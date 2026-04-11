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
- supports custom bars for supplemental cooldowns without taking over Blizzard's default spell list
- matches Blizzard's cooldown settings UI closely enough to feel at home there

## V1 Features

- embedded `Sidecar` tab inside Blizzard's cooldown settings
- drag-and-drop organizer with `Not Displayed` and user bars
- custom side-tab icon and Blizzard-aligned styling
- per-bar rename, delete, and inline layout editing
- per-bar icon size, spacing, anchor target, anchor side, and growth direction
- screen anchoring or attachment to Blizzard `Essential` / `Utility` cooldown viewers
- spec-based layouts with copy-from-other-spec support
- lock bars and hide runtime titles while locked
- optional runtime tooltip toggle
- custom spell and item validation before entries are added
- slash-command removal for accidental custom entries

## Runtime Behavior

- Blizzard-owned spell cooldowns stay in Blizzard's viewer
- Sidecar-owned entries render only on Sidecar bars
- passive trinkets can stay assigned in config, but do not occupy runtime bar space until an on-use trinket is equipped in that slot
- deleting a bar moves its assigned entries back to `Not Displayed`
- custom-entry aura swapping is not a guaranteed feature

## Slash Commands

- `/bus config`
- `/bus catalog`
- `/bus profile`
- `/bus layouts`
- `/bus addspell <spellID>`
- `/bus additem <itemID>`
- `/bus remove <entryID|rawID>`
- `/bus move <entryID|rawID> <barID|hidden>`
- `/bus addbar <name>`

## Data Model

- active profiles are spec-based
- layout copy/import is spec-based
- bars and entries are stored in `BuckleUpSidecarDB`

## Limitations

- this is not a replacement cooldown manager
- Blizzard-owned spell cooldowns are intentionally left to Blizzard
- addon-owned entries are focused on reliable cooldown display, not automatic aura-swap parity with Blizzard

## License

MIT. See [LICENSE](D:/projects/WoW%20Addons/BuckleUpSidecar/LICENSE).
