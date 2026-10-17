#include "desktopmanager.h"
#include "desktopsurface.h"

#include <QGuiApplication>
#include <QScreen>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDate>
#include <QTimer>
#include <QSettings>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QDBusConnection>
#include <QDBusInterface>

DesktopManager::DesktopManager(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
    const QList<QScreen *> screens = QGuiApplication::screens();
    for (QScreen *screen : screens)
        screenAdded(screen);

    updatePrimaryScreen();

    connect(qApp, &QGuiApplication::screenAdded, this, &DesktopManager::screenAdded);
    connect(qApp, &QGuiApplication::screenRemoved, this, &DesktopManager::screenRemoved);
    connect(qApp, &QGuiApplication::primaryScreenChanged, this, &DesktopManager::updatePrimaryScreen);

    m_netManager = new QNetworkAccessManager(this);
    QTimer *bingTimer = new QTimer(this);
    bingTimer->setInterval(3600000); // Check every 1 hour
    connect(bingTimer, &QTimer::timeout, this, &DesktopManager::checkBingWallpaper);
    bingTimer->start();

    QTimer::singleShot(2500, this, &DesktopManager::checkBingWallpaper);
}

DesktopManager::~DesktopManager()
{
    qDeleteAll(m_surfaces);
    m_surfaces.clear();
}

void DesktopManager::screenAdded(QScreen *screen)
{
    if (m_surfaces.contains(screen))
        return;

    DesktopSurface *surface = new DesktopSurface(m_engine, screen);
    m_surfaces.insert(screen, surface);

    // A new screen can become the primary one, and the surface has to know
    // before it is shown so it loads the right contents straight away.
    updatePrimaryScreen();
    surface->show();
}

void DesktopManager::screenRemoved(QScreen *screen)
{
    DesktopSurface *surface = m_surfaces.take(screen);

    if (!surface)
        return;

    surface->setVisible(false);
    surface->deleteLater();

    updatePrimaryScreen();
}

void DesktopManager::updatePrimaryScreen()
{
    QScreen *primary = QGuiApplication::primaryScreen();

    for (auto it = m_surfaces.constBegin(); it != m_surfaces.constEnd(); ++it)
        it.value()->setPrimary(it.key() == primary);
}

static inline QString wallpaperConfigOrg()
{
    const QString aevisPath = QDir::homePath() + QStringLiteral("/.config/aevis/wallpaper.conf");
    return (QFile::exists(aevisPath) || QFile::exists(QDir::homePath() + QStringLiteral("/.config/aevis")))
        ? QStringLiteral("aevis") : QStringLiteral("cutefishos");
}

void DesktopManager::checkBingWallpaper()
{
    QSettings settings(wallpaperConfigOrg(), QStringLiteral("wallpaper"));
    if (!settings.value(QStringLiteral("autoBingWallpaper"), false).toBool()) {
        QSettings legacySettings(QStringLiteral("cutefishos"), QStringLiteral("wallpaper"));
        if (!legacySettings.value(QStringLiteral("autoBingWallpaper"), false).toBool())
            return;
    }

    QString today = QDate::currentDate().toString(QStringLiteral("yyyyMMdd"));
    QString savedDate = settings.value(QStringLiteral("bingTodayDate")).toString();
    QString savedPath = settings.value(QStringLiteral("bingTodayPath")).toString();

    // If today is already saved and file exists, do not re-fetch
    if (savedDate == today && !savedPath.isEmpty() && QFile::exists(savedPath))
        return;

    if (m_jsonReply || m_imgReply)
        return;

    QUrl url(QStringLiteral("https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US"));
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Mozilla/5.0 ProjectAevis/1.0 (Compatible; CutefishOS/1.0)"));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);

    m_jsonReply = m_netManager->get(request);
    connect(m_jsonReply, &QNetworkReply::finished, this, &DesktopManager::onBingJsonDownloaded);
}

