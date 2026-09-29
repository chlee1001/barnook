// BarNook website: the interactive menu bar demo and the language link.
// The page is complete without this file; the idle demo is pre-rendered in the HTML.
"use strict";

// Text the demo generates. Korean templates never attach a particle to an
// interpolated name or number.
const STRINGS = {
  en: {
    iconTitle: shown => `BarNook — click to ${shown ? "hide" : "show"} hidden apps`,
    moreTitle: "Items macOS could not fit",
    pinTitle: (name, pinned) => `${name} — click to ${pinned ? "unpin" : "pin"}`,
    hintIdle: opt => `Click the <b>BarNook icon</b> in the menu bar${opt ? " (Option is held: always-hidden apps come too)" : ""}.`,
    hintCountdown: s => `Hiding again in <b>${s}s</b> · click the desktop to hide now`,
    captionCollapsed: n => `macOS collapsed ${n} items and the BarNook icon behind «. Open « to reach the icon. On a notch display, "Show in a bar below" avoids this.`,
    captionEscalated: "A pin didn't fit next to the notch, so BarNook hid every other app while the pins are up. Click the icon to bring the bar back, and again to hide everything.",
    captionPinned: names => `Pinned ${names.join(", ")}. Click the item in the menu bar as you would any other. Pins stay until you hide the set.`,
    captionBar: "The menu bar stays as it is. Click an app in the bar to pin its item into the menu bar, up to three at once.",
    captionMenubar: "Hidden apps are back in the menu bar. They're hidden again when you click the icon, click the desktop, or wait 15 seconds.",
    captionIdle: (hidden, always, stay, notch) => `${notch ? "This MacBook has a notch. " : ""}Hidden: ${hidden} apps, plus ${always} always hidden. In the menu bar: ${stay}.`,
  },
  ko: {
    iconTitle: shown => `BarNook — 클릭하면 숨긴 앱을 ${shown ? "다시 숨깁니다" : "보여 줍니다"}`,
    moreTitle: "macOS가 메뉴 막대에 다 넣지 못한 항목",
    pinTitle: (name, pinned) => `${name} — 클릭하면 ${pinned ? "고정을 풉니다" : "메뉴 막대에 고정합니다"}`,
    hintIdle: opt => `메뉴 막대의 <b>BarNook 아이콘</b>을 클릭하세요${opt ? " (Option 키를 누른 상태라 항상 숨김 앱도 함께 나옵니다)" : ""}.`,
    hintCountdown: s => `<b>${s}초</b> 뒤에 다시 숨겨집니다 · 데스크탑을 클릭하면 바로 숨겨집니다`,
    captionCollapsed: n => `macOS가 항목 ${n}개와 BarNook 아이콘을 « 뒤로 접었습니다. 아이콘을 누르려면 먼저 « 버튼을 열어야 합니다. 노치가 있는 화면에서는 "아래 막대에 표시"를 고르면 이런 일이 생기지 않습니다.`,
    captionEscalated: "고정한 항목이 노치 옆에 다 들어가지 않아서, 고정이 풀릴 때까지 BarNook이 나머지 앱을 모두 숨겼습니다. 아이콘을 클릭하면 막대가 다시 열리고, 한 번 더 클릭하면 전부 숨겨집니다.",
    captionPinned: names => `고정한 앱: ${names.join(", ")}. 메뉴 막대에서 해당 항목을 평소처럼 클릭해 쓰면 됩니다. 앱을 다시 숨기면 고정도 풀립니다.`,
    captionBar: "메뉴 막대는 그대로입니다. 아래 막대에서 앱을 클릭하면 그 앱의 항목이 메뉴 막대에 고정됩니다(최대 3개).",
    captionMenubar: "숨긴 앱이 메뉴 막대에 다시 나타났습니다. 아이콘이나 데스크탑을 클릭하거나 15초가 지나면 다시 숨겨집니다.",
    captionIdle: (hidden, always, stay, notch) => `${notch ? "노치가 있는 MacBook입니다. " : ""}숨긴 앱 ${hidden}개, 항상 숨김 ${always}개. 메뉴 막대에 남은 앱은 ${stay}개입니다.`,
  },
};
const T = STRINGS[document.documentElement.lang];

