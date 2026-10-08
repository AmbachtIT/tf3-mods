# Multi-layer stations - probe mod

Throwaway research mod, `modId` `multi_layer_probe_1`. Not for publication. It
answers phases 0, 1 and 3b of [../PLAN.md](../PLAN.md) in a single game launch.

Log prefix `[ml-probe]`. Every probe logs what it emitted, so the log says
whether the script ran at all before you go looking for geometry.

## What it adds

Three constructions, all under **rail buildings**, at the end of the list
(`order` 99000-99002), plus one module under **building modules**.

| probe | asks | pass looks like |
| --- | --- | --- |
| **ML probe: bridge edge +12 m** | Does `edgeType = "BRIDGE"` work from inside a construction? Phase 0. | A viaduct with pillars at +12 m, terrain untouched underneath, and a track you can draw to either end |
| **ML probe: tunnel edge -12 m** | Same for a heavy rail tunnel at -12 m on `tunnel_b`. Phase 1. | A tunnel at depth, terrain untouched, both ends connectable |
| **ML probe: stacked slots** | superseded - not selectable, see step 5 | - |
| **ML probe: block** | superseded, the old slot probe's module | - |
| *modifier on the stock rail station* | Can a module go in a slot at +12 m? Does `postConstructionModifiable` work? Phase 3b, and Phase 2 via **ML: strip terrain**. | See step 5 |

Each construction plants a marker and four bollards at its own level, so a probe
that renders nothing still shows you where it is. **Markers but no viaduct or
tunnel is the answer, not a failed deploy** - it means the edge type did not
take.

Note on what you see: the marker (`marker_exclamation.mdl`) is 26 m tall and
animated, so it is unmissable. The "pillars" (`era_c_street_pillar.mdl`) are
11 cm x 84 cm bollards, so they are effectively invisible - "two exclamation
marks" is the correct appearance of a working probe, not a half-failure.

## Results so far (2026-10-08)

| probe | result |
| --- | --- |
| bridge edge +12 m | **PASS.** Viaduct renders, terrain untouched, player track connects and works. |
| tunnel edge -12 m | **PARKED.** Tunnel renders and connects; the player's connecting track trenches on flat ground. Level -1 is out of scope for now - see `../NOTES.md`, "Parked: level -1". |
| stacked slots | **Blocked.** Placeable but not selectable; replaced by the rail-station modifier. |


# Running the probes

**For the current round, follow [TESTS.md](TESTS.md) instead.** It is a
run-from-nothing protocol - no save needed - covering T1-T8 with a results table
to fill in. The sections below are the original per-probe notes, kept for
reference and for the parked level -1 work.

Keys below are read out of `settings_keys_v3.lua`, so they are the bindings
actually in use:

| action | key |
| --- | --- |
| toggle underground mode | **G** |
| raise during placement | **.** or Keypad + |
| lower during placement | **,** or Keypad - |
| place without snapping | **C** |


## Step 1 - validate, before spending a launch

Close the game first, then:

```powershell
cd C:\Projects\tf3-mods\multi-layer-stations\probe
.\deploy.ps1 -Validate
```

This is the only syntax check available - there is no Lua interpreter on this
machine. A Lua error in `probe.script.lua` would otherwise show up as "the
constructions are missing from the menu" and cost a whole launch to diagnose.

Expect `levelPc`/`levelConsole` of `Info` and `Messages: none`. Ignore the exit
code; it is not a verdict, and neither is `critical` - see the root `NOTES.md`.

**Validated clean as of 2026-10-08.** The one failure it caught was a bare
`require "/scripts/vec3.tl"`, which resolves inside the mod's own namespace
rather than the base game; see root `NOTES.md`, "From a mod, `require` needs the
`::/` prefix for base content".


## Step 2 - a game to probe in

Mods are per-savegame, and `autoActivate` is off, so the probe has to be enabled
deliberately.

Start a **new game**, and in the mod list enable:

- **Multi-layer Stations Probe**
- one of the shipped cost mods, `urbangames_no_costs` or `urbangames_sandbox` -
  each probe costs 100,000 and you will place several

Pick **flat terrain**. Flat is not cosmetic here: the whole question is whether
the terrain deforms, and on a slope you cannot tell a plateau from the hill that
was already there.

