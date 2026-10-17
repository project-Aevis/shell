#include "appmenumodel.h"

#include <QAction>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusServiceWatcher>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QMenu>
#include <QQmlEngine>
#include <QDesktopServices>
#include <QUrl>
#include <QDir>
#include <QStandardPaths>
#include <QProcess>
#include <QKeySequence>
#include <QDebug>

#include "../libdbusmenuqt/dbusmenuimporter.h"
#include "core/services/activity.h"
#include "core/wayland/kwinwaylandinterface.h"
#include "menuimporter.h"

class CDBusMenuImporter : public DBusMenuImporter
{
public:
    CDBusMenuImporter(const QString &service, const QString &path, QObject *parent)
        : DBusMenuImporter(service, path, parent)
    {
    }

protected:
    QIcon iconForName(const QString &name) override
    {
        return QIcon::fromTheme(name);
    }
};

static void launchFileManager(const QStringList &args)
{
    if (!QProcess::startDetached(QStringLiteral("aevis-filemanager"), args)) {
        QProcess::startDetached(QStringLiteral("cutefish-filemanager"), args);
    }
}

static void launchSettings(const QStringList &args)
{
    if (!QProcess::startDetached(QStringLiteral("aevis-settings"), args)) {
        QProcess::startDetached(QStringLiteral("cutefish-settings"), args);
    }
}

AppMenuModel::AppMenuModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_menuAvailable(false)
    , m_menu(nullptr)
    , m_activityMenu(nullptr)
    , m_activityAction(nullptr)
    , m_finderMenu(nullptr)
    , m_genericAppMenu(nullptr)
    , m_activity(Activity::self())
    , m_serviceWatcher(new QDBusServiceWatcher(this))
{
    m_activityMenu = new QMenu;
    m_activityAction = new QAction(tr("Finder"), this);
    m_activityAction->setMenu(m_activityMenu);

    setupFinderMenu();
    rebuildActivityMenu(tr("Finder"), true);

    connect(this, &AppMenuModel::modelNeedsUpdate, this, [this] {
        if (!m_updatePending) {
            m_updatePending = true;
            QMetaObject::invokeMethod(this, "update", Qt::QueuedConnection);
        }
    });

    // On Wayland KWin exposes the active window and its exported application
    // menu together, so no client-side window identifier is needed.
    KWinWaylandInterface *kwin = KWinWaylandInterface::instance();
    connect(kwin, &KWinWaylandInterface::activeWindowChanged, this, &AppMenuModel::onActiveWindowChanged, Qt::QueuedConnection);
    connect(kwin, &KWinWaylandInterface::clientChanged, this, &AppMenuModel::onActiveWindowChanged, Qt::QueuedConnection);
    connect(kwin, &KWinWaylandInterface::clientRemoved, this, &AppMenuModel::onActiveWindowChanged, Qt::QueuedConnection);

    // Compatibility exporters may register after the window is mapped. Their
    // numeric token is not a Wayland window ID, so only use the exporter's
    // D-Bus process ID to associate the menu with KWin's active window.
    if (MenuImporter *importer = MenuImporter::instance()) {
        connect(importer, &MenuImporter::WindowRegistered, this,
                [this](uint, const QString &, const QDBusObjectPath &) { onActiveWindowChanged(); }, Qt::QueuedConnection);
        connect(importer, &MenuImporter::WindowUnregistered, this,
                [this](uint) { onActiveWindowChanged(); }, Qt::QueuedConnection);
    }

    connect(m_activity, &Activity::titleChanged, this,
            &AppMenuModel::updateActivityVisibility);
    onActiveWindowChanged();

    m_serviceWatcher->setConnection(QDBusConnection::sessionBus());
    // if our current DBus connection gets lost, close the menu
    // we'll select the new menu when the focus changes
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceUnregistered, this, [this](const QString &serviceName) {
        if (serviceName == m_serviceName) {
            setMenuAvailable(false);
            emit modelNeedsUpdate();
        }
    });
}

