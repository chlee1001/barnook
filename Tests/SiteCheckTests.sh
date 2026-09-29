#!/usr/bin/env bash
# Exercise scripts/check-site.sh: the real site passes, and each broken copy fails
# with the message of the check that guards it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fresh() { rm -rf "$work/site"; cp -R "$root/site" "$work/site"; }

fresh
bash "$root/scripts/check-site.sh" "$work/site" >/dev/null

expect_failure() {
  local expected="$1" output
  if output="$(bash "$root/scripts/check-site.sh" "$work/site" 2>&1)"; then
    echo "check-site passed a site that should fail with: $expected" >&2; exit 1
  fi
  [[ "$output" == *"$expected"* ]] || { printf 'expected "%s", got:\n%s\n' "$expected" "$output" >&2; exit 1; }
  fresh
}

perl -0pi -e 's/ id="faq"//' "$work/site/ko/index.html"
expect_failure '(b) the id sequences'

perl -0pi -e 's#</head>#<script src="https://cdn.example.com/x.js"></script>\n</head>#' "$work/site/index.html"
expect_failure '(f) index.html loads a third-party resource'

perl -0pi -e "s#</head>#<img src='//cdn.example.com/x.png' alt=''>\n</head>#" "$work/site/ko/index.html"
expect_failure '(f) ko/index.html loads a third-party resource'

perl -0pi -e 's#</body>#<script>console.log(1)</script>\n</body>#' "$work/site/index.html"
expect_failure '(f) index.html must have exactly one inline script'

perl -0pi -e 's#</body>#<script type="module">console.log(1)</script>\n</body>#' "$work/site/index.html"
expect_failure '(f) index.html must have exactly one inline script'

perl -0pi -e 's#</body>#<script data-src="assets/site.js">console.log(1)</script>\n</body>#' "$work/site/index.html"
expect_failure '(f) index.html must have exactly one inline script'

perl -0pi -e 's#</head>#<img src="assets/icon-256.png" srcset="assets/icon-256.png 1x, https://cdn.example.com/x.png 2x" alt="">\n</head>#' "$work/site/index.html"
expect_failure '(f) index.html loads a third-party resource'

perl -0pi -e 's#</head>#<IMG SRC = "https://cdn.example.com/x.png" alt="">\n</head>#' "$work/site/ko/index.html"
expect_failure '(f) ko/index.html loads a third-party resource'

printf '\n.x { background: url(//cdn.example.com/x.png); }\n' >> "$work/site/assets/site.css"
expect_failure '(f) site.css loads a third-party resource'

printf '\n.x { background: URL(HTTPS://cdn.example.com/x.png); }\n' >> "$work/site/assets/site.css"
expect_failure '(f) site.css loads a third-party resource'

perl -0pi -e 's# id="deskHint"##' "$work/site/index.html"; perl -0pi -e 's# id="deskHint"##' "$work/site/ko/index.html"
expect_failure '(j) index.html lacks #deskHint'

perl -0pi -e 's#<link rel="alternate" hreflang="x-default"[^>]*>\n##' "$work/site/index.html"
expect_failure '(g) the alternate links of the en and ko pages differ'

perl -0pi -e 's#og/og-en\.png#og/og-kr.png#' "$work/site/index.html"
expect_failure '(g) index.html og:image'

printf 'x' >> "$work/site/assets/fonts/PretendardVariable.woff2"
expect_failure '(i) the font does not match'

printf 'x' >> "$work/site/assets/fonts/LICENSE.txt"
expect_failure '(i) the font license does not match'

perl -0pi -e 's#</footer>#<p class="mock-note">draft</p>\n</footer>#' "$work/site/ko/index.html"
expect_failure '(h) mockup leftovers'

perl -0pi -e 's#</footer>#<img src="assets/missing.png" alt="">\n</footer>#' "$work/site/index.html"
expect_failure '(e) index.html links to missing assets/missing.png'

echo 'check-site passes the site and rejects all 17 broken copies.'
