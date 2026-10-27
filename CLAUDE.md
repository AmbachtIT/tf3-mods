# Transport Fever 3 Mods
This project contains multiple transport fever 3 mods and mod research.
[README.md](README.md) is the repository's own introduction - the mod list, the
layout, and how to deploy and check a mod - and it is accurate; prefer fixing it
to repeating it.

**Read [NOTES.md](NOTES.md) before working on any mod here.** It holds the
cross-mod findings - the modifier hooks, how construction params and savegames
interact, which mods are safe to remove, where the log and the staging area
live - each one either cited to a file in the install or confirmed in-game.

## Conventions

- **Decide where a note belongs before writing it.** The question is *would
  this still be true if this mod did not exist?* If yes it is an engine fact and
  goes in the root `NOTES.md`, even when only one mod uses it; if no it is a
  decision and belongs to the mod. Audience splits it again: player-facing
  material goes in `PLAYERS.md`, contributor-facing in `MODDERS.md`, outstanding
  work in `PLAN.md`, test protocol in `TESTS.md`. **`README.md` stays a front
  page** - a paragraph, a status and links - at the root and in each mod. Say it
  once and link to it rather than repeating it; [MODDERS.md](MODDERS.md) has the
  full table.
- **Deploy to the staging area, never to `mods\`, and never to both.** Staging
  is a full install source, so a mod there is playable as well as publishable,
  and it wins over `mods\` when a `modId` is in both - which makes a stale
  duplicate silently authoritative. `pick-single-platform-side/deploy.ps1` is
  the template; keep the copies in step.
- **A restart is not always enough to see a change.** `updateFn` output is baked
  into the save, so script-emitted geometry needs each placed construction
  rebuilt as well. Root `NOTES.md`, "Which changes need a rebuild".

The mod list lives in [README.md](README.md#the-mods), not here.
