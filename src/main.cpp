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
    app.setApplicationName(QStringLiteral("cutefish-shell"));
    app.setDesktopFileName(QStringLiteral("cutefish-shell"));
    app.setOrganizationName(QStringLiteral("cutefishos"));

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
