/*
 * Copyright (C) 2021 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "appmanager.h"
#include "applicationregistry.h"
#include <QFile>

AppManager::AppManager(QObject *parent)
    : QObject(parent)
    , m_iface("com.cutefish.Daemon",
              "/AppManager",
              "com.cutefish.AppManager", QDBusConnection::systemBus())
{
}

void AppManager::uninstall(const QString &desktopFile)
{
    QString path = desktopFile;
    if (DesktopEntry *entry = ApplicationRegistry::instance()->byId(desktopFile))
        path = entry->path();

    if (m_iface.isValid()) {
        m_iface.asyncCall("uninstall", path);
    }
}

bool AppManager::isAevisOS()
{
    return QFile::exists(QStringLiteral("/etc/aevis")) ||
           QFile::exists(QStringLiteral("/etc/aevisos")) ||
           QFile::exists(QStringLiteral("/etc/cutefishos")) ||
           QFile::exists(QStringLiteral("/etc/cutefish"));
}

bool AppManager::isCutefishOS()
{
    return isAevisOS();
}
