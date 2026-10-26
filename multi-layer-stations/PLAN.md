# Plan

Feasibility: **proven**. The station is built, placeable, editable, and as of
2026-10-22 both **passengers and freight move between the two levels** in a real
save. As of 2026-10-23 the last open *behavioural* question is closed too:
passengers **walk** between the levels through the concourse, so the pedestrian
link stays.

One feature went in after that, on 2026-10-26 and deliberately before
publishing: the concourse is now **two modules**, an arch over the entrance road
and a hall for the rest of the frontage, and the pedestrian link is one lane per
concourse rather than one per station. It was asked for from the game, it is the
last thing that will change the shipped behaviour, and it is item 0 of the
release list below because it is the only item there that has not been in front
of the game. Everything after it is release work, not design work. The phase
sections further down are kept as the record of how each question was settled -
read them for the reasoning, not for the plan.

The original framing, kept because it still explains the ordering: everything in
`NOTES.md` was read out of the install and nothing was confirmed in-game, so the
plan was ordered to kill the project soonest if it was going to die.

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

The two levels are **two separate stations**, and that is forced rather than
chosen - see Phase 3, answered 2026-10-22. One construction with two station
records becomes two station *groups*, one station each, and there is no API to
join them. Lines on the two levels therefore cannot interchange freight
directly; they do it through stock in the shared catchment, which is what the
concourse's goods store is for. Passengers are a separate mechanism and a
separate open question (Phase 10, step 2).

Shape being aimed at: **option A** from `NOTES.md` - three levels at a 12 m
pitch, each level hosting one whole stock station family offset in z, with
per-level slot id namespacing and no terrain alignment off grade. Option B stays
on the table only if a probe rules A out.


## Release: what is left

Ordered so that anything that can still change the shipped behaviour comes
before the things that only polish it.

### 0. The concourse pair - written 2026-10-26, part-run

Asked for from the game: a second concourse building with the same footprint,
no road tunnel, and pedestrian connections, plus a doubt about whether
"concourse" was the right word for either of them. What was built:

- `ml_concourse` became **`ml_concourse_arch`**, and the new module is
  **`ml_concourse_hall`** - *Concourse - Road Arch* and *Concourse - Hall* in
  the menu. A slot type is a savegame key, so renaming the first one was free
  exactly once, and this was it;
- the hall carries **everything the arch carries**: 175 m of catchment, +100
  capacity, its own 100 units of the goods store, the same price, and its own
  pedestrian climb. The two differ in their art and in the ground they are
  offered on;
- its slots are **one per deck tile along the frontage**, in the arch's own
  40 x 6 m band, taking their frame from the entrance and their extent from the
  deck. Tile 0 is the arch's and is never offered as a hall, nor is any cell
  within a tile's width of another entrance;
- `linkLevels` draws **one lane per concourse module**, anchored at that
  module's cell, which closes Phase 10 step 2. The unanchored fallback stays for
  a station with no concourse;
- and each hall draws a **footway of its own**, at grade - a frontage lane
  across its cell, a `linkable` kerb spur to its road-facing face, and a link to
  the nearest node the station already had. That came out of the first run: the
  volumes were right and *"there are no pedestrian connections from the new
  concourse to the road next to it."* It works - *"fully functional"* - and the
  second run put the geometry under it: a 30 cm walkway along the cell's face,
  because 30 cm is the kerb every stock footway sits on and a lane at that
  height with nothing beneath it is a lane the engine raises the ground to meet.

`NOTES.md`, "The concourse becomes two modules", has the design record and the
id arithmetic. The run of 2026-10-26 answered the question that could have sent
this back to the drawing board - **a hall slot takes a pip**, `0 of 72` of our
slots filtered, and the building places and reads right - and four interchange
lanes coexisted without the duplicate-edge crash.

The footway that run asked for is in and working, and it now has a walkway under
it; `TESTS.md` T10 step 7 says what to re-check, which is whether any hill
survives having a real kerb to climb.
What is left of this item is ordinary verification - T10 steps 4, 5, 8, 9, 10
and 11 - and one thing that is older than the hall: a solid 40 m block and a
footway at grade are both right on the flat and unproven on a slope, because
this construction anchors terrain and never flattens it. That is an open
question in `NOTES.md` rather than a release blocker.

