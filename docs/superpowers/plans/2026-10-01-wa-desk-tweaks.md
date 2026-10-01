# WA Desk Tweaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tambahkan ke WA Desk: blur privasi, sembunyikan banner download, bookmark pesan lokal dengan panel, tag chat lokal dengan titik warna + filter, hotkey global ⌥⌘W, selalu di atas, jadwal senyap, dan CSS kustom.

**Architecture:** Satu `WKUserScript` (`tweaksScript`) mengekspos `window.__wadesk` dan satu stylesheet beratribut (`tweaksStyle`); semua ketergantungan DOM WhatsApp hidup di `Tweaks.swift`. Native memanggil fungsi JS lewat `callAsyncJavaScript` dengan argumen terstruktur (tanpa interpolasi string), menyimpan setting di UserDefaults dan bookmark/tag di JSON per akun, dan menyediakan menu **Tweaks** + panel bookmark native. `main.swift` (533 baris) dipecah dulu menjadi file per tanggung jawab.

**Tech Stack:** Swift 6.3 (Command Line Tools), Cocoa, WebKit, UserNotifications, Carbon (hotkey), JavaScriptCore (cek sintaks JS di selftest). Nol dependency eksternal.

**Spec:** `docs/superpowers/specs/2026-10-01-wa-desk-tweaks-design.md` (dan spec inti `docs/superpowers/specs/2026-09-30-wa-wkwebview-client-design.md`)

## Global Constraints

- Build hanya lewat `./build.sh` (`swiftc -O -target "$(uname -m)-apple-macos14.0" *.swift …`). Tidak ada Xcode project, SwiftPM, atau dependency eksternal. Framework: Cocoa, WebKit, UserNotifications, Carbon, JavaScriptCore.
- Hanya `main.swift` yang boleh berisi kode top-level. File lain: deklarasi saja.
- Bundle id tetap `dev.zen.wa`; nama app "WA Desk"; executable `wa-desk`; bundle `WA Desk.app`.
- Semua ketergantungan pada DOM WhatsApp (selector, atribut, struktur) hanya boleh ada di `tweaksScript`/`tweaksStyle` di `Tweaks.swift`. Swift lain memanggil `__wadesk.*` saja.
- Pemanggilan JS dari native lewat `AccountWindow.tweak(_:_:completion:)` (`callAsyncJavaScript` dengan `arguments`), tidak pernah menyisipkan data ke string JS.
- Setiap fungsi murni bercabang punya kasus di `selftest()`; `./build.sh` menjalankan `wa-desk --selftest` dan gagal kalau selftest gagal. `--selftest` keluar sebelum `NSApplication`.
- Setting Tweaks di UserDefaults dengan key persis: `blur`, `hideBanner` (default true), `dndEnabled`, `dndStart` (`"22:00"`), `dndEnd` (`"07:00"`).
- Data per akun di `~/Library/Application Support/wa-desk/<accountId>/bookmarks.json` dan `tags.json`, tulis atomik, file korup → `.bak-<unix>` + mulai kosong.
- Palet tag persis: `#34D399 #60A5FA #F472B6 #FBBF24 #A78BFA #F87171`. Nama tag 1–24 karakter setelah trim.
- Baris chat yang tidak cocok filter diredupkan (`opacity: .25`), tidak disembunyikan.
- Teks menu/toast dalam bahasa Indonesia seperti di spec §6 dan §8.
- Commit: pesan polos, tanpa trailer `Co-Authored-By`, tanpa atribusi AI.

## Review Focus

1. Jadwal senyap lewat tengah malam (`22:00`–`07:00`) pada 23:00, 03:00, dan 12:00, serta `start == end` → harus aktif, aktif, tidak, tidak. Dipaku oleh kasus `dndActive` (Task 2).
2. Hasil `capture()` yang tidak lengkap (tanpa `id`, teks 400 karakter, `fromMe` bukan Bool) → bookmark ditolak / dipotong 300 / `fromMe=false`, bukan crash. Dipaku oleh kasus `bookmark(fromCapture:)` (Task 2).
3. `tags.json` menyebut nama tag yang sudah dihapus → chat itu tanpa titik, tag pertama yang masih ada menang. Dipaku oleh `tagMap` (Task 2).
4. `bookmarks.json`/`tags.json` korup → file dipindah ke `.bak-<unix>`, store kosong, app tetap jalan. Dipaku oleh kasus `TweakStore` korup (Task 2).
5. `tweaksScript` salah sintaks atau tidak mendefinisikan API → semua tweak mati diam-diam. Dipaku oleh evaluasi di `JSContext` tanpa exception dan `typeof __wadesk.capture == "function"` (Task 3); skrip wajib tidak menyentuh `document` saat dimuat tanpa DOM.

---

### Task 1: Pecah `main.swift` menjadi file per tanggung jawab

**Files:**
- Create: `Helpers.swift`, `Selftest.swift`, `Accounts.swift`, `AccountWindow.swift`, `AppDelegate.swift`
- Modify: `main.swift` (sisakan entry saja), `build.sh`

**Interfaces:**
- Consumes: isi `main.swift` saat ini (533 baris), dibagi oleh header `// MARK:`.
- Produces: tata letak file yang dipakai semua task berikutnya. Tidak ada perubahan perilaku; selftest dan launch harus identik.

- [ ] **Step 1: Pindahkan bagian ke file baru (tanpa mengubah isi)**

Gunakan header `// MARK:` di `main.swift` sebagai batas. Setiap file baru diawali baris import yang disebut. Setelah dipindah, hapus bagian itu dari `main.swift`.

