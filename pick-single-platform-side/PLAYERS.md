# Pick Single Platform Side, for players

The bus station and the cargo truck station let you pick one, two or four
platforms. With two or four the layout is symmetric about the entrance, so there
is nothing to choose. With **one** platform there is: the stock station always
puts it on the same side, and that is sometimes the wrong side for the spot you
are building on.

This mod adds a **Platform Orientation** option to the placement dialog, next to
the platform count.

| Value | Effect |
| --- | --- |
| Standard | exactly the stock layout |
| Other side | the platform moves across the entrance |

The option only appears for a single platform, since two and four have no side
to choose.

## Why "Other side" and not "Left"

Which on-screen side the stock platform lands on depends on how the station is
rotated when you place it, so a fixed left/right label would be wrong half the
time.

"Platform Orientation" and "Standard" are already in the base game's string
catalogs for all ten shipped languages - the first is what the stock underground
street station calls its own equivalent control - so only "Other side" needed
translating.

## What it does not change

Nothing else. No new models, textures or icons, and no base game file is
replaced: the left-hand and right-hand platform models both already exist in the
game, and the layout this mod picks is one you can reach by hand today by adding
a platform module on the left and deleting the one on the right.

## Savegames

**Safe to add at any time, and safe to remove again at any time** - tested, with
a station already built on the other side.

The mod only changes the placement dialog. The layout is baked into the
construction when you place it, and the game's own code renders from that, not
from the platform count - so stations already built keep their layout whether
the mod is there or not. That is why it declares `severityRemove: None`.

[Multi-layer Stations](../multi-layer-stations/PLAYERS.md) is the opposite case
and shows where the line is: that mod *is* the station, so its stations have
nowhere to come from without it.

## Installing

See the repository's [PLAYERS.md](../PLAYERS.md) for installing by hand and for
turning a mod on in a savegame. Subscribing on mod.io does the installing for
you; enabling it per save is still yours to do.
