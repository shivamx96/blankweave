#!/usr/bin/env python3
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'defaults/shell'))

SPEC = importlib.util.spec_from_file_location('shortcuts', REPO / 'defaults/shell/shortcuts-settings.py')
m = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(m)

class ShortcutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, HOME=self.temp.name, XDG_CONFIG_HOME=self.temp.name, HYPRLAND_INSTANCE_SIGNATURE='session')
        env.start(); self.addCleanup(env.stop)
        self.helper=m.Shortcuts(); self.marker='defaults'; self.errors=[]; self.reject=False; self.override=False; self.options=''
        self.rows=self.bindings({})
        mocked=patch.object(m, 'ipc', side_effect=self.ipc);mocked.start();self.addCleanup(mocked.stop)

    def bindings(self, saved):
        rows=[]
        for r in m.catalog():
            _,mask,key=m.chord(saved.get(r['id'],r['default']))
            rows.append(dict(description='blankweave:'+r['id'],key=key,modmask=mask,keycode=0,submap='',repeat=r['repeat'],locked=r.get('locked',False)))
        return rows

    def ipc(self,*args):
        if args[0]=='repl':return self.marker
        if args[0]=='configerrors':return json.dumps(self.errors)
        if args[0]=='binds':return json.dumps(self.rows)
        if args[0]=='getoption':return json.dumps({'str':self.options})
        if args[0]=='reload':
            if self.reject:self.reject=False;raise ValueError('Rejected reload')
            saved=self.helper.settings()
            self.rows=self.bindings(saved['bindings'])
            if self.override:self.rows=[r for r in self.rows if r['description']!='blankweave:terminal']
            self.marker=m.revision(saved) if self.helper.config.exists() else 'defaults'
            return 'ok'
        raise AssertionError(args)

    def request(self, action='terminal',value='SUPER + CTRL + F8'):
        return dict(revision=m.revision(self.helper.settings()),session='session',fingerprint=m.revision([self.rows,self.options]),id=action,value=value)

    def test_panel_bindings_are_unique_and_unlocked(self):
        rows = m.catalog()
        expected = {"audio": "A", "network": "N", "bluetooth": "B", "notifications": "I", "display": "D"}
        for panel, key in expected.items():
            row = next(r for r in rows if r['id'] == 'panel-' + panel)
            self.assertEqual(row['default'], 'SUPER + CTRL + ' + key)
            self.assertFalse(row.get('locked', False))
            chord = m.chord(row['default'])
            self.assertEqual(sum(m.chord(other['default']) == chord for other in rows), 1)
        voice = (REPO / 'defaults/hypr/voxtype.lua').read_text()
        for panel, key in expected.items():
            self.assertNotIn('"SUPER + CTRL + ' + key + '"', voice)

    def test_settings_shortcuts_binding(self):
        self.assertIn('slash', m.KEYS)
        rows = [r for r in m.catalog() if r['default'] == 'SUPER + slash']
        self.assertEqual([r['id'] for r in rows], ['settings-shortcuts'])
        self.assertNotIn('locked', rows[0])
        lua = (REPO / 'defaults/hypr/keybindings.lua').read_text()
        self.assertIn('bind("settings-shortcuts", main_mod .. " + slash", hl.dsp.exec_cmd("~/.local/bin/blankweave settings shortcuts"))', lua)

    def test_apply_reset(self):
        self.helper.apply(self.request())
        self.assertEqual(self.helper.settings()['bindings']['terminal'],'SUPER + CTRL + F8')
        self.assertTrue(self.helper.verified(self.rows,'terminal','SUPER + CTRL + F8'))
        self.helper.apply(self.request(value=None));self.assertEqual(self.helper.settings()['bindings'],{})
        self.assertTrue(self.helper.verified(self.rows,'terminal','SUPER + Return'))

    def test_lock_remap_preserves_locked_flag(self):
        self.helper.apply(self.request(action='lock', value='SUPER + CTRL + F9'))
        self.assertTrue(self.helper.verified(self.rows, 'lock', 'SUPER + CTRL + F9'))
        for action in ('lock', 'terminal'):
            rows = copy.deepcopy(self.rows)
            row = next(r for r in rows if r['description'] == 'blankweave:' + action)
            row['locked'] = not row['locked']
            self.assertFalse(self.helper.verified(rows, action,
                'SUPER + CTRL + F9' if action == 'lock' else 'SUPER + Return'))

    def test_managed_conflict(self):
        with self.assertRaisesRegex(ValueError,'conflicts'):self.helper.apply(self.request(value='SUPER + b'))
        self.assertFalse(self.helper.config.exists())

    def test_personal_release_and_keycode_conflicts(self):
        for key,code in [('F8',0),('',74)]:
            self.rows=self.bindings({})+[dict(description='Personal action',key=key,modmask=68,keycode=code,submap='',release=True)]
            with self.assertRaisesRegex(ValueError,'Personal action'):self.helper.apply(self.request())

    def test_submaps(self):
        self.rows.append(dict(description='submap action',key='F8',modmask=68,keycode=0,submap='resize'))
        self.helper.apply(self.request())
        self.rows.append(dict(description='universal action',key='F9',modmask=68,keycode=0,submap='resize',submap_universal='true'))
        with self.assertRaisesRegex(ValueError,'universal action'):self.helper.apply(self.request(value='SUPER + CTRL + F9'))

    def test_layout_switch_conflict(self):
        self.options='grp:win_space_toggle'
        # Remove launcher to isolate the XKB conflict.
        self.rows=[r for r in self.rows if r['description']!='blankweave:launcher']
        with self.assertRaisesRegex(ValueError,'layout switcher'):self.helper.apply(self.request(value='SUPER + space'))

    def test_stale(self):
        for key,val in [('revision','old'),('session','old'),('fingerprint','old')]:
            r=self.request();r[key]=val
            with self.assertRaisesRegex(ValueError,'changed'):self.helper.apply(r)

    def test_removed_action(self):
        self.rows=[r for r in self.rows if r['description']!='blankweave:terminal']
        with self.assertRaisesRegex(ValueError,'removed'):self.helper.apply(self.request())
        self.assertFalse(next(r for r in self.helper.status()['rows'] if r['id']=='terminal')['available'])

    def test_unsafe_chords(self):
        for value in ['A','SHIFT + A','SUPER + SUPER + A','SUPER + code:24','SUPER + mouse:272','SUPER + A; os.execute("x")','CTRL + Unknown',[],None]:
            with self.assertRaises(ValueError):m.chord(value)
        self.assertEqual(m.chord('SHIFT + SUPER + b')[0],'SUPER + SHIFT + B')

    def test_rollback(self):
        self.reject=True
        with self.assertRaisesRegex(ValueError,'restored'):self.helper.apply(self.request())
        self.assertFalse(self.helper.config.exists());self.assertFalse(self.helper.rules.exists())

    def test_readback_rollback(self):
        self.override=True
        with self.assertRaisesRegex(ValueError,'overrides'):self.helper.apply(self.request())
        self.assertFalse(self.helper.config.exists())

    def test_existing_errors(self):
        self.errors=['bad config']
        with self.assertRaisesRegex(ValueError,'existing'):self.helper.apply(self.request())

    def test_user_files(self):
        request=self.request();self.helper.directory.mkdir();target=Path(self.temp.name)/'personal';target.write_text('personal')
        self.helper.rules.symlink_to(target)
        with self.assertRaisesRegex(ValueError,'symlinks'):self.helper.apply(request)
        self.helper.rules.unlink();self.helper.rules.write_text('-- personal')
        with self.assertRaisesRegex(ValueError,'preserved'):self.helper.apply(request)
        self.assertEqual(target.read_text(),'personal')

    def test_feedback_commands_and_silent_fallback(self):
        script = """
local dispatcher = setmetatable({}, {__index=function(self, key) return self end, __call=function() return function() end end})
dispatcher.exec_cmd = function(command) return command end
hl = {dsp=dispatcher, bind=function(keys, action, options)
 if type(action) == "string" then print(options.description .. "\\t" .. action) end
end}
dofile(arg[0]); os.exit(0)
"""
        result = subprocess.run(['lua', '-e', script, str(REPO/'defaults/hypr/keybindings.lua')], check=True, text=True, capture_output=True)
        commands = dict(line.split('\t', 1) for line in result.stdout.splitlines())
        prefix = 'qs ipc -n -p "$HOME/.local/share/blankweave/quickshell" call blankweave '
        expected = {
            'volume-up': 'volume up || wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+',
            'volume-down': 'volume down || wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-',
            'volume-mute': 'volume mute || wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle',
            'mic-mute': 'micMute || wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle',
        }
        for action, command in expected.items():
            self.assertEqual(commands['blankweave:' + action], prefix + command)
        connector = "\"$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')\""
        for action in ['up', 'down']:
            self.assertEqual(commands['blankweave:brightness-' + action], prefix + 'brightness ' + action + ' || ~/.local/share/blankweave/shell/brightness.sh ' + action + ' 5 ' + connector)
        self.assertEqual(commands['blankweave:media-stop'], '~/.local/share/blankweave/shell/open-default.sh command playerctl stop')
        for action, mode in [('screenshot-print', 'screen'), ('screenshot', 'screen'), ('screenshot-region', 'region'), ('screenshot-window', 'window')]:
            self.assertEqual(commands['blankweave:' + action], '~/.local/share/blankweave/shell/screenshot.sh ' + mode)
        self.assertNotIn('notify-send', (REPO/'defaults/shell/brightness.sh').read_text())

    def test_retired_monitor_binding_preserves_other_preferences(self):
        old = {'version': 1, 'bindings': {'move-monitor': 'SUPER + SHIFT + K',
                                        'terminal': 'SUPER + CTRL + F8'}}
        normalized = m.validate(old)
        self.assertEqual(normalized['bindings'], {'terminal': 'SUPER + CTRL + F8'})
        self.assertNotIn('move-monitor', m.render(old))
        self.assertIn('move-monitor', old['bindings'])

    def test_new_defaults_have_no_conflicts(self):
        rows = self.bindings({})
        # Optional voice profile reserves Super+D and both F12 events.
        rows += [dict(description='voice', key=k, modmask=mask, keycode=0, submap='')
                 for k, mask in [('d', 64), ('F12', 0), ('F12', 0)]]
        self.assertNotIn('move-monitor', {r['id'] for r in m.catalog()})
        for row in m.catalog():
            self.assertFalse(self.helper.conflict(rows, row['id'], row['default']), row['id'])
        for key in ['mouse:272', 'mouse:273']:
            with self.assertRaises(ValueError):
                m.chord('SUPER + ' + key)

    def test_lua_catalog_and_callbacks(self):
        # Execute the real file with harmless dispatcher stubs; its declarations
        # must match the catalog, including workspace callbacks and repeat flags.
        script='''
local dispatcher = setmetatable({}, {__index=function(self, key) return self end, __call=function() return function() end end})
dispatcher.exec_cmd = function(command) return command end
local power_command = 'qs ipc -n -p "$HOME/.local/share/blankweave/quickshell" call blankweave power'
local workspace_action
hl = {dsp=dispatcher, bind=function(keys, action, options)
 if options.mouse then
  local fixed = { ["blankweave:drag-move"] = "SUPER + mouse:272", ["blankweave:drag-resize"] = "SUPER + mouse:273", ["blankweave:drag-resize-left"] = "SUPER + SHIFT + mouse:272" }
  assert(keys == fixed[options.description])
  assert(not options.locked and not options.repeating)
  return
 end
 if options.description == "blankweave:logout" or options.description == "blankweave:power-menu" then
  assert(action == power_command, "Power shortcuts must open the confirmation panel")
 end
 if options.description == "blankweave:lock" then
  assert(action == "~/.local/share/blankweave/shell/lock.sh", "Manual lock must call the helper directly")
 end
 local allowed = {["blankweave:brightness-down"] = true, ["blankweave:brightness-up"] = true, ["blankweave:lock"] = true, ["blankweave:media-next"] = true, ["blankweave:media-pause"] = true, ["blankweave:media-play"] = true, ["blankweave:media-previous"] = true, ["blankweave:media-stop"] = true, ["blankweave:mic-mute"] = true, ["blankweave:volume-down"] = true, ["blankweave:volume-mute"] = true, ["blankweave:volume-up"] = true}
 assert((options.locked == true) == (allowed[options.description] == true), "Exact locked set")
 assert(keys ~= "SUPER + M", "Old unguarded session shortcut must remain free")
 print(options.description .. "\\t" .. keys .. "\\t" .. tostring(options.repeating == true) .. "\\t" .. tostring(options.locked == true))
 if options.description == "blankweave:workspace-3" then workspace_action=action end
end, get_active_monitor=function() return {active_workspace={id=3}} end,
get_monitors=function() return {{},{}} end, dispatch=function() end}
dofile(arg[0]); assert(type(workspace_action)=="function"); workspace_action(); os.exit(0)
'''
        result=subprocess.run(['lua','-e',script,str(REPO/'defaults/hypr/keybindings.lua')],check=True,text=True,capture_output=True)
        captured=[line.split('\t') for line in result.stdout.splitlines()]
        expected=[['blankweave:'+r['id'],r['default'],str(r['repeat']).lower(),str(r.get('locked',False)).lower()] for r in m.catalog()]
        self.assertEqual(captured,expected)
        self.helper.apply(self.request())
        # Saved bindings are applied by Lua without changing the catalog action.
        result=subprocess.run(['lua','-e',script,str(REPO/'defaults/hypr/keybindings.lua')],check=True,text=True,capture_output=True)
        self.assertIn('blankweave:terminal\tSUPER + CTRL + F8\tfalse',result.stdout)

class DefaultRoleBindingsTest(unittest.TestCase):
    def test_role_commands_and_stable_ids(self):
        root = Path(__file__).resolve().parents[1]
        lua = (root / 'defaults/hypr/keybindings.lua').read_text()
        for role in ('browser', 'files', 'terminal'):
            self.assertIn('bind("' + role + '"', lua)
            self.assertIn('open-default.sh ' + role, lua)
        self.assertNotIn('zen-browser', lua)
        self.assertNotIn('blueman-manager', lua)
        self.assertIn('blankweave settings bluetooth', lua)


if __name__=='__main__':unittest.main()
