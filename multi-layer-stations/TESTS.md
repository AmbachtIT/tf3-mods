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

Prerequisite: close the game and run `.\deploy.ps1 -Validate`. Expect
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
| `seeded: rail 4 tiles (160 m, era c) + station building + 1 bus platform` | `createTemplateFn` ran |
| `rail slot types: ...` | the rail family's slot inventory, for checking against `addSupportSlots` |
| `support footprints: ...` | what size support slot each thing above got |
| `snapPoint: transl=(...) fromStreetResult=false` | `false` is correct - the module's snap point won, not the hook's default |
| `built: N support slots, 2 subconstructions, 2 stations, ...` | the summary; **2 stations is the number to check** |
| `linked levels: (...) -> (...)` | the pedestrian link was created |
| `module add/remove slot=... via=street\|plain modules=N->M` | one line per module edit. `via=street` means the paired-platform rule ran; `N->M` is the map size, and a delete that is being applied shows `M = N-1` |
| **`track edge list N has ... and no snapNodes`** | module editing will break as soon as a track is connected |
| **`N support module(s) have no slot any more`** | the level above them was removed; the engine will drop them |
| **`no pedestrian link possible`** | T6 failed - no interchange between levels |
| **`a station had no catchment of its own`** | `MAIN_BUILDING_SLOT` no longer lands in a real slot - likely a game update |
| **`module '...' belongs to neither stock family`** | a module was routed by guesswork |
| **`terminateConstructionHook called twice`** | should never fire; if it does, the lift is being suppressed |

Nothing in that list should appear in bold during a clean run.


## T1 - place one, look at it

The baseline, and the point is to establish a known-good state to edit from.

1. Road buildings tab, passenger filter, **Multi-layer Station**. Place it on
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
4. Take the **track-type tool** (high speed) and drag it over the elevated
   track. Expect the track type to change along the row.
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


## T5b - can a passenger reach the upper platform? *(new, untested)*

Since 2026-10-12 no station building is seeded on either level - the concourse
replaces both. The rail main building was also the upper level's authored
pedestrian connection (`person_lanes` and `linkable_person_lanes`,
`trainstationutil.lua:436-445`), so that route now runs only through
`linkLevels` and out via the street entrance.

One check, and it is a behavioural one because nothing about this shows up as an
error: run a train and a bus line through a station with **nothing but the
seeded modules**, and confirm passengers actually board on the upper level. A
platform that is unreachable on foot looks exactly like a platform nobody wants
to use.

If they do not board, place a rail station building by hand. If that fixes it,
the missing piece is the lanes rather than the catchment, and the concourse has
to carry a person lane of its own up to the deck - which is Phase 10 step 3's
job anyway, since that is where the stairs art goes.


## T5 - supports

Known to be imperfect; the point is to confirm *how* imperfect, for the README.

**As of 2026-10-09 the elevated deck has no bridge under it**, so this section
carries more weight than it did: supports are now the *only* thing that can
hold the deck up, and track tiles get support slots where before the viaduct
covered them.

1. Place supports under the platform tiles **and under the track tiles**. They
   should line up with each other.
2. Confirm the elevated track is happy with nothing beneath it - no engine
   complaint, no terrain rising to meet it, and a train still runs. `NOTES.md`,
   "The elevated track carries no bridge", flags this as the one open question
   the change introduces: `BRIDGE` is what Phase 0 actually tested.
3. Leave a gap and drive a road through it.
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
   Set up a feeder bus line into the lower level and a train line out of the
   upper one and watch a passenger complete the journey. **Without this the
   station looks ignored rather than broken**, because a journey is only taken
   when the whole route exists.
4. If `no pedestrian link possible` appears, the two levels are isolated and
   that is a release blocker, not a limitation.

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

`mod.json` declares `severityRemove: "Warning"`, which is a promise about what
happens next.

1. From a save with a station placed, deactivate the mod for that savegame and
   reload.
2. Expect the station to be gone and the save to load. Confirm the mod is
   genuinely inactive - the `Active mods:` block must not list it and
   `[multi-layer]` must not appear anywhere in the session.
3. Check the log against the clean-removal table in root `NOTES.md`: no `ERROR`
   lines, no `placeholders/` or `missing_street_terminal.con` substitution.
4. Reactivate and confirm the save still loads.

Unlike `pick-single-platform-side`, this mod adds a construction rather than
seeding a stock one, so removal destroys placed stations. That is expected; what
is being tested is that it destroys them cleanly.


## T9 - the awkward cases

Quick, and each one is a thing a player will do in the first hour.

1. Place on a **slope**. It will cut into the hill; confirm it is usable rather
   than broken.
2. Place **two** of them adjacent, and overlapping in plan if the game lets you.
3. Place one in **1900** and one in **1930**, to check era selection and that
   `yearFrom = 1900` is honoured.
4. **Bulldoze** one with lines running through both levels.
5. Place one, then build a road **through** the structure at grade between
   supports.
6. Draw a track from the elevated level down to ground. Expect an embankment -
   an accepted limitation, but confirm it does not bury the lower level, which
   is the condition `NOTES.md` set for revisiting the decision.


## Results

| test | result | notes |
| --- | --- | --- |
| validator | | |
| T1 place + passengers both levels | pass 2026-10-09 | both levels carry passengers and **transfer between them** - settles the StationGroup question |
| T2 edit elevated level, unconnected | pass 2026-10-09 | underpasses, extra tracks and extra platforms all work |
| T2 edit elevated level, **track connected** | pass 2026-10-09 | was broken by the `snapNodes` conversion; fixed |
| T3 edit lower level *(new)* | pass 2026-10-09 | second bus line and second entrance both work |
| T4 upgrade tools *(new)* | **pass 2026-10-12** (step 1) | two failures first, same symptom both times. 10-09: `isAffectedByToolFn` was delegated and would not resolve on the tool thread, so the tool never offered the station. 10-12: the tool offered it and `upgradeFn` declined, on a gate reading `entry.metadata` - a field that only exists on the `updateFn` entry. Resolved from `api.res.moduleRep` instead and the catenary tool works. The track-type tool is the same code path with the other branch; the open question is the electric loco actually running |
| T5a concourse *(new)* | | |
| T5 supports | | |
| T6 pedestrian link *(new)* | | |
| T7 save / reload / rebuild | | |
| T8 mod removal | | |
| T9 awkward cases | | |


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
