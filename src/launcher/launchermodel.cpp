#include "launchermodel.h"

#include "applicationlauncher.h"
#include "applicationregistry.h"
#include "desktopentry.h"

#include <QDataStream>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSet>
#include <QStandardPaths>

#include <algorithm>
#include <utility>

namespace {

void updateItem(AppItem *item, DesktopEntry *entry)
{
    item->id = entry->id();
    item->name = entry->name();
    item->genericName = entry->genericName();
    item->comment = entry->comment();
    item->iconName = entry->icon();
    item->args = entry->command();
}

} // namespace

LauncherModel::LauncherModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_settings("cutefishos", "launcher-applist", this)
    , m_mode(NormalMode)
    , m_firstLoad(false)
{
    const QByteArray listByteArray = m_settings.value("list").toByteArray();
    QDataStream in(listByteArray);
    in >> m_appItems;
    m_firstLoad = m_appItems.isEmpty();

    ApplicationRegistry *registry = ApplicationRegistry::instance();
    connect(registry, &ApplicationRegistry::applicationsChanged,
            this, &LauncherModel::onApplicationsChanged);
    if (!registry->loading())
        onApplicationsChanged();

    m_saveTimer.setInterval(1000);
    m_saveTimer.setSingleShot(true);
    connect(&m_saveTimer, &QTimer::timeout, this, &LauncherModel::save);

    connect(this, &QAbstractItemModel::rowsInserted, this, &LauncherModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &LauncherModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &LauncherModel::countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, &LauncherModel::countChanged);
}

LauncherModel::~LauncherModel()
{
    save();
}

int LauncherModel::count() const
{
    return rowCount();
}

int LauncherModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_mode == SearchMode ? m_searchItems.size() : m_appItems.size();
}

QHash<int, QByteArray> LauncherModel::roleNames() const
{
    return {
        {AppIdRole, "appId"},
        {ApplicationRole, "application"},
        {NameRole, "name"},
        {GenericNameRole, "genericName"},
        {CommentRole, "comment"},
        {IconNameRole, "iconName"},
        {CategoriesRole, "categories"},
        {FilterInfoRole, "filterInfo"},
        {PinnedRole, "pinned"},
        {PinnedIndexRole, "pinnedIndex"},
        {NewInstalledRole, "newInstalled"}
    };
}

QVariant LauncherModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid())
        return {};

    const AppItem &item = m_mode == NormalMode ? m_appItems.at(index.row())
                                               : m_searchItems.at(index.row());
    switch (role) {
    case AppIdRole: return item.id;
    case NameRole: return item.name;
    case GenericNameRole: return item.genericName;
    case CommentRole: return item.comment;
    case IconNameRole: return item.iconName;
    case FilterInfoRole: return item.name + QLatin1Char(' ') + item.genericName
                                + QLatin1Char(' ') + item.comment;
    case NewInstalledRole: return item.newInstalled;
    default: return {};
    }
}

void LauncherModel::search(const QString &key)
{
    beginResetModel();
    m_searchKey = key;
    m_mode = key.isEmpty() ? NormalMode : SearchMode;
    m_searchItems.clear();

    if (!key.isEmpty()) {
        for (const AppItem &item : std::as_const(m_appItems)) {
            if (item.name.contains(key, Qt::CaseInsensitive)
                || item.genericName.contains(key, Qt::CaseInsensitive)
                || item.comment.contains(key, Qt::CaseInsensitive)
                || item.id.contains(key, Qt::CaseInsensitive)) {
                m_searchItems.append(item);
            }
        }
    }

    endResetModel();
    emit countChanged();
}

void LauncherModel::sendToDesktop(const QString &key)
{
    DesktopEntry *entry = ApplicationRegistry::instance()->byId(key);
    if (!entry)
        entry = ApplicationRegistry::instance()->byPath(key);
    if (!entry)
        return;

    const QString desktop = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    QFile::copy(entry->path(), desktop + QLatin1Char('/') + QFileInfo(entry->path()).fileName());
}

