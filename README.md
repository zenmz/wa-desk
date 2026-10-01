# WA Desk

Client WhatsApp Desktop ringan untuk macOS 14+. Satu `WKWebView` (WebKit sistem)
per akun di atas web.whatsapp.com, tanpa Electron, tanpa dependency.
Notifikasi native, badge Dock, download ke ~/Downloads, call, multi-akun sebagai tab.

## Install (Homebrew)

    brew install zenmz/tap/wa-desk
    ln -sfn "$(brew --prefix)/opt/wa-desk/WA Desk.app" "/Applications/WA Desk.app"

Formula build dari source saat install (~10 detik, butuh Command Line Tools),
jadi tidak ada masalah Gatekeeper. Update: `brew upgrade wa-desk`.
Versi terbaru dari `main`: `brew install --HEAD zenmz/tap/wa-desk`.

## Build

Butuh Command Line Tools (`xcode-select --install`). Tidak butuh Xcode.app.

    ./build.sh && open "WA Desk.app"

`build.sh` mengompilasi `*.swift`, menggambar icon dari `icon/make-icon.swift`
(CoreGraphics → `sips` → `iconutil`), membungkus `WA Desk.app`, codesign ad-hoc,
lalu menjalankan `wa-desk --selftest` (fungsi murni: badge, filter akun, nama file download,
aturan link luar, notifikasi, jadwal senyap, bookmark, tag; store JSON; sintaks dan API skrip inject lewat JavaScriptCore).

## Pakai

- Cmd+N: akun baru (tab). Ctrl+Tab / Ctrl+Shift+Tab: pindah akun (item Show Next/Previous Tab di menu Window ditambahkan otomatis oleh macOS).
- File → Hapus Akun Ini…: hapus sesi + cache akun yang sedang dilihat.
- Cmd+W menyembunyikan window; pesan tetap masuk. Keluar dengan Cmd+Q.
- Klik ikon Dock menampilkan lagi window yang disembunyikan.
- Cmd+= / Cmd+- / Cmd+0 zoom. Cmd+R reload.

Data per akun disimpan WebKit per UUID, biasanya di `~/Library/WebKit/dev.zen.wa/`
(kalau tidak ada: `find ~/Library -maxdepth 3 -name 'dev.zen.wa*'`).
Daftar akun di `defaults read dev.zen.wa accounts`.

## Tweaks

Menu **Tweaks** menambah fitur yang tidak ada di WhatsApp Web; semuanya lokal di Mac ini.

- **Blur Privasi** (⇧⌘B): tiap baris chat, tiap pesan, dan header chat dikaburkan sendiri-sendiri; yang di bawah kursor jelas.
- **Sembunyikan Banner Download**: banner "Download WhatsApp for Mac" disembunyikan (default aktif).
- **Bookmark Pesan** (⌘D): arahkan kursor ke pesan, tekan ⌘D. **Tampilkan Bookmark…** (⇧⌘D) membuka
  panel; Return/dobel-klik membuka chat dan melompat ke pesan (kalau pesannya sudah dimuat), ⌫ menghapus.
  Pengganti pin: batas pin ditegakkan server WhatsApp dan tidak bisa dinaikkan.
- **Tag Chat Ini**: beri tag (nama + warna) ke chat yang terbuka; titik warna muncul di daftar chat.
  **Filter Tag** meredupkan chat lain. Tag dicocokkan dengan judul chat: mengganti nama kontak melepas tag.
- **Senyap ▸**: **Senyap Sekarang** (30 menit / 1 jam / 2 jam / sampai dimatikan) untuk meeting; ⇧⌘M = senyap
  1 jam atau matikan. **Jadwal Senyap** menahan notifikasi pada jam tertentu; **Atur Jadwal…** memilih jam Mulai/Selesai
  (boleh lewat tengah malam). Judul menu jadi "Senyap ●" saat sedang senyap. Badge Dock tetap jalan; senyap sementara
  bertahan walau app di-restart.
- **Muat Ulang CSS Kustom**: `~/.config/wa-desk/custom.css` disuntik ke halaman; ubah apa pun lewat CSS.
- **Debug Selector**: toast jumlah elemen WhatsApp yang dikenali, dan tulis ringkasan struktur DOM ke
  `~/Library/Application Support/wa-desk/debug-dom.txt`. Kalau ada ✗ atau banner masih muncul, file itu
  yang dipakai untuk memperbarui selector di `Tweaks.swift`.
- Window → **Selalu di Atas** (⌥⌘T): berlaku per window akun yang aktif. Hotkey global **⌥⌘W** menampilkan/menyembunyikan
  app dari mana saja. Catatan: selama WA Desk jalan, ⌥⌘W di app lain (yang biasanya "Close All") ikut tertangkap; ubah
  konstanta di `GlobalHotkey` (`Tweaks.swift`) kalau mengganggu.

Data bookmark dan tag ada di `~/Library/Application Support/wa-desk/<id akun>/` (JSON).
Semua Tweaks hanya CSS, pembacaan DOM, dan klik sintetis setara klik user; tidak ada otomasi kirim pesan.

## Launch pertama

- macOS akan minta izin notifikasi saat launch, akses folder Downloads saat download pertama, dan kamera/mic saat call pertama.
- Tanpa internet saat launch window kosong; Cmd+R memuat ulang setelah online.
- `build.sh` menandatangani ad-hoc: tiap build ulang = identitas baru bagi macOS, jadi izin kamera/mic bisa ditanya lagi setelah rebuild. Pakai identitas self-signed di Keychain kalau ini mengganggu.

## Tidak ada (sengaja)

App icon, auto-update, ikon menubar, launch at login, screen share saat call
(`getDisplayMedia` tidak tersedia di WKWebView).

## Checklist smoke test

Jalankan setelah login; centang yang lulus.

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
- [ ] Tweaks: blur ⇧⌘B on/off, jelas saat hover
- [ ] Tweaks: banner download hilang (halaman QR dan setelah login)
- [ ] Tweaks: ⌘D pada pesan → toast "Disimpan" → muncul di panel; Return → chat terbuka, pesan berkilat
- [ ] Tweaks: bookmark chat yang di luar layar → toast yang sesuai
- [ ] Tweaks: tag baru → titik warna; Filter Tag → chat lain redup; hapus tag
- [ ] Tweaks: ⌥⌘W dari app lain; Selalu di Atas
- [ ] Tweaks: Jadwal Senyap aktif → pesan masuk tanpa banner, badge naik
- [ ] Tweaks: ⇧⌘M → toast "Senyap sampai HH:MM", pesan masuk tanpa banner; ⇧⌘M lagi → matikan
- [ ] Tweaks: Atur Jadwal… → simpan → judul "Jadwal Senyap HH:MM–HH:MM" berubah dan tercentang
- [ ] Tweaks: `custom.css` berisi `#pane-side{background:#111}` → Muat Ulang → terlihat
- [ ] Tweaks: Debug Selector semua ✓

## Ukuran

Angka WA Desk diukur di halaman QR (sebelum login, satu akun); ukur ulang setelah login.

| App | RAM | Storage |
|---|---|---|
| WA Desk (halaman QR, 1 akun) | 55.5 MB | app 1.1M (icon 880K), data 41M |
| WhatsApp resmi (sisa container) | belum diukur (app tidak terpasang) | 161M + 409M (Containers + Group Containers) |
