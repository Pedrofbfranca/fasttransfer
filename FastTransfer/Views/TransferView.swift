import SwiftUI
import AppKit

struct TransferView: View {
    @EnvironmentObject var transferManager: TransferManager
    @EnvironmentObject var favoritesManager: FavoritesManager
    @State private var destination: URL?
    @State private var showJobSheet: TransferJob?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Source drop zone
                    SourceDropZone(
                        sources: $transferManager.pendingSources,
                        isTargeted: $isDropTargeted
                    )

                    // Source list
                    if !transferManager.pendingSources.isEmpty {
                        SourceListView(sources: $transferManager.pendingSources)
                    }

                    // Destination
                    DestinationPickerView(destination: $destination)

                    // Favorites
                    FavoritesBarView(destination: $destination)

                    // Active jobs
                    if !transferManager.activeJobs.isEmpty {
                        ActiveJobsView()
                    }
                }
                .padding(20)
            }

            Divider()

            // Bottom toolbar
            HStack(spacing: 12) {
                Button("Limpar") {
                    transferManager.clearSources()
                }
                .disabled(transferManager.pendingSources.isEmpty)

                Spacer()

                if let dest = destination {
                    Button {
                        favoritesManager.add(url: dest)
                    } label: {
                        Label("Favoritar destino", systemImage: "star")
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    guard let dest = destination, !transferManager.pendingSources.isEmpty else { return }
                    transferManager.startTransfer(sources: transferManager.pendingSources, destination: dest)
                    transferManager.clearSources()
                } label: {
                    Label("Transferir", systemImage: "bolt.fill")
                        .frame(minWidth: 100)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(transferManager.pendingSources.isEmpty || destination == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
        }
    }
}

// MARK: - Source Drop Zone

struct SourceDropZone: View {
    @Binding var sources: [URL]
    @Binding var isTargeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .frame(height: 140)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                )

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                Text("Arraste arquivos ou pastas aqui")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Selecionar manualmente…") {
                    selectManually()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                for provider in providers {
                    if let url = await loadURL(from: provider) {
                        if !sources.contains(url) {
                            sources.append(url)
                        }
                    }
                }
            }
            return true
        }
    }

    private func selectManually() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            for url in panel.urls where !sources.contains(url) {
                sources.append(url)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Source List

struct SourceListView: View {
    @Binding var sources: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Origem")
                    .font(.headline)
                Spacer()
                Text("\(sources.count) \(sources.count == 1 ? "item" : "itens")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 1) {
                ForEach(Array(sources.enumerated()), id: \.element) { idx, url in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            sources.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
    }
}

// MARK: - Destination Picker

struct DestinationPickerView: View {
    @Binding var destination: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destino")
                .font(.headline)

            HStack(spacing: 10) {
                if let dest = destination {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: dest.path))
                        .resizable()
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dest.lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(dest.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Alterar") { pickDestination() }
                        .buttonStyle(.borderless)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Nenhum destino selecionado")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Selecionar…") { pickDestination() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Selecionar"
        if panel.runModal() == .OK {
            destination = panel.url
        }
    }
}

// MARK: - Favorites Bar

struct FavoritesBarView: View {
    @Binding var destination: URL?
    @EnvironmentObject var favoritesManager: FavoritesManager

    var body: some View {
        if !favoritesManager.favorites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Favoritos")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(favoritesManager.favorites) { fav in
                            FavoriteChip(favorite: fav, isSelected: fav.url == destination) {
                                destination = fav.url
                            } onDelete: {
                                favoritesManager.remove(id: fav.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct FavoriteChip: View {
    let favorite: FavoriteDestination
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            if let url = favorite.url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(favorite.name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3)))
        .clipShape(Capsule())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Active Jobs

struct ActiveJobsView: View {
    @EnvironmentObject var transferManager: TransferManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Em progresso")
                .font(.headline)
            ForEach(transferManager.activeJobs) { job in
                ActiveJobRow(job: job)
            }
        }
    }
}

struct ActiveJobRow: View {
    @ObservedObject var job: TransferJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("→ \(job.destination.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if job.status == .paused {
                    Button("Retomar") { job.resume() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                        .font(.caption)
                } else {
                    Button("Pausar") { job.pause() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Button("Cancelar") { job.cancel() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            ProgressView(value: job.progress.percentage / 100)
                .progressViewStyle(.linear)
                .opacity(job.status == .paused ? 0.5 : 1)

            HStack {
                if job.status == .paused {
                    Text("Pausado")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if !job.progress.speed.isEmpty {
                    Text(job.progress.speed)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !job.progress.currentFile.isEmpty {
                    Text(job.progress.currentFile)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !job.progress.timeRemaining.isEmpty && job.progress.timeRemaining != "--:--:--" {
                    Text("Restante: \(job.progress.timeRemaining)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "%.0f%%", job.progress.percentage))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Files counter
            if job.progress.totalFiles > 0 {
                Text("\(job.progress.filesTransferred) de \(job.progress.totalFiles) arquivos")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }
}
