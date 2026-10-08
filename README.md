# Universal Consumables

Lets tarot and spectral cards be used on your Jokers and your other
consumables, not just on the cards in your hand.

## Requirements
- Balatro 1.0.1
- [Steamodded](https://github.com/Steamodded/smods) 0.9.8+
- [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector)

## Install
Drop the `UniversalConsumables` folder into `%AppData%/Balatro/Mods/`

## Picking what a card targets

Every card has one **target area**: `HAND`, `JOKERS` or `CONSUMABLES`. It
starts on `HAND`, which is the behaviour of the unmodded game, and it only
changes when you change it.

Two ways to change it:

- **Click the `TARGET: …` button** on the card's hover panel, next to Use
  and Sell. It is colour-coded — blue for hand, red for jokers, purple for
  consumables — and the Use button takes the same colour, so the active
  area is visible without hovering.
- **Press Tab.** The key is configurable in the mod's config tab.

The toggle only offers areas that card can actually do something with, and
only while there is something there to point at, so a card that just
rewrites your hand never offers a Joker mode and Joker mode never appears
when you have no jokers.

Cards now also respect the vanilla selection limits: The Magician works on
one or two selected cards, and the Use button goes dark if you have three
selected, the same as the base game.

### Safety

The old version read *every* highlighted card on screen, so a joker left
selected from earlier could quietly hijack the next spectral you used.
That is gone — a card only ever looks at the area you are targeting.

On top of that, **Safe targeting** (on by default, in the mod's config tab)
means anything that destroys or overwrites one specific card in Joker or
Consumable mode only acts on cards you clicked. Immolate in Joker mode eats
the jokers you picked and nothing else; with safe targeting off it reverts
to taking 5 at random.

Eternal jokers are protected throughout, including from effects that would
overwrite rather than destroy them (Death, The Magician, Strength, …).

## What it does

Where the table says *vanilla*, the card behaves exactly as it does in the
unmodded game.

**Tarots**

| Card | Hand | Jokers |
|---|---|---|
| The Magician | vanilla | → Lucky Cat |
| The Lovers | vanilla | → Smeared Joker |
| The Chariot | vanilla | → Steel Joker |
| Justice | vanilla | → Glass Joker |
| The Devil | vanilla | → Golden Ticket |
| The Tower | vanilla | → Stone Joker |
| The Empress | vanilla | → Jolly Joker |
| The Hierophant | vanilla | → Zany Joker |
| The Star / Moon / Sun / World | vanilla | → the suit's Common joker, or its gemstone joker if Uncommon+ |
| Strength | vanilla | → a random joker one rarity higher |
| The Hanged Man | vanilla | destroys the selected jokers |
| Death | vanilla | the **left** selected joker becomes a copy of the **right** one |

The Hanged Man and Death also work in Consumable mode.

Wheel of Fortune is left exactly as the base game has it — it already
targets jokers, and leaving it alone keeps every mod that changes its odds
working.

**Spectrals**

| Card | Hand | Jokers | Consumables |
|---|---|---|---|
| Talisman | vanilla | Gold seal (pays $3 when the joker scores) | — |
| Trance | vanilla | Blue seal (a Planet at end of round) | — |
| Medium | vanilla | Purple seal (a Tarot when sold) | — |
| Deja Vu | vanilla | Red seal (retriggers the joker) | — |
| Aura | vanilla | an edition on the selected joker | — |
| Cryptid | vanilla | 2 copies of the selected joker | 1 copy of the selected consumable |
| Immolate | vanilla | destroys the selected jokers, +$20 | — |
| Hex | polychromes one card in hand, destroys the rest | vanilla | — |
| Ankh | copies one card in hand, destroys the rest | vanilla | — |
| Ectoplasm | Negative on a card in hand | vanilla | Negative on the selected consumable |
| Wraith | adds a loaded random card to your hand | vanilla | — |
| Familiar / Grim / Incantation | vanilla | destroys the selected joker, then adds its cards | destroys the selected consumable, then adds its cards |
| Sigil / Ouija | vanilla | — | — |

Sigil and Ouija used to light up their Use button in Joker mode and then do
nothing at all — they wrote fields the game never reads. They are hand-only
now.

## Playing with other spectral mods

- Universal Consumables loads late (priority 100) and keeps a copy of
  whatever was on each card before it took over. When you target the area a
  card natively works on, the original implementation runs. So if another
  mod reworks Hex, its Hex is what you get in Joker mode, and UC only
  supplies the extra Hand mode.
- Cards from other mods are left alone entirely and keep working as their
  author wrote them.
- Mod authors can opt in. `UC.choose(candidates, seed, mode)` returns the
  candidate the player highlighted when that mode is active and falls back
  to your own random roll otherwise, and `UC.declare(key, { "jokers" })`
  tells UC to show the target button on your card:

  ```lua
  can_use = function(self, card) return #G.jokers.cards > 0 end,
  use = function(self, card)
      local target = UC and UC.choose(G.jokers.cards, 'my_seed', 'jokers')
          or pseudorandom_element(G.jokers.cards, pseudoseed('my_seed'))
      -- ...
  end,
  ```

  Also available: `UC.mode()`, `UC.is_mode(m)`, `UC.highlighted_in(mode,
  exclude, max)`, `UC.all_in(mode, exclude)`, `UC.protected(card)`,
  `UC.room_in(area, n)`. `UC.API_VERSION` is `1`.

  [Spectral Expansion](https://github.com/hydrophobis/TheVoid) uses this,
  so its Anchor, Paragon, Mourning, Effigy, Exhume, Conduit and Transmute
  hit the card you picked instead of a random one.
