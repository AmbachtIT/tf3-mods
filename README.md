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

## Built with Claude

These mods are written with [Claude Code](https://claude.com/claude-code), and
Claude is indispensable to them rather than incidental. Transport Fever 3's
modding surface is largely undocumented, so nearly every question here is
answered by reading the game's own Lua and model files out of the install,
forming a hypothesis, and putting it in front of the running game. That is work
of exactly the shape a model is good at and a person alone is slow at: holding a
few hundred unfamiliar files in view at once, finding the single line that
contradicts the plan, and writing down what was learned while it is still fresh.
`NOTES.md` is what came of it.

Wariness about AI slop is understandable, and a mod that writes into your
savegame deserves more suspicion than most. So the standard this repository
holds itself to is the one that answers that suspicion: **every finding is cited
to a file in the install or to a log line from a real run**, the test protocols
and their results are kept here rather than summarised away, and what each mod
promises about your savegame is stated plainly - including the mod whose promise
is *do not remove me*. Where something is a placeholder, untested or known to be
broken, it says so in the place you would look for it.

Judge the mods on their merits; the evidence is all here to do it with.

## Reporting a problem

Please open a [GitHub issue](https://github.com/AmbachtIT/tf3-mods/issues).

Include **the log and the savegame** - both, as a minimum. The log is
`crash_dump\stdout.txt` and the save is in the `save\` folder beside it;
[PLAYERS.md](PLAYERS.md#something-looks-wrong) has the full path and the one
thing that matters most about it, which is that **the game overwrites the log
every time it starts** - so copy it aside before relaunching. Each mod writes
its own prefixed lines, so the log usually settles in seconds whether the mod
was even running.

**There is no guarantee these mods work alongside other mods, and least of all
alongside other script mods.** Two scripts can hook the same construction or the
same modifier point, and the one that loads last wins - which surfaces as any
kind of bug at all, a long way from the cause. So say in the issue which other
mods you have enabled, and if you can, check whether the problem survives with
only this one. That single answer is worth more than anything else you can put
in a report.

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
