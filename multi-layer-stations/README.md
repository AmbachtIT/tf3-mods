# Multi-layer stations

The idea behind Multi-layer stations is to unlock the z-axis for station
construction. I want to be able to build an elevated train station with a bus
station underneath.

Scope is levels, not a free z-axis, at a 12 m pitch. **Level 0 and level +1**
for the first working version - a station at grade with another above it. One
transport family per level, and the two levels stay **two separate stations**,
which matches in-game practice and lets the player inspect and name each one.
**Level -1 is parked**; its findings are in `NOTES.md` under "Parked: level -1".

Status: **v0.1 works in-game.** A 160 m rail platform at +12 m over a bus
platform at grade, as two separate stations. Track connects to the upper level,
road to the lower, both levels are editable with the game's own modules and
tools, the terrain is undisturbed, and it survives a save/reload.

**Both levels are the game's own stock stations, delegated.** Level 0 is the
modular street station, unchanged and at grade; level +1 is the modular rail
station, turned a quarter turn so the tracks cross the bus exit rather than
running alongside it, and lifted 12 m. The lower level therefore brings the bus
station's real layout, entrance and snap-to-the-road-end behaviour.

Both levels are editable with the game's own modules **and** its own tools,
because the construction delegates each family's whole script surface rather
than just `updateFn`: adding a bus platform adds both of its tiles, and the
catenary tool electrifies the elevated track.

Two write-ups in the root [NOTES.md](../NOTES.md) are the reusable parts of this
mod: "Hosting two stock families in one construction", and "Delegating a family
means delegating its whole script surface" - the second being the one that is
easy to miss, because a missing `preProcessScript` leaves placement looking
perfect and breaks only editing.

Accepted limitations for now:

- **the elevated deck has no structure under it.** The track used to sit on a
  stone viaduct via `edgeType = "BRIDGE"`, but the engine generates a bridge's
  pillars and abutments from the edge alone and so drove them straight through
  the bus station below. Nothing automatic can know what the player means to
  put under the deck, so the deck is bare and structure is placed, not
  generated - see `NOTES.md`, "The elevated track carries no bridge". Support
  modules cover it for now; proper art is the real answer;
- a track drawn from the elevated level down to grade is built as an embankment
  rather than a viaduct (`NOTES.md`, "The player's connecting edge earthworks, in
  both directions");
- **one name for both levels.** The two `station` records join a single
  StationGroup, which is what gives interchange between the levels for free -
  and a StationGroup has exactly one name, so the levels cannot be named
  individually. Same fact, both sides;
- the entity window labels both levels "Tram Station". The label is the
  *group's*, picked by last-carrier-wins in
  `make_entity_window.tl:46-101`, and why the group reports a `TRAM` carrier is
  not yet explained - `NOTES.md`, "Why the upper level says Tram Station".
  Cosmetic: lines, routing and transfers are unaffected;
- **supports** are player-placed modules that work under platform and track
  tiles but are misaligned under station buildings. The cause is known and written up in
  `PLAN.md` Phase 7 - which also now records that the fix has to be keyed on the
  *module*, not the slot type, because `rail_building_size2` hosts buildings 17,
  23 and 38 m deep;
- stock station buildings have ground-level entrances and read as street level
  however they are supported. Stairs placed at a platform end look right and
  carry catchment, so they are the better default until there is custom art;
- no construction parameters at all. The level layout is fixed at placement by
  design, and everything else - track type, catenary, how many platforms on
  either level - is chosen afterwards with the game's own modules and tools.

```
.\deploy.ps1            # staging area; restart the game afterwards
.\deploy.ps1 -Validate  # close the game first
```

Log prefix `[multi-layer]`. Look for **Multi-layer Station** in the **road**
buildings menu, passenger filter - the level at grade decides which tab a variant
lives in and what it snaps to, so the mirror variant (road over rail) will sit in
the rail tab.

- [TESTS.md](TESTS.md) - the beta test protocol: what to run before publishing,
  what each diagnostic in the log means, and what is frozen once the mod is
  public.
- [NOTES.md](NOTES.md) - what the install says and what the probes proved: the
  terrain mechanisms, the measured vertical budget, where the 12 m pitch comes
  from, why a rail platform will not go in a bus station, how editing works, and
  the merge rules.
- [PLAN.md](PLAN.md) - the phases and what each probe settled.
- [probe/](probe/) - the throwaway probe mod that answered the feasibility
  questions, with its test protocol in [probe/TESTS.md](probe/TESTS.md).
- [../NOTES.md](../NOTES.md) - the engine-general findings this builds on.

## What v0.1 does and does not do

Does: hosts the stock **street** station at grade and the stock **rail** station
at level +1 in one construction, sharing one result table between them; lifts
all of the rail family's output 12 m in one pass at the end of a wrapped
`terminateConstructionHook`, with a quarter turn so the tracks cross the bus
exit; drops its terrain alignment and ground faces; links the two levels'
pedestrian networks with one lane; and routes each
of `preProcessFn`, `upgradeFn` and `isAffectedByToolFn` to whichever family owns
the slot being acted on.

Does not, yet: any choice of transport type per level, road-over-rail as well as
rail-over-road, cargo, or anything below grade.


## Where the default station puts things

The seeded deck lands **on the concourse**: the quarter turn puts the rail
columns at a 5 m pitch along the construction's y axis, and `RAIL_SHIFT_Y`
moves them so the platform sits at the entrance's edge rather than three columns
short of it. The bus platforms are then beside the deck, with three free column
positions to extend into if you want tracks over them.

A station places with one platform and one track above, one bus platform and an
entrance below, and **one concourse** over the entrance - which is what gives
either level a catchment of its own. No station building is seeded on either
level; the concourse stands in for both.


## Accepted limitations

Measured, understood, and left as they are for v0.1:

- **The elevated deck stops at the street entrance, and does not continue on
  the far side of it.** No platform or track slot is offered over the entrance's
  own 16 x 15 m tile, because a module there could never be removed again: the
  entrance spans the full width of a track column's reserved rectangle, so
  nothing would be left of it to click. Since the entrance is narrower than a
  40 m tile is long, the tiles either side of that one *could* be built on and
  the deck could hop the road - so everything at or past the first blocked
  column is withheld too, on that side only. About 15 m of the station's
  frontage is out of reach, and the concourse is what crosses the road there
  instead.
- **A concourse is placed by clicking a 2 m band at one of its piers**, not
  anywhere on its 24 m span. The engine offers an empty slot only where its
  reservation holds ground no occupied slot is holding, and the entrance's own
  reservations cover everything inside x = +-10 of our cell. The art and the
  catchment are offset back over the entrance, so only the pip sits off-centre.
- **A support cell that stands inside the bus platform's own rectangle is never
  offered.** One cell, hidden under the platform, for the same reason. The build
  logs the count on every rebuild.
- **The supports and the concourse are placeholder blocks**, drawn with
  `support_block.mdl` - a solid 1 m stone cube shipped with the mod, reusing the
  game's own unit-cube mesh with a collider equal to it. They are deliberately
  solid and fill their cell to within 0.1 m on every side, because what is drawn
  is how a modder reads the room the real art has. The concourse is the one
  exception: its footprint is open below the deck, since the 16 m entrance road
  runs through it.
