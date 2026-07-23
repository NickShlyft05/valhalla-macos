import SwiftUI

struct BootloaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear
                        .frame(height: 0)
                        .id("bootloader-top")

                    BootloaderHero()
                    UnlockProgressStrip()
                    UnlockTransportCard()

                    if let report = model.unlockReport {
                        HStack(alignment: .top, spacing: 16) {
                            UnlockEligibilityCard(report: report)
                            UnlockDiagnosticsCard(report: report)
                        }
                    } else if model.unlockTransport == .downloadMode {
                        DownloadModeInstructionCard()
                    }

                    OfficialUnlockWorkflowCard()
                    UnlockHardStopsCard()
                }
                .padding(28)
            }
            .onAppear {
                proxy.scrollTo("bootloader-top", anchor: .top)
            }
            .background(
                RadialGradient(
                    colors: [Color(hex: 0x17332E, alpha: 0.25), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 540
                )
            )
        }
        .sheet(isPresented: $model.showUnlockConfirmation) {
            UnlockConfirmationView()
                .environmentObject(model)
        }
    }
}

struct BootloaderHero: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("OWNER-CONTROLLED WORKFLOW")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Color(hex: 0x40D9B5))

                Text("Unlock eligibility.\nNo fake bypasses.")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(-0.5)

                Text("Valhalla checks the official path, prepares Download Mode, and leaves the irreversible approval where Android requires it: physically on your phone.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 610, alignment: .leading)
            }

            Spacer(minLength: 16)

            ZStack {
                Circle()
                    .fill(Color(hex: 0x40D9B5, alpha: 0.08))
                    .frame(width: 118, height: 118)
                Circle()
                    .stroke(Color(hex: 0x40D9B5, alpha: 0.2), lineWidth: 1)
                    .frame(width: 93, height: 93)
                Image(systemName: heroIcon)
                    .font(.system(size: 39, weight: .light))
                    .foregroundStyle(heroColor)
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: 0x121B1C),
                    Color(hex: 0x0E131A)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color(hex: 0x40D9B5, alpha: 0.13), lineWidth: 1)
        }
    }

    private var heroIcon: String {
        switch model.unlockReport?.eligibility {
        case .alreadyUnlocked: return "lock.open.fill"
        case .unsupported, .wrongManufacturer: return "lock.slash.fill"
        default: return "lock.open.rotation"
        }
    }

    private var heroColor: Color {
        switch model.unlockReport?.eligibility {
        case .unsupported, .wrongManufacturer: return Color(hex: 0xFF7A86)
        default: return Color(hex: 0x40D9B5)
        }
    }
}

struct UnlockProgressStrip: View {
    @EnvironmentObject private var model: AppModel

    private let steps = [
        ("1", "Authorize ADB"),
        ("2", "Check eligibility"),
        ("3", "Enter Download Mode"),
        ("4", "Confirm on phone")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(index <= activeIndex ? Color(hex: 0x40D9B5) : Color.white.opacity(0.055))
                            .frame(width: 24, height: 24)
                        Text(step.0)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(index <= activeIndex ? Color(hex: 0x07110E) : Color.white.opacity(0.3))
                    }
                    Text(step.1)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(index <= activeIndex ? Color.white.opacity(0.84) : Color.white.opacity(0.3))

                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(index < activeIndex ? Color(hex: 0x40D9B5, alpha: 0.42) : Color.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 55)
        .cardStyle()
    }

    private var activeIndex: Int {
        switch model.unlockTransport {
        case .downloadMode:
            return 3
        case .adb:
            if model.unlockReport != nil { return 1 }
            return 0
        case .unauthorized:
            return 0
        default:
            return -1
        }
    }
}

