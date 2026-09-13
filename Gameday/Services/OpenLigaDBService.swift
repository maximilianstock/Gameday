import Foundation

/// Scores and tables from OpenLigaDB (api.openligadb.de), a free community database, for
/// leagues ESPN doesn't cover (3. Liga). Results are entered by volunteers, so live scores can
/// lag behind and there is no match clock.
final class OpenLigaDBService: ScoreboardProviding {
    private let session: URLSession

    /// A game without a confirmed result counts as live for this long after kick-off.
    private static let liveWindow: TimeInterval = 135 * 60

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func sections(for league: League, day: Date, calendar: Calendar) async throws -> [ScoreSection] {
        guard let shortcut = league.openLigaDBShortcut else { return [] }
        // One request returns the whole season (380 games, about 16 KB).
        let season = Self.season(containing: day, calendar: calendar)
        let matches = try await Self.fetch([OLMatch].self, path: "getmatchdata/\(shortcut)/\(season)", session: session)
        let now = Date()
        let games = matches.compactMap { match -> Game? in
            guard let start = ESPNDate.parse(match.matchDateTimeUTC), calendar.isDate(start, inSameDayAs: day) else { return nil }
            return Self.game(from: match, league: league, start: start, now: now)
        }
        .sorted { ($0.startDate, $0.first.name) < ($1.startDate, $1.first.name) }
        guard !games.isEmpty else { return [] }
        return [ScoreSection(
            id: league.id,
            leagueID: league.id,
            sport: league.sport,
            title: league.name,
            subtitle: nil,
            logoURL: nil,
            priority: 0,
            subOrder: 0,
            games: games
        )]
    }

    static func standings(shortcut: String, season: Int?, session: URLSession) async throws -> Standings {
        let season = season ?? Self.season(containing: Date(), calendar: .current)
        let table = try await fetch([OLTableRow].self, path: "getbltable/\(shortcut)/\(season)", session: session)
        let rows = table.enumerated().map { index, entry in
            let position = index + 1
            let name = entry.teamName ?? "Unknown"
            return Standings.Row(
                id: teamID(entry.teamInfoId),
                position: position,
                rank: position,
                name: name,
                shortName: entry.shortName.flatMap { $0.isEmpty ? nil : $0 } ?? name,
                logoURL: logoURL(entry.teamIconUrl),
                gamesPlayed: entry.matches ?? 0,
                wins: entry.won ?? 0,
                draws: entry.draw ?? 0,
                losses: entry.lost ?? 0,
                goalDifference: entry.goalDiff ?? 0,
                points: entry.points ?? 0,
                winPercent: 0,
                zone: zone(shortcut: shortcut, position: position, teamCount: table.count)
            )
        }
        return Standings(
            seasonYear: season,
            seasonName: "\(season)-\(String(format: "%02d", (season + 1) % 100))",
            groups: rows.isEmpty ? [] : [Standings.Group(name: nil, rows: rows)],
            link: nil
        )
    }

    static func teamID(_ id: Int) -> String { "openligadb:t:\(id)" }

    static func isTeamID(_ id: String) -> Bool { id.hasPrefix("openligadb:") }

    // MARK: Mapping

