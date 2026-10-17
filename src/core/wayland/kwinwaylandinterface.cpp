#include "kwinwaylandinterface.h"

#include <QGuiApplication>
#include <QCoreApplication>
#include <QScreen>
#include <QTimer>
#include <QtGui/qguiapplication_platform.h>

#include <KWayland/Client/compositor.h>
#include <KWayland/Client/connection_thread.h>
#include <KWayland/Client/plasmashell.h>
#include <KWayland/Client/shm_pool.h>
#include <KWayland/Client/surface.h>

#include "layershell.h"
#include <KWayland/Client/plasmawindowmanagement.h>
#include <KWayland/Client/plasmavirtualdesktop.h>
#include <KWayland/Client/registry.h>

using namespace KWayland::Client;

static KWinWaylandInterface *INSTANCE = nullptr;

KWinWaylandInterface *KWinWaylandInterface::instance()
{
    if (!INSTANCE)
        INSTANCE = new KWinWaylandInterface;

    return INSTANCE;
}

KWinWaylandInterface::KWinWaylandInterface(QObject *parent)
    : QObject(parent)
{
    if (!QGuiApplication::platformName().contains(QStringLiteral("wayland")))
        return;

    m_connection = ConnectionThread::fromApplication(this);
    if (!m_connection)
        return;

    m_available = true;
    m_registry = new Registry(this);
    m_registry->create(m_connection);
    connect(m_registry, &Registry::plasmaShellAnnounced,
            this, &KWinWaylandInterface::setupPlasmaShell);
    connect(m_registry, &Registry::interfaceAnnounced,
            this, &KWinWaylandInterface::setupInterface);
    connect(m_registry, &Registry::compositorAnnounced, this, [this](quint32 name, quint32 version) {
        if (!m_compositor)
            m_compositor = m_registry->createCompositor(name, version, this);
    });
    connect(m_registry, &Registry::shmAnnounced, this, [this](quint32 name, quint32 version) {
        if (!m_shmPool)
            m_shmPool = m_registry->createShmPool(name, version, this);
    });
    connect(m_registry, &Registry::plasmaWindowManagementAnnounced,
            this, &KWinWaylandInterface::setupWindowManagement);
    connect(m_registry, &Registry::plasmaVirtualDesktopManagementAnnounced,
            this, &KWinWaylandInterface::setupVirtualDesktopManagement);
    m_registry->setup();

    // The panels ask for their plasma-shell surface while they are being
    // constructed, so the interface has to be bound before this returns
    // instead of on the next event loop iteration.
    m_connection->roundtrip();
}

PlasmaShell *KWinWaylandInterface::plasmaShell() const
{
    return m_plasmaShell;
}

Compositor *KWinWaylandInterface::compositor() const
{
    return m_compositor;
}

ShmPool *KWinWaylandInterface::shmPool() const
{
    return m_shmPool;
}

zwlr_layer_shell_v1 *KWinWaylandInterface::layerShell() const
{
    return m_layerShell;
}

void KWinWaylandInterface::setupInterface(const QByteArray &interface, quint32 name, quint32 version)
{
    // KWayland has no wrapper for wlr-layer-shell, so it is bound straight off
    // the registry it already owns.
    if (m_layerShell || interface != QByteArrayLiteral("zwlr_layer_shell_v1"))
        return;

    const quint32 wanted = qMin(version, quint32(zwlr_layer_shell_v1_interface.version));
    m_layerShell = static_cast<zwlr_layer_shell_v1 *>(
        wl_registry_bind(m_registry->registry(), name, &zwlr_layer_shell_v1_interface, wanted));

    if (m_layerShell)
        emit layerShellReady();
    else
        qWarning() << "Could not bind zwlr_layer_shell_v1; panels will not reserve work area";
}

void KWinWaylandInterface::setupPlasmaShell(quint32 name, quint32 version)
{
    if (m_plasmaShell)
        return;

    m_plasmaShell = m_registry->createPlasmaShell(name, version, this);
    if (!m_plasmaShell || !m_plasmaShell->isValid()) {
        qWarning() << "KWin PlasmaShell is unavailable";
        m_plasmaShell = nullptr;
        return;
    }

    emit plasmaShellReady();
}

bool KWinWaylandInterface::available() const
{
    return m_available;
}

