import Cocoa
import WebKit
import UserNotifications

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, NSMenuItemValidation {
    private(set) var accounts: [AccountWindow] = []
    /// Dibangun ulang tiap dibuka (menuNeedsUpdate) supaya centang dan daftar tag selalu segar.
    private let tweaksMenu = NSMenu(title: "Tweaks")

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        GlobalHotkey.register { [weak self] in self?.toggleVisibility() }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        Accounts.pendingRemoval().forEach(purgeDataStore)
        for id in Accounts.all() { open(id: id) }
        NSApp.activate()
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
        if !win.isVisible, win.tabGroup == nil,
           let anchor = accounts.compactMap(\.window).first(where: { $0.isVisible && $0 !== win }) {
            anchor.addTabbedWindow(win, ordered: .above)
        }
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(account.webView)
    }

    /// Akun yang window-nya (atau panel bookmark-nya) sedang key; fallback akun pertama.
    var current: AccountWindow? {
        accounts.first { $0.owns(NSApp.keyWindow) } ?? accounts.first
    }

    func refreshBadge() {
        NSApp.dockTile.badgeLabel = badgeLabel(total: accounts.reduce(0) { $0 + $1.unread })
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
            NSApp.activate()
            present(account)
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
        menu.addItem(item("Jadwal Senyap \(TweakSettings.dndStart)–\(TweakSettings.dndEnd)",
                          #selector(toggleDND), on: TweakSettings.dndEnabled))
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

    @objc func toggleDND() { TweakSettings.dndEnabled.toggle() }

    @objc func toggleAlwaysOnTop() {
        guard let w = current?.window else { return }
        w.level = w.level == .floating ? .normal : .floating
    }

    /// Centang "Selalu di Atas" mengikuti window key. Item lain selalu aktif.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAlwaysOnTop) {
            item.state = current?.window?.level == .floating ? .on : .off
            return current?.window != nil
        }
        return true
    }

    /// ⌥⌘W: app aktif dengan window terlihat → sembunyikan; selain itu → aktifkan dan tampilkan akun yang tersembunyi.
    func toggleVisibility() {
        // Sembunyikan hanya kalau memang ada window akun yang terlihat; setelah Cmd+W semua window
        // tersembunyi walau app masih aktif, jadi ⌥⌘W harus menampilkan, bukan hide (yang tidak terlihat).
        let anyVisible = accounts.contains { $0.window?.isVisible == true }
        if NSApp.isActive && anyVisible {
            NSApp.hide(nil)
        } else {
            NSApp.activate()
            accounts.filter { $0.window?.isVisible == false }.forEach(present)
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

    @objc func newAccount() { open(id: Accounts.add()) }

    /// Tombol "+" di tab bar macOS memanggil ini lewat responder chain.
    @objc func newWindowForTab(_ sender: Any?) { newAccount() }

    @objc func removeAccount() {
        // Hanya akun yang windownya key; jangan tebak lewat fallback `current` saat semua tab disembunyikan.
        guard let account = accounts.first(where: { $0.window?.isKeyWindow == true }), let win = account.window else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Hapus akun ini dari WA?"
        alert.informativeText = "Sesi login dan cache akun ini di Mac ikut dihapus. Chat di HP tidak terpengaruh."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hapus")
        alert.addButton(withTitle: "Batal")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let id = account.id
        account.webView.stopLoading()
        account.webView.configuration.userContentController.removeScriptMessageHandler(forName: "notify")
        account.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wadesk")
        account.bookmarksPanel?.close()
        win.contentView = nil
        win.close()
        NSWindow.removeFrame(usingName: "win-\(id)")
        accounts.removeAll { $0 === account }
        Accounts.remove(id)
        Accounts.markPendingRemoval(id)
        // Alert menjanjikan data lokal akun dihapus: bookmark/tag ikut dihapus.
        try? FileManager.default.removeItem(at: account.store.dir)
        refreshBadge()
        // ponytail: tunda 1 detik supaya WebKit sempat melepas store; kalau masih gagal atau app keburu quit, diulang saat launch berikutnya.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.purgeDataStore(id)
        }
        if accounts.isEmpty { open(id: Accounts.all()[0]) }
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
            item("Akun Baru", #selector(newAccount), "n"),
            item("Hapus Akun Ini…", #selector(removeAccount)),
            .separator(),
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
        tweaksMenu.delegate = self
        tweaksMenu.autoenablesItems = false
        let tweaksHolder = NSMenuItem()
        tweaksHolder.submenu = tweaksMenu
        main.addItem(tweaksHolder)
        // AppKit otomatis menambah Show Next/Previous Tab, Merge All Windows di sini.
        NSApp.windowsMenu = menu("Window", [
            item("Minimize", #selector(NSWindow.miniaturize(_:)), "m"),
            item("Selalu di Atas", #selector(toggleAlwaysOnTop), "t", [.command, .option]),
        ])
        NSApp.mainMenu = main
    }
}


