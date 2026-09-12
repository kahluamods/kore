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

local _G = _G
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tostring = tostring
local GetTime = GetTime
local min = math.min
local max = math.max
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local xpcall, pcall = xpcall, pcall
local ipairs, pairs, next, type = ipairs, pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local UIParent = UIParent
local safecall
local floor = math.floor
local ceil = math.ceil
local CreateFrame = CreateFrame
local tsort = table.sort
local tmaxn = table.maxn

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

--
-- What cfg.blackbg fills a window with. It is painted black by the caller, so
-- all this has to be is a tile that covers -- which the stock dialog grounds
-- do not do on their own.
--
-- The stippled rock a tabbed dialog is filled with is not this: that comes
-- from ButtonFrameTemplate, which brings its own.
--
local WINDOW_BG = "Interface/Buttons/WHITE8X8"

local borders = {
  { -- Thin
    bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
    offset = 6,
  },
  { -- Thick
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background", edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
    offset = 12,
  }
}

local cfbackdrop = {
  bgFile = "Interface/ChatFrame/ChatFrameBackground", edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

KUI.emptydropdown = {
  {
    text = "",
    notcheckable = true,
    notclickable = true,
    enabled = false,
  },
}

--
-- The three different types of dropdown menu:
-- SINGLE allows selection of a single item from a list. The selected choice
--   is displayed in the text box. When the menu is dropped down the selected
--   item has a checkmark. This typically has a label and not a title.
-- COMPACT allows selection of a single item from a list. When the menu is
--   dropped down the selected item is checked. The selected item is NOT
--   displayed in the main text box. Rather, the title is always displayed
--   in the text box, thus the title must always be provided. A label can
--   also be provided but that will look weird.
-- MULTI allows selection of multiple items from a list. When the menu is
--   dropped down all of the selected items will have a checkmark. The main
--   widget text is always the title text unless the very first item in the
--   item list is marked as a title item in which case that is used. A label
--   can also be provided but it looks wierd.
--
-- SINGLE and COMPACT have the following two functions:
--   SetValue(value) will ensure that the first item in the item list with
--     the specified value will be selected, and this will be the return
--     value from calling GetValue(). If no item with the specified value
--     can be found then no changes are made to the widget.
--   GetValue() will return the value of the currently selected item or nil
--     if no current value is selected.
-- MULTI menus have the following two functions:
--   SetSelected(value, onoff) will set all items with the specified value
--     to either selected (onoff is true) or not (it is false).
--   IsSelected(value) returns true if the specified value is currently
--     selected, false if it is not, or nil if no such value could be found.
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
  templ = templ or (BackdropTemplateMixin and "BackdropTemplate" or nil)
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

KUI.wcounters = KUI.wcounters or {}

-- Defined further down; needed by the menu widget factory before that point.
local tl_OnEnter, tl_OnLeave, get_radiowidget

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

function KUI:MeasureStrWidth(str, font)
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

function KUI:GetFontColor(font, rgbtab)
  if (font and font ~= self.lastfont) then
    self.strwidth:SetFontObject(font)
    self.lastfont = font
  end

  local r,g,b,a = self.strwidth:GetTextColor()

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

local function hook_SetWidth(fr)
  if (fr.SetWidth) then
    hooksecurefunc(fr, "SetWidth", function(self, width)
      self:Throw("OnWidthSet", width)
    end)
  end
end

local function hook_SetHeight(fr)
  if (fr.SetHeight) then
    hooksecurefunc(fr, "SetHeight", function(self, height)
      self:Throw("OnHeightSet", height)
    end)
  end
end

local function hook_Enable(fr)
  if (fr.Enable) then
    hooksecurefunc(fr, "Enable", function(self, ...)
      self.enabled = true
      self:Throw("OnEnable", true)
    end)
  end
end

local function hook_Disable(fr)
  if (fr.Disable) then
    hooksecurefunc(fr, "Disable", function(self, ...)
      self.enabled = false
      self:Throw("OnEnable", false)
    end)
  end
end

local function hook_Show(fr)
  if (fr.Show) then
    hooksecurefunc(fr, "Show", function(self, ...)
      self:Throw("OnShow", false)
    end)
  end
end

local function hook_Hide(fr)
  if (fr.Hide) then
    hooksecurefunc(fr, "Hide", function(self, ...)
      self:Throw("OnHide", false)
    end)
  end
end

function BC.SetEnabled(self, onoff)
  if (onoff == nil) then
    onoff = true
  end

  if (not self.Enable or not self.Disable) then
    self.enabled = onoff
    self:Throw("OnEnable", onoff)
    return
  end

  if (onoff) then
    self:Enable()
  else
    self:Disable()
  end
  self:Throw("OnEnable", onoff)
end

function BC.SetShown(self, onoff)
  if (onoff == nil) then
    onoff = true
  end

  if (onoff) then
    self:Show()
  else
    self:Hide()
  end
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

  GameTooltip_SetDefaultAnchor(GameTooltip, this)
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
  if (this.tipfunc) then
    GameTooltip:SetOwner(this, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPLEFT", this, "TOPRIGHT", 5, 0)
    this.tipfunc(this)
  end
end

local function tip_OnEnter(this, event)
  do_tooltip_onenter(this, this.enabled)
end

local function tip_OnLeave(this, event)
  GameTooltip:Hide()
end

local function apply_hooks(fr)
  hook_SetWidth(fr)
  hook_SetHeight(fr)
  hook_Enable(fr)
  hook_Disable(fr)
  hook_Show(fr)
  hook_Hide(fr)
  fr:HookScript("OnEnter", generic_OnEnter)
  fr:HookScript("OnLeave", generic_OnLeave)
end

local function newobj(cfg, kparent, defwt, defht, fname, ftype, template)
  local defh, defw
  local lx = 0
  local ly = 0

  if (cfg.template) then
    template = cfg.template
  end

  if (template == "") then
    template = nil
  end

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

  local frame = MakeFrame(ftype or "Frame", fname, parent, template)
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
  -- If defh and defw are both 0, it means we have a "special" case on our hands, where the calling function will do all the
  -- placement.
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
-- same shape. The frame cannot grow to cover them without stretching the artwork it owns, which is Blizzard's and not ours
-- to re-anchor.
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
-- A recessed panel, the way Blizzard's own windows divide themselves up.
--
-- The frame returned is the panel. Put widgets in ret.content, which is the area inside its border -- anything anchored to
-- the panel itself sits on top of the artwork.
--
local INSET_BACKDROP = {
  bgFile = "Interface/ChatFrame/ChatFrameBackground", edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

--
-- The space between one widget and the next. A panel laying out a column walks down it with
--
--   ypos = ypos - widget:GetHeight() - KUI.WIDGET_GAP
--
-- and that is the whole of it: no per-panel constant, and nothing that has to know what kind of widget it just placed. That
-- works only because a widget's frame is the size of the box it draws -- an edit box is 20 because InputBoxTemplate draws
-- 20, a dropdown is 24 because its artwork is opaque for 24. A frame with dead space in it forces every caller to correct
-- for it by eye, and then the gaps down a column are even in the source and uneven on the screen.
--
-- So if a layout needs a number that is not this one, the widget is lying about its size. Fix the widget.
--
KUI.WIDGET_GAP = 4

--
-- The space between the parts of one widget: a checkbox and the words beside it, a dropdown and the label over it. Nothing a
-- caller places is separated by this, and nothing inside a widget is separated by WIDGET_GAP. They are deliberately two
-- numbers even when they hold the same value, because they answer different questions -- how far apart are two things the
-- user thinks of as separate, against how close together are the pieces of one thing -- and tuning either must not disturb
-- the other.
--
KUI.INTERNAL_GAP = 4

--
-- What a dropdown wants after it on top of the standard gap. Its artwork is a tray drawn wider and taller than the frame it
-- belongs to, and the eye reads the tray rather than the frame, so a dropdown followed by the same gap as a checkbox looks
-- crowded where the checkbox looks right.
--
-- A column that has just placed a dropdown steps by
--
--   ypos = ypos - dd:GetHeight() - KUI.WIDGET_GAP - KUI.DROPDOWN_ADD_GAP
--
KUI.DROPDOWN_ADD_GAP = 2

--
-- A panel is three rings deep on every side. The frame handed back is the outer box and the size the caller asked for is
-- that outer size:
--
--   cfg.padding        space between the frame edge and the artwork, so that a panel stands clear of its neighbours and
--                      of the window. Two panels side by side each give up this much, so the space between them is twice
--                      it and no separate gutter is needed anywhere.
--   INSET_BORDER       the artwork itself. The border texture is cut into 16 pixel tiles but the line inside one sits 4 in,
--                      which is what this records.
--   cfg.inner_padding  space inside the artwork before the usable area. The border is the panel's neighbour as far as the
--                      first widget is concerned, so this is the standard gap.
--
-- So a 100x100 panel with the defaults has its artwork box from 4,4 to 96,96 and ret.content, the part a caller can use,
-- from 12,12 to 88,88.
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
-- The strip a scroll list keeps on its right for the bar, which is wider than the bar's own slider.
-- UIPanelScrollBarTemplateLightBorder hangs 18 wide buttons off a 16 wide slider and draws a border beyond those again, so
-- what you see is several pixels proud of the slider on each side and the strip has to hold all of it.
--
-- It is a number to taste rather than a derivation: a strip exactly as wide as the bar draws leaves it sitting clear of
-- whatever the list is inside, and a little narrower puts it back against that edge, which is where it looks like it
-- belongs.
--
KUI.SCROLLBAR_COMPENSATE = 22

--
-- What a dropdown costs beyond the words in it: the inset before the text and the arrow button after it, matching where
-- CreateDropDown anchors its text.
--
KUI.DROPDOWN_CHROME = 12 + 26

--
-- How far a dropdown's end caps hang outside the frame, so that the box the user sees begins where the frame begins. The
-- LabelFrame slice Kore cuts its caps from carries a soft margin before the border inks, exactly as it does above and below,
-- and Blizzard's own use of the texture answers it the same way, anchoring the cap outside the frame rather than trimming
-- the texture.
--
-- Without this a dropdown disagrees with itself: a label above one starts at the frame's left edge and the box under it
-- starts inside that, and a column of dropdowns and checkboxes has two left edges in it.
--
KUI.DROPDOWN_ART_BLEED = 3

--
-- The box a checkbox draws, which its label starts to the right of. A caller laying checkboxes out in columns needs this to
-- know what one costs beyond the words in it, and one laying them out in rows steps by this plus WIDGET_GAP like any other
-- widget.
--
-- CHECKBOX_ART is the size the artwork is drawn at for a box of CHECKBOX_SIZE, and is deliberately larger. Blizzard's
-- checkbox texture carries a wide transparent margin and inks only the middle of whatever square it is given, so a frame the
-- size of the texture is mostly empty air and stacking two of them a standard gap apart leaves a visibly enormous one. The
-- texture is therefore drawn oversize and centred on the frame, hanging over every side, and the frame is the box you
-- actually see. The words stand INTERNAL_GAP off that box.
--
-- The two are a ratio rather than a pair of sizes. A checkbox given a height draws its artwork in proportion to it, so
-- asking for a bigger box gets a bigger box and the frame goes on being the size of what it draws.
--
KUI.CHECKBOX_SIZE = 16
KUI.CHECKBOX_ART = 24

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
-- so the content sits where it would have, four pixels further out.
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
-- A border is eight pieces of one texture and there is no way to leave one of them out, so an edge that is not wanted is put
-- out of sight instead. The artwork lives in a frame that clips its children and a suppressed side is anchored a whole edge
-- tile beyond it, where it is cut away. The background goes with it, so the panel still fills right to that edge and simply
-- has no line drawn on it.
--
local INSET_EDGE_TILE = 16

--
-- A TITLE PLATE is words on a small plate, which is how anything in this toolkit says what it is. A panel hangs one on its top
-- edge, a dialog hangs one off the top of its border. They are the same object built by the same code, and only where it is
-- hung differs.
--
-- Everything about a title is one table, rather than a handful of cfg.titleSomething keys spread through the host widget's
-- own options:
--
--   { text, style, width, height, padding, font, bordercolor }
--
-- A title is one thing with several properties and reads as one, and having a shape of its own it can be handed along
-- untouched by anything that builds one widget on behalf of another -- which is what the splits do with their panes, and
-- CreatePopupList with its dialog. A bare string is that table with only its text filled in, which is what nearly every
-- caller wants.
--
-- Two styles:
--
--   THIN is the toolkit's thin grey-bordered plate -- the same backdrop CreateStringLabel draws with border = true. It is
--   what one section of a page wants, and is what a panel takes if it says nothing.
--
--   THICK is the stock dialog header, the ornate gold plate a window title sits in, for something that is a whole thing in
--   its own right. It is built from three pieces of one texture: a centre that stretches and an end cap at each side that
--   does not, which is why a THICK plate can never be narrower than its two caps. It is what a dialog takes if it says
--   nothing.
--
-- One table rather than seven file locals: Lua 5.1 allows a chunk two hundred of those and this file is close enough to the
-- ceiling to care.
--
local TITLE = { CAP = 30 }

TITLE.STYLES = {
  THIN  = { height = 24, font = "GameFontNormal", padding = 12 },
  THICK = { height = 40, font = "GameFontNormal", padding = 16 },
}

--
-- Width of the plate for the text in it: what the string measures plus a margin each side.
--
-- On a THICK plate the caps are ornament flaring off the ends rather than room for words, so the margin is measured against
-- the centre they sit either side of and the two of them are added on top of it. Measured against the whole plate instead, a
-- title only a little wider than sixty pixels would be left with a centre narrower than itself and would run out into the
-- wings.
--
function TITLE.measure(this)
  local w = ceil(this.text:GetStringWidth()) + (2 * this.pad)

  if (this.caps) then
    w = w + (2 * TITLE.CAP)
  end

  return w
end

--
-- Not called SetWidth: that is a real frame method and this is not it. What is set here is the plate as a whole, and on a
-- THICK one only the centre stretches -- the caps are anchored to its ends and follow it out, so all that changes is what is
-- left when they have taken their thirty pixels each.
--
function TITLE.setwidth(this, width)
  this:SetWidth(width)

  if (this.caps) then
    this.bg:SetWidth(max(width - (2 * TITLE.CAP), 1))
  end
end

function TITLE.settext(this, text)
  this.text:SetText(text or "")

  --
  -- A plate given an explicit width keeps it whatever it is later told to say, because the caller sized it to fit a column
  -- or a neighbour rather than to fit these particular words.
  --
  if (this.auto) then
    TITLE.setwidth(this, TITLE.measure(this))
  end
end

--
-- Build one. SPEC is the table or string above, or nil for no plate at all. DEFSTYLE is only the fallback: a spec naming a
-- style gets that style, so a panel can ask for THICK and a dialog for THIN. The plate is returned unanchored, because where
-- it hangs is the whole of what the host widget has left to decide.
--
function TITLE.plate(parent, spec, defstyle)
  if (spec == nil) then
    return nil
  end

  if (type(spec) ~= "table") then
    spec = { text = spec }
  end

  local st = TITLE.STYLES[string.upper(spec.style or "")] or TITLE.STYLES[defstyle]
  local th = tonumber(spec.height) or st.height
  local plate = MakeFrame("Frame", nil, parent)

  plate:SetHeight(th)
  plate.pad = tonumber(spec.padding) or st.padding
  plate.caps = (st == TITLE.STYLES.THICK)
  plate.auto = spec.width == nil
  plate.SetPlateWidth = TITLE.setwidth
  plate.SetTitleText = TITLE.settext

  if (plate.caps) then
    local bg = plate:CreateTexture(nil, "BORDER")

    bg:SetTexture(131080) -- Interface\\DialogFrame\\UI-DialogBox-Header
    bg:SetTexCoord(0.31, 0.67, 0, 0.63)
    bg:SetPoint("TOP", plate, "TOP", 0, 0)
    bg:SetHeight(th)
    plate.bg = bg

    local cl = plate:CreateTexture(nil, "BORDER")

    cl:SetTexture(131080)
    cl:SetTexCoord(0.21, 0.31, 0, 0.63)
    cl:SetPoint("RIGHT", bg, "LEFT", 0, 0)
    cl:SetWidth(TITLE.CAP)
    cl:SetHeight(th)

    local cr = plate:CreateTexture(nil, "BORDER")

    cr:SetTexture(131080)
    cr:SetTexCoord(0.67, 0.77, 0, 0.63)
    cr:SetPoint("LEFT", bg, "RIGHT", 0, 0)
    cr:SetWidth(TITLE.CAP)
    cr:SetHeight(th)
  else
    plate:SetBackdrop(cfbackdrop)
    plate:SetBackdropColor(0, 0, 0, 1)

    local bc = spec.bordercolor

    plate:SetBackdropBorderColor(bc and bc.r or 0.4, bc and bc.g or 0.4,
      bc and bc.b or 0.4, bc and bc.a or 1)
  end

  local tt = plate:CreateFontString(nil, "OVERLAY", spec.font or st.font)

  tt:SetPoint("CENTER", plate, "CENTER", 0, 0)
  tt:SetJustifyH("CENTER")
  tt:SetText(spec.text or "")
  plate.text = tt

  TITLE.setwidth(plate, tonumber(spec.width) or TITLE.measure(plate))

  return plate
end

--
-- The host's half of it: hand the plate on to whoever asks the widget for it, so that ret.title, ret.titletext and
-- ret:SetTitleText mean the same thing on a panel and on a dialog.
--
function TITLE.attach(frame, plate)
  frame.title = plate
  frame.titletext = plate.text

  frame.SetTitleText = function(this, text)
    this.title:SetTitleText(text)
  end
end

--
-- A panel names itself on a plate straddling its top edge: centred horizontally, and hung so that the panel's own top border
-- runs through the middle of it. Straddling is the whole point -- a plate sitting wholly above the panel is a caption
-- floating in the window, and one sitting wholly inside it is just a widget somebody put there. On the line it belongs to
-- the panel and says what the panel is. The plate is opaque, so the border stops at its edges instead of being drawn through
-- the words.
--
-- Returns the plate's height, which is what the panel below it has to make room for; zero when there is no title at all,
-- which leaves every measurement below exactly as it was.
--
function TITLE.panel(frame, cfg, p)
  local plate = TITLE.plate(frame, cfg.title, "THIN")

  if (not plate) then
    return 0
  end

  plate:SetFrameLevel(frame:GetFrameLevel() + 4)
  plate:SetPoint("TOP", frame, "TOP", 0, 0 - p.top)
  TITLE.attach(frame, plate)

  return plate:GetHeight()
end

function KUI:CreateInset(cfg, kparent)
  local cfg = cfg or {}
  local frame, parent = newobj(cfg, kparent, 100, 100, cfg.name)

  local art = MakeFrame("Frame", nil, frame)
  art:SetAllPoints(frame)
  frame.artframe = art

  --
  -- Without clipping there is nowhere for a suppressed edge to go but over the panel next door, so on a client that cannot
  -- clip every edge draws. A border too many is a cosmetic loss; artwork loose in the window is not.
  --
  local canclip = art.SetClipsChildren and true or false

  if (canclip) then
    art:SetClipsChildren(true)
  end

  frame.drawart = cfg.inset_art ~= false
  frame.edges = canclip and inset_edges(cfg.inset_art) or inset_edges(true)

  --
  -- CreateFrame raises on a template it does not know rather than returning nil, so the stock inset is tried behind a pcall
  -- and a plainer backdrop stands in where there is no such template. A flatter panel is a great deal better than an addon
  -- that will not load.
  --
  local ok, inner = pcall(MakeFrame, "Frame", nil, art, "InsetFrameTemplate")

  if (not (ok and inner)) then
    inner = MakeFrame("Frame", nil, art)
    inner:SetBackdrop(INSET_BACKDROP)
    inner:SetBackdropColor(0, 0, 0, 1)
  end

  frame.inset = inner

  --
  -- cfg.padding is not cfg.inset. The splits already use that name for the margin they leave on the *outside* of themselves,
  -- and one key cannot mean both.
  --
  local e = frame.edges
  local p = padding_sides(cfg.padding, KUI.INSET_PADDING)
  local ip = padding_sides(cfg.inner_padding, KUI.INSET_INNER_PADDING)

  --
  -- A titled panel gives up its top padding, because the plate IS the top padding. It is a real object occupying that edge,
  -- not something floating above a margin. Left at the default the two both claim the edge and the panel sits four lower
  -- than an untitled one beside it.
  --
  -- Only when the caller said nothing about padding. One that names it gets exactly what it asked for.
  --
  if (cfg.title and cfg.padding == nil) then
    p.top = 0
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
  -- A title pushes the panel down under itself. The panel's top edge falls half a plate below the top of the frame, so that
  -- the border runs through the middle of the plate, and the content clears the whole plate rather than just the border:
  -- along that edge the plate has taken the border's place, and everything it covers goes with it.
  --
  if (th > 0) then
    rings.top = p.top + th + ip.top
  end

  frame.rings = rings

  --
  -- What the top edge still owes the title once the panel has stopped being a panel. A container gives up nothing on any
  -- side, but a plate is a real object hanging off the top of the frame and content laid over it would simply be on top of
  -- the words.
  --
  frame.titlering = (th > 0) and (p.top + th) or 0

  --
  -- Where the panel's own top edge goes. With a title it drops half a plate, so that the line it draws runs through the
  -- middle of the plate -- less half a border, because that line is not the inset frame's edge: the border is INSET_BORDER
  -- of artwork with the line down the middle of it, so the edge has to sit that much higher for the line to come out level.
  --
  local pt = p.top

  if (th > 0) then
    pt = p.top + th / 2 - KUI.INSET_BORDER / 2
  end

  frame.arttop = pt

  local xl = e.left and p.left or 0 - INSET_EDGE_TILE
  local xr = e.right and p.right or 0 - INSET_EDGE_TILE
  local xt = e.top and pt or 0 - INSET_EDGE_TILE
  local xb = e.bottom and p.bottom or 0 - INSET_EDGE_TILE

  inner:SetPoint("TOPLEFT", frame, "TOPLEFT", xl, 0 - xt)
  inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - xr, xb)

  local content = MakeFrame("Frame", nil, frame)
  frame.content = content

  --
  -- The artwork sits one frame deeper than the panel, inside the frame that clips it, so the content has to be lifted clear
  -- of it by hand or the border draws over everything placed in the panel.
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
    this.inset:SetShown(onoff and this.drawart)

    --
    -- A container is not a panel at all: it holds panels, which bring their own padding, so it gives up nothing on any side
    -- and the content is the whole of it.
    --
    local rg = this.rings
    local l = onoff and rg.left or 0
    local r = onoff and rg.right or 0
    local t = onoff and rg.top or this.titlering
    local b2 = onoff and rg.bottom or 0

    this.content:ClearAllPoints()
    this.content:SetPoint("TOPLEFT", this, "TOPLEFT", l, 0 - t)
    this.content:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 0 - r, b2)
  end

  frame:SetBorderShown(true)

  return frame
end

--
-- The y offset that puts something centred in a panel's CONTENT. Achors with
-- SetPoint("RIGHT", content, "RIGHT", x, KUI:PanelMiddle(content)).
--
-- The two are not the same. A panel's rings are not symmetric: a title makes the top one much the deeper of the two, and the
-- lines themselves sit inside the artwork rather than at its edge. Centred in the content, a block of buttons in a titled
-- panel reads several pixels low.
--
function KUI:PanelMiddle(content)
  local ins = content and content.owninginset

  if (not ins) then
    return 0
  end

  local r = ins.rings

  return (r.top - r.bottom - ins.arttop + ins.padding.bottom) / 2
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
-- A split's pane is a panel and is titled like one, with the very same table.
-- That is the whole reason a title is one table rather than a handful of
-- cfg.titleSomething keys: it can be passed along untouched by anything that
-- builds a panel on somebody else's behalf.
--
-- A pane told not to draw gives up the artwork and the inner padding that
-- measured the distance to it, there being nothing left to stand clear of.
-- Its outer padding is position rather than border and is kept, so what is
-- put in the pane sits where it would have, just without a line around it.
--
-- That leaves one ring, which the caller drops by asking for no padding on
-- that pane. Both rings gone is a container: a frame whose content is the
-- whole of it, for a pane that holds panels of its own rather than widgets.
--
local function pane_border(arg, border)
  if (border == false) then
    arg.inset_art = false
    arg.inner_padding = 0
  end

  return arg
end


--
-- Split a frame into two panes, one above the other.
--
-- cfg.height is the usable height of the static pane, as it always was, so a
-- caller asking for 48 still gets 48 to put things in: the panel is made
-- taller than that by everything its own edges give up. cfg.topanchor makes
-- the static pane the top one. The end cap and shift options a divider needed
-- are accepted and ignored, because there is no divider any more.
--
-- The two panes meet edge to edge. Each already stands its own padding clear
-- of its outside, so the space between them is those two paddings and there
-- is no gutter to add on top of it.
--
function KUI:CreateHSplit(cfg, kparent)
  local frame, parent = newobj(cfg, kparent, 0, 0, cfg.name)
  local inset = cfg.inset or 0

  unborder_parent(parent)

  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, 0 - inset)
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 - inset, inset)

  --
  -- cfg.inset_art describes the outside of the pair, not either panel, and
  -- each pane is given only the sides it actually owns. The two edges facing
  -- each other across the gutter are interior and always draw.
  --
  local ea = inset_edges(cfg.inset_art)

  local ta = { padding = cfg.toppadding or cfg.padding, inner_padding = cfg.inner_padding,
    title = cfg.toptitle, inset_art = { left = ea.left, right = ea.right, top = ea.top } }
  local ba = { padding = cfg.bottompadding or cfg.padding, inner_padding = cfg.inner_padding,
    title = cfg.bottomtitle, inset_art = { left = ea.left, right = ea.right, bottom = ea.bottom } }

  local tp = self:CreateInset(pane_border(ta, cfg.topborder), frame)
  local bp = self:CreateInset(pane_border(ba, cfg.bottomborder), frame)

  --
  -- The static pane is sized so that what is left inside it is the height the
  -- caller asked for, which is not the same for both panes: the one with an
  -- edge left open gives up nothing on that side.
  --
  local sp = cfg.topanchor and tp or bp
  local hh = (cfg.height or 24) + sp.rings.top + sp.rings.bottom

  tp:ClearAllPoints()
  bp:ClearAllPoints()

  if (cfg.topanchor) then
    tp:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tp:SetHeight(hh)
    bp:SetPoint("TOPLEFT", tp, "BOTTOMLEFT", 0, 0)
    bp:SetPoint("TOPRIGHT", tp, "BOTTOMRIGHT", 0, 0)
    bp:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
  else
    bp:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bp:SetHeight(hh)
    tp:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tp:SetPoint("BOTTOM", bp, "TOP", 0, 0)
  end

  frame.topinset = tp
  frame.bottominset = bp
  frame.topframe = tp.content
  frame.bottomframe = bp.content

  return frame
