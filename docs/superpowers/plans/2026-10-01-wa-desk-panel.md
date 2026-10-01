# WA Desk Single Window + In-Page Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Semua akun dalam satu window (pindah lewat menu Akun ⌘1–⌘9 atau panel), icon WA Desk di bilah navigasi WhatsApp di bawah Meta AI yang membuka popover berisi daftar akun + semua Tweaks, dengan aksi panel yang divalidasi ketat di native.

**Architecture:** `MainWindow` menumpuk satu `WKWebView` per `Account` dan menampilkan satu; semua akun tetap hidup. Panel adalah IIFE JS kedua (`PanelScript.swift`) yang hanya merender state yang didorong native (`__wadesk.setPanelState`) dan mengirim `{action,…}` ke handler `wadesk`; native mem-parse lewat fungsi murni `panelAction(from:)` lalu memanggil aksi menu yang sudah ada.

**Tech Stack:** Swift 6.3 CLT, Cocoa, WebKit, UserNotifications, Carbon, JavaScriptCore. Nol dependency.

**Spec:** `docs/superpowers/specs/2026-10-01-wa-desk-panel-design.md` (+ spec Tweaks 2026-10-01, spec inti 2026-09-30)

## Global Constraints

- Build hanya lewat `./build.sh` (`swiftc *.swift`, Carbon + JavaScriptCore sudah terhubung). Nol dependency. Hanya `main.swift` punya kode top-level.
- Nama file: `AccountWindow.swift` → `Account.swift` (class `Account`), file baru `MainWindow.swift`, `PanelScript.swift`.
- Window tunggal: `tabbingMode = .disallowed`; tidak ada `addTabbedWindow`, tidak ada `newWindowForTab`.
- Semua pengetahuan DOM WhatsApp tetap hanya di `Tweaks.swift` (`tweaksScript`/`tweaksStyle`) dan `PanelScript.swift` (`panelScript`/`panelStyle`).
- Native → JS lewat `Account.tweak(_:_:completion:)`; JS → native lewat handler `wadesk` di belakang guard main-frame + origin `web.whatsapp.com`; payload panel di-parse hanya oleh `panelAction(from:)`; aksi tak dikenal diabaikan; `id` harus UUID dan milik akun yang ada; `min ∈ {30,60,120,0}`; `tag` lolos `tagNameValid`; `color` kosong atau dari `tagPalette`.
- Semua teks state di-escape sebelum masuk HTML panel (`esc()`).
- UserDefaults baru: `activeAccount` (String id), `accountNames` (`[String: String]`).
- Teks menu/panel bahasa Indonesia seperti di spec §2 dan §4.
- Selftest wajib tetap lulus; skrip gabungan (`tweaksScript` = style + lapisan Tweaks + panel) harus dievaluasi di JSContext tanpa exception.
- Commit: pesan polos, tanpa `Co-Authored-By`, tanpa atribusi AI.

## Review Focus

1. Payload panel palsu/salah bentuk (aksi tak dikenal, `id` bukan UUID, `min` 45, `color` di luar palet, `tag` kosong) → diabaikan, tidak crash. Dipaku oleh kasus `panelAction(from:)` (Task 3).
2. Nama akun kustom berisi spasi/newline saja → kembali ke "Akun N". Dipaku oleh `accountLabel` (Task 1).
3. Skrip inject dengan panel ditambahkan masih bisa dievaluasi tanpa DOM (JSC) dan mendefinisikan `setPanelState`/`openPanel`. Dipaku oleh selftest JS (Task 2).
4. Hapus akun yang sedang aktif → akun tetangga tampil; hapus akun terakhir → akun baru dibuat; tidak pernah nol akun. Kode Task 1 `removeAccount`; dicek manual oleh user (butuh login) dan lewat alur tanpa login di launch check.
5. Notifikasi untuk akun yang **tidak** sedang dilihat tetap tampil walau app aktif (`isBeingViewed` false). Kode Task 1; manual oleh user.

---

### Task 1: Satu window: `Account`, `MainWindow`, menu Akun

**Files:**
- Rename: `AccountWindow.swift` → `Account.swift` (isi ditulis ulang di bawah)
- Create: `MainWindow.swift`
- Modify: `Accounts.swift` (tambah `AccountNames`), `Helpers.swift` (`accountLabel`), `Selftest.swift`, `AppDelegate.swift`

**Interfaces:**
- Consumes: `TweakStore`, `tweaksScript`, `notificationShim`, `unreadCount`, `Accounts.*`, `BookmarksPanel`.
- Produces:
  - `final class Account: NSObject` dengan `id`, `webView`, `store`, `unread`, `tagFilter`, `bookmarksPanel` (private(set)), `openChatTitle` (private(set)), `pageTitle`, `name`, `windowTitle`, `isBeingViewed`, `tweak(_:_:completion:)`, `applyTweaks()`, `pushTags()`, `owns(_:)`, `showBookmarksPanel()`, `open(bookmark:)`.
  - `final class MainWindow: NSWindowController` dengan `active: Account?`, `attach(_:)`, `detach(_:)`, `show(_:)`, `refreshTitle()`.
  - `enum AccountNames { static func custom(for:) -> String?; static func set(_:for:) }`, `func accountLabel(custom:index:) -> String`.
  - `AppDelegate`: `accounts: [Account]`, `mainWindow`, `attach(id:) -> Account`, `show(_:)`, `current`, `refreshBadge()`, `accountTitleChanged(_:)`, `rename(_:)`, aksi `newAccount`, `switchAccount(_:)`, `nextAccount`, `previousAccount`, `renameAccount`, `removeAccount`; menu Akun (`accountsMenu`) dibangun di `menuNeedsUpdate`.

- [ ] **Step 1: Selftest `accountLabel` (gagal)**

Di `Selftest.swift`, sebelum `if failed.isEmpty`:

```swift
    // Nama akun
    check(accountLabel(custom: nil, index: 0) == "Akun 1", "accountLabel default")
    check(accountLabel(custom: " \n ", index: 1) == "Akun 2", "accountLabel spasi/newline → default")
    check(accountLabel(custom: " Kerja ", index: 5) == "Kerja", "accountLabel kustom di-trim")
```

Run: `./build.sh` → `cannot find 'accountLabel' in scope`.

- [ ] **Step 2: `accountLabel` dan `AccountNames`**

`Helpers.swift`, di bawah `hhmm(fromMinutes:)`:

```swift
/// Nama tampilan akun: nama kustom (setelah trim) atau "Akun N" dari urutan daftar (index 0-based).
func accountLabel(custom: String?, index: Int) -> String {
    let c = (custom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return c.isEmpty ? "Akun \(index + 1)" : c
}
```

