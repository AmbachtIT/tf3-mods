# Transport Fever 3 modding notes

Findings that apply across mods. Mod-specific detail stays in each mod's own
`NOTES.md`.

Everything here is either read out of the install or confirmed by running the
game; where it is confirmed, the log line is quoted. Game build 40408.


## A mod that only *seeds* a construction is safe to remove

**Confirmed** 2026-10-08, with `pick-single-platform-side`: place a station with
a mod-chosen layout, save, quit, deactivate the mod, reload. The save loads
clean and the station keeps its layout.

The reason is worth knowing before writing any construction mod, because it
decides `severityRemove` and how much a mod is allowed to do:

- A construction's `createTemplateFn` runs **at placement only**. It seeds the
  initial module map and is never consulted again.
- The placed construction then carries its own `params.modules` - see
  `gui/construction/construction.tl`, `constructionComp.params.modules`. The
  stock `preProcessFn` mutates that map whenever the player adds or removes a
  module, so it, not the template function, is the source of truth.
- `updateFn`, which builds the actual geometry, reads `params.modules`. For the
  street station it never reads `params.platforms`.
- Leftover params from the removed mod (here `platformSide = 2`) are simply read
  by nobody. The engine does **not** complain about a stored construction param
  that no longer exists in the desc, and does not force a refresh.

So the rule of thumb: **a mod that changes what gets built is removable; a mod
that changes how a built thing behaves every frame is not.** The first kind
bakes its decision into the savegame at build time and can declare
`severityRemove: "None"`.

How the test was run, since "removing" is ambiguous: the mod stays on disk and
is *deactivated for the savegame*. That is the real removal path - mods are
per-savegame, so a deactivated mod's `runFn` never runs and its modifiers are
never registered. Verify it actually was inactive rather than assuming: the
`Active mods:` block in the log must not list it, and the mod's own log prefix
must be absent from the whole session.

What a clean removal run looks like, for comparison next time - no `ERROR`
lines at all, and the only warnings are engine/GUI noise:

| warning | what it is |
| --- | --- |
| `Preserved props id N of an instance of ...` / `It has been created by by an instance of MainPage` | React GUI chatter, by far the bulk of it |
| `Not removed conflicting gamepad-only key assigment (...)` | stock keybinding clashes |
| `Texture error: Could not find texture ''` | fires at the main menu too, before any save is loaded |
| `Multiple (2) mods with same id found <id>` | the same mod in both `mods\` and `staging_area\`; staging wins |
| `Ignoring Set() on expired ReactRefWrap` + `stack traceback:` into `::/gui/main/selector_react_util.tl` | base game, `MESSAGE` level, happens on closing an entity selection |

A real problem would look different: an `ERROR` line, a `placeholders/` or
`missing_street_terminal.con` substitution, or the mod's own prefix appearing
when it should not.


## Resource modifiers

`addModifier(key, fn)` (`base/content/base.zip`, `base/mod.lua:142`) registers a
transform that runs as resources load. Register from `runFn`; `postRunFn` is too
late for a modifier and is where `api.res.*` edits go instead.

```lua
addModifier("loadConstruction", function(fileName, data)
    ...
    return data
end)
```

- `data` is the table the resource file's `data()` returned - the **raw file
  format**, including fields the Teal records do not declare
  (`constructionTemplates`, `createTemplateScript`, `preProcessScript`, ...).
- The key list is the `modifiers` table in `base/mod.lua` (~lines 66-140):
  `loadConstruction`, `loadModel`, `loadModule`, `loadScript`,
  `loadMetaConstruction`, `loadTrack`, `loadStreet`, ... ~45 of them.
- Shipped examples: `base/base_mod.lua:217-230` (the base game modifying its own
  constructions) and `mods/release/urbangames_vehicles_no_end_year/content/mod.script.lua`,
  a complete minimal script mod that is nothing but one `addModifier` call.

**The `fileName` a modifier receives keeps its extension.** Confirmed: it is
`::/stations/street/modular_street_station/modular_terminal.con.lua`, *not*
`...modular_terminal.con`. The bare form is the **resource name**, a different
string - that is what appears in e.g. `mission/guide_system/...`. Match with a
substring test, never equality.


## From a mod, `require` needs the `::/` prefix for base content

A bare `require "/scripts/vec3.tl"` inside a mod resolves **inside that mod's
own namespace**, not the base game. Confirmed 2026-10-08 by the validator:

```
Error message: module 'multi_layer_probe_1::/scripts/vec3.tl' not found:
Could not find file multi_layer_probe_1::/scripts/vec3.tl
Stack trace: base/content/base.zip/base/init.lua (104): require
```

Base content must be `require "::/scripts/vec3.tl"`. The trap is that **the
shipped station scripts use bare paths** - `modular_station.script.lua:1-8` is
all `require "/scripts/vec3.tl"` - and copying that idiom into a mod breaks it.
Stock content gets away with it because it *is* the base mod, so its own
namespace is the one you want.

So when porting a snippet out of `base/content`, rewrite every bare `require`.
`::/` is also right for resource names elsewhere (model ids, `.street_template`,
`.bridge` and `.tunnel` refs), and `<modid>::/` for the mod's own files, which is
the form `mod.json` uses for `runScript`.

**The rule bites a third way: resource names a mod *returns*.** A mod that
delegates to a stock function and passes its output on has to rewrite the paths
in it. The stock rail station's `createTemplateFn` seeds module names like
`/stations/rail/modular_station/platform_passenger_era_c.module`; returning
those unchanged from a mod's own `createTemplateFn` gives

```
Error message: Could not find module resource
Res name: multi_layer_stations_1::/stations/rail/modular_station/platform_passenger_roof_era_c.module
In function: modules_util::PatchParams
```

followed by `Error running updateFn for construction`, so **nothing is built at
all**. Confirmed 2026-10-08.

**And a fourth way: model ids and resource names *inside* a delegated result.**
A mod that lifts or edits a stock construction's output has to rewrite the paths
in it too - `models[i].id` ("/stations/rail/era_c/perron_5.mdl"),
`edgeLists[i].params.type`
("/infrastructure/track/standard/standard.street_template"), ground-face `key`s.
An unresolvable model id does not error; **the game substitutes a placeholder
cube**, which is how this one announced itself. Confirmed 2026-10-08.

The general form, worth applying to anything handed back from a stock function:

```lua
local function absoluteRes(name)
    if type(name) ~= "string" then return name end
    if string.find(name, "::", 1, true) then return name end
    if string.sub(name, 1, 1) == "/" then return "::" .. name end
    return name
