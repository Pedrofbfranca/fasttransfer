import Foundation
import AppKit

@MainActor
class TransferManager: ObservableObject {
    static let shared = TransferManager()

    @Published var pendingSources: [URL] = []
    @Published var pendingDestination: URL?
    @Published var activeJobs: [TransferJob] = []
    @Published var completedJobs: [TransferJob] = []
    @Published var overwriteConflict: OverwriteConflict?

    struct OverwriteConflict {
        let job: TransferJob
        let conflictingFiles: [String]
        var completion: (OverwriteAction) -> Void
    }

    enum OverwriteAction {
        case replace, skip, cancel
    }

    private init() {}

    func addSources(_ urls: [URL]) {
        let newURLs = urls.filter { !pendingSources.contains($0) }
        pendingSources.append(contentsOf: newURLs)
    }

    func removeSources(at offsets: IndexSet) {
        pendingSources.remove(atOffsets: offsets)
    }

    func clearSources() {
        pendingSources = []
    }

    func startTransfer(sources: [URL], destination: URL, overwrite: OverwriteAction = .replace) {
        guard !sources.isEmpty else { return }

        // Verify free space
        if let freeSpace = freeSpaceAt(destination) {
            let estimatedSize = estimateSize(sources)
            if estimatedSize > freeSpace {
                let msg = "Espaço insuficiente no destino. Necessário: \(formatBytes(estimatedSize)), Disponível: \(formatBytes(freeSpace))"
                showAlert(msg)
                return
            }
        }

        // Warn if same volume
        if sameVolume(sources.first, destination) {
            let alert = NSAlert()
            alert.messageText = "Mesma unidade de armazenamento"
            alert.informativeText = "Origem e destino estão no mesmo volume. Deseja continuar?"
            alert.addButton(withTitle: "Continuar")
            alert.addButton(withTitle: "Cancelar")
            if alert.runModal() == .alertSecondButtonReturn { return }
        }

        let job = TransferJob(sources: sources, destination: destination)
        activeJobs.append(job)
        runJob(job)
    }

    private func runJob(_ job: TransferJob) {
        let runner = RsyncRunner()
        job.runner = runner
        job.status = .running

        runner.run(
            sources: job.sources,
            destination: job.destination,
            onProgress: { [weak job] progress in
                job?.progress = progress
            },
            onLog: { _ in },
            onCompletion: { [weak self, weak job] success, error in
                guard let self, let job else { return }
                job.completedAt = Date()
                if success {
                    job.status = .completed
                    job.progress.percentage = 100
                } else if error.contains("Cancelado") {
                    job.status = .cancelled
                } else {
                    job.status = .failed(error)
                    job.errorMessage = error
                }
                self.activeJobs.removeAll { $0.id == job.id }
                self.completedJobs.insert(job, at: 0)
                HistoryManager.shared.record(job: job)
            }
        )
    }

    // MARK: - Helpers

    private func freeSpaceAt(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let cap = values?.volumeAvailableCapacityForImportantUsage {
            return cap
        }
        return nil
    }

    private func estimateSize(_ urls: [URL]) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        for url in urls {
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let file as URL in enumerator {
                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    total += Int64(size)
                }
            }
        }
        return total
    }

    private func sameVolume(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        // Compare volume identifiers via FileManager
        let fm = FileManager.default
        let va = (try? fm.attributesOfItem(atPath: a.path)[.systemNumber]) as? Int
        let vb = (try? fm.attributesOfItem(atPath: b.path)[.systemNumber]) as? Int
        return va != nil && va == vb
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func showAlert(_ msg: String) {
        let alert = NSAlert()
        alert.messageText = "FastTransfer"
        alert.informativeText = msg
        alert.runModal()
    }
}