A fresh save also keeps the probes out of a real game, which matters because
`severityRemove` is `Warning` - removing this mod from a save that contains
placed probes will complain.


## Step 3 - confirm it actually loaded

Open a tail on the log in a second PowerShell window and leave it running for
the whole session:

```powershell
Get-Content "C:\Program Files (x86)\Steam\userdata\49924974\3493540\local\crash_dump\stdout.txt" -Wait -Tail 40 |
    Select-String "ml-probe|ERROR"
```

**There will be no `[ml-probe]` line at startup.** The probes only log from
`updateFn`, which runs when a construction is previewed or placed. To confirm
the mod loaded, look for `multi_layer_probe_1` in the `Active mods:` block near
the top of `stdout.txt` instead.

`stdout.txt` is overwritten every session, so copy it aside when you are done if
the run is worth keeping.


## Step 4 - probes 1 and 2, the edge probes

Do these on open flat ground, well away from anything else, with a short stretch
of ordinary ground-level track nearby to try connecting to.

**Probe 1, bridge.** Open the rail construction menu, buildings, and scroll to
the very end - **ML probe: bridge edge +12 m**, with a stairs icon.

1. Hover it over the ground. `updateFn` runs on preview, so the log should
   already say:
   `[ml-probe] bridge probe: edge at z=12.0 edgeType=BRIDGE via ::/infrastructure/bridge/concrete.bridge, 1 edge list(s), 1 alignment entry`
   No line means the script failed to load - go back to step 1.
2. Place it.
3. Look at four things, in this order:
   - **Markers and pillars floating at +12 m?** The script ran and its geometry
     landed.
   - **A viaduct deck with its own pillars reaching the ground?** This is the
     Phase 0 answer. Pillars and abutments mean `BRIDGE` works from inside a
     construction.
   - **Terrain still flat underneath?** Then the tiny `LESS` grade anchor is
     inert, which is what the real mod needs.
   - **Can you draw track to it?** Start a track from the ground-level stub and
     aim at either end of the probe. If it snaps and climbs, free nodes at
     height work.

**Probe 2, tunnel. Parked - skip this.** Level -1 is out of scope for the first
working version; the construction already proved it can own a tunnel edge. Left
here for whenever it is picked up again, with the follow-ups recorded in
`../NOTES.md` under "Parked: level -1".

**ML probe: tunnel edge -12 m**, the next entry.

1. Press **G** for underground mode before placing - the probe sets
   `undergroundView = true`, which is what enables underground rendering and
   snapping for it.
2. Place it, then check the same four things: markers at -12 m, actual tunnel
   geometry, terrain undisturbed above, and whether an underground track will
   connect to either end.
3. This one uses `tunnel_b`, the rail tunnel with the biggest envelope
   (12.16 m) on purpose. If its tunnel pokes above ground or fights the surface,
   the 12 m pitch needs to become 13.


## Step 5 - probe 3, the slot layer on the stock rail station

