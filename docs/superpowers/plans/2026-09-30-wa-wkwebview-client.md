# WA WKWebView Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App macOS native ringan pengganti WhatsApp Desktop: satu `WKWebView` per akun di atas web.whatsapp.com, dengan notifikasi native, badge Dock, download, call, dan multi-akun sebagai tab.

**Architecture:** Satu file `main.swift` (AppKit + WebKit + UserNotifications), dibangun `swiftc` lewat `build.sh` menjadi `WA.app`. Setiap akun = `AccountWindow` (NSWindowController) dengan `WKWebsiteDataStore(forIdentifier:)` sendiri; `AppDelegate` pegang daftar akun, menu, badge, dan notifikasi. Logika bercabang dipisah jadi fungsi murni yang dites `WA --selftest` tiap build.

**Tech Stack:** Swift 6.3 (Command Line Tools, tanpa Xcode.app), Cocoa, WebKit, UserNotifications. Nol dependency eksternal.

**Spec:** `docs/superpowers/specs/2026-09-30-wa-wkwebview-client-design.md`

## Global Constraints

- Mac saja, `LSMinimumSystemVersion` `14.0` (butuh `WKWebsiteDataStore(forIdentifier:)`).
- Build hanya dengan `swiftc` dari Command Line Tools. Tidak ada Xcode project, tidak ada SwiftPM.
- Nol dependency eksternal. Framework sistem: Cocoa, WebKit, UserNotifications.
- Satu file sumber `main.swift`. Pecah hanya kalau melewati ~400 baris.
- Bundle id `dev.zen.wa`, nama app `WA`, executable `WA`.
- User agent: `applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"`.
- Codesign ad-hoc (`codesign --force --sign - WA.app`) wajib tiap build.
- Setiap fungsi murni yang punya cabang wajib punya kasus di `selftest()`. `build.sh` gagal kalau selftest gagal.
- Commit tanpa trailer `Co-Authored-By` dan tanpa atribusi AI (aturan user).
- `WA.app/` masuk `.gitignore`.

## Review Focus

1. Judul kembali ke `"WhatsApp"` setelah semua chat dibaca → badge Dock harus hilang (nil), bukan tampil `"0"`. Dipaku oleh `badgeLabel(total: 0) == nil` (Task 2).
2. Download file dengan nama yang sudah ada di `~/Downloads` → file lama tidak boleh tertimpa. Dipaku oleh kasus `uniqueURL` suffix `(1)`, `(2)` dan tanpa ekstensi (Task 3).
3. `UserDefaults["accounts"]` berisi string bukan UUID (edit manual / korup) → dilewati tanpa crash; kalau semua invalid, buat satu akun baru. Dipaku oleh `validAccountIDs` (Task 1); fallback `Accounts.all()` dicek manual di Task 2.
4. Notifikasi masuk saat user sedang melihat tab akun itu → tidak boleh muncul banner dobel; saat lihat tab akun lain atau app di background → harus muncul. Dipaku oleh tiga kasus `shouldNotify` (Task 4).
5. Navigasi tanpa host (`about:blank`, popup internal WhatsApp) → tidak boleh dilempar ke browser default; `wa.me` dan domain lain → harus ke browser. Dipaku oleh empat kasus `isExternal` (Task 3) dan guard skema `http` di `createWebViewWith`.

---

### Task 1: Skeleton build + selftest harness

**Files:**
- Create: `main.swift`
- Create: `Info.plist`
- Create: `build.sh`
- Create: `.gitignore`

**Interfaces:**
- Consumes: —
- Produces:
  - `func unreadCount(_ title: String) -> Int`
  - `func validAccountIDs(_ raw: [String]) -> [String]`
  - `func selftest() -> Int32` dengan helper lokal `check(_ ok: Bool, _ name: String)`; task berikutnya **menambah** baris `check(...)` di dalam fungsi ini, sebelum baris `if failed.isEmpty`.
  - Marker komentar di `main.swift` yang dipakai task berikutnya sebagai titik sisip: `// MARK: - Accounts`, `// MARK: - AccountWindow`, `// MARK: - AppDelegate`, `// MARK: - Main`.

