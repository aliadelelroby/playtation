# Architecture

Playtation is a SwiftUI macOS app with one observable model.

## ConsoleModel

`Model/ConsoleModel.swift` holds all published state. Behavior is split into extensions, one file per concern:

| File | Responsibility |
| --- | --- |
| `+Navigation` | D-pad, face buttons, shoulders, hover; moving focus around Home |
| `+Panels` | Details, per-game settings and the Settings page |
| `+AddGame` | Add Game flow, saved launchers, removing games |
| `+SearchKeyboard` | On-screen keyboard state and input |
| `+Launch` | Starting, watching and closing games |
| `+Library` | Applying scan results, records, bottle changes |
| `+Artwork` | Names, metadata, icons, tiles and backdrops |
| `+Boot` | Boot and welcome flow |
| `+Pattern` | Sign-in pattern: asking for it on the profile screen, setting it up from Settings |

Views read the model and call its methods. They hold no game logic.

## Library

`LibraryScanner` reads each CrossOver bottle: Start Menu entries (`cxmenu`) and Steam libraries
(`SteamScanner`). `CustomLauncherStore` adds saved launchers and `MediaApps` adds web services.
`LibraryWatcher` watches the bottles, Steam folders, mounted drives and the clock, and asks the model
to rescan. `GameLauncher` builds the `wine` command line.

A `Game` is a plain value. Special kinds are marked by fields, not subclasses: `webURL` for web apps,
`customEnvironment` for saved launchers, `isAction` for the Add Game tile, `isLauncher` for store clients.

## Metadata

`GameCatalog.sync` is the entry point. For each game it:

1. cleans the title (`TitleMatcher.clean`),
2. reuses cached results when they are fresh and still match,
3. otherwise asks RAWG (with a key) then the Steam store,
4. accepts a listing only if `TitleMatcher.score` clears `threshold`,
5. stores screenshots, a portrait icon and `GameMeta` in `ArtworkStore`.

`TitleMatcher` is pure and unit tested. Change matching rules there and add a test.

## Input

`ControllerSupport` binds `GCController` buttons to model methods. `DualSenseHID` reads the PS button,
which macOS otherwise swallows. `ControllerAgent` is a login item that keeps that working when
Playtation is not running. While a game runs, `PadGate` stops the shell from reacting to the pad.
The touchpad draws the sign-in pattern: `PatternTrace` turns touch positions into dots (pure, unit
tested) and `PatternLock` keeps a salted hash of the result.

## UI

Home is `UI/Home`. The tile row is a horizontal `ScrollView`; apps are shown as a grouped shelf
(`AppShelf`). Liquid Glass is applied through helpers in `UI/Theme/Theme.swift` (`glassCapsule`,
`glassCircle`, `glassRounded`) that fall back to materials before macOS 26.
