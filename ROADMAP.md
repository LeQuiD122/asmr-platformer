# ASMR Platformer: roadmap

What we are going to build, roughly in order. `HANDOFF.md` describes what exists; this file is
what does not exist yet. Every idea is tagged with where it came from: **(you)** for your ideas
and decisions, **(suggested)** for mine.

Last updated: 2026-10-20. Everything built up to and including the ninety-second pass has been played in Studio
**(you)**; the ninety-third to the hundred-and-fourth wait for a test. Section 9 is your list of 2026-10-20 and where
each item stands.
The short version is the Status section of `README.md`. What comes next, in order, is section 8.

## Where the levels stand

| Level | Name | Background today | Plan |
|---|---|---|---|
| 1 | City Shore | a pastel beach city round a bay, open sea toward the sun, with the Siren Tower in the spiral | built and tested: the high dive as a scored scene (Maren, the gulls, your thoughts on the way down, the light under the water); its shots reworked in the ninety-third pass, waiting for a test |
| 2 | Sky Pools | pool terraces down a meander over a drifting cloud sea, round a fountain tower | built and tested: the slide round the tower and the skim across the final pool, a scored scene; the landing shot reworked in the ninety-third pass |
| 3 | The Sunken City | a drowned city either side of a boulevard, with something patrolling under it | built and tested: the swirling drain and Outfall 3 to the pumping station, a scored scene; two drain shots reworked in the ninety-third pass |
| 4 | Flooded Halls | the Corporation Baths: the flume ends in the mouth in the dark and then the Gate Chamber, where the story ends | built and tested; the flume's end, the mouth's beats and the chamber's shots reworked in the ninety-third pass |
| 5 | Hill House | the key holder's house on the hill at eight in the morning (`LORE.md`) | chosen as the next level **(you, 2026-10-17)**, next now the lobby is built (section 8) |

---

## 1. City Shore finale: BUILT 2026-09-15, TESTED 2026-09-17, works

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

## 2. Story mode: BUILT 2026-10-13 (sixtieth pass), TESTED by 2026-10-17

**Decided (you, 2026-10-13):** my suggestions for the four questions below: a Story pad in the lobby; one clock
across the levels with a leaderboard of its own; a death restarts only the level you are on; progress saved between
sessions, in Chill and in Hardcore. Built as described in HANDOFF (**Story mode**); the rest of this section is the
history of the idea.

**Idea (you):** a mode that plays the levels in order, one after another.

- **Finishing a level takes you into the next one instead of back to the lobby (you).** The first
  link: **City Shore teleports you into the Flooded Halls.** You dive into the ocean and come up
  in the Flooded Halls.
- **Order after that** is not decided yet. The Flooded Halls ends by dropping into a shaft, which
  could lead naturally into whatever comes next **(suggested)**.
- **The levels are numbered by the clock (you, fifteenth pass):** Level 1 City Shore at 9:14 in the
  morning, Level 2 the Sky Pools at three, Level 3 the Sunken City at eight minutes to midnight, Level
  4 the Flooded Halls (the Corporation Baths under the pumping station) at four minutes to midnight,
  ending at the gates. That order replaces the first link above (City Shore straight into the halls).
- **Level 5, Hill House, 8:00 in the morning (suggested, LORE.md):** before any of it. The key holder's
  house on the hill with the big clock, the key on its green ribbon by the door, and why you did not
  go in. The true ending would be clocking in. The lost property in the baths already points at it.
- **The journal, saved (suggested; built in the thirty-first pass):** what was taken is kept with the
  player's profile between sessions. The words are saved as the story wrote them rather than rebuilt from the
  tables, because those live with each level and a level is not built while you are in the lobby. The
  keepsakes are on a shelf in the squish room since the thirty-second pass, each player's own collection.
  Shown to other players since the forty-eighth pass, as a Keepsakes count in Roblox's player list.
