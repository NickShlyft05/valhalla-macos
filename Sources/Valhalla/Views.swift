import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color(hex: 0x090C12).ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 268)

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1)

                VStack(spacing: 0) {
                    TopBar()
                    content
                }
            }
        }
        .sheet(isPresented: $model.showFlashConfirmation) {
            FlashConfirmationView()
                .environmentObject(model)
        }
        .alert(
            "Valhalla",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            ),
            actions: {
                Button("OK") { model.alertMessage = nil }
            },
            message: {
                Text(model.alertMessage ?? "")
            }
        )
        .onAppear {
            if case .unknown = model.connection {
                model.scanForDevice()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSection {
        case .flash:
            FlashView()
        case .device:
            DeviceView()
        case .logs:
            LogView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandView()
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 28)

            VStack(spacing: 7) {
                ForEach(AppSection.allCases) { section in
                    SidebarButton(
                        section: section,
                        selected: model.selectedSection == section,
                        badge: section == .logs && model.logs.count > 0 ? "\(model.logs.count)" : nil
                    ) {
                        model.selectedSection = section
                    }
                }
            }
            .padding(.horizontal, 13)

            DeviceStatusCard()
                .padding(.horizontal, 14)
                .padding(.top, 26)

            SafetyRail()
                .padding(.horizontal, 20)
                .padding(.top, 24)

            Spacer(minLength: 18)

            HStack(spacing: 9) {
                Circle()
                    .fill(model.heimdallURL == nil ? Color.red : Color(hex: 0x40D9B5))
                    .frame(width: 7, height: 7)
                Text(model.backendVersion)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .background(Color(hex: 0x0D1119))
    }
}

struct BrandView: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x9B8CFF), Color(hex: 0x5F4CDD)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 39, height: 39)

                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("VALHALLA")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(1.6)
                Text("SAMSUNG FLASH UTILITY")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0x9B8CFF))
            }
        }
    }
}

struct SidebarButton: View {
    let section: AppSection
    let selected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.56))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                selected ? Color(hex: 0x9B8CFF, alpha: 0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(Color(hex: 0x9B8CFF))
                        .frame(width: 3, height: 20)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DeviceStatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("USB CONNECTION")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.65), radius: 5)
            }

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.055))
                        .frame(width: 38, height: 48)
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.3)
                        .frame(width: 22, height: 36)
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 7, height: 1.5)
                        .offset(y: 13)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.connection.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(statusSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                model.scanForDevice()
            } label: {
                HStack {
                    if case .scanning = model.connection {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Scan USB")
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
        .background(
            Color.white.opacity(0.028),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var statusColor: Color {
        switch model.connection {
        case .connected: return Color(hex: 0x40D9B5)
        case .scanning: return Color(hex: 0xFFB15C)
        case .error: return .red
        default: return Color.white.opacity(0.25)
        }
    }

    private var statusSubtitle: String {
        switch model.connection {
        case .connected: return "Ready for PIT read"
        case .scanning: return "Looking for Samsung USB"
        case .error(let message): return message
        default: return "Connect phone via USB"
        }
    }
}

struct SafetyRail: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("READINESS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ForEach(Array(model.safetyChecks.enumerated()), id: \.offset) { _, check in
                HStack(spacing: 9) {
                    Image(systemName: check.1 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(check.1 ? Color(hex: 0x40D9B5) : Color.white.opacity(0.17))
                    Text(check.0)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(check.1 ? Color.white.opacity(0.76) : Color.white.opacity(0.34))
                }
            }
        }
    }
}

struct TopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedSection.rawValue)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(sectionSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.operationInProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("WORKING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                }
                .foregroundStyle(Color(hex: 0x9B8CFF))
                .padding(.horizontal, 11)
                .frame(height: 29)
                .background(Color(hex: 0x9B8CFF, alpha: 0.09), in: Capsule())
            }

            Text("macOS NATIVE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.38))
                .padding(.horizontal, 11)
                .frame(height: 29)
                .background(Color.white.opacity(0.035), in: Capsule())
        }
        .padding(.horizontal, 28)
        .frame(height: 70)
        .background(Color(hex: 0x090C12).opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var sectionSubtitle: String {
        switch model.selectedSection {
        case .flash: return "Load official firmware packages and build a PIT-matched flash plan."
        case .device: return "Inspect the connected device’s authoritative partition layout."
        case .logs: return "A local audit trail of every backend action and result."
        }
    }
}

struct FlashView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sectionHeader(
                    eyebrow: "01 / FIRMWARE",
                    title: "Load packages",
                    detail: "Official BL, AP, CP, and CSC archives are supported. Drop or choose files."
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(FirmwareSlot.allCases) { slot in
                        FirmwareCard(slot: slot)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    FlashOptionsCard()
                    PlanSummaryCard()
                }

                FlashActionBar()
            }
            .padding(28)
        }
        .background(
            RadialGradient(
                colors: [Color(hex: 0x1B1732, alpha: 0.26), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
        )
    }

    private func sectionHeader(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Color(hex: 0x9B8CFF))
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FirmwareCard: View {
    @EnvironmentObject private var model: AppModel
    let slot: FirmwareSlot
    @State private var dropTargeted = false

    var body: some View {
        Button {
            model.chooseFile(for: slot)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(slot.color.opacity(selection == nil ? 0.09 : 0.15))
                        .frame(width: 46, height: 46)
                    Text(slot.rawValue)
                        .font(.system(size: slot == .userdata ? 8 : 12, weight: .black, design: .monospaced))
                        .foregroundStyle(slot.color)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(slot.title)
                            .font(.system(size: 13, weight: .semibold))
                        if let selection {
                            validationIcon(selection.validation)
                        }
                    }

                    if let selection {
                        Text(selection.filename)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 6) {
                            Text(selection.formattedSize)
                            Text("•")
                            validationText(selection.validation)
                        }
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else {
                        Text(slot.hint)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.31))
                            .lineLimit(1)
                        Text("CLICK OR DROP FILE")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(slot.color.opacity(0.72))
                    }
                }

                Spacer(minLength: 6)

                if selection != nil {
                    Button {
                        model.remove(slot)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove package")
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.04), in: Circle())
                }
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
            .background(
                dropTargeted ? slot.color.opacity(0.1) : Color.white.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        dropTargeted ? slot.color.opacity(0.8) : Color.white.opacity(0.075),
                        style: StrokeStyle(lineWidth: 1, dash: selection == nil ? [5, 5] : [])
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    model.select(url, for: slot)
                }
            }
            return true
        }
    }

    private var selection: FirmwareSelection? {
        model.firmware[slot]
    }

    @ViewBuilder
    private func validationIcon(_ validation: PackageValidation) -> some View {
        switch validation {
        case .inspecting:
            ProgressView().controlSize(.mini)
        case .valid:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0x40D9B5))
        case .invalid:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func validationText(_ validation: PackageValidation) -> some View {
        switch validation {
        case .inspecting: Text("Inspecting")
        case .valid(let detail): Text(detail)
        case .invalid(let detail): Text(detail).foregroundStyle(.red)
        }
    }
}

