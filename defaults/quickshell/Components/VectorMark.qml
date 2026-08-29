import QtQuick
import "../Assets/marks.js" as Marks

// Renders an interface mark from Assets/marks.js in the caller's colours, so
// vector marks follow the theme and the widget state exactly like the
// icon-font glyphs they sit beside.
Item {
    id: root

    property string mark: ""
    property color markColor: "#ffffff"
    property color accentColor: root.markColor
    property int visualSize: 16

    function hex(value) {
        return Qt.rgba(value.r, value.g, value.b, 1).toString()
    }

    visible: root.mark !== ""
    implicitWidth: root.visualSize
    implicitHeight: root.visualSize

    Image {
        anchors.fill: parent
        source: root.mark === ""
            ? ""
            : Marks.source(root.mark, root.hex(root.markColor), root.hex(root.accentColor))
        sourceSize.width: root.visualSize * 2
        sourceSize.height: root.visualSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
}
