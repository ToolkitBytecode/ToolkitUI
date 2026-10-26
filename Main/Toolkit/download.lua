local Library = { Version = "2.2.0" }

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer

local White = Color3.new(1, 1, 1)

local Theme = {
	-- BLACK palette: pure black surfaces, neutral grey steps, WHITE strokes / highlights / icons.
	-- The liquid look comes from the white UIGradient + UIStroke layers (see the glass system below).
	Bg = Color3.fromRGB(0, 0, 0),
	Bg2 = Color3.fromRGB(8, 8, 8),
	Card = Color3.fromRGB(14, 14, 14),
	CardHover = Color3.fromRGB(26, 26, 26),
	Hover = Color3.fromRGB(36, 36, 36),
	Selected = Color3.fromRGB(30, 30, 30),
	Stroke = Color3.fromRGB(44, 44, 44),          -- hairline separators / tracks
	StrokeHi = Color3.fromRGB(255, 255, 255),     -- white border (always shown through a low-alpha gradient)
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(160, 160, 160),
	Accent = Color3.fromRGB(255, 255, 255),       -- primary = white
	AccentDim = Color3.fromRGB(140, 140, 140),
	OnAccent = Color3.fromRGB(0, 0, 0),
	Frost = Color3.fromRGB(255, 255, 255),        -- frosted highlight (white)
	Soft = Color3.fromRGB(235, 235, 235),         -- soft reflection
	IconDim = Color3.fromRGB(130, 130, 130),      -- inactive icons
	IconHi = Color3.fromRGB(255, 255, 255),       -- active icons (white)
	Cyan = Color3.fromRGB(210, 210, 210),
	Pink = Color3.fromRGB(255, 77, 166),
	Teal = Color3.fromRGB(20, 184, 166),
	Blue = Color3.fromRGB(59, 130, 246),
	-- status colors are intentionally left saturated so success / warning / error stay unmistakable
	Green = Color3.fromRGB(74, 222, 128),
	Red = Color3.fromRGB(248, 113, 113),
	Amber = Color3.fromRGB(251, 191, 36),
	NotifBg = Color3.fromRGB(0, 0, 0),
}
Theme.Violet = Theme.Accent
Library.Theme = Theme

local ParagraphColors = {
	Red = Color3.fromRGB(248, 113, 113), Orange = Color3.fromRGB(251, 146, 60), Green = Color3.fromRGB(74, 222, 128),
	Blue = Color3.fromRGB(59, 130, 246), Purple = Color3.fromRGB(139, 92, 255), Grey = Color3.fromRGB(148, 153, 166),
}

local TypeColors = {
	success = Theme.Green, error = Theme.Red, warn = Theme.Amber, warning = Theme.Amber, info = Theme.Cyan,
}

-- FONTS: Roboto (neo-grotesque sans-serif) everywhere. Weights are built from Roblox's own Roboto family,
-- so the asset path always matches the client. Falls back to Enum.Font.Roboto if anything fails.
local function MakeFont(Weight, Fallback)
	local Ok, F = pcall(function()
		local Base = Font.fromEnum(Enum.Font.Roboto)
		return Font.new(Base.Family, Weight, Enum.FontStyle.Normal)
	end)
	if Ok and F then return F end
	return Font.fromEnum(Fallback or Enum.Font.Roboto)
end
local FontReg = MakeFont(Enum.FontWeight.Regular)
local FontMed = MakeFont(Enum.FontWeight.Medium)
local FontBold = MakeFont(Enum.FontWeight.Bold)
local FontBlack = MakeFont(Enum.FontWeight.ExtraBold)
local FontMono = Font.fromEnum(Enum.Font.RobotoMono)    -- Roboto's monospace sibling, used by the code block
local Left, Right = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
local AutoY, AutoX = Enum.AutomaticSize.Y, Enum.AutomaticSize.X
local QuartOut, DirOut = Enum.EasingStyle.Quart, Enum.EasingDirection.Out
local MouseButton1, TouchInput, MouseMove = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.UserInputType.MouseMovement
-- Corner hierarchy (px): 1-3 details, 4-6 fields/chips, 7-9 controls, 10-12 panels/cards, 13-16 windows/dialogs
local MAIN_RADIUS = 14
local CONTROL_RADIUS = 8
local DIALOG_RADIUS = 14
local CARD_RADIUS = 12
local GROUP_RADIUS = 10
local FIELD_RADIUS = 6

local function New(Class, Props, Parent)
	local Object = Instance.new(Class)
	-- Every text element starts with Roboto, so nothing can fall back to the default font.
	if Class == "TextLabel" or Class == "TextButton" or Class == "TextBox" then
		Object.FontFace = FontReg
	end
	for K, V in pairs(Props or {}) do
		Object[K] = V
	end
	Object.Parent = Parent
	return Object
end

local function Tween(Object, Time, Props, Style, Direction)
	local T = TweenService:Create(Object, TweenInfo.new(Time, Style or QuartOut, Direction or DirOut), Props)
	T:Play()
	return T
end

-- Reuses an existing UICorner on the same object instead of stacking a second one.
local function Corner(Parent, R)
	local Radius = UDim.new(0, math.clamp(tonumber(R) or 10, 1, 16))
	local Existing = Parent:FindFirstChildOfClass("UICorner")
	if Existing then
		Existing.CornerRadius = Radius
		return Existing
	end
	return New("UICorner", { CornerRadius = Radius }, Parent)
end

-- ============================================================================
-- Glass visual system (gradient / stroke fallback layer)
--
-- Everything here is static: instances are created once, given fixed names and
-- looked up by name afterwards, so rebuilding or refreshing a surface never
-- stacks duplicate UIGradient / UIStroke / UICorner / highlight frames.
-- Nothing in this block runs per frame.
--
-- Notes on how Roblox composes these (verify visually in your target client):
--  * UIGradient.Color is multiplied with the parent's own color, so surfaces
--    that carry a Color gradient start from the brighter tone and fade darker.
--  * A UIGradient parented to a UIStroke shades the stroke itself, which is how
--    the rim gets a bright top edge and a faint lower edge.
--  * UIGradient also tints TEXT on its parent, so fill gradients are only put
--    on objects without visible text (or with dark text on a light fill).
-- ============================================================================
local FX = { Layers = setmetatable({}, { __mode = "k" }), Reflections = true }

local function SeqKeys(Ctor, Points)
	local K = {}
	for I, P in ipairs(Points) do K[I] = Ctor.new(P[1], P[2]) end
	return K
end
local function CSeq(Points) return ColorSequence.new(SeqKeys(ColorSequenceKeypoint, Points)) end
local function NSeq(Points) return NumberSequence.new(SeqKeys(NumberSequenceKeypoint, Points)) end

local RimPresets = {
	-- Major surfaces: frosted top edge that fades into the border tone; slight lean for a side highlight.
	Rim = {
		Rotation = 80,
		Color = CSeq({ { 0, White }, { 0.55, Color3.fromRGB(215, 215, 215) }, { 1, Color3.fromRGB(170, 170, 170) } }),
		Alpha = NSeq({ { 0, 0.36 }, { 0.14, 0.58 }, { 0.5, 0.84 }, { 0.82, 0.80 }, { 1, 0.62 } }),
	},
	-- Controls / cards: thinner, lower-contrast version of the same light direction.
	Soft = {
		Rotation = 90,
		Color = CSeq({ { 0, White }, { 1, Color3.fromRGB(220, 220, 220) } }),
		Alpha = NSeq({ { 0, 0.30 }, { 0.5, 0.58 }, { 1, 0.46 } }),
	},
}

local DepthPresets = {
	Panel = { Rotation = 90, Color = CSeq({ { 0, White }, { 1, Color3.fromRGB(225, 225, 225) } }) },
	Button = { Rotation = 90, Color = CSeq({ { 0, White }, { 1, Color3.fromRGB(235, 235, 235) } }) },
	Bar = { Rotation = 0, Color = CSeq({ { 0, Color3.fromRGB(205, 205, 205) }, { 1, White } }) },
}

-- Reflection overlay: soft icy tint that is strongest at the top and fully gone before the middle.
local SheenAlpha = NSeq({ { 0, 0.84 }, { 0.3, 0.92 }, { 0.65, 0.975 }, { 1, 1 } })
-- Bottom shade: gives the pane a little weight without a hard shadow.
local ShadeAlpha = NSeq({ { 0, 1 }, { 0.45, 0.93 }, { 1, 0.66 } })
-- Separator that fades out at both ends instead of stopping abruptly.
local HairAlpha = NSeq({ { 0, 1 }, { 0.12, 0.3 }, { 0.88, 0.3 }, { 1, 1 } })

local function Named(Parent, Class, Name)
	local Found = Parent:FindFirstChild(Name)
	if Found and Found:IsA(Class) then return Found end
	return New(Class, { Name = Name }, Parent)
end

function FX.Rim(S, Kind)
	local P = RimPresets[Kind] or RimPresets.Soft
	local G = Named(S, "UIGradient", "GlassRim")
	G.Color, G.Transparency, G.Rotation = P.Color, P.Alpha, P.Rotation
	return G
end

function FX.Depth(Obj, Kind)
	local P = DepthPresets[Kind] or DepthPresets.Panel
	local G = Named(Obj, "UIGradient", "GlassDepth")
	G.Color, G.Rotation = P.Color, P.Rotation
	return Obj
end

function FX.Hairline(Obj, Vertical)
	local G = Named(Obj, "UIGradient", "GlassHairline")
	G.Transparency = HairAlpha
	G.Rotation = Vertical and 90 or 0
	return Obj
end

-- Adds the reflection (and optional bottom shade) layers inside a rounded surface.
-- Both use the same corner radius as the surface, never take input, and sit below the
-- surface's interactive children (children that need to stay on top use ZIndex >= 3).
-- Do not call this on a frame that has a UIListLayout / UIGridLayout of its own:
-- the layer would be arranged like a normal child.
function FX.Surface(Parent, R, O)
	O = O or {}
	local Z = O.Z or 2
	if not Parent:FindFirstChild("GlassSheen") then
		local Sheen = New("Frame", {
			Name = "GlassSheen", Size = UDim2.new(1, 0, 0, O.Height or 64), BackgroundColor3 = Theme.Soft,
			BorderSizePixel = 0, ZIndex = Z, Active = false, Visible = FX.Reflections,
		}, Parent)
		Corner(Sheen, R)
		New("UIGradient", { Name = "GlassSheenGradient", Rotation = 80, Transparency = SheenAlpha }, Sheen)
		FX.Layers[Sheen] = true
	end
	if O.Shade and not Parent:FindFirstChild("GlassShade") then
		local Shade = New("Frame", {
			Name = "GlassShade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, O.ShadeHeight or 70), BackgroundColor3 = Theme.Bg,
			BorderSizePixel = 0, ZIndex = Z, Active = false, Visible = FX.Reflections,
		}, Parent)
		Corner(Shade, R)
		New("UIGradient", { Name = "GlassShadeGradient", Rotation = 90, Transparency = ShadeAlpha }, Shade)
		FX.Layers[Shade] = true
	end
	return Parent
end

-- Cheap quality switch: hides / shows every reflection + shade layer (no per-frame work either way).
function FX.SetReflections(V)
	FX.Reflections = V ~= false
	for Obj in pairs(FX.Layers) do
		if Obj.Parent then Obj.Visible = FX.Reflections else FX.Layers[Obj] = nil end
	end
end

function Library:SetReflections(V) FX.SetReflections(V) end

