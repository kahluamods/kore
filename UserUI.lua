--[[
   KahLua Kore - the widgets for showing and editing a person.
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

local K = LibStub:GetLibrary("Kore")

if (not K) then
  return
end

local KUI, KM = LibStub:GetLibrary("KoreUI")
assert(KUI, "Kore UserUI requires KoreUI")
assert(tonumber(KM) >= 1, "Kore UserUI requires KoreUI r1 or later")

local L = LibStub("AceLocale-3.0"):GetLocale("Kore")

local KU = K.Users
local MakeFrame = KUI.MakeFrame

local tinsert = table.insert
local tsort = table.sort
local max = math.max
local floor = math.floor
local strfmt = string.format
local strlower = string.lower
local tonumber, tostring = tonumber, tostring
local pairs, ipairs, select = pairs, ipairs, select

local USER_CLASS = KU.USER_CLASS
local USER_PPROF = KU.USER_PPROF
local USER_SPROF = KU.USER_SPROF
local USER_MSROLE = KU.USER_MSROLE
local USER_OSROLE = KU.USER_OSROLE
local USER_KUID = KU.USER_KUID
local USER_ALTOF = KU.USER_ALTOF
local USER_ALTS = KU.USER_ALTS

--
-- How much of a name a box shows, and how much may be typed into one. They are deliberately different numbers: a character
-- name is short and every box is sized for one, while the realm on the end of it can be long, and a box wide enough for the
-- longest Name-Realm there is would be a box mostly full of nothing. So a long name runs past the end of the box as it is
-- typed and is cut off in a dropdown that shows it, and the menu the name was picked from shows it whole.
--
KU.NAME_CHARS = 15
KU.NAME_MAXLEN = 30

--
-- THE WIDGETS A PERSON IS SHOWN AND EDITED WITH
--
-- A class, a role, a profession and whose alt somebody is mean the same thing to every KahLua mod, so the pickers
-- for them are here rather than assembled again in each one, where they would come out a different width and a different
-- order. Kore's own user editor and a mod's own pages both reach for these.
--
--
-- The two pickers for what a user is. Both are the platform's: a role and a class mean the same thing whatever distribution
-- policy is running, so a policy building a panel of its own reaches for these rather than assembling the same list again
-- and getting a different width and a different order.
--
-- W and LW are the widths of the dropdown and of its label, and both are optional. The dropdown measures itself against the
-- longest thing it can ever show, which is the right width in every locale rather than in the one the number was picked in.
-- The label fits its own word, unless a caller stacking a column of widgets has a wider one for their left edges to line up
-- against -- see KUI:WidestString.
--
local function item_width(items)
  local strs = {}

  for k, v in ipairs(items) do
    tinsert(strs, v.text)
  end

  return KUI:DropDownWidth(strs)
end

--
-- The role an item or a list is restricted to.
--
function KU:CreateRoleDropdown(name, x, y, parent, w, lw)
  local items = {
    { text = K.RoleName(K.ROLE_UNSET), value = K.ROLE_UNSET },
    { text = K.RoleName(K.ROLE_HEALER), value = K.ROLE_HEALER },
    { text = K.RoleName(K.ROLE_MELEE), value = K.ROLE_MELEE },
    { text = K.RoleName(K.ROLE_RANGED), value = K.ROLE_RANGED },
    { text = K.RoleName(K.ROLE_CASTER), value = K.ROLE_CASTER },
    { text = K.RoleName(K.ROLE_TANK), value = K.ROLE_TANK },
  }

  local arg = {
    name = name, mode = "SINGLE", itemheight = 16, x = x, y = y,
    dwidth = w or item_width(items), items = items,
    label = { text = L["User role"], pos = "LEFT", width = lw },
    tooltip = { title = "$$", text = L["TIP071"] },
  }

  return KUI:CreateDropDown(arg, parent)
end

--
-- A user's main spec, or with OFF their off spec, as a dropdown offering -Not set- and then the roles one class can play,
-- in the order of K.ROLES. A spec is what a player calls the role they raid in, and what is stored is the role, so which
-- class's roles the menu offers is set with dd:SetClass(class), and until a class is set it offers -Not set- alone. The
-- value is a K.ROLE_ number, K.ROLE_UNSET for -Not set-. The dropdown is as wide as the longest role, so it does not change
-- size with the class.
--
-- LPOS is where the label goes, "LEFT" unless it is given, and "NONE" for a dropdown drawn without one, which is the second
-- of a pair standing under one label between them. LTEXT names the dropdown where the caller wants it named something else,
-- as that pair's first one is named for both. The tooltip is titled for the field itself either way, so the one with no label
-- of its own still says which it is.
--
local function spec_items(class)
  local items = { { text = K.NOTSET_STR, value = K.ROLE_UNSET } }

  for _, role in ipairs(class and K.ClassRoles[class] or {}) do
    tinsert(items, { text = K.RoleName(role), value = role })
  end

  return items
end

local function spec_names()
  local names = { K.NOTSET_STR }

  for _, role in ipairs(K.ROLES) do
    tinsert(names, K.RoleName(role))
  end

  return names
end

function KU:CreateSpecDropdown(name, x, y, parent, off, w, lw, lpos, ltext)
  local title = off and L["Off spec"] or L["Main spec"]

  local arg = {
    name = name, mode = "SINGLE", itemheight = 16, x = x, y = y,
    dwidth = w or KUI:DropDownWidth(spec_names()), items = spec_items(nil),
    label = (lpos ~= "NONE") and { text = ltext or title, pos = lpos or "LEFT", width = lw } or nil,
    tooltip = { title = title, text = off and strfmt(L["TIP109"], K.NOTSET_STR) or L["TIP108"] },
  }

  local dd = KUI:CreateDropDown(arg, parent)

  dd.SetClass = function(this, class)
    this:UpdateItems(spec_items(class))
  end

  return dd
end

function KU:CreateClassDropdown(name, x, y, parent, w, lw, lpos)
  local items = {}

  --
  -- K.IndexClass is keyed by class id, so it comes out of pairs() in a different order every session. Sorted by name,
  -- because a list of classes the user is expected to find something in has to be in the same place twice running.
  --
  for k, v in pairs(K.IndexClass) do
    if (v.c and not v.ign) then
      tinsert(items, { text = v.c, value = k, color = K.ClassColorsRGBPerc[k] })
    end
  end

  tsort(items, function(a, b)
    return strlower(a.text) < strlower(b.text)
  end)

  local arg = {
    name = name, mode = "SINGLE", itemheight = 16, x = x, y = y,
    dwidth = w or item_width(items), items = items,
    label = (lpos ~= "NONE") and { text = L["User class"], pos = lpos or "LEFT", width = lw } or nil,
    title = { text = L["Class"] },
    tooltip = { title = L["User class"], text = L["TIP073"] },
  }

  return KUI:CreateDropDown(arg, parent)
end

--
-- Both profession slots offer the same list, Not set and then every profession this client has of a kind Konfer records, in
-- name order, so both the user editor and the create user dialog build them here. A caller lining several dropdowns up
-- measures its column across this list too.
--
-- Kore knows every profession there is and PROF_KINDS is where Konfer says which of them it keeps about a user. Both kinds
-- are wanted today, a miner being as much a thing worth knowing about a raider as a blacksmith, so the filter weeds nothing
-- out yet; it is here so that a kind Kore gains is a deliberate decision on this side rather than a new row that simply appears in the dropdown.
--
local PROF_KINDS = { [K.PROF_CRAFTING] = true, [K.PROF_GATHERING] = true }

local function profession_items()
  local items = {}

  for prof, info in pairs(K.IndexProf) do
    if (PROF_KINDS[info.kind]) then
      tinsert(items, { text = info.c, value = prof })
    end
  end

  tsort(items, function(a, b)
    return strlower(a.text) < strlower(b.text)
  end)

  tinsert(items, 1, { text = K.NOTSET_STR, value = K.PROF_UNSET })

  return items
end

--
-- LPOS is where the label goes, as it is for the spec dropdown above, "NONE" included. LTEXT names the dropdown where the
-- caller wants it named something else: the user editor and the create user dialog stand the two under one label naming both,
-- being two fields among many about somebody else; the specs dialog asks the player about themselves and says Profession 1 and 2.
--
function KU:CreateProfessionDropdown(name, x, y, parent, second, w, lw, lpos, ltext)
  local items = profession_items()
  local title = second and L["Second profession"] or L["First profession"]

  local arg = {
    name = name, mode = "SINGLE", itemheight = 16, x = x, y = y,
    dwidth = w or item_width(items), items = items,
    label = (lpos ~= "NONE") and { text = ltext or title, pos = lpos or "LEFT", width = lw } or nil,
    tooltip = { title = title, text = second and strfmt(L["TIP105"], K.NOTSET_STR) or L["TIP104"] },
  }

  return KUI:CreateDropDown(arg, parent)
end

--
-- Every profession name, so a caller laying out a profession dropdown beside other things can measure a column across them.
--
function KU:ProfessionNames()
  local names = {}

  for _, item in ipairs(profession_items()) do
    tinsert(names, item.text)
  end

  return names
end

--
-- How wide a dropdown has to be to hold the widest of them: every profession recorded about a user, every role, every
-- class. Each is one answer for the whole client -- the words are the game's and the locale's and neither
-- changes while it runs -- so each is measured the first time it is asked for and kept. Every window laying one of these
-- dropdowns out beside something else asks here, rather than assembling the list again and arriving at a width of its own,
-- which is how two windows showing the same dropdown end up drawing it two sizes.
--
local widest = {}

function KU:ProfessionWidth()
  widest.prof = widest.prof or item_width(profession_items())

  return widest.prof
end

function KU:SpecWidth()
  widest.spec = widest.spec or KUI:DropDownWidth(spec_names())

  return widest.spec
end

function KU:ClassWidth()
  if (not widest.class) then
    local names = {}

    for k, v in pairs(K.IndexClass) do
      if (v.c and not v.ign) then
        tinsert(names, v.c)
      end
    end

    widest.class = KUI:DropDownWidth(names)
  end

  return widest.class
end

--
-- Nobody has a profession twice, so neither slot offers what the other holds. Each rebuilds its menu as it opens, the way the
-- config page's Assign to dropdowns keep one enchanter out of two slots. UpdateItems keeps the slot's own value.
--
local function exclude_other_profession(dd, other)
  dd:Catch("OnClick", function(this, evt, _, shown)
    if (not shown) then
      return
    end

    local taken = other:GetValue()
    local items = {}

    for k, v in ipairs(profession_items()) do
      if (v.value == K.PROF_UNSET or v.value ~= taken) then
        tinsert(items, v)
      end
    end

    this:UpdateItems(items)
  end)
end

--
-- Keep the two profession dropdowns FIRST and SECOND from ever offering what the other holds.
--
function KU:PairProfessionDropdowns(first, second)
  exclude_other_profession(first, second)
  exclude_other_profession(second, first)
end

--
-- Whose alt a user is, as a dropdown reading "User is an alt of" and then -Nobody- or a main, in name order and in class
-- colour. The value is the main's KUID, or "" for -Nobody-, which every setter takes for no main at all. -Nobody- is set off
-- by its dashes so that it cannot be mistaken for a character who happens to be called Nobody.
--
-- There is one alt link and every window shows it, so who is offered is the same question wherever it is asked, and that is
-- everybody we know who is not already somebody's alt. A main in one mod's configuration is a main in all of them, and one
-- nobody's configuration holds is still offered, the link being a fact about the human rather than about a raid.
--
-- MAINS is function (exclude) -> array of KUIDs, EXCLUDE being the KUID of the user the dropdown is set for, who is never
-- offered as their own main. KU.Mains is that function, and a mod with a narrower answer passes its own. The users change
-- while a window is open, so the menu is built again every time it opens and by dd:Refill(exclude), which is called before a
-- value is set, a value only being settable when it is in the menu.
--
function KU.Mains(exclude)
  local kuids = {}

  for name, rec in pairs(KU.users or {}) do
    if (not rec[USER_ALTOF] and rec[USER_KUID] ~= exclude) then
      tinsert(kuids, rec[USER_KUID])
    end
  end

  return kuids
end

local function main_items(kuids)
  local items = { { text = K.NOBODY_STR, value = "" } }
  local sorted = {}

  for k, v in ipairs(kuids) do
    tinsert(sorted, { kuid = v, shown = strlower(K.DisplayName(KU.kuids[v] or "")) })
  end

  tsort(sorted, function(a, b)
    return a.shown < b.shown
  end)

  for k, v in ipairs(sorted) do
    tinsert(items, { text = KU:String(v.kuid), value = v.kuid })
  end

  return items
end

function KU:CreateMainDropdown(name, x, y, parent, w, lw, mains)
  local arg = {
    name = name, mode = "SINGLE", itemheight = 16, x = x, y = y, dwidth = w, items = main_items({}),
    label = { text = L["User is an alt of"], pos = "LEFT", width = lw },
    tooltip = { title = "$$", text = strfmt(L["TIP_USEREDIT_MAIN"], K.NOBODY_STR) },
  }

  local dd = KUI:CreateDropDown(arg, parent)

  dd.Refill = function(this, exclude)
    this.exclude = exclude
    this:UpdateItems(main_items(mains(exclude)))
  end

  dd:Catch("OnClick", function(this, evt, _, shown)
    if (shown) then
      this:Refill(this.exclude)
    end
  end)

  return dd
end

--
-- Add what is known of KUID's character to TOOLTIP, a line to each: main spec, off spec and their professions, the label on
-- the left and the value on the right. A fact that is not known has no line. True when any went in.
--
function KU:AddUserFacts(tooltip, kuid)
  local rec = self:Record(kuid)

  if (not rec) then
    return false
  end

  local added = false
  local lr, lg, lb = NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b
  local vr, vg, vb = HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b

  local function line(label, entry)
    if (entry and entry.c) then
      tooltip:AddDoubleLine(label, entry.c, lr, lg, lb, vr, vg, vb)
      added = true
    end
  end

  -- A role in words, in the shape line takes, or nothing for one not set.
  local function role(r)
    return (r and r ~= K.ROLE_UNSET) and { c = K.RoleName(r) } or nil
  end

  line(L["Main spec"], role(rec[USER_MSROLE]))
  line(L["Off spec"], role(rec[USER_OSROLE]))
  line(L["Profession"], rec[USER_PPROF] and K.IndexProf[rec[USER_PPROF]])
  line(L["Profession"], rec[USER_SPROF] and K.IndexProf[rec[USER_SPROF]])

  return added
end

--
-- What is true of a character, as the part of a user editor that shows and edits it: the main spec and off spec and both
-- professions. The class is not among them. A character is created as one and stays it, so it is asked for once, by the
-- create user dialog, and after that the only thing that ever writes it is a character info check, the character answering
-- about itself. An editor showing it as a dropdown would be offering a choice that nothing is allowed to take.
--
-- The mod's user editor, every policy's Users page and the create user dialog both of them put up
-- build it here and nowhere else, so none of them can drift apart. How a window says these are shared is the window's: the
-- mod's editor names its whole panel for them, and a policy's Users page, where they follow the config's own view of the
-- user, sets a separator over them.
--
-- The alt dropdown at the foot of it is read here like every other row. Whose alt somebody is is one fact, the same in every
-- configuration of every mod, so both callers show the same answer. Who they may offer as a main differs, a config only
-- being able to point at people it holds, which is what MAINS is for. What they do with an edit differs too, the mod's
-- editor writing it straight and a policy's page sending it to the config's other admins as well, so the edit is reported
-- rather than saved here.
--
-- CFG holds:
--   prefix    put in front of every frame name, each window building a block of its own
--   x, y      where the block starts in PARENT
--   lw        the label width, when the caller has labels of its own to line up with these and has measured them together
--             with shared_labels(). Measured from the block's own labels otherwise.
--   mains     who the alt dropdown offers, as CreateMainDropdown takes it. KU.Mains, every main there is, for a caller
--             with no configuration to narrow it to.
--   changed   function (field, value) called when the user edits one of them, FIELD being "msspec", "osspec", "pprof",
--             "sprof" or "main". Values are the two roles, as K.ROLE_ numbers, the two profession numbers and the main's
--             KUID, "" for -Nobody-.
--
-- The block hands back its widgets; LW and DW, the label width and the width of a control beside one, so that a caller can
-- line its own widgets up with them; WIDTH, what its widest row comes out at, for a caller sizing a panel round it; and
-- YPOS, where the next widget goes below it. And:
--
--   block:SetUser(kuid)        show user KUID, or nobody for nil. Edits are reported while a user is shown. Somebody who
--                              has alts of their own is a main and cannot be made anybody's alt, so their dropdown is shut.
--   block:SetNew()             show a user not made yet, every field empty, and report edits to it.
--   block:SetValues(info)      show edits not yet saved over the user shown, INFO holding the fields as CFG.changed names
--                              them. Nothing is reported, the edits being ones already reported.
--   block:SetClass(class)      which class's roles the two spec dropdowns offer. A shown user's is their own and is set for
--                              them; the create dialog, where the class is being picked, sets it as that changes, and a
--                              role the new class cannot play is taken away and reported as an edit.
--   block:SetEnabled(onoff)    whether it can be edited. A user with alts of their own is a main and cannot be made
--                              anybody's alt, so for them the alt dropdown stays shut.
--
local function shared_labels()
  return { L["User is an alt of"] }
end

function KU:CreateSharedUserInfo(cfg, parent)
  local block = {}
  local x = cfg.x or 0
  local ypos = cfg.y or 0
  local prefix = cfg.prefix or ""

  --
  -- The two pairs of dropdowns are each as wide as the longest role or profession asks for. The alt dropdown holds
  -- names, which have no longest, so it is as wide as a name usually is and no wider: its menu is sized by its own items, so
  -- a long name shows whole where it is picked and is cut off only in the box afterwards. WIDTH is whichever of the two rows
  -- comes out the wider, for a caller sizing a panel round the block.
  --
  local sw = max(KU:SpecWidth(), KU:ProfessionWidth())

  block.lw = cfg.lw or KUI:WidestString(shared_labels())
  block.dw = KUI:DropDownCharsWidth(KU.NAME_CHARS)
  block.width = max(2 * sw + KUI.WIDGET_GAP, block.lw + KUI.INTERNAL_GAP + block.dw)

  local lw, dw = block.lw, block.dw

  local function edited(field, value)
    if (block.editing) then
      cfg.changed(field, value)
    end
  end

  local function row(dd)
    ypos = ypos - dd:GetHeight() - KUI.WIDGET_GAP - KUI.DROPDOWN_ADD_GAP
  end

  --
  -- Two columns, the specs down the first under one label naming both, and the professions down the second under theirs, all
  -- four at the one width so that the two columns are a grid. The label is the first of each pair's, which carries its height,
  -- and the second of each stands under the first.
  --
  local x2 = x + sw + KUI.WIDGET_GAP
  local top = ypos

  block.msspec = self:CreateSpecDropdown(prefix .. "KoreSharedMainSpecDD", x, top, parent, false, sw, nil, "TOP",
    L["Main / off spec"])
  block.msspec:Catch("OnValueChanged", function(this, evt, newv)
    edited("msspec", tonumber(newv) or K.ROLE_UNSET)
  end)

  block.pprof = self:CreateProfessionDropdown(prefix .. "KoreSharedFirstProfDD", x2, top, parent, false, sw, nil, "TOP",
    L["Professions"])
  block.pprof:Catch("OnValueChanged", function(this, evt, newv)
    edited("pprof", tonumber(newv) or K.PROF_UNSET)
  end)
  row(block.msspec)

  block.osspec = self:CreateSpecDropdown(prefix .. "KoreSharedOffSpecDD", x, ypos, parent, true, sw, nil, "NONE")
  block.osspec:Catch("OnValueChanged", function(this, evt, newv)
    edited("osspec", tonumber(newv) or K.ROLE_UNSET)
  end)

  block.sprof = self:CreateProfessionDropdown(prefix .. "KoreSharedSecondProfDD", x2, ypos, parent, true, sw, nil, "NONE")
  block.sprof:Catch("OnValueChanged", function(this, evt, newv)
    edited("sprof", tonumber(newv) or K.PROF_UNSET)
  end)
  self:PairProfessionDropdowns(block.pprof, block.sprof)
  row(block.osspec)

  --
  -- The two pairs above are one block, each labelled over itself, and the alt link is a row of a different shape with its
  -- words beside it. A gap of its own before it says so, rather than leaving it looking like a third thing in the grid.
  --
  ypos = ypos - KUI.WIDGET_GAP

  block.main = self:CreateMainDropdown(prefix .. "KoreSharedMainDD", x, ypos, parent, dw, lw, cfg.mains or KU.Mains)
  block.main:Catch("OnValueChanged", function(this, evt, newv)
    edited("main", newv or "")
  end)
  row(block.main)

  block.ypos = ypos
  block.enabled = true

  local function sync(this)
    this.msspec:SetEnabled(this.enabled)
    this.osspec:SetEnabled(this.enabled)
    this.pprof:SetEnabled(this.enabled)
    this.sprof:SetEnabled(this.enabled)
    this.main:SetEnabled(this.enabled and not this.hasalts)
  end

  --
  -- Values are set without throwing, and edits are only reported again once they all are, showing what is stored not being an edit.
  --
  local function show(this, rec)
    this.editing = false
    this.hasalts = (rec and rec[USER_ALTS]) and true or false
    this.msspec:SetClass(rec and rec[USER_CLASS])
    this.msspec:SetValue(rec and rec[USER_MSROLE] or K.ROLE_UNSET, true)
    this.osspec:SetClass(rec and rec[USER_CLASS])
    this.osspec:SetValue(rec and rec[USER_OSROLE] or K.ROLE_UNSET, true)
    this.pprof:SetValue(rec and rec[USER_PPROF] or K.PROF_UNSET, true)
    this.sprof:SetValue(rec and rec[USER_SPROF] or K.PROF_UNSET, true)
    this.main:Refill(rec and rec[USER_KUID])
    this.main:SetValue(rec and rec[USER_ALTOF] or "", true)
  end

  block.SetUser = function(this, kuid)
    local rec = KU:Record(kuid)

    show(this, rec)
    this.editing = rec and true or false
    sync(this)
  end

  block.SetNew = function(this)
    show(this, nil)
    this.editing = true
    sync(this)
  end

  block.SetValues = function(this, info)
    local editing = this.editing

    this.editing = false
    this.msspec:SetValue(info.msspec or K.ROLE_UNSET, true)
    this.osspec:SetValue(info.osspec or K.ROLE_UNSET, true)
    this.pprof:SetValue(info.pprof or K.PROF_UNSET, true)
    this.sprof:SetValue(info.sprof or K.PROF_UNSET, true)
    this.main:SetValue(info.main or "", true)
    this.editing = editing
  end

  --
  -- The roles offered are the class's. One the new class cannot play is taken away, and that is an edit like any other. A
  -- class that plays one role alone has it as the main spec from the start, which is an edit too.
  --
  block.SetClass = function(this, class)
    local roles = (class and K.ClassRoles[class]) or {}

    for _, dd in ipairs({ this.msspec, this.osspec }) do
      local role = tonumber(dd:GetValue())
      local plays = false

      for _, r in ipairs(roles) do
        if (r == role) then
          plays = true
        end
      end

      dd:SetClass(class)

      if (not plays) then
        dd:SetValue(K.ROLE_UNSET)
      end
    end

    if (#roles == 1 and (tonumber(this.msspec:GetValue()) or K.ROLE_UNSET) == K.ROLE_UNSET) then
      this.msspec:SetValue(roles[1])
    end
  end

  block.SetEnabled = function(this, onoff)
    this.enabled = onoff and true or false
    sync(this)
  end

  return block
end

--
-- THE PLAYER'S OWN NOTES ON SOMEBODY
--
-- How good the player thinks somebody is at each of RATE_ROWS, and whatever else they want to remember about them. None of it
-- is fact and none of it ever leaves the machine (KU:Rating, KU:Note). Kore's user editor shows it, and so may a mod's
-- own page about people, both through KU:CreateUserNotes, so that the two cannot differ.
--

--
-- What a rating grid rates, in the order it lists them. KEY names each one's label and its dropdown's frame.
--
KU.RATE_ROWS = {
  { which = KU.RATE_HEALER,    key = "HEALER" },
  { which = KU.RATE_TANK,      key = "TANK" },
  { which = KU.RATE_MELEE,     key = "MELEE" },
  { which = KU.RATE_RANGED,    key = "RANGED" },
  { which = KU.RATE_ETIQUETTE, key = "ETIQUETTE" },
  { which = KU.RATE_KNOWLEDGE, key = "KNOWLEDGE" },
  { which = KU.RATE_HELPFUL,   key = "HELPFUL" },
}

local RATE_ROWS = KU.RATE_ROWS

--
-- What a rating can be, worst first, each in the colour it is shown in at a glance: red for the worst through orange and
-- yellow, then blue for good, so it cannot be mistaken for the green of the best. -Not rated- is 0 in the menu and no rating
-- at all when stored, and is grey.
--
local RATINGS = {
  { value = KU.RATING_TERRIBLE,  key = "TERRIBLE",  colour = { r = 1.0,  g = 0.13, b = 0.13 } },
  { value = KU.RATING_BIND,      key = "BIND",      colour = { r = 1.0,  g = 0.45, b = 0.1 } },
  { value = KU.RATING_ORDINARY,  key = "ORDINARY",  colour = { r = 1.0,  g = 0.7,  b = 0.1 } },
  { value = KU.RATING_ABOVE,     key = "ABOVE",     colour = { r = 1.0,  g = 1.0,  b = 0.2 } },
  { value = KU.RATING_GOOD,      key = "GOOD",      colour = { r = 0.3,  g = 0.75, b = 1.0 } },
  { value = KU.RATING_EXCELLENT, key = "EXCELLENT", colour = { r = 0.13, g = 1.0,  b = 0.13 } },
}

local COLOR_NOTRATED = { r = 0.5, g = 0.5, b = 0.5 }

--
-- A rating's words go under its dropdown in RATING_FONT, pulled RATING_LIFT pixels up from the usual internal gap below it,
-- the font's line having room above its letters that would otherwise sit between them and the pill.
--
local RATING_FONT = "GameFontNormalTiny"
local RATING_LIFT = 3

--
-- The least the note is ever drawn at: a couple of lines to write on under the ratings.
--
local NOTE_MINHEIGHT = 40

--
-- As much as anybody needs to say about somebody. A note is a reminder rather than a diary, and it is kept for every user
-- there is, so it is bounded.
--
local NOTE_MAXLEN = 512

--
-- What a panel holding the notes is called, for a mod whose page puts them in a panel of its own.
--
KU.NOTES_TITLE = L["USEREDIT_NOTES"]

--
-- The menu a rating dropdown offers, EMPTY being the words for no rating at all.
--
local function rating_items(empty)
  local items = { { text = empty, value = 0, color = COLOR_NOTRATED } }

  for _, v in ipairs(RATINGS) do
    tinsert(items, { text = L["USEREDIT_RATING_" .. v.key], value = v.value, color = v.colour })
  end

  return items
end

--
-- The words and colour for RATING, a RATING_ constant, or EMPTY in grey for nil.
--
local function rating_shown(rating, empty)
  for _, v in ipairs(RATINGS) do
    if (v.value == rating) then
      return L["USEREDIT_RATING_" .. v.key], v.colour
    end
  end

  return empty, COLOR_NOTRATED
end

--
-- Add how this player rates KUID to TOOLTIP, a line to each thing rated: what it is on the left and the rating on the right,
-- in the rating's own colour, as the grid shows it. A thing not rated has no line. With SPACED a blank line goes before the
-- first, for a tooltip ending in something else. True when any went in.
--
function KU:AddUserRatings(tooltip, kuid, spaced)
  local added = false
  local lr, lg, lb = NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b

  for _, r in ipairs(RATE_ROWS) do
    local words, c = rating_shown(self:Rating(kuid, r.which))

    if (words) then
      if (spaced and not added) then
        tooltip:AddLine(" ")
      end

      tooltip:AddDoubleLine(L["USEREDIT_RATE_" .. r.key], words, lr, lg, lb, c.r, c.g, c.b)
      added = true
    end
  end

  return added
end

--
-- How wide a rating grid has to be, two dropdowns and the gap between them: each wide enough for the words of whatever it
-- rates and for every rating's words under it.
--
function KU:RatingGridWidth()
  local labels = {}
  local texts = {}

  for _, r in ipairs(RATE_ROWS) do
    tinsert(labels, L["USEREDIT_RATE_" .. r.key])
  end

  for _, v in ipairs(rating_items(K.NOTRATED_STR)) do
    tinsert(texts, v.text)
  end

  tinsert(texts, K.NOTSET_STR)

  local need = max(KUI:DropDownWidth(labels), (KUI:WidestString(texts, RATING_FONT)))

  return need * 2 + KUI.WIDGET_GAP
end

--
-- A grid of every RATE_ROWS rating, the one drawing the player's notes and the user editor's filter dialog alike, so that
-- the two cannot differ. Each rating is a compact dropdown, the way a config's announcements are: the pill always reads what is
-- being rated, and the rating it holds is written under it in RATING_FONT, in its colour, so it can be seen at a glance. They
-- go two to a row, the usual gap between them, filling WIDTH across, and a row left with one has it in the middle.
--
-- CFG holds:
--   prefix   put in front of every frame name
--   x, y     where the grid starts in PARENT
--   width    how wide it is, at least KU:RatingGridWidth()
--   empty    the words for no rating, which the menus offer first and the grid shows under a dropdown holding nothing
--   tooltip  the words of each dropdown's tooltip, with %s for EMPTY
--   changed  function (which, rating) called when the user picks one, RATING being nil for EMPTY
--
-- The grid hands back HEIGHT, how tall it is, and:
--   grid:Set(which, rating)  show RATING at WHICH, in its dropdown without throwing and under it, nil for none
--   grid:Get(which)          the rating held at WHICH, or nil
--   grid:Blank()             hold nothing anywhere and show nothing under any of them, for nobody to be rated
--   grid:SetEnabled(onoff)   whether the dropdowns can be used
--
function KU:CreateRatingGrid(cfg, parent)
  local grid = { dds = {}, labels = {}, held = {} }
  local width = cfg.width
  local dw = floor((width - KUI.WIDGET_GAP) / 2)
  local vh = select(2, KUI:MeasureStrWidth("Wy", RATING_FONT))
  local ypos = cfg.y or 0
  local nrates = #RATE_ROWS

  grid.Set = function(this, which, rating)
    local text, colour = rating_shown(rating, cfg.empty)
    local label = this.labels[which]

    this.held[which] = rating
    this.dds[which]:SetValue(rating or 0, true)
    label:SetText(text)
    label:SetTextColor(colour.r, colour.g, colour.b, 1)
  end

  grid.Get = function(this, which)
    return this.held[which]
  end

  grid.Blank = function(this)
    for which, dd in pairs(this.dds) do
      this.held[which] = nil
      dd:SetValue(0, true)
      this.labels[which]:SetText("")
    end
  end

  grid.SetEnabled = function(this, onoff)
    for _, dd in pairs(this.dds) do
      dd:SetEnabled(onoff)
    end
  end

  for i, r in ipairs(RATE_ROWS) do
    local which = r.which
    local col = (i - 1) % 2
    local text = L["USEREDIT_RATE_" .. r.key]
    local x = (cfg.x or 0) + col * (dw + KUI.WIDGET_GAP)

    if (col == 0 and i == nrates) then
      x = (cfg.x or 0) + floor((width - dw) / 2)
    end

    local dd = KUI:CreateDropDown({
      name = cfg.prefix .. "Rating" .. r.key, mode = "COMPACT", itemheight = 16, x = x, y = ypos, dwidth = dw,
      items = rating_items(cfg.empty), title = { text = text },
      tooltip = { title = text, text = strfmt(cfg.tooltip, cfg.empty) },
    }, parent)
    dd:SetValue(0, true)
    dd:Catch("OnValueChanged", function(this, evt, newv, user)
      if (user) then
        newv = tonumber(newv) or 0
        grid:Set(which, (newv ~= 0) and newv or nil)
        cfg.changed(which, grid:Get(which))
      end
    end)
    grid.dds[which] = dd

    local vy = ypos - dd:GetHeight() - KUI.INTERNAL_GAP + RATING_LIFT

    grid.labels[which] = KUI:CreateStringLabel({
      x = x, y = vy, width = dw, height = vh, autosize = false, justifyh = "CENTER", font = RATING_FONT, text = "",
    }, parent)

    grid.height = (cfg.y or 0) - vy + vh

    if (col == 1) then
      ypos = vy - vh - KUI.WIDGET_GAP
    end
  end

  return grid
end

--
-- The whole of the player's notes on somebody, built into PARENT: the ratings, and under them the note. Given a number of
-- lines the note is that tall, for a page of fixed size, and otherwise it takes everything the ratings leave down to PARENT's
-- foot, for a window that is dragged taller and shorter. The two stand together in a frame of their own, as wide as the
-- ratings, and that frame is centred across PARENT. PARENT is the content of a panel whose title says what all of it is
-- (KU.NOTES_TITLE), so the ratings need no heading of their own and the note no label, its well being the only thing there
-- that is not a rating. Both are stored the moment they are chosen or typed, having nothing to do with any Update button,
-- which saves facts, and Escape only leaves the note, what was typed being stored already.
--
-- CFG holds:
--   prefix   put in front of every frame name
--   y        where the ratings start in PARENT
--   width    how wide the ratings and the note are, at least KU:RatingGridWidth(), which is what leaving it out gives
--   lines    how many lines tall the note is, or nil for it to run down to PARENT's foot
--
-- It hands back FRAME, the one holding both, GRID and NOTE, its two parts, WIDTH, and MINHEIGHT, the least it is ever drawn
-- at from Y down, for a caller sizing whatever holds it: the ratings and the note's lines, or the ratings and a couple of
-- lines to write on under them where the note takes what there is. And:
--
--   notes:SetUser(kuid)      show the notes on user KUID, and store what is chosen or typed as theirs, or nobody's for nil
--   notes:SetEnabled(onoff)  whether they can be edited
--
function KU:CreateUserNotes(cfg, parent)
  local notes = {}
  local prefix = cfg.prefix or ""

  notes.width = max(cfg.width or 0, self:RatingGridWidth())

  local frame = MakeFrame("Frame", nil, parent)

  frame:ClearAllPoints()
  frame:SetPoint("TOP", parent, "TOP", 0, cfg.y or 0)
  frame:SetWidth(notes.width)
  notes.frame = frame

  notes.grid = self:CreateRatingGrid({
    prefix = prefix, x = 0, y = 0, width = notes.width, empty = K.NOTRATED_STR, tooltip = L["TIP_USEREDIT_RATING"],
    changed = function(which, rating)
      if (notes.who) then
        KU:SetRating(notes.who, which, rating)
      end
    end,
  }, frame)

  local notetop = 0 - notes.grid.height - KUI.WIDGET_GAP

  notes.note = KUI:CreateTextArea({ name = prefix .. "Note", font = "GameFontHighlightSmall", len = NOTE_MAXLEN,
    lines = cfg.lines, tooltip = { title = L["USEREDIT_NOTE"], text = L["TIP_USEREDIT_NOTE"] },
  }, frame)
  notes.note:ClearAllPoints()
  notes.note:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, notetop)
  notes.note:Catch("OnValueChanged", function(this, evt, newv, user)
    if (user and notes.who) then
      KU:SetNote(notes.who, newv)
    end
  end)

  if (cfg.lines) then
    notes.note:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, notetop)
    notes.minheight = 0 - notetop + notes.note:GetHeight()
    frame:SetHeight(notes.minheight)
  else
    notes.note:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    notes.minheight = 0 - notetop + NOTE_MINHEIGHT
  end

  notes.SetUser = function(this, kuid)
    local rec = KU:Record(kuid)

    this.who = rec and kuid or nil

    if (rec) then
      for _, r in ipairs(RATE_ROWS) do
        this.grid:Set(r.which, KU:Rating(kuid, r.which))
      end
    else
      this.grid:Blank()
    end

    -- Set rather than typed, so nothing is written back where it came from.
    this.note:SetText(rec and KU:Note(kuid) or "")
  end

  notes.SetEnabled = function(this, onoff)
    this.grid:SetEnabled(onoff)
    this.note:SetEnabled(onoff)
  end

  notes:SetUser(nil)
  notes:SetEnabled(false)

  return notes
end

--
-- The player's notes on one user in a dialog of their own, the very ratings and note Kore's user editor shows
-- (KU:CreateUserNotes) under the user's name, for a page that lists people and has no room for the notes on it. Everything in
-- it is stored as it is chosen or typed, so its one button only closes it, as Escape does. dlg:Open(kuid) shows it for KUID.
-- However it closes it throws OnHide, which is where an opener that stood aside for it comes back. It is as wide as the
-- notes or as its title, whichever is wider, so the plate never runs past the dialog's corners.
--
-- CFG holds:
--   name   the dialog's frame name, put in front of the names of the frames in it too
--   owner  the word in the plate's brackets, "<Konfer> Private notes / ratings", the notes belonging to no mod's window in
--          particular but shown from one, and the dialog being too narrow for anything more; left out it is the suite's
--
local NOTESDLG_LINES = 5

function KU:CreateNotesDialog(cfg)
  local width = self:RatingGridWidth()
  local dlg = KUI:CreateDialogFrame({
    x = "CENTER", y = "MIDDLE", name = cfg.name, title = K.WindowTitle(cfg.owner, KU.NOTES_TITLE),
    border = true, width = width, height = 300, canmove = true, canresize = false, escclose = true, blackbg = true,
    okbutton = true, buttons = "CENTER",
  })
  local inside = dlg.content
  local _, lh = KUI:MeasureStrWidth("Wy", "GameFontNormal")

  dlg.who = inside:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  dlg.who:SetPoint("TOP", inside, "TOP", 0, 0)
  dlg.who:SetWidth(width)
  dlg.who:SetJustifyH("CENTER")

  dlg.notes = self:CreateUserNotes({ prefix = cfg.name, y = 0 - lh - KUI.WIDGET_GAP, width = width, lines = NOTESDLG_LINES },
    inside)

  local r = dlg.rings

  dlg:SetWidth(max(dlg.notes.width, dlg.title:GetWidth()) + r.left + r.right)
  dlg:SetHeight(lh + KUI.WIDGET_GAP + dlg.notes.minheight + r.top + r.bottom)

  dlg.Open = function(this, kuid)
    this.who:SetText(KU:String(kuid))
    this.notes:SetUser(kuid)
    this.notes:SetEnabled(KU:Record(kuid) ~= nil)
    this:Show()
  end

  return dlg
end

--
-- The dialog that makes a new user, which the mod's user editor and every policy's Users page both put up. The standard
-- fields are the user's name, their class and then everything CreateSharedUserInfo shows, all of them what is true of the
-- character, so the dialog is the same wherever it is opened. Whoever opens it can add fields of their own under those.
--
-- The class is here and in no editor, this being the one moment it is ever asked for: a character is created as one and stays
-- it. The specs are the class's, so the dialog tells the block which class has been picked as that changes.
--
-- CFG holds:
--   name    the dialog's frame name
--   err     function (fmt, ...) that reports why OK was refused, in the opener's own voice
--   extra   function (dlg, ypos) -> ypos, optional. Called once, after the standard fields are built, to add the opener's own
--           widgets to DLG from YPOS down, answering where the next would go. YPOS already stands clear of the standard
--           fields, those being the person and these the opener's own. They are placed at DLG.x, and DLG.lw is the
--           label width of the standard fields. A widget of the opener's resets itself when the dialog opens by catching
--           OnShow, and what it holds goes in DLG.entry, which is a fresh empty table every time the dialog opens.
--   accept  function (dlg, info) called with OK once a name and a class are given, INFO being { name, class, msspec, osspec,
--           pprof, sprof, main } with NAME as typed and MAIN the main's KUID, "" for -Nobody-. Answering true leaves the
--           dialog open, for a refusal the opener has reported.
--   owner   Whose window this is, for the plate. Kore's own editor leaves it out and the dialog is the suite's, because all
--           it does there is make a person. An opener that is doing more than that, a mod's page that also enrols them
--           somewhere of its own and adds fields to say how, passes itself and the dialog is plated as its own windows are.
--           This is the same split as ERR above: what the dialog reports and what it calls itself both belong to whoever
--           raised it, and only that opener knows which it is.
--
-- The dialog is as tall as what is in it, extra fields included. dlg:Open() empties it and shows it. However it closes, it
-- throws OnHide, which is where an opener that stood aside for it comes back.
--
local USERDLG_WIDTH = 370

--
-- What separates one part of the dialog from another, on top of the gap between two rows of the same part. There are three:
-- under the title plate, which straddles the top rim rather than sitting above it and would otherwise have the first row
-- crowded against its words; before whatever the opener adds, which is its own fields rather than the person's; and over the
-- buttons, which are a different kind of thing again from the fields above them.
--
local USERDLG_SECTION_GAP = 10

function KU:CreateUserDialog(cfg)
  local dlg = KUI:CreateDialogFrame({
    x = "CENTER", y = "MIDDLE", name = cfg.name, title = (cfg.owner or KU):WindowTitle(L["Create user"]),
    border = true, width = USERDLG_WIDTH, height = 300,
    canmove = true, canresize = false, escclose = true, blackbg = true,
    okbutton = true, cancelbutton = true,
  })

  local labels = shared_labels()

  tinsert(labels, L["Name"])

  local lw = KUI:WidestString(labels)
  local info = {}
  local ypos = 0 - USERDLG_SECTION_GAP

  dlg.x = 5
  dlg.lw = lw

  --
  -- The name and the class are one row. A class is a word from a list of ten and is as wide as the longest of them, and the
  -- name is what a name box is anywhere: as wide as a name usually is, taking a long one that runs past the end of it as it
  -- is typed. The class needs no words of its own beside a row that is plainly the person.
  --
  -- The name's label is as wide as the word it holds, in whatever locale, and its box stands the usual gap after it. It lines
  -- up with nothing below it and is not meant to: the rows under it are pairs standing under their own words, and a label
  -- stretched to the width of the widest of those would leave the name sitting a third of the dialog away from what names it.
  --
  dlg.username = KUI:CreateEditBox({
    x = dlg.x, y = ypos, charwidth = KU.NAME_CHARS, len = KU.NAME_MAXLEN,
    label = { text = L["Name"], pos = "LEFT", width = KUI:MeasureStrWidth(L["Name"]) },
    tooltip = { title = "$$", text = L["TIP072"] },
  }, dlg)

  dlg.class = self:CreateClassDropdown(cfg.name .. "ClassDD", nil, nil, dlg, KU:ClassWidth(), nil, "NONE")
  dlg.class:ClearAllPoints()
  dlg.class:SetPoint("LEFT", dlg.username, "RIGHT", KUI.WIDGET_GAP, 0)
  dlg.class:Catch("OnValueChanged", function(this, evt, newv)
    info.class = newv
    dlg.shared:SetClass(newv)
  end)
  ypos = ypos - dlg.class:GetHeight() - KUI.WIDGET_GAP - KUI.DROPDOWN_ADD_GAP

  dlg.shared = self:CreateSharedUserInfo({
    prefix = cfg.name, x = dlg.x, y = ypos, lw = lw,
    changed = function(field, value)
      info[field] = value
    end,
  }, dlg)
  ypos = dlg.shared.ypos

  if (cfg.extra) then
    ypos = cfg.extra(dlg, ypos - USERDLG_SECTION_GAP)
  end

  --
  -- The last row's gap is the one the dialog already leaves above its buttons, and the buttons stand clear of the fields by
  -- their own gap on top of it.
  --
  dlg:SetHeight(dlg.rings.top - ypos - KUI.WIDGET_GAP + USERDLG_SECTION_GAP + dlg.rings.bottom)

  dlg.OnAccept = function(this)
    local name = this.username:GetText()

    if (not name or name == "") then
      cfg.err(L["you must specify a character name."])
      this.username:SetFocus()
      return true
    end

    if (not K.CanonicalName(name)) then
      cfg.err(L["%q is not a valid character name."], name)
      this.username:SetFocus()
      return true
    end

    if (not info.class) then
      cfg.err(L["you must set a user class."])
      return true
    end

    local keep = cfg.accept(this, {
      name = name, class = info.class, msspec = info.msspec, osspec = info.osspec, pprof = info.pprof, sprof = info.sprof,
      main = info.main,
    })

    if (keep) then
      return true
    end

    this:Hide()
  end

  dlg.Open = function(this)
    info = { msspec = K.ROLE_UNSET, osspec = K.ROLE_UNSET, pprof = K.PROF_UNSET, sprof = K.PROF_UNSET, main = "" }
    this.entry = {}
    this.username:SetText("")

    -- Nothing picked, so the box says what it is for: the dropdown's title, which is not an item and cannot be chosen.
    this.class:SetValue(nil, true)
    this.shared:SetNew()
    this:Show()
    this.username:SetFocus()
  end

  return dlg
end

--
-- The guild import dialog, one for the whole mod, which the user editor and every policy's Users page raise alike. It imports
-- every member of the ranks ticked who is at least the minimum level: each becomes a user of the mod, if they are not one
-- already, and is then handed to whoever raised the dialog. The user editor wants no more than that. A policy's page adds them
-- to its config as well.
--
-- How many ranks the guild has decides both how many rows the dialog has and how tall it is, so it is built again when that
-- changes. WoW cannot destroy a frame, so the old one is orphaned rather than freed, which is a fair price for something that
-- happens when a guild is reorganised.
--
local guildimportdlg = nil

--
-- Wide enough for the plate along its top, which carries the suite, the mod and the window's own name, rather than only for
-- the rank names under it. A guild's ranks are its own words and some of them are long, so the room the title asks for is
-- room the checkboxes wanted anyway.
--
local GUILDIMP_WIDTH = 340

-- One rank, and how wide the slider is drawn. The slider carries its own label above it and its bounds below.
local GUILDIMP_RANK_H = 24
local GUILDIMP_SLIDER_W = 200

-- What a rank is drawn in. Said rather than left to the default, because the width is measured in it (see below).
local GUILDIMP_RANK_FONT = "GameFontHighlight"

--
-- Clear air under the title plate before the box starts. The plate straddles the top rim rather than sitting above it, so
-- the content's own top edge is already close under it and the first rank would otherwise be crowded against the words.
--
local GUILDIMP_TOP_GAP = 10

local function build_guild_import(self)
  local ret = KUI:CreateDialogFrame({
    x = "CENTER", y = "MIDDLE", name = "KoreGuildImportDlg" .. K.guild.numranks, title = KU:WindowTitle(L["Import guild users"]),
    border = true, width = GUILDIMP_WIDTH, height = 200, canmove = true, canresize = false,
    escclose = true, blackbg = true, okbutton = true, cancelbutton = true,
  })

  ret.numranks = K.guild.numranks

  --
  -- The ranks as one column, every one of them as wide as the guild's own longest rank name asks for, so they share a left
  -- edge and the ticks run in a straight line. They are the guild's words rather than ours, so the width is measured from
  -- them rather than written down, and a guild that has renamed everything gets names that fit rather than names cut off at
  -- a number somebody picked once.
  --
  -- Measured exactly as a checkbox sizes itself to its own label: the words, the box, the gap between the two and the pad
  -- past the end. The box is as wide as the row is tall, and the words have to be measured in the font they will be drawn
  -- in, so that font is said here rather than left to each side's default, the two defaults not being the same one.
  --
  local names = {}

  for i = 1, K.guild.numranks do
    tinsert(names, K.guild.ranks[i])
  end

  local rankw = (KUI:WidestString(names, GUILDIMP_RANK_FONT)) + GUILDIMP_RANK_H + KUI.INTERNAL_GAP +
    KUI.CHECKBOX_LABEL_PAD
  local y = 0 - GUILDIMP_TOP_GAP

  for i = 1, K.guild.numranks do
    ret["rankcb" .. tostring(i)] = KUI:CreateCheckBox({
      x = "CENTER", y = y, width = rankw, height = GUILDIMP_RANK_H, autosize = false,
      label = { text = K.guild.ranks[i], font = GUILDIMP_RANK_FONT },
    }, ret)
    y = y - GUILDIMP_RANK_H
  end

  --
  -- The slider under them, centred too, so the dialog reads down one line rather than as two things pushed against its left
  -- edge with the plate centred above them.
  --
  local ypos = y - KUI.WIDGET_GAP * 2

  ret.minlevel = KUI:CreateSlider({
    x = "CENTER", y = ypos, width = GUILDIMP_SLIDER_W, minval = 1, maxval = K.maxlevel, initialvalue = K.maxlevel, step = 1,
    label = { text = L["Minimum level"], }, tooltip = { title = "$$", text = L["TIP074"] },
  }, ret)

  --
  -- As tall as what is in it, the number of ranks being the guild's business rather than ours.
  --
  ypos = ypos - ret.minlevel:GetHeight() - KUI.WIDGET_GAP

  ret:SetHeight(ret.rings.top - ypos + ret.rings.bottom)

  ret.OnCancel = function(this)
    this.count = nil
    this:Hide()
  end

  ret.OnAccept = function(this)
    local minlev = this.minlevel:GetValue()
    local roster = K.guild.roster.id
    local count = 0

    for i = 1, K.guild.numroster do
      local m = roster[i]
      local cb = this["rankcb" .. tostring(m.rank)]

      if (cb and cb:GetChecked() and m.level >= minlev) then
        local kuid, rec, isnew = self:Add(m.name, m.class)

        if (kuid) then
          if (this.onadd) then
            isnew = this.onadd(kuid, m.class, isnew)
          end
          if (isnew) then
            count = count + 1
          end
        end
      end
    end

    --
    -- Anybody new to the mod is in the user editor now, whether or not whoever raised the dialog counted them.
    --
    self:RefreshUserEditor()

    this.count = count
    this:Hide()
  end

  --
  -- However it closes, OK, Cancel or Escape, whoever raised it hears about it once, with how many were added or nil when nothing was imported.
  --
  ret:Catch("OnHide", function(this, evt)
    local onclose = this.onclose

    this.onclose = nil
    this.onadd = nil
    if (onclose) then
      onclose(this.count)
    end
  end)

  return ret
end

--
-- Raise the guild import dialog. ONADD is function (kuid, class, isnew) -> added, called for each member imported once they
-- are a user of the mod, KUID being who they are and ISNEW whether this import made them one. It answers whether it
-- added them to anything, and that is what is counted. Nil counts the members who were new to the mod. ONCLOSE is function
-- (count), called when the dialog closes, COUNT being how many were added or nil when it was cancelled. A caller that
-- stands its window aside puts it back there.
--
-- OWNER is whose window this is, as KU:CreateUserDialog takes it. There is one of these dialogs however many openers there
-- are, one per number of ranks, so the plate is set as it is raised rather than as it is built.
--
function KU:OpenGuildImport(onadd, onclose, owner)
  if (guildimportdlg and guildimportdlg.numranks ~= K.guild.numranks) then
    guildimportdlg:Hide()
    guildimportdlg = nil
  end

  if (not guildimportdlg) then
    guildimportdlg = build_guild_import(self)
  end

  guildimportdlg:SetTitleText((owner or KU):WindowTitle(L["Import guild users"]))

  --
  -- Raised again while it is already up, whoever raised it before is told it closed with nothing imported, so that they put
  -- back what they stood aside. That is why an opener stands its window aside only once this has returned.
  --
  if (guildimportdlg.onclose) then
    local onclose = guildimportdlg.onclose

    guildimportdlg.onclose = nil
    guildimportdlg.onadd = nil
    onclose(nil)
  end

  --
  -- Every rank starts checked, importing the whole guild being what this is almost always for. Leaving ranks out is the
  -- exception and is a couple of clicks, where ticking eight ranks to reach the common case is not. Set here rather than at
  -- creation so that a reused dialog opens the same way a new one does.
  --
  --
  -- The rank names are put back each time too, a rank renamed since the dialog was built keeping its place.
  --
  for i = 1, K.guild.numranks do
    guildimportdlg["rankcb" .. tostring(i)]:SetText(K.guild.ranks[i])
    guildimportdlg["rankcb" .. tostring(i)]:SetChecked(true)
  end

  guildimportdlg.count = nil
  guildimportdlg.onadd = onadd
  guildimportdlg.onclose = onclose
  guildimportdlg:Show()
end
