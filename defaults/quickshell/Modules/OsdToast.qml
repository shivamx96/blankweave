import QtQuick
import Quickshell
import Quickshell.Wayland
PanelWindow {
    id: root
    required property var modelData
    required property var theme
    required property var feedback
    screen: modelData
    visible: feedback.visible && modelData.name === feedback.screenName
    color: "transparent"
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    surfaceFormat.opaque: false
    anchors.bottom: true
    margins.bottom: theme.spacing("page")
    mask: Region { }
    WlrLayershell.namespace: "blankweave-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    OsdCard { id: card; anchors.fill: parent; theme: root.theme; feedback: root.feedback }
}
