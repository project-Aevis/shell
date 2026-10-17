/*
 * Copyright (C) 2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * WindowPreviewPopup.qml - Live interactive taskbar/dock window preview cards
 */

import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import FishUI 1.0 as FishUI
import Cutefish.Dock 1.0
import org.kde.taskmanager 0.1 as TaskManager
import org.kde.pipewire 1.0 as PipeWire

Window {
    id: previewPopup
    visible: false
    color: "transparent"
    flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.ToolTip

    property string appId: ""
    property string appName: ""
    property var windows: []
    property point popupPosition: Qt.point(0, 0)
    property var currentItem: null

    HoverHandler {
        id: popupHoverHandler
    }

    property bool containsCursor: popupHoverHandler.hovered || popupMouseArea.containsMouse

    signal windowActivated(string wid)
    signal windowClosed(string wid)

    width: mainCard.implicitWidth
    height: mainCard.implicitHeight

    x: popupPosition.x
    y: popupPosition.y

    FishUI.WindowHelper {
        id: windowHelper
    }

    FishUI.WindowShadow {
        view: previewPopup
        radius: mainCard.radius + 4
        strength: 0.4
    }

    FishUI.WindowBlur {
        view: previewPopup
        enabled: FishUI.Theme.blurEnabled
        windowRadius: mainCard.radius
    }

    MouseArea {
        id: popupMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    onPopupPositionChanged: adjustCorrectLocation()
    onWidthChanged: {
        if (currentItem)
            currentItem.updateWindowPreviewPosition()
        else
            adjustCorrectLocation()
    }
    onHeightChanged: {
        if (currentItem)
            currentItem.updateWindowPreviewPosition()
        else
            adjustCorrectLocation()
    }

    function adjustCorrectLocation() {
        var posX = previewPopup.popupPosition.x
        var posY = previewPopup.popupPosition.y

        // On Wayland, positions are relative to parent surface; clamping to Screen coordinates
        // forces the preview into the panel area and causes severe blinking.
        if (windowHelper.wayland) {
            previewPopup.x = posX
            previewPopup.y = posY
            return
        }

        // Bounds checking against virtual desktop/screen coordinates
        if (posX <= Screen.virtualX + FishUI.Units.smallSpacing)
            posX = Screen.virtualX + FishUI.Units.smallSpacing

        if (posY <= Screen.virtualY + FishUI.Units.smallSpacing)
            posY = Screen.virtualY + FishUI.Units.smallSpacing

        if (posX + previewPopup.width > Screen.virtualX + Screen.width)
            posX = Screen.virtualX + Screen.width - previewPopup.width - FishUI.Units.smallSpacing

        if (posY + previewPopup.height > Screen.virtualY + Screen.height)
            posY = Screen.virtualY + Screen.height - previewPopup.height - FishUI.Units.smallSpacing

        previewPopup.x = posX
        previewPopup.y = posY
    }

    function show() {
        if (windowHelper.popupMenuVisible())
            return
        visible = true
    }

    function hide() {
        visible = false
        windows = []
        appId = ""
    }

    Rectangle {
        id: mainCard
        anchors.fill: parent
        implicitWidth: windows.length > 0 ? Math.max(previewCol.implicitWidth + 20, 220) : (titleLabel.implicitWidth + 24)
        implicitHeight: windows.length > 0 ? (previewCol.implicitHeight + 20) : (titleLabel.implicitHeight + 14)

        radius: 12
        color: FishUI.Theme.darkMode
               ? Qt.rgba(0.12, 0.12, 0.16, FishUI.Theme.blurEnabled ? 0.82 : 0.96)
               : Qt.rgba(0.96, 0.96, 0.98, FishUI.Theme.blurEnabled ? 0.86 : 0.98)
        border.width: 1 / FishUI.Dpi.ratio
        border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.16)
                                            : Qt.rgba(0, 0, 0, 0.12)

        // Simple text label when no running windows exist
        Label {
            id: titleLabel
            anchors.centerIn: parent
            visible: previewPopup.windows.length === 0
            text: previewPopup.appName
            font.bold: true
            font.pointSize: 10
            color: FishUI.Theme.textColor
        }

        ColumnLayout {
            id: previewCol
            anchors.centerIn: parent
            spacing: 8
            visible: previewPopup.windows.length > 0

            // Header Row: App Name and "+ New Window" Quick Action
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                spacing: 8

                Label {
                    text: previewPopup.appName
                    font.bold: true
                    font.pixelSize: 11
                    color: FishUI.Theme.textColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    height: 20
                    width: newWinLayout.implicitWidth + 12
                    radius: 10
                    color: newWinMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))
                                               : (newWinMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                    border.width: 1 / FishUI.Dpi.ratio
                    border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.14) : Qt.rgba(0, 0, 0, 0.10)
                    antialiasing: true

                    RowLayout {
                        id: newWinLayout
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "+"
                            font.bold: true
                            font.pixelSize: 12
                            color: FishUI.Theme.highlightColor
                        }

                        Label {
                            id: newWinText
                            text: qsTr("New Window")
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: FishUI.Theme.textColor
                        }
                    }

                    MouseArea {
                        id: newWinMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            appModel.openNewInstance(previewPopup.appId)
                            previewPopup.hide()
                        }
                    }
                }
            }

            // Horizontal row of window preview tiles
            Row {
                id: previewRow
                spacing: 10

            Repeater {
                model: previewPopup.windows

                Item {
                    id: tileItem
                    width: 200
                    height: 142

                    readonly property var winData: modelData || {}
                    readonly property bool isCurrentActive: winData ? (winData.active === true) : false
                    readonly property bool isMinimized: winData ? (winData.minimized === true) : false
                    property bool hovered: tileMouseArea.containsMouse || closeMouseArea.containsMouse

                    Rectangle {
                        id: tileBg
                        anchors.fill: parent
                        radius: 8
                        color: tileItem.hovered
                               ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                               : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))
                        border.width: tileItem.isCurrentActive ? 2 : 1
                        border.color: tileItem.isCurrentActive
                                      ? FishUI.Theme.highlightColor
                                      : (tileItem.hovered
                                         ? (FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.28) : Qt.rgba(0, 0, 0, 0.20))
                                         : (FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(0, 0, 0, 0.08)))

                        scale: tileItem.hovered ? 1.02 : 1.0

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                        MouseArea {
                            id: tileMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                previewPopup.windowActivated(winData.wid)
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 6

                            // Top Header: App Icon, Window Title, Close Button
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                FishUI.IconItem {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: (winData && winData.iconName) ? winData.iconName : "application-x-desktop"
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: (winData && winData.title) ? winData.title : ""
                                    font.pixelSize: 11
                                    font.bold: tileItem.isCurrentActive
                                    color: FishUI.Theme.textColor
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                // Close Button (x)
                                Rectangle {
                                    id: closeBtn
                                    z: 10
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 10
                                    color: closeMouseArea.containsMouse
                                           ? "#FF453A"
                                           : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.10))

                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u00d7"
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: closeMouseArea.containsMouse ? "#FFFFFF" : FishUI.Theme.textColor
                                    }

                                    MouseArea {
                                        id: closeMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            mouse.accepted = true
                                            previewPopup.windowClosed(winData.wid)
                                        }
                                    }
                                }
                            }

                            // Body: Hardware-accelerated live PipeWire window canvas preview
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 6
                                clip: true
                                color: FishUI.Theme.darkMode ? "#141416" : "#E8E8ED"
                                border.width: 1
                                border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                                TaskManager.ScreencastingRequest {
                                    id: scRequest
                                    uuid: (previewPopup.visible && winData && winData.uuid) ? winData.uuid : ""
                                }

                                // Fallback placeholder with centered app icon
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    opacity: (!pipewireItem.ready || tileItem.isMinimized) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    FishUI.IconItem {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredWidth: 38
                                        Layout.preferredHeight: 38
                                        source: (winData && winData.iconName) ? winData.iconName : "application-x-desktop"
                                        opacity: tileItem.isMinimized ? 0.50 : 0.85
                                    }
                                }

                                // Live Wayland window stream via PipeWire
                                PipeWire.PipeWireSourceItem {
                                    id: pipewireItem
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    nodeId: (previewPopup.visible && scRequest.nodeId > 0) ? scRequest.nodeId : 0
                                    visible: previewPopup.visible && scRequest.nodeId > 0 && !tileItem.isMinimized
                                    opacity: ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }

                                // Minimized status badge pill
                                Rectangle {
                                    visible: tileItem.isMinimized
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 8
                                    height: 18
                                    width: minLabel.implicitWidth + 14
                                    radius: 9
                                    color: FishUI.Theme.darkMode ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0.2, 0.2, 0.2, 0.65)

                                    Label {
                                        id: minLabel
                                        anchors.centerIn: parent
                                        text: qsTr("Minimized")
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                        color: "#FFFFFF"
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
        }
    }
}