`Accounts.swift`, di akhir file:

```swift
/// Nama kustom akun. UserDefaults "accountNames": [id: nama]. nil = pakai "Akun N".
enum AccountNames {
    private static let key = "accountNames"

    static func custom(for id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id]
    }

    static func set(_ name: String?, for id: String) {
        var d = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        d[id] = name
        UserDefaults.standard.set(d, forKey: key)
    }
}
```

Run: `./build.sh` → `selftest OK` (sisa app masih memakai `AccountWindow`, belum diubah).

- [ ] **Step 3: `git mv AccountWindow.swift Account.swift` lalu tulis ulang bagian class**

Ganti seluruh isi file dari awal sampai tepat sebelum `// MARK: - Navigasi, download, media` dengan:

```swift
import Cocoa
import WebKit
import UserNotifications

// MARK: - Account

/// Satu akun WhatsApp: WKWebView + data store + state Tweaks. Tidak punya window sendiri;
/// MainWindow menumpuk webView semua akun dan menampilkan satu. Akun yang tersembunyi tetap hidup.
final class Account: NSObject {
    let id: String
    let webView: WKWebView
    private(set) var unread = 0
    private var titleObservation: NSKeyValueObservation?
    let store: TweakStore
    /// Warna tag yang sedang difilter di akun ini ("" = semua). Sesi saja.
    var tagFilter = ""
    private(set) var bookmarksPanel: BookmarksPanel?
    /// Judul chat yang sedang terbuka, dilaporkan JS lewat handler "wadesk". nil = tidak ada chat.
    private(set) var openChatTitle: String?
    /// Judul halaman WhatsApp ("(3) WhatsApp"); kosong sebelum dimuat.
    private(set) var pageTitle = ""

    private var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    init(id: String) {
        self.id = id
        store = TweakStore(accountID: id)
        let cfg = WKWebViewConfiguration()
        // Data store per akun: cookie, IndexedDB, dan sesi login terisolasi.
        cfg.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: id)!)
        // UA setara Safari supaya lolos cek browser WhatsApp Web.
        cfg.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.userContentController.addUserScript(WKUserScript(
            source: notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.addUserScript(WKUserScript(
            source: tweaksScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsMagnification = true
        webView.autoresizingMask = [.width, .height]
        super.init()
        webView.configuration.userContentController.add(self, name: "notify")
        webView.configuration.userContentController.add(self, name: "wadesk")
        webView.navigationDelegate = self
        webView.uiDelegate = self

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            self.pageTitle = wv.title ?? ""
            self.unread = unreadCount(self.pageTitle)
            self.delegate?.accountTitleChanged(self)
        }
        webView.load(URLRequest(url: waHome))
    }

    deinit { titleObservation?.invalidate() }

    /// Nama tampilan: nama kustom atau "Akun N" menurut urutan di daftar akun.
    var name: String {
        let index = delegate?.accounts.firstIndex { $0 === self } ?? 0
        return accountLabel(custom: AccountNames.custom(for: id), index: index)
    }

    /// Judul window saat akun ini aktif, mis. "Kerja · (3) WhatsApp".
    var windowTitle: String { "\(name) · \(pageTitle.isEmpty ? "WhatsApp" : pageTitle)" }

    /// User sedang melihat akun ini: webView-nya yang tampil dan window utama key.
    var isBeingViewed: Bool { !webView.isHidden && webView.window?.isKeyWindow == true }

    /// Panggil `__wadesk.<fn>(...)` dengan argumen terstruktur (callAsyncJavaScript), tanpa interpolasi string.
    /// `args` urut sesuai parameter fungsi JS. Hasil `undefined`/`null` → nil.
    func tweak(_ fn: String, _ args: KeyValuePairs<String, Any> = [:], completion: ((Any?) -> Void)? = nil) {
        let call = "return await __wadesk.\(fn)(\(args.map(\.key).joined(separator: ", ")))"
        let dict = Dictionary(uniqueKeysWithValues: args.map { ($0.key, $0.value) })
        webView.callAsyncJavaScript(call, arguments: dict, in: nil, in: .page) { result in
            switch result {
            case .success(let v):
                // callAsyncJavaScript membungkus `undefined` sebagai Optional<Any>.none dan `null` sebagai NSNull; keduanya → nil.
                // Lewat AnyObject: Optional.none yang terbungkus Any dijembatani ke NSNull (`v as Any?` tidak membukanya).
                let unwrapped: Any? = (v as AnyObject) is NSNull ? nil : v
                completion?(unwrapped)
            case .failure(let e):
                FileHandle.standardError.write(Data("tweak \(fn): \(e.localizedDescription)\n".utf8))
                completion?(nil)
            }
        }
    }

    /// Dorong semua setting Tweaks ke halaman. Dipanggil tiap halaman selesai dimuat dan saat setting berubah.
    func applyTweaks() {
        tweak("setBlur", ["on": TweakSettings.blur])
        tweak("setHideBanner", ["on": TweakSettings.hideBanner])
        if let css = customCSS() { tweak("setCustomCSS", ["css": css]) }
        pushTags()
        tweak("setFilter", ["color": tagFilter])
    }

    func pushTags() { tweak("setTags", ["map": tagColors(store.tags)]) }

    /// Panel bookmark akun ini. Dipakai AppDelegate.current supaya aksi menu mengenai akun yang benar saat panel key.
    func owns(_ w: NSWindow?) -> Bool { w != nil && w === bookmarksPanel }

    func showBookmarksPanel() {
        if bookmarksPanel == nil {
            let p = BookmarksPanel(store: store)
            p.onOpen = { [weak self] b in self?.open(bookmark: b) }
            bookmarksPanel = p
        }
        bookmarksPanel?.makeKeyAndOrderFront(nil)
    }

    /// Tampilkan akun ini, buka chat bookmark, lompat ke pesannya; setiap kegagalan dilaporkan lewat toast.
    func open(bookmark b: Bookmark) {
        delegate?.show(self)
        tweak("openChat", ["title": b.chat, "jid": b.jid ?? ""]) { [weak self] result in
            guard let self else { return }
            switch result as? String {
            case "clicked":
                self.tweak("jumpTo", ["id": b.id, "title": b.chat]) { ok in
                    if ok as? Bool != true { self.tweak("toast", ["msg": "Pesan lama, scroll manual"]) }
                }
            case "navigated":
                self.tweak("toast", ["msg": "Membuka chat…"])
            default:
                self.tweak("toast", ["msg": "Chat tidak terlihat di daftar"])
            }
        }
    }
}

```

