# Notes

Reverse-engineered from the install at
`C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3`, plus the
modding wiki at <https://wiki.transportfever3.com/>. Everything with a file and
line reference was read out of the shipped content; everything under "Open
questions" still has to be confirmed in-game.


## Verdict: feasible, and cheap

The mod needs **no new art, no new geometry and no new engine behaviour**. The
stock station already supports a single platform on either side - the player can
build that configuration today by hand, by adding a platform module to the left
slot and deleting the one on the right. All the mod has to do is seed the other
slot at placement time and expose a parameter for it.


## The construction in question

The bus station *and* the cargo truck station are the same construction:

    ::/stations/street/modular_street_station/modular_terminal.con

shipped in `base/content/stations/street.zip` as
`street/modular_street_station/modular_terminal.con.lua`. The `::/...` form is
the resource name the engine uses; it shows up verbatim in
`mission/guide_system/main/guide_system_story.tl:18`.

It is a *modular* construction with six `constructionTemplates` (all
`type = "DYNAMIC"`): three passenger terminals (era A/B/C) and three universal
cargo terminals (era A/B/C). The other `addCargoTemplate` calls for liquid /
bulk / flatbed / goods are commented out in the stock file.

Every one of those six templates carries the same parameter, from `makeParams()`
in `modular_terminal.con.lua`:

```lua
{
    key = "platforms",
    name = _("Platforms"),
    values = { "street_station_terminal_1.tga",
               "street_station_terminal_2.tga",
               "street_station_terminal_4.tga" },
    defaultIndex = 1,
    displayMode = "Horizontal",
    uiType = "IconButton"
}
```

That is the 1 / 2 / 4 selector the README is about. The cargo templates add a
second param, `specialization` (Universal / Liquid / Bulk / Flatbed / Goods).

Note that `constructionTemplates` is marked `[DEPRECATED] Use metaconstructions
instead` in `api/tealdef/api/type.d.tl:1705`, but **no shipped content uses
metaconstructions at all** - a scan of every archive in `base/content` finds no
`metacon.lua`. The deprecated path is the live one.


## Where the asymmetry comes from

`modular_terminal.script.lua`, `createTemplateFn` (around line 1178). Slots are
addressed by `(coordI, coordJ, variant)`; `coordI` runs left-to-right with the
station entrance between `-1` and `0`:

```lua
-- right
result[MangleId({0, 0, variant})] = module
result[MangleId({0, 1, variant})] = module
if params.platforms > 2 then
    result[MangleId({1, 0, variant})] = module
    result[MangleId({1, 1, variant})] = module
end
-- center
result[MangleId({55, 0, moduleVariants.hor_entrance_exit})] = "entrance_exit.module"
-- left
if params.platforms > 1 then
    result[MangleId({-1, 0, variant})] = module
    result[MangleId({-1, 1, variant})] = module
end
if params.platforms > 2 then
    result[MangleId({-2, 0, variant})] = module
    result[MangleId({-2, 1, variant})] = module
end
```

So:

| `platforms` | occupied `coordI` | symmetric? |
| --- | --- | --- |
| 1 | `0` | **no** |
| 2 | `0`, `-1` | yes |
| 4 | `1`, `0`, `-1`, `-2` | yes |

Only the single-platform case is lopsided, which is exactly what the README
describes. The mirror map `coordI -> -1 - coordI` is a no-op for 2 and 4, and
swaps `0 <-> -1` for 1.

Slot ids are packed by two local functions in the same file:

```lua
MangleId   = 200000 * (coordJ + 100) + 100 * (coordI + 100) + variant
DemangleId -- inverse: variant = id % 100, then coordI, then coordJ
```

`moduleVariants` (line ~1149): `passengerTerminal = 0`, `cargoTerminal = 1`,
`hor_entrance_exit = 3`, ... The entrance sits at the sentinel `coordI = 55` and
**must not be mirrored**.


## Why no geometry work is needed

`updateFn` in the same script derives the whole layout from whichever slots are
occupied. It computes `minCoordI` / `maxCoordI` and then `leftLen` / `rightLen`
by walking outwards from the centre in both directions (lines ~1366-1435), and
it handles a lone left platform explicitly:

```lua
if coordI == 0 then
    platformXPos =  (centerSize + platformSize) * 0.5
elseif coordI == -1 then
    platformXPos = -(centerSize + platformSize) * 0.5
else
    ...
```

The left/right model variants already exist as separate `.mdl` files
(`cntr_btm_l` / `cntr_btm_r`, `entr_l` / `entr_r`, `cargo_pltfrm_l_*` /
`cargo_pltfrm_r_*`, ...) and `updateFn` picks between them from the sign of
`coordI`. Nothing in that path assumes at least one platform on the right.

This is the single most important finding: the target configuration is one the
stock code already renders correctly, so the mod is a *seeding* change, not a
construction rewrite.


## The hook: `addModifier("loadConstruction", ...)`

`base/content/base.zip`, `base/mod.lua:142`:

```lua
function addModifier(key, fun)
    table.insert(modifiers[key], fun)
end

function applyModifiers(key, name, data)
    for i, v in ipairs(modifiers[key]) do
        data = v(name, data)
    end
    return data
end
```

The `modifiers` table (lines ~66-140) includes `loadConstruction`, `loadScript`,
`loadModule`, `loadMetaConstruction` and ~45 others. `data` is the table the
resource file's `data()` returned - i.e. the raw file-format shape, including
`constructionTemplates`, `params` and `createTemplateScript`, none of which the
`ConstructionDesc` Teal record exposes.

Precedents, both shipped:

- `base/base_mod.lua:217-230` - the base game itself registers two
  `loadConstruction` modifiers, to convert cargo types and to back-fill
  `edgeObject`.
- `mods/release/urbangames_vehicles_no_end_year/content/mod.script.lua` - a
  complete, minimal first-party script mod that does nothing but
  `addModifier("loadModel", ...)` from `runFn`. It is the template to copy.

`fileName` as passed to a modifier carries the `::` prefix -
`mission/modifier.lua:98` (`applyTree`) splits on `/` and looks for the segment
containing `::` to find where the resource path starts.

Per the wiki's "Mod Parameters & Scripts" page, modifiers must be registered in
`runFn`; they are applied when resources load, after every mod's `runFn` has
run. `postRunFn` is too late for a modifier but is where `api.res.*` edits go.


## Construction parameters: what can be added, and what must not change

`api/tealdef/api/type.d.tl:1723` defines `ConstructionScriptParam`. The fields
that matter here:

- `key`, `name`, `values`, `tooltips`, `defaultIndex`
- `uiType` - `Button` / `Slider` / `ComboBox` / `IconButton` / `CheckBox`
- `displayMode` - `Default` / `Compact` / `Horizontal` / `Vertical` / `Sparse`
- `location` - `Default` / `Toolbar`
- `yearFrom` / `yearTo`
- `postConstructionModifiable`
- `checkEnabledScript` - `function(params : {string : number}, scriptRefParams : table)`
  returning one of `Enabled` / `Hidden` / `Disabled` / `InputActionOnly`
  (`base/tealdef/gui/construction/construction_menu.d.tl:69-74`). Wired up in
  `gui/construction/construction_react_util.tl:801-806`, so it is live for
  construction params, not only for the built-in ones.

**Parameters are keyed by name, not by position.** `createTemplateFn` reads
`params.platforms`, `params.specialization`, `params.templateIndex`;
`checkEnabledFn` takes `{string : number}`. So *adding* a key is safe for
existing savegames - old stations simply have no value for it, and the code must
treat `nil` as the stock default.

Corollary, and the reason not to take the obvious shortcut: **do not turn
`platforms` into a four-value param** (1-left / 1-right / 2 / 4). The values are
returned as 1-based indices, so inserting a value shifts the meaning of every
already-built station's stored `platforms` value.

A direct precedent for a side-ish param on a stock street station:
`street/underground_station/underground_station.con.lua:12-21` declares
`platformOrientation` as a `Slider`.


## Wrapping the stock `createTemplateFn` instead of reimplementing it

`base/content/scripts.zip`, `scripts/util.tl:5`:

```lua
function util.useFn(ref : string) : function
    loaderHelper:useFn(ref)
    local t = game
    -- splits "path@a.b" on "@" then on "." and indexes `game` with each part
    ...
    return t as function
end
```

`game` has an `__index` metamethod that resolves resource paths
(`api/tealdef/main.d.tl`). The GUI uses this everywhere to call a `ScriptRef` -
e.g. `construction_react_util.tl:636, 802, 810, 821`.

