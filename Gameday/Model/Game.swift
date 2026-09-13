import Foundation

enum GamePhase: Hashable, Sendable {
    case scheduled
    case live
    case final
    case postponed
    case canceled
    case delayed
    case suspended
}

/// One game/set score in tennis.
struct SetScore: Hashable, Sendable {
    var games: Int
    var tiebreak: Int?
    var won: Bool?
}

struct Participant: Hashable, Sendable {
    var name: String
    var imageURL: URL?
    /// Aggregate score for team sports. Nil for scheduled games and for tennis.
    var score: String?
    /// Per-set scores for tennis.
    var sets: [SetScore] = []
    var isWinner: Bool = false
    var seed: Int?
    /// Current position in the league table (football leagues only). Set by the store.
    var tablePosition: Int?
    /// True when the image is a country flag (rendered as a small rectangle rather than a square logo).
    var imageIsFlag: Bool = false
    /// Normalised ESPN identifiers ("s:600~t:124" for a team, "s:850~a:2375" for a player;
    /// two entries for a doubles pair). Used to match favourites and standings.
    var entityIDs: [String] = []
    var isFavorite: Bool = false
}

struct Game: Identifiable, Hashable, Sendable {
    let id: String
    let leagueID: String
    let sport: Sport
    let startDate: Date
    let phase: GamePhase
    /// Status label for live/finished/other states ("67'", "FT", "Final/OT", "PPD"). Nil for scheduled games.
    let statusText: String?
    /// Short round label for tennis ("SF", "R16"). Nil otherwise.
    let roundText: String?
    /// The participant displayed on the first line, then the second line.
    var first: Participant
    var second: Participant
    let link: URL?
    /// False when the start time is still to be announced.
    let hasStartTime: Bool
    /// Grand Slam (tennis only).
    var isMajor: Bool = false
    /// Set by the highlight engine: a game between top teams or players.
    var isTopMatch: Bool = false

    var isLive: Bool { phase == .live }
    var isTennis: Bool { sport == .tennis }
    var involvesFavorite: Bool { first.isFavorite || second.isFavorite }
}

struct ScoreSection: Identifiable, Hashable, Sendable {
    let id: String
    let leagueID: String
    let sport: Sport
    let title: String
    let subtitle: String?
    let logoURL: URL?
    /// Lower sorts first inside the same sport (tennis: majors before regular tour events).
    let priority: Int
    /// Tie-breaker inside a tournament (order of the draw groupings).
    let subOrder: Int
    var games: [Game]

    var liveCount: Int { games.filter(\.isLive).count }
}
