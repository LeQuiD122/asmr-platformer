--!strict
-- ReplicatedStorage/Shared/MaterialConfig.lua
-- Single source of truth for all material physics constants.

export type MaterialCategory = "pace" | "risk"

export type MaterialDef = {
	category: MaterialCategory,
	speedMultiplier: number?,
	frictionOverride: number?,
	decayDuration: number,
	launchVelocity: number?,
	dissolveTime: number?,
	-- Footfalls a cell survives before it gives way. Separate from dissolveTime, which
	-- is a clock: this counts CONTACTS, so crossing a cell repeatedly breaks it down
	-- even though no single visit is long.
	stepsToCollapse: number?,
	popCount: number?,
	microBounceHeight: number?,
	sfxEvent: string,
	-- Minimum seconds between two sounds of THIS material, whatever fires them. See the
	-- note in AudioService: sub-regions are 2.5 studs and a stride crosses several at once,
	-- so without a per-material gate one footfall plays three or four copies of the same
	-- file on the same frame.
	--
	-- EVERY MATERIAL IS AT 0.2, tuned by ear in play.
	--
	-- It carries more weight now than when it was set: sound no longer dedupes on the
	-- visual repeat guard, so a cell you re-cross fires again instead of being silent, and
	-- this gate is the only thing deciding how often that may happen. The field stays per-material rather than becoming a constant: the values
	-- genuinely want to differ eventually and the tuning is done by ear, not derived. The
	-- one to revisit first is bubble wrap -- at 0.26 it can pop about four times a second,
	-- and overlapping crackle is arguably the whole appeal of the material -- but that is a
	-- judgement to make while walking on it rather than from the numbers.
	sfxMinGap: number?,
	deformationAnim: string,
	-- A material that MOVES MATERIAL between cells rather than failing where it is stood on:
	-- "squeeze" for clay, "brine" for salt. See DISPLACEMENT in DeformationService.
	displacement: string?,
	-- How many presses take a cell as far down as it goes.
	displaceSteps: number?,
	-- Pushes a salt plate takes before it lifts and tilts, and will not take a foot.
	displaceTilt: number?,
	-- Pushes a clay lip takes before it tears off, or a salt plate before it sinks.
	displaceLimit: number?,
	-- How far a salt cell has to be packed before packing it further pushes brine out sideways.
	displaceFrom: number?,
	-- Seconds a lifted, tilted salt plate floats before it sinks on its own.
	sinkAfter: number?,
	-- Seconds between the presses a player standing still gives the cell under them.
	creepEvery: number?,
	bounceCooldown: number?,
	-- KEYPADS. What each of the three switches does to your walking speed, by the name
	-- ChunkBuilder writes on the tile as `Switch`. See KEYPADS in DeformationService.
	switchSpeeds: { [string]: number }?,
	-- How long a clicky press's surge lasts, including after you have left the pad.
	surgeLinger: number?,
	-- Clicky presses in a row, each inside `streakWindow` seconds of the last, that make a combo,
	-- and the surge a combo gives and how long it lasts.
	comboAt: number?,
	streakWindow: number?,
	comboSpeed: number?,
	comboLinger: number?,
	-- The event to play while this material's own `sfxEvent` has no takes uploaded.
	sfxFallback: string?,
	-- THE NEEDOH SQUEEZE. Seconds of standing still before the dough starts to give, seconds
	-- from there to fully squeezed, and your jump HEIGHT at full squeeze as a multiple of normal.
	chargeAfter: number?,
	chargeTime: number?,
	chargeJump: number?,
	-- A KEYPAD CIRCUIT: a clicky press in every row of the pad inside one streak. Its surge.
	circuitSpeed: number?,
	circuitLinger: number?,
	-- A KEYPAD CAPACITOR, the violet switch. How many charges it stores, how long they hold from the
	-- last violet press, what each one adds to the surge of the clicky press that spends them and to
	-- how long it lasts, and the fastest any keypad surge can go.
	capacitorMax: number?,
	capacitorHold: number?,
	dischargeSpeed: number?,
	dischargeLinger: number?,
	surgeCap: number?,
	-- A KEYPAD SPRING, the pink switch. Your jump height on it as a multiple of normal, one entry per
	-- level of a bounce chain, and the seconds after jumping off pink that landing on pink is a bounce.
	springJump: { number }?,
	springChain: number?,
	-- CHARCOAL EMBERS. Seconds from a foot to the coal burning, how long it burns before it is ash
	-- and gives way, when a burning coal tries to light each neighbour and the chance it does, how
	-- much sooner a foot on burning coal makes it go, when an ash hole has a fresh coal in it, and
	-- your walking speed on burning coal.
	igniteAfter: number?,
	burnFor: number?,
	spreadAfter: number?,
	spreadChance: number?,
	stompBurn: number?,
	regrowAfter: number?,
	hotSpeed: number?,
	-- OOBLECK WADING. How fast you sink standing and moving (a full wade per second), the speed
	-- below which you count as standing, how much of your speed the deepest wade takes, the landing
	-- speed that hardens the pool, how long it stays hard, and when a hole fills back in.
	wadeStill: number?,
	wadeMoving: number?,
	wadeSlow: number?,
	wadeDrag: number?,
	shockFrom: number?,
	shockTime: number?,
	healAfter: number?,
}

