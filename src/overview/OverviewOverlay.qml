/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * GNOME-Style Window Overview / Mission Control Expose Overlay with Workspace Switcher & Live Filter
 */

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import Cutefish.Shell 1.0
import FishUI 1.0 as FishUI

Popup {
    id: overviewRoot

    anchors.centerIn: parent
    width: parent ? parent.width : 1280
    height: parent ? parent.height : 800
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: FishUI.Theme.darkMode ? Qt.rgba(0.06, 0.06, 0.08, 0.82) : Qt.rgba(0.92, 0.92, 0.96, 0.85)
        FishUI.WindowBlur {
            view: overviewRoot
            enabled: FishUI.Theme.blurEnabled
        }
    }

    contentItem: Item {
        anchors.fill: parent

        // Header / Search Bar (GNOME style)
        ColumnLayout {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 40
            spacing: 14

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Mission Control & Overview")
                font.bold: true
                font.pointSize: 20
                renderType: Text.NativeRendering
                color: FishUI.Theme.textColor
            }

            // Search box
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 380
                height: 40
                radius: 20
                color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)
                border.width: 1 / FishUI.Dpi.ratio
                border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.18) : Qt.rgba(0, 0, 0, 0.1)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8

                    Text {
                        text: "🔍"
                        font.pixelSize: 14
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        font.pointSize: 11
                        renderType: Text.NativeRendering
                        color: FishUI.Theme.textColor
                        selectByMouse: true
                        placeholderText: qsTr("Type to filter open windows...")
                    }
                }
            }
        }

        // Active Windows Grid (Expose / Mission Control)
        GridView {
            id: windowGrid
            anchors.centerIn: parent
            width: Math.min(parent.width - 120, cellWidth * 3)
            height: Math.min(parent.height - 220, 480)
            cellWidth: 320
            cellHeight: 240
            clip: true

            delegate: Rectangle {
                width: 300
                height: 220
                radius: 16
                color: delegateMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.1))
                                                   : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(255, 255, 255, 0.70))
                border.width: 1 / FishUI.Dpi.ratio
                border.color: delegateMouse.containsMouse ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.15) : Qt.rgba(0, 0, 0, 0.08))
                antialiasing: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Image {
                            width: 20
                            height: 20
                            sourceSize: Qt.size(40, 40)
                            source: model.iconName ? ("image://icontheme/" + model.iconName) : "image://icontheme/application-x-desktop"
                        }

                        Label {
                            text: model.title ? model.title : qsTr("Window")
                            font.bold: true
                            font.pointSize: 9.5
                            renderType: Text.NativeRendering
                            color: FishUI.Theme.textColor
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 11
                            color: closeMouse.pressed ? "#ef4444" : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.1))

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                font.pixelSize: 14
                                color: FishUI.Theme.textColor
                            }

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                onClicked: kwinInterface.closeWindow(model.windowId)
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: FishUI.Theme.darkMode ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.5)
                        border.width: 1 / FishUI.Dpi.ratio
                        border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(0, 0, 0, 0.05)

                        Item {
                            anchors.fill: parent
                            anchors.margins: 8

                            Label {
                                anchors.centerIn: parent
                                text: model.appName ? model.appName : qsTr("Application")
                                font.pointSize: 12
                                font.bold: true
                                renderType: Text.NativeRendering
                                color: FishUI.Theme.disabledTextColor
                            }
                        }
                    }
                }

                MouseArea {
                    id: delegateMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        kwinInterface.focusWindow(model.windowId)
                        overviewRoot.close()
                    }
                }
            }
        }

        // Bottom Workspace Switcher (macOS / GNOME style)
        RowLayout {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 32
            spacing: 16

            Repeater {
                model: 2
                delegate: Rectangle {
                    width: 90
                    height: 56
                    radius: 10
                    color: index === 0 ? Qt.rgba(0, 122, 255, 0.3) : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.06))
                    border.width: index === 0 ? 2 : 1 / FishUI.Dpi.ratio
                    border.color: index === 0 ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.15) : Qt.rgba(0, 0, 0, 0.1))
                    antialiasing: true

                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Desktop %1").arg(index + 1)
                        font.pointSize: 8.5
                        renderType: Text.NativeRendering
                        color: FishUI.Theme.textColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            // Workspace switch action
                        }
                    }
                }
            }
        }
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            overviewRoot.close()
        }
    }
}