end
```


## `util.useFn` is per-thread, and not equally willing on every thread

Each engine thread runs its own Lua state with its own copy of a resource
script, so a resolved-function cache never crosses threads - and resolution
itself can succeed on one thread and fail on another.

Observed 2026-10-08, same construction, two seconds apart:

```
14:28:11  Main Thread      [multi-layer] seeded 8 rail modules
14:28:13  ConstructionBuil [multi-layer] could not resolve
                           ::/stations/rail/.../modular_station.script@createTemplateFn
14:28:13  ConstructionBuil [multi-layer] built: rail level lifted to +12 ...
```

Note the last line: `@updateFn` **from the same file** resolved on the
ConstructionBuilder thread moments after `@createTemplateFn` failed there. So
it is not that the thread cannot resolve - it looks like the file was not loaded
into that state yet when the earlier call was made, and resolving any function
from it gets it loaded.

Two rules follow:

- **Never cache a failure.** Caching `false` turns a transient miss into a
  permanent one; here it meant every subsequent placement produced an empty
  station.
- **On a miss, resolve a sibling function from the same script and retry.**
  Cheap, and it covers the not-loaded-yet case.

```lua
local function resolveFn(ref, sibling)
    if resolved[ref] then return resolved[ref] end
    local fn = tryResolve(ref)
    if fn then return fn end
    if sibling then tryResolve(sibling); return tryResolve(ref) end
end
```

Worth keeping a fallback anyway - caching the last successful result of an
expensive delegated call, for instance - because a resource script has no way to
force a load.


## The stock hook shares model tables between `result` and the subconstruction

`modular_station.script.lua`'s hook assembles its subconstruction by copying
**references**, not values:

```lua
local mainSubconstruction = result.cargoStation
result.subconstructions = { }
for k, v in pairs(result.models) do
    table.insert(mainSubconstruction.models, v)
end
for k, v in pairs(result.colliders) do ... end
for k, v in pairs(result.terrainAlignmentLists) do ... end
```

So after the hook a single model table is reachable from both `result.models`
and `result.subconstructions[n].models`. Anything that walks both lists and
mutates what it finds will hit each shared entry **twice**.

Confirmed 2026-10-08 the visible way: a mod lifting a delegated station by 12 m
walked the subconstructions and then the result, and the doubly-lifted geometry
appeared floating at +24 - one pitch above where it belonged.

Track identity rather than trying to reason about which list to visit:

```lua
local seen = {}
...
if not seen[m] then seen[m] = true; m.transf = lift(m.transf, dz) end
```

The same sharing applies to colliders, lane lists and terrain alignment entries.
Clearing a list by assigning `{}` is safe - the other list keeps its own
reference - but *mutating entries* is not.


## A PERSON lane must never share a node with a vehicle lane

Lanes in a construction connect where their **nodes coincide** - same position,
not merely crossing. Join a `PERSON` lane to a `BUS` lane that way and the game
dies:

```
Assertion Failure: Assertion `person0 == person1' failed.
In file: train_fever/src/Game/ecs/TransportNetworkSystem.cpp:116
In function: `anonymous-namespace'::IsValidTransition
```

Confirmed 2026-10-08: a pedestrian lane routed across a bus lane had an
intermediate node at exactly the bus lane's stop node, and placing the
construction crashed on the simulation thread.

Two practical consequences:

- **Route pedestrian lanes so they never place a node on a vehicle lane.**
  Crossing a vehicle lane mid-segment, with no node there, is fine; it is the
  shared node that is fatal.
- **Conversely, a shared node is exactly how you *do* connect two PERSON
  lanes.** A lane that merely touches another without a coincident node is not
  connected to it, so a platform lane needs explicit nodes where its access
  lanes attach - split the platform lane into extra curves to create them,
  since `laneutil.createLane` makes two nodes per curve.


## Do not let a delegated call decide what the player sees

Corollary of the per-thread `util.useFn` finding above, and worth stating on its
own because the symptom is so misleading.

A mod delegated the stock seeding function and fell back to its own seeding when
resolution failed. Resolution succeeded on some threads and not others, so two
stations placed a minute apart came out **visibly different** - one with eight
modules, one with two - and the difference tracked nothing the player had
changed. It was mistaken for a bug in an unrelated feature that happened to be
under test at the time.

So: a delegated stock call is fine for *geometry*, where a failure degrades to
"nothing drawn" and is obvious. It is a bad idea for anything that decides the
**shape of the result**, like the initial module map, where a failure degrades
to "a different thing, silently". Seed from your own code and keep the
delegation for the parts where failure is loud.


## A modular station carries passengers only if the right *modules* are present

Catchment and capacity are not properties of a station or of its platforms.
They are summed from the **metadata of the placed modules**, and only some
modules have them:

| property | read from | declared by |
| --- | --- | --- |
| catchment | `module.metadata.catchmentPassenger.radius`, via `constructionutil.addCatchmentCircles` | rail: `main_building_*`, `side_building_*`, `stairs`. street: `entrance`, `entrance_exit`, `exit` |
| pool capacity | `module.metadata.moreCapacity.passenger`, via `modulesutil.getStationPoolCapacities` | building modules only |

**Platform modules provide neither.** A rail platform declares
`capacityPassenger = { 0, 68 }` in its *description attributes*, which is
display text and nothing else.

So a hand-seeded modular station consisting of a platform and a track is fully
placeable, fully routable, vehicles will run lines to it - and it will load and
unload **zero passengers**, for either of two independent reasons. Confirmed
in-game 2026-10-08 after chasing it through three different line
configurations.

The only clue is a warning that is easy to read past:

```
WARNING - no catchment areas generated for station
```

from `addCatchmentCircles` (`constructionutil.lua:531-546`), which fires when
the module sweep found nothing. It had been sitting in the log for several
rounds before anyone connected it to "no passengers". **A station with no
catchment is indistinguishable from a station the game has decided to ignore.**

Two ways to fix it, and the choice is a design decision:

- **Seed a station building module**, which is what the stock seeding does, and
  get the game's own radii and capacities.
- **Set `catchmentAreas` and `pool.capacity` directly** after delegating. Quick
  and unblocking, and it does not depend on a module the player might delete.
  Stock radii for reference: 150 m for a rail station building, 175 m for a
  street entrance.

`multi-layer-stations` does the second as a stopgap and intends the first:
catchment driven by the buildings the player places is what a player expects,
and a station whose reach ignores what is built on it reads as arbitrary. See
that mod's `PLAN.md`, "Phase 6".


## Hosting two stock families in one construction

The pattern behind `multi-layer-stations`: delegate **two** stock modular
stations from one `.con`, so both levels are editable with the game's own
modules instead of re-authoring them. It works, and it is reusable - but the
argument that got it started, "their module APIs use disjoint field names so one
merged result can serve both", is true and covers maybe a fifth of what has to
line up. The rest is below, learned over four separate in-game failures, none of
which produced an error message.

### The shape of the problem: three parties, not two

```
updateFn   -> familyA = aFn(...)      familyB = bFn(...)
              merged  = merge(familyA, familyB)        <- returned to the engine
