# WA Desk — Tweaks (blur, bookmark, tag, utilitas)

Tanggal: 2026-10-01
Status: disetujui untuk planning
Dasar: `docs/superpowers/specs/2026-09-30-wa-wkwebview-client-design.md` (app inti, sekarang bernama WA Desk, repo `zenmz/wa-desk`)

## 1. Tujuan

Fitur yang tidak ada di WhatsApp Web, berjalan lokal di Mac:

1. Blur privasi: tiap baris chat, tiap pesan, dan header chat dikaburkan sendiri-sendiri; yang di bawah kursor jelas.
2. Sembunyikan banner "Download WhatsApp for Mac".
3. Bookmark pesan tanpa batas (pengganti pin, yang batasnya ditegakkan server WhatsApp).
4. Tag/label chat lokal dengan titik warna dan filter.
5. Utilitas: hotkey global tampil/sembunyi, selalu di atas, jadwal senyap (DND), CSS kustom.

Yang **tidak** bisa dan tidak dicoba: menaikkan batas pin/pinned chat, mengubah apa pun yang
ditegakkan server WhatsApp, otomasi kirim pesan (risiko ban).

## 2. Pendekatan

Satu lapisan inject berbasis atribut + UI native:

- Satu `WKUserScript` (`tweaksScript`, `atDocumentEnd`, main frame) mengekspos `window.__wadesk`.
- Satu `<style id="wadesk">` (`tweaksStyle`) yang aturannya di-key atribut `html[data-wadesk-*]`.
- Native (AppKit) hanya: set atribut, panggil fungsi `__wadesk.*`, simpan data, tampilkan menu/panel.
- Semua yang bergantung DOM WhatsApp hidup di `tweaksScript` + `tweaksStyle` saja.

Jangkar DOM WhatsApp Web yang dipakai (stabil bertahun-tahun, tetap bisa berubah):

| Jangkar | Arti |
|---|---|
| `#pane-side` | kontainer daftar chat (tervirtualisasi) |
| `#pane-side [role="listitem"]` | satu baris chat; judul di `span[title]` pertama |
| `#main` | panel percakapan; nama chat di `#main header span[title]` |
| `#main div[data-id]` | satu pesan; `data-id` = `<true|false>_<jid>_<msgid>` (`true` = dari saya) |
| `[data-pre-plain-text]` | teks pesan; atribut berisi `[HH:MM, D/M/YYYY] Nama: ` |
| `button[data-testid^="download-native-client-button"]` | tombol banner download (ditemukan via probe 2026-10-01) |

## 3. Struktur file

`main.swift` (533 baris) melewati ambang ~400 dari spec inti → dipecah. `swiftc *.swift`; hanya
`main.swift` boleh punya kode top-level.

```
main.swift            entry: --selftest lalu NSApplication
Helpers.swift         fungsi murni lama + baru (semua dites selftest)
Selftest.swift        selftest()
Accounts.swift        enum Accounts (+ pendingRemoval)
AccountWindow.swift   AccountWindow + extension navigasi/download/notifikasi
AppDelegate.swift     AppDelegate, menu, badge, notifikasi, aksi Tweaks
Tweaks.swift          tweaksScript, tweaksStyle, TweakSettings, Bookmark, Tag, TweakStore, GlobalHotkey
BookmarksPanel.swift  NSPanel + NSTableView
```

`build.sh`: `swiftc -O -target … *.swift` + `-framework Carbon -framework JavaScriptCore` (Carbon untuk hotkey, JavaScriptCore untuk cek sintaks JS di selftest).

## 4. Data

### 4.1 `TweakSettings` (UserDefaults, berlaku untuk semua akun)

| Key | Tipe | Default | Arti |
|---|---|---|---|
| `blur` | Bool | false | blur privasi aktif |
| `hideBanner` | Bool | true | banner download disembunyikan |
| `dndEnabled` | Bool | false | jadwal senyap aktif |
| `dndStart` | String | `"22:00"` | awal senyap, `HH:mm` |
| `dndEnd` | String | `"07:00"` | akhir senyap, `HH:mm`; boleh lewat tengah malam |

Jam DND diubah lewat `defaults write dev.zen.wa dndStart 23:30` (tanpa UI). Filter tag dan
"selalu di atas" tidak dipersist (sesi saja).

### 4.2 Per akun: `~/Library/Application Support/wa-desk/<accountId>/`

`bookmarks.json` — array `Bookmark`:

