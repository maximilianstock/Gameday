import SwiftUI

struct RootView: View {
    let store: ScoreboardStore

    var body: some View {
        Group {
            switch store.page {
            case .scores:
                ScoresView(store: store)
            case .leagues:
                LeaguePickerView(store: store)
            case .favorites:
                FavoritesView(store: store)
            }
        }
        .frame(width: Theme.width)
        .background(Theme.background)
        .background(PopoverChrome())
        .foregroundStyle(Theme.textPrimary)
        .font(Theme.Fonts.body)
    }
}
