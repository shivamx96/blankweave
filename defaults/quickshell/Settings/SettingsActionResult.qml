import QtQuick
import QtQuick.Layouts

SettingsResult {
    id: root
    required property var backend
    required property string actionKey
    property string targetKey: ""
    readonly property var outcome: backend && typeof backend.outcome === "function" ? backend.outcome(actionKey, targetKey) : null
    objectName: "actionResult:" + actionKey + ":" + targetKey
    Layout.fillWidth: true
    visible: outcome !== null && message !== ""
    message: outcome ? outcome.message : ""
    detail: outcome ? outcome.detail : ""
    cancelled: Boolean(outcome && outcome.cancelled)
}
