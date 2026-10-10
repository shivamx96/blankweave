pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Components"
import "Catalog.js" as Catalog

Rectangle {
    id: root
    required property var theme
    required property var appearance
    property var displays: null
    property string selectedPage: "appearance"
    readonly property var results: Catalog.search(search.text)
    readonly property var page: results.find(entry => entry.id === selectedPage) || results[0] || null
    readonly property bool narrow: width < 800
    signal closeRequested

    color: theme.canvas

    function focusSearch() { search.forceActiveFocus(); search.selectAll() }

    onPageChanged: pageScroll.contentItem.contentY = 0
    Connections {
        target: root.displays
        function onPreviewPendingChanged() {
            if (root.displays.previewPending && root.page && root.page.id === "displays")
                pageScroll.contentItem.contentY = 0
        }
    }

    Shortcut { sequence: "Ctrl+F"; onActivated: root.focusSearch() }
    Shortcut { sequence: "Ctrl+W"; onActivated: root.closeRequested() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (search.text) search.clear()
            else root.closeRequested()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: root.theme.panelSurface

            RowLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14
                VectorMark {
                    mark: "blankweave"
                    markColor: root.theme.text
                    accentColor: root.theme.accentBright
                    visualSize: 28
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                }
                Text {
                    text: "Settings"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                TextField {
                    id: search
                    objectName: "settingsSearch"
                    Layout.preferredWidth: Math.min(280, root.width * 0.36)
                    Layout.preferredHeight: 36
                    placeholderText: "Search settings…"
                    Accessible.name: "Search settings"
                    color: root.theme.text
                    placeholderTextColor: root.theme.textMuted
                    selectionColor: root.theme.accentSurface
                    selectedTextColor: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.textSize
                    leftPadding: 12
                    background: Rectangle {
                        color: root.theme.surface
                        radius: root.theme.widgetRadius
                        border.color: search.activeFocus ? root.theme.accentBright : root.theme.outline
                    }
                    onAccepted: {
                        if (root.results.length) {
                            root.selectedPage = root.results[0].id
                            categories.forceActiveFocus()
                        }
                    }
                    Keys.onDownPressed: categories.forceActiveFocus()
                }
                SettingsButton {
                    theme: root.theme
                    text: "Close"
                    onClicked: root.closeRequested()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.divider }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.preferredWidth: root.narrow ? 190 : 238
                Layout.fillHeight: true
                color: root.theme.panelSurface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 16
                    Text {
                        Layout.topMargin: 12
                        Layout.leftMargin: 12
                        text: "YOUR DESKTOP"
                        color: root.theme.textMuted
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.microTextSize
                        font.letterSpacing: 1.5
                    }
                    ListView {
                        id: categories
                        objectName: "settingsCategories"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.results
                        spacing: 5
                        clip: true
                        currentIndex: Math.max(0, root.results.findIndex(entry => entry.id === root.selectedPage))
                        keyNavigationEnabled: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { }
                        Keys.onReturnPressed: {
                            if (root.results[currentIndex]) root.selectedPage = root.results[currentIndex].id
                        }
                        Keys.onSpacePressed: {
                            if (root.results[currentIndex]) root.selectedPage = root.results[currentIndex].id
                        }
                        delegate: SettingsButton {
                            id: category
                            required property var modelData
                            required property int index
                            width: categories.width
                            height: root.narrow ? 60 : 46
                            theme: root.theme
                            text: modelData.title
                            selected: root.page !== null && root.page.id === modelData.id
                            Accessible.description: modelData.description
                            onClicked: root.selectedPage = modelData.id
                            background: Rectangle {
                                radius: root.theme.widgetRadius
                                color: category.selected ? root.theme.accentSurface
                                    : category.hovered ? root.theme.surfaceHover : "transparent"
                                border.width: category.activeFocus || (categories.activeFocus && category.index === categories.currentIndex) ? 1 : 0
                                border.color: root.theme.accentBright
                            }
                            contentItem: RowLayout {
                                spacing: 12
                                Text {
                                    Layout.leftMargin: 8
                                    text: category.modelData.icon
                                    color: category.selected ? root.theme.accentBright : root.theme.textMuted
                                    font.family: root.theme.iconFontFamily
                                    font.pixelSize: 18
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: category.text
                                    color: category.selected ? root.theme.accentBright : root.theme.text
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.textSize
                                    font.weight: category.selected ? Font.DemiBold : Font.Normal
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.margins: 12
                        text: "Blankweave\nA little more your own."
                        color: root.theme.textMuted
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.smallTextSize
                        lineHeight: 1.5
                    }
                }
            }

            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: root.theme.divider }

            ScrollView {
                id: pageScroll
                objectName: "settingsPageScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: pageScroll.availableWidth
                    spacing: 20

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: root.narrow ? 20 : 32
                        spacing: 9

                        Text {
                            Layout.fillWidth: true
                            text: root.page ? root.page.title : "No settings found"
                            color: root.theme.text
                            font.family: root.theme.fontFamily
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.page ? root.page.description : "Try a different word, such as keyboard, backups, or theme."
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.textSize
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            implicitHeight: notice.implicitHeight + 28
                            visible: root.page !== null
                            color: root.theme.accentSurface
                            radius: root.theme.widgetRadius
                            Text {
                                id: notice
                                anchors { fill: parent; margins: 14 }
                                text: root.page && root.page.id === "appearance"
                                    ? "Theme, color mode, and bar changes apply immediately. Other controls are previews."
                                    : root.page && root.page.id === "displays" && root.displays
                                    ? "Scaling and position are saved immediately. Resolution changes have a 20-second preview before saving. Other controls are previews."
                                    : "Preview — changes aren’t applied. These controls show what’s planned; values are examples, not your device’s status."
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.smallTextSize
                                wrapMode: Text.WordWrap
                            }
                        }

                        ColumnLayout {
                            visible: root.page !== null && root.page.id === "appearance"
                            Layout.fillWidth: true
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: root.appearance.busy ? "Updating appearance…"
                                        : root.appearance.error || (root.appearance.ready ? "Connected to your desktop" : "Loading your preferences…")
                                    color: root.appearance.error ? root.theme.warning : root.theme.textMuted
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.smallTextSize
                                    wrapMode: Text.WordWrap
                                    Accessible.role: Accessible.StaticText
                                }
                                SettingsButton {
                                    text: "Refresh"
                                    theme: root.theme
                                    enabled: !root.appearance.busy
                                    onClicked: root.appearance.refresh()
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                visible: root.appearance.systemPending || root.appearance.syncMessage !== ""
                                implicitHeight: systemAppearance.implicitHeight + 28
                                color: root.theme.panelSurface
                                radius: root.theme.widgetRadius
                                border.color: root.theme.outline

                                ColumnLayout {
                                    id: systemAppearance
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    spacing: 10
                                    Text {
                                        text: "System appearance"
                                        color: root.theme.text
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.textSize
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: root.appearance.systemPending
                                        text: root.appearance.pendingDescription
                                            + (root.appearance.syncAvailable
                                                ? " Apply these changes with administrator approval."
                                                : " Update Blankweave to enable system appearance controls.")
                                        color: root.theme.textMuted
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.smallTextSize
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        objectName: "systemAppearanceProgress"
                                        Layout.fillWidth: true
                                        visible: root.appearance.syncMessage !== ""
                                        text: root.appearance.syncMessage
                                        color: root.appearance.syncState === "error" ? root.theme.warning : root.theme.text
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.smallTextSize
                                        wrapMode: Text.WordWrap
                                    }
                                    SettingsButton {
                                        objectName: "applySystemAppearance"
                                        theme: root.theme
                                        visible: root.appearance.systemPending
                                        enabled: root.appearance.ready && root.appearance.syncAvailable && !root.appearance.busy
                                        text: root.appearance.syncing ? "Applying…"
                                            : root.appearance.syncState === "error" ? "Try again…" : "Apply system appearance…"
                                        onClicked: root.appearance.syncSystem()
                                    }
                                }
                            }
                        }

                        Loader {
                            Layout.fillWidth: true
                            active: root.page !== null && root.page.id === "displays" && root.displays !== null
                            visible: active
                            sourceComponent: Component {
                                SettingsDisplaySelector {
                                    theme: root.theme
                                    backend: root.displays
                                }
                            }
                        }

                        Repeater {
                            model: root.page ? root.page.groups : []
                            delegate: ColumnLayout {
                                id: group
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: 12
                                spacing: 10
                                ControlSectionLabel {
                                    theme: root.theme
                                    text: group.modelData.title.toUpperCase()
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: rows.implicitHeight
                                    color: root.theme.panelSurface
                                    radius: root.theme.panelRadius
                                    border.color: root.theme.outline
                                    ColumnLayout {
                                        id: rows
                                        width: parent.width
                                        spacing: 0
                                        Repeater {
                                            model: group.modelData.rows
                                            delegate: ColumnLayout {
                                                id: settingGroup
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 18
                                                    Layout.rightMargin: 18
                                                    visible: settingGroup.index > 0
                                                    implicitHeight: 1
                                                    color: root.theme.divider
                                                }
                                                SettingsRow {
                                                    Layout.fillWidth: true
                                                    theme: root.theme
                                                    setting: settingGroup.modelData
                                                    backend: root.page && root.page.id === "appearance" ? root.appearance
                                                        : root.page && root.page.id === "displays" ? root.displays : null
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
