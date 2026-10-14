pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Services/BarWidgets.js" as Widgets
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property var prefs: backend && backend.preferences ? backend.preferences : null
    readonly property bool writable: prefs !== null && prefs.ready
    spacing: 10
    Text {
        Layout.fillWidth: true
        text: "Show or hide widgets and move them within each section. Changes apply to every display. System and power menus remain available."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Repeater {
        model: ["left", "center", "right"]
        delegate: ColumnLayout {
            id: section
            required property string modelData
            readonly property var order: Widgets.order(modelData, root.prefs ? root.prefs.bar[modelData + "Order"] : "")
            Layout.fillWidth: true
            Text { text: section.modelData.toUpperCase(); color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize }
            Repeater {
                model: section.order
                delegate: RowLayout {
                    id: entry
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    Text { text: Widgets.labels[entry.modelData]; Layout.fillWidth: true; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize }
                    SettingsButton {
                        theme: root.theme
                        text: root.prefs && Widgets.hidden(root.prefs.bar.hiddenWidgets).includes(entry.modelData) ? "Show" : "Hide"
                        enabled: root.writable && !["overview", "power"].includes(entry.modelData)
                        onClicked: {
                            const hidden = Widgets.hidden(root.prefs.bar.hiddenWidgets)
                            root.prefs.bar.hiddenWidgets = (hidden.includes(entry.modelData) ? hidden.filter(id => id !== entry.modelData) : hidden.concat([entry.modelData])).join(",")
                        }
                    }
                    SettingsButton { theme: root.theme; text: "←"; Accessible.name: "Move " + Widgets.labels[entry.modelData] + " left"; enabled: root.writable && entry.index > 0; onClicked: root.prefs.bar[section.modelData + "Order"] = Widgets.move(section.modelData, root.prefs.bar[section.modelData + "Order"], entry.modelData, -1) }
                    SettingsButton { theme: root.theme; text: "→"; Accessible.name: "Move " + Widgets.labels[entry.modelData] + " right"; enabled: root.writable && entry.index < section.order.length - 1; onClicked: root.prefs.bar[section.modelData + "Order"] = Widgets.move(section.modelData, root.prefs.bar[section.modelData + "Order"], entry.modelData, 1) }
                }
            }
        }
    }
    SettingsButton { theme: root.theme; text: "Restore default widgets"; enabled: root.writable; onClicked: { root.prefs.bar.hiddenWidgets = ""; root.prefs.bar.leftOrder = ""; root.prefs.bar.centerOrder = ""; root.prefs.bar.rightOrder = "" } }
    Text { Layout.fillWidth: true; text: root.prefs ? root.prefs.writeError : "Bar preferences unavailable."; visible: text !== ""; color: root.theme.warning; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap }
}
