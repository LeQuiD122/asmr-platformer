--!strict
-- ReplicatedStorage/Shared/SoundAudition.lua
-- STUDIO ONLY: THE SOUND AUDITION (the two-hundred-and-fifteenth pass, from your note of 2026-11-14: "find better sounds
-- for the sounds section of the shop, the chunks like needoh, soda, slime and sand to see if there could be better
-- alternatives"). For each, what plays NOW (its events, through AudioService, as the game plays them) and a few free
-- Creator Store sounds to TRY beside it, each measured in Studio on 2026-11-14 (loaded, and its length). Nothing here
-- plays in a run or the shop: the test panel (F8) lists them, you press to hear, and press the heart on the ones you like.
-- Then I swap in the ones you chose; nothing changes until you have.
local SoundAudition = {}

export type Try = { id: string, name: string, length: number }
export type Slot = { slot: string, what: string, now: { string }, volume: number, try: { Try } }

SoundAudition.SLOTS = {
	{ slot = "Needoh", what = "the Needoh chunk", now = { "needohSquish" }, volume = 0.6, try = {
		{ id = "115505091338053", name = "Plush squish", length = 0.57 },
		{ id = "135374150434314", name = "Needoh squish", length = 0.55 },
		{ id = "114553569477108", name = "Needoh audio", length = 0.75 },
		{ id = "87447839536470", name = "Needoh sfx", length = 0.40 },
		{ id = "97586267210246", name = "Squish press A", length = 1.23 },
		{ id = "113074783164255", name = "Squish press B", length = 0.68 },
	} },
	{ slot = "Soda", what = "the jello soda chunk", now = { "jelloWobble" }, volume = 0.5, try = {
		{ id = "140099098215408", name = "Fizz A", length = 1.60 },
		{ id = "80378394973147", name = "Fizz B", length = 1.25 },
		{ id = "121615499393539", name = "Fizz C", length = 1.25 },
		{ id = "103110459733446", name = "Fizzle", length = 1.14 },
		{ id = "139585167823988", name = "Jelly wobble", length = 1.45 },
		{ id = "127329232364922", name = "Jelly slime", length = 0.16 },
	} },
	{ slot = "Slime", what = "the slime chunk", now = { "slimeBoing" }, volume = 0.6, try = {
		{ id = "87295773843957", name = "Slime squishy A", length = 0.48 },
		{ id = "128710847750782", name = "Slime squishy B", length = 0.46 },
		{ id = "137866583821455", name = "Goop slime", length = 1.58 },
		{ id = "124672564748126", name = "Slime satisfying", length = 0.32 },
		{ id = "76169806288463", name = "Slime press", length = 1.14 },
		{ id = "71972357334329", name = "Gloopy splat", length = 1.02 },
		{ id = "94238955194144", name = "Wet squelch", length = 1.87 },
	} },
	{ slot = "Sand", what = "the kinetic sand chunk", now = { "kineticSandImprint" }, volume = 0.6, try = {
		{ id = "138299332040168", name = "Sand step A", length = 1.07 },
		{ id = "116763433481680", name = "Sand step B", length = 0.55 },
		{ id = "109565823661998", name = "Sand walk A", length = 0.42 },
		{ id = "114947896895754", name = "Sand walk B", length = 0.45 },
		{ id = "98912102275037", name = "Sand footstep", length = 0.50 },
		{ id = "9118770616", name = "Sand silt", length = 1.97 },
	} },
	{ slot = "Crunchy", what = "the shop's Crunchy steps", now = { "saltCrunch", "snowPack" }, volume = 0.45, try = {
		{ id = "6540859678", name = "Snow step", length = 0.86 },
		{ id = "72043022297629", name = "Snow step B", length = 1.04 },
		{ id = "18643816569", name = "Wet snow", length = 0.64 },
		{ id = "116255275290794", name = "Crunchy wax", length = 3.38 },
		{ id = "76787741706449", name = "Crunch", length = 0.30 },
	} },
	{ slot = "Gloopy", what = "the shop's Gloopy steps", now = { "honeySquish", "needohSquish", "slimeBoing" }, volume = 0.45, try = {
		{ id = "86049114778636", name = "Honey squish A", length = 1.00 },
		{ id = "85976439630659", name = "Honey squish B", length = 1.00 },
		{ id = "85028780654050", name = "Honey ASMR A", length = 1.00 },
		{ id = "104911785188405", name = "Honey ASMR B", length = 1.00 },
	} },
	{ slot = "Poppy", what = "the shop's Poppy steps", now = { "bubblePop" }, volume = 0.4, try = {
		{ id = "7158013361", name = "Bubble wrap pops", length = 3.07 },
		{ id = "9114234244", name = "Bubble wrap twist", length = 1.30 },
		{ id = "9125745707", name = "Bubble wrap rustle", length = 1.28 },
	} },
	{ slot = "Velvet", what = "the shop's Velvet steps", now = { "leafBrush", "cloudHush" }, volume = 0.6, try = {
		{ id = "72429645813951", name = "Fabric rustle", length = 1.05 },
		{ id = "6636232274", name = "Fabric rustle B", length = 1.20 },
		{ id = "9113593812", name = "Hair brush A", length = 0.71 },
		{ id = "9113594075", name = "Hair brush B", length = 0.68 },
		{ id = "9125408271", name = "Brush on cushion", length = 1.53 },
		{ id = "121238985608899", name = "Clothes", length = 0.57 },
	} },
	{ slot = "Thock", what = "the shop's Thock steps", now = { "keyThock" }, volume = 0.45, try = {
		{ id = "113108830240353", name = "Cream keyboard", length = 0.21 },
		{ id = "102855535543930", name = "Creamy keyboard", length = 0.18 },
		{ id = "88073348503000", name = "Thocky keyboard", length = 1.32 },
		{ id = "84720992459612", name = "Creamy ASMR", length = 0.94 },
		{ id = "72826565018765", name = "Keyboard ASMR", length = 0.15 },
	} },
} :: { Slot }

SoundAudition.STAMP = "9dc92c15"
return SoundAudition
