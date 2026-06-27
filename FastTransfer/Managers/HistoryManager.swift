import Foundation

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var records: [TransferRecord] = []

    private let key = "FastTransfer.History"
    private let maxRecords = 100

    private init() {
        load()
    }

    func record(job: TransferJob) {
        let success: Bool
        var errMsg: String?

        switch job.status {
        case .completed:
            success = true
        case .failed(let e):
            success = false
            errMsg = e
        default:
            success = false
        }

        let rec = TransferRecord(
            id: UUID(),
            sourcePaths: job.sources.map { $0.path },
            destinationPath: job.destination.path,
            startedAt: job.startedAt,
            completedAt: job.completedAt ?? Date(),
            totalBytes: job.progress.transferredBytes,
            success: success,
            errorMessage: errMsg
        )

        records.insert(rec, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    func clearHistory() {
        records = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TransferRecord].self, from: data) else { return }
        records = decoded
    }
}