AppMenuModel::~AppMenuModel()
{
    if (m_activityAction)
        m_activityAction->setMenu(nullptr);
    delete m_activityMenu;
    delete m_finderMenu;
    delete m_genericAppMenu;
}

bool AppMenuModel::menuAvailable() const
{
    return m_menuAvailable;
}

void AppMenuModel::setMenuAvailable(bool set)
{
    if (m_menuAvailable != set) {
        m_menuAvailable = set;
        emit menuAvailableChanged();
    }
}

bool AppMenuModel::visible() const
{
    return m_visible;
}

void AppMenuModel::setVisible(bool visible)
{
    if (m_visible != visible) {
        m_visible = visible;
        emit visibleChanged();
    }
}

int AppMenuModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    if (!m_visible) {
        return 0;
    }

    if (m_isFinder) {
        return 1 + (m_finderMenu ? m_finderMenu->actions().count() : 0);
    }

    if (m_menuAvailable && m_menu && !m_menu->actions().isEmpty()) {
        return 1 + m_menu->actions().count();
    }

    if (m_genericAppMenu) {
        return 1 + m_genericAppMenu->actions().count();
    }

    return 1;
}

void AppMenuModel::update()
{
    beginResetModel();
    endResetModel();
    m_updatePending = false;
}

void AppMenuModel::onActiveWindowChanged()
{
    KWinWaylandInterface *kwin = KWinWaylandInterface::instance();
    const KWinWaylandClient client = kwin->client(kwin->activeWindow());

    QString serviceName = client.appMenuServiceName;
    QString objectPath = client.appMenuObjectPath;

    if ((serviceName.isEmpty() || objectPath.isEmpty()) && client.pid > 0) {
        if (MenuImporter *importer = MenuImporter::instance()) {
            serviceName = importer->serviceForPid(static_cast<uint>(client.pid));
            objectPath = importer->pathForPid(static_cast<uint>(client.pid));
        }
    }

    if (!serviceName.isEmpty() && !objectPath.isEmpty()) {
        setMenuAvailable(true);
        updateApplicationMenu(serviceName, objectPath);
    } else {
        setMenuAvailable(false);
    }

    updateActivityVisibility();
    emit modelNeedsUpdate();
}

void AppMenuModel::updateActivityVisibility()
{
    QString title = m_activity->title();
    bool isFinder = false;
    if (title.isEmpty()
        || title.compare(tr("Finder"), Qt::CaseInsensitive) == 0
        || title.compare(QStringLiteral("Finder"), Qt::CaseInsensitive) == 0
        || title.compare(QStringLiteral("Desktop"), Qt::CaseInsensitive) == 0) {
        title = tr("Finder");
        isFinder = true;
    }

    m_isFinder = isFinder;
    const bool titleChanged = (m_activityAction->text() != title);
    if (titleChanged) {
        m_activityAction->setText(title);
    }

    rebuildActivityMenu(title, isFinder);

    if (!m_visible) {
        setVisible(true);
    }

    emit modelNeedsUpdate();
}

QHash<int, QByteArray> AppMenuModel::roleNames() const
{
    QHash<int, QByteArray> roleNames;
    roleNames[MenuRole] = QByteArrayLiteral("activeMenu");
    roleNames[ActionRole] = QByteArrayLiteral("activeActions");
    return roleNames;
}

QVariant AppMenuModel::data(const QModelIndex &index, int role) const
{
    QAction *action = actionAt(index.row());
    if (!action) {
        return QVariant();
    }

    if (role == MenuRole) { // TODO this should be Qt::DisplayRole
        return action->text();
    } else if (role == ActionRole) {
        return QVariant::fromValue((void *)action);
    }

    return QVariant();
}

QObject *AppMenuModel::menuAt(int row) const
{
    QAction *action = actionAt(row);
    if (!action)
        return nullptr;

    QMenu *menu = action->menu();

    // Both synthetic and imported menus are owned by C++.
    if (menu)
        QQmlEngine::setObjectOwnership(menu, QQmlEngine::CppOwnership);

    return menu;
}