| Bagian `main.swift` | Ke file | Import di atas file |
|---|---|---|
| dari `// MARK: - Helpers murni` sampai tepat sebelum `// MARK: - Selftest` (termasuk `let waHome`, semua `func`, `let notificationShim`) | `Helpers.swift` | `import Foundation` |
| dari `// MARK: - Selftest` sampai tepat sebelum baris `if CommandLine.arguments.contains("--selftest")` (yaitu `func selftest() -> Int32 { … }`) | `Selftest.swift` | `import Foundation` |
| dari `// MARK: - Accounts` sampai tepat sebelum `// MARK: - AccountWindow` | `Accounts.swift` | `import Foundation` |
| dari `// MARK: - AccountWindow` sampai tepat sebelum `// MARK: - AppDelegate` (class + extension navigasi + extension notifikasi) | `AccountWindow.swift` | `import Cocoa`, `import WebKit`, `import UserNotifications` |
| dari `// MARK: - AppDelegate` sampai tepat sebelum `// MARK: - Main` | `AppDelegate.swift` | `import Cocoa`, `import WebKit`, `import UserNotifications` |

- [ ] **Step 2: Tulis ulang `main.swift` menjadi entry saja**

Isi `main.swift` seluruhnya:

```swift
import Cocoa

// Entry point WA Desk. Deklarasi ada di file lain; hanya file ini yang boleh punya kode top-level.
if CommandLine.arguments.contains("--selftest") { exit(selftest()) }

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Ubah `build.sh` agar mengompilasi semua file dan framework baru**

Ganti baris `swiftc -O -target "$TARGET" main.swift -o "$APP/Contents/MacOS/wa-desk" \` dan baris lanjutannya menjadi:

```sh
swiftc -O -target "$TARGET" *.swift -o "$APP/Contents/MacOS/wa-desk" \
  -framework Cocoa -framework WebKit -framework UserNotifications \
  -framework Carbon -framework JavaScriptCore
```

(`*.swift` hanya menangkap file di root; `icon/make-icon.swift` tetap dikompilasi terpisah oleh baris di bawahnya.)

- [ ] **Step 4: Build dan pastikan identik**

Run: `./build.sh`
Expected: `selftest OK`, `built WA Desk.app`, tanpa warning. Lalu:

```sh
wc -l *.swift
grep -c "" main.swift   # ≤ 12
open "WA Desk.app"; sleep 8; pgrep -x wa-desk && osascript -e 'quit app "wa-desk"'
```
Expected: `pgrep` mencetak pid; app keluar bersih.

- [ ] **Step 5: Commit**

```bash
git add main.swift Helpers.swift Selftest.swift Accounts.swift AccountWindow.swift AppDelegate.swift build.sh
git commit -m "Split main.swift into focused files"
```

---

### Task 2: Model, setting, store, dan fungsi murni Tweaks

**Files:**
- Create: `Tweaks.swift`
- Modify: `Helpers.swift` (tambah fungsi murni di bawah `shouldNotify`), `Selftest.swift` (tambah `check` sebelum `if failed.isEmpty`)

**Interfaces:**
- Consumes: `check(_:_:)` lokal di `selftest()`.
- Produces:
  - `struct Bookmark: Codable, Equatable { id, chat, jid: String?, text, time, fromMe: Bool, savedAt: Date }`
  - `struct Tag: Codable, Equatable { name, color }`, `struct TagData: Codable, Equatable { tags: [Tag], chats: [String: [String]] }`
  - `enum TweakSettings { static var blur, hideBanner, dndEnabled: Bool; static var dndStart, dndEnd: String }`
  - `final class TweakStore { init(accountID:base:); bookmarks: [Bookmark]; tags: TagData; onChange: (() -> Void)?; add(_:); remove(bookmarkID:); update(_ change: (inout TagData) -> Void) }`
  - `let tagPalette: [String]`, `func minutesOfDay(_ hhmm: String) -> Int?`, `func minutesOfDay(_ date: Date, calendar: Calendar) -> Int`, `func dndActive(minutesNow:start:end:enabled:) -> Bool`, `func bookmark(fromCapture:savedAt:) -> Bookmark?`, `func tagColorValid(_:) -> Bool`, `func tagNameValid(_:) -> Bool`, `func tagMap(_ data: TagData) -> [String: String]`

- [ ] **Step 1: Tambah selftest (gagal)**

Di `Selftest.swift`, sebelum `if failed.isEmpty`:

```swift
    // Jadwal senyap
    check(minutesOfDay("22:00") == 1320, "minutesOfDay 22:00")
    check(minutesOfDay("7:5") == 425, "minutesOfDay 7:5")
    check(minutesOfDay("25:00") == nil, "minutesOfDay jam >23")
    check(minutesOfDay("ab") == nil, "minutesOfDay non-angka")
    check(dndActive(minutesNow: 1380, start: "22:00", end: "07:00", enabled: false) == false, "dnd disabled")
    check(dndActive(minutesNow: 600, start: "09:00", end: "17:00", enabled: true) == true, "dnd dalam rentang")
    check(dndActive(minutesNow: 1020, start: "09:00", end: "17:00", enabled: true) == false, "dnd batas akhir eksklusif")
    check(dndActive(minutesNow: 1380, start: "22:00", end: "07:00", enabled: true) == true, "dnd malam 23:00")
    check(dndActive(minutesNow: 180, start: "22:00", end: "07:00", enabled: true) == true, "dnd malam 03:00")
    check(dndActive(minutesNow: 720, start: "22:00", end: "07:00", enabled: true) == false, "dnd siang 12:00")
    check(dndActive(minutesNow: 600, start: "10:00", end: "10:00", enabled: true) == false, "dnd start==end")
    check(dndActive(minutesNow: 600, start: "x", end: "07:00", enabled: true) == false, "dnd jam invalid")

    // Bookmark dari hasil capture()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let full = bookmark(fromCapture: ["id": "true_628@c.us_ABC", "chat": "Budi", "jid": "628@c.us", "text": "halo",
                                      "time": "[10:00, 1/10/2026]", "fromMe": true], savedAt: now)
    check(full == Bookmark(id: "true_628@c.us_ABC", chat: "Budi", jid: "628@c.us", text: "halo",
                           time: "[10:00, 1/10/2026]", fromMe: true, savedAt: now), "bookmark lengkap")
    check(bookmark(fromCapture: ["chat": "Budi"], savedAt: now) == nil, "bookmark tanpa id")
    check(bookmark(fromCapture: ["id": "x", "chat": ""], savedAt: now) == nil, "bookmark chat kosong")
    check(bookmark(fromCapture: ["id": "x", "chat": "Budi", "text": String(repeating: "a", count: 400)], savedAt: now)?.text.count == 300, "bookmark teks dipotong 300")
    check(bookmark(fromCapture: ["id": "x", "chat": "Budi", "fromMe": "yes"], savedAt: now)?.fromMe == false, "bookmark fromMe bukan Bool")

    // Tag
    check(tagColorValid("#34D399") && !tagColorValid("#000000"), "tagColorValid")
    check(tagNameValid("Kerja") && tagNameValid(" a ") && !tagNameValid("  ") && !tagNameValid(String(repeating: "a", count: 25)), "tagNameValid")
    let td = TagData(tags: [Tag(name: "Kerja", color: "#60A5FA"), Tag(name: "Keluarga", color: "#F472B6")],
                     chats: ["Budi": ["Hilang", "Kerja", "Keluarga"], "Ani": ["Hilang"]])
    check(tagMap(td) == ["Budi": "#60A5FA"], "tagMap: tag terhapus dilewati, tag pertama menang")

    // Store: roundtrip JSON dan file korup
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wadesk-selftest-\(UUID().uuidString)")
    let s1 = TweakStore(accountID: "acc", base: tmp)
    s1.add(full!)
    s1.update { $0 = td }
    let s2 = TweakStore(accountID: "acc", base: tmp)
    check(s2.bookmarks == [full!] && s2.tags == td, "store roundtrip")
    s2.add(Bookmark(id: "true_628@c.us_ABC", chat: "Budi", jid: nil, text: "edit", time: "", fromMe: false, savedAt: now))
    check(s2.bookmarks.count == 1 && s2.bookmarks[0].text == "edit", "store add id sama mengganti")
    s2.remove(bookmarkID: "true_628@c.us_ABC")
    check(TweakStore(accountID: "acc", base: tmp).bookmarks.isEmpty, "store remove tersimpan")
    try? Data("{bukan json".utf8).write(to: tmp.appendingPathComponent("acc/tags.json"))
    let s3 = TweakStore(accountID: "acc", base: tmp)
    let baks = ((try? FileManager.default.contentsOfDirectory(atPath: tmp.appendingPathComponent("acc").path)) ?? [])
        .filter { $0.hasPrefix("tags.json.bak-") }
    check(s3.tags == TagData() && baks.count == 1, "store korup → .bak + kosong")
    try? FileManager.default.removeItem(at: tmp)
