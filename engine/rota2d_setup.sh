#!/bin/bash
# Rota 360 2D (Inside Out) project setup. usage: bash rota2d_setup.sh <project-dir>
# Run AFTER: bash $SKILL/scripts/new_video.sh inside-out <slug>
# Adds the Turkish Google-TTS voice tool and the World Tour mixer (atmospheres) from bundle.sh, and Turkish caption casing.
set -eu
P="${1:?project dir}"; E="$(cd "$(dirname "$0")" && pwd)"
python3 - "$E/bundle.sh" "$P" <<'PY'
import re, sys
b = open(sys.argv[1]).read(); P = sys.argv[2]
for m in re.finditer(r'cat > "\$P/([^"]+)" <<\'(\w+)\'\n(.*?)\n\2\n', b, re.S):
    if m.group(1) in ('tools/voice_google.py', 'tools/mix.py'):
        open(f'{P}/{m.group(1)}', 'w').write(m.group(3) + '\n'); print('installed', m.group(1))
c = open(f'{P}/src/core/captions.js').read().replace(".toUpperCase()", ".toLocaleUpperCase('tr')")
open(f'{P}/src/core/captions.js', 'w').write(c); print('captions: Turkish upper-case')
PY
mkdir -p "$P/review" "$P/renders"
echo "Rota 2D project ready: $P (style inside-out; write script.json + src/shots.js with the kit in src/core/kit.js)"
