# Notes

Read out of the install at
`C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3`, game build
40408. **Nothing here is confirmed in-game yet** - see `PLAN.md` for the probes
that would confirm it. The engine-general findings this builds on live in the
root [NOTES.md](../NOTES.md): terrain alignment is opt-in per face,
constructions have a native height offset, construction edges can be `BRIDGE` /
`TUNNEL`, and a module is bound to its host construction's private API.


## Scope

Not a free z-axis. Levels only, at a 12 m pitch.

**Level -1 is parked as of 2026-10-08.** Current scope is **level 0 and
level +1** - a station at grade with a second one above it, which is the
README's own example (elevated train station over a bus station). Level 0
behaves exactly as today. Level +1 is off-grade and must not disturb the
terrain. See "Parked: level -1" below for what was already learned about going
down, so it can be picked up without re-deriving it.


## The native height slider is not the answer

Every construction gets a `height` toolbar slider (root `NOTES.md`,
"Constructions have a native height offset"). **Confirmed 2026-10-08: it works,
but it pulls the terrain up with it.** The station rises, the ground under it
rises into a plateau, and a bus station placed underneath collides.

That is exactly what the next section predicts: the alignment faces are in
construction space, so a height offset moves them too. The slider is fine for
lifting geometry; it is not a route to a multi-level station on its own. Pitch
12 m is settled as the level spacing.


## Terrain: nothing to disable, just stop asking

A station flattens its footprint because it asks to. The modular rail station
emits `{ type = "EQUAL", faces = { faces } }` for every platform-end connector
tile (`modular_station.script.lua:952`) and every platform / track module
(`modules.script.lua:203, 343, 518, 580`).

The stock underground station is the control case: its only alignment entry is
`meshes["equal"]` at z = 0 under the surface head, and there is **none at all**
for the platform level at z = -18. It is otherwise a complete worked example of
an off-grade station - lanes, models, props, the `station` record and tram edges
all at depth, with pedestrian lane curves climbing from z = 0 to the platform.

### There are two terrain mechanisms, not one

Learned the hard way 2026-10-08. Emptying `terrainAlignmentLists` is only half
the job: **an edge list deforms the ground along its own edges** unless it sets
`alignTerrain = false` (`construction_util_serialized.d.tl:153`). The airfield
is the precedent - it sets the flag on its runway and taxiway so they do not cut
into the landscape (`airfield.script.lua:344-352`).

A station's *track* edges will therefore flatten the ground under them however
thoroughly its alignment lists have been cleared. The probe stripped 7 alignment
entries in the hook and the ground still conformed, which is what pointed at
this.

So the rule is two lines:

- **levels != 0 emit no `terrainAlignmentLists` entries**, and
- **their edge lists set `alignTerrain = false`.**

Level 0 keeps both unchanged, which is correct - a station at grade should
level its own footprint.

### For level +1 this may already be free

Worth not over-engineering: an elevated level's edges are `BRIDGE` edges, and
**the bridge probe left the terrain beneath it completely untouched** without
anyone setting `alignTerrain`. So a viaduct may not deform terrain in the first
place. The explicit flag is still the right thing to set - it costs one line and
removes the doubt - but the terrain problem for level +1 is likely already
solved by the edge type.

This also means the probe's strip-terrain test is aimed slightly off the real
question. It strips alignment from a station at **grade**, where the track edges
legitimately flatten the ground; the question that matters is whether a level at
+12 deforms anything, and the bridge probe already answered no.


## Vertical budget, measured

All z values relative to a level's reference plane, which is the rail base /
platform base of that level.

| element | z extent | source |
| --- | --- | --- |
| track bed | 0 .. 0.53 | `standard_catenary.street_template.lua:28` (`height`) |
| platform deck | 0 .. 1.12 | `stations/rail/era_a/perron_5.mdl` bbox |
| platform roof, era A | 1.10 .. 4.97 | `era_a/perron_5_roof.mdl` bbox |
| platform roof, era B | 1.09 .. 5.16 | `era_b/perron_5_roof.mdl` bbox |
| platform roof, era C | 1.10 .. **5.48** | `era_c/perron_5_roof.mdl` bbox |
| catenary pole, short | -1.14 .. **8.17** | `power_pole_2_standard.mdl` bbox |
| catenary pole, tall | -1.10 .. **10.60** | `power_pole_1_standard.mdl` bbox |
| viaduct structure below deck | **-2.40** | `concrete.bridge.lua`, `c_6_rep_*` bbox |
| platform / track module collider | **+-6.0** | `modules.script.lua:349, 524` |
| cargo platform collider | -2 .. +14 | `modules.script.lua:205-211` |
| connector tile collider | -1 .. +9 | `modular_station.script.lua:969` |
| rail tunnel envelope, a / c / b | 9.66 / 10.66 / **12.16** | `tunnel_a/c/b.tunnel.lua` (`height`) |
| road + tram tunnel envelope | 10.03 / 10.55 | `tunnel_b_car`, `tunnel_a_car` |

Bridge geometry also has `pillarLen = 4`, `abutmentLen = 4`,
`pillarMinDist = 60` / `pillarTargetDist = 72` / `pillarMaxDist = 84`
(`concrete.bridge.lua`), which matters once pillars have to miss whatever is at
level 0.


## How tall is a level? 12 m

Four independent numbers in the install converge on it:

- the platform / track module collider is exactly `+-6`, i.e. a 12 m envelope
- the worst-case rail tunnel envelope is 12.16 m (`tunnel_b`)
- the underground station's first drop, street to mezzanine, is exactly -12
- the road and tram tunnel envelopes are ~10 m, comfortably inside

**Pitch = 12 m.** A level L owns the band `L*12 - 2.4` (its viaduct structure)
to `L*12 + 9.6` (clear to the underside of the level above).

The one number that argued for 13 m instead was `tunnel_b`'s 12.16 m envelope,
which overruns 12 by 0.16 m - and that only matters for level -1, now parked. So
within the current scope of levels 0 and +1, **12 m is settled**, and the 13 m
question is deferred along with going underground.

What fits at level 0 with a deck at +12, whose underside is 9.6 m:

| at level 0 | top | verdict |
| --- | --- | --- |
| bare platform | 1.12 | fits, 8.5 m spare |
| roofed platform, era C | 5.48 | **fits**, 4.1 m spare |
| roofed platform + short catenary | 8.17 | **fits**, 1.4 m spare |
| roofed platform + tall catenary gantry | 10.60 | **overruns by 1.0 m** |

So the roof is affordable after all; the thing a covered level has to give up is
the tall `power_pole_1` catenary. That is a module-substitution problem, and the
stock station already does exactly this kind of swap -
`modular_station.script.lua:382-404`, `SwapModuleCatenaryAdd` /
`SwapModuleCatenaryRemove`, driven by `catenaryAdd` / `catenaryRemove` on the
module desc.

Two collider consequences of pitch 12:

- platform and track colliders (`+-6`) **abut exactly** between adjacent levels
  without overlapping, which is itself evidence 12 is the intended figure;
- the **cargo platform collider spans -2 .. +14**, so it pokes 2 m into the
  level above. A cargo platform cannot carry anything over it unless its
  collider is shrunk.


## Mixing modes: why a rail platform will not go in a bus station

Two barriers, and the slot type is the smaller one. See root `NOTES.md`,
"A module is bound to its host construction's private API", for the detail: the
rail and street families share no slot type strings, and more importantly each
family's modules are written against that family's private `result` contract
(`result.GetCoord`, `result.connector`, `result.addPlatformCallback` on one
side; `result.DemangleId`, `result.coord2terminalInfo`, `result.leftLen` on the
other). Cross-declaring a slot type makes the module offerable and then crashes
it on the first field access.

### Option A - one station family per level *(recommended)*

Never mix modules. Each level hosts a whole stock family, offset in z. The mod's
construction delegates each level to the stock family's `updateFn` via
`util.useFn` (proven in `pick-single-platform-side`) and post-processes the
returned table:

1. **Namespace the slot ids per level.** Slot ids are plain integers the host
   invents, and `params.modules` is keyed by them. Offset level L's ids, strip
   the offset before delegating and re-add it to the returned
   `result.slots[].id`. The stock closures (`GetModuleAt`, `DemangleId`) then
   see the map they expect and need no changes.

   **Confirmed working in-game 2026-10-08.** The probe added slots at
   `stock_id + 5e7` to the stock rail station and placed modules into them; the
   log reported slots 57399000 / 57400000 / 57401000 at `z=12`. Note the offset
   has to clear the stock id space, which is bigger than it first looks: the
   base constants alone run from `cargoPlatformSlotId = 6400000` to
   `passengerPlatformAddonSlotId = 10800000`
   (`modular_station.script.lua:41-46`), plus `1000 * coordI + 10 * coordJ`, so
   stock ids reach roughly 11e6. 1e8 per level is the clean choice.
2. **Translate the result** by `vec3.new(0, 0, L * 12)` - models, lanes,
   colliders, edge points, slot transforms.
3. **Strip `terrainAlignmentLists`** for L != 0.
4. **Rewrite `edgeLists[].edgeType`** to `BRIDGE` plus a `.bridge` resource name
   for L > 0, and `TUNNEL` plus a `.tunnel` one for L < 0.
5. **Prefix the construction params** per level (`l1_tracks`, `l1_length`, ...).
   Adding param keys is savegame-safe; see root `NOTES.md`, "Construction
   parameters are keyed by name".

The appeal is that you author no platform, track, bay or building modules at
all. The one thing you do have to author is **vertical circulation**, and the
underground station shows exactly how: pedestrian lane curves between levels,
wired into `station.terminals[].personEdges` / `personNodes`.

Cost: the delegation plumbing, the id namespacing, and the terminal wiring.
Limitation already accepted: one transport family per level.

### Option B - one unified multi-level station type

Own slot scheme, own module protocol, own modules for platforms, tracks, bus
bays, cargo bays, entrances, roofs, buildings and vertical links. That is
reimplementing both stock scripts - `modular_terminal.script.lua` is 3308 lines
and `modular_station.script.lua` is 1371 - inside one coherent framework. Best
end result, far more work, and it has to be re-checked against every game
update.

### Transfers may come for free

`StationGroup` is a first-class entity: `getStationGroup(stationEntity)`
(`api/tealdef/api/engine/system.d.tl:97`), and a line stop is addressed as
(station index, terminal index) *within a group* (`type.d.tl:1002-1013`). A
construction's `Construction.stations` is a list, and several stock
constructions already publish more than one `station` record - the harbor's
passenger and cargo stations, the rail station's `cargoStation`.

**If a construction's station records all land in one StationGroup, option A
gets interchange between levels for free**, and the vertical pedestrian lanes
become cosmetic rather than load-bearing. This is the single highest-value thing
to confirm, because it decides how much work option A actually is.


## Editing: levels are chosen at construction time

Settled 2026-10-08, after testing and a scope decision: **a station's level
layout is fixed when it is placed.** You cannot convert a single-level station
into a multi-level one afterwards. That is an accepted limitation and it removes
the hardest part of the design.

### Why the post-construction route is dead

`postConstructionModifiable` (`type.d.tl:1774`) is real, but the UI reads the
flag off **`desc.params`** - the construction's own top-level param list -
`entity_window_util.tl:1893-1912`:

```lua
local desc = api.res.constructionRep.get(constructionResId)
if desc and desc.params and #desc.params > 0 then
    for __, param in ipairs(desc.params) do
        if param.postConstructionModifiable then
```

**The modular rail station has no top-level `params` field at all**
(`modular_station.con.lua:259-295`); every param lives in
`constructionTemplates[i].data.params`. The street station is the same. So for
any template-based construction the loop above iterates nothing, and the
post-construction param panel never appears - which is exactly what a player
sees: no stock construction can have its parameters edited after building.

Confirmed in-game: the probe set `postConstructionModifiable = true` on three
params added to `template.data.params`, and none of them appeared on the built
station. **The flag was in the wrong place, so this is not evidence the flag is
broken** - it would plausibly work on a construction that declares top-level
`params`, the way the underground station does
(`underground_station.con.lua`, `params = { ... }` with an empty
`template.data.params`). Untested, and no longer needed.

### What replaces it

Nothing, because the problem dissolves:

- **Level layout is a placement-time decision.** Ordinary construction params,
  available in the placement toolbar, which is the one place params definitely
  work. Changing one re-runs `createTemplateFn` and `updateFn` live.
- **Module editing after placement needs no level switch at all.** Per-level
  slot types do the whole job: the MODULES list offers a module when its `type`
  matches a slot type on the selected construction
  (`construction.tl:4090-4135`), so each level's modules are their own entries
  and the level follows from *which module the player picked*. Confirmed in-game
  - the probe's upper-layer module was the only thing offered for the upper
  slots, nothing stock leaked in, and placing it landed at `z=12`.

Per-level `slotConfig` entries come along for free, which matters because
`SlotConfig.skipCollisionCheck` (`construction_util_serialized.d.tl:50-54`) is
what stops stacked slots fighting; the street station already sets it on all
five of its own slot types (`modular_terminal.script.lua:1301-1325`).

The slot picker's z-awareness is therefore moot. `Slot.height`, `autoFill` and
`alignToTerrain` remain undeclared-and-unused curiosities
(`construction_util_serialized.d.tl:113-123`; `shape` is used by the harbor at
`harbor_modular.script.lua:160-272`) - worth knowing about, not worth chasing.


## Picking a transport type per level

Requirement added 2026-10-08: at construction time the player picks what each
level *is* - road or rail - not just that the station is multi-level. Two params,
`level0Type` and `level1Type`, each None / Road / Rail.

That makes the construction a **router**: for each level, delegate to that
family's stock `updateFn` with the right z offset, then merge the results.

### Same family on both levels is the hard case. Different families is not.

