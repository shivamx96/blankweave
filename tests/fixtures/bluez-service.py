#!/usr/bin/env python3
"""Minimal BlueZ on the test's private bus; never talks to the system bus."""
import json
import os
from pathlib import Path
from gi.repository import Gio, GLib

state_path = Path(os.environ['BLUETOOTH_TEST_STATE'])
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName',
              GLib.Variant('(su)', ('org.bluez', 0)), None, Gio.DBusCallFlags.NONE, 3000, None)
DEVICE = '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF'
XML = '''<node>
<interface name="org.bluez.AgentManager1">
<method name="RegisterAgent"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="UnregisterAgent"><arg type="o" direction="in"/></method>
</interface>
<interface name="org.bluez.Device1"><method name="Pair"/><method name="Connect"/><method name="Disconnect"/><method name="CancelPairing"/></interface>
<interface name="org.bluez.Adapter1"><method name="RemoveDevice"><arg type="o" direction="in"/></method></interface>
<interface name="org.freedesktop.DBus.Properties">
<method name="GetAll"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
<method name="Set"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/></method>
</interface></node>'''
agent = None
pending = None

def read():
    return json.loads(state_path.read_text())

def write(state):
    state_path.write_text(json.dumps(state))

def method_call(connection, sender, path, interface, method, params, invocation):
    global agent, pending
    state = read()
    state.setdefault('calls', []).append(method)
    write(state)
    args = params.unpack()
    if method == 'RegisterAgent':
        agent = (sender, args[0])
    elif method == 'UnregisterAgent':
        agent = None
    elif method == 'GetAll':
        if state.get('removed'):
            invocation.return_dbus_error('org.bluez.Error.DoesNotExist', 'Device disappeared')
            return
        props = {k: GLib.Variant('b', state.get(k, False)) for k in ['Paired', 'Connected', 'Blocked', 'Trusted']}
        invocation.return_value(GLib.Variant('(a{sv})', (props,)))
        return
    elif method == 'Set':
        state[args[1]] = args[2]
        write(state)
    elif method == 'Connect':
        if state.get('failConnect'):
            invocation.return_dbus_error('org.bluez.Error.Failed', 'Connection refused by fixture')
            return
        state['Connected'] = not state.get('readbackMismatch', False)
        write(state)
    elif method == 'Disconnect':
        state['Connected'] = False
        write(state)
    elif method == 'RemoveDevice':
        assert args == (DEVICE,)
        state['removed'] = True
        write(state)
    elif method == 'CancelPairing':
        if pending:
            old, pending = pending, None
            old.return_dbus_error('org.bluez.Error.AuthenticationCanceled', 'Canceled')
    elif method == 'Pair':
        pending = invocation
        kind = state.get('prompt', 'confirm')
        device = DEVICE if kind != 'foreign' else '/org/bluez/hci1/dev_AA_BB_CC_DD_EE_FF'
        spec = {'pin': ('RequestPinCode', '(o)', (device,)),
                'passkey': ('RequestPasskey', '(o)', (device,)),
                'display': ('DisplayPasskey', '(ouq)', (device, 12345, 0)),
                'authorization': ('RequestAuthorization', '(o)', (device,)),
                'service': ('AuthorizeService', '(os)', (device, 'test-service'))}
        name, signature, values = spec.get(kind, ('RequestConfirmation', '(ou)', (device, 12345)))
        def response(conn, result):
            global pending
            if not pending:
                return
            current, pending = pending, None
            try:
                answer = conn.call_finish(result).unpack()
                changed = read()
                changed['answer'] = list(answer)
                changed['Paired'] = True
                write(changed)
                current.return_value(None)
            except GLib.Error:
                current.return_dbus_error('org.bluez.Error.AuthenticationRejected', 'Pairing rejected')
        bus.call(agent[0], agent[1], 'org.bluez.Agent1', name, GLib.Variant(signature, values), None,
                 Gio.DBusCallFlags.NONE, 10000, None, response)
        return
    invocation.return_value(None)

for interface in Gio.DBusNodeInfo.new_for_xml(XML).interfaces:
    path = '/org/bluez' if interface.name.endswith('AgentManager1') else '/org/bluez/hci0' if interface.name.endswith('Adapter1') else DEVICE
    bus.register_object(path, interface, method_call, None, None)
print('READY', flush=True)
GLib.MainLoop().run()