### 1. The probe is out - done 2026-10-23

`ml_probe.gs.lua` and `ml_probe.script.lua` are archived in
[probe/entity_probe/](probe/entity_probe/) with a README covering what they
answered and how to re-enable them, and their two entries are gone from
`_content.json`. The deployed mod is 15 files and no game script; `deploy.ps1`
wipes its target, so nothing stale survives in the staging area. Verified.

They were held back until last because they are the only way this project can
see entities, and item 7's `Tram station` label turned out to need them. That is
answered, and nothing else was waiting.

One gap recorded in the archive's README, for anyone who revives them:
`api.type["enum"].Carrier` did not resolve at runtime, so carriers and transport
modes printed as raw integers and had to be decoded against the declaration
order in the tealdefs. Worth hardcoding both name tables in a successor.

### 2. The pedestrian link stays - settled 2026-10-23

Answered in game, and the other way from the way this section was leaning:
**passengers walk up through the concourse** and reach the platforms by the rail
station's own passenger crossings from there. `linkLevels` is load-bearing and
stays, and `vehicleNodeKeys` stays with it - its refusal fired 11 times in that
session, so the crash path it guards sees live traffic rather than theory.

The log is what makes it conclusive rather than anecdotal:

    person nodes: 142 street (z 0.0..0.3), 2208 rail (z 5.0..13.1);
      0 node(s) shared between the levels

Zero shared nodes, with both families now filed correctly, means stock joins the
two levels **nowhere**: the street level tops out at 0.3 m and the rail level
starts at 5.0, so there is no coincident node for the engine to weld. The lane
this mod draws is the only route across, and it now ends somewhere a person can
stand - `street (-47.5,-13.8,0.3) -> rail (-47.5,-14.0,13.1), a climb of
12.8 m`, which is the condition the shared-node report was written to check.

The teleport of 2026-10-22 is explained rather than contradicted: there was no
path then, because the link was joining rail to rail. The engine teleports a
transferring passenger when no walkable path exists and walks them when one
does. See `NOTES.md`, "The link is what carries them after all, and the teleport
was a fallback".

### 3. The freight path, played - settled 2026-10-23

`CONCOURSE_STOCK_CAPACITY` is 100 per module, chosen 2026-10-22 over 250 so that
two concourses buffer a train's worth of one cargo and no more. It was played at
that number on 2026-10-23 and the transfer works as expected - no store that
fills and stalls the train. Nothing left to decide here.

### 4. The build-menu tile advertises freight too - done 2026-10-23

`multi_layer_station.con.lua` declared `cargoClassesIncluded = { "PASSENGERS" }`,
which was a leftover and was wrong: both levels take freight and the concourse
stores it. It now reads `{ "PASSENGERS", "UNIVERSAL", }`.

Those two cover everything, and they are the stock idiom rather than a guess.
The game has exactly six cargo classes - `PASSENGERS`, `UNIVERSAL`, `BULK`,
`FLATBED`, `GOODS`, `LIQUID` - read off every `*.cargo.lua` in
`base/content/cargos/`, and **every freight cargo declares `UNIVERSAL` plus one
specialization**. `{ "PASSENGERS", "UNIVERSAL", }` is what every airport, every
small street stop and the modular harbor declare, verbatim.

Not syntax-checked with `tools/luacheck.py`, which needs `lupa` installed; the
change is a table literal and a comment.

### 5. The README's promises - done 2026-10-23

All four are written up. *What v0.1 does and does not do* gained a "three things
worth knowing before you build one, because each looks like a bug and is not"
block covering the first three below, and lost its stale claim that the mod does
not do cargo; *Accepted limitations* gained the `Tram station` label as a
base-game defect with the measurement behind it. What was owed:

- the station is internally **two stations**, one per level, in two separate
  StationGroups - which matters for line stops, but is **not** what the player
  sees. Corrected 2026-10-23 against the game: clicking either level opens one
  dialog with a **single station name** and three tabs, `Road station`,
  `Tram station` (the rail level, mislabelled by an engine bug) and
  `Warehouse`. The earlier claim here that the two levels get separate names was
  an inference from the group count, never an observation, and it was wrong;
- **freight crosses levels through the concourse's goods store**, so a station
  with no concourse cannot interchange cargo at all. This is the "required
  module" problem the plan already flags under Phase 10, and freight makes it
  sharper;
- **passengers cross on foot**, walking up through the concourse and across by
  the rail station's own passenger crossings - so a station with no concourse
  strands them as surely as it strands freight. Settled 2026-10-23 (step 2).

### 6. Art is placeholder, and says so

Three sets, all deliberately labelled: the menu tiles and previews
(`tools/make_menu_art.py`), the support's facade of tiled bridge abutment
(`stone_abut_rep_rep.mdl`, one finished face out of four), and the concourse's
two brick walls. The README's *Contributing art* section already carries the
sizes, formats and volumes. **Not a release blocker** - it is honest and it
invites replacement - but it is the first thing anyone will comment on.

Worth considering: the concourse store has no `loadIndicators`, so the goods it
holds are invisible. Crate art would make a mechanic that is currently
log-only visible in the world.

### 7. Known defects to fix or document

Each one needs a decision, not necessarily a fix:

- **the cargo station building cannot be placed.** The engine's module collision
  check is height-blind and runs after our hook, so the one rail module that
  would give the upper level catchment of its own is refused. Documented in
  `NOTES.md`; it is the sharpest remaining functional gap.
- **a support with no collider** - whether it would still be deletable is
  untested, and it is the cheaper half of the collider problem.
- **the rail level is labelled `Tram station`** in the entity window, when it is
  a train station. **Measured and closed as a vanilla defect, 2026-10-23** - it
  is not ours and cannot be fixed from here. The engine maps
  `TransportMode.TRAM_TRACK` to `Carrier.TRAM`, every stock rail track template
  carries `TRAM_TRACK`, and `getSubconstructionDescriptionAndSortKey` walks the
  carriers with no `break` so the last one wins. Every rail station in the game
  has the label; vanilla just never renders a header for a single-tab window.
  All seven of our rail terminals report it identically, which is what rules out
  our own merge. **Action: document it in the README and report it upstream** -
  the alternatives are a custom track template without `TRAM_TRACK`, which costs
  the track-type and upgrade tools, or overriding the engine's GUI file. See
  `NOTES.md`, "The `Tram station` label is vanilla's".
- **T8's recovery path** is unrun.
- the menu icon is hardcoded to era C.

### 8. Validate, then publish

1. `.\deploy.ps1 -Validate` with the game **closed**. It runs the game's own
   validator over the staging area, which is what publishing runs anyway; judge
   `levelPc` and `levelConsole`.
2. Run the pre-publish set in [TESTS.md](TESTS.md).
3. Publish from the in-game Mod Manager. It writes the numeric id into
   `_metadata/mod.io_fileid.txt` **in the staging area**, which `deploy.ps1`
   overwrites - so copy it back into the source tree immediately and add the id
   to the table in the root `NOTES.md`.

### Frozen on first publish

After the first release these become a compatibility contract, because a save
holds them and a change to any of them breaks what the player built:

- the support slot id packing, `SUPPORT_SLOT_BASE + slot.id * 10 + k`, the
  arch's `ARCH_SLOT_BASE + streetSlotId` with the variant digits cleared, and
  the hall's `HALL_SLOT_BASE + that same entrance id + 50 + tile`;
- the module names `ml_support`, `ml_concourse_arch` and `ml_concourse_hall`,
  and the slot types of the same names. The concourse rename of 2026-10-26 is
  the last one that costs nothing;
- the construction param list, which is deliberately **empty** - stored values
  come back as 1-based indices into `values`, so adding a param later changes
  the meaning of every station already built.

`mod.json` already says the honest thing about removal: keep the mod enabled
while a save contains one of these stations.


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

