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
  questions, with its test protocol in [probe/TESTS.md](probe/TESTS.md), and
  [probe/entity_probe/](probe/entity_probe/) - the game script that answered
  everything the construction log cannot see, archived rather than shipped.
- [../NOTES.md](../NOTES.md) - the engine-general findings this builds on.

## What v0.1 does and does not do

Does: hosts the stock **street** station at grade and the stock **rail** station
at level +1 in one construction, sharing one result table between them; lifts
all of the rail family's output 12 m in one pass at the end of a wrapped
`terminateConstructionHook`, with a quarter turn so the tracks cross the bus
exit; drops its terrain alignment and ground faces; links the two levels'
pedestrian networks with one lane per concourse; and routes each
of `preProcessFn`, `upgradeFn` and `isAffectedByToolFn` to whichever family owns
the slot being acted on.

Does not, yet: any choice of transport type per level, road-over-rail as well as
rail-over-road, or anything below grade.

Three things about how it behaves in play are worth knowing before you build
one, because each of them looks like a bug and is not:

- **Passengers walk between the levels, through a concourse.** They go up from
  grade through the building and reach the platforms by the rail station's own
  passenger crossings. The lane that makes this possible is the only route there
  is: the two levels share no walkable node otherwise, so without a concourse in
  the build there is nowhere for that climb to start. Each concourse you place
  gets its own climb, so a long frontage is not served by one staircase at one
  end of it.
- **Freight crosses between the levels through the concourse's goods store.**
  Each concourse is a small warehouse - 100 units of universal storage per
  module - and that store is the interchange. Freight in this game never passes
  from station to station; it passes to stock in a station's catchment and out
  again. **A station with no concourse cannot interchange cargo at all.**
- **It is two stations internally, and one station to you.** Each level is a
  separate station record in its own station group, which is why a line stops at
  one level rather than at "the station". But clicking either level opens a
  single dialog with **one station name** and a tab per part - `Road station`,
  the rail level, and `Warehouse` for the concourse's store.

A concourse is therefore close to a required module rather than an optional
one, and one is seeded in the default station for that reason.

**There are two of them, and they are the same building.** *Concourse - Road
Arch* is the one that spans an entrance road, and it is offered on the entrance
only; *Concourse - Hall* fills the same 40 x 6 m cell solid and is offered along
the rest of the frontage, one cell per deck tile, so a row of them reads as one
building the length of the station. They cost the same and carry the same
catchment, capacity, goods store and stairs - what differs is the hole in the
bottom of the arch, and where each can stand.

A hall also brings a footway of its own. The front 2 m of its cell is a 30 cm
walkway - a kerb at the same height as the game's own pavements, so stepping
from a road onto it is level - and along it runs a path, with a spur to the kerb
for the game to join to a street and a link back into the station's own paths.
A row of halls is one pavement and one path. An arch needs none of it, because
it stands in the entrance's.


## Where to find it in the build menu

The mod ships two build-menu categories of its own rather than borrowing stock
ones:

- **Road menu -> Multi-layer Stations** - the station itself, sitting directly
  after the stock Buildings category.
- **Module menu -> Multi-layer** - the support and the two concourses, after
  the stock module categories and before Misc.

A category is an ordinary resource (`type = "menu_category"`) that the build
menu collects by type, so any mod can add one; root `NOTES.md` has the field
list and the icon format, and `tools/make_menu_icon.py` draws the icons.


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

A concourse is **one deck tile wide**, 40 x 6 m, so it ends where the module
above it ends and lines up with the supports either side. The arch's piers stand
at x = +-12, leaving a 21.8 m opening for the 16 m entrance road; the 8 m at each
end, beyond the piers, is solid. The arch is placed, though, by clicking a 2 m
band at its right-hand pier - see the limitations below.

The halls go either side of it, on the cells the deck covers: with the default
four-tile deck that is three of them, under the tiles at 40, 80 and -40 m, and
extending the deck extends the row. The cell an entrance road passes through is
never offered as a hall, because a hall is solid and would wall the road off.


## Contributing art

**Every picture and every block in this mod is a placeholder, and better ones
are welcome.** They are all generated by scripts in `tools/`, which is a way of
saying nobody drew them: they are deliberately plain so that what they stand in
for is obvious, and so that replacing one does not mean reverse-engineering a
format first.

The build-menu art, per constructable. Both files are TGA, bottom-up, with the
26-byte `TRUEVISION-XFILE.` footer, and both are named `@2x` - the suffix is the
engine's, so the `.con` and `.module` files ask for the name without it:

| file | size | format | where it shows |
| --- | --- | --- | --- |
| `ml_station@2x.tga` | 240 x 150 | 32bpp BGRA, type 2, descriptor 0x08 | the tile in the Road menu |
| `ml_station_preview@2x.tga` | 720 x 405 | 24bpp BGR, type 2, descriptor 0x00 | the large image in the side panel |
| `ml_support@2x.tga`, `ml_support_preview@2x.tga` | as above | as above | the support, in the module menu |
| `ml_concourse_arch@2x.tga`, `ml_concourse_arch_preview@2x.tga` | as above | as above | the road arch, in the module menu |
| `ml_concourse_hall@2x.tga`, `ml_concourse_hall_preview@2x.tga` | as above | as above | the hall, in the module menu |
| `category_ml_station@2x.tga`, `category_ml_modules@2x.tga` | 48 x 48 | **8bpp greyscale**, type 3 | the two menu category buttons |