struct UnlockTransportCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(statusColor.opacity(0.11))
                    .frame(width: 54, height: 54)
                Image(systemName: statusIcon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.unlockReport?.displayName ?? model.unlockTransport.title)
                        .font(.system(size: 14, weight: .bold))
                    statusBadge
                }
                Text(model.unlockStatusDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                toolStatus("ADB", ready: model.adbURL != nil)
                toolStatus("HEIMDALL", ready: model.heimdallURL != nil)
                toolStatus("FASTBOOT", ready: model.fastbootURL != nil)
            }
            .padding(.trailing, 8)

            Button {
                model.scanUnlockDevice()
            } label: {
                HStack(spacing: 8) {
                    if model.operationInProgress {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wave.3.right")
                    }
                    Text(model.unlockReport == nil ? "Inspect Phone" : "Refresh")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.operationInProgress)
        }
        .padding(17)
        .cardStyle()
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(statusLabel)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.09), in: Capsule())
    }

    private var statusLabel: String {
        switch model.unlockTransport {
        case .adb: return "ADB"
        case .downloadMode: return "ODIN / LOKE"
        case .fastboot: return "FASTBOOT"
        case .unauthorized: return "AUTHORIZE"
        case .scanning: return "SCANNING"
        case .error: return "ERROR"
        default: return "OFFLINE"
        }
    }

    private var statusColor: Color {
        switch model.unlockTransport {
        case .adb, .downloadMode: return Color(hex: 0x40D9B5)
        case .scanning, .unauthorized, .fastboot: return Color(hex: 0xFFB15C)
        case .error, .multipleDevices: return Color(hex: 0xFF7A86)
        default: return Color.white.opacity(0.28)
        }
    }

    private var statusIcon: String {
        switch model.unlockTransport {
        case .adb: return "cable.connector"
        case .downloadMode: return "arrow.down.to.line.compact"
        case .fastboot: return "terminal.fill"
        case .unauthorized: return "hand.raised.fill"
        case .scanning: return "wave.3.right"
        case .error, .multipleDevices: return "exclamationmark.triangle.fill"
        default: return "iphone.slash"
        }
    }

    private func toolStatus(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ready ? Color(hex: 0x40D9B5) : Color.red)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
    }
}

struct UnlockEligibilityCard: View {
    let report: BootloaderReport

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Eligibility verdict", systemImage: verdictIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(verdictColor)
                Spacer()
                Text(verdictLabel)
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(verdictColor)
            }

            Text(report.eligibility.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text(verdictDetail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.white.opacity(0.07))

            HStack {
                diagnosticStatus(
                    "OEM SUPPORT",
                    value: boolLabel(report.oemUnlockSupported),
                    positive: report.oemUnlockSupported
                )
                diagnosticStatus(
                    "OEM ALLOWED",
                    value: boolLabel(report.oemUnlockAllowed),
                    positive: report.oemUnlockAllowed
                )
                diagnosticStatus(
                    "FLASH LOCK",
                    value: lockLabel(report.flashLocked),
                    positive: report.flashLocked.map { !$0 }
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 206, alignment: .topLeading)
        .cardStyle()
    }

    private var verdictLabel: String {
        switch report.eligibility {
        case .alreadyUnlocked: return "UNLOCKED"
        case .readyForDeviceConfirmation: return "READY"
        case .needsOEMToggle: return "SETUP"
        case .unsupported, .wrongManufacturer: return "BLOCKED"
        default: return "UNKNOWN"
        }
    }

    private var verdictIcon: String {
        switch report.eligibility {
        case .alreadyUnlocked, .readyForDeviceConfirmation: return "checkmark.shield.fill"
        case .unsupported, .wrongManufacturer: return "xmark.shield.fill"
        default: return "questionmark.diamond.fill"
        }
    }

    private var verdictColor: Color {
        switch report.eligibility {
        case .alreadyUnlocked, .readyForDeviceConfirmation: return Color(hex: 0x40D9B5)
        case .unsupported, .wrongManufacturer: return Color(hex: 0xFF7A86)
        default: return Color(hex: 0xFFB15C)
        }
    }

    private var verdictDetail: String {
        switch report.eligibility {
        case .alreadyUnlocked:
            return "The Android boot properties report an open flash lock. Recheck after every firmware change."
        case .readyForDeviceConfirmation:
            return "The software-side authorization appears enabled. The phone must still approve the unlock physically."
        case .needsOEMToggle:
            return "Enable OEM Unlock in Developer options. Valhalla will not alter that protected setting for you."
        case .unsupported:
            return "The firmware reports ro.oem_unlock_supported=0. There is no legitimate host-side override."
        case .wrongManufacturer(let manufacturer):
            return "The connected device reports \(manufacturer). This workflow is intentionally Samsung-only."
        case .unknown:
            return "The build did not expose enough state for a definitive answer. Check Developer options manually."
        case .noReport:
            return "Inspect the phone to continue."
        }
    }

    private func diagnosticStatus(_ title: String, value: String, positive: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(
                    positive == true
                        ? Color(hex: 0x40D9B5)
                        : positive == false ? Color(hex: 0xFFB15C) : Color.white.opacity(0.55)
                )
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func boolLabel(_ value: Bool?) -> String {
        guard let value else { return "UNKNOWN" }
        return value ? "YES" : "NO"
    }

    private func lockLabel(_ value: Bool?) -> String {
        guard let value else { return "UNKNOWN" }
        return value ? "LOCKED" : "OPEN"
    }
}

struct UnlockDiagnosticsCard: View {
    let report: BootloaderReport

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Device diagnostics", systemImage: "waveform.path.ecg.rectangle")
                .font(.system(size: 13, weight: .semibold))

            diagnosticRow("Manufacturer", report.manufacturer)
            diagnosticRow("Product / device", joined(report.product, report.device))
            diagnosticRow("Android", report.androidVersion)
            diagnosticRow("Build", report.buildNumber)
            diagnosticRow("Verified Boot", report.verifiedBootState.uppercased())
            diagnosticRow("VBMeta state", report.vbmetaState.uppercased())
            diagnosticRow("ADB serial", masked(report.serial))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 206, alignment: .topLeading)
        .cardStyle()
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "Not reported" : value)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.73))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func joined(_ first: String, _ second: String) -> String {
        [first, second].filter { !$0.isEmpty }.joined(separator: " / ")
    }

    private func masked(_ value: String) -> String {
        guard value.count > 7 else { return value }
        return "\(value.prefix(4))••••\(value.suffix(3))"
    }
}

