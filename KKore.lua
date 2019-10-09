--[[
   KahLua Kore - core library functions for KahLua addons.
     WWW: http://kahluamod.com/kore
     Git: https://github.com/kahluamods/kore
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com

   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2019 James Kean Johnston. All rights reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

   PLEASE NOTE: the above copyright and license terms only apply to code that
   I (James Kean Johnston) wrote. Where different copyright holders exist
   for code I have used, under different license terms, I have noted that
   in the code.
]]

--
-- This portion of this file is the embedded LibStub, with full credit to
-- Kaelton, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel and joshborke.
-- That code is in in the public domain. See http://www.wowace.com/wiki/LibStub
-- for details.
--
local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
local LibStub = _G[LIBSTUB_MAJOR]

if (not LibStub or LibStub.minor < LIBSTUB_MINOR) then
  LibStub = LibStub or {libs = {}, minors = {} }
  _G[LIBSTUB_MAJOR] = LibStub
  LibStub.minor = LIBSTUB_MINOR

  function LibStub:NewLibrary (major, minor)
    assert (type (major) == "string",
      "LibStub:Newlibrary: bad argument #1 (string expected).")
    minor = assert (tonumber (strmatch (minor, "%d+")),
      "LibStub:NewLibrary: minor version must either be a number or contain a number.")
    local oldminor = self.minors[major]

    if (oldminor and oldminor >= minor) then
      return nil
    end

    self.minors[major] = minor
    self.libs[major] = self.libs[major] or {}
    return self.libs[major], oldminor
  end -- Function LibStub:NewLibrary

  function LibStub:GetLibrary (major, silent)
    if ((not self.libs[major]) and (not silent)) then
      error (("Cannot find a library instance of %q."):format (tostring (major)), 2)
    end
    return self.libs[major], self.minors[major]
  end -- Function LibStub:GetLibrary

  function LibStub:IterateLibraries()
    return pairs(self.libs)
  end -- Function LibStub:IterateLibraries

  setmetatable (LibStub, { __call = LibStub.GetLibrary })
end
--
-- End of LibStub code
--

local KKORE_MAJOR = "KKore"
local KKORE_MINOR = 2

local K = LibStub:NewLibrary (KKORE_MAJOR, KKORE_MINOR)

if (not K) then
  return
end

local kaoname = ...
if (string.lower (kaoname) == "kkore") then
  K.KORE_PATH = "Interface\\Addons\\KKore\\"
else
  K.KORE_PATH = "Interface\\Addons\\" .. kaoname .. "\\KKore\\"
end

_G["KKore"] = K

K.extensions = K.extensions or {}

-- Local aliases for global or Lua library functions
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tostring = tostring
local GetTime = GetTime
local min = math.min
local max = math.max
local floor = floor
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local strlower = string.lower
local strupper = string.upper
local strbyte = string.byte
local strchar = string.char
local gmatch = string.gmatch
local match = string.match
local gsub = string.gsub
local xpcall, pcall = xpcall, pcall
local pairs, next, type = pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local band, rshift = bit.band, bit.rshift
local unpack, error = unpack, error

local k,v,i

local kore_ready = 0

K.local_realm = K.local_realm or select (2, UnitFullName ("player"))

--
-- Capitalise the first character in a users name. Many thanks to Arrowmaster
-- in #wowuidev on irc.freenode.net for the pattern below.
--
function K.CapitaliseName (name)
  assert (name)
  return gsub(strlower (name), "^([\192-\255]?%a?[\128-\191]*)", strupper, 1)
end
K.CapitalizeName = K.CapitaliseName

--
-- Return a full Name-Realm string. Even for users on the local realm it will
-- add it so that names are universally in the format Name-Realm. This will
-- always be a valid tell target as the realm name has had all spaces and
-- special characters removed (it is the realm name as returned by UnitName()
-- or equivalent functions). This is so much more complicated than it needs to
-- be. Some Blizzard functions return a full Name-Realm string in which case
-- we have nothing to do except capitalise it according to our own rules.
-- Other functions return Name-realm if the player is on a different realm.
-- Still others return only the name even if they player is on a different
-- realm but they are in the guild. This has been carefully adjusted over
-- time to always do The Right Thing(TM).
--
function K.CanonicalName (name, realm)
  if (not name) then
    return nil
  end

  --
  -- If the name is already in Name-Realm format, simply remove any spaces
  -- and capitalise it according to our function above.
  --
  if (strfind (name, "-", 1, true)) then
    local nm = gsub (name, " ", "")
    return K.CapitaliseName (nm)
  end

  --
  -- If this wasn't set correctly during addon initialisation do it now.
  --
  K.local_realm = K.local_realm or select (2, UnitFullName ("player"))

  --
  -- Try UnitFullName (). This returns the player name as the first argument
  -- and the realm as the second. The realm name already has the spaces
  -- removed from it. However, this doesn't return anything if the user
  -- isn't online and it is ambiguous if the name given is a duplicate in the
  -- raid or the guild. But if this returns anything we go with it as there
  -- is only so much we can do.
  --
  local nm, rn = UnitFullName (name)

  if (nm and rn and nm ~= "" and rn ~= "") then
    return K.CapitaliseName (nm .. "-" .. rn)
  end

  if (not nm or nm == "") then
    nm = name
    rn = realm
  end

  if (not rn or rn == "") then
    rn = K.local_realm
  end

  if (not rn or rn == "") then
    return nil
  end

  nm = Ambiguate (nm, "mail")
  if (strfind (nm, "-", 1, true)) then
    return K.CapitaliseName (nm)
  else
    return K.CapitaliseName (nm .. '-' .. rn)
  end
end

function K.FullUnitName (unit)
  if (not unit or type (unit) ~= "string" or unit == "") then
    return nil
  end

  local unit_name, unit_realm = UnitFullName (unit)

  if (not unit_realm or unit_realm == "") then
    K.local_realm = K.local_realm or select (2, UnitFullName ("player"))
    unit_realm = K.local_realm
  end

  if (not unit_name or unit_name == "Unknown" or not unit_realm or unit_realm == "") then
    return nil
  end

  return K.CapitaliseName (unit_name .. "-" .. unit_realm)
end

function K.ShortName (name)
  return Ambiguate (name, "guild")
end

---
--- Some versions of the WoW client have problems with strfmt ("%08x", val)
--- for any val > 2^31. This simple functions avoids that.
---
function K.hexstr (val)
  local lowerbits = band (val, 0xffff)
  local higherbits = band (rshift (val, 16), 0xffff)
  return strfmt ("%04x%04x", higherbits, lowerbits)
end

K.player = K.player or {}
K.guild = K.guild or {}
K.guild.ranks = K.guild.ranks or {}
K.guild.roster = K.guild.roster or {}
K.guild.roster.id = K.guild.roster.id or {}
K.guild.roster.name = K.guild.roster.name or {}
K.guild.gmname = nil
K.raids = K.raids or { numraids = 0, info = {} }

local done_pi_once = false
local function get_static_player_info ()
  if (done_pi_once) then
    return true
  end

  K.local_realm = select (2, UnitFullName ("player"))
  if (not K.local_realm or K.local_realm == "") then
    K.local_realm = nil
    return false
  end

  K.player.name = K.FullUnitName ("player")
  if (not K.player.name) then
    return false
  end

  K.player.faction = UnitFactionGroup ("player")
  K.player.class = K.ClassIndex[select (2, UnitClass ("player"))]
  done_pi_once = true
  kore_ready = kore_ready + 1
  return true
end

local function update_player_and_guild ()
  if (not get_static_player_info ()) then
    return
  end

  K.player.level = UnitLevel ("player")
  if (IsInGuild()) then
    local gname, _, rankidx = GetGuildInfo ("player")
    if (not gname or gname == "") then
      return
    end
    K.player.guild = gname
    K.player.guildrankidx = rankidx + 1
    K.player.is_guilded = true
    if (IsGuildLeader ()) then
      K.player.is_gm = true
    else
      K.player.is_gm = false
    end
  else
    K.player.is_guilded = false
    K.player.guild = nil
    K.player.guildrankidx = 0
    K.player.is_gm = false
  end

  if (K.player.is_guilded) then
    local i

    K.guild.numranks = GuildControlGetNumRanks ()
    K.guild.ranks = {}
    K.guild.numroster = GetNumGuildMembers ()
    K.guild.roster = {}
    K.guild.roster.id = {}
    K.guild.roster.name = {}

    for i = 1, K.guild.numranks do
      local rname = GuildControlGetRankName (i)
      K.guild.ranks[i] = rname
    end

    for i = 1, K.guild.numroster do
      local nm, _, ri, lvl, _, _, _, _, ol, _, cl = GetGuildRosterInfo (i)
      nm = K.CanonicalName (nm)
      local iv = { name = nm, rank = ri + 1, level = lvl, class = K.ClassIndex[cl], online = ol and true or false }
      tinsert (K.guild.roster.id, iv)
      K.guild.roster.name[nm] = i
      if (ri == 0) then
        K.guild.gmname = nm
      end
    end
  else
    K.guild = {}
    K.guild.numranks = 0
    K.guild.ranks = {}
    K.guild.numroster = 0
    K.guild.roster = {}
    K.guild.roster.id = {}
    K.guild.roster.name = {}
    K.guild.gmname = nil
  end

  K:SendMessage ("PLAYER_INFO_UPDATED")
end

function K:UpdatePlayerAndGuild ()
  update_player_and_guild ()
end

--
-- The private table is used to store functions and variables that are
-- intended to be private to KahLua and its modules, not to general purpose
-- modules that use KahLua. This is simply to promote code-reuse, as some of
-- these functions are generically useful, and tend to appear in a lot of
-- addons. They can be used, but with the provisio that their interface is
-- subject to change without notice.
--
K.pvt = K.pvt or {}
local KP = K.pvt

--
-- Simple debugging mechanism.
--
K.debugging = K.debugging or {}
K.debugframe = nil
K.maxlevel = MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()]

K.debugging["kore"] = 9 -- @debug-delete@

