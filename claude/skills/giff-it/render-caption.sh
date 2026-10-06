#!/bin/bash
# Render one caption band to PNG with headless Chrome.
# usage: render.sh <out.png> <width> <height> <badge> <badge-color> <step> <text> [<subtext>]
set -euo pipefail
out=$1 w=$2 h=$3 badge=$4 color=$5 step=$6 text=$7 sub=${8:-}
html="${out%.png}.html"
cat > "$html" <<EOF
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:${w}px;height:${h}px;background:#111317;overflow:hidden}
body{display:flex;align-items:center;gap:22px;padding:0 28px;box-sizing:border-box;
  font-family:-apple-system,"SF Pro Text","Helvetica Neue",Arial,sans-serif;color:#f2f3f5;
  border-top:3px solid ${color}}
.badge{flex:none;font-weight:800;font-size:26px;letter-spacing:.08em;color:#111317;
  background:${color};border-radius:8px;padding:8px 16px}
.step{flex:none;font-weight:700;font-size:24px;color:#9aa0aa;font-variant-numeric:tabular-nums}
.txt{display:flex;flex-direction:column;gap:4px;min-width:0}
.main{font-weight:600;font-size:30px;line-height:1.2}
.sub{font-size:21px;color:#aeb4bd}
</style></head><body>
<div class="badge">${badge}</div><div class="step">${step}</div>
<div class="txt"><div class="main">${text}</div>${sub:+<div class="sub">${sub}</div>}</div>
</body></html>
EOF
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
  --hide-scrollbars --force-device-scale-factor=1 --window-size="${w},${h}" \
  --screenshot="$out" "file://$html" >/dev/null 2>&1
test -s "$out"
