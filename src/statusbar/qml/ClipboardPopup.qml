/*
 * Copyright (C) 2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * macOS-style Clipboard Manager Popup
 */

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12

import Cutefish.StatusBar 1.0
import Cutefish.Shell 1.0
import FishUI 1.0 as FishUI

PopupWindow {
    id: control

    width: 330
    height: Math.min(460, _mainLayout.implicitHeight + 24)

    property var margin: 6
    property point position: Qt.point(0, 0)
    property string searchQuery: ""

    onWidthChanged: adjustCorrectLocation()
    onHeightChanged: adjustCorrectLocation()
    onPositionChanged: adjustCorrectLocation()

    color: "transparent"

    function adjustCorrectLocation() {
        var posX = control.position.x
        var posY = control.position.y

        if (posX + control.width >= StatusBar.screenRect.x + StatusBar.screenRect.width)
            posX = StatusBar.screenRect.x + StatusBar.screenRect.width - control.width - control.margin

        posY = rootItem.y + rootItem.height + control.margin

        control.x = Math.round(posX)
        control.y = Math.round(posY)
    }

    property var clipboardHelper: null

    ClipboardHelper {
        id: _fallbackClipboardHelper
    }

    readonly property var activeClipboardHelper: clipboardHelper ? clipboardHelper : _fallbackClipboardHelper

    FishUI.WindowBlur {
        view: control
        windowRadius: _background.radius
        enabled: FishUI.Theme.blurEnabled
    }

    FishUI.WindowShadow {
        view: control
        radius: _background.radius
        strength: 0.35
    }

    Rectangle {
        id: _background
        anchors.fill: parent
        radius: 16
        color: FishUI.Theme.darkMode
               ? Qt.rgba(0.14, 0.14, 0.16, FishUI.Theme.blurEnabled ? 0.76 : 1.0)
               : Qt.rgba(0.96, 0.96, 0.98, FishUI.Theme.blurEnabled ? 0.76 : 1.0)
        antialiasing: true
        border.width: 1 / FishUI.Dpi.ratio
        border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(0, 0, 0, 0.06)
    }

    ColumnLayout {
        id: _mainLayout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // Header Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Image {
                width: 16
                height: 16
                sourceSize: Qt.size(16, 16)
                source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "clipboard.svg"
            }

            Text {
                text: qsTr("Clipboard")
                font.pointSize: 12
                font.weight: Font.DemiBold
                color: FishUI.Theme.textColor
                Layout.fillWidth: true
            }

            // Clear All Button
            Rectangle {
                id: clearBtn
                width: clearTxt.implicitWidth + 14
                height: 24
                radius: 12
                color: clearMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.12))
                     : clearMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                     : "transparent"
                border.width: 1 / FishUI.Dpi.ratio
                border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(0, 0, 0, 0.10)
                visible: activeClipboardHelper.count > 0

                Text {
                    id: clearTxt
                    anchors.centerIn: parent
                    text: qsTr("Clear All")
                    font.pointSize: 9
                    color: FishUI.Theme.textColor
                    opacity: 0.8
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        activeClipboardHelper.clear()
                    }
                }
            }
        }

        // Search Box
        Rectangle {
            Layout.fillWidth: true
            height: 28
            radius: 8
            color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04)
            border.width: 1 / FishUI.Dpi.ratio
            border.color: searchInput.activeFocus ? FishUI.Theme.highlightColor : (FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(0, 0, 0, 0.08))

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Image {
                    width: 12
                    height: 12
                    sourceSize: Qt.size(12, 12)
                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "system-search-symbolic.svg"
                    opacity: 0.5
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    font.pointSize: 10
                    color: FishUI.Theme.textColor
                    selectByMouse: true
                    clip: true
                    onTextChanged: {
                        control.searchQuery = text.toLowerCase().trim()
                    }

                    Text {
                        anchors.fill: parent
                        text: qsTr("Search clips...")
                        font.pointSize: 10
                        color: FishUI.Theme.textColor
                        opacity: 0.4
                        visible: !parent.text && !parent.activeFocus
                    }
                }

                // Clear search text button
                Text {
                    text: "✕"
                    font.pointSize: 9
                    color: FishUI.Theme.textColor
                    opacity: 0.5
                    visible: searchInput.text.length > 0
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchInput.text = ""
                    }
                }
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            height: 1 / FishUI.Dpi.ratio
            color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(0, 0, 0, 0.06)
        }

        // Clips List
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(320, Math.max(80, clipView.contentHeight))
            clip: true

            ListView {
                id: clipView
                anchors.fill: parent
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds

                model: {
                    var list = activeClipboardHelper.history
                    if (!control.searchQuery)
                        return list
                    var filtered = []
                    for (var i = 0; i < list.length; i++) {
                        if (list[i].toLowerCase().indexOf(control.searchQuery) !== -1)
                            filtered.push(list[i])
                    }
                    return filtered
                }

                delegate: Rectangle {
                    id: clipDelegate
                    width: clipView.width
                    height: Math.min(54, clipText.implicitHeight + 14)
                    radius: 8
                    color: itemMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
                         : itemMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.05))
                         : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        // Index badge
                        Rectangle {
                            width: 18
                            height: 18
                            radius: 4
                            color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 4

                            Text {
                                anchors.centerIn: parent
                                text: (index + 1)
                                font.pointSize: 8
                                font.weight: Font.DemiBold
                                color: FishUI.Theme.textColor
                                opacity: 0.6
                            }
                        }

                        // Content text preview
                        Text {
                            id: clipText
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: modelData
                            font.pointSize: 9.5
                            color: FishUI.Theme.textColor
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            wrapMode: Text.WrapAnywhere
                        }

                        // Delete single item button (visible on hover)
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: delMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.15)) : "transparent"
                            visible: itemMouse.containsMouse
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                font.pointSize: 11
                                color: FishUI.Theme.textColor
                                opacity: 0.6
                            }

                            MouseArea {
                                id: delMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    activeClipboardHelper.remove(index)
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            activeClipboardHelper.copy(modelData)
                            control.close()
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    id: scrollBar
                    policy: clipView.contentHeight > clipView.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                }
            }

            // Empty state
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8
                visible: clipView.count === 0

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    width: 32
                    height: 32
                    sourceSize: Qt.size(32, 32)
                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "clipboard.svg"
                    opacity: 0.3
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: control.searchQuery ? qsTr("No matching items") : qsTr("Clipboard is empty")
                    font.pointSize: 10
                    color: FishUI.Theme.textColor
                    opacity: 0.5
                }
            }
        }
    }
}