void AppMenuModel::trigger(int row)
{
    QAction *action = actionAt(row);
    if (!action || action->menu())
        return;

    action->trigger();
}

QAction *AppMenuModel::actionAt(int row) const
{
    if (!m_visible || row < 0)
        return nullptr;

    if (row == 0)
        return m_activityAction;

    const int actionIndex = row - 1;

    if (m_isFinder) {
        if (!m_finderMenu)
            return nullptr;
        const auto actions = m_finderMenu->actions();
        if (actionIndex >= actions.count())
            return nullptr;
        return actions.at(actionIndex);
    }

    if (m_menuAvailable && m_menu && !m_menu->actions().isEmpty()) {
        const auto actions = m_menu->actions();
        if (actionIndex >= actions.count())
            return nullptr;
        return actions.at(actionIndex);
    }

    if (m_genericAppMenu) {
        const auto actions = m_genericAppMenu->actions();
        if (actionIndex >= actions.count())
            return nullptr;
        return actions.at(actionIndex);
    }

    return nullptr;
}

int AppMenuModel::rowForAction(QAction *action) const
{
    if (!action || !m_visible)
        return -1;

    if (action == m_activityAction)
        return 0;

    if (m_isFinder) {
        if (!m_finderMenu)
            return -1;
        const int idx = m_finderMenu->actions().indexOf(action);
        return idx < 0 ? -1 : idx + 1;
    }

    if (m_menuAvailable && m_menu && !m_menu->actions().isEmpty()) {
        const int idx = m_menu->actions().indexOf(action);
        return idx < 0 ? -1 : idx + 1;
    }

    if (m_genericAppMenu) {
        const int idx = m_genericAppMenu->actions().indexOf(action);
        return idx < 0 ? -1 : idx + 1;
    }

    return -1;
}

void AppMenuModel::updateApplicationMenu(const QString &serviceName, const QString &menuObjectPath)
{
    if (m_serviceName == serviceName && m_menuObjectPath == menuObjectPath) {
        if (m_importer) {
            QMetaObject::invokeMethod(m_importer, "updateMenu", Qt::QueuedConnection);
        }
        return;
    }

    m_serviceName = serviceName;
    m_serviceWatcher->setWatchedServices(QStringList({m_serviceName}));

    m_menuObjectPath = menuObjectPath;

    m_menu = nullptr;

    if (m_importer) {
        m_importer->deleteLater();
    }

    m_importer = new CDBusMenuImporter(serviceName, menuObjectPath, this);
    QMetaObject::invokeMethod(m_importer, "updateMenu", Qt::QueuedConnection);

    connect(m_importer.data(), &DBusMenuImporter::menuUpdated, this, [=](QMenu *menu) {
        m_menu = m_importer->menu();
        if (m_menu.isNull() || menu != m_menu) {
            return;
        }

        // cache first layer of sub menus, which we'll be popping up
        const auto actions = m_menu->actions();
        for (QAction *a : actions) {
            // signal dataChanged when the action changes
            connect(a, &QAction::changed, this, [this, a] {
                const int actionRow = rowForAction(a);
                if (actionRow >= 0) {
                    const QModelIndex modelIdx = index(actionRow, 0);
                    emit dataChanged(modelIdx, modelIdx);
                }
            });

            connect(a, &QAction::destroyed, this, &AppMenuModel::modelNeedsUpdate);

            if (a->menu()) {
                m_importer->updateMenu(a->menu());
            }
        }

        setMenuAvailable(true);
        emit modelNeedsUpdate();
    });

    connect(m_importer.data(), &DBusMenuImporter::actionActivationRequested, this, [this](QAction *action) {
        // TODO submenus
        if (!m_menuAvailable || !m_menu) {
            return;
        }

        const auto actions = m_menu->actions();
        auto it = std::find(actions.begin(), actions.end(), action);
        if (it != actions.end()) {
            Q_EMIT requestActivateIndex((it - actions.begin()) + 1);
        }
    });
}

