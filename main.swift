import Cocoa
import WebKit
import UserNotifications

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

// MARK: - Selftest

func selftest() -> Int32 {
    var failed: [String] = []
    func check(_ ok: Bool, _ name: String) { if !ok { failed.append(name) } }

    check(unreadCount("(3) WhatsApp") == 3, "unreadCount 3")
    check(unreadCount("(12) WhatsApp") == 12, "unreadCount 12")
    check(unreadCount("WhatsApp") == 0, "unreadCount none")
    check(unreadCount("") == 0, "unreadCount empty")
    check(unreadCount("(x) WhatsApp") == 0, "unreadCount non-numeric")

    let good = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    check(validAccountIDs([good, "abc", ""]) == [good], "validAccountIDs filters")
    check(validAccountIDs([]).isEmpty, "validAccountIDs empty")

    check(badgeLabel(total: 0) == nil, "badgeLabel nil saat 0")
    check(badgeLabel(total: 7) == "7", "badgeLabel 7")

    check(isExternal(URL(string: "https://web.whatsapp.com/")!) == false, "isExternal wa")
    check(isExternal(URL(string: "https://example.com/x")!) == true, "isExternal other")
    check(isExternal(URL(string: "https://wa.me/628")!) == true, "isExternal wa.me")
    check(isExternal(URL(string: "about:blank")!) == false, "isExternal no host")

    let dir = URL(fileURLWithPath: "/tmp/wa-selftest")
    let taken: Set<String> = ["a.jpg", "a (1).jpg", "noext"]
    let exists: (URL) -> Bool = { taken.contains($0.lastPathComponent) }
    check(uniqueURL(in: dir, name: "b.jpg", exists: exists).lastPathComponent == "b.jpg", "uniqueURL free")
    check(uniqueURL(in: dir, name: "a.jpg", exists: exists).lastPathComponent == "a (2).jpg", "uniqueURL suffix")
    check(uniqueURL(in: dir, name: "noext", exists: exists).lastPathComponent == "noext (1)", "uniqueURL no ext")
    check(isExternal(URL(string: "https://Web.WhatsApp.com/")!) == false, "isExternal case-insensitive host")
    check(uniqueURL(in: dir, name: "../../evil.jpg", exists: exists).lastPathComponent == "evil.jpg", "uniqueURL strips path")
    check(uniqueURL(in: dir, name: "../../evil.jpg", exists: exists).deletingLastPathComponent().path == dir.path, "uniqueURL stays in dir")
    check(uniqueURL(in: dir, name: "", exists: exists).lastPathComponent == "download", "uniqueURL empty name")
    check(isExternal(URL(string: "file://localhost/Applications/Calculator.app")!) == false, "isExternal file scheme")
    check(isExternal(URL(string: "HTTPS://EXAMPLE.COM/")!) == true, "isExternal uppercase scheme")
    check(uniqueURL(in: dir, name: "..", exists: exists).lastPathComponent == "download", "uniqueURL dotdot")
    check(uniqueURL(in: dir, name: "/", exists: exists).lastPathComponent == "download", "uniqueURL slash")
    check(shouldNotify(appActive: true, windowKey: true) == false, "shouldNotify ditekan saat dilihat")
    check(shouldNotify(appActive: true, windowKey: false) == true, "shouldNotify tab lain")
    check(shouldNotify(appActive: false, windowKey: true) == true, "shouldNotify app background")

    if failed.isEmpty { print("selftest OK"); return 0 }
    for f in failed { FileHandle.standardError.write(Data("FAIL: \(f)\n".utf8)) }
    return 1
}

if CommandLine.arguments.contains("--selftest") { exit(selftest()) }

// MARK: - Accounts

enum Accounts {
    private static let key = "accounts"
    private static let defaults = UserDefaults.standard

    /// Daftar id akun. Kalau kosong atau semua invalid, buat satu akun baru.
    static func all() -> [String] {
        var ids = validAccountIDs(defaults.stringArray(forKey: key) ?? [])
        if ids.isEmpty {
            ids = [UUID().uuidString]
            defaults.set(ids, forKey: key)
        }
        return ids
    }

    static func add() -> String {
        let id = UUID().uuidString
        defaults.set(all() + [id], forKey: key)
        return id
    }

    static func remove(_ id: String) {
        defaults.set(all().filter { $0 != id }, forKey: key)
    }

    // Akun yang datanya masih harus dihapus (gagal / keburu quit). Dicoba lagi tiap launch.
    private static let pendingKey = "pendingRemoval"

    static func pendingRemoval() -> [String] {
        validAccountIDs(defaults.stringArray(forKey: pendingKey) ?? [])
    }

    static func markPendingRemoval(_ id: String) {
        defaults.set(pendingRemoval() + [id], forKey: pendingKey)
    }