struct FlashOptionsCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Flash behavior", systemImage: "switch.2")
                .font(.system(size: 13, weight: .semibold))

            Toggle(isOn: $model.autoReboot) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto reboot")
                        .font(.system(size: 12, weight: .medium))
                    Text("Restart after a successful flash")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider().overlay(Color.white.opacity(0.07))

            HStack(spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color(hex: 0x40D9B5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repartition is locked")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("This build never alters PIT layout.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .cardStyle()
    }
}

struct PlanSummaryCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Preflight summary", systemImage: "checklist")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 24) {
                metric(value: "\(model.firmware.count)", label: "PACKAGES")
                metric(value: "\(model.validPackageCount)", label: "VALID")
                metric(value: "\(model.partitions.count)", label: "PIT ENTRIES")
            }

            Divider().overlay(Color.white.opacity(0.07))

            if let plan = model.currentPlan {
                Label(
                    "\(plan.mappings.count) payloads matched by device PIT",
                    systemImage: plan.canFlash ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(plan.canFlash ? Color(hex: 0x40D9B5) : Color.red)
            } else {
                Text("The plan is generated only after the device PIT is read. No payload is assigned by slot-name guesswork.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .cardStyle()
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(.secondary)
        }
    }
}

struct FlashActionBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 19))
                .foregroundStyle(Color(hex: 0xFFB15C))

            VStack(alignment: .leading, spacing: 3) {
                Text("Device writes require a final typed confirmation")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Keep the Mac awake and use a direct, reliable USB cable.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.prepareFlash()
            } label: {
                HStack(spacing: 9) {
                    if model.operationInProgress {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(model.hasDevicePIT ? "Build Flash Plan" : "Preflight & Read PIT")
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 20)
                .frame(height: 40)
                .background(
                    model.canPrepareFlash ? Color(hex: 0x7967F2) : Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .foregroundStyle(model.canPrepareFlash ? .white : Color.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!model.canPrepareFlash)
        }
        .padding(16)
        .background(Color(hex: 0xFFB15C, alpha: 0.055), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(hex: 0xFFB15C, alpha: 0.16), lineWidth: 1)
        }
    }
}

