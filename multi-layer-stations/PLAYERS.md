# Multi-layer stations, for players

An elevated train station over a bus station, 12 m apart, as one structure.
**v0.1**: it works, it survives a save and reload, and every block and icon in
it is a placeholder.

Both levels are the game's own stock stations - the modular street station at
grade, the modular rail station turned a quarter turn and lifted 12 m - so the
lower level brings the bus station's real layout, entrance and
snap-to-the-road-end behaviour, and both levels are editable with the game's own
modules **and** its own tools. Adding a bus platform adds both of its tiles, and
the catenary tool electrifies the elevated track.

## Where to find it

- **Road menu -> Multi-layer Stations**, passenger filter, directly after the
  stock Buildings category.
- **Module menu -> Multi-layer**, for the support and the two concourses.

The level at grade decides which tab a variant lives in and what it snaps to, so
a later mirror variant - road over rail - will sit in the rail tab instead.

## What you get when you place one

One platform and one track above, one bus platform and an entrance below, and
**one concourse** over the entrance, which is what gives either level a
catchment of its own. No station building is seeded on either level; the
concourse stands in for both.

The seeded deck lands on the concourse, with the bus platforms beside it and
three free column positions to extend into if you want tracks over them.

There are **no construction parameters at all**. The level layout is fixed at
placement by design, and everything else - track type, catenary, how many
platforms on either level - is chosen afterwards with the game's own modules and
tools.

## Three things that look like bugs and are not

**Passengers walk between the levels, through a concourse.** They go up from
grade through the building and reach the platforms by the rail station's own
passenger crossings. That lane is the only route there is: the two levels share
no walkable node otherwise, so without a concourse in the build there is nowhere
for the climb to start. Each concourse gets its own climb, so a long frontage is
not served by one staircase at one end of it.

**Freight crosses between the levels through the concourse's goods store.** Each
concourse is a small warehouse - 100 units of universal storage - and that store
is the interchange. Freight in this game never passes from station to station;
it passes to stock in a station's catchment and out again. **A station with no
concourse cannot interchange cargo at all.**

**It is two stations internally and one station to you.** Each level is a
separate station record in its own station group, which is why a line stops at
one level rather than at "the station". But clicking either level opens a single
dialog with **one station name** and a tab per part - `Road station`, the rail
level, and `Warehouse` for the concourse's store.

A concourse is therefore close to a required module rather than an optional one,
and one is seeded in the default station for that reason.

## The two concourses

**There are two of them, and they are the same building.** *Concourse - Road
Arch* is the one that spans an entrance road, and it is offered on the entrance
only; *Concourse - Hall* fills the same 40 x 6 m cell solid and is offered along
the rest of the frontage, one cell per deck tile, so a row of them reads as one
building the length of the station. They cost the same and carry the same
catchment, capacity, goods store and stairs - what differs is the hole in the
bottom of the arch, and where each can stand.

With the default four-tile deck there are three hall cells, under the tiles at
40, 80 and -40 m, and extending the deck extends the row. The cell an entrance
road passes through is never offered as a hall, because a hall is solid and
would wall the road off.

A hall also brings a footway of its own. The front 2 m of its cell is a 30 cm
walkway - a kerb at the same height as the game's own pavements, so stepping
from a road onto it is level - and along it runs a path, with a spur to the kerb
for the game to join to a street, and a link back into the station's own paths.
A row of halls is one pavement and one path. An arch needs none of it, because
it stands in the entrance's.

## What it cannot do yet

- **The elevated deck has no structure under it.** Support modules cover it for
  now, and they are placed by you rather than generated: nothing automatic can
  know what you mean to put under the deck, and the engine's own bridge pillars
  drove straight through the bus station when this was tried.
- **Supports work under platform and track tiles, and are misaligned under
  station buildings.** The cause is known; see `PLAN.md` Phase 7.
- **A support is one deck tile long**, 40 m, so a road under the deck needs a
  whole tile left clear. And the tile where a track leaves the station cannot be
  supported at all - your connecting edge comes down as an embankment and
  reaches into it, and the engine refuses the module as a collision. Leave that
  tile open, or build the connection at the end of a tile the deck does not
  need held up.
- **A track drawn from the elevated level down to grade is built as an
  embankment, not a viaduct.**
- **About 15 m of the frontage is out of reach**, at the street entrance: the
  deck stops there rather than hopping the road, because a platform module over
  the entrance could never be clicked again to remove it. The concourse is what
  crosses the road there instead.
- **A concourse is placed by clicking a 2 m band at one of its piers**, not
  anywhere along its span. The art and the catchment sit where you would expect;
  only the pip you click is off-centre.
- **A support cell that overlaps the bus station at grade is offered with a
  shortened click target.** The block still fills the whole cell.
- **One name for both levels.** The two levels join a single station group,
  which is what gives interchange between them for free - and a group has
  exactly one name, so the levels cannot be named individually. Same fact, both
  sides.
- **The elevated level's tab is labelled `Tram station`.** It is a train
  station, the label is wrong, and it is **the base game's bug, not this
  mod's** - every rail station in the game is labelled this way, and you have
  never seen it because the tab header is only drawn when a station has more
  than one part to tab between. This one has three. Lines, routing and transfers
  are unaffected. [MODDERS.md](MODDERS.md) has the measurement and why it cannot
  be fixed from here.
- **Stock station buildings read as street level** however they are supported,
  because their entrances are at ground level. Stairs placed at a platform end
  look right and carry catchment, so they are the better default until there is
  custom art.
- **All of the art is placeholder.** The supports and concourses are plain
  concrete blocks, deliberately plain rather than unfinished by accident.

## Removing the mod

**Keep it enabled while a savegame contains any multi-layer station.** This mod
*is* the station - not a setting applied to a base-game one - so deactivating it
for a save deletes every station built with it, and the save may not load at all
afterwards. Bulldoze the stations first if you want the mod gone.

That is a deliberate promise rather than a measured result. Removal might well
grade better than that today, but a station whose geometry, slot ids and module
names all come from the mod can regress to "the save will not load" with any
later version, and a promise that has to be re-earned every release is not worth
making. `mod.json` declares `severityRemove: "Warning"`, the loudest value any
shipped mod in the install uses.

[Pick Single Platform Side](../pick-single-platform-side/PLAYERS.md) is the
opposite case and shows where the line is: it only *seeds* a stock construction,
the decision is baked into the savegame at build time, and it can declare
`severityRemove: "None"`.
