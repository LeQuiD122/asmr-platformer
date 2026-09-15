# Material sound brief

Nine materials, nine sounds. Each entry has what the game actually does with the sound,
what the video should show, what the audio has to be, and a prompt you can paste straight
into a video generator.

## Read this first — it decides whether the audio is usable

**The game fires ONE sound per cell entry.** `DeformationService` announces a genuine
entry, `AudioService` looks the material's `sfxEvent` up in `SOUND_IDS_BY_EVENT` and plays
it once. So what you need out of each video is a **clean isolated one-shot**, not a
continuous ASMR ambience. A thirty-second bed of honey noises is unusable; twelve separate
squelches with silence between them is twelve candidates.

Four things follow from that, and they matter more than how nice the video looks:

- **Silence between hits.** Two seconds of nothing either side of every sound, so you can
  cut a clean one-shot without a neighbour bleeding into it.
- **Dry, close, no room.** Reverb tails overlap when you cross a platform quickly and turn
  into mush. `Constants.AUDIO_MAX_POLYPHONY` is 4, so up to four of these can sound at
  once — anything with a long tail smears.
- **Short.** Target durations are given per material below. A footstep sound longer than
  about half a second arrives late for the step after it.
- **No music, no voice, no room tone.** Anything under the sound comes along with it.

**Several takes per material, and this is why the prompts ask for eight or ten.**
`SOUND_IDS_BY_EVENT` holds a LIST per event and picks one at random on every trigger, never
the same take twice running. Three to five usable cuts per material is the sweet spot —
enough that a run across a platform never doubles a sample, few enough to be worth
uploading. A partly filled list is fine: it varies across whatever is actually there.

That makes the takes worth cutting *differently* rather than identically. Vary the pressure,
the exact spot, the angle — the point is that no two are the same file, so eight identical
presses give you one usable sound, not eight.

---

## 1. Honey — `honeySquish`

**In game:** a pace material. Halves your walk speed (`speedMultiplier = 0.50`), the
surface sinks under you and holds the dent for seven seconds. The sound has to say *slow*
and *sticky* before the speed change is felt.

