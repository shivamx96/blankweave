import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var bar
    required property var theme

    readonly property bool hasIndicators: tailscale.running || docker.running || git.available

    implicitWidth: indicators.implicitWidth
    implicitHeight: theme.widgetHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    RowLayout {
        id: indicators
        anchors.fill: parent
        spacing: theme.barItemGap

        TailscaleWidget {
            id: tailscale
            bar: root.bar
            theme: root.theme
        }

        DockerWidget {
            id: docker
            bar: root.bar
            theme: root.theme
        }

        GitWidget {
            id: git
            bar: root.bar
            theme: root.theme
        }
    }
}
