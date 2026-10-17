/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * macOS Notification Banner Popup
 */

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import QtQuick.Window 2.12
import Qt5Compat.GraphicalEffects
import FishUI 1.0 as FishUI
import Cutefish.Notification 1.0

NotificationPopup {
    id: control
    flags: Qt.WindowDoesNotAcceptFocus | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    width: 340
    height: Math.max(68, _contentLayout.implicitHeight + 20)
    color: "transparent"
    visible: false
    onVisibleChanged: if (visible) timer.restart()

    property int defaultTimeout: 6000

    FishUI.WindowShadow {
        view: control
        radius: _background.radius
        strength: 0.35
    }

    FishUI.WindowBlur {
        view: control
        windowRadius: _background.radius
        enabled: FishUI.Theme.blurEnabled
    }

    Item {
        id: _contentWrapper
        anchors.fill: parent

        Rectangle {
            id: _background
            anchors.fill: parent
            radius: 14
            color: FishUI.Theme.darkMode ? Qt.rgba(0.12, 0.12, 0.15, FishUI.Theme.blurEnabled ? 0.78 : 0.98)
                                         : Qt.rgba(0.96, 0.96, 0.98, FishUI.Theme.blurEnabled ? 0.78 : 0.98)
            border.width: 1 / FishUI.Dpi.ratio
            border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(0, 0, 0, 0.06)
        }

        MouseArea {
            id: _mouseArea
            anchors.fill: parent
            hoverEnabled: true
            drag.target: _contentWrapper
            drag.axis: Drag.XAxis
            drag.minimumX: -300
            drag.maximumX: 300

            onEntered: timer.stop()
            onExited: timer.restart()

            onReleased: {
                if (Math.abs(_contentWrapper.x) > 80) {
                    swipeDismissAnim.start()
                } else {
                    snapBackAnim.start()
                }
            }

            onClicked: {
                if (Math.abs(_contentWrapper.x) < 5) {
                    if (model.hasDefaultAction) {
                        notificationsModel.invokeDefaultAction(model.notificationId)
                    }
                    notificationsModel.close(model.notificationId)
                }
            }
        }

        NumberAnimation {
            id: snapBackAnim
            target: _contentWrapper
            property: "x"
            to: 0
            duration: 180
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: swipeDismissAnim
            target: _contentWrapper
            property: "x"
            to: _contentWrapper.x > 0 ? 400 : -400
            duration: 200
            easing.type: Easing.InQuad
            onFinished: {
                notificationsModel.close(model.notificationId)
                _contentWrapper.x = 0
            }
        }

    ColumnLayout {
        id: _contentLayout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4

        // Top Row: App Icon, App Name, Timestamp, Close Button
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Image {
                id: _icon
                width: 18
                height: 18
                source: model.iconName ? "image://icontheme/%1".arg(model.iconName) : ""
                sourceSize: Qt.size(18, 18)
                Layout.alignment: Qt.AlignVCenter
                antialiasing: true
                smooth: true
                visible: status === Image.Ready
            }

            Image {
                id: _defaultIcon
                width: 18
                height: 18
                source: "image://icontheme/preferences-desktop-notification"
                sourceSize: Qt.size(18, 18)
                Layout.alignment: Qt.AlignVCenter
                antialiasing: true
                smooth: true
                visible: !_icon.visible
            }

            Label {
                text: (model.appName && model.appName.length > 0) ? model.appName : qsTr("Notification")
                font.weight: Font.DemiBold
                font.pointSize: 8.5
                renderType: Text.NativeRendering
                color: FishUI.Theme.textColor
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Label {
                text: qsTr("now")
                font.pointSize: 7.5
                renderType: Text.NativeRendering
                color: FishUI.Theme.disabledTextColor
                Layout.alignment: Qt.AlignVCenter
            }

            // Close button
            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: _closeBtnArea.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.14))
                                             : (_closeBtnArea.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                                                                            : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)))
                border.width: 1 / FishUI.Dpi.ratio
                border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                visible: _mouseArea.containsMouse || _closeBtnArea.containsMouse
                antialiasing: true

                Behavior on color {
                    ColorAnimation { duration: 100 }
                }

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: _closeBtnArea.containsMouse ? FishUI.Theme.textColor : FishUI.Theme.disabledTextColor
                }

                MouseArea {
                    id: _closeBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: timer.stop()
                    onClicked: notificationsModel.close(model.notificationId)
                }
            }
        }

        // Summary Title
        Label {
            text: model.summary
            visible: text.length > 0
            font.weight: Font.DemiBold
            font.pointSize: 9
            renderType: FishUI.Theme.renderType
            color: FishUI.Theme.textColor
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        // Body Text
        Label {
            text: model.body
            visible: text.length > 0
            font.pointSize: 8
            renderType: FishUI.Theme.renderType
            color: FishUI.Theme.textColor
            opacity: 0.78
            maximumLineCount: 2
            elide: Text.ElideRight
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
    }

    Timer {
        id: timer
        interval: control.defaultTimeout
        onTriggered: notificationsModel.expired(model.notificationId)
    }
}