When the engine calls a module's `updateFn` it passes **one** result table - the
host's. Each stock family's modules reach into that table for their own private
fields (root `NOTES.md`, "A module is bound to its host construction's private
API"), and the two families' field names are **disjoint**:

| family | fields its modules reach for |
| --- | --- |
| rail | `cargoStation`, `GetCoord`, `GetModuleAt`, `GetRoofAt`, `connector`, `addPlatformCallback`, `trackCoord2models` |
| street | `passengerStation`, `DemangleId`, `MangleId`, `leftLen`, `rightLen`, `needOuterLeft`, `needOuterRight`, `erastr`, `cat`, `coord2terminalInfo` |

So merging a street result and a rail result into one table gives **each**
family's modules exactly the fields they expect, with no collisions - as long as
no more than one level uses each family. Models land at the right height for
free, because a module composes its geometry relative to the slot `transform`
it is handed, and that transform already carries the level's z offset.

**Rail over road is therefore the easy case, and it is also the motivating
example** - an elevated train station over a bus station. Take it as v1.

Two levels of the *same* family would need one set of host closures per level
behind a dispatcher that decodes the level from the slot id, plus per-level
routing for the plain tables stock modules mutate (`coord2terminalInfo`,
`addPlatformCallback`, the `terrainAlignmentLists` they insert at the slot
transform). The closures are tractable; the plain tables are the awkward part.
Defer it.

*The disjointness above is read out of the two scripts, not yet tested. It is
the next thing to probe.*

### Both orderings, and where they differ

Scope for v1, decided 2026-10-08: **rail over road and road over rail**. The
merge itself is symmetric - the disjoint-field argument above does not care
which family is elevated - so neither ordering is harder to wire than the other.
Three things are not symmetric, though:

- **Electrified rail at level 0 cannot take a tall catenary.** `power_pole_1`
  reaches 10.6 m and the soffit of a deck at +12 is 9.6 m; the short
  `power_pole_2` at 8.17 m fits. So *rail under road* has to force the short
  catenary (or none), and *road under rail* does not. See "How tall is a level?".
  The street station's `tramCatenary` is the mirror case and has not been
  measured.
- **A STREET edge at +12 as a bridge is untested.** `TRACK` at +12 with
  `edgeType = "BRIDGE"` is confirmed working. `concrete.bridge` declares
  `carriers = { "RAIL", "ROAD" }` so a road viaduct should be supported, but
  road-over-rail depends on it and nothing has driven a bus up one yet.
- **The street station's `snapPoint`** snaps to street edges
  (`underground_station.script.lua` does the same) and would be at +12 if that
  family is elevated, which is probably wrong. Needs handling.

What both orderings share is the one genuinely unsolved piece: **pedestrian
access between levels.** Each stock family provides its own entrance at its own
level, so the elevated family's entrance lanes float at +12. Passengers need a
lane path from grade to +12 wired into `station.terminals[].personEdges` /
`personNodes`. The stock underground station is the worked example, at the other
sign. This is the main authoring job in option A and it is unavoidable in either
ordering.

### A road terminal needs `vehicleEdges`

Confirmed in-game 2026-10-08, by getting it wrong. A hand-built bus terminal
with `vehicleNode` but no `vehicleEdges` places, appears in the line manager and
can be picked as a stop - and then the line fails with **"can't connect stops"**.
`vehicleNode` only says where a vehicle stands; `vehicleEdges` is the drivable
path *through* the stop.

Every stock ROAD terminal sets it (`modular_street_station/modules.script.lua:92-98`
and `:501`; the airports too). The stock **underground station does not**, which
is the trap - it was the obvious template to copy because it is the only
off-grade station in the game, but its terminals are TRAM and trams follow track
edges instead.

The field is **absent from the `TerminalDef` record**
(`construction_util_serialized.d.tl:173-184`), which declares only
`comfortFactor`, `personEdges`, `capacity` and `cargoTransferSpeeds` - not
`vehicleNode`, `vehicleEdges`, `personNodes` or `transportModes`. Shipped
content wins.

### Settled: the two stations **do** join one StationGroup

**Confirmed in-game 2026-10-09.** This was the mod's highest-value open
question - "does a line stopping on one level let passengers reach the other?" -
and the answer is yes, for free. Passengers use the bus station, use the train
station, and transfer between them. No terminal merging, no index rebasing, no
work at all: each delegated family keeps its own `station` record and the engine
groups them.

So the "one station, terminals at two heights" branch below is moot, and the
earlier rejection of it (also below) was arguing about the wrong thing.

**The price is naming, and it is not optional.** A StationGroup has exactly one
name, so the two levels cannot be named individually - the claim that each level
would be "separately nameable" was simply wrong and is corrected here. The same
grouping that gives free interchange is what collapses the two names into one.
That is a good trade, but it is a trade.

### Why the upper level says "Tram Station"

`getSubconstructionDescriptionAndSortKey`
(`gui/entity_window/make_entity_window.tl:46-101`) builds the label like this:

```lua
local stationGroupEntity = api.engine.system.stationGroupSystem.getStationGroup(entity)
local carriersAndTransportModes = api.engine.system.stationGroupSystem.getCarriers(stationGroupEntity, -1, -1)
local carriers = carriersAndTransportModes[1]
local stationName = _("Station")
for __, carrier in ipairs(carriers) do
    if carrier == ROAD then stationName = _("Road Station")
    elseif carrier == RAIL then stationName = _("Train Station")
    elseif carrier == TRAM then stationName = _("Tram Station")
    ...
```

Two things to take from it:

1. **The carriers are the whole _group's_, not the station's**, and there is
   **no `break`** - so the *last* carrier in the list wins and **both** of our
   stations get the same label. It is one label for the group, like the name.
2. Nothing in this mod chooses it. It is a pure function of the group's carrier
   list.

What is **not** yet explained is why `TRAM` is in that list at all. It should
not be: both street terminals gate `TRAM` behind
`constrParams.tramTrack and constrParams.tramTrack > 1`
(`modular_street_station/modules.script.lua:85-90` and `:486-491`), this
construction declares no `tramTrack` param, and street's `updateFn` is handed
`tramTrack = 1`, so `selectTramTrack` returns `"NO"` everywhere. Something else
is contributing a TRAM carrier.

Worth knowing before chasing it: this is **cosmetic**. The label is a heading in
the entity window; lines, routing and transfers all work. Next step if it is
picked up is to read the carrier list directly from a game script -
`api.engine.system.stationGroupSystem.getCarriers(getStationGroup(e), -1, -1)` -
rather than reasoning further from the content, since that turns a guess into a
list.

### Two stations or one? A fork that turned out not to matter

Confirmed in-game: a construction with two `station` records produces **two
separately selectable stations**, not one grouped station. The train station and
the bus deck each appear on their own in the line manager.

That is not necessarily wrong, and there are two shapes to choose between:

- **Two stations.** What the probe did first. Each level is its own station,
  separately nameable, each taking its own lines. Passengers transfer by
  *walking* the pedestrian network between them - which is exactly what the
  deck's `linkable` access ramp provides. Simple to build, because each level's
  delegated family keeps its own station record untouched.
- **One station, terminals at two heights.** Append the upper level's terminal
  to the lower level's existing `station` record. Then it is one station with
  terminals at 0 and +12, and transfers are free rather than a walk. The catch:
  terminal index pairs are relative to the subconstruction that owns the
  station, so the upper level's lanes have to live in the **lower** level's
  `laneLists`. That is easy by hand and awkward when delegating to two stock
  families, each of which builds its own subconstruction.

The probe now has an `ML: one station` switch to try both. Which one wins
decides how the merge rules below have to work, so it is worth settling before
writing the real delegation.

### The terrain under an elevated level: not the alignment lists

Instrumented 2026-10-08, after three rounds of reading the stock scripts and
concluding each time that it "should be covered". The diagnostics settled it:

```
after lift: result.terrainAlignmentLists=0  result.groundFaces=0
            sub1 tag=1 models=22 align=0 ground=0 station=true
after lift: cargoStation inSubconstructions=true itsAlign=0
after lift: edgeLists ... 5:TRACK/BRIDGE/edges=12/z=12/align=false
```

Every alignment entry gone, every ground face gone, `cargoStation` confirmed
present in `subconstructions` and also clear, and the track edges correctly at
z = 12 with `edgeType = BRIDGE` and `alignTerrain = false`. **And the terrain
still rises to the deck.** So neither `terrainAlignmentLists` nor
`alignTerrain` is responsible.

The remaining candidate is the engine's own bridge structure. `concrete.bridge`
declares `abutmentLen = 4.0` with `abutmentBase` / `abutmentRepeat` /
`abutmentTop` models, and an abutment is an **earthwork**: under a deck 12 m up
it is a 12 m embankment. That would also explain the second symptom - a track
drawn to the station's own track ends reports a collision, which is consistent
with it hitting raised ground rather than the station.

Why the Phase 0 bridge probe did not show this: its edge was a single 2-point
edge with both nodes **free** and nothing attached. The station's track edges
come from `trainstationutil`, which sets `snapNodes` on their ends, and a snap
node is where the engine joins to the outside world - plausibly where it decides
an abutment is needed.

**Superseded 2026-10-09. The answer was an _empty_ `terrainAlignmentLists`, not
`Slot.alignToTerrain`.** The section below is kept because its bisection is
sound and its table is still the record of what was observed - but its
conclusion was overtaken by the root `NOTES.md` finding "An **empty**
`terrainAlignmentLists` is not 'leave the terrain alone'", which tested
`Slot.alignToTerrain` against a build that could falsify it and **cleared it**.
The fix in the code is the grade anchor; nothing sets `slot.alignToTerrain`.

Leaving the two accounts to disagree had a cost. The elevated track's
`snapNodes` were converted to `freeNodes` as part of this same terrain hunt, on
the same mistaken theory, and the conversion was never revisited once the real
cause was found - it surfaced much later as "modules cannot be deleted once a
track is connected" (root `NOTES.md`, "A station's `snapNodes` are
load-bearing"). **When a bisect finds the real cause, revert the things that
were tried on the way and left in, and mark the superseded account as
superseded.**

The original account follows.

The bridge/abutment theory was wrong, and so was the edge theory. Cutting the
construction down one part at a time settled it in a single session:

| build | terrain |
| --- | --- |
| everything | deformed |
| lifted track edges only, no subconstructions and no slots | **flat** |
| no rail level at all | flat |

So the lifted track edges never touched the terrain, with or without a bridge.
What did was the **slots**. A slot asks the terrain to come up to meet it unless
told otherwise, and the modular rail station emits on the order of 140 of them;
lifted to +12 that is a 12 m mound the width of the station - which is exactly
the "terrain rising towards the centre of the station" that had been visible
since the very first attempt.

`Slot.alignToTerrain` is declared at `construction_util_serialized.d.tl:121` and
set by **no shipped content**, so the engine default is on. It is one of the four
undeclared-and-unused `Slot` fields listed under "Editing" above, where it was
guessed to be "made for off-grade slots" and then not followed up on for several
rounds. The fix is one line per slot:

```lua
for _i, slot in ipairs(result.slots or {}) do
    if slot.transf then slot.transf = lift(slot.transf, dz) end
    slot.alignToTerrain = false
end
```

A caution for the elevated level generally: **anything carrying an implicit
"meet the ground" behaviour has to be switched off per level, not just the
things named `terrainAlignment*`.** The candidates found so far are
`terrainAlignmentLists`, `groundFaces`, `EdgeList.alignTerrain` and
`Slot.alignToTerrain`.

*And the counter-caution, learned the expensive way: that list is a list of
**candidates**, not of things to switch off pre-emptively. Of the four, only
`terrainAlignmentLists` turned out to matter, and the collateral damage came
from switching off a fifth thing - `snapNodes` - that was never on the list and
is not a terrain control at all.*

**Lesson worth keeping separately from the answer:** three rounds were spent
reasoning from the stock sources about what should be in the result, when one
round of logging what *was* in it would have ruled out two thirds of the search
space immediately. Instrument earlier.

### Which menu tab, and what it snaps to

Decided 2026-10-08: **the level at grade decides both.** That is the level the
player is actually placing against, so it is what the construction should snap
to and where they would look for it.

| variant | ground level | menu tab | snaps to |
| --- | --- | --- | --- |
| rail over road | bus platform | `road_buildings` | `STREET` |
| road over rail | rail platform | `rail_buildings` | `TRACK` |

The `snapPoint` has to be set **after** the elevated family has been lifted,
otherwise it gets carried up with everything else and the station tries to snap
12 m in the air. Shape is the underground station's:

```lua
result.snapPoint = {
    transf = transf.transl(vec3.new(0, 0, 0)),
    snapToBaseEdgeTypes = { "STREET" },
    allowSnapToBaseEdgeEnds = true,
}
```

### One station with terminals of two carriers does not work

Tried and rejected 2026-10-08. The probe's one-station mode appended a BUS
terminal to the rail station's own `station` record: the script ran and logged
`2 terminal(s) on that station`, so the terminal was accepted into the table -
but the resulting stop was not usable in game. Two separate station records, one
per level, is both the working arrangement and the preferred one.

Not chased further, since two stations is the design. If it is ever revisited,
the likely constraint is that a single station entity carries one carrier while
a *StationGroup* is what spans several - `getCarriers` is a group-level call
(`engine/system.d.tl`), and `getSubconstructionDescriptionAndSortKey` names a
group from the carriers it finds.

### Merge rules

Concatenate, never overwrite: `slots`, `edgeLists`, `models`, `colliders`,
`terrainAlignmentLists`, `subconstructions`, `slotConfig`. Then per level:

- offset every slot `transf` and every edge point by `level * 12`
- namespace slot ids by level (see option A step 1 above)
- for `level ~= 0`, drop the `terrainAlignmentLists` the family emitted and set
  `alignTerrain = false` on its edge lists
- for `level > 0`, rewrite `edgeLists[].edgeType` to `BRIDGE` with a `.bridge`
  resource name

Each family contributes its own station subconstruction, so a two-level station
has two station records - which makes the StationGroup question (does a line
stopping on one level let passengers reach the other?) the next thing that
actually matters.


## The deck does not reach the bus entrance

Worth knowing before designing anything that spans the two levels, and it was
not obvious until the coordinates were worked through.

With the default seeding the elevated deck is **one platform plus one track**,
so it is 10 m wide. The quarter turn maps rail-local x to world y, which puts
the deck at world **y in [-2.5, 7.5]** - over the bus platforms. The street
entrance slot sits at world **y = -15**, and its road runs out to **y = -30**.

So the deck and the entrance road are about 12 m apart and **do not overlap at
all**. The road only passes under the deck once the player adds enough
platforms and tracks to widen it - each extra one adds 5 m in world y.

The consequence for the concourse (`PLAN.md` Phase 10): "a tunnel entrance where
the road passes under the deck" describes something that does not exist in the
default layout. A concourse derived from the *entrance* slot sits on the
entrance road, 12 m clear of the deck above it, which is both the wrong place
for a portal and directly in the way of the road.

## The elevated track carries no bridge

**Decided 2026-10-09.** The elevated track's edge lists keep `edgeType` at its
default `NORMAL`. They used to be `BRIDGE` on `::/infrastructure/bridge/stone.bridge`.

It worked - Phase 0 proved it, and that probe closed the load-bearing risk for
the whole mod, so this is not a retraction of that finding. The problem is that
a bridge type is a **generic** answer to "hold this up": the engine generates
pillars and abutments from the edge alone, knowing nothing about what the
construction has at grade, so the structure pushed straight through the bus
station below. `pillarMinDist = 60` / `pillarTargetDist = 72` /
`pillarMaxDist = 84` leave no room to dodge anything, and the engine's own
pillar-dodging (`Proposal.Context.extendProposalRedoPillars`) only applies to
bridges it generates from player-drawn edges, not from a construction's.

This is the same argument that already moved supports out of `updateFn` and
into player-placed modules, and it is worth stating as a rule, because it has
now come up twice:

> **Nothing automatic can know what the player means to put under the deck.**
> A multi-level station's structure has to be placed, not generated.

So the deck is bare, and looking tidy is the job of modules with art made for
it. Two consequences:

- **Track tiles now get support slots too.** They were previously skipped
  precisely because the viaduct carried them; without it they would be the one
  part of the deck with no way to support it. Their `spacing` is the same
  5 x 39 m as a platform tile, so no special case was needed.
- **The support brick's one remaining argument is gone.** It is
  `stone_abut_rep_rep.mdl`, chosen partly so the brickwork would match the
  stone viaduct. There is no viaduct to match now, so the choice of *stone* is
  arbitrary until there is purpose-made art.

`alignTerrain = false` stays on those edge lists. It is the explicit "do not
deform the ground along this edge" control and has nothing to do with whether
the edge has a structure.

Still open, and the first thing to watch: **does the engine mind a `NORMAL`
track edge at +12 with nothing beneath it?** The Open Questions below already
ask whether geometry at height needs support and conclude probably not, on the
evidence of roofs at 5.5 m and the main buildings - but no stock construction
puts a *track* up there unsupported, and `BRIDGE` is what Phase 0 tested.


## The player's connecting edge earthworks, in both directions

Confirmed 2026-10-08, and it is the mirror image of the level -1 trench.

The station's **own** elevated track is fine: a `BRIDGE` edge at +12 with free
nodes and a grade anchor renders as a stone viaduct, leaves the terrain alone,
and accepts a connection. But a track the **player** draws from that connection
outwards comes down to ground as an **embankment**, not a viaduct - and choosing
the stone bridge in the track builder does not change that.

So the same rule holds going up as going down (`NOTES.md`, "Parked: level -1"):
a construction can own off-grade infrastructure cleanly, but the moment the
player's own edge has to get from grade to the station's height, the engine
grades earth rather than building structure. Bridge and tunnel types seem to
apply where the engine has already decided a span is needed, not as a way to
demand one.

**Decision 2026-10-08: accept the embankment.** It is what a real railway does
to reach an elevated station, and the alternative below buys only a
*relocated* embankment for a meaningful amount of machinery. Revisit if the
embankment turns out to bury the lower level in practice.

Options if it is picked up again, none of them tested:

1. **Own more of the approach.** Give the station longer elevated `BRIDGE` stubs,
   with the free nodes out at a distance, so the player connects further away and
   the construction - not the engine - decides what the viaduct looks like. The
   stock underground station does exactly this at the other sign: it owns the
   whole descent and only exposes nodes already at depth.
2. **Ramp inside the construction**, bringing the track down to grade before the
   free node, so the player only ever connects at ground level. Loses the
   elevated-approach look but sidesteps the problem entirely.
3. Accept the embankment as the cost of connecting to an elevated station, which
   is at least what a real railway does.

Option 1 is the most promising, and the question it has to answer is how a
fixed stub survives the player extending the station with modules. It does,
because the stubs would be **derived, not remembered**: the stock station
already recomputes where a track run ends every rebuild - a node becomes a
connection point only when there is no adjacent track module
(`trainstationutil.lua:80-87`) - so approach spans built from that list follow
the ends as the station grows.

Two details for whoever builds it: emit the spans as a **separate edge list**
rather than appending to the stock one, which carries `tag2nodes` and node
indices the terminals reference (edges connect where endpoints coincide, so a
separate list still joins up); and the station's own end nodes then become
internal junctions - neither snap nodes, which pull the terrain, nor free nodes.


## Parked: level -1

Parked 2026-10-08 to keep the first working version to levels 0 and +1. Nothing
here is a dead end - this is a scope cut, not a failure. Everything below was
established before parking, so picking it up again should not need re-deriving.

**What already works.** A construction can own a `TUNNEL` edge at z = -12 using
`edgeTypeName = "::/infrastructure/tunnel/tunnel_b.tunnel"` (the `RAIL` carrier).
It renders correctly, the terrain above it is undisturbed, and a player-drawn
track will connect to its free nodes. Confirmed in-game with
`probe/probe_tunnel.con.lua`, which is left in the probe mod as the record.

**The one open problem: the player's connecting track trenches.** Drawing track
from the surface down to a node at -12 on flat ground produces a cutting, not a
tunnel, even with a tunnel type selected in the bridge/tunnel picker. Most
likely this is ordinary game behaviour rather than a defect - a tunnel needs
cover above it, and on flat ground the first stretch of a descent has none.

Three things to try when this is picked up again, cheapest first:

1. Draw the connecting track with **underground mode on** (`G`, input action
   `IA_UNDERGOUND_MODE_TOGGLE`). That mode is what sets `undergroundMode` on
   the track builder (`construction_react_util.tl:3253`), and it is plausibly
   the whole answer.
2. Connect from existing underground track rather than from the surface.
3. Try it on a hill, where there is cover from the start.

**The structural answer, if those fail.** The stock underground station never
exposes this problem because **it owns the entire descent itself** - surface
head at z = 0, mezzanine at -12, platform at -17.65, and tram stubs at -18 whose
free nodes are already at depth. The player only ever connects underground to
underground. A level -1 station would likely have to do the same: own its
access shaft rather than expect the player to drive a track down to it. That is
a bigger piece of work than level +1 needs, which is the main reason for
parking it.

**What does not carry over.** The 12 m pitch was partly justified by `tunnel_b`'s
12.16 m envelope and by the underground station's exactly -12 first drop. With
-1 parked, neither constrains anything, so a future level -1 may want 13 m - see
"How tall is a level?" above.


## A rail building slot type does not tell you the building's size

Read out of the install 2026-10-09, while reviewing for the beta. It matters
because the support layer sizes itself from the thing above it, and the obvious
key - the slot type - is not one:

| slot type | `extend` of the modules that declare it |
| --- | --- |
| `rail_building_size1` | `6, -6, 0, -17` |
| `rail_building_size2` | `11, -11, 0, -17` **and** `11, -11, 0, -23` **and** `11, -11, 0, -38` |
| `rail_building_size3` | `21, -21, 0, -38` |

`main_building_1` and `main_building_2` are both `rail_building_size2` at 17 m
and 23 m deep, and `side_building_3_cargo` is also `rail_building_size2` at
38 m. The names also mislead: `main_building_1` goes in a *size2* slot, and
`addSlot(id, ...)` / `id+1` / `id+5` hand out size2, size3 and size1 from one
base id (`modular_station.script.lua:688-692`).

`config.extend` in the module's `updateScript.params` is `{ xMax, xMin, yMax,
yMin, ... }` in model space and is uniform across eras, so it is the right
source - keyed by module name, or read off the module desc at runtime if
`api.res.moduleRep.get(...).updateScript.params` is reachable (rail reads
`.metadata` off that desc, so the desc is). See `PLAN.md` Phase 7.


## The upgrade tools, round two: a gate on `entry.metadata`

**Confirmed** 2026-10-12. The catenary tool highlighted the elevated track,
accepted a click, and produced no catenaries; changing where the metadata is
read from fixed it on the next run. That fix changed nothing else that could
matter, so the gate below *was* the refusal.

The first round of this (2026-10-09, root `NOTES.md`, "sometimes the sibling
retry is not enough") was `isAffectedByToolFn` failing to resolve, so the tool
never offered the station at all. That part is fixed: the tool now highlights,
which means `isAffectedByToolFn` is answering `true`. What is left is
`upgradeFn` declining, which looks exactly the same to the player and almost the
same in the log.

What the log says, for a session that ended right after the attempt:

- 85 rebuilds, no `ERROR`, none of the delegation warnings;
- module edits all applied (`module add slot=8400990 ... name=::/trainstation___/infrastructure/track/simple/simple.street_template`);
- three rebuilds at the end with **no** module change and the edge-list count
  unmoved at 8.

That last line is the evidence. A catenary swap renames the track module to the
`simple_catenary` one, and the track module's `updateFn` resolves its edge list
by name through `trainstationutil.findOrMakeNewEdgeListNum` - rail pre-creates
only standard / standard_catenary / high_speed / high_speed_catenary, so a
`simple_catenary` row has to **append a new edge list**. The count would have
gone 8 -> 9. It did not, so no renamed module ever reached `updateFn`.

The cause was a gate this mod added and stock does not have:

```lua
if entry.metadata == nil or not entry.metadata.track then return params end
```

`entry` is `params.modules[slotId]`. Rail's `updateFn` does read
`entry.metadata.track` that way (`modular_station.script.lua:495`), but its
`upgradeFn` pointedly does **not** - it resolves the desc instead, for the same
module it is about to rename:

```lua
local moduleDesc = api.res.moduleRep.get(api.res.moduleRep.find(params.modules[slotId].name))
local metadata = moduleDesc and moduleDesc.metadata or nil
```

Two functions, one field, two different ways of getting it, in the same file.
That asymmetry is not a style quirk, it is the API: **the entry handed to
`updateFn` is the enriched one the engine builds for the module pass, and the
entry handed to `upgradeFn` is the stored one, which carries `name` and little
else.** So our gate rejected every upgrade.

Fixed by resolving the metadata from `api.res.moduleRep` (`moduleMetadata` in
the script) and keeping the entry's own metadata only as a fallback. The gate
itself is worth keeping - it is what stops a mis-aimed tool renaming a bus
platform into a track.

**The second lesson is about the silence, and it is the same one as last time.**
A declining `upgradeFn` has no failure mode: the cursor still offers the
upgrade, the construction still rebuilds, and nothing anywhere says the swap was
refused. There is now a deduped `upgrade ...` log line on every branch of
`upgradeFn`, including each refusal, so the next failure of this kind is a line
in the log rather than two rounds of inference.

**Not a savegame problem.** The question came up because the station under test
came out of a save. It is not: `upgradeScript` is read off the `.con.lua` at
load, so a station in a save gets the current script, and the same session shows
module editing - which goes through the same stored `params.modules` - working
on that very station.


## A support can be placed and not removed

> **Closed, 2026-10-12.** Two causes, found in this order and neither of them
> the supports: a **seeded concourse** (rounds five and six) and then the
> **zeroed slot reservations** that had been added while chasing it, which cost
> the tracks their only pickable geometry (round seven). Confirmed in game:
> tracks and platforms both delete, re-add and delete again. The reading below
> is kept because every step of it still holds - it is only the conclusion that
> pointed at the wrong module.

What was established, 2026-10-12:

**The message is the bulldozer's.** `Invalid configuration, N modules will
collide` comes from `ModuleBulldozerAction.cpp`, not from the builder - see the
root `NOTES.md`, "The engine's own strings are readable". That fits the symptom
exactly: the builder accepts a support, the bulldozer then refuses to take it
away. It also means no Lua hook of ours is involved in the decision.

**Nothing was removable that session, not just supports.** From the `module
remove` lines: every one of the 93 of them reads `modules=16->15`, and no later
line ever starts from 15. A removal that committed would show up as the next
preview starting one lower, so none did. The previews cover one of our supports
(`674000103`, `674000105`, `674000202`, `684010205`), a **rail** passenger
platform (`7400020`) and a **street** entrance (`20015503`). Adds in the same
session did commit, 12 -> 16, one per click. So the refusal is a property of the
configuration, not of our slot type - which is consistent with a whole-proposal
check that only the bulldozer runs.

**The first overlap diagnostic was wrong, and its answer was an artefact.** It
reported `20 of our grade-level slot pair(s) reserve overlapping ground` and
named a platform cell and the track cell beside it. Both halves were broken:

  * it treated every `spacing` as axis-aligned in construction space, but
    `RAIL_XF` is `transl(0,0,12) * rotZ(90 deg)`, so a **rail-derived slot's
    local x runs along construction y**. A support slot keeps the level's
    rotation on purpose - `addSupportSlots` copies `m`'s 3x3 and only zeroes the
    z translation - so its rectangle is 5 m along construction y and 7.8 m along
    construction x, and reading `spacing` the other way round turns two cells
    5 m apart and 5 m wide, touching exactly, into a 2.8 m overlap;
  * it swept **all** slots rather than occupied ones, and rail emits
    `passenger_platform` and `track` for one cell at the same transform with the
    same rectangle (`modular_station.script.lua:559-560`), so there is always
    something to find.

The count proves it: 20 pairs is exactly the 4 tiles x 5 cells of
platform/track pairs on that station and nothing else. The rewrite uses each
slot's own axes, covers all three families (rail's slots get `RAIL_XF` applied,
since `liftRail` has not run yet when it is called), counts occupied slots only,
and separates same-level pairs from cross-level ones. A support at grade under a
platform at +12 overlaps in plan **by design**; that only matters if the check
ignores height, which is the next thing the log can tell us.

**The slot rectangles are not the cause.** From the 2026-10-12 14:35 session,
with the corrected diagnostic: the only *same-level* overlap in the whole
construction is the concourse against the street entrance
(`20015503 street/street_terminal_entrance_exit (0.0,-22.5) 16.0x15.0` vs
`820015500 ours/ml_concourse (0.0,-18.0) 24.0x6.0`), and the concourse is the
one module that **does** delete. The supports' only overlaps are the five
cross-level ones with the platform 12 m above them. So a reserved-ground overlap
is neither necessary nor sufficient for the refusal, and the next section has
what is.

One more tell in the same log: a removal preview logs a `module remove` line
because it re-runs the build, and there is one for a street slot
(`slot=20210000 ... modules=17->15`) and **none for any support slot**. The
bulldozer therefore refuses a support before it rebuilds anything - a pre-check
on the target, not a verdict on the resulting configuration.

Still worth keeping in view: our supports stand at grade both under the rail
deck and alongside the bus station, so a cross-family overlap at grade has never
actually been measured. The street station's own slots all carry
`skipCollisionCheck = true` (`modular_terminal.script.lua:1301-1325`); rail sets
`slotConfig = {}` and so carries none, which the merge patches.


## The brickwork has to be built on the cell outline, not tiled across it

Two rounds on this, and the second one was the real bug.

`stone_abut_rep_rep.mdl`'s `boundingInfo` is `bbMin.x = -2.21521`,
`bbMax.x = 2.216`, `y = 0 .. 4`, `z = 0 .. 2`: **4.43** x 4 x 2 - not the 4.4
the code assumed - anchored at its own back edge in y and its bottom in z, and
centred in x. So it is a wall whose length is x, whose thickness is y, and whose
one finished face points along y.

The sizing was wrong first. `supportModels` laid the piece at full size and
stepped by `width / cols`, a different number: for a 5 m platform cell,
`ceil(5 / 4.4)` is 2 columns at a 2.5 m step, and a 4.43 m piece at each covers
-3.47 .. 0.97 and -0.97 .. 3.47. That is ~2 m of doubled masonry down the middle
and ~1 m over each edge, and since cells are 5 m apart on the rail grid, the
cells either side of a platform overlapped each other's brickwork too.

Scaling each piece to its tile fixed the overhang and did **not** fix the
appearance, because the layout was wrong as well. Every piece was laid
unrotated, so the "sides" of the cell were more y-facing slabs instead of walls
running along y. With the tile count rounded, a 5 m cell is one column wide, so
what came out was two walls across the cell - one on the near edge, one through
the middle - and nothing at all on the other three edges. Hence "the geometry of
the support does not coincide with the slot at all": the footprint was right,
and the thing drawn in it bore no relation to its outline.

The shape that works is four walls **on** the cell's outline, each scaled to the
edge it stands on, with the two side walls inset by the thickness of the end
ones so no two walls claim the same ground. `brickWall` does that for one edge
and `supportModels` calls it four times; `concourseModels` calls it twice, for
the two piers either side of the entrance road. Verified against the model's own
bounding box before deploying: a 5.0 x 7.8 cell draws into
-2.501 .. 2.501 by -3.900 .. 3.900 by 0 .. 12, which is the cell to within the
rounding of the brick's own asymmetry in x.

**Both faces, deliberately.** Each slab is emitted twice, the second turned
through 180 degrees (or -90 against +90, for a wall along y) so that the two
copies fill the same volume with their finished faces opposed. The piece has one
finished face and nothing in the model file says which way it points, so this
buys orientation-independence for the price of twice the models: 48 per
platform-cell support, 24 for a concourse. That is the placeholder bargain, and
it is what makes the earlier symptom - different faces from different sides,
geometry that appears only under the module-delete ghost, which draws without
backface culling - go away without having to work out which way round the mesh
is. The real answer is still art made for the job (`PLAN.md` Phase 10 step 3),
and when that lands the twin can go.


## Round three: what collides is the collider, 0.8 m into the next cell

**2026-10-12.** The symptom was "the supports are a bit wider than necessary -
maybe that is why I still cannot delete them", and that guess was right, for a
reason nothing on screen shows.

`stone_abut_rep_rep.mdl` declares a `BOX` collider that is **not centred on its
mesh**: `halfExtents {1.71561, 2, 1}` at `(1.20039, 2, 1)`, so it covers
`x = -0.52 .. 2.92` where the mesh covers `-2.22 .. 2.22`. It reaches 0.70 m
past the piece's own `+x` edge - see the root `NOTES.md`, "A model's collider is
not its mesh". Scaled to a tile `step` metres long the overhang is
`step * (2.916 / 4.43 - 0.5)`, i.e. `step * 0.158`, and because every slab is
drawn twice with the twin turned 180 degrees, the pair overhangs its tile at
**both** ends.

With the walls standing on the cell outline, that put the envelope of a
5.0 x 7.8 platform cell at 2.30 x 4.82 half-extents against a cell of
2.50 x 3.90: 0.79 m into the next cell across the platforms, 0.92 m along them.
Supports sit 5.0 m apart across and 7.8 m along, so **every adjacent pair
overlapped**, by 1.6 m and 1.8 m of collider respectively. In the 14:35 session
the five supports were at (55.6,0), (24.4,0), (-24.4,0), (40,5) and (-24.4,5) -
the last two of those are neighbours across the platforms - and in the earlier
session `674000103` and `674000105` were neighbours along one.

The fix is not a bigger inset, because the overhang is a fraction of whatever is
left after the inset: a flat 0.75 m off a 5 m cell leaves a 3.5 m pier whose
collider reaches 2.30 m, which is 0.20 m of clearance rather than the 0.75 m it
looked like buying. `fitSpan` solves it the other way round,
`span * (1 + 2 * overhang / n) = cell - 2 * SUPPORT_MARGIN`, iterating twice
because `n` is `tileCount(span)`; `n` has to be in there or a 40 m building cell
would shrink to 29.6 m instead of 37.7 m. `tileCount` now rounds **up**, which
caps a tile at the piece's own length and so caps the overhang at 0.70 m, at the
price of masonry squeezed to ~70% on spans that do not divide.

With `SUPPORT_MARGIN = 0.5`, verified against the model's own boxes before
deploying - mesh and collider corners through each model transform:

| cell | drawn envelope | clear of the cell | gap to the neighbour |
|---|---|---|---|
| 5.0 x 7.8 (platform) | 4.0 x 5.9 | 0.50 / 0.97 | 1.0 m / 1.9 m |
| 18.5 x 7.4 (size1 building) | 17.5 x 5.5 | 0.50 / 0.94 | 1.0 m |
| 40.0 x 7.4 (size3 building) | 39.0 x 5.5 | 0.50 / 0.94 | 1.0 m |
| 24.0 x 6.0 (concourse) | 24.0 x 5.0 | 0.00 / 0.50 | - |

The concourse is inset along its depth only: its piers' x is load-bearing - it
is what clears the 16 m entrance road - and a wall running along y has no
overhang across its thickness, so x was already exact.

`supportUpdateFn` now logs `drawn=` beside `cell=`, from `drawnExtent`, which
pushes the collider corners through each emitted transform. It has to come out
smaller than the cell; bigger means geometry is in the neighbour's cell again.

If removal is still refused with all geometry inside its cell, the next lever is
stock's own answer for a slot stacked under or over another one:
`spacing = { 0, 0, 0, 0 }` (root `NOTES.md`, "A slot stacked over another one
reserves no ground"). That would need `supportCell` to read its dimensions from
somewhere other than `spacing`, which is the only reason it has not been tried
first.


## Round four: a support slot must reserve no ground

> **Superseded in part by "Round seven".** Our own slots still reserve nothing -
> that part stands, and stock does the same for a stacked slot. Extending it to
> stock's *rail* slots did not fix anything and cost the tracks their only
> pickable geometry; those are clipped now, not zeroed.

**2026-10-12, after the clearance fix.** The report that settles the shape of
the problem: *"I can't delete any station modules after placing a support."*
Not the support - **any** module, and only once a support exists. So this is not
a property of the module being removed; it is the configuration being invalid
while a support is in it, which is exactly what
`Invalid Configuration, {count} Modules Will Collide` says if `count` is a count
over the whole proposal rather than the target.

What a support does that nothing else does is reserve ground **under another
module**. And the engine's module collision check is flat - height is not in it.
That was already proven here from the other direction, and the proof was written
off as a placement quirk at the time: before `mergeResults` set
`skipCollisionCheck` on every slot type, a rail station building at **+12** was
refused as colliding with the **bus station at grade**, and highlighted it as
the obstruction. Two modules 12 m apart vertically collide in this engine's
arithmetic.

So a support reserving its cell at grade under the deck it holds up is a
collision by construction. `skipCollisionCheck` fixes that for the builder - it
is a `SlotConfig` field - and does not reach the bulldozer's own copy of the
check, which is why placing works and removing does not.

Stock's answer is not `skipCollisionCheck`, it is to reserve nothing: the
platform roof and platform addon slots sit above an occupied platform slot and
declare `spacing = { 0, 0, 0, 0 }`
(`rail/modular_station/modular_station.script.lua:567-612`), with the
relationship carried by `dependentSlots` instead. Our support and concourse
slots now do the same - the concourse too, because it spans the entrance road on
purpose and so overlaps the street entrance's tile by design.

Consequences, all small:

- a support module can no longer read its size off its own `spacing`, so
  `addSupportSlots` records `supportCells[slotId] = { width, cellD }` and
  `supportCell` reads that. It is rebuilt with the slots, and the module pass
  runs after the construction pass in the same build;
- `slotBox` substitutes those dimensions back in, so the overlap diagnostic
  still measures what our modules *occupy* rather than going quiet about the
  only modules it was written for;
- the concourse module already sized itself from `CONCOURSE_W/D`, so nothing
  there had to change.

Both reservations were zeroed in one go, which does cost the attribution: if
removal works now, it does not prove the concourse's same-level overlap with the
entrance was harmless. Zero reservation is the right shape for both regardless -
each is deliberately stacked on something else - so the trade was worth it.

`dependentSlots` is the half of the stock idiom still missing: removing a
platform orphans the supports under it rather than taking them with it. See the
open questions.


## The supports were too short, and `SUPPORT_MARGIN` paid for an overhang that was not there

The clearance work gave both directions of a cell the same 0.5 m margin plus an
allowance for the collider overhang. Along the span that is wasted: a collider
overhangs the direction its wall **runs**, not the direction of its thickness,
and in a four-walled cell the extremes along the span are the end walls'
thickness, which is exact. The side walls, inset by the end walls' 1 m, cannot
reach past it either - their worst overhang is 0.70 m.

So a 7.8 m cell drew 5.9 m, leaving 2.4 m gaps in what should read as a
continuous support under the deck, to compensate for an overhang of zero.

Now `SUPPORT_MARGIN` (0.5 m) applies across the cell, where the end walls' own
overhang lands, and `SUPPORT_SEAM` (0.1 m) applies along it, which is there only
so two supports in a row do not share a face. A 5.0 x 7.8 platform cell draws a
3.0 x 7.6 m pier - a 1.0 m gap to the support on the next platform, a 0.2 m seam
to the one in front - with the envelope 0.50 m and 0.10 m inside the cell.

| cell | mesh | envelope | clear |
|---|---|---|---|
| 5.0 x 7.8 (platform) | 3.0 x 7.6 | 4.0 x 7.6 | 0.50 / 0.10 |
| 18.5 x 7.4 (size1 building) | 16.2 x 7.2 | 17.5 x 7.2 | 0.50 / 0.10 |
| 40.0 x 7.4 (size3 building) | 37.7 x 7.2 | 39.0 x 7.2 | 0.50 / 0.10 |

The side-wall inset is `max(t, SUPPORT_SEAM + overhang)` rather than `t`, so the
claim holds for a cell too narrow to carry a 1 m wall as well; at the sizes the
mod actually produces it is always `t`.


## Round five: the colliding modules are stock against stock

**2026-10-12.** Zeroing our own reservations did not restore removal, and the
203 `module remove` lines in that session say why: every one of them reads
`modules=18->17` and no later line ever starts from 17, so the preview runs -
our whole build runs, for every family, `via=plain` for our own supports - and
the **commit** is refused. The refusal is not about which module is under the
cursor; it is about the configuration.

The corrected diagnostic then named the pair I had been stepping over for two
rounds:

```
occupied slot overlaps: 1 at the same level, 8 across levels, out of 17 modules;
  cross: 7400000 rail/passenger_platform (0.0,0.0,12.0) 5.0x39.0
     vs 20010000 street/street_terminal_passenger (15.0,0.0,0.0) 10.0x10.0 dz=12.0