local Materials: { [string]: MaterialDef } = {
	Honey = {
		category = "pace",
		speedMultiplier = 0.50,
		decayDuration = 7,
		sfxMinGap = 0.2,
		sfxEvent = "honeySquish",
		deformationAnim = "sink",
	},
	ButterWax = {
		category = "pace",
		frictionOverride = 0.25,
		-- LONGER THAN EVERY OTHER MATERIAL, and butter is the one that earns it. This
		-- is the wait between stepping off and the surface returning to pristine, and
		-- the renderer holds most of the dent (WAX_RESIDUAL) for all of it -- so this
		-- number is how long your footprints stay in the block behind you. Warm butter
		-- is plastic, it keeps the shape it was pushed into; at 7s the platform had
		-- smoothed itself out before you were far enough along to look back at it,
		-- which read as the butter springing back the way honey does.
		decayDuration = 13,
		sfxMinGap = 0.2,
		sfxEvent = "butterWaxCrack",
		deformationAnim = "crack",
	},
	KineticSand = {
		-- RISK, because it collapses under you and drops you off the level. Note this
		-- field is documentation: nothing reads it, and slot eligibility comes from the
		-- CHUNK's category in ChunkDefinitions. Sand's three chunks (P3, P4, C2) are
		-- still pace and connector chunks, so a pace section can currently drop you --
		-- reclassifying those is a separate, deliberate level-design change.
		category = "risk",
		frictionOverride = 0.75,
		decayDuration = 7, -- candidate for 15-20s post-playtest; NOT permanent
		-- IT FALLS APART. Kinetic sand holds together right up until it does not, which
		-- is the whole appeal of the stuff -- so standing still on a cell long enough
		-- costs you the floor, the same mechanic soap has.
		--
		-- 4.0 against soap's 2.5, because the two are doing different jobs. Soap is a
		-- risk chunk you are meant to hurry across; sand sits in PACE slots, where a
		-- trap that punishes normal walking would break the level's rhythm. Four seconds
		-- is comfortably longer than crossing a cell takes and only catches loitering.
		--
		-- But TIME ALONE WAS THE WRONG MODEL and made the mechanic nearly unreachable:
		-- the timer wants continuous occupancy of ONE cell, and walking leaves a cell
		-- long before four seconds are up. Kinetic sand does not fail because you stood
		-- on it, it fails because it has been WORKED -- so the count below is the real
		-- trigger and the clock is only the standing-still case.
		-- 2.3 (was 3.0): every chunk that can drop you now gives way faster.
		dissolveTime = 2.3,
		stepsToCollapse = 3,
		sfxMinGap = 0.2,
		sfxEvent = "kineticSandImprint",
		deformationAnim = "imprint",
	},
	Slime = {
		category = "risk",
		-- DEVIATION FROM GDD v1.1: doc pins 70 studs/s (~12.5 studs of height).
		-- Raised to 100 (~25.5 studs, about 4x a default jump) because 70 read as
		-- barely more than a normal jump once you are already moving. Note the
		-- earlier weakness was mostly the Humanoid state bug, not this number, so
		-- tune this down if it now overshoots.
		launchVelocity = 100,
		decayDuration = 7,
		sfxMinGap = 0.2,
		sfxEvent = "slimeBoing",
		deformationAnim = "stretch",
	},
	Soap = {
		category = "risk",
		-- SLIPPERY, and its absence was the oddest gap in the game: the one material every
		-- player expects to slide had ordinary floor grip. It lands between ice at 0.08 and
		-- butter-wax at 0.25, nearer the ice end, because a wet bar underfoot goes out from
		-- under you the way ice does -- but it is a solid being crushed rather than a film,
		-- so it still bites a little.
		frictionOverride = 0.12,
		-- 1.9 (was 2.5): every chunk that can drop you now gives way faster.
		dissolveTime = 1.9,
		decayDuration = 7,
		sfxMinGap = 0.2,
		sfxEvent = "soapCrumble",
		deformationAnim = "crumble",
	},
	CreamyKeyboard = {
		-- PACE, not risk. Nothing about a keyboard can drop you: the keys bottom out on a
		-- solid chassis 0.55 studs down and that chassis is the floor. What it changes is
		-- how you MOVE across it -- deliberately, one key at a time -- which is exactly
		-- what a pace material is for.
		category = "pace",
		-- Barely slower. A keyboard is not sticky like honey or slippery like butter; the
		-- resistance is psychological, and 0.92 is enough to make the crossing feel
		-- measured without the player noticing a number changed.
		speedMultiplier = 0.92,
		-- SHORT, and the shortest of any material here. Every other surface in the game
		-- keeps its mark: honey holds a dent, butter holds a footprint for thirteen
		-- seconds, sand keeps the print until it collapses. A key that stayed down would
		-- be a broken key. Returning is the whole character of the material.
		decayDuration = 2,
		sfxMinGap = 0.2,
		sfxEvent = "keyThock",
		deformationAnim = "press",
	},
	-- SALT: a crust over brine, better where you have been and worse where you have not.
	--
	-- Each step packs the crystals under you into a denser, flatter, faster patch, and that has
	-- always been the material: the second visit to a cell is better than the first. What it was
	-- missing is where the brine goes. Packing the crust squeezes the brine out from under it
	-- into the loose crust beside it, and that crust HEAVES: one push cracks a plate, two lift
	-- and tilt it, three break it and it sinks. A tilted plate breaks under a foot.
	--
	-- So a trail gets firmer with every pass while the crust either side of it breaks up, and a
	-- player who stops packs themselves onto an island and has to jump off it. Nothing else in the
	-- game breaks the cells you did NOT stand on. See DISPLACEMENT in DeformationService.
	Salt = {
		-- Documentation, as sand's is: the chunk stays in PACE slots, because a steady crossing
		-- is safe. Stopping, doubling back and crowding are what break the crust.
		category = "risk",
		-- Loose crystals roll under you. DeformationService takes this back toward 1 as the cell
		-- you step onto is packed, which is the reward half of the material.
		speedMultiplier = 0.88,
		-- Thirty seconds, down from the whole session (600). The trail and the broken crust beside
		-- it are the record of who crossed, and at twenty-five seconds a trail loosened again
		-- before anyone could use it -- but a record that outlasts the run is also what left a
		-- player stranded on a crust they could no longer cross. See REGROW_DURATION.
		decayDuration = 30,
		displacement = "brine",
		displaceSteps = 3,
		-- NOT FROM THE FIRST STEP. The first crushes the loose crystals on top; it is packing the
		-- cell harder that forces the brine out. Pushing from the first step broke a plate under
		-- the second foot of an ordinary crossing: a player walking with a foot either side of a
		-- cell line strains the next cell under that foot from behind AND from beside before it
		-- lands. Measured in sim_displace, from DeformationService's own rules.
		displaceFrom = 2,
		displaceTilt = 2,
		displaceLimit = 3,
		-- A floating plate does not float for long.
		sinkAfter = 8,
		-- Standing on a cell packs it again this often. Two of these and the plates around you
		-- are floating, and stepping off onto one of them is stepping into the brine.
		creepEvery = 1.2,
		sfxMinGap = 0.15,
		sfxEvent = "saltCrunch",
		deformationAnim = "compact",
	},
	-- LAVA AND OBSIDIAN: you make the floor as you go, and it does not last.
	--
	-- The surface is molten. Standing on it crusts it over -- your own heat loss freezes a
	-- raft of obsidian under your feet -- so a safe path exists only where you have already
	-- been. Then the crust cracks, because a raft that thin over moving rock always does.
	--
	-- Three steps like ice, and deliberately so: the two are the same shape of problem read
	-- opposite ways. Ice starts safe and you spend it; lava starts lethal and you earn it.
	Lava = {
		category = "risk",
		-- Molten rock is not slippery, it is DRAGGING. The only friction override above 1
		-- in the game, so crossing feels laboured rather than skated.
		frictionOverride = 1.6,
		stepsToCollapse = 3,
		decayDuration = 6,
		sfxMinGap = 0.2,
		sfxEvent = "lavaCrust",
		deformationAnim = "crust",
	},
	-- NON-NEWTONIAN: stamp it hard.
	--
	-- It was "stand still and you sink", which the cloud, the foam and the Needoh all do in one form
	-- or another. What only oobleck does is harden under a BLOW. So you WADE on it: every moment on the
	-- pool you sink a little -- slowly while you keep moving, fast when you stop -- and it drags at
	-- your legs the deeper you are. All the way in, and it has you.
	--
	-- LAND on it and the impact hardens the whole pool at once: everyone wading pops back up and walks
	-- at full speed while it lasts. So the way across is to keep it struck. Hop, and every landing is
	-- a floor for you and for anyone else out on it. A hole fills back in after `healAfter`.
	Oobleck = {
		category = "risk",
		speedMultiplier = 1.0,
		wadeStill = 1.1,
		-- High enough that a crossing at a walk visibly wades (sim_round3: 0.32 never reached the first
		-- step), low enough that it still gets across.
		wadeMoving = 0.45,
		wadeSlow = 8,
		wadeDrag = 0.5,
		-- A default jump lands at about fifty studs a second; walking off a step does not come close.
		shockFrom = 28,
		shockTime = 1.3,
		healAfter = 3.5,
		decayDuration = 5,
		sfxMinGap = 0.2,
		sfxEvent = "ooblSquelch",
		deformationAnim = "shear",
	},
	-- CLICKY BUTTONS: an arcade keypad, and the one surface in the game where the route you pick
	-- across it is written on it in light.
	--
	-- It was one kind of button and it did nothing to you: every cap went down and came back and
	-- the pad was a slab you crossed at normal speed with some violet dots on it. Now every cell
	-- carries one of THREE SWITCHES, the way a switch tester has them, and each one moves your feet
	-- differently. ChunkBuilder decides which cell carries which, symmetric about the pad's centre
	-- and different per keypad, and writes it on the tile as `Switch`.
	--
	--   CLICKY, cyan: it snaps, and throws you forward. The surge carries off the pad.
	--   LINEAR, violet: smooth, nothing to feel, and it leaves a surge you already have alone.
	--   TACTILE, pink: a bump part way down its travel that you feel as drag. It costs your surge.
	--
	-- Three clicky presses in a row is a COMBO: a bigger surge for longer, and the whole pad lights
	-- up in a wave from your foot. No launch anywhere -- the spring is in the cap, and a pad that
	-- threw you upward was a trampoline.
	Buttons = {
		category = "pace",
		speedMultiplier = 1.0,
		-- Tactile is no longer a drag (0.88) that cost you your surge: pink is the spring now.
		switchSpeeds = { clicky = 1.22, linear = 1.0, tactile = 1.0 },
		-- A SURGE THAT STOPPED AT THE EDGE would be over before anyone noticed it: a keypad is
		-- twelve studs long. This is from the last clicky press, and a surge you carry off the
		-- pad lasts this long unless another material takes your speed first.
		surgeLinger = 1.4,
		comboAt = 3,
		streakWindow = 0.8,
		comboSpeed = 1.34,
		comboLinger = 2.4,
		-- THE WHOLE LANE -- a clicky press in every row of the pad without the streak breaking -- is
		-- a CIRCUIT: the pad overloads, and the surge is the biggest in the game.
		circuitSpeed = 1.42,
		circuitLinger = 3.2,
		-- THE VIOLET CAPACITOR: three violet presses and then a clicky one is a surge as big as a
		-- circuit's, for longer, off a single lane button.
		capacitorMax = 3,
		capacitorHold = 4,
		dischargeSpeed = 0.06,
		dischargeLinger = 0.5,
		surgeCap = 1.6,
		-- THE PINK SPRING: half as high again on the first pink button, and a bounce from pink to pink
		-- inside springChain goes a level higher -- the top is the Needoh's full squeeze.
		springJump = { 1.45, 1.8, 2.2 },
		springChain = 1.0,
		decayDuration = 2,
		sfxMinGap = 0.12,
		sfxEvent = "buttonClick",
		-- UNTIL buttonClick HAS TAKES the keypad plays the keyboard's thock -- as a NOTE, pitched by
		-- where the button sits, so a crossing plays a rising run. See the renderer.
		sfxFallback = "keyThock",
		deformationAnim = "press",
	},
	-- SNOW: it is melting whether you are there or not.
	--
	-- The drips are ambient (see AMBIENT in ChunkBuilder), which means a snow chunk is
	-- visibly going before you reach it and would still be going if you never arrived. Your
	-- footsteps only speed it up: each one packs the snow to slush, and slush does not hold.
	--
	-- Four steps, the most of any collapsing material, because snow is deep. It gives a
	-- little each time rather than holding and then breaking, which is what separates it
	-- from the ice two chunks away.
	Snow = {
		category = "risk",
		speedMultiplier = 0.86,
		stepsToCollapse = 4,
		-- AND a clock, because it is melting on its own. Long, so it is not the thing that
		-- gets you -- it is the thing that reminds you the chunk is temporary.
		-- 5.5 (was 7.0): every chunk that can drop you now gives way faster.
		dissolveTime = 5.5,
		decayDuration = 9,
		sfxMinGap = 0.18,
		sfxEvent = "snowPack",
		deformationAnim = "pack",
	},
	-- FOAM: the only surface that keeps giving while you stand still.
	--
	-- Every other material here answers a footfall and then settles. Foam does not settle:
	-- it goes on compressing for as long as you are on it, so the longer you dither the
	-- deeper you are and the less you get back from a jump. It never breaks and never
	-- drops you, which makes it the only material that punishes hesitation without ever
	-- being a risk -- the pressure comes from the surface itself rather than from a threat.
	Foam = {
		category = "pace",
		speedMultiplier = 0.90,
		-- The dwell sink is a client effect (see FOAM in DeformationRenderer); what the
		-- server owns is how long the hollow you left stays behind you.
		decayDuration = 5,
		sfxMinGap = 0.2,
		sfxEvent = "foamCompress",
		deformationAnim = "compress",
	},
	-- LIGHT SWITCHES: the keyboard's opposite number.
	--
	-- Both are fields of discrete things you press, and that is exactly why this one has to
	-- LATCH. A key returning is the whole character of the keyboard -- "a key that stayed
	-- down would be a broken key" is the note in that entry -- so a switch that stays down,
	-- and lights, is the same idea run the other way. The decay is long enough to outlast
	-- most of a run, so a platform you crossed early is still lit when you look back at it.
	LightSwitch = {
		category = "pace",
		speedMultiplier = 0.95,
		decayDuration = 30,
		sfxMinGap = 0.2,
		sfxEvent = "switchClack",
		deformationAnim = "toggle",
	},
	-- LEGO: the only HARD surface in the game.
	--
	-- Ten materials in and every one of them yields -- they sag, stretch, crumble, crack or
	-- compress. Nothing was rigid, and rigidity is a texture too: the studs press back into
	-- your feet and the platform does not move at all. What makes it a risk instead of a
	-- floor is that the bricks are only pressed together, so a cell worked hard enough pops
	-- its brick out and leaves a real hole.
	Lego = {
		category = "risk",
		-- THE ONLY MATERIAL THAT IS BETTER THAN THE FLOOR. A hard clean studded surface is
		-- the best footing there is, and lego is the only rigid thing in a game otherwise
		-- made of substances that give. Barely above 1, because the point is that it feels
		-- SURE rather than fast.
		speedMultiplier = 1.06,
		frictionOverride = 1.15,
		-- Four, the most of any material. A brick does not weaken the way sand or ice does
		-- -- it either holds or it is gone -- so the count is high and nothing about the
		-- surface gives way until the moment it does.
		stepsToCollapse = 4,
		decayDuration = 8,
		sfxMinGap = 0.2,
		sfxEvent = "legoClick",
		deformationAnim = "detach",
	},
	-- CHARCOAL: the grill that catches.
	--
	-- It used to snap on the second step, which half the risk chunks already did in one form or
	-- another. Charcoal is the one thing here that BURNS, and fire is the one hazard in the game that
	-- moves on its own. So: a foot on cold charcoal lights it. The coal smoulders, then burns --
	-- glowing cracks, sparks, smoke -- and while it burns it tries to light the coals beside it. When
	-- it has burned out it is ash, and ash does not hold you. Nothing else here spreads.
	--
	-- A crossing at a walk is always ahead of its own fire: you light the grill behind you, not under
	-- you. Stop, double back, or follow someone across, and the grill is burning out from under
	-- you. Burning coal is hot to stand on, so you hurry on it; stamping on burning coal crushes the
	-- embers and it goes sooner. A fresh coal drops into an ash hole after `regrowAfter`, so the grill
	-- is never burned out for good.
	Charcoal = {
		category = "risk",
		-- Draggy on cold coal: it crumbles under the ball of your foot.
		speedMultiplier = 0.90,
		igniteAfter = 0.9,
		burnFor = 1.9,
		spreadAfter = 0.8,
		-- Low enough that one crossing burns patches, not the whole grill: sim_round3 measured 11 of 20
		-- coals at 0.4, and sometimes all of them.
		spreadChance = 0.22,
		stompBurn = 0.5,
		regrowAfter = 5.5,
		hotSpeed = 1.15,
		decayDuration = 10,
		sfxMinGap = 0.2,
		sfxEvent = "charcoalSnap",
		deformationAnim = "ember",
	},
	-- CHOCOLATE: the only material that changes STATE.
	--
	-- Its problem was always butter-wax, which is also a brittle surface over something
	-- soft, and melting is what separates them. Butter is soft from the start and stays
	-- soft; chocolate begins hard enough to snap and becomes something else entirely under
	-- you -- and the something else is SLIPPERIER than what it started as, so the longer
	-- you spend the less control you have. It is the only surface whose friction changes
	-- while you are standing on it.
	Chocolate = {
		category = "risk",
		frictionOverride = 0.30,
		-- BOTH TRIGGERS, and chocolate is the only material that genuinely wants both.
		--
		-- The clock was here first, on the reasoning that what melts chocolate is warmth
		-- over time. That is half true and it made the material read as a timer rather than
		-- as a substance: it looked identical on your first step and your last, and then
		-- gave way on a count you could not see.
		--
		-- Warmth also comes from CONTACT, and three steps is the temperature story -- each
		-- one leaves the bar a little further past tempered, and you can see it. So the
		-- clock stays (stand still and it goes) but the steps are what carry the read, and
		-- the clock is longer now so that dwelling is a real choice rather than the only
		-- way to fail.
		--
		-- FOUR, not three, and the reason is that the renderer has THREE stages of
		-- almost-melted to show. At three the last of them would land on the same step that
		-- collapses the cell, so the stage that says "the next one will not hold" would
		-- flash for a frame and then be gone -- a warning nobody could act on. Four steps
		-- means all three are seen with a step left to use them.
		stepsToCollapse = 4,
		-- 3.8 (was 5.0): every chunk that can drop you now gives way faster.
		dissolveTime = 3.8,
		decayDuration = 12,
		sfxMinGap = 0.2,
		sfxEvent = "chocolateSnap",
		deformationAnim = "melt",
	},
	-- CHOCOLATE, COLD. The same bar at the other end of the thermometer.
	--
	-- Melting chocolate and snapping chocolate are genuinely different materials to walk on
	-- and it would be a waste to only ship one. Warm, it goes soft and slippery and takes
	-- four steps of gradual give; cold, it is one of the most brittle things there is -- it
	-- holds completely, and then it does not, in two.
	--
	-- It SHARES the mesh and the textures with its warm twin on purpose, which is the
	-- opposite of the rule ice and butter follow. There the shared mesh was a problem
	-- because two different substances would have worn one crack pattern. Here it is the
	-- same substance at a different temperature, so looking identical at rest is correct --
	-- what tells them apart is that one of them is dripping and the other is not.
	ChocolateSolid = {
		category = "risk",
		-- TWO, the fewest of any material, tied with charcoal. Tempered chocolate has no
		-- give at all before it breaks: there is no soft stage to spend a step on.
		stepsToCollapse = 2,
		-- No dissolveTime, and no frictionOverride either. Both belong to the warm bar --
		-- cold chocolate neither melts under you nor slides you around, and giving it
		-- either would blur the one contrast the pair exists to draw.
		decayDuration = 11,
		sfxMinGap = 0.2,
		sfxEvent = "chocolateSnap",
		deformationAnim = "snap",
	},
	-- CLAY: the visitor book, and the only surface that moves itself somewhere else.
	--
	-- Sand also holds a print, and sand's prints die with the cell that carried them. Clay keeps
	-- every print for the session. What it was missing is the other half of pressing clay: what
	-- goes down comes up somewhere. A step sinks the cell and squeezes that clay toward the nearest
	-- side of the slab, so the middle of a trampled slab is a trench between ridges and its sides
	-- grow a LIP that curls out over the edge. A lip that takes three squeezes tears off and drops
	-- away with whoever is on it, and the next cell in is the edge.
	--
	-- Standing still keeps squeezing. The middle is safe to stand in; the edges are not, and
	-- trampling the middle pushes ridges out toward them. See DISPLACEMENT in DeformationService.
	Clay = {
		-- Documentation, as sand's is: the chunks stay in PACE slots, because a steady crossing
		-- down the middle is safe.
		category = "risk",
		speedMultiplier = 0.93,
		-- Thirty seconds, down from the whole session (600): ridges and squeezed cells flatten out
		-- again instead of holding the shape of the last crossing for good. See REGROW_DURATION.
		decayDuration = 30,
		displacement = "squeeze",
		-- A print bottoms out on the slab after three.
		displaceSteps = 3,
		displaceLimit = 3,
		-- Standing on the edge cell tears it in three seconds; standing with a foot either side of
		-- the edge line, in one and a half, because both feet are squeezing the same lip.
		creepEvery = 1.5,
		sfxMinGap = 0.2,
		sfxEvent = "claySquish",
		deformationAnim = "squeeze",
	},
	-- CLOUD: no steps, no warning, just a floor that is always leaving.
	--
	-- Ice is the material to stay away from and the separation is DISCRETENESS. Ice gives
	-- you three distinct chances and shows you the crack widening between them; cloud gives
	-- you no chances at all, because there is nothing to count. You sink from the moment
	-- you land and you keep sinking, so the only thing that saves you is not stopping.
	--
	-- No stepsToCollapse for that reason. The sink is continuous and the fall comes out of
	-- it rather than out of a threshold.
	Cloud = {
		category = "risk",
		-- Floaty. There is not enough under you to push against, which is the same fact the
		-- continuous sink expresses -- this just puts it in your legs as well as your eyes.
		speedMultiplier = 0.94,
		-- 1.15 (was 1.6): every chunk that can drop you now gives way faster.
		dissolveTime = 1.15,
		decayDuration = 7,
		sfxMinGap = 0.2,
		sfxEvent = "cloudHush",
		deformationAnim = "sink",
	},
	-- LAMB'S EAR: THE ONLY DRY SOFT THING IN THE GAME.
	--
	-- Every other surface here is wet, granular or brittle -- honey and slime and jello
	-- are wet, soap and sand are granular, butter and ice and bubble wrap break. Nothing
	-- was DRY AND SOFT, and that is the most touchable category there is: it is why
	-- sensory gardens plant this and why people cannot walk past it without reaching out.
	--
	-- It is also the quietest thing in the game, on purpose. The roster is pops, cracks
	-- and squelches; a surface that answers a footfall with almost nothing is a contrast
	-- the other eight cannot provide, and it makes the chunk after it louder for free.
	LambsEar = {
		category = "pace",
		-- BARELY SLOWER, and slower for a physical reason rather than a stickiness one:
		-- soft ground absorbs the push-off, so you get less back from each step. Not
		-- honey's 0.50 -- this is a surface you cross comfortably, and the pace it sets
		-- is a rest between risks rather than an obstacle.
		speedMultiplier = 0.94,
		-- LONG, because velvet holds a mark. Pressed nap does not spring back on its own
		-- the way a jelly does; it stays brushed until something disturbs it, and six
		-- seconds is long enough that a player crossing at a walk can look behind them
		-- and see the whole path they took. That trail IS the material.
		decayDuration = 6,
		sfxMinGap = 0.2,
		sfxEvent = "leafBrush",
		deformationAnim = "nap",
	},
	-- ICE: THE ONE CORNER OF THE GRID NOTHING OCCUPIED.
	--
	-- Butter-wax is slippery but safe. Kinetic sand grips but collapses. Ice is both --
	-- slippery AND breaking -- and that combination is the whole reason it earns a slot
	-- rather than being a butter reskin: you cannot stop to think, because you are still
	-- sliding while it fails under you.
	--
	-- Slipperier than butter by a wide margin (0.08 against 0.25). Butter's friction is a
	-- nuisance; ice's is the hazard.
	Ice = {
		category = "risk",
		frictionOverride = 0.08,
		-- THREE STEPS ON THE SAME SPOT, AND NOTHING ELSE BREAKS IT.
		--
		-- `dissolveTime` is gone deliberately. Sand and soap fail on a CLOCK as well as on
		-- contact -- stand still long enough and they give -- but ice should fail because
		-- you loaded it, not because you loitered. Standing on a frozen sheet is exactly
		-- what you are supposed to be able to do; it is the second and third impact in the
		-- same place that opens it. Leaving the timer in would also have made it break
		-- under a player who had stopped moving, which reads as the game killing you for
		-- nothing.
		stepsToCollapse = 3,
		-- Longer than sand's 7: a crazed sheet you have already crossed should still look
		-- crazed when you glance back at it from the next chunk.
		decayDuration = 9,
		sfxEvent = "iceCrack",
		sfxMinGap = 0.2,
		deformationAnim = "crack",
	},
	-- JELLO SODA: the material that gives energy BACK.
	--
	-- Honey takes speed away, butter takes grip away, slime throws you a fixed distance.
	-- None of them return what you put in. Jello does: it compresses under a step and
	-- bounces you on the rebound, so it is the only surface where the timing of your last
	-- landing changes your next jump. That is a rhythm, and nothing else here has one.
	--
	-- `microBounceHeight` is the field bubble wrap already uses, so this needed no new
	-- mechanism at all -- just a bigger number and a material that deserves it.
	JelloSoda = {
		category = "pace",
		-- Barely slowed. The wobble does the work; a speed penalty on top would make it
		-- feel like honey with a bounce.
		speedMultiplier = 0.88,
		microBounceHeight = 3,
		-- SHORT. A jelly that held its dent would be a set jelly, which is a different
		-- dessert and a much duller platform.
		decayDuration = 3,
		sfxEvent = "jelloWobble",
		sfxMinGap = 0.2,
		deformationAnim = "wobble",
	},
	-- JELLYFISH: the Sunken City's own material, a bell floating level with the route.
	--
	-- Every other surface on that route is from the kit; this is the one that belongs to the
	-- sea. It throws you up on EVERY landing, not on the first step the way slime does -- a
	-- bell is a spring you keep landing on -- so crossing one is a run of bounces, and
	-- crossing from one bell to the next is timing the last of them. Five studs up is a
	-- jump's height: enough to clear a GAP_LENGTH gap from the bell's edge at a walk, and
	-- not so much that the bounce stops being yours to steer. The cooldown lets a landing
	-- finish before the next throw, so it bounces rather than buzzes.
	--
	-- PACE, because nothing about a bell drops you. The risk is the gap between two bells
	-- (R39_JellyfishHop), which is the chunk's, not the material's.
	Jellyfish = {
		category = "pace",
		speedMultiplier = 0.94,
		microBounceHeight = 5,
		bounceCooldown = 0.45,
		decayDuration = 3,
		sfxEvent = "slimeBoing",
		sfxMinGap = 0.25,
		deformationAnim = "wobble",
	},
	-- NEEDOH: dough in a skin, which is neither of the two soft things already here.
	--
	-- Jello is water held in a lattice -- it wobbles, it springs back in a moment, and it
	-- barely slows you. Slime is a fluid pretending to be a solid. A Needoh is a sealed bag
	-- of dough: it takes the shape you press into it, holds it noticeably longer than jello
	-- does, and pushes back with almost no spring at all.
	--
	-- Those three numbers below are the whole difference and they are all deliberate:
	-- slower than jello because dough resists a stride rather than yielding to it, a
	-- decay five seconds rather than three because the dent visibly lingers, and a bounce
	-- of 2 rather than 3 because it does not throw you.
	-- A STICK OF BUTTER, and deliberately not ButterWax.
	--
	-- ButterWax is butter under a wax shell, and the shell is the mechanic: it cracks in
	-- plates and what is under it is only revealed by breaking it. An unwrapped stick has no
	-- shell to break, so sharing that entry would have given this one a coating it does not
	-- have. What is left when you take the shell away is the softest surface in the game --
	-- butter at room temperature offers almost no resistance at all.
	--
	-- Hence the slowest speed of any pace material here and the longest decay: you sink in,
	-- and the dent is still there when you look back at it.
	-- MOLTEN KEYCAPS: lava's behaviour on a keyboard's body.
	--
	-- The lava keyboard has been a TINT on CreamyKeyboard -- dark keys with the free model's
	-- texture over them -- which is a paint job, not a material. It looked like lava and
	-- behaved exactly like the cream keyboard next to it.
	--
	-- What it borrows from Lava is the HEAT: a key glows where you stood and cools back over
	-- a couple of seconds, so a crossing leaves a trail that fades behind you. What it does
	-- NOT borrow is the danger. Real lava here is a risk material that gives way; these are
	-- keycaps on a solid chassis, so they are pace -- and the point of the chunk is that
	-- something that looks lethal turns out to be the softest thing in the level.
	--
	-- Slower than the cream keyboard because a molten key gives further before it bottoms
	-- out, and the decay is long so the glow outlasts the footstep that made it.
	LavaKeys = {
		category = "pace",
		speedMultiplier = 0.88,
		microBounceHeight = 1,
		decayDuration = 8,
		-- Both sounds are right and only one can play, so: the thock, because that is what
		-- your foot is doing. The crust is what the surface is doing afterwards, and the
		-- glow says that better than a second sample would.
		sfxEvent = "keyThock",
		sfxMinGap = 0.18,
		deformationAnim = "compress",
	},
	ButterStick = {
		category = "pace",
		speedMultiplier = 0.84,
		microBounceHeight = 1,
		decayDuration = 9,
		sfxEvent = "butterWaxCrack",
		sfxMinGap = 0.24,
		deformationAnim = "press",
	},
	-- THE NEEDOH SQUEEZE, and the mini jumps are gone.
	--
	-- The bed used to throw you up a couple of studs on its own every second and a half while you
	-- walked on it -- reported twice, first as too frequent and then still as not Needoh-like. A
	-- Needoh does not throw anything. It GIVES, slowly, for as long as you squeeze it, and it only
	-- pushes back when you let go.
	--
	-- So: walk across it and it is soft underfoot and nothing else. STAND STILL and the dough goes
	-- on sinking under you, deeper and deeper, with the bed swelling up around the hollow; at full
	-- squeeze it shivers and glows. JUMP out of the hollow and the dough gives the push back:
	-- your jump is up to `chargeJump` times its normal height. The jump is always yours.
	Needoh = {
		category = "pace",
		speedMultiplier = 0.90,
		chargeAfter = 0.25,
		chargeTime = 1.1,
		chargeJump = 2.2,
		decayDuration = 5,
		-- Borrowed from clay, and the right borrow: both are a dense soft mass taking a
		-- print. Jello's wobble would be wrong here -- there is nothing in a Needoh that
		-- rings, which is exactly what separates it from the platform it used to sit on.
		sfxEvent = "claySquish",
		sfxMinGap = 0.2,
		deformationAnim = "compress",
	},
	BubbleWrap = {
		category = "risk",
		popCount = 4,
		microBounceHeight = 4,
		decayDuration = 7,
		-- HALVED, and bubble wrap is the one material that wants it. Every other surface
		-- uses 0.2 to stop a single stride firing three copies of one sample, but
		-- overlapping crackle is the entire appeal here -- a sheet of bubble wrap popping
		-- one bubble at a time is not what anybody is picturing. At 0.1 it can pop about
		-- ten times a second, which is roughly what hands do to it.
		sfxMinGap = 0.1,
		sfxEvent = "bubblePop",
		deformationAnim = "pop",
	},
}

