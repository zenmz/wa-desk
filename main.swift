import Cocoa

// Entry point WA Desk. Deklarasi ada di file lain; hanya file ini yang boleh punya kode top-level.
if CommandLine.arguments.contains("--selftest") { exit(selftest()) }

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
