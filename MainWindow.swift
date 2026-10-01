import Cocoa

// MARK: - MainWindow

/// Satu window untuk semua akun: webView tiap akun ditumpuk di container, hanya yang aktif terlihat.
final class MainWindow: NSWindowController, NSWindowDelegate {
    private let container = NSView()
    private(set) var active: Account?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: win)
        win.title = "WhatsApp"
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.contentView = container
        win.delegate = self
        win.center()
        win.setFrameAutosaveName("main")
    }

    required init?(coder: NSCoder) { fatalError("tidak dipakai") }

    /// Tumpuk webView akun di container, tersembunyi, tetap memuat halaman.
    func attach(_ account: Account) {
        account.webView.frame = container.bounds
        account.webView.isHidden = true
        container.addSubview(account.webView)
    }

    func detach(_ account: Account) {
        account.webView.removeFromSuperview()
        if active === account { active = nil }
    }

    /// Tampilkan akun ini; akun lain tetap hidup tapi tersembunyi.
    func show(_ account: Account) {
        for v in container.subviews { v.isHidden = v !== account.webView }
        account.webView.frame = container.bounds
        active = account
        refreshTitle()
        window?.makeFirstResponder(account.webView)
    }

    func refreshTitle() { window?.title = active?.windowTitle ?? "WhatsApp" }

    /// Tutup window = sembunyikan. Pesan tetap masuk. Keluar hanya lewat Cmd+Q.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
