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

#include "core/qmltypes.h"
#include "core/services/screenhelper.h"
#include "core/services/processprovider.h"
#include "core/window/popupwindow.h"

#include <QQmlEngine>

void registerCoreQmlTypes()
{
    // The work area is shell-wide: on Wayland only the shell knows it, because
    // it is the shell that reserves the struts.
    for (const char *uri : {"Cutefish.Shell", "Aevis.Shell"}) {
        qmlRegisterType<ScreenHelper>(uri, 1, 0, "ScreenHelper");
        qmlRegisterType<PopupWindow>(uri, 1, 0, "PopupWindow");
        qmlRegisterType<ProcessProvider>(uri, 1, 0, "ProcessProvider");
    }
}