void DesktopManager::onBingJsonDownloaded()
{
    if (!m_jsonReply)
        return;

    if (m_jsonReply->error() != QNetworkReply::NoError) {
        m_jsonReply->deleteLater();
        m_jsonReply = nullptr;
        return;
    }

    QByteArray data = m_jsonReply->readAll();
    m_jsonReply->deleteLater();
    m_jsonReply = nullptr;

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject())
        return;

    QJsonObject root = doc.object();
    QJsonArray images = root.value(QStringLiteral("images")).toArray();
    if (images.isEmpty())
        return;

    QJsonObject imgObj = images.first().toObject();
    m_pendingBingTitle = imgObj.value(QStringLiteral("title")).toString();
    m_pendingBingDate = imgObj.value(QStringLiteral("startdate")).toString();
    QString copyright = imgObj.value(QStringLiteral("copyright")).toString();

    QString urlPart = imgObj.value(QStringLiteral("url")).toString();
    QString fullUrl = urlPart.startsWith(QLatin1String("http")) ? urlPart : (QStringLiteral("https://www.bing.com") + urlPart);

    for (const QString &org : { QStringLiteral("aevis"), QStringLiteral("cutefishos") }) {
        QSettings settings(org, QStringLiteral("wallpaper"));
        settings.setValue(QStringLiteral("bingTodayTitle"), m_pendingBingTitle);
        settings.setValue(QStringLiteral("bingTodayCopyright"), copyright);
        settings.setValue(QStringLiteral("bingTodayDate"), m_pendingBingDate);
    }

    QNetworkRequest imgRequest((QUrl(fullUrl)));
    imgRequest.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Mozilla/5.0 ProjectAevis/1.0 (Compatible; CutefishOS/1.0)"));
    imgRequest.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);

    m_imgReply = m_netManager->get(imgRequest);
    connect(m_imgReply, &QNetworkReply::finished, this, &DesktopManager::onBingImageDownloaded);
}

void DesktopManager::onBingImageDownloaded()
{
    if (!m_imgReply)
        return;

    if (m_imgReply->error() != QNetworkReply::NoError) {
        m_imgReply->deleteLater();
        m_imgReply = nullptr;
        return;
    }

    QByteArray bytes = m_imgReply->readAll();
    m_imgReply->deleteLater();
    m_imgReply = nullptr;

    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/backgrounds/aevis");
    QDir().mkpath(cacheDir);

    QString fileName = QStringLiteral("bing-%1.jpg").arg(m_pendingBingDate.isEmpty() ? QStringLiteral("today") : m_pendingBingDate);
    QString fullPath = cacheDir + QLatin1Char('/') + fileName;

    QFile file(fullPath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(bytes);
        file.close();
    }

    // Mirror to legacy path for compatibility
    QString legacyDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/backgrounds/cutefishos");
    QDir().mkpath(legacyDir);
    QString legacyPath = legacyDir + QLatin1Char('/') + fileName;
    if (!QFile::exists(legacyPath)) {
        QFile legacyFile(legacyPath);
        if (legacyFile.open(QIODevice::WriteOnly)) {
            legacyFile.write(bytes);
            legacyFile.close();
        }
    }

    // Generic cache copy
    QString genericCacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/wallpapers");
    QDir().mkpath(genericCacheDir);
    QString todayPath = genericCacheDir + QStringLiteral("/bing-today.jpg");
    QFile todayFile(todayPath);
    if (todayFile.open(QIODevice::WriteOnly)) {
        todayFile.write(bytes);
        todayFile.close();
    }

    for (const QString &org : { QStringLiteral("aevis"), QStringLiteral("cutefishos") }) {
        QSettings settings(org, QStringLiteral("wallpaper"));
        settings.setValue(QStringLiteral("bingTodayPath"), fullPath);

        QSettings themeSettings(org, QStringLiteral("theme"));
        themeSettings.setValue(QStringLiteral("Wallpaper"), fullPath);
        themeSettings.setValue(QStringLiteral("wallpaper"), fullPath);
        themeSettings.setValue(QStringLiteral("BackgroundType"), 0);
        themeSettings.setValue(QStringLiteral("backgroundtype"), 0);
        themeSettings.sync();
    }

    // Apply wallpaper to system
    QDBusInterface appearance(QStringLiteral("org.aevis.Services"),
                              QStringLiteral("/org/aevis/Services/Appearance"),
                              QStringLiteral("org.aevis.Services.Appearance"),
                              QDBusConnection::sessionBus());
    if (appearance.isValid()) {
        appearance.call(QStringLiteral("setWallpaper"), fullPath);
        appearance.call(QStringLiteral("setBackgroundType"), 0);
    }

    QDBusInterface legacyAppearance(QStringLiteral("com.cutefish.Services"),
                                    QStringLiteral("/com/cutefish/Services/Appearance"),
                                    QStringLiteral("com.cutefish.Services.Appearance"),
                                    QDBusConnection::sessionBus());
    if (legacyAppearance.isValid()) {
        legacyAppearance.call(QStringLiteral("setWallpaper"), fullPath);
        legacyAppearance.call(QStringLiteral("setBackgroundType"), 0);
    }

    QProcess::startDetached(QStringLiteral("notify-send"),
                           { QStringLiteral("-a"), QStringLiteral("Wallpaper"),
                             QStringLiteral("Bing Daily Wallpaper"),
                             QStringLiteral("Set background: %1").arg(m_pendingBingTitle),
                             QStringLiteral("-i"), QStringLiteral("preferences-desktop-wallpaper") });
}

