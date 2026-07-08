import AppKit
import SwiftUI

private enum RingMetrics {
    static let canvasSize: CGFloat = 320
    static let searchPanelWidth: CGFloat = 236
    static let searchPanelHeight: CGFloat = 246
    static let searchPanelPadding: CGFloat = 10
    static let panelGap: CGFloat = 16
    static let overlayWidth: CGFloat = canvasSize + panelGap + searchPanelWidth
    static let outerDiameter: CGFloat = 320
    static let centerDiameter: CGFloat = 150
    static let ringDiameter: CGFloat = (outerDiameter + centerDiameter) / 2
    static let ringThickness: CGFloat = (outerDiameter - centerDiameter) / 2
    static let groupRadius: CGFloat = ringDiameter / 2
    static let groupSpacing: CGFloat = 52
    static let cardSize: CGFloat = 48
    static let iconSize: CGFloat = 40
    static let ambientGlowSize: CGFloat = 112
    static let arcGapToCenterHole: CGFloat = 1
    static let arcGlowWidth: CGFloat = 18
    static let arcStrokeWidth: CGFloat = 4
}

@MainActor
private final class HoverActivationState: ObservableObject {
    @Published var isArmed = false

    private var mouseMonitor: Any?

    func startMonitoring() {
        stopMonitoring()
        isArmed = false

        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.isArmed = true
            return event
        }
    }

    func stopMonitoring() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }
}

@MainActor
struct RingView: View {
    let groups: [RingAppGroup]
    @ObservedObject var appSearchIndex: AppSearchIndex
    let catalogService: AppCatalogService
    let shortcutLabel: String
    let onSelect: @MainActor (RingApp) -> Void
    let onSearchSelect: @MainActor (DiscoveredApp) -> Void
    let onDismiss: @MainActor () -> Void

    @State private var hoveredAppID: RingApp.ID?
    @State private var contentVisible = false
    @State private var arcThicknessProgress: CGFloat = 0
    @State private var arcSettleProgress: CGFloat = 0
    @State private var arcOpacityProgress: CGFloat = 0
    @State private var searchText = ""
    @State private var selectedSearchResultID: DiscoveredApp.ID?
    @StateObject private var hoverActivation = HoverActivationState()
    @FocusState private var isSearchFieldFocused: Bool

    private var appSlots: [RingAppSlot] {
        var entryIndex = 0

        return groups.flatMap { group in
            Array(group.apps.enumerated()).map { index, app in
                defer { entryIndex += 1 }

                return RingAppSlot(
                    app: app,
                    accentColor: group.direction.accentColor,
                    entryIndex: entryIndex,
                    center: position(
                        for: group.direction,
                        index: index,
                        count: group.apps.count
                    )
                )
            }
        }
    }

