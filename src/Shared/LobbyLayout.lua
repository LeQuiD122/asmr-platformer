--!strict
-- ReplicatedStorage/Shared/LobbyLayout.lua
-- THE LOBBY AS A PROMENADE (the hundredth pass, from your notes: "expand the lobby, since it gets way too cluttered",
-- and you chose the promenade with zones). It was one deck, 110 by 96, with everything on it: the level pads, the
-- keys, the start pad, the shop, the chest, the boards, the post box, the statue, the leaderboard, the pool, the
-- benches, the viewer, the lift and the back corridor, each squeezed into the gap the last one left.
--
-- Now a promenade on piers over the sea: a PLAZA in the middle (you arrive there, by the fountain, among benches,
-- under the canopy), and round it four places of their own, each down a wide boardwalk:
--   the LEVEL GATES (north)   the level pads in an arc round the start, the length and mode keys on the way in
--   the HALL OF FAME (east)   the leaderboard facing the way in, your statue and its pose keys
--   the ARCADE (west)         the shop's kiosk facing the way in, the daily chest, the two boards, the post box, and
--                             a small closed house in the corner with a yellow light in its doorway
--   the GARDEN (south)        a lawn, benches facing the sea, planters, the seaside viewer, the lift to the squish room
--
-- EVERY PLACE IS HERE, from the lobby's origin, and only here: HubService builds from it, SquishRoomService puts its
-- lift by it, blender/plan_lobby.py draws it and blender/check_hub.py checks that nothing crowds anything, that
-- everything stands inside a deck's inlay and that every way in is clear. Every deck and walk stands on its own piers
-- down to the sea.

local LobbyLayout = {}

LobbyLayout.ORIGIN = Vector3.new(0, 200, -600)
LobbyLayout.SEA_DROP = 190 -- studs from the deck down to the water, the piers' height

-- THE DECKS: each a platform of its own, its centre (x, z) from the origin and its size; the inlay, the line it
-- draws round itself, is MARGIN in from its edge, and nothing may stand past it.
LobbyLayout.MARGIN = 5
LobbyLayout.DECKS = {
	plaza = { x = 0, z = 0, w = 84, d = 84 },
	gates = { x = 0, z = -122, w = 108, d = 76 },
	fame = { x = 104, z = 0, w = 56, d = 76 },
	arcade = { x = -104, z = 0, w = 56, d = 76 },
	garden = { x = 0, z = 106, w = 96, d = 48 },
}

-- THE WALKS: a boardwalk from the plaza to each place, as wide as `width`, edge to edge, railed both sides.
LobbyLayout.WALKS = {
	{ to = "gates", width = 24 },
	{ to = "fame", width = 20 },
	{ to = "arcade", width = 20 },
	{ to = "garden", width = 20 },
}

-- WHERE EACH THING STANDS, from the origin (on the deck at y = 1 unless it says).
LobbyLayout.AT = {
	-- THE PLAZA
	spawn = Vector3.new(0, 1.5, -22), -- facing the gates up the walk
	pool = Vector3.new(0, 1, 12), -- the pool and the fountain in it
	-- THE LEVEL GATES: the start in the middle of the arc of pads, so the last thing you do is step into it; the length
	-- and mode keys across the way in, so you walk over them on the way.
	start = Vector3.new(0, 1.8, -118),
	modeRow = Vector3.new(0, 0, -104),
	lengthRow = Vector3.new(0, 0, -94),
	-- THE HALL OF FAME
	board = Vector3.new(124, 8, 0), -- the leaderboard on the far side, facing the way in (-X)
	statue = Vector3.new(104, 3.5, -22), -- facing its keys (+Z)
	poseRow = Vector3.new(104, 1.5, -14), -- the pose keys' middle, a row along x in front of the statue
	-- THE ARCADE
	kiosk = Vector3.new(-120, 1, 0), -- on the far side, facing the way in (+X)
	chest = Vector3.new(-92, 1, -22),
	challenges = Vector3.new(-114, 1, -26),
	materials = Vector3.new(-102, 1, -27),
	postBox = Vector3.new(-92, 1, 22),
	backDoor = Vector3.new(-112, 1, 18), -- the doorway, facing +X; its house and the corridor in it run back west
	-- THE GARDEN
	viewer = Vector3.new(40, 1, 106), -- the telescope, looking out east over the rail
	lift = Vector3.new(-38, 1, 104), -- the squish room's lift, its door toward the garden (+X)
}

-- THE LEVEL PADS: round the start, on an arc `radius` from it, `spread` degrees across, facing it.
LobbyLayout.ARC = { radius = 30, spread = 150 }