function K.debug(addon, lvl, ...)
  if (not K.debugging[addon]) then
    K.debugging[addon] = 0
  end

  if (K.debugging[addon] < lvl) then
    return
  end

  local text = ":[:" .. addon .. ":]: " .. string.format(...)
  local frame = K.debugframe or DEFAULT_CHAT_FRAME
  frame:AddMessage(text, 0.6, 1.0, 1.0)
end

local function debug(lvl,...)
  K.debug("kore", lvl, ...)
end

--
-- Standard colors for usage messages, error messages and info messages
--
K.ucolor = { r = 1.0, g = 0.5, b = 0.0 }
K.ecolor = { r = 1.0, g = 0.0, b = 0.0 }
K.icolor = { r = 0.0, g = 1.0, b = 1.0 }

function K.printf(...)
  local first = ...
  local frame = DEFAULT_CHAT_FRAME
  local i = 1
  local r,g,b,id

  if (type(first) == "table") then
    if (first.AddMessage) then
      frame = first
      i = i + 1
    end

    local c = select(i, ...)
    if (type(c) == "table" and (c.r or c.g or c.b or c.id)) then
      r,g,b,id = c.r or nil, c.g or nil, c.b or nil, c.id or nil
      i = i + 1
    end
  end

  frame:AddMessage(string.format(select(i, ...)), r, g, b, id)
end

--
-- Here we set up a bunch of constants that are used frequently throughout
-- various modules. Some of them require actual computation, and its
-- pointless having multiple modules do the same computations, so we set up
-- the list of such constants here. Modules can then either reference these
-- directly (K.constant) or do a local constant = K.constant.
--
--K.NaNstring = tostring(0/0)
K.Infstring = tostring(math.huge)
K.NInfstring = tostring(-math.huge)

--
-- There are a number of places where we want to store classes, but storing
-- the class name is inefficient. So here we create a standard numbering
-- scheme for the classes. The numbers are always 2 digits, so that when they
-- are embedded in strings, we can always lift out exactly two digits to get
-- back to the class name.
--

K.CLASS_WARRIOR     = "01"
K.CLASS_PALADIN     = "02"
K.CLASS_HUNTER      = "03"
K.CLASS_ROGUE       = "04"
K.CLASS_PRIEST      = "05"
K.CLASS_SHAMAN      = "07"
K.CLASS_MAGE        = "08"
K.CLASS_WARLOCK     = "09"
K.CLASS_DRUID       = "11"

K.ClassIndex = {
  ["WARRIOR"]     = K.CLASS_WARRIOR,
  ["PALADIN"]     = K.CLASS_PALADIN,
  ["HUNTER"]      = K.CLASS_HUNTER,
  ["ROGUE"]       = K.CLASS_ROGUE,
  ["PRIEST"]      = K.CLASS_PRIEST,
  ["SHAMAN"]      = K.CLASS_SHAMAN,
  ["MAGE"]        = K.CLASS_MAGE,
  ["WARLOCK"]     = K.CLASS_WARLOCK,
  ["DRUID"]       = K.CLASS_DRUID,
}

local kClassTable = {}
FillLocalizedClassList (kClassTable, false)

local warrior = kClassTable["WARRIOR"]
local paladin = kClassTable["PALADIN"]
local hunter = kClassTable["HUNTER"]
local rogue = kClassTable["ROGUE"]
local priest = kClassTable["PRIEST"]
local shaman = kClassTable["SHAMAN"]
local mage = kClassTable["MAGE"]
local warlock = kClassTable["WARLOCK"]
local druid = kClassTable["DRUID"]

-- Same table but using the localised names
K.LClassIndex = {
  [warrior]     = K.CLASS_WARRIOR,
  [paladin]     = K.CLASS_PALADIN,
  [hunter]      = K.CLASS_HUNTER,
  [rogue]       = K.CLASS_ROGUE,
  [priest]      = K.CLASS_PRIEST,
  [shaman]      = K.CLASS_SHAMAN,
  [mage]        = K.CLASS_MAGE,
  [warlock]     = K.CLASS_WARLOCK,
  [druid]       = K.CLASS_DRUID,
}

K.LClassIndexNSP = {
  [gsub (warrior, " ", "")]     = K.CLASS_WARRIOR,
  [gsub (paladin, " ", "")]     = K.CLASS_PALADIN,
  [gsub (hunter, " ", "")]      = K.CLASS_HUNTER,
  [gsub (rogue, " ", "")]       = K.CLASS_ROGUE,
  [gsub (priest, " ", "")]      = K.CLASS_PRIEST,
  [gsub (shaman, " ", "")]      = K.CLASS_SHAMAN,
  [gsub (mage, " ", "")]        = K.CLASS_MAGE,
  [gsub (warlock, " ", "")]     = K.CLASS_WARLOCK,
  [gsub (druid, " ", "")]       = K.CLASS_DRUID,
}

-- And the reverse
K.IndexClass = {
  [K.CLASS_WARRIOR]     = { u = "WARRIOR", c = warrior },
  [K.CLASS_PALADIN]     = { u = "PALADIN", c = paladin },
  [K.CLASS_HUNTER]      = { u = "HUNTER", c = hunter },
  [K.CLASS_ROGUE]       = { u = "ROGUE", c = rogue },
  [K.CLASS_PRIEST]      = { u = "PRIEST", c = priest },
  [K.CLASS_SHAMAN]      = { u = "SHAMAN", c = shaman },
  [K.CLASS_MAGE]        = { u = "MAGE", c = mage },
  [K.CLASS_WARLOCK]     = { u = "WARLOCK", c = warlock },
  [K.CLASS_DRUID]       = { u = "DRUID", c = druid },
}
for k,v in pairs(K.IndexClass) do
  if (v.c) then
    K.IndexClass[k].l = gsub (strlower(v.c), " ", "")
  end
end

--
-- Maps a class ID to a widget name. We cannot use IndexClass.l because that
-- can be localised. So for widget names, we always use the English name and
-- it is always one of these values.
--
K.IndexClass[K.CLASS_WARRIOR].w     = "warrior"
K.IndexClass[K.CLASS_PALADIN].w     = "paladin"
K.IndexClass[K.CLASS_HUNTER].w      = "hunter"
K.IndexClass[K.CLASS_ROGUE].w       = "rogue"
K.IndexClass[K.CLASS_PRIEST].w      = "priest"
K.IndexClass[K.CLASS_SHAMAN].w      = "shaman"
K.IndexClass[K.CLASS_MAGE].w        = "mage"
K.IndexClass[K.CLASS_WARLOCK].w     = "warlock"
K.IndexClass[K.CLASS_DRUID].w       = "druid"

--
-- Many mods need to know the different class colors. We set up three tables
-- here. The first is percentage-based RGB values, the second is decimal,
-- with all numbers between 0 and 255 and the third is with text strings
-- suitable for messages.
-- This also means that it is possible to change the class colors for all
-- KahLua mods by simply changing these values.
--
K.ClassColorsRGBPerc = {
  [K.CLASS_WARRIOR]     = RAID_CLASS_COLORS["WARRIOR"],
  [K.CLASS_PALADIN]     = RAID_CLASS_COLORS["PALADIN"],
  [K.CLASS_HUNTER]      = RAID_CLASS_COLORS["HUNTER"],
  [K.CLASS_ROGUE]       = RAID_CLASS_COLORS["ROGUE"],
  [K.CLASS_PRIEST]      = RAID_CLASS_COLORS["PRIEST"],
  [K.CLASS_SHAMAN]      = RAID_CLASS_COLORS["SHAMAN"],
  [K.CLASS_MAGE]        = RAID_CLASS_COLORS["MAGE"],
  [K.CLASS_WARLOCK]     = RAID_CLASS_COLORS["WARLOCK"],
  [K.CLASS_DRUID]       = RAID_CLASS_COLORS["DRUID"],
}

function K.RGBPercToDec (rgb)
  local ret = {}
  ret.r = rgb.r * 255
  ret.g = rgb.g * 255
  ret.b = rgb.b * 255
  return ret
end

function K.RGBDecToHex (rgb)
  return string.format("%02x%02x%02x", rgb.r, rgb.g, rgb.b)
end

function K.RGBPercToHex (rgb)
  return string.format("%02x%02x%02x", rgb.r*255, rgb.g*255, rgb.b*255)
end

function K.RGBPercToColorCode (rgb)
  local a = 1
  if (rgb.a) then
    a = rgb.a
  end
  return string.format("|c%02x%02x%02x%02x", a*255, rgb.r*255, rgb.g*255, rgb.b*255)
end

function K.RGBDecToColorCode (rgb)
  local a = 255
  if (rgb.a) then
    a = rgb.a
  end
  return string.format("|c%02x%02x%02x%02x", a, rgb.r, rgb.g, rgb.b)
end

function K.SetupClassColors ()
  K.ClassColorsRGB = {}
  K.ClassColorsHex = {}
  K.ClassColorsEsc = {}
  K.ClassColorsRGBPerc2 = {}
  K.ClassColorsRGB2 = {}
  K.ClassColorsHex2 = {}
  K.ClassColorsEsc2 = {}

  for k,v in pairs (K.ClassIndex) do
    K.ClassColorsRGB[v] = K.RGBPercToDec (K.ClassColorsRGBPerc[v])
    K.ClassColorsHex[v] = K.RGBDecToHex (K.ClassColorsRGB[v])
    K.ClassColorsEsc[v] = K.RGBPercToColorCode (K.ClassColorsRGBPerc[v])

    local r, g, b, a
    r = K.ClassColorsRGBPerc[v].r / 1.75
    g = K.ClassColorsRGBPerc[v].g / 1.75
    b = K.ClassColorsRGBPerc[v].b / 1.75
    a = K.ClassColorsRGBPerc[v].a or 1
    K.ClassColorsRGBPerc2[v] = { r = r, g = g, b = b, a = a }
    K.ClassColorsRGB2[v] = K.RGBPercToDec (K.ClassColorsRGBPerc2[v])
    K.ClassColorsHex2[v] = K.RGBDecToHex (K.ClassColorsRGB2[v])
    K.ClassColorsEsc2[v] = K.RGBPercToColorCode (K.ClassColorsRGBPerc2[v])
  end
end

-- Set the defaults and conversion tables
K.SetupClassColors ()