- **Decided (you, 2026-10-12):** levels open in order. Built in the fifty-first pass: a level is open when anyone
  in the server has finished the one before it (or any later one, since the fifty-seventh pass); locked pads are
  boarded up in the lobby.

To work out when we design it:

- a Story pad in the lobby
- how the timer, best times and leaderboard work across several levels
- what a death does: restart the current level, not the whole story **(suggested)**
- whether story progress is saved between sessions
- whether Chill and Hardcore both apply

## 3. Level 2, Sky Pools: BUILT 2026-09-18, TESTED by 2026-10-17 **("peaceful pools in the sky" is yours)**

Calm, bright, silent apart from water: the one level with no scares at all. The picture is
`blender/skypools_plan.png` (run `python blender/plan_skypools.py`). It is drawn by the same Python
that `blender/check_skypools.py` tests, so it shows the level as built, not a proposal.

**The route: a meander, going down (yours).** The level's 44 chunks (its `T2_BubbleWrapWindow`
template) follow a path that sweeps from side to side on a long sine and goes down the whole way:
from 24 at the start to about -116 at the end on a medium run, taking steps 1.6 times the climb's
size. It was a ring, and from inside it the level read as a lap: most of the view was route you
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
**(you)**. Each terrace stands on nine COLUMNS to the sea (under the pool's four corners, under
both sun decks and under the prow), and each pool spills off the prow in a waterfall that also
reaches the sea **(you)**. Nothing floats.

This differs from the layout: the terraces sit BESIDE the route rather than being chunks in it.
That needed no new chunk, so ChunkBuilder is unchanged and the chunk folders need no clearing.

**The fountain tower (suggested)** stands beside the slide's mouth at the end of the route, a
hundred and fifty studs off it: beside, not ahead, because a slide round it is an arc and an arc
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

## 4. Level 3, The Sunken City: BUILT 2026-09-18, TESTED by 2026-10-17 **(suggested; the sunken city with sea monsters is yours)**

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

**Ninety-second pass (2026-10-17), from your third test (you):** the mouth seen again in the dark, the fall and the
dive acted and shot toward where they go, and a paste check that catches code pasted into the wrong script, as in
HANDOFF **(suggested how)**. Next: the Studio test of pass 92 (and the re-paste of BackdropService, BackRoomsService
and SearchlightClient). Still open, yours to choose: Hill House, showing what you have earned in the shop, a group
reward, a weekly leaderboard.

**Eighty-sixth to ninety-first passes (2026-10-16), from your second test (you):** the lockers and their scenes, the
fall into the mouth, eleven chunk sounds, the people's voices, the back rooms (sunk things, E. Marsh, the way out),
the VIP tag, embers and countdown, the keepsakes' count and the story's typeface, as in HANDOFF **(suggested how)**.
Next: the Studio test of passes 86 to 91. Still open, yours to choose: Hill House, showing what you have earned in
the shop, a group reward, a weekly leaderboard.

**Seventy-eighth to eighty-fifth passes (2026-10-16), from your first test (you):** the sounds, the shop and its
things, the dive, the pry bar's scenes, the Sky Pools slide, the whirlpool, the flume and the mouth, and the people's
gestures, as in HANDOFF **(suggested how)**. Next: the Studio test of passes 78 to 85. Still open, yours to choose:
Hill House, showing what you have earned in the shop, a group reward, a weekly leaderboard.

**Seventy-seventh pass (2026-10-15), codes (you chose them):** a post box in the lobby and one list of codes, as in
HANDOFF **(suggested how)**. Next: the Studio test of passes 18 to 77. Still open, yours to choose: Hill House,
showing what you have earned in the shop, a group reward, a weekly leaderboard, a Studio test checklist.

**Seventy-sixth pass (2026-10-15), a review (you chose it):** passes 18 to 49 read; three fixes, as in HANDOFF.

**Seventy-fifth pass (2026-10-15), a review (you chose it):** passes 50 to 74 read end to end; two fixes, as in
HANDOFF.

