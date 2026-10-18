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

#include "statusbar.h"
#include "battery.h"
#include "appmenu/appmenu.h"
#include "statusbaradaptor.h"

#include <QQmlEngine>
#include <QQmlContext>

#include <QDBusConnection>
#include <QSettings>
#include <QScreen>
#include <QAction>
#include <QProcess>
#include <QFile>
#include <QDir>
#include <KGlobalAccel>

StatusBar::StatusBar(QQmlEngine *engine)
    : ShellSurface(engine)
    , m_acticity(Activity::self())
    , m_strutSpacer(new StrutSpacer(this))
{
    const QString localeOrg = QFile::exists(QDir::homePath() + QStringLiteral("/.config/aevis/locale.conf"))
        ? QStringLiteral("aevis")
        : QStringLiteral("cutefishos");
    QSettings settings(localeOrg, QStringLiteral("locale"));
    m_twentyFourTime = settings.value("twentyFour", false).toBool();

    setFlags(Qt::FramelessWindowHint);
    setTitle(QStringLiteral("Status Bar"));
    setColor(Qt::transparent);

    new StatusbarAdaptor(this);
    new AppMenu(this);
    setContextProperty("StatusBar", this);
    setContextProperty("acticity", m_acticity);
    setContextProperty("battery", Battery::self());

    setSource(QUrl(QStringLiteral("qrc:/statusbar/qml/main.qml")));
    configureSurfaceRole(SurfaceRole::Panel);

    // The status bar always lives on the primary screen.
    followPrimaryScreen([this] { updateGeometry(); });

    setVisible(true);
    initState();
    setupGlobalShortcuts();

    connect(m_acticity, &Activity::launchPadChanged, this, &StatusBar::initState);
}

QRect StatusBar::screenRect()
{
    return m_screenRect;
}

bool StatusBar::twentyFourTime()
{
    return m_twentyFourTime;
}

void StatusBar::setBatteryPercentage(bool enabled)
{
    Battery::self()->setShowPercentage(enabled);
}

void StatusBar::setTwentyFourTime(bool t)
{
    if (m_twentyFourTime != t) {
        m_twentyFourTime = t;
        emit twentyFourTimeChanged();
    }
}

void StatusBar::toggleSpotlight()
{
    emit spotlightRequested();
}

void StatusBar::toggleControlCenter()
{
    emit controlCenterRequested();
}

void StatusBar::updateGeometry()
{
    QScreen *s = screen();
    if (!s)
        s = qGuiApp->primaryScreen();
    if (!s)
        return;

    const QRect rect = s->geometry();

    if (m_screenRect != rect) {
        m_screenRect = rect;
        emit screenRectChanged();
    }

    const QRect windowRect(rect.x(), rect.y(), rect.width(), Height);
    setGeometry(windowRect);
    setSurfacePosition(windowRect.topLeft());

    if (m_strutSpacer) {
        m_strutSpacer->setScreen(s);
        m_strutSpacer->setEdge(Qt::TopEdge);
        m_strutSpacer->setThickness(isVisible() ? Height : 0);
    }

    updateViewStruts();
}

void StatusBar::updateViewStruts()
{
    // PlasmaSurface with Role::Panel automatically manages workarea and struts via org_kde_plasma_shell.
}

void StatusBar::initState()
{
    // The launcher is an ordinary full-screen window, so the status bar has
    // to step out of its way.
    bool visible = !m_acticity->launchPad();
    setVisible(visible);
    setPanelBehavior(m_acticity->launchPad() ? PanelBehavior::AllowCovering
                                             : PanelBehavior::StayAbove);
    if (m_strutSpacer) {
        m_strutSpacer->setThickness(visible ? Height : 0);
    }
    updateViewStruts();
}

#include <QDBusMessage>

void StatusBar::setupGlobalShortcuts()
{
    // Clear conflicting native KDE Spectacle shortcuts so they never hijack the PrtSc button
    const QString spectacleComponent = QStringLiteral("org.kde.spectacle.desktop");
    const QStringList spectacleActions = {
        QStringLiteral("_launch"),
        QStringLiteral("ActiveWindowScreenShot"),
        QStringLiteral("CurrentMonitorScreenShot"),
        QStringLiteral("FullScreenScreenShot"),
        QStringLiteral("OpenWithoutScreenshot"),
        QStringLiteral("RecordRegion"),
        QStringLiteral("RecordScreen"),
        QStringLiteral("RecordWindow"),
        QStringLiteral("RectangularRegionScreenShot"),
        QStringLiteral("WindowUnderCursorScreenShot")
    };

    for (const QString &action : spectacleActions) {
        QDBusMessage msg = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.kglobalaccel"),
            QStringLiteral("/kglobalaccel"),
            QStringLiteral("org.kde.KGlobalAccel"),
            QStringLiteral("setForeignShortcut")
        );
        msg << QStringList{spectacleComponent, action, QString(), QString()}
            << QVariant::fromValue(QList<int>());
        QDBusConnection::sessionBus().call(msg);
    }

    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::Key_Print));
    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::SHIFT | Qt::Key_Print));
    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::META | Qt::Key_Print));
    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::META | Qt::SHIFT | Qt::Key_Print));
    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::META | Qt::CTRL | Qt::Key_Print));
    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::META | Qt::SHIFT | Qt::Key_S));
    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::SHIFT | Qt::META | Qt::Key_3));
    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::SHIFT | Qt::META | Qt::Key_4));
    KGlobalAccel::stealShortcutSystemwide(QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_A));

    // Spotlight search shortcut: Meta+Space and Ctrl+Space
    QAction *spotlightAction = new QAction(this);
    spotlightAction->setObjectName(QStringLiteral("SpotlightSearch"));
}