module pass -> the engine hands **merged** to every module, of either family
hooks       -> aHook() writes into familyA; bHook() writes into familyB
```

Each family's hook is a closure over **its own** result table, while the modules
mutate the **merged** one. So for every field written in both places you have to
decide which wins, and **the answer is not uniform**. That is the whole pattern;
everything else follows from it.

### The decision table

For `multi-layer-stations`, with street at grade and rail elevated:

| field | treatment | why |
| --- | --- | --- |
| `edgeLists` | shared, **A's own table**, A's entries first | track modules call `pairs(result.edgeLists)` *during the module pass*, so it must exist by then; and rail indexes it positionally |
| `slots`, `slotConfig` | union, on the merged result only | the engine reads them to drive the module pass; each hook iterates its own |
| `models`, `colliders`, `laneLists`, `terrainAlignmentLists`, `groundFaces`, `labelText`, `poolConfig` | **the grade family's tables** | its hook wraps these into a subconstruction of its own and then builds lanes from them |
| `subconstructions` | nobody shares; re-read both **after** the hooks | both hooks *reassign* this field |
| `snapPoint` | the **module's**, i.e. whatever is on the merged table | the family's hook writes a worse default to its own table |
| private fields (`cargoStation`, `GetCoord`, `passengerStation`, `DemangleId`, `erastr`, ...) | copied across; grade family wins a name clash | this is the disjoint-names part, and it is the easy bit |

### The five traps, with their symptoms

Each of these presented as behaviour, never as an error.

**Hooks reassign, they do not append.** `result.subconstructions = {}`
(`modular_station.script.lua:1338`, `modular_terminal.script.lua:3204`). Any
sharing of such a field is abandoned the moment a hook runs.
*Symptom:* `0 subconstructions, 0 stations` and almost nothing drawn.
*Silver lining:* because they reassign, each family hands its subconstructions
back cleanly separated, so no discriminator is needed afterwards.

**A hook may absorb a construction-level list wholesale.** Rail does
`for k, v in pairs(result.models) do table.insert(mainSubconstruction.models, v)`.
Share `models` between families and whichever hook runs second swallows the
other's geometry - after the first already took it.

**A hook may wrap the construction level into a subconstruction and then build
from it.** Street does exactly that and *then* calls `addLaneLists`
(`modular_terminal.script.lua:3214-3226`), while its entrance module adds a model
through a two-argument `addModel` that lands at construction level. Give the
merged result a private `models` and that model goes where street never looks.
*Symptom:* **a bus can enter the station but has no path out** - the entrance
crossing's lanes were never built.

**Positional indices.** Rail's `edgeListHasCatenary` is
`{false, true, false, true}` for its four track lists (`:476`, read at `:995`).
Put anything ahead of those in a shared `edgeLists` and the catenary lookup is
silently mis-keyed.

**Module writes versus hook writes, for the same field.** The entrance module
writes a good `snapPoint` offset along the entrance road to the merged table; the
street hook then writes its own with **no `transf`** to its own table
(`:3295`), which means the construction origin.
*Symptom:* the station snapped by its centre rather than by the end of its bus
entrance. The stock station is unaffected because both writes land in one table,
the hook's wins, and its origin *is* its entrance.

And one that is not about merging at all but bites here: **resource names have to
be absolutised for both families**, not just the one being transformed. Doing it
inside the elevation pass left the other family with unresolvable model ids and
ground textures - a silent placeholder and a silent sand texture.

### How to find these without a failure each

Do not discover them one bug at a time, which is what happened here. For each
family, list every `result.<field>` its **modules write** and every one its
**hook reads**, and reconcile the two sets in one pass:

```sh
grep -o "result\.[a-zA-Z_]*" modules.script.lua | sort -u
awk 'NR>=<hook start line>' family.script.lua | grep -o "result\.[a-zA-Z_]*" | sort -u
```

Anything in both lists is a decision you have to make deliberately. That sweep
found `poolConfig` in one go after three fields had each cost a test round.

### Delegating a family means delegating its whole script surface

`updateFn` and `createTemplateFn` are the two obvious ones and they are not the
whole job. A `.con.lua` declares up to five script refs, and a construction that
hosts a stock family has to answer for every one the family answers for -
otherwise the parts of the station those scripts own quietly stop working, with
nothing in the log.

| script | rail | street | what stops working without it |
| --- | --- | --- | --- |
| `createTemplateScript` | yes | yes | the initial module map |
| `updateScript` | yes | yes | everything |
| `preProcessScript` | **no** | **yes** | module add/remove bookkeeping |
| `upgradeScript` | **yes** | yes | the upgrade tools |
| `isAffectedByToolScript` | **yes** | yes | which tools target the construction |

The two that bite:

- **`preProcessFn` is where a family's "one click, several slots" rules live.**
  A street passenger platform is *two* slots: street's `preProcessFn`
  (`modular_terminal.script.lua:1219-1269`) writes `coordJ = 1` when the player
  adds at `coordJ = 0`, and removes both when either goes. With no
  `preProcessScript` the engine does the plain thing - set or clear the one slot
  that was clicked - so seeding looks right and only *editing* is broken, which
  is a bad failure to find late. Rail declares none and instead uses
  `result.dependentSlots`, which the engine honours by itself.
- **`upgradeFn` is the only post-placement route to track type and catenary.**
  The modular rail station has no construction param for either; both are chosen
  by dragging the upgrade tool over the built station, and
  `modular_station.script.lua:351-427` is what turns that into module-name
  rewrites along the track row. A delegating construction without an
  `upgradeScript` is therefore stuck with whatever its seeding chose - in
  particular it can never be electrified.

Both have to be **routed, not forwarded**, for the same reason the module map is
split: street's `preProcessFn` calls its own `DemangleId` on `change.slotId`, and
rail's `SwapModule` assigns `.name` to whatever it finds at the id it is given
without checking what it is. Hand either one the other family's slot id and it
does something confident and wrong.

### Top-level `desc.params` are not inert on a template-based construction

Worth stating because the opposite is easy to infer from the
`postConstructionModifiable` finding below. There are **two different param
readers**:

- the **placement toolbar** concatenates `desc.params` with
  `template.data.params` (`gui/construction/construction_react_util.tl:1057-1067`)
  and shows the lot;
- the **post-construction panel** looks only at `desc.params`
  (`entity_window_util.tl:1893`), which is why no stock station can be edited
  after building.

So a top-level param on a construction that also has `constructionTemplates`
*does* appear at placement time. A declared-but-unread param is a control the
player can move to no effect.

### What is genuinely reusable

- The three-party model and the decision table above.
- Delegating the family's whole script surface, not just `updateFn`.
- One family at grade, untransformed, owning the construction level. Giving the
  *transformed* family the construction level would mean transforming terrain
  alignment faces and ground textures too.
- Splitting the module map by **module name** rather than slot-id range: the
  families' id spaces overlap in principle even where they do not in practice.
- Renumbering subconstruction `tag`s across both families at the end, since a
  duplicate crashes the game outright.
- Deciding per field, and writing down why - the table above is the deliverable,
  not the code.


## Two subconstructions must not share a `tag`

A duplicate `tag` across a construction's subconstructions **crashes the game**,
not gracefully:

```
Assertion Failure: Assertion `it2.second' failed.
In file: train_fever/src/Game/construction/create_proposal_data.cpp:365
In function: construction_builder_util::...::PopulateOld2NewSubconstructions
```

