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

#include "screenhelper.h"
#include "core/wayland/strutspacer.h"

#include <QApplication>
#include <QScreen>

ScreenHelper::ScreenHelper(QObject *parent)
    : QObject(parent)
{
    connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, &ScreenHelper::watchPrimaryScreen);

    // On Wayland Qt reports the whole output as available, so the work area
    // comes from the struts the shell itself reserves.
    connect(StrutRegistry::self(), &StrutRegistry::changed,
            this, &ScreenHelper::availableScreenRectChanged);

    watchPrimaryScreen();
}

void ScreenHelper::watchPrimaryScreen()
{
    // Following the primary screen means following whichever QScreen that is
    // now: the signals of the old one say nothing about the geometry this
    // helper reports.
    if (m_screen)
        m_screen->disconnect(this);

    m_screen = qApp->primaryScreen();

    if (m_screen) {
        connect(m_screen, &QScreen::geometryChanged, this, &ScreenHelper::screenGeometryChanged);
        connect(m_screen, &QScreen::physicalDotsPerInchChanged, this, &ScreenHelper::screenGeometryChanged);
        connect(m_screen, &QScreen::geometryChanged, this, &ScreenHelper::availableScreenRectChanged);
    }

    emit screenGeometryChanged();
    emit availableScreenRectChanged();
}

QRect ScreenHelper::screenGeometry() const
{
    return qApp->primaryScreen()->geometry();
}

QRect ScreenHelper::availableScreenRect() const
{
    return StrutRegistry::self()->availableGeometry(qApp->primaryScreen());
}
