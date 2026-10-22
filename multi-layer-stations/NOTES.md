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

> **Retired by "Round seventeen".** The measurements below are right about the
> old piece and wrong about the bulldozer: a support now deletes with its cell
> filled to 0.1 m. Kept for the collider arithmetic, which is still how a model
> is read.

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

> **Superseded by "Round seven" and "Round eight".** None of this held up.
> Extending the zero to stock's *rail* slots fixed nothing and cost the tracks
> their only pickable geometry; zeroing **our own** slots made them impossible
> to place into, because an empty slot has no geometry and the rectangle is all
> it has. Reservations are trimmed now, not wiped, and only on occupied slots.

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

> **Closed by "Round seventeen".** True of that build, not a rule: a platform
> now deletes with the concourse seeded and in the build. What made the
> configuration invalid was the reservations the concourse carried, which round
> seven clipped.

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

## Round eight: an empty slot with no reserved ground is not offered at all

**2026-10-12.** *"I can't place the concourse - there is no module slot
available."* The log had been saying `concourse slots 24x6: 820015500@(0.0,-18.0)
occupied=false` on every rebuild since the slot was written, which is exactly the
line that was put there to separate "the slot is not there" from "the slot is
there and the placement is refused". It was the third case, which that line
cannot tell apart from the second: the slot is there and **cannot be clicked**.

Same cause as the tracks, one step further. A track module has no geometry, so
an occupied track slot needs its rectangle to be picked by. An **empty** slot of
any kind has no geometry *by definition* - nothing is drawn where nothing has
been built - so its rectangle is the only thing it can ever be found by. Both
our slot kinds declared `spacing = { 0, 0, 0, 0 }`, so neither could be placed
into. That also explains a silence nobody had read as evidence: after round four
zeroed the support slots, the next two sessions logged `support=0`. No supports
were placed because none *could* be.

Stock gets away with the zero on its roof and addon slots because it pairs it
with `result.dependentSlots[platformId] = { roofId, addonId }`: the player
reaches those slots through the platform slot under them. We took the first half
of the idiom and not the second, three rounds ago, on the reasoning that the
reservation was what made the station un-bulldozable - which it was not.

So our slots carry their real cell again - `width x cellD` for a support,
`CONCOURSE_W x CONCOURSE_D` for a concourse - and the collision argument that
the zero was for is handled where it actually applies. The engine's check is
over **modules**, so it can only see a slot that is occupied, and an occupied
slot is one whose module is standing there to be clicked. `trimReservations`
therefore runs in two passes, in priority order:

| pass | trims | clear of | levels |
| --- | --- | --- | --- |
| 1 | rail slots | occupied street slots | across levels only |
| 2 | our slots | occupied street **and** rail slots | any level |

Street is never trimmed; it is at grade, it is stock, and it was there first.
Rail yields only across levels, because two decks 12 m apart overlap by design
and two things at grade do not - trimming a same-level overlap away would hide a
real bug. Ours yield at any level, because every overlap they have is deliberate:
a support stands under the deck it holds up, and a concourse spans the entrance
road. Ours are not trimmed against each other; support cells touch exactly at
their pitch, which is not an overlap, and a concourse fouling a support is a
layout question that should stay visible in the diagnostic.

Checked offline against the logged geometry, in the same frame the engine sees:

| slot | before | after |
| --- | --- | --- |
| rail platform / track, clear of the bus station | 5.0 x 39.0 | untouched |
| rail platform / track over the bus platform | 5.0 x 39.0 | 5.0 x 29.5, cut at the bus station's edge |
| occupied support under the deck | 5.0 x 7.8 | zeroed - no cut leaves a rectangle, and its brickwork is what the cursor finds |
| occupied support clear of everything | 5.0 x 7.8 | untouched |
| occupied concourse across the entrance tile | 24.0 x 6.0 | zeroed, same reason |
| **any empty slot** | - | **untouched, always** |

The last row is the whole point. `trimReservations` only ever looks at occupied
slots, so every slot a player still has to click keeps the rectangle stock gave
it, or the one we gave it.

### A sharper test than any of this

`tools/luacheck.py` had been running with `PARAMS_RE` broken since it was
written: the pattern started with a literal `\x08` instead of `\b`, a backslash
eaten on the way into the file (see root `NOTES.md` on writing text through a
heredoc). The practical effect is that **no function parameter has ever counted
as defined**, so every call to a callback's own argument read as a missing
local. It went unnoticed because the known cases were hard-listed in
`GAME_GLOBALS` with a comment saying `PARAMS_RE` was meant to cover them.
Repaired, and both mods check clean.

## Round nine: a slot standing on occupied ground cannot be clicked

**Measured 2026-10-13.** *"I can place the concourse next to the bus station
entrance, but not over the bus station entrance itself."* Two concourse slots
were in the build, identical in every way that a slot can be - the same cell,
the same `spacing`, the same type with the same `skipCollisionCheck`, the same
`replaceable`, consecutive ids, the same module - and differing only in **where
they are**: the real one on the entrance, the probe 30 m along the entrance's
own x, out in the open. The log settles it in two lines:

```
concourse slots 24x6: 820015500@(0.0,-18.0) occupied=false, 820015501@(30.0,-18.0) occupied=true
module add slot=820015501 family=ours via=plain modules=11->12 name=multi_layer_stations_1::/ml_concourse.module
```

Four adds on the probe, forty-one removes, and **not one** on the real slot in
the same session. So nothing about the slot, the module, its desc or its id was
ever the problem. The engine resolves a cursor position to a single slot, and
where an occupied slot already claims that ground at that height, it wins; ours
is then unreachable however well formed it is. `logBuriedSlots` names the pair
on every rebuild:

```
our slots with an occupied stock slot over the same ground: 2 of 42;
  674000001 ml_support at (15.6,-0.0) under 20010000 street_terminal_passenger;
  820015500 ml_concourse at (0.0,-18.0) under 20015503 street_terminal_entrance_exit