Sisa file (dua extension) tetap, dengan tiga perubahan:
- Kedua header extension: `extension AccountWindow:` → `extension Account:`.
- Di `runOpenPanelWith`: `guard let win = window else` → `guard let win = webView.window else`.
- Di `userContentController(_:didReceive:)`: `windowKey: window?.isKeyWindow ?? false` → `windowKey: isBeingViewed`.

- [ ] **Step 4: `MainWindow.swift`**

```swift
import Cocoa

// MARK: - MainWindow

/// Satu window untuk semua akun: webView tiap akun ditumpuk di container, hanya yang aktif terlihat.
final class MainWindow: NSWindowController, NSWindowDelegate {
    private let container = NSView()
    private(set) var active: Account?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: win)
        win.title = "WhatsApp"
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.contentView = container
        win.delegate = self
        win.center()
        win.setFrameAutosaveName("main")
    }

    required init?(coder: NSCoder) { fatalError("tidak dipakai") }

    /// Tumpuk webView akun di container, tersembunyi, tetap memuat halaman.
    func attach(_ account: Account) {
        account.webView.frame = container.bounds
        account.webView.isHidden = true
        container.addSubview(account.webView)
    }

    func detach(_ account: Account) {
        account.webView.removeFromSuperview()
        if active === account { active = nil }
    }

    /// Tampilkan akun ini; akun lain tetap hidup tapi tersembunyi.
    func show(_ account: Account) {
        for v in container.subviews { v.isHidden = v !== account.webView }
        account.webView.frame = container.bounds
        active = account
        refreshTitle()
        window?.makeFirstResponder(account.webView)
    }

    func refreshTitle() { window?.title = active?.windowTitle ?? "WhatsApp" }

    /// Tutup window = sembunyikan. Pesan tetap masuk. Keluar hanya lewat Cmd+Q.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
```

- [ ] **Step 5: `AppDelegate.swift`**

a) Ganti baris `private(set) var accounts: [AccountWindow] = []` dan dua baris di bawahnya (komentar + `tweaksMenu`) dengan:

```swift
    private(set) var accounts: [Account] = []
    let mainWindow = MainWindow()
    /// Dibangun ulang tiap dibuka (menuNeedsUpdate) supaya centang dan daftar tag selalu segar.
    private let tweaksMenu = NSMenu(title: "Tweaks")
    /// Dibangun ulang tiap dibuka: satu item per akun ⌘1–⌘9 dengan unread, centang akun aktif.
    private let accountsMenu = NSMenu(title: "Akun")
```

b) Di `applicationDidFinishLaunching`, ganti dua baris `for id in Accounts.all() { open(id: id) }` dan `NSApp.activate()` dengan:

```swift
        for id in Accounts.all() { attach(id: id) }
        let last = UserDefaults.standard.string(forKey: "activeAccount")
        show(accounts.first { $0.id == last } ?? accounts[0])
        NSApp.activate()
```

c) Ganti `applicationShouldHandleReopen` dengan:

```swift
    /// Klik ikon Dock → tampilkan lagi window utama.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        mainWindow.showWindow(nil)
        mainWindow.window?.makeKeyAndOrderFront(nil)
        return true
    }
```

d) Ganti seluruh blok dari `// MARK: akun` sampai tepat sebelum `/// Hapus data store akun yang sudah dihapus.` (yaitu `open(id:)`, `present(_:)`, `current`, `refreshBadge()`) dengan:

```swift
    // MARK: akun

    /// Buat akun dan tumpuk webView-nya di window utama (belum ditampilkan).
    @discardableResult
    func attach(id: String) -> Account {
        let account = Account(id: id)
        accounts.append(account)
        mainWindow.attach(account)
        return account
    }

    /// Tampilkan akun di window utama dan bawa window ke depan; ingat sebagai akun aktif.
    func show(_ account: Account) {
        mainWindow.show(account)
        mainWindow.showWindow(nil)
        mainWindow.window?.makeKeyAndOrderFront(nil)
        UserDefaults.standard.set(account.id, forKey: "activeAccount")
    }

    /// Akun yang panel bookmark-nya key; kalau tidak, akun yang sedang tampil.
    var current: Account? {
        accounts.first { $0.owns(NSApp.keyWindow) } ?? mainWindow.active ?? accounts.first
    }

    func refreshBadge() {
        NSApp.dockTile.badgeLabel = badgeLabel(total: accounts.reduce(0) { $0 + $1.unread })
    }

    /// Judul halaman akun berubah (unread): badge Dock, dan judul window kalau akun itu yang tampil.
    func accountTitleChanged(_ account: Account) {
        refreshBadge()
        if mainWindow.active === account { mainWindow.refreshTitle() }
    }

```

e) Di `userNotificationCenter(_:didReceive:…)`, ganti `present(account)` dengan `show(account)`.

f) Ganti `toggleAlwaysOnTop()`, `validateMenuItem(_:)`, dan `toggleVisibility()` dengan:

```swift
    @objc func toggleAlwaysOnTop() {
        guard let w = mainWindow.window else { return }
        w.level = w.level == .floating ? .normal : .floating
    }

    /// Centang "Selalu di Atas" mengikuti window utama. Item lain selalu aktif.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAlwaysOnTop) {
            item.state = mainWindow.window?.level == .floating ? .on : .off
        }
        return true
    }

    /// ⌥⌘W: app aktif dengan window terlihat → sembunyikan; selain itu → aktifkan dan tampilkan window utama.
    func toggleVisibility() {
        let visible = mainWindow.window?.isVisible == true
        if NSApp.isActive && visible {
            NSApp.hide(nil)
        } else {
            NSApp.activate()
            mainWindow.showWindow(nil)
            mainWindow.window?.makeKeyAndOrderFront(nil)
        }
    }
```

g) Ganti blok dari `@objc func newAccount() { open(id: Accounts.add()) }` sampai akhir `removeAccount()` (termasuk `newWindowForTab`) dengan:

```swift
    @objc func newAccount() { show(attach(id: Accounts.add())) }

    @objc func switchAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let account = accounts.first(where: { $0.id == id }) else { return }
        show(account)
    }

    @objc func nextAccount() { step(1) }
    @objc func previousAccount() { step(-1) }

    private func step(_ delta: Int) {
        guard accounts.count > 1, let active = mainWindow.active,
              let i = accounts.firstIndex(where: { $0 === active }) else { return }
        show(accounts[(i + delta + accounts.count) % accounts.count])
    }

    @objc func renameAccount() {
        guard let account = current else { return }
        rename(account)
    }

    /// Dialog nama akun. Kosong = kembali ke nama otomatis "Akun N".
    func rename(_ account: Account) {
        let alert = NSAlert()
        alert.messageText = "Nama akun"
        alert.informativeText = "Kosongkan untuk kembali ke nama otomatis."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = AccountNames.custom(for: account.id) ?? ""
        field.placeholderString = account.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Simpan")
        alert.addButton(withTitle: "Batal")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        AccountNames.set(name.isEmpty ? nil : String(name.prefix(24)), for: account.id)
        mainWindow.refreshTitle()
    }

    @objc func removeAccount() {
        guard let account = current else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Hapus akun “\(account.name)” dari WA Desk?"
        alert.informativeText = "Sesi login, cache, bookmark, dan tag akun ini di Mac ikut dihapus. Chat di HP tidak terpengaruh."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hapus")
        alert.addButton(withTitle: "Batal")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let id = account.id
        let index = accounts.firstIndex { $0 === account } ?? 0
        account.webView.stopLoading()
        account.webView.configuration.userContentController.removeScriptMessageHandler(forName: "notify")
        account.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wadesk")
        account.bookmarksPanel?.close()
        mainWindow.detach(account)
        accounts.removeAll { $0 === account }
        Accounts.remove(id)
        Accounts.markPendingRemoval(id)
        AccountNames.set(nil, for: id)
        // Alert menjanjikan data lokal akun dihapus: bookmark/tag ikut dihapus.
        try? FileManager.default.removeItem(at: account.store.dir)
        refreshBadge()
        // ponytail: tunda 1 detik supaya WebKit sempat melepas store; kalau masih gagal atau app keburu quit, diulang saat launch berikutnya.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.purgeDataStore(id)
        }
        if accounts.isEmpty { attach(id: Accounts.all()[0]) }
        show(accounts[min(index, accounts.count - 1)])
    }
```

h) Di `buildMenu()`: ganti blok `_ = menu("File", [ … ])` dengan:

```swift
        _ = menu("File", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        accountsMenu.delegate = self
        accountsMenu.autoenablesItems = false
        let accountsHolder = NSMenuItem()
        accountsHolder.submenu = accountsMenu
        main.addItem(accountsHolder)
```

i) Di `menuNeedsUpdate(_:)`, ganti baris pertama `guard menu === tweaksMenu else { return }` dengan:

```swift
        if menu === accountsMenu { rebuildAccountsMenu(); return }
        guard menu === tweaksMenu else { return }
```

dan tambahkan method baru tepat di bawah `menuNeedsUpdate`:

```swift
    private func rebuildAccountsMenu() {
        let menu = accountsMenu
        menu.removeAllItems()
        for (i, a) in accounts.enumerated() {
            let title = a.unread > 0 ? "\(a.name)  (\(a.unread))" : a.name
            let item = NSMenuItem(title: title, action: #selector(switchAccount(_:)), keyEquivalent: i < 9 ? String(i + 1) : "")
            item.representedObject = a.id
            item.state = mainWindow.active === a ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let next = NSMenuItem(title: "Akun Berikutnya", action: #selector(nextAccount), keyEquivalent: "\t")
        next.keyEquivalentModifierMask = .control
        let prev = NSMenuItem(title: "Akun Sebelumnya", action: #selector(previousAccount), keyEquivalent: "\t")
        prev.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(next)
        menu.addItem(prev)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Akun Baru", action: #selector(newAccount), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Ganti Nama Akun…", action: #selector(renameAccount), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hapus Akun Ini…", action: #selector(removeAccount), keyEquivalent: ""))
    }
```

j) Bersihkan sisa referensi: `grep -n "AccountWindow\|present(\|newWindowForTab\|tabGroup\|addTabbedWindow\|removeFrame" *.swift` harus kosong.

- [ ] **Step 6: Build, selftest, launch check**

Run: `./build.sh` → `selftest OK`, `built WA Desk.app`, tanpa warning.

Launch check (instance repo terpisah; app user mungkin sedang jalan dari /opt/homebrew):

