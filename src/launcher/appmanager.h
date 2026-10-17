/*
 * Copyright (C) 2021 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#ifndef APPMANAGER_H
#define APPMANAGER_H

#include <QObject>
#include <QDBusInterface>
#include <QDBusPendingCall>

class AppManager : public QObject
{
    Q_OBJECT

public:
    explicit AppManager(QObject *parent = nullptr);

    Q_INVOKABLE void uninstall(const QString &desktopFile);

    Q_INVOKABLE bool isAevisOS();
    Q_INVOKABLE bool isCutefishOS();

private:
    QDBusInterface m_iface;
};

#endif // APPMANAGER_H
