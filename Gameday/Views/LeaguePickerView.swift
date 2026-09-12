import SwiftUI

struct LeaguePickerView: View {
    let store: ScoreboardStore

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            SelfSizingScrollView(minHeight: Theme.minListHeight, maxHeight: Theme.maxListHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Sport.allCases, id: \.self) { sport in
                        sportHeader(sport)
                        ForEach(LeagueCatalog.leagues(for: sport)) { league in
                            OptionRow(title: league.name, detail: league.region, isSelected: store.preferences.isSelected(league.id)) {
                                store.setLeague(league.id, selected: !store.preferences.isSelected(league.id))
                            }
                        }
                        if sport == .tennis {
                            OptionRow(title: "Include qualifying rounds", detail: nil, isSelected: store.preferences.showsTennisQualifying) {
                                store.setShowsTennisQualifying(!store.preferences.showsTennisQualifying)
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            HairlineDivider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "chevron.left", help: "Back to scores") { store.page = .scores }
            Text("Leagues")
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(selectionSummary)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private var selectionSummary: String {
        let count = store.preferences.selectedLeagueIDs.count
        return count == 1 ? "1 selected" : "\(count) selected"
    }

    private func sportHeader(_ sport: Sport) -> some View {
        HStack(spacing: 6) {
            Image(systemName: sport.symbolName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 14, height: 14)
            Text(sport.displayName.uppercased())
                .font(Theme.Fonts.sectionHeader)
                .tracking(0.4)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 3)
    }

    private var footer: some View {
        HStack {
            Text("Changes apply immediately.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            TextButton(title: "Reset to defaults") { store.resetLeaguesToDefaults() }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 30)
    }
}

private struct OptionRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Checkbox(isOn: isSelected)
                Text(title)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .padding(.horizontal, 6)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
