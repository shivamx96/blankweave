import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    required property var bar
    required property var theme
    required property Item anchorItem
    default property alias content: panelContent.children
    property bool open: false
    property bool preserveNextClose: false
    property int panelWidth: 340
    property string anchorAlignment: "right"

    function syncVisibilityHold() {
        if (root.bar && root.bar.setVisibilityHold)
            root.bar.setVisibilityHold(root, root.open)
    }

    visible: open
    grabFocus: true
    color: "transparent"
    implicitWidth: panelWidth
    implicitHeight: panelContent.implicitHeight + 28

    onClosed: {
        if (preserveNextClose) {
            preserveNextClose = false
            reopenTimer.restart()
        }
        else {
            open = false
        }
    }
    onOpenChanged: syncVisibilityHold()

    Component.onCompleted: syncVisibilityHold()
    Component.onDestruction: {
        if (root.bar && root.bar.setVisibilityHold)
            root.bar.setVisibilityHold(root, false)
    }

    Timer {
        id: reopenTimer
        interval: 1
        onTriggered: root.open = true
    }

    anchor {
        id: popupAnchor
        window: root.bar
        adjustment: PopupAdjustment.Slide
        edges: root.bar.atBottom
            ? (Edges.Bottom | Edges.Left)
            : (Edges.Top | Edges.Left)
        gravity: root.bar.atBottom
            ? (Edges.Top | Edges.Right)
            : (Edges.Bottom | Edges.Right)
        rect.width: 1
        rect.height: 1

        onAnchoring: {
            const target = root.anchorItem
            if (!target)
                return

            const targetX = root.anchorAlignment === "center"
                ? target.width / 2 - root.implicitWidth / 2
                : target.width - root.implicitWidth
            // A bottom-anchored surface cannot offer a negative anchor rect;
            // use the target's top edge and let upward gravity place the panel.
            const targetY = root.bar.atBottom ? 0 : target.height + 8
            const point = root.bar.contentItem.mapFromItem(target, targetX, targetY)
            popupAnchor.rect.x = Math.round(Math.max(6, Math.min(point.x, root.bar.width - root.implicitWidth - 6)))
            popupAnchor.rect.y = Math.round(point.y)
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.open = false

        // One uniform border, the same as the tooltip and the bar's widgets,
        // rather than accent hairlines that vary along the edges.
        Rectangle {
            anchors.fill: parent
            radius: root.theme.panelRadius
            color: root.theme.panelSurface
            border.width: 1
            border.color: root.theme.outlineStrong
        }

        ColumnLayout {
            id: panelContent
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
        }
    }
}
