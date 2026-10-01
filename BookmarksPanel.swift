import Cocoa

/// Tabel yang meneruskan Return/Enter dan ⌫/Delete ke closure; sisanya perilaku NSTableView biasa.
private final class KeyTable: NSTableView {
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()      // Return, Enter
        case 51, 117: onDelete?()     // ⌫, Delete
        default: super.keyDown(with: event)
        }
    }
}

/// Panel daftar bookmark satu akun. Return/dobel-klik → buka chat & lompat ke pesan; ⌫ → hapus.
final class BookmarksPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let store: TweakStore
    private let table = KeyTable()
    var onOpen: ((Bookmark) -> Void)?

    init(store: TweakStore) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow],
                   backing: .buffered, defer: false)
        title = "Bookmark"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Tetap terlihat saat app tidak aktif, tapi jangan melayang di atas window app lain.
        isFloatingPanel = false
        for (id, name, width) in [("chat", "Chat", 140.0), ("text", "Pesan", 240.0), ("time", "Waktu", 120.0)] {
            let col = NSTableColumn(identifier: .init(id))
            col.title = name
            col.width = width
            table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.tableColumns[1].resizingMask = [.autoresizingMask, .userResizingMask]   // Pesan mengambil sisa lebar
        table.tableColumns[0].resizingMask = .userResizingMask
        table.tableColumns[2].resizingMask = .userResizingMask
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.onReturn = { [weak self] in self?.openSelected() }
        table.onDelete = { [weak self] in self?.deleteSelected() }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        contentView = scroll
        center()
        store.onChange = { [weak self] in self?.table.reloadData() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.bookmarks.count }

    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        let b = store.bookmarks[row]
        switch column?.identifier.rawValue {
        case "chat": return b.chat
        case "time": return b.time
        default: return (b.fromMe ? "Saya: " : "") + b.text
        }
    }

    @objc private func openSelected() {
        guard store.bookmarks.indices.contains(table.selectedRow) else { return }
        onOpen?(store.bookmarks[table.selectedRow])
    }

    private func deleteSelected() {
        let row = table.selectedRow
        guard store.bookmarks.indices.contains(row) else { return }
        store.remove(bookmarkID: store.bookmarks[row].id)
        let next = min(row, store.bookmarks.count - 1)
        if next >= 0 { table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false) }
    }
}
