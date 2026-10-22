# Beta test protocol

What to run before publishing `multi_layer_stations_1` as a beta. Ordered so the
cheapest test that could kill the release runs first, and so each section builds
on the game state the last one left behind.

Fill in the results table at the bottom. Anything that fails is a line in the
README's accepted limitations or a fix, not a thing to shrug at - a beta that
other modders build on is a beta whose behaviour has to be known.

**This is a pre-publish document, not a development one.** Mid-development, the
only things worth putting in front of the game are the ones whose outcome is
genuinely unknown; a fix that has been seen working is taken as working, and the
table below records that rather than queuing it up again. Running these sections
end to end is what happens once, when the beta is about to go out.

Prerequisite: **grep the log for `were removed because`** if any `.mdl` has
changed - a model with a mod-relative resource path is discarded at load and
replaced by a placeholder that looks plausible (root `NOTES.md`). Then close the
game and run `.\deploy.ps1 -Validate`. Expect
`level=Info` and `Messages: none`. The validator is flaky (root `NOTES.md`,
"Validating a mod from the command line") - if no report appears, validate
`pick_single_platform_side_1` as a control before suspecting this mod.


## What this round is actually for

Everything load-bearing has been confirmed once, in the session that built v0.1.
This round is not about whether the idea works. It is about the three things a
single successful placement does **not** tell you:

1. **Does it survive editing?** Every test below that matters is "add or remove a
   module and see what the rebuild does". The module map is the only state this
   mod keeps, `updateFn` is the only thing that reads it, and a rebuild is the
   only time the two meet.
2. **Does it survive a reload?** A save/reload that merely looks right proves
   almost nothing, because reloading does **not** re-run `updateFn` (root
   `NOTES.md`) - the geometry comes back from the save. The real test is a
   rebuild *after* a reload.
3. **Does it survive the player doing something unreasonable?** Deleting the
   entrance, bulldozing half the platforms, dragging the catenary tool across
   the bus station.

Three changes in this pass have never been exercised in-game at all and each one
is a section of its own: the delegated `preProcessFn` (T3), the delegated
`upgradeFn` (T4), and the pedestrian link's vehicle-node refusal (T6).


## T0 - the test game

1. Launch, new game, enable **Multi-layer Stations** plus **No Costs** and
   **Sandbox** (both one-line shipped mods, `severityRemove: None`).
2. **Flat terrain, smallest map.** Flat is not cosmetic: several tests are "did
   the terrain deform", and on a slope a plateau is indistinguishable from the
   hill that was already there.
3. Start year **1990 or later**, so every era of module is available.
4. Save immediately as `ml-beta-0` before building anything.

Leave a log tail running for the whole session in a second window:

```powershell
Get-Content "$(( Get-ChildItem 'C:\Program Files (x86)\Steam\userdata\*\3493540\local' -Directory | Select-Object -First 1 ).FullName)\crash_dump\stdout.txt" -Wait -Tail 40 |
    Select-String "multi-layer|ERROR|WARNING"
```

Watch for the mod's own diagnostics, which are there to be read rather than
ignored:

| log line | what it means |
| --- | --- |
| `seeded: rail 4 tiles (160 m, era c) + 1 bus platform + entrance + 1 concourse` | `createTemplateFn` ran |
| `rail slot types: ...` | the rail family's slot inventory, for checking against `addSupportSlots` |
| `support footprints: ...` | what size support slot each thing above got |
| `snapPoint: transl=(...) fromStreetResult=false` | `false` is correct - the module's snap point won, not the hook's default |
| `built: N support slots, 2 subconstructions, 2 stations, ...` | the summary; **2 stations is the number to check** |
| `linked levels: (...) -> (...)` | the pedestrian link was created |
| `module add/remove slot=... via=street\|plain modules=N->M` | one line per module edit. `via=street` means the paired-platform rule ran; `N->M` is the map size, and a delete that is being applied shows `M = N-1` |
| `deck columns blocked at y = ...; rail slots not offered because the deck cannot reach past one: N` | the deck's street-side limit. `y = none` means the first-pass guard is not blocking the entrance column and the second pass is inert - see round sixteen |
| **`track edge list N has ... and no snapNodes`** | module editing will break as soon as a track is connected |
| **`N support module(s) have no slot any more`** | the level above them was removed; the engine will drop them |
| **`no pedestrian link possible`** | T6 failed - no interchange between levels |
| **`a station had no catchment of its own`** | `MAIN_BUILDING_SLOT` no longer lands in a real slot - likely a game update |
| **`module '...' belongs to neither stock family`** | a module was routed by guesswork |
| **`terminateConstructionHook called twice`** | should never fire; if it does, the lift is being suppressed |