end


--
-- Split a frame into two panes, side by side. cfg.width is the usable width
-- of the static pane and cfg.rightanchor makes that the right hand one.
--
function KUI:CreateVSplit(cfg, kparent)
  local frame, parent = newobj(cfg, kparent, 0, 0, cfg.name)
  local inset = cfg.inset or 0

  unborder_parent(parent)

  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, 0 - inset)
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 - inset, inset)

  --
  -- As for the horizontal split: the outer sides are handed to whichever
  -- pane owns them, and the two facing the gutter always draw.
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
-- Helper function to make a frame resizable. Takes as its parameters the
-- parent frame that is to be resizable, the height of the corner frames,
-- and the direction(s) in which the frame is to be resized. This can be
-- a boolean (true means resize both vertically and horizontally, false
-- means don't resize at all), or a string which case have the values
-- "HEIGHT" to resize the height only, "WIDTH" to resize the width only,
-- or "BOTH" to resize both.
-- Returns the southeast, southwest and southern frame pointers or nil for
-- any of them not used.
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

function KUI:CreateDialogFrame(cfg, kparent)
  local fname = cfg.name or ("KUIDlgFrame" .. self:GetWidgetNum("dialog"))
  local frame,parent,width,height = newobj(cfg, kparent, 300, 300, fname)
  local bstyle = 2 -- Thick
  local offset = 0
  local topheight = 0

  if (cfg.border ~= nil) then
    if (type(cfg.border) == "boolean") then
      if (cfg.border) then
        bstyle = 2
      else
        bstyle = 0
      end
    elseif (type(cfg.border) == "string") then
      if (cfg.border == "THICK") then
        bstyle = 2
      elseif (cfg.border == "THIN") then
        bstyle = 1
      elseif (cfg.border == "NONE") then
        bstyle = 0
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
  frame:SetFrameStrata(cfg.strata or "FULLSCREEN_DIALOG")

  local bdrop = {}

  if (bstyle > 0) then
    bdrop.bgFile = borders[bstyle].bgFile
    bdrop.edgeFile = borders[bstyle].edgeFile
    bdrop.tileSize = borders[bstyle].tileSize
    bdrop.edgeSize = borders[bstyle].edgeSize
    bdrop.insets = borders[bstyle].insets
    offset = borders[bstyle].offset
    bdrop.tile = true
  end

  if (cfg.blackbg) then
    bdrop.bgFile = WINDOW_BG
    bdrop.tile = true
  end

  frame.borderoffset = offset

  frame:SetBackdrop(bdrop)
  frame:SetBackdropColor(0, 0, 0, 1)

  if (frame:IsResizable()) then
    frame:SetResizeBounds(cfg.minwidth or width, cfg.minheight or height, cfg.maxwidth or width, cfg.maxheight or height)
  end

  if (cfg.xbutton) then
    local xbutton = MakeFrame("Button", nil, frame, "UIPanelCloseButton")
    xbutton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    xbutton:SetScript("OnClick", xbutton_OnClick)
  end

  frame:Hide()

  --
  -- A dialog's title is the same plate a panel names itself with, hung off
  -- the top of the border rather than straddling an edge, and taking THICK
  -- when it says nothing: the ornate header is what a window title has always
  -- sat in. It doubles as the drag handle, which is the only thing here a
  -- panel's title does not do.
  --
  local dtitle = (bstyle > 0) and TITLE.plate(frame, cfg.title, "THICK") or nil

  if (dtitle) then
    TITLE.attach(frame, dtitle)
    dtitle:SetPoint("TOP", frame, "TOP", 0, 12)
    dtitle:EnableMouse(true)

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
      mframe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 5)
      mframe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -5)
      mframe:SetHeight(25)
      mframe:SetScript("OnMouseDown", parent_StartMoving)
      mframe:SetScript("OnMouseUp", parent_StopMoving)
    end
  end

  local rightmost = frame
  local rightpoint = "BOTTOMRIGHT"
  local xoffs, yoffs = -15, 16
  local addheight = 0

  if (frame.title or cfg.xbutton) then
    topheight = topheight + 14
  end

  if (cfg.cancelbutton) then
    local cancel
    cancel = MakeFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetScript("OnClick", function(this)
      this:GetParent():Throw("OnCancel")
    end)
    cancel:SetPoint("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    cancel:SetHeight(cfg.cancelbutton.height or 20)
    cancel:SetWidth(cfg.cancelbutton.width or 100)
    cancel:SetText(cfg.cancelbutton.text or K.CANCEL_STR)
    addheight = max(addheight, cancel:GetHeight())

    --
    -- Kept so that a caller can move the pair. The OK button hangs off the
    -- cancel button, so re-anchoring this one moves both.
    --
    frame.cancelbutton = cancel

    rightmost = cancel
    rightpoint = "BOTTOMLEFT"
    xoffs = -5
    yoffs = 0
  end

  if (cfg.okbutton) then
    local ok = MakeFrame("Button", nil, frame, "UIPanelButtonTemplate")
    ok:SetScript("OnClick", function(this)
      this:GetParent():Throw("OnAccept")
    end)
    ok:SetPoint("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    ok:SetHeight(cfg.okbutton.height or 20)
    ok:SetWidth(cfg.okbutton.width or 100)
    ok:SetText(cfg.okbutton.text or K.OK_STR)
    addheight = max(addheight, ok:GetHeight())

    frame.okbutton = ok

    rightmost = ok
    rightpoint = "BOTTOMLEFT"
    xoffs = -5
    yoffs = 0
  end

  if (cfg.statusbar) then
    local statusbg = MakeFrame("Frame", nil, frame)
    frame.statusframe = statusbg
    statusbg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, offset)
    statusbg:SetPoint("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    statusbg:SetHeight(20)
    statusbg:SetBackdrop(cfbackdrop)
    statusbg:SetBackdropColor(0.1, 0.1, 0.1)
    statusbg:SetBackdropBorderColor(0.4, 0.4, 0.4)
    addheight = max(addheight, 20)

    local statustext = statusbg:CreateFontString(nil, "OVERLAY",
      cfg.statusfont or "GameFontNormal")
    frame.statustext = statustext
    statustext:SetPoint("TOPLEFT", statusbg, "TOPLEFT", 7, -2)
    statustext:SetPoint("BOTTOMRIGHT", statusbg, "BOTTOMRIGHT", -7, 2)
    statustext:SetHeight(20)
    statustext:SetJustifyH("LEFT")
    statustext:SetText("")
    frame.SetStatusText = function(this, text)
      this.statustext:SetText(text or "")
    end
  end

  local content = MakeFrame("Frame", nil, frame)
  --
  -- The border offset clears the artwork and nothing more, so content placed
  -- at 0,0 sits hard against it. cfg.padding is kept inside that, for a dialog
  -- that would rather its widgets looked placed than jammed into the corner.
  -- It is none unless asked for: every dialog written before this one is laid
  -- out in its own coordinates and would move under it.
  --
  local pad = padding_sides(cfg.padding, 0)

  frame.content = content
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", offset + pad.left,
    0 - (offset + topheight + pad.top))
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
    0 - (offset + pad.right), offset + addheight + pad.bottom)

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