```

This is the other half of round eight. An empty slot has only its rectangle to
be found by - and a rectangle is not enough if something occupied is standing on
it.

### The entrance's own rectangle is wider than the concourse

All three entrance variants are emitted at **one** transform
(`modular_terminal.script.lua:2596-2617`), and the `large_building` slot at that
same transform is wider still:

| slot at the entrance transform | `spacing` | reaches |
| --- | --- | --- |
| `street_terminal_entrance_exit` | `{8, 8, 15, 0}` | x -8 .. 8, y -15 .. 0 |
| `street_terminal_entrance` | `{3, 8, 15, 0}` | x -3 .. 8 |
| `street_terminal_exit` | `{8, 3, 15, 0}` | x -8 .. 3 |
| `street_terminal_large_buildings` | `{10, 10, 20, 0}` | x -10 .. 10, y -20 .. 0 |

The union reaches x = +-10 and 15 m back along y, while the concourse cell is
24 m x 6 m centred on the same point - so every part of it within x +-10 is
claimed, and the only clear ground it has is the two bands x = 10 .. 12 and
-12 .. -10, out at its piers. Moving the cell off the entrance is not an option:
spanning that road is what a concourse *is*.

### So move the origin, not the cell

`spacing` is four distances from the slot's **origin**, not a half-extent, so
the origin does not have to be in the middle of its own cell.
`CONCOURSE_PICK_X = 11` puts it out on the flank, in the middle of the clear
band, and `concourseSpacing` gives back `{23, 1, 3, 3}` - the same 24 x 6 m
rectangle, in the same place, measured from somewhere else.

Two things follow from that and both are in the code:

- `addModel` draws a module's models relative to the slot's origin, so the art
  has to come back the other way. `concourseModels` takes the cell centre as
  `cx` and is called with `-CONCOURSE_PICK_X` from both the `updateFn` and the
  preview's `getModelsFn`.
- the catchment circle is positioned from the slot, which is now 11 m off the
  entrance it serves. `applyConcourse` corrects it through the slot's own
  frame, so a rotated entrance stays right.

A side effect worth having: an **occupied** concourse used to be zeroed by
`trimReservations`, because no single cut clear of the entrance left a rectangle
containing the old centre origin. From the flank, the cut to x = 8 keeps it, so
the placed concourse keeps a 4 m strip to be picked by instead of nothing.

The probe stays for one more round, as the control that says whether a build
reached the game at all - and because it is holding a module in the test save.

**The fix in this section does not work, and the measurement in it still
stands.** Moving the origin to the flank changed nothing in the game; see round
ten, which keeps the finding and throws the offset away.

## Round ten: a click resolves to what is standing there, not to a rectangle

**Measured 2026-10-13, same day, second run.** The pick origin was out on the
flank - the pip had visibly moved in the game, and the diagnostic agreed
(`our slots with an occupied stock slot over the same ground: 1 of 42`, the
concourse no longer among them). The slot was **still** never offered. In 2915
lines of log:

- 14 `module add slot=820015501` lines on the probe, 18 removes;
- not one `module add slot=820015500` on the real slot;
- no `Invalid configuration`, no `construction not possible`, nothing from the
  engine at all.

That last point is what makes this a resolution failure and not a refusal.
`preProcessFn` logs **every** proposed change, and a refusal is a proposal that
does not commit - we have seen plenty of those. Here nothing was ever proposed.

So round nine's measurement holds and its reading was half wrong. Position
decides, but a reserved rectangle is not how a click finds a slot: there was
ground inside our cell that no stock slot reserved, the origin was moved onto
it, and it made no difference. What the cursor lands on over the entrance is
the entrance **module** - its geometry, its pavement - and that is what the
click resolves to. An empty slot's rectangle only works where nothing is
standing, which is exactly the probe's situation and exactly not ours.

### Stock has an idiom for this, and it is the half round eight left out

Round eight read the rail station's roof and addon slots and took one half of
what they do: a slot stacked on an occupied one. The other half is one line:

```lua
result.dependentSlots[platformSlotId] = { roofSlotId, addonSlotId }
```

(`modular_station.script.lua:567-612`). Those two slots have
`spacing = {0, 0, 0, 0}`, so by round eight's own finding they cannot be
clicked - and roofs are placeable in the stock game. The platform's click is
the route, and `dependentSlots` is what names it.

The exe backs that up. Strings in `TransportFever3.exe`, build 40408:

| string | what it says |
| --- | --- |
| `ConstructionSlot` + `replaceable`, `autoFill`, `spacing` | the slot fields the engine reads from Lua - and `autoFill` is one we do not use |
| `ConstructionSlotConfig` + `skipCollisionCheck`, `maxModules` | `slotConfig`, which stock also gives a `message` and `maxModules = -1` |
| `dependentSlots`, next to `tag2modelInstance` and `subconstructions` | **a field of the `Construction` component**, not a Lua convention: the engine reads it and the savegame keeps it |
| `UI::ModuleBuilder::MousePressed`, `::RecheckCollisions`, `modules_util::Collision` | the click path and the collision path are different code, which is why a collision message never appeared |

`tag2modelInstance` sitting beside it is the shape of the mechanism: modules
are drawn with a tag, the tag maps back to the module, and a click on a model
instance is a click on the slot that drew it. Empty slots have no instance, so
they fall back to their rectangle - and lose wherever a filled slot's geometry
is in the way.

### `dependSlot`, used twice

- **The concourse, keyed on its entrance.** Declared from intent, not geometry:
  the concourse slot is derived from that entrance slot, so that is its parent,
  per occupied entrance variant.
- **Anything of ours standing on occupied stock ground**, keyed on the slot it
  stands in. `logBuriedSlots` became `dependOnOccupiedGround`: the diagnostic
  that was written to report the problem now routes what it finds, which is how
  the buried support gets a way in without hard-coding anything about bus
  platforms.

The origin offset came out again, so the concourse cell is centred on its
entrance and the art and the pip agree. A new log line prints the
`dependentSlots` table as the engine will get it, ours named - because
`shareLists` hands the merged result **rail's own** table, and a write that
landed in a copy instead would look exactly like the dependency not being the
mechanism.

### The support confirms the rule, a second time

Round nine predicted that the one support standing on the bus platform's ground
could not be placed while its neighbours could. The log says yes, without
anyone having to aim at it:

```
module add slot=673999902 / 673999903 / 673999905 / 674000003 / 674000005 ...
```

- and never `674000001`, the buried one, which is `k = 1` of the same tiled row
as `674000003` and `674000005`. Two families, two positions, one rule.

### It did not work either, and the log says the dependency was not the reason

The entries reached the engine - that is what the new log line was for:

```
dependent slots: 6 parent(s), 2 of them pointing at a slot of ours;
  20015503 -> 820015500, 20010000 -> 674000001
