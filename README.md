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

## Ukuran

Angka WA diukur di halaman QR (sebelum login, satu akun); ukur ulang setelah login.

| App | RAM | Storage |
|---|---|---|
| WA (halaman QR, 1 akun) | 55.5 MB | app 212K, data 71M |
| WhatsApp resmi (sisa container) | belum diukur (app tidak terpasang) | 161M + 409M (Containers + Group Containers) |