void AppMenuModel::setupFinderMenu()
{
    m_finderMenu = new QMenu;

    // 1. File Menu
    QMenu *fileMenu = new QMenu(m_finderMenu);
    QAction *fileAction = m_finderMenu->addAction(tr("File"));
    fileAction->setMenu(fileMenu);

    QAction *newFinderWindow = fileMenu->addAction(tr("New Finder Window"));
    newFinderWindow->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_N));
    connect(newFinderWindow, &QAction::triggered, this, []() {
        launchFileManager({QDir::homePath()});
    });

    QAction *newFolder = fileMenu->addAction(tr("New Folder"));
    newFolder->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_N));
    connect(newFolder, &QAction::triggered, this, []() {
        QString desktop = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
        QDir dir(desktop);
        if (dir.exists()) {
            QString name = tr("New Folder");
            int counter = 1;
            while (dir.exists(name)) {
                name = tr("New Folder %1").arg(++counter);
            }
            dir.mkdir(name);
        }
    });

    fileMenu->addSeparator();

    QAction *closeWindow = fileMenu->addAction(tr("Close Window"));
    closeWindow->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_W));
    connect(closeWindow, &QAction::triggered, m_activity, &Activity::close);

    // 2. Edit Menu
    QMenu *editMenu = new QMenu(m_finderMenu);
    QAction *editAction = m_finderMenu->addAction(tr("Edit"));
    editAction->setMenu(editMenu);

    QAction *undoAction = editMenu->addAction(tr("Undo"));
    undoAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_Z));
    undoAction->setEnabled(false);

    QAction *redoAction = editMenu->addAction(tr("Redo"));
    redoAction->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_Z));
    redoAction->setEnabled(false);

    editMenu->addSeparator();

    QAction *cutAction = editMenu->addAction(tr("Cut"));
    cutAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_X));

    QAction *copyAction = editMenu->addAction(tr("Copy"));
    copyAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_C));

    QAction *pasteAction = editMenu->addAction(tr("Paste"));
    pasteAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_V));

    QAction *selectAllAction = editMenu->addAction(tr("Select All"));
    selectAllAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_A));

    // 3. View Menu
    QMenu *viewMenu = new QMenu(m_finderMenu);
    QAction *viewAction = m_finderMenu->addAction(tr("View"));
    viewAction->setMenu(viewMenu);

    QAction *asIcons = viewMenu->addAction(tr("as Icons"));
    asIcons->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_1));

    QAction *asList = viewMenu->addAction(tr("as List"));
    asList->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_2));

    QAction *asColumns = viewMenu->addAction(tr("as Columns"));
    asColumns->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_3));

    viewMenu->addSeparator();

    viewMenu->addAction(tr("Clean Up"));

    QAction *showViewOpts = viewMenu->addAction(tr("Show View Options"));
    showViewOpts->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_J));

    // 4. Go Menu
    QMenu *goMenu = new QMenu(m_finderMenu);
    QAction *goAction = m_finderMenu->addAction(tr("Go"));
    goAction->setMenu(goMenu);

    QAction *backAction = goMenu->addAction(tr("Back"));
    backAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_BracketLeft));

    QAction *forwardAction = goMenu->addAction(tr("Forward"));
    forwardAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_BracketRight));

    QAction *enclosingFolder = goMenu->addAction(tr("Enclosing Folder"));
    enclosingFolder->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_Up));

    goMenu->addSeparator();

    QAction *goApps = goMenu->addAction(tr("Applications"));
    goApps->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_A));
    connect(goApps, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl::fromLocalFile(QStringLiteral("/usr/share/applications")));
    });

    QAction *goDesktop = goMenu->addAction(tr("Desktop"));
    goDesktop->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_D));
    connect(goDesktop, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl::fromLocalFile(QStandardPaths::writableLocation(QStandardPaths::DesktopLocation)));
    });

    QAction *goDocs = goMenu->addAction(tr("Documents"));
    goDocs->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_O));
    connect(goDocs, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl::fromLocalFile(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)));
    });

    QAction *goDownloads = goMenu->addAction(tr("Downloads"));
    goDownloads->setShortcut(QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_L));
    connect(goDownloads, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl::fromLocalFile(QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)));
    });

    QAction *goHome = goMenu->addAction(tr("Home"));
    goHome->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_H));
    connect(goHome, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl::fromLocalFile(QDir::homePath()));
    });

    goMenu->addSeparator();

    QAction *goTrash = goMenu->addAction(tr("Trash"));
    connect(goTrash, &QAction::triggered, this, []() {
        launchFileManager({QStringLiteral("trash:///")});
    });

    // 5. Window Menu
    QMenu *windowMenu = new QMenu(m_finderMenu);
    QAction *windowAction = m_finderMenu->addAction(tr("Window"));
    windowAction->setMenu(windowMenu);

    QAction *minAction = windowMenu->addAction(tr("Minimize"));
    minAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_M));
    connect(minAction, &QAction::triggered, m_activity, &Activity::minimize);

    QAction *zoomAction = windowMenu->addAction(tr("Zoom"));
    connect(zoomAction, &QAction::triggered, m_activity, &Activity::maximize);

    windowMenu->addSeparator();

    QAction *bringAll = windowMenu->addAction(tr("Bring All to Front"));
    connect(bringAll, &QAction::triggered, m_activity, &Activity::showAll);

    // 6. Help Menu
    QMenu *helpMenu = new QMenu(m_finderMenu);
    QAction *helpAction = m_finderMenu->addAction(tr("Help"));
    helpAction->setMenu(helpMenu);

    QAction *helpItem = helpMenu->addAction(tr("Help"));
    connect(helpItem, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl(QStringLiteral("https://aevis.org")));
    });

    // Fallback menu for regular applications without DBus menus (macOS style)
    m_genericAppMenu = new QMenu;

    // 1. File Menu
    QMenu *genericFileMenu = new QMenu(m_genericAppMenu);
    QAction *genFileAction = m_genericAppMenu->addAction(tr("File"));
    genFileAction->setMenu(genericFileMenu);

    QAction *gCloseWin = genericFileMenu->addAction(tr("Close Window"));
    gCloseWin->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_W));
    connect(gCloseWin, &QAction::triggered, m_activity, &Activity::close);

    // 2. Edit Menu
    QMenu *genericEditMenu = new QMenu(m_genericAppMenu);
    QAction *genEditAction = m_genericAppMenu->addAction(tr("Edit"));
    genEditAction->setMenu(genericEditMenu);

    QAction *gUndo = genericEditMenu->addAction(tr("Undo"));
    gUndo->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_Z));

    QAction *gRedo = genericEditMenu->addAction(tr("Redo"));
    gRedo->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_Z));

    genericEditMenu->addSeparator();

    QAction *gCut = genericEditMenu->addAction(tr("Cut"));
    gCut->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_X));

    QAction *gCopy = genericEditMenu->addAction(tr("Copy"));
    gCopy->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_C));

    QAction *gPaste = genericEditMenu->addAction(tr("Paste"));
    gPaste->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_V));

    QAction *gSelectAll = genericEditMenu->addAction(tr("Select All"));
    gSelectAll->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_A));

    // 3. View Menu
    QMenu *genericViewMenu = new QMenu(m_genericAppMenu);
    QAction *genViewAction = m_genericAppMenu->addAction(tr("View"));
    genViewAction->setMenu(genericViewMenu);

    QAction *gFullScreen = genericViewMenu->addAction(tr("Enter Full Screen"));
    gFullScreen->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_F11));
    connect(gFullScreen, &QAction::triggered, m_activity, &Activity::maximize);

    // 4. Window Menu
    QMenu *genericWindowMenu = new QMenu(m_genericAppMenu);
    QAction *genWinAction = m_genericAppMenu->addAction(tr("Window"));
    genWinAction->setMenu(genericWindowMenu);

    QAction *gMinAction = genericWindowMenu->addAction(tr("Minimize"));
    gMinAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_M));
    connect(gMinAction, &QAction::triggered, m_activity, &Activity::minimize);

    QAction *gZoomAction = genericWindowMenu->addAction(tr("Zoom"));
    connect(gZoomAction, &QAction::triggered, m_activity, &Activity::maximize);

    genericWindowMenu->addSeparator();

    QAction *gBringAll = genericWindowMenu->addAction(tr("Bring All to Front"));
    connect(gBringAll, &QAction::triggered, m_activity, &Activity::showAll);

    // 5. Help Menu
    QMenu *genericHelpMenu = new QMenu(m_genericAppMenu);
    QAction *genHelpAction = m_genericAppMenu->addAction(tr("Help"));
    genHelpAction->setMenu(genericHelpMenu);

    QAction *gHelpItem = genericHelpMenu->addAction(tr("%1 Help").arg(tr("Application")));
    connect(gHelpItem, &QAction::triggered, this, []() {
        QDesktopServices::openUrl(QUrl(QStringLiteral("https://aevis.org")));
    });
}

