# ASMR Platformer: roadmap

What we are going to build, roughly in order. `HANDOFF.md` describes what exists; this file is
what does not exist yet. Every idea is tagged with where it came from: **(you)** for your ideas
and decisions, **(suggested)** for mine.

Last updated: 2026-09-18. The short version, with what is built and waiting for a test, is the
Status section of `README.md`.

## Where the levels stand

| Level | Name | Background today | Plan |
|---|---|---|---|
| 1 | City Shore | a pastel beach city round a bay, open sea toward the sun (second version, untested) | ending built and tested: the dive works (section 1) |
| 2 | Sky Pools | pool terraces down a meander over a cloud sea (built, fourth pass untested) | ends on the slide into the final pool; needs a Studio test (section 3) |
| 3 | The Sunken City | a drowned city either side of a boulevard, with something patrolling under it (built, ninth pass untested) | ends on the harbour drain; needs a Studio test (section 4) |
| 4 | Flooded Halls | built, ends on the flume into the shaft | the slide ending is tested and works |

---

## 1. City Shore finale -- BUILT 2026-09-15, TESTED 2026-09-17: works

**Built as you asked (you):** no slide ride. At the top of the spiral the last chunk runs onto a
platform with a diving board, you jump off into the sea about 830 studs below, and hitting the
water completes the level. Since 2026-09-16 the finish is a landing circle on the water, 600 studs
across, because divers were being sent back to the route **(you)**.

What went in: the deck, the springboard on its clamp and roller, rails, a corner flag, the dive
detection, a splash with spray and a spreading ring, and a fade to black under the completion
banner as the diver sinks, before the lobby takes them back. The horizon turned out to need no change at all: the
backdrop stopped following the player some rounds ago, so the sea was already really there.
HANDOFF.md carries the details.

**Tested (you):** the diving board works. Still open to taste: whether the drop wants to be higher
or the board longer.

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

## 3. Level 2, Sky Pools -- BUILT 2026-09-18, not tested yet **("peaceful pools in the sky" is yours)**

Calm, bright, silent apart from water: the one level with no scares at all. The picture is
`blender/skypools_plan.png` (run `python blender/plan_skypools.py`). It is drawn by the same Python
that `blender/check_skypools.py` tests, so it shows the level as built, not a proposal.

**The route: a meander, going down (yours).** The level's 44 chunks (its `T2_BubbleWrapWindow`
template) follow a path that sweeps from side to side on a long sine and goes down the whole way:
from 24 at the start to about -116 at the end on a medium run, taking steps 1.6 times the climb's
size. It was a ring, and from inside it the level read as a lap -- most of the view was route you
had already run, and on a short run the next terrace round stood a hundred studs away with its
columns up past your deck. The meander never crosses itself and never comes back on itself, and it
bends no harder than the ring did at any one chunk, so what is ahead of you is somewhere you have
not been.

**Pool terraces beside the checkpoints (you).** There are five: at the start, and at the
checkpoints nearest a fifth, two fifths, three fifths and four fifths of the way. Each steps off its
checkpoint flush with it, taking ALTERNATING SIDES of the route so no two of them crowd each other.

A terrace is not a square: a narrow walk off the checkpoint, shoulders where it flares, a wide
middle with a sun deck either side of the pool, and a rounded prow past the pool that the water goes
over. The pool is nine deep and filled with terrain water, so you SWIM in it; four steps at the
inner end walk you in and back out, and there is a ladder at the deep end, a band of darker tile at
the waterline and two lights set into the walls under the surface. On the deck: loungers with slats
and a back on its hinge, a ribbed parasol, a towel somebody left, and on different terraces a
pergola, stone planters, a changing cabana, a lifeguard's chair or a diving board out over the water
**(you)**. Each terrace stands on nine COLUMNS to the sea -- under the pool's four corners, under
both sun decks and under the prow -- and each pool spills off the prow in a waterfall that also
reaches the sea **(you)**. Nothing floats.

