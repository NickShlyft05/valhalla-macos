import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case flash = "Flash"
    case unlock = "Bootloader"
    case device = "PIT & Device"
    case logs = "Session Log"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flash: return "bolt.fill"
        case .unlock: return "lock.open.fill"
        case .device: return "square.stack.3d.up.fill"
        case .logs: return "text.alignleft"
        }
    }
}

enum UnlockTransport: Equatable {
    case unknown
    case scanning
    case disconnected
    case unauthorized(String)
    case adb(String)
    case downloadMode
    case fastboot(String)
    case multipleDevices(Int)
    case error(String)

    var title: String {
        switch self {
        case .unknown: return "Not scanned"
        case .scanning: return "Inspecting device…"
        case .disconnected: return "No device"
        case .unauthorized: return "USB authorization needed"
        case .adb: return "Android connected"
        case .downloadMode: return "Download Mode"
        case .fastboot: return "Fastboot detected"
        case .multipleDevices(let count): return "\(count) devices connected"
        case .error: return "Inspection failed"
        }
    }

    var isADBConnected: Bool {
        if case .adb = self { return true }
        return false
    }
}

enum BootloaderEligibility: Equatable {
    case noReport
    case wrongManufacturer(String)
    case alreadyUnlocked
    case readyForDeviceConfirmation
    case needsOEMToggle
    case unsupported
    case unknown

    var title: String {
        switch self {
        case .noReport: return "Connect and inspect"
        case .wrongManufacturer: return "Not a Samsung device"
        case .alreadyUnlocked: return "Bootloader appears unlocked"
        case .readyForDeviceConfirmation: return "Ready for Download Mode"
        case .needsOEMToggle: return "OEM Unlock setup required"
        case .unsupported: return "Official unlock unsupported"
        case .unknown: return "Eligibility not reported"
        }
    }
}

struct BootloaderReport: Equatable {
    let serial: String
    let manufacturer: String
    let model: String
    let product: String
    let device: String
    let androidVersion: String
    let buildNumber: String
    let oemUnlockSupported: Bool?
    let oemUnlockAllowed: Bool?
    let flashLocked: Bool?
    let vbmetaState: String
    let verifiedBootState: String
    let developerOptionsEnabled: Bool?

    var eligibility: BootloaderEligibility {
        if !manufacturer.isEmpty,
           !manufacturer.localizedCaseInsensitiveContains("samsung") {
            return .wrongManufacturer(manufacturer)
        }
        if flashLocked == false || vbmetaState.localizedCaseInsensitiveContains("unlocked") {
            return .alreadyUnlocked
        }
        if oemUnlockSupported == false {
            return .unsupported
        }
        if oemUnlockAllowed == true {
            return .readyForDeviceConfirmation
        }
        if oemUnlockSupported == true {
            return .needsOEMToggle
        }
        return .unknown
    }

    var displayName: String {
        if !model.isEmpty { return model }
        if !product.isEmpty { return product }
        return "Samsung device"
    }
}

struct ADBDeviceRecord: Equatable {
    let serial: String
    let state: String
    let attributes: [String: String]
}

enum AndroidDeviceParser {
    static func parseDevices(_ output: String) -> [ADBDeviceRecord] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    !line.isEmpty,
                    !line.hasPrefix("List of devices"),
                    !line.hasPrefix("* daemon")
                else {
                    return nil
                }

                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count >= 2 else { return nil }
                var attributes: [String: String] = [:]
                for field in fields.dropFirst(2) {
                    guard let colon = field.firstIndex(of: ":") else { continue }
                    let key = String(field[..<colon])
                    let value = String(field[field.index(after: colon)...])
                    attributes[key] = value
                }
                return ADBDeviceRecord(
                    serial: fields[0],
                    state: fields[1],
                    attributes: attributes
                )
            }
    }

    static func parseProperties(_ output: String) -> [String: String] {
        var properties: [String: String] = [:]
        let pattern = #"^\[([^\]]+)\]: \[(.*)\]$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return properties }

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard
                let match = regex.firstMatch(in: line, range: range),
                let keyRange = Range(match.range(at: 1), in: line),
                let valueRange = Range(match.range(at: 2), in: line)
            else {
                continue
            }
            properties[String(line[keyRange])] = String(line[valueRange])
        }
        return properties
    }
}

enum FirmwareSlot: String, CaseIterable, Identifiable, Hashable {
    case bl = "BL"
    case ap = "AP"
    case cp = "CP"
    case csc = "CSC"
    case userdata = "USERDATA"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bl: return "Bootloader"
        case .ap: return "System image"
        case .cp: return "Modem"
        case .csc: return "Region / carrier"
        case .userdata: return "User data"
        }
    }

    var hint: String {
        switch self {
        case .bl: return "BL_…tar.md5"
        case .ap: return "AP_…tar.md5"
        case .cp: return "CP_…tar.md5"
        case .csc: return "CSC_… or HOME_CSC_…"
        case .userdata: return "Optional USERDATA package"
        }
    }

    var color: Color {
        switch self {
        case .bl: return Color(hex: 0x9B8CFF)
        case .ap: return Color(hex: 0x40D9B5)
        case .cp: return Color(hex: 0x61A8FF)
        case .csc: return Color(hex: 0xFFB15C)
        case .userdata: return Color(hex: 0xF275A8)
        }
    }
}

enum PackageValidation: Equatable {
    case inspecting
    case valid(String)
    case invalid(String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

struct FirmwareSelection: Identifiable, Equatable {
    let id = UUID()
    let slot: FirmwareSlot
    let url: URL
    let size: Int64
    var entries: [String]
    var validation: PackageValidation

    var filename: String { url.lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct PITPartition: Identifiable, Equatable {
    let id = UUID()
    let identifier: Int?
    let name: String
    let flashFilename: String?

    var displayFilename: String {
        guard let flashFilename, !flashFilename.isEmpty else { return "—" }
        return flashFilename
    }
}

enum DeviceConnection: Equatable {
    case unknown
    case scanning
    case disconnected
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .unknown: return "Not scanned"
        case .scanning: return "Scanning…"
        case .disconnected: return "No device"
        case .connected: return "Download Mode"
        case .error: return "Backend error"
        }
    }
}

enum LogKind {
    case info
    case success
    case warning
    case error

    var symbol: String {
        switch self {
        case .info: return "•"
        case .success: return "✓"
        case .warning: return "!"
        case .error: return "×"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let kind: LogKind
    let message: String

    var timestamp: String {
        Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct FlashMapping: Identifiable, Equatable {
    let id = UUID()
    let partition: PITPartition
    let payloadURL: URL

    var payloadName: String { payloadURL.lastPathComponent }
}

struct FlashPlan {
    let mappings: [FlashMapping]
    let stagingDirectory: URL
    let unmappedPayloads: [URL]
    let duplicatePartitions: [String]

    var canFlash: Bool {
        !mappings.isEmpty && unmappedPayloads.isEmpty && duplicatePartitions.isEmpty
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}
