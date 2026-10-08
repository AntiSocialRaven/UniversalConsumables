--- STEAMODDED HEADER
--- MOD_NAME: Universal Consumables
--- MOD_ID: ucsm
--- MOD_AUTHOR: [hydrophobis]
--- MOD_DESCRIPTION: Allows tarot and spectral cards to be used on jokers and consumables.
--- DEPENDENCIES: [Steamodded>=0.9.8]
--- PRIORITY: 100
--- VERSION: 1.1.0

UC = UC or {}

UC.API_VERSION = 1

-- =========================================================================
-- Configuration
-- =========================================================================

UC.mod = SMODS.current_mod

UC.default_config = {
  toggle_key = "tab",
  -- When on, effects that destroy or overwrite one specific card will only
  -- act on cards you have actually clicked on while in Joker/Consumable
  -- mode. This is what stops a stray effect from eating a joker.
  safe_targeting = true,
  show_mode_button = true,
}

function UC.cfg()
  local c = UC.mod and UC.mod.config
  if type(c) ~= "table" then return UC.default_config end
  for k, v in pairs(UC.default_config) do
    if c[k] == nil then c[k] = v end
  end
  return c
end

-- =========================================================================
-- Vanilla crash guards (kept from 1.0.x)
-- =========================================================================

-- JokerDisplay and similar mods pass joker cards to poker hand evaluation,
-- which crashes in get_X_same because jokers lack base.value.
local UC_orig_get_X_same = get_X_same
get_X_same = function(num, hand, or_more)
  local clean = {}
  for _, c in ipairs(hand or {}) do
    if c.base and c.base.value then clean[#clean + 1] = c end
  end
  if #clean < (num or 0) then return {} end
  return UC_orig_get_X_same(num, clean, or_more)
end

-- get_poker_hand_info can return nil for scoring_hand when non-playing cards
-- are in the hand. That crashes any caller doing pairs(scoring_hand).
local UC_orig_get_poker_hand_info = G.FUNCS.get_poker_hand_info
if UC_orig_get_poker_hand_info then
  G.FUNCS.get_poker_hand_info = function(...)
    local a, b, c, d, e = UC_orig_get_poker_hand_info(...)
    if d == nil then d = {} end
    return a, b, c, d, e
  end
end

-- =========================================================================
-- Target modes
-- =========================================================================

UC.MODES = { "hand", "jokers", "consumables" }
UC.MODE_INDEX = { hand = 1, jokers = 2, consumables = 3 }
UC.MODE_LABEL = { hand = "HAND", jokers = "JOKERS", consumables = "CONSUMABLES" }
UC.MODE_HINT = {
  hand = "the cards in your hand",
  jokers = "your Jokers",
  consumables = "your other consumables",
}

UC.specs = {}     -- key -> spec table, for cards UC implements itself
UC.declared = {}  -- key -> {mode=true}, for cards other mods made mode-aware
UC.orig = {}      -- key -> captured pre-ownership implementation

UC._mode = "hand"

function UC.get_mode()
  local m = (G and G.GAME and G.GAME.ucsm_mode) or UC._mode
  if not UC.MODE_INDEX[m] then m = "hand" end
  return m
end

-- Public alias for other mods.
function UC.mode() return UC.get_mode() end
function UC.is_mode(m) return UC.get_mode() == m end

function UC.set_mode(m)
  if not UC.MODE_INDEX[m] then m = "hand" end
  UC._mode = m
  if G and G.GAME then G.GAME.ucsm_mode = m end
  UC.refresh_ui()
  return m
end

function UC.mode_colour(m)
  if not (G and G.C) then return nil end
  if m == "jokers" then return G.C.RED end
  if m == "consumables" then return G.C.PURPLE end
  return G.C.BLUE
end

function UC.area_for(mode)
  if mode == "hand" then return G.hand end
  if mode == "jokers" then return G.jokers end
  if mode == "consumables" then return G.consumeables end
  return nil
end

-- A mode is available when its area exists and holds something to point at.
-- Hand mode stays available whenever a hand exists so the vanilla behaviour
-- of every card is always one toggle away.
function UC.mode_available(mode, exclude)
  if mode == "hand" then return G.hand ~= nil end
  local area = UC.area_for(mode)
  if not (area and area.cards) then return false end
  for _, c in ipairs(area.cards) do
    if c ~= exclude then return true end
  end
  return false
end

-- =========================================================================
-- Which modes a given card understands
-- =========================================================================

function UC.short_key(card)
  local center = card and card.config and card.config.center
  local key = center and center.key
  if type(key) ~= "string" then return nil end
  return (key:gsub("^c_", ""))
end

-- Other mods call this to announce that their consumable reads UC.get_mode()
-- (usually through UC.choose). Accepts the center key with or without "c_".
function UC.declare(key, modes)
  if type(key) ~= "string" then return end
  key = (key:gsub("^c_", ""))
  local t = {}
  for _, m in ipairs(modes or {}) do
    if UC.MODE_INDEX[m] then t[m] = true end
  end
  UC.declared[key] = t
end

function UC.card_modes(card)
  local key = UC.short_key(card)
  local out = {}
  if not key then return out end
  local spec = UC.specs[key]
  if spec then
    for _, m in ipairs(UC.MODES) do
      if spec[m] ~= nil then out[#out + 1] = m end
    end
    return out
  end
  local d = UC.declared[key]
  if d then
    for _, m in ipairs(UC.MODES) do
      if d[m] then out[#out + 1] = m end
    end
  end
  return out
end

function UC.card_supports(card, mode)
  for _, m in ipairs(UC.card_modes(card)) do
    if m == mode then return true end
  end
  return false
end

-- The mode this specific card will actually use. If the player is in a mode
-- this card has nothing to do with, the card quietly falls back to the area
-- it targets in the base game rather than becoming unusable.
function UC.effective_mode(card)
  local mode = UC.get_mode()
  local modes = UC.card_modes(card)
  if #modes == 0 then return mode end
  for _, m in ipairs(modes) do
    if m == mode then return mode end
  end
  local spec = UC.specs[UC.short_key(card)]
  if spec and spec.vanilla then return spec.vanilla end
  return modes[1]
end

function UC.cycle_mode(announce, card)
  local allowed = UC.card_modes(card)
  local function permitted(m)
    if #allowed == 0 then return true end
    for _, a in ipairs(allowed) do
      if a == m then return true end
    end
    return false
  end

  local cur = UC.MODE_INDEX[UC.get_mode()]
  for i = 1, #UC.MODES do
    local m = UC.MODES[((cur - 1 + i) % #UC.MODES) + 1]
    if permitted(m) and UC.mode_available(m, card) then
      UC.set_mode(m)
      if announce then UC.announce(m, card) end
      return m
    end
  end
  return UC.get_mode()
end

function UC.announce(mode, card)
  play_sound("cardSlide1", 1.1, 0.4)
  local major = card
  if not major and G.consumeables and G.consumeables.cards[1] then
    major = G.consumeables.cards[1]
  end
  attention_text({
    text = "TARGET: " .. (UC.MODE_LABEL[mode] or "?"),
    scale = 0.8, hold = 1.2, align = "cm",
    offset = { x = 0, y = 0 },
    major = major or G.consumeables or G.ROOM_ATTACH,
  })
end

-- =========================================================================
-- Targeting helpers (also the public API for other mods)
-- =========================================================================

-- Highlighted cards in a mode's area, in board order, capped at `max`.
function UC.highlighted_in(mode, exclude, max)
  local area = UC.area_for(mode)
  local out = {}
  if not (area and area.cards) then return out end
  for _, c in ipairs(area.cards) do
    if c.highlighted and c ~= exclude then out[#out + 1] = c end
  end
  while max and max > 0 and #out > max do table.remove(out) end
  return out
end

function UC.all_in(mode, exclude)
  local area = UC.area_for(mode)
  local out = {}
  if not (area and area.cards) then return out end
  for _, c in ipairs(area.cards) do
    if c ~= exclude then out[#out + 1] = c end
  end
  return out
end

-- Public helper for other mods: pick from `candidates`, preferring whatever
-- the player highlighted while in `mode`, otherwise falling back to the
-- mod's own random roll. `seed` is a pseudoseed string.
function UC.choose(candidates, seed, mode)
  candidates = candidates or {}
  if #candidates == 0 then return nil end
  if (not mode) or UC.get_mode() == mode then
    for _, c in ipairs(candidates) do
      if c.highlighted then return c end
    end
  end
  return pseudorandom_element(candidates, pseudoseed(seed or "ucsm"))
end

-- Eternal jokers cannot be destroyed, and overwriting one destroys it in all
-- but name, so UC refuses both.
function UC.protected(c)
  return (c and c.ability and c.ability.eternal) and true or false
end

function UC.safe_targeting()
  return UC.cfg().safe_targeting ~= false
end

function UC.msg(card, text, colour)
  if not card then return end
  card_eval_status_text(card, "extra", nil, nil, nil,
    { message = text, colour = colour or G.C.FILTER })
end

function UC.destroy(c)
  if not c then return end
  if c.area == G.hand then G.hand:remove_card(c) end
  c:start_dissolve(nil, true)
end

function UC.after(delay_s, fn)
  G.E_MANAGER:add_event(Event({
    trigger = "after", delay = delay_s or 0.1,
    func = function() fn(); return true end,
  }))
end

function UC.max_highlighted(card, fallback)
  local n = card and card.ability and card.ability.consumeable
      and card.ability.consumeable.max_highlighted
  if not n then
    local cc = card and card.config and card.config.center and card.config.center.config
    n = cc and cc.max_highlighted
  end
  return n or fallback
end

function UC.rarity_num(c)
  local r = c and c.config and c.config.center and c.config.center.rarity or 1
  if type(r) == "string" then
    r = ({ Common = 1, Uncommon = 2, Rare = 3, Legendary = 4 })[r] or 1
  end
  return tonumber(r) or 1
end

function UC.room_in(area, needed)
  if not area then return false end
  local lim = (area.config and area.config.card_limit) or 5
  local buffer = 0
  if area == G.consumeables then buffer = G.GAME.consumeable_buffer or 0 end
  return #area.cards + buffer + (needed or 1) <= lim
end

-- =========================================================================
-- Card definition / delegation
-- =========================================================================

local function center_obj(key)
  if SMODS and SMODS.Consumables then
    if SMODS.Consumables[key] then return SMODS.Consumables[key] end
    if SMODS.Consumables["c_" .. key] then return SMODS.Consumables["c_" .. key] end
  end
  if G and G.P_CENTERS then return G.P_CENTERS["c_" .. key] end
  return nil
end

-- Snapshot whatever implementation is on the card before UC overwrites it.
-- If another mod already customised this card, UC hands control straight
-- back to it whenever the player is targeting the area that card natively
-- works on, so the other mod keeps working untouched.
local function capture(key)
  local obj = center_obj(key)
  if obj then
    UC.orig[key] = { obj = obj, can_use = obj.can_use, use = obj.use }
  end
  return UC.orig[key]
end

function UC.has_delegate(key)
  local o = UC.orig[key]
  return (o and type(o.use) == "function") and true or false
end

local function delegate_can(key, self, card)
  local o = UC.orig[key]
  if not (o and type(o.can_use) == "function") then return true end
  local ok, r = pcall(o.can_use, o.obj or self, card)
  if not ok then return true end
  return r == true
end

local function delegate_use(key, self, card, area, copier)
  local o = UC.orig[key]
  if not (o and type(o.use) == "function") then return end
  pcall(o.use, o.obj or self, card, area, copier)
end

local function resolve(key, mode, card)
  local spec = UC.specs[key]
  if not spec then return nil end
  if mode == spec.vanilla and UC.has_delegate(key) then return "delegate" end
  return spec[mode]
end

-- Returns the targets plus whether the player has more cards selected than
-- the card accepts. Like the base game, too many selected means the card is
-- unusable rather than silently acting on the first few.
local function spec_targets(spec, handler, card, mode)
  local max = UC.max_highlighted(card, spec.max)
  if handler.targets then return handler.targets(card, mode, max) or {}, false end
  local t = UC.highlighted_in(mode, card)
  local over = (max and max > 0 and #t > max) or false
  return t, over
end

function UC.can_use(key, self, card)
  local spec = UC.specs[key]
  if not spec then return false end
  local mode = UC.effective_mode(card)
  local handler = resolve(key, mode, card)
  if handler == nil then return false end
  if handler == "delegate" then return delegate_can(key, self, card) end
  local t, over = spec_targets(spec, handler, card, mode)
  if over then return false end
  if handler.can then
    local ok, r = pcall(handler.can, card, mode, t)
    return ok and r == true
  end
  return #t > 0
end

function UC.use(key, self, card, area, copier)
  local spec = UC.specs[key]
  if not spec then return end
  local mode = UC.effective_mode(card)
  local handler = resolve(key, mode, card)
  if handler == nil then return end
  if handler == "delegate" then return delegate_use(key, self, card, area, copier) end
  local t, over = spec_targets(spec, handler, card, mode)
  if over then return end
  UC.after(0.1, function() handler.run(card, mode, t) end)
end

function UC.define(key, spec)
  if not center_obj(key) then return end
  spec.max = spec.max or 1
  spec.vanilla = spec.vanilla or "hand"
  UC.specs[key] = spec
  capture(key)
  SMODS.Consumable:take_ownership(key, {
    can_use = function(self, card) return UC.can_use(key, self, card) end,
    use = function(self, card, area, copier) return UC.use(key, self, card, area, copier) end,
  }, true)
end

-- =========================================================================
-- Joker conversion tables
-- =========================================================================

local JOKER_FOR_ENHANCE = {
  m_lucky = "j_lucky_cat",
  m_wild  = "j_smeared",
  m_steel = "j_steel_joker",
  m_glass = "j_glass",
  m_gold  = "j_golden_ticket",
  m_stone = "j_stone",
  m_mult  = "j_jolly",
  m_bonus = "j_zany",
}

local JOKER_FOR_SUIT_COMMON = {
  Diamonds = "j_greedy_joker",
  Clubs    = "j_gluttonous_joker",
  Hearts   = "j_lusty_joker",
  Spades   = "j_wrathful_joker",
}
local JOKER_FOR_SUIT_RARE = {
  Diamonds = "j_rough_gem",
  Clubs    = "j_onyx_agate",
  Hearts   = "j_bloodstone",
  Spades   = "j_arrowhead",
}

function UC.can_convert_joker(c, joker_key)
  if not (c and joker_key) then return false end
  if UC.protected(c) then return false end
  if not (G.P_CENTERS and G.P_CENTERS[joker_key]) then return false end
  local cur = c.config and c.config.center and c.config.center.key
  return cur ~= joker_key
end

function UC.swap_to_joker(t, joker_key)
  local center = G.P_CENTERS[joker_key]
  if not center then return end
  t:set_ability(center)
  t:juice_up(0.3, 0.2)
  UC.msg(t, localize("k_upgrade_ex"), G.C.PURPLE)
end

local function any_convertible(targets, joker_key)
  for _, c in ipairs(targets) do
    if UC.can_convert_joker(c, joker_key) then return true end
  end
  return false
end

-- =========================================================================
-- Tarot: enhancements
-- =========================================================================

local function def_enhance(key, center_key, msg_key, colour_key, max)
  local joker_key = JOKER_FOR_ENHANCE[center_key]
  UC.define(key, {
    vanilla = "hand",
    max = max,
    hand = {
      run = function(card, mode, t)
        for _, c in ipairs(t) do
          c:set_ability(G.P_CENTERS[center_key])
          UC.msg(c, localize(msg_key), G.C[colour_key])
        end
      end,
    },
    jokers = joker_key and {
      can = function(card, mode, t) return any_convertible(t, joker_key) end,
      run = function(card, mode, t)
        for _, c in ipairs(t) do
          if UC.can_convert_joker(c, joker_key) then UC.swap_to_joker(c, joker_key) end
        end
      end,
    } or nil,
  })
end

def_enhance("magician",   "m_lucky", "k_lucky_ex", "MULT",   2)
def_enhance("lovers",     "m_wild",  "k_wild_ex",  "GREEN",  1)
def_enhance("chariot",    "m_steel", "k_steel_ex", "BLUE",   1)
def_enhance("justice",    "m_glass", "k_glass_ex", "BLUE",   1)
def_enhance("devil",      "m_gold",  "k_gold_ex",  "MONEY",  1)
def_enhance("tower",      "m_stone", "k_stone_ex", "CHIPS",  1)
def_enhance("empress",    "m_mult",  "k_mult_ex",  "MULT",   2)
def_enhance("hierophant", "m_bonus", "k_bonus_ex", "CHIPS",  2)

-- =========================================================================
-- Tarot: suits
-- =========================================================================

local function def_suit(key, suit)
  UC.define(key, {
    vanilla = "hand",
    max = 3,
    hand = {
      run = function(card, mode, t)
        for _, c in ipairs(t) do
          c:change_suit(suit)
          UC.msg(c, localize(suit, "suits_plural"), G.C.SUITS[suit])
        end
      end,
    },
    jokers = {
      can = function(card, mode, t)
        for _, c in ipairs(t) do
          local jk = (UC.rarity_num(c) >= 2) and JOKER_FOR_SUIT_RARE[suit] or JOKER_FOR_SUIT_COMMON[suit]
          if UC.can_convert_joker(c, jk) then return true end
        end
        return false
      end,
      run = function(card, mode, t)
        for _, c in ipairs(t) do
          local jk = (UC.rarity_num(c) >= 2) and JOKER_FOR_SUIT_RARE[suit] or JOKER_FOR_SUIT_COMMON[suit]
          if UC.can_convert_joker(c, jk) then UC.swap_to_joker(c, jk) end
        end
      end,
    },
  })
end

def_suit("star",  "Diamonds")
def_suit("moon",  "Clubs")
def_suit("sun",   "Hearts")
def_suit("world", "Spades")

-- =========================================================================
-- Strength
-- =========================================================================

local function rank_up(c)
  local cc = c.config and c.config.card
  if not (cc and cc.suit and cc.value and SMODS.Suits[cc.suit] and SMODS.Ranks[cc.value]) then return end
  local suit_key = SMODS.Suits[cc.suit].card_key
  for i, rk in ipairs(SMODS.Rank.obj_buffer) do
    if rk == cc.value then
      local next_key = SMODS.Rank.obj_buffer[i + 1] or SMODS.Rank.obj_buffer[1]
      local next_rank = SMODS.Ranks[next_key]
      if next_rank then c:set_base(G.P_CARDS[suit_key .. "_" .. next_rank.card_key]) end
      return
    end
  end
end

local function joker_rarity_pool(next_rarity)
  local eligible = {}
  for _, j in ipairs(G.P_CENTER_POOLS["Joker"] or {}) do
    local r = j.rarity
    if type(r) == "string" then
      r = ({ Common = 1, Uncommon = 2, Rare = 3, Legendary = 4 })[r] or 1
    end
    if r == next_rarity and not j.no_pool_flag then eligible[#eligible + 1] = j end
  end
  return eligible
end

UC.define("strength", {
  vanilla = "hand",
  max = 2,
  hand = {
    run = function(card, mode, t)
      for _, c in ipairs(t) do
        rank_up(c)
        UC.msg(c, localize("k_upgrade_ex"), G.C.CHIPS)
      end
    end,
  },
  jokers = {
    can = function(card, mode, t)
      for _, c in ipairs(t) do
        if not UC.protected(c) and UC.rarity_num(c) < 4
            and #joker_rarity_pool(UC.rarity_num(c) + 1) > 0 then
          return true
        end
      end
      return false
    end,
    run = function(card, mode, t)
      for _, c in ipairs(t) do
        if not UC.protected(c) and UC.rarity_num(c) < 4 then
          local pool = joker_rarity_pool(UC.rarity_num(c) + 1)
          if #pool > 0 then
            c:set_ability(pseudorandom_element(pool, pseudoseed("ucsm_strength")))
            c:juice_up(0.3, 0.2)
            UC.msg(c, localize("k_upgrade_ex"), G.C.CHIPS)
          end
        end
      end
    end,
  },
})

-- =========================================================================
-- The Hanged Man
-- =========================================================================

local function destroyable(t)
  local out = {}
  for _, c in ipairs(t) do
    if not UC.protected(c) then out[#out + 1] = c end
  end
  return out
end

UC.define("hanged_man", {
  vanilla = "hand",
  max = 2,
  hand = {
    run = function(card, mode, t)
      for _, c in ipairs(t) do UC.destroy(c) end
    end,
  },
  jokers = {
    can = function(card, mode, t) return #destroyable(t) > 0 end,
    run = function(card, mode, t)
      for _, c in ipairs(destroyable(t)) do UC.destroy(c) end
    end,
  },
  consumables = {
    can = function(card, mode, t) return #destroyable(t) > 0 end,
    run = function(card, mode, t)
      for _, c in ipairs(destroyable(t)) do UC.destroy(c) end
    end,
  },
})

-- =========================================================================
-- Death
--
-- Base game Death turns the LEFT selected card into a copy of the RIGHT one.
-- Jokers and consumables now follow the same direction: the rightmost card
-- you pick is the original, the leftmost becomes the copy.
-- =========================================================================

local function death_pair(t)
  if #t < 2 then return nil, nil end
  -- UC.highlighted_in walks area.cards, so t is already left-to-right.
  return t[#t], t[1] -- src (right), dst (left)
end

UC.define("death", {
  vanilla = "hand",
  max = 2,
  hand = {
    can = function(card, mode, t) return #t >= 2 end,
    run = function(card, mode, t)
      local src, dst = death_pair(t)
      if not (src and dst) then return end
      if src.config and src.config.card and next(src.config.card) then
        dst:set_base(src.config.card)
      end
      dst:set_ability(src.config.center)
      UC.copy_extras(src, dst)
      dst:juice_up(0.3, 0.2)
      UC.msg(dst, localize("k_copied_ex"), G.C.PURPLE)
    end,
  },
  jokers = {
    can = function(card, mode, t)
      local src, dst = death_pair(t)
      return src ~= nil and dst ~= nil and not UC.protected(dst)
    end,
    run = function(card, mode, t)
      local src, dst = death_pair(t)
      if not (src and dst) or UC.protected(dst) then return end
      dst:set_ability(src.config.center)
      UC.copy_extras(src, dst)
      dst:juice_up(0.3, 0.2)
      UC.msg(dst, localize("k_copied_ex"), G.C.PURPLE)
    end,
  },
  consumables = {
    can = function(card, mode, t)
      local src, dst = death_pair(t)
      return src ~= nil and dst ~= nil and not UC.protected(dst)
    end,
    run = function(card, mode, t)
      local src, dst = death_pair(t)
      if not (src and dst) or UC.protected(dst) then return end
      dst:set_ability(src.config.center)
      UC.copy_extras(src, dst)
      dst:juice_up(0.3, 0.2)
      UC.msg(dst, localize("k_copied_ex"), G.C.PURPLE)
    end,
  },
})

function UC.copy_extras(src, dst)
  if src.edition then dst:set_edition(src.edition, true) else dst:set_edition(nil, true) end
  if src.seal then dst:set_seal(src.seal, true, true)
  elseif dst.seal then dst:set_seal(nil, true, true) end
end

-- =========================================================================
-- Seal spectrals
-- =========================================================================

local function def_seal(key, seal, msg_key, colour_key)
  local function sealable(t)
    local out = {}
    for _, c in ipairs(t) do
      if c.seal ~= seal then out[#out + 1] = c end
    end
    return out
  end
  local function apply(t)
    for _, c in ipairs(sealable(t)) do
      c:set_seal(seal, true, true)
      UC.msg(c, localize(msg_key), G.C[colour_key])
    end
  end
  UC.define(key, {
    vanilla = "hand",
    max = 1,
    hand = {
      can = function(card, mode, t) return #sealable(t) > 0 end,
      run = function(card, mode, t) apply(t) end,
    },
    jokers = {
      can = function(card, mode, t) return #sealable(t) > 0 end,
      run = function(card, mode, t) apply(t) end,
    },
  })
end

def_seal("talisman", "Gold",   "k_gold_seal",   "MONEY")
def_seal("deja_vu",  "Red",    "k_red_seal",    "RED")
def_seal("trance",   "Blue",   "k_blue_seal",   "BLUE")
def_seal("medium",   "Purple", "k_purple_seal", "PURPLE")

-- =========================================================================
-- Aura
-- =========================================================================

local function roll_edition(seed)
  local r = pseudorandom(pseudoseed(seed))
  if r < 0.5 then return "foil" elseif r < 0.85 then return "holo" else return "polychrome" end
end

local function def_aura_mode()
  return {
    can = function(card, mode, t) return #t > 0 end,
    run = function(card, mode, t)
      local target = t[1]
      if not target then return end
      target:set_edition({ [roll_edition("ucsm_aura")] = true }, true)
      UC.msg(target, localize("k_upgrade_ex"), G.C.PURPLE)
    end,
  }
end

UC.define("aura", {
  vanilla = "hand",
  max = 1,
  hand = def_aura_mode(),
  jokers = def_aura_mode(),
})

-- =========================================================================
-- Cryptid
-- =========================================================================

UC.define("cryptid", {
  vanilla = "hand",
  max = 1,
  hand = {
    can = function(card, mode, t) return #t > 0 end,
    run = function(card, mode, t)
      local src = t[1]
      if not src then return end
      for _ = 1, 2 do
        G.playing_card = (G.playing_card and G.playing_card + 1) or 1
        local copy = copy_card(src, nil, nil, G.playing_card)
        copy:add_to_deck()
        G.deck.config.card_limit = G.deck.config.card_limit + 1
        table.insert(G.playing_cards, copy)
        G.deck:emplace(copy)
      end
      UC.msg(src, localize("k_copied_ex"), G.C.PURPLE)
    end,
  },
  jokers = {
    can = function(card, mode, t) return #t > 0 and UC.room_in(G.jokers, 2) end,
    run = function(card, mode, t)
      local src = t[1]
      if not src then return end
      for _ = 1, 2 do
        if not UC.room_in(G.jokers, 1) then break end
        local copy = copy_card(src, nil, nil, nil)
        copy:add_to_deck()
        G.jokers:emplace(copy)
        copy:juice_up(0.3, 0)
        UC.msg(copy, localize("k_copied_ex"), G.C.PURPLE)
      end
    end,
  },
  consumables = {
    can = function(card, mode, t) return #t > 0 and UC.room_in(G.consumeables, 1) end,
    run = function(card, mode, t)
      local src = t[1]
      if not (src and UC.room_in(G.consumeables, 1)) then return end
      local copy = copy_card(src, nil, nil, nil)
      copy:add_to_deck()
      G.consumeables:emplace(copy)
      copy:juice_up(0.3, 0)
      UC.msg(copy, localize("k_copied_ex"), G.C.PURPLE)
    end,
  },
})

-- =========================================================================
-- Immolate
-- =========================================================================

local function pick_victims(pool, count, seed)
  local chosen = {}
  local work = {}
  for _, c in ipairs(pool) do work[#work + 1] = c end
  for _ = 1, math.min(count, #work) do
    local idx = pseudorandom(seed, 1, #work)
    chosen[#chosen + 1] = table.remove(work, idx)
  end
  return chosen
end

UC.define("immolate", {
  vanilla = "hand",
  max = 0,
  hand = {
    can = function(card, mode, t) return G.hand and #G.hand.cards > 0 end,
    run = function(card, mode, t)
      for _, c in ipairs(pick_victims(UC.all_in("hand", card), 5, "ucsm_immolate")) do
        UC.destroy(c)
      end
      ease_dollars(20)
      UC.msg(card, "$20", G.C.MONEY)
    end,
  },
  jokers = {
    -- With safe targeting on, Immolate will only eat the jokers you clicked.
    targets = function(card, mode)
      local hl = destroyable(UC.highlighted_in(mode, card, 5))
      if #hl > 0 then return hl end
      if UC.safe_targeting() then return {} end
      return pick_victims(destroyable(UC.all_in(mode, card)), 5, "ucsm_immolate")
    end,
    can = function(card, mode, t) return #t > 0 end,
    run = function(card, mode, t)
      for _, c in ipairs(t) do UC.destroy(c) end
      ease_dollars(20)
      UC.msg(card, "$20", G.C.MONEY)
    end,
  },
})

-- =========================================================================
-- Hex  (base game targets jokers)
-- =========================================================================

local function non_poly(list)
  local out = {}
  for _, c in ipairs(list) do
    if not (c.edition and c.edition.polychrome) then out[#out + 1] = c end
  end
  return out
end

local function hex_run(mode, card, t)
  local chosen = t[1]
  if not chosen then return end
  chosen:set_edition({ polychrome = true }, true)
  UC.msg(chosen, localize("k_upgrade_ex"), G.C.PURPLE)
  for _, c in ipairs(UC.all_in(mode, card)) do
    if c ~= chosen and not UC.protected(c) then UC.destroy(c) end
  end
end

local function hex_targets(card, mode)
  local hl = non_poly(UC.highlighted_in(mode, card, 1))
  if #hl > 0 then return hl end
  local pool = non_poly(UC.all_in(mode, card))
  if #pool == 0 then return {} end
  return { pseudorandom_element(pool, pseudoseed("ucsm_hex")) }
end

UC.define("hex", {
  vanilla = "jokers",
  max = 1,
  hand = {
    targets = hex_targets,
    can = function(card, mode, t) return #t > 0 and #UC.all_in(mode, card) > 1 end,
    run = function(card, mode, t) hex_run(mode, card, t) end,
  },
  jokers = {
    targets = hex_targets,
    can = function(card, mode, t) return #t > 0 end,
    run = function(card, mode, t) hex_run(mode, card, t) end,
  },
})

-- =========================================================================
-- Ankh  (base game targets jokers)
-- =========================================================================

local function ankh_targets(card, mode)
  local hl = UC.highlighted_in(mode, card, 1)
  if #hl > 0 then return hl end
  local pool = UC.all_in(mode, card)
  if #pool == 0 then return {} end
  return { pseudorandom_element(pool, pseudoseed("ucsm_ankh")) }
end

UC.define("ankh", {
  vanilla = "jokers",
  max = 1,
  hand = {
    targets = ankh_targets,
    can = function(card, mode, t) return #t > 0 end,
    run = function(card, mode, t)
      local chosen = t[1]
      if not chosen then return end
      for _, c in ipairs(UC.all_in("hand", card)) do
        if c ~= chosen then UC.destroy(c) end
      end
      G.playing_card = (G.playing_card and G.playing_card + 1) or 1
      local copy = copy_card(chosen, nil, nil, G.playing_card)
      if chosen.edition and chosen.edition.negative then copy:set_edition(nil, true) end
      copy:add_to_deck()
      G.deck.config.card_limit = G.deck.config.card_limit + 1
      table.insert(G.playing_cards, copy)
      G.deck:emplace(copy)
      copy:juice_up(0.3, 0)
      UC.msg(copy, localize("k_copied_ex"), G.C.PURPLE)
    end,
  },
  jokers = {
    targets = ankh_targets,
    can = function(card, mode, t) return #t > 0 and UC.room_in(G.jokers, 1) end,
    run = function(card, mode, t)
      local chosen = t[1]
      if not chosen then return end
      for _, c in ipairs(UC.all_in("jokers", card)) do
        if c ~= chosen and not UC.protected(c) then UC.destroy(c) end
      end
      local copy = copy_card(chosen, nil, nil, nil)
      if chosen.edition and chosen.edition.negative then copy:set_edition(nil, true) end
      copy:add_to_deck()
      G.jokers:emplace(copy)
      copy:juice_up(0.3, 0)
      UC.msg(copy, localize("k_copied_ex"), G.C.PURPLE)
    end,
  },
})

-- =========================================================================
-- Ectoplasm  (base game targets jokers)
-- =========================================================================

local function non_negative(list)
  local out = {}
  for _, c in ipairs(list) do
    if not (c.edition and c.edition.negative) then out[#out + 1] = c end
  end
  return out
end

local function ecto_targets(card, mode)
  local hl = non_negative(UC.highlighted_in(mode, card, 1))
  if #hl > 0 then return hl end
  local pool = non_negative(UC.all_in(mode, card))
  if #pool == 0 then return {} end
  return { pseudorandom_element(pool, pseudoseed("ucsm_ectoplasm")) }
end

local function ecto_mode()
  return {
    targets = ecto_targets,
    can = function(card, mode, t) return #t > 0 end,
    run = function(card, mode, t)
      local chosen = t[1]
      if chosen then
        chosen:set_edition({ negative = true }, true)
        UC.msg(chosen, localize("k_upgrade_ex"), G.C.PURPLE)
      end
      G.GAME.ectoplasm_count = (G.GAME.ectoplasm_count or 0) + 1
      G.hand:change_size(-G.GAME.ectoplasm_count)
      UC.msg(card, localize { type = "variable", key = "a_handsize", vars = { -G.GAME.ectoplasm_count } }, G.C.RED)
    end,
  }
end

UC.define("ectoplasm", {
  vanilla = "jokers",
  max = 1,
  hand = ecto_mode(),
  jokers = ecto_mode(),
  consumables = ecto_mode(),
})

-- =========================================================================
-- Wraith  (base game targets jokers)
-- =========================================================================

UC.define("wraith", {
  vanilla = "jokers",
  max = 0,
  hand = {
    can = function(card, mode, t)
      return G.hand ~= nil and G.STATE == G.STATES.SELECTING_HAND
    end,
    run = function(card, mode, t)
      local suit_keys = { "S", "H", "C", "D" }
      local rank_keys = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
      local enhancements = { "m_bonus", "m_mult", "m_wild", "m_glass", "m_steel", "m_stone", "m_gold", "m_lucky" }
      local editions = { "foil", "holo", "polychrome", "negative" }
      local seals = { "Gold", "Red", "Blue", "Purple" }

      local front = G.P_CARDS[pseudorandom_element(suit_keys, pseudoseed("ucsm_wraith_s")) .. "_"
        .. pseudorandom_element(rank_keys, pseudoseed("ucsm_wraith_r"))]
      if not front then return end

      local center = G.P_CENTERS.c_base
      if pseudorandom(pseudoseed("ucsm_wraith_e")) < 0.7 then
        center = G.P_CENTERS[pseudorandom_element(enhancements, pseudoseed("ucsm_wraith_en"))] or center
      end

      G.playing_card = (G.playing_card and G.playing_card + 1) or 1
      local nc = Card(G.deck.T.x + G.deck.T.w / 2, G.deck.T.y, G.CARD_W, G.CARD_H,
        front, center, { playing_card = G.playing_card })
      table.insert(G.playing_cards, nc)

      if pseudorandom(pseudoseed("ucsm_wraith_ed")) < 0.5 then
        nc:set_edition({ [pseudorandom_element(editions, pseudoseed("ucsm_wraith_edk"))] = true }, true)
      end
      if pseudorandom(pseudoseed("ucsm_wraith_sl")) < 0.5 then
        nc:set_seal(pseudorandom_element(seals, pseudoseed("ucsm_wraith_slk")), true, true)
      end

      nc:add_to_deck()
      G.hand.config.card_limit = G.hand.config.card_limit + 1
      G.hand:emplace(nc)
      nc:start_materialize()
      UC.msg(card, localize("k_added_ex"), G.C.GREEN)
    end,
  },
  jokers = {
    can = function(card, mode, t) return UC.room_in(G.jokers, 1) end,
    run = function(card, mode, t)
      local new_joker = create_card("Joker", G.jokers, nil, 3, nil, nil, nil, "wraith")
      new_joker:add_to_deck()
      G.jokers:emplace(new_joker)
      new_joker:start_materialize()
      UC.msg(card, localize("k_joker_ex"), G.C.PURPLE)
      ease_dollars(-G.GAME.dollars)
      UC.msg(card, "$0", G.C.MONEY)
    end,
  },
})

-- =========================================================================
-- Sigil / Ouija
--
-- These rewrite every card in your hand, so they only have a hand mode.
-- (1.0.x put a "joker mode" on them that wrote ability.forced_suit /
-- ability.forced_rank, fields nothing in the game ever reads. The Use button
-- lit up and the card did nothing, so that mode is gone.)
-- =========================================================================

UC.define("sigil", {
  vanilla = "hand",
  max = 0,
  hand = {
    can = function(card, mode, t) return G.hand and #G.hand.cards > 0 end,
    run = function(card, mode, t)
      local suits = {}
      for _, k in ipairs(SMODS.Suit.obj_buffer) do suits[#suits + 1] = k end
      local suit = pseudorandom_element(suits, pseudoseed("ucsm_sigil")) or "Spades"
      for _, c in ipairs(G.hand.cards) do
        c:change_suit(suit)
        UC.msg(c, localize(suit, "suits_plural"), G.C.SUITS[suit])
      end
    end,
  },
})

UC.define("ouija", {
  vanilla = "hand",
  max = 0,
  hand = {
    can = function(card, mode, t) return G.hand and #G.hand.cards > 0 end,
    run = function(card, mode, t)
      local ranks = {}
      for _, k in ipairs(SMODS.Rank.obj_buffer) do ranks[#ranks + 1] = k end
      local rank = pseudorandom_element(ranks, pseudoseed("ucsm_ouija")) or "Ace"
      for _, c in ipairs(G.hand.cards) do
        local cc = c.config and c.config.card
        if cc and cc.suit and SMODS.Suits[cc.suit] and SMODS.Ranks[rank] then
          c:set_base(G.P_CARDS[SMODS.Suits[cc.suit].card_key .. "_" .. SMODS.Ranks[rank].card_key])
        end
        UC.msg(c, rank, G.C.CHIPS)
      end
      G.hand:change_size(-1)
      UC.msg(card, localize { type = "variable", key = "a_handsize", vars = { -1 } }, G.C.RED)
    end,
  },
})

-- =========================================================================
-- Familiar / Grim / Incantation
-- =========================================================================

local function add_random_cards(rank_pool, add_count)
  local suits = { "Spades", "Hearts", "Clubs", "Diamonds" }
  local enhs = { "m_bonus", "m_mult", "m_wild", "m_glass", "m_steel", "m_stone", "m_gold", "m_lucky" }
  for _ = 1, add_count do
    local r = pseudorandom_element(rank_pool, pseudoseed("ucsm_add_r"))
    local s = pseudorandom_element(suits, pseudoseed("ucsm_add_s"))
    local e = pseudorandom_element(enhs, pseudoseed("ucsm_add_e"))
    local front = G.P_CARDS[s .. "_" .. r]
    if front then
      G.playing_card = (G.playing_card and G.playing_card + 1) or 1
      local nc = Card(G.deck.T.x + G.deck.T.w / 2, G.deck.T.y, G.CARD_W, G.CARD_H,
        front, G.P_CENTERS[e], { playing_card = G.playing_card })
      table.insert(G.playing_cards, nc)
      nc:add_to_deck()
      G.deck.config.card_limit = G.deck.config.card_limit + 1
      G.deck:emplace(nc)
      UC.msg(nc, localize("k_added_ex"), G.C.GREEN)
    end
  end
end

local function def_destroy_add(key, rank_pool, add_count)
  local function other_mode()
    return {
      targets = function(card, mode)
        local hl = destroyable(UC.highlighted_in(mode, card, 1))
        if #hl > 0 then return hl end
        if UC.safe_targeting() then return {} end
        local pool = destroyable(UC.all_in(mode, card))
        if #pool == 0 then return {} end
        return { pseudorandom_element(pool, pseudoseed("ucsm_" .. key)) }
      end,
      can = function(card, mode, t) return #t > 0 end,
      run = function(card, mode, t)
        UC.destroy(t[1])
        add_random_cards(rank_pool, add_count)
      end,
    }
  end
  UC.define(key, {
    vanilla = "hand",
    max = 0,
    hand = {
      can = function(card, mode, t) return G.hand and #G.hand.cards > 0 end,
      run = function(card, mode, t)
        local hl = UC.highlighted_in("hand", card, 1)
        local victim = hl[1]
        if not victim then
          local pool = UC.all_in("hand", card)
          if #pool > 0 then victim = pseudorandom_element(pool, pseudoseed("ucsm_" .. key)) end
        end
        UC.destroy(victim)
        add_random_cards(rank_pool, add_count)
      end,
    },
    jokers = other_mode(),
    consumables = other_mode(),
  })
end

def_destroy_add("familiar",    { "Jack", "Queen", "King" }, 3)
def_destroy_add("grim",        { "Ace" }, 2)
def_destroy_add("incantation", { "2", "3", "4", "5", "6", "7", "8", "9", "10" }, 4)

-- Note: Wheel of Fortune is deliberately left alone. It already targets
-- jokers in the base game, and leaving it unowned keeps every mod that
-- changes its odds or its edition pool working.

-- =========================================================================
-- Joker seals
-- =========================================================================

local UC_orig_eval_card = eval_card
eval_card = function(card, context)
  local ret, post = UC_orig_eval_card(card, context)
  context = context or {}

  if card and card.seal and card.area and G.jokers and card.area == G.jokers then
    if card.seal == "Red" and context.joker_main and next(ret or {}) then
      ret.retriggers = ret.retriggers or {}
      ret.retriggers[#ret.retriggers + 1] = { message = localize("k_again_ex"), colour = G.C.RED }
    end

    if card.seal == "Gold" and context.joker_main and next(ret or {}) then
      UC.after(0.1, function()
        ease_dollars(3)
        UC.msg(card, localize("$") .. "3", G.C.MONEY)
      end)
    end

    if card.seal == "Blue" and context.end_of_round and not context.blueprint then
      UC.after(0.2, function()
        if UC.room_in(G.consumeables, 1) then
          local planet = create_card("Planet", G.consumeables, nil, nil, nil, nil, nil, "uc_blue_seal")
          planet:add_to_deck()
          G.consumeables:emplace(planet)
          planet:start_materialize()
          UC.msg(card, localize("k_planet_ex"), G.C.SECONDARY_SET.Planet)
        end
      end)
    end
  end

  return ret, post
end

local UC_orig_sell = Card.sell_card
function Card:sell_card(selling)
  if self.seal == "Purple" and self.ability and self.ability.set == "Joker" then
    UC.after(0.1, function()
      if UC.room_in(G.consumeables, 1) then
        local tarot = create_card("Tarot", G.consumeables, nil, nil, nil, nil, nil, "uc_purple_seal")
        tarot:add_to_deck()
        G.consumeables:emplace(tarot)
        tarot:start_materialize()
        UC.msg(self, localize("k_tarot_ex"), G.C.SECONDARY_SET.Tarot)
      end
    end)
  end
  return UC_orig_sell(self, selling)
end

-- =========================================================================
-- UI: the target toggle
-- =========================================================================

UC.ui = { label = "TARGET: HAND", colour = { 0.2, 0.46, 0.8, 1 } }

function UC.refresh_ui()
  local m = UC.get_mode()
  UC.ui.label = "TARGET: " .. (UC.MODE_LABEL[m] or "?")
  local src = UC.mode_colour(m)
  if src then
    for i = 1, 4 do UC.ui.colour[i] = src[i] end
  end
end

function UC.mode_button_visible(card)
  if UC.cfg().show_mode_button == false then return false end
  if not (card and card.area and G.consumeables and card.area == G.consumeables) then return false end
  local modes = UC.card_modes(card)
  if #modes < 2 then return false end
  local n = 0
  for _, m in ipairs(modes) do
    if UC.mode_available(m, card) then n = n + 1 end
  end
  return n >= 2
end

function UC.mode_button_node(card)
  UC.refresh_ui()
  local key = tostring(UC.cfg().toggle_key or "tab"):upper()
  local tip_lines = {}
  for _, m in ipairs(UC.card_modes(card)) do
    tip_lines[#tip_lines + 1] = UC.MODE_LABEL[m] .. ": " .. (UC.MODE_HINT[m] or "")
  end
  tip_lines[#tip_lines + 1] = "Click, or press " .. key .. ", to change."
  return {
    n = G.UIT.R, config = { align = "cm", padding = 0.05 },
    nodes = { {
      n = G.UIT.C,
      config = {
        ref_table = card, align = "cm", padding = 0.08, r = 0.08,
        colour = UC.ui.colour, button = "uc_cycle_mode", shadow = true,
        minw = 1.9, minh = 0.5, hover = true, one_press = true,
        tooltip = { title = "Target area", text = tip_lines },
      },
      nodes = { {
        n = G.UIT.T,
        config = {
          ref_table = UC.ui, ref_value = "label",
          scale = 0.28, colour = G.C.UI.TEXT_LIGHT, shadow = true,
        },
      } },
    } },
  }
end

G.FUNCS.uc_cycle_mode = function(e)
  local card = e and e.config and e.config.ref_table
  UC.cycle_mode(false, card)
  play_sound("cardSlide1", 1.2, 0.4)
  if card and card.juice_up then card:juice_up(0.1, 0.05) end
end

local function install_uidef()
  if UC._uidef_installed then return end
  if not (G and G.UIDEF and G.UIDEF.use_and_sell_buttons) then return end
  UC._uidef_installed = true
  local orig = G.UIDEF.use_and_sell_buttons
  G.UIDEF.use_and_sell_buttons = function(card)
    local t = orig(card)
    pcall(function()
      if type(t) == "table" and type(t.nodes) == "table" and UC.mode_button_visible(card) then
        table.insert(t.nodes, UC.mode_button_node(card))
      end
    end)
    return t
  end
end

install_uidef()

local UC_orig_game_update = Game.update
function Game:update(dt)
  if not UC._uidef_installed then install_uidef() end
  return UC_orig_game_update(self, dt)
end

-- Tint the Use button so the active target is obvious even without hovering.
local UC_orig_can_use = G.FUNCS.can_use_consumeable
G.FUNCS.can_use_consumeable = function(e)
  UC_orig_can_use(e)
  local card = e and e.config and e.config.ref_table
  if card and e.config.button and G.consumeables and card.area == G.consumeables then
    local modes = UC.card_modes(card)
    if #modes >= 2 then
      local c = UC.mode_colour(UC.effective_mode(card))
      if c then e.config.colour = c end
    end
  end
end

-- =========================================================================
-- Keybind
-- =========================================================================

local function keybind_allowed()
  if G.OVERLAY_MENU then return false end
  if G.CONTROLLER and G.CONTROLLER.text_input_hook then return false end
  if not (G.consumeables and #G.consumeables.cards > 0) then return false end
  local states = G.STATES or {}
  for _, s in pairs({
    states.SELECTING_HAND, states.SHOP, states.BLIND_SELECT,
    states.DRAW_TO_HAND, states.HAND_PLAYED, states.ROUND_EVAL,
    states.TAROT_PACK, states.SPECTRAL_PACK, states.STANDARD_PACK,
    states.BUFFOON_PACK, states.PLANET_PACK, states.SMODS_BOOSTER_OPENED,
  }) do
    if s and G.STATE == s then return true end
  end
  return false
end

local UC_orig_keypressed = love.keypressed
love.keypressed = function(key, ...)
  if key == (UC.cfg().toggle_key or "tab") and keybind_allowed() then
    local card = nil
    for _, c in ipairs(G.consumeables.cards) do
      if c.highlighted then card = c; break end
    end
    if not card then
      for _, c in ipairs(G.consumeables.cards) do
        if #UC.card_modes(c) >= 2 then card = c; break end
      end
    end
    UC.cycle_mode(true, card)
    return
  end
  if UC_orig_keypressed then return UC_orig_keypressed(key, ...) end
end

-- =========================================================================
-- Mod config tab
-- =========================================================================

if UC.mod then
  local KEYS = { "tab", "lshift", "lalt", "lctrl", "`", "q", "e", "r", "z", "x", "c", "v" }
  UC.mod.config_tab = function()
    local conf = UC.cfg()
    local key_index = 1
    for i, k in ipairs(KEYS) do
      if k == conf.toggle_key then key_index = i end
    end
    return {
      n = G.UIT.ROOT,
      config = { align = "cm", padding = 0.05, colour = G.C.CLEAR, minw = 6 },
      nodes = {
        create_option_cycle({
          label = "Toggle key", scale = 0.8, w = 4,
          options = KEYS, opt_callback = "uc_set_toggle_key",
          current_option = key_index,
        }),
        create_toggle({
          label = "Safe targeting", scale = 0.8,
          ref_table = conf, ref_value = "safe_targeting",
          info = {
            "Effects that destroy or overwrite one card",
            "only act on cards you clicked on while in",
            "Joker or Consumable mode.",
          },
        }),
        create_toggle({
          label = "Show target button", scale = 0.8,
          ref_table = conf, ref_value = "show_mode_button",
        }),
      },
    }
  end

  G.FUNCS.uc_set_toggle_key = function(e)
    local v = e and e.to_val
    if type(v) ~= "string" then v = KEYS[(e and e.to_key) or 1] end
    UC.cfg().toggle_key = v or "tab"
  end
end

UC.refresh_ui()
