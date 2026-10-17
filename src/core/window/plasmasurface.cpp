#include "core/window/plasmasurface.h"
#include "core/wayland/kwinwaylandinterface.h"

#include <QEvent>
#include <QPlatformSurfaceEvent>
#include <QWindow>
#include <QDebug>

#include <KWayland/Client/surface.h>

using namespace KWayland::Client;

PlasmaSurface::PlasmaSurface(QWindow *window)
    : QObject(window)
    , m_window(window)
{
    m_window->installEventFilter(this);
    connect(KWinWaylandInterface::instance(), &KWinWaylandInterface::plasmaShellReady,
            this, &PlasmaSurface::attach);
}

PlasmaSurface::~PlasmaSurface()
{
    delete m_surface;
}

void PlasmaSurface::setRole(Role role)
{
    m_role = role;
    m_hasRole = true;
    attach();
}

void PlasmaSurface::setPanelBehavior(PanelBehavior behavior)
{
    if (m_panelBehavior == behavior)
        return;

    m_panelBehavior = behavior;

    if (m_surface && (m_role == Role::Panel))
        m_surface->setPanelBehavior(behavior);
}

void PlasmaSurface::setPanelTakesFocus(bool takesFocus)
{
    if (m_panelTakesFocus == takesFocus)
        return;

    m_panelTakesFocus = takesFocus;

    if (m_surface && m_role == Role::Panel)
        m_surface->setPanelTakesFocus(takesFocus);
}

QPoint PlasmaSurface::position() const
{
    return m_position;
}

void PlasmaSurface::setPosition(const QPoint &position)
{
    m_position = position;

    if (m_surface)
        m_surface->setPosition(position);
}

void PlasmaSurface::attach()
{
    if (!m_hasRole)
        return;

    PlasmaShell *shell = KWinWaylandInterface::instance()->plasmaShell();
    if (!shell) {
        qWarning() << "No org_kde_plasma_shell; cannot set the surface role of"
                   << m_window->title();
        return;
    }

    Surface *surface = Surface::fromWindow(m_window);
    wl_surface *native = surface ? static_cast<wl_surface *>(*surface) : nullptr;
    if (!native)
        return;

    if (native == m_wlSurface && m_surface) {
        m_surface->setRole(m_role);
        if (m_role == Role::Panel) {
            m_surface->setPanelBehavior(m_panelBehavior);
            m_surface->setPanelTakesFocus(m_panelTakesFocus);
        }
        m_surface->setSkipTaskbar(true);
        m_surface->setSkipSwitcher(true);
        m_surface->setPosition(m_position);
        return;
    }

    delete m_surface;
    m_wlSurface = native;
    m_surface = shell->createSurface(surface, this);
    if (!m_surface)
        return;

    m_surface->setRole(m_role);

    if (m_role == Role::Panel) {
        m_surface->setPanelBehavior(m_panelBehavior);
        m_surface->setPanelTakesFocus(m_panelTakesFocus);
    }

    m_surface->setSkipTaskbar(true);
    m_surface->setSkipSwitcher(true);
    m_surface->setPosition(m_position);
}

void PlasmaSurface::detach()
{
    delete m_surface;
    m_surface = nullptr;
    m_wlSurface = nullptr;
}

bool PlasmaSurface::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != m_window)
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
    case QEvent::PlatformSurface:
        switch (static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType()) {
        case QPlatformSurfaceEvent::SurfaceCreated:
            // The wl_surface exists from here on and nothing has been
            // committed on it yet. Claiming the role and the position now
            // rather than on the first expose is what keeps KWin from running
            // its placement pass over the surface: a window that already knows
            // where it goes is left alone, while one that does not gets shrunk
            // to the work area first and has to be resized back.
            attach();
            break;
        case QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed:
            detach();
            break;
        }
        break;
    case QEvent::Expose:
        // A newly exposed window has a fresh wl_surface.
        if (m_window->isExposed())
            attach();
        break;
    default:
        break;
    }

    return QObject::eventFilter(watched, event);
}