local function sl_SetTextColor(this, r, g, b, a)
  this.rgb = {r = r, g = g, b = b, a = a or 1}
  local d = this.enabled and 1 or 2
  this.label:SetTextColor(r/d, g/d, b/d, a or 1)
end

local function sl_OnEnable(this, event, onoff)
  local onoff = onoff or false
  this.enabled = onoff
  local d = onoff and 1 or 2
  this.label:SetTextColor(this.rgb.r/d, this.rgb.g/d, this.rgb.b/d, this.rgb.a)
end

local function sl_SetText(this, text)
  if (this.autosize) then
    local sw, sh = KUI:MeasureStrWidth(text, this.font)
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
-- A bordered label is bigger than the words in it by the backdrop's own
-- declared insets, and by nothing else. Asked of cfbackdrop rather than
-- written down, so that the frame, the padding and the autosize allowance
-- cannot drift apart from each other or from the artwork.
--
local function sl_inset(cfg)
  return cfg.border and cfbackdrop.insets.left or 0
end

function KUI:CreateStringLabel(cfg, kparent)
  local bi = sl_inset(cfg)
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
  local r,g,b,a = label:GetTextColor()
  frame.rgb = {r = r, g = g, b = b, a = a}
  if (cfg.color) then
    frame.rgb = { r = cfg.color.r, g = cfg.color.g, b = cfg.color.b, a = cfg.color.a or 1 }
  end

  if (cfg.border) then
    frame:SetBackdrop(cfbackdrop)
    frame:SetBackdropColor(0, 0, 0, 0)
    if (cfg.bordercolor) then
      frame:SetBackdropBorderColor(cfg.bordercolor.r,
        cfg.bordercolor.g, cfg.bordercolor.b, cfg.bordercolor.a or 1)
    else
      frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end
  end

  --
  -- How much wider and taller the frame is than the words, which is what
  -- sl_SetText grows it by when it is asked to fit itself to new text.
  --
  frame.xtrawidth = bi * 2
  frame.xtraheight = bi * 2

  label:SetPoint("TOPLEFT", frame, "TOPLEFT", bi, 0 - bi)
  label:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - bi, bi)

  frame.SetText = sl_SetText
  frame.SetTextColor = sl_SetTextColor
  frame.OnEnable = sl_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetText(cfg.text or "")
  frame:SetEnabled(cfg.enabled)

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

local function eb_OnEnterPressed(this)
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

local function eb_SetText(this, text)
  this.setvalue = text
  this:Throw("OnValueChanged", text, false)
end

local function eb_OnTextChanged(this, user)
  if (user) then
    local newv = this:GetText()
    this:Throw("OnValueChanged", newv, true)
  end
end

local function eb_OnEscapePressed(this)
  this:ClearFocus()
  this:SetText(this.setvalue or "")
  this:Throw("OnEscapePressed", this:GetText())
end

local function eb_OnEnable(this, event, onoff)
  local onoff = onoff or false
  local d = onoff and 1 or 2
  this:EnableMouse(onoff)
  this:SetTextColor(this.trgb.r/d, this.trgb.g/d, this.trgb.b/d, this.trgb.a)
  if (this.label) then
    this.label:SetTextColor(this.lrgb.r/d, this.lrgb.g/d, this.lrgb.b/d, this.lrgb.a)
  end
  this.enabled = onoff
  return false
end

function KUI:CreateEditBox(cfg, kparent)
  local frname = cfg.name
  if (not cfg.name) then
    frname = "KUIEditBox" .. self:GetWidgetNum("edit")
  end
  local dwe = 0
  if (cfg.x ~= "CENTER") then
    dwe = 8
  end
  --
  -- Twenty, because that is what InputBoxTemplate draws: its textures are a
  -- fixed 20 tall and anchored to the top of whatever frame wears them. A
  -- taller frame does not make a taller box, it makes an edit box with dead
  -- space under it -- and a caller stacking a column of widgets, who has
  -- nothing to go on but GetHeight, would leave a gap here that it does not
  -- leave under anything else.
  --
  local frame,ppf,width,height = newobj(cfg, kparent, { 200, dwe }, 20, frname, "EditBox", "InputBoxTemplate")

  frame:SetTextInsets(0, 0, 3, 3)
  frame:SetMaxLetters(cfg.len or 128)
  frame:SetCursorPosition(0)
  frame:SetAutoFocus(false)
  frame:SetFontObject(cfg.font or "ChatFontNormal")
  frame:EnableMouse(true)
  frame:EnableKeyboard(true)
  if (cfg.numeric) then
    frame:SetNumeric(true)
  end
  frame:HookScript("OnEnterPressed", eb_OnEnterPressed)
  frame:HookScript("OnEscapePressed", eb_OnEscapePressed)
  frame:HookScript("OnTextChanged", eb_OnTextChanged)
  hooksecurefunc(frame, "SetText", eb_SetText)

  if (cfg.label) then
    local lfont = cfg.label.font or "GameFontNormal"
    local lw,lh = KUI:MeasureStrWidth(cfg.label.text or "", lfont)
    local label = frame:CreateFontString(nil, "ARTWORK", lfont)
    frame.label = label
    local r,g,b,a = label:GetTextColor()
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
    label:SetWidth(lw+4)
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
      label:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
      if (cfg.x and cfg.x == "CENTER") then
        frame:SetPoint("LEFT", ppf, "CENTER", (width + lw + 8) / -2, 0)
      end
    elseif (cfg.label.pos == "BOTTOM") then
      label:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
      if (cfg.y and cfg.y == "MIDDLE") then
        frame:SetPoint("TOP", ppf, "CENTER", 0, (height + lh) / 2)
      end
    else -- Assume LEFT
      --
      -- Four further out than a dropdown places its label, because
      -- InputBoxTemplate draws its left hand end five pixels outside the
      -- frame wearing it -- measured, not guessed: a frame at 681.2 has its
      -- leftmost texture at 676.2. The frame is set that much further right
      -- so that the box you SEE starts where the label geometry says, and an
      -- edit box lines up with a dropdown under it.
      --
      -- This does mean an edit box's frame is not where its artwork is. That
      -- is Blizzard's template and not ours to re-anchor, and it costs
      -- nothing here: columns are laid out by GetHeight, and nothing lays out
      -- a row by GetWidth. If anything ever does, this is the first thing to
      -- look at.
      --
      label:SetPoint("TOPRIGHT", frame, "TOPLEFT", -8, 0)
      if (cfg.x) then
        if (cfg.x ~= "CENTER") then
          frame:SetPoint("LEFT", ppf, "LEFT", cfg.x + lw + 12, 0)
        else
          frame:SetPoint("LEFT", ppf, "CENTER", (width - lw + 12) / -2, 0)
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

  local r,g,b,a = frame:GetTextColor()
  if (cfg.color) then
    r = cfg.color.r or r
    g = cfg.color.g or g
    b = cfg.color.b or b
    a = cfg.color.a or 1
  end
  frame.trgb = {r = r, g = g, b = b, a = a}

  frame.OnEnable = eb_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetEnabled(cfg.enabled)
  frame:SetCursorPosition(0)
  frame:ClearFocus()
  frame:SetText(cfg.initialvalue or "")
  return frame
end

local function cb_OnMouseDown(this)
  if (this.enabled and this.text) then
    local t = this.text
    t:SetPoint("LEFT", t.ipoints[1], t.ipoints[2], t.ipoints[3] + 1, t.ipoints[4] - 1)
  end
end

local function cb_OnMouseUp(this)
  if (this.enabled) then
    if (this.ToggleChecked) then
      this:ToggleChecked()
    else
      this:SetChecked()
    end
    if (this.text) then
      local t = this.text
      t:SetPoint("LEFT", t.ipoints[1], t.ipoints[2], t.ipoints[3], t.ipoints[4])
    end
    this:Throw("OnClick", this.checked)
    this:Throw("OnValueChanged", this.checked, true, this.groupname and this.value or nil)
  end
end

local function cb_SetText(this, text)
  if (this.text) then
    this.text:SetText(text or "")
    if (this.autosize) then
      local w = this.text:GetStringWidth() + this.boxsize + KUI.INTERNAL_GAP + 12
      --
      -- A ceiling rather than a size: the frame is as wide as its words need
      -- until they need more than this, and from there it stops growing and
      -- the words are cut off at the edge. That is what a translated label
      -- wants -- snug in the language that fits and never wide enough to
      -- push what stands beside it off the panel in the one that does not.
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

local function cb_GetChecked(this)
  return this.checked
end

local function cb_ToggleChecked(this)
  this:SetChecked(not this.checked, true)
end

local function cb_OnEnable(this, event, onoff)
  local onoff = onoff or false
  this.enabled = onoff
  local d = onoff and 1 or 2
  SetDesaturation(this.check, not onoff)
  if (this.text) then
    this.text:SetTextColor(this.rgb.r/d, this.rgb.g/d, this.rgb.b/d, this.rgb.a)
  end
end

local function kui_checkradio(cfg, kparent, size, dh, art)
  local dw = size
  if (cfg.label) then
    dw = 200
  end
  local frame, parent, width, height = newobj(cfg, kparent, dw, dh, cfg.name, "Button")

  --
  -- The box is the frame's height and the artwork is drawn in proportion to
  -- it, rather than both being fixed. A caller asking for a bigger checkbox
  -- gets a bigger checkbox, not the same one loose in a taller frame, so the
  -- frame is the size of what is drawn whatever height is asked for.
  --
  -- The box is square, so an unlabelled checkbox that was not given a width
  -- takes its height for one; a labelled one is as wide as its words need.
  --
  local box = height
  local artbox = box * (art or size) / size
  local over = (artbox - box) / 2

  if (not cfg.label and not cfg.width) then
    frame:SetWidth(box)
  end

  frame.boxsize = box
  frame.checked = cfg.checked or false
  frame.autosize = cfg.autosize
  frame.maxwidth = cfg.maxwidth
  frame:HookScript("OnMouseDown", cb_OnMouseDown)
  frame:HookScript("OnMouseUp", cb_OnMouseUp)
  frame:EnableMouse(true)

  local bg = frame:CreateTexture(nil, "ARTWORK")
  bg:SetWidth(artbox)
  bg:SetHeight(artbox)
  bg:SetPoint("LEFT", frame, "LEFT", 0 - over, 0)

  local check = frame:CreateTexture(nil, "OVERLAY")
  frame.check = check
  check:SetWidth(artbox)
  check:SetHeight(artbox)
  check:SetPoint("CENTER", bg, "CENTER", 0, 0)
  if (not frame.checked) then
    check:Hide()
  end

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
    -- The words stand a standard gap off the box the frame reserves, not off
    -- the artwork, which hangs over it and is mostly margin. ipoints carries
    -- the x that anchor was made with, so that the press-and-release nudge
    -- below can put it back.
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
    -- A caller that fixed this frame's width, or put a ceiling on it, has
    -- said the words live inside that, so they are cut off at its edge rather
    -- than wrapped. Wrapping is much the worse of the two failures: the frame
    -- goes on reporting the height it was given while the words grow
    -- downwards out of it and through whatever is drawn underneath. A frame
    -- free to size itself grows to fit its words and has nothing to overflow,
    -- so it keeps the default.
    --
    if (not frame.autosize or frame.maxwidth) then
      text:SetWordWrap(false)
    end
  end

  frame.SetText = cb_SetText
  frame.GetChecked = cb_GetChecked
  frame.OnEnable = cb_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  if (cfg.label) then
    frame:SetText(cfg.label.text or "")
    check_tooltip_title(frame, cfg, cfg.label.text)
  end
  frame:SetEnabled(cfg.enabled)
  return frame, bg, check
