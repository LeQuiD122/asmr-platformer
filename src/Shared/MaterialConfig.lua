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
		dissolveTime = 3.0,
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
		dissolveTime = 2.5,
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
	-- SALT: the only surface that gets BETTER as you wreck it.
	--
	-- Everything else here degrades under use -- it cracks, melts, crumbles or gives way.
	-- Salt compacts. Each step crushes the crystals under it into a denser, flatter, harder
	-- patch, and that patch is easier to cross than the loose stuff around it. It never
	-- fails, so the reward for working it is permanent within a run.
	--
	-- That inverts the game's whole bargain: on every other risk material the second visit
	-- is worse than the first, and here it is better. The trodden path a player leaves is
	-- also a route for the next one, which nothing else in the game does.
	Salt = {
		category = "pace",
		-- Loose crystals roll under you. This is the starting figure; the renderer takes it
		-- back toward 1 as a cell compacts, which is the whole mechanic.
		speedMultiplier = 0.88,
		-- LONG. The path has to outlast the crossing or there is no point making it.
		decayDuration = 25,
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
	-- NON-NEWTONIAN: solid if you are quick, liquid if you are not.
	--
	-- Shear-thickening is the one real-world material property that is already a platformer
	-- mechanic, and it needs no translation at all: run and it holds you, hesitate and you
	-- go through. `dissolveTime` is doing exactly what it says here -- a clock that only
	-- runs while you are in continuous contact -- which is the mechanic verbatim.
	--
	-- NOT the cloud. Cloud sinks from the moment you land and nothing stops it; oobleck is
	-- completely solid until you stop moving, so one punishes lingering and the other
	-- punishes existing. The distinction is the whole reason both can be in the game.
	Oobleck = {
		category = "risk",
		-- Under a second and a half of standing still. Long enough to cross at a walk,
		-- short enough that stopping to line up a jump is a real decision.
		dissolveTime = 1.4,
		decayDuration = 5,
		sfxMinGap = 0.2,
		sfxEvent = "ooblSquelch",
		deformationAnim = "shear",
	},
	-- CLICKY BUTTONS: the only surface that gives energy BACK.
	--
	-- The keyboard depresses and returns; the switches latch. A button does neither -- it
	-- bottoms out hard and then throws you off it, because that is what a spring under a cap
	-- is for. It is the third material in a family that had two, and it is the only one of
	-- the three you would ever choose to walk on for the movement rather than the sound.
	Buttons = {
		category = "pace",
		speedMultiplier = 1.0,
		-- NO microBounceHeight, and its absence is deliberate. It was 6, on the reasoning
		-- that a spring under a cap should give something back -- but a platform that throws
		-- you upward on every step is a trampoline, and it made the chunk impossible to
		-- cross with any control. The spring is in the CAP, which travels and returns; the
		-- player it is under stays exactly where they put themselves.
		decayDuration = 2,
		sfxMinGap = 0.12,
		sfxEvent = "buttonClick",
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
		dissolveTime = 7.0,
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
	-- CHARCOAL: snaps rather than crumbles.
	--
	-- Sand is the material this has to stay away from, and the separation is in HOW it
	-- fails. Sand loses cohesion: it is worked loose over three steps and slumps. Charcoal
	-- is brittle in the way glass is brittle -- it holds completely, then breaks all at once
	-- into angular pieces. Two steps, not three, and the second is the last.
	Charcoal = {
		category = "risk",
		-- Draggy and loose. Charcoal crumbles under the ball of your foot, so you get less
		-- back from every push-off -- the same reasoning as foam, arrived at from the
		-- opposite direction: one is too soft to push against and one keeps breaking.
		speedMultiplier = 0.90,
		stepsToCollapse = 2,
		decayDuration = 10,
		sfxMinGap = 0.2,
		sfxEvent = "charcoalSnap",
		deformationAnim = "snap",
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
		dissolveTime = 5.0,
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
	-- CLAY: the visitor book.
	--
	-- Sand also holds a print, and sand's prints die with the cell that carried them -- it
	-- is a risk material and it collapses. Clay never fails, so its prints have nothing to
	-- interrupt them, and the decay is set past the length of a run on purpose: by the end
	-- of a session a clay chunk is covered in every route every player took across it.
	-- That is a record the level keeps of the people who walked it, and nothing else here
	-- does anything like it.
	Clay = {
		category = "pace",
		speedMultiplier = 0.93,
		decayDuration = 600,
		sfxMinGap = 0.2,
		sfxEvent = "claySquish",
		deformationAnim = "imprint",
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
		dissolveTime = 1.6,
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
	Needoh = {
		category = "pace",
		speedMultiplier = 0.90,
		microBounceHeight = 2,
		-- FAR RARER THAN THE SHARED 0.35s. A NeeDoh is dough: it gives, and what it gives
		-- back it gives back slowly. At the default cadence a normal walking pace clears the
		-- cooldown on nearly every stride, so the surface launched you continuously and the
		-- chunk turned into a trampoline -- which is bubble wrap's job, not this one.
		--
		-- At 1.4s a bounce is an occasional punctuation rather than a gait.
		bounceCooldown = 1.4,
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
}

return {
	Materials = Materials,
	Constants = Constants,
}
