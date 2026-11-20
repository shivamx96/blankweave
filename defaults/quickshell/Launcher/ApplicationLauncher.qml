import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../Services/LauncherUsage.js" as Usage
import "../Components"
import "Launch.js" as Launch
import "Clipboard.js" as Clipboard
import "../Settings/Catalog.js" as Catalog
import "../Services/PowerActions.js" as PowerActions

PanelWindow {
    id: root

    required property LauncherSession session
    readonly property var targetScreen: session.targetScreen
    required property var theme
    readonly property bool open: session.open
    // "applications" or "clipboard". The two views are peers: applications come
    // from DesktopEntries and are always current, while the clipboard is read
    // from cliphist once per open, so they refresh independently.
    readonly property string mode: session.mode
    property var clipboardEntries: []
    property bool clipboardAvailable: true
    property bool clipboardLoaded: false
    readonly property bool clipboardLoading: clipboardQuery.running
    readonly property bool showEmpty: Clipboard.showEmpty(root.results.length,
        root.clipboardMode, root.clipboardLoaded, root.clipboardLoading)
    property int deletionIndex: -1
    property var runClipboardMutation: command => {
        clipboardMutation.command = command
        clipboardMutation.running = true
    }
    readonly property var applicationEntries: DesktopEntries.applications
        ? DesktopEntries.applications.values
        : []
    readonly property bool clipboardMode: root.mode === "clipboard"
    readonly property var modes: [
        { "id": "applications", "label": "APPLICATIONS" },
        { "id": "clipboard", "label": "CLIPBOARD" }
    ]
    readonly property var results: root.clipboardMode
        ? root.filterClipboard(root.session.searchText)
        : root.rankApplications(root.session.searchText)

    // Injectable executor keeps isolated tests from running desktop actions.
    property var executeCommand: command => Quickshell.execDetached(command)
    property string armedAction: ""
    property bool automaticSignIn: true
    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/blankweave/shell"
    readonly property var systemActions: [
        {id: "lock", name: "Lock", icon: "󰌾", command: PowerActions.lockCommand()},
        {id: "suspend", name: "Suspend", icon: "󰒲", command: PowerActions.suspendCommand()},
        {id: "restart", name: "Restart", icon: "󰜉", guarded: true, command: PowerActions.restartCommand()},
        {id: "shutdown", name: "Shut down", icon: "󰐥", guarded: true, command: PowerActions.shutdownCommand()},
        {id: "logout", name: PowerActions.exitLabel(automaticSignIn), icon: "󰍃", guarded: true, command: PowerActions.exitCommand()},
        {id: "theme-toggle", name: "Toggle dark mode", icon: "󰖔", command: PowerActions.themeCommand(shellDir)},
        {id: "dnd-toggle", name: "Toggle Do Not Disturb", icon: "󰂛", command: PowerActions.dndCommand(shellDir)}
    ]
    FileView {
        path: "/etc/blankweave/signin.conf"
        watchChanges: true
        printErrors: false
        onLoaded: root.automaticSignIn = text().trim() !== "no"
        onLoadFailed: root.automaticSignIn = true
        onFileChanged: reload()
    }
    onOpenChanged: { armedAction = ""; lastPointer = Qt.point(-1, -1) }
    onArmedActionChanged: {
        if (armedAction === "clipboard-clear") clearTimeout.restart()
        else clearTimeout.stop()
    }
    Timer { id: clearTimeout; interval: 5000; onTriggered: root.armedAction = "" }
    signal settingRequested(string target)
    signal dismissed
    signal modeRequested(string mode)

    screen: targetScreen
    visible: open && targetScreen !== null
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

    property var usage: null
    property point lastPointer: Qt.point(-1, -1)
    function pointerMoved(x, y) {
        const moved = lastPointer.x >= 0 && (lastPointer.x !== x || lastPointer.y !== y)
        lastPointer = Qt.point(x, y)
        return moved
    }
    function pointerRow(x, y, index) {
        if (pointerMoved(x, y) && index >= 0) root.session.selectedIndex = index
    }
    HoverHandler {
        onPointChanged: {
            const p = point.position
            const local = resultList.mapFromItem(root, p.x, p.y)
            if (local.x < 0 || local.x >= resultList.width || local.y < 0 || local.y >= resultList.height) { root.pointerRow(p.x, p.y, -1); return }
            const index = resultList.indexAt(local.x + resultList.contentX, local.y + resultList.contentY)
            root.pointerRow(p.x, p.y, index)
        }
    }

    function applicationScore(entry, query) {
        const name = root.normalized(entry.name)
        const genericName = root.normalized(entry.genericName)
        const id = root.normalized(entry.id)
        const comment = root.normalized(entry.comment)
        const keywords = root.normalized((entry.keywords || []).join(" "))
        if (!query)
            return usage && usage.history[entry.id]
                ? -Usage.score(usage.history[entry.id], usage.referenceTime)
                : Usage.neutral(entry)

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
            if (!query || score >= 0)
                ranked.push({ "entry": entry, "score": score })
        }
        if (query) {
            // Preserve Catalog's own relevance ordering within Settings results.
            Catalog.searchSettings(query).forEach(result => {
                const page = Catalog.pages.find(page => page.id === result.pageId)
                const entry = {id: result.id, target: result.pageId + "/" + result.id, name: result.title, kind: "setting",
                    icon: "󰒓", genericName: page.title}
                ranked.push({entry: entry, score: 100 + result.score})
            })
            root.systemActions.forEach(action => {
                const score = root.applicationScore(action, query)
                if (!query || score >= 0) ranked.push({entry: Object.assign({kind: "system"}, action), score: 200 + score})
            })
        }
        ranked.sort((left, right) => {
            if (left.score !== right.score)
                return left.score - right.score
            return String(left.entry.name).localeCompare(String(right.entry.name))
                || String(left.entry.id).localeCompare(String(right.entry.id))
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
        if (item.kind === "system" && root.armedAction === item.id)
            return "Press Enter again to " + item.name.toLowerCase()
        if (item.id === "dnd-toggle") return "Critical alerts still appear"
        return String(item.genericName || item.comment || "")
    }

    function clampSelection(value) {
        if (root.results.length === 0)
            return 0
        return Math.max(0, Math.min(root.results.length - 1, value))
    }

    function moveSelection(offset) {
        root.session.selectedIndex = root.clampSelection(root.session.selectedIndex + offset)
        Qt.callLater(() => resultList.positionViewAtIndex(
            root.session.selectedIndex,
            ListView.Contain
        ))
    }

    function activate(item) {
        if (!item)
            return
        if (item.kind === "system") {
            if (item.guarded && root.armedAction !== item.id) {
                root.armedAction = item.id
                return
            }
            const command = item.command
            root.armedAction = ""
            root.dismissed()
            root.executeCommand(command)
            return
        }
        if (item.kind === "setting") {
            root.settingRequested(item.target)
            return
        }
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
        Qt.callLater(() => {
            Launch.activate(item, command => Quickshell.execDetached(command))
            if (root.usage) root.usage.record(String(item.id))
        })
    }

    function closeLauncher() {
        root.armedAction = ""
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

    // The session signal can precede re-evaluation of this window's bindings.
    // Read the authoritative mode directly when starting a clipboard query.
    function refresh() {
        if (root.session.mode === "clipboard" && !clipboardQuery.running) {
            clipboardQuery.running = true
        }
        Qt.callLater(() => searchField.forceActiveFocus())
    }

    function canDeleteClipboard(cursor, length, selectionStart, selectionEnd) {
        return root.clipboardMode && Clipboard.canDelete(cursor, length, selectionStart, selectionEnd)
    }

    function deleteClipboard() {
        if (!root.clipboardMode || clipboardMutation.running || clipboardQuery.running) return
        const item = root.results[root.session.selectedIndex]
        if (!item) return
        root.armedAction = ""
        root.deletionIndex = root.session.selectedIndex
        root.runClipboardMutation(["sh", "-c", 'cliphist delete "$1"', "sh", String(item.clipboardId)])
    }

    function clearClipboard() {
        if (!root.clipboardMode || clipboardMutation.running || clipboardQuery.running || !root.clipboardEntries.length) return
        if (root.armedAction !== "clipboard-clear") {
            root.armedAction = "clipboard-clear"
            return
        }
        root.armedAction = ""
        root.deletionIndex = 0
        root.runClipboardMutation(["cliphist", "wipe"])
    }

    function completeClipboardLoad(text) {
        root.clipboardEntries = root.parseClipboard(text)
        root.clipboardLoaded = true
        if (root.deletionIndex >= 0) {
            root.session.selectedIndex = root.clampSelection(root.deletionIndex)
            root.deletionIndex = -1
        } else root.session.selectedIndex = root.clampSelection(root.session.selectedIndex)
    }

    Process {
        id: clipboardMutation
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.refresh()
            else root.deletionIndex = -1
        }
    }

    Connections {
        target: root.session
        function onRefreshRequested() { root.refresh() }
        function onSearchTextChanged() { root.armedAction = "" }
        function onSelectedIndexChanged() { root.armedAction = "" }
        function onModeChanged() { root.armedAction = "" }
    }
    // Changing a PanelWindow's screen can recreate its native surface. Keep
    // the QML search state and restore focus without starting a new query.
    onTargetScreenChanged: if (open && targetScreen !== null) Qt.callLater(() => searchField.forceActiveFocus())

    Process {
        id: clipboardQuery

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.completeClipboardLoad(text)
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

    ThemeSurface {
        surfaceTheme: root.theme
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
                            if (root.session.searchText.trim() !== "")
                                return root.results.length + (root.clipboardMode
                                    ? " matching entries"
                                    : " matching results")
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
                    : "Search applications, settings, and actions"
                text: root.session.searchText
                color: root.theme.text
                placeholderTextColor: root.theme.textMuted
                selectionColor: root.theme.accentBright
                selectedTextColor: root.theme.surfaceRaised
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize + 1
                renderType: Text.NativeRendering

                onTextEdited: {
                    root.session.searchText = text
                    root.session.selectedIndex = 0
                }

                onAccepted: {
                    if (root.results.length > 0)
                        root.activate(root.results[root.session.selectedIndex])
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.closeLauncher()
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Delete
                        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                        && root.canDeleteClipboard(
                        searchField.cursorPosition, searchField.length,
                        searchField.selectionStart, searchField.selectionEnd)) {
                        root.deleteClipboard()
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
                    if (root.session.searchText.trim() !== "")
                        return root.results.length + " RESULTS"
                    return root.clipboardMode
                        ? "CLIPBOARD HISTORY · NEWEST FIRST"
                        : "ALL APPLICATIONS · RECENTLY USED FIRST"
                }
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.microTextSize
                font.weight: Font.DemiBold
                font.letterSpacing: 1.1
                renderType: Text.NativeRendering
            }

            RowLayout {
                visible: root.clipboardMode
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "ENTER copy · DEL / SHIFT+DEL delete at query end"
                    color: root.theme.textMuted
                    font.family: root.theme.monoFontFamily
                    font.pixelSize: root.theme.microTextSize
                }
                Button {
                    text: root.armedAction === "clipboard-clear"
                        ? "Confirm clear " + root.clipboardEntries.length + " entries" : "Clear history"
                    enabled: root.clipboardEntries.length > 0 && !clipboardMutation.running && !clipboardQuery.running
                    onClicked: root.clearClipboard()
                    onActiveFocusChanged: if (!activeFocus && root.armedAction === "clipboard-clear") root.armedAction = ""
                }
            }

            ListView {
                id: resultList

                visible: root.results.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.results
                currentIndex: root.session.selectedIndex
                clip: true
                spacing: 5
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                highlightMoveDuration: 0

                ScrollBar.vertical: ScrollBar {
                    background: Rectangle { color: "transparent" }
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
                        readonly property bool selected: index === root.session.selectedIndex

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

                            Behavior on height { NumberAnimation { duration: Math.round(root.theme.motionDuration * 130 / 150) } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 11

                            IconImage {
                                visible: !root.clipboardMode && !resultCard.modelData.kind
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
                                visible: root.clipboardMode || Boolean(resultCard.modelData.kind)
                                Layout.preferredWidth: 30
                                horizontalAlignment: Text.AlignHCenter
                                text: resultCard.modelData.icon || (resultCard.modelData.binary ? "󰋩" : "󰅌")
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
                            // Selection follows the root pointer tracker, never hover entry.
                            onClicked: root.activate(resultCard.modelData)
                        }
                }
            }

            ColumnLayout {
                visible: root.showEmpty
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
                        return root.session.searchText.trim() === ""
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
