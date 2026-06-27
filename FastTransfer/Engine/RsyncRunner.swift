import Foundation

@MainActor
class RsyncRunner {
    private var process: Process?
    private var isCancelled = false

    // Parses rsync --info=progress2 output lines
    // Format: "   1.23G  45%   98.76MB/s    0:01:23"
    private func parseProgress(_ line: String) -> TransferProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Match pattern: size  pct  speed  eta
        let pattern = #"([\d,.]+\w*)\s+(\d+)%\s+([\d,.]+\w+/s)\s+([\d:]+|--:--:--)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            return nil
        }

        func group(_ i: Int) -> String {
            let r = match.range(at: i)
            guard let range = Range(r, in: trimmed) else { return "" }
            return String(trimmed[range])
        }

        var p = TransferProgress()
        p.percentage = Double(group(2)) ?? 0
        p.speed = group(3)
        p.timeRemaining = group(4)

        // Parse transferred bytes from size string
        let sizeStr = group(1).replacingOccurrences(of: ",", with: "")
        p.transferredBytes = parseBytes(sizeStr)

        return p
    }

    private func parseBytes(_ str: String) -> Int64 {
        let s = str.uppercased()
        let multipliers: [(String, Int64)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1_024),
            ("B", 1)
        ]
        for (suffix, mult) in multipliers {
            if s.hasSuffix(suffix) {
                let num = s.dropLast(suffix.count)
                if let d = Double(num) {
                    return Int64(d * Double(mult))
                }
            }
        }
        return Int64(str.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    func run(
        sources: [URL],
        destination: URL,
        onProgress: @escaping @MainActor (TransferProgress) -> Void,
        onLog: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String) -> Void
    ) {
        isCancelled = false

        Task.detached { [weak self] in
            guard let self else { return }

            let rsyncPath = "/usr/bin/rsync"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: rsyncPath)

            var args = ["-aHAX", "--info=progress2", "--partial", "--inplace", "--human-readable", "--no-inc-recursive"]
            for source in sources {
                args.append(source.path)
            }
            args.append(destination.path + "/")

            proc.arguments = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe

            await MainActor.run { self.process = proc }

            do {
                try proc.run()
            } catch {
                await MainActor.run {
                    onCompletion(false, "Falha ao iniciar rsync: \(error.localizedDescription)")
                }
                return
            }

            // Read stdout in chunks for live progress
            let stdoutHandle = stdoutPipe.fileHandleForReading
            var buffer = Data()

            while proc.isRunning {
                let chunk = stdoutHandle.availableData
                buffer.append(chunk)

                // Process complete lines
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) ?? buffer.firstIndex(of: UInt8(ascii: "\r")) {
                    let lineData = buffer[buffer.startIndex...newline]
                    buffer = buffer[buffer.index(after: newline)...]

                    if let line = String(data: lineData, encoding: .utf8) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            let captured = trimmed
                            await MainActor.run {
                                onLog(captured)
                                if let p = self.parseProgress(captured) {
                                    onProgress(p)
                                }
                            }
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }

            // Drain remaining
            let remaining = stdoutHandle.readDataToEndOfFile()
            buffer.append(remaining)
            if let finalOutput = String(data: buffer, encoding: .utf8) {
                for line in finalOutput.components(separatedBy: .newlines) {
                    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        await MainActor.run {
                            onLog(t)
                            if let p = self.parseProgress(t) {
                                onProgress(p)
                            }
                        }
                    }
                }
            }

            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""

            proc.waitUntilExit()
            let exitCode = proc.terminationStatus

            let cancelled = await MainActor.run { self.isCancelled }

            await MainActor.run {
                if cancelled {
                    onCompletion(false, "Cancelado pelo usuário.")
                } else if exitCode == 0 {
                    onCompletion(true, "")
                } else {
                    let errMsg = stderrOutput.isEmpty ? "rsync saiu com código \(exitCode)" : stderrOutput
                    onCompletion(false, errMsg)
                }
            }
        }
    }

    nonisolated func cancel() {
        Task { @MainActor in
            isCancelled = true
            process?.terminate()
        }
    }
}
