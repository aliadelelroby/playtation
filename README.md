<h1 align="center">Playtation</h1>

<p align="center">
  <b>Your Windows games on the Mac, on a console-style home screen.</b><br>
  Sit back, pick up a controller, press ✕.
</p>

<p align="center">
  <a href="https://github.com/aliadelelroby/playtation/releases/latest"><b>Download</b></a> ·
  <a href="#get-playing-in-5-minutes">Get playing</a> ·
  <a href="#controller-cheat-sheet">Controls</a> ·
  <a href="#troubleshooting">Help</a> ·
  <a href="CONTRIBUTING.md">Contribute</a>
</p>

---

Playtation is a front end for [CrossOver](https://www.codeweavers.com/crossover). It finds the games you
already run through CrossOver and Steam, lays them out like a console dashboard, and launches them with
your controller. No more hunting through Finder and bottle folders.

> Playtation is an independent fan project. It is not affiliated with Sony, CodeWeavers or Valve.

## What you get

- 🎮 **A console-style home**: big artwork, a tile row, and Liquid Glass buttons on macOS 26.
- 🔎 **Your library, automatic**: CrossOver Start Menu entries and Steam games (even on other drives)
  appear on their own, and new installs show up while Playtation is open.
- 🖼️ **Artwork and details** fetched for every game, with careful matching so a sequel or a soundtrack
  never takes the place of the right game.
- 🧰 **Apps shelf**: Steam and other launchers, plus Spotify, YouTube, Twitch, Netflix, Disney+ and
  Prime Video.
- ➕ **Add Game**: run an installer, or save any program as a launcher with its own environment variables.
- 🕹️ **Made for controllers**: DualSense and other pads, an on-screen keyboard for search, haptics.
- 🖥️ **Resolution that suits your games**: pick the maximum resolution Playtation switches to, and your
  display goes back afterwards. This keeps HDR working, which CrossOver's *High Resolution* option turns off.

## Get playing in 5 minutes

### 1. Install CrossOver and your games

Playtation launches games through [CrossOver](https://www.codeweavers.com/crossover), so install it first
(the free trial works). Then add your games the way you normally would:

- **Steam**: install the Windows Steam client into a CrossOver bottle, sign in, and install games.
- **Other stores or setup files**: use CrossOver's *Install* button, or Playtation's **Add Game** tile later.

### 2. Install Playtation

1. Download **Playtation-1.0-macOS.zip** from the [latest release](https://github.com/aliadelelroby/playtation/releases/latest).
2. Unzip it and drag **Playtation** into your **Applications** folder.
3. Open it. The first time, macOS will say it can't verify the app, because it isn't notarized yet.
   Fix it once:
   - Right-click **Playtation** → **Open** → **Open**, or
   - open **System Settings → Privacy & Security** and click **Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/Playtation.app` in Terminal.

### 3. Allow access

Playtation asks for **Screen Recording** and **Accessibility** access. It uses them only to find a game's
window, bring it to the front and make it full screen. You can grant them in
**System Settings → Privacy & Security**. Restart Playtation afterwards.

### 4. Connect a controller and play

Connect a DualSense (USB or Bluetooth) or another controller, press the **PS button** (or click) on the
welcome screen, pick a game and press **✕**. That's it. Pulling **R2** also starts the highlighted game.

Don't see your games? Open **Settings → System → Rescan library**, and check that the game has a
Start Menu entry in CrossOver (or is installed through Steam in a bottle).

## Controller cheat sheet

| Button | Does |
| --- | --- |
| D-pad / left stick | Move around |
| ✕ | Select, start a game |
| ○ | Back, clear search |
| □ | Game details |
| △ | Game settings |
| L1 / R1 | Switch category (All, Games, Apps) |
| R2 | Start the highlighted game |
| PS / Options | Open the PS menu |

On the home screen, pick the magnifier for a PS-style keyboard. Every screen shows its own button hints.

## Add a game yourself

Select the **Add Game** tile at the end of the Games row:

1. Choose the **bottle** and the **program** (`.exe`, `.msi` or `.bat`).
2. Optionally give it a **name** and **environment variables** (`NAME=value`, separated by spaces).
3. Press **Run** to run an installer, or **Save as launcher** to put it on Home.

To remove a game, open its **…** menu and choose **Remove**. Playtation hides it, or deletes a launcher
you saved. It never deletes your game files.

## Requirements

- A Mac with **macOS 14** or later (Liquid Glass looks need **macOS 26**). Apple silicon and Intel.
- **CrossOver** installed in `/Applications` or `~/Applications`.
- A game controller is recommended but not required.

## Troubleshooting

<details>
<summary><b>"Playtation can't be opened because Apple cannot check it for malicious software"</b></summary>

The app is signed for local use but not notarized. Use one of the three options in step 2 above.
</details>

<details>
<summary><b>My game doesn't appear</b></summary>

Playtation reads CrossOver's Start Menu and Steam libraries. Make sure the game has a Start Menu entry in
its bottle, or is installed through Steam inside a bottle, then use **Settings → System → Rescan library**.
You can always add it by hand with **Add Game**.
</details>

<details>
<summary><b>The game doesn't come to the front or full screen</b></summary>

Check that Playtation has **Screen Recording** and **Accessibility** access in System Settings, then restart it.
</details>

<details>
<summary><b>Wrong or missing artwork and details</b></summary>

Playtation matches the shortcut's name against Steam (and RAWG, if you add a key). Give the game a clearer
name, or add a free [RAWG key](https://rawg.io/apidocs) by exporting `RAWG_API_KEY` or saving it to
`~/Library/Application Support/Playtation/rawg.key`.
</details>

<details>
<summary><b>HDR turns off when I start a game</b></summary>

Leave CrossOver's *High Resolution* option off and choose a maximum under **Settings → System → Game resolution**.
</details>

<details>
<summary><b>Where is my data?</b></summary>

`~/Library/Application Support/Playtation/` holds play history, hidden games, saved launchers and cached
artwork. Delete that folder to start fresh. Your games are untouched.
</details>

## Build from source

```sh
git clone https://github.com/aliadelelroby/playtation.git
cd playtation
brew install xcodegen
xcodegen generate
open Playtation.xcodeproj
```

Run the tests with `xcodebuild -project Playtation.xcodeproj -scheme Playtation test`. To make a release zip,
see [docs/RELEASING.md](docs/RELEASING.md).

### Project layout

```
Playtation/
  App/        App entry point, shell, boot and welcome screens
  Model/      ConsoleModel (split by concern), game and bottle types
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

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the pieces fit together.

## Contributing

Bug reports, ideas and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## Licenses and trademarks

Playtation is MIT licensed ([LICENSE](LICENSE)). Bundled fonts are under the SIL Open Font License
(`Playtation/Resources/Fonts/OFL.txt`). Service logos belong to their owners and are used only to identify
each service; see `Playtation/Resources/Logos/README.md`.