-- Style: nil (plain stroke) | "Rim" (major surfaces) | "Soft" (cards / controls). Reuses an existing stroke.
local function Stroke(Parent, Color, Thickness, Transparency, Style)
	local S = Parent:FindFirstChildOfClass("UIStroke")
	if S then
		S.Color, S.Thickness, S.Transparency = Color or Theme.Stroke, Thickness or 1, Transparency or 0
	else
		S = New("UIStroke", {
			Color = Color or Theme.Stroke, Thickness = Thickness or 1, Transparency = Transparency or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, Parent)
	end
	if Style then FX.Rim(S, Style) end
	return S
end

-- ============================================================================
-- GLASSMORPHISM (optional, PC only): black + white glossy "liquid glass"
--   * Library:SetGlassmorphism(true/false) / Window:SetGlassmorphism(true/false)
--   * PC only. On touch devices the same call only switches on Transparent mode (nothing else changes),
--     because the animated gloss + backdrop blur are too heavy for mobile.
--   * Layers per surface (all white, always inside the surface's own corners):
--       tint (frosted top light) + two soft light streaks that drift slowly + inner rim + top specular line
--   * A BlurEffect (Lighting) blurs the game world behind the window while the window is open.
-- ============================================================================
Library.Glassmorphism = false          -- what the user asked for
Library.GlassEffective = false         -- what is really drawn (asked for AND running on PC)
Library.GlassBlurSize = 6              -- 0 = no backdrop blur (low by default: mostly clear glass with a light blur)
Library.GlassDistortion = 0.6          -- 0-1: strength of the lens / refraction edge on the glass
do
	local U = UserInputService
	Library.IsPC = (not U.TouchEnabled) or (U.KeyboardEnabled and U.MouseEnabled)
end

FX.Liquids = setmetatable({}, { __mode = "k" })

local LiquidTintAlpha = NSeq({ { 0, 0.9 }, { 0.3, 0.95 }, { 0.7, 0.975 }, { 1, 0.99 } })
local StreakAlphaA = NSeq({ { 0, 1 }, { 0.36, 1 }, { 0.5, 0.88 }, { 0.64, 1 }, { 1, 1 } })
local StreakAlphaB = NSeq({ { 0, 1 }, { 0.42, 1 }, { 0.52, 0.94 }, { 0.62, 1 }, { 1, 1 } })
-- Lens edge: light bends near the rim of real glass, so the edge gets a bright, soft band that fades inward
-- (stronger on the top-left, softer on the bottom-right). Peak scales each band; D is Library.GlassDistortion.
local function LensSeq(D, Peak)
	local Pts = { { 0, 0.55 }, { 0.3, 0.2 }, { 0.55, 0.04 }, { 0.8, 0.2 }, { 1, 0.45 } }
	local K = {}
	for I, P in ipairs(Pts) do
		K[I] = NumberSequenceKeypoint.new(P[1], math.clamp(1 - P[2] * Peak * D, 0, 1))
	end
	return NumberSequence.new(K)
end
local SpecAlpha = NSeq({ { 0, 1 }, { 0.18, 0.55 }, { 0.5, 0.15 }, { 0.82, 0.55 }, { 1, 1 } })

-- Kind: "Full" (tint + streaks + rim + specular line) or "Light" (tint + rim + specular line, nothing animated)
function FX.Liquid(Parent, R, Kind)
	if Parent:FindFirstChild("LiquidGlass") then return Parent:FindFirstChild("LiquidGlass") end
	local Full = Kind ~= "Light"
	local Holder = New("Frame", {
		Name = "LiquidGlass", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = 2, Active = false, Visible = Library.GlassEffective,
	}, Parent)
	local Rec = { Kind = Kind or "Full" }

	local Tint = New("Frame", {
		Name = "Tint", Size = UDim2.fromScale(1, 1), BackgroundColor3 = White, BackgroundTransparency = 0,
		BorderSizePixel = 0, ZIndex = 2, Active = false,
	}, Holder)
	Corner(Tint, R)
	New("UIGradient", { Rotation = 90, Transparency = LiquidTintAlpha }, Tint)

	if Full then
		local A = New("Frame", {
			Name = "StreakA", Size = UDim2.fromScale(1, 1), BackgroundColor3 = White, BackgroundTransparency = 0,
			BorderSizePixel = 0, ZIndex = 2, Active = false,
		}, Holder)
		Corner(A, R)
		Rec.GA = New("UIGradient", { Rotation = 24, Transparency = StreakAlphaA, Offset = Vector2.new(-0.5, 0) }, A)
		local B = New("Frame", {
			Name = "StreakB", Size = UDim2.fromScale(1, 1), BackgroundColor3 = White, BackgroundTransparency = 0,
			BorderSizePixel = 0, ZIndex = 2, Active = false,
		}, Holder)
		Corner(B, R)
		Rec.GB = New("UIGradient", { Rotation = -38, Transparency = StreakAlphaB, Offset = Vector2.new(0.5, 0) }, B)
	end

	-- inner rim: a second, thinner white edge just inside the main border (gives the "thick glass" look)
	local Rim = New("Frame", {
		Name = "InnerRim", Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 3, Active = false,
	}, Holder)
	Corner(Rim, math.max(R - 2, 1))
	Stroke(Rim, White, 1, 0.1, "Soft")

	-- lens / refraction edge (three soft bands of different widths, strength = Library.GlassDistortion)
	if Full then
		Rec.Lens = {}
		for _, B in ipairs({ { 10, 0.4 }, { 5, 0.7 }, { 2, 1.2 } }) do
			local T, Peak = B[1], B[2]
			local Band = New("Frame", {
				Name = "LensEdge", Position = UDim2.fromOffset(T, T), Size = UDim2.new(1, -T * 2, 1, -T * 2), BackgroundTransparency = 1,
				BorderSizePixel = 0, ZIndex = 3, Active = false,
			}, Holder)
			Corner(Band, math.max(R - T, 1))
			local St = New("UIStroke", { Color = White, Thickness = T, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 0 }, Band)
			local G = New("UIGradient", { Rotation = 135, Transparency = LensSeq(Library.GlassDistortion, Peak) }, St)
			table.insert(Rec.Lens, { Grad = G, Peak = Peak })
		end
	end

	-- specular line along the top edge
	local Spec = New("Frame", {
		Name = "Specular", Position = UDim2.new(0, R, 0, 1), Size = UDim2.new(1, -R * 2, 0, 1), BackgroundColor3 = White,
		BorderSizePixel = 0, ZIndex = 3, Active = false,
	}, Holder)
	New("UIGradient", { Transparency = SpecAlpha }, Spec)

	FX.Liquids[Holder] = Rec
	return Holder
end

function FX.SetDistortion(D)
	for Holder, Rec in pairs(FX.Liquids) do
		if Holder.Parent and Rec.Lens then
			for _, L in ipairs(Rec.Lens) do L.Grad.Transparency = LensSeq(D, L.Peak) end
		end
	end
end

-- BlurFrame: a real Frame inside the main frame, exactly the same size and corners as it. The acrylic blur is built from
-- THIS frame's position and size, and it carries the soft dark acrylic tint while glassmorphism is on.
FX.BlurFrames = setmetatable({}, { __mode = "k" })
function FX.BlurFrame(Parent, R)
	local F = New("Frame", {
		Name = "BlurFrame", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1, Active = false,
	}, Parent)
	Corner(F, R)
	FX.BlurFrames[F] = true
	if Library.GlassEffective then F.BackgroundTransparency = 0.82 end
	return F
end

function FX.SetBlurFrames(V)
	for F in pairs(FX.BlurFrames) do
		if F.Parent then Tween(F, 0.3, { BackgroundTransparency = V and 0.82 or 1 }) else FX.BlurFrames[F] = nil end
	end
end

function FX.SetLiquid(V)
	for Holder in pairs(FX.Liquids) do
		if Holder.Parent then Holder.Visible = V else FX.Liquids[Holder] = nil end
	end
end

-- one shared loop moves every streak (about 30 updates a second, only while glass is really on)
task.spawn(function()
	local T0 = os.clock()
	while true do
		task.wait(1 / 30)
		if Library.GlassEffective and Library.Moving then
			local T = os.clock() - T0
			for Holder, Rec in pairs(FX.Liquids) do
				if Rec.GA and Holder.Parent and Holder.Visible then
					Rec.GA.Offset = Vector2.new(math.sin(T * 0.32) * 0.75, 0)
					Rec.GB.Offset = Vector2.new(math.cos(T * 0.23) * 0.75, 0)
				end
			end
		end
	end
end)

local function Gradient(Parent, A, B, Rotation)
	return New("UIGradient", { Color = ColorSequence.new(A, B), Rotation = Rotation or 0 }, Parent)
end

local function Pad(Parent, L, T, R, B)
	return New("UIPadding", {
		PaddingLeft = UDim.new(0, L), PaddingTop = UDim.new(0, T), PaddingRight = UDim.new(0, R), PaddingBottom = UDim.new(0, B),
	}, Parent)
end

local function List(Parent, Padding, Props)
	local P = { Padding = UDim.new(0, Padding or 0), SortOrder = Enum.SortOrder.LayoutOrder }
	for K, V in pairs(Props or {}) do P[K] = V end
	return New("UIListLayout", P, Parent)
end

local function Call(Fn, ...)
	if type(Fn) == "function" then task.spawn(Fn, ...) end
end

local function InsetY() return GuiService:GetGuiInset().Y end

local function ParseColor(V, Fallback)
	if typeof(V) == "Color3" then return V end
	if type(V) == "table" and tonumber(V[1]) and tonumber(V[2]) and tonumber(V[3]) then
		return Color3.fromRGB(math.clamp(V[1], 0, 255), math.clamp(V[2], 0, 255), math.clamp(V[3], 0, 255))
	end
	if type(V) == "string" then
		local Named = Theme[V] or ParagraphColors[V]
		if typeof(Named) ~= "Color3" then
			local Lower = V:lower()
			Named = nil
			for K, C in pairs(Theme) do
				if typeof(C) == "Color3" and K:lower() == Lower then Named = C break end
			end
			if not Named then
				for K, C in pairs(ParagraphColors) do
					if K:lower() == Lower then Named = C break end
				end
			end
		end
		if typeof(Named) == "Color3" then return Named end

		local R, G, B = V:match("^%s*rgb%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)%s*$")
		if R then
			return Color3.fromRGB(math.min(tonumber(R), 255), math.min(tonumber(G), 255), math.min(tonumber(B), 255))
		end

		local H = V:gsub("%s", "")
		H = H:gsub("^#", "")
		H = H:gsub("^0[xX]", "")
		if #H == 3 then H = H:sub(1, 1):rep(2) .. H:sub(2, 2):rep(2) .. H:sub(3, 3):rep(2) end
		if #H == 8 then H = H:sub(1, 6) end
		if #H == 6 and not H:find("%X") then
			return Color3.fromRGB(tonumber(H:sub(1, 2), 16), tonumber(H:sub(3, 4), 16), tonumber(H:sub(5, 6), 16))
		end
	end
	return Fallback
end
Library.ParseColor = ParseColor

local function CopyText(Text)
	local Fn = setclipboard or toclipboard or (syn and syn.write_clipboard)
	if not Fn then return false end
	return (pcall(Fn, Text))
end

local function ParentGui(Gui)
	local Ok = pcall(function() Gui.Parent = gethui and gethui() or CoreGui end)
	if not Ok or not Gui.Parent then Gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end

local function StripRich(Text)
	return (tostring(Text):gsub("<[^>]+>", ""))
end

Library.BackgroundTransparency = 0
Library.Transparent = false
Library.Moving = true
local BgRegistry = {}

-- Base can be a number OR a function returning a number (so it can react to Library.Transparent)
local function BgCalc(Base)
	if type(Base) == "function" then Base = Base() end
	Base = Base or 0
	return Base + (1 - Base) * Library.BackgroundTransparency
end

-- Glass(solidValue, transparentValue): picks the base transparency depending on Library.Transparent
local function Glass(Normal, Clear)
	return function()
		if not Library.Transparent then return Normal end
		-- glassmorphism: more see-through so the backdrop blur shows through
		if Library.GlassEffective then return Clear + (1 - Clear) * 0.5 end
		return Clear
	end
end

local function PruneBg()
	for I = #BgRegistry, 1, -1 do
		if BgRegistry[I].Obj.Parent == nil then table.remove(BgRegistry, I) end
	end
end

local function Bg(Obj, Base)
	Base = Base or 0
	table.insert(BgRegistry, { Obj = Obj, Base = Base })
	if #BgRegistry % 100 == 0 then PruneBg() end
	Obj.BackgroundTransparency = BgCalc(Base)
	return Obj
end

local function BgStroke(Obj, Base)
	Base = Base or 0
	table.insert(BgRegistry, { Obj = Obj, Base = Base, Prop = "Transparency" })
	Obj.Transparency = BgCalc(Base)
	return Obj
end

-- ============================================================================
-- Optional genuine-glass adapter (boatbomber / boatbeaker "GlassmorphicUI")
--
-- What the reference actually is (from its README): a ModuleScript that builds the
-- frosted / refracted look from an EditableImage, sampling the backdrop and inserting
-- a "GlassPane" ImageLabel below a GuiObject's other children. Its documented API:
--   addGlassBackground(GuiObject), pauseUpdates / resumeUpdates / forceUpdate(GuiObject)
-- and attributes on the object: Transparency (tint alpha), CornerRadius (UDim),
-- SuperEllipseFactor (2 = circular corner), BlurRadius, ... BackgroundColor3 is the tint.
--
-- Why it is OPT-IN here: it needs the module to be required (it is not a loadstring
-- one-liner) plus EditableImage access, and none of that can be assumed in a CoreGui /
-- gethui executor environment. The "Liquid Glass" devforum asset is not used at all:
-- it renders workspace meshes + Highlights (high graphics only, reported not working
-- on mobile, breaks under full-screen UI) and does not apply to screen-space UI.
--
-- Usage:   Library:SetGlassProvider(require(GlassmorphicUIModule), { Static = false })
--     or   CreateWindow({ GlassModule = <module>, GlassOptions = { Surfaces = { Main = true, Dialog = true } } })
-- If the module is missing / errors, nothing changes and the gradient layer stays.
-- ============================================================================
local GlassProvider, GlassOpts = nil, {}
local GlassTargets = {}
Library.GlassActive = false

local function BgEntryFor(Obj)
	for _, E in ipairs(BgRegistry) do
		if E.Obj == Obj and not E.Prop then return E end
	end
end

local function ApplyGlass(T)
	if not GlassProvider or T.Applied or not T.Obj.Parent then return end
	if type(GlassOpts.Surfaces) == "table" and not GlassOpts.Surfaces[T.Kind] then return end
	if not pcall(GlassProvider.addGlassBackground, T.Obj) then return end
	T.Applied = true
	Library.GlassActive = true
	pcall(function()
		T.Obj:SetAttribute("CornerRadius", UDim.new(0, T.R)) -- match the surface's UICorner
		T.Obj:SetAttribute("SuperEllipseFactor", 2)          -- circular corners like UICorner
		T.Obj:SetAttribute("Transparency", BgCalc(0.35))
	end)
	-- The glass pane replaces the frame's own fill, so stop the fill from showing underneath.
	local E = BgEntryFor(T.Obj)
	if E then E.Base = 1 end
	T.Obj.BackgroundTransparency = 1
	if GlassOpts.Static and type(GlassProvider.pauseUpdates) == "function" then
		pcall(GlassProvider.pauseUpdates, T.Obj)
	end
end

local function RefreshGlass()
	for I = #GlassTargets, 1, -1 do
		local T = GlassTargets[I]
		if not T.Obj.Parent then
			table.remove(GlassTargets, I)
		elseif T.Applied then
			pcall(function() T.Obj:SetAttribute("Transparency", BgCalc(0.35)) end)
		end
	end
end

-- Called by the library for the surfaces that benefit from real glass (main window, dialogs).
function FX.RealGlass(Obj, R, Kind)
	for I = #GlassTargets, 1, -1 do
		if not GlassTargets[I].Obj.Parent then table.remove(GlassTargets, I) end
	end
	local T = { Obj = Obj, R = R, Kind = Kind or "Main" }
	table.insert(GlassTargets, T)
	ApplyGlass(T)
end

function Library:SetGlassProvider(Mod, Opts)
	if type(Mod) ~= "table" or type(Mod.addGlassBackground) ~= "function" then
		warn("[ToolkitUI] SetGlassProvider expects the GlassmorphicUI module (needs addGlassBackground); keeping the gradient glass.")
		return false
	end
	GlassProvider = Mod
	GlassOpts = type(Opts) == "table" and Opts or {}
	for _, T in ipairs(GlassTargets) do ApplyGlass(T) end
	return true
end

function Library:SetBackgroundTransparency(V)
	V = math.clamp(tonumber(V) or 0, 0, 1)
	Library.BackgroundTransparency = V
	PruneBg()
	for _, E in ipairs(BgRegistry) do
		pcall(function() E.Obj[E.Prop or "BackgroundTransparency"] = BgCalc(E.Base) end)
	end
	RefreshGlass()
end

-- Toggle glass mode at runtime (re-applies every registered background)
function Library:SetTransparent(V)
	V = V and true or false
	if Library.Glassmorphism then
		-- glassmorphism always needs the transparent look; remember the wish for when it is switched off
		Library._PreGlassTransparent = V
		Library.Transparent = true
	else
		Library.Transparent = V
	end
	Library:SetBackgroundTransparency(Library.BackgroundTransparency)
end

-- ---- Glassmorphism: acrylic backdrop blur (PC only, MAIN WINDOW only) ----
-- "Window" mode (default): a thin glass part is placed right in front of the camera exactly behind the main window and a
--   DepthOfField effect blurs only that area (the "acrylic" trick), so dialogs, notifications and the rest of the screen stay sharp.
-- "Screen" mode: fallback that blurs the whole game view with a BlurEffect (use it if "Window" does not show on your executor).
-- Everything is created when Glassmorphism is switched on and fully removed (other DepthOfField effects restored) when it is off.
Library.OpenWindows = {}
Library.GlassBlurMode = "Window"
local ScreenBlur
local AcrylicParts = {}
local AcrylicFolder, AcrylicDof
local SavedDof = {}
local AcrylicBind = "ToolkitUIAcrylic"
local ACRYLIC_DISTANCE = 0.001
Library.GlassBlurAdjust = { X = 0, Y = 0, W = 0, H = 0 }   -- manual fine-tune in pixels if your executor is off by a few px

local function DofStrength() return math.clamp(Library.GlassBlurSize / 20, 0, 1) end

local function SetScreenBlur(On)
	if On then
		if not (ScreenBlur and ScreenBlur.Parent) then
			local Ok, B = pcall(function()
				local Old = Lighting:FindFirstChild("ToolkitUIGlassBlur")
				if Old then Old:Destroy() end
				return New("BlurEffect", { Name = "ToolkitUIGlassBlur", Size = 0 }, Lighting)
			end)
			ScreenBlur = Ok and B or nil
		end
		if ScreenBlur then Tween(ScreenBlur, 0.35, { Size = Library.GlassBlurSize }) end
	elseif ScreenBlur then
		local B = ScreenBlur
		ScreenBlur = nil
		local Ok, T = pcall(Tween, B, 0.25, { Size = 0 })
		if Ok and T then
			T.Completed:Connect(function() pcall(function() B:Destroy() end) end)
		else
			pcall(function() B:Destroy() end)
		end
	end
end

local ACRYLIC_STRIPS = 6        -- strips per rounded corner: they follow the window's curve so nothing sticks out

local function PlaceAcrylicRect(Part, Cam, X, Y, W, H)
	if W < 0.5 or H < 0.5 then
		Part.Parent = nil
		return
	end
	-- every corner is projected onto ONE flat plane in front of the camera (perpendicular to where it looks),
	-- so the part lines up with the frame at any position on screen (the old sphere-distance version drifted off-centre)
	local CF = Cam.CFrame
	local Look = CF.LookVector
	local function ToWorld(P)
		local R = Cam:ViewportPointToRay(P.X, P.Y)
		local Dir = R.Direction
		local T = (ACRYLIC_DISTANCE - (R.Origin - CF.Position):Dot(Look)) / Dir:Dot(Look)
		return R.Origin + Dir * T
	end
	local TL = ToWorld(Vector2.new(X, Y))
	local TR = ToWorld(Vector2.new(X + W, Y))
	local BR = ToWorld(Vector2.new(X + W, Y + H))
	Part.Size = Vector3.new((TR - TL).Magnitude, (TR - BR).Magnitude, 0)
	Part.CFrame = CFrame.fromMatrix((TL + BR) / 2, Cam.CFrame.XVector, Cam.CFrame.YVector, Cam.CFrame.ZVector)
	Part.Parent = AcrylicFolder
end

-- The blur area is built from thin horizontal strips that follow the rounded corners of the main frame,
-- so it fits the window exactly and nothing is blurred outside it.
local function AcrylicRender()
	local Cam = workspace.CurrentCamera
	if not Cam then return end
	for Win, Set in pairs(AcrylicParts) do
		local M = Win.BlurFrame or Win.Main
		if not (M and M.Parent) then
			for _, P in ipairs(Set) do P.Parent = nil end
		else
			local Adj = Library.GlassBlurAdjust
			local Pos = M.AbsolutePosition + Vector2.new(Adj.X, Adj.Y)
			local Size = M.AbsoluteSize + Vector2.new(Adj.W, Adj.H)
			local Scale = Win.RootScale and Win.RootScale.Scale or 1
			local R = math.min(MAIN_RADIUS * Scale, Size.X / 2, Size.Y / 2)
			local K = ACRYLIC_STRIPS
			local H = R / K
			for I = 1, K do
				local YTop = (I - 1) * H
				local Dy = R - YTop
				local Inset = R - math.sqrt(math.max(R * R - Dy * Dy, 0))
				local W = Size.X - Inset * 2
				PlaceAcrylicRect(Set[I], Cam, Pos.X + Inset, Pos.Y + YTop, W, H + 0.5)                       -- top strips
				PlaceAcrylicRect(Set[K + I], Cam, Pos.X + Inset, Pos.Y + Size.Y - YTop - H - 0.5, W, H + 0.5) -- bottom strips
			end
			PlaceAcrylicRect(Set[2 * K + 1], Cam, Pos.X, Pos.Y + R, Size.X, Size.Y - R * 2)                      -- middle
		end
	end
end

local function EnsureAcrylicRig()
	if AcrylicDof and AcrylicDof.Parent then return true end
	local Cam = workspace.CurrentCamera
	if not Cam then return false end
	local Ok = pcall(function()
		-- other DepthOfField effects would fight with ours, so pause them while the acrylic is on
		for _, E in ipairs(Lighting:GetChildren()) do
			if E:IsA("DepthOfFieldEffect") and E.Name ~= "ToolkitUIAcrylicDof" and SavedDof[E] == nil then
				SavedDof[E] = E.Enabled
				E.Enabled = false
			end
		end
		AcrylicFolder = Cam:FindFirstChild("ToolkitUIAcrylic") or New("Folder", { Name = "ToolkitUIAcrylic" }, Cam)
		AcrylicDof = New("DepthOfFieldEffect", {
			Name = "ToolkitUIAcrylicDof", FarIntensity = 0, FocusDistance = 0.05, InFocusRadius = 0.1, NearIntensity = DofStrength(),
		}, Lighting)
	end)
	if Ok then
		pcall(function() RunService:BindToRenderStep(AcrylicBind, 2000, AcrylicRender) end)
	end
	return Ok and AcrylicDof ~= nil
end

local function ClearAcrylicRig()
	pcall(function() RunService:UnbindFromRenderStep(AcrylicBind) end)
	for Win, Set in pairs(AcrylicParts) do
		for _, P in ipairs(Set) do pcall(function() P:Destroy() end) end
		AcrylicParts[Win] = nil
	end
	if AcrylicDof then pcall(function() AcrylicDof:Destroy() end) AcrylicDof = nil end
	if AcrylicFolder then pcall(function() AcrylicFolder:Destroy() end) AcrylicFolder = nil end
	for E, Was in pairs(SavedDof) do
		pcall(function() E.Enabled = Was end)
		SavedDof[E] = nil
	end
end

local function NewAcrylicPart()
	local Part = New("Part", {
		Name = "Body", Color = Color3.new(0, 0, 0), Material = Enum.Material.Glass, Size = Vector3.new(1, 1, 0),
		Anchored = true, CanCollide = false, Locked = true, CastShadow = false, Transparency = 0.98,
	})
	New("SpecialMesh", { MeshType = Enum.MeshType.Brick, Offset = Vector3.new(0, 0, -0.000001) }, Part)
	return Part
end

local function AddAcrylic(Win)
	if AcrylicParts[Win] or not (Win.BlurFrame or Win.Main) then return end
	if not EnsureAcrylicRig() then return end
	local Set = {}
	for I = 1, ACRYLIC_STRIPS * 2 + 1 do Set[I] = NewAcrylicPart() end
	AcrylicParts[Win] = Set
end

local function RemoveAcrylic(Win)
	local Set = AcrylicParts[Win]
	if Set then
		for _, P in ipairs(Set) do pcall(function() P:Destroy() end) end
		AcrylicParts[Win] = nil
	end
end

local function UpdateGlassBlur()
	local On = Library.GlassEffective and Library.GlassBlurSize > 0
	if Library.GlassBlurMode == "Screen" then
		ClearAcrylicRig()
		SetScreenBlur(On and next(Library.OpenWindows) ~= nil)
		return
	end
	SetScreenBlur(false)
	for Win in pairs(Library.OpenWindows) do
		if On then AddAcrylic(Win) else RemoveAcrylic(Win) end
	end
	for Win in pairs(AcrylicParts) do
		if not (On and Library.OpenWindows[Win]) then RemoveAcrylic(Win) end
	end
	if AcrylicDof then AcrylicDof.NearIntensity = DofStrength() end
	if next(AcrylicParts) == nil then ClearAcrylicRig() end
end

-- Returns true when the full glass look is really on (PC). On mobile it only switches on Transparent mode and returns false.
function Library:SetGlassmorphism(V)
	V = V and true or false
	if V ~= Library.Glassmorphism then
		Library.Glassmorphism = V
		if V then
			Library._PreGlassTransparent = Library.Transparent
			Library.Transparent = true
		else
			if Library._PreGlassTransparent ~= nil then Library.Transparent = Library._PreGlassTransparent end
			Library._PreGlassTransparent = nil
		end
	end
	Library.GlassEffective = Library.Glassmorphism and Library.IsPC
	FX.SetLiquid(Library.GlassEffective)
	FX.SetBlurFrames(Library.GlassEffective)
	Library:SetBackgroundTransparency(Library.BackgroundTransparency)
	UpdateGlassBlur()
	return Library.GlassEffective
end

function Library:IsGlassmorphismSupported() return Library.IsPC end

-- Acrylic blur strength for glassmorphism (0 = off, max 40)
function Library:SetGlassBlur(Size)
	Library.GlassBlurSize = math.clamp(tonumber(Size) or 6, 0, 40)
	UpdateGlassBlur()
end

-- Fine-tune the blur frame in pixels: X / Y move it, W / H grow or shrink it (all optional, default 0)
function Library:SetGlassBlurAdjust(X, Y, W, H)
	Library.GlassBlurAdjust = { X = tonumber(X) or 0, Y = tonumber(Y) or 0, W = tonumber(W) or 0, H = tonumber(H) or 0 }
end

-- Lens / refraction edge strength on the glass (0 = none, 1 = strong)
function Library:SetGlassDistortion(V)
	Library.GlassDistortion = math.clamp(tonumber(V) or 0.6, 0, 1)
	FX.SetDistortion(Library.GlassDistortion)
end

-- "Window" (default, blurs only the main window area) or "Screen" (blurs the whole game view)
function Library:SetGlassBlurMode(Mode)
	Library.GlassBlurMode = (tostring(Mode):lower() == "screen") and "Screen" or "Window"
	UpdateGlassBlur()
end

Library._UpdateGlassBlur = UpdateGlassBlur

-- Opacity: 0 = invisible backgrounds, 1 = fully visible
function Library:SetOpacity(V)
	V = math.clamp(tonumber(V) or 1, 0, 1)
	Library:SetBackgroundTransparency(1 - V)
end

function Library:GetOpacity()
	return 1 - Library.BackgroundTransparency
end

local function safeHttpGet(url)
	local ok, res = pcall(function() return game:HttpGet(url) end)
	if ok and type(res) == "string" and #res > 100 then return res end
	local req = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
	if req then
		local ok2, r = pcall(function() return req({ Url = url, Method = "GET" }) end)
		if ok2 and r then
			if type(r) == "string" and #r > 100 then return r end
			if r.Body and type(r.Body) == "string" and #r.Body > 100 then return r.Body end
		end
	end
	if ok and type(res) == "string" then return res end
	return nil
end

-- Understands: { Icons = { name = { Image, ImageRectSize, ImageRectPosition } }, Spritesheets = { ["1"] = "rbxassetid://..." } }
-- and plain { name = <asset / table> } tables.
local function ResolveFromTable(T, Name)
	if type(T) ~= "table" then return nil end
	local Set = T.Icons or T.icons
	local Entry
	if type(Set) == "table" then Entry = Set[Name] end
	if Entry == nil then Entry = rawget(T, Name) end
	if Entry == nil then return nil end
	if type(Entry) ~= "table" then return Entry end
	local Sheets = T.Spritesheets or T.Spritesheet or T.Sheets
	local Img = Entry.Image
	if Img == nil then Img = Entry[1] end
	if type(Sheets) == "table" and Img ~= nil then
		local Sheet = Sheets[tostring(Img)] or Sheets[Img]
		if Sheet ~= nil then
			return { Sheet, {
				ImageRectSize = Entry.ImageRectSize,
				ImageRectPosition = Entry.ImageRectPosition or Entry.ImageRectOffset,
			} }
		end
	end
	return Entry
end

local IconSets = {}

local function LoadIconSet(set)
	if IconSets[set] then return IconSets[set] end
	local S = { ready = false, api = nil, waiters = {}, custom = {}, warned = {} }
	IconSets[set] = S
	task.spawn(function()
		local ok, result = pcall(function()
			local Direct, V2

			-- Source 1: spritesheet table (<set>/dist/Icons.lua)
			local directSrc = safeHttpGet("https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/" .. set .. "/dist/Icons.lua")
			if directSrc and #directSrc > 100 then
				local Fn = loadstring(directSrc)
				if Fn then
					local OkD, T = pcall(Fn)
					if OkD and type(T) == "table" then Direct = T end
				end
			end

			-- Source 2: Main-v2 API (only fetched when source 1 is missing or can't resolve a known icon)
			local needV2 = true
			if Direct then
				for _, Probe in ipairs({ "check", "home", "x" }) do
					if ResolveFromTable(Direct, Probe) ~= nil then needV2 = false break end
				end
			end
			if needV2 then
				local src = safeHttpGet("https://raw.githubusercontent.com/Footagesus/Icons/main/Main-v2.lua")
				if src then
					local Fn = loadstring(src)
					if Fn then
						local OkV, Api = pcall(Fn)
						if OkV and type(Api) == "table" then
							if Api.SetIconsType then pcall(Api.SetIconsType, set) end
							V2 = Api
						end
					end
				end
			end
			if not Direct and not V2 then error("no icon source reachable") end

			return {
				GetIcon = function(name)
					local R = ResolveFromTable(Direct, name)
					if R ~= nil then return R end
					if V2 then
						if V2.GetIcon then
							local OkG, G = pcall(V2.GetIcon, name)
							if OkG and G ~= nil and G ~= name then return G end
						end
						if V2.Icon then
							local OkI, I = pcall(V2.Icon, name, set)
							if OkI and I ~= nil and I ~= name then return I end
						end
					end
					return name
				end,
			}
		end)
		if ok and result then
			S.api = result
		else
			warn("[ToolkitUI] Failed to load icon set '" .. set .. "': " .. tostring(result))
		end
		S.ready = true
		for I = #S.waiters, 1, -1 do
			local W = S.waiters[I]
			S.waiters[I] = nil
			pcall(W)
		end
	end)
	return S
end

local function ParseIcon(Icon)
	if type(Icon) == "number" then return "asset", "rbxassetid://" .. Icon end
	if type(Icon) ~= "string" or Icon == "" then return nil end
	if Icon:match("^%d+$") then return "asset", "rbxassetid://" .. Icon end
	if Icon:find("^rbx") or Icon:find("^http") then return "asset", Icon end
	local set, name = Icon:match("^(%w+):(.+)$")
	if set then return set:lower(), name end
	return "lucide", Icon
end

local function ApplyResolved(Label, V)
	if type(V) == "number" then
		Label.Image = "rbxassetid://" .. V
		return true
	elseif type(V) == "string" then
		if V == "" then return false end
		Label.Image = V
		return true
	elseif type(V) == "table" then
		local Img, Data = V.Image, V
		if type(V[1]) == "string" and type(V[2]) == "table" then
			Img, Data = V[1], V[2]
			if (Img == nil or Img == "") and type(Data.Image) == "string" then Img = Data.Image end
		end
		if type(Img) == "number" then Img = "rbxassetid://" .. Img end
		if type(Img) ~= "string" or Img == "" then return false end
		Label.Image = Img
		if Data.ImageRectSize then
			Label.ImageRectSize = Data.ImageRectSize
			Label.ImageRectOffset = Data.ImageRectPosition or Data.ImageRectOffset or Vector2.new(0, 0)
		end
		return true
	end
	return false
end

local function SetLucide(Label, Icon, Fallback)
	local Kind, Val = ParseIcon(Icon)
	if not Kind then return end
	if Kind == "asset" then
		Label.ImageRectSize = Vector2.new(0, 0)
		Label.ImageRectOffset = Vector2.new(0, 0)
		Label.Image = Val
		if Fallback then Fallback.Visible = false end
		return
	end
	local S = LoadIconSet(Kind)
	local function Try()
		if not Label.Parent then return end
		local V = S.custom[Val]
		if V == nil and S.api then
			local ok, r = pcall(S.api.GetIcon, Val)
			if ok and r ~= nil and r ~= Val then V = r end
		end
		if V ~= nil and ApplyResolved(Label, V) then
			if Fallback then Fallback.Visible = false end
		elseif S.api and not S.warned[Val] then
			S.warned[Val] = true
			warn("[ToolkitUI] icon not found: " .. Kind .. ":" .. tostring(Val))
		end
	end
	if S.ready then Try() else table.insert(S.waiters, Try) end
end

Library.Creator = {
	AddIcons = function(Set, Tbl)
		local S = LoadIconSet(Set)
		for K, V in pairs(Tbl) do S.custom[K] = V end
	end,
}
function Library:SetIcon(Label, Icon, Fallback) SetLucide(Label, Icon, Fallback) end

local function SetBadgeIcon(Img, Fallback, Icon, Tint, Radius, LucideSize)
	local Kind = ParseIcon(Icon)
	if not Kind then return end
	local Round = Img:FindFirstChild("BadgeCorner")
	if not Round then
		Round = New("UICorner", { Name = "BadgeCorner", CornerRadius = UDim.new(0, 1) }, Img)
	end
	if Kind == "asset" then
		Img.ImageColor3 = White
		Img.Size = UDim2.fromScale(1, 1)
		Img.ScaleType = Enum.ScaleType.Crop
		Round.CornerRadius = UDim.new(0, math.clamp(Radius or 1, 1, 16))
	else
		Img.ImageColor3 = Tint or Theme.OnAccent
		Img.Size = LucideSize or UDim2.fromScale(0.6, 0.6)
		Img.ScaleType = Enum.ScaleType.Fit
		Round.CornerRadius = UDim.new(0, 1)
		Img.Image = ""
		if Fallback then Fallback.Visible = true end
	end
	SetLucide(Img, Icon, Fallback)
end

local function IconLabel(Parent, Icon, Size, Color, Props, FallbackText)
	local P = {
		Size = UDim2.fromOffset(Size, Size), BackgroundTransparency = 1, ImageColor3 = Color or Theme.Muted,
		ScaleType = Enum.ScaleType.Fit,
	}
	for K, V in pairs(Props or {}) do P[K] = V end
	local L = New("ImageLabel", P, Parent)
	local FB
	if FallbackText then
		FB = New("TextLabel", {
			AnchorPoint = P.AnchorPoint, Position = P.Position, Size = P.Size, BackgroundTransparency = 1,
			Text = FallbackText, TextColor3 = Color or Theme.Muted, TextSize = math.max(Size - 4, 8), FontFace = FontBold,
			Visible = P.Visible,
		}, Parent)
	end
	SetLucide(L, Icon, FB)
	return L, FB
end

local function AccentButton(Parent, Text, Size, Position, TextSize)
	local B = New("TextButton", {
		Size = Size, Position = Position, BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, AutoButtonColor = false,
		Text = Text, TextColor3 = Theme.OnAccent, TextSize = TextSize or 13, FontFace = FontBold,
	}, Parent)
	Corner(B, CONTROL_RADIUS)
	FX.Depth(B, "Button")
	local S = Stroke(B, Theme.Accent:Lerp(White, 0.4), 1, 0.35, "Soft")
	B.MouseEnter:Connect(function()
		Tween(B, 0.12, { BackgroundColor3 = Theme.Accent:Lerp(White, 0.14) })
		Tween(S, 0.12, { Transparency = 0 })
	end)
	B.MouseLeave:Connect(function()
		Tween(B, 0.12, { BackgroundColor3 = Theme.Accent })
		Tween(S, 0.12, { Transparency = 0.35 })
	end)
	return B, B
end

local function DangerColors()
	return Theme.Red:Lerp(Theme.Bg, 0.78), Theme.Red:Lerp(Theme.Bg, 0.35), Theme.Red:Lerp(White, 0.35)
end

local function IconButton(Parent, Text, Position, HoverColor)
	local B = New("TextButton", {
		Size = UDim2.fromOffset(26, 26), Position = Position, BackgroundColor3 = Theme.Card, BorderSizePixel = 0,
		AutoButtonColor = false, Text = Text, TextColor3 = Theme.Muted, TextSize = 18, FontFace = FontBold,
	}, Parent)
	Corner(B, CONTROL_RADIUS)
	local S = Stroke(B, Theme.StrokeHi, 1, 0, "Soft")
	B.MouseEnter:Connect(function()
		Tween(B, 0.15, { BackgroundColor3 = HoverColor:Lerp(Theme.Bg, 0.7), TextColor3 = Theme.Text })
		Tween(S, 0.15, { Color = HoverColor })
	end)
	B.MouseLeave:Connect(function()
		Tween(B, 0.15, { BackgroundColor3 = Theme.Card, TextColor3 = Theme.Muted })
		Tween(S, 0.15, { Color = Theme.StrokeHi })
	end)
	return B
end

local Rng = Random.new()

local function MakeParticles(Parent, Count)
	local L = {}
	for I = 1, Count do
		local S = Rng:NextInteger(2, 3)
		local X, Y = Rng:NextNumber(), Rng:NextNumber()
		local P = New("Frame", {
			Size = UDim2.fromOffset(S, S), Position = UDim2.fromScale(X, Y),
			BackgroundColor3 = Theme.Muted, BackgroundTransparency = Rng:NextNumber(0.82, 0.94), BorderSizePixel = 0, ZIndex = 1,
		}, Parent)
		Corner(P, 1)
		L[I] = { Obj = P, X = X, Y = Y, Speed = Rng:NextNumber(0.01, 0.03), Drift = Rng:NextNumber(0, 6.28) }
	end
	return L
end

local OrbDefaultImage = "rbxassetid://6014261993"
local OrbPurple = Color3.fromRGB(90, 90, 90)
local OrbRegistry = {}
Library.OrbImages = {}
Library.OrbImageTransparency = nil
Library.OrbsHidden = false

local function StyleOrb(E)
	local Obj = E.Obj
	if not Obj or not Obj.Parent then return end
	Obj.Visible = not Library.OrbsHidden
	local Kind, Val
	local Src = Library.OrbImages[E.Key]
	if Src then Kind, Val = ParseIcon(Src) end
	if Kind == "asset" then
		Obj.Image = Val
		Obj.ImageColor3 = White
		Obj.ScaleType = Enum.ScaleType.Fit
		Obj.ImageRectSize = Vector2.new(0, 0)
		Obj.ImageRectOffset = Vector2.new(0, 0)
		Obj.ImageTransparency = Library.OrbImageTransparency or E.Transparency
	else
		Obj.Image = OrbDefaultImage
		Obj.ImageColor3 = E.Color
		Obj.ScaleType = Enum.ScaleType.Slice
		Obj.SliceCenter = Rect.new(49, 49, 450, 450)
		Obj.ImageTransparency = E.Transparency
	end
end

local function PruneOrbs()
	for I = #OrbRegistry, 1, -1 do
		if OrbRegistry[I].Obj.Parent == nil then table.remove(OrbRegistry, I) end
	end
end

function Library:SetOrbImage(Img, Transparency)
	if type(Img) == "table" then
		Library.OrbImages = { Purple = Img.Purple or Img.Violet or Img[1], Cyan = Img.Cyan or Img[2] }
	elseif Img == nil or Img == "" then
		Library.OrbImages = {}
	else
		Library.OrbImages = { Purple = Img, Cyan = Img }
	end
	if type(Transparency) == "number" then Library.OrbImageTransparency = math.clamp(Transparency, 0, 1) end
	PruneOrbs()
	for _, E in ipairs(OrbRegistry) do StyleOrb(E) end
end

-- Hides every orb (window, notifications, popups, splash). Hidden orbs also stop moving.
function Library:SetOrbsHidden(V)
	Library.OrbsHidden = V and true or false
	PruneOrbs()
	for _, E in ipairs(OrbRegistry) do StyleOrb(E) end
end

local function Orb(Key, X, Y, Size, Transparency, Parent)
	local Obj = New("ImageLabel", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(X, Y),
		Size = UDim2.fromOffset(Size, Size), ZIndex = 1,
	}, Parent)
	local E = { Obj = Obj, Key = Key, Color = Key == "Cyan" and Theme.Cyan or OrbPurple, Transparency = Transparency }
	table.insert(OrbRegistry, E)
	if #OrbRegistry % 60 == 0 then PruneOrbs() end
	StyleOrb(E)
	return Obj
end

local function Ser(V)
	if typeof(V) == "Color3" then return { __c = { V.R, V.G, V.B } } end
	if typeof(V) == "EnumItem" then return V.Name end
	return V
end

local function Deser(V)
	if type(V) == "table" and V.__c then return Color3.new(V.__c[1], V.__c[2], V.__c[3]) end
	return V
end

local Window = {}
Window.__index = Window

local Elements = {}
Elements.__index = Elements

local TabClass = {}
TabClass.__index = TabClass
setmetatable(TabClass, { __index = Elements })

local SectionClass = {}
SectionClass.__index = SectionClass
setmetatable(SectionClass, { __index = Elements })

local SideSection = {}
SideSection.__index = SideSection

function Window:Connect(Signal, Fn)
	local C = Signal:Connect(Fn)
	table.insert(self.Connections, C)
	return C
end

local function IsPointerStart(I)
	return I.UserInputType == MouseButton1 or I.UserInputType == TouchInput
end

local function IsTrackedMove(Tracked, I)
	if not Tracked then return false end
	if Tracked.UserInputType == TouchInput then return I == Tracked end
	return I.UserInputType == MouseMove
end

local function IsTrackedEnd(Tracked, I)
	if not Tracked then return false end
	if Tracked.UserInputType == TouchInput then return I == Tracked end
	return I.UserInputType == MouseButton1
end

local function MakeDraggable(Win, Handle, Target, GetScale, CanDrag, OnMoved)
	local Tracked, Start, StartPos = nil, nil, nil
	Handle.InputBegan:Connect(function(I)
		if Tracked or not IsPointerStart(I) then return end
		if CanDrag and not CanDrag() then return end
		Tracked, Start, StartPos = I, I.Position, Target.Position
	end)
	Win:Connect(UserInputService.InputChanged, function(I)
		if not IsTrackedMove(Tracked, I) then return end
		local D = (I.Position - Start) / GetScale()
		Target.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + D.X, StartPos.Y.Scale, StartPos.Y.Offset + D.Y)
		if OnMoved and D.Magnitude > 4 then OnMoved() end
	end)
	Win:Connect(UserInputService.InputEnded, function(I)
		if IsTrackedEnd(Tracked, I) then Tracked = nil end
	end)
end

-- Only ONE slider / colorpicker drag can be active at a time across the whole UI.
local ActiveDrag = nil

-- OnBegin (optional): when given, it runs at the start of a drag INSTEAD of OnMove, so the value does not jump
-- to the pointer (used by the slider, where only the knob can be dragged).
local function MakeDrag(Win, Hit, OnMove, Page, OnBegin)
	local Tracked = nil
	local Token = { Win = Win }
	local function Pos(I) return Vector2.new(I.Position.X, I.Position.Y + InsetY()) end
	local function Stop()
		Tracked = nil
		if ActiveDrag == Token then ActiveDrag = nil end
		if Page and Page.Parent then Page.ScrollingEnabled = true end
	end
	Hit.Active = true
	Hit.InputBegan:Connect(function(I)
		if Tracked or ActiveDrag or not IsPointerStart(I) then return end
		ActiveDrag = Token
		Tracked = I
		if Page then Page.ScrollingEnabled = false end
		if OnBegin then OnBegin(Pos(I)) else OnMove(Pos(I)) end
	end)
	Win:Connect(UserInputService.InputChanged, function(I)
		if ActiveDrag ~= Token or not IsTrackedMove(Tracked, I) then return end
		-- safety: if the mouse was released outside the window, stop the drag
		if Tracked.UserInputType == MouseButton1 and not UserInputService:IsMouseButtonPressed(MouseButton1) then
			Stop()
			return
		end
		OnMove(Pos(I))
	end)
	Win:Connect(UserInputService.InputEnded, function(I)
		if IsTrackedEnd(Tracked, I) then Stop() end
	end)
end

local function BuildDialog(Host, O)
	O = O or {}
	local D = {}
	local Box, Sc

	function D:Show()
		if Host.Current and Host.Current ~= D then Host.Current:Close(true) end
		if Box then return D end
		Host.Current = D
		Host.Modal.Visible = true
		Tween(Host.Dim, 0.2, { BackgroundTransparency = 0.45 })

		Box = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 360, 0, 0),
			AutomaticSize = AutoY, BackgroundColor3 = Theme.Card, BorderSizePixel = 0, ZIndex = 2, Active = true,
		}, Host.Modal)
		Bg(Box, Glass(0, 0.2))
		Corner(Box, DIALOG_RADIUS)
		Stroke(Box, Theme.Frost, 1.5, 0, "Rim")
		FX.Surface(Box, DIALOG_RADIUS, { Height = 72, Shade = true })
		FX.Liquid(Box, DIALOG_RADIUS, "Full")
		FX.RealGlass(Box, DIALOG_RADIUS, "Dialog")
		Sc = New("UIScale", { Scale = 0.92 }, Box)
		Tween(Sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

		-- moving orbs behind the dialog content
		local Glow = New("CanvasGroup", { Name = "Glow", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, Box)
		Corner(Glow, DIALOG_RADIUS)
		local OrbA = Orb("Purple", 0.1, 0.15, 200, 0.7, Glow)
		local OrbB = Orb("Cyan", 0.95, 0.9, 200, 0.7, Glow)

		local Content = New("Frame", {
			Name = "Content", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
		}, Box)
		Pad(Content, 18, 16, 18, 16)
		List(Content, 12)

		local MyBox = Box
		task.spawn(function()
			local T0, Seed = os.clock(), math.random() * 6.28
			while Box == MyBox and MyBox.Parent do
				if Library.Moving and not Library.OrbsHidden then
					local T = os.clock() - T0 + Seed
					OrbA.Position = UDim2.fromScale(0.1 + math.sin(T * 0.9) * 0.1, 0.15 + math.cos(T * 0.7) * 0.2)
					OrbB.Position = UDim2.fromScale(0.95 + math.cos(T * 0.8) * 0.1, 0.9 + math.sin(T * 0.6) * 0.2)
				end
				RunService.RenderStepped:Wait()
			end
		end)

		local TitleRow = New("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, Content)
		local TX = 0
		if O.Icon then
			IconLabel(TitleRow, O.Icon, 22, Theme.Frost, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }, "•")
			TX = 30
		end
		New("TextLabel", {
			Position = UDim2.fromOffset(TX, 0), Size = UDim2.new(1, -TX, 1, 0), BackgroundTransparency = 1, RichText = true,
			Text = O.Title or "Dialog", TextColor3 = Theme.Text, TextSize = 18, FontFace = FontBlack, TextXAlignment = Left,
		}, TitleRow)
		local Body = O.Content or O.Desc
		if Body then
			New("TextLabel", {
				LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1, RichText = true,
				Text = Body, TextColor3 = Theme.Muted, TextSize = 14, FontFace = FontMed, TextWrapped = true,
				TextXAlignment = Left, TextYAlignment = Enum.TextYAlignment.Top,
			}, Content)
		end

		local Buttons = O.Buttons or {}
		if #Buttons > 0 then
			local Row = New("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, Content)
			List(Row, 8, { FillDirection = Enum.FillDirection.Horizontal })
			local N = #Buttons
			for I, B in ipairs(Buttons) do
				local Size = UDim2.new(1 / N, -8 * (N - 1) / N, 1, 0)
				local Variant = tostring(B.Variant or B.Style or "Primary")
				local Btn
				if Variant == "Primary" then
					Btn = AccentButton(Row, B.Title or "Button", Size, UDim2.new(), 13)
					Btn.LayoutOrder = I
				else
					local BgC, StC, TxC = Theme.Hover, Theme.StrokeHi, Theme.Text
					if Variant == "Danger" then BgC, StC, TxC = DangerColors() end
					Btn = New("TextButton", {
						LayoutOrder = I, Size = Size, BackgroundColor3 = BgC, BackgroundTransparency = Variant == "Tertiary" and 1 or 0,
						BorderSizePixel = 0, AutoButtonColor = false, Text = B.Title or "Button", TextColor3 = TxC, TextSize = 13, FontFace = FontBold,
					}, Row)
					Corner(Btn, CONTROL_RADIUS)
					local BS
					if Variant ~= "Tertiary" then BS = Stroke(Btn, StC, 1.2, 0, "Soft") end
					Btn.MouseEnter:Connect(function()
						Tween(Btn, 0.12, { BackgroundColor3 = BgC:Lerp(White, 0.08) })
						if BS then Tween(BS, 0.12, { Color = StC:Lerp(White, 0.25) }) end
					end)
					Btn.MouseLeave:Connect(function()
						Tween(Btn, 0.12, { BackgroundColor3 = BgC })
						if BS then Tween(BS, 0.12, { Color = StC }) end
					end)
				end
				Btn.MouseButton1Click:Connect(function()
					D:Close()
					Call(B.Callback)
				end)
			end
		end
		return D
	end

	function D:Close(Instant)
		if not Box then return end
		local B, S = Box, Sc
		Box, Sc = nil, nil
		if Host.Current == D then Host.Current = nil end
		if Instant then
			B:Destroy()
			return
		end
		Tween(Host.Dim, 0.15, { BackgroundTransparency = 1 })
		Tween(S, 0.15, { Scale = 0.94 })
		task.delay(0.16, function()
			B:Destroy()
			if not Host.Current then Host.Modal.Visible = false end
		end)
	end

	return D
end

local PopupHost
local function GetPopupHost()
	if PopupHost and PopupHost.Gui.Parent then return PopupHost end
	local Gui = New("ScreenGui", {
		Name = "ToolkitUI_Popup", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000001,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	ParentGui(Gui)
	local Modal = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 40 }, Gui)
	local Dim = New("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		Active = true, ZIndex = 1,
	}, Modal)
	PopupHost = { Gui = Gui, Modal = Modal, Dim = Dim }
	return PopupHost
end

function Library:Popup(O)
	local D = BuildDialog(GetPopupHost(), O)
	D:Show()
	return D
end

local NotifGui, NotifHolder, NotifList, NotifAnim
local NotifWidth = 340
local NotifHeight = 120
local NOTIF_RADIUS = CARD_RADIUS
local NOTIF_GAP = 8
local NotifGlows = {}
local NotifOrder = 0
local NotifActive = {}
local NotifMargin = 16
local NotifSide = "Right"

local function ClampNotifW(W) return math.clamp(tonumber(W) or 340, 200, 600) end
local function ClampNotifH(H) return math.clamp(tonumber(H) or 120, 70, 240) end

local function ApplyNotifLayout()
	if not (NotifHolder and NotifHolder.Parent) then return end
	local IsLeft = NotifSide == "Left"
	NotifHolder.Size = UDim2.new(1, -NotifMargin * 2, 1, -NotifMargin * 2)
	NotifHolder.AnchorPoint = Vector2.new(IsLeft and 0 or 1, 1)
	NotifHolder.Position = UDim2.new(IsLeft and 0 or 1, IsLeft and NotifMargin or -NotifMargin, 1, -NotifMargin)
	NotifList.HorizontalAlignment = IsLeft and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right
end

local function FitNotifs(NewH)
	local Cam = workspace.CurrentCamera
	local Avail = (Cam and Cam.ViewportSize.Y or 720) - NotifMargin * 2
	local function Total()
		local T = NewH
		for _, E in ipairs(NotifActive) do T += E.H + NOTIF_GAP end
		return T
	end
	while #NotifActive > 0 and (#NotifActive >= 5 or Total() > Avail) do
		local Old = table.remove(NotifActive, 1)
		pcall(Old.Dismiss)
	end
end

local function EnsureNotif()
	if NotifGui and NotifGui.Parent then return end
	NotifGui = New("ScreenGui", {
		Name = "ToolkitUI_Notify", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	ParentGui(NotifGui)
	if NotifAnim then pcall(function() NotifAnim:Disconnect() end) end
	local Acc = 0
	NotifAnim = RunService.RenderStepped:Connect(function(Dt)
		Acc += Dt
		if Acc < 1 / 30 then return end
		Acc = 0
		if not (NotifGui and NotifGui.Parent) then return end
		local Now = os.clock()
		for I = #NotifGlows, 1, -1 do
			local G = NotifGlows[I]
			if not G.A.Parent then
				table.remove(NotifGlows, I)
			elseif Library.Moving and not Library.OrbsHidden then
				local T = Now - G.T0 + G.Seed
				G.A.Position = UDim2.fromScale(0.1 + math.sin(T * 0.9) * 0.1, 0.15 + math.cos(T * 0.7) * 0.2)
				G.B.Position = UDim2.fromScale(0.95 + math.cos(T * 0.8) * 0.1, 0.9 + math.sin(T * 0.6) * 0.2)
			end
		end
	end)
	NotifHolder = New("Frame", { Name = "Holder", BackgroundTransparency = 1 }, NotifGui)
	NotifList = List(NotifHolder, NOTIF_GAP, { VerticalAlignment = Enum.VerticalAlignment.Bottom })
	ApplyNotifLayout()
end

function Library:SetNotificationPosition(Side)
	NotifSide = string.find(string.lower(tostring(Side or "")), "left") and "Left" or "Right"
	ApplyNotifLayout()
end

function Library:SetNotificationWidth(W)
	NotifWidth = ClampNotifW(W)
end

function Library:SetNotificationHeight(H)
	NotifHeight = ClampNotifH(H)
end

function Library:SetNotificationSize(W, H)
	if W ~= nil then NotifWidth = ClampNotifW(W) end
	if H ~= nil then NotifHeight = ClampNotifH(H) end
end

function Library:GetNotificationSize()
	return NotifWidth, NotifHeight
end

function Library:SetNotificationLower(V)
	NotifMargin = V and 64 or 16
	ApplyNotifLayout()
end

function Library:Notify(O)
	if type(O) == "string" then O = { Content = O } end
	O = O or {}
	EnsureNotif()
	local Dur = math.max(tonumber(O.Duration) or 4, 0.5)

	local Cam = workspace.CurrentCamera
	local VpW = Cam and Cam.ViewportSize.X or 1280
	local W = math.min(O.Width and ClampNotifW(O.Width) or NotifWidth, math.max(VpW - NotifMargin * 2, 120))
	local H = O.Height and ClampNotifH(O.Height) or NotifHeight
	local OffX = (NotifSide == "Left" and -1 or 1) * (W + 60)
	NotifOrder += 1

	FitNotifs(H)

	local Holder = New("Frame", {
		LayoutOrder = NotifOrder, Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1,
	}, NotifHolder)

	local Card = New("Frame", {
		Position = UDim2.fromOffset(OffX, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Bg, BorderSizePixel = 0,
	}, Holder)
	Bg(Card, Glass(0, 0.12))
	Corner(Card, NOTIF_RADIUS)
	BgStroke(Stroke(Card, Theme.Frost, 1, 0, "Rim"), Glass(0, 0.12))
	FX.Surface(Card, NOTIF_RADIUS, { Height = 44 })
	FX.Liquid(Card, NOTIF_RADIUS, "Light")

	local Glow = New("CanvasGroup", { Name = "Glow", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, Card)
	Corner(Glow, NOTIF_RADIUS)
	local OrbA = Orb("Purple", 0.1, 0.15, 170, 0.7, Glow)
	local OrbB = Orb("Cyan", 0.95, 0.9, 170, 0.7, Glow)
	table.insert(NotifGlows, { A = OrbA, B = OrbB, T0 = os.clock(), Seed = math.random() * 6.28 })

	local Fill = New("Frame", {
		Name = "TimerFill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Soft, BackgroundTransparency = 0.88,
		BorderSizePixel = 0, ZIndex = 1,
	}, Glow)

	local Body = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, Card)
	Pad(Body, 16, 14, 34, 14)
	local TextX = 0
	if O.Icon then
		-- typed notifications keep their status hue (softened toward frost); untyped ones use the frosted icon tone
		local Tint = TypeColors[string.lower(tostring(O.Type or ""))]
		IconLabel(Body, O.Icon, 24, Tint and Tint:Lerp(Theme.Frost, 0.2) or Theme.IconHi, { Position = UDim2.fromOffset(0, 0) }, "•")
		TextX = 36
	end
	local Column = New("Frame", {
		Position = UDim2.fromOffset(TextX, 0), Size = UDim2.new(1, -TextX, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true,
	}, Body)
	List(Column, 4)
	New("TextLabel", {
		LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, RichText = true,
		Text = O.Title or "Notification", TextColor3 = Theme.Text, TextSize = 15, FontFace = FontBold, TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Left, TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.75,
	}, Column)
	if O.Content then
		New("TextLabel", {
			LayoutOrder = 2, Size = UDim2.new(1, 0, 1, -24), BackgroundTransparency = 1, RichText = true,
			Text = O.Content, TextColor3 = Color3.fromRGB(215, 215, 215), TextSize = 13, FontFace = FontMed, TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.75,
		}, Column)
	end
	New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1, Text = "×", TextColor3 = Theme.Muted, TextSize = 20, FontFace = FontBold, ZIndex = 4,
	}, Card)

	local Entry = { H = H }
	local Gone = false
	local function Dismiss()
		if Gone then return end
		Gone = true
		local I = table.find(NotifActive, Entry)
		if I then table.remove(NotifActive, I) end
		local T = Tween(Card, 0.25, { Position = UDim2.fromOffset(OffX, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		T.Completed:Connect(function() Holder:Destroy() end)
	end
	Entry.Dismiss = Dismiss
	table.insert(NotifActive, Entry)

	Tween(Card, 0.35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	Tween(Fill, Dur, { Size = UDim2.new(0, 0, 1, 0) }, Enum.EasingStyle.Linear)
	task.delay(Dur, Dismiss)
	New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 6 }, Card).MouseButton1Click:Connect(Dismiss)

	return { Close = Dismiss }
end

function Elements:_Next()
	self._n += 1
	return self._n
end

function Elements:_NewGroup()
	local Frame = New("Frame", {
		Name = "Group", LayoutOrder = self:_Next(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
		BackgroundColor3 = Theme.Card, BorderSizePixel = 0,
	}, self.Parent)
	Bg(Frame, Glass(0, 0.35))
	Corner(Frame, GROUP_RADIUS)
	FX.Depth(Frame, "Panel")
	local GS = Stroke(Frame, Theme.StrokeHi, 1, 0, "Soft")
	List(Frame, 0)
	local G = { Frame = Frame, Stroke = GS, n = 0 }
	self._group = G
	return G
end

local function RefreshGroup(G)
	if not G or not G.Frame then return end
	local Rows = {}
	for _, R in ipairs(G.Frame:GetChildren()) do
		if R:IsA("Frame") and R:GetAttribute("Row") then table.insert(Rows, R) end
	end
	if #Rows == 0 then
		G.Frame:Destroy()
		return
	end
	table.sort(Rows, function(A, B) return A.LayoutOrder < B.LayoutOrder end)
	for I, R in ipairs(Rows) do
		local S = R:FindFirstChild("Sep")
		if S then S.Visible = I > 1 end
	end
end

function Elements:_Card(O, RightW, Clickable, Standalone)
	RightW = RightW or 0
	local G = self._group
	if Standalone or not G or not G.Frame.Parent then G = self:_NewGroup() end
	if Standalone then self._group = nil end
	G.n += 1

	local Root = New("Frame", {
		Name = "Element", LayoutOrder = G.n, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1, Active = true,
	}, G.Frame)
	Root:SetAttribute("Row", true)

	local HoverBg = New("Frame", {
		Position = UDim2.fromOffset(4, 3), Size = UDim2.new(1, -8, 1, -6), BackgroundColor3 = Theme.Hover,
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
	}, Root)
	Corner(HoverBg, GROUP_RADIUS - 4) -- nested: parent radius minus the 4px inset
	FX.Hairline(New("Frame", {
		Name = "Sep", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 1), BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0, ZIndex = 2, Visible = G.n > 1,
	}, Root))

	local Card = New("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
	}, Root)
	Pad(Card, 14, 9, 14, 9)
	New("UISizeConstraint", { MinSize = Vector2.new(0, 48) }, Card)
	List(Card, 8, { VerticalAlignment = Enum.VerticalAlignment.Center })

	local Lock = New("TextButton", {
		Name = "LockOverlay", Position = UDim2.fromOffset(4, 3), Size = UDim2.new(1, -8, 1, -6), BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.2, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 20,
	}, Root)
	Corner(Lock, GROUP_RADIUS - 4)
	local LockChip = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 26),
		AutomaticSize = AutoX, BackgroundColor3 = Theme.Card, BorderSizePixel = 0,
	}, Lock)
	Corner(LockChip, FIELD_RADIUS)
	Stroke(LockChip, Theme.Amber, 1, 0.45)
	Pad(LockChip, 9, 0, 10, 0)
	List(LockChip, 6, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	local LockIconWrap = New("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1 }, LockChip)
	IconLabel(LockIconWrap, "lucide:lock", 14, Theme.Amber, { Position = UDim2.fromOffset(0, 0) }, "•")
	local LockLabel = New("TextLabel", {
		LayoutOrder = 2, Size = UDim2.fromOffset(0, 20), AutomaticSize = AutoX, BackgroundTransparency = 1, Text = "Locked",
		TextColor3 = Theme.Text, TextSize = 12, FontFace = FontBold,
	}, LockChip)

	local HeadProps = { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1 }
	if Clickable then
		HeadProps.Text = ""
		HeadProps.AutoButtonColor = false
	end
	local Head = New(Clickable and "TextButton" or "Frame", HeadProps, Card)
	New("UISizeConstraint", { MinSize = Vector2.new(0, 28) }, Head)

	local TextX, Ico = 0, nil
	if O.Icon and O.Icon ~= "" then
		local IS = O.IconSize or 20
		Ico = IconLabel(Head, O.Icon, IS, ParseColor(O.IconColor, Theme.IconHi), { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }, "•")
		TextX = IS + 10
	end

	local Column = New("Frame", {
		Position = UDim2.fromOffset(TextX, 0), Size = UDim2.new(1, -(TextX + (RightW > 0 and RightW + 10 or 0)), 0, 0),
		AutomaticSize = AutoY, BackgroundTransparency = 1,
	}, Head)
	List(Column, 2)
	local Title = New("TextLabel", {
		LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1, RichText = true,
		Text = O.Title or "Element", TextColor3 = Theme.Text, TextSize = 14, FontFace = FontBold, TextWrapped = true, TextXAlignment = Left,
	}, Column)
	local Desc
	if O.Desc then
		Desc = New("TextLabel", {
			LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1, RichText = true,
			Text = O.Desc, TextColor3 = Theme.Muted, TextSize = 12, FontFace = FontMed, TextWrapped = true, TextXAlignment = Left,
		}, Column)
	end

	-- icon: white (or the IconColor hex you set); slightly softer at rest, full strength on hover
	if Ico then Ico.ImageTransparency = 0.2 end
	Root.MouseEnter:Connect(function()
		Tween(HoverBg, 0.12, { BackgroundTransparency = 0.5 })
		if Ico then Tween(Ico, 0.12, { ImageTransparency = 0 }) end
	end)
	Root.MouseLeave:Connect(function()
		Tween(HoverBg, 0.15, { BackgroundTransparency = 1 })
		if Ico then Tween(Ico, 0.15, { ImageTransparency = 0.2 }) end
	end)

	return {
		Root = Root, Card = Card, Head = Head, Title = Title, Desc = Desc, Icon = Ico, Group = G, HoverBg = HoverBg,
		Lock = Lock, LockLabel = LockLabel,
	}
end

local function SetLockText(C, Text)
	Text = tostring(Text or "")
	C.LockLabel.Text = Text
	C.LockLabel.Visible = Text ~= ""
end

function Elements:_Finish(O, Obj, C)
	local Win = self.Win
	Obj.Frame = C.Root
	Obj.Locked = false
	SetLockText(C, O.LockTitle or O.LockedTitle or "Locked")

	function Obj:SetTitle(T) C.Title.Text = T end
	function Obj:SetDesc(T)
		if C.Desc then C.Desc.Text = T end
	end
	function Obj:SetLockTitle(T) SetLockText(C, T) end
	function Obj:Lock(Title)
		Obj.Locked = true
		if Title ~= nil then SetLockText(C, Title) end
		if type(Obj.Close) == "function" then pcall(Obj.Close, Obj) end
		C.Lock.Visible = true
	end
	function Obj:Unlock()
		Obj.Locked = false
		C.Lock.Visible = false
	end
	function Obj:Destroy()
		if O.Flag then Win.FlagElements[O.Flag] = nil end
		local I = table.find(Win._Elements, Obj)
		if I then table.remove(Win._Elements, I) end
		C.Root:Destroy()
		RefreshGroup(C.Group)
	end
	table.insert(Win._Elements, Obj)
	if O.Flag then Win.FlagElements[O.Flag] = Obj end
	if O.Locked then Obj:Lock() end
	return Obj
end

function Elements:Toggle(O)
	O = O or {}
	local Checkbox = O.Type == "Checkbox"
	local C = self:_Card(O, Checkbox and 30 or 54, true)
	local Obj = { Value = false }
	local Render

	if Checkbox then
		local Box = New("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0,
		}, C.Head)
		Corner(Box, FIELD_RADIUS)
		local BS = Stroke(Box, Theme.StrokeHi, 1.5, 0, "Soft")
		local Chk, ChkFB = IconLabel(Box, "check", 14, Theme.OnAccent, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ImageTransparency = 1, ZIndex = 3,
		}, "✓")
		ChkFB.TextTransparency = 1
		ChkFB.TextColor3 = Theme.OnAccent
		ChkFB.ZIndex = 3
		Render = function(V)
			-- checked = solid accent, unchecked = glass-aware
			Box.BackgroundTransparency = V and 0 or BgCalc(Glass(0, 0.45))
			Tween(Box, 0.15, { BackgroundColor3 = V and Theme.Accent or Theme.Bg2 })
			Tween(BS, 0.15, { Color = V and Theme.Accent:Lerp(White, 0.3) or Theme.StrokeHi })
			Tween(Chk, 0.15, { ImageTransparency = V and 0 or 1 })
			Tween(ChkFB, 0.15, { TextTransparency = V and 0 or 1 })
		end
		-- keep it registered so SetBackgroundTransparency / SetTransparent also reach it
		table.insert(BgRegistry, { Obj = Box, Base = function() return Obj.Value and 0 or (Library.Transparent and 0.45 or 0) end })
	else
		local Track = New("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(46, 24),
			BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0,
		}, C.Head)
		Corner(Track, 12)
		FX.Depth(Track, "Button")
		local TS = Stroke(Track, Theme.StrokeHi, 1.5, 0, "Soft")
		local Knob = New("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Theme.Muted, BorderSizePixel = 0, ZIndex = 2,
		}, Track)
		Corner(Knob, 8)
		Render = function(V)
			-- ON = AccentDim stays mostly visible, OFF = glass-aware
			Track.BackgroundTransparency = BgCalc(function()
				if V then return Library.Transparent and 0.25 or 0 end
				return Library.Transparent and 0.45 or 0
			end)
			Tween(Track, 0.18, { BackgroundColor3 = V and Theme.AccentDim or Theme.Bg2 })
			Tween(TS, 0.18, { Color = V and Theme.Accent or Theme.StrokeHi })
			Tween(Knob, 0.18, {
				Position = V and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 4, 0.5, 0),
				BackgroundColor3 = V and Theme.Text or Theme.Muted,
			}, Enum.EasingStyle.Back)
		end
		table.insert(BgRegistry, {
			Obj = Track,
			Base = function()
				if Obj.Value then return Library.Transparent and 0.25 or 0 end
				return Library.Transparent and 0.45 or 0
			end,
		})
	end

	function Obj:Set(V, Silent)
		V = V and true or false
		Obj.Value = V
		Render(V)
		if not Silent then Call(O.Callback, V) end
	end
	C.Head.MouseButton1Click:Connect(function() Obj:Set(not Obj.Value) end)
	local Init = (O.Value == true) or (O.Default == true)
	Obj:Set(Init, not Init)
	return self:_Finish(O, Obj, C)
