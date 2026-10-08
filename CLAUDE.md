# Transport Fever 3 Mods
This project contains multiple transport fever 3 mods and mod research

**Read [NOTES.md](NOTES.md) before working on any mod here.** It holds the
cross-mod findings - the modifier hooks, how construction params and savegames
interact, which mods are safe to remove, where the log and the staging area
live - each one either cited to a file in the install or confirmed in-game. Add
to it whenever something is learned that is not specific to one mod; mod-specific
detail belongs in that mod's own `NOTES.md`.

## Conventions

- **Deploy to the staging area, never to `mods\`, and never to both.** Staging
  is a full install source, so a mod there is playable as well as publishable,
  and it wins over `mods\` when a `modId` is in both - which makes a stale
  duplicate silently authoritative. `pick-single-platform-side/deploy.ps1` is
  the template.

## Mods

| folder | mod id | what it does |
|---|---|---|
| `pick-single-platform-side` | `pick_single_platform_side_1` | adds a Platform Orientation option to the bus / cargo truck station, so a single platform can sit on either side of the entrance |
| `multi-layer-stations` | `multi_layer_stations_1` | unlocks the z-axis for stations at a 12 m pitch: an elevated train platform over a bus platform, as two stations in one structure. v0.1; `probe/` holds the throwaway research mod |
