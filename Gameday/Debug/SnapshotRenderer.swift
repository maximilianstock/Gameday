#if DEBUG
import AppKit
import SwiftUI

/// Renders the popover with fixture data to PNG files: `Gameday --snapshot <directory>`.
/// Used to check the layout without clicking through the menu bar.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        Task {
            await render(into: directory)
            exit(0)
        }
        return true
    }

    private static func render(into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "gameday.snapshot")!
        defaults.removePersistentDomain(forName: "gameday.snapshot")
        let live = CommandLine.arguments.contains("--live")
        let preferences = Preferences(defaults: defaults)
        let service: ScoreboardProviding = live ? ESPNScoreboardService() : FixtureScoreboardService()
        let store = ScoreboardStore(service: service, preferences: preferences)
        await store.refresh()
        var urls = live ? [] : Fixtures.imageURLs
        for section in store.sections {
            if let logo = section.logoURL { urls.append(logo) }
            for game in section.games {
                if let url = game.first.imageURL { urls.append(url) }
                if let url = game.second.imageURL { urls.append(url) }
            }
        }
        await store.waitForHighlights()
        if !live {
            preferences.addFavorite(Favorite(id: "s:600~t:132", name: "FC Bayern München", subtitle: "Bundesliga", imageURL: Fixtures.logo("soccer", "132"), sport: .soccer, isPlayer: false))
            preferences.addFavorite(Favorite(id: "s:850~a:2375", name: "Alexander Zverev", subtitle: "ATP", imageURL: URL(string: "https://a.espncdn.com/i/headshots/tennis/players/full/2375.png"), sport: .tennis, isPlayer: true))
            store.debugMarkTopMatches(["g1", "n1", "t1"])
            urls.append(contentsOf: preferences.favorites.compactMap(\.imageURL))
        }
        store.isPopoverShown = true
        await ImageStore.shared.prefetch(urls)
        print("snapshot: \(store.sections.count) sections, \(store.sections.reduce(0) { $0 + $1.games.count }) games, failed: \(store.failedLeagueIDs)")

        let appearances: [(String, NSAppearance.Name, ColorScheme)] = [
            ("light", .aqua, .light),
            ("dark", .darkAqua, .dark),
        ]
        for (label, appearanceName, scheme) in appearances {
            for (pageLabel, page) in [("scores", Page.scores), ("scores-highlights", Page.scores), ("leagues", Page.leagues), ("favorites", Page.favorites)] {
                store.page = page
                store.showsHighlightsOnly = pageLabel == "scores-highlights"
                let view = RootView(store: store)
                    .environment(\.colorScheme, scheme)
                    .environment(\.isSnapshotMode, true)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                var image: NSImage?
                NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
                    image = renderer.nsImage
                }
                guard let image, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:])
                else {
                    print("snapshot: failed to render \(label)-\(pageLabel)")
                    continue
                }
                let file = directory.appendingPathComponent("\(pageLabel)-\(label).png")
                try? png.write(to: file)
                print("snapshot: wrote \(file.path)")
            }
        }
    }
}
#endif
