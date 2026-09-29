#!/usr/bin/env bash
# Build the website's generated images.
#   icons  site/assets/{icon-256,favicon-64,apple-touch-icon}.png from Resources/AppIcon.png
#          (rerun after changing the app icon, alongside scripts/make-icon.sh)
#   og     site/assets/og/og-{en,ko}.png, 1200x630, from scripts/og-card.html in headless Chrome
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
assets="$root/site/assets"

icons() {
  local png="$root/Resources/AppIcon.png"
  [[ -f "$png" ]] || { echo "error: $png is missing; run scripts/make-icon.sh first" >&2; exit 1; }
  sips -z 256 256 "$png" --out "$assets/icon-256.png" >/dev/null
  sips -z 64 64 "$png" --out "$assets/favicon-64.png" >/dev/null
  sips -z 180 180 "$png" --out "$assets/apple-touch-icon.png" >/dev/null
  echo "wrote $assets/{icon-256,favicon-64,apple-touch-icon}.png"
}

og() {
  local chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
  [[ -x "$chrome" ]] || { echo "error: Chrome not found at $chrome; set CHROME" >&2; exit 1; }
  local port
  port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$root" >/dev/null 2>&1 &
  og_server=$!
  trap 'kill "$og_server" 2>/dev/null || true' EXIT
  local tries=0
  until curl -fs -o /dev/null "http://127.0.0.1:$port/scripts/og-card.html"; do
    tries=$((tries + 1))
    [[ "$tries" -lt 50 ]] || { echo "error: the preview server did not start" >&2; exit 1; }
    sleep 0.1
  done

  mkdir -p "$assets/og"
  local lang out
  for lang in en ko; do
    out="$assets/og/og-$lang.png"
    "$chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 \
      --virtual-time-budget=5000 --screenshot="$out" "http://127.0.0.1:$port/scripts/og-card.html?lang=$lang" >/dev/null 2>&1
    local size
    size="$(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixel(Width|Height)/ { printf "%s ", $2 }')"
    [[ "$size" == "1200 630 " ]] || { echo "error: $out is ${size}, not 1200x630" >&2; exit 1; }
    echo "wrote $out"
  done
}

case "${1:-}" in
  icons) icons ;;
  og) og ;;
  *) echo "usage: $0 icons|og" >&2; exit 2 ;;
esac
