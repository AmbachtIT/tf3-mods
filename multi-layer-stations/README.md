# Multi-layer stations

A mod for **Transport Fever 3** that unlocks the z-axis for station building: an
elevated train station with a bus station underneath, as one structure you place
from the road menu.

Scope is levels, not a free z-axis, at a 12 m pitch. **Level 0 and level +1**
for the first working version - a station at grade with another above it. One
transport family per level, and the two levels stay **two separate stations**,
which matches in-game practice and lets the player inspect and name each one.
**Level -1 is parked**; its findings are in [NOTES.md](NOTES.md) under "Parked:
level -1".

Status: **v0.1 works in-game, and is not published yet.** A 160 m rail platform
at +12 m over a bus platform at grade, as two separate stations. Track connects
to the upper level, road to the lower, both levels are editable with the game's
own modules and tools, the terrain is undisturbed, and it survives a
save/reload. All of the art is placeholder.

**Playing?** [PLAYERS.md](PLAYERS.md) - where to find it, what a station
contains when you place it, how passengers and freight cross between the levels,
and what it cannot do yet.

**Modding?** [MODDERS.md](MODDERS.md) - how the two stock stations are hosted in
one construction, the measurements the geometry is built on, and what art a pull
request would have to fit.

## The rest of the documentation

- [NOTES.md](NOTES.md) - why this mod is built the way it is: the terrain
  mechanisms, the measured vertical budget, where the 12 m pitch comes from, why
  a rail platform will not go in a bus station, how editing works, and the merge
  rules.
- [PLAN.md](PLAN.md) - the phases, and what each probe settled.
- [TESTS.md](TESTS.md) - the beta test protocol: what to run before publishing,
  what each diagnostic in the log means, and what is frozen once the mod is
  public.
- [probe/](probe/) - the throwaway probe mod that answered the feasibility
  questions, with its protocol in [probe/TESTS.md](probe/TESTS.md), and
  [probe/entity_probe/](probe/entity_probe/) - the game script that answered
  everything the construction log cannot see, archived rather than shipped.
- [../NOTES.md](../NOTES.md) - the engine-general findings this builds on.
- [../README.md](../README.md) - the repository: the other mod, the shared
  tools, and where a given piece of documentation belongs.
