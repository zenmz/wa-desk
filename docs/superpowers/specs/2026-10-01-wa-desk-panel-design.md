# WA Desk — Satu window, panel WA Desk di halaman

Tanggal: 2026-10-01
Status: disetujui untuk planning
Dasar: spec inti (2026-09-30) dan spec Tweaks (2026-10-01)

## 1. Tujuan

1. Semua akun hidup dalam **satu window**: ⌘N membuat akun baru tanpa membuka tab/window baru; pindah akun
   lewat menu **Akun** (⌘1–⌘9) atau panel di halaman.
2. **Icon WA Desk** di bilah navigasi kiri WhatsApp Web, tepat di bawah Meta AI. Klik → popover berisi
   daftar akun (pindah, ganti nama, tambah, hapus) dan semua Tweaks.
3. Menu bar Tweaks tetap ada; panel hanya cermin dengan aksi yang sama.

## 2. Model window

- `MainWindow` (satu `NSWindowController`): window 1100×750, `tabbingMode = .disallowed`, autosave `main`,
  `contentView` = container. `attach(account)` menumpuk `webView` akun (tersembunyi), `show(account)` menampilkan
  satu dan menyembunyikan yang lain, `detach(account)` melepas. Tutup window = sembunyikan.
- `Account` (dulu `AccountWindow`): `webView`, data store, `store`, `unread`, `openChatTitle`, `tagFilter`,
  `bookmarksPanel`, `pageTitle`, `name`, `windowTitle` ("<nama> · <judul halaman>"), `isBeingViewed`
  (webView terlihat dan window key). Semua akun tetap memuat halaman: notifikasi dan badge jalan untuk akun
  yang tidak tampil. Banner notifikasi ditekan hanya untuk akun yang sedang dilihat.
- Akun aktif terakhir disimpan di UserDefaults `activeAccount` dan dipulihkan saat launch.
- Nama akun: UserDefaults `accountNames` `[id: nama]`; default `"Akun N"` (urutan daftar); fungsi murni
  `accountLabel(custom:index:)`.
- Menu **Akun** (dibangun ulang saat dibuka): satu item per akun "<nama>  (<unread>)" ⌘1–⌘9, centang = aktif;
  Akun Berikutnya ⌃Tab, Akun Sebelumnya ⌃⇧Tab; Akun Baru ⌘N; Ganti Nama Akun…; Hapus Akun Ini….
  Menu File hanya Close ⌘W. Menu Window: Minimize, Selalu di Atas.
- Hapus akun: konfirmasi native (menyebut nama akun) → lepas webView, hapus dari daftar, data store dan folder
  Application Support, nama kustom; lalu tampilkan akun tetangga; nol akun → buat baru.

## 3. Icon di bilah navigasi

- Dicari di `[data-testid="navbar-primary-section"]`: item yang `aria-label`/`title`/teks cocok `/meta ai/i`;
  "item" = leluhur yang anak langsung section. Item itu di-`cloneNode(true)`, atribut `id`, `data-testid`,
  `data-navbar-item`, `aria-label`, `title`, `tabindex` dibersihkan dari seluruh subtree, SVG diganti SVG
  gelembung WA Desk (24 px, `currentColor`), lalu disisipkan **setelah** item Meta AI. Hover/active mengikuti
  class WhatsApp yang ikut terklon.
- Fallback tanpa Meta AI: elemen 40×40 bergaya sendiri di akhir section. Tanpa section (halaman QR): tidak ada icon.
- `data-wadesk-nav="1"`, `role=button`, `aria-label="WA Desk"`, klik/Enter/Spasi → toggle panel. Observer
  (throttle 500 ms) memasang ulang kalau WhatsApp merender ulang bilah.

## 4. Panel

- `#wadesk-panel`, `position: fixed`, lebar 320, `max-height: 80vh`, scroll, di kanan bilah (`navRect.right + 8`),
  atas sejajar icon (dijepit ke viewport). Tema gelap/terang dari luminans `background-color` `body`.
  Tutup: Esc, klik di luar, atau klik icon lagi.
