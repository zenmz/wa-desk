import Foundation

// MARK: - Selftest

func selftest() -> Int32 {
    var failed: [String] = []
    func check(_ ok: Bool, _ name: String) { if !ok { failed.append(name) } }

    check(unreadCount("(3) WhatsApp") == 3, "unreadCount 3")
    check(unreadCount("(12) WhatsApp") == 12, "unreadCount 12")
    check(unreadCount("WhatsApp") == 0, "unreadCount none")
    check(unreadCount("") == 0, "unreadCount empty")
    check(unreadCount("(x) WhatsApp") == 0, "unreadCount non-numeric")

    let good = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    check(validAccountIDs([good, "abc", ""]) == [good], "validAccountIDs filters")
    check(validAccountIDs([]).isEmpty, "validAccountIDs empty")

    check(badgeLabel(total: 0) == nil, "badgeLabel nil saat 0")
    check(badgeLabel(total: 7) == "7", "badgeLabel 7")

    check(isExternal(URL(string: "https://web.whatsapp.com/")!) == false, "isExternal wa")
    check(isExternal(URL(string: "https://example.com/x")!) == true, "isExternal other")
    check(isExternal(URL(string: "https://wa.me/628")!) == true, "isExternal wa.me")
    check(isExternal(URL(string: "about:blank")!) == false, "isExternal no host")

    let dir = URL(fileURLWithPath: "/tmp/wa-selftest")
    let taken: Set<String> = ["a.jpg", "a (1).jpg", "noext"]
    let exists: (URL) -> Bool = { taken.contains($0.lastPathComponent) }
    check(uniqueURL(in: dir, name: "b.jpg", exists: exists).lastPathComponent == "b.jpg", "uniqueURL free")
    check(uniqueURL(in: dir, name: "a.jpg", exists: exists).lastPathComponent == "a (2).jpg", "uniqueURL suffix")
    check(uniqueURL(in: dir, name: "noext", exists: exists).lastPathComponent == "noext (1)", "uniqueURL no ext")
    check(isExternal(URL(string: "https://Web.WhatsApp.com/")!) == false, "isExternal case-insensitive host")
    check(uniqueURL(in: dir, name: "../../evil.jpg", exists: exists).lastPathComponent == "evil.jpg", "uniqueURL strips path")
    check(uniqueURL(in: dir, name: "../../evil.jpg", exists: exists).deletingLastPathComponent().path == dir.path, "uniqueURL stays in dir")
    check(uniqueURL(in: dir, name: "", exists: exists).lastPathComponent == "download", "uniqueURL empty name")
    check(isExternal(URL(string: "file://localhost/Applications/Calculator.app")!) == false, "isExternal file scheme")
    check(isExternal(URL(string: "HTTPS://EXAMPLE.COM/")!) == true, "isExternal uppercase scheme")
    check(uniqueURL(in: dir, name: "..", exists: exists).lastPathComponent == "download", "uniqueURL dotdot")
    check(uniqueURL(in: dir, name: "/", exists: exists).lastPathComponent == "download", "uniqueURL slash")
    check(shouldNotify(appActive: true, windowKey: true) == false, "shouldNotify ditekan saat dilihat")
    check(shouldNotify(appActive: true, windowKey: false) == true, "shouldNotify tab lain")
    check(shouldNotify(appActive: false, windowKey: true) == true, "shouldNotify app background")

    if failed.isEmpty { print("selftest OK"); return 0 }
    for f in failed { FileHandle.standardError.write(Data("FAIL: \(f)\n".utf8)) }
    return 1
}

