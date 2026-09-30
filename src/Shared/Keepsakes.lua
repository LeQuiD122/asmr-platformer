--!strict
-- ReplicatedStorage/Shared/Keepsakes.lua
-- WHAT EVERY PLATFORM IS. The one piece of the story that belongs to this game and no other: in the
-- Hold, the tide does not carry things away, it KEEPS them, and everything somebody in Harrow Bay was
-- holding, pressing, squeezing or fidgeting with when the water came was kept and grown into the
-- stepping stones the levels are made of. That is why every surface wants to be pressed: it was being
-- pressed when the day stopped. It remembers your weight for a while (the dents, the footprints, the
-- cracks) and then forgets it, because the day always comes round again (LORE.md, "The Hold").
--
-- One entry per material in MaterialConfig: what it was, where it came from, and one line about who
-- was holding it. Each is also a THING in the levels now: StoryService leaves a few in the nooks off
-- the route (Interactables.keepsake builds it, in the material's own colour), and picking one up puts
-- this entry in your journal (JournalService). check_story holds every material to having one, and
-- every line to having no dashes.
--
--   thing   what it was, as the town would say it
--   from    where in Harrow Bay it came from
--   line    one line, the story of it; read in about five seconds

export type Keepsake = { thing: string, from: string, line: string }

local Keepsakes: { [string]: Keepsake } = {
	Honey = {
		thing = "A jar of Hale's honey",
		from = "the hives on the Novelty Works roof",
		line = "Sal dropped it on the Front steps at twelve minutes past nine. It has been running down them ever since.",
	},
	ButterWax = {
		thing = "A church candle",
		from = "St Brigid's, on the hill",
		line = "Lit for the fishermen every August. Butter yellow under the wax, and it still gives when you lean on it.",
	},
	ButterStick = {
		thing = "The dairy cart's butter",
		from = "the Front, delivered at eight",
		line = "For the ices. Sal never got round to it. It still takes the shape of whoever stands on it.",
	},
	KineticSand = {
		thing = "Pip's sandcastle sand",
		from = "the bucket by the pier",
		line = "It keeps your footprint for a while, the way Pip keeps her dad's place on the beach.",
	},
	Slime = {
		thing = "Novelty Works slime",
		from = "the Works on Mill Lane",
		line = "The green batch, for the Christmas order. It was never shipped. It will throw you if you let it.",
	},
	Needoh = {
		thing = "A squeeze toy",
		from = "the Works on Mill Lane",
		line = "Made to be squeezed when you are worried. Half the town bought one the week the tide came in.",
	},
	BubbleWrap = {
		thing = "Dev's parcel",
		from = "the post office queue",
		line = "Wrapped at nine to send to his sister. He never got to the front of the queue. Every bubble is a minute he waited.",
	},
	Soap = {
		thing = "A bar from the Corporation Baths",
		from = "Mrs Venn's cupboard",
		line = "She cut it into blocks every morning. It still crumbles the way it did at fourteen minutes past nine.",
	},
	CreamyKeyboard = {
		thing = "The waterworks teleprinter",
		from = "the Control Room",
		line = "The last thing it typed was KEY HOLDER PLEASE CONFIRM. Nobody did.",
	},
	Buttons = {
		thing = "The pump panel",
		from = "the Control Room",
		line = "Every pump in the bay has a button here. Pressing them does nothing without the key.",
	},
	LightSwitch = {
		thing = "The station switchboard",
		from = "the Control Room",
		line = "Mr Barlow put every light on at midnight on the eleventh, so the key holder could find the way in.",
	},
	Charcoal = {
		thing = "Coal from the bunkers",
		from = "the Engine House",
		line = "Enough to run the pumps for a year. They only ever needed the key.",
	},
	Lava = {
		thing = "Clinker from the boiler",
		from = "the Engine House",
		line = "Mr Barlow banked the fires on the eleventh. They never quite went out.",
	},
	LavaKeys = {
		thing = "The boiler's gauge keys",
		from = "the Engine House",
		line = "Too hot to touch. Mr Barlow touched them anyway, every hour, in case.",
	},
	Salt = {
		thing = "Salt from the harbour pans",
		from = "the flats past the pier",
		line = "Left behind the last time the tide went out. It has not gone out since.",
	},
	Oobleck = {
		thing = "Harbour mud",
		from = "under the pier",
		line = "Stand still and it takes you. Run and it holds you up. The fishermen knew that before the town did.",
	},
	Ice = {
		thing = "The fishmonger's ice",
		from = "Quay Street",
		line = "Laid on the slab at dawn on the fourteenth. The fish went back to the sea. The ice stayed.",
	},
	Snow = {
		thing = "Ice House snow",
		from = "the Ice House on Quay Street",
		line = "Packed in August for the fish. It squeaks the way it did under Sal's boots.",
	},
	Lego = {
		thing = "The toy shop window",
		from = "Marlow's Toys, High Street",
		line = "Pip wanted the red set. Tobi said after the weekend.",
	},
	Chocolate = {
		thing = "A bar from Marlow's",
		from = "the sweet shop on the High Street",
		line = "Dev bought it for the party. It goes a little softer every time the day comes round.",
	},
	ChocolateSolid = {
		thing = "A slab from Marlow's cellar",
		from = "under the sweet shop",
		line = "Still cold. It snaps clean, the way it did in the first hour of the first day.",
	},
	Clay = {
		thing = "Harrow brick clay",
		from = "the Brickworks",
		line = "Every wall in the waterworks was pressed from it in 1911. It remembers hands.",
	},
	Foam = {
		thing = "A Promenade Hotel mattress",
		from = "Room 14",
		line = "Somebody slept badly on it the night before. It still has the shape of them.",
	},
	Cloud = {
		thing = "Steam from the hotel laundry",
		from = "the Promenade Hotel roof",
		line = "The party's towels are still drying. They will be drying for a very long time.",
	},
	JelloSoda = {
		thing = "The rooftop bar's soda jelly",
		from = "Dev's bar at the Sky Pools",
		line = "Made for the party on the eleventh. It is still fizzing.",
	},
	LambsEar = {
		thing = "The Corporation Gardens",
		from = "the bed by the bandstand",
		line = "Mrs Okafor planted it because Pip liked to stroke the leaves on the way to school.",
	},
	Jellyfish = {
		thing = "The aquarium's jellyfish",
		from = "the tunnel tank",
		line = "They got out when the glass went. They light up when you land on them, as if they want to be seen.",
	},
}

return Keepsakes
