# Checklist uji manual WA Desk

Jalankan setelah login (butuh HP untuk scan QR). Centang yang lulus. Kalau ada yang gagal,
jalankan **Tweaks → Debug Selector** dan lampirkan `~/Library/Application Support/wa-desk/debug-dom.txt`
di issue.

## Inti
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

## Tweaks
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
