<p align="center">
  <img src="Resources/AppIcon.png" width="144" alt="CmdSpace app icon">
</p>

<h1 align="center">CmdSpace</h1>

<p align="center">
  Fast, local-first search for your Mac
</p>

CmdSpace is a small native macOS launcher intended to replace Spotlight on
<kbd>⌘</kbd><kbd>Space</kbd>. It builds its own filename index of the startup
drive, follows filesystem changes as they happen, and learns from items opened
through CmdSpace.

## Install

Download the latest
[CmdSpace DMG](https://github.com/jvanderberg/cmdspace/releases/latest),
open it, and drag CmdSpace to Applications.

CmdSpace requires macOS 13 or newer. The first index may take a few minutes.
Existing results remain searchable while later refreshes run.

## What it does

- Indexes application names, file names, and folder names (not file contents).
- Opens from a fast keyboard-first floating launcher.
- Previews selected files with Quick Look after navigating with the arrow keys.
- Provides contextual actions for revealing, copying paths, choosing an app,
  and moving items to Trash.
- Browses largest files and most recently modified files via the mode switch
  or ⌘1/⌘2/⌘3, and searches the web with ⌘4.
- Ranks exact and prefix matches first, then boosts items by launch frequency
  and recency.
- Keeps apps first by default, with a setting to use normal relevance instead.
- Calculates expressions and converts common units directly in Search.
- Shows live web results and opens full searches with your chosen provider.
- Stores the index and launch history locally in
  `~/Library/Application Support/CmdSpace/index.sqlite3`.
- Tolerates unreadable folders and reports progress in the launcher.
- Includes in-app Settings for refresh timing, ranking, launch at login,
  permissions, and manual refresh, plus a complete Help window.

CmdSpace scans the sealed System and writable Data APFS volumes separately,
then maps Data-volume paths back to their familiar `/Users` and `/Applications`
spellings. It skips caches, cloud-provider roots, automount triggers, container
data, VCS internals, dependency trees, temporary volumes, and other high-noise
locations. It does not use or modify Spotlight's index.

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

This Developer ID-signs CmdSpace, installs it at `/Applications/CmdSpace.app`,
verifies the installed signature, and relaunches that copy.

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