```sh
open -n "WA Desk.app"; sleep 7
MYPID=$(ps -axo pid,command | grep "orca/projects/wa/WA Desk.app/Contents/MacOS/wa-desk" | grep -v grep | awk '{print $1}' | head -1)
osascript -l JavaScript -e "
const se = Application('System Events'); const p = se.processes.whose({unixId: $MYPID})[0]; p.frontmost = true; delay(0.5);
const mb = p.menuBars[0]; console.log('menus: ' + mb.menuBarItems.name().join(' | '));
const ak = mb.menuBarItems.byName('Akun').menus[0]; console.log('Akun: ' + ak.menuItems.name().join(' | '));
console.log('title: ' + p.windows[0].name());
ak.menuItems.byName('Akun Baru').click(); delay(2);
console.log('Akun setelah ⌘N: ' + ak.menuItems.name().join(' | ') + ' | windows: ' + p.windows.name().join(','));
"
kill $MYPID
```
Expected: menus memuat `Akun`; daftar `Akun 1 | | Akun Berikutnya | Akun Sebelumnya | | Akun Baru | Ganti Nama Akun… | Hapus Akun Ini…`; judul window `Akun 1 · WhatsApp…`; setelah Akun Baru: `Akun 1 | Akun 2 | …` dan **tetap satu window**. Setelah itu bersihkan akun uji: `defaults read dev.zen.wa accounts` lalu hapus id kedua yang baru dibuat dengan `defaults write dev.zen.wa accounts -array "<id pertama>"` dan `rm -rf ~/Library/WebKit/dev.zen.wa/WebsiteDataStore/<uuid kedua lowercase>` (catat di laporan).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Host all accounts in one window with an Akun menu instead of native tabs"
```

---

### Task 2: Icon di bilah navigasi + panel (JS/CSS)

**Files:**
- Create: `PanelScript.swift`
- Modify: `Tweaks.swift` (gabungkan skrip), `Selftest.swift`

**Interfaces:**
- Consumes: `__wadesk` (Tweaks.swift), `jsStringLiteral`.
- Produces: `let panelStyle: String`, `let panelScript: String`; `tweaksScript` kini = prefix style + `tweaksScriptBody` + `panelScript`; API JS `__wadesk.setPanelState(state)`, `__wadesk.openPanel()`, `__wadesk.closePanel()`; pesan ke native `{action: "panelOpen"}` saat dibuka dan `{action, id?, tag?, color?, min?}` untuk tiap kontrol.

- [ ] **Step 1: Selftest (gagal)**

Di `Selftest.swift`, ganti baris loop `for fn in [... "dump"] {` menjadi menyertakan dua nama baru:

```swift
    for fn in ["setBlur", "setHideBanner", "setCustomCSS", "setFilter", "setTags", "toast", "currentChat", "jumpTo", "dump", "setPanelState", "openPanel"] {
```

Run: `./build.sh` → `FAIL: JS __wadesk.setPanelState`, `FAIL: JS __wadesk.openPanel`.

- [ ] **Step 2: `PanelScript.swift`**

```swift
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
    if (!sec || $('[data-wadesk-nav="1"]', sec)) return;
    const meta = metaAIItem(sec);
    let item;
    if (meta) {
      // Klon item Meta AI: class WhatsApp ikut (hover/active sama), listener tidak ikut; atribut identitas dibersihkan.
      item = meta.cloneNode(true);
      for (const el of [item, ...$$("*", item)]) {
        for (const a of Array.from(el.attributes)) {
          if (/^(id|data-testid|data-navbar-item|aria-label|aria-selected|aria-pressed|title|tabindex)$/i.test(a.name)) el.removeAttribute(a.name);
        }
      }
      const svg = item.querySelector("svg");
      (svg ? svg.parentElement : item).innerHTML = ICON;
      meta.insertAdjacentElement("afterend", item);
    } else {
      item = document.createElement("div");
      item.className = "wadesk-nav-fallback";
      item.innerHTML = ICON;
      sec.appendChild(item);
    }
    item.dataset.wadeskNav = "1";
    item.setAttribute("role", "button");
    item.setAttribute("aria-label", "WA Desk");
    item.setAttribute("title", "WA Desk");
    item.tabIndex = 0;
    item.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); toggle(); }, true);
    item.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); } });
  }

  function isDark() {
    const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(getComputedStyle(document.body).backgroundColor || "");
    if (!m) return matchMedia("(prefers-color-scheme: dark)").matches;
    return (0.2126 * m[1] + 0.7152 * m[2] + 0.0722 * m[3]) / 255 < 0.5;
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
    p.style.left = Math.round(r.right + 8) + "px";
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
      '<label class="wd-row wd-tag"><input type="checkbox" data-act="toggleTag" data-tag="' + esc(t.name) + '"' + (t.checked ? " checked" : "") + (s.hasOpenChat ? "" : " disabled") + '><span class="wd-swatch" style="background:' + esc(t.color) + '"></span>' + esc(t.name) + "</label>").join("");
    const chips = ['<button class="wd-chip' + (s.filter ? "" : " on") + '" data-act="setFilter" data-color="">Semua</button>']
      .concat((s.tags || []).map(t => '<button class="wd-chip' + (s.filter === t.color ? " on" : "") + '" data-act="setFilter" data-color="' + esc(t.color) + '" style="--c:' + esc(t.color) + '">' + esc(t.name) + "</button>")).join("");
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
  document.addEventListener("keydown", e => { if (e.key === "Escape" && P.open) toggle(false); }, true);
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
```

- [ ] **Step 3: Gabungkan skrip di `Tweaks.swift`**

Ganti baris `let tweaksScript = "const WADESK_STYLE = \(jsStringLiteral(tweaksStyle));\n" + #"""` dengan:

```swift
private let tweaksScriptBody = #"""
```

dan tepat setelah baris penutup `"""#` dari raw string itu (sebelum `// MARK: - Hotkey global`) tambahkan:

```swift
/// Skrip inject lengkap: konstanta style, lapisan Tweaks, lalu panel. Dievaluasi juga di JSContext (selftest).
let tweaksScript = "const WADESK_STYLE = \(jsStringLiteral(tweaksStyle));\nconst WADESK_PANEL_STYLE = \(jsStringLiteral(panelStyle));\n"
    + tweaksScriptBody + "\n" + panelScript
```

- [ ] **Step 4: Build**

Run: `./build.sh` → `selftest OK` (termasuk `JS __wadesk.setPanelState`, `openPanel`), tanpa warning.

- [ ] **Step 5: Harness DOM tiruan**

Buat `/private/tmp/claude-501/-Users-zen-orca-projects-wa/7f04885d-6866-4a32-bd6c-d31e251cfa14/scratchpad/harness/h6/main.swift` dan `fixture-nav.html` (folder boleh dibuat baru). Fixture:

```html
<!doctype html><html><head><meta charset="utf-8"><style>body{background:#111b21;color:#e9edef}</style></head><body><div id="app">
<header data-testid="chatlist-header"><div><div data-testid="navbar-primary-section">
  <div class="navitem"><div><button aria-label="Chats"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/></svg></button></div></div>
  <div class="navitem"><div><button aria-label="Status"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/></svg></button></div></div>
  <div class="navitem metaai" id="meta-wrap"><div><button aria-label="Meta AI" data-testid="meta-ai-nav" tabindex="0"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/></svg></button></div></div>
  <hr>
  <div class="navitem"><div><button aria-label="Settings"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/></svg></button></div></div>
</div></div></header>
<div id="side"><div id="pane-side"><div role="row" style="transform: translateY(0px)"><span title="Budi">Budi</span></div></div></div>
<div id="main"><header><span title="Budi">Budi</span></header></div>
</div><script>window.__posted = []; window.webkit = { messageHandlers: { wadesk: { postMessage: m => window.__posted.push(m) }, notify: { postMessage: () => {} } } };</script></body></html>
```

Driver (`main.swift`, kompilasi: `swiftc -O main.swift <repo>/Tweaks.swift <repo>/PanelScript.swift -o harness6 -framework Cocoa -framework WebKit -framework Carbon`):

