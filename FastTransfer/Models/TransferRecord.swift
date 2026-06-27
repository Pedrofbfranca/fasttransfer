import Foundation

struct TransferRecord: Codable, Identifiable {
    let id: UUID
    let sourcePaths: [String]
    let destinationPath: String
    let startedAt: Date
    let completedAt: Date
    let totalBytes: Int64
    let success: Bool
    let errorMessage: String?

    var duration: TimeInterval {
        completedAt.timeIntervalSince(startedAt)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var averageSpeedMBs: Double {
        guard duration > 0 else { return 0 }
        return Double(totalBytes) / duration / 1_048_576
    }
}
