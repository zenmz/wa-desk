import Cocoa
import WebKit
import UserNotifications

// MARK: - Helpers murni (dites oleh --selftest)

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
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsMagnification = true

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: win)

        win.title = "WhatsApp"
        win.isReleasedWhenClosed = false
        win.tabbingMode = .preferred
        win.tabbingIdentifier = "wa"
        win.contentView = webView
        win.delegate = self
        win.center()
        win.setFrameAutosaveName("win-\(id)")

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let title = wv.title ?? ""
            self.window?.title = title.isEmpty ? "WhatsApp" : title
            self.unread = unreadCount(title)
            (NSApp.delegate as? AppDelegate)?.refreshBadge()
        }
        webView.load(URLRequest(url: URL(string: "https://web.whatsapp.com/")!))
    }

    required init?(coder: NSCoder) { fatalError("tidak dipakai") }

    /// Tutup window = sembunyikan. Pesan tetap masuk. Keluar hanya lewat Cmd+Q.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}


// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var accounts: [AccountWindow] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        for id in Accounts.all() { open(id: id) }
        NSApp.activate(ignoringOtherApps: true)
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
        if !win.isVisible,
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

    // MARK: menu actions

    @objc func reload() { current?.webView.reload() }
    @objc func zoomIn() { current?.webView.pageZoom += 0.1 }
    @objc func zoomOut() { current?.webView.pageZoom -= 0.1 }
    @objc func zoomReset() { current?.webView.pageZoom = 1 }

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
