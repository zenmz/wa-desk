import Foundation

// MARK: - Helpers murni (dites oleh --selftest)

let waHome = URL(string: "https://web.whatsapp.com/")!

/// "(3) WhatsApp" -> 3, "WhatsApp" -> 0. WhatsApp Web menaruh jumlah unread di judul halaman.
func unreadCount(_ title: String) -> Int {
    guard title.hasPrefix("("), let close = title.firstIndex(of: ")") else { return 0 }
    return Int(title[title.index(after: title.startIndex)..<close]) ?? 0
}

/// Buang id akun yang bukan UUID valid (UserDefaults bisa diedit/korup).
func validAccountIDs(_ raw: [String]) -> [String] {
    raw.filter { UUID(uuidString: $0) != nil }
}

/// Badge Dock: nil saat 0 supaya badge hilang, bukan menampilkan "0".
func badgeLabel(total: Int) -> String? { total > 0 ? String(total) : nil }

/// Hanya http(s) ke host selain web.whatsapp.com yang dibuka di browser default.
/// Skema lain (file, ssh, about:blank) dan URL tanpa host bukan external.
func isExternal(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = url.host?.lowercased() else { return false }
    return host != "web.whatsapp.com"
}

/// Nama file unik di dir: "a.jpg" → "a (1).jpg" → "a (2).jpg" … supaya download tidak menimpa. Nama disanitasi ke lastPathComponent (kosong → "download").
func uniqueURL(in dir: URL, name: String, exists: (URL) -> Bool) -> URL {
    let safeName = (name as NSString).lastPathComponent
    let name = ["", ".", "..", "/"].contains(safeName) ? "download" : safeName
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var candidate = dir.appendingPathComponent(name)
    var n = 1
    while exists(candidate) {
        candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
        n += 1
    }
    return candidate
}

/// Jangan tampilkan notifikasi kalau user sedang melihat window akun itu (hindari dobel).
func shouldNotify(appActive: Bool, windowKey: Bool) -> Bool { !(appActive && windowKey) }

// MARK: Tweaks

let tagPalette = ["#34D399", "#60A5FA", "#F472B6", "#FBBF24", "#A78BFA", "#F87171"]

/// "22:00" → 1320, "7:5" → 425. Di luar 00:00–23:59 atau bukan angka → nil.
func minutesOfDay(_ hhmm: String) -> Int? {
    let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
          (0...23).contains(h), (0...59).contains(m) else { return nil }
    return h * 60 + m
}

func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
    let c = calendar.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

/// Jadwal senyap. Mati, jam invalid, atau start == end → tidak aktif. Rentang boleh lewat tengah malam.
func dndActive(minutesNow now: Int, start: String, end: String, enabled: Bool) -> Bool {
    guard enabled, let s = minutesOfDay(start), let e = minutesOfDay(end), s != e else { return false }
    return s < e ? (now >= s && now < e) : (now >= s || now < e)
}

/// Bookmark dari dict hasil __wadesk.capture(). Butuh id dan chat non-kosong; sisanya opsional.
func bookmark(fromCapture d: [String: Any], savedAt: Date) -> Bookmark? {
    guard let id = d["id"] as? String, !id.isEmpty,
          let chat = d["chat"] as? String, !chat.isEmpty else { return nil }
    return Bookmark(id: id, chat: chat, jid: d["jid"] as? String,
                    text: String((d["text"] as? String ?? "").prefix(300)),
                    time: d["time"] as? String ?? "",
                    fromMe: d["fromMe"] as? Bool ?? false, savedAt: savedAt)
}

func tagColorValid(_ hex: String) -> Bool { tagPalette.contains(hex) }

func tagNameValid(_ name: String) -> Bool {
    let t = name.trimmingCharacters(in: .whitespaces)
    return (1...24).contains(t.count) && !t.contains("\n")
}

/// Judul chat → warna tag pertama yang masih ada di daftar tag. Chat tanpa tag valid tidak masuk.
func tagMap(_ data: TagData) -> [String: String] {
    let colors = Dictionary(data.tags.map { ($0.name, $0.color) }, uniquingKeysWith: { a, _ in a })
    var out: [String: String] = [:]
    for (chat, names) in data.chats {
        if let c = names.lazy.compactMap({ colors[$0] }).first { out[chat] = c }
    }
    return out
}

/// WKWebView tidak punya window.Notification. Shim ini meneruskan ke native lewat message handler "notify".
let notificationShim = """
(() => {
  let seq = Date.now();
  const live = {};
  class Notification extends EventTarget {
    static get permission() { return "granted"; }
    static get maxActions() { return 0; }
    static requestPermission(cb) { if (cb) cb("granted"); return Promise.resolve("granted"); }
    constructor(title, opts = {}) {
      super();
      Object.assign(this, { body: "", tag: "", icon: "", data: null, silent: false }, opts);
      this.title = String(title);
      this.onclick = null; this.onclose = null; this.onshow = null; this.onerror = null;
      this._id = String(++seq);
      live[this._id] = this;
      try {
        window.webkit.messageHandlers.notify.postMessage({
          id: this._id, title: this.title,
          body: this.body == null ? "" : String(this.body),
          tag: this.tag == null ? "" : String(this.tag)
        });
      } catch (e) {}
    }
    close() { delete live[this._id]; this.dispatchEvent(new Event("close")); if (this.onclose) this.onclose(); }
  }
  window.Notification = Notification;
  window.__waNotifClick = (id) => {
    const n = live[id]; if (!n) return;
    const ev = new Event("click"); n.dispatchEvent(ev); if (n.onclick) n.onclick(ev);
  };
})();
"""

