import Foundation

@MainActor
extension AppModel {
    var unlockReadinessChecks: [(String, Bool)] {
        let report = unlockReport
        return [
            ("ADB tool available", adbURL != nil),
            ("Samsung detected", report?.manufacturer.localizedCaseInsensitiveContains("samsung") == true),
            ("OEM unlock supported", report?.oemUnlockSupported == true),
            ("Backup acknowledged", unlockBackupConfirmed)
        ]
    }

    var canOpenDeveloperOptions: Bool {
        unlockTransport.isADBConnected && unlockReport != nil && !operationInProgress
    }

    var canBeginUnlockTransition: Bool {
        guard
            unlockTransport.isADBConnected,
            let report = unlockReport,
            !operationInProgress
        else {
            return false
        }

        switch report.eligibility {
        case .wrongManufacturer, .alreadyUnlocked, .unsupported, .noReport:
            return false
        case .readyForDeviceConfirmation, .needsOEMToggle, .unknown:
            return true
        }
    }

    func scanUnlockDevice() {
        guard !operationInProgress else { return }
        guard let adbURL else {
            unlockTransport = .error("ADB is not installed")
            unlockStatusDetail = "Install Android Platform Tools with: brew install android-platform-tools"
            alertMessage = unlockStatusDetail
            return
        }

        operationInProgress = true
        unlockTransport = .scanning
        unlockReport = nil
        unlockStatusDetail = "Checking ADB, Samsung Download Mode, and fastboot transports…"
        log(.info, "Inspecting connected devices for official bootloader unlock eligibility…")

        Task {
            defer { operationInProgress = false }

            let adbResult = await ShellRunner.run(adbURL, ["devices", "-l"])
            guard adbResult.succeeded else {
                unlockTransport = .error("ADB failed")
                unlockStatusDetail = trimmed(adbResult.output)
                log(.error, "ADB inspection failed — \(unlockStatusDetail)")
                return
            }

            let records = AndroidDeviceParser.parseDevices(adbResult.output)
            if records.count > 1 {
                unlockTransport = .multipleDevices(records.count)
                unlockStatusDetail = "Disconnect every device except the Samsung phone you intend to inspect."
                log(.warning, "Unlock inspection blocked — \(records.count) ADB devices are connected")
                return
            }

            if let record = records.first {
                if record.state == "unauthorized" {
                    unlockTransport = .unauthorized(record.serial)
                    unlockStatusDetail = "Unlock the phone and approve this Mac’s USB debugging key."
                    log(.warning, "ADB device found but USB debugging is not authorized")
                    return
                }

                guard record.state == "device" else {
                    unlockTransport = .error("ADB state: \(record.state)")
                    unlockStatusDetail = "The device is visible to ADB but is not ready. Reconnect it and unlock the screen."
                    log(.warning, "Unexpected ADB state: \(record.state)")
                    return
                }

                await inspectAuthorizedDevice(record, adbURL: adbURL)
                return
            }

            if let heimdallURL {
                let heimdall = await ShellRunner.run(heimdallURL, ["detect", "--stdout-errors"])
                if heimdall.succeeded && heimdall.output.localizedCaseInsensitiveContains("detected") {
                    unlockTransport = .downloadMode
                    unlockStatusDetail = "Use the instructions shown on the phone. The physical confirmation cannot be automated."
                    log(.success, "Samsung device detected in Download Mode")
                    return
                }
            }

            if let fastbootURL {
                let fastboot = await ShellRunner.run(fastbootURL, ["devices"])
                if let serial = firstDeviceSerial(fastboot.output) {
                    unlockTransport = .fastboot(serial)
                    unlockStatusDetail = "Fastboot is present, but Samsung unlocks normally require the device’s Download Mode confirmation."
                    log(.warning, "Fastboot transport detected; no Samsung unlock command was sent")
                    return
                }
            }

            unlockTransport = .disconnected
            unlockStatusDetail = "Enable USB debugging, unlock the phone, and connect it directly to this Mac."
            log(.warning, "No Android, Download Mode, or fastboot device detected")
        }
    }