The category icons are a different format from the rest: a greyscale coverage
mask, bright glyph on black, no colour. Those dimensions and formats are
measured off the stock files, not guessed - `tools/make_menu_art.py` and
`tools/make_menu_icon.py` carry the measurements in their docstrings, and the
generated files come out byte-for-byte the same size as the stock ones they
replace.

The 3D art is the other half, and the bigger one:

- `support_block.mdl` is a 1 m cube scaled per support. A real support would be
  a pier and a span, and anything replacing it should know that the cell it has
  to fill is **5 x 40 m by 12 m tall** for a deck tile, and that its collider
  wants to stay inside that (`NOTES.md`, round three).
- both concourses are drawn from the same cube in `concourseModels`: a
  **40 x 6 m** footprint, 12 m tall, with a **21.8 m opening** in the middle of
  the arch for the entrance road to pass through and no opening at all in the
  hall. A tunnel portal is what the arch is standing in for; the hall wants a
  facade - doors, glass, a departure board - and the two have to agree at the
  seam where they meet, which is why one function draws both.
- both are drawn with a plain concrete material for a measured reason - see
  `NOTES.md`, "A reused mesh brings its UVs" - and a replacement that brings its
  own mesh does not inherit that constraint.

Pull requests, or just the files, are equally welcome.


## Removing the mod

**Keep it enabled while a savegame contains any multi-layer station.** This mod
*is* the station - not a setting applied to a base-game one - so deactivating it
for a save deletes every station built with it, and the save may not load at
all afterwards. Bulldoze the stations first if you want the mod gone.

That is a deliberate promise rather than a measured result. Removal might well
grade better than that today, but a station whose geometry, slot ids and module
names all come from the mod can regress to "the save will not load" with any
later version, and a promise that has to be re-earned every release is not worth
making. `mod.json` declares `severityRemove: "Warning"`, which is the loudest
value any shipped mod in the install uses.

`pick-single-platform-side` is the opposite case and shows where the line is: it
only *seeds* a stock construction, the decision is baked into the savegame at
build time, and it can declare `severityRemove: "None"` (root `NOTES.md`).


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
- **A support cell that overlaps the bus station at grade is offered with a
  shortened click target**, not refused. The block still fills the whole cell;
  only the rectangle the cursor finds the empty slot by is cut clear, because
  the engine will not offer a slot whose reservation touches occupied ground. A
  cell with no such cut available is not offered at all, and the build logs both
  counts. Until 2026-10-22 one cell under the bus platform was simply withheld;
  the cut recovered it.
- **The supports and the concourse are placeholder blocks**, drawn with
  `support_block.mdl` - a solid 1 m concrete cube shipped with the mod, reusing
  the game's own unit-cube mesh with a collider equal to it. Concrete rather
  than masonry for a measured reason: that mesh's UVs are a cube-cross atlas, so
  a patterned texture smears one crop of itself over a 40 m block, while a flat
  one survives it (root `NOTES.md`, "A reused mesh brings its UVs"). They are deliberately
  solid and fill their cell to within 0.02 m on every side, because what is drawn
  is how a modder reads the room the real art has. The concourse is the one
  exception: its footprint is open below the deck, since the 16 m entrance road
  runs through it.
- **A support is one deck tile long, so a road under the deck needs a whole
  tile left clear.** One support holds one platform or track module, 40 m of it,
  and neighbouring supports meet with a 0.2 m seam. It was five supports of
  7.8 m per module until 2026-10-22, which allowed a narrower gap for a road but
  could never read as continuous: each cell paid a seam, and the module's own
  slot reserves 39 m of its 40, so five cells carried five gaps.
- **The tile where a track leaves the station cannot be supported.** The
  player's own connecting edge comes down as an embankment and reaches into
  that tile, and a support now has to clear the whole 40 m of it. The engine
  refuses the module as a collision. Leave that tile open, or build the
  connection at the end of a tile the deck does not need held up.
- **The elevated level's tab is labelled `Tram station`.** It is a train
  station; the label is wrong; and it is **the base game's bug, not this mod's.**
  The engine works a station's label out from its group's carrier list, and it
  maps the transport mode `TRAM_TRACK` to the tram carrier - while every stock
  rail track template, `simple`, `standard` and `high_speed` alike, carries
  `TRAM_TRACK` so that tram track can share a rail alignment. The routine that
  picks the name then has no `break` in it, so the **last** carrier in the list
  wins, and the order happens to be rail then tram.

  Which means **every rail station in the game is labelled this way**. You have
  never seen it because the header is only drawn when a station has more than
  one part to tab between, and a plain rail station has one. This station has
  three, so the header appears and the wrong word comes with it.

  Measured rather than guessed: all seven of the elevated level's terminals
  report the same pair of transport modes, `TRAIN` and `TRAM_TRACK`, with no
  tram *vehicle* mode anywhere. Nothing a construction can declare overrides it,
  so fixing it from here would mean either shipping a bespoke track type without
  `TRAM_TRACK` - which would cost you the track-type and catenary tools on this
  station - or overriding one of the game's own interface files, which would
  fight every other mod that touches it. Reported upstream instead.
