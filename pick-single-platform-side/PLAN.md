# Plan

Feasibility: **yes**. See `NOTES.md` for the evidence. This plan assumes those
findings.

Status: **working in-game.** Phases 0-3 are done and confirmed (see
`NOTES.md`, "Confirmed in-game"). What is left before publishing is the real
listing screenshot, the rest of the Phase 4 matrix, and the validator run.

Shape of the mod: a script-only mod that registers one
`addModifier("loadConstruction", ...)` from `runFn`, which (a) adds a
`platformSide` parameter to the six templates of the stock street station and
(b) repoints the station's `createTemplateScript` at our own function, which
calls the stock one and then mirrors the seeded slots when the player asked for
it.

No models, no textures, no icons, no changes to any base game file.


## Naming

Standardised on the folder name (the README title was changed to match):

- repo / folder: `pick-single-platform-side`
- `modId`: `pick_single_platform_side_1` (wiki allows only `a-z 0-9 _`)
- display name: "Pick Single Platform Side"
- log prefix: `[pick-platform-side]`


## Phase 0 - the load-bearing assumption *(confirmed)*

That a `loadConstruction` modifier can add a construction parameter to a stock
station and have the build menu render it. Rather than spike it separately the
real mod logs what it did, and the first launch answered it: six templates
patched, stock `createTemplateFn` resolved and wrapped, parameter renders,
changing it updates the preview. Details in `NOTES.md`, "Confirmed in-game".

The health check for later runs, after a game update: `stdout.txt` should carry
one `[pick-platform-side] patched 6 templates ...` line. A different count means
the stock template shape changed; no line at all means the modifier never
fired; a `could not resolve stock createTemplateFn` line means `util.useFn`
stopped working from a resource script and the mod is running on its own
fallback seeding.


## Phase 1 - scaffold *(done)*

This mod lives inside the `tf3-mods` collection rather than in its own repo, so
there is no `LICENSE` / `.gitattributes` / per-mod `CLAUDE.md`; the root
`CLAUDE.md` covers the project. `tlconfig.lua` + `all_def.tl` are not needed
either - the one script is `.lua`, not `.tl`.

```
pick-single-platform-side/
  README.md
  NOTES.md
  PLAN.md                   this file
  deploy.ps1                from town-redistribution, $ModId + log prefix changed
  mod/pick_single_platform_side_1/
    mod.json
    strings.json            "Other side", ten languages
    _content.json
    _metadata/modinfo.json
    content/pick_platform_side.script.lua
```

Still missing before this could be published: `_metadata/0.png` at 1920x1080.

`mod.json`:

```json
{
    "modId": "pick_single_platform_side_1",
    "revision": 1,
    "cosmetic": true,
    "visible": true,
    "autoActivate": false,
    "dependencies": null,
    "incompatibilities": null,
    "options": null,
    "params": null,
    "preRunScript":  { "fileName": "" },
    "runScript":     { "fileName": "pick_single_platform_side_1::/pick_platform_side.script@runFn" },
    "postRunScript": { "fileName": "" },
    "severityAdd": "None",
    "severityRemove": "None"
}
```

`severityRemove` is `None`. A station built with the platform on the other side
stores `platformSide = 2`, which nothing reads once the mod is gone; the
removal test below passed, so the warning it would otherwise raise is not
warranted.

`cosmetic: true` - it changes nothing about simulation, cost or capacity, so it
should not disable achievements. Same reasoning as `town_clustering_1`.


## Phase 2 - the modifier *(done)*

`content/pick_platform_side.script.lua`, one file, three exported functions.

```lua
local STATION = "/stations/street/modular_street_station/modular_terminal.con"
local SELF    = "pick_single_platform_side_1::/pick_platform_side.script"

local function makeSideParam()
    return {
        key = "platformSide",
        name = _("Platform Orientation"),
        values = { _("Standard"), _("Other side") },
        defaultIndex = 1,                     -- 1 = stock behaviour
        displayMode = "Horizontal",
        checkEnabledScript = { fileName = SELF .. "@checkSideEnabledFn", params = {} },
    }
end

function data()
return {
    runFn = function(captureParams, settings, allModParams)
        addModifier("loadConstruction", function(fileName, data)
            if not string.find(fileName, STATION, 1, true) then return data end
            ...
            return data
        end)
    end,

    createTemplateFn = function(captureParams, params) ... end,
    checkSideEnabledFn = function(captureParams, params) ... end,
}
end
```

The labels deliberately avoid "Left" / "Right": which on-screen side
`coordI = 0` lands on depends on how the station is rotated when it is placed,
so a fixed left/right label would be wrong half the time. "Standard" and
"Other side" are true regardless of rotation, and they make the no-op option
obviously the no-op one. That retires open question 3 in `NOTES.md` as a
blocker - still worth knowing, but nothing depends on it.

