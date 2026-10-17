/*
 * Copyright (C) 2021 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * Author:     Reion Wong <reion@cutefishos.com>
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

#ifndef NOTIFICATIONMANAGER_H
#define NOTIFICATIONMANAGER_H

#include <QObject>

class QQmlEngine;
class QQmlComponent;
class QQmlContext;
class NotificationServer;
class NotificationsModel;
class NotificationSettings;

/**
 * What cutefish-notificationd used to be: the org.freedesktop.Notifications
 * server, the notification history, and the banners it puts on screen.
 *
 * The notification centre itself is not created here. It is a
 * NotificationCenterDialog declared in the status bar's QML, next to the
 * control centre, so it opens as a popup anchored to the item that toggles it;
 * showWindow() over D-Bus only asks the status bar to open it.
 */
class NotificationManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool doNotDisturb READ doNotDisturb WRITE setDoNotDisturb NOTIFY doNotDisturbChanged)

public:
    explicit NotificationManager(QQmlEngine *engine, QObject *parent = nullptr);
    ~NotificationManager() override;

    bool doNotDisturb() const;
    void setDoNotDisturb(bool enabled);

public slots:
    /** D-Bus entry point, and what `cutefish-notificationd -s` used to do. */
    void showWindow();

signals:
    void doNotDisturbChanged();
    /** Asks the status bar to toggle the notification centre. */
    void windowRequested();

private:
    QQmlEngine *m_engine;
    QQmlComponent *m_popupsComponent;
    QObject *m_popups;
    NotificationServer *m_server;
    NotificationsModel *m_model;
    NotificationSettings *m_settings;
};

#endif // NOTIFICATIONMANAGER_H
