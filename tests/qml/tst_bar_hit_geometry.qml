import QtQuick
import QtTest
import "../../defaults/quickshell/Components/BarHitGeometry.js" as Geometry
TestCase {
    name: "BarHitGeometry"
    function test_edges_and_nonoverlapping_gaps() {
        const rects = [{x:12,y:5,width:30,height:30}, {x:50,y:5,width:30,height:30}, {x:88,y:5,width:30,height:30}]
        for (const bottom of [false, true]) {
            const first = Geometry.partition(rects, 0, 130, 40, bottom)
            const middle = Geometry.partition(rects, 1, 130, 40, bottom)
            const last = Geometry.partition(rects, 2, 130, 40, bottom)
            compare(first.x + 12, 0)
            compare(last.x + 88 + last.width, 130)
            compare(first.x + 12 + first.width, middle.x + 50)
            compare(middle.x + 50 + middle.width, last.x + 88)
            compare(middle.y + 5, bottom ? 5 : 0)
            compare(middle.y + 5 + middle.height, bottom ? 40 : 35)
        }
    }
}