end

function Elements:Button(O)
	O = O or {}
	local Text = O.Text or O.ButtonText or O.Label
	if Text ~= nil then Text = tostring(Text) end
	local Danger = O.Danger == true or string.lower(tostring(O.Variant or O.Style or "")) == "danger"
	local RightW = Text and (#Text * 8 + 30 + (O.ButtonIcon and 22 or 0)) or 40
	local C = self:_Card(O, RightW, true)
	local Obj = {}

	local FillC, StrokeC, TextC
	if Danger then
		FillC, StrokeC, TextC = DangerColors()
	else
		FillC, StrokeC, TextC = Theme.Accent, Theme.Accent:Lerp(White, 0.4), Theme.OnAccent
	end

	local Chip = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(Text and 0 or 38, 28),
		AutomaticSize = Text and AutoX or Enum.AutomaticSize.None, BackgroundColor3 = FillC, BorderSizePixel = 0,
	}, C.Head)
	Corner(Chip, CONTROL_RADIUS)
	FX.Depth(Chip, "Button")
	local CS = Stroke(Chip, StrokeC, 1.2, Danger and 0.1 or 0.35, "Soft")
	if Text then
		Pad(Chip, 12, 0, 12, 0)
		local Inner = New("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = AutoX, BackgroundTransparency = 1 }, Chip)
		List(Inner, 6, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
		if O.ButtonIcon then
			local Wrap = New("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1 }, Inner)
			IconLabel(Wrap, O.ButtonIcon, 14, TextC, { Position = UDim2.fromOffset(0, 0) }, "•")
		end
		New("TextLabel", {
			LayoutOrder = 2, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = AutoX, BackgroundTransparency = 1, Text = Text,
			TextColor3 = TextC, TextSize = 13, FontFace = FontBold,
		}, Inner)
	else
		IconLabel(Chip, "chevron-right", 15, TextC, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, ">")
	end

	C.Head.MouseEnter:Connect(function()
		Tween(Chip, 0.12, { BackgroundColor3 = FillC:Lerp(White, 0.12) })
		Tween(CS, 0.12, { Transparency = 0 })
	end)
	C.Head.MouseLeave:Connect(function()
		Tween(Chip, 0.15, { BackgroundColor3 = FillC })
		Tween(CS, 0.15, { Transparency = Danger and 0.1 or 0.35 })
	end)
	C.Head.MouseButton1Click:Connect(function()
		Chip.BackgroundColor3 = FillC:Lerp(White, 0.3)
		Tween(Chip, 0.25, { BackgroundColor3 = FillC })
		Call(O.Callback)
	end)
	function Obj:SetText(T)
		for _, D in ipairs(Chip:GetDescendants()) do
			if D:IsA("TextLabel") then D.Text = tostring(T) break end
		end
	end
	return self:_Finish(O, Obj, C)
end

function Elements:Slider(O)
	O = O or {}
	local V = type(O.Value) == "table" and O.Value or {}
	local Min, Max = V.Min or O.Min or 0, V.Max or O.Max or 100
	local Default = V.Default
	if Default == nil then Default = O.Default end
	if Default == nil and type(O.Value) == "number" then Default = O.Value end
	local Step = O.Step or 1
	local C = self:_Card(O, 80)
	local Obj = { Value = Min }

	local ValueBox = New("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(80, 20),
		BackgroundTransparency = 1, Text = "", TextColor3 = Theme.Accent, TextSize = 14, FontFace = FontBold, TextXAlignment = Right,
		ClearTextOnFocus = false, TextEditable = O.IsTextbox == true, TextTruncate = Enum.TextTruncate.AtEnd,
	}, C.Head)
	local Holder = New("Frame", {
		LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1,
	}, C.Card)
	local Track = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.new(1, -18, 0, 6),
		BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0,
	}, Holder)
	Corner(Track, 3)
	local Fill = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0 }, Track)
	Corner(Fill, 3)
	FX.Depth(Fill, "Bar")
	local Knob = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Theme.Text, BorderSizePixel = 0, ZIndex = 2,
	}, Track)
	Corner(Knob, 7)
	Stroke(Knob, Theme.Accent, 2)
	-- Only the knob (the drag handle) can be dragged. This invisible, slightly larger area makes it easy to grab on touch.
	local KnobHit = New("Frame", {
		Name = "DragHandle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Active = true,
	}, Knob)

	local Decimals = #(tostring(Step):match("%.(%d+)") or "")
	function Obj:Set(Val, Silent)
		local Prev = Obj.Value
		Val = tonumber(Val) or Min
		Val = math.clamp(math.floor((Val - Min) / Step + 0.5) * Step + Min, Min, Max)
		Val = tonumber(string.format("%." .. Decimals .. "f", Val))
		Obj.Value = Val
		local R = (Val - Min) / math.max(Max - Min, 1e-9)
		Tween(Fill, 0.08, { Size = UDim2.fromScale(R, 1) })
		Tween(Knob, 0.08, { Position = UDim2.fromScale(R, 0.5) })
		ValueBox.Text = tostring(Val) .. (O.Suffix or "")
		if not Silent and Val ~= Prev then Call(O.Callback, Val) end
	end
	function Obj:SetMax(N)
		Max = N
		Obj:Set(Obj.Value, true)
	end
	function Obj:SetMin(N)
		Min = N
		Obj:Set(Obj.Value, true)
	end

	ValueBox.FocusLost:Connect(function()
		local N = tonumber(ValueBox.Text:match("-?%d+%.?%d*"))
		Obj:Set(N or Obj.Value)
	end)

	local GrabOffset = 0
	MakeDrag(self.Win, KnobHit, function(P)
		local R = math.clamp((P.X - GrabOffset - Track.AbsolutePosition.X) / math.max(Track.AbsoluteSize.X, 1), 0, 1)
		Obj:Set(Min + (Max - Min) * R)
	end, self.Page, function(P)
		-- remember where on the knob it was grabbed so the knob follows the pointer without jumping
		GrabOffset = P.X - (Knob.AbsolutePosition.X + Knob.AbsoluteSize.X / 2)
	end)

	Obj:Set(Default or Min, Default == nil)
	return self:_Finish(O, Obj, C)
