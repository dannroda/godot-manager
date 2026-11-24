# Changelog

All notable changes to godot-manager. The release workflow (Actions → Release → Run workflow) publishes the **Unreleased** section as the release notes and turns it into the new version's section, so write entries here, in English, as changes land. Versions before 2.4.0 are on the [releases page](https://github.com/dannroda/godot-manager/releases).

## [Unreleased]

## [2.4.6] - 2026-11-24

### Fixed

- **Download tab: uninstall installed versions and update buttons.** Selecting an installed release now shows **Uninstall…** (also in the right-click menu and via Delete, with an edition picker when both standard and Mono are installed). **Install…** stays enabled with the missing edition preselected when only one edition is installed, disables once all editions of the release are installed, and refreshes automatically after installing or uninstalling.

## [2.4.5] - 2026-11-23

### Changed

- **A new Add plugin window.**
  - It opens with suggestions: our plugins (Godot Agent and Scope Compass) next to the top-rated Asset Store items that work with the project's Godot. Before, it was empty until you searched, and ours were a row of buttons above it.
  - Each result is a card with its image, name, author, license, review score, description and Store tags. A **View in the Store** (or **View on GitHub**) button opens its page.
  - Cards are labeled **Plugin** or **Assets** (art, sound and other files) so you can tell them apart. The Asset Store doesn't say which is which, so the label is a guess from the item's tags and description.
- **`godot-manager plugins search`** with no text lists the top-rated Asset Store items, and each result now includes its tags, image and that plugin/assets guess.

### Fixed

- **Right-click menus open where you click.** Since 2.4.1 they opened at the top-left corner of the screen.
- **Updating from the GUI works again.** In 2.4.4 the update banner didn't load, so the GUI never offered new versions and Settings → **Check now** didn't work either. **If you're on 2.4.4**, update once from a terminal with `godot-manager self-update` (in the folder where you extracted it), or download the archive again; from 2.4.5 on, the GUI does it.
- **Asset Store items that aren't editor plugins** (music, sprites and other packs) show up in the project's details as **Assets** once installed, and can be updated, pinned and uninstalled. Before, they showed as "not installed" forever. They're still installed with the same paths as in their zip, as Godot does, so their `res://` references keep working.

## [2.4.4] - 2026-11-23

### Fixed

- **Restart after updating, on Linux.** After the GUI updated itself, **Restart** closed it without opening the new version, so you had to open it yourself. It now opens the new version. If it still can't, the GUI stays open and says so.

## [2.4.3] - 2026-11-23

### Changed

- **New projects match Godot's Project Manager.**
  - The GUI's **New…** names the project folder the way Godot does: in kebab-case by default (`My Game` → `my-game`), or with the directory naming convention set in Godot's editor settings. Before, the folder kept the project name as typed.
  - `godot-manager new` now adds the Godot icon (`icon.svg`, set as the project icon) and `.editorconfig`, like a project created from Godot.

## [2.4.2] - 2026-11-20

### Fixed

- **Checking for updates.** Settings has a **Check now** button that says whether you have the latest version, shows the new one, or says why it couldn't check. Before, there was no way to check by hand, and nothing showed when you were up to date. A check that fails on startup, for example with no network, now runs again the next time you open the GUI instead of waiting a day.

## [2.4.1] - 2026-11-20

### Added

- **`godot-manager dirs`** prints the folders godot-manager uses: `GODOT_DIR`, the one it uses when `GODOT_DIR` is not set, and where versions and export templates go.

### Changed

- **GUI dialogs open in their own windows** instead of inside the main window, and choosing a file or folder uses the system's file picker.
- **A roomier GUI.** The top bar, the screens, the action buttons and the list rows have more padding, and the window opens at 1152×720.
- **Settings are grouped in sections.** The versions folder shows the actual default folder instead of an empty field, and **Restore** goes back to it after you pick another one.

## [2.4.0] - 2026-11-19

### Plugins

- `godot-manager plugins add` installs plugins from the [Godot Asset Store](https://store.godotengine.org) (`store:publisher/slug`) or from a GitHub repo's releases (`github:owner/repo`), picking the newest version that works with the project's Godot.
- Each project tracks its plugins in `plugins.json` (what it asks for) and `plugins.lock` (exact versions, zip sha256 and a hash of every file). You can commit both, and `plugins install` rebuilds `addons/` from them.
- New subcommands:
  - `plugins search`: search the Asset Store.
  - `plugins outdated`: shows new versions that work with the project's Godot, and which ones need a newer Godot.
  - `plugins update`: never overwrites files you changed by hand unless you pass `--force`.
  - `plugins pin` / `plugins unpin`: freeze a plugin on a version, or let it follow the newest one again.
- **Presets**: `presets save|add|show|drop|remove` keep the plugins you always use, and `plugins apply <preset>` adds them to a project.
- **`godot-manager new`** creates an empty Godot 4 project with a pinned version, a renderer and a plugin preset.
- The work is done by [`pluginkit/`](https://github.com/dannroda/godot-manager/tree/main/pluginkit), a GDScript library that editor addons can use too. The CLI runs it with an installed Godot 4.2+.

### GUI

- **Projects → New…** creates a project with a Godot version and a plugin preset.
- A project's details let you:
  - add plugins from the Asset Store or GitHub (godot-agent and scope-compass are one click away);
  - check for and apply updates;
  - pin or unpin a version;
  - install missing plugins;
  - apply or save presets.
- The Versions tab marks versions that have a newer release in their series and upgrades them. **Free up space** deletes the versions no project uses.
- Settings can put godot-manager on the `PATH`.

### CLI

- **macOS support**: installs the `.app` (universal or per architecture) and the dSYM debug symbols. There are release archives for `darwin-amd64` and `darwin-arm64`.
- **`outdated` / `upgrade`**: find newer releases in a version's series and install them with the same extras.
- **`prune`**: deletes the versions that neither the default nor any of your projects use.
- **`path add|remove`**: puts `godot-manager` and `godot` on the `PATH`.
- **`completion bash|zsh|fish|powershell`**: shell completion.
- `self-update` detects Scoop, Homebrew and system packages and tells you to update through them.
- `godot-manager.exe` and `godot.exe` now have the app icon.

### Packaging

- **Scoop**: `scoop bucket add godot-manager https://github.com/dannroda/godot-manager` then `scoop install godot-manager`.
- **Arch Linux**: `packaging/arch/PKGBUILD` builds a `godot-manager-bin` package from the release binaries, for use with `makepkg -si`.