end

local function cb_SetChecked(self, onoff, nothrow)
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

function KUI:CreateCheckBox(cfg, kparent)
  local frame, bg, check = kui_checkradio(cfg, kparent, KUI.CHECKBOX_SIZE, KUI.CHECKBOX_SIZE,
    KUI.CHECKBOX_ART)

  bg:SetTexture("Interface/Buttons/UI-CheckBox-Up")
  bg:SetTexCoord(0, 1, 0, 1)

  check:SetTexture("Interface/Buttons/UI-CheckBox-Check")
  check:SetTexCoord(0, 1, 0, 1)
  check:SetBlendMode("BLEND")

  frame.SetChecked = cb_SetChecked
  frame.ToggleChecked = cb_ToggleChecked
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetChecked(cfg.checked)
  frame:SetEnabled(cfg.enabled)
  return frame
end

local function rb_uncheck_group(t, g, ...)
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

local function rb_SetChecked(this)
  if (this.checked) then
    return
  end

  --
  -- Find and set to the OFF state any other buttons in the group
  --
  rb_uncheck_group(this, this.groupname, this.groupparent:GetChildren())
  this.checked = true
  this.check:Show()
  this:Throw("OnValueChanged", true, false, this.value)
end

local function rb_OnValueChanged(this, evt, onoff, user, val)
  if (this.cvfunc) then
    local onoff = onoff or false
    this.cvfunc(this, evt, onoff, user, val)
  end
end

local function rb_getsetvalue(t, g, v, n, set, ...)
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
          rb_uncheck_group(t, g, ...)
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

local function rb_SetValue(this, val, nothrow)
  if (this.checked and this.value and this.value == val) then
    return
  end
  rb_getsetvalue(this, this.groupname, val, nothrow, true, this.groupparent:GetChildren())
end

local function rb_GetValue(this)
  if (this.checked) then
    return this.value
  end
  return rb_getsetvalue(this, this.groupname, nil, nil, false, this.groupparent:GetChildren())
end

--
-- For radio boxes, we must have a group name. When one button in the
-- group is checked, all others become unchecked. All radio boxes in the
-- same group must have the same parent frame.
--
function KUI:CreateRadioButton(cfg, kparent)
  assert(cfg.group, "must supply radio button group name")
  local frame, bg, check = kui_checkradio(cfg, kparent, 16, 16)

  frame.groupname = cfg.group
  frame.groupparent = cfg.groupparent or frame:GetParent()
  frame.value = cfg.value
  frame.cvfunc = cfg.func
  frame.getbutton = cfg.getbutton

  bg:SetTexture("Interface/Buttons/UI-RadioButton")
  bg:SetTexCoord(0, 0.25, 0, 1)

  check:SetTexture("Interface/Buttons/UI-RadioButton")
  check:SetTexCoord(0.25, 0.5, 0, 1)

  frame.SetChecked = rb_SetChecked
  frame.OnValueChanged = rb_OnValueChanged
  frame.SetValue = rb_SetValue
  frame.GetValue = rb_GetValue

  frame.checked = nil
  if (cfg.checked) then
    frame:SetChecked()
  end
  frame:SetEnabled(cfg.enabled)
  return frame
end

-- JKJ FIXME: Add a convenience widget type for a group of radio buttons
-- where the user can specify a list of choices, and have a single event
-- thrown when the choice changes. Possibly allow the group to have a frame
-- and a title. Then lay out the buttons appropriately. Allow for either
-- vertical or horizontal placement.
function KUI:CreateRadioGroup(cfg, kparent)
end

local function update_eb_text(this)
  local val = this.value or 0
  this.editbox:SetText(floor((val * 100) + 0.5) / 100)
end

local function update_editbox(this)
  if (not this.setup) then
    local val = this:GetValue()
    if (this.step and this.step > 0) then
      local mv = this.minval or 0
      val = (floor((val - mv) / this.step + 0.5) * this.step) + mv
    end
    if (val ~= this.value) then
      this.value = val
      this:Throw("OnValueChanged", this.value, this.mousedown and true or false)
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
  local p = this:GetParent()
  local minv, maxv = p:GetMinMaxValues()
  if (val >= minv and val <= maxv) then
    p:SetValue(val)
    p:Throw("OnValueChanged", p:GetValue(), true)
    this:ClearFocus()
  end
end

local function sd_OnEnable(this, event, onoff)
  if (onoff == nil) then
    onoff = true
  end
  this.enabled = onoff
  local d = onoff and 1 or 2

  if (onoff) then
    this:EnableMouse(true)
    this.editbox:EnableMouse(true)
  else
    this:EnableMouse(false)
    this.editbox:EnableMouse(false)
    this.editbox:ClearFocus()
  end

  local tr = this.mrgb
  this.mintxt:SetTextColor(tr.r/d, tr.g/d, tr.b/d, tr.a)
  this.maxtxt:SetTextColor(tr.r/d, tr.g/d, tr.b/d, tr.a)

  tr = this.ergb
  this.editbox:SetTextColor(tr.r/d, tr.g/d, tr.b/d, tr.a)

  if (this.label) then
    tr = this.lrgb
    this.label:SetTextColor(tr.r/d, tr.g/d, tr.b/d, tr.a)
  end
  return false
end

local function sd_OnMouseWheel(this, delta)
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
  this:SetValue(cv)
  this:Throw("OnValueChanged", this:GetValue(), true)
end

local function sd_OnMouseDown(this)
  this.mousedown = true
end

local function sd_OnMouseUp(this)
  this.mousedown = nil
end

local function sd_changeminmax(this, newmin, newmax)
  this.minval = newmin
  this.maxval = newmax
  this:SetMinMaxValues(newmin, newmax)
  this.mintxt:SetText(tostring(newmin))
  this.maxtxt:SetText(tostring(newmax))

  if ((this.value < newmin) or (this.value > newmax)) then
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
  frame.minval = minval
  frame.maxval = maxval
  frame.step = cfg.step or 1

  local sliderbg = {
    bgFile = "Interface/Buttons/UI-SliderBar-Background",
    edgeFile = "Interface/Buttons/UI-SliderBar-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  }
  if (orientation == "HORIZONTAL") then
    frame:SetBackdrop(sliderbg)
    frame:SetThumbTexture("Interface/Buttons/UI-SliderBar-Button-Horizontal")
    local tt = frame:GetThumbTexture()
    --
    -- Size both dimensions here, even though SetThumbTexture has already
    -- given the texture its natural 32 wide. Setting the size explicitly at
    -- this point is what makes the engine place the thumb correctly straight
    -- away; left to resolve it later, a fresh slider draws its thumb adrift
    -- and only corrects itself once something drags it.
    --
    -- The width stays at the natural 32. A slider's thumb travel is inset by
    -- half the thumb's width at each end, so the knob stops short of both
    -- stops -- but that is how Blizzard's own sliders behave and narrowing
    -- the thumb to close the gap only squashes the artwork.
    --
    tt:SetSize(32, height + 8)
  else
    sliderbg.insets.top = 3
    sliderbg.insets.bottom = 3
    frame:SetBackdrop(sliderbg)
    frame:SetThumbTexture("Interface/Buttons/UI-SliderBar-Button-Vertical")
    local tt = frame:GetThumbTexture()
    tt:SetSize(width + 8, 32)
  end

  -- The min and max labels
  local mmfont = cfg.minmaxfont or "GameFontHighlightSmall"
  local mintxt = frame:CreateFontString(nil, "ARTWORK", mmfont)
  local maxtxt = frame:CreateFontString(nil, "ARTWORK", mmfont)
  frame.mintxt = mintxt
  frame.maxtxt = maxtxt
  local r, g, b, a = mintxt:GetTextColor()
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
  r,g,b,a = editbox:GetTextColor()
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
      r,g,b,a = label:GetTextColor()
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
  -- A horizontal slider is a bar with its label over it and its value box
  -- under it, and the bar is the only part the frame can be. The min and max
  -- captions share the value box's row and so cost nothing further.
  --
  if (orientation == "HORIZONTAL") then
    drawn_extent(frame, frame.label and frame.label:GetHeight() or 0, editbox:GetHeight())
  end

  mintxt:SetText(tostring(minval))
  maxtxt:SetText(tostring(maxval))

  local bg = editbox:CreateTexture (nil, "BACKGROUND")
  bg:SetTexture("Interface/ChatFrame/ChatFrameBackground")
  bg:SetVertexColor(0, 0, 0, 0.25)
  bg:SetAllPoints(editbox)
  editbox.bg = bg

  frame:HookScript("OnValueChanged", update_editbox)
  frame:HookScript("OnMouseWheel", sd_OnMouseWheel)
  frame:HookScript("OnMouseDown", sd_OnMouseDown)
  frame:HookScript("OnMouseUp", sd_OnMouseUp)

  frame.OnEnable = sd_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave
  frame.ChangeMinMax = sd_changeminmax

  frame.value = value
  frame:SetValue(value)
  frame:SetEnabled(cfg.enabled)

  frame.setup = nil

  update_eb_text(frame)

  return frame
end

function KUI:CreateButton(cfg, kparent)
  local frame, parent, width, height =
    newobj(cfg, kparent, 100, 24, cfg.name, "Button", "UIPanelButtonTemplate")

  if (cfg.hook) then
    frame:HookScript("OnClick", function(this, ...)
      this:Throw("OnClick", ...)
    end)
  else
    frame:SetScript("OnClick", function(this, ...)
      this:Throw("OnClick", ...)
    end)
  end

  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetText(cfg.text or "")
  check_tooltip_title(frame, cfg, cfg.text)

  local fs = frame:GetFontString()
  fs:SetWidth(width - 6)
  fs:SetHeight(height - 6)

  frame:SetEnabled(cfg.enabled)
  return frame
end

--
-- A button whose face is a picture rather than a word: an icon, a card, one
-- cell of a sprite sheet. UIPanelButtonTemplate is a plate with a caption cut
-- into it and is no use for any of those, so this one carries no template at
-- all and draws what it is given.
--
-- The picture fills the button. Nothing here scales it or preserves its
-- shape -- the caller sets the size, and a caller who cares about the aspect
-- ratio works it out, because only the caller knows which of the two
-- dimensions it is fitting into.
--
local function ib_OnEnable(this, onoff)
  --
  -- A picture cannot go grey the way a caption does, so a disabled one is
  -- desaturated, which is what Blizzard does to an icon that cannot be used.
  --
  this.image:SetDesaturated(not onoff)
end

local function ib_OnMouseDown(this)
  if (this.enabled == false) then
    return
  end

  this.image:SetPoint("TOPLEFT", this, "TOPLEFT", 1, -1)
  this.image:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 1, -1)
end

local function ib_OnMouseUp(this)
  this.image:SetPoint("TOPLEFT", this, "TOPLEFT", 0, 0)
  this.image:SetPoint("BOTTOMRIGHT", this, "BOTTOMRIGHT", 0, 0)
end

local function ib_SetTexture(this, texture, texcoord)
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

local function ib_SetSelected(this, onoff)
  this.selected = onoff and true or false

  if (this.outline) then
    this.outline:SetShown(this.selected)
  end
end

