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

#include "launcher/qmltypes.h"

#include "launcher/appmanager.h"
#include "launcher/launchermodel.h"
#include "launcher/pagemodel.h"

#include <QAbstractItemModel>
#include <QQmlEngine>

void registerLauncherQmlTypes()
{
    for (const char *uri : {"Cutefish.Launcher", "Aevis.Launcher"}) {
        qmlRegisterType<LauncherModel>(uri, 1, 0, "LauncherModel");
        qmlRegisterType<PageModel>(uri, 1, 0, "PageModel");
        qmlRegisterType<AppManager>(uri, 1, 0, "AppManager");
        qmlRegisterAnonymousType<QAbstractItemModel>(uri, 0);
    }
}
