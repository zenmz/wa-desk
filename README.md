<p align="center">
  <img src="docs/assets/icon-256.png" width="128" height="128" alt="Icon WA Desk">
</p>

<h1 align="center">WA Desk</h1>

<p align="center">
  WhatsApp Desktop ringan untuk macOS. Engine WebKit bawaan sistem, tanpa Electron, tanpa dependency.<br>
  <sub>A lightweight native WhatsApp Web wrapper for macOS with privacy blur, local bookmarks, chat tags, quiet hours, and multi-account tabs.</sub>
</p>

<p align="center">
  <a href="https://github.com/zenmz/wa-desk/tags"><img src="https://img.shields.io/github/v/tag/zenmz/wa-desk?label=versi&color=059669" alt="Versi"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111827" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Homebrew-zenmz%2Ftap%2Fwa--desk-f59e0b" alt="Homebrew">
  <img src="https://img.shields.io/badge/app-1.3%20MB-34D399" alt="Ukuran app">
</p>

---

## Kenapa WA Desk

WhatsApp Desktop resmi berbasis Electron: membawa Chromium sendiri, berat di RAM dan menyisakan
ratusan MB di disk. WA Desk hanya membungkus **web.whatsapp.com** dalam `WKWebView` (engine yang sama
dengan Safari) dan menambah fitur native yang tidak ada di WhatsApp Web.

| | WA Desk | WhatsApp Desktop resmi |
|---|---|---|
| Ukuran app | **1,3 MB** | ratusan MB (Electron) |
| RAM, 1 akun login | **~90 MB** (app + helper WebKit, RSS saat baru dibuka) | belum diukur di mesin ini |
| Data lokal | 204 MB (cache WebKit, 1 akun) | 570 MB sisa container di mesin ini |
| Dependency | 0 | Electron + Chromium |

Angka diukur 2026-10-01 di macOS 26 pada 1 akun; RAM WebKit bertambah seiring banyaknya chat/media yang dibuka.

## Fitur

**Inti**
- Notifikasi native macOS, klik membuka chat yang benar. Badge unread di Dock.
- Multi-akun: tiap akun satu tab native, sesi login terpisah.
- Panggilan suara/video (WebRTC WebKit), download ke `~/Downloads`, attach file, drag-drop.
- Link luar terbuka di browser default. Tutup window hanya menyembunyikan; pesan tetap masuk.

**Tweaks (menu Tweaks)**
- **Blur Privasi**: tiap baris chat, pesan, dan header dikaburkan sendiri-sendiri; yang di bawah kursor jelas.
- **Bookmark pesan** tanpa batas (pengganti pin yang dibatasi server WhatsApp), panel native, lompat ke pesan.
- **Tag chat** dengan titik warna dan filter, lokal di Mac.
- **Senyap**: senyap sekarang (30 menit, 1 jam, 2 jam, sampai dimatikan) dan jadwal senyap dengan editor jam.
- Sembunyikan banner "Download WhatsApp for Mac", hotkey global tampil/sembunyi, selalu di atas, CSS kustom.

## Instalasi

### Homebrew (disarankan)

```sh
brew install zenmz/tap/wa-desk
ln -sfn "$(brew --prefix)/opt/wa-desk/WA Desk.app" "/Applications/WA Desk.app"
```

Formula membangun dari source saat install (sekitar 15 detik, butuh Command Line Tools:
`xcode-select --install`). Karena dibangun di Mac sendiri, tidak ada peringatan Gatekeeper.

- Update: `brew upgrade wa-desk`
- Versi pengembangan dari `main`: `brew install --HEAD zenmz/tap/wa-desk`
- Uninstall: `brew uninstall wa-desk && rm "/Applications/WA Desk.app"`. Data login ada di
  `~/Library/WebKit/dev.zen.wa`, bookmark/tag di `~/Library/Application Support/wa-desk`,
  setting di `defaults delete dev.zen.wa`.

### Dari source

```sh
git clone https://github.com/zenmz/wa-desk.git && cd wa-desk
./build.sh && open "WA Desk.app"
```

### Launch pertama

1. Scan QR dari HP seperti WhatsApp Web biasa.
2. macOS akan minta izin **notifikasi** saat launch, **folder Downloads** saat download pertama,
   dan **kamera/mikrofon** saat call pertama.
3. Tanpa internet saat launch window kosong; tekan ⌘R setelah online.

## Cara pakai

| Aksi | Shortcut |
|---|---|
| Akun baru (tab) | ⌘N |
| Pindah akun | ⌃Tab / ⌃⇧Tab |
| Hapus akun yang sedang dilihat (sesi + cache) | File → Hapus Akun Ini… |
| Sembunyikan window (pesan tetap masuk) | ⌘W; klik ikon Dock untuk kembali |
| Tampil/sembunyikan app dari mana saja | ⌥⌘W (global) |
| Zoom | ⌘= / ⌘- / ⌘0 |
| Reload | ⌘R |
| Keluar | ⌘Q |

## Tweaks