`it2.second` is the success flag of a map insert, so the map is keyed by tag and
the second insert of the same key fails the assertion. Confirmed 2026-10-08 by
adding a subconstruction with `tag = 1` to the modular rail station, which
already uses `tag = 1` for its own station subconstruction
(`modular_station.script.lua:646`).

It surfaces when the **module builder** runs over the construction - clicking
the station to configure it - not at placement, so a construction can look fine
and then take the game down on the first edit. Known tags in shipped content:
rail station station `1`, underground station `1`, harbor's extra geometry
subconstruction `2`. Pick something clear of those.


## Construction parameters are keyed by name

`createTemplateFn` reads `params.platforms`; `checkEnabledFn` takes
`{string : number}`. Parameters are a name-keyed dict, not an ordered list.

- **Adding** a parameter key is savegame-safe. Stations built earlier simply
  have no value for it, so treat `nil` as the stock default.
- **Inserting a value into an existing param's `values` list is not.** Values
  come back as 1-based indices, so an insert silently changes the meaning of
  every already-built instance's stored value.
- `checkEnabledScript` (`base/tealdef/gui/construction/construction_menu.d.tl:69`,
  wired at `gui/construction/construction_react_util.tl:801`) returns
  `Enabled` / `Hidden` / `Disabled` / `InputActionOnly`, and works for
  mod-added construction params. A `Hidden` param keeps its stored value.
- Changing a construction param during placement **does** re-run
  `createTemplateFn`, which is what makes a mod-added param take effect live.


## `util.useFn` works from a resource script

`ug_require "::/scripts/util.tl"` then `util.useFn("path@fn")` resolves a
`ScriptRef` to a callable (`scripts/util.tl:5`, via the `game` table's
`__index`). Confirmed working from a `.script.lua` loaded as a construction
resource, so a mod can **wrap** a stock script function instead of forking it:
point the construction's script ref at your own function, resolve the original,
call it, post-process the result.

`scripts/util.tl` only pulls in `scripts/mathutil.lua` - no GUI dependencies, so
it is safe from a resource script. (Unrelated but adjacent: `.gs.lua` game
scripts must never `require` anything under `::/gui/...`.)

Watch out for relative script refs. The stock street station declares
`createTemplateScript` as `"modular_terminal.script@createTemplateFn"`, which
resolves against *your* folder once you are the caller. Make it absolute by
joining it to the directory of the `fileName` the modifier was handed.


## The mod.io id lives in `_metadata/mod.io_fileid.txt`

Publishing from the in-game Mod Manager writes the mod.io numeric id into
`<mod>/_metadata/mod.io_fileid.txt` in the **deployed** folder - a 9-byte file
like `6435170\r\n`. The literal path `_metadata/mod.io_fileid.txt` is in the
exe, inside `LocalModHubBackend`, so that file is how the game decides a local
folder *is* mod.io mod N. With it, the next publish **updates** that mod;
without it, the next publish **creates a second one**.

**A deploy script that wipes and recopies the target will delete it**, which is
the whole trap: nothing errors, and the next publish quietly forks the mod into
a duplicate listing. So:

- Commit the file to the repo, in the mod's source tree, so every deploy
  carries it.
- Pin it in `.gitattributes` as `**/_metadata/mod.io_fileid.txt -text`. It is
  written with CRLF, and the repo-wide `eol=lf` rule would otherwise rewrite
  the bytes the game reads back.
- Have the deploy script rescue it: if the target has the id and the source
  does not, copy it back after the recopy and say so loudly.
  `pick-single-platform-side/deploy.ps1` does this, and prints the id on every
  deploy so a broken link is visible immediately.

**Nobody else can take over a mod with its id.** The id is a resource
identifier, not a credential. Uploads go through mod.io's authenticated API -
the exe carries `AuthenticateUserEmail` / `AuthenticateUserExternal` and
`UploadModAsync`, and `ModPublishHelper::StartUpload(ModId, PublishSettings,
CookResult)` - and mod.io authorises writes per account, to the mod's owner and
team. Someone putting your id in their own `mod.io_fileid.txt` gets a
permission error, not your listing. (Reasoned from the platform model and the
auth plumbing in the binary; not tested, for obvious reasons.)

