import Foundation

struct DiscoveredApp: Identifiable, Hashable, Sendable {
    let name: String
    let bundleIdentifier: String?
    let path: String

    var id: String {
        bundleIdentifier ?? path
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }
}

struct InstalledAppDiscoveryService: Sendable {
    func discoverInstalledApps(excluding existingItems: [AppConfiguration]) -> [DiscoveredApp] {
        let fileManager = FileManager.default
        let existingBundleIdentifiers = Set(existingItems.compactMap(\.bundleIdentifier))
        let existingPaths = Set(existingItems.map(\.path))
        var seenIdentifiers = Set<String>()
        var discoveredApps: [DiscoveredApp] = []

        for directory in searchDirectories {
            let expandedPath = NSString(string: directory).expandingTildeInPath
            guard fileManager.fileExists(atPath: expandedPath) else {
                continue
            }

            let rootURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "app" else {
                    continue
                }

                enumerator?.skipDescendants()

                guard let app = buildAppDescriptor(at: url) else {
                    continue
                }

                guard shouldInclude(
                    app,
                    existingBundleIdentifiers: existingBundleIdentifiers,
                    existingPaths: existingPaths,
                    seenIdentifiers: &seenIdentifiers
                ) else {
                    continue
                }

                discoveredApps.append(app)
            }
        }

        for path in additionalAppPaths {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            guard let app = buildAppDescriptor(at: url) else {
                continue
            }

            guard shouldInclude(
                app,
                existingBundleIdentifiers: existingBundleIdentifiers,
                existingPaths: existingPaths,
                seenIdentifiers: &seenIdentifiers
            ) else {
                continue
            }

            discoveredApps.append(app)
        }

        return discoveredApps.sorted {
            if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }

            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var searchDirectories: [String] {
        [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "~/Applications",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications"
        ]
    }

    private var additionalAppPaths: [String] {
        [
            "/System/Library/CoreServices/Finder.app"
        ]
    }

    private func shouldInclude(
        _ app: DiscoveredApp,
        existingBundleIdentifiers: Set<String>,
        existingPaths: Set<String>,
        seenIdentifiers: inout Set<String>
    ) -> Bool {
        if existingPaths.contains(app.path) {
            return false
        }

        if let bundleIdentifier = app.bundleIdentifier {
            guard !existingBundleIdentifiers.contains(bundleIdentifier) else {
                return false
            }

            return seenIdentifiers.insert(bundleIdentifier).inserted
        }

        return seenIdentifiers.insert(app.path).inserted
    }

    private func buildAppDescriptor(at url: URL) -> DiscoveredApp? {
        guard url.pathExtension.lowercased() == "app" else {
            return nil
        }

        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier
        let name = (
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ) ?? (
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        ) ?? url.deletingPathExtension().lastPathComponent

        return DiscoveredApp(
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: url.path
        )
    }
}
