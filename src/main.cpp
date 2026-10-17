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

#include "shell.h"

#include <QApplication>
#include <QIcon>
#include <QQuickWindow>
#include <QFile>

#if defined(__linux__)
#include <malloc.h>
#endif

int main(int argc, char *argv[])
{
#if defined(__linux__)
    mallopt(M_ARENA_MAX, 1);
    mallopt(M_TRIM_THRESHOLD, 64 * 1024);
    mallopt(M_MMAP_THRESHOLD, 32 * 1024);
#endif

    // If no NVIDIA GPU device exists, restrict EGL ICD loader to Mesa/system driver
    // to prevent libglvnd from unconditionally mapping huge unused proprietary NVIDIA libraries.
    if (!QFile::exists(QStringLiteral("/dev/nvidia0"))
        && QFile::exists(QStringLiteral("/usr/share/glvnd/egl_vendor.d/50_mesa.json"))
        && qEnvironmentVariableIsEmpty("__EGL_VENDOR_LIBRARY_FILENAMES")) {
        qputenv("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json");
    }

    if (qEnvironmentVariableIsEmpty("QSG_RENDER_LOOP")) {
        qputenv("QSG_RENDER_LOOP", "basic");
    }

    // Prevent fractional rounding artifacts on high-DPI and scaled displays
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    // QApplication rather than QGuiApplication: the status bar's application
    // menu and several context menus are QWidget menus.
    QApplication app(argc, argv);

    const bool isAevis = QFile::exists(QStringLiteral("/usr/share/applications/aevis-shell.desktop"))
        || qgetenv("XDG_CURRENT_DESKTOP").contains("Aevis")
        || qgetenv("DESKTOP_SESSION").compare("aevis", Qt::CaseInsensitive) == 0
        || (argc > 0 && QString::fromLocal8Bit(argv[0]).contains(QLatin1String("aevis")));
    const QString desktopFile = isAevis ? QStringLiteral("aevis-shell") : QStringLiteral("cutefish-shell");
    app.setApplicationName(desktopFile);
    app.setDesktopFileName(desktopFile);
    app.setOrganizationName(desktopFile.startsWith(QLatin1String("aevis")) ? QStringLiteral("aevis") : QStringLiteral("cutefishos"));



    // Ensure all Qt Quick windows request an RGBA surface format with an alpha buffer for compositor blur
    QQuickWindow::setDefaultAlphaBuffer(true);
    QQuickWindow::setTextRenderType(QQuickWindow::QtTextRendering);

    if (QIcon::themeName().isEmpty() || QIcon::themeName() == QLatin1String("hicolor") || QIcon::themeName() == QLatin1String("Crule-dark")) {
        QIcon::setThemeName(QStringLiteral("Cutefish"));
    }

    // The shell owns the session's panels; closing the last one must not quit.
    app.setQuitOnLastWindowClosed(false);

    Shell shell;

    if (!shell.registerServices())
        return -1;

    shell.start();

    return app.exec();
}