```swift
struct Bookmark: Codable, Equatable {
    var id: String        // data-id pesan, unik
    var chat: String      // judul chat saat disimpan
    var jid: String?      // dari data-id, mis. 628123@c.us / 1203@g.us
    var text: String      // ≤ 300 karakter
    var time: String      // "[HH:MM, D/M/YYYY]" apa adanya dari WhatsApp, atau ""
    var fromMe: Bool
    var savedAt: Date
}
```

`tags.json` — `TagData`:

```swift
struct Tag: Codable, Equatable { var name: String; var color: String }   // color = salah satu palet
struct TagData: Codable, Equatable {
    var tags: [Tag] = []
    var chats: [String: [String]] = [:]   // judul chat → nama tag
}
```

Palet 6 warna (hex): `#34D399 #60A5FA #F472B6 #FBBF24 #A78BFA #F87171`. Nama tag unik,
case-sensitive, 1–24 karakter.

`TweakStore` (satu per akun): `load()` saat window dibuat, `save()` setelah tiap perubahan,
tulis atomik (`Data.write(options: .atomic)`). File korup atau skema tak cocok → rename ke
`<nama>.bak-<unix time>`, mulai kosong, log stderr. Folder dibuat saat pertama simpan.

## 5. Lapisan inject (`Tweaks.swift`)

### 5.1 `tweaksStyle`

```css
html[data-wadesk-blur="1"] #pane-side [role="listitem"], html[data-wadesk-blur="1"] #main div[data-id],
html[data-wadesk-blur="1"] #main header { filter: blur(6px); transition: filter .12s; }
html[data-wadesk-blur="1"] #pane-side [role="listitem"]:hover, html[data-wadesk-blur="1"] #main div[data-id]:hover,
html[data-wadesk-blur="1"] #main header:hover { filter: none; }
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
```

Baris tak cocok filter **diredupkan**, bukan disembunyikan: daftar chat WhatsApp tervirtualisasi
(baris diposisikan absolut), `display:none` meninggalkan lubang.

### 5.2 `tweaksScript` — `window.__wadesk`

| Fungsi | Perilaku |
|---|---|
| (init) | sisipkan `<style id="wadesk">`; pasang `mouseover` di `document` yang mengingat `#main div[data-id]` terakhir di-hover; pasang satu `MutationObserver` di `document.body` (childList, subtree, throttle 250 ms) yang memanggil `markBanner()` dan `applyTags()` |
| `capture()` | dari pesan terakhir di-hover: `{id, chat, jid, text, time, fromMe}`; `chat` = `#main header span[title]`.title; `text` = `[data-pre-plain-text]`/`.selectable-text` innerText atau fallback innerText pesan, dipotong 300; `time` = atribut `data-pre-plain-text` bagian `[…]` atau `""`; `fromMe` = data-id diawali `true_`; `jid` = segmen ke-2 data-id. Tidak ada pesan di-hover → `null` |
| `currentChat()` | `{title, jid}` chat yang terbuka (`jid` dari `#main div[data-id]` mana pun), atau `null` |
| `openChat(title, jid)` | cari `#pane-side span[title]` yang `title === title` → dispatch `mousedown`,`mouseup`,`click` pada `span[title]` di dalam baris (bubbling sampai listitem) → `"clicked"`. Tidak ada & `jid` berakhiran `@c.us` → `location.href = "https://web.whatsapp.com/send?phone=" + nomor` → `"navigated"`. Selain itu `"missing"` |
| `jumpTo(id, title)` | poll ≤ 3 s sampai `#main header span[title]`.title === title; lalu `#main div[data-id="<id>"]` → `scrollIntoView({block:"center"})`, tambah `.wadesk-flash` 2 s → `true`; tidak ketemu → `false` |
| `setTags(map)` | `map` = {judul: [warnaHex…]}; simpan; `applyTags()`: tiap baris `[role="listitem"]`: judul → `colors`; titik memakai warna pertama: `row.dataset.wadeskTag = colors[0] || ""`, `row.style.setProperty("--wadesk-tag", colors[0])`, dan `row.dataset.wadeskMatch` = `"1"` kalau filter kosong atau `colors.includes(filter)`, selain itu `"0"` |
| `setFilter(color)` | simpan; `html.dataset.wadeskFilter = color`; `applyTags()` |
| `setBlur(on)`, `setHideBanner(on)` | set `html.dataset.wadeskBlur` / `wadeskHideBanner` ke `"1"`/`""` |
| `markBanner()` | untuk tiap tombol download: naik ≤ 8 tingkat selama induk bukan `body`/`#app`, tidak cocok/berisi `#pane-side`, `#main`, `[role=listitem]`, QR, `header`, `[role=textbox]`, `[contenteditable]`, `input`, `textarea`, dan hanya memuat satu tombol download → tandai node tertinggi itu dengan `data-wadesk-banner="1"` |
| `setCustomCSS(text)` | isi/ganti `<style id="wadesk-custom">` |
| `toast(msg)` | tampilkan `#wadesk-toast` 1.6 s |
| `debug()` | `{paneSide, main, rows, messages, bannerButtons, hovered}` (boolean/jumlah), `banner`: daftar node yang ditandai banner |

