# Playing with these mods

Everything here is for **Transport Fever 3** on PC, game build 40408.

## The mods

### [Pick Single Platform Side](pick-single-platform-side/PLAYERS.md)

Published on mod.io. When you place a bus station or a cargo truck station with
a **single** platform, it always lands on the same side of the entrance. This
adds a *Platform Orientation* option to the placement dialog so you can put it
on the other side.

It changes nothing else: no new models, no base game file replaced, and the
layout you pick is baked into the station when you place it. **Safe to add to a
savegame and safe to remove from one**, with stations already built on the far
side - that is tested, and it is why the mod declares `severityRemove: None`.

### [Multi-layer Stations](multi-layer-stations/PLAYERS.md)

**v0.1, not published yet.** An elevated train station over a bus station, 12 m
apart, as one structure you place in the road menu. Both halves are the game's
own stock stations, so you edit them with the game's own modules and tools -
add platforms, lay track, run the catenary tool - and passengers and freight
cross between the levels through a concourse.

Two things to know before you build one:

- **the art is placeholder.** The supports and concourses are plain concrete
  blocks. They are deliberately plain, not unfinished-by-accident;
- **keep the mod enabled while a savegame contains a station built with it.**
  This mod *is* the station rather than a setting applied to a stock one, so
  turning it off for that save deletes every station built with it, and the save
  may not load at all afterwards. Bulldoze them first if you want it gone. The
  mod declares `severityRemove: Warning`, the loudest value any shipped mod in
  the install uses.

Its own [PLAYERS.md](multi-layer-stations/PLAYERS.md) covers where to find it,
what a freshly placed station contains, how passengers and freight actually get
between the levels, and the limitations that show up in play.

## Installing

**From mod.io**, for a published mod: find it in the in-game Mod Manager or on
the website and subscribe. The game downloads it on the next start.

**By hand**, for a mod built from this repository: copy the folder under
`mod/` - the one named for the mod id, such as `multi_layer_stations_1` - into

```
C:\Program Files (x86)\Steam\userdata\<your id>\3493540\local\mods\
```

so that the mod's own `mod.json` sits at
`...\local\mods\multi_layer_stations_1\mod.json`. Mods are read at startup, so
restart the game.

One copy only: the game also reads a `staging_area\` folder next to `mods\`,
that one wins when the same mod id is in both, and nothing says which it chose
except a line in the log.

## Turning a mod on

**A mod that is installed is not yet active.** Each savegame carries its own mod
list, so enable it in the game's mod settings for that save - for a new game at
the start, for an existing one from its settings. A mod that is installed but
not enabled does nothing at all, and nothing it adds appears in the build menu.

## Savegames

| mod | add to an existing save | remove from a save |
| --- | --- | --- |
| Pick Single Platform Side | yes | yes, stations keep the layout they were built with |
| Multi-layer Stations | yes | **no** - bulldoze every multi-layer station first |

The difference is what each mod owns. The first one only *seeds* a stock
construction, and the decision is baked into the savegame at placement, so the
mod has nothing left to do afterwards. The second one is the construction, so
its stations have nowhere to come from without it.

## Something looks wrong

The game writes a log to

```
C:\Program Files (x86)\Steam\userdata\<your id>\3493540\local\crash_dump\stdout.txt
```

and **overwrites it every time the game starts**, so copy it aside before
relaunching if something went wrong. Each mod here writes its own lines with a
prefix - `[multi-layer]` for Multi-layer Stations - and those lines are the
fastest way to tell whether the mod is even running.
