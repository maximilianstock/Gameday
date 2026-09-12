import Foundation

/// Searches ESPN for teams (all supported sports) and players (tennis only, because only
/// tennis games list individual athletes).
final class SearchService: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func search(_ query: String) async throws -> [Favorite] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "https://site.web.api.espn.com/apis/search/v2")!
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "limit", value: "20"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw ScoreboardError.badResponse(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(ESPNSearchResponse.self, from: data)

        var results: [Favorite] = []
        var seen: Set<String> = []
        for group in decoded.results ?? [] {
            let isTeam = group.type == "team"
            let isPlayer = group.type == "player"
            guard isTeam || isPlayer else { continue }
            for content in group.contents ?? [] {
                guard let sport = Self.sport(for: content.sport),
                      let id = EntityID.normalize(content.uid),
                      let name = content.displayName,
                      seen.insert(id).inserted
                else { continue }
                if isPlayer && sport != .tennis { continue }
                if isTeam && Self.isExcludedLeague(content.defaultLeagueSlug) { continue }
                let subtitle = isPlayer ? Self.tourName(for: content.defaultLeagueSlug) : content.subtitle
                results.append(Favorite(
                    id: id,
                    name: name,
                    subtitle: subtitle,
                    imageURL: content.image?.default.flatMap(URL.init(string:)),
                    sport: sport,
                    isPlayer: isPlayer
                ))
            }
        }
        return Array(results.prefix(12))
    }

    private static func sport(for name: String?) -> Sport? {
        switch name {
        case "soccer": return .soccer
        case "football": return .americanFootball
        case "basketball": return .basketball
        case "tennis": return .tennis
        case "hockey": return .hockey
        case "baseball": return .baseball
        default: return nil
        }
    }

    private static func isExcludedLeague(_ slug: String?) -> Bool {
        guard let slug else { return false }
        return slug.contains("womens") || slug.contains("wchampions") || slug == "club.friendly"
    }

    private static func tourName(for slug: String?) -> String? {
        switch slug {
        case "atp": return "ATP"
        case "wta": return "WTA"
        default: return "Tennis"
        }
    }
}
