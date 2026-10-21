--[[
   KahLua Kore - core library functions for KahLua addons.
     Git: https://github.com/kahluamods/kore
     E-mail: me@cruciformer.com

   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2026 Kean Johnston. All rights reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
]]

local addonName, addonPrivate = ...

local KOREUI_MAJOR = "KoreUI"
local KOREUI_MINOR = 1

local KUI = LibStub:NewLibrary(KOREUI_MAJOR, KOREUI_MINOR)

if (not KUI) then
  return
end

KUI.debug_id = KOREUI_MAJOR

--
-- Where this copy of KoreUI keeps its art, taken from the name the game hands every file rather than written down, so that
-- renaming the folder is a rename and nothing more. Each copy works this out for itself rather than there being one path on
-- K, because LibStub picks the newest Kore and the newest KoreUI separately and the two need not have come from the same one.
--
-- The kit map is addonPrivate.KoreUIKit, generated into UIKit.lua. It lives in the addon's private table rather than on KUI
-- because it is only right for the code it was built with, and a copy of this file that LibStub kept finds the map that shipped
-- beside it there, whatever other copies of Kore have loaded. UIKit.lua loads after this file, so read the map inside functions
-- only. A local taken from it here would be nil.
--
KUI.TEXTURE_PATH = "Interface\\Addons\\" .. addonName .. "\\Textures\\"

--
-- The Lua and WoW globals this file leans on, named here so that a lookup inside a function is an upvalue rather than a trip
-- through the global table. Only the ones it actually uses. A chunk may hold two hundred local names and this one is a widget
-- toolkit, so an alias nothing calls is not free, it is one of the two hundred.
--
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tostring = tostring
local GetTime = GetTime
local min = math.min
local max = math.max
local strfind = string.find
local strlower = string.lower
local strupper = string.upper
local strrep = string.rep
local ipairs, pairs, next, type = ipairs, pairs, next, type
local select, assert = select, assert
local UIParent = UIParent
local floor = math.floor
local ceil = math.ceil
local CreateFrame = CreateFrame
local tsort = table.sort

--
-- A widget's handlers live on a table of its own rather than loose at the top of the file. A chunk may hold two hundred local
-- names, and a toolkit of two dozen widgets has hundreds of handlers, so a handler keeping a name of its own would spend the
-- whole allowance on one file's plumbing. A table costs one name and holds as many handlers as its widget has.
--
-- It reads better as well. What follows the dot is what the handler does and what comes before it is whose it is, so
-- RADIO.SetValue is a radio button's SetValue and nothing else has to be read to know that.
--
-- They are declared together rather than each above its own code, because a handler is commonly handed to a widget built
-- thousands of lines from where it is written, and because between them they are most of what this file is.
--
local CB = {}     -- check boxes, and the radio buttons built by the same code
local DD = {}     -- drop down menus
local EB = {}     -- edit boxes
local HOOK = {}   -- the frame methods KoreUI hooks on every widget it makes
local IB = {}     -- image buttons
local LBL = {}    -- string labels
local NFR = {}    -- the item frames inside a drop down
local POP = {}    -- popup lists
local RADIO = {}  -- radio buttons, and the radio groups made of them
local SD = {}     -- sliders
local SL = {}     -- scroll lists
local TD = {}     -- tabbed dialogs, whose constants are set where that window is built
local TL = {}     -- the top level frame a drop down hangs from

local K, KM = LibStub:GetLibrary("Kore")
assert(K, "KoreUI requires Kore")
assert(tonumber(KM) >= 1, "KoreUI requires Kore r1 or later")
K:RegisterExtension(KUI, KOREUI_MAJOR, KOREUI_MINOR)

local function debug(lvl,...)
  K.debug("kore", lvl, ...)
end

local xpcall = xpcall

local function errorhandler(err)
  return geterrorhandler()(err)
end

-- Call optional function
local function safecall(func, ...)
  if type(func) == "function" then
    return xpcall(func, errorhandler, ...)
  end
end


KUI.emptydropdown = {
  {
    text = "",
    checkable = false,
    clickable = false,
    enabled = false,
  },
}

--
-- The three different types of dropdown menu:
-- SINGLE allows selection of a single item from a list. The selected choice is displayed in the text box. When the menu is dropped
--   down the selected item has a checkmark. This typically has a label and not a title.
-- COMPACT allows selection of a single item from a list. When the menu is dropped down the selected item is checked. The selected
--   item is NOT displayed in the main text box. Rather, the title is always displayed in the text box, thus the title must always
--   be provided. A label can also be provided but that will look weird.
-- MULTI allows selection of multiple items from a list. When the menu is dropped down all of the selected items will have a checkmark.
--   The main widget text is the title text. A label can also be provided but it looks wierd.
--
-- Whichever of the three it is, a text box with nothing to show falls back to the head of its own list when that item is a title
-- item. That is a SINGLE dropdown with nothing chosen yet, or a COMPACT or MULTI one given no title. A title item is not one of the
-- choices, it names the list it heads, so the box says that rather than standing empty. See DD.headtext.
--
-- SINGLE and COMPACT have the following two functions:
--   SetValue(value) will ensure that the first item in the item list with the specified value will be selected, and this will be
--     the return value from calling GetValue(). If no item with the specified value can be found then no changes are made to the widget.
--   GetValue() will return the value of the currently selected item or nil if no current value is selected.
-- MULTI menus have no value of their own. Which items are checked is each item's checked, given in the item list and set again with
-- UpdateItems, and every click on one throws OnItemChecked with the item, its value and whether it is now checked.
--
local MODE_SINGLE  = 1
local MODE_COMPACT = 2
local MODE_MULTI   = 3

local function fixframelevels(parent, ...)
  local l = 1
  local c = select(l, ...)
  local pl = parent:GetFrameLevel() + 1
  while (c) do
    c:SetFrameLevel(pl)
    fixframelevels(c, c:GetChildren())
    l = l + 1
    c = select(l, ...)
  end
end

function KUI.MakeFrame(ftype, fname, parent, templ)
  local f = CreateFrame(ftype, fname, parent, templ)
  local p = f:GetParent()
  if (p and p.GetFrameLevel) then
    hooksecurefunc(f, "SetFrameLevel", function(this, level)
      fixframelevels(this, this:GetChildren())
    end)
  end
  return f
end

local MakeFrame = KUI.MakeFrame

--
-- THE KIT. Every piece of art KoreUI draws is a rectangle on one sheet, KoreUIKit, and the map UIKit.lua generates says where
-- each one is and how it may be drawn. Nothing of Blizzard's is drawn but tooltips, fonts and whatever icons a caller puts in.
--
-- A tinted piece is two textures, its achromatic white layer and its chroma layer added over it. The chroma layer wears the
-- accent colour, so gold metal becomes ruby or sapphire metal while black enamel stays black. A FLAT piece wears the accent on
-- both layers and reads as one coloured object, which is what gems, fills and orbs want. A notint piece keeps colours of its
-- own and is only ever brightened or greyed. A glow is white light added over whatever is under it in the accent colour.
--
-- The map is loaded after this file, into the addon's private table, so it is only ever read inside functions.
--
-- Everything lives on one table rather than in file locals, this chunk being at Lua 5.1's limit of two hundred.
--
local KIT = {}

--
-- THE PALETTE
--
-- Every colour the kit knows is named here and nothing anywhere writes one out as numbers. The names all begin COLOR_, so
-- that a colour is recognisable as one wherever it turns up and grepping for the prefix finds the lot.
--
-- COLOR_REDGOLD is the kit's own, the fully saturated form of the hue the whole kit is drawn in. A tinted piece wearing it
-- is its drawing again exactly.
--
-- COLOR_GOLD is the yellower one the kit writes in: the colour of a title on its plaque, and of artwork meant to read as
-- gold rather than as metal.
--
-- COLOR_SAPPHIRE is the colour of the stones wherever nobody gave them one, #0866FF, which is the sapphire of the mock-up
-- the kit was drawn from once the stone's own darkness has been multiplied back in.
--
-- The kit's own, which are the colours it is drawn in.
--
KUI.COLOR_REDGOLD  = { r = 1.0,   g = 0.59, b = 0.0 }
KUI.COLOR_GOLD     = { r = 1.0,   g = 0.80, b = 0.0 }
KUI.COLOR_SAPPHIRE = { r = 0.031, g = 0.4,  b = 1.0 }

--
-- The eight a terminal has, at full strength. They are here so that anything wanting a plain primary says which one rather
-- than carrying a row of ones and zeroes, and so that two places wanting the same red are demonstrably wanting the same red.
-- Nothing in the kit's own artwork is any of these; they are for callers.
--
KUI.COLOR_BLACK   = { r = 0, g = 0, b = 0 }
KUI.COLOR_RED     = { r = 1, g = 0, b = 0 }
KUI.COLOR_GREEN   = { r = 0, g = 1, b = 0 }
KUI.COLOR_YELLOW  = { r = 1, g = 1, b = 0 }
KUI.COLOR_BLUE    = { r = 0, g = 0, b = 1 }
KUI.COLOR_MAGENTA = { r = 1, g = 0, b = 1 }
KUI.COLOR_CYAN    = { r = 0, g = 1, b = 1 }
KUI.COLOR_WHITE   = { r = 1, g = 1, b = 1 }

--
-- The stones, each named for what it is rather than for whoever happens to be wearing it. Every one is fully saturated with
-- its brightest channel at one, because the kit multiplies its drawing by a colour and multiplying can only darken: a colour
-- given any less to start with comes out dull rather than coloured.
--
-- Konfer dresses its five distribution systems in these. That is Konfer's business and it says so in each policy's own
-- descriptor; what is here is the colour, which anything at all may use.
--
-- Azure is not the sapphire above and is not blue: it is bluer than the stones and lighter than the primary, which is what
-- makes it a colour of its own rather than either of them at a different strength.
--
KUI.COLOR_EMERALD = { r = 0.000, g = 1.000, b = 0.478 }
KUI.COLOR_AZURE   = { r = 0.000, g = 0.323, b = 1.000 }
KUI.COLOR_PURPLE  = { r = 0.517, g = 0.000, b = 1.000 }
KUI.COLOR_AMBER   = { r = 1.000, g = 0.550, b = 0.000 }
KUI.COLOR_RUBY    = { r = 1.000, g = 0.000, b = 0.067 }

--
-- THE DEFAULTS
--
-- Which of the palette the kit reaches for when nobody has said. These are what the kit uses, never the palette entries
-- themselves: a piece falling back to a colour is asking for "the default", and what that happens to be today is one line
-- here rather than a decision repeated at every site that falls back.
--
-- DEFAULT_ARTWORK_COLOR is what a piece and a word wear with no colour named anywhere above them, which is the tint and the
-- accent of anything nobody gave one. DEFAULT_FILL_COLOR is what fills a stone, and the selected page and tab buttons with
-- it, wherever no gem colour was named. DEFAULT_CHANGED_COLOR is what a widget's value is written in while it differs from
-- what is saved, set by its SetChanged.
--
KUI.DEFAULT_ARTWORK_COLOR = KUI.COLOR_GOLD
KUI.DEFAULT_FILL_COLOR    = KUI.COLOR_SAPPHIRE
KUI.DEFAULT_CHANGED_COLOR = KUI.COLOR_CYAN

--
-- What a disabled piece wears, whatever its window's colours: a dim grey drawn flat, so that it sits back from everything
-- that can be used instead of standing out as bare metal. A piece of its own colour is greyed and dimmed by DISABLED_OWN,
-- which is a multiplier rather than a colour and so is not one of the COLOR_ names.
--
KIT.COLOR_DISABLED = { r = 0.25, g = 0.25, b = 0.25 }
KIT.DISABLED_OWN = 0.5

--
-- Hover and pressed are the normal drawing times a constant per channel, measured by fitting the drawn states of ButtonPointed
-- to its first one. A vertex colour cannot go above one, so the part of a multiplier above one is added instead, by a second
-- copy of each layer laid over the first with ADD blend at that strength. White times 1.06 and white plus 0.06 of itself are
-- the same thing.
--
KIT.STATES = {
  normal  = { 1.000, 1.000, 1.000 },
  hover   = { 1.062, 1.084, 0.952 },
  pressed = { 0.936, 0.909, 0.841 },
}

--
-- The close button's own states. A small stone brightened by the few percent a button's metal is reads as not changing at all,
-- and the close button is the one control a user reaches for without looking, so its hover is a plain lift of half again.
--
KIT.CLOSE_STATES = {
  normal  = { 1.000, 1.000, 1.000 },
  hover   = { 1.500, 1.500, 1.500 },
  pressed = { 0.800, 0.800, 0.800 },
}

--
-- A scroll bar's states, each the button's at SCROLL_BRIGHTNESS. A bar runs the whole height of what it scrolls, and in the
-- full brightness of the window's metal it outshines the rims and the rows beside it.
--
KIT.SCROLL_BRIGHTNESS = 0.67
KIT.SCROLL_STATES = {}

for state, v in pairs(KIT.STATES) do
  KIT.SCROLL_STATES[state] = { v[1] * KIT.SCROLL_BRIGHTNESS, v[2] * KIT.SCROLL_BRIGHTNESS, v[3] * KIT.SCROLL_BRIGHTNESS }
end

function KIT.def(name)
  local map = addonPrivate.KoreUIKit

  assert(map, "KoreUI: the kit map UIKit.lua is not loaded")
  assert(map.pieces[name], "KoreUI: the kit has no piece called " .. tostring(name))

  return map.pieces[name]
end

function KIT.has(name)
  local map = addonPrivate.KoreUIKit

  return (map and map.pieces[name]) and true or false
end

function KIT.sheet()
  return KUI.TEXTURE_PATH .. addonPrivate.KoreUIKit.sheet
end

--
-- A window wears three colours. Its tint is the colour of its metal, the rims, buttons, tabs and every other piece of it. Its
-- accent is the colour of what marks the window as its own, its portrait's frame and the plaque its title sits in. Its gem
-- colour is the colour of every stone set in it. Each is set with cfg.tint, cfg.accent and cfg.gem on any frame, and found by
-- walking up from the piece, so a checkbox deep inside a window wears the window's without every widget between having to
-- pass them on.
--
-- The accent a frame wears is its own, or that of the nearest frame above it that has one, or the kit's gold.
--
function KIT.accent(frame)
  local f = frame

  while (f) do
    if (f.kuiaccent) then
      return f.kuiaccent
    end

    f = f.GetParent and f:GetParent() or nil
  end

  return KUI.DEFAULT_ARTWORK_COLOR
end

--
-- The tint a frame wears is that of the nearest frame, itself or above it, that sets either colour: its tint if it sets one,
-- and otherwise its accent, so a frame that names only an accent wears it everywhere. The second value says whether the tint
-- is drawn flat, both layers multiplied by it, which cfg.tintflat asks for: a dark tint added over the metal the usual way
-- gives light steel, and only multiplying makes it dark. An accent standing in for a tint is drawn the usual way.
--
function KIT.tint(frame)
  local f = frame

  while (f) do
    if (f.kuitint) then
      return f.kuitint, KIT.inherited(frame, "kuitintflat") and true or false
    end

    if (f.kuiaccent) then
      return f.kuiaccent, false
    end

    f = f.GetParent and f:GetParent() or nil
  end

  return KUI.DEFAULT_ARTWORK_COLOR, false
end

--
-- The gem colour a frame wears is its own, or that of the nearest frame above it that has one, or the kit's sapphire. An
-- accent does not stand in for it: the stones are sapphire in a window of any accent unless that window says otherwise.
--
function KIT.gemcolour(frame)
  return KIT.inherited(frame, "kuigem") or KUI.DEFAULT_FILL_COLOR
end

--
-- Which colour each named part of a widget wears unless a frame says otherwise with cfg.parts, as a table of part names to
-- "tint", "accent" or "gem". A piece with no part, or a part not named here, wears the tint.
--
--   gem       a stone set in a plaque, a tab, the ends of a page button, a slider's knob or a scrollbar's thumb
--   titlegem  the stone in the plaque a tabbed window's title sits in
--   portrait  the frame round a tabbed window's portrait
--   title     the plaque a tabbed window's title sits in
--   plaque    the plaque over a panel or a dialog
--   glow      the glow under a menu row the pointer is on, or a list row where the list asks for the glow
--   rowrim    the ring round the selected row of a list
--   tabfill   the fill in the page button of the page on show and in the tab button of the tab on show
--   buttonfill the fill in a button's or a closed dropdown's dark middle, unless cfg.buttonfill turns it off, darkened by
--             KIT.FILL_SHADE
--   mark      the tick or cross in a checkbox or a menu, and the orb in a radio button
--
KIT.PARTS = {
  gem        = "gem",
  titlegem   = "accent",
  portrait   = "accent",
  title      = "accent",
  plaque     = "tint",
  glow       = "tint",
  rowrim     = "tint",
  tabfill    = "gem",
  buttonfill = "gem",
  mark       = "tint",
}

function KIT.wears(frame, part)
  if (not part) then
    return "tint"
  end

  local f = frame

  while (f) do
    local parts = f.kuiparts

    if (parts and parts[part] ~= nil) then
      return parts[part]
    end

    f = f.GetParent and f:GetParent() or nil
  end

  return KIT.PARTS[part] or "tint"
end

--
-- The first value of KEY on FRAME or on any frame above it, or nil when none of them has one. How a setting a window makes
-- once reaches every widget in it.
--
function KIT.inherited(frame, key)
  local f = frame

  while (f) do
    if (f[key] ~= nil) then
      return f[key]
    end

    f = f.GetParent and f:GetParent() or nil
  end

  return nil
end

--
-- Whether a mark on FRAME, a checkbox's tick or cross or a menu's check, wears its window's colour rather than its own green
-- or red. It keeps its own unless FRAME or a frame above it says otherwise with cfg.markcolour = false.
--
function KIT.markaccented(frame)
  local own = KIT.inherited(frame, "kuimarkcolour")

  if (own == nil) then
    own = true
  end

  return not own
end

--
-- Every piece, so that a frame whose accent changes can find the pieces beneath it. Weak, though WoW never frees a frame.
--
KIT.all = setmetatable({}, { __mode = "k" })

local PIECE = {}
PIECE.__index = PIECE
KIT.PIECE = PIECE

--
-- A piece drawn on OWNER. OPTS may give the draw layer and the sublevel its lowest texture sits on (a tinted piece uses that
-- and the three above it, so no higher than 4), flat for the flat look, part for which of the parts in KIT.PARTS it is and so
-- which of its window's colours it wears, accent for a colour it wears whatever its window's, shade for how much darker than
-- that colour it is drawn, intensity for a glow, and accented for a piece of its own colour that is to wear its window's
-- colour instead, its brightness multiplied by it the way a flat piece is. The piece draws nothing until it is given a box.
--
-- The box is an empty texture the caller anchors like any region, and every slice anchors to it. That lets a strip centre
-- its ornament and a frame hang its corners from any rectangle at all, however the caller placed it.
--
function KIT.new(owner, name, opts)
  opts = opts or {}

  local p = setmetatable({}, PIECE)

  p.owner = owner
  p.name = name
  p.def = KIT.def(name)
  p.layer = opts.layer or "ARTWORK"
  p.sub = opts.sublevel or 0
  p.flat = opts.flat and true or false
  p.part = opts.part
  p.fixed = opts.accent
  p.intensity = opts.intensity or 1
  p.shade = opts.shade
  p.accented = (opts.accented and p.def.value) and true or false
  p.states = opts.states or KIT.STATES
  p.alpha = 1
  p.state = "normal"
  p.enabled = true
  p.shown = true
  p.scale = 1
  p.slices = {}
  p.box = owner:CreateTexture(nil, p.layer)
  p.box:SetAlpha(0)

  KIT.all[p] = true
  return p
end

--
-- The texture coordinates of a part of a rectangle, the part given as fractions of it.
--
function KIT.sub(rect, u0, u1, v0, v1)
  local w, h = rect[2] - rect[1], rect[4] - rect[3]

  return rect[1] + w * u0, rect[1] + w * u1, rect[3] + h * v0, rect[3] + h * v1
end

--
-- Slice I of the piece, made on first use: the textures for every layer the piece has, cut to U0..U1 by V0..V1 of it. The
-- first texture carries the anchors and the others lie over it.
--
function PIECE.slice(self, i, u0, u1, v0, v1)
  local s = self.slices[i]
  local d = self.def

  if (not s) then
    s = {}
    local sheet = KIT.sheet()
    local o = self.owner

    if (d.colour) then
      s.base = o:CreateTexture(nil, self.layer, nil, self.sub)
      s.base:SetTexture(sheet)
      if (d.kind == "glow") then
        s.base:SetBlendMode("ADD")
      end
      s.layers = { { tex = s.base, rect = self.accented and d.value or d.colour } }
    else
      s.base = o:CreateTexture(nil, self.layer, nil, self.sub)
      s.base:SetTexture(sheet)
      local ch = o:CreateTexture(nil, self.layer, nil, self.sub + 1)
      ch:SetTexture(sheet)
      ch:SetBlendMode("ADD")
      ch:SetAllPoints(s.base)
      s.layers = { { tex = s.base, rect = d.white }, { tex = ch, rect = d.chroma } }
    end

    self.slices[i] = s
  end

  s.uv = { u0, u1, v0, v1 }
  for _, l in ipairs(s.layers) do
    l.tex:SetTexCoord(KIT.sub(l.rect, u0, u1, v0, v1))
  end
  if (s.extra) then
    for k, l in ipairs(s.extra) do
      l.tex:SetTexCoord(KIT.sub(s.layers[k].rect, u0, u1, v0, v1))
    end
  end

  s.base:ClearAllPoints()
  s.hidden = nil
  return s
end

--
-- The piece's natural size: the width and height it is drawn at when nothing stretches it.
--
function PIECE.natural(self)
  local d = self.def

  return d.draw * d.aspect, d.draw
end

--
-- Lay the slices out in the box. THICK is how many pixels across the piece is drawn along its short side, which fixes how big
-- its ends and its ornament are, since only the runs between them stretch. For a frame it is instead a scale on its corners.
-- Leaving it out draws the piece at the size it was drawn at.
--
function PIECE.Layout(self, thick)
  local d = self.def
  local box = self.box
  local nw, nh = self:natural()

  if (d.nine) then
    self:layout_nine(thick or self.scale)
  elseif (d.slice and d.axis == "v") then
    local s = (thick or nw) / nw
    local f = d.slice
    local ct, cb = f[1] * nh * s, (1 - f[2]) * nh * s
    local top = self:slice(1, 0, 1, 0, f[1])
    top.base:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    top.base:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    top.base:SetHeight(ct)
    local bot = self:slice(3, 0, 1, f[2], 1)
    bot.base:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    bot.base:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    bot.base:SetHeight(cb)
    local mid = self:slice(2, 0, 1, f[1], f[2])
    mid.base:SetPoint("TOPLEFT", top.base, "BOTTOMLEFT", 0, 0)
    mid.base:SetPoint("BOTTOMRIGHT", bot.base, "TOPRIGHT", 0, 0)
    self.thick = thick or nw
  elseif (d.slice) then
    local s = (thick or nh) / nh
    local f = d.slice
    local last = #f
    local cl, cr = f[1] * nw * s, (1 - f[last]) * nw * s
    local left = self:slice(1, 0, f[1], 0, 1)
    left.base:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    left.base:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    left.base:SetWidth(cl)
    local right = self:slice(5, f[last], 1, 0, 1)
    right.base:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    right.base:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    right.base:SetWidth(cr)

    if (last == 2) then
      local mid = self:slice(2, f[1], f[2], 0, 1)
      mid.base:SetPoint("TOPLEFT", left.base, "TOPRIGHT", 0, 0)
      mid.base:SetPoint("BOTTOMRIGHT", right.base, "BOTTOMLEFT", 0, 0)
    else
      local centre = self:slice(3, f[2], f[3], 0, 1)
      centre.base:SetPoint("TOP", box, "TOP", 0, 0)
      centre.base:SetPoint("BOTTOM", box, "BOTTOM", 0, 0)
      centre.base:SetWidth((f[3] - f[2]) * nw * s)
      local ml = self:slice(2, f[1], f[2], 0, 1)
      ml.base:SetPoint("TOPLEFT", left.base, "TOPRIGHT", 0, 0)
      ml.base:SetPoint("BOTTOMRIGHT", centre.base, "BOTTOMLEFT", 0, 0)
      local mr = self:slice(4, f[3], f[4], 0, 1)
      mr.base:SetPoint("TOPLEFT", centre.base, "TOPRIGHT", 0, 0)
      mr.base:SetPoint("BOTTOMRIGHT", right.base, "BOTTOMLEFT", 0, 0)
    end
    self.thick = thick or nh
  else
    local one = self:slice(1, 0, 1, 0, 1)
    local bh = box:GetHeight()
    one.base:SetAllPoints(box)
    self.thick = thick or ((bh and bh > 0) and bh or nh)
  end

  self:Refresh()
  self:apply_shown()
end

--
-- A frame: four corners at their own size times SCALE and four sides stretched between them. The middle of a frame is cleared
-- by the build and is not drawn, but a fill nine-sliced the same way, a piece whose map says middle, has its middle stretched
-- between the four sides as well. A side can be left out, and then its two corners go with it and the sides either side of it
-- run to the edge of the box instead. A notch takes a stretch out of the top or the bottom side, which is then drawn in two
-- pieces either side of it, for words to be set into the line or for a tray to be drawn there.
--
function PIECE.layout_nine(self, scale)
  local d = self.def
  local box = self.box
  local n = d.nine
  local nw, nh = self:natural()
  local cl, cr, ct, cb = n[1] * nw * scale, n[2] * nw * scale, n[3] * nh * scale, n[4] * nh * scale
  local sd = self.sides or { left = true, right = true, top = true, bottom = true }
  local u1, u2, v1, v2 = n[1], 1 - n[2], n[3], 1 - n[4]

  self.scale = scale
  for _, s in pairs(self.slices) do
    s.hidden = true
    s.base:ClearAllPoints()
  end

  local tl = (sd.top and sd.left) and self:slice(1, 0, u1, 0, v1) or nil
  local tr = (sd.top and sd.right) and self:slice(3, u2, 1, 0, v1) or nil
  local bl = (sd.bottom and sd.left) and self:slice(6, 0, u1, v2, 1) or nil
  local br = (sd.bottom and sd.right) and self:slice(8, u2, 1, v2, 1) or nil

  if (tl) then tl.base:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0); tl.base:SetSize(cl, ct) end
  if (tr) then tr.base:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0); tr.base:SetSize(cr, ct) end
  if (bl) then bl.base:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0); bl.base:SetSize(cl, cb) end
  if (br) then br.base:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0); br.base:SetSize(cr, cb) end

  if (sd.top) then
    local t = self:slice(2, u1, u2, 0, v1)
    local tail = t
    local g = self.gaps and self.gaps.TOP

    t.base:SetPoint("TOPLEFT", tl and tl.base or box, tl and "TOPRIGHT" or "TOPLEFT", 0, 0)

    --
    -- The gap's ends are measured from one of the top side's own three points, so the y offset is the top of the box wherever
    -- it hangs and only the x anchor differs.
    --
    if (g) then
      t.base:SetPoint("BOTTOMRIGHT", box, g.at, g.x0, 0 - ct)
      tail = self:slice(10, u1, u2, 0, v1)
      tail.base:SetPoint("TOPLEFT", box, g.at, g.x1, 0)
    end

    if (tr) then
      tail.base:SetPoint("BOTTOMRIGHT", tr.base, "BOTTOMLEFT", 0, 0)
    else
      tail.base:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, 0 - ct)
    end
  end

  if (sd.left) then
    local l = self:slice(4, 0, u1, v1, v2)
    if (tl) then
      l.base:SetPoint("TOPLEFT", tl.base, "BOTTOMLEFT", 0, 0)
    else
      l.base:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    end
    if (bl) then
      l.base:SetPoint("BOTTOMRIGHT", bl.base, "TOPRIGHT", 0, 0)
    else
      l.base:SetPoint("BOTTOMRIGHT", box, "BOTTOMLEFT", cl, 0)
    end
  end

  if (sd.right) then
    local r = self:slice(5, u2, 1, v1, v2)
    if (tr) then
      r.base:SetPoint("TOPLEFT", tr.base, "BOTTOMLEFT", 0, 0)
    else
      r.base:SetPoint("TOPLEFT", box, "TOPRIGHT", 0 - cr, 0)
    end
    if (br) then
      r.base:SetPoint("BOTTOMRIGHT", br.base, "TOPRIGHT", 0, 0)
    else
      r.base:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    end
  end

  if (sd.bottom) then
    local b = self:slice(7, u1, u2, v2, 1)
    local g = self.gaps and self.gaps.BOTTOM
    if (bl) then
      b.base:SetPoint("TOPLEFT", bl.base, "TOPRIGHT", 0, 0)
    else
      b.base:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, cb)
    end

    if (g) then
      b.base:SetPoint("BOTTOMRIGHT", box, g.at, g.x0, 0)
      local b2 = self:slice(9, u1, u2, v2, 1)
      b2.base:SetPoint("TOPLEFT", box, g.at, g.x1, cb)
      if (br) then
        b2.base:SetPoint("BOTTOMRIGHT", br.base, "BOTTOMLEFT", 0, 0)
      else
        b2.base:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
      end
    elseif (br) then
      b.base:SetPoint("BOTTOMRIGHT", br.base, "BOTTOMLEFT", 0, 0)
    else
      b.base:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    end
  end

  if (d.middle) then
    local m = self:slice(11, u1, u2, v1, v2)

    m.base:SetPoint("TOPLEFT", box, "TOPLEFT", cl, 0 - ct)
    m.base:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0 - cr, cb)
  end
end

--
-- Which sides of a frame draw, as a table of left, right, top and bottom with anything unnamed drawing.
--
function PIECE.SetSides(self, sides)
  local sd = { left = true, right = true, top = true, bottom = true }

  if (type(sides) == "table") then
    for k in pairs(sd) do
      if (sides[k] ~= nil) then
        sd[k] = sides[k] and true or false
      end
    end
  end

  self.sides = sd
end

--
-- Take a stretch out of the top or the bottom side of a frame, for words to be set into the line or for a tray to be drawn
-- there. AT says which of that side's three points the gap is measured from, "TOPLEFT", "TOP" or "TOPRIGHT" along the top and
-- the three BOTTOM points along the bottom, and X0 and X1 are its two ends in pixels from there, positive rightwards. A nil
-- X0 takes the gap out again.
--
-- Measured from a point of the side rather than always from its left end, because then the anchors say where the gap belongs
-- and WoW keeps it there. A gap hung on a corner stays that far from the corner and one on the middle of a side stays in the
-- middle, however the frame is resized afterwards, without anything being laid out again.
--
-- A side has the one gap, so a tray and a notch on the bottom side are the same gap under two names.
--
function PIECE.SetNotch(self, at, x0, x1)
  self.gaps = self.gaps or {}
  self.gaps[strfind(at, "TOP", 1, true) and "TOP" or "BOTTOM"] = x0 and { at = at, x0 = x0, x1 = x1 } or nil
end

--
-- The stretch from X0 to X1 pixels along the box out of a frame's bottom side, for a tray to be drawn there. Nil for none.
--
function PIECE.SetTray(self, x0, x1)
  self:SetNotch("BOTTOMLEFT", x0, x1)
end

--
-- Three questions about where a frame piece's artwork actually is, all of them answered by the drawing rather than assumed
-- from the rim a caller asked for. Anything laid on a frame's line should be anchored to the piece's own box and placed with
-- these, and then it sits on the artwork whatever the artwork turns out to be.
--
-- SIDE is "LEFT", "RIGHT", "TOP" or "BOTTOM".
--
KIT.EDGE_AT = { LEFT = 1, RIGHT = 2, TOP = 3, BOTTOM = 4 }

--
-- How far in from the box's left and right edges the straight run of its top and bottom sides begins, which is what anything
-- set into one of those sides has to clear. The corners are drawn at their own size times the piece's scale. The two are
-- answered separately, a frame's corners not being required to match.
--
function PIECE.corners(self)
  local n = self.def.nine
  local nw = self:natural()
  local s = self.scale

  return n[1] * nw * s, n[2] * nw * s
end

--
-- Half the weight SIDE is drawn at, measured in from the box's own edge, which is the middle of the band of metal that side
-- draws. A frame's four sides are not one thickness and the scale is set from the widest of them, so half the rim a caller
-- asked for is the middle of that one side and of no other.
--
function PIECE.midline(self, side)
  return self.def.edge[KIT.EDGE_AT[side]] * self.scale / 2
end

--
-- How far outside the region it was boxed to the box's SIDE edge lies, the drawing reaching that far past its straight outer
-- line. What converts between the two sets of coordinates, for anything anchored to the frame rather than to the artwork.
--
function PIECE.overhang(self, side)
  return self.def.bleed[KIT.EDGE_AT[side]] * self.scale
end

--
-- The middle of SIDE's band again, measured from the edge of the region instead.
--
function PIECE.frameline(self, side)
  return self:midline(side) - self:overhang(side)
end

--
-- The box, anchored to REGION inset by L, T, R and B pixels, each positive inwards and negative outwards.
--
function PIECE.SetBox(self, region, l, t, r, b, thick)
  local box = self.box

  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", region, "TOPLEFT", l or 0, 0 - (t or 0))
  box:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0 - (r or 0), b or 0)
  self:Layout(thick)
end

--
-- The box anchored by the caller, who calls Layout afterwards.
--
function PIECE.Box(self)
  return self.box
end

function PIECE.apply_shown(self)
  for _, s in pairs(self.slices) do
    local on = self.shown and not s.hidden

    for _, l in ipairs(s.layers) do
      l.tex:SetShown(on)
    end

    if (s.extra) then
      for _, l in ipairs(s.extra) do
        l.tex:SetShown(on and s.extrashown)
      end
    end
  end
end

function PIECE.SetShown(self, onoff)
  self.shown = onoff and true or false
  self:apply_shown()
end

function PIECE.Show(self)
  self:SetShown(true)
end

function PIECE.Hide(self)
  self:SetShown(false)
end

function PIECE.IsShown(self)
  return self.shown
end

function PIECE.SetAlpha(self, a)
  self.alpha = a or 1
  self:Refresh()
end

function PIECE.SetState(self, state)
  if (self.state ~= state) then
    self.state = state
    self:Refresh()
  end
end

function PIECE.SetEnabled(self, onoff)
  onoff = onoff and true or false
  if (self.enabled ~= onoff) then
    self.enabled = onoff
    self:Refresh()
  end
end

--
-- Wear COLOUR whatever the window's accent is, or nil to go back to wearing the window's.
--
function PIECE.SetAccent(self, colour)
  self.fixed = colour
  self:Refresh()
end

--
-- The copies of each layer that carry the part of a state above one, made the first time a piece is hovered.
--
function PIECE.extras(self, s)
  if (s.extra) then
    return s.extra
  end

  s.extra = {}
  local sheet = KIT.sheet()
  local uv = s.uv

  for k, l in ipairs(s.layers) do
    local t = self.owner:CreateTexture(nil, self.layer, nil, self.sub + 2 + (k - 1))
    t:SetTexture(sheet)
    t:SetBlendMode("ADD")
    t:SetAllPoints(s.base)
    t:SetTexCoord(KIT.sub(l.rect, uv[1], uv[2], uv[3], uv[4]))
    s.extra[k] = { tex = t }
  end

  return s.extra
end

--
-- The colour the piece wears, and whether it is drawn flat: a colour of its own if it was given one, and otherwise its
-- window's tint, accent or gem colour, whichever its part wears, darkened by the piece's shade if it has one.
--
function PIECE.basecolour(self)
  if (self.fixed) then
    return self.fixed, self.flat
  end

  local wears = KIT.wears(self.owner, self.part)

  if (wears == "accent") then
    return KIT.accent(self.owner), self.flat
  end

  if (wears == "gem") then
    return KIT.gemcolour(self.owner), self.flat
  end

  local tint, flat = KIT.tint(self.owner)

  return tint, self.flat or flat
end

function PIECE.colour(self)
  local c, flat = self:basecolour()
  local s = self.shade

  if (s) then
    c = { r = c.r * s, g = c.g * s, b = c.b * s }
  end

  return c, flat
end

--
-- Colour every texture for the piece's colour, state and whether it is enabled. A disabled tinted piece wears KIT.COLOR_DISABLED
-- flat, and a disabled piece of its own colour is greyed and dimmed.
--
function PIECE.Refresh(self)
  local d = self.def
  local acc, flat = self:colour()
  local st = self.states[self.state] or self.states.normal
  local a = self.alpha

  if (not self.enabled) then
    acc = KIT.COLOR_DISABLED
    flat = true
    st = self.states.normal
  end

  local br, bg, bb = min(st[1], 1), min(st[2], 1), min(st[3], 1)
  local xr, xg, xb = max(st[1] - 1, 0), max(st[2] - 1, 0), max(st[3] - 1, 0)
  local lift = (xr + xg + xb) > 0

  for _, s in pairs(self.slices) do
    local lay = s.layers

    if (d.kind) then
      local k = self.intensity
      lay[1].tex:SetVertexColor(acc.r * k, acc.g * k, acc.b * k, a)
    elseif (self.accented) then
      lay[1].tex:SetVertexColor(acc.r * br, acc.g * bg, acc.b * bb, a)
    elseif (d.colour) then
      local k = self.enabled and 1 or KIT.DISABLED_OWN
      lay[1].tex:SetVertexColor(br * k, bg * k, bb * k, a)
      lay[1].tex:SetDesaturated(not self.enabled)
    elseif (flat) then
      lay[1].tex:SetVertexColor(acc.r * br, acc.g * bg, acc.b * bb, a)
      lay[2].tex:SetVertexColor(acc.r * br, acc.g * bg, acc.b * bb, a)
    else
      lay[1].tex:SetVertexColor(br, bg, bb, a)
      lay[2].tex:SetVertexColor(acc.r * br, acc.g * bg, acc.b * bb, a)
    end

    if (lift and not d.kind) then
      local ex = self:extras(s)
      for k, l in ipairs(ex) do
        -- Lit the way the piece itself is drawn, so a notint piece's lift is white whatever tint the frame asks for.
        local tinted = self.accented or (not d.colour and ((k == 2) or flat))
        if (tinted) then
          l.tex:SetVertexColor(acc.r * xr, acc.g * xg, acc.b * xb, a)
        else
          l.tex:SetVertexColor(xr, xg, xb, a)
        end
      end
      s.extrashown = true
    else
      s.extrashown = false
    end
  end

  self:apply_shown()
end

--
-- How many pixels a piece drawn THICK across takes up along its length before anything stretches: its ends, and its ornament
-- if it has one. A strip cannot usefully be drawn shorter than this.
--
function PIECE.fixedlength(self, thick)
  local d = self.def
  local f = d.slice
  local nw, nh = self:natural()

  if (not f) then
    return nw * (thick or nh) / nh
  end

  local s = (thick or nh) / nh
  local len = (f[1] + 1 - f[#f]) * nw * s

  if (#f == 4) then
    len = len + (f[3] - f[2]) * nw * s
  end

  return len
end

--
-- Where a hole or a setting sits once the piece is laid out, as an offset of its centre from the box's centre and its width
-- and height. Holes and settings are measured on the piece as drawn, so they scale with THICK, and a hole in the middle of a
-- strip stays in the middle however far it stretches.
--
function PIECE.opening(self, which)
  local d = self.def
  local r = d[which or "hole"] or d.setting or d.hole

  if (not r) then
    return nil
  end

  local nw, nh = self:natural()
  local s = (self.thick or nh) / nh
  local w, h = (r[2] - r[1]) * nw * s, (r[4] - r[3]) * nh * s
  local cy = (0.5 - (r[3] + r[4]) / 2) * nh * s

  return 0, cy, w, h
end

--
-- A gem set into a piece: the stone flat in whatever colour its PART wears, the gem part if none is named, with its sparkle
-- over it in white. In a hole the stone goes under the piece and is drawn a little bigger than the opening, so its edge tucks
-- under the rim instead of showing a gap. On a setting, an ornament drawn filled, it goes on top of the setting's well, the
-- dark inside of it, and KIT.WELL_COVER times its size. A setting with no well gets the stone at a little under the setting's
-- own size. The host's sublevel wants to be 0 for there to be room either side of it.
--
-- A stone never covers the metal it is set in: every gem keeps its border. So a stone laid on top of its setting is never
-- drawn bigger than the well it sits in.
--
KIT.WELL_COVER = 1.0

function KIT.gem(host, name, part)
  local well = host.def.well and not host.def.hole
  local ox, oy, w, h = host:opening(well and "well" or nil)

  if (not ox) then
    return nil
  end

  local g = {}
  local under = host.def.hole and true or false
  local side = max(w, h) * (under and 1.15 or (well and KIT.WELL_COVER or 0.8))
  local sub = under and max(host.sub - 6, -8) or min(host.sub + 4, 4)
  local stone = name or "GemDiamond"

  g.stone = KIT.new(host.owner, stone, { layer = host.layer, sublevel = sub, flat = true, part = part or "gem" })
  g.stone.box:SetPoint("CENTER", host.box, "CENTER", ox, oy)
  g.stone.box:SetSize(side, side)
  g.stone:Layout()

  local sparkle = stone .. "Sparkle"
  if (KIT.has(sparkle)) then
    g.shine = KIT.new(host.owner, sparkle, { layer = host.layer, sublevel = sub + 2, accent = KUI.COLOR_WHITE })
    g.shine.box:SetAllPoints(g.stone.box)
    g.shine:Layout()
  end

  g.SetShown = function(this, onoff)
    this.stone:SetShown(onoff)
    if (this.shine) then
      this.shine:SetShown(onoff)
    end
  end

  return g
end

--
-- The pieces on an interactive frame follow it: hovered while the pointer is over it, pressed while a button is held down on it,
-- normal otherwise, and dimmed when it is disabled. Every one of those is decided here from the frame's own state rather than
-- set by each event, so no order of events leaves a piece in a state its frame is not in.
--
function KIT.sync(frame)
  local list = frame.kuipieces

  if (not list) then
    return
  end

  local enabled = (frame.enabled == nil) or frame.enabled
  local state = "normal"

  if (enabled) then
    if (frame.kuidown and frame.kuiover) then
      state = "pressed"
    elseif (frame.kuiover or frame.kuifocus or frame.kuihot) then
      state = "hover"
    end
  end

  for _, p in ipairs(list) do
    p:SetEnabled(enabled)
    p:SetState(state)
  end
end

function KIT.enter(this)
  this.kuiover = true
  KIT.sync(this)
end

function KIT.leave(this)
  this.kuiover = nil
  KIT.sync(this)
end

function KIT.down(this)
  this.kuidown = true
  KIT.sync(this)
end

function KIT.up(this)
  this.kuidown = nil
  this.kuiover = this:IsMouseOver() and true or nil
  KIT.sync(this)
end

function KIT.interactive(frame, ...)
  if (not frame.kuipieces) then
    frame.kuipieces = {}
    frame:HookScript("OnEnter", KIT.enter)
    frame:HookScript("OnLeave", KIT.leave)
    frame:HookScript("OnMouseDown", KIT.down)
    frame:HookScript("OnMouseUp", KIT.up)
    frame:HookScript("OnHide", KIT.up)
  end

  for i = 1, select("#", ...) do
    local p = select(i, ...)
    if (p) then
      tinsert(frame.kuipieces, p)
    end
  end

  KIT.sync(frame)
end

--
-- Retint every piece under FRAME, after its accent changed.
--
function KIT.retint(frame)
  for p in pairs(KIT.all) do
    local f = p.owner

    while (f) do
      if (f == frame) then
        p:Refresh()
        break
      end
      f = f.GetParent and f:GetParent() or nil
    end
  end
end

--
-- The window surface, tiled over whatever the texture is anchored to. It is drawn at its own size wherever it is put, so the
-- grain is the same size in every window, and a window is never a stretched copy of one small square.
--
function KIT.surface(owner, layer, sublevel)
  local t = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or -8)

  t:SetTexture(KUI.TEXTURE_PATH .. "WindowSurface", "REPEAT", "REPEAT")
  t:SetHorizTile(true)
  t:SetVertTile(true)

  return t
end

--
-- The borders a window, a menu or a label can wear, by the name cfg.border gives them. RIM is how many pixels of gold a side
-- is drawn with, and the frame is scaled to that, so the thin border and the thick one are one piece of arithmetic. OFFSET is
-- how far in from the frame's edge its content starts, which is the rim and a little clear space inside it.
--
KIT.BORDERS = {
  THIN  = { piece = "MenuFrame", rim = 4, offset = 6 },
  THICK = { piece = "WindowDialog", rim = 10, offset = 12 },
}

--
-- A frame piece scaled so that its widest side draws RIM pixels of rim. Placed with PIECE.SetFrameBox, which stands it proud
-- of its region by however far its drawing reaches past its straight outer line at that scale, so the region's edge is where
-- the rim is and a corner flourish hangs outside it.
--
function KIT.border(owner, name, rim, opts)
  local p = KIT.new(owner, name, opts)
  local e = p.def.edge
  local widest = max(e[1], e[2], e[3], e[4])

  p.scale = (rim and widest > 0) and (rim / widest) or 1
  return p
end

function PIECE.SetFrameBox(self, region, l, t, r, b)
  local bl = self.def.bleed
  local s = self.scale

  self:SetBox(region, (l or 0) - bl[1] * s, (t or 0) - bl[3] * s, (r or 0) - bl[2] * s, (b or 0) - bl[4] * s, s)
end

--
-- How far in from the edges of the region a frame piece is boxed to the ground under it starts, at the piece's scale. A frame's
-- corners sweep in from its straight edges, so a ground drawn out to them would show outside the curve. The frame carries its
-- own surface wherever that leaves a gap inside it.
--
function PIECE.groundinset(self)
  return (self.def.ground or 0) * self.scale
end

--
-- GROUND laid under the frame piece RIM, which was boxed to REGION inset by L, T, R and B.
--
function KIT.fitground(ground, region, rim, l, t, r, b)
  local g = rim and rim:groundinset() or 0

  ground:ClearAllPoints()
  ground:SetPoint("TOPLEFT", region, "TOPLEFT", (l or 0) + g, 0 - (t or 0) - g)
  ground:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0 - (r or 0) - g, (b or 0) + g)
end

--
-- The four button silhouettes, by the name cfg.style gives them.
--
KIT.BUTTONS = {
  POINTED  = "ButtonPointed",
  ROUNDED  = "ButtonRounded",
  FINIAL   = "ButtonRoundedFinial",
  STRAIGHT = "ButtonStraight",
}

--
-- A row in a list or a menu that marks itself while the pointer is on it, and a list row that marks itself again when it is
-- selected. A menu row glows under its words in its window's tint. A list row wears a fill, faint under the pointer and whole
-- when selected, with a ring round a selected one in the window's tint: charcoal or grey rather than a colour, because a
-- row's words are often a class's colour and a coloured glow under them takes it away. The fill is the lighter of the two
-- charcoals, drawn large enough that a row as tall as several lines is never stretched past it, unless the scroll list or
-- scroll frame the row is in was made with cfg.highlight = "DARK" for the darker, the same shade as a panel's ground, or
-- "GRAIN" for the grey grain (KIT.ROW_FILLS). One made with cfg.highlight = "GLOW" marks its rows the way a menu does, in
-- cfg.highlightcolour if it gives one.
--
-- Either way the mark under the pointer is ROW.kuiglow and the one for selection ROW.kuisel. The strengths are a glow's
-- intensity and a fill's alpha.
--
KIT.ROW_HOVER = 0.35
KIT.ROW_SELECTED = 0.6
KIT.GRAIN_HOVER = 0.75
KIT.GRAIN_SELECTED = 1

KIT.ROW_FILLS = {
  GRAIN = "RowSelectGrain",
  DARK  = "RoundedDarkCharcoal",
  LIGHT = "RoundedLighterCharcoal",
}

--
-- How much darker than the window a panel's ground is, as the alpha of black laid over the window's surface.
--
KIT.PANEL_GROUND = 0.35

function KIT.rowshow(this)
  if (this.kuiglow and (this.kuiglowable == nil or this.kuiglowable)) then
    this.kuiglow:Show()
  end
end

function KIT.rowhide(this)
  if (this.kuiglow) then
    this.kuiglow:Hide()
  end
end

--
-- The glow under a row the pointer is on, in the glow part's colour or in COLOUR.
--
function KIT.rowglow(row, layer, colour)
  if (row.kuiglow) then
    return row.kuiglow
  end

  local g = KIT.new(row, "RowGlow", { layer = layer or "BACKGROUND", sublevel = 1, intensity = KIT.ROW_HOVER, part = "glow",
    accent = colour })
  g:SetBox(row, 0, 0, 0, 0)
  g:Hide()
  row.kuiglow = g
  row:HookScript("OnEnter", KIT.rowshow)
  row:HookScript("OnLeave", KIT.rowhide)
  return g
end

--
-- The fill STYLE names (KIT.ROW_FILLS) stretched over ROW at SUBLEVEL of its background and ALPHA, hidden until it is wanted.
-- It stops a pixel in from every edge, inside the selection ring. A charcoal is nine-sliced by the build, its corners rounded
-- to the ring's inner edge and drawn at their own size whatever the row's height, its sides and middle stretched between
-- them, so it follows the ring at any height as it stands. The grain is cut in three, its rounded ends drawn at the row's
-- height, and is laid out again whenever the row changes height.
--
function KIT.grain(row, style, sublevel, alpha)
  local g = KIT.new(row, KIT.ROW_FILLS[style] or KIT.ROW_FILLS.LIGHT, { layer = "BACKGROUND", sublevel = sublevel })
  local h = row:GetHeight()

  g:SetAlpha(alpha)

  if (g.def.nine) then
    g:SetBox(row, 1, 1, 1, 1, 1)
  else
    g:SetBox(row, 1, 1, 1, 1, (h and h > 2) and (h - 2) or nil)

    row:HookScript("OnSizeChanged", function(this, w, nh)
      g:Layout((nh and nh > 2) and (nh - 2) or nil)
    end)
  end

  g:Hide()

  return g
end

--
-- Whether a list row is marked the way a menu row is, "GLOW", or with a fill, "LIGHT" unless told "DARK" or "GRAIN", and in
-- what colour for a glow. Asked of the scroll list or scroll frame the row is in, which is the only thing that sets either.
--
function KIT.rowstyle(row)
  return KIT.inherited(row, "kuihighlight") or "LIGHT", KIT.inherited(row, "kuihighlightcolour")
end

--
-- The mark under a list row the pointer is on.
--
function KIT.rowhover(row)
  if (row.kuiglow) then
    return row.kuiglow
  end

  local style, colour = KIT.rowstyle(row)

  if (style == "GLOW") then
    return KIT.rowglow(row, nil, colour)
  end

  row.kuiglow = KIT.grain(row, style, 1, KIT.GRAIN_HOVER)
  row:HookScript("OnEnter", KIT.rowshow)
  row:HookScript("OnLeave", KIT.rowhide)
  return row.kuiglow
end

--
-- Mark a list row selected, or take the mark away.
--
function KIT.rowselect(row, onoff)
  if (not row.kuisel) then
    if (not onoff) then
      return
    end

    local style, colour = KIT.rowstyle(row)

    if (style == "GLOW") then
      row.kuisel = KIT.new(row, "RowGlow", { layer = "BACKGROUND", sublevel = 0, intensity = KIT.ROW_SELECTED, part = "glow",
        accent = colour })
      row.kuisel:SetBox(row, 0, 0, 0, 0)
    else
      local fill = KIT.grain(row, style, 0, KIT.GRAIN_SELECTED)
      local rim = KIT.new(row, "RowSelectRim", { layer = "BACKGROUND", sublevel = 2, part = "rowrim" })

      rim:SetBox(row, 0, 0, 0, 0)
      row.kuisel = {
        SetShown = function(this, on)
          fill:SetShown(on)
          rim:SetShown(on)
        end,
      }
    end
  end

  row.kuisel:SetShown(onoff)
end

--
-- The public face of all of this, for a caller that wants a piece of the kit on a frame of its own. See UI.txt.
--
function KUI:CreatePiece(frame, name, opts)
  return KIT.new(frame, name, opts)
end

function KUI:RowHighlight(row)
  return KIT.rowhover(row)
end

function KUI:RowSelected(row, onoff)
  KIT.rowselect(row, onoff)
end

--
-- The game's own group finder role icons, which every client has on one sheet: a tank's shield, a healer's cross and a
-- sword for everybody else, melee, ranged and caster alike. They are the game's rather than the kit's because they are
-- what a player already reads as those roles. The corners are those the game's own inline icons use.
--
KUI.ROLE_ICON_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"

local ROLE_ICON_COORDS = {
  tank   = { 0, 19 / 64, 22 / 64, 41 / 64 },
  healer = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
  damage = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

--
-- Which icon ROLE draws as, "tank", "healer" or "damage", or nil for K.ROLE_UNSET or nil. Two roles that answer the same
-- look the same, melee and caster for two.
--
function KUI:RoleIconKind(role)
  if (role == K.ROLE_TANK) then
    return "tank"
  elseif (role == K.ROLE_HEALER) then
    return "healer"
  elseif (role and role ~= K.ROLE_UNSET) then
    return "damage"
  end

  return nil
end

-- Where KIND's icon is in KUI.ROLE_ICON_TEXTURE, as a menu item's iconcoord takes it, or nil for a kind there is none of.
function KUI:RoleIconCoord(kind)
  local c = ROLE_ICON_COORDS[kind]

  return c and { left = c[1], right = c[2], top = c[3], bottom = c[4] } or nil
end

--
-- A SIZE square texture on FRAME showing a role. icon:SetRole(role) takes a K.ROLE_ number and shows its icon, or nothing
-- for K.ROLE_UNSET or nil, the square staying where it is so that a column of them lines up whatever is in it.
--
function KUI:CreateRoleIcon(frame, size)
  local icon = frame:CreateTexture(nil, "ARTWORK")

  icon:SetSize(size, size)
  icon:SetTexture(KUI.ROLE_ICON_TEXTURE)
  icon:Hide()

  icon.SetRole = function(this, role)
    local which = KUI:RoleIconKind(role)

    if (which) then
      this:SetTexCoord(unpack(ROLE_ICON_COORDS[which]))
    end

    this:SetShown(which ~= nil)
  end

  return icon
end

function KUI:GetAccent(frame)
  return KIT.accent(frame)
end

KUI.wcounters = KUI.wcounters or {}

local function add_escclose(fname)
  for k,v in pairs(UISpecialFrames) do
    if (v == fname) then
      return
    end
  end
  tinsert(UISpecialFrames, fname)
end

local function remove_escclose(fname)
  for k,v in pairs(UISpecialFrames) do
    if (v == fname) then
      -- tremove invalidates the pairs() iterator, and names are unique here.
      tremove(UISpecialFrames, k)
      return
    end
  end
end

--
-- This invisible frame is used to measure text width.
--
do
  local mframe = CreateFrame("Frame")
  mframe:Hide()
  mframe:SetHeight(64)
  mframe:SetWidth(4192)
  local mtt = mframe:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  mtt:ClearAllPoints()
  mtt:SetPoint("LEFT", mframe, "LEFT", 0, 0)
  mtt:SetPoint("RIGHT", mframe, "RIGHT", 0, 0)
  KUI.strwidth = mtt
  KUI.lastfont = "GameFontNormal"
end

--
-- A secret string, which retail hands out inside instances, is not measured. Setting one on the measuring font string would
-- make that font string's text secret, and every measurement after it would error.
--
function KUI:MeasureStrWidth(str, font)
  if (not K.CanAccess(str)) then
    return 0, 0
  end

  if (font and font ~= self.lastfont) then
    self.strwidth:SetFontObject(font)
    self.lastfont = font
  end
  self.strwidth:SetText(str or "")
  local w, h = self.strwidth:GetStringWidth(), self.strwidth:GetStringHeight()
  return w+4,h
end

--
-- The dwidth a dropdown needs to hold the longest of the things it can show, without eliding any of them and without the
-- guessed round number that is otherwise always either too wide or, in some locale nobody tested, too narrow.
--
-- It has to be asked for rather than worked out inside CreateDropDown, because plenty of dropdowns are made empty and filled
-- in later -- a config selector knows nothing at all when it is built -- and one of those would size itself to nothing. A
-- caller that knows the whole set up front, which is any dropdown over a fixed vocabulary, can use this.
--
function KUI:DropDownWidth(strings, font)
  return self:WidestString(strings, font or "GameFontHighlightSmall") + KUI.DROPDOWN_CHROME
end

--
-- How wide a box has to be to show CHARS characters of it. Nothing here is drawn in a fixed width font, so this is CHARS of
-- a middling letter rather than a promise about any particular word: something written in narrow letters leaves room to
-- spare and something in capitals is cut off. That is the bargain every width short of the longest thing that could ever be
-- in the box makes, and it is the right bargain for a box holding a name, where the longest possible one is half a line wide
-- and nobody is called that.
--
KUI.WIDTH_SPECIMEN = "n"

function KUI:CharsWidth(chars, font)
  return self:MeasureStrWidth(strrep(KUI.WIDTH_SPECIMEN, chars), font or "GameFontNormal")
end

--
-- The same for a dropdown, whose menu is sized by its own items and so still shows every name whole however narrow the
-- static portion above it is.
--
function KUI:DropDownCharsWidth(chars, font)
  return self:CharsWidth(chars, font or "GameFontHighlightSmall") + KUI.DROPDOWN_CHROME
end

--
-- How wide the widest of a set of strings comes out in FONT, and which one it was. This is what a column of labelled widgets
-- is asking for: give every label this width and their widgets line up down one edge, instead of each starting wherever its
-- own word happens to end.
--
-- Measuring rather than declaring a number is the point of it. Which string is the longest is a question about the locale,
-- and a width that lines up perfectly in one language is crooked in the next.
--
-- FONT defaults to GameFontNormal, which is what a label is drawn in unless it says otherwise.
--
function KUI:WidestString(strings, font)
  local widest = 0
  local which = nil

  for _, v in ipairs(strings or {}) do
    local w = self:MeasureStrWidth(v, font or "GameFontNormal")

    if (w > widest) then
      widest = w
      which = v
    end
  end

  return widest, which
end

--
-- The colours Blizzard's own font templates are drawn in, where the template names its colour (<Color color="NORMAL_FONT_COLOR"/>)
-- rather than giving it as numbers. Asked with GetTextColor, a font like that answers white whatever it draws in, and so does
-- every font string made from it, so the colour is taken from the name the template gives instead. Read from the clients'
-- font XML (Blizzard_Fonts_Shared), which is the same on every client. A template given its colour as numbers, and every font
-- KoreUI makes itself, answers GetTextColor truly and is not here.
--
local NAMED_FONT_COLOURS = {
  GameFontNormal = "NORMAL_FONT_COLOR", GameFontNormalLeft = "NORMAL_FONT_COLOR",
  GameFontNormalLeftBottom = "NORMAL_FONT_COLOR", GameFontNormalSmall = "NORMAL_FONT_COLOR",
  GameFontNormalSmallLeft = "NORMAL_FONT_COLOR",
  GameFontHighlight = "WHITE_FONT_COLOR", GameFontHighlightCenter = "WHITE_FONT_COLOR",
  GameFontHighlightLeft = "WHITE_FONT_COLOR", GameFontHighlightRight = "WHITE_FONT_COLOR",
  GameFontHighlightSmall = "WHITE_FONT_COLOR", GameFontHighlightSmallLeft = "WHITE_FONT_COLOR",
  GameFontHighlightSmallLeftTop = "WHITE_FONT_COLOR", GameFontHighlightSmallRight = "WHITE_FONT_COLOR",
  GameFontHighlightSmallOutline = "WHITE_FONT_COLOR", GameFontHighlightExtraSmall = "WHITE_FONT_COLOR",
  GameFontHighlightExtraSmallLeft = "WHITE_FONT_COLOR", GameFontHighlightExtraSmallLeftTop = "WHITE_FONT_COLOR",
  GameFontWhiteLarge = "WHITE_FONT_COLOR",
  GameFontDisableSmall = "DISABLED_FONT_COLOR", GameFontDisableSmall2 = "DISABLED_FONT_COLOR",
  GameFontDisableSmallLeft = "DISABLED_FONT_COLOR", GameFontNormalLeftGrey = "DISABLED_FONT_COLOR",
  GameFontGreen = "GREEN_FONT_COLOR",
}

--
-- The colour FONT draws in, a font object or its name. This is the one place anything in KoreUI learns a font's colour: a
-- widget remembers the colour its words are drawn in, to dim them and put them back, and asking the font string it has just
-- made would be told white by every template above.
--
function KUI:GetFontColor(font, rgbtab)
  local fname = (type(font) == "table" and font.GetName) and font:GetName() or font
  local named = type(fname) == "string" and NAMED_FONT_COLOURS[fname] and _G[NAMED_FONT_COLOURS[fname]]
  local r, g, b, a

  if (named) then
    r, g, b, a = named.r, named.g, named.b, 1
  else
    if (font and font ~= self.lastfont) then
      self.strwidth:SetFontObject(font)
      self.lastfont = font
    end

    r, g, b, a = self.strwidth:GetTextColor()
  end

  if (rgbtab) then
    return { r = r, g = g, b = b, a = a or 1 }
  else
    return r,g,b,a
  end
end

function KUI:GetWidgetNum(wtype)
  if (not self.wcounters[wtype]) then
    self.wcounters[wtype] = 0
  end

  self.wcounters[wtype] = self.wcounters[wtype] + 1
  return self.wcounters[wtype]
end

function KUI:GetFramePos(frame, tbl)
  local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
  local t, b = frame:GetTop() or 0, frame:GetBottom() or 0
  local l, r = frame:GetLeft() or 0, frame:GetRight() or 0

  if (tbl) then
    return { w=w, h=h, t=t, b=b, l=l, r=r }
  else
    return w, h, t, b, l, r
  end
end

--
-- Base class for a widget "object"
--
KUI.BaseClass = KUI.BaseClass or {}

local BC = KUI.BaseClass

function BC.Catch(self, event, handler)
  local _G = _G

  if (handler and type(handler) == "function") then
    self.events[event] = handler
  elseif (handler and type(handler) == "string") then
    if (self[handler] and type(self[handler]) == "function") then
      self.events[event] = self[handler]
    elseif (_G[handler] and type(_G[handler]) == "function") then
      self.events[event] = _G[handler]
    end
  elseif (not handler and self.events[event]) then
    return self.events[event]
  end
end

--
-- For each event we throw, we check two places for a handler. The first is an actual function of the event name itself in
-- the self object. This is intended for internal use and should not be overwritten. The second is a user-defined hander that
-- they install with Catch().
--
function BC.Throw(self, event, ...)
  local ok,rv,fail

  if (self[event] and type(self[event]) == "function") then
    ok, fail = safecall(self[event], self, event, ...)
    if (ok and fail) then
      return fail
    end
  end

  if (self.events[event] and type(self.events[event] == "function")) then
    ok, rv = safecall(self.events[event], self, event, ...)
    if (ok) then
      return rv
    end
  end
end

function HOOK.SetWidth(fr)
  if (fr.SetWidth) then
    hooksecurefunc(fr, "SetWidth", function(self, width)
      self:Throw("OnWidthSet", width)
    end)
  end
end

function HOOK.SetHeight(fr)
  if (fr.SetHeight) then
    hooksecurefunc(fr, "SetHeight", function(self, height)
      self:Throw("OnHeightSet", height)
    end)
  end
end

function HOOK.Enable(fr)
  if (fr.Enable) then
    fr.kuienablehooked = true
    hooksecurefunc(fr, "Enable", function(self, ...)
      self.enabled = true
      KIT.sync(self)
      self:Throw("OnEnable", true)
    end)
  end
end

function HOOK.Disable(fr)
  if (fr.Disable) then
    hooksecurefunc(fr, "Disable", function(self, ...)
      self.enabled = false
      KIT.sync(self)
      self:Throw("OnEnable", false)
    end)
  end
end

function HOOK.Show(fr)
  if (fr.Show) then
    hooksecurefunc(fr, "Show", function(self, ...)
      self:Throw("OnShow", false)
    end)
  end
end

function HOOK.Hide(fr)
  if (fr.Hide) then
    hooksecurefunc(fr, "Hide", function(self, ...)
      self:Throw("OnHide", false)
    end)
  end
end

--
-- ONOFF is tested for truth, so nil disables, as the game's own SetEnabled does. A widget's constructor that is told nothing
-- starts it enabled through cfg_enabled.
--
function BC.SetEnabled(self, onoff)
  onoff = onoff and true or false

  if (not self.Enable or not self.Disable) then
    self.enabled = onoff
    KIT.sync(self)
    self:Throw("OnEnable", onoff)
    return
  end

  if (onoff) then
    self:Enable()
  else
    self:Disable()
  end

  -- A frame whose Enable and Disable are hooked has had OnEnable thrown by the hook already, and gets it once.
  if (not self.kuienablehooked) then
    self:Throw("OnEnable", onoff)
  end
end

--
-- Give the frame an accent, a tint or a gem colour of its own, which it and everything under it wears. Each takes a colour
-- table or three numbers, and nil takes it away again, so that the frame goes back to wearing whatever is above it.
--
function KIT.colourof(r, g, b)
  if (type(r) == "table") then
    return { r = r.r or 1, g = r.g or 1, b = r.b or 1 }
  elseif (r) then
    return { r = r, g = g or r, b = b or r }
  end

  return nil
end

function BC.SetAccent(self, r, g, b)
  self.kuiaccent = KIT.colourof(r, g, b)
  KIT.retint(self)
end

function BC.SetTint(self, r, g, b)
  self.kuitint = KIT.colourof(r, g, b)
  KIT.retint(self)
end

function BC.SetGem(self, r, g, b)
  self.kuigem = KIT.colourof(r, g, b)
  KIT.retint(self)
end

--
-- Whether a widget's value differs from what is saved. Its value is then written in DEFAULT_CHANGED_COLOR, a checkbox's words
-- being its value. The widget's own OnEnable is what paints its words, so that is what is run again, and every later enable
-- or disable keeps the colour. A widget with no words to colour takes the flag and shows nothing.
--
function BC.SetChanged(self, onoff)
  onoff = onoff and true or false

  if (self.kuichanged == onoff) then
    return
  end

  self.kuichanged = onoff

  if (self.OnEnable) then
    self:OnEnable(nil, self.enabled)
  end
end

-- As with SetEnabled, nil hides, as the game's own SetShown does.
function BC.SetShown(self, onoff)
  if (onoff) then
    self:Show()
  else
    self:Hide()
  end
end

--
-- Whether a widget starts out enabled: as CFG.enabled says, and enabled when it says nothing.
--
local function cfg_enabled(cfg)
  if (cfg.enabled == nil) then
    return true
  end

  return cfg.enabled and true or false
end

local function generic_OnEnter(this)
  this:Throw("OnEnter")
end

local function generic_OnLeave(this)
  this:Throw("OnLeave")
end

local function do_tooltip_onenter(this, enabled)
  if ((not this.tiptitle) and (not this.tiptext)) then
    return
  end

  if (not enabled) then
    return
  end

  local tf = GameTooltip.SetText
  local r, g, b

  --
  -- The owner is set, and the placement function run, before anything goes in the tooltip, setting an owner being what clears it.
  --
  if (this.tipfunc) then
    GameTooltip:SetOwner(this, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", this, "TOPRIGHT", 5, 0)
    this.tipfunc(this)
  else
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
  end

  if (this.tiptitle) then
    tf = GameTooltip.AddLine
    r = HIGHLIGHT_FONT_COLOR.r
    g = HIGHLIGHT_FONT_COLOR.g
    b = HIGHLIGHT_FONT_COLOR.b
    GameTooltip:SetText(this.tiptitle, r, g, b, 1)
  end

  if (this.tiptext) then
    r = NORMAL_FONT_COLOR.r
    g = NORMAL_FONT_COLOR.g
    b = NORMAL_FONT_COLOR.b
    tf(GameTooltip, this.tiptext, r, g, b, 1)
  end

  GameTooltip:Show()
end

local function tip_OnEnter(this, event)
  do_tooltip_onenter(this, this.enabled)
end

local function tip_OnLeave(this, event)
  GameTooltip:Hide()
end

local function apply_hooks(fr)
  HOOK.SetWidth(fr)
  HOOK.SetHeight(fr)
  HOOK.Enable(fr)
  HOOK.Disable(fr)
  HOOK.Show(fr)
  HOOK.Hide(fr)
  fr:HookScript("OnEnter", generic_OnEnter)
  fr:HookScript("OnLeave", generic_OnLeave)
end

local function newobj(cfg, kparent, defwt, defht, fname, ftype)
  local defh, defw
  local lx = 0
  local ly = 0

  if (type(defwt) == "table") then
    defw = defwt[1]
    lx = defwt[2]
  else
    defw = defwt
  end

  if (type(defht) == "table") then
    defh = defht[1]
    ly = defht[2]
  else
    defh = defht
  end

  local parent

  --
  -- If defh and defw are both 0 it means we have a somewhat special case here, and kparent isn't a typical KahLua KoreUI
  -- return, but instead any simple frame. Set parent accordingly.
  --
  if (defh == 0 and defw == 0) then
    parent = kparent
  else
    if (cfg.parent) then
      parent = cfg.parent
    elseif (kparent and kparent.content) then
      parent = kparent.content
    elseif (kparent) then
      parent = kparent
    else
      parent = UIParent
    end
  end

  local frame = MakeFrame(ftype or "Frame", fname, parent)
  frame:Show()
  if (cfg.level) then
    frame:SetFrameLevel(cfg.level)
  end
  local width  = cfg.width or defw or 100
  local height = cfg.height or defh or 100

  frame.Catch = BC.Catch
  frame.Throw = BC.Throw
  frame.SetEnabled = BC.SetEnabled
  frame.SetShown = BC.SetShown
  frame.SetChanged = BC.SetChanged
  frame.SetAccent = BC.SetAccent
  frame.SetTint = BC.SetTint
  frame.SetGem = BC.SetGem

  --
  -- The frame's colours, and which parts wear which. See KIT.accent, KIT.tint, KIT.gemcolour and KIT.PARTS.
  --
  frame.kuiaccent = KIT.colourof(cfg.accent)
  frame.kuitint = KIT.colourof(cfg.tint)
  frame.kuigem = (type(cfg.gem) == "table") and KIT.colourof(cfg.gem) or nil

  if (cfg.tintflat ~= nil) then
    frame.kuitintflat = cfg.tintflat and true or false
  end

  if (type(cfg.parts) == "table") then
    frame.kuiparts = {}
    for k, v in pairs(cfg.parts) do
      frame.kuiparts[k] = v
    end
  end

  --
  -- Marks, a checkbox's tick or cross and a menu's check, keep their own green or red unless this frame or one above it asks
  -- for them to wear the window's colour for the mark part with cfg.markcolour = false. See KIT.markaccented.
  --
  if (cfg.markcolour ~= nil) then
    frame.kuimarkcolour = cfg.markcolour and true or false
  end

  --
  -- Whether a button on this frame or under it fills its dark middle: true for the buttonfill part, a colour for exactly that
  -- colour, false for none whatever a frame above says. Left out, the frames above decide, and with none saying the fill is
  -- the buttonfill part's. See KIT.buttonfill.
  --
  if (type(cfg.buttonfill) == "table") then
    frame.kuibuttonfill = KIT.colourof(cfg.buttonfill)
  elseif (cfg.buttonfill ~= nil) then
    frame.kuibuttonfill = cfg.buttonfill and true or false
  end

  frame.events = {}
  apply_hooks(frame)
  frame.groupname = cfg.group or nil

  if (width > 0) then
    frame:SetWidth(width)
  end

  if (height > 0) then
    frame:SetHeight(height)
  end

  --
  -- If defh and defw are both 0, it means we have a "special" case on our hands, where the calling function will do all the placement.
  --
  if (defw ~= 0 and defh ~= 0) then
    if (cfg.x) then
      if (cfg.x ~= "CENTER") then
        frame:SetPoint("LEFT", parent, "LEFT", cfg.x + lx, 0)
        frame.centerx = nil
      else
        local pw = floor(width / -2)
        frame:SetPoint("LEFT", parent, "CENTER", pw, 0)
        frame.centerx = true
      end
    end

    if (cfg.y) then
      if (cfg.y ~= "MIDDLE") then
        frame:SetPoint("TOP", parent, "TOP", 0, cfg.y + ly)
        frame.centery = nil
      else
        frame:SetPoint("TOP", parent, "CENTER", 0, height / 2)
        frame.centery = true
      end
    end
  end

  if (cfg.tooltip) then
    frame.tiptitle = cfg.tooltip.title
    frame.tiptext = cfg.tooltip.text
    frame.tipfunc = cfg.tooltip.func
  end

  if (cfg.newobjhook) then
    cfg.newobjhook(frame, cfg, parent, width, height)
  end

  if (cfg.debug) then
    local ttt = frame:CreateTexture(nil, "ARTWORK")
    ttt:SetAllPoints(frame)
    ttt:SetColorTexture(0.3, 0.3, 0.3, 0.5)
  end

  return frame, parent, width, height
end

local function check_tooltip_title(frame, cfg, title)
  if (cfg.tooltip and cfg.tooltip.title == "$$") then
    frame.tiptitle = title
  end
end

--
-- Some widgets draw outside their own frame. A slider is a Blizzard Slider whose backdrop is the bar, so the bar is all the
-- frame can ever be, yet the widget also puts a label over it and a value box under it. A dropdown with a label above is the
-- same shape. The frame cannot grow to cover them without stretching the artwork it owns, which is Blizzard's and not ours to re-anchor.
--
-- So the frame stays the size of its own piece and GetHeight is taught what the whole widget occupies, because that is the
-- question a column asks. The widget is placed by the top of everything it draws, which newobj's second height element
-- already arranges by pushing the frame down past its label.
--
local function drawn_extent(frame, above, below)
  local above = above or 0
  local below = below or 0

  if (above == 0 and below == 0) then
    return
  end

  local realheight = frame.GetHeight

  frame.drawnabove = above
  frame.drawnbelow = below
  frame.GetHeight = function(this)
    return realheight(this) + this.drawnabove + this.drawnbelow
  end
end

local function parent_StartMoving(this)
  local pf = this:GetParent()
  pf:StartMoving()
  if (pf.Throw) then
    pf:Throw("OnStartMoving")
  end
end

local function parent_StopMoving(this)
  local pf = this:GetParent()
  pf:StopMovingOrSizing()
  if (pf.Throw) then
    pf:Throw("OnStopMoving")
  end
end

--
-- The space between one widget and the next. A panel laying out a column walks down it with
--
--   ypos = ypos - widget:GetHeight() - KUI.WIDGET_GAP
--
-- and that is the whole of it: no per-panel constant, and nothing that has to know what kind of widget it just placed. That
-- works only because a widget's frame is the size of the box it draws -- an edit box is 20 because its text field is drawn
-- 20 tall, a dropdown is 24 because its pill is. A frame with dead space in it forces every caller to correct for it by eye,
-- and then the gaps down a column are even in the source and uneven on the screen.
--
-- So if a layout needs a number that is not this one, the widget is lying about its size. Fix the widget.
--
KUI.WIDGET_GAP = 4

--
-- The space between the parts of one widget: a checkbox and the words beside it, a dropdown and the label over it. Nothing a
-- caller places is separated by this, and nothing inside a widget is separated by WIDGET_GAP. They are deliberately two
-- numbers even when they hold the same value, because they answer different questions -- how far apart are two things the
-- user thinks of as separate, against how close together are the pieces of one thing -- and tuning either must not disturb the other.
--
KUI.INTERNAL_GAP = 4

--
-- What a dropdown wants after it on top of the standard gap. A column that has just placed a dropdown steps by
--
--   ypos = ypos - dd:GetHeight() - KUI.WIDGET_GAP - KUI.DROPDOWN_ADD_GAP
--
-- It is none, the pill being drawn exactly the size of its frame. It stays a number of its own so that a dropdown can be given
-- more room than a checkbox if the eye asks for it, without every column that places one having to change.
--
KUI.DROPDOWN_ADD_GAP = 0

--
-- How far one notch of the wheel moves a text area, in pixels rather than lines: a line is whatever font the caller gave it
-- and the box is not asked how tall one of its lines is.
--
KUI.TEXTAREA_WHEEL_STEP = 20

--
-- A panel is three rings deep on every side. The frame handed back is the outer box and the size the caller asked for is that outer size:
--
--   cfg.padding        space between the frame edge and the artwork, so that a panel stands clear of its neighbours and
--                      of the window. Two panels side by side each give up this much, so the space between them is twice
--                      it and no separate gutter is needed anywhere.
--   INSET_BORDER       the rim itself. PanelBorder is scaled so that its rim draws this many pixels on every side, which
--                      makes this number the rim's size rather than a measurement of it.
--   cfg.inner_padding  space inside the artwork before the usable area. The border is the panel's neighbour as far as the
--                      first widget is concerned, so this is the standard gap.
--
-- So a 100x100 panel with the defaults has its artwork box from 4,4 to 96,96 and ret.content, the part a caller can use, from 12,12 to 88,88.
--
KUI.INSET_BORDER = 4
KUI.INSET_PADDING = 4
KUI.INSET_INNER_PADDING = KUI.WIDGET_GAP

--
-- The height of a dropdown's box, which is what CreateDropDown gives the frame. A caller putting a dropdown on a row beside
-- something shorter needs this to work out how far to drop the shorter thing so that the two sit on one centre line.
--
KUI.DROPDOWN_HEIGHT = 24

--
-- How wide a scroll bar is, and the strip a scroll list keeps on its right to hold it. The strip is the bar and the space
-- between the bar and the rows, so a row laid out to the list's own width stands clear of the bar by that much.
--
KUI.SCROLLBAR_WIDTH = 16
KUI.SCROLLBAR_COMPENSATE = KUI.SCROLLBAR_WIDTH + 4

--
-- Where a dropdown's words sit inside its pill: clear of the rounded end on the left, and on the right clear of the end and of
-- the chevron standing just inside it. What a dropdown costs beyond the words in it is the two together.
--
KUI.DROPDOWN_TEXT_LEFT = 14
KUI.DROPDOWN_TEXT_RIGHT = 30
KUI.DROPDOWN_CHROME = KUI.DROPDOWN_TEXT_LEFT + KUI.DROPDOWN_TEXT_RIGHT

--
-- The box a checkbox draws, which its label starts to the right of. A caller laying checkboxes out in columns needs this to
-- know what one costs beyond the words in it, and one laying them out in rows steps by this plus WIDGET_GAP like any other
-- widget. The box is the whole of its artwork, the kit's pieces being cut tight to what they draw, and a checkbox given a
-- height draws a box that size.
--
KUI.CHECKBOX_SIZE = 16

--
-- How far a checkbox's label is lifted off the vertical centre it would otherwise sit on. A font string is centred on its
-- line box, which reserves room under the baseline for descenders whether the words have any or not, so a label reading
-- "Ignore Item" hangs its g into that room and reads low beside one reading "Warrior", which does not. Lifting by half the
-- descent centres the letters instead of the space they are allowed to occupy.
--
-- Zero centres on the line box, which is what Blizzard's own labels do.
--
KUI.CHECKBOX_LABEL_LIFT = 0

--
-- Clear air past the end of a labelled checkbox's words when it sizes itself to them, so the label does not finish hard
-- against the frame's edge. A caller sizing a column of checkboxes to their longest label wants the same arithmetic the
-- widget uses, which is the words, the box, KUI.INTERNAL_GAP between the two, and this.
--
KUI.CHECKBOX_LABEL_PAD = 12

--
-- Either ring is a single number for all four sides, or a table naming any of left, right, top and bottom with anything left
-- out taken as none. Left out altogether the ring is the framework default.
--
local function padding_sides(spec, def)
  if (type(spec) == "table") then
    return {
      left = spec.left or 0, right = spec.right or 0,
      top = spec.top or 0, bottom = spec.bottom or 0
    }
  end

  local n = tonumber(spec) or def

  return { left = n, right = n, top = n, bottom = n }
end

--
-- Which of a panel's four edges draw. cfg.inset_art left out, or true, is all four, which is what almost every panel wants.
-- A table names the sides that differ and anything not named still draws, so { top = false } reads as "everything but the top".
--
-- Suppressing an edge only stops it being drawn. Both paddings belong to the panel rather than to the border and are kept,
-- so the content sits where it would have, INSET_BORDER pixels further out.
--
-- A container is all three rings at zero and nothing more:
--
--   { inset_art = false, padding = 0, inner_padding = 0 }
--
-- is a frame whose content is the whole of it. SetBorderShown(false) is that same state arrived at later rather than a
-- different thing, and it exists because a panel usually cannot know it is a container when it is made. The splits find out
-- only when they are built inside one.
--
local INSET_SIDES = { "left", "right", "top", "bottom" }

local function inset_edges(spec)
  local e = { left = true, right = true, top = true, bottom = true }

  if (type(spec) == "table") then
    for _, k in ipairs(INSET_SIDES) do
      if (spec[k] ~= nil) then
        e[k] = spec[k] and true or false
      end
    end
  end

  return e
end

--
-- A TITLE PLATE is words on a small plate, which is how anything in this toolkit says what it is. A panel hangs one on one
-- of its own edges, a dialog hangs one off its border. They are the same object built by the same code, and only where it is hung differs.
--
-- Everything about a title is one table, rather than a handful of cfg.titleSomething keys spread through the host widget's own options:
--
--   { text, location, style, width, height, padding, font }
--
-- A title is one thing with several properties and reads as one, and having a shape of its own it can be handed along
-- untouched by anything that builds one widget on behalf of another -- which is what the splits do with their panes, and
-- CreatePopupList with its dialog. A bare string is that table with only its text filled in, which is what nearly every caller wants.
--
-- Every plate is WindowTitlePlaque, the plaque with a star finial at each end and the window's gem set in the diamond on its
-- top edge. The kit has the one plaque, drawn at the largest size any title wants, and the styles differ only in the size
-- they draw it at, their font and their padding:
--
--   THIN is what one section of a page wants, and is what a panel takes if it says nothing.
--
--   THICK is for something that is a whole thing in its own right, and is what a dialog takes if it says nothing.
--
--   WINDOW is the one set into the top edge of a tabbed window.
--
-- A plate is a strip: its ends and its ornament are drawn at their own size and only the runs between them stretch, which is
-- why a plate can never be narrower than those.
--
local TITLE = {}

--
-- All three wear WindowTitlePlaque. The gem hanging on the plate's top line dips into the box below it, and how far
-- it dips decides the shortest plate that still has room for a line of words, the whole drawing scaling together. This
-- one's dip clears the words at every height here. The kit also carries WindowTitlePlaqueBigGem, the deeper-set original,
-- and SquareTitlePlaque, whose ends are square rather than tapered to a point. Neither is worn by anything today.
--
TITLE.STYLES = {
  THIN   = { height = 30, font = "GameFontNormal", padding = 8, piece = "WindowTitlePlaque", gem = true, part = "plaque" },
  THICK  = { height = 34, font = "GameFontNormal", padding = 12, minwidth = 100, piece = "WindowTitlePlaque", gem = true,
    part = "plaque" },
  WINDOW = { height = 36, font = "GameFontNormal", padding = 16, piece = "WindowTitlePlaque", gem = true, part = "title",
    gempart = "titlegem" },
}

--
-- Where a title hangs. It names one of six places, and takes the middle of the top edge when it names none, which is where
-- every title in this toolkit hung before there was a choice. A location is two facts and only two, the edge the plate is hung
-- on and where along that edge it sits, and every host needs both of them. The names are the caller's own, so the middle of a
-- horizontal edge is "middle" there, while the anchor it becomes is CENTER, this being one word about an edge and the other
-- about an axis.
--
-- A host with only the one edge to hang a plate on says so and a location naming the other keeps its end and moves to the edge
-- there is. That is a tabbed window, whose bottom edge is the tray its page buttons stand in.
--
TITLE.LOCATIONS = {
  topleft      = { edge = "TOP",    align = "LEFT" },
  topmiddle    = { edge = "TOP",    align = "CENTER" },
  topright     = { edge = "TOP",    align = "RIGHT" },
  bottomleft   = { edge = "BOTTOM", align = "LEFT" },
  bottommiddle = { edge = "BOTTOM", align = "CENTER" },
  bottomright  = { edge = "BOTTOM", align = "RIGHT" },
}

TITLE.DEFAULT_LOCATION = TITLE.LOCATIONS.topmiddle

function TITLE.location(spec)
  local name = (type(spec) == "table") and spec.location or nil

  return TITLE.LOCATIONS[strlower(name or "")] or TITLE.DEFAULT_LOCATION
end

--
-- Which edge a title asks to hang on, answered without building anything, for a host that has to lay the room out before it
-- has a plate to measure. Nil for no title at all.
--
function TITLE.edgeof(spec)
  return (spec ~= nil) and TITLE.location(spec).edge or nil
end

--
-- The anchor point a plate is hung by, which is its edge and, for one hung on a corner, the end of it.
--
function TITLE.anchor(plate)
  return plate.edge .. ((plate.align == "CENTER") and "" or plate.align)
end

--
-- Hang PLATE on its own edge of FRAME. Y is where the plate's outer edge goes, measured from that edge of the frame and
-- positive inwards, so a host that hangs the plate outside its frame gives a negative one. SIDE is how far in from the corner
-- a plate hung on one starts, and is ignored by a plate in the middle of its edge.
--
-- Both are the host's to work out, because what a plate has to clear is the host's own business. The panel knows where its rim
-- draws its corners and the dialog knows where it put its close button.
--
function TITLE.hang(frame, plate, y, side)
  local at = TITLE.anchor(plate)
  local x = 0

  if (plate.align == "LEFT") then
    x = side
  elseif (plate.align == "RIGHT") then
    x = 0 - side
  end

  plate:ClearAllPoints()
  plate:SetPoint(at, frame, at, x, (plate.edge == "TOP") and (0 - y) or y)
end

--
-- How far a plate hung on RIM's line reaches past that line into the frame, which is the room the content has to clear on
-- that edge. The tips sit on the middle of the band, so what reaches in is the rest of the plate below them at the head of a
-- frame and the whole of the plaque above them at its foot, the stone standing above the plaque either way. Measured from the
-- frame's edge rather than from the artwork's, the artwork standing proud of it.
--
function TITLE.reach(rim, plate)
  local th = plate:GetHeight()
  local tip = TITLE.point(plate) * th
  local top = plate.edge == "TOP"

  return rim:midline(plate.edge) + (top and (th - tip) or tip) - rim:overhang(plate.edge)
end

--
-- Hang PLATE on the line of the frame piece RIM, with the tips of its ends on the middle of that line. A frame's rim is where
-- it is and cannot move to meet a plate the way a panel's edge can, so here the plate is anchored to the rim's own box and
-- placed by the drawing. Nothing is measured against the frame, and a side drawn lighter than the rim the caller asked for is
-- no longer a couple of pixels of error.
--
-- PAST is anything else at that corner the plate has to clear, measured from the same box, for a host with its own furniture
-- there. The corner itself is always cleared. Returns what TITLE.reach answers, the host having to make room for it.
--
function TITLE.hangon(rim, plate, past)
  local th = plate:GetHeight()
  local tip = TITLE.point(plate) * th
  local top = plate.edge == "TOP"
  local cl, cr = rim:corners()
  local side = max(past or 0, (plate.align == "RIGHT") and cr or cl) + KUI.WIDGET_GAP

  TITLE.hang(rim:Box(), plate, rim:midline(plate.edge) - (top and tip or (th - tip)), side)

  return TITLE.reach(rim, plate)
end

--
-- Width of the plate for the text in it: what the string measures, a margin each side, and the two ends. The ends are
-- ornament flaring off the plate rather than room for words, so the margin is measured from where they stop. The ornament in
-- the middle stands on the top edge above the words and costs nothing, but the plate is never drawn shorter than all of its fixed parts together.
--
function TITLE.measure(this)
  --
  -- The words decide the width, so a longer title in another language simply makes a wider plate. What they cannot do is
  -- make it too small to read as a plate at all, so a short title, or none, is held to a floor first and the padding and the
  -- ends go on top of whatever that came to.
  --
  local w = max(ceil(this.text:GetStringWidth()), this.minw) + (2 * this.pad) + this.ends

  return max(w, ceil(this.fixed) + 2)
end

--
-- Not called SetWidth: that is a real frame method and this is not it. What is set here is the plate as a whole, and the art
-- follows the frame, stretching its runs to fit.
--
function TITLE.setwidth(this, width)
  this:SetWidth(width)
  TITLE.custom(this)
end

--
-- Ask a plate's customtitle whether it has the plate's box, and show the box or hide it by the answer. The box is the
-- caller's to draw in, anchored and sized here, so a plate that changes size asks again for the caller to lay its drawing
-- out afresh. A callback that raises has not taken the box, and the plate stays plain.
--
function TITLE.custom(this)
  if (not this.customtitle) then
    return
  end

  local ok, mine = safecall(this.customtitle, this, this.box)

  this.box:SetShown((ok and mine) and true or false)
end

--
-- The piece's ends, the part of a strip before its first stretch and after its last, at thickness TH.
--
function KIT.ends(p, th)
  local d = p.def
  local f = d.slice

  if (not f) then
    return 0
  end

  local nw, nh = p:natural()

  return (f[1] + 1 - f[#f]) * nw * th / nh
end

--
-- How far below its middle a strip's words sit, where its body is not the whole of its height: a plaque with a diamond
-- standing on its top edge has its body below the diamond, and words centred on the whole plaque would sit high in the body.
-- The build measures the body as the rows its stretch covers.
--
function KIT.bodyoffset(p, th)
  local b = p.def.body

  if (not b) then
    return 0
  end

  return (0.5 - (b[1] + b[2]) / 2) * th
end

function TITLE.settext(this, text)
  if (this.fulltext) then
    this.fulltext = text or ""
    this.text:SetText(TITLE.plain(this.fulltext))
  else
    this.text:SetText(text or "")
  end

  --
  -- A plate given an explicit width keeps it whatever it is later told to say, because the caller sized it to fit a column
  -- or a neighbour rather than to fit these particular words.
  --
  if (this.auto) then
    TITLE.setwidth(this, TITLE.measure(this))
  end
end

--
-- Hold the plate at WIDTH whatever it is later told to say, as a plate made with a width is held, or with WIDTH nil let it
-- measure itself against its words again. For a title whose words change as it is watched, a countdown, which would
-- otherwise grow and shrink with every digit.
--
function TITLE.holdwidth(this, width)
  this.auto = (width == nil)
  TITLE.setwidth(this, tonumber(width) or TITLE.measure(this))
end

--
-- Build one. SPEC is the table or string above, or nil for no plate at all. DEFSTYLE is only the fallback: a spec naming a
-- style gets that style, so a panel can ask for THICK and a dialog for THIN. ONLYEDGE is for a host with a single edge to hang
-- a plate on and forces the plate to it. The plate is returned unanchored, carrying the location it asked for, because where it
-- hangs is the whole of what the host widget has left to decide.
--
function TITLE.plate(parent, spec, defstyle, onlyedge)
  if (spec == nil) then
    return nil
  end

  if (type(spec) ~= "table") then
    spec = { text = spec }
  end

  local st = TITLE.STYLES[string.upper(spec.style or "")] or TITLE.STYLES[defstyle]
  local loc = TITLE.location(spec)
  local th = tonumber(spec.height) or st.height
  local plate = MakeFrame("Frame", nil, parent)

  plate.edge = onlyedge or loc.edge
  plate.align = loc.align
  plate:SetHeight(th)
  plate.pad = tonumber(spec.padding) or st.padding

  --
  -- The least the words may measure before the padding is added. A window's plate has one so that a short name, or a window
  -- that names only its owner, still gets a plate rather than a stub; a panel's does not, sitting among other panels and
  -- wanting to be no wider than it has to be.
  --
  plate.minw = tonumber(spec.minwidth) or st.minwidth or 0
  plate.auto = spec.width == nil
  plate.SetPlateWidth = TITLE.setwidth
  plate.SetTitleText = TITLE.settext
  plate.HoldWidth = TITLE.holdwidth

  local art = KIT.new(plate, st.piece, { layer = "BORDER", part = st.part })
  art:SetBox(plate, 0, 0, 0, 0, th)
  plate.art = art
  plate.ends = KIT.ends(art, th)
  plate.fixed = art:fixedlength(th)

  if (st.gem) then
    plate.gem = KIT.gem(art, nil, st.gempart)
  end

  --
  -- A plate whose innards its caller draws, spec.customtitle, has a box for them: the rectangle between its two ends, from
  -- the top of its body under the diamond to its foot, which is what the words are centred in. The box is a frame of its own
  -- over the plaque, and the words go on one over that, so that whatever the caller draws lies between the two.
  --
  local lettering = plate

  if (type(spec.customtitle) == "function") then
    local body = art.def.body or { 0, 1 }

    plate.customtitle = spec.customtitle
    plate.box = MakeFrame("Frame", nil, plate)
    plate.box:SetPoint("TOPLEFT", plate, "TOPLEFT", plate.ends / 2, 0 - body[1] * th)
    plate.box:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", 0 - plate.ends / 2, (1 - body[2]) * th)
    plate.box:Hide()

    lettering = MakeFrame("Frame", nil, plate)
    lettering:SetAllPoints(plate)
    KUI:SetFrameLevelKeeping(lettering, plate:GetFrameLevel() + 2)
  end

  local tt = lettering:CreateFontString(nil, "OVERLAY", spec.font or st.font)

  --
  -- The words sit on the middle of the box, and nowhere else.
  --
  -- The box is the plate proper: the two lines with the sloped ends between them, whose side points sit on the rule the
  -- plate straddles. Its middle is that rule, so words with their MIDDLE on it are exactly between the top and bottom lines
  -- and, CENTER, exactly between the sides. Nothing is measured against the stone and nothing is nudged.
  --
  -- That middle is not the texture's middle. The stone stands above the box, so the texture is taller than the box and the
  -- side points fall at TITLE.point down it rather than halfway. This is the difference between the two.
  --
  -- The gap under the stone is opened by making the box taller, never by moving the words: the box grows about its middle,
  -- the words stay on it, and the stone rides up with the top line away from them. See TITLE.STYLES.
  --
  tt:SetPoint("CENTER", plate, "CENTER", 0, 0 - (TITLE.point(plate) - 0.5) * th)
  tt:SetJustifyH("CENTER")
  tt:SetJustifyV("MIDDLE")
  tt:SetText(spec.text or "")

  --
  -- Said rather than left to the font, so that the colour the kit writes in is one line and anything drawn to match a title
  -- can name the same default. Disabling a plate saves this and puts it back, so it survives being dimmed.
  --
  tt:SetTextColor(KUI.DEFAULT_ARTWORK_COLOR.r, KUI.DEFAULT_ARTWORK_COLOR.g, KUI.DEFAULT_ARTWORK_COLOR.b)
  plate.text = tt

  TITLE.setwidth(plate, tonumber(spec.width) or TITLE.measure(plate))

  return plate
end

--
-- Dim a plate for a panel that cannot be used, or bring it back. The plaque and its gem wear the kit's disabled grey, the
-- gem's sparkle goes out, and the words take KIT.COLOR_DISABLED_TEXT, the colour they had being put back after. Colour codes in the
-- words would outrank that, so a disabled plate shows its words without them and keeps the whole of them in fulltext, which
-- is what it shows again when it is enabled, whatever it was told to say in between.
--
KIT.COLOR_DISABLED_TEXT = { r = 0.5, g = 0.5, b = 0.5 }

function TITLE.plain(text)
  local s = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

  return s
end

function TITLE.setenabled(plate, onoff)
  if (not onoff) then
    if (not plate.fulltext) then
      plate.fulltext = plate.text:GetText() or ""
      plate.text:SetText(TITLE.plain(plate.fulltext))
    end
  elseif (plate.fulltext) then
    local full = plate.fulltext
    plate.fulltext = nil
    plate.text:SetText(full)
  end

  plate.art:SetEnabled(onoff)

  if (plate.gem) then
    plate.gem.stone:SetEnabled(onoff)
    if (plate.gem.shine) then
      plate.gem.shine:SetShown(onoff)
    end
  end

  if (not onoff) then
    if (not plate.textcolour) then
      local r, g, b, a = plate.text:GetTextColor()
      plate.textcolour = { r = r, g = g, b = b, a = a }
    end
    plate.text:SetTextColor(KIT.COLOR_DISABLED_TEXT.r, KIT.COLOR_DISABLED_TEXT.g, KIT.COLOR_DISABLED_TEXT.b)
  elseif (plate.textcolour) then
    local c = plate.textcolour
    plate.text:SetTextColor(c.r, c.g, c.b, c.a)
    plate.textcolour = nil
  end
end

--
-- How far down a plate the tips of its ends are, as a fraction of its height. A plate laid across a line is placed by its tips,
-- which sit lower than its middle when its plaque keeps room above itself for a gem.
--
function TITLE.point(plate)
  return plate.art.def.point or 0.5
end

--
-- The host's half of it: hand the plate on to whoever asks the widget for it, so that ret.title, ret.titletext,
-- ret:SetTitleText, ret:SetTitleWidth and ret:RedrawTitle mean the same thing on a panel and on a dialog.
--
function TITLE.attach(frame, plate)
  frame.title = plate
  frame.titletext = plate.text

  frame.SetTitleText = function(this, text)
    this.title:SetTitleText(text)
  end

  frame.SetTitleWidth = function(this, width)
    this.title:HoldWidth(width)
  end

  frame.RedrawTitle = function(this)
    TITLE.custom(this.title)
  end
end

--
-- A panel names itself on a plate straddling one of its own edges, hung so that the panel's border runs through the middle of
-- it. Straddling is the whole point. A plate sitting wholly outside the panel is a caption floating in the window, and one
-- sitting wholly inside it is just a widget somebody put there. On the line it belongs to the panel and says what the panel
-- is. The plate is opaque, so the border stops at its edges instead of being drawn through the words.
--
-- The plate hangs on the padding, its outer edge where the padding ends, and the panel's line comes to meet it. That is the
-- same arrangement whichever edge it is on, so a title at the foot of a panel is a title at the head of it turned over.
--
-- What is not turned over is the plaque. Its stone stands above it and cannot be drawn any other way up, so a plate at the
-- foot of a panel keeps its stone inside the panel where a plate at the head keeps it outside. A foot title therefore
-- reaches further into the panel than a head title does, and the room the panel gives up is worked out from the plate rather than assumed to match.
--
-- Returns the plate's height, which is what the panel has to make room for on that edge. Zero when there is no title at all,
-- which leaves every measurement below exactly as it was.
--
function TITLE.panel(frame, cfg, p)
  local plate = TITLE.plate(frame, cfg.title, "THIN")

  if (not plate) then
    return 0
  end

  --
  -- How far in from the corner a plate hung on one starts. The rim's corners are drawn at their own size and the panel's
  -- padding lies outside them, so the straight run of the edge begins that far in and the plate stands the usual gap clear of
  -- it again. A corner only exists where both of its sides are drawn, and where there is none the padding is the whole of it.
  --
  local e = frame.edges
  local side = (plate.align == "RIGHT") and "right" or "left"
  local run = p[side]

  if (frame.drawart and e[side] and e[strlower(plate.edge)]) then
    local rim = frame.inset.rim
    local cl, cr = rim:corners()
    local at = (plate.align == "RIGHT") and "RIGHT" or "LEFT"

    run = run + ((at == "RIGHT") and cr or cl) - rim:overhang(at) + KUI.WIDGET_GAP
  end

  plate:SetFrameLevel(frame:GetFrameLevel() + 4)
  TITLE.hang(frame, plate, (plate.edge == "TOP") and p.top or p.bottom, run)
  TITLE.attach(frame, plate)

  return plate:GetHeight()
end

function KUI:CreateInset(cfg, kparent)
  local cfg = cfg or {}
  local frame, parent = newobj(cfg, kparent, 100, 100, cfg.name)

  frame.drawart = (cfg.inset_art == nil) or (cfg.inset_art and true or false)
  frame.edges = inset_edges(cfg.inset_art)

  --
  -- The panel's art is its rim, PanelBorder scaled to INSET_BORDER, over a ground a shade darker than the window around it.
  -- A side that is not wanted is simply not drawn: the rim is sliced, so its corners go with the side and the sides either
  -- side of it run on to the edge instead.
  --
  local rim = KIT.border(frame, "PanelBorder", KUI.INSET_BORDER, { layer = "BORDER" })
  rim:SetSides(frame.edges)

  local ground = frame:CreateTexture(nil, "BACKGROUND")
  ground:SetColorTexture(0, 0, 0, KIT.PANEL_GROUND)

  frame.inset = { rim = rim, ground = ground }

  --
  -- cfg.padding is not cfg.inset. The splits already use that name for the margin they leave on the *outside* of themselves,
  -- and one key cannot mean both.
  --
  local e = frame.edges
  local p = padding_sides(cfg.padding, KUI.INSET_PADDING)
  local ip = padding_sides(cfg.inner_padding, KUI.INSET_INNER_PADDING)

  --
  -- A titled panel gives up the padding on the titled edge, because the plate IS that padding. It is a real object occupying
  -- the edge, not something floating above a margin. Left at the default the two both claim the edge and the panel sits four
  -- pixels in from an untitled one beside it.
  --
  -- Only when the caller said nothing about padding. One that names it gets exactly what it asked for.
  --
  -- Which edge that is has to be known before the plate is built, since the plate is hung on the padding, so the title is asked
  -- where it is going rather than made and measured.
  --
  local tedge = TITLE.edgeof(cfg.title)
  local tside = tedge and strlower(tedge) or nil

  if (tside and cfg.padding == nil) then
    p[tside] = 0
  end

  frame.padding = p
  frame.inner_padding = ip

  local th = TITLE.panel(frame, cfg, p)

  --
  -- What each side gives up in total, which is what the panel's usable area is inset by. Both paddings are the panel's own
  -- and apply whatever it is drawing. A side with no border on it gives up the four pixels of border and nothing else.
  --
  local rings = {}

  for _, k in ipairs(INSET_SIDES) do
    local bw = (frame.drawart and e[k]) and KUI.INSET_BORDER or 0

    rings[k] = p[k] + bw + ip[k]
  end

  --
  -- A title pushes the panel in from under itself. The panel's own edge falls half a plate inside the frame, so that the
  -- border runs through the middle of the plate, and the content clears the whole plate rather than just the border. Along
  -- that edge the plate has taken the border's place, and everything it covers goes with it.
  --
  if (th > 0) then
    rings[tside] = p[tside] + th + ip[tside]
  end

  frame.rings = rings

  --
  -- What the titled edge still owes the title once the panel has stopped being a panel, and which edge that is. A container
  -- gives up nothing on any side, but a plate is a real object hanging off the frame and content laid over it would simply be
  -- on top of the words.
  --
  frame.titleedge = (th > 0) and tedge or nil
  frame.titlering = (th > 0) and (p[tside] + th) or 0

  --
  -- Where the panel's own top and bottom edges go. The titled one moves in to the plate's tips, so that the line it draws runs
  -- through them, less half a border, because the rim is INSET_BORDER of artwork and it is the middle of that which has to come
  -- out level with the tips. The tips lie below the middle of the plate, so a top edge moves in further than a bottom edge
  -- does, and each is measured from its own end of the plate rather than from the other one's.
  --
  local pt, pb = p.top, p.bottom

  if (th > 0) then
    local tip = TITLE.point(frame.title) * th

    if (tedge == "TOP") then
      pt = p.top + tip - KUI.INSET_BORDER / 2
    else
      pb = p.bottom + th - tip - KUI.INSET_BORDER / 2
    end
  end

  frame.arttop = pt
  frame.artbottom = pb

  --
  -- A side with no rim runs its ground on to the edge of the panel's frame, so a panel under a tab strip and the strip read as one surface.
  --
  local xl = e.left and p.left or 0
  local xr = e.right and p.right or 0
  local xt = e.top and pt or 0
  local xb = e.bottom and pb or 0

  local g = rim:groundinset()

  rim:SetFrameBox(frame, xl, xt, xr, xb)
  ground:SetPoint("TOPLEFT", frame, "TOPLEFT", xl + (e.left and g or 0), 0 - xt - (e.top and g or 0))
  ground:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - xr - (e.right and g or 0), xb + (e.bottom and g or 0))

  local content = MakeFrame("Frame", nil, frame)
  frame.content = content

  --
  -- Above the panel, so that anything placed in it draws over the rim rather than under it.
  --
  content:SetFrameLevel(frame:GetFrameLevel() + 3)

  --
  -- A back pointer so that a split created inside this panel can find it and turn its border off. See SetBorderShown.
  --
  content.owninginset = frame

  --
  -- Panels are meant to be siblings, never nested. An inset drawn inside another inset gives a doubled border and a very
  -- busy window, which is what happens the moment one split is placed inside another -- and Konfer nests them two and three
  -- deep. So a panel that turns out to be a container for further panels stops drawing itself and becomes plain space,
  -- leaving only the innermost ones visible.
  --
  frame.SetBorderShown = function(this, onoff)
    local drawn = (onoff and this.drawart) and true or false

    this.inset.rim:SetShown(drawn)
    this.inset.ground:SetShown(drawn)

    --
    -- A container is not a panel at all: it holds panels, which bring their own padding, so it gives up nothing on any side
    -- and the content is the whole of it.
    --
    local rg = this.rings
    local l = onoff and rg.left or 0
    local r = onoff and rg.right or 0
    local t = onoff and rg.top or ((this.titleedge == "TOP") and this.titlering or 0)
    local b2 = onoff and rg.bottom or ((this.titleedge == "BOTTOM") and this.titlering or 0)

    this.content:ClearAllPoints()
    this.content:SetPoint("TOPLEFT", this, "TOPLEFT", l, 0 - t)
    this.content:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 0 - r, b2)
  end

  frame:SetBorderShown(true)

  --
  -- A panel whose contents cannot be used says so on its title: the plaque, its gem and its words dim the way a disabled
  -- control does. It is the caller that decides, and it touches nothing inside the panel, whose controls are enabled and
  -- disabled by their own rules. A panel with no title shows nothing.
  --
  frame.panelenabled = true
  frame.SetEnabled = function(this, onoff)
    onoff = onoff and true or false

    if (this.panelenabled ~= onoff) then
      this.panelenabled = onoff
      if (this.title) then
        TITLE.setenabled(this.title, onoff)
      end
    end
  end
  frame.IsPanelEnabled = function(this)
    return this.panelenabled
  end

  return frame
end

--
-- The y offset that puts something centred in a panel's CONTENT. Anchors with
-- SetPoint("RIGHT", content, "RIGHT", x, KUI:PanelMiddle(content)).
--
-- The two are not the same. A panel's rings are not symmetric. A title makes its own edge much the deeper of the two, since
-- the whole plate comes out of it although half the plate hangs outside the line. Centred in the content, a block of buttons
-- in a titled panel reads several pixels away from the title.
--
-- What this answers is the middle of the box the rim draws, and that is the whole of it. The rule's own weight needs no
-- allowance: it is a band of artwork of the same thickness top and bottom, so it moves both edges inward by the same amount
-- and leaves the middle where it was. Adding half a rule was tried and reads high.
--
function KUI:PanelMiddle(content)
  local ins = content and content.owninginset

  if (not ins) then
    return 0
  end

  local r = ins.rings

  return (r.top - r.bottom - ins.arttop + ins.artbottom) / 2
end

--
-- Called by both splits: if the frame they are being built in is the inside of a panel, that panel is a container rather
-- than a leaf and should not be drawing a border of its own.
--
local function unborder_parent(parent)
  if (parent and parent.owninginset) then
    parent.owninginset:SetBorderShown(false)
  end
end

--
-- Say that a pane is going to hold panels of its own rather than content, so it should not draw itself. The splits do this
-- to their parent already; this is for code laying panels out by hand.
--
function KUI:UseAsContainer(frame)
  unborder_parent(frame)
end

--
-- A split's pane is a panel and is titled like one, with the very same table. That is the whole reason a title is one table
-- rather than a handful of cfg.titleSomething keys: it can be passed along untouched by anything that builds a panel on somebody else's behalf.
--
-- A pane told not to draw gives up the artwork and the inner padding that measured the distance to it, there being nothing
-- left to stand clear of. Its outer padding is position rather than border and is kept, so what is put in the pane sits
-- where it would have, just without a line around it.
--
-- That leaves one ring, which the caller drops by asking for no padding on that pane. Both rings gone is a container: a
-- frame whose content is the whole of it, for a pane that holds panels of its own rather than widgets.
--
local function pane_border(arg, border)
  if (border == nil) then
    border = true
  end

  if (not border) then
    arg.inset_art = false
    arg.inner_padding = 0
  end

  return arg
end


--
-- Split a frame into two panes, one above the other.
--
-- cfg.height is the usable height of the static pane, as it always was, so a caller asking for 48 still gets 48 to put
-- things in: the panel is made taller than that by everything its own edges give up. cfg.topanchor makes the static pane the
-- top one. The end cap and shift options a divider needed are accepted and ignored, because there is no divider any more.
--
-- The two panes meet edge to edge. Each already stands its own padding clear of its outside, so the space between them is
-- those two paddings and there is no gutter to add on top of it.
--
function KUI:CreateHSplit(cfg, kparent)
  local frame, parent = newobj(cfg, kparent, 0, 0, cfg.name)
  local inset = cfg.inset or 0

  unborder_parent(parent)

  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, 0 - inset)
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 - inset, inset)

  --
  -- cfg.inset_art describes the outside of the pair, not either panel, and each pane is given only the sides it actually
  -- owns. The two edges facing each other across the gutter are interior and always draw.
  --
  local ea = inset_edges(cfg.inset_art)

  local ta = { padding = cfg.toppadding or cfg.padding, inner_padding = cfg.inner_padding,
    title = cfg.toptitle, inset_art = { left = ea.left, right = ea.right, top = ea.top } }
  local ba = { padding = cfg.bottompadding or cfg.padding, inner_padding = cfg.inner_padding,
    title = cfg.bottomtitle, inset_art = { left = ea.left, right = ea.right, bottom = ea.bottom } }

  local tp = self:CreateInset(pane_border(ta, cfg.topborder), frame)
  local bp = self:CreateInset(pane_border(ba, cfg.bottomborder), frame)

  --
  -- The static pane is sized so that what is left inside it is the height the caller asked for, which is not the same for
  -- both panes: the one with an edge left open gives up nothing on that side.
  --
  local sp = cfg.topanchor and tp or bp
  local hh = (cfg.height or 24) + sp.rings.top + sp.rings.bottom

  --
  -- The static pane against its edge of the split, and the other pane from it to the far edge, or from the split's own
  -- edge when the static pane is not shown.
  --
  local function place(shown)
    tp:ClearAllPoints()
    bp:ClearAllPoints()

    if (cfg.topanchor) then
      tp:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
      tp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
      bp:SetPoint("TOPLEFT", shown and tp or frame, shown and "BOTTOMLEFT" or "TOPLEFT", 0, 0)
      bp:SetPoint("TOPRIGHT", shown and tp or frame, shown and "BOTTOMRIGHT" or "TOPRIGHT", 0, 0)
      bp:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    else
      bp:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
      bp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
      tp:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
      tp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
      tp:SetPoint("BOTTOM", shown and bp or frame, shown and "TOP" or "BOTTOM", 0, 0)
    end
  end

  sp:SetHeight(hh)
  place(true)

  frame.topinset = tp
  frame.bottominset = bp
  frame.topframe = tp.content
  frame.bottomframe = bp.content

  --
  -- cfg.height after the fact, for a static pane that is as tall as whatever is in it and whose contents change. Without it
  -- a caller has to know that the height belongs to the inset rather than to the split, and has to add the rings back on
  -- itself, which is the widget's own arithmetic in somebody else's file.
  --
  frame.SetSplitSize = function(this, height)
    sp:SetHeight(height + sp.rings.top + sp.rings.bottom)
  end

  --
  -- Show or hide the static pane, the other pane taking the whole split while it is hidden. A pane is never made zero high
  -- to hide it: the game does not lay out what is anchored to a frame of no height, and the other pane is anchored to it.
  --
  frame.SetStaticShown = function(this, onoff)
    onoff = onoff and true or false
    sp:SetShown(onoff)
    place(onoff)
  end

  return frame
end


--
-- Split a frame into two panes, side by side. cfg.width is the usable width of the static pane and cfg.rightanchor makes
-- that the right hand one.
--
function KUI:CreateVSplit(cfg, kparent)
  local frame, parent = newobj(cfg, kparent, 0, 0, cfg.name)
  local inset = cfg.inset or 0

  unborder_parent(parent)

  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, 0 - inset)
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 - inset, inset)

  --
  -- As for the horizontal split: the outer sides are handed to whichever pane owns them, and the two facing the gutter always draw.
  --
  local ea = inset_edges(cfg.inset_art)

  local la = { padding = cfg.leftpadding or cfg.padding, inner_padding = cfg.inner_padding,
    title = cfg.lefttitle, inset_art = { left = ea.left, top = ea.top, bottom = ea.bottom } }
  local ra = { padding = cfg.rightpadding or cfg.padding, inner_padding = cfg.inner_padding,
    title = cfg.righttitle, inset_art = { right = ea.right, top = ea.top, bottom = ea.bottom } }

  local lp = self:CreateInset(pane_border(la, cfg.leftborder), frame)
  local rp = self:CreateInset(pane_border(ra, cfg.rightborder), frame)

  local sp = cfg.rightanchor and rp or lp
  local ww = (cfg.width or 24) + sp.rings.left + sp.rings.right

  lp:ClearAllPoints()
  rp:ClearAllPoints()

  if (cfg.rightanchor) then
    rp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    rp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    rp:SetWidth(ww)
    lp:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    lp:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    lp:SetPoint("RIGHT", rp, "LEFT", 0, 0)
  else
    lp:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    lp:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    lp:SetWidth(ww)
    rp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    rp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    rp:SetPoint("LEFT", lp, "RIGHT", 0, 0)
  end

  frame.leftinset = lp
  frame.rightinset = rp
  frame.leftframe = lp.content
  frame.rightframe = rp.content

  -- cfg.width after the fact. The horizontal split's SetSplitSize says why.
  frame.SetSplitSize = function(this, width)
    sp:SetWidth(width + sp.rings.left + sp.rings.right)
  end

  return frame
end


--
-- Helper function called when we stop resizing a frame.
--
local function resize_OnMouseUp(this)
  local pf = this:GetParent()
  pf:StopMovingOrSizing()
  if (pf.content) then
    local cw = pf.content:GetWidth()
    local ch = pf.content:GetHeight()
    pf:Throw("OnContentSizeChanged", cw, ch)
  end
  if (pf.Throw) then
    pf:Throw("OnStopSizing")
  end
end

local function resize_OnMouseDown(this)
  local pf = this:GetParent()
  pf:StartSizing(this.resize_direction)
  if (pf.Throw) then
    pf:Throw("OnStartSizing")
  end
end

--
-- Helper function to make a frame resizable. Takes as its parameters the parent frame that is to be resizable, the height of
-- the corner frames, and the direction(s) in which the frame is to be resized. This can be a boolean (true means resize both
-- vertically and horizontally, false means don't resize at all), or a string which case have the values "HEIGHT" to resize
-- the height only, "WIDTH" to resize the width only, or "BOTH" to resize both. Returns the southeast, southwest and southern
-- frame pointers or nil for any of them not used.
--
local function make_resizeable(frame, height, opt, swframe, seframe, soframe)
  if (not opt) then
    frame:SetResizable(false)
    return
  end

  local resize

  if (type(opt) == "boolean" or (type(opt) == "string" and opt == "BOTH")) then
    resize = { [1] = "BOTTOMLEFT", [2] = "BOTTOMRIGHT" }
  elseif (type(opt) == "string" and opt == "WIDTH") then
    resize = { [1] = "LEFT", [2] = "RIGHT" }
  elseif (type(opt) == "string" and opt == "HEIGHT") then
    resize = { [1] = "BOTTOM", [2] = "BOTTOM" }
  else
    frame:SetResizable(false)
    return nil, nil, nil
  end

  frame:SetResizable(true)

  --
  -- South-west corner. Size down and to the left.
  --
  local swframe = swframe
  if (not swframe) then
    swframe = MakeFrame("Frame", nil, frame)
  end
  swframe.resize_direction = resize[1]
  swframe:ClearAllPoints()
  swframe:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -5, -5)
  swframe:SetHeight(height)
  swframe:SetWidth(height)
  swframe:EnableMouse(true)
  swframe:SetScript("OnMouseDown", resize_OnMouseDown)
  swframe:SetScript("OnMouseUp", resize_OnMouseUp)

  --
  -- South-east corner. Size down and to the right.
  --
  local seframe = seframe
  if (not seframe) then
    seframe = MakeFrame("Frame", nil, frame)
  end
  seframe.resize_direction = resize[2]
  seframe:ClearAllPoints()
  seframe:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
  seframe:SetHeight(height)
  seframe:SetWidth(height)
  seframe:EnableMouse(true)
  seframe:SetScript("OnMouseDown", resize_OnMouseDown)
  seframe:SetScript("OnMouseUp", resize_OnMouseUp)

  local soframe = soframe
  if (type(opt) == "boolean" or (type(opt) == "string" and (opt == "BOTH" or opt == "HEIGHT"))) then
    --
    -- Southern edge. Size down only.
    --
    if (not soframe) then
      soframe = MakeFrame("Frame", nil, frame)
    end
    soframe.resize_direction = "BOTTOM"
    soframe:ClearAllPoints()
    soframe:SetPoint("TOPLEFT", swframe, "TOPRIGHT", 0, 0)
    soframe:SetPoint("BOTTOMRIGHT", seframe, "BOTTOMLEFT", 0, 0)
    soframe:EnableMouse(true)
    soframe:SetScript("OnMouseDown", resize_OnMouseDown)
    soframe:SetScript("OnMouseUp", resize_OnMouseUp)
  end

  return seframe, swframe, soframe
end

local function xbutton_OnClick(this)
  this:GetParent():Hide()
  this:GetParent():Throw("OnClose")
end

--
-- The kit's close button, the red gem with its gold cross, on FRAME's top right corner. It throws OnClose on FRAME rather than
-- merely hiding it, like every window here.
--
function KIT.closebutton(frame, x, y)
  local xb = MakeFrame("Button", nil, frame)
  local art = KIT.new(xb, "WindowClose", { layer = "ARTWORK", states = KIT.CLOSE_STATES })

  xb:SetSize(KIT.CLOSE_SIZE, KIT.CLOSE_SIZE)
  xb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x or -4, y or -4)
  xb:SetFrameLevel(frame:GetFrameLevel() + 8)
  art:SetBox(xb)
  xb.art = art
  xb:SetScript("OnClick", xbutton_OnClick)
  KIT.interactive(xb, art)
  return xb
end

KIT.CLOSE_SIZE = 24
KIT.STATUS_HEIGHT = 20

--
-- How tall a dropdown's chevron is drawn, and how far its right hand side stands in from the right of the pill, which puts it
-- just inside the rounded end.
--
KIT.DD_CHEVRON = 8
KIT.DD_CHEVRON_RIGHT = 12

--
-- How opaque a menu's ground is. Nearly, so a menu reads as floating over what it opened from.
--
KIT.MENU_GROUND = 0.92

--
-- How big the radio ring on a menu item of a radio group is drawn, in the space a tick takes on any other checkable item.
--
KIT.MENU_RADIO = 12

function KUI:CreateDialogFrame(cfg, kparent)
  local fname = cfg.name or ("KUIDlgFrame" .. self:GetWidgetNum("dialog"))
  local frame,parent,width,height = newobj(cfg, kparent, 300, 300, fname)

  if (parent == UIParent) then
    KIT.addwindow(frame)
  end
  local bstyle = "THICK"
  local offset = 0
  local topheight = 0
  local botheight = 0

  if (cfg.border ~= nil) then
    if (type(cfg.border) == "boolean") then
      bstyle = cfg.border and "THICK" or nil
    elseif (type(cfg.border) == "string") then
      if (cfg.border == "THICK" or cfg.border == "THIN") then
        bstyle = cfg.border
      elseif (cfg.border == "NONE") then
        bstyle = nil
      end
    end
  end

  if (cfg.canmove ~= nil) then
    frame:SetMovable(cfg.canmove)
  else
    frame:SetMovable(true)
  end

  local seframe, swframe, soframe = make_resizeable(frame, 25, cfg.canresize)

  frame:EnableMouse(true)
  frame:EnableKeyboard(true)
  -- With the game's own dialogs, so a mod's window, a strata below, never covers one of them.
  frame:SetFrameStrata(cfg.strata or "DIALOG")

  --
  -- The window's surface, black instead where the caller asked for a plain ground, and its rim over that.
  --
  local bs = bstyle and KIT.BORDERS[bstyle] or nil
  local ground

  if (cfg.blackbg) then
    ground = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    ground:SetColorTexture(0, 0, 0, 1)
  else
    ground = KIT.surface(frame)
  end
  frame.ground = ground

  if (bs) then
    offset = bs.offset
    frame.rim = KIT.border(frame, bs.piece, bs.rim, { layer = "BORDER" })
    frame.rim:SetFrameBox(frame, 0, 0, 0, 0)
  end

  KIT.fitground(ground, frame, frame.rim)

  frame.borderoffset = offset

  --
  -- A dialog made resizable can be made bigger as well as smaller than it starts out, up to what a tabbed dialog allows when it
  -- is not told, 1024 each way, or its starting size if that is more.
  --
  if (frame:IsResizable()) then
    frame:SetResizeBounds(cfg.minwidth or width, cfg.minheight or height, cfg.maxwidth or max(width, 1024),
      cfg.maxheight or max(height, 1024))
  end

  --
  -- The close button sits on the border's top line, centred on it the way the title plate's tips are, so that it is level
  -- with the title and above the content, never over it. Where that line is, is the drawing's to say and not half the rim
  -- the caller asked for, the top side of a frame rarely being drawn the weight of its widest. A dialog with no border has no
  -- line and keeps the button in the corner.
  --
  if (cfg.xbutton) then
    local xy = bs and (KIT.CLOSE_SIZE / 2 - frame.rim:frameline("TOP")) or -4

    frame.xbutton = KIT.closebutton(frame, -4 - (bs and bs.rim or 0), xy)
  end

  frame:Hide()

  --
  -- A dialog's title is the same plate a panel names itself with, straddling its rim the way a panel's straddles its own edge,
  -- and taking THICK when it says nothing, the heavier plate being what a window title sits in. It doubles as the drag handle,
  -- which is the only thing here a panel's title does not do.
  --
  -- The rim is where it is and cannot move to meet the plate, so the plate is hung on the rim, anchored to the artwork and
  -- placed by it. What is left inside the line is room the content stands clear of.
  --
  -- A dialog's own furniture keeps its corners, so a plate hung on one starts clear of that as well. The close button is on
  -- the top line at the right, and the buttons and the status bar stand inside the bottom of the frame, which a foot title
  -- shares with them rather than clearing.
  --
  local dtitle = bs and TITLE.plate(frame, cfg.title, "THICK") or nil

  if (dtitle) then
    local top = dtitle.edge == "TOP"
    local past = nil

    if (frame.xbutton and top and dtitle.align == "RIGHT") then
      past = frame.rim:overhang("RIGHT") + KUI.WIDGET_GAP + bs.rim + KIT.CLOSE_SIZE
    end

    TITLE.attach(frame, dtitle)
    dtitle:SetFrameLevel(frame:GetFrameLevel() + 6)
    dtitle:EnableMouse(true)

    local reach = max(0, ceil(TITLE.hangon(frame.rim, dtitle, past) - offset))

    if (top) then
      topheight = reach
    else
      botheight = reach
    end

    if (frame:IsMovable()) then
      dtitle:SetScript("OnMouseDown", parent_StartMoving)
      dtitle:SetScript("OnMouseUp", parent_StopMoving)
    end
  else
    if (frame:IsMovable()) then
      local mframe = MakeFrame("Frame", nil, frame)
      frame.mframe = mframe
      mframe:EnableMouse(true)
      mframe:ClearAllPoints()
      -- A strip along the top edge, level from end to end.
      mframe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
      mframe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
      mframe:SetHeight(25)
      mframe:SetScript("OnMouseDown", parent_StartMoving)
      mframe:SetScript("OnMouseUp", parent_StopMoving)
    end
  end

  local rightmost = frame
  local rightpoint = "BOTTOMRIGHT"
  local xoffs, yoffs = 0 - offset - KUI.WIDGET_GAP, offset + KUI.WIDGET_GAP
  local addheight = 0

  --
  -- Each button is true for the standard one or a table to change it.
  --
  if (cfg.cancelbutton) then
    local cb = (type(cfg.cancelbutton) == "table") and cfg.cancelbutton or {}
    local cancel = KUI:CreateButton({ width = cb.width or 100, height = cb.height, text = cb.text or K.CANCEL_STR }, frame)
    cancel:Catch("OnClick", function(this)
      this:GetParent():Throw("OnCancel")
    end)
    cancel:ClearAllPoints()
    cancel:SetPoint("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    addheight = max(addheight, cancel:GetHeight() + KUI.WIDGET_GAP)

    --
    -- Kept so that a caller can move the pair. The OK button hangs off the cancel button, so re-anchoring this one moves both.
    --
    frame.cancelbutton = cancel

    rightmost = cancel
    rightpoint = "BOTTOMLEFT"
    xoffs = 0 - KUI.WIDGET_GAP
    yoffs = 0
  end

  if (cfg.okbutton) then
    local ob = (type(cfg.okbutton) == "table") and cfg.okbutton or {}
    local ok = KUI:CreateButton({ width = ob.width or 100, height = ob.height, text = ob.text or K.OK_STR }, frame)
    ok:Catch("OnClick", function(this)
      this:GetParent():Throw("OnAccept")
    end)
    ok:ClearAllPoints()
    ok:SetPoint("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    addheight = max(addheight, ok:GetHeight() + KUI.WIDGET_GAP)

    --
    -- Enter on a dialog that asks for it (cfg.enteraccept) is its OK button. A field with the keyboard has Enter first and
    -- gives the keyboard back to the dialog when it takes it, so the first Enter finishes the field and the next one accepts.
    --
    -- A frame with a key handler is handed every key, so every other one is passed on to the game: Escape closing the dialog
    -- is the game's, and a player must still be able to move with one up. Whether a key goes on can only be changed out of
    -- combat, so in combat it stays as the last key left it, which OnShow puts back to passing on.
    --
    if (cfg.enteraccept) then
      local function propagate(this, onoff)
        if (not InCombatLockdown()) then
          this:SetPropagateKeyboardInput(onoff)
        end
      end

      propagate(frame, true)

      frame:HookScript("OnShow", function(this)
        propagate(this, true)
      end)

      frame:SetScript("OnKeyDown", function(this, key)
        if (key == "ENTER" and ok:IsShown() and ok:IsEnabled()) then
          propagate(this, false)
          this:Throw("OnAccept")
        else
          propagate(this, true)
        end
      end)
    end

    frame.okbutton = ok

    rightmost = ok
    rightpoint = "BOTTOMLEFT"
    xoffs = 0 - KUI.WIDGET_GAP
    yoffs = 0
  end

  --
  -- The pair stands in the bottom right corner unless the caller asks for the middle, in the same word every other widget
  -- here takes for it. OK hangs off the cancel button, so the pair is moved by moving that one, which is the same thing a
  -- caller would otherwise be doing by hand.
  --
  -- Not for a dialog that also has a status bar. The bar stretches from the left wall to whichever button is leftmost, so
  -- centring the pair drags the bar into the middle along with it.
  --
  if (cfg.buttons == "CENTER") then
    local ok, cancel = frame.okbutton, frame.cancelbutton
    local ybtn = offset + KUI.WIDGET_GAP

    if (cancel) then
      --
      -- Where the cancel button's left edge has to land for the pair to be centred, measured from the middle of the frame:
      -- half of everything standing to its left, less half of itself.
      --
      local okw = ok and ok:GetWidth() + KUI.WIDGET_GAP or 0

      cancel:ClearAllPoints()
      cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", (okw - cancel:GetWidth()) / 2, ybtn)
    elseif (ok) then
      ok:ClearAllPoints()
      ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, ybtn)
    end
  end

  if (cfg.statusbar) then
    local statusbg = MakeFrame("Frame", nil, frame)
    frame.statusframe = statusbg
    statusbg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset + KUI.WIDGET_GAP, offset + KUI.WIDGET_GAP)
    if (rightmost == frame) then
      statusbg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - offset - KUI.WIDGET_GAP, offset + KUI.WIDGET_GAP)
    else
      statusbg:SetPoint("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    end
    statusbg:SetHeight(KIT.STATUS_HEIGHT)
    statusbg.art = KIT.new(statusbg, "StatusStrip", { layer = "BORDER" })
    statusbg.art:SetBox(statusbg, 0, 0, 0, 0, KIT.STATUS_HEIGHT)
    addheight = max(addheight, KIT.STATUS_HEIGHT + KUI.WIDGET_GAP)

    local ends = KIT.ends(statusbg.art, KIT.STATUS_HEIGHT) / 2
    local statustext = statusbg:CreateFontString(nil, "OVERLAY",
      cfg.statusfont or "GameFontNormal")
    frame.statustext = statustext
    statustext:SetPoint("TOPLEFT", statusbg, "TOPLEFT", ends, 0)
    statustext:SetPoint("BOTTOMRIGHT", statusbg, "BOTTOMRIGHT", 0 - ends, 0)
    statustext:SetJustifyH("LEFT")
    statustext:SetText("")
    frame.SetStatusText = function(this, text)
      this.statustext:SetText(text or "")
    end
  end

  --
  -- The buttons and status bar stand a gap clear of the border, and the content stands a gap clear of them, so that nothing
  -- a caller puts at the foot of the content ever sits against a button.
  --
  if (addheight > 0) then
    addheight = addheight + KUI.WIDGET_GAP
  end

  --
  -- A title at the foot of the dialog stands in the same band the buttons do, so the content clears the deeper of the two
  -- rather than both. They are beside each other, not stacked.
  --
  addheight = max(addheight, botheight)

  local content = MakeFrame("Frame", nil, frame)
  --
  -- The border offset clears the artwork and nothing more, so content placed at 0,0 sits hard against it. cfg.padding is
  -- kept inside that, for a dialog that would rather its widgets looked placed than jammed into the corner. It is none
  -- unless asked for: every dialog written before this one is laid out in its own coordinates and would move under it.
  --
  local pad = padding_sides(cfg.padding, 0)

  frame.content = content

  --
  -- How far in from each edge of the window its content is, for a caller that sizes the window to fit what it put there.
  --
  frame.rings = {
    left = offset + pad.left, right = offset + pad.right,
    top = offset + topheight + pad.top, bottom = offset + addheight + pad.bottom,
  }
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.rings.left, 0 - frame.rings.top)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - frame.rings.right, frame.rings.bottom)

  if (cfg.escclose) then
    add_escclose(fname)
  end

  frame.OnAccept = function(this)
    this:Hide()
  end

  frame.OnCancel = function(this)
    this:Hide()
  end

  return frame
end

function LBL.SetTextColor(this, r, g, b, a)
  this.rgb = {r = r, g = g, b = b, a = a or 1}
  local d = this.enabled and 1 or 2
  this.label:SetTextColor(r/d, g/d, b/d, a or 1)
end

--
-- A label is not something the pointer does anything to, so its border is not an interactive piece. Its words and its border are dimmed here instead.
--
function LBL.OnEnable(this, event, onoff)
  local onoff = onoff or false
  this.enabled = onoff
  local d = onoff and 1 or 2
  this.label:SetTextColor(this.rgb.r/d, this.rgb.g/d, this.rgb.b/d, this.rgb.a)
  if (this.rim) then
    this.rim:SetEnabled(onoff)
  end
end

function LBL.SetText(this, text)
  if (this.autosize) then
    local sw, sh

    --
    -- An empty label is one line of its font and no width. What the game measures for an empty string is not the height of a
    -- line, and a label built empty to be filled in later still has the widgets under it placed by its height.
    --
    if (not text or text == "") then
      sw, sh = 0, select(2, KUI:MeasureStrWidth("Wy", this.font))
    else
      sw, sh = KUI:MeasureStrWidth(text, this.font)
    end
    this:SetWidth(sw + this.xtrawidth)
    this:SetHeight(sh + this.xtraheight)
    if (this.centerx) then
      local pw = (sw + this.xtrawidth) / -2
      this:SetPoint("LEFT", this:GetParent(), "CENTER", pw, 0)
    end
    if (this.centery) then
      this:SetPoint("TOP", this:GetParent(), "CENTER", 0, (sh + this.xtraheight) / 2)
    end
  end
  this.label:SetText(text)
end

--
-- A separator: the kit's rule across whatever it is put in, a stone set in the diamond at its middle, and words centred under
-- the rule heading what comes after it. It divides one panel's column of widgets into sections where a second panel would be
-- a panel nested inside a panel. Its frame is the rule and the words together, so a column stepping down by GetHeight leaves
-- the usual gap under it. Without cfg.width it runs from cfg.x to the right hand edge of its parent.
--
KUI.SEPARATOR_THICK = 12

function KUI:CreateSeparator(cfg, kparent)
  local font = cfg.font or "GameFontNormal"
  local text = cfg.text or ""
  local _, th = self:MeasureStrWidth("Wy", font)
  local height = KUI.SEPARATOR_THICK + ((text ~= "") and (th + KUI.INTERNAL_GAP) or 0)
  local frame, parent = newobj(cfg, kparent, 100, height, cfg.name)

  if (not cfg.width and cfg.x) then
    frame:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
  end

  local rule = MakeFrame("Frame", nil, frame)
  rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  rule:SetHeight(KUI.SEPARATOR_THICK)

  local art = KIT.new(rule, "Separator", { layer = "ARTWORK" })
  art:SetBox(rule, 0, 0, 0, 0, KUI.SEPARATOR_THICK)
  frame.art = art
  frame.gem = KIT.gem(art)

  local label = frame:CreateFontString(nil, "ARTWORK", font)
  label:SetPoint("TOP", rule, "BOTTOM", 0, 0 - KUI.INTERNAL_GAP)
  label:SetJustifyH("CENTER")
  label:SetText(text)
  frame.label = label

  frame.SetText = function(this, words)
    this.label:SetText(words or "")
  end

  return frame
end

--
-- A group box gathers a few of a panel's widgets under a heading of their own, inside the panel. A panel inside a panel would
-- double the panel rim, so a group box wears the kit's thin border instead, the menu frame at THIN's rim over no ground of
-- its own, and its title is set into its top or its bottom line, which stops short either side of the words rather than
-- running through them. GROUPBOX_NOTCH is the space left between the words and each end of the line.
--
-- A group box takes the same six locations a title plate does, since a heading is a heading wherever this toolkit puts one.
-- The words are on the line rather than on a plaque, so nothing here has to be turned over and the two edges are exact mirrors of each other.
--
-- Its rings are like a panel's with no outer padding, a group box sitting in content that already stands clear of its
-- neighbours. They are the rim and the usual gap inside it on every side, and on the titled edge the deeper of the rim's foot and the words'.
--
KUI.GROUPBOX_NOTCH = 4

function KUI:CreateGroupBox(cfg, kparent)
  local spec = (type(cfg.title) == "table") and cfg.title or { text = cfg.title }
  local font = spec.font or cfg.font or "GameFontNormal"
  local text = spec.text or ""
  local loc = TITLE.location(spec)
  local bs = KIT.BORDERS.THIN
  local _, th = self:MeasureStrWidth("Wy", font)
  local frame, parent = newobj(cfg, kparent, 100, 100, cfg.name)

  th = ceil(th)

  --
  -- The rim's line runs through the middle of the words, and without words it is at the edge of the frame.
  --
  local rimset = (text ~= "") and floor((th - bs.rim) / 2) or 0
  local top = loc.edge == "TOP"

  frame.rim = KIT.border(frame, bs.piece, bs.rim, { layer = "BORDER" })
  frame.rimtop = top and rimset or 0
  frame.rimbottom = top and 0 or rimset
  frame.titleedge = loc.edge
  frame.titlealign = loc.align

  --
  -- Where words hung on a corner start from it, which is clear of the corner and the same gap past it that separates them from
  -- the line at each end. The notch is measured along the rim's own box, which stands proud of the frame by the piece's bleed,
  -- so that much is added back to put the two in the same coordinates.
  --
  local cl, cr = frame.rim:corners()
  local cat = (loc.align == "RIGHT") and "RIGHT" or "LEFT"

  frame.titlebleed = frame.rim:overhang(cat)
  frame.titleindent = ((cat == "RIGHT") and cr or cl) - frame.titlebleed + KUI.GROUPBOX_NOTCH

  local at = loc.edge .. ((loc.align == "CENTER") and "" or loc.align)
  local label = frame:CreateFontString(nil, "ARTWORK", font)
  local lx = 0

  if (loc.align == "LEFT") then
    lx = frame.titleindent
  elseif (loc.align == "RIGHT") then
    lx = 0 - frame.titleindent
  end

  label:SetPoint(at, frame, at, lx, 0)
  label:SetJustifyH("CENTER")
  frame.titletext = label
  frame.titlecolour = { KUI:GetFontColor(font) }

  local inner = bs.rim + KUI.WIDGET_GAP
  local titled = max((text ~= "") and th or 0, rimset + bs.rim) + KUI.WIDGET_GAP

  frame.rings = {
    left = inner, right = inner,
    top = top and titled or inner,
    bottom = top and inner or titled,
  }

  local content = MakeFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.rings.left, 0 - frame.rings.top)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - frame.rings.right, frame.rings.bottom)
  content:SetFrameLevel(frame:GetFrameLevel() + 3)
  frame.content = content

  --
  -- The gap in the line is the words and their margin, put where the words are. In the middle of the line it is measured from
  -- the middle, and on a corner from that corner, so it stays where it belongs when the box is resized.
  --
  frame.SetTitleText = function(this, words)
    words = words or ""
    this.titletext:SetText(words)

    if (words == "") then
      this.rim:SetNotch(this.titleedge, nil)
    else
      local w = this.titletext:GetStringWidth() + 2 * KUI.GROUPBOX_NOTCH
      local corner = this.titleindent - KUI.GROUPBOX_NOTCH + this.titlebleed

      if (this.titlealign == "CENTER") then
        this.rim:SetNotch(this.titleedge, 0 - w / 2, w / 2)
      elseif (this.titlealign == "RIGHT") then
        this.rim:SetNotch(this.titleedge .. "RIGHT", 0 - corner - w, 0 - corner)
      else
        this.rim:SetNotch(this.titleedge .. "LEFT", corner, corner + w)
      end
    end

    this.rim:SetFrameBox(this, 0, this.rimtop, 0, this.rimbottom)
  end

  --
  -- Like a panel, a group box whose contents cannot be used dims its title and touches nothing else.
  --
  frame.SetEnabled = function(this, onoff)
    local c = this.titlecolour

    if (onoff) then
      this.titletext:SetTextColor(c[1], c[2], c[3], c[4])
    else
      this.titletext:SetTextColor(0.5, 0.5, 0.5, c[4])
    end
  end

  frame:SetTitleText(text)

  return frame
end

--
-- A bordered label wears the thin border, and is bigger than the words in it by that border's offset and by nothing else. Asked
-- of the border rather than written down, so that the frame, the padding and the autosize allowance cannot drift apart from each
-- other or from the artwork.
--
function LBL.inset(cfg)
  return cfg.border and KIT.BORDERS.THIN.offset or 0
end

function KUI:CreateStringLabel(cfg, kparent)
  local bi = LBL.inset(cfg)
  local dw = 200 + (bi * 2)
  local dh = 16 + (bi * 2)
  local frame,parent,width,height = newobj(cfg, kparent, dw, dh, cfg.name)
  frame.font = cfg.font or "GameFontHighlightSmall"
  local label = frame:CreateFontString(nil, "ARTWORK", frame.font)
  frame.autosize = true
  if (cfg.autosize ~= nil) then
    frame.autosize = cfg.autosize
  end

  label:SetJustifyH(cfg.justifyh or "LEFT")
  label:SetJustifyV(cfg.justifyv or "MIDDLE")
  frame.label = label
  local r,g,b,a = KUI:GetFontColor(frame.font)
  frame.rgb = {r = r, g = g, b = b, a = a}
  if (cfg.color) then
    frame.rgb = { r = cfg.color.r, g = cfg.color.g, b = cfg.color.b, a = cfg.color.a or 1 }
  end

  --
  -- The border wears the window's tint unless the caller named a colour of its own for it.
  --
  if (cfg.border) then
    local bc = cfg.bordercolor
    local bs = KIT.BORDERS.THIN

    frame.rim = KIT.border(frame, bs.piece, bs.rim, { layer = "BORDER",
      accent = bc and { r = bc.r or 1, g = bc.g or 1, b = bc.b or 1 } or nil })
    frame.rim:SetFrameBox(frame, 0, 0, 0, 0)
  end

  --
  -- How much wider and taller the frame is than the words, which is what LBL.SetText grows it by when it is asked to fit itself to new text.
  --
  frame.xtrawidth = bi * 2
  frame.xtraheight = bi * 2

  label:SetPoint("TOPLEFT", frame, "TOPLEFT", bi, 0 - bi)
  label:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - bi, bi)

  frame.SetText = LBL.SetText
  frame.SetTextColor = LBL.SetTextColor
  frame.OnEnable = LBL.OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  --
  -- A label is a plain frame that takes no mouse, so one with a tooltip is told when the pointer moves over it. Only that:
  -- a click still goes through to whatever is under it.
  --
  if (cfg.tooltip) then
    frame:SetMouseMotionEnabled(true)
  end

  frame:SetText(cfg.text or "")
  frame:SetEnabled(cfg_enabled(cfg))

  --
  -- A label whose text holds links made by K.Link catches clicks on them when it is given somewhere to send them. The
  -- handler is taken now rather than read from CFG at click time, callers being in the habit of reusing one table for
  -- the next widget they make. A client whose frames cannot carry links gets none, and K.Link has drawn none there.
  --
  local onlink = cfg.onlink

  if (onlink and frame.SetHyperlinksEnabled) then
    frame:SetHyperlinksEnabled(true)
    frame:EnableMouse(true)
    frame:SetScript("OnHyperlinkClick", function(this, link, text, button)
      local _, _, kind, data = strfind(link, "^([^:]+):(.*)$")

      if (kind) then
        onlink(this, kind, data, text, button)
      end
    end)
  end

  return frame
end

function EB.OnEnterPressed(this)
  local val = this:GetText()
  local err = this:Throw("OnEnterPressed", val)
  if (err) then
    this:SetFocus()
  else
    this:ClearFocus()
    this:Throw("OnValueChanged", val, true)
    this.setvalue = val
  end
end

function EB.SetText(this, text)
  this.setvalue = text
  this:Throw("OnValueChanged", text, false)
end

function EB.OnTextChanged(this, user)
  if (user) then
    local newv = this:GetText()
    this:Throw("OnValueChanged", newv, true)
  end
end

function EB.OnEscapePressed(this)
  this:ClearFocus()
  this:SetText(this.setvalue or "")
  this:Throw("OnEscapePressed", this:GetText())
end

function EB.OnEnable(this, event, onoff)
  local onoff = onoff or false
  local d = onoff and 1 or 2
  local tc = this.kuichanged and KUI.DEFAULT_CHANGED_COLOR or this.trgb
  this:EnableMouse(onoff)
  this:SetTextColor(tc.r/d, tc.g/d, tc.b/d, tc.a or 1)
  if (this.label) then
    this.label:SetTextColor(this.lrgb.r/d, this.lrgb.g/d, this.lrgb.b/d, this.lrgb.a)
  end
  this.enabled = onoff
  return false
end

--
-- An edit box lights up while it has the keyboard, the text field's focused state being its hover state, and selects all of
-- its text when it takes the keyboard so that typing replaces it.
--
-- KIT.focused is whichever of the kit's fields has the keyboard, so that something which ends an edit, a save bar's button,
-- can take the keyboard back without asking the game which frame has it.
--
function KIT.fieldfocus(this)
  this.kuifocus = true
  KIT.focused = this
  this:HighlightText()
  KIT.sync(this)
end

function KIT.fieldblur(this)
  this.kuifocus = nil

  if (KIT.focused == this) then
    KIT.focused = nil
  end

  this:HighlightText(0, 0)
  KIT.sync(this)
end

--
-- TAB ORDER
--
-- Tab moves the keyboard to the next of the kit's fields in the same window, and Shift-Tab to the one before, wrapping round
-- at either end and passing over any that is hidden or disabled. A field's place is cfg.taborder, and without one it is the
-- place of the field made before it in that window plus one, so that the order a window's fields were made in is its tab
-- order unless it says otherwise. Fields sharing a place go in the order they were made.
--
-- A field's window is the outermost of its ancestors that is a window (KIT.iswindow, see KIT.addwindow), or its outermost
-- ancestor short of UIParent where none is, and each window keeps its own list, KUITABS, and the last place given, KUITABLAST.
--
KIT.iswindow = {}

local function tab_window(frame)
  local win = nil
  local f = frame

  while (f) do
    if (KIT.iswindow[f]) then
      win = f
    end

    local p = f:GetParent()

    if (not p or p == UIParent) then
      break
    end

    f = p
  end

  return win or f
end

function KIT.addtab(field, order)
  local win = tab_window(field)

  win.kuitabs = win.kuitabs or {}
  order = order or ((win.kuitablast or 0) + 1)
  win.kuitablast = order

  field.taborder = order
  field.tabwindow = win
  field.tabseq = #win.kuitabs + 1
  tinsert(win.kuitabs, field)
end

function KIT.tabpressed(this)
  local list = {}

  for _, f in ipairs(this.tabwindow and this.tabwindow.kuitabs or {}) do
    if (f == this or (f:IsVisible() and (not f.IsEnabled or f:IsEnabled()))) then
      tinsert(list, f)
    end
  end

  if (#list < 2) then
    return
  end

  tsort(list, function(a, b)
    if (a.taborder ~= b.taborder) then
      return a.taborder < b.taborder
    end

    return a.tabseq < b.tabseq
  end)

  for i, f in ipairs(list) do
    if (f == this) then
      local step = IsShiftKeyDown() and -1 or 1
      local nxt = list[(i - 1 + step) % #list + 1]

      nxt:SetFocus()
      return
    end
  end
end

function KUI:CreateEditBox(cfg, kparent)
  local frname = cfg.name
  if (not cfg.name) then
    frname = "KUIEditBox" .. self:GetWidgetNum("edit")
  end
  --
  -- Twenty, the height the text field is drawn at. A taller frame makes a taller field, so the frame is always the size of
  -- the box it draws and a caller stacking a column of widgets by GetHeight leaves the same gap under this as under anything.
  --
  local frame,ppf,width,height = newobj(cfg, kparent, 200, 20, frname, "EditBox")

  frame.art = KIT.new(frame, "TextField", { layer = "BACKGROUND" })
  frame.art:SetBox(frame, 0, 0, 0, 0, height)
  KIT.interactive(frame, frame.art)

  local inset = ceil(KIT.ends(frame.art, height) / 2)

  --
  -- A box asked for in characters is that many characters of text plus the chrome round them, which is the field's own and
  -- is not a number a caller can know. What may be typed into it is cfg.len and has nothing to do with how much of it shows.
  --
  if (cfg.charwidth) then
    frame:SetWidth(KUI:CharsWidth(cfg.charwidth, cfg.font or "ChatFontNormal") + inset * 2)
  end

  frame:SetTextInsets(inset, inset, 3, 3)
  frame:SetMaxLetters(cfg.len or 128)
  frame:SetCursorPosition(0)
  frame:SetAutoFocus(false)
  frame:SetFontObject(cfg.font or "ChatFontNormal")
  frame:EnableMouse(true)
  frame:EnableKeyboard(true)
  if (cfg.numeric) then
    frame:SetNumeric(true)
  end
  frame:HookScript("OnEnterPressed", EB.OnEnterPressed)
  frame:HookScript("OnEscapePressed", EB.OnEscapePressed)
  frame:HookScript("OnTextChanged", EB.OnTextChanged)
  frame:HookScript("OnEditFocusGained", KIT.fieldfocus)
  frame:HookScript("OnEditFocusLost", KIT.fieldblur)
  frame:HookScript("OnTabPressed", KIT.tabpressed)
  hooksecurefunc(frame, "SetText", EB.SetText)
  KIT.addtab(frame, cfg.taborder)

  if (cfg.label) then
    local lfont = cfg.label.font or "GameFontNormal"
    local lw,lh = KUI:MeasureStrWidth(cfg.label.text or "", lfont)
    local label = frame:CreateFontString(nil, "ARTWORK", lfont)
    frame.label = label
    local r,g,b,a = KUI:GetFontColor(lfont)
    if (cfg.label.color) then
      r = cfg.label.color.r or r
      g = cfg.label.color.g or g
      b = cfg.label.color.b or b
      a = cfg.label.color.a or 1
    end
    lh = cfg.label.height or lh
    lw = cfg.label.width or lw
    frame.lrgb = {r = r, g = g, b = b, a = a}
    if (lh < height) then
      lh = height
    end
    label:SetHeight(lh)
    label:SetWidth(lw)
    label:SetJustifyH(cfg.label.justifyh or "LEFT")
    label:SetJustifyV(cfg.label.justifyv or "MIDDLE")
    label:SetText(cfg.label.text or "")
    check_tooltip_title(frame, cfg, cfg.label.text)

    if (cfg.label.pos == "TOP") then
      label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
      if (cfg.y) then
        if (cfg.y ~= "MIDDLE") then
          frame:SetPoint("TOP", ppf, "TOP", 0, cfg.y - lh)
        else
          frame:SetPoint("TOP", ppf, "CENTER", 0, (height - lh) / 2)
        end
      end
    elseif (cfg.label.pos == "RIGHT") then
      label:SetPoint("TOPLEFT", frame, "TOPRIGHT", KUI.INTERNAL_GAP, 0)
      if (cfg.x and cfg.x == "CENTER") then
        frame:SetPoint("LEFT", ppf, "CENTER", (width + KUI.INTERNAL_GAP + lw) / -2, 0)
      end
    elseif (cfg.label.pos == "BOTTOM") then
      label:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
      if (cfg.y and cfg.y == "MIDDLE") then
        frame:SetPoint("TOP", ppf, "CENTER", 0, (height + lh) / 2)
      end
    else -- Assume LEFT
      --
      -- The field is its frame, so the words stand INTERNAL_GAP off the frame and the frame starts that far past them, the
      -- same as a dropdown's, and an edit box lines up with a dropdown under it given the same label width.
      --
      label:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0 - KUI.INTERNAL_GAP, 0)
      if (cfg.x) then
        if (cfg.x ~= "CENTER") then
          frame:SetPoint("LEFT", ppf, "LEFT", cfg.x + lw + KUI.INTERNAL_GAP, 0)
        else
          frame:SetPoint("LEFT", ppf, "CENTER", (width - lw - KUI.INTERNAL_GAP) / -2, 0)
        end
      end
    end
    if (cfg.label.pos == "TOP") then
      drawn_extent(frame, lh, 0)
    elseif (cfg.label.pos == "BOTTOM") then
      drawn_extent(frame, 0, lh)
    end

    if (cfg.label.debug) then
      local ttt = frame:CreateTexture(nil, "ARTWORK")
      ttt:SetAllPoints(label)
      ttt:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    end
  end

  local r,g,b,a = KUI:GetFontColor(cfg.font or "ChatFontNormal")
  if (cfg.color) then
    r = cfg.color.r or r
    g = cfg.color.g or g
    b = cfg.color.b or b
    a = cfg.color.a or 1
  end
  frame.trgb = {r = r, g = g, b = b, a = a}

  frame.OnEnable = EB.OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetEnabled(cfg_enabled(cfg))
  frame:SetCursorPosition(0)
  frame:ClearFocus()
  frame:SetText(cfg.initialvalue or "")
  return frame
end

--
-- Somewhere to write more than a line. An edit box is a line, drawn as the kit's text field, which is a strip scaling as one
-- piece and so can only ever be the height its artwork is. This is any size the caller anchors it to, so it wears the panel
-- rim over a panel's ground instead, sliced and therefore right at every size, and that well is the sunken border round it.
--
-- The words do not push the box open as they fill it. They scroll, which is why this is a widget of its own rather than a
-- flag on an edit box: a box that scrolls is a scroll frame with the box inside it, that box grows to its text and the frame
-- shows a window on it. So what the caller anchors is the well, and everything an edit box answers to the well answers by
-- passing on to the box inside it.
--
-- Nothing WoW gives us keeps the caret in sight: the scroll frame knows where its child is and the box knows where the caret
-- is in the words, and neither tells the other. OnCursorChanged hands us where the caret is from the top of the text, so we
-- scroll to it when it has gone off either end.
--
-- cfg.len is 0 by default, which is as much as anybody cares to type. Otherwise this is an edit box: cfg.font, cfg.color,
-- cfg.initialvalue and cfg.tooltip all mean what they do there, and it throws OnValueChanged and OnEscapePressed. It has no
-- label, having no line to put one beside, and there is no Enter to commit on: Enter is a new line, what is typed is the
-- value from the keystroke it was typed at, and Escape leaves the box rather than undoing it.
--
function KUI:CreateTextArea(cfg, kparent)
  local frname = cfg.name or ("KUITextArea" .. self:GetWidgetNum("edit"))

  --
  -- The words stand off the rim the same distance a panel's contents stand off theirs. cfg.lines makes it as tall as that many
  -- lines of its font and the margin above and below them.
  --
  local pad = KUI.INSET_BORDER + KUI.INSET_INNER_PADDING
  local tall = 60

  if (cfg.lines) then
    tall = cfg.lines * select(2, self:MeasureStrWidth("Wy", cfg.font or "ChatFontNormal")) + pad * 2
  end

  local frame, ppf, width, height = newobj(cfg, kparent, 200, tall, frname)

  local well = KIT.border(frame, "PanelBorder", KUI.INSET_BORDER, { layer = "BORDER" })
  local ground = frame:CreateTexture(nil, "BACKGROUND")

  ground:SetColorTexture(0, 0, 0, KIT.PANEL_GROUND)
  well:SetFrameBox(frame, 0, 0, 0, 0)
  KIT.fitground(ground, frame, well, 0, 0, 0, 0)

  frame.well = well
  frame.ground = ground

  local scroll = MakeFrame("ScrollFrame", frname .. "Scroll", frame)
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, 0 - pad)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - pad, pad)

  local eb = MakeFrame("EditBox", frname .. "Edit", scroll)

  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(cfg.font or "ChatFontNormal")
  eb:SetMaxLetters(cfg.len or 0)
  eb:SetJustifyH("LEFT")
  eb:SetTextInsets(0, 0, 0, 0)
  eb:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  eb:SetWidth(scroll:GetWidth())
  eb:SetHeight(scroll:GetHeight())
  eb:EnableMouse(true)
  eb:EnableKeyboard(true)
  scroll:SetScrollChild(eb)

  frame.scroll = scroll
  frame.editbox = eb

  --
  -- The child is as wide as the window on it, always, or the words wrap somewhere other than where they are cut off.
  --
  scroll:SetScript("OnSizeChanged", function(this, w, h)
    eb:SetWidth(w)
  end)

  --
  -- Y is how far the caret is below the top of the text, as a negative number, and H is how tall the line it is on is.
  --
  eb:SetScript("OnCursorChanged", function(this, cx, cy, cw, ch)
    local view = scroll:GetHeight()
    local top = scroll:GetVerticalScroll()
    local at = 0 - (cy or 0)

    if (at < top) then
      scroll:SetVerticalScroll(at)
    elseif ((at + (ch or 0)) > (top + view)) then
      scroll:SetVerticalScroll(at + (ch or 0) - view)
    end
  end)

  --
  -- Text taken away can leave the window looking at nothing below the last line.
  --
  eb:SetScript("OnTextChanged", function(this, user)
    local range = scroll:GetVerticalScrollRange()

    if (scroll:GetVerticalScroll() > range) then
      scroll:SetVerticalScroll(range)
    end

    if (user) then
      frame:Throw("OnValueChanged", this:GetText(), true)
    end
  end)

  eb:SetScript("OnEscapePressed", function(this)
    this:ClearFocus()
    frame:Throw("OnEscapePressed", this:GetText())
  end)

  --
  -- The box is only as tall as what is written in it, so a click in the empty part of the well lands on the scroll frame and
  -- has to be handed on, and the wheel scrolls wherever it is over.
  --
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseDown", function(this)
    if (frame.enabled) then
      eb:SetFocus()
    end
  end)

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(this, delta)
    local step = KUI.TEXTAREA_WHEEL_STEP * (0 - delta)

    this:SetVerticalScroll(max(0, min(this:GetVerticalScroll() + step, this:GetVerticalScrollRange())))
  end)

  local r, g, b, a = KUI:GetFontColor(cfg.font or "ChatFontNormal")

  if (cfg.color) then
    r = cfg.color.r or r
    g = cfg.color.g or g
    b = cfg.color.b or b
    a = cfg.color.a or 1
  end

  frame.trgb = { r = r, g = g, b = b, a = a }

  frame.SetText = function(this, text)
    eb:SetText(text or "")
    scroll:SetVerticalScroll(0)
    this:Throw("OnValueChanged", eb:GetText(), false)
  end

  frame.GetText = function(this)
    return eb:GetText()
  end

  frame.SetFocus = function(this)
    eb:SetFocus()
  end

  frame.ClearFocus = function(this)
    eb:ClearFocus()
  end

  frame.OnEnable = function(this, event, onoff)
    local onoff = onoff or false
    local d = onoff and 1 or 2

    eb:EnableMouse(onoff)
    eb:EnableKeyboard(onoff)
    eb:SetTextColor(this.trgb.r/d, this.trgb.g/d, this.trgb.b/d, this.trgb.a)

    if (not onoff) then
      eb:ClearFocus()
    end

    this.enabled = onoff
    return false
  end

  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  if (cfg.tooltip) then
    scroll:SetScript("OnEnter", function(this) tip_OnEnter(frame) end)
    scroll:SetScript("OnLeave", function(this) tip_OnLeave(frame) end)
  end

  frame:SetEnabled(cfg_enabled(cfg))
  frame:SetText(cfg.initialvalue or "")
  return frame
end

--
-- A checkbox or radio button is clicked the way a button is: pressed with the left mouse button and released over it. Any
-- other button does nothing, and neither does sliding off before letting go.
--
function CB.OnMouseDown(this, button)
  if (this.enabled and button == "LeftButton") then
    this.kuipressed = true
    if (this.text) then
      local t = this.text
      t:SetPoint("LEFT", t.ipoints[1], t.ipoints[2], t.ipoints[3] + 1, t.ipoints[4] - 1)
    end
  end
end

function CB.OnMouseUp(this, button)
  local pressed = this.kuipressed

  this.kuipressed = nil

  if (not pressed) then
    return
  end

  if (this.text) then
    local t = this.text
    t:SetPoint("LEFT", t.ipoints[1], t.ipoints[2], t.ipoints[3], t.ipoints[4])
  end

  if (this.enabled and button == "LeftButton" and this:IsMouseOver()) then
    if (this.ToggleChecked) then
      this:ToggleChecked()
    else
      this:SetChecked()
    end
    this:Throw("OnClick", this.checked)
    this:Throw("OnValueChanged", this.checked, true, this.groupname and this.value or nil)
  end
end

function CB.SetText(this, text)
  if (this.text) then
    this.text:SetText(text or "")
    if (this.autosize) then
      local w = this.text:GetStringWidth() + this.boxsize + KUI.INTERNAL_GAP + KUI.CHECKBOX_LABEL_PAD
      --
      -- A ceiling rather than a size: the frame is as wide as its words need until they need more than this, and from there
      -- it stops growing and the words are cut off at the edge. That is what a translated label wants -- snug in the
      -- language that fits and never wide enough to push what stands beside it off the panel in the one that does not.
      --
      if (this.maxwidth and w > this.maxwidth) then
        w = this.maxwidth
      end
      this:SetWidth(w)
    end
    if (this.centerx) then
      local pw = floor(this:GetWidth() / -2)
      this:SetPoint("LEFT", this:GetParent(), "CENTER", pw, 0)
    end
  end
end

function CB.GetChecked(this)
  return this.checked
end

function CB.ToggleChecked(this)
  this:SetChecked(not this.checked, true)
end

function CB.OnEnable(this, event, onoff)
  local onoff = onoff or false
  this.enabled = onoff
  local d = onoff and 1 or 2
  local tc = this.kuichanged and KUI.DEFAULT_CHANGED_COLOR or this.rgb
  if (this.text) then
    this.text:SetTextColor(tc.r/d, tc.g/d, tc.b/d, tc.a or 1)
  end
end

--
-- What a checked checkbox or radio button shows, which is more than one piece: a fill and a mark, or an orb. Radio groups show
-- and hide it by the one name, so it answers to the same calls a texture does.
--
function KIT.mark(...)
  local m = { ... }

  m.SetShown = function(this, onoff)
    for _, p in ipairs(this) do
      p:SetShown(onoff)
    end
  end
  m.Show = function(this) this:SetShown(true) end
  m.Hide = function(this) this:SetShown(false) end
  m.IsShown = function(this) return this[1] and this[1]:IsShown() end

  return m
end

local function kui_checkradio(cfg, kparent, size, dh)
  local dw = size
  if (cfg.label) then
    dw = 200
  end
  local frame, parent, width, height = newobj(cfg, kparent, dw, dh, cfg.name, "Button")

  --
  -- The box is the frame's height, and its art is drawn the size of the box, the kit's pieces being cut tight to what they
  -- draw. A caller asking for a bigger checkbox gets a bigger checkbox, not the same one loose in a taller frame.
  --
  -- The box is square, so an unlabelled checkbox that was not given a width takes its height for one; a labelled one is as
  -- wide as its words need.
  --
  local boxsize = height

  if (not cfg.label and not cfg.width) then
    frame:SetWidth(boxsize)
  end

  frame.boxsize = boxsize
  frame.checked = cfg.checked or false
  frame.autosize = cfg.autosize
  frame.maxwidth = cfg.maxwidth
  frame:HookScript("OnMouseDown", CB.OnMouseDown)
  frame:HookScript("OnMouseUp", CB.OnMouseUp)
  frame:EnableMouse(true)

  --
  -- An empty region the size of the box, for the art and the label to hang from.
  --
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(boxsize, boxsize)
  bg:SetPoint("LEFT", frame, "LEFT", 0, 0)
  frame.box = bg

  local over = 0

  if (cfg.label) then
    assert(cfg.label.pos == nil or cfg.label.pos == "LEFT" or cfg.label.pos == "RIGHT", "checkbox label position can only be LEFT or RIGHT (default)")
    local font = cfg.label.font or "GameFontHighlight"
    local text = frame:CreateFontString(nil, "OVERLAY", font)
    frame.rgb = KUI:GetFontColor(font, true)
    if (cfg.label.color) then
      frame.rgb.r = cfg.label.color.r
      frame.rgb.g = cfg.label.color.g
      frame.rgb.b = cfg.label.color.b
      frame.rgb.a = cfg.label.color.a
    end
    frame.text = text
    local dh = "LEFT"
    text:ClearAllPoints()
    --
    -- The words stand the internal gap off the box. ipoints carries the x that anchor was made with, so that the
    -- press-and-release nudge below can put it back.
    --
    local lift = KUI.CHECKBOX_LABEL_LIFT

    if (cfg.label.pos == "LEFT") then
      bg:ClearAllPoints()
      bg:SetPoint("RIGHT", frame, "RIGHT", over, 0)
      text:SetPoint("RIGHT", bg, "LEFT", over - KUI.INTERNAL_GAP, lift)
      text:SetPoint("LEFT", frame, "LEFT", 0, lift)
      text.ipoints = { frame, "LEFT", 0, lift }
      dh = "RIGHT"
      if (cfg.autosize == nil) then
        frame.autosize = false
      end
    else
      text:SetPoint("LEFT", bg, "RIGHT", KUI.INTERNAL_GAP - over, lift)
      text:SetPoint("RIGHT", frame, "RIGHT", 0, lift)
      text.ipoints = { bg, "RIGHT", KUI.INTERNAL_GAP - over, lift }
      if (cfg.autosize == nil) then
        frame.autosize = true
      end
    end
    text:SetJustifyH(cfg.label.justifyh or dh)
    text:SetJustifyV(cfg.label.justifyv or "MIDDLE")

    --
    -- A caller that fixed this frame's width, or put a ceiling on it, has said the words live inside that, so they are cut
    -- off at its edge rather than wrapped. Wrapping is much the worse of the two failures: the frame goes on reporting the
    -- height it was given while the words grow downwards out of it and through whatever is drawn underneath. A frame free to
    -- size itself grows to fit its words and has nothing to overflow, so it keeps the default.
    --
    if (not frame.autosize or frame.maxwidth) then
      text:SetWordWrap(false)
    end
  end

  frame.SetText = CB.SetText
  frame.GetChecked = CB.GetChecked
  frame.OnEnable = CB.OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  if (cfg.label) then
    frame:SetText(cfg.label.text or "")
    check_tooltip_title(frame, cfg, cfg.label.text)
  end
  return frame, bg
end

function CB.SetChecked(self, onoff, nothrow)
  local onoff = onoff or false
  local c = self.check
  local old = self.checked

  self.checked = onoff
  if (onoff) then
    c:Show()
  else
    c:Hide()
  end

  if (not nothrow) then
    self:Throw("OnValueChanged", onoff, false)
  end
end

--
-- A checkbox is the box, its rim in the window's tint and its centre left dark, and a mark in the centre when it is checked.
-- The mark is a tick unless the caller asks for cfg.mark = "CROSS", for a box where ticking it takes something away. It is
-- the mark's own green or red unless cfg.markcolour = false on the checkbox or a frame above it asks for the window's colour.
--
function KUI:CreateCheckBox(cfg, kparent)
  local frame, bg = kui_checkradio(cfg, kparent, KUI.CHECKBOX_SIZE, KUI.CHECKBOX_SIZE)
  local size = frame.boxsize

  local box = KIT.new(frame, "CheckBox", { layer = "ARTWORK", sublevel = 0 })
  box.box:SetAllPoints(bg)
  box:Layout()

  --
  -- The mark is drawn at the height of the box and as wide as its own shape makes it, so a tick's tail may reach past the box
  -- the way a hand-drawn tick does.
  --
  local mark = KIT.new(frame, (cfg.mark == "CROSS") and "CheckBoxCross" or "CheckBoxTick",
    { layer = "OVERLAY", accented = KIT.markaccented(frame), part = "mark" })
  local mw, mh = mark:natural()
  mark.box:SetPoint("CENTER", bg, "CENTER", 0, 0)
  mark.box:SetSize(size * mw / mh, size)
  mark:Layout()

  frame.check = KIT.mark(mark)
  KIT.interactive(frame, box, mark)

  frame.SetChecked = CB.SetChecked
  frame.ToggleChecked = CB.ToggleChecked
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetChecked(cfg.checked)
  frame:SetEnabled(cfg_enabled(cfg))
  return frame
end

function RADIO.uncheck_group(t, g, ...)
  local l = 1
  local c = select(l, ...)
  while (c) do
    local rc = c
    if (t.getbutton) then
      rc = t.getbutton(c)
    end
    if (rc ~= t and rc.groupname ~= nil and rc.groupname == g) then
      if (rc.checked) then
        rc.checked = false
        rc.check:Hide()
        rc:Throw("OnValueChanged", false, false, rc.value)
      end
    end
    l = l + 1
    c = select(l, ...)
  end
end

function RADIO.SetChecked(this)
  if (this.checked) then
    return
  end

  --
  -- Find and set to the OFF state any other buttons in the group
  --
  RADIO.uncheck_group(this, this.groupname, this.groupparent:GetChildren())
  this.checked = true
  this.check:Show()
  this:Throw("OnValueChanged", true, false, this.value)
end

function RADIO.OnValueChanged(this, evt, onoff, user, val)
  if (this.cvfunc) then
    local onoff = onoff or false
    this.cvfunc(this, evt, onoff, user, val)
  end
end

function RADIO.getsetvalue(t, g, v, n, set, ...)
  local l = 1
  local c = select(l, ...)
  while (c) do
    local rc = c
    if (t.getbutton) then
      rc = t.getbutton(c)
    end
    if (rc.groupname ~= nil and rc.groupname == g) then
      if ((not set) and rc.checked) then
        return rc.value
      elseif (set) then
        if (rc.value ~= v) then
          if (rc.checked) then
            rc.checked = false
            rc.check:Hide()
            if (not n) then
              rc:Throw("OnValueChanged", false, false, rc.value)
            end
          end
        else
          RADIO.uncheck_group(t, g, ...)
          rc.checked = true
          rc.check:Show()
          if (not n) then
            rc:Throw("OnValueChanged", true, false, rc.value)
          end
        end
      end
    end
    l = l + 1
    c = select(l, ...)
  end
end

function RADIO.SetValue(this, val, nothrow)
  if (this.checked and this.value and this.value == val) then
    return
  end
  RADIO.getsetvalue(this, this.groupname, val, nothrow, true, this.groupparent:GetChildren())
end

function RADIO.GetValue(this)
  if (this.checked) then
    return this.value
  end
  return RADIO.getsetvalue(this, this.groupname, nil, nil, false, this.groupparent:GetChildren())
end

--
-- For radio boxes, we must have a group name. When one button in the group is checked, all others become unchecked. All
-- radio boxes in the same group must have the same parent frame.
--
function KUI:CreateRadioButton(cfg, kparent)
  assert(cfg.group, "must supply radio button group name")
  local frame, bg = kui_checkradio(cfg, kparent, KUI.CHECKBOX_SIZE, KUI.CHECKBOX_SIZE)

  frame.groupname = cfg.group
  frame.groupparent = cfg.groupparent or frame:GetParent()
  frame.value = cfg.value
  frame.cvfunc = cfg.func
  frame.getbutton = cfg.getbutton

  --
  -- The ring, and the orb that lights it when this is the button chosen, in the window's accent and in proportion to the ring
  -- as the two were drawn.
  --
  local ring = KIT.new(frame, "RadioButton", { layer = "ARTWORK", sublevel = 0 })
  ring.box:SetAllPoints(bg)
  ring:Layout()

  local orb = KIT.new(frame, "RadioButtonOrb", { layer = "ARTWORK", sublevel = 2, flat = true, part = "mark" })
  local os = frame.boxsize * orb.def.draw / ring.def.draw
  orb.box:SetPoint("CENTER", bg, "CENTER", 0, 0)
  orb.box:SetSize(os, os)
  orb:Layout()
  orb:Hide()

  frame.check = KIT.mark(orb)
  KIT.interactive(frame, ring, orb)

  frame.SetChecked = RADIO.SetChecked
  frame.OnValueChanged = RADIO.OnValueChanged
  frame.SetValue = RADIO.SetValue
  frame.GetValue = RADIO.GetValue

  frame.checked = nil
  if (cfg.checked) then
    frame:SetChecked()
  end
  frame:SetEnabled(cfg_enabled(cfg))
  return frame
end

--
-- A GROUP OF RADIO BUTTONS from a list of choices, laid out by the widget and throwing one event between them. The buttons are
-- the same ones KUI:CreateRadioButton makes by hand, in a group whose name nobody has to invent, so what this saves a caller is
-- the placement, the name, and the four events one click spreads over the two buttons that changed.
--
-- The choices stand one of three ways. With neither of the two below they are a column, one under another. cfg.spacing puts
-- them along one row, each as wide as its own words and that far past the words of the one before, however long those are.
-- cfg.positions puts them along one row at places of the caller's choosing, one for each choice, measured from the start of
-- the row, which is where a label to the left starts, so the first has to leave the label room; a choice's words are cut off
-- a gap short of the next choice rather than running into it. Given no width or height the group is as big as its choices.
--
-- A group is named one of two ways. cfg.title puts the choices in a KUI:CreateGroupBox, the thin border with its heading set
-- into the line, which is what a few controls under a heading of their own wear everywhere else here and takes the same six
-- locations. cfg.label is words beside or above a plain frame, as an edit box's label is (RADIO.grouplabel), and wins where
-- both are given. With neither the group is a plain frame with nothing drawn round it.
--
function RADIO.groupinside(this)
  return this.content or this
end

--
-- Where each button goes, and how wide it is: as wide as its words, and short of the next position where it has one. The frame
-- starts at the first choice with a label to the left hanging off it, so a position is taken back by the label's room (lead).
--
function RADIO.grouplayout(this)
  local inside = RADIO.groupinside(this)
  local x = 0

  for i, b in ipairs(this.buttons) do
    local w = b.wordswidth

    b:ClearAllPoints()

    if (this.positions) then
      local nextx = this.positions[i + 1]

      if (nextx) then
        w = max(1, min(w, nextx - this.positions[i] - KUI.WIDGET_GAP))
      end

      b:SetPoint("TOPLEFT", inside, "TOPLEFT", this.positions[i] - this.lead, 0)
    elseif (this.spacing) then
      b:SetPoint("TOPLEFT", inside, "TOPLEFT", x, 0)
      x = x + w + this.spacing
    else
      b:SetPoint("TOPLEFT", inside, "TOPLEFT", 0, 0 - (i - 1) * (KUI.CHECKBOX_SIZE + KUI.WIDGET_GAP))
    end

    b:SetWidth(w)
  end
end

--
-- One click moves two buttons and each of them says so, the one being checked saying so twice over, so the group listens for
-- the click itself and says once that its value has changed. A change made through ret:SetValue says so the same way, and a
-- click on the choice already chosen says nothing at all.
--
function RADIO.groupclicked(this)
  local grp = this.radiogroup

  if (grp and grp.value ~= this.value) then
    grp.value = this.value
    grp:Throw("OnValueChanged", this.value, true)
  end
end

function RADIO.GroupGetValue(this)
  return this.value
end

function RADIO.GroupSetValue(this, value, nothrow)
  local found

  for _, b in ipairs(this.buttons) do
    if (b.value == value) then
      found = b
    end
  end

  --
  -- A value none of the choices offers changes nothing, the same as a dropdown told to select an item it does not have.
  --
  if ((not found) or (this.value == value)) then
    return
  end

  this.value = value
  found:SetValue(value, true)

  if (not nothrow) then
    this:Throw("OnValueChanged", value, false)
  end
end

--
-- A disabled group greys every choice in it and, where it has a heading, that too. A choice the caller disabled on its own
-- stays disabled when the group is enabled again, the group's word being about the group and not about that choice.
--
function RADIO.GroupSetEnabled(this, onoff)
  onoff = onoff and true or false

  this.enabled = onoff
  this.groupenable(this, onoff)

  for _, b in ipairs(this.buttons) do
    b:SetEnabled(onoff and b.itemenabled)
  end

  -- The group's label greys with it, at half its colour, as an edit box's does.
  if (this.label) then
    local c = this.lrgb
    local d = onoff and 1 or 2

    this.label:SetTextColor(c.r / d, c.g / d, c.b / d, c.a)
  end
end

--
-- The words the group goes by, beside its first row of choices or above them, as an edit box's label is: to the LEFT the words
-- start at cfg.x and the choices stand INTERNAL_GAP past them, and on TOP the choices start a line lower and the frame says it
-- draws that line.
--
function RADIO.grouplabel(frame, cfg)
  local lc = cfg.label
  local lfont = lc.font or "GameFontNormal"
  local lw, lh = KUI:MeasureStrWidth(lc.text or "", lfont)
  local label = frame:CreateFontString(nil, "ARTWORK", lfont)
  local parent = frame:GetParent()
  local r, g, b, a = KUI:GetFontColor(lfont)

  assert(lc.pos == nil or lc.pos == "LEFT" or lc.pos == "TOP", "radio group label position can only be LEFT (default) or TOP")

  if (lc.color) then
    r, g, b, a = lc.color.r or r, lc.color.g or g, lc.color.b or b, lc.color.a or 1
  end

  lw = lc.width or lw
  lh = lc.height or lh
  frame.label = label
  frame.lrgb = { r = r, g = g, b = b, a = a }
  label:SetJustifyH(lc.justifyh or "LEFT")
  label:SetJustifyV(lc.justifyv or "MIDDLE")
  label:SetText(lc.text or "")

  if (lc.pos == "TOP") then
    label:SetSize(lw, lh)
    label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)

    if (cfg.y and cfg.y ~= "MIDDLE") then
      frame:SetPoint("TOP", parent, "TOP", 0, cfg.y - lh)
    end

    drawn_extent(frame, lh, 0)
    return
  end

  label:SetSize(lw, max(lh, KUI.CHECKBOX_SIZE))
  label:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0 - KUI.INTERNAL_GAP, 0)
  frame.lead = lw + KUI.INTERNAL_GAP

  if (cfg.x and cfg.x ~= "CENTER") then
    frame:SetPoint("LEFT", parent, "LEFT", cfg.x + lw + KUI.INTERNAL_GAP, 0)
  end
end

function KUI:CreateRadioGroup(cfg, kparent)
  local items = cfg.items or {}
  local n = #items
  local gname = "KUIRadioGroup" .. self:GetWidgetNum("radiogroup")
  local frame = (cfg.title and not cfg.label) and self:CreateGroupBox(cfg, kparent) or newobj(cfg, kparent, 100, 100, cfg.name)
  local inside = RADIO.groupinside(frame)
  local widest, total = 0, 0

  assert(not (cfg.spacing and cfg.positions), "a radio group takes spacing or positions, not both")
  assert(not cfg.positions or #cfg.positions >= n, "a radio group's positions must give one for every choice")

  frame.buttons = {}
  frame.spacing = tonumber(cfg.spacing)
  frame.positions = cfg.positions
  frame.lead = 0

  for i, it in ipairs(items) do
    local b = self:CreateRadioButton({ group = gname, value = it.value, enabled = it.enabled, tooltip = it.tooltip,
      label = { text = it.text, font = cfg.font } }, inside)

    b.radiogroup = frame
    b.itemenabled = cfg_enabled(it)
    b:Catch("OnClick", RADIO.groupclicked)
    frame.buttons[i] = b

    --
    -- Each choice has sized itself to its own words, which is the only measurement of them anybody here needs.
    --
    b.wordswidth = b:GetWidth()
    widest = max(widest, b.wordswidth)
    total = total + b.wordswidth
  end

  if (cfg.label) then
    RADIO.grouplabel(frame, cfg)
  end

  assert(not cfg.positions or n == 0 or cfg.positions[1] >= frame.lead, "a radio group's first position must clear its label")

  local r = frame.rings
  local rx = r and (r.left + r.right) or 0
  local ry = r and (r.top + r.bottom) or 0
  local inrow = (frame.spacing or frame.positions) and true or false

  if (not cfg.width and n > 0) then
    if (frame.positions) then
      frame:SetWidth(frame.positions[n] - frame.lead + frame.buttons[n].wordswidth + rx)
    elseif (frame.spacing) then
      frame:SetWidth(total + (n - 1) * frame.spacing + rx)
    else
      frame:SetWidth(widest + rx)
    end
  end

  if (not cfg.height) then
    local rows = inrow and 1 or max(1, n)

    frame:SetHeight(rows * KUI.CHECKBOX_SIZE + (rows - 1) * KUI.WIDGET_GAP + ry)
  end

  --
  -- The choices stop sizing themselves now that the layout says how wide they are, and their words are cut off rather than
  -- wrapped, a wrapped label growing down through whatever is drawn under it while the frame reports the height it was given.
  --
  for _, b in ipairs(frame.buttons) do
    b.autosize = false

    if (b.text) then
      b.text:SetWordWrap(false)
    end
  end

  RADIO.grouplayout(frame)

  frame.groupenable = frame.SetEnabled
  frame.SetEnabled = RADIO.GroupSetEnabled
  frame.GetValue = RADIO.GroupGetValue
  frame.SetValue = RADIO.GroupSetValue

  if (cfg.initialvalue ~= nil) then
    frame:SetValue(cfg.initialvalue, true)
  end

  frame:SetEnabled(cfg_enabled(cfg))

  return frame
end

local function update_eb_text(this)
  local val = this.value or 0
  this.editbox:SetText(floor((val * 100) + 0.5) / 100)
end

--
-- A slider's value is always a whole number of steps from its minimum. The engine's own value is wherever the thumb happens
-- to be, fractions and all, so the slider keeps the snapped one in this.value and answers GetValue with that; the engine's is
-- read only here, to snap it.
--
function SD.rawvalue(this)
  return getmetatable(this).__index.GetValue(this)
end

function SD.GetValue(this)
  return this.value
end

--
-- Every change of value comes through here, once. It is the user's doing when they are dragging, turning the wheel over it or
-- typing into its box, which is what USERCHANGE is set for around the last two.
--
local function update_editbox(this)
  if (not this.setup) then
    local val = SD.rawvalue(this)
    if (this.step and this.step > 0) then
      local mv = this.minval or 0
      val = (floor((val - mv) / this.step + 0.5) * this.step) + mv
    end
    if (val ~= this.value) then
      this.value = val
      this:Throw("OnValueChanged", this.value, (this.mousedown or this.userchange) and true or false)
    end
    if (this.value) then
      update_eb_text(this)
    end
  end
end

local function sde_OnEscapePressed(this)
  this:SetText(this:GetParent():GetValue())
  this:ClearFocus()
end

local function sde_OnEnterPressed(this)
  local val = tonumber(this:GetText())

  -- What is not a number at all, an emptied box included, is put back as it was.
  if (not val) then
    sde_OnEscapePressed(this)
    return
  end

  local p = this:GetParent()
  local minv, maxv = p:GetMinMaxValues()
  if (val >= minv and val <= maxv) then
    p.userchange = true
    p:SetValue(val)
    p.userchange = nil
    update_eb_text(p)
    this:ClearFocus()
  end
end

function SD.OnEnable(this, event, onoff)
  onoff = onoff and true or false
  this.enabled = onoff
  local d = onoff and 1 or 2

  if (onoff) then
    this:EnableMouse(true)
    this:EnableMouseWheel(true)
    this.editbox:EnableMouse(true)
  else
    this:EnableMouse(false)
    this:EnableMouseWheel(false)
    this.editbox:EnableMouse(false)
    this.editbox:ClearFocus()
  end

  local tr = this.mrgb
  this.mintxt:SetTextColor(tr.r/d, tr.g/d, tr.b/d, tr.a)
  this.maxtxt:SetTextColor(tr.r/d, tr.g/d, tr.b/d, tr.a)

  tr = this.kuichanged and KUI.DEFAULT_CHANGED_COLOR or this.ergb
  this.editbox:SetTextColor(tr.r/d, tr.g/d, tr.b/d, tr.a or 1)

  if (this.label) then
    tr = this.lrgb
    this.label:SetTextColor(tr.r/d, tr.g/d, tr.b/d, tr.a)
  end
  return false
end

function SD.OnMouseWheel(this, delta)
  if (not this.enabled) then
    return
  end

  local cv = this:GetValue()
  local vs = this:GetValueStep()
  if (delta > 0) then
    cv = cv - vs
  else
    cv = cv + vs
  end
  local mn,mx = this:GetMinMaxValues()
  if (cv < mn) then
    cv = mn
  elseif (cv > mx) then
    cv = mx
  end
  this.userchange = true
  this:SetValue(cv)
  this.userchange = nil
end

function SD.OnMouseDown(this)
  this.mousedown = true
end

function SD.OnMouseUp(this)
  this.mousedown = nil
end

function SD.changeminmax(this, newmin, newmax)
  this.minval = newmin
  this.maxval = newmax
  this:SetMinMaxValues(newmin, newmax)
  this.mintxt:SetText(tostring(newmin))
  this.maxtxt:SetText(tostring(newmax))

  -- A value outside the new range moves to the nearer end of it.
  if (this.value < newmin) then
    this:SetValue(newmin)
    this.value = newmin
  elseif (this.value > newmax) then
    this:SetValue(newmax)
    this.value = newmax
  end
end

function KUI:CreateSlider(cfg, kparent)
  local orientation = cfg.orientation or "HORIZONTAL"
  local dheight, dwidth
  if (orientation == "HORIZONTAL") then
    dwidth = 200
    dheight = 16
    if (cfg.label) then
      dheight = { 16, -16 }
    end
  else
    dheight = 200
    dwidth = 16
  end

  local frame,parent,width,height = newobj(cfg, kparent, dwidth, dheight, cfg.name, "Slider")

  local minval = cfg.minval or 0
  local maxval = cfg.maxval or 100
  local value = cfg.initialvalue or minval

  frame.setup = true

  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)

  frame:SetOrientation(orientation)
  if (orientation == "HORIZONTAL") then
    frame:SetHeight(height)
    frame:SetHitRectInsets(0, 0, -10, 0)
  else
    frame:SetWidth(width)
  end
  frame:SetMinMaxValues(minval, maxval)
  frame:SetValueStep(cfg.step or 1)
  if (frame.SetObeyStepOnDrag) then
    frame:SetObeyStepOnDrag(true)
  end
  frame.minval = minval
  frame.maxval = maxval
  frame.step = cfg.step or 1

  --
  -- The groove the knob runs in, as thick as the kit draws it and centred across the slider.
  --
  local track = KIT.new(frame, "SliderTrack", { layer = "BACKGROUND" })
  local tthick = track.def.draw

  if (orientation == "HORIZONTAL") then
    track.box:SetPoint("LEFT", frame, "LEFT", 0, 0)
    track.box:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    track.box:SetHeight(tthick)
  else
    track.box:SetPoint("TOP", frame, "TOP", 0, 0)
    track.box:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    track.box:SetWidth(tthick)
  end
  track:Layout(tthick)
  frame.track = track

  --
  -- The engine moves the thumb texture, so the knob is drawn in pieces anchored to it and the thumb itself draws nothing. It
  -- stands a little proud of the slider across it, and is as long as its drawing makes it at that size.
  --
  -- Size both dimensions here. Setting the size explicitly at this point is what makes the engine place the thumb correctly
  -- straight away; left to resolve it later, a fresh slider draws its thumb adrift and only corrects itself once something drags it.
  --
  frame:SetThumbTexture(KIT.sheet())
  local tt = frame:GetThumbTexture()
  local kd = KIT.def("SliderKnob")
  local across = ((orientation == "HORIZONTAL") and height or width) + 8
  local kw, kh = across * kd.aspect, across

  tt:SetSize(kw, kh)
  tt:SetAlpha(0)

  local knob = KIT.new(frame, "SliderKnob", { layer = "ARTWORK", sublevel = 0 })
  knob.box:SetAllPoints(tt)
  knob:Layout()

  local gd = KIT.def("SliderKnobGem")
  local gh = kh * gd.draw / kd.draw
  local gem = KIT.new(frame, "SliderKnobGem", { layer = "ARTWORK", sublevel = 2, flat = true, part = "gem" })
  gem.box:SetPoint("CENTER", tt, "CENTER", 0, 0)
  gem.box:SetSize(gh * gd.aspect, gh)
  gem:Layout()

  local shine = KIT.new(frame, "SliderKnobGemSparkle", { layer = "OVERLAY", accent = KUI.COLOR_WHITE })
  shine.box:SetAllPoints(gem.box)
  shine:Layout()

  frame.knob = knob
  KIT.interactive(frame, knob, gem)

  -- The min and max labels
  local mmfont = cfg.minmaxfont or "GameFontHighlightSmall"
  local mintxt = frame:CreateFontString(nil, "ARTWORK", mmfont)
  local maxtxt = frame:CreateFontString(nil, "ARTWORK", mmfont)
  frame.mintxt = mintxt
  frame.maxtxt = maxtxt
  local r, g, b, a = KUI:GetFontColor(mmfont)
  if (cfg.minmaxcolor) then
    r = cfg.minmaxcolor.r or r
    g = cfg.minmaxcolor.g or g
    b = cfg.minmaxcolor.b or b
    a = cfg.minmaxcolor.a or a
  end
  frame.mrgb = {r = r, g = g, b = b, a = a}

  -- The edit box for typing in values
  local editbox = MakeFrame("EditBox", nil, frame)
  frame.editbox = editbox
  editbox:SetAutoFocus(false)
  editbox:EnableMouse(true)
  editbox:SetNumeric(true)
  editbox:SetMaxLetters(4)
  editbox:SetFontObject(cfg.editfont or "GameFontHighlightSmall")
  r,g,b,a = KUI:GetFontColor(cfg.editfont or "GameFontHighlightSmall")
  if (cfg.editcolor) then
    r = cfg.editcolor.r or r
    g = cfg.editcolor.g or g
    b = cfg.editcolor.b or b
    a = cfg.editcolor.a or a
  end
  frame.ergb = {r = r, g = g, b = b, a = a}
  editbox:SetHeight(14)
  editbox:SetWidth(45)
  editbox:HookScript("OnEscapePressed", sde_OnEscapePressed)
  editbox:HookScript("OnEnterPressed", sde_OnEnterPressed)

  if (orientation == "HORIZONTAL") then
    editbox:SetJustifyH("CENTER")
    -- The label above the slider (only for horizontal sliders)
    if (cfg.label) then
      local label = frame:CreateFontString(nil, "OVERLAY", cfg.label.font or "GameFontNormal")
      r,g,b,a = KUI:GetFontColor(cfg.label.font or "GameFontNormal")
      if (cfg.label.color) then
        r = cfg.label.color.r or r
        g = cfg.label.color.g or g
        b = cfg.label.color.b or b
        a = cfg.label.color.a or a
      end
      frame.lrgb = {r = r, g = g, b = b, a = a}
      frame.label = label
      label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 16)
      label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 16)
      label:SetJustifyH(cfg.label.justifyh or "CENTER")
      label:SetJustifyV(cfg.label.justifyv or "MIDDLE")
      label:SetHeight(16)
      label:SetText(cfg.label.text or "")
      check_tooltip_title(frame, cfg, cfg.label.text)
    end
    mintxt:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 2, 3)
    maxtxt:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -2, 3)
    editbox:SetPoint("TOP", frame, "BOTTOM", 0, 0)
  else
    editbox:SetJustifyH("LEFT")
    mintxt:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, -4)
    maxtxt:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 4, 4)
    editbox:SetPoint("LEFT", frame, "RIGHT", 4, 0)
  end

  --
  -- A horizontal slider is a bar with its label over it and its value box under it, and the bar is the only part the frame
  -- can be. The min and max captions share the value box's row and so cost nothing further.
  --
  if (orientation == "HORIZONTAL") then
    drawn_extent(frame, frame.label and frame.label:GetHeight() or 0, editbox:GetHeight())
  end

  mintxt:SetText(tostring(minval))
  maxtxt:SetText(tostring(maxval))

  local bg = editbox:CreateTexture (nil, "BACKGROUND")
  bg:SetColorTexture(0, 0, 0, 0.25)
  bg:SetAllPoints(editbox)
  editbox.bg = bg

  frame:HookScript("OnValueChanged", update_editbox)
  frame:HookScript("OnMouseWheel", SD.OnMouseWheel)
  frame:HookScript("OnMouseDown", SD.OnMouseDown)
  frame:HookScript("OnMouseUp", SD.OnMouseUp)

  frame.OnEnable = SD.OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave
  frame.ChangeMinMax = SD.changeminmax
  frame.GetValue = SD.GetValue

  frame.value = value
  frame:SetValue(value)
  frame:SetEnabled(cfg_enabled(cfg))

  frame.setup = nil

  update_eb_text(frame)

  return frame
end

--
-- The fill for the dark middle of a button drawn with PIECE on OWNER at HEIGHT, boxed to OWNER. Every button has one unless
-- cfg.buttonfill = false on OWNER or a frame above it: the silhouette's own fill piece, in the buttonfill part's colour darkened
-- by KIT.FILL_SHADE, or in exactly the colour the nearest cfg.buttonfill names. Nil where it is turned off, or the kit has no
-- fill for PIECE.
--
function KIT.buttonfill(owner, piece, height)
  local bf = KIT.inherited(owner, "kuibuttonfill")

  if (bf == nil) then
    bf = true
  end

  if (not bf or not KIT.has(piece .. "Fill")) then
    return nil
  end

  local opts = { layer = "BACKGROUND", sublevel = 4, flat = true }

  if (type(bf) == "table") then
    opts.accent = bf
  else
    opts.part = "buttonfill"
    opts.shade = KIT.FILL_SHADE
  end

  local fill = KIT.new(owner, piece .. "Fill", opts)
  fill:SetBox(owner, 0, 0, 0, 0, height)
  return fill
end

--
-- A disabled button shows its dark middle whatever fill it has, the way it did before it had one.
--
-- The colour of the words on a button and in a closed dropdown: TEXT normally and TEXT_HOT while the pointer is on it. Both
-- read them, so the two can never disagree, and a disabled one greys whatever these say.
--
KIT.COLOR_TEXT = KUI.COLOR_WHITE
KIT.COLOR_TEXT_HOT = KUI.DEFAULT_ARTWORK_COLOR

--
-- A copy of the font BASE, named by its name, in TEXT or, HOT, in TEXT_HOT. A button is handed these as its normal and
-- highlight fonts, so the game still does the switching and only the colours are the kit's. Made once each.
--
KIT.fonts = {}

function KIT.textfont(base, hot)
  local key = base .. (hot and "Hot" or "")
  local f = KIT.fonts[key]

  if (not f) then
    local c = hot and KIT.COLOR_TEXT_HOT or KIT.COLOR_TEXT

    f = CreateFont("KoreUI" .. key)
    f:CopyFontObject(base)
    f:SetTextColor(c.r, c.g, c.b)
    KIT.fonts[key] = f
  end

  return f
end

-- A copy of the font BASE in the game's disabled colour, for a button whose words are drawn in a font other than its own.
function KIT.dimfont(base)
  local key = base .. "Dim"
  local f = KIT.fonts[key]

  if (not f) then
    local c = DISABLED_FONT_COLOR

    f = CreateFont("KoreUI" .. key)
    f:CopyFontObject(base)
    f:SetTextColor(c.r, c.g, c.b)
    KIT.fonts[key] = f
  end

  return f
end

local function bt_OnEnable(this, event, onoff)
  if (this.fill) then
    this.fill:SetShown(onoff and true or false)
  end
end

--
-- A button is one of the kit's four silhouettes, chosen by cfg.style and rounded unless it says otherwise, with its words over
-- it. The words stand clear of the half of each end nearest them, which is room enough for the word and no more of the end
-- than reads as ornament. Rounded is the default because pointed ends are what the pages, tabs and plaques wear, and a button
-- that looks like one of those reads as somewhere to go rather than something to do.
--
-- The dark middle wears a fill unless cfg.buttonfill on the button or a frame above it turns it off. See KIT.buttonfill.
--
function KUI:CreateButton(cfg, kparent)
  local frame, parent, width, height = newobj(cfg, kparent, 100, 24, cfg.name, "Button")
  local piece = KIT.BUTTONS[string.upper(cfg.style or "ROUNDED")] or KIT.BUTTONS.ROUNDED

  frame.art = KIT.new(frame, piece, { layer = "BACKGROUND" })
  frame.art:SetBox(frame, 0, 0, 0, 0, height)
  frame.fill = KIT.buttonfill(frame, piece, height)

  frame.OnEnable = bt_OnEnable
  KIT.interactive(frame, frame.art, frame.fill)

  local fs = frame:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(KIT.textfont("GameFontNormal"))
  frame:SetFontString(fs)
  frame:SetNormalFontObject(KIT.textfont("GameFontNormal"))
  frame:SetHighlightFontObject(KIT.textfont("GameFontNormal", true))
  frame:SetDisabledFontObject("GameFontDisable")
  frame:SetPushedTextOffset(1, -1)

  if (cfg.hook) then
    frame:HookScript("OnClick", function(this, ...)
      this:Throw("OnClick", ...)
    end)
  else
    frame:SetScript("OnClick", function(this, ...)
      this:Throw("OnClick", ...)
    end)
  end

  -- As an image button's, and wired only when asked for for the same reason. See KUI:CreateImageButton.
  if (cfg.doubleclick) then
    frame:SetScript("OnDoubleClick", function(this, ...)
      this:Throw("OnDoubleClick", ...)
    end)
  end

  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetText(cfg.text or "")
  check_tooltip_title(frame, cfg, cfg.text)

  fs:SetWidth(max(width - KIT.ends(frame.art, height) / 2, 1))
  fs:SetHeight(height - 6)

  frame:SetEnabled(cfg_enabled(cfg))
  return frame
end

--
-- A button whose face is a picture rather than a word: an icon, a card, one cell of a sprite sheet. A button's plate is no
-- use for any of those, so this one draws what it is given.
--
-- The picture fills the button. Nothing here scales it or preserves its shape -- the caller sets the size, and a caller who
-- cares about the aspect ratio works it out, because only the caller knows which of the two dimensions it is fitting into.
--
function IB.OnEnable(this, event, onoff)
  --
  -- A picture cannot go grey the way a caption does, so a disabled one is desaturated, which is what Blizzard does to an
  -- icon that cannot be used.
  --
  this.image:SetDesaturated(not onoff)
end

function IB.OnMouseDown(this)
  if (not this:IsEnabled()) then
    return
  end

  this.image:SetPoint("TOPLEFT", this, "TOPLEFT", 1, -1)
  this.image:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 1, -1)
end

function IB.OnMouseUp(this)
  this.image:SetPoint("TOPLEFT", this, "TOPLEFT", 0, 0)
  this.image:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 0, 0)
end

function IB.SetTexture(this, texture, texcoord)
  if (texture) then
    this.image:SetTexture(texture)
  end

  local tc = texcoord

  if (tc) then
    this.image:SetTexCoord(tc[1] or 0, tc[2] or 1, tc[3] or 0, tc[4] or 1)
  else
    this.image:SetTexCoord(0, 1, 0, 1)
  end
end

function IB.SetSelected(this, onoff)
  this.selected = onoff and true or false

  if (this.outline) then
    this.outline:SetShown(this.selected)
  end

  if (this.hoverglow) then
    local over = this:IsMouseOver()
    this.hoverrim:SetShown(over and not this.selected)
    this.hoverglow:SetShown(over)
  end
end

--
-- An outlined button wears the selected rim while it is selected, and a rim of half its weight while the pointer is on it, the
-- selected one taking over from the other. The pointer on it, selected or not, also lights its picture with a glow in the
-- outline's colour, which is all a selected button has to show it.
--
KIT.CARD_HOVER_RIM = 2

function KIT.rimenter(this)
  if (this.hoverglow) then
    this.hoverrim:SetShown(not this.selected)
    this.hoverglow:Show()
  end
end

function KIT.rimleave(this)
  if (this.hoverglow) then
    this.hoverrim:Hide()
    this.hoverglow:Hide()
  end
end

function KUI:CreateImageButton(cfg, kparent)
  local frame, parent, width, height =
    newobj(cfg, kparent, 32, 32, cfg.name, "Button")

  --
  -- The rim around the outside of the button, standing OUTLINESIZE clear of it and over the picture's edge, in the outline's
  -- colour. A button that is never selected does not ask for one and does not get it.
  --
  if (cfg.outline) then
    local ow = cfg.outlinesize or 2
    local oc = { r = cfg.outline.r or 1, g = cfg.outline.g or 1, b = cfg.outline.b or 1 }

    frame.outline = KIT.new(frame, "CardRimSelected", { layer = "OVERLAY", sublevel = 2, accent = oc })
    frame.outline:SetFrameBox(frame, 0 - ow, 0 - ow, 0 - ow, 0 - ow)
    frame.outline:Hide()

    frame.hoverrim = KIT.border(frame, "CardRim", KIT.CARD_HOVER_RIM, { layer = "OVERLAY", sublevel = 0, accent = oc })
    frame.hoverrim:SetFrameBox(frame, 0 - ow, 0 - ow, 0 - ow, 0 - ow)
    frame.hoverrim:Hide()

    frame.hoverglow = KIT.new(frame, "RowGlow", { layer = "ARTWORK", sublevel = 2, accent = oc, intensity = KIT.ROW_HOVER })
    frame.hoverglow:SetBox(frame, 0, 0, 0, 0)
    frame.hoverglow:Hide()

    frame:HookScript("OnEnter", KIT.rimenter)
    frame:HookScript("OnLeave", KIT.rimleave)
  end

  local image = frame:CreateTexture(nil, "ARTWORK")
  image:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  image:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.image = image

  --
  -- A face drawn from the kit rather than a picture: cfg.piece names the piece, which fills the button and follows the pointer
  -- and whether the button is enabled the way every other control in the kit does.
  --
  if (cfg.piece) then
    frame.art = KIT.new(frame, cfg.piece, { layer = "ARTWORK", sublevel = 1 })
    frame.art:SetBox(frame)
    KIT.interactive(frame, frame.art)
  end

  --
  -- A caption over the picture, for a button whose picture does not say enough by itself or has not been drawn yet. Made
  -- either way, because a caller that reuses one button for several things may want it later.
  --
  local fs = frame:CreateFontString(nil, "OVERLAY",
    cfg.font or "GameFontNormal")
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", cfg.textx or 10,
    0 - (cfg.texty or 10))
  fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0 - (cfg.textx or 10),
    0 - (cfg.texty or 10))
  fs:SetJustifyH(cfg.justifyh or "LEFT")
  frame:SetFontString(fs)

  --
  -- A caller's own highlight texture, or else the kit's glow over the picture while the pointer is on it. An outlined button
  -- has its hover rim instead and wants no glow over its picture as well.
  --
  if (type(cfg.highlight) == "string") then
    frame:SetHighlightTexture(cfg.highlight, "ADD")
  elseif ((cfg.highlight == nil or cfg.highlight) and not cfg.outline and not cfg.piece) then
    KIT.rowglow(frame, "OVERLAY")
  end

  frame.SetTexture = IB.SetTexture
  frame.SetSelected = IB.SetSelected
  frame.OnEnable = IB.OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetTexture(cfg.texture, cfg.texcoord)

  if (cfg.color) then
    image:SetVertexColor(cfg.color.r or 1, cfg.color.g or 1, cfg.color.b or 1,
      cfg.color.a or 1)
  end

  frame:SetText(cfg.text or "")
  check_tooltip_title(frame, cfg, cfg.text)

  if (cfg.push == nil or cfg.push) then
    frame:HookScript("OnMouseDown", IB.OnMouseDown)
    frame:HookScript("OnMouseUp", IB.OnMouseUp)
  end

  if (cfg.hook) then
    frame:HookScript("OnClick", function(this, ...)
      this:Throw("OnClick", ...)
    end)
  else
    frame:SetScript("OnClick", function(this, ...)
      this:Throw("OnClick", ...)
    end)
  end

  --
  -- A second click is a second intention rather than a repeat of the first: pick this one, then go into it. Wired only when
  -- the caller asks for it, because WoW gives the second click of a pair to OnDoubleClick INSTEAD of OnClick, and a button
  -- with no use for the distinction would have every other click quietly go missing.
  --
  if (cfg.doubleclick) then
    frame:SetScript("OnDoubleClick", function(this, ...)
      this:Throw("OnDoubleClick", ...)
    end)
  end

  frame:SetEnabled(cfg_enabled(cfg))
  return frame
end

--
-- A tabbed dialog has two independent strips of buttons. They are different things with different geometry and different
-- art, and the words for them are used strictly throughout this file:
--
--   PAGES are the buttons along the BOTTOM edge of the dialog. A page is a whole screen. It owns a frame, a content area,
--     a top bar and a title.
--
--   TABS are the buttons along the TOP of a page, drawn in that page's top bar. A page may have any number of tabs; a tab
--     may not have tabs of its own.
--
-- Both are addressed by NAME everywhere in this API, never by position. A page or a tab carries an "order", and that decides
-- only where in its strip it is drawn. Position shifts whenever something is hidden, added or removed; a name does not,
-- which is the entire point of the distinction.
--
-- The pages hang below the window, their tops tucked up into the tray the window's bottom edge steps down into, and the tray
-- is drawn under however many of them are showing. The tabs stand along the bottom of a page's top bar, on the window's
-- inner rule. Where the pages start is worked out when the window is built, being how far in the tray can start past the
-- corner and how far down the tray's floor line is.
--
-- The button of the page showing carries its fill, a shade of the window's gem colour, and a gem over each of the stones in
-- its ends. The button of the tab showing carries its fill and the window's gem in the setting on its top edge.
--

--
-- How big, against a stone in a button's art, the gem laid over it on the selected button is drawn. Never more than the stone
-- itself, so that the metal the stone is set in still shows round it: every gem keeps its border.
--
KIT.STONE_COVER = 1.0

--
-- How much darker than the gem colour the fill in a selected tab or page button is drawn, so the stones stand out bright
-- against it rather than being lost in the same blue.
--
KIT.FILL_SHADE = 0.6

local PAGE_STRIP = {
  point = "BOTTOMLEFT", x = 0, y = 0, chainx = 2, chainy = 0,
  piece = "PageTab", fill = "PageTabFill", height = 32, pad = 8,
}

local TAB_STRIP = {
  point = "BOTTOMLEFT", x = 0, y = 24, chainx = 2, chainy = 0,
  piece = "PanelTab", fill = "PanelTabFill", gem = true, height = 24, pad = 8,
}

--
-- A button for either strip. SetSelectedState shows its fill or its gem and lights its words, and the button stays lit as if
-- hovered, which is what tells the current page from the others at a glance.
--
function KIT.tabselect(this, onoff)
  onoff = onoff and true or false

  if (this.fill) then
    this.fill:SetShown(onoff)
  end
  if (this.gem) then
    this.gem:SetShown(onoff)
  end
  if (this.stones) then
    for _, stone in ipairs(this.stones) do
      stone:SetShown(onoff)
    end
  end

  this:SetNormalFontObject(onoff and "GameFontHighlightSmall" or "GameFontNormalSmall")
  this.kuihot = onoff or nil
  KIT.sync(this)
end

function KIT.tabresize(this)
  local st = this.strip
  local w = ceil(this:GetFontString():GetStringWidth()) + KIT.ends(this.art, st.height) + 2 * st.pad

  this:SetWidth(max(w, ceil(this.art:fixedlength(st.height)) + 2 * st.pad))
end

function KIT.tabbutton(parent, fname, text, st)
  local tb = MakeFrame("Button", fname, parent)
  local h = st.height

  tb.strip = st
  tb:SetHeight(h)

  tb.art = KIT.new(tb, st.piece, { layer = "BACKGROUND", sublevel = 0 })
  tb.art:SetBox(tb, 0, 0, 0, 0, h)

  --
  -- The fill goes over the art and under the gem, which KIT.gem sets four sublevels above the art, so the two never share a
  -- sublevel and leave which is drawn on top to the engine.
  --
  if (st.fill) then
    tb.fill = KIT.new(tb, st.fill, { layer = "BACKGROUND", sublevel = 2, flat = true, part = "tabfill",
      shade = KIT.FILL_SHADE })
    tb.fill:SetBox(tb, 0, 0, 0, 0, h)
    tb.fill:Hide()
  end

  if (st.gem) then
    tb.gem = KIT.gem(tb.art)
    if (tb.gem) then
      tb.gem:SetShown(false)
    end
  end

  --
  -- A button whose art has stones set in its ends has them drawn in the metal's colour with the rest of it, so the button
  -- that is selected lays one of the kit's gems over each, in the gem colour, sized by KIT.STONE_COVER so that the metal the
  -- stone is set in still shows round it. The stones are placed from the map, each end being drawn at its own size.
  --
  local sd = tb.art.def.stones

  if (sd) then
    local nw = h * tb.art.def.aspect

    tb.stones = {}
    for side = 0, 1 do
      local l, r, t, b = sd[side * 4 + 1], sd[side * 4 + 2], sd[side * 4 + 3], sd[side * 4 + 4]
      local size = max((r - l) * nw, (b - t) * h) * KIT.STONE_COVER
      local cy = 0 - (t + b) / 2 * h
      local stone = KIT.new(tb, "GemDiamond", { layer = "BORDER", sublevel = 0, flat = true, part = "gem" })

      if (side == 0) then
        stone.box:SetPoint("CENTER", tb, "TOPLEFT", (l + r) / 2 * nw, cy)
      else
        stone.box:SetPoint("CENTER", tb, "TOPRIGHT", 0 - (1 - (l + r) / 2) * nw, cy)
      end
      stone.box:SetSize(size, size)
      stone:Layout()
      stone:Hide()
      tb.stones[side + 1] = stone
    end
  end

  local fs = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER", tb, "CENTER", 0, KIT.bodyoffset(tb.art, h))
  tb:SetFontString(fs)
  tb:SetNormalFontObject("GameFontNormalSmall")
  tb:SetHighlightFontObject("GameFontHighlightSmall")
  tb:SetDisabledFontObject("GameFontDisableSmall")

  tb.SetSelectedState = KIT.tabselect
  KIT.interactive(tb, tb.art, tb.fill, tb.stones and tb.stones[1], tb.stones and tb.stones[2])

  tb:SetText(text or "")
  KIT.tabresize(tb)
  return tb
end

local function order_sorter(a, b)
  return (tonumber(a.order) or 0) < (tonumber(b.order) or 0)
end

--
-- Re-anchor a strip of buttons, skipping the hidden ones so that the strip closes up instead of leaving a hole where a
-- button used to be. Every path that changes what is visible in a strip finishes here.
--
local function strip_relayout(list, anchor, geom)
  local prev = nil
  local x = anchor.kuistripx or geom.x
  local y = anchor.kuistripy or geom.y
  local span = 0

  for k, v in ipairs(list) do
    local tb = v.tbutton

    if (tb) then
      if (v.hidden) then
        tb:Hide()
      else
        tb:ClearAllPoints()
        if (prev) then
          tb:SetPoint("TOPLEFT", prev, "TOPRIGHT", geom.chainx, geom.chainy)
          span = span + geom.chainx
        else
          tb:SetPoint("TOPLEFT", anchor, geom.point, x, y)
        end
        tb:Show()
        span = span + tb:GetWidth()
        prev = tb
      end
    end
  end

  --
  -- A window whose bottom edge carries a tray fits the tray to the pages showing, from the left of the first to the right of
  -- the last, and takes it away altogether when none are.
  --
  if (anchor.kuitray and geom == PAGE_STRIP) then
    anchor:kuitray(prev and x or nil, prev and (x + span) or nil)
  end
end

--
-- Mark the button named SELNAME as the one showing and every other one as not.
--
local function strip_select(list, selname)
  for k, v in ipairs(list) do
    if (v.tbutton) then
      v.tbutton:SetSelectedState(v.name == selname)
    end
  end
end

--
-- The name of the first entry in LIST that is not hidden, or nil if every one of them is.
--
local function first_visible(list)
  for k, v in ipairs(list) do
    if (not v.hidden) then
      return v.name
    end
  end

  return nil
end

--
-- Where to go when the entry named NAME stops being available. We look to the LEFT first, because a strip reads left to
-- right and the neighbour before the one that went away is where the eye already is. Only if nothing to the left is visible
-- do we look right. If the strip has nothing visible left at all we return nil, and the caller shows nothing -- an empty
-- strip is a legitimate state, not an error.
--
local function nearest_visible(list, name)
  local idx = nil

  for k, v in ipairs(list) do
    if (v.name == name) then
      idx = k
      break
    end
  end

  if (not idx) then
    return first_visible(list)
  end

  for k = idx - 1, 1, -1 do
    if (not list[k].hidden) then
      return list[k].name
    end
  end

  for k = idx + 1, #list do
    if (not list[k].hidden) then
      return list[k].name
    end
  end

  return nil
end

local function do_split(cframe, arg, which)
  local oname = arg.name

  if (not arg.name) then
    arg.name = cframe:GetName() .. ((which == "h") and "HSplit" or "VSplit")
  end

  if (which == "h") then
    cframe.hsplit = KUI:CreateHSplit(arg, cframe)
  else
    cframe.vsplit = KUI:CreateVSplit(arg, cframe)
  end

  arg.name = oname
end

--
-- Build the frames for one page: its full-size frame, its content area, its top bar, and its button on the bottom strip.
-- This is split out from CreateTabbedDialog so that AddPage() can build a page long after the dialog itself exists. Every
-- frame is named for the page rather than for its position, because a position moves and a WoW frame name cannot.
--
--
-- In a dialog that keeps the save bar's room (cfg.savebarreserved), a page or tab can do without it. With cfg.savebar false
-- it never has the bar and takes the room for itself; with cfg.savebaroffset it takes the room too and puts the bar up
-- that far above the foot of the content, so that it can keep something of its own under it. What the page or tab ends up
-- with is kept on OBJ, the page or the tab, as .nosavebar and .savebaroffset, the latter being free to set again later once
-- the page knows how tall its own thing is. Answers how far the content reaches down past the dialog's content to do it.
--
local function savebar_claim(frame, cfg, obj)
  obj.nosavebar = (cfg.savebar == false)
  obj.savebaroffset = (type(cfg.savebaroffset) == "number") and cfg.savebaroffset or nil

  if (not frame.savebarreserved or not (obj.nosavebar or obj.savebaroffset)) then
    return 0
  end

  return frame.savebarheight or 0
end

local function build_page(frame, cfg)
  local fname = frame:GetName()

  --
  -- The caller's own config table is kept as .cfg. KoreUI never looks inside it beyond the fields below, but a caller
  -- commonly wants to hang its own meaning on a page -- who may see it, which subsystem owns it -- and this saves it keeping
  -- a parallel table keyed by page name.
  --
  local pg = {
    name = cfg.name,
    title = cfg.title,
    text = cfg.text,
    order = cfg.order,
    hidden = cfg.hidden and true or false,
    onclick = cfg.onclick,
    deftab = cfg.deftab,
    tabframe = cfg.tabframe,
    cfg = cfg,
    tabs = {},
    tabsbyname = {},
    retired = {},
  }

  local pf = MakeFrame("Frame", fname .. "Page" .. pg.name, frame)
  pf:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  pf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  pf.pagename = pg.name
  pf:Hide()
  pg.frame = pf

  --
  -- A page's content is the dialog's content, and its top bar the dialog's top bar: the same rectangles rather than the same
  -- numbers written down twice, which is how they came to disagree.
  --
  -- cfg.padding insets it. A page that puts widgets straight onto its content wants it, because nothing else is standing
  -- them off the dialog's edge; a page that declares a split does not, because the split's panels bring their own padding
  -- and this would be added to it.
  --
  local pp = padding_sides(cfg.padding, 0)
  local pcf = MakeFrame("Frame", pf:GetName() .. "Content", pf)
  pcf:SetPoint("TOPLEFT", frame.content, "TOPLEFT", pp.left, 0 - pp.top)
  pcf:SetPoint("BOTTOMRIGHT", frame.content, "BOTTOMRIGHT", 0 - pp.right, pp.bottom - savebar_claim(frame, cfg, pg))
  pcf.pagename = pg.name
  pg.content = pcf

  --
  -- If the caller asked for a split, reserve the space now. Only one of the two is honoured; setting both is not supported.
  --
  if (cfg.hsplit) then
    pg.hsplit = cfg.hsplit
    do_split(pcf, cfg.hsplit, "h")
  end

  if (cfg.vsplit) then
    pg.vsplit = cfg.vsplit
    do_split(pcf, cfg.vsplit, "v")
  end

  local ptb = MakeFrame("Frame", pf:GetName() .. "Topbar", pf)
  ptb:SetAllPoints(frame.topbar)
  ptb.pagename = pg.name
  pg.topbar = ptb

  local tb = KIT.tabbutton(frame, fname .. "Tab" .. pg.name, pg.text, PAGE_STRIP)
  tb.pagename = pg.name
  tb:SetFrameLevel(frame:GetFrameLevel() + 2)
  tb:SetScript("OnClick", function(this)
    this:GetParent():SetPage(this.pagename)
  end)
  tb.SetShown = BC.SetShown
  pg.tbutton = tb

  return pg
end

--
-- Build one tab inside page PG: its content frame and its button on that page's top strip. Where the page has a split and
-- asked, through tabframe, for only one side of it to change as tabs are selected, the tab's content covers just that side;
-- otherwise, or for a tab that asks for the whole page, it covers the whole page content.
--
local function build_tab(frame, pg, cfg)
  local tab = {
    name = cfg.name,
    text = cfg.text,
    order = cfg.order,
    hidden = cfg.hidden and true or false,
    onclick = cfg.onclick,
    wholepage = cfg.wholepage and true or false,
    cfg = cfg,
  }

  local stcontent = pg.content

  if (pg.tabframe and (pg.vsplit or pg.hsplit) and not tab.wholepage) then
    if (pg.vsplit) then
      if (pg.tabframe == "LEFT") then
        stcontent = pg.content.vsplit.leftframe
      elseif (pg.tabframe == "RIGHT") then
        stcontent = pg.content.vsplit.rightframe
      end
    elseif (pg.hsplit) then
      if (pg.tabframe == "TOP") then
        stcontent = pg.content.hsplit.topframe
      elseif (pg.tabframe == "BOTTOM") then
        stcontent = pg.content.hsplit.bottomframe
      end
    end
  end

  local sp = padding_sides(cfg.padding, 0)
  local claim = savebar_claim(frame, cfg, tab)

  -- A page that has taken the save bar's room already reaches down into it, so its tabs have nothing more to take.
  if (pg.nosavebar) then
    claim = 0
  end

  local scf = MakeFrame("Frame",
    pg.content:GetName() .. "Sub" .. tab.name, stcontent)
  scf:SetPoint("TOPLEFT", stcontent, "TOPLEFT", sp.left, 0 - sp.top)
  scf:SetPoint("BOTTOMRIGHT", stcontent, "BOTTOMRIGHT", 0 - sp.right, sp.bottom - claim)
  scf.pagename = pg.name
  scf.tabname = tab.name
  scf:Hide()
  tab.content = scf

  if (cfg.hsplit) then
    tab.hsplit = cfg.hsplit
    do_split(scf, cfg.hsplit, "h")
  end

  if (cfg.vsplit) then
    tab.vsplit = cfg.vsplit
    do_split(scf, cfg.vsplit, "v")
  end

  --
  -- The button is a child of the page frame even though it is anchored to that page's top bar, so that hiding the page hides its tab strip too.
  --
  local stb = KIT.tabbutton(pg.frame, pg.frame:GetName() .. "Tab" .. tab.name, tab.text, TAB_STRIP)
  stb.pagename = pg.name
  stb.tabname = tab.name
  stb:SetScript("OnClick", function(this)
    frame:SetPage(this.pagename, this.tabname)
  end)
  stb.SetShown = BC.SetShown
  tab.tbutton = stb

  return tab
end

--
-- Select the page named PAGENAME and, within it, the tab named TABNAME. Both are optional. A nil page means "whichever is
-- current, else the default, else the first visible one", and a nil tab means the same within the chosen page. Naming a page
-- that does not exist, or one that is hidden, falls back the same way, so a caller never has to check first.
--
-- Returns the page name and tab name actually selected, or nil if every page is hidden.
--
function TD.SetPage(self, pagename, tabname)
  local pg = pagename and self.pagesbyname[pagename] or nil

  if (not pg or pg.hidden) then
    pg = self.pagesbyname[self.currentpage or ""]
  end

  if (not pg or pg.hidden) then
    pg = self.pagesbyname[self.defpage or ""]
  end

  if (not pg or pg.hidden) then
    pg = self.pagesbyname[first_visible(self.pages) or ""]
  end

  --
  -- Nothing is visible. Show no page at all and fall back to the dialog's own title.
  --
  if (not pg) then
    for k, v in ipairs(self.pages) do
      v.frame:Hide()
    end

    strip_select(self.pages, nil)
    self.currentpage = nil
    self.pagecontent = nil

    if (self.titletext and self.titletext ~= "") then
      self.title:SetText(self.titletext)
    else
      self.title:SetText(self.maintitle or "")
    end

    return nil
  end

  for k, v in ipairs(self.pages) do
    if (v.name == pg.name) then
      v.frame:Show()
    else
      v.frame:Hide()
    end
  end

  strip_select(self.pages, pg.name)
  self.currentpage = pg.name
  self.pagecontent = pg.content

  --
  -- A page with no title of its own, in a dialog with none either, shows none, rather than the title of the page before it.
  --
  if (pg.title) then
    self.title:SetText(pg.title)
  elseif (self.titletext and self.titletext ~= "") then
    self.title:SetText(self.titletext)
  else
    self.title:SetText(self.maintitle or "")
  end

  local tab = tabname and pg.tabsbyname[tabname] or nil

  if (not tab or tab.hidden) then
    tab = pg.tabsbyname[pg.currenttab or ""]
  end

  if (not tab or tab.hidden) then
    tab = pg.tabsbyname[pg.deftab or ""]
  end

  if (not tab or tab.hidden) then
    tab = pg.tabsbyname[first_visible(pg.tabs) or ""]
  end

  --
  -- A page with no tabs at all, or one whose tabs are all hidden, is perfectly normal: its own content frame is the whole
  -- page. What a tab that has just been hidden was showing goes with it.
  --
  --
  -- The split the tabs share one side of is hidden under a tab that covers the whole page, and back for any other.
  --
  local split = pg.tabframe and (pg.content.vsplit or pg.content.hsplit)

  if (split) then
    split:SetShown(not (tab and tab.wholepage))
  end

  if (not tab) then
    for k, v in ipairs(pg.tabs) do
      v.content:Hide()
    end

    strip_select(pg.tabs, nil)
    pg.currenttab = nil
    self:SyncPending()

    if (self.onclick) then
      self:onclick(pg.name, nil)
    end

    if (pg.onclick) then
      pg:onclick(pg.name, nil)
    end

    return pg.name
  end

  for k, v in ipairs(pg.tabs) do
    if (v.name == tab.name) then
      v.content:Show()
    else
      v.content:Hide()
    end
  end

  strip_select(pg.tabs, tab.name)
  pg.currenttab = tab.name
  self.pagecontent = tab.content
  self:SyncPending()

  if (self.onclick) then
    self:onclick(pg.name, tab.name)
  end

  if (pg.onclick) then
    pg:onclick(pg.name, tab.name)
  end

  if (tab.onclick) then
    tab:onclick(pg.name, tab.name)
  end

  return pg.name, tab.name
end

--
-- Select a tab within the page that is already current.
--
function TD.SetTab(self, tabname)
  return TD.SetPage(self, self.currentpage, tabname)
end

function TD.GetPage(self, pagename)
  return self.pagesbyname[pagename or self.currentpage or ""]
end

function TD.GetTab(self, pagename, tabname)
  local pg = TD.GetPage(self, pagename)

  if (not pg) then
    return nil
  end

  return pg.tabsbyname[tabname or pg.currenttab or ""]
end

--
-- Retitle the page named PAGENAME. The plaque is shared by every page and shows whichever one is current, so the words on
-- screen change now only if this is that page; any other page's new title is waiting for it when it is next selected.
--
-- This is for a dialog whose pages are named after something that changes under them, where rebuilding the whole window to
-- relabel it would throw away every frame in it.
--
function TD.SetPageTitle(self, pagename, title)
  local pg = self.pagesbyname[pagename]

  if (not pg) then
    return
  end

  pg.title = title

  if (self.currentpage == pagename) then
    if (title) then
      self.title:SetText(title)
    elseif (self.titletext and self.titletext ~= "") then
      self.title:SetText(self.titletext)
    else
      self.title:SetText(self.maintitle or "")
    end
  end
end

--
-- Show or hide the page named PAGENAME. The strip closes up around it, and if the page being hidden was the current one we
-- move to its nearest visible neighbour rather than leaving the dialog showing nothing.
--
function TD.SetPageShown(self, pagename, onoff)
  local pg = self.pagesbyname[pagename]

  if (not pg) then
    return
  end

  local hidden = not onoff

  if (pg.hidden == hidden) then
    return
  end

  local fallback = nearest_visible(self.pages, pagename)

  pg.hidden = hidden
  strip_relayout(self.pages, self, PAGE_STRIP)

  if (hidden) then
    if (self.currentpage == pagename) then
      TD.SetPage(self, fallback)
    end
  elseif (not self.currentpage) then
    TD.SetPage(self, pagename)
  end
end

-- Whether the dialog has a page named PAGENAME and it is not hidden, so that SetPage would select it.
function TD.IsPageShown(self, pagename)
  local pg = self.pagesbyname[pagename]

  return (pg and not pg.hidden) and true or false
end

--
-- Show or hide one tab of one page. As with pages, the strip closes up and a hidden current tab moves to its nearest visible neighbour.
--
function TD.SetTabShown(self, pagename, tabname, onoff)
  local pg = self.pagesbyname[pagename]

  if (not pg) then
    return
  end

  local tab = pg.tabsbyname[tabname]

  if (not tab) then
    return
  end

  local hidden = not onoff

  if (tab.hidden == hidden) then
    return
  end

  local fallback = nearest_visible(pg.tabs, tabname)

  tab.hidden = hidden
  strip_relayout(pg.tabs, pg.topbar, TAB_STRIP)

  if (self.currentpage ~= pagename) then
    if (pg.currenttab == tabname and hidden) then
      pg.currenttab = fallback
    end
    return
  end

  if (hidden) then
    if (pg.currenttab == tabname) then
      TD.SetPage(self, pagename, fallback)
    end
  elseif (not pg.currenttab) then
    TD.SetPage(self, pagename, tabname)
  end
end

--
-- Add a page to the dialog after it has been created. If a page of this name was removed earlier its frames are reused,
-- because WoW frames cannot be destroyed and creating a fresh set on every add would leak them for the life of the session.
-- CFG takes the same fields as a page in the tabs config passed to CreateTabbedDialog, including its own tabs.
--
function TD.AddPage(self, cfg)
  if (not cfg or not cfg.name) then
    return nil
  end

  if (self.pagesbyname[cfg.name]) then
    return self.pagesbyname[cfg.name]
  end

  local pg = self.retired[cfg.name]

  if (pg) then
    self.retired[cfg.name] = nil
    pg.hidden = false
    if (cfg.order) then
      pg.order = cfg.order
    end
  else
    pg = build_page(self, cfg)

    if (cfg.tabs) then
      for k, v in pairs(cfg.tabs) do
        local tcfg = v
        tcfg.name = tcfg.name or k
        local tab = build_tab(self, pg, tcfg)
        tinsert(pg.tabs, tab)
        pg.tabsbyname[tab.name] = tab
      end
      tsort(pg.tabs, order_sorter)
      strip_relayout(pg.tabs, pg.topbar, TAB_STRIP)
    end
  end

  self.pagesbyname[pg.name] = pg
  tinsert(self.pages, pg)
  tsort(self.pages, order_sorter)
  strip_relayout(self.pages, self, PAGE_STRIP)

  if (not self.currentpage) then
    TD.SetPage(self, pg.name)
  end

  return pg
end

--
-- Remove the page named PAGENAME. Its frames are retired rather than destroyed - WoW has no way to destroy a frame - and
-- are reused if a page of the same name is added again later.
--
function TD.RemovePage(self, pagename)
  local pg = self.pagesbyname[pagename]

  if (not pg) then
    return
  end

  local fallback = nearest_visible(self.pages, pagename)

  for k, v in ipairs(self.pages) do
    if (v.name == pagename) then
      tremove(self.pages, k)
      break
    end
  end

  self.pagesbyname[pagename] = nil
  self.retired[pagename] = pg

  pg.tbutton:Hide()
  pg.frame:Hide()

  strip_relayout(self.pages, self, PAGE_STRIP)

  if (self.currentpage == pagename) then
    self.currentpage = nil
    TD.SetPage(self, fallback)
  end
end

--
-- Add a tab to an existing page, reusing a retired tab of the same name if there is one, for the same reason AddPage does.
--
function TD.AddTab(self, pagename, cfg)
  local pg = self.pagesbyname[pagename]

  if (not pg or not cfg or not cfg.name) then
    return nil
  end

  if (pg.tabsbyname[cfg.name]) then
    return pg.tabsbyname[cfg.name]
  end

  local tab = pg.retired[cfg.name]

  if (tab) then
    pg.retired[cfg.name] = nil
    tab.hidden = false
    if (cfg.order) then
      tab.order = cfg.order
    end
  else
    tab = build_tab(self, pg, cfg)
  end

  pg.tabsbyname[tab.name] = tab
  tinsert(pg.tabs, tab)
  tsort(pg.tabs, order_sorter)
  strip_relayout(pg.tabs, pg.topbar, TAB_STRIP)

  if (self.currentpage == pagename and not pg.currenttab) then
    TD.SetPage(self, pagename, tab.name)
  end

  return tab
end

--
-- Remove a tab from a page, retiring its frames for reuse.
--
function TD.RemoveTab(self, pagename, tabname)
  local pg = self.pagesbyname[pagename]

  if (not pg) then
    return
  end

  local tab = pg.tabsbyname[tabname]

  if (not tab) then
    return
  end

  local fallback = nearest_visible(pg.tabs, tabname)

  for k, v in ipairs(pg.tabs) do
    if (v.name == tabname) then
      tremove(pg.tabs, k)
      break
    end
  end

  pg.tabsbyname[tabname] = nil
  pg.retired[tabname] = tab

  tab.tbutton:Hide()
  tab.content:Hide()

  strip_relayout(pg.tabs, pg.topbar, TAB_STRIP)

  if (pg.currenttab == tabname) then
    pg.currenttab = nil
    if (self.currentpage == pagename) then
      TD.SetPage(self, pagename, fallback)
    else
      pg.currenttab = fallback
    end
  end
end

--
-- A tabbed dialog is the kit's tabbed window. Its rim's bottom edge steps down into a tray under the page buttons. The window's
-- title sits in WindowTitlePlaque, set into the middle of the top edge with the window's gem on it, and its portrait in
-- WindowPortrait over the top left corner. The band between the plaque and the content is the top bar, where the tabs stand.
--
-- The rim comes plain or fancy, cfg.innerart = "FANCY" asking for the fancy one. WindowTabbed, the plain one, has rounded
-- corners and nothing inside it. WindowTabbedFancy has a flourish standing out from each corner, and WindowTabbedFancyInner, a
-- rule round the content that the tabs stand on. Each has its own tray, the two bottom edges being cut from different
-- drawings. TD.PLAIN and TD.FANCY name the pieces, and a style without a rule has none.
--
-- Every distance below is the art's own, measured by the build, except the few named here, which are room between things.
--
-- TD_GAP is the space between the rim and the rule round the content, or the content itself where there is no rule. TD_BAR
-- is how tall the top bar is, which holds the tabs and whatever the caller puts in ret.topbar. TD_PORTRAIT is how big the
-- portrait is drawn, which brings its foot down to the top of the content and no further, and TD_PORTRAIT_ABOVE how far its
-- top stands out over the window's top edge. TD_TRAY_PAD is how far the floor of the tray runs past the page buttons at each
-- end. TD_LIFT is how much lighter the surface is drawn across the top of the window, down to where the content starts, so
-- that the title and the top bar stand on a band of their own. The surface is added over itself there at that strength,
-- since a tint can only darken it.
--
-- TD_PORTRAIT_POINT is the art's own and not measured by the build: how far across the portrait the point at the foot of its
-- bottom left corner runs down, as a share of its width, measured through the middle of the star it is the foot of. The
-- portrait is placed across the window so that point stands on the middle of the rim's left line, which runs on down from it.
--
TD.GAP = 2
TD.BAR = 28
TD.PORTRAIT = 64
TD.PORTRAIT_ABOVE = 16
TD.PORTRAIT_POINT = 0.115
TD.TRAY_PAD = 4
TD.LIFT = 0.75
TD.PLAIN = { rim = "WindowTabbed", tray = "WindowTabbedTray" }
TD.FANCY = { rim = "WindowTabbedFancy", rule = "WindowTabbedFancyInner", tray = "WindowTabbedFancyTray" }

--
-- The save bar, a panel across the foot of the content, or its head as cfg.savebarlocation says, that a page puts up while
-- it has changes not yet saved. It is a panel like any other, the panel rim and its ground, with the Separator's diamond laid
-- on the middle of its top line and a stone in it, and holds one wide button and a few small words under it saying what
-- the button is for.
--
-- The window makes room for it rather than giving it the content's room. While it is up the content stops short of it and
-- the window is that much taller, its top edge staying where it was so that only the bottom moves, and the resize bounds are
-- raised by the same so that the user cannot drag the window back over it. Taking it down gives all of that back.
--
-- The button throws OnSave on the dialog. Saving is the caller's business, and so is taking the bar down after.
--
-- TD.SAVEBAR_BUTTON is the least width of the button, TD.SAVEBAR_JEWEL how many of the Separator's own lengths the jewel
-- is drawn across the top line.
--
TD.SAVEBAR_BUTTON = 300
TD.SAVEBAR_JEWEL = 1.5

local function build_savebar(frame, spec)
  local spec = spec or {}
  local bar = KUI:CreateInset({ name = frame:GetName() .. "SaveBar", parent = frame }, frame)
  local text = spec.text or K.SAVEBAR_STR
  local bw = max(TD.SAVEBAR_BUTTON, KUI:WidestString({ text }) + 8 * KUI.WIDGET_GAP)

  bar:Hide()

  -- The bar holds the button and nothing else. What saving means is the button's tooltip.
  bar.button = KUI:CreateButton({ x = "CENTER", y = 0, width = bw, height = 24, text = text,
    tooltip = { title = text, text = spec.message or K.SAVEBAR_MSG } }, bar)
  bar.button:Catch("OnClick", function(this, evt)
    local ps = frame.ShownPending and frame:ShownPending()

    -- Saving ends the edit, so the field being typed in lets go of the keyboard and its cursor.
    if (KIT.focused) then
      KIT.focused:ClearFocus()
    end

    if (ps) then
      ps:Save()
    end

    frame:Throw("OnSave")
  end)

  --
  -- The jewel: a short length of the Separator, its diamond on the middle of the rim's top line and a stone set in it. It is
  -- a frame of its own above the panel so that it lies over the rim rather than under it.
  --
  local jh = KUI.SEPARATOR_THICK
  local jewel = MakeFrame("Frame", nil, bar)

  jewel:SetSize(jh * KIT.def("Separator").aspect * TD.SAVEBAR_JEWEL, jh)
  jewel:SetPoint("CENTER", bar, "TOP", 0, 0 - KUI.INSET_PADDING - KUI.INSET_BORDER / 2)
  jewel:SetFrameLevel(bar:GetFrameLevel() + 2)
  bar.jewelart = KIT.new(jewel, "Separator", { layer = "ARTWORK" })
  bar.jewelart:SetBox(jewel, 0, 0, 0, 0, jh)
  bar.jewel = KIT.gem(bar.jewelart)

  -- The whole bar wears the colour a changed value is written in, which is what it is there to say.
  bar:SetTint(KUI.DEFAULT_CHANGED_COLOR)

  return bar
end

-- How tall the bar is: its button and the rings round it.
local function savebar_height(frame, bar)
  return bar.rings.top + 24 + bar.rings.bottom
end

function TD.IsSaveBarShown(this)
  return (this.savebar and this.savebar:IsShown()) and true or false
end

--
-- Stand the bar H tall across the foot of the content, or across its head under the top bar when ATTOP, and have the content
-- give up that much room on that side. H of 0 gives the content all of its room back.
--
local function place_savebar(this, h, attop)
  local bar = this.savebar
  local inset = this.inset
  local topgive = attop and h or 0
  local botgive = (not attop) and h or 0

  bar:ClearAllPoints()

  if (attop) then
    bar:SetPoint("TOPLEFT", this, "TOPLEFT", inset.left, 0 - inset.top)
    bar:SetPoint("TOPRIGHT", this, "TOPRIGHT", 0 - inset.right, 0 - inset.top)
  else
    bar:SetPoint("BOTTOMLEFT", this, "BOTTOMLEFT", inset.left, inset.bottom)
    bar:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 0 - inset.right, inset.bottom)
  end

  bar:SetHeight(h)

  this.content:SetPoint("TOPLEFT", this, "TOPLEFT", inset.left, 0 - inset.top - topgive)
  this.content:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 0 - inset.right, inset.bottom + botgive)
end

--
-- A dialog made with cfg.savebarreserved keeps the bar's room from the start: the bar is built and placed when the dialog is,
-- the content always stops short of it, and putting it up or taking it down only shows or hides it, nothing moving.
--
local function reserve_savebar(this, spec)
  this.savebar = build_savebar(this, spec)
  this.savebarheight = savebar_height(this, this.savebar)
  place_savebar(this, this.savebarheight, this.savebarlocation == "TOP")
end

--
-- Put the save bar up, or take it down. SPEC is read the first time only, and may give the button's text and the message.
--
function TD.SetSaveBar(this, onoff, spec)
  onoff = onoff and true or false

  if (onoff == this:IsSaveBarShown()) then
    return
  end

  --
  -- A dialog keeping the bar's room only shows or hides it, standing it at the offset the page or tab on show asks for,
  -- which is 0, the foot of the content, unless it keeps something of its own under the bar.
  --
  if (this.savebarreserved) then
    if (onoff) then
      local pg, tab = this:GetPage(), this:GetTab()
      local shown = tab or pg
      local off = (shown and shown.savebaroffset) or 0
      local inset = this.inset
      local bar = this.savebar

      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", this, "BOTTOMLEFT", inset.left, inset.bottom + off)
      bar:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 0 - inset.right, inset.bottom + off)
    end

    this.savebar:SetShown(onoff)
    return
  end

  this.savebar = this.savebar or build_savebar(this, spec)

  local bar = this.savebar
  local inset = this.inset
  local h = onoff and savebar_height(this, bar) or (this.savebarheight or 0)

  this.savebarheight = onoff and h or nil

  --
  -- The top edge stays where it is. A window anchored by its middle would grow at both ends, so it is anchored by its top left
  -- corner first, where it already is.
  --
  local top, left = this:GetTop(), this:GetLeft()

  if (top and left) then
    this:ClearAllPoints()
    this:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  end

  local grow = onoff and h or (0 - h)

  this:SetHeight(this:GetHeight() + grow)

  if (this.kuibounds) then
    local b = this.kuibounds
    local lift = onoff and h or 0

    this:SetResizeBounds(b[1], b[2] + lift, b[3], b[4] + lift)
  end

  --
  -- The bar across the foot of the content, or across its head under the top bar, as the dialog's savebarlocation says. The
  -- content gives up the room on that side only while the bar is up, and has all of it back on both sides once it is down.
  --
  place_savebar(this, onoff and h or 0, onoff and this.savebarlocation == "TOP")
  bar:SetShown(onoff)
end

--
-- A page's held edits, what drives the save bar. Nothing a page edits is written while it is being edited: each change is
-- held here, against the value that was saved when it was made, until the page is saved, and then the lot is handed to the
-- page's own save at once. A page, or a tab of one, makes one with ret:NewPending and the dialog keeps it under the page's
-- and tab's names, so that the save bar follows whichever is showing. It says how a key's saved value is read and how the
-- held ones are saved, and it watches its widgets, so that a widget whose value differs from what is saved is shown changed
-- (see BC.SetChanged) and goes back to its own when the two agree again.
--
-- What is held is a value that differs from what is saved. Setting a key back to its saved value is no change, and takes it
-- off the list. A change made elsewhere to a key that is held here replaces it: the saved value is kept beside each held
-- one, and a key whose saved value has moved since is dropped by Reconcile.
--
-- On a page with a selector the changes are to the one selected. Picking another throws them away, which is Pick's to do.
--
local PEND = {}

--
-- Whether two values are the same, tables being the same when every entry is. Settings hold tables of plain values only,
-- so one level is all there is.
--
local function pend_same(a, b)
  if (type(a) ~= "table" or type(b) ~= "table") then
    return a == b
  end

  for k, v in pairs(a) do
    if (b[k] ~= v) then
      return false
    end
  end

  for k, v in pairs(b) do
    if (a[k] ~= v) then
      return false
    end
  end

  return true
end

local function pend_copy(v)
  return (type(v) == "table") and K.CopyTable(v, {}) or v
end

--
-- The value KEY has on screen, held if it is held and saved otherwise. What a page's own rules, a widget enabled by
-- another's value, are decided on.
--
function PEND.Value(this, key)
  if (this.has[key]) then
    return this.pending[key]
  end

  return this.saved(key)
end

function PEND.Has(this, key)
  return this.has[key] and true or false
end

function PEND.Dirty(this)
  return next(this.has) ~= nil
end

-- An edit of KEY to VAL. The same as what is saved is no change at all.
function PEND.Set(this, key, val)
  local saved = this.saved(key)

  if (pend_same(val, saved)) then
    this.has[key] = nil
    this.pending[key] = nil
    this.base[key] = nil
  else
    if (not this.has[key]) then
      this.base[key] = pend_copy(saved)
    end

    this.has[key] = true
    this.pending[key] = pend_copy(val)
  end

  this:Paint()
  this.dialog:SyncPending()
end

--
-- WIDGET is shown as changed while any of the keys after it is held. A widget can stand for several keys, and one key can
-- have several widgets.
--
function PEND.Watch(this, widget, ...)
  this.watched[widget] = { ... }
  widget:SetChanged(false)
end

function PEND.Paint(this)
  for widget, keys in pairs(this.watched) do
    local on = false

    for _, key in ipairs(keys) do
      if (this.has[key]) then
        on = true
      end
    end

    widget:SetChanged(on)
  end
end

-- Throw every held change away. The page puts its widgets back from what is saved afterwards, which is its own business.
function PEND.Discard(this)
  this.pending = {}
  this.base = {}
  this.has = {}
  this:Paint()
  this.dialog:SyncPending()
end

--
-- On a page with a selector, the one thing the changes are to, by its id, or nil for none. Picking another throws the
-- changes away, and picking the same one again, which a refresh does, keeps them less what has since been replaced. The
-- page's saved and save read this.picked to know what they are about.
--
function PEND.Pick(this, id)
  if (this.holding) then
    this.heldpick = id
    return
  end

  if (this.picked ~= id) then
    this.picked = id
    this:Discard()
  else
    this:Reconcile()
  end
end

--
-- A refresh rebuilding a page's list deselects it and selects the same row again, and going by each of those would throw the
-- changes away on the way past. Between Hold and Release a pick is only noted, and Release acts on the last one, so a refresh
-- that ends where it began keeps them. A refresh that picks nothing at all leaves the pick where it was.
--
function PEND.Hold(this)
  this.holding = true
  this.heldpick = this.picked
end

function PEND.Release(this)
  local id = this.heldpick

  this.holding = nil
  this.heldpick = nil
  this:Pick(id)
end

--
-- Called when what is saved may have changed under the page. A key changed elsewhere since it was edited here takes that
-- value, and one whose saved value now agrees with the edit is no longer a change. True when anything was dropped.
--
function PEND.Reconcile(this)
  local dropped = false

  for key in pairs(this.has) do
    local saved = this.saved(key)

    if (not pend_same(saved, this.base[key]) or pend_same(saved, this.pending[key])) then
      this.has[key] = nil
      this.pending[key] = nil
      this.base[key] = nil
      dropped = true
    end
  end

  this:Paint()
  this.dialog:SyncPending()

  return dropped
end

-- Save the held changes, handed to the page's save as one table of key to value, and forget them.
function PEND.Save(this)
  if (not this:Dirty()) then
    return
  end

  local changes = {}

  for key in pairs(this.has) do
    changes[key] = pend_copy(this.pending[key])
  end

  this.pending = {}
  this.base = {}
  this.has = {}

  this.save(changes)
  this:Paint()
  this.dialog:SyncPending()
end

local function pend_key(pagename, tabname)
  return pagename .. "/" .. (tabname or "")
end

--
-- Make the held edits of page OPTS.page, or of its tab OPTS.tab. OPTS.saved(key) is a key's saved value, OPTS.save(changes)
-- writes a table of them, and OPTS.reload() puts the page's widgets back from what is saved.
--
-- The first one a dialog makes also has it put every page's changes away when it is hidden, which is what the save button's
-- tooltip says closing the window does.
--
function TD.NewPending(this, opts)
  local ps = {
    saved = opts.saved, save = opts.save, reload = opts.reload, page = opts.page, tab = opts.tab, dialog = this,
    pending = {}, base = {}, has = {}, watched = {},
  }

  for k, v in pairs(PEND) do
    ps[k] = v
  end

  if (not this.pendings) then
    this.pendings = {}
    this:HookScript("OnHide", function(self)
      self:DiscardPending()
    end)
  end

  this.pendings[pend_key(opts.page, opts.tab)] = ps

  return ps
end

-- The held edits of the page and tab on show, if that page keeps any.
function TD.ShownPending(this)
  local pg, tab = this:GetPage(), this:GetTab()

  if (not pg or not this.pendings) then
    return nil
  end

  return this.pendings[pend_key(pg.name, tab and tab.name)]
end

--
-- The save bar is up exactly while the page on show has held changes. A dialog that keeps no held edits is left to put its
-- bar up and down itself.
--
function TD.SyncPending(this)
  if (not this.pendings) then
    return
  end

  local ps = this:ShownPending()

  this:SetSaveBar(ps and ps:Dirty() or false)
end

-- Throw away every page's held changes, and have each page put its widgets back from what is saved.
function TD.DiscardPending(this)
  for _, ps in pairs(this.pendings or {}) do
    ps:Discard()

    if (ps.reload) then
      ps.reload()
    end
  end
end

function KUI:CreateTabbedDialog(cfg, kparent)
  local fname = cfg.name or("KUITabbedDlg"..self:GetWidgetNum("tabbeddialog"))
  local frame, parent, width, height = newobj(cfg, kparent, 512, 512, fname)

  if (parent == UIParent) then
    KIT.addwindow(frame)
  end

  frame:SetMovable(cfg.canmove and true or false)
  frame:EnableMouse(true)
  -- Over the game's panels, and under its dialogs and the kit's, which stand on it.
  frame:SetFrameStrata(cfg.strata or "HIGH")
  frame:Hide()

  local tspec = cfg.title

  if (type(tspec) ~= "table") then
    tspec = { text = tspec }
  end

  frame.maintitle = tspec.text or ""
  frame.onclick = cfg.onclick

  --
  -- The surface and the rim over it.
  --
  frame.ground = KIT.surface(frame)
  frame.groundlift = KIT.surface(frame, "BACKGROUND", -7)
  frame.groundlift:SetBlendMode("ADD")
  frame.groundlift:SetAlpha(TD.LIFT)

  local art = (type(cfg.innerart) == "string" and string.upper(cfg.innerart) == "FANCY") and TD.FANCY or TD.PLAIN
  local rim = KIT.new(frame, art.rim, { layer = "BORDER" })
  rim.scale = 1
  rim:SetFrameBox(frame, 0, 0, 0, 0)
  frame.rim = rim
  KIT.fitground(frame.ground, frame, rim)
  frame.groundlift:SetPoint("TOPLEFT", frame.ground, "TOPLEFT", 0, 0)
  frame.groundlift:SetPoint("TOPRIGHT", frame.ground, "TOPRIGHT", 0, 0)

  local re = rim.def.edge
  local rule = art.rule and KIT.new(frame, art.rule, { layer = "BORDER", sublevel = 4 }) or nil
  local ue = rule and rule.def.edge or { 0, 0, 0, 0 }

  --
  -- Where the content goes, which is inside the rim, the gap and any rule on every side, and on the top below the plaque and
  -- the top bar as well. The tips of the plaque's ends sit on the middle of the rim's top line, so what is below them hangs
  -- into the window and the content starts under it.
  --
  local plate = TITLE.plate(frame, { text = "", font = tspec.font, location = tspec.location }, "WINDOW", "TOP")
  local barTop = ceil(TITLE.reach(rim, plate))
  local inset = {
    left = ceil(re[1] + TD.GAP + ue[1]),
    right = ceil(re[2] + TD.GAP + ue[2]),
    top = barTop + TD.BAR + ceil(ue[3]),
    bottom = ceil(re[4] + TD.GAP + ue[4]),
  }
  frame.inset = inset
  frame.groundlift:SetHeight(inset.top - rim:groundinset())

  --
  -- The title. The plaque measures itself against its words every time they change, and the words change whenever a page or
  -- a tab is selected, since SetPage sets them by calling SetText on ret.title.
  --
  -- It is set into the top edge and takes only the three places along it, the bottom edge being the tray the page buttons
  -- stand in, so a location naming the bottom keeps its end and comes up here. Where it is hung is left until the portrait is
  -- built, a plaque at that end having to start clear of the portrait as well as of the corner.
  --
  plate:SetFrameLevel(frame:GetFrameLevel() + 6)
  frame.titleplate = plate
  frame.title = plate.text
  hooksecurefunc(plate.text, "SetText", function()
    TITLE.setwidth(plate, TITLE.measure(plate))
  end)

  --
  -- The addon's logo goes behind the portrait frame, filling its opening, so the frame's rim covers the logo's edge. The frame
  -- is the portrait part, which wears the window's accent, or cfg.portraitaccent when the caller gives it a colour of its own.
  -- Across, it stands where the point at the foot of its left corner comes down on the middle of the rim's left line (PX).
  --
  local ps = TD.PORTRAIT
  local portrait = KIT.new(frame, "WindowPortrait", { layer = "ARTWORK", part = "portrait",
    accent = KIT.colourof(cfg.portraitaccent) })
  local px = rim:frameline("LEFT") - TD.PORTRAIT_POINT * ps * portrait.def.aspect

  portrait.box:SetPoint("TOPLEFT", frame, "TOPLEFT", px, TD.PORTRAIT_ABOVE)
  portrait.box:SetSize(ps * portrait.def.aspect, ps)
  portrait:Layout()
  frame.portraitframe = portrait

  local ox, oy, hw, hh = portrait:opening()
  frame.portrait = frame:CreateTexture(nil, "BORDER", nil, 6)
  frame.portrait:SetPoint("CENTER", portrait.box, "CENTER", ox or 0, oy or 0)
  frame.portrait:SetSize((hw or ps) + 2, (hh or ps) + 2)

  --
  -- The plaque hung where it asked to be. Wherever along the edge that is, it is placed by its tips, which come out on the
  -- middle of the rim's line. A plaque at an end starts clear of whatever is there already, the corner at both ends and the
  -- portrait standing out over the left one.
  --
  TITLE.hangon(rim, plate, (plate.align == "LEFT") and (px + ps * portrait.def.aspect + rim:overhang("LEFT")) or nil)

  --
  -- cfg.tltexture and cfg.tltexcoord after the fact, for a window whose badge names something that changes under it. A
  -- texture with no coords is the whole of its file, and no texture at all is the dark corner a window with no logo wears,
  -- which is also how the badge is cleared.
  --
  frame.SetPortrait = function(this, texture, coords)
    if (texture) then
      this.portrait:SetTexture(texture)
      this.portrait:SetTexCoord(coords and coords[1] or 0, coords and coords[2] or 1,
        coords and coords[3] or 0, coords and coords[4] or 1)
    else
      this.portrait:SetTexCoord(0, 1, 0, 1)
      this.portrait:SetColorTexture(0, 0, 0, 1)
    end
  end

  frame:SetPortrait(cfg.tltexture, cfg.tltexcoord)

  --
  -- A texture cannot be clicked, so an invisible button is laid over the portrait and handed back for a caller that wants the
  -- corner to mean something. It throws OnDoubleClick, and OnClick with the mouse button for a caller that wants a click with a
  -- modifier held, a plain click on a window's own badge being best left meaning nothing.
  --
  local pb = MakeFrame("Button", nil, frame)
  pb:SetAllPoints(portrait.box)
  pb:EnableMouse(true)
  pb:RegisterForClicks("AnyUp")
  pb:SetFrameLevel(frame:GetFrameLevel() + 7)
  pb.events = {}
  pb.Catch = BC.Catch
  pb.Throw = BC.Throw
  pb:SetScript("OnClick", function(this, ...)
    this:Throw("OnClick", ...)
  end)
  pb:SetScript("OnDoubleClick", function(this, ...)
    this:Throw("OnDoubleClick", ...)
  end)
  frame.portraitbutton = pb

  frame.xbutton = KIT.closebutton(frame, -4, -4)

  --
  -- The band above the top bar is the drag handle, the whole width of the window.
  --
  local tframe = MakeFrame("Frame", nil, frame)

  tframe:EnableMouse(true)
  tframe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  tframe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  tframe:SetHeight(barTop)

  if (cfg.canmove) then
    tframe:SetScript("OnMouseDown", parent_StartMoving)
    tframe:SetScript("OnMouseUp", parent_StopMoving)
  end

  local seframe, swframe, soframe = make_resizeable(frame, 25, cfg.canresize)
  if (seframe) then
    -- Kept, so that the save bar can raise the heights by its own while it is up and give them back after.
    frame.kuibounds = { cfg.minwidth or 192, cfg.minheight or 192, cfg.maxwidth or 1024, cfg.maxheight or 1024 }
    frame:SetResizeBounds(frame.kuibounds[1], frame.kuibounds[2], frame.kuibounds[3], frame.kuibounds[4])

    --
    -- The grip's strokes run parallel to the rim's rounded corner and leave the bottom right of its box empty, so squared up
    -- against the content's corner it would stand well clear of the curve. It is pulled 8 into the corner each way instead,
    -- where it lies over the rim's bend.
    --
    local grip = KIT.new(seframe, "WindowGrip", { layer = "OVERLAY" })
    local gs = grip.def.draw
    grip.box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8 - inset.right, inset.bottom - 8)
    grip.box:SetSize(gs * grip.def.aspect, gs)
    grip:Layout()
    KIT.interactive(seframe, grip)

    --
    -- The grip reaches in past the rim, so the corner that takes the drag reaches in to cover it, and stands above the content
    -- that would otherwise take the click first.
    --
    seframe:ClearAllPoints()
    seframe:SetPoint("TOPLEFT", grip.box, "TOPLEFT", -2, 2)
    seframe:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
    seframe:SetFrameLevel(frame:GetFrameLevel() + 8)
  end

  --
  -- The content frame is the dialog's usable area and stays put whatever page or tab is showing. Every page's content is laid
  -- over the same rectangle, and ret.pagecontent is whichever of those, or of the current page's tabs, is on show.
  --
  frame.content = MakeFrame("Frame", fname .. "Content", frame)
  frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", inset.left, 0 - inset.top)
  frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - inset.right, inset.bottom)

  --
  -- The save bar's room, kept from the start when asked for, before any page is laid out in what is left. See TD.SetSaveBar.
  --
  frame.savebarlocation = (type(cfg.savebarlocation) == "string") and strupper(cfg.savebarlocation) or "BOTTOM"
  frame.savebarreserved = cfg.savebarreserved and true or false

  if (frame.savebarreserved) then
    reserve_savebar(frame, cfg.savebar)
  end

  if (rule) then
    rule.scale = 1
    rule:SetFrameBox(frame.content, 0 - ue[1], 0 - ue[3], 0 - ue[2], 0 - ue[4])
  end
  frame.rule = rule

  --
  -- cfg.blackbg blacks out everything below the top band, which reads better behind a screen that is mostly panels than the
  -- surface does. It runs from the top of the content down to the rim on three sides and on into the tray, so the page buttons
  -- stand on the same black as the pages. The band across the top keeps its surface.
  --
  if (cfg.blackbg) then
    local cbg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)

    cbg:SetPoint("TOPLEFT", frame.ground, "TOPLEFT", 0, rim:groundinset() - inset.top)
    cbg:SetPoint("BOTTOMRIGHT", frame.ground, "BOTTOMRIGHT", 0, 0)
    cbg:SetColorTexture(0, 0, 0, 1)
    frame.contentground = cbg
  end

  --
  -- The top bar, from clear of the portrait to the rim on the right, standing on the content.
  --
  frame.topbar = MakeFrame("Frame", fname .. "TopBar", frame)
  frame.topbar:SetPoint("TOPLEFT", frame, "TOPLEFT", ceil(px + ps) + TD.GAP, 0 - barTop)
  frame.topbar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0 - inset.right, 0 - barTop - TD.BAR)

  --
  -- The tray. The page buttons start as far in as the tray can begin clear of the bottom left corner, and the tray is fitted to
  -- them every time the strip is laid out, the rim's bottom edge giving up that stretch to it. The tray is part of the window,
  -- so the window's ground goes down into it too, the surface or the black of cfg.blackbg. The tips of the buttons' ends sit
  -- on the middle of the tray's floor line, which is the tray's depth below the rim's bottom edge less half the rim's weight
  -- and 2px higher again by eye, so their tops stand up into the tray.
  --
  if (KIT.has(art.tray)) then
    local tray = KIT.new(frame, art.tray, { layer = "BORDER", sublevel = 2 })
    local tth = tray.def.draw
    local tends = KIT.ends(tray, tth) / 2
    local bl = rim.def.bleed[1]
    local corner = rim.def.nine[1] * rim.def.draw * rim.def.aspect

    frame.traypiece = tray
    if (cfg.blackbg) then
      frame.trayground = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
      frame.trayground:SetColorTexture(0, 0, 0, 1)
    else
      frame.trayground = KIT.surface(frame)
    end
    frame.kuistripx = ceil(corner - bl + tends + TD.TRAY_PAD) + 2
    frame.kuistripy = (KIT.def(PAGE_STRIP.piece).point or 0.5) * PAGE_STRIP.height - tray.def.depth + re[4] / 2 + 2

    frame.kuitray = function(this, x0, x1)
      if (not x0) then
        rim:SetTray(nil)
        rim:Layout(rim.scale)
        tray:Hide()
        this.trayground:Hide()
        return
      end

      local f0, f1 = x0 - TD.TRAY_PAD, x1 + TD.TRAY_PAD

      rim:SetTray(f0 - tends + bl, f1 + tends + bl)
      rim:Layout(rim.scale)

      tray.box:ClearAllPoints()
      tray.box:SetPoint("BOTTOMLEFT", rim.box, "BOTTOMLEFT", f0 - tends + bl, 0)
      tray.box:SetSize(f1 - f0 + 2 * tends, tth)
      tray:Layout(tth)
      tray:Show()

      --
      -- The surface goes under the tray as far as its hole reaches into its ends, which is to the inside of each step, and up
      -- to meet the window's own, which stops short of the bottom edge by its ground inset.
      --
      local th = tray.def.hole
      local tw = tray.def.draw * tray.def.aspect
      local g0 = th and (f0 - tends + th[1] * tw) or f0
      local g1 = th and (f1 + tends - (1 - th[2]) * tw) or f1

      this.trayground:ClearAllPoints()
      this.trayground:SetPoint("TOPLEFT", this, "BOTTOMLEFT", g0, rim:groundinset())
      this.trayground:SetPoint("BOTTOMRIGHT", this, "BOTTOMLEFT", g1, 0 - tray.def.depth)
      this.trayground:Show()
    end

    frame:kuitray(nil)
  end

  if (cfg.escclose) then
    add_escclose(fname)
  end

  --
  -- Build every page named in the config, and every tab inside each of them. The config tables are keyed by name and pairs()
  -- does not promise an order, which is exactly why each entry carries an explicit "order" that we sort on afterwards.
  --
  frame.pages = {}
  frame.pagesbyname = {}
  frame.retired = {}
  frame.defpage = cfg.defpage

  for k, v in pairs(cfg.pages) do
    local pcfg = v
    pcfg.name = pcfg.name or k

    local pg = build_page(frame, pcfg)

    if (pcfg.tabs) then
      for kk, vv in pairs(pcfg.tabs) do
        local tcfg = vv
        tcfg.name = tcfg.name or kk

        local tab = build_tab(frame, pg, tcfg)
        tinsert(pg.tabs, tab)
        pg.tabsbyname[tab.name] = tab
      end

      tsort(pg.tabs, order_sorter)
      strip_relayout(pg.tabs, pg.topbar, TAB_STRIP)
    end

    tinsert(frame.pages, pg)
    frame.pagesbyname[pg.name] = pg
  end

  tsort(frame.pages, order_sorter)
  strip_relayout(frame.pages, frame, PAGE_STRIP)

  frame.SetTitleText = function(this, text)
    this.titletext = text or ""
    this.title:SetText(this.titletext)
  end

  frame.SetSaveBar = TD.SetSaveBar
  frame.IsSaveBarShown = TD.IsSaveBarShown
  frame.NewPending = TD.NewPending
  frame.ShownPending = TD.ShownPending
  frame.SyncPending = TD.SyncPending
  frame.DiscardPending = TD.DiscardPending
  frame.SetPage = TD.SetPage
  frame.SetTab = TD.SetTab
  frame.GetPage = TD.GetPage
  frame.GetTab = TD.GetTab
  frame.SetPageTitle = TD.SetPageTitle
  frame.SetPageShown = TD.SetPageShown
  frame.IsPageShown = TD.IsPageShown
  frame.SetTabShown = TD.SetTabShown
  frame.AddPage = TD.AddPage
  frame.RemovePage = TD.RemovePage
  frame.AddTab = TD.AddTab
  frame.RemoveTab = TD.RemoveTab

  frame:SetPage(cfg.defpage)

  return frame
end

--
-- This function is used to set the current item in a list. It is called from several places. First, when a list is being
-- updated with new items it is called with a nil offset to disable any current selection. This is because the current
-- selection may no longer be valid after the list is updated. Thus it is the caller's responsibility to remember any current
-- position if restoring the current selection is important. Second, it is called when a list item is clicked. It is not
-- called directly, but through the containing list's :SetSelected() method. The default helper functions do this correctly
-- but if the code implements its own newitem method, it must set the OnClick handler to call the :SetSelected() method itself.
--
-- When a new offset is selected, this code ensures that the previously selected entry has its highlight removed and its
-- deselection routine run. It then highlights the new entry, and runs its selection method. Thus all of the logic for
-- dealing with the selection is here in this function.
--
function SL.setsel(objp, offset, force)
  local i
  local nslot = nil
  local nbtn = nil
  local ro

  if (offset and (offset > objp.itemcount or offset <= 0)) then
    offset = nil
  end

  if (objp.selecteditem) then
    --
    -- We have a currently selected item. If the new offset is not the same as the current selection, we need to remove the
    -- highlight, and run the current selected items deselection function.
    --
    local cslot = nil
    local cbtn = nil
    for i = 1, objp.visibleslots do
      ro = i + objp.offset
      if (ro == objp.selecteditem) then
        cslot = i
        cbtn = objp.slots[i]
      end
      if (offset and ro == offset) then
        nslot = i
        nbtn = objp.slots[i]
      end
    end
    if (objp.selecteditem ~= offset) then
      --
      -- The new offset is not the same as the current. If the current one is being displayed at the moment, remove its highlight.
      --
      if (cslot) then
        objp:highlightitem(objp.selecteditem, cslot, cbtn, false)
      end
      -- And run its deselection function
      objp:selectitem(objp.selecteditem, cslot, cbtn, false)
    else
      if (force) then
        objp:selectitem(objp.selecteditem, cslot, cbtn, true)
      end
      return
    end
  end

  if (offset and not nslot) then
    for i = 1, objp.visibleslots do
      ro = i + objp.offset
      if (ro == offset) then
        nslot = i
        nbtn = objp.slots[i]
        break
      end
    end
  end

  objp.selecteditem = offset
  if (offset) then
    --
    -- If we have a new offset and it would be visible, turn on its highlight and run its selection function. If it wouldnt
    -- be visible just run the selection function.
    --
    if (nbtn) then
      objp:highlightitem(offset, nslot, nbtn, true)
    end
    objp:selectitem(offset, nslot, nbtn, true)
  else
    --
    -- No offset, we're setting the offset to nil. No need to deal with any highlights here, just call the selection function appropriately.
    --
    objp:selectitem(nil, nil, nil, nil)
  end
end

function SL.setrem_highlight(objp, onoff)
  local onoff = onoff or false

  if (not objp.selecteditem) then
    return
  end

  local i, ro
  local sel = objp.selecteditem
  for i = 1, objp.visibleslots do
    ro = i + objp.offset
    if (ro == sel) then
      objp:highlightitem(ro, i, objp.slots[i], onoff)
      return
    end
  end
end

--
-- How many visual elements a list needs. A list that scrolls by whole items needs only as many as fit; one that scrolls
-- smoothly needs one more, because at every position but the top there is a part of an item showing at each end.
--
--
-- A CHECK LIST
--
-- A list made with cfg.itemcheck gives every item a box of its own, CHECK_SIZES big, in a strip down the list's left or
-- right (cfg.checkpos) inside the list itself, CHECK_GAP clear of the item, the items standing in from that side to make
-- room. The list is a scroll frame and cuts off whatever its rows hang outside it, which is why the strip is the list's.
-- Each box is its item's slot's own, so it comes and goes with the slot.
--
-- Whether an item is ticked is the caller's where it answers cfg.ischecked, and the list's own by item otherwise. A tick
-- that changes, by a click or by the list's own functions, throws OnItemChecked with the item, whether it is now ticked and
-- whether a player did it, and nothing is thrown for a tick set to what it already was. Each box can be shown or hidden,
-- lit or dark, one by one by item or all at once, a word for one item standing over the word for them all until the next
-- word for them all. The strip is there whether the boxes are shown or not, so the items stay put as they come and go.
--
SL.CHECK_SIZES = { TINY = 10, SMALL = 12, NORMAL = KUI.CHECKBOX_SIZE }
SL.CHECK_GAP = KUI.WIDGET_GAP

--
-- A LIST IN A WELL
--
-- A list made with cfg.well sits sunk into what it stands on: a rim of the panel's art WELL_RIM thick, as dim as a scroll bar
-- (KIT.SCROLL_STATES), round a ground of black at WELL_GROUND laid over the parent's own, and the rows, their boxes and the
-- bar WELL_INSET in from the parent's edges, which leaves WELL_INSET less the rim between them and the rim.
--
SL.WELL_RIM = 2
SL.WELL_RIM_END = 1
SL.WELL_INSET = SL.WELL_RIM + 2
SL.WELL_GROUND = 0.35

-- Whether ITEM's box is shown, or lit, from the word for it alone in OVER and the word for them all, ALL.
function SL.itemflag(over, all, item)
  local v = over[item]

  if (v == nil) then
    return all
  end

  return v
end

-- How far the items stand in from SIDE for the strip.
function SL.checkinset(objp, side)
  if (objp.checksize and objp.checkpos == side) then
    return objp.checksize + SL.CHECK_GAP
  end

  return 0
end

-- The first slot, which every other follows down the list, in from whichever side the strip is on.
function SL.placefirst(objp)
  local s = objp.slots[1]

  if (s) then
    local y = objp.smoothscroll and (objp.pixeloffset or 0) or 0

    s:SetPoint("TOPLEFT", objp, "TOPLEFT", SL.checkinset(objp, "LEFT"), y)
    s:SetPoint("TOPRIGHT", objp, "TOPRIGHT", 0 - SL.checkinset(objp, "RIGHT"), y)
  end
end

function SL.makecheck(objp, slot)
  if (not objp.checksize) then
    return
  end

  local box = KUI:CreateCheckBox({ x = 0, y = 0, height = objp.checksize }, slot)

  box:ClearAllPoints()

  if (objp.checkpos == "RIGHT") then
    box:SetPoint("LEFT", slot, "RIGHT", SL.CHECK_GAP, 0)
  else
    box:SetPoint("RIGHT", slot, "LEFT", 0 - SL.CHECK_GAP, 0)
  end

  box:Catch("OnValueChanged", function(this, evt, onoff, user)
    if (user) then
      SL.setcheck(objp, slot:GetID(), onoff, true)
    end
  end)

  slot.kuicheck = box
end

function SL.checked(objp, item)
  if (objp.ischecked) then
    return objp.ischecked(objp, item) and true or false
  end

  return objp.checks[item] and true or false
end

function SL.paintcheck(objp, slot, item)
  local box = slot.kuicheck

  if (box) then
    box:SetShown(SL.itemflag(objp.checkshow, objp.checkshown, item))
    box:SetEnabled((objp.enabled and SL.itemflag(objp.checkenable, objp.checkenabled, item)) and true or false)
    box:SetChecked(SL.checked(objp, item))
  end
end

function SL.paintchecks(objp)
  for i = 1, objp.visibleslots or 0 do
    local slot = objp.slots[i]

    if (slot and slot:IsShown()) then
      SL.paintcheck(objp, slot, slot:GetID())
    end
  end
end

function SL.setcheck(objp, item, onoff, user)
  onoff = onoff and true or false

  if (SL.checked(objp, item) ~= onoff) then
    if (not objp.ischecked) then
      objp.checks[item] = onoff or nil
    end

    objp:Throw("OnItemChecked", item, onoff, user and true or false)
  end

  SL.paintchecks(objp)
end

-- Every item whose box is shown and lit ticked, or not, each that changes throwing as it does.
function SL.allchecks(objp, onoff)
  onoff = onoff and true or false

  for item = 1, objp.itemcount or 0 do
    if (SL.itemflag(objp.checkshow, objp.checkshown, item) and SL.itemflag(objp.checkenable, objp.checkenabled, item)
      and SL.checked(objp, item) ~= onoff) then
      if (not objp.ischecked) then
        objp.checks[item] = onoff or nil
      end

      objp:Throw("OnItemChecked", item, onoff, false)
    end
  end

  SL.paintchecks(objp)
end

--
-- Say whether ITEM's box, or every box where ITEM is nil, is shown or lit: OVER names the words for one item, checkshow or
-- checkenable, and ALL the word for them all, checkshown or checkenabled.
--
function SL.checkword(objp, over, all, item, onoff)
  onoff = onoff and true or false

  if (item == nil) then
    objp[all] = onoff
    objp[over] = {}
  else
    objp[over][item] = onoff
  end

  SL.placefirst(objp)
  SL.paintchecks(objp)
end

--
-- How many whole items the list shows. The game hands a height back through the UI scale, so a list made exactly five rows
-- high can say it is a hair short of that, and half a pixel of slack keeps the fifth.
--
function SL.slotcount(objp)
  local n = floor((objp:GetHeight() + 0.5) / objp.itemheight)

  if (objp.smoothscroll) then
    n = n + 1
  end

  return n
end

function SL.vertscroll(objp, offset)
  SL.setrem_highlight(objp, false)
  local sb = objp.scrollbar
  local sel = objp.selecteditem

  --
  -- No more than have been made. A list that has grown gets its new slots from SL.updatevals, which may not have run yet.
  --
  objp.visibleslots = min(SL.slotcount(objp), objp.numslots)

  --
  -- Scrolling by whole items stops when the last item is in the bottom slot; scrolling smoothly stops when the bottom of the
  -- last item reaches the bottom of the list, which is a little further and is what lets the final part item be brought fully into view.
  --
  local maxoffs

  if (objp.smoothscroll) then
    maxoffs = (objp.itemcount * objp.itemheight) - objp:GetHeight()
  else
    maxoffs = (objp.itemcount - objp.visibleslots) * objp.itemheight
  end

  maxoffs = max(maxoffs, 0)

  if (offset ~= nil) then
    if (offset < 0) then
      offset = 0
    elseif (offset > maxoffs) then
      offset = maxoffs
    end
    sb:SetValue(offset)

    --
    -- The item offset is which item is at the top. Scrolling smoothly keeps the leftover pixels as well, and the slots are
    -- shifted up by that much so the top item is cut off rather than snapped away.
    --
    if (objp.smoothscroll) then
      objp.offset = floor(offset / objp.itemheight)
      objp.pixeloffset = offset - (objp.offset * objp.itemheight)
    else
      objp.offset = floor((offset / objp.itemheight) + 0.5)
    end
  end

  if (maxoffs <= 0) then
    objp.offset = 0
    objp.pixeloffset = 0
    sb:SetValue(0)
  end

  if (objp.smoothscroll and objp.slots[1]) then
    objp.slots[1]:SetPoint("TOPLEFT", objp, "TOPLEFT", SL.checkinset(objp, "LEFT"),
      objp.pixeloffset or 0)
  end

  for i = 1, objp.visibleslots do
    local ro = i + objp.offset

    if (ro > objp.itemcount) then
      objp.slots[i]:Hide()
    else
      objp.slots[i]:Show()
      objp.slots[i]:SetID(ro)
      objp:setitem(ro, i, objp.slots[i])
      SL.paintcheck(objp, objp.slots[i], ro)
    end
  end

  if (objp:IsShown()) then
    local sch = 0

    if (objp.itemcount > 0) then
      objp.content:Show()
      sch = objp.itemcount * objp.itemheight
    else
      objp.content:Hide()
    end

    sb:SetMinMaxValues(0, maxoffs)
    sb:SetValueStep(objp.smoothscroll and 1 or objp.itemheight)
    objp.content:SetHeight(sch)

    -- OFFSET counts items and MAXOFFS pixels.
    local maxitem = floor(maxoffs / objp.itemheight)

    if (objp.offset > maxitem) then
      objp.offset = maxitem
      sb:SetValue(maxoffs)
    end

  end
  SL.setrem_highlight(objp, true)
end

function SL.updatevals(objp)
  SL.setrem_highlight(objp, false)
  local dispheight = objp:GetHeight()
  local fullheight = objp.content:GetHeight()
  local numvisible = SL.slotcount(objp)
  local desiredheight = objp.itemcount * objp.itemheight
  local rslot = nil
  local rbtn = nil

  if (numvisible > objp.numslots) then
    for i = objp.numslots+1, numvisible do
      --
      -- A row runs the width of the list, whatever width newitem made it, so that it neither stops short of the list's
      -- right edge nor runs on under the strip kept for the scrollbar and is cut off there.
      --
      objp.slots[i] = objp.newitem(objp, i)
      if (i == 1) then
        SL.placefirst(objp)
      else
        objp.slots[i]:SetPoint("TOPLEFT", objp.slots[i-1], "BOTTOMLEFT", 0, 0)
        objp.slots[i]:SetPoint("TOPRIGHT", objp.slots[i-1], "BOTTOMRIGHT", 0, 0)
      end
      SL.makecheck(objp, objp.slots[i])
      objp.slots[i]:Hide()
      if (not objp.enabled) then
        objp.slots[i]:EnableMouse(false)
      end
    end
    objp.numslots = numvisible
  end

  for i = 1, numvisible do
    local ro = i + objp.offset
    if (ro <= objp.itemcount) then
      objp.slots[i]:Show()
      objp.slots[i]:SetID(ro)
      objp:setitem(ro, i, objp.slots[i])
      SL.paintcheck(objp, objp.slots[i], ro)
      if (ro == objp.selecteditem) then
        rslot = i
        rbtn = objp.slots[i]
      end
    end
  end

  for i = numvisible+1, objp.numslots do
    objp.slots[i]:Hide()
  end

  objp.content:SetHeight(desiredheight)
  objp.visibleslots = numvisible

  --
  -- Scrolling smoothly has a slot more than fits, so counting slots would say there is nothing to scroll while the last item
  -- is still half off the bottom. What matters is whether the items are taller than the list.
  --
  local needbar

  if (objp.smoothscroll) then
    needbar = desiredheight > dispheight
  else
    needbar = numvisible < objp.itemcount
  end

  if (needbar) then
    objp.scrollbar:SetShown(objp.showbar)
    objp.scrollbar:SetValue(objp.scrollbar:GetValue() or 0)
  else
    objp.scrollbar:Hide()
  end

  SL.setrem_highlight(objp, true)
  return rslot, rbtn
end

local function item_widget(tbf)
  local ti = tbf.iinfo
  local cfg = {}
  local ret

  cfg.checked = tbf.checked
  cfg.enabled = tbf.enabled
  cfg.x = ti.x or 0
  cfg.y = ti.y or 0
  cfg.width = ti.width
  cfg.height = ti.height
  cfg.initialvalue = ti.initialvalue
  if (ti.label) then
    cfg.label = { text = ti.label, color = tbf.color, font = tbf.font }
  end

  if (ti.widget == "radio") then
    assert(ti.group, "must provide group name for radio items")
    cfg.group = ti.group
    cfg.value = ti.value
    cfg.groupparent = tbf.rparent
    cfg.getbutton = RADIO.getbutton
    tbf.checkable = false
    cfg.checked = tbf.checked
    ret = KUI:CreateRadioButton(cfg, tbf)
  elseif (ti.widget == "slider") then
    local dw, dh, xw, xh
    cfg.orientation = ti.orientation or "VERTICAL"
    if (cfg.orientation == "VERTICAL") then
      dw = 16
      dh = 100
      xw = 50
      xh = 0
    else
      dw = 100
      dh = 16
      xw = 0
      xh = 16
    end
    cfg.editfont = ti.editfont
    cfg.editcolor = ti.editcolor or {r = 1, g = 1, b = 0 }
    cfg.minmaxfont = ti.minmaxfont
    cfg.minmaxcolor = ti.minmaxcolor or {r = 0, g = 1, b = 0 }
    cfg.minval = ti.minval
    cfg.maxval = ti.maxval
    cfg.step = ti.step
    cfg.width = ti.width or dw
    cfg.height = ti.height or dh
    tbf.height = cfg.height + xh
    tbf.width = cfg.width + xw
    tbf.checkable = false
    ret = KUI:CreateSlider(cfg, tbf)
    ret.editbox.toplevel = tbf.toplevel
    ret.editbox:HookScript("OnEnter", TL.OnEnter)
    ret.editbox:HookScript("OnLeave", TL.OnLeave)
  elseif (ti.widget == "editbox") then
    cfg.len = ti.len
    cfg.numeric = ti.numeric
    cfg.font = ti.font and tbf.font or nil
    cfg.color = tbf.color
    cfg.label = nil
    cfg.width = ti.width or 100
    cfg.height = ti.height or 24
    tbf.height = cfg.height
    tbf.width = cfg.width
    tbf.checkable = false
    ret = KUI:CreateEditBox(cfg, tbf)
    ret:SetTextInsets(0, 0, 5, 1)
  elseif (ti.widget == "button") then
    cfg.text = ti.label
    cfg.width = ti.width or 100
    cfg.height = ti.height or 24
    tbf.height = cfg.height
    tbf.width = cfg.width
    tbf.checkable = false
    ret = KUI:CreateButton(cfg, tbf)
  else
    assert(false, "unknown or missing widget type")
  end

  ret.toplevel = tbf.toplevel
  ret.parent = tbf.parent
  ret:HookScript("OnEnter", TL.OnEnter)
  ret:HookScript("OnLeave", TL.OnLeave)
  return ret
end

--
-- A scroll bar: a slider WIDTH wide running in the kit's track, with its thumb and the gem set in the thumb, and an arrow
-- button off each end that scrolls half a bar's height. The buttons hang outside the slider, so the track is drawn from the
-- top of one to the bottom of the other. ret.upbutton and ret.downbutton are the buttons, lit whenever the list is, at
-- either end of it too. Every piece of it is drawn in KIT.SCROLL_STATES, a third darker than a button.
--
-- THUMB is how long the thumb is drawn, the thumb being a strip that stretches along the bar.
--
function KIT.arrow(sb, name)
  local b = MakeFrame("Button", nil, sb)
  local art = KIT.new(b, name, { layer = "ARTWORK", states = KIT.SCROLL_STATES })
  local w = sb:GetWidth()

  b:SetSize(w, w)
  art:SetBox(b)
  b.enabled = true
  hooksecurefunc(b, "Enable", function(this) this.enabled = true; KIT.sync(this) end)
  hooksecurefunc(b, "Disable", function(this) this.enabled = false; KIT.sync(this) end)
  KIT.interactive(b, art)
  return b
end

function KIT.scrollbar(parent, name, width, thumb)
  local sb = MakeFrame("Slider", name, parent)

  sb:SetOrientation("VERTICAL")
  sb:SetWidth(width)

  sb.upbutton = KIT.arrow(sb, "ScrollButtonUp")
  sb.upbutton:SetPoint("BOTTOM", sb, "TOP", 0, 0)
  sb.upbutton:SetScript("OnClick", function(this)
    local bar = this:GetParent()
    bar:SetValue(bar:GetValue() - (bar:GetHeight() / 2))
  end)

  sb.downbutton = KIT.arrow(sb, "ScrollButtonDown")
  sb.downbutton:SetPoint("TOP", sb, "BOTTOM", 0, 0)
  sb.downbutton:SetScript("OnClick", function(this)
    local bar = this:GetParent()
    bar:SetValue(bar:GetValue() + (bar:GetHeight() / 2))
  end)

  local track = KIT.new(sb, "ScrollTrack", { layer = "BACKGROUND", states = KIT.SCROLL_STATES })
  track.box:SetPoint("TOP", sb.upbutton, "TOP", 0, 0)
  track.box:SetPoint("BOTTOM", sb.downbutton, "BOTTOM", 0, 0)
  track.box:SetWidth(width)
  track:Layout(width)
  sb.track = track

  --
  -- The engine moves the thumb texture, so the thumb is drawn in pieces anchored to it and the texture itself draws nothing.
  --
  sb:SetThumbTexture(KIT.sheet())
  local tt = sb:GetThumbTexture()
  local tw = width - 2
  local tl = thumb or (tw * 2)

  tt:SetSize(tw, tl)
  tt:SetAlpha(0)

  local rim = KIT.new(sb, "ScrollThumbVertical", { layer = "ARTWORK", sublevel = 2, states = KIT.SCROLL_STATES })
  rim.box:SetAllPoints(tt)
  rim:Layout(tw)

  --
  -- The gem is as wide as the thumb's opening and as tall as its own shape makes it, no taller than the thumb has room for.
  --
  local gd = KIT.def("ScrollThumbVerticalGem")
  local hole = rim.def.hole
  local gw = tw * (hole and (1 - 2 * hole[1]) or 0.6) * 1.15
  local gh = min(gw / gd.aspect, tl * 0.8)
  local gem = KIT.new(sb, "ScrollThumbVerticalGem", { layer = "ARTWORK", sublevel = -2, flat = true, part = "gem",
    states = KIT.SCROLL_STATES })
  gem.box:SetPoint("CENTER", tt, "CENTER", 0, 0)
  gem.box:SetSize(gh * gd.aspect, gh)
  gem:Layout()

  sb.thumbrim = rim
  KIT.interactive(sb, rim, gem)
  return sb
end

--
-- A disabled scroll list or scroll frame cannot be scrolled: its bar, the bar's arrows and the mouse wheel stop.
--
function KIT.scrollenable(this, onoff)
  local sb = this.scrollbar

  this.enabled = onoff
  this:EnableMouseWheel(onoff)
  sb:EnableMouseWheel(onoff)
  sb:EnableMouse(onoff)
  sb.enabled = onoff
  KIT.sync(sb)

  --
  -- The arrows go with the list. At either end one has nowhere to go and pressing it does nothing, but it stays lit: an
  -- arrow gone dark at the end of a list reads as a list that cannot be scrolled at all.
  --
  for _, b in ipairs({ sb.upbutton, sb.downbutton }) do
    if (onoff) then
      b:Enable()
    else
      b:Disable()
    end
  end
end

--
-- A disabled scroll list cannot be clicked either: its rows stop taking the mouse, the rows made later as the list grows
-- included. What it shows is left as it is.
--
function KIT.slistenable(this, event, onoff)
  onoff = onoff and true or false
  KIT.scrollenable(this, onoff)

  for _, slot in ipairs(this.slots) do
    slot:EnableMouse(onoff)
  end

  -- A check list's boxes go dark with it and come back as each item says.
  SL.paintchecks(this)
end

--
-- Please note that this element type completely fills the parent frame, and that the width and height config elements are
-- ignored. If you require a specific size, ensure that the parent specified is of the correct size.
--

function KUI:CreateScrollList(cfg, kparent)
  local x = self:GetWidgetNum("scrolllist")
  local fname = cfg.name or ("KUIScrollList" .. x)
  local frame, parent, width, height = newobj(cfg, kparent, 0, 0, fname, "ScrollFrame")
  local sname = "KUIScrollBar" .. self:GetWidgetNum("scrollbar")
  local scrollbar = KIT.scrollbar(frame, sname, KUI.SCROLLBAR_WIDTH)
  local content = MakeFrame("Frame", nil, frame)

  assert(cfg.newitem)
  assert(cfg.setitem)
  assert(cfg.selectitem)
  assert(cfg.highlightitem)
  -- Rows are counted by dividing by it, and the game's Lua raises "Division by zero" where a sim would quietly get inf.
  assert((tonumber(cfg.itemheight) or 0) > 0, "a scroll list must have a row height above 0")

  scrollbar:SetScript("OnValueChanged", function(this, value)
    this:GetParent():SetVerticalScroll(value)
  end)

  frame.scrollbar = scrollbar
  frame.offset = 0
  frame.content = content
  frame.enabled = true
  frame.OnEnable = KIT.slistenable

  --
  -- How the rows mark the pointer and the selection, read by every row made in this list. See KIT.rowstyle.
  --
  frame.kuihighlight = cfg.highlight and string.upper(cfg.highlight) or nil
  frame.kuihighlightcolour = KIT.colourof(cfg.highlightcolour)

  --
  -- Held one clear of the left edge so that a selected row's highlight does not sit flush against whatever the list is
  -- inside, and SCROLLBAR_COMPENSATE clear on the right for the scrollbar, which lives in that strip. A list without a bar
  -- keeps no strip and runs to the parent's right edge. The bar is still made, hidden, because it holds where the list is
  -- scrolled to and the wheel moves it.
  --
  --
  -- A list scrolling smoothly runs to the parent's foot, a part item showing there. One scrolling whole rows is as many of
  -- them as the parent's height holds and no more, so that it never ends in a gap too short for a row, and it is cut again
  -- whenever the parent changes height. What it leaves over is below it, in the parent.
  --
  assert(cfg.scrollstyle == nil or cfg.scrollstyle == "rows" or cfg.scrollstyle == "smooth",
    "a scroll list's scrollstyle is \"rows\" or \"smooth\"")

  local showbar = true

  if (cfg.scrollbar ~= nil) then
    showbar = cfg.scrollbar and true or false
  end

  local strip = showbar and KUI.SCROLLBAR_COMPENSATE or 0

  --
  -- A list in a well (cfg.well) stands WELL_INSET in from the parent on every side, rows, boxes and bar alike, inside a thin
  -- dim rim round a ground darker than what the parent stands on. The well is drawn on the parent, under the list, and runs
  -- from the parent's top to WELL_INSET past the list's foot, so that it hugs a list of whole rows.
  --
  local wi = cfg.well and SL.WELL_INSET or 0

  frame.showbar = showbar
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", cfg.well and wi or 1, 0 - wi)

  if (cfg.scrollstyle == "smooth") then
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 - strip - wi, wi)
  else
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0 - strip - wi, 0 - wi)

    local function fit_rows()
      frame:SetHeight(max(floor(((parent:GetHeight() or 0) - wi - wi) / cfg.itemheight) * cfg.itemheight, 1))
    end

    parent:HookScript("OnSizeChanged", fit_rows)
    fit_rows()
  end

  if (cfg.well) then
    local box = parent:CreateTexture(nil, "BACKGROUND")
    local rim = KIT.border(parent, "PanelBorder", SL.WELL_RIM, { layer = "BORDER", states = KIT.SCROLL_STATES })
    local ground = parent:CreateTexture(nil, "BACKGROUND")

    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    box:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    box:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0 - wi)
    -- The rim's top and bottom lines stand in by WELL_RIM_END, closer to the rows than its sides are to theirs.
    rim:SetFrameBox(box, 0, SL.WELL_RIM_END, 0, SL.WELL_RIM_END)
    ground:SetColorTexture(0, 0, 0, SL.WELL_GROUND)
    KIT.fitground(ground, box, rim, 0, SL.WELL_RIM_END, 0, SL.WELL_RIM_END)
    frame.wellrim = rim
    frame.wellground = ground
  end

  frame:SetScrollChild(content)
  frame:EnableMouseWheel(true)
  scrollbar:EnableMouseWheel(true)

  --
  -- itemheight is the height of each individual item in the list. newitem is a function that is called to create a new item
  -- slot when the window size changes and the code needs a new item to display a list entry. This code will only ever create
  -- more item slots, it will never reduce them, so the maximum number of slots is always the largest the window has ever
  -- been. If the window is shrunk, there will be excess item slots that simply go unused.
  --
  -- setitem is called to set an individual item in the list. It is passed the real index (from list item 1) as well as the
  -- slot index and the return value from newitem() for that slot.
  --
  frame.itemheight = cfg.itemheight
  frame.newitem = cfg.newitem
  frame.setitem = cfg.setitem
  frame.selectitem = cfg.selectitem
  frame.highlightitem = cfg.highlightitem
  frame.smoothscroll = (cfg.scrollstyle == "smooth")
  frame.slots = {}
  frame.numslots = 0
  frame.visibleslots = 0
  frame.itemcount = 0
  frame.pixeloffset = 0

  --
  -- A check list's boxes, beside the items and outside their highlight (A CHECK LIST).
  --
  local itemcheck = string.upper(cfg.itemcheck or "NONE")
  local checkpos = string.upper(cfg.checkpos or "LEFT")

  assert(itemcheck == "NONE" or SL.CHECK_SIZES[itemcheck],
    "a scroll list's itemcheck is \"TINY\", \"SMALL\", \"NORMAL\" or \"NONE\"")
  assert(checkpos == "LEFT" or checkpos == "RIGHT", "a scroll list's checkpos is \"LEFT\" or \"RIGHT\"")

  frame.checksize = SL.CHECK_SIZES[itemcheck]
  frame.checkpos = checkpos
  frame.ischecked = cfg.ischecked
  frame.checks = {}
  frame.checkshown = true
  frame.checkenabled = true
  frame.checkshow = {}
  frame.checkenable = {}

  frame.CheckAll = function(this) SL.allchecks(this, true) end
  frame.UncheckAll = function(this) SL.allchecks(this, false) end
  frame.SetCheckedAll = function(this, onoff) SL.allchecks(this, onoff) end
  frame.SetItemChecked = function(this, item, onoff) SL.setcheck(this, item, onoff, false) end
  frame.GetItemChecked = function(this, item) return SL.checked(this, item) end
  frame.ShowItemCheck = function(this, item) SL.checkword(this, "checkshow", "checkshown", item, true) end
  frame.HideItemCheck = function(this, item) SL.checkword(this, "checkshow", "checkshown", item, false) end
  frame.EnableItemCheck = function(this, item) SL.checkword(this, "checkenable", "checkenabled", item, true) end
  frame.DisableItemCheck = function(this, item) SL.checkword(this, "checkenable", "checkenabled", item, false) end
  frame.RefreshChecks = function(this) SL.paintchecks(this) end
  frame.CheckStrip = function(this) return this.checksize and (this.checksize + SL.CHECK_GAP) or 0 end

  --
  -- Whether the bar is wanted is decided in SL.updatevals, which only runs on UpdateList. A list is built empty and may
  -- never be updated at all, so it starts with the bar hidden: an empty list wearing a scroll bar is a lie about having something to scroll to.
  --
  scrollbar:Hide()

  --
  -- Half the bar's height is half a page, which reads as a page turn on a list of text rows. A list that scrolls smoothly is
  -- one whose items are big, so a notch there moves half an item and the movement can be seen.
  --
  frame:HookScript("OnMouseWheel", function(self, delta)
    local sb = self.scrollbar
    local step = sb:GetHeight() / 2

    if (self.smoothscroll) then
      step = self.itemheight / 2
    end

    if (delta > 0) then
      sb:SetValue(sb:GetValue() - step)
    else
      sb:SetValue(sb:GetValue() + step)
    end
  end)

  scrollbar:HookScript("OnMouseWheel", function(self, delta)
    if (delta > 0) then
      self:SetValue(self:GetValue() - (self:GetHeight() / 2))
    else
      self:SetValue(self:GetValue() + (self:GetHeight() / 2))
    end
  end)

  frame:HookScript("OnSizeChanged", function(this, w, h)
    if (this.ever_updated) then
      SL.updatevals(this)
      SL.vertscroll(this, nil)
    end
  end)

  frame:HookScript("OnVerticalScroll", function(this, offset)
    SL.vertscroll(this, offset)
  end)

  content:ClearAllPoints()
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  --
  -- The bar fills the strip against the parent's right edge, with its arrow buttons inside the strip at each end.
  --
  local gap = KUI.SCROLLBAR_COMPENSATE - KUI.SCROLLBAR_WIDTH

  scrollbar:ClearAllPoints()
  scrollbar:SetPoint("TOPLEFT", frame, "TOPRIGHT", gap, 0 - KUI.SCROLLBAR_WIDTH)
  scrollbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", gap, KUI.SCROLLBAR_WIDTH)

  frame.UpdateList = function(this)
    this.ever_updated = true
    this.selecteditem = nil
    for i = 1, this.visibleslots do
      this.highlightitem(this, nil, 1, this.slots[i], false)
    end
    SL.setsel(this, nil, false)
    SL.updatevals(this)
    SL.vertscroll(this, nil)
  end

  --
  -- DISPLAY scrolls the item into view only when it is not wholly in view already, so that reselecting what the user is
  -- looking at, which every refresh does, leaves the list where they put it.
  --
  frame.SetSelected = function(this, offset, display, force)
    SL.setsel(this, offset, force)
    if (display and offset) then
      local top = (offset - 1) * this.itemheight
      local cur = this.scrollbar:GetValue() or 0
      local shown = this.smoothscroll and this:GetHeight() or (SL.slotcount(this) * this.itemheight)

      if (top < cur or top + this.itemheight > cur + shown) then
        SL.vertscroll(this, top)
      end
    end
  end

  frame.GetSelected = function(this)
    return this.selecteditem
  end

  return frame
end

--
-- A scroll frame: a canvas taller than the view onto it, for what is not rows of one height. The caller builds on ret.canvas
-- and says how tall that came to with ret:SetCanvasHeight, and the frame scrolls it by the pixel under the kit's bar. It sits
-- in its parent exactly as a scroll list does, filling it but for a pixel on the left and the strip its bar stands in on the
-- right, and it wears the bar only while there is more than fits.
--
-- The furthest it scrolls is worked out here from the two heights rather than asked of the game, which works its own out a
-- frame after the canvas changes size and would in between hold the view somewhere the canvas no longer reaches.
--
function KUI:CreateScrollFrame(cfg, kparent)
  local fname = cfg.name or ("KUIScrollFrame" .. self:GetWidgetNum("scrollframe"))
  local frame, parent = newobj(cfg, kparent, 0, 0, fname, "ScrollFrame")
  local scrollbar = KIT.scrollbar(frame, "KUIScrollBar" .. self:GetWidgetNum("scrollbar"), KUI.SCROLLBAR_WIDTH)
  local canvas = MakeFrame("Frame", nil, frame)

  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, 0)
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 - KUI.SCROLLBAR_COMPENSATE, 0)

  canvas:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  canvas:SetWidth(max(frame:GetWidth(), 1))
  canvas:SetHeight(1)
  frame:SetScrollChild(canvas)

  frame.canvas = canvas
  frame.scrollbar = scrollbar
  frame.canvasheight = 0
  frame.enabled = true

  -- How a row on the canvas marks the pointer and the selection, as a scroll list's rows do. See KIT.rowstyle.
  frame.kuihighlight = cfg.highlight and string.upper(cfg.highlight) or nil
  frame.kuihighlightcolour = KIT.colourof(cfg.highlightcolour)
  frame.OnEnable = function(this, event, onoff)
    KIT.scrollenable(this, onoff and true or false)
  end

  local function furthest(this)
    return max(this.canvasheight - this:GetHeight(), 0)
  end

  --
  -- The bar is the one record of where the view is, the frame following it, so a canvas that has shrunk pulls the view up with it.
  --
  local function fit(this)
    local sb = this.scrollbar
    local range = furthest(this)

    sb:SetMinMaxValues(0, range)
    sb:SetValue(min(sb:GetValue() or 0, range))
    this:SetVerticalScroll(sb:GetValue() or 0)
    sb:SetShown(range > 0)
  end

  scrollbar:SetValueStep(1)
  scrollbar:SetMinMaxValues(0, 0)
  scrollbar:SetValue(0)
  scrollbar:Hide()
  scrollbar:SetScript("OnValueChanged", function(this, value)
    frame:SetVerticalScroll(value)
  end)

  local gap = KUI.SCROLLBAR_COMPENSATE - KUI.SCROLLBAR_WIDTH

  scrollbar:ClearAllPoints()
  scrollbar:SetPoint("TOPLEFT", frame, "TOPRIGHT", gap, 0 - KUI.SCROLLBAR_WIDTH)
  scrollbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", gap, KUI.SCROLLBAR_WIDTH)

  --
  -- A notch of the wheel, over the canvas or over the bar, moves half the bar's height, which is what its arrows move.
  --
  local function wheel(this, delta)
    local sb = frame.scrollbar

    sb:SetValue((sb:GetValue() or 0) - delta * sb:GetHeight() / 2)
  end

  frame:EnableMouseWheel(true)
  frame:HookScript("OnMouseWheel", wheel)
  scrollbar:EnableMouseWheel(true)
  scrollbar:HookScript("OnMouseWheel", wheel)

  -- The canvas is as wide as the view on it, always, so that what is anchored to its right edge is at the view's.
  frame:HookScript("OnSizeChanged", function(this, w, h)
    this.canvas:SetWidth(max(w or 0, 1))
    fit(this)
  end)

  frame.SetCanvasHeight = function(this, h)
    this.canvasheight = max(h or 0, 0)
    this.canvas:SetHeight(max(this.canvasheight, 1))
    fit(this)
  end

  frame.ScrollTo = function(this, offset)
    this.scrollbar:SetValue(max(0, min(offset or 0, furthest(this))))
  end

  return frame
end

--
-- These functions are helper functions for dealing with scroll lists. Most often, scroll lists are lists of text items that
-- need to have something happen when they are selected, deselected and clicked. Most of the code can be shared, and these
-- helper functions do most of the common stuff. They provide opportunities for the caller to provide custom functions for various tasks.
--
function KUI.NewItemHelper(objp, num, name, w, h, stf, och, ocs, pch)
  local bname = name .. tostring(num)
  local rf = MakeFrame("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"

  rf:SetWidth(w or 160)
  rf:SetHeight(h or 16)
  KIT.rowhover(rf)

  local text = rf:CreateFontString(nil, "ARTWORK", nfn)
  text:ClearAllPoints()
  text:SetPoint("TOPLEFT", rf, "TOPLEFT", 8, -2)
  text:SetPoint("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -8, 2)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("MIDDLE")
  -- A row is one line, so what does not fit ends in an ellipsis rather than running on past the row's own edge.
  text:SetWordWrap(false)
  rf.text = text

  rf.SetText = stf or function(self, txt)
    self.text:SetText(txt)
  end

  --
  -- The row as part of a tree, the way a column list's row is, its words standing in past the connector.
  --
  rf.SetTree = function(this, kind, lead)
    this.treekind = kind
    this.treelead = lead
    this.text:SetPoint("TOPLEFT", this, "TOPLEFT", 8 + KIT.rowtree(this, 8), -2)
  end

  rf.fn_och = och
  rf.fn_ocs = ocs

  rf:SetScript("OnClick", och or function(this, button)
    local idx = this:GetID()
    if (this.fn_ocs) then
      if (this.fn_ocs(this, idx)) then
        return
      end
    end
    this:GetParent():GetParent():SetSelected(idx, false)
  end)

  if (pch) then
    pch(rf, objp, num)
  end

  return rf
end

function KUI.SetItemHelper(objp, btn, idx, tfn)
  local ts = tfn(objp, idx)
  btn:SetText(ts)
end

function KUI.SelectItemHelper(objp, idx, slot, btn, onoff, cfn, onfn, offfn, nilfn)
  if (onoff) then
    if (cfn) then
      local rv = cfn()
      if (rv == nil) then return end
      if (not rv) then
        error("Severe logic bug! Please report to me@cruciformer.com", 1)
        return
      end
    end

    if (onfn) then
      return onfn(objp, idx, slot, btn, true)
    end
  elseif (onoff == nil) then
    if (nilfn) then
      return nilfn(objp, idx, slot, btn, nil)
    end
    if (offfn) then
      return offfn(objp, idx, slot, btn, nil)
    end
  else
    if (offfn) then
      return offfn(objp, idx, slot, btn, onoff)
    end
  end
end

--
-- The selected row is marked the way its list marks a selection, the grain and a ring unless the list asked for the glow. See KIT.rowselect.
--
function KUI.HighlightItemHelper(objp, idx, slot, btn, onoff, onfn, offfn)
  if (onoff) then
    KIT.rowselect(btn, true)

    if (onfn) then
      return onfn(objp, idx, slot, btn, true)
    end
    return
  else
    KIT.rowselect(btn, false)
    if (offfn) then
      return offfn(objp, idx, slot, btn, false)
    end
  end
end

--
-- A COLUMN LIST is a scroll list whose rows are cut into columns, under a header that names them and sorts by them. Its
-- header is a straight button per column, the brief's clickable column header, and the column the list is sorted on carries
-- the kit's sort arrow pointing the way it runs. The caller keeps its own rows, as it does for a scroll list: it says how
-- many there are and fills a row's cells when asked, and when a header is clicked it hears OnSort and sorts its rows, with
-- ret:Sort doing that for it by the column's own rule.
--
-- COLUMN_HEADER is how tall the header is, COLUMN_GAP the space between two columns, and COLUMN_INSET how far a cell's words
-- stand in from the left of their column, clear of a selected row's ring. The gap is published as KUI.COLUMN_GAP, for a
-- caller working out how wide a set of columns is.
--
KIT.COLUMN_HEADER = 20
KUI.COLUMN_GAP = 4
KIT.COLUMN_GAP = KUI.COLUMN_GAP
KIT.COLUMN_INSET = 4

--
-- A column list can draw its rows as a tree one level deep, each parent followed by its children, with the connectors in the
-- first column shown. The caller may stand the whole connector in from where a parent's words start by a lead of its own,
-- given to row:SetTree. TREE_ROD is how thick a connector is, TREE_STEM how far the rod stands in past the lead, TREE_ARM
-- how far the arm reaches from the rod's left edge, TREE_REACH how far a rod reaches up into the row above to meet its
-- parent's words, and TREE_INDENT how far a child's words stand in past the lead.
--
-- The connectors are strips rather than the kit's ListTree corner, which at a row's height is under a pixel thick and goes
-- soft, where a strip is a whole number of pixels at any height and one row's rod meets the next exactly. They wear the
-- window's tint the way its metal does, TREE_WHITE of white light and TREE_CHROMA of the tint. Each is shaded across its
-- thickness as though lit from the top left, from TREE_SHINE times that colour on its lit edge to TREE_SHADE times it on
-- the other, so a rod reads as polished metal rather than a line. The lit edge keeps the tint's hue only while its brightest
-- channel stays under one: past that it clips there while the others go on rising, and gold turns yellow.
--
KIT.TREE_ROD = 1
KIT.TREE_STEM = 3
KIT.TREE_ARM = 8
KIT.TREE_REACH = 2
KIT.TREE_INDENT = 14
KIT.TREE_WHITE = 0.1
KIT.TREE_CHROMA = 0.4
KIT.TREE_SHINE = 1.15
KIT.TREE_SHADE = 0.6

--
-- Put CL's columns across the width its list has now: every column its own width but the one that asked to fill, which
-- takes what they leave. A column's own width is never less than its heading needs (col.need), so no heading is cut short.
-- The header buttons are sized and placed, and every row made so far has its cells moved to match. Header and rows both
-- stop short of the strip the list keeps for its scroll bar.
--
local function column_width(col)
  return max(col.width, col.need or 0)
end

--
-- A check list's header box (cfg.checkall) up with the boxes, lit with them, and ticked while every row whose box is shown is.
--
function KIT.checkallpaint(cl)
  local box = cl.checkall
  local list = cl.list

  if (not box) then
    return
  end

  local all = (list.itemcount or 0) > 0

  for item = 1, list.itemcount or 0 do
    if (SL.itemflag(list.checkshow, list.checkshown, item) and not SL.checked(list, item)) then
      all = false
      break
    end
  end

  box:SetShown(list.checkshown and true or false)
  box:SetEnabled((list.enabled and list.checkenabled) and true or false)
  box:SetChecked(all)
end

--
-- The columns across the list's width, less a check list's strip for its boxes, and the headings over them standing in
-- from the side the strip is on, so that each stands over its cells.
--
function KIT.columnlayout(cl)
  local strip = cl.list:CheckStrip()
  local w = (cl.list:GetWidth() or 0) - strip
  local x0 = (cl.list.checkpos == "LEFT") and strip or 0
  local fixed = 0
  local shown = 0
  local fills = 0

  --
  -- A hidden column takes no room and no gap, so the columns after it close up and a fill column takes what it gave up.
  -- Several columns may ask to fill, which is what a list built a column at a time tends to produce, and they share what is
  -- left between them rather than each taking all of it and running off the end.
  --
  for _, col in ipairs(cl.columns) do
    if (not col.hidden) then
      shown = shown + 1
      if (type(col.width) == "number") then
        fixed = fixed + column_width(col)
      else
        fills = fills + 1
      end
    end
  end

  local fill = max(0, w - fixed - max(shown - 1, 0) * KIT.COLUMN_GAP)
  local x = 0

  if (fills > 1) then
    fill = floor(fill / fills)
  end

  for _, col in ipairs(cl.columns) do
    local b = col.button or col.widget

    b:SetShown(not col.hidden)

    if (col.hidden) then
      col.w = 0
    else
      col.x = x
      col.w = (type(col.width) == "number") and column_width(col) or fill

      b:ClearAllPoints()

      --
      -- A heading is stretched to its column and its words fitted inside that. A control of the caller's is its own size and
      -- is only placed, a checkbox that grew with its column being a checkbox nobody could aim at. It stands at the head of
      -- its column and in the middle of the header's height, so that it and the controls in the cells read as one column.
      --
      if (col.button) then
        b:SetPoint("TOPLEFT", cl.header, "TOPLEFT", x0 + x + 1, 0)
        b:SetWidth(max(col.w, 1))
        b:GetFontString():SetWidth(max(col.w - 2 * col.pad - col.sortw, 1))
      else
        b:SetPoint("TOPLEFT", cl.header, "TOPLEFT", x0 + x, 0 - floor((KIT.COLUMN_HEADER - b:GetHeight()) / 2))
      end

      x = x + col.w + KIT.COLUMN_GAP
    end
  end

  for _, row in ipairs(cl.list.slots or {}) do
    KIT.columnrow(cl, row)
  end
end

--
-- Draw ROW's tree connector for the kind and lead it was given by row:SetTree, where the words of the column it is drawn in
-- start at X, or hide it when the row has none. A branch's rod runs the whole height of the row, and an end's stops at the foot of its arm. Both
-- start TREE_REACH above the row. Answers how far past X the row's words then start.
--
function KIT.rowtree(row, x)
  local kind = row.treekind
  local t = row.tree

  assert(kind == nil or kind == "branch" or kind == "end", "a row's tree connector is nil, \"branch\" or \"end\"")

  if (not kind) then
    if (t) then
      t.rod:Hide()
      t.arm:Hide()
    end
    return 0
  end

  if (not t) then
    t = { rod = row:CreateTexture(nil, "ARTWORK"), arm = row:CreateTexture(nil, "ARTWORK") }
    row.tree = t
  end

  local tint = KIT.tint(row)
  local mid = floor(row:GetHeight() / 2)
  local half = floor(KIT.TREE_ROD / 2)
  local lead = row.treelead or 0
  local rx = x + lead + KIT.TREE_STEM
  local lit, shaded = {}, {}

  for _, c in ipairs({ "r", "g", "b" }) do
    local v = KIT.TREE_WHITE + KIT.TREE_CHROMA * tint[c]

    tinsert(lit, min(v * KIT.TREE_SHINE, 1))
    tinsert(shaded, v * KIT.TREE_SHADE)
  end

  local CreateColor = CreateColor

  lit = CreateColor(lit[1], lit[2], lit[3], 1)
  shaded = CreateColor(shaded[1], shaded[2], shaded[3], 1)

  for _, tex in pairs(t) do
    tex:SetColorTexture(1, 1, 1, 1)
    tex:ClearAllPoints()
    tex:Show()
  end

  --
  -- A horizontal gradient runs from its left edge to its right, and a vertical one from its bottom edge to its top.
  --
  t.rod:SetGradient("HORIZONTAL", lit, shaded)
  t.arm:SetGradient("VERTICAL", shaded, lit)

  t.arm:SetPoint("TOPLEFT", row, "TOPLEFT", rx, 0 - mid + half)
  t.arm:SetSize(KIT.TREE_ARM, KIT.TREE_ROD)

  t.rod:SetPoint("TOPLEFT", row, "TOPLEFT", rx, KIT.TREE_REACH)
  t.rod:SetWidth(KIT.TREE_ROD)
  if (kind == "end") then
    t.rod:SetHeight(KIT.TREE_REACH + mid + half)
  else
    t.rod:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", rx, 0)
  end

  return lead + KIT.TREE_INDENT
end

--
-- The same connector on a row of the caller's own making, whose words start at X. See UI.txt.
--
function KUI:SetRowTree(row, kind, x, lead)
  row.treekind = kind
  row.treelead = lead
  return KIT.rowtree(row, x or 0)
end

--
-- Lay ROW's cells out under CL's columns. The column that says it carries the row's tree connector (tree), or the first shown
-- where none says so, carries it, if it has one, and its words stand in past it.
--
function KIT.columnrow(cl, row)
  row:SetWidth(max((cl.list:GetWidth() or 0) - cl.list:CheckStrip(), 1))

  local carrier = nil

  for _, col in ipairs(cl.columns) do
    if (not col.hidden and (col.tree or not carrier)) then
      carrier = col
    end
  end

  for _, col in ipairs(cl.columns) do
    local fs = row.cells[col.key]
    local x = (col.x or 0) + KIT.COLUMN_INSET
    local indent = 0

    if (col == carrier) then
      indent = KIT.rowtree(row, x)
    end

    fs:SetShown(not col.hidden)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", x + indent, 0)
    fs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x + indent, 0)
    fs:SetWidth(max((col.w or 0) - KIT.COLUMN_INSET - indent, 1))
  end
end

--
-- The comparison a column sorts by: its own where it gave one, and otherwise its key's value in each row, numbers as numbers
-- and anything else as words without regard to case. Either way it answers whether A comes before B running upward.
--
function KIT.columnless(col)
  if (type(col.sort) == "function") then
    return col.sort
  end

  local key = col.key

  return function(a, b)
    local va, vb = a[key], b[key]

    if (type(va) == "number" and type(vb) == "number") then
      return va < vb
    end

    return strlower(tostring(va or "")) < strlower(tostring(vb or ""))
  end
end

--
-- One column of column list FRAME, described by C, appended to the columns it already has. A column that cannot be sorted on
-- is a label on the same button and takes no clicks. One that can sorts on itself when clicked, running upward, or turns the
-- other way when it is the column already sorted on. Answers the column, which is what the layout and the rows read.
--
local function column_header(frame, c)
  --
  -- A heading is a string, which stands at the left of its column, or a table saying more about it:
  -- { text, justifyh, justifyv, font }, named and worded as they are everywhere else here and defaulting to LEFT, MIDDLE and
  -- a button's own font.
  --
  -- This is deliberately not the column's align, which is about the cells below: a column of numbers is commonly right while its heading is not.
  --
  local spec = (type(c.text) == "table") and c.text or { text = c.text }
  local col = { key = c.key, text = spec.text or "", width = c.width, align = c.align or "LEFT", sort = c.sort,
    justifyh = strupper(spec.justifyh or "LEFT"), justifyv = strupper(spec.justifyv or "MIDDLE"), font = spec.font,
    tree = c.tree }

  --
  -- A column may carry a control of the caller's in its header rather than a heading, for a column whose cells are controls
  -- too: the tick that answers for every row belongs at the top of the column of ticks it answers for, not beside it.
  --
  -- Such a column cannot be sorted on. The heading is a button so that clicking it sorts, and a control in its place is
  -- taking those clicks for itself.
  --
  if (c.header) then
    col.sort = nil
    col.widget = KUI:CreateCheckBox({ x = 0, y = 0, checked = c.header.checked, tooltip = c.header.tooltip },
      frame.header)

    col.widget:Catch("OnValueChanged", function(this, evt, onoff, user)
      if (user and c.header.changed) then
        c.header.changed(frame, onoff)
      end
    end)

    tinsert(frame.columns, col)

    return col
  end

  local b = KUI:CreateButton({ style = "STRAIGHT", text = col.text, width = 60, height = KIT.COLUMN_HEADER }, frame.header)

  --
  -- What the sort arrow takes at the right hand end, which the words are kept out of however they are justified. A column
  -- that cannot be sorted on has no arrow and gives the whole width to its heading. A heading in a smaller font of its own
  -- has its arrow drawn smaller by as much, so that the two keep their proportion.
  --
  col.sortw = 0

  local scale = 1

  if (col.font) then
    local _, own = KUI:MeasureStrWidth("Wy", col.font)
    local _, usual = KUI:MeasureStrWidth("Wy", "GameFontNormal")

    if ((usual or 0) > 0 and (own or 0) > 0) then
      scale = min(1, own / usual)
    end
  end

  for _, dir in ipairs({ "Up", "Down" }) do
    local arrow = KIT.new(b, "ListSort" .. dir, { layer = "OVERLAY" })
    local d = arrow.def
    local h = floor(d.draw * scale + 0.5)

    arrow.box:SetPoint("RIGHT", b, "RIGHT", 0 - KIT.COLUMN_INSET - 2, 0)
    arrow.box:SetSize(h * d.aspect, h)
    arrow:Layout()
    arrow:Hide()
    b["sort" .. dir] = arrow

    if (col.sort) then
      col.sortw = ceil(h * d.aspect) + 2
    end
  end

  if (col.sort) then
    b:Catch("OnClick", function()
      local asc = true

      if (frame.sortkey == col.key) then
        asc = not frame.ascending
      end
      frame:SetSort(col.key, asc, true)
    end)
  else
    b:EnableMouse(false)
  end

  --
  -- How far in the words start, which is the button's own end and nothing on top of it. A button's ends are drawn at their
  -- own size whatever its width, so words set in by the column's inset alone would begin inside the rim rather than clear of
  -- it, and the rim is itself the space between the words and the edge. This is what CreateButton allows for when it sizes its own text.
  --
  col.pad = ceil(KIT.ends(b.art, KIT.COLUMN_HEADER) / 2)

  --
  -- A button's font string is centred on the button by default, so the heading is anchored here instead. Left and centre
  -- hang from the left, right from the right and clear of the arrow. KIT.columnlayout sets the width between them.
  --
  local fs = b:GetFontString()

  -- A heading in a font of its own wears it in the button's colours, so that it lights and dims as any heading does.
  if (col.font) then
    fs:SetFontObject(KIT.textfont(col.font))
    b:SetNormalFontObject(KIT.textfont(col.font))
    b:SetHighlightFontObject(KIT.textfont(col.font, true))
    b:SetDisabledFontObject(KIT.dimfont(col.font))
  end

  fs:ClearAllPoints()
  fs:SetJustifyH(col.justifyh)
  fs:SetJustifyV(col.justifyv)

  if (col.justifyh == "RIGHT") then
    fs:SetPoint("RIGHT", b, "RIGHT", 0 - col.pad - col.sortw, 0)
  else
    fs:SetPoint("LEFT", b, "LEFT", col.pad, 0)
  end

  --
  -- The least the column may be for its heading to show whole: the words, the button's ends and the arrow where it sorts.
  -- A caller cannot know the last two, so KIT.columnlayout holds a column of a fixed width to this rather than cutting its
  -- heading short. The words' own width is what they measure unconfined, and the two over it are for rounding.
  --
  col.need = ceil(fs:GetStringWidth() or 0) + 2 + 2 * col.pad + col.sortw

  col.button = b
  tinsert(frame.columns, col)

  return col
end

--
-- ROW's words for column COL. The list builds a row only when it needs one and a column may arrive after some of them
-- already exist, so this is called both as a row is made and as a column is added to a list that already has rows.
--
local function column_cell(row, col, font)
  local fs = row:CreateFontString(nil, "ARTWORK", font)

  fs:SetJustifyH(col.align)
  fs:SetJustifyV("MIDDLE")
  fs:SetWordWrap(false)
  row.cells[col.key] = fs

  return fs
end

function KUI:CreateColumnList(cfg, kparent)
  assert(cfg.name, "a column list must be named")
  assert(cfg.columns and #cfg.columns > 0, "a column list must have columns")
  assert(cfg.setitem, "a column list must be given setitem")

  local frame, parent = newobj(cfg, kparent, 0, 0, cfg.name)

  frame:ClearAllPoints()
  frame:SetAllPoints(parent)

  local header = MakeFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  header:SetHeight(KIT.COLUMN_HEADER)
  frame.header = header

  local body = MakeFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0 - KUI.INTERNAL_GAP)
  body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.body = body

  --
  -- The header, one button per column. The font is kept because a column added later has to make its cells in the same one.
  --
  frame.font = cfg.font or "GameFontNormalSmallLeft"
  frame.columns = {}
  for _, c in ipairs(cfg.columns) do
    column_header(frame, c)
  end

  --
  -- The rows. Each is a text per column, and a caller that wants more of a row, a tooltip say, gets it through cfg.newrow.
  -- Clicking a row selects it unless newrow says otherwise.
  --
  local list = KUI:CreateScrollList({
    name = cfg.name .. "List",
    itemheight = cfg.itemheight or 16,
    highlight = cfg.highlight,
    highlightcolour = cfg.highlightcolour,
    scrollbar = cfg.scrollbar,
    itemcheck = cfg.itemcheck,
    checkpos = cfg.checkpos,
    ischecked = cfg.ischecked,
    newitem = function(objp, num)
      local row = MakeFrame("Button", nil, objp.content)

      row:SetHeight(objp.itemheight)
      KIT.rowhover(row)
      row.cells = {}
      for _, col in ipairs(frame.columns) do
        column_cell(row, col, frame.font)
      end
      row.SetCell = function(this, key, text)
        local fs = this.cells[key]

        if (fs) then
          fs:SetText(text or "")
        end
      end
      row.SetTree = function(this, kind, lead)
        if (this.treekind ~= kind or this.treelead ~= lead) then
          this.treekind = kind
          this.treelead = lead
          KIT.columnrow(frame, this)
        end
      end
      row:SetScript("OnClick", function(this)
        objp:SetSelected(this:GetID(), false)
      end)

      KIT.columnrow(frame, row)
      if (cfg.newrow) then
        cfg.newrow(frame, row, num)
      end
      return row
    end,
    setitem = function(objp, idx, slot, btn)
      btn:SetID(idx)
      return cfg.setitem(frame, idx, slot, btn)
    end,
    selectitem = function(objp, idx, slot, btn, onoff)
      if (cfg.selectitem) then
        return cfg.selectitem(frame, idx, slot, btn, onoff)
      end
    end,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }, body)
  frame.list = list
  frame.itemcount = 0

  --
  -- The header stops short of the scroll bar's strip, so the bar starts level with the top of the header rather than below
  -- it, its up arrow in the space beside the last column. Only its top anchor moves: it stays in its strip.
  --
  list.scrollbar:SetPoint("TOPLEFT", header, "TOPRIGHT", 0 - KUI.SCROLLBAR_WIDTH, 0 - KUI.SCROLLBAR_WIDTH)

  frame.SetSort = function(this, key, ascending, throw)
    this.sortkey = key
    this.ascending = ascending and true or false
    for _, col in ipairs(this.columns) do
      -- A column with a control of the caller's in its header has no heading and no arrows, and cannot be sorted on.
      if (col.button) then
        local on = col.key == key
        col.button.sortUp:SetShown(on and this.ascending)
        col.button.sortDown:SetShown(on and not this.ascending)
      end
    end
    if (throw) then
      this:Throw("OnSort", key, this.ascending)
    end
  end

  frame.GetSort = function(this)
    return this.sortkey, this.ascending
  end

  frame.SetColumnShown = function(this, key, onoff)
    for _, col in ipairs(this.columns) do
      if (col.key == key) then
        col.hidden = (not onoff) or nil
      end
    end
    KIT.columnlayout(this)
  end

  --
  -- The control in column KEY's header, for a caller that has to put it back where the rows have moved under it: every row
  -- ticked by hand leaves the tick at the top saying nothing, and only the caller knows when that is so.
  --
  frame.ColumnWidget = function(this, key)
    for _, col in ipairs(this.columns) do
      if (col.key == key) then
        return col.widget
      end
    end

    return nil
  end

  --
  -- A column the caller did not know about when the list was built, for a list whose shape is only settled by what arrives.
  -- It goes on the end, so the first column keeps the tree connector wherever this is called from. Rows made after this get
  -- their cell from newitem, which reads frame.columns, but rows that already exist have none and KIT.columnrow draws every
  -- column of every row, so those are given one here rather than left for the next layout to trip over.
  --
  frame.AddColumn = function(this, c)
    local col = column_header(this, c)

    for _, row in ipairs(this.list.slots or {}) do
      column_cell(row, col, this.font)
    end

    KIT.columnlayout(this)

    return col
  end

  frame.Sort = function(this, rows)
    local col

    for _, c in ipairs(this.columns) do
      if (c.key == this.sortkey) then
        col = c
      end
    end
    if (not col or not col.sort or not rows) then
      return
    end

    local less = KIT.columnless(col)

    if (this.ascending) then
      tsort(rows, less)
    else
      tsort(rows, function(a, b) return less(b, a) end)
    end
  end

  frame.UpdateList = function(this, count)
    if (count) then
      this.list.itemcount = count
    end
    this.itemcount = this.list.itemcount or 0
    this.list:UpdateList()
    KIT.checkallpaint(this)
  end

  --
  -- A check list's boxes (cfg.itemcheck) are the scroll list's, and so are its functions for them, which the column list
  -- hands on. With cfg.checkall a box in the header over them ticks or unticks every row, and is ticked while they all are.
  -- The scroll list holds one catch an event, which the column list takes to keep that box right, so OnItemChecked is
  -- thrown on again by the column list, and a caller catches it there.
  --
  if (cfg.checkall and list.checksize) then
    local side = list.checkpos
    local box = KUI:CreateCheckBox({ x = 0, y = 0, height = list.checksize }, header)

    box:ClearAllPoints()
    box:SetPoint(side, list, "TOP" .. side, 0, KUI.INTERNAL_GAP + KIT.COLUMN_HEADER / 2)
    box:Catch("OnValueChanged", function(this, evt, onoff, user)
      if (user) then
        list:SetCheckedAll(onoff)
        KIT.checkallpaint(frame)
      end
    end)
    frame.checkall = box
  end

  -- The caller is told first, since where it keeps the ticks (cfg.ischecked) the box can only be right once it has heard.
  list:Catch("OnItemChecked", function(this, evt, item, checked, user)
    frame:Throw("OnItemChecked", item, checked, user)
    KIT.checkallpaint(frame)
  end)

  for _, fn in ipairs({ "CheckAll", "UncheckAll", "SetCheckedAll", "SetItemChecked", "GetItemChecked", "ShowItemCheck",
    "HideItemCheck", "EnableItemCheck", "DisableItemCheck", "RefreshChecks", "CheckStrip" }) do
    frame[fn] = function(this, ...)
      local r = this.list[fn](this.list, ...)

      KIT.checkallpaint(this)
      return r
    end
  end

  frame.SetSelected = function(this, ...)
    return this.list:SetSelected(...)
  end

  frame.GetSelected = function(this)
    return this.list:GetSelected()
  end

  frame.OnEnable = function(this, event, onoff)
    this.list:SetEnabled(onoff)
    for _, col in ipairs(this.columns) do
      local b = col.button or col.widget

      b:SetEnabled(onoff)
    end
  end

  list:HookScript("OnSizeChanged", function()
    KIT.columnlayout(frame)
  end)
  KIT.columnlayout(frame)

  frame:SetSort(cfg.sortkey, not cfg.descending, false)
  return frame
end

KUI.ddframes = KUI.ddframes or {}

local function ddmi_tooltip(this)
  if (this.spacer) then
    return
  end
  do_tooltip_onenter(this, this.enabled and (not this.title))
end

local function stop_countdown(this)
  this:SetScript("OnUpdate", nil)
end

local function cd_OnUpdate(this)
  local now = GetTime()
  if ((now - this.timeout_start) > this.timeout) then
    this:SetScript("OnUpdate", nil)
    if (this.dropdown) then
      this.dropdown:Close()
    else
      this:Close()
    end
    this.timeout_start = 0
    this.lastpos = {}
  end
end

--
-- A menu never closes itself before the pointer has been in it. Opening one leaves the pointer on whatever opened it, and the
-- way from there into the menu crosses a gap, so a countdown armed on the way would close the menu before it could be reached.
-- TOPLEVEL.kuientered says the pointer has been in the open menu since it opened, and until it has no countdown starts.
--
local function start_countdown(this)
  if (not this.kuientered) then
    return
  end

  this.timeout_start = GetTime()
  this:SetScript("OnUpdate", cd_OnUpdate)
end

--
-- The pointer is in the open menu, which is any part of it. A dropdown's own pill is not part of its menu, and TL.OnEnter leaves it out.
--
local function menu_entered(toplevel)
  toplevel.kuientered = true
end

function TL.OnShow(this)
  this.toplevel.kuientered = nil
  this.toplevel:StartTimeoutCounter()
  this.toplevel.screenw = GetScreenWidth()
  this.toplevel.screenh = GetScreenHeight()
  this.toplevel.scale = UIParent:GetEffectiveScale()
end

-- The one dropdown menu open, if any. Opening another closes it.
local global_dd_shown

function TL.OnHide(this)
  this.toplevel:StopTimeoutCounter()
  if (this.toplevel.subopen) then
    this.toplevel.subopen:Close()
    this.toplevel.subopen = nil
  end

  --
  -- A dropdown's menu is a child of the dropdown, so it goes out of sight when the window does and yet stays shown: it would
  -- come back with the window, and until then it holds Escape, which closes whatever is shown. It is closed instead.
  --
  if (this.dropdown and this.dropdown:IsShown()) then
    this.dropdown:Close()
    if (global_dd_shown == this.dropdown) then
      global_dd_shown = nil
    end
  end
end

function TL.OnEnter(this)
  if (not this.dropdown) then
    menu_entered(this.toplevel)
  end
  this.toplevel:StopTimeoutCounter()
  do_tooltip_onenter(this, this.enabled or false)
end

function TL.OnLeave(this)
  this.toplevel:StartTimeoutCounter()
  GameTooltip:Hide()
end

function DD.OnEnter(this)
  local tl = this.toplevel

  tl:StopTimeoutCounter()
  do_tooltip_onenter(tl, tl.enabled or false)
  tl.kuitexthot = true
  KIT.ddpaint(tl)
end

function DD.OnLeave(this)
  local tl = this.toplevel

  tl:StartTimeoutCounter()
  GameTooltip:Hide()
  tl.kuitexthot = nil
  KIT.ddpaint(tl)
end

local function parent_OnEnter(this)
  menu_entered(this:GetParent().toplevel)
  this:GetParent().toplevel:StopTimeoutCounter()
end

local function parent_OnLeave(this)
  this:GetParent().toplevel:StartTimeoutCounter()
end

function DD.Close(self)
  if (self.subopen) then
    self.subopen:Close()
    self.subopen = nil
  end
  self:Hide()
  tremove(self.toplevel.lastpos)
end

function NFR.OnEnter(this)
  menu_entered(this.toplevel)
  this.toplevel:StopTimeoutCounter()
  KIT.rowshow(this)
  if (this.parent.subopen) then
    this.parent.subopen:Close()
    this.parent.subopen = nil
  end

  --
  -- The submenu hangs off the menu this item is in, so it is that menu's border it stands in by. The top level is not it
  -- for a dropdown, being the button the menu drops from, which has no border of its own.
  --
  if (this.menuframe and this.enabled) then
    local os = this.parent.offset or 0
    local ls = this.parent.hasvscroll
    local nl = #this.toplevel.lastpos
    local lasth = nl > 0 and this.toplevel.lastpos[nl][1] or nil
    local lastv = nl > 0 and this.toplevel.lastpos[nl][2] or nil
    local sw = this.toplevel.screenw
    local sh = this.toplevel.screenh

    this.menuframe:Show()
    this.parent.subopen = this.menuframe
    local rpos = KUI:GetFramePos(this, true)
    this.menuframe:ClearAllPoints()
    this.menuframe:SetPoint("TOPLEFT", this, "TOPRIGHT", 0, os)
    local mpos = KUI:GetFramePos(this.menuframe, true)
    this.menuframe:ClearAllPoints()
    if (mpos.r > sw) then
      lasth = "LEFT"
    elseif ((rpos.l - mpos.w) < 0) then
      lasth = "RIGHT"
    elseif (not lasth) then
      if (mpos.l < (sw / 2)) then
        lasth = "RIGHT"
      else
        lasth = "LEFT"
      end
    end
    if (mpos.b < 0) then
      lastv = "UP"
    elseif (mpos.t > sh) then
      lastv = "DOWN"
    elseif (not lastv) then
      if (mpos.t < (sh / 2)) then
        lastv = "UP"
      else
        lastv = "DOWN"
      end
    end

    if (lastv == "UP") then
      if (lasth == "LEFT") then
        this.menuframe:SetPoint("BOTTOMRIGHT", this, "BOTTOMLEFT", -ls, -os)
      else
        this.menuframe:SetPoint("BOTTOMLEFT", this, "BOTTOMRIGHT", 0, -os)
      end
    else
      if (lasth == "LEFT") then
        this.menuframe:SetPoint("TOPRIGHT", this, "TOPLEFT", -ls, os)
      else
        this.menuframe:SetPoint("TOPLEFT", this, "TOPRIGHT", 0, os)
      end
    end
    tinsert(this.toplevel.lastpos, { lasth, lastv })
  end
  ddmi_tooltip(this)
end

function NFR.OnLeave(this)
  this.toplevel:StartTimeoutCounter()
  KIT.rowhide(this)
  GameTooltip:Hide()
end

local function run_funcs(this, iscreate)
  if (this.func) then
    this.func(this, iscreate)
  end
  if (this.parent.func and this.parent.func ~= this.func) then
    this.parent.func(this, iscreate)
  end
  if (this.toplevel.func and this.toplevel.func ~= this.parent.func and this.toplevel.func ~= this.func) then
    this.toplevel.func(this, iscreate)
  end
end

--
-- This is only ever used by the individual line items in a dropdown or popup menu, which is reached via this.toplevel. The
-- THIS parameter is the actual button frame itself (i.e. the line item in a scroll list).
--
function NFR.OnClick(this)
  local tlf = this.toplevel
  local tlc = tlf.current

  if ((not this.clickable) or (not this.enabled)) then
    return
  end

  --
  -- One of a radio group is chosen rather than toggled: the one clicked is checked and every other item of its group in the
  -- same menu is unchecked, each throwing OnItemChecked. Clicking the one already chosen changes nothing. A SINGLE or COMPACT
  -- menu is one radio group already, and its items go the way below.
  --
  if (this.group and tlf.mode ~= MODE_SINGLE and tlf.mode ~= MODE_COMPACT) then
    if (not this.checked) then
      for _, v in ipairs(this.parent.iframes) do
        if (v ~= this and v.group == this.group and v.checked) then
          v.checked = false
          if (v.checkmark) then
            v.checkmark:Hide()
          end
          tlf:Throw("OnItemChecked", v, v.value, false)
          run_funcs(v, false)
        end
      end

      this.checked = true
      if (this.checkmark) then
        this.checkmark:Show()
      end
      tlf:Throw("OnItemChecked", this, this.value, true)
      run_funcs(this, false)
    end

    if (not this.keep) then
      (tlf.dropdown or tlf):Close()
    end
    return
  end

  if (tlf.mode == MODE_MULTI) then
    if (this.checkmark) then
      if (this.checked) then
        this.checkmark:Hide()
      else
        this.checkmark:Show()
      end
    end
    this.checked = not this.checked
    tlf:Throw("OnItemChecked", this, this.value, this.checked)
    if (not this.keep) then
      (tlf.dropdown or tlf):Close()
    end
    run_funcs(this, false)
    return
  end

  if (tlc) then
    if (tlc == this) then
      if (not this.keep) then
        (tlf.dropdown or tlf):Close()
      end
      return
    else
      tlc.checked = false
      if (tlc.checkmark) then
        tlc.checkmark:Hide()
      end
      tlf:Throw("OnItemChecked", tlc, tlc.value, tlc.checked)
      run_funcs(tlc, false)
    end
  end

  tlf.current = this
  tlc = this
  this.checked = true
  if (this.checkmark) then
    this.checkmark:Show()
  end
  -- A popup menu is its own top level and has no dropdown to close.
  if (not this.keep) then
    (tlf.dropdown or tlf):Close()
  end

  if ((tlf.mode == MODE_SINGLE) and this.text) then
    tlf.text:SetText(this.text:GetText())
    KIT.ddpaint(tlf)
  end
  tlf:Throw("OnItemChecked", this, this.value, this.checked)
  tlf:Throw("OnValueChanged", this.value, true, true)

  run_funcs(this, false)
end

--
-- A SECURE ITEM
--
-- Some things only the game's own code may do, making somebody the main tank among them, and the game refuses the call to an
-- addon outright, so an item's func cannot do them. It does them for a secure action button the player clicks, so an item
-- given SECURE, the attributes of a SecureActionButtonTemplate, is covered by such a button carrying them. The button takes
-- the click, and the item then behaves as if clicked itself, closing the menu and running any func.
--
-- The buttons are kept in a pool and laid over their items only while the menu is shown, and only over an item the menu
-- does not have scrolled out of sight. Each is UIParent's and at TOOLTIP strata, above any menu, and not the menu's own,
-- since a window holding a protected frame is itself locked in combat. The game will not set one up in combat either, so a
-- secure item is dark there, and a menu holding one is closed as combat begins, which is the last moment its buttons can
-- still be put away.
--
local secure_free = {}
local secure_used = {}

local function secure_button()
  local b = tremove(secure_free)

  if (not b) then
    b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp")
    b:SetFrameStrata("TOOLTIP")
    b:SetScript("OnEnter", function(this)
      if (this.kuirow) then
        NFR.OnEnter(this.kuirow)
      end
    end)
    b:SetScript("OnLeave", function(this)
      if (this.kuirow) then
        NFR.OnLeave(this.kuirow)
      end
    end)
    b:HookScript("OnClick", function(this)
      if (this.kuirow) then
        NFR.OnClick(this.kuirow)
      end
    end)
    b.kuiattrs = {}
  end

  return b
end

local function secure_free_button(b)
  if (b.kuirow) then
    b.kuirow.kuisecure = nil
    b.kuirow = nil
  end

  b:Hide()
  b:ClearAllPoints()
  secure_used[b] = nil
  tinsert(secure_free, b)
end

function DD.secure_release(fr)
  for _, row in ipairs(fr.iframes or {}) do
    if (row.kuisecure) then
      secure_free_button(row.kuisecure)
    end
  end
end

-- An item a scrolling menu shows only part of, or none, is left uncovered, a button over it reaching past the menu.
local function in_sight(fr, row)
  if (fr.hasvscroll == 0) then
    return true
  end

  local top, bottom = fr.sframe:GetTop(), fr.sframe:GetBottom()
  local rtop, rbottom = row:GetTop(), row:GetBottom()

  return (top and bottom and rtop and rbottom and rtop <= top and rbottom >= bottom) and true or false
end

function DD.secure_attach(fr)
  DD.secure_release(fr)

  if (not fr:IsVisible() or InCombatLockdown()) then
    return
  end

  for _, row in ipairs(fr.iframes or {}) do
    if (row.secure and row.enabled and row:IsShown() and in_sight(fr, row)) then
      local b = secure_button()

      for k in pairs(b.kuiattrs) do
        b:SetAttribute(k, nil)
      end

      b.kuiattrs = {}

      for k, v in pairs(row.secure) do
        b:SetAttribute(k, v)
        b.kuiattrs[k] = true
      end

      -- Left to itself the button acts as the mouse goes down or comes up as a setting of the game's says. A menu acts as it comes up.
      b:SetAttribute("useOnKeyDown", false)
      b.kuiattrs.useOnKeyDown = true

      b.kuirow = row
      row.kuisecure = b
      secure_used[b] = true
      b:SetAllPoints(row)
      b:Show()
    end
  end
end

KIT.securewatch = CreateFrame("Frame")
KIT.securewatch:SetScript("OnEvent", function()
  for b in pairs(secure_used) do
    local row = b.kuirow

    if (row and row.toplevel) then
      local menu = row.toplevel.dropdown or row.toplevel

      menu:Close()
    end
  end

  for b in pairs(secure_used) do
    secure_free_button(b)
  end
end)
KIT.securewatch:RegisterEvent("PLAYER_REGEN_DISABLED")

function NFR.OnHide(this)
  if (this.subopen) then
    this.subopen:Close()
    this.subopen = nil
  end
end

function DD.SetJustification(this, just)
  local tf = this.text
  if (just == "RIGHT") then
    tf:SetJustifyH(just)
  elseif (just == "CENTER") then
    tf:SetJustifyH(just)
  else
    just = "LEFT"
    tf:SetJustifyH(just)
  end
end

function DD.OnClick(this, ...)
  local pp = this:GetParent()
  local pdf = pp.dropdown
  local isshown = false
  if (pdf:IsShown()) then
    pdf:Close()
    if (global_dd_shown == pdf) then
      global_dd_shown = nil
    end
  else
    if (global_dd_shown) then
      global_dd_shown:Close()
      global_dd_shown = nil
    end
    if (pdf.itemcount > 0) then
      --
      -- A menu opening afresh has not had the pointer in it, and a countdown left over from the last time it was open must not close it.
      --
      pp:StopTimeoutCounter()
      pp.kuientered = nil
      pdf:Show()
      global_dd_shown = pdf
      isshown = true
    end
  end
  pp:Throw("OnClick", pp, isshown, ...)
end

function DD.OnMouseWheel(this, value)
  local sbf = this:GetParent().scrollbar
  local sv = floor(sbf:GetValueStep() or 0)
  local cv = sbf:GetValue() or 0
  local _, my = sbf:GetMinMaxValues()

  --
  -- A menu whose items all fit has nothing to scroll, and no step is nothing to scroll by.
  --
  if (not my or my <= 0 or sv <= 0) then
    return
  end

  if (value > 0) then
    cv = cv - sv
  elseif (value < 0) then
    cv = cv + sv
  end

  --
  -- Snapped to a whole step before it is held to the range, so that the end of the range is reached even when it is not a
  -- whole number of steps, which it is not whenever the last page is only partly full.
  --
  cv = floor(cv / sv) * sv
  if (cv < 0) then
    cv = 0
  end
  if (cv > my) then
    cv = my
  end
  sbf:SetValue(cv)
end

function DD.OnValueChanged(this, val)
  local sf = this:GetParent().sframe
  sf:SetVerticalScroll(val)
  sf:UpdateScrollChildRect()
end

function DD.OnScrollRangeChanged(this, x, y)
  local fr = this:GetParent()
  local sb = fr.scrollbar
  local cv = sb:GetValue() or 0
  local _, my = sb:GetMinMaxValues()
  local sheight = (this:GetHeight() - (2 * fr.offset) - fr.headeroffset - fr.footeroffset) / 2

  if (my ~= y) then
    sb:SetMinMaxValues(0, y)
  end
  if (cv > y) then
    cv = y
  end

  if (sheight > y) then
    sheight = y
  end
  sb:SetValueStep(sheight)
  sb:SetValue(cv)
end

function TL.OnEvent(this, event)
  if (event == "PLAYER_REGEN_ENABLED") then
    this.incombat = false
    this:Throw("OnLeaveCombat")
  elseif (event == "PLAYER_REGEN_DISABLED") then
    this.incombat = true
    this:Throw("OnEnterCombat")
  end
end

function DD.item_init(item)
  item.arg = nil
  item.checkable = nil
  item.checked = nil
  item.checkmark = nil
  item.clickable = nil
  item.color = nil
  item.enabled = nil
  item.font = nil
  item.frame = nil
  item.func = nil
  item.group = nil
  item.hasvscroll = nil
  item.hasicons = nil
  item.hassub = nil
  item.hascheck = nil
  item.height = nil
  item.icon = nil
  item.idx = nil
  item.iinfo = nil
  item.keep = nil
  item.secure = nil
  item.menuarg = nil
  item.menuframe = nil
  item.menuname = nil
  item.name = nil
  item.spacer = nil
  item.subarrow = nil
  item.text = nil
  item.tipfunc = nil
  item.tiptext = nil
  item.tiptitle = nil
  item.title = nil
  item.tlarg = nil
  item.tlname = nil
  item.toplevel = nil
  item.value = nil
  item.width = nil
end

function DD.create_cframe(fr, cfname, ftype)
  local nfr

  if (not ftype and fr.kframes[cfname]) then
    nfr = fr.kframes[cfname]
    nfr:SetParent(fr.cframe)
  else
    nfr = MakeFrame(ftype or "Button", ftype == nil and cfname or nil, fr.cframe)
    if (not ftype) then
      fr.kframes[cfname] = nfr
    end
  end
  DD.item_init(nfr)
  nfr:SetFrameStrata(fr.cframe:GetFrameStrata())
  nfr:SetFrameLevel(fr.cframe:GetFrameLevel() + 1)
  nfr.toplevel = fr.toplevel or fr
  nfr.parent = fr
  nfr.rparent = fr.cframe
  nfr:SetScript("OnEnter", NFR.OnEnter)
  nfr:SetScript("OnLeave", NFR.OnLeave)
  if (not ftype) then
    nfr:SetScript("OnClick", NFR.OnClick)
  end
  nfr:SetScript("OnHide", NFR.OnHide)
  return nfr
end


function DD.refresh_frame(fr, tlfr, ilist, nilist)
  if (tlfr == fr) then
    -- If this is the top level frame, set it to nil
    tlfr = nil
  end

  --
  -- The first step in the refresh is to go through the existing line items and see if they have any of the "extra" bits
  -- displayed - the submenu check, the check item check etc. So we go through the current list and hide any such markers.
  --
  DD.secure_release(fr)

  if (fr.iframes) then
    for k,v in ipairs(fr.iframes) do
      if (v.p_checkmark) then
        v.p_checkmark:Hide()
      end
      if (v.p_radioring) then
        v.p_radioring:Hide()
        v.p_radioorb:Hide()
      end
      v.checked = nil
      v.checkmark = nil

      if (v.menuframe) then
        v.menuframe:Hide()
      end

      if (v.p_spacer) then
        v.p_spacer:Hide()
      end
      v.spacer = nil

      if (v.p_subarrow) then
        v.p_subarrow:Hide()
      end
      v.subarrow = nil

      if (v.p_icon) then
        v.p_icon:Hide()
      end
      v.icon = nil

      if (v.p_text) then
        v.p_text:Hide()
      end
      v.text = nil

      v:Hide()
    end
  end

  fr.itemcount = nilist
  fr.items = ilist
  fr.iheight = 0
  fr.iframes = {}

  local cf = fr.cframe

  --
  -- Set up the actual list item buttons. As we go through the list we calculate the widest button and whether or not any
  -- buttons have check marks, icons or submenu marks. We set the text for each button (with any color specified) and other button options.
  --
  local relframe = fr.cframe
  local rtopleft = "TOPLEFT"
  local rbotright = "TOPRIGHT"
  local widest = 0
  local hassub = 0
  local hasicons = 0
  local hascheck = 0

  local function set_element(which, tbf, v, tv)
    local is_which = "is_" .. which
    if (v[which] ~= nil) then
      if (type(v[which]) == "boolean") then
        tbf[which] = v[which]
      elseif (type(v[which]) == "function") then
        tbf[which] = v[which](tbf)
      else
        assert(false, which .. " must be a boolean or a function")
      end
    elseif (tv[is_which] ~= nil) then
      if (type(tv[is_which]) == "boolean") then
        tbf[which] = tv[is_which]
      elseif (type(tv[is_which]) == "function") then
        tbf[which] = tv[is_which](tbf)
      end
    end
  end

  for k,v in ipairs(fr.items) do
    local tbf, txt, w, h = nil, nil, nil, nil

    local cfname = cf:GetName() .. "Button" .. k
    tbf = DD.create_cframe(fr, cfname, v.frame and "Frame" or nil)
    tbf:Show()
    tinsert(fr.iframes, tbf)

    tbf.iinfo = v
    tbf.idx = k
    tbf.arg = v.arg
    tbf.name = v.name
    tbf.func = v.func
    tbf.value = v.value
    -- A custom frame's group is its radio widget's own, and only a text item is marked as one of a group.
    tbf.group = (not v.frame) and v.group or nil
    tbf.menuname = fr:GetName()
    tbf.menuarg = fr.arg
    if (v.tooltip) then
      tbf.tiptitle = v.tooltip.title
      tbf.tiptext = v.tooltip.text
      tbf.tipfunc = v.tooltip.func
    end
    if (tlfr) then
      tbf.toplevel = tlfr
      tbf.tlarg = tlfr.arg
      tbf.tlname = tlfr:GetName()
    else
      tbf.toplevel = fr
      tbf.tlarg = fr.arg
      tbf.tlname = fr:GetName()
    end

    if (v.color) then
      if (type(v.color) == "table") then
        tbf.color = {r = v.color.r or 1, g = v.color.g or 1, b = v.color.b or 1, a = v.color.a or 1 }
      elseif (type(v.color) == "function") then
        local fc = v.color(tbf)
        assert(type(fc) == "table", "return color must be an RGB table")
        tbf.color = {r = fc.r or 1, g = fc.g or 1, b = fc.b or 1, a = fc.a or 1 }
      else
        assert(false, "color must be a table or function")
      end
    else
      tbf.color = nil
    end

    -- See if it is a title element or not
    tbf.title = false
    set_element("title", tbf, v, tlfr or fr)

    -- See if it is disabled or not
    tbf.enabled = true
    set_element("enabled", tbf, v, tlfr or fr)

    -- What only the game's own code may do, done by a secure button laid over the item (see A SECURE ITEM), never in combat.
    if (type(v.secure) == "function") then
      tbf.secure = v.secure(tbf)
    else
      tbf.secure = v.secure
    end

    if (tbf.secure and InCombatLockdown()) then
      tbf.enabled = false
    end

    -- Determine if it is checked or not
    tbf.checked = false
    set_element("checked", tbf, v, tlfr or fr)

    -- Determine if we should keep the window open on click or not
    if (fr.mode == MODE_MULTI) then
      tbf.keep = true
    else
      tbf.keep = false
    end
    set_element("keep", tbf, v, tlfr or fr)

    -- Determine the item text
    tbf.spacer = nil
    if (v.text) then
      if (type(v.text) == "string") then
        txt = v.text
      elseif (type(v.text) == "function") then
        txt = v.text(tbf)
      else
        assert(false, "text must be a string or a function")
      end
      assert(txt)
      if (txt == "-") then
        -- This is a spacer, a faint hairline in the white a menu's words are in, or grey when the item is disabled.
        if (not tbf.p_spacer) then
          local st = tbf:CreateTexture(nil, "ARTWORK")
          st:Hide()
          tbf.p_spacer = st
        end
        tbf.spacer = tbf.p_spacer
        tbf.spacer:Show()
        txt = nil
        if (tbf.enabled) then
          local c = KIT.COLOR_TEXT
          tbf.spacer:SetColorTexture(c.r, c.g, c.b, 0.3)
        else
          tbf.spacer:SetColorTexture(0.4, 0.4, 0.4, 0.3)
        end
      else
        if (tbf.p_spacer) then
          tbf.p_spacer:Hide()
        end
      end
    end

    -- Determine if the item is clickable or not
    tbf.clickable = true
    set_element("clickable", tbf, v, tlfr or fr)

    -- Determine if the item is checkable or not
    tbf.checkable = true
    set_element("checkable", tbf, v, tlfr or fr)

    -- Set values that depend on the type
    if (tbf.title or tbf.spacer) then
      tbf.checked = false
      tbf.clickable = false
      tbf.checkable = false
    end

    if (not tbf.enabled) then
      tbf.clickable = false
      if (not tbf.frame) then
        tbf:SetScript("OnClick", nil)
      end
    end

    --
    -- Adjust for submenus, icons and check marks. An item that opens a submenu is not itself a choice, unless it is one of a
    -- radio group, which is a choice with more to say about it: it keeps its ring, and the submenu is where the rest is said.
    --
    if (v.submenu) then
      if (not tbf.group) then
        tbf.checkable = false
      end
      hassub = 16
      if (not tbf.p_subarrow) then
        local sm = KIT.new(tbf, "MenuArrow", { layer = "ARTWORK" })
        local mh = sm.def.draw
        sm.box:SetPoint("CENTER", tbf, "RIGHT", -8, 0)
        sm.box:SetSize(mh * sm.def.aspect, mh)
        sm:Layout()
        tbf.p_subarrow = sm
      end
      tbf.subarrow = tbf.p_subarrow
      tbf.subarrow:Show()
      tbf.subarrow:SetEnabled(tbf.enabled)
      if (tbf.enabled) then
        tbf.menuframe = DD.create_sa(v.submenu, fr, fr.toplevel, nil)
      else
        tbf.menuframe = nil
      end
    else
      if (tbf.p_subarrow) then
        tbf.p_subarrow:Hide()
      end
      tbf.subarrow = nil
      tbf.menuframe = nil
    end

    if (v.icon) then
      -- The icon's column, and the gap that keeps the item's words off it.
      hasicons = 16 + KUI.INTERNAL_GAP

      -- A function answers the texture for this item, asked every time the menu is built.
      local itex = v.icon
      if (type(itex) == "function") then
        itex = itex(tbf)
      elseif (type(itex) ~= "string") then
        assert(false, "icon must be a string or a function")
      end

      if (not tbf.p_icon) then
        local it = tbf:CreateTexture(nil, "ARTWORK")
        it:SetWidth(16)
        it:SetHeight(16)
        it:ClearAllPoints()
        tbf.p_icon = it
      end
      tbf.icon = tbf.p_icon
      tbf.icon:SetTexture(itex)
      if (v.iconcoord) then
        tbf.icon:SetTexCoord(v.iconcoord.left or 0, v.iconcoord.right or 1, v.iconcoord.top or 0, v.iconcoord.bottom or 1)
      else
        tbf.icon:SetTexCoord(0, 1, 0, 1)
      end
    else
      if (tbf.p_icon) then
        tbf.p_icon:Hide()
      end
      tbf.icon = nil
    end

    local fontnm = "GameFontHighlightSmallLeft"
    if (tbf.title) then
      fontnm = "GameFontNormalSmallLeft"
    end
    tbf.font = fontnm
    if (v.font) then
      if (type(v.font) == "string") then
        tbf.font = v.font
      elseif (type(v.font) == "function") then
        tbf.font = v.font(tbf)
      else
        assert(false, "font must be a string or a function")
      end
    end

    -- See if this is the widest item yet
    if (txt) then
      w = ceil(KUI:MeasureStrWidth(txt, tbf.font) + 8)
    elseif (not tbf.spacer) then
      if (type(v.frame) == "table") then
        tbf.frame = v.frame
      elseif (type(v.frame) == "function") then
        tbf.frame = v.frame(tbf)
      elseif (type(v.frame) == "boolean" and v.frame) then
        tbf.frame = item_widget(tbf)
      else
        assert(false, "frame must be a table, a function or true")
      end
      tbf.frame:SetParent(cf)
      tbf.frame:SetFrameLevel(tbf:GetFrameLevel() + 1)

      w = tbf.width or floor(tbf.frame:GetWidth() + 0.5)
    end

    if (fr.itemheight) then
      h = fr.itemheight
    else
      assert(v.height, "item must specify height if global itemheight not set")
    end
    if (v.height) then
      h = v.height
    end
    if ((not w or w == 0) and v.width) then
      w = v.width
    end

    --
    -- In case one of the functions called forced a width and height, set it to any preset values now.
    --
    if (tbf.width) then
      w = tbf.width
    end
    if (tbf.height) then
      h = tbf.height
    end

    --
    -- A checkable item is marked by a tick, and one of a radio group by the kit's radio ring, always shown, with its orb in it
    -- when it is the one chosen. The orb is the item's checkmark, so everything that shows and hides a checkmark works on it.
    --
    if (tbf.p_checkmark) then
      tbf.p_checkmark:Hide()
    end
    if (tbf.p_radioring) then
      tbf.p_radioring:Hide()
      tbf.p_radioorb:Hide()
    end
    tbf.checkmark = nil

    if (tbf.checkable and tbf.group) then
      hascheck = 16
      if (not tbf.p_radioring) then
        local rs = KIT.MENU_RADIO
        local ring = KIT.new(tbf, "RadioButton", { layer = "ARTWORK", sublevel = 0 })
        ring.box:SetPoint("CENTER", tbf, "LEFT", 8, 0)
        ring.box:SetSize(rs, rs)
        ring:Layout()

        local orb = KIT.new(tbf, "RadioButtonOrb", { layer = "ARTWORK", sublevel = 2, flat = true, part = "mark" })
        local os = rs * orb.def.draw / ring.def.draw
        orb.box:SetPoint("CENTER", ring.box, "CENTER", 0, 0)
        orb.box:SetSize(os, os)
        orb:Layout()

        tbf.p_radioring = ring
        tbf.p_radioorb = orb
      end
      tbf.p_radioring:Show()
      tbf.p_radioring:SetEnabled(tbf.enabled)
      tbf.checkmark = tbf.p_radioorb
      tbf.checkmark:SetEnabled(tbf.enabled)
    elseif (tbf.checkable) then
      hascheck = 16
      if (not tbf.p_checkmark) then
        local cm = KIT.new(tbf, "CheckBoxTick", { layer = "ARTWORK", accented = KIT.markaccented(tbf),
          part = "mark" })
        local ch = 14
        cm.box:SetPoint("CENTER", tbf, "LEFT", 8, 0)
        cm.box:SetSize(ch * cm.def.aspect, ch)
        cm:Layout()
        tbf.p_checkmark = cm
      end
      tbf.checkmark = tbf.p_checkmark
      tbf.checkmark:SetEnabled(tbf.enabled)
    end
    if (tbf.checkmark) then
      tbf.checkmark:SetShown(tbf.checked)
    end

    if (w and w > widest) then
      widest = w
    end
    fr.iheight = fr.iheight + h

    -- Position the item frame within the scrolling child frame
    tbf:ClearAllPoints()
    tbf.height = h
    tbf:SetPoint("TOPLEFT", relframe, rtopleft, 0, 0)
    tbf:SetPoint("BOTTOMRIGHT", relframe, rbotright, 0, -tbf.height)
    -- @debug-start@
    if (v.debug) then
      local ttt = tbf:CreateTexture(nil, "ARTWORK")
      ttt:SetAllPoints(tbf)
      ttt:SetColorTexture(0.3, 0.3, 0.3)
    end
    -- @debug-end@
    relframe = tbf
    rtopleft = "BOTTOMLEFT"
    rbotright = "BOTTOMRIGHT"

    -- If it was a text item create the string and set its value
    if (txt) then
      if (not tbf.p_text) then
        tbf.p_text = tbf:CreateFontString(nil, "OVERLAY", tbf.font)
      end
      local text = tbf.p_text
      text:SetFontObject(tbf.font)
      text:ClearAllPoints()
      text:SetJustifyH(v.justifyh or "LEFT")
      text:SetJustifyV(v.justifyv or "MIDDLE")
      text:SetText(txt)
      check_tooltip_title(tbf, v, txt)
      if (tbf.color) then
        text:SetTextColor(tbf.color.r, tbf.color.g, tbf.color.b, tbf.color.a)
      else
        text:SetTextColor(KUI:GetFontColor(tbf.font))
      end
      tbf.text = text
    else
      if (tbf.p_text) then
        tbf.p_text:Hide()
      end
      tbf.text = nil
    end

    --
    -- If the item isn't disabled in any way (not a title, not explicitly disabled), set the button highlight texture.
    -- Otherwise clear it in case we are reusing a frame from a previous call to create this menu.
    --
    if (not tbf.frame) then
      KIT.rowglow(tbf)
      tbf.kuiglowable = (tbf.enabled and tbf.clickable) and true or false
      KIT.rowhide(tbf)
    else
      tbf.kuiglowable = false
    end

    if (tbf.text and (not tbf.enabled)) then
      local r, g, b, a = tbf.text:GetTextColor()
      tbf.text:SetTextColor(r/2, g/2, b/2, a or 1)
    end
  end -- Of loop through all of the items

  local wwidth = widest
  if (fr.width and fr.width > 0) then
    if (fr.width > widest) then
      widest = fr.width
    end
    wwidth = fr.width
  end

  local wheight = fr.height
  if (not wheight or wheight <= 0) then
    wheight = fr.iheight
    if (wheight > 300) then
      wheight = 300
    end
  end
  local iwheight = wheight

  -- See if we need a vertical scroll bar or not
  local hasvscroll = 0
  if (fr.iheight > wheight) then
    hasvscroll = 12
  end
  if (fr.maxheight and fr.iheight > fr.maxheight) then
    hasvscroll = 12
  end
  if (fr.minheight and fr.iheight > fr.minheight) then
    hasvscroll = 12
  end

  --
  -- Now adjust the width for possible submenu marks, scroll bars and for the checkmark. Then, size the frame and draw its borders, background etc.
  --
  local xtra = hasvscroll + hasicons + hassub + hascheck

  -- Add in the width/height of the border
  wheight = wheight + (fr.offset * 2) + fr.headeroffset + fr.footeroffset
  wwidth = wwidth + xtra + (fr.offset * 2)

  fr.hasvscroll = hasvscroll
  fr.hasicons = hasicons
  fr.hassub = hassub
  fr.hascheck = hascheck

  local maxwidth = widest + xtra + (fr.offset * 2)
  local maxheight = fr.iheight + (fr.offset * 2) + fr.headeroffset + fr.footeroffset

  fr:SetWidth(wwidth)
  fr:SetHeight(wheight)
  fr.widest = widest
  fr.extrawidth = xtra

  fr:SetResizeBounds(fr.minwidth or wwidth, fr.minheight or wheight, fr.maxwidth or maxwidth, fr.maxheight or maxheight)

  --
  -- Now we need to loop through all of the item frames one last time and do the final positioning of all elements now that
  -- we know which extra elements will be displayed.
  --
  for k,v in ipairs(fr.iframes) do
    if (v.spacer) then
      -- Centred, the same way in from each side whatever columns the items round it have.
      v.spacer:ClearAllPoints()
      local vpos = floor(v.height / 2) - 1
      v.spacer:SetPoint("TOPLEFT", v, "TOPLEFT", 2 * KUI.WIDGET_GAP, -vpos)
      v.spacer:SetPoint("TOPRIGHT", v, "TOPRIGHT", -2 * KUI.WIDGET_GAP, -vpos)
      v.spacer:SetHeight(1)
      v.spacer:Show()
    elseif (v.text) then
      v.text:ClearAllPoints()
      v.text:SetPoint("TOPLEFT", v, "TOPLEFT", fr.hascheck + fr.hasicons, 0)
      v.text:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", fr.hassub * -1, 0)
      v.text:Show()
    elseif (v.frame) then
      v.frame:Show()
    end

    if (v.icon) then
      v.icon:SetPoint("LEFT", v, "LEFT", fr.hascheck, 0)
      v.icon:Show()
    end

    if (v.checked and v.checkmark) then
      --
      -- We can't just blindly show the check mark. If this is a SINGLE or COMPACT dropdown menu, only 1 item at a time can
      -- ever be checked. So, we look to see if we already have an entry checked, and if so, we uncheck it and mark this one
      -- as the current checked value.
      --
      if (v.toplevel.mode) then
        if (v.toplevel.mode ~= MODE_MULTI) then
          if (v.toplevel.current) then
            v.toplevel.current.checked = false
            if (v.toplevel.current.checkmark) then
              v.toplevel.current.checkmark:Hide()
            end
          end
          v.toplevel.current = v
        end
        v.checkmark:Show()
      else
        v.checkmark:Show()
      end
    elseif (v.checked and v.clickable) then
      if (v.toplevel.mode ~= MODE_MULTI) then
        if (v.toplevel.current) then
          v.toplevel.current.checked = false
          if (v.toplevel.current.checkmark) then
            v.toplevel.current.checkmark:Hide()
          end
        end
        v.toplevel.current = v
      end
    end

    if (v.subarrow) then
      v.subarrow:Show()
    end

    run_funcs(v, true)
  end

  --
  -- And last but not least, position the scrollbar and scroll frame within the main frame.
  --
  fr.sframe:SetPoint("TOPLEFT", fr, "TOPLEFT", fr.offset + fr.hasvscroll, -(fr.offset + fr.headeroffset))
  fr.sframe:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", -fr.offset, fr.offset + fr.footeroffset)
  cf:SetHeight(fr.iheight)
  cf:SetWidth(fr.widest + fr.extrawidth - fr.hasvscroll)
  fr.sframe:UpdateScrollChildRect()
  if (fr.hasvscroll > 0) then
    fr.scrollbar:Show()
    fr.scrollbar:SetValue(0)
    local mxs = fr.minheight
    if (not fr.minheight) then
      mxs = iwheight
    end
    fr.scrollbar:SetMinMaxValues(0, fr.iheight - mxs)
  else
    fr.scrollbar:Hide()
  end

  --
  -- Check to see if the window is currently larger than the min/maximum. This can happen when items are refreshed and the maximum size changes.
  --
  local mnwidth, mnheight, mxwidth, mxheight = fr:GetResizeBounds()
  local cw, ch = fr:GetWidth(), fr:GetHeight()
  local sbx, sby = fr.scrollbar:GetMinMaxValues()
  if (cw < mnwidth) then
    fr:SetWidth(mnwidth)
    cw = mnwidth
  end
  if (ch < mnheight) then
    fr:SetHeight(mnheight)
    ch = mnheight
  end
  --
  -- By ordering things this way we catch the case where the maximum is actually less than the minimum.
  --
  if (cw > mxwidth) then
    fr:SetWidth(mxwidth)
  end
  if (ch > mxheight) then
    fr:SetHeight(mxheight)
  end

  DD.secure_attach(fr)
end

--
-- The words a dropdown puts in its static box when it has nothing of its own to put there, which are the head of its list
-- when that item is a title item. A title item is not one of the choices, it names the list it heads, so a box that would
-- otherwise stand empty says that instead. Nil where the list has no such head, and then the box says nothing.
--
-- Read off the built item rather than off the caller's item table, so that a title or a text given as a function is whatever
-- the menu itself made of it and the two can never disagree.
--
function DD.headtext(this)
  local fr = this.dropdown or this
  local head = fr.iframes and fr.iframes[1]

  if (head and head.title and head.text) then
    return head.text:GetText()
  end

  return nil
end

--
-- Only the top-level frame gets this function
--
function DD.UpdateItems(this, newitems)
  assert(newitems, "dropdown items must be provided")
  local ic = 0
  for k,v in pairs(newitems) do
    ic = ic + 1
    assert(v.text or v.frame, "must provide text or a custom frame")
  end

  if (this.subopen) then
    this.subopen:Close()
    this.subopen = nil
  end

  if (this.dropdown) then
    local oldv = nil
    if (this.current) then
      oldv = this.current.value
      if (this.current.checkmark) then
        this.current.checkmark:Hide()
      end
      this.current.checked = false
      this.current = nil
    end
    local shown = this.dropdown:IsShown()
    this.dropdown:Close()
    DD.refresh_frame(this.dropdown, this.toplevel, newitems, ic)

    -- An item the new items mark as checked, which building them has already chosen.
    local chosen = this.current

    if (this.text) then
      if ((this.mode ~= MODE_SINGLE) and this.titletext) then
        this.text:SetText(this.titletext)
      else
        this.text:SetText(DD.headtext(this) or "")
      end
    end

    --
    -- The value held before is kept when the new items still offer it, and otherwise the one they mark as checked is chosen.
    -- Either way a SINGLE dropdown's pill shows what is chosen, SetValue saying nothing of a value that is chosen already.
    --
    if (oldv) then
      this:SetValue(oldv, true)
    end
    if (chosen and not this.current) then
      this:SetValue(chosen.value, true)
    end
    if (this.mode == MODE_SINGLE and this.text and this.current and this.current.text) then
      this.text:SetText(this.current.text:GetText())
      KIT.ddpaint(this)
    end
    if (shown) then
      this.dropdown:Show()
      DD.OnEnter(this)
    end
  else
    this.current = nil
    DD.refresh_frame(this, this.toplevel, newitems, ic)
  end
end

function DD.GetValue(this)
  local tl = this.toplevel
  if (not tl.current) then
    return nil
  end
  return tl.current.value
end

--
-- The colour a closed dropdown shows the chosen ITEM's words in: the item's own colour where it was given one, a class's say,
-- and otherwise a button's, a closed dropdown being the same pill as a button, KIT.COLOR_TEXT or KIT.COLOR_TEXT_HOT while the pointer is
-- on it, HOT. The open menu keeps its own colours. Words carrying colour codes show those whatever this says.
--
function KIT.ddvaluecolour(item, hot)
  local c = (item and item.color) or (hot and KIT.COLOR_TEXT_HOT) or KIT.COLOR_TEXT

  return c.r, c.g, c.b, c.a or 1
end

--
-- Colour the words of the closed dropdown TL for the item it shows, whether it is enabled and whether the pointer is on it. A
-- disabled one is dimmed to half and never lights.
--
function KIT.ddpaint(tl)
  local cur = tl.current

  if (tl.mode ~= MODE_SINGLE or not tl.text) then
    return
  end

  local d = tl.enabled and 1 or 2

  --
  -- With nothing chosen the box shows its title rather than an answer, and wears it the way a MULTI dropdown wears its own,
  -- in the title's gold rather than in the white a value is shown in.
  --
  if (not cur or not cur.text) then
    local c = tl.trgb

    if (c) then
      tl.text:SetTextColor(c.r/d, c.g/d, c.b/d, c.a)
    end

    return
  end

  local r, g, b, a = KIT.ddvaluecolour(cur, tl.enabled and tl.kuitexthot)

  if (tl.kuichanged) then
    local c = KUI.DEFAULT_CHANGED_COLOR

    r, g, b, a = c.r, c.g, c.b, 1
  end

  tl.text:SetTextColor(r/d, g/d, b/d, a)
end

function DD.SetValue(this, value, nothrow)
  local tl = this.toplevel
  if (tl.current and tl.current.value == value) then
    return true
  end

  local function recursive_set(tlf, frs, val)
    for k,v in ipairs(frs.iframes) do
      if (val and v.value == val and v.clickable) then
        if (tlf.current) then
          tlf.current.checked = false
          if (tlf.current.checkmark) then
            tlf.current.checkmark:Hide()
          end
          tlf.current = nil
        end
        tlf.current = v
        v.checked = true
        if (v.checkable and v.checkmark) then
          v.checkmark:Show()
        end
        return true
      end
      if (v.menuframe) then
        local done = recursive_set(tlf, v.menuframe, val)
        if (done) then
          return true
        end
      end
    end
    return false
  end

  local ret = recursive_set(tl, this.dropdown, value)

  --
  -- A value that none of the items has, nil included, leaves nothing chosen. Keeping the last item on show would say the
  -- dropdown holds a value it does not.
  --
  if (not ret and tl.mode == MODE_SINGLE and tl.current) then
    tl.current.checked = false
    if (tl.current.checkmark) then
      tl.current.checkmark:Hide()
    end
    tl.current = nil
  end

  --
  -- With nothing chosen the box says what it is for, where it was given a title. A SINGLE dropdown otherwise shows its value
  -- and has no use for one, so a caller that names it there means the words to stand in until there is a value to show. An
  -- item that is a frame of its own has no words at all, and the box shows nothing rather than naming itself under it.
  --
  if (tl.mode == MODE_SINGLE) then
    if (tl.current and tl.current.text) then
      this.text:SetFontObject(tl.valuefont)
      this.text:SetText(tl.current.text:GetText())
    elseif (tl.current) then
      this.text:SetText("")
    else
      this.text:SetFontObject(tl.titlefont)
      this.text:SetText(tl.emptytext or "")
    end

    KIT.ddpaint(tl)
  end

  if (ret) then
    if (not nothrow) then
      tl:Throw("OnValueChanged", value, false)
    end
  end

  return ret
end

function DD.OnEnable(this, event, onoff)
  local onoff = onoff or false

  this.enabled = onoff

  local button = this.button

  button.enabled = onoff
  KIT.sync(button)

  -- A disabled dropdown shows its dark middle, as a disabled button does.
  if (this.fill) then
    this.fill:SetShown(onoff)
  end

  if (onoff) then
    button:Enable()
  else
    button:Disable()
    if (this.dropdown) then
      this.dropdown:Close()
    else
      if (this.subopen) then
        this.subopen:Close()
        this.subopen = nil
      end
    end
  end

  local d = onoff and 1 or 2
  if (this.label) then
    this.label:SetTextColor(this.labelcolor.r/d, this.labelcolor.g/d, this.labelcolor.b/d, this.labelcolor.a)
  end

  if (this.dropdown) then
    if (this.mode ~= MODE_SINGLE) then
      local tc = this.kuichanged and KUI.DEFAULT_CHANGED_COLOR or this.trgb

      if (tc) then
        this.text:SetTextColor(tc.r/d, tc.g/d, tc.b/d, tc.a or 1)
      end
    else
      KIT.ddpaint(this)
    end
  end
end

--
-- This is the workhorse function that creates the functional part of a dropdown menu or a popup menu. This is the bit that
-- contains the actual items. It can call itself recursively if any of the items have submenus. If this is the top-level
-- menu, it is what is returned to the caller and has two functions which each child must call when the cursor is over the
-- child: StopTimeoutCounter() when the cursor moves into a child frame and StartTimeoutCounter() when it leaves.
--
function DD.create_sa(cfg, parent, toplevel, ispopup)
  assert(cfg, "dropdown config must be provided")
  assert(cfg.name, "you must provide a frame name")
  assert(cfg.items, "dropdown items must be provided ("..cfg.name..")")

  if (toplevel) then
    assert(toplevel.StopTimeoutCounter, "toplevel specified incorrectly")
    assert(toplevel.StartTimeoutCounter, "toplevel specified incorrectly")
  end

  local nitems = 0
  for k,v in ipairs(cfg.items) do
    nitems = nitems + 1
    assert(v.text or v.frame, "must provide text or a custom frame")
  end
  assert(nitems > 0, "must provide at least 1 item")

  local frame

  if (not toplevel and not ispopup) then
    assert(cfg.dwidth, "must provide dropdown width (dwidth)")
    --
    -- This is a "dropdown" style frame. This has a controlling UI element that does not change, and then the actual dropped
    -- down portion which might. This is where we create the controlling UI element which will "house" the countdown timers
    -- and other events. The actual dropped down portion that will be displayed when the downarrow button is pressed is
    -- created by a recursive call to this function below.
    --
    local ppf
    --
    -- The closed dropdown is the rounded pill a button is by default, with a chevron standing just inside its right hand end,
    -- and the whole pill is what the pointer clicks. It wears a fill wherever a button would, cfg.buttonfill deciding both.
    -- The frame is the size of the pill because GetHeight has to be able to answer "where does the next widget go".
    --
    frame, ppf = newobj(cfg, parent, 100, KUI.DROPDOWN_HEIGHT, cfg.name .. "DDContainer")
    frame:SetWidth(cfg.dwidth)
    frame:SetHeight(KUI.DROPDOWN_HEIGHT)

    local pill = KIT.new(frame, KIT.BUTTONS.ROUNDED, { layer = "BACKGROUND" })
    pill:SetBox(frame, 0, 0, 0, 0, KUI.DROPDOWN_HEIGHT)
    frame.pill = pill

    local chevron = KIT.new(frame, "DropdownChevron", { layer = "ARTWORK" })
    local cvh = KIT.DD_CHEVRON
    chevron.box:SetPoint("RIGHT", frame, "RIGHT", 0 - KIT.DD_CHEVRON_RIGHT, 0)
    chevron.box:SetSize(cvh * chevron.def.aspect, cvh)
    chevron:Layout()

    local text = frame:CreateFontString(frame:GetName() .. "Text", "ARTWORK")
    frame.text = text
    frame.valuefont = "GameFontHighlightSmall"
    text:SetFontObject(frame.valuefont)
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", KUI.DROPDOWN_TEXT_LEFT, 0)
    text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - KUI.DROPDOWN_TEXT_RIGHT, 0)
    text:SetWordWrap(false)

    local button = MakeFrame("Button", frame:GetName() .. "Button", frame)
    frame.button = button
    button.toplevel = frame
    button:ClearAllPoints()
    button:SetAllPoints(frame)
    frame.fill = KIT.buttonfill(frame, KIT.BUTTONS.ROUNDED, KUI.DROPDOWN_HEIGHT)
    KIT.interactive(button, pill, chevron, frame.fill)

    frame.OnEnable = DD.OnEnable
    frame.SetJustification = DD.SetJustification
    frame.UpdateItems = DD.UpdateItems
    frame.GetValue = DD.GetValue
    frame.SetValue = DD.SetValue
    -- What a dropdown showing its title is given to say becomes that title, so that new items do not put the old one back.
    frame.SetText = function(this, text)
      if (this.mode ~= MODE_SINGLE) then
        this.titletext = text
      end

      return this.text:SetText(text)
    end
    frame.GetText = function(this, ...) return this.text:GetText(...) end
    frame.SetTextColor = function(this, ...) return this.text:SetTextColor(...) end
    frame.GetTextColor = function(this, ...) return this.text:GetTextColor(...) end
    frame.SetFont = function(this, ...) return this.text:SetFont(...) end
    frame.GetFont = function(this, ...) return this.text:GetFont(...) end

    button:SetScript("OnEnter", DD.OnEnter)
    button:SetScript("OnLeave", DD.OnLeave)
    button:SetScript("OnClick", DD.OnClick)

    frame:SetJustification(cfg.justifyh or "LEFT")

    --
    -- Dropdowns can also have a label. Deal with that now.
    --
    if (cfg.label) then
      local lfont = cfg.label.font or "GameFontNormal"
      local lwidth = cfg.label.width or (KUI:MeasureStrWidth(cfg.label.text, lfont) + 4)
      local label = frame:CreateFontString(nil, "ARTWORK", lfont)
      frame.label = label
      frame.labelcolor = KUI:GetFontColor(lfont, true)
      if (cfg.label.color) then
        frame.labelcolor.r = cfg.label.color.r
        frame.labelcolor.g = cfg.label.color.g
        frame.labelcolor.b = cfg.label.color.b
        frame.labelcolor.a = cfg.label.color.a or 1
      end
      label:SetHeight(16)

      --
      -- A label beside the dropdown is as wide as it measured, where the dropdown goes being worked out from that. One above
      -- or below is a heading and is given no width unless asked for one, so it is as wide as whatever it says, including
      -- whatever it is told to say later, rather than cut off at what it said first.
      --
      if (cfg.label.width or cfg.label.pos == "LEFT" or cfg.label.pos == "RIGHT") then
        label:SetWidth(lwidth)
      end

      label:SetJustifyH(cfg.label.justifyh or "LEFT")
      label:SetJustifyV(cfg.label.justifyv or "MIDDLE")
      label:SetText(cfg.label.text or "")
      check_tooltip_title(frame, cfg, cfg.label.text)

      if (cfg.label.pos == "LEFT") then
        label:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, -4)
        if (cfg.x) then
          if (cfg.x == "CENTER") then
            frame:SetPoint("CENTER", ppf, "CENTER", (lwidth/2)*-1, 0)
          else
            frame:SetPoint("LEFT", ppf, "LEFT", cfg.x + lwidth + 4, 0)
          end
        end
      elseif (cfg.label.pos == "RIGHT") then
        label:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, -4)
        if (cfg.x and cfg.x == "CENTER") then
          frame:SetPoint("CENTER", ppf, "CENTER", (lwidth/2)*-1, 0)
        end
      elseif (cfg.label.pos == "BOTTOM") then
        label:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
      else -- Assume TOP
        label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
        if (cfg.y) then
          --
          -- The label sits above the widget, so the pair of them is what has to be centred or placed: the widget goes half
          -- the difference below the centre, and cfg.y is where the label starts rather than where the widget does. Both are
          -- asked of the label rather than assumed, which is what CreateEditBox does with the same case.
          --
          local lh = label:GetHeight()

          if (cfg.y == "MIDDLE") then
            frame:SetPoint("TOP", ppf, "CENTER", 0, (frame:GetHeight() - lh) / 2)
          else
            frame:SetPoint("TOP", ppf, "TOP", 0, cfg.y - lh)
          end
        end
      end

      if (cfg.label.pos == "BOTTOM") then
        drawn_extent(frame, 0, label:GetHeight())
      elseif (cfg.label.pos ~= "LEFT" and cfg.label.pos ~= "RIGHT") then
        drawn_extent(frame, label:GetHeight(), 0)
      end
    end
  else -- Not the container portion of a dropdown
    if (not toplevel) then
      frame = newobj(cfg, parent, 100, 100, cfg.name)
    else
      if (KUI.ddframes[cfg.name]) then
        frame = KUI.ddframes[cfg.name]
        frame:SetParent(parent or UIParent)
      else
        frame = MakeFrame("Frame", cfg.name, parent or UIParent)
        frame.SetEnabled = BC.SetEnabled
        frame.SetShown = BC.SetShown
        KUI.ddframes[cfg.name] = frame
      end
    end
  end
  frame:Show()

  if (frame.subopen) then
    frame.subopen:Close()
    frame.subopen = nil
  end

  frame.toplevel = toplevel or frame
  frame.height = cfg.height
  frame.width = cfg.width
  -- @debug-start@
  frame.debug = cfg.debug
  -- @debug-end@

  if (toplevel) then
    frame.border = toplevel.border
    frame.mode = toplevel.mode
  else
    frame:SetFrameLevel(frame:GetFrameLevel() + 8 + (ispopup and 8 or 0))
    if (cfg.escclose or not ispopup) then
      add_escclose(cfg.name)
    else
      remove_escclose(cfg.name)
    end

    frame.timeout = cfg.timeout or 0
    if (cfg.border == "THICK") then
      frame.border = 2
    else
      frame.border = 1
    end

    frame.lastpos = {}
    if (ispopup) then
      frame.mode = nil
      frame.SetEnabled = nil
      frame.OnStopMoving = function(this, evt)
        this.lastpos = {}
      end
    else
      if (cfg.mode == "MULTI") then
        frame.mode = MODE_MULTI
      elseif (cfg.mode == "COMPACT") then
        frame.mode = MODE_COMPACT
      else
        frame.mode = MODE_SINGLE
      end
    end
  end

  frame.arg = cfg.arg
  frame.func = cfg.func
  frame.items = cfg.items
  frame.itemheight = cfg.itemheight or frame.toplevel.itemheight
  frame.is_enabled = cfg.is_enabled
  frame.is_checked = cfg.is_checked
  frame.minheight = cfg.minheight or frame.toplevel.minheight
  frame.minwidth = cfg.minwidth or frame.toplevel.minwidth
  frame.maxheight = cfg.maxheight or frame.toplevel.maxheight
  frame.maxwidth = cfg.maxwidth or frame.toplevel.maxwidth

  if (not toplevel) then
    frame.StopTimeoutCounter = stop_countdown
    frame.StartTimeoutCounter = start_countdown
    frame:UnregisterAllEvents()
    if (ispopup) then
      frame:SetFrameStrata(cfg.strata or "FULLSCREEN_DIALOG")
      frame:RegisterEvent("PLAYER_REGEN_ENABLED")
      frame:RegisterEvent("PLAYER_REGEN_DISABLED")
      frame:HookScript("OnEvent", TL.OnEvent)
    end
    frame:HookScript("OnShow", TL.OnShow)
    frame:HookScript("OnHide", TL.OnHide)
  else
    frame.StopTimeoutCounter = nil
    frame.StartTimeoutCounter = nil
    frame:SetFrameStrata(toplevel:GetFrameStrata())
  end

  frame.Close = DD.Close
  frame:EnableMouse(true)

  --
  -- A submenu's frame is kept by name and built again every time the menu holding it is, so what is hooked is hooked once.
  -- HookScript adds a handler each time it is called and never replaces one.
  --
  if (not frame.kuimenuhooked) then
    frame.kuimenuhooked = true
    frame:HookScript("OnEnter", TL.OnEnter)
    frame:HookScript("OnLeave", TL.OnLeave)
    frame:HookScript("OnShow", DD.secure_attach)
    frame:HookScript("OnHide", DD.secure_release)
  end

  if (not toplevel and not ispopup) then
    --
    -- DropDown menu. Create the actual portion that is dropped down when the button is pressed. Simply create the dropdown
    -- frame and return the container.
    --
    frame.dropdown = DD.create_sa(cfg, frame, frame, false)
    frame.dropdown:SetFrameLevel(frame.dropdown:GetFrameLevel() + 4)
    frame.dropdown:ClearAllPoints()
    frame.dropdown:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)

    -- Closing a dropdown closes its menu, the pill staying where it is.
    frame.Close = function(this)
      this.dropdown:Close()
    end

    --
    -- An open menu covers what is around it, and standing four levels above its own button does not promise that. A window's
    -- panels nest deep enough that the widgets in them sit above any fixed number, so a menu dropped near the top of a panel
    -- is drawn under the checkboxes below it and under the panel after that. It is lifted above its whole window each time it
    -- opens instead, which is what KIT.popupraise does and what a popup list has always done.
    --
    -- Hooked once. These frames are kept by name and built again whenever the menu holding them is, and HookScript adds a
    -- handler every time it is called rather than replacing the one that is there.
    --
    if (not frame.dropdown.kuiraisehooked) then
      frame.dropdown.kuiraisehooked = true
      frame.dropdown:HookScript("OnShow", KIT.popupraise)
    end
    if (frame.mode ~= MODE_SINGLE) then
      local tfont = cfg.title.font or "GameFontNormalSmallLeft"
      frame.text:SetFontObject(tfont)
      frame.text:SetText(cfg.title.text)
      frame.titletext = cfg.title.text
      frame.trgb = KUI:GetFontColor(tfont, true)
      if (cfg.title.color) then
        frame.trgb.r = cfg.title.color.r
        frame.trgb.g = cfg.title.color.g
        frame.trgb.b = cfg.title.color.b
        frame.trgb.a = cfg.title.color.a or 1
      end
      check_tooltip_title(frame, cfg, cfg.title.text)
    else -- MODE_SINGLE
      --
      -- A title here is what the box says until there is a value to say instead, worn in the title font and colour rather
      -- than in the white the value comes out in, so that naming the box cannot be read as an answer in it.
      --
      frame.emptytext = cfg.title and cfg.title.text or nil
      frame.titlefont = (cfg.title and cfg.title.font) or "GameFontNormalSmallLeft"
      frame.trgb = KUI:GetFontColor(frame.titlefont, true)

      if (cfg.title and cfg.title.color) then
        frame.trgb.r = cfg.title.color.r
        frame.trgb.g = cfg.title.color.g
        frame.trgb.b = cfg.title.color.b
        frame.trgb.a = cfg.title.color.a or 1
      end

      local head = DD.headtext(frame)

      if (frame.current and frame.current.text) then
        frame.text:SetText(frame.current.text:GetText())
      elseif (head) then
        frame.text:SetText(head)
      else
        frame.text:SetFontObject(frame.titlefont)
        frame.text:SetText(frame.emptytext or "")
        KIT.ddpaint(frame)
      end
    end

    if (cfg.initialvalue ~= nil) then
      frame:SetValue(cfg.initialvalue)
    end

    frame:SetEnabled(cfg_enabled(cfg))
    return frame
  end

  --
  -- From this point on no longer deal with the dropdown container. We deal with the actual menu items or dropdown items.
  --
  -- A menu is the thin border or the thick one around a near-black ground. A menu frame is kept and rebuilt rather than made
  -- afresh, so its art is made once and only shown or hidden after that.
  --
  local bstyle = (frame.border == 2) and "THICK" or "THIN"
  local bs = KIT.BORDERS[bstyle]

  frame.offset = bs.offset

  if (not frame.menuground) then
    frame.menuground = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.menuground:SetColorTexture(0, 0, 0, KIT.MENU_GROUND)
    frame.menurims = {}
  end

  for k, rim in pairs(frame.menurims) do
    rim:SetShown(k == bstyle)
  end

  if (not frame.menurims[bstyle]) then
    local rim = KIT.border(frame, bs.piece, bs.rim, { layer = "BORDER" })
    rim:SetFrameBox(frame, 0, 0, 0, 0)
    frame.menurims[bstyle] = rim
  end

  KIT.fitground(frame.menuground, frame, frame.menurims[bstyle])

  --
  -- Now we create the scrollframe and fit it just inside the borders of the container frame. If this is a popup menu we
  -- allow the user to reserve space at the top and bottom of the frame for a header and a footer.
  --
  local sframe = frame.sframe
  local cframe = frame.cframe
  local hframe = frame.header
  local fframe = frame.footer
  if (not frame.sframe) then
    sframe = MakeFrame("ScrollFrame", nil, frame)
    frame.sframe = sframe
    sframe.toplevel = frame.toplevel
    sframe:HookScript("OnEnter", TL.OnEnter)
    sframe:HookScript("OnLeave", TL.OnLeave)
  end

  if (not frame.cframe) then
    cframe = MakeFrame("Frame", frame:GetName() .. "Child", sframe)
    frame.cframe = cframe
    cframe.toplevel = frame.toplevel
    cframe:HookScript("OnEnter", TL.OnEnter)
    cframe:HookScript("OnLeave", TL.OnLeave)
  end

  frame.headeroffset = 0
  frame.footeroffset = 0

  if (ispopup) then
    if (cfg.header) then
      frame.headeroffset = cfg.header
      if (not frame.header) then
        hframe = MakeFrame("Frame", frame:GetName() .. "Header", frame)
        frame.header = hframe
        hframe.toplevel = frame.toplevel
        hframe:HookScript("OnEnter", TL.OnEnter)
        hframe:HookScript("OnLeave", TL.OnLeave)
      end
      hframe:ClearAllPoints()
      hframe:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.offset, -frame.offset)
      hframe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -frame.offset, -frame.offset)
      hframe:SetHeight(cfg.header)
    end

    if (cfg.footer) then
      frame.footeroffset = cfg.footer
      if (not frame.footer) then
        fframe = MakeFrame("Frame", frame:GetName() .. "Footer", frame)
        frame.footer = fframe
        fframe.toplevel = frame.toplevel
        fframe:HookScript("OnEnter", TL.OnEnter)
        fframe:HookScript("OnLeave", TL.OnLeave)
      end
      fframe:ClearAllPoints()
      fframe:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", frame.offset, frame.offset)
      fframe:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -frame.offset, frame.offset)
      fframe:SetHeight(cfg.footer)
    end
  end

  sframe:SetScrollChild(cframe)
  sframe:ClearAllPoints()
  sframe:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.offset, -(frame.offset + frame.headeroffset))
  sframe:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -frame.offset, frame.offset + frame.footeroffset)
  sframe:EnableMouse(true)
  sframe:EnableMouseWheel(true)
  cframe:EnableMouse(true)

  local sbar = frame.scrollbar
  if (not frame.scrollbar) then
    sbar = MakeFrame("Slider", nil, frame)
    frame.scrollbar = sbar

    -- Hooked once, when made, the frame being kept and built again.
    sbar:HookScript("OnMouseWheel", DD.OnMouseWheel)
    sbar:HookScript("OnValueChanged", DD.OnValueChanged)
    sbar:HookScript("OnEnter", parent_OnEnter)
    sbar:HookScript("OnLeave", parent_OnLeave)
    -- Scrolling moves which items are in sight, and so which the secure buttons cover.
    sbar:HookScript("OnValueChanged", function()
      DD.secure_attach(frame)
    end)

    sframe:HookScript("OnMouseWheel", DD.OnMouseWheel)
    sframe:HookScript("OnScrollRangeChanged", DD.OnScrollRangeChanged)
  end
  sbar:SetOrientation("VERTICAL")
  sbar:ClearAllPoints()
  sbar:SetPoint("TOPLEFT", sframe, "TOPLEFT", -12, 0)
  sbar:SetPoint("BOTTOMRIGHT", sframe, "BOTTOMLEFT", -4, 0)
  sbar:EnableMouse(true)
  sbar:EnableMouseWheel(true)

  --
  -- A menu's bar is only a thumb, narrow enough to sit in the menu's margin, drawn in pieces on the thumb texture the engine
  -- moves while the texture itself draws nothing.
  --
  if (not sbar.thumbrim) then
    sbar:SetThumbTexture(KIT.sheet())

    local sbt = sbar:GetThumbTexture()
    sbt:SetWidth(8)
    sbt:SetHeight(16)
    sbt:SetAlpha(0)

    sbar.thumbrim = KIT.new(sbar, "ScrollThumbVertical", { layer = "ARTWORK" })
    sbar.thumbrim.box:SetAllPoints(sbt)
    sbar.thumbrim:Layout(8)
  end
  sbar:Hide()

  if (not toplevel and cfg.canmove and ispopup) then
    --
    -- If we want a moveable frame, we can only do so by click-dragging on the very top of the frame, along its border. We
    -- want to set up a target zone for registering those clicks which means we need to create yet another frame.
    --
    frame:SetMovable(true)
    local mframe = frame.mframe
    if (not frame.mframe) then
      mframe = MakeFrame("Frame", nil, frame)
      frame.mframe = mframe
    end
    mframe:ClearAllPoints()
    mframe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    mframe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    mframe:SetHeight(frame.offset)
    mframe:EnableMouse(true)
    mframe:SetScript("OnMouseDown", parent_StartMoving)
    mframe:SetScript("OnMouseUp", parent_StopMoving)
    mframe:SetScript("OnEnter", parent_OnEnter)
    mframe:SetScript("OnLeave", parent_OnLeave)
    mframe:Show()
  else
    frame:SetMovable(false)
    if (frame.mframe) then
      frame.mframe:ClearAllPoints()
      frame.mframe:Hide()
    end
  end

  local swframe, seframe, soframe = make_resizeable(frame, frame.offset + 10,
    cfg.canresize, frame.swframe, frame.seframe, frame.soframe)

  if (swframe) then
    frame.swframe = swframe
    swframe:SetScript("OnEnter", parent_OnEnter)
    swframe:SetScript("OnLeave", parent_OnLeave)
  end

  if (seframe) then
    frame.seframe = seframe
    seframe:SetScript("OnEnter", parent_OnEnter)
    seframe:SetScript("OnLeave", parent_OnLeave)
  end

  if (soframe) then
    frame.soframe = soframe
    soframe:SetScript("OnEnter", parent_OnEnter)
    soframe:SetScript("OnLeave", parent_OnLeave)
  end

  if (not frame:IsResizable()) then
    frame:SetScript("OnSizeChanged", nil)
    if (frame.seframe) then
      frame.seframe:Hide()
      frame.seframe:ClearAllPoints()
    end
    if (frame.swframe) then
      frame.swframe:Hide()
      frame.swframe:ClearAllPoints()
    end
    if (frame.soframe) then
      frame.soframe:Hide()
      frame.soframe:ClearAllPoints()
    end
  end

  --
  -- kframes is used to store the names of the various child frames we have created. Since every line element in a menu is
  -- actually a frame, and we can change the appearance or values of each of those frames at any time, we do not want to
  -- create more frames than we need, so we keep track of the child frames we create. Note that this table tracks only the
  -- item entry frames, it does not store the frame pointers for submenu frames (see below for those). A frame built again
  -- keeps the item frames it made before, which are named and would otherwise be made afresh under the same names, and the old ones lost.
  --
  frame.kframes = frame.kframes or {}

  -- A popup menu is its own top level and is handed new items the way a dropdown is.
  if (ispopup) then
    frame.UpdateItems = DD.UpdateItems
  end

  DD.refresh_frame(frame, toplevel, cfg.items, nitems)
  frame:Hide()

  return frame
end

function KUI:CreateDropDown(cfg, parent)
  return DD.create_sa(cfg, parent, nil, false)
end

--
-- A popup menu stands over the window it belongs to, as a popup list does, whatever level that window has been raised to
-- since the menu was made.
--
function KUI:CreatePopupMenu(cfg, parent)
  local ret = DD.create_sa(cfg, parent, nil, true)

  ret:HookScript("OnShow", KIT.popupraise)
  return ret
end

--
-- Helper function for creating custom frames as popup item widgets.
--
-- The getbutton function a radio item in a menu is given, a menu item being a frame with the button inside it.
--
function RADIO.getbutton(this)
  return this.frame or this
end

--
-- This is a mixture of a popup menu and a scroll list, but wrapped in a dialog frame. It is meant for popping up long lists
-- of names. It uses the more space efficient ScrollList rather than using a popup menu which is unsuited to arbitrarily long lists of names.
--
function POP.settext(self, txt)
  self.text:SetText(txt)
end

function POP.onclick(this)
  local idx = this:GetID()
  local tlf = this.toplevel

  tlf.slist:SetSelected(idx, false)
  if (tlf.func) then
    tlf.func(tlf.selectionlist, idx, tlf.arg)
  end
  if (not tlf.keep) then
    tlf:Hide()
  end
end

--
-- A popup list closes itself TIMEOUT seconds after the pointer leaves it, and never if TIMEOUT is 0. The countdown starts
-- only when the pointer leaves, not when the list opens, so a list opened from somewhere else stays open until it has been used or left.
--
function POP.onleave(this)
  this.toplevel:StartTimeoutCounter()
end

function POP.onhide(this)
  this.toplevel:StopTimeoutCounter()
end

POP.onenter = POP.onhide

function POP.newitem(objp, num)
  local nm = objp:GetName() .. "Button"
  local tlf = objp.toplevel
  local rf = KUI.NewItemHelper(objp, num, nm, tlf.itemwidth, tlf.itemheight, POP.settext, POP.onclick, nil, nil)
  rf.toplevel = tlf
  rf:HookScript("OnEnter", POP.onenter)
  rf:HookScript("OnLeave", POP.onleave)
  return rf
end

function POP.setitem(objp, idx, slot, btn)
  local tlf = objp.toplevel

  if (tlf.textfunc) then
    btn:SetText(tlf.textfunc(tlf.selectionlist, idx, tlf.arg))
  else
    local tbl = tlf.selectionlist
    if (type(tbl[idx]) == "string") then
      btn:SetText(tbl[idx])
    elseif (type(tbl[idx]) == "table") then
      btn:SetText(tbl[idx].text)
    else
      assert(false)
    end
  end
end

function POP.selectitem(objp, idx, slot, btn, onoff)
end

function POP.highlightitem(objp, idx, slot, btn, onoff)
  return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff, nil, nil)
end

function POP.onupdate(this)
  local now = GetTime()
  if ((now - this.timeout_start) > this.timeout) then
    this:SetScript("OnUpdate", nil)
    this.timeout_start = 0
    this:Hide()
  end
end

function POP.startcountdown(this)
  if (this.timeout <= 0) then
    return
  end

  this.timeout_start = GetTime()
  this:SetScript("OnUpdate", POP.onupdate)
end

function POP.stopcountdown(this)
  this:SetScript("OnUpdate", nil)
end

function POP.updatelist(this, nlist)
  this.selectionlist = nlist
  local x
  if (not nlist) then
    x = 0
  else
   x = #nlist
  end
  local ga = this.headerspace + this.footerspace + (2 * this.borderoffset)
  local mh = ((x + 1) * this.itemheight) + ga

  --
  -- As tall as the items need, or as the caller asked if that is less, and no shorter to drag than two rows unless the items
  -- need less than that, a minimum above the maximum being no bounds at all.
  --
  local h = this.uheight and min(mh, this.uheight) or mh
  local mnh = min((2 * this.itemheight) + ga + 48, mh)
  local mnw, _, mxw, _ = this:GetResizeBounds()
  this.height = h
  this:SetResizeBounds(mnw, mnh, mxw, mh)
  this:SetHeight(h)
  this.slist.itemcount = x
  this.slist:UpdateList()
end

--
-- Take every item whose value is VALUE out of the list the popup is showing, and show what is left. The list is the caller's
-- own table, given to UpdateList, and is changed in place. A list of plain strings has no values and is left alone.
--
function KIT.popupremovevalue(this, value)
  local lst = this.selectionlist

  if (not lst) then
    return
  end

  for i = #lst, 1, -1 do
    if (type(lst[i]) == "table" and lst[i].value == value) then
      tremove(lst, i)
    end
  end

  POP.updatelist(this, lst)
end

--
-- Put ITEM, a table with text and value or a plain string, into the list the popup is showing at POS, or at the end without
-- one, and show the list. A popup with no list yet starts one. A caller keeping its list in an order puts the item where that
-- order says, which only the caller knows.
--
function KIT.popupadditem(this, item, pos)
  local lst = this.selectionlist or {}

  if (pos) then
    tinsert(lst, max(1, min(pos, #lst + 1)), item)
  else
    tinsert(lst, item)
  end

  POP.updatelist(this, lst)
end

function POP.hook(fr)
  fr:HookScript("OnHide", POP.onhide)
  fr:HookScript("OnEnter", POP.onenter)
  fr:HookScript("OnLeave", POP.onleave)
end

--
-- Lift the popup POP above everything in the window it is part of. A popup is parented into a window, often a page, and shares
-- its strata, so a fixed level is not enough: a window's panels nest deep enough that the buttons in them sit above any number
-- picked, and would be drawn over the popup. So each time it shows, the popup goes one above the highest level anywhere in its
-- window, its own frames aside.
--
-- KUI.MakeFrame's hook puts every child one level above its parent when the parent's level is set, which would flatten the
-- popup's own frames and bury the ones set higher on purpose, its close button above its list. So every frame in the popup
-- is put back the same distance above it that it was, parents before children, since setting a parent flattens what is under it.
--
function KIT.popupraise(pop)
  local top = pop:GetParent()

  while (top and top:GetParent() and top:GetParent() ~= UIParent) do
    top = top:GetParent()
  end

  if (not top or top == UIParent) then
    return
  end

  KUI:SetFrameLevelKeeping(pop, min(KUI:HighestFrameLevel(top, pop) + 1, 9000))
end

--
-- The highest frame level anywhere in FRAME, its own and every frame under it. SKIP and everything under it are left out,
-- which is how a popup measures the window it is part of without measuring itself.
--
function KUI:HighestFrameLevel(frame, skip)
  local function highest(f, best)
    if (f == skip) then
      return best
    end

    best = max(best, f:GetFrameLevel())
    for _, child in ipairs({ f:GetChildren() }) do
      best = highest(child, best)
    end
    return best
  end

  return highest(frame, 0)
end

--
-- Put FRAME at LEVEL, with every frame under it standing the same distance above it as it did.
--
-- KUI.MakeFrame hooks SetFrameLevel to put every child one above its parent, which flattens whatever is under the frame and
-- buries the frames set higher on purpose, a panel's plaque above its content. And every call through the hook sets the
-- whole subtree again, each of those calls doing the same below it, so moving a window that way costs twice as much for each
-- level it is deep. So every level is measured first and then set through the frame type's own SetFrameLevel, which the
-- hook never sees, a parent before its children.
--
function KUI:SetFrameLevelKeeping(frame, level)
  local base = frame:GetFrameLevel()
  local all = {}

  local function record(f)
    tinsert(all, f)
    tinsert(all, f:GetFrameLevel() - base)
    for _, child in ipairs({ f:GetChildren() }) do
      record(child)
    end
  end
  record(frame)

  for i = 1, #all, 2 do
    local f = all[i]
    getmetatable(f).__index.SetFrameLevel(f, level + all[i + 1])
  end
end

--
-- Windows. Every dialog and tabbed dialog made straight onto UIParent is a window, and windows stack as whole things rather
-- than having their frames interleave where two overlap. Each is given a band of frame levels of its own, starting
-- WINDOW_LEVEL_GAP above the highest level in the window below it, which leaves room for a popup a window raises over itself.
--
-- KIT.windows is the order they stack in, bottom first. Showing a window puts it on top, and so does a click anywhere in one
-- that is not already on top. Only shown windows are given a band, a hidden one being placed as it is shown.
--
KUI.WINDOW_LEVEL_BASE = 10
KUI.WINDOW_LEVEL_GAP = 32

KIT.windows = {}

function KIT.restack()
  local level = KUI.WINDOW_LEVEL_BASE

  for _, win in ipairs(KIT.windows) do
    if (win:IsShown()) then
      if (win:GetFrameLevel() ~= level) then
        KUI:SetFrameLevelKeeping(win, level)
      end
      level = min(KUI:HighestFrameLevel(win) + KUI.WINDOW_LEVEL_GAP, 9000)
    end
  end
end

--
-- A window is raised when something shows it, which is a call to its Show, and KoreUI's SetShown is one. The OnShow script is
-- not what is watched, because it also runs for every window on screen when UIParent comes back after Alt-Z, one after
-- another in whatever order the engine picks, which would restack them all in that order.
--
function KIT.addwindow(frame)
  tinsert(KIT.windows, frame)
  KIT.iswindow[frame] = true
  hooksecurefunc(frame, "Show", function(this)
    KUI:RaiseWindow(this)
  end)
end

--
-- Put window WIN on top of every other window.
--
function KUI:RaiseWindow(win)
  for i = #KIT.windows, 1, -1 do
    if (KIT.windows[i] == win) then
      tremove(KIT.windows, i)
    end
  end

  tinsert(KIT.windows, win)
  KIT.restack()
end

--
-- Stack the windows in LIST in that order, the first lowest, under every window LIST does not name.
--
function KUI:SetWindowOrder(list)
  local named = {}
  local order = {}

  for _, win in ipairs(list) do
    named[win] = true
    tinsert(order, win)
  end

  for _, win in ipairs(KIT.windows) do
    if (not named[win]) then
      tinsert(order, win)
    end
  end

  KIT.windows = order
  KIT.restack()
end

--
-- A click anywhere in a window raises it, a click on a button deep inside it included. The game says a mouse button went down
-- and nothing more, so the window it went down in is the topmost shown one the pointer is over.
--
KIT.clickwatch = CreateFrame("Frame")
KIT.clickwatch:SetScript("OnEvent", function()
  local top = nil

  for i = #KIT.windows, 1, -1 do
    local win = KIT.windows[i]

    if (win:IsVisible()) then
      top = top or win
      if (win:IsMouseOver()) then
        if (win ~= top) then
          KUI:RaiseWindow(win)
        end
        return
      end
    end
  end
end)
KIT.clickwatch:RegisterEvent("GLOBAL_MOUSE_DOWN")

function KUI:CreatePopupList(cfg, parent)
  assert(cfg.name)

  local arg = {
    x = cfg.x,
    y = cfg.y,
    name = cfg.name,
    border = cfg.border,
    width = cfg.width,
    height = cfg.height,
    title = cfg.title,
    minwidth = cfg.minwidth,
    maxwidth = cfg.maxwidth,
    minheight = cfg.minheight,
    maxheight = cfg.maxheight,
    canmove = cfg.canmove,
    canresize = cfg.canresize,
    escclose = cfg.escclose,
    blackbg = cfg.blackbg,
    -- A popup that stays open when an item is picked has to be closable some other way than by picking one.
    xbutton = (cfg.xbutton or cfg.keep) and true or false,
    level = cfg.level or 24,
    -- A popup covers whatever it is put up over, as a popup menu does.
    strata = "FULLSCREEN_DIALOG",
  }
  local ret = KUI:CreateDialogFrame(arg, cfg.parent or parent)
  ret:HookScript("OnShow", KIT.popupraise)
  ret.keep = cfg.keep and true or false

  --
  -- A popup's close button sits over the top right corner of its rim. The popup's list is not moved down for it: what shares
  -- the top of the popup with the button is the header, for a caller to put something in.
  --
  if (ret.xbutton) then
    ret.xbutton:ClearAllPoints()
    ret.xbutton:SetPoint("CENTER", ret, "TOPRIGHT", -10, -10)
  end
  ret.toplevel = ret
  ret.content.toplevel = ret
  local c = ret.content
  local tlf = c
  local brf = c
  local tlp = "TOPLEFT"
  local brp = "BOTTOMRIGHT"

  POP.hook(ret)
  POP.hook(ret.content)
  if (ret.title) then
    ret.title.toplevel = ret
    POP.hook(ret.title)
  end
  if (ret.mframe) then
    ret.mframe.toplevel = ret
    POP.hook(ret.mframe)
  end

  ret.headerspace = 0
  ret.footerspace = 0
  if (cfg.header) then
    ret.headerspace = cfg.header
    ret.header = MakeFrame("Frame", nil, c)
    ret.header.toplevel = ret
    ret.header:ClearAllPoints()
    ret.header:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    ret.header:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    ret.header:SetHeight(cfg.header)
    tlf = ret.header
    tlp = "BOTTOMLEFT"
    POP.hook(ret.header)
  end

  if (cfg.footer) then
    ret.footerspace = cfg.footer
    ret.footer = MakeFrame("Frame", nil, c)
    ret.footer.toplevel = ret
    ret.footer:ClearAllPoints()
    ret.footer:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
    ret.footer:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    ret.footer:SetHeight(cfg.footer)
    brf = ret.footer
    brp = "TOPRIGHT"
    POP.hook(ret.footer)
  end

  if (ret.header or ret.footer) then
    ret.cframe = MakeFrame("Frame", nil, c)
    ret.cframe:ClearAllPoints()
    ret.cframe:SetPoint("TOPLEFT", tlf, tlp, 0, 0)
    ret.cframe:SetPoint("BOTTOMRIGHT", brf, brp, 0, 0)
  else
    ret.cframe = ret.content
  end

  ret.arg = cfg.arg
  ret.textfunc = cfg.textfunc
  ret.func = cfg.func
  ret.timeout = cfg.timeout or 0
  ret.itemheight = cfg.itemheight or 16
  ret.itemwidth = cfg.itemwidth or 160
  ret.uheight = cfg.height

  arg = {
    name = cfg.name .. "ScrollList",
    itemheight = ret.itemheight,
    newitem = POP.newitem,
    setitem = POP.setitem,
    selectitem = POP.selectitem,
    highlightitem = POP.highlightitem,
    __noh__ = ret,
    newobjhook = function(fr,cf,pr,wd,ht)
      fr.toplevel = cf.__noh__
    end,
  }
  ret.StopTimeoutCounter = POP.stopcountdown
  ret.StartTimeoutCounter = POP.startcountdown
  ret.cframe.toplevel = ret
  ret.slist = KUI:CreateScrollList(arg, ret.cframe)
  ret.slist.toplevel = ret
  POP.hook(ret.slist)
  ret.slist.scrollbar.toplevel = ret
  POP.hook(ret.slist.scrollbar)
  ret.UpdateList = POP.updatelist
  ret.RemoveValue = KIT.popupremovevalue
  ret.AddItem = KIT.popupadditem
  ret:Hide()

  return ret
end