Nothing in that list should appear in bold during a clean run.


## T1 - place one, look at it

The baseline, and the point is to establish a known-good state to edit from.

1. Road menu, **Multi-layer Stations** category (its own, since 2026-10-22 -
   not the stock Buildings category), passenger filter, **Multi-layer Station**.
   The support and the concourse live under **Multi-layer** in the module menu.
   Place it on
   flat ground against a road.
2. Check: it snaps by the **end of its bus entrance**, not by its centre. The
   log's `snapPoint` line says which.
3. Check: the terrain under and around it is flat. No mound, no plateau.
4. Check: no placeholder cubes and no sand-coloured ground texture - both are
   what an unresolved base-game resource name looks like, and neither errors.
5. Click it. Two stations should be selectable and separately nameable.
6. Connect a road to the lower level and a track to the upper one. Run a bus
   line and a train line.

**Then the thing that is actually being tested:** passengers. Give the bus line
a stop in a town and the train line a stop at another station, and confirm
non-zero passenger numbers *on both*. Catchment and pool capacity are the two
independent ways this station can be fully placeable, fully routable and carry
exactly nobody (root `NOTES.md`, "A modular station carries passengers only if
the right *modules* are present"), and neither shows up as an error.

Save as `ml-beta-1`.


## T2 - editing the elevated level

All of this is the rail family doing its own job through our merge.

**Do the whole of this section twice: once with nothing connected, and once
with a track connected to the upper level and a road to the lower one.** That
is not padding - it is the gap that let a real bug through. Module editing was
tested on an unconnected station and worked; connecting a single piece of track
made every module except the one at the connection refuse with "construction
not possible" (root `NOTES.md`, "A station's `snapNodes` are load-bearing").
An unconnected station exercises almost none of the engine's rebuild
machinery, because there is nothing it has to preserve.

When something refuses, the control test is always the same: **do it to a stock
modular rail station.** If stock refuses too it is engine behaviour and the job
is to document it. That one comparison is worth more than any amount of reading
the stock scripts.

1. Add a platform tile at each end, then a track tile at each end. **These are
   independent modules** - a platform does not extend the track or vice versa,
   and the rail station offers a `passenger_platform` and a `track` slot at
   every `(i, j)`. Both have to be extended by hand, and that is stock
   behaviour.
2. Add a roof, then an addon (stairs/underpass), then remove them again.
3. Add a second track and a second platform alongside.
4. Add a station building. Then **swap it for a different size** - this is the
   case that exercises `rail_building_size2` hosting buildings of two different
   depths.
5. Remove the station building entirely. Expect the catchment fallback warning
   and a station that still works; that is the designed behaviour, not a bug.
6. Delete every rail module. The construction should survive as a bus station
   with an empty deck rather than erroring.
7. **Extend the deck towards the street entrance, as far as it will go, then
   delete the tiles again.** This is the round-thirteen case. The deck must stop
   one tile short of the entrance - no platform or track slot is offered over
   it, because a module there could never be removed again (`NOTES.md`, round
   thirteen) - and every tile that *is* offered must delete again afterwards.
   The log line to read is

       rail slots not offered, because no reservation of theirs would survive
       the level below: N

   with N going up as the deck approaches the entrance. A tile that is offered
   and then will not highlight for the delete tool is the bug this guard exists
   to prevent, and the recovery is to remove the entrance module, delete the
   tile, and put the entrance back.

Watch for: geometry at +24 (a double lift), anything at grade that belongs
above, the terrain following a newly added tile, and `0 subconstructions`.


## T3 - editing the lower level *(new, untested)*

The delegated `preProcessFn`. Before this pass, a street passenger platform was
one slot instead of two.

1. Add a bus platform. **It must appear as a full two-tile platform**, not a
   half one. This is the single check this test exists for.
2. Remove it. **Both** tiles must go.
3. Add and remove the entrance, an exit, and a street building.
4. Remove the entrance and leave it off. The bus has no way in; confirm that
   reads as a broken station rather than a crash, and that re-adding it restores
   the lanes - in particular that a bus can get **out** again, since the
   entrance crossing's lanes are the thing a private `models` list breaks (root
   `NOTES.md`, "A hook may wrap the construction level into a subconstruction").