    var body: some View {
        ZStack {
            backgroundDismissLayer

            ringContent
                .position(canvasCenter)

            searchPanel
                .position(searchPanelCenter)
        }
        .frame(width: RingMetrics.overlayWidth, height: RingMetrics.canvasSize)
        .onAppear {
            hoveredAppID = nil
            searchText = ""
            selectedSearchResultID = nil
            appSearchIndex.loadIfNeeded()
            KeyboardInputSourceManager.selectEnglishInputSource()
            hoverActivation.startMonitoring()
            contentVisible = false
            arcThicknessProgress = 0
            arcSettleProgress = 0
            arcOpacityProgress = 0
            DispatchQueue.main.async {
                contentVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                isSearchFieldFocused = true
            }
            withAnimation(arcOpacityAnimation) {
                arcOpacityProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(arcThicknessBuildAnimation) {
                    arcThicknessProgress = 0.88
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
                withAnimation(arcThicknessSettleAnimation) {
                    arcSettleProgress = 1
                }
            }
        }
        .onDisappear {
            hoverActivation.stopMonitoring()
            isSearchFieldFocused = false
            searchText = ""
            selectedSearchResultID = nil
            contentVisible = false
            arcThicknessProgress = 0
            arcSettleProgress = 0
            arcOpacityProgress = 0
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard hoverActivation.isArmed else {
                    return
                }

                let nextHoveredAppID = hoveredAppID(at: location)
                guard nextHoveredAppID != hoveredAppID else {
                    return
                }

                withAnimation(.easeOut(duration: 0.11)) {
                    hoveredAppID = nextHoveredAppID
                }
            case .ended:
                withAnimation(.easeOut(duration: 0.11)) {
                    hoveredAppID = nil
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            let filteredValue = EnglishSearchInput.filtered(newValue)
            guard filteredValue == newValue else {
                searchText = filteredValue
                return
            }

            selectedSearchResultID = searchResults.first?.id
        }
        .onChange(of: searchResultIDs) { _, ids in
            selectedSearchResultID = ids.first
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                selectNextSearchResult()
            case .up:
                selectPreviousSearchResult()
            default:
                break
            }
        }
        .onExitCommand {
            onDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ringSearchMoveDown)) { _ in
            selectNextSearchResult()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ringSearchMoveUp)) { _ in
            selectPreviousSearchResult()
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [DiscoveredApp] {
        appSearchIndex.rankedApps(matching: searchText)
    }

    private var searchResultIDs: [DiscoveredApp.ID] {
        searchResults.map(\.id)
    }

    private var selectedSearchResult: DiscoveredApp? {
        if let selectedSearchResultID,
           let selectedResult = searchResults.first(where: { $0.id == selectedSearchResultID }) {
            return selectedResult
        }

        return searchResults.first
    }

    private var backgroundDismissLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        guard !isInteractive(at: value.location) else {
                            return
                        }
                        onDismiss()
                    }
            )
    }

    private var ringContent: some View {
        ZStack {
            backgroundRing
                .allowsHitTesting(false)

            ForEach(appSlots, id: \.app.id) { slot in
                RingIconButton(
                    app: slot.app,
                    accentColor: slot.accentColor,
                    isHovered: hoveredAppID == slot.app.id,
                    onSelect: onSelect
                )
                .frame(width: RingMetrics.cardSize, height: RingMetrics.cardSize)
                .position(slot.center)
                .scaleEffect(contentVisible ? 1 : 0.90)
                .opacity(contentVisible ? 1 : 0)
                .offset(
                    x: contentVisible ? 0 : iconEntranceOffset(for: slot).width,
                    y: contentVisible ? 0 : iconEntranceOffset(for: slot).height
                )
                .animation(slotRevealAnimation(for: slot), value: contentVisible)
            }
        }
        .frame(width: RingMetrics.canvasSize, height: RingMetrics.canvasSize)
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            searchResultsArea
        }
        .padding(RingMetrics.searchPanelPadding)
        .frame(width: RingMetrics.searchPanelWidth, height: RingMetrics.searchPanelHeight, alignment: .top)
        .background(searchPanelBackground)
        .opacity(contentVisible ? 1 : 0)
        .offset(x: contentVisible ? 0 : -8)
        .animation(.easeOut(duration: 0.16), value: contentVisible)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFieldFocused = true
        }
    }

    private var searchPanelBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0.82),
                        Color(nsColor: .textBackgroundColor).opacity(0.66)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 12)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .focused($isSearchFieldFocused)
                .disableAutocorrection(true)
                .onSubmit {
                    launchSelectedSearchResult()
                }
        }
        .padding(.horizontal, 11)
        .frame(width: searchContentWidth, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSearchFieldFocused
                        ? Color.accentColor.opacity(0.58)
                        : Color.white.opacity(0.14),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private var searchResultsArea: some View {
        if !trimmedSearchText.isEmpty {
            if appSearchIndex.isLoading && appSearchIndex.apps.isEmpty {
                SearchStatusRow(systemName: "magnifyingglass", title: "Indexing")
            } else if searchResults.isEmpty {
                SearchStatusRow(systemName: "questionmark.app", title: "No app")
            } else {
                VStack(spacing: 6) {
                    ForEach(searchResults) { app in
                        searchResultButton(for: app)
                    }
                }
            }
        }
    }

    private func searchResultButton(for app: DiscoveredApp) -> some View {
        Button {
            onSearchSelect(app)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: catalogService.previewIcon(forApplicationURL: app.url))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(app.bundleIdentifier ?? app.url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .frame(width: searchContentWidth - 16, height: 42)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            SearchResultButtonStyle(
                isSelected: selectedSearchResult?.id == app.id
            )
        )
    }

    private func launchSelectedSearchResult() {
        guard let selectedSearchResult else {
            NSSound.beep()
            return
        }

        onSearchSelect(selectedSearchResult)
    }

    private func selectNextSearchResult() {
        selectSearchResult(offset: 1)
    }

    private func selectPreviousSearchResult() {
        selectSearchResult(offset: -1)
    }

    private func selectSearchResult(offset: Int) {
        guard !searchResults.isEmpty else {
            return
        }

        let currentIndex = selectedSearchResultID.flatMap { id in
            searchResults.firstIndex(where: { $0.id == id })
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), searchResults.count - 1)
        selectedSearchResultID = searchResults[nextIndex].id
    }

    private var backgroundRing: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.01),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 182
                    )
                )
                .frame(width: 364, height: 364)
                .blur(radius: 18)
                .mask(ringShellMask)

            liquidGlassShell
            ringSurface
            ringAccentArcs
            ambientGlows

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
                .frame(width: RingMetrics.outerDiameter, height: RingMetrics.outerDiameter)

            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                .blur(radius: 3)
                .frame(width: RingMetrics.outerDiameter - 3, height: RingMetrics.outerDiameter - 3)
        }
        .frame(width: RingMetrics.canvasSize, height: RingMetrics.canvasSize)
    }

    private var liquidGlassShell: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .opacity(0.60)

            Circle()
                .fill(Color.white.opacity(0.24))

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.015),
                            Color(red: 0.67, green: 0.76, blue: 0.92).opacity(0.01),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.008),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.33, y: 0.20),
                        startRadius: 0,
                        endRadius: 250
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.36, green: 0.44, blue: 0.66).opacity(0.03),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.76, y: 0.82),
                        startRadius: 0,
                        endRadius: 260
                    )
                )
        }
        .frame(width: RingMetrics.outerDiameter, height: RingMetrics.outerDiameter)
        .mask(ringShellMask)
    }

    private var liquidGlassReflections: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(
                    width: RingMetrics.outerDiameter * 0.58,
                    height: RingMetrics.outerDiameter * 0.11
                )
                .blur(radius: 9)
                .offset(x: -RingMetrics.outerDiameter * 0.04, y: -RingMetrics.outerDiameter * 0.25)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.015),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: RingMetrics.outerDiameter * 0.34,
                    height: RingMetrics.outerDiameter * 0.08
                )
                .blur(radius: 10)
                .offset(x: RingMetrics.outerDiameter * 0.16, y: RingMetrics.outerDiameter * 0.18)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.015)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(
                    width: RingMetrics.outerDiameter * 0.34,
                    height: 3
                )
                .blur(radius: 4)
                .offset(x: -RingMetrics.outerDiameter * 0.03, y: -RingMetrics.outerDiameter * 0.29)
        }
        .blendMode(.screen)
        .opacity(0.58)
        .frame(width: RingMetrics.outerDiameter, height: RingMetrics.outerDiameter)
        .mask(ringShellMask)
    }

    private var ringSurface: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color(red: 0.67, green: 0.76, blue: 0.92).opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: RingMetrics.ringThickness)
                )
                .frame(width: RingMetrics.ringDiameter, height: RingMetrics.ringDiameter)

            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.01),
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.01),
                            Color.white.opacity(0.04)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: RingMetrics.ringThickness - 34)
                )
                .frame(width: RingMetrics.ringDiameter - 6, height: RingMetrics.ringDiameter - 6)
                .blur(radius: 10)
                .opacity(0.16)

            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                .frame(
                    width: RingMetrics.ringDiameter + RingMetrics.ringThickness,
                    height: RingMetrics.ringDiameter + RingMetrics.ringThickness
                )

            Circle()
                .stroke(Color.white.opacity(0.025), lineWidth: 1)
                .frame(
                    width: RingMetrics.ringDiameter - RingMetrics.ringThickness,
                    height: RingMetrics.ringDiameter - RingMetrics.ringThickness
                )
        }
    }

    private var liquidGlassEdgeHighlights: some View {
        ZStack {
            RingArcShape(
                startAngle: .degrees(-24),
                endAngle: .degrees(82)
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color(red: 0.82, green: 0.90, blue: 1.00).opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )
            .frame(width: RingMetrics.outerDiameter - 6, height: RingMetrics.outerDiameter - 6)
            .blur(radius: 1.2)

            RingArcShape(
                startAngle: .degrees(208),
                endAngle: .degrees(308)
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.92, blue: 0.88).opacity(0.08),
                        Color.white.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
            )
            .frame(width: RingMetrics.outerDiameter - 10, height: RingMetrics.outerDiameter - 10)
            .blur(radius: 1.4)

            RingArcShape(
                startAngle: .degrees(-18),
                endAngle: .degrees(88)
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            .frame(width: RingMetrics.centerDiameter + 6, height: RingMetrics.centerDiameter + 6)
            .blur(radius: 1.2)

            RingArcShape(
                startAngle: .degrees(200),
                endAngle: .degrees(300)
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.86, green: 0.92, blue: 1.00).opacity(0.07),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
            .frame(width: RingMetrics.centerDiameter + 10, height: RingMetrics.centerDiameter + 10)
            .blur(radius: 1.0)
        }
        .blendMode(.screen)
        .mask(ringShellMask)
    }

    private var ringAccentArcs: some View {
        ZStack {
            ForEach(RingGroupDirection.allCases) { direction in
                let sweep = accentArcSweep(for: direction)
                let combinedThicknessProgress = min(1, arcThicknessProgress + ((1 - arcThicknessProgress) * arcSettleProgress))
                let weightedThicknessProgress = pow(combinedThicknessProgress, 1.35)
                let thickness = max(0.001, RingMetrics.arcStrokeWidth * weightedThicknessProgress)
                let glowThickness = max(0.001, RingMetrics.arcGlowWidth * weightedThicknessProgress)

                RingArcShape(
                    startAngle: .degrees(direction.ringAngle - (sweep / 2)),
                    endAngle: .degrees(direction.ringAngle + (sweep / 2))
                )
                .stroke(
                    direction.accentColor.opacity(0.22 * arcOpacityProgress),
                    style: StrokeStyle(
                        lineWidth: glowThickness,
                        lineCap: .round
                    )
                )
                .frame(
                    width: accentArcDiameter,
                    height: accentArcDiameter
                )
                .blur(radius: 8 + (8 * arcOpacityProgress))

                RingArcShape(
                    startAngle: .degrees(direction.ringAngle - (sweep / 2)),
                    endAngle: .degrees(direction.ringAngle + (sweep / 2))
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            direction.accentColor.opacity(0.12 * arcOpacityProgress),
                            direction.accentColor.opacity(0.62 * arcOpacityProgress),
                            direction.accentColor.opacity(0.12 * arcOpacityProgress)
                        ],
                        startPoint: direction.arcGradientStartPoint,
                        endPoint: direction.arcGradientEndPoint
                    ),
                    style: StrokeStyle(
                        lineWidth: thickness,
                        lineCap: .round
                    )
                )
                .frame(
                    width: accentArcDiameter,
                    height: accentArcDiameter
                )
            }
        }
    }

    private var ambientGlows: some View {
        ZStack {
            ForEach(RingGroupDirection.allCases) { direction in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                direction.accentColor.opacity(groupOpacity(for: direction)),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: RingMetrics.ambientGlowSize / 2
                        )
                    )
                    .frame(width: RingMetrics.ambientGlowSize, height: RingMetrics.ambientGlowSize)
                    .position(anchorPoint(for: direction, center: canvasCenter))
                    .blur(radius: 30)
            }
        }
        .blendMode(.screen)
        .opacity(0.9)
    }

    private func position(
        for direction: RingGroupDirection,
        index: Int,
        count: Int
    ) -> CGPoint {
        let sweep = appGroupSweep(forCount: count, radius: RingMetrics.groupRadius)

        guard count > 1 else {
            return pointOnCircle(radius: RingMetrics.groupRadius, angle: direction.ringAngle)
        }

        let step = sweep / Double(count - 1)
        let startAngle = direction.usesReversedArcOrdering
            ? direction.ringAngle + (sweep / 2)
            : direction.ringAngle - (sweep / 2)
        let angleStep = direction.usesReversedArcOrdering ? -step : step
        let angle = startAngle + (angleStep * Double(index))

        return pointOnCircle(radius: RingMetrics.groupRadius, angle: angle)
    }

    private func anchorPoint(for direction: RingGroupDirection, center: CGPoint) -> CGPoint {
        switch direction {
        case .up:
            CGPoint(x: center.x, y: center.y - RingMetrics.groupRadius)
        case .right:
            CGPoint(x: center.x + RingMetrics.groupRadius, y: center.y)
        case .down:
            CGPoint(x: center.x, y: center.y + RingMetrics.groupRadius)
        case .left:
            CGPoint(x: center.x - RingMetrics.groupRadius, y: center.y)
        }
    }

    private var canvasCenter: CGPoint {
        CGPoint(x: RingMetrics.canvasSize / 2, y: RingMetrics.canvasSize / 2)
    }

    private var searchPanelCenter: CGPoint {
        CGPoint(
            x: RingMetrics.canvasSize + RingMetrics.panelGap + (RingMetrics.searchPanelWidth / 2),
            y: RingMetrics.canvasSize / 2
        )
    }

    private var searchContentWidth: CGFloat {
        RingMetrics.searchPanelWidth - (RingMetrics.searchPanelPadding * 2)
    }

    private func groupOpacity(for direction: RingGroupDirection) -> Double {
        guard let group = groups.first(where: { $0.direction == direction }) else {
            return 0.10
        }

        return group.apps.isEmpty ? 0.08 : 0.18
    }

    private func hoveredAppID(at location: CGPoint) -> RingApp.ID? {
        appSlots.first(where: { slot in
            slot.hitFrame.contains(location)
        })?.app.id
    }

    private func iconEntranceOffset(for slot: RingAppSlot) -> CGSize {
        let dx = slot.center.x - canvasCenter.x
        let dy = slot.center.y - canvasCenter.y
        let magnitude = max(sqrt((dx * dx) + (dy * dy)), 1)
        let distance: CGFloat = 10

        return CGSize(
            width: -(dx / magnitude) * distance,
            height: -(dy / magnitude) * distance
        )
    }

    private func slotRevealAnimation(for slot: RingAppSlot) -> Animation {
        .spring(response: 0.24, dampingFraction: 0.84)
            .delay(Double(slot.entryIndex) * 0.014)
    }

    private var arcOpacityAnimation: Animation {
        .easeOut(duration: 0.18)
    }

    private var arcThicknessBuildAnimation: Animation {
        .timingCurve(0.22, 0.88, 0.30, 1.0, duration: 0.42)
    }

    private var arcThicknessSettleAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.86)
    }

    private var ringShellMask: some View {
        RingShellShape(innerDiameter: RingMetrics.centerDiameter)
            .fill(Color.white)
            .frame(width: RingMetrics.outerDiameter, height: RingMetrics.outerDiameter)
    }

    private func isInteractive(at location: CGPoint) -> Bool {
        if appSlots.contains(where: { $0.hitFrame.contains(location) }) {
            return true
        }

        if searchPanelFrame.contains(location) {
            return true
        }

        let dx = location.x - canvasCenter.x
        let dy = location.y - canvasCenter.y
        let distance = sqrt((dx * dx) + (dy * dy))
        let outerRadius = RingMetrics.outerDiameter / 2
        let innerRadius = RingMetrics.centerDiameter / 2

        return distance <= outerRadius && distance >= innerRadius
    }

    private var searchPanelFrame: CGRect {
        CGRect(
            x: RingMetrics.canvasSize + RingMetrics.panelGap,
            y: searchPanelCenter.y - (RingMetrics.searchPanelHeight / 2),
            width: RingMetrics.searchPanelWidth,
            height: RingMetrics.searchPanelHeight
        )
    }

    private func pointOnCircle(radius: CGFloat, angle: Double) -> CGPoint {
        let radians = (angle - 90) * (.pi / 180)
        return CGPoint(
            x: canvasCenter.x + (cos(radians) * radius),
            y: canvasCenter.y + (sin(radians) * radius)
        )
    }

    private var accentArcDiameter: CGFloat {
        let arcCenterRadius = (RingMetrics.centerDiameter / 2) + RingMetrics.arcGapToCenterHole + (RingMetrics.arcStrokeWidth / 2)
        return arcCenterRadius * 2
    }

    private func accentArcSweep(for direction: RingGroupDirection) -> Double {
        let count = groups.first(where: { $0.direction == direction })?.apps.count ?? 0
        let radius = max(RingMetrics.groupRadius, 1)
        let baseSweep = appGroupSweep(forCount: count, radius: radius) + angularSpan(for: RingMetrics.cardSize * 0.58, radius: radius) + 14
        let minimumSweep: Double

        switch count {
        case 0, 1:
            minimumSweep = 66
        case 2:
            minimumSweep = 74
        default:
            minimumSweep = 80
        }

        return min(max(baseSweep, minimumSweep), 86)
    }

    private func appGroupSweep(forCount count: Int, radius: CGFloat) -> Double {
        guard count > 1 else {
            return 0
        }

        let step = angularSpan(for: RingMetrics.groupSpacing, radius: radius)
        return step * Double(count - 1)
    }

    private func angularSpan(for chord: CGFloat, radius: CGFloat) -> Double {
        let clampedRatio = min(max(chord / (2 * max(radius, 1)), 0), 0.98)
        return Double(2 * asin(clampedRatio) * (180 / .pi))
    }
}

