import Cocoa
import WebKit
import UserNotifications

// MARK: - AccountWindow

final class AccountWindow: NSWindowController, NSWindowDelegate {
    let id: String
    let webView: WKWebView
    private(set) var unread = 0
    private var titleObservation: NSKeyValueObservation?

    init(id: String) {
        self.id = id
        let cfg = WKWebViewConfiguration()
        // Data store per akun: cookie, IndexedDB, dan sesi login terisolasi.
        cfg.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: id)!)
        // UA setara Safari supaya lolos cek browser WhatsApp Web.
        cfg.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.userContentController.addUserScript(WKUserScript(
            source: notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsMagnification = true

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: win)
        webView.configuration.userContentController.add(self, name: "notify")

        win.title = "WhatsApp"
        win.isReleasedWhenClosed = false
        win.tabbingMode = .preferred
        win.tabbingIdentifier = "wa"
        win.contentView = webView
        win.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        win.center()
        win.setFrameAutosaveName("win-\(id)")

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let title = wv.title ?? ""
            self.window?.title = title.isEmpty ? "WhatsApp" : title
            self.unread = unreadCount(title)
            (NSApp.delegate as? AppDelegate)?.refreshBadge()
        }
        webView.load(URLRequest(url: waHome))
    }

    required init?(coder: NSCoder) { fatalError("tidak dipakai") }

    deinit { titleObservation?.invalidate() }

    /// Tutup window = sembunyikan. Pesan tetap masuk. Keluar hanya lewat Cmd+Q.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}


// MARK: - Navigasi, download, media

extension AccountWindow: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
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

    /// target=_blank / window.open: luar → browser default; web.whatsapp.com sendiri → muat di tab ini.
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
        guard let win = window else { return completionHandler(nil) }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: win) { completionHandler($0 == .OK ? panel.urls : nil) }
    }
}

// MARK: - Notifikasi

extension AccountWindow: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == "web.whatsapp.com",
              let body = message.body as? [String: Any],
              let nid = body["id"] as? String, Int(nid) != nil else { return }
        guard shouldNotify(appActive: NSApp.isActive, windowKey: window?.isKeyWindow ?? false) else { return }

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

