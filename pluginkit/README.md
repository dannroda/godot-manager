# pluginkit

Installs, updates, and pins Godot plugins from the [Godot Asset Store](https://store.godotengine.org) and from GitHub releases. Each project records its plugins in two JSON files that any tool can read. The library is plain GDScript with no editor APIs. godot-manager runs it from its CLI with a headless Godot, and an editor addon (such as godot-agent) can load the same files directly. Both therefore share one implementation and one file format, and neither depends on the other.

Requires Godot 4.2 or newer. The tests run on 4.2.2 and 4.7.2.

## Files in the project root

`plugins.json` lists what the project asks for. People edit it, and so do tools:

```json
{
  "plugins": {
    "dialogue-manager": {"source": "store:nathanhoad/dialogue-manager"},
    "godot-agent": {"source": "github:dannroda/godot-agent", "version": "v0.1.32"},
    "scope-compass": {"source": "github:dannroda/scope-compass", "prerelease": true}
  }
}
```

- `source`: either `store:publisher/slug` or `github:owner/repo`.
- `version` (optional): pins that exact version. Without it, the plugin follows the newest release that works with the project's Godot.
- `prerelease` (optional): lets prereleases through. A plugin that only has prereleases gets one anyway.

`plugins.lock` records what was installed. Only tools write it:

```json
{
  "schema": 1,
  "plugins": {
    "dialogue-manager": {
      "source": "store:nathanhoad/dialogue-manager",
      "version": "v3.10.5",
      "release": "7922",
      "sha256": "<sha256 of the zip>",
      "godot_min": "4.3",
      "godot_max": "",
      "folders": ["addons/dialogue_manager"],
      "files": {"addons/dialogue_manager/plugin.cfg": "<sha256>"}
    }
  }
}
```

- `release`: the release id in its source. For the Store it is the numeric id, because Store download links expire after 10 minutes. For GitHub it is the tag, and the entry also has a `url`.
- `files`: every file the plugin wrote, with its hash. The library uses these hashes to tell whether someone changed a file by hand before it overwrites or deletes it.
- Paths are relative to the project root and use `/`. Keys are sorted, so diffs stay small.

## Install rules

These follow the editor's own installer:

1. If the zip has a single top-level folder, that folder is stripped, unless it is `addons/`.
2. If the zip contains `addons/`, only that is installed. Demos, READMEs and `project.godot` files are skipped.
3. Entries that would land outside the project are dropped. These are paths with `..`, a leading `/`, a drive letter, or a backslash.
4. A file that already exists counts as a conflict when:
   - no installed plugin owns it,
   - another plugin in the lock owns it, or
   - this plugin owns it but its hash no longer matches the lock.

   Any conflict stops the install unless `force` is set.
5. A file that is identical to the one in the zip is adopted without being written. This means a plugin that was copied in by hand, at the same version, does not cause a conflict.
6. An update deletes the files that the new version no longer ships. It also deletes the `.import` and `.uid` files the editor generated next to them, and any folders left empty.

## Using it from an addon

Copy only the library scripts into your addon: `versions.gd`, `sources.gd`, `installer.gd`, `lockfile.gd`, `http.gd` and `kit.gd`. Leave out `project.godot`, because the editor ignores any folder that contains one. Leave out `cli.gd` and `tests/` as well.

```gdscript
const Kit := preload("res://addons/your_addon/pluginkit/kit.gd")
const Http := preload("res://addons/your_addon/pluginkit/http.gd")

var http := Http.new(self)  # any Node inside the tree
var kit := Kit.new(ProjectSettings.globalize_path("res://"), http, OS.get_cache_dir().path_join("plugins"))
kit.godot = Engine.get_version_info().string
var result: Dictionary = await kit.add("store:nathanhoad/dialogue-manager")
if result.has("error"):
    push_error("%s %s" % [result.error, result.details])
else:
    # Your addon handles the editor side: rescan the filesystem and enable result.plugins.
    EditorInterface.get_resource_filesystem().scan()
```

Operations: `search(query, page)`, `add(spec, name, pin, prerelease)`, `install()`, `outdated()`, `update(names)`, `pin(name, version)`, `unpin(name)`, `remove(name)` and `status()`. For presets there are `apply(preset_path)`, which merges a preset into `plugins.json` and installs, and `preset_add(preset_path, specs)`. A preset is a file with the same shape as `plugins.json`.

- Each operation returns a `Dictionary`. On failure it has `error`, a stable code listed at the top of `kit.gd`, and `details`.
- The `progress` signal reports `check`, `download`, `install` and `remove` while the operation runs.

## Command line

```sh
godot --headless --path pluginkit --script res://cli.gd -- add store:pub/slug --project /path/to/game --out result.json --godot 4.5
```

Progress goes to stdout, one `@pk {...}` line per event. The result is written to `--out`. godot-manager embeds these files and runs them like this.

## Tests

```sh
godot --headless --path pluginkit --script res://tests/run_tests.gd
```

The tests make no network calls. They use a fake HTTP client and zips built during the test run.
