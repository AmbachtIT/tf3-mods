# Pick Single Platform Side

A mod for **Transport Fever 3**. When placing a bus station or a cargo truck
station you can select one, two or four platforms. Two and four are symmetric,
but the single platform always lands on the same side of the entrance - which is
sometimes the wrong side for the spot you are building on.

This mod adds a **Platform Orientation** option to the placement dialog, next to
the platform count. Pick **Other side** and the lone platform moves across the
entrance.

![Pick Single Platform Side](mod/pick_single_platform_side_1/_metadata/0.png)

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
already exist. **No new models, textures or icons, and no base game file is
replaced.**

The hook is `addModifier("loadConstruction", ...)`, registered from the mod's
`runFn`. It adds the parameter to every template that offers a platform count -
driven off the presence of `platforms` rather than a hardcoded list, so a new
era or a re-enabled cargo specialisation picks it up too - and repoints the
station's `createTemplateScript` at a function that calls the stock one and
mirrors its result.

See [NOTES.md](NOTES.md) for the reverse-engineered details and
[PLAN.md](PLAN.md) for the implementation and test plan.

## The option

The option only appears for a single platform, since two and four have no side
to choose.

| Value | Effect |
| --- | --- |
| Standard | exactly the stock layout |
| Other side | the platform moves across the entrance |

The labels avoid "Left" and "Right" on purpose: which on-screen side the stock
platform lands on depends on how the station is rotated when you place it, so a
fixed left/right label would be wrong half the time.

"Platform Orientation" and "Standard" are already in the base game's string
catalogs for all ten shipped languages - the first is what the stock underground
street station calls its own equivalent control - so only "Other side" needed
translating, in `strings.json`.

## Savegame safety

The mod only changes the placement dialog, so it can be added to a savegame at
any time, and **removed again at any time** - tested, with a station already
built on the other side. The layout is baked into the construction's stored
`params.modules` at placement, and the stock `updateFn` - which the mod never
touches - renders from that, not from the platform count. Stations already
built keep their layout either way, so `severityRemove` is `None`.

See "Removing the mod from a savegame" in [PLAN.md](PLAN.md), and the project
root [NOTES.md](../NOTES.md) for the general rule this is an instance of.

## Layout

```
mod/pick_single_platform_side_1/   the publishable mod (deploy.ps1 installs this)
tools/make_listing_image.ps1       renders the listing image
deploy.ps1                         copy to the user mods folder, or the staging area
```

`.\deploy.ps1` installs to `mods\` for normal play; `.\deploy.ps1 -Staging`
installs to `staging_area\`, which is the only place the in-game publisher reads
from. Mods are read at startup, so restart the game after deploying.
