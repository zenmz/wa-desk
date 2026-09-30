# WA — client WhatsApp Desktop ringan untuk macOS (WKWebView)

Tanggal: 2026-09-30
Status: disetujui untuk planning

## 1. Tujuan

Pengganti WhatsApp Desktop resmi (Electron) di Mac yang hemat RAM dan storage,
dengan fitur lengkap yang dipakai harian: chat teks + media, panggilan
suara/video, status/channel/community, dan multi-akun.

Pendekatan: wrapper native tipis di atas `https://web.whatsapp.com` memakai
`WKWebView` (WebKit sistem). Bukan client protokol (whatsmeow/Baileys) karena
jalur itu tidak mendukung call dan status, dan berisiko ban akun.

Target ukuran: binary < 1 MB. RAM per akun ~150–300 MB (isi halaman WhatsApp
Web, bukan overhead app). Storage per akun = cache WebKit, umumnya < 100 MB.

## 2. Batasan & keputusan

- Mac saja. Minimum macOS 14 (butuh `WKWebsiteDataStore(forIdentifier:)`).
- Swift, tanpa Xcode.app: build pakai `swiftc` dari Command Line Tools.
- Nol dependency eksternal. Framework sistem saja: Cocoa, WebKit,
  UserNotifications.
- Satu file sumber `main.swift`. Dipecah hanya kalau melewati ~400 baris.
- Bundle id `dev.zen.wa`, nama app `WA`.

## 3. Struktur repo

```
wa/
├── main.swift      # seluruh kode app
├── Info.plist      # bundle id, izin kamera/mic, min OS
├── build.sh        # swiftc → WA.app, codesign ad-hoc, jalankan selftest
├── README.md       # cara build + checklist smoke test
└── docs/superpowers/specs/…
```

`.gitignore`: `WA.app/`.

## 4. Komponen (semua di `main.swift`)

### 4.1 `Accounts`
- Daftar id akun (UUID string) disimpan di `UserDefaults` key `accounts`.
- Launch pertama atau daftar kosong → buat satu UUID baru dan simpan.
- Operasi: `all()`, `add() -> String`, `remove(id)`.

### 4.2 `AccountWindow`
Satu instance per akun. `NSWindowController` yang juga jadi
`WKNavigationDelegate`, `WKUIDelegate`, `WKDownloadDelegate`,
`WKScriptMessageHandler`.

Window:
- Ukuran awal 1100×750, `styleMask` standar (titled, closable,
  miniaturizable, resizable).
- `tabbingMode = .preferred`, `tabbingIdentifier = "wa"` → beberapa akun
  otomatis digabung jadi tab native macOS. Pindah akun pakai Cmd+Shift+[ / ].
- `setFrameAutosaveName("win-<id>")` → posisi/ukuran diingat per akun.
- `title` = judul halaman (WhatsApp set sendiri, mis. `"(3) WhatsApp"`).
- `windowShouldClose` → `orderOut`, return false. Window disembunyikan, bukan
  ditutup, supaya pesan tetap masuk. Keluar app hanya lewat Cmd+Q.

WKWebView config:
- `websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(id))` → cookie,
  IndexedDB, dan session terisolasi per akun, persisten di container app.
- `applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"` → UA jadi
  setara Safari, lolos cek browser WhatsApp Web.
- `preferences.isElementFullscreenEnabled = true` → video fullscreen.
- `userContentController`: tambah `NotificationShim` (4.3) sebagai
  `WKUserScript` `atDocumentStart`, `forMainFrameOnly: true`; daftarkan
  message handler nama `notify`.
- `webView.allowsMagnification = true` → pinch zoom.
- Load `https://web.whatsapp.com/`.

Navigasi & link luar:
- `decidePolicyFor navigationAction`: kalau `shouldPerformDownload` →
  `.download`. Kalau host bukan `web.whatsapp.com` dan navigasi dari
  klik user (`navigationType == .linkActivated`) → `NSWorkspace.shared.open`,
  `.cancel`. Selain itu `.allow`.
- `decidePolicyFor navigationResponse`: kalau `!canShowMIMEType` →
  `.download`, selain itu `.allow`.
