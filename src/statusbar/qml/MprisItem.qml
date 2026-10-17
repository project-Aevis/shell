/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * Modern macOS Now Playing Media Card (Pre-Liquid Glass / Big Sur - Sonoma)
 */

import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import Qt5Compat.GraphicalEffects
import FishUI 1.0 as FishUI
import Cutefish.Media 1.0

Item {
    id: control

    property bool available: mprisManager.availableServices.length > 0
    property bool isPlaying: currentService && mprisManager.playbackStatus === Mpris.Playing
    property alias currentService: mprisManager.currentService
    property var artUrlTag: Mpris.metadataToString(Mpris.ArtUrl)
    property var titleTag: Mpris.metadataToString(Mpris.Title)
    property var artistTag: Mpris.metadataToString(Mpris.Artist)

    property var cardBgColor: FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08)
                                                    : Qt.rgba(1, 1, 1, 0.75)
    property var cardBorderColor: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.10)
                                                        : Qt.rgba(0, 0, 0, 0.05)

    MprisManager {
        id: mprisManager

        onCurrentServiceChanged: {
            control.updateInfo()
        }

        onMetadataChanged: {
            control.updateInfo()
        }
    }

    Component.onCompleted: { control.updateInfo() }

    function extractString(val) {
        if (val === undefined || val === null) return "";
        if (Array.isArray(val)) return val.join(", ");
        return String(val).trim();
    }

    function updateInfo() {
        var metadata = mprisManager.metadata || {}
        var title = ""
        var artist = ""
        var artUrl = ""

        if (metadata) {
            if (titleTag in metadata) title = extractString(metadata[titleTag])
            if (!title && "xesam:title" in metadata) title = extractString(metadata["xesam:title"])
            if (!title && "title" in metadata) title = extractString(metadata["title"])

            if (artistTag in metadata) artist = extractString(metadata[artistTag])
            if (!artist && "xesam:artist" in metadata) artist = extractString(metadata["xesam:artist"])
            if (!artist && "artist" in metadata) artist = extractString(metadata["artist"])

            if (artUrlTag in metadata) artUrl = normalizeArtUrl(extractString(metadata[artUrlTag]))
            if (!artUrl && "mpris:artUrl" in metadata) artUrl = normalizeArtUrl(extractString(metadata["mpris:artUrl"]))
            if (!artUrl && "artUrl" in metadata) artUrl = normalizeArtUrl(extractString(metadata["artUrl"]))
        }

        var hasTrack = (title !== "" || artist !== "")

        control.visible = true
        _songLabel.text = hasTrack ? title : qsTr("Music Center")
        _artistLabel.text = hasTrack ? artist : qsTr("Not Playing")
        if (artUrl !== "") {
            artImage.source = artUrl
        } else {
            artImage.source = ""
        }
    }

    function normalizeArtUrl(value) {
        var url = value === undefined || value === null ? "" : String(value).trim()
        if (url.charAt(0) === "/")
            return "file://" + url
        return url
    }

    // Frosted Card Surface
    Rectangle {
        anchors.fill: parent
        color: control.cardBgColor
        radius: 14
        border.width: 1 / FishUI.Dpi.ratio
        border.color: control.cardBorderColor
        antialiasing: true
    }

    RowLayout {
        id: _mainLayout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // Album Art
        Item {
            Layout.preferredWidth: 52
            Layout.preferredHeight: 52
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                id: artMask
                width: 52
                height: 52
                radius: 10
                visible: false
            }

            Image {
                id: defaultImage
                anchors.fill: parent
                source: "qrc:/statusbar/images/media-cover.svg"
                sourceSize: Qt.size(Math.ceil(52 * FishUI.Dpi.ratio), Math.ceil(52 * FishUI.Dpi.ratio))
                visible: !artImage.visible
                fillMode: Image.PreserveAspectCrop

                layer.enabled: defaultImage.visible
                layer.smooth: true
                layer.textureSize: Qt.size(Math.ceil(width * FishUI.Dpi.ratio), Math.ceil(height * FishUI.Dpi.ratio))
                layer.effect: OpacityMask {
                    maskSource: artMask
                }
            }

            Image {
                id: artImage
                anchors.fill: parent
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(Math.ceil(64 * FishUI.Dpi.ratio), Math.ceil(64 * FishUI.Dpi.ratio))
                asynchronous: true

                layer.enabled: artImage.visible
                layer.smooth: true
                layer.textureSize: Qt.size(Math.ceil(width * FishUI.Dpi.ratio), Math.ceil(height * FishUI.Dpi.ratio))
                layer.effect: OpacityMask {
                    maskSource: artMask
                }
            }

            // Subtle inner border over album art
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.width: 1 / FishUI.Dpi.ratio
                border.pixelAligned: FishUI.Dpi.ratio > 1 ? false : true
                border.color: Qt.rgba(0, 0, 0, 0.15)
                antialiasing: true
            }
        }

        // Track & Artist Information
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (mprisManager.canRaise) {
                        mprisManager.raise()
                    } else if (mprisManager.desktopEntry && mprisManager.desktopEntry.length > 0) {
                        process.startDetached(mprisManager.desktopEntry)
                    } else {
                        process.startDetached("cutefish-music")
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 2

                Label {
                    id: _songLabel
                    Layout.fillWidth: true
                    visible: _songLabel.text !== ""
                    elide: Text.ElideRight
                    font.bold: true
                    font.pointSize: FishUI.Theme.fontSize
                    color: FishUI.Theme.textColor
                }

                Label {
                    id: _artistLabel
                    Layout.fillWidth: true
                    visible: _artistLabel.text !== ""
                    elide: Text.ElideRight
                    font.pointSize: FishUI.Theme.smallFont.pointSize
                    color: FishUI.Theme.disabledTextColor
                }
            }
        }

        // Playback Control Buttons
        RowLayout {
            spacing: 6
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: 32

            Rectangle {
                id: prevButton
                implicitWidth: 28
                implicitHeight: 28
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 14
                visible: true
                enabled: mprisManager.canGoPrevious || control.available
                opacity: enabled ? 1.0 : 0.45
                color: enabled && prevMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15))
                                                    : (enabled && prevMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                antialiasing: true
                scale: enabled && prevMouse.pressed ? 0.90 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 100 }
                }

                Image {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    sourceSize: Qt.size(Math.ceil(20 * FishUI.Dpi.ratio), Math.ceil(20 * FishUI.Dpi.ratio))
                    mipmap: false
                    smooth: true
                    antialiasing: true
                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark" : "light") + "/media-skip-backward-symbolic.svg"
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: parent.enabled
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (mprisManager.canGoPrevious) {
                            mprisManager.previous()
                        } else if (control.available) {
                            mprisManager.setPosition(0)
                        }
                    }
                }
            }

            Rectangle {
                id: playButton
                implicitWidth: 32
                implicitHeight: 32
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                radius: 16
                visible: true
                enabled: true
                opacity: 1.0
                color: playMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.18))
                                         : (playMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08))
                                                                    : (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04)))
                antialiasing: true
                scale: playMouse.pressed ? 0.90 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 100 }
                }

                Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    sourceSize: Qt.size(Math.ceil(16 * FishUI.Dpi.ratio), Math.ceil(16 * FishUI.Dpi.ratio))
                    mipmap: false
                    smooth: true
                    antialiasing: true
                    source: control.isPlaying ? "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark" : "light") + "/media-playback-pause-symbolic.svg"
                                              : "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark" : "light") + "/media-playback-start-symbolic.svg"
                }

                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (control.available) {
                            mprisManager.playPause()
                        } else if (mprisManager.desktopEntry && mprisManager.desktopEntry.length > 0) {
                            process.startDetached(mprisManager.desktopEntry)
                        } else {
                            process.startDetached("cutefish-music")
                        }
                    }
                }
            }

            Rectangle {
                id: nextButton
                implicitWidth: 28
                implicitHeight: 28
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 14
                visible: true
                enabled: mprisManager.canGoNext || control.available
                opacity: enabled ? 1.0 : 0.45
                color: enabled && nextMouse.pressed ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15))
                                                    : (enabled && nextMouse.containsMouse ? (FishUI.Theme.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                antialiasing: true
                scale: enabled && nextMouse.pressed ? 0.90 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 100 }
                }

                Image {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    sourceSize: Qt.size(Math.ceil(20 * FishUI.Dpi.ratio), Math.ceil(20 * FishUI.Dpi.ratio))
                    mipmap: false
                    smooth: true
                    antialiasing: true
                    source: "qrc:/statusbar/images/" + (FishUI.Theme.darkMode ? "dark" : "light") + "/media-skip-forward-symbolic.svg"
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: parent.enabled
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (mprisManager.canGoNext) {
                            mprisManager.next()
                        }
                    }
                }
            }
        }
    }
}