- Dirender murni dari **state** yang didorong native lewat `__wadesk.setPanelState(state)`; saat dibuka panel
  mengirim `{action: "panelOpen"}` supaya native mendorong state terbaru. `__wadesk.openPanel()` juga ada.
- State: `version`, `accounts: [{id, name, unread, active}]`, `blur`, `hideBanner`, `mute: {active, label}`,
  `dnd: {enabled, start, end, active}`, `onTop`, `tags: [{name, color, checked}]`, `hasOpenChat`, `filter`.
- Isi: **Akun** (baris per akun: titik aktif, nama, badge unread, ✎ ganti nama; "+ Akun baru ⌘N";
  "Hapus akun ini…"), **Tweaks** (saklar Blur ⇧⌘B, Sembunyikan banner; tautan "Bookmark pesan yang di-hover ⌘D",
  "Tampilkan bookmark… ⇧⌘D"; "Tag chat ini" daftar kotak centang + "+ Tag baru…" (dinonaktifkan tanpa chat
  terbuka); "Filter tag" chip Semua + tag; "Senyap" status + chip 30 mnt / 1 jam / 2 jam / ∞ / Matikan;
  saklar Jadwal senyap HH:MM–HH:MM + ⚙ Atur; saklar Selalu di atas ⌥⌘T; "Muat ulang CSS kustom";
  "Debug selector").
- Semua teks dari state di-escape sebelum masuk HTML.

## 5. Jembatan aksi

- Panel → native: `webkit.messageHandlers.wadesk.postMessage({action, id?, tag?, color?, min?})`, lewat guard
  main-frame + origin yang sama dengan `notify`.
- Native: `panelAction(from:) -> PanelAction?` (fungsi murni, di selftest) hanya menerima aksi dari daftar
  tetap; `id` harus UUID dan milik akun yang ada (dicek di AppDelegate); `min ∈ {30, 60, 120, 0}`; `tag` lolos
  `tagNameValid`; `color` kosong atau dari palet. Aksi tak dikenal diabaikan.
- Aksi dipetakan ke fungsi menu yang sudah ada (`toggleBlur`, `toggleHideBanner`, `bookmarkMessage`,
  `showBookmarksPanel`, `toggleTag(named:in:)`, `newTag`, `setFilter(_:in:)`, `mute(minutes:)`, `muteOff`,
  `toggleDND`, `editQuietHours`, `toggleAlwaysOnTop`, `reloadCustomCSS`, `debugSelectors`, `show(account)`,
  `newAccount`, `rename(account)`, `removeAccount`). Aksi destruktif tetap lewat konfirmasi native.
- Setelah setiap aksi, dan setiap kali unread/akun aktif/chat terbuka/tag/senyap berubah, native mendorong
  state ke semua akun (`pushPanelState()`).

## 6. Testing

- Selftest: `accountLabel` (kustom, kosong, spasi, index); `panelAction(from:)` (semua aksi valid; aksi tak
  dikenal; `min` 45 ditolak; `id` bukan UUID ditolak; `tag` kosong ditolak; `color` di luar palet ditolak);
  skrip gabungan dievaluasi di JSContext tanpa exception; `typeof __wadesk.setPanelState/openPanel`.
- Harness DOM tiruan (dijalankan implementer): bilah dengan item Meta AI → icon tersisip tepat setelahnya,
  atribut WhatsApp dibersihkan; tanpa Meta AI → fallback di akhir; `setPanelState` + `openPanel` → panel
  berisi nama akun, unread, saklar sesuai state; klik baris akun → `postMessage({action:"switchAccount", id})`
  (handler dimock); Esc menutup.
- Manual (user): pindah akun lewat ⌘1/⌘2 dan panel, notifikasi akun tersembunyi tetap muncul, ganti nama,
  hapus akun, semua aksi Tweaks dari panel.

## 7. Di luar scope

Drag-urut akun, avatar/nomor telepon di daftar akun, sinkron nama akun antar Mac, panel di halaman QR,
animasi panel.