```

Six parents, so rail's own platform pairs are in there too and the table is the
one the engine gets. And still: no `module add slot=820015500`, no
`module add slot=674000001`, in a session where five other support cells and
the probe took modules. So `dependentSlots` is not a way *in* to a slot that is
otherwise excluded - whatever it does for stock's roofs, it does not do it here.
See round eleven, which has the measurement that explains why none of this could
have worked.

## Round eleven: there is no pip, so the slot is excluded before any click

**2026-10-13, third run, and this is the measurement that should have come
first.** *"I still only see a single blue slot pip and it is to the side of the
entrance road."*

One pip, 30 m along the station front: the probe. The slot on the entrance has
**no pip at all** - and re-reading round nine, it never had one. What moved
there was the probe's pip, which the offset shifted by the same 11 m, and the
report of "the pip was translated" was taken as evidence about the real slot.
It was not. Three rounds of aiming at a pip that was never drawn.

A missing pip is a different fact from a click that misses. It means the engine
does not have the slot in its candidate set for that module at all, so nothing
about cursors, geometry, rays, `tag2modelInstance` or `dependentSlots` can be
the explanation - all of those happen after a slot is a candidate. The filter
runs earlier.

### What the excluded slots have in common

Two slots of ours have now never taken a module, in three sessions, across two
families:

| slot | where | reserves | pip |
| --- | --- | --- | --- |
| `820015500` concourse | on the street entrance | 24 x 6 m, overlapping the entrance's `{8,8,15,0}` | none |
| `674000001` support | under the bus platform | 5 x 7.8 m, overlapping `street_terminal_passenger` | none seen |
| `820015501` probe | 30 m out in the open | 24 x 6 m, overlapping nothing | yes, and 23 modules placed in it |
| 40 other supports | clear of the bus station | 5 x 7.8 m, overlapping nothing | yes, placeable |

The common property is not height, not type, not id, not `slotConfig`, not the
module - all of those are shared with slots that work. It is that **the
reservation overlaps an occupied stock slot's reservation**. Every slot of ours
whose rectangle is clear works; both whose rectangle is not are excluded.

That also re-reads round eight correctly. Its conclusion was "an empty slot with
no reserved ground is not offered at all", measured by zeroing every slot - and
that is still true, but it is one end of a single rule, not a separate fact:

> the engine offers an empty slot where its reservation holds ground that no
> occupied slot is holding. No reservation is one way to fail that; a
> reservation entirely inside somebody else's is another.

### The two readings, and both are in the build

What is **not** settled is whether the overlap disqualifies the slot outright or
whether stock simply never does this - its stacked slots reserve nothing and are
listed in `dependentSlots`, and ours reserved ground *and* overlapped. So one
slot each:

| slot | shape | what its success would mean |
| --- | --- | --- |
| `820015500`, the real one | `spacing = {0,0,0,0}` + `dependentSlots[entrance]` | stock's idiom is the answer, both halves, and the entrance is the thing to click |
| `820015501`, the probe, moved onto the entrance's flank | a 2 m x 6 m band at x = 10 .. 12, overlapping no stock reservation, no dependency | the reservation is a filter, and a clear rectangle is all it ever needed |

The two cannot interfere, because the real slot now claims no ground for the
probe's band to compete with, and the `concourse slots` log line prints each
slot's reservation next to its position so the shapes are readable from the log
alone.

Worth noting what the zero also buys, whichever way the experiment falls: it is
what round four wanted. The flat module-collision check is over reservations, so
a concourse that reserves nothing cannot be half of a colliding pair, and
`trimReservations` has nothing to clip for it - the `occupied()` guard already
skips a zero.

## Round twelve: answered. A slot needs a reservation on ground nobody occupies

**2026-10-13, fourth session, and this is the rule.** Both shapes were offered
side by side at the same entrance, and the log is one line:

```
concourse slots 24x6: 820015500@(0.0,-18.0) reserves 0x0 occupied=false,
                      820015501@(11.0,-18.0) reserves 2x6 occupied=true
module add slot=820015501   (x4)
```

The 2 m band took the module. The zero reservation with a `dependentSlots` entry
under its entrance - stock's own idiom for a stacked slot - was never offered at
all. So:

> **The engine offers an empty slot only where its reservation holds ground
> that no occupied slot is holding.** Nothing else substitutes for that: not
> `skipCollisionCheck`, not `replaceable`, not moving the origin onto clear
> ground while the rectangle still overlaps, not being listed in
> `dependentSlots` of the slot that is standing there.

Four sessions of evidence, every combination tried once:

| reservation | origin | dependency | offered |
| --- | --- | --- | --- |
| 24 x 6 m, overlapping the entrance | centred | no | **no pip** |
| 24 x 6 m, overlapping the entrance | on clear ground, x = 11 | no | **no pip** |
| 24 x 6 m, overlapping the entrance | centred | yes | **no pip** |
| none | centred | yes | **no pip** |
| 2 x 6 m on clear ground, x = 10 .. 12 | x = 11 | no | **yes - 4 modules** |

That also puts round eight's finding in its place. "An empty slot with no
reserved ground is not offered" is not a separate fact about zero; it is the
degenerate case of this rule, and the whole of rounds nine to eleven was spent
looking for a way round a rule that does not have one.

### What the mod does now

One concourse slot per entrance, at `CONCOURSE_FLANK` = 11 m along the
entrance's local x, reserving the 2 m x 6 m band from x = 10 to 12 - inside our
own cell, and clear of every rectangle stock puts at that transform: the three
entrance variants at x = +-8 and `large_building` at +-10.

Two compensations come with that, and neither is cosmetic:

- `concourseModels` is handed `cx = -CONCOURSE_FLANK`, so the piers still
  straddle the road 11 m away from the slot's origin. The probe showed what the
  alternative looks like: *"the mesh is not positioned over the entrance road,
  but one side of it collides with it"* - a pier in the carriageway;
- `applyConcourse` reads the catchment position back through the slot's own
  frame, so the circle sits over the entrance and not out at the pier. Through
  the frame rather than in world x, so a rotated entrance comes out right.

The probe is gone - four sessions, and the question it was built for is
answered. The `dependentSlots` entry stays, demoted to what it is: the removal
cascade, so a concourse goes with its entrance rather than being orphaned and
dropped with a warning.

### The price, and the one slot still unreachable

A 2 m x 6 m target at one pier instead of the 24 m span, with the pip there
rather than in the middle of the concourse. That is the rule's price and there
is no way to pay less of it at this position - every other part of our cell is
inside the entrance's own rectangle.

The one support cell standing in the bus platform (`674000001` at (15.6, 0))
cannot be fixed the same way: its cell is in the **middle** of the platform's
rectangle, not at its edge, so there is no clear band to retreat to. Two honest
options, neither taken yet:

1. stop offering it - do not create a support slot whose reservation is inside
   an occupied stock slot's. Cheap and truthful, and it removes a pip that
   never worked. The risk is the reverse case: a player who removes the bus
   platform, places a support there, and puts the platform back would have the
   slot vanish under a module that is already in it;
2. leave it. It is a support **under a bus platform** - invisible, and
   structurally pointless, since the platform is not what the deck rests on.

Option 2 is what the build does, and `dependOnOccupiedGround` reports the count
on every rebuild so it cannot quietly grow.

## Round thirteen: the same rule, from the other side, in stock's slots

**Reported 2026-10-13, with the concourse finally working.** *"I can place
platforms and tracks over the bus station. If I extend them too far so the
track is above the concourse mesh, I can't delete the track, even if I have
deleted the concourse. When hovering over the track with the module delete
tool, the track doesn't light up in yellow."*

No highlight is the same symptom as no pip, and it has the same cause - only
this time it is a **stock** slot that has no rectangle, and we are the ones who
took it away. The log of that session:

```
cross: 8395000 rail/track (-0.0,-25.0,12.0) 5.0x39.0
    vs 20015503 street/street_terminal_entrance_exit (0.0,-22.5,0.0) 16.0x15.0 dz=12.0