local Constants = {
	DEFAULT_FRICTION = 0.5,   -- Roblox default (Plastic)
	DEFAULT_WALKSPEED = 16,   -- Roblox default Humanoid.WalkSpeed
	GRAVITY = 196.2,          -- studs/s^2
	AUDIO_MAX_POLYPHONY = 4,
	SUBREGION_CELL_SIZE = 2.5,
	DECAY_DURATION = 7,
	-- NOTHING STAYS BROKEN LONGER THAN THIS. Every cell that gives way -- a torn clay lip, a
	-- crumbled soap cell, a coal gone to ash -- comes back this many seconds later, and no
	-- material holds its dents for longer either (DeformationService caps decayDuration by it).
	--
	-- A level used to be able to strand you: a clay lip tears off at the one place a jump needs
	-- it, that hole is permanent for the rest of the run, and the only way on is to restart the
	-- level -- a punishment for playing with the material the level is made of. Thirty seconds is
	-- long enough that a hole is a real obstacle to route around, and short enough that waiting
	-- is never worse than restarting.
	--
	-- Materials with their own FASTER return keep it: charcoal regrows at `regrowAfter` (5.5 s),
	-- oobleck fills in at `healAfter` (3.5 s), bubble wrap re-inflates on its decay timer.
	REGROW_DURATION = 30,
}

return {
	Materials = Materials,
	Constants = Constants,
}