    func openDeveloperOptions() {
        guard
            canOpenDeveloperOptions,
            let adbURL,
            let serial = unlockReport?.serial
        else {
            return
        }

        operationInProgress = true
        log(.info, "Opening Developer options on the connected phone…")
        Task {
            defer { operationInProgress = false }
            let result = await ShellRunner.run(
                adbURL,
                [
                    "-s", serial,
                    "shell", "am", "start",
                    "-a", "android.settings.APPLICATION_DEVELOPMENT_SETTINGS"
                ]
            )
            if result.succeeded {
                log(.success, "Developer options opened on the phone")
            } else {
                alertMessage = "Developer options could not be opened automatically. Open Settings → Developer options on the phone."
                log(.warning, "Could not open Developer options — \(trimmed(result.output))")
            }
        }
    }

    func requestUnlockTransition() {
        guard canBeginUnlockTransition else { return }
        unlockConfirmationPhrase = ""
        unlockOwnsDevice = false
        unlockBackupConfirmed = false
        unlockKnoxConfirmed = false
        unlockFRPConfirmed = false
        showUnlockConfirmation = true
    }

    func cancelUnlockTransition() {
        showUnlockConfirmation = false
        unlockConfirmationPhrase = ""
    }

    func executeUnlockTransition() {
        guard
            unlockConfirmationPhrase == "ERASE AND UNLOCK",
            unlockOwnsDevice,
            unlockBackupConfirmed,
            unlockKnoxConfirmed,
            unlockFRPConfirmed,
            let adbURL,
            let serial = unlockReport?.serial,
            canBeginUnlockTransition
        else {
            return
        }

        showUnlockConfirmation = false
        operationInProgress = true
        log(.warning, "User authorized reboot to Samsung Download Mode; no unlock bypass command will be sent")

        Task {
            defer { operationInProgress = false }
            let result = await ShellRunner.run(adbURL, ["-s", serial, "reboot", "download"])
            guard result.succeeded else {
                alertMessage = "The phone rejected ADB reboot-to-download. Enter Download Mode with the model-specific button combination instead."
                log(.error, "ADB reboot download failed — \(trimmed(result.output))")
                return
            }

            unlockTransport = .scanning
            unlockStatusDetail = "Waiting for Samsung Download Mode…"
            log(.success, "Phone reboot command accepted; waiting for Download Mode")
            try? await Task.sleep(nanoseconds: 6_000_000_000)

            if let heimdallURL {
                let detection = await ShellRunner.run(heimdallURL, ["detect", "--stdout-errors"])
                if detection.succeeded && detection.output.localizedCaseInsensitiveContains("detected") {
                    unlockTransport = .downloadMode
                    unlockStatusDetail = "Follow the warning screen on the phone. On supported models, long-press Volume Up to request bootloader unlock."
                    log(.success, "Samsung Download Mode detected — physical confirmation is now required")
                    return
                }
            }

            unlockTransport = .disconnected
            unlockStatusDetail = "Check the phone screen. If Download Mode did not appear, use its model-specific button combination."
            log(.warning, "Download Mode was not detected automatically after reboot")
        }
    }