The wording is also chosen for free localisation. Checked against the shipped
gettext catalogs (`base/strings/<lang>/LC_MESSAGES/base.mo`): `"Platform
Orientation"` and `"Standard"` are present in every language - the first is what
the stock underground street station calls its own equivalent control
(`underground_station.con.lua:14`) - while `"Platform Side"` and `"Default"` are
in none of them. Only `"Other side"` had to be translated, in the mod's
`strings.json`. The English catalog holds nothing but ID-style keys, so a plain
English `_("...")` msgid falls through to its own literal; `strings.json` lists
`en` explicitly anyway, to say so out loud.

The modifier body, in order:

1. Bail unless `fileName` ends with `STATION` (plain `find`, not a pattern -
   the string contains `/` and `.`).
2. For each entry of `data.constructionTemplates`, if `template.data.params`
   contains a param with `key == "platforms"`, insert `makeSideParam()`
   immediately after it. Driving off the presence of `platforms` rather than
   off a hard-coded template count means the mod keeps working if Urban Games
   adds an era D or re-enables the four commented-out cargo specialisations.
3. Read the stock `data.createTemplateScript.fileName` (do not assume the
   literal) and make it absolute. The stock declares it *relatively*
   (`"modular_terminal.script@createTemplateFn"`), which would resolve against
   *our* folder once we are the caller, so it is joined to the directory of the
   `fileName` the modifier was handed. Then replace `createTemplateScript` with
   `SELF .. "@createTemplateFn"`, passing `{ stockRef, stockParams }` as the
   capture params so the stock function still gets its own.
4. Bail out, loudly and without patching, if there is no
   `createTemplateScript` or no template carried a `platforms` param. A mod that
   does nothing beats a mod that half-patches a station.
5. Log once: how many templates were patched, and the stock ref being wrapped.
   Cheap, and makes a future game update's breakage obvious in the log instead
   of silent.

`createTemplateFn`:

```lua
-- (coordI, coordJ, variant) <-> slot id, copied from modular_terminal.script.lua
local function mangle(i, j, v)   return 200000 * (j + 100) + 100 * (i + 100) + v end
local function demangle(id)
    local v = id % 100
    local r = (id - v) / 100 % 2000
    return r - 100, ((id - v) / 100 - r) / 2000 - 100, v
end
```

- Call the wrapped stock function to get the slot map.
- Return it unchanged unless `params.platformSide == 2`. `nil` is treated as 1,
  so an older savegame and a hidden parameter both mean "stock".
- Otherwise rebuild the map with `coordI -> -1 - coordI`, but **only** for slots
  whose variant is `passengerTerminal` (0) or `cargoTerminal` (1). Everything
  else - above all the entrance at the `coordI = 55` sentinel - passes through
  untouched.

There is deliberately no `platforms == 1` guard on the mirror. For 2 the slot
set `{0, -1}` maps to `{-1, 0}` and for 4 `{1, 0, -1, -2}` maps to
`{-2, -1, 0, 1}`; since every platform slot holds the same module, both produce
a map identical to the input. One code path, provably a no-op where it should
be, and it stays correct if the stock seeding changes.

`resolveStockFn` wraps `util.useFn` in a `pcall`. In practice `util.useFn`
*does* work from a resource script (confirmed - see `NOTES.md`), so the wrap is
the live path and `seedLikeStock`, the 25-line copy of the stock seeding, is a
safety net against a future game update breaking the resolve.

**That fallback has therefore never executed.** Its one risky detail is that it
returns absolute module names
(`::/stations/street/modular_street_station/...`), since it emits them from a
different folder than the stock script does - the stock `.con` uses that same
absolute form for its own icons, so this is very likely right, but it is
reasoning rather than observation. To exercise it, temporarily corrupt the
`stockRef` written by the modifier and place a station: the log should show the
`could not resolve` line and the station should come out identical. Worth doing
at some point; the alternative is dropping the fallback and accepting that a
future resolve failure breaks station placement outright.

`checkSideEnabledFn(captureParams, params)` returns `"Enabled"` when
`(params.platforms or 1) == 1`, else `"Hidden"` - the param is meaningless for
the symmetric 2- and 4-platform layouts.


## Phase 3 - polish *(done, except the real screenshot)*

- `_metadata/modinfo.json` - name, summary, description, `authors`
  (`Bram Fokke` / `CREATOR`), `tags: ["Script Mod"]`, and the AI disclaimer line
  used in `town_clustering_1`.
- `_metadata/1.jpg` - the in-game shot of the placement dialog, 860x663.
- `_metadata/0.png` at 1920x1080 - the grid image, built by
  `tools/make_listing_image.ps1`, which composites `1.jpg` at **native size**
  next to a title block. Native size on purpose: the screenshot is smaller than
  the canvas and upscaling it to fill only softens it. Run the script with
  `-Schematic` to fall back to the flat placeholder it drew before there was a
  screenshot.
- `strings.json` at the mod root, format
  `{"<lang>": {"<msgid>": "<text>"}}` per the wiki's Mod Definition page. Only
  `"Other side"` is in it, in all ten shipped languages; the other two labels
  come from the base catalogs.


## Removing the mod from a savegame *(confirmed)*