| Fitur | Cara | Catatan |
|---|---|---|
| Blur Privasi | ⇧⌘B | per baris chat, per pesan, dan header; hover untuk melihat |
| Sembunyikan Banner Download | Tweaks → centang | aktif secara default |
| Bookmark Pesan | arahkan kursor ke pesan, ⌘D | **Tampilkan Bookmark…** ⇧⌘D: Return/dobel-klik buka chat dan lompat ke pesan, ⌫ hapus |
| Tag Chat Ini | Tweaks → Tag Chat Ini | nama + warna; titik warna di daftar chat; **Filter Tag** meredupkan chat lain |
| Senyap sekarang | ⇧⌘M, atau Tweaks → Senyap → Senyap Sekarang | 30 menit / 1 jam / 2 jam / sampai dimatikan; ⇧⌘M lagi mematikan |
| Jadwal Senyap | Tweaks → Senyap → Atur Jadwal… | jam Mulai/Selesai, boleh lewat tengah malam; judul menu "Senyap ●" saat aktif |
| Selalu di Atas | ⌥⌘T | per window akun |
| CSS kustom | `~/.config/wa-desk/custom.css` lalu Tweaks → Muat Ulang CSS Kustom | ubah tampilan WhatsApp Web sesuka hati |
| Debug Selector | Tweaks → Debug Selector | toast jumlah elemen yang dikenali + tulis `debug-dom.txt` (lihat Troubleshooting) |

Senyap hanya menahan banner notifikasi; badge Dock tetap berjalan. Senyap sementara tersimpan dan
tetap berlaku setelah app di-restart.

## Privasi & keamanan

- Tidak ada server perantara, telemetri, atau akun tambahan. Lalu lintas langsung ke WhatsApp seperti
  membuka web.whatsapp.com di Safari.
- Tweaks hanya menyuntik CSS, membaca DOM, dan mengirim klik sintetis setara klik pengguna. Tidak ada
  otomasi kirim pesan atau akses ke protokol WhatsApp.
- Bookmark dan tag disimpan sebagai JSON lokal per akun; tidak disinkronkan ke mana pun.
- App ditandatangani ad-hoc oleh `build.sh` di Mac sendiri. Setiap build ulang menjadi identitas baru
  bagi macOS, jadi izin kamera/mikrofon bisa ditanya lagi setelah upgrade.

## Batasan

- Tidak bisa menaikkan batas pin atau mengubah hal lain yang ditegakkan server WhatsApp; bookmark adalah
  pengganti lokal.
- Tag dicocokkan dengan nama chat: mengganti nama kontak melepas tagnya.
- Screen share saat call tidak tersedia (`getDisplayMedia` tidak ada di WKWebView).
- Hotkey ⌥⌘W menimpa shortcut "Close All" app lain selama WA Desk berjalan; ganti konstanta di
  `GlobalHotkey` (`Tweaks.swift`) kalau mengganggu.
- WhatsApp Web bisa mengubah struktur halamannya sewaktu-waktu. Fitur inti tidak terpengaruh; Tweaks
  yang bergantung DOM (blur, bookmark, tag, banner) mungkin perlu penyesuaian selector.

## Troubleshooting

- **Blur/bookmark/tag tidak bekerja atau banner masih muncul**: jalankan Tweaks → Debug Selector. Toast
  menampilkan `pane:✓ main:✓ rows:N …`; ✗ atau `rows:0` berarti selector perlu diperbarui. Ringkasan DOM
  ditulis ke `~/Library/Application Support/wa-desk/debug-dom.txt`; lampirkan di issue.
- **Window kosong**: offline saat launch, tekan ⌘R.
- **Notifikasi tidak muncul**: cek System Settings → Notifications → WA Desk, dan apakah Senyap aktif
  (judul menu "Senyap ●").
- **Mulai dari nol**: ⌘Q, lalu hapus `~/Library/WebKit/dev.zen.wa`, `~/Library/Application Support/wa-desk`,
  dan `defaults delete dev.zen.wa`.

## Untuk pengembang

```
main.swift           entry
Helpers.swift        fungsi murni (semua dites --selftest)
Selftest.swift       selftest: helper, store JSON, sintaks + API skrip inject (JavaScriptCore)
Accounts.swift       daftar akun di UserDefaults
AccountWindow.swift  window + WKWebView per akun, navigasi, download, notifikasi, jembatan tweak()
AppDelegate.swift    menu, badge, hotkey, aksi Tweaks
Tweaks.swift         setting, model Bookmark/Tag, store JSON, dan seluruh JS/CSS yang tahu DOM WhatsApp
BookmarksPanel.swift panel bookmark
icon/make-icon.swift icon digambar dengan CoreGraphics saat build
```

`./build.sh` mengompilasi semua file dengan `swiftc`, menggambar icon, membungkus `WA Desk.app`,
codesign ad-hoc, lalu menjalankan `wa-desk --selftest`; build gagal kalau selftest gagal.
Semua ketergantungan pada DOM WhatsApp sengaja dikumpulkan di `Tweaks.swift` (`tweaksScript`,
`tweaksStyle`). Desain dan plan ada di `docs/superpowers/`. Checklist uji manual: [docs/smoke-test.md](docs/smoke-test.md).

Rilis: naikkan versi di `Info.plist`, tag `vX.Y.Z`, lalu perbarui `url` + `sha256` di
[zenmz/homebrew-tap](https://github.com/zenmz/homebrew-tap).

## Status

Proyek personal yang dipakai harian; bukan produk resmi dan tidak berafiliasi dengan WhatsApp/Meta.
Laporan masalah lewat GitHub Issues, sertakan `debug-dom.txt` bila terkait Tweaks.