Known ids, for reference and because losing one is annoying:

| mod | mod.io id |
| --- | --- |
| `pick_single_platform_side_1` | 6435170 |
| `mapzilla_1` | 6423494 |
| `town_clustering_1` | 6418126 |


## Validating a mod from the command line

The usage strings inside `TransportFever3.exe` give the real syntax:

```
--validate <source>,<modid> [report.json] [--and-cook <cook-output-path>]
```

Both trailing parts are optional and **both take an argument**. Other flags in
the binary: `--validate-all`, `--validate-client`, `--exec`, `--script`,
`--settings`.

Three things that cost a run each to work out:

- `--and-cook` with no path logs `--and-cook argument provided without cook
  output path, ignoring` and silently skips cooking - the console-asset half of
  the check. Give it a path. The path must not already exist: `Cook output
  folder already exists, please remove manually`.
- **The exit code is not a verdict.** The process that gets started hands off to
  a second one and returns before the work is finished - exit `53` on a run
  that passed cleanly, with the report file appearing afterwards. Wait for no
  `TransportFever3` process to remain *and* the report to exist, then judge by
  the report.
- The exe is a GUI subsystem binary, so calling it with `&` from PowerShell
  detaches it and never sets `$LASTEXITCODE`. Use `Start-Process -Wait
  -PassThru`.

The report is small and machine-readable:

```json
{
    "cookedConsolePath": "...", "cookedPcPath": null,
    "criticalConsole": false,   "criticalPc": false,
    "levelConsole": "Info",     "levelPc": "Info",
    "messages": null,
    "modId": { "name": "pick_single_platform_side_1" }
}
```

PC and console are graded separately. `messages: null` and `level*: "Info"` is a
clean pass; the log says `Validation Passed without issues.` alongside it.
`cookedPcPath` came back `null` for a script-only mod while the console path
was populated, so a null there is not by itself a failure.

**`critical` is not the verdict - `level` is.** Confirmed 2026-10-08: a Lua
parse failure that stopped the mod loading entirely came back as

```json
{ "levelPc": "Error", "criticalPc": false, "messages": [ ... ] }
```

so a script that branches on `critical*` alone prints "Validation passed"
directly underneath the error that broke the mod. Grade on
`levelPc`/`levelConsole`, which read `Info` on a clean pass. Both deploy scripts
were fixed to do that.

`messages` entries are objects, not strings - `{ consoleOnly, context, file,
level, message }` - so interpolating one in PowerShell renders
`@{consoleOnly=False; context=...}` and buries the text. Print the fields.

The in-game Mod Manager runs the same validator from the staging area entry and
reports per file, which is the fallback when the CLI says nothing useful.

**The CLI validator is flaky.** Seen 2026-10-08: after several successful runs
it began exiting 53 with **no report and no new `stdout.txt` session at all**,
for an unchanged mod that had passed an hour earlier, with and without
`--and-cook`. Steam was running and there was 260 GB free. So when the report
does not appear, suspect the harness before the mod - re-validate a known-good
mod as a control before believing the mod is at fault.


## Syntax-checking Lua without launching the game

`tools/luacheck.py` compiles each `.lua` with a real Lua front end via `lupa`
(`python -m pip install lupa`):

```
python tools/luacheck.py multi-layer-stations/probe/mod pick-single-platform-side/mod
```

It catches the entire class of error that otherwise appears in-game as "my
constructions are missing from the menu", costs no process launch, and works
while the game is running - which the real validator does not. It only checks
that a file *parses*: it knows nothing about the game's globals or resource
names, so it is a syntax gate, not a substitute for `deploy.ps1 -Validate`.

The `lupa` wheel builds against Lua 5.5 while the game is on 5.4, which has not
mattered for anything written so far.

It also does a second, non-syntax pass: **calls to names that are never defined
as a local in the file.** A Lua chunk compiles happily with a call to a nil
global and only fails at runtime, inside the game, as "attempt to call a nil
value" - which is exactly what an editing slip produces when it deletes a
`local function` and leaves its callers behind. That happened here - twice, from careless
index-based string slicing in an editing script - and the compile pass reported
the gutted file clean both times.

The second time the casualties were two *constants* rather than functions, which
is worse: `local DECK` disappeared, `{ id = DECK }` still compiled, and the game
threw `Required key not found: key='id'` on **every** `updateFn` call. Seventy-four
exceptions during a single hover, which the player experienced as the game
locking up rather than as an error. So the check covers both shapes:

- calls to a name that is not a local in the file;
- SCREAMING_CASE names *read as values* that are not a local - a nil constant
  travels silently into a table and fails somewhere else entirely.

Both were verified by deleting a real definition and confirming the warning
fires. A lowercase bare name is deliberately not checked, since it has too many
legitimate reasons to be a global.

**And the editing lesson, which is the actual root cause:** do not restructure a
file with `s.index(...)` slices. One pattern matched further than intended and
took nine definitions with it; the next took two constants. Use targeted
replacements of text that is unique, or rewrite the file wholesale.

**Do not hand-roll a regex "block balance" checker as a substitute.** One was
tried and reported a confident `UNCLOSED function at line 172` in a file that
compiles cleanly - its string-literal regex was spanning newlines and losing 25
of them, which threw off both the depth count and the line numbers. A wrong
answer delivered confidently is worse than no checker.


## The `.d.tl` files are incomplete - trust the shipped content

`api/tealdef/api/type.d.tl`'s `ConstructionDesc` does not declare
`createTemplateScript`, `preProcessScript`, `upgradeScript` or `namePrefix`,
though the stock `.con.lua` sets all of them. Likewise `constructionTemplates`
is marked `[DEPRECATED] Use metaconstructions instead`, yet **no shipped content
uses metaconstructions at all** - there is no `metacon.lua` anywhere in
`base/content`. The deprecated path is the live one.

When the Teal definitions and the shipped `.con.lua` / `.script.lua` disagree,
the shipped content wins. See `external-connections/NOTES.md` for a table of
further cases that each cost a restart.


## A deployed mod still has to be activated per savegame

Obvious in hindsight, and still worth the line because it costs a confusing
restart. `deploy.ps1` puts a mod in the staging area and the game picks it up at
startup - the log says `new ModHubMod was installed and will be added to
filesystem <modId>` - but that only makes it **available**. Mods are
per-savegame, so until it is enabled in the save's mod settings, or a new game
is started with it ticked, none of its content exists in that game.

