# Multi-layer stations

The idea behind Multi-layer stations is to unlock the z-axis for station
construction. I want to be able to build an elevated train station with a bus
station underneath.

Scope is levels, not a free z-axis, at a 12 m pitch. **Level 0 and level +1**
for the first working version - a station at grade with another above it. One
transport family per level, and the two levels stay **two separate stations**,
which matches in-game practice and lets the player inspect and name each one.
**Level -1 is parked**; its findings are in `NOTES.md` under "Parked: level -1".

Status: **v0.1 works in-game.** A 160 m rail platform on a stone viaduct at
+12 m over a bus platform at grade, as two separate stations. Track connects to
the upper level, road to the lower, rail modules can be added to the upper
level, the terrain is undisturbed, and it survives a save/reload.

**Both levels are the game's own stock stations, delegated.** Level 0 is the
modular street station, unchanged and at grade; level +1 is the modular rail
station, turned a quarter turn so the tracks cross the bus exit rather than
running alongside it, and lifted 12 m onto a stone viaduct. Both are therefore
editable with the game's own modules, and the lower level brings the bus
station's real layout, entrance and snap-to-the-road-end behaviour.

How two stock families share one construction is written up in the root
[NOTES.md](../NOTES.md), "Hosting two stock families in one construction" - it is
the reusable part of this mod.

Accepted limitations for now:

- a track drawn from the elevated level down to grade is built as an embankment
  rather than a viaduct (`NOTES.md`, "The player's connecting edge earthworks, in
  both directions");
- the upper station is labelled a tram station, because of how carrier names are
  chosen from a station group's carriers;
- **supports** are player-placed modules that work under platform tiles but are
  misaligned under station buildings - cause known, fix written up in `PLAN.md`
  Phase 7;
- stock station buildings have ground-level entrances and read as street level
  however they are supported. Stairs placed at a platform end look right and
  carry catchment, so they are the better default until there is custom art.

```
.\deploy.ps1            # staging area; restart the game afterwards
.\deploy.ps1 -Validate  # close the game first
```

Log prefix `[multi-layer]`. Look for **Multi-layer Station** in the **road**
buildings menu, passenger filter - the level at grade decides which tab a variant
lives in and what it snaps to, so the mirror variant (road over rail) will sit in
the rail tab.

- [NOTES.md](NOTES.md) - what the install says and what the probes proved: the
  terrain mechanisms, the measured vertical budget, where the 12 m pitch comes
  from, why a rail platform will not go in a bus station, how editing works, and
  the merge rules.
- [PLAN.md](PLAN.md) - the phases and what each probe settled.
- [probe/](probe/) - the throwaway probe mod that answered the feasibility
  questions, with its test protocol in [probe/TESTS.md](probe/TESTS.md).
- [../NOTES.md](../NOTES.md) - the engine-general findings this builds on.

## What v0.1 does and does not do

Does: delegates the stock rail station to level +1 and lifts all of its output
12 m in one pass at the end of a wrapped `terminateConstructionHook`; converts
its edges to bridges; drops its terrain alignment and ground faces; adds a
single bus platform with its own station record at grade, with road stubs and a
pedestrian lane that climbs to the upper level.

Does not, yet: modular editing of the lower level (it is one fixed platform),
any choice of transport type per level, road-over-rail as well as rail-over-road,
cargo, or anything below grade.
