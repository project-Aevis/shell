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

#include "poweractions.h"
#include <QDebug>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QProcess>

namespace
{
static void callSessionMethod(const QString &method, const QStringList &fallbackProcess = {})
{
    const QString service = (QDBusConnection::sessionBus().interface() &&
                             QDBusConnection::sessionBus().interface()->isServiceRegistered(QStringLiteral("org.aevis.Session")))
        ? QStringLiteral("org.aevis.Session")
        : QStringLiteral("com.cutefish.Session");

    QDBusInterface iface(service, QStringLiteral("/Session"), service, QDBusConnection::sessionBus());
    if (iface.isValid()) {
        const QDBusMessage reply = iface.call(method);
        if (reply.type() != QDBusMessage::ErrorMessage)
            return;
    }

    if (!fallbackProcess.isEmpty()) {
        QProcess::startDetached(fallbackProcess.first(), fallbackProcess.mid(1));
    }
}
} // namespace

PowerActions::PowerActions(QObject *parent)
    : QObject(parent)
{
}

void PowerActions::shutdown()
{
    callSessionMethod(QStringLiteral("powerOff"), {QStringLiteral("systemctl"), QStringLiteral("poweroff")});
}

void PowerActions::logout()
{
    callSessionMethod(QStringLiteral("logout"), {QStringLiteral("loginctl"), QStringLiteral("terminate-session"), QStringLiteral("self")});
}

void PowerActions::reboot()
{
    callSessionMethod(QStringLiteral("reboot"), {QStringLiteral("systemctl"), QStringLiteral("reboot")});
}

void PowerActions::lockScreen()
{
    if (!QProcess::startDetached(QStringLiteral("aevis-screenlocker"), {}))
        QProcess::startDetached(QStringLiteral("cutefish-screenlocker"), {});
}

void PowerActions::suspend()
{
    callSessionMethod(QStringLiteral("suspend"));
}