    private func inspectAuthorizedDevice(_ record: ADBDeviceRecord, adbURL: URL) async {
        let propertiesResult = await ShellRunner.run(
            adbURL,
            ["-s", record.serial, "shell", "getprop"]
        )
        guard propertiesResult.succeeded else {
            unlockTransport = .error("Property inspection failed")
            unlockStatusDetail = trimmed(propertiesResult.output)
            log(.error, "Could not read Android properties — \(unlockStatusDetail)")
            return
        }

        let properties = AndroidDeviceParser.parseProperties(propertiesResult.output)
        let developerResult = await ShellRunner.run(
            adbURL,
            ["-s", record.serial, "shell", "settings", "get", "global", "development_settings_enabled"]
        )
        let oemSettingResult = await ShellRunner.run(
            adbURL,
            ["-s", record.serial, "shell", "settings", "get", "global", "oem_unlock_allowed"]
        )

        let propertyOEMAllowed = firstNonempty(
            properties["sys.oem_unlock_allowed"],
            properties["ro.boot.oem_unlock_allowed"]
        )
        let settingOEMAllowed = oemSettingResult.succeeded ? trimmed(oemSettingResult.output) : ""

        let report = BootloaderReport(
            serial: record.serial,
            manufacturer: value(properties, "ro.product.manufacturer"),
            model: firstNonempty(
                properties["ro.product.model"],
                record.attributes["model"]
            ),
            product: firstNonempty(
                properties["ro.build.product"],
                record.attributes["product"]
            ),
            device: firstNonempty(
                properties["ro.product.device"],
                record.attributes["device"]
            ),
            androidVersion: value(properties, "ro.build.version.release"),
            buildNumber: firstNonempty(
                properties["ro.build.display.id"],
                properties["ro.build.version.incremental"]
            ),
            oemUnlockSupported: parseBoolean(properties["ro.oem_unlock_supported"]),
            oemUnlockAllowed: parseBoolean(
                propertyOEMAllowed.isEmpty ? settingOEMAllowed : propertyOEMAllowed
            ),
            flashLocked: parseLockState(properties["ro.boot.flash.locked"]),
            vbmetaState: value(properties, "ro.boot.vbmeta.device_state"),
            verifiedBootState: value(properties, "ro.boot.verifiedbootstate"),
            developerOptionsEnabled: developerResult.succeeded
                ? parseBoolean(trimmed(developerResult.output))
                : nil
        )

        unlockReport = report
        unlockTransport = .adb(record.serial)
        unlockStatusDetail = detail(for: report.eligibility)

        switch report.eligibility {
        case .alreadyUnlocked:
            log(.success, "\(report.displayName) reports an unlocked bootloader")
        case .unsupported:
            log(.warning, "\(report.displayName) reports that flashing unlock is unsupported")
        case .wrongManufacturer(let manufacturer):
            log(.warning, "Connected device manufacturer is \(manufacturer), not Samsung")
        default:
            log(.success, "Inspected \(report.displayName) bootloader eligibility")
        }
    }

    private func detail(for eligibility: BootloaderEligibility) -> String {
        switch eligibility {
        case .noReport:
            return "Connect and inspect the phone."
        case .wrongManufacturer(let manufacturer):
            return "This workflow is Samsung-only; the connected manufacturer reports \(manufacturer)."
        case .alreadyUnlocked:
            return "Android reports the flash lock is already open. Verify before flashing anything."
        case .readyForDeviceConfirmation:
            return "OEM unlock authorization is reported. Back up the phone before entering Download Mode."
        case .needsOEMToggle:
            return "Open Developer options and enable OEM Unlock before continuing."
        case .unsupported:
            return "This model, region, carrier, or firmware build reports no official flashing-unlock support."
        case .unknown:
            return "Android did not expose a definitive unlock flag. Confirm the OEM Unlock toggle manually."
        }
    }

    private func value(_ properties: [String: String], _ key: String) -> String {
        properties[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func parseBoolean(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "enabled": return true
        case "0", "false", "no", "disabled": return false
        default: return nil
        }
    }

    private func parseLockState(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "locked": return true
        case "0", "unlocked": return false
        default: return nil
        }
    }

    private func firstNonempty(_ values: String?...) -> String {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0.lowercased() != "null" }) ?? ""
    }

    private func firstDeviceSerial(_ output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .first(where: { $0.count >= 2 && $0[1] == "fastboot" })?
            .first
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