This differs from the layout: the terraces sit BESIDE the route rather than being chunks in it.
That needed no new chunk, so ChunkBuilder is unchanged and the chunk folders need no clearing.

**The fountain tower (suggested)** stands beside the slide's mouth at the end of the route, a
hundred and fifty studs off it -- beside, not ahead, because a slide round it is an arc and an arc
leaves its mouth across its radius. It runs from the sea, through
the final pool and the clouds, to a basin 90 studs above the start with a jet in it. The basin
overflows all the way round, and that curtain of water is what fills the final pool.

**The cloud sea** is one layer of wide, low ellipsoids, 2400 studs across, with its top 14 studs
above the kill plane. A fall sinks into cloud just as it is caught. The clouds are flat layers,
never balls, because City Shore's round clouds looked like eggs.

**The ending (you).** The route runs onto a finale deck with a rail along its inner side and an
arch over the slide's mouth. You hold E to ride. The slide goes 0.85 of a turn round the tower,
down through the clouds, and into the final pool 220 studs under the cloud top. On the longest
runs the pool sits a little higher, to stay well above the -500 line where Roblox deletes a
falling character. It is hung from the
tower on rods. The ride moves at 70 studs a second and takes 8 to 15 seconds depending on how the
run came out.

You ride it in a SLED you sit in, rather than being slid along standing up. The server sits you in
it and keeps the clock; your own client draws every frame of the ride from the shared path in
`ReplicatedStorage/Shared/SkyPath.lua`, which is why it is smooth. Nothing is built within sixteen
studs of the trough ahead of the mouth.
The splash ends the level, and the final pool drains over its rim into the sea, 520 studs further
down **(you)**.

**Around it:** six smaller pool terraces out in the sky on their own columns, each with its
waterfall, each placed at least 300 studs from every chunk of the route.

**Light (suggested):** late morning (clock 10.8), a clear blue sky fading to pale blue at the
horizon, and very little haze. It is LightingService's `skyPools` palette and stays within a step
of the default everywhere else.

**Materials (you):** cloud, foam, bubble wrap and soap lead, with the calm rest of the kit around
them: jello soda, lamb's ear, honey, slime, Needoh and the keypads. None of the fierce ones: no
lava, no burning charcoal, no salt or clay tearing under you. None of the chunks that climb inside
themselves either, since this route only goes down.

**The finale banner** reads "Sky Pools / Down through the clouds", in the slide's lavender.

**Second pass, the same day (suggested).** Every waterfall is heard now, and the pools answer: a
splash when you step in and spreading ripples as you wade. Ducks and swim rings drift in the pools.
Under the second terrace there is a pump room behind a STAFF ONLY hatch, where the overflow pipe
runs to the sea and the log on the wall points at the Sunken City.

**Third pass, the same day: more to find (the walkable places are yours).**
- **A changing cabana** stands on the fourth terrace, with its door facing the pool. The shower is
  running with nobody in it, a robe hangs on a hook, and one locker is open, with a towel and a
  lost-property note: "one flip-flop (left), ask at Pump Room 2".
- **A lifeguard's chair** stands on the diving-board terrace, facing the pool. You can climb it,
  and a lifebuoy hangs on a post beside it.
- **Hot air balloons** drift slowly round the level, far out and high up, and their burners flare
  now and then. They float, because that is what balloons do.
- **Two flocks of gulls** wheel round the fountain tower.
- There are still no scares in this level.

**What to test (open):**

- Does the ring look right from the start, with the tower across it and the clouds below?
- Are the terraces flush with their checkpoints, and are the pools shallow enough to walk through?
- Does the slide carry you all the way to the pool, and is the ride's speed right?
- Does a fall off the route still reset you in the clouds?
- Is the light right, or is it too bright over the white clouds?
- Does it run smoothly? The cloud sea is several hundred parts.

