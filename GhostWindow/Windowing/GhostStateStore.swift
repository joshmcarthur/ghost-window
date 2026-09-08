import Foundation

/// Persists original opacity so a relaunch can restore windows after a crash.
final class GhostStateStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var records: [UInt32: GhostedWindowRecord] = [:]

    init(fileManager: FileManager = .default, url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            let directory = root.appendingPathComponent("GhostWindow", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.url = directory.appendingPathComponent("ghosted-windows.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    var all: [GhostedWindowRecord] {
        Array(records.values)
    }

    func record(for windowID: UInt32) -> GhostedWindowRecord? {
        records[windowID]
    }

    func isGhosted(_ windowID: UInt32) -> Bool {
        records[windowID] != nil
    }

    func save(_ record: GhostedWindowRecord) {
        records[record.window.windowID] = record
        persist()
    }

    func remove(_ windowID: UInt32) {
        records.removeValue(forKey: windowID)
        persist()
    }

    func removeAll() {
        records.removeAll()
        persist()
    }

    func pruneMissing(exists: (UInt32) -> Bool) {
        let gone = records.keys.filter { !exists($0) }
        guard !gone.isEmpty else { return }
        gone.forEach { records.removeValue(forKey: $0) }
        persist()
        for windowID in gone {
            GhostLogger.log("Window disappeared, clearing state: \(windowID)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? decoder.decode([GhostedWindowRecord].self, from: data) {
            records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.window.windowID, $0) })
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(Array(records.values))
            try data.write(to: url, options: .atomic)
        } catch {
            GhostLogger.log("Failed to persist ghost state: \(error.localizedDescription)")
        }
    }
}