```

A **rail** platform at +12 against a **street** bus platform at grade. Stock
against stock, eight such pairs, and nothing to do with supports: it is two
decks stacked 12 m apart, which is the entire point of the mod, seen by a check
that has no height in it. The support correlation was a coincidence of when the
modules got placed - no module removal has ever committed in this construction,
in any session we have a log for.

So `clearReservations` takes the reserved ground off the rail level's
**occupied** slots, leaving every empty slot exactly as stock made it (the check
is over modules, so an empty slot cannot be half of a colliding pair - and
whatever else the engine does with `spacing`, it keeps doing it wherever a module
can still be added).

Why this is cheaper than it sounds:

- `spacing` is **write-only** from Lua. Nothing in `rail.zip` or `street.zip`
  reads it back - the only matches are the four `addSlot` writers and stock's
  own `{0,0,0,0}` - so no stock code can notice;
- the protection it buys was already given up here. `skipCollisionCheck` on
  every slot type is what makes placement possible at all in a two-level
  construction, and that already stops the builder refusing an overlapping
  module. The bulldozer's veto is the only consumer left;
- it does not touch terrain alignment, the placement check against the world
  (geometry, not reservations), or street's own slots.

The diagnostic now reports the number that matters - how many overlapping pairs
**still reserve ground on both sides**, which is what a flat check can see - and
warns only on that. The geometric overlaps stay in the line, because what the
modules occupy is still worth knowing; `slotBox` reads the pre-zeroing
reservation through a snapshot so the two numbers can differ honestly.

If removal still fails with `0 of those still reserve ground on both sides`,
then the check is not reading slot reservations at all and the next suspect is
module **geometry**: our support models are emitted through `addModel`, which
tags them `__module_<slotId>`, and a 2D contour of a brick box 12 m tall sits
directly under the deck's own contour. The test for that is to emit the same
models untagged, as construction geometry rather than module geometry, and see
whether the refusal goes with them.


## Round six: the concourse is the offender, and the log proves it is not the supports

**2026-10-12, 15:52 session.** Two facts from the same log kill three rounds of
theory:

- **`support=0` on every `built:` line.** Not one support module was placed in
  that session, and removal was refused anyway. Supports are out.
- **Every `module remove` line reads `modules=12->11`.** 278 previews, nothing
  committed, and `0 of those still reserve ground on both sides` on every
  rebuild - so `clearReservations` did its job and the refusal is not about
  reserved ground either.

What the player reports is sharper than anything the log can show: *every module
is refused except the concourse*. That is the signature of a configuration-level
veto, not a per-module one. The engine refuses while the configuration is
invalid and allows exactly the removal that makes it valid again - which means
the concourse is the thing making it invalid.

It also fits the regression window, which is the player's own observation: this
worked before the station buildings came out of the seed and the concourse went
in, and that is the whole of the uncommitted diff apart from support art and
diagnostics.

The preview timeline, reconstructed from the log, adds one mechanism that was
invisible until now:

```
rm slot=20015503 street (the entrance) -> built: street=2 concourse=1, 0 concourse slots
rm slot=20010000 street (bus platform) -> built: street=1  (street cascades to the entrance)
```

The concourse slot is **derived from the entrance slot**, so removing the
entrance - or the bus platform, which takes the entrance with it in street's own
code - deletes the slot out from under a module that is still in
`params.modules`. A module with no slot is one of the few things the engine can
call invalid outright. That explains the street half on its own, and
`logOrphanModules` now reports it for every family rather than only for
supports.

It does **not** explain the rail half, where the concourse slot survives the
preview. So the test is a controlled A/B, and the first half of it is the state
that used to work:

1. the concourse is no longer seeded - place a station and try to delete a
   platform. If that works, the concourse is the cause;
2. then place a concourse and try again. If it breaks, it is the concourse
   itself and not the fact that it was *seeded*; if it keeps working, seeding
   was the half that mattered - and seeded modules have a known asymmetry
   behind them (root `NOTES.md`, "A seeded module's geometry is checked against
   the world at placement");
3. if even step 1 fails, the cause is the other half of the window - no station
   building on either level - and seeding one again is the next move.

Unseeding is defensible on its own terms, which is why it is the change rather
than a temporary hack: it is the third time this mod has concluded that nothing
automatic can know what the player means a station to be - supports and the
viaduct were the first two - and a fresh station falls back to a default
catchment with a line in the log.


## Round seven: the platforms came back, and the tracks were the bill for it

> **Confirmed in game, 2026-10-12.** Tracks and platforms both delete; both can
> be re-added and deleted again. The whole arc that started with "a support can
> be placed and not removed" is closed, and the supports were never in it.

**2026-10-12, 19:43 session.** Unseeding the concourse worked: platforms are
removable again. Round six's A/B answered step 1 in the affirmative on the first
try, and the log shows the removals committing - `modules=11->10` once, then the
next preview starting from 10, which is what a commit looks like from Lua.

Then: *"I can delete the platforms but I can't delete the tracks."*

The log says this is **not** the same failure. Every slot id that appears in a
`module remove` line in the whole session is a platform or a street module:

```
41 module remove slot=7399990     21 module remove slot=7400000
36 module remove slot=7400010     17 module remove slot=7400020
27 module remove slot=20010000     7 module remove slot=20210000
```

Slot ids are `base + 1000*i + 10*j` (`modular_station.script.lua:531`) with
`passengerPlatformSlotId = 7400000` and `trackSlotId = 8400000`, so those four
are the platform row at `j = -1..2` and **not one track slot id appears at all**.
A refusal previews and then does not commit; this never previewed. The engine
never built a candidate configuration, which means it never found a slot under
the cursor. A miss, not a veto - and the two are only distinguishable from the
log, because in the game they look identical.

What makes a track different from a platform is that a track module has
**nothing to click**. `trackmodule.script.lua` emits one model,
`tn_underground_connection.mdl`, and that file is `collider = { type = "NONE" }`
with no mesh under its `RootNode` and a bounding box from z -5 to -1: it is the
person-network provider for the subway under the rails. The rails themselves are
**edges**, and an edge carries no `__module_<slotId>` tag. So the only thing
that can identify a track slot is its reserved rectangle - which round four
zeroed, on every occupied rail slot, including the tracks.

One cause, and it predicts the asymmetry exactly: a platform has a real mesh
with a real collider and never needed the rectangle.

It also settles the question round four left open, in the uncomfortable
direction: zeroing the reservations was never shown to help. It was in place for
the whole of rounds five and six while nothing could be removed, and the thing
that fixed removal was the concourse. `spacing` is still write-only from *Lua* -
no stock script reads it - but the engine reads it for at least two purposes,
and we traded one of them away for a guess about the other.

### Clip, do not zero

`trimReservations` replaces `clearReservations`. For each **occupied** rail
slot, it clips the rectangle until it no longer overlaps an occupied slot on the
other level, instead of discarding it:

- four candidate cuts per obstacle - one per side - and the cheapest by lost
  area wins;
- a cut must leave at least `RESERVATION_MIN = 1.0` m across, and must keep the
  slot's **own origin inside** the rectangle. `spacing` is four distances
  measured from that origin, so a rectangle that does not contain it cannot be
  written back: the four distances would describe a larger rectangle, inflating
  straight back over the obstacle. When no cut qualifies the slot is zeroed, and
  the log says so with a warning;
- the write-back is exact only while the slot's axes are at a right angle to the
  construction's. `RAIL_XF` is a 90 degree `rotZ`, so they are, and the code
  checks it rather than assuming it.

On the four-tile test station this costs almost nothing. Six of the eight
occupied rail slots do not overlap the street level at all and keep their full
5 x 39 m; the platform and the track at `j = 0` overlap the bus platform
(10 x 10 at `(15,0,0)`) and come back as 5 x 29.5 m, clipped at `x = 10` where
the bus station starts. Verified offline against the logged geometry: the
round-trip through `spacing` is exact to 1e-9 and nothing overlaps afterwards.

`logSlotOverlaps` had to change with it. Its `reserved` count used to be "both
sides still reserve ground", which was a yes/no per slot; a clipped slot still
reserves ground, just less of it, so the count is now taken from a **second**
set of boxes built from the live `spacing` rather than from the pre-trim
snapshot. The line now reads `N pair(s) of reserved rectangles still overlap
after trimming, out of M that reserve any`, and the geometry half of the line -
`same` and `cross` - still reports what the modules *occupy*, which is the honest
number for a mod whose entire point is two decks 12 m apart.

## Open questions

- ~~Does zeroing the slot reservations restore module removal?~~ **No -
  answered 2026-10-12.** It was in place throughout rounds five and six while
  nothing could be removed, and what restored removal was unseeding the
  concourse. Zeroing then cost the tracks their only pickable geometry, so it is
  now a clip rather than a wipe. See "Round seven". What is still **unknown** is
  whether a cross-level reservation overlap vetoes a removal *at all*; the next
  build no longer has one to find out with, so answering it would mean putting
  one back deliberately.
- **Does the bulldozer's flat check look at module *geometry* as well as slot
  reservations?** Nothing has ruled it out, and it is the remaining suspect if a
  removal is ever refused again with no overlapping rectangle in the log. The
  test is to emit a module's models untagged, as construction geometry
  (`result.models` directly rather than through `addModel`), and see whether the
  refusal follows the tag or the geometry.
- **Should support slots be `dependentSlots` of the rail module above?** Stock
  pairs a roof slot with its platform that way, and it is the half of the idiom
  this mod does not implement: removing a platform orphans its supports instead
  of taking them with it. Appending rather than replacing matters - rail already
  uses `dependentSlots[platformId]` for the roof and addon.

- ~~Do two station records in one construction join one StationGroup?~~
  **Answered yes, 2026-10-09** - interchange works and costs nothing. See
  "Settled: the two stations **do** join one StationGroup". The follow-on
  question is narrower: why does the group report a `TRAM` carrier?
- Are the rail and street families' module/host field names really disjoint, so
  one merged result can host both? Reasoned from the scripts, not tested. See
  "Picking a transport type per level".
- Does `postConstructionModifiable` work on a construction that declares
  top-level `params`? Moot for this mod now, but it would be good to know.
- What do `slot.autoFill` and `slot.alignToTerrain` do? Unused by all shipped
  content, and `alignToTerrain = false` sounds made for off-grade slots.
- Does `optional = true` on an alignment entry mean "level if you can" or
  "ignore if it conflicts"? Affects whether level 0 can stay soft.
- Does the engine reject construction geometry at z > 0 with no support beneath
  it? The roof at 5.5 m and the main buildings say no, but no stock construction
  puts a *track* up there.
