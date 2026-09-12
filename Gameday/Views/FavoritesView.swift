import SwiftUI

struct FavoritesView: View {
    let store: ScoreboardStore
    @State private var query = ""
    @State private var results: [Favorite] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingResults: Bool { trimmedQuery.count >= 2 }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            SearchField(text: $query, placeholder: "Search teams and players")
            HairlineDivider()
            SelfSizingScrollView(minHeight: Theme.minListHeight, maxHeight: Theme.maxListHeight) {
                content
            }
            HairlineDivider()
            footer
        }
        .task(id: trimmedQuery) {
            await runSearch(for: trimmedQuery)
        }
        #if DEBUG
        .onAppear {
            if let debugQuery = store.debugSearchQuery { query = debugQuery }
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "chevron.left", help: "Back to scores") { store.page = .scores }
            Text("Favorites")
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(countLabel)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private var countLabel: String {
        let count = store.preferences.favorites.count
        return count == 1 ? "1 favorite" : "\(count) favorites"
    }

    @ViewBuilder
    private var content: some View {
        if isShowingResults {
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { favorite in
                        FavoriteRow(favorite: favorite, style: .result(isAdded: store.preferences.isFavorite(favorite.id))) {
                            if store.preferences.isFavorite(favorite.id) {
                                store.removeFavorite(id: favorite.id)
                            } else {
                                store.addFavorite(favorite)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            } else if isSearching {
                EmptyState(symbol: nil, title: "Searching…", message: nil, buttonTitle: nil, action: nil)
            } else if searchFailed {
                EmptyState(symbol: "wifi.exclamationmark", title: "Search didn't work", message: "Check your connection and try again.", buttonTitle: nil, action: nil)
            } else {
                EmptyState(symbol: "magnifyingglass", title: "No results", message: "Try the club's or player's full name.", buttonTitle: nil, action: nil)
            }
        } else if store.preferences.favorites.isEmpty {
            EmptyState(
                symbol: "star",
                title: "No favorites yet",
                message: "Search for a club or a tennis player above. Their games get a star in the list.",
                buttonTitle: nil,
                action: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.preferences.favorites) { favorite in
                    FavoriteRow(favorite: favorite, style: .saved) {
                        store.removeFavorite(id: favorite.id)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var footer: some View {
        HStack {
            Text("Games with your favorites get a star.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private func runSearch(for text: String) async {
        guard text.count >= 2 else {
            results = []
            isSearching = false
            searchFailed = false
            return
        }
        isSearching = true
        searchFailed = false
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do {
            let found = try await store.searchService.search(text)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchFailed = true
        }
        isSearching = false
    }
}

private struct FavoriteRow: View {
    enum Style {
        case saved
        case result(isAdded: Bool)
    }

    let favorite: Favorite
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RemoteImage(
                    url: favorite.imageURL,
                    size: CGSize(width: 18, height: 18),
                    cornerRadius: favorite.isPlayer ? 9 : 0,
                    fallbackSymbol: favorite.sport?.symbolName ?? "star"
                )
                Text(favorite.name)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle = favorite.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                trailingIcon
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .padding(.horizontal, 6)
        .help(helpText)
    }

    @ViewBuilder
    private var trailingIcon: some View {
        switch style {
        case .saved:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        case .result(let isAdded):
            Image(systemName: isAdded ? "star.fill" : "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isAdded ? Theme.accent : Theme.textTertiary)
        }
    }

    private var helpText: String {
        switch style {
        case .saved: return "Remove from favorites"
        case .result(let isAdded): return isAdded ? "Remove from favorites" : "Add to favorites"
        }
    }
}
