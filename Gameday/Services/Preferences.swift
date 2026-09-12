import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class Preferences {
    private static let selectedLeaguesKey = "selectedLeagueIDs"
    private static let tennisQualifyingKey = "showsTennisQualifying"
    private static let favoritesKey = "favorites"

    private let defaults: UserDefaults

    /// Selected leagues, always kept in catalog order.
    private(set) var selectedLeagueIDs: [String]

    /// Qualifying rounds make up most of a tennis week and are hidden unless asked for.
    var showsTennisQualifying: Bool {
        didSet { defaults.set(showsTennisQualifying, forKey: Self.tennisQualifyingKey) }
    }

    private(set) var favorites: [Favorite]

    var favoriteIDs: Set<String> { Set(favorites.map(\.id)) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: Self.selectedLeaguesKey) as? [String] {
            selectedLeagueIDs = Self.normalized(stored)
        } else {
            selectedLeagueIDs = Self.normalized(LeagueCatalog.defaultSelection)
        }
        showsTennisQualifying = defaults.bool(forKey: Self.tennisQualifyingKey)
        if let data = defaults.data(forKey: Self.favoritesKey),
           let stored = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = stored
        } else {
            favorites = []
        }
    }

    func isFavorite(_ id: String) -> Bool {
        favorites.contains { $0.id == id }
    }

    func addFavorite(_ favorite: Favorite) {
        guard !isFavorite(favorite.id) else { return }
        favorites.append(favorite)
        saveFavorites()
    }

    func removeFavorite(id: String) {
        favorites.removeAll { $0.id == id }
        saveFavorites()
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: Self.favoritesKey)
        }
    }

    func isSelected(_ leagueID: String) -> Bool {
        selectedLeagueIDs.contains(leagueID)
    }

    func setLeague(_ leagueID: String, selected: Bool) {
        var ids = Set(selectedLeagueIDs)
        if selected { ids.insert(leagueID) } else { ids.remove(leagueID) }
        selectedLeagueIDs = Self.normalized(Array(ids))
        defaults.set(selectedLeagueIDs, forKey: Self.selectedLeaguesKey)
    }

    func resetLeaguesToDefaults() {
        selectedLeagueIDs = Self.normalized(LeagueCatalog.defaultSelection)
        defaults.set(selectedLeagueIDs, forKey: Self.selectedLeaguesKey)
    }

    private static func normalized(_ ids: [String]) -> [String] {
        Array(Set(ids))
            .filter { LeagueCatalog.league(id: $0) != nil }
            .sorted { LeagueCatalog.index(of: $0) < LeagueCatalog.index(of: $1) }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
