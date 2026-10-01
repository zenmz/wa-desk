import Foundation
import JavaScriptCore

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

    // Jadwal senyap
    check(minutesOfDay("22:00") == 1320, "minutesOfDay 22:00")
    check(minutesOfDay("7:5") == 425, "minutesOfDay 7:5")
    check(minutesOfDay("25:00") == nil, "minutesOfDay jam >23")
    check(minutesOfDay("ab") == nil, "minutesOfDay non-angka")
    check(dndActive(minutesNow: 1380, start: "22:00", end: "07:00", enabled: false) == false, "dnd disabled")
    check(dndActive(minutesNow: 600, start: "09:00", end: "17:00", enabled: true) == true, "dnd dalam rentang")
    check(dndActive(minutesNow: 1020, start: "09:00", end: "17:00", enabled: true) == false, "dnd batas akhir eksklusif")
    check(dndActive(minutesNow: 1380, start: "22:00", end: "07:00", enabled: true) == true, "dnd malam 23:00")
    check(dndActive(minutesNow: 180, start: "22:00", end: "07:00", enabled: true) == true, "dnd malam 03:00")
    check(dndActive(minutesNow: 720, start: "22:00", end: "07:00", enabled: true) == false, "dnd siang 12:00")
    check(dndActive(minutesNow: 600, start: "10:00", end: "10:00", enabled: true) == false, "dnd start==end")
    check(dndActive(minutesNow: 600, start: "x", end: "07:00", enabled: true) == false, "dnd jam invalid")

    // Bookmark dari hasil capture()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let full = bookmark(fromCapture: ["id": "true_628@c.us_ABC", "chat": "Budi", "jid": "628@c.us", "text": "halo",
                                      "time": "[10:00, 1/10/2026]", "fromMe": true], savedAt: now)
    check(full == Bookmark(id: "true_628@c.us_ABC", chat: "Budi", jid: "628@c.us", text: "halo",
                           time: "[10:00, 1/10/2026]", fromMe: true, savedAt: now), "bookmark lengkap")
    check(bookmark(fromCapture: ["chat": "Budi"], savedAt: now) == nil, "bookmark tanpa id")
    check(bookmark(fromCapture: ["id": "x", "chat": ""], savedAt: now) == nil, "bookmark chat kosong")
    check(bookmark(fromCapture: ["id": "x", "chat": "Budi", "text": String(repeating: "a", count: 400)], savedAt: now)?.text.count == 300, "bookmark teks dipotong 300")
    check(bookmark(fromCapture: ["id": "x", "chat": "Budi", "fromMe": "yes"], savedAt: now)?.fromMe == false, "bookmark fromMe bukan Bool")

    // Tag
    check(tagColorValid("#34D399") && !tagColorValid("#000000"), "tagColorValid")
    check(tagNameValid("Kerja") && tagNameValid(" a ") && !tagNameValid("  ") && !tagNameValid(String(repeating: "a", count: 25)), "tagNameValid")
    check(!tagNameValid("a\r\nb") && !tagNameValid("a\u{2028}b"), "tagNameValid CRLF")
    check(!tagNameValid("\t\t") && tagNameValid(String(repeating: "a", count: 24)), "tagNameValid tab-only dan 24 karakter")
    let td = TagData(tags: [Tag(name: "Kerja", color: "#60A5FA"), Tag(name: "Keluarga", color: "#F472B6")],
                     chats: ["Budi": ["Hilang", "Kerja", "Keluarga"], "Ani": ["Hilang"]])
    check(tagMap(td) == ["Budi": "#60A5FA"], "tagMap: tag terhapus dilewati, tag pertama menang")

    // Store: roundtrip JSON dan file korup
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wadesk-selftest-\(UUID().uuidString)")
    let s1 = TweakStore(accountID: "acc", base: tmp)
    s1.add(full!)
    s1.update { $0 = td }
    let s2 = TweakStore(accountID: "acc", base: tmp)
    check(s2.bookmarks == [full!] && s2.tags == td, "store roundtrip")
    s2.add(Bookmark(id: "true_628@c.us_ABC", chat: "Budi", jid: nil, text: "edit", time: "", fromMe: false, savedAt: now))
    check(s2.bookmarks.count == 1 && s2.bookmarks[0].text == "edit", "store add id sama mengganti")
    s2.remove(bookmarkID: "true_628@c.us_ABC")
    check(TweakStore(accountID: "acc", base: tmp).bookmarks.isEmpty, "store remove tersimpan")
    try? Data("{bukan json".utf8).write(to: tmp.appendingPathComponent("wa-desk/acc/tags.json"))
    let s3 = TweakStore(accountID: "acc", base: tmp)
    let baks = ((try? FileManager.default.contentsOfDirectory(atPath: tmp.appendingPathComponent("wa-desk/acc").path)) ?? [])
        .filter { $0.hasPrefix("tags.json.bak-") }
    check(s3.tags == TagData() && baks.count == 1, "store korup → .bak + kosong")
    try? FileManager.default.removeItem(at: tmp)

    // Skrip inject harus valid dan mendefinisikan API, juga tanpa DOM (JSContext murni).
    let ctx = JSContext()!
    ctx.exceptionHandler = { _, e in failed.append("JS exception: \(e?.toString() ?? "?")") }
    ctx.evaluateScript(tweaksScript)
    check(ctx.evaluateScript("typeof __wadesk.capture")?.toString() == "function", "JS __wadesk.capture")
    check(ctx.evaluateScript("typeof __wadesk.openChat")?.toString() == "function", "JS __wadesk.openChat")
    check(ctx.evaluateScript("typeof __wadesk.debug")?.toString() == "function", "JS __wadesk.debug")
    for fn in ["setBlur", "setHideBanner", "setCustomCSS", "setFilter", "setTags", "toast", "currentChat", "jumpTo"] {
        check(ctx.evaluateScript("typeof __wadesk.\(fn)")?.toString() == "function", "JS __wadesk.\(fn)")
    }
    if failed.isEmpty { print("selftest OK"); return 0 }
    for f in failed { FileHandle.standardError.write(Data("FAIL: \(f)\n".utf8)) }
    return 1
}

