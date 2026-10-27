# Multi-layer stations, for modders

How the mod is built, the measurements the geometry stands on, and what a pull
request would have to fit. The repository-wide loop - deploy, restart, rebuild,
log, syntax gate - is in the root [MODDERS.md](../MODDERS.md); the reasoning
behind each decision here is in [NOTES.md](NOTES.md), in rounds.

```powershell
.\deploy.ps1            # staging area; restart the game afterwards
.\deploy.ps1 -Validate  # close the game first
```

Restarting shows a new `.mdl` or `.mtl`. It does **not** show a change to what
the script emits - geometry, slots, lanes - on a station that already exists:
`updateFn` output is baked into the save, so rebuild each one by adding or
removing a module. Root
[NOTES.md](../NOTES.md#which-changes-need-a-rebuild-and-which-only-need-a-restart).

The mod logs with the prefix `[multi-layer]`, and [TESTS.md](TESTS.md) says what
each of its diagnostics means.

## What v0.1 does

**Both levels are the game's own stock stations, delegated.** Level 0 is the
modular street station, unchanged and at grade; level +1 is the modular rail
station, turned a quarter turn so the tracks cross the bus exit rather than
running alongside it, and lifted 12 m.

It hosts both families in one construction, sharing one result table between
them; lifts all of the rail family's output 12 m in one pass at the end of a
wrapped `terminateConstructionHook`; drops its terrain alignment and ground
faces; links the two levels' pedestrian networks with one lane per concourse;
and routes each of `preProcessFn`, `upgradeFn` and `isAffectedByToolFn` to
whichever family owns the slot being acted on.

Both levels stay editable with the game's own modules **and** its own tools
precisely because the construction delegates each family's whole script surface
rather than just `updateFn`.

Does not, yet: any choice of transport type per level, road-over-rail as well as
rail-over-road, or anything below grade.

**Two write-ups in the root [NOTES.md](../NOTES.md) are the reusable parts of
this mod**: "Hosting two stock families in one construction", and "Delegating a
family means delegating its whole script surface" - the second being the one
that is easy to miss, because a missing `preProcessScript` leaves placement
looking perfect and breaks only editing.

## The numbers the geometry stands on

- **12 m pitch** between levels, from the measured vertical budget in
  [NOTES.md](NOTES.md).
- **A deck tile is 40 m**, and a support is one tile long: one support holds one
  platform or track module, and neighbouring supports meet with a 0.2 m seam. It
  was five supports of 7.8 m per module until 2026-10-22, which allowed a
  narrower gap for a road but could never read as continuous - each cell paid a
  seam, and the module's own slot reserves 39 m of its 40.
- **A support cell is 5 x 40 m by 12 m tall** for a deck tile, and its collider
  wants to stay inside that ([NOTES.md](NOTES.md), round three).
- **A concourse cell is 40 x 6 m**, one deck tile wide, so it ends where the
  module above it ends and lines up with the supports either side. The arch's
  piers stand at x = +-12, leaving a **21.8 m opening** for the 16 m entrance
  road; the 8 m at each end, beyond the piers, is solid. 6 m rather than 10
  because a deeper cell reached the road's snap point and left the concourse
  impossible to re-place after demolition.
- **The seeded deck lands on the concourse**: the quarter turn puts the rail
  columns at a 5 m pitch along the construction's y axis, and `RAIL_SHIFT_Y`
  moves them so the platform sits at the entrance's edge rather than three
  columns short of it.

## Why the limitations are where they are

Each of these is measured and understood, and left as it is for v0.1. The
player-facing version of the same list is in [PLAYERS.md](PLAYERS.md).

- **No bridge under the deck.** The track used to sit on a stone viaduct via
  `edgeType = "BRIDGE"`, but the engine generates a bridge's pillars and
  abutments from the edge alone and so drove them straight through the bus
  station below. Nothing automatic can know what the player means to put under
  the deck, so structure is placed, not generated - [NOTES.md](NOTES.md), "The
  elevated track carries no bridge". Proper art is the real answer.
- **The deck stops at the street entrance and does not continue past it.** No
  platform or track slot is offered over the entrance's own 16 x 15 m tile,
  because a module there could never be removed again: the entrance spans the
  full width of a track column's reserved rectangle, so nothing would be left of
  it to click. Since the entrance is narrower than a 40 m tile is long, the tiles
  either side *could* be built on and the deck could hop the road - so
  everything at or past the first blocked column is withheld too, on that side
  only.
- **A concourse is placed by clicking a 2 m band at one of its piers.** The
  engine offers an empty slot only where its reservation holds ground no
  occupied slot is holding, and the entrance's own reservations cover everything
  inside x = +-10 of our cell. The art and the catchment are offset back over
  the entrance, so only the pip sits off-centre.
- **A support cell overlapping the bus station is offered with a shortened click
  target**, not refused. The block still fills the whole cell; only the
  rectangle the cursor finds the empty slot by is cut clear, because the engine
  will not offer a slot whose reservation touches occupied ground. A cell with
  no such cut available is not offered at all, and the build logs both counts.
  Until 2026-10-22 one cell under the bus platform was simply withheld; the cut
  recovered it.
- **The tile where a track leaves the station cannot be supported.** The
  player's connecting edge comes down as an embankment and reaches into that
  tile, and a support has to clear the whole 40 m of it, so the engine refuses
  the module as a collision.
- **Supports are misaligned under station buildings.** The fix has to be keyed
  on the *module*, not the slot type, because `rail_building_size2` hosts
  buildings 17, 23 and 38 m deep - [PLAN.md](PLAN.md) Phase 7.
- **One name for both levels.** The two `station` records join a single
  StationGroup, which is what gives interchange between the levels for free, and
  a StationGroup has exactly one name.
- **The elevated level's tab says `Tram station`.** The engine works a station's
  label out from its group's carrier list and maps the transport mode
  `TRAM_TRACK` to the tram carrier - while every stock rail track template,
  `simple`, `standard` and `high_speed` alike, carries `TRAM_TRACK` so that tram
  track can share a rail alignment. The routine that picks the name has no
  `break` in it, so the **last** carrier wins, and the order happens to be rail
  then tram (`make_entity_window.tl:46-101`). Measured rather than guessed: all
  seven of the elevated level's terminals report the same pair of transport
  modes, `TRAIN` and `TRAM_TRACK`, with no tram *vehicle* mode anywhere.
  Nothing a construction can declare overrides it, so fixing it from here would
  mean either shipping a bespoke track type without `TRAM_TRACK` - which costs
  the track-type and catenary tools on this station - or overriding one of the
  game's own interface files, which fights every other mod that touches it.
  Reported upstream instead. This one is the base game's behaviour rather than
  this mod's, so it belongs in the root notes whenever those get reorganised.

## The build menu

The mod ships two build-menu categories of its own rather than borrowing stock
ones: **Road menu -> Multi-layer Stations** for the station, and **Module menu
-> Multi-layer** for the support and the two concourses. A category is an
ordinary resource (`type = "menu_category"`) that the build menu collects by
type, so any mod can add one; the root [NOTES.md](../NOTES.md) has the field
list and the icon format, and `tools/make_menu_icon.py` draws the icons.

## Contributing art

**Every picture and every block in this mod is a placeholder, and better ones
are welcome.** They are all generated by scripts in `../tools/`, which is a way
of saying nobody drew them: they are deliberately plain so that what they stand
in for is obvious, and so that replacing one does not mean reverse-engineering a
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
  a pier and a span, and anything replacing it should know the cell it has to
  fill is 5 x 40 m by 12 m tall for a deck tile.
- both concourses are drawn from the same cube in `concourseModels`: a
  **40 x 6 m** footprint, 12 m tall, with a 21.8 m opening in the middle of the
  arch for the entrance road to pass through and no opening at all in the hall.
  A tunnel portal is what the arch is standing in for; the hall wants a facade -
  doors, glass, a departure board - and the two have to agree at the seam where
  they meet, which is why one function draws both.
- the blocks are **deliberately solid** and fill their cell to within 0.02 m on
  every side, because what is drawn is how a modder reads the room the real art
  has.
- they carry a plain concrete material for a measured reason, and the geometry
  is cut into panels for another: that mesh's UVs are a cube-cross atlas, so one
  face samples one fixed crop and a scaled box stretches it. Root
  [NOTES.md](../NOTES.md), "A reused mesh brings its UVs", and [NOTES.md](NOTES.md),
  "The smear is anisotropy". **A replacement that brings its own mesh inherits
  none of this** - both constraints are the borrowed cube's, not the game's.

Pull requests, or just the files, are equally welcome.
