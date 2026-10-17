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

#include "statusbar/qmltypes.h"

#include "statusbar/statusbarforegroundhelper.h"
#include "statusbar/battery.h"
#include "statusbar/brightness.h"
#include "statusbar/notifications.h"
#include "statusbar/poweractions.h"
#include "statusbar/continuitymanager.h"
#include "statusbar/clipboardhelper.h"
#include "statusbar/appmenu/appmenumodel.h"
#include "statusbar/qmenu/qmenumodel.h"
#include "statusbar/systemtray/systemtraymodel.h"
#include "core/services/processprovider.h"

#include <QQmlEngine>

void registerStatusBarQmlTypes()
{
    for (const char *uri : {"Cutefish.StatusBar", "Aevis.StatusBar"}) {
        qmlRegisterType<SystemTrayModel>(uri, 1, 0, "SystemTrayModel");
        qmlRegisterType<Brightness>(uri, 1, 0, "Brightness");
        qmlRegisterType<Battery>(uri, 1, 0, "Battery");
        qmlRegisterType<ClipboardHelper>(uri, 1, 0, "ClipboardHelper");
        qmlRegisterType<AppMenuModel>(uri, 1, 0, "AppMenuModel");
        qmlRegisterType<QMenuModel>(uri, 1, 0, "QMenuModel");
        qmlRegisterType<PowerActions>(uri, 1, 0, "PowerActions");
        qmlRegisterType<Notifications>(uri, 1, 0, "Notifications");
        qmlRegisterType<ContinuityManager>(uri, 1, 0, "ContinuityManager");
        qmlRegisterType<StatusBarForegroundHelper>(uri, 1, 0, "StatusBarForegroundHelper");
        qmlRegisterType<ProcessProvider>(uri, 1, 0, "ProcessProvider");
    }
}