-- Utility function to copy one table to another
function K.CopyTable (src, dest)
  if (type (dest) ~= "table") then
    dest = {}
  end

  if (type (src) == "table") then
    for k, v in pairs (src) do
      if (type (v) == "table") then
        v = K.CopyTable (v, dest[k])
      end
      dest[k] = v
    end
  end
  return dest
end

--
-- Quite a few metatables want to prevent indexed access, so this
-- function is used quite a bit. It simply always asserts false which
-- will raise an exception.
--
K.assert_false = function() assert(false) end

--
-- Two functions to always return true or false
--
K.always_true = function(self) return true end
K.always_false = function(self) return false end

--
-- All KahLua mods support localization. These few simple functions
-- allow us to localize messages, menu items etc.
--

-- We treat British the same as American English.
K.CurrentLocale = GetLocale()
if (K.CurrentLocale == "enGB") then
  K.CurrentLocale = "enUS"
end

--
-- We store the translations for each KahLua module in its own table.
-- What we actually store is a reference to the table, indexed by the
-- module name. This table reference is returned by GetI18NTable() below.
-- For error reporting purposes, we also store a reverse table which
-- returns the module name given a table reference, since at the time we
-- report the error we do not have the module name in context, only the
-- I18N table being used.
--
K.I18Nmodtables = K.I18Nmodtables or {}
K.I18Nmodnames = K.I18Nmodnames or {}

local i18n_mt_ta = {
  __index = function(self, key)
    local mname = tostring(K.I18Nmodnames[self])
    rawset(self, key, key)
    geterrorhandler() ("KKore I18N (" .. mname .. 
      "): Untranslated string '" .. tostring(key) .. "'")
    return key
  end
}

--
-- This metatable function is used when a user wants to bypass all
-- localised strings for a given module (for example, raid warning
-- modules may not want to send out warnings in foreign languages).
-- This simply always returns the key and ignores the value. The
-- GetI18NTable() function below will set this as the metatable if
-- instructed to ignore localisation tables.
local i18n_mt_ta_ign = {
  __index = function (self, key)
    rawset(self, key, key)
    return key
  end
}

local regi18n

local i18n_mt_tableset = setmetatable({}, {
  __newindex = function(self, k, v)
    rawset(regi18n, k, (type(v) == "boolean" and v == true) and k or v)
  end,
  __index = K.assert_false
})

local i18n_mt_tableset_default = setmetatable({}, {
  __newindex = function(self, k, v)
    if (not rawget(regi18n, k)) then
      rawset(regi18n, k, (type(v) == "boolean" and v == true) and k or v)
    end
  end,
  __index = K.assert_false
})

function K:RegisterI18NTable (modname, locale)
  local rl = locale
  local dflt = false
  local mtbl = K.I18Nmodtables[modname]

  if (locale == "enUS") or (locale == "enGB") then
    dflt = true
    locale = "enUS"
  end

  if (locale ~= K.CurrentLocale and not dflt) then
    return
  end

  if (not mtbl) then
    mtbl = setmetatable({}, dflt and i18n_mt_ta_ign or i18n_mt_ta)
    K.I18Nmodtables[modname] = mtbl
    K.I18Nmodnames[mtbl] = modname
  end

  regi18n = mtbl

  if (dflt) then
    return i18n_mt_tableset_default
  end
  return i18n_mt_tableset
end

function K:GetI18NTable (modname, igni18n)
  local rtbl = K.I18Nmodtables[modname]

  if (not rtbl) then
    error("KKore I18N (" .. tostring(modname) .. 
      "): No translations registered for this module.")
  end

  if (igni18n) then
    setmetatable (rtbl, i18n_mt_ta_ign)
    return rtbl
  end

  setmetatable (rtbl, i18n_mt_ta)
  return rtbl
end

