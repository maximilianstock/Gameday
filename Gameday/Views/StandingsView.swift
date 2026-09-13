import AppKit
import SwiftUI

/// League table for one football league, opened from its section header in the score list.
struct StandingsView: View {
    let store: ScoreboardStore
    let leagueID: String
    @State private var isLoading = false

    private var league: League? { LeagueCatalog.league(id: leagueID) }
    private var standings: Standings? { store.standings[leagueID] }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            if let standings, !standings.isEmpty {
                ColumnHeader()
                HairlineDivider()
            }
            SelfSizingScrollView(minHeight: Theme.minListHeight, maxHeight: Theme.maxListHeight) {
                content
            }
            HairlineDivider()
            footer
        }
        .task(id: leagueID) { await load() }
    }

    private func load() async {
        isLoading = true
        await store.loadStandings(leagueIDs: [leagueID])
        isLoading = false
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "chevron.left", help: "Back to scores") { store.page = .scores }
            Text(league?.name ?? "Table")
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            if let season = standings?.seasonName {
                Text(season)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let standings, !standings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(standings.groups) { group in
                    if standings.groups.count > 1, let name = group.name {
                        GroupHeader(title: name)
                    }
                    ForEach(group.rows) { row in
                        StandingsRow(row: row, isFavorite: store.preferences.isFavorite(row.id))
                    }
                }
                if !standings.zones.isEmpty {
                    ZoneLegend(zones: standings.zones)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 10)
        } else if standings != nil {
            EmptyState(
                symbol: "tablecells",
                title: "No table yet",
                message: "ESPN hasn't published a table for this competition.",
                buttonTitle: nil,
                action: nil
            )
        } else if store.failedStandingsIDs.contains(leagueID), !isLoading {
            EmptyState(
                symbol: "wifi.exclamationmark",
                title: "Couldn't load the table",
                message: "Check your connection and try again.",
                buttonTitle: "Try again"
            ) {
                Task { await load() }
            }
        } else {
            EmptyState(symbol: nil, title: "Loading table…", message: nil, buttonTitle: nil, action: nil)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            if let link = standings?.link {
                TextButton(title: "Open on ESPN") { NSWorkspace.shared.open(link) }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 30)
    }
}

// MARK: - Layout

/// Column widths shared by the header and the rows so the numbers line up.
private enum Column {
    static let zone: CGFloat = 3
    static let position: CGFloat = 18
    static let logo: CGFloat = 16
    static let stat: CGFloat = 21
    static let goalDifference: CGFloat = 28
    static let points: CGFloat = 26
    static let statFont = Font.system(size: 12).monospacedDigit()
}

private struct ColumnHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Column.zone)
            label("#", width: Column.position)
            Color.clear.frame(width: 8 + Column.logo + 8)
            Text("Club")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 4)
            label("P", width: Column.stat, help: "Played")
            label("W", width: Column.stat, help: "Won")
            label("D", width: Column.stat, help: "Drawn")
            label("L", width: Column.stat, help: "Lost")
            label("GD", width: Column.goalDifference, help: "Goal difference")
            label("Pts", width: Column.points, help: "Points")
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
    }

    private func label(_ title: String, width: CGFloat, help: String? = nil) -> some View {
        Text(title)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.textTertiary)
            .frame(width: width, alignment: .trailing)
            .help(help ?? "")
    }
}

private struct StandingsRow: View {
    let row: Standings.Row
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(row.zone.map { Color(hex: $0.color) } ?? Color.clear)
                .frame(width: Column.zone, height: 14)
                .help(row.zone?.description ?? "")
            Text("\(row.position)")
                .font(Theme.Fonts.status)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Column.position, alignment: .trailing)
            RemoteImage(url: row.logoURL, size: CGSize(width: Column.logo, height: Column.logo))
                .padding(.horizontal, 8)
            HStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    name(row.name)
                    name(row.shortName)
                }
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Favorite")
                }
            }
            Spacer(minLength: 4)
            stat("\(row.gamesPlayed)", width: Column.stat)
            stat("\(row.wins)", width: Column.stat)
            stat("\(row.draws)", width: Column.stat)
            stat("\(row.losses)", width: Column.stat)
            stat(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)", width: Column.goalDifference)
            Text("\(row.points)")
                .font(Theme.Fonts.score)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Column.points, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(isFavorite ? Theme.accent.opacity(0.05) : Color.clear)
        )
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.position). \(row.name), \(row.points) points, \(row.gamesPlayed) played")
    }

    private func name(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
    }

    private func stat(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(Column.statFont)
            .foregroundStyle(Theme.textSecondary)
            .frame(width: width, alignment: .trailing)
    }
}

private struct GroupHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Fonts.sectionHeader)
                .tracking(0.4)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 3)
    }
}

/// Explains the coloured markers next to the positions.
private struct ZoneLegend: View {
    let zones: [Standings.Zone]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(zones, id: \.self) { zone in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(hex: zone.color))
                        .frame(width: Column.zone, height: 11)
                    Text(zone.description)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}
