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
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import Qt5Compat.GraphicalEffects

import Cutefish.Dock 1.0
import Cutefish.Shell 1.0
import FishUI 1.0 as FishUI

Item {
    id: root
    visible: true

    property bool isLeft: Settings.direction === DockSettings.Left
    property bool isRight: Settings.direction === DockSettings.Right
    property bool isHorizontal: Settings.direction === DockSettings.Bottom

    // Geometry shared with Dock, see src/dockmetrics.h. The dock is a
    // row (or column) of icons with padding at both ends, and the running dot
    // lives between the icons and the screen edge.
    property var metrics: dock.metrics
    property int iconGap: metrics.iconGap
    property int lengthPadding: metrics.lengthPadding
    property int outerPadding: metrics.outerPadding
    property int activeDotGap: metrics.dotGap
    property int activeDotSize: metrics.dotSize
    property int edgePadding: metrics.edgePadding
    property int dotAreaSize: edgePadding + activeDotSize + activeDotGap
    property int thickness: isHorizontal ? root.height : root.width
    property real windowRadius: thickness * 28 / 86
    property real iconSizeRatio: 1.0
    property int itemSize: (metrics && metrics.iconSize) ? metrics.iconSize : Math.max(1, thickness - root.dotAreaSize - root.outerPadding)

    property real hoverPos: -1
    property bool isHovered: false
    property real maxMagnification: 1.40
    property real magnificationSpread: root.itemSize * 2.3
    property int dividerSlotWidth: 14

    ScreenHelper {
        id: _screenHelper
    }

    // Item positions come out in surface coordinates: a plasma-shell panel is
    // reported at (0, 0) on Wayland. A menu clamps its position against this
    // rectangle, so hand it the work area in that same space.
    function menuAvailableGeometry() {
        var origin = root.mapToGlobal(0, 0)
        var rect = _screenHelper.availableScreenRect
        return Qt.rect(rect.x + origin.x - dock.surfacePosition.x,
                       rect.y + origin.y - dock.surfacePosition.y,
                       rect.width, rect.height)
    }

    function areWindowListsEqual(a, b) {
        if (!a || !b || a.length !== b.length)
            return false
        for (var i = 0; i < a.length; ++i) {
            if (!a[i] || !b[i])
                return false
            if (a[i].wid !== b[i].wid || a[i].uuid !== b[i].uuid || a[i].minimized !== b[i].minimized || a[i].title !== b[i].title)
                return false
        }
        return true
    }

    function showWindowPreview(appId, appName, item) {
        var wins = appModel.windowsForApp(appId)
        if (wins && wins.length > 0) {
            previewDismissTimer.stop()
            popupTips.hide()
            windowPreviewPopup.currentItem = item
            windowPreviewPopup.appName = appName
            if (windowPreviewPopup.appId !== appId || !areWindowListsEqual(windowPreviewPopup.windows, wins)) {
                windowPreviewPopup.appId = appId
                windowPreviewPopup.windows = wins
            }
            item.updateWindowPreviewPosition()
            dock.previewOpen = true
            windowPreviewPopup.show()
            return true
        }
        return false
    }

    function scheduleHideWindowPreview(appId) {
        if (windowPreviewPopup.visible && windowPreviewPopup.appId === appId) {
            previewDismissTimer.restart()
        }
    }

    DropArea {
        anchors.fill: parent
        enabled: true
    }

    // Theme-tinted translucent dock surface.
    Rectangle {
        id: _background

        anchors.fill: parent
        radius: root.windowRadius
        color: FishUI.Theme.darkMode
               ? Qt.rgba(0.08, 0.08, 0.12, FishUI.Theme.blurEnabled ? 0.68 : 0.98)
               : Qt.rgba(0.96, 0.96, 0.98, FishUI.Theme.blurEnabled ? 0.72 : 0.98)
        border.width: 1 / FishUI.Dpi.ratio
        border.pixelAligned: FishUI.Dpi.ratio > 1 ? false : true
        border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.12)
                                            : Qt.rgba(0, 0, 0, 0.08)
    }

    FishUI.WindowShadow {
        view: dock
        strength: 0.35
        radius: _background.radius + 4
    }

    FishUI.WindowBlur {
        view: dock
        windowRadius: _background.radius
        enabled: FishUI.Theme.blurEnabled
    }

    // Theme-aware dock tooltip.
    FishUI.PopupTips {
        id: popupTips
        backgroundColor: FishUI.Theme.darkMode ? Qt.rgba(0.12, 0.12, 0.14, 0.92)
                                               : Qt.rgba(0.96, 0.96, 0.98, 0.95)
        borderColor: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.20)
                                           : Qt.rgba(0, 0, 0, 0.15)
        blurEnabled: FishUI.Theme.blurEnabled
    }

    WindowPreviewPopup {
        id: windowPreviewPopup
        transientParent: dock

        onWindowActivated: function(wid) {
            appModel.activateWindow(wid)
            windowPreviewPopup.hide()
            dock.previewOpen = false
        }

        onWindowClosed: function(wid) {
            appModel.closeWindow(wid)
            var updated = appModel.windowsForApp(windowPreviewPopup.appId)
            if (updated && updated.length > 0) {
                windowPreviewPopup.windows = updated
            } else {
                windowPreviewPopup.hide()
                dock.previewOpen = false
            }
        }

        onVisibleChanged: {
            if (!visible) {
                dock.previewOpen = false
                windowPreviewPopup.currentItem = null
                windowPreviewPopup.windows = []
                windowPreviewPopup.appId = ""
            }
        }
    }

    Timer {
        id: previewDismissTimer
        interval: 280
        repeat: false
        onTriggered: {
            if (!windowPreviewPopup.containsCursor) {
                windowPreviewPopup.hide()
                dock.previewOpen = false
            }
        }
    }

    Connections {
        target: windowPreviewPopup
        function onContainsCursorChanged() {
            if (!windowPreviewPopup.containsCursor) {
                previewDismissTimer.restart()
            } else {
                previewDismissTimer.stop()
            }
        }
    }

    Connections {
        target: popupTips
        function onVisibleChanged() {
            dock.popupTipsOpen = popupTips.visible
        }
    }

    HoverHandler {
        id: rootHoverHandler
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        onHoveredChanged: {
            dock.setMouseOverDock(hovered)
        }
    }

    // Non-blocking hover tracker for continuous magnification wave across dock
    MouseArea {
        id: backgroundHoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
            var p = mapToItem(mainLayout, mouse.x, mouse.y)
            root.hoverPos = root.isHorizontal ? p.x : p.y
            root.isHovered = true
            hoverResetTimer.restart()
            dock.setMouseOverDock(true)
        }
        onExited: {
            hoverResetTimer.restart()
            dock.setMouseOverDock(false)
        }
    }

    Timer {
        id: hoverResetTimer
        interval: 90
        repeat: false
        onTriggered: {
            root.isHovered = false
            root.hoverPos = -1
        }
    }

    GridLayout {
        id: mainLayout
        anchors.centerIn: parent
        flow: root.isHorizontal ? Grid.LeftToRight : Grid.TopToBottom
        columns: root.isHorizontal ? -1 : 1
        rows: root.isHorizontal ? 1 : -1
        columnSpacing: root.isHorizontal ? root.iconGap : 0
        rowSpacing: root.isHorizontal ? 0 : root.iconGap

        // 1. Pinned Apps ListView (Left/Top of Divider)
        ListView {
            id: pinnedAppItemView
            orientation: root.isHorizontal ? Qt.Horizontal : Qt.Vertical
            spacing: root.iconGap
            snapMode: ListView.SnapToItem
            interactive: false
            model: appModel ? appModel.pinnedModel : null
            clip: false

            Layout.fillHeight: !root.isHorizontal
            Layout.fillWidth: root.isHorizontal
            Layout.preferredWidth: root.isHorizontal ? (contentWidth + 2) : root.itemSize
            Layout.preferredHeight: root.isHorizontal ? root.itemSize : (contentHeight + 2)

            Layout.maximumWidth: root.isHorizontal
                ? Math.max(root.itemSize, root.width - (unpinnedAppItemView.contentWidth + root.dividerSlotWidth + root.itemSize + 4 * root.iconGap + 2 * root.lengthPadding))
                : root.itemSize
            Layout.maximumHeight: !root.isHorizontal
                ? Math.max(root.itemSize, root.height - (unpinnedAppItemView.contentHeight + root.dividerSlotWidth + root.itemSize + 4 * root.iconGap + 2 * root.lengthPadding))
                : root.itemSize

            delegate: AppItem {
                id: pinnedAppItemDelegate
                property bool shouldAnimateOnAdd: dock.geometryAnimationAdding
                                                 && model.animationToken === dock.geometryAnimationToken
                property real addProgress: shouldAnimateOnAdd
                                          ? dock.geometryAnimationProgress : 1.0
                property real layoutProgress: addProgress
                property real layoutWidth: root.itemSize * layoutProgress
                property real layoutHeight: root.itemSize * layoutProgress

                width: root.isHorizontal ? layoutWidth : root.itemSize
                height: root.isHorizontal ? root.itemSize : layoutHeight
                scale: addProgress
                transformOrigin: Item.Center
                opacity: addProgress
                iconSizeRatio: root.iconSizeRatio
            }
        }

        // 2. macOS Glass Divider
        Item {
            id: dockDivider
            implicitWidth: root.isHorizontal ? root.dividerSlotWidth : root.itemSize
            implicitHeight: root.isHorizontal ? root.itemSize : root.dividerSlotWidth
            Layout.alignment: Qt.AlignCenter

            Rectangle {
                anchors.centerIn: parent
                width: root.isHorizontal ? 1 : parent.width * 0.58
                height: root.isHorizontal ? parent.height * 0.58 : 1
                radius: 0.5
                color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.18)
                                             : Qt.rgba(0, 0, 0, 0.18)

                Rectangle {
                    width: root.isHorizontal ? 1 : parent.width
                    height: root.isHorizontal ? parent.height : 1
                    x: root.isHorizontal ? 1 : 0
                    y: root.isHorizontal ? 0 : 1
                    color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.06)
                                                 : Qt.rgba(255, 255, 255, 0.5)
                }
            }
        }

        // 3. Unpinned Apps ListView (Right/Bottom of Divider, Left/Top of Trash Bin)
        ListView {
            id: unpinnedAppItemView
            orientation: root.isHorizontal ? Qt.Horizontal : Qt.Vertical
            spacing: root.iconGap
            snapMode: ListView.SnapToItem
            interactive: false
            model: appModel ? appModel.unpinnedModel : null
            clip: false

            Layout.fillHeight: !root.isHorizontal
            Layout.fillWidth: root.isHorizontal
            Layout.preferredWidth: root.isHorizontal ? (contentWidth + 2) : root.itemSize
            Layout.preferredHeight: root.isHorizontal ? root.itemSize : (contentHeight + 2)

            Layout.maximumWidth: root.isHorizontal
                ? Math.max(0, root.width - (pinnedAppItemView.contentWidth + root.dividerSlotWidth + root.itemSize + 4 * root.iconGap + 2 * root.lengthPadding))
                : root.itemSize
            Layout.maximumHeight: !root.isHorizontal
                ? Math.max(0, root.height - (pinnedAppItemView.contentHeight + root.dividerSlotWidth + root.itemSize + 4 * root.iconGap + 2 * root.lengthPadding))
                : root.itemSize

            delegate: AppItem {
                id: unpinnedAppItemDelegate
                property bool shouldAnimateOnAdd: dock.geometryAnimationAdding
                                                 && model.animationToken === dock.geometryAnimationToken
                property real addProgress: shouldAnimateOnAdd
                                          ? dock.geometryAnimationProgress : 1.0
                property real layoutProgress: addProgress
                property real layoutWidth: root.itemSize * layoutProgress
                property real layoutHeight: root.itemSize * layoutProgress

                width: root.isHorizontal ? layoutWidth : root.itemSize
                height: root.isHorizontal ? root.itemSize : layoutHeight
                scale: addProgress
                transformOrigin: Item.Center
                opacity: addProgress
                iconSizeRatio: root.iconSizeRatio
            }
        }

        DockItem {
            id: trashItem
            implicitWidth: root.itemSize
            implicitHeight: root.itemSize
            iconSizeRatio: root.iconSizeRatio
            popupText: qsTr("Trash")
            enableActivateDot: false
            iconName: trash.count === 0 ? "user-trash-empty" : "user-trash-full"
            onClicked: trash.openTrash()
            onRightClicked: popupMenu(trashMenu)

            dropArea.enabled: true

            onDropped: function(drop) {
                if (drop.hasUrls) {
                    trash.moveToTrash(drop.urls)
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: FishUI.Units.smallSpacing / 2
                color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.12)
                                             : Qt.rgba(0, 0, 0, 0.08)
                border.color: FishUI.Theme.highlightColor
                radius: height * 0.28
                border.width: 1.5
                opacity: trashItem.dropArea.containsDrag ? 0.9 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 180
                    }
                }
            }

            FishUI.DesktopMenu {
                id: trashMenu
                blurEnabled: FishUI.Theme.blurEnabled

                MenuItem {
                    text: qsTr("Open")
                    onTriggered: trash.openTrash()
                }

                MenuItem {
                    text: qsTr("Empty Trash")
                    onTriggered: trash.emptyTrash()
                    visible: trash.count !== 0
                }
            }
        }
    }

    Connections {
        target: Settings

        function onDirectionChanged() {
            popupTips.hide()
            windowPreviewPopup.hide()
            dock.previewOpen = false
        }
    }

    Connections {
        target: dock

        function onVisibleChanged() {
            popupTips.hide()
            windowPreviewPopup.hide()
            dock.previewOpen = false
        }
    }
}
