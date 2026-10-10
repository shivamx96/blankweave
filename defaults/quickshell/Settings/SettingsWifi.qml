pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool active: backend !== null && backend.profilesActive
    readonly property bool ready: backend !== null && backend.available
    property string passwordKey: ""
    property string confirmUuid: ""
    readonly property var passwordRow: backend ? backend.wifiRows.find(row => row.key === passwordKey) || null : null
    spacing: 12

    function clearPassword() { passwordKey = ""; password.text = "" }
    function requestConnect(row) {
        clearPassword()
        if (!row.known && backend.requiresCredentials(row.security) && backend.supportsPassword(row.security)) {
            passwordKey = row.key
            password.forceActiveFocus()
        } else backend.connectNetwork(row.key)
    }
    function submitPassword() {
        if (!passwordRow || !password.text || backend.busy || !backend.usable) return
        backend.connectNetwork(passwordKey, password.text)
        clearPassword()
    }
    onActiveChanged: if (!active) { clearPassword(); confirmUuid = "" }
    onPasswordRowChanged: if (!passwordRow) clearPassword()
    Connections {
        target: root.backend
        function onCredentialsRequired(key) {
            if (!root.active) return
            const row = root.backend.wifiRows.find(item => item.key === key)
            if (row && root.backend.supportsPassword(row.security)) {
                root.clearPassword()
                root.passwordKey = key
                password.forceActiveFocus()
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        SettingsButton {
            objectName: "wifiPower"
            theme: root.theme
            text: root.ready ? root.backend.enabled ? "Wi-Fi: On" : "Wi-Fi: Off" : "Wi-Fi unavailable"
            selected: root.ready && root.backend.enabled
            enabled: root.ready && root.backend.wifiDevice !== null && root.backend.hardwareEnabled && !root.backend.busy
            onClicked: root.backend.setEnabled(!root.backend.enabled)
        }
        SettingsButton {
            objectName: "wifiRefresh"
            theme: root.theme
            text: "Refresh saved networks"
            enabled: root.ready && !root.backend.profilesBusy
            onClicked: { root.backend.profilesError = ""; root.backend.refreshProfiles() }
        }
    }
    Text {
        Layout.fillWidth: true
        objectName: "wifiStatus"
        text: !root.ready ? "NetworkManager is unavailable."
            : !root.backend.wifiDevice ? "No Wi-Fi adapter detected."
            : !root.backend.hardwareEnabled ? "Wi-Fi is blocked by a hardware switch."
            : !root.backend.managed ? "This Wi-Fi adapter is not managed by NetworkManager."
            : root.backend.hosting ? "This adapter is hosting a Wi-Fi hotspot."
            : !root.backend.enabled ? "Wi-Fi is turned off."
            : root.backend.connectedWifiNetwork ? "Connected to " + root.backend.connectedWifiNetwork.name
            : root.backend.busy ? "Wi-Fi request in progress…" : "Looking for nearby networks…"
        textFormat: Text.PlainText
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.backend ? root.backend.failureReason : ""
        textFormat: Text.PlainText
        color: root.theme.critical
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    ColumnLayout {
        visible: root.passwordRow !== null
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Password for " + (root.passwordRow ? root.passwordRow.ssid : "")
            textFormat: Text.PlainText
            color: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.textSize
            wrapMode: Text.WordWrap
        }
        ControlTextField {
            id: password
            objectName: "wifiPassword"
            Layout.fillWidth: true
            theme: root.theme
            secret: true
            placeholderText: "Wi-Fi password"
            Accessible.name: "Wi-Fi password"
            enabled: root.ready && !root.backend.busy
            onAccepted: root.submitPassword()
            Keys.onEscapePressed: root.clearPassword()
        }
        RowLayout {
            SettingsButton {
                objectName: "wifiPasswordConnect"
                theme: root.theme
                text: "Connect"
                enabled: password.text.length > 0 && root.ready && !root.backend.busy && root.backend.usable
                onClicked: root.submitPassword()
            }
            SettingsButton { theme: root.theme; text: "Cancel"; onClicked: root.clearPassword() }
        }
    }
    Repeater {
        model: root.ready && root.backend.usable ? root.backend.wifiRows : []
        delegate: GridLayout {
            id: networkRow
            required property var modelData
            Layout.fillWidth: true
            columns: root.width < 430 ? 1 : 2
            ColumnLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: networkRow.modelData.ssid
                    textFormat: Text.PlainText
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.textSize
                    font.weight: networkRow.modelData.connected ? Font.DemiBold : Font.Normal
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: (root.backend.actionKey === networkRow.modelData.key ? "Working… · "
                        : networkRow.modelData.connected ? "Connected · " : networkRow.modelData.known ? "Saved · " : "")
                        + networkRow.modelData.signal + "% signal · "
                        + (root.backend.requiresCredentials(networkRow.modelData.security) ? "Secured" : "Open")
                    color: root.theme.textMuted
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.smallTextSize
                    wrapMode: Text.WordWrap
                }
            }
            SettingsButton {
                objectName: "wifiConnect:" + networkRow.modelData.key
                theme: root.theme
                text: networkRow.modelData.connected ? "Disconnect" : "Connect"
                enabled: !root.backend.busy && !networkRow.modelData.stateChanging
                onClicked: networkRow.modelData.connected ? root.backend.disconnectNetwork(networkRow.modelData.key) : root.requestConnect(networkRow.modelData)
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: "Nearby networks update while this page is open. New connections support open and personal-password networks. Configure enterprise certificates or hidden networks in a NetworkManager connection editor first."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.divider }
    Text { text: "Saved networks"; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.textSize; font.weight: Font.DemiBold }
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: !root.backend ? "Saved networks unavailable." : root.backend.profilesError ? root.backend.profilesError
            : !root.backend.profilesReady ? "Reading saved networks…" : !root.backend.profiles.length ? "No saved Wi-Fi networks." : ""
        textFormat: Text.PlainText
        color: root.backend && root.backend.profilesError ? root.theme.critical : root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: root.backend && root.backend.profilesReady ? root.backend.profiles : []
        delegate: GridLayout {
            id: savedRow
            required property var modelData
            Layout.fillWidth: true
            columns: root.width < 430 ? 1 : 2
            Text {
                Layout.fillWidth: true
                text: savedRow.modelData.name + (savedRow.modelData.name !== savedRow.modelData.ssid ? " · " + savedRow.modelData.ssid : "")
                    + (savedRow.modelData.active ? " · Connected" : "")
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize
                wrapMode: Text.WordWrap
            }
            SettingsButton {
                objectName: "wifiForget:" + savedRow.modelData.uuid
                theme: root.theme
                text: root.confirmUuid === savedRow.modelData.uuid ? "Confirm forget" : "Forget"
                enabled: !root.backend.busy && !root.backend.profilesBusy && !savedRow.modelData.active
                onClicked: {
                    if (root.confirmUuid === savedRow.modelData.uuid) {
                        root.backend.forgetProfile(savedRow.modelData.uuid)
                        root.confirmUuid = ""
                    } else { root.confirmUuid = savedRow.modelData.uuid; confirmTimer.restart() }
                }
            }
        }
    }
    Timer { id: confirmTimer; interval: 5000; onTriggered: root.confirmUuid = "" }
}