end

function Elements:Dropdown(O)
	O = O or {}
	local Multi = O.Multi == true
	local Values = O.Values or {}
	local C = self:_Card(O, 150)
	local Obj = { Value = Multi and {} or nil, Values = Values }
	local Open = false

	local Pill = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(140, 28),
		BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, C.Head)
	Bg(Pill, Glass(0, 0.4))
	Corner(Pill, CONTROL_RADIUS)
	FX.Depth(Pill, "Button")
	local PillStroke = Stroke(Pill, Theme.StrokeHi, 1, 0, "Soft")
	local ValueLabel = New("TextLabel", {
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -32, 1, 0), BackgroundTransparency = 1, Text = "",
		TextColor3 = Theme.Text, TextSize = 12, FontFace = FontMed, TextXAlignment = Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, Pill)
	local Chevron = IconLabel(Pill, "chevron-down", 14, Theme.Muted, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0) }, "v")

	Pill.MouseEnter:Connect(function()
		if Open then return end
		Tween(PillStroke, 0.15, { Color = Theme.Accent })
		Tween(Pill, 0.15, { BackgroundColor3 = Theme.Hover })
	end)
	Pill.MouseLeave:Connect(function()
		if Open then return end
		Tween(PillStroke, 0.15, { Color = Theme.StrokeHi })
		Tween(Pill, 0.15, { BackgroundColor3 = Theme.Bg2 })
	end)

	local Holder = New("Frame", {
		LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, ClipsDescendants = true, Visible = false,
		Active = true,
	}, C.Card)
	Bg(Holder, Glass(0, 0.25))
	Corner(Holder, CONTROL_RADIUS)
	Stroke(Holder, Theme.Accent, 1, 0.3, "Soft")
	FX.Surface(Holder, CONTROL_RADIUS, { Height = 28, Z = 1 })
	local Scroll = New("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Accent, CanvasSize = UDim2.new(), AutomaticCanvasSize = AutoY,
		ScrollingDirection = Enum.ScrollingDirection.Y, Active = true,
	}, Holder)
	Pad(Scroll, 4, 4, 4, 4)
	List(Scroll, 2)

	local Buttons = {}
	local ContentH = 0
	local function Height() return math.min(math.max(ContentH, 32), 160) + 8 end

	local function NameOf(Item)
		if Item == nil then return nil end
		if type(Item) == "table" then
			if Item.Title == nil then return nil end
			return tostring(Item.Title)
		end
		return tostring(Item)
	end

	local function Paint(B)
		local Col, T = Theme.Hover, 1
		if B.Locked then
			T = 1
		elseif B.Down then
			Col, T = Theme.Accent, 0.5
		elseif B.On then
			Col, T = Theme.Accent, B.Hover and 0.6 or 0.75
		elseif B.Hover then
			Col, T = Theme.Hover, 0
		end
		Tween(B.Btn, 0.1, { BackgroundColor3 = Col, BackgroundTransparency = T })
		B.Accent.Visible = (B.On or B.Hover or B.Down) and not B.Locked
		if not B.Locked then
			B.Lbl.TextColor3 = (B.On or B.Hover or B.Down) and Theme.Text or Theme.Muted
		end
	end

	local function SetOpen(Val)
		Open = Val
		Obj.Opened = Val
		if Val then
			Holder.Visible = true
			Tween(Holder, 0.25, { Size = UDim2.new(1, 0, 0, Height()) })
		else
			Tween(Holder, 0.2, { Size = UDim2.new(1, 0, 0, 0) })
			task.delay(0.22, function()
				if not Open and Holder.Parent then Holder.Visible = false end
			end)
		end
		Tween(Chevron, 0.2, { Rotation = Val and 180 or 0 })
		Tween(PillStroke, 0.2, { Color = Val and Theme.Accent or Theme.StrokeHi })
		Tween(Pill, 0.2, { BackgroundColor3 = Val and Theme.Hover or Theme.Bg2 })
	end

	local function Render()
		if Multi then
			ValueLabel.Text = #Obj.Value == 0 and (O.Placeholder or "None") or table.concat(Obj.Value, ", ")
		else
			ValueLabel.Text = Obj.Value and tostring(Obj.Value) or (O.Placeholder or "Select...")
		end
		for Name, B in pairs(Buttons) do
			local On
			if Multi then On = table.find(Obj.Value, Name) ~= nil else On = Obj.Value == Name end
			B.On = On
			B.Chk.Visible = On
			if B.ChkFB then B.ChkFB.Visible = On and B.Chk.Image == "" end
			if B.Locked then
				B.Lbl.TextColor3 = Theme.Muted
				B.Lbl.TextTransparency = 0.45
			else
				B.Lbl.TextColor3 = On and Theme.Text or Theme.Muted
				B.Lbl.FontFace = On and FontBold or FontMed
			end
			Paint(B)
		end
	end

	function Obj:Select(Val, Silent)
		if Multi then
			local L = {}
			if type(Val) == "table" and Val.Title == nil then
				for _, Item in ipairs(Val) do
					local N = NameOf(Item)
					if N then table.insert(L, N) end
				end
			elseif Val ~= nil then
				local N = NameOf(Val)
				if N then table.insert(L, N) end
			end
			if O.AllowNone == false and #L == 0 then return end
			Obj.Value = L
		else
			if type(Val) == "table" and Val.Title == nil then Val = Val[1] end
			Obj.Value = NameOf(Val)
		end
		Render()
		if not Silent then Call(O.Callback, Multi and table.clone(Obj.Value) or Obj.Value) end
	end
	Obj.Set = Obj.Select

	local function Build()
		for _, Ch in ipairs(Scroll:GetChildren()) do
			if Ch:IsA("GuiObject") then Ch:Destroy() end
		end
		Buttons = {}
		ContentH = 0
		if #Values == 0 then
			New("TextLabel", {
				LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = O.EmptyText or "No options",
				TextColor3 = Theme.Muted, TextSize = 12, FontFace = FontMed,
			}, Scroll)
			ContentH = 32
			return
		end
		for I, Raw in ipairs(Values) do
			if type(Raw) == "table" and Raw.Type == "Divider" then
				local Div = New("Frame", { LayoutOrder = I, Size = UDim2.new(1, 0, 0, 7), BackgroundTransparency = 1 }, Scroll)
				New("Frame", {
					AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.new(1, -12, 0, 1),
					BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0,
				}, Div)
				ContentH += 9
			else
				local Name = NameOf(Raw) or tostring(Raw)
				local ItemLocked = type(Raw) == "table" and Raw.Locked == true
				local LockText = "Locked"
				if ItemLocked then
					local T = Raw.LockTitle
					if T == nil then T = Raw.LockedTitle end
					if T ~= nil then LockText = tostring(T) end
				end

				local Btn = New("TextButton", {
					LayoutOrder = I, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Hover, BackgroundTransparency = 1,
					BorderSizePixel = 0, AutoButtonColor = false, Text = "", ClipsDescendants = true,
				}, Scroll)
				Corner(Btn, CONTROL_RADIUS - 3) -- nested inside the 4px-padded list
				local Accent = New("Frame", {
					AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 16),
					BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Visible = false,
				}, Btn)
				Corner(Accent, 2)
				local Row = New("Frame", {
					Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -38, 1, 0), BackgroundTransparency = 1,
				}, Btn)
				List(Row, 6, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
				if type(Raw) == "table" and Raw.Icon then
					local Wrap = New("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1 }, Row)
					IconLabel(Wrap, Raw.Icon, 14, Theme.Accent, { Position = UDim2.fromOffset(0, 0) })
				end
				local Lbl = New("TextLabel", {
					LayoutOrder = 2, Size = UDim2.fromOffset(0, 28), AutomaticSize = AutoX, BackgroundTransparency = 1, Text = Name,
					TextColor3 = Theme.Muted, TextSize = 13, FontFace = FontMed,
				}, Row)
				if ItemLocked then
					local LockWrap = New("Frame", { LayoutOrder = 3, Size = UDim2.fromOffset(0, 28), AutomaticSize = AutoX, BackgroundTransparency = 1 }, Row)
					List(LockWrap, 4, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
					local IconWrap = New("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1 }, LockWrap)
					IconLabel(IconWrap, "lock", 12, Theme.Amber, { Position = UDim2.fromOffset(0, 0) }, "•")
					if LockText ~= "" then
						New("TextLabel", {
							LayoutOrder = 2, Size = UDim2.fromOffset(0, 28), AutomaticSize = AutoX, BackgroundTransparency = 1, Text = LockText,
							TextColor3 = Theme.Amber, TextSize = 11, FontFace = FontBold,
						}, LockWrap)
					end
				end
				local Chk, ChkFB = IconLabel(Btn, "check", 14, Theme.Accent, {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Visible = false,
				}, "✓")

				local B = {
					Btn = Btn, Lbl = Lbl, Chk = Chk, ChkFB = ChkFB, Accent = Accent, Locked = ItemLocked,
					On = false, Hover = false, Down = false,
				}
				Btn.MouseEnter:Connect(function()
					B.Hover = true
					Paint(B)
				end)
				Btn.MouseLeave:Connect(function()
					B.Hover = false
					B.Down = false
					Paint(B)
				end)
				Btn.MouseButton1Down:Connect(function()
					B.Down = true
					Paint(B)
				end)
				Btn.MouseButton1Up:Connect(function()
					B.Down = false
					Paint(B)
				end)
				Btn.MouseButton1Click:Connect(function()
					if ItemLocked then return end
					if type(Raw) == "table" then Call(Raw.Callback) end
					if Multi then
						local L = table.clone(Obj.Value)
						local Idx = table.find(L, Name)
						if Idx then table.remove(L, Idx) else table.insert(L, Name) end
						Obj:Select(L)
					else
						if O.AllowNone == true and Obj.Value == Name then Obj:Select(nil) else Obj:Select(Name) end
						SetOpen(false)
					end
				end)
				Buttons[Name] = B
				ContentH += 32
			end
		end
	end

	function Obj:Refresh(NewValues)
		Values = NewValues or {}
		Obj.Values = Values
		Build()
		local Keep = Obj.Value
		if Multi then
			local L = {}
			for _, N in ipairs(Keep) do
				if Buttons[N] then table.insert(L, N) end
			end
			Obj.Value = L
		elseif Keep and not Buttons[Keep] then
			Obj.Value = nil
		end
		Render()
		if Open then Tween(Holder, 0.2, { Size = UDim2.new(1, 0, 0, Height()) }) end
	end
	function Obj:Open() SetOpen(true) end
	function Obj:Close() SetOpen(false) end
	function Obj:Toggle() SetOpen(not Open) end

	Pill.MouseButton1Click:Connect(function() SetOpen(not Open) end)
	Build()
	local Init = O.Value
	if Init == nil then Init = O.Default end
	Obj:Select(Init, Init == nil)
	return self:_Finish(O, Obj, C)
end

function Elements:Input(O)
	O = O or {}
	local Textarea = O.Type == "Textarea"
	local Obj = { Value = "" }
	local C = self:_Card(O, Textarea and 0 or 170)

	local Pill
	if Textarea then
		Pill = New("Frame", {
			LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, ClipsDescendants = true,
		}, C.Card)
	else
		Pill = New("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(170, 28),
			BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, ClipsDescendants = true,
		}, C.Head)
	end
	Bg(Pill, Glass(0, 0.4))
	Corner(Pill, FIELD_RADIUS)
	FX.Depth(Pill, "Button")
	local PS = Stroke(Pill, Theme.StrokeHi, 1, 0, "Soft")

	local TX = 8
	if O.InputIcon then
		IconLabel(Pill, O.InputIcon, 14, Theme.Muted, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, Textarea and 0 or 0.5, Textarea and 14 or 0) })
		TX = 28
	end
	local TB = New("TextBox", {
		Position = UDim2.fromOffset(TX, Textarea and 4 or 0), Size = UDim2.new(1, -(TX + 8), 1, Textarea and -8 or 0),
		BackgroundTransparency = 1, Text = "", PlaceholderText = O.Placeholder or "Enter text...", PlaceholderColor3 = Theme.Muted,
		TextColor3 = Theme.Text, TextSize = 13, FontFace = FontMed, ClearTextOnFocus = O.ClearTextOnFocus == true, TextXAlignment = Left,
		TextYAlignment = Textarea and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center, MultiLine = Textarea, TextWrapped = Textarea,
	}, Pill)
	TB.Focused:Connect(function() Tween(PS, 0.15, { Color = Theme.Accent }) end)

	function Obj:Set(Val, Silent)
		Val = tostring(Val or "")
		TB.Text = Val
		Obj.Value = Val
		if not Silent then Call(O.Callback, Val) end
	end
	function Obj:SetPlaceholder(T) TB.PlaceholderText = T end
	TB.FocusLost:Connect(function()
		Tween(PS, 0.15, { Color = Theme.StrokeHi })
		local Text = TB.Text
		if O.Numeric and Text ~= "" and not tonumber(Text) then
			Text = Obj.Value
		end
		Obj:Set(Text)
	end)
	local Init = O.Value
	if Init == nil then Init = O.Default end
	Obj:Set(Init or "", Init == nil)
	return self:_Finish(O, Obj, C)
end

function Elements:Keybind(O)
	O = O or {}
	local C = self:_Card(O, 96)
	local Obj = { Value = "None" }
	local Listening = false

	local Pill = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(86, 28),
		BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, AutoButtonColor = false, Text = "None", TextColor3 = Theme.Text,
		TextSize = 12, FontFace = FontBold,
	}, C.Head)
	Bg(Pill, Glass(0, 0.4))
	Corner(Pill, FIELD_RADIUS)
	local PS = Stroke(Pill, Theme.StrokeHi, 1, 0, "Soft")

	function Obj:Set(K, Silent)
		if typeof(K) == "EnumItem" then K = K.Name end
		K = tostring(K or "None")
		Obj.Value = K
		Pill.Text = K
		if not Silent then Call(O.ChangedCallback, K) end
	end

	Pill.MouseButton1Click:Connect(function()
		if O.CanChange == false then return end
		Listening = true
		Pill.Text = "..."
		Tween(PS, 0.15, { Color = Theme.Accent })
	end)

	self.Win:Connect(UserInputService.InputBegan, function(I, Processed)
		if Listening then
			if I.UserInputType == Enum.UserInputType.Keyboard then
				Listening = false
				Tween(PS, 0.15, { Color = Theme.StrokeHi })
				Obj:Set(I.KeyCode == Enum.KeyCode.Escape and "None" or I.KeyCode.Name)
			end
			return
		end
		if Processed or Obj.Locked then return end
		if I.UserInputType == Enum.UserInputType.Keyboard and Obj.Value ~= "None" and I.KeyCode.Name == Obj.Value then
			Call(O.Callback, I.KeyCode.Name)
		end
	end)

	local Init = O.Value
	if Init == nil then Init = O.Default end
	Obj:Set(Init or "None", true)
	return self:_Finish(O, Obj, C)
