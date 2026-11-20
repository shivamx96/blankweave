#!/usr/bin/env python3
"""Execute animation declarations against assertions, without a compositor."""
from pathlib import Path
import re
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
namespaces = set()
for path in (root / 'defaults/quickshell').rglob('*.qml'):
    namespaces.update(re.findall(r'WlrLayershell.namespace:\s*"(blankweave-[^"]+)"', path.read_text()))
script = '''local rules, leaves = {}, {}
hl = {
 config=function(v)
   assert(v.animations.enabled)
   assert(v.ecosystem.no_update_news and v.ecosystem.no_donation_nag)
 end,
 curve=function(name, v)
   assert(name == "easeOut" and v.type == "bezier")
   for _, p in ipairs(v.points) do assert(p[2] >= 0 and p[2] <= 1) end
 end,
 animation=function(v)
   assert(v.speed >= 2 and v.speed <= 3 and v.bezier == "easeOut")
   leaves[v.leaf] = true
 end,
 layer_rule=function(v) assert(v.no_anim); rules[v.match.namespace] = true end,
}
dofile(arg[1])
for _, leaf in ipairs({"windowsIn", "windowsOut", "windowsMove", "fade", "border", "workspaces"}) do assert(leaves[leaf], leaf) end
'''
for namespace in sorted(namespaces):
    script += 'assert(rules["^' + namespace + '$"], "Missing layer rule: ' + namespace + '")\n'
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'test.lua'
    path.write_text(script)
    import os
    subprocess.run(['lua', str(path), str(root / 'defaults/hypr/animations.lua')],
                   env={**os.environ, 'XDG_CONFIG_HOME': directory}, check=True)
print('Animation bounds, ecosystem options and QML namespace coverage passed.')