```swift
import Cocoa
import WebKit

final class Driver: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addUserScript(WKUserScript(source: tweaksScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700), configuration: cfg)
        super.init()
        webView.navigationDelegate = self
    }
    func js(_ src: String) async -> Any? {
        await withCheckedContinuation { (c: CheckedContinuation<Any?, Never>) in
            webView.evaluateJavaScript(src) { v, e in c.resume(returning: e.map { "ERROR: \($0.localizedDescription)" } ?? v) }
        }
    }
    func sleep(_ ms: Int) async { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in await run(); exit(0) } }
    func show(_ l: String, _ v: Any?) { print("[\(l)] \(v.map { "\($0)" } ?? "nil")") }
    func run() async {
        await sleep(700)
        show("nav icon after meta", await js("(() => { const i = document.querySelector('[data-wadesk-nav=\"1\"]'); return i ? (i.previousElementSibling && i.previousElementSibling.id) + ' | class=' + i.className + ' | leaked=' + i.querySelectorAll('[data-testid],[id]').length + ' | label=' + i.getAttribute('aria-label') : 'MISSING'; })()"))
        _ = await js("__wadesk.setPanelState({version:'0.5.0', accounts:[{id:'A',name:'Kerja',unread:3,active:true},{id:'B',name:'Akun 2',unread:0,active:false}], blur:true, hideBanner:true, mute:{active:false,label:''}, dnd:{enabled:false,start:'22:00',end:'07:00',active:false}, onTop:false, tags:[{name:'Kerja',color:'#60A5FA',checked:true}], hasOpenChat:true, filter:''})")
        _ = await js("__wadesk.openPanel()")
        await sleep(200)
        show("panel visible", await js("(() => { const p = document.getElementById('wadesk-panel'); return p && !p.hidden ? 'yes dark=' + p.classList.contains('wd-dark') + ' left=' + p.style.left : 'no'; })()"))
        show("accounts rendered", await js("[...document.querySelectorAll('#wadesk-panel .wd-acc')].map(r => r.querySelector('.wd-name').textContent + (r.classList.contains('on') ? '*' : '') + ' ' + (r.querySelector('.wd-badge') || {}).textContent).join(' | ')"))
        show("blur switch checked", await js("document.querySelector('#wadesk-panel .wd-switch[data-act=toggleBlur]').checked"))
        show("tag checkbox", await js("(() => { const c = document.querySelector('#wadesk-panel input[data-act=toggleTag]'); return c.checked + ' disabled=' + c.disabled; })()"))
        show("escape injection", await js("(() => { __wadesk.setPanelState({version:'x', accounts:[{id:'A',name:'<img src=x onerror=alert(1)>',unread:0,active:true}], tags:[], mute:{}, dnd:{}}); return document.querySelector('#wadesk-panel .wd-name').innerHTML; })()"))
        _ = await js("document.querySelector('#wadesk-panel .wd-acc[data-id=A]') && (() => { __wadesk.setPanelState({version:'0.5.0', accounts:[{id:'A',name:'Kerja',unread:3,active:true},{id:'B',name:'Akun 2',unread:0,active:false}], blur:true, hideBanner:true, mute:{active:false,label:''}, dnd:{enabled:false,start:'22:00',end:'07:00',active:false}, onTop:false, tags:[], hasOpenChat:false, filter:''}); document.querySelector('#wadesk-panel .wd-acc[data-id=B]').click(); })()")
        _ = await js("document.querySelector('#wadesk-panel .wd-chip[data-min=\"60\"]') || __wadesk.openPanel()")
        _ = await js("document.querySelector('#wadesk-panel .wd-chip[data-min=\"60\"]').click()")
        show("posted", await js("JSON.stringify(window.__posted)"))
        show("panel closed after switch?", await js("document.getElementById('wadesk-panel').hidden"))
        _ = await js("__wadesk.openPanel(); document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}))")
        show("closed by Escape", await js("document.getElementById('wadesk-panel').hidden"))
        _ = await js("document.getElementById('meta-wrap').remove()")
        await sleep(100)
        _ = await js("document.querySelector('[data-wadesk-nav=\"1\"]').remove()")
        await sleep(800)
        show("fallback icon when Meta AI absent", await js("(() => { const i = document.querySelector('[data-wadesk-nav=\"1\"]'); return i ? i.className + ' last=' + (i.parentElement.lastElementChild === i) : 'MISSING'; })()"))
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let driver = Driver()
let html = try! String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), encoding: .utf8)
driver.webView.loadHTMLString(html, baseURL: URL(string: "https://web.whatsapp.com/")!)
app.run()
```

Expected: `nav icon after meta` = `meta-wrap | class=navitem metaai | leaked=0 | label=WA Desk`; panel visible `yes dark=true`; accounts `Kerja* 3 | Akun 2 undefined`; blur switch `true`; tag `true disabled=false`; escape injection menunjukkan `&lt;img …` (bukan elemen img); `posted` memuat `{"action":"panelOpen"}`, `{"action":"switchAccount","id":"B"}`, `{"action":"mute","min":60}`; panel tertutup setelah switch `true`; Escape `true`; fallback `wadesk-nav-fallback last=true`. Catat output lengkap di laporan.

- [ ] **Step 6: Commit**

```bash
git add PanelScript.swift Tweaks.swift Selftest.swift
git commit -m "Add in-page WA Desk nav icon and panel rendered from native state"
```

---

### Task 3: Jembatan aksi panel

**Files:**
- Modify: `Helpers.swift` (`PanelAction`, `panelAction(from:)`), `Selftest.swift`, `AppDelegate.swift` (state, push, dispatch, refactor aksi), `Account.swift` (hook push/aksi)

**Interfaces:**
- Consumes: Task 1 (`show`, `rename`, `removeAccount`, `newAccount`, `accounts`, `mainWindow`), Task 2 (`setPanelState`), aksi Tweaks yang ada.
- Produces: `enum PanelAction`, `func panelAction(from: [String: Any]) -> PanelAction?`; `AppDelegate.panelState(for:) -> [String: Any]`, `pushPanelState(to:)`, `handlePanelAction(_:from:)`, `toggleTag(named:in:)`, `setFilter(_:in:)`, `mute(minutes:)`.

- [ ] **Step 1: Selftest `panelAction` (gagal)**

Di `Selftest.swift`, sebelum `if failed.isEmpty`:

```swift
    // Aksi panel: input dari halaman web, semua divalidasi
    let uid = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    check(panelAction(from: ["action": "panelOpen"]) == .open, "panelAction open")
    check(panelAction(from: ["action": "switchAccount", "id": uid]) == .switchAccount(uid), "panelAction switch")
    check(panelAction(from: ["action": "switchAccount", "id": "x"]) == nil, "panelAction switch id bukan UUID")
    check(panelAction(from: ["action": "renameAccount"]) == nil, "panelAction rename tanpa id")
    check(panelAction(from: ["action": "mute", "min": 60]) == .mute(60), "panelAction mute 60")
    check(panelAction(from: ["action": "mute", "min": 60.0]) == .mute(60), "panelAction mute double dari JS")
    check(panelAction(from: ["action": "mute", "min": 45]) == nil, "panelAction mute 45 ditolak")
    check(panelAction(from: ["action": "toggleTag", "tag": "Kerja"]) == .toggleTag("Kerja"), "panelAction tag")
    check(panelAction(from: ["action": "toggleTag", "tag": ""]) == nil, "panelAction tag kosong ditolak")
    check(panelAction(from: ["action": "setFilter", "color": ""]) == .setFilter(""), "panelAction filter semua")
    check(panelAction(from: ["action": "setFilter", "color": "#60A5FA"]) == .setFilter("#60A5FA"), "panelAction filter palet")
    check(panelAction(from: ["action": "setFilter", "color": "#000000"]) == nil, "panelAction filter di luar palet")
    check(panelAction(from: ["action": "formatDisk"]) == nil, "panelAction tak dikenal")
    check(panelAction(from: [:]) == nil, "panelAction kosong")
```

