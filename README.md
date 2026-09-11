<p align="center">
  <img src="Resources/AppIcon.png" width="144" alt="CmdSpace app icon">
</p>

<h1 align="center">CmdSpace</h1>

<p align="center">
  Fast, local-first search for your Mac
</p>

CmdSpace is a native macOS launcher for
<kbd>⌘</kbd><kbd>Space</kbd>. It builds its own filename index of the startup
drive, follows filesystem changes as they happen, and learns from items opened
through CmdSpace.

## Install

Download the latest
[CmdSpace DMG](https://github.com/jvanderberg/cmdspace/releases/latest),
open it, and drag CmdSpace to Applications.

CmdSpace requires macOS 13 or newer. The first index may take a few minutes.
Existing results remain searchable while later refreshes run.

## Using CmdSpace

Press <kbd>⌘</kbd><kbd>Space</kbd>, type a query, choose a result with the arrow
keys, and press Return. Escape closes the launcher. Open Settings with the
gear button and Help by searching for `help`.

Search stays responsive while an app opens. A spinner and “Opening [name]…”
appear while macOS handles the request. The launcher closes when macOS reports
success, unless you have started another search. An app may continue loading
after the launcher closes.

Use the mode buttons or keyboard shortcuts to choose what to search.

| Mode | Shortcut | Contents |
| --- | --- | --- |
| Search | ⌘1 | Apps, files, folders, settings, commands, and calculations |
| Large Files | ⌘2 | Up to 1,000 indexed files, largest first |
| Recent Files | ⌘3 | Up to 1,000 recently modified files |
| Web | ⌘4 | Live web results and a full search with your chosen provider |

Type to filter Large Files and Recent Files by name. Recent Files can prioritize
common personal folders through Settings.

## Features

### System commands and running apps

Search for Lock Screen, Sleep, Mute, Unmute, Volume Up, Volume Down,
Quit CmdSpace, Restart, Shut Down, or Empty Trash. Commands have distinct
icons and a Command label. Matching System Settings results appear first.

Type `quit` or `kill` to list running apps by CPU usage, highest first.
Continue with an app name, such as `quit chrome`, to filter the list.
The initial order uses CPU usage and stays fixed while the list is open,
including when you filter by name. CPU values refresh about once per second.
Apps that exit disappear, and newly opened apps append at the bottom. Reopen
the list for a fresh CPU sort. Usage includes associated helper processes;
100% means one CPU core.

Return with `quit` requests a normal quit, allowing the app to prompt about
unsaved work. Return with `kill` asks for confirmation before force quit.
Restart, Shut Down, and Empty Trash also require confirmation, with Cancel
selected by default. Empty Trash permanently deletes its contents.

Lock Screen uses the macOS lock shortcut and requires Accessibility access
for CmdSpace. macOS may ask for Automation access when you first use commands
that control System Events or Finder. Failed commands show an error.

### Frequently used apps

Open Search with an empty query to see up to 18 apps most frequently opened
through CmdSpace, in up to three rows of six, with icons above their names. Recent launches break ties.
Only apps launched through CmdSpace appear; incomplete rows align to the left.
Click an app or use the arrow keys followed by Return to open it.
Empty Search shows only the app grid. Type to see search results. The grid disappears as soon as
you type and returns when you clear Search. Internal-app filtering applies.

### Hide internal app components

Search hides embedded helpers, managed placeholders, incomplete app bundles,
and background-only components under Application Support by default.
Turn off **Hide internal app components** in Settings → Search and Browse to
show these indexed entries immediately without reindexing.

Visibility follows deterministic rules based on paths and app metadata.
Apps with unreadable metadata stay visible. Launch history affects ranking.

### System Settings search

Find common Mac settings directly in Search. Try `wifi`, `dark mode`,
`resolution`, `startup apps`, `microphone access`, or `full disk access`.
Results show a destination-specific icon and breadcrumb. Press Return to open the page.

The built-in catalog covers Wi-Fi, Bluetooth, battery or desktop power,
appearance, displays, wallpaper, keyboard, trackpad, printers, privacy and
security, sound, mouse, notifications, Focus, Lock Screen, Login Items,
Software Update, Storage, and Accessibility. Common privacy permissions have
their own results. Setting names match from two characters. Partial matches
on related words require at least three characters.

Settings search works offline without waiting for the file index. Matching
settings always appear above apps and files, with at most six settings results per
query. Settings results open pages without changing any settings. Some
destinations open the containing page, including Firewall under Network and
FileVault under Privacy & Security on macOS 13. Hardware-specific pages such
as Mouse depend on the devices connected to your Mac.

### Live indexing

CmdSpace follows filesystem changes continuously while it is running.
Created and renamed folders have their contents indexed, removed folders are
deleted from results, and changes made while CmdSpace was closed replay from
the macOS event journal after relaunch.

Full-drive refresh defaults to **Manual only**. Settings also offers 6-hour,
12-hour, daily, and weekly refresh schedules.
CmdSpace also reconciles automatically if macOS reports an event-history gap.

### Quick Look and file actions

After moving through results with the arrow keys, press <kbd>Space</kbd> to
preview the selected file with Quick Look. Press <kbd>⌘</kbd><kbd>K</kbd> or
right-click a result for these actions

- Open
- Quick Look
- Reveal in Finder
- Copy Path
- Open With
- Move to Trash
- Terminal from Here for folders

Move to Trash uses the macOS Trash, so the item remains recoverable.

### Calculator, conversions, and dates

Type calculations directly into Search and press Return to copy the result.
CmdSpace supports arithmetic, percentages, factorials, functions, constants,
complex numbers, and natural-language operators.

Unit conversion covers length, area, volume, mass, temperature, speed, time,
storage, angle, energy, power, pressure, and frequency. Ambiguous ounces use
the destination dimension, so `20 ounces in milliliters` means fluid ounces
while `20 ounces in grams` means weight ounces.

Common unit pairs complete inline. For example, `20F` suggests Celsius and
calculates immediately. Press Tab to accept the suggested text. Time units
include milliseconds, microseconds with `us`, `µs`, or `μs`, and nanoseconds.

Programmer literals using `0b`, `0o`, or `0x` show binary, octal, decimal, and
hexadecimal forms. Binary suffix notation such as `1111b` is also supported.
Type-ahead suggests a common target, and suffixes such as `in hex`, `in binary`,
`in octal`, or `in decimal` choose the value copied with Return.

The Search field supports the standard macOS editing shortcuts for copy, paste,
cut, select all, undo, and redo.

English date phrases support relative dates, date differences, and weekdays.
Business days mean Monday through Friday and do not include holiday calendars.

```text
30 days from today
July 25 + 6 weeks
days until Christmas
business days between August 1 and September 15
1 ms to us
0xF2Ea
0b010101010 in hex
```

## Index and ranking

CmdSpace indexes app, file, and folder names, paths, modification dates, and
file sizes. It does not search document contents or use Spotlight’s index.
The index and launch history stay on your Mac at
`~/Library/Application Support/CmdSpace/index.sqlite3`.

Matching settings lead Search results. App and file ranking uses exact and
prefix matches, launch frequency, and recency. **Prefer apps in Search results**
places apps above files and folders and can be disabled in Settings.

CmdSpace scans the startup drive’s System and Data volumes and displays familiar
paths such as `/Users` and `/Applications`. It skips caches, cloud-provider
roots, container data, dependency trees, temporary volumes, and other locations
that would fill results with internal files. Unreadable folders are skipped.

## Build and run

Requires macOS 13 or newer and Xcode command-line tools.

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open .build/CmdSpace.app
```

Release builds automatically use the first installed Developer ID Application
certificate, preserving identity-keyed privacy grants across rebuilds. Set
`CODESIGN_IDENTITY=-` to force ad-hoc signing, or pass an exact identity in
`CODESIGN_IDENTITY`.

For a stable installation whose Full Disk Access grant survives rebuilds

```sh
chmod +x scripts/install-app.sh
./scripts/install-app.sh
```

This builds and signs CmdSpace, installs it at `/Applications/CmdSpace.app`,
verifies the installed signature, and launches that copy. A Developer ID
Application certificate is needed for a stable signing identity across builds.

## Claim ⌘Space

macOS reserves <kbd>⌘</kbd><kbd>Space</kbd> for Spotlight by default

1. Open **System Settings → Keyboard → Keyboard Shortcuts → Spotlight**.
2. Turn off “Show Spotlight search”.
3. Quit and reopen CmdSpace.

If the shortcut is still occupied, CmdSpace stays available from its menu-bar
icon and shows a warning in that menu.

## Permissions

CmdSpace indexes every location macOS lets it read. To include protected
locations, add `CmdSpace.app` under **System Settings → Privacy & Security →
Full Disk Access**, then choose **Refresh Index** from its menu-bar icon.

## Tests

```sh
swift test
```

## Build a DMG

```sh
./scripts/build-dmg.sh
```

The DMG and SHA-256 checksum are written to `dist`.

Public distribution also requires Apple notarization. Store credentials in a
notarytool keychain profile, then run

```sh
./scripts/build-release.sh YOUR_KEYCHAIN_PROFILE
```

This signs with hardened runtime and trusted timestamps, notarizes and staples
the app, builds the DMG, then notarizes and staples the DMG.
