pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "JobStatus.js" as Status

ColumnLayout {
    id: root
    required property var theme
    required property var job
    property bool expanded: false
    property bool copied: false
    property double now: Date.now()
    readonly property string jobId: job ? job.id : ""
    readonly property bool running: Status.running(job)
    signal copyRequested(string text)
    signal dismissRequested(string jobId)
    onJobIdChanged: { expanded = false; copied = false }
    spacing: 8
    Timer { interval: 1000; repeat: true; running: root.visible && root.running; onTriggered: root.now = Date.now() }
    Text {
        objectName: "jobSummary"
        Layout.fillWidth: true
        text: root.job ? root.job.label + " · " + Status.phase(root.job)
            + (Status.elapsed(root.job, root.now) ? " · " + Status.elapsed(root.job, root.now) : "") : ""
        textFormat: Text.PlainText; wrapMode: Text.WordWrap
        color: root.job && ["failed", "interrupted"].includes(root.job.phase) ? root.theme.warning : root.theme.text
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        font.weight: Font.Medium
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }
    Text {
        Layout.fillWidth: true
        visible: root.running
        text: "Continues in the background. Progress percentage is not available."
        wrapMode: Text.WordWrap
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        SettingsButton {
            theme: root.theme
            text: root.expanded ? "Hide details" : "View details"
            visible: Boolean(root.job && root.job.message)
            onClicked: root.expanded = !root.expanded
        }
        SettingsButton {
            theme: root.theme; text: root.copied ? "Copied" : "Copy report"
            visible: Boolean(root.job && root.job.message)
            onClicked: {
                root.copyRequested(root.job.label + " · " + Status.phase(root.job) + "\n" + root.job.message)
                root.copied = true
            }
        }
        SettingsButton {
            theme: root.theme; text: "Dismiss"
            visible: root.job !== null && !root.running
            onClicked: root.dismissRequested(root.jobId)
        }
    }
    ScrollView {
        objectName: "jobDetails"
        Layout.fillWidth: true
        Layout.preferredHeight: 180
        visible: root.expanded && Boolean(root.job && root.job.message)
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: SettingsScrollBar { theme: root.theme }
        TextEdit {
            width: parent.width
            text: root.job ? root.job.message || "" : ""
            textFormat: TextEdit.PlainText; readOnly: true; selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            color: root.theme.text; selectionColor: root.theme.accentSurface; selectedTextColor: root.theme.text
            font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
    }
}