Run: `./build.sh` → `cannot find 'panelAction' in scope`.

- [ ] **Step 2: `PanelAction` di `Helpers.swift`**

Di bawah `accountLabel`:

```swift
/// Aksi dari panel di halaman. Hanya daftar ini yang diterima; argumen divalidasi di panelAction(from:).
enum PanelAction: Equatable {
    case open, switchAccount(String), newAccount, renameAccount(String), removeAccount
    case toggleBlur, toggleBanner, bookmark, showBookmarks, toggleTag(String), newTag, setFilter(String)
    case mute(Int), muteOff, toggleDND, editDND, toggleOnTop, reloadCSS, debug
}

/// Parse pesan panel `{action, id?, tag?, color?, min?}`. Input dari halaman web: aksi tak dikenal atau argumen
/// tak valid → nil. Kepemilikan `id` dicek lagi di AppDelegate.
func panelAction(from d: [String: Any]) -> PanelAction? {
    let validID = (d["id"] as? String).flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
    switch d["action"] as? String {
    case "panelOpen": return .open
    case "switchAccount": return validID.map { .switchAccount($0) }
    case "newAccount": return .newAccount
    case "renameAccount": return validID.map { .renameAccount($0) }
    case "removeAccount": return .removeAccount
    case "toggleBlur": return .toggleBlur
    case "toggleBanner": return .toggleBanner
    case "bookmark": return .bookmark
    case "showBookmarks": return .showBookmarks
    case "toggleTag":
        guard let t = d["tag"] as? String, tagNameValid(t) else { return nil }
        return .toggleTag(t)
    case "newTag": return .newTag
    case "setFilter":
        guard let c = d["color"] as? String, c.isEmpty || tagColorValid(c) else { return nil }
        return .setFilter(c)
    case "mute":
        guard let m = (d["min"] as? NSNumber)?.intValue, [30, 60, 120, 0].contains(m) else { return nil }
        return .mute(m)
    case "muteOff": return .muteOff
    case "toggleDND": return .toggleDND
    case "editDND": return .editDND
    case "toggleOnTop": return .toggleOnTop
    case "reloadCSS": return .reloadCSS
    case "debug": return .debug
    default: return nil
    }
}
```

Run: `./build.sh` → `selftest OK`.

- [ ] **Step 3: Refactor aksi menu supaya bisa dipanggil tanpa `NSMenuItem`**

Di `AppDelegate.swift`:

a) Ganti `toggleTag(_ sender:)` dengan:

```swift
    @objc func toggleTag(_ sender: NSMenuItem) {
        guard let acc = current, let name = sender.representedObject as? String else { return }
        toggleTag(named: name, in: acc)
    }

    func toggleTag(named name: String, in acc: Account) {
        guard let chat = acc.openChatTitle, acc.store.tags.tags.contains(where: { $0.name == name }) else { return }
        acc.store.update { data in
            var names = data.chats[chat] ?? []
            if let i = names.firstIndex(of: name) { names.remove(at: i) } else { names.append(name) }
            data.chats[chat] = names.isEmpty ? nil : names
        }
        acc.pushTags()
        pushPanelState()
    }
```

b) Ganti `setTagFilter(_ sender:)` dengan:

```swift
    @objc func setTagFilter(_ sender: NSMenuItem) {
        guard let acc = current else { return }
        setFilter(sender.representedObject as? String ?? "", in: acc)
    }

    func setFilter(_ color: String, in acc: Account) {
        acc.tagFilter = color
        acc.tweak("setFilter", ["color": color])
        pushPanelState()
    }
```

c) Ganti `muteFor(_ sender:)` dan `muteOneHour()` dengan:

```swift
    @objc func muteFor(_ sender: NSMenuItem) { mute(minutes: sender.representedObject as? Int ?? 60) }
    @objc func muteOneHour() { mute(minutes: 60) }

    /// 0 = sampai dimatikan.
    func mute(minutes: Int) {
        let until: Date = minutes == 0 ? .distantFuture : Date().addingTimeInterval(TimeInterval(minutes * 60))
        TweakSettings.muteUntil = until
        current?.tweak("toast", ["msg": "Senyap \(muteUntilLabel(until))"])
        pushPanelState()
    }
```

d) Tambahkan `pushPanelState()` sebagai baris terakhir di: `toggleBlur()`, `toggleHideBanner()`, `toggleDND()`, `muteOff()`, `editQuietHours()` (setelah toast), `toggleAlwaysOnTop()`, `newTag()` (setelah `acc.pushTags()`), `deleteTag(_:)` (setelah `acc.pushTags()`), `rename(_:)` (setelah `mainWindow.refreshTitle()`), `show(_:)` (setelah `UserDefaults…set`), `removeAccount()` (paling akhir), dan `accountTitleChanged(_:)` (paling akhir).

- [ ] **Step 4: State, push, dispatch**

Tambahkan di `AppDelegate`, di bawah `accountTitleChanged(_:)`:

