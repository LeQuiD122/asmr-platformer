# ASMR Platformer: roadmap

What we are going to build, roughly in order. `HANDOFF.md` describes what exists; this file is
what does not exist yet. Every idea is tagged with where it came from: **(you)** for your ideas
and decisions, **(suggested)** for mine.

Last updated: 2026-09-15.

## Where the levels stand

| Level | Name | Background today | Plan |
|---|---|---|---|
| 1 | City Shore | skyscrapers, beach and waterpark on the horizon | ending built (section 1), needs Studio testing |
| 2 | Open Sky | nothing | becomes Sky Pools (section 3) |
| 3 | Far Water | nothing | becomes The Sunken City (section 4) |
| 4 | Flooded Halls | built, ends on the flume into the shaft | finish Studio testing |

---

## 1. City Shore finale -- BUILT 2026-09-15, untested in Studio

**Built as you asked (you):** no slide ride. At the top of the spiral the last chunk runs onto a
platform with a diving board, you jump off into the sea about 830 studs below, and hitting the
water completes the level.

What went in: the deck, the springboard on its clamp and roller, rails, a corner flag, the dive
detection, a splash with spray and a spreading ring, and a fade to black under the completion
banner as the diver sinks, before the lobby takes them back. The horizon turned out to need no change at all: the
backdrop stopped following the player some rounds ago, so the sea was already really there.
HANDOFF.md carries the details.

**Left to check in Studio:** whether the fall reads well from the board, whether the splash lands
where it should, and whether the drop wants to be higher or the board longer.

## 2. Story mode

**Idea (you):** a mode that plays the levels in order, one after another.

- **Finishing a level takes you into the next one instead of back to the lobby (you).** The first
  link: **City Shore teleports you into the Flooded Halls.** You dive into the ocean and come up
  in the Flooded Halls.
- **Order after that** is not decided yet. The Flooded Halls ends by dropping into a shaft, which
  could lead naturally into whatever comes next **(suggested)**.

To work out when we design it:

- a Story pad in the lobby
- how the timer, best times and leaderboard work across several levels
- what a death does: restart the current level, not the whole story **(suggested)**
- whether story progress is saved between sessions
- whether Chill and Hardcore both apply

## 3. Level 2, Open Sky, becomes Sky Pools **(suggested; "peaceful pools in the sky" is yours)**

- Tiled pool basins floating among the clouds, joined by the chunk route. Waterfalls spill off
  their edges into nothing. Calm, bright, silent apart from water.
- **Materials:** cloud, foam, bubble wrap, soap.
- **Walkable places:** some checkpoints are real pool decks you can step off onto, with a sun
  lounger, a lost towel, or a diving board over a long drop.
- **Ending:** a slide down through the cloud layer into the pool below, and the last pool drains
  into the sea.
- **Tone:** the one level with no scares at all.

## 4. Level 3, Far Water, becomes The Sunken City **(suggested; the sunken city with sea monsters is yours)**

- The route runs above a drowned city: streets, a clock tower, a car park, flooded apartment
  blocks you can look down into. Something enormous moves slowly between the buildings.
- **The sea monster never chases you.** It circles, and when it passes under the route the water
  darkens and the sound drops. In Hardcore, falling while it is under you sends you back to spawn.
  In Chill it only watches.
- **Materials:** slime, jello soda, ice, oobleck.
- **Walkable place:** an aquarium tunnel through one sunken building.
- **Ending:** pulled down a drain in the harbour floor into the dark.

## 5. The Backrooms secret level **(you)**

- **Fall enough times in one run (you),** say 7 **(suggested)**, and instead of respawning you clip
  through the floor into the Backrooms: yellow rooms, humming lights, damp carpet.
- Never announced anywhere, so it has to be found **(suggested)**.
- The game already counts deaths, so the trigger is cheap.

## 6. Rules for scares, monsters and secrets

- **An eerie atmosphere, and a monster that resets you to spawn (you).** The reset only happens in
  Hardcore; in Chill a monster sends you to your checkpoint or only watches **(suggested)**. Every
  threat is telegraphed, with sound cutting out or lights flickering first **(suggested)**.
- **A fake scary face in a mirror, with eerie music (you).** Rare, once per server or less, and
  never in Chill **(suggested)**. A scare that happens every time stops being scary, and
  players who came to relax shouldn't get one.
- **Walkable, accessible places with custom easter eggs (you).** These go on some checkpoints, as
  small places you can step off the route to explore **(suggested)**.

## 7. Everything else, for later (all of it is wanted in the game eventually)

**Every idea from your brainstorm (you),** grouped into worlds so a long list becomes a map
**(suggested)**.

| World | Places |
|---|---|
| Leisure | pools, aqua park, kids' playground (its own big level), peaceful pools in the sky |
| Everyday | different floors of an office building, parking lot, houses, parks, museum, luxury mansions, highways, sport stadiums |
| Nature | endless grass biomes with occasional farmland, flower valley, mountains, volcanoes, underground mines |
| Deep | underwater sunken cities with sea monsters, aquarium, underwater caves |
| Beyond | spaceship in outer space, other planets, open sky, abstract shapes |
| Strange | mazes, tiny world of bugs, medieval villages, rollercoasters, industrial facilities |
| Hidden | the Backrooms |

**Suggested priority after sections 1 to 5:**

1. **Kids' playground.** Foam, lego and buttons suit it perfectly; a strong level 5.
2. **Office floors, parking lot, museum, aquarium.** Classic liminal spaces, good as side areas or
   secret routes.
3. **Tiny world of bugs.** The game's materials seen as giant terrain.
4. **The rest, as worlds.**

Space, other planets and rollercoasters break the grounded liminal tone. They fit late, or a
rollercoaster could be a finale ride rather than a whole level.
