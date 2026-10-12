# Plan

Feasibility: **unproven**. Everything in `NOTES.md` is read out of the install;
nothing is confirmed in-game. This plan is ordered so that the cheapest probe
kills the project soonest if it is going to die.

Status after the first probe run, 2026-10-08:

- **Phase 0 - PASSED.** A construction can own a `BRIDGE` edge at +12 m. It
  renders as a viaduct, the terrain underneath is untouched, and player-drawn
  track connects to it and works. This was the load-bearing risk for the whole
  idea and it is closed.
- **Phase 1 - PARKED.** The `TUNNEL` edge at -12 m renders and accepts a
  connection, so the construction side works. The player's connecting track
  trenches instead of tunnelling on flat ground, and chasing that is not worth
  it yet. **Level -1 is out of scope for the first working version** - see
  `NOTES.md`, "Parked: level -1", which records what works, the three things to
  try next, and the likely structural answer.
- **Phase 3b - blocked, then redesigned.** The standalone slot probe could not
  be selected after placing, because a construction with no station-like
  subconstruction has no entity window at all (root `NOTES.md`, "A construction
  is only selectable if it contains a station-like component"). Replaced with a
  `loadConstruction` modifier that adds the slot layer to the **stock modular
  rail station**, which is already selectable. Deployed and validated; awaiting
  a run.

All probe questions that gate the design are now settled - see
[probe/TESTS.md](probe/TESTS.md) for the results table. **Phase 4 has started**:
`mod/multi_layer_stations_1` is v0.1, one rail platform over one bus platform.

Decided along the way: the two levels stay **two separate stations**, not one
grouped station. It matches in-game practice, lets the player inspect and name
each level, and costs nothing in the merge - each delegated family keeps its own
station record. Passengers transfer by walking the pedestrian lane between
levels rather than for free.

Shape being aimed at: **option A** from `NOTES.md` - three levels at a 12 m
pitch, each level hosting one whole stock station family offset in z, with
per-level slot id namespacing and no terrain alignment off grade. Option B stays
on the table only if a probe rules A out.


## Phase 0 - the load-bearing probe: an elevated construction edge

**Question.** Does `edgeType = "BRIDGE"` work from inside a construction?
Specifically: does the engine generate pillars and abutments for an edge born at
z = +12, and can the player draw a track to its free node up there?

Nothing in the shipped content does this - the underground station is the only
construction that sets `edgeType` at all, and it only ever uses `TUNNEL`. If
this does not work, option A's elevated half is dead and the mod becomes
"underground only", which changes the whole proposition.

**Spike.** A throwaway construction, no modules, no params beyond what the menu
forces: one track edge at z = 12 via `constructionutil.addEdges` with
`edgeType = "BRIDGE"` and `edgeTypeName = "::/infrastructure/bridge/concrete.bridge"`,
two snap nodes, **zero** `terrainAlignmentLists`. Order of 60 lines.

**What to watch.** Pillars and abutments rendered or not; whether the terrain
stays put; whether a player-drawn track snaps to the free node; any `ERROR` line
in `stdout.txt`.


## Phase 1 - level -1 *(parked)*

Answered as far as it needs to be: the construction can own a `TUNNEL` edge at
-12 m and it works. The remaining problem is the player's connecting track, and
level -1 is out of scope for now. `NOTES.md`, "Parked: level -1", holds the
state so this can resume without re-deriving it.

Current scope is **level 0 and level +1 only**.


## Phase 2 - terrain, on the real station

**Question.** Does dropping the alignment entries actually stop the plateau?

**Spike.** A `loadConstruction` modifier that wraps the modular rail station's
`updateScript`, calls the stock function via `util.useFn`, and empties
`result.terrainAlignmentLists` before returning. Same shape as
`pick-single-platform-side`, so the plumbing is known-good.

**What to watch.** Station sits on raw terrain instead of flattening it; ground
textures (`groundFaces`) still land, since those are a separate list; nothing
floats or sinks in a way that makes the station unusable.

The complementary case is already answered: the native `height` slider works but
carries the terrain up with it, so a station underneath collides (confirmed
2026-10-08). Stripping the alignment entries is the hypothesis that fixes it.


## Phase 3 - one StationGroup, or several?

**Question.** Do several `station` records in one construction join a single
StationGroup, so lines stopping on different levels can interchange?

This decides how much work option A is. If the answer is yes, vertical
pedestrian lanes are cosmetic. If no, every level pair needs authored lanes and
merged `terminals`, and the lane index rebasing across subconstructions becomes
real work.

**Spike.** Cheapest version is observational: place a stock harbor (passenger +
cargo stations in one construction) and check whether the line editor offers
both under one station entry. Confirm against
`api.engine.system.stationGroupSystem.getStationGroup` from a console or game
script if the UI is ambiguous.


## Phase 3b - the editing probe

Cheap, independent of 0-3, and it decides the UX. Two questions on one
throwaway construction with slots at z = 0 and z = 12:

1. **Is the slot picker z-aware?** Give the two layers the same slot `type` and
   see which one a click selects. Then set `slot.height` (undeclared in any
   shipped content) on both and see whether it changes the answer.
2. **Does `postConstructionModifiable` work?** Add one param with the flag set
   and check that the built construction's entity window offers it. No shipped
   construction sets it, so this is unexercised.

If (2) works, the `editLevel` mechanism in `NOTES.md` is viable and the UX is
settled regardless of (1). If (1) also turns out z-aware, the level param
becomes a convenience filter rather than a requirement.


## Phase 4 - delegation plumbing *(in progress)*

**v0.1 done, awaiting its first run.** `mod/multi_layer_stations_1` delegates the
stock rail station to level +1, lifts all of its output by 12 m in one pass at
the end of a wrapped hook, converts its edges to bridges, drops its terrain
alignment and ground faces, and adds a hand-built bus platform at grade with its
own station record.

Why one uniform lift at the end rather than offsetting the slots up front:
`addLaneLists` runs inside the stock hook and derives lane transforms from model
transforms, and those models are a mix of module-placed and host-placed. Shifting
the slots early would split the station across two heights and leave the lane
list straddling both.

**Hardened for the beta, 2026-10-09.** Both levels are delegated and the
construction now answers for the whole of each family's script surface, not just
`updateFn` - see root `NOTES.md`, "Delegating a family means delegating its whole
script surface". What changed:

- `preProcessScript`, routed to street's `preProcessFn`. Without it a street
  passenger platform was one slot instead of two, so **editing** the lower level
  produced half platforms even though placement looked right.
- `upgradeScript` + `isAffectedByToolScript`, **reimplemented** rather than
  routed to rail's. Without them the elevated track could never be electrified
  or changed to another track type, because the modular rail station has no
  param for either - the upgrade tool is the only route. Both took two rounds to
  get working, for two different reasons, and both failures looked identical from
  the cursor; `NOTES.md`, "The upgrade tools, round two". Confirmed working
  2026-10-12.
- The dead `mlBridge` construction param removed. It was visible in the
  placement toolbar (`desc.params` is concatenated with `template.data.params`)
  and read by nobody.
- Module routing by slot id for our own slots rather than by the name
  `ml_support`, so a third-party support module is not mistaken for a rail one.
  Anything unclassifiable is now logged.
- Subconstruction tags from a per-family base (street 1.., rail 101..) rather
  than from the position in the concatenated list, so the rail station's tag no
  longer depends on how many subconstructions the street level produced.
- A run-once guard on the hook, a grade-anchored empty result when a stock
  `updateFn` cannot be resolved, a `year` fallback, and the pedestrian link now
  refuses to attach to a person node that coincides with a vehicle node - the
  one thing in this mod that can hard-crash the game.
- **The elevated track's `snapNodes` are no longer converted to `freeNodes`.**
  That conversion was a leftover from the terrain hunt and it broke module
  editing the moment a track was connected: every module except the one at the
  connection refused with "construction not possible". Reverting it fixed that
  and changed nothing about the terrain. Root `NOTES.md`, "A station's
  `snapNodes` are load-bearing"; there is now a warning if a TRACK edge list
  ever ends up with edges and no snap nodes again.
- Bare-relative resource ids are resolved against the owning family's
  directory. Street uses 42 of them and rail none, so the bus station's side
  building had been a missing model on every rebuild since the street level was
  delegated.
- **The bridge under the elevated track is gone.** `edgeType` stays `NORMAL`.
  The stone viaduct rendered correctly but the engine generates its pillars and
  abutments from the edge alone, so they drove through the bus station below.
  Structure on a multi-level station has to be placed, not generated - the same
  conclusion Phase 7 reached for supports. Track tiles consequently get support
  slots now. See `NOTES.md`, "The elevated track carries no bridge".

See [TESTS.md](TESTS.md) for what to run before publishing.

Still to do:

1. ~~Make level 0 modular~~ - done.
2. Per-level slot id namespacing, needed once two families are delegated. Not
   needed in v0.1 with only one. In practice the two families' id spaces already
   differ (rail 6.4-10.8e6, street ~20e6) but not by construction, so namespace
   anyway.
3. Per-level transport type params (`level0Type`, `level1Type`).
4. Road-over-rail as well as rail-over-road.
5. Force the short catenary (`power_pole_2`) on any level that has something
   above it - 10.60 m does not fit under a 9.6 m soffit, 8.17 m does.
6. Shrink or skip the cargo platform collider (-2 .. +14) where it would poke
   into the level above.


## Phase 7 - support alignment under station buildings *(parked)*

**Parked 2026-10-08.** Supports work under platform tiles. Under station
buildings they sit beneath one side of the building and miss the other, and the
cause is now known, so resuming should be mechanical.

### What already works

- Supports are a **player-placed module** (`ml_support`), on their own slot layer
  at grade, aligned to the grid of the level above. Slot ids
  `600000000 + slot.id * 10 + k`, stable across rebuilds.
- Each module **sizes itself** from its slot's `spacing`, so one module serves any
  cell.
- Geometry is a **facade** - the outer ring of the cell only, hollow inside -
  tiled from `stone_abut_rep_rep.mdl` (4.4 x 4 x 2 m), six courses to the 12 m
  pitch, so brickwork lines up between adjacent cells and with the viaduct.
- Zero-footprint slots (stairs, `{0,0,0,0}`) are skipped.
- The footprint figures themselves are right, confirmed by the in-game
  diagnostic: `passenger_platform 5.0x7.8 x5`,
  `rail_building_size2 20.0x6.7 x3`, `rail_building_size3 40.0x7.4 x5`.

### First: the slot type is the wrong key, so the table below cannot work

Found 2026-10-09 while reviewing for the beta, by listing every rail building
module's `type` against the `extend` in its `updateScript.params.config`.
**A slot type does not determine the footprint of what goes in it:**

| slot type | model `extend` of the modules that declare it |
| --- | --- |
| `rail_building_size1` | `6, -6, 0, -17` |
| `rail_building_size2` | `11, -11, 0, -17` *and* `11, -11, 0, -23` *and* `11, -11, 0, -38` |
| `rail_building_size3` | `21, -21, 0, -38` |

`main_building_1` and `main_building_2` are both `rail_building_size2`, and they
are 17 m and 23 m deep; `side_building_3_cargo` is also `rail_building_size2`
and is 38 m deep. So any `FOOTPRINTS` table keyed on slot type - the one in the
code today, and the corrected one below - is wrong by up to a factor of two in
depth for whatever it did not happen to be fitted to.

The key has to be the **module**, not the slot. `addSupportSlots` already has
it: `modules[slot.id]` is the module entry, carrying `.name` (confirmed - rail's
own code does `mod.name:match(...)` at `modular_station.script.lua:579`). So
either key the table by name pattern - the extents are uniform across eras, so
`main_building_1` / `_2` / `_3` and `side_building_1` / `_2` / `_3` is six rows -
or read `extend` out of the module desc at runtime if
`api.res.moduleRep.get(...).updateScript.params` turns out to be reachable
(rail reads `.metadata` off the same desc, so the desc itself is).

`extend` is `{ xMax, xMin, yMax, yMin, ... }` in model space, which is the same
space as the bounding boxes below, so the quarter-turn correction still applies
on top of it.

### The bug, and the fix

The footprints are measured in **model space**, but the building module does not
place its model on the slot axes. `trainstationutil.MakeMainBuildingModule`
(`trainstationutil.lua:299`) uses:

```lua
local modelTransf = transf.rotZTransl(math.rad(-90), vec3.new(7.5, 0, 0))
```

A quarter turn **and** a 7.5 m shift in x. So in slot-local terms the model's
width and depth are **swapped**, and the footprint is offset sideways - which is
precisely "under one side of the building but not the other".

Working it through for `rail_building_size1`, whose model bbox is
x [-9.25, 9.25] (plus connectors to +-10.03) and y [-11, 0]:

- `rotZ(-90)` maps `(x, y) -> (y, -x)`, then `+ (7.5, 0)`;
- model x `[-10.03, 10.03]` -> slot **y** `[-10.03, 10.03]`, so slot-local
  depth = 20.1, centred on 0;
- model y `[-11, 0]` -> slot **x** `[-3.5, 7.5]`, so slot-local width = 11,
  centred at **+2.0**.

So `FOOTPRINTS` should hold slot-local values, not model-space ones, and needs a
lateral offset it currently hardcodes to zero:

| slot type | width (slot x) | depth (slot y) | cx | cy |
| --- | --- | --- | --- | --- |
| `rail_building_size1` | 11.0 | 20.1 | +2.0 | 0.0 |
| `rail_building_size2` | 20.05 | 20.0 | +2.5 | 0.0 |
| `rail_building_size3` | 37.0 | 40.0 | +11.0 | 0.0 |

Those last two rows are derived the same way but **have not been checked** -
size2's model y is `[-20.05, 0]` and size3's `[-36.025, 1.02]`, and size3 in
particular may use a different placement transform, since
`MakeMainBuildingModule` branches on head/side. Verify before trusting them.

`addSupportSlots` already applies `offX`; it just passes `0.0` whenever a
`FOOTPRINTS` entry exists. Feeding `cx` through is a one-line change.

### The better fix, if model attribution ever lands

All of the above is reverse-engineering a placement transform that the stock
script owns and could change. The robust version is to **compute each module's
footprint from the models it actually placed** - which needs the ability to
attribute models to the module that created them. That is the same missing
capability as "put the station building at grade" (Phase 8), so if it is ever
built, both get easier and this table can go.

### The art question, which is separate

`stone_abut_rep_rep.mdl` is a **bridge abutment** with one finished face. Tiled
into a four-sided ring it shows its unfinished side on two of them. Alignment is
fixable; this is not, without custom art. See the README's accepted limitations.


## Phase 8 - placing a module at a different level from its family

Needed by both "station building at grade" and the robust fix in Phase 7. The
rail subconstruction is lifted as a single unit, so there is currently no way to
exempt one module's geometry from the lift, or to find out which models a given
module produced.

Worth knowing before starting: the stock hook copies `result.models` into its
subconstruction **by reference**, and modules add models through an `addModel`
whose target list is passed in, so a snapshot of list lengths around the module
pass is the obvious starting point - the rail `updateFn` emits no geometry at
all, so everything present before the hook runs came from modules.


## Phase 6 - catchment from station buildings

**Largely done 2026-10-08.** Both levels now seed a station building, so
catchment and capacity come from module metadata the way the stock stations do
it - rail `main_building_1_era_*` at slot `3400020`, street
`era_*_passenger_building_10_10` at `MangleId({0, 0, small_building})`. The stock
`no catchment areas generated` warning is gone and the catchment fallback no
longer fires, which confirms the rail building's slot id was inferred correctly.

The direct overrides are kept as a **safety net that warns when it fires**, so a
wrong slot id after a game update shows up as a log line rather than as a station
that quietly stops attracting passengers.

That is a stopgap, not the intended behaviour. **Catchment should come from the
station buildings the player places**, because that is what a player expects: add
a building, the station reaches further. The current version ignores what is
built on it, which will feel arbitrary as soon as anyone looks.

**Answered 2026-10-09 by Phase 10, the concourse.** "Whether to keep the floor"
was the open question, and the answer is neither of the two options it offered:
the floor becomes a **placed object**. A concourse module provides the
catchment and capacity, so there is something visible to point at, and the
hidden default stays only as a backstop that says in the log that it fired.

The other half of this phase - "catchment should come from the station buildings
the player places" - is now true in the only way that matters: it comes from a
module the player can add, move and remove, and adding a second concourse over a
second entrance extends the catchment to where that entrance is.

Still open:

1. The street building's slot id is inferred the same way the rail one was, from
   `MangleId({coordI, 0, moduleVariants.small_building})`. If the pool-capacity
   fallback stops firing, it landed.


## Phase 10 - the concourse

The module that makes a multi-layer station a station: it spans the bus entrance
road at grade, and it is where the station's catchment and waiting capacity come
from - for **both** levels at once.

It is the third time this mod has reached the same conclusion, which is why it
is worth naming: *nothing automatic can know what the player means a station to
be.* Supports became player-placed because no rule can know what is under the
deck (Phase 7); the viaduct went for the same reason; catchment follows.

Why a module of ours is the only thing that can do this: on the rail side
catchment comes only from `main_building_*` / `side_building_*` / `stairs`, on
the street side only from `entrance*`, and **each feeds its own station record**
(`constructionutil.addCatchmentCircles` maps `catchmentPassenger` to the
passenger station and `catchmentCargo` to the cargo one). The two levels share a
single StationGroup, so one building serving both is the honest model, and our
module is in neither family's module map - so neither family's sweep sees it and
there is nothing to double-count.

### Step 1 - catchment and capacity *(done 2026-10-09, awaiting a run)*

- Slot type `ml_concourse`, id `800e6 + streetSlotId` with the variant digits
  cleared. One slot per **entrance**, derived from the street family's entrance
  slots the way support slots are derived from rail's - so a second entrance
  gets a second concourse for free. Clearing the variant digits matters: the
  three entrance variants are emitted as three slots at one transform, so
  keying off the raw id would both duplicate the slot and move the concourse's
  own id when a player swapped an entrance for an exit.
- 20 m x 10 m. The street entrance's ground face is x in [-5, 5], so the road is
  10 m and 20 m leaves 5 m either side while matching a stock `*_20_20` building
  and the `rail_building_size2` footprint. The depth stops short of the
  entrance edge's snap node at y = -15.
- The numbers are **data on the module desc** - `metadata.catchmentPassenger`
  and `metadata.moreCapacity` - read back by `applyConcourse` after the hooks.
  175 m and +100 capacity, against 150 m for a rail station building and 175 m
  for a street entrance.
- Seeded by default, over the seeded entrance.

The work happens in `finish`, not in the module's `updateFn`, and that is
forced: a module runs in stage 2, and the station records are assembled by the
two families' hooks in stage 3. The module declares; the script applies.

### Step 2 - anchor the pedestrian link *(next)*

`linkLevels` currently searches for the closest pair of person nodes in plan,
ignoring z, and in a real session picked a lower endpoint at **z = 5.0** -
passengers stepping off five metres up. With a concourse present the link should
start at the concourse's slot instead, which makes it deterministic and puts it
where the stairs art will be. Keep the vehicle-node refusal.

### Step 3 - the art

A tunnel portal over the road. Today the module draws two brick walls either
side of the cell, reusing the support course so it at least lines up; that is a
placeholder and looks like one.

### Still to decide

**How hard a requirement it is.** It cannot be enforced on removal - there is no
mechanism, and `slot.replaceable = false` is set by no shipped content, which
puts it in the same untested category as `Slot.alignToTerrain` was before it was
tested and cleared. So "required" means "the station stops working", which is
the silent failure this codebase has already paid for once. The intended answer
is to make the absence **visible in-game** rather than only in the log -
`result.labelText` is the lever to try - and to keep the backstop until it is.


## Phase 5 - the build UI

Design settled in `NOTES.md`, "Editing: how clicking picks a level". Build it:

1. An `editLevel` param, values -1 / 0 / +1, `postConstructionModifiable = true`.
2. `updateFn` emits slots for the active level only, so a click is unambiguous.
3. Per-level slot types (`l0_track`, `lp1_track`, `lm1_track`) so the MODULES
   menu is per-level, with `skipCollisionCheck = true` in each `slotConfig`
   entry.
4. Gate the per-level construction params with a `checkEnabledScript` returning
   `Hidden` for the inactive levels, so the toolbar only shows the live set.

Relax step 2 to "all levels always have slots" only if Phase 3b shows the picker
is z-aware.


## Deployment

Staging area only, per the root `CLAUDE.md`. Copy
`pick-single-platform-side/deploy.ps1` and change `$ModId` and the log prefix.
No mod.io id yet, so nothing to rescue in `_metadata/` until the first publish.