```swift
    // MARK: panel di halaman

    /// State yang dirender panel di halaman akun `account`.
    func panelState(for account: Account) -> [String: Any] {
        let now = Date()
        let scheduled = dndActive(minutesNow: minutesOfDay(now), start: TweakSettings.dndStart,
                                  end: TweakSettings.dndEnd, enabled: TweakSettings.dndEnabled)
        let temporary = muteActive(now: now, until: TweakSettings.muteUntil)
        let open = account.openChatTitle
        return [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "accounts": accounts.map { ["id": $0.id, "name": $0.name, "unread": $0.unread, "active": mainWindow.active === $0] },
            "blur": TweakSettings.blur,
            "hideBanner": TweakSettings.hideBanner,
            "mute": ["active": temporary, "label": temporary ? muteUntilLabel(TweakSettings.muteUntil ?? .distantFuture) : ""],
            "dnd": ["enabled": TweakSettings.dndEnabled, "start": TweakSettings.dndStart, "end": TweakSettings.dndEnd, "active": scheduled],
            "onTop": mainWindow.window?.level == .floating,
            "tags": account.store.tags.tags.map { t in
                ["name": t.name, "color": t.color, "checked": open.flatMap { account.store.tags.chats[$0]?.contains(t.name) } ?? false]
            },
            "hasOpenChat": open != nil,
            "filter": account.tagFilter,
        ]
    }

    /// Dorong state panel ke satu akun atau ke semua akun.
    func pushPanelState(to account: Account? = nil) {
        for a in (account.map { [$0] } ?? accounts) { a.tweak("setPanelState", ["state": panelState(for: a)]) }
    }

    /// Aksi dari panel di halaman (sudah lewat guard origin). Divalidasi panelAction(from:), lalu dipetakan ke aksi menu.
    func handlePanelAction(_ body: [String: Any], from account: Account) {
        guard let action = panelAction(from: body) else { return }
        switch action {
        case .open: break
        case .switchAccount(let id): if let a = accounts.first(where: { $0.id == id }) { show(a) }
        case .newAccount: newAccount()
        case .renameAccount(let id): if let a = accounts.first(where: { $0.id == id }) { rename(a) }
        case .removeAccount: removeAccount()
        case .toggleBlur: toggleBlur()
        case .toggleBanner: toggleHideBanner()
        case .bookmark: bookmarkMessage()
        case .showBookmarks: account.showBookmarksPanel()
        case .toggleTag(let name): toggleTag(named: name, in: account)
        case .newTag: newTag()
        case .setFilter(let color): setFilter(color, in: account)
        case .mute(let minutes): mute(minutes: minutes)
        case .muteOff: muteOff()
        case .toggleDND: toggleDND()
        case .editDND: editQuietHours()
        case .toggleOnTop: toggleAlwaysOnTop()
        case .reloadCSS: reloadCustomCSS()
        case .debug: debugSelectors()
        }
        pushPanelState()
    }
```

- [ ] **Step 5: Hook di `Account.swift`**

a) Di `applyTweaks()`, tambahkan baris terakhir: `delegate?.pushPanelState(to: self)`.

b) Di `userContentController(_:didReceive:)`, ganti blok

```swift
        if message.name == "wadesk" {
            let title = body["chat"] as? String ?? ""
            openChatTitle = title.isEmpty ? nil : title
            return
        }
```
dengan
```swift
        if message.name == "wadesk" {
            if body["action"] is String {
                delegate?.handlePanelAction(body, from: self)
            } else if let title = body["chat"] as? String {
                openChatTitle = title.isEmpty ? nil : title
                delegate?.pushPanelState(to: self)
            }
            return
        }
```

- [ ] **Step 6: Build, launch check**

Run: `./build.sh` → `selftest OK`, tanpa warning. Launch check seperti Task 1 (open -n, pid sendiri): pastikan app hidup 10 detik, menu Akun ada, lalu kill pid sendiri. Perilaku panel sendiri butuh WhatsApp login (user).

- [ ] **Step 7: Commit**

```bash
git add Helpers.swift Selftest.swift AppDelegate.swift Account.swift
git commit -m "Bridge in-page panel actions to native with strict validation"
```

---

### Task 4: Dokumentasi, hapus smoke-test, versi 0.5.0

**Files:**
- Delete: `docs/smoke-test.md`
- Modify: `README.md`, `Info.plist`, `docs/superpowers/specs/2026-10-01-wa-desk-tweaks-design.md` (satu baris)

- [ ] **Step 1: Hapus checklist**

`git rm docs/smoke-test.md`. Di `README.md`, hapus kalimat `Checklist uji manual: [docs/smoke-test.md](docs/smoke-test.md).` (sisakan kalimat sebelumnya utuh).

- [ ] **Step 2: README**

a) Di bagian **Fitur → Inti**, ganti baris `- Multi-akun: tiap akun satu tab native, sesi login terpisah.` dengan:

```
- Multi-akun dalam satu window: sesi login terpisah per akun, pindah lewat menu **Akun** (⌘1–⌘9) atau panel WA Desk.
```

b) Di **Fitur → Tweaks**, tambahkan baris pertama:

```
- **Panel WA Desk** di bilah navigasi kiri WhatsApp (icon di bawah Meta AI): daftar akun (pindah, ganti nama, tambah, hapus) dan semua Tweaks di satu tempat.
```

c) Di tabel **Cara pakai**, ganti baris `| Akun baru (tab) | ⌘N |` dan `| Pindah akun | ⌃Tab / ⌃⇧Tab |` dengan:

```
| Akun baru (dalam window yang sama) | ⌘N |
| Pindah akun | ⌘1 … ⌘9, ⌃Tab / ⌃⇧Tab, atau panel WA Desk |
| Ganti nama akun | Akun → Ganti Nama Akun…, atau ✎ di panel |
```
dan baris `| Hapus akun yang sedang dilihat (sesi + cache) | File → Hapus Akun Ini… |` menjadi `| Hapus akun yang sedang dilihat (sesi + cache + bookmark/tag) | Akun → Hapus Akun Ini… |`.

d) Di tabel **Tweaks**, tambahkan baris pertama:

```
| Panel WA Desk | klik icon WA Desk di bilah kiri | semua aksi di bawah juga ada di panel; Esc menutup |
```

e) Di **Troubleshooting**, tambahkan bullet:

```
- **Icon WA Desk tidak muncul di bilah kiri**: WhatsApp belum login (icon hanya ada setelah bilah navigasi tampil), atau struktur bilah berubah; jalankan Debug Selector dan lampirkan `debug-dom.txt`.
```

f) Di **Untuk pengembang**, tambahkan dua baris pada blok struktur file setelah `AccountWindow.swift …` (ganti nama itu):

```
Account.swift        satu akun: WKWebView + store + state, navigasi, download, notifikasi, jembatan tweak()
MainWindow.swift     satu window untuk semua akun (webView ditumpuk, satu tampil)
PanelScript.swift    icon di bilah navigasi + panel popover (JS/CSS), dirender dari state native
```

- [ ] **Step 3: Versi + spec**

`Info.plist`: `CFBundleShortVersionString` `0.4.0` → `0.5.0`, `CFBundleVersion` `7` → `8`.
Spec Tweaks §9 (Testing): hapus kalimat yang merujuk `docs/smoke-test.md` kalau ada (kalau tidak ada, lewati).

- [ ] **Step 4: Build, commit**

Run: `./build.sh` → `selftest OK`.

```bash
git add -A
git commit -m "Document the single-window model and in-page panel; bump to 0.5.0"
```