The check is the `Active mods:` block in `stdout.txt`. If the mod is not listed
there, nothing it adds will appear in the build menu, and the absence of any of
its log lines is the confirmation. `autoActivate` in `mod.json` is the flag that
would change this; every mod here has it `false`.


## Paths and deployment

- Install: `C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3`
- User folder: `C:\Program Files (x86)\Steam\userdata\<id>\3493540\local`,
  holding `mods\`, `staging_area\`, `save\` and `crash_dump\stdout.txt`.
- `stdout.txt` is **overwritten each session**, so copy it before relaunching if
  a run needs keeping.
- **Deploy to `staging_area\` only.** The staging area is a full install source,
  not just an upload staging post: the precedence when a `modId` appears more
  than once is Staging Area, then the manual `mods\` folder, then subscribed
  mods. So a mod in staging is playable *and* publishable, and publishing
  (`Modhub.ModPublishHelper`) only ever reads from there.

  Deploying to both is the trap: the log fills with `Multiple (2) mods with
  same id found <id>, the one from .../staging_area/... has been selected`, and
  the staging copy silently wins. Redeploy only the `mods\` copy and the game
  keeps running the stale staging one, with nothing but a warning to say so.
  `pick-single-platform-side/deploy.ps1` is the current template: staging by
  default, a `-Mods` escape hatch, and a warning if a second copy is left
  behind.
- Mods are read at startup. Restart the game after every deploy.
- Translations: `strings.json` at the mod root,
  `{"<lang>": {"<msgid>": "<text>"}}`. The log confirms it loaded:
  `Loaded translation string for .../strings.json with 10 languages`. The
  English catalog (`base/strings/en/LC_MESSAGES/base.mo`) contains only
  ID-style keys, so a plain-English `_("...")` msgid falls through to its own
  literal; the translated catalogs do hold the plain-English msgids, so reusing
  a string the base game already has gets every language for free.


## Terrain alignment is opt-in, per face

There is no terrain *check* to disable. A construction gets levelled ground only
because it asked for it, one face at a time, in `result.terrainAlignmentLists`.
`scripts/construction/constructionutil.lua:241-321` is the whole mechanism:

```lua
result.terrainAlignmentLists[#... + 1] = {
    type = type,            -- "EQUAL" | "LESS" | "GREATER"
    triangles = triangles,  -- or faces = { ... }
    optional = optional,
    slopeLow = slopeLow, slopeHigh = slopeHigh,
}
```

`constructionutil.addModelsAndGroups` fills it from the `generatedData` table it
is handed:

| source key | emitted as |
| --- | --- |
| `meshes.equal` | `EQUAL`, `optional = false` |
| `meshes.less` / `meshes.greater` | `LESS` / `GREATER`, `optional = true` |
| `meshes.equal_optional` etc. | same type, `optional = true` |
| `curves["<prefix>equal_faces|<lo>|<hi>"]` | `EQUAL` with `slopeLow`/`slopeHigh` |
| `curves["<prefix>equal_faces_optional|<lo>|<hi>"]` | same, `optional = true` |

`modulesutil.addGroundFaces` is a *different* thing and does not touch terrain -
it only emits `groundFaces`, i.e. the ground texture decal.

**`faces`, `optional`, `slopeLow` and `slopeHigh` are all absent from the
`TerrainAlignment` record** at `api/tealdef/api/type.d.tl:2424`, which only
declares `triangles`, `weights`, `type` and `bbox`. Another case for the "trust
the shipped content" rule below.

The practical consequence: a construction that emits no alignment entry for a
piece of geometry leaves the terrain alone there. The stock underground station
is the proof - its only alignment is `meshes["equal"]` at z = 0 under the
surface head, and nothing at all for the platform level at z = -18
(`stations/street.zip`, `street/underground_station/underground_station.script.lua`).
Conversely the modular rail station flattens its whole footprint because it asks
for `{ type = "EQUAL" }` on every tile - `modular_station.script.lua:952` for
the platform-end connectors, `modules.script.lua:203, 343, 518, 580` for the
platform and track modules themselves.

For programmatic builds there is also `Proposal.Context.checkTerrainAlignment`
(`type.d.tl:2475`), but it is a proposal-context flag, not a construction one.


### An **empty** `terrainAlignmentLists` is not "leave the terrain alone"

It is the opposite. **Confirmed in-game 2026-10-08**, after a long hunt.

Clearing a construction's `terrainAlignmentLists` to `{}` made the engine raise
the ground to meet the construction's geometry - for a station lifted to +12 m,
a 12 m mound the width of the station. Replacing the empty list with a **single
tiny `LESS` face at z = 0** fixed it completely: geometry stays at +12, terrain
stays flat, and it holds as modules are added.

```lua
--- "Terrain no higher than this", over a 20 cm square at the origin: as close
--- to a no-op as the shape allows, but *not nothing*.
local function gradeAnchor()
    return {
        type = "LESS",
        faces = { {
            {  0.1, -0.1, 0.0, 1.0 }, {  0.1, 0.1, 0.0, 1.0 },
            { -0.1,  0.1, 0.0, 1.0 }, { -0.1, -0.1, 0.0, 1.0 },
        } },
    }
end
```

**The stock content says the same thing, if you read it the right way round.**
The modular rail station ends its hook with:

```lua
if #result.terrainAlignmentLists + #result.cargoStation.terrainAlignmentLists == 0 then
    result.terrainAlignmentLists = {
        { type = "LESS", faces = { { {10.1,-0.1,0,1},{10.1,0.1,0,1},{9.9,0.1,0,1},{9.9,-0.1,0,1} } } }
    }
