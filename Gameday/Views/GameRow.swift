import AppKit
import SwiftUI

struct GameRow: View {
    let game: Game
    var animatesHighlights = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                ParticipantLine(participant: game.first, game: game)
                ParticipantLine(participant: game.second, game: game)
            }
            StatusColumn(game: game)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(wash)
        .overlay(border)
        .contentShape(Rectangle())
        .hoverHighlight(enabled: game.link != nil)
        .padding(.horizontal, 6)
        .onTapGesture {
            if let link = game.link { NSWorkspace.shared.open(link) }
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var wash: some View {
        if game.isTopMatch {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Spectrum.angular)
                .opacity(0.07)
        } else if game.involvesFavorite {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.accent)
                .opacity(0.05)
        }
    }

    @ViewBuilder
    private var border: some View {
        if game.isTopMatch {
            SpectrumBorder(animated: animatesHighlights)
        }
    }

    private var helpText: String {
        switch (game.isTopMatch, game.involvesFavorite) {
        case (true, true): return "Top match with one of your favorites"
        case (true, false): return "Top match"
        case (false, true): return "One of your favorites"
        case (false, false): return ""
        }
    }

    private var accessibilityText: String {
        var parts = ["\(game.first.name) versus \(game.second.name)"]
        if game.isTopMatch { parts.append("top match") }
        if game.involvesFavorite { parts.append("favorite") }
        return parts.joined(separator: ", ")
    }
}

private struct ParticipantLine: View {
    let participant: Participant
    let game: Game

    private var dimmed: Bool {
        game.phase == .final && !participant.isWinner
    }

    var body: some View {
        HStack(spacing: 8) {
            if participant.imageIsFlag {
                RemoteImage(url: participant.imageURL, size: CGSize(width: 18, height: 13), cornerRadius: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(Theme.divider, lineWidth: 0.5)
                    )
                    .frame(width: 18, height: 18)
            } else {
                RemoteImage(url: participant.imageURL, size: CGSize(width: 18, height: 18))
            }
            Text(participant.name)
                .font(participant.isWinner ? Theme.Fonts.bodyMedium : Theme.Fonts.body)
                .foregroundStyle(dimmed ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if participant.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Favorite")
            }
            // Seed for tennis players, table position for football clubs.
            if let number = participant.seed ?? participant.tablePosition {
                Text("\(number)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 6)
            if game.isTennis {
                HStack(spacing: 8) {
                    ForEach(Array(participant.sets.enumerated()), id: \.offset) { _, set in
                        SetScoreView(set: set, dimmed: set.won == false)
                    }
                }
            } else if let score = participant.score {
                Text(score)
                    .font(Theme.Fonts.score)
                    .foregroundStyle(dimmed ? Theme.textSecondary : Theme.textPrimary)
                    .frame(minWidth: 22, alignment: .trailing)
            }
        }
        .frame(height: 18)
    }
}

private struct SetScoreView: View {
    let set: SetScore
    let dimmed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            Text("\(set.games)")
                .font(Theme.Fonts.setScore)
                .foregroundStyle(dimmed ? Theme.textTertiary : Theme.textPrimary)
            if let tiebreak = set.tiebreak {
                Text("\(tiebreak)")
                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                    .baselineOffset(5)
            }
        }
        .frame(minWidth: 16, alignment: .trailing)
    }
}

private struct StatusColumn: View {
    let game: Game

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            switch game.phase {
            case .live:
                HStack(spacing: 4) {
                    LiveDot()
                    Text(game.statusText ?? "Live")
                        .font(Theme.Fonts.status)
                        .foregroundStyle(Theme.live)
                }
            case .scheduled:
                Text(game.hasStartTime ? game.startDate.formatted(date: .omitted, time: .shortened) : "TBD")
                    .font(Theme.Fonts.status)
                    .foregroundStyle(Theme.textSecondary)
            case .final:
                Text(game.statusText ?? "Final")
                    .font(Theme.Fonts.status)
                    .foregroundStyle(Theme.textTertiary)
            case .postponed, .canceled, .delayed, .suspended:
                Text(game.statusText ?? "")
                    .font(Theme.Fonts.status)
                    .foregroundStyle(Theme.textTertiary)
            }
            if let round = game.roundText {
                Text(round)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else if game.isTopMatch {
                Text("Top match")
                    .font(Theme.Fonts.captionMedium)
                    .foregroundStyle(Spectrum.linear)
            }
        }
        .lineLimit(1)
        .frame(width: 64, alignment: .trailing)
    }
}
