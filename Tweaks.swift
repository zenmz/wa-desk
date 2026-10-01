import Foundation

// MARK: - Model

struct Bookmark: Codable, Equatable {
    var id: String        // data-id pesan WhatsApp, unik
    var chat: String      // judul chat saat disimpan
    var jid: String?      // 628xxx@c.us / 1203xxx@g.us, dari data-id
    var text: String      // ≤ 300 karakter
    var time: String      // "[HH:MM, D/M/YYYY]" apa adanya, atau ""
    var fromMe: Bool
    var savedAt: Date
}

struct Tag: Codable, Equatable {
    var name: String
    var color: String     // salah satu tagPalette
}

struct TagData: Codable, Equatable {
    var tags: [Tag] = []
    var chats: [String: [String]] = [:]   // judul chat → nama tag
}

// MARK: - Setting (UserDefaults, berlaku semua akun)

enum TweakSettings {
    private static let d = UserDefaults.standard
    static var blur: Bool {
        get { d.bool(forKey: "blur") }
        set { d.set(newValue, forKey: "blur") }
    }
    static var hideBanner: Bool {
        get { d.object(forKey: "hideBanner") as? Bool ?? true }
        set { d.set(newValue, forKey: "hideBanner") }
    }
    static var dndEnabled: Bool {
        get { d.bool(forKey: "dndEnabled") }
        set { d.set(newValue, forKey: "dndEnabled") }
    }
    /// Jam diubah lewat `defaults write dev.zen.wa dndStart 23:30` (tanpa UI).
    static var dndStart: String { d.string(forKey: "dndStart") ?? "22:00" }
    static var dndEnd: String { d.string(forKey: "dndEnd") ?? "07:00" }
}

// MARK: - Store per akun

/// Bookmark + tag satu akun, JSON di ~/Library/Application Support/wa-desk/<accountId>/.
final class TweakStore {
    let dir: URL
    private(set) var bookmarks: [Bookmark] = []
    private(set) var tags = TagData()
    /// Dipanggil setelah tiap simpan (panel bookmark memakai ini untuk reload).
    var onChange: (() -> Void)?

    init(accountID: String,
         base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        dir = base.appendingPathComponent("wa-desk").appendingPathComponent(accountID)
        bookmarks = load("bookmarks.json") ?? []
        tags = load("tags.json") ?? TagData()
    }

    /// Id sama → bookmark lama diganti. Terbaru di depan.
    func add(_ b: Bookmark) {
        bookmarks.removeAll { $0.id == b.id }
        bookmarks.insert(b, at: 0)
        save("bookmarks.json", bookmarks)
    }

    func remove(bookmarkID id: String) {
        bookmarks.removeAll { $0.id == id }
        save("bookmarks.json", bookmarks)
    }

    func update(_ change: (inout TagData) -> Void) {
        change(&tags)
        save("tags.json", tags)
    }

    private func load<T: Decodable>(_ name: String) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // File korup: simpan sebagai .bak supaya tidak hilang, mulai kosong.
            let bak = dir.appendingPathComponent("\(name).bak-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: bak)
            FileHandle.standardError.write(Data("\(name) korup, dipindah ke \(bak.lastPathComponent): \(error)\n".utf8))
            return nil
        }
    }

    private func save<T: Encodable>(_ name: String, _ value: T) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(value).write(to: dir.appendingPathComponent(name), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("simpan \(name) gagal: \(error)\n".utf8))
        }
        onChange?()
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