end

function Elements:Colorpicker(O)
	O = O or {}
	local C = self:_Card(O, 44, false)
	local Default = O.Default or Theme.Accent
	local H, S, V = Default:ToHSV()
	local Alpha = O.Transparency or 0
	local HasAlpha = O.Transparency ~= nil
	local Obj = { Value = Default, Transparency = Alpha }
	local Open = false
	local PH = 110
	local TotalH = PH + (HasAlpha and 22 or 0)

	local Swatch = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(36, 22),
		BackgroundColor3 = Default, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, C.Head)
	Corner(Swatch, FIELD_RADIUS)
	Stroke(Swatch, Theme.Frost, 1, 0.6, "Soft")

	local Holder = New("Frame", {
		LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false,
	}, C.Card)

	local SV = New("Frame", { Size = UDim2.new(1, -30, 0, PH), BackgroundColor3 = Color3.fromHSV(H, 1, 1), BorderSizePixel = 0 }, Holder)
	Corner(SV, 6)
	local WhiteOv = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = White, BorderSizePixel = 0 }, SV)
	Corner(WhiteOv, 6)
	New("UIGradient", { Transparency = NumberSequence.new(0, 1) }, WhiteOv)
	local BlackOv = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, SV)
	Corner(BlackOv, 6)
	New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, BlackOv)
	local Cursor = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
	}, SV)
	Corner(Cursor, 6)
	Stroke(Cursor, White, 2)

	local HueBar = New("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(20, PH),
		BackgroundColor3 = White, BorderSizePixel = 0,
	}, Holder)
	Corner(HueBar, 6)
	local Keys = {}
	for I = 0, 6 do table.insert(Keys, ColorSequenceKeypoint.new(I / 6, Color3.fromHSV(I / 6, 1, 1))) end
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Keys) }, HueBar)
	local HueCur = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1, 4, 0, 4),
		BackgroundColor3 = White, BorderSizePixel = 0, ZIndex = 3,
	}, HueBar)
	Corner(HueCur, 2)
	Stroke(HueCur, Color3.new(0, 0, 0), 1, 0.5)

	local AlphaBar, AlphaCur, AlphaGrad
	if HasAlpha then
		AlphaBar = New("Frame", {
			Position = UDim2.fromOffset(0, PH + 8), Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = White, BorderSizePixel = 0,
		}, Holder)
		Corner(AlphaBar, 6)
		AlphaGrad = Gradient(AlphaBar, Default, Theme.Bg, 0)
		AlphaCur = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 4, 1, 4),
			BackgroundColor3 = White, BorderSizePixel = 0, ZIndex = 3,
		}, AlphaBar)
		Corner(AlphaCur, 2)
		Stroke(AlphaCur, Color3.new(0, 0, 0), 1, 0.5)
	end

	local function Render()
		SV.BackgroundColor3 = Color3.fromHSV(H, 1, 1)
		Cursor.Position = UDim2.fromScale(S, 1 - V)
		HueCur.Position = UDim2.fromScale(0.5, H)
		Swatch.BackgroundColor3 = Obj.Value
		if HasAlpha then
			AlphaGrad.Color = ColorSequence.new(Obj.Value, Theme.Bg)
			AlphaCur.Position = UDim2.fromScale(Alpha, 0.5)
		end
	end
	local function Apply(Silent)
		Obj.Value = Color3.fromHSV(H, S, V)
		Obj.Transparency = Alpha
		Render()
		if not Silent then
			if HasAlpha then Call(O.Callback, Obj.Value, Alpha) else Call(O.Callback, Obj.Value) end
		end
	end

	function Obj:Set(Col, Transp, Silent)
		if typeof(Col) ~= "Color3" then return end
		if type(Transp) == "number" then Alpha = Transp elseif type(Transp) == "boolean" then Silent = Transp end
		H, S, V = Col:ToHSV()
		Apply(Silent)
	end

	MakeDrag(self.Win, SV, function(P)
		S = math.clamp((P.X - SV.AbsolutePosition.X) / math.max(SV.AbsoluteSize.X, 1), 0, 1)
		V = 1 - math.clamp((P.Y - SV.AbsolutePosition.Y) / math.max(SV.AbsoluteSize.Y, 1), 0, 1)
		Apply()
	end, self.Page)
	MakeDrag(self.Win, HueBar, function(P)
		H = math.clamp((P.Y - HueBar.AbsolutePosition.Y) / math.max(HueBar.AbsoluteSize.Y, 1), 0, 0.999)
		Apply()
	end, self.Page)
	if HasAlpha then
		MakeDrag(self.Win, AlphaBar, function(P)
			Alpha = math.clamp((P.X - AlphaBar.AbsolutePosition.X) / math.max(AlphaBar.AbsoluteSize.X, 1), 0, 1)
			Apply()
		end, self.Page)
	end

	local function SetOpen(Val)
		Open = Val
		if Val then
			Holder.Visible = true
			Tween(Holder, 0.25, { Size = UDim2.new(1, 0, 0, TotalH) })
		else
			Tween(Holder, 0.2, { Size = UDim2.new(1, 0, 0, 0) })
			task.delay(0.22, function()
				if not Open and Holder.Parent then Holder.Visible = false end
			end)
		end
	end
	function Obj:Open() SetOpen(true) end
	function Obj:Close() SetOpen(false) end
	Swatch.MouseButton1Click:Connect(function() SetOpen(not Open) end)

	Render()
	if O.Default ~= nil then
		if HasAlpha then Call(O.Callback, Obj.Value, Alpha) else Call(O.Callback, Obj.Value) end
	end
	return self:_Finish(O, Obj, C)