    static func clearPendingRemoval(_ id: String) {
        defaults.set(pendingRemoval().filter { $0 != id }, forKey: pendingKey)
    }
}


// MARK: - AccountWindow

final class AccountWindow: NSWindowController, NSWindowDelegate {
    let id: String
    let webView: WKWebView
    private(set) var unread = 0
    private var titleObservation: NSKeyValueObservation?

    init(id: String) {
        self.id = id
        let cfg = WKWebViewConfiguration()
        // Data store per akun: cookie, IndexedDB, dan sesi login terisolasi.
        cfg.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: id)!)
        // UA setara Safari supaya lolos cek browser WhatsApp Web.
        cfg.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.userContentController.addUserScript(WKUserScript(
            source: notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsMagnification = true

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: win)
        webView.configuration.userContentController.add(self, name: "notify")

        win.title = "WhatsApp"
        win.isReleasedWhenClosed = false
        win.tabbingMode = .preferred
        win.tabbingIdentifier = "wa"
        win.contentView = webView
        win.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        win.center()
        win.setFrameAutosaveName("win-\(id)")

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let title = wv.title ?? ""
            self.window?.title = title.isEmpty ? "WhatsApp" : title
            self.unread = unreadCount(title)
            (NSApp.delegate as? AppDelegate)?.refreshBadge()
        }
        webView.load(URLRequest(url: waHome))
    }

    required init?(coder: NSCoder) { fatalError("tidak dipakai") }

    deinit { titleObservation?.invalidate() }

    /// Tutup window = sembunyikan. Pesan tetap masuk. Keluar hanya lewat Cmd+Q.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}


// MARK: - Navigasi, download, media

extension AccountWindow: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { return decisionHandler(.download) }
        if let url = action.request.url, let scheme = url.scheme?.lowercased(), scheme == "mailto" || scheme == "tel" {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        if action.navigationType == .linkActivated, let url = action.request.url, isExternal(url) {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : (response.isForMainFrame ? .download : .cancel))
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        completionHandler(uniqueURL(in: dir, name: suggestedFilename) {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        FileHandle.standardError.write(Data("download gagal: \(error.localizedDescription)\n".utf8))
    }

    /// Proses WebContent mati (memory pressure, crash) → halaman kosong diam-diam. Muat ulang.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: waHome))
    }

    /// target=_blank / window.open: luar → browser default; web.whatsapp.com sendiri → muat di tab ini.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if isExternal(url) {
            NSWorkspace.shared.open(url)
        } else if url.host?.lowercased() == "web.whatsapp.com" {
            webView.load(action.request)
        }
        return nil
    }

    /// Kamera/mic untuk call. TCC macOS tetap prompt sekali (teks di Info.plist).
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == "web.whatsapp.com" ? .grant : .deny)
    }

    /// Tombol attach di WhatsApp → NSOpenPanel.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard let win = window else { return completionHandler(nil) }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: win) { completionHandler($0 == .OK ? panel.urls : nil) }
    }
}

// MARK: - Notifikasi

