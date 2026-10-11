# Contributing

Thanks for helping. Playtation is small, so the bar is simple: keep it readable and keep it working
with a controller.

## Setup

```sh
git clone https://github.com/aliadelelroby/playtation.git
cd playtation
brew install xcodegen
xcodegen generate
open Playtation.xcodeproj
```

The Xcode project is generated from `project.yml` and is not committed. Add new Swift files anywhere
under `Playtation/` and run `xcodegen generate` again.

## Before you open a pull request

- `xcodebuild -project Playtation.xcodeproj -scheme Playtation test` passes.
- The app builds without new warnings.
- Anything you can reach with a mouse can also be reached with the d-pad and ✕/○.
- Changes to title matching come with a test in `Tests/PlaytationTests/TitleMatcherTests.swift`.

## Code style

- One main type per file, named after the file. Put model behavior in the matching
  `ConsoleModel+…` extension.
- Views draw; the model decides. Keep game logic out of `UI/`.
- Prefer small pure functions you can test (see `TitleMatcher`).
- Comments say why, not what. Skip comments that repeat the code.
- Use native SwiftUI and Liquid Glass APIs, with an availability fallback for older macOS.
- No force unwraps on data from disk or the network.

## Updating the screenshots

Launch the app with `PLAYTATION_CAPTURE_DIR=/some/folder`. It walks through the main screens, saves a PNG of
its own window for each (no Screen Recording permission needed, and a generic profile is shown instead of yours),
then quits. Resize to about 1600 px wide and put the JPEGs in `docs/images/`. The tour lives in
`Playtation/System/ScreenshotTour.swift`.

## Good first issues

- More launchers in `Game.isLauncher` or more services in `MediaApps`.
- Better artwork sources.
- Translations and accessibility labels.
- Tests for `LibraryScanner` against sample bottle folders.

## Reporting bugs

Include your macOS and CrossOver versions, the game, and steps to reproduce. Crash reports from
`~/Library/Logs/DiagnosticReports` help a lot.