```

- [ ] **Step 2: Build, pastikan gagal**

Run: `./build.sh`
Expected: error `cannot find 'minutesOfDay' in scope`, `cannot find type 'Bookmark' in scope`, dll.

- [ ] **Step 3: Tulis `Tweaks.swift` (model, setting, store)**

```swift
import Foundation

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
```

- [ ] **Step 4: Tambah fungsi murni di `Helpers.swift`**

Di bawah `func shouldNotify(...)`, sebelum `let notificationShim`:

```swift
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
```

- [ ] **Step 5: Build, selftest lulus**

Run: `./build.sh`
Expected: satu baris stderr `tags.json korup, dipindah ke tags.json.bak-…` (dari kasus korup, memang diharapkan), lalu `selftest OK`, `built WA Desk.app`, tanpa warning swiftc.

- [ ] **Step 6: Commit**

```bash
git add Tweaks.swift Helpers.swift Selftest.swift
git commit -m "Add tweak settings, bookmark and tag models, and per-account store"
```

---

### Task 3: Lapisan inject + menu Tweaks dasar (blur, banner, CSS kustom, debug)

**Files:**
- Modify: `Tweaks.swift` (tambah `tweaksStyle`, `tweaksScript`, `jsStringLiteral`, `customCSS()`), `Selftest.swift` (cek sintaks JS), `AccountWindow.swift` (store, inject, `tweak`, `applyTweaks`, `didFinish`), `AppDelegate.swift` (menu Tweaks + 4 aksi)

**Interfaces:**
- Consumes: `TweakSettings`, `TweakStore`, `tagMap` (Task 2).
- Produces:
  - `let tweaksStyle: String`, `let tweaksScript: String`, `func customCSS() -> String?`
  - `AccountWindow.store: TweakStore`, `AccountWindow.tagFilter: String`, `func tweak(_ fn: String, _ args: KeyValuePairs<String, Any> = [:], completion: ((Any?) -> Void)? = nil)`, `func applyTweaks()`, `func pushTags()`
  - `AppDelegate: NSMenuDelegate` dengan `tweaksMenu` yang dibangun ulang di `menuNeedsUpdate(_:)`; helper lokal `item(_:_:_:_:on:)` di dalamnya; aksi `toggleBlur`, `toggleHideBanner`, `reloadCustomCSS`, `debugSelectors`; helper `func broadcast(_ fn: String, _ args: KeyValuePairs<String, Any>)` yang memanggil `tweak` di semua akun.
  - API JS `window.__wadesk`: `capture()`, `currentChat()`, `openChat(title, jid)`, `jumpTo(id, title)` (Promise<Bool>), `setTags(map)`, `setFilter(color)`, `setBlur(on)`, `setHideBanner(on)`, `setCustomCSS(css)`, `toast(msg)`, `debug()`.

- [ ] **Step 1: Tambah selftest sintaks JS (gagal)**

Di `Selftest.swift`, tambahkan `import JavaScriptCore` di atas, dan sebelum `if failed.isEmpty`:

```swift
    // Skrip inject harus valid dan mendefinisikan API, juga tanpa DOM (JSContext murni).
    let ctx = JSContext()!
    ctx.exceptionHandler = { _, e in failed.append("JS exception: \(e?.toString() ?? "?")") }
    ctx.evaluateScript(tweaksScript)
    check(ctx.evaluateScript("typeof __wadesk.capture")?.toString() == "function", "JS __wadesk.capture")
    check(ctx.evaluateScript("typeof __wadesk.openChat")?.toString() == "function", "JS __wadesk.openChat")
    check(ctx.evaluateScript("typeof __wadesk.setTags")?.toString() == "function", "JS __wadesk.setTags")
    check(ctx.evaluateScript("typeof __wadesk.debug")?.toString() == "function", "JS __wadesk.debug")