struct DownloadModeInstructionCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color(hex: 0x40D9B5))

            VStack(alignment: .leading, spacing: 8) {
                Text("The Mac is done. Read the phone.")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("On supported Samsung models, the Download Mode screen offers bootloader unlock after a long-press of Volume Up. Follow the exact prompt shown by your model. The phone—not Valhalla—must accept the irreversible factory reset.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color(hex: 0x40D9B5, alpha: 0.055), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(hex: 0x40D9B5, alpha: 0.17), lineWidth: 1)
        }
    }
}

struct OfficialUnlockWorkflowCard: View {
    @EnvironmentObject private var model: AppModel

    private let steps = [
        ("1", "Back up every file", "Unlock confirmation triggers a factory reset. Treat anything not backed up as disposable."),
        ("2", "Enable Developer options", "Tap Build number seven times, then enable USB debugging and the OEM Unlock toggle if present."),
        ("3", "Re-inspect eligibility", "Valhalla checks read-only boot properties. Missing OEM Unlock means stop—not hunt for a bypass."),
        ("4", "Enter Download Mode", "Valhalla can request the reboot. The final unlock approval stays on the phone’s physical controls."),
        ("5", "Set up and verify again", "After the wipe, complete legitimate Google account verification, re-enable USB debugging, and inspect again.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OFFICIAL SAMSUNG PATH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(Color(hex: 0x9B8CFF))
                    Text("Guided unlock workflow")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                Spacer()
                Button("Open Developer Options") {
                    model.openDeveloperOptions()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!model.canOpenDeveloperOptions)

                Button {
                    model.requestUnlockTransition()
                } label: {
                    Label("Prepare Download Mode", systemImage: "lock.open.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canBeginUnlockTransition)
            }

            Divider().overlay(Color.white.opacity(0.07))

            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 12) {
                    Text(step.0)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x9B8CFF))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: 0x9B8CFF, alpha: 0.09), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.1)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(step.2)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(19)
        .cardStyle()
    }
}

struct UnlockHardStopsCard: View {
    private let stops = [
        ("KG / RMM", "Carrier, finance, or enterprise restrictions must be cleared by the authorized provider."),
        ("FRP", "Know the Google account currently associated with the phone. Valhalla does not bypass account verification."),
        ("Knox", "Booting or flashing unauthorized code can permanently trip the one-time Warranty Bit."),
        ("Missing OEM Unlock", "Some models, regions, carriers, and firmware builds simply do not expose an official unlock path.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "nosign")
                    .foregroundStyle(Color(hex: 0xFF7A86))
                Text("Hard stops—not “advanced mode” opportunities")
                    .font(.system(size: 13, weight: .semibold))
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 10
            ) {
                ForEach(Array(stops.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0xFF7A86))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Text(item.1)
                                .font(.system(size: 9.2))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                    .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(18)
        .background(Color(hex: 0xFF7A86, alpha: 0.035), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(hex: 0xFF7A86, alpha: 0.12), lineWidth: 1)
        }
    }
}