5. Add a second and third bus platform and run two bus lines through them.

Watch for: half platforms, an orphan tile that cannot be clicked, and
`the street preProcessFn failed`.


## T4 - the upgrade tools *(catenary works 2026-10-12)*

The delegated `upgradeFn` and `isAffectedByToolFn`. Before this pass the
elevated track was permanently plain, non-electrified standard track.

1. Take the **catenary tool** and drag it over the elevated track. Expect
   catenary poles and wire at +12, along the whole track row.
2. Run an electric locomotive to the upper level. This is the test - poles that
   render but do not electrify the track look identical.
3. Remove the catenary again.
4. Change the **track type**, the two ways that exist: with the **upgrade
   tool**, and by **placing a new track module over** the existing one. Both
   pass (2026-10-22). Dragging track from the Tracks menu is *not* one of them -
   it reports a collision because it is the builder laying new track, which is
   also what it does to a stock station. The one thing still outstanding is that
   the upgrade tool lists no **high-speed** variant, which is parked (round
   seventeen) and not about this construction: every track type is `yearTo = 0`
   and high speed is live from 1980.
5. Drag the **road upgrade tool** over the bus station. Expect nothing to
   happen to the construction: rail's `isAffectedByToolFn` returns false for a
   road template, which is the stock bus station's behaviour too.
6. Drag the catenary tool across the **lower** level and across a support.
   Expect no change and no error - `upgradeFn` gates on the slot being rail's
   precisely because `SwapModule` would otherwise rename whatever it found.

Watch for: a bus platform turning into a track module (the failure mode the gate
exists for), `the rail upgradeFn failed`, and the tall catenary pole
(`power_pole_1`, 10.6 m) - it is fine at +12 with nothing above, and it is the
thing that will not fit once there is a level above.

**Read the log, do not trust the cursor.** This test has now failed twice with
the tool offering the upgrade and nothing happening, because both failures were
refusals rather than errors - once in `isAffectedByToolFn`, once in `upgradeFn`.
`upgradeFn` therefore logs its decision on every branch, deduped, and step 1
should produce:

    [multi-layer] upgrade slot=<id> catenaryAdd -> ::/trainstation___/infrastructure/track/simple/simple_catenary.street_template

A refusal says so in the same place - `is empty`, `family=street`,
`is not a track module`, or `neither a track type nor a catenary change`. If
nothing at all is logged while the cursor still offers the upgrade, then
`upgradeFn` is not being called and the fault is above it, in the engine's
mapping from the click to a slot id.

The cheap corroboration, if the log is ever unavailable: the `built:` line's
**edge-list count must go up by one** the first time a row is electrified. Rail
pre-creates four track edge lists (standard, standard_catenary, high_speed,
high_speed_catenary) and resolves them by name, so a `simple_catenary` row has
to append a fifth. A count that does not move means no renamed module reached
`updateFn`.


## T5a - the concourse *(new, untested)*

The module that supplies the station's catchment and waiting capacity, for both
levels. `PLAN.md` Phase 10.

**Placement first, because the concourse broke it once.** The concourse is
seeded, so its geometry is present when the engine runs the placement collision
check - unlike a support, which the player adds afterwards. Its first version
was 10 m deep and reached the entrance's **snapPoint** at local y = -10, which
is exactly where a road snapped to the station lands:

1. **Snap the station to an existing road.** It must place. This failed before,
   while placing in free space worked, because free space has no road for the
   concourse to collide with - so *free space placing fine is not evidence*.
   **Re-run this: the concourse went from 24 to 40 m wide on 2026-10-22**, and
   it is seeded, so that is 16 m more geometry checked against the world at
   placement. The depth is unchanged, which is the direction the road was in,
   but the frontage it sweeps is now a full deck tile. Try it in a town, not
   just against a lone road.
