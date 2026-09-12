import Foundation
import Observation

enum Page: Hashable {
    case scores
    case leagues
    case favorites
}

/// Source of truth for what the popover shows: the selected day, the loaded sections and
/// the loading/error state. Everything runs on the main actor.
@MainActor
@Observable
final class ScoreboardStore {
    private(set) var selectedDay: Date
    private(set) var sections: [ScoreSection] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    /// Leagues whose last request failed. Stale data (if any) is still shown for them.
    private(set) var failedLeagueIDs: Set<String> = []
    /// Set when nothing at all could be loaded for the selected day.
    private(set) var loadError: String?
    /// Number of live games today, for the menu bar item. Updated even while another day is shown.
    private(set) var liveCountToday = 0
    var page: Page = .scores
    /// True while the popover is on screen; drives whether highlight animations run.
    var isPopoverShown = false

    let preferences: Preferences
    let calendar: Calendar
    let searchService = SearchService()

    private let service: ScoreboardProviding
    private let highlightEngine = HighlightEngine()
    private var cache: [String: CacheEntry] = [:]
    private var loadGeneration = 0
    /// Game ids the highlight engine has classified as top matches.
    private var topMatchIDs: Set<String> = []
    private var annotationTask: Task<Void, Never>?

    private struct CacheEntry {
        var sections: [ScoreSection]
        var fetchedAt: Date
    }

    /// Cached data younger than this is reused instead of refetched.
    private let freshness: TimeInterval = 45

    init(service: ScoreboardProviding, preferences: Preferences, calendar: Calendar = .current) {
        self.service = service
        self.preferences = preferences
        self.calendar = calendar
        self.selectedDay = calendar.startOfDay(for: Date())
    }

    // MARK: Derived state

    var selectedLeagues: [League] {
        preferences.selectedLeagueIDs.compactMap(LeagueCatalog.league(id:))
    }

    var isToday: Bool { calendar.isDateInToday(selectedDay) }

    var hasLiveGames: Bool { sections.contains { $0.liveCount > 0 } }

    var hasPartialFailure: Bool { !failedLeagueIDs.isEmpty && loadError == nil }

    var hasTopMatches: Bool { sections.contains { $0.games.contains(where: \.isTopMatch) } }

