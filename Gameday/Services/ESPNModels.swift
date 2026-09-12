import Foundation

// Decodable mirror of the parts of ESPN's public scoreboard payload that Gameday uses.
// Everything is optional on purpose: a single unexpected field must not break decoding
// of the whole league.

struct ESPNScoreboard: Decodable {
    var leagues: [ESPNLeague]?
    var events: [ESPNEvent]?
}

struct ESPNLeague: Decodable {
    var id: String?
    var name: String?
    var abbreviation: String?
    var slug: String?
    var logos: [ESPNLogo]?
}

struct ESPNLogo: Decodable {
    var href: String?
}

struct ESPNEvent: Decodable {
    var id: String
    var name: String?
    var shortName: String?
    var date: String?
    var endDate: String?
    var major: Bool?
    var status: ESPNStatus?
    var competitions: [ESPNCompetition]?
    var groupings: [ESPNGrouping]?
    var links: [ESPNLink]?
}

struct ESPNLink: Decodable {
    var href: String?
    var rel: [String]?
}

struct ESPNGrouping: Decodable {
    var grouping: ESPNGroupingInfo?
    var competitions: [ESPNCompetition]?
}

struct ESPNGroupingInfo: Decodable {
    var id: String?
    var slug: String?
    var displayName: String?
}

struct ESPNCompetition: Decodable {
    var id: String
    var date: String?
    var timeValid: Bool?
    var status: ESPNStatus?
    var competitors: [ESPNCompetitor]?
    var round: ESPNRound?
    var type: ESPNCompetitionType?
    var notes: [ESPNNote]?
}

struct ESPNRound: Decodable {
    var id: String?
    var displayName: String?
}

struct ESPNCompetitionType: Decodable {
    var id: String?
    var text: String?
    var slug: String?
    var abbreviation: String?
}

struct ESPNNote: Decodable {
    var text: String?
    var type: String?
}

struct ESPNStatus: Decodable {
    var clock: Double?
    var displayClock: String?
    var period: Int?
    var type: ESPNStatusType?
}

struct ESPNStatusType: Decodable {
    var id: String?
    var name: String?
    var state: String?
    var completed: Bool?
    var description: String?
    var detail: String?
    var shortDetail: String?
}

struct ESPNCompetitor: Decodable {
    var id: String?
    var uid: String?
    var homeAway: String?
    var order: Int?
    var winner: Bool?
    var score: ESPNScore?
    var team: ESPNTeam?
    var athlete: ESPNAthlete?
    var roster: ESPNRoster?
    var linescores: [ESPNLinescore]?
    var curatedRank: ESPNRank?
}

/// ESPN sends scores as strings in most feeds, but numbers and objects also occur.
struct ESPNScore: Decodable {
    var display: String?

    private struct ScoreObject: Decodable {
        var value: Double?
        var displayValue: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            display = string
        } else if let number = try? container.decode(Double.self) {
            display = number == number.rounded() ? String(Int(number)) : String(number)
        } else if let object = try? container.decode(ScoreObject.self) {
            display = object.displayValue ?? object.value.map { String(Int($0)) }
        } else {
            display = nil
        }
    }
}

struct ESPNTeam: Decodable {
    var id: String?
    var uid: String?
    var displayName: String?
    var shortDisplayName: String?
    var abbreviation: String?
    var name: String?
    var logo: String?
}

struct ESPNAthlete: Decodable {
    var id: String?
    var displayName: String?
    var shortName: String?
    var flag: ESPNFlag?
    var links: [ESPNLink]?
}

// MARK: Standings

struct ESPNStandingsResponse: Decodable {
    var season: ESPNSeasonInfo?
    var children: [ESPNStandingsGroup]?
    var standings: ESPNStandings?
}

struct ESPNSeasonInfo: Decodable {
    var year: Int?
    var displayName: String?
}

struct ESPNStandingsGroup: Decodable {
    var name: String?
    var standings: ESPNStandings?
    var children: [ESPNStandingsGroup]?
}

struct ESPNStandings: Decodable {
    var entries: [ESPNStandingsEntry]?
}

struct ESPNStandingsEntry: Decodable {
    var team: ESPNTeam?
    var stats: [ESPNStat]?
}

struct ESPNStat: Decodable {
    var name: String?
    var value: Double?
    var displayValue: String?
}

// MARK: Rankings

struct ESPNRankingsResponse: Decodable {
    var rankings: [ESPNRanking]?
}

struct ESPNRanking: Decodable {
    var ranks: [ESPNRankEntry]?
}

struct ESPNRankEntry: Decodable {
    var current: Int?
    var athlete: ESPNAthlete?
}

// MARK: Search

struct ESPNSearchResponse: Decodable {
    var results: [ESPNSearchGroup]?
}

struct ESPNSearchGroup: Decodable {
    var type: String?
    var contents: [ESPNSearchContent]?
}

struct ESPNSearchContent: Decodable {
    var uid: String?
    var displayName: String?
    var sport: String?
    var defaultLeagueSlug: String?
    var subtitle: String?
    var image: ESPNSearchImage?
}

struct ESPNSearchImage: Decodable {
    var `default`: String?
}

struct ESPNFlag: Decodable {
    var href: String?
    var alt: String?
}

struct ESPNRoster: Decodable {
    var displayName: String?
    var shortDisplayName: String?
    var athletes: [ESPNAthlete]?
}

struct ESPNLinescore: Decodable {
    var value: Double?
    var tiebreak: Int?
    var winner: Bool?
    var period: Int?
}

struct ESPNRank: Decodable {
    var current: Int?
}

enum ESPNDate {
    private static let formatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private static let requestFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// Day parameter in the form ESPN expects, in the local calendar.
    static func requestString(for date: Date) -> String {
        requestFormatter.string(from: date)
    }
}
