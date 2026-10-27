# Transport Fever 3 mods

Mods for **Transport Fever 3**, and the research they are built on.

| mod | status | what it does |
| --- | --- | --- |
| [Pick Single Platform Side](pick-single-platform-side) | published on mod.io | Puts a one-platform bus or cargo truck station's platform on either side of its entrance. |
| [Multi-layer Stations](multi-layer-stations) | v0.1, not yet published | Builds an elevated train station over a bus station, as two stations in one structure. |

**Playing?** [PLAYERS.md](PLAYERS.md) - how to install a mod, what each one
does, and what each one promises about your savegame.

**Modding?** [MODDERS.md](MODDERS.md) - the development loop, what the tools
do, and the conventions this repository keeps.

Nothing here replaces a base game file: each mod either hooks the engine's own
modifier points or ships a construction of its own. Every finding in the notes
is read out of a file in the install or confirmed by running the game, and where
it was confirmed the log line is quoted. Game build 40408.

## Layout

```
README.md                    this file
PLAYERS.md                   installing and playing with these mods
MODDERS.md                   developing in this repository
NOTES.md                     engine findings that apply across mods
CLAUDE.md                    the brief for AI assistants working here
LICENSE                      MIT
tools/                       Lua syntax gate, menu art, mesh reader

multi-layer-stations/        one folder per mod, named for the mod
pick-single-platform-side/
```

Each mod folder is laid out the same way: `README.md` as its front page,
`PLAYERS.md` and `MODDERS.md` beside it, `NOTES.md` for why it is built that
way, `PLAN.md` for what is left, `TESTS.md` where there is a protocol,
`deploy.ps1` to install it, and `mod/<mod id>/` for the publishable mod itself.
Everything outside that last folder is development material and never ships.

## Licence

MIT, see [LICENSE](LICENSE). These mods read and extend the game's own content;
no game asset is redistributed here.
