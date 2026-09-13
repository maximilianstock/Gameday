import Foundation

/// Fetches league tables from ESPN and caches them in memory. Shared by the table page, the
/// table positions in the score list and the highlight engine, so each table is loaded once.
actor StandingsService {
    private let session: URLSession
    private var cache: [String: (fetchedAt: Date, standings: Standings)] = [:]
    private var running: [String: Task<Standings, Error>] = [:]

    /// The current table changes on every matchday; past seasons don't.
    static let currentMaxAge: TimeInterval = 5 * 60
    static let pastMaxAge: TimeInterval = 24 * 60 * 60

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// `season` nil means the current season. `maxAge` lets callers that don't need the latest
    /// positions reuse an older table.
    func standings(leagueID: String, season: Int? = nil, maxAge: TimeInterval? = nil) async throws -> Standings {
        let key = "\(leagueID)|\(season.map(String.init) ?? "current")"
        let maxAge = maxAge ?? (season == nil ? Self.currentMaxAge : Self.pastMaxAge)
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached.standings
        }
        if let task = running[key] { return try await task.value }
        let task = Task<Standings, Error> { [session] in
            var components = URLComponents(string: "https://site.api.espn.com/apis/v2/sports/\(leagueID)/standings")!
            if let season { components.queryItems = [URLQueryItem(name: "season", value: String(season))] }
            let (data, response) = try await session.data(from: components.url!)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                throw ScoreboardError.badResponse(http.statusCode)
            }
            let decoded: ESPNStandingsResponse
            do {
                decoded = try JSONDecoder().decode(ESPNStandingsResponse.self, from: data)
            } catch {
                throw ScoreboardError.decoding(error)
            }
            return Self.standings(from: decoded)
        }
        running[key] = task
        defer { running[key] = nil }
        let standings = try await task.value
        cache[key] = (Date(), standings)
        return standings
    }

    static func standings(from response: ESPNStandingsResponse) -> Standings {
        var groups: [(name: String?, standings: ESPNStandings)] = []
        func collect(_ group: ESPNStandingsGroup) {
            if let standings = group.standings, !(standings.entries ?? []).isEmpty {
                groups.append((group.name, standings))
            }
            for child in group.children ?? [] { collect(child) }
        }
        if let top = response.standings, !(top.entries ?? []).isEmpty { groups.append((nil, top)) }
        for child in response.children ?? [] { collect(child) }

        let result = groups.map { group in
            Standings.Group(name: group.name, rows: rows(from: group.standings.entries ?? []))
        }
        let first = groups.first?.standings
        return Standings(
            seasonYear: response.season?.year ?? Calendar.current.component(.year, from: Date()),
            seasonName: shortSeasonName(response.season?.displayName ?? first?.seasonDisplayName),
            groups: result,
            link: first?.links?.first { ($0.rel ?? []).contains("desktop") }?.href.flatMap(URL.init(string:))
        )
    }

    private static func rows(from entries: [ESPNStandingsEntry]) -> [Standings.Row] {
        var rows: [Standings.Row] = []
        for entry in entries {
            guard let team = entry.team, let id = EntityID.normalize(team.uid) else { continue }
            var stats: [String: Double] = [:]
            for stat in entry.stats ?? [] {
                if let name = stat.name, let value = stat.value { stats[name] = value }
            }
            let wins = stats["wins"] ?? 0
            let losses = stats["losses"] ?? 0
            let ties = stats["ties"] ?? 0
            let zone = entry.note.flatMap { note -> Standings.Zone? in
                guard let description = note.description, !description.isEmpty,
                      let color = note.color.flatMap(parseHex) else { return nil }
                return Standings.Zone(description: description, color: color)
            }
            let name = team.displayName ?? team.name ?? "Unknown"
            rows.append(Standings.Row(
                id: id,
                position: 0,
                rank: stats["rank"].flatMap { $0 > 0 ? Int($0) : nil },
                name: name,
                shortName: team.shortDisplayName ?? team.abbreviation ?? name,
                logoURL: (team.logos?.first?.href ?? team.logo).flatMap(URL.init(string:)),
                gamesPlayed: Int(stats["gamesPlayed"] ?? (wins + losses + ties)),
                wins: Int(wins),
                draws: Int(ties),
                losses: Int(losses),
                goalDifference: Int(stats["pointDifferential"] ?? stats["differential"] ?? 0),
                points: Int(stats["points"] ?? 0),
                winPercent: stats["winPercent"] ?? 0,
                zone: zone
            ))
        }
        // ESPN lists rows in table order; the rank stat, where present, is authoritative.
        if rows.allSatisfy({ $0.rank != nil }) {
            rows = rows.enumerated()
                .sorted { ($0.element.rank!, $0.offset) < ($1.element.rank!, $1.offset) }
                .map(\.element)
        }
        for index in rows.indices {
            rows[index].position = rows[index].rank ?? index + 1
        }
        return rows
    }

    /// "2026-27 German Bundesliga" → "2026-27", "2026 MLS" → "2026".
    private static func shortSeasonName(_ name: String?) -> String? {
        guard let name else { return nil }
        let first = name.split(separator: " ").first.map(String.init)
        guard let first, first.first?.isNumber == true else { return name }
        return first
    }

    private static func parseHex(_ string: String) -> UInt32? {
        let digits = string.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
    }
}
