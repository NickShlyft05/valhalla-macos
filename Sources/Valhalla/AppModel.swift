import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .flash
    @Published var connection: DeviceConnection = .unknown
    @Published var firmware: [FirmwareSlot: FirmwareSelection] = [:]
    @Published var partitions: [PITPartition] = []
    @Published var logs: [LogEntry] = []
    @Published var backendVersion = "Checking…"
    @Published var operationInProgress = false
    @Published var flashProgress: Double?
    @Published var autoReboot = true
    @Published var showFlashConfirmation = false
    @Published var confirmationPhrase = ""
    @Published var currentPlan: FlashPlan?
    @Published var alertMessage: String?
    @Published var unlockTransport: UnlockTransport = .unknown
    @Published var unlockReport: BootloaderReport?
    @Published var showUnlockConfirmation = false
    @Published var unlockConfirmationPhrase = ""
    @Published var unlockOwnsDevice = false
    @Published var unlockBackupConfirmed = false
    @Published var unlockKnoxConfirmed = false
    @Published var unlockFRPConfirmed = false
    @Published var unlockStatusDetail = "Connect an unlocked Android session over USB to begin."

    let heimdallURL = BackendLocator.heimdall
    let adbURL = AndroidTooling.adb
    let fastbootURL = AndroidTooling.fastboot
    private var downloadedPITURL: URL?
    private var devicePartitions: [PITPartition] = []
    private var sessionNeedsResume = false

    init() {
        log(.info, "Valhalla session started")
        Task { await loadBackendVersion() }
    }

    var validPackageCount: Int {
        firmware.values.filter { $0.validation.isValid }.count
    }

    var canPrepareFlash: Bool {
        heimdallURL != nil
            && connection.isConnected
            && !operationInProgress
            && !firmware.isEmpty
            && validPackageCount == firmware.count
    }

    var hasDevicePIT: Bool {
        !devicePartitions.isEmpty
    }

    var safetyChecks: [(String, Bool)] {
        [
            ("Heimdall backend ready", heimdallURL != nil),
            ("Device in Download Mode", connection.isConnected),
            ("Firmware packages valid", !firmware.isEmpty && validPackageCount == firmware.count),
            ("Device PIT loaded", hasDevicePIT)
        ]
    }

    func log(_ kind: LogKind, _ message: String) {
        logs.append(LogEntry(date: Date(), kind: kind, message: message))
    }

    func chooseFile(for slot: FirmwareSlot) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(slot.rawValue) firmware"
        panel.message = slot.hint
        panel.prompt = "Load \(slot.rawValue)"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            select(url, for: slot)
        }
    }

    func select(_ url: URL, for slot: FirmwareSlot) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        firmware[slot] = FirmwareSelection(
            slot: slot,
            url: url,
            size: size,
            entries: [],
            validation: .inspecting
        )
        currentPlan = nil
        log(.info, "Inspecting \(slot.rawValue): \(url.lastPathComponent)")

        Task {
            do {
                let result = try await FirmwareInspector.inspect(url)
                guard var selection = firmware[slot], selection.url == url else { return }
                selection.entries = result.entries
                selection.validation = .valid(result.detail)
                firmware[slot] = selection
                log(.success, "\(slot.rawValue) accepted — \(result.detail)")
            } catch {
                guard var selection = firmware[slot], selection.url == url else { return }
                selection.validation = .invalid(error.localizedDescription)
                firmware[slot] = selection
                log(.error, "\(slot.rawValue) rejected — \(error.localizedDescription)")
            }
        }
    }

    func remove(_ slot: FirmwareSlot) {
        if let selection = firmware.removeValue(forKey: slot) {
            log(.info, "Removed \(selection.filename)")
        }
        currentPlan = nil
    }

    func scanForDevice() {
        guard let heimdallURL else {
            connection = .error("Heimdall missing")
            alertMessage = "Heimdall is not installed. Run: brew install heimdall"
            return
        }
        guard !operationInProgress else { return }

        if hasDevicePIT {
            devicePartitions.removeAll()
            downloadedPITURL = nil
            partitions.removeAll()
            currentPlan = nil
            log(.info, "Cleared the prior live PIT before a fresh USB scan")
        }
        sessionNeedsResume = false
        connection = .scanning
        log(.info, "Scanning USB for a Samsung Download Mode device…")
        Task {
            let result = await ShellRunner.run(heimdallURL, ["detect", "--stdout-errors"])
            if result.succeeded && result.output.localizedCaseInsensitiveContains("detected") {
                connection = .connected
                log(.success, "Samsung device detected in Download Mode")
            } else {
                connection = .disconnected
                let detail = cleaned(result.output)
                log(.warning, detail.isEmpty ? "No Download Mode device detected" : detail)
            }
        }
    }

    func readDevicePIT() {
        guard let heimdallURL, connection.isConnected, !operationInProgress else { return }
        operationInProgress = true
        log(.info, "Reading the device partition table (read-only)…")

        Task {
            defer { operationInProgress = false }
            do {
                let pitURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Valhalla-device-\(UUID().uuidString).pit")
                let download = await ShellRunner.run(
                    heimdallURL,
                    ["download-pit", "--output", pitURL.path, "--no-reboot", "--stdout-errors"]
                )
                guard download.succeeded else {
                    throw ValhallaError.commandFailed(cleaned(download.output))
                }
                sessionNeedsResume = true

                let printed = await ShellRunner.run(
                    heimdallURL,
                    ["print-pit", "--file", pitURL.path, "--stdout-errors"]
                )
                guard printed.succeeded else {
                    throw ValhallaError.commandFailed(cleaned(printed.output))
                }
                let parsed = PITParser.parse(printed.output)
                guard !parsed.isEmpty else { throw ValhallaError.invalidPIT }

                downloadedPITURL = pitURL
                devicePartitions = parsed
                partitions = parsed
                log(.success, "Loaded \(parsed.count) partitions from the connected device")
            } catch {
                alertMessage = error.localizedDescription
                log(.error, "PIT read failed — \(error.localizedDescription)")
            }
        }
    }

    func importPIT() {
        let panel = NSOpenPanel()
        panel.title = "Import a PIT file for inspection"
        panel.prompt = "Inspect PIT"
        panel.allowedContentTypes = [UTType(filenameExtension: "pit") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let heimdallURL else {
            alertMessage = "Heimdall is required to parse PIT files."
            return
        }

        operationInProgress = true
        Task {
            defer { operationInProgress = false }
            let result = await ShellRunner.run(
                heimdallURL,
                ["print-pit", "--file", url.path, "--stdout-errors"]
            )
            let parsed = PITParser.parse(result.output)
            if result.succeeded && !parsed.isEmpty {
                partitions = parsed
                log(.success, "Imported \(parsed.count) partitions from \(url.lastPathComponent)")
            } else {
                alertMessage = "That PIT file could not be parsed."
                log(.error, "PIT import failed — \(cleaned(result.output))")
            }
        }
    }

    func prepareFlash() {
        guard canPrepareFlash else { return }
        operationInProgress = true
        flashProgress = nil
        currentPlan = nil
        log(.info, "Staging firmware packages…")

        Task {
            defer { operationInProgress = false }
            do {
                if !hasDevicePIT {
                    try await downloadPITForFlash()
                }

                let selections = FirmwareSlot.allCases.compactMap { firmware[$0] }
                let staged = try await FirmwareStager.stage(selections)
                let plan = FlashPlanner.create(
                    payloads: staged.payloads,
                    partitions: devicePartitions,
                    stagingDirectory: staged.directory
                )
                currentPlan = plan

                if !plan.unmappedPayloads.isEmpty {
                    let names = plan.unmappedPayloads.map(\.lastPathComponent)
                    throw ValhallaError.mappingFailed(names)
                }
                if !plan.duplicatePartitions.isEmpty {
                    throw ValhallaError.commandFailed(
                        "Multiple payloads target the same partition: \(plan.duplicatePartitions.joined(separator: ", "))"
                    )
                }

                log(.success, "Flash plan ready — \(plan.mappings.count) PIT-matched partitions")
                confirmationPhrase = ""
                showFlashConfirmation = true
            } catch {
                alertMessage = error.localizedDescription
                log(.error, "Staging blocked — \(error.localizedDescription)")
            }
        }
    }

    func executeConfirmedFlash() {
        guard
            confirmationPhrase == "FLASH",
            let plan = currentPlan,
            plan.canFlash,
            let heimdallURL,
            connection.isConnected,
            !operationInProgress
        else { return }

        showFlashConfirmation = false
        operationInProgress = true
        flashProgress = nil
        selectedSection = .logs
        log(.warning, "Flash authorized by the user — do not disconnect the cable")

        Task {
            defer {
                operationInProgress = false
                try? FileManager.default.removeItem(at: plan.stagingDirectory)
            }

            var arguments = ["flash"]
            for mapping in plan.mappings {
                arguments.append("--\(mapping.partition.name)")
                arguments.append(mapping.payloadURL.path)
            }
            if sessionNeedsResume {
                arguments.append("--resume")
            }
            if !autoReboot {
                arguments.append("--no-reboot")
            }
            arguments.append("--stdout-errors")

            log(.info, "Writing \(plan.mappings.count) partitions with Heimdall…")
            let result = await ShellRunner.run(heimdallURL, arguments)
            let lines = result.output.split(whereSeparator: \.isNewline).map(String.init)
            for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                log(result.succeeded ? .info : .error, line)
            }

            sessionNeedsResume = false
            if result.succeeded {
                flashProgress = 1
                log(.success, autoReboot ? "Flash completed; device reboot requested" : "Flash completed; device left in Download Mode")
            } else {
                alertMessage = "Heimdall reported a flash failure. The phone was not marked successful; review the session log before doing anything else."
                log(.error, "Flash failed with exit code \(result.status)")
            }
        }
    }

    func cancelConfirmation() {
        showFlashConfirmation = false
        confirmationPhrase = ""
    }

    func clearLog() {
        logs.removeAll()
        log(.info, "Session log cleared")
    }

    private func loadBackendVersion() async {
        guard let heimdallURL else {
            backendVersion = "Not installed"
            log(.warning, "Heimdall backend not found")
            return
        }
        let result = await ShellRunner.run(heimdallURL, ["version"])
        backendVersion = result.succeeded
            ? "Heimdall \(cleaned(result.output))"
            : "Heimdall found"
        log(.success, "\(backendVersion) ready")
    }

    private func downloadPITForFlash() async throws {
        guard let heimdallURL else { throw ValhallaError.backendMissing }
        log(.info, "Downloading the device PIT for authoritative partition matching…")
        let pitURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Valhalla-device-\(UUID().uuidString).pit")
        let download = await ShellRunner.run(
            heimdallURL,
            ["download-pit", "--output", pitURL.path, "--no-reboot", "--stdout-errors"]
        )
        guard download.succeeded else {
            throw ValhallaError.commandFailed(cleaned(download.output))
        }
        sessionNeedsResume = true

        let printed = await ShellRunner.run(
            heimdallURL,
            ["print-pit", "--file", pitURL.path, "--stdout-errors"]
        )
        guard printed.succeeded else {
            throw ValhallaError.commandFailed(cleaned(printed.output))
        }
        let parsed = PITParser.parse(printed.output)
        guard !parsed.isEmpty else { throw ValhallaError.invalidPIT }
        downloadedPITURL = pitURL
        devicePartitions = parsed
        partitions = parsed
        log(.success, "Matched against \(parsed.count) device partitions")
    }

    private func cleaned(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
