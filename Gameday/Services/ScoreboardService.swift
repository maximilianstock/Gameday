import Foundation

protocol ScoreboardProviding: Sendable {
    /// Sections (with games) for one league on one local calendar day.
    func sections(for league: League, day: Date, calendar: Calendar) async throws -> [ScoreSection]
}

enum ScoreboardError: LocalizedError {
    case badResponse(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "The scores server answered with status \(code)."
        case .decoding: return "The scores server sent data Gameday couldn't read."
        }
    }
}

final class ESPNScoreboardService: ScoreboardProviding {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: configuration)
    }

    func sections(for league: League, day: Date, calendar: Calendar) async throws -> [ScoreSection] {
        let url = Self.endpoint(for: league, day: day, calendar: calendar)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw ScoreboardError.badResponse(http.statusCode)
        }
        let board: ESPNScoreboard
        do {
            board = try JSONDecoder().decode(ESPNScoreboard.self, from: data)
        } catch {
            throw ScoreboardError.decoding(error)
        }
        return ESPNMapper.sections(from: board, league: league, day: day, calendar: calendar)
    }

    /// ESPN's day boundaries follow US Eastern time. For team sports the neighbouring days are
    /// requested too and filtered locally, which makes the result correct in every time zone.
    /// The tennis feed answers date ranges incompletely, but a single day returns every
    /// tournament active on that day with its full draw, so tennis asks for one day only.
    static func endpoint(for league: League, day: Date, calendar: Calendar) -> URL {
        let dates: String
        if league.sport == .tennis {
            dates = ESPNDate.requestString(for: day)
        } else {
            let from = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let to = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            dates = "\(ESPNDate.requestString(for: from))-\(ESPNDate.requestString(for: to))"
        }
        var components = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.espnPath)/scoreboard")!
        components.queryItems = [URLQueryItem(name: "dates", value: dates)]
        return components.url!
    }
}

enum ESPNMapper {
    static func sections(from board: ESPNScoreboard, league: League, day: Date, calendar: Calendar) -> [ScoreSection] {
        if league.sport == .tennis {
            return tennisSections(from: board, league: league, day: day, calendar: calendar)
        }
        let logoURL = board.leagues?.first?.logos?.first?.href.flatMap(URL.init(string:))
        var games: [Game] = []
        for event in board.events ?? [] {
            guard let competition = event.competitions?.first,
                  let start = ESPNDate.parse(competition.date ?? event.date),
                  calendar.isDate(start, inSameDayAs: day),
                  let game = teamGame(event: event, competition: competition, league: league, start: start)
            else { continue }
            games.append(game)
        }
        guard !games.isEmpty else { return [] }
        games.sort(by: chronological)
        return [ScoreSection(
            id: league.id,
            leagueID: league.id,
            sport: league.sport,
            title: league.name,
            subtitle: nil,
            logoURL: logoURL,
            priority: 0,
            subOrder: 0,
            games: games
        )]
    }

    // MARK: Team sports

    private static func teamGame(event: ESPNEvent, competition: ESPNCompetition, league: League, start: Date) -> Game? {
        let competitors = competition.competitors ?? []
        guard competitors.count >= 2 else { return nil }
        let home = competitors.first { $0.homeAway == "home" } ?? competitors[0]
        let away = competitors.first { $0.homeAway == "away" } ?? competitors[1]

        let status = competition.status ?? event.status
        let (phase, statusText) = phaseAndText(status: status, sport: league.sport)

        var homeParticipant = teamParticipant(home, phase: phase)
        var awayParticipant = teamParticipant(away, phase: phase)
        if phase == .final, !homeParticipant.isWinner, !awayParticipant.isWinner,
           let homeScore = Int(homeParticipant.score ?? ""), let awayScore = Int(awayParticipant.score ?? "") {
            homeParticipant.isWinner = homeScore > awayScore
            awayParticipant.isWinner = awayScore > homeScore
        }

        guard !isPlaceholder(homeParticipant.name), !isPlaceholder(awayParticipant.name) else { return nil }

        let awayFirst = league.sport.listsAwayTeamFirst
        return Game(
            id: "\(league.id)#\(event.id)",
            leagueID: league.id,
            sport: league.sport,
            startDate: start,
            phase: phase,
            statusText: statusText,
            roundText: nil,
            first: awayFirst ? awayParticipant : homeParticipant,
            second: awayFirst ? homeParticipant : awayParticipant,
            link: link(from: event.links),
            hasStartTime: competition.timeValid ?? true
        )
    }