QList<KWinWaylandClient> KWinWaylandInterface::clients() const
{
    return m_clients.values();
}

KWinWaylandClient KWinWaylandInterface::client(quint64 id) const
{
    return m_clients.value(id);
}

QString KWinWaylandInterface::appId(const KWinWaylandClient &client)
{
    return client.className.isEmpty() ? client.initialClass : client.className;
}

bool KWinWaylandInterface::isAcceptableWindow(quint64 id) const
{
    const KWinWaylandClient window = m_clients.value(id);
    if (window.id == 0 || !window.mapped)
        return false;

    // Never accept windows belonging to the shell process itself
    const qint64 shellPid = static_cast<qint64>(QCoreApplication::applicationPid());
    if (shellPid > 0 && window.pid == shellPid)
        return false;

    // Never accept windows explicitly flagged to skip taskbar
    if (window.skipTaskbar)
        return false;

    const QString name = appId(window).toLower();
    const QString cls = window.className.toLower();
    const QString res = window.resourceName.toLower();
    const QString title = window.title.trimmed();

    auto isShellId = [](const QString &s) {
        if (s.isEmpty())
            return false;
        return s == QLatin1String("aevis-shell")
            || s == QLatin1String("cutefish-shell")
            || s == QLatin1String("aevis-dock")
            || s == QLatin1String("cutefish-dock")
            || s == QLatin1String("aevis-launcher")
            || s == QLatin1String("cutefish-launcher")
            || s == QLatin1String("aevis-statusbar")
            || s == QLatin1String("cutefish-statusbar")
            || s == QLatin1String("aevis-desktop")
            || s == QLatin1String("cutefish-desktop")
            || s == QLatin1String("aevis-screenlocker")
            || s == QLatin1String("cutefish-screenlocker")
            || s == QLatin1String("org.aevis.shell")
            || s == QLatin1String("org.cutefish.shell")
            || s == QLatin1String("org.kde.xwaylandvideobridge")
            || s == QLatin1String("org.kde.plasmashell")
            || s == QLatin1String("plasmashell")
            || s == QLatin1String("krunner");
    };

    if (isShellId(name) || isShellId(cls) || isShellId(res))
        return false;

    if (title == QLatin1String("Desktop")
        || title == QLatin1String("Dock")
        || title == QLatin1String("Status Bar")
        || title == QLatin1String("Launcher")
        || title == QLatin1String("aevis-shell")
        || title == QLatin1String("cutefish-shell")) {
        return false;
    }

    if (name.isEmpty() && title.isEmpty())
        return false;

    return true;
}

quint64 KWinWaylandInterface::activeWindow() const
{
    return m_activeWindow;
}

quint64 KWinWaylandInterface::windowForPid(qint64 pid, const QString &title) const
{
    for (auto it = m_clients.cbegin(); it != m_clients.cend(); ++it) {
        if (it->pid != pid)
            continue;
        if (!title.isEmpty() && it->initialTitle != title && it->title != title)
            continue;
        return it.key();
    }

    return 0;
}

void KWinWaylandInterface::roundtrip()
{
    if (m_connection)
        m_connection->roundtrip();
}

void KWinWaylandInterface::refresh()
{
    for (auto it = m_windows.cbegin(); it != m_windows.cend(); ++it)
        updateWindow(it.value());
    updateActiveWindow();
}

quint64 KWinWaylandInterface::idFor(PlasmaWindow *window)
{
    return reinterpret_cast<quint64>(window);
}

void KWinWaylandInterface::setupWindowManagement(quint32 name, quint32 version)
{
    if (m_windowManagement)
        return;

    m_windowManagement = m_registry->createPlasmaWindowManagement(name, qMin(version, quint32(20)), this);
    if (!m_windowManagement || !m_windowManagement->isValid()) {
        qWarning() << "KWin PlasmaWindowManagement is unavailable";
        delete m_windowManagement;
        m_windowManagement = nullptr;

        static int retryAttempts = 0;
        if (retryAttempts < 3) {
            ++retryAttempts;
            QTimer::singleShot(500, this, [this, name, version]() {
                if (!m_windowManagement) {
                    qDebug() << "Retrying KWin PlasmaWindowManagement connection...";
                    setupWindowManagement(name, version);
                }
            });
        }
        return;
    }

    connect(m_windowManagement, &PlasmaWindowManagement::windowCreated,
            this, &KWinWaylandInterface::addWindow);
    connect(m_windowManagement, &PlasmaWindowManagement::activeWindowChanged,
            this, &KWinWaylandInterface::updateActiveWindow);
    connect(m_windowManagement, &PlasmaWindowManagement::showingDesktopChanged,
            this, &KWinWaylandInterface::refresh);

    for (PlasmaWindow *window : m_windowManagement->windows())
        addWindow(window);

    emit windowManagementReady();
    qInfo() << "KWin PlasmaWindowManagement connected with"
            << m_windows.size() << "windows";
}