function KUI:CreateImageButton(cfg, kparent)
  local frame, parent, width, height =
    newobj(cfg, kparent, 32, 32, cfg.name, "Button")

  --
  -- Drawn behind the picture and larger than it, so that what shows is a rim
  -- around the outside. A button that is never selected does not ask for one
  -- and does not get the texture.
  --
  if (cfg.outline) then
    local ow = cfg.outlinesize or 2
    local ol = frame:CreateTexture(nil, "BACKGROUND")

    ol:SetPoint("TOPLEFT", frame, "TOPLEFT", 0 - ow, ow)
    ol:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", ow, 0 - ow)
    ol:SetTexture("Interface\\Buttons\\WHITE8X8")
    ol:SetVertexColor(cfg.outline.r or 1, cfg.outline.g or 1,
      cfg.outline.b or 1, cfg.outline.a or 1)
    ol:Hide()
    frame.outline = ol
  end

  local image = frame:CreateTexture(nil, "ARTWORK")
  image:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  image:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.image = image

  --
  -- A caption over the picture, for a button whose picture does not say
  -- enough by itself or has not been drawn yet. Made either way, because a
  -- caller that reuses one button for several things may want it later.
  --
  local fs = frame:CreateFontString(nil, "OVERLAY",
    cfg.font or "GameFontNormal")
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", cfg.textx or 10,
    0 - (cfg.texty or 10))
  fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0 - (cfg.textx or 10),
    0 - (cfg.texty or 10))
  fs:SetJustifyH(cfg.justifyh or "LEFT")
  frame:SetFontString(fs)

  if (cfg.highlight ~= false) then
    frame:SetHighlightTexture(cfg.highlight or
      "Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
  end

  frame.SetTexture = ib_SetTexture
  frame.SetSelected = ib_SetSelected
  frame.OnEnable = ib_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetTexture(cfg.texture, cfg.texcoord)

  if (cfg.color) then
    image:SetVertexColor(cfg.color.r or 1, cfg.color.g or 1, cfg.color.b or 1,
      cfg.color.a or 1)
  end

  frame:SetText(cfg.text or "")
  check_tooltip_title(frame, cfg, cfg.text)

  if (cfg.push ~= false) then
    frame:HookScript("OnMouseDown", ib_OnMouseDown)
    frame:HookScript("OnMouseUp", ib_OnMouseUp)
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
  -- A second click is a second intention rather than a repeat of the first:
  -- pick this one, then go into it. Wired only when the caller asks for it,
  -- because WoW gives the second click of a pair to OnDoubleClick INSTEAD of
  -- OnClick, and a button with no use for the distinction would have every
  -- other click quietly go missing.
  --
  if (cfg.doubleclick) then
    frame:SetScript("OnDoubleClick", function(this, ...)
      this:Throw("OnDoubleClick", ...)
    end)
  end

  frame:SetEnabled(cfg.enabled)
  return frame
end

--
-- A tabbed dialog has two independent strips of buttons. They are different
-- things with different geometry and different templates, and the words for
-- them are used strictly throughout this file:
--
--   PAGES are the buttons along the BOTTOM edge of the dialog. A page is a
--   whole screen. It owns a frame, a content area, a top bar and a title.
--
--   TABS are the buttons along the TOP of a page, drawn in that page's top
--   bar. A page may have any number of tabs; a tab may not have tabs of its
--   own.
--
-- Both are addressed by NAME everywhere in this API, never by position. A
-- page or a tab carries an "order", and that decides only where in its strip
-- it is drawn. Position shifts whenever something is hidden, added or
-- removed; a name does not, which is the entire point of the distinction.
--
--
-- The pages hang below the window, tucked under its bottom border. There is
-- not much room to move here: the tab art is drawn to meet that border, so
-- dropping them any further shows daylight between the two.
--
local PAGE_STRIP = {
  point = "BOTTOMLEFT", x = 15, y = 0, chainx = -16, chainy = 0,
  template = "CharacterFrameTabButtonTemplate",
}

local TAB_STRIP = {
  point = "BOTTOMLEFT", x = 0, y = 28, chainx = 0, chainy = 0,
  template = "TabButtonTemplate",
}

local function order_sorter(a, b)
  return (tonumber(a.order) or 0) < (tonumber(b.order) or 0)
end

--
-- Re-anchor a strip of buttons, skipping the hidden ones so that the strip
-- closes up instead of leaving a hole where a button used to be. Every path
-- that changes what is visible in a strip finishes here.
--
local function strip_relayout(list, anchor, geom)
  local prev = nil

  for k, v in ipairs(list) do
    local tb = v.tbutton

    if (tb) then
      if (v.hidden) then
        tb:Hide()
      else
        tb:ClearAllPoints()
        if (prev) then
          tb:SetPoint("TOPLEFT", prev, "TOPRIGHT", geom.chainx, geom.chainy)
        else
          tb:SetPoint("TOPLEFT", anchor, geom.point, geom.x, geom.y)
        end
        tb:Show()
        prev = tb
      end
    end
  end
end

--
-- Highlight the button named SELNAME and un-highlight every other one. We
-- drive the buttons individually rather than calling PanelTemplates_SetTab,
-- because that helper locates its buttons by iterating over
-- _G[frame:GetName() .. "Tab" .. i], which would force every button name to
-- encode its position in the strip. Our buttons are named for their page or
-- tab, so the selection is done here instead.
--
local function strip_select(list, selname)
  for k, v in ipairs(list) do
    if (v.tbutton) then
      if (v.name == selname) then
        PanelTemplates_SelectTab(v.tbutton)
      else
        PanelTemplates_DeselectTab(v.tbutton)
      end
    end
  end
end

--
-- The name of the first entry in LIST that is not hidden, or nil if every
-- one of them is.
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
-- Where to go when the entry named NAME stops being available. We look to
-- the LEFT first, because a strip reads left to right and the neighbour
-- before the one that went away is where the eye already is. Only if nothing
-- to the left is visible do we look right. If the strip has nothing visible
-- left at all we return nil, and the caller shows nothing -- an empty strip
-- is a legitimate state, not an error.
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
-- Build the frames for one page: its full-size frame, its content area, its
-- top bar, and its button on the bottom strip. This is split out from
-- CreateTabbedDialog so that AddPage() can build a page long after the
-- dialog itself exists. Every frame is named for the page rather than for
-- its position, because a position moves and a WoW frame name cannot.
--
local function build_page(frame, cfg)
  local fname = frame:GetName()

  --
  -- The caller's own config table is kept as .cfg. KoreUI never looks inside
  -- it beyond the fields below, but a caller commonly wants to hang its own
  -- meaning on a page -- who may see it, which subsystem owns it -- and this
  -- saves it keeping a parallel table keyed by page name.
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
  -- A page's content is the dialog's content, and its top bar the dialog's
  -- top bar: the same rectangles rather than the same numbers written down
  -- twice, which is how they came to disagree.
  --
  -- cfg.padding insets it. A page that puts widgets straight onto its content
  -- wants it, because nothing else is standing them off the dialog's edge; a
  -- page that declares a split does not, because the split's panels bring
  -- their own padding and this would be added to it.
  --
  local pp = padding_sides(cfg.padding, 0)
  local pcf = MakeFrame("Frame", pf:GetName() .. "Content", pf)
  pcf:SetPoint("TOPLEFT", frame.content, "TOPLEFT", pp.left, 0 - pp.top)
  pcf:SetPoint("BOTTOMRIGHT", frame.content, "BOTTOMRIGHT", 0 - pp.right, pp.bottom)
  pcf.pagename = pg.name
  pg.content = pcf

  --
  -- If the caller asked for a split, reserve the space now. Only one of the
  -- two is honoured; setting both is not supported.
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

  local tb = MakeFrame("Button", fname .. "Tab" .. pg.name, frame,
    PAGE_STRIP.template)
  tb:SetText(pg.text)
  tb.pagename = pg.name
  PanelTemplates_TabResize(tb, 0)
  tb:SetScript("OnClick", function(this)
    this:GetParent():SetPage(this.pagename)
  end)
  tb.SetShown = BC.SetShown
  pg.tbutton = tb

  return pg
end

--
-- Build one tab inside page PG: its content frame and its button on that
-- page's top strip. Where the page has a split and asked, through tabframe,
-- for only one side of it to change as tabs are selected, the tab's content
-- covers just that side; otherwise it covers the whole page content.
--
local function build_tab(frame, pg, cfg)
  local tab = {
    name = cfg.name,
    text = cfg.text,
    order = cfg.order,
    hidden = cfg.hidden and true or false,
    onclick = cfg.onclick,
    cfg = cfg,
  }

  local stcontent = pg.content

  if (pg.tabframe and (pg.vsplit or pg.hsplit)) then
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
  local scf = MakeFrame("Frame",
    pg.content:GetName() .. "Sub" .. tab.name, stcontent)
  scf:SetPoint("TOPLEFT", stcontent, "TOPLEFT", sp.left, 0 - sp.top)
  scf:SetPoint("BOTTOMRIGHT", stcontent, "BOTTOMRIGHT", 0 - sp.right, sp.bottom)
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
  -- The button is a child of the page frame even though it is anchored to
  -- that page's top bar, so that hiding the page hides its tab strip too.
  --
  local stb = MakeFrame("Button", pg.frame:GetName() .. "Tab" .. tab.name,
    pg.frame, TAB_STRIP.template)
  stb:SetText(tab.text)
  stb.pagename = pg.name
  stb.tabname = tab.name
  PanelTemplates_TabResize(stb, 0)
  stb:SetScript("OnClick", function(this)
    frame:SetPage(this.pagename, this.tabname)
  end)
  stb.SetShown = BC.SetShown
  tab.tbutton = stb

  return tab
end

--
-- Select the page named PAGENAME and, within it, the tab named TABNAME.
-- Both are optional. A nil page means "whichever is current, else the
-- default, else the first visible one", and a nil tab means the same within
-- the chosen page. Naming a page that does not exist, or one that is hidden,
-- falls back the same way, so a caller never has to check first.
--
-- Returns the page name and tab name actually selected, or nil if every page
-- is hidden.
--
local function td_SetPage(self, pagename, tabname)
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
  -- Nothing is visible. Show no page at all and fall back to the dialog's
  -- own title.
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

  if (pg.title) then
    self.title:SetText(pg.title)
  elseif (self.titletext and self.titletext ~= "") then
    self.title:SetText(self.titletext)
  elseif (self.maintitle and self.maintitle ~= "") then
    self.title:SetText(self.maintitle)
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
  -- A page with no tabs at all, or one whose tabs are all hidden, is
  -- perfectly normal: its own content frame is the whole page.
  --
  if (not tab) then
    pg.currenttab = nil

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
local function td_SetTab(self, tabname)
  return td_SetPage(self, self.currentpage, tabname)
end

local function td_GetPage(self, pagename)
  return self.pagesbyname[pagename or self.currentpage or ""]
end

local function td_GetTab(self, pagename, tabname)
  local pg = td_GetPage(self, pagename)

  if (not pg) then
    return nil
  end

  return pg.tabsbyname[tabname or pg.currenttab or ""]
end

--
-- Show or hide the page named PAGENAME. The strip closes up around it, and
-- if the page being hidden was the current one we move to its nearest
-- visible neighbour rather than leaving the dialog showing nothing.
--
local function td_SetPageShown(self, pagename, onoff)
  local pg = self.pagesbyname[pagename]

  if (not pg) then
    return
  end

  local hidden = (onoff == false)

  if (pg.hidden == hidden) then
    return
  end

  local fallback = nearest_visible(self.pages, pagename)

  pg.hidden = hidden
  strip_relayout(self.pages, self, PAGE_STRIP)

  if (hidden) then
    if (self.currentpage == pagename) then
      td_SetPage(self, fallback)
    end
  elseif (not self.currentpage) then
    td_SetPage(self, pagename)
  end
end

--
-- Show or hide one tab of one page. As with pages, the strip closes up and
-- a hidden current tab moves to its nearest visible neighbour.
--
local function td_SetTabShown(self, pagename, tabname, onoff)
  local pg = self.pagesbyname[pagename]

  if (not pg) then
    return
  end

  local tab = pg.tabsbyname[tabname]

  if (not tab) then
    return
  end

  local hidden = (onoff == false)

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
      td_SetPage(self, pagename, fallback)
    end
  elseif (not pg.currenttab) then
    td_SetPage(self, pagename, tabname)
  end
end

--
-- Add a page to the dialog after it has been created. If a page of this
-- name was removed earlier its frames are reused, because WoW frames cannot
-- be destroyed and creating a fresh set on every add would leak them for the
-- life of the session. CFG takes the same fields as a page in the tabs
-- config passed to CreateTabbedDialog, including its own tabs.
--
local function td_AddPage(self, cfg)
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
    td_SetPage(self, pg.name)
  end

  return pg
end

--
-- Remove the page named PAGENAME. Its frames are retired rather than
-- destroyed -- WoW has no way to destroy a frame -- and are reused if a page
-- of the same name is added again later.
--
local function td_RemovePage(self, pagename)
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
    td_SetPage(self, fallback)
  end
end

--
-- Add a tab to an existing page, reusing a retired tab of the same name if
-- there is one, for the same reason AddPage does.
--
local function td_AddTab(self, pagename, cfg)
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
    td_SetPage(self, pagename, tab.name)
  end

  return tab
end

--
-- Remove a tab from a page, retiring its frames for reuse.
--
local function td_RemoveTab(self, pagename, tabname)
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
      td_SetPage(self, pagename, fallback)
    else
      pg.currenttab = fallback
    end
  end
end

--
-- A tabbed dialog is Blizzard's PortraitFrameTemplate: the same window the
-- Social pane is, and the one this addon's own border art was cut from. It
-- brings the round portrait with its circular mask, the stippled rock ground,
-- the title band and streaks above it, and tiling borders down every side, so
-- it resizes -- which the pre-composed panels of a fixed-size stock window
-- cannot do, and which is why that art had been re-cut by hand.
--
-- Not ButtonFrameTemplate, which is this plus a bar along the bottom for a
-- row of buttons: thirty-two pixels reserved and a three pixel divider drawn
-- above them. This window's page buttons hang below its bottom edge, so that
-- bar is a line across nothing.
--
-- The geometry is written down in SharedUIPanelTemplates.xml rather than
-- measured off a screenshot. The sides and the top are the insets Blizzard
-- gives its own content frame; the bottom is the height of _UI-Frame-Bot,
-- the border tile itself, there being no button bar to clear.
--
-- One off the top of that 60: the tabs stand on the client area, and at the
-- number Blizzard writes down they leave a hairline of the window's ground
-- under their feet.
--
local TD_INSET = { left = 4, top = 59, right = 6, bottom = 6 }

--
-- What the portrait takes out of the top left corner, which is what the tab
-- strip and the title both start clear of. Blizzard's TitleText uses the same
-- number for the same reason.
--
local TD_PORTRAIT = 60

--
-- How far the black client backing runs past the content: up to meet the
-- foot of the tab buttons, and down to meet the window's bottom border
-- without painting over it.
--
local TD_BLEED_TOP = 2
local TD_BLEED_BOT = 2

--
-- How far the tab strip's frame stands above the content. The tab art is
-- drawn to meet what it opens on to, so this is what decides whether their
-- feet sit on the client area or a hair off it.
--
local TD_BARGAP = 9

function KUI:CreateTabbedDialog(cfg, kparent)
  local fname = cfg.name or("KUITabbedDlg"..self:GetWidgetNum("tabbeddialog"))

  --
  -- CreateFrame raises on a template it does not know rather than returning
  -- nil, so the stock one is tried behind a pcall and a plain bordered frame
  -- stands in where there is none. A flatter window is a great deal better
  -- than an addon that will not load.
  --
  local ok, frame, parent, width, height = pcall(newobj, cfg, kparent, 512, 512, fname, nil, "PortraitFrameTemplate")

  if (not ok) then
    frame, parent, width, height = newobj(cfg, kparent, 512, 512, fname)

    local bd = borders[2]

    frame:SetBackdrop({ bgFile = bd.bgFile, edgeFile = bd.edgeFile, tile = true, tileSize = bd.tileSize,
      edgeSize = bd.edgeSize, insets = bd.insets })
    frame:SetBackdropColor(0, 0, 0, 1)
  end

  frame.stockframe = ok

  frame:SetMovable(cfg.canmove and true or false)
  frame:EnableMouse(true)
  frame:SetFrameStrata(cfg.strata or "FULLSCREEN_DIALOG")
  frame:Hide()

  local tspec = cfg.title

  if (type(tspec) ~= "table") then
    tspec = { text = tspec }
  end

  frame.maintitle = tspec.text or ""
  frame.onclick = cfg.onclick

  --
  -- The addon's logo goes in the portrait the template already draws, where
  -- the circular mask that comes with it crops it to the ring. Nothing here
  -- places or sizes it: that is the template's business and it has done it.
  --
  if (frame.portrait) then
    frame.portrait:SetTexture(cfg.tltexture or "Interface/FriendsFrame/FriendsFrameScrollIcon")

    --
    -- A texture cannot be clicked, so an invisible button is laid over the
    -- portrait and handed back for a caller that wants the corner to mean
    -- something. It throws OnDoubleClick only: a single click on a window's
    -- own badge is how you drag the window, and taking that away to make the
    -- badge a button would be a poor trade.
    --
    local pb = MakeFrame("Button", nil, frame)
    pb:SetAllPoints(frame.portrait)
    pb:EnableMouse(true)
    pb:RegisterForClicks("AnyUp")
    pb.events = {}
    pb.Catch = BC.Catch
    pb.Throw = BC.Throw
    pb:SetScript("OnDoubleClick", function(this, ...)
      this:Throw("OnDoubleClick", ...)
    end)
    frame.portraitbutton = pb
  end


  --
  -- The template's own close button, wired to throw OnClose the way every
  -- other window here does rather than merely hiding itself.
  --
  if (frame.CloseButton) then
    frame.CloseButton:SetScript("OnClick", xbutton_OnClick)
  else
    local xbutton = MakeFrame("Button", nil, frame, "UIPanelCloseButton")
    xbutton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    xbutton:SetScript("OnClick", xbutton_OnClick)
  end


  --
  -- The title is the template's own font string where there is one, already
  -- placed in the band and already clear of the portrait. It stays a font
  -- string rather than becoming a plate, because the words change every time
  -- a page or a tab is selected and SetPage sets them by calling SetText.
  --
  local title = frame.TitleText

  if (not title) then
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -5)
    title:SetPoint("LEFT", frame, "LEFT", TD_PORTRAIT, 0)
    title:SetPoint("RIGHT", frame, "RIGHT", 0 - TD_PORTRAIT, 0)
    title:SetJustifyH("CENTER")
  end

  if (tspec.font) then
    title:SetFontObject(tspec.font)
  end

  title:SetText("")
  frame.title = title

  --
  -- The band the title sits in is the drag handle, and it is the whole width
  -- of the window down to where the content starts.
  --
  local tframe = MakeFrame("Frame", nil, frame)

  tframe:EnableMouse(true)
  tframe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  tframe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  tframe:SetHeight(24)

  if (cfg.canmove) then
    tframe:SetScript("OnMouseDown", parent_StartMoving)
    tframe:SetScript("OnMouseUp", parent_StopMoving)
  end

  local seframe, swframe, soframe = make_resizeable(frame, 25, cfg.canresize)
  if (seframe) then
    frame:SetResizeBounds(cfg.minwidth or 192, cfg.minheight or 192, cfg.maxwidth or 1024, cfg.maxheight or 1024)

    -- This "draws" the little chevron at the bottom right corner that the user
    -- can drag to resize.
    local line1 = seframe:CreateTexture(nil, "BACKGROUND")
    line1:SetTexture(137057) -- Interface/Tooltips/UI-Tooltip-Border
    line1:SetWidth(8)
    line1:SetHeight(8)
    line1:SetPoint("BOTTOMRIGHT", -8, 8)
    line1:SetTexCoord(-0.03, 0.05, 0.05, 0.13, 0.05, 0.42, 0.58, 0.5)
  end

  --
  -- For convenience sake and to keep things consistent with the rest of
  -- this code, we set a content frame. This will remain static no matter
  -- what tab is selected. However, we also set a tabcontent frame. This
  -- will be updated in the returned table each time a different tab is
  -- selected. The user can also select any individual tab's content
  -- pointer using ret.tabs[id].content.
  --
  frame.content = MakeFrame("Frame", fname .. "Content", frame)
  frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", TD_INSET.left, 0 - TD_INSET.top)
  frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0 - TD_INSET.right, TD_INSET.bottom)

  --
  -- cfg.blackbg blacks out the content rectangle only. The rock ground the
  -- template brings reads well behind a header, and reads as noise behind a
  -- screen that is mostly panels -- so the header keeps it and the part that
  -- holds the panels does not.
  --
  if (cfg.blackbg) then
    local cbg = frame.content:CreateTexture(nil, "BACKGROUND")

    --
    -- Taller than the content at both ends, so no hairline of the ground is
    -- left showing between it and the tab buttons above or the border below.
    -- The content is not moved: this is the backing behind it, not the room
    -- in it.
    --
    cbg:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, TD_BLEED_TOP)
    cbg:SetPoint("BOTTOMRIGHT", frame.content, "BOTTOMRIGHT", 0, 0 - TD_BLEED_BOT)
    cbg:SetTexture(WINDOW_BG)
    cbg:SetVertexColor(0, 0, 0, 1)
  end

  --
  -- The tab strip stands in the band between the title and the content,
  -- starting clear of the portrait. Its height and its distance above the
  -- content are what they have always been, so the tabs keep the position in
  -- the band that TAB_STRIP was set up for.
  --
  local barbot = TD_INSET.top - TD_BARGAP
  local bartop = barbot - 32

  frame.topbar = MakeFrame("Frame", fname .. "TopBar", frame)
  frame.topbar:SetPoint("TOPLEFT", frame, "TOPLEFT", TD_PORTRAIT, 0 - bartop)
  frame.topbar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0 - TD_INSET.right, 0 - barbot)

  if (cfg.escclose) then
    add_escclose(fname)
  end

  --
  -- Build every page named in the config, and every tab inside each of
  -- them. The config tables are keyed by name and pairs() does not promise
  -- an order, which is exactly why each entry carries an explicit "order"
  -- that we sort on afterwards.
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

  frame.SetPage = td_SetPage
  frame.SetTab = td_SetTab
  frame.GetPage = td_GetPage
  frame.GetTab = td_GetTab
  frame.SetPageShown = td_SetPageShown
  frame.SetTabShown = td_SetTabShown
  frame.AddPage = td_AddPage
  frame.RemovePage = td_RemovePage
  frame.AddTab = td_AddTab
  frame.RemoveTab = td_RemoveTab

  frame:SetPage(cfg.defpage)

  return frame
