pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Controls

// Own every painted surface: the desktop Qt style can retain a light palette
// even when Blankweave switches themes while this window is open.
Controls.ComboBox {
    id: root
    required property var theme

    implicitHeight: 36
    implicitWidth: 190
    leftPadding: 12
    rightPadding: 32
    hoverEnabled: true
    font.family: theme.fontFamily
    font.pixelSize: theme.smallTextSize

    contentItem: Text {
        text: root.displayText
        textFormat: Text.PlainText
        font: root.font
        color: root.enabled ? root.theme.text : root.theme.textMuted
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: root.width - width - 12
        y: (root.height - height) / 2
        text: "▾"
        font: root.font
        color: root.enabled ? root.theme.text : root.theme.textMuted
    }

    background: Rectangle {
        radius: root.theme.widgetRadius
        color: root.down ? root.theme.surfacePressed
            : root.hovered && root.enabled ? root.theme.surfaceHover : root.theme.surfaceRaised
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
    }

    delegate: Controls.ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: root.width - 8
        implicitHeight: 38
        leftPadding: 12
        rightPadding: 12
        text: String(modelData)
        highlighted: root.highlightedIndex === index
        hoverEnabled: true
        font: root.font
        Accessible.name: text

        contentItem: Text {
            text: option.text
            textFormat: Text.PlainText
            font: option.font
            color: option.highlighted || option.index === root.currentIndex
                ? root.theme.accentBright : root.theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: root.theme.widgetRadius
            color: option.down ? root.theme.surfacePressed
                : option.highlighted ? root.theme.accentSurface
                : option.hovered ? root.theme.surfaceHover : "transparent"
            border.width: option.visualFocus ? 1 : 0
            border.color: root.theme.accentBright
        }
    }

    popup: Controls.Popup {
        y: root.height + 4
        width: root.width
        padding: 4
        topMargin: 8
        bottomMargin: 8
        height: Math.min(menu.contentHeight + padding * 2, 320)
        popupType: Controls.Popup.Item

        contentItem: ListView {
            id: menu
            clip: true
            model: root.delegateModel
            currentIndex: root.highlightedIndex
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {
                visible: menu.contentHeight > menu.height
                contentItem: Rectangle {
                    implicitWidth: 3
                    implicitHeight: 20
                    radius: 1
                    color: root.theme.textMuted
                }
            }
        }
        background: Rectangle {
            radius: root.theme.widgetRadius
            color: root.theme.panelSurface
            border.color: root.theme.outline
        }
    }
}
