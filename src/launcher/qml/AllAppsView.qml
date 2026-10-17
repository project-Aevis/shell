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

import QtQuick 2.15
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12

import Cutefish.Launcher 1.0

ListView {
    id: control

    property bool searchMode: false

    // Qt refuses a drag enter whose source item is an ancestor of the DropArea,
    // so the drag cannot be carried by the view: it lives on a proxy item that
    // sits beside the grid and survives the delegate being recycled.
    property Item dragSource: null
    readonly property string draggedAppId: dragSource ? dragSource.draggedAppId : ""

    property string _pendingDragId: ""
    property url _pendingDragImage: ""
    property string _pendingMoveId: ""
    property int _pendingMoveTo: -1

    // An automatic drag runs a nested event loop, and a reorder inside it
    // deletes the delegate whose handler asked for the drag. Both the drag and
    // the move therefore have to leave the delegate's stack frame first.
    function startDrag(appId, image) {
        control._pendingDragId = appId
        control._pendingDragImage = image
        Qt.callLater(control._beginDrag)
    }

    function _beginDrag() {
        const appId = control._pendingDragId
        control._pendingDragId = ""
        if (!control.dragSource || appId === "")
            return

        control.dragSource.startDrag(appId, control._pendingDragImage,
                                     Qt.point(control.iconSize / 2, control.iconSize / 2))
    }

    function requestMove(to) {
        // Captured now: the drag is over by the time a move asked for on drop
        // gets to run.
        control._pendingMoveId = control.draggedAppId
        control._pendingMoveTo = to
        Qt.callLater(control._applyMove)
    }

    function _applyMove() {
        const appId = control._pendingMoveId
        const to = control._pendingMoveTo
        control._pendingMoveId = ""
        control._pendingMoveTo = -1
        if (appId === "" || to < 0)
            return

        const from = launcherModel.findById(appId)
        if (from < 0 || from === to)
            return

        control.startSettle()
        launcherModel.move(from, to)
    }

    // Deadlines rather than Timers: a QML Timer is a pause animation and stops
    // being advanced while the launcher window is hidden, so one that was
    // running at hide time reports running forever after.
    property double settleUntil: 0

    // True while a swap or a page change is still animating. Without it the
    // delegates sliding past the cursor each claim the drag and it bounces.
    function settling() {
        return Date.now() < control.settleUntil
    }

    property var sourceModel: launcherModel
    property int modelCount: sourceModel.count

    // A fixed column/row count per size class; the cell scales to fit.
    readonly property int columns: control.width < 720  ? 4
                                 : control.width < 1100 ? 5
                                 : control.width < 1500 ? 6
                                 : control.width < 2000 ? 7
                                 : control.width < 2800 ? 8
                                                        : 9

    readonly property int rows: control.height < 420  ? 2
                              : control.height < 620  ? 3
                              : control.height < 880  ? 4
                              : control.height < 1440 ? 5
                                                      : 6

    // Never zero: the view is laid out once at zero size while the window
    // is being created.
    readonly property int pageCount: Math.max(1, control.columns * control.rows)

    // Leaves a gutter on both sides at every resolution.
    readonly property real contentWidthRatio: 0.86

    readonly property int cellWidth: Math.max(64, Math.floor(control.width * control.contentWidthRatio
                                                             / control.columns))
    readonly property int cellHeight: Math.max(64, Math.floor(Math.min(control.height / control.rows,
                                                                       control.cellWidth * 1.15)))

    // The label reserves two lines so every row of icons shares a baseline;
    // the icon takes what is left. Must respect height too, or it overflows
    // the cell on short screens.
    readonly property int labelPixelSize: Math.max(11, Math.min(18, Math.round(control.cellWidth * 0.085)))
    readonly property int labelHeight: Math.round(control.labelPixelSize * 2.8)
    readonly property int cellSpacing: Math.max(6, Math.round(control.cellWidth * 0.06))

    readonly property int iconSize: Math.max(32, Math.min(160,
        Math.min(Math.round(control.cellWidth * 0.44),
                 Math.round((control.cellHeight - control.labelHeight) * 0.68))))

    orientation: ListView.Horizontal
    snapMode: ListView.SnapOneItem
    model: control.modelCount > 0 ? Math.ceil(control.modelCount / control.pageCount) : 0

    maximumFlickVelocity: 10000
    highlightMoveDuration: 240

    preferredHighlightBegin: 0
    preferredHighlightEnd: 0
    highlightRangeMode: ListView.StrictlyEnforceRange
    highlightFollowsCurrentItem: true

    // Keep one extra page ready without tying the cache size to the model
    // count, which can trigger a binding loop while the view is resizing.
    cacheBuffer: control.width
    boundsBehavior: Flickable.DragOverBounds
    currentIndex: -1
    clip: true

    function startSettle(duration) {
        control.settleUntil = Date.now() + (duration === undefined ? 270 : duration)
    }

    // An explicit currentIndex of -1 marks the index as cleared, so the view
    // never selects page 0 on its own and currentItem stays null.
    onCountChanged: {
        if (control.count > 0 && control.currentIndex < 0)
            control.currentIndex = 0
    }

    // Paging is driven from the page's MouseArea below: a WheelHandler on the
    // view never activates, and a horizontal Flickable ignores a vertical wheel.
    property real wheelAccumulated: 0

    function handleWheel(event) {
        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
        if (delta === 0)
            return

        event.accepted = true
        wheelResetTimer.restart()
        if ((control.wheelAccumulated > 0) !== (delta > 0))
            control.wheelAccumulated = 0

        // A touchpad sends many small deltas. Page once per notch's worth of
        // them, or a two-finger scroll runs through the whole grid.
        control.wheelAccumulated += delta
        if (Math.abs(control.wheelAccumulated) < 120)
            return

        control.wheelAccumulated = 0
        if (delta > 0)
            control.scrollPreviousPage()
        else
            control.scrollNextPage()
    }

    Timer {
        id: wheelResetTimer
        interval: 250
        onTriggered: control.wheelAccumulated = 0
    }

    delegate: Item {
        id: _pageItem

        width: control.width
        height: control.height

        readonly property int pageIndex: index

        // Anything that is not an icon or the search field dismisses. Also the
        // lowest item in the chain that still sees every wheel event.
        MouseArea {
            anchors.fill: parent
            onClicked: launcher.hideWindow()
            onWheel: function (wheel) { control.handleWheel(wheel) }
        }

        GridView {
            id: _page

            anchors.centerIn: parent
            width: control.cellWidth * control.columns
            height: control.cellHeight * control.rows

            cellWidth: control.cellWidth
            cellHeight: control.cellHeight

            interactive: false

            displaced: Transition {
                NumberAnimation {
                    properties: "x, y"
                    duration: 260
                    easing.type: Easing.OutQuint
                }
            }

            moveDisplaced: Transition {
                NumberAnimation {
                    properties: "x, y"
                    duration: 260
                    easing.type: Easing.OutQuint
                }
            }

            // The dragged item is hidden, but its slot still has to travel with
            // the rest or it snaps into place when the drag ends.
            move: Transition {
                NumberAnimation {
                    properties: "x, y"
                    duration: 260
                    easing.type: Easing.OutQuint
                }
            }

            model: PageModel {
                id: _pageModel
                sourceModel: launcherModel
                startIndex: control.pageCount * _pageItem.pageIndex
                limitCount: control.pageCount
            }

            delegate: GridItemDelegate {
                width: control.cellWidth
                height: control.cellHeight
                searchMode: control.searchMode
                pageIndex: _pageItem.pageIndex
                pageCount: control.pageCount
                iconSize: control.iconSize
                labelPixelSize: control.labelPixelSize
                labelHeight: control.labelHeight
                spacing: control.cellSpacing
                view: control
            }
        }
    }

    function goToPage(index) {
        if (index < 0 || index >= control.count || index === control.currentIndex)
            return

        control.currentIndex = index
        control.startSettle(control.highlightMoveDuration)
    }

    function scrollNextPage() {
        control.goToPage(Math.max(0, control.currentIndex) + 1)
    }

    function scrollPreviousPage() {
        control.goToPage(Math.max(0, control.currentIndex) - 1)
    }
}