- [ ] **Step 1: Tulis `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>WA</string>
	<key>CFBundleIdentifier</key>
	<string>dev.zen.wa</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>WA</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSCameraUsageDescription</key>
	<string>Dipakai untuk video call WhatsApp.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Dipakai untuk voice/video call dan voice note WhatsApp.</string>
</dict>
</plist>
```

- [ ] **Step 2: Tulis `build.sh` dan `.gitignore`**

`build.sh`:

```sh
#!/bin/sh
# Build WA.app dengan swiftc (Command Line Tools), lalu jalankan selftest.
set -eu
cd "$(dirname "$0")"
APP=WA.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/WA" \
  -framework Cocoa -framework WebKit -framework UserNotifications
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Ad-hoc sign: TCC (kamera/mic) dan UNUserNotificationCenter butuh identitas bundle stabil.
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/WA" --selftest
echo "built $APP"
```

`.gitignore`:

```
WA.app/
```

Jalankan: `chmod +x build.sh`

- [ ] **Step 3: Tulis selftest yang gagal (fungsi belum ada)**

`main.swift`:

```swift
import Cocoa
import WebKit
import UserNotifications

// MARK: - Helpers murni (dites oleh --selftest)

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

    if failed.isEmpty { print("selftest OK"); return 0 }
    for f in failed { FileHandle.standardError.write(Data("FAIL: \(f)\n".utf8)) }
    return 1
}

if CommandLine.arguments.contains("--selftest") { exit(selftest()) }

// MARK: - Accounts

// MARK: - AccountWindow

// MARK: - AppDelegate

// MARK: - Main
```

- [ ] **Step 4: Jalankan build, pastikan gagal karena fungsi belum ada**

Run: `./build.sh`
Expected: compile error `cannot find 'unreadCount' in scope` dan `cannot find 'validAccountIDs' in scope`.

- [ ] **Step 5: Implementasi dua helper**

Sisipkan di bawah `// MARK: - Helpers murni (dites oleh --selftest)`:

```swift
/// "(3) WhatsApp" -> 3, "WhatsApp" -> 0. WhatsApp Web menaruh jumlah unread di judul halaman.
func unreadCount(_ title: String) -> Int {
    guard title.hasPrefix("("), let close = title.firstIndex(of: ")") else { return 0 }
    return Int(title[title.index(after: title.startIndex)..<close]) ?? 0
}

/// Buang id akun yang bukan UUID valid (UserDefaults bisa diedit/korup).
func validAccountIDs(_ raw: [String]) -> [String] {
    raw.filter { UUID(uuidString: $0) != nil }
}
```

- [ ] **Step 6: Build lagi, pastikan selftest lulus**

Run: `./build.sh`
Expected: baris `selftest OK` lalu `built WA.app`. Exit code 0.

- [ ] **Step 7: Commit**

```bash
git add main.swift Info.plist build.sh .gitignore
git commit -m "Add build script, Info.plist, and selftest harness"
```

---

### Task 2: Satu akun: window, WKWebView, menu, badge, hide-on-close

**Files:**
- Modify: `main.swift` (sisip di bawah marker `// MARK: - Helpers murni`, `// MARK: - Accounts`, `// MARK: - AccountWindow`, `// MARK: - AppDelegate`, `// MARK: - Main`; tambah `check` di `selftest()`)

**Interfaces:**
- Consumes: `unreadCount`, `validAccountIDs` (Task 1).
- Produces:
  - `func badgeLabel(total: Int) -> String?`
  - `enum Accounts { static func all() -> [String]; static func add() -> String; static func remove(_ id: String) }`
  - `final class AccountWindow: NSWindowController, NSWindowDelegate { let id: String; let webView: WKWebView; private(set) var unread: Int; init(id: String) }`
  - `final class AppDelegate: NSObject, NSApplicationDelegate { private(set) var accounts: [AccountWindow]; var current: AccountWindow?; func open(id: String) -> AccountWindow; func present(_ account: AccountWindow); func refreshBadge(); private func buildMenu() }` dengan menu **File** berisi item `Close` (Task 5 menyisipkan item akun di atasnya).
  - Di `AccountWindow.init`, baris `win.delegate = self` adalah titik sisip Task 3 untuk `navigationDelegate`/`uiDelegate`, dan baris `super.init(window: win)` adalah titik sisip Task 4 untuk message handler.

