/*
 * Copyright (C) 2021 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * Author:     revenmartin <revenmartin@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "applicationmodel.h"
#include "core/services/applicationresolver.h"
#include "applicationlauncher.h"
#include "applicationregistry.h"
#include "applicationruntime.h"
#include "desktopentry.h"
#include "launcher/launcher.h"

#include <QFileInfo>
#include <QSettings>
#include <QCoreApplication>
#include <QTimer>
#include <QDir>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusConnectionInterface>

#include <algorithm>
#include <utility>

// The dock's built-in launcher button. It is not backed by a .desktop file.
static const char *kLauncherId = "cutefish-launcher";

// Let the application close its windows on its own before the runtime
// terminates whatever is left of it.
static const int kQuitGraceMs = 3000;

class PinnedFilterProxyModel : public QSortFilterProxyModel
{
public:
    PinnedFilterProxyModel(bool showPinned, QObject *parent = nullptr)
        : QSortFilterProxyModel(parent), m_showPinned(showPinned)
    {
        setDynamicSortFilter(true);
    }

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override {
        QModelIndex index = sourceModel()->index(sourceRow, 0, sourceParent);
        bool isPinned = sourceModel()->data(index, ApplicationModel::IsPinnedRole).toBool();
        return isPinned == m_showPinned;
    }

private:
    bool m_showPinned;
};

ApplicationModel::ApplicationModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_kwin(KWinWaylandInterface::instance())
{
    m_pinnedModel = new PinnedFilterProxyModel(true, this);
    m_pinnedModel->setSourceModel(this);

    m_unpinnedModel = new PinnedFilterProxyModel(false, this);
    m_unpinnedModel->setSourceModel(this);
    connect(m_kwin, &KWinWaylandInterface::clientAdded, this, [this](quint64 wid) {
        if (m_kwin->isAcceptableWindow(wid))
            onWindowAdded(wid);
    });
    connect(m_kwin, &KWinWaylandInterface::clientRemoved, this, &ApplicationModel::onWindowRemoved);
    connect(m_kwin, &KWinWaylandInterface::clientChanged, this, [this](quint64 wid) {
        // A window that stops being acceptable -- unmapped, or turned into one
        // of ours -- leaves the dock the same way a closed one does.
        if (m_kwin->isAcceptableWindow(wid))
            onWindowChanged(wid);
        else
            onWindowRemoved(wid);
    });
    connect(m_kwin, &KWinWaylandInterface::activeWindowChanged, this, &ApplicationModel::onActiveChanged);

    ApplicationRegistry *registry = ApplicationRegistry::instance();
    connect(registry, &ApplicationRegistry::applicationsChanged,
            this, &ApplicationModel::onApplicationsChanged);
    initPinnedApplications();
    m_pinsInitialized = true;
    if (!registry->loading())
        onApplicationsChanged();

    QTimer::singleShot(100, this, [this] {
        loadExistingWindows();
        m_initialWindowsLoaded = true;
    });
}

void ApplicationModel::setLauncher(Launcher *launcher)
{
    m_launcher = launcher;
}

int ApplicationModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)

    return m_appItems.size();
}

QHash<int, QByteArray> ApplicationModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[AppIdRole] = "appId";
    roles[IconNameRole] = "iconName";
    roles[VisibleNameRole] = "visibleName";
    roles[ActiveRole] = "isActive";
    roles[WindowCountRole] = "windowCount";
    roles[WindowIdsRole] = "windowIds";
    roles[IsPinnedRole] = "isPinned";
    roles[DesktopFileRole] = "desktopFile";
    roles[FixedItemRole] = "fixed";
    roles[AnimationTokenRole] = "animationToken";
    return roles;
}

QVariant ApplicationModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid())
        return QVariant();

    ApplicationItem *item = m_appItems.at(index.row());

    switch (role) {
    case AppIdRole:
        return item->id;
    case IconNameRole:
        return item->iconName;
    case VisibleNameRole:
        return item->visibleName;
    case ActiveRole:
        return item->isActive;
    case WindowCountRole:
        return item->wids.count();
    case WindowIdsRole: {
        QStringList windowIds;
        for (quint64 wid : item->wids)
            windowIds.append(QString::number(wid));
        return windowIds;
    }
    case IsPinnedRole:
        return item->isPinned;
    case DesktopFileRole:
        return item->desktopPath;
    case FixedItemRole:
        return item->fixed;
    case AnimationTokenRole:
        return item->animationToken;
    default:
        return QVariant();
    }

    return QVariant();
}

void ApplicationModel::updateFromDesktopEntry(ApplicationItem *item,
                                               DesktopEntry *entry)
{
    if (!item || !entry)
        return;

    item->id = entry->id();
    if (!entry->icon().isEmpty())
        item->iconName = entry->icon();
    if (item->id == QLatin1String("cutefish-filemanager") || item->id == QLatin1String("aevis-filemanager"))
        item->iconName = item->id;
    if (!entry->name().isEmpty())
        item->visibleName = entry->name();
    if (!entry->exec().isEmpty())
        item->exec = entry->exec();
    item->desktopPath = entry->path();
}

void ApplicationModel::addItem(const QString &desktopFile)
{
    ApplicationRegistry *registry = ApplicationRegistry::instance();
    DesktopEntry *entry = registry->byPath(desktopFile);
    if (!entry)
        entry = registry->byId(desktopFile);
    if (!entry)
        return;

    ApplicationItem *existsItem = findItemByDesktop(entry->path());

    if (existsItem) {
        existsItem->isPinned = true;
        updateFromDesktopEntry(existsItem, entry);
        handleDataChangedFromItem(existsItem);
        savePinAndUnPinList();
        return;
    }

    int launcherIndex = indexOf(QLatin1String(kLauncherId));
    int insertPos = (launcherIndex != -1) ? launcherIndex : rowCount();
    beginInsertRows(QModelIndex(), insertPos, insertPos);
    ApplicationItem *item = new ApplicationItem;
    updateFromDesktopEntry(item, entry);
    item->isPinned = true;
    item->animationToken = animationTokenForNewItem();

    m_appItems.insert(insertPos, item);
    endInsertRows();

    savePinAndUnPinList();

    emit itemAdded();
    emit countChanged();
}

void ApplicationModel::removeItem(const QString &desktopFile)
{
    DesktopEntry *entry = ApplicationRegistry::instance()->byPath(desktopFile);
    if (!entry)
        entry = ApplicationRegistry::instance()->byId(desktopFile);

    ApplicationItem *item = entry ? findItemByDesktop(entry->path())
                                  : findItemByDesktop(desktopFile);
    if (!item)
        item = findItemById(desktopFile);

    if (item) {
        ApplicationModel::unPin(item->id);
    }
}

int ApplicationModel::animationTokenForNewItem()
{
    return m_initialWindowsLoaded ? ++m_nextAnimationToken : 0;
}

bool ApplicationModel::desktopContains(const QString &desktopFile)
{
    if (desktopFile.isEmpty())
        return false;

    DesktopEntry *entry = ApplicationRegistry::instance()->byPath(desktopFile);
    if (!entry)
        entry = ApplicationRegistry::instance()->byId(desktopFile);
    if (entry)
        return findItemByDesktop(entry->path()) != nullptr;

    if (findItemById(desktopFile))
        return true;
    return findItemByDesktop(desktopFile) != nullptr;
}

bool ApplicationModel::isDesktopPinned(const QString &desktopFile)
{
    DesktopEntry *entry = ApplicationRegistry::instance()->byPath(desktopFile);
    if (!entry)
        entry = ApplicationRegistry::instance()->byId(desktopFile);
    ApplicationItem *item = entry ? findItemByDesktop(entry->path())
                                  : findItemByDesktop(desktopFile);
    if (!item)
        item = findItemById(desktopFile);

    if (item) {
        return item->isPinned;
    }

    return false;
}

void ApplicationModel::clicked(const QString &id)
{
    if (id == kLauncherId || id == "launchpad" || id == "aevis-launcher") {
        if (m_launcher) {
            m_launcher->toggle();
        } else {
            const QString launcherService = (QDBusConnection::sessionBus().interface() &&
                                             QDBusConnection::sessionBus().interface()->isServiceRegistered(QStringLiteral("org.aevis.Launcher")))
                ? QStringLiteral("org.aevis.Launcher")
                : QStringLiteral("com.cutefish.Launcher");
            QDBusInterface iface(launcherService, "/Launcher", launcherService, QDBusConnection::sessionBus());
            iface.call("toggle");
        }
        return;
    }

    ApplicationItem *item = findItemById(id);

    if (!item)
        return;

    // Application Item that has been pinned,
    // We need to open it.
    if (item->wids.isEmpty()) {
        // open application
        openNewInstance(item->id);
    }
    // Multiple windows have been opened and need to switch between them,
    // The logic here needs to be improved.
    else if (item->wids.count() > 1) {
        item->currentActive++;

        if (item->currentActive == item->wids.count())
            item->currentActive = 0;

        m_kwin->focusWindow(item->wids.at(item->currentActive));
    } else if (m_kwin->activeWindow() == item->wids.first()) {
        m_kwin->minimizeWindow(item->wids.first());
    } else {
        m_kwin->focusWindow(item->wids.first());
    }
}

void ApplicationModel::raiseWindow(const QString &id)
{
    ApplicationItem *item = findItemById(id);

    if (!item)
        return;

    m_kwin->focusWindow(item->wids.at(item->currentActive));
}

bool ApplicationModel::openNewInstance(const QString &appId)
{
    ApplicationItem *item = findItemById(appId);

    if (!item)
        return false;

    // The launcher lives in this very process now, so open it directly rather
    // than trying to run a binary that no longer exists.
    if (item->id == QLatin1String(kLauncherId)) {
        if (!m_launcher)
            return false;

        m_launcher->toggle();
        return true;
    }

    if (DesktopEntry *entry = ApplicationRegistry::instance()->byId(item->id))
        return entry->launch();

    if (item->exec.isEmpty())
        return ApplicationLauncher::startDetached({appId});

    return ApplicationLauncher::startDetached(DesktopEntry::parseExec(item->exec));
}

bool ApplicationModel::openAction(const QString &appId, const QString &actionCmd)
{
    if (actionCmd.isEmpty())
        return openNewInstance(appId);

    return ApplicationLauncher::startDetached(DesktopEntry::parseExec(actionCmd));
}

void ApplicationModel::closeAllByAppId(const QString &appId)
{
    ApplicationItem *item = findItemById(appId);

    if (!item)
        return;

    for (quint64 wid : item->wids) {
        m_kwin->closeWindow(wid);
    }
}

QVariantList ApplicationModel::windowsForApp(const QString &appId)
{
    QVariantList list;
    ApplicationItem *item = findItemById(appId);
    if (!item || !m_kwin)
        return list;

    const quint64 activeWid = m_kwin->activeWindow();

    for (quint64 wid : item->wids) {
        KWinWaylandClient c = m_kwin->client(wid);
        QVariantMap map;
        map[QStringLiteral("wid")] = QString::number(wid);
        map[QStringLiteral("uuid")] = c.uuid;
        map[QStringLiteral("title")] = c.title.trimmed().isEmpty() ? item->visibleName : c.title.trimmed();
        map[QStringLiteral("active")] = (wid == activeWid);
        map[QStringLiteral("minimized")] = c.hidden;
        map[QStringLiteral("iconName")] = item->iconName;
        list.append(map);
    }
    return list;
}

void ApplicationModel::activateWindow(const QString &widStr)
{
    bool ok = false;
    quint64 wid = widStr.toULongLong(&ok);
    if (ok && m_kwin) {
        m_kwin->restoreWindow(wid);
        m_kwin->focusWindow(wid);
    }
}

void ApplicationModel::closeWindow(const QString &widStr)
{
    bool ok = false;
    quint64 wid = widStr.toULongLong(&ok);
    if (ok && m_kwin) {
        m_kwin->closeWindow(wid);
    }
}

void ApplicationModel::quit(const QString &appId)
{
    ApplicationItem *item = findItemById(appId);

    if (!item)
        return;

    QList<quint32> pids;
    for (quint64 wid : item->wids) {
        const quint32 pid = static_cast<quint32>(m_kwin->client(wid).pid);

        // Never terminate the shell itself.
        if (pid == 0 || pid == static_cast<quint32>(QCoreApplication::applicationPid()))
            continue;

        if (!pids.contains(pid))
            pids.append(pid);
    }

    QString runtimeId;
    if (DesktopEntry *entry = ApplicationRegistry::instance()->byPath(item->desktopPath))
        runtimeId = entry->id();

    // Close the windows first so the application can still prompt to save.
    closeAllByAppId(appId);

    // Then terminate what is left, including an application that closed its
    // windows but keeps running. Only the pids that were on screen when quit
    // was asked for: falling back to the application id here would also hit
    // an instance the user started again during the grace period.
    QTimer::singleShot(kQuitGraceMs, this, [pids, runtimeId] {
        ApplicationRuntime *runtime = ApplicationRuntime::instance();

        for (quint32 pid : pids)
            runtime->quitByPid(pid);

        if (pids.isEmpty() && !runtimeId.isEmpty())
            runtime->quitApplication(runtimeId);
    });
}

void ApplicationModel::pin(const QString &appId)
{
    ApplicationItem *item = findItemById(appId);

    if (!item)
        return;

    item->isPinned = true;

    handleDataChangedFromItem(item);
    savePinAndUnPinList();
}

void ApplicationModel::unPin(const QString &appId)
{
    ApplicationItem *item = findItemById(appId);

    if (!item)
        return;

    item->isPinned = false;
    handleDataChangedFromItem(item);

    // Need to be removed after unpin
    if (item->wids.isEmpty()) {
        int index = indexOf(item->id);
        if (index != -1) {
            beginRemoveRows(QModelIndex(), index, index);
            m_appItems.removeAll(item);
            endRemoveRows();

            emit itemRemoved();
            emit countChanged();
        }
    }

    savePinAndUnPinList();
}

void ApplicationModel::move(int from, int to)
{
    if (from == to)
        return;

    m_appItems.move(from, to);

    if (from < to)
        beginMoveRows(QModelIndex(), from, from, QModelIndex(), to + 1);
    else
        beginMoveRows(QModelIndex(), from, from, QModelIndex(), to);

    endMoveRows();
}

ApplicationItem *ApplicationModel::findItemByWId(quint64 wid)
{
    for (ApplicationItem *item : std::as_const(m_appItems)) {
        for (quint64 winId : std::as_const(item->wids)) {
            if (winId == wid)
                return item;
        }
    }

    return nullptr;
}

ApplicationItem *ApplicationModel::findItemById(const QString &id)
{
    if (id.isEmpty())
        return nullptr;

    const QString cleanId = id.section('.', -1).toLower();

    for (ApplicationItem *item : std::as_const(m_appItems)) {
        if (item->id.compare(id, Qt::CaseInsensitive) == 0)
            return item;

        const QString itemCleanId = item->id.section('.', -1).toLower();
        if (itemCleanId.compare(cleanId, Qt::CaseInsensitive) == 0)
            return item;

        if (!item->desktopPath.isEmpty()) {
            const QString baseName = QFileInfo(item->desktopPath).completeBaseName().toLower();
            if (baseName.compare(cleanId, Qt::CaseInsensitive) == 0 || baseName.compare(id, Qt::CaseInsensitive) == 0)
                return item;
        }
    }

    return nullptr;
}

ApplicationItem *ApplicationModel::findItemByDesktop(const QString &desktop)
{
    if (desktop.isEmpty())
        return nullptr;

    const QString normalizedDesktop = QFileInfo(desktop).absoluteFilePath();
    for (ApplicationItem *item : std::as_const(m_appItems)) {
        if (!item->desktopPath.isEmpty()
            && QFileInfo(item->desktopPath).absoluteFilePath() == normalizedDesktop)
            return item;
    }

    return nullptr;
}

bool ApplicationModel::contains(const QString &id)
{
    return findItemById(id) != nullptr;
}

int ApplicationModel::indexOf(const QString &id)
{
    for (int i = 0; i < m_appItems.size(); ++i) {
        if (m_appItems.at(i)->id == id)
            return i;
    }

    return -1;
}

void ApplicationModel::initPinnedApplications()
{
    const QString userOrg = QFile::exists(QDir::homePath() + QStringLiteral("/.config/aevis/dock_pinned.conf")) ? "aevis" : "cutefishos";
    QSettings settings(QSettings::UserScope, userOrg, "dock_pinned");
    const QString sysDock = QFile::exists(QStringLiteral("/etc/aevis-dock-list.conf"))
        ? QStringLiteral("/etc/aevis-dock-list.conf")
        : QStringLiteral("/etc/cutefish-dock-list.conf");
    QSettings systemSettings(sysDock, QSettings::IniFormat);
    QSettings *set = (QFile(settings.fileName()).exists()) ? &settings
                                                           : &systemSettings;
    QStringList groups = set->childGroups();
    QList<QPair<int, QString>> orderedGroups;
    for (const QString &group : groups) {
        set->beginGroup(group);
        orderedGroups.append({set->value("Index").toInt(), group});
        set->endGroup();
    }
    std::sort(orderedGroups.begin(), orderedGroups.end(),
              [](const auto &left, const auto &right) { return left.first < right.first; });

    // Finder (macOS position 0)
    ApplicationItem *finderItem = new ApplicationItem;
    const QString fmDesktop = QFile::exists(QStringLiteral("/usr/share/applications/aevis-filemanager.desktop"))
        ? QStringLiteral("/usr/share/applications/aevis-filemanager.desktop")
        : QStringLiteral("/usr/share/applications/cutefish-filemanager.desktop");
    const QString fmExec = QFile::exists(QStringLiteral("/usr/bin/aevis-filemanager"))
        ? QStringLiteral("aevis-filemanager")
        : QStringLiteral("cutefish-filemanager");
    const QString fmId = QFile::exists(QStringLiteral("/usr/share/applications/aevis-filemanager.desktop"))
        ? QStringLiteral("aevis-filemanager")
        : QStringLiteral("cutefish-filemanager");

    finderItem->id = fmId;
    finderItem->desktopPath = fmDesktop;
    finderItem->iconName = "file-manager";
    finderItem->visibleName = tr("Finder");
    finderItem->exec = fmExec;
    finderItem->isPinned = true;
    finderItem->fixed = true;
    if (DesktopEntry *finderEntry = ApplicationRegistry::instance()->byId(fmId)) {
        updateFromDesktopEntry(finderItem, finderEntry);
        finderItem->visibleName = tr("Finder");
        finderItem->fixed = true;
    } else if (DesktopEntry *legacyEntry = ApplicationRegistry::instance()->byId("cutefish-filemanager")) {
        updateFromDesktopEntry(finderItem, legacyEntry);
        finderItem->visibleName = tr("Finder");
        finderItem->fixed = true;
    }
    m_appItems.append(finderItem);

    // Pinned apps. Older configurations store an absolute path, while newer
    // ones store the desktop id as the group name; both remain supported.
    for (const auto &[index, group] : orderedGroups) {
        Q_UNUSED(index)
        set->beginGroup(group);
        const QString path = set->value("DesktopPath").toString();
        const QString savedIcon = set->value("Icon").toString();
        const QString savedName = set->value("VisibleName").toString();
        const QString savedExec = set->value("Exec").toString();
        DesktopEntry *entry = ApplicationRegistry::instance()->byPath(path);
        if (!entry)
            entry = ApplicationRegistry::instance()->byId(group);
        if (!entry) {
            QString altGroup = group;
            if (altGroup.startsWith(QStringLiteral("cutefish-")))
                altGroup.replace(0, 9, QStringLiteral("aevis-"));
            else if (altGroup.startsWith(QStringLiteral("aevis-")))
                altGroup.replace(0, 6, QStringLiteral("cutefish-"));
            entry = ApplicationRegistry::instance()->byId(altGroup);
        }

        if (entry && !findItemById(entry->id())) {
            beginInsertRows(QModelIndex(), rowCount(), rowCount());
            ApplicationItem *item = new ApplicationItem;
            updateFromDesktopEntry(item, entry);
            if (item->iconName.isEmpty())
                item->iconName = savedIcon;
            if (item->visibleName.isEmpty())
                item->visibleName = savedName;
            if (item->exec.isEmpty())
                item->exec = savedExec;
            item->isPinned = true;
            item->animationToken = animationTokenForNewItem();
            m_appItems.append(item);
            endInsertRows();

            emit itemAdded();
            emit countChanged();
        } else if (!entry && !path.isEmpty() && QFile::exists(path)
                   && !findItemById(group)) {
            beginInsertRows(QModelIndex(), rowCount(), rowCount());
            ApplicationItem *item = new ApplicationItem;
            item->id = group;
            item->desktopPath = path;
            item->iconName = savedIcon;
            item->visibleName = savedName;
            item->exec = savedExec;
            item->isPinned = true;
            item->animationToken = animationTokenForNewItem();
            m_appItems.append(item);
            endInsertRows();

            emit itemAdded();
            emit countChanged();
        }
        set->endGroup();
    }

    // Launcher / Launchpad (Anchored on the right side of pinned apps, right before the dock divider)
    beginInsertRows(QModelIndex(), m_appItems.count(), m_appItems.count());
    ApplicationItem *launcherItem = new ApplicationItem;
    launcherItem->id = kLauncherId;
    launcherItem->exec = QString();
    launcherItem->iconName = "qrc:/dock/images/launchpad.svg";
    launcherItem->visibleName = tr("Launchpad");
    launcherItem->isPinned = true;
    launcherItem->fixed = true;
    m_appItems.append(launcherItem);
    endInsertRows();
}

void ApplicationModel::onApplicationsChanged()
{
    if (!m_pinsInitialized) {
        initPinnedApplications();
        m_pinsInitialized = true;
    }

    ApplicationRegistry *registry = ApplicationRegistry::instance();
    for (ApplicationItem *item : std::as_const(m_appItems)) {
        if (item->fixed)
            continue;

        DesktopEntry *entry = registry->byId(item->id);
        if (!entry && !item->desktopPath.isEmpty())
            entry = registry->byPath(item->desktopPath);
        for (quint64 wid : std::as_const(item->wids)) {
            const QString path = desktopPathFor(wid);
            if (path.isEmpty())
                continue;

            if (DesktopEntry *windowEntry = registry->byPath(path)) {
                entry = windowEntry;
                break;
            }
        }
        if (!entry)
            continue;

        updateFromDesktopEntry(item, entry);
        handleDataChangedFromItem(item);
    }
}

void ApplicationModel::savePinAndUnPinList()
{
    const QString userOrg = QFile::exists(QDir::homePath() + QStringLiteral("/.config/aevis/dock_pinned.conf")) ? "aevis" : "cutefishos";
    QSettings settings(QSettings::UserScope, userOrg, "dock_pinned");
    settings.clear();

    int index = 0;

    for (ApplicationItem *item : m_appItems) {
        if (item->isPinned) {
            settings.beginGroup(item->id);
            settings.setValue("Index", index);
            settings.setValue("Icon", item->iconName);
            settings.setValue("VisibleName", item->visibleName);
            settings.setValue("Exec", item->exec);
            settings.setValue("DesktopPath", item->desktopPath);
            settings.endGroup();
            ++index;
        }
    }

    settings.sync();
}

void ApplicationModel::handleDataChangedFromItem(ApplicationItem *item)
{
    if (!item)
        return;

    QModelIndex idx = index(m_appItems.indexOf(item), 0, QModelIndex());

    if (idx.isValid()) {
        emit dataChanged(idx, idx);
    }
}

void ApplicationModel::loadExistingWindows()
{
    m_kwin->refresh();

    for (const KWinWaylandClient &client : m_kwin->clients()) {
        if (m_kwin->isAcceptableWindow(client.id))
            onWindowAdded(client.id);
    }
}

QString ApplicationModel::desktopPathFor(quint64 wid) const
{
    const KWinWaylandClient client = m_kwin->client(wid);
    const QString id = KWinWaylandInterface::appId(client);
    return ApplicationResolver::instance()->desktopPathFromMetadata(
        id, static_cast<quint32>(client.pid), id);
}

void ApplicationModel::onWindowAdded(quint64 wid)
{
    if (findItemByWId(wid))
        return;

    if (!m_kwin->isAcceptableWindow(wid))
        return;

    const KWinWaylandClient client = m_kwin->client(wid);
    const QString id = KWinWaylandInterface::appId(client);

    if (id.isEmpty())
        return;

    const bool active = m_kwin->activeWindow() == wid;
    const QString desktopPath = desktopPathFor(wid);
    DesktopEntry *entry = ApplicationRegistry::instance()->byPath(desktopPath);
    ApplicationItem *matchedItem = findItemByDesktop(desktopPath);

    if (!matchedItem)
        matchedItem = findItemById(id);

    // Use matched item
    if (matchedItem != nullptr) {
        if (!matchedItem->wids.contains(wid))
            matchedItem->wids.append(wid);

        matchedItem->isActive = active;

        if (entry && matchedItem->desktopPath.isEmpty())
            updateFromDesktopEntry(matchedItem, entry);

        handleDataChangedFromItem(matchedItem);
    }
    // New item needs to be added.
    else {
        int launcherIndex = indexOf(QLatin1String(kLauncherId));
        int insertPos = (launcherIndex != -1) ? launcherIndex : rowCount();
        beginInsertRows(QModelIndex(), insertPos, insertPos);
        ApplicationItem *item = new ApplicationItem;
        item->id = id;
        item->iconName = id.toLower();
        item->visibleName = client.title.isEmpty() ? id : client.title;
        item->isActive = active;
        item->wids.append(wid);
        item->desktopPath = desktopPath;
        item->animationToken = animationTokenForNewItem();

        if (entry)
            updateFromDesktopEntry(item, entry);

        m_appItems.insert(insertPos, item);
        endInsertRows();

        emit itemAdded();
        emit countChanged();
    }
}

void ApplicationModel::onWindowChanged(quint64 wid)
{
    if (!m_kwin->isAcceptableWindow(wid)) {
        onWindowRemoved(wid);
        return;
    }

    ApplicationItem *item = findItemByWId(wid);
    if (!item) {
        onWindowAdded(wid);
        return;
    }

    const KWinWaylandClient client = m_kwin->client(wid);
    if (client.id == 0)
        return;

    const QString id = KWinWaylandInterface::appId(client);

    if (item->desktopPath.isEmpty()) {
        if (!client.title.isEmpty())
            item->visibleName = client.title;
        if (!id.isEmpty())
            item->iconName = id.toLower();
    }
    if (!id.isEmpty() && item->id.isEmpty())
        item->id = id;
    item->isActive = m_kwin->activeWindow() == wid;
    handleDataChangedFromItem(item);
}

void ApplicationModel::onWindowRemoved(quint64 wid)
{
    ApplicationItem *item = findItemByWId(wid);

    if (!item)
        return;

    // Remove from wid list.
    item->wids.removeOne(wid);

    if (item->currentActive >= item->wids.size())
        item->currentActive = 0;

    handleDataChangedFromItem(item);

    if (item->wids.isEmpty()) {
        // If it is not fixed to the dock, need to remove it.
        if (!item->isPinned) {
            int index = indexOf(item->id);

            if (index == -1)
                return;

            beginRemoveRows(QModelIndex(), index, index);
            m_appItems.removeAll(item);
            endRemoveRows();

            emit itemRemoved();
            emit countChanged();
        }
    }
}

void ApplicationModel::onActiveChanged(quint64 wid)
{
    // Using this method will cause the listview scrollbar to reset.
    // beginResetModel();

    for (ApplicationItem *item : m_appItems) {
        if (item->isActive != item->wids.contains(wid)) {
            item->isActive = item->wids.contains(wid);

            QModelIndex idx = index(indexOf(item->id), 0, QModelIndex());
            if (idx.isValid()) {
                emit dataChanged(idx, idx);
            }
        }
    }
}
