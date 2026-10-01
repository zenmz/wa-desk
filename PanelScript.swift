import Foundation

// MARK: - Panel WA Desk di halaman: icon di bilah navigasi + popover. Hanya merender state dari native.

let panelStyle = """
#wadesk-panel { position: fixed; z-index: 2147483646; width: 320px; max-height: 80vh; overflow: auto; border-radius: 12px;
  box-shadow: 0 12px 40px rgba(0,0,0,.35); font: 13px -apple-system, "Segoe UI", sans-serif; padding: 10px 0 8px;
  background: #fff; color: #111b21; border: 1px solid rgba(0,0,0,.08); }
#wadesk-panel.wd-dark { background: #202c33; color: #e9edef; border-color: rgba(255,255,255,.08); }
#wadesk-panel .wd-h { font-weight: 600; font-size: 15px; padding: 2px 14px 8px; display: flex; justify-content: space-between; align-items: baseline; }
#wadesk-panel .wd-sec { font-size: 11px; text-transform: uppercase; letter-spacing: .06em; opacity: .6; padding: 10px 14px 4px; }
#wadesk-panel .wd-sub { font-size: 12px; opacity: .8; padding: 8px 14px 2px; }
#wadesk-panel .wd-muted { opacity: .55; font-weight: 400; font-size: 12px; }
#wadesk-panel .wd-row { display: flex; align-items: center; gap: 8px; padding: 6px 14px; cursor: default; }
#wadesk-panel .wd-row.wd-link, #wadesk-panel .wd-acc { cursor: pointer; }
#wadesk-panel .wd-row.wd-link:hover, #wadesk-panel .wd-acc:hover { background: rgba(0,0,0,.05); }
#wadesk-panel.wd-dark .wd-row.wd-link:hover, #wadesk-panel.wd-dark .wd-acc:hover { background: rgba(255,255,255,.06); }
#wadesk-panel .wd-row > span:first-child { flex: 1; }
#wadesk-panel .wd-danger { color: #ea4335; }
#wadesk-panel .wd-dot { width: 8px; height: 8px; border-radius: 50%; border: 1.5px solid currentColor; opacity: .35; flex: none; }
#wadesk-panel .wd-acc.on .wd-dot { background: #25d366; border-color: #25d366; opacity: 1; }
#wadesk-panel .wd-name { flex: 1; }
#wadesk-panel .wd-badge { background: #25d366; color: #fff; border-radius: 10px; padding: 0 7px; font-size: 11px; line-height: 18px; }
#wadesk-panel .wd-mini { border: 0; background: transparent; color: inherit; opacity: .6; cursor: pointer; font-size: 13px; padding: 2px 4px; }
#wadesk-panel .wd-mini:hover { opacity: 1; }
#wadesk-panel .wd-kbd { opacity: .5; font-size: 11px; margin-left: 6px; }
#wadesk-panel .wd-switch { appearance: none; -webkit-appearance: none; width: 34px; height: 20px; border-radius: 10px; background: rgba(128,128,128,.35); position: relative; cursor: pointer; flex: none; margin: 0; }
#wadesk-panel .wd-switch::after { content: ""; position: absolute; top: 2px; left: 2px; width: 16px; height: 16px; border-radius: 50%; background: #fff; transition: left .15s; }
#wadesk-panel .wd-switch:checked { background: #25d366; }
#wadesk-panel .wd-switch:checked::after { left: 16px; }
#wadesk-panel .wd-tag input { accent-color: #25d366; margin: 0; }
#wadesk-panel .wd-swatch { width: 10px; height: 10px; border-radius: 50%; flex: none; }
#wadesk-panel .wd-chips { display: flex; flex-wrap: wrap; gap: 6px; padding: 4px 14px 6px; }
#wadesk-panel .wd-chip { border: 1px solid rgba(128,128,128,.4); background: transparent; color: inherit; border-radius: 12px; padding: 2px 10px; font-size: 12px; cursor: pointer; }
#wadesk-panel .wd-chip.on { background: #25d366; border-color: #25d366; color: #fff; }
#wadesk-panel .wd-chip[style*="--c"] { border-color: var(--c); }
#wadesk-panel .wd-on { color: #25d366; }
.wadesk-nav-fallback { width: 40px; height: 40px; display: flex; align-items: center; justify-content: center; border-radius: 50%; cursor: pointer; color: inherit; margin: 4px auto; }
.wadesk-nav-fallback:hover { background: rgba(128,128,128,.15); }
"""