- [ ] **Step 1: Tambah test `badgeLabel` (gagal)**

Di `selftest()`, sebelum `if failed.isEmpty`:

```swift
    check(badgeLabel(total: 0) == nil, "badgeLabel nil saat 0")
    check(badgeLabel(total: 7) == "7", "badgeLabel 7")
```

- [ ] **Step 2: Build, pastikan gagal**

Run: `./build.sh`
Expected: `cannot find 'badgeLabel' in scope`.

- [ ] **Step 3: Implementasi `badgeLabel`**

Di bawah `validAccountIDs`:

```swift
/// Badge Dock: nil saat 0 supaya badge hilang, bukan menampilkan "0".
func badgeLabel(total: Int) -> String? { total > 0 ? String(total) : nil }
```

- [ ] **Step 4: Tulis `Accounts`**

Di bawah `// MARK: - Accounts`:

```swift
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
```

- [ ] **Step 5: Tulis `AccountWindow`**

Di bawah `// MARK: - AccountWindow`:

```swift
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
```

- [ ] **Step 6: Tulis `AppDelegate` dan `Main`**

Di bawah `// MARK: - AppDelegate`:

```swift
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
```

Di bawah `// MARK: - Main`:

```swift
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 7: Build, selftest lulus, app jalan**

Run: `./build.sh && open WA.app`
Expected: `selftest OK`; window "WhatsApp" muncul dengan halaman QR login.

Kalau halaman tampil pesan browser tidak didukung (mis. "WhatsApp works with Google Chrome…"): tambahkan di `AccountWindow.init` setelah `webView.allowsMagnification = true` baris berikut, build ulang, dan catat di README bahwa fallback ini dipakai:

```swift
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
```

- [ ] **Step 8: Smoke test manual (butuh user, HP di tangan)**

1. Scan QR dari HP → daftar chat muncul.
2. Ketik pesan, Cmd+C / Cmd+V teks di kolom chat → jalan.
3. Terima 1 pesan baru tanpa dibuka → judul window jadi `(1) WhatsApp`, ikon Dock badge `1`. Buka chat itu → badge hilang.
4. Cmd+W → window hilang, app tetap di Dock. Klik ikon Dock → window kembali, masih di chat yang sama.
5. Cmd+= / Cmd+- / Cmd+0 → zoom berubah. Cmd+R → reload, tetap login.
6. Cmd+Q, `open WA.app` lagi → langsung masuk tanpa QR (sesi persisten), posisi/ukuran window sama.
7. Cek Review Focus 3: `defaults write dev.zen.wa accounts -array "bukan-uuid"`, buka app → tetap jalan dengan 1 akun baru (QR lagi). Setelah itu kembalikan: `defaults delete dev.zen.wa accounts` lalu login ulang (atau terima bahwa akun lama harus login lagi).

Catat hasil tiap poin. Poin gagal = task belum selesai.

- [ ] **Step 9: Commit**

```bash
git add main.swift
git commit -m "Add single-account window with WKWebView, menu, and dock badge"
```

---

### Task 3: Navigasi: link luar, popup, download, upload, izin kamera/mic

**Files:**
- Modify: `main.swift` (helper baru di bawah `badgeLabel`; dua baris di `AccountWindow.init`; extension baru di bawah class `AccountWindow`; `check` baru di `selftest()`)

**Interfaces:**
- Consumes: `AccountWindow` (Task 2), `window` property dari NSWindowController.
- Produces:
  - `func isExternal(_ url: URL) -> Bool`
  - `func uniqueURL(in dir: URL, name: String, exists: (URL) -> Bool) -> URL`
  - `extension AccountWindow: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate`

- [ ] **Step 1: Tambah test `isExternal` dan `uniqueURL` (gagal)**

Di `selftest()`, sebelum `if failed.isEmpty`:

```swift
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
```

- [ ] **Step 2: Build, pastikan gagal**

Run: `./build.sh`
Expected: `cannot find 'isExternal' in scope`, `cannot find 'uniqueURL' in scope`.

- [ ] **Step 3: Implementasi helper**

Di bawah `badgeLabel`:

```swift
/// Host selain web.whatsapp.com dibuka di browser default. Tanpa host (about:blank) = internal.
func isExternal(_ url: URL) -> Bool {
    guard let host = url.host else { return false }
    return host != "web.whatsapp.com"
}