Tested 2026-10-08: placed a station with the platform on the other side, saved,
quit, deactivated the mod, reloaded. The save loads clean - the `Active mods:`
block does not list the mod, its log prefix is absent from the whole session
(so `runFn` never ran and the construction was fully stock), there are no
`ERROR` lines, and every warning is ordinary engine/GUI noise. `severityRemove`
is `None` accordingly. The general version of this finding is in the project
root `NOTES.md`.

A station already built keeps its layout because the mirrored arrangement is
**baked into the construction entity, not re-derived**:

- `createTemplateFn` - the only thing the mod replaces - runs at *placement*
  only. It seeds the initial module map.
- From then on the construction carries its own `params.modules`
  (`gui/construction/construction.tl:4126`, `constructionComp.params.modules`),
  which `preProcessFn` mutates whenever the player adds or removes a module.
- `updateFn`, which builds the actual geometry, reads `params.modules` and
  never `params.platforms`. The mod does not touch `updateFn`, so after the mod
  is gone the stock one renders the same stored module map - the same
  configuration a player could have assembled by hand.
- The leftover `platformSide = 2` on a built station is then read by nobody.

The open part of this was whether the engine prunes or validates stored
construction params against the current desc on load, and whether that could
force a refresh. It does not: the leftover `platformSide` is simply read by
nobody.


## Phase 4 - test matrix

Each row is: deploy, restart, build, look. The basic case is confirmed working;
the rest is the pre-publication sweep.

| case | expectation | done |
| --- | --- | --- |
| passenger, `platforms = 1`, side = Standard | identical to vanilla | yes |
| same, side = Other side | platform across the entrance, correct `_l`/`_r` models, no gap or doubled kerb | yes |
| the same two for eras A/B/C | ditto | |
| cargo universal era A/B/C, both sides | same, and the truck lanes still connect | |
| `platforms = 2` and `4` | side param hidden; geometry unchanged from vanilla | |
| flip side back and forth in the menu | preview updates each time, no stale modules | |
| flip `platforms` 1 -> 2 -> 1 with side = Other side | ends up on the other side, not the default one | |
| build on the other side, then hand-edit modules in the entity window | behaves like any hand-built station | |
| load a pre-mod savegame with existing 1-platform stations | unchanged, no log errors | |
| remove the mod from a save containing an other-side station | station survives; decides final `severityRemove` | yes |
| with another station-touching mod active | modifier chain still applies ours | |
| tram track / catenary variants (`tramTrack` 1/2/3) | no interaction | |

Watch `...\local\crash_dump\stdout.txt` for `[pick-platform-side]` throughout.


## Phase 5 - publishing

1. ~~Replace the placeholder listing image.~~ Done - `0.png` now composites the
   real screenshot. More in-game shots can go in as `2.jpg`, `3.jpg`, ... and
   `mapzilla_1` shows the game is happy with `0.png` plus a run of `.jpg`s.
2. `.\deploy.ps1` - done; the mod is in `staging_area\` and nowhere else.
   Deploying is staging-only now, for the whole project - see the root
   `NOTES.md`.
3. `.\deploy.ps1 -Validate` - **done, passed.** With the game closed:

   ```
   PC      : level=Info critical=False
   Console : level=Info critical=False
   Messages: none
   ```

   and `Validation Passed without issues.` in the log. The script now passes a
   report path and a cook output path, waits out the exe's hand-off to a second
   process, and judges by the report rather than the exit code (which is `53`
   even on a clean pass). Details in the root `NOTES.md`.
4. Publish from the in-game Mod Manager's staging area entry.

Checked already against the wiki's limits: `name` 25 chars (max 32), `summary`
85 (max 100), neither with line breaks; `modId` is `a-z0-9_` only; `revision`
is 1 for the first upload and goes up with each published update. `url` is
omitted - this mod has no repo of its own, it lives in the `tf3-mods`
collection.

`severityRemove` is `None` - the mod-removal row above passed.


## Fallbacks, if Phase 0 or 2 does not hold

**Alternative A - our own `createTemplateFn`, no wrapping.** If `util.useFn`
cannot resolve the stock function from our script, copy the ~40-line layout
block out of `modular_terminal.script.lua` into our script and emit the mirrored
layout directly. Works, but pins the mod to the current stock layout and has to
be re-checked after game updates.

**Alternative B - a second construction, not a new parameter.** If a
`loadConstruction` modifier cannot add a parameter the build menu honours, use
`postRunFn` and `api.res.constructionRep.addAsTable` to register a mirrored copy
of the station as its own menu entry. This gives up on "modifies the placement
dialog" - the player picks a different station instead of a different side - but
it is independent of everything uncertain above.

**Alternative C - shadow the stock `.con.lua`.** Ship
`content/stations/street/modular_street_station/modular_terminal.con.lua` as a
copy of the stock file with the extra param. Most direct, and the worst
behaviour under game updates and mod conflicts. Last resort.


## Scope held back

- The rail modular station. Same hook would work; different `.con`, different
  slot conventions, and the README does not ask for it.
- The small bus stops (`street/small_stops/*`). These already ship one-sided and
  two-sided as separate constructions, so there is no asymmetry to fix.
- Making the side switchable after the station is built
  (`postConstructionModifiable`). The player can already move platform modules
  in the entity window, so this would add a second way to do the same thing.
