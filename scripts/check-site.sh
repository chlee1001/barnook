#!/usr/bin/env bash
# Check the static website: en/ko structural parity, local links, no third-party loads,
# page metadata, leftover mockup markers, the pinned Pretendard font and license,
# and the elements the demo script needs.
# Usage: scripts/check-site.sh [site-dir]   (default: site/ next to this script's repo)
set -euo pipefail

dir="${1:-$(cd "$(dirname "$0")/.." && pwd)/site}"
dir="${dir%/}"
en="$dir/index.html"
ko="$dir/ko/index.html"
css="$dir/assets/site.css"
base="https://devch.co.kr/barnook/"
inline_script="document.documentElement.className='js'"
font="$dir/assets/fonts/PretendardVariable.woff2"
font_size=2057688
font_sha=9599f12fd42fc0bce1cd50b47a0c022e108d7aa64dd0d1bb0ed44f3282d900b4
license="$dir/assets/fonts/LICENSE.txt"
license_size=4419
license_sha=b04538c9abec39a3db75108cf0af0fd9c77032fe8aa2cf38345b4d250e98e38e

fail() { echo "check-site: $*" >&2; exit 1; }

# Print capture group 1 (and 2, space-separated, when present) of every match of $1 in file $2.
scan() { PAT="$1" perl -0ne 'while (/$ENV{PAT}/g) { print join(" ", grep { defined } ($1, $2)), "\n" }' "$2"; }
# Count literal occurrences of $1 in file $2.
count() { S="$1" perl -0ne '$c = () = /\Q$ENV{S}\E/g; print $c' "$2"; }
# Count opening <$1> tags in file $2 (whole tag name, so "li" does not match <link>).
count_tag() { T="$1" perl -0ne '$c = () = /<\Q$ENV{T}\E(?=[\s>])/g; print $c' "$2"; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
# A local path, relative to directory $1, that must exist; a directory means its index.html.
resolves() {
  local path="$1/$2"
  [[ -d "$path" ]] && path="${path%/}/index.html"
  [[ -f "$path" ]]
}
# Map a public site URL to its file under $dir.
url_file() {
  local rest="${1#"$base"}"
  [[ "$rest" != "$1" ]] || return 1
  local path="$dir/${rest%%[#?]*}"
  [[ -d "$path" ]] && path="${path%/}/index.html"
  printf '%s\n' "$path"
}

# (a) Both pages exist with their language.
[[ -f "$en" ]] || fail "(a) missing $en"
[[ -f "$ko" ]] || fail "(a) missing $ko"
grep -q '<html lang="en"' "$en" || fail '(a) index.html is not lang="en"'
grep -q '<html lang="ko"' "$ko" || fail '(a) ko/index.html is not lang="ko"'

# (b) Same element ids in the same order.
[[ "$(scan '\bid="([^"]+)"' "$en")" == "$(scan '\bid="([^"]+)"' "$ko")" ]] ||
  fail "(b) the id sequences of the en and ko pages differ"

# (c) Same number of sections, FAQ entries, cards, list items and buttons.
for tag in section details li; do
  [[ "$(count_tag "$tag" "$en")" == "$(count_tag "$tag" "$ko")" ]] ||
    fail "(c) the en and ko pages have a different number of <$tag>"
done
for marker in 'class="card"' 'class="btn'; do
  [[ "$(count "$marker" "$en")" == "$(count "$marker" "$ko")" ]] ||
    fail "(c) the en and ko pages have a different number of $marker"
done

# (d) Same external links in the same order.
external() { scan 'href="(https?:[^"]+)"' "$1" | grep -vF "$base" || true; }
[[ "$(external "$en")" == "$(external "$ko")" ]] || fail "(d) the external links of the en and ko pages differ"

# (e) Every local src/href resolves; url() in site.css resolves relative to assets/.
# Absolute and protocol-relative URLs are left to (f).
for page in "$en" "$ko"; do
  while IFS= read -r ref; do
    case "$ref" in ''|'#'*|//*|http:*|https:*|mailto:*|data:*) continue ;; esac
    ref="${ref%%[#?]*}"
    resolves "$(dirname "$page")" "$ref" || fail "(e) ${page#"$dir"/} links to missing $ref"
  done < <(scan '\b(?:src|href)="([^"]*)"' "$page")
done
while IFS= read -r ref; do
  case "$ref" in data:*|//*|http:*|https:*) continue ;; esac
  resolves "$dir/assets" "${ref%%[#?]*}" || fail "(e) site.css links to missing $ref"
done < <(scan 'url\(\s*["'"'"']?([^"'"'"')]+)' "$css")

# (f) Nothing loads from other hosts, and the only inline script is the js class swap.
# An absolute (http:, https:) or protocol-relative (//) URL is another host.
for page in "$en" "$ko"; do
  name="${page#"$dir"/}"
  foreign="$(perl -0ne '
    my $abs = qr/["\x27\s,=](?:https?:)?\/\//i;
    while (/<(?:script|img|iframe|source|video|audio|embed|object)\b[^>]*>/gi) {
      my $t = $&;
      while ($t =~ /(?:^|\s)(?:src|srcset|data)\s*=\s*("[^"]*"|\x27[^\x27]*\x27|\S+)/gi) { if ("=$1" =~ $abs) { print "$t\n"; last } }
    }
    while (/<link\b[^>]*>/gi) {
      my $t = $&;
      print "$t\n" if $t =~ /(?:^|\s)href\s*=\s*["\x27]?(?:https?:)?\/\//i && $t !~ /rel="(?:canonical|alternate)"/;
    }
  ' "$page")"
  [[ -z "$foreign" ]] || fail "(f) $name loads a third-party resource: $foreign"
  inline="$(perl -0ne 'while (/<script\b([^>]*)>(.*?)<\/script>/gis) { print "$2\n" unless $1 =~ /(?:^|\s)src\s*=/i }' "$page")"
  [[ "$(printf '%s' "$inline" | grep -c '')" == 1 ]] || fail "(f) $name must have exactly one inline script"
  [[ "$inline" == "$inline_script" ]] || fail "(f) $name has an unexpected inline script"
done
if perl -0ne 'exit((/url\(\s*["'"'"']?(?:https?:)?\/\//i || /\@import/i) ? 0 : 1)' "$css"; then
  fail "(f) site.css loads a third-party resource"
fi

# (j) The elements site.js drives are on both pages.
for page in "$en" "$ko"; do
  for id in stage displaySeg placementSeg optBox mbApps panel overflow deskHint caption; do
    grep -q "id=\"$id\"" "$page" || fail "(j) ${page#"$dir"/} lacks #$id, which site.js needs"
  done
  grep -q 'class="stage-scroll' "$page" || fail "(j) ${page#"$dir"/} lacks .stage-scroll, which site.js needs"
done

# (g) Canonical, alternates, Open Graph and required metadata.
for page in "$en" "$ko"; do
  name="${page#"$dir"/}"
  canonical="$(scan '<link rel="canonical" href="([^"]+)"' "$page")"
  [[ -n "$canonical" ]] || fail "(g) $name has no canonical link"
  [[ "$(url_file "$canonical" || true)" == "$page" ]] || fail "(g) $name canonical $canonical is not this page"
  [[ "$(scan '<meta property="og:url" content="([^"]+)"' "$page")" == "$canonical" ]] ||
    fail "(g) $name og:url differs from its canonical"
  image="$(scan '<meta property="og:image" content="([^"]+)"' "$page")"
  [[ -n "$image" && -f "$(url_file "$image" || true)" ]] || fail "(g) $name og:image ${image:-(none)} is missing"
  while read -r lang url; do
    file="$(url_file "$url" || true)"
    [[ -f "$file" ]] || fail "(g) $name alternate $lang $url is missing"
    case "$lang" in
      en) [[ "$file" == "$en" ]] || fail "(g) $name alternate en is not the en page" ;;
      ko) [[ "$file" == "$ko" ]] || fail "(g) $name alternate ko is not the ko page" ;;
    esac
  done < <(scan '<link rel="alternate" hreflang="([^"]+)" href="([^"]+)"' "$page")
  for required in 'property="og:type"' 'property="og:locale"' 'property="og:image:width"' \
    'property="og:image:height"' 'name="twitter:card"' 'name="description"'; do
    [[ "$(count "$required" "$page")" != 0 ]] || fail "(g) $name is missing $required"
  done
  [[ -n "$(scan '(<link rel="preload" href="[^"]*PretendardVariable\.woff2")' "$page")" ]] ||
    fail "(g) $name does not preload the font"
done
alternates() { scan '<link rel="alternate" hreflang="([^"]+)" href="([^"]+)"' "$1" | sort; }
[[ "$(alternates "$en")" == "$(alternates "$ko")" ]] || fail "(g) the alternate links of the en and ko pages differ"
for lang in en ko x-default; do
  alternates "$en" | grep -q "^$lang " || fail "(g) the alternate links lack $lang"
done

# (h) No leftovers from the mockup.
if leftover="$(grep -rIl -e 'mock-note' -e '목업' -e '../../Resources' "$dir")"; then
  fail "(h) mockup leftovers in: $leftover"
fi

# (i) The font and its license are the pinned, unmodified upstream files.
[[ "$(wc -c < "$font" | tr -d ' ')" == "$font_size" && "$(sha256 "$font")" == "$font_sha" ]] ||
  fail "(i) the font does not match its pinned size and sha256"
[[ "$(wc -c < "$license" | tr -d ' ')" == "$license_size" && "$(sha256 "$license")" == "$license_sha" ]] ||
  fail "(i) the font license does not match its pinned size and sha256"

echo "check-site: ok"