Semua fungsi `try/catch` internal; gagal → kembalikan `null`/`false`, tidak melempar.

## 6. Native

### 6.1 Menu **Tweaks** (top-level, setelah View)

| Item | Shortcut | Aksi |
|---|---|---|
| Blur Privasi | ⇧⌘B | toggle `blur` (centang), `setBlur` ke semua akun |
| Sembunyikan Banner Download | — | toggle `hideBanner` (centang), `setHideBanner` ke semua akun |
| — | | |
| Bookmark Pesan | ⌘D | `capture()` di akun key → tambah ke store (id sama → ganti) → `toast("Disimpan")`; `null` → `toast("Arahkan kursor ke pesan dulu")` |
| Tampilkan Bookmark… | ⇧⌘D | tampilkan `BookmarksPanel` untuk akun key |
| — | | |
| Tag Chat Ini ▸ | | submenu: satu item per tag (centang = chat terbuka punya tag itu; klik toggle), pemisah, **Tag Baru…** (NSAlert: field nama + popup warna → buat tag & langsung pasang ke chat terbuka), **Hapus Tag ▸** (submenu per tag → NSAlert konfirmasi → hapus tag dari daftar dan dari semua chat). Tidak ada chat terbuka → item tag disabled |
| Filter Tag ▸ | | **Semua** + satu item radio per tag → `setFilter(warna atau "")` |
| — | | |
| Jadwal Senyap 22:00–07:00 | — | toggle `dndEnabled` (centang); judul menampilkan jam dari defaults |
| Muat Ulang CSS Kustom | — | baca `~/.config/wa-desk/custom.css` → `setCustomCSS` ke semua akun; tidak ada file → toast "Tidak ada ~/.config/wa-desk/custom.css" |
| Debug Selector | — | `debug()` → cetak JSON ke stderr dan `toast` ringkas (`pane:✓ main:✓ rows:42 msgs:30 banner:0`) |

Menu Tweaks dibangun ulang (`NSMenuDelegate.menuNeedsUpdate`) supaya centang dan daftar tag
selalu segar.

### 6.2 Menu Window: **Selalu di Atas** ⌥⌘T

Toggle `window.level` antara `.normal` dan `.floating` untuk window key; centang mengikuti.

### 6.3 Hotkey global ⌥⌘W (`GlobalHotkey` di `Tweaks.swift`)

Carbon `RegisterEventHotKey(kVK_ANSI_W, cmdKey|optionKey, …)` + `InstallEventHandler`
(tanpa izin Accessibility). Aksi: kalau app aktif → `NSApp.hide(nil)`; kalau tidak →
`NSApp.activate()` lalu `present` semua akun yang windownya tersembunyi. Gagal daftar → log stderr.

### 6.4 `BookmarksPanel` (per akun, dibuat malas)

`NSPanel` 520×460, `.titled, .closable, .resizable, .utilityWindow`, judul "Bookmark".
`NSTableView` 3 kolom: Chat (140), Pesan (sisa), Waktu (120); urut `savedAt` menurun.
Return / dobel-klik → `openChat` lalu, kalau hasil `"clicked"`, `jumpTo`; `"navigated"` →
toast "Membuka chat…"; `"missing"` → toast "Chat tidak terlihat di daftar"; `jumpTo` false →
toast "Pesan lama, scroll manual". Delete/⌫ → hapus baris (tanpa konfirmasi; bisa bookmark lagi).
Panel mengamati perubahan store (closure `onChange`) dan `reloadData`.

### 6.5 DND di jalur notifikasi

Di handler `notify` (AccountWindow), setelah `shouldNotify`:

```swift
guard !dndActive(minutesNow: minutesOfDay(Date()), start: settings.dndStart, end: settings.dndEnd, enabled: settings.dndEnabled)
```

