# Probe test script

A run-from-nothing protocol: no save required, no prior state assumed. Fill in
the results table at the bottom as you go.

Prerequisites, both already done: the mod is deployed to the staging area and
passes the validator. If in doubt, close the game and run `.\deploy.ps1
-Validate` - expect `level=Info` and `Messages: none`.


## What this round does and does not test

**Does:** whether the modifier fires, whether a slot layer can be added at
+12 m, whether `postConstructionModifiable` works, whether a param change
re-runs `updateFn`, whether a module can be placed into a slot at height and
render there, and whether stripping terrain alignment stops a station
flattening its footprint.

**Does not:** anything about level -1, which is parked (`../NOTES.md`, "Parked:
level -1"). Mod add/remove severity. Param migration across mod revisions.
Station grouping, which is Phase 3 and separate.

**One savegame test is included, deliberately** - T8. Everything else here is
"does the machinery work at all", which is the right thing to establish first.
But the whole option A design hangs on namespacing slot ids per level
(`stock_id + level * 10^7`), and `params.modules` is savegame state keyed by
exactly those ids. The root `NOTES.md` already records that re-keying a module
map later is **not** savegame-safe, so if ids outside the stock range do not
survive a round-trip, the scheme is dead and Phase 4 has to be redesigned. It
costs one save and one reload at the end of a session you are already in, so
there is no reason to defer it.


## T0 - make the test game

1. Launch the game.
2. New game. In the mod list enable:
   - **Multi-layer Stations Probe**
   - **No Costs** (`urbangames_no_costs`, sets `baseConfig.noCosts`)
   - **Sandbox** (`urbangames_sandbox`, sets `baseConfig.sandboxMode`)

   Both cost mods are one-line shipped mods with `severityRemove: None`, so
   enabling both is harmless.
3. **Flat terrain, smallest map.** Flat is not cosmetic - half these tests are
   "did the terrain deform", and on a slope you cannot tell a plateau from the
   hill that was already there. Smallest map just loads faster.
4. If the setup offers a start year, pick **1990 or later** so every era of
   station is available.
5. Save it immediately as `ml-probe` before building anything, so T8 has a
   clean baseline and you can get back here without redoing T0.

In a second PowerShell window, start the log tail and leave it for the whole
session:

```powershell
Get-Content "C:\Program Files (x86)\Steam\userdata\<id>\3493540\local\crash_dump\stdout.txt" -Wait -Tail 40 |
    Select-String "ml-probe|ERROR"
```

`stdout.txt` is overwritten every session, so copy it aside at the end.


## T1 - did the modifier fire?

**Question.** Does the `loadConstruction` modifier reach the stock rail station?

**Expect**, once, at load:

```
[ml-probe] patched 12 rail station templates, stock updateFn at ::/stations/rail/modular_station/modular_station.script@updateFn
```

**Pass:** that line, with a count of **12** - `makePassengerTemplate` and
`makeCargoTemplate` each insert two templates (normal and head variant) and each
is called once per era, so 2 x 3 + 2 x 3 = 12
(`modular_station.con.lua:72, 115, 159-161, 165, 208, 252-254`).
**A different count** means the stock template shape changed - still fine, note
the number.
**No line at all** means the modifier never ran. Stop here; nothing downstream
can work. Check `multi_layer_probe_1` appears in the `Active mods:` block, and
search the log for `probe_upper_slots`.

**RESULT 2026-10-08: PASS**, 12 templates, no `ERROR` lines in the session.


## T2 - are the upper slots generated?

**Question.** Does the wrapped `updateFn` run and append slots at +12 m?

1. Open the rail construction menu and hover **the ordinary modular train
   station** - not a probe construction.
2. Confirm three new params in the toolbar: **ML: upper slots**, **ML: slot
   height**, **ML: strip terrain**.
3. Place it on flat ground with at least one passenger platform.

**Expect:**

```
[ml-probe] added N upper slots at +12.0 (type ml_upper_slot, slot.height unset), M slots total
```

**Pass:** `N` is non-zero and roughly the number of passenger platform tiles.
**`N = 0`** means no slots of type `passenger_platform` were found to clone -
note it and carry on, it points at the wrong source slot type.
**No line** means the wrap failed. Look for
`stock updateFn unavailable, station will be broken`, which means `util.useFn`
could not resolve the stock function.


## T3 - does `postConstructionModifiable` work?

**The most important result in this round.** The real mod's level switch depends
on it, and no shipped construction sets the flag.

1. Click the placed station to open its entity window.
2. Look for **ML: upper slots**, **ML: slot height**, **ML: strip terrain**.

**Pass:** all three appear and are editable on the already-built station.
**Fail:** they appear only during placement. Then the level switch needs a
different mechanism and `../NOTES.md` "Editing" has to be reworked - say so and
stop, because it changes the design rather than the code.


## T4 - does a param change re-run `updateFn`?

1. With the station selected, change **ML: slot height** to `12 m`.

**Pass:** a *new* `[ml-probe] added N upper slots ... slot.height set` line
appears.
**Fail:** no new line. Then slots cannot be regenerated per level after
placement, and the "show only the active level's slots" plan does not work.


## T5 - can a module be placed into a slot at +12 m?

**The core question of the whole probe.**

1. With the station selected, open its modules list.
2. Find **ML probe: upper marker**. It declares `type = "ml_upper_slot"`, so it
   is the only module that fits the new slots and it cannot land anywhere else.
3. Click on the station, over a passenger platform.

**Expect:**

```
[ml-probe] upper module placed in slot <id> at z=12.0
```

and a 26 m exclamation marker standing **12 m above the platform**.

**Pass:** both the log line and the marker at height.
**Log line but no marker** means the module ran but its models did not reach a
rendered subconstruction - look for `no result.cargoStation to draw into`.
**Neither** means the module was never offered or the click never reached the
slot. Note whether the module appeared in the list at all; that distinguishes
"slot type not registered" from "slot not clickable".

Then: **place a second one** on a different platform, to see whether multiple
upper modules coexist.

**RESULT 2026-10-08: PASS.** Modules landed in slots 57399000, 57400000 and
57401000, all reporting `z=12`, with no `no result.cargoStation` warning. The id
arithmetic checks out: `passengerPlatformSlotId = 7400000`
(`modular_station.script.lua:42`) plus `1000 * coordI`, plus our 5e7 offset, so
57400000 is coordI 0 and the neighbours are -1 and +1.

Caveat on what you see: `marker_exclamation.mdl` is also what the game itself
substitutes for an empty or missing model, so "a placeholder exclamation mark"
is the expected *success* appearance here. Confirm by the `z=12` log line, not
by the model.


## T6 - does `Slot.height` change anything?

`Slot.height` is declared (`construction_util_serialized.d.tl:118`) and used by
no shipped content.

1. Toggle **ML: slot height** between `Unset` and `12 m`, retrying T5 each way.

**Looking for:** any difference in whether the click reaches the upper slot, how
far off you can click and still hit it, or whether the ground slot steals the
click. A difference means the picker is z-aware. No difference is a perfectly
good answer too - the real mod uses per-level slot types, so it never needs an
ambiguous click resolved.


## T7 - does stripping terrain alignment work? (Phase 2)

1. Set **ML: strip terrain** to `On`.

**Expect:** `[ml-probe] stripped N terrain alignment entries`.

**Pass:** the station stops flattening its footprint and sits on the raw ground.
Ground textures should still appear, because `groundFaces` is a separate list.

On flat terrain the visual difference will be subtle, so for this one test
place a station **on a slope** and compare `On` against `Off`. This is the only
test that wants uneven ground.


## T8 - does a module in an upper slot survive a save/reload?

**Why now:** see the top of this file. The slot id namespacing scheme is the
foundation of option A, and `params.modules` is keyed by those ids.

1. With at least one upper marker placed, save as `ml-probe-t8`.
2. Quit to the main menu. Reload `ml-probe-t8`.
3. Look at the station.

**Pass:** the marker is still 12 m up, and the log shows the
`added N upper slots` line again on load plus an `upper module placed in slot
<id> at z=12.0` line with **the same id**.
**Fail - marker gone:** a slot id of `stock_id + 50000000` does not round-trip,
and the namespacing scheme needs rethinking before Phase 4.
**Fail - marker moved to the ground:** worse, and more interesting: the id
survived but the slot it maps to did not.
**Any `ERROR` on load** is worth quoting in full.

**RESULT 2026-10-08: partial.** No crash, no errors, markers still at +12. But
the log shows **no `updateFn` output at all after the load** - only the
`loadConstruction` modifier firing. The geometry came back from the savegame
without the scripts re-running (root `NOTES.md`, "Reloading a savegame does not
re-run `updateFn`"), so this does **not** prove the slot ids round-trip. One
marker would have been enough for this much; three only added "different coordI
values coexist".


## T8b - do the slot ids still line up after a reload?

The part T8 could not reach. Forces `updateFn` to run against the restored
`params.modules`.

1. Load the save that already has upper markers.
2. **Add one more upper marker**, or bulldoze one.

**Expect:** an `added N upper slots` line, and the markers that were already
there still at +12 afterwards.

**Pass:** the pre-existing markers survive the rebuild. The ids round-trip and
per-level namespacing is safe to build on.
**Fail - the old markers vanish or drop to ground level** on the first edit
after a reload: `params.modules` keys and regenerated slot ids disagree, and the
namespacing scheme needs rethinking before any real code uses it.


## T9 - two station records in one construction (the bus deck)

**The question that now matters most.** A two-level station has one station
record per level, so interchange depends on them joining a single StationGroup.

1. Place a **new** modular train station with **ML: bus deck +12m** set to `On`.
   The existing ones will not have it; the param defaults to Off.
2. Expect, at placement:
   `[ml-probe] bus deck added at +12.0: 3 lanes, 1 terminal, N subconstructions total, 2 road stubs`
3. **Look for a 40 m slab at +12** with a marker on it, and two road stubs
   running out from either end of it at the same height.
4. **Open the line manager / create a bus line.** Does the station appear
   **once**, offering both the rail platforms and the bus deck as terminals? Or
   twice, as two separate stations?
   - once -> StationGroup joins them, interchange works, the design holds
   - twice -> they do not group, and passengers cannot transfer between levels
     without something extra
5. **Try driving a road up to a stub.** This is the untested half of
   road-over-rail: `TRACK` at +12 as a `BRIDGE` is proven, `STREET` is not.
6. **Check the pedestrian ramp.** Lane 2 climbs from the deck at +12 down to
   ground at y=32 and is `linkable`, so it should join the street network. If
   passengers can walk from the street onto the deck, the vertical-circulation
   problem has a working shape.

## Results

| test | question | result | notes |
| --- | --- | --- | --- |
| T1 | modifier fires | **PASS** | 12 templates, no errors |
| T2 | upper slots generated | **PASS** | 20-26 upper slots, 282-340 total; recomputes live as modules change |
| T3 | `postConstructionModifiable` | **no** | flag was on `template.data.params`; the UI reads `desc.params`. Design changed so it is no longer needed. |
| T4 | param change re-runs updateFn | n/a | needs T3; moot now |
| T5 | module placeable at +12 m | **PASS** | slots 57399000 / 57400000 / 57401000, all `z=12`; no cargoStation warning |
| T6 | `Slot.height` has an effect | n/a | moot - per-level slot types mean no ambiguous click |
| T9 | two station records | **both exist, not grouped** | train + bus selectable separately; bus line failed "can't connect stops" - missing `vehicleEdges`, now fixed |
| T10 | STREET at +12 as BRIDGE | **PASS** | roads drive up the stubs and connect fine |
| T11 | one-station mode | | new `ML: one station` switch |
| T7 | terrain strip works | **partly, and aimed off-target** | stripping now works (7 entries, in hook) but ground still conforms: edge lists deform terrain separately. `alignTerrain=false` added. The question that matters - does a level at +12 deform terrain - was already answered no by the bridge probe. |
| T8 | survives save/reload | **partial** | geometry survives, but `updateFn` does not re-run on load - see T8b |
| T8b | slot ids round-trip | **PASS** | 4 modules restored at 57400020 / 57401000 / 57401010 / 57401990, all `z=12`; deletions stable across rebuilds |


## What to send back

- The results table.
- Every `[ml-probe]` line from the session.
- Any `ERROR` line, and anything naming `probe_upper_slots` or
  `multi_layer_probe_1`.
- A screenshot of the station after T5, from a low angle.
- `stdout.txt`, copied aside before you relaunch.

The root `NOTES.md` records what a clean session's warnings look like - React
GUI chatter, gamepad key clashes, an empty-texture error at the main menu.
Anything outside that is worth quoting.
