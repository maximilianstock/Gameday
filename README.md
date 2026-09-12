# Gameday

A menu bar app for macOS that shows today's games across the leagues you follow. One click, one list, no browser.

- Football (Bundesliga, Premier League, La Liga, Serie A, Champions League and more), NFL, NBA, tennis (ATP and WTA), NHL, MLB
- Live scores with match clock, finished results, kick-off times for upcoming games
- Step through days with the arrows or the keyboard (← →, `T` for today)
- Pick leagues in the popover; changes apply immediately
- **Top matches**: games between top teams (by the current table, or last season's early on) and Grand Slam semis and finals get a spectrum outline
- **Favorites**: search any club or tennis player; their games get a star
- A filter in the header shows only top matches and favorites
- Games whose participants aren't decided yet ("TBD") stay hidden
- Live game count in the menu bar
- Starts at login automatically once it runs from the Applications folder (switch it off in the ⋯ menu)
- Updates itself: new releases on GitHub show up as a one-line banner, one click installs and relaunches

## Install

1. Download the latest `Gameday-x.y.z.zip` from the [Releases](../../releases) page and unpack it.
2. Move `Gameday.app` to your Applications folder and open it. It lives in the menu bar; there is no Dock icon.
3. The first launch is blocked because the app isn't notarized with Apple. Later updates install from inside the app and don't trigger this again. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Alternatively run this once in Terminal:

   ```sh
   xattr -d com.apple.quarantine /Applications/Gameday.app
   ```

Requires macOS 15.1 or later.

## Keyboard

| Key | Action |
| --- | --- |
| ← → | Previous / next day |
| T | Back to today |
| R or ⌘R | Refresh |
| F | Favorites |
| H | Only top matches and favorites |
| , or ⌘, | Leagues |
| Esc | Back, then close |

## Build from source

Open `Gameday.xcodeproj` in Xcode 16 or later and run the `Gameday` scheme. No API key is needed: scores, standings and search come from ESPN's public endpoints.

From the command line:

```sh
xcodebuild -project Gameday.xcodeproj -scheme Gameday -configuration Release build
```

## Releasing

Pushing a tag builds the app on GitHub Actions and attaches the zip to a GitHub release:

```sh
git tag v2.0.0
git push origin v2.0.0
```

The build is ad-hoc signed, which is why the install step above is needed. With an Apple Developer ID certificate the workflow could sign and notarize instead; that removes the warning for everyone.

## Layout

| Folder | Contents |
| --- | --- |
| `Gameday/App` | Entry point, `AppDelegate` (status item, popover, timers, keyboard) |
| `Gameday/Model` | `Sport`, `League` catalog, `Game`/`ScoreSection`, `Favorite` |
| `Gameday/Services` | ESPN client and mapper, highlight engine (standings, rankings), search, preferences, image cache |
| `Gameday/State` | `ScoreboardStore`, the observable model the views render |
| `Gameday/Views` | SwiftUI views and the `Theme` |
| `Gameday/Debug` | Debug-only fixtures and snapshot rendering |

## How top matches are picked

- League games: both teams in the top 4 (football) or top 8 (NFL, NBA, NHL, MLB) of the table. While a season is young, last season's final table is used instead.
- Champions League, Europa League, Conference League: both teams in the top 8 of the competition table once three matchdays are played; before that, both must be top 4 in their domestic league.
- DFB-Pokal and FA Cup: both teams top 4 in their domestic league.
- Tennis: Grand Slam semi-finals and finals, any match between two top-10 players, and finals between top-20 players.

## Debug helpers

Debug builds accept launch arguments that make UI checks reproducible without clicking through the menu bar:

- `--snapshot <dir>` renders the scores, leagues and favorites pages in light and dark mode to PNG files using fixture data; add `--live` to use real data for today.
- `--open-popover [--leagues | --favorites [--query text] | --highlights-only | --check-updates]` opens the popover right after launch.
- `--auto-update` checks GitHub and, if a newer release exists, installs it and relaunches; useful for testing the updater against a build with a lower version number.