void AppMenuModel::rebuildActivityMenu(const QString &title, bool isFinder)
{
    if (!m_activityMenu)
        return;

    m_activityMenu->clear();

    if (isFinder) {
        QAction *aboutAction = m_activityMenu->addAction(tr("About Finder"));
        connect(aboutAction, &QAction::triggered, this, []() {
            launchSettings({QStringLiteral("-m"), QStringLiteral("about")});
        });

        QAction *settingsAction = m_activityMenu->addAction(tr("Settings..."));
        settingsAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_Comma));
        connect(settingsAction, &QAction::triggered, this, []() {
            launchSettings({});
        });

        m_activityMenu->addSeparator();

        QAction *emptyTrashAction = m_activityMenu->addAction(tr("Empty Trash..."));
        connect(emptyTrashAction, &QAction::triggered, this, []() {
            launchFileManager({QStringLiteral("-e")});
        });

        m_activityMenu->addSeparator();

        QAction *hideOthersAction = m_activityMenu->addAction(tr("Hide Others"));
        hideOthersAction->setShortcut(QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_H));
        connect(hideOthersAction, &QAction::triggered, m_activity, &Activity::hideOthers);

        QAction *showAllAction = m_activityMenu->addAction(tr("Show All"));
        connect(showAllAction, &QAction::triggered, m_activity, &Activity::showAll);
    } else {
        QAction *aboutAction = m_activityMenu->addAction(tr("About %1").arg(title));
        connect(aboutAction, &QAction::triggered, this, []() {
            launchSettings({QStringLiteral("-m"), QStringLiteral("about")});
        });

        QAction *settingsAction = m_activityMenu->addAction(tr("Settings..."));
        settingsAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_Comma));
        connect(settingsAction, &QAction::triggered, this, []() {
            launchSettings({});
        });

        m_activityMenu->addSeparator();

        QAction *hideAction = m_activityMenu->addAction(tr("Hide %1").arg(title));
        hideAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_H));
        connect(hideAction, &QAction::triggered, m_activity, &Activity::minimize);

        QAction *hideOthersAction = m_activityMenu->addAction(tr("Hide Others"));
        hideOthersAction->setShortcut(QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_H));
        connect(hideOthersAction, &QAction::triggered, m_activity, &Activity::hideOthers);

        QAction *showAllAction = m_activityMenu->addAction(tr("Show All"));
        connect(showAllAction, &QAction::triggered, m_activity, &Activity::showAll);

        m_activityMenu->addSeparator();

        QAction *quitAction = m_activityMenu->addAction(tr("Quit %1").arg(title));
        quitAction->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_Q));
        connect(quitAction, &QAction::triggered, m_activity, &Activity::quit);
    }
}

