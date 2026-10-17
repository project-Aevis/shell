/*
 * Copyright (C) 2021 CutefishOS.
 *
 * Author:     Reoin Wong <reion@cutefishos.com>
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

import QtQuick 2.12
import QtQuick.Controls 2.12
import Qt5Compat.GraphicalEffects
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import Cutefish.Shell 1.0
import FishUI 1.0 as FishUI
import Cutefish.Launcher 1.0

Item {
    id: control

    property bool searchMode: false

    property int pageIndex: 0
    property int pageCount: 0

    property int iconSize: 96
    property int labelPixelSize: 13
    property int labelHeight: 32
    property int spacing: 12

    // The AllAppsView this delegate belongs to.
    property Item view: null

    readonly property int itemIndex: index
    readonly property bool dragging: control.view && control.view.draggedAppId === model.appId

    // Tracked by hand: a window-level drag takes the mouse grab away, so the
    // MouseArea never sees the release and would stay pressed after the drop.
    property bool iconPressed: false

    // Set while this delegate holds a drag that has not been acted on yet.
    property bool reorderPending: false

    z: dragging ? 2 : 0

    onDraggingChanged: control.iconPressed = false

    Image {
        id: icon

        width: control.iconSize
        height: control.iconSize
        sourceSize: Qt.size(control.iconSize, control.iconSize)

        x: Math.round((control.width - width) / 2)
        y: Math.round((control.height - height - control.labelHeight - control.spacing) / 2)

        source: model.iconName ? (model.iconName.indexOf("/") === 0 ? "file://" + model.iconName : "image://icontheme/" + model.iconName) : ""
        visible: !control.dragging
        opacity: control.iconPressed && !control.dragging ? 0.6 : 1.0
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    DropArea {
        id: dropArea

        anchors.fill: parent
        keys: ["application/x-cutefish-desktop-id"]
        enabled: !control.searchMode

        onEntered: {
            control.reorderPending = true
            reorderTimer.restart()
        }

        onExited: {
            control.reorderPending = false
            reorderTimer.stop()
        }

        onDropped: function (drop) {
            reorderTimer.stop()
            drop.accept(Qt.MoveAction)

            // A swap re-binds this delegate to the slot the other icon came
            // from, so reordering again here would undo the dwell's move.
            if (control.reorderPending)
                control.reorder(drop.source)
            control.reorderPending = false
        }
    }

    function reorder(source) {
        if (!control.view || source !== control.view.dragSource
                || !control.view.draggedAppId)
            return

        // The view applies it: a cross-page move resets the page models and
        // destroys this delegate.
        control.view.requestMove(control.itemIndex + control.pageIndex * control.pageCount)
    }

    // Hovering a neighbour long enough swaps it, rather than waiting for the
    // button to come up.
    Timer {
        id: reorderTimer

        interval: 90

        onTriggered: {
            if (!dropArea.containsDrag || !control.view)
                return

            // Wait out the previous swap's animation.
            if (control.view.settling()) {
                reorderTimer.restart()
                return
            }

            control.reorderPending = false
            control.reorder(dropArea.drag.source)
        }
    }

    ScreenHelper {
        id: _screenHelper
    }

    FishUI.DesktopMenu {
        id: _itemMenu
        availableGeometry: _screenHelper.availableScreenRect
        blurEnabled: FishUI.Theme.blurEnabled

        MenuItem {
            text: qsTr("Open")
            onTriggered: launcherModel.launch(model.appId)
        }

        MenuItem {
            id: sendToDock
            text: qsTr("Send to dock")
            onTriggered: launcher.sendToDock(model.appId)
        }

        MenuItem {
            id: sendToDesktop
            text: qsTr("Send to desktop")
            onTriggered: launcherModel.sendToDesktop(model.appId)
        }

        MenuItem {
            id: removeFromDock
            text: qsTr("Remove from dock")
            onTriggered: launcher.removeFromDock(model.appId)
        }

        MenuItem {
            id: uninstallItem
            text: qsTr("Uninstall")
            onTriggered: {
                root.uninstallDialog.desktopPath = model.appId
                root.uninstallDialog.appName = model.name
                root.uninstallDialog.visible = true
            }
        }

        function updateActions() {
            sendToDock.visible = launcher.dockAvailable() && !launcher.isPinedDock(model.appId)
            removeFromDock.visible = launcher.dockAvailable() && launcher.isPinedDock(model.appId)
        }
    }

    // Only the icon is clickable; the label and the gaps fall through to the
    // page's dismiss handler.
    MouseArea {
        id: iconMouseArea

        x: icon.x
        y: icon.y
        width: icon.width
        height: icon.height

        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // The view is a Flickable and would steal the grab on the first few
        // pixels of movement, paging the grid instead of starting the drag.
        // Dragging the view from anywhere else still works.
        preventStealing: true

        // The drag threshold is tracked by hand: MouseArea's own drag machinery
        // needs a target item to move, and here the compositor moves the icon.
        property point pressPoint
        property url dragImage
        // One drag per press.
        property bool dragArmed: false

        onPressed: function (mouse) {
            control.iconPressed = true
            iconMouseArea.dragArmed = true
            iconMouseArea.pressPoint = Qt.point(mouse.x, mouse.y)
            iconMouseArea.dragImage = ""
            icon.grabToImage(function (result) {
                iconMouseArea.dragImage = result.url
            })
        }

        onReleased: control.iconPressed = false
        onCanceled: control.iconPressed = false

        onPositionChanged: function (mouse) {
            if (!iconMouseArea.dragArmed || !(mouse.buttons & Qt.LeftButton)
                    || control.searchMode || control.dragging || !control.view)
                return

            const dx = mouse.x - iconMouseArea.pressPoint.x
            const dy = mouse.y - iconMouseArea.pressPoint.y
            if (dx * dx + dy * dy < Math.pow(Qt.styleHints.startDragDistance, 2))
                return

            // The image the compositor carries has to exist before the drag
            // goes active. It is grabbed on press so this does not have to
            // wait a frame for it.
            iconMouseArea.dragArmed = false

            if (iconMouseArea.dragImage != "") {
                control.view.startDrag(model.appId, iconMouseArea.dragImage)
                return
            }

            icon.grabToImage(function (result) {
                // grabToImage is asynchronous; the button may be up by now.
                if (!control.iconPressed)
                    return

                control.view.startDrag(model.appId, result.url)
            })
        }

        onClicked: function (mouse) {
            if (mouse.button === Qt.LeftButton) {
                launcherModel.launch(model.appId)
            } else if (mouse.button === Qt.RightButton) {
                uninstallItem.visible = appManager.isCutefishOS()
                _itemMenu.updateActions()
                _itemMenu.popup()
            }
        }
    }

    Rectangle {
        id: newInstallPoint

        width: Math.max(5, Math.round(control.iconSize * 0.06))
        height: width
        radius: height / 2

        visible: !control.dragging && model.newInstalled

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: label.top
        anchors.bottomMargin: Math.round(control.spacing / 3)

        color: FishUI.Theme.highlightColor
    }

    Label {
        id: label

        x: Math.round((control.width - width) / 2)
        y: icon.y + icon.height + control.spacing

        width: control.width - control.spacing * 2
        height: control.labelHeight

        visible: !control.dragging

        text: model.name
        elide: Text.ElideRight
        textFormat: Text.PlainText
        maximumLineCount: 2
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignTop
        font: Qt.font({ family: Qt.application.font.family,
                        pixelSize: control.labelPixelSize })
        color: "white"
    }
}