    private static func teamParticipant(_ competitor: ESPNCompetitor, phase: GamePhase) -> Participant {
        let team = competitor.team
        let name = team?.displayName ?? team?.name ?? team?.shortDisplayName ?? "Unknown"
        let showsScore = phase != .scheduled && phase != .postponed && phase != .canceled
        return Participant(
            name: name,
            imageURL: team?.logo.flatMap(URL.init(string:)),
            score: showsScore ? (competitor.score?.display ?? "0") : nil,
            sets: [],
            isWinner: competitor.winner ?? false,
            seed: nil,
            imageIsFlag: false,
            entityIDs: [EntityID.normalize(team?.uid ?? competitor.uid)].compactMap { $0 }
        )
    }

    // MARK: Tennis

    private static func tennisSections(from board: ESPNScoreboard, league: League, day: Date, calendar: Calendar) -> [ScoreSection] {
        let allowedPrefixes = league.id.hasSuffix("atp") ? ["mens", "mixed"] : ["womens", "mixed"]
        var sections: [ScoreSection] = []
        for event in board.events ?? [] {
            for (groupingIndex, grouping) in (event.groupings ?? []).enumerated() {
                let slug = grouping.grouping?.slug ?? ""
                guard allowedPrefixes.contains(where: { slug.hasPrefix($0) }) else { continue }
                var games: [Game] = []
                for competition in grouping.competitions ?? [] {
                    guard let start = ESPNDate.parse(competition.date),
                          calendar.isDate(start, inSameDayAs: day),
                          let game = tennisGame(competition: competition, event: event, league: league, start: start)
                    else { continue }
                    games.append(game)
                }
                guard !games.isEmpty else { continue }
                games.sort(by: chronological)
                // Grand Slams first, then tournaments whose most important round is furthest along.
                let bestRound = games.map { roundRank($0.roundText) }.min() ?? 9
                let priority = ((event.major ?? false) ? 0 : 10) + bestRound
                sections.append(ScoreSection(
                    id: "tennis#\(event.id)#\(slug)",
                    leagueID: league.id,
                    sport: .tennis,
                    title: event.shortName ?? event.name ?? "Tennis",
                    subtitle: grouping.grouping?.displayName,
                    logoURL: nil,
                    priority: priority,
                    subOrder: groupingIndex,
                    games: games
                ))
            }
        }
        return sections
    }

