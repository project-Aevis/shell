#include "strutspacer.h"
#include "kwinwaylandinterface.h"

#include <QDebug>
#include <QImage>

#include <KWayland/Client/buffer.h>
#include <KWayland/Client/compositor.h>
#include <KWayland/Client/region.h>
#include <KWayland/Client/shm_pool.h>
#include <KWayland/Client/surface.h>

#include <wayland-client-protocol.h>

#include "layershell.h"

using namespace KWayland::Client;

static const zwlr_layer_surface_v1_listener s_listener = {
    StrutSpacer::configureCallback,
    StrutSpacer::closedCallback,
};

static quint32 anchorFor(Qt::Edge edge)
{
    // The spacer stretches along the edge it is anchored to, so that the strip
    // KWin keeps clear spans the whole output rather than a one pixel column.
    switch (edge) {
    case Qt::TopEdge:
        return ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT
             | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    case Qt::BottomEdge:
        return ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT
             | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    case Qt::LeftEdge:
        return ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP
             | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;
    case Qt::RightEdge:
        return ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT | ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP
             | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;
    }

    return 0;
}

StrutRegistry *StrutRegistry::self()
{
    static StrutRegistry registry;
    return &registry;
}

void StrutRegistry::add(StrutSpacer *spacer)
{
    if (!m_spacers.contains(spacer))
        m_spacers.append(spacer);
}

void StrutRegistry::remove(StrutSpacer *spacer)
{
    m_spacers.removeOne(spacer);
    emit changed();
}

void StrutRegistry::notify()
{
    emit changed();
}

QRect StrutRegistry::availableGeometry(QScreen *screen) const
{
    if (!screen)
        return QRect();

    QRect rect = screen->geometry();

    for (const StrutSpacer *spacer : m_spacers) {
        if (spacer->m_screen != screen || spacer->m_thickness <= 0)
            continue;

        switch (spacer->m_edge) {
        case Qt::TopEdge:
            rect.setTop(rect.top() + spacer->m_thickness);
            break;
        case Qt::BottomEdge:
            rect.setBottom(rect.bottom() - spacer->m_thickness);
            break;
        case Qt::LeftEdge:
            rect.setLeft(rect.left() + spacer->m_thickness);
            break;
        case Qt::RightEdge:
            rect.setRight(rect.right() - spacer->m_thickness);
            break;
        }
    }

    return rect;
}

StrutSpacer::StrutSpacer(QObject *parent)
    : QObject(parent)
{
    StrutRegistry::self()->add(this);

    // The layer shell may not have been announced yet when a panel is built.
    connect(KWinWaylandInterface::instance(), &KWinWaylandInterface::layerShellReady,
            this, &StrutSpacer::update);
}

StrutSpacer::~StrutSpacer()
{
    StrutRegistry::self()->remove(this);
    destroySurface();
}

void StrutSpacer::setEdge(Qt::Edge edge)
{
    if (m_edge == edge)
        return;

    m_edge = edge;
    StrutRegistry::self()->notify();

    // The anchor cannot be changed on a mapped surface without a new configure
    // round trip; starting over is simpler and happens only when the user moves
    // the dock to another screen edge.
    destroySurface();
    update();
}

void StrutSpacer::setThickness(int thickness)
{
    thickness = qMax(0, thickness);
    if (m_thickness == thickness)
        return;

    m_thickness = thickness;
    StrutRegistry::self()->notify();
    update();
}

void StrutSpacer::setScreen(QScreen *screen)
{
    if (m_screen == screen)
        return;

    m_screen = screen;
    StrutRegistry::self()->notify();
    destroySurface();
    update();
}

void StrutSpacer::setWaylandSurfaceEnabled(bool enabled)
{
    if (m_waylandSurfaceEnabled == enabled)
        return;

    m_waylandSurfaceEnabled = enabled;
    if (!m_waylandSurfaceEnabled) {
        destroySurface();
    } else {
        update();
    }
}

