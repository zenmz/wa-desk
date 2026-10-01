import AppKit
import Foundation
import Carbon.HIToolbox

// MARK: - Model

struct Bookmark: Codable, Equatable {
    var id: String        // data-id pesan WhatsApp, unik
    var chat: String      // judul chat saat disimpan
    var jid: String?      // 628xxx@c.us / 1203xxx@g.us, dari data-id
    var text: String      // ≤ 300 karakter
    var time: String      // "[HH:MM, D/M/YYYY]" apa adanya, atau ""
    var fromMe: Bool
    var savedAt: Date
}

struct Tag: Codable, Equatable {
    var name: String
    var color: String     // salah satu tagPalette
}

struct TagData: Codable, Equatable {
    var tags: [Tag] = []
    var chats: [String: [String]] = [:]   // judul chat → nama tag
}

// MARK: - Setting (UserDefaults, berlaku semua akun)

enum TweakSettings {
    private static let d = UserDefaults.standard
    static var blur: Bool {
        get { d.bool(forKey: "blur") }
        set { d.set(newValue, forKey: "blur") }
    }
    static var hideBanner: Bool {
        get { d.object(forKey: "hideBanner") as? Bool ?? true }
        set { d.set(newValue, forKey: "hideBanner") }
    }
    static var dndEnabled: Bool {
        get { d.bool(forKey: "dndEnabled") }
        set { d.set(newValue, forKey: "dndEnabled") }
    }
    /// Jam diubah lewat `defaults write dev.zen.wa dndStart 23:30` (tanpa UI).
    static var dndStart: String { d.string(forKey: "dndStart") ?? "22:00" }
    static var dndEnd: String { d.string(forKey: "dndEnd") ?? "07:00" }
}

// MARK: - Store per akun

/// Bookmark + tag satu akun, JSON di ~/Library/Application Support/wa-desk/<accountId>/.
final class TweakStore {
    let dir: URL
    private(set) var bookmarks: [Bookmark] = []
    private(set) var tags = TagData()
    /// Dipanggil setelah tiap simpan (panel bookmark memakai ini untuk reload).
    var onChange: (() -> Void)?

    init(accountID: String,
         base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        dir = base.appendingPathComponent("wa-desk").appendingPathComponent(accountID)
        bookmarks = load("bookmarks.json") ?? []
        tags = load("tags.json") ?? TagData()
    }

    /// Id sama → bookmark lama diganti. Terbaru di depan.
    func add(_ b: Bookmark) {
        bookmarks.removeAll { $0.id == b.id }
        bookmarks.insert(b, at: 0)
        save("bookmarks.json", bookmarks)
    }

    func remove(bookmarkID id: String) {
        bookmarks.removeAll { $0.id == id }
        save("bookmarks.json", bookmarks)
    }

    func update(_ change: (inout TagData) -> Void) {
        change(&tags)
        save("tags.json", tags)
    }

    private func load<T: Decodable>(_ name: String) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // File korup: simpan sebagai .bak supaya tidak hilang, mulai kosong.
            let bak = dir.appendingPathComponent("\(name).bak-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: bak)
            FileHandle.standardError.write(Data("\(name) korup, dipindah ke \(bak.lastPathComponent): \(error)\n".utf8))
            return nil
        }
    }

    private func save<T: Encodable>(_ name: String, _ value: T) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(value).write(to: dir.appendingPathComponent(name), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("simpan \(name) gagal: \(error)\n".utf8))
        }
        onChange?()
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - Lapisan inject (satu-satunya tempat yang tahu DOM WhatsApp)

/// Isi ~/.config/wa-desk/custom.css, atau nil kalau tidak ada.
func customCSS() -> String? {
    try? String(contentsOfFile: NSHomeDirectory() + "/.config/wa-desk/custom.css", encoding: .utf8)
}

/// String Swift → literal string JS yang aman (lewat JSON).
func jsStringLiteral(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s])
    return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
}

