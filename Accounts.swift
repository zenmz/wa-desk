import Foundation

// MARK: - Accounts

enum Accounts {
    private static let key = "accounts"
    private static let defaults = UserDefaults.standard

    /// Daftar id akun. Kalau kosong atau semua invalid, buat satu akun baru.
    static func all() -> [String] {
        var ids = validAccountIDs(defaults.stringArray(forKey: key) ?? [])
        if ids.isEmpty {
            ids = [UUID().uuidString]
            defaults.set(ids, forKey: key)
        }
        return ids
    }

    static func add() -> String {
        let id = UUID().uuidString
        defaults.set(all() + [id], forKey: key)
        return id
    }

    static func remove(_ id: String) {
        defaults.set(all().filter { $0 != id }, forKey: key)
    }

    // Akun yang datanya masih harus dihapus (gagal / keburu quit). Dicoba lagi tiap launch.
    private static let pendingKey = "pendingRemoval"

    static func pendingRemoval() -> [String] {
        validAccountIDs(defaults.stringArray(forKey: pendingKey) ?? [])
    }

    static func markPendingRemoval(_ id: String) {
        defaults.set(pendingRemoval() + [id], forKey: pendingKey)
    }

    static func clearPendingRemoval(_ id: String) {
        defaults.set(pendingRemoval().filter { $0 != id }, forKey: pendingKey)
    }
}

/// Nama kustom akun. UserDefaults "accountNames": [id: nama]. nil = pakai "Akun N".
enum AccountNames {
    private static let key = "accountNames"

    static func custom(for id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id]
    }

    static func set(_ name: String?, for id: String) {
        var d = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        d[id] = name
        UserDefaults.standard.set(d, forKey: key)
    }
}