end
```

(`modular_station.script.lua:1323-1335`.) Urban Games substitute a minimal
anchor **exactly when the lists would come out empty**. Nobody writes that
fallback unless empty misbehaves, so treat it as the documented workaround for
this, not as housekeeping.

So the rule for any construction that should not disturb the terrain:
**emit one no-op alignment entry, never an empty list.** Likewise when
post-processing a stock construction - stripping its alignment is not enough,
the stripped list has to be replaced by an anchor.

How much this cost, as a warning about method: the cause was found only by
cutting the construction down one component at a time, after several rounds of
theorising. Each of `EdgeList.alignTerrain`, bridge abutments,
`Slot.alignToTerrain` and `TransformedModel.thin` looked like the answer and was
not - and `Slot.alignToTerrain` had even been guessed, in writing, to be
"made for off-grade slots" before being tested and cleared. The bisect that
worked kept exactly one variable per build; the earlier one that changed two at
once produced a confident wrong conclusion. **Bisect one variable at a time, and
distrust any mechanism that has not been tested against a build that could
falsify it.**


## Constructions have a native height offset

Every construction gets a `height` slider on the build toolbar unless its desc
opts out. `gui/construction/construction_react_util.tl:857`:

```lua
if (not definition or definition.heightAdjustable) then
    params[#params + 1] = { key = "height", name = _("Height"), ... }
```

and it is handed straight to the engine builder -
`constructionBuilder.height = actionParams["height"] or 0.0` (same file, :3172).
The value range comes from `makeSliderParamsHeight` (:237) -> `makeSliderParams(
name, -5000, 5000)`, a cubic ramp whose useful span is +-50 m.

The gate is `ConstructionDesc.heightAdjustable` (`type.d.tl:1713`). No shipped
construction sets it `true`; the only mentions set it `false` (water stations
and depots, offshore industries, waterside landmarks), so the engine default is
evidently on. `MetaConstructionDesc` carries the same field plus `heightModView`
(`type.d.tl:1829-1833`); the airports set `heightModView = false`.

`undergroundView` (`type.d.tl:1712`) is the sibling flag, set by the underground
station, and pairs with the `undergroundMode` toolbar toggle
(`construction_react_util.tl:660`, input action `IA_UNDERGOUND_MODE_TOGGLE`).

**The slider works, but it takes the terrain with it.** Confirmed 2026-10-08:
raising a stock station raises the ground under it into a plateau, and a second
station placed underneath then collides. That is the expected consequence of the
section above - the station's `EQUAL` alignment faces are in construction space,
so they travel with the height offset. The height offset is therefore usable for
*geometry* but is not by itself a route to a multi-level station. See
`multi-layer-stations/NOTES.md`.


## Construction edges can be bridges or tunnels

`constructionutil.addEdges` passes two fields through to the engine untouched
(`constructionutil.lua:68-71`):

```lua
local res = {
    edgeType = params.edgeType,          -- BaseEdgeType: NORMAL | BRIDGE | TUNNEL
    edgeTypeName = params.edgeTypeName,  -- e.g. "::/infrastructure/tunnel/tunnel_b_car.tunnel"
    ...
```

`BaseEdgeType` is `NORMAL | BRIDGE | TUNNEL` (`type.d.tl:457`). The underground
station is the **only** shipped construction that uses either, and it only ever
uses `TUNNEL`:

```lua
constructionutil.addEdges(transform(edge1, platformTransform), result, "STREET", {
    type = "::/infrastructure/street/tram/tram_new.street_template",
    tramTrackType = ..., edgeType = "TUNNEL",
    edgeTypeName = "::/infrastructure/tunnel/tunnel_b_car.tunnel" },
    false, snapNodes, freeNodesList)
```

**`edgeType = "BRIDGE"` works, and it works properly.** Confirmed in-game
2026-10-08 with `multi-layer-stations/probe`: a construction emitting a single
track edge at z = +12 with `edgeType = "BRIDGE"` and
`edgeTypeName = "::/infrastructure/bridge/concrete.bridge"` renders as a
viaduct, leaves the terrain beneath it alone, and **a player-drawn track
connects to its free nodes at height and fully works.** No shipped content does
this, so it was the main open risk for building above grade; it is closed.

`TUNNEL` at z = -12 on `::/infrastructure/tunnel/tunnel_b.tunnel` (the `RAIL`
carrier) also renders and accepts a connection. The caveat there is about the
*player's* edge, not the construction's: on flat ground a track descending from
the surface to a node at -12 is built as a trench, not a tunnel, which is
ordinary game behaviour - a tunnel needs cover above it. The stock underground
station sidesteps this by owning the whole descent itself and only exposing
nodes that are already at depth.

Node indices in `snapNodes` / `freeNodes` are **0-based**:
`street_util_serialized.freeAllNodes` returns `freeNodes[i] = i - 1`
(`street_util_serialized.tl:70-76`), and `trainstationutil.lua:73` uses
`nedges + 0` for its first node. A 2-point curve yields nodes `0` and `1`;
listing both in `freeNodes` makes both ends connectable - confirmed.

### A station's `snapNodes` are load-bearing - do not convert them to `freeNodes`

**Confirmed 2026-10-09**, and it cost a debugging round. A mod lifting the
modular rail station turned its track edges' `snapNodes` into `freeNodes`,
reasoning that a snap node is where the engine brings the ground up to meet the
edge. The consequence had nothing to do with terrain:

> Place the station - modules delete fine. Connect **a single piece of track**.
> Now only the module at the connection can be deleted; every other module
> gives "construction not possible" on hover.

Verified against a stock modular rail station, which allows the deletion, so
this was the mod's doing and not engine behaviour.

The mechanism is in `trainstationutil.lua`. A track module contributes 12 edges,
and the util marks an end node **only where there is no adjacent track module**
(`:80-87`) while separately recording all twelve of that module's node indices
in `edgeLists[n].tag2nodes[tag]` (`:277-291`). `tag2nodes` is tag-keyed, so it
is how a rebuild re-identifies nodes and carries an external connection across
it. Emptying `snapNodes` discards the engine's own record of "this is where I
join the world" while leaving `tag2nodes` asserting otherwise, and the engine
then refuses any rebuild that would have to re-stitch the connection.

Reverting the conversion fixed it **and left the terrain alone**, so the
conversion bought nothing in the first place.

Two lessons, the second more useful than the first:

- **`snapNodes` is not a terrain control.** The terrain controls are
  `terrainAlignmentLists` (which must be a grade anchor, never empty),
  `groundFaces` and `EdgeList.alignTerrain`. Reaching for anything else to fix
  terrain means guessing.
- **A fix adopted on an untested theory outlives the theory.** This conversion
  was added while hunting the terrain bug, kept when the real cause turned out
  to be the empty `terrainAlignmentLists`, and only showed its own bill months
  later in a completely unrelated feature. When a bisect finds the real cause,
  go back and revert the things that were tried and left in.

**`EdgeList.alignTerrain` is the explicit "do not deform terrain" control**
(`construction_util_serialized.d.tl:153`). The airfield sets it `false` on its
runway and taxiway edge lists (`airfield.script.lua:344-352`,
`airport.script.lua:682-689`) and nothing else in the install uses it. Off-grade
edge lists should set it rather than relying on `BRIDGE`/`TUNNEL` implying it.


## A modular construction is built in three stages, and the hook is stage 3

`result.terminateConstructionHook` (`construction_util_serialized.d.tl:256`) is
not a tidy-up callback - for every stock modular station it is where most of the
work happens. The order is:

1. **`updateFn`** - emits `slots`, sets up the host's private state, installs
   `terminateConstructionHook`, returns.
2. **The engine runs each placed module's `updateScript`**, handing it the
   result table the host just returned.
3. **`terminateConstructionHook()`** - terrain alignment, connector geometry,
   terminals, lane lists, `subconstructions` assembly.

For the modular rail station, `updateFn` is lines 429-854 and **the hook is
855-1364** (`modular_station.script.lua`) - two thirds of the script. Every
other modular station does the same: street, harbor, airport, airfield,
heliport.

**Confirmed in-game 2026-10-08, the hard way.** A modifier that wrapped the
stock `updateFn` and tried to empty `result.terrainAlignmentLists` immediately
after it returned logged `stripped 0 terrain alignment entries` and changed
nothing on screen - because at that moment the lists are genuinely empty. The
station's own alignment arrives in stage 3 and the modules' in stage 2.

So for a mod that post-processes a stock construction:

- **anything the host emits in `updateFn`** - above all `slots` - can be
  adjusted right after calling it, and that works (confirmed: added slots show
  up and accept modules);
- **anything the host or its modules emit later** - `terrainAlignmentLists`,
  `models`, `colliders`, `edgeLists`, `station` records, `subconstructions` -
  must be post-processed by **wrapping the hook**: keep the stock
  `terminateConstructionHook`, install your own, call theirs first, then edit
  the result.

```lua
local stockHook = result.terminateConstructionHook
result.terminateConstructionHook = function(...)
    if stockHook ~= nil then stockHook(...) end
    -- now the result is fully populated; edit it here
end
```


## Reloading a savegame does not re-run `updateFn`

**Confirmed 2026-10-08.** After loading a save containing a placed modular
station, the log shows the `loadConstruction` modifier firing again (resources
are re-read at startup) but **no** `updateFn` output at all - no slot counts, no
module placements. The construction's geometry comes back from the savegame,
not from re-running the scripts.

This is the same fact that makes a seeding mod safe to remove, seen from the
other side: `updateFn` output is baked into the save.

The consequence for testing is sharp: **a save/reload that merely looks right
proves very little.** It shows the serialized geometry survived. To find out
whether the *script state* round-trips - whether a slot id scheme still lines up
with `params.modules` after a reload - you have to force a rebuild after
loading, by adding or removing a module on the station. Only then does
`updateFn` run against the restored param map.


## A construction is only selectable if it contains a station-like component

Clicking a placed construction opens nothing unless one of its subconstructions
carries a `WAREHOUSE`, `INDUSTRY`, `STATION` or `VEHICLE_DEPOT` component.
`getSubconstructionDescriptionAndSortKey`
(`gui/entity_window/make_entity_window.tl:46-101`) checks exactly those four and
`return nil, 0` otherwise, and the construction window's loop skips any
subconstruction whose description came back nil.

**Confirmed in-game 2026-10-08.** A probe construction made only of models,
colliders and terrain alignment could be placed and bulldozed but never
selected, so its slots were unreachable and its params invisible - even though
`isConstructionModifiable` (`entity_window_util.tl:1893-1912`) would happily
have said yes, since it only wants slots or a `postConstructionModifiable`
param. The pick is not the problem; there is simply no window to show.

Two consequences:

- A pure-geometry construction - a decorative asset, a probe, a viaduct with no
  station - is placeable but not clickable. Nothing to be done about it short of
  giving it a station, a depot, or an `entityWindowScript`
  (`make_entity_window.tl:328` short-circuits to that script before the
  subconstruction loop, so it bypasses the whole check).
- **To test slots or construction params, borrow a construction that is already
  a station** rather than growing one onto a test fixture. A
  `loadConstruction` modifier that adds slots to the stock modular rail station
  gets selection, a modules list and an entity window for free.


## A module is bound to its host construction's private API

A `.module.lua` is not portable between station families, and the slot `type`
string is the *lesser* of the two reasons.

The slot type is just a string match. Slots are emitted by the host's `updateFn`
with `{ id, transf, type, spacing, replaceable }`, and the module desc declares
a matching `type`. The two stock families share nothing:

| family | slot types |
| --- | --- |
| `modular_station` (rail) | `track`, `passenger_platform`, `passenger_platform_roof`, `cargo_platform_roof`, `passenger_platform_addon`, `rail_building_size4` |
| `modular_terminal` (street) | `street_terminal_passenger`, `street_terminal_cargo`, `street_terminal_entrance`, `street_terminal_exit`, `street_terminal_entrance_exit`, `street_terminal_small_buildings`, `street_terminal_large_buildings` |

The real coupling is the module `updateFn` signature
`(captureParams, result, transform, tag, slotId, addModel, constrParams)`, where
`result` is **the host's own half-built result table**, carrying closures and
fields the host invented. The rail modules reach for `result.cargoStation`,
`result.GetCoord(slotId)`, `result.GetModuleAt(i, j)`, `result.GetRoofAt(i, j)`,
`result.connector[...]`, `result.addPlatformCallback(...)`,
`result.trackCoord2models` (`stations/rail/modular_station/modules.script.lua`).
The street modules reach for `result.DemangleId(slotId)`,
`result.passengerStation.models`, `result.leftLen`, `result.rightLen`,
`result.needOuterLeft`, `result.needOuterRight`, `result.erastr`, `result.cat`,
`result.coord2terminalInfo[i][j]`
(`stations/street/modular_street_station/modules.script.lua:461`).

Neither set of names exists in the other host. Declaring a rail-typed slot
inside the street station would make the module *offerable* and then crash it on
the first field access. **To host another family's modules you have to reproduce
that family's result contract, not just its slot type.**