## 4. Level 3, The Sunken City -- FIRST VERSION BUILT 2026-09-18, not tested yet **(suggested; the sunken city with sea monsters is yours)**

The picture is `blender/sunkencity_plan.png` (run `python blender/plan_sunkencity.py`), drawn by the
same Python that `blender/check_sunkencity.py` tests.

**The route (suggested).** A flat ring just above the sea, 0.8 of a turn, rising and dipping 3.5
studs on a slow swell so it comes down near the water and lifts away again. About 100, 200 or 300
studs across for a short, medium or long run. A fall goes into the water before the kill plane
catches it.

**The drowned city (you).**
- **The plaza and the clock tower** sit in the middle. The tower is stopped at twelve past four,
  and now and then its minute hands try to move on.
- **Rings of lots** stand between ring streets and eight avenues.
- **Flooded flats next to the route**, roofless, with their rooms a few studs under the surface and
  the beds, sofas and fridges still in them. These are the ones you look down into.
- **Taller blocks and offices break the surface** further out, never within 40 studs of the route.
- **A multi-storey car park** stands with its top deck of cars just under the water.
- **The boulevard** runs under the route, with road signs on gantries a few studs down.
- **A harbour** has quays, a crane standing out of the water, a sunken boat with its bow up, and
  buoys.

**The thing (you): something enormous swims the boulevard under the route and never chases you.**
It circles against the direction of the run and swings out round the harbour. When it comes near,
the sound goes first, the water darkens after, and a low rumble comes up. It is drawn on each
player's screen from shared numbers, so everyone sees it in the same place.

**The aquarium (you),** off one checkpoint:
- A round tower stands in the water, with a door, and a stair spirals down inside it.
- A glass tunnel on pillars runs through the water, with kelp and fish.
- A gallery at the end has a window onto the deep and a sign asking you not to tap on the glass.
- **Tap three times as a Hardcore player and, once a run, something taps back (suggested).** In
  Chill nothing answers.

**The ending (you): pulled down a drain in the harbour floor into the dark.** The route runs out
onto a pier. Past its end is a whirlpool. Step off and it pulls you round and down the current,
into the drain and a black shaft, where the run ends and the banner comes up.

**Materials (you):** slime, jello soda, ice and oobleck, filled out with salt, sea foam, the
Needohs, soap and bubble wrap **(suggested)**, because jello soda is the only pace chunk among the
four.

**Light (suggested):** a grey-green afternoon with real haze, a step under the default.

**Sky Pools points here (suggested).** The log in Sky Pools' pump room ends "The sea runs to the
drain", the one line that ties the two levels together, ready for story mode.

**The thing now resets you in Hardcore (you, section 6).** Every 80 seconds or so, while it is
under the route, it surfaces:
1. For five seconds first, the sound goes, bubbles rise and a dark patch spreads on the water over
   the spot.
2. Then its back heaves up just under the surface and its fins cut through it.
3. A surge of spray goes over the route. Any Hardcore player standing within 26 studs of the spot
   is taken back to the start, with a deep thud and a darker moment.

In Chill it only watches. It never surfaces in the harbour or under the road signs, and nobody
indoors (in the aquarium or the flat) can be taken. Every player sees it at the same moment and
place, because the server and the clients work it out from one shared schedule.

**The last dry flat, and the face in the mirror (you, section 6).** Off another checkpoint:
- A plank gangway leads to a block of flats whose top floor is still above the water. A lamp is
  still on inside, so the doorway glows from the route.