end

--
-- This function is used to set the current item in a list. It is called
-- from several places. First, when a list is being updated with new items
-- it is called with a nil offset to disable any current selection. This
-- is because the current selection may no longer be valid after the list
-- is updated. Thus it is the caller's responsibility to remember any
-- current position if restoring the current selection is important.
-- Second, it is called when a list item is clicked. It is not called
-- directly, but through the containing list's :SetSelected() method. The
-- default helper functions do this correctly but if the code implements
-- its own newitem method, it must set the OnClick handler to call the
-- :SetSelected() method itself.
-- When a new offset is selected, this code ensures that the previously
-- selected entry has its highlight removed and its deselection routine run.
-- It then highlights the new entry, and runs its selection method. Thus all
-- of the logic for dealing with the selection is here in this function.
--
local function sl_setsel(objp, offset, force)
  local i
  local nslot = nil
  local nbtn = nil
  local ro

  if (offset and (offset > objp.itemcount or offset <= 0)) then
    offset = nil
  end

  if (objp.selecteditem) then
    -- We have a currently selected item. If the new offset is not the same
    -- as the current selection, we need to remove the highlight, and run
    -- the current selected items deselection function.
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
      -- The new offset is not the same as the current. If the current one
      -- is being displayed at the moment, remove its highlight.
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
    -- If we have a new offset and it would be visible, turn on its highlight
    -- and run its selection function. If it wouldnt be visible just run the
    -- selection function.
    if (nbtn) then
      objp:highlightitem(offset, nslot, nbtn, true)
    end
    objp:selectitem(offset, nslot, nbtn, true)
  else
    -- No offset, we're setting the offset to nil. No need to deal with any
    -- highlights here, just call the selection function appropriately.
    objp:selectitem(nil, nil, nil, nil)
  end
end

local function sl_setrem_highlight(objp, onoff)
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
-- How many visual elements a list needs. A list that scrolls by whole items
-- needs only as many as fit; one that scrolls smoothly needs one more, because
-- at every position but the top there is a part of an item showing at each end.
--
local function sl_slotcount(objp)
  local n = floor(objp:GetHeight() / objp.itemheight)

  if (objp.smoothscroll) then
    n = n + 1
  end

  return n
end

local function sl_vertscroll(objp, offset)
  sl_setrem_highlight(objp, false)
  local sb = objp.scrollbar
  local sel = objp.selecteditem
  objp.visibleslots = sl_slotcount(objp)

  --
  -- Scrolling by whole items stops when the last item is in the bottom slot;
  -- scrolling smoothly stops when the bottom of the last item reaches the
  -- bottom of the list, which is a little further and is what lets the final
  -- part item be brought fully into view.
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
    -- The item offset is which item is at the top. Scrolling smoothly keeps
    -- the leftover pixels as well, and the slots are shifted up by that much
    -- so the top item is cut off rather than snapped away.
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
    objp.slots[1]:SetPoint("TOPLEFT", objp, "TOPLEFT", 0,
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
    end
  end

  if (objp:IsShown()) then
    local upb = _G[sb:GetName() .. "ScrollUpButton"]
    local dnb = _G[sb:GetName() .. "ScrollDownButton"]
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

    if (objp.offset > maxoffs) then
      objp.offset = maxoffs
      sb:SetValue(maxoffs)
    end

    if (sb:GetValue() == 0) then
      upb:Disable()
    else
      upb:Enable()
    end
    if (sb:GetValue() - maxoffs == 0) then
      dnb:Disable()
    else
      dnb:Enable()
    end
  end
  sl_setrem_highlight(objp, true)
end

local function sl_updatevals(objp)
  sl_setrem_highlight(objp, false)
  local dispheight = objp:GetHeight()
  local fullheight = objp.content:GetHeight()
  local numvisible = sl_slotcount(objp)
  local desiredheight = objp.itemcount * objp.itemheight
  local rslot = nil
  local rbtn = nil

  if (numvisible > objp.numslots) then
    for i = objp.numslots+1, numvisible do
      objp.slots[i] = objp.newitem(objp, i)
      if (i == 1) then
        objp.slots[i]:SetPoint("TOPLEFT", objp, "TOPLEFT", 0, 0)
      else
        objp.slots[i]:SetPoint("TOPLEFT", objp.slots[i-1], "BOTTOMLEFT", 0, 0)
      end
      objp.slots[i]:Hide()
    end
    objp.numslots = numvisible
  end

  for i = 1, numvisible do
    local ro = i + objp.offset
    if (ro <= objp.itemcount) then
      objp.slots[i]:Show()
      objp.slots[i]:SetID(ro)
      objp:setitem(ro, i, objp.slots[i])
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
  -- Scrolling smoothly has a slot more than fits, so counting slots would say
  -- there is nothing to scroll while the last item is still half off the
  -- bottom. What matters is whether the items are taller than the list.
  --
  local needbar

  if (objp.smoothscroll) then
    needbar = desiredheight > dispheight
  else
    needbar = numvisible < objp.itemcount
  end

  if (needbar) then
    objp.scrollbar:Show()
    objp.scrollbar:SetValue(objp.scrollbar:GetValue() or 0)
  else
    objp.scrollbar:Hide()
  end

  sl_setrem_highlight(objp, true)
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
    cfg.getbutton = get_radiowidget
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
    ret.editbox:HookScript("OnEnter", tl_OnEnter)
    ret.editbox:HookScript("OnLeave", tl_OnLeave)
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
    cfg.template = ti.template
    tbf.height = cfg.height
    tbf.width = cfg.width
    tbf.checkable = false
    ret = KUI:CreateButton(cfg, tbf)
  else
    assert(false, "unknown or missing widget type")
  end

  ret.toplevel = tbf.toplevel
  ret.parent = tbf.parent
  ret:HookScript("OnEnter", tl_OnEnter)
  ret:HookScript("OnLeave", tl_OnLeave)
  return ret
end

--
-- Please note that this element type completely fills the parent frame,
-- and that the width and height config elements are ignored. If you require
-- a specific size, ensure that the parent specified is of the correct size.
--

function KUI:CreateScrollList(cfg, kparent)
  local x = self:GetWidgetNum("scrolllist")
  local fname = cfg.name or ("KUIScrollList" .. x)
  local frame, parent, width, height = newobj(cfg, kparent, 0, 0, fname, "ScrollFrame")
  local sname = "KUIScrollBar" .. self:GetWidgetNum("scrollbar")
  local scrollbar = MakeFrame("Slider", sname, frame, "UIPanelScrollBarTemplateLightBorder")
  local content = MakeFrame("Frame", nil, frame)

  assert(cfg.newitem)
  assert(cfg.setitem)
  assert(cfg.selectitem)
  assert(cfg.highlightitem)

  local scrollbg = scrollbar:CreateTexture(nil, "BACKGROUND")
  scrollbg:SetAllPoints(scrollbar)
  scrollbg:SetColorTexture(0, 0, 0, 0.4)

  frame.scrollbar = scrollbar
  frame.offset = 0
  frame.content = content

  --
  -- Held one clear of the left edge so that a selected row's highlight does
  -- not sit flush against whatever the list is inside, and SCROLLBAR_COMPENSATE
  -- clear on the right for the scrollbar, which lives in that strip.
  --
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, 0)
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 - KUI.SCROLLBAR_COMPENSATE, 0)
  frame:SetScrollChild(content)
  frame:EnableMouseWheel(true)
  scrollbar:EnableMouseWheel(true)

  --
  -- itemheight is the height of each individual item in the list.
  -- newitem is a function that is called to create a new item slot when the
  -- window size changes and the code needs a new item to display a list
  -- entry. This code will only ever create more item slots, it will never
  -- reduce them, so the maximum number of slots is always the largest the
  -- window has ever been. If the window is shrunk, there will be excess
  -- item slots that simply go unused.
  -- setitem is called to set an individual item in the list. It is passed
  -- the real index (from list item 1) as well as the slot index and the
  -- return value from newitem() for that slot.
  --
  frame.itemheight = cfg.itemheight
  frame.newitem = cfg.newitem
  frame.setitem = cfg.setitem
  frame.selectitem = cfg.selectitem
  frame.highlightitem = cfg.highlightitem
  frame.smoothscroll = cfg.smoothscroll and true or false
  frame.slots = {}
  frame.numslots = 0
  frame.visibleslots = 0
  frame.itemcount = 0
  frame.pixeloffset = 0

  --
  -- Whether the bar is wanted is decided in sl_updatevals, which only runs on
  -- UpdateList. A list is built empty and may never be updated at all, so it
  -- starts with the bar hidden rather than with whatever the stock template
  -- left showing: an empty list wearing a scroll bar is a lie about having
  -- something to scroll to.
  --
  scrollbar:Hide()

  --
  -- Half the bar's height is half a page, which reads as a page turn on a list
  -- of text rows. A list that scrolls smoothly is one whose items are big, so
  -- a notch there moves half an item and the movement can be seen.
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
      sl_updatevals(this)
      sl_vertscroll(this, nil)
    end
  end)

  frame:HookScript("OnVerticalScroll", function(this, offset)
    sl_vertscroll(this, offset)
  end)

  content:ClearAllPoints()
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  scrollbar:ClearAllPoints()
  scrollbar:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, -20)
  scrollbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 4, 20)

  frame.UpdateList = function(this)
    this.ever_updated = true
    this.selecteditem = nil
    for i = 1, this.visibleslots do
      this.highlightitem(this, nil, 1, this.slots[i], false)
    end
    sl_setsel(this, nil, false)
    sl_updatevals(this)
    sl_vertscroll(this, nil)
  end

  frame.SetSelected = function(this, offset, display, force)
    sl_setsel(this, offset, force)
    if (display and offset) then
      sl_vertscroll(this, (offset - 1) * this.itemheight)
    end
  end

  frame.GetSelected = function(this)
    return this.selecteditem
  end

  return frame
end