end

function Elements:Paragraph(O)
	O = O or {}
	local C = self:_Card({ Title = O.Title, Desc = O.Desc, Icon = O.Image or O.Icon, IconSize = O.ImageSize or 30 }, 0, false, true)
	local Obj = {}

	local Col = O.Color ~= nil and ParseColor(O.Color, nil) or nil
	if Col then
		C.Group.Frame.BackgroundColor3 = Theme.Card:Lerp(Col, 0.14)
		C.Group.Stroke.Color = Col
	end

	local Thumb
	local function MakeThumb(Image, Size)
		if not Image or Image == "" then
			if Thumb then Thumb.Visible = false end
			return
		end
		if not Thumb then
			Thumb = New("ImageLabel", {
				LayoutOrder = 2, Size = UDim2.new(1, 0, 0, Size or 80), BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0,
				ScaleType = Enum.ScaleType.Crop,
			}, C.Card)
			Corner(Thumb, 8)
		end
		Thumb.Visible = true
		Thumb.Size = UDim2.new(1, 0, 0, Size or 80)
		SetLucide(Thumb, Image)
	end
	MakeThumb(O.Thumbnail, O.ThumbnailSize)

	if O.Buttons and #O.Buttons > 0 then
		local Row = New("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1 }, C.Card)
		List(Row, 6, { FillDirection = Enum.FillDirection.Horizontal, Wraps = true })
		for I, B in ipairs(O.Buttons) do
			local Btn = New("TextButton", {
				LayoutOrder = I, Size = UDim2.fromOffset(0, 30), AutomaticSize = AutoX, BackgroundColor3 = Theme.CardHover,
				BorderSizePixel = 0, AutoButtonColor = false, Text = "",
			}, Row)
			Corner(Btn, CONTROL_RADIUS)
			Stroke(Btn, Theme.StrokeHi, 1, 0, "Soft")
			Pad(Btn, 10, 0, 10, 0)
			local Inner = New("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = AutoX, BackgroundTransparency = 1 }, Btn)
			List(Inner, 6, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
			if B.Icon then
				local Wrap = New("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1 }, Inner)
				IconLabel(Wrap, B.Icon, 14, Theme.Accent, { Position = UDim2.fromOffset(0, 0) }, "•")
			end
			New("TextLabel", {
				LayoutOrder = 2, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = AutoX, BackgroundTransparency = 1,
				Text = B.Title or "Button", TextColor3 = Theme.Text, TextSize = 12, FontFace = FontBold,
			}, Inner)
			Btn.MouseButton1Click:Connect(function() Call(B.Callback) end)
		end
	end

	function Obj:SetImage(Image, Size)
		if C.Icon then SetLucide(C.Icon, Image) end
	end
	function Obj:SetThumbnail(Image, Size) MakeThumb(Image, Size) end
	return self:_Finish(O, Obj, C)
end

function Elements:Code(O)
	O = O or {}
	local C = self:_Card({ Title = O.Title or "Code", Icon = O.Icon }, 64, false)
	local Obj = { Value = O.Code or "" }
	local Block = New("Frame", {
		LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundColor3 = Theme.Bg, BorderSizePixel = 0,
	}, C.Card)
	Bg(Block, Glass(0, 0.3))
	Corner(Block, 8)
	Pad(Block, 10, 8, 10, 8)
	local Lbl = New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1, Text = Obj.Value, TextColor3 = Theme.Cyan,
		TextSize = 13, FontFace = FontMono, TextWrapped = true, TextXAlignment = Left, TextYAlignment = Enum.TextYAlignment.Top,
	}, Block)
	local Copy = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(60, 26),
		BackgroundColor3 = Theme.CardHover, BorderSizePixel = 0, AutoButtonColor = false, Text = "COPY", TextColor3 = Theme.Text,
		TextSize = 11, FontFace = FontBold,
	}, C.Head)
	Corner(Copy, CONTROL_RADIUS)
	Stroke(Copy, Theme.StrokeHi, 1, 0, "Soft")
	Copy.MouseButton1Click:Connect(function()
		CopyText(Obj.Value)
		Copy.Text = "COPIED"
		task.delay(1.2, function()
			if Copy.Parent then Copy.Text = "COPY" end
		end)
		Call(O.OnCopy)
	end)
	function Obj:SetCode(T)
		Obj.Value = T
		Lbl.Text = T
	end
	return self:_Finish(O, Obj, C)
end

function Elements:Divider()
	self._group = nil
	return New("Frame", { LayoutOrder = self:_Next(), Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1 }, self.Parent)
end

function Elements:Space(O)
	self._group = nil
	local H = type(O) == "number" and O or (type(O) == "table" and O.Size) or ((type(O) == "table" and O.Columns or 1) * 8)
	return New("Frame", { LayoutOrder = self:_Next(), Size = UDim2.new(1, 0, 0, H), BackgroundTransparency = 1 }, self.Parent)
end

function Elements:Section(O)
	if type(O) == "string" then O = { Title = O } end
	O = O or {}
	self._group = nil
	local Wrap = New("Frame", { LayoutOrder = self:_Next(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1 }, self.Parent)
	Pad(Wrap, 0, 8, 0, 0)
	List(Wrap, 8)

	local Align = ({ Left = Left, Center = Enum.TextXAlignment.Center, Right = Right })[O.TextXAlignment or "Left"] or Left
	local Header = New("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, Wrap)
	Pad(Header, 4, 0, 4, 0)
	local Lbl = New("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = StripRich(O.Title or "Section"), TextColor3 = Theme.Text,
		TextTransparency = O.TextTransparency or 0, TextSize = O.TextSize or 16, FontFace = FontBold, TextXAlignment = Align,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Header)

	local Body = New("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1 }, Wrap)
	List(Body, 8)

	local Sec = setmetatable({ Win = self.Win, Parent = Body, Page = self.Page, _n = 0 }, SectionClass)
	function Sec:SetTitle(T) Lbl.Text = StripRich(T) end
	function Sec:Destroy() Wrap:Destroy() end
	return Sec
end

function Elements:ConfigPanel(O)
	if type(O) == "string" then O = { Title = O } end
	O = O or {}
	local Win = self.Win
	local Sec = self:Section({ Title = O.Title or "Configuration", Icon = O.Icon })
	local Panel = {}

	local NameInput = Sec:Input({
		Title = "Config name",
		Desc = "Type a name, then press Create",
		Placeholder = "my-config",
	})

	local Dd
	local function Selected()
		local V = Dd and Dd.Value
		if type(V) == "string" and V ~= "" then return V end
		return nil
	end

	function Panel:Refresh(Pick)
		Dd:Refresh(Win:GetConfigs())
		if Pick then Dd:Select(Pick, true) end
	end

	Dd = Sec:Dropdown({
		Title = "Saved configs",
		Desc = "Pick one to save, load or delete",
		Placeholder = "Select config",
		EmptyText = "No configs yet",
		Values = Win:GetConfigs(),
	})

	local function Warn(Msg)
		Library:Notify({ Title = "Config", Content = Msg, Type = "warn", Icon = "lucide:info", Duration = 3 })
	end
	local function Good(Msg)
		Library:Notify({ Title = "Config", Content = Msg, Type = "success", Icon = "lucide:check", Duration = 3 })
	end

	Sec:Button({
		Title = "Create Config", Desc = "Makes a new config from the current settings",
		Icon = "lucide:file-plus", Text = "Create",
		Callback = function()
			local Name = Win.ConfigManager:Sanitize(NameInput.Value)
			if Name == "" then return Warn("Enter a config name first.") end
			if Win.ConfigManager:ConfigExists(Name) then return Warn("\"" .. Name .. "\" already exists.") end
			Win:CreateConfig(Name):Save()
			Panel:Refresh(Name)
			NameInput:Set("", true)
			Good("Created \"" .. Name .. "\".")
		end,
	})

	Sec:Button({
		Title = "Save Config", Desc = "Overwrite the selected config",
		Icon = "lucide:save", Text = "Save",
		Callback = function()
			local Name = Selected()
			if not Name then return Warn("Select a config first.") end
			if Win:SaveConfig(Name) then Good("Saved \"" .. Name .. "\".") else Warn("Could not save \"" .. Name .. "\".") end
		end,
	})

	Sec:Button({
		Title = "Load Config", Desc = "Apply the selected config",
		Icon = "lucide:folder-open", Text = "Load",
		Callback = function()
			local Name = Selected()
			if not Name then return Warn("Select a config first.") end
			if Win:LoadConfig(Name) then Good("Loaded \"" .. Name .. "\".") else Warn("Could not load \"" .. Name .. "\".") end
		end,
	})

	Sec:Button({
		Title = "Delete Selected Config", Desc = "Removes it from the list and from disk",
		Icon = "lucide:trash-2", Text = "Delete", Variant = "Danger",
		Callback = function()
			local Name = Selected()
			if not Name then return Warn("Select a config first.") end
			Win:Dialog({
				Title = "DELETE CONFIG", Icon = "lucide:trash-2",
				Content = "Delete \"" .. Name .. "\"? This can't be undone.",
				Buttons = {
					{ Title = "CANCEL", Variant = "Secondary" },
					{
						Title = "DELETE", Variant = "Danger",
						Callback = function()
							Win:DeleteConfig(Name)
							Panel:Refresh()
							Good("Deleted \"" .. Name .. "\".")
						end,
					},
				},
			})
		end,
	})

	Panel.Section, Panel.Dropdown, Panel.Input = Sec, Dd, NameInput
	function Panel:GetSelected() return Selected() end
	return Panel
end

function TabClass:Select(Instant)
	local Win = self.Win
	if self.Locked then return end
	for _, T in ipairs(Win.Tabs) do
		if T ~= self then T:_SetActive(false) end
	end
	self:_SetActive(true, Instant)
	Win.CurrentTab = self
end

function Window:_NextSide()
	self._side += 1
	return self._side
end

local function ShowIcon(Img, Fallback, On)
	if not Img then return end
	Img.Visible = On
	if Fallback then Fallback.Visible = On and Img.Image == "" end
end

function Window:_MakeTab(O, ParentFrame)
	if type(O) == "string" then O = { Title = O } end
	O = O or {}
	local WinRef = self
	local LockTitle = "Locked"
	if O.LockTitle ~= nil then LockTitle = tostring(O.LockTitle) elseif O.LockedTitle ~= nil then LockTitle = tostring(O.LockedTitle) end
	local Tab = setmetatable({ Win = self, _n = 0, Title = O.Title or "Tab", Locked = false, LockTitle = LockTitle }, TabClass)

	local Btn = New("TextButton", {
		LayoutOrder = self:_NextSide(), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "",
	}, ParentFrame)
	Corner(Btn, 7)
	-- selected / hover plate: lighter blue-gray fill + frosted rim, clearly different from the unselected (transparent) state
	local ActiveFill = New("Frame", {
		Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Selected, BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, Btn)
	Corner(ActiveFill, 7)
	FX.Depth(ActiveFill, "Panel")
	local ActStroke = Stroke(ActiveFill, Theme.Frost, 1, 1, "Rim")
	local Bar = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 16),
		BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
	}, Btn)
	Corner(Bar, 2)

	local IconRight = O.IconAlign == "Right"
	local TabIconCol = ParseColor(O.IconColor, Theme.IconHi)      -- white, or the IconColor hex you set
	local Ico, IcoFB
	local TextL = 14
	if O.Icon then
		if IconRight then
			Ico, IcoFB = IconLabel(Btn, O.Icon, 17, TabIconCol, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -11, 0.5, 0), ZIndex = 2 }, "•")
		else
			Ico, IcoFB = IconLabel(Btn, O.Icon, 17, TabIconCol, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), ZIndex = 2 }, "•")
			TextL = 38
		end
	end
	if Ico then Ico.ImageTransparency = 0.4 end
	local LockIco, LockFB = IconLabel(Btn, "lucide:lock", 14, Theme.Amber, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -11, 0.5, 0), Visible = false, ZIndex = 2,
	}, "•")

	local Lbl = New("TextLabel", {
		Position = UDim2.fromOffset(TextL, 0), Size = UDim2.new(1, -(TextL + 10), 1, 0), BackgroundTransparency = 1,
		Text = Tab.Title, TextColor3 = Theme.Muted, TextSize = 13, FontFace = FontBold, TextXAlignment = Left,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2,
	}, Btn)

	local function Reflow()
		local R = 10
		if (Ico and IconRight) or Tab.Locked then R = 36 end
		Lbl.Size = UDim2.new(1, -(TextL + R), 1, 0)
	end
	Reflow()

	local Page = New("ScrollingFrame", {
		Name = "Page_" .. Tab.Title, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.StrokeHi, CanvasSize = UDim2.new(), AutomaticCanvasSize = AutoY,
		ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, Active = true,
	}, self.Content)
	Pad(Page, 3, 3, 12, 3)
	List(Page, 8)

	Tab.Parent, Tab.Page, Tab.TabButton = Page, Page, Btn

	local Selected = false
	function Tab:_SetActive(On, Instant)
		Selected = On
		Tween(ActiveFill, 0.2, { BackgroundTransparency = On and (Library.Transparent and 0.55 or 0) or 1 })
		Tween(ActStroke, 0.2, { Transparency = On and 0 or 1 })
		Tween(Bar, 0.2, { BackgroundTransparency = On and 0 or 1 })
		Tween(Lbl, 0.2, { TextColor3 = On and Theme.Text or Theme.Muted })
		if Ico then Tween(Ico, 0.2, { ImageTransparency = On and 0 or 0.4 }) end
		if On then
			Page.Visible = true
			if not Instant and WinRef._moving ~= false then
				Page.Position = UDim2.fromOffset(0, 12)
				Tween(Page, 0.3, { Position = UDim2.fromOffset(0, 0) })
			else
				Page.Position = UDim2.fromOffset(0, 0)
			end
		else
			Page.Visible = false
		end
	end
	function Tab:Lock(Title)
		Tab.Locked = true
		if Title ~= nil then Tab.LockTitle = tostring(Title) end
		Lbl.TextTransparency = 0.5
		if IconRight then ShowIcon(Ico, IcoFB, false) end
		ShowIcon(LockIco, LockFB, true)
		Reflow()
	end
	function Tab:Unlock()
		Tab.Locked = false
		Lbl.TextTransparency = 0
		ShowIcon(LockIco, LockFB, false)
		if IconRight then ShowIcon(Ico, IcoFB, true) end
		Reflow()
	end
	function Tab:SetTitle(T)
		Tab.Title = T
		Lbl.Text = T
	end
	function Tab:SetLockTitle(T) Tab.LockTitle = tostring(T or "") end
	function Tab:Destroy()
		local I = table.find(self.Win.Tabs, Tab)
		if I then table.remove(self.Win.Tabs, I) end
		if self.Win.CurrentTab == Tab then self.Win.CurrentTab = nil end
		Page:Destroy()
		Btn:Destroy()
	end
	if O.Locked == true then Tab:Lock() end

	Btn.MouseEnter:Connect(function()
		if Tab.Locked or Selected then return end
		Tween(Lbl, 0.12, { TextColor3 = Theme.Text })
		if Ico then Tween(Ico, 0.12, { ImageTransparency = 0 }) end
		Tween(ActiveFill, 0.12, { BackgroundTransparency = Library.Transparent and 0.75 or 0.45 })
		Tween(ActStroke, 0.12, { Transparency = 0.5 })
	end)
	Btn.MouseLeave:Connect(function()
		if Tab.Locked or Selected then return end
		Tween(Lbl, 0.12, { TextColor3 = Theme.Muted })
		if Ico then Tween(Ico, 0.12, { ImageTransparency = 0.4 }) end
		Tween(ActiveFill, 0.12, { BackgroundTransparency = 1 })
		Tween(ActStroke, 0.12, { Transparency = 1 })
	end)
	Btn.MouseButton1Click:Connect(function()
		if Tab.Locked then
			Library:Notify({
				Title = Tab.Title, Content = Tab.LockTitle ~= "" and Tab.LockTitle or "Locked", Icon = "lucide:lock", Type = "warn", Duration = 2.5,
			})
			return
		end
		Tab:Select()
	end)

	table.insert(self.Tabs, Tab)
	-- No auto-select: the content stays blank until Tab:Select() is called (or the user clicks a tab)
	return Tab
end

function Window:Tab(O) return self:_MakeTab(O, self.Sidebar) end

