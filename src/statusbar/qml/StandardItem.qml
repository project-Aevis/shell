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
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import Qt5Compat.GraphicalEffects

import FishUI 1.0 as FishUI
import Cutefish.StatusBar 1.0

Item {
    id: control

    property string popupText: ""

    property bool checked: false
    property bool contextMenuPressed: false

    property alias mouseArea: _mouseArea

    signal clicked(var mouse)
    signal pressed(var mouse)
    signal wheel(var wheel)
    signal contextMenu(var mouse)

    signal positionChanged
    signal released

    function updateBackground() {
        _bgRect.state = checked || contextMenuPressed || _mouseArea.containsMouse ? "shown" : "hidden"
    }

    onCheckedChanged: control.updateBackground()
    onContextMenuPressedChanged: control.updateBackground()

    MouseArea {
        id: _mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true

        onEntered: {
            control.updateBackground()
        }

        onExited: {
            control.updateBackground()
        }

        onClicked: function(mouse) {
            control.clicked(mouse)
        }

        onPressed: function(mouse) {
            popupTips.hide()
            control.pressed(mouse)
        }

        onWheel: function(wheel) {
            control.wheel(wheel)
            wheel.accepted = false
        }

        onReleased: {
            control.released()
        }

        onContainsMouseChanged: {
            if (containsMouse && control.popupText !== "") {
                popupTips.popupText = control.popupText
                popupTips.position = Qt.point(control.mapToGlobal(0, 0).x + (control.width / 2 - popupTips.width / 2),
                                              control.height + FishUI.Units.smallSpacing)
                popupTips.show()
            } else {
                popupTips.hide()
            }
        }

        onPositionChanged: {
            control.positionChanged()
        }
    }

    Rectangle {
        id: _bgRect
        radius: FishUI.Theme.smallRadius

        state: "hidden"
        states: [
            State {
                name: "shown"
                PropertyChanges {
                    target: _bgRect
                    x: 0
                    y: 4
                    width: control.width
                    height: control.height - 8
                    visible: true
                }
            },
            State {
                name: "hidden"
                PropertyChanges {
                    target: _bgRect
                    x: 0
                    y: 0
                    width: 0
                    height: 0
                    visible: false
                }
            }
        ]

        color: {
            if (control.checked || control.contextMenuPressed) {
                return (rootItem.darkMode) ? Qt.rgba(255, 255, 255, 0.2) : Qt.rgba(0, 0, 0, 0.1)
            }

            if (_mouseArea.containsPress)
                return (rootItem.darkMode) ? Qt.rgba(255, 255, 255, 0.3) : Qt.rgba(0, 0, 0, 0.2)
            else
                return (rootItem.darkMode) ? Qt.rgba(255, 255, 255, 0.2) : Qt.rgba(0, 0, 0, 0.1)
        }
    }
}
