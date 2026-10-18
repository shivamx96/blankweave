pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../Components"
import "Catalog.js" as Catalog

Rectangle {
    id: root
    required property var theme
    required property var appearance
    property var displays: null
    property var power: null
    property var battery: null
    property var idle: null
    property var startup: null
    property var wallpaper: null
    property var webapps: null
    property var operations: null
    property var system: null
    property var notifications: null
    property var defaultApps: null
    property var accessibility: null
    property var interfaceSettings: null
    property var shortcuts: null
    property var keyboard: null
    property var pointer: null
    property var sound: null
    property var voice: null
    property var systemSounds: null
    property var wireless: null
    property var connections: null
    property var wifi: null
    property var bluetooth: null
    property string selectedPage: "appearance"
    readonly property var results: Catalog.pages
    readonly property bool searching: search.text.trim().length > 0
    readonly property var searchResults: Catalog.searchSettings(search.text)
    property string highlightedSetting: ""
    property int searchIndex: 0
    property bool followSearchTarget: false
    readonly property var page: results.find(entry => entry.id === selectedPage) || results[0] || null
    readonly property bool narrow: width < 800
    signal copyRequested(string text)
    signal closeRequested

    color: theme.canvas

    function focusSearch() { search.forceActiveFocus(); search.selectAll() }
    function openSetting(id) {
        for (const page of Catalog.pages) {
            if (page.groups.some(group => group.rows.some(row => row.id === id))) {
                showResult({id: id, pageId: page.id})
                return
            }
        }
    }

    function showResult(result) {
        if (!result) return
        selectedPage = result.pageId
        search.clear()
        highlightedSetting = result.id
        followSearchTarget = true
        jumpTimer.restart()
    }
    function rowForSetting(id) {
        for (let g = 0; g < groups.count; g++) {
            const group = groups.itemAt(g)
            for (let r = 0; r < group.rowRepeater.count; r++) {
                const row = group.rowRepeater.itemAt(r)
                if (row.modelData.id === id) return row
            }
        }
        return null
    }
    function focusResult(index) {
        if (!searchResults.length) return
        searchIndex = Math.max(0, Math.min(index, searchResults.length - 1))
        const item = searchRows.itemAt(searchIndex)
        if (item) {
            item.forceActiveFocus()
            const y = item.mapToItem(pageColumn, 0, 0).y
            pageScroll.contentItem.contentY = Math.max(0, Math.min(y - 16,
                pageScroll.contentItem.contentHeight - pageScroll.contentItem.height))
        }
    }
    Timer {
        id: jumpTimer
        interval: 50
        onTriggered: {
            const row = root.rowForSetting(root.highlightedSetting)
            if (!row) return
            pageScroll.contentItem.contentY = Math.max(0, Math.min(row.mapToItem(pageColumn, 0, 0).y - 16,
                pageScroll.contentItem.contentHeight - pageScroll.contentItem.height))
            row.forceActiveFocus()
            highlightTimer.restart()
        }
    }
    Timer { id: highlightTimer; interval: 3500; onTriggered: { root.highlightedSetting = ""; root.followSearchTarget = false } }
    onPageChanged: { followSearchTarget = false; jumpTimer.stop(); highlightTimer.stop(); highlightedSetting = ""; pageScroll.contentItem.contentY = 0 }
    onSearchingChanged: pageScroll.contentItem.contentY = 0
    Connections {
        target: pageScroll.contentItem
        function onContentHeightChanged() {
            if (root.followSearchTarget && root.highlightedSetting) jumpTimer.restart()
        }
        function onMovementStarted() { root.followSearchTarget = false; jumpTimer.stop() }
    }
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
                    font.pixelSize: Math.round(20 * (root.theme.textScale || 1))
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                SettingsTextField {
                    theme: root.theme
                    id: search
                    objectName: "settingsSearch"
                    Layout.preferredWidth: Math.min(280, root.width * 0.36)
                    Layout.preferredHeight: 36
                    placeholderText: "Search settings…"
                    Accessible.name: "Search settings"
                    onTextChanged: { root.followSearchTarget = false; jumpTimer.stop(); highlightTimer.stop(); root.highlightedSetting = ""; root.searchIndex = 0; pageScroll.contentItem.contentY = 0 }
                    onAccepted: root.showResult(root.searchResults[root.searchIndex])
                    Keys.onDownPressed: root.searching ? root.focusResult(0) : categories.forceActiveFocus()
                }
                SettingsButton {
                    theme: root.theme
                    text: "Close"
                    onClicked: root.closeRequested()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.divider }
        SettingsJobsBar {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            theme: root.theme
            service: root.operations
            onSettingRequested: id => root.openSetting(id)
        }

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
                        ScrollBar.vertical: SettingsScrollBar { theme: root.theme }
                        Keys.onReturnPressed: {
                            if (root.results[currentIndex]) { search.clear(); root.selectedPage = root.results[currentIndex].id }
                        }
                        Keys.onSpacePressed: {
                            if (root.results[currentIndex]) { search.clear(); root.selectedPage = root.results[currentIndex].id }
                        }
                        delegate: SettingsButton {
                            id: category
                            required property var modelData
                            required property int index
                            width: categories.width
                            height: root.narrow ? 60 : 46
                            theme: root.theme
                            text: modelData.title
                            selected: !root.searching && root.page !== null && root.page.id === modelData.id
                            Accessible.description: modelData.description
                            onClicked: { search.clear(); root.selectedPage = modelData.id }
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
                                    Layout.preferredWidth: 20
                                    Layout.minimumWidth: 20
                                    Layout.maximumWidth: 20
                                    Layout.alignment: Qt.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: category.modelData.icon
                                    color: category.selected ? root.theme.accentBright : root.theme.textMuted
                                    font.family: root.theme.iconFontFamily
                                    font.pixelSize: 18
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
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
                ScrollBar.vertical: SettingsScrollBar { theme: root.theme }

                ColumnLayout {
                    id: pageColumn
                    width: pageScroll.availableWidth
                    spacing: 20

                    ColumnLayout {
                        visible: root.searching
                        Layout.fillWidth: true
                        Layout.margins: root.narrow ? 20 : 32
                        spacing: 12
                        Text {
                            Layout.fillWidth: true
                            text: root.searchResults.length ? "Search results" : "No settings found"
                            color: root.theme.text; font.family: root.theme.fontFamily
                            font.pixelSize: Math.round(28 * (root.theme.textScale || 1))
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.searchResults.length ? root.searchResults.length + (root.searchResults.length === 1 ? " matching setting" : " matching settings")
                                : "Try another word, such as keyboard, backups, or theme."
                            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
                            wrapMode: Text.WordWrap
                        }
                        Repeater {
                            id: searchRows
                            model: root.searching ? root.searchResults : []
                            delegate: SettingsButton {
                                id: resultButton
                                required property var modelData
                                required property int index
                                objectName: "searchResult_" + modelData.id
                                Layout.fillWidth: true
                                implicitHeight: resultLabels.implicitHeight + 24
                                theme: root.theme
                                text: modelData.title
                                padding: 12
                                Accessible.name: modelData.title + ". " + modelData.breadcrumb
                                Accessible.description: modelData.description
                                onClicked: root.showResult(modelData)
                                Keys.onDownPressed: root.focusResult(index + 1)
                                Keys.onUpPressed: index === 0 ? search.forceActiveFocus() : root.focusResult(index - 1)
                                Keys.onReturnPressed: root.showResult(modelData)
                                contentItem: ColumnLayout {
                                    id: resultLabels
                                    spacing: 4
                                    Text {
                                        Layout.fillWidth: true
                                        text: resultButton.modelData.title
                                        textFormat: Text.PlainText; wrapMode: Text.WordWrap
                                        color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.textSize
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: resultButton.modelData.breadcrumb
                                        textFormat: Text.PlainText; wrapMode: Text.WordWrap
                                        color: root.theme.accentBright; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: resultButton.modelData.description
                                        textFormat: Text.PlainText; wrapMode: Text.WordWrap
                                        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: !root.searching
                        Layout.fillWidth: true
                        Layout.margins: root.narrow ? 20 : 32
                        spacing: 9

                        Text {
                            Layout.fillWidth: true
                            text: root.page ? root.page.title : "No settings found"
                            color: root.theme.text
                            font.family: root.theme.fontFamily
                            font.pixelSize: Math.round(28 * (root.theme.textScale || 1))
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
                                    ? "Theme, color mode, bar widgets, wallpaper, text, and pointer sizes are available."
                                    : root.page && root.page.id === "displays" && root.displays
                                    ? "Mode, mirror, and setup changes have a 20-second preview. Other display changes apply immediately; night light applies to all displays."
                                    : root.page && root.page.id === "sound" && root.sound
                                    ? "Sound controls are available. Changes apply to the selected device or supported apps."
                                    : root.page && root.page.id === "power" && root.power
                                    ? "Power profiles, battery controls, idle timeouts, and hibernation readiness are available."
                                    : root.page && root.page.id === "input" && root.pointer
                                    ? "Input and accessibility controls apply to this session and supported assistive applications."
                                    : root.page && root.page.id === "apps" && root.defaultApps
                                    ? "Manage installed software, supported application permissions, defaults, startup apps, and notifications."
                                    : root.page && root.page.id === "system" && root.system
                                    ? "System changes may require administrator authorization. Device support is detected before offering operations."
                                    : root.page && root.page.id === "network" && root.wifi
                                    ? "Manage connections, private networks, and supported sharing services."
                                    : root.page && root.page.id === "storage" ? "Inspect storage, manage removable drives, and configure supported backup providers."
                                    : "Controls report unavailable services and hardware before changes can be made."
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
                            id: groups
                            model: root.page ? root.page.groups : []
                            delegate: ColumnLayout {
                                id: group
                                property alias rowRepeater: settingsRows
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
                                            id: settingsRows
                                            model: group.modelData.rows
                                            delegate: ColumnLayout {
                                                id: settingGroup
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                spacing: 0
                                                objectName: "settingTarget_" + modelData.id
                                                Accessible.name: modelData.title
                                                Accessible.role: Accessible.Grouping
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 4
                                                    visible: root.highlightedSetting === settingGroup.modelData.id
                                                    color: root.theme.accentBright
                                                    radius: 2
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 18
                                                    Layout.rightMargin: 18
                                                    visible: settingGroup.index > 0
                                                    implicitHeight: 1
                                                    color: root.theme.divider
                                                }
                                                SettingsRow {
                                                    onSettingRequested: id => root.openSetting(id)
                                                    onCopyRequested: text => root.copyRequested(text)
                                                    Layout.fillWidth: true
                                                    theme: root.theme
                                                    setting: settingGroup.modelData
                                                    backend: settingGroup.modelData.kind === "operations" ? (root.operations ? root.operations.provider(settingGroup.modelData.id) : null)
                                                        : settingGroup.modelData.kind === "system-info" ? root.system
                                                        : settingGroup.modelData.kind === "webapps" ? root.webapps
                                                        : settingGroup.modelData.kind === "wallpaper" ? root.wallpaper
                                                        : settingGroup.modelData.kind === "startup" ? root.startup
                                                        : settingGroup.modelData.kind === "notifications" ? root.notifications
                                                        : settingGroup.modelData.kind === "default-apps" ? root.defaultApps
                                                        : settingGroup.modelData.kind === "accessibility" ? root.accessibility
                                                        : settingGroup.modelData.kind === "interface-size" ? root.interfaceSettings
                                                        : settingGroup.modelData.kind === "shortcuts" ? root.shortcuts
                                                        : settingGroup.modelData.kind === "keyboard" ? root.keyboard
                                                        : settingGroup.modelData.kind === "pointer" ? root.pointer
                                                        : settingGroup.modelData.kind === "idle" ? root.idle
                                                        : settingGroup.modelData.kind === "battery-health" ? root.battery
                                                        : ["power-profile", "automatic-power"].includes(settingGroup.modelData.kind) ? root.power
                                                        : ["airplane", "hotspot"].includes(settingGroup.modelData.kind) ? root.wireless
                                                        : settingGroup.modelData.kind === "network" ? root.connections
                                                        : settingGroup.modelData.kind === "bluetooth" ? root.bluetooth
                                                        : settingGroup.modelData.kind === "wifi" ? root.wifi
                                                        : settingGroup.modelData.kind === "system-sounds" ? root.systemSounds
                                                        : settingGroup.modelData.kind === "dictation" ? root.voice
                                                        : root.page && root.page.id === "appearance" ? root.appearance
                                                        : root.page && root.page.id === "displays" ? root.displays
                                                        : root.page && root.page.id === "sound" ? root.sound : null
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