Badge Dock tetap diperbarui.

### 6.6 CSS kustom

Saat `AccountWindow` dibuat dan saat menu reload: kalau `~/.config/wa-desk/custom.css` ada,
isinya dikirim via `setCustomCSS`. Tidak ada file → tidak ada aksi (menu reload memberi toast).

## 7. Fungsi murni baru (`Helpers.swift`, semua di selftest)

```swift
func minutesOfDay(_ hhmm: String) -> Int?            // "22:00" → 1320; "7:5" → 425; "25:00"/"ab" → nil
func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Int
func dndActive(minutesNow: Int, start: String, end: String, enabled: Bool) -> Bool
    // enabled false → false; start/end invalid → false; start == end → false;
    // start < end: start ≤ now < end; start > end (lewat tengah malam): now ≥ start || now < end
func bookmark(fromCapture d: [String: Any], savedAt: Date) -> Bookmark?
    // butuh id & chat non-kosong; text dipotong 300; field lain opsional dengan default
func tagColorValid(_ hex: String) -> Bool             // ada di palet
func tagNameValid(_ name: String) -> Bool             // 1–24 karakter setelah trim, tanpa newline
func tagColors(_ data: TagData) -> [String: [String]]   // judul → warna semua tag yang masih ada, urut
```

## 8. Error handling

| Situasi | Perilaku |
|---|---|
| Jangkar DOM tidak ada (WhatsApp berubah) | fungsi JS kembalikan `null`/`false` (semua dibungkus try/catch); native menampilkan toast spesifik di bawah; diagnosis lewat Tweaks → Debug Selector (✗ = selector perlu diperbarui) |
| `capture()` null karena belum hover | toast "Arahkan kursor ke pesan dulu" |
| Chat bookmark tidak terlihat di daftar & bukan nomor | toast "Chat tidak terlihat di daftar"; tidak ada navigasi |
| Pesan lama belum dimuat | chat terbuka, toast "Pesan lama, scroll manual" |
| JSON korup | rename `.bak-<ts>`, mulai kosong, log stderr |
| Hotkey gagal didaftar (konflik) | log stderr, fitur lain jalan |
| `dndStart`/`dndEnd` invalid | DND dianggap mati |
| `custom.css` tidak ada | lewati; hanya menu reload yang memberi toast |
| Panel dibuka saat semua window tersembunyi | pakai akun pertama |

## 9. Testing

Selftest (otomatis, tiap build):
- `minutesOfDay`: 4 kasus (valid, satu digit, >23, non-angka).
- `dndActive`: disabled; start<end dalam/luar; lewat tengah malam (23:00 & 03:00 aktif, 12:00 tidak); start==end; string invalid.
- `bookmark(fromCapture:)`: lengkap; tanpa `id` → nil; `text` 400 karakter → 300; `fromMe` bukan Bool → false.
- `tagColorValid` / `tagNameValid`: valid, kosong, 25 karakter, bukan palet.
- `tagColors`: tag terhapus dilewati; dua tag → kedua warna, urut.
- Roundtrip JSON `TagData` dan `[Bookmark]` lewat `JSONEncoder/Decoder`.
- **Sintaks JS**: `JSContext().evaluateScript(tweaksScript)`; `context.exception == nil`; dan `evaluateScript("typeof __wadesk.capture")` == `"function"` (JSC tanpa DOM: skrip harus menoleransi `document` undefined saat init — guard `if (typeof document !== "undefined")` sebelum menyentuh DOM).

Manual (checklist README, butuh login): blur on/off + hover; banner hilang di halaman QR dan setelah login; ⌘D pada pesan → toast → muncul di panel; Return di panel → chat terbuka & pesan berkilat; bookmark chat yang di luar layar; tag baru → titik warna; filter → baris lain redup; hapus tag; ⌥⌘W dari app lain; Selalu di Atas; DND: set `dndStart` ke menit sekarang, nyalakan, kirim pesan → tanpa banner, badge naik; `custom.css` berisi `#pane-side{background:#111}` → reload → terlihat; Debug Selector menunjukkan semua ✓.

## 10. Di luar scope

UI ubah jam DND, sinkron antar Mac/akun, pencarian/sortir di panel, ekspor bookmark, tag by JID
(pakai judul; rename kontak melepas tag), persist always-on-top dan filter, bookmark media
(hanya teks + metadata), tema/dark mode kustom (bisa lewat custom.css).
