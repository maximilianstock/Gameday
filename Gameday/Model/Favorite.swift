import Foundation

/// A team or player the user follows. Identified by ESPN's normalised uid so games can be matched.
struct Favorite: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var subtitle: String?
    var imageURL: URL?
    var sport: Sport?
    var isPlayer: Bool
}

enum EntityID {
    /// Normalises ESPN uids so the same team or player gets the same key in every feed.
    /// Teams keep their league component ("s:20~l:28~t:4"; soccer teams have none: "s:600~t:124"),
    /// players lose it ("s:850~l:851~a:2375" becomes "s:850~a:2375").
    static func normalize(_ uid: String?) -> String? {
        guard let uid else { return nil }
        var sport: String?
        var league: String?
        var team: String?
        var athlete: String?
        for part in uid.split(separator: "~") {
            let pieces = part.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "s": sport = String(pieces[1])
            case "l": league = String(pieces[1])
            case "t": team = String(pieces[1])
            case "a": athlete = String(pieces[1])
            default: break
            }
        }
        guard let sport else { return nil }
        if let athlete { return "s:\(sport)~a:\(athlete)" }
        if let team {
            if let league { return "s:\(sport)~l:\(league)~t:\(team)" }
            return "s:\(sport)~t:\(team)"
        }
        return nil
    }

    static func tennisPlayer(id: String) -> String { "s:850~a:\(id)" }

    /// Extracts the athlete id from an ESPN player page link ("…/player/_/id/2375/…").
    static func athleteID(fromLink href: String?) -> String? {
        guard let href, let range = href.range(of: "/id/") else { return nil }
        let rest = href[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }
}
