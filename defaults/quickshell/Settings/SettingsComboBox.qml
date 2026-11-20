pragma ComponentBehavior: Bound
import QtQuick
import "../Components/PanelNavigation.js" as Navigation
import "../Components"
import QtQuick.Controls.Basic as Controls

// Own every painted surface: the desktop Qt style can retain a light palette
// even when Blankweave switches themes while this window is open.
Controls.ComboBox {
    id: root
    Keys.onPressed: event => {
        if (searchable && popup.visible) {
            filterKey(event)
            if (!event.accepted && event.text && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                searchInput().text += event.text
                menu.headerItem.forceActiveFocus()
                event.accepted = true
            }
        } else Navigation.route(root, event)
    }
    Keys.onReturnPressed: event => { if (searchable && popup.visible) filterKey(event); else event.accepted = false }
    Keys.onEnterPressed: event => { if (searchable && popup.visible) filterKey(event); else event.accepted = false }
    Keys.onEscapePressed: event => { if (searchable && popup.visible) filterKey(event); else event.accepted = false }
    FocusRing { theme: root.theme }
    required property var theme

    // Keep the native short-menu interaction; search starts at 12 options.
    readonly property bool searchable: count >= 12
    property var optionEnabled: function(index) { return true }
    property string filterText: ""
    property int filterIndex: 0
    readonly property var filteredIndices: {
        let found = []
        const needle = filterText.toLowerCase()
        for (let i = 0; i < count; i++)
            if ((textAt(i) + " " + String(valueAt(i))).toLowerCase().includes(needle)) found.push(i)
        return found
    }
    onFilteredIndicesChanged: if (searchable && popup.visible) Qt.callLater(() => menu.headerItem.forceActiveFocus())
    function searchInput(): Controls.TextField { return menu.headerItem as Controls.TextField }
    function filterKey(event) {
        if (event.key === Qt.Key_Escape) {
            if (filterText) { filterText = ""; searchInput().text = "" }
            else popup.close()
        } else if (event.key === Qt.Key_Down) filterIndex = Math.min(filteredIndices.length - 1, filterIndex + 1)
        else if (event.key === Qt.Key_Up) filterIndex = Math.max(0, filterIndex - 1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (filteredIndices.length && optionEnabled(filteredIndices[Math.max(0, filterIndex)])) {
                const selected = filteredIndices[Math.max(0, filterIndex)]
                popup.close()
                currentIndex = selected
                activated(selected)
            }
        } else return
        if (popup.visible) menu.headerItem.forceActiveFocus()
        event.accepted = true
    }

    implicitHeight: Math.max(36, implicitContentHeight + topPadding + bottomPadding)
    implicitWidth: 190
    leftPadding: root.theme.spacing("xl")
    rightPadding: root.theme.spacing("content")
    hoverEnabled: true
    font.family: theme.fontFamily
    font.weight: theme.textWeight
    font.pixelSize: theme.smallTextSize

    contentItem: Text {
        text: root.displayText
        textFormat: Text.PlainText
        font: root.font
        color: root.enabled ? root.theme.text : root.theme.textMuted
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: root.width - width - 12
        y: (root.height - height) / 2
        text: "▾"
        font: root.font
        color: root.enabled ? root.theme.text : root.theme.textMuted
    }

    background: Rectangle {
        radius: root.theme.widgetRadius
        color: root.down ? root.theme.surfacePressed
            : root.hovered && root.enabled ? root.theme.surfaceHover : root.theme.surfaceRaised
        border.width: root.activeFocus ? Math.max(1, root.theme.borderWidth) : root.theme.borderWidth
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
    }

    delegate: Controls.ItemDelegate {
        id: option
        FocusRing { theme: root.theme; target: option }
        required property int index
        required property var modelData
        enabled: root.optionEnabled(index)
        width: menu.width
        readonly property bool matchesFilter: !root.searchable || root.filteredIndices.includes(index)
        visible: matchesFilter
        height: matchesFilter ? implicitHeight : 0
        implicitHeight: Math.max(38, implicitContentHeight + topPadding + bottomPadding)
        leftPadding: root.theme.spacing("xl")
        rightPadding: root.theme.spacing("xl")
        text: root.textAt(index)
        highlighted: root.searchable ? root.filteredIndices[root.filterIndex] === index : root.highlightedIndex === index
        hoverEnabled: true
        font: root.font
        Accessible.name: text

        contentItem: Text {
            text: option.text
            textFormat: Text.PlainText
            font: option.font
            color: option.highlighted || option.index === root.currentIndex
                ? root.theme.accentBright : root.theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: root.theme.widgetRadius
            color: option.down ? root.theme.surfacePressed
                : option.highlighted ? root.theme.accentSurface
                : option.hovered ? root.theme.surfaceHover : "transparent"
            border.width: option.visualFocus ? Math.max(1, root.theme.borderWidth) : 0
            border.color: root.theme.accentBright
        }
    }

    popup: Controls.Popup {
        focus: root.searchable
        y: root.height + 4
        width: root.width
        padding: root.theme.spacing("xs")
        topMargin: root.theme.spacing("md")
        bottomMargin: root.theme.spacing("md")
        height: Math.min((root.searchable ? menu.contentHeight : menu.contentHeight) + padding * 2, 320)
        onOpened: if (root.searchable) { root.filterText = ""; root.filterIndex = 0; root.searchInput().text = ""; Qt.callLater(() => menu.headerItem.forceActiveFocus()) }
        onClosed: { root.filterText = ""; root.forceActiveFocus() }
        popupType: Controls.Popup.Item

        contentItem: ListView {
            id: menu
            clip: true
            model: root.delegateModel
            currentIndex: root.searchable ? (root.filteredIndices[root.filterIndex] ?? -1) : root.highlightedIndex
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            headerPositioning: ListView.OverlayHeader
            header: Controls.TextField {
                id: searchField
                objectName: "comboFilter"
                color: root.theme.text
                font: root.font
                background: Rectangle { color: root.theme.surfaceRaised }
                visible: root.searchable
                width: menu.width; height: root.searchable ? 44 : 0
                z: 3
                placeholderText: "Filter options"
                Accessible.name: "Filter options"
                onTextChanged: { root.filterText = text; root.filterIndex = 0 }
                Keys.onPressed: event => root.filterKey(event)
                Keys.onReturnPressed: event => root.filterKey(event)
                Keys.onEnterPressed: event => root.filterKey(event)
                Keys.onEscapePressed: event => root.filterKey(event)
            }
            Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
        }
        background: Rectangle {
            radius: root.theme.widgetRadius
            color: root.theme.panelSurface
            border.width: root.theme.borderWidth
            border.color: root.theme.outline
        }
    }
}
