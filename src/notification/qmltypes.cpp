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

#include "notification/qmltypes.h"

#include "notification/historymodel.h"
#include "notification/notificationpopup.h"
#include "notification/notificationsmodel.h"

#include <QQmlEngine>

void registerNotificationQmlTypes()
{
    for (const char *uri : {"Cutefish.Notification", "Aevis.Notification"}) {
        qmlRegisterType<NotificationsModel>(uri, 1, 0, "NotificationsModel");
        qmlRegisterType<HistoryModel>(uri, 1, 0, "HistoryModel");
        qmlRegisterType<NotificationPopup>(uri, 1, 0, "NotificationPopup");
    }
}
