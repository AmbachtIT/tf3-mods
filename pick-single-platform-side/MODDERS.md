# Pick Single Platform Side, for modders

The whole mod is one mirror of one table. This file says where it hooks in and
why that is enough; [NOTES.md](NOTES.md) carries the reverse-engineered detail
and [PLAN.md](PLAN.md) the implementation and test plan. The repository-wide
loop is in the root [MODDERS.md](../MODDERS.md).

## How it works

The bus station and the cargo truck station are one modular construction,
`::/stations/street/modular_street_station/modular_terminal.con`. Its
`createTemplateFn` seeds platform modules into numbered slots, with the entrance
between `coordI` -1 and 0:

| `platforms` | occupied `coordI` | symmetric? |
| --- | --- | --- |
| 1 | `0` | **no** |
| 2 | `0`, `-1` | yes |
| 4 | `1`, `0`, `-1`, `-2` | yes |

So the whole mod is one mirror, `coordI -> -1 - coordI`, applied to the platform
slots only - provably a no-op for two and four platforms, and a side swap for
one.

Nothing else has to change. The stock `updateFn` derives the geometry from
whichever slots are occupied and already handles a lone left-hand platform: it
is the configuration you can reach by hand today by adding a platform module on
the left and deleting the one on the right. The left and right models both
already exist.

The hook is `addModifier("loadConstruction", ...)`, registered from the mod's
`runFn`. It adds the parameter to every template that offers a platform count -
driven off the presence of `platforms` rather than a hardcoded list, so a new
era or a re-enabled cargo specialisation picks it up too - and repoints the
station's `createTemplateScript` at a function that calls the stock one and
mirrors its result.

## Why it is safe to remove

`createTemplateFn` runs **at placement only**. The placed construction then
carries its own `params.modules`, which the stock `preProcessFn` maintains, and
`updateFn` renders from that. So the mod has nothing left to do once a station
exists, and `severityRemove` is `None`.

This is the clean case of a general rule, and the rule is in the root
[NOTES.md](../NOTES.md) under "A mod that only *seeds* a construction is safe to
remove" - confirmed with this mod, which is why the write-up lives there rather
than here. [PLAN.md](PLAN.md), "Removing the mod from a savegame", has what was
run to confirm it.

## Strings

"Platform Orientation" and "Standard" are already in the base game's string
catalogs for all ten shipped languages - the first is what the stock underground
street station calls its own equivalent control - so only "Other side" needed
translating, in `strings.json`.

## Layout and build

```
mod/pick_single_platform_side_1/   the publishable mod (deploy.ps1 installs this)
tools/make_listing_image.ps1       renders the mod.io listing image
deploy.ps1                         install into the game's staging area
NOTES.md                           what the install says, and why this works
PLAN.md                            the implementation and test plan
```

```powershell
.\deploy.ps1              # into the staging area
.\deploy.ps1 -Validate    # plus the game's own validator; close the game first
```

The staging area is both a full install source and the only place the in-game
publisher reads from, so one copy there is playable and publishable. Mods are
read at startup, so restart the game after deploying. This mod only seeds a
construction at placement, so a restart is all it ever needs - see
[*Which changes need a rebuild*](../NOTES.md#which-changes-need-a-rebuild-and-which-only-need-a-restart)
for when that is not true.