```

- [ ] **Step 2: Build, pastikan gagal**

Run: `./build.sh`
Expected: `cannot find 'tweaksScript' in scope`.

- [ ] **Step 3: Tambah style, skrip, dan helper di `Tweaks.swift`**

Di akhir `Tweaks.swift`:

```swift
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
#pane-side [role="listitem"][data-wadesk-tag]:not([data-wadesk-tag=""]) { position: relative; }
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
  const W = { hovered: null, tags: {}, filter: "", toastTimer: 0 };
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
      if (row.dataset.wadeskTag !== color) { row.dataset.wadeskTag = color; row.style.setProperty("--wadesk-tag", color); }
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
        if (!p || p === document.body || p.id === "app" || p.querySelector(BIG) || p.querySelectorAll(BANNER_BTN).length !== 1) break;
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
    setTimeout(() => { pending = false; markBanner(); applyTags(); }, 250);
  }).observe(document.documentElement, { childList: true, subtree: true });
  markBanner();
  applyTags();
})();
"""#
```

- [ ] **Step 4: Build, selftest JS lulus**

Run: `./build.sh`
Expected: `selftest OK` (empat kasus `JS __wadesk.*` lulus, tanpa `JS exception`).

- [ ] **Step 5: Hubungkan ke `AccountWindow`**

Di `AccountWindow.swift`:

a) Properti baru di dalam `final class AccountWindow`, setelah `private var titleObservation: NSKeyValueObservation?`:

```swift
    let store: TweakStore
    /// Warna tag yang sedang difilter di akun ini ("" = semua). Sesi saja.
    var tagFilter = ""
```

b) Di `init(id:)`, baris pertama setelah `self.id = id`:

```swift
        store = TweakStore(accountID: id)
```

c) Di `init(id:)`, tepat setelah blok `cfg.userContentController.addUserScript(WKUserScript(source: notificationShim, …))`:

```swift
        cfg.userContentController.addUserScript(WKUserScript(
            source: tweaksScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
```

d) Method baru di dalam class, sebelum `required init?(coder:)`:

```swift
    /// Panggil `__wadesk.<fn>(...)` dengan argumen terstruktur (callAsyncJavaScript), tanpa interpolasi string.
    /// `args` urut sesuai parameter fungsi JS. Hasil `undefined` → nil.
    func tweak(_ fn: String, _ args: KeyValuePairs<String, Any> = [:], completion: ((Any?) -> Void)? = nil) {
        let call = "return await __wadesk.\(fn)(\(args.map(\.key).joined(separator: ", ")))"
        let dict = Dictionary(uniqueKeysWithValues: args.map { ($0.key, $0.value) })
        webView.callAsyncJavaScript(call, arguments: dict, in: nil, in: .page) { result in
            switch result {
            case .success(let v): completion?(v is NSNull ? nil : v)
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

    func pushTags() { tweak("setTags", ["map": tagMap(store.tags)]) }
```

e) Di `extension AccountWindow: WKNavigationDelegate, …`, tambahkan:

```swift
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { applyTweaks() }
```

- [ ] **Step 6: Menu Tweaks di `AppDelegate`**

a) Ganti baris deklarasi class menjadi:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
```

b) Setelah `private(set) var accounts: [AccountWindow] = []` tambahkan:

```swift
    /// Dibangun ulang tiap dibuka (menuNeedsUpdate) supaya centang dan daftar tag selalu segar.
    private let tweaksMenu = NSMenu(title: "Tweaks")
```

c) Di `buildMenu()`, tepat sebelum baris komentar `// AppKit otomatis menambah Show Next/Previous Tab…`:

```swift
        tweaksMenu.delegate = self
        tweaksMenu.autoenablesItems = false
        let tweaksHolder = NSMenuItem()
        tweaksHolder.submenu = tweaksMenu
        main.addItem(tweaksHolder)
```

d) Method baru di dalam `AppDelegate`, di bawah `@objc func zoomReset()`:

```swift
    // MARK: Tweaks

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === tweaksMenu else { return }
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command, on: Bool = false) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.state = on ? .on : .off
            return i
        }
        menu.addItem(item("Blur Privasi", #selector(toggleBlur), "B", [.command, .shift], on: TweakSettings.blur))
        menu.addItem(item("Sembunyikan Banner Download", #selector(toggleHideBanner), on: TweakSettings.hideBanner))
        menu.addItem(.separator())
        menu.addItem(item("Muat Ulang CSS Kustom", #selector(reloadCustomCSS)))
        menu.addItem(item("Debug Selector", #selector(debugSelectors)))
    }

    /// Panggil fungsi __wadesk di semua akun.
    func broadcast(_ fn: String, _ args: KeyValuePairs<String, Any>) {
        accounts.forEach { $0.tweak(fn, args) }
    }

    @objc func toggleBlur() {
        TweakSettings.blur.toggle()
        broadcast("setBlur", ["on": TweakSettings.blur])
    }

    @objc func toggleHideBanner() {
        TweakSettings.hideBanner.toggle()
        broadcast("setHideBanner", ["on": TweakSettings.hideBanner])
    }

    @objc func reloadCustomCSS() {
        guard let css = customCSS() else {
            current?.tweak("toast", ["msg": "Tidak ada ~/.config/wa-desk/custom.css"])
            return
        }
        broadcast("setCustomCSS", ["css": css])
    }

    @objc func debugSelectors() {
        guard let acc = current else { return }
        acc.tweak("debug") { v in
            let d = v as? [String: Any] ?? [:]
            FileHandle.standardError.write(Data("wadesk debug: \(d)\n".utf8))
            let ok: (String) -> String = { (d[$0] as? Bool ?? false) ? "✓" : "✗" }
            acc.tweak("toast", ["msg": "pane:\(ok("paneSide")) main:\(ok("main")) rows:\(d["rows"] ?? 0) msgs:\(d["messages"] ?? 0) banner:\(d["bannerButtons"] ?? 0)"])
        }
    }
```

- [ ] **Step 7: Build dan cek launch**

Run: `./build.sh`
Expected: `selftest OK`, tanpa warning. Lalu:

```sh
open "WA Desk.app"; sleep 10; pgrep -x wa-desk
osascript -e 'tell application "System Events" to tell process "wa-desk" to get name of every menu item of menu "Tweaks" of menu bar 1'
osascript -e 'quit app "wa-desk"'
```
Expected: pid tercetak; daftar item `Blur Privasi, Sembunyikan Banner Download, missing value, Muat Ulang CSS Kustom, Debug Selector`. (Kalau System Events ditolak izin, catat dan lewati.) Perilaku di halaman (banner hilang di halaman QR, blur) diuji manual oleh user.

- [ ] **Step 8: Commit**

```bash
git add Tweaks.swift Selftest.swift AccountWindow.swift AppDelegate.swift
git commit -m "Inject tweaks layer with blur, banner hiding, custom CSS, and debug"
```

---

### Task 4: Jadwal senyap, hotkey global, selalu di atas

**Files:**
- Modify: `Tweaks.swift` (tambah `GlobalHotkey`), `AccountWindow.swift` (guard DND di handler notify), `AppDelegate.swift` (item menu + aksi + `validateMenuItem`)

**Interfaces:**
- Consumes: `dndActive`, `minutesOfDay(_: Date)`, `TweakSettings.dnd*` (Task 2); `menuNeedsUpdate` dan helper `item` (Task 3).
- Produces: `enum GlobalHotkey { static func register(_ action: @escaping () -> Void) }`; `AppDelegate.toggleDND()`, `toggleAlwaysOnTop()`, `toggleVisibility()`.

- [ ] **Step 1: Guard DND di jalur notifikasi**

Di `AccountWindow.swift`, dalam `userContentController(_:didReceive:)`, tepat setelah baris `guard shouldNotify(appActive: NSApp.isActive, windowKey: window?.isKeyWindow ?? false) else { return }`:

```swift
        // Jadwal senyap hanya menahan banner; badge Dock tetap diperbarui lewat judul halaman.
        guard !dndActive(minutesNow: minutesOfDay(Date()), start: TweakSettings.dndStart,
                         end: TweakSettings.dndEnd, enabled: TweakSettings.dndEnabled) else { return }
```

- [ ] **Step 2: `GlobalHotkey` di `Tweaks.swift`**

Tambahkan `import Carbon.HIToolbox` di bawah `import Foundation`, lalu di akhir file:

```swift
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
```

- [ ] **Step 3: AppDelegate: hotkey, DND, selalu di atas**

a0) Ganti baris deklarasi class menjadi (tambah `NSMenuItemValidation` supaya `validateMenuItem` dipanggil untuk item menu Window):

```swift
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, NSMenuItemValidation {
```

a) Di `applicationDidFinishLaunching`, setelah `buildMenu()`:

```swift
        GlobalHotkey.register { [weak self] in self?.toggleVisibility() }
```

b) Di `menuNeedsUpdate`, tepat sebelum `menu.addItem(item("Muat Ulang CSS Kustom", …))`:

```swift
        menu.addItem(item("Jadwal Senyap \(TweakSettings.dndStart)–\(TweakSettings.dndEnd)",
                          #selector(toggleDND), on: TweakSettings.dndEnabled))
```

c) Di `buildMenu()`, dalam `NSApp.windowsMenu = menu("Window", [ … ])`, setelah item `Minimize`:

```swift
            item("Selalu di Atas", #selector(toggleAlwaysOnTop), "t", [.command, .option]),
```

d) Method baru di `AppDelegate`, di bawah `debugSelectors()`:

```swift
    @objc func toggleDND() { TweakSettings.dndEnabled.toggle() }

    @objc func toggleAlwaysOnTop() {
        guard let w = NSApp.keyWindow else { return }
        w.level = w.level == .floating ? .normal : .floating
    }

    /// Centang "Selalu di Atas" mengikuti window key. Item lain selalu aktif.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAlwaysOnTop) {
            item.state = NSApp.keyWindow?.level == .floating ? .on : .off
            return NSApp.keyWindow != nil
        }
        return true
    }

    /// ⌥⌘W: app aktif → sembunyikan; selain itu → aktifkan dan tampilkan akun yang tersembunyi.
    func toggleVisibility() {
        if NSApp.isActive {
            NSApp.hide(nil)
        } else {
            NSApp.activate()
            accounts.filter { $0.window?.isVisible == false }.forEach(present)
        }
    }
```

- [ ] **Step 4: Build dan cek**

Run: `./build.sh`
Expected: `selftest OK`, tanpa warning. Lalu `open "WA Desk.app"; sleep 8; pgrep -x wa-desk; osascript -e 'quit app "wa-desk"'` → pid, keluar bersih, dan **tidak ada** baris `hotkey ⌥⌘W gagal didaftar` di stderr (jalankan sekali langsung: `"WA Desk.app/Contents/MacOS/wa-desk" & sleep 5; kill %1` dan lihat output).

- [ ] **Step 5: Commit**

```bash
git add Tweaks.swift AccountWindow.swift AppDelegate.swift
git commit -m "Add quiet hours, global show/hide hotkey, and always-on-top"
```

---

### Task 5: Bookmark pesan + panel

**Files:**
- Create: `BookmarksPanel.swift`
- Modify: `AccountWindow.swift` (`showBookmarksPanel`, `open(bookmark:)`), `AppDelegate.swift` (2 item menu + 2 aksi)

**Interfaces:**
- Consumes: `TweakStore.add/remove/bookmarks/onChange`, `bookmark(fromCapture:)` (Task 2); `tweak`, `__wadesk.capture/openChat/jumpTo/toast` (Task 3).
- Produces: `final class BookmarksPanel: NSPanel { init(store:); var onOpen: ((Bookmark) -> Void)? }`; `AccountWindow.showBookmarksPanel()`, `AccountWindow.open(bookmark:)`; `AppDelegate.bookmarkMessage()`, `showBookmarks()`.

- [ ] **Step 1: Tulis `BookmarksPanel.swift`**

```swift
import Cocoa

/// Tabel yang meneruskan Return/Enter dan ⌫/Delete ke closure; sisanya perilaku NSTableView biasa.
private final class KeyTable: NSTableView {
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()      // Return, Enter
        case 51, 117: onDelete?()     // ⌫, Delete
        default: super.keyDown(with: event)
        }
    }
}

/// Panel daftar bookmark satu akun. Return/dobel-klik → buka chat & lompat ke pesan; ⌫ → hapus.
final class BookmarksPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let store: TweakStore
    private let table = KeyTable()
    var onOpen: ((Bookmark) -> Void)?

    init(store: TweakStore) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow],
                   backing: .buffered, defer: false)
        title = "Bookmark"
        isReleasedWhenClosed = false
        for (id, name, width) in [("chat", "Chat", 140.0), ("text", "Pesan", 240.0), ("time", "Waktu", 120.0)] {
            let col = NSTableColumn(identifier: .init(id))
            col.title = name
            col.width = width
            table.addTableColumn(col)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.onReturn = { [weak self] in self?.openSelected() }
        table.onDelete = { [weak self] in self?.deleteSelected() }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        contentView = scroll
        center()
        store.onChange = { [weak self] in self?.table.reloadData() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.bookmarks.count }

    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        let b = store.bookmarks[row]
        switch column?.identifier.rawValue {
        case "chat": return b.chat
        case "time": return b.time
        default: return (b.fromMe ? "Saya: " : "") + b.text
        }
    }

    @objc private func openSelected() {
        guard store.bookmarks.indices.contains(table.selectedRow) else { return }
        onOpen?(store.bookmarks[table.selectedRow])
    }

    private func deleteSelected() {
        guard store.bookmarks.indices.contains(table.selectedRow) else { return }
        store.remove(bookmarkID: store.bookmarks[table.selectedRow].id)
    }
}
```

- [ ] **Step 2: `AccountWindow`: tampilkan panel dan buka bookmark**

Di dalam `final class AccountWindow`, setelah `var tagFilter = ""`:

```swift
    private var bookmarksPanel: BookmarksPanel?
```

Setelah `func pushTags()`:

```swift
    func showBookmarksPanel() {
        if bookmarksPanel == nil {
            let p = BookmarksPanel(store: store)
            p.onOpen = { [weak self] b in self?.open(bookmark: b) }
            bookmarksPanel = p
        }
        bookmarksPanel?.makeKeyAndOrderFront(nil)
    }

    /// Buka chat bookmark lalu lompat ke pesannya; setiap kegagalan dilaporkan lewat toast.
    func open(bookmark b: Bookmark) {
        window?.makeKeyAndOrderFront(nil)
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
```

- [ ] **Step 3: Menu + aksi di `AppDelegate`**

Di `menuNeedsUpdate`, tepat setelah baris `menu.addItem(.separator())` yang pertama (di bawah "Sembunyikan Banner Download"):

```swift
        menu.addItem(item("Bookmark Pesan", #selector(bookmarkMessage), "d"))
        menu.addItem(item("Tampilkan Bookmark…", #selector(showBookmarks), "D", [.command, .shift]))
        menu.addItem(.separator())
```

Method baru di bawah `toggleVisibility()`:

```swift
    @objc func bookmarkMessage() {
        guard let acc = current else { return }
        acc.tweak("capture") { v in
            guard let d = v as? [String: Any], let b = bookmark(fromCapture: d, savedAt: Date()) else {
                acc.tweak("toast", ["msg": "Arahkan kursor ke pesan dulu"])
                return
            }
            acc.store.add(b)
            acc.tweak("toast", ["msg": "Disimpan"])
        }
    }

    @objc func showBookmarks() { current?.showBookmarksPanel() }
```

- [ ] **Step 4: Build dan cek panel kosong**

Run: `./build.sh`
Expected: `selftest OK`, tanpa warning. Lalu `open "WA Desk.app"; sleep 8`, buka panel lewat AppleScript:

```sh
osascript -e 'tell application "System Events" to tell process "wa-desk" to click menu item "Tampilkan Bookmark…" of menu "Tweaks" of menu bar 1' ; sleep 1
osascript -e 'tell application "System Events" to get name of every window of process "wa-desk"'
osascript -e 'quit app "wa-desk"'
```
Expected: daftar window memuat `Bookmark`. (Izin System Events ditolak → catat, lewati.)

- [ ] **Step 5: Commit**

```bash
git add BookmarksPanel.swift AccountWindow.swift AppDelegate.swift
git commit -m "Add local message bookmarks with a native panel"
```

---

### Task 6: Tag chat: submenu tag, filter, titik warna

**Files:**
- Modify: `Tweaks.swift` (JS: lapor chat terbuka; `nsColor(hex:)`, `swatch(_:)`), `AccountWindow.swift` (handler `wadesk`, `openChatTitle`), `AppDelegate.swift` (submenu + aksi; lepas handler saat hapus akun)

**Interfaces:**
- Consumes: `TweakStore.update/tags`, `tagNameValid`, `tagPalette`, `tagMap` (Task 2); `pushTags`, `tweak`, `menuNeedsUpdate`, helper `item` (Task 3).
- Produces: `AccountWindow.openChatTitle: String?` (diperbarui dari JS); `AppDelegate.toggleTag(_:)`, `newTag()`, `deleteTag(_:)`, `setTagFilter(_:)`; `func nsColor(hex:) -> NSColor`, `func swatch(_ hex: String) -> NSImage`.

- [ ] **Step 1: JS melaporkan chat yang terbuka**

Di `tweaksScript` (Tweaks.swift), di dalam callback `MutationObserver`, ganti baris
`setTimeout(() => { pending = false; markBanner(); applyTags(); }, 250);` menjadi:

```js
    setTimeout(() => {
      pending = false; markBanner(); applyTags();
      const cc = currentChat(); const t = cc ? cc.title : "";
      if (t !== W.lastChat) {
        W.lastChat = t;
        try { window.webkit.messageHandlers.wadesk.postMessage({ chat: t }); } catch (e) {}
      }
    }, 250);
```

dan tambahkan `lastChat: ""` ke objek `W` (`const W = { hovered: null, tags: {}, filter: "", toastTimer: 0, lastChat: "" };`).

- [ ] **Step 2: Helper warna di `Tweaks.swift`**

Tambahkan `import AppKit` di atas file, dan di akhir file:

```swift
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
```

- [ ] **Step 3: `AccountWindow`: terima laporan chat terbuka**

a) Properti, setelah `private var bookmarksPanel: BookmarksPanel?`:

```swift
    /// Judul chat yang sedang terbuka, dilaporkan JS lewat handler "wadesk". nil = tidak ada chat.
    private(set) var openChatTitle: String?
```

b) Di `init(id:)`, tepat setelah `webView.configuration.userContentController.add(self, name: "notify")`:

```swift
        webView.configuration.userContentController.add(self, name: "wadesk")
```

c) Di `userContentController(_:didReceive:)`, ganti `guard` pertama (yang mengecek `isMainFrame`, origin, `body`, `nid`) menjadi dua tahap:

```swift
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == "web.whatsapp.com",
              let body = message.body as? [String: Any] else { return }
        if message.name == "wadesk" {
            let title = body["chat"] as? String ?? ""
            openChatTitle = title.isEmpty ? nil : title
            return
        }
        guard let nid = body["id"] as? String, Int(nid) != nil else { return }
```

- [ ] **Step 4: `AppDelegate`: submenu Tag dan Filter + aksi**

a) Di `menuNeedsUpdate`, tepat sebelum baris `menu.addItem(item("Jadwal Senyap …"))`:

```swift
        let acc = current
        let tags = acc?.store.tags.tags ?? []
        let openChat = acc?.openChatTitle

        let tagMenu = NSMenu(title: "Tag Chat Ini")
        tagMenu.autoenablesItems = false
        for tag in tags {
            let i = item(tag.name, #selector(toggleTag(_:)),
                         on: openChat.flatMap { acc?.store.tags.chats[$0]?.contains(tag.name) } ?? false)
            i.image = swatch(tag.color)
            i.representedObject = tag.name
            i.isEnabled = openChat != nil
            tagMenu.addItem(i)
        }
        if !tags.isEmpty { tagMenu.addItem(.separator()) }
        tagMenu.addItem(item("Tag Baru…", #selector(newTag)))
        let deleteMenu = NSMenu(title: "Hapus Tag")
        deleteMenu.autoenablesItems = false
        for tag in tags {
            let i = item(tag.name, #selector(deleteTag(_:)))
            i.image = swatch(tag.color)
            i.representedObject = tag.name
            deleteMenu.addItem(i)
        }
        let deleteHolder = NSMenuItem(title: "Hapus Tag", action: nil, keyEquivalent: "")
        deleteHolder.submenu = deleteMenu
        deleteHolder.isEnabled = !tags.isEmpty
        tagMenu.addItem(deleteHolder)
        let tagHolder = NSMenuItem(title: "Tag Chat Ini", action: nil, keyEquivalent: "")
        tagHolder.submenu = tagMenu
        menu.addItem(tagHolder)

        let filterMenu = NSMenu(title: "Filter Tag")
        filterMenu.autoenablesItems = false
        let all = item("Semua", #selector(setTagFilter(_:)), on: (acc?.tagFilter ?? "").isEmpty)
        all.representedObject = ""
        filterMenu.addItem(all)
        for tag in tags {
            let i = item(tag.name, #selector(setTagFilter(_:)), on: acc?.tagFilter == tag.color)
            i.image = swatch(tag.color)
            i.representedObject = tag.color
            filterMenu.addItem(i)
        }
        let filterHolder = NSMenuItem(title: "Filter Tag", action: nil, keyEquivalent: "")
        filterHolder.submenu = filterMenu
        menu.addItem(filterHolder)
        menu.addItem(.separator())
```

b) Method baru di bawah `showBookmarks()`:

```swift
    // MARK: Tag

    @objc func toggleTag(_ sender: NSMenuItem) {
        guard let acc = current, let chat = acc.openChatTitle, let name = sender.representedObject as? String else { return }
        acc.store.update { data in
            var names = data.chats[chat] ?? []
            if let i = names.firstIndex(of: name) { names.remove(at: i) } else { names.append(name) }
            data.chats[chat] = names.isEmpty ? nil : names
        }
        acc.pushTags()
    }

    @objc func newTag() {
        guard let acc = current else { return }
        let alert = NSAlert()
        alert.messageText = "Tag baru"
        alert.informativeText = acc.openChatTitle == nil
            ? "Nama tag dan warnanya."
            : "Nama tag dan warnanya. Tag langsung dipasang ke chat yang terbuka."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "mis. Kerja"
        let colors = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        for hex in tagPalette {
            colors.addItem(withTitle: hex)
            colors.lastItem?.image = swatch(hex)
        }
        let stack = NSStackView(views: [field, colors])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 220, height: 58)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Buat")
        alert.addButton(withTitle: "Batal")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard tagNameValid(name), !acc.store.tags.tags.contains(where: { $0.name == name }) else {
            NSSound.beep()
            acc.tweak("toast", ["msg": "Nama tag kosong, >24 karakter, atau sudah ada"])
            return
        }
        let color = tagPalette[max(0, colors.indexOfSelectedItem)]
        acc.store.update { data in
            data.tags.append(Tag(name: name, color: color))
            if let chat = acc.openChatTitle { data.chats[chat, default: []].append(name) }
        }
        acc.pushTags()
    }

    @objc func deleteTag(_ sender: NSMenuItem) {
        guard let acc = current, let name = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = "Hapus tag “\(name)”?"
        alert.informativeText = "Tag dilepas dari semua chat."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hapus")
        alert.addButton(withTitle: "Batal")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let removedColor = acc.store.tags.tags.first { $0.name == name }?.color
        acc.store.update { data in
            data.tags.removeAll { $0.name == name }
            for (chat, names) in data.chats {
                let kept = names.filter { $0 != name }
                data.chats[chat] = kept.isEmpty ? nil : kept
            }
        }
        if acc.tagFilter == removedColor, !acc.store.tags.tags.contains(where: { $0.color == removedColor }) {
            acc.tagFilter = ""
            acc.tweak("setFilter", ["color": ""])
        }
        acc.pushTags()
    }

    @objc func setTagFilter(_ sender: NSMenuItem) {
        guard let acc = current else { return }
        acc.tagFilter = sender.representedObject as? String ?? ""
        acc.tweak("setFilter", ["color": acc.tagFilter])
    }
```

c) Di `removeAccount()`, tepat setelah baris `account.webView.configuration.userContentController.removeScriptMessageHandler(forName: "notify")`:

```swift
        account.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wadesk")
```

- [ ] **Step 5: Build dan cek**

Run: `./build.sh`
Expected: `selftest OK` (termasuk selftest JS yang kini memuat kode `lastChat`), tanpa warning. Lalu `open "WA Desk.app"; sleep 8; pgrep -x wa-desk; osascript -e 'quit app "wa-desk"'`.

- [ ] **Step 6: Commit**

```bash
git add Tweaks.swift AccountWindow.swift AppDelegate.swift
git commit -m "Add local chat tags with colored dots and filter"
```

---

### Task 7: README, versi 0.3.0

**Files:**
- Modify: `README.md`, `Info.plist`

**Interfaces:**
- Consumes: semua fitur Task 3–6.
- Produces: dokumentasi + versi untuk rilis.

- [ ] **Step 1: `Info.plist`**

Ganti `CFBundleShortVersionString` `0.2.1` → `0.3.0` dan `CFBundleVersion` `3` → `4`.

- [ ] **Step 2: README — bagian Tweaks**

Sisipkan setelah bagian `## Pakai` (sebelum `## Launch pertama`):

```markdown
## Tweaks

Menu **Tweaks** menambah fitur yang tidak ada di WhatsApp Web; semuanya lokal di Mac ini.

- **Blur Privasi** (⇧⌘B): daftar chat dan pesan dikaburkan, jelas saat kursor di atasnya.
- **Sembunyikan Banner Download**: banner "Download WhatsApp for Mac" disembunyikan (default aktif).
- **Bookmark Pesan** (⌘D): arahkan kursor ke pesan, tekan ⌘D. **Tampilkan Bookmark…** (⇧⌘D) membuka
  panel; Return/dobel-klik membuka chat dan melompat ke pesan (kalau pesannya sudah dimuat), ⌫ menghapus.
  Pengganti pin: batas pin ditegakkan server WhatsApp dan tidak bisa dinaikkan.
- **Tag Chat Ini**: beri tag (nama + warna) ke chat yang terbuka; titik warna muncul di daftar chat.
  **Filter Tag** meredupkan chat lain. Tag dicocokkan dengan judul chat: mengganti nama kontak melepas tag.
- **Jadwal Senyap**: notifikasi ditahan pada jam yang ditentukan; badge tetap. Jam diubah lewat
  `defaults write dev.zen.wa dndStart 23:30` dan `defaults write dev.zen.wa dndEnd 06:00` (format HH:mm,
  boleh lewat tengah malam), lalu nyalakan di menu.
- **Muat Ulang CSS Kustom**: `~/.config/wa-desk/custom.css` disuntik ke halaman; ubah apa pun lewat CSS.
- **Debug Selector**: cetak jumlah elemen WhatsApp yang dikenali ke stderr dan toast. Kalau ada ✗,
  struktur WhatsApp Web berubah dan selector di `Tweaks.swift` perlu diperbarui.
- Window → **Selalu di Atas** (⌥⌘T). Hotkey global **⌥⌘W** menampilkan/menyembunyikan app dari mana saja.

Data bookmark dan tag ada di `~/Library/Application Support/wa-desk/<id akun>/` (JSON).
Semua Tweaks hanya CSS, pembacaan DOM, dan klik sintetis setara klik user; tidak ada otomasi kirim pesan.
```

- [ ] **Step 3: README — checklist**

Di bawah baris terakhir checklist smoke test yang ada, tambahkan:

```markdown
- [ ] Tweaks: blur ⇧⌘B on/off, jelas saat hover
- [ ] Tweaks: banner download hilang (halaman QR dan setelah login)
- [ ] Tweaks: ⌘D pada pesan → toast "Disimpan" → muncul di panel; Return → chat terbuka, pesan berkilat
- [ ] Tweaks: bookmark chat yang di luar layar → toast yang sesuai
- [ ] Tweaks: tag baru → titik warna; Filter Tag → chat lain redup; hapus tag
- [ ] Tweaks: ⌥⌘W dari app lain; Selalu di Atas
- [ ] Tweaks: Jadwal Senyap aktif → pesan masuk tanpa banner, badge naik
- [ ] Tweaks: `custom.css` berisi `#pane-side{background:#111}` → Muat Ulang → terlihat
- [ ] Tweaks: Debug Selector semua ✓
```

- [ ] **Step 4: Build, commit**

Run: `./build.sh` → `selftest OK`.

```bash
git add README.md Info.plist
git commit -m "Document tweaks and bump version to 0.3.0"
```
