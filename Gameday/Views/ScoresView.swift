import AppKit
import SwiftUI

struct ScoresView: View {
    let store: ScoreboardStore

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            if store.updates.pendingUpdate != nil {
                UpdateBanner(updates: store.updates)
                HairlineDivider()
            }
            SelfSizingScrollView(minHeight: Theme.minListHeight, maxHeight: Theme.maxListHeight) {
                content
            }
            HairlineDivider()
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "chevron.left", help: "Previous day") { store.goToPreviousDay() }
            Text(store.dayTitle)
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 116)
                .contentTransition(.numericText())
            IconButton(symbol: "chevron.right", help: "Next day") { store.goToNextDay() }
            if !store.isToday {
                TextButton(title: "Today") { store.goToToday() }
                    .fixedSize()
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
            FilterToggle(isOn: store.showsHighlightsOnly) {
                store.showsHighlightsOnly.toggle()
            }
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 26, height: 26)
            } else {
                IconButton(symbol: "arrow.clockwise", help: "Refresh") {
                    Task { await store.refresh() }
                }
            }
            IconButton(symbol: "star", help: "Favorites") {
                store.page = .favorites
            }
            IconButton(symbol: "slider.horizontal.3", help: "Leagues") {
                store.page = .leagues
            }
            MoreMenu(store: store)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if store.selectedLeagues.isEmpty {
            EmptyState(
                symbol: "slider.horizontal.3",
                title: "No leagues selected",
                message: "Pick the leagues you want to follow.",
                buttonTitle: "Choose leagues"
            ) {
                store.page = .leagues
            }
        } else if let error = store.loadError, store.sections.isEmpty {
            EmptyState(
                symbol: "wifi.exclamationmark",
                title: error,
                message: "Check your connection and try again.",
                buttonTitle: "Try again"
            ) {
                Task { await store.refresh() }
            }
        } else if store.isFilterHidingGames {
            EmptyState(
                symbol: "line.3.horizontal.decrease",
                title: "No highlights",
                message: "No top matches or favorites in your leagues on this day.",
                buttonTitle: "Show all games"
            ) {
                store.showsHighlightsOnly = false
            }
        } else if store.sections.isEmpty {
            if store.isLoading && store.lastUpdated == nil {
                EmptyState(symbol: nil, title: "Loading scores…", message: nil, buttonTitle: nil, action: nil)
            } else {
                EmptyState(
                    symbol: "calendar",
                    title: "No games",
                    message: "Nothing scheduled in your leagues on this day.",
                    buttonTitle: nil,
                    action: nil
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.visibleSections) { section in
                    SectionHeader(section: section, openTable: tableAction(for: section))
                    ForEach(section.games) { game in
                        GameRow(game: game, animatesHighlights: store.isPopoverShown)
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    private func tableAction(for section: ScoreSection) -> (() -> Void)? {
        guard LeagueCatalog.league(id: section.leagueID)?.hasTable == true else { return nil }
        return { store.page = .standings(leagueID: section.leagueID) }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if store.hasPartialFailure {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Text("Some leagues didn't update")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else if case .checking = store.updates.state {
                Text("Checking for updates…")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else if case .upToDate = store.updates.state {
                Text("Gameday \(store.updates.currentVersion) is up to date")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else if case .failed(let message, nil) = store.updates.state {
                Text("Update check failed: \(message)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            } else if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else if store.isLoading {
                Text("Updating…")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if store.hasTablePositions {
                HStack(spacing: 3) {
                    Text("#")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Text("Table position")
                        .font(Theme.Fonts.captionMedium)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.trailing, store.hasLiveGames ? 8 : 0)
            }
            if store.hasLiveGames {
                LiveDot()
                Text("Live")
                    .font(Theme.Fonts.captionMedium)
                    .foregroundStyle(Theme.live)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }
}

// MARK: - Update banner

/// One quiet row under the header while a newer build is available or being installed.
struct UpdateBanner: View {
    let updates: UpdateController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(message)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            actions
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background(Theme.accent.opacity(0.06))
    }

    private var symbol: String {
        if case .failed = updates.state { return "exclamationmark.circle" }
        return "arrow.down.circle"
    }

    private var message: String {
        switch updates.state {
        case .available(let update):
            return "Gameday \(update.version) is available"
        case .downloading(let update, let fraction):
            if let fraction { return "Downloading \(update.version)… \(Int(fraction * 100))%" }
            return "Downloading \(update.version)…"
        case .installing(let update):
            return "Installing \(update.version)…"
        case .failed(let error, _):
            return "Update failed: \(error)"
        default:
            return ""
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch updates.state {
        case .available:
            if updates.canInstallInPlace {
                TextButton(title: "Update", prominent: true) { Task { await updates.install() } }
            } else {
                TextButton(title: "Download", prominent: true) { Task { await updates.install() } }
                    .help("Move Gameday to the Applications folder to update in place")
            }
            IconButton(symbol: "xmark", help: "Skip this version", size: 22) { updates.dismissPendingUpdate() }
        case .downloading, .installing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
                .padding(.trailing, 4)
        case .failed(_, let update):
            if update != nil {
                TextButton(title: "Try again") { Task { await updates.install() } }
            }
            TextButton(title: "Release page") { NSWorkspace.shared.open(UpdateController.releasesPage) }
            IconButton(symbol: "xmark", help: "Dismiss", size: 22) { updates.dismissPendingUpdate() }
        default:
            EmptyView()
        }
    }
}

// MARK: - Filter toggle

/// Header toggle for "only top matches and favorites". Reads as pressed while active.
struct FilterToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isOn ? Theme.accent : Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? Theme.accent.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 5, enabled: !isOn)
        .help(isOn ? "Showing only top matches and favorites" : "Show only top matches and favorites")
        .accessibilityLabel("Only top matches and favorites")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let section: ScoreSection
    /// Set for leagues with a table: the name becomes a link with a disclosure chevron.
    var openTable: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if let openTable {
                Button(action: openTable) {
                    label
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 5)
                .help("Show \(section.title) table")
            } else {
                label
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 9)
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let logo = section.logoURL {
                RemoteImage(url: logo, size: CGSize(width: 14, height: 14), fallbackSymbol: section.sport.symbolName)
            } else {
                Image(systemName: section.sport.symbolName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 14, height: 14)
            }
            Text(section.title.uppercased())
                .font(Theme.Fonts.sectionHeader)
                .tracking(0.4)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            if let subtitle = section.subtitle {
                Text("·")
                    .font(Theme.Fonts.sectionHeader)
                    .foregroundStyle(Theme.textTertiary)
                Text(subtitle.uppercased())
                    .font(Theme.Fonts.sectionHeader)
                    .tracking(0.4)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            if openTable != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, -1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let symbol: String?
    let title: String
    let message: String?
    let buttonTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 4)
            }
            Text(title)
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
            if let message {
                Text(message)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let buttonTitle, let action {
                OutlinedButton(title: buttonTitle, action: action)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 32)
        .frame(width: Theme.width, height: Theme.emptyStateHeight)
    }
}

// MARK: - More menu

struct MoreMenu: View {
    let store: ScoreboardStore
    @State private var launchAtLogin = false

    var body: some View {
        Menu {
            Button("Refresh") { Task { await store.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
            Button("Choose Leagues…") { store.page = .leagues }
                .keyboardShortcut(",", modifiers: .command)
            Button("Favorites…") { store.page = .favorites }
            Divider()
            Toggle("Only Top Matches & Favorites", isOn: Binding(
                get: { store.showsHighlightsOnly },
                set: { store.showsHighlightsOnly = $0 }
            ))
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        try store.preferences.setLaunchAtLogin(newValue)
                        launchAtLogin = newValue
                    } catch {
                        launchAtLogin = store.preferences.launchAtLogin
                    }
                }
            ))
            Divider()
            Button("Check for Updates…") {
                Task { await store.updates.check(userInitiated: true) }
            }
            Button("About Gameday") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Button("Quit Gameday") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverHighlight(cornerRadius: 5)
        .help("More")
        .onAppear { launchAtLogin = store.preferences.launchAtLogin }
    }
}