trimmed the reserved ground: ... 2 zeroed because no single cut would do
```

The entrance reserves 16 x 15 m; a track column is 5 m wide and 39 m long. So
the entrance spans the **entire width** of the track's rectangle - no cut in x
leaves anything - and a cut in y would have to drop the slot's own origin at
y = -25, which is inside the entrance's -30 .. -15. `spacing` is four distances
from the origin, so a rectangle that does not contain the origin cannot be
written back at all: `trimReservations` zeroes the slot, and a track module has
nothing else to be found by, because it draws one invisible model with no
collider (root NOTES.md).

**The concourse was never involved**, which is exactly why deleting it did not
help. The obstacle is the street entrance's own reservation, and the concourse
merely stands on the same ground.

### The fix is round twelve's rule applied to stock's slots

A slot that cannot hold a rectangle must not be offered.
`dropUnreservableRailSlots` asks the clip question *before* a module is in the
slot - the test is factored out of `trimReservations` as `clipAgainstAll` so the
two cannot disagree - and takes the **empty** ones out of `result.slots` before
the engine sees them. The deck now stops one tile short of the entrance rather
than extending into a tile whose module could never be removed again, and the
count is logged every rebuild:

```
rail slots not offered, because no reservation of theirs would survive the
level below: N. A module there could never be removed again.
```

**Empty only, on purpose.** Dropping an occupied slot orphans its module, and
an orphan is one of the few configurations the engine can call invalid outright
- which would turn "one module I cannot delete" into "a construction I cannot
edit". The guard is about not getting there; it cannot clean up after the fact.

### Recovering a module that is already stuck

Without bulldozing the station: **remove the street entrance module.** That is
the obstacle, it is removable (`module remove slot=20015503 family=street`
appears throughout the logs), and with it gone nothing fouls the track column -
`trimReservations` leaves it its full 39 m, the track highlights, and it can be
deleted. Then place the entrance again. The concourse slot comes back with it.

### What it costs, and the one way out of that

The deck cannot be extended over the entrance strip at all - not even as a
platform, because platform and track share a transform and a rectangle, so both
go. Fifteen metres of the station's own frontage is out of reach, and the
concourse is what crosses the road there instead. For this mod that is close to
the intended shape anyway, so it is a cheap price.

The one thing that would lift it is **negative `spacing`**, which has never been
tried: if the engine reads `{left, right, back, front}` as plain offsets rather
than as distances, then `{19.5, -5, 2.5, 2.5}` describes the part of the track
column *south* of the entrance - a rectangle that does not contain the slot's
origin, which is the one shape the clip cannot express today. Untested, and the
notes' claim that such a rectangle "cannot be written back" is an assumption
about sign, not a measurement.

## Round fourteen: the placeholders fill their cells, and what the inset was for

**2026-10-13, on request:** *"Can you please modify the meshes so they fully
occupy the space they use? They are placeholder content, so showing their full
extent is useful for modders."*

A 5 m platform cell was drawing 3.0 m of brickwork - 61% of it - and the missing
2 m was two insets stacked on each other:

| inset | what it bought |
| --- | --- |
| `SUPPORT_MARGIN`, 0.5 m a side | half a metre of clear ground, measured against the collider envelope |
| the collider allowance in `fitSpan` | the brick's own overhang, `0.158 x tile`, which is 0.70 m at a full tile |

The margin went. It was round three's answer to "a support can be placed and not
removed", and rounds four to six removed nothing while it was in place; round
seven fixed removal by clipping the **reservations**. So it was buying off a
cause that was never demonstrated, at 1 m of every cell.

The allowance stayed, because *that* is measured - `stone_abut_rep_rep.mdl`'s
collider really does reach 0.70 m past its mesh at a full tile - and because the
drawn-vs-cell figure in the log is only worth having if the geometry is supposed
to stay inside the cell. Instead the **tile** got shorter, which is the lever
that was there all along: the overhang is a fraction of the tile, so the same
span laid in three pieces gives away a third as much.

```
cap        5.0 m cell   7.8 m cell   24 m cell
4.43 m     73%          84%          94%     (the brick's own length)
2.00 m     87%          90%          97%     (SUPPORT_TILE)
```

Flush was tried on paper first and rejected on the arithmetic: a mesh on the
cell outline puts 0.28 m of collider into the neighbour on a 5 m cell and 0.36 m
past the concourse's own kerb-facing edge - and that second one is the exact
failure the concourse was refused for once already. 87% with the envelope inside
the cell is worth more than 96% with it outside.

The concourse also got the thing that actually shows its extent: **a deck slab
across the whole footprint** at the top of the structure (`CONCOURSE_DECK`),
with the piers carrying it. Filling the footprint at *grade* was never an option
- the 16 m entrance road runs through the middle of this cell - and a slab at
the top is what a concourse is anyway. `brickWall` takes a `z0 .. z1` band for
it, scaling the courses to land exactly on the top rather than overshooting it.

What the cells draw now, envelope included, against the cell they have to fit
in:

| cell | mesh | envelope | cell |
| --- | --- | --- | --- |
| support, platform span | 4.34 x 7.60 | 4.80 x 7.60 | 5.0 x 7.8 |
| concourse | 23.19 x 5.25 piers + slab | 23.80 x 5.80 | 24 x 6 |

### And then: filling the cell is not the same as being solid

Second report, same day: *"The meshes look slightly better, but they still
don't look like a fully fleshed out mesh. I see parallel faces that suggest the
total shape of the envelope, not a full solid shape."*

Which is the hollow box seen from outside. A support was four 1 m walls on the
cell outline, so what a modder reads off it is two wall faces with a void
between them - and from that you cannot tell whether the real art has 1 m to
work in or 5. Widening the walls' *outline* to 87% of the cell did nothing
about that, because the outline was never the problem.

So the volume is filled. `brickFill` is `brickWall` repeated across the depth,
and the two aesthetic arguments that produced the hollow box - "12 m of masonry
reads as a block rather than a support" and "the inside of a closed box cannot
be seen" - are arguments about a stand-in, which is exactly what should lose to
being readable.

One wall already fills its own thickness, because the piece is *scaled* to it:
a wall 7.6 m thick is 7.6 m of masonry, not two faces. What it is not is in
proportion - stretched five times its own depth the brick smears - so the depth
is laid in `SUPPORT_TILE` slices, each a wall in its own right. Nothing is added
to the envelope by that: a wall's collider overhangs the direction it **runs**,
not its thickness, so slicing the depth is free and only `x` pays the
allowance, once.

| | mesh | collider reach | half-cell | models |
| --- | --- | --- | --- | --- |
| support, platform span 5.0 x 7.8 | 4.34 x 7.60 solid | 2.40 | 2.50 | 144 |
| support, building span 15.0 x 7.8 | 14.24 x 7.60 solid | 7.40 | 7.50 | 384 |
| concourse deck 24 x 6 | 23.19 x 5.25 x 6 solid | 11.90 | 12.00 | 216 |
| concourse piers | 1.0 x 5.25 x 6 each | flush | - | 36 |

The support came out at the **same** 144 models as the four walls it replaced,
which is worth recording because the intuition is the other way round: four
walls each paid for their own tiling and for the twin that finishes them, and
drew every corner twice.

The concourse's deck went from 2 m to **6 m** deep (`CONCOURSE_DECK = PITCH *
0.5`) for the same reason - a 2 m slab on two piers reads as a lid on legs - and
it still leaves 6 m of headroom over the road underneath, more than the stock
street templates ask for. Filling the footprint at *grade* is still not
available: the 16 m entrance road runs through the middle of that cell, and the
piers at x = +-12 are what clear it.

### Third report, and the piece was two planes all along

*"The meshes still are composed of stacks of polygons, all in the same plane.
The volume is correct."*

The volume was correct. The piece was not. `tools/meshfaces.py` reads a model's
vertex buffer instead of believing its `boundingInfo`, and the answer took one
command:

| model | declared box | mesh box | faces | triangles |
| --- | --- | --- | --- | --- |
| `stone_abut_rep_rep.mdl` | 4.43 x 4.00 x 2.00 | 3.43 x 4.00 x 2.00 | **2** | **4** |

Four triangles across two faces: the piece is a **pair of parallel planes**, the
two sides of a box with nothing between or around them. That is all a bridge
ever needed of it, since the rest is buried in the abutment. Every version of
the supports - four walls, wider walls, a filled volume - was therefore an
envelope made of flat faces, and the three rounds spent on insets, tile sizes
and fill patterns could not have fixed it. The `boundingInfo` is not the
geometry and neither is the collider: here the collider *is* the geometry, which
is why `drawn` in the log was right every time while the art was wrong.

The stock library has no neutral solid block to swap in. It has closed boxes
whose collider is three times their mesh (`placeholders/unit_cube.mdl`), and
exact closed boxes that are plywood piles and advertising hoardings. So
`support_block.mdl` is assembled from the two halves that are right: the game's
own unit cube mesh - 8 vertices, 12 triangles, all six faces - and the stone
abutment's material, both by absolute path, which stock models use freely (695
absolute mesh references and 8354 material references across the shipped
`.mdl`s). Its collider is declared as exactly its mesh.

That one property deletes most of the geometry code. A box is now one instance:
scale by its size, translate to its centre. No tiling, no twin copy turned 180
degrees, no overhang allowance - so `tileCount`, `fitSpan`, `SUPPORT_TILE`,
`SUPPORT_BRICK_*` and `brickWall` all went, 132 lines of them, and the only
inset left is `SUPPORT_SEAM`.

| | before | now |
| --- | --- | --- |
| support, 5.0 x 7.8 cell | 4.34 x 7.60 of flat faces, 144 models | 4.80 x 7.60 solid, **6 models** |
| concourse | 23.19 x 5.25 + piers, 252 models | 23.80 x 5.80 solid, **9 models** |
| inset per side | seam + collider allowance | seam, 0.1 m |

The one thing that can still go wrong is the thing that has never been tried
here: **this is the first resource the mod ships rather than borrows**, and an
id the engine cannot find draws a missing-model cube or nothing at all, with no
complaint in the log. So `checkBlock` asks `api.res.modelRep.find` once per
session and logs the answer, including "could not ask" if that API is not
reachable from the module thread. The id is `multi_layer_stations_1::/support_block.mdl`,
the same shape the modules use, and `_content.json` lists the file.

### A forward reference compiles and then reads nil

Moving the constants around for this put `SUPPORT_TILE`'s declaration 75 lines
*below* the `brickWall` that reads it. A Lua local is only an upvalue for code
below it, so that reads a nil global - `tileCount(length, nil)` - on the first
rebuild, in the game, after a deploy and a restart. `tools/luacheck.py` could
not see it: it checked whether a name is a local in the file, not whether it is
one *yet*.

It does now, and it is worth having for a file this size: every definition
records the line it is declared on, and a call or a SCREAMING_CASE read above
that line is a warning. Clean on both mods, and it catches the case in a
five-line test file.

## Round fifteen: the deck lands on the concourse, and -15 m is the limit

**2026-10-13, on request:** *"Currently, there is room for 3 tracks or
platforms between the concourse and the default platform. I think it makes sense
to shift the platform by 15 meters so they align."*

Three columns of room, and the count is exact. In construction space:

- the quarter turn maps a rail-local `(x, y)` to `(-y, x)`, so a rail **column**
  - the 5 m pitch across the platforms - sits at construction `y = 5i`, and the
  40 m tiles run along construction x;
- the seed puts the platform at `i = 0` and the track at `i = 1`, because
  `TRACK_SLOT + 1000` is `1000 * i` in the rail station's id scheme. So the deck
  was at `y = 0` and `y = 5`;
- the street entrance is at `y = -15` and the concourse cell runs from there to
  `y = -21`.

Which leaves `y = -5`, `-10` and `-15` unused between them: 15 m, exactly as
reported from the game. `RAIL_SHIFT_Y = -15` closes it, and the three spare
columns move to the other side of the deck, over the bus platforms, where a
player can extend into them.

### -15 is not a round number, it is the limit

Centring the platform on the concourse would want `-18`, and lining its far edge
up with the concourse's would want `-17.5`. Both are worse than they look, and
the reason is round thirteen's rule:

| shift | platform origin | what the clip leaves it |
| --- | --- | --- |
| **-15.0** | y = -15.0 | **39.0 x 2.5 m** - cut back to the entrance's edge |
| -17.5 | y = -17.5 | zeroed |
| -18.0 | y = -18.0 | zeroed |

The entrance reserves `x = -8 .. 8` by `y = -30 .. -15`. A slot whose origin is
*inside* that rectangle cannot keep a reservation at all, because `spacing` is
four distances from the origin and no single cut leaves a rectangle containing
it - so it is zeroed, and a **track** module that loses its rectangle can never
be removed again. At `y = -15` the origin sits exactly on the boundary, which
`clipFootprint`'s epsilon treats as outside, so the column keeps a 2.5 m strip
and stays pickable.

Checked against the clip rules offline before the game saw it, with the
obstacles taken from the log:

```
seeded platform i=0  column at y= -15.0  keeps 39.0 x 2.5
seeded track i=1     column at y= -10.0  keeps 39.0 x 5.0
extend i=-1          column at y= -20.0  ZEROED -> not offered (round thirteen)
extend i=2           column at y=  -5.0  keeps 29.5 x 5.0   (clipped by the bus platform)
```

So the default station now reads as: tracks crossing the entrance road on a deck
that stands on the concourse, with the bus platforms beside it and three columns
of room to extend over them. The 15 m of frontage that cannot carry a module is
unchanged and is now *behind* the deck rather than in front of it.

### What this does not solve

Larger concourses. A 6 m cell under a 5 m column leaves the deck 0.5 m off
centre either way, and a concourse of two or three columns' depth would want the
cell sized from the pitch rather than from road clearance - which is the next
thing to try, and the reason `CONCOURSE_D`'s own note about the 16 m road is
worth reading first: it is the constraint that set 6 m, not taste.

## Round sixteen: a column is four slots, and the deck may not hop the entrance

**Measured in-game 2026-10-21**, the first session to see rounds thirteen to
fifteen. Reported: *"I can extend it towards the street and beyond, except
adjacent to the concourse. [...] However, it is possible to add a track or
platform on the other side of the concourse. I don't like this behaviour. It
should not be possible to extend the station on the side where the concourse is
built, since that will become glitchy."*

Both halves of that are round thirteen's guard being exactly as literal as it
was written to be. The log decodes the session precisely, because a rail slot
id is `base + 1000 * coordI + 10 * coordJ` and construction `y = 5 * coordI +
RAIL_SHIFT_Y`, `x = -40 * coordJ`:

| slot added | coordI, coordJ | construction (x, y) | where that is |
| --- | --- | --- | --- |
| `8402000` | 2, 0 | (0, -5) | away from the street, over the bus platforms |
| `8398990` | -1, -1 | (40, -20) | **over the entrance's column**, one tile along |
| `8399010` | -1, 1 | (-40, -20) | the same column, the other way |
| `8397990` | -2, -1 | (40, -25) | the next column in, off to one side |
| `8397000` | -3, 0 | (0, -30) | on the entrance's far edge |
| `8394000` | -6, 0 | (0, -45) | **past** the entrance entirely |

And nothing at `(0, -20)` or `(0, -25)`, which is the whole of what the guard
withheld: the two tiles directly over the entrance. That is the "except
adjacent to the concourse" in the report, and it is the guard working.

The trouble is the shape of what it protects. The entrance reserves 16 m of x
and a track tile is 40 m long, so **only the tile over the entrance loses its
rectangle**; its neighbours in the same column, 40 m away along the track, are
clear in x and keep theirs. Two columns further in, the entrance's 15 m of y is
behind you and every tile is clear again. So the deck could grow around the
road and carry on past it, with a hole in it at the one place a train actually
has to cross - and the hole is not removable, so the player cannot even fix it
by hand.

### The rule is the deck's, not the slot's

`dropUnreservableRailSlots` now runs a second pass: find the nearest **blocked
deck column** on each side of the columns that are occupied, and withhold every
empty rail slot at or past it.

- only `DECK_SLOT_TYPES` - `track`, `passenger_platform`, `cargo_platform` -
  propagate. A building or roof slot that cannot keep a rectangle says nothing
  about whether the deck can continue, and treating it as a stop would withhold
  half the deck for a size3 building slot overhanging a bus platform.
- the anchor is the occupied columns, so the two sides are independent: a
  second entrance on the other side of the station stops that side only.
- it never drops an occupied slot, for the same reason the first pass does not:
  an orphaned module is a configuration the engine can call invalid outright.
- with the deck deleted down to nothing the anchor falls back to `RAIL_SHIFT_Y`,
  the seeded platform's own column, so an empty deck still has a street side.

The new log line reports what it found and is worth reading even when it drops
nothing, because it is the only confirmation that the first pass blocks what we
think it blocks:

    deck columns blocked at y = -20.0, -25.0; rail slots not offered because the
    deck cannot reach past one: 24 (y <= -20.0). The deck ends where the
    entrance starts.

`y = none` would mean the refusal the player sees at the entrance comes from
somewhere else - the engine's own collision check, say - and that the second
pass is inert.

### The concourse is seeded again

Asked in the same session: *"Am I correct to assume that the concourse was not
added by default? If so, you may do that in the single location where I can
actually build it."* Correct - it has not been seeded since round six - and it
is now, at `CONCOURSE_SLOT_BASE + streetMangle(55, 0, 0)`, the entrance's slot
id with its variant digits cleared.

Round six unseeded it because module removal broke while a concourse was in the
build; round seven found the real cause (reservations zeroed to nothing) and
rounds nine to twelve rebuilt the slot so the concourse is picked from a clear
band at its pier. What seeding re-exposes is the engine asymmetry, not that bug:
a **seeded** module's geometry is checked against the *world* at placement,
where a player-added one is only checked against the construction. So the test
is placing the station **snapped to a road**, and what has to clear the road is
the hole in the 24 x 6 m cell rather than the cell.

The other test is removal with a concourse in the build, and this session did
not do it: the concourse went in last, at 14:05:20Z, and nothing was deleted
afterwards. Round six's symptom was exactly that, so it is the first thing to
try next time, alongside deleting a **support** - also never deleted since the
meshes were made solid, which is what round three's open question is waiting on.

### High-speed track is not obsolete, and the module list is not where you change it

Also asked: *"I don't have the high speed upgrade tool. I started the game in
2020. Is it possible the other track types are obsolete?"* No. Every track type
the player can build is `yearTo = 0`, which never expires:

| street template | `yearFrom` | menu |
| --- | --- | --- |
| `track/simple/simple` | 0 | tracks, order 3000 |
| `track/simple/simple_catenary` | 1921 | tracks |
| `track/standard/standard` | 1930 | tracks, order 3000 |
| `track/standard/standard_catenary` | 1930 | tracks |
| `track/high_speed/high_speed` | **1980** | tracks, order 5000 |
| `track/high_speed/high_speed_catenary` | 1980 | tracks |

So in 2020 all six are available. There is no separate "upgrade" tool for the
track type: it is the ordinary **track tool from the Tracks menu with the type
selected**, dragged over the station, and the engine turns that into
`upgradeFn(..., constructionConfig.streetTemplate)` - the same entry point the
catenary tool uses with `constructionConfig.catenary`. The station's own module
list cannot change it, which is why nothing in the Buildings tab looks like a
track type.

Our gate on that path matches stock exactly, which is worth recording since it
reads backwards: `isAffectedByToolFn` returns `desc.roadType == 0`, and stock's
own comment is `-- 0: "TRACK"` (`modular_station.script.lua`). So 0 is a track
and a road template is refused.

### Corrected the same day: the track tool reports a *collision*

*"Are you really sure about the high speed track type? It works that way for
modules. But I was referring to the regular track tool. If I drag a high speed
track over a regular track, I can't build it because it would collide."*

Which is a different thing entirely, and the paragraph above answers a question
nobody asked. A **collision** is the builder talking: the engine was laying new
track across the construction, not offering it an upgrade. So the open question
is not availability, it is whether the track tool ever routes the drag to this
construction's `isAffectedByToolFn` at all - and there is no evidence either
way, because the only `upgrade` lines any session has produced are the catenary
tool's. The track-type branch of `upgradeFn` has never been observed running.

Three things it could be, and they are distinguishable:

1. **The engine never asks.** The track tool may only treat an existing *edge*
   as upgradable, and a station's track is a module, reached by the catenary
   tool through a different path (its log lines come from a `TrackModifierPool`
   thread, which the builder is not).
2. **It asks and the drag misses.** Our track is at +12 with the terrain at 0,
   so a drag that looks like it is over the deck may be at grade, where it
   genuinely does collide with the station.
3. **It asks and we decline.** Least likely: the gate is stock's, byte for byte,
   and returns true for any `roadType == 0` template.

`isAffectedByToolFn` now logs what it was asked and what it answered, deduped,
the same way `upgradeFn` has since round two of T4:

    [multi-layer] tool add{streetTemplate=...high_speed} remove{nil} roadType=0 -> true

Nothing logged while the cursor refuses means the first explanation, and the
control test settles it without any of this: **drag high-speed over a stock
modular rail station.** If stock collides too, the track tool is not how a
station's track type is changed in this game, and the module list is - which is
what the report says already works.

**It is the first explanation - answered 2026-10-22.** The collision is correct
behaviour and the track tool is not a route to a station's track type at all.
Both routes that exist work: the upgrade tool, and replacing the module. See
"Round seventeen".

## Round seventeen: the three deletes, and the track type was never the track tool's

**Measured in-game 2026-10-22.** Three open questions closed with four clicks,
and every one of them closed the cheap way - by doing the thing, not by
instrumenting it further. All three had been waiting a session or two with the
code already in the state the test needed.

### A support deletes. The collider overhang was never the obstacle

Deleting a support works, with supports standing either side of it, with
`SUPPORT_SEAM = 0.1` and `support_block.mdl` filling its cell to within 0.1 m on
every side. So the last trace of round three is retired: a support's collider
reaching the cell outline, and all but touching its neighbour's, is **not** what
the bulldozer objects to.

That is the second half of what round seven started. Round three read the old
abutment's 0.70 m collider overhang as the reason a support could be placed and
not removed, and the whole of `fitSpan`, `SUPPORT_TILE`, `tileCount` and the
doubled-up twin copies existed to buy it off. Rounds four to six could still
remove nothing with all of it in place; round seven fixed removal by clipping
the **reservations**; and now the geometry that round three said would overlap
its neighbours deletes without complaint. Nothing about the drawn shape was ever
load-bearing - only the rectangle.

The practical gain is that the cells can stay full. There is no allowance left to
reinstate and no reason to shrink a pier again.

### A platform deletes with the concourse in the build

Round six's exact condition, finally run: the concourse seeded, in the build,
and a platform deleted. It goes.

So the concourse as it stands since rounds nine to twelve - picked from a clear
2 m band at its pier, reservations clipped rather than zeroed - does not veto the
configuration the way the round-six version did. Round six's reading was right
about *that* build and wrong as a rule: it was never the concourse's presence,
it was the reservations it was carrying.

What is still untested, and now deliberately so, is whether a **cross-level
reservation overlap** vetoes a removal at all. No build has one left to find out
with; answering it would mean putting one back on purpose, and nothing needs the
answer.

### A seeded concourse places against a road

T5a steps 1-2, the asymmetry round sixteen flagged: a seeded module's geometry
is checked against the **world** at placement, where a player-added one is only
checked against the construction. Placing the station snapped to an existing
road works, and so does demolishing the concourse and putting it back with the
road already there.

So the hole in the 24 x 6 m cell is wide enough for the entrance road it has to
clear, which is the thing the design rests on. Round fifteen's -15 m limit and
`CONCOURSE_PICK_X` are both confirmed by a placement that would have failed
under either of the two earlier geometries.

### The track tool's collision is correct, and the module list is one of two routes

The control test from round sixteen, answered by the report rather than by the
log: dragging high-speed track over the station collides, and **it is supposed
to**. That is the builder laying new track, not an upgrade path, and it behaves
the same against stock.

A station's track type is changed two ways, both of which work here:

- **the upgrade tool**, which is the path `upgradeFn` serves and the one the
  catenary already proved on 2026-10-21, and
- **placing a new track module over the existing one**, which is the module list
  doing it.

So explanation 1 of the three in round sixteen is the right one - the engine
never asks the track tool's drag about this construction - and it is not a
defect. `isAffectedByToolFn`'s logging stays, because it is what made the
distinction checkable, but there is nothing left for it to catch here.

One thing is genuinely missing and is parked: **the upgrade tool offers no
high-speed variant.** Availability by year is not it - round sixteen's table has
all six templates live from 1980 - so it is either where the upgrade tool gets
its list from or something about the pairing of types, and it is a question for a
later session. Standard and catenary are enough for v0.1.

## Open questions

- ~~Why can a support be placed and a concourse not?~~ **Position - answered
  2026-10-13.** The probe slot took the module and the real one never did, with
  nothing else differing between them. See "Round nine"; the fix is
  `CONCOURSE_PICK_X`.

- ~~Does the engine pick a slot by its rectangle or by its origin?~~
  **Neither, where something is standing - answered 2026-10-13.** The origin
  was moved onto ground no stock slot reserves and the slot was still not
  offered. See "Round ten".

- ~~Is the buried support unplaceable as well?~~ **Yes - answered 2026-10-13.**
  `674000001` never took a module while `674000003` and `674000005`, its
  neighbours in the same tiled row, both did. Second confirmation of the rule,
  in a different family.

- ~~Does `dependentSlots` carry the click?~~ **Not on its own - answered
  2026-10-13.** Both entries reached the engine and neither slot became
  placeable. It may still be the second half of stock's idiom; what it is not is
  a way in for a slot that reserves overlapping ground. See round eleven.

- ~~Does an overlapping reservation disqualify a slot, or does stock's zero plus
  a dependency let it in?~~ **The reservation is the filter - answered
  2026-10-13.** Side by side at one entrance, the clear 2 m band took four
  modules and the zero-plus-dependency took none. See "Round twelve".

- ~~Is the brick's collider overhang actually what the bulldozer objects to?~~
  **No - answered 2026-10-22.** A support deletes with its cell filled to within
  0.1 m and neighbours either side of it, so the drawn shape was never the
  obstacle and the reservations always were. Round three is retired and the
  allowance it bought is gone. See "Round seventeen".

- **Does the engine accept a negative `spacing` component?** Open, 2026-10-13.
  It is the difference between "the deck stops at the entrance" and "the deck
  crosses it with the part of its column that is clear" - see round thirteen -
  and it would also widen the concourse's own 2 m pick band. Everything written
  here about rectangles having to contain the slot's origin rests on `spacing`
  being four *distances*; nothing has tested whether a negative one is read as
  an offset or clamped.

- **Does an *empty* stock reservation disqualify a slot too, or only an occupied
  one?** Open, 2026-10-13. The band that works (x = 10 .. 12) is clear of both
  the occupied entrance at +-8 and the empty `large_building` slot at +-10, so
  the measurement does not separate them. It is worth knowing, because if only
  occupied rectangles count the band could be 8 .. 12 - twice the target - and
  `trimReservations` already has the machinery to cut a rectangle clear of an
  obstacle and keep the origin inside it. Cheap to test: widen
  `CONCOURSE_FLANK_HALF` to 2 and move `CONCOURSE_FLANK` to 10, and see whether
  the pip survives.

- **How does stock's own platform roof get offered, then?** Open, 2026-10-13.
  It reserves nothing and is listed in `dependentSlots`, which in our hands
  produced no pip. Either the engine treats a roof type specially, or
  `dependentSlots` works only in some configuration ours does not reproduce (a
  roof sits 2 m directly **above** its parent, same x and y; ours was 3 m to the
  side at the same height), or roofs are reached some third way. Not needed for
  this mod any more - the rule in round twelve is enough to build on - but it is
  the one thing that would make a stacked slot clickable without spending a
  rectangle on it.

- **What are `autoFill`, `maxModules` and `message` for?** Open, 2026-10-13.
  All three are slot or `slotConfig` fields the engine reads and this mod does
  not set. Stock sets `maxModules = -1` on every street slot type and
  `-8-2` on a harbor one (`harbor_modular.script.lua:128`), so negative is not
  a disabled flag but an expression of something; `message` is `""` everywhere
  except `street_terminal_exit`, which carries "You shall not pass"; and
  `modules_util::GetNumAndFilledAutoFillSlots` plus `autoFillSlots` on
  `SimpleProposal` say `autoFill` is about slots the engine fills itself. None
  of it is needed yet. It is written down because a slot field we do not
  understand is exactly the shape of the last four rounds.

- ~~Does zeroing the slot reservations restore module removal?~~ **No -
  answered 2026-10-12.** It was in place throughout rounds five and six while
  nothing could be removed, and what restored removal was unseeding the
  concourse. Zeroing then cost the tracks their only pickable geometry, so it is
  now a clip rather than a wipe. See "Round seven". What is still **unknown** is
  whether a cross-level reservation overlap vetoes a removal *at all*; the next
  build no longer has one to find out with, so answering it would mean putting
  one back deliberately. Round seventeen leaves it there on purpose: deleting a
  platform with the concourse in the build now works, so nothing needs the
  answer.
- **Does the bulldozer's flat check look at module *geometry* as well as slot
  reservations?** Round seventeen makes this unlikely - a block filling its cell
  to 0.1 m deletes - but it is not ruled out, and it is the remaining suspect if
  a removal is ever refused again with no overlapping rectangle in the log. The
  test is to emit a module's models untagged, as construction geometry
  (`result.models` directly rather than through `addModel`), and see whether the
  refusal follows the tag or the geometry.
- **Should support slots be `dependentSlots` of the rail module above?** Stock
  pairs a roof slot with its platform that way, and it is the half of the idiom
  this mod does not implement - twice over now: removing a platform orphans its
  supports instead of taking them with it, and it is also what lets stock get
  away with `spacing = { 0, 0, 0, 0 }` on a stacked slot (round eight). Appending rather than replacing matters - rail already
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
- **Why does the upgrade tool offer no high-speed variant?** Open, 2026-10-22,
  and parked. Both routes to a station's track type work - the upgrade tool and
  replacing the module - but high speed appears in neither tool list, while
  round sixteen's table says all six templates are live from 1980. See "Round
  seventeen".
