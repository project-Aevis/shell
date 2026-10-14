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
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import Qt5Compat.GraphicalEffects

import Cutefish.Launcher 1.0
import Cutefish.Appearance 1.0 as Appearance
import FishUI 1.0 as FishUI

Item {
    id: root

    // Follow the actual layer-surface content size.  This is the Qt6
    // equivalent of the old QQuickView::SizeRootObjectToView behavior.
    anchors.fill: parent

    property bool showed: launcher.showed
    property real wallpaperQuality: 0.5

    property alias uninstallDialog: _uninstallDialog

    // Margins are a fraction of the surface, clamped at both ends.
    readonly property int outerMarginH: Math.max(16, Math.min(96, Math.round(root.width * 0.035)))
    readonly property int outerMarginV: Math.max(16, Math.min(64, Math.round(root.height * 0.035)))
    readonly property int sectionSpacing: Math.max(10, Math.min(48, Math.round(root.height * 0.025)))

    // The status bar and the dock keep drawing on top of this full-screen
    // surface; C++ is the side that knows where the dock is.
    readonly property int panelTop: launcher.topMargin
    readonly property int panelLeft: launcher.leftMargin
    readonly property int panelRight: launcher.rightMargin
    readonly property int panelBottom: launcher.bottomMargin

    // Scales with the surface, or it is a lost little pill on a 4K screen.
    readonly property int searchPixelSize: Math.max(12, Math.min(22, Math.round(root.height * 0.017)))
    readonly property int searchFieldWidth: Math.round(Math.max(240, Math.min(root.width * 0.22,
                                                                              root.height * 0.42)))
    readonly property int searchFieldHeight: Math.round(root.searchPixelSize * 2.3)
    readonly property int searchIconSize: Math.round(root.searchFieldHeight * 0.5)
    readonly property int searchIconGap: FishUI.Units.smallSpacing

    AppManager {
        id: appManager
    }

    Dialog {
        id: _uninstallDialog

        property var desktopPath: ""
        property var appName: ""

        width: _uninstallDialogLayout.implicitWidth + FishUI.Units.largeSpacing * 2
        height: _uninstallDialogLayout.implicitHeight + FishUI.Units.largeSpacing * 2

        modal: true

        x: (root.width - width) / 2
        y: (root.height - height) / 2

        ColumnLayout {
            id: _uninstallDialogLayout
            anchors.centerIn: parent
            anchors.margins: FishUI.Units.largeSpacing
            spacing: FishUI.Units.largeSpacing * 1.5

            Label {
                text: qsTr("Are you sure you want to uninstall %1 ?").arg(_uninstallDialog.appName)
                wrapMode: Text.WordWrap
            }

            RowLayout {
                spacing: FishUI.Units.largeSpacing

                Button {
                    text: qsTr("Cancel")
                    onClicked: _uninstallDialog.close()
                    Layout.fillWidth: true
                }

                Button {
                    flat: true
                    text: qsTr("Uninstall")
                    Layout.fillWidth: true
                    onClicked: {
                        _uninstallDialog.close()
                        appManager.uninstall(_uninstallDialog.desktopPath)
                    }
                }
            }
        }
    }

    Connections {
        target: launcher

        function onVisibleChanged(visible) {
            if (!visible) {
                _uninstallDialog.close()
            }
        }
    }

    Appearance.Wallpaper {
        id: backend
    }

    Rectangle {
        anchors.fill: parent
        color: backend.color
        visible: backend.type === 1
    }

    Image {
        id: wallpaperImage
        anchors.fill: parent
        source: "file://" + backend.path
        sourceSize: Qt.size(Math.max(1, Math.round(launcher.screenRect.width * root.wallpaperQuality)),
                            Math.max(1, Math.round(launcher.screenRect.height * root.wallpaperQuality)))
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        smooth: true
        visible: root.showed && backend.type === 0

        onSourceChanged: launcher.clearPixmapCache()
    }

    FastBlur {
        id: wallpaperBlur
        anchors.fill: parent
        radius: 48
        source: wallpaperImage
        cached: true
        visible: root.showed && wallpaperImage.visible
    }

    Rectangle {
        id: wallpaperDimmer
        anchors.fill: parent
        color: "#000000"
        opacity: backend.dimsWallpaper ? 0.5 : 0.4
        visible: root.showed && wallpaperImage.visible
    }

    LauncherModel {
        id: launcherModel
    }

    Connections {
        target: launcherModel

        function onApplicationLaunched() {
            launcher.hideWindow()
        }
    }

    // Catches the outer margins and the search row.
    MouseArea {
        anchors.fill: parent
        onClicked: launcher.hideWindow()
    }

    // Carries the window-level drag. It must not be an ancestor of the icon
    // drop areas, and it must outlive the delegate a cross-page move destroys.
    Item {
        id: dragProxy

        property string draggedAppId: ""

        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.MoveAction
        Drag.proposedAction: Qt.MoveAction
        Drag.mimeData: ({ "application/x-cutefish-desktop-id": dragProxy.draggedAppId })
        Drag.keys: ["application/x-cutefish-desktop-id"]

        Drag.onActiveChanged: {
            launcher.setDragging(dragProxy.Drag.active)
            if (!dragProxy.Drag.active)
                dragProxy.draggedAppId = ""
        }

        function startDrag(appId, image, hotSpot) {
            dragProxy.draggedAppId = appId
            dragProxy.Drag.hotSpot = hotSpot
            dragProxy.Drag.imageSource = image
            dragProxy.Drag.active = true
        }
    }

    // The whole surface accepts the drag. Without it the cursor flips to "no
    // drop" in every gap between the icons. The per-icon drop areas sit deeper
    // in the tree, so they still get the event first.
    DropArea {
        anchors.fill: parent
        keys: ["application/x-cutefish-desktop-id"]
    }

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.topMargin: root.outerMarginV + root.panelTop
        anchors.leftMargin: root.outerMarginH + root.panelLeft
        anchors.rightMargin: root.outerMarginH + root.panelRight
        anchors.bottomMargin: root.outerMarginV + root.panelBottom
        spacing: root.sectionSpacing

        Item {
            id: searchItem

            Layout.fillWidth: true
            Layout.preferredHeight: root.searchFieldHeight

            TextField {
                id: textField
                anchors.centerIn: parent
                width: root.searchFieldWidth
                height: root.searchFieldHeight

                // Keeps the typed text on the same x as the placeholder label:
                // left margin + icon + the layout's spacing.
                leftPadding: textField.activeFocus ? FishUI.Units.largeSpacing + root.searchIconSize + root.searchIconGap
                                                   : FishUI.Units.largeSpacing
                rightPadding: FishUI.Units.largeSpacing

                selectByMouse: true

                wrapMode: Text.NoWrap

                font: Qt.font({ family: Qt.application.font.family,
                                pixelSize: root.searchPixelSize })
                color: "white"

                Item {
                    id: placeHolderItem
                    height: textField.height
                    width: _placeHolderLayout.implicitWidth
                    opacity: 0.6
                    x: textField.activeFocus ? FishUI.Units.largeSpacing : (textField.width - placeHolderItem.width) / 2
                    y: 0

                    Behavior on x {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        id: _placeHolderLayout
                        anchors.fill: parent
                        // Must match the gap in textField.leftPadding, or the
                        // placeholder and the typed text sit at different x.
                        spacing: root.searchIconGap

                        Image {
                            id: _placeImage
                            height: root.searchIconSize
                            width: height
                            Layout.preferredWidth: width
                            Layout.preferredHeight: height
                            sourceSize: Qt.size(width, height)
                            source: "qrc:/launcher/images/system-search-symbolic.svg"

                            scale: textField.activeFocus ? 1.1 : 1.0
                            Behavior on scale {
                                NumberAnimation { duration: 260; easing.type: Easing.OutBack }
                            }
                        }

                        Label {
                            id: _placeLabel
                            color: "white"
                            font: Qt.font({ family: Qt.application.font.family,
                                            pixelSize: root.searchPixelSize })
                            text: qsTr("Search")
                            visible: !textField.length && !textField.preeditText && (!textField.activeFocus || textField.horizontalAlignment !== Qt.AlignHCenter)
                        }
                    }
                }

                background: Rectangle {
                    // Pill: radius is always half the height.
                    radius: height / 2
                    color: "white"
                    opacity: textField.activeFocus ? 0.28 : 0.18
                    border.width: textField.activeFocus ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.35)
                    scale: textField.activeFocus ? 1.0 : 0.985

                    Behavior on opacity {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    Behavior on scale {
                        NumberAnimation { duration: 260; easing.type: Easing.OutBack }
                    }
                }

                Timer {
                    id: searchTimer
                    interval: 150
                    repeat: false
                    onTriggered: launcherModel.search(textField.text)
                }

                onTextChanged: {
                    if (textField.text === "") {
                        searchTimer.stop()
                        launcherModel.search("")
                    } else {
                        searchTimer.start()
                    }
                }

                onAccepted: {
                    searchTimer.stop()
                    launcherModel.search(textField.text)
                    if (launcherModel.count > 0 && textField.text.length > 0) {
                        var firstAppId = launcherModel.data(launcherModel.index(0, 0), LauncherModel.AppIdRole)
                        if (firstAppId) {
                            launcherModel.launch(firstAppId)
                        }
                    }
                }

                Keys.onEscapePressed: launcher.hideWindow()
            }
        }

        Item {
            id: gridItem
            Layout.fillHeight: true
            Layout.fillWidth: true

            Keys.enabled: true
            Keys.forwardTo: appView

            AllAppsView {
                id: appView
                anchors.fill: parent
                dragSource: dragProxy
                searchMode: textField.text.length > 0
                focus: true

                Keys.enabled: true
                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Escape)
                        launcher.hideWindow()

                    if (event.key === Qt.Key_Left ||
                            event.key === Qt.Key_Right ||
                            event.key === Qt.Key_Up ||
                            event.key === Qt.Key_Down) {
                        return
                    }

                    // First input text
                    if ((event.key >= Qt.Key_A && event.key <= Qt.Key_Z) ||
                            event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                        textField.forceActiveFocus()
                        textField.text = event.text
                    }
                }

                Label {
                    anchors.centerIn: parent
                    text: qsTr("Not found")
                    font: Qt.font({ family: Qt.application.font.family,
                                    pixelSize: Math.max(20, Math.min(48, Math.round(root.height * 0.035))) })
                    color: "white"
                    visible: appView.count === 0
                }
            }
        }

        PageIndicator {
            id: pageIndicator

            count: appView.count
            currentIndex: appView.currentIndex

            interactive: true

            // Clicking a dot pages. The binding above is dropped the first time
            // the user does that, so the view has to push its index back.
            onCurrentIndexChanged: {
                if (pageIndicator.currentIndex !== appView.currentIndex)
                    appView.currentIndex = pageIndicator.currentIndex
            }

            Connections {
                target: appView
                function onCurrentIndexChanged() {
                    pageIndicator.currentIndex = appView.currentIndex
                }
            }

            spacing: FishUI.Units.largeSpacing
            Layout.alignment: Qt.AlignHCenter
            visible: appView.count > 1

            delegate: Rectangle {
                width: Math.max(8, Math.min(12, Math.round(root.height * 0.009)))
                height: width
                radius: width / 2
                color: index === pageIndicator.currentIndex ? "white" : Qt.darker("white", 1.8)
            }
        }
    }

    Repeater {
        model: 2

        DropArea {
            id: edgeDropArea
            readonly property bool previous: index === 0
            readonly property bool canPage: previous ? appView.currentIndex > 0
                                                     : appView.currentIndex < appView.count - 1

            x: previous ? 0 : root.width - width
            width: (previous ? mainLayout.x : root.width - mainLayout.x - mainLayout.width)
                   + appView.width * (1 - appView.contentWidthRatio) / 2
            height: root.height
            enabled: root.showed && !appView.searchMode && appView.count > 1
            keys: ["application/x-cutefish-desktop-id"]

            Timer {
                interval: 600
                repeat: true
                running: edgeDropArea.containsDrag && edgeDropArea.enabled && edgeDropArea.canPage
                onTriggered: {
                    if (edgeDropArea.previous)
                        appView.scrollPreviousPage()
                    else
                        appView.scrollNextPage()
                }
            }
        }
    }

    Timer {
        id: clearSearchTimer
        interval: 100
        onTriggered: textField.text = ""
    }

    Connections {
        target: launcher

        function onVisibleChanged(visible) {
            if (visible) {
                textField.focus = false
                appView.focus = true
                appView.forceActiveFocus()
            } else {
                clearSearchTimer.restart()
            }
        }
    }
}
