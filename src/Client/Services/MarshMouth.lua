--!strict
-- StarterPlayerScripts/Services/MarshMouth.lua
-- HIS OWN MOUTH (the two-hundred-and-twenty-seventh pass, 2026-11-20, from your question: "idk if i like that the head
-- itself is one object which doesnt separate, do you think having his mouth actually open instead of just having
-- another fake one underneath would be better?"). It would, and now it does. Marsh's made head (Assets/Props.Marsh_Head)
-- is one mesh; at the catch the whole of it used to tip up like a lid onto a second mouth built under it. Now it is cut
-- in two, once, on this screen, along a plane through his lips that rises toward his ears: his skull above, his own
-- jaw below (his chin, his lower lip), and each cut face filled with flesh, a palate above and the floor of his mouth
-- below. His jaw hinges under his ears, so it is his face that opens, not a lid lifting off one.
--
-- Built from the mesh itself (EditableMesh): the head's own triangles clipped against the plane, those across it cut
-- where they cross (their texture and their shading carried across the cut), and the two caps fanned from the middle
-- of the cut. Done once, a third of a second, in the background as the game starts; StoryClient (his face at the
-- catch) and StalkerClient (his jaw as he walks, rushes and holds you) clone the pieces. If the mesh cannot be read
-- (`ready` stays false), both keep what they did before: the lid over a mouth.
--
-- Everything here is in the made head's own mesh space (its MeshSize: about 1.7 by 2 by 1.75 studs, its face to -Z);
-- whoever uses a piece scales it by the head's Size over its MeshSize and places it at the head's centre.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MarshMouth = {}

-- THE CUT: through his lips (found from the mesh's profile: the nose at y -0.2, the lips at -0.42, the chin at -1),
-- rising toward the back at SLOPE so it passes under his ears and not through them.
MarshMouth.SLOPE = 0.12
MarshMouth.LIPS = Vector3.new(0, -0.42, -0.8)
MarshMouth.NORMAL = Vector3.new(0, 1, -MarshMouth.SLOPE).Unit
-- His jaw's hinge, under his ears, on the cut.
MarshMouth.HINGE = Vector3.new(0, -0.42 + MarshMouth.SLOPE * 0.95, 0.15)

-- HIS EYES (the two-hundred-and-twenty-eighth pass, from "make his eyes open when he spots you"): the made head's eyes
-- are sculpted shut. Each closed lid (the skull's triangles inside an ellipse over it, found by marking them on the
-- mesh) is cut out of the skull as a piece of its own, hinged along its top edge; behind it, a dark socket and an
-- eyeball. Opening, the lid swings up and back into his head and the eye is there, staring.
MarshMouth.EYES = { Vector3.new(-0.31, 0.165, -0.58), Vector3.new(0.31, 0.165, -0.58) }
MarshMouth.EYE_SIZE = Vector2.new(0.14, 0.072) -- the ellipse's half width and half height
type Pieces = { skull: MeshPart, jaw: MeshPart, palate: MeshPart?, floor: MeshPart?, lids: { MeshPart }, rim: { Vector3 },
	middle: Vector3, meshSize: Vector3, colour: Color3 }
local pieces: Pieces? = nil
local tried = false

local function templateOf(): MeshPart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = assets and assets:FindFirstChild("Props")
	local made = props and props:FindFirstChild("Marsh_Head")
	local part = made and (if made:IsA("MeshPart") then made else made:FindFirstChildWhichIsA("MeshPart", true))
	return if part and part:IsA("MeshPart") then part else nil
end

type Point = { p: Vector3, uv: Vector2, n: Vector3, key: string?, d: number }

-- ONE CUT AT A TIME: each needs its source mesh loaded while it is cut, and the budget holds only so many at once.
local cutting = false
local function oneAtATime(fn: (...any) -> any, ...: any): (boolean, any)
	while cutting do
		task.wait(0.1)
	end
	cutting = true
	local ok, result = pcall(fn, ...)
	cutting = false
	return ok, result
end

local function cutHead(template: MeshPart): Pieces
	local n, lips = MarshMouth.NORMAL, MarshMouth.LIPS
	local src = AssetService:CreateEditableMeshAsync(Content.fromUri(template.MeshId))
	-- The skull, the jaw, and each eye's lid.
	-- The skull (and his palate), the jaw (and the floor of his mouth), and both his lids in one: three meshes, not six
	-- (editable meshes share one small budget on each screen, and the sea's two monsters need some of it). The lids
	-- can be one because both hinge on the same line across his face.
	local halves = { AssetService:CreateEditableMesh(), AssetService:CreateEditableMesh(), AssetService:CreateEditableMesh() }
	local maps: { { [string]: { number } } } = { {}, {}, {} }
	local function lidOf(a: Point, b: Point, c: Point): number?
		local centre = (a.p + b.p + c.p) / 3
		local facing = (b.p - a.p):Cross(c.p - a.p)
		if centre.Z > -0.3 or facing.Magnitude < 1e-9 or math.abs(facing.Unit.Z) < 0.2 then
			return nil
		end
		for _, eye in ipairs(MarshMouth.EYES) do
			local u, v = (centre.X - eye.X) / MarshMouth.EYE_SIZE.X, (centre.Y - eye.Y) / MarshMouth.EYE_SIZE.Y
			if u * u + v * v < 1 then
				return 3
			end
		end
		return nil
	end
	local cut: { { Vector3 } } = {}
	local capUV: Vector2? = nil
	local function vert(side: number, v: Point): { any }
		local em, map = halves[side], maps[side]
		local key = v.key
		if key and map[key] then
			return map[key]
		end
		local made = { em:AddVertex(v.p), em:AddUV(v.uv), em:AddNormal(v.n) }
		if key then
			map[key] = made
		end
		return made
	end
	local function tri(side: number, a: Point, b: Point, c: Point)
		if side == 1 then
			side = lidOf(a, b, c) or 1
		end
		local em = halves[side]
		local va, vb, vc = vert(side, a), vert(side, b), vert(side, c)
		local ok, face = pcall(function()
			return em:AddTriangle(va[1], vb[1], vc[1])
		end)
		if ok then
			em:SetFaceUVs(face, { va[2], vb[2], vc[2] })
			em:SetFaceNormals(face, { va[3], vb[3], vc[3] })
		end
	end
	local function across(a: Point, b: Point, t: number): Point
		return { p = a.p:Lerp(b.p, t), uv = a.uv:Lerp(b.uv, t), n = a.n:Lerp(b.n, t).Unit, key = nil, d = 0 }
	end
	for _, face in ipairs(src:GetFaces()) do
		local vs, uvs, ns = src:GetFaceVertices(face), src:GetFaceUVs(face), src:GetFaceNormals(face)
		local pts: { Point } = {}
		local above = 0
		for i = 1, 3 do
			local p = src:GetPosition(vs[i])
			pts[i] = {
				p = p,
				uv = if uvs[i] then src:GetUV(uvs[i]) else Vector2.zero,
				n = if ns[i] then src:GetNormal(ns[i]) else Vector3.yAxis,
				-- (A vertex keyed with its own UV and normal: where the texture has a seam, the two sides stay apart.)
				key = tostring(vs[i]) .. ":" .. tostring(uvs[i]) .. ":" .. tostring(ns[i]),
				d = n:Dot(p - lips),
			}
			if pts[i].d >= 0 then
				above += 1
			end
		end
		if above == 3 then
			tri(1, pts[1], pts[2], pts[3])
		elseif above == 0 then
			tri(2, pts[1], pts[2], pts[3])
		else
			-- ACROSS THE CUT: clipped to each side, the edge it leaves on the plane kept for the caps.
			for side = 1, 2 do
				local poly: { Point } = {}
				local onPlane: { Vector3 } = {}
				for i = 1, 3 do
					local a, b = pts[i], pts[i % 3 + 1]
					local inA = if side == 1 then a.d >= 0 else a.d < 0
					local inB = if side == 1 then b.d >= 0 else b.d < 0
					if inA then
						table.insert(poly, a)
					end
					if inA ~= inB then
						local x = across(a, b, a.d / (a.d - b.d))
						table.insert(poly, x)
						table.insert(onPlane, x.p)
						capUV = capUV or x.uv
					end
				end
				for k = 2, #poly - 1 do
					tri(side, poly[1], poly[k], poly[k + 1])
				end
				if side == 1 and #onPlane == 2 then
					table.insert(cut, onPlane)
				end
			end
		end
	end
	-- THE CAPS: the cut, fanned from its middle, each wound both ways with its own normal so it is lit from either
	-- side (a cap with no normals of its own came out grey).
	local middle = Vector3.zero
	for _, seg in ipairs(cut) do
		middle += seg[1] + seg[2]
	end
	middle /= math.max(1, #cut * 2)
	-- Into the skull's own mesh and the jaw's: dark flesh, by a vertex colour over a pale bit of his own skin's texture.
	for side = 1, 2 do
		local em = halves[side]
		local c = em:AddVertex(middle)
		local up, down = em:AddNormal(n), em:AddNormal(-n)
		local skin = em:AddUV(capUV or Vector2.new(0.5, 0.5))
		local flesh = em:AddColor(Color3.new(0.27, 0.05, 0.07), 1)
		for _, seg in ipairs(cut) do
			local a, b = em:AddVertex(seg[1]), em:AddVertex(seg[2])
			local facing = (seg[1] - middle):Cross(seg[2] - middle):Dot(n) > 0
			for _, wound in ipairs({ { a, b, facing }, { b, a, not facing } }) do
				local face = em:AddTriangle(c, wound[1], wound[2])
				em:SetFaceNormals(face, if wound[3] then { up, up, up } else { down, down, down })
				em:SetFaceUVs(face, { skin, skin, skin })
				em:SetFaceColors(face, { flesh, flesh, flesh })
			end
		end
	end
	local rim: { Vector3 } = {}
	for _, seg in ipairs(cut) do
		table.insert(rim, seg[1])
		table.insert(rim, seg[2])
	end
	local function made(em: EditableMesh, name: string, textured: boolean, colour: Color3): MeshPart
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		-- (Pass 266, from your note: "head is not visible in the back rooms monster". A mesh cut here has no simpler
		-- versions for far away, so at its own Automatic detail it was drawn as nothing beyond a few studs: his head was
		-- there up close and gone down a corridor. Always at full detail.)
		pcall(function()
			part.RenderFidelity = Enum.RenderFidelity.Precise
		end)
		part.Name = name
		part.Anchored = false
		part.Massless = true
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
		part.CastShadow = false
		part.Material = if textured then template.Material else Enum.Material.SmoothPlastic
		part.Color = colour
		if textured then
			part.TextureID = template.TextureID
		end
		return part
	end
	-- (The source freed at once: editable meshes share one memory budget on this screen, and three monsters' heads did
	-- not fit while every source was kept.)
	src:Destroy()
	return {
		skull = made(halves[1], "MouthSkull", true, template.Color),
		jaw = made(halves[2], "MouthJaw", true, template.Color),
		palate = nil,
		floor = nil,
		lids = { made(halves[3], "MouthLid", true, template.Color) },
		rim = rim,
		middle = middle,
		meshSize = template.MeshSize,
		colour = template.Color,
	}
end

-- Cut his head, once (yields; call it in the background). True if the pieces are there.
function MarshMouth.prepare(): boolean
	if pieces then
		return true
	end
	if tried then
		return false
	end
	tried = true
	local template: MeshPart? = nil
	for _ = 1, 60 do
		template = templateOf()
		if template then
			break
		end
		task.wait(0.5)
	end
	-- (A head turned on its mesh, FrontYaw, would need the cut turned with it: it keeps the lid.)
	if not template or template:GetAttribute("FrontYaw") ~= nil then
		return false
	end
	local ok, result = oneAtATime(cutHead, template)
	if ok then
		pieces = result
		print(("MarshMouth: his head cut at the lips, %d points round the cut"):format(#result.rim))
	else
		warn("MarshMouth: his head could not be cut (" .. tostring(result) .. "), so it opens as a lid")
	end
	return pieces ~= nil
end

function MarshMouth.ready(): boolean
	return pieces ~= nil
end

-- The pieces (to clone), or nil if his head was not cut.
function MarshMouth.pieces(): Pieces?
	return pieces
end

-- The front of the cut nearest `x` across his face (the edge of his lips there), or nil.
function MarshMouth.lipAt(x: number): Vector3?
	local got = pieces
	if not got then
		return nil
	end
	local best: Vector3? = nil
	for _, p in ipairs(got.rim) do
		if math.abs(p.X - x) < 0.05 and p.Z < -0.2 and (best == nil or p.Z < (best :: Vector3).Z) then
			best = p
		end
	end
	return best
end

-- HIS TEETH, where they root on the lips and which way each points: `upper` hang from the palate, the rest stand up off
-- the floor of his mouth. Long and thin, uneven, raked toward you, a pair of long ones each side. The same every time.
type Tooth = { root: Vector3, up: Vector3, len: number, upper: boolean }
function MarshMouth.teeth(): { Tooth }
	local list: { Tooth } = {}
	local rng = Random.new(1983)
	local n = MarshMouth.NORMAL
	for _, upper in ipairs({ true, false }) do
		local dir = if upper then -1 else 1
		for k = 1, 11 do
			local x = (k - 6) * 0.075
			local edge = MarshMouth.lipAt(x)
			if edge then
				-- (The lower ones longer since the first film: stubs, they read as pebbles in his gum.)
				local long = (if upper then 0.17 else 0.3) + 0.1 * rng:NextNumber()
				if k == 3 or k == 9 then
					long *= 1.6
				end
				-- Rooted a little in from the lip, sunk a hair into the gum.
				local root = edge + Vector3.new(0, 0, 0.07) - n * (dir * 0.02)
				local up = (n * dir + Vector3.new((rng:NextNumber() - 0.5) * 0.3, 0, if upper then -0.25 else -0.2)).Unit
				table.insert(list, { root = root, up = up, len = long, upper = upper })
			end
		end
	end
	return list
end

-- A tooth's frame on its piece (mesh space scaled by `scale`), its +Y along the tooth from its root.
function MarshMouth.toothFrame(tooth: Tooth, scale: Vector3): CFrame
	local up = tooth.up
	local side = (Vector3.xAxis - up * up:Dot(Vector3.xAxis)).Unit
	return CFrame.fromMatrix(tooth.root * scale, side, up)
end

-- Where a piece sits for a head whose centre is `at`: the skull tipped back `skullTurn` radians on the hinge, the
-- jaw dropped `jawTurn` (both scaled by `scale`, the head's Size over its MeshSize).
function MarshMouth.hinged(at: CFrame, scale: Vector3, turn: number): CFrame
	local h = CFrame.new(MarshMouth.HINGE * scale)
	return at * h * CFrame.Angles(turn, 0, 0) * h:Inverse()
end

-- An eyelid's hinge (mesh space, scaled): along the top of its eye, a little in front.
function MarshMouth.lidHinge(i: number, scale: Vector3): CFrame
	local eye = MarshMouth.EYES[i]
	return CFrame.new((eye + Vector3.new(0, MarshMouth.EYE_SIZE.Y, -0.02)) * scale)
end

-- A lid `open` (0 shut, 1 gone up into his head), as its offset from the skull.
function MarshMouth.lidTurn(i: number, scale: Vector3, open: number): CFrame
	local h = MarshMouth.lidHinge(i, scale)
	return h * CFrame.Angles(-math.rad(105) * open, 0, 0) * h:Inverse()
end

-- (Sunk deep: set just behind the lids, his pupils showed through them shut.)
-- WHAT IS BEHIND HIS LIDS, for each eye, as parts and their offsets from the skull: a dark socket filling the hole, the
-- eyeball sunk in it (wet, yellowed white, veined a little red at its rim), and a pupil no bigger than a pinprick.
type EyePart = { part: Part, offset: CFrame }
function MarshMouth.eyeParts(scale: Vector3): { EyePart }
	local list: { EyePart } = {}
	local k = scale.Y
	local function ball(name: string, size: Vector3, colour: Color3, at: Vector3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size * k
		part.Color = colour
		part.Material = Enum.Material.SmoothPlastic
		part.Massless = true
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
		part.CastShadow = false
		local round = Instance.new("SpecialMesh")
		round.MeshType = Enum.MeshType.Sphere
		round.Parent = part
		table.insert(list, { part = part, offset = CFrame.new(at * scale) })
		return part
	end
	for _, eye in ipairs(MarshMouth.EYES) do
		ball("MouthSocket", Vector3.new(0.34, 0.2, 0.12), Color3.fromRGB(26, 10, 10), eye + Vector3.new(0, 0, 0.15))
		ball("MouthEyeRim", Vector3.new(0.25, 0.17, 0.2), Color3.fromRGB(150, 60, 56), eye + Vector3.new(0, 0, 0.16))
		local white = ball("MouthEye", Vector3.new(0.23, 0.15, 0.2), Color3.fromRGB(232, 224, 196), eye + Vector3.new(0, 0, 0.155))
		white.Reflectance = 0.12
		ball("MouthPupil", Vector3.new(0.035, 0.035, 0.02), Color3.fromRGB(8, 6, 6), eye + Vector3.new(0, 0, 0.055))
	end
	return list
end

-- ===== JAWS FOR THE SEA'S MONSTERS (the two-hundred-and-twenty-ninth pass, "now do the serpent and leviathan mouths") =====
--
-- The Sunken City serpent's made head (Assets/Props.Sea_Head) and the lobby leviathan's (Sea_LeviathanHead) were each
-- made with their jaws half open, and never moved them. Each is cut here the same way as Marsh's, but only its LOWER
-- JAW comes away: what is under a plane through the gap between its teeth AND in front of the hinge at the corner of
-- its mouth (so its throat and neck stay with its skull). No caps: the cut runs along the open gap of the mouth, where
-- there is little to fill. Each spec is in that head's own mesh space: the gap's front point, the plane's normal (up out
-- of the jaw), the hinge, and which way its snout points along Z (+1 or -1).
-- `throat`: a dark gullet inside the mouth (its middle and size, box-centred mesh space), turning half as far as the jaw
-- so it stays in the gap: opened wider than it was made, the mouth showed the sky through it.
export type JawSpec = { point: Vector3, normal: Vector3, hinge: Vector3, snout: number,
	throat: { at: Vector3, size: Vector3 } }
MarshMouth.JAWS = {
	Sea_Head = { point = Vector3.new(0, -1.06, -3.1), normal = Vector3.new(0, 0.972, -0.236).Unit,
		hinge = Vector3.new(0, -0.6, -1.25), snout = -1,
		throat = { at = Vector3.new(0, -0.8, -1.55), size = Vector3.new(2.0, 0.75, 1.7) } },
	Sea_LeviathanHead = { point = Vector3.new(0, -0.07, 1.0), normal = Vector3.new(0, 0.989, 0.15).Unit,
		hinge = Vector3.new(0, 0, 0.5), snout = 1,
		throat = { at = Vector3.new(0, -0.06, 0.66), size = Vector3.new(0.5, 0.2, 0.36) } },
} :: { [string]: JawSpec }

type Jaw = { skull: MeshPart, jaw: MeshPart, meshSize: Vector3, spec: JawSpec, centre: Vector3 }
local jaws: { [string]: Jaw | false } = {}

local function cutJaw(template: MeshPart, spec: JawSpec): Jaw
	local src = AssetService:CreateEditableMeshAsync(Content.fromUri(template.MeshId))
	-- (Its middle: a MeshPart made from an EditableMesh is drawn about the mesh's own origin, where the head as made is
	-- drawn about the middle of its box.)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, v in ipairs(src:GetVertices()) do
		local p = src:GetPosition(v)
		low, high = low:Min(p), high:Max(p)
	end
	local halves = { AssetService:CreateEditableMesh(), AssetService:CreateEditableMesh() }
	local maps: { { [string]: { number } } } = { {}, {} }
	local function vert(side: number, v: Point): { any }
		local em, map = halves[side], maps[side]
		local key = v.key
		if key and map[key] then
			return map[key]
		end
		local made = { em:AddVertex(v.p), em:AddUV(v.uv), em:AddNormal(v.n) }
		if key then
			map[key] = made
		end
		return made
	end
	local function tri(side: number, a: Point, b: Point, c: Point)
		local em = halves[side]
		local va, vb, vc = vert(side, a), vert(side, b), vert(side, c)
		local ok, face = pcall(function()
			return em:AddTriangle(va[1], vb[1], vc[1])
		end)
		if ok then
			em:SetFaceUVs(face, { va[2], vb[2], vc[2] })
			em:SetFaceNormals(face, { va[3], vb[3], vc[3] })
		end
	end
	-- A polygon split by the plane where `side(p)` is 0: what is >= 0, and what is < 0.
	local function split(poly: { Point }, side: (Vector3) -> number): ({ Point }, { Point })
		local keep, rest = {}, {}
		for i = 1, #poly do
			local a, b = poly[i], poly[i % #poly + 1]
			local da, db = side(a.p), side(b.p)
			if da >= 0 then
				table.insert(keep, a)
			else
				table.insert(rest, a)
			end
			if (da >= 0) ~= (db >= 0) then
				local t = da / (da - db)
				local x = { p = a.p:Lerp(b.p, t), uv = a.uv:Lerp(b.uv, t), n = a.n:Lerp(b.n, t).Unit, key = nil, d = 0 }
				table.insert(keep, x)
				table.insert(rest, x)
			end
		end
		return keep, rest
	end
	local function fan(side: number, poly: { Point })
		for k = 2, #poly - 1 do
			tri(side, poly[1], poly[k], poly[k + 1])
		end
	end
	-- (The spec is measured from the middle of the head's box.)
	local centre = (low + high) / 2
	local above = function(p: Vector3): number
		return spec.normal:Dot(p - centre - spec.point)
	end
	local ahead = function(p: Vector3): number
		return spec.snout * (p.Z - centre.Z - spec.hinge.Z)
	end
	local band = (high.Z - low.Z) * 0.07
	for _, face in ipairs(src:GetFaces()) do
		local vs, uvs, ns = src:GetFaceVertices(face), src:GetFaceUVs(face), src:GetFaceNormals(face)
		local poly: { Point } = {}
		for i = 1, 3 do
			poly[i] = {
				p = src:GetPosition(vs[i]),
				uv = if uvs[i] then src:GetUV(uvs[i]) else Vector2.zero,
				n = if ns[i] then src:GetNormal(ns[i]) else Vector3.yAxis,
				key = tostring(vs[i]) .. ":" .. tostring(uvs[i]) .. ":" .. tostring(ns[i]),
				d = 0,
			}
		end
		local up, down = split(poly, above)
		if #up >= 3 then
			fan(1, up)
		end
		if #down >= 3 then
			local front, back = split(down, ahead)
			if #front >= 3 then
				fan(2, front)
			end
			if #back >= 3 then
				fan(1, back)
				-- A STRIP OF ITS THROAT ON THE JAW TOO, just behind the cut (filmed, the cut opened as a line of sky
				-- behind the jaw as it gaped): what lies there is drawn on both, so the jaw slides over the skull.
				local middle = Vector3.zero
				for _, point in ipairs(back) do
					middle += point.p
				end
				if ahead(middle / #back) > -band then
					fan(2, back)
				end
			end
		end
	end
	local function made(em: EditableMesh, name: string): MeshPart
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		-- (Pass 266, from your note: "head is not visible in the back rooms monster". A mesh cut here has no simpler
		-- versions for far away, so at its own Automatic detail it was drawn as nothing beyond a few studs: his head was
		-- there up close and gone down a corridor. Always at full detail.)
		pcall(function()
			part.RenderFidelity = Enum.RenderFidelity.Precise
		end)
		part.Name = name
		part.Anchored = true
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
		part.CastShadow = false
		part.Material = template.Material
		part.MaterialVariant = template.MaterialVariant
		part.Color = template.Color
		part.TextureID = template.TextureID
		part.DoubleSided = template.DoubleSided
		-- Its own made skin, where it has one (the leviathan's head wears a SurfaceAppearance, not a texture).
		for _, skin in ipairs(template:GetChildren()) do
			if skin:IsA("SurfaceAppearance") then
				skin:Clone().Parent = part
			end
		end
		return part
	end
	local result = { skull = made(halves[1], "JawSkull"), jaw = made(halves[2], "JawLower"), meshSize = template.MeshSize,
		spec = spec, centre = (low + high) / 2 }
	src:Destroy()
	return result
end

-- `name`'s head cut at its jaw (yields; once), or nil when it cannot be (not made, or no mesh access).
function MarshMouth.jaw(name: string): Jaw?
	local known = jaws[name]
	if known ~= nil then
		return if known then known else nil
	end
	jaws[name] = false
	local spec = MarshMouth.JAWS[name]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = assets and assets:FindFirstChild("Props")
	local made = props and props:FindFirstChild(name)
	local template = made and (if made:IsA("MeshPart") then made else made:FindFirstChildWhichIsA("MeshPart", true))
	if not (spec and template and template:IsA("MeshPart")) then
		return nil
	end
	local ok, result = oneAtATime(cutJaw, template, spec)
	if not ok then
		warn(("MarshMouth: %s's jaw could not be cut (%s), so its mouth stays as it was made"):format(name, tostring(result)))
		return nil
	end
	jaws[name] = result
	return result
end

-- `name`'s cut jaw if it has been cut already (never yields), else nil.
function MarshMouth.jawIfReady(name: string): Jaw?
	local known = jaws[name]
	return if known then known else nil
end

-- THE LEVIATHAN'S JAW, in the lobby: HubService lays its made head on the server; on this screen that head is hidden and
-- drawn instead in its two pieces, its jaw working slowly, now and then gaping in a long silent roar. Runs for the
-- whole game (call it in the background); the lobby is built once, so the head is looked for until it is there.
function MarshMouth.leviathan()
	local head: BasePart? = nil
	for _ = 1, 120 do
		local found = workspace:FindFirstChild("Sea_LeviathanHead", true)
		if found and found:IsA("BasePart") then
			head = found
			break
		end
		task.wait(1)
	end
	local cut = if head then MarshMouth.jaw("Sea_LeviathanHead") else nil
	if not (head and cut) then
		return
	end
	local function piece(from: MeshPart): MeshPart
		local part = from:Clone()
		part.Size = from.Size * (head.Size / cut.meshSize)
		part.Parent = head.Parent
		return part
	end
	local skull, jaw = piece(cut.skull), piece(cut.jaw)
	local throat = MarshMouth.throat(cut, head.Size)
	throat.Parent = head.Parent
	head.LocalTransparencyModifier = 1
	skull.CFrame = MarshMouth.jawFrame(cut, head.CFrame, head.Size, 0)
	print("MarshMouth: the leviathan's jaw is its own")
	local roarAt = os.clock() + 12
	game:GetService("RunService").Heartbeat:Connect(function()
		if not (head.Parent and jaw.Parent) then
			return
		end
		local now = os.clock()
		-- Breathing, slow; and every so often a roar: wide, held, and shut again.
		local turn = -0.04 + 0.06 * math.sin(now * 0.45)
		local into = now - roarAt
		if into > 0 then
			local roar = if into < 1.2 then into / 1.2 elseif into < 4 then 1 elseif into < 5.5 then 1 - (into - 4) / 1.5 else 0
			turn += 0.32 * (roar * roar * (3 - 2 * roar))
			if into > 5.5 then
				roarAt = now + 16 + math.random() * 14
			end
		end
		jaw.CFrame = MarshMouth.jawFrame(cut, head.CFrame, head.Size, turn)
		throat.CFrame = MarshMouth.throatFrame(cut, head.CFrame, head.Size, turn)
	end)
end

-- The dark gullet for a jaw cut, to be placed with `throatFrame` (sized for a head of Size `size`).
function MarshMouth.throat(jaw: Jaw, size: Vector3): Part
	local scale = size / jaw.meshSize
	local part = Instance.new("Part")
	part.Name = "JawThroat"
	part.Size = jaw.spec.throat.size * scale
	-- Matte flesh, deep red (glossy black, filmed, it was an egg in the leviathan's mouth with the sky in it).
	part.Color = Color3.fromRGB(52, 12, 16)
	part.Material = Enum.Material.Fabric
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
	part.CastShadow = false
	local round = Instance.new("SpecialMesh")
	round.MeshType = Enum.MeshType.Sphere
	round.Parent = part
	return part
end

function MarshMouth.throatFrame(jaw: Jaw, at: CFrame, size: Vector3, turn: number): CFrame
	local scale = size / jaw.meshSize
	local h = CFrame.new(jaw.spec.hinge * scale)
	return at * h * CFrame.Angles(-turn * 0.5 * -jaw.spec.snout, 0, 0) * h:Inverse() * CFrame.new(jaw.spec.throat.at * scale)
end

-- Where a cut piece goes so that, together, they are the head whose box's middle is `at` (its Size `size`), the jaw turned `turn` radians on
-- its hinge (more than nought opens it wider than it was made).
function MarshMouth.jawFrame(jaw: Jaw, at: CFrame, size: Vector3, turn: number): CFrame
	local scale = size / jaw.meshSize
	local h = CFrame.new(jaw.spec.hinge * scale)
	-- Opening drops the jaw's front: about +X for a snout to -Z, about -X for a snout to +Z. (The spec is measured from
	-- the middle of the head's box; the pieces are drawn about the mesh's origin, `centre` from it.)
	return at * h * CFrame.Angles(-turn * -jaw.spec.snout, 0, 0) * h:Inverse() * CFrame.new(-jaw.centre * scale)
end

MarshMouth.STAMP = "ec4896a1"
return MarshMouth
