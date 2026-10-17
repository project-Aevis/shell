#include "continuitymanager.h"

#include <QDBusConnectionInterface>
#include <QProcess>
#include <QUrl>
#include <QFile>
#include <QDir>
#include <QDebug>

ContinuityManager::ContinuityManager(QObject *parent)
    : QObject(parent)
{
    loadLocalSettings();

    m_serviceWatcher = new QDBusServiceWatcher(QStringLiteral("org.kde.kdeconnect"),
                                               QDBusConnection::sessionBus(),
                                               QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration,
                                               this);

    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceRegistered,
            this, &ContinuityManager::onServiceRegistered);
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceUnregistered,
            this, &ContinuityManager::onServiceUnregistered);

    if (QDBusConnection::sessionBus().interface()->isServiceRegistered(QStringLiteral("org.kde.kdeconnect")).value()) {
        m_kdeConnectActive = true;
        queryKdeConnectDevices();
    }
}

void ContinuityManager::loadLocalSettings()
{
    QString org = (QFile::exists(QDir::homePath() + QStringLiteral("/.config/aevis/continuity.conf"))
                   || !QFile::exists(QDir::homePath() + QStringLiteral("/.config/cutefishos/continuity.conf")))
                      ? QStringLiteral("aevis")
                      : QStringLiteral("cutefishos");
    QSettings settings(org, QStringLiteral("continuity"));
    m_deviceName = settings.value(QStringLiteral("deviceName"), QString()).toString();
    m_connected = false;
    m_paired = false;
    m_reachable = false;
    m_batteryCharge = -1;
    m_isCharging = false;
    m_clipboardSync = settings.value(QStringLiteral("clipboardSync"), true).toBool();
    m_notificationSync = settings.value(QStringLiteral("notificationSync"), true).toBool();
    m_showInMenuBar = settings.value(QStringLiteral("showInMenuBar"), true).toBool();
    m_signalStrength = 0;
    m_networkType.clear();
}

void ContinuityManager::saveLocalSettings()
{
    QSettings settings(QStringLiteral("aevis"), QStringLiteral("continuity"));
    settings.setValue(QStringLiteral("deviceName"), m_deviceName);
    settings.setValue(QStringLiteral("clipboardSync"), m_clipboardSync);
    settings.setValue(QStringLiteral("notificationSync"), m_notificationSync);
    settings.setValue(QStringLiteral("showInMenuBar"), m_showInMenuBar);
    settings.sync();

    // Mirror to cutefishos if directory exists
    if (QFile::exists(QDir::homePath() + QStringLiteral("/.config/cutefishos"))) {
        QSettings legacy(QStringLiteral("cutefishos"), QStringLiteral("continuity"));
        legacy.setValue(QStringLiteral("deviceName"), m_deviceName);
        legacy.setValue(QStringLiteral("clipboardSync"), m_clipboardSync);
        legacy.setValue(QStringLiteral("notificationSync"), m_notificationSync);
        legacy.setValue(QStringLiteral("showInMenuBar"), m_showInMenuBar);
        legacy.sync();
    }
}

bool ContinuityManager::isConnected() const
{
    return m_connected && m_reachable;
}

bool ContinuityManager::isPaired() const
{
    return m_paired;
}

bool ContinuityManager::isReachable() const
{
    return m_reachable;
}

QString ContinuityManager::deviceId() const
{
    return m_deviceId;
}

QString ContinuityManager::deviceName() const
{
    return m_deviceName;
}

QString ContinuityManager::deviceType() const
{
    return m_deviceType;
}

int ContinuityManager::batteryCharge() const
{
    return m_batteryCharge;
}

bool ContinuityManager::isCharging() const
{
    return m_isCharging;
}

int ContinuityManager::signalStrength() const
{
    return m_signalStrength;
}

QString ContinuityManager::networkType() const
{
    return m_networkType;
}

bool ContinuityManager::clipboardSync() const
{
    return m_clipboardSync;
}

bool ContinuityManager::notificationSync() const
{
    return m_notificationSync;
}

bool ContinuityManager::showInMenuBar() const
{
    return m_showInMenuBar;
}

bool ContinuityManager::isKdeConnectActive() const
{
    return m_kdeConnectActive;
}

void ContinuityManager::onServiceRegistered(const QString &service)
{
    Q_UNUSED(service)
    m_kdeConnectActive = true;
    emit backendChanged();
    queryKdeConnectDevices();
}

void ContinuityManager::onServiceUnregistered(const QString &service)
{
    Q_UNUSED(service)
    m_kdeConnectActive = false;
    m_deviceId.clear();
    m_deviceName.clear();
    m_connected = false;
    m_paired = false;
    m_reachable = false;
    m_batteryCharge = -1;
    m_isCharging = false;
    m_signalStrength = 0;
    m_networkType.clear();
    emit backendChanged();
    emit statusChanged();
    emit batteryChanged();
}