/// Nama file unik di dir: "a.jpg" → "a (1).jpg" → "a (2).jpg" … supaya download tidak menimpa.
func uniqueURL(in dir: URL, name: String, exists: (URL) -> Bool) -> URL {
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
```

- [ ] **Step 4: Build, selftest lulus**

Run: `./build.sh`
Expected: `selftest OK`.

- [ ] **Step 5: Pasang delegate di `AccountWindow.init`**

Setelah baris `win.delegate = self` tambahkan:

```swift
        webView.navigationDelegate = self
        webView.uiDelegate = self
```

- [ ] **Step 6: Tulis extension delegate**

Langsung di bawah penutup class `AccountWindow` (sebelum `// MARK: - AppDelegate`):

```swift
// MARK: - Navigasi, download, media

extension AccountWindow: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { return decisionHandler(.download) }
        if action.navigationType == .linkActivated, let url = action.request.url, isExternal(url) {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
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

    /// target=_blank / window.open → browser default. Hanya skema http(s).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme?.hasPrefix("http") == true {
            NSWorkspace.shared.open(url)
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
```

- [ ] **Step 7: Build dan smoke test manual**

Run: `./build.sh && open WA.app`
Expected: `selftest OK`, app jalan, masih login.

1. Klik link `https://…` di chat → terbuka di browser default, WA tetap di halaman chat.
2. Terima foto → klik download → file muncul di `~/Downloads`. Download foto yang sama lagi → file kedua bernama `… (1).jpg`, yang pertama utuh. (macOS bisa prompt izin akses folder Downloads sekali; izinkan.)
3. Klik attach (klip) → Foto & Video → NSOpenPanel muncul → pilih file → terkirim. Drag-drop file ke chat → terkirim.
4. Rekam voice note → macOS prompt izin mikrofon (teks dari Info.plist) → izinkan → voice note terkirim.
5. Voice call ke kontak → tersambung, suara dua arah. Video call → prompt kamera → video dua arah. Ini Risiko #2 di spec; kalau call gagal, catat pesan error di halaman/console (`Safari > Develop` tidak tersedia; pakai `log stream --predicate 'process == "WA"'` di terminal) dan laporkan sebelum lanjut.

- [ ] **Step 8: Commit**

```bash
git add main.swift
git commit -m "Handle external links, downloads, file upload, and media permissions"
```

---

### Task 4: Notifikasi native via shim `window.Notification`

**Files:**
- Modify: `main.swift` (helper + konstanta shim di bawah `uniqueURL`; dua sisipan di `AccountWindow.init`; extension baru; perubahan `AppDelegate`; `check` baru di `selftest()`)

**Interfaces:**
- Consumes: `AccountWindow`, `AppDelegate.accounts`, `AppDelegate.present(_:)` (Task 2).
- Produces:
  - `func shouldNotify(appActive: Bool, windowKey: Bool) -> Bool`
  - `let notificationShim: String` (JS), mendefinisikan `window.Notification` dan `window.__waNotifClick(id)`.
  - `extension AccountWindow: WKScriptMessageHandler` untuk handler bernama `"notify"`, body `{id: String, title: String, body: String, tag: String}`; `userInfo` notifikasi = `["account": id, "nid": id notifikasi]`.
  - `AppDelegate` menjadi `UNUserNotificationCenterDelegate`.

- [ ] **Step 1: Tambah test `shouldNotify` (gagal)**

Di `selftest()`, sebelum `if failed.isEmpty`:

```swift
    check(shouldNotify(appActive: true, windowKey: true) == false, "shouldNotify ditekan saat dilihat")
    check(shouldNotify(appActive: true, windowKey: false) == true, "shouldNotify tab lain")
    check(shouldNotify(appActive: false, windowKey: true) == true, "shouldNotify app background")
```

- [ ] **Step 2: Build, pastikan gagal**

Run: `./build.sh`
Expected: `cannot find 'shouldNotify' in scope`.

- [ ] **Step 3: Implementasi helper dan shim**

Di bawah `uniqueURL`:

```swift
/// Jangan tampilkan notifikasi kalau user sedang melihat window akun itu (hindari dobel).
func shouldNotify(appActive: Bool, windowKey: Bool) -> Bool { !(appActive && windowKey) }

/// WKWebView tidak punya window.Notification. Shim ini meneruskan ke native lewat message handler "notify".
let notificationShim = """
(() => {
  let seq = 0;
  const live = {};
  class Notification {
    static get permission() { return "granted"; }
    static requestPermission(cb) { if (cb) cb("granted"); return Promise.resolve("granted"); }
    constructor(title, opts = {}) {
      this.title = title; this.body = opts.body || ""; this.tag = opts.tag || "";
      this.onclick = null; this.onclose = null; this.onshow = null; this.onerror = null;
      this._id = String(++seq);
      live[this._id] = this;
      window.webkit.messageHandlers.notify.postMessage({
        id: this._id, title: String(title), body: String(this.body), tag: String(this.tag)
      });
    }
    close() { delete live[this._id]; if (this.onclose) this.onclose(); }
    addEventListener(type, fn) { if (type === "click") this.onclick = fn; }
    removeEventListener() {}
  }
  window.Notification = Notification;
  window.__waNotifClick = (id) => { const n = live[id]; if (n && n.onclick) n.onclick(new Event("click")); };
})();
"""
```

- [ ] **Step 4: Inject shim dan daftarkan handler di `AccountWindow.init`**

Sebelum baris `webView = WKWebView(frame: .zero, configuration: cfg)`:

```swift
        cfg.userContentController.addUserScript(WKUserScript(
            source: notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
```

Setelah baris `super.init(window: win)` (pakai controller milik webView, bukan `cfg`, karena WKWebView menyalin konfigurasi):

```swift
        webView.configuration.userContentController.add(self, name: "notify")
```

- [ ] **Step 5: Tulis handler pesan**

Di bawah extension Task 3 (sebelum `// MARK: - AppDelegate`):

```swift
// MARK: - Notifikasi

extension AccountWindow: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
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
```

- [ ] **Step 6: Ubah `AppDelegate`**

Ganti deklarasi class:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
```

Di `applicationDidFinishLaunching`, setelah `buildMenu()`:

```swift
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
```

Tambahkan method baru di dalam `AppDelegate`, di bawah `refreshBadge()`:

```swift
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
            NSApp.activate(ignoringOtherApps: true)
            present(account)
            if let nid = info["nid"] as? String, Int(nid) != nil {
                account.webView.evaluateJavaScript("window.__waNotifClick('\(nid)')")
            }
        }
        handler()
    }