- `createWebViewWith` (target=_blank / window.open) → buka URL di browser
  default, return nil.

Download (`WKDownloadDelegate`):
- `navigationAction/navigationResponse didBecome download` → set delegate.
- `decideDestinationUsing` → `~/Downloads/<suggestedFilename>`. Kalau file
  sudah ada, tambah suffix ` (1)`, ` (2)`, … sebelum ekstensi.
- `downloadDidFinish` → `NSWorkspace.shared.activateFileViewerSelecting`
  tidak dipakai (mengganggu). Cukup diam. Gagal → tulis ke stderr.

Media & upload (`WKUIDelegate`):
- `requestMediaCapturePermissionFor origin … decisionHandler(.grant)`
  untuk origin `web.whatsapp.com`, selain itu `.deny`. TCC macOS tetap
  prompt kamera/mic sekali; string alasan ada di Info.plist.
- `runOpenPanelWith parameters` → `NSOpenPanel`, hormati
  `allowsMultipleSelection` dan `allowsDirectories` dari parameter.

Badge unread:
- KVO `webView.title`. Fungsi murni `unreadCount(_ title: String) -> Int`
  ambil angka di dalam kurung di awal judul, 0 kalau tidak ada.
- Setiap perubahan → `AppDelegate.refreshBadge()` jumlahkan semua akun →
  `NSApp.dockTile.badgeLabel` (`nil` kalau 0).

### 4.3 `NotificationShim` (JavaScript, di-inject)
WKWebView tidak menyediakan `window.Notification`. Shim mendefinisikan:

```js
class Notification {
  static permission = "granted";
  static requestPermission(cb) { cb && cb("granted"); return Promise.resolve("granted"); }
  constructor(title, opts = {}) {
    this.title = title; this.onclick = null;
    this._id = String(Math.random());
    window.__waNotif = window.__waNotif || {};
    window.__waNotif[this._id] = this;
    webkit.messageHandlers.notify.postMessage({ id: this._id, title, body: opts.body || "", tag: opts.tag || "" });
  }
  close() { delete window.__waNotif[this._id]; }
  addEventListener(t, fn) { if (t === "click") this.onclick = fn; }
}
window.Notification = Notification;
```

Sisi native (`userContentController(_:didReceive:)`):
- Abaikan kalau app aktif DAN window akun ini `isKeyWindow` (user sedang
  lihat chat, hindari notifikasi dobel).
- Buat `UNMutableNotificationContent` (title, body), `userInfo =
  ["account": id, "nid": id notifikasi JS]`, identifier = tag kalau ada
  (supaya notifikasi chat yang sama menimpa, bukan menumpuk).
- Klik notifikasi (`UNUserNotificationCenterDelegate didReceive response`)
  → `NSApp.activate`, tampilkan window akun, lalu
  `evaluateJavaScript("__waNotif['<nid>']?.onclick?.()")` supaya
  WhatsApp buka chat terkait.
- Minta izin notifikasi (`.alert, .sound, .badge`) sekali saat launch.
  Ditolak → app tetap jalan, badge Dock tetap update.

### 4.4 `AppDelegate`
- `applicationDidFinishLaunching`: bangun menu, minta izin notifikasi, buat
  `AccountWindow` untuk setiap id di `Accounts.all()`, tampilkan semua.
- Menu (programatik, tanpa nib):
  - **WA**: About, Hide, Quit (Cmd+Q).
  - **File**: Akun Baru (Cmd+N), Hapus Akun Ini… .
  - **Edit**: Undo, Redo, Cut, Copy, Paste, Select All (selector standar
    responder chain, wajib supaya Cmd+C/V jalan di WKWebView).
  - **View**: Reload (Cmd+R), Zoom In/Out/Reset (Cmd+=/-/0, ubah
    `webView.pageZoom`).
  - **Window**: Minimize, Show All, Show Next/Previous Tab (bawaan
    window tabbing).