### Answered 2026-10-22: several. The answer is no.

Measured with a game script against the real station
(`stationGroupSystem.getStationGroup`), not inferred:

    station 20844: group=26028    group 26028: stations=1
    station 20810: group=26029    group 26029: stations=1

**One construction with N station records becomes N station groups**, one
station each. There is no way to join them - `cmd.d.tl` has no join or merge
command and `stationGroupSystem` is read-only - and terminals cannot be moved
into one record either, because a terminal's node and edge ids index **its own
subconstruction's** lane lists (`addLaneLists`' `replaceIndices`).

So the pessimistic branch of this question is the real one, with one correction
to what it predicted: **freight does not need merged terminals, it needs shared
stock.** A station hands cargo to stock in its own catchment and never to
another station, so a `STORAGE_STOCK` both levels can reach is the whole of the
mechanism - built into the concourse, Phase 10. Confirmed carrying planks
2026-10-22 (`shipped/yr` climbing).

Passenger interchange is still open, and is now the *only* thing the pedestrian
lane might be load-bearing for. See Phase 10, step 2.


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

**Closed 2026-10-12: the seeded station buildings are gone.** With the concourse
confirmed working in-game, a seeded building on each level is a second building
the player did not ask for and has to delete twice, so neither is seeded any
more. The slots are untouched - anyone who wants a station building places one,
and it then adds its own catchment and capacity on top of the concourse's, which
is the behaviour this phase was asking for in the first place.

What each one was actually worth, for the record: rail `main_building_1` is
150 m of catchment and +30 capacity; street `era_*_passenger_building_10_10` is
+8 capacity and **no catchment at all** - street-side catchment comes from the
entrance, which is still seeded. One concourse is 175 m and +100, so removing
both leaves every station better off on catchment and roughly level on capacity.

The one thing this changes that is not about numbers: the rail main building was
also contributing `person_lanes` and `linkable_person_lanes`
(`trainstationutil.lua:436-445`), so the upper level's pedestrian connection now
runs entirely through `linkLevels` down to grade and out through the street
entrance. That is the intended design - the concourse is where the stairs
belong - but it had never been the *only* route before. See TESTS.md T5b.


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
passenger station and `catchmentCargo` to the cargo one). One building serving
both levels is the honest model, and our module is in neither family's module
map - so neither family's sweep sees it and there is nothing to double-count.

This section used to justify that with "the two levels share a single
StationGroup". **They do not** (Phase 3, answered 2026-10-22), which makes the
concourse more important rather than less: it is the only thing either level has
that can serve both.

### Step 1 - catchment and capacity *(done 2026-10-09, awaiting a run)*

- Slot type `ml_concourse_arch` (`ml_concourse` until the pair of 2026-10-26),
  id `800e6 + streetSlotId` with the variant digits
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

### Step 2 - anchor the pedestrian link *(written 2026-10-26, unrun)*

**Done, as part of item 0 of the release list.** `linkLevels` draws one lane per
placed concourse module of either variant, anchored at that module's cell, with
the vehicle-node refusal and the duplicate-edge guard both kept and the second
one now also applied between our own lanes. A station with no concourse keeps
the unanchored lane this section was written about.

What the section said when it was still a question, because the reasoning is
what justifies the shape: `linkLevels` searched for the closest pair of person
nodes in plan, ignoring z, and in a real session picked a lower endpoint at
**z = 5.0** - passengers stepping off five metres up. With a concourse present
the link should start at the concourse's slot instead, which makes it
deterministic and puts it where the stairs art will be. Keep the vehicle-node
refusal.

**First decide whether the link stays at all.** The interchange works in both
directions and passengers **teleport** between the levels rather than walking
(2026-10-22), and a stock island platform with no underpass works too - so
interchange inside a StationGroup does not need a walkable path, and the lane
may be buying nothing. Against that it is the only known hard-crash path in the
mod. The control test is T6 step 5: make `linkLevels` inert and repeat the
no-catchment interchange test. If the link is optional, this step merges into
step 3 and becomes a lane that follows the stairs art, or no lane at all.

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
