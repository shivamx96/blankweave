pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "DateTime.js" as Clock
ColumnLayout {
    id: root
    required property var theme
    property string timeFormat: "24h"
    property var parts: [new Date().getFullYear(), new Date().getMonth()+1, new Date().getDate(), timeFormat === "12h" ? (new Date().getHours()%12 || 12) : new Date().getHours(), new Date().getMinutes(), 0]
    property string period: new Date().getHours() >= 12 ? "PM" : "AM"
    readonly property string composed: Clock.compose(...parts, timeFormat, period)
    signal edited(string value)
    onComposedChanged: edited(composed)
    Component.onCompleted: edited(composed)
    Repeater {
        model: ["Year", "Month", "Day", "Hour", "Minute", "Second"]
        delegate: RowLayout {
            required property int index
            required property string modelData
            Text { text: parent.modelData; color: root.theme.text; font.family: root.theme.fontFamily }
            SettingsNumberField {
                theme: root.theme
                label: parent.modelData
                value: String(root.parts[parent.index])
                minimum: [1970, 1, 1, root.timeFormat === "12h" ? 1 : 0, 0, 0][parent.index]
                maximum: [9999, 12, 31, root.timeFormat === "12h" ? 12 : 23, 59, 59][parent.index]
                onEdited: value => { let next = root.parts.slice(); next[parent.index] = value; root.parts = next; root.edited(root.composed) }
            }
        }
    }
    SettingsComboBox { theme: root.theme; visible: root.timeFormat === "12h"; model: ["AM", "PM"]; currentIndex: root.period === "PM" ? 1 : 0; onActivated: root.period = currentText }
    Text { visible: !root.composed; text: "Enter a valid date and time."; color: root.theme.critical; font.family: root.theme.fontFamily }
}