struct DeviceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Authoritative partition table")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Read directly from the connected device, or inspect a local PIT file.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import PIT…") { model.importPIT() }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    model.readDevicePIT()
                } label: {
                    Label("Read Device PIT", systemImage: "arrow.down.doc.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.connection.isConnected || model.operationInProgress)
            }
            .padding(28)

            if model.partitions.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0x9B8CFF, alpha: 0.09))
                            .frame(width: 80, height: 80)
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Color(hex: 0x9B8CFF))
                    }
                    Text("No PIT loaded")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Connect a phone in Download Mode and read its PIT before building a flash plan.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
                Spacer()
            } else {
                PITTable(partitions: model.partitions)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
        }
    }
}

struct PITTable: View {
    let partitions: [PITPartition]
    @State private var search = ""

    private var filtered: [PITPartition] {
        guard !search.isEmpty else { return partitions }
        return partitions.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.displayFilename.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter \(partitions.count) partitions", text: $search)
                    .textFieldStyle(.plain)
                Spacer()
                Text("\(filtered.count) SHOWN")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 39)
            .background(Color.white.opacity(0.025))

            HStack {
                Text("ID").frame(width: 56, alignment: .leading)
                Text("PARTITION").frame(maxWidth: .infinity, alignment: .leading)
                Text("FLASH FILENAME").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color.white.opacity(0.04))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { partition in
                        HStack {
                            Text(partition.identifier.map(String.init) ?? "—")
                                .frame(width: 56, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Text(partition.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(Color.white.opacity(0.88))
                            Text(partition.displayFilename)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(Color(hex: 0x9B8CFF))
                        }
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 14)
                        .frame(height: 33)
                        .background(partition.id.hashValue.isMultiple(of: 2) ? Color.white.opacity(0.012) : .clear)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.white.opacity(0.035)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }
}

struct LogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LOCAL SESSION OUTPUT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.clearLog() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 28)
            .frame(height: 58)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.logs) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(entry.timestamp)
                                    .foregroundStyle(Color.white.opacity(0.26))
                                    .frame(width: 57, alignment: .leading)
                                Text(entry.kind.symbol)
                                    .foregroundStyle(color(for: entry.kind))
                                    .frame(width: 12)
                                Text(entry.message)
                                    .foregroundStyle(Color.white.opacity(0.77))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .id(entry.id)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.white.opacity(0.025)).frame(height: 1)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(Color(hex: 0x07090D))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .onChange(of: model.logs.count) { _ in
                    if let last = model.logs.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func color(for kind: LogKind) -> Color {
        switch kind {
        case .info: return Color(hex: 0x61A8FF)
        case .success: return Color(hex: 0x40D9B5)
        case .warning: return Color(hex: 0xFFB15C)
        case .error: return Color.red
        }
    }
}

struct FlashConfirmationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: 0xFFB15C, alpha: 0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: 0xFFB15C))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Authorize firmware flash")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("This is the point where the app stops being theoretical.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)

            Divider().overlay(Color.white.opacity(0.07))

            VStack(alignment: .leading, spacing: 16) {
                if let plan = model.currentPlan {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(plan.mappings.count) PARTITIONS WILL BE WRITTEN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(Color(hex: 0x9B8CFF))

                        ScrollView {
                            LazyVStack(spacing: 5) {
                                ForEach(plan.mappings) { mapping in
                                    HStack {
                                        Text(mapping.partition.name)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(mapping.payloadName)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(Color(hex: 0xFFB15C))
                    Text("Do not disconnect the USB cable, close the MacBook, or let the Mac sleep while flashing.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Type FLASH to continue")
                        .font(.system(size: 10.5, weight: .semibold))
                    TextField("FLASH", text: $model.confirmationPhrase)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    model.confirmationPhrase == "FLASH"
                                        ? Color(hex: 0x40D9B5, alpha: 0.7)
                                        : Color.white.opacity(0.1),
                                    lineWidth: 1
                                )
                        }
                }
            }
            .padding(22)

            Divider().overlay(Color.white.opacity(0.07))

            HStack {
                Button("Cancel") { model.cancelConfirmation() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button {
                    model.executeConfirmedFlash()
                } label: {
                    Label("Flash Firmware", systemImage: "bolt.fill")
                }
                .buttonStyle(DangerButtonStyle())
                .disabled(model.confirmationPhrase != "FLASH")
            }
            .padding(18)
        }
        .frame(width: 540)
        .background(Color(hex: 0x10141D))
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }
}

extension View {
    fileprivate func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 33)
            .background(Color(hex: 0x7967F2).opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 13)
            .frame(height: 33)
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.055), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.white.opacity(0.76))
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 16)
            .frame(height: 35)
            .background(Color.red.opacity(configuration.isPressed ? 0.65 : 0.83), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
    }
}
