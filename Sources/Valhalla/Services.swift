import CryptoKit
import Foundation

struct CommandResult {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }
}

enum ValhallaError: LocalizedError {
    case backendMissing
    case commandFailed(String)
    case unsafeArchiveEntry(String)
    case noPayloads
    case invalidPIT
    case mappingFailed([String])

    var errorDescription: String? {
        switch self {
        case .backendMissing:
            return "Heimdall was not found. Install it with Homebrew before flashing."
        case .commandFailed(let message):
            return message
        case .unsafeArchiveEntry(let entry):
            return "The archive contains an unsafe path: \(entry)"
        case .noPayloads:
            return "No flashable payloads were found."
        case .invalidPIT:
            return "The PIT could not be parsed or contained no partitions."
        case .mappingFailed(let payloads):
            return "These payloads could not be matched to the device PIT: \(payloads.joined(separator: ", "))"
        }
    }
}

enum ShellRunner {
    static func run(_ executable: URL, _ arguments: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: CommandResult(status: process.terminationStatus, output: output))
                } catch {
                    continuation.resume(returning: CommandResult(status: -1, output: error.localizedDescription))
                }
            }
        }
    }
}

enum BackendLocator {
    static let candidates = [
        "/opt/homebrew/bin/heimdall",
        "/usr/local/bin/heimdall",
        "/usr/bin/heimdall"
    ]