int LauncherModel::findById(const QString &id)
{
    QString canonicalId = id;
    if (DesktopEntry *entry = ApplicationRegistry::instance()->byPath(id))
        canonicalId = entry->id();

    for (int i = 0; i < m_appItems.size(); ++i) {
        if (m_appItems.at(i).id == canonicalId)
            return i;
    }
    return -1;
}

void LauncherModel::move(int from, int to)
{
    if (from == to)
        return;

    if (from < 0 || from >= m_appItems.size() || to < 0 || to >= m_appItems.size())
        return;

    const int destination = from < to ? to + 1 : to;
    if (!beginMoveRows({}, from, from, {}, destination))
        return;
    m_appItems.move(from, to);
    endMoveRows();
    delaySave();
}

void LauncherModel::save()
{
    m_settings.clear();
    QByteArray data;
    QDataStream out(&data, QIODevice::WriteOnly);
    out << m_appItems;
    m_settings.setValue("list", data);
    m_settings.sync();
}

void LauncherModel::delaySave()
{
    m_saveTimer.start();
}

bool LauncherModel::launch(const QString &path)
{
    DesktopEntry *entry = ApplicationRegistry::instance()->byId(path);
    if (!entry)
        entry = ApplicationRegistry::instance()->byPath(path);
    if (!entry)
        return false;

    const int index = findById(entry->id());
    if (index >= 0 && m_appItems[index].newInstalled) {
        m_appItems[index].newInstalled = false;
        emit dataChanged(this->index(index), this->index(index));
        delaySave();
    }

    QStringList command = entry->command();
    // The launcher animation needs to finish before the screenshot utility
    // captures the screen.
    if (command.value(0) == QStringLiteral("cutefish-screenshot"))
        command << QStringLiteral("-d") << QStringLiteral("200");

    const bool launched = ApplicationLauncher::startDetached(command,
                                                              entry->workingDirectory());
    if (launched)
        emit applicationLaunched();
    return launched;
}

void LauncherModel::onApplicationsChanged()
{
    ApplicationRegistry *registry = ApplicationRegistry::instance();
    // Only entries that pass the XDG display rules; a stale saved list must not
    // resurrect an application that is now NoDisplay/Hidden or not for Cutefish.
    const QList<DesktopEntry *> available = registry->applicationEntries();

    QHash<QString, DesktopEntry *> visibleById;
    QHash<QString, DesktopEntry *> visibleByPath;
    for (DesktopEntry *entry : available) {
        visibleById.insert(entry->id(), entry);
        visibleByPath.insert(QFileInfo(entry->path()).absoluteFilePath(), entry);
    }

    QList<AppItem> updated;
    QSet<QString> seen;
    for (AppItem item : std::as_const(m_appItems)) {
        DesktopEntry *entry = visibleById.value(item.id);
        if (!entry)
            entry = visibleByPath.value(QFileInfo(item.id).absoluteFilePath());
        if (!entry || entry->terminal() || seen.contains(entry->id()))
            continue;

        const bool newInstalled = item.newInstalled;
        updateItem(&item, entry);
        item.newInstalled = newInstalled;
        updated.append(item);
        seen.insert(entry->id());
    }

    for (DesktopEntry *entry : available) {
        if (entry->terminal() || seen.contains(entry->id()))
            continue;

        AppItem item;
        updateItem(&item, entry);
        item.newInstalled = true;
        updated.append(item);
        seen.insert(entry->id());
    }

    if (m_firstLoad) {
        std::sort(updated.begin(), updated.end(), [](const AppItem &left, const AppItem &right) {
            return QString::localeAwareCompare(left.name, right.name) < 0;
        });
        m_firstLoad = false;
    }

    beginResetModel();
    m_appItems = updated;
    m_searchItems.clear();
    m_mode = NormalMode;
    endResetModel();

    if (!m_searchKey.isEmpty())
        search(m_searchKey);
    delaySave();
}
