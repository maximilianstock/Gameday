import Foundation

/// The sports Gameday knows about. Order here defines display order in the app.
enum Sport: String, CaseIterable, Codable, Sendable {
    case soccer
    case americanFootball
    case basketball
    case tennis
    case hockey
    case baseball

    var displayName: String {
        switch self {
        case .soccer: return "Football"
        case .americanFootball: return "American Football"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis"
        case .hockey: return "Ice Hockey"
        case .baseball: return "Baseball"
        }
    }

    /// SF Symbol used wherever a league has no logo of its own.
    var symbolName: String {
        switch self {
        case .soccer: return "soccerball"
        case .americanFootball: return "football"
        case .basketball: return "basketball"
        case .tennis: return "tennisball"
        case .hockey: return "hockey.puck"
        case .baseball: return "baseball"
        }
    }

    /// US leagues are conventionally written "Away @ Home", so the away side is listed first.
    var listsAwayTeamFirst: Bool {
        switch self {
        case .americanFootball, .basketball, .hockey, .baseball: return true
        case .soccer, .tennis: return false
        }
    }
}

struct League: Identifiable, Hashable, Sendable {
    /// ESPN path, e.g. "soccer/ger.1". Doubles as the stable identifier that is persisted.
    let id: String
    let sport: Sport
    let name: String
    let region: String

    var espnPath: String { id }
}

enum LeagueCatalog {
    static let all: [League] = [
        // Football
        League(id: "soccer/ger.1", sport: .soccer, name: "Bundesliga", region: "Germany"),
        League(id: "soccer/ger.2", sport: .soccer, name: "2. Bundesliga", region: "Germany"),
        League(id: "soccer/ger.dfb_pokal", sport: .soccer, name: "DFB-Pokal", region: "Germany"),
        League(id: "soccer/eng.1", sport: .soccer, name: "Premier League", region: "England"),
        League(id: "soccer/eng.fa", sport: .soccer, name: "FA Cup", region: "England"),
        League(id: "soccer/esp.1", sport: .soccer, name: "La Liga", region: "Spain"),
        League(id: "soccer/ita.1", sport: .soccer, name: "Serie A", region: "Italy"),
        League(id: "soccer/fra.1", sport: .soccer, name: "Ligue 1", region: "France"),
        League(id: "soccer/ned.1", sport: .soccer, name: "Eredivisie", region: "Netherlands"),
        League(id: "soccer/por.1", sport: .soccer, name: "Primeira Liga", region: "Portugal"),
        League(id: "soccer/usa.1", sport: .soccer, name: "MLS", region: "USA"),
        League(id: "soccer/uefa.champions", sport: .soccer, name: "Champions League", region: "Europe"),
        League(id: "soccer/uefa.europa", sport: .soccer, name: "Europa League", region: "Europe"),
        League(id: "soccer/uefa.europa.conf", sport: .soccer, name: "Conference League", region: "Europe"),
        // American football
        League(id: "football/nfl", sport: .americanFootball, name: "NFL", region: "USA"),
        League(id: "football/college-football", sport: .americanFootball, name: "College Football", region: "USA"),
        // Basketball
        League(id: "basketball/nba", sport: .basketball, name: "NBA", region: "USA"),
        League(id: "basketball/wnba", sport: .basketball, name: "WNBA", region: "USA"),
        League(id: "basketball/mens-college-basketball", sport: .basketball, name: "College Basketball", region: "USA"),
        // Tennis
        League(id: "tennis/atp", sport: .tennis, name: "ATP Tour", region: "Men"),
        League(id: "tennis/wta", sport: .tennis, name: "WTA Tour", region: "Women"),
        // Ice hockey
        League(id: "hockey/nhl", sport: .hockey, name: "NHL", region: "USA"),
        // Baseball
        League(id: "baseball/mlb", sport: .baseball, name: "MLB", region: "USA"),
    ]

    static let defaultSelection: [String] = [
        "soccer/ger.1",
        "soccer/eng.1",
        "soccer/esp.1",
        "soccer/ita.1",
        "soccer/uefa.champions",
        "football/nfl",
        "basketball/nba",
        "tennis/atp",
        "tennis/wta",
    ]

    private static let byID: [String: League] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let indexByID: [String: Int] = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.id, $0) })

    static func league(id: String) -> League? { byID[id] }

    static func index(of id: String) -> Int { indexByID[id] ?? Int.max }

    static func leagues(for sport: Sport) -> [League] { all.filter { $0.sport == sport } }
}
