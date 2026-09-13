import Foundation

/// A league table as ESPN publishes it: one group for most leagues, several for leagues split
/// into conferences (MLS, NFL).
struct Standings: Hashable, Sendable {
    struct Zone: Hashable, Sendable {
        var description: String
        /// sRGB hex, e.g. 0x81D6AC.
        var color: UInt32
    }

    struct Row: Identifiable, Hashable, Sendable {
        /// Normalised team uid ("s:600~t:124").
        let id: String
        /// Position inside the group.
        var position: Int
        /// ESPN's own rank stat, nil when the feed has none.
        var rank: Int?
        var name: String
        var shortName: String
        var logoURL: URL?
        var gamesPlayed: Int
        var wins: Int
        var draws: Int
        var losses: Int
        var goalDifference: Int
        var points: Int
        var winPercent: Double
        var zone: Zone?
    }

    struct Group: Identifiable, Hashable, Sendable {
        var id: String { name ?? "" }
        var name: String?
        var rows: [Row]
    }

    let seasonYear: Int
    /// Short season label ("2026-27").
    let seasonName: String?
    let groups: [Group]
    let link: URL?

    /// Group position per team, only for groups in which at least one game has been played.
    /// Before that ESPN orders teams alphabetically.
    let positions: [String: Int]

    init(seasonYear: Int, seasonName: String?, groups: [Group], link: URL?) {
        self.seasonYear = seasonYear
        self.seasonName = seasonName
        self.groups = groups
        self.link = link
        var positions: [String: Int] = [:]
        for group in groups where group.rows.contains(where: { $0.gamesPlayed > 0 }) {
            for row in group.rows { positions[row.id] = row.position }
        }
        self.positions = positions
    }

    var isEmpty: Bool { groups.allSatisfy { $0.rows.isEmpty } }

    /// Zones in table order for the legend under the table. ESPN sometimes gives two zones the
    /// same colour ("Europa League", "Conference League qualifying"); those share one entry.
    var zones: [Zone] {
        var legend: [Zone] = []
        for zone in groups.flatMap(\.rows).compactMap(\.zone) {
            if let index = legend.firstIndex(where: { $0.color == zone.color }) {
                let parts = legend[index].description.components(separatedBy: " · ")
                if !parts.contains(zone.description) {
                    legend[index].description += " · \(zone.description)"
                }
            } else {
                legend.append(zone)
            }
        }
        return legend
    }
}
