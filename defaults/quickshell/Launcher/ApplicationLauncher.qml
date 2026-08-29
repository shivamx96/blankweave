import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: root

    required property var modelData
    required property var theme
    property bool open: false
    property string searchText: ""
    property int selectedIndex: 0
    readonly property var applicationEntries: DesktopEntries.applications
        ? DesktopEntries.applications.values
        : []
    readonly property var applicationResults: root.rankApplications(root.searchText)

    signal dismissed

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

    WlrLayershell.namespace: "hyprarch-launcher"
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

    function clampSelection(value) {
        if (root.applicationResults.length === 0)
            return 0
        return Math.max(0, Math.min(root.applicationResults.length - 1, value))
    }

    function moveSelection(offset) {
        root.selectedIndex = root.clampSelection(root.selectedIndex + offset)
        Qt.callLater(() => applicationList.positionViewAtIndex(
            root.selectedIndex,
            ListView.Contain
        ))
    }

    function launch(entry) {
        if (!entry)
            return
        root.dismissed()
        Qt.callLater(() => entry.execute())
    }

    function closeLauncher() {
        root.dismissed()
    }

    onOpenChanged: {
        if (open) {
            searchText = ""
            selectedIndex = 0
            Qt.callLater(() => searchField.forceActiveFocus())
        }
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
        border.width: 1
        border.color: root.theme.outlineStrong

        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            width: 110
            height: 2
            color: root.theme.accentBright
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            width: 34
            height: 2
            color: root.theme.divider
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 110
            height: 2
            color: root.theme.accentBright
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 34
            height: 2
            color: root.theme.divider
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
                        text: "APPLICATIONS"
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.textSize + 2
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        renderType: Text.NativeRendering
                    }

                    Text {
                        text: root.searchText.trim() === ""
                            ? "Quick launch · " + root.applicationEntries.length + " installed"
                            : root.applicationResults.length + " matching applications"
                        color: root.theme.textMuted
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.microTextSize
                        renderType: Text.NativeRendering
                    }
                }

                Text {
                    text: "ESC"
                    color: root.theme.textMuted
                    font.family: root.theme.monoFontFamily
                    font.pixelSize: root.theme.microTextSize
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }
            }

            TextField {
                id: searchField

                Layout.fillWidth: true
                Layout.preferredHeight: 46
                leftPadding: 42
                rightPadding: 14
                placeholderText: "Search applications"
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
                    if (root.applicationResults.length > 0)
                        root.launch(root.applicationResults[root.selectedIndex])
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
                    else if (event.key === Qt.Key_Tab) {
                        const direction = event.modifiers & Qt.ShiftModifier ? -1 : 1
                        root.moveSelection(direction)
                        event.accepted = true
                    }
                }

                background: Rectangle {
                    color: searchField.activeFocus
                        ? root.theme.accentSurface
                        : "transparent"
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
                text: root.searchText.trim() === ""
                    ? "ALL APPLICATIONS · FAVOURITES FIRST"
                    : root.applicationResults.length + " RESULTS"
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.microTextSize
                font.weight: Font.DemiBold
                font.letterSpacing: 1.1
                renderType: Text.NativeRendering
            }

            ListView {
                id: applicationList

                visible: root.applicationResults.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.applicationResults
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
                        color: root.theme.accentBright
                        opacity: 0.72
                    }
                }

                delegate: Item {
                        id: applicationCard

                        required property int index
                        required property var modelData
                        readonly property bool selected: index === root.selectedIndex

                        width: applicationList.width - 10
                        height: 50

                        Rectangle {
                            anchors.fill: parent
                            color: applicationCard.selected
                                ? root.theme.accentSurface
                                : (applicationMouse.containsMouse ? root.theme.surfaceHover : "transparent")
                            border.width: applicationCard.selected || applicationMouse.containsMouse ? 1 : 0
                            border.color: applicationCard.selected
                                ? root.theme.accentBright
                                : root.theme.outline
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: applicationCard.selected ? 30 : 14
                            color: applicationCard.selected
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
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                source: Quickshell.iconPath(
                                    String(applicationCard.modelData.icon || ""),
                                    "application-x-executable"
                                )
                                mipmap: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: String(applicationCard.modelData.name || "Application")
                                    color: applicationCard.selected
                                        ? root.theme.accentBright
                                        : root.theme.text
                                    elide: Text.ElideRight
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.smallTextSize
                                    font.weight: Font.DemiBold
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    visible: text !== ""
                                    Layout.fillWidth: true
                                    text: String(applicationCard.modelData.genericName
                                        || applicationCard.modelData.comment || "")
                                    color: root.theme.textMuted
                                    elide: Text.ElideRight
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.microTextSize
                                    renderType: Text.NativeRendering
                                }
                            }

                            Text {
                                visible: applicationCard.selected
                                text: "ENTER"
                                color: root.theme.accentBright
                                font.family: root.theme.monoFontFamily
                                font.pixelSize: root.theme.microTextSize
                                font.weight: Font.DemiBold
                                renderType: Text.NativeRendering
                            }
                        }

                        MouseArea {
                            id: applicationMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = applicationCard.index
                            onClicked: root.launch(applicationCard.modelData)
                        }
                }
            }

            ColumnLayout {
                visible: root.applicationResults.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    text: "󰍉"
                    color: root.theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.heroIconSize + 4
                    renderType: Text.NativeRendering
                }

                Text {
                    Layout.fillWidth: true
                    text: "No matching applications"
                    color: root.theme.text
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.smallTextSize
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Text {
                    Layout.fillWidth: true
                    text: "Try another name, category, or keyword."
                    color: root.theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.microTextSize
                    renderType: Text.NativeRendering
                }

                Item { Layout.fillHeight: true }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.theme.outline
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "↑ ↓  NAVIGATE     TAB  STEP     ENTER  OPEN"
                    color: root.theme.textMuted
                    font.family: root.theme.monoFontFamily
                    font.pixelSize: root.theme.microTextSize
                    renderType: Text.NativeRendering
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "HYPRARCH // NATIVE LAUNCHER"
                    color: root.theme.divider
                    font.family: root.theme.monoFontFamily
                    font.pixelSize: root.theme.microTextSize
                    font.letterSpacing: 0.5
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