// Demo apps in menu bar order, right to left after the system items. The names are made up.
const APPS = [
  { id: "syncly",  name: "Syncly",  letter: "S", color: "#3b82f6", set: "shown" },
  { id: "gauge",   name: "Gauge",   letter: "G", color: "#10b981", set: "hidden" },
  { id: "tunnel",  name: "Tunnel",  letter: "T", color: "#6366f1", set: "shown" },
  { id: "clipsy",  name: "Clipsy",  letter: "C", color: "#f59e0b", set: "hidden" },
  { id: "pomo",    name: "Pomo",    letter: "P", color: "#ef4444", set: "hidden" },
  { id: "skycast", name: "Skycast", letter: "K", color: "#0ea5e9", set: "hidden" },
  { id: "pingo",   name: "Pingo",   letter: "I", color: "#8b5cf6", set: "hidden" },
  { id: "jotter",  name: "Jotter",  letter: "J", color: "#ca8a04", set: "hidden" },
  { id: "keyring", name: "Keyring", letter: "R", color: "#64748b", set: "always" },
  { id: "juice",   name: "Juice",   letter: "U", color: "#22c55e", set: "always" },
];
// How many menu bar slots fit right of the notch (notch) or right of the app
// menus (plain) on the 760px stage. Fixed rather than measured, so the demo
// behaves the same in both languages and before and after the font loads.
const CAPACITY = { notch: 4, plain: 12 };
const PIN_LIMIT = 3, TIMEOUT = 15;
const NOOK = '<svg width="16" height="16" viewBox="0 0 16 16"><path d="M2.5 4.6h11M4.4 13V8.4a3.6 3.6 0 0 1 7.2 0V13" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><rect x="6.8" y="9.6" width="2.4" height="2.4" rx=".6" fill="currentColor"/></svg>';
const CHEVRON = '<svg width="16" height="16" viewBox="0 0 16 16"><path d="M10 3.5 5.5 8l4.5 4.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

const $ = id => document.getElementById(id);
const byId = id => APPS.find(a => a.id === id);
const countOf = set => APPS.filter(a => a.set === set).length;
const chip = (a, fresh) => `<span class="it${fresh ? " new" : ""}" style="background:${a.color}" title="${a.name}">${a.letter}</span>`;
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");

let display = "notch", placement = "bar", placementChosen = false;
let shown = false, withAlways = false, panelOpen = false, pins = [];
let timer = null, remaining = 0, overflowOpen = false;
// The idle chips are already in the HTML, so the first render doesn't pop them in.
let lastVisible = new Set(APPS.filter(a => a.set === "shown").map(a => a.id));

// What macOS draws, right to left: the allowed apps in their positions, then the BarNook icon.
function layout() {
  const inMenuBar = set => set === "shown" || (shown && placement === "menubar" && (set === "hidden" || (set === "always" && withAlways)));
  let apps = APPS.filter(a => inMenuBar(a.set) || pins.includes(a.id));
  const cap = CAPACITY[display];
  let escalated = false;
  if (pins.length && apps.length + 1 > cap) {
    apps = apps.filter(a => pins.includes(a.id));
    escalated = true;
  }
  let items = [...apps.map(a => ({ app: a })), { icon: true }];
  let collapsed = 0;
  if (items.length > cap) {
    collapsed = items.length - (cap - 1);
    items = [...items.slice(0, cap - 1), { more: true }];
  }
  return { items, collapsed, escalated, iconCollapsed: !items.some(i => i.icon) };
}

function panelApps() {
  const always = withAlways ? APPS.filter(a => a.set === "always") : [];
  return { always, hidden: APPS.filter(a => a.set === "hidden") };
}

// Scroll the phone-width stage so the element is fully in view.
function ensureVisible(el) {
  const scroller = document.querySelector(".stage-scroll");
  if (!el || !scroller || scroller.scrollWidth <= scroller.clientWidth) return;
  const margin = 8, r = el.getBoundingClientRect(), s = scroller.getBoundingClientRect();
  let delta = 0;
  if (r.left < s.left + margin) delta = r.left - s.left - margin;
  else if (r.right > s.right - margin) delta = r.right - s.right + margin;
  if (delta) scroller.scrollBy({ left: delta, behavior: reducedMotion.matches ? "auto" : "smooth" });
}