--
-- These functions are helper functions for dealing with scroll lists.
-- Most often, scroll lists are lists of text items that need to have
-- something happen when they are selected, deselected and clicked.
-- Most of the code can be shared, and these helper functions do most of
-- the common stuff. They provide opportunities for the caller to
-- provide custom functions for various tasks.
--
function KUI.NewItemHelper(objp, num, name, w, h, stf, och, ocs, pch)
  local bname = name .. tostring(num)
  local rf = MakeFrame("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth(w or 160)
  rf:SetHeight(h or 16)
  rf:SetHighlightTexture(htn, "ADD")

  local text = rf:CreateFontString(nil, "ARTWORK", nfn)
  text:ClearAllPoints()
  text:SetPoint("TOPLEFT", rf, "TOPLEFT", 8, -2)
  text:SetPoint("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -8, 2)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  rf.text = text

  rf.SetText = stf or function(self, txt)
    self.text:SetText(txt)
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
      if (rv == false) then
        error("Severe logic bug! Please report to me@cruciformer.com", 1)
        return
      end
    end

    if (onfn) then
      return onfn(objp, idx, slot, btn, true)
    end
  elseif (onoff == false) then
    if (offfn) then
      return offfn(objp, idx, slot, btn, onoff)
    end
  elseif (onoff == nil) then
    if (nilfn) then
      return nilfn(objp, idx, slot, btn, nil)
    end
    if (offfn) then
      return offfn(objp, idx, slot, btn, nil)
    end
  end
end

function KUI.HighlightItemHelper(objp, idx, slot, btn, onoff, onfn, offfn)
  if (onoff) then
    local normal_texture_nm = "Interface/AuctionFrame/UI-AuctionFrame-FilterBg"
    btn:SetNormalTexture(normal_texture_nm)
    local normal_texture = btn:GetNormalTexture()
    normal_texture:SetTexCoord(0, 0.53125, 0, 0.625)

    if (onfn) then
      return onfn(objp, idx, slot, btn, true)
    end
    return
  else
    local normal_texture = btn:GetNormalTexture()
    if (normal_texture) then
      normal_texture:SetTexture(nil)
    end
    if (offfn) then
      return offfn(objp, idx, slot, btn, false)
    end
  end
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

local function start_countdown(this)
  this.timeout_start = GetTime()
  this:SetScript("OnUpdate", cd_OnUpdate)
end

local function tl_OnShow(this)
  this.toplevel:StartTimeoutCounter()
  this.toplevel.screenw = GetScreenWidth()
  this.toplevel.screenh = GetScreenHeight()
  this.toplevel.scale = UIParent:GetEffectiveScale()
end

local function tl_OnHide(this)
  this.toplevel:StopTimeoutCounter()
  if (this.toplevel.subopen) then
    this.toplevel.subopen:Close()
    this.toplevel.subopen = nil
  end
end

-- Forward declared at the top of this file.
function tl_OnEnter(this)
  this.toplevel:StopTimeoutCounter()
  do_tooltip_onenter(this, this.enabled or false)
end

function tl_OnLeave(this)
  this.toplevel:StartTimeoutCounter()
  GameTooltip:Hide()
end

local function dd_OnEnter(this)
  this.toplevel:StopTimeoutCounter()
  do_tooltip_onenter(this.toplevel, this.toplevel.enabled or false)
end

local function dd_OnLeave(this)
  this.toplevel:StartTimeoutCounter()
  GameTooltip:Hide()
end

local function parent_OnEnter(this)
  this:GetParent().toplevel:StopTimeoutCounter()
end

local function parent_OnLeave(this)
  this:GetParent().toplevel:StartTimeoutCounter()
end

local function dd_Close(self)
  if (self.subopen) then
    self.subopen:Close()
    self.subopen = nil
  end
  self:Hide()
  tremove(self.toplevel.lastpos)
end

local function nfr_OnEnter(this)
  this.toplevel:StopTimeoutCounter()
  if (this.parent.subopen) then
    this.parent.subopen:Close()
    this.parent.subopen = nil
  end

  if (this.menuframe and this.enabled) then
    local os = this.toplevel.offset
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

local function nfr_OnLeave(this)
  this.toplevel:StartTimeoutCounter()
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
-- This is only ever used by the individual line items in a dropdown or popup
-- menu, which is reached via this.toplevel. The THIS parameter is the actual
-- button frame itself (i.e. the line item in a scroll list).
--
local function nfr_OnClick(this)
  local tlf = this.toplevel
  local tlc = tlf.current

  if ((not this.clickable) or (not this.enabled)) then
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
      tlf.dropdown:Close()
    end
    run_funcs(this, false)
    return
  end

  if (tlc) then
    if (tlc == this) then
      if (not this.keep) then
        tlf.dropdown:Close()
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
  if (not this.keep) then
    tlf.dropdown:Close()
  end

  if ((tlf.mode == MODE_SINGLE) and this.text) then
    tlf.text:SetText(this.text:GetText())
    tlf.text:SetTextColor(this.text:GetTextColor())
  end
  tlf:Throw("OnItemChecked", this, this.value, this.checked)
  tlf:Throw("OnValueChanged", this.value, true, true)

  run_funcs(this, false)
end

local function nfr_OnHide(this)
  if (this.subopen) then
    this.subopen:Close()
    this.subopen = nil
  end
end

local function dd_SetJustification(this, just)
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

local global_dd_shown

local function dd_OnClick(this, ...)
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
      pdf:Show()
      global_dd_shown = pdf
      isshown = true
    end
  end
  pp:Throw("OnClick", pp, isshown, ...)
end

local function dd_OnMouseWheel(this, value)
  local sbf = this:GetParent().scrollbar
  local sv = floor(sbf:GetValueStep()) or 0
  local cv = sbf:GetValue() or 0
  local _, my = sbf:GetMinMaxValues()
  if (value > 0) then
    cv = cv - sv
  elseif (value < 0) then
    cv = cv + sv
  end
  if (cv < 0 or cv < sv) then
    cv = 0
  end
  if (cv > my) then
    cv = my
  end
  cv = (floor(cv/sv) * sv)
  sbf:SetValue(cv)
end

local function dd_OnValueChanged(this, val)
  local sf = this:GetParent().sframe
  sf:SetVerticalScroll(val)
  sf:UpdateScrollChildRect()
end

local function dd_OnScrollRangeChanged(this, x, y)
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

local function tl_OnEvent(this, event)
  if (event == "PLAYER_REGEN_ENABLED") then
    this.incombat = false
    this:Throw("OnLeaveCombat")
  elseif (event == "PLAYER_REGEN_DISABLED") then
    this.incombat = true
    this:Throw("OnEnterCombat")
  end
end

local function dd_item_init(item)
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
  item.hasvscroll = nil
  item.hasicons = nil
  item.hassub = nil
  item.hascheck = nil
  item.height = nil
  item.icon = nil
  item.idx = nil
  item.iinfo = nil
  item.keep = nil
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

local function dd_create_cframe(fr, cfname, ftype)
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
  dd_item_init(nfr)
  nfr:SetFrameStrata(fr.cframe:GetFrameStrata())
  nfr:SetFrameLevel(fr.cframe:GetFrameLevel() + 1)
  nfr.toplevel = fr.toplevel or fr
  nfr.parent = fr
  nfr.rparent = fr.cframe
  nfr:SetScript("OnEnter", nfr_OnEnter)
  nfr:SetScript("OnLeave", nfr_OnLeave)
  if (not ftype) then
    nfr:SetScript("OnClick", nfr_OnClick)
  end
  nfr:SetScript("OnHide", nfr_OnHide)
  return nfr
end

local create_dd_sa

local function dd_refresh_frame(fr, tlfr, ilist, nilist)
  if (tlfr == fr) then
    -- If this is the top level frame, set it to nil
    tlfr = nil
  end

  --
  -- The first step in the refresh is to go through the existing line items and see if they have any of the
  -- "extra" bits displayed - the submenu check, the check item check etc. So we go through the current list
  -- and hide any such markers.
  --
  if (fr.iframes) then
    for k,v in ipairs(fr.iframes) do
      if (v.p_checkmark) then
        v.p_checkmark:Hide()
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
  -- Set up the actual list item buttons. As we go through the list we
  -- calculate the widest button and whether or not any buttons have
  -- check marks, icons or submenu marks. We set the text for each
  -- button (with any color specified) and other button options.
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
    tbf = dd_create_cframe(fr, cfname, v.frame and "Frame" or nil)
    tbf:Show()
    tinsert(fr.iframes, tbf)

    tbf.iinfo = v
    tbf.idx = k
    tbf.arg = v.arg
    tbf.name = v.name
    tbf.func = v.func
    tbf.value = v.value
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
        -- This is a spacer
        if (not tbf.p_spacer) then
          local st = tbf:CreateTexture(nil, "ARTWORK")
          st:SetColorTexture(0.75, 0.75, 0.75, 1)
          st:Hide()
          tbf.p_spacer = st
        end
        tbf.spacer = tbf.p_spacer
        tbf.spacer:Show()
        txt = nil
        if (tbf.enabled) then
          SetDesaturation(tbf.spacer, false)
        else
          SetDesaturation(tbf.spacer, true)
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

    -- Adjust for submenus, icons and check marks
    if (v.submenu) then
      tbf.checkable = false
      hassub = 16
      if (not tbf.p_subarrow) then
        local sm = tbf:CreateTexture(nil, "ARTWORK")
        sm:SetTexture("Interface/ChatFrame/ChatFrameExpandArrow")
        sm:SetWidth(16)
        sm:SetHeight(16)
        sm:SetPoint("LEFT", tbf, "RIGHT", -16, 0)
        tbf.p_subarrow = sm
      end
      tbf.subarrow = tbf.p_subarrow
      tbf.subarrow:Show()
      if (tbf.enabled) then
        SetDesaturation(tbf.subarrow, false)
        tbf.menuframe = create_dd_sa(v.submenu, fr, fr.toplevel, nil)
      else
        SetDesaturation(tbf.subarrow, true)
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
      hasicons = 16
      if (not tbf.p_icon) then
        local it = tbf:CreateTexture(nil, "ARTWORK")
        if (type(v.icon) == "string") then
          it:SetTexture(v.icon)
        elseif (type(v.icon) == "function") then
          it:SetTexture(v.icon(tbf))
        else
          assert(false, "icon must be a string or a function")
        end
        it:SetWidth(16)
        it:SetHeight(16)
        it:ClearAllPoints()
        tbf.p_icon = it
      end
      tbf.icon = tbf.p_icon
      tbf.icon:SetTexture(v.icon)
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
      elseif (v.frame == true) then
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
    -- In case one of the functions called forced a width and height, set it
    -- to any preset values now.
    --
    if (tbf.width) then
      w = tbf.width
    end
    if (tbf.height) then
      h = tbf.height
    end

    if (tbf.checkable) then
      hascheck = 16
      if (not tbf.p_checkmark) then
        local cm = tbf:CreateTexture(nil, "ARTWORK")
        cm:SetTexture("Interface/Buttons/UI-CheckBox-Check")
        cm:SetWidth(16)
        cm:SetHeight(16)
        cm:ClearAllPoints()
        cm:SetPoint("LEFT", tbf, "LEFT", 0, 0)
        tbf.p_checkmark = cm
      end
      tbf.checkmark = tbf.p_checkmark
      if (not tbf.enabled) then
        SetDesaturation(tbf.checkmark, true)
      else
        SetDesaturation(tbf.checkmark, false)
      end
    else
      if (tbf.p_checkmark) then
        tbf.p_checkmark:Hide()
      end
      tbf.checkmark = nil
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
    -- If the item isn't disabled in any way (not a title, not explicitly
    -- disabled), set the button highlight texture. Otherwise clear it in
    -- case we are reusing a frame from a previous call to create this
    -- menu.
    --
    if (not tbf.frame) then
      if ((not tbf.enabled) or (not tbf.clickable)) then
        local hlt = tbf:GetHighlightTexture()
        if hlt then
          hlt:SetTexture(nil)
        end
      else
        tbf:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
      end
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
  -- Now adjust the width for possible submenu marks, scroll bars and for
  -- the checkmark. Then, size the frame and draw its borders, background
  -- etc.
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
  -- Now we need to loop through all of the item frames one last time and
  -- do the final positioning of all elements now that we know which
  -- extra elements will be displayed.
  --
  for k,v in ipairs(fr.iframes) do
    if (v.spacer) then
      v.spacer:ClearAllPoints()
      local vpos = floor(v.height / 2) - 1
      v.spacer:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -vpos)
      v.spacer:SetPoint("TOPRIGHT", v, "TOPRIGHT", fr.hassub * -1, -vpos)
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
      -- We can't just blindly show the check mark. If this is a SINGLE or
      -- COMPACT dropdown menu, only 1 item at a time can ever be checked.
      -- So, we look to see if we already have an entry checked, and if so,
      -- we uncheck it and mark this one as the current checked value.
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
  -- And last but not least, position the scrollbar and scroll frame
  -- within the main frame.
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
  -- Check to see if the window is currently larger than the min/maximum. This
  -- can happen when items are refreshed and the maximum size changes.
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
  -- By ordering things this way we catch the case where the maximum is
  -- actually less than the minimum.
  --
  if (cw > mxwidth) then
    fr:SetWidth(mxwidth)
  end
  if (ch > mxheight) then
    fr:SetHeight(mxheight)
  end
end

--
-- Only the top-level frame gets this function
--
local function dd_UpdateItems(this, newitems)
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
    dd_refresh_frame(this.dropdown, this.toplevel, newitems, ic)
    if (this.text) then
      if ((this.mode ~= MODE_SINGLE) and this.titletext) then
        this.text:SetText(this.titletext)
      else
        -- JKJ FIXME this is where we would set the title element if the first item is a title
        this.text:SetText("")
      end
    end
    if (oldv) then
      this:SetValue(oldv, true)
    end
    if (shown) then
      this.dropdown:Show()
      dd_OnEnter(this)
    end
  else
    this.current = nil
    dd_refresh_frame(this, this.toplevel, newitems, ic)
  end
end

local function dd_SetText(this, text)
  if (not this.dropdown or not this.text) then
    return
  end
  this.text:SetText(text)
end

local function dd_GetValue(this)
  local tl = this.toplevel
  if (not tl.current) then
    return nil
  end
  return tl.current.value
end

local function dd_SetValue(this, value, nothrow)
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
  if (tl.mode == MODE_SINGLE) then
    if (tl.current and tl.current.text) then
      local tt = tl.current.text
      local r,g,b,a = tt:GetTextColor()
      local d = this.enabled and 1 or 2
      this.text:SetText(tt:GetText())
      this.text:SetTextColor(r/d, g/d, b/d, a)
    elseif (tl.current and tl.current.frame) then
      this.text:SetText("")
    elseif (not tl.current) then
      this.text:SetText("")
    end
  end

  if (ret) then
    if (not nothrow) then
      tl:Throw("OnValueChanged", value, false)
    end
  end

  return ret
end

local function dd_OnEnable(this, event, onoff)
  local onoff = onoff or false

  this.enabled = onoff

  local button = this.button

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
      if (this.trgb) then
        this.text:SetTextColor(this.trgb.r/d, this.trgb.g/d, this.trgb.b/d, this.trgb.a)
      end
    else
      if (this.current and this.current.text) then
        local tt = this.current.text
        local r,g,b,a = tt:GetTextColor()
        this.text:SetTextColor(r/d,g/d, b/d, a)
      end
    end
  end
end

