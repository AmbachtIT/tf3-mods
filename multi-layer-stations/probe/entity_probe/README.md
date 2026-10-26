# Entity probe - archived, not shipped

A **game script**, kept out of the shipped mod. It is the only way this project
has ever been able to see *entities*: a construction's `updateFn` runs before
its station and warehouse records become components, so nothing in
`multi_layer_station.script.lua` can ask what the engine actually made of them.

Retired from the build on 2026-10-23, once the last question that needed it was
answered. Kept because the next entity question will want it.

## Why it must not ship

It runs in **every session of every save** that enables the mod, on every
`Sim Pool` thread, and reports every ten seconds. That is right for a diagnostic
and wrong for a release.

## What it answered

- **Two station groups, one station each** - measured with
  `stationGroupSystem.getStationGroup` rather than inferred from a working
  interchange, which is what the earlier wrong answer had been. There is no API
  to join them.
- **Both levels reach the same stock**, via
  `catchmentAreaSystem.getStationCatchables`, which is what made the concourse
  into a warehouse and got freight across the levels.
- **Why the rail level's tab reads `Tram station`** - carriers `RAIL -> TRAM`
  from modes `TRAIN+TRAM_TRACK`, identically on all seven rail terminals. A
  vanilla label bug, not ours. See `../../NOTES.md`, "The `Tram station` label
  is vanilla's".
- That `getLineStationProblems` and `getLineProblems` reported **nothing**
  world-wide, which is what finally pointed at the test lines rather than the
  construction - both stops of both lines had been set to load.

## Re-enabling it

1. Copy both files into `mod/multi_layer_stations_1/content/`.
2. Add `"ml_probe.gs.lua"` and `"ml_probe.script.lua"` to the `files` list in
   `mod/multi_layer_stations_1/_content.json`.
3. `.\deploy.ps1` from `multi-layer-stations/`, then restart the game.

Log prefix `[ml-probe]`, deliberately distinct from the construction's
`[multi-layer]` so the two grep apart.

## Known gap, if you build on it

`api.type["enum"].Carrier` did **not** resolve at runtime, so `enumName` fell
through to `tostring` and carriers and transport modes printed as raw integers.
They were decoded against the declaration order in the tealdefs
(`api/tealdef/api/type.d.tl:403-418` for `Carrier`,
`base/tealdef/scripts/construction/construction_util_serialized.d.tl:13-29` for
`TransportMode`), and a bus station reporting `ROAD` with `BUS+TRUCK` is the
control that confirms the reading is 0-based.

Worth hardcoding both name tables in any successor rather than trusting the
enum lookup.
