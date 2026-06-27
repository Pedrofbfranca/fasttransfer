import Foundation
import AppKit

enum TransferStatus: Equatable {
    case queued
    case running
    case paused
    case completed
    case failed(String)
    case cancelled
    case waitingOverwrite
}

struct TransferProgress {
    var percentage: Double = 0
    var transferredBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var speed: String = ""
    var timeRemaining: String = ""
    var currentFile: String = ""
    var filesTransferred: Int = 0
    var totalFiles: Int = 0
}

@MainActor
class TransferJob: ObservableObject, Identifiable {
    let id = UUID()
    let sources: [URL]
    let destination: URL
    let startedAt: Date

    @Published var status: TransferStatus = .queued
    @Published var progress: TransferProgress = TransferProgress()
    @Published var errorMessage: String = ""
    @Published var completedAt: Date?
    @Published var totalTransferredBytes: Int64 = 0
    @Published var averageSpeed: String = ""

    var runner: RsyncRunner?

    init(sources: [URL], destination: URL) {
        self.sources = sources
        self.destination = destination
        self.startedAt = Date()
    }

    var displayName: String {
        if sources.count == 1 {
            return sources[0].lastPathComponent
        }
        return "\(sources.count) itens"
    }

    var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    func cancel() {
        runner?.cancel()
        status = .cancelled
    }

    func pause() {
        runner?.pause()
        status = .paused
    }

    func resume() {
        runner?.resume()
        status = .running
    }
}
