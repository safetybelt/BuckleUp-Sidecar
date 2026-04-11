# Changelog

## 1.0.0

Initial public `BuckleUpSidecar` release.

- Added a `Sidecar` tab embedded in Blizzard's cooldown settings
- Added drag-and-drop organization with user bars and `Not Displayed`
- Added support for trinket slots, racials, custom spells, and custom items
- Added per-bar layout controls for size, spacing, anchoring, side, and growth
- Added attachment to Blizzard `Essential` and `Utility` cooldown viewers
- Added spec-based layout copy and reset behavior
- Added lock/unlock behavior for runtime bars with hidden titles while locked
- Added optional runtime tooltip suppression
- Added validation for custom spell and item IDs before they are stored
- Added `/bus remove` for cleaning up accidental custom entries
- Passive trinkets no longer consume runtime bar space unless the equipped trinket has a use effect
