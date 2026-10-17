import QtQuick 2.12
import QtQuick.Effects
import FishUI 1.0 as FishUI

Item {
    id: control

    property alias text: _label.text
    property alias font: _label.font
    property alias color: _label.color
    property bool dropShadow: false

    implicitWidth: _label.implicitWidth
    implicitHeight: _label.implicitHeight

    // A blurred black copy of the text, not a layer effect on the label itself:
    // a layer pushes the glyphs through an FBO, which loses the hinting and
    // turns their subpixel coverage into colour fringes. Only the copy's alpha
    // survives the blur, so its own fringing does not matter.
    Item {
        id: _shadowHolder
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        // Room for the blur to fall outside the glyphs.
        width: _label.width + 16
        height: _label.height + 16
        visible: control.dropShadow
        opacity: 0.3

        Text {
            anchors.centerIn: parent
            text: _label.text
            font: _label.font
            color: "black"
        }

        layer.enabled: control.dropShadow
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 6
            blur: 0.5
        }
    }

    // The glyphs keep the fontconfig subpixel fringes (neither Text.QtRendering
    // nor QQuickWindow::setTextRenderType switches them off in this process).
    // The soft halo is too diffuse to cover them; this faint 1px edge is.
    Text {
        id: _label
        anchors.centerIn: parent
        font.family: FishUI.Theme.fontFamily
        renderType: Text.QtRendering
        style: control.dropShadow ? Text.Raised : Text.Normal
        styleColor: Qt.rgba(0, 0, 0, 0.14)
    }
}