2. **Connect a road, demolish the concourse, then place it again.** It must go
   back. This failed before for the same reason: re-placing re-checks against
   the road that is now there, while the seeded one survived because it
   predated the road.
3. Compare the two logged positions for the same rebuild - `concourse cells
   (x,y) 20x6` against `snapPoint: transl=(...)`. They must not overlap, and
   `skipCollisionCheck` will not save you: it governs a slot against the rest of
   the construction, not the construction against the world.

Then the functional part:

4. Place a station. One concourse should be seeded over the bus entrance, and
   the log should say `seeded: ... + 1 concourse` and then
   `concourse: 1 catchment circle(s) and +100 pool capacity on each of 2 stations`.
5. **The warning that used to fire as designed should now be absent.** No
   `a station had no catchment of its own` on a freshly placed station.
6. Confirm passengers still board on both levels - the catchment is now coming
   from a different place, so this is a real regression check, not a formality.
7. **Remove the concourse.** Expect the backstop to fire, with a log line
   naming the concourse, and expect the station to keep working on the default.
   Decide whether that is the behaviour you want (Phase 10, "Still to decide").
8. Put it back. Then add a **second entrance** - a second concourse slot should
   appear over it, and placing a concourse there should report
   `2 catchment circle(s)` and double the pool capacity.
9. Check the catchment does not double-count: the numbers in the log should be
   exactly `circles x radius` from concourses only. Stock station buildings are
   counted by their own family's hook, and `applyConcourse` filters to
   `ml_concourse` slots precisely so they are not added twice.
10. Swap the entrance for an exit module, or vice versa. The concourse should
   **stay put** - its slot id drops the entrance's variant digits for exactly
   this reason.
11. Save, reload, then force a rebuild. The concourse slot id is ours, so this is
   the same round-trip risk as the supports in T7.

The art is a placeholder - two brick walls either side of the road - and is
meant to look unfinished. Step 3 of Phase 10 replaces it with a tunnel portal.


## T5b - can a passenger reach the upper platform? *(pass 2026-10-22)*

Since 2026-10-12 no station building is seeded on either level - the concourse
replaces both. The rail main building was also the upper level's authored
pedestrian connection (`person_lanes` and `linkable_person_lanes`,
`trainstationutil.lua:436-445`), so that route now runs only through
`linkLevels` and out via the street entrance.

**Run this as the no-catchment interchange test, which also covers T6 step 3.**
Build a station with **nothing in its catchment** - open country, no buildings -
with nothing but the seeded modules, a bus line to a town at one end and a train
line to a station with its own catchment at the other. An empty catchment
generates nobody, so every passenger on a platform arrived on one line and is
leaving on the other, and throughput is the proof. The confound it removes is
real: a passenger on the elevated platform could otherwise have walked in from a
house nearby.

Two things the setup needs, or it will look like a failure that is not one:

- **no alternative route** between the two ends, or the pathfinder will go round
  the interchange rather than through it, and
- **both directions watched.** Our link is one lane welded to existing person
  nodes by coincident position, and `createLane`'s last argument is *linkable*,
  not *one-way* (`townbuildingutil.lua:207-211` passes `true` for the curve
  named `entrance_linkable`). A one-way link would pass bus-to-train and fail
  train-to-bus.

Passed 2026-10-22, both directions. Note what it does **not** prove: passengers
**teleport** between the levels rather than walking, and a stock island platform
with no underpass works too, so interchange inside a StationGroup does not need
a walkable path and this test cannot validate `linkLevels` (root `NOTES.md`,
"The transfer is instant, and no one walks it"). The follow-up that would is
T6 step 5.


## T5 - supports

Known to be imperfect; the point is to confirm *how* imperfect, for the README.

**As of 2026-10-09 the elevated deck has no bridge under it**, so this section
carries more weight than it did: supports are now the *only* thing that can
hold the deck up, and track tiles get support slots where before the viaduct
covered them.

