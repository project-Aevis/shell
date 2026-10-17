/*
 * Copyright (C) 2021 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * Author:     rekols <revenmartin@gmail.com>
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
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import Qt5Compat.GraphicalEffects
import Cutefish.Dock 1.0
import FishUI 1.0 as FishUI

Item {
    id: control

    property bool isLeft: Settings.direction === DockSettings.Left
    property bool isRight: Settings.direction === DockSettings.Right
    property bool isBottom: Settings.direction === DockSettings.Bottom

    property var iconSize: root.isHorizontal ? control.height * iconSizeRatio
                                             : control.width * iconSizeRatio

    property bool draggable: false
    property int dragItemIndex

    property alias icon: icon
    property alias mouseArea: iconArea
    property alias dropArea: iconDropArea

    property bool enableActivateDot: true
    property bool isActive: false
    property int windowCount: 0
    property int unreadCount: 0

    property string appId: ""
    property var popupText

    property double iconSizeRatio: 0.82
    property var iconName

    property bool dragStarted: false

    // macOS wave magnification properties
    readonly property real itemCenterPos: {
        if (!mainLayout) return 0
        var center = control.mapToItem(mainLayout, control.width / 2, control.height / 2)
        return root.isHorizontal ? center.x : center.y
    }

    readonly property real distToCursor: root.isHovered
        ? Math.abs(root.hoverPos - itemCenterPos)
        : 999999

    readonly property real targetScale: {
        if (!root.isHovered || distToCursor > root.magnificationSpread)
            return 1.0
        var t = distToCursor / root.magnificationSpread
        var bell = Math.cos(t * Math.PI * 0.5)
        return 1.0 + (root.maxMagnification - 1.0) * (bell * bell)
    }

    property real currentScale: 1.0

    Behavior on currentScale {
        NumberAnimation {
            duration: root.isHovered ? 45 : 180
            easing.type: root.isHovered ? Easing.OutCubic : Easing.OutBack
        }
    }

    onTargetScaleChanged: {
        currentScale = targetScale
    }

    // Dynamic Z-ordering: the highest magnified icon draws on top of adjacent icons
    z: Math.round(control.currentScale * 100)

    // Tactile click compression
    property real clickScale: iconArea.pressed && !mouseArea.drag.active ? 0.92 : 1.0
    Behavior on clickScale {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutQuad
        }
    }

    property real bounceOffset: 0
    property bool isBouncing: false

    SequentialAnimation {
        id: bounceAnim
        loops: Animation.Infinite

        NumberAnimation {
            target: control
            property: "bounceOffset"
            to: 14
            duration: 250
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: control
            property: "bounceOffset"
            to: 0
            duration: 250
            easing.type: Easing.InQuad
        }
        PauseAnimation {
            duration: 80
        }
    }

    Timer {
        id: bounceTimeout
        interval: 8000
        repeat: false
        onTriggered: control.stopBounce()
    }

    function startBounce() {
        if (!isBouncing) {
            isBouncing = true
            bounceAnim.start()
            bounceTimeout.restart()
        }
    }

    function stopBounce() {
        if (isBouncing) {
            isBouncing = false
            bounceAnim.stop()
            bounceTimeout.stop()
            bounceOffset = 0
        }
    }

    signal positionChanged()
    signal released()
    signal pressed(var mouse)
    signal pressAndHold(var mouse)
    signal clicked(var mouse)
    signal doubleClicked(var mouse)
    signal rightClicked(var mouse)
    signal dropped(var drop)

    function updatePopupTipsPosition() {
        if (!iconArea.containsMouse)
            return

        var controlPosition = control.mapToGlobal(0, 0)
        var magOffset = control.currentScale > 1.0 ? control.iconSize * (control.currentScale - 1.0) * 0.45 : 0
        if (Settings.direction === DockSettings.Left)
            popupTips.position = Qt.point(root.mapToGlobal(root.width, 0).x + FishUI.Units.largeSpacing + magOffset,
                                          controlPosition.y + (control.height / 2 - popupTips.height / 2))
        else if (Settings.direction === DockSettings.Right)
            popupTips.position = Qt.point(root.mapToGlobal(0, 0).x - popupTips.width - FishUI.Units.largeSpacing - magOffset,
                                          controlPosition.y + (control.height / 2 - popupTips.height / 2))
        else
            popupTips.position = Qt.point(controlPosition.x + (control.width / 2 - popupTips.width / 2),
                                          root.mapToGlobal(0, 0).y - popupTips.height - FishUI.Units.smallSpacing - magOffset)
    }

    function updateWindowPreviewPosition() {
        if (typeof windowPreviewPopup === "undefined" || !windowPreviewPopup)
            return

        var controlPosition = control.mapToGlobal(0, 0)
        var magOffset = control.currentScale > 1.0 ? control.iconSize * (control.currentScale - 1.0) * 0.45 : 0
        var targetX = 0
        var targetY = 0

        if (Settings.direction === DockSettings.Left) {
            targetX = root.mapToGlobal(root.width, 0).x + FishUI.Units.largeSpacing + 4 + magOffset
            targetY = controlPosition.y + (control.height / 2 - windowPreviewPopup.height / 2)
        } else if (Settings.direction === DockSettings.Right) {
            targetX = root.mapToGlobal(0, 0).x - windowPreviewPopup.width - FishUI.Units.largeSpacing - 4 - magOffset
            targetY = controlPosition.y + (control.height / 2 - windowPreviewPopup.height / 2)
        } else {
            targetX = controlPosition.x + (control.width / 2 - windowPreviewPopup.width / 2)
            targetY = root.mapToGlobal(0, 0).y - windowPreviewPopup.height - FishUI.Units.largeSpacing - 4 - magOffset
        }

        windowPreviewPopup.popupPosition = Qt.point(targetX, targetY)
        windowPreviewPopup.adjustCorrectLocation()
    }

    function popupMenu(menu) {
        menu.ensureLayout()
        menu.transientParent = control.Window.window
        menu.availableGeometry = root.menuAvailableGeometry()

        var iconPosition = icon.mapToGlobal(0, 0)
        var menuWidth = menu.popupContentItem.implicitWidth
        var menuHeight = menu.popupContentItem.implicitHeight

        if (Settings.direction === DockSettings.Left)
            menu.popupAt(root.mapToGlobal(root.width, 0).x + FishUI.Units.largeSpacing,
                         iconPosition.y)
        else if (Settings.direction === DockSettings.Right)
            menu.popupAt(root.mapToGlobal(0, 0).x - menuWidth - FishUI.Units.largeSpacing,
                         iconPosition.y)
        else
            menu.popupAt(iconPosition.x,
                         root.mapToGlobal(0, 0).y - menuHeight - FishUI.Units.smallSpacing)
    }

    function resolveIconSource(name) {
        if (!name) return "image://icontheme/application-x-desktop"
        var s = (typeof name === "string") ? name : ("" + name)
        if (s.length === 0) return "image://icontheme/application-x-desktop"
        if (s.indexOf("qrc:/") === 0 || s.indexOf(":/") === 0) {
            if (s.indexOf(":/") === 0 && s.indexOf("qrc:/") !== 0) {
                return "qrc" + s
            }
            return s
        }
        if (s.indexOf("file:/") === 0)
            return s
        if (s.indexOf("/") === 0)
            return "file://" + s
        if (s.indexOf("image://") === 0)
            return s
        return "image://icontheme/" + s
    }

    function refreshIcon() {
        if (icon) {
            var src = resolveIconSource(iconName)
            if (icon.source !== src)
                icon.source = src
        }
    }

    onIconNameChanged: refreshIcon()
    onIconSizeChanged: refreshIcon()

    Component.onCompleted: refreshIcon()

    Drag.active: mouseArea.drag.active && control.draggable
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.MoveAction
    Drag.hotSpot.x: icon.width / 2
    Drag.hotSpot.y: icon.height / 2

    Drag.onDragStarted:  {
        dragStarted = true
    }

    Drag.onDragFinished: {
        dragStarted = false
    }

    Image {
        id: icon
        x: (parent.width - width) / 2 + (control.isLeft ? control.bounceOffset : (control.isRight ? -control.bounceOffset : 0))
        y: (parent.height - height) / 2 - (control.isBottom ? control.bounceOffset : 0)
        width: control.iconSize
        height: control.iconSize
        source: control.resolveIconSource(control.iconName)
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        mipmap: true
        smooth: true
        antialiasing: true

        function updateIcon() {
            var s = icon.source
            icon.source = ""
            icon.source = s
        }

        visible: !dragStarted

        scale: control.currentScale * control.clickScale
        transformOrigin: root.isLeft ? Item.Left
                       : root.isRight ? Item.Right
                       : Item.Bottom

        // Tactile light sheen on click
        Rectangle {
            anchors.fill: parent
            radius: width * 0.22
            color: FishUI.Theme.darkMode ? "#ffffff" : "#000000"
            opacity: iconArea.pressed && !mouseArea.drag.active ? 0.15 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }

        onStatusChanged: {
            if (status === Image.Error && source !== "image://icontheme/application-x-desktop") {
                source = "image://icontheme/application-x-desktop"
            }
        }
    }

    DropArea {
        id: iconDropArea
        anchors.fill: parent
        enabled: draggable
        onDropped: function(drop) { control.dropped(drop) }
    }

    MouseArea {
        id: iconArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        drag.axis: Drag.XAndYAxis

        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                control.rightClicked(mouse)
            else
                control.clicked(mouse)
        }

        onDoubleClicked: function(mouse) { control.doubleClicked(mouse) }

        onPressed: function(mouse) {
            control.pressed(mouse)
            popupTips.hide()
            if (typeof windowPreviewPopup !== "undefined" && windowPreviewPopup)
                windowPreviewPopup.hide()
        }

        onPositionChanged: function(mouse) {
            var p = control.mapToItem(mainLayout, mouse.x, mouse.y)
            root.hoverPos = root.isHorizontal ? p.x : p.y
            root.isHovered = true
            hoverResetTimer.restart()
            dock.setMouseOverDock(true)

            if (pressed) {
                if (control.draggable && mouse.source !== Qt.MouseEventSynthesizedByQt) {
                    drag.target = icon
                    icon.grabToImage(function(result) {
                        control.Drag.imageSource = result.url
                    })
                } else {
                    drag.target = null
                }
            }

            control.positionChanged()
        }

        onPressAndHold: function(mouse) { control.pressAndHold(mouse) }
        onReleased: {
            drag.target = null
            control.released()
        }

        onContainsMouseChanged: {
            if (containsMouse) {
                if (control.windowCount > 0 && control.appId) {
                    if (root.showWindowPreview(control.appId, control.popupText, control)) {
                        return
                    }
                }
                if (control.popupText !== "") {
                    if (typeof windowPreviewPopup !== "undefined" && windowPreviewPopup)
                        windowPreviewPopup.hide()
                    popupTips.popupText = control.popupText
                    popupPositionTimer.restart()
                }
            } else {
                popupPositionTimer.stop()
                popupTips.hide()
                if (control.appId) {
                    root.scheduleHideWindowPreview(control.appId)
                }
            }
        }
    }

    Timer {
        id: popupPositionTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (iconArea.containsMouse && popupTips.popupText !== "") {
                if (!popupTips.visible) {
                    popupTips.show()
                    restart()
                } else {
                    control.updatePopupTipsPosition()
                }
            }
        }
    }

    // Unread Notification / Multi-Window Badge (Top-Right of Icon)
    Rectangle {
        id: countBadge
        z: 10
        anchors.top: icon.top
        anchors.topMargin: -2
        anchors.right: icon.right
        anchors.rightMargin: -2
        width: Math.max(18, countText.implicitWidth + 8)
        height: 18
        radius: 9
        color: control.unreadCount > 0 ? "#FF3B30" : "#007AFF"
        border.width: 1.5
        border.color: FishUI.Theme.darkMode ? "#1C1C1E" : "#FFFFFF"
        antialiasing: true
        visible: (control.unreadCount > 0 || (control.windowCount > 1 && control.unreadCount > 0)) && !dragStarted

        scale: visible ? 1.0 : 0.0
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

        Text {
            id: countText
            anchors.centerIn: parent
            text: control.unreadCount > 0 ? (control.unreadCount > 99 ? "99+" : control.unreadCount)
                                          : (control.windowCount > 99 ? "99+" : control.windowCount)
            font.bold: true
            font.pixelSize: 10
            renderType: Text.NativeRendering
            color: "#FFFFFF"
        }
    }

    // macOS / Modern Capsule Pearl Indicator Dot
    Item {
        id: activeDotContainer
        z: 100

        readonly property real baseDotSize: (typeof root !== "undefined" && root.activeDotSize) ? Math.max(5, root.activeDotSize) : 5
        readonly property bool isMultiWindow: control.windowCount > 1

        width: (isMultiWindow && isBottom) ? (baseDotSize * 2.3) : baseDotSize
        height: (isMultiWindow && !isBottom) ? (baseDotSize * 2.3) : baseDotSize

        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        anchors.horizontalCenter: isBottom ? icon.horizontalCenter : undefined
        anchors.top: isBottom ? icon.bottom : undefined
        anchors.topMargin: isBottom ? 3 : 0

        anchors.verticalCenter: !isBottom ? icon.verticalCenter : undefined
        anchors.right: isLeft ? icon.left : undefined
        anchors.rightMargin: isLeft ? 3 : 0
        anchors.left: isRight ? icon.right : undefined
        anchors.leftMargin: isRight ? 3 : 0

        visible: (enableActivateDot || control.windowCount > 0) && !dragStarted

        opacity: (enableActivateDot || control.windowCount > 0) ? 1.0 : 0.0
        scale: (enableActivateDot || control.windowCount > 0) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

        // Glow halo for frontmost active app
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 8
            height: parent.height + 8
            radius: Math.min(width, height) / 2
            color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.30)
                                         : Qt.rgba(0, 0, 0, 0.20)
            visible: control.isActive
            Behavior on visible { PropertyAnimation { duration: 200 } }
        }

        // Crisp capsule / circular pearl dot with subtle contrast rim
        Rectangle {
            id: activeDot
            anchors.fill: parent
            radius: Math.min(width, height) / 2
            border.width: 0.5
            border.color: FishUI.Theme.darkMode ? Qt.rgba(0, 0, 0, 0.35)
                                                : Qt.rgba(255, 255, 255, 0.7)
            color: {
                if (control.isActive) {
                    return FishUI.Theme.darkMode ? "#FFFFFF"
                                                 : "#1C1C1E"
                } else {
                    return FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.85)
                                                 : Qt.rgba(0, 0, 0, 0.65)
                }
            }

            Behavior on color {
                ColorAnimation { duration: 180 }
            }
        }
    }
}
