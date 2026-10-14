import QtQuick
import QtTest
import "../../defaults/quickshell/Services/BarWidgets.js" as Widgets
TestCase {
    name: "BarWidgets"
    function test_normalization_preserves_new_widgets_and_rejects_unknowns() {
        compare(Widgets.order("left", "window,window,bogus,overview"), ["window", "overview", "workspaces"])
        compare(Widgets.order("right", "audio").slice(0, 2), ["indicators", "audio"])
        compare(Widgets.order("right", "audio").length, Widgets.groups.right.length)
        compare(Widgets.hidden("overview,power,audio,bogus"), ["audio"])
    }
    function test_move_and_boundaries() {
        compare(Widgets.move("left", "", "workspaces", -1), "workspaces,overview,window")
        compare(Widgets.move("left", "", "overview", -1), "overview,workspaces,window")
        compare(Widgets.move("left", "", "window", 1), "overview,workspaces,window")
    }
    function test_right_groups_preserve_custom_order_inside_each_group() {
        const order = Widgets.order("right", "cpu,audio,power,brightness,indicators")
        compare(order[0], "indicators")
        verify(order.indexOf("audio") < order.indexOf("brightness"))
        verify(order.indexOf("battery") < order.indexOf("cpu"))
        verify(order.indexOf("cpu") < order.indexOf("power"))
        verify(!Widgets.canMove("right", order, 1, -1))
        compare(Widgets.move("right", order.join(","), "audio", -1), order.join(","))
        verify(Widgets.canMove("right", order, 1, 1))
    }
    function test_dividers_only_separate_visible_groups() {
        const defaults = Widgets.order("right", "")
        compare(defaults.filter(id => Widgets.dividerBefore("right", defaults, id)), ["brightness", "memory"])
        const hiddenFirstMembers = ["audio", "network", "cpu", "power"]
        compare(hiddenFirstMembers.filter(id => Widgets.dividerBefore("right", hiddenFirstMembers, id)), ["cpu"])
        verify(Widgets.dividerBefore("right", ["indicators", "power"], "power"))
        verify(!Widgets.dividerBefore("right", ["power"], "power"))
        verify(!Widgets.dividerBefore("left", ["overview", "workspaces"], "workspaces"))
    }
}
