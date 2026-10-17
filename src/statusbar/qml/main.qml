/*
 * Copyright (C) 2021 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * Author:     Reion Wong <aj@cutefishos.com>
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
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import QtQuick.Window 2.12
import Qt5Compat.GraphicalEffects

import Cutefish.Accounts 1.0 as Accounts
import Cutefish.Appearance 1.0 as Appearance
import Cutefish.Shell 1.0
import Cutefish.StatusBar 1.0
import Cutefish.Network 1.0 as NM
import Cutefish.Audio 1.0
import FishUI 1.0 as FishUI

Item {
    id: rootItem

    property int iconSize: 18

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    SinkModel {
        id: paSinkModel
    }

    ClipboardHelper {
        id: globalClipboardHelper
    }

    readonly property var defaultSink: paSinkModel.defaultSink
    readonly property real defaultSinkValue: defaultSink ? defaultSink.volume / PulseAudio.NormalVolume * 100.0 : -1
    readonly property string volumeIconName: {
        if (!defaultSink || defaultSink.muted || defaultSinkValue <= 0)
            return "audio-volume-muted-symbolic"
        else if (defaultSinkValue <= 25)
            return "audio-volume-low-symbolic"
        else if (defaultSinkValue <= 75)
            return "audio-volume-medium-symbolic"
        else
            return "audio-volume-high-symbolic"
    }

    // True when the bar needs light contents, i.e. what is behind it is dark.
    property bool darkMode: bgHelper.valid ? bgHelper.useLightForeground
                                           : sysWallpaper.darkMode
    property color textColor: rootItem.darkMode ? "#FFFFFF" : "#000000";
    property int fontSize: 10

    property var timeFormat: StatusBar.twentyFourTime ? "ddd MMM d  HH:mm" : "ddd MMM d  h:mm AP"

    onTimeFormatChanged: {
        timeTimer.interval = 50
        timeTimer.restart()
    }

    Appearance.Wallpaper {
        id: sysWallpaper

        function reload() {
            if (!sysWallpaper.backgroundVisible)
                bgHelper.setUnavailable()
            else if (sysWallpaper.type === 0)
                bgHelper.setBackground(sysWallpaper.path,
                                       sysWallpaper.darkMode && sysWallpaper.dimsWallpaper)
            else
                bgHelper.setColor(sysWallpaper.color)
        }

        Component.onCompleted: sysWallpaper.reload()

        onTypeChanged: sysWallpaper.reload()
        onColorChanged: sysWallpaper.reload()
        onPathChanged: sysWallpaper.reload()
        onBackgroundVisibleChanged: sysWallpaper.reload()
        onDarkModeChanged: sysWallpaper.reload()
        onDimsWallpaperChanged: sysWallpaper.reload()
    }

    Accounts.UserAccount {
        id: currentUser
    }

    ContinuityManager {
        id: continuity
    }

    StatusBarForegroundHelper {
        id: bgHelper
    }

    FishUI.PopupTips {
        id: popupTips
    }

    // Wayland tells a client nothing about the panels, so the menus are given
    // the work area the shell itself reserves.
    ScreenHelper {
        id: screenHelper
    }

    FishUI.WindowBlur {
        view: rootItem.Window.window
        windowRadius: 0
        enabled: FishUI.Theme.blurEnabled
    }

    Rectangle {
        id: barBackground
        anchors.fill: parent
        color: rootItem.darkMode
               ? Qt.rgba(0.08, 0.08, 0.10, FishUI.Theme.blurEnabled ? 0.65 : 0.98)
               : Qt.rgba(0.96, 0.96, 0.98, FishUI.Theme.blurEnabled ? 0.72 : 0.98)
        z: -2

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1 / FishUI.Dpi.ratio
            color: rootItem.darkMode ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(0, 0, 0, 0.08)
        }
    }

    // Application menu
    //
    // The menu bar behaves the way macOS does: the pointer switches between
    // the menus while one of them is open, and so do the arrow keys. Both
    // reuse a single popup window - closing and reopening one would hand the
    // keyboard grab back and forth and lose the menu the user is in.
    //
    // The switch is driven by the menu bar's own hover. The open menu sees the
    // pointer too, but only as coordinates in whatever window the compositor
    // handed the event to, and on Wayland a client does not know where its
    // windows are: the dock reports its own top left as the origin, so the
    // pointer crossing the dock used to read as a walk along the menu bar.
    property int appMenuIndex: -1

    function openAppMenu(index, keyboard) {
        if (index < 0 || index >= appMenuView.count)
            return

        var item = appMenuView.itemAtIndex(index)
        if (!item)
            return

        var menuObject = appMenuModel.menuAt(index)

        // A menu bar entry can be a plain action instead of a menu.
        if (!menuObject) {
            rootItem.closeAppMenu()
            appMenuModel.trigger(index)
            return
        }

        appMenuPopup.closeSubmenus()
        appMenuPopup.menuModel = null
        appMenuPopupModel.menu = menuObject
        appMenuPopup.menuModel = appMenuPopupModel
        appMenuPopup.setCurrentIndex(-1)
        appMenuPopup.keyboardNavigation = !!keyboard

        rootItem.appMenuIndex = index

        rootItem.popupMenuAt(appMenuPopup, item)
    }

    function closeAppMenu() {
        rootItem.appMenuIndex = -1

        if (appMenuPopup.visible)
            appMenuPopup.dismissAllPopups()
    }

    function popupMenuAt(menu, item) {
        menu.transientParent = rootItem.Window.window
        var pos = item.mapToGlobal(0, item.height + FishUI.Units.smallSpacing)
        menu.popupAt(pos.x, pos.y)
    }

    // Left and right walk to the neighbouring menu, wrapping around.
    function stepAppMenu(step) {
        var count = appMenuView.count
        if (count === 0)
            return

        rootItem.openAppMenu((rootItem.appMenuIndex + step + count) % count, true)
    }

    QMenuModel {
        id: appMenuPopupModel
    }

    QMenuPopup {
        id: appMenuPopup

        availableGeometry: screenHelper.availableScreenRect

        onKeyNavigationLeft: rootItem.stepAppMenu(-1)
        onKeyNavigationRight: rootItem.stepAppMenu(1)

        onVisibleChanged: {
            if (!visible)
                rootItem.appMenuIndex = -1
        }
    }

    // Main layout
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: FishUI.Units.largeSpacing
        anchors.rightMargin: FishUI.Units.largeSpacing
        spacing: FishUI.Units.largeSpacing

        // Apple system menu
        StandardItem {
            id: userItem

            checked: userMenu.item ? userMenu.item.visible : false
            Layout.fillHeight: true
            Layout.preferredWidth: rootItem.iconSize + FishUI.Units.largeSpacing * 2

            onClicked: {
                if (!userMenu.active) {
                    userMenu.active = true
                    return
                }

                if (!userMenu.item)
                    return

                if (userMenu.item.visible) {
                    userMenu.item.dismissAllPopups()
                } else {
                    var pos = mapToGlobal(0, height + FishUI.Units.smallSpacing)
                    userMenu.item.showAt(pos.x, pos.y)
                }
            }

            BarIcon {
                id: osLogo
                anchors.centerIn: parent
                width: rootItem.iconSize
                height: width
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit
                mipmap: true
                smooth: true
                antialiasing: true
                source: "qrc:/statusbar/images/aevis-logo.svg"
                dropShadow: rootItem.darkMode
            }
        }

        // App menu
        Item {
            id: appMenuItem
            Layout.fillHeight: true
            Layout.fillWidth: true

            ListView {
                id: appMenuView
                anchors.fill: parent
                orientation: Qt.Horizontal
                spacing: FishUI.Units.smallSpacing
                visible: appMenuModel.visible
                interactive: false
                clip: true

                model: appMenuModel

                onVisibleChanged: {
                    if (!visible)
                        rootItem.closeAppMenu()
                }

                delegate: StandardItem {
                    id: _menuItem
                    width: _actionText.width + FishUI.Units.largeSpacing
                    height: ListView.view.height
                    checked: rootItem.appMenuIndex === index

                    BarLabel {
                        id: _actionText
                        anchors.centerIn: parent
                        color: rootItem.textColor
                        font.bold: index === 0
                        font.pointSize: rootItem.fontSize
                        dropShadow: rootItem.darkMode
                        text: {
                            var text = activeMenu
                            text = text.replace(/([^&]*)&(.)([^&]*)/g, function (match, p1, p2, p3) {
                                return p1.concat(p2, p3)
                            })
                            return text
                        }
                    }

                    // A menu opens on click or double-click. While one is
                    // open, moving onto another entry switches to it: whether
                    // the pointer event reaches the menu bar or the menu
                    // depends on how the compositor routes the popup grab,
                    // so both are wired up to the same switch.
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: rootItem.appMenuIndex !== -1
                        onClicked: rootItem.openAppMenu(index)
                        onDoubleClicked: rootItem.openAppMenu(index)
                        onEntered: {
                            if (rootItem.appMenuIndex !== -1 &&
                                    rootItem.appMenuIndex !== index)
                                rootItem.openAppMenu(index)
                        }
                    }
                }

                AppMenuModel {
                    id: appMenuModel

                    // An application can ask for one of its menus to be
                    // opened, which is how a menu shortcut arrives here.
                    onRequestActivateIndex: function (index) {
                        rootItem.openAppMenu(index, true)
                    }
                }
            }
        }

        // System tray(Right)
        SystemTray {}

        // Phone / Continuity Indicator (macOS style)
        StandardItem {
            id: phoneStatusItem
            visible: continuity.showInMenuBar && continuity.isConnected
            Layout.fillHeight: true
            Layout.preferredWidth: _phoneLayout.implicitWidth + FishUI.Units.smallSpacing * 2

            onClicked: controler.toggleDialog()

            RowLayout {
                id: _phoneLayout
                anchors.centerIn: parent
                spacing: FishUI.Units.smallSpacing / 2

                BarIcon {
                    id: phoneIcon
                    dropShadow: rootItem.darkMode
                    width: rootItem.iconSize
                    height: width
                    source: "qrc:/statusbar/images/" + (rootItem.darkMode ? "dark/" : "light/") + "phone.svg"
                    antialiasing: true
                }

                BarLabel {
                    text: continuity.batteryCharge + "%"
                    font.pointSize: rootItem.fontSize - 1
                    color: rootItem.textColor
                    dropShadow: rootItem.darkMode
                    visible: continuity.isConnected
                }
            }
        }

        // Wi-Fi Indicator
        StandardItem {
            id: wifiStatusItem
            visible: enabledConnections.wirelessHwEnabled &&
                     enabledConnections.wirelessEnabled
            Layout.fillHeight: true
            Layout.preferredWidth: rootItem.iconSize + 20

            onClicked: controler.toggleDialog()

            BarIcon {
                id: wirelessIcon
                anchors.centerIn: parent
                dropShadow: rootItem.darkMode
                width: rootItem.iconSize
                height: width
                source: activeConnection.wirelessIcon ? "qrc:/statusbar/images/" + (rootItem.darkMode ? "dark/" : "light/") + activeConnection.wirelessIcon + ".svg" : "qrc:/statusbar/images/" + (rootItem.darkMode ? "dark/" : "light/") + "network-wireless-connected-100.svg"
                antialiasing: true
            }
        }

        // Sound Indicator
        StandardItem {
            id: soundStatusItem
            visible: !!rootItem.defaultSink
            Layout.fillHeight: true
            Layout.preferredWidth: rootItem.iconSize + 20

            onClicked: controler.toggleDialog()

            BarIcon {
                id: volumeIcon
                anchors.centerIn: parent
                dropShadow: rootItem.darkMode
                width: rootItem.iconSize
                height: width
                source: "qrc:/statusbar/images/" + (rootItem.darkMode ? "dark/" : "light/") + rootItem.volumeIconName + ".svg"
                antialiasing: true
            }
        }

        // Battery Indicator
        StandardItem {
            id: batteryStatusItem
            visible: battery.available
            Layout.fillHeight: true
            Layout.preferredWidth: _batteryLayout.implicitWidth + 12

            onClicked: controler.toggleDialog()

            RowLayout {
                id: _batteryLayout
                anchors.centerIn: parent
                spacing: 5

                BarIcon {
                    id: batteryIcon
                    dropShadow: rootItem.darkMode
                    width: 20
                    height: 11
                    fillMode: Image.PreserveAspectFit
                    source: "qrc:/statusbar/images/" + (rootItem.darkMode ? "dark/" : "light/") + battery.iconSource
                    Layout.alignment: Qt.AlignCenter
                    antialiasing: true
                }

                BarLabel {
                    text: battery.chargePercent + "%"
                    font.pointSize: rootItem.fontSize
                    color: rootItem.textColor
                    dropShadow: rootItem.darkMode
                    visible: battery.showPercentage
                }
            }
        }

        // Dedicated macOS Control Center Button
        StandardItem {
            id: controler
            checked: controlCenter.item ? controlCenter.item.visible : false
            Layout.fillHeight: true
            Layout.preferredWidth: rootItem.iconSize + 20

            onClicked: {
                toggleDialog()
            }

            function toggleDialog() {
                if (!controlCenter.active) {
                    controlCenter.active = true
                    return
                }

                if (!controlCenter.item)
                    return

                if (controlCenter.item.visible)
                    controlCenter.item.close()
                else {
                    controlCenter.item.position = Qt.point(0, 0)
                    controlCenter.item.position = mapToGlobal(0, 0)
                    controlCenter.item.open()
                }
            }

            BarIcon {
                id: controlCenterIcon
                anchors.centerIn: parent
                dropShadow: rootItem.darkMode
                width: rootItem.iconSize
                height: width
                source: "qrc:/statusbar/images/" + (rootItem.darkMode ? "dark/" : "light/") + "control.svg"
                antialiasing: true
            }
        }

        // Spotlight Search Button (macOS style)
        StandardItem {
            id: spotlightItem
            checked: spotlight.item ? spotlight.item.visible : false
            Layout.fillHeight: true
            Layout.preferredWidth: rootItem.iconSize + FishUI.Units.smallSpacing * 2

            onClicked: {
                toggleDialog()
            }

            function toggleDialog() {
                if (!spotlight.active) {
                    spotlight.active = true
                    return
                }

                if (!spotlight.item)
                    return

                if (spotlight.item.visible)
                    spotlight.item.close()
                else {
                    spotlight.item.open()
                }
            }

            BarIcon {
                id: searchIcon
                anchors.centerIn: parent
                dropShadow: rootItem.darkMode
                width: rootItem.iconSize
                height: width
                source: "qrc:/statusbar/images/" + (rootItem.darkMode ? "dark/" : "light/") + "system-search-symbolic.svg"
                antialiasing: true
            }
        }

        // Clipboard Manager Button (macOS style)
        StandardItem {
            id: clipboardItem
            checked: clipboardPopup.item ? clipboardPopup.item.visible : false
            Layout.fillHeight: true
            Layout.preferredWidth: rootItem.iconSize + FishUI.Units.smallSpacing * 2

            onClicked: {
                toggleDialog()
            }

            function toggleDialog() {
                if (!clipboardPopup.active) {
                    clipboardPopup.active = true
                    return
                }

                if (!clipboardPopup.item)
                    return

                if (clipboardPopup.item.visible)
                    clipboardPopup.item.close()
                else {
                    clipboardPopup.item.position = Qt.point(0, 0)
                    clipboardPopup.item.position = mapToGlobal(0, 0)
                    clipboardPopup.item.open()
                }
            }

            BarIcon {
                id: clipboardIcon
                anchors.centerIn: parent
                dropShadow: rootItem.darkMode
                width: rootItem.iconSize
                height: width
                source: "qrc:/statusbar/images/" + (rootItem.darkMode ? "dark/" : "light/") + "clipboard.svg"
                antialiasing: true
            }
        }

        // Pop-up notification center and calendar
        StandardItem {
            id: datetimeItem

            checked: notificationCenter.item ? notificationCenter.item.visible : false
            Layout.fillHeight: true
            Layout.preferredWidth: _dateTimeLayout.implicitWidth + FishUI.Units.smallSpacing * 2

            onClicked: {
                toggleDialog()
            }

            function toggleDialog() {
                if (!notificationCenter.active) {
                    notificationCenter.active = true
                    return
                }

                if (!notificationCenter.item)
                    return

                if (notificationCenter.item.visible)
                    notificationCenter.item.close()
                else {
                    notificationCenter.item.position = Qt.point(0, 0)
                    notificationCenter.item.position = mapToGlobal(0, 0)
                    notificationCenter.item.open()
                }
            }

            RowLayout {
                id: _dateTimeLayout
                anchors.fill: parent

                BarLabel {
                    id: timeLabel
                    Layout.alignment: Qt.AlignCenter
                    font.pointSize: rootItem.fontSize
                    font.weight: Font.Medium
                    font.letterSpacing: 0.2
                    color: rootItem.textColor
                    dropShadow: rootItem.darkMode

                    Timer {
                        id: timeTimer
                        interval: 1000
                        repeat: true
                        running: true
                        triggeredOnStart: true
                        onTriggered: {
                            var now = new Date()
                            timeLabel.text = now.toLocaleString(Qt.locale(), rootItem.timeFormat)
                            var remainingSeconds = 60 - now.getSeconds()
                            interval = (remainingSeconds > 0 ? remainingSeconds : 60) * 1000
                        }
                    }
                }
            }
        }

    }

    PowerActions {
        id: powerActions
    }

    // Power Confirmation Dialog in Root Status Bar Window
    FishUI.ConfirmDialog {
        id: confirmPowerDialog
        property string actionType: "shutdown"

        title: actionType === "shutdown" ? qsTr("Shut Down")
             : (actionType === "restart" ? qsTr("Restart")
             : qsTr("Log Out"))

        text: actionType === "shutdown" ? qsTr("Are you sure you want to shut down your computer?")
            : (actionType === "restart" ? qsTr("Are you sure you want to restart your computer?")
            : qsTr("Are you sure you want to log out of your session?"))

        confirmText: actionType === "shutdown" ? qsTr("Shut Down")
                   : (actionType === "restart" ? qsTr("Restart")
                   : qsTr("Log Out"))

        onAccepted: {
            if (actionType === "shutdown") {
                powerActions.shutdown()
                process.startDetached("systemctl", ["poweroff"])
            } else if (actionType === "restart") {
                powerActions.reboot()
                process.startDetached("systemctl", ["reboot"])
            } else if (actionType === "logout") {
                powerActions.logout()
                process.startDetached("loginctl", ["terminate-session", "self"])
            }
        }
    }

    function showPowerDialog(type) {
        confirmPowerDialog.actionType = type
        confirmPowerDialog.show()
        confirmPowerDialog.raise()
        confirmPowerDialog.requestActivate()
    }

    MouseArea {
        id: _sliding
        anchors.fill: parent
        z: -1

        property int startY: -1
        property bool activated: false

        onActivatedChanged: {
            // TODO
            // if (activated)
            //     acticity.move()
        }

        onPressed: (mouse) => {
            startY = mouse.y
        }

        onReleased: {
            startY = -1
        }

        onDoubleClicked: {
            acticity.toggleMaximize()
        }

        onMouseYChanged: {
            if (startY === parseInt(mouseY)) {
                activated = false
                return
            }

            // Up
            if (startY > parseInt(mouseY)) {
                activated = false
                return
            }

            if (mouseY > rootItem.height)
                activated = true
            else
                activated = false
        }
    }

    // Components
    Loader {
        id: controlCenter
        active: false
        sourceComponent: Component { ControlCenter {} }
        asynchronous: true
        onLoaded: {
            item.transientParent = rootItem.Window.window
            item.position = Qt.point(0, 0)
            item.position = controler.mapToGlobal(0, 0)
            item.open()
        }
    }

    // The notification centre lives in the notification component's resources,
    // so it comes in by URL rather than as an inline component.
    Loader {
        id: notificationCenter
        active: false
        source: "qrc:/notification/qml/NotificationCenter.qml"
        asynchronous: true

        // Anchor the popup to the status bar. Without a transient parent Qt
        // has nothing to make an xdg_popup out of and falls back to an
        // ordinary toplevel, which KWin then decorates and places itself -
        // exactly what the notification centre used to look like when it lived
        // in its own process.
        onLoaded: {
            item.transientParent = rootItem.Window.window
            item.position = Qt.point(0, 0)
            item.position = datetimeItem.mapToGlobal(0, 0)
            item.open()
        }
    }

    // `cutefish-notificationd -s` used to pop the window up from another
    // process; now com.cutefish.Notification.showWindow() lands here.
    Connections {
        target: notificationManager

        function onWindowRequested() {
            datetimeItem.toggleDialog()
        }
    }

    Loader {
        id: userMenu
        active: false
        sourceComponent: Component { UserMenu {} }
        asynchronous: true

        onLoaded: {
            item.transientParent = rootItem.Window.window
            item.availableGeometry = Qt.binding(function () {
                return screenHelper.availableScreenRect
            })
            var pos = userItem.mapToGlobal(0, userItem.height + FishUI.Units.smallSpacing)
            item.showAt(pos.x, pos.y)
        }
    }

    Loader {
        id: spotlight
        active: false
        sourceComponent: Component { Spotlight {} }
        asynchronous: true

        onLoaded: {
            item.transientParent = rootItem.Window.window
            item.open()
        }
    }

    Connections {
        target: StatusBar

        function onSpotlightRequested() {
            spotlightItem.toggleDialog()
        }

        function onControlCenterRequested() {
            controler.toggleDialog()
        }
    }

    Loader {
        id: clipboardPopup
        active: false
        sourceComponent: Component {
            ClipboardPopup {
                clipboardHelper: globalClipboardHelper
            }
        }
        asynchronous: true

        onLoaded: {
            item.transientParent = rootItem.Window.window
            item.position = Qt.point(0, 0)
            item.position = clipboardItem.mapToGlobal(0, 0)
            item.open()
        }
    }

    Shortcut {
        sequence: "Ctrl+Alt+V"
        onActivated: clipboardItem.toggleDialog()
    }

    Shortcut {
        sequence: "Meta+Shift+V"
        onActivated: clipboardItem.toggleDialog()
    }

    Loader {
        id: overviewOverlayLoader
        active: false
        sourceComponent: OverviewOverlay {}
        asynchronous: true

        onLoaded: {
            item.transientParent = rootItem.Window.window
            item.open()
        }
    }

    function toggleOverview() {
        if (!overviewOverlayLoader.active) {
            overviewOverlayLoader.active = true
            return
        }

        if (overviewOverlayLoader.item) {
            if (overviewOverlayLoader.item.visible)
                overviewOverlayLoader.item.close()
            else
                overviewOverlayLoader.item.open()
        }
    }

    Shortcut {
        sequence: "F9"
        onActivated: toggleOverview()
    }

    Shortcut {
        sequence: "Meta+Tab"
        onActivated: toggleOverview()
    }

    Loader {
        id: stageManagerLoader
        active: false
        source: "qrc:/statusbar/qml/StageManager.qml"
        asynchronous: true

        onLoaded: {
            item.enabled = true
        }
    }

    function toggleStageManager() {
        if (!stageManagerLoader.active) {
            stageManagerLoader.active = true
            return
        }

        if (stageManagerLoader.item) {
            stageManagerLoader.item.enabled = !stageManagerLoader.item.enabled
        }
    }

    Shortcut {
        sequence: "F10"
        onActivated: toggleStageManager()
    }

    Shortcut {
        sequence: "Meta+S"
        onActivated: toggleStageManager()
    }


    NM.ActiveConnection {
        id: activeConnection
    }

    NM.EnabledConnections {
        id: enabledConnections
    }

    NM.Handler {
        id: nmHandler
    }
}
