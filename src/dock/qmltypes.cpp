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

#include "dock/qmltypes.h"
#include "dock/docksettings.h"

#include <QQmlEngine>

void registerDockQmlTypes()
{
    // Uncreatable: the QML only reads the Direction enum off the type, and the
    // one instance the dock follows is exposed as the "Settings" context
    // property.
    for (const char *uri : {"Cutefish.Dock", "Aevis.Dock"}) {
        qmlRegisterUncreatableType<DockSettings>(uri, 1, 0, "DockSettings",
                                                 QStringLiteral("Use the Settings context property."));
    }
}
