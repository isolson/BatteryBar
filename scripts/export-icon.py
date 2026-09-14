#!/usr/bin/env python3
"""Export the flat fallback from the same SVG layers used by Icon Composer."""
from pathlib import Path
import json
import shutil
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
artwork = root / 'artwork'
package = artwork / 'BatteryBar.icon'
manifest = json.loads((package / 'icon.json').read_text())
ns = 'http://www.w3.org/2000/svg'
ET.register_namespace('', ns)
svg = ET.fromstring('''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="background" x2="0" y2="1"><stop stop-color="#38424A"/><stop offset="1" stop-color="#1A2026"/></linearGradient>
  <linearGradient id="sage" x2="0" y2="1"><stop stop-color="#BFCDB8"/><stop offset="0.5" stop-color="#9BAE95"/><stop offset="1" stop-color="#7F9475"/></linearGradient>
  <linearGradient id="menu" x2="0" y2="1"><stop stop-color="#7D8790"/><stop offset="1" stop-color="#4B555E"/></linearGradient>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="180%"><feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="12"/><feComponentTransfer><feFuncA type="linear" slope="0.3"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <style>.battery-body {fill:url(#sage);stroke:#BCCAB5;stroke-width:4}.menu-strip {fill:url(#menu);stroke:#8C969E;stroke-width:2}</style>
</defs>
<rect x="96" y="96" width="832" height="832" rx="184" fill="url(#background)" stroke="#59616A" stroke-width="2"/>
</svg>''')
composition = ET.SubElement(svg, f'{{{ns}}}g', {'transform': 'translate(96 96) scale(0.8125)'})
# Icon Composer lists the front group first; SVG draws back to front.
for group in reversed(manifest['groups']):
    target = ET.SubElement(composition, f'{{{ns}}}g', {'filter': 'url(#shadow)'})
    for layer in group['layers']:
        source = ET.parse(package / 'Assets' / layer['image-name']).getroot()
        target.extend(list(source))
output = artwork / 'AppIcon.svg'
ET.ElementTree(svg).write(output, encoding='unicode', xml_declaration=False)
inkscape = shutil.which('inkscape') or '/Applications/Inkscape.app/Contents/MacOS/inkscape'
if not Path(inkscape).is_file():
    raise SystemExit('Install Inkscape to update the PNG fallback. Ordinary builds use the tracked PNG.')
subprocess.run([inkscape, str(output), '--export-type=png', '--export-width=1024',
                '--export-height=1024', f'--export-filename={artwork / "AppIcon.png"}'], check=True)
print('Exported artwork/AppIcon.svg and artwork/AppIcon.png from the SVG layers.')
