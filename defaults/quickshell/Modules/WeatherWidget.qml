import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"
    readonly property string weatherScript: shellDir + "/weather-status.sh"
    property var status: ({
        "configured": false,
        "available": false,
        "stale": false,
        "error": ""
    })
    property bool editingLocation: false
    property string locationQuery: ""
    property string searchError: ""
    property string actionKind: ""
    readonly property bool configured: Boolean(status.configured)
    readonly property bool available: Boolean(status.available)
    readonly property bool stale: Boolean(status.stale)
    readonly property var current: status.current || ({})
    readonly property var hourly: status.hourly || ({})
    readonly property var daily: status.daily || ({})
    readonly property int weatherCode: Number(current.weather_code ?? -1)
    readonly property bool isDay: Number(current.is_day ?? 1) === 1
    readonly property int temperature: Math.round(Number(current.temperature_2m || 0))
    readonly property int feelsLike: Math.round(Number(current.apparent_temperature || 0))
    readonly property int rainChance: hourly.precipitation_probability
        && hourly.precipitation_probability.length > 0
        ? Math.round(Number(hourly.precipitation_probability[0] || 0))
        : 0
    readonly property string weatherMark: root.markFor(root.weatherCode, root.isDay)

    function updateStatus(payload) {
        if (!payload)
            return
        try {
            root.status = JSON.parse(payload)
        } catch (error) {
            root.status = {
                "configured": root.configured,
                "available": false,
                "stale": false,
                "error": "Could not read the weather response"
            }
        }
    }

    function conditionCategory(code, day) {
        const value = Number(code)
        if (value === 0)
            return day ? "clear-day" : "clear-night"
        if (value === 1 || value === 2)
            return day ? "partly-cloudy-day" : "partly-cloudy-night"
        if (value === 3)
            return "cloudy"
        if (value === 45 || value === 48)
            return "fog"
        if ((value >= 51 && value <= 67) || (value >= 80 && value <= 82))
            return "rain"
        if ((value >= 71 && value <= 77) || value === 85 || value === 86)
            return "snow"
        if (value >= 95)
            return "storm"
        return "cloudy"
    }

    function markFor(code, day) {
        return "weather-" + root.conditionCategory(code, day)
    }

    function conditionLabel(code) {
        const value = Number(code)
        if (value === 0) return "Clear"
        if (value === 1) return "Mainly clear"
        if (value === 2) return "Partly cloudy"
        if (value === 3) return "Overcast"
        if (value === 45 || value === 48) return "Foggy"
        if (value >= 51 && value <= 57) return "Drizzle"
        if (value >= 61 && value <= 67) return "Rain"
        if (value >= 71 && value <= 77) return "Snow"
        if (value >= 80 && value <= 82) return "Rain showers"
        if (value === 85 || value === 86) return "Snow showers"
        if (value >= 95) return "Thunderstorms"
        return "Weather unavailable"
    }

    function formatHour(value) {
        const parts = String(value || "").split("T")
        if (parts.length < 2)
            return "—"
        const hour = Number(parts[1].slice(0, 2))
        if (Number.isNaN(hour))
            return "—"
        const displayHour = hour % 12 === 0 ? 12 : hour % 12
        return displayHour + (hour < 12 ? " AM" : " PM")
    }

    function formatDay(value) {
        const parsed = new Date(String(value || "") + "T12:00:00")
        if (Number.isNaN(parsed.getTime()))
            return "—"
        return parsed.toLocaleDateString(Qt.locale(), "ddd").toUpperCase()
    }

    function timeOnly(value) {
        const parts = String(value || "").split("T")
        return parts.length > 1 ? parts[1].slice(0, 5) : "—"
    }

    function windDirection(value) {
        const directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        const normalized = ((Number(value || 0) % 360) + 360) % 360
        return directions[Math.round(normalized / 45) % 8]
    }

    function hourlyRows() {
        const rows = []
        const times = hourly.time || []
        const temperatures = hourly.temperature_2m || []
        const codes = hourly.weather_code || []
        const dayStates = hourly.is_day || []
        const rain = hourly.precipitation_probability || []
        const count = Math.min(6, times.length)
        for (let index = 0; index < count; index++) {
            rows.push({
                "time": String(times[index] || ""),
                "temperature": Math.round(Number(temperatures[index] || 0)),
                "code": Number(codes[index] ?? -1),
                "isDay": Number(dayStates[index] ?? 1) === 1,
                "rain": Math.round(Number(rain[index] || 0))
            })
        }
        return rows
    }

    function dailyRows() {
        const rows = []
        const times = daily.time || []
        const codes = daily.weather_code || []
        const highs = daily.temperature_2m_max || []
        const lows = daily.temperature_2m_min || []
        const rain = daily.precipitation_probability_max || []
        const count = Math.min(5, times.length)
        for (let index = 0; index < count; index++) {
            rows.push({
                "date": String(times[index] || ""),
                "code": Number(codes[index] ?? -1),
                "high": Math.round(Number(highs[index] || 0)),
                "low": Math.round(Number(lows[index] || 0)),
                "rain": Math.round(Number(rain[index] || 0))
            })
        }
        return rows
    }

    function syncSearchResults(results) {
        searchModel.clear()
        const values = results || []
        for (let index = 0; index < values.length; index++) {
            const result = values[index]
            searchModel.append({
                "placeId": String(result.id || index),
                "name": String(result.name || "Unknown location"),
                "latitude": Number(result.latitude),
                "longitude": Number(result.longitude),
                "admin1": String(result.admin1 || ""),
                "country": String(result.country || ""),
                "timezone": String(result.timezone || "")
            })
        }
    }

    function searchLocation() {
        const query = root.locationQuery.trim()
        if (!query || actionProcess.running)
            return
        root.searchError = ""
        root.actionKind = "search"
        actionProcess.command = [root.weatherScript, "search", query]
        actionProcess.running = true
    }

    function saveLocation(result) {
        if (actionProcess.running)
            return
        root.searchError = ""
        root.actionKind = "save"
        actionProcess.command = [
            root.weatherScript,
            "save",
            String(result.latitude),
            String(result.longitude),
            String(result.name || ""),
            String(result.admin1 || ""),
            String(result.country || "")
        ]
        actionProcess.running = true
    }

    iconMark: root.weatherMark
    iconVisualSize: root.theme.iconSize + 2
    label: root.available ? root.temperature + "°" : ""
    tooltip: !root.configured
        ? "Weather location not set\nClick to configure"
        : (root.available
            ? String(root.status.location || "Weather") + " · " + root.conditionLabel(root.weatherCode)
                + " · " + root.temperature + "°C"
                + (root.stale ? "\nShowing cached forecast" : "")
            : String(root.status.error || "Weather unavailable"))
    active: weatherPanel.open

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            weatherPanel.open = !weatherPanel.open
            if (weatherPanel.open && !root.configured)
                root.editingLocation = true
        }
        else if (button === Qt.RightButton) {
            statusPoller.refresh()
        }
    }

    ScriptPoller {
        id: statusPoller
        command: root.weatherScript + " status"
        interval: weatherPanel.open ? 300000 : 900000
        onUpdated: payload => root.updateStatus(payload)
    }

    ListModel {
        id: searchModel
    }

    Process {
        id: actionProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const payload = String(text || "").trim()
                try {
                    const response = JSON.parse(payload || "{}")
                    if (response.results !== undefined) {
                        root.syncSearchResults(response.results || [])
                        root.searchError = String(response.error || "")
                        if (!root.searchError && searchModel.count === 0)
                            root.searchError = "No matching locations"
                    }
                    else if (response.saved !== undefined) {
                        if (Boolean(response.saved)) {
                            root.editingLocation = false
                            root.locationQuery = ""
                            root.syncSearchResults([])
                            statusPoller.refresh()
                        }
                        else {
                            root.searchError = String(response.error || "Could not save location")
                        }
                    }
                } catch (error) {
                    root.searchError = root.actionKind === "search"
                        ? "Could not read location results"
                        : "Could not save location"
                }
            }
        }

        onExited: root.actionKind = ""
    }

    ControlPopup {
        id: weatherPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        anchorAlignment: "center"
        panelWidth: 430

        ControlPanelHeader {
            theme: root.theme
            iconMark: root.weatherMark
            title: root.configured ? String(root.status.location || "WEATHER").toUpperCase() : "WEATHER"
            subtitle: root.available
                ? root.conditionLabel(root.weatherCode) + " · Feels like " + root.feelsLike + "°C"
                    + (root.stale ? " · Cached" : "")
                : (root.configured ? String(root.status.error || "Loading forecast…") : "Choose a forecast location")
            actions: [
                { "id": "refresh", "icon": "󰑐" },
                { "id": "location", "icon": "󰍎", "active": root.editingLocation }
            ]
            onActionPressed: actionId => {
                if (actionId === "refresh")
                    statusPoller.refresh()
                else if (actionId === "location") {
                    root.editingLocation = !root.editingLocation
                    root.searchError = ""
                    if (root.editingLocation)
                        Qt.callLater(() => locationField.forceActiveFocus())
                }
            }
        }

        ControlDivider { theme: root.theme }

        ColumnLayout {
            visible: root.editingLocation
            Layout.fillWidth: true
            spacing: 8

            ControlSectionLabel {
                theme: root.theme
                text: "FORECAST LOCATION"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                ControlTextField {
                    id: locationField
                    Layout.fillWidth: true
                    theme: root.theme
                    placeholderText: "Search city or postcode"
                    text: root.locationQuery
                    onTextEdited: root.locationQuery = text
                    onAccepted: root.searchLocation()
                }

                ControlAction {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 82
                    theme: root.theme
                    icon: "󰍉"
                    label: actionProcess.running && root.actionKind === "search" ? "Searching" : "Search"
                    enabled: root.locationQuery.trim() !== "" && !actionProcess.running
                    onPressed: root.searchLocation()
                }
            }

            Text {
                visible: root.searchError !== ""
                Layout.fillWidth: true
                text: root.searchError
                color: root.theme.warning
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.microTextSize
                wrapMode: Text.Wrap
                renderType: Text.NativeRendering
            }

            Repeater {
                model: searchModel

                delegate: ApplicationListRow {
                    required property string name
                    required property real latitude
                    required property real longitude
                    required property string admin1
                    required property string country

                    theme: root.theme
                    rowHeight: 44
                    icon: "󰍎"
                    title: name
                    subtitle: [admin1, country].filter(value => value !== "").join(" · ")
                    busy: actionProcess.running && root.actionKind === "save"
                    actions: [{ "id": "select", "icon": "󰄬", "label": "Use" }]
                    onActionPressed: root.saveLocation({
                        "name": name,
                        "latitude": latitude,
                        "longitude": longitude,
                        "admin1": admin1,
                        "country": country
                    })
                }
            }
        }

        ApplicationEmptyState {
            visible: !root.editingLocation && !root.available
            theme: root.theme
            icon: root.configured ? "󰖐" : "󰍎"
            title: root.configured ? "Forecast unavailable" : "Set a weather location"
            message: root.configured
                ? String(root.status.error || "Try refreshing in a moment.")
                : "Use the location control above to search for your city."
        }

        ApplicationSummary {
            visible: !root.editingLocation && root.available
            theme: root.theme
            metrics: [
                { "label": "NOW", "value": root.temperature + "°C", "active": true },
                { "label": "FEELS", "value": root.feelsLike + "°C" },
                { "label": "RAIN", "value": root.rainChance + "%" }
            ]
        }

        ApplicationSummary {
            visible: !root.editingLocation && root.available
            theme: root.theme
            metrics: [
                {
                    "label": "HUMIDITY",
                    "value": Math.round(Number(root.current.relative_humidity_2m || 0)) + "%"
                },
                {
                    "label": "WIND",
                    "value": Math.round(Number(root.current.wind_speed_10m || 0)) + " "
                        + root.windDirection(root.current.wind_direction_10m)
                },
                {
                    "label": "UV MAX",
                    "value": root.daily.uv_index_max && root.daily.uv_index_max.length > 0
                        ? Number(root.daily.uv_index_max[0] || 0).toFixed(1)
                        : "—"
                }
            ]
        }

        ControlDivider {
            visible: !root.editingLocation && root.available
            theme: root.theme
        }

        ControlSectionLabel {
            visible: !root.editingLocation && root.available
            theme: root.theme
            text: "NEXT HOURS"
        }

        RowLayout {
            visible: !root.editingLocation && root.available
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: root.hourlyRows()

                delegate: ColumnLayout {
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: parent.index === 0 ? "NOW" : root.formatHour(parent.modelData.time)
                        color: parent.index === 0 ? root.theme.accentBright : root.theme.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.microTextSize
                        font.weight: parent.index === 0 ? Font.DemiBold : Font.Normal
                        renderType: Text.NativeRendering
                    }

                    VectorMark {
                        Layout.alignment: Qt.AlignHCenter
                        mark: root.markFor(parent.modelData.code, parent.modelData.isDay)
                        markColor: root.theme.text
                        accentColor: root.theme.accentBright
                        visualSize: 22
                    }

                    Text {
                        Layout.fillWidth: true
                        text: parent.modelData.temperature + "°"
                        color: root.theme.text
                        horizontalAlignment: Text.AlignHCenter
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.smallTextSize
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                    }

                    Text {
                        Layout.fillWidth: true
                        text: parent.modelData.rain + "%"
                        color: root.theme.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        font.family: root.theme.monoFontFamily
                        font.pixelSize: root.theme.microTextSize
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        ControlDivider {
            visible: !root.editingLocation && root.available
            theme: root.theme
        }

        ControlSectionLabel {
            visible: !root.editingLocation && root.available
            theme: root.theme
            text: "FIVE DAY OUTLOOK"
        }

        Repeater {
            model: root.available && !root.editingLocation ? root.dailyRows() : []

            delegate: Item {
                required property int index
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 34

                RowLayout {
                    anchors.fill: parent
                    spacing: 10

                    Text {
                        Layout.preferredWidth: 48
                        text: parent.parent.index === 0 ? "TODAY" : root.formatDay(parent.parent.modelData.date)
                        color: parent.parent.index === 0 ? root.theme.accentBright : root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.microTextSize
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                    }

                    VectorMark {
                        mark: root.markFor(parent.parent.modelData.code, true)
                        markColor: root.theme.text
                        accentColor: root.theme.accentBright
                        visualSize: 22
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.conditionLabel(parent.parent.modelData.code)
                        color: root.theme.textMuted
                        elide: Text.ElideRight
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.microTextSize
                        renderType: Text.NativeRendering
                    }

                    Text {
                        Layout.preferredWidth: 42
                        horizontalAlignment: Text.AlignRight
                        text: parent.parent.modelData.rain + "%"
                        color: root.theme.textMuted
                        font.family: root.theme.monoFontFamily
                        font.pixelSize: root.theme.microTextSize
                        renderType: Text.NativeRendering
                    }

                    Text {
                        Layout.preferredWidth: 62
                        horizontalAlignment: Text.AlignRight
                        text: parent.parent.modelData.high + "° / " + parent.parent.modelData.low + "°"
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.smallTextSize
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        Text {
            visible: !root.editingLocation && root.available
            Layout.fillWidth: true
            text: root.daily.sunrise && root.daily.sunrise.length > 0
                ? "SUNRISE " + root.timeOnly(root.daily.sunrise[0])
                    + "   ·   SUNSET " + root.timeOnly(root.daily.sunset[0])
                    + "   ·   OPEN-METEO"
                : "FORECAST · OPEN-METEO"
            color: root.theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            font.family: root.theme.monoFontFamily
            font.pixelSize: root.theme.microTextSize
            font.letterSpacing: 0.4
            renderType: Text.NativeRendering
        }
    }
}
