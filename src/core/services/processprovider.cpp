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

#include "processprovider.h"
#include "applicationlauncher.h"
#include <QProcess>
#include <QStandardPaths>

ProcessProvider::ProcessProvider(QObject *parent)
    : QObject(parent)
{
}

bool ProcessProvider::startDetached(const QString &exec, QStringList args)
{
    QString target = exec;
    if (target.startsWith(QStringLiteral("cutefish-"))) {
        QString aevisExec = target;
        aevisExec.replace(0, 8, QStringLiteral("aevis"));
        if (!QStandardPaths::findExecutable(aevisExec).isEmpty()) {
            target = aevisExec;
        }
    }

    if (ApplicationLauncher::startDetached(QStringList{target} + args))
        return true;

    if (QProcess::startDetached(target, args))
        return true;

    if (target != exec) {
        if (ApplicationLauncher::startDetached(QStringList{exec} + args))
            return true;
        if (QProcess::startDetached(exec, args))
            return true;
    }

    if (exec == QStringLiteral("cutefish-settings") || exec == QStringLiteral("aevis-settings")) {
        if (QProcess::startDetached(QStringLiteral("systemsettings"), args))
            return true;
        if (QProcess::startDetached(QStringLiteral("gnome-control-center"), args))
            return true;
    }
    return false;
}