0. **Existing saves have orphaned supports.** As of 2026-10-22 a deck tile has
   one support slot instead of five, so a support placed in cells 2 to 5 of a
   tile no longer has a slot. Expect `modules with no slot: N` on the first
   rebuild of an older save and expect those supports to vanish; re-place them.
   Nothing is published yet, so the id packing is still free to change.
1. Place supports under the platform tiles **and under the track tiles**. They
   should line up with each other, and **one support should span a whole module**
   with a 0.2 m seam to the next - not five short ones with gaps.
   The log line to check is `support footprints: ... track 5.0x40.0 x1`.
1b. **Place one under a tile that overlaps the bus station at grade** - a column
   extended over the bus platforms is the case. The cell is 5 x 40 m now, so it
   catches things a 7.8 m cell missed, and `clipEmptyOurSlots` shortens the
   click target rather than letting the engine refuse the slot silently:

       empty slots of ours cut clear of occupied ground at their own level: N;
       buried with no cut that keeps the origin: M

   A support that cannot be placed anywhere along a tile the deck occupies, with
   `N = 0` in that line, means the cut is not firing and the rectangle is still
   fouled.
2. Confirm the elevated track is happy with nothing beneath it - no engine
   complaint, no terrain rising to meet it, and a train still runs. `NOTES.md`,
   "The elevated track carries no bridge", flags this as the one open question
   the change introduces: `BRIDGE` is what Phase 0 actually tested.
3. Leave a gap and drive a road through it. A gap is a whole 40 m tile now.
3b. **Try a support under the track tile the player's own track connects to.**
   It is refused as a collision (2026-10-22) - the embankment is in the cell and
   no slot flag reaches a world collision. Confirm it is only *that* tile: a
   support under the next tile along, and under the platform beside it, must
   still go in. If a connected track row refuses supports along its whole
   length, that is a different problem and a release blocker.
4. Place supports under a station building. Expect them to sit under one side
   and miss the other - the known Phase 7 bug. Record which building and how
   far off, since `PLAN.md` now says the per-slot-type footprint table cannot be
   right for `rail_building_size2`.
5. Remove supports again.
6. Count models: a size3 building's support cells are of the order of a hundred
   models each. Watch the frame rate with a station fully supported.


## T6 - the pedestrian link *(new refusal path, untested)*

1. Confirm `linked levels:` in the log, with two plausible endpoints.
2. If `skipped N person node(s) that coincide with a vehicle lane node` appears,
   note it - it means the refusal is doing real work and is not just theory.
3. Confirm a passenger can actually get from a bus at grade onto a train above.
   This is the T5b no-catchment test; do not run it twice. **Without it the
   station looks ignored rather than broken**, because a journey is only taken
   when the whole route exists.
4. If `no pedestrian link possible` appears, the two levels are isolated and
   that is a release blocker, not a limitation.
5. **Is the link doing anything at all?** Passengers teleport rather than walk
   (T5b, 2026-10-22), so make `linkLevels` inert - an early return, keeping its
   diagnostics - and repeat the T5b test. Transfer that still works means the
   link is optional and the lane is art, not function; transfer that stops means
   it is load-bearing. One deploy, one run, and it gates Phase 10 step 2.

The thing this test cannot be allowed to produce is the assertion failure in
`TransportNetworkSystem.cpp:116`. If the game dies on placing or editing the
station, that is what happened, and the refusal above missed a case.


## T7 - savegame round-trip

The only test that can catch a slot-id scheme that does not survive
serialisation, and it needs the second step to mean anything.

1. From `ml-beta-1`, with supports placed and both levels edited: save, quit to
   desktop, relaunch, load.
2. Check the station is intact and both lines still run.
3. **Now force a rebuild**: add one module and remove it again. Reloading does
   not re-run `updateFn`, so only this makes the restored `params.modules` meet
   the code that reads it. A stale or re-keyed id shows up here and nowhere
   else - as `N modules will be removed`, a support in the wrong place, or an
   empty deck.
4. Repeat for a support module specifically, since its ids are ours
   (`600000000 + slot.id * 10 + k`) and the rest are the stock families'.


## T8 - mod removal

**Decided 2026-10-22, before the test rather than after it: assume the worst
grade.** *"Let's assume C. Even if it's A or B now, it might very well degrade
to C later on. For mods like these, having to keep the mod enabled while there
are any stations in the save is acceptable."*

