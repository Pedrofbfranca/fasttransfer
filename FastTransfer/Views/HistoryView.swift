import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var transferManager: TransferManager

    var body: some View {
        VStack(spacing: 0) {
            if historyManager.records.isEmpty && transferManager.completedJobs.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Nenhuma transferência ainda")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    // Recent completed (current session)
                    if !transferManager.completedJobs.isEmpty {
                        Section("Sessão atual") {
                            ForEach(transferManager.completedJobs) { job in
                                CompletedJobRow(job: job)
                            }
                        }
                    }

                    // Historical records
                    if !historyManager.records.isEmpty {
                        Section("Histórico") {
                            ForEach(historyManager.records) { record in
                                HistoryRecordRow(record: record)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if !historyManager.records.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Button("Limpar histórico") {
                        historyManager.clearHistory()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(12)
                }
            }
        }
    }
}

struct CompletedJobRow: View {
    @ObservedObject var job: TransferJob

    var statusIcon: (String, Color) {
        switch job.status {
        case .completed: return ("checkmark.circle.fill", .green)
        case .cancelled: return ("xmark.circle.fill", .orange)
        case .failed: return ("exclamationmark.circle.fill", .red)
        default: return ("circle", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon.0)
                .foregroundStyle(statusIcon.1)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text("→ \(job.destination.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if case .failed(let err) = job.status {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                if let duration = job.duration {
                    let bytes = job.progress.transferredBytes
                    let avgSpeed = duration > 0 ? Double(bytes) / duration : 0
                    HStack(spacing: 6) {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("•").font(.caption2).foregroundStyle(.secondary)
                        Text(formatDuration(duration))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("•").font(.caption2).foregroundStyle(.secondary)
                        Text("média \(RsyncRunner.formatSpeed(avgSpeed))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if job.status == .completed {
                Button {
                    NSWorkspace.shared.open(job.destination)
                } label: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Abrir destino")
            }
        }
        .padding(.vertical, 4)
    }

    func formatDuration(_ d: TimeInterval) -> String {
        if d < 60 { return String(format: "%.0fs", d) }
        if d < 3600 { return String(format: "%.0fm %.0fs", d / 60, d.truncatingRemainder(dividingBy: 60)) }
        return String(format: "%.0fh %.0fm", d / 3600, (d / 60).truncatingRemainder(dividingBy: 60))
    }
}

struct HistoryRecordRow: View {
    let record: TransferRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.success ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.sourcePaths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Desconhecido")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("→ \(record.destinationPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(record.startedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(record.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: record.destinationPath))
            } label: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Abrir destino")
        }
        .padding(.vertical, 4)
    }
}