    private static func game(from match: OLMatch, league: League, start: Date, now: Date) -> Game? {
        guard let homeName = match.team1.teamName, !homeName.isEmpty,
              let awayName = match.team2.teamName, !awayName.isEmpty else { return nil }

        let finished = match.matchIsFinished ?? false
        // Final result, or the latest known score while the game runs.
        let finalResult = match.matchResults?.first { $0.resultTypeID == 2 }
            ?? match.matchResults?.max { ($0.resultOrderID ?? 0) < ($1.resultOrderID ?? 0) }
        let latestGoal = match.goals?.max { ($0.goalID ?? 0) < ($1.goalID ?? 0) }
        let score: (Int, Int)?
        if finished, let home = finalResult?.pointsTeam1, let away = finalResult?.pointsTeam2 {
            score = (home, away)
        } else if let home = latestGoal?.scoreTeam1, let away = latestGoal?.scoreTeam2 {
            score = (home, away)
        } else if let home = finalResult?.pointsTeam1, let away = finalResult?.pointsTeam2 {
            score = (home, away)
        } else {
            score = nil
        }

        let phase: GamePhase
        let statusText: String?
        if finished {
            phase = .final
            statusText = "FT"
        } else if now < start {
            phase = .scheduled
            statusText = nil
        } else if now.timeIntervalSince(start) < liveWindow {
            phase = .live
            statusText = "Live"
        } else if score != nil {
            // Over, but not yet confirmed by the database.
            phase = .final
            statusText = "FT"
        } else {
            phase = .delayed
            statusText = "Pending"
        }

        var home = participant(match.team1, name: homeName, score: phase == .scheduled ? nil : score?.0)
        var away = participant(match.team2, name: awayName, score: phase == .scheduled ? nil : score?.1)
        if phase == .final, let score {
            home.isWinner = score.0 > score.1
            away.isWinner = score.1 > score.0
        }
        return Game(
            id: "\(league.id)#ol\(match.matchID)",
            leagueID: league.id,
            sport: league.sport,
            startDate: start,
            phase: phase,
            statusText: statusText,
            roundText: nil,
            first: home,
            second: away,
            link: nil,
            hasStartTime: true
        )
    }

    private static func participant(_ team: OLTeam, name: String, score: Int?) -> Participant {
        Participant(
            name: name,
            imageURL: logoURL(team.teamIconUrl),
            score: score.map(String.init),
            entityIDs: [teamID(team.teamId)]
        )
    }

    /// Club logos are Wikimedia thumbnails, usually 960 px wide. Ask for the 120 px size instead.
    private static func logoURL(_ string: String?) -> URL? {
        guard var string, !string.isEmpty else { return nil }
        if string.contains("/thumb/"), let range = string.range(of: #"/\d+px-"#, options: .regularExpression) {
            string.replaceSubrange(range, with: "/120px-")
        }
        return URL(string: string)
    }

    /// OpenLigaDB has no zone data; these follow the league rules.
    private static func zone(shortcut: String, position: Int, teamCount: Int) -> Standings.Zone? {
        guard shortcut == "bl3" else { return nil }
        switch position {
        case 1 ... 2: return Standings.Zone(description: "Promotion", color: 0x81D6AC)
        case 3: return Standings.Zone(description: "Promotion playoff", color: 0xB5E7CE)
        case (teamCount - 3)...: return Standings.Zone(description: "Relegation", color: 0xFF7F84)
        default: return nil
        }
    }

    /// Seasons are named by the year they start in; a new one starts in July.
    static func season(containing date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 2026
        return (components.month ?? 1) >= 7 ? year : year - 1
    }

    private static func fetch<T: Decodable>(_ type: T.Type, path: String, session: URLSession) async throws -> T {
        let url = URL(string: "https://api.openligadb.de/\(path)")!
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw ScoreboardError.badResponse(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ScoreboardError.decoding(error)
        }
    }
}

// MARK: - Payload

private struct OLMatch: Decodable {
    var matchID: Int
    var matchDateTimeUTC: String?
    var team1: OLTeam
    var team2: OLTeam
    var matchIsFinished: Bool?
    var matchResults: [OLResult]?
    var goals: [OLGoal]?
}

private struct OLTeam: Decodable {
    var teamId: Int
    var teamName: String?
    var shortName: String?
    var teamIconUrl: String?
}

private struct OLResult: Decodable {
    var pointsTeam1: Int?
    var pointsTeam2: Int?
    var resultOrderID: Int?
    /// 1 half time, 2 final result.
    var resultTypeID: Int?
}

private struct OLGoal: Decodable {
    var goalID: Int?
    var scoreTeam1: Int?
    var scoreTeam2: Int?
}

private struct OLTableRow: Decodable {
    var teamInfoId: Int
    var teamName: String?
    var shortName: String?
    var teamIconUrl: String?
    var points: Int?
    var matches: Int?
    var won: Int?
    var draw: Int?
    var lost: Int?
    var goalDiff: Int?
}
