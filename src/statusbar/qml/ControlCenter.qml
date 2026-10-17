/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * HarmonyOS-inspired Control Center UI refinement
 */

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import Qt5Compat.GraphicalEffects

import Cutefish.Accounts 1.0 as Accounts
import Cutefish.Bluetooth 1.0 as Bluetooth
import Cutefish.Network 1.0 as NM
import Cutefish.Appearance 1.0 as FrameworkAppearance
import Cutefish.StatusBar 1.0
import Cutefish.Shell 1.0
import Cutefish.Audio 1.0
import FishUI 1.0 as FishUI

PopupWindow {
    id: control

    width: 372
    property real baseHeight: 486
    height: Math.max(baseHeight, mainView.implicitHeight) + 28

    property string currentView: "main"

    property var margin: 6
    property point position: Qt.point(0, 0)
    property var defaultSink: paSinkModel.defaultSink

    property bool bluetoothDisConnected: Bluetooth.Manager.bluetoothBlocked
    property string bluetoothConnectedDeviceName: ""
    property bool bluetoothHasConnectedDevice: false
    property var defaultSinkValue: defaultSink ? defaultSink.volume / PulseAudio.NormalVolume * 100.0 : -1

    property bool _airdropActive: false
    property bool _nightLightActive: false
    property bool _locationActive: true
    property bool _powerSaverActive: false
    property bool _keyboardBacklightActive: false
    property bool _wifiActive: true
    property int _powerModeState: battery.powerMode
    property int _keyboardBacklightLevel: 0

    property color cardBgColor: FishUI.Theme.darkMode ? Qt.rgba(0.18, 0.20, 0.26, 0.52)
                                                      : Qt.rgba(1, 1, 1, 0.68)
    property color cardBorderColor: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.14)
                                                          : Qt.rgba(1, 1, 1, 0.85)
    property color inactiveCircleColor: FishUI.Theme.darkMode ? Qt.rgba(0.24, 0.26, 0.32, 0.65)
                                                              : "#FFFFFF"
    property color inactiveCircleBorderColor: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.10)
                                                                    : Qt.rgba(0, 0, 0, 0.08)
    property string inactiveIconDir: FishUI.Theme.darkMode ? "dark/" : "light/"
    property color subTextColor: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.70)
                                                       : Qt.rgba(0.12, 0.14, 0.20, 0.62)
    property string iconDir: FishUI.Theme.darkMode ? "dark/" : "light/"

    property var volumeIconName: {
        if (!defaultSink || defaultSink.muted || defaultSinkValue <= 0)
            return "audio-volume-muted-symbolic"
        else if (defaultSinkValue <= 25)
            return "audio-volume-low-symbolic"
        else if (defaultSinkValue <= 75)
            return "audio-volume-medium-symbolic"
        else
            return "audio-volume-high-symbolic"
    }

    onWidthChanged: adjustCorrectLocation()
    onPositionChanged: adjustCorrectLocation()
    onVisibleChanged: {
        if (!visible) {
            control.currentView = "main"
        } else {
            control.updateBtConnectedStatus()
        }
    }

    Component.onCompleted: {
        control.updateBtConnectedStatus()
    }

    color: "transparent"

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    FrameworkAppearance.Appearance { id: appearance }
    Notifications { id: notifications }
    PowerActions { id: powerActions }
    SinkModel { id: paSinkModel }
    Brightness { id: brightness }
    Accounts.UserAccount { id: currentUser }
    ContinuityManager { id: continuity }
    ProcessProvider { id: process }
    Bluetooth.BluetoothManager { id: ccBtManager }
    Bluetooth.DevicesModel { id: ccBtDevicesModel }
    Bluetooth.DevicesProxyModel { id: ccBtProxyModel; sourceModel: ccBtDevicesModel }
    NM.NetworkModel { id: ccNetworkModel }
    NM.AppletProxyModel { id: ccWifiProxyModel; type: NM.AppletProxyModel.WirelessType; sourceModel: ccNetworkModel }

    Connections {
        target: Bluetooth.Manager
        function onDevicesChanged() { control.updateBtConnectedStatus() }
        function onDeviceChanged(device) { control.updateBtConnectedStatus() }
        function onDeviceAdded(device) { control.updateBtConnectedStatus() }
        function onDeviceRemoved(device) { control.updateBtConnectedStatus() }
        function onBluetoothBlockedChanged() { control.updateBtConnectedStatus() }
        function onBluetoothOperationalChanged() { control.updateBtConnectedStatus() }
    }

    Connections {
        target: ccBtProxyModel
        function onConnectedNameChanged() { control.updateBtConnectedStatus() }
    }

    Timer {
        id: btRefreshTimer
        interval: 2000
        running: control.visible
        repeat: true
        onTriggered: control.updateBtConnectedStatus()
    }

    Timer {
        id: btConnectUpdateTimer
        interval: 1200
        repeat: false
        onTriggered: control.updateBtConnectedStatus()
    }

    Timer {
        id: screenshotTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (!process.startDetached("aevis-screenshot"))
                process.startDetached("cutefish-screenshot")
        }
    }

    function triggerScreenshot() {
        control.close()
        screenshotTimer.restart()
    }

    function openSettings(moduleName) {
        control.close()
        var args = moduleName ? ["-m", moduleName] : []
        if (!process.startDetached("aevis-settings", args)) {
            if (!process.startDetached("cutefish-settings", args)) {
                if (!process.startDetached("systemsettings", args)) {
                    process.startDetached("gnome-control-center")
                }
            }
        }
    }

    function cyclePowerMode() {
        var nextMode = (battery.powerMode + 1) % 3
        battery.setPowerMode(nextMode)
        control._powerModeState = nextMode

        var profile = "balanced"
        var sys76 = "balanced"
        var cpu = "performance"
        var tuned = "balanced"

        if (nextMode === 1) {
            profile = "performance"
            sys76 = "performance"
            cpu = "performance"
            tuned = "throughput-performance"
        } else if (nextMode === 2) {
            profile = "power-saver"
            sys76 = "battery"
            cpu = "powersave"
            tuned = "powersave"
        }

        process.startDetached("dbus-send", [
            "--system",
            "--print-reply",
            "--dest=org.freedesktop.UPower.PowerProfiles",
            "/org/freedesktop/UPower/PowerProfiles",
            "org.freedesktop.DBus.Properties.Set",
            "string:org.freedesktop.UPower.PowerProfiles",
            "string:ActiveProfile",
            "variant:string:" + profile
        ])
        process.startDetached("powerprofilesctl", ["set", profile])
        process.startDetached("system76-power", ["profile", sys76])
        process.startDetached("cpupower", ["frequency-set", "-g", cpu])
        process.startDetached("auto-cpufreq", ["--force=" + (nextMode === 1 ? "performance" : (nextMode === 2 ? "powersave" : "reset"))])
        process.startDetached("tuned-adm", ["profile", tuned])
    }

    function toggleNightLight() {
        control._nightLightActive = !control._nightLightActive
        if (control._nightLightActive) {
            process.startDetached("qdbus6", ["org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight.preview", "86400000"])
            process.startDetached("qdbus", ["org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight.preview", "86400000"])
            process.startDetached("sh", ["-c", "for out in $(xrandr | grep ' connected' | cut -d' ' -f1); do xrandr --output \"$out\" --gamma 1.0:0.82:0.65 2>/dev/null; done"])
        } else {
            process.startDetached("qdbus6", ["org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight.stopPreview"])
            process.startDetached("qdbus", ["org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight.stopPreview"])
            process.startDetached("sh", ["-c", "for out in $(xrandr | grep ' connected' | cut -d' ' -f1); do xrandr --output \"$out\" --gamma 1.0:1.0:1.0 2>/dev/null; done"])
        }
    }

    function toggleKeyboardBacklight() {
        control._keyboardBacklightLevel = (control._keyboardBacklightLevel + 1) % 3
        control._keyboardBacklightActive = (control._keyboardBacklightLevel > 0)

        var valPct = "0%"
        var valStep = "0"
        var valGnome = "0.0"
        var valAsus = "off"

        if (control._keyboardBacklightLevel === 2) {
            valPct = "100%"
            valStep = "2"
            valGnome = "1.0"
            valAsus = "high"
        } else if (control._keyboardBacklightLevel === 1) {
            valPct = "50%"
            valStep = "1"
            valGnome = "0.5"
            valAsus = "low"
        }

        process.startDetached("dbus-send", [
            "--system",
            "--type=method_call",
            "--dest=org.freedesktop.UPower",
            "/org/freedesktop/UPower/KbdBacklight",
            "org.freedesktop.UPower.KbdBacklight.SetBrightness",
            "int32:" + valStep
        ])
        process.startDetached("brightnessctl", ["--device=*kbd_backlight*", "set", valPct])
        process.startDetached("brightnessctl", ["--device=*keyboard*", "set", valPct])
        process.startDetached("brightnessctl", ["--class=leds", "set", valPct])
        process.startDetached("light", ["-s", "sysfs/leds/smc::kbd_backlight", "-S", valPct.replace("%", "")])
        process.startDetached("asusctl", ["-k", valAsus])
        process.startDetached("gsettings", ["set", "org.gnome.settings-daemon.peripherals.keyboard", "backlight-brightness", valGnome])
    }

    function toggleFocusDND() {
        notifications.doNotDisturb = !notifications.doNotDisturb
        if (notifications.doNotDisturb) {
            process.startDetached("dunstctl", ["set-paused", "true"])
        } else {
            process.startDetached("dunstctl", ["set-paused", "false"])
        }
    }

    function toggleWifi() {
        control._wifiActive = !control._wifiActive
        if (typeof nmHandler !== "undefined" && nmHandler) {
            nmHandler.enableWireless(control._wifiActive)
        }
        process.startDetached("nmcli", ["radio", "wifi", control._wifiActive ? "on" : "off"])
    }

    function toggleBluetooth() {
        control.bluetoothDisConnected = !control.bluetoothDisConnected
        if (typeof Bluetooth !== "undefined" && Bluetooth.Manager) {
            Bluetooth.Manager.bluetoothBlocked = control.bluetoothDisConnected
            for (var i = 0; i < Bluetooth.Manager.adapters.length; ++i) {
                var adapter = Bluetooth.Manager.adapters[i]
                adapter.powered = !control.bluetoothDisConnected
            }
        }
        process.startDetached("bluetoothctl", ["power", !control.bluetoothDisConnected ? "on" : "off"])
        process.startDetached("rfkill", [!control.bluetoothDisConnected ? "unblock" : "block", "bluetooth"])
        control.updateBtConnectedStatus()
    }

    function updateBtConnectedStatus() {
        if (control.bluetoothDisConnected) {
            control.bluetoothConnectedDeviceName = ""
            control.bluetoothHasConnectedDevice = false
            return
        }

        var connectedNames = []
        var anyConnected = false

        if (typeof Bluetooth !== "undefined" && Bluetooth.Manager && Bluetooth.Manager.devices) {
            for (var i = 0; i < Bluetooth.Manager.devices.length; ++i) {
                var dev = Bluetooth.Manager.devices[i]
                if (dev && dev.connected) {
                    anyConnected = true
                    var n = dev.friendlyName || dev.name
                    if (n && n.length > 0 && connectedNames.indexOf(n) === -1) {
                        connectedNames.push(n)
                    }
                }
            }
        }

        if (connectedNames.length === 0 && ccBtProxyModel && ccBtProxyModel.connectedName && ccBtProxyModel.connectedName.length > 0) {
            connectedNames.push(ccBtProxyModel.connectedName)
            anyConnected = true
        }

        if (connectedNames.length > 0) {
            control.bluetoothConnectedDeviceName = connectedNames.join(", ")
            control.bluetoothHasConnectedDevice = true
        } else {
            control.bluetoothConnectedDeviceName = ""
            control.bluetoothHasConnectedDevice = anyConnected
        }
    }

    function adjustCorrectLocation() {
        var posX = control.position.x
        var posY = control.position.y
        if (posX + control.width >= StatusBar.screenRect.x + StatusBar.screenRect.width)
            posX = StatusBar.screenRect.x + StatusBar.screenRect.width - control.width - control.margin
        posY = rootItem.y + rootItem.height + control.margin
        control.x = Math.round(posX)
        control.y = Math.round(posY)
    }

    FishUI.WindowBlur {
        view: control
        windowRadius: _background.radius
        enabled: FishUI.Theme.blurEnabled
    }

    FishUI.WindowShadow {
        view: control
        radius: _background.radius
        strength: 0.60
    }

    // High Translucency Frosted Glass Panel
    Rectangle {
        id: _background
        anchors.fill: parent
        radius: 26
        color: FishUI.Theme.darkMode ? Qt.rgba(0.08, 0.09, 0.13, 0.65)
                                     : Qt.rgba(0.92, 0.94, 0.98, 0.72)
        antialiasing: true
        border.width: 1 / FishUI.Dpi.ratio
        border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.20)
                                            : Qt.rgba(1, 1, 1, 0.95)

        // Inner Specular Glass Rim
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 25
            color: "transparent"
            border.width: 1 / FishUI.Dpi.ratio
            border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.12)
                                                : Qt.rgba(1, 1, 1, 0.50)
        }
    }

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.margins: 14
        clip: true

        // ==========================================
        // 1. MAIN CONTROL CENTER VIEW
        // ==========================================
        ColumnLayout {
            id: mainView
            width: contentArea.width
            spacing: 12

            x: control.currentView === "main" ? 0 : -contentArea.width * 0.25
            opacity: control.currentView === "main" ? 1.0 : 0.0
            visible: opacity > 0
            enabled: control.currentView === "main"

            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

        // ==========================================
        // 1. HEADER ROW: Control Center Title + Settings Button
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: qsTr("Control Center")
                font.bold: true
                font.pixelSize: 15
                color: FishUI.Theme.textColor
                Layout.fillWidth: true
            }

            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: lockMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.12))
                                        : (lockMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                antialiasing: true

                Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    sourceSize: Qt.size(32, 32)
                    source: "qrc:/statusbar/images/" + control.iconDir + "lock.svg"
                }

                MouseArea {
                    id: lockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        control.close()
                        powerActions.lockScreen()
                    }
                }
            }

            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: setMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.12))
                                        : (setMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                antialiasing: true

                Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    sourceSize: Qt.size(32, 32)
                    source: "qrc:/statusbar/images/" + control.iconDir + "settings.svg"
                }

                MouseArea {
                    id: setMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: openSettings()
                }
            }
        }

        // ==========================================
        // 2. TOP SECTION: 2x2 Grid (Wi-Fi, BT, Wireless Share, Super Device)
        // ==========================================
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 10
            columnSpacing: 10

            // 1. Wi-Fi Card
            Rectangle {
                id: wifiCard
                Layout.fillWidth: true
                height: 60
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                antialiasing: true
                scale: wifiMouse.pressed && !wifiChevronMouse.pressed ? 0.94 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        color: control._wifiActive ? "#007AFF" : control.inactiveCircleColor
                        border.width: control._wifiActive ? 0 : (!FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0)
                        border.color: control.inactiveCircleBorderColor
                        antialiasing: true

                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            sourceSize: Qt.size(44, 44)
                            source: "qrc:/statusbar/images/" + (control._wifiActive ? "dark/wifi.svg" : (control.inactiveIconDir + "wifi_disabled.svg"))
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            z: 10
                            onClicked: control.toggleWifi()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Wi-Fi")
                            font.bold: true
                            font.pixelSize: 12
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: (typeof activeConnection !== "undefined" && activeConnection && activeConnection.wirelessName)
                                ? activeConnection.wirelessName
                                : (control._wifiActive ? qsTr("On") : qsTr("Off"))
                            font.pixelSize: 11
                            color: (typeof activeConnection !== "undefined" && activeConnection && activeConnection.wirelessName)
                                ? control.subTextColor
                                : FishUI.Theme.disabledTextColor
                            font.weight: (typeof activeConnection !== "undefined" && activeConnection && activeConnection.wirelessName)
                                ? Font.Medium
                                : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: wifiChevronBtn
                        width: 28
                        height: 28
                        radius: 14
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        z: 10
                        color: wifiChevronMouse.containsMouse
                            ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                            : "transparent"
                        antialiasing: true
                        scale: wifiChevronMouse.pressed ? 0.90 : (wifiChevronMouse.containsMouse ? 1.05 : 1.0)

                        Behavior on scale {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        Item {
                            id: wifiChevronIconContainer
                            anchors.centerIn: parent
                            width: 14
                            height: 14

                            Image {
                                anchors.centerIn: parent
                                width: 7
                                height: 14
                                sourceSize: Qt.size(28, 56)
                                source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "chevron-right.svg"
                                opacity: wifiChevronMouse.containsMouse ? 1.0 : (FishUI.Theme.darkMode ? 0.90 : 0.65)
                                antialiasing: true
                                smooth: true

                                Behavior on opacity {
                                    NumberAnimation { duration: 150 }
                                }
                            }
                        }

                        MouseArea {
                            id: wifiChevronMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                control.currentView = "wifi"
                            }
                        }
                    }
                }

                MouseArea {
                    id: wifiMouse
                    anchors.fill: parent
                    anchors.rightMargin: 42
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: control.toggleWifi()
                }
            }

            // 2. Bluetooth Card
            Rectangle {
                id: btCard
                Layout.fillWidth: true
                height: 60
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                antialiasing: true
                scale: btMouse.pressed && !btChevronMouse.pressed ? 0.94 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        color: !control.bluetoothDisConnected ? "#007AFF" : control.inactiveCircleColor
                        border.width: !control.bluetoothDisConnected ? 0 : (!FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0)
                        border.color: control.inactiveCircleBorderColor
                        antialiasing: true

                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            sourceSize: Qt.size(44, 44)
                            source: "qrc:/statusbar/images/" + (!control.bluetoothDisConnected ? "dark/" : control.inactiveIconDir) + (control.bluetoothDisConnected ? "bluetooth-off.svg" : "bluetooth-symbolic.svg")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            z: 10
                            onClicked: control.toggleBluetooth()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Bluetooth")
                            font.bold: true
                            font.pixelSize: 12
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: {
                                if (control.bluetoothDisConnected)
                                    return qsTr("Off")
                                if (control.bluetoothConnectedDeviceName.length > 0)
                                    return control.bluetoothConnectedDeviceName
                                if (control.bluetoothHasConnectedDevice)
                                    return qsTr("Connected")
                                return qsTr("Not Connected")
                            }
                            font.pixelSize: 11
                            color: (!control.bluetoothDisConnected && (control.bluetoothConnectedDeviceName.length > 0 || control.bluetoothHasConnectedDevice))
                                ? control.subTextColor
                                : FishUI.Theme.disabledTextColor
                            font.weight: (!control.bluetoothDisConnected && (control.bluetoothConnectedDeviceName.length > 0 || control.bluetoothHasConnectedDevice))
                                ? Font.Medium
                                : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: btChevronBtn
                        width: 28
                        height: 28
                        radius: 14
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        z: 10
                        color: btChevronMouse.containsMouse
                            ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                            : "transparent"
                        antialiasing: true
                        scale: btChevronMouse.pressed ? 0.90 : (btChevronMouse.containsMouse ? 1.05 : 1.0)

                        Behavior on scale {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        Item {
                            id: btChevronIconContainer
                            anchors.centerIn: parent
                            width: 14
                            height: 14

                            Image {
                                anchors.centerIn: parent
                                width: 7
                                height: 14
                                sourceSize: Qt.size(28, 56)
                                source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "chevron-right.svg"
                                opacity: btChevronMouse.containsMouse ? 1.0 : (FishUI.Theme.darkMode ? 0.90 : 0.65)
                                antialiasing: true
                                smooth: true

                                Behavior on opacity {
                                    NumberAnimation { duration: 150 }
                                }
                            }
                        }

                        MouseArea {
                            id: btChevronMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                control.currentView = "bluetooth"
                            }
                        }
                    }
                }

                MouseArea {
                    id: btMouse
                    anchors.fill: parent
                    anchors.rightMargin: 42
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: control.toggleBluetooth()
                }
            }

            // 3. Wireless Share Card
            Rectangle {
                Layout.fillWidth: true
                height: 60
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                antialiasing: true

                MouseArea {
                    anchors.fill: parent
                    onClicked: control._airdropActive = !control._airdropActive
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 10

                    Rectangle {
                        width: 42
                        height: 42
                        radius: 21
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
                        Layout.alignment: Qt.AlignVCenter
                        color: control._airdropActive ? "#007AFF" : control.inactiveCircleColor
                        border.width: control._airdropActive ? 0 : (!FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0)
                        border.color: control.inactiveCircleBorderColor
                        antialiasing: true

                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            sourceSize: Qt.size(44, 44)
                            source: "qrc:/statusbar/images/" + (control._airdropActive ? "dark/wireless-share.svg" : (control.inactiveIconDir + "wireless-share-off.svg"))
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Wireless Share")
                            font.bold: true
                            font.pixelSize: 12
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: control._airdropActive ? qsTr("On") : qsTr("Off")
                            font.pixelSize: 11
                            color: FishUI.Theme.disabledTextColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // 4. Super Device Card (KDE Connect)
            Rectangle {
                id: kdeCard
                Layout.fillWidth: true
                height: 60
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                antialiasing: true
                scale: kdeMouse.pressed && !kdeChevronMouse.pressed ? 0.94 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        color: continuity.isConnected ? "#34C759" : control.inactiveCircleColor
                        border.width: continuity.isConnected ? 0 : (!FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0)
                        border.color: control.inactiveCircleBorderColor
                        antialiasing: true

                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            sourceSize: Qt.size(44, 44)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            source: "qrc:/statusbar/images/" + (continuity.isConnected ? "dark/" : control.inactiveIconDir) + "phone.svg"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("KDE Connect")
                            font.bold: true
                            font.pixelSize: 12
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: continuity.isConnected ? (continuity.deviceName.length > 0 ? continuity.deviceName : qsTr("Connected")) : qsTr("Not Connected")
                            font.pixelSize: 11
                            color: continuity.isConnected ? control.subTextColor : FishUI.Theme.disabledTextColor
                            font.weight: continuity.isConnected ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: kdeChevronBtn
                        width: 22
                        height: 22
                        radius: 11
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        Layout.alignment: Qt.AlignVCenter
                        color: kdeChevronMouse.containsMouse
                            ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                            : "transparent"
                        antialiasing: true
                        scale: kdeChevronMouse.pressed ? 0.90 : (kdeChevronMouse.containsMouse ? 1.05 : 1.0)

                        Behavior on scale {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        Item {
                            id: kdeChevronIconContainer
                            anchors.centerIn: parent
                            width: 14
                            height: 14

                            Image {
                                anchors.centerIn: parent
                                width: 7
                                height: 14
                                sourceSize: Qt.size(28, 56)
                                source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "chevron-right.svg"
                                opacity: kdeChevronMouse.containsMouse ? 1.0 : (FishUI.Theme.darkMode ? 0.90 : 0.65)
                                antialiasing: true
                                smooth: true

                                Behavior on opacity {
                                    NumberAnimation { duration: 150 }
                                }
                            }
                        }

                        MouseArea {
                            id: kdeChevronMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                control.currentView = "kdeconnect"
                            }
                        }
                    }
                }

                MouseArea {
                    id: kdeMouse
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: kdeChevronBtn.left
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        control.currentView = "kdeconnect"
                    }
                }
            }
        }

        // ==========================================
        // 3. MPRIS MEDIA PLAYER CARD
        // ==========================================
        MprisItem {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            cardBgColor: control.cardBgColor
            cardBorderColor: control.cardBorderColor
        }

        // ==========================================
        // 4. HARMONYOS STACKED SLIDERS (One unified card holding both)
        // ==========================================

        // Unified HarmonyOS brightness and volume ca
        // Floating brightness and volume sliders
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            // Brightness pill
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: FishUI.Theme.darkMode
                        ? Qt.rgba(0.18, 0.20, 0.26, 0.80)
                        : Qt.rgba(0, 0, 0, 0.10)
                }

                Rectangle {
                    width: parent.width
                        * Math.max(0, Math.min(100,
                            brightnessSlider.value)) / 100
                    height: parent.height
                    radius: height / 2
                    color: FishUI.Theme.darkMode
                        ? Qt.rgba(1, 1, 1, 0.92)
                        : "#FFFFFF"
                }

                Image {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    sourceSize: Qt.size(44, 44)
                    source: "qrc:/statusbar/images/light/" + (brightness.value >= 99 ? "brightness_max.svg" : "brightness_min.svg")
                    z: 2
                }

                Slider {
                    id: brightnessSlider
                    anchors.fill: parent
                    from: 1
                    to: 100
                    value: brightness.value
                    leftPadding: 40
                    rightPadding: 0

                    onMoved: brightness.setValue(value)
                    onPressedChanged: {
                        if (!pressed)
                            brightness.setValue(value)
                    }

                    background: Item {}

                    handle: Item {
                        implicitWidth: 0
                        implicitHeight: 0
                    }
                }
            }

            // Volume pill
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: FishUI.Theme.darkMode
                        ? Qt.rgba(0.18, 0.20, 0.26, 0.80)
                        : Qt.rgba(0, 0, 0, 0.10)
                }

                Rectangle {
                    width: parent.width
                        * Math.max(0, Math.min(100,
                            defaultSinkValue)) / 100
                    height: parent.height
                    radius: height / 2
                    color: FishUI.Theme.darkMode
                        ? Qt.rgba(1, 1, 1, 0.92)
                        : "#FFFFFF"
                }

                Image {
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17
                    height: 17
                    sourceSize: Qt.size(34, 34)
                    source: "qrc:/statusbar/images/light/"
                        + control.volumeIconName + ".svg"
                    z: 2
                }

                Slider {
                    id: volumeSlider
                    anchors.fill: parent
                    from: 0
                    to: 100
                    value: Math.max(0, defaultSinkValue)
                    leftPadding: 36
                    rightPadding: 0

                    onMoved: {
                        if (defaultSink)
                            defaultSink.volume =
                                value * PulseAudio.NormalVolume / 100.0
                    }
                    onPressedChanged: {
                        if (!pressed && defaultSink)
                            defaultSink.volume =
                                value * PulseAudio.NormalVolume / 100.0
                    }

                    background: Item {}

                    handle: Item {
                        implicitWidth: 0
                        implicitHeight: 0
                    }
                }
            }
        }



        // ==========================================
        // 5. ROUND QUICK TOGGLES GRID (2 Rows x 5 Items = 10 Toggles)
        // ==========================================

        ColumnLayout {
            id: bottomQuickSettings
            Layout.fillWidth: true
            spacing: 8

            // Row 1: Power Mode, Night, Capture, Focus, Dark (5 items)
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                // 1. Power Mode (3-Way Switch: Balanced -> Performance -> Saver)
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control.cyclePowerMode()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: control._powerModeState === 1
                                ? "#FF9500"
                                : (control._powerModeState === 2
                                   ? "#34C759"
                                   : control.inactiveCircleColor)
                            border.width: control._powerModeState === 0 && !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/" + (control._powerModeState !== 0 ? "dark/" : control.inactiveIconDir) + (control._powerModeState === 1 ? "turbo.svg" : (control._powerModeState === 2 ? "power-saver.svg" : "balanced.svg"))
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: control._powerModeState === 1
                                ? qsTr("Perf")
                                : (control._powerModeState === 2
                                   ? qsTr("Saver")
                                   : qsTr("Balanced"))
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                // 2. Night Shift
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control.toggleNightLight()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: control._nightLightActive
                                ? "#FF9500"
                                : control.inactiveCircleColor
                            border.width: !control._nightLightActive && !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/"
                                    + (control._nightLightActive
                                       ? "dark/" : control.inactiveIconDir)
                                    + "eye-protection.svg"
                                scale: control._nightLightActive ? 1.10 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Night")
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                // 3. Screenshot (Capture)
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control.triggerScreenshot()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: control.inactiveCircleColor
                            border.width: !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/"
                                    + control.inactiveIconDir + "screenshot.svg"
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Capture")
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                // 4. Focus (DND Toggle)
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control.toggleFocusDND()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: notifications.doNotDisturb
                                ? "#5856D6"
                                : control.inactiveCircleColor
                            border.width: !notifications.doNotDisturb && !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/"
                                    + (notifications.doNotDisturb
                                       ? "dark/do-not-disturb.svg" : (control.inactiveIconDir + "do-not-disturb-off.svg"))
                                rotation: notifications.doNotDisturb ? 360 : 0
                                Behavior on rotation {
                                    NumberAnimation { duration: 350; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Focus")
                            font.pointSize: 7.5
                            horizontalAlignment: Text.AlignHCenter
                            renderType: Text.NativeRendering
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                // 5. Dark Mode
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: appearance.switchDarkMode(!FishUI.Theme.darkMode)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: FishUI.Theme.darkMode
                                ? "#007AFF"
                                : control.inactiveCircleColor
                            border.width: !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                id: darkModeIcon
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/"
                                    + (FishUI.Theme.darkMode
                                       ? "dark/dark-mode.svg" : "light/light-mode.svg")
                                rotation: FishUI.Theme.darkMode ? 0 : 180
                                Behavior on rotation {
                                    NumberAnimation { duration: 300; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: FishUI.Theme.darkMode ? qsTr("Dark") : qsTr("Light")
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Row 2: Key Light, Location, Logout, Restart, Power Off (5 items)
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                // 6. Key Light (Keyboard Backlight - 3-level cycle)
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control.toggleKeyboardBacklight()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: control._keyboardBacklightActive
                                ? "#007AFF"
                                : control.inactiveCircleColor
                            border.width: !control._keyboardBacklightActive && !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/"
                                    + (control._keyboardBacklightActive ? "dark/" : control.inactiveIconDir)
                                    + (control._keyboardBacklightLevel === 2
                                       ? "keyboard-backlight-high.svg"
                                       : (control._keyboardBacklightLevel === 1
                                          ? "keyboard-backlight-low.svg"
                                          : "keyboard-backlight-off.svg"))
                                scale: control._keyboardBacklightActive ? 1.10 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: control._keyboardBacklightLevel === 2
                                ? qsTr("Key High")
                                : (control._keyboardBacklightLevel === 1
                                   ? qsTr("Key Low")
                                   : qsTr("Backlight"))
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                // 7. Location
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control._locationActive = !control._locationActive
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: control._locationActive
                                ? "#007AFF"
                                : control.inactiveCircleColor
                            border.width: !control._locationActive && !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/"
                                    + (control._locationActive
                                       ? "dark/location-mode.svg" : (control.inactiveIconDir + "location-mode-off.svg"))
                                scale: control._locationActive ? 1.10 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Location")
                            font.pointSize: 7.5
                            horizontalAlignment: Text.AlignHCenter
                            renderType: Text.NativeRendering
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                // 8. Logout
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            control.close()
                            rootItem.showPowerDialog("logout")
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: control.inactiveCircleColor
                            border.width: !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/"
                                    + control.inactiveIconDir + "system-log-out.svg"
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Logout")
                            font.pointSize: 7.5
                            horizontalAlignment: Text.AlignHCenter
                            renderType: Text.NativeRendering
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                // 9. Restart
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            control.close()
                            rootItem.showPowerDialog("restart")
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: control.inactiveCircleColor
                            border.width: !FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0
                            border.color: control.inactiveCircleBorderColor
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/"
                                    + control.inactiveIconDir + "system-reboot.svg"
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Restart")
                            font.pointSize: 7.5
                            horizontalAlignment: Text.AlignHCenter
                            renderType: Text.NativeRendering
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                // 10. Power Off
                Item {
                    Layout.fillWidth: true
                    height: 60

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            control.close()
                            rootItem.showPowerDialog("shutdown")
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: "#FF3B30"
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/statusbar/images/dark/system-shutdown.svg"
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Power Off")
                            font.pointSize: 7.5
                            horizontalAlignment: Text.AlignHCenter
                            renderType: Text.NativeRendering
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
          } // end mainView

        // ==========================================
        // 2. WI-FI SELECTION VIEW
        // ==========================================
        ColumnLayout {
            id: wifiView
            width: contentArea.width
            height: contentArea.height
            spacing: 12

            x: control.currentView === "wifi" ? 0 : contentArea.width * 0.25
            opacity: control.currentView === "wifi" ? 1.0 : 0.0
            visible: opacity > 0
            enabled: control.currentView === "wifi"

            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // Header Row: Back Button + Wi-Fi Title + Settings Button
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: backWifiMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))
                                                : (backWifiMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                    antialiasing: true
                    scale: backWifiMouse.pressed ? 0.92 : (backWifiMouse.containsMouse ? 1.05 : 1.0)

                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Item {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        rotation: (Qt.application.layoutDirection === Qt.RightToLeft) ? 0 : 180

                        Image {
                            anchors.centerIn: parent
                            width: 7
                            height: 14
                            sourceSize: Qt.size(28, 56)
                            source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "chevron-right.svg"
                            opacity: backWifiMouse.containsMouse ? 1.0 : (FishUI.Theme.darkMode ? 0.90 : 0.70)
                            antialiasing: true
                            smooth: true
                        }
                    }

                    MouseArea {
                        id: backWifiMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control.currentView = "main"
                    }
                }

                Label {
                    text: qsTr("Wi-Fi")
                    font.bold: true
                    font.pixelSize: 15
                    color: FishUI.Theme.textColor
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: wifiSetMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))
                                                : (wifiSetMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                    antialiasing: true
                    scale: wifiSetMouse.pressed ? 0.92 : (wifiSetMouse.containsMouse ? 1.05 : 1.0)

                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize: Qt.size(32, 32)
                        source: "qrc:/statusbar/images/" + control.iconDir + "settings.svg"
                    }

                    MouseArea {
                        id: wifiSetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: openSettings("network")
                    }
                }
            }

            // Wi-Fi Master Toggle Card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                antialiasing: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        color: control._wifiActive ? "#007AFF" : control.inactiveCircleColor
                        border.width: control._wifiActive ? 0 : (!FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0)
                        border.color: control.inactiveCircleBorderColor
                        antialiasing: true

                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            sourceSize: Qt.size(44, 44)
                            source: "qrc:/statusbar/images/" + (control._wifiActive ? "dark/wifi.svg" : (control.inactiveIconDir + "wifi_disabled.svg"))
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            z: 10
                            onClicked: control.toggleWifi()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Wi-Fi")
                            font.bold: true
                            font.pixelSize: 13
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: (typeof activeConnection !== "undefined" && activeConnection && activeConnection.wirelessName)
                                ? activeConnection.wirelessName
                                : (control._wifiActive ? qsTr("On") : qsTr("Off"))
                            font.pixelSize: 11
                            color: (typeof activeConnection !== "undefined" && activeConnection && activeConnection.wirelessName)
                                ? control.subTextColor
                                : FishUI.Theme.disabledTextColor
                            font.weight: (typeof activeConnection !== "undefined" && activeConnection && activeConnection.wirelessName)
                                ? Font.Medium
                                : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    // Toggle Switch Pill
                    Rectangle {
                        id: wifiSwitchPill
                        width: 40
                        height: 24
                        radius: 12
                        Layout.alignment: Qt.AlignVCenter
                        color: control._wifiActive ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15))
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            x: control._wifiActive ? parent.width - width - 2 : 2
                            color: "#FFFFFF"
                            antialiasing: true

                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            id: wifiSwitchArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: control.toggleWifi()
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: 56
                    cursorShape: Qt.PointingHandCursor
                    onClicked: control.toggleWifi()
                }
            }

            // Networks List Card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                clip: true
                antialiasing: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4

                        Label {
                            text: qsTr("Available Networks")
                            font.bold: true
                            font.pixelSize: 12
                            color: control.subTextColor
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 11
                            color: wifiRescanMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.12))
                                                          : (wifiRescanMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 12
                                height: 12
                                sourceSize: Qt.size(24, 24)
                                source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "restore_normal.svg"
                                opacity: wifiRescanMouse.containsMouse ? 1.0 : 0.6
                            }

                            MouseArea {
                                id: wifiRescanMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    process.startDetached("nmcli", ["device", "wifi", "rescan"])
                                }
                            }
                        }
                    }

                    ListView {
                        id: fullWifiListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        reuseItems: true
                        model: ccWifiProxyModel
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            width: fullWifiListView.width
                            height: 38
                            radius: 10
                            color: fullWifiItemMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
                                                            : (fullWifiItemMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : "transparent")
                            antialiasing: true

                            readonly property bool isCurrentConnected: (typeof activeConnection !== "undefined" && activeConnection && activeConnection.wirelessName === (model.itemUniqueName || model.ssid))
                            readonly property bool isSecured: model.securityType && model.securityType !== 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Image {
                                    width: 18
                                    height: 18
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    sourceSize: Qt.size(36, 36)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    antialiasing: true
                                    source: (isSecured && !isCurrentConnected)
                                        ? ("qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "network-wireless-locked.svg")
                                        : ("qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + (model.connectionIcon ? model.connectionIcon : "network-wireless-symbolic") + ".svg")
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Label {
                                    text: model.itemUniqueName ? model.itemUniqueName : (model.ssid ? model.ssid : qsTr("Hidden Network"))
                                    font.pixelSize: 12
                                    font.bold: isCurrentConnected
                                    color: isCurrentConnected ? FishUI.Theme.highlightColor : FishUI.Theme.textColor
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Rectangle {
                                    visible: isCurrentConnected
                                    width: wifiConnText.implicitWidth + 12
                                    height: 20
                                    radius: 10
                                    color: FishUI.Theme.darkMode ? Qt.rgba(0, 0.48, 1, 0.25) : Qt.rgba(0, 0.48, 1, 0.15)
                                    Layout.alignment: Qt.AlignVCenter

                                    Label {
                                        id: wifiConnText
                                        anchors.centerIn: parent
                                        text: qsTr("Connected")
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: FishUI.Theme.highlightColor
                                    }
                                }
                            }

                            MouseArea {
                                id: fullWifiItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var name = model.itemUniqueName || model.ssid
                                    if (name && name.length > 0) {
                                        process.startDetached("nmcli", ["connection", "up", name])
                                    } else {
                                        openSettings("network")
                                    }
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            text: !control._wifiActive ? qsTr("Wi-Fi is turned off") : qsTr("Searching for networks...")
                            font.pixelSize: 12
                            color: FishUI.Theme.disabledTextColor
                            visible: fullWifiListView.count === 0
                        }
                    }
                }
            }
        } // end wifiView

        // ==========================================
        // 3. BLUETOOTH SELECTION VIEW
        // ==========================================
        ColumnLayout {
            id: btView
            width: contentArea.width
            height: contentArea.height
            spacing: 12

            x: control.currentView === "bluetooth" ? 0 : contentArea.width * 0.25
            opacity: control.currentView === "bluetooth" ? 1.0 : 0.0
            visible: opacity > 0
            enabled: control.currentView === "bluetooth"

            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // Header Row: Back Button + Bluetooth Title + Settings Button
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: backBtMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))
                                              : (backBtMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                    antialiasing: true
                    scale: backBtMouse.pressed ? 0.92 : (backBtMouse.containsMouse ? 1.05 : 1.0)

                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Item {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        rotation: (Qt.application.layoutDirection === Qt.RightToLeft) ? 0 : 180

                        Image {
                            anchors.centerIn: parent
                            width: 7
                            height: 14
                            sourceSize: Qt.size(28, 56)
                            source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "chevron-right.svg"
                            opacity: backBtMouse.containsMouse ? 1.0 : (FishUI.Theme.darkMode ? 0.90 : 0.70)
                            antialiasing: true
                            smooth: true
                        }
                    }

                    MouseArea {
                        id: backBtMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control.currentView = "main"
                    }
                }

                Label {
                    text: qsTr("Bluetooth")
                    font.bold: true
                    font.pixelSize: 15
                    color: FishUI.Theme.textColor
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: btSetMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))
                                              : (btSetMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                    antialiasing: true
                    scale: btSetMouse.pressed ? 0.92 : (btSetMouse.containsMouse ? 1.05 : 1.0)

                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize: Qt.size(32, 32)
                        source: "qrc:/statusbar/images/" + control.iconDir + "settings.svg"
                    }

                    MouseArea {
                        id: btSetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: openSettings("bluetooth")
                    }
                }
            }

            // Bluetooth Master Toggle Card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                antialiasing: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        color: !control.bluetoothDisConnected ? "#007AFF" : control.inactiveCircleColor
                        border.width: !control.bluetoothDisConnected ? 0 : (!FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0)
                        border.color: control.inactiveCircleBorderColor
                        antialiasing: true

                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            sourceSize: Qt.size(44, 44)
                            source: "qrc:/statusbar/images/" + (!control.bluetoothDisConnected ? "dark/" : control.inactiveIconDir) + (control.bluetoothDisConnected ? "bluetooth-off.svg" : "bluetooth-symbolic.svg")
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            z: 10
                            onClicked: control.toggleBluetooth()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Bluetooth")
                            font.bold: true
                            font.pixelSize: 13
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: {
                                if (control.bluetoothDisConnected)
                                    return qsTr("Off")
                                if (control.bluetoothConnectedDeviceName.length > 0)
                                    return control.bluetoothConnectedDeviceName
                                if (control.bluetoothHasConnectedDevice)
                                    return qsTr("Connected")
                                return qsTr("Not Connected")
                            }
                            font.pixelSize: 11
                            color: (!control.bluetoothDisConnected && (control.bluetoothConnectedDeviceName.length > 0 || control.bluetoothHasConnectedDevice))
                                ? control.subTextColor
                                : FishUI.Theme.disabledTextColor
                            font.weight: (!control.bluetoothDisConnected && (control.bluetoothConnectedDeviceName.length > 0 || control.bluetoothHasConnectedDevice))
                                ? Font.Medium
                                : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    // Toggle Switch Pill
                    Rectangle {
                        id: btSwitchPill
                        width: 40
                        height: 24
                        radius: 12
                        Layout.alignment: Qt.AlignVCenter
                        color: !control.bluetoothDisConnected ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15))
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            x: !control.bluetoothDisConnected ? parent.width - width - 2 : 2
                            color: "#FFFFFF"
                            antialiasing: true

                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            id: btSwitchArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: control.toggleBluetooth()
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: 56
                    cursorShape: Qt.PointingHandCursor
                    onClicked: control.toggleBluetooth()
                }
            }

            // Devices List Card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                clip: true
                antialiasing: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4

                        Label {
                            text: qsTr("Devices")
                            font.bold: true
                            font.pixelSize: 12
                            color: control.subTextColor
                            Layout.fillWidth: true
                        }
                    }

                    ListView {
                        id: fullBtListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        reuseItems: true
                        model: ccBtProxyModel
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            width: fullBtListView.width
                            height: 38
                            radius: 10
                            color: fullBtItemMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
                                                          : (fullBtItemMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : "transparent")
                            antialiasing: true

                            readonly property bool isConnected: (model.Connected === true)
                            readonly property string devAddress: model.Address ? model.Address : ""

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Image {
                                    width: 18
                                    height: 18
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    sourceSize: Qt.size(36, 36)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    antialiasing: true
                                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "bluetooth-symbolic.svg"
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Label {
                                    text: model.Name ? model.Name : (model.DeviceFullName ? model.DeviceFullName : devAddress)
                                    font.pixelSize: 12
                                    font.bold: isConnected
                                    color: isConnected ? FishUI.Theme.highlightColor : FishUI.Theme.textColor
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Connection status pill
                                Rectangle {
                                    width: fullBtStatusText.implicitWidth + 12
                                    height: 20
                                    radius: 10
                                    color: isConnected ? (FishUI.Theme.darkMode ? Qt.rgba(0, 0.48, 1, 0.25) : Qt.rgba(0, 0.48, 1, 0.15))
                                                       : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                                    Layout.alignment: Qt.AlignVCenter

                                    Label {
                                        id: fullBtStatusText
                                        anchors.centerIn: parent
                                        text: isConnected ? qsTr("Connected") : qsTr("Connect")
                                        font.pixelSize: 9
                                        font.bold: isConnected
                                        color: isConnected ? FishUI.Theme.highlightColor : FishUI.Theme.disabledTextColor
                                    }
                                }
                            }

                            MouseArea {
                                id: fullBtItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (devAddress.length > 0) {
                                        if (isConnected) {
                                            process.startDetached("bluetoothctl", ["disconnect", devAddress])
                                        } else {
                                            process.startDetached("bluetoothctl", ["connect", devAddress])
                                        }
                                        btConnectUpdateTimer.restart()
                                    } else {
                                        openSettings("bluetooth")
                                    }
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            text: control.bluetoothDisConnected ? qsTr("Bluetooth is turned off") : qsTr("No paired devices found")
                            font.pixelSize: 12
                            color: FishUI.Theme.disabledTextColor
                            visible: fullBtListView.count === 0
                        }
                    }
                }
            }
        } // end btView

        // ==========================================
        // 4. KDE CONNECT SELECTION / MANAGEMENT VIEW
        // ==========================================
        ColumnLayout {
            id: kdeConnectView
            width: contentArea.width
            height: contentArea.height
            spacing: 12

            x: control.currentView === "kdeconnect" ? 0 : contentArea.width * 0.25
            opacity: control.currentView === "kdeconnect" ? 1.0 : 0.0
            visible: opacity > 0
            enabled: control.currentView === "kdeconnect"

            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // Header Row: Back Button + Title + Settings Button
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: backKdeMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))
                                               : (backKdeMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                    antialiasing: true
                    scale: backKdeMouse.pressed ? 0.92 : (backKdeMouse.containsMouse ? 1.05 : 1.0)

                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Item {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        rotation: (Qt.application.layoutDirection === Qt.RightToLeft) ? 0 : 180

                        Image {
                            anchors.centerIn: parent
                            width: 7
                            height: 14
                            sourceSize: Qt.size(28, 56)
                            source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "chevron-right.svg"
                            opacity: backKdeMouse.containsMouse ? 1.0 : (FishUI.Theme.darkMode ? 0.90 : 0.70)
                            antialiasing: true
                            smooth: true
                        }
                    }

                    MouseArea {
                        id: backKdeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: control.currentView = "main"
                    }
                }

                Label {
                    text: qsTr("KDE Connect")
                    font.bold: true
                    font.pixelSize: 15
                    color: FishUI.Theme.textColor
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: kdeSetMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))
                                              : (kdeSetMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                    antialiasing: true
                    scale: kdeSetMouse.pressed ? 0.92 : (kdeSetMouse.containsMouse ? 1.05 : 1.0)

                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize: Qt.size(32, 32)
                        source: "qrc:/statusbar/images/" + control.iconDir + "settings.svg"
                    }

                    MouseArea {
                        id: kdeSetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: openSettings("phonelink")
                    }
                }
            }

            // KDE Connect Master Status Card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                antialiasing: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        color: continuity.isConnected ? "#34C759" : control.inactiveCircleColor
                        border.width: continuity.isConnected ? 0 : (!FishUI.Theme.darkMode ? 1 / FishUI.Dpi.ratio : 0)
                        border.color: control.inactiveCircleBorderColor
                        antialiasing: true

                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            sourceSize: Qt.size(44, 44)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            source: "qrc:/statusbar/images/" + (continuity.isConnected ? "dark/" : control.inactiveIconDir) + "phone.svg"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: continuity.isConnected ? (continuity.deviceName.length > 0 ? continuity.deviceName : qsTr("Phone")) : qsTr("KDE Connect")
                            font.bold: true
                            font.pixelSize: 13
                            color: FishUI.Theme.textColor
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: continuity.isConnected
                                ? ((continuity.batteryCharge >= 0 ? (continuity.batteryCharge + "%" + (continuity.isCharging ? " • " + qsTr("Charging") : "")) : qsTr("Connected")) + (continuity.networkType.length > 0 ? " • " + continuity.networkType : ""))
                                : qsTr("Not Connected")
                            font.pixelSize: 11
                            color: continuity.isConnected ? control.subTextColor : FishUI.Theme.disabledTextColor
                            font.weight: continuity.isConnected ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    // Connected badge or Pair button
                    Rectangle {
                        visible: continuity.isConnected
                        width: kdeMasterStatusText.implicitWidth + 14
                        height: 22
                        radius: 11
                        color: FishUI.Theme.darkMode ? Qt.rgba(0.20, 0.78, 0.35, 0.22) : Qt.rgba(0.20, 0.78, 0.35, 0.14)
                        Layout.alignment: Qt.AlignVCenter

                        Label {
                            id: kdeMasterStatusText
                            anchors.centerIn: parent
                            text: qsTr("Connected")
                            font.pixelSize: 10
                            font.bold: true
                            color: "#34C759"
                        }
                    }

                    Rectangle {
                        visible: !continuity.isConnected
                        width: kdeMasterPairText.implicitWidth + 16
                        height: 26
                        radius: 13
                        color: kdeMasterPairMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))
                                                         : (kdeMasterPairMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06))
                                                                                             : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04)))
                        border.width: 1 / FishUI.Dpi.ratio
                        border.color: control.cardBorderColor
                        antialiasing: true
                        Layout.alignment: Qt.AlignVCenter

                        Label {
                            id: kdeMasterPairText
                            anchors.centerIn: parent
                            text: qsTr("Pair")
                            font.pixelSize: 11
                            font.bold: true
                            color: FishUI.Theme.highlightColor
                        }

                        MouseArea {
                            id: kdeMasterPairMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                continuity.openKdeConnect()
                            }
                        }
                    }
                }
            }

            // KDE Connect Management & Quick Actions Card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: control.cardBgColor
                border.width: 1 / FishUI.Dpi.ratio
                border.color: control.cardBorderColor
                clip: true
                antialiasing: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4

                        Label {
                            text: continuity.isConnected ? qsTr("Device Actions") : qsTr("Connection")
                            font.bold: true
                            font.pixelSize: 12
                            color: control.subTextColor
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 11
                            color: kdeRescanMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.12))
                                                          : (kdeRescanMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                            antialiasing: true

                            Image {
                                anchors.centerIn: parent
                                width: 12
                                height: 12
                                sourceSize: Qt.size(24, 24)
                                source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "restore_normal.svg"
                                opacity: kdeRescanMouse.containsMouse ? 1.0 : 0.6
                                fillMode: Image.PreserveAspectFit
                            }

                            MouseArea {
                                id: kdeRescanMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    continuity.refresh()
                                }
                            }
                        }
                    }

                    // Connected Actions List
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: continuity.isConnected
                        spacing: 6

                        // 1. Ring Device Action
                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 10
                            color: ringMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
                                                     : (ringMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.02)))
                            antialiasing: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Image {
                                    width: 18
                                    height: 18
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    sourceSize: Qt.size(36, 36)
                                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "audio-volume-high-symbolic.svg"
                                    fillMode: Image.PreserveAspectFit
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 1

                                    Label {
                                        text: qsTr("Ring Device")
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: FishUI.Theme.textColor
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: qsTr("Play a loud ring on your phone")
                                        font.pixelSize: 10
                                        color: FishUI.Theme.disabledTextColor
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Rectangle {
                                    width: ringBtnLabel.implicitWidth + 14
                                    height: 24
                                    radius: 12
                                    color: FishUI.Theme.darkMode ? Qt.rgba(0, 0.48, 1, 0.25) : Qt.rgba(0, 0.48, 1, 0.15)
                                    Layout.alignment: Qt.AlignVCenter

                                    Label {
                                        id: ringBtnLabel
                                        anchors.centerIn: parent
                                        text: qsTr("Ring")
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: FishUI.Theme.highlightColor
                                    }
                                }
                            }

                            MouseArea {
                                id: ringMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: continuity.ringPhone()
                            }
                        }

                        // 2. Send Ping Action
                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 10
                            color: pingMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
                                                     : (pingMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.02)))
                            antialiasing: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Image {
                                    width: 18
                                    height: 18
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    sourceSize: Qt.size(36, 36)
                                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "notification-symbolic.svg"
                                    fillMode: Image.PreserveAspectFit
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 1

                                    Label {
                                        text: qsTr("Send Ping")
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: FishUI.Theme.textColor
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: qsTr("Test notification connection")
                                        font.pixelSize: 10
                                        color: FishUI.Theme.disabledTextColor
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Rectangle {
                                    width: pingBtnLabel.implicitWidth + 14
                                    height: 24
                                    radius: 12
                                    color: FishUI.Theme.darkMode ? Qt.rgba(0, 0.48, 1, 0.25) : Qt.rgba(0, 0.48, 1, 0.15)
                                    Layout.alignment: Qt.AlignVCenter

                                    Label {
                                        id: pingBtnLabel
                                        anchors.centerIn: parent
                                        text: qsTr("Ping")
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: FishUI.Theme.highlightColor
                                    }
                                }
                            }

                            MouseArea {
                                id: pingMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: continuity.sendPing()
                            }
                        }

                        // 3. Clipboard Sync Toggle
                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 10
                            color: clipRowMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.02))
                            antialiasing: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Image {
                                    width: 18
                                    height: 18
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    sourceSize: Qt.size(36, 36)
                                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "clipboard.svg"
                                    fillMode: Image.PreserveAspectFit
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Label {
                                    text: qsTr("Clipboard Sync")
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: FishUI.Theme.textColor
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Rectangle {
                                    width: 36
                                    height: 20
                                    radius: 10
                                    Layout.alignment: Qt.AlignVCenter
                                    color: continuity.clipboardSync ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15))
                                    antialiasing: true

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: continuity.clipboardSync ? parent.width - width - 2 : 2
                                        color: "#FFFFFF"
                                        antialiasing: true

                                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }

                            MouseArea {
                                id: clipRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: continuity.setClipboardSync(!continuity.clipboardSync)
                            }
                        }

                        // 4. Notification Sync Toggle
                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 10
                            color: notifRowMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.02))
                            antialiasing: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Image {
                                    width: 18
                                    height: 18
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    sourceSize: Qt.size(36, 36)
                                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "notification-new-symbolic.svg"
                                    fillMode: Image.PreserveAspectFit
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Label {
                                    text: qsTr("Notification Sync")
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: FishUI.Theme.textColor
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Rectangle {
                                    width: 36
                                    height: 20
                                    radius: 10
                                    Layout.alignment: Qt.AlignVCenter
                                    color: continuity.notificationSync ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15))
                                    antialiasing: true

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: continuity.notificationSync ? parent.width - width - 2 : 2
                                        color: "#FFFFFF"
                                        antialiasing: true

                                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }

                            MouseArea {
                                id: notifRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: continuity.setNotificationSync(!continuity.notificationSync)
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }
                    }

                    // Disconnected Empty State
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !continuity.isConnected
                        spacing: 10

                        Item { Layout.fillHeight: true }

                        Rectangle {
                            width: 52
                            height: 52
                            radius: 26
                            color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                            Layout.alignment: Qt.AlignHCenter

                            Image {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                sourceSize: Qt.size(52, 52)
                                source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "phone.svg"
                                opacity: 0.7
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        Label {
                            text: qsTr("No Device Connected")
                            font.bold: true
                            font.pixelSize: 13
                            color: FishUI.Theme.textColor
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Label {
                            text: qsTr("Pair your phone with KDE Connect to sync notifications, clipboard, and battery status.")
                            font.pixelSize: 11
                            color: FishUI.Theme.disabledTextColor
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            width: openKdeBtnText.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: openKdeMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(0, 0.48, 1, 0.4) : Qt.rgba(0, 0.48, 1, 0.25))
                                                       : (openKdeMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(0, 0.48, 1, 0.3) : Qt.rgba(0, 0.48, 1, 0.2)) : (FishUI.Theme.darkMode ? Qt.rgba(0, 0.48, 1, 0.2) : Qt.rgba(0, 0.48, 1, 0.12)))
                            Layout.alignment: Qt.AlignHCenter
                            antialiasing: true

                            Label {
                                id: openKdeBtnText
                                anchors.centerIn: parent
                                text: qsTr("Open KDE Connect")
                                font.pixelSize: 12
                                font.bold: true
                                color: FishUI.Theme.highlightColor
                            }

                            MouseArea {
                                id: openKdeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: continuity.openKdeConnect()
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        } // end kdeConnectView
    } // end contentArea
}
