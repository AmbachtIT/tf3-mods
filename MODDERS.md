# Modding in this repository

What the development loop is, what the tools do, and where a given piece of
documentation belongs. The engine findings themselves are in
[NOTES.md](NOTES.md); each mod's own `MODDERS.md` covers how that mod is built.

## Requirements

Transport Fever 3 on Steam, on Windows. The deploy and listing scripts are
PowerShell. The tools in `tools/` are Python 3 on the standard library, except
`luacheck.py`, which needs [`lupa`](https://pypi.org/project/lupa/)
(`python -m pip install lupa`) for a real Lua front end.

## The loop

```powershell
cd multi-layer-stations
.\deploy.ps1              # into the game's staging area
.\deploy.ps1 -Validate    # plus the game's own validator; close the game first
```

**Deploy to the staging area, never to `mods\`, and never to both.** The staging
area is a full install source as well as the only folder the in-game publisher
reads, so one copy there is playable *and* publishable. It also wins when the
same mod id is in both places, which is how a stale copy becomes silently
authoritative - the log says so once, and nothing else does.

Then **restart the game**, because mods are read at startup.

### A restart is not always enough

`updateFn` output is baked into the savegame. So a change to what a script
*emits* - geometry, slots, lanes - does not reach a construction that already
exists until that construction is **rebuilt**, by opening it with the build tool
and adding or removing a module. A change inside a `.mdl` or `.mtl` does arrive
on the restart alone.

The trap is that this cuts across what the change looks like rather than what it
is: cutting a stretched block into panels is a texture fix to the player and a
geometry change to the engine, so it needs the rebuild even though no art file
moved. The test is which file you edited - anything in a `.script.lua` needs it.
Root [NOTES.md](NOTES.md#which-changes-need-a-rebuild-and-which-only-need-a-restart)
has the table.

### The log

```
C:\Program Files (x86)\Steam\userdata\<id>\3493540\local\crash_dump\stdout.txt
```

**Overwritten on every launch**, so copy it aside if a run matters. Each mod
logs with its own prefix, `[multi-layer]` and so on. Read it before asking for
another run: most questions about what the game did are answered there, and the
engine reports missing resources, refused modules and module counts without
being asked.

### Before deploying

```
python tools/luacheck.py multi-layer-stations/mod/multi_layer_stations_1
```

A syntax gate, not a validator: it parses every Lua resource file and catches a
bare global and a name used above the `local` that declares it. That is the
whole class of mistake which otherwise shows up in-game as "my construction is
missing from the build menu", with nothing in the log to say why.

## Tools

| tool | what it does |
| --- | --- |
| `tools/luacheck.py` | parses the mod's Lua without launching the game |
| `tools/meshfaces.py` | reads a stock `.mdl`'s vertex buffer: its real extent, and which of the six faces exist. `boundingInfo` is not the geometry and neither is the collider |
| `tools/make_menu_art.py` | draws the build-menu tiles and preview images, in the formats measured off the stock files |
| `tools/make_menu_icon.py` | draws the 48 x 48 greyscale menu-category icons |
| `<mod>/tools/` | anything that only makes sense for that one mod, such as its mod.io listing image |

## Where documentation goes

Six kinds of document, and one question decides between them:

> **Would this still be true if this mod did not exist?**

If yes, it is a fact about the game and belongs at the root. If no, it belongs
to the mod.

| file | scope | holds |
| --- | --- | --- |
| [`NOTES.md`](NOTES.md) | the collection | How the engine behaves: the modifier hooks, what a savegame bakes and what it re-reads, how slots and colliders interact, resource paths, menu formats, the log and the staging area. One section per finding, each cited to a file in the install or to a run. |
| [`PLAYERS.md`](PLAYERS.md) / `<mod>/PLAYERS.md` | both | The player's view: installing, what a mod does, what it promises about a savegame, and the limitations that show up in play. No internals. |
| `MODDERS.md` / `<mod>/MODDERS.md` | both | The contributor's view: this file for the repository, and per mod how that mod is built and what art or code a pull request would have to fit. |
| `<mod>/NOTES.md` | one mod | Why *this* mod is built the way it is: what was tried, what the game said, which numbers are measured and where they came from. The lab notebook, in rounds. |
| `<mod>/PLAN.md` | one mod | What is left to do, in phases, and what each probe settled. |
| `<mod>/TESTS.md` | one mod | What to run before publishing, what each diagnostic in the log means, and what is frozen once the mod is public. |

`README.md`, at the root and in each mod, is a front page and an index: a
paragraph, a status, and links. Material that grows belongs in one of the files
above, not in it.

Three rules of thumb that follow from the question:

- **An engine fact goes to the root even when only one mod uses it.** The next
  mod will need it, and the mod that found it should link rather than keep it. A
  root section may well say which mod found it.
- **A decision stays with the mod.** "A crop is 0.75 as wide as it is tall" is
  the engine; "so the course is the panel times 4/3" is one mod's choice.
- **Say it once and link to it.** A mod's `PLAYERS.md` summarising a root
  finding in a sentence and linking to it is right; the same three paragraphs in
  two files is not.

## Art

**Every block, icon and preview image in Multi-layer Stations is a
placeholder**, generated by the scripts in `tools/` rather than drawn. They are
deliberately plain, so that what they stand in for is obvious and so that
replacing one does not mean reverse-engineering a format first. The sizes, the
formats and the constraints real art has to meet are in that mod's
[MODDERS.md](multi-layer-stations/MODDERS.md). Better art is welcome, as a pull
request or just as files.
