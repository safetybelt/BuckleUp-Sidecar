# BuckleUpSidecar

`BuckleUpSidecar` is a hybrid World of Warcraft addon that supplements Blizzard's native Cooldown Viewer instead of replacing it.

Blizzard keeps ownership of Blizzard-managed spell cooldowns and their built-in aura behavior. `BuckleUpSidecar` adds flexible, addon-owned bars for the gaps Blizzard does not handle well by default:

- trinket slots
- racials
- custom spells by spell ID
- custom items by item ID

## What It Does

- embeds a `Sidecar` tab directly into Blizzard's cooldown settings
- lets you drag entries between user bars and `Not Displayed`
- uses Blizzard Edit Mode for Sidecar bar placement and snap behavior
- provides a Sidecar Edit Mode panel for bar presentation settings
- supports live bar matching against Blizzard `Essential` and `Utility` cooldown viewers
- optionally applies a unified square-style visual treatment to both Sidecar bars and Blizzard cooldown viewers

## Current Features

- embedded `Sidecar` tab inside Blizzard's cooldown settings
- drag-and-drop organizer with `Not Displayed` and user bars
- custom side-tab icon and Blizzard-aligned styling
- add custom spells by spell ID and custom items by item ID
- create, rename, and delete Sidecar bars
- Blizzard Edit Mode placement for Sidecar bars
- Sidecar Edit Mode panel for `Match Mode`, size, padding, opacity, visibility, and growth direction
- live `Match Essential Bar` / `Match Utility Bar` presentation modes
- spec-based layouts with copy-from-other-spec support
- optional runtime tooltip toggle
- optional unified visual style for Sidecar runtime bars and Blizzard cooldown viewers
- custom spell and item validation before entries are added
- slash-command removal for accidental custom entries

## Runtime Behavior

- Blizzard-owned spell cooldowns stay in Blizzard's viewer
- Sidecar-owned entries render only on Sidecar bars
- custom items remain visible on Sidecar bars and gray out when unavailable or unusable
- spell and racial entries gray out based on runtime cooldown/charge state
- passive trinkets can stay assigned in config, but do not occupy runtime bar space until an on-use trinket is equipped in that slot
- deleting a bar moves its assigned entries back to `Not Displayed`
- trinket slot entries are protected from deletion
- custom-entry aura swapping is not a guaranteed feature

## Bar Placement And Presentation

- Sidecar bars are moved in Blizzard Edit Mode
- Sidecar bars can stay attached to Blizzard cooldown viewers
- the Sidecar Edit Mode panel exposes:
  - `Match Mode`: `Manual`, `Match Essential Bar`, `Match Utility Bar`
  - `Size`: `50%` to `200%`
  - `Padding`: `0` to `14`
  - `Opacity`: `50%` to `100%`
  - `Visibility`: `Always`, `In Combat`, `Hidden`
  - `Growth Direction`: `Left`, `Center`, `Right`
- when a match mode is enabled, Sidecar follows the matched Blizzard bar's presentation settings live

## Unified Visual Style

- the unified visual style option restyles:
  - Sidecar runtime bars
  - Blizzard `Essential` cooldown viewer
  - Blizzard `Utility` cooldown viewer
  - Blizzard tracked buff icon and bar viewers
- the feature changes presentation only; Blizzard still owns Blizzard cooldown logic and aura behavior

## Slash Commands

- `/bus config` opens Blizzard's Cooldown Viewer settings and shows the Sidecar panel
- `/bus catalog`
- `/bus profile`
- `/bus layouts`
- `/bus addspell <spellID>`
- `/bus additem <itemID>`
- `/bus remove <entryID|rawID>`
- `/bus move <entryID|rawID> <barID|hidden>`
- `/bus addbar <name>`

## Data Model

- active profile data is spec-based
- layout snapshot copy/import is spec-based
- bars and entries are stored in `BuckleUpSidecarDB`

## Limitations

- this is not a replacement cooldown manager
- Blizzard-owned spell cooldowns are intentionally left to Blizzard
- addon-owned entries are focused on reliable cooldown display, not automatic aura-swap parity with Blizzard

## License

MIT. See [LICENSE](D:/projects/WoW%20Addons/BuckleUpSidecar/LICENSE).
