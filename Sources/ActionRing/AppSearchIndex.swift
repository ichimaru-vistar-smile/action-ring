import Combine
import Foundation

@MainActor
final class AppSearchIndex: ObservableObject {
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published private(set) var isLoading = false

    private let discoveryService: InstalledAppDiscoveryService
    private var didLoad = false

    init(discoveryService: InstalledAppDiscoveryService = InstalledAppDiscoveryService()) {
        self.discoveryService = discoveryService
    }

    func loadIfNeeded() {
        guard !didLoad, !isLoading else {
            return
        }

        isLoading = true
        let discoveryService = discoveryService

        Task {
            let discoveredApps = await Task.detached(priority: .userInitiated) {
                discoveryService.discoverInstalledApps(excluding: [])
            }.value

            apps = discoveredApps
            didLoad = true
            isLoading = false
        }
    }

    func rankedApps(matching rawQuery: String, limit: Int = 3) -> [DiscoveredApp] {
        let query = normalized(rawQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else {
            return []
        }

        return apps
            .compactMap { app -> (app: DiscoveredApp, score: Int)? in
                guard let score = score(for: app, query: query) else {
                    return nil
                }

                return (app, score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
                }

                return lhs.score < rhs.score
            }
            .prefix(limit)
            .map(\.app)
    }

    private func score(for app: DiscoveredApp, query: String) -> Int? {
        let name = normalized(app.name)
        let bundleIdentifier = normalized(app.bundleIdentifier ?? "")
        let path = normalized(app.path)
        let fileName = normalized(app.url.deletingPathExtension().lastPathComponent)
        let initials = acronym(for: app.name)

        if name == query || fileName == query {
            return 0
        }

        if name.hasPrefix(query) {
            return 10 + name.count
        }

        if fileName.hasPrefix(query) {
            return 14 + fileName.count
        }

        if initials.hasPrefix(query) {
            return 20 + initials.count
        }

        if let wordPrefixScore = wordPrefixScore(for: query, in: app.name) {
            return 24 + wordPrefixScore
        }

        if let range = name.range(of: query) {
            return 40 + name.distance(from: name.startIndex, to: range.lowerBound)
        }

        if bundleIdentifier.hasPrefix(query) {
            return 56 + bundleIdentifier.count
        }

        if bundleIdentifier.contains(query) {
            return 72 + bundleIdentifier.count
        }

        if path.contains(query) {
            return 92 + path.count
        }

        if let fuzzyScore = fuzzySubsequenceScore(for: query, in: name) {
            return 120 + fuzzyScore
        }

        return nil
    }

    private func wordPrefixScore(for query: String, in name: String) -> Int? {
        let words = normalized(name)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard let index = words.firstIndex(where: { $0.hasPrefix(query) }) else {
            return nil
        }

        return (index * 4) + (words[index].count - query.count)
    }

    private func fuzzySubsequenceScore(for query: String, in candidate: String) -> Int? {
        var candidateIndex = candidate.startIndex
        var previousMatchOffset: Int?
        var score = 0

        for character in query {
            guard candidateIndex < candidate.endIndex,
                  let matchIndex = candidate[candidateIndex...].firstIndex(of: character) else {
                return nil
            }

            let offset = matchIndex.utf16Offset(in: candidate)
            if let previousMatchOffset {
                score += max(0, offset - previousMatchOffset - 1)
            } else {
                score += offset
            }

            previousMatchOffset = offset
            candidateIndex = candidate.index(after: matchIndex)
        }

        return score + candidate.count
    }

    private func acronym(for name: String) -> String {
        normalized(name)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
