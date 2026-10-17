/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * HarmonyOS 6 Floating Frosted Glass OSD (Volume & Brightness HUD)
 */

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import FishUI 1.0 as FishUI
import Cutefish.StatusBar 1.0

PopupWindow {
    id: osd

    width: 220
    height: 54
    color: "transparent"
    visible: false

    property string iconSource: ""
    property int osdValue: 0
    property string osdTitle: ""

    Timer {
        id: hideTimer
        interval: 1800
        repeat: false
        onTriggered: osd.close()
    }

    function showOsd(title, icon, value) {
        osdTitle = title
        iconSource = icon
        osdValue = Math.max(0, Math.min(100, value))

        var screenRect = StatusBar.screenRect
        osd.x = Math.round(screenRect.x + (screenRect.width - osd.width) / 2)
        osd.y = Math.round(screenRect.y + screenRect.height - 120)

        osd.open()
        hideTimer.restart()
    }

    FishUI.WindowBlur {
        view: osd
        windowRadius: _bg.radius
        enabled: FishUI.Theme.blurEnabled
    }

    FishUI.WindowShadow {
        view: osd
        radius: _bg.radius
        strength: 0.60
    }

    Rectangle {
        id: _bg
        anchors.fill: parent
        radius: 27
        color: FishUI.Theme.darkMode ? Qt.rgba(0.11, 0.13, 0.18, 0.82)
                                     : Qt.rgba(0.91, 0.93, 0.97, 0.85)
        antialiasing: true
        border.width: 1 / FishUI.Dpi.ratio
        border.color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.22)
                                            : Qt.rgba(1, 1, 1, 0.90)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Image {
                width: 22
                height: 22
                sourceSize: Qt.size(44, 44)
                source: osd.iconSource
                antialiasing: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.18)
                                                 : Qt.rgba(0, 0, 0, 0.12)

                    Rectangle {
                        width: parent.width * (osd.osdValue / 100.0)
                        height: parent.height
                        radius: 4
                        color: "#007AFF"

                        Behavior on width {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            Label {
                text: osd.osdValue + "%"
                font.bold: true
                font.pointSize: 9
                color: FishUI.Theme.textColor
            }
        }
    }
}