/// IIFE kedua, dijalankan setelah lapisan Tweaks. Memakai `__wadesk` yang sudah ada; tanpa DOM hanya mendaftarkan API.
let panelScript = #"""
(() => {
  const root = typeof window !== "undefined" ? window : globalThis;
  const hasDOM = typeof document !== "undefined";
  const api = root.__wadesk;
  if (!api || api.setPanelState) return;
  const P = { state: null, open: false };
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const post = (msg) => { try { window.webkit.messageHandlers.wadesk.postMessage(msg); } catch (e) {} };
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const safeColor = (c) => /^#[0-9a-f]{3,8}$/i.test(String(c || "")) ? String(c) : "";
  const ICON = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v7a2.5 2.5 0 0 1-2.5 2.5H9l-4.2 3.2V6.5z"/><path d="M8 9h8M8 12.5h5"/></svg>';

  function navSection() { return $('[data-testid="navbar-primary-section"]'); }
  // Item Meta AI = anak langsung section yang memuat elemen berlabel "Meta AI".
  function metaAIItem(sec) {
    const hit = $$('[aria-label], [title], button, [role="button"]', sec).find(e =>
      /meta ai/i.test((e.getAttribute("aria-label") || "") + " " + (e.getAttribute("title") || "") + " " + (e.textContent || "").slice(0, 40)));
    if (!hit) return null;
    let el = hit;
    while (el.parentElement && el.parentElement !== sec) el = el.parentElement;
    return el.parentElement === sec ? el : null;
  }
  function ensureNavIcon() {
    const sec = navSection();
    if (!sec) return;
    const existing = $('[data-wadesk-nav="1"]', sec);
    const meta = metaAIItem(sec);
    if (existing && !(existing.classList.contains("wadesk-nav-fallback") && meta)) return;
    if (existing) existing.remove();   // fallback → ganti dengan klon sekarang Meta AI ada
    let item = null;
    if (meta) {
      // Klon item Meta AI: class WhatsApp ikut (hover/active sama), listener tidak ikut; atribut identitas dibersihkan.
      const clone = meta.cloneNode(true);
      // Kalau "item" ternyata pembungkus seluruh bilah (lebih dari satu ikon), jangan dipakai.
      if (clone.querySelectorAll("svg").length <= 1 && clone.querySelectorAll('button, [role="button"]').length <= 1) {
        for (const el of [clone, ...$$("*", clone)]) {
          for (const a of Array.from(el.attributes)) {
            if (/^(id|data-testid|data-navbar-item|data-tab|aria-label|aria-selected|aria-pressed|aria-current|title|tabindex)$/i.test(a.name)) el.removeAttribute(a.name);
          }
        }
        const svg = clone.querySelector("svg");
        (svg ? svg.parentElement : clone).innerHTML = ICON;
        // Satu tab stop saja: elemen fokus bawaan di dalam klon dimatikan.
        for (const f of clone.querySelectorAll('button, a, [tabindex]')) f.tabIndex = -1;
        meta.insertAdjacentElement("afterend", clone);
        item = clone;
      }
    }
    if (!item) {
      item = document.createElement("div");
      item.className = "wadesk-nav-fallback";
      item.innerHTML = ICON;
      sec.appendChild(item);
    }
    item.dataset.wadeskNav = "1";
    item.setAttribute("role", "button");
    item.setAttribute("aria-label", "WA Desk");
    item.setAttribute("aria-expanded", "false");
    item.setAttribute("title", "WA Desk");
    item.tabIndex = 0;
    item.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); toggle(); }, true);
    item.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); } });
  }

  function luminance(el) {
    const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/.exec(getComputedStyle(el).backgroundColor || "");
    if (!m || (m[4] !== undefined && Number(m[4]) === 0)) return null;   // transparan → tidak ada info
    return (0.2126 * m[1] + 0.7152 * m[2] + 0.0722 * m[3]) / 255;
  }
  function isDark() {
    if (document.body.classList.contains("dark") || document.documentElement.classList.contains("dark")) return true;
    for (const el of [document.body, document.getElementById("app"), document.documentElement]) {
      const l = el ? luminance(el) : null;
      if (l !== null) return l < 0.5;
    }
    return matchMedia("(prefers-color-scheme: dark)").matches;
  }
  function ensurePanel() {
    let p = document.getElementById("wadesk-panel");
    if (!p) {
      p = document.createElement("div");
      p.id = "wadesk-panel";
      p.hidden = true;
      p.addEventListener("click", onClick);
      p.addEventListener("change", onChange);
      document.body.appendChild(p);
    }
    p.classList.toggle("wd-dark", isDark());
    return p;
  }
  function position(p) {
    const icon = $('[data-wadesk-nav="1"]');
    const sec = navSection();
    const r = (sec || icon || document.body).getBoundingClientRect();
    const ir = icon ? icon.getBoundingClientRect() : r;
    const left = Math.min(Math.round(r.right + 8), Math.max(8, window.innerWidth - p.offsetWidth - 8));
    p.style.left = left + "px";
    const maxTop = Math.max(8, window.innerHeight - p.offsetHeight - 8);
    p.style.top = Math.round(Math.min(Math.max(8, ir.top), maxTop)) + "px";
  }
  function toggleHTML(label, act, on, extra) {
    return '<label class="wd-row"><span>' + label + '</span><input type="checkbox" class="wd-switch" data-act="' + act + '"' + (on ? " checked" : "") + ">" + (extra || "") + "</label>";
  }
  function render() {
    const p = ensurePanel();
    const s = P.state;
    if (!s) { p.innerHTML = '<div class="wd-h">WA Desk</div><div class="wd-row wd-muted">Menunggu status…</div>'; return; }
    const accs = (s.accounts || []).map(a =>
      '<div class="wd-row wd-acc' + (a.active ? " on" : "") + '" data-act="switchAccount" data-id="' + esc(a.id) + '"><span class="wd-dot"></span><span class="wd-name">' + esc(a.name) + "</span>" +
      (a.unread ? '<span class="wd-badge">' + esc(a.unread) + "</span>" : "") +
      '<button class="wd-mini" data-act="renameAccount" data-id="' + esc(a.id) + '" title="Ganti nama">✎</button></div>').join("");
    const tags = (s.tags || []).map(t =>
      '<label class="wd-row wd-tag"><input type="checkbox" data-act="toggleTag" data-tag="' + esc(t.name) + '"' + (t.checked ? " checked" : "") + (s.hasOpenChat ? "" : " disabled") + '><span class="wd-swatch" style="background:' + safeColor(t.color) + '"></span>' + esc(t.name) + "</label>").join("");
    const chips = ['<button class="wd-chip' + (s.filter ? "" : " on") + '" data-act="setFilter" data-color="">Semua</button>']
      .concat((s.tags || []).map(t => '<button class="wd-chip' + (s.filter === t.color ? " on" : "") + '" data-act="setFilter" data-color="' + safeColor(t.color) + '" style="--c:' + safeColor(t.color) + '">' + esc(t.name) + "</button>")).join("");
    const mute = s.mute || {}, dnd = s.dnd || {};
    const muteStatus = mute.active ? '<span class="wd-on">● ' + esc(mute.label) + "</span>" : (dnd.active ? '<span class="wd-on">● jadwal</span>' : "");
    p.innerHTML =
      '<div class="wd-h">WA Desk <span class="wd-muted">' + esc(s.version) + "</span></div>" +
      '<div class="wd-sec">Akun</div>' + accs +
      '<div class="wd-row wd-link" data-act="newAccount">+ Akun baru <span class="wd-kbd">⌘N</span></div>' +
      '<div class="wd-row wd-link wd-danger" data-act="removeAccount">Hapus akun ini…</div>' +
      '<div class="wd-sec">Tweaks</div>' +
      toggleHTML('Blur Privasi <span class="wd-kbd">⇧⌘B</span>', "toggleBlur", s.blur) +
      toggleHTML("Sembunyikan banner download", "toggleBanner", s.hideBanner) +
      '<div class="wd-row wd-link" data-act="bookmark">Bookmark pesan yang di-hover <span class="wd-kbd">⌘D</span></div>' +
      '<div class="wd-row wd-link" data-act="showBookmarks">Tampilkan bookmark… <span class="wd-kbd">⇧⌘D</span></div>' +
      '<div class="wd-sub">Tag chat ini' + (s.hasOpenChat ? "" : ' <span class="wd-muted">(buka chat dulu)</span>') + "</div>" + tags +
      '<div class="wd-row wd-link" data-act="newTag">+ Tag baru…</div>' +
      '<div class="wd-sub">Filter tag</div><div class="wd-chips">' + chips + "</div>" +
      '<div class="wd-sub">Senyap ' + muteStatus + "</div>" +
      '<div class="wd-chips">' + (mute.active ? '<button class="wd-chip on" data-act="muteOff">Matikan</button>' : "") +
      '<button class="wd-chip" data-act="mute" data-min="30">30 mnt</button><button class="wd-chip" data-act="mute" data-min="60">1 jam</button>' +
      '<button class="wd-chip" data-act="mute" data-min="120">2 jam</button><button class="wd-chip" data-act="mute" data-min="0">∞</button></div>' +
      toggleHTML("Jadwal senyap " + esc(dnd.start) + "–" + esc(dnd.end), "toggleDND", dnd.enabled, '<button class="wd-mini" data-act="editDND" title="Atur jadwal">⚙</button>') +
      toggleHTML('Selalu di atas <span class="wd-kbd">⌥⌘T</span>', "toggleOnTop", s.onTop) +
      '<div class="wd-row wd-link" data-act="reloadCSS">Muat ulang CSS kustom</div>' +
      '<div class="wd-row wd-link" data-act="debug">Debug selector</div>';
    position(p);
  }
  function message(el) {
    const msg = { action: el.dataset.act };
    if (el.dataset.id != null) msg.id = el.dataset.id;
    if (el.dataset.tag != null) msg.tag = el.dataset.tag;
    if (el.dataset.color != null) msg.color = el.dataset.color;
    if (el.dataset.min != null) msg.min = Number(el.dataset.min);
    return msg;
  }
  function onClick(e) {
    const el = e.target.closest("[data-act]");
    if (!el || el.tagName === "INPUT") return;   // kotak centang ditangani onChange
    e.preventDefault(); e.stopPropagation();
    post(message(el));
    if (el.dataset.act === "switchAccount") toggle(false);
  }
  function onChange(e) {
    const el = e.target.closest("input[data-act]");
    if (el) post(message(el));
  }
  function toggle(force) {
    const p = ensurePanel();
    P.open = typeof force === "boolean" ? force : p.hidden;
    const icon = $('[data-wadesk-nav="1"]'); if (icon) icon.setAttribute("aria-expanded", P.open ? "true" : "false");
    if (P.open) { render(); p.hidden = false; position(p); post({ action: "panelOpen" }); }
    else { p.hidden = true; }
  }

  api.setPanelState = (state) => { try { P.state = state || null; if (P.open) render(); } catch (e) { console.warn("wadesk panel", e); } };
  api.openPanel = () => { try { toggle(true); } catch (e) { console.warn("wadesk panel", e); } };
  api.closePanel = () => { try { toggle(false); } catch (e) {} };

  if (!hasDOM) return;
  const st = document.createElement("style");
  st.id = "wadesk-panel-style";
  st.textContent = WADESK_PANEL_STYLE;
  (document.head || document.documentElement).appendChild(st);
  document.addEventListener("keydown", e => {
    if (e.key === "Escape" && P.open) { e.preventDefault(); e.stopPropagation(); toggle(false); }
  }, true);
  document.addEventListener("mousedown", e => {
    if (!P.open) return;
    const p = document.getElementById("wadesk-panel");
    if (p && !p.contains(e.target) && !(e.target.closest && e.target.closest('[data-wadesk-nav="1"]'))) toggle(false);
  }, true);
  let pending = false;
  new MutationObserver(() => {
    if (pending) return;
    pending = true;
    setTimeout(() => { pending = false; try { ensureNavIcon(); } catch (e) { console.warn("wadesk nav", e); } }, 500);
  }).observe(document.documentElement, { childList: true, subtree: true });
  try { ensureNavIcon(); } catch (e) {}
})();
"""#
