import Foundation

/// Decides which games are "top matches": both sides are top teams by the current table
/// (or last season's while the current one is too young), or top-ranked tennis players.
/// Standings come from the shared standings service; rankings are fetched lazily and cached in memory.
actor HighlightEngine {
    struct Table: Sendable {
        struct Entry: Sendable {
            var rank: Int
            var gamesPlayed: Int
        }
        var seasonYear: Int
        var entries: [String: Entry]   // key: normalised team uid
    }

    private let session: URLSession
    private let standingsService: StandingsService
    private var rankings: [String: (fetchedAt: Date, ranks: [String: Int])] = [:]
    private var rankingTasks: [String: Task<[String: Int], Error>] = [:]

    private let rankingTTL: TimeInterval = 24 * 60 * 60

    /// Domestic leagues used to judge teams in cup competitions.
    private static let domesticSoccerLeagues = ["soccer/ger.1", "soccer/eng.1", "soccer/esp.1", "soccer/ita.1", "soccer/fra.1", "soccer/ned.1", "soccer/por.1"]
    private static let uefaCompetitions: Set<String> = ["soccer/uefa.champions", "soccer/uefa.europa", "soccer/uefa.europa.conf"]
    private static let domesticCups: Set<String> = ["soccer/ger.dfb_pokal", "soccer/eng.fa"]

    init(standingsService: StandingsService) {
        self.standingsService = standingsService
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // MARK: Annotation

    func annotate(_ sections: [ScoreSection]) async -> [ScoreSection] {
        var result = sections
        for sectionIndex in result.indices {
            for gameIndex in result[sectionIndex].games.indices {
                let game = result[sectionIndex].games[gameIndex]
                result[sectionIndex].games[gameIndex].isTopMatch = await isTopMatch(game)
            }
        }
        return result
    }

    func isTopMatch(_ game: Game) async -> Bool {
        switch game.sport {
        case .tennis:
            return await isTennisTopMatch(game)
        case .soccer:
            // National teams have no club table to judge them by.
            if LeagueCatalog.league(id: game.leagueID)?.isInternational == true { return false }
            if Self.uefaCompetitions.contains(game.leagueID) {
                if let byTable = await bothInTop(8, game: game, leagueID: game.leagueID, minGames: 3) { return byTable }
                return await bothDomesticTop(4, game: game)
            }
            if Self.domesticCups.contains(game.leagueID) {
                return await bothDomesticTop(4, game: game)
            }
            return await bothInTop(4, game: game, leagueID: game.leagueID, minGames: 6, fallbackToPreviousSeason: true) ?? false
        case .americanFootball:
            guard game.leagueID == "football/nfl" else { return false }
            return await bothInTop(8, game: game, leagueID: game.leagueID, minGames: 4, fallbackToPreviousSeason: true) ?? false
        case .basketball:
            guard game.leagueID == "basketball/nba" else { return false }
            return await bothInTop(8, game: game, leagueID: game.leagueID, minGames: 10, fallbackToPreviousSeason: true) ?? false
        case .hockey:
            return await bothInTop(8, game: game, leagueID: game.leagueID, minGames: 10, fallbackToPreviousSeason: true) ?? false
        case .baseball:
            return await bothInTop(8, game: game, leagueID: game.leagueID, minGames: 20, fallbackToPreviousSeason: true) ?? false
        }
    }

    // MARK: Rules

    /// Both teams within the top `n` of the league table. Returns nil when the table can't be
    /// used (not loaded, or too few games and no fallback), so callers can try another rule.
    private func bothInTop(_ n: Int, game: Game, leagueID: String, minGames: Int, fallbackToPreviousSeason: Bool = false) async -> Bool? {
        guard let first = game.first.entityIDs.first, let second = game.second.entityIDs.first else { return nil }
        guard let current = try? await table(leagueID: leagueID, season: nil) else { return nil }
        let firstEntry = current.entries[first]
        let secondEntry = current.entries[second]
        let matured = (firstEntry?.gamesPlayed ?? 0) >= minGames && (secondEntry?.gamesPlayed ?? 0) >= minGames
        if matured, let a = firstEntry, let b = secondEntry {
            return a.rank <= n && b.rank <= n
        }
        guard fallbackToPreviousSeason,
              let previous = try? await table(leagueID: leagueID, season: current.seasonYear - 1),
              let a = previous.entries[first], let b = previous.entries[second]
        else { return nil }
        return a.rank <= n && b.rank <= n
    }

    /// Both teams within the top `n` of their own domestic league (current table when mature,
    /// otherwise last season's).
    private func bothDomesticTop(_ n: Int, game: Game) async -> Bool {
        guard let first = game.first.entityIDs.first, let second = game.second.entityIDs.first else { return false }
        guard let a = await domesticRank(teamID: first), let b = await domesticRank(teamID: second) else { return false }
        return a <= n && b <= n
    }

    private func domesticRank(teamID: String) async -> Int? {
        for leagueID in Self.domesticSoccerLeagues {
            guard let current = try? await table(leagueID: leagueID, season: nil) else { continue }
            if let entry = current.entries[teamID] {
                if entry.gamesPlayed >= 6 { return entry.rank }
                if let previous = try? await table(leagueID: leagueID, season: current.seasonYear - 1),
                   let previousEntry = previous.entries[teamID] {
                    return previousEntry.rank
                }
                return nil
            }
        }
        return nil
    }

    private func isTennisTopMatch(_ game: Game) async -> Bool {
        let round = game.roundText ?? ""
        if game.isMajor, round == "F" || round == "SF" { return true }
        guard let first = game.first.entityIDs.first, let second = game.second.entityIDs.first else { return false }
        let atp = (try? await rankings(leagueID: "tennis/atp")) ?? [:]
        let wta = (try? await rankings(leagueID: "tennis/wta")) ?? [:]
        guard let a = atp[first] ?? wta[first], let b = atp[second] ?? wta[second] else { return false }
        if a <= 10 && b <= 10 { return true }
        if round == "F", a <= 20, b <= 20 { return true }
        return false
    }

    // MARK: Standings

    func table(leagueID: String, season: Int?) async throws -> Table {
        // Top matches don't hinge on the latest matchday, so an older table is fine.
        Self.buildTable(from: try await standingsService.standings(leagueID: leagueID, season: season, maxAge: 6 * 60 * 60))
    }

    private static func buildTable(from standings: Standings) -> Table {
        let rows = standings.groups.flatMap(\.rows)
        var entries: [String: Table.Entry] = [:]
        let singleTableWithRanks = standings.groups.count == 1 && rows.allSatisfy { $0.rank != nil }
        if singleTableWithRanks {
            for row in rows { entries[row.id] = Table.Entry(rank: row.rank ?? 0, gamesPlayed: row.gamesPlayed) }
        } else {
            // Several conferences or no rank stat: order league-wide.
            let ordered = rows.sorted { a, b in
                if a.winPercent != b.winPercent { return a.winPercent > b.winPercent }
                if a.points != b.points { return a.points > b.points }
                return a.goalDifference > b.goalDifference
            }
            for (index, row) in ordered.enumerated() {
                entries[row.id] = Table.Entry(rank: index + 1, gamesPlayed: row.gamesPlayed)
            }
        }
        return Table(seasonYear: standings.seasonYear, entries: entries)
    }

    // MARK: Rankings

    func rankings(leagueID: String) async throws -> [String: Int] {
        if let cached = rankings[leagueID], Date().timeIntervalSince(cached.fetchedAt) < rankingTTL {
            return cached.ranks
        }
        if let running = rankingTasks[leagueID] { return try await running.value }
        let task = Task<[String: Int], Error> { [session] in
            let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(leagueID)/rankings")!
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                throw ScoreboardError.badResponse(http.statusCode)
            }
            let decoded = try JSONDecoder().decode(ESPNRankingsResponse.self, from: data)
            var ranks: [String: Int] = [:]
            for entry in decoded.rankings?.first?.ranks ?? [] {
                guard let rank = entry.current,
                      let id = entry.athlete?.id ?? EntityID.athleteID(fromLink: entry.athlete?.links?.first?.href)
                else { continue }
                ranks[EntityID.tennisPlayer(id: id)] = rank
            }
            return ranks
        }
        rankingTasks[leagueID] = task
        defer { rankingTasks[leagueID] = nil }
        let ranks = try await task.value
        rankings[leagueID] = (Date(), ranks)
        return ranks
    }
}