void ContinuityManager::queryKdeConnectDevices()
{
    if (!m_kdeConnectActive) {
        m_deviceId.clear();
        m_deviceName.clear();
        m_connected = false;
        m_paired = false;
        m_reachable = false;
        m_batteryCharge = -1;
        m_isCharging = false;
        emit statusChanged();
        emit batteryChanged();
        return;
    }

    QDBusInterface daemon(QStringLiteral("org.kde.kdeconnect"),
                          QStringLiteral("/modules/kdeconnect"),
                          QStringLiteral("org.kde.kdeconnect.daemon"),
                          QDBusConnection::sessionBus());

    if (!daemon.isValid()) {
        m_deviceId.clear();
        m_deviceName.clear();
        m_connected = false;
        m_paired = false;
        m_reachable = false;
        m_batteryCharge = -1;
        m_isCharging = false;
        emit statusChanged();
        emit batteryChanged();
        return;
    }

    QDBusReply<QStringList> reply = daemon.call(QStringLiteral("devices"), true, true);
    if (!reply.isValid() || reply.value().isEmpty()) {
        reply = daemon.call(QStringLiteral("devices"), false, true);
    }
    if (!reply.isValid() || reply.value().isEmpty()) {
        reply = daemon.call(QStringLiteral("devices"), false, false);
    }

    if (!reply.isValid() || reply.value().isEmpty()) {
        m_deviceId.clear();
        m_deviceName.clear();
        m_connected = false;
        m_paired = false;
        m_reachable = false;
        m_batteryCharge = -1;
        m_isCharging = false;
        emit statusChanged();
        emit batteryChanged();
        return;
    }

    m_deviceId = reply.value().first();

    QDBusInterface dev(QStringLiteral("org.kde.kdeconnect"),
                       QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId,
                       QStringLiteral("org.kde.kdeconnect.device"),
                       QDBusConnection::sessionBus());

    if (dev.isValid()) {
        m_deviceName = dev.property("name").toString();
        m_isCharging = false;
        m_reachable = dev.property("isReachable").toBool();
        m_paired = dev.property("isPaired").toBool();
        m_connected = m_reachable && m_paired;
        m_deviceType = dev.property("type").toString();
        if (m_deviceType.isEmpty())
            m_deviceType = QStringLiteral("phone");
    }

    // Connect device reachable signals
    QDBusConnection::sessionBus().connect(
        QStringLiteral("org.kde.kdeconnect"),
        QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId,
        QStringLiteral("org.kde.kdeconnect.device"),
        QStringLiteral("reachableChanged"),
        this, SLOT(onDeviceReachableChanged(bool)));

    // Query battery
    QDBusInterface battery(QStringLiteral("org.kde.kdeconnect"),
                           QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId + QStringLiteral("/battery"),
                           QStringLiteral("org.kde.kdeconnect.device.battery"),
                           QDBusConnection::sessionBus());
    if (battery.isValid()) {
        QVariant chargeVar = battery.property("charge");
        if (chargeVar.isValid())
            m_batteryCharge = chargeVar.toInt();
        else
            m_batteryCharge = -1;

        QVariant isChargingVar = battery.property("isCharging");
        if (isChargingVar.isValid())
            m_isCharging = isChargingVar.toBool();
    } else {
        m_batteryCharge = -1;
        m_isCharging = false;
    }

    // Connect battery signals
    QDBusConnection::sessionBus().connect(
        QStringLiteral("org.kde.kdeconnect"),
        QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId + QStringLiteral("/battery"),
        QStringLiteral("org.kde.kdeconnect.device.battery"),
        QStringLiteral("chargeChanged"),
        this, SLOT(onBatteryChargeChanged(int)));

    QDBusConnection::sessionBus().connect(
        QStringLiteral("org.kde.kdeconnect"),
        QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId + QStringLiteral("/battery"),
        QStringLiteral("org.kde.kdeconnect.device.battery"),
        QStringLiteral("chargingChanged"),
        this, SLOT(onBatteryChargingChanged(bool)));

    // Connectivity report
    QDBusInterface connReport(QStringLiteral("org.kde.kdeconnect"),
                              QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId + QStringLiteral("/connectivity_report"),
                              QStringLiteral("org.kde.kdeconnect.device.connectivity_report"),
                              QDBusConnection::sessionBus());
    if (connReport.isValid()) {
        QVariant netTypeVar = connReport.property("cellularNetworkType");
        if (netTypeVar.isValid())
            m_networkType = netTypeVar.toString();
        QVariant sigVar = connReport.property("cellularNetworkStrength");
        if (sigVar.isValid())
            m_signalStrength = sigVar.toInt();
    }

    emit statusChanged();
    emit batteryChanged();
}

void ContinuityManager::onDeviceReachableChanged(bool reachable)
{
    m_reachable = reachable;
    m_connected = m_reachable && m_paired;
    emit statusChanged();
}

void ContinuityManager::onBatteryChargeChanged(int charge)
{
    m_batteryCharge = charge;
    emit batteryChanged();
}

void ContinuityManager::onBatteryChargingChanged(bool charging)
{
    m_isCharging = charging;
    emit batteryChanged();
}