```

- [ ] **Step 7: Build dan smoke test manual**

Run: `./build.sh && open WA.app`
Expected: `selftest OK`; saat launch macOS prompt izin notifikasi → izinkan.

1. Di WhatsApp Web: Settings → Notifications → pastikan tidak ada banner "Turn on desktop notifications" (shim mengaku `granted`).
2. Pindah ke app lain (WA di background), minta seseorang kirim pesan → banner notifikasi macOS muncul dengan nama pengirim + isi. Klik banner → WA aktif, chat pengirim terbuka.
3. Cmd+W (window disembunyikan), terima pesan → banner tetap muncul dalam beberapa detik (Risiko #4 di spec). Kalau telat > 30 detik, ganti `sender.orderOut(nil)` di `windowShouldClose` menjadi `sender.miniaturize(nil)`, build ulang, uji lagi, dan catat di README.
4. WA aktif dan chat terbuka di layar, terima pesan → **tidak** ada banner (Review Focus 4).
5. Dua pesan beruntun dari chat yang sama → satu banner yang diperbarui, bukan dua.

- [ ] **Step 8: Commit**

```bash
git add main.swift
git commit -m "Bridge web notifications to native macOS notifications"
```

---

### Task 5: Multi-akun: tambah, hapus, tab

**Files:**
- Modify: `main.swift` (menu File di `buildMenu()`; method baru di `AppDelegate`)

**Interfaces:**
- Consumes: `Accounts.add/remove`, `AppDelegate.open/present/current/refreshBadge` (Task 2), handler `"notify"` (Task 4).
- Produces: `@objc func newAccount()`, `@objc func removeAccount()`, `@objc func newWindowForTab(_:)` di `AppDelegate`.

- [ ] **Step 1: Tambah item menu**

Di `buildMenu()`, ganti blok `menu("File", …)` menjadi:

```swift
        _ = menu("File", [
            item("Akun Baru", #selector(newAccount), "n"),
            item("Hapus Akun Ini…", #selector(removeAccount)),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
```

- [ ] **Step 2: Tulis aksi akun**

Di `AppDelegate`, di bawah `@objc func zoomReset()`:

```swift
    @objc func newAccount() { open(id: Accounts.add()) }

    /// Tombol "+" di tab bar macOS memanggil ini lewat responder chain.
    @objc func newWindowForTab(_ sender: Any?) { newAccount() }

    @objc func removeAccount() {
        guard let account = current, let win = account.window else { return }
        let alert = NSAlert()
        alert.messageText = "Hapus akun ini dari WA?"
        alert.informativeText = "Sesi login dan cache akun ini di Mac ikut dihapus. Chat di HP tidak terpengaruh."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hapus")
        alert.addButton(withTitle: "Batal")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let id = account.id
        account.webView.stopLoading()
        account.webView.configuration.userContentController.removeScriptMessageHandler(forName: "notify")
        win.close()
        accounts.removeAll { $0 === account }
        Accounts.remove(id)
        refreshBadge()
        // ponytail: tunda 1 detik supaya WebKit sempat melepas data store; kalau tetap gagal cukup log, foldernya tidak dipakai lagi.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            WKWebsiteDataStore.remove(forIdentifier: UUID(uuidString: id)!) { error in
                if let error {
                    FileHandle.standardError.write(Data("hapus data store gagal: \(error.localizedDescription)\n".utf8))
                }
            }
        }
        if accounts.isEmpty { open(id: Accounts.all()[0]) }
    }
```

- [ ] **Step 3: Build dan smoke test manual**

Run: `./build.sh && open WA.app`
Expected: `selftest OK`.

1. Cmd+N → tab kedua "WhatsApp" muncul di window yang sama dengan halaman QR. Tab pertama tetap login. Scan QR dengan nomor kedua (atau nomor yang sama sebagai linked device lain) → login.
2. Cmd+Shift+] / Cmd+Shift+[ → pindah tab. Menu Window punya "Show Next Tab" dll (otomatis dari AppKit).
3. Terima pesan di akun tab yang tidak aktif → banner muncul; badge Dock = jumlah unread kedua akun. Klik banner → tab akun yang benar terpilih.
4. Cmd+Q, buka lagi → dua tab kembali, keduanya login.
5. Pilih tab kedua → File → Hapus Akun Ini… → Batal → tidak ada perubahan. Ulangi → Hapus → tab hilang, badge terkoreksi. Jalankan `./WA.app/Contents/MacOS/WA` dari terminal untuk mengulang langkah ini dan pastikan tidak ada baris `hapus data store gagal` di stderr.
6. Hapus akun terakhir → langsung muncul tab baru dengan QR (tidak pernah nol akun).

- [ ] **Step 4: Commit**

```bash
git add main.swift
git commit -m "Add multi-account support with native window tabs"
```

---

### Task 6: README + smoke test penuh + perbandingan RAM

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: semua task sebelumnya.
- Produces: dokumentasi build dan checklist verifikasi; hasil pengukuran RAM/storage.

- [ ] **Step 1: Tulis `README.md`**

```markdown
# WA

Client WhatsApp Desktop ringan untuk macOS 14+. Satu `WKWebView` (WebKit sistem)
per akun di atas web.whatsapp.com, tanpa Electron, tanpa dependency.
Notifikasi native, badge Dock, download ke ~/Downloads, call, multi-akun sebagai tab.

## Build

Butuh Command Line Tools (`xcode-select --install`). Tidak butuh Xcode.app.

    ./build.sh && open WA.app

`build.sh` mengompilasi `main.swift`, membungkus `WA.app`, codesign ad-hoc,
lalu menjalankan `WA --selftest` (fungsi murni: parsing badge, filter akun,
nama file download, aturan link luar, aturan notifikasi).

## Pakai

- Cmd+N: akun baru (tab). Cmd+Shift+[ / ]: pindah akun.
- File → Hapus Akun Ini…: hapus sesi + cache akun yang sedang dilihat.
- Cmd+W menyembunyikan window; pesan tetap masuk. Keluar dengan Cmd+Q.
- Klik ikon Dock menampilkan lagi window yang disembunyikan.
- Cmd+= / Cmd+- / Cmd+0 zoom. Cmd+R reload.

Data per akun disimpan WebKit per UUID, biasanya di `~/Library/WebKit/dev.zen.wa/`
(kalau tidak ada: `find ~/Library -maxdepth 3 -name 'dev.zen.wa*'`).
Daftar akun di `defaults read dev.zen.wa accounts`.

## Tidak ada (sengaja)

App icon, auto-update, ikon menubar, launch at login, screen share saat call
(`getDisplayMedia` tidak tersedia di WKWebView).

## Checklist smoke test

- [ ] QR login, daftar chat muncul
- [ ] Kirim teks, foto, dokumen, voice note; Cmd+C/V di kolom chat
- [ ] Download media → ~/Downloads, nama unik kalau bentrok
- [ ] Link luar terbuka di browser default
- [ ] Badge Dock naik saat unread, hilang saat dibaca
- [ ] Notifikasi saat app background dan saat window disembunyikan; klik membuka chat
- [ ] Tidak ada notifikasi saat chat sedang dilihat
- [ ] Voice call dan video call dua arah
- [ ] Akun kedua (Cmd+N), pindah tab, notifikasi & badge gabungan
- [ ] Hapus akun; hapus akun terakhir membuat akun baru
- [ ] Cmd+Q lalu buka lagi: semua akun masih login, posisi window sama
```

- [ ] **Step 2: Jalankan seluruh checklist**

Run: `./build.sh && open WA.app`, lalu kerjakan tiap baris checklist di README. Tandai `[x]` yang lulus langsung di README. Baris yang gagal: perbaiki di task pemiliknya (Task 2–5) sebelum lanjut, jangan ditandai lulus.

- [ ] **Step 3: Ukur RAM dan storage, catat di README**

Tutup Safari dan app WebKit lain dulu (proses `com.apple.WebKit.*` dipakai bersama, ikut terhitung). Setelah 5 menit pemakaian normal dengan 1 akun:

```sh
ps -eo rss,comm | grep -E 'WA$|WebKit|com.apple.WebKit' | awk '{s+=$1} END {print "WA total MB:", s/1024}'
du -sh ~/Library/WebKit/dev.zen.wa 2>/dev/null || find ~/Library -maxdepth 3 -name 'dev.zen.wa*' -exec du -sh {} +
```

Bandingkan dengan WhatsApp resmi (jalankan sebentar, ukur `ps -eo rss,comm | grep -i whatsapp`, dan `du -sh ~/Library/Containers/net.whatsapp.WhatsApp ~/Library/Group\ Containers/group.net.whatsapp.WhatsApp.shared`). Tambahkan bagian `## Ukuran` di README dengan tabel dua baris (WA vs WhatsApp resmi, kolom RAM dan storage) berisi angka hasil ukur.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Add README with usage, smoke test checklist, and measurements"
```
