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

