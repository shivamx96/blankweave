import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Components"

WidgetFrame {
    id: root

    property int displayMode: 0
    property int viewYear: clock.date.getFullYear()
    property int viewMonth: clock.date.getMonth()
    property date selectedDate: clock.date
    readonly property string todayKey: Qt.formatDate(clock.date, "yyyy-MM-dd")
    readonly property string selectedKey: Qt.formatDate(selectedDate, "yyyy-MM-dd")

    function monthTitle() {
        return Qt.formatDate(new Date(viewYear, viewMonth, 1), "MMMM yyyy").toUpperCase()
    }

    function isoWeekNumber(date) {
        const target = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12)
        const day = (target.getDay() + 6) % 7
        target.setDate(target.getDate() - day + 3)
        const firstThursday = new Date(target.getFullYear(), 0, 4, 12)
        const firstDay = (firstThursday.getDay() + 6) % 7
        firstThursday.setDate(firstThursday.getDate() - firstDay + 3)
        return 1 + Math.round((target.getTime() - firstThursday.getTime()) / 604800000)
    }

    function calendarCells() {
        const result = []
        const headings = ["WK", "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        for (let index = 0; index < headings.length; index++) {
            result.push({
                "kind": index === 0 ? "weekHeader" : "dayHeader",
                "label": headings[index]
            })
        }

        const first = new Date(viewYear, viewMonth, 1, 12)
        const leadingDays = (first.getDay() + 6) % 7
        for (let week = 0; week < 6; week++) {
            const weekStart = new Date(viewYear, viewMonth, 1 - leadingDays + week * 7, 12)
            result.push({
                "kind": "week",
                "label": String(root.isoWeekNumber(weekStart)).padStart(2, "0")
            })

            for (let day = 0; day < 7; day++) {
                const date = new Date(
                    weekStart.getFullYear(),
                    weekStart.getMonth(),
                    weekStart.getDate() + day,
                    12
                )
                const key = Qt.formatDate(date, "yyyy-MM-dd")
                result.push({
                    "kind": "date",
                    "label": String(date.getDate()),
                    "timestamp": date.getTime(),
                    "inMonth": date.getMonth() === viewMonth,
                    "today": key === root.todayKey,
                    "selected": key === root.selectedKey
                })
            }
        }
        return result
    }

    function shiftMonth(offset) {
        const next = new Date(viewYear, viewMonth + offset, 1, 12)
        viewYear = next.getFullYear()
        viewMonth = next.getMonth()
    }

    function goToday() {
        selectedDate = new Date(clock.date.getTime())
        viewYear = clock.date.getFullYear()
        viewMonth = clock.date.getMonth()
    }

    function selectDate(timestamp) {
        const next = new Date(Number(timestamp))
        selectedDate = next
        if (next.getFullYear() !== viewYear || next.getMonth() !== viewMonth) {
            viewYear = next.getFullYear()
            viewMonth = next.getMonth()
        }
    }

    icon: displayMode === 0 ? "󰥔" : "󰃭"
    label: {
        if (displayMode === 1)
            return Qt.formatDateTime(clock.date, "ddd, dd MMM")
        if (displayMode === 2)
            return Qt.formatDateTime(clock.date, "ddd, dd MMM · hh:mm AP")
        return Qt.formatDateTime(clock.date, "hh:mm AP")
    }
    tooltip: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy\nHH:mm:ss")
        + "\nRight-click: change display"
    active: displayMode !== 0 || calendarPanel.open
    labelWeight: Font.DemiBold
    horizontalPadding: 13

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            calendarPanel.open = !calendarPanel.open
        }
        else if (button === Qt.RightButton)
            root.displayMode = (root.displayMode + 1) % 3
    }

    ControlPopup {
        id: calendarPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        anchorAlignment: "center"
        panelWidth: 400

        ControlPanelHeader {
            theme: root.theme
            icon: "󰃭"
            title: "TIME & DATE"
            subtitle: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy · HH:mm:ss t")
            actions: [
                { "id": "previous", "icon": "󰁍" },
                { "id": "today", "icon": "󰃭", "active": root.todayKey === root.selectedKey },
                { "id": "next", "icon": "󰁔" }
            ]
            onActionPressed: actionId => {
                if (actionId === "previous")
                    root.shiftMonth(-1)
                else if (actionId === "today")
                    root.goToday()
                else if (actionId === "next")
                    root.shiftMonth(1)
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "LOCAL TIME",
                    "value": Qt.formatDateTime(clock.date, "hh:mm AP"),
                    "active": true
                },
                {
                    "label": "ISO WEEK",
                    "value": "W" + String(root.isoWeekNumber(clock.date)).padStart(2, "0")
                },
                {
                    "label": "TIME ZONE",
                    "value": Qt.formatDateTime(clock.date, "t")
                }
            ]
        }

        ControlSectionLabel {
            theme: root.theme
            text: root.monthTitle()
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 8
            columnSpacing: 2
            rowSpacing: 3

            Repeater {
                model: root.calendarCells()

                delegate: Item {
                    id: calendarCell

                    required property var modelData
                    readonly property bool isDate: modelData.kind === "date"
                    readonly property bool isWeek: modelData.kind === "week"

                    Layout.preferredWidth: modelData.kind === "weekHeader" || isWeek ? 28 : 44
                    Layout.preferredHeight: modelData.kind === "dayHeader" || modelData.kind === "weekHeader"
                        ? 22
                        : 36

                    Rectangle {
                        visible: calendarCell.isDate && Boolean(calendarCell.modelData.today)
                        anchors.centerIn: parent
                        width: 31
                        height: 30
                        color: "transparent"
                        border.width: 1
                        border.color: root.theme.accentBright
                    }

                    Rectangle {
                        visible: calendarCell.isDate && Boolean(calendarCell.modelData.selected)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 22
                        height: 2
                        color: root.theme.accentBright
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(calendarCell.modelData.label || "")
                        color: {
                            if (calendarCell.isDate && Boolean(calendarCell.modelData.selected))
                                return root.theme.accentBright
                            if (calendarCell.isDate && !Boolean(calendarCell.modelData.inMonth))
                                return root.theme.textMuted
                            if (calendarCell.isWeek || calendarCell.modelData.kind === "weekHeader")
                                return root.theme.divider
                            if (calendarCell.modelData.kind === "dayHeader")
                                return root.theme.textMuted
                            return root.theme.text
                        }
                        opacity: calendarCell.isDate && !Boolean(calendarCell.modelData.inMonth) ? 0.5 : 1
                        font.family: calendarCell.isWeek || calendarCell.modelData.kind === "weekHeader"
                            ? root.theme.monoFontFamily
                            : root.theme.fontFamily
                        font.pixelSize: calendarCell.modelData.kind === "dayHeader"
                            || calendarCell.modelData.kind === "weekHeader"
                            ? root.theme.microTextSize
                            : root.theme.smallTextSize
                        font.weight: calendarCell.isDate && (Boolean(calendarCell.modelData.today)
                            || Boolean(calendarCell.modelData.selected))
                            ? Font.Bold
                            : Font.Normal
                        renderType: Text.NativeRendering
                    }

                    Rectangle {
                        visible: calendarMouse.containsMouse && calendarCell.isDate
                            && !Boolean(calendarCell.modelData.selected)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 14
                        height: 1
                        color: root.theme.accentBright
                    }

                    MouseArea {
                        id: calendarMouse
                        anchors.fill: parent
                        enabled: calendarCell.isDate
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.selectDate(calendarCell.modelData.timestamp)
                    }
                }
            }
        }

        ControlDivider { theme: root.theme }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: Qt.formatDate(root.selectedDate, "dddd, d MMMM yyyy")
                color: root.selectedKey === root.todayKey
                    ? root.theme.accentBright
                    : root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
            }

            Text {
                text: "W" + String(root.isoWeekNumber(root.selectedDate)).padStart(2, "0")
                color: root.theme.textMuted
                font.family: root.theme.monoFontFamily
                font.pixelSize: root.theme.microTextSize
                renderType: Text.NativeRendering
            }
        }
    }
}
