/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * Dock AppItem - macOS / GNOME 50 App-Specific Quick Actions
 */

import QtQuick 2.12
import QtQuick.Controls 2.12
import Cutefish.Dock 1.0
import Cutefish.Shell 1.0
import FishUI 1.0 as FishUI

DockItem {
    id: appItem

    appId: (model && model.appId) ? model.appId : ""
    windowCount: (model && model.windowCount !== undefined) ? model.windowCount : 0
    property var windowIds: model.windowIds
    property var dragSource: null

    iconName: model.iconName ? model.iconName : "application-x-desktop"
    isActive: model.isActive ? model.isActive : false
    popupText: model.visibleName
    enableActivateDot: windowCount > 0
    draggable: !model.fixed
    dragItemIndex: index

    function updateMinimizedGeometry() {
        minimizedGeometryTimer.restart()
    }

    onWindowCountChanged: {
        if (windowCount > 0)
            stopBounce()
        updateMinimizedGeometry()
    }

    onWindowIdsChanged: updateMinimizedGeometry()

    Component.onCompleted: updateMinimizedGeometry()

    Connections {
        target: icon

        function onXChanged() {
            appItem.updateMinimizedGeometry()
        }

        function onYChanged() {
            appItem.updateMinimizedGeometry()
        }

        function onWidthChanged() {
            appItem.updateMinimizedGeometry()
        }

        function onHeightChanged() {
            appItem.updateMinimizedGeometry()
        }
    }

    Connections {
        target: dock

        function onMinimizedGeometrySurfaceChanged() {
            appItem.updateMinimizedGeometry()
        }
    }

    Timer {
        id: minimizedGeometryTimer
        interval: 0
        repeat: false
        onTriggered: dock.updateIconGeometry(icon, windowIds)
    }

    onRightClicked: {
        if (model.appId !== "cutefish-launcher" && model.appId !== "aevis-launcher")
            popupMenu(contextMenu)
    }

    onDoubleClicked: function(mouse) {
        if (mouse.button === Qt.LeftButton) {
            var id = model.appId.toLowerCase()
            if (id.indexOf("firefox") !== -1) {
                startBounce()
                appModel.openAction(model.appId, "firefox -P")
            } else if (id.indexOf("chrome") !== -1 || id.indexOf("chromium") !== -1 || id.indexOf("brave") !== -1) {
                startBounce()
                popupMenu(contextMenu)
            } else if (model.appId === "cutefish-launcher" || model.appId === "aevis-launcher") {
                appModel.clicked(model.appId)
            } else {
                startBounce()
                popupMenu(contextMenu)
            }
        } else if (mouse.button === Qt.RightButton) {
            if (model.appId !== "cutefish-launcher" && model.appId !== "aevis-launcher")
                popupMenu(contextMenu)
        }
    }

    onClicked: function(mouse) {
        if (mouse.button === Qt.LeftButton) {
            if (windowCount === 0 && model.appId !== "cutefish-launcher" && model.appId !== "aevis-launcher")
                startBounce()
            appModel.clicked(model.appId)
        } else if (mouse.button === Qt.MiddleButton) {
            if (model.appId !== "cutefish-launcher" && model.appId !== "aevis-launcher") {
                startBounce()
                appModel.openNewInstance(model.appId)
            }
        }
    }

    dropArea.onEntered: function(drag) {
        appItem.dragSource = drag.source
        dropTimer.restart()
    }

    dropArea.onExited: {
        appItem.dragSource = null
        dropTimer.stop()
    }

    dropArea.onDropped: {
        appModel.save()
    }

    Timer {
        id: dropTimer
        interval: 300
        onTriggered: {
            if (appItem.dragSource)
                appModel.move(appItem.dragSource.dragItemIndex,
                              appItem.dragItemIndex)
            else
                appModel.raiseWindow(model.appId)
        }
    }

    FishUI.DesktopMenu {
        id: contextMenu
        blurEnabled: FishUI.Theme.blurEnabled

        onVisibleChanged: {
            if (typeof dock !== "undefined" && dock)
                dock.menuOpen = visible
        }

        // Standard Open
        MenuItem {
            text: qsTr("Open")
            visible: windowCount === 0
            icon.name: "document-open"
            onTriggered: {
                startBounce()
                appModel.openNewInstance(model.appId)
            }
        }

        // App-Specific Quick Action: Firefox Profile Chooser
        MenuItem {
            text: qsTr("Choose Profile / Profile Manager")
            visible: model.appId.toLowerCase().indexOf("firefox") !== -1
            icon.name: "user-bookmarks"
            onTriggered: {
                startBounce()
                appModel.openAction(model.appId, "firefox -P")
            }
        }

        // App-Specific Quick Action: Firefox New Private Window
        MenuItem {
            text: qsTr("Open New Private Window")
            visible: model.appId.toLowerCase().indexOf("firefox") !== -1
            icon.name: "view-private"
            onTriggered: {
                startBounce()
                appModel.openAction(model.appId, "firefox --private-window")
            }
        }

        // App-Specific Quick Action: Chrome New Incognito Window
        MenuItem {
            text: qsTr("Open New Incognito Window")
            visible: model.appId.toLowerCase().indexOf("chrome") !== -1 || model.appId.toLowerCase().indexOf("chromium") !== -1 || model.appId.toLowerCase().indexOf("brave") !== -1
            icon.name: "view-private"
            onTriggered: {
                startBounce()
                appModel.openAction(model.appId, model.appId + " --incognito")
            }
        }

        // App-Specific Quick Action: VS Code / Code
        MenuItem {
            text: qsTr("Open New Empty Window")
            visible: model.appId.toLowerCase().indexOf("code") !== -1 || model.appId.toLowerCase().indexOf("vscodium") !== -1
            icon.name: "window-new"
            onTriggered: {
                startBounce()
                appModel.openAction(model.appId, "code -n")
            }
        }

        // App-Specific Quick Action: Terminal
        MenuItem {
            text: qsTr("Open New Terminal Window")
            visible: model.appId.toLowerCase().indexOf("terminal") !== -1 || model.appId.toLowerCase().indexOf("kitty") !== -1
            icon.name: "utilities-terminal"
            onTriggered: {
                startBounce()
                appModel.openAction(model.appId, model.appId)
            }
        }

        // App-Specific Quick Action: File Manager Downloads
        MenuItem {
            text: qsTr("Open Downloads Folder")
            visible: model.appId.indexOf("filemanager") !== -1 || model.appId.indexOf("nautilus") !== -1
            icon.name: "folder-download"
            onTriggered: {
                startBounce()
                appModel.openAction(model.appId, "cutefish-filemanager ~/Downloads")
            }
        }

        // App-Specific Quick Action: File Manager Home
        MenuItem {
            text: qsTr("Open Home Directory")
            visible: model.appId.indexOf("filemanager") !== -1 || model.appId.indexOf("nautilus") !== -1
            icon.name: "user-home"
            onTriggered: {
                startBounce()
                appModel.openAction(model.appId, "cutefish-filemanager ~")
            }
        }

        MenuItem {
            text: qsTr("New Window")
            visible: windowCount > 0 && model.appId !== "cutefish-launcher" && model.appId !== "aevis-launcher"
            icon.name: "window-new"
            onTriggered: {
                startBounce()
                appModel.openNewInstance(model.appId)
            }
        }

        MenuItem {
            text: qsTr("Show %1").arg(model.visibleName)
            visible: windowCount > 0 && model.visibleName
            icon.name: "view-restore"
            onTriggered: {
                appModel.raiseWindow(model.appId)
            }
        }

        MenuSeparator {
            visible: windowCount > 0
        }

        MenuItem {
            text: qsTr("Close All Windows")
            visible: windowCount !== 0
            icon.name: "window-close"
            onTriggered: appModel.closeAllByAppId(model.appId)
        }

        MenuSeparator {
            visible: model.desktopFile !== ""
        }

        MenuItem {
            text: model.isPinned ? qsTr("Unpin") : qsTr("Pin")
            visible: model.desktopFile !== ""
            icon.name: model.isPinned ? "list-remove" : "list-add"
            onTriggered: {
                model.isPinned ? appModel.unPin(model.appId) : appModel.pin(model.appId)
            }
        }

        MenuSeparator {
            visible: windowCount !== 0 && model.desktopFile !== ""
        }

        MenuItem {
            visible: windowCount !== 0
            text: qsTr("Quit")
            icon.name: "application-exit"
            onTriggered: appModel.quit(model.appId)
        }
    }
}
