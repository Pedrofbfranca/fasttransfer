import Foundation
import UserNotifications

@MainActor
class RsyncRunner {
    private var isCancelled = false
    private var isPaused = false
    private var process: Process?

    func run(
        sources: [URL],
        destination: URL,
        onProgress: @escaping @MainActor (TransferProgress) -> Void,
        onLog: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String) -> Void
    ) {
        isCancelled = false
        isPaused = false

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

    func pause() { isPaused = true }
    func resume() { isPaused = false }

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
                        await MainActor.run { onLog(line); if let p { onProgress(p) } }
                    }
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
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

    // MARK: - Native parallel copy

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
            var allFiles: [(src: URL, dst: URL, size: Int64)] = []
            var totalBytes: Int64 = 0

            for source in sources {
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
                        let size = Int64(vals?.fileSize ?? 0)
                        allFiles.append((src: file, dst: dstFile, size: size))
                        totalBytes += size
                    }
                } else {
                    let size = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                    allFiles.append((src: source, dst: destination.appendingPathComponent(source.lastPathComponent), size: size))
                    totalBytes += size
                }
            }

            // Parallel copy with up to 8 concurrent tasks
            let copiedBytes = ActorCounter()
            let copiedFiles = ActorIntCounter()
            let errors = ActorStringList()
            let startTime = Date()
            // Moving average for speed (last 5 samples)
            let speedSampler = SpeedSampler()

            await withTaskGroup(of: Void.self) { group in
                let semaphore = AsyncSemaphore(limit: 8)

                for pair in allFiles {
                    await semaphore.wait()

                    group.addTask { [weak self] in
                        defer { Task { await semaphore.signal() } }
                        guard let self else { return }

                        // Check cancelled
                        let cancelled = await MainActor.run { self.isCancelled }
                        if cancelled { return }

                        // Wait if paused
                        while await MainActor.run(body: { self.isPaused }) {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }

                        // Create parent dir
                        let parent = pair.dst.deletingLastPathComponent()
                        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)

                        // Skip if identical (resume support)
                        if fm.fileExists(atPath: pair.dst.path) {
                            let srcMod = (try? pair.src.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                            let dstMod = (try? pair.dst.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                            let dstSize = Int64((try? pair.dst.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                            if dstSize == pair.size && srcMod == dstMod {
                                // Already copied, skip
                                await copiedBytes.add(pair.size)
                                await copiedFiles.increment()
                                return
                            }
                            try? fm.removeItem(at: pair.dst)
                        }

                        do {
                            try fm.copyItem(at: pair.src, to: pair.dst)
                            await copiedBytes.add(pair.size)
                            await copiedFiles.increment()
                        } catch {
                            await errors.append(error.localizedDescription)
                        }

                        // Report progress
                        let copied = await copiedBytes.value
                        let files = await copiedFiles.value
                        let elapsed = Date().timeIntervalSince(startTime)
                        let instantSpeed = elapsed > 0 ? Double(copied) / elapsed : 0
                        await speedSampler.add(instantSpeed)
                        let smoothSpeed = await speedSampler.average()
                        let remaining = smoothSpeed > 0 ? Double(totalBytes - copied) / smoothSpeed : 0
                        let pct = totalBytes > 0 ? Double(copied) / Double(totalBytes) * 100 : 0

                        var p = TransferProgress()
                        p.percentage = min(pct, 99.9)
                        p.transferredBytes = copied
                        p.totalBytes = totalBytes
                        p.filesTransferred = files
                        p.totalFiles = allFiles.count
                        p.speed = RsyncRunner.formatSpeed(smoothSpeed)
                        p.timeRemaining = RsyncRunner.formatTime(remaining)
                        p.currentFile = pair.src.lastPathComponent

                        let pCopy = p
                        let name = pair.src.lastPathComponent
                        await MainActor.run {
                            onLog("✓ \(name)")
                            onProgress(pCopy)
                        }
                    }
                }
            }

            let cancelled = await MainActor.run { self.isCancelled }
            let errorList = await errors.all()
            let finalBytes = await copiedBytes.value

            // Send notification
            if !cancelled {
                await self.sendNotification(
                    title: "Transferência concluída",
                    body: "\(RsyncRunner.formatBytes(finalBytes)) copiados com sucesso."
                )
            }

            await MainActor.run {
                if cancelled { onCompletion(false, "Cancelado pelo usuário.") }
                else if errorList.isEmpty { onCompletion(true, "") }
                else { onCompletion(false, errorList.joined(separator: "\n")) }
            }
        }
    }

    // MARK: - Notification

    private func sendNotification(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(req)
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
            if s.hasSuffix(suffix), let d = Double(s.dropLast(suffix.count)) { return Int64(d * Double(mult)) }
        }
        return Int64(str) ?? 0
    }

    nonisolated static func formatSpeed(_ bps: Double) -> String {
        if bps > 1_073_741_824 { return String(format: "%.1f GB/s", bps / 1_073_741_824) }
        if bps > 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
        if bps > 1_024 { return String(format: "%.0f KB/s", bps / 1_024) }
        return String(format: "%.0f B/s", bps)
    }

    nonisolated static func formatTime(_ s: Double) -> String {
        if s <= 0 || s.isInfinite || s.isNaN { return "--:--:--" }
        let t = Int(s)
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    nonisolated static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    nonisolated func cancel() {
        Task { @MainActor in isCancelled = true; process?.terminate() }
    }
}

// MARK: - Concurrency helpers

actor ActorCounter {
    private(set) var value: Int64 = 0
    func add(_ n: Int64) { value += n }
}

actor ActorIntCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

actor ActorStringList {
    private var items: [String] = []
    func append(_ s: String) { items.append(s) }
    func all() -> [String] { items }
}

actor SpeedSampler {
    private var samples: [Double] = []
    private let maxSamples = 8
    func add(_ v: Double) {
        samples.append(v)
        if samples.count > maxSamples { samples.removeFirst() }
    }
    func average() -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }
}

actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { count = limit }
    func wait() async {
        if count > 0 { count -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        if waiters.isEmpty { count += 1 }
        else { waiters.removeFirst().resume() }
    }
}