@MainActor
private struct RingAppSlot {
    let app: RingApp
    let accentColor: Color
    let entryIndex: Int
    let center: CGPoint

    var hitFrame: CGRect {
        CGRect(
            x: center.x - (RingMetrics.cardSize / 2),
            y: center.y - (RingMetrics.cardSize / 2),
            width: RingMetrics.cardSize,
            height: RingMetrics.cardSize
        )
    }
}

private struct RingShellShape: Shape {
    let innerDiameter: CGFloat

    func path(in rect: CGRect) -> Path {
        let outerDiameter = min(rect.width, rect.height)
        let lineWidth = max((outerDiameter - innerDiameter) / 2, 0)
        let strokedRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        return Path(ellipseIn: strokedRect).strokedPath(
            StrokeStyle(lineWidth: lineWidth)
        )
    }
}


@MainActor
private struct SearchStatusRow: View {
    let systemName: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(width: RingMetrics.searchPanelWidth - (RingMetrics.searchPanelPadding * 2) - 16, height: 38)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.38))
        )
        .foregroundStyle(.secondary)
    }
}

@MainActor
private struct SearchResultButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.22)
                            : Color(nsColor: .textBackgroundColor).opacity(configuration.isPressed ? 0.58 : 0.40)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.58)
                            : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.accentColor.opacity(0.86))
                        .frame(width: 3, height: 24)
                        .padding(.leading, 4)
                }
            }
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
                radius: 8,
                x: 0,
                y: 3
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