So the three grades below are no longer something to measure and write down.
They are a promise the mod declines to make: **keep the mod enabled while a
save contains any multi-layer station.** The reasoning is about versions, not
about today - the station's geometry, slot ids and module names all come from
the mod, so a removal that grades A this week can grade C after any change to
any of them, and a promise that has to be re-earned every release is worth
less than no promise at all.

| grade | what it looks like |
| --- | --- |
| A | the save loads, the stations are gone, everything else intact |
| B | the save loads, but a line or a vehicle needs repairing by hand |
| C | the save does not load |

Where the promise now lives, which is the deliverable this replaces:

- `_metadata/modinfo.json` - the listing text players read before installing,
  in capitals near the top;
- `README.md`, "Removing the mod", with the reasoning;
- `mod.json`, `severityRemove: "Warning"`. **That is the loudest value there is
  evidence for**: across the base game, the DLCs and every mod on this machine,
  15 `mod.json` files use only `"None"` (13) and `"Warning"` (2), and the enum
  itself is registered in the binary with no readable value list. A louder
  string may simply not exist, and an invalid one risks the mod not loading at
  all - which is a worse failure than a mild dialog. If `"Critical"` is ever
  worth trying, the validator is the cheap check, and the game has to be closed
  for it.

What is still worth running, and it is two minutes rather than a session:

1. **The recovery path.** Deactivate for a save with a station, load (expect
   anything), then **reactivate and load again**. A player who toggles the mod
   by accident or loses it to a failed download needs to know whether going
   back works. This is the only question here whose answer changes what a
   player should do.
2. **What the dialog says.** Note the wording the game shows when deactivating,
   once, so the README's claim and the game's own warning do not contradict
   each other.

Neither is a release blocker. A station that has to be bulldozed before the mod
comes out is a documented condition of use.


## T9 - the awkward cases

Each one is a thing a player does in the first hour, and each one has a specific
mechanism behind it rather than being a general poke. Quick to run; the value is
in knowing what failure looks like before you see it.

**All seven pass, 2026-10-22.** The notes below stay as the protocol and carry
what each case was watching for; the results are in the table at the bottom.

1. **Place on a slope.** *As expected.* Level 0 flattens its own footprint because it asks to;
   level +1 emits no terrain alignment at all and its edges set
   `alignTerrain = false`, so the deck sits at exactly +12 above the
   construction's origin whatever the ground does (`NOTES.md`, "Terrain:
   nothing to disable, just stop asking").
   The thing to look at is the **supports**, and this is newly interesting: a
   support is drawn from z = 0 to z = 12 *in construction space*, so it does
   not follow terrain, and it is now 40 m long instead of 7.8 m - eight times
   the ground to disagree with. Expect a support to float where the ground
   falls away and to be buried where it rises. Record how bad it is on a gentle
   slope versus a steep one; "unusable on anything but flat" is a limitation
   worth writing down, and "a support sinks into the hill" is cosmetic.
2. **Place two of them adjacent**, then overlapping in plan if the game lets
   you. *As expected.* Two things are being tested and only the first is about geometry: the
   concourse is now **40 m of seeded geometry** checked against the world, so
   two stations side by side collide sooner than they used to (T5a's mechanism,
   with a station instead of a road). The second is that each station is its own
   **StationGroup** with its own name, and two groups 50 m apart is exactly the
   configuration where the engine's own catchment sharing gets interesting.
   Neither is expected to break; both are unobserved.
3. **Place one in 1930 and one later.** *Resolved by making 1930 the earliest.*
   The station used to be available from 1900 while the track it seeds -
   `track/standard/standard` - does not exist until 1930 (round sixteen's
   table), so an 1900 station came with a track type from the future.
   `availability.yearFrom` is now 1930 for exactly that reason, which makes the
   case moot rather than passed. What is left is cosmetic and certain: the menu
   icon is a hardcoded `station_era_c.tga`, so a 1930 station advertises itself
   with era-c art.
