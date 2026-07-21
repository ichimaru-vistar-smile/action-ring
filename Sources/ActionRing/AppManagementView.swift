import AppKit
import Combine
import SwiftUI

@MainActor
struct AppManagementView: View {
    @ObservedObject var store: AppConfigurationStore
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @State private var launchAtLoginToggle = false
    @State private var isSynchronizingLaunchAtLoginToggle = false

    let onAddApp: @MainActor (RingGroupDirection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                shortcutSection
                screenEdgeSection
                appearanceSection
                startupSection
                groupEditor
                footer
            }
            .padding(24)
        }
        .frame(minWidth: 900, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            launchAtLoginManager.refresh()
            syncLaunchAtLoginToggle()
        }
        .onReceive(launchAtLoginStatePublisher) { _ in
            syncLaunchAtLoginToggle()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Manage Apps")
                    .font(.system(size: 24, weight: .semibold))

                Text("Edit the ring as four fixed groups: up, right, down, and left. Each group supports up to 3 apps.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Open Config Folder") {
                    NSWorkspace.shared.open(store.configurationDirectoryURL)
                }

                Button("Reset Defaults") {
                    store.resetToDefaults()
                }
            }
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcut")
                        .font(.system(size: 16, weight: .semibold))

                    Text("Current: \(store.shortcutDisplayString)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: hotKeySelectionBinding) {
                        ForEach(HotKeyKeyOption.allOptions) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Modifiers")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(HotKeyModifier.allCases, id: \.self) { modifier in
                            Toggle(modifier.title, isOn: modifierBinding(modifier))
                                .toggleStyle(.switch)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ring Position")
                        .font(.system(size: 16, weight: .semibold))

                    Text("Choose whether the ring opens in the screen center or around the current pointer.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Picker("Ring Position", selection: overlayPositionBinding) {
                ForEach(RingOverlayPositionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(store.overlayPositionMode.description)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var screenEdgeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Edge Actions")
                        .font(.system(size: 16, weight: .semibold))

                    Text("Hold the selected key and touch a screen edge to open that direction's default app or group.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hold Key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Picker("Hold Key", selection: screenEdgeHoldKeyBinding) {
                        ForEach(ScreenEdgeHoldKey.allCases) { key in
                            Text("\(key.symbol) \(key.title)").tag(key)
                        }
                    }
                    .frame(width: 180)
                }

                Text("Set the default target separately inside each direction below. Directions without a default target stay inactive.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var groupEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupDirectionCard(
                direction: .up,
                items: store.items(for: .up),
                store: store,
                onAdd: onAddApp
            )

            HStack(alignment: .top, spacing: 18) {
                GroupDirectionCard(
                    direction: .left,
                    items: store.items(for: .left),
                    store: store,
                    onAdd: onAddApp
                )

                GroupDirectionCard(
                    direction: .right,
                    items: store.items(for: .right),
                    store: store,
                    onAdd: onAddApp
                )
            }

            GroupDirectionCard(
                direction: .down,
                items: store.items(for: .down),
                store: store,
                onAdd: onAddApp
            )
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Startup")
                        .font(.system(size: 16, weight: .semibold))

                    Text(launchAtLoginManager.statusDescription)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 16) {
                Toggle("Launch at login", isOn: $launchAtLoginToggle)
                    .toggleStyle(.switch)
                    .disabled(!launchAtLoginManager.isSupported && !launchAtLoginManager.requiresApproval)
                    .onChange(of: launchAtLoginToggle) { _, isEnabled in
                        handleLaunchAtLoginToggleChange(isEnabled)
                    }

                if launchAtLoginManager.shouldOfferInstall {
                    Button(launchAtLoginManager.installButtonTitle) {
                        launchAtLoginManager.installToApplications()
                    }
                }

                if launchAtLoginManager.requiresApproval {
                    Button("Open Login Items") {
                        launchAtLoginManager.openSystemSettings()
                    }
                }
            }

            if !launchAtLoginManager.installDescription.isEmpty {
                Text(launchAtLoginManager.installDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var footer: some View {
        HStack {
            Text("Each direction is a fixed group. Move apps inside the group with up/down. Move apps across groups from the transfer menu.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(store.totalItemCount) apps")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var hotKeySelectionBinding: Binding<HotKeyKeyOption> {
        Binding(
            get: {
                HotKeyKeyOption.option(for: store.preferences.hotKey.keyCode)
            },
            set: { option in
                store.updateHotKeyKeyCode(option.keyCode)
            }
        )
    }

    private var overlayPositionBinding: Binding<RingOverlayPositionMode> {
        Binding(
            get: {
                store.overlayPositionMode
            },
            set: { mode in
                store.updateOverlayPositionMode(mode)
            }
        )
    }

    private var screenEdgeHoldKeyBinding: Binding<ScreenEdgeHoldKey> {
        Binding(
            get: {
                store.screenEdgeHoldKey
            },
            set: { key in
                store.updateScreenEdgeHoldKey(key)
            }
        )
    }

    private func modifierBinding(_ modifier: HotKeyModifier) -> Binding<Bool> {
        Binding(
            get: {
                store.preferences.hotKey.modifiers.contains(modifier)
            },
            set: { isEnabled in
                store.setHotKeyModifier(modifier, enabled: isEnabled)
            }
        )
    }

    private var launchAtLoginStatePublisher: AnyPublisher<Bool, Never> {
        launchAtLoginManager.$isEnabled
            .combineLatest(launchAtLoginManager.$requiresApproval)
            .map { isEnabled, requiresApproval in
                isEnabled || requiresApproval
            }
            .eraseToAnyPublisher()
    }

    private func handleLaunchAtLoginToggleChange(_ isEnabled: Bool) {
        guard !isSynchronizingLaunchAtLoginToggle else {
            return
        }

        if launchAtLoginManager.requiresApproval {
            launchAtLoginManager.openSystemSettings()
            syncLaunchAtLoginToggle()
            return
        }

        launchAtLoginManager.setEnabled(isEnabled)
        syncLaunchAtLoginToggle()
    }

    private func syncLaunchAtLoginToggle() {
        let resolvedState = launchAtLoginManager.isEnabled || launchAtLoginManager.requiresApproval
        guard launchAtLoginToggle != resolvedState else {
            return
        }

        isSynchronizingLaunchAtLoginToggle = true
        launchAtLoginToggle = resolvedState

        DispatchQueue.main.async {
            isSynchronizingLaunchAtLoginToggle = false
        }
    }
}

@MainActor
private struct GroupDirectionCard: View {
    let direction: RingGroupDirection
    let items: [AppConfiguration]
    @ObservedObject var store: AppConfigurationStore
    let onAdd: @MainActor (RingGroupDirection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(direction.symbol) \(direction.title)")
                        .font(.system(size: 16, weight: .semibold))

                    Text("\(items.count) / \(AppGroupConfiguration.maxItemCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Add App") {
                    onAdd(direction)
                }
                .disabled(!store.canAdd(to: direction))
            }

            if items.count >= 2 {
                appGroupEditor
            }

            defaultTargetEditor

            VStack(spacing: 10) {
                ForEach(slotModels, id: \.slotIndex) { slot in
                    if let item = slot.item {
                        GroupAppRow(
                            slotIndex: slot.slotIndex + 1,
                            direction: direction,
                            item: item,
                            store: store
                        )
                    } else {
                        EmptySlotView(slotIndex: slot.slotIndex + 1)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var slotModels: [SlotModel] {
        (0..<AppGroupConfiguration.maxItemCount).map { index in
            SlotModel(slotIndex: index, item: index < items.count ? items[index] : nil)
        }
    }

    private var groupChoices: [AppGroupChoice] {
        guard items.count >= 2 else {
            return [AppGroupChoice(title: "None", ids: [])]
        }

        var choices = [
            AppGroupChoice(title: "None", ids: []),
            AppGroupChoice(title: "\(items[0].name) + \(items[1].name)", ids: [items[0].id, items[1].id])
        ]

        if items.count == 3 {
            choices.append(
                AppGroupChoice(title: "\(items[1].name) + \(items[2].name)", ids: [items[1].id, items[2].id])
            )
            choices.append(AppGroupChoice(title: "All three apps", ids: items.map(\.id)))
        }

        return choices
    }

    private var selectedGroupIDs: [UUID] {
        store.group(for: direction).groupedAppIDs
    }

    private var selectedGroupTitle: String {
        groupChoices.first(where: { $0.ids == selectedGroupIDs })?.title ?? "Unknown group"
    }

    private var appGroupEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("App group")
                        .font(.system(size: 12, weight: .semibold))

                    Text(selectedGroupIDs.isEmpty ? "No group" : selectedGroupTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if selectedGroupIDs.isEmpty {
                    Menu("Create Group") {
                        groupChoiceButtons
                    }
                } else {
                    if groupChoices.filter({ !$0.ids.isEmpty && $0.ids != selectedGroupIDs }).isEmpty == false {
                        Menu("Edit") {
                            groupChoiceButtons
                        }
                    }

                    Button("Remove Group", role: .destructive) {
                        store.setGroupedAppIDs([], for: direction)
                    }
                }
            }

            Text("One group per direction. Grouped apps must be next to each other.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private var defaultTargetEditor: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Screen edge default")
                    .font(.system(size: 12, weight: .semibold))

                Text("Used while holding \(store.screenEdgeHoldKey.symbol) at the \(direction.title.lowercased()) edge.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Default target", selection: defaultTargetBinding) {
                Text("Not Set").tag(DirectionDefaultTarget?.none)

                ForEach(items) { item in
                    Text(item.name).tag(DirectionDefaultTarget?.some(.app(item.id)))
                }

                if !selectedGroupIDs.isEmpty {
                    Text("Group: \(selectedGroupTitle)").tag(DirectionDefaultTarget?.some(.group))
                }
            }
            .labelsHidden()
            .frame(width: 210)
            .disabled(items.isEmpty)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private var defaultTargetBinding: Binding<DirectionDefaultTarget?> {
        Binding(
            get: {
                store.group(for: direction).defaultTarget
            },
            set: { target in
                store.setDefaultTarget(target, for: direction)
            }
        )
    }

    @ViewBuilder
    private var groupChoiceButtons: some View {
        ForEach(groupChoices.filter { !$0.ids.isEmpty }) { choice in
            Button(choice.title) {
                store.setGroupedAppIDs(choice.ids, for: direction)
            }
            .disabled(choice.ids == selectedGroupIDs)
        }
    }
}

private struct AppGroupChoice: Identifiable {
    let title: String
    let ids: [UUID]

    var id: String {
        ids.map(\.uuidString).joined(separator: ":")
    }
}

@MainActor
private struct GroupAppRow: View {
    let slotIndex: Int
    let direction: RingGroupDirection
    let item: AppConfiguration
    let store: AppConfigurationStore

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", slotIndex))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            Image(nsImage: store.previewIcon(for: item))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))

                Text(item.bundleIdentifier ?? item.path)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    store.moveUp(id: item.id, in: direction)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(!store.canMoveUp(id: item.id, in: direction))

                Button {
                    store.moveDown(id: item.id, in: direction)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!store.canMoveDown(id: item.id, in: direction))

                Menu {
                    ForEach(RingGroupDirection.allCases) { target in
                        Button("\(target.symbol) \(target.title)") {
                            store.move(item.id, from: direction, to: target)
                        }
                        .disabled(!store.canMove(item.id, from: direction, to: target))
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .menuStyle(.borderlessButton)

                Button(role: .destructive) {
                    store.remove(id: item.id, from: direction)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct EmptySlotView: View {
    let slotIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", slotIndex))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .frame(width: 30, height: 30)

            Text("Empty slot")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }
}

private struct SlotModel {
    let slotIndex: Int
    let item: AppConfiguration?
}
