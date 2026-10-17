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

#include "notificationmanager.h"
#include "notificationserver.h"
#include "notificationsmodel.h"
#include "historymodel.h"
#include "notification/notificationsettings.h"
#include "notificationadaptor.h"

#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QDebug>

NotificationManager::NotificationManager(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
    , m_popupsComponent(nullptr)
    , m_popups(nullptr)
    , m_server(NotificationServer::self())
    , m_model(NotificationsModel::self())
    , m_settings(NotificationSettings::self())
{
    new NotificationAdaptor(this);

    // The models are read by the banners and by the notification centre, which
    // lives in the status bar's QML, so they go on the engine's root context
    // where every shell surface can see them.
    QQmlContext *context = m_engine->rootContext();
    context->setContextProperty(QStringLiteral("notificationsModel"), m_model);
    context->setContextProperty(QStringLiteral("historyModel"), HistoryModel::self());
    context->setContextProperty(QStringLiteral("notificationManager"), this);

    connect(m_settings, &NotificationSettings::doNotDisturbChanged,
            this, &NotificationManager::doNotDisturbChanged);

    // The banners are windows of their own, spawned by an Instantiator; the
    // object holding it is never shown.
    m_popupsComponent = new QQmlComponent(m_engine,
                                          QUrl(QStringLiteral("qrc:/notification/qml/NotificationPopups.qml")),
                                          this);

    if (m_popupsComponent->isError()) {
        qWarning() << "NotificationManager: cannot load the popup host:"
                   << m_popupsComponent->errors();
        return;
    }

    m_popups = m_popupsComponent->create(context);

    if (m_popups)
        m_popups->setParent(this);
    else
        qWarning() << "NotificationManager:" << m_popupsComponent->errors();
}

NotificationManager::~NotificationManager()
{
    delete m_popups;
}

bool NotificationManager::doNotDisturb() const
{
    return m_settings->doNotDisturb();
}

void NotificationManager::setDoNotDisturb(bool enabled)
{
    m_settings->setDoNotDisturb(enabled);
}

void NotificationManager::showWindow()
{
    emit windowRequested();
}