- Akun Baru → `Accounts.add()`, buat window baru, tampilkan sebagai tab.
- Hapus Akun Ini → `NSAlert` konfirmasi (destruktif, sebut data login akan
  dihapus) → `WKWebsiteDataStore.remove(forIdentifier:)` →
  `Accounts.remove` → tutup window. Kalau itu akun terakhir, langsung buat
  akun baru kosong.
- `applicationShouldHandleReopen` (klik ikon Dock) → tampilkan semua window
  akun yang disembunyikan.
- `applicationShouldTerminateAfterLastWindowClosed` → false.

### 4.5 Selftest
`WA --selftest` dijalankan `build.sh` setelah link. Tanpa NSApplication.
Assert lalu exit 0, atau cetak kasus gagal dan exit 1:

```
unreadCount("(3) WhatsApp")  == 3
unreadCount("(12) WhatsApp") == 12
unreadCount("WhatsApp")      == 0
unreadCount("")              == 0
isExternal("https://web.whatsapp.com/x") == false
isExternal("https://example.com")        == true
isExternal("https://wa.me/628")          == true
```

## 5. `Info.plist`

- `CFBundleIdentifier` `dev.zen.wa`, `CFBundleName` `WA`,
  `CFBundleExecutable` `WA`, `CFBundlePackageType` `APPL`,
  `CFBundleShortVersionString` `0.1.0`.
- `LSMinimumSystemVersion` `14.0`, `NSHighResolutionCapable` true,
  `NSPrincipalClass` `NSApplication`.
- `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`: teks untuk
  video/voice call WhatsApp.
- Tidak ada `LSUIElement` (app punya ikon Dock, badge butuh itu).

## 6. `build.sh`

```
set -euo pipefail
APP=WA.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O main.swift -o "$APP/Contents/MacOS/WA" \
  -framework Cocoa -framework WebKit -framework UserNotifications
cp Info.plist "$APP/Contents/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/WA" --selftest
```

Codesign ad-hoc wajib: TCC (kamera/mic) dan UNUserNotificationCenter butuh
identitas bundle yang stabil. Tanpa `--deep`; hanya satu binary.

## 7. Error handling

| Situasi | Perilaku |
|---|---|
| WhatsApp tampil "browser tidak didukung" | Ganti ke `customUserAgent` string Safari penuh (fallback, ditentukan saat smoke test Task 1). |
| Id akun di UserDefaults tidak valid (bukan UUID) | Lewati akun itu, jangan crash. Daftar jadi kosong → buat satu baru. |
| Izin notifikasi ditolak | Abaikan; badge Dock tetap jalan. |
| Download gagal | Log ke stderr. Tidak ada UI. |
| Pesan telat masuk saat window disembunyikan | Risiko throttling WebKit untuk view tak terlihat. Websocket tidak di-throttle, jadi diperkirakan aman. Kalau terbukti telat: ganti `orderOut` ke `miniaturize`. |

## 8. Risiko & urutan pembuktian

1. web.whatsapp.com load dan QR login di WKWebView macOS 26 dengan UA di
   atas. Gagal = proyek gagal. Dibuktikan pertama, sebelum fitur lain.
2. Call suara/video jalan (WebRTC + `requestMediaCapturePermission`).
3. Notifikasi native muncul via shim saat window tidak fokus.
4. Pesan tetap masuk saat window disembunyikan.
5. Multi-akun: 2 tab, login berbeda, keduanya terima pesan.

## 9. Testing

- Otomatis: `WA --selftest` (4.5), jalan tiap `./build.sh`.
- Manual (checklist di README): login QR, kirim teks / foto / voice note /
  dokumen, download media, buka link luar, notifikasi saat hidden + klik
  notifikasi buka chat yang benar, badge Dock, call suara & video, tambah
  akun ke-2 dan login, hapus akun, Cmd+C/V, zoom, reload, Cmd+Q lalu buka
  lagi masih login. Bandingkan RAM di Activity Monitor dengan WA resmi.

## 10. Di luar scope (YAGNI)

App icon, auto-update, menubar/tray icon, launch at login, screen-share
saat call (`getDisplayMedia` tidak tersedia di WKWebView publik), spell
check kustom, shortcut pindah akun kustom (tab native sudah punya), sandbox
App Store, distribusi/notarisasi.
