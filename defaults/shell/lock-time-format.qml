// Same Qt locale and short-time test as ShellPreferences / LocaleFormats.js.
import QtQml
QtObject {
    Component.onCompleted: {
        Qt.exit(/ap/i.test(Qt.locale().timeFormat(Locale.ShortFormat)) ? 12 : 24)
    }
}
