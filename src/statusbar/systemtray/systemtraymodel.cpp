#include "systemtraymodel.h"

#include <QApplication>
#include <QDebug>
#include <QQmlEngine>

#include <utility>

static QStringList noColorOverlayList = {
    "netease-cloud-music",
    "chrome_status_icon_1",
    "35682", // obs studio
    "lark_status_icon_1",
    "spotify",
    "spotify-client",
    "ht-music",
    "hypertube music"
};

SystemTrayModel::SystemTrayModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_watcher = new StatusNotifierWatcher;
    m_sniHost = StatusNotifierItemHost::self();

    connect(m_sniHost, &StatusNotifierItemHost::itemAdded, this, &SystemTrayModel::onItemAdded);
    connect(m_sniHost, &StatusNotifierItemHost::itemRemoved, this, &SystemTrayModel::onItemRemoved);

    for (auto service : m_sniHost->services()) {
        onItemAdded(service);
    }
}

SystemTrayModel::~SystemTrayModel()
{
    QDBusConnection::sessionBus().unregisterService(m_hostName);
}

int SystemTrayModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_items.size();
}

QHash<int, QByteArray> SystemTrayModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[IconNameRole] = "iconName";
    roles[IconRole] = "icon";
    roles[TitleRole] = "title";
    roles[ToolTipRole] = "toolTip";
    roles[CanColorOverlay] = "canColorOverlay";
    return roles;
}

QVariant SystemTrayModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid())
        return QVariant();

    StatusNotifierItemSource *item = m_items.at(index.row());

    switch (role) {
    case IdRole:
        return item->id();
    case IconNameRole:
        return item->iconName();
    case IconRole: {
        // Keep theme-resolved icons as names so they can be reloaded when the
        // icon theme changes. Expose a QIcon only for pixmaps or desktop-entry
        // fallbacks that do not have a usable theme name.
        if (item->iconName().isEmpty() && !item->icon().isNull())
            return item->icon();
        else
            return QVariant();
    }
    case TitleRole:
        return item->title();
    case ToolTipRole:
        return item->tooltip();
    case CanColorOverlay: {
        const QString &appId = item->appId();
        const QString &iconName = item->iconName();
        const QString &title = item->title();

        for (const QString &excluded : noColorOverlayList) {
            if (appId.contains(excluded, Qt::CaseInsensitive)
                || iconName.contains(excluded, Qt::CaseInsensitive)
                || title.contains(excluded, Qt::CaseInsensitive)) {
                return false;
            }
        }

        if (iconName.isEmpty() && !item->icon().isNull()) {
            return false;
        }

        if (iconName.contains(QLatin1String("-symbolic"), Qt::CaseInsensitive)) {
            return true;
        }

        return false;
    }
    }

    return QVariant();
}

int SystemTrayModel::indexOf(const QString &id)
{
    for (StatusNotifierItemSource *item : std::as_const(m_items)) {
        if (item->id() == id)
            return m_items.indexOf(item);
    }

    return -1;
}

StatusNotifierItemSource *SystemTrayModel::findItemById(const QString &id)
{
    int index = indexOf(id);

    if (index == -1)
        return nullptr;

    return m_items.at(index);
}

// The x/y handed to StatusNotifierItem are the logical global position of the
// item, straight from popupPosition(). They are only a hint for where the app
// should put its own window; on Wayland there is no global pixel space to
// convert them into, so they are passed through unscaled.
void SystemTrayModel::leftButtonClick(const QString &id, int x, int y)
{
    StatusNotifierItemSource *item = findItemById(id);

    if (item) {
        item->activate(x, y);
    }
}

QObject *SystemTrayModel::contextMenu(const QString &id, int x, int y)
{
    StatusNotifierItemSource *item = findItemById(id);

    if (!item)
        return nullptr;

    if (QMenu *menu = item->contextMenuObject()) {
        // The menu of a tray item has no parent, so QML would take ownership
        // of it and the garbage collector would delete a menu the importer
        // still uses.
        QQmlEngine::setObjectOwnership(menu, QQmlEngine::CppOwnership);
        return menu;
    }

    item->requestContextMenu(x, y);

    return nullptr;
}

void SystemTrayModel::middleButtonClick(const QString &id, int x, int y)
{
    StatusNotifierItemSource *item = findItemById(id);

    if (item) {
        item->secondaryActivate(x, y);
    }
}

void SystemTrayModel::move(int from, int to)
{
    if (from == to)
        return;

    m_items.move(from, to);

    if (from < to)
        beginMoveRows(QModelIndex(), from, from, QModelIndex(), to + 1);
    else
        beginMoveRows(QModelIndex(), from, from, QModelIndex(), to);

    endMoveRows();
}

QPointF SystemTrayModel::popupPosition(QQuickItem *visualParent, int x, int y)
{
    if (!visualParent) {
        return QPointF(0, 0);
    }

    QPointF pos = visualParent->mapToScene(QPointF(x, y));

    if (visualParent->window() && visualParent->window()->screen()) {
        pos = visualParent->window()->mapToGlobal(pos.toPoint());
    } else {
        return QPoint();
    }

    return pos;
}

void SystemTrayModel::onItemAdded(const QString &service)
{
    StatusNotifierItemSource *source = m_sniHost->itemForService(service);

    connect(source, &StatusNotifierItemSource::updated, this, &SystemTrayModel::updated);

    beginInsertRows(QModelIndex(), rowCount(), rowCount());
    m_items.append(source);
    endInsertRows();
}

void SystemTrayModel::onItemRemoved(const QString &service)
{
    int index = indexOf(service);

    if (index != -1) {
        beginRemoveRows(QModelIndex(), index, index);
        StatusNotifierItemSource *item = m_items.at(index);
        m_items.removeAll(item);
        endRemoveRows();
    }
}

void SystemTrayModel::updated(StatusNotifierItemSource *item)
{
    if (!item)
        return;

    int idx = indexOf(item->id());

    // update
    if (idx != -1) {
        emit dataChanged(index(idx, 0), index(idx, 0));
    }
}