function render() {
  $("stage").classList.toggle("plain", display === "plain");
  const L = layout();
  const visible = new Set(L.items.filter(i => i.app).map(i => i.app.id));
  $("mbApps").innerHTML = L.items.map(i => {
    if (i.icon) return `<button type="button" class="bn${shown ? " on" : ""}" id="bnIcon" title="${T.iconTitle(shown)}">${shown ? CHEVRON : NOOK}</button>`;
    if (i.more) return `<button type="button" class="more" id="moreBtn" title="${T.moreTitle}">«</button>`;
    return chip(i.app, !lastVisible.has(i.app.id));
  }).join("");
  lastVisible = visible;
  if (!L.iconCollapsed) overflowOpen = false;
  const hiddenByMacOS = APPS.filter(a => !visible.has(a.id) && (a.set === "shown" || shown && (a.set === "hidden" || (a.set === "always" && withAlways))));
  $("overflow").innerHTML = hiddenByMacOS.map(a => `<div>${chip(a, false)}${a.name}</div>`).join("") + `<div class="bn-row" id="overflowIcon">${NOOK} BarNook</div>`;
  $("overflow").classList.toggle("off", !overflowOpen);

  const { always, hidden } = panelApps();
  const cell = a => `<button type="button" data-pin="${a.id}" class="${pins.includes(a.id) ? "pinned" : ""}" title="${T.pinTitle(a.name, pins.includes(a.id))}">${chip(a, false)}</button>`;
  $("panel").innerHTML = always.map(cell).join("") + (always.length ? '<div class="sep"></div>' : "") + hidden.map(cell).join("");
  const barOpen = placement === "bar" && panelOpen;
  $("panel").classList.toggle("off", !barOpen);
  requestAnimationFrame(() => {
    const icon = $("bnIcon");
    if (!icon) return;
    const r = icon.getBoundingClientRect(), s = $("stage").getBoundingClientRect();
    $("panel").style.left = `${Math.max(8, r.right - s.left - $("panel").offsetWidth + 4)}px`;
    if (barOpen) ensureVisible($("panel"));
  });
  if (overflowOpen) ensureVisible($("overflow"));

  $("deskHint").innerHTML = !shown
    ? T.hintIdle(withAlways || $("optBox").checked)
    : remaining > 0 && !pins.length ? T.hintCountdown(remaining) : "";
  // The caption is a live region: assign it only when the words change.
  const text = caption(L);
  if ($("caption").textContent !== text) $("caption").textContent = text;
  document.querySelectorAll("#displaySeg button").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.v === display)));
  document.querySelectorAll("#displaySeg button").forEach(b => b.classList.toggle("on", b.dataset.v === display));
  document.querySelectorAll("#placementSeg button").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.v === placement)));
  document.querySelectorAll("#placementSeg button").forEach(b => b.classList.toggle("on", b.dataset.v === placement));
}

function caption(L) {
  if (L.iconCollapsed) return T.captionCollapsed(L.collapsed - 1);
  if (L.escalated) return T.captionEscalated;
  if (pins.length) return T.captionPinned(pins.map(id => byId(id).name));
  if (shown && placement === "bar") return T.captionBar;
  if (shown) return T.captionMenubar;
  return T.captionIdle(countOf("hidden"), countOf("always"), countOf("shown"), display === "notch");
}

function startTimer() {
  stopTimer();
  if (pins.length) return;
  remaining = TIMEOUT;
  timer = setInterval(() => {
    remaining -= 1;
    if (remaining <= 0) hideAll(); else render();
  }, 1000);
}
function stopTimer() { clearInterval(timer); timer = null; remaining = 0; }
function hideAll() { shown = false; withAlways = false; panelOpen = false; overflowOpen = false; pins = []; stopTimer(); render(); }

function clickIcon(alt) {
  if (placement === "bar") {
    if (panelOpen) return hideAll();
    if (shown) { panelOpen = true; return render(); }
    shown = true; withAlways = alt; panelOpen = true;
  } else {
    if (shown) return hideAll();
    shown = true; withAlways = alt;
  }
  startTimer();
  render();
}

function togglePin(id) {
  if (pins.includes(id)) pins = pins.filter(p => p !== id);
  else { pins.push(id); if (pins.length > PIN_LIMIT) pins.shift(); }
  panelOpen = false;
  if (pins.length) stopTimer(); else startTimer();
  render();
}

$("stage").addEventListener("click", e => {
  if (e.target.closest("#bnIcon")) return clickIcon(e.altKey || $("optBox").checked);
  if (e.target.closest("#moreBtn")) { overflowOpen = !overflowOpen; return render(); }
  if (e.target.closest("#overflowIcon")) { overflowOpen = false; return clickIcon(e.altKey || $("optBox").checked); }
  const pin = e.target.closest("[data-pin]");
  if (pin) return togglePin(pin.dataset.pin);
  if (e.target.closest("#mb") || e.target.closest("#panel") || e.target.closest("#overflow")) return;
  if (panelOpen && pins.length) { panelOpen = false; render(); }
  else if (shown && !pins.length) hideAll();
});
$("displaySeg").addEventListener("click", e => {
  const b = e.target.closest("button"); if (!b) return;
  display = b.dataset.v;
  if (!placementChosen) placement = display === "notch" ? "bar" : "menubar";
  hideAll();
});
$("placementSeg").addEventListener("click", e => {
  const b = e.target.closest("button"); if (!b) return;
  placement = b.dataset.v; placementChosen = true;
  hideAll();
});
$("optBox").addEventListener("change", render);

// Keep the section the reader is on when switching language.
document.querySelectorAll("a.lang").forEach(a => {
  const base = a.getAttribute("href");
  a.addEventListener("click", () => { a.setAttribute("href", base + location.hash); });
});

// On a phone the stage is wider than the screen; start at the right end, where the icon is.
const scroller = document.querySelector(".stage-scroll");
scroller.scrollLeft = scroller.scrollWidth;
render();