function Window:Section(O)
	if type(O) == "string" then O = { Title = O } end
	O = O or {}
	local Wrap = New("Frame", { LayoutOrder = self:_NextSide(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1 }, self.Sidebar)
	List(Wrap, 4)
	local Header = New("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, Wrap)
	New("TextLabel", {
		Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -14, 1, 0), BackgroundTransparency = 1,
		Text = StripRich(O.Title or "Section"), TextColor3 = Theme.Muted, TextSize = 16, FontFace = FontBold,
		TextXAlignment = Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, Header)
	local Body = New("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1 }, Wrap)
	List(Body, 4)

	local Sec = setmetatable({ Win = self }, SideSection)
	function Sec:Tab(TO) return self.Win:_MakeTab(TO, Body) end
	return Sec
end

function Window:Divider()
	return New("Frame", {
		LayoutOrder = self:_NextSide(), Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0,
	}, self.Sidebar)
end

function Window:Space(O)
	return New("Frame", { LayoutOrder = self:_NextSide(), Size = UDim2.new(1, 0, 0, type(O) == "number" and O or 8), BackgroundTransparency = 1 }, self.Sidebar)
end

function Window:SelectTab(Index)
	local T = self.Tabs[Index]
	if T then T:Select() end
end

function Window:SetStatus() end

function Window:Open()
	if self.Destroyed or not self.Hidden then return end
	self.Hidden = false
	self.Root.Visible = true
	self.Bubble.Visible = false
	Library.OpenWindows[self] = true
	Library._UpdateGlassBlur()
	Call(self._onOpen)
end

function Window:Close()
	if self.Destroyed or self.Hidden then return end
	self.Hidden = true
	self.Root.Visible = false
	self.Bubble.Visible = self._openButton
	Library.OpenWindows[self] = nil
	Library._UpdateGlassBlur()
	Call(self._onClose)
end

function Window:Toggle()
	if self.Hidden then self:Open() else self:Close() end
end

function Window:SetToggleKey(Key) self.ToggleKey = Key end
function Window:OnClose(Fn) self._onClose = Fn end
function Window:OnOpen(Fn) self._onOpen = Fn end
function Window:OnDestroy(Fn) self._onDestroy = Fn end

function Window:OpenButton(O)
	O = O or {}
	if O.Enabled ~= nil then
		self._openButton = O.Enabled and true or false
		if self.Hidden then self.Bubble.Visible = self._openButton end
	end
	if O.Draggable ~= nil then
		self._bubbleDraggable = O.Draggable and true or false
	end
	if O.Icon ~= nil and O.Icon ~= "" then
		SetBadgeIcon(self.BubbleImg, self.BubbleFB, O.Icon, White, 24, UDim2.fromOffset(24, 24))
	end
	return self
end
Window.EditOpenButton = Window.OpenButton

function Window:SetIcon(Icon)
	if Icon == nil or Icon == "" then return end
	SetBadgeIcon(self.LogoImg, self.LogoFB, Icon, White, 9, UDim2.fromScale(0.6, 0.6))
	if self.SplashImg and self.SplashImg.Parent then
		SetBadgeIcon(self.SplashImg, self.SplashFB, Icon, self.SplashIconColor or White, 18, UDim2.fromScale(0.6, 0.6))
	end
end

function Window:SetTitle(T)
	self.TitleLabel.Text = T
end

function Window:SetAuthor(T)
	self.AuthorLabel.Text = T
end

function Window:SetBackgroundTransparency(V)
	Library:SetBackgroundTransparency(V)
end

function Window:SetTransparent(V)
	Library:SetTransparent(V)
end

-- Opacity: 0 = invisible backgrounds, 1 = fully visible
function Window:SetOpacity(V)
	Library:SetOpacity(V)
end

-- Glassmorphism (PC only). Returns true if the full glass look is on; false on mobile (only Transparent mode is applied).
function Window:SetGlassmorphism(V) return Library:SetGlassmorphism(V) end
function Window:IsGlassmorphismSupported() return Library:IsGlassmorphismSupported() end
function Window:SetGlassBlur(V) Library:SetGlassBlur(V) end
function Window:SetGlassBlurMode(V) Library:SetGlassBlurMode(V) end
function Window:SetGlassDistortion(V) Library:SetGlassDistortion(V) end
function Window:SetGlassBlurAdjust(X, Y, W, H) Library:SetGlassBlurAdjust(X, Y, W, H) end

function Window:Tag(O)
	if type(O) == "string" then O = { Title = O } end
	O = O or {}
	self._tagN += 1
	local Col = ParseColor(O.Color, Theme.Accent)
	local Rec = {
		Title = tostring(O.Title or "Tag"), HasIcon = O.Icon ~= nil and O.Icon ~= "",
		MinTextW = tonumber(O.MinWidth) or 0,
	}

	local Tag = New("Frame", {
		Name = "Tag", LayoutOrder = self._tagN, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(40, 24), BackgroundColor3 = ParseColor(O.BackgroundColor, Col),
		BackgroundTransparency = O.Transparency or 0.82, BorderSizePixel = 0,
	}, self.TagFrame)
	Corner(Tag, O.Radius or FIELD_RADIUS)
	local TS = Stroke(Tag, ParseColor(O.BorderColor, Col), 1, 0.1)

	local Wrap = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(13, 13),
		BackgroundTransparency = 1, Visible = Rec.HasIcon,
	}, Tag)
	local Ico
	if Rec.HasIcon then Ico = IconLabel(Wrap, O.Icon, 13, ParseColor(O.TextColor, Col:Lerp(White, 0.4)), nil, "•") end
	local Lbl = New("TextLabel", {
		Size = UDim2.fromOffset(20, 24), BackgroundTransparency = 1, Text = Rec.Title,
		TextColor3 = ParseColor(O.TextColor, Col:Lerp(White, 0.5)), TextSize = 12, FontFace = FontBold, TextXAlignment = Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Tag)

	Rec.Frame, Rec.Wrap, Rec.Lbl = Tag, Wrap, Lbl
	local function Measure()
		local Ok, S = pcall(function()
			local P = Instance.new("GetTextBoundsParams")
			P.Text, P.Font, P.Size, P.Width = Rec.Title, FontBold, 12, 1000
			return TextService:GetTextBoundsAsync(P)
		end)
		Rec.TextW = math.max((Ok and S and S.X or #Rec.Title * 7) + 2, Rec.MinTextW)
	end
	Measure()
	table.insert(self._tags, Rec)
	if self._layoutTags then self._layoutTags() end

	local Win = self
	local Obj = {}
	function Obj:SetTitle(T)
		Rec.Title = tostring(T)
		Lbl.Text = Rec.Title
		Measure()
		if Win._layoutTags then Win._layoutTags() end
	end
	function Obj:SetColor(C)
		local NC = ParseColor(C, nil)
		if not NC then return end
		Tag.BackgroundColor3 = NC
		TS.Color = NC
		Lbl.TextColor3 = NC:Lerp(White, 0.5)
		if Ico then Ico.ImageColor3 = NC:Lerp(White, 0.4) end
	end
	function Obj:Destroy()
		local I = table.find(Win._tags, Rec)
		if I then table.remove(Win._tags, I) end
		Tag:Destroy()
		if Win._layoutTags then Win._layoutTags() end
	end
	return Obj
end

function Window:Notify(O) return Library:Notify(O) end

function Window:Dialog(O)
	local D = BuildDialog(self.Host, O)
	D:Show()
	return D
end

function Window:LockAll() for _, E in ipairs(self._Elements) do E:Lock() end end
function Window:UnlockAll() for _, E in ipairs(self._Elements) do E:Unlock() end end
function Window:GetLocked()
	local L = {}
	for _, E in ipairs(self._Elements) do if E.Locked then table.insert(L, E) end end
	return L
end
function Window:GetUnlocked()
	local L = {}
	for _, E in ipairs(self._Elements) do if not E.Locked then table.insert(L, E) end end
	return L
end
function Window:GetAllElements() return self._Elements end

function Window:CreateConfig(Name)
	return self.ConfigManager:CreateConfig(Name)
end

function Window:SaveConfig(Name)
	Name = Name or "default"
	local Cfg = self.ConfigManager.Configs[Name] or self.ConfigManager:CreateConfig(Name)
	return Cfg:Save()
end

function Window:LoadConfig(Name)
	Name = Name or "default"
	local Cfg = self.ConfigManager.Configs[Name] or self.ConfigManager:CreateConfig(Name)
	return Cfg:Load()
end

function Window:DeleteConfig(Name)
	return self.ConfigManager:DeleteConfig(Name)
end

function Window:GetConfigs()
	return self.ConfigManager:AllConfigs()
end

function Window:SetMovingAnimation(V)
	self._moving = V ~= false
	Library.Moving = self._moving
	if not self._moving and self._resetMotion then self._resetMotion() end
end

function Window:SetOrbImage(Img, Transparency)
	Library:SetOrbImage(Img, Transparency)
end

function Window:SetOrbsHidden(V)
	Library:SetOrbsHidden(V)
end

-- Show / hide the static reflection layers (cheap quality switch for low-end devices).
function Window:SetReflections(V)
	Library:SetReflections(V)
end

function Window:SetParticles(V)
	self._particles = V ~= false
	if self._applyParticles then self._applyParticles() end
end

function Window:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	if ActiveDrag and ActiveDrag.Win == self then ActiveDrag = nil end
	Library.OpenWindows[self] = nil
	Library._UpdateGlassBlur()
	Call(self._onDestroy)
	for _, C in ipairs(self.Connections) do pcall(function() C:Disconnect() end) end
	local Ok, T = pcall(Tween, self.RootScale, 0.25, { Scale = 0.8 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	local function Kill() pcall(function() self.Gui:Destroy() end) end
	if Ok and T then T.Completed:Connect(Kill) else Kill() end
end

local function MakeConfigManager(Win)
	local CM = { Configs = {} }
	local Dir = "ToolkitUI/" .. Win.Folder .. "/config"
	local HasList = type(listfiles) == "function" and type(isfile) == "function"
	local CanWrite = type(writefile) == "function" and type(readfile) == "function"

	local function Ensure()
		pcall(function()
			if makefolder and isfolder then
				for _, P in ipairs({ "ToolkitUI", "ToolkitUI/" .. Win.Folder, Dir }) do
					if not isfolder(P) then makefolder(P) end
				end
			end
		end)
	end

	function CM:Sanitize(Name)
		Name = tostring(Name or ""):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
		return Name:sub(1, 32)
	end

	function CM:ConfigPath(Name)
		return Dir .. "/" .. Name .. ".json"
	end

	function CM:ConfigExists(Name)
		Name = CM:Sanitize(Name)
		if Name == "" then return false end
		if HasList then
			local Ok, R = pcall(isfile, CM:ConfigPath(Name))
			return Ok and R == true
		end
		return CM.Configs[Name] ~= nil
	end

	function CM:CreateConfig(Name)
		Name = CM:Sanitize(Name)
		if Name == "" then Name = "default" end
		if CM.Configs[Name] then return CM.Configs[Name] end

		local Cfg = { Name = Name, Registered = {}, Memory = nil }
		local Path = CM:ConfigPath(Name)

		function Cfg:Register(Key, Element) Cfg.Registered[Key] = Element end

		local function All()
			local T = {}
			for K, E in pairs(Win.FlagElements) do T[K] = E end
			for K, E in pairs(Cfg.Registered) do T[K] = E end
			return T
		end

		function Cfg:Save()
			local Data = {}
			for K, E in pairs(All()) do
				if E.Value ~= nil then Data[K] = Ser(E.Value) end
			end
			if not CanWrite then
				Cfg.Memory = Data
				return true
			end
			Ensure()
			return (pcall(function() writefile(Path, HttpService:JSONEncode(Data)) end))
		end

		function Cfg:Load()
			local Data
			if CanWrite then
				local Ok, Result = pcall(function() return HttpService:JSONDecode(readfile(Path)) end)
				if Ok then Data = Result end
			else
				Data = Cfg.Memory
			end
			if type(Data) ~= "table" then return false end
			local Els = All()
			for K, V in pairs(Data) do
				local E = Els[K]
				if E then pcall(function() if E.Select then E:Select(Deser(V)) else E:Set(Deser(V)) end end) end
			end
			return true
		end

		function Cfg:Exists() return CM:ConfigExists(Name) end
		function Cfg:Delete() return CM:DeleteConfig(Name) end

		CM.Configs[Name] = Cfg
		return Cfg
	end

	function CM:GetConfig(Name)
		return CM.Configs[CM:Sanitize(Name)]
	end

	function CM:DeleteConfig(Name)
		Name = CM:Sanitize(Name)
		if Name == "" then return false end
		local Path = CM:ConfigPath(Name)
		pcall(function()
			if delfile and isfile and isfile(Path) then delfile(Path) end
		end)
		CM.Configs[Name] = nil
		return not CM:ConfigExists(Name)
	end

	function CM:AllConfigs()
		local L, Seen = {}, {}
		if HasList then
			pcall(function()
				for _, F in ipairs(listfiles(Dir)) do
					local N = F:match("([^/\\]+)%.json$")
					if N and not Seen[N] then
						Seen[N] = true
						table.insert(L, N)
					end
				end
			end)
		else
			for N in pairs(CM.Configs) do table.insert(L, N) end
		end
		table.sort(L, function(A, B) return A:lower() < B:lower() end)
		return L
	end

	return CM
end

local function BuildKeyGate(Win, KS)
	local Keys = type(KS.Key) == "table" and KS.Key or { KS.Key }
	local KeyFile = "ToolkitUI/" .. Win.Folder .. "/key.txt"
	local function Valid(K)
		for _, V in ipairs(Keys) do
			if tostring(V) == K then return true end
		end
		return false
	end

	local Gate = New("Frame", {
		Name = "KeyGate", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Bg, BorderSizePixel = 0, ZIndex = 90, Active = true,
	}, Win.Main)
	Bg(Gate, Glass(0, 0.12))
	Corner(Gate, MAIN_RADIUS)

	local Box = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 320, 0, 0),
		AutomaticSize = AutoY, BackgroundTransparency = 1, ZIndex = 91,
	}, Gate)
	List(Box, 10, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	local TI = 1
	if KS.Thumbnail and KS.Thumbnail.Image then
		local Img = New("ImageLabel", {
			LayoutOrder = TI, Size = UDim2.fromOffset(64, 64), BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop, ZIndex = 91,
		}, Box)
		Corner(Img, 14)
		SetLucide(Img, KS.Thumbnail.Image)
		TI += 1
	end
	New("TextLabel", {
		LayoutOrder = TI, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Text = (KS.Thumbnail and KS.Thumbnail.Title) or "KEY SYSTEM",
		TextColor3 = White, TextSize = 20, FontFace = FontBlack, ZIndex = 91,
	}, Box)
	New("TextLabel", {
		LayoutOrder = TI + 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BackgroundTransparency = 1, Text = KS.Note or "Enter your key to continue.",
		TextColor3 = Theme.Muted, TextSize = 13, FontFace = FontMed, TextWrapped = true, ZIndex = 91,
	}, Box)

	local Pill = New("Frame", { LayoutOrder = TI + 2, Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, ZIndex = 91 }, Box)
	Bg(Pill, Glass(0, 0.4))
	Corner(Pill, CONTROL_RADIUS)
	FX.Depth(Pill, "Button")
	local PS = Stroke(Pill, Theme.StrokeHi, 1, 0, "Soft")
	local TB = New("TextBox", {
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), BackgroundTransparency = 1, Text = "", PlaceholderText = "Enter key...",
		PlaceholderColor3 = Theme.Muted, TextColor3 = Theme.Text, TextSize = 14, FontFace = FontMed, ClearTextOnFocus = false, TextXAlignment = Left, ZIndex = 92,
	}, Pill)

	local StatusL = New("TextLabel", {
		LayoutOrder = TI + 3, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "", TextColor3 = Theme.Muted,
		TextSize = 12, FontFace = FontMed, ZIndex = 91,
	}, Box)

	local Row = New("Frame", { LayoutOrder = TI + 4, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 91 }, Box)
	List(Row, 8, { FillDirection = Enum.FillDirection.Horizontal })

	local function Unlock(K)
		if KS.SaveKey then
			pcall(function()
				if makefolder and isfolder then
					for _, P in ipairs({ "ToolkitUI", "ToolkitUI/" .. Win.Folder }) do
						if not isfolder(P) then makefolder(P) end
					end
				end
				writefile(KeyFile, K)
			end)
		end
		Win._Unlocked = true
		Tween(Gate, 0.3, { BackgroundTransparency = 1 })
		for _, D in ipairs(Gate:GetDescendants()) do
			pcall(function()
				if D:IsA("TextLabel") or D:IsA("TextButton") or D:IsA("TextBox") then Tween(D, 0.25, { TextTransparency = 1 }) end
				if D:IsA("ImageLabel") then Tween(D, 0.25, { ImageTransparency = 1 }) end
				if D:IsA("Frame") then Tween(D, 0.25, { BackgroundTransparency = 1 }) end
			end)
		end
		task.delay(0.35, function() Gate:Destroy() end)
	end

	local function Check()
		local K = TB.Text:gsub("%s+", "")
		if Valid(K) then
			StatusL.Text = "Key accepted!"
			StatusL.TextColor3 = Theme.Green
			Unlock(K)
		else
			StatusL.Text = "Invalid key"
			StatusL.TextColor3 = Theme.Red
			Tween(PS, 0.2, { Color = Theme.Red })
			task.delay(1, function()
				if PS.Parent then Tween(PS, 0.3, { Color = Theme.StrokeHi }) end
			end)
		end
	end

	if KS.URL then
		local Get = New("TextButton", {
			LayoutOrder = 1, Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Theme.Hover, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "GET KEY", TextColor3 = Theme.Text, TextSize = 13, FontFace = FontBold, ZIndex = 92,
		}, Row)
		Corner(Get, CONTROL_RADIUS)
		Stroke(Get, Theme.StrokeHi, 1.2, 0, "Soft")
		Get.MouseButton1Click:Connect(function()
			local Ok = CopyText(KS.URL)
			StatusL.Text = Ok and "Key link copied" or "Copy failed"
			StatusL.TextColor3 = Ok and Theme.Cyan or Theme.Red
		end)
	end
	local Submit, SH = AccentButton(Row, "SUBMIT", UDim2.new(KS.URL and 0.5 or 1, KS.URL and -4 or 0, 1, 0), UDim2.new(), 13)
	SH.LayoutOrder = 2
	SH.ZIndex = 92
	Submit.ZIndex = 93
	Submit.MouseButton1Click:Connect(Check)
	TB.FocusLost:Connect(function(Enter) if Enter then Check() end end)

	if KS.SaveKey then
		local Ok, Saved = pcall(function() return isfile and isfile(KeyFile) and readfile(KeyFile) end)
		if Ok and type(Saved) == "string" then
			local Clean = Saved:gsub("%s+", "")
			if Valid(Clean) then task.defer(function() Unlock(Clean) end) end
		end
	end
end

function Library:CreateWindow(O)
	O = O or {}

	-- Transparent = true/false, or a number 0-1 (1 = visible, 0 = invisible)
	if type(O.Transparent) == "number" then
		Library.Transparent = true
		Library:SetOpacity(O.Transparent)
	else
		Library.Transparent = O.Transparent and true or false
	end
	-- Opacity = 0-1 (1 = visible, 0 = invisible)
	if type(O.Opacity) == "number" then
		Library:SetOpacity(O.Opacity)
	end
	Library.Moving = O.MovingAnimation ~= false
	if O.OrbImage ~= nil then Library:SetOrbImage(O.OrbImage, O.OrbImageTransparency) end
	if O.HideOrbs ~= nil then Library:SetOrbsHidden(O.HideOrbs) end
	if O.Reflections ~= nil then Library:SetReflections(O.Reflections) end
	if O.GlassModule ~= nil then Library:SetGlassProvider(O.GlassModule, O.GlassOptions) end
	if O.GlassBlurMode ~= nil then Library.GlassBlurMode = (tostring(O.GlassBlurMode):lower() == "screen") and "Screen" or "Window" end
	if O.GlassBlur ~= nil then Library.GlassBlurSize = math.clamp(tonumber(O.GlassBlur) or 6, 0, 40) end
	if O.GlassDistortion ~= nil then Library.GlassDistortion = math.clamp(tonumber(O.GlassDistortion) or 0.6, 0, 1) end
	-- Glassmorphism = true turns the PC-only liquid glass on at start (optional, default off)
	if O.Glassmorphism ~= nil then Library:SetGlassmorphism(O.Glassmorphism) end

	if O.NotificationWidth ~= nil or O.NotificationHeight ~= nil then
		Library:SetNotificationSize(O.NotificationWidth, O.NotificationHeight)
	end
	if O.NotificationPosition ~= nil then
		Library:SetNotificationPosition(O.NotificationPosition)
	end

	-- legacy option (0 = solid, 1 = invisible); overrides Transparent/Opacity if set
	if type(O.BackgroundTransparency) == "number" then
		Library:SetBackgroundTransparency(O.BackgroundTransparency)
	end

	local Size = typeof(O.Size) == "UDim2" and O.Size or UDim2.fromOffset(600, 400)
	local BASE_W, BASE_H = Size.X.Offset, Size.Y.Offset
	local SBW = math.clamp(O.SideBarWidth or 160, 120, math.floor(BASE_W * 0.4))
	local FolderName = O.Folder or O.ConfigFolder or "ToolkitUI"
	local Name = "ToolkitUI_" .. FolderName
	local UserCfg = type(O.User) == "table" and O.User.Enabled and O.User or nil
	local KeyCfg = type(O.KeySystem) == "table" and O.KeySystem.Enabled == true and O.KeySystem or nil
	local PlainTitle = StripRich(O.Title or "ToolkitUI")

	local Win = setmetatable({
		Connections = {}, Tabs = {}, Destroyed = false, Hidden = false, _side = 0, _tagN = 0, _Elements = {}, FlagElements = {},
		Folder = FolderName, ToggleKey = O.ToggleKey or Enum.KeyCode.RightShift, _openButton = true, _bubbleDraggable = true,
		_moving = O.MovingAnimation ~= false, _particles = O.Particles ~= false,
	}, Window)
	Library.OpenWindows[Win] = true
	Library._UpdateGlassBlur()

	pcall(function()
		local Containers = { CoreGui }
		local PG = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if PG then table.insert(Containers, PG) end
		if gethui then
			local Ok, Hui = pcall(gethui)
			if Ok and Hui then table.insert(Containers, Hui) end
		end
		for _, C in ipairs(Containers) do
			local Old = C:FindFirstChild(Name)
			if Old then Old:Destroy() end
		end
	end)

	local Gui = New("ScreenGui", {
		Name = Name, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	ParentGui(Gui)
	Win.Gui = Gui

	local function ComputeScale()
		local Cam = workspace.CurrentCamera
		local Vp = Cam and Cam.ViewportSize or Vector2.new(1280, 720)
		return math.clamp(math.min((Vp.X - 24) / BASE_W, (Vp.Y - 24) / BASE_H), 0.5, 1.1)
	end
	local TargetScale = ComputeScale()

	local Root = New("Frame", {
		Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BASE_W, BASE_H), BackgroundTransparency = 1,
	}, Gui)
	local RootScale = New("UIScale", { Scale = TargetScale * 0.9 }, Root)
	Win.Root, Win.RootScale = Root, RootScale

	local Main = New("Frame", {
		Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Bg,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 2, Active = true,
	}, Root)
	Bg(Main, Glass(0, 0.12))
	Corner(Main, MAIN_RADIUS)
	Stroke(Main, Theme.Frost, 1.5, 0, "Rim")
	FX.Surface(Main, MAIN_RADIUS, { Height = 120, Shade = true, ShadeHeight = 90 })
	FX.Liquid(Main, MAIN_RADIUS, "Full")
	FX.RealGlass(Main, MAIN_RADIUS, "Main")
	Win.Main = Main
	Win.BlurFrame = FX.BlurFrame(Main, MAIN_RADIUS)
	Library._UpdateGlassBlur()

	local Background = New("CanvasGroup", { Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, Main)
	Corner(Background, MAIN_RADIUS)
	local MainOrbA = Orb("Purple", 0.85, 0.15, 300, 0.8, Background)
	local MainOrbB = Orb("Cyan", 0.15, 0.85, 300, 0.8, Background)
	local Particles = MakeParticles(Background, 14)
	Win._applyParticles = function()
		for _, P in ipairs(Particles) do P.Obj.Visible = Win._particles end
	end
	Win._applyParticles()

	local TopBar = New("Frame", { Name = "TopBar", Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, ZIndex = 5 }, Main)
	local Logo = New("Frame", {
		Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(14, 10), BackgroundColor3 = Theme.Card, BorderSizePixel = 0,
	}, TopBar)
	Corner(Logo, 9)
	FX.Depth(Logo, "Button")
	Stroke(Logo, White, 1, 0.35, "Soft")
	local LogoImg = New("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.6),
		BackgroundTransparency = 1, ImageColor3 = White, ScaleType = Enum.ScaleType.Fit,
	}, Logo)
	local LogoFB = New("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = string.upper(string.sub(PlainTitle, 1, 1)),
		TextColor3 = White, TextSize = 16, FontFace = FontBlack,
	}, Logo)
	Win.LogoImg, Win.LogoFB = LogoImg, LogoFB
	SetBadgeIcon(LogoImg, LogoFB, O.Icon or "layout-grid", White, 9, UDim2.fromScale(0.6, 0.6))

	Win.TitleLabel = New("TextLabel", {
		Position = UDim2.fromOffset(58, 8), Size = UDim2.fromOffset(BASE_W - 250, 22), BackgroundTransparency = 1, RichText = true,
		Text = O.Title or "ToolkitUI", TextColor3 = Theme.Text, TextSize = 17, FontFace = FontBlack, TextXAlignment = Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, TopBar)
	Win.AuthorLabel = New("TextLabel", {
		Position = UDim2.fromOffset(58, 30), Size = UDim2.fromOffset(BASE_W - 250, 16), BackgroundTransparency = 1,
		Text = O.Author or "", TextColor3 = Theme.Muted, TextSize = 12, FontFace = FontMed, TextXAlignment = Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, TopBar)

	local CloseButton = IconButton(TopBar, "×", UDim2.new(1, -40, 0, 14), Theme.Red)
	local MinButton = IconButton(TopBar, "–", UDim2.new(1, -72, 0, 14), Theme.Accent)

	local TAG_EDGE = tonumber(O.TagOffset) or 114
	local TAG_GAP = tonumber(O.TagSpacing) or 8
	local MIN_TITLE = 96
	local TagSep = New("Frame", {
		Name = "TagSeparator", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(TAG_EDGE - 12), 0, 16),
		Size = UDim2.fromOffset(1, 22), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Visible = false,
	}, TopBar)
	local TagHost = New("Frame", {
		Name = "Tags", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TAG_EDGE, 0, 10), Size = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
	}, TopBar)
	Win.TagFrame = TagHost
	Win._tags = {}

	Win._layoutTags = function()
		local Tags = Win._tags
		local N = #Tags
		local Avail = math.max(BASE_W - 58 - MIN_TITLE - TAG_EDGE - 14, 60)

		-- Level 1 = roomy, 2 = compact, 3 = tight (icons are KEPT in all three),
		-- level 4 = tightest (icons hidden, only used when nothing else fits)
		local function Natural(T, L)
			local P = L == 1 and 9 or (L == 2 and 7 or (L == 3 and 5 or 6))
			local Ic = 0
			if T.HasIcon then
				if L == 1 then Ic = 18 elseif L == 2 then Ic = 16 elseif L == 3 then Ic = 15 end
			end
			return P * 2 + Ic + T.TextW, P, Ic
		end

		local ShownW = 0
		if N > 0 then
			local function GapFor(L) return L == 1 and TAG_GAP or math.min(TAG_GAP, L == 2 and 6 or 4) end
			local function Total(L)
				local S = GapFor(L) * (N - 1)
				for _, T in ipairs(Tags) do S += (Natural(T, L)) end
				return S
			end
			local L = 4
			if Total(1) <= Avail then L = 1 elseif Total(2) <= Avail then L = 2 elseif Total(3) <= Avail then L = 3 end
			local Gap = GapFor(L)
			local Widths, Sum = {}, 0
			for I, T in ipairs(Tags) do
				Widths[I] = (Natural(T, L))
				Sum += Widths[I]
			end
			if Sum + Gap * (N - 1) > Avail then
				Gap = math.min(Gap, 6)
				local Room = math.max(Avail - Gap * (N - 1), 1)
				local Scale = Room / Sum
				for I = 1, N do Widths[I] = math.max(28, math.floor(Widths[I] * Scale)) end
			end
			local X, Shown = 0, 0
			for I, T in ipairs(Tags) do
				local _, P, Ic = Natural(T, L)
				local W = Widths[I]
				if X + W > Avail + 0.5 then
					T.Frame.Visible = false
				else
					T.Frame.Visible = true
					T.Frame.Size = UDim2.fromOffset(W, 24)
					T.Frame.Position = UDim2.new(0, X, 0.5, 0)
					T.Wrap.Visible = Ic > 0
					T.Wrap.Position = UDim2.new(0, P, 0.5, 0)
					T.Lbl.Position = UDim2.fromOffset(P + Ic, 0)
					T.Lbl.Size = UDim2.fromOffset(math.max(W - 2 * P - Ic, 0), 24)
					X += W + Gap
					Shown += 1
				end
			end
			ShownW = Shown > 0 and (X - Gap) or 0
		end

		local Has = ShownW > 0
		TagHost.Visible = Has
		TagSep.Visible = Has
		TagHost.Size = UDim2.fromOffset(ShownW, 34)
		local Reserve = Has and (TAG_EDGE + ShownW + 14) or 86
		local TitleW = math.max(BASE_W - 58 - Reserve, 40)
		Win.TitleLabel.Size = UDim2.fromOffset(TitleW, 22)
		Win.AuthorLabel.Size = UDim2.fromOffset(TitleW, 16)
	end
	Win._layoutTags()

	FX.Hairline(New("Frame", {
		Position = UDim2.fromOffset(14, 53), Size = UDim2.new(1, -28, 0, 1), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, ZIndex = 5,
	}, Main))

	local SideBottom = UserCfg and 62 or 12
	local Sidebar = New("ScrollingFrame", {
		Name = "Sidebar", Position = UDim2.fromOffset(8, 60), Size = UDim2.new(0, SBW + 8, 1, -(60 + SideBottom)),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AutoY, ScrollingDirection = Enum.ScrollingDirection.Y, ClipsDescendants = true, ZIndex = 5, Active = true,
	}, Main)
	Pad(Sidebar, 4, 4, 4, 4)
	List(Sidebar, 4)
	Win.Sidebar = Sidebar

	local SideDivider = New("Frame", {
		Position = UDim2.fromOffset(SBW + 20, 68), Size = UDim2.new(0, 1, 1, -(68 + 16)), BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0, ZIndex = 5,
	}, Main)

	FX.Hairline(SideDivider, true)

	local UC
	if UserCfg then
		UC = New("TextButton", {
			Position = UDim2.new(0, 12, 1, -58), Size = UDim2.fromOffset(SBW, 46), BackgroundColor3 = Theme.Card, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "", ZIndex = 5,
		}, Main)
		Bg(UC, Glass(0, 0.35))
		Corner(UC, GROUP_RADIUS)
		FX.Depth(UC, "Panel")
		Stroke(UC, Theme.StrokeHi, 1, 0, "Soft")
		local Av = New("ImageLabel", {
			Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0,
			Image = UserCfg.Anonymous and "" or ("rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150"),
		}, UC)
		Corner(Av, 16)
		New("TextLabel", {
			Position = UDim2.fromOffset(48, 6), Size = UDim2.new(1, -56, 0, 18), BackgroundTransparency = 1,
			Text = UserCfg.Anonymous and "Anonymous" or LocalPlayer.DisplayName, TextColor3 = Theme.Text, TextSize = 13, FontFace = FontBold,
			TextXAlignment = Left, TextTruncate = Enum.TextTruncate.AtEnd,
		}, UC)
		New("TextLabel", {
			Position = UDim2.fromOffset(48, 24), Size = UDim2.new(1, -56, 0, 14), BackgroundTransparency = 1,
			Text = UserCfg.Anonymous and "@anonymous" or ("@" .. LocalPlayer.Name), TextColor3 = Theme.Muted, TextSize = 11, FontFace = FontMed,
			TextXAlignment = Left, TextTruncate = Enum.TextTruncate.AtEnd,
		}, UC)
		UC.MouseButton1Click:Connect(function() Call(UserCfg.Callback) end)
	end

	local Content = New("Frame", {
		Name = "Content", Position = UDim2.fromOffset(SBW + 26, 62), Size = UDim2.new(1, -(SBW + 26 + 12), 1, -(62 + 12)),
		BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 5, Active = true,
	}, Main)
	Win.Content = Content

	-- Sidebar, divider, user card and content are revealed together (see the watcher below)
	local function SetChrome(On)
		Sidebar.Visible = On
		SideDivider.Visible = On
		Content.Visible = On
		if UC then UC.Visible = On end
	end
	Win._SetChrome = SetChrome

	local Modal = New("Frame", { Name = "Modal", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 40 }, Main)
	local Dim = New("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		Active = true, ZIndex = 1,
	}, Modal)
	Corner(Dim, MAIN_RADIUS)
	Win.Modal, Win.Dim = Modal, Dim
	Win.Host = { Modal = Modal, Dim = Dim }

	local Bubble = New("Frame", {
		Size = UDim2.fromOffset(48, 48), Position = UDim2.new(1, -64, 0.5, -24), BackgroundColor3 = Theme.Card, BorderSizePixel = 0, Visible = false,
		Active = true,
	}, Gui)
	Corner(Bubble, 16)
	FX.Depth(Bubble, "Button")
	Stroke(Bubble, White, 1.5, 0.3, "Soft")
	local BubbleButton = New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, Bubble)
	local BubbleImg = New("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1, ImageColor3 = White,
	}, Bubble)
	local BubbleFB = New("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "≡", TextColor3 = White, TextSize = 20, FontFace = FontBold,
	}, Bubble)
	Win.Bubble, Win.BubbleImg, Win.BubbleFB = Bubble, BubbleImg, BubbleFB
	SetBadgeIcon(BubbleImg, BubbleFB, O.Icon or "layout-grid", White, 24, UDim2.fromOffset(24, 24))
	if type(O.OpenButton) == "table" then Win:OpenButton(O.OpenButton) end

	MakeDraggable(Win, TopBar, Root, function() return RootScale.Scale end, function() return not Modal.Visible end)
	local BubbleMoved = false
	MakeDraggable(Win, BubbleButton, Bubble, function() return 1 end, function() return Win._bubbleDraggable end, function() BubbleMoved = true end)

	CloseButton.MouseButton1Click:Connect(function()
		if O.ConfirmClose == false then
			Win:Destroy()
			return
		end
		Win:Dialog({
			Title = "CLOSE UI",
			Icon = "lucide:power",
			Content = "Are you sure you want to close this?",
			Buttons = {
				{ Title = "NO", Variant = "Secondary" },
				{ Title = "YES", Variant = "Danger", Callback = function() Win:Destroy() end },
			},
		})
	end)
	MinButton.MouseButton1Click:Connect(function() Win:Close() end)
	BubbleButton.MouseButton1Click:Connect(function()
		if BubbleMoved then
			BubbleMoved = false
			return
		end
		Win:Open()
	end)
	Win:Connect(UserInputService.InputBegan, function(I, Processed)
		if Processed or Win.Destroyed then return end
		if I.KeyCode == Win.ToggleKey then Win:Toggle() end
	end)

	Win._resetMotion = function() end

	local Elapsed, Acc = 0, 0
	Win:Connect(RunService.RenderStepped, function(Dt)
		if Win.Destroyed or Win.Hidden or not Win._moving then return end
		Elapsed += Dt
		Acc += Dt
		if Acc < 1 / 30 then return end
		local Step = Acc
		Acc = 0

		if not Library.OrbsHidden then
			MainOrbA.Position = UDim2.fromScale(0.85 + math.cos(Elapsed * 0.7) * 0.12, 0.15 + math.sin(Elapsed * 0.55) * 0.15)
			MainOrbB.Position = UDim2.fromScale(0.15 + math.sin(Elapsed * 0.6) * 0.12, 0.85 + math.cos(Elapsed * 0.5) * 0.15)
		end

		if not Win._particles then return end
		for _, P in ipairs(Particles) do
			local Y = P.Y - P.Speed * Step
			if Y < -0.02 then Y = 1.02 end
			local X = P.X + math.sin(Elapsed + P.Drift) * 0.018 * Step
			P.X, P.Y = X, Y
			P.Obj.Position = UDim2.fromScale(X, Y)
		end
	end)

	Win.ConfigManager = MakeConfigManager(Win)

	Win._IntroDone = false
	local LoadCfg = type(O.Loading) == "table" and O.Loading or {}
	if KeyCfg then Win._Unlocked = false end
	do
		local IntroOn = not (O.ShowIntro == false or LoadCfg.Enabled == false)
		if IntroOn or KeyCfg then
			SetChrome(false)
			task.spawn(function()
				repeat RunService.Heartbeat:Wait() until Win.Destroyed or (Win._IntroDone and Win._Unlocked ~= false)
				if not Win.Destroyed then SetChrome(true) end
			end)
		end
	end
	if O.ShowIntro == false or LoadCfg.Enabled == false then
		RootScale.Scale = TargetScale
		Win._IntroDone = true
	else
		Tween(RootScale, 0.35, { Scale = TargetScale }, Enum.EasingStyle.Back)

		local TitleText = string.upper(StripRich(LoadCfg.Title or PlainTitle))
		local StatusReady = tostring(LoadCfg.Status or "Initializing")
		local StatusWait = tostring(LoadCfg.WaitStatus or "Wait")
		local SubText = LoadCfg.Subtitle == nil and "Please wait" or tostring(LoadCfg.Subtitle)
		local UseDots = LoadCfg.Dots ~= false
		local MinT = math.max(tonumber(LoadCfg.MinTime) or 1.3, 0)
		local MaxT = math.max(tonumber(LoadCfg.MaxTime) or 3, MinT)
		local Yield = LoadCfg.Yield ~= false

		local Splash = New("CanvasGroup", {
			Name = "Splash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0,
			ZIndex = 100, Active = true,
		}, Main)
		-- The loading screen is always fully solid (not registered with Bg/Glass), so Transparent / Opacity
		-- settings can never make the window title, author or content show through it.
		Corner(Splash, MAIN_RADIUS)

		-- Pure black screen. The liquid layers (UIGradient sheen + UIStroke rim) stay WHITE so it still looks like glass.
		FX.Surface(Splash, MAIN_RADIUS, { Z = 1 })
		local Sheen = Splash:FindFirstChild("GlassSheen")
		if Sheen then Sheen.BackgroundColor3 = White end
		Stroke(Splash, White, 1.5, 0.2, "Rim")
		local IconCol = ParseColor(LoadCfg.IconColor, White)     -- icon stays white, or the hex you set (Loading.IconColor)
		Win.SplashIconColor = IconCol

		local SLogo = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -52), Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = White, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 2, Active = true,
		}, Splash)
		Corner(SLogo, 16)
		local LogoStroke = Stroke(SLogo, White, 1.5, 0.5, "Soft")
		-- hover: the logo tile and its rim brighten a little
		SLogo.MouseEnter:Connect(function()
			Tween(SLogo, 0.2, { BackgroundTransparency = 0.78 })
			Tween(LogoStroke, 0.2, { Transparency = 0.25 })
		end)
		SLogo.MouseLeave:Connect(function()
			Tween(SLogo, 0.2, { BackgroundTransparency = 0.9 })
			Tween(LogoStroke, 0.2, { Transparency = 0.5 })
		end)
		local SImg = New("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.6),
			BackgroundTransparency = 1, ImageColor3 = IconCol, ZIndex = 3,
		}, SLogo)
		local SFB = New("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = string.upper(string.sub(PlainTitle, 1, 1)),
			TextColor3 = IconCol, TextSize = 30, FontFace = FontBlack, ZIndex = 3,
		}, SLogo)
		Win.SplashImg, Win.SplashFB = SImg, SFB
		SetBadgeIcon(SImg, SFB, LoadCfg.Icon or O.Icon or "layout-grid", IconCol, 18, UDim2.fromScale(0.6, 0.6))

		local STitle = New("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 14), Size = UDim2.fromOffset(400, 32),
			BackgroundTransparency = 1, Text = TitleText, TextColor3 = White, TextSize = 24, FontFace = FontBlack,
			MaxVisibleGraphemes = 0, ZIndex = 2,
		}, Splash)
		local StatusLbl = New("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 46), Size = UDim2.fromOffset(400, 20),
			BackgroundTransparency = 1, RichText = true, Text = "", TextColor3 = White, TextSize = 15, FontFace = FontBold, ZIndex = 2,
		}, Splash)
		local BarBg = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 72), Size = UDim2.fromOffset(220, 4),
			BackgroundColor3 = Color3.fromRGB(38, 38, 38), BorderSizePixel = 0, ZIndex = 2,
		}, Splash)
		Corner(BarBg, 2)
		local BarFill = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = White, BorderSizePixel = 0 }, BarBg)
		Corner(BarFill, 2)
		if SubText ~= "" then
			New("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 92), Size = UDim2.fromOffset(400, 16),
				BackgroundTransparency = 1, Text = SubText, TextColor3 = Theme.Muted, TextSize = 12, FontFace = FontMed, ZIndex = 2,
			}, Splash)
		end

		Tween(SLogo, 0.35, { Size = UDim2.fromOffset(72, 72) }, Enum.EasingStyle.Back)
		task.spawn(function()
			for I = 1, #TitleText do
				if Win.Destroyed then return end
				STitle.MaxVisibleGraphemes = I
				task.wait(0.03)
			end
			STitle.MaxVisibleGraphemes = -1
		end)

		local function DotsText(Base, N)
			if not UseDots then return Base end
			return Base .. string.rep(".", N) .. "<font transparency=\"1\">" .. string.rep(".", 3 - N) .. "</font>"
		end

		local function Finish()
			if Win.Destroyed then return end
			BarFill.Size = UDim2.fromScale(1, 1)
			task.wait(0.15)
			if Win.Destroyed then return end
			Win._IntroDone = true
			Tween(Splash, 0.3, { GroupTransparency = 1 })
			task.wait(0.32)
			pcall(function() Splash:Destroy() end)
		end

		local function Run()
			local T0 = os.clock()
			local Need = Rng:NextNumber(MinT, MaxT)
			local LastKey
			while not Win.Destroyed do
				local Loaded = game:IsLoaded()
				local El = os.clock() - T0
				local Phase = math.floor(El / 0.35) % 4
				local Key = (Loaded and 10 or 0) + Phase
				if Key ~= LastKey then
					LastKey = Key
					StatusLbl.Text = DotsText(Loaded and StatusReady or StatusWait, Phase)
				end
				BarFill.Size = UDim2.fromScale(math.min(El / math.max(Need, 0.01), Loaded and 1 or 0.9), 1)
				if Loaded and El >= Need then break end
				RunService.Heartbeat:Wait()
			end
			Finish()
		end

		if Yield then Run() else task.spawn(Run) end
	end

	if KeyCfg then
		-- wait for the loading screen to finish first, then show the key system
		repeat task.wait(0.05) until Win._IntroDone or Win.Destroyed
		if not Win.Destroyed then BuildKeyGate(Win, KeyCfg) end
		repeat task.wait(0.1) until Win._Unlocked or Win.Destroyed
	end

	if O.TipsNotify == true then
		local Tips = type(O.Tips) == "table" and O.Tips or {}
		task.spawn(function()
			while not Win.Destroyed and not (Win._IntroDone and Win._Unlocked ~= false) do
				task.wait(0.1)
			end
			task.wait(tonumber(Tips.Delay) or 4)
			if Win.Destroyed then return end
			local KeyName = typeof(Win.ToggleKey) == "EnumItem" and Win.ToggleKey.Name or tostring(Win.ToggleKey)
			Library:Notify({
				Title = Tips.Title or "Tips",
				Content = Tips.Content or ("UI loaded. Press " .. KeyName .. " to hide/show."),
				Icon = Tips.Icon or "lucide:lightbulb",
				Duration = Tips.Duration or 5,
				Width = Tips.Width,
				Height = Tips.Height,
			})
		end)
	end

	return Win
end

return Library
