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

#include "core/qmltypes.h"
#include "core/services/processprovider.h"
#include "desktop/desktopmanager.h"
#include "dock/dockwindow.h"
#include "dock/qmltypes.h"
#include "launcher/launcher.h"
#include "launcher/qmltypes.h"
#include "notification/notificationmanager.h"
#include "notification/qmltypes.h"
#include "statusbar/qmltypes.h"
#include "statusbar/statusbar.h"

#include "applicationregistry.h"

#include <QQmlEngine>
#include <QQmlContext>
#include <QDBusConnection>
#include <QGuiApplication>
#include <QTranslator>
#include <QPixmapCache>
#include <QLocale>
#include <QFile>
#include <QDebug>

namespace {

struct ServiceRegistration {
    const char *service;
    const char *path;
};

// Register both Aevis and legacy Cutefish service names for seamless compatibility.
constexpr ServiceRegistration s_services[] = {
    { "org.aevis.Shell",           "/Shell"        },
    { "com.cutefish.Shell",        "/Shell"        },
    { "org.aevis.Statusbar",       "/Statusbar"    },
    { "com.cutefish.Statusbar",    "/Statusbar"    },
    { "org.aevis.Dock",            "/Dock"         },
    { "com.cutefish.Dock",         "/Dock"         },
    { "org.aevis.Launcher",        "/Launcher"     },
    { "com.cutefish.Launcher",     "/Launcher"     },
    { "org.aevis.Notification",    "/Notification" },
    { "com.cutefish.Notification", "/Notification" },
};

// One catalogue per merged component, so the components' existing translations
// are reused as they are.
constexpr const char *s_translationCatalogues[] = {
    "statusbar", "dock", "launcher", "notification"
};

} // namespace

#if defined(__linux__)
#include <malloc.h>
#endif
#include <QTimer>

Shell::Shell(QObject *parent)
    : QObject(parent)
    , m_engine(new QQmlEngine(this))
    , m_statusBar(nullptr)
    , m_dock(nullptr)
    , m_launcher(nullptr)
    , m_desktops(nullptr)
    , m_notifications(nullptr)
{
    QPixmapCache::setCacheLimit(2048);

#if defined(__linux__)
    QTimer *trimTimer = new QTimer(this);
    connect(trimTimer, &QTimer::timeout, this, [this]() {
        if (m_engine) {
            m_engine->trimComponentCache();
        }
        malloc_trim(0);
    });
    trimTimer->start(45000);
    QTimer::singleShot(3000, this, [this]() {
        if (m_engine) {
            m_engine->trimComponentCache();
        }
        malloc_trim(0);
    });
#endif

    registerQmlTypes();
    loadTranslations();

    // Shared by every component's QML; one instance on the root context rather
    // than one per window.
    m_engine->rootContext()->setContextProperty(QStringLiteral("process"),
                                                new ProcessProvider(this));
}

Shell::~Shell()
{
    delete m_notifications;
    delete m_desktops;
    delete m_launcher;
    delete m_dock;
    delete m_statusBar;
}

void Shell::registerQmlTypes()
{
    registerApplicationsQmlTypes();
    registerCoreQmlTypes();
    registerStatusBarQmlTypes();
    registerDockQmlTypes();
    registerLauncherQmlTypes();
    registerNotificationQmlTypes();

    // The background is drawn from Cutefish.Appearance's Wallpaper type; the
    // desktop icons come from the org.cutefish.filemanager.desktop QML plugin,
    // and both register their own types.
}

void Shell::loadTranslations()
{
    const QString locale = QLocale::system().name();

    for (const char *component : s_translationCatalogues) {
        QString path = QStringLiteral("/usr/share/aevis-shell/translations/%1_%2.qm")
                           .arg(QLatin1String(component), locale);
        if (!QFile::exists(path)) {
            path = QStringLiteral("/usr/share/cutefish-shell/translations/%1_%2.qm")
                       .arg(QLatin1String(component), locale);
        }

        if (!QFile::exists(path))
            continue;

        QTranslator *translator = new QTranslator(this);
        if (translator->load(path))
            QGuiApplication::installTranslator(translator);
        else
            translator->deleteLater();
    }
}

bool Shell::registerServices()
{
    QDBusConnection bus = QDBusConnection::sessionBus();

    bool anyRegistered = false;
    for (const ServiceRegistration &registration : s_services) {
        if (!bus.registerService(QString::fromLatin1(registration.service))) {
            qWarning() << "aevis-shell: cannot take the D-Bus name"
                       << registration.service;
        } else {
            anyRegistered = true;
        }
    }

    if (!anyRegistered) {
        qWarning() << "aevis-shell: could not register any D-Bus services - is a shell already running?";
        return false;
    }

    return true;
}

void Shell::start()
{
    QDBusConnection bus = QDBusConnection::sessionBus();

    // Construct the dock first so its D-Bus object and geometry are available
    // to the desktop, but on Wayland defer mapping it until after the desktop.
    // DesktopSurface is a full-screen ordinary xdg-toplevel; mapping it last
    // can leave it above the dock/status bar and consume every pointer click.
    m_dock = new DockWindow(m_engine);
    bus.registerObject(QStringLiteral("/Dock"), m_dock);

    m_desktops = new DesktopManager(m_engine, this);

    // The notification service comes up before the status bar: the status bar's
    // QML holds the notification centre window and reads the models the
    // manager publishes on the engine's root context.
    m_notifications = new NotificationManager(m_engine, this);
    bus.registerObject(QStringLiteral("/Notification"), m_notifications);

    m_statusBar = new StatusBar(m_engine);
    bus.registerObject(QStringLiteral("/Statusbar"), m_statusBar);

    m_launcher = new Launcher(m_engine);
    bus.registerObject(QStringLiteral("/Launcher"),
                       QStringLiteral("org.aevis.Launcher"), m_launcher);
    bus.registerObject(QStringLiteral("/Launcher"),
                       QStringLiteral("com.cutefish.Launcher"), m_launcher);
    m_launcher->setDock(m_dock);
    m_dock->setLauncher(m_launcher);

    m_dock->show();
    m_statusBar->show();
}
