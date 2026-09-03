import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../Components"

PanelWindow {
    id: root

    required property var modelData
    required property var theme
    property bool open: false
    // "applications" or "clipboard". The two views are peers: applications come
    // from DesktopEntries and are always current, while the clipboard is read
    // from cliphist once per open, so they refresh independently.
    property string mode: "applications"
    property string searchText: ""
    property int selectedIndex: 0
    property var clipboardEntries: []
    property bool clipboardAvailable: true
    readonly property var applicationEntries: DesktopEntries.applications
        ? DesktopEntries.applications.values
        : []
    readonly property bool clipboardMode: root.mode === "clipboard"
    readonly property var modes: [
        { "id": "applications", "label": "APPLICATIONS" },
        { "id": "clipboard", "label": "CLIPBOARD" }
    ]
    readonly property var results: root.clipboardMode
        ? root.filterClipboard(root.searchText)
        : root.rankApplications(root.searchText)

    signal dismissed
    signal modeRequested(string mode)

    screen: modelData
    visible: open
    color: "transparent"
    exclusiveZone: 0
    surfaceFormat.opaque: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "blankweave-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    function normalized(value) {
        return String(value || "").toLowerCase().trim()
    }

    function favoriteRank(entry) {
        const preferred = [
            "zen", "firefox", "com.mitchellh.ghostty", "thunar", "dev.zed.zed",
            "t3code", "obsidian", "org.pulseaudio.pavucontrol", "blueman-manager", "steam"
        ]
        const id = root.normalized(entry.id).replace(/\.desktop$/, "")
        for (let index = 0; index < preferred.length; index++) {
            if (id === preferred[index])
                return index
        }
        return 100
    }

    function applicationScore(entry, query) {
        const name = root.normalized(entry.name)
        const genericName = root.normalized(entry.genericName)
        const id = root.normalized(entry.id)
        const comment = root.normalized(entry.comment)
        const keywords = root.normalized((entry.keywords || []).join(" "))
        if (!query)
            return root.favoriteRank(entry) * 1000 + name.charCodeAt(0)

        const terms = query.split(/\s+/).filter(term => term !== "")
        const haystack = [name, genericName, id, comment, keywords].join(" ")
        for (let index = 0; index < terms.length; index++) {
            if (!haystack.includes(terms[index]))
                return -1
        }
        if (name === query) return 0
        if (name.startsWith(query)) return 10
        if (id.startsWith(query)) return 20
        if (name.includes(query)) return 30
        if (genericName.includes(query)) return 40
        if (id.includes(query)) return 50
        return 60
    }

    function rankApplications(value) {
        const query = root.normalized(value)
        const ranked = []
        const entries = root.applicationEntries || []
        for (let index = 0; index < entries.length; index++) {
            const entry = entries[index]
            if (!entry || entry.noDisplay || !String(entry.name || ""))
                continue
            const score = root.applicationScore(entry, query)
            if (score >= 0)
                ranked.push({ "entry": entry, "score": score })
        }
        ranked.sort((left, right) => {
            if (left.score !== right.score)
                return left.score - right.score
            return String(left.entry.name).localeCompare(String(right.entry.name))
        })
        return ranked.map(item => item.entry)
    }

    // `cliphist list` emits "<id>\t<single-line preview>", most recent first,
    // and describes anything unprintable as "[[ binary data … ]]".
    function parseClipboard(output) {
        const rows = []
        const lines = String(output || "").split("\n")
        for (let index = 0; index < lines.length; index++) {
            const line = lines[index]
            const separator = line.indexOf("\t")
            if (separator <= 0)
                continue
            const preview = line.slice(separator + 1)
            rows.push({
                "clipboardId": line.slice(0, separator),
                "preview": preview,
                "binary": preview.startsWith("[[ binary data")
            })
        }
        return rows
    }

    // Recency is the clipboard's ordering, so filtering only narrows the list
    // rather than re-ranking it the way application search does.
    function filterClipboard(value) {
        const query = root.normalized(value)
        const rows = root.clipboardEntries || []
        if (!query)
            return rows
        const terms = query.split(/\s+/).filter(term => term !== "")
        return rows.filter(row => {
            const haystack = root.normalized(row.preview)
            return terms.every(term => haystack.includes(term))
        })
    }

    function rowTitle(item) {
        if (!item)
            return ""
        if (root.clipboardMode)
            return String(item.preview || "")
        return String(item.name || "Application")
    }

    function rowSubtitle(item) {
        if (!item)
            return ""
        if (root.clipboardMode)
            return item.binary ? "Binary clipboard entry" : ""
        return String(item.genericName || item.comment || "")
    }

    function clampSelection(value) {
        if (root.results.length === 0)
            return 0
        return Math.max(0, Math.min(root.results.length - 1, value))
    }

    function moveSelection(offset) {
        root.selectedIndex = root.clampSelection(root.selectedIndex + offset)
        Qt.callLater(() => resultList.positionViewAtIndex(
            root.selectedIndex,
            ListView.Contain
        ))
    }

    function activate(item) {
        if (!item)
            return
        root.dismissed()
        if (root.clipboardMode) {
            // The id is passed as an argument rather than spliced into the
            // shell string, so a preview can never become shell syntax.
            clipboardCopy.command = [
                "sh", "-c", 'cliphist decode "$1" | wl-copy', "sh",
                String(item.clipboardId)
            ]
            clipboardCopy.running = true
            return
        }
        Qt.callLater(() => item.execute())
    }

    function closeLauncher() {
        root.dismissed()
    }

    function selectMode(next) {
        if (next === root.mode)
            return
        root.modeRequested(next)
    }

    function cycleMode(offset) {
        const index = root.modes.findIndex(item => item.id === root.mode)
        const count = root.modes.length
        root.selectMode(root.modes[(index + offset + count) % count].id)
    }

    // Reads root.mode rather than clipboardMode because this also runs from
    // onModeChanged, where the derived binding may not have re-evaluated yet.
    function refresh() {
        searchText = ""
        selectedIndex = 0
        if (root.mode === "clipboard" && !clipboardQuery.running) {
            root.clipboardEntries = []
            clipboardQuery.running = true
        }
        Qt.callLater(() => searchField.forceActiveFocus())
    }

    onOpenChanged: if (open) root.refresh()
    onModeChanged: if (open) root.refresh()

    Process {
        id: clipboardQuery

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.clipboardEntries = root.parseClipboard(text)
        }
        onExited: (exitCode, exitStatus) => {
            root.clipboardAvailable = exitCode === 0
        }
    }

    Process {
        id: clipboardCopy
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeLauncher()
        }
    }

    Rectangle {
        id: launcherSurface

        anchors.centerIn: parent
        width: Math.min(620, root.width - 48)
        height: Math.min(680, root.height - 64)
        color: root.theme.panelSurface
        radius: root.theme.panelRadius
        border.width: 1
        border.color: root.theme.outlineStrong

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30

                    GridLayout {
                        anchors.centerIn: parent
                        columns: 2
                        columnSpacing: 3
                        rowSpacing: 3

                        Repeater {
                            model: 4

                            Rectangle {
                                required property int index
                                Layout.preferredWidth: 8
                                Layout.preferredHeight: 8
                                radius: 2
                                color: index === 0 || index === 3
                                    ? root.theme.accentBright
                                    : root.theme.divider
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "LAUNCHER"
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.textSize + 2
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        renderType: Text.NativeRendering
                    }

                    Text {
                        text: {
                            if (root.searchText.trim() !== "")
                                return root.results.length + (root.clipboardMode
                                    ? " matching entries"
                                    : " matching applications")
                            if (root.clipboardMode)
                                return "Recent first · " + root.clipboardEntries.length + " entries"
                            return "Quick launch · " + root.applicationEntries.length + " installed"
                        }
                        color: root.theme.textMuted
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.microTextSize
                        renderType: Text.NativeRendering
                    }
                }

                Item { Layout.fillWidth: true }

                // The only two keys here that are not already obvious from a
                // search list, kept as legends rather than a hint row.
                Text {
                    text: "CTRL+TAB   ESC"
                    color: root.theme.textMuted
                    font.family: root.theme.monoFontFamily
                    font.pixelSize: root.theme.microTextSize
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }
            }

            ControlTabs {
                theme: root.theme
                currentId: root.mode
                tabs: root.modes
                onSelected: tabId => root.selectMode(tabId)
            }

            TextField {
                id: searchField

                Layout.fillWidth: true
                Layout.preferredHeight: 46
                leftPadding: 42
                rightPadding: 14
                placeholderText: root.clipboardMode
                    ? "Search clipboard history"
                    : "Search applications"
                text: root.searchText
                color: root.theme.text
                placeholderTextColor: root.theme.textMuted
                selectionColor: root.theme.accent
                selectedTextColor: root.theme.surfaceRaised
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize + 1
                renderType: Text.NativeRendering

                onTextEdited: {
                    root.searchText = text
                    root.selectedIndex = 0
                }

                onAccepted: {
                    if (root.results.length > 0)
                        root.activate(root.results[root.selectedIndex])
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.closeLauncher()
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Down) {
                        root.moveSelection(1)
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Up) {
                        root.moveSelection(-1)
                        event.accepted = true
                    }
                    // Qt delivers Shift+Tab as Key_Backtab, so both keys have
                    // to be recognised for the reverse direction to work.
                    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        const reverse = event.key === Qt.Key_Backtab
                            || (event.modifiers & Qt.ShiftModifier)
                        const direction = reverse ? -1 : 1
                        if (event.modifiers & Qt.ControlModifier)
                            root.cycleMode(direction)
                        else
                            root.moveSelection(direction)
                        event.accepted = true
                    }
                }

                background: Rectangle {
                    color: searchField.activeFocus
                        ? root.theme.accentSurface
                        : "transparent"
                    radius: root.theme.widgetRadius
                    border.width: 1
                    border.color: searchField.activeFocus
                        ? root.theme.accentBright
                        : root.theme.outlineStrong
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    color: root.theme.accentBright
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.controlIconSize
                    renderType: Text.NativeRendering
                }
            }

            Text {
                Layout.fillWidth: true
                text: {
                    if (root.searchText.trim() !== "")
                        return root.results.length + " RESULTS"
                    return root.clipboardMode
                        ? "CLIPBOARD HISTORY · NEWEST FIRST"
                        : "ALL APPLICATIONS · FAVOURITES FIRST"
                }
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.microTextSize
                font.weight: Font.DemiBold
                font.letterSpacing: 1.1
                renderType: Text.NativeRendering
            }

            ListView {
                id: resultList

                visible: root.results.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.results
                currentIndex: root.selectedIndex
                clip: true
                spacing: 5
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                highlightMoveDuration: 0

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 4

                    contentItem: Rectangle {
                        implicitWidth: 2
                        radius: width / 2
                        color: root.theme.accentBright
                        opacity: 0.72
                    }
                }

                delegate: Item {
                        id: resultCard

                        required property int index
                        required property var modelData
                        readonly property bool selected: index === root.selectedIndex

                        width: resultList.width - 10
                        height: 50

                        Rectangle {
                            anchors.fill: parent
                            radius: root.theme.widgetRadius
                            color: resultCard.selected
                                ? root.theme.accentSurface
                                : (resultMouse.containsMouse ? root.theme.surfaceHover : "transparent")
                            border.width: resultCard.selected || resultMouse.containsMouse ? 1 : 0
                            border.color: resultCard.selected
                                ? root.theme.accentBright
                                : root.theme.outline
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: resultCard.selected ? 30 : 14
                            radius: 1
                            color: resultCard.selected
                                ? root.theme.accentBright
                                : root.theme.divider

                            Behavior on height { NumberAnimation { duration: 130 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 11

                            IconImage {
                                visible: !root.clipboardMode
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                source: root.clipboardMode
                                    ? ""
                                    : Quickshell.iconPath(
                                        String(resultCard.modelData.icon || ""),
                                        "application-x-executable"
                                    )
                                mipmap: true
                            }

                            Text {
                                visible: root.clipboardMode
                                Layout.preferredWidth: 30
                                horizontalAlignment: Text.AlignHCenter
                                text: resultCard.modelData.binary ? "󰋩" : "󰅌"
                                color: resultCard.selected
                                    ? root.theme.accentBright
                                    : root.theme.textMuted
                                font.family: root.theme.iconFontFamily
                                font.pixelSize: root.theme.controlIconSize
                                renderType: Text.NativeRendering
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: root.rowTitle(resultCard.modelData)
                                    color: resultCard.selected
                                        ? root.theme.accentBright
                                        : root.theme.text
                                    elide: Text.ElideRight
                                    font.family: root.clipboardMode
                                        ? root.theme.monoFontFamily
                                        : root.theme.fontFamily
                                    font.pixelSize: root.theme.smallTextSize
                                    font.weight: root.clipboardMode ? Font.Normal : Font.DemiBold
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    visible: text !== ""
                                    Layout.fillWidth: true
                                    text: root.rowSubtitle(resultCard.modelData)
                                    color: root.theme.textMuted
                                    elide: Text.ElideRight
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.microTextSize
                                    renderType: Text.NativeRendering
                                }
                            }

                            Text {
                                visible: resultCard.selected
                                text: root.clipboardMode ? "COPY" : "ENTER"
                                color: root.theme.accentBright
                                font.family: root.theme.monoFontFamily
                                font.pixelSize: root.theme.microTextSize
                                font.weight: Font.DemiBold
                                renderType: Text.NativeRendering
                            }
                        }

                        MouseArea {
                            id: resultMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = resultCard.index
                            onClicked: root.activate(resultCard.modelData)
                        }
                }
            }

            ColumnLayout {
                visible: root.results.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    text: root.clipboardMode ? "󰅌" : "󰍉"
                    color: root.theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.heroIconSize + 4
                    renderType: Text.NativeRendering
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!root.clipboardMode)
                            return "No matching applications"
                        if (!root.clipboardAvailable)
                            return "Clipboard history unavailable"
                        return root.searchText.trim() === ""
                            ? "Clipboard history is empty"
                            : "No matching entries"
                    }
                    color: root.theme.text
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.smallTextSize
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!root.clipboardMode)
                            return "Try another name, category, or keyword."
                        if (!root.clipboardAvailable)
                            return "cliphist is not running or returned an error."
                        return "Copy something and it will appear here."
                    }
                    color: root.theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.microTextSize
                    renderType: Text.NativeRendering
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
