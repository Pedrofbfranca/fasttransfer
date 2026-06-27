import Foundation

// Copies files using FileManager with real-time progress tracking.
// Falls back to GNU rsync if available via Homebrew.
@MainActor
class RsyncRunner {
    private var isCancelled = false
    private var process: Process?

    func run(
        sources: [URL],
        destination: URL,
        onProgress: @escaping @MainActor (TransferProgress) -> Void,
        onLog: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String) -> Void
    ) {
        isCancelled = false

        // Try GNU rsync first (Homebrew)
        let gnuRsync = ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]
            .first { FileManager.default.fileExists(atPath: $0) }

        if let rsyncPath = gnuRsync {
            runRsync(rsyncPath: rsyncPath, sources: sources, destination: destination,
                     onProgress: onProgress, onLog: onLog, onCompletion: onCompletion)
        } else {
            runNativeCopy(sources: sources, destination: destination,
                          onProgress: onProgress, onLog: onLog, onCompletion: onCompletion)
        }
    }

    // MARK: - GNU rsync

    private func runRsync(
        rsyncPath: String, sources: [URL], destination: URL,
        onProgress: @escaping @MainActor (TransferProgress) -> Void,
        onLog: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String) -> Void
    ) {
        Task.detached { [weak self] in
            guard let self else { return }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: rsyncPath)
            var args = ["-aH", "--info=progress2", "--partial", "--inplace", "--human-readable"]
            for source in sources { args.append(source.path) }
            args.append(destination.path + "/")
            proc.arguments = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe

            await MainActor.run { self.process = proc }

            do { try proc.run() } catch {
                await MainActor.run { onCompletion(false, error.localizedDescription) }
                return
            }

            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()

            while proc.isRunning {
                let chunk = handle.availableData
                buffer.append(chunk)
                while let idx = buffer.firstIndex(of: UInt8(ascii: "\r")) ?? buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buffer[buffer.startIndex...idx]
                    buffer = buffer[buffer.index(after: idx)...]
                    if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                        let p = self.parseProgress2(line)
                        await MainActor.run {
                            onLog(line)
                            if let p { onProgress(p) }
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            let remaining = handle.readDataToEndOfFile()
            if let s = String(data: remaining, encoding: .utf8) {
                for line in s.components(separatedBy: .newlines) {
                    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty, let p = self.parseProgress2(t) {
                        await MainActor.run { onProgress(p) }
                    }
                }
            }

            let errStr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            proc.waitUntilExit()

            let cancelled = await MainActor.run { self.isCancelled }
            await MainActor.run {
                if cancelled { onCompletion(false, "Cancelado.") }
                else if proc.terminationStatus == 0 { onCompletion(true, "") }
                else { onCompletion(false, errStr.isEmpty ? "Erro rsync \(proc.terminationStatus)" : errStr) }
            }
        }
    }

    // MARK: - Native copy (FileManager)

    private func runNativeCopy(
        sources: [URL], destination: URL,
        onProgress: @escaping @MainActor (TransferProgress) -> Void,
        onLog: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String) -> Void
    ) {
        Task.detached { [weak self] in
            guard let self else { return }

            let fm = FileManager.default

            // Enumerate all files
            var allFiles: [(src: URL, dst: URL)] = []
            var totalBytes: Int64 = 0

            for source in sources {
                let destDir = destination.appendingPathComponent(source.lastPathComponent)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: source.path, isDirectory: &isDir)

                if isDir.boolValue {
                    guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { continue }
                    let items = enumerator.allObjects.compactMap { $0 as? URL }
                    for file in items {
                        let vals = try? file.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                        if vals?.isDirectory == true { continue }
                        let rel = file.path.replacingOccurrences(of: source.deletingLastPathComponent().path + "/", with: "")
                        let dstFile = destination.appendingPathComponent(rel)
                        allFiles.append((src: file, dst: dstFile))
                        totalBytes += Int64(vals?.fileSize ?? 0)
                    }
                } else {
                    let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    allFiles.append((src: source, dst: destDir))
                    totalBytes += Int64(size)
                }
            }

            var copiedBytes: Int64 = 0
            var copiedFiles = 0
            var errors: [String] = []
            let startTime = Date()

            for pair in allFiles {
                let cancelled = await MainActor.run { self.isCancelled }
                if cancelled { break }

                // Create parent dir
                let parent = pair.dst.deletingLastPathComponent()
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true)

                // Remove existing if needed
                if fm.fileExists(atPath: pair.dst.path) {
                    try? fm.removeItem(at: pair.dst)
                }

                do {
                    try fm.copyItem(at: pair.src, to: pair.dst)
                    let size = Int64((try? pair.src.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                    copiedBytes += size
                    copiedFiles += 1

                    let elapsed = Date().timeIntervalSince(startTime)
                    let speedBps = elapsed > 0 ? Double(copiedBytes) / elapsed : 0
                    let remaining = speedBps > 0 ? Double(totalBytes - copiedBytes) / speedBps : 0
                    let pct = totalBytes > 0 ? Double(copiedBytes) / Double(totalBytes) * 100 : 0

                    var p = TransferProgress()
                    p.percentage = pct
                    p.transferredBytes = copiedBytes
                    p.totalBytes = totalBytes
                    p.filesTransferred = copiedFiles
                    p.totalFiles = allFiles.count
                    p.speed = RsyncRunner.formatSpeed(speedBps)
                    p.timeRemaining = RsyncRunner.formatTime(remaining)
                    p.currentFile = pair.src.lastPathComponent

                    let pCopy = p
                    let fileName = pair.src.lastPathComponent
                    await MainActor.run {
                        onLog("✓ \(fileName)")
                        onProgress(pCopy)
                    }
                } catch {
                    errors.append(error.localizedDescription)
                }
            }

            let cancelled = await MainActor.run { self.isCancelled }
            let errorsCopy = errors
            await MainActor.run {
                if cancelled {
                    onCompletion(false, "Cancelado pelo usuário.")
                } else if errorsCopy.isEmpty {
                    onCompletion(true, "")
                } else {
                    onCompletion(false, errorsCopy.joined(separator: "\n"))
                }
            }
        }
    }

    // MARK: - Helpers

    private nonisolated func parseProgress2(_ line: String) -> TransferProgress? {
        let pattern = #"([\d,.]+\w*)\s+(\d+)%\s+([\d,.]+\w+/s)\s+([\d:]+|--:--:--)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }

        func g(_ i: Int) -> String {
            guard let r = Range(match.range(at: i), in: line) else { return "" }
            return String(line[r])
        }

        var p = TransferProgress()
        p.percentage = Double(g(2)) ?? 0
        p.speed = g(3)
        p.timeRemaining = g(4)
        p.transferredBytes = parseBytes(g(1).replacingOccurrences(of: ",", with: ""))
        return p
    }

    private nonisolated func parseBytes(_ str: String) -> Int64 {
        let s = str.uppercased()
        for (suffix, mult) in [("TB", Int64(1_099_511_627_776)), ("GB", 1_073_741_824), ("MB", 1_048_576), ("KB", 1_024), ("B", 1)] {
            if s.hasSuffix(suffix), let d = Double(s.dropLast(suffix.count)) {
                return Int64(d * Double(mult))
            }
        }
        return Int64(str) ?? 0
    }

    nonisolated static func formatSpeed(_ bps: Double) -> String {
        if bps > 1_073_741_824 { return String(format: "%.1f GB/s", bps / 1_073_741_824) }
        if bps > 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
        if bps > 1_024 { return String(format: "%.0f KB/s", bps / 1_024) }
        return String(format: "%.0f B/s", bps)
    }

    nonisolated static func formatTime(_ seconds: Double) -> String {
        if seconds <= 0 || seconds.isInfinite || seconds.isNaN { return "--:--:--" }
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    nonisolated func cancel() {
        Task { @MainActor in
            isCancelled = true
            process?.terminate()
        }
    }
}
