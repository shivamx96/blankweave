import QtQuick
import QtQuick.Layouts
import "PanelNavigation.js" as Navigation
import "PopupGeometry.js" as Geometry
import Quickshell

PopupWindow {
    id: root

    required property var bar
    required property var theme
    required property Item anchorItem
    default property alias content: panelContent.content
    readonly property Item navigationScope: panelScope
    property string panelId: ""
    readonly property var session: root.bar.shell && root.bar.shell.panels ? root.bar.shell.panels : null
    property var escapeHandler: null
    property bool keyboardMode: false
    property string focusIdentity: ""
    property bool open: false
    function handleKey(event) {
        keyboardMode = true
        if (event.key === Qt.Key_Escape) { if (!escapeHandler || !escapeHandler()) open = false; event.accepted = true; return }
        Navigation.key(panelScope, event)
    }
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
    readonly property real maximumHeight: Geometry.maximum(
        ((bar.screen && bar.screen.height) || 1080), bar.height)
    implicitHeight: Math.min(maximumHeight, panelContent.naturalHeight + root.theme.spacing("section") * 2)

    onClosed: {
        if (preserveNextClose) {
            preserveNextClose = false
            reopenTimer.restart()
        }
        else {
            open = false
        }
    }
    onOpenChanged: {
        if (open) {
            if (session && !(session.open && session.mode === panelId && session.targetName === bar.screen.name)) session.claim(root)
            keyboardMode = session ? session.keyboardRequest : false
            focusIdentity = ""
            Qt.callLater(() => {
                if (!root.open) return
                const items = Navigation.controls(panelScope)
                if (items.length) { items[0].forceActiveFocus(Qt.TabFocusReason); Navigation.reveal(items[0]) }
            })
        } else if (session && !session.synchronizing && session.mode === panelId && bar.screen && session.targetName === bar.screen.name) session.dismiss()
        syncVisibilityHold()
    }

    Component.onCompleted: { if (session) session.registerPanel(root); syncVisibilityHold() }
    Component.onDestruction: {
        if (session) session.unregisterPanel(root)
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
        id: panelScope
        readonly property var panelController: root
        anchors.fill: parent
        focus: root.visible
        Keys.priority: Keys.AfterItem
        Keys.onPressed: event => root.handleKey(event)

        // One uniform border, the same as the tooltip and the bar's widgets,
        // rather than accent hairlines that vary along the edges.
        ThemeSurface {
            surfaceTheme: root.theme
            anchors.fill: parent
            radius: root.theme.panelRadius
            color: root.theme.panelSurface
            border.width: root.theme.borderWidth
            border.color: root.theme.outlineStrong
        }

        PanelViewport {
            id: panelContent
            theme: root.theme
            anchors.fill: parent
            anchors.margins: root.theme.spacing("section")
        }
    }
}
