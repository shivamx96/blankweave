pragma ComponentBehavior: Bound
import QtQuick
import "LegacyErrors.js" as Errors
import QtQuick.Layouts
import "../Components"

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    property bool hotspot: false
    readonly property bool busy: !backend || backend.busy || backend.otherBusy
    readonly property var devices: backend ? backend.devices : []
    readonly property var radioGroups: {
        const radios = backend && backend.airplane ? backend.airplane.radios : []
        const names = {wlan: "Wi-Fi", bluetooth: "Bluetooth", wwan: "Mobile broadband", wimax: "WiMAX", nfc: "NFC", uwb: "Ultra-wideband", gps: "GPS"}
        return Array.from(new Set(radios.map(row => row.type))).map(type => {
            const group = radios.filter(row => row.type === type)
            return {name: names[type] || type, state: group.every(row => row.soft || row.hard)
                ? group.some(row => row.hard) ? "Off · hardware switch" : "Off"
                : group.some(row => row.soft || row.hard) ? "Partly blocked" : "Available"}
        })
    }
    property string selectedPath: ""
    readonly property var selected: devices.find(row => row.path === selectedPath) || null
    property var formTarget: null
    readonly property bool canStart: selected !== null && selected.managed && selected.apCapable && !selected.hotspot
        && [30, 100, 120].includes(selected.state) && backend.network && backend.network.wifiEnabled
        && backend.network.hardwareEnabled && backend.network.sharingAvailable && !backend.airplaneRequested
    spacing: root.theme.spacing("xl")

    function clearSecret() { password.text = ""; formTarget = null }
    function start() {
        if (!canStart || busy || !ssid.text.trim() || password.text.length < 8) return
        const captured = formTarget || selected
        if (!backend.matches(captured, selected)) { clearSecret(); return }
        backend.start(captured, ssid.text, password.text, captured.activePath !== "/")
        clearSecret()
    }
    onSelectedPathChanged: clearSecret()
    onDevicesChanged: {
        if (!devices.some(row => row.path === selectedPath)) selectedPath = devices.length ? devices[0].path : ""
        if (formTarget && !backend.matches(formTarget, devices.find(row => row.path === selectedPath))) clearSecret()
    }
    Connections {
        target: root.backend
        function onActiveChanged() { if (!root.backend.active) root.clearSecret() }
    }
    Component.onDestruction: clearSecret()

    Flow {
        visible: !root.hotspot
        Layout.fillWidth: true
        spacing: root.theme.spacing("md")
        SettingsSwitchRow {
            objectName: "airplaneToggle"
            theme: root.theme
            checked: root.backend !== null && root.backend.radiosBlocked
            busy: Boolean(root.backend && root.backend.busy)
            error: root.backend ? Errors.message(root.backend.error) : ""
            detail: root.backend ? Errors.detail(root.backend.error) : ""
            text: "Airplane mode"
            enabled: !root.busy && root.backend.airplane !== null && root.backend.airplane.radios.length > 0
            onClicked: root.backend.setAirplane(!(root.backend.airplaneRequested || root.backend.radiosBlocked))
        }
        SettingsButton {
            theme: root.theme
            text: "Turn off remaining radios"
            visible: root.backend !== null && root.backend.airplaneRequested && !root.backend.radiosBlocked
            enabled: !root.busy
            onClicked: root.backend.setAirplane(true)
        }
    }
    Text {
        visible: !root.hotspot
        Layout.fillWidth: true
        text: !root.backend || !root.backend.airplane ? (root.backend ? root.backend.radioError : "") || "Reading wireless radios…"
            : !root.backend.airplane.radios.length ? "No wireless radios detected."
            : root.backend.radiosBlocked ? "Wireless radios are blocked. Ethernet remains available."
            : root.backend.airplaneRequested ? "A radio was enabled outside airplane mode. Turn it off again or leave airplane mode."
            : "Turns off Wi-Fi, Bluetooth, and other wireless radios. Turning airplane mode off restores their previous state."
        textFormat: Text.PlainText; wrapMode: Text.WordWrap
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
    }
    Repeater {
        model: !root.hotspot ? root.radioGroups : []
        delegate: Text {
            required property var modelData
            Layout.fillWidth: true
            text: modelData.name + " · " + modelData.state
            textFormat: Text.PlainText; wrapMode: Text.WordWrap
            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
    }
    ColumnLayout {
        visible: root.hotspot
        Layout.fillWidth: true
        SettingsComboBox {
            id: adapterChoice
            objectName: "hotspotAdapter"
            Layout.fillWidth: true
            theme: root.theme
            property var captured: []
            property bool selecting: false
            readonly property var options: selecting ? captured : root.devices
            model: options.map(row => row.interface + (row.name ? " · " + row.name : ""))
            currentIndex: options.findIndex(row => row.path === root.selectedPath)
            enabled: !root.busy && options.length > 0
            onActivated: index => {
                const row = options[index]
                if (row && root.devices.some(current => root.backend.matches(current, row))) root.selectedPath = row.path
            }
            Connections {
                target: adapterChoice.popup
                function onAboutToShow() { adapterChoice.captured = root.devices.slice(); adapterChoice.selecting = true }
                function onClosed() { Qt.callLater(() => { if (!adapterChoice.popup.visible) adapterChoice.selecting = false }) }
            }
        }
        Text {
            Layout.fillWidth: true
            text: !root.backend || !root.backend.network ? (root.backend ? root.backend.networkError : "") || "Reading Wi-Fi adapters…"
                : !root.selected ? "No Wi-Fi adapter detected."
                : root.selected.hotspot ? "Hotspot: " + root.selected.ssid + (root.selected.connected ? " · Active" : " · Starting…")
                : !root.selected.managed ? "This adapter is not managed by NetworkManager."
                : root.backend.airplaneRequested ? "Turn off airplane mode before starting a hotspot."
                : !root.backend.network.hardwareEnabled ? "Wi-Fi is blocked by a hardware switch."
                : !root.backend.network.wifiEnabled ? "Turn on Wi-Fi to start a hotspot."
                : !root.selected.apCapable ? "This adapter does not support a WPA2 hotspot."
                : !root.backend.network.sharingAvailable ? "Hotspot sharing needs dnsmasq and nftables installed."
                : "Share Internet from Ethernet or another adapter. Starting a hotspot replaces the Wi-Fi connection on this adapter."
            textFormat: Text.PlainText; wrapMode: Text.WordWrap
            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        ControlTextField {
            id: ssid
            objectName: "hotspotName"
            Layout.fillWidth: true
            theme: root.theme
            text: "Blankweave"
            placeholderText: "Hotspot name"
            Accessible.name: "Hotspot name"
            visible: !root.selected || !root.selected.hotspot
            enabled: root.canStart && !root.busy
            onTextChanged: if (text && !root.formTarget && root.selected) root.formTarget = Object.assign({}, root.selected)
        }
        ControlTextField {
            id: password
            objectName: "hotspotPassword"
            Layout.fillWidth: true
            theme: root.theme
            secret: true
            placeholderText: "Password (8–63 ASCII characters)"
            Accessible.name: "Hotspot password"
            visible: !root.selected || !root.selected.hotspot
            enabled: root.canStart && !root.busy
            onTextChanged: if (text && !root.formTarget && root.selected) root.formTarget = Object.assign({}, root.selected)
        }
        Flow {
            Layout.fillWidth: true
            spacing: root.theme.spacing("md")
            SettingsButton {
                objectName: "hotspotStart"
                theme: root.theme
                visible: !root.selected || !root.selected.hotspot
                text: root.selected && root.selected.activePath !== "/" ? "Disconnect “" + root.selected.name + "” & start hotspot" : "Start hotspot"
                enabled: !root.busy && root.canStart && ssid.text.trim().length > 0 && password.text.length >= 8 && password.text.length <= 63
                onClicked: root.start()
            }
            SettingsConfirmButton {
                targetIdentity: JSON.stringify(root.selected)
                objectName: "hotspotStop"
                theme: root.theme; actionText: "Stop hotspot"
                visible: root.selected !== null && root.selected.hotspot && root.selected.owned
                enabled: !root.busy
                onConfirmed: root.backend.stop(root.selected)
            }
        }
        Text {
            Layout.fillWidth: true
            text: root.selected && root.selected.hotspot && !root.selected.owned ? "Manage this hotspot in the app that created it."
                : "Hotspots use WPA2 encryption and stop when disconnected or after reboot. The password is not saved to disk. Saved Wi-Fi profiles stay available for reconnection."
            textFormat: Text.PlainText; wrapMode: Text.WordWrap
            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
    }
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.backend ? Errors.message(root.backend.error) || root.backend.notice || (root.backend.applying ? "Working…" : "") : ""
        textFormat: Text.PlainText; wrapMode: Text.WordWrap
        color: root.backend && Errors.message(root.backend.error) ? root.theme.critical : root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
    }
    SettingsButton { theme: root.theme; text: "Refresh"; enabled: !root.busy; onClicked: root.backend.refresh(true) }
}
