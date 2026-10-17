/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * Stage Manager - Left Edge Recent App Carousel (macOS Sequoia Style)
 */

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import Cutefish.Shell 1.0
import FishUI 1.0 as FishUI

Item {
    id: stageManagerRoot

    property bool enabled: false
    width: enabled ? 80 : 0
    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

    visible: width > 0

    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    z: 9999

    Rectangle {
        anchors.fill: parent
        color: FishUI.Theme.darkMode ? Qt.rgba(0.08, 0.08, 0.12, 0.92) : Qt.rgba(0.95, 0.95, 0.97, 0.95)
        border.width: 1 / FishUI.Dpi.ratio
        border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.15) : Qt.rgba(0, 0, 0, 0.08)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        Repeater {
            model: 3
            delegate: Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 56
                height: 56
                radius: 12
                color: index === 0 ? Qt.rgba(0, 122, 255, 0.25) : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.06))
                border.width: index === 0 ? 2 : 1 / FishUI.Dpi.ratio
                border.color: index === 0 ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.15) : Qt.rgba(0, 0, 0, 0.08))
                antialiasing: true

                Image {
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    sourceSize: Qt.size(56, 56)
                    source: "image://icontheme/application-x-desktop"
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        // Switch stage group
                    }
                }
            }
        }
    }
}
