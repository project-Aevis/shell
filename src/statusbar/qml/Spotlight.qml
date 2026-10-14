/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 *
 * Spotlight Search - macOS Sequoia Design
 */

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import QtQuick.Window 2.12
import Qt5Compat.GraphicalEffects

import Cutefish.Launcher 1.0
import Cutefish.StatusBar 1.0
import Cutefish.Shell 1.0
import FishUI 1.0 as FishUI

PopupWindow {
    id: control

    width: 620
    height: searchInput.text.length > 0 ? Math.min(520, _mainLayout.implicitHeight + 20) : 58

    color: "transparent"

    onOpened: {
        centerOnScreen()
        searchInput.text = ""
        searchInput.forceActiveFocus()
    }

    function centerOnScreen() {
        var posX = StatusBar.screenRect.x + (StatusBar.screenRect.width - control.width) / 2
        var posY = StatusBar.screenRect.y + StatusBar.screenRect.height * 0.16
        control.x = Math.round(posX)
        control.y = Math.round(posY)
    }

    LauncherModel {
        id: launcherModel
    }

    PowerActions {
        id: powerActions
    }

    ProcessProvider {
        id: process
    }

    Timer {
        id: screenshotTimer
        interval: 200
        repeat: false
        onTriggered: {
            process.startDetached("cutefish-screenshot", ["-a"])
        }
    }

    // System Settings Modules Definition
    readonly property var settingsModules: [
        { id: "wlan", name: qsTr("Wi-Fi & Networks"), keywords: "wifi wlan wireless network internet ssid", icon: "network-wireless-connected-100" },
        { id: "bluetooth", name: qsTr("Bluetooth"), keywords: "bluetooth bt wireless devices pair", icon: "bluetooth-symbolic" },
        { id: "appearance", name: qsTr("Appearance & Dark Mode"), keywords: "appearance dark light mode theme color wallpaper font", icon: "dark-mode" },
        { id: "display", name: qsTr("Displays & Resolution"), keywords: "display screen resolution scale monitor brightness orientation", icon: "brightness" },
        { id: "sound", name: qsTr("Sound & Volume"), keywords: "sound volume audio speaker microphone sink output input", icon: "audio-volume-high-symbolic" },
        { id: "dock", name: qsTr("Dock & Menu Bar"), keywords: "dock taskbar panel autohide intellihide size position", icon: "control" },
        { id: "touchpad", name: qsTr("Touchpad & Mouse"), keywords: "touchpad mouse pointer cursor speed scroll natural", icon: "settings" },
        { id: "battery", name: qsTr("Battery & Power"), keywords: "battery power energy sleep charge percentage", icon: "battery-level-100-symbolic" },
        { id: "datetime", name: qsTr("Date & Time"), keywords: "date time clock timezone calendar 24-hour", icon: "settings" },
        { id: "user", name: qsTr("Users & Accounts"), keywords: "user account password avatar login admin", icon: "settings" },
        { id: "about", name: qsTr("About This Computer"), keywords: "about system specs version cutefish os info", icon: "settings" }
    ]

    // System Power Commands Definition
    readonly property var systemCommands: [
        { id: "lock", name: qsTr("Lock Screen"), keywords: "lock screen sleep secure", icon: "system-lock-screen", action: "lock" },
        { id: "screenshot", name: qsTr("Take Screenshot"), keywords: "screenshot screen capture snip crop", icon: "screenshot", action: "screenshot" },
        { id: "logout", name: qsTr("Log Out"), keywords: "logout log out sign out exit session", icon: "system-log-out", action: "logout" },
        { id: "reboot", name: qsTr("Restart Computer"), keywords: "restart reboot power reset", icon: "system-reboot", action: "reboot" },
        { id: "shutdown", name: qsTr("Shut Down"), keywords: "shutdown shut down power off turn off", icon: "system-shutdown-symbolic", action: "shutdown" }
    ]

    // Computed Settings Matches
    property var matchedSettings: {
        var query = searchInput.text.trim().toLowerCase()
        if (!query) return []
        var res = []
        for (var i = 0; i < settingsModules.length; ++i) {
            var m = settingsModules[i]
            if (m.name.toLowerCase().indexOf(query) !== -1 || m.keywords.indexOf(query) !== -1) {
                res.push(m)
            }
        }
        return res
    }

    // Computed Command Matches
    property var matchedCommands: {
        var query = searchInput.text.trim().toLowerCase()
        if (!query) return []
        var res = []
        for (var i = 0; i < systemCommands.length; ++i) {
            var c = systemCommands[i]
            if (c.name.toLowerCase().indexOf(query) !== -1 || c.keywords.indexOf(query) !== -1) {
                res.push(c)
            }
        }
        return res
    }

    // Safe mathematical expression evaluator (no eval or Function calls)
    function evalMathExpression(expr) {
        if (!expr) return null
        var sanitized = expr.replace(/\s+/g, "")
        if (!/^[0-9\.\+\-\*\/\%\(\)\^]+$/.test(sanitized)) return null

        var pos = 0
        function parsePrimary() {
            if (pos >= sanitized.length) return null
            if (sanitized[pos] === "(") {
                pos++
                var val = parseExpression()
                if (pos >= sanitized.length || sanitized[pos] !== ")") return null
                pos++
                return val
            }
            if (sanitized[pos] === "-") {
                pos++
                var val = parsePrimary()
                return val !== null ? -val : null
            }
            if (sanitized[pos] === "+") {
                pos++
                return parsePrimary()
            }
            var start = pos
            while (pos < sanitized.length && ((sanitized[pos] >= "0" && sanitized[pos] <= "9") || sanitized[pos] === ".")) {
                pos++
            }
            if (start === pos) return null
            var num = parseFloat(sanitized.substring(start, pos))
            return isNaN(num) ? null : num
        }

        function parseExponent() {
            var left = parsePrimary()
            if (left === null) return null
            while (pos < sanitized.length && sanitized[pos] === "^") {
                pos++
                var right = parseExponent()
                if (right === null) return null
                left = Math.pow(left, right)
            }
            return left
        }

        function parseMulDiv() {
            var left = parseExponent()
            if (left === null) return null
            while (pos < sanitized.length && (sanitized[pos] === "*" || sanitized[pos] === "/" || sanitized[pos] === "%")) {
                var op = sanitized[pos++]
                var right = parseExponent()
                if (right === null) return null
                if (op === "*") left *= right
                else if (op === "/") {
                    if (right === 0) return null
                    left /= right
                } else if (op === "%") {
                    if (right === 0) return null
                    left %= right
                }
            }
            return left
        }

        function parseExpression() {
            var left = parseMulDiv()
            if (left === null) return null
            while (pos < sanitized.length && (sanitized[pos] === "+" || sanitized[pos] === "-")) {
                var op = sanitized[pos++]
                var right = parseMulDiv()
                if (right === null) return null
                if (op === "+") left += right
                else if (op === "-") left -= right
            }
            return left
        }

        var result = parseExpression()
        if (pos === sanitized.length && result !== null && isFinite(result)) {
            return result
        }
        return null
    }

    // Live Calculator Evaluator
    property var calcResult: {
        var query = searchInput.text.trim()
        if (!query || query.length < 2) return null
        return evalMathExpression(query)
    }

    FishUI.WindowBlur {
        view: control
        windowRadius: _bgRect.radius
        enabled: FishUI.Theme.blurEnabled
    }

    FishUI.WindowShadow {
        view: control
        radius: _bgRect.radius
        strength: 0.65
    }

    Rectangle {
        id: _bgRect
        anchors.fill: parent
        radius: 18
        color: FishUI.Theme.darkMode
               ? Qt.rgba(0.08, 0.08, 0.12, FishUI.Theme.blurEnabled ? 0.72 : 0.98)
               : Qt.rgba(0.96, 0.96, 0.98, FishUI.Theme.blurEnabled ? 0.75 : 0.98)
        border.width: 1 / FishUI.Dpi.ratio
        border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.18) : Qt.rgba(255, 255, 255, 0.60)
        antialiasing: true

        // Inner Specular Glass Highlight
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 17
            color: "transparent"
            border.width: 1 / FishUI.Dpi.ratio
            border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.40)
        }
    }

    ColumnLayout {
        id: _mainLayout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Top Search Bar Input
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            spacing: 12

            Image {
                width: 22
                height: 22
                sourceSize: Qt.size(22, 22)
                source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark/" : "light/") + "system-search-symbolic.svg"
                Layout.alignment: Qt.AlignVCenter
                opacity: 0.65
            }

            TextInput {
                id: searchInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                font.pointSize: 16
                font.family: "SF Pro Text"
                color: FishUI.Theme.textColor
                selectByMouse: true
                clip: true

                Text {
                    anchors.fill: parent
                    text: qsTr("Spotlight Search")
                    font.pointSize: searchInput.font.pointSize
                    font.family: searchInput.font.family
                    color: FishUI.Theme.disabledTextColor
                    visible: !searchInput.text && !searchInput.activeFocus
                }

                onTextChanged: {
                    launcherModel.search(text)
                    resultsList.currentIndex = 0
                }

                Keys.onDownPressed: {
                    if (resultsList.count > 0)
                        resultsList.currentIndex = Math.min(resultsList.count - 1, resultsList.currentIndex + 1)
                }

                Keys.onUpPressed: {
                    if (resultsList.count > 0)
                        resultsList.currentIndex = Math.max(0, resultsList.currentIndex - 1)
                }

                Keys.onReturnPressed: {
                    launchCurrent()
                }

                Keys.onEnterPressed: {
                    launchCurrent()
                }

                Keys.onEscapePressed: {
                    control.close()
                }

                function launchCurrent() {
                    // 1. Desktop Application Match
                    if (resultsList.count > 0 && resultsList.currentIndex >= 0 && resultsList.currentIndex < resultsList.count) {
                        var appId = resultsList.model.data(resultsList.model.index(resultsList.currentIndex, 0), LauncherModel.AppIdRole)
                        if (appId) {
                            launcherModel.launch(appId)
                            control.close()
                            return
                        }
                    }

                    // 2. Settings Match
                    if (control.matchedSettings.length > 0) {
                        process.startDetached("cutefish-settings", ["-m", control.matchedSettings[0].id])
                        control.close()
                        return
                    }

                    // 3. System Action Match
                    if (control.matchedCommands.length > 0) {
                        var cmd = control.matchedCommands[0]
                        control.close()
                        if (cmd.action === "lock") powerActions.lockScreen()
                        else if (cmd.action === "screenshot") screenshotTimer.restart()
                        else if (cmd.action === "logout") powerActions.logout()
                        else if (cmd.action === "reboot") powerActions.reboot()
                        else if (cmd.action === "shutdown") powerActions.shutdown()
                        return
                    }

                    // 4. Calculator
                    if (control.calcResult !== null) {
                        control.close()
                        return
                    }
                }
            }

            // Clear Button
            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.1)
                visible: searchInput.text.length > 0
                Layout.alignment: Qt.AlignVCenter
                antialiasing: true

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.pixelSize: 13
                    font.bold: true
                    color: FishUI.Theme.textColor
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        searchInput.text = ""
                        searchInput.forceActiveFocus()
                    }
                }
            }
        }

        // Top Section Divider
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(0, 0, 0, 0.08)
            visible: searchInput.text.length > 0
        }

        // 1. Live Calculator Result Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 12
            color: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.75)
            border.width: 1 / FishUI.Dpi.ratio
            border.color: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(0, 0, 0, 0.06)
            visible: control.calcResult !== null
            antialiasing: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 12

                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    color: "#FF9500"
                    antialiasing: true

                    Text {
                        anchors.centerIn: parent
                        text: "="
                        font.pixelSize: 18
                        font.bold: true
                        color: "#FFFFFF"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Label {
                        text: searchInput.text + " ="
                        font.pointSize: 9
                        color: FishUI.Theme.disabledTextColor
                    }

                    Label {
                        text: control.calcResult !== null ? control.calcResult.toString() : ""
                        font.bold: true
                        font.pointSize: 14
                        color: FishUI.Theme.textColor
                    }
                }

                Label {
                    text: qsTr("Calculator")
                    font.pointSize: 8.5
                    color: FishUI.Theme.disabledTextColor
                }
            }
        }

        // 2. System Settings Matches List
        Repeater {
            model: control.matchedSettings

            delegate: Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: 10
                color: setMouse.containsMouse ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                antialiasing: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 12

                    Image {
                        width: 28
                        height: 28
                        sourceSize: Qt.size(28, 28)
                        source: "qrc:/statusbar/images/" + (setMouse.containsMouse ? "dark/" : (FishUI.Theme.darkMode ? "dark/" : "light/")) + modelData.icon + ".svg"
                        antialiasing: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: modelData.name
                            font.bold: true
                            font.pointSize: 10.5
                            color: setMouse.containsMouse ? "#FFFFFF" : FishUI.Theme.textColor
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("System Settings")
                            font.pointSize: 8.5
                            color: setMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.8) : FishUI.Theme.disabledTextColor
                        }
                    }
                }

                MouseArea {
                    id: setMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        process.startDetached("cutefish-settings", ["-m", modelData.id])
                        control.close()
                    }
                }
            }
        }

        // 3. System Actions Matches List
        Repeater {
            model: control.matchedCommands

            delegate: Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: 10
                color: cmdMouse.containsMouse ? "#007AFF" : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                antialiasing: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 12

                    Image {
                        width: 28
                        height: 28
                        sourceSize: Qt.size(28, 28)
                        source: "qrc:/statusbar/images/" + (cmdMouse.containsMouse ? "dark/" : (FishUI.Theme.darkMode ? "dark/" : "light/")) + modelData.icon + ".svg"
                        antialiasing: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: modelData.name
                            font.bold: true
                            font.pointSize: 10.5
                            color: cmdMouse.containsMouse ? "#FFFFFF" : FishUI.Theme.textColor
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("System Action")
                            font.pointSize: 8.5
                            color: cmdMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.8) : FishUI.Theme.disabledTextColor
                        }
                    }
                }

                MouseArea {
                    id: cmdMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        control.close()
                        if (modelData.action === "lock") powerActions.lockScreen()
                        else if (modelData.action === "screenshot") screenshotTimer.restart()
                        else if (modelData.action === "logout") powerActions.logout()
                        else if (modelData.action === "reboot") powerActions.reboot()
                        else if (modelData.action === "shutdown") powerActions.shutdown()
                    }
                }
            }
        }

        // 4. Desktop Applications Results List
        ListView {
            id: resultsList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(320, count * 50)
            clip: true
            visible: searchInput.text.length > 0 && count > 0
            model: launcherModel
            spacing: 2

            delegate: Rectangle {
                id: resultDelegate
                width: ListView.view.width
                height: 48
                radius: 10
                antialiasing: true

                property bool isCurrent: ListView.isCurrentItem

                color: isCurrent ? "#007AFF"
                                 : (itemMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)) : "transparent")

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: resultsList.currentIndex = index
                    onClicked: {
                        launcherModel.launch(model.appId)
                        control.close()
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 12

                    Image {
                        width: 32
                        height: 32
                        sourceSize: Qt.size(32, 32)
                        source: model.iconName ? "image://icontheme/" + model.iconName : "image://icontheme/application-x-desktop"
                        antialiasing: true
                        smooth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Layout.alignment: Qt.AlignVCenter

                        Label {
                            text: model.name
                            font.bold: true
                            font.pointSize: 10.5
                            color: resultDelegate.isCurrent ? "#FFFFFF" : FishUI.Theme.textColor
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            text: model.comment ? model.comment : (model.genericName ? model.genericName : qsTr("Application"))
                            font.pointSize: 8.5
                            color: resultDelegate.isCurrent ? Qt.rgba(1, 1, 1, 0.8) : FishUI.Theme.disabledTextColor
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    Label {
                        text: qsTr("Application")
                        font.pointSize: 8
                        color: resultDelegate.isCurrent ? Qt.rgba(1, 1, 1, 0.7) : FishUI.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }

        // Empty Search Results Indicator
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            visible: searchInput.text.length > 0 && resultsList.count === 0 && control.calcResult === null && control.matchedSettings.length === 0 && control.matchedCommands.length === 0

            Label {
                anchors.centerIn: parent
                text: qsTr("No Results Found")
                color: FishUI.Theme.disabledTextColor
                font.pointSize: 11
            }
        }

        // Bottom Footer Hints
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            visible: searchInput.text.length > 0

            Item { Layout.fillWidth: true }

            Label {
                text: qsTr("↩ to Open   •   Esc to Close")
                font.pointSize: 7.5
                color: FishUI.Theme.disabledTextColor
            }
        }
    }
}