**Seventy-fourth pass (2026-10-15), the materials as a collection (you chose it):** found on the levels, in the
journal and on a lobby board, as described in HANDOFF **(suggested how)**.

**Seventy-third pass (2026-10-14), a starter pack (you chose it):** a 99 Robux pass with 500 tokens and the sea glass
trail, as described in HANDOFF **(suggested how)**.

**Seventy-second pass (2026-10-14), daily challenges (you chose them):** three a day on a lobby board, as described
in HANDOFF **(suggested how)**.

**Seventy-first pass (2026-10-14), a friends bonus (you chose it):** a fifth more for a run with a Roblox friend in
it, as described in HANDOFF **(suggested how)**.

**Seventieth pass (2026-10-14), hidden token caches (you chose them):** one a level, as described in HANDOFF
**(suggested how)**.

**Sixty-ninth pass (2026-10-14), the daily reward (you chose it):** a chest in the lobby, as described in HANDOFF
**(suggested how)**. Next: the Studio test of passes 18 to 69. Still open, yours to choose: Hill House, hidden token
caches.

**Sixty-eighth pass (2026-10-14), the story reward (you chose it):** a bonus and the green ribbon for finishing
the story, as described in HANDOFF **(suggested how)**. Next: the Studio test of passes 18 to 68. Still open, yours to
choose: Hill House, a daily reward.

**Sixty-seventh pass (2026-10-14), a bit more (you):** the back rooms kept out of the lobby's vote, as described
in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 67. Open, and yours to choose when you want more:
Hill House (the fifth level, LORE.md), a reward for finishing the story, a daily reward.

**Sixty-sixth pass (2026-10-14), a bit more (you):** the back rooms are the sixth secret, as described in
HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 66.

**Sixty-fifth pass (2026-10-14), a bit more (you):** the lobby's back corridor leads to the back rooms once
found, as described in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 65.

**Sixty-fourth pass (2026-10-14), a bit more (you):** the back rooms, your secret level from section 5, as
described in HANDOFF **(suggested how)**. Next: the Studio test of passes 18 to 64.

**Sixty-third pass (2026-10-14), a bit more (you):** Roblox badges, switched off until made, as described in
HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 63; making the badges is yours when you want them.

**Sixty-first and sixty-second passes (2026-10-14), a bit more (you):** the move between a story's levels, and the
Self-test sees the story, as described in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 62.

**Fifty-eighth to sixtieth passes (2026-10-13), story mode and an admin's /levels (you):** as described in
HANDOFF; how is mine **(suggested)**. Plus one run at a time in the lobby, a bug found on the way. Next: the Studio
test of passes 18 to 60.

**Fifty-seventh pass (2026-10-12), a bit more (you):** getting further keeps a level open, and new players are
told that finishing a level opens the next, as described in HANDOFF **(suggested)**. Next: the Studio test of
passes 18 to 57.

**Fifty-sixth pass (2026-10-12), a bit more (you):** the climb through the levels on the dashboard, and the
Self-test opening and locking a level, as described in HANDOFF **(suggested)**. Next: the Studio test of passes 18
to 56.

**Fifty-fourth and fifty-fifth passes (2026-10-12), a bit more (you):** a level opened is told as you come back,
and Near the end on the test panel, as described in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 55.