--
-- This is the workhorse function that creates the functional part of a
-- dropdown menu or a popup menu. This is the bit that contains the actual
-- items. It can call itself recursively if any of the items have submenus.
-- If this is the top-level menu, it is what is returned to the caller and
-- has two functions which each child must call when the cursor is over
-- the child: StopTimeoutCounter() when the cursor moves into a child frame
-- and StartTimeoutCounter() when it leaves.
--
-- This assigns the local forward declared above dd_refresh_frame, which is
-- what builds a submenu and therefore has to be able to reach this while
-- being written before it. Declaring it local again here would make a second
-- local and leave the one that function closed over nil.
--
function create_dd_sa(cfg, parent, toplevel, ispopup)
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
    -- This is a "dropdown" style frame. This has a controlling UI element
    -- that does not change, and then the actual dropped down portion which
    -- might. This is where we create the controlling UI element which will
    -- "house" the countdown timers and other events. The actual dropped
    -- down portion that will be displayed when the downarrow button is
    -- pressed is created by a recursive call to this function below.
    --
    local tn = "Interface/Glues/CharacterCreate/CharacterCreate-LabelFrame"
    local ppf
    --
    -- The frame is 24 and the artwork below is 32, drawn two pixels above the
    -- frame's top and hanging over its bottom. That is not a mistake: the
    -- LabelFrame slice is transparent for two pixels, opaque for twenty-four
    -- and transparent for the rest, so 24 is the box you see and 32 is the
    -- picture it is cut from, offset to bring the two into line.
    --
    -- The frame is the size of the box because GetHeight has to be able to
    -- answer "where does the next widget go". Dead space inside a frame makes
    -- it lie, and every caller then compensates by eye with a constant of its
    -- own -- which is what everything anchored inside here used to do.
    --
    frame, ppf = newobj(cfg, parent, 100, KUI.DROPDOWN_HEIGHT, cfg.name .. "DDContainer")
    frame:SetWidth(cfg.dwidth)
    frame:SetHeight(KUI.DROPDOWN_HEIGHT)

    local lt = frame:CreateTexture(frame:GetName() .. "Left", "ARTWORK")
    lt:SetTexture(tn)
    lt:SetTexCoord(0.125, 0.2109375, 0.25, 0.75)
    lt:SetWidth(12)
    lt:SetHeight(32)
    lt:SetPoint("TOPLEFT", frame, "TOPLEFT", 0 - KUI.DROPDOWN_ART_BLEED, 2)

    local rt = frame:CreateTexture(frame:GetName() .. "Right", "ARTWORK")
    rt:SetTexture(tn)
    rt:SetTexCoord(0.78128, 0.875, 0.25, 0.75)
    rt:SetWidth(12)
    rt:SetHeight(32)
    rt:SetPoint("TOPRIGHT", frame, "TOPRIGHT", KUI.DROPDOWN_ART_BLEED, 2)

    local mt = frame:CreateTexture(frame:GetName() .. "Middle", "ARTWORK")
    mt:SetTexture(tn)
    mt:SetTexCoord(0.2109375, 0.78128, 0.25, 0.75)
    mt:SetWidth(78)
    mt:SetHeight(32)
    mt:SetPoint("LEFT", lt, "RIGHT", 0, 0)
    mt:SetPoint("RIGHT", rt, "LEFT", 0, 0)

    local text = frame:CreateFontString(frame:GetName() .. "Text", "ARTWORK")
    frame.text = text
    text:SetFontObject("GameFontHighlightSmall")
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, 0)
    text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 0)
    text:SetWordWrap(false)

    local button = MakeFrame("Button", frame:GetName() .. "Button", frame)
    frame.button = button
    button.toplevel = frame
    button:SetWidth(24)
    button:SetHeight(24)
    button:ClearAllPoints()
    button:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    local bnt = button:CreateTexture(button:GetName() .. "NormalTexture")
    bnt:SetTexture("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Up")
    bnt:SetWidth(24)
    bnt:SetHeight(24)
    bnt:ClearAllPoints()
    bnt:SetPoint("RIGHT", button)

    local bpt = button:CreateTexture(button:GetName() .. "PushedTexture")
    bpt:SetTexture("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Down")
    bpt:SetWidth(24)
    bpt:SetHeight(24)
    bpt:ClearAllPoints()
    bpt:SetPoint("RIGHT", button)

    local bdt = button:CreateTexture(button:GetName() .. "DisabledTexture")
    bdt:SetTexture("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Disabled")
    bdt:SetWidth(24)
    bdt:SetHeight(24)
    bdt:ClearAllPoints()
    bdt:SetPoint("RIGHT", button)

    local bht = button:CreateTexture(button:GetName() .. "HighlightTexture")
    bht:SetTexture("Interface/Buttons/UI-Common-MouseHilight")
    bht:SetWidth(24)
    bht:SetHeight(24)
    bht:ClearAllPoints()
    bht:SetPoint("RIGHT", button)
    bht:SetBlendMode("ADD")

    button:SetNormalTexture(bnt)
    button:SetPushedTexture(bpt)
    button:SetDisabledTexture(bdt)
    button:SetHighlightTexture(bht)

    frame.OnEnable = dd_OnEnable
    frame.SetJustification = dd_SetJustification
    frame.UpdateItems = dd_UpdateItems
    frame.GetValue = dd_GetValue
    frame.SetValue = dd_SetValue
    frame.SetText = function(this, ...) return this.text:SetText(...) end
    frame.GetText = function(this, ...) return this.text:GetText(...) end
    frame.SetTextColor = function(this, ...) return this.text:SetTextColor(...) end
    frame.GetTextColor = function(this, ...) return this.text:GetTextColor(...) end
    frame.SetFont = function(this, ...) return this.text:SetFont(...) end
    frame.GetFont = function(this, ...) return this.text:GetFont(...) end

    button:SetScript("OnEnter", dd_OnEnter)
    button:SetScript("OnLeave", dd_OnLeave)
    button:SetScript("OnClick", dd_OnClick)

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
      label:SetWidth(lwidth)
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
          -- The label sits above the widget, so the pair of them is what has
          -- to be centred or placed: the widget goes half the difference
          -- below the centre, and cfg.y is where the label starts rather than
          -- where the widget does. Both are asked of the label rather than
          -- assumed, which is what CreateEditBox does with the same case.
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
    if (frame.SetTopLevel) then
      frame:SetTopLevel(true)
    end
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
      frame:HookScript("OnEvent", tl_OnEvent)
    end
    frame:HookScript("OnShow", tl_OnShow)
    frame:HookScript("OnHide", tl_OnHide)
  else
    frame.StopTimeoutCounter = nil
    frame.StartTimeoutCounter = nil
    frame:SetFrameStrata(toplevel:GetFrameStrata())
  end

  frame.Close = dd_Close
  frame:EnableMouse(true)
  frame:HookScript("OnEnter", tl_OnEnter)
  frame:HookScript("OnLeave", tl_OnLeave)

  if (not toplevel and not ispopup) then
    --
    -- DropDown menu. Create the actual portion that is dropped down when
    -- the button is pressed. Simply create the dropdown frame and return
    -- the container.
    --
    frame.dropdown = create_dd_sa(cfg, frame, frame, false)
    frame.dropdown:SetFrameLevel(frame.dropdown:GetFrameLevel() + 4)
    frame.dropdown:ClearAllPoints()
    frame.dropdown:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
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
      if (frame.current) then
        if (frame.current.text) then
          frame.text:SetText(frame.current.text:GetText())
        else
          frame.text:Settext("")
          -- JKJ FIXME possibly display title if first item is a title
        end
      end
    end

    if (cfg.initialvalue ~= nil) then
      frame:SetValue(cfg.initialvalue)
    end

    frame:SetEnabled(cfg.enabled)
    return frame
  end

  -- From this point on no longer deal with the dropdown container. We deal
  -- with the actual menu items or dropdown items.
  frame.offset = borders[frame.border].offset
  frame:SetBackdrop( { bgFile = borders[frame.border].bgFile,
    edgeFile = borders[frame.border].edgeFile,
    tile = true,
    tileSize = borders[frame.border].tileSize,
    edgeSize = borders[frame.border].edgeSize,
    insets = borders[frame.border].insets, })
  frame:SetBackdropColor(0, 0, 0, 1)

  --
  -- Now we create the scrollframe and fit it just inside the borders of
  -- the container frame. If this is a popup menu we allow the user to reserve
  -- space at the top and bottom of the frame for a header and a footer.
  --
  local sframe = frame.sframe
  local cframe = frame.cframe
  local hframe = frame.header
  local fframe = frame.footer
  if (not frame.sframe) then
    sframe = MakeFrame("ScrollFrame", nil, frame)
    frame.sframe = sframe
    sframe.toplevel = frame.toplevel
    sframe:HookScript("OnEnter", tl_OnEnter)
    sframe:HookScript("OnLeave", tl_OnLeave)
  end

  if (not frame.cframe) then
    cframe = MakeFrame("Frame", frame:GetName() .. "Child", sframe)
    frame.cframe = cframe
    cframe.toplevel = frame.toplevel
    cframe:HookScript("OnEnter", tl_OnEnter)
    cframe:HookScript("OnLeave", tl_OnLeave)
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
        hframe:HookScript("OnEnter", tl_OnEnter)
        hframe:HookScript("OnLeave", tl_OnLeave)
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
        fframe:HookScript("OnEnter", tl_OnEnter)
        fframe:HookScript("OnLeave", tl_OnLeave)
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
  end
  sbar:SetOrientation("VERTICAL")
  sbar:ClearAllPoints()
  sbar:SetPoint("TOPLEFT", sframe, "TOPLEFT", -12, 0)
  sbar:SetPoint("BOTTOMRIGHT", sframe, "BOTTOMLEFT", -4, 0)
  sbar:EnableMouse(true)
  sbar:EnableMouseWheel(true)
  sbar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")

  local sbt = sbar:GetThumbTexture()
  sbt:SetTexCoord(0.15625, 0.78128, 0.1875, 0.75)
  sbt:SetWidth(8)
  sbt:SetHeight(16)
  sbar:Hide()

  sbar:HookScript("OnMouseWheel", dd_OnMouseWheel)
  sbar:HookScript("OnValueChanged", dd_OnValueChanged)
  sbar:HookScript("OnEnter", parent_OnEnter)
  sbar:HookScript("OnLeave", parent_OnLeave)

  sframe:HookScript("OnMouseWheel", dd_OnMouseWheel)
  sframe:HookScript("OnScrollRangeChanged", dd_OnScrollRangeChanged)

  if (not toplevel and cfg.canmove and ispopup) then
    --
    -- If we want a moveable frame, we can only do so by click-dragging on the
    -- very top of the frame, along its border. We want to set up a target
    -- zone for registering those clicks which means we need to create yet
    -- another frame.
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
  -- kframes is used to store the names of the various child frames we have
  -- created. Since every line element in a menu is actually a frame, and
  -- we can change the appearance or values of each of those frames at any
  -- time, we do not want to create more frames than we need, so we keep
  -- track of the child frames we create. Note that this table tracks only
  -- the item entry frames, it does not store the frame pointers for
  -- submenu frames (see below for those).
  --
  frame.kframes = {}

  dd_refresh_frame(frame, toplevel, cfg.items, nitems)
  frame:Hide()

  return frame
end

function KUI:CreateDropDown(cfg, parent)
  return create_dd_sa(cfg, parent, nil, false)
end

function KUI:CreatePopupMenu(cfg, parent)
  return create_dd_sa(cfg, parent, nil, true)
end

--
-- Helper function for creating custom frames as popup item widgets.
--
-- Forward declared at the top of this file.
function get_radiowidget(this)
  return this.frame or this
end

--
-- This is a mixture of a popup menu and a scroll list, but wrapped in a dialog
-- frame. It is meant for popping up long lists of names. It uses the more
-- space efficient ScrollList rather than using a popup menu which is unsuited
-- to arbitrarily long lists of names.
--
local function ksl_settext(self, txt)
  self.text:SetText(txt)
end

local function ksl_onclick(this)
  local idx = this:GetID()
  local tlf = this.toplevel

  tlf.slist:SetSelected(idx, false)
  if (tlf.func) then
    tlf.func(tlf.selectionlist, idx, tlf.arg)
  end
  tlf:Hide()
end

local function ksl_onshow(this)
  this.toplevel:StartTimeoutCounter()
end

local function ksl_onhide(this)
  this.toplevel:StopTimeoutCounter()
end

local ksl_onenter = ksl_onhide
local ksl_onleave = ksl_onshow

local function ksl_newitem(objp, num)
  local nm = objp:GetName() .. "Button"
  local tlf = objp.toplevel
  local rf = KUI.NewItemHelper(objp, num, nm, tlf.itemwidth, tlf.itemheight, ksl_settext, ksl_onclick, nil, nil)
  rf.toplevel = tlf
  rf:HookScript("OnEnter", ksl_onenter)
  rf:HookScript("OnLeave", ksl_onleave)
  return rf
end

local function ksl_setitem(objp, idx, slot, btn)
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

local function ksl_selectitem(objp, idx, slot, btn, onoff)
end

local function ksl_highlightitem(objp, idx, slot, btn, onoff)
  return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff, nil, nil)
end

local function ksl_onupdate(this)
  local now = GetTime()
  if ((now - this.timeout_start) > this.timeout) then
    this:SetScript("OnUpdate", nil)
    this.timeout_start = 0
    this:Hide()
  end
end

local function ksl_startcountdown(this)
  this.timeout_start = GetTime()
  this:SetScript("OnUpdate", ksl_onupdate)
end

local function ksl_stopcountdown(this)
  this:SetScript("OnUpdate", nil)
end

local function ksl_updatelist(this, nlist)
  this.selectionlist = nlist
  local x
  if (not nlist) then
    x = 0
  else
   x = #nlist
  end
  local ga = this.headerspace + this.footerspace + (2 * this.borderoffset)
  local mh = ((x + 1) * this.itemheight) + ga
  local h = min(mh, this.uheight)
  local mnw, _, mxw, _ = this:GetResizeBounds()
  this.height = h
  this:SetResizeBounds(mnw, (2 * this.itemheight) + ga + 48, mxw, mh)
  this:SetHeight(h)
  this.slist.itemcount = x
  this.slist:UpdateList()
end

local function ksl_hook(fr)
  fr:HookScript("OnShow", ksl_onshow)
  fr:HookScript("OnHide", ksl_onhide)
  fr:HookScript("OnEnter", ksl_onenter)
  fr:HookScript("OnLeave", ksl_onleave)
end

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
    xbutton = cfg.xbutton,
    level = cfg.level or 24,
  }
  local ret = KUI:CreateDialogFrame(arg, cfg.parent or parent)
  ret.toplevel = ret
  ret.content.toplevel = ret
  local c = ret.content
  local tlf = c
  local brf = c
  local tlp = "TOPLEFT"
  local brp = "BOTTOMRIGHT"

  ksl_hook(ret)
  ksl_hook(ret.content)
  if (ret.title) then
    ret.title.toplevel = ret
    ksl_hook(ret.title)
  end
  if (ret.mframe) then
    ret.mframe.toplevel = ret
    ksl_hook(ret.mframe)
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
    ksl_hook(ret.header)
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
    ksl_hook(ret.footer)
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
    newitem = ksl_newitem,
    setitem = ksl_setitem,
    selectitem = ksl_selectitem,
    highlightitem = ksl_highlightitem,
    __noh__ = ret,
    newobjhook = function(fr,cf,pr,wd,ht)
      fr.toplevel = cf.__noh__
    end,
  }
  ret.StopTimeoutCounter = ksl_stopcountdown
  ret.StartTimeoutCounter = ksl_startcountdown
  ret.cframe.toplevel = ret
  ret.slist = KUI:CreateScrollList(arg, ret.cframe)
  ret.slist.toplevel = ret
  ksl_hook(ret.slist)
  ret.slist.scrollbar.toplevel = ret
  ksl_hook(ret.slist.scrollbar)
  ret.UpdateList = ksl_updatelist
  ret:Hide()

  return ret
end

--
-- How to make the plastic look from Claude
--
-- local white = f:CreateTexture(nil, "ARTWORK")
-- white:SetAllPoints(f)
-- white:SetTexture(KIT)
-- white:SetTexCoord(unpack(skin.button_white))
-- 
-- local chroma = f:CreateTexture(nil, "ARTWORK", nil, 1)   -- one sub-layer above
-- chroma:SetAllPoints(f)
-- chroma:SetTexture(KIT)
-- chroma:SetTexCoord(unpack(skin.button_chroma))
-- chroma:SetBlendMode("ADD")
-- 
