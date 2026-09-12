#if DEBUG
import Foundation

/// Static sample data for offline rendering (`--snapshot <dir>`).
enum Fixtures {
    static func logo(_ sport: String, _ id: String) -> URL {
        URL(string: "https://a.espncdn.com/i/teamlogos/\(sport)/500/\(id).png")!
    }

    static func flag(_ code: String) -> URL {
        URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/\(code).png")!
    }

    static func time(_ hour: Int, _ minute: Int, day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func sections(for league: League, day: Date, calendar: Calendar) -> [ScoreSection] {
        switch league.id {
        case "soccer/ger.1":
            return [ScoreSection(id: league.id, leagueID: league.id, sport: .soccer, title: "Bundesliga", subtitle: nil,
                                 logoURL: URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500/10.png"), priority: 0, subOrder: 0, games: [
                Game(id: "g1", leagueID: league.id, sport: .soccer, startDate: time(15, 30, day: day, calendar: calendar), phase: .final, statusText: "FT", roundText: nil,
                     first: Participant(name: "Borussia Dortmund", imageURL: logo("soccer", "124"), score: "2", isWinner: true),
                     second: Participant(name: "SC Paderborn 07", imageURL: logo("soccer", "3307"), score: "1"),
                     link: nil, hasStartTime: true),
                Game(id: "g2", leagueID: league.id, sport: .soccer, startDate: time(18, 30, day: day, calendar: calendar), phase: .live, statusText: "67'", roundText: nil,
                     first: Participant(name: "FC Bayern München", imageURL: logo("soccer", "132"), score: "1", entityIDs: ["s:600~t:132"]),
                     second: Participant(name: "RB Leipzig", imageURL: logo("soccer", "11420"), score: "1"),
                     link: nil, hasStartTime: true),
                Game(id: "g3", leagueID: league.id, sport: .soccer, startDate: time(20, 30, day: day, calendar: calendar), phase: .scheduled, statusText: nil, roundText: nil,
                     first: Participant(name: "Eintracht Frankfurt", imageURL: logo("soccer", "125")),
                     second: Participant(name: "VfB Stuttgart", imageURL: logo("soccer", "134")),
                     link: nil, hasStartTime: true),
            ])]
        case "football/nfl":
            return [ScoreSection(id: league.id, leagueID: league.id, sport: .americanFootball, title: "NFL", subtitle: nil,
                                 logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/leagues/500/nfl.png"), priority: 0, subOrder: 0, games: [
                Game(id: "n1", leagueID: league.id, sport: .americanFootball, startDate: time(19, 0, day: day, calendar: calendar), phase: .live, statusText: "Q3 4:12", roundText: nil,
                     first: Participant(name: "Tampa Bay Buccaneers", imageURL: logo("nfl", "tb"), score: "17"),
                     second: Participant(name: "Cincinnati Bengals", imageURL: logo("nfl", "cin"), score: "21"),
                     link: nil, hasStartTime: true),
                Game(id: "n2", leagueID: league.id, sport: .americanFootball, startDate: time(22, 25, day: day, calendar: calendar), phase: .scheduled, statusText: nil, roundText: nil,
                     first: Participant(name: "Kansas City Chiefs", imageURL: logo("nfl", "kc")),
                     second: Participant(name: "Buffalo Bills", imageURL: logo("nfl", "buf")),
                     link: nil, hasStartTime: true),
            ])]
        case "basketball/nba":
            return [ScoreSection(id: league.id, leagueID: league.id, sport: .basketball, title: "NBA", subtitle: nil,
                                 logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/leagues/500/nba.png"), priority: 0, subOrder: 0, games: [
                Game(id: "b1", leagueID: league.id, sport: .basketball, startDate: time(1, 30, day: day, calendar: calendar), phase: .final, statusText: "Final/OT", roundText: nil,
                     first: Participant(name: "Minnesota Timberwolves", imageURL: logo("nba", "min"), score: "103"),
                     second: Participant(name: "Oklahoma City Thunder", imageURL: logo("nba", "okc"), score: "116", isWinner: true),
                     link: nil, hasStartTime: true),
            ])]
        case "tennis/atp":
            return [
                ScoreSection(id: "tennis#189#womens-singles", leagueID: league.id, sport: .tennis, title: "US Open", subtitle: "Women's Singles", logoURL: nil, priority: 0, subOrder: 1, games: [
                    Game(id: "t1", leagueID: league.id, sport: .tennis, startDate: time(22, 0, day: day, calendar: calendar), phase: .live, statusText: "Set 3", roundText: "F",
                         first: Participant(name: "A. Sabalenka", imageURL: flag("blr"), sets: [SetScore(games: 6, tiebreak: nil, won: true), SetScore(games: 4, tiebreak: nil, won: false), SetScore(games: 3, tiebreak: nil, won: nil)], seed: 1, imageIsFlag: true),
                         second: Participant(name: "E. Rybakina", imageURL: flag("kaz"), sets: [SetScore(games: 3, tiebreak: nil, won: false), SetScore(games: 6, tiebreak: nil, won: true), SetScore(games: 2, tiebreak: nil, won: nil)], seed: 2, imageIsFlag: true),
                         link: nil, hasStartTime: true),
                ]),
                ScoreSection(id: "tennis#189#mens-singles", leagueID: league.id, sport: .tennis, title: "US Open", subtitle: "Men's Singles", logoURL: nil, priority: 0, subOrder: 0, games: [
                    Game(id: "t2", leagueID: league.id, sport: .tennis, startDate: time(18, 0, day: day, calendar: calendar), phase: .final, statusText: "Final", roundText: "SF",
                         first: Participant(name: "B. Shelton", imageURL: flag("usa"), sets: [SetScore(games: 4, tiebreak: nil, won: false), SetScore(games: 6, tiebreak: nil, won: true), SetScore(games: 6, tiebreak: nil, won: true), SetScore(games: 7, tiebreak: 7, won: true)], isWinner: true, seed: 8, imageIsFlag: true),
                         second: Participant(name: "F. Tiafoe", imageURL: flag("usa"), sets: [SetScore(games: 6, tiebreak: nil, won: true), SetScore(games: 3, tiebreak: nil, won: false), SetScore(games: 3, tiebreak: nil, won: false), SetScore(games: 6, tiebreak: 4, won: false)], seed: 11, imageIsFlag: true),
                         link: nil, hasStartTime: true),
                    Game(id: "t3", leagueID: league.id, sport: .tennis, startDate: time(20, 0, day: day, calendar: calendar), phase: .scheduled, statusText: nil, roundText: "SF",
                         first: Participant(name: "A. Zverev", imageURL: flag("ger"), seed: 1, imageIsFlag: true),
                         second: Participant(name: "K. Krawietz / T. Puetz", imageURL: flag("ger"), seed: 6, imageIsFlag: true),
                         link: nil, hasStartTime: true),
                ]),
            ]
        default:
            return []
        }
    }

    static var imageURLs: [URL] {
        var urls: [URL] = []
        let day = Date()
        for league in LeagueCatalog.all {
            for section in sections(for: league, day: day, calendar: .current) {
                if let logo = section.logoURL { urls.append(logo) }
                for game in section.games {
                    if let url = game.first.imageURL { urls.append(url) }
                    if let url = game.second.imageURL { urls.append(url) }
                }
            }
        }
        return urls
    }
}

struct FixtureScoreboardService: ScoreboardProviding {
    func sections(for league: League, day: Date, calendar: Calendar) async throws -> [ScoreSection] {
        Fixtures.sections(for: league, day: day, calendar: calendar)
    }
}
#endif