That means our own `.script.lua` can resolve and call the stock function:

```lua
local orig = util.useFn(
    "::/stations/street/modular_street_station/modular_terminal.script@createTemplateFn")
```

and post-process its result, rather than forking the 40-line layout block. That
keeps the mod correct if Urban Games changes the stock layout - which matters,
because `modular_terminal.script.lua` is 3308 lines and we want to depend on as
little of it as possible.


## Mod packaging

Same as `town_clustering_1` / `external-connections_1`:

```
mod/<modid>/
  mod.json                    modId, revision, runScript, params, severity*
  _metadata/modinfo.json      name, summary, description, authors, tags
  _content.json               { "archives": null, "files": [ ... ] }
  content/...                 .script.lua / .script.tl picked up by extension
```

`mod.json` script refs take the form `<modid>::/<file>@<fn>` - see
`mods/release/urbangames_vehicles_no_end_year/mod.json`.

Deploy target (`deploy.ps1` in the sibling repos):
`C:\Program Files (x86)\Steam\userdata\<id>\3493540\local\mods\<modid>`, or
`staging_area\` when it needs to be publishable. Log is
`...\local\crash_dump\stdout.txt`; `debugPrint` / `log.*` write there.


## Confirmed in-game

Everything above was read out of the install; these were settled by running the
mod (log line from `crash_dump/stdout.txt`, 2026-10-08):

```
[pick-platform-side] patched 6 templates of
::/stations/street/modular_street_station/modular_terminal.con.lua, wrapping
::/stations/street/modular_street_station/modular_terminal.script@createTemplateFn
```

- **A `loadConstruction` modifier can add a construction parameter to a stock
  station, and the build menu renders it.** Six templates, as predicted.
- **The `fileName` handed to a `loadConstruction` modifier keeps the `.lua`
  extension** - `...modular_terminal.con.lua`, not `...modular_terminal.con`.
  The bare `.con` form in `mission/guide_system/main/guide_system_story.tl` is
  the *resource name*, which is not the same string. Match with a substring
  test, not equality.
- **Changing a construction param during placement does re-run
  `createTemplateFn`** - that is what makes the new parameter take effect live.
- **`util.useFn` works from a resource script**, so the stock `createTemplateFn`
  can be resolved and wrapped at placement time; `loaderHelper` is reachable
  there. No `could not resolve` line was logged, so the mod's fallback seeding
  never ran. `scripts/util.tl` only pulls in `scripts/mathutil.lua`, no GUI
  dependencies, so requiring it from a resource script is safe.
- **`checkEnabledScript` returning `Hidden` behaves**: the parameter is absent
  from the menu for 2 and 4 platforms and the stored value survives.

This also makes open question 2 moot - patching the stock script via
`loadScript` was never needed.


- **A placed station survives the mod being removed.** Tested with a save
  containing an other-side station: loads clean, keeps its layout, no errors.
  The engine does not prune or complain about the now-undeclared
  `platformSide` param it still stores. `severityRemove` is `None`. This is the
  general rule about seeding-only mods - see the project root `NOTES.md`.


## Open questions

1. **Which on-screen side is `coordI = 0`?** The stock comment says "right", but
   what the player sees depends on build rotation, so there is no rotation-
   independent answer and the parameter labels do not try to give one. Still
   worth knowing for the listing screenshots.
2. Whether the rail modular station
   (`::/stations/rail/modular_station/modular_station.con`) has the same
   single-platform asymmetry. Out of scope for this mod, but the same hook would
   serve it.


## Things deliberately not done

- No `api.res.constructionRep.getAsTable` / `setAsTable` editing. It would
  probably also work, but `ConstructionDesc` in `api/tealdef/api/type.d.tl:1661`
  does not declare `createTemplateScript`, `preProcessScript`, `upgradeScript`
  or `namePrefix` even though the stock `.con.lua` sets all of them, so a
  round-trip through that record is not obviously lossless. See
  external-connections' `NOTES.md`, "The .d.tl files are incomplete".
- No shadowing of the stock `modular_terminal.con.lua` by shipping a file at the
  same path. It would be the most direct edit, but it hard-forks a base game
  file and conflicts with any other mod touching the same station.
