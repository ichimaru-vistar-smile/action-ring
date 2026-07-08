import AppKit
import SwiftUI

@MainActor
struct InstalledAppPickerView: View {
    let direction: RingGroupDirection
    @ObservedObject var viewModel: InstalledAppPickerViewModel

    let catalogService: AppCatalogService
    let onClose: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content
            footer
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.loadIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add App to \(direction.symbol) \(direction.title)")
                .font(.system(size: 24, weight: .semibold))

            Text("Browse installed apps, search by name, and place the app into this group.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search installed apps", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning installed apps...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        } else if viewModel.filteredApps.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("No matching apps")
                    .font(.system(size: 18, weight: .semibold))

                Text("Try a different keyword or reset your search.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        } else {
            List(selection: $viewModel.selectedAppID) {
                ForEach(viewModel.filteredApps) { app in
                    Button {
                        viewModel.select(app)
                    } label: {
                        HStack(spacing: 14) {
                            Image(nsImage: catalogService.previewIcon(forApplicationURL: app.url))
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text(app.bundleIdentifier ?? app.path)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(app.id)
                    .onTapGesture(count: 2) {
                        viewModel.select(app)
                        if viewModel.addSelectedApp() {
                            onClose()
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(viewModel.filteredApps.count) apps")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                onClose()
            }

            Button("Add Selected App") {
                if viewModel.addSelectedApp() {
                    onClose()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.selectedApp == nil || viewModel.isLoading)
        }
    }
}