-- THE BENCHES (x, z, facing in radians: a sitter faces (sin, 0, cos) of it) and the planters (x, z).
LobbyLayout.BENCHES = {
	{ x = -22, z = 12, facing = math.pi / 2 }, -- either side of the pool, facing it
	{ x = 22, z = 12, facing = -math.pi / 2 },
	{ x = -10, z = 28, facing = math.pi }, -- across its far end, clear of the way onto the garden's walk
	{ x = 10, z = 28, facing = math.pi },
	{ x = -26, z = 118, facing = 0 }, -- the garden's, facing the sea
	{ x = -8, z = 118, facing = 0 },
	{ x = 10, z = 118, facing = 0 },
	{ x = 26, z = 118, facing = 0 },
}
LobbyLayout.PLANTERS = {
	{ x = -32, z = -32 }, { x = 32, z = -32 }, { x = -32, z = 32 }, { x = 32, z = 32 },
	{ x = -38, z = 92 }, { x = 38, z = 92 }, { x = -20, z = 96 }, { x = 20, z = 96 },
	{ x = 120, z = 28 }, { x = -86, z = 28 },
}

-- THE LAMP POSTS (x, z), each a real light: the plaza has its columns' lamps and the canopy's lanterns, and every
-- other place has these. The last four stand on the walks, one each, at the side.
LobbyLayout.LAMPS = {
	{ x = -46, z = -94 }, { x = 46, z = -94 }, { x = -46, z = -150 }, { x = 46, z = -150 },
	{ x = 84, z = -16 }, { x = 84, z = 16 },
	{ x = -84, z = -16 }, { x = -84, z = 16 },
	{ x = -24, z = 104 }, { x = 24, z = 104 },
	{ x = 10.5, z = -63 }, { x = 59, z = -8.5 }, { x = -59, z = 8.5 }, { x = -8.5, z = 62 },
}

-- A deck's centre, from the origin.
function LobbyLayout.centre(name: string): Vector3
	local deck = (LobbyLayout.DECKS :: any)[name]
	return Vector3.new(deck.x, 0, deck.z)
end

-- The level pads' places (from the origin) and the way each faces (toward the start), for `count` pads.
function LobbyLayout.arc(count: number): { CFrame }
	local out = {}
	local start = LobbyLayout.AT.start
	local half = math.rad(LobbyLayout.ARC.spread) / 2
	for index = 1, count do
		local t = if count > 1 then (index - 1) / (count - 1) else 0.5
		local angle = -half + 2 * half * t
		local at = Vector3.new(start.X + math.sin(angle) * LobbyLayout.ARC.radius, 1.7,
			start.Z - math.cos(angle) * LobbyLayout.ARC.radius)
		table.insert(out, CFrame.lookAt(at, Vector3.new(start.X, 1.7, start.Z)))
	end
	return out
end

-- THE WALK from the plaza to `to`: its centre, its length (along the way) and its width, and whether it runs along X.
function LobbyLayout.walk(to: string): (Vector3, number, number, boolean)
	local plaza, deck = LobbyLayout.DECKS.plaza, (LobbyLayout.DECKS :: any)[to]
	local width = 20
	for _, w in ipairs(LobbyLayout.WALKS) do
		if w.to == to then
			width = w.width
		end
	end
	if deck.x ~= plaza.x then
		-- East or west: from the plaza's side to the deck's.
		local sign = if deck.x > plaza.x then 1 else -1
		local a = plaza.x + sign * plaza.w / 2
		local b = deck.x - sign * deck.w / 2
		return Vector3.new((a + b) / 2, 0, deck.z), math.abs(b - a), width, true
	end
	local sign = if deck.z > plaza.z then 1 else -1
	local a = plaza.z + sign * plaza.d / 2
	local b = deck.z - sign * deck.d / 2
	return Vector3.new(deck.x, 0, (a + b) / 2), math.abs(b - a), width, false
end

-- WHETHER A POINT (from the origin) IS OVER THE LOBBY: over a deck or a walk, give or take `slack` studs. Who is in
-- the room (HubService) is who is over it, not who is near its middle: the gates are 120 studs from the plaza.
function LobbyLayout.over(offset: Vector3, slack: number): boolean
	for _, deck in pairs(LobbyLayout.DECKS) do
		if math.abs(offset.X - deck.x) <= deck.w / 2 + slack and math.abs(offset.Z - deck.z) <= deck.d / 2 + slack then
			return true
		end
	end
	for _, w in ipairs(LobbyLayout.WALKS) do
		local centre, length, width, alongX = LobbyLayout.walk(w.to)
		local halfX = if alongX then length / 2 else width / 2
		local halfZ = if alongX then width / 2 else length / 2
		if math.abs(offset.X - centre.X) <= halfX + slack and math.abs(offset.Z - centre.Z) <= halfZ + slack then
			return true
		end
	end
	return false
end

LobbyLayout.STAMP = "fa28ae08"
return LobbyLayout
