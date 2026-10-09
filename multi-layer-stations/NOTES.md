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


## Open questions

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