void KWinWaylandInterface::setupVirtualDesktopManagement(quint32 name, quint32 version)
{
    if (m_virtualDesktopManagement)
        return;

    m_virtualDesktopManagement = m_registry->createPlasmaVirtualDesktopManagement(name, version, this);
    if (!m_virtualDesktopManagement || !m_virtualDesktopManagement->isValid()) {
        delete m_virtualDesktopManagement;
        m_virtualDesktopManagement = nullptr;
        return;
    }

    auto updateDesktops = [this]() {
        for (PlasmaVirtualDesktop *desktop : m_virtualDesktopManagement->desktops()) {
            if (desktop->isActive()) {
                m_activeDesktopId = desktop->id();
            }
            connect(desktop, &PlasmaVirtualDesktop::activated, this, [this, desktop]() {
                m_activeDesktopId = desktop->id();
                refresh();
            }, Qt::UniqueConnection);
            connect(desktop, &PlasmaVirtualDesktop::deactivated, this, [this]() {
                refresh();
            }, Qt::UniqueConnection);
        }
    };

    connect(m_virtualDesktopManagement, &PlasmaVirtualDesktopManagement::desktopCreated, this, [updateDesktops](const QString &, quint32) {
        updateDesktops();
    });
    connect(m_virtualDesktopManagement, &PlasmaVirtualDesktopManagement::desktopRemoved, this, [this, updateDesktops](const QString &) {
        updateDesktops();
        refresh();
    });

    updateDesktops();
}

KWinWaylandClient KWinWaylandInterface::toClient(PlasmaWindow *window) const
{
    KWinWaylandClient client;
    client.id = idFor(window);
    client.uuid = QString::fromUtf8(window->uuid());
    client.mapped = true;
    client.className = window->appId();
    client.resourceName = window->resourceName();
    if (client.className.isEmpty())
        client.className = client.resourceName;
    client.initialClass = client.className;
    client.title = window->title();
    client.initialTitle = client.title;
    client.pid = window->pid();
    client.geometry = window->geometry();
    client.plasmaVirtualDesktops = window->plasmaVirtualDesktops();
    client.onAllDesktops = window->isOnAllDesktops();
    client.hidden = window->isMinimized();
    client.skipTaskbar = window->skipTaskbar();
    client.skipSwitcher = window->skipSwitcher();
    client.maximized = window->isMaximized();
    client.fullscreen = window->isFullscreen() ? 1 : 0;
    client.fullscreenClient = client.fullscreen;
    client.appMenuServiceName = window->applicationMenuServiceName();
    client.appMenuObjectPath = window->applicationMenuObjectPath();
    return client;
}

void KWinWaylandInterface::addWindow(PlasmaWindow *window)
{
    if (!window)
        return;

    const quint64 id = idFor(window);
    if (m_windows.contains(id))
        return;

    m_windows.insert(id, window);
    m_clients.insert(id, toClient(window));

    qDebug() << "KWin window added:" << id << window->appId()
             << window->title() << window->pid();

    connect(window, &PlasmaWindow::titleChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::appIdChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::activeChanged, this, [this, window] {
        updateWindow(window);
        updateActiveWindow();
    });
    connect(window, &PlasmaWindow::minimizedChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::maximizedChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::fullscreenChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::geometryChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::skipTaskbarChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::applicationMenuChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::plasmaVirtualDesktopEntered, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::plasmaVirtualDesktopLeft, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::onAllDesktopsChanged, this, [this, window] { updateWindow(window); });
    connect(window, &PlasmaWindow::unmapped, this, [this, id] { removeWindow(id); });

    emit clientAdded(id);
    updateActiveWindow();
}