4. **Bulldoze one with lines running through both levels.** *No crash,
   2026-10-22 - the game warns the line is no longer connected and rebuilding
   the platform reconnects it.* The most dangerous test in the file, and the only one that can take the game down rather than
   produce a bad result: the construction holds two `station` records, three
   subconstructions, and a **hand-built `PERSON` lane** between the levels, and
   a person lane sharing a node with a vehicle lane is the
   `TransportNetworkSystem.cpp:116` assertion failure (root `NOTES.md`). If the
   game dies here, that is what happened and `vehicleNodeKeys` missed a case.
   Do it with a bus and a train both **mid-journey**, which is the state the
   engine has least reason to handle gracefully.
5. **Build a road through the structure at grade.** *As expected, and a second
   concourse can be placed on the far side of the new road - the per-entrance
   slot derivation paying for itself.* A gap is a whole 40 m tile now, so leave one deliberately rather than expecting to thread between
   7.8 m piers. Two outcomes are both informative: a road **refused** where
   nothing of ours stands means our geometry claims more than it draws, and a
   road accepted straight **through** a support means the block is not
   colliding at all - which is the collider-less behaviour the open question
   asks about, arriving by accident.
6. **Draw a track from the elevated level down to ground.** *As expected.* Expect an
   embankment; it is accepted (`NOTES.md`, "The player's connecting edge
   earthworks"). Two observables now rather than one: whether it **buries the
   lower level**, which is the condition set for revisiting the decision, and
   how far along the connecting tile it reaches - that reach is what refuses a
   support under the tile the track leaves from, which is the accepted
   limitation of 2026-10-22.
7. **Place against a curved road.** *As expected.* New, and it follows from the widening: the
   entrance snaps by its own snapPoint, and the concourse is a 40 m straight
   block at the frontage. On a curve the two cannot both be flush, so either
   the station refuses to place or the concourse's ends cut into the road's
   verge. Worth knowing which, because a straight road is the only thing any
   session has placed against.


## Results

| test | result | notes |
| --- | --- | --- |
| validator | | |
| T1 place + passengers both levels | pass 2026-10-09 | both levels carry passengers and **transfer between them** - settles the StationGroup question |
| T2 edit elevated level, unconnected | pass 2026-10-09 | underpasses, extra tracks and extra platforms all work |
| T2 edit elevated level, **track connected** | pass 2026-10-09 | was broken by the `snapNodes` conversion; fixed |
| T2 extend the deck to the entrance *(new)* | **pass 2026-10-21** | first attempt was a half pass: the tile over the entrance was withheld as designed, but a column is four tiles and the entrance covers only one of them, so the deck grew around the road and continued past it, leaving a hole over the crossing that could never be removed. Second pass added the same day and confirmed in the next session - `deck columns blocked at y = -22.5, -20.0, -17.5; rail slots not offered because the deck cannot reach past one: 104 (y <= -17.5)`, nothing offered on that side, and the far side still extends (columns at y = -5, 0, +5 all took modules). Round sixteen |
| T2 edit elevated level, **re-check after the deletion bug** | pass 2026-10-12 | add and delete platforms and tracks, then re-add and delete again. Regressed twice in one day and both causes were elsewhere: a seeded concourse, whose slot is derived from the street entrance, and then the zeroed rail slot reservations added while chasing it - a track module's only model is invisible and collider-less, so the slot rectangle is the only thing the cursor can find it by. See `NOTES.md`, "Round seven" |
| T3 edit lower level *(new)* | pass 2026-10-09 | second bus line and second entrance both work |
| T4 upgrade tools *(new)* | **pass 2026-10-22** | steps 1-3 and 5-6 on 10-21: the catenary goes on, an **electric locomotive runs**, and it comes off again; removing it raises the game's own "line is incomplete" notice, which clears when it goes back on - correct behaviour, not a fault. Two earlier failures, same symptom both times: 10-09 `isAffectedByToolFn` would not resolve on the tool thread; 10-12 `upgradeFn` declined on a gate reading `entry.metadata`. Step 4 closed 10-22: dragging track from the Tracks menu **collides, as it should** - that is the builder, not an upgrade path. The two real routes both work, the upgrade tool and replacing the module. Separately parked: the upgrade tool lists no high-speed variant. Round seventeen |
| T5a concourse *(new)* | **pass 2026-10-22**, step 7 open | snapping the station to an existing road works with the concourse seeded at its full 40 m width, re-confirmed after the widening. seeded again as of 2026-10-21 and it arrives where it should: `seeded: ... + 1 concourse`, `1 catchment circle(s) and +100 pool capacity on each of 2 stations`, no catchment warning, and it deletes and goes back again (slot `820015500`, `12->11` then `11->12`). The mesh reads as intended - a solid block with a hole the entrance road fits through. Steps 1-2 pass 10-22: the station places **snapped to a road** with the concourse seeded, and the concourse goes back after a demolish with the road already there - the asymmetry about seeded geometry being checked against the world is cleared. Round six's condition also run that day: a **platform deletes** with the concourse in the build. Round seventeen |
| T5 supports | **place and delete pass 2026-10-22** | solid blocks, filling their cells, lining up with each other. A support **deletes** with neighbours either side - confirmed twice: first against the engine's placeholder, then again with the real `support_block.mdl` loading, whose collider is its mesh and whose slot rectangle is zeroed by the trim. That is round three's feared configuration exactly, and it deletes. One cell inside a bus platform's rectangle is now offered with a shortened click target rather than withheld | One cell, inside the bus platform's own rectangle, is never offered; accepted, see round twelve |
| T5b passengers reach the upper platform *(new)* | **pass 2026-10-22** | run as the no-catchment interchange test: empty catchment, bus one end, train the other, so throughput is the proof. Transfers **both ways**. They **teleport** rather than walk, which a stock island platform with no underpass does too - so this says the station works and says nothing about `linkLevels` |
| T6 pedestrian link *(new)* | **steps 1-4 pass 2026-10-22**, step 5 open | `linked levels: (20.0,-15.0,5.0) -> (20.0,-15.0,13.1)` on every rebuild, from 108 grade and 336 elevated person nodes, and no refusal line. Step 3 passed as the T5b interchange test, in both directions, so the levels are not isolated and the blocker is closed. Step 5 - whether the link is what carries it - is the open one, and the teleport says probably not |
| T7 save / reload / rebuild | **steps 1-2 pass 2026-10-22**, step 4 to re-run | saved, loaded, and the station is fully functional - both lines still run. Module editing after the reload (placing supports, which is what turned up the support sizing) exercised the rebuild path too, so step 3 is covered in substance. **Step 4 wants re-running**: support ids changed the same day, one cell per deck tile instead of five, so no support in any existing save has been through a save with the ids it will ship with |
| T8 mod removal | **n/a - declared, not tested 2026-10-22** | the mod promises the worst grade instead of measuring one: keep it enabled while a save holds a station. The recovery path (deactivate, reactivate, reload) is still worth two minutes |
| T9 awkward cases | **pass 2026-10-22** | all seven as expected. The two that mattered: **bulldozing with a bus and a train running through both levels did not crash** - the `TransportNetworkSystem` assertion did not fire, so `vehicleNodeKeys` holds - and the game's "line is no longer connected" notice is correct behaviour, cleared by rebuilding the platform. A **second concourse** can be placed across a road driven through the structure. Case 3 was made moot instead of passed: `yearFrom` is 1930 now, which is when the seeded track type starts to exist |


## Before publishing

Not tests, but on the same checklist:

- `_metadata/` has no listing images. `pick_single_platform_side_1` ships `0.png`
  and `1.jpg`; there is a generator at
  `pick-single-platform-side/tools/make_listing_image.ps1`.
- There is no `strings.json`, so every language shows the English literals. That
  is acceptable - a plain-English msgid falls through to itself - but it is a
  choice, not an oversight.
- The first publish writes `_metadata/mod.io_fileid.txt` into the **deployed**
  folder. Copy it back into the source tree and commit it, or the next publish
  forks the listing (root `NOTES.md`).
- **Decide what is frozen.** From the first public release these are savegame
  keys and cannot change without orphaning what players have built: the
  construction resource name, the module resource name, the slot type
  `ml_support`, `SUPPORT_SLOT_BASE` and the `slot.id * 10 + k` packing, the
  subconstruction tag bases (street 1.., rail 101..), and any construction param
  key or `values` ordering - of which there are now deliberately none.
