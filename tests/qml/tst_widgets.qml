import QtQuick
import QtTest
import "../../defaults/quickshell/Services/BarWidgets.js" as Widgets
TestCase {
    name: "BarWidgets"
    function test_normalization_preserves_new_widgets_and_rejects_unknowns() {
        compare(Widgets.order("left", "window,window,bogus,overview"), ["window", "overview", "workspaces"])
        compare(Widgets.order("right", "audio")[0], "audio")
        compare(Widgets.order("right", "audio").length, Widgets.groups.right.length)
        compare(Widgets.hidden("overview,power,audio,bogus"), ["audio"])
    }
    function test_move_and_boundaries() {
        compare(Widgets.move("left", "", "workspaces", -1), "workspaces,overview,window")
        compare(Widgets.move("left", "", "overview", -1), "overview,workspaces,window")
        compare(Widgets.move("left", "", "window", 1), "overview,workspaces,window")
    }
}
