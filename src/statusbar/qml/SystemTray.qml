import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import Qt5Compat.GraphicalEffects

import Cutefish.Shell 1.0
import Cutefish.StatusBar 1.0
import FishUI 1.0 as FishUI

ListView {
    id: trayView

    orientation: Qt.Horizontal
    layoutDirection: Qt.RightToLeft
    interactive: false
    clip: true
    spacing: FishUI.Units.smallSpacing / 2

    property real itemWidth: rootItem.iconSize + FishUI.Units.largeSpacing
    property var contextMenuItem: null

    visible: count > 0
    Layout.fillHeight: true
    Layout.preferredWidth: count > 0 ? (count * itemWidth + Math.max(0, count - 1) * spacing) : 0

    model: SystemTrayModel {
        id: trayModel
    }

    QMenuModel {
        id: trayMenuModel
    }

    // One popup for every tray item: the model it shows is swapped as menus
    // are opened.
    ScreenHelper {
        id: screenHelper
    }

    QMenuPopup {
        id: trayMenu
        menuModel: trayMenuModel
        availableGeometry: screenHelper.availableScreenRect

        onVisibleChanged: {
            if (!visible)
                trayView.contextMenuItem = null
        }
    }

    function openContextMenu(item, globalPos) {
        var menuObject = trayModel.contextMenu(item.itemId, globalPos.x, globalPos.y)

        // An item without an exported menu was asked to show its own.
        if (!menuObject)
            return

        trayMenu.closeSubmenus()
        trayMenu.menuModel = null
        trayMenuModel.menu = menuObject
        trayMenu.menuModel = trayMenuModel
        trayMenu.setCurrentIndex(-1)
        trayView.contextMenuItem = item

        trayMenu.transientParent = item.Window.window
        var pos = item.mapToGlobal(0, item.height + FishUI.Units.smallSpacing)
        trayMenu.popupAt(pos.x, pos.y)
    }

    moveDisplaced: Transition {
        NumberAnimation {
            properties: "x, y"
            duration: 200
            easing.type: Easing.InOutQuad
        }
    }

    delegate: StandardItem {
        id: _trayItem

        property string itemId: model.id

        property bool darkMode: rootItem.darkMode
        property int dragItemIndex: index
        property bool dragStarted: false

        width: trayView.itemWidth
        height: ListView.view.height
        contextMenuPressed: trayView.contextMenuItem === _trayItem && trayMenu.visible

        onDarkModeChanged: updateTimer.restart()

        Drag.active: _trayItem.mouseArea.drag.active
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.MoveAction
        Drag.hotSpot.x: iconItem.width / 2
        Drag.hotSpot.y: iconItem.height / 2

        Drag.onDragStarted:  {
            dragStarted = true
        }

        Drag.onDragFinished: {
            dragStarted = false
        }

        onPositionChanged: {
            if (_trayItem.mouseArea.pressed) {
                _trayItem.mouseArea.drag.target = iconItem
                iconItem.grabToImage(function(result) {
                    _trayItem.Drag.imageSource = result.url
                })
            } else {
                _trayItem.mouseArea.drag.target = null
            }
        }

        onReleased: {
            _trayItem.mouseArea.drag.target = null
        }

        DropArea {
            anchors.fill: parent
            enabled: true

            onEntered: {
                if (drag.source)
                    trayModel.move(drag.source.dragItemIndex,
                                   _trayItem.dragItemIndex)
            }
        }

        Timer {
            id: updateTimer
            interval: 10
            onTriggered: iconItem.updateIcon()
        }

        FishUI.IconItem {
            id: iconItem
            anchors.centerIn: parent
            width: rootItem.iconSize
            height: width
            source: model.icon ? model.icon : (model.iconName ? model.iconName : "application-x-desktop")
            color: model.canColorOverlay ? rootItem.textColor : "transparent"
            opacity: (model.canColorOverlay && !rootItem.darkMode) ? 0.7 : 1.0
            antialiasing: true
            smooth: true
            visible: !dragStarted
        }

        onClicked: {
            var pos = trayModel.popupPosition(_trayItem, mouse.x, mouse.y)

            if (mouse.button === Qt.LeftButton) {
                trayModel.leftButtonClick(model.id, pos.x, pos.y)
            } else if (mouse.button === Qt.RightButton) {
                trayView.openContextMenu(_trayItem, pos)
            } else if (mouse.button === Qt.MiddleButton) {
                trayModel.middleButtonClick(model.id, pos.x, pos.y)
            }
        }

        popupText: model.toolTip ? model.toolTip : model.title
    }
}