let tweaksStyle = """
html[data-wadesk-blur="1"] #pane-side, html[data-wadesk-blur="1"] #main { filter: blur(9px); transition: filter .15s; }
html[data-wadesk-blur="1"] #pane-side:hover, html[data-wadesk-blur="1"] #main:hover { filter: none; }
html[data-wadesk-hide-banner="1"] [data-wadesk-banner="1"] { display: none !important; }
#pane-side [role="listitem"][data-wadesk-tag]:not([data-wadesk-tag=""])::after {
  content: ""; position: absolute; right: 12px; top: 10px; width: 9px; height: 9px;
  border-radius: 50%; background: var(--wadesk-tag); pointer-events: none; }
html[data-wadesk-filter]:not([data-wadesk-filter=""]) #pane-side [role="listitem"][data-wadesk-match="0"] { opacity: .25; }
.wadesk-flash { outline: 3px solid #34D399; outline-offset: 2px; border-radius: 8px; }
#wadesk-toast { position: fixed; left: 50%; bottom: 28px; transform: translateX(-50%); background: #111827;
  color: #fff; padding: 8px 14px; border-radius: 8px; font: 13px -apple-system, sans-serif;
  z-index: 2147483647; opacity: 0; transition: opacity .15s; pointer-events: none; }
#wadesk-toast.show { opacity: .95; }
"""

