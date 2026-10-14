import QtQuick

// Center the clock itself. The neighboring weather widget must not shift it.
Item {
    id: root
    property alias clockContent: clockSlot.data
    property alias weatherContent: weatherSlot.data
    property bool clockVisible: true
    property bool weatherFirst: true
    implicitWidth: clockVisible ? clockSlot.width : weatherSlot.width
    implicitHeight: Math.max(clockSlot.height, weatherSlot.height)
    Item {
        id: clockSlot
        objectName: "centeredClockSlot"
        width: childrenRect.width; height: childrenRect.height
        x: (root.width - width) / 2
    }
    Item {
        id: weatherSlot
        objectName: "adjacentWeatherSlot"
        width: childrenRect.width; height: childrenRect.height
        x: !root.clockVisible ? (root.width - width) / 2
            : root.weatherFirst ? clockSlot.x - width : clockSlot.x + clockSlot.width
    }
}