    var dayTitle: String {
        let dayPart = selectedDay.formatted(.dateTime.day().month(.abbreviated))
        if calendar.isDateInToday(selectedDay) { return "Today, \(dayPart)" }
        if calendar.isDateInYesterday(selectedDay) { return "Yesterday, \(dayPart)" }
        if calendar.isDateInTomorrow(selectedDay) { return "Tomorrow, \(dayPart)" }
        if calendar.isDate(selectedDay, equalTo: Date(), toGranularity: .year) {
            return selectedDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return selectedDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    // MARK: Navigation

    func goToPreviousDay() { moveSelectedDay(by: -1) }

    func goToNextDay() { moveSelectedDay(by: 1) }

    func goToToday() {
        select(day: Date())
    }

    private func moveSelectedDay(by days: Int) {
        guard let day = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        select(day: day)
    }

    private func select(day: Date) {
        let newDay = calendar.startOfDay(for: day)
        guard newDay != selectedDay else { return }
        selectedDay = newDay
        loadError = nil
        failedLeagueIDs = []
        // Show whatever is cached immediately so navigation feels instant.
        sections = assemble(cachedResults(for: newDay), leagues: selectedLeagues)
        annotateTopMatches(for: newDay)
        Task { await load(day: newDay, force: false, publish: true) }
    }

    // MARK: Loading

    func refresh() async {
        await load(day: selectedDay, force: true, publish: true)
    }

    func refreshIfStale(maxAge: TimeInterval) {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge, loadError == nil { return }
        Task { await load(day: selectedDay, force: false, publish: true) }
    }

    /// Refreshes today's games in the background so the menu bar live count stays current.
    func refreshToday() async {
        let today = calendar.startOfDay(for: Date())
        await load(day: today, force: true, publish: isToday)
    }

    func setLeague(_ leagueID: String, selected: Bool) {
        preferences.setLeague(leagueID, selected: selected)
        leaguesDidChange()
    }

    func resetLeaguesToDefaults() {
        preferences.resetLeaguesToDefaults()
        leaguesDidChange()
    }

    func setShowsTennisQualifying(_ shows: Bool) {
        preferences.showsTennisQualifying = shows
        leaguesDidChange()
    }

    private func leaguesDidChange() {
        sections = assemble(cachedResults(for: selectedDay), leagues: selectedLeagues)
        annotateTopMatches(for: selectedDay)
        Task { await load(day: selectedDay, force: false, publish: true) }
    }

    // MARK: Favourites

    func addFavorite(_ favorite: Favorite) {
        preferences.addFavorite(favorite)
        sections = applyFlags(sections)
    }

    func removeFavorite(id: String) {
        preferences.removeFavorite(id: id)
        sections = applyFlags(sections)
    }

    // MARK: Highlights

    /// Runs the highlight engine over the current sections and re-publishes once it knows more.
    private func annotateTopMatches(for day: Date) {
        annotationTask?.cancel()
        let snapshot = sections
        guard snapshot.contains(where: { !$0.games.isEmpty }) else { return }
        annotationTask = Task { [highlightEngine] in
            let annotated = await highlightEngine.annotate(snapshot)
            guard !Task.isCancelled else { return }
            for section in annotated {
                for game in section.games {
                    if game.isTopMatch { topMatchIDs.insert(game.id) } else { topMatchIDs.remove(game.id) }
                }
            }
            if calendar.isDate(day, inSameDayAs: selectedDay) {
                sections = applyFlags(sections)
            }
        }
    }

    private func applyFlags(_ sections: [ScoreSection]) -> [ScoreSection] {
        let favorites = preferences.favoriteIDs
        var result = sections
        for sectionIndex in result.indices {
            for gameIndex in result[sectionIndex].games.indices {
                var game = result[sectionIndex].games[gameIndex]
                game.isTopMatch = topMatchIDs.contains(game.id)
                game.first.isFavorite = game.first.entityIDs.contains { favorites.contains($0) }
                game.second.isFavorite = game.second.entityIDs.contains { favorites.contains($0) }
                result[sectionIndex].games[gameIndex] = game
            }
        }
        return result
    }

    /// Waits for the running highlight classification, if any.
    func waitForHighlights() async {
        await annotationTask?.value
    }

    #if DEBUG
    var debugSearchQuery: String?

    func debugMarkTopMatches(_ ids: Set<String>) {
        annotationTask?.cancel()
        annotationTask = nil
        topMatchIDs = ids
        sections = applyFlags(sections)
    }
    #endif

    private func load(day: Date, force: Bool, publish: Bool) async {
        let leagues = selectedLeagues
        guard !leagues.isEmpty else {
            if publish {
                sections = []
                loadError = nil
                failedLeagueIDs = []
                lastUpdated = Date()
            }
            if calendar.isDateInToday(day) { liveCountToday = 0 }
            return
        }

        // Only loads that publish take part in the generation check; a background refresh must
        // never cancel or discard a load the user is waiting for.
        var generation = loadGeneration
        if publish {
            loadGeneration += 1
            generation = loadGeneration
            isLoading = true
        }
        defer { if publish, generation == loadGeneration { isLoading = false } }

        var results: [String: [ScoreSection]] = [:]
        var failures: Set<String> = []
        var didFetch = false
        let now = Date()
        let service = self.service
        let calendar = self.calendar

        await withTaskGroup(of: (String, Result<[ScoreSection], Error>).self) { group in
            for league in leagues {
                let key = cacheKey(league: league, day: day)
                if !force, let entry = cache[key], now.timeIntervalSince(entry.fetchedAt) < freshness {
                    results[league.id] = entry.sections
                    continue
                }
                didFetch = true
                group.addTask {
                    do {
                        let sections = try await service.sections(for: league, day: day, calendar: calendar)
                        return (league.id, .success(sections))
                    } catch {
                        return (league.id, .failure(error))
                    }
                }
            }
            for await (leagueID, result) in group {
                let key = "\(leagueID)|\(dayKey(day))"
                switch result {
                case .success(let sections):
                    results[leagueID] = sections
                    cache[key] = CacheEntry(sections: sections, fetchedAt: Date())
                case .failure:
                    failures.insert(leagueID)
                    if let stale = cache[key] { results[leagueID] = stale.sections }
                }
            }
        }

        if calendar.isDateInToday(day) {
            liveCountToday = assemble(results, leagues: leagues).reduce(0) { $0 + $1.liveCount }
        }

        guard publish, generation == loadGeneration, calendar.isDate(day, inSameDayAs: selectedDay) else { return }

        sections = assemble(results, leagues: leagues)
        failedLeagueIDs = failures
        let everythingFailed = failures.count == leagues.count && results.isEmpty
        loadError = everythingFailed ? "Couldn't load scores" : nil
        if !everythingFailed, didFetch || lastUpdated == nil { lastUpdated = Date() }
        annotateTopMatches(for: day)
    }

    // MARK: Assembly

    private func cachedResults(for day: Date) -> [String: [ScoreSection]] {
        var results: [String: [ScoreSection]] = [:]
        for league in selectedLeagues {
            if let entry = cache[cacheKey(league: league, day: day)] {
                results[league.id] = entry.sections
            }
        }
        return results
    }

    /// Orders sections by catalog order, groups tennis tournaments together and removes
    /// duplicates that appear in both the ATP and WTA feeds (combined events, mixed doubles).
    private func assemble(_ results: [String: [ScoreSection]], leagues: [League]) -> [ScoreSection] {
        var ordered: [ScoreSection] = []
        var tennis: [ScoreSection] = []
        var seen: Set<String> = []
        let showsQualifying = preferences.showsTennisQualifying
        for league in leagues {
            for var section in results[league.id] ?? [] {
                guard seen.insert(section.id).inserted else { continue }
                if section.sport == .tennis {
                    if !showsQualifying {
                        section.games.removeAll { ($0.roundText ?? "").hasPrefix("Q") }
                        if section.games.isEmpty { continue }
                    }
                    tennis.append(section)
                } else {
                    ordered.append(section)
                }
            }
        }
        tennis.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            if a.title != b.title { return a.title < b.title }
            return a.subOrder < b.subOrder
        }
        // Tennis stays where its sport sits in the catalog order.
        if let insertIndex = ordered.firstIndex(where: { LeagueCatalog.index(of: $0.leagueID) > LeagueCatalog.index(of: "tennis/atp") }) {
            ordered.insert(contentsOf: tennis, at: insertIndex)
        } else {
            ordered.append(contentsOf: tennis)
        }
        return applyFlags(ordered)
    }

    private func cacheKey(league: League, day: Date) -> String {
        "\(league.id)|\(dayKey(day))"
    }

    private func dayKey(_ day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
