import Cocoa
import WebKit
import UserNotifications

// MARK: - Account

/// Satu akun WhatsApp: WKWebView + data store + state Tweaks. Tidak punya window sendiri;
/// MainWindow menumpuk webView semua akun dan menampilkan satu. Akun yang tersembunyi tetap hidup.
final class Account: NSObject {
    let id: String
    let webView: WKWebView
    private(set) var unread = 0
    private var titleObservation: NSKeyValueObservation?
    let store: TweakStore
    /// Warna tag yang sedang difilter di akun ini ("" = semua). Sesi saja.
    var tagFilter = ""
    private(set) var bookmarksPanel: BookmarksPanel?
    /// Judul chat yang sedang terbuka, dilaporkan JS lewat handler "wadesk". nil = tidak ada chat.
    private(set) var openChatTitle: String?
    /// Judul halaman WhatsApp ("(3) WhatsApp"); kosong sebelum dimuat.
    private(set) var pageTitle = ""

    private var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    init(id: String) {
        self.id = id
        store = TweakStore(accountID: id)
        let cfg = WKWebViewConfiguration()
        // Data store per akun: cookie, IndexedDB, dan sesi login terisolasi.
        cfg.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: id)!)
        // UA setara Safari supaya lolos cek browser WhatsApp Web.
        cfg.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.userContentController.addUserScript(WKUserScript(
            source: notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.addUserScript(WKUserScript(
            source: tweaksScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsMagnification = true
        webView.autoresizingMask = [.width, .height]
        super.init()
        webView.configuration.userContentController.add(self, name: "notify")
        webView.configuration.userContentController.add(self, name: "wadesk")
        webView.navigationDelegate = self
        webView.uiDelegate = self

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            self.pageTitle = wv.title ?? ""
            self.unread = unreadCount(self.pageTitle)
            self.delegate?.accountTitleChanged(self)
        }
        webView.load(URLRequest(url: waHome))
    }

    deinit { titleObservation?.invalidate() }

    /// Nama tampilan: nama kustom atau "Akun N" menurut urutan di daftar akun.
    var name: String {
        let index = delegate?.accounts.firstIndex { $0 === self } ?? 0
        return accountLabel(custom: AccountNames.custom(for: id), index: index)
    }

    /// Judul window saat akun ini aktif, mis. "Kerja · (3) WhatsApp".
    var windowTitle: String { "\(name) · \(pageTitle.isEmpty ? "WhatsApp" : pageTitle)" }

    /// User sedang melihat akun ini: webView-nya yang tampil dan window utama key.
    var isBeingViewed: Bool { !webView.isHidden && webView.window?.isKeyWindow == true }

    /// Panggil `__wadesk.<fn>(...)` dengan argumen terstruktur (callAsyncJavaScript), tanpa interpolasi string.
    /// `args` urut sesuai parameter fungsi JS. Hasil `undefined`/`null` → nil.
    func tweak(_ fn: String, _ args: KeyValuePairs<String, Any> = [:], completion: ((Any?) -> Void)? = nil) {
        let call = "return await __wadesk.\(fn)(\(args.map(\.key).joined(separator: ", ")))"
        let dict = Dictionary(uniqueKeysWithValues: args.map { ($0.key, $0.value) })
        webView.callAsyncJavaScript(call, arguments: dict, in: nil, in: .page) { result in
            switch result {
            case .success(let v):
                // callAsyncJavaScript membungkus `undefined` sebagai Optional<Any>.none dan `null` sebagai NSNull; keduanya → nil.
                // Lewat AnyObject: Optional.none yang terbungkus Any dijembatani ke NSNull (`v as Any?` tidak membukanya).
                let unwrapped: Any? = (v as AnyObject) is NSNull ? nil : v
                completion?(unwrapped)
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
        tweak("setSilence", ["on": delegate?.silenced ?? false])
        delegate?.pushPanelState(to: self)
    }

    func pushTags() { tweak("setTags", ["map": tagColors(store.tags)]) }

    /// Panel bookmark akun ini. Dipakai AppDelegate.current supaya aksi menu mengenai akun yang benar saat panel key.
    func owns(_ w: NSWindow?) -> Bool { w != nil && w === bookmarksPanel }

    func showBookmarksPanel() {
        if bookmarksPanel == nil {
            let p = BookmarksPanel(store: store)
            p.onOpen = { [weak self] b in self?.open(bookmark: b) }
            bookmarksPanel = p
        }
        bookmarksPanel?.makeKeyAndOrderFront(nil)
    }

    /// Tampilkan akun ini, buka chat bookmark, lompat ke pesannya; setiap kegagalan dilaporkan lewat toast.
    func open(bookmark b: Bookmark) {
        delegate?.show(self)
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
}

// MARK: - Navigasi, download, media

extension Account: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { applyTweaks() }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { return decisionHandler(.download) }
        if let url = action.request.url, let scheme = url.scheme?.lowercased(), scheme == "mailto" || scheme == "tel" {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        if action.navigationType == .linkActivated, let url = action.request.url, isExternal(url) {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : (response.isForMainFrame ? .download : .cancel))
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        completionHandler(uniqueURL(in: dir, name: suggestedFilename) {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        FileHandle.standardError.write(Data("download gagal: \(error.localizedDescription)\n".utf8))
    }

    /// Proses WebContent mati (memory pressure, crash) → halaman kosong diam-diam. Muat ulang.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: waHome))
    }

    /// target=_blank / window.open: luar → browser default; web.whatsapp.com sendiri → muat di akun ini.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if isExternal(url) {
            NSWorkspace.shared.open(url)
        } else if url.host?.lowercased() == "web.whatsapp.com" {
            webView.load(action.request)
        }
        return nil
    }

    /// Kamera/mic untuk call. TCC macOS tetap prompt sekali (teks di Info.plist).
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == "web.whatsapp.com" ? .grant : .deny)
    }

    /// Tombol attach di WhatsApp → NSOpenPanel.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard let win = webView.window else { return completionHandler(nil) }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: win) { completionHandler($0 == .OK ? panel.urls : nil) }
    }
}

// MARK: - Notifikasi

extension Account: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == "web.whatsapp.com",
              let body = message.body as? [String: Any] else { return }
        if message.name == "wadesk" {
            if body["action"] is String {
                delegate?.handlePanelAction(body, from: self)
            } else if let title = body["chat"] as? String {
                openChatTitle = title.isEmpty ? nil : title
                delegate?.pushPanelState(to: self)
            }
            return
        }
        guard let nid = body["id"] as? String, Int(nid) != nil else { return }
        guard shouldNotify(appActive: NSApp.isActive, windowKey: isBeingViewed) else { return }
        // Jadwal senyap / senyap sementara hanya menahan banner; badge Dock tetap diperbarui lewat judul halaman.
        guard !dndActive(minutesNow: minutesOfDay(Date()), start: TweakSettings.dndStart,
                         end: TweakSettings.dndEnd, enabled: TweakSettings.dndEnabled),
              !muteActive(now: Date(), until: TweakSettings.muteUntil) else { return }

        let content = UNMutableNotificationContent()
        content.title = body["title"] as? String ?? ""
        content.body = body["body"] as? String ?? ""
        // Tanpa suara native: WhatsApp Web sudah memutar suara sendiri.
        content.userInfo = ["account": id, "nid": nid]
        let tag = body["tag"] as? String ?? ""
        // Tag sama (chat sama) → notifikasi lama diganti, tidak menumpuk.
        let identifier = tag.isEmpty ? "\(id)-\(nid)" : "\(id)-\(tag)"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