**Fiftieth to fifty-third passes (2026-10-12), the four you chose (you):** a VIP tag over heads, levels that open
in order (for the whole server, from anyone's save), a storm by the Sky Pools slide, and the Flooded Halls' lamps
failing behind you, as described in HANDOFF; how each works is mine **(suggested)**. Next: the Studio test of
passes 18 to 53.

**Forty-ninth pass (2026-10-12), a bit more (you):** the Self-test compares what is shown with the save, as
described in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 49.

**Forty-eighth pass (2026-10-12), a bit more (you):** the collection in the player list, from the roadmap, as
described in HANDOFF **(suggested: Roblox's own player list rather than anything of the game's)**. Next: the
Studio test of passes 18 to 48.

**Forty-seventh pass (2026-10-12), a bit more (you):** the Self-test sees what was built and the server
answering, as described in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 47.

**Forty-sixth pass (2026-10-12), a bit more (you):** the client's Self-test, completed, as described in
HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 46.

**Forty-fifth pass (2026-10-11), a bit more (you):** the Self-test's client half, as described in HANDOFF
**(suggested)**. Next: the Studio test of passes 18 to 45.

**Forty-fourth pass (2026-10-11), a bit more (you):** the Self-test, wider, as described in HANDOFF
**(suggested)**. Next: the Studio test of passes 18 to 44.

**Forty-third pass (2026-10-11), a bit more (you):** the test panel's Self-test, as described in HANDOFF
**(suggested)**. Next: the Studio test of passes 18 to 43.

**Forty-second pass (2026-10-11), a bit more (you):** fingerprints, so the paste check names old copies, as
described in HANDOFF **(suggested)**. Next, and worth more now than anything built blind: the Studio test of
passes 18 to 42.

**Forty-first pass (2026-10-10), a bit more (you):** the paste check's two new lines, as described in HANDOFF
**(suggested)**. Next: the Studio test of passes 18 to 41.

**Fortieth pass (2026-10-10), a bit more (you):** paid passes kept when Roblox is slow to answer, and the
Robux prompts on the dashboard, as described in HANDOFF **(suggested)**. Next: the Studio test of passes 18
to 40.

**Thirty-ninth pass (2026-10-10), a bit more (you):** level progression and kiosk visits on the Creator
Dashboard, as described in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 39.

**Thirty-eighth pass (2026-10-10), a bit more (you):** a readable Output for the test, as described in
HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 38; after it, the Flooded Halls' lights failing
behind you (left for after the test, as it changes a level whose lighting you have shaped).

**Thirty-seventh pass (2026-10-10), a bit more before testing (you):** the test panel's keepsake and journal
buttons, as described in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 37.

**Thirty-sixth pass (2026-10-09), a bit more (you):** the paste check, as described in HANDOFF
**(suggested)**. Next: the Studio test of passes 18 to 36, starting from what the paste check says.

**Thirty-fifth pass (2026-10-09), a bit more (you):** the death card under a locked cursor, leaving a run
you are not in, and a safer mutation runner, as described in HANDOFF **(suggested)**. Next: the Studio test
of passes 18 to 35.

**Thirty-fourth pass (2026-10-09), a bit more (you):** the store's read limits in a busy lobby, fixed as
described in HANDOFF **(suggested)**. Next: the Studio test of passes 18 to 34.

**Thirty-third pass (2026-10-09), a bit more (you):** a review of what only shows with more than one
player, which found four bugs (statues piling up, the lobby keeping a level's sky, a reset in the lobby
putting you on the level, late joiners not counted into the run), fixed as described in HANDOFF
**(suggested: all of it)**. Next: the Studio test of passes 18 to 33, with two players for this one.

**Thirty-second pass (2026-10-08), a bit more (you):** the keepsake shelf, from the roadmap, built as
described in HANDOFF **(suggested: in the squish room rather than the lobby, each player's own collection on
it, the prompt opening the journal)**. Next: the Studio test of passes 18 to 32.

**Thirty-first pass (2026-10-08), a bit more (you):** the journal kept between sessions, from the roadmap,
and tokens only for a route walked, built as described in HANDOFF **(suggested: saving what the story wrote
from the server only, reading it back quietly, showing what you have as taken)**. Next: the Studio test of
passes 18 to 31; then the other level improvements, and the roadmap below.

**Thirtieth pass (2026-10-07), a bit more (you):** a review of everything a client can ask the server for,
which found a leaderboard exploit and a chill best saved as 0, and two ways for the game to grow: an invite
from the pause menu and the favourite asked once, built as described in HANDOFF **(suggested: all of it)**.
Next: the Studio test of passes 18 to 30; then the other level improvements (City Shore's tide, the Sky
Pools' storm and party, the Flooded Halls flooding behind you), and the roadmap below.

**Twenty-ninth pass (2026-10-07), a bit more, try hard (you):** a review of passes 22 to 28 with five fixes,
and the Sunken City's searchlights as a rescue launch in the harbour, built as described in HANDOFF
**(suggested: one launch rather than several, placed in the open basin past the end of the street, which the
city's blocks never reach; the beam ending at the water with a pool of light; the rain and the thing on the
horizon steering it)**. Next: the Studio test of passes 18 to 29; then the other level improvements (City
Shore's tide, the Sky Pools' storm and party, the Flooded Halls flooding behind you), and the roadmap below.

**Twenty-eighth pass (2026-10-06), a bit more (you):** the Studio test panel and the one chord, built as
described in HANDOFF **(suggested: both)**.

**Twenty-seventh pass (2026-10-05), the squish room (you):** behind a door, built as described in HANDOFF
**(suggested: a lift as the door, real slabs set into the floor over pits, the hall far beyond every
horizon, keeping its players out of the lobby's vote)**. Next: the Studio test of passes 18 to 28; then the
level improvements (City Shore's tide, the Sky Pools' storm and party, the Sunken City's searchlights, the
Flooded Halls flooding behind you), and the roadmap below.

**Twenty-sixth pass (2026-10-05), emotes and the second chance (you):** built as described in HANDOFF
**(suggested: the poses, the toy, the picker and its keys, the second chance never counting for the
leaderboard or a best, buying it from the death card)**. The shop's catalogue is now complete.

**Twenty-fifth pass (2026-10-05), footprints and step sounds (you):** the footprints and step sounds
next. Built as described in HANDOFF **(suggested: the four print shapes and how each fades, swapping
Roblox's footstep rather than layering over it, the packs made of the material takes, Retro as built-in
blips with no upload, the try-on)**. Still to come from the shop: the emotes and the second chance.

**Twenty-fourth pass (2026-10-04), every device (you):** the controller fix and every older screen on
every device. Built as described in HANDOFF **(suggested: D-pad down and up for the menu and the journal,
the Y clash with Talk, the phone layout off the thumbstick and jump, the 44-pixel rule and its exemptions)**.

**Twenty-third pass (2026-10-04), the first five minutes (you):** a player should understand what to do
in their first five minutes, with a welcome. Built as described in HANDOFF **(suggested: three pages with
the controls for your device, the lobby guide to City Shore, Chill, Short and Start, one hint per
material, the way to the shop, and the seven-step funnel)**. Still to come from the shop's plan: the
footprints, step sounds, emotes and second chance; and the every-device rules over the older screens.

**Twenty-second pass (2026-10-04), the shop (you):** the game is to make money; a shop in the style of
the reference reel; tokens earned by finishing levels, with Robux packs; ProfileStore; footprints, trails,
sound packs, passes, auras and emotes; every button on every device; nothing dupable; a clear first five
minutes. Built so far: the saved economy and the shop (design in
`docs/superpowers/specs/2026-10-04-shop-and-economy-design.md`) **(suggested: the tactile look, the kiosk,
the prices and rewards, the try-on, the Studio gift, the analytics)**. Next, in order: the first five
minutes (a welcome, a guided first run, one-time hints, ending at the shop); the footprints, step sounds,
emotes and second chance; and the same every-device rules over the older screens.

**Twenty-first pass (2026-09-30), from your notes (you):** sounds made for each ending, playing while
its scene plays, for a cinematic feel; a more Needoh-like Needoh sound, and which files to replace; the
Needoh and clay no longer sharing a sound; lava that looks about to burst, a hot surface; and a better
final sequence for City Shore. Built as described in HANDOFF **(suggested: the seventeen synthesised
ending sounds and where each one falls, the Needoh borrowing clay's pitched down until its own takes are
in, the lava's breathing glow, embers, heat haze, bubbles and fountain, and the dive's cut to Maren, the
gulls, the rushing air, the sun flare, and the light and fish under the water)**.

**Twentieth pass (2026-09-30), from your notes (you):** whether Ctrl lock should turn you to walk back
(answered: it is standard mouse lock, left as it is); the mouse stuck over NPCs; nicer lettering for your
character's lines in the endings; Roblox's own prompts rather than a restyle; the lobby's viewer putting
you straight back into a good third person; one text size in every speech bubble, with the bubble sized
to the words; the Sky Pools' washed-out light; small improvements to the level and its people; and the
slide's rods seeming to pass through you. Built as described in HANDOFF **(suggested: the prompt card as
the cause of the stuck mouse, Permanent Marker and Kalam for the voice, the habits, the turntable, and
each light setting)**.

**Nineteenth pass (2026-09-30), from your notes (you):** third person as the game's view, first person
only as an option in the lobby and never on the screen, Ctrl toggling the cursor lock as in Squid Game,
and more details small and large, like the whirlpool. Built as described in HANDOFF **(suggested: the
seaside viewer, the slime's camera kick, the moving cloud sea, the swirling whirlpool and lined shaft)**.

**Eighteenth pass (2026-09-29), from recordings (you):** keepsakes as things you actually pick up; notes
and keepsakes kept to read later from a menu rather than coming up over the level; captions held long
enough to read; the lobby and banner waiting for an ending to finish; every ending redone; bubble wrap
heard at once; soap without cracks; softer Sky Pools light. Built as described in HANDOFF **(suggested:
the journal on J, the lit nooks off the route, and the route sometimes leading you to one)**.

**Seventeenth pass (2026-09-29), from your notes (you):** ambience silenced at the endings and added
where there was none; a movie-like script; lore through letters, lockers, doors and things broken open
with a tool, a secret on every level (a tall building off a chunk at City Shore, something under a pool
at the Sky Pools, something by the flume at the Flooded Halls); and a giant creature's mouth at the
bottom of the flume with a scene to match. Built as described in HANDOFF **(suggested: the Hold's drone,
the Fountain screenplay, the pry bar, the Siren Tower and R. Pell, the five secrets, E. Marsh's locker,
"I'll go in tomorrow", the mouth as only ever a mouth, and the dolly zoom)**.

**Fifteenth pass (2026-09-29), from play (you):** every ending about twice as slow so there is time to
read; your character always visible in them whatever the camera; F7 not hiding the debug panel; what
people say up twice as long; better endings everywhere; the void at the end of the Flooded Halls; the
levels numbered in the order they happen; more lore; people in the Flooded Halls; people that look
better; an ending in the Flooded Halls you do not control; and sounds for the materials that had none.
Built as described in HANDOFF **(suggested: the Gate Chamber and the key, the loop back to 9:14, Mrs
Venn's "back rooms of the baths", the notes, the LOOKS table, the generated stand-in sounds and the
MaterialSounds folder)**. Asked, not built: whether to go first person (answered in the pass's reply:
not for the platforming).

**Fourteenth pass (2026-09-26), from play (you):** a more cinematic ending that goes on to the end of
the tunnel, five seconds to stand in the last room after LEVEL COMPLETE, more to the fish, then scenes
for City Shore's dive and the Sky Pools' slide, people on those levels, and a story connecting them in
which the people live their ordinary lives on the day of a disaster while the player calls the place
the backrooms. Built as described in HANDOFF **(suggested: Harrow Bay on 14 August, the key holder who
never came and the time card in the player's name, the culvert and the pumping station, six seconds
for every level, and the fish scattering)**.

**Thirteenth pass (2026-09-26), from play (you):** more water flowing in where the attendant is, the
attendant screaming and moving when the glass goes, the animals, the red notice, the drain's
animation and its animated sequence. Built as described in HANDOFF **(suggested: the old Bootstrap as
the cause, joints of either kind, the fall through the sluice's floor, name resolution in the parser,
and the Ferris wheel's reasons)**.

**Twelfth pass (2026-09-26), from play (you):** the chest the right way round, no animals (the client
not running), water in the aquarium you can swim in with more to it and no boxy water, the rider
animated at the end, the soda chunk vanishing in Sky Pools, and the hub's score sign improved or
removed. Built as described in HANDOFF **(suggested: the server finding out why the client does not
run, a real Luau parser as a checker, the server flailing the rider without the client, the
underwater sound, and removing the sign rather than redesigning it)**.

**Eleventh pass (2026-09-26), from play (you):** readable speech, water that visibly flows into the
aquarium, a jellyfish effect of its own, the drain ride as an animated scene with the character
flailing and screaming for help, a more detailed chest, small improvements, and the animals. Built
as described in HANDOFF **(suggested: the server drawing the flood, the washed-out fade, the teeth of
glass, the Studio panel, and the SeaRig timeout as the likely reason nothing moved)**.

**Tenth pass (2026-09-25), from play (you):** tall landmark buildings as meshes, more city in the
city, only the signed glass tappable, water flowing in when it breaks, the animals visible, and
NPCs. Built as described in HANDOFF **(suggested: which four landmarks, the side streets' poles,
boats and signs, the metro totems, and who the three people are)**.

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

## 5. The Backrooms secret level **(you)**: BUILT 2026-10-14 (sixty-fourth pass), TESTED by 2026-10-17

Built as the back rooms of the baths (HANDOFF, **The back rooms**): the seventh fall in a run, once a run, with a way
out; and since the sixty-fifth pass the lobby's yellow back corridor leads there for anyone who has found them once.

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

**Suggested priority after sections 1 to 5 and 8:**

1. **Kids' playground.** Foam, lego and buttons suit it perfectly; a strong level after Hill House.
2. **Office floors, parking lot, museum, aquarium.** Classic liminal spaces, good as side areas or
   secret routes.
3. **Tiny world of bugs.** The game's materials seen as giant terrain.
4. **The rest, as worlds.**

Space, other planets and rollercoasters break the grounded liminal tone. They fit late, or a
rollercoaster could be a finale ride rather than a whole level.

## 8. Next, in this order **(you, 2026-10-17)**

Asked for after your third test, in your words: the camera angles of levels 1 to 4 "verified extensively" and made
better; the text, fonts, textures and style the same everywhere, "since that would appeal less to an average player";
the lobby expanded, since it "gets way too cluttered", and better modelled; then a new level. Since then: better
quality things in the shop "using blender meshes and animations", every cosmetic looking better, more variety in the
lobby's ambience and its water splashing ("too repetitive"), the butter sticks' deformation fixed, and the remaining
generated sounds made "way better". How each is done is mine **(suggested)** unless marked.

1. **The camera, shot by shot: BUILT (ninety-third pass), waiting for a test.** Every scripted shot in levels 1 to 4
   is played through the game's own camera by `blender/check_shots.py` and checked for being seen, its size, its
   length and the camera never inside you. HANDOFF, **The camera, checked shot by shot**.
2. **The butter sticks: BUILT (ninety-fourth pass), waiting for a test.** One shallow dent where you step, no wave
   after it, and the wax wrapper going down and back up with the butter.
3. **The lobby's own sound: BUILT (ninety-sixth pass), waiting for a test.** Two long sea beds drifting against each other, single waves breaking far below, the
   fountain falling into its basin with splashes and plinks, gusts and now and then a bell on a buoy, each at random
   gaps, pitches and loudness and never the same take twice running. Then the remaining generated sounds remade: the
   story's and the levels' ambience, the endings, the keypads and the last four material sounds.
4. **One style everywhere: BUILT (ninety-ninth pass), waiting for a test.** One display face, one body face and one
   for numbers on every screen, one set of corner radii, strokes and button looks, all from `Style.lua`; the words
   printed in the world (signs, letters, notices) kept as they are on purpose. `check_style.py` holds every screen to
   it. HANDOFF, **One style (ninety-ninth pass)**.
5. **The shop's cosmetics as modelled meshes: BUILT (ninety-seventh pass), waiting for a test.** Trails, auras and footprints built from small Blender-modelled pieces
   (puffy stars and hearts, snowflakes, honey drops, clouds, sea glass, sprinkles, fireflies, embers, slime, paw
   prints), animated: trails leave them, auras carry them round you, steps press them into the ground.
6. **The lobby as a promenade by the sea (you chose it): BUILT (hundredth pass), waiting for a test.** Five decks
   on piers over the sea joined by boardwalks: the plaza (the spawn, the fountain, benches, the canopy on its
   columns), the level gates (the pads in an arc round the Start, the Story pad, the mode and length keys on the way
   in), the arcade (the kiosk, the daily chest, the boards, the post box, and the back corridor in a small house of
   its own), the hall of fame (the leaderboard and the statue) and the garden (a lawn, seats facing the sea, the
   seaside viewer and the lift to the squish room). Every place from `LobbyLayout.lua`; `check_hub.py` measures it.
   HANDOFF, **The lobby as a promenade (hundredth pass)**.
7. **Hill House (you chose it): after section 9.** Level 5 in the story's order of play, first in its clock: the key holder's house on
   the hill at eight in the morning, the big clock, the key on its green ribbon by the door, and why you did not go in.

## 9. From your notes of 2026-10-20 **(you)**

Asked for in one message after the lobby, in your words, with what I suggested and you chose marked. In the order they
are being built:

1. **Sounds where they are: BUILT (hundred-and-first pass).** "The fountain ... location based ... fade away the farther
   I go"; wind and the sea stay everywhere. A sound for the lever, "hardcore with a deeper, more dramatic lever crank and
   chill ... more chill"; sounds for "selecting the level, poses on the pedestal, level difficulty". Sky Pools' "light
   bug" (I took it to be the long falls' sheets, white lines to the clouds; tell me if it is still there). "I do not see
   the bubbles popping". "My soap crumble was better": your own recording is played alone now.
2. **One font, every device: BUILT (hundred-and-second pass).** "They should all be ONE style!!!" (Nunito, you chose
   it); "verify that every device can see everything and that everything scales properly".
3. **The back rooms: BUILT (hundred-and-third pass).** "Go back through the door I came, just like in the movie" (from
   the lobby only); "make the backrooms guy way scarier and the screamer way more dramatic"; "improve the looks of
   backrooms greatly".
4. **What you say, and a deeper story: BUILT (hundred-and-fourth pass).** "I want to say the lines to them myself ...
   walking away ... the options ... disappear by themselves"; "I also want the plot to be deeper": you are Marsh's
   child (you chose it).
5. **The shop made over.** "Stylistically connect the shop UI and its vibe with the rest of the level"; colour; the
   mouse cursor as a chunk, a cookie that crumbles; effects splashing and splattering, with sounds; a different sound
   for each tab; the background cracking if it is ice, sparkling if lava, crumbling if soap; a random background of
   defaults; backgrounds to buy, detailed, in rarities (token crates and Robux mythics, you chose); open and close with
   their own animation and sound.
6. **Trails and auras.** "Even cooler and even slicker and even more pronounced", the trail "less wide ... more
   specific effects, not just a line that fades out".
7. **Sky Pools' arches.** "Glowing or making these cool sparkling effects and kind of like shake my camera a little".
8. **The lobby's look and feel.** "Greatly improve the vibe and aesthetics of the lobby."
9. **Your sounds, sampled.** "Take a sample of my sounds and improve them": with your files in `audio/yours/`, each
   sound's takes built from your recording (librosa and pedalboard, installed with your OK).
10. **A cookie chunk.** "Add a cookie chunk yk."
11. **Hill House** (section 8, item 7).