**Look:** thick amber honey, deep gold (the game's colour is RGB 238/148/24), poured in a
slab and left to settle. A finger or a flat wooden paddle presses into it and lifts away
slowly, drawing a thread that thins and snaps. Warm light from a low angle so the surface
carries a moving highlight. Everything unhurried.

**Sound:** a wet, low, viscous *squelch* on the press, then the finer *tick* of the thread
breaking on the lift. Body in the low mids, no high fizz. **0.4–0.7s.**

> Extreme close-up macro of thick golden honey in a shallow glass dish, warm side lighting.
> A flat wooden paddle presses slowly into the surface and lifts away, pulling a long thread
> that stretches, thins and snaps. Repeated eight times with two seconds of complete
> stillness between each press. Recorded very close and dry, no music, no voice, no room
> reverb. Slow, deliberate, calm.

---

## 2. Butter-wax — `butterWaxCrack`

**In game:** a pace material and the slippery one — `frictionOverride = 0.25`. A brittle
wax film over soft butter; stepping cracks the film. It holds its footprint for **thirteen
seconds**, the longest of any material, so this is the surface that keeps a record of where
you have been.

**Look:** a pale butter block (RGB 240/212/130) under a thin, slightly paler wax shell,
chilled so the shell is taut. Something blunt presses down and the shell fractures in a
short star of cracks; the butter beneath gives softly and stays dented. Cool, even light so
the fracture lines read as shadow.

**Sound:** a dry, brittle, high **crack** — a single snap, not a crunch — immediately
followed by a soft, dull *give* as the butter takes the weight. Two events in one, tight
together. **0.2–0.3s.**

> Macro close-up of a chilled block of pale butter with a thin hardened wax coating. A blunt
> rounded tool presses down; the wax surface fractures with a short spray of cracks and the
> butter beneath compresses and holds the dent. Repeated eight times on fresh areas, two
> seconds of stillness between each. Cool even lighting, very close and dry audio, no music
> or voice.

---

## 3. Kinetic sand — `kineticSandImprint`

**In game:** a **risk** material. Three footfalls on the same cell and it collapses
(`stepsToCollapse = 3`), or three seconds of standing still. The sound needs to be
satisfying the first time and slightly *worse* on repetition — that is the warning.

**Look:** damp kinetic sand, warm tan (RGB 206/176/126), pressed into a smooth bed. A hand
or flat block presses in and lifts, leaving a crisp imprint with a raised berm of displaced
grain around it. Grains visibly shear and crumble at the edges. Low raking light so the
imprint's edge casts a hard shadow.

**Sound:** a soft granular **crunch-compaction** — thousands of tiny grains shearing at
once, more *scrunch* than crunch, with a faint dry hiss as loose grain falls back. No
impact thud. **0.25–0.4s.**

> Extreme macro of damp kinetic sand in a tray, raking low light. A flat block presses
> firmly into the smooth surface and lifts straight up, leaving a sharp-edged imprint with
> a ridge of displaced grain and a few grains crumbling from the edge. Repeated eight times
> on fresh sand, two seconds of stillness between. Very close dry audio, no music, no voice.

---

## 4. Slime — `slimeBoing`

**In game:** a **risk** material that launches you — `launchVelocity = 100`, by far the
biggest number in the config. This is the loudest, most physical sound of the seven and the
only one that is a *reaction* rather than a contact.

**Look:** bright green slime (RGB 126/220/116), glossy and translucent, in a wide shallow
bowl. A hand presses in hard, the slime resists, deforms, then snaps back and throws itself
upward with a wobble that settles. Strong specular highlight so the stretch reads.

**Sound:** a wet, elastic **boing** — a rubbery pitch-bend upward on the release, wet body
underneath, a soft slapping settle. Bouncy, comedic, unmistakably rubber-and-water.
**0.4–0.6s.**

> Macro close-up of bright green translucent slime in a shallow bowl under bright glossy
> lighting. A hand presses down hard into the centre, the slime deforms and resists, then
> releases and springs back upward with a rippling wobble that settles. Repeated eight
> times, two seconds of stillness between each. Very close dry audio, no music, no voice.

---

## 5. Soap — `soapCrumble`

**In game:** a **risk** material and the harshest one — it dissolves in 2.5 seconds of
contact and **stays gone for the rest of the attempt**. It is the only material built from
a field of small cubes rather than a surface, so the sound should be *many small things*,
not one surface failing.

**Look:** a pale blue-white block of dry pressed soap (RGB 232/243/250), chalky and matte.
A tool scrapes and crumbles the surface into fine flakes and small chips that scatter. Dry,
powdery, no moisture anywhere. Flat soft light so it reads as chalk rather than plastic.

**Sound:** a **dry crumble** — a short cascade of small hard fragments breaking loose and
falling, with a fine powdery hiss underneath. Brittle and airy, no wetness, no low end.
**0.3–0.45s.**

> Extreme macro of a block of dry pressed soap, pale blue-white and chalky, in soft flat
> light. A metal edge scrapes across the surface and a section crumbles away into fine
> flakes and small chips that scatter across the table. Repeated eight times, two seconds of
> stillness between each. Very close dry audio, no music, no voice, no reverb.

---

## 6. Bubble wrap — `bubblePop`

**In game:** a **risk** material. Four pops per cell, then the floor gives way. It also
throws you up four studs (`microBounceHeight = 4`). The giant chunk is two sheets deep, so
this sound plays a lot — it has to survive heavy repetition without becoming irritating.

**Look:** near-white translucent bubble wrap (RGB 232/243/250) with large pockets, stretched
over a flat surface, lit from behind so the air in each pocket glows. A fingertip presses one
single pocket until it bursts and the film goes slack. **One pocket at a time** — never a
handful at once, since the game plays one sound per step.

**Sound:** a sharp, dry, high **pop** — a single clean burst with no tail at all. Plasticky,
crisp, minimal low end. The shortest of the seven. **0.08–0.15s.**

> Extreme macro of large-pocket bubble wrap stretched flat and backlit so each air pocket
> glows. A single fingertip presses one pocket until it bursts sharply and the film collapses
> and goes slack. One pocket at a time, eight bursts, two seconds of stillness between each.
> Very close dry audio, no music, no voice, no room reverb.

---

## 7. Creamy keyboard — `keyThock`

**In game:** the newest material, a pace surface. Keys travel 0.31 studs down in 90ms and
return over 380ms with no overshoot. "Creamy" means a specific thing to keyboard people —
smooth travel, damped bottom-out, **no ping and no rattle** — and this sound is where most
of that lives, because the motion is already built to match it.

**Look:** a pastel mechanical keyboard, cream keycaps on a blush-pink case (the game's
colours are RGB 247/240/228 on 233/156/174), matte PBT plastic. One finger presses a single
key fully down and releases. Shot close and slightly above so the cap's travel is visible.
Soft even light, no harsh glare — the caps are matte, not glossy.

**Sound:** a deep, muted **thock** — full-bodied, slightly hollow, marbly. Low-mid weight,
no high-frequency ping, no spring rattle, no sharp click. Damped, as if the case is filled
with foam. The single most important note: **it should sound soft and expensive, not
clicky.** **0.1–0.2s.**

> Close-up of a pastel mechanical keyboard with cream keycaps on a pink case, soft even
> lighting, matte plastic. One finger presses a single key fully down and releases it,
> showing the full travel. Repeated ten times on different keys, one and a half seconds of
> stillness between each press. Very close dry audio, deep muted thock, no music, no voice,
> no room reverb.

---

## 8. Ice — `iceCrack`

**In game:** a **risk** material, and the only one that is slippery *and* breaking —
`frictionOverride` is 0.08 against butter's 0.25, and three steps collapse it. You cannot
stop to think about it, because you are still sliding while it fails.

**Look:** a sheet of clear ice over dark water, pale glacial blue (RGB 196/228/244), lit
from below so the cracks light up. A blunt weight presses down; a white star of fractures
races out from the point and the sheet sags. Frost blooms along each crack.

**Sound:** a bright, brittle **crack** with a hollow *ring* under it — the same gesture as
butter-wax but without the soft give, and with a long thin resonance instead. That ring is
what says the sheet is large and there is water beneath. **0.25–0.4s.**

> Extreme macro of a sheet of clear ice over dark water, lit from below so fractures catch
> the light. A blunt weight presses down and a white star of cracks races outward across
> the surface. Repeated eight times on fresh ice, two seconds of stillness between each.
> Very close dry audio, no music, no voice, no room reverb.

---

## 9. Jello soda — `jelloWobble`

**In game:** a **pace** material and the only one that gives energy *back*. It compresses
under a step and bounces you on the rebound (`microBounceHeight = 3`), so the timing of
your last landing changes your next jump.

**Look:** an amber soda jelly (RGB 244/158/96), translucent and glossy, with carbonation
bubbles suspended and rising through it. A finger presses the top and the whole block
wobbles, the bubbles shivering with it. Backlit so the light bends through the wobble.

**Sound:** a low, wet **wobble** — a soft rubbery *whumph* on the press with a pitch dip as
it flexes, then a faint **carbonated fizz** on the tail. The fizz is the whole identity: a
jelly without it is just slime, and this material sits next to slime in the level.
**0.35–0.55s.**

> Macro close-up of an amber soda jelly on a plate, translucent and glossy with bubbles
> suspended inside it, backlit. A finger presses the top and releases; the whole block
> wobbles and the bubbles shiver. Repeated eight times, two seconds of stillness between
> each. Very close dry audio, a soft wet wobble with a faint fizz, no music, no voice.

---

## 10. Lamb's ear — `leafBrush`

**In game:** a **pace** material, and the quietest surface in the game on purpose. Every
other material answers a footfall with a pop, a crack or a squelch; this one barely answers
at all, which is what makes the chunk after it louder for free. It also holds a mark longer
than anything except sand (`decayDuration = 6`), so a player crossing at a walk can look
back and see the whole line they took.

**Look:** a dense mat of overlapping silvery-green leaves (RGB 176/187/152), each one a
thick felted blade covered in fine white hairs, lying over each other like shingles. The
silver is the hairs; the green only shows in the hollows where the nap parts. Matte
throughout, with no specular highlight anywhere on it. Where a hand or foot has brushed
across it, the nap lies flat and that patch goes DARKER and slightly glossier than the
upright fuzz around it, and it stays that way.

**Sound:** a dry, soft **brush** with no attack — the sound of a palm sweeping over felt or
suede. Almost under the floor of what a listener notices: high, airy, with a faint papery
rustle from the leaves shifting against each other. Nothing wet, nothing crisp, no
footfall thud. If a take sounds like a footstep it is the wrong take, and the most common
failure will be a recordist making it too loud. **0.25-0.45s.**

> Macro close-up of a dense clump of lamb's ear, silvery-green velvety leaves overlapping,
> soft daylight from one side. A hand brushes slowly across the leaves and lifts away,
> leaving the nap pressed flat in a visible darker streak. Repeated eight times, two
> seconds of stillness between each. Very close dry audio, a faint dry brushing of fur
> against skin, no music, no voice.

---

## 11. Memory foam - `foamCompress`

**In game:** a **pace** material, and the only one that keeps giving while you stand still.
It compresses further the longer you are on it, so hesitating costs you height and push-off.
The hollow rises back slower than it went down.

**Look:** a block of open-cell memory foam, cream (RGB 238/232/218), completely matte with no
specular anywhere. Big irregular pores through the surface with thin walls standing between
them. A hand presses in and the foam closes around it; lifted away, the print stays and then
rises out slowly over several seconds.

**Sound:** almost nothing, and nothing crisp. A soft compressing **whump** with air moving
through the cells, very low and very short, plus a faint creak of the cell walls. No thud, no
impact transient. The second-quietest material in the game after lamb's ear. **0.3-0.5s.**

> Macro close-up of a block of cream memory foam in soft light. A hand presses slowly into it
> and lifts away, leaving a hollow that rises back out on its own. Repeated eight times, three
> seconds of stillness between each. Very close dry audio, a soft airy compression, no music,
> no voice.

---

## 12. Light switches - `switchClack`

**In game:** a **pace** material and the keyboard's opposite number. These **latch**: the
rocker stays thrown and the switch lights up, so a platform you crossed stays lit behind you
for the rest of the run.

**Look:** a wall of off-white plastic rocker switches (RGB 242/240/232) in square faceplates,
laid out in a regular grid. Each rocker is visibly tilted at rest - one end proud, one end
sunk - so a switch reads as OFF before anything touches it. Thrown, the paddle flips and a
warm light comes on behind it.

**Sound:** the **hardest attack in the game**. A loud plastic **CLACK** with an over-centre
snap in it - two-stage, the spring going over followed by the paddle hitting its stop.
Nothing soft, nothing wet, no tail. This is the one material where a sharp transient is
correct and a gentle take is the wrong take. **0.1-0.2s.**

> Macro close-up of a bank of white plastic rocker light switches on a wall. A finger flips
> one down and it stays down. Repeated eight times on different switches, two seconds of
> stillness between each. Very close dry audio, a hard plastic snap, no music, no voice.

---

## 13. Lego - `legoClick`

**In game:** a **risk** material, and the only **hard** surface in the game. It does not yield
at all - your foot stops dead. Four steps on the same cell pops the brick out and it flies
off, leaving a real hole.

**Look:** a red ABS baseplate (RGB 206/62/54), glossy and flawless, with studs on a regular
grid and brick seams laid in a running bond so the joints of one course fall over the middle
of the one below. Injection-moulded perfection: no wear, no grain, no variation.

**Sound:** a dry plastic **tick** - hard, small and completely without resonance. Then, on the
brick coming loose, the distinctive **squeak-and-release** of two bricks separating. Both
totally dry. **0.08-0.25s.**

> Macro close-up of a red lego baseplate. A finger taps a stud, then pulls a brick free from
> the plate. Repeated eight times, two seconds of stillness between each. Very close dry
> audio, hard plastic clicks and one separation squeak, no music, no voice.

---

## 14. Charcoal - `charcoalSnap`

**In game:** a **risk** material that **snaps** rather than crumbles. Sand loses cohesion over
three steps and slumps; charcoal holds completely and then breaks all at once on the second.

**Look:** angular black lumps (RGB 44/42/41) with flat facets meeting at sharp edges, none of
them parallel. Sooty and matte in the hollows, with a faint **graphite sheen** on the high
points where handling has burnished it. When it goes, it breaks into angular pieces and
throws slow black dust that hangs in the air.

**Sound:** a dull, dry **snap** with no ring to it - the sound of something breaking that has
no springiness at all - followed by a scatter of grit. The absence of resonance is the whole
identity: ice cracks with a bright ring, charcoal cracks dead. **0.25-0.45s.**

> Macro close-up of a piece of barbecue charcoal on a dark surface. Two hands snap it in half
> and the pieces drop, shedding black dust. Repeated eight times, two seconds of stillness
> between each. Very close dry audio, a dull dry snap and scattering grit, no music, no voice.

---

## 15. Chocolate - `chocolateSnap`

**In game:** a **risk** material and the only one that changes **state**. Standing on it melts
it: it loses its gloss first, then its shape, and it gets **slipperier** as it goes
(`frictionOverride = 0.30`). Cross it in three quick steps and you are fine; linger and you
are not.

**Look:** a moulded dark milk chocolate bar (RGB 94/58/34), segments in a grid with deep
valleys and moulded draft on every side. High gloss, close to a mirror where it is tempered,
with pale matte **bloom** patches where cocoa butter has recrystallised. Under a warm hand the
gloss goes first, turning wet-looking, and then the edges soften and slump.

**Sound:** a clean, brittle **crack** with a little ring to it - the tempered snap - that
becomes progressively **duller and softer** on later takes as the bar warms, ending in a
muted bend with no break at all. That progression is the brief: record it going from crisp to
dead. **0.2-0.4s.**

> Macro close-up of a dark chocolate bar in warm light. Hands snap a segment off; the surface
> is glossy and slightly bloomed. Repeated eight times as the bar warms and softens, two
> seconds of stillness between each. Very close dry audio, a crisp snap becoming duller each
> time, no music, no voice.

---

## 16. Clay - `claySquish`

**In game:** a **pace** material, and the **visitor book**. Impressions are permanent for the
whole session (`decayDuration = 600`), so by the end of a run a clay chunk carries every route
every player took across it. It never fails and never drops you.

**Look:** a slab of wet terracotta (RGB 178/116/88), completely matte, with a few long bowed
finger drags and some thumb dents in it and nothing else - deliberately quiet, so the
footprints pressed into it are the loudest thing on the surface. Fine grog speckle in the
body. A print taken in it has a sharp edge and stays sharp.

**Sound:** a wet, dense **press** with no tail at all - clay absorbs rather than resonates.
A soft squelch with a little suction on the release. Lower and denser than slime, and it stops
dead instead of ringing on. **0.2-0.4s.**

> Macro close-up of a slab of wet terracotta clay. A hand presses down and lifts away, leaving
> a sharp print. Repeated eight times in different places, two seconds of stillness between
> each. Very close dry audio, a dense wet press with slight suction, no music, no voice.

---

## 17. Cloud - `cloudHush`

**In game:** a **risk** material with **no steps to count**. Ice gives three chances and shows
you the crack widening; cloud gives none, because you begin sinking the moment you land and
you never stop. The only thing that saves you is not standing still.

**Look:** a mass of white cumulus (RGB 246/249/255), partly transparent so you can half see
through the thing holding you up. Rounded cauliflower lobes with no countable spheres among
them and no crisp edge anywhere. Vapour lifts off it where a foot lands.

**Sound:** a **breath**. Airy, wide, with no attack and no defined end - white noise shaped
like an exhale. This is the only material with no impact component whatsoever; if there is
anything you could call a hit in the take, it is the wrong take. **0.5-0.9s.**

> Macro close-up of dense white fog rolling slowly across a dark surface, lit softly from
> above. A hand passes through it and the fog swirls and closes. Repeated eight times, three
> seconds of stillness between each. Very close dry audio, a soft airy hush with no impact,
> no music, no voice.

---

## 18. Salt - `saltCrunch`

**In game:** a **pace** material, and the only surface that gets **better** as you wreck it.
Every step compacts the crystals into a denser, flatter patch that stays packed for 25
seconds. The trodden path you leave is a route for the next player.

**Look:** loose cubic rock salt (RGB 244/245/246), flat-topped crystals at random rotations,
white and glittering in points rather than glowing evenly. Where it has been walked on the
crystals are crushed flat and the sparkle is gone.

**Sound:** a dry, sharp **crunch** with a lot of high frequency - many small hard things
breaking at once. Crucially it must get **duller and quieter each take**, because the fourth
step is landing on powder rather than crystals. Record the progression. **0.15-0.3s.**

> Macro close-up of coarse rock salt on a dark surface. A hand presses down and grinds
> slightly, crushing the crystals. Repeated eight times in the same spot as the salt turns to
> powder. Very close dry audio, a sharp crunch becoming duller each time, no music, no voice.

---

## 19. Lava crust - `lavaCrust`

**In game:** a **risk** material where **you make the floor as you go**. The surface is
molten; standing on it crusts a raft of obsidian under your feet. Three steps and the raft
cracks back into melt. Ice starts safe and you spend it - this starts lethal and you earn it.
It also **drags** (`frictionOverride = 1.6`), the only above-1 friction in the game.

**Look:** black obsidian rafts floating on incandescent orange channels (RGB 255/148/52 on
28/22/24). The plates are near-mirror glossy; the melt between them is matte, because it is
radiating rather than reflecting. As you stand, the glow under you goes out and the surface
goes black.

**Sound:** a low, continuous **hiss** with a **glassy tick** layered on top as the crust
forms - the tick is the important half and it should be brittle and small against the hiss.
Then on failure, a wet crackle as the raft breaks. No roaring: lava is quiet. **0.4-0.7s.**

> Macro close-up of molten glass or slag cooling on a dark surface, orange fading to black
> crust, with the crust cracking. Repeated eight times, two seconds of stillness between
> each. Very close dry audio, a low hiss with small glassy ticks, no music, no voice.

---

## 20. Non-Newtonian fluid - `ooblSquelch`

**In game:** a **risk** material and the one real-world property that is already a platformer
mechanic. Run and it holds you; stand still for 1.4 seconds and you go through. Not the
cloud - cloud sinks from the moment you land, oobleck is completely solid until you stop.

**Look:** pale cornflour slurry (RGB 236/234/226), matte where it has stiffened and wet where
it has relaxed, with the surface frozen mid-ripple - sharp-crested waves rather than smooth
swells, because a shear-thickening fluid throws stiff peaks under impact.

**Sound:** a thick, dense **squelch** with **no splash at all**. That absence is the whole
brief: this material sounds like something being punched rather than something being poured,
so no droplets, no trickle, no wetness on the tail. A dull heavy slap with a short rubbery
ring. **0.2-0.4s.**

> Macro close-up of cornflour and water mixed to a thick slurry in a bowl. A fist punches the
> surface and it stays solid, then a finger sinks in slowly. Repeated eight times, two
> seconds of stillness between each. Very close dry audio, a dense slap with no splash, no
> music, no voice.

---

## 21. Clicky buttons - `buttonClick`

**In game:** a **pace** material and the only surface that gives energy **back**. The
keyboard depresses and returns; the switches latch; a button bottoms out hard and then
**throws you off it** (`microBounceHeight = 6`). It is the one of the three you would choose
to walk on for the movement rather than the sound.

**Look:** big round arcade caps in recessed housings (RGB 222/76/72), domed and standing well
proud of the plate, glossy, with a polished worn spot on each crown where thumbs land.

**Sound:** the **sharpest click in the game after the light switches**, and it must be
two-part: a hard **crisp click** going down and a distinct **lighter click** coming back up.
Most button recordings capture only the press. The release is what makes this feel springy
rather than dead. **0.08-0.18s.**

> Macro close-up of large arcade buttons on a control panel. A finger presses one fully down
> and releases it, and the cap springs back. Repeated eight times on different buttons, two
> seconds of stillness between each. Very close dry audio, a sharp click down and a lighter
> click up, no music, no voice.

---

## 22. Melting snow - `snowPack`

**In game:** a **risk** material that is melting whether you are there or not - the chunk
drips from its underside and all four sides before you reach it. Four steps, the most of any
collapsing material, because snow is deep and gives a little each time rather than holding
and then breaking. That is what separates it from the ice.

**Look:** soft white drifts (RGB 250/251/255) with a fine brittle crust crazing the top,
sparkling in points, and **blue in every hollow** - snow is deep enough for light to scatter
inside it, so what comes back out of a dent has lost its warm end. Meltwater runs off every
face.

**Sound:** a soft **compressing squeak** - the high, almost rubbery noise cold snow makes
under a boot - with a dull thud under it. No crunch: crunch is salt and gravel, and squeak is
what tells a listener this is snow and that it is cold. **0.25-0.45s.**

> Macro close-up of a boot pressing slowly into fresh snow, compacting it, then lifting away.
> Repeated eight times in different spots, two seconds of stillness between each. Very close
> dry audio, a soft high squeak with a dull thud, no music, no voice.

---

## Where the ids go

`src/Client/Services/AudioService.lua`, in `SOUND_IDS_BY_EVENT`:

```lua
local SOUND_IDS_BY_EVENT: { [string]: { string } } = {
	honeySquish = { "rbxassetid://111", "rbxassetid://112", "rbxassetid://113" },
	butterWaxCrack = { "rbxassetid://121", "rbxassetid://122" },
	kineticSandImprint = {},
	slimeBoing = {},
	soapCrumble = {},
	bubblePop = {},
	iceCrack = {},
	jelloWobble = {},
	keyThock = {},
}
```

Fill them in as you go — an empty list is silent, and the materials you have done already
work while the rest wait.

Paste them into the repo copy of the file, not only into Studio — the next paste of
`AudioService.lua` overwrites whatever is in Studio, and an empty string here is silent.

**Never use `rbxassetid://0` as a placeholder.** It is a real request for an asset that does
not exist, so Roblox retries it and logs a failure on every single trigger. An empty string
is skipped silently, which is why the unfilled ones are empty.