struct UnlockConfirmationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.11))
                        .frame(width: 43, height: 43)
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 19))
                        .foregroundStyle(Color(hex: 0xFF7A86))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prepare irreversible unlock")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Valhalla reboots the phone; your physical confirmation performs the wipe.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)

            Divider().overlay(Color.white.opacity(0.07))

            VStack(alignment: .leading, spacing: 14) {
                confirmationToggle(
                    "I own or am authorized to modify this phone.",
                    isOn: $model.unlockOwnsDevice
                )
                confirmationToggle(
                    "My local data is backed up; I accept a complete factory reset.",
                    isOn: $model.unlockBackupConfirmed
                )
                confirmationToggle(
                    "I know the current Google account credentials required by FRP.",
                    isOn: $model.unlockFRPConfirmed
                )
                confirmationToggle(
                    "I understand unofficial code may permanently trip Knox and disable Samsung services.",
                    isOn: $model.unlockKnoxConfirmed
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("Type ERASE AND UNLOCK")
                        .font(.system(size: 10.5, weight: .semibold))
                    TextField("ERASE AND UNLOCK", text: $model.unlockConfirmationPhrase)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(confirmationReady ? Color(hex: 0x40D9B5, alpha: 0.7) : Color.white.opacity(0.1))
                        }
                }

                Text("No bypass, KG/RMM clearing, FRP removal, firmware flash, or unlock command is bundled into this action.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(hex: 0xFFB15C))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)

            Divider().overlay(Color.white.opacity(0.07))

            HStack {
                Button("Cancel") { model.cancelUnlockTransition() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button {
                    model.executeUnlockTransition()
                } label: {
                    Label("Reboot to Download Mode", systemImage: "arrow.down.to.line.compact")
                }
                .buttonStyle(DangerButtonStyle())
                .disabled(!confirmationReady)
            }
            .padding(18)
        }
        .frame(width: 590)
        .background(Color(hex: 0x10141D))
    }

    private var confirmationReady: Bool {
        model.unlockConfirmationPhrase == "ERASE AND UNLOCK"
            && model.unlockOwnsDevice
            && model.unlockBackupConfirmed
            && model.unlockFRPConfirmed
            && model.unlockKnoxConfirmed
    }

    private func confirmationToggle(_ text: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
    }
}

struct UnlockSidebarStatus: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("UNLOCK TRANSPORT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(statusColor)
                    .frame(width: 38, height: 43)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.unlockTransport.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(sidebarDetail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Button {
                model.scanUnlockDevice()
            } label: {
                HStack {
                    if model.operationInProgress {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wave.3.right")
                    }
                    Text("Inspect phone")
                }
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(model.operationInProgress)
        }
        .padding(14)
        .cardStyle()
    }

    private var statusColor: Color {
        switch model.unlockTransport {
        case .adb, .downloadMode: return Color(hex: 0x40D9B5)
        case .unauthorized, .scanning, .fastboot: return Color(hex: 0xFFB15C)
        case .error, .multipleDevices: return Color(hex: 0xFF7A86)
        default: return Color.white.opacity(0.26)
        }
    }

    private var sidebarDetail: String {
        if let report = model.unlockReport {
            return report.eligibility.title
        }
        switch model.unlockTransport {
        case .unauthorized: return "Approve the RSA key"
        case .downloadMode: return "Confirm on the phone"
        default: return "ADB or Download Mode"
        }
    }
}

struct UnlockReadinessRail: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("ELIGIBILITY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            readiness("ADB available", model.adbURL != nil)
            readiness("Phone authorized", model.unlockTransport.isADBConnected)
            readiness(
                "Samsung identified",
                model.unlockReport?.manufacturer.localizedCaseInsensitiveContains("samsung") == true
            )
            readiness(
                "Official path reported",
                model.unlockReport?.eligibility == .readyForDeviceConfirmation
                    || model.unlockReport?.eligibility == .needsOEMToggle
            )
        }
    }

    private func readiness(_ title: String, _ ready: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ready ? Color(hex: 0x40D9B5) : Color.white.opacity(0.17))
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ready ? Color.white.opacity(0.76) : Color.white.opacity(0.34))
        }
    }
}
