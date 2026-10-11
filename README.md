# Playtation

A console-style front end for Windows games on the Mac. Playtation reads your
[CrossOver](https://www.codeweavers.com/crossover) bottles and Steam libraries, shows them as a
PlayStation-style home screen, and launches them with a controller. It is not affiliated with Sony,
CodeWeavers or Valve.

## Features

- **Home screen** with artwork, a tile row, categories (All, Games, Apps) and Liquid Glass controls
  on macOS 26 and later.
- **Automatic library**: games from CrossOver Start Menu entries and Steam libraries (including
  other drives) show up on their own and stay current while the app runs.
- **Metadata and artwork** from RAWG (optional key) and the Steam store, with strict title matching
  so a sequel or a soundtrack never replaces the right game.
- **Apps shelf** for Steam and other launchers, plus Spotify, YouTube, Twitch, Netflix, Disney+ and
  Prime Video.
- **Add Game**: run an installer in a bottle, or save any program as a launcher with its own
  environment variables.
- **Controller first**: DualSense and other controllers, an on-screen search keyboard, haptics and
  trigger feedback.
- **Display handling**: switches to a chosen maximum resolution when a game starts and restores it
  afterwards, so HDR keeps working.

## Requirements

- macOS 14 or later (Liquid Glass needs macOS 26)
- [CrossOver](https://www.codeweavers.com/crossover) installed in `/Applications` or `~/Applications`
- Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build

## Build and run

```sh
git clone https://github.com/aliadelelroby/playtation.git
cd playtation
brew install xcodegen
xcodegen generate
open Playtation.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project Playtation.xcodeproj -scheme Playtation -configuration Release build
```

Run the tests with `xcodebuild -project Playtation.xcodeproj -scheme Playtation test`.

Playtation asks for Screen Recording and Automation access so it can find a game window, focus it and
make it full screen.

## Optional: RAWG key

Steam covers most games without a key. For wider coverage, create a free key at
[rawg.io/apidocs](https://rawg.io/apidocs) and either export `RAWG_API_KEY` or save the key in
`~/Library/Application Support/Playtation/rawg.key`.

## Where data lives

`~/Library/Application Support/Playtation/` holds `library.json` (play counts, hidden games, per-game
overrides), `launchers.json` (saved launchers), and the cached `Screenshots/` and `Icons/`. Playtation
never deletes game files.

## Project layout

```
Playtation/
  App/        App entry point, shell, boot and welcome screens
  Model/      ConsoleModel (split into extensions by concern), game and bottle types
  Library/    CrossOver and Steam scanning, launchers, file watching, media apps
  Metadata/   Title matching, store clients, artwork cache
  Input/      Controller binding, DualSense HID, haptics, permissions
  System/     Display resolution and game window focus
  Audio/      UI sounds and music
  UI/         Home, Settings, overlays, theme and artwork rendering
  Resources/  Assets, fonts, sounds, logos, Info.plist
ControllerAgent/  Login-item helper that catches the PS button
Tests/            Unit tests
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit together and
[CONTRIBUTING.md](CONTRIBUTING.md) to get involved.

## Licenses and trademarks

Playtation is MIT licensed (see [LICENSE](LICENSE)). The bundled fonts are under the SIL Open Font
License (`Playtation/Resources/Fonts/OFL.txt`). Service logos in `Resources/Logos` belong to their
owners and are used only to identify each service; see `Resources/Logos/README.md`.
