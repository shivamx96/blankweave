pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "JobStatus.js" as Status

ColumnLayout {
    id: root
    required property var theme
    required property var service
    property bool expanded: false
    readonly property var jobs: service ? service.backgroundJobs || [] : []
    signal settingRequested(string settingId)
    visible: jobs.length > 0 || Boolean(service && service.jobsError)
    spacing: 4
    SettingsButton {
        theme: root.theme
        visible: root.jobs.length > 0
        Layout.fillWidth: true
        text: root.jobs.filter(job => Status.running(job)).length + " running · "
            + root.jobs.filter(job => !Status.running(job)).length + " finished · " + (root.expanded ? "Hide tasks ▴" : "Show tasks ▾")
        onClicked: root.expanded = !root.expanded
    }
    Text {
        Layout.fillWidth: true
        visible: root.service && Boolean(root.service.jobsError)
        text: root.service ? root.service.jobsError || "" : ""
        wrapMode: Text.WordWrap
        color: root.theme.warning; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
    }
    ScrollView {
        visible: root.expanded
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(jobRows.implicitHeight, 140)
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: SettingsScrollBar { theme: root.theme }
        ColumnLayout {
            id: jobRows
            width: parent.width
            Repeater {
                model: root.jobs
                delegate: RowLayout {
                    id: jobRow
                    required property var modelData
                    Layout.fillWidth: true
                    SettingsButton {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: jobRow.modelData.label + " · " + Status.phase(jobRow.modelData) + " · View"
                        onClicked: root.settingRequested(jobRow.modelData.domain)
                    }
                    SettingsButton {
                        theme: root.theme; text: "Dismiss"
                        visible: !Status.running(jobRow.modelData)
                        onClicked: root.service.provider(jobRow.modelData.domain).dismissedJobId = jobRow.modelData.id
                    }
                }
            }
        }
    }
}