--
-- This next portion of Kore is by and large a copy of portions of Ace3.
-- This code is Copyright (C) 2007, Ace3 Development Team. All rights
-- reserved. Here is the license for that code.
--[[
Copyright (c) 2007, Ace3 Development Team

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.
  * Redistribution of a stand alone version is strictly prohibited without
    prior written authorization from the Lead of the Ace3 Development Team.
  * Neither the name of the Ace3 Development Team nor the names of its
    contributors may be used to endorse or promote products derived from
    this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--
-- You may well wonder why I embed Ace3 here and don't just use the
-- original. Mostly because I wanted KahLua Kore to be its own beast,
-- but the functionality of Ace3 is useful and part of what I wanted
-- to be in the Kore. Also, I learned more than a few things by looking
-- at the code but wanted to use my own coding style. I learn by doing,
-- and in going through the code and fitting it into Kore, I learned a great
-- deal. My profuse thanks to the authors of this code, they are obviously
-- extremely talented individuals. I also wanted Kore to be a simple
-- library that provided the features that all addons use, and not much
-- else. Ace3 went (in my opinion) a little over the top in splitting
-- things up, as almost every addon uses a core set of modules, such as
-- AceAddon, Callbackhandler etc. So I wrapped all of those up into Kore,
-- making my own small tweaks and changes along the way. Any errors
-- introduced by doing so are mine and do not reflect on the quality of
-- the original code.
--
KP.empty_table_meta = {
  __index = function(tbl, key)
    tbl[key] = {}
    return tbl[key]
  end
}
local empty_table_meta = KP.empty_table_meta

-- xpcall safecall implementation
KP.errorhandler = function (err)
  return geterrorhandler()(err)
end
local errorhandler = KP.errorhandler

--
-- This function creates a function with a variable number of arguments.
-- Its builds the actual function up in a text string and then loads it.
-- I haven't figured out exactly why this is necessary yet, but it is
-- used in AceAddon so it is duplicated here.
--
local function CreateDispatcher(argc)
  local code = [[
    local xpcall, eh = ...
    local method, ARGS
    local function call() return method(ARGS) end

    local function dispatch(func, ...)
      method = func
      if not method then return end
      ARGS = ...
      return xpcall(call, eh)
    end

    return dispatch
  ]]

  local ARGS = {}
  local i
  for i = 1, argc do ARGS[i] = "arg"..i end
  code = code:gsub("ARGS", tconcat(ARGS, ", "))
  return assert(loadstring(code, "safecall Dispatcher["..argc.."]"))(xpcall, errorhandler)
end

KP.Dispatchers = setmetatable({}, {
  __index=function(self, argc)
    local dispatcher = CreateDispatcher(argc)
    rawset(self, argc, dispatcher)
    return dispatcher
  end
})
local Dispatchers = KP.Dispatchers

Dispatchers[0] = function(func) return xpcall(func, errorhandler) end

--
-- safecall() checks to see if its argument is really a function before
-- calling it, and silently returns if its not. This is intended for
-- optional functions like OnInitialize().
--
KP.safecall = function (func, ...)
  if (type(func) == "function") then
    return Dispatchers[select("#",...)](func, ...)
  end
end
local safecall=KP.safecall

--
-- Same thing but each slot is a table(queue) of functions to call
--
local function CreateDispatcherQ(argc)
  local code = [[
  local next, xpcall, eh = ...

  local method, ARGS
  local function call() method(ARGS) end

  local function dispatch(handlers, ...)
    local index
    index, method = next(handlers)
    if not method then return end
    local OLD_ARGS = ARGS
    ARGS = ...
    repeat
      xpcall(call, eh)
      index, method = next(handlers, index)
    until not method
    ARGS = OLD_ARGS
  end

  return dispatch
  ]]

  local ARGS, OLD_ARGS = {}, {}
  local i
  for i = 1, argc do ARGS[i], OLD_ARGS[i] = "arg"..i, "old_arg"..i end
  code = code:gsub("OLD_ARGS", tconcat(OLD_ARGS, ", ")):gsub("ARGS", tconcat(ARGS, ", "))
  return assert(loadstring(code, "safecall DispatcherQ["..argc.."]"))(next, xpcall, errorhandler)
end

KP.DispatchersQ = setmetatable({}, {
  __index=function(self, argc)
    local dispatcher = CreateDispatcherQ(argc)
    rawset(self, argc, dispatcher)
    return dispatcher
  end
})
local DispatchersQ = KP.DispatchersQ

DispatchersQ[0] = function(func) return xpcall(func, errorhandler) end

--
-- This next section of code is the CallbackHandler stuff from Ace3.
--
function K:NewCB(target, regName, unregName, unregallName)
  regName = regName or "RegisterCallback"
  unregName = unregName or "UnregisterCallback"
  if (unregallName == nil) then
    unregallName = "UnregisterAllCallbacks"
  end

  local errstr = "KKore:NewCB(" .. regName .. "): "

  -- Create the registry object
  local events = setmetatable({}, empty_table_meta)
  local kregistry = {recurse = 0, events = events}

  function kregistry:Fire(eventname, ...)
    assert(eventname)
    local arg1 = ...
    if ((not rawget(events, eventname)) or
        (not next(events[eventname]))) then
      return
    end

    local oldrecurse = kregistry.recurse
    kregistry.recurse = oldrecurse + 1
    DispatchersQ[select("#", ...) + 1](events[eventname], eventname, ...)
    kregistry.recurse = oldrecurse

    if (kregistry.insertQueue and oldrecurse == 0) then
      -- Something in one of the callbacks wanted to register more callbacks,
      -- which got queued.
      for eventname,callbacks in pairs(kregistry.insertQueue) do
        local first = not rawget(events, eventname) or
          not next(events[eventname])
        for self,func in pairs(callbacks) do
          events[eventname][self] = func
          if (first and kregistry.OnUsed) then
            kregistry.OnUsed(kregistry, target, eventname)
            first = nil
          end
        end
      end
      kregistry.insertQueue = nil
    end
  end

  --
  -- Registration of a callback
  --
  target[regName] = function(self, eventname, method, ...)
    if (type(eventname) ~= "string") then
      error(errstr .. "'eventname' - string expected.", 2)
    end

    method = method or eventname

    local first = not rawget(events, eventname) or not next(events[eventname])
    if (type(method) ~= "string" and type(method) ~= "function") then
      error (errstr .. "'method' - string or function expected.", 2)
    end

    local regfunc

    if (type(method) == "string") then
      if (type(self) ~= "table") then
        error(errstr .. "self was not a table.", 2)
      elseif (self == target) then
        error(errstr .. "do not use KKore:"..regName.."(), use your own 'self'.", 2)
      elseif (type(self[method]) ~= "function") then
        error(errstr .. "method '" .. tostring(method) .. "' not found on self.", 2)
      end

      if (select("#", ...) >= 1) then
        local arg = select(1, ...)
        regfunc = function(...) self[method](self, arg, ...) end
      else
        regfunc = function(...) self[method](self, ...) end
      end
    else
      if (type(self) ~= "table" and type(self) ~= "string" and type(self) ~= "thread") then
        error (errstr .. "'self or addonId': table or string or thread expected.", 2)
      end

      if (select("#", ...) >= 1) then
        local arg = select(1, ...)
        regfunc = function(...) method(arg, ...) end
      else
        regfunc = method
      end
    end

    if (events[eventname][self] or
        kregistry.recurse < 1) then
      events[eventname][self] = regfunc
      if (kregistry.OnUsed and first) then
        kregistry.OnUsed(kregistry, target, eventname)
      end
    else
      -- We're currently process a callback in this registry, so delay
      -- the registration of this new entry by adding it to a queue
      -- that will be added when recursion terminates.
      kregistry.insertQueue = kregistry.insertQueue or
        setmetatable({}, empty_table_meta)
      kregistry.insertQueue[eventname][self] = regfunc
    end
  end

  -- Unregister a callback
  local errstr = "KKore:NewCB(" .. unregName .. "): "
  target[unregName] = function(self, eventname)
    if (not self or self == target) then
      error (errstr .. "bad 'self' ."..tostring(self), 2)
    end
    if (type(eventname) ~= "string") then
      error (errstr .. "'eventname' - string expected.", 2)
    end

    if (rawget(events, eventname) and events[eventname][self]) then
      events[eventname][self] = nil
      if (kregistry.OnUnused and not next(events[eventname])) then
        kregistry.OnUnused(kregistry, target, eventname)
      end
    end

    if (kregistry.insertQueue and rawget(kregistry.insertQueue, eventname)
        and kregistry.insertQueue[eventname][self]) then
      kregistry.insertQueue[eventname][self] = nil
    end
  end

  -- Optional: unregister all events
  local errstr = "KKore:NewCB(" .. unregallName .. "): "
  if (unregallName) then
    target[unregallName] = function(...)
      if (select("#", ...) < 1) then
        error (errstr .. "missing 'self' or addonId to unregister events for.", 2)
      end
      if (select("#", ...) == 1 and ... == target) then
        error (errstr .. "supply a meaningful self or addonId.", 2)
      end

      for i=1,select("#", ...) do
        local self = select(i, ...)
        if (kregistry.insertQueue) then
          for eventname, callbacks in pairs(kregistry.insertQueue) do
            if (callbacks[self]) then
              callbacks[self] = nil
            end
          end
        end
        for eventname, callbacks in pairs(events) do
          if (callbacks[self]) then
            callbacks[self] = nil
            if (kregistry.OnUnused and not next(callbacks)) then
              kregistry.OnUnused(kregistry, target, eventname)
            end
          end
        end
      end
    end
  end

  return kregistry
end

-- AceEvent 3.0 stuff
K.eventframe = K.eventframe or CreateFrame ("Frame", "KKoreEvent")
if (not K.events) then
  K.events = K:NewCB(K, "RegisterEvent",
    "UnregisterEvent", "UnregisterAllEvents")
end

function K.events:OnUsed(target, eventname)
  K.eventframe:RegisterEvent(eventname)
end

function K.events:OnUnused(target, eventname)
  K.eventframe:UnregisterEvent(eventname)
end

if (not K.messages) then
  K.messages = K:NewCB(K, "RegisterMessage",
    "UnregisterMessage", "UnregisterAllMessages")
  K.SendMessage = K.messages.Fire
end

local events = K.events
K.eventframe:SetScript("OnEvent", function(this, event, ...)
  events:Fire(event, ...)
end)

--
-- The list of functions that each addon gets when it is initialised via
-- K:NewAddon(). So for example, each addon gets an addon.SendMessage()
-- function. Calling addon.SendMessage() is identical to calling
-- K.SendMessage() directly.
--
local evtembeds = {
  "RegisterEvent", "UnregisterEvent",
  "RegisterMessage", "UnregisterMessage",
  "UnregisterAllMessages", "UnregisterAllEvents",
  "SendMessage",
}

for k,v in pairs (evtembeds) do
  KP[v] = K[v]
end

--
-- Initialise ChatThrottleLib if it hasn't been already
--
local ctl = _G.ChatThrottleLib
assert (ctl, "KahLua Kore requires ChatThrottleLib")
assert (ctl.version >= 22, "KahLua Kore requires ChatThrottleLib >= 22")
ctl.MIN_FPS = 15

--
-- Next up is the AceSerializer stuff. Useful for all addons.
--
local function SerStrHelper (ch)
  local n = strbyte (ch)

  if (n == 30) then
    return "\126\121"
  elseif (n == 58) then
    return "\126\122"
  elseif (n <= 32) then             -- nonprint + space
    return "\126" .. strchar (n+64)
  elseif (n == 94) then         -- value separator 
    return "\126\125"
  elseif (n == 126) then        -- our own escape character
    return "\126\124"
  elseif (n == 127) then        -- nonprint (DEL)
    return "\126\123"
  else
    assert(false)               -- can't be reached if caller uses a sane regex
  end
end

local function SerValue (v, res, nres)
  local t = type (v)

  if (t == "string") then
    res[nres+1] = "^S"
    res[nres+2] = gsub (v,"[%c \94\126\127]", SerStrHelper)
    nres = nres + 2
  elseif (t == "number") then
    local str = tostring (v)
    if (tonumber (str) == v or --[[str == K.NaNstring or]] str == K.InfString or
      str == K.NInfstring) then
      res[nres+1] = "^N"
      res[nres+2] = str
      nres = nres + 2
    else
      local m, e = frexp (v)
      res[nres+1] = "^F"
      res[nres+2] = strfmt ("%.0f", m * 2^53)
      res[nres+3] = "^f"
      res[nres+4] = tostring(e-53)
      nres = nres + 4
    end
  elseif (t == "table") then
    nres = nres + 1
    res[nres] = "^T"
    for k,v in pairs (v) do
      nres = SerValue (k, res, nres)
      nres = SerValue (v, res, nres)
    end
    nres = nres + 1
    res[nres] = "^t"
  elseif (t == "boolean") then
    nres = nres + 1
    if (v == true) then
      res[nres] = "^B"
    else
      res[nres] = "^b"
    end
  elseif (t == "nil") then
    nres = nres + 1
    res[nres] = "^Z"
  end

  return nres
end

local sertbl = { "^1" }

function K.Serialise (...)
  local nres = 1

  for i = 1, select("#", ...) do
    local v = select (i, ...)
    nres = SerValue (v, sertbl, nres)
  end

  nres = nres + 1
  sertbl[nres] = "^^"
  return tconcat (sertbl, "", 1, nres)
end
K.Serialize = K.Serialise -- Help Americans who can't spell

local function DeserStrHelper (esc)
  if (esc < "~\121") then
    return strchar (strbyte (esc,2,2)-64)
  elseif (esc == "~\121") then
    return ("\030")
  elseif (esc == "~\122") then
    return ("\58")
  elseif (esc == "~\123") then
    return "\127"
  elseif (esc == "~\124") then
    return "\126"
  elseif (esc == "~\125") then
    return "\94"
  end
end

local function DeserNumHelper (num)
  --[[if (num == K.NaNstring) then
    return 0/0
  else]]if (num == K.NInfstring) then
    return -1/0
  elseif (num == K.Infstring) then
    return 1/0
  else
    return tonumber (num)
  end
end

local function DeserValue (iter, single, ctl, data)
  if (not single) then
    ctl,data = iter()
  end

  if (not ctl) then 
    error("Supplied data misses KoreSerializer terminator ('^^')")
  end

  if (ctl == "^^") then
    return
  end

  local res

  if (ctl == "^S") then
    res = gsub(data, "~.", DeserStrHelper)
  elseif (ctl == "^N") then
    res = DeserNumHelper(data)
    if (not res) then
      error("Invalid serialized number: '"..tostring(data).."'")
    end
  elseif (ctl == "^F") then     -- ^F<mantissa>^f<exponent>
    local ctl2,e = iter()
    if (ctl2 ~= "^f") then
      error("Invalid serialized floating-point number, expected '^f', not '"..tostring(ctl2).."'")
    end
    local m=tonumber(data)
    e=tonumber(e)
    if (not (m and e)) then
      error("Invalid serialized floating-point number, expected mantissa and exponent, got '"..tostring(m).."' and '"..tostring(e).."'")
    end
    res = m*(2^e)
  elseif (ctl == "^B") then
    res = true
  elseif (ctl == "^b") then
    res = false
  elseif (ctl == "^Z") then
    res = nil
  elseif (ctl == "^T") then
    res = {}
    local k,v
    while true do
      ctl,data = iter()
      if (ctl == "^t") then
        break
      end
      k = DeserValue (iter, true, ctl, data)
      if (k == nil) then 
        error("Invalid KoreSerializer table format (no table end marker)")
      end
      ctl,data = iter()
      v = DeserValue (iter, true, ctl, data)
      if (v == nil) then
        error("Invalid KoreSerializer table format (no table end marker)")
      end
      res[k]=v
    end
  else
    error("Invalid KoreSerializer control code '"..ctl.."'")
  end

  if (not single) then
    return res, DeserValue (iter)
  else
    return res
  end
end

function K.Deserialise (str)
  str = gsub (str, "[%c ]", "")

  local iter = gmatch (str, "(^.)([^^]*)")
  local ctl,data = iter()
  if ((not ctl) or (ctl ~= "^1")) then
    return false, "Supplied data is not KoreSerializer data (rev 1)"
  end

  return pcall (DeserValue, iter)
end
K.Deserialize = K.Deserialise -- Help Americans who can't spell

--
-- AceTimer-3.0 (r17) stuff. Schedule periodic timers.
--

K.activetimers = K.activetimers or {}
local activetimers = K.activetimers

local GetTime, C_TimerAfter = GetTime, C_Timer.After

local function newTimer(self, loop, func, delay, ...)
  if (delay < 0.01) then
    delay = 0.01
  end

  local timer = {...}
  timer.object = self
  timer.func = func
  timer.looping = loop
  timer.argscount = select ("#", ...)
  timer.delay = delay
  timer.ends = GetTime() + delay

  activetimers[timer] = timer

  timer.callback = function() 
    if not timer.cancelled then
      if (type(timer.func) == "string") then
        timer.object[timer.func](timer.object, unpack(timer, 1, timer.argscount))
      else
        timer.func(unpack(timer, 1, timer.argscount))
      end

      if (timer.looping and not timer.cancelled) then
        local time = GetTime()
        local delay = timer.delay - (time - timer.ends)

        if (delay < 0.01) then
          delay = 0.01
        end

        C_TimerAfter(delay, timer.callback)
        timer.ends = time + delay
      else
        activetimers[timer.handle or timer] = nil
      end
    end
  end

  C_TimerAfter(delay, timer.callback)
  return timer
end

function K:ScheduleTimer (func, delay, ...)
  return newTimer (self, nil, func, delay, ...)
end

function K:ScheduleRepeatingTimer (func, delay, ...)
  return newTimer (self, true, func, delay, ...)
end

function K:CancelTimer (id)
  local timer = activetimers[id]
  if (not timer) then
    return false
  else
    timer.cancelled = true
    activetimers[id] = nil
    return true
  end
end

function K:CancelAllTimers ()
  for k,v in pairs(activetimers) do
    if (v.object == self) then
      K.CancelTimer (self, k)
    end
  end
end

function K:TimeLeft (id)
  local timer = activetimers[id]
  if (not timer) then
    return 0
  else
    return timer.ends - GetTime()
  end
end

--
-- And last, but not least, of the Ace3 stuff: AceComm.
--
local MSG_MULTI_FIRST = "\001"
local MSG_MULTI_NEXT  = "\002"
local MSG_MULTI_LAST  = "\003"
local MSG_ESCAPE      = "\004"

K.comm = K.comm or {}
local com = K.comm
com.mp_origprefixes = nil
com.mp_reassemblers = nil
com.mp_spool = com.mp_spool or {}
com.ourprefixes = com.ourprefixes or {}

function com:RegisterComm (prefix, method)
  if (method == nil) then
    method = "OnCommReceived"
  end
  if (C_ChatInfo) then
    C_ChatInfo.RegisterAddonMessagePrefix (prefix)
  else
    RegisterAddonMessagePrefix (prefix)
  end
  com.ourprefixes[prefix] = true
  return com._RegisterComm (self, prefix, method)
end

function com:UnregisterComm (prefix, ...)
  com.ourprefixes[prefix] = nil
  return com._UnregisterComm (prefix, ...)
end

function com.SendCommMessage (prefix,text,dist,target,prio,cback,cbackarg)
  local self = com
  prio = prio or "NORMAL"
  if (not (type (prefix) == "string" and
           type (text) == "string" and
           type (dist) == "string" and
           (target == nil or type (target) == "string") and
           (prio == "BULK" or prio == "NORMAL" or prio == "ALERT"))) then
    error ("K.comm.SendCommMessage: invalid usage.", 2)
  end

  local textlen = #text
  local maxtextlen = 255 - #prefix
  local qname = prefix..dist..(target or "")

  local ctlCallback = nil
  if (cback) then
    ctlCallback = function (sent) return cback (cbackarg, sent, textlen) end
  end

  local forcemp
  if (match (text, "^[\001-\009]")) then
    if (textlen+1 > maxtextlen) then
      forcemp = true
    else
      text ="\004" .. text
    end
  end

  if (not forcemp and textlen <= maxtextlen) then
    -- Fits in a single message
    ctl:SendAddonMessage (prio, prefix, text, dist, target, qname, ctlCallback, textlen)
  else
    maxtextlen = maxtextlen - 1

    -- First part
    local chunk = strsub (text, 1, maxtextlen)
    ctl:SendAddonMessage (prio, prefix, MSG_MULTI_FIRST..chunk, dist, target, qname, ctlCallback, maxtextlen)

    local pos=1+maxtextlen

    while (pos+maxtextlen <= textlen) do
      chunk = strsub (text, pos, pos+maxtextlen-1)
      ctl:SendAddonMessage (prio, prefix, MSG_MULTI_NEXT..chunk, dist, target, qname, ctlCallback, pos+maxtextlen-1)
      pos = pos + maxtextlen
    end

    -- Final part
    chunk = strsub(text, pos)
    ctl:SendAddonMessage (prio, prefix, MSG_MULTI_LAST..chunk, dist, target, qname, ctlCallback, textlen)
  end
end

-- Message receiving
do -- start local block
  local compost = setmetatable({}, {__mode="k"})
  local function comnew()
    local t=next(compost)
    if (t) then
      compost[t]=nil
      for i=#t,3,-1 do
        t[i]=nil
      end
      return t
    end
    return {}
  end

  function com:OnReceiveMultipartFirst (prefix, msg, dist, snd)
    local sender = K.CanonicalName (snd, nil)
    local key = prefix.."\t"..dist.."\t"..sender
    local spool = com.mp_spool
    spool[key] = msg
  end

  function com:OnReceiveMultipartNext (prefix, msg, dist, snd)
    local sender = K.CanonicalName (snd, nil)
    local key = prefix.."\t"..dist.."\t"..sender
    local spool = com.mp_spool
    local olddata = spool[key]

    if (not olddata) then
      return
    end

    if (type (olddata) ~= "table") then
      local t = comnew ();
      t[1] = olddata
      t[2] = msg
      spool[key] = t
    else
      tinsert (olddata, msg)
    end
  end

  function com:OnReceiveMultipartLast(prefix, msg, dist, snd)
    local sender = K.CanonicalName (snd, nil)
    local key = prefix.."\t"..dist.."\t"..sender
    local spool = com.mp_spool
    local olddata = spool[key]

    if (not olddata) then
      return
    end

    spool[key] = nil

    if (type (olddata) == "table") then
      tinsert (olddata, msg)
      com.callbacks:Fire (prefix, tconcat(olddata, ""), dist, sender)
      compost[olddata]=true
    else
      com.callbacks:Fire (prefix, olddata..msg, dist, sender)
    end
  end
end -- local do block

if (not com.callbacks) then
  com.__prefixes = {}
  com.callbacks = K:NewCB(com, "_RegisterComm", "_UnregisterComm", "UnregisterAllComm")
end

local comOnEvent

com.callbacks.OnUsed = nil
com.callbacks.OnUnused = nil

local function comOnEvent (this, event, ...)
  if (event == "CHAT_MSG_ADDON") then
    local prefix, msg, dist, snd = ...
    if (not com.ourprefixes[prefix]) then
      return
    end
    local sender = K.CanonicalName (snd, nil)
    local control, rest = match (msg, "^([\001-\009])(.*)")

    if (control) then
      if (control == MSG_MULTI_FIRST) then
        com:OnReceiveMultipartFirst (prefix, rest, dist, sender)
      elseif (control == MSG_MULTI_NEXT) then
        com:OnReceiveMultipartNext (prefix, rest, dist, sender)
      elseif (control == MSG_MULTI_LAST) then
        com:OnReceiveMultipartLast (prefix, rest, dist, sender)
      elseif (control == MSG_ESCAPE) then
        com.callbacks:Fire (prefix, rest, dist, sender)
      end
    else
      com.callbacks:Fire (prefix, msg, dist, sender)
    end
  end
end

com.frame = com.frame or CreateFrame("Frame", "KKoreComm")
com.frame:SetScript("OnEvent", comOnEvent)
com.frame:UnregisterAllEvents()
com.frame:RegisterEvent("CHAT_MSG_ADDON")

--
-- Utility function: return a number of nil values, followed by any number
-- of other values.
--
function K.nilret(num, ...)
  if (num > 1) then
    return nil, K.nilret(num-1, ...)
  elseif (num == 1) then
    return nil, ...
  else
    return ...
  end
end

--
-- Utility function: get one or more arguments from a string
--
function K.GetArgs(arg, argc, spos)
  argc = argc or 1
  spos = max (spos or 1, 1)

  local pos = spos
  pos = strfind (arg, "[^ ]", pos)
  if (not pos) then
    -- End of string before we got an argument
    return K.nilret (argc, 1e9)
  end

  if (argc < 1) then
    return pos
  end

  local delim_or_pipe
  local ch = strsub (arg, pos, pos)
  if (ch == '"') then
    pos = pos + 1
    delim_or_pipe='([|"])'
  elseif (ch == "'") then
    pos = pos + 1
    delim_or_pipe="([|'])"
  else
    delim_or_pipe="([| ])"
  end

  spos = pos
  while true do
    -- Find delimiter or hyperlink
    local ch,_
    pos,_,ch = strfind (arg, delim_or_pipe, pos)

    if (not pos) then
      break
    end

    if (ch == "|") then
      -- Some kind of escape

      if (strsub (arg, pos, pos + 1) == "|H") then
        -- It's a |H....|hhyper link!|h
        pos = strfind (arg, "|h", pos + 2)       -- first |h
        if (not pos) then
          break
        end

        pos = strfind (arg, "|h", pos + 2)       -- second |h
        if (not pos) then
          break
        end
      elseif (strsub (arg,pos, pos + 1) == "|T") then
        -- It's a |T....|t  texture
        pos=strfind (arg, "|t", pos + 2)
        if (not pos) then
          break
        end
      end

      pos = pos + 2 -- Skip past this escape (last |h if it was a hyperlink)
    else
      -- Found delimiter, done with this arg
      return strsub (arg, spos, pos - 1), K.GetArgs (arg, argc - 1, pos + 1)
    end
  end

  -- Search aborted, we hit end of string. return it all as one argument.
  return strsub (arg, spos), K.nilret (argc - 1, 1e9)
end

--
-- The rest of this file was writting by James Kean Johnston (Cruciformer) and
-- is subject to the KahLua Kore license, which is the Apache license, Version
-- 2.0. Please see LICENSE.txt for details.
-- (C) Copyright 2008-2018 James Kean Johnston. All rights reserved.
--

--
-- Deal with KahLua Kore slash commands. Each KahLua module can have its
-- commands accessed either by typing /kahlua NAME, or any number of
-- additional extra arguments. /kNAME is always created too. So for
-- example, if you register a module called "konfer", you can get to its
-- main argument handling function via "/kahlua konfer" or "/kkonfer" by
-- default. You can also chose to register any number of additional
-- entry points.
--
-- Each argument after the name and the primary function is either a
-- string or a table. If its a string, it is a simple entry into the
-- main argument processing array. If it is a table, the table must have
-- two members: name and func. name is the name of the command and func
-- is a reference to the function that will deal with that alias.
--

local function listall()
  local k,v
  for k,v in pairs(K.slashtable) do
    K.printf (K.ucolor, "    |cffffff00%s|r - %s [r%s]", k, v.desc, v.version)
  end
end

local function kahlua_usage()
  local L = K:GetI18NTable(KKORE_MAJOR, false)
  K.printf (K.ucolor, "|cffff2222<%s>|r %s - %s", K.KAHLUA,
    strfmt(L["KAHLUA_VER"], KKORE_MINOR), L["KAHLUA_DESC"])
  K.printf (K.ucolor, L["Usage: %s/%s module [arg [arg...]]%s"],
    "|cffffffff", L["CMD_KAHLUA"], "|r")
  K.printf (K.ucolor, L["    Where module is one of the following modules:"])
  listall()
  K.printf (K.ucolor, L["For help with any module, type %s/%s module %s%s."], "|cffffffff", L["CMD_KAHLUA"], L["CMD_HELP"], "|r")
end

local function kahlua(input)
  if (not input or input == "" or input:lower() == "help") then
    kahlua_usage()
    return
  end

  local L = K:GetI18NTable(KKORE_MAJOR, false)

  if (input:lower() == L["CMD_VERSION"] or input:lower() == "version" or input:lower() == "ver") then
    K.printf (K.ucolor, "|cffff2222<%s>|r %s - %s", K.KAHLUA,
      strfmt(L["KAHLUA_VER"], KKORE_MINOR), L["KAHLUA_DESC"])
    K.printf (K.ucolor, "(C) Copyright 2008-2009 J. Kean Johnston (Cruciformer). All rights reserved.")
    K.printf (K.ucolor, L["KKore extensions loaded:"])
    for k,v in pairs (K.extensions) do
      K.printf (K.ucolor, "    |cffffff00%s|r %s", k, strfmt(L["KAHLUA_VER"], v.version))
    end
    K.printf (K.ucolor, "This is open source software, distributed under the terms of the Apache license. For the latest version, other KahLua modules and discussion forums, visit |cffffffffhttp://www.kahluamod.com|r.")
    return
  end

  if (input:lower() == L["CMD_LIST"]) then
    K.printf (K.ucolor,L["The following modules are available:"])
    listall()
    return
  end

  local cmd, pos = K.GetArgs (input)
  if (not cmd or cmd == "") then
    kahlua_usage()
    return
  end
  if (pos == 1e9) then
    kahlua_usage()
    return
  end
  strlower(cmd)

  if (not K.slashtable[cmd]) then
    K.printf (K.ecolor, L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."], cmd, "|cffffffff", L["CMD_KAHLUA"], L["CMD_LIST"], "|r")
    return
  end

  local arg
  if (pos == 1e9) then
    arg = ""
  else
    arg = strsub(input, pos)
  end

  K.slashtable[cmd].fn (arg)
end

local function kcmdfunc(input)
  local L = K:GetI18NTable(KKORE_MAJOR, false)
  if (not input or input:lower() == L["CMD_HELP"] or input == "?" or input == "") then
    K.printf (K.ucolor,L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"], "|cffffffff", L["CMD_KKORE"], "|r")
    K.printf (K.ucolor,L["%s/%s %s module level%s"], "|cffffffff", L["CMD_KKORE"], L["CMD_DEBUG"], "|r")
    K.printf (K.ucolor,L["  Sets the debug level for a module. 0 disables."])
    K.printf (K.ucolor,L["  The higher the number the more verbose the output."])
    K.printf (K.ucolor,"%s/%s %s%s", "|cffffffff", L["CMD_KKORE"], L["CMD_LIST"], "|r")
    K.printf (K.ucolor,L["  Lists all modules registered with KahLua."])
    return
  end

  if (input:lower() == L["CMD_LIST"] or input:lower() == "list") then
    K.printf (K.ucolor,L["The following modules are available:"])
    listall()
    return
  end

  local cmd, pos = K.GetArgs (input)
  if (not cmd or cmd == "") then
    kcmdfunc()
    return
  end
  strlower(cmd)

  if (cmd == L["CMD_DEBUG"] or cmd == "debug") then
    local md, lvl, npos = K.GetArgs(input, 2, pos)
    if (not md or not lvl or npos ~= 1e9) then
      kcmdfunc()
      return
    end
    lvl = tonumber(lvl)

    if (not K.slashtable[md]) then
      K.printf (K.ecolor, L["Cannot enable debugging for '%s' - no such module."],
        md)
      return
    end

    if (lvl < 0 or lvl > 10) then
      K.printf (K.ecolor, L["Debug level %d out of bounds - must be between 0 and 10."], lvl)
    end

    K.debugging[md] = lvl
    return
  elseif (cmd == "ginit") then
    update_player_and_guild()
  elseif (cmd == "status") then
    local rs = strfmt ("player=%s faction=%s class=%s level=%s guilded=%s", tostring(K.player.name), tostring(K.player.faction), tostring(K.player.class), tostring(K.player.level), tostring(K.player.is_guilded))
    if (K.player.is_guilded) then
      rs = rs.. strfmt (" guild=%q isgm=%s rankidx=%s numranks=%s", tostring(K.player.guild), tostring(K.player.is_gm), tostring(K.player.guildrankidx), tostring(K.guild.numranks))
    end

    K.printf ("%s", rs);
    if (K.player.is_guilded) then
      local i
      for i = 1, K.guild.numranks do
        K.printf ("Rank %d: name=%q", i, tostring(K.guild.ranks[i]))
      end
    end
  end
end

local function RegisterSlashCommand(name, func, desc, version, ...)
  local L = K:GetI18NTable(KKORE_MAJOR, false)
  if (not L) then
    error ("KahLua Kore: I18N initialization did not complete.", 2)
  end

  strlower(name)

  if (not K.slashtable) then
    K.slashtable = {}
    K.slashtable["kore"] = { fn = kcmdfunc,
      desc = strfmt(L["KORE_DESC"], K.KAHLUA),
      version = KKORE_MINOR }
    K.slashtable["kore"].alts = {}
    K.slashtable["kore"].alts["kkore"] = kcmdfunc
  end

  K.slashtable[name] = K.slashtable[name] or {}
  local st = K.slashtable[name]
  local kname = "k" .. name

  st.fn = func
  st.desc = desc
  st.version = version
  st.alts = st.alts or {}
  st.alts[kname] = func

  for i = 1, select("#", ...) do
    local aname = select(i, ...)
    if (type(aname) == "string") then
      st.alts[strlower(aname)] = func
    elseif (type(aname) == "table") then
      st.alts[strlower(aname.name)] = aname.func
    else
      error ("KKore:NewAddon: invalid alternate name.", 2)
    end
  end

  --
  -- Register all of the slash command each time a new one is added.
  -- No real penalty to doing so, as it will just re-register the same
  -- old commands on additional calls to the function.
  --
  SlashCmdList["KAHLUA"] = kahlua
  _G["SLASH_KAHLUA1"] = "/kahlua"

  for k,v in pairs(K.slashtable) do
    local c, sn, ds

    c = 1
    sn = "KAHLUA_" .. k:upper()
    SlashCmdList[sn] = v.fn
    ds = "SLASH_" .. sn .. tostring(c)
    _G[ds] = "/" .. k

    for kk,vv in pairs(v.alts) do
      if (vv == v.fn) then
        c = c + 1
        ds = "SLASH_" .. sn .. tostring(c)
        _G[ds] = "/" .. kk:lower()
      else
        asn = sn .. "_" .. kk:upper()
        SlashCmdList[asn] = vv
        ds = "SLASH_" .. asn .. "1"
        _G[ds] = "/" .. kk
      end
    end
  end
end

--
-- Now for a few standard events that we capture and process so that all addons
-- interested in them can simply register for the message. We want to keep
-- track of some of this stuff for our own internal purposes.
--
local function guild_update (evt, arg1)
  if (evt == "PLAYER_GUILD_UPDATE") then
    update_player_and_guild ()
    return
  end

  if (evt == "GUILD_ROSTER_UPDATE") then
    if (arg1) then
      GuildRoster()
      return
    end

    update_player_and_guild ()
    return
  end
end

local hasraidinfo

local function instance_update (evt, ...)
  if (not hasraidinfo) then
    hasraidinfo = 1
    return
  end
  K.raids = {}
  K.raids.numraids = GetNumSavedInstances ()
  K.raids.info = {}
  if (K.raids.numraids > 0) then
    local i
    for i = 1, K.raids.numraids do
      local iname, iid, ireset, ilevel = GetSavedInstanceInfo (i)
      local ti = { zone = iname, raidid = iid, level = ilevel }
      tinsert (K.raids.info, ti)
    end
    K:SendMessage ("RAID_LIST_UPDATED")
  end
end

KP:RegisterEvent ("PLAYER_GUILD_UPDATE", guild_update)
KP:RegisterEvent ("GUILD_ROSTER_UPDATE", guild_update)
KP:RegisterEvent ("UPDATE_INSTANCE_INFO", instance_update)

--
-- Deal with Kore addon initialisation. We maintain a table of all Kore
-- addons, each of which announces itself to Kore by calling KKore:NewAddon(), 
-- defined below. Each addon calls this very early on in its life in order
-- to create the addon object. That call also embeds various Kore functions
-- into the returned object. It also sets up the slash command handler for
-- the modules and arranges to call the module's argument processing
-- function (addon.ProcessSlashCommand). We also arrange for the addon's
-- initialization functions to be called at the appropriate time. An addon
-- can have four initialisation functions: OnEarlyInit, which is called when
-- ADDON_LOADED fires, OnLoginInit() which is called when PLAYER_LOGIN is
-- fired and IsLoggedIn() returns true, OnEnteringWorld() which is called
-- when PLAYER_ENTERING_WORLD fires, which can happen more than once, and
-- OnLateInit(), which is called after all addons and FrameXML code has
-- loaded. Only OnEnteringWorld() is ever called more than once.
--
K.addons = K.addons or {}
K.earlyq = K.earlyq or {}
K.loginq = K.loginq or {}
K.pewq = K.pewq or {}
K.lateq = K.lateq or {}

local function addon_tostring (self)
  return self.kore_name
end

--
-- object  - existing object to embed Kore into or nil to create a new one
-- name    - the name of the addon, usually CamelCased
-- ver     - the version of the addon
-- desc    - brief description of the addon
-- cmdname - the primary command name for accessing the addon
-- ...     - additional alternate commands for accessing the addon
function K:NewAddon (obj, name, ver, desc, cmdname, ...)
  assert (obj == nil or type(obj) == "table", "KKore: first argument must be nil or an object table.")
  assert (name, "KKore: addon name must be provided.")
  assert (ver, "KKore: addon version must be provided.")
  assert (desc, "KKore: addon description must be provided.")

  if (self.addons[name]) then
    error (("KKore: addon %q already exists."):format (name), 2)
  end

  local obj = obj or {}
  obj.kore_name = name
  obj.kore_desc = desc
  obj.kore_ver = ver
  obj.kore_minor = KKORE_MINOR

  local addonmeta = {}
  local oldmeta = getmetatable (obj)
  if (oldmeta) then
    for k,v in pairs (oldmeta) do
      addonmeta[k] = v
    end
  end
  addonmeta.__tostring = addon_tostring
  setmetatable (obj, addonmeta)

  self.addons[name] = obj

  --
  -- Each object gets a Kore-specific frame that we use for timers and other
  -- such things. Create that frame now.
  --
  obj.kore_frame = obj.kore_frame or CreateFrame ("Frame", name .. "KoreFrame")
  obj.kore_frame:UnregisterAllEvents ()

  obj.kore_callbacks = K:NewCB (obj, "RegisterIPC", "UnregisterIPC", "UnregisterAllIPCs")
  obj.SendIPC = obj.kore_callbacks.Fire

  --
  -- Embed all of the Kore functions into the addon. JKJ FIXME: must update
  -- this list whenever new Kore functions are added.
  --
  obj.SendChatMessage = K.SendChatMessage
  obj.SendAddonMessage = K.SendAddonMessage
  obj.ScheduleTimer = K.ScheduleTimer
  obj.ScheduleRepeating = K.ScheduleRepeating
  obj.CancelTimer = K.CancelTimer
  obj.CancelAllTimers = K.CancelAllTimers
  obj.TimeLeft = K.TimeLeft
  obj.SendCommMessage = K.comm.SendCommMessage
  for k,v in pairs (evtembeds) do
    obj[v] = K[v]
  end

  RegisterSlashCommand (cmdname, function (...)
    safecall (obj.OnSlashCommand, obj, ...)
  end, desc, ver, ...)

  tinsert (self.earlyq, obj)
  tinsert (self.pewq, obj)

  if (kore_ready == 2) then
    safecall (obj.OnLateInit, obj)
    obj.SendIPC ("KORE_READY")
  else
    tinsert (self.lateq, obj)
  end

  return obj
end

function K:GetAddon (name, opt)
  if (not opt and not self.addons[name]) then
    error (("KKore:GetAddon: cannot find addon %q"):format (tostring(name)), 2)
  end
  return self.addons[name]
end

local function addonOnEvent (this, event, arg1)
  if (event == "PLAYER_LOGIN") then
    while (#K.earlyq > 0) do
      get_static_player_info()
      local addon = tremove(K.earlyq, 1)
      safecall (addon.OnEarlyInit, addon)
      tinsert(K.loginq, addon)
    end

    if (IsLoggedIn()) then
      get_static_player_info()
      while (#K.loginq> 0) do
        local addon = tremove(K.loginq, 1)
        safecall (addon.OnLoginInit, addon)
      end
    end
    return
  elseif (event == "PLAYER_ENTERING_WORLD") then
    get_static_player_info()
    for i = 1, #K.pewq do
      local addon = K.pewq[i]
      safecall (addon.OnEnteringWorld, addon)
    end
  end
end

local function addonOnUpdate (this, event)
  this:SetScript ("OnUpdate", nil)
  update_player_and_guild ()
  if (kore_ready == 1) then
    kore_ready = 2
    -- For each extension or addon that is using us let them know that basic
    -- Kore functionality is ready. If a module joins late, after this code
    -- has been run, then the code that deals with adding the extension will
    -- send the event.
    for k, v in pairs (K.extensions) do
      safecall (v.library.OnLateInit, v.library)
      v.library.SendIPC (v.library, "KORE_READY")
    end
    while (#K.lateq > 0) do
      local addon = tremove (K.lateq, 1)
      safecall (addon.OnLateInit, addon)
    end
  end
end

K.addonframe = K.addonframe or CreateFrame ("Frame", "KKoreAddonFrame")
K.addonframe:UnregisterAllEvents ()
K.addonframe:RegisterEvent ("PLAYER_LOGIN")
K.addonframe:RegisterEvent ("PLAYER_ENTERING_WORLD")
K.addonframe:SetScript ("OnEvent", addonOnEvent)
K.addonframe:SetScript ("OnUpdate", addonOnUpdate)

K.addons = {}

local addonembeds = {
  "DoCallbacks", "RegisterAddon", "SuspendAddon", "ResumeAddon",
  "ActivateAddon", "GetAddon", "AddonCallback", "GetPrivate"
}

function K.DoCallbacks (self, name, ...)
  for k, v in pairs (self.addons) do
    if (type (v) == "table" and type (v.callbacks) == "table") then
      if (v.active) then
        -- All callbacks are called with the same first 3 arguments:
        -- 1. The name of the addon.
        -- 2. The name of the callback.
        -- 3. The addon private data table.
        -- Only active addons have their callbacks called.
        safecall (v.callbacks[name], k, name, v.private, ...)
      end
    end
  end
end

--
-- Function: K:RegisterAddon (name)
-- Purpose : Called by an addon to register with an ext. This creates both a
--           private config space for the addon, as well a place to store
--           any callback functions.
-- Fires   : NEW_ADDON (name)
--           ACTIVATE_ADDON (name)
-- Returns : true if the addon was added and the events fired, false if not.
--
function K.RegisterAddon (self, nm)
  if (not nm or type(nm) ~= "string" or nm == "" or self.addons[nm]) then
    return false
  end

  local newadd = {}

  -- New addons start out in the inactive state.
  newadd.active = false

  -- Private addon config space
  newadd.private = {}

  -- List of callbacks
  newadd.callbacks = {}

  self.addons[nm] = newadd

  self:SendMessage ("NEW_ADDON", nm)
  self:SendMessage ("SUSPEND_ADDON", nm)

  return true
end

--
-- Function: K:SuspendAddon (name)
-- Purpose : Called by an addon to suspend itself. When an addon is suspended
--           none of its callback functions will be called by Kore as it does
--           its work. However, if the addon has registered any event handlers
--           they will still be called.
-- Fires   : SUSPEND_ADDON (name)
-- Returns : true if the addon was suspended, false if it was either already
--           suspended or the addon name is invalid.
--
function K.SuspendAddon (self, name)
  if (not name or type (name) ~= "string" or name == "" or not self.addons[name]
      or type (self.addons[name]) ~= "table") then
    return false
  end

  if (self.addons[name].active) then
    self.addons[name].active = false
    self:SendMessage ("SUSPEND_ADDON", name)
    return true
  end

  return false
end

--
-- Function: K:ResumeAddon (name)
--           K:ActivateAddon (name)
-- Purpose : Called by an addon to resume itself.
-- Fires   : ACTIVATE_ADDON (name)
-- Returns : true if the addon was resumed, false if it was either already
--           active or the addon name is invalid.
--
function K.ResumeAddon (self, name)
  if (not name or type (name) ~= "string" or name == "" or not self.addons[name]
      or type (self.addons[name]) ~= "table") then
    return false
  end

  if (not self.addons[name].active) then
    self.addons[name].active = true
    self:SendMessage ("ACTIVATE_ADDON", name)
    return true
  end

  return false
end
K.ActivateAddon = K.ResumeAddon

--
-- Function: K:GetPrivate (name)
-- Purpose : Called by an addon to get its private config space.
-- Returns : The private config space for the named addon or nil if no such
--           addon exists.
--
function K.GetPrivate (self, name)
  if (not name or type (name) ~= "string" or name == "" or not self.addons[name]
      or type (self.addons[name]) ~= "table" or not self.addons[name].private
      or type (self.addons[name].private) ~= "table") then
    return nil
  end

  return self.addons[name].private
end

--
-- Function: K:AddonCallback (name, callback, handler)
-- Purpose : Called by an addon with the specified name to register a new
--           callback. The name of the callback must be a string and only
--           a defined set of callback names will ever be called by Kore.
--           The callback arg can be nil to remove a callback. Each addon
--           can only register a single handler function for each given
--           callback.
-- Returns : True if the callback was registered and valid, false otherwise.
--
function K.AddonCallback (self, name, callback, handler)
  if (not name or type (name) ~= "string" or name == ""
      or not self.addons[name] or type (self.addons[name]) ~= "table"
      or not self.addons[name].callbacks
      or type (self.addons[name].callbacks) ~= "table"
      or not callback or type (callback) ~= "string" or callback == "" 
      or not self.valid_callbacks[callback]) then
    return false
  end

  if (handler and type (handler) ~= "function") then
    return false
  end

  self.addons[name].callbacks[callback] = handler

  return true
end

for k,v in pairs (addonembeds) do
  KP[v] = K[v]
end

--
-- This is for extensions to KKore itself, such as KKoreParty or KKoreLoot.
-- Those extensions register with the Kore via this function. Addons that
-- use either the Kore or its extensions can register themselves with the
-- component(s) they need, which they do using the various Addon functions
-- above, each of which is added to the list of elements in the extension.
-- So for example, an addon that wants to use both KKoreParty (KRP) and
-- KKoreLoot (KLD) would call: KRP:RegisterAddon() and KLD:RegisterAddon.
--
function K:RegisterExtension (kext, major, minor)
  local ext = {}
  ext.version = minor
  ext.library = kext
  self.extensions[major] = ext
  kext.version = minor

  for k,v in pairs (evtembeds) do
    kext[v] = KP[v]
  end

  for k,v in pairs (addonembeds) do
    kext[v] = KP[v]
  end

  kext.kore_callbacks = K:NewCB (kext, "RegisterIPC", "UnregisterIPC", "UnregisterAllIPCs")
  kext.SendIPC = kext.kore_callbacks.Fire

  if (kore_ready == 2) then
    safecall (kext.OnLateInit, kext)
    kext.SendIPC ("KORE_READY")
  end
end

--
-- This isn't really useful to any mod that doesn't every have to deal with
-- items or loot, but it's a small table and a lot of mods do deal with items
-- so this is now a part of Kore (as of release 732).
--
-- One of the things we need to know when looting items is the armour class
-- of an item. This info is returned by GetItemInfo() but the strings are
-- localised. So we need to set up a translation table from that localised
-- string to some constant that has generic meaning to us (and is locale
-- agnostic). Set up that table now. Please note that this relies heavily
-- on the fact that some of these functions return values in the same
-- order for a given UI release. If this proves to be inacurate, this whole
-- strategy will need to be re-thought.
--
K.classfilters = {}
K.classfilters.weapon = LE_ITEM_CLASS_WEAPON   -- 2
K.classfilters.armor  = LE_ITEM_CLASS_ARMOR    -- 4

local ohaxe    = LE_ITEM_WEAPON_AXE1H            -- 0
local thaxe    = LE_ITEM_WEAPON_AXE2H            -- 1
local bows     = LE_ITEM_WEAPON_BOWS             -- 2
local guns     = LE_ITEM_WEAPON_GUNS             -- 3
local ohmace   = LE_ITEM_WEAPON_MACE1H           -- 4
local thmace   = LE_ITEM_WEAPON_MACE2H           -- 5
local poles    = LE_ITEM_WEAPON_POLEARM          -- 6
local ohsword  = LE_ITEM_WEAPON_SWORD1H          -- 7
local thsword  = LE_ITEM_WEAPON_SWORD2H          -- 8
local staves   = LE_ITEM_WEAPON_STAFF            -- 10
local fist     = LE_ITEM_WEAPON_UNARMED          -- 13
local miscw    = LE_ITEM_WEAPON_GENERIC          -- 14
local daggers  = LE_ITEM_WEAPON_DAGGER           -- 15
local thrown   = LE_ITEM_WEAPON_THROWN           -- 16
local xbows    = LE_ITEM_WEAPON_CROSSBOW         -- 18
local wands    = LE_ITEM_WEAPON_WAND             -- 19
local fish     = LE_ITEM_WEAPON_FISHINGPOLE      -- 20

local amisc    = LE_ITEM_ARMOR_GENERIC           -- 0
local cloth    = LE_ITEM_ARMOR_CLOTH             -- 1
local leather  = LE_ITEM_ARMOR_LEATHER           -- 2
local mail     = LE_ITEM_ARMOR_MAIL              -- 3
local plate    = LE_ITEM_ARMOR_PLATE             -- 4
local cosmetic = LE_ITEM_ARMOR_COSMETIC          -- 5
local shields  = LE_ITEM_ARMOR_SHIELD            -- 6
local libram   = LE_ITEM_ARMOR_LIBRAM            -- 7
local idols    = LE_ITEM_ARMOR_IDOL              -- 8
local totems   = LE_ITEM_ARMOR_TOTEM             -- 9

K.classfilters.strict = {}
K.classfilters.relaxed = {}
K.classfilters.weapons = {}
--                                 +------------- Warriors            1
--                                 |+------------ Paladins            2
--                                 ||+----------- Hunters             3
--                                 |||+---------- Rogues              4
--                                 ||||+--------- Priests             5
--                                 |||||+-------- Unused              6
--                                 ||||||+------- Shaman              7
--                                 |||||||+------ Mages               8
--                                 ||||||||+----- Warlocks            9
--                                 |||||||||+---- unused              10
--                                 ||||||||||+--- Druids              11
--                                 |||||||||||
K.classfilters.strict[amisc]    = "11111111111"
K.classfilters.strict[cloth]    = "00001001100"
K.classfilters.strict[leather]  = "00010000001"
K.classfilters.strict[mail]     = "00100010000"
K.classfilters.strict[plate]    = "11000000000"
K.classfilters.strict[cosmetic] = "11111111111"
K.classfilters.strict[shields]  = "11000010000"
K.classfilters.strict[libram]   = "01000000000"
K.classfilters.strict[idols]    = "00000000001"
K.classfilters.strict[totems]   = "00000010000"
K.classfilters.relaxed[amisc]   = "11111111111"
K.classfilters.relaxed[cloth]   = "11111111111"
K.classfilters.relaxed[leather] = "11110010001"
K.classfilters.relaxed[mail]    = "11100010000"
K.classfilters.relaxed[plate]   = "11000000000"
K.classfilters.relaxed[cosmetic]= "11111111111"
K.classfilters.relaxed[shields] = "11000010000"
K.classfilters.relaxed[libram]  = "01000000000"
K.classfilters.relaxed[idols]   = "00000000001"
K.classfilters.relaxed[totems]  = "00000010000"
K.classfilters.weapons[ohaxe]   = "11110010000"
K.classfilters.weapons[thaxe]   = "11100010000"
K.classfilters.weapons[bows]    = "10110000000"
K.classfilters.weapons[guns]    = "10110000000"
K.classfilters.weapons[ohmace]  = "11011010001"
K.classfilters.weapons[thmace]  = "11000010001"
K.classfilters.weapons[poles]   = "11100000001"
K.classfilters.weapons[ohsword] = "11110001100"
K.classfilters.weapons[thsword] = "11100000000"
K.classfilters.weapons[staves]  = "10101011101"
K.classfilters.weapons[fist]    = "10110010001"
K.classfilters.weapons[miscw]   = "11111111111"
K.classfilters.weapons[daggers] = "10111011101"
K.classfilters.weapons[thrown]  = "10110000000"
K.classfilters.weapons[xbows]   = "10110000000"
K.classfilters.weapons[wands]   = "00001001100"
K.classfilters.weapons[fish]    = "11111111111"
K.classfilters.allclasses       = "11111111111"

--
-- This function will take a given itemlink and examine its tooltip looking
-- for class restrictions. It will return a class filter mask suitable for
-- use in a loot system. If no class restriction was found, return the
-- all-inclusive mask.
--
function K.GetItemClassFilter (ilink)
  local tnm = GetItemInfo (ilink)
  if (not tnm or tnm == "") then
    return K.classfilters.allclasses, nil
  end

  local tt = K.ScanTooltip (ilink)
  local ss = strfmt (ITEM_CLASSES_ALLOWED, "(.-)\n")
  local foo = string.match (tt, ss)
  local boe = nil
  if (string.match (tt, ITEM_BIND_ON_PICKUP)) then
    boe = false
  elseif (string.match (tt, ITEM_BIND_ON_EQUIP)) then
    boe = true
  end

  if (foo) then
    foo = gsub (foo, " ", "")
    local clist = { "0","0","0","0","0","0","0","0","0","0","0", "0" }
    for k,v in pairs ( { string.split (",", foo) } ) do
      local cp = tonumber (K.LClassIndexNSP[v]) or 10
      clist[cp] = "1"
    end
    return tconcat (clist, ""), boe
  else
    return K.classfilters.allclasses, boe
  end
end

--
-- This portion of this file (through to the end) was not written by me.
-- It was a link given to me by Adys on #wowuidev@irc.freenode.net. Many
-- thanks for this code. It has been modified to suit Kore so any bugs are
-- mine.
--

--[[
Copyright (c) Jerome Leclanche. All rights reserved.


Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, 
       this list of conditions and the following disclaimer.
    
    2. Redistributions in binary form must reproduce the above copyright 
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.


THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]

local kkorett = CreateFrame ("GameTooltip", "KKoreUTooltip", UIParent,
  "GameTooltipTemplate")
kkorett:SetOwner (UIParent, "ANCHOR_PRESERVE")
kkorett:SetPoint ("CENTER", "UIParent")
kkorett:Hide ()

local function SetTooltipHack (link)
  kkorett:SetOwner (UIParent, "ANCHOR_PRESERVE")
  kkorett:SetHyperlink ("spell:1")
  kkorett:Show ()
  kkorett:SetHyperlink (link)
end

local function UnsetTooltipHack ()
  kkorett:SetOwner (UIParent, "ANCHOR_PRESERVE")
  kkorett:Hide ()
end

function K.ScanTooltip (link)
  SetTooltipHack (link)

  local lines = kkorett:NumLines ()
  local tooltiptxt = ""

  for i = 1, lines do
    local left = _G["KKoreUTooltipTextLeft"..i]:GetText ()
    local right = _G["KKoreUTooltipTextRight"..i]:GetText ()

    if (left) then
      tooltiptxt = tooltiptxt .. left
      if (right) then
        tooltiptxt = tooltiptxt .. "\t" .. right .. "\n"
      else
        tooltiptxt = tooltiptxt .. "\n"
      end
    elseif (right) then
      tooltiptxt = tooltiptxt .. right .. "\n"
    end
  end

  UnsetTooltipHack ()
  return tooltiptxt
end

--[[ NOT CURRENTLY USED
function K.GetTooltipLine (link, line, side)
  side = side or "Left"
  SetTooltipHack (link)

  local lines = kkorett:NumLines ()
  if (line > lines) then
    return UnsetTooltipHack()
  end

  local text = _G["KSKUTooltipText"..side..line]:GetText ()
  UnsetTooltipHack ()
  return text
end

function K.GetTooltipLines (link, ...)
  local lines = {}
  SetTooltipHack (link)
        
  for k,v in pairs({...}) do
    lines[#lines+1] = _G["KSKUTooltipTextLeft"..v]:GetText()
  end

  UnsetTooltipHack ()
  return unpack (lines)
end
]]