extension AccountWindow: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == "web.whatsapp.com",
              let body = message.body as? [String: Any],
              let nid = body["id"] as? String, Int(nid) != nil else { return }
        guard shouldNotify(appActive: NSApp.isActive, windowKey: window?.isKeyWindow ?? false) else { return }

        let content = UNMutableNotificationContent()
        content.title = body["title"] as? String ?? ""
        content.body = body["body"] as? String ?? ""
        // Tanpa suara native: WhatsApp Web sudah memutar suara sendiri.
        content.userInfo = ["account": id, "nid": nid]
        let tag = body["tag"] as? String ?? ""
        // Tag sama (chat sama) → notifikasi lama diganti, tidak menumpuk.
        let identifier = tag.isEmpty ? "\(id)-\(nid)" : "\(id)-\(tag)"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private(set) var accounts: [AccountWindow] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        Accounts.pendingRemoval().forEach(purgeDataStore)
        for id in Accounts.all() { open(id: id) }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Klik ikon Dock → tampilkan lagi akun yang windownya disembunyikan.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        accounts.filter { $0.window?.isVisible == false }.forEach(present)
        return true
    }

    // MARK: akun

    @discardableResult
    func open(id: String) -> AccountWindow {
        let account = AccountWindow(id: id)
        accounts.append(account)
        present(account)
        return account
    }

    /// Tampilkan window akun. Kalau ada window akun lain yang terlihat, gabung sebagai tab.
    func present(_ account: AccountWindow) {
        guard let win = account.window else { return }
        if !win.isVisible, win.tabGroup == nil,
           let anchor = accounts.compactMap(\.window).first(where: { $0.isVisible && $0 !== win }) {
            anchor.addTabbedWindow(win, ordered: .above)
        }
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(account.webView)
    }

    /// Akun yang windownya sedang key; fallback akun pertama.
    var current: AccountWindow? {
        accounts.first { $0.window?.isKeyWindow == true } ?? accounts.first
    }

    func refreshBadge() {
        NSApp.dockTile.badgeLabel = badgeLabel(total: accounts.reduce(0) { $0 + $1.unread })
    }

    /// Hapus data store akun yang sudah dihapus. Dipanggil saat hapus akun dan saat launch,
    /// karena WebKit menolak menghapus store yang masih dipakai dan quit bisa keburu terjadi.
    func purgeDataStore(_ id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        WKWebsiteDataStore.remove(forIdentifier: uuid) { error in
            if let error {
                FileHandle.standardError.write(Data("hapus data store \(id) gagal: \(error.localizedDescription)\n".utf8))
            } else {
                Accounts.clearPendingRemoval(id)
            }
        }
    }

    // MARK: notifikasi

    /// Tampilkan banner walau app di foreground (user mungkin sedang di tab akun lain).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .list])
    }

    /// Klik notifikasi → fokus akun terkait dan teruskan onclick ke WhatsApp supaya chat terbuka.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let accountID = info["account"] as? String,
           let account = accounts.first(where: { $0.id == accountID }) {
            NSApp.activate()
            present(account)
            if let nid = info["nid"] as? String, Int(nid) != nil {
                account.webView.evaluateJavaScript("window.__waNotifClick('\(nid)')")
            }
        }
        handler()
    }

    // MARK: menu actions

    /// Reload biasa hanya kalau halaman WhatsApp sudah termuat; kalau kosong (launch offline) atau nyasar ke host lain, muat ulang dari awal.
    @objc func reload() {
        guard let wv = current?.webView else { return }
        if let url = wv.url, !isExternal(url) { wv.reload() } else { wv.load(URLRequest(url: waHome)) }
    }
    @objc func zoomIn() { if let wv = current?.webView { wv.pageZoom = min(3, wv.pageZoom + 0.1) } }
    @objc func zoomOut() { if let wv = current?.webView { wv.pageZoom = max(0.5, wv.pageZoom - 0.1) } }
    @objc func zoomReset() { current?.webView.pageZoom = 1 }

    @objc func newAccount() { open(id: Accounts.add()) }

    /// Tombol "+" di tab bar macOS memanggil ini lewat responder chain.
    @objc func newWindowForTab(_ sender: Any?) { newAccount() }

    @objc func removeAccount() {
        // Hanya akun yang windownya key; jangan tebak lewat fallback `current` saat semua tab disembunyikan.
        guard let account = accounts.first(where: { $0.window?.isKeyWindow == true }), let win = account.window else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Hapus akun ini dari WA?"
        alert.informativeText = "Sesi login dan cache akun ini di Mac ikut dihapus. Chat di HP tidak terpengaruh."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hapus")
        alert.addButton(withTitle: "Batal")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let id = account.id
        account.webView.stopLoading()
        account.webView.configuration.userContentController.removeScriptMessageHandler(forName: "notify")
        win.contentView = nil
        win.close()
        NSWindow.removeFrame(usingName: "win-\(id)")
        accounts.removeAll { $0 === account }
        Accounts.remove(id)
        Accounts.markPendingRemoval(id)
        refreshBadge()
        // ponytail: tunda 1 detik supaya WebKit sempat melepas store; kalau masih gagal atau app keburu quit, diulang saat launch berikutnya.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.purgeDataStore(id)
        }
        if accounts.isEmpty { open(id: Accounts.all()[0]) }
    }

    private func buildMenu() {
        let main = NSMenu()
        func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let holder = NSMenuItem()
            holder.submenu = m
            main.addItem(holder)
            return m
        }
        _ = menu("WA", [
            item("About WA", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide WA", #selector(NSApplication.hide(_:)), "h"),
            item("Quit WA", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = menu("File", [
            item("Akun Baru", #selector(newAccount), "n"),
            item("Hapus Akun Ini…", #selector(removeAccount)),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        // Selector standar responder chain: tanpa ini Cmd+C/V tidak jalan di WKWebView.
        _ = menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        _ = menu("View", [
            item("Reload", #selector(reload), "r"),
            .separator(),
            item("Zoom In", #selector(zoomIn), "="),
            item("Zoom Out", #selector(zoomOut), "-"),
            item("Actual Size", #selector(zoomReset), "0"),
        ])
        // AppKit otomatis menambah Show Next/Previous Tab, Merge All Windows di sini.
        NSApp.windowsMenu = menu("Window", [
            item("Minimize", #selector(NSWindow.miniaturize(_:)), "m"),
        ])
        NSApp.mainMenu = main
    }
}


// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
