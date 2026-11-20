import QtQuick
import QtTest
import "../../defaults/quickshell/Services/PollerOutput.js" as Output

TestCase {
    name: "PollerOutput"
    function test_clean_and_noisy() {
        compare(Output.decode('{"text":"42","tooltip":"load"}').data.text, "42")
        compare(Output.decode('profile log\nwarning: {not JSON}\n {"text":"43"}\n').data.text, "43")
        compare(Output.decode('[{"id":"theme"}]').data[0].id, "theme")
        compare(Output.decode('{\n"text":"multiline"\n}').data.text, "multiline")
    }
    function test_ambiguous_or_invalid_output() {
        for (const text of ["", "noise only", "42", "null", '{"text":"42"}\nnoise', '[not JSON]\n{"text":"42"}', '{"text":']) {
            let rejected = false
            try { Output.decode(text) } catch (error) { rejected = true }
            verify(rejected, "Must reject: " + text)
        }
    }
}