    static var heimdall: URL? {
        candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var lz4: URL? {
        [
            "/opt/homebrew/bin/lz4",
            "/usr/local/bin/lz4",
            "/usr/bin/lz4"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

struct InspectionResult {
    let entries: [String]
    let detail: String
}

enum FirmwareInspector {
    static func inspect(_ url: URL) async throws -> InspectionResult {
        let filename = url.lastPathComponent.lowercased()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValhallaError.commandFailed("The selected file no longer exists.")
        }

        if filename.contains(".tar") {
            let result = await ShellRunner.run(
                URL(fileURLWithPath: "/usr/bin/tar"),
                ["-tf", url.path]
            )
            guard result.succeeded else {
                throw ValhallaError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let entries = result.output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.hasSuffix("/") && !$0.hasPrefix("._") && !$0.contains("/._") }

            for entry in entries where entry.hasPrefix("/") || entry.split(separator: "/").contains("..") {
                throw ValhallaError.unsafeArchiveEntry(entry)
            }

            let verbose = await ShellRunner.run(
                URL(fileURLWithPath: "/usr/bin/tar"),
                ["-tvf", url.path]
            )
            guard verbose.succeeded else {
                throw ValhallaError.commandFailed("The archive metadata could not be inspected.")
            }
            let containsLinks = verbose.output
                .split(whereSeparator: \.isNewline)
                .contains { line in
                    guard let marker = line.first else { return false }
                    return marker == "l" || marker == "h"
                }
            if containsLinks {
                throw ValhallaError.commandFailed("Archives containing symbolic or hard links are blocked.")
            }

            let payloads = entries.filter(isPotentialPayload)
            guard !payloads.isEmpty else { throw ValhallaError.noPayloads }

            if filename.hasSuffix(".md5") {
                let checksum = await TarMD5Verifier.verify(url)
                switch checksum {
                case .verified:
                    return InspectionResult(entries: entries, detail: "MD5 verified • \(payloads.count) payloads")
                case .mismatch:
                    throw ValhallaError.commandFailed("The appended MD5 checksum does not match this archive.")
                case .missing:
                    throw ValhallaError.commandFailed("This .tar.md5 file has no valid MD5 trailer.")
                case .unavailable(let message):
                    throw ValhallaError.commandFailed(message)
                }
            }

            return InspectionResult(entries: entries, detail: "Readable archive • \(payloads.count) payloads")
        }

        guard isPotentialPayload(url.lastPathComponent) else {
            throw ValhallaError.commandFailed("Choose a .tar.md5, .tar, .img, .bin, .lz4, .elf, or .mbn file.")
        }
        return InspectionResult(entries: [url.lastPathComponent], detail: "Single payload")
    }

    static func isPotentialPayload(_ path: String) -> Bool {
        let value = path.lowercased()
        let extensions = [".img", ".bin", ".lz4", ".elf", ".mbn"]
        return extensions.contains(where: value.hasSuffix)
            || value.contains(".img.")
            || value.contains(".bin.")
    }

}

enum TarMD5Result: Equatable {
    case verified
    case mismatch
    case missing
    case unavailable(String)
}

enum TarMD5Verifier {
    static func verify(_ url: URL) async -> TarMD5Result {
        await Task.detached(priority: .userInitiated) {
            verifySynchronously(url)
        }.value
    }

    static func verifySynchronously(_ url: URL) -> TarMD5Result {
        guard
            let handle = try? FileHandle(forReadingFrom: url),
            let size = try? handle.seekToEnd(),
            size >= 32
        else {
            return .missing
        }

        do {
            let tailOffset: UInt64 = size > 128 ? size - 128 : 0
            try handle.seek(toOffset: tailOffset)
            let tail = try handle.readToEnd() ?? Data()
            let trailer = parseTrailer(tail, absoluteOffset: tailOffset)
            guard let trailer else {
                try handle.close()
                return .missing
            }

            try handle.seek(toOffset: 0)
            var remaining = trailer.payloadLength
            var hasher = Insecure.MD5()
            let chunkSize = 4 * 1_024 * 1_024
            while remaining > 0 {
                let requested = Int(min(UInt64(chunkSize), remaining))
                guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else {
                    break
                }
                hasher.update(data: chunk)
                remaining -= UInt64(chunk.count)
            }
            try handle.close()

            let actual = hasher.finalize()
                .map { String(format: "%02x", $0) }
                .joined()
            return actual == trailer.expected.lowercased() ? .verified : .mismatch
        } catch {
            try? handle.close()
            return .unavailable(error.localizedDescription)
        }
    }

    private static func parseTrailer(
        _ tail: Data,
        absoluteOffset: UInt64
    ) -> (expected: String, payloadLength: UInt64)? {
        let bytes = [UInt8](tail)
        var end = bytes.count
        while end > 0 && [9, 10, 13, 32].contains(bytes[end - 1]) {
            end -= 1
        }
        guard end >= 32 else { return nil }

        let start = end - 32
        let digestBytes = Array(bytes[start..<end])
        guard digestBytes.allSatisfy(isASCIIHex) else { return nil }
        guard let expected = String(bytes: digestBytes, encoding: .ascii) else { return nil }
        return (expected, absoluteOffset + UInt64(start))
    }

    private static func isASCIIHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }
}

enum PITParser {
    static func parse(_ output: String) -> [PITPartition] {
        var partitions: [PITPartition] = []
        var identifier: Int?
        var name: String?
        var filename: String?

        func finishBlock() {
            if let name, !name.isEmpty {
                partitions.append(PITPartition(identifier: identifier, name: name, flashFilename: filename))
            }
            identifier = nil
            name = nil
            filename = nil
        }

        for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("--- Entry #") {
                finishBlock()
            } else if line.hasPrefix("Partition Name:") {
                name = value(afterColonIn: line)
            } else if line.hasPrefix("Partition Identifier:") {
                identifier = Int(value(afterColonIn: line))
            } else if line.hasPrefix("Flash Filename:") {
                filename = value(afterColonIn: line)
            }
        }
        finishBlock()
        return partitions
    }

    private static func value(afterColonIn line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
}

enum FilenameNormalizer {
    private static let removableSuffixes = [
        ".lz4", ".img", ".bin", ".elf", ".mbn", ".ext4", ".sparse"
    ]

    static func normalize(_ filename: String) -> String {
        var value = URL(fileURLWithPath: filename).lastPathComponent.lowercased()
        var removed = true
        while removed {
            removed = false
            for suffix in removableSuffixes where value.hasSuffix(suffix) {
                value.removeLast(suffix.count)
                removed = true
                break
            }
        }
        return value
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}

enum FlashPlanner {
    static func create(payloads: [URL], partitions: [PITPartition], stagingDirectory: URL) -> FlashPlan {
        var mappings: [FlashMapping] = []
        var unmapped: [URL] = []
        var usedNames: [String: Int] = [:]

        for payload in payloads {
            let normalizedPayload = FilenameNormalizer.normalize(payload.lastPathComponent)
            let matches = partitions.filter { partition in
                let partitionName = FilenameNormalizer.normalize(partition.name)
                let flashName = partition.flashFilename.map(FilenameNormalizer.normalize)
                return normalizedPayload == flashName || normalizedPayload == partitionName
            }

            guard matches.count == 1, let match = matches.first else {
                unmapped.append(payload)
                continue
            }

            usedNames[match.name, default: 0] += 1
            mappings.append(FlashMapping(partition: match, payloadURL: payload))
        }

        let duplicates = usedNames
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()

        return FlashPlan(
            mappings: mappings,
            stagingDirectory: stagingDirectory,
            unmappedPayloads: unmapped,
            duplicatePartitions: duplicates
        )
    }
}

enum FirmwareStager {
    static func stage(_ selections: [FirmwareSelection]) async throws -> (directory: URL, payloads: [URL]) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Valhalla", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        for selection in selections {
            let slotDirectory = base.appendingPathComponent(selection.slot.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: slotDirectory, withIntermediateDirectories: true)

            if selection.filename.lowercased().contains(".tar") {
                let result = await ShellRunner.run(
                    URL(fileURLWithPath: "/usr/bin/tar"),
                    ["-xf", selection.url.path, "-C", slotDirectory.path]
                )
                guard result.succeeded else {
                    throw ValhallaError.commandFailed("Could not extract \(selection.filename): \(result.output)")
                }
            } else {
                let destination = slotDirectory.appendingPathComponent(selection.filename)
                try FileManager.default.copyItem(at: selection.url, to: destination)
            }
        }

        var payloads = try recursiveFiles(in: base).filter {
            FirmwareInspector.isPotentialPayload($0.lastPathComponent)
        }

        let compressed = payloads.filter { $0.pathExtension.lowercased() == "lz4" }
        if !compressed.isEmpty {
            guard let lz4 = BackendLocator.lz4 else {
                throw ValhallaError.commandFailed("LZ4 is required to unpack this firmware. Install it with: brew install lz4")
            }

            for source in compressed {
                let destination = source.deletingPathExtension()
                let result = await ShellRunner.run(lz4, ["-d", "-f", source.path, destination.path])
                guard result.succeeded else {
                    throw ValhallaError.commandFailed("Could not unpack \(source.lastPathComponent): \(result.output)")
                }
            }
            payloads = try recursiveFiles(in: base).filter {
                FirmwareInspector.isPotentialPayload($0.lastPathComponent)
                    && $0.pathExtension.lowercased() != "lz4"
            }
        }

        guard !payloads.isEmpty else { throw ValhallaError.noPayloads }
        return (base, payloads.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }

    private static func recursiveFiles(in directory: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: Set(keys))
            return values.isRegularFile == true ? url : nil
        }
    }
}
