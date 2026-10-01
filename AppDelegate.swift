import Cocoa
import WebKit
import UserNotifications

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, NSMenuItemValidation {
    private(set) var accounts: [Account] = []
    let mainWindow = MainWindow()
    /// Dibangun ulang tiap dibuka (menuNeedsUpdate) supaya centang dan daftar tag selalu segar.
    private let tweaksMenu = NSMenu(title: "Tweaks")
    /// Dibangun ulang tiap dibuka: satu item per akun ⌘1–⌘9 dengan unread, centang akun aktif.
    private let accountsMenu = NSMenu(title: "Akun")

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        GlobalHotkey.register { [weak self] in self?.toggleVisibility() }
        // Senyap berbasis waktu (jadwal, kedaluwarsa): periksa tiap 30 detik.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.pushSilence() }
        // WKWebView menelan ⌃Tab/⌃⇧Tab sebelum sampai ke menu; tangkap lebih dulu di tingkat app.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard e.keyCode == 48, mods.subtracting(.shift) == .control else { return e }
            if mods.contains(.shift) { self?.previousAccount() } else { self?.nextAccount() }
            return nil
        }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        Accounts.pendingRemoval().forEach(purgeDataStore)
        for id in Accounts.all() { attach(id: id) }
        let last = UserDefaults.standard.string(forKey: "activeAccount")
        show(accounts.first { $0.id == last } ?? accounts[0])
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Klik ikon Dock → tampilkan lagi window utama.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        mainWindow.showWindow(nil)
        mainWindow.window?.makeKeyAndOrderFront(nil)
        return true
    }

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
        pushPanelState()
    }

    /// Akun yang panel bookmark-nya key; kalau tidak, akun yang sedang tampil.
    var current: Account? {
        accounts.first { $0.owns(NSApp.keyWindow) } ?? mainWindow.active ?? accounts.first
    }

    /// Senyap sedang berlaku (jadwal atau sementara): banner native ditahan dan audio skrip halaman diblokir.
    var silenced: Bool {
        let now = Date()
        return dndActive(minutesNow: minutesOfDay(now), start: TweakSettings.dndStart,
                         end: TweakSettings.dndEnd, enabled: TweakSettings.dndEnabled)
            || muteActive(now: now, until: TweakSettings.muteUntil)
    }
    private var lastSilenced = false

    /// Dorong status senyap ke semua halaman; panel ikut diperbarui kalau status berubah (mis. senyap kedaluwarsa).
    func pushSilence() {
        let on = silenced
        broadcast("setSilence", ["on": on])
        if on != lastSilenced {
            lastSilenced = on
            pushPanelState()
        }
    }

    func refreshBadge() {
        NSApp.dockTile.badgeLabel = badgeLabel(total: accounts.reduce(0) { $0 + $1.unread })
    }

    /// Judul halaman akun berubah (unread): badge Dock, dan judul window kalau akun itu yang tampil.
    func accountTitleChanged(_ account: Account) {
        refreshBadge()
        if mainWindow.active === account { mainWindow.refreshTitle() }
        pushPanelState()
    }

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
        for a in (account.map { [$0] } ?? accounts) where a.webView.url != nil && !a.webView.isLoading {
            a.tweak("setPanelState", ["state": panelState(for: a)])
        }
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

    /// Hapus data store akun yang sudah dihapus. Dipanggil saat hapus akun dan saat launch,
    /// karena WebKit menolak menghapus store yang masih dipakai dan quit bisa keburu terjadi.
    func purgeDataStore(_ id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        WKWebsiteDataStore.remove(forIdentifier: uuid) { error in
            if let error {
                FileHandle.standardError.write(Data("hapus data store \(id) gagal: \(error.localizedDescription)\n".utf8))
            } else {
                Accounts.clearPendingRemoval(id)
            }
        }
    }

    // MARK: notifikasi

    /// Tampilkan banner walau app di foreground (user mungkin sedang di akun lain).
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
            NSApp.activate()
            show(account)
            if let nid = info["nid"] as? String, Int(nid) != nil {
                account.webView.evaluateJavaScript("window.__waNotifClick('\(nid)')")
            }
        }
        handler()
    }

    // MARK: menu actions

    /// Reload biasa hanya kalau halaman WhatsApp sudah termuat; kalau kosong (launch offline) atau nyasar ke host lain, muat ulang dari awal.
    @objc func reload() {
        guard let wv = current?.webView else { return }
        if let url = wv.url, !isExternal(url) { wv.reload() } else { wv.load(URLRequest(url: waHome)) }
    }
    @objc func zoomIn() { if let wv = current?.webView { wv.pageZoom = min(3, wv.pageZoom + 0.1) } }
    @objc func zoomOut() { if let wv = current?.webView { wv.pageZoom = max(0.5, wv.pageZoom - 0.1) } }
    @objc func zoomReset() { current?.webView.pageZoom = 1 }

    // MARK: Tweaks

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === accountsMenu { rebuildAccountsMenu(); return }
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
        menu.addItem(item("Bookmark Pesan", #selector(bookmarkMessage), "d"))
        menu.addItem(item("Tampilkan Bookmark…", #selector(showBookmarks), "D", [.command, .shift]))
        menu.addItem(.separator())
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
        // Senyap: sementara (sekarang) + jadwal.
        let now = Date()
        let scheduled = dndActive(minutesNow: minutesOfDay(now), start: TweakSettings.dndStart,
                                  end: TweakSettings.dndEnd, enabled: TweakSettings.dndEnabled)
        let temporary = muteActive(now: now, until: TweakSettings.muteUntil)
        let muteMenu = NSMenu(title: "Senyap")
        muteMenu.autoenablesItems = false
        if temporary, let until = TweakSettings.muteUntil {
            muteMenu.addItem(item("Senyap \(muteUntilLabel(until)) — Matikan", #selector(muteOff), "M", [.command, .shift]))
        } else {
            muteMenu.addItem(item("Senyap 1 Jam", #selector(muteOneHour), "M", [.command, .shift]))
        }
        let nowMenu = NSMenu(title: "Senyap Sekarang")
        nowMenu.autoenablesItems = false
        for (title, minutes) in [("30 Menit", 30), ("1 Jam", 60), ("2 Jam", 120), ("Sampai Dimatikan", 0)] {
            let i = item(title, #selector(muteFor(_:)))
            i.representedObject = minutes
            nowMenu.addItem(i)
        }
        let nowHolder = NSMenuItem(title: "Senyap Sekarang", action: nil, keyEquivalent: "")
        nowHolder.submenu = nowMenu
        muteMenu.addItem(nowHolder)
        muteMenu.addItem(.separator())
        muteMenu.addItem(item("Jadwal Senyap \(TweakSettings.dndStart)–\(TweakSettings.dndEnd)",
                              #selector(toggleDND), on: TweakSettings.dndEnabled))
        muteMenu.addItem(item("Atur Jadwal…", #selector(editQuietHours)))
        let muteHolder = NSMenuItem(title: (temporary || scheduled) ? "Senyap ●" : "Senyap", action: nil, keyEquivalent: "")
        muteHolder.submenu = muteMenu
        menu.addItem(muteHolder)
        menu.addItem(item("Muat Ulang CSS Kustom", #selector(reloadCustomCSS)))
        menu.addItem(item("Debug Selector", #selector(debugSelectors)))
    }

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

    /// Panggil fungsi __wadesk di semua akun.
    func broadcast(_ fn: String, _ args: KeyValuePairs<String, Any>) {
        accounts.forEach { $0.tweak(fn, args) }
    }

    @objc func toggleBlur() {
        TweakSettings.blur.toggle()
        broadcast("setBlur", ["on": TweakSettings.blur])
        pushPanelState()
    }

    @objc func toggleHideBanner() {
        TweakSettings.hideBanner.toggle()
        broadcast("setHideBanner", ["on": TweakSettings.hideBanner])
        pushPanelState()
    }

    @objc func reloadCustomCSS() {
        guard let css = customCSS() else {
            broadcast("setCustomCSS", ["css": ""])
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
            acc.tweak("toast", ["msg": "pane:\(ok("paneSide")) main:\(ok("main")) rows:\(d["rows"] ?? 0) msgs:\(d["messages"] ?? 0) banner:\(d["bannerButtons"] ?? 0)+\(d["bannerText"] ?? 0) → debug-dom.txt"])
        }
        // Dump struktur DOM ke file supaya selector bisa diperbaiki tanpa copy-paste dari user.
        acc.tweak("dump") { v in
            guard let text = v as? String, !text.isEmpty else { return }
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("wa-desk")
            let url = dir.appendingPathComponent("debug-dom.txt")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("tulis debug-dom.txt gagal: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    @objc func toggleDND() {
        TweakSettings.dndEnabled.toggle()
        pushSilence()
        pushPanelState()
    }

    // MARK: senyap sementara

    func muteUntilLabel(_ until: Date) -> String {
        if until == .distantFuture { return "sampai dimatikan" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "sampai \(f.string(from: until))"
    }

    @objc func muteFor(_ sender: NSMenuItem) { mute(minutes: sender.representedObject as? Int ?? 60) }
    @objc func muteOneHour() { mute(minutes: 60) }

    /// 0 = sampai dimatikan.
    func mute(minutes: Int) {
        let until: Date = minutes == 0 ? .distantFuture : Date().addingTimeInterval(TimeInterval(minutes * 60))
        TweakSettings.muteUntil = until
        current?.tweak("toast", ["msg": "Senyap \(muteUntilLabel(until))"])
        pushSilence()
        pushPanelState()
    }

    @objc func muteOff() {
        TweakSettings.muteUntil = nil
        current?.tweak("toast", ["msg": "Senyap dimatikan"])
        pushSilence()
        pushPanelState()
    }

    /// Dialog dua pemilih jam (Mulai/Selesai); menyimpan jadwal dan langsung mengaktifkannya.
    @objc func editQuietHours() {
        let alert = NSAlert()
        alert.messageText = "Jadwal Senyap"
        alert.informativeText = "Notifikasi ditahan dari jam Mulai sampai Selesai (boleh lewat tengah malam). Badge tetap jalan."
        func picker(_ time: String, y: CGFloat) -> NSDatePicker {
            let p = NSDatePicker(frame: NSRect(x: 70, y: y, width: 110, height: 24))
            p.datePickerStyle = .textFieldAndStepper
            p.datePickerElements = .hourMinute
            let m = minutesOfDay(time) ?? 0
            p.dateValue = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            return p
        }
        func label(_ text: String, y: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.frame = NSRect(x: 0, y: y + 2, width: 64, height: 20)
            return l
        }
        let start = picker(TweakSettings.dndStart, y: 32)
        let end = picker(TweakSettings.dndEnd, y: 2)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 190, height: 60))
        view.subviews = [label("Mulai", y: 32), start, label("Selesai", y: 2), end]
        alert.accessoryView = view
        alert.addButton(withTitle: "Simpan")
        alert.addButton(withTitle: "Batal")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        TweakSettings.dndStart = hhmm(fromMinutes: minutesOfDay(start.dateValue))
        TweakSettings.dndEnd = hhmm(fromMinutes: minutesOfDay(end.dateValue))
        TweakSettings.dndEnabled = true
        current?.tweak("toast", ["msg": "Jadwal senyap \(TweakSettings.dndStart)–\(TweakSettings.dndEnd) aktif"])
        pushSilence()
        pushPanelState()
    }

    @objc func toggleAlwaysOnTop() {
        guard let w = mainWindow.window else { return }
        w.level = w.level == .floating ? .normal : .floating
        pushPanelState()
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

    // MARK: Tag

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
        field.translatesAutoresizingMaskIntoConstraints = false
        colors.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 220),
            colors.widthAnchor.constraint(equalToConstant: 220),
        ])
        alert.accessoryView = stack
        alert.addButton(withTitle: "Buat")
        alert.addButton(withTitle: "Batal")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tagNameValid(name), !acc.store.tags.tags.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
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
        pushPanelState()
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
        pushPanelState()
    }

    @objc func setTagFilter(_ sender: NSMenuItem) {
        guard let acc = current else { return }
        setFilter(sender.representedObject as? String ?? "", in: acc)
    }

    func setFilter(_ color: String, in acc: Account) {
        acc.tagFilter = color
        acc.tweak("setFilter", ["color": color])
        pushPanelState()
    }

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
        pushPanelState()
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
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
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
        // Kalau yang dihapus bukan akun yang tampil (mis. lewat panel bookmark akun lain), biarkan tampilan tetap.
        show(mainWindow.active ?? accounts[min(index, accounts.count - 1)])
        pushPanelState()
    }

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
        _ = menu("WA Desk", [
            item("About WA Desk", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide WA Desk", #selector(NSApplication.hide(_:)), "h"),
            item("Quit WA Desk", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = menu("File", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        accountsMenu.delegate = self
        accountsMenu.autoenablesItems = false
        let accountsHolder = NSMenuItem()
        accountsHolder.submenu = accountsMenu
        main.addItem(accountsHolder)
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
        tweaksMenu.delegate = self
        tweaksMenu.autoenablesItems = false
        let tweaksHolder = NSMenuItem()
        tweaksHolder.submenu = tweaksMenu
        main.addItem(tweaksHolder)
        // Menu Window: Minimize dan Selalu di Atas; tab native dimatikan (tabbingMode = .disallowed).
        NSApp.windowsMenu = menu("Window", [
            item("Minimize", #selector(NSWindow.miniaturize(_:)), "m"),
            item("Selalu di Atas", #selector(toggleAlwaysOnTop), "t", [.command, .option]),
        ])
        NSApp.mainMenu = main
    }
}