private enum EnglishSearchInput {
    static func filtered(_ value: String) -> String {
        var result = ""

        for scalar in value.unicodeScalars {
            guard scalar.value >= 32, scalar.value < 127 else {
                continue
            }

            result.unicodeScalars.append(scalar)
        }

        return result
    }
}


@MainActor
private struct RingIconButton: View {
    let app: RingApp
    let accentColor: Color
    let isHovered: Bool
    let onSelect: @MainActor (RingApp) -> Void

    var body: some View {
        Button {
            onSelect(app)
        } label: {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(isHovered ? 0.16 : 0))
                    .frame(width: RingMetrics.iconSize + 10, height: RingMetrics.iconSize + 10)
                    .blur(radius: isHovered ? 12 : 0)

                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: RingMetrics.iconSize, height: RingMetrics.iconSize)
                    .scaleEffect(isHovered ? 1.06 : 1.0)
                    .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isHovered)
            }
            .frame(width: RingMetrics.cardSize, height: RingMetrics.cardSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(RingIconButtonStyle(isHovered: isHovered))
    }
}

@MainActor
private struct RingIconButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : (isHovered ? 1.10 : 1.0))
            .offset(y: configuration.isPressed ? 1 : (isHovered ? -4 : 0))
            .brightness(configuration.isPressed ? 0.03 : (isHovered ? 0.01 : 0))
            .saturation(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isHovered)
            .animation(.spring(response: 0.16, dampingFraction: 0.80), value: configuration.isPressed)
    }
}

private extension RingGroupDirection {
    var accentColor: Color {
        switch self {
        case .up:
            Color(red: 0.40, green: 0.84, blue: 0.94)
        case .right:
            Color(red: 0.96, green: 0.56, blue: 0.48)
        case .down:
            Color(red: 0.53, green: 0.59, blue: 0.98)
        case .left:
            Color(red: 0.45, green: 0.88, blue: 0.73)
        }
    }

    var ringAngle: Double {
        switch self {
        case .up:
            0
        case .right:
            90
        case .down:
            180
        case .left:
            270
        }
    }

    var usesReversedArcOrdering: Bool {
        switch self {
        case .down, .left:
            true
        case .up, .right:
            false
        }
    }

    var arcGradientStartPoint: UnitPoint {
        switch self {
        case .up:
            .leading
        case .right:
            .top
        case .down:
            .trailing
        case .left:
            .bottom
        }
    }

    var arcGradientEndPoint: UnitPoint {
        switch self {
        case .up:
            .trailing
        case .right:
            .bottom
        case .down:
            .leading
        case .left:
            .top
        }
    }
}

private struct RingArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle - .degrees(90),
            endAngle: endAngle - .degrees(90),
            clockwise: false
        )
        return path
    }
}

@MainActor
private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