/// Skrip inject. Harus bisa dievaluasi tanpa DOM (selftest di JSContext): semua akses DOM ada di dalam fungsi
/// atau di belakang guard `hasDOM`.
let tweaksScript = "const WADESK_STYLE = \(jsStringLiteral(tweaksStyle));\n" + #"""
(() => {
  const root = typeof window !== "undefined" ? window : globalThis;
  if (root.__wadesk) return;
  const hasDOM = typeof document !== "undefined";
  const W = { hovered: null, tags: {}, filter: "", toastTimer: 0, lastChat: "" };
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const html = () => document.documentElement;
  const BIG = '#pane-side, #main, [role="listitem"], [data-testid="link-device-qr-code"]';
  const BANNER_BTN = 'button[data-testid^="download-native-client-button"]';

  function ensureStyle(id, css) {
    let el = document.getElementById(id);
    if (!el) { el = document.createElement("style"); el.id = id; (document.head || html()).appendChild(el); }
    el.textContent = css;
  }
  function rowTitle(row) { const s = row.querySelector("span[title]"); return s ? s.getAttribute("title") : null; }

  function applyTags() {
    for (const row of $$('#pane-side [role="listitem"]')) {
      const t = rowTitle(row);
      const color = (t && W.tags[t]) || "";
      if (row.dataset.wadeskTag !== color) {
        row.dataset.wadeskTag = color;
        row.style.setProperty("--wadesk-tag", color);
        // Jangkar untuk titik ::after: hanya kalau baris belum punya posisi sendiri (daftar WA tervirtualisasi, baris absolute).
        if (color && getComputedStyle(row).position === "static") row.style.position = "relative";
      }
      const match = (!W.filter || color === W.filter) ? "1" : "0";
      if (row.dataset.wadeskMatch !== match) row.dataset.wadeskMatch = match;
    }
  }

  // Naik dari tombol download ke leluhur tertinggi yang masih "kartu banner":
  // tidak memuat daftar chat / panel pesan / QR, dan hanya punya satu tombol download.
  function markBanner() {
    for (const btn of $$(BANNER_BTN)) {
      let top = btn;
      for (let i = 0; i < 8; i++) {
        const p = top.parentElement;
        if (!p || p === document.body || p.id === "app" || p.matches(BIG) || p.querySelector(BIG) || p.querySelectorAll(BANNER_BTN).length !== 1) break;
        top = p;
      }
      if (top.dataset.wadeskBanner !== "1") top.dataset.wadeskBanner = "1";
    }
  }

  function capture() {
    const el = W.hovered;
    if (!el || !el.isConnected) return null;
    const id = el.getAttribute("data-id") || "";
    const parts = id.split("_");
    const header = $('#main header span[title]');
    const pre = el.querySelector("[data-pre-plain-text]");
    const m = pre ? /^\[([^\]]*)\]/.exec(pre.getAttribute("data-pre-plain-text") || "") : null;
    const textEl = pre || el.querySelector(".selectable-text") || el;
    return { id, chat: header ? header.getAttribute("title") : "", jid: parts[1] || null,
             text: (textEl.innerText || "").trim().slice(0, 300), time: m ? "[" + m[1] + "]" : "",
             fromMe: parts[0] === "true" };
  }

  function currentChat() {
    const header = $('#main header span[title]');
    if (!header) return null;
    const any = $('#main div[data-id]');
    return { title: header.getAttribute("title"), jid: any ? (any.getAttribute("data-id").split("_")[1] || null) : null };
  }

  function click(el) {
    for (const t of ["mousedown", "mouseup", "click"]) el.dispatchEvent(new MouseEvent(t, { bubbles: true, cancelable: true, view: window }));
  }

  function openChat(title, jid) {
    const span = $$('#pane-side span[title]').find(s => s.getAttribute("title") === title);
    if (span) { click(span.closest('[role="listitem"]') || span); return "clicked"; }
    if (jid && /@c\.us$/.test(jid)) { location.href = "https://web.whatsapp.com/send?phone=" + jid.replace(/@c\.us$/, ""); return "navigated"; }
    return "missing";
  }

  function jumpTo(id, title) {
    return new Promise(resolve => {
      const t0 = Date.now();
      const tick = () => {
        const header = $('#main header span[title]');
        if (header && header.getAttribute("title") === title) {
          const msg = $('#main div[data-id="' + CSS.escape(id) + '"]');
          if (!msg) return resolve(false);
          msg.scrollIntoView({ block: "center" });
          msg.classList.add("wadesk-flash");
          setTimeout(() => msg.classList.remove("wadesk-flash"), 2000);
          return resolve(true);
        }
        if (Date.now() - t0 > 3000) return resolve(false);
        setTimeout(tick, 100);
      };
      tick();
    });
  }

  function toast(msg) {
    let el = document.getElementById("wadesk-toast");
    if (!el) { el = document.createElement("div"); el.id = "wadesk-toast"; document.body.appendChild(el); }
    el.textContent = msg;
    el.classList.add("show");
    clearTimeout(W.toastTimer);
    W.toastTimer = setTimeout(() => el.classList.remove("show"), 1600);
  }

  function debug() {
    return { paneSide: !!$('#pane-side'), main: !!$('#main'), rows: $$('#pane-side [role="listitem"]').length,
             messages: $$('#main div[data-id]').length, bannerButtons: $$(BANNER_BTN).length, hovered: !!W.hovered };
  }

  function safe(fn, fallback) { return (...a) => { try { return fn(...a); } catch (e) { return fallback; } }; }

  root.__wadesk = {
    capture: safe(capture, null),
    currentChat: safe(currentChat, null),
    openChat: safe(openChat, "missing"),
    jumpTo: (id, title) => jumpTo(id, title).catch(() => false),
    toast: safe(toast, undefined),
    debug: safe(debug, null),
    setTags: safe(map => { W.tags = map || {}; applyTags(); }, undefined),
    setFilter: safe(color => { W.filter = color || ""; html().dataset.wadeskFilter = W.filter; applyTags(); }, undefined),
    setBlur: safe(on => { html().dataset.wadeskBlur = on ? "1" : ""; }, undefined),
    setHideBanner: safe(on => { html().dataset.wadeskHideBanner = on ? "1" : ""; markBanner(); }, undefined),
    setCustomCSS: safe(css => { ensureStyle("wadesk-custom", css || ""); }, undefined),
  };

  if (!hasDOM) return;
  ensureStyle("wadesk", WADESK_STYLE);
  document.addEventListener("mouseover", e => {
    const m = e.target && e.target.closest && e.target.closest('#main div[data-id]');
    if (m) W.hovered = m;
  }, true);
  let pending = false;
  new MutationObserver(() => {
    if (pending) return;
    pending = true;
    setTimeout(() => {
      pending = false; markBanner(); applyTags();
      const cc = currentChat(); const t = cc ? cc.title : "";
      if (t !== W.lastChat) {
        W.lastChat = t;
        try { window.webkit.messageHandlers.wadesk.postMessage({ chat: t }); } catch (e) {}
      }
    }, 250);
  }).observe(document.documentElement, { childList: true, subtree: true });
  markBanner();
  applyTags();
})();
"""#

// MARK: - Hotkey global

/// ⌥⌘W lewat Carbon RegisterEventHotKey: jalan tanpa izin Accessibility.
enum GlobalHotkey {
    private static var ref: EventHotKeyRef?
    private static var action: (() -> Void)?

    static func register(_ handler: @escaping () -> Void) {
        action = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            GlobalHotkey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: 0x5741_444B, id: 1)   // 'WADK'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(cmdKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            FileHandle.standardError.write(Data("hotkey ⌥⌘W gagal didaftar: \(status)\n".utf8))
        }
    }
}

// MARK: - Warna tag untuk menu

func nsColor(hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
    return NSColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// Lingkaran warna 14×14 untuk item menu.
func swatch(_ hex: String) -> NSImage {
    NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
        nsColor(hex: hex).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
    }
}