void ContinuityManager::openKdeConnect()
{
    if (!QProcess::startDetached(QStringLiteral("kdeconnect-app"), {})) {
        if (!QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_kdeconnect")})) {
            QProcess::startDetached(QStringLiteral("kdeconnect-indicator"), {});
        }
    }
}

void ContinuityManager::ringPhone()
{
    if (m_kdeConnectActive && !m_deviceId.isEmpty()) {
        QDBusInterface findmyphone(QStringLiteral("org.kde.kdeconnect"),
                                   QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId + QStringLiteral("/findmyphone"),
                                   QStringLiteral("org.kde.kdeconnect.device.findmyphone"),
                                   QDBusConnection::sessionBus());
        if (findmyphone.isValid()) {
            findmyphone.call(QStringLiteral("ring"));
        }
    }

    QProcess::startDetached(QStringLiteral("notify-send"),
                           { QStringLiteral("-a"), QStringLiteral("Continuity"),
                             QStringLiteral("Find My Phone"),
                             QStringLiteral("Ringing %1...").arg(m_deviceName),
                             QStringLiteral("-i"), QStringLiteral("phone") });

    QProcess::startDetached(QStringLiteral("canberra-gtk-play"),
                           { QStringLiteral("-i"), QStringLiteral("phone-incoming-call") });
}

void ContinuityManager::sendPing()
{
    if (m_kdeConnectActive && !m_deviceId.isEmpty()) {
        QDBusInterface ping(QStringLiteral("org.kde.kdeconnect"),
                            QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId + QStringLiteral("/ping"),
                            QStringLiteral("org.kde.kdeconnect.device.ping"),
                            QDBusConnection::sessionBus());
        if (ping.isValid()) {
            ping.call(QStringLiteral("sendPing"));
        }
    }

    QProcess::startDetached(QStringLiteral("notify-send"),
                           { QStringLiteral("-a"), QStringLiteral("Continuity"),
                             QStringLiteral("Continuity Ping"),
                             QStringLiteral("Ping message sent to %1").arg(m_deviceName),
                             QStringLiteral("-i"), QStringLiteral("phone") });
}

void ContinuityManager::shareFile(const QString &filePath)
{
    if (filePath.isEmpty())
        return;

    if (m_kdeConnectActive && !m_deviceId.isEmpty()) {
        QDBusInterface share(QStringLiteral("org.kde.kdeconnect"),
                             QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId + QStringLiteral("/share"),
                             QStringLiteral("org.kde.kdeconnect.device.share"),
                             QDBusConnection::sessionBus());
        if (share.isValid()) {
            share.call(QStringLiteral("shareUrl"), QUrl::fromLocalFile(filePath).toString());
        }
    }

    QProcess::startDetached(QStringLiteral("notify-send"),
                           { QStringLiteral("-a"), QStringLiteral("AirDrop"),
                             QStringLiteral("AirDrop"),
                             QStringLiteral("Sending \"%1\" to %2...").arg(filePath, m_deviceName),
                             QStringLiteral("-i"), QStringLiteral("document-send") });
}

void ContinuityManager::shareText(const QString &text)
{
    if (text.isEmpty())
        return;

    if (m_kdeConnectActive && !m_deviceId.isEmpty()) {
        QDBusInterface share(QStringLiteral("org.kde.kdeconnect"),
                             QStringLiteral("/modules/kdeconnect/devices/") + m_deviceId + QStringLiteral("/share"),
                             QStringLiteral("org.kde.kdeconnect.device.share"),
                             QDBusConnection::sessionBus());
        if (share.isValid()) {
            share.call(QStringLiteral("shareText"), text);
        }
    }

    QProcess::startDetached(QStringLiteral("notify-send"),
                           { QStringLiteral("-a"), QStringLiteral("Continuity"),
                             QStringLiteral("Shared to Phone"),
                             QStringLiteral("Text sent to %1").arg(m_deviceName),
                             QStringLiteral("-i"), QStringLiteral("phone") });
}

void ContinuityManager::toggleConnect()
{
    m_connected = !m_connected;
    saveLocalSettings();
    emit statusChanged();
}

void ContinuityManager::setDeviceName(const QString &name)
{
    if (m_deviceName != name) {
        m_deviceName = name;
        saveLocalSettings();
        emit statusChanged();
    }
}

void ContinuityManager::setClipboardSync(bool enabled)
{
    if (m_clipboardSync != enabled) {
        m_clipboardSync = enabled;
        saveLocalSettings();
        emit settingsChanged();
    }
}

void ContinuityManager::setNotificationSync(bool enabled)
{
    if (m_notificationSync != enabled) {
        m_notificationSync = enabled;
        saveLocalSettings();
        emit settingsChanged();
    }
}

void ContinuityManager::setShowInMenuBar(bool enabled)
{
    if (m_showInMenuBar != enabled) {
        m_showInMenuBar = enabled;
        saveLocalSettings();
        emit settingsChanged();
    }
}

void ContinuityManager::refresh()
{
    if (m_kdeConnectActive) {
        queryKdeConnectDevices();
    } else {
        loadLocalSettings();
        emit statusChanged();
        emit batteryChanged();
        emit settingsChanged();
    }
}