**This replaces the standalone `ML probe: stacked slots` construction**, which
could be placed but never selected - a construction with no station-like
subconstruction has no entity window at all, so its slots were unreachable (root
`NOTES.md`, "A construction is only selectable if it contains a station-like
component"). The old probe is left in the mod so existing saves do not break;
ignore it.

Instead the mod now adds the slot layer to the **stock modular rail station**
via a `loadConstruction` modifier - a construction that is already selectable,
already has a modules list, and is what the real mod will wrap anyway. While
this mod is active, every modular rail station gets the extra layer.

1. **Place an ordinary modular rail station.** With at least one passenger
   platform. The log should report, at placement:
   `[ml-probe] added N upper slots at +12.0 (type ml_upper_slot, slot.height unset), M slots total`
   And once at startup:
   `[ml-probe] patched 4 rail station templates, stock updateFn at ::/stations/rail/...`
   No startup line means the modifier never fired.
2. **Check the three new params** appear in the placement toolbar: **ML: upper
   slots**, **ML: slot height**, **ML: strip terrain**.
3. **Select the placed station.** Do the three params appear in its entity
   window? That is the `postConstructionModifiable` answer, and the real mod's
   level switch depends on it.
4. **Change one and watch the log** for a fresh `added N upper slots` line. A new
   line means a param change on a built construction re-runs `updateFn`.
5. **Place the module.** In the station's modules list, find **ML probe: upper
   marker** - it only fits `ml_upper_slot`, so it cannot land anywhere else. Does
   a 26 m exclamation mark appear **12 m above a platform**? The log says which
   slot and at what z:
   `[ml-probe] upper module placed in slot <id> at z=12.0`
   That is the real question: can a module be placed into a slot at height and
   render there.
6. **Set ML: slot height to 12 m** and try again, to see whether the undeclared
   `Slot.height` field changes anything about reach or hit-testing.
7. **Set ML: strip terrain to On.** Does the station stop flattening its
   footprint? That is Phase 2, folded in for free.

### Superseded: the standalone slot probe

This one has an order to it, and each step answers a different question.

1. **Place ML probe: stacked slots** on flat ground. The log should say:
   `[ml-probe] slot probe: 2 slots, slot.height unset, editLevel param = 2`
2. **Click the placed construction** to open its entity window. Does it offer
   **Edit Level** and **Slot height**?
   - Yes -> `postConstructionModifiable` works. That is the single most
     important answer in the whole probe set, because the real mod's level
     switch is built on it.
   - No -> the level switch needs a different mechanism, and option A gets more
     expensive.
3. **Change Edit Level** to `+1`. Watch for a *new* log line reading
   `editLevel param = 3`.
   - New line -> changing a param on a built construction re-runs `updateFn`,
     so the mod can regenerate slots per level.
   - No new line -> it does not, and showing one level's slots at a time is not
     possible this way.
4. **Place the module.** With the construction selected, find **ML probe: block**
   in the modules list and click on the probe, aiming at where the two slots
   overlap. The log says which slot took it:
   - `module placed in slot 1000001 at z=0.0` -> the picker took the **ground**
     slot
   - `module placed in slot 2000001 at z=12.0` -> it reached the **upper** slot
   - `result.probeSub is nil` -> the host/module contract is not what we
     assumed; stop and tell me, this needs re-reading rather than guessing
5. **Now set Slot height to 12 m**, bulldoze the module, and place it again.
   - **Different slot wins** -> the engine reads the undeclared `Slot.height`
     field, the picker is z-aware, and all three levels can stay clickable at
     once. This is the good outcome and it simplifies the UX a lot.
   - **Same slot wins** -> the picker ignores z, and the real mod must emit only
     the active level's slots. Which is the plan anyway, so this is not a
     setback.


## Step 6 - what to send back

- Every `[ml-probe]` line from the session.
- Any `ERROR` line, and any line naming `probe.script` or `multi_layer_probe_1`.
- Whether the terrain deformed under or over any probe.
- A screenshot of each probe, ideally from a low angle so the space underneath
  the bridge probe is visible.

For comparison, the root `NOTES.md` records what a clean session's warnings look
like - React GUI chatter, gamepad key clashes, an empty-texture error at the
main menu. Anything outside that table is worth quoting.


## Failure triage

| symptom | likely cause |
| --- | --- |
| no `[ml-probe]` line even on hover | mod not enabled for this save, or a Lua error in `probe.script.lua` - search the log for `probe.script` |
| constructions missing from the rail buildings menu | the `.con` desc was rejected; the log names the file |
| probe places but nothing at all is visible | `updateFn` returned but the subconstruction was dropped - check the log's model count |
| markers visible, no viaduct or tunnel | **this is a result**: the edge type did not take from inside a construction |
| terrain deforms anyway | the `LESS` grade anchor is not inert; try an empty `terrainAlignmentLists` instead |
| only one end of an edge connects | `freeNodes = { 0, 1 }` indexing is off by one |


## Known unknowns in the probe itself

Guesses the first run will confirm or kill. None are worth fixing before seeing
the log.

- **`result.probeSub`.** Modules get handed the host's result table and the stock
  rail modules reach for `result.cargoStation`; ours reaches for `probeSub` by
  the same logic.
- **`freeNodes = { 0, 1 }`.** Node indices are assumed 0-based into the array
  `addEdges` builds from a 2-point curve.
- **The grade anchor.** Each probe emits one tiny `LESS` face at the origin
  rather than an empty `terrainAlignmentLists`, because the stock station
  substitutes exactly that when it would otherwise emit none
  (`modular_station.script.lua:1323-1335`).
- **No `soundConfig`.** Omitted as presumed optional.
