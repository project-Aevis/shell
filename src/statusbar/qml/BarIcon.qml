import QtQuick 2.12
import QtQuick.Window
import QtQuick.Effects

// Bar icons sit straight on the wallpaper; same soft shadow the text gets.
Image {
    id: control

    property bool dropShadow: false

    smooth: true
    mipmap: true
    antialiasing: true
    fillMode: Image.PreserveAspectFit

    sourceSize.width: Math.max(64, Math.ceil(width * (Window.devicePixelRatio || 2) * 2))
    sourceSize.height: Math.max(64, Math.ceil(height * (Window.devicePixelRatio || 2) * 2))

    layer.enabled: control.dropShadow
    layer.smooth: true
    layer.textureSize: Qt.size(Math.max(64, Math.ceil(width * (Window.devicePixelRatio || 2) * 2)), Math.max(64, Math.ceil(height * (Window.devicePixelRatio || 2) * 2)))
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 1
        blurMax: 6
        shadowBlur: 0.5
        shadowColor: "black"
        shadowOpacity: 0.25
    }
}
