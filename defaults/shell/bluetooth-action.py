#!/usr/bin/env python3
"""One BlueZ action with a temporary, device-scoped interactive pairing agent."""
import json
import re
import signal
import sys
import threading

from gi.repository import Gio, GLib, GLibUnix

DEVICE = "org.bluez.Device1"
PROPERTIES = "org.freedesktop.DBus.Properties"
AGENT = "/org/blankweave/PairingAgent"
AGENT_XML = """<node><interface name="org.bluez.Agent1">
<method name="Release"/><method name="Cancel"/>
<method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
<method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
<method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
<method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
<method name="RequestAuthorization"><arg type="o" direction="in"/></method>
<method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
</interface></node>"""


def emit(**data):
    print(json.dumps(data), flush=True)


class Action:
    def __init__(self, action, path):
        if action not in ("pair", "connect", "disconnect", "forget") or not re.fullmatch(
                r"/org/bluez/hci\d+/dev_(?:[0-9A-Fa-f]{2}_){5}[0-9A-Fa-f]{2}", path):
            raise ValueError("Invalid Bluetooth action or device identity.")
        self.action, self.path = action, path
        self.stage = action
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.loop = GLib.MainLoop()
        self.pending = None
        self.prompt_kind = ""
        self.sequence = 0
        self.done = False
        self.success = False
        self.registered = False
        self.owner = self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                       "org.freedesktop.DBus", "GetNameOwner", GLib.Variant("(s)", ("org.bluez",)),
                                       None, Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]

    def call_sync(self, path, interface, method, parameters=None):
        return self.bus.call_sync(self.owner, path, interface, method, parameters, None,
                                  Gio.DBusCallFlags.NONE, 5000, None)

    def properties(self):
        return self.call_sync(self.path, PROPERTIES, "GetAll", GLib.Variant("(s)", (DEVICE,))).unpack()[0]

    def call(self, path, interface, method, parameters, after):
        def completed(connection, result):
            if self.done:
                return
            try:
                connection.call_finish(result)
                after()
            except GLib.Error as error:
                self.finish(False, error.message)
        self.bus.call(self.owner, path, interface, method, parameters, None, Gio.DBusCallFlags.NONE,
                      90000 if method == "Pair" else 20000, None, completed)

    def agent_call(self, connection, sender, path, interface, method, parameters, invocation):
        args = parameters.unpack()
        if sender != self.owner or (args and args[0] != self.path):
            invocation.return_dbus_error("org.bluez.Error.Rejected", "This pairing session belongs to another device.")
            return
        if method in ("Cancel", "Release"):
            self.reject_pending()
            emit(kind="prompt", prompt=None)
            invocation.return_value(None)
            return
        if method.startswith("Display"):
            self.sequence += 1
            code = args[1] if method == "DisplayPinCode" else f"{args[1]:06d}"
            emit(kind="prompt", prompt={"id": self.sequence, "type": "display", "code": code,
                                        "entered": args[2] if len(args) > 2 else 0})
            invocation.return_value(None)
            return
        if self.pending:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Another confirmation is pending.")
            return
        self.sequence += 1
        self.prompt_kind = {"RequestPinCode": "pin", "RequestPasskey": "passkey"}.get(method, "confirm")
        self.pending = invocation
        emit(kind="prompt", prompt={"id": self.sequence, "type": self.prompt_kind,
                                    "code": f"{args[1]:06d}" if method == "RequestConfirmation" else "",
                                    "service": args[1] if method == "AuthorizeService" else ""})

    def reject_pending(self):
        if self.pending:
            self.pending.return_dbus_error("org.bluez.Error.Canceled", "Pairing canceled.")
            self.pending = None

    def respond(self, data):
        if self.done:
            return False
        if data.get("cancel") is True:
            self.cancel()
            return False
        if not self.pending or data.get("id") != self.sequence:
            return False
        value = data.get("value")
        if self.prompt_kind == "confirm":
            if value is not True:
                self.cancel()
                return False
            response = None
        elif self.prompt_kind == "pin":
            if not isinstance(value, str) or not re.fullmatch(r"[\x20-\x7e]{1,16}", value):
                return False
            response = GLib.Variant("(s)", (value,))
        else:
            if not isinstance(value, str) or not re.fullmatch(r"\d{1,6}", value, re.ASCII):
                return False
            response = GLib.Variant("(u)", (int(value),))
        pending, self.pending = self.pending, None
        pending.return_value(response)
        emit(kind="prompt", prompt=None)
        return False

    def cancel(self):
        if self.done:
            return False
        self.reject_pending()
        if self.action == "pair":
            try:
                self.call_sync(self.path, DEVICE, "Disconnect" if self.stage == "connect" else "CancelPairing")
            except GLib.Error:
                pass
        self.finish(False, "Pairing canceled.")
        return False

    def finish(self, success, message=""):
        if self.done:
            return
        self.done, self.success = True, success
        self.reject_pending()
        emit(kind="result", success=success, message=message)
        self.loop.quit()

    def confirm_connection(self, expected):
        matched = bool(self.properties().get("Connected")) == expected
        self.finish(matched, "" if matched else "The device did not confirm the connection change.")

    def connect(self):
        self.stage = "connect"
        self.call(self.path, DEVICE, "Connect", None, lambda: self.confirm_connection(True))

    def paired(self):
        if not self.properties().get("Paired"):
            self.finish(False, "Pairing was not confirmed by the device.")
            return
        self.call_sync(self.path, PROPERTIES, "Set", GLib.Variant("(ssv)", (DEVICE, "Trusted", GLib.Variant("b", True))))
        self.connect()

    def input_loop(self):
        for line in sys.stdin:
            try:
                data = json.loads(line)
                if isinstance(data, dict):
                    GLib.idle_add(self.respond, data)
            except (ValueError, TypeError):
                pass
        GLib.idle_add(self.cancel)

    def run(self):
        properties = self.properties()
        if properties.get("Blocked") and self.action in ("pair", "connect"):
            raise ValueError("This device is blocked in Bluetooth settings.")
        try:
            if self.action == "pair":
                interface = Gio.DBusNodeInfo.new_for_xml(AGENT_XML).interfaces[0]
                self.bus.register_object(AGENT, interface, self.agent_call, None, None)
                self.call_sync("/org/bluez", "org.bluez.AgentManager1", "RegisterAgent", GLib.Variant("(os)", (AGENT, "KeyboardDisplay")))
                self.registered = True
                threading.Thread(target=self.input_loop, daemon=True).start()
                GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.cancel)
                GLib.timeout_add_seconds(100, self.cancel)
                if properties.get("Paired"):
                    self.paired()
                else:
                    self.call(self.path, DEVICE, "Pair", None, self.paired)
            elif self.action == "connect":
                self.connect()
            elif self.action == "disconnect":
                self.call(self.path, DEVICE, "Disconnect", None,
                          lambda: self.confirm_connection(False))
            else:
                self.call(self.path.rsplit("/", 1)[0], "org.bluez.Adapter1", "RemoveDevice", GLib.Variant("(o)", (self.path,)), lambda: self.finish(True))
            if not self.done:
                self.loop.run()
        finally:
            if self.registered:
                try:
                    self.call_sync("/org/bluez", "org.bluez.AgentManager1", "UnregisterAgent", GLib.Variant("(o)", (AGENT,)))
                except GLib.Error:
                    pass
        return 0 if self.success else 1


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("Usage: bluetooth-action.py <pair|connect|disconnect|forget> DEVICE_PATH")
        sys.exit(Action(sys.argv[1], sys.argv[2]).run())
    except (GLib.Error, OSError, ValueError) as error:
        emit(kind="result", success=False, message=str(error))
        sys.exit(1)