- Inside is a sofa facing the window over the drowned city, a kitchen counter and a calendar ("The
  water will not come up this far. Management").
- A stairwell spirals down into the flooded floor below, where the stairs end in the water at a
  doorway blocked by a fallen wardrobe.
- The bathroom has a flickering cold light, a bathtub full of dark water, and **the mirror**.
- Stand before it in Hardcore and, **once a server at most**, the light stutters and a pale face is
  in the mirror for half a second, over a low drone. Then the light goes out, and when it comes
  back the mirror is empty. **Never in Chill.**

**A lantern at the end of the pier** is the one warm light in the harbour. You see it from along
the route before you see the pier.

**Ninth pass (2026-09-25), from you:** the serpent mesh for the thing under the route, and the code
made to run better with its bugs fixed. Built as described in HANDOFF.

**Eighth pass (2026-09-25), from you:** better and higher quality all round, Blender models for
the animals, new chunks with meshes of their own, and the crash at build. Built as described in
HANDOFF **(suggested: the Ferris wheel, the kelp canopy, and the jellyfish as the material the new
chunks are made of)**.

**Seventh pass (2026-09-24), from play (you):** roofs higher than the water with no flicker, bigger
cars, a less barren sea and city, the water swimmable past FLOODED. NO ACCESS., a whirlpool that
moves like water, the animals visible, the buildings' details under the water, more life and decor,
and a countdown that ticks evenly. Built as described in HANDOFF **(suggested: dolphins, gulls,
turtles surfacing, the tram and the street furniture, and what is in the flooded flat)**.

**Sixth pass (2026-09-24), from play (you):** tap the glass enough and it breaks, the aquarium
floods, and you are washed back to your checkpoint in Chill and to the start in Hardcore. Built with
warning steps first (a crack at three taps, a spreading, weeping crack at five, the break at seven)
and the glass whole again afterwards **(suggested: the thresholds and the timings)**. Also from play:
kelp that is detailed and moves, animals you can actually see, the stair out of the tunnel's way, a
better aquarium.

**Fifth pass (2026-09-23), from play (you):** buildings that are not hollow, better lanterns,
skyscrapers, clock tower and containers, better water, animals that swim like characters, rain,
eerie sounds, and something scary far out in the water. Built as: every block roofed; a clock tower
whose bell tolls on its own; rays, turtles, jellyfish, eels and groupers in the street; showers on a
shared schedule; a handful of windows lit on and off; strange sounds from out in the city; and a
back like a range of hills that comes up on the horizon every few minutes and goes down again
**(suggested: the form each of those takes)**.

**What to test (open):**

- Does the city read from the route, with the flooded rooms below you and the towers in the haze?
- Is the water too clear or too murky? Does the depth colouring work?
- The thing: is it big enough and slow enough, and does its approach feel right?
- The surfacing: is five seconds of warning enough, and is the surge fair?
- Is the face in the mirror frightening, and too much or too little? It is rare, so testing it
  needs a Hardcore run and possibly a few tries.
- Is the flat's stairwell readable as "don't go down there"?
- Does the stair work, and does the tunnel feel underwater?
- Is the whirlpool ride right?
- Does it run smoothly? The city is a couple of thousand parts.

## 5. The Backrooms secret level **(you)**

- **Fall enough times in one run (you),** say 7 **(suggested)**, and instead of respawning you clip
  through the floor into the Backrooms: yellow rooms, humming lights, damp carpet.
- Never announced anywhere, so it has to be found **(suggested)**.
- The game already counts deaths, so the trigger is cheap.

## 6. Rules for scares, monsters and secrets

- **An eerie atmosphere, and a monster that resets you to spawn (you).** The reset only happens in
  Hardcore; in Chill a monster sends you to your checkpoint or only watches **(suggested)**. Every
  threat is telegraphed, with sound cutting out or lights flickering first **(suggested)**.
  **Built in the Sunken City (2026-09-18):** the thing's surfacing (section 4).
- **A fake scary face in a mirror, with eerie music (you).** Rare, once per server or less, and
  never in Chill **(suggested)**. A scare that happens every time stops being scary, and
  players who came to relax shouldn't get one. **Built in the Sunken City's dry flat
  (2026-09-18).** The "music" is a low drone, because the project has no uploaded audio.
- **Built so far:** the Sunken City's aquarium and dry flat; Sky Pools' pump room and cabana.
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