void StrutSpacer::update()
{
    if (!m_waylandSurfaceEnabled) {
        destroySurface();
        return;
    }

    if (m_layerSurface) {
        // Releasing the area by dropping the exclusive zone rather than by
        // unmapping the surface. Unmapping makes the compositor treat it as a
        // panel that went away: KWin's sliding-popups effect animates layer
        // surfaces off their edge and forces blur and background contrast on
        // them while it does, which turned this invisible spacer into a
        // blurred strip sliding across the screen every time the launcher
        // opened.
        zwlr_layer_surface_v1_set_exclusive_zone(m_layerSurface, m_thickness);
        if (m_thickness > 0) {
            const bool horizontal = m_edge == Qt::TopEdge || m_edge == Qt::BottomEdge;
            zwlr_layer_surface_v1_set_size(m_layerSurface,
                                           horizontal ? 0 : m_thickness,
                                           horizontal ? m_thickness : 0);
        }
        wl_surface_commit(*m_surface);
        return;
    }

    if (m_thickness <= 0)
        return;

    KWinWaylandInterface *wayland = KWinWaylandInterface::instance();
    zwlr_layer_shell_v1 *layerShell = wayland->layerShell();
    Compositor *compositor = wayland->compositor();
    if (!layerShell || !compositor)
        return;

    m_surface = compositor->createSurface(this);
    if (!m_surface || !m_surface->isValid()) {
        qWarning() << "Could not create the strut spacer surface";
        return;
    }

    wl_output *output = nullptr;
    if (m_screen) {
        // Letting the compositor pick is fine on a single output; naming one
        // would need the wl_output of that QScreen, which KWayland only knows
        // for outputs it bound itself.
    }

    m_layerSurface = zwlr_layer_shell_v1_get_layer_surface(layerShell,
                                                          *m_surface,
                                                          output,
                                                          ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM,
                                                          "cutefish-strut");
    if (!m_layerSurface) {
        qWarning() << "Could not create the strut spacer layer surface";
        destroySurface();
        return;
    }

    zwlr_layer_surface_v1_add_listener(m_layerSurface, &s_listener, this);

    const bool horizontal = m_edge == Qt::TopEdge || m_edge == Qt::BottomEdge;
    zwlr_layer_surface_v1_set_anchor(m_layerSurface, anchorFor(m_edge));
    zwlr_layer_surface_v1_set_size(m_layerSurface,
                                   horizontal ? 0 : m_thickness,
                                   horizontal ? m_thickness : 0);
    zwlr_layer_surface_v1_set_exclusive_zone(m_layerSurface, m_thickness);
    zwlr_layer_surface_v1_set_keyboard_interactivity(m_layerSurface, 0);

    // Nothing must ever land on this surface: it sits behind the panel and
    // covers a strip of the desktop.
    clearInputRegion();
    wl_surface_commit(*m_surface);
}

void StrutSpacer::clearInputRegion()
{
    Compositor *compositor = KWinWaylandInterface::instance()->compositor();
    if (!m_surface || !compositor)
        return;

    // Not setInputRegion(nullptr): that *resets* the region, and an unset
    // input region is an infinite one. The spacer would then eat every click
    // along the whole screen edge, which is what kept the desktop from
    // reacting to the left and right of the dock. An explicitly empty region
    // is what makes the surface click-through.
    std::unique_ptr<Region> empty = compositor->createRegion(QRegion());
    m_surface->setInputRegion(empty.get());
}

void StrutSpacer::handleConfigure(quint32 serial, quint32 width, quint32 height)
{
    zwlr_layer_surface_v1_ack_configure(m_layerSurface, serial);

    const QSize size(qMax<int>(1, width), qMax<int>(1, height));
    ShmPool *pool = KWinWaylandInterface::instance()->shmPool();
    if (!pool)
        return;

    if (m_bufferSize != size) {
        QImage image(size, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);

        auto buffer = pool->createBuffer(image);
        if (!buffer) {
            qWarning() << "Could not allocate the strut spacer buffer";
            return;
        }

        m_bufferSize = size;
        m_surface->attachBuffer(buffer);
    }

    // An empty input region has to be re-applied after every configure, since
    // it is double buffered along with the rest of the surface state.
    clearInputRegion();
    m_surface->damage(QRect(QPoint(0, 0), size));
    wl_surface_commit(*m_surface);
}

void StrutSpacer::destroySurface()
{
    if (m_layerSurface) {
        zwlr_layer_surface_v1_destroy(m_layerSurface);
        m_layerSurface = nullptr;
    }

    delete m_surface;
    m_surface = nullptr;
    m_bufferSize = QSize();
}

void StrutSpacer::configureCallback(void *data, zwlr_layer_surface_v1 *surface,
                                    quint32 serial, quint32 width, quint32 height)
{
    Q_UNUSED(surface)
    static_cast<StrutSpacer *>(data)->handleConfigure(serial, width, height);
}

void StrutSpacer::closedCallback(void *data, zwlr_layer_surface_v1 *surface)
{
    Q_UNUSED(surface)
    static_cast<StrutSpacer *>(data)->destroySurface();
}
