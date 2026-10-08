-- Default settings for Universal Consumables.
-- Steamodded loads this into SMODS.current_mod.config and persists changes
-- made in the mod's config tab.
return {
  -- Key that cycles the target area (hand / jokers / consumables).
  toggle_key = "tab",

  -- When on, effects that destroy or overwrite one specific card only act on
  -- cards you have actually clicked on while in Joker or Consumable mode.
  safe_targeting = true,

  -- Show the "TARGET: ..." button on a consumable's hover panel.
  show_mode_button = true,
}