void KWinWaylandInterface::updateWindow(PlasmaWindow *window)
{
    if (!window)
        return;

    const quint64 id = idFor(window);
    if (!m_windows.contains(id))
        return;

    const KWinWaylandClient updated = toClient(window);
    if (m_clients.value(id) == updated)
        return;

    m_clients.insert(id, updated);
    emit clientChanged(id);
}

void KWinWaylandInterface::removeWindow(quint64 id)
{
    if (!m_windows.contains(id))
        return;

    m_windows.remove(id);
    m_clients.remove(id);
    emit clientRemoved(id);
    updateActiveWindow();
}

void KWinWaylandInterface::updateActiveWindow()
{
    quint64 active = 0;
    for (auto it = m_windows.cbegin(); it != m_windows.cend(); ++it) {
        if (it.value()->isActive()) {
            active = it.key();
            break;
        }
    }

    if (active == m_activeWindow)
        return;

    m_activeWindow = active;
    emit activeWindowChanged(active);
}

PlasmaWindow *KWinWaylandInterface::window(quint64 id) const
{
    return m_windows.value(id, nullptr);
}

void KWinWaylandInterface::focusWindow(quint64 id)
{
    if (PlasmaWindow *target = window(id))
        target->requestActivate();
}

void KWinWaylandInterface::setMinimizedGeometry(quint64 id, Surface *panel,
                                                  const QRect &geometry)
{
    if (!panel)
        return;

    if (PlasmaWindow *target = window(id))
        target->setMinimizedGeometry(panel, geometry);
}

void KWinWaylandInterface::minimizeWindow(quint64 id)
{
    if (PlasmaWindow *target = window(id))
        target->requestToggleMinimized();
}

void KWinWaylandInterface::restoreWindow(quint64 id)
{
    if (PlasmaWindow *target = window(id); target && target->isMinimized())
        target->requestToggleMinimized();
}

void KWinWaylandInterface::closeWindow(quint64 id)
{
    if (PlasmaWindow *target = window(id))
        target->requestClose();
}

void KWinWaylandInterface::toggleMaximize(quint64 id)
{
    if (PlasmaWindow *target = window(id))
        target->requestToggleMaximized();
}

void KWinWaylandInterface::startMove(quint64 id)
{
    if (PlasmaWindow *target = window(id))
        target->requestMove();
}

bool KWinWaylandInterface::isOnCurrentDesktop(const KWinWaylandClient &client) const
{
    if (client.onAllDesktops || client.plasmaVirtualDesktops.isEmpty() || m_activeDesktopId.isEmpty())
        return true;
    return client.plasmaVirtualDesktops.contains(m_activeDesktopId);
}

bool KWinWaylandInterface::hasFullscreenWindow(const QRect &screenRect) const
{
    if (m_windowManagement && m_windowManagement->isShowingDesktop())
        return false;

    for (const auto &client : m_clients) {
        if (!isAcceptableWindow(client.id))
            continue;
        if (!client.mapped || client.hidden || client.skipTaskbar)
            continue;
        if (!isOnCurrentDesktop(client))
            continue;

        if (client.fullscreen != 0) {
            if (!screenRect.isEmpty() && client.geometry.isValid() && !client.geometry.isEmpty()) {
                if (client.geometry.intersects(screenRect))
                    return true;
            } else {
                return true;
            }
        }
    }

    return false;
}

bool KWinWaylandInterface::hasWindowTouching(const QRect &rect) const
{
    if (rect.isEmpty())
        return false;

    if (m_windowManagement && m_windowManagement->isShowingDesktop())
        return false;

    // Direct intersection with dock window bounding rect + 4px margin
    const QRect touchRect = rect.adjusted(-4, -4, 4, 4);

    for (const auto &client : m_clients) {
        if (!isAcceptableWindow(client.id))
            continue;
        if (!client.mapped || client.hidden || client.skipTaskbar)
            continue;
        if (!isOnCurrentDesktop(client))
            continue;

        // If client is fullscreen or maximized on this output, it covers the dock area
        if (client.fullscreen != 0 || client.maximized) {
            return true;
        }

        if (client.geometry.isValid() && !client.geometry.isEmpty()) {
            if (client.geometry.intersects(touchRect)) {
                return true;
            }
        }
    }

    return false;
}

