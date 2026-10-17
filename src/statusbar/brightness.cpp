#include "brightness.h"
#include <QDBusPendingCall>
#include <QFile>
#include <QTextStream>
#include <QDir>
#include <QProcess>
#include <algorithm>

Brightness::Brightness(QObject *parent)
    : QObject(parent)
    , m_dbusConnection(QDBusConnection::sessionBus())
    , m_iface("com.cutefish.Services",
              "/com/cutefish/Services/Brightness",
              "com.cutefish.Services.Brightness", m_dbusConnection)
    , m_value(100)
    , m_enabled(false)
{
    // Locate backlight device directly
    QDir blDir(QStringLiteral("/sys/class/backlight"));
    const QStringList entries = blDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (!entries.isEmpty()) {
        m_backlightDev = blDir.filePath(entries.first());
        m_enabled = true;
    }

    if (m_iface.isValid()) {
        m_value = m_iface.property("brightness").toInt();
        m_enabled = m_enabled || m_iface.property("brightnessEnabled").toBool();

        m_dbusConnection.connect(
            QStringLiteral("com.cutefish.Services"),
            QStringLiteral("/com/cutefish/Services/Brightness"),
            QStringLiteral("com.cutefish.Services.Brightness"),
            QStringLiteral("brightnessChanged"),
            this,
            SLOT(onBrightnessChanged()));
    } else if (!m_backlightDev.isEmpty()) {
        // Read directly from /sys/class/backlight
        QFile maxF(m_backlightDev + QStringLiteral("/max_brightness"));
        QFile curF(m_backlightDev + QStringLiteral("/brightness"));
        int maxB = 100, curB = 100;
        if (maxF.open(QIODevice::ReadOnly)) {
            maxB = maxF.readAll().trimmed().toInt();
            maxF.close();
        }
        if (curF.open(QIODevice::ReadOnly)) {
            curB = curF.readAll().trimmed().toInt();
            curF.close();
        }
        if (maxB > 0)
            m_value = std::clamp(curB * 100 / maxB, 0, 100);
    }
}

void Brightness::onBrightnessChanged()
{
    if (m_iface.isValid()) {
        int newVal = m_iface.property("brightness").toInt();
        if (m_value != newVal) {
            m_value = newVal;
            emit valueChanged();
        }
    }
}

void Brightness::setValue(int value)
{
    value = std::clamp(value, 1, 100);
    if (m_value != value) {
        m_value = value;
        emit valueChanged();
    }

    // Direct hardware write to sysfs
    if (!m_backlightDev.isEmpty()) {
        QFile curF(m_backlightDev + QStringLiteral("/brightness"));
        if (curF.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            QFile maxF(m_backlightDev + QStringLiteral("/max_brightness"));
            int maxB = 100;
            if (maxF.open(QIODevice::ReadOnly)) {
                maxB = maxF.readAll().trimmed().toInt();
                maxF.close();
            }
            int rawVal = std::max(1, (value * maxB) / 100);
            QTextStream out(&curF);
            out << rawVal << "\n";
            curF.close();
        }
    }

    // Always invoke brightnessctl & light for guaranteed backlight adjustment
    QProcess::startDetached(QStringLiteral("brightnessctl"), QStringList() << QStringLiteral("set") << QString("%1%").arg(value));
    QProcess::startDetached(QStringLiteral("light"), QStringList() << QStringLiteral("-S") << QString::number(value));

    // Also inform services daemon asynchronously if available
    if (m_iface.isValid()) {
        m_iface.asyncCall("setValue", value);
    }
}

int Brightness::value() const
{
    return m_value;
}

bool Brightness::enabled() const
{
    return m_enabled;
}
