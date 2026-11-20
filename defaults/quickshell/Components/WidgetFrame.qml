import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "TooltipHints.js" as TooltipHints

Item {
    id: root

    required property var bar
    required property var theme

    property string icon: ""
    property string iconMark: ""
    // Icon-theme artwork for a specific application. Marks and glyphs are the
    // bar's own monochrome language; this is the exception, for showing which
    // app a widget is actually about.
    property url iconImage: ""
    // Sized so a full-bleed icon lands on the bar's optical target; artwork
    // that carries its own margin reads slightly smaller, as its author meant.
    property int iconImageSize: theme.barIconSize - 2
    property int iconVisualSize: theme.barIconSize + 1
    property int iconPixelSize: theme.barIconSize
    property string label: ""
    property string tooltip: ""
    property var dataSources: []
    readonly property bool dataStale: dataSources.some(source => source.stale)
    readonly property string staleDetail: dataSources.filter(source => source.stale)
        .map(source => source.staleText).filter((line, index, lines) => lines.indexOf(line) === index).join("\n")
    property string rightClickHint: ""
    property string scrollHint: ""
    readonly property string tooltipText: TooltipHints.text(tooltip + (staleDetail ? "\n" + staleDetail : ""), rightClickHint, scrollHint)
    onTooltipTextChanged: {
        if (mouse.containsMouse && root.tooltipText)
            root.bar.showTooltip(root, root.tooltipText)
    }
    property bool active: false
    property bool attention: false
    property bool iconOnly: false
    property int labelWeight: Font.Medium
    property int labelWidth: 0
    property int horizontalPadding: theme.widgetPadding
    property color foreground: dataStale ? theme.textMuted : attention ? theme.critical : (active ? theme.accentBright : theme.text)
    // Vector marks carry an accent detail. Once the widget itself is accented
    // the detail would disappear into it, so the mark goes monochrome instead.
    readonly property color markAccent: dataStale || active || attention ? foreground : theme.accentBright

    signal pressed(int button)
    signal scrolled(int steps)

    readonly property bool barHitFrame: true
    readonly property var hitBounds: typeof bar.hitBounds === "function"
        ? bar.hitBounds(root) : Qt.rect(0, 0, width, height)
    property real wheelRemainder: 0

    function resetScroll() {
        wheelRemainder = 0
        scrollPause.stop()
    }
    function accumulateWheel(vertical, inverted) {
        if (!vertical) return
        wheelRemainder += inverted ? -vertical : vertical
        const steps = Math.trunc(wheelRemainder / 120)
        wheelRemainder -= steps * 120
        scrollPause.restart()
        if (steps) scrolled(steps)
    }
    Timer { id: scrollPause; interval: 250; onTriggered: root.resetScroll() }

    implicitWidth: content.implicitWidth + horizontalPadding * 2
    implicitHeight: theme.widgetHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: root.label ? theme.widgetContentGap : 0

        IconImage {
            visible: root.iconImage.toString() !== ""
            Layout.preferredWidth: root.iconImageSize
            Layout.preferredHeight: root.iconImageSize
            source: root.iconImage
            mipmap: true
        }

        VectorMark {
            mark: root.iconMark
            markColor: root.foreground
            accentColor: root.markAccent
            visualSize: root.iconVisualSize
        }

        Text {
            visible: root.iconImage.toString() === "" && root.iconMark === "" && root.icon !== ""
            text: root.icon
            color: root.foreground
            font.family: theme.iconFontFamily
            font.pixelSize: root.iconPixelSize
            renderType: Text.NativeRendering
        }

        Text {
            visible: !root.iconOnly && root.label !== ""
            Layout.preferredWidth: root.labelWidth > 0 ? root.labelWidth : implicitWidth
            text: root.label
            color: root.foreground
            horizontalAlignment: root.labelWidth > 0 ? Text.AlignRight : Text.AlignLeft
            font.family: theme.fontFamily
            font.pixelSize: theme.textSize
            font.weight: root.labelWeight
            font.letterSpacing: 0.1
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bar.atBottom ? 0 : parent.height - height
        width: mouse.containsMouse ? Math.max(8, root.width - root.horizontalPadding * 2) : 0
        height: 1
        color: root.dataStale ? root.theme.textMuted : root.attention ? root.theme.critical : root.theme.accentBright
        opacity: mouse.pressed ? 1 : 0.72

        Behavior on width {
            NumberAnimation { duration: root.theme.motionDuration; easing.type: root.theme.motionEasing }
        }
    }

    MouseArea {
        id: mouse
        objectName: "barWidgetHitArea"
        x: root.hitBounds.x
        y: root.hitBounds.y
        width: root.hitBounds.width
        height: root.hitBounds.height
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            if (root.tooltipText)
                root.bar.showTooltip(root, root.tooltipText)
        }
        onExited: {
            root.resetScroll()
            root.bar.hideTooltip(root)
        }
        onClicked: mouse => root.pressed(mouse.button)
        onWheel: wheel => {
            wheel.accepted = wheel.angleDelta.y !== 0
            root.accumulateWheel(wheel.angleDelta.y, wheel.inverted)
        }
    }

    Component.onDestruction: root.bar.hideTooltip(root)
}
