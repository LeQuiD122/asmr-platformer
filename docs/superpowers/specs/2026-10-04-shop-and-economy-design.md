# The shop and the economy: design

Approved in conversation on 2026-10-03 and 2026-10-04. Built in the twenty-second pass (pieces 1 and 2).

## Goal

The game is meant to make money. Add a shop players want to use, on every device, that cannot be
duplicated or cheated, without cluttering the screen during play.

## Decisions (the user's)

- Shop first, then the first five minutes, then the cosmetics' effects, then a full device pass.
- Currency: **tokens**, earned by finishing a level; Robux buys token packs, passes and private servers.
- Earning: **finishing a level only** (hard to farm).
- Save layer: **ProfileStore** (session-locked).
- Catalogue at launch: footprints and trails, squish sound packs, gamepasses, auras and emotes.
- Look: **option A, tactile chunky** (bold like the reference reel, soft and rounded, buttons that press and
  squish like the materials).
- Requirements added on 2026-10-03: every button works on PC, phone, tablet and controller; a player
  understands the first five minutes (a welcome); nothing is dupable; the experience is great.

## The five pieces

1. **Saved profile and economy** (EconomyService, ShopCatalog). Built.
2. **The shop** (ShopService, the lobby kiosk, the pause menu entry). Built.
3. **The first five minutes**: a welcome on first join, a guided first run (City Shore, Chill, Short),
   quiet one-time hints per material that never cover the level, ending at the shop. Built (twenty-third
   pass, OnboardingService).
4. **The cosmetics' effects**: footprints, sound packs, emotes, the Hardcore second chance (marked "soon"
   in the shop until built). Trails and auras are built; footprints and step sounds built in the
   twenty-fifth pass (StepService); emotes and the second chance in the twenty-sixth (EmoteService,
   Bootstrap). The second chance never counts for the leaderboard or a best.
5. **Every device**: the same rules applied to the existing screens (journal, pause menu, banner, voting
   card), held by a checker. Built (twenty-fourth pass, `check_devices.py`).

## Piece 1: saved profile and economy

- One ProfileStore profile per player: tokens, owned items, what is worn, the welcome flag, tokens ever
  earned, recent Robux PurchaseIds. Studio uses its own store (`PlayerData_Studio`); live uses
  `PlayerData`. Without ProfileStore the game runs unsaved and refuses Robux outside Studio.
- Earning: Short 10, Medium 20, Long 30; Hardcore x1.5; a new hardcore best +10; the 2x pass doubles.
  Paid only for a run the server saw start, at least 45 / 90 / 135 seconds long.
- The client asks with an action (`buy`, `equip`, `unequip`) and an item id, nothing else. Prices come
  from ShopCatalog. One request at a time per player, 0.25 s apart.
- Robux: token packs granted once per PurchaseId and confirmed only after a save containing it; passes
  checked on join and when bought.
- Analytics: every token source and sink logged (AnalyticsService economy events).

## Piece 2: the shop

- Opens from a striped kiosk left of the lobby spawn (Roblox's own prompt) and from a Shop button in the
  pause menu. Nothing else on screen.
- Header (Shop, your tokens with a + for packs, close), tabs (Featured, Steps, Trails, Sounds, Auras,
  Emotes, Passes, Tokens), a grid of tiles with a drawn icon, name, line and a squishy price button
  (amber tokens, green Robux, grey soon, teal owned: Put on / Take off).
- Tapping a tile tries a trail or aura on your own character. Buying confirms in one tap, pops like
  bubble wrap, and wears the item at once. Short of tokens: how many more, and a way to token packs.
- Every device: laid out from the safe area's size; 4 / 3 / 2 columns by width; tabs scroll sideways;
  nothing pressable under 44 px; controller selection, bumpers for tabs, B to close; Escape closes;
  movement paused while open; the cursor freed.
- Prices: footprints 60 to 150, trails 100 to 250, sounds 150 to 300, auras 200 to 400, emotes 80 to
  150 tokens; 2x tokens 199 R$, VIP 299 R$ (chat tag and the gold sparkle), second chance 25 R$; packs
  100 / 300 / 800 / 2000 tokens for 49 / 129 / 299 / 649 R$.

## Testing

`blender/check_shop.py` holds all of the above; `blender/mutations/pass22.py` plants 23 bugs (the classic
dupes, the device rules, the wiring) and every one is caught. In Studio: the kiosk, the pause menu entry,
buying with the Studio gift of 1000 tokens, wearing, the try-on, phone and tablet emulation, a controller.
