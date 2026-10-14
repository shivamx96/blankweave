pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"
import "../Modules"
import "../Services/BarWidgets.js" as Widgets
BarSection {
    id: root
    required property var bar
    required property string group
    readonly property var prefs: bar.preferences
    property int layoutRevision: 0
    readonly property var visibleIds: {
        // Repeater count can change before its delegates become available.
        root.layoutRevision
        const ids = []
        for (let i = 0; i < widgets.count; i++) {
            const entry = widgets.itemAt(i)
            if (entry && entry.shown) ids.push(entry.modelData)
        }
        return ids
    }
    Repeater {
        id: widgets
        onItemAdded: root.layoutRevision++
        onItemRemoved: root.layoutRevision++
        model: Widgets.order(root.group, root.prefs[root.group + "Order"])
        delegate: RowLayout {
            id: entry
            required property string modelData
            readonly property bool shown: widget.active && widget.item !== null
                && (modelData !== "indicators" || (widget.item as ApplicationIndicatorsWidget).hasIndicators)
                && (modelData !== "battery" || (widget.item as BatteryWidget).batteryAvailable)
            visible: shown
            spacing: root.theme.barItemGap
            BarDivider { theme: root.theme; visible: Widgets.dividerBefore(root.group, root.visibleIds, entry.modelData) }
            Loader {
                id: widget
                active: !Widgets.hidden(root.prefs.hiddenWidgets).includes(entry.modelData)
                    && (entry.modelData !== "window" || !root.bar.veryCompact)
                Layout.preferredWidth: item ? (item as Item).implicitWidth : 0
                Layout.preferredHeight: item ? (item as Item).implicitHeight : 0
                sourceComponent: ({overview: root.overview, workspaces: root.workspaces, window: root.activeWindow, weather: root.weather, clock: root.clock, indicators: root.indicators, brightness: root.brightness, audio: root.audio, bluetooth: root.bluetooth, network: root.network, notifications: root.notifications, battery: root.battery, memory: root.memory, cpu: root.cpu, gpu: root.gpu, power: root.power})[entry.modelData] || null
                onActiveChanged: if (!active && item) root.bar.hideTooltip(item)
            }
        }
    }
    property Component overview: Component { SystemOverviewWidget { bar: root.bar; theme: root.theme } }
    property Component workspaces: Component { WorkspacesWidget { bar: root.bar; theme: root.theme } }
    property Component activeWindow: Component { ActiveWindowWidget { bar: root.bar; theme: root.theme } }
    property Component weather: Component { WeatherWidget { bar: root.bar; theme: root.theme } }
    property Component clock: Component { ClockWidget { bar: root.bar; theme: root.theme } }
    property Component indicators: Component { ApplicationIndicatorsWidget { bar: root.bar; theme: root.theme } }
    property Component brightness: Component { BrightnessWidget { bar: root.bar; theme: root.theme; iconOnly: true } }
    property Component audio: Component { AudioWidget { bar: root.bar; theme: root.theme; iconOnly: true } }
    property Component bluetooth: Component { BluetoothWidget { bar: root.bar; theme: root.theme; bluetooth: root.bar.shell.bluetooth; iconOnly: true } }
    property Component network: Component { NetworkWidget { bar: root.bar; theme: root.theme; wifi: root.bar.shell.wifi; connections: root.bar.shell.connections; iconOnly: true } }
    property Component notifications: Component { NotificationWidget { bar: root.bar; theme: root.theme } }
    property Component battery: Component { BatteryWidget { bar: root.bar; theme: root.theme; power: root.bar.shell.power; iconOnly: true } }
    property Component memory: Component { MemoryWidget { bar: root.bar; theme: root.theme; iconOnly: root.bar.compact } }
    property Component cpu: Component { CpuWidget { bar: root.bar; theme: root.theme; iconOnly: root.bar.compact } }
    property Component gpu: Component { GpuWidget { bar: root.bar; theme: root.theme; iconOnly: root.bar.compact } }
    property Component power: Component { PowerWidget { bar: root.bar; theme: root.theme } }
}
