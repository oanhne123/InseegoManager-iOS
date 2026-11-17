import Foundation
import Combine

final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    @Published private(set) var entries: [LogEntry] = []
    private let lock = NSLock()
    private var nextId: Int64 = 1
    private let maxEntries = 300

    private init() {}

    func add(_ title: String, _ detail: String) {
        lock.lock()
        let entry = LogEntry(id: nextId, timestamp: Date(), title: title, detail: detail)
        nextId += 1
        lock.unlock()

        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries.removeLast(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }

    func exportText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] \(entry.title)\n\(entry.detail)"
        }.joined(separator: "\n\n---\n\n")
    }
}