    private static func tennisGame(competition: ESPNCompetition, event: ESPNEvent, league: League, start: Date) -> Game? {
        let competitors = (competition.competitors ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        guard competitors.count >= 2 else { return nil }
        let (phase, statusText) = phaseAndText(status: competition.status, sport: .tennis)
        let first = tennisParticipant(competitors[0])
        let second = tennisParticipant(competitors[1])
        guard !isPlaceholder(first.name), !isPlaceholder(second.name) else { return nil }
        return Game(
            id: "tennis#\(competition.id)",
            leagueID: league.id,
            sport: .tennis,
            startDate: start,
            phase: phase,
            statusText: statusText,
            roundText: roundAbbreviation(competition.round?.displayName),
            first: first,
            second: second,
            link: link(from: event.links),
            hasStartTime: competition.timeValid ?? true,
            isMajor: event.major ?? false
        )
    }

    private static func tennisParticipant(_ competitor: ESPNCompetitor) -> Participant {
        let name: String
        let flag: String?
        var entityIDs: [String] = []
        if let roster = competitor.roster {
            name = roster.shortDisplayName ?? roster.displayName ?? "Unknown"
            flag = roster.athletes?.first?.flag?.href
            for athlete in roster.athletes ?? [] {
                if let id = athlete.id ?? EntityID.athleteID(fromLink: athlete.links?.first?.href) {
                    entityIDs.append(EntityID.tennisPlayer(id: id))
                }
            }
        } else {
            name = competitor.athlete?.shortName ?? competitor.athlete?.displayName ?? "Unknown"
            flag = competitor.athlete?.flag?.href
            if let id = competitor.athlete?.id ?? competitor.id ?? EntityID.athleteID(fromLink: competitor.athlete?.links?.first?.href) {
                entityIDs.append(EntityID.tennisPlayer(id: id))
            }
        }
        let sets = (competitor.linescores ?? []).map { line in
            SetScore(games: Int(line.value ?? 0), tiebreak: line.tiebreak, won: line.winner)
        }
        let seed = competitor.curatedRank?.current.flatMap { $0 > 0 && $0 <= 64 ? $0 : nil }
        return Participant(
            name: name,
            imageURL: flag.flatMap(URL.init(string:)),
            score: nil,
            sets: sets,
            isWinner: competitor.winner ?? false,
            seed: seed,
            imageIsFlag: true,
            entityIDs: entityIDs
        )
    }

    static func roundAbbreviation(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let lower = name.lowercased()
        if lower == "final" || lower == "finals" { return "F" }
        if lower.contains("semifinal") { return "SF" }
        if lower.contains("quarterfinal") { return "QF" }
        if lower.contains("round robin") { return "RR" }
        let digits = lower.filter(\.isNumber)
        if lower.hasPrefix("round of"), !digits.isEmpty { return "R\(digits)" }
        if lower.contains("qualifying") { return digits.isEmpty ? "Q" : "Q\(digits)" }
        if lower.contains("round"), !digits.isEmpty { return "R\(digits)" }
        return name
    }

    /// 0 for a final, rising towards qualifying rounds.
    static func roundRank(_ abbreviation: String?) -> Int {
        switch abbreviation {
        case "F": return 0
        case "SF": return 1
        case "QF": return 2
        case "R16": return 3
        case "R32": return 4
        case "R64": return 5
        case "R128": return 6
        case "RR": return 7
        case let value? where value.hasPrefix("Q"): return 8
        default: return 9
        }
    }

    // MARK: Status

    static func phaseAndText(status: ESPNStatus?, sport: Sport) -> (GamePhase, String?) {
        let typeName = status?.type?.name ?? ""
        let state = status?.type?.state ?? "pre"
        let shortDetail = status?.type?.shortDetail ?? ""
        let clock = status?.displayClock ?? ""
        let period = status?.period ?? 0

        switch typeName {
        case "STATUS_POSTPONED": return (.postponed, "Postponed")
        case "STATUS_CANCELED", "STATUS_CANCELLED": return (.canceled, "Cancelled")
        case "STATUS_ABANDONED": return (.canceled, "Abandoned")
        case "STATUS_DELAYED", "STATUS_RAIN_DELAY": return (.delayed, "Delayed")
        case "STATUS_SUSPENDED": return (.suspended, "Suspended")
        case "STATUS_HALFTIME": return (.live, "HT")
        default: break
        }

        switch state {
        case "in":
            switch sport {
            case .soccer:
                return (.live, clock.isEmpty ? "Live" : clock)
            case .tennis:
                return (.live, period > 0 ? "Set \(period)" : "Live")
            case .americanFootball, .basketball:
                let label = period <= 4 ? "Q\(period)" : (period == 5 ? "OT" : "\(period - 4)OT")
                if typeName == "STATUS_END_PERIOD" { return (.live, "End \(label)") }
                return (.live, clock.isEmpty ? label : "\(label) \(clock)")
            case .hockey:
                let label = period <= 3 ? "P\(period)" : "OT"
                if typeName == "STATUS_END_PERIOD" { return (.live, "End \(label)") }
                return (.live, clock.isEmpty ? label : "\(label) \(clock)")
            case .baseball:
                return (.live, shortDetail.isEmpty ? "Live" : shortDetail)
            }
        case "post":
            switch sport {
            case .soccer:
                if typeName == "STATUS_FINAL_PEN" { return (.final, "Pens") }
                if typeName == "STATUS_FINAL_AET" { return (.final, "AET") }
                return (.final, "FT")
            case .tennis:
                return (.final, "Final")
            default:
                return (.final, shortDetail.hasPrefix("Final") ? shortDetail : "Final")
            }
        default:
            return (.scheduled, nil)
        }
    }

    // MARK: Helpers

    /// ESPN lists undecided slots in draws and cup ties as "TBD" (doubles: "TBD / TBD").
    static func isPlaceholder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Unknown" { return true }
        let tokens = trimmed.uppercased().split(whereSeparator: { $0 == " " || $0 == "/" })
        if tokens.contains("TBD") || tokens.contains("TBA") { return true }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("winner of") || lower.hasPrefix("loser of") || lower.hasPrefix("qualifier")
    }

    private static func link(from links: [ESPNLink]?) -> URL? {
        guard let links else { return nil }
        let preferred = links.first { ($0.rel ?? []).contains("desktop") } ?? links.first
        return preferred?.href.flatMap(URL.init(string:))
    }

    private static func chronological(_ a: Game, _ b: Game) -> Bool {
        if a.startDate != b.startDate { return a.startDate < b.startDate }
        return a.first.name < b.first.name
    }
}
