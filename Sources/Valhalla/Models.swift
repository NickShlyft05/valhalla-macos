import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case flash = "Flash"
    case device = "PIT & Device"
    case logs = "Session Log"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flash: return "bolt.fill"
        case .device: return "square.stack.3d.up.fill"
        case .logs: return "text.alignleft"
        }
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
