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

local CallbackHandler = LibStub("CallbackHandler-1.0")
local DB = LibStub("AceDB-3.0")

local KORE_MAJOR = "Kore"
local KORE_MINOR = 1

--
-- The packaged build number, which is what a character info check reports and compares. It is not KORE_MINOR: that is the
-- LibStub minor, which says which copy of this library wins a load, and it is bumped by hand. This is set by the packager,
-- and the line after it is deleted in a packaged build, so an unpackaged tree reports 0. See K:RegisterMod.
--
local KORE_REVISION = tonumber("@revision@")
local KORE_REVISION = 0 -- @debug-delete@

local K = LibStub:NewLibrary(KORE_MAJOR, KORE_MINOR)

if (not K) then
  return
end

_G["Kore"] = K

--
-- The locale files carry nothing but strings and load before this one (see Kore.xml), so this reads like it does in every
-- other file and everything here can have a word at load time.
--
local L = LibStub("AceLocale-3.0"):GetLocale(KORE_MAJOR)

--
-- The handful of words used so widely that they are worth having on K rather than looked up at every call: the answer to a
-- dialog, and what a choice reads when it stands for no value at all. Those last are set off with dashes so that one can
-- never be taken for a real value of the same name, a character called Nobody for one.
--
K.OK_STR = L["OK_STR"]
K.CANCEL_STR = L["CANCEL_STR"]
K.ACCEPT_STR = L["ACCEPT_STR"]
K.CLOSE_STR = L["CLOSE_STR"]
K.OPEN_STR = L["OPEN_STR"]
K.HELP_STR = L["HELP_STR"]
K.YES_STR = L["YES_STR"]
K.NO_STR = L["NO_STR"]
K.NONE_STR = L["NONE_STR"]
K.NOTSET_STR = L["NOTSET_STR"]
K.NOBODY_STR = L["NOBODY_STR"]
K.NOTRATED_STR = L["NOTRATED_STR"]
K.KAHLUA = L["KAHLUA"]

-- What a tabbed dialog's save bar says, its button and the words under it, unless its caller says otherwise.
K.SAVEBAR_STR = L["SAVEBAR_STR"]
K.SAVEBAR_MSG = L["SAVEBAR_MSG"]

-- What a version of 0 is shown as. A development copy has no build number, so showing it the number would be a lie.
K.DEV_STR = L["DEV_STR"]

--
-- VERSION as it is written down, for any mod that shows one. The 0 a development copy carries is never displayed as a
-- number, so that every KahLua mod says the same thing about an unpackaged build rather than each inventing its own word.
--
function K.VersionString(version)
  version = tonumber(version) or 0

  if (version == 0) then
    return K.DEV_STR
  end

  return tostring(version)
end

--
-- Which game this is. One Kore runs on every client Blizzard ships, so what differs between them is decided here, once, before
-- anything else in Kore or in an addon built on it runs.
--
-- Blizzard gives every game a project id, WOW_PROJECT_ID, and these are its values under names of our own. Each is named after
-- the expansion that game plays rather than after a product, because the product called Classic has already been Wrath, then
-- Cataclysm, then Mists, while the game K.GAME_MISTS names never changes. The ids are Blizzard's and are neither ordered nor
-- contiguous, so they are only ever compared for equality. Retail defines only the first two itself, which is why each falls
-- back to Blizzard's number. A classic client's own FrameXML sets WOW_PROJECT_ID before any addon loads.
--
--   K.GAME        This client's project id, one of the K.GAME_ values.
--   K.RETAIL      True on retail, which Blizzard calls mainline.
--   K.CLASSIC     True on every other client.
--   K.EXPANSION   The expansion this client plays, as an LE_EXPANSION_ value counting up from 0 for the original game. This is
--                 the one to compare with >= to ask whether something has existed since a given expansion. A classic client
--                 answers through GetClassicExpansionLevel, and retail is always the current expansion.
--
-- Where clients differ in what they can do, code asks what this client can do rather than which client it is, so that it keeps
-- working when Blizzard gives a feature to one client or takes it from another. Those capabilities follow.
--
K.GAME_RETAIL  = WOW_PROJECT_MAINLINE or 1
K.GAME_VANILLA = WOW_PROJECT_CLASSIC or 2
K.GAME_TBC     = WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5
K.GAME_WRATH   = WOW_PROJECT_WRATH_CLASSIC or 11
K.GAME_CATA    = WOW_PROJECT_CATACLYSM_CLASSIC or 14
K.GAME_MISTS   = WOW_PROJECT_MISTS_CLASSIC or 19

K.GAME = WOW_PROJECT_ID
K.RETAIL = (K.GAME == K.GAME_RETAIL)
K.CLASSIC = not K.RETAIL

if (K.RETAIL) then
  K.EXPANSION = LE_EXPANSION_LEVEL_CURRENT
else
  K.EXPANSION = GetClassicExpansionLevel()
end

--
-- K.HAS_MASTER_LOOT is true where a group can be put on master loot, which is the game's own answer: which loot methods it
-- offers, asked as this file loads, before any group exists and whoever the player is grouped with. That is not the same
-- as which game this is. A client can call itself retail and still offer master loot, as the Classic built on retail's
-- client does. Nor is it whether the functions exist: GiveMasterLoot, GetMasterLootCandidate and
-- Enum.LootMethod.Masterlooter are all still there on retail, which offers only personal loot. Whether master loot is in
-- use right now is KoreParty's loot_method.
--
K.HAS_MASTER_LOOT = C_PartyInfo.IsLootMethodAvailable(Enum.LootMethod.Masterlooter) and true or false

--
-- K.HAS_TOOLTIP_DATA is true where the game's own tooltips are filled through the tooltip data system, so that anything added
-- to every item tooltip goes after the game's lines through TooltipDataProcessor.AddTooltipPostCall, and an item tooltip
-- says which item it shows through TooltipUtil.GetDisplayedItem. Elsewhere a tooltip says an item was set on it through its
-- OnTooltipSetItem script, and GetItem says which. Every client has TooltipDataProcessor, the classic ones included, but only
-- retail's tooltips are built on it, so its presence proves nothing: what is asked is whether GameTooltip carries the data
-- handler, which retail's does and no classic client's does.
--
K.HAS_TOOLTIP_DATA = (GameTooltip and GameTooltip.GetPrimaryTooltipData) and true or false

--
-- Whether EVENT is one this client has. Registering an event the client does not know raises an error, so an event from a later
-- expansion, or one retail has retired, is asked about here first. K:AceKore below does that for every object Kore embeds, so
-- RegisterEvent on Kore, on its extensions or on an addon built on it quietly skips an event this client lacks.
--
function K.EventExists(event)
  return C_EventUtils.IsEventValid(event)
end

--
-- Whether VALUE is one an addon may look at. Retail can hand an addon a secret in place of a real value, as it does with chat
-- text and with some unit information inside dungeons and raids and during encounters. Testing a secret, comparing it or doing
-- arithmetic with it raises an error, so a value that might be secret is asked about here before anything else is done with it.
-- The other clients have no secrets, and there everything is accessible.
--
local canaccessvalue = canaccessvalue

function K.CanAccess(value)
  if (not canaccessvalue) then
    return true
  end

  return canaccessvalue(value)
end

--
-- The name of spell SPELLID in the client's locale, or nil if the client has no such spell. Retail has retired the global
-- GetSpellInfo, and C_Spell.GetSpellName exists on every client.
--
function K.SpellName(spellid)
  return C_Spell.GetSpellName(spellid)
end

--
-- Kore is a superset of a bunch of Ace3 plugins. In the past we used to embed slightly tweaked versions of those plugins
-- directly in Kore. That turned out to be a maintenance mightmare. So now we use them the way they were intended, as
-- replaceable libraries. However, we still want Kore to provide the actual "API" that Kahlua mods can use, which means that
-- these select few basic Ace3 mods must be present in every Kahlua addon. This function centralises the location of that
-- list of Ace3 libraries and embeds them into the object passed as a parameter. This is called for Kore itself (so it too
-- has access to the same APIs) as well as each Kahlua mod when it registers with Kore.
--

function K:AceKore(obj)
  LibStub("AceEvent-3.0"):Embed(obj)
  LibStub("AceComm-3.0"):Embed(obj)
  LibStub("AceTimer-3.0"):Embed(obj)

  --
  -- An event this client does not have is skipped rather than handed to the client, which would raise an error, so one codebase
  -- can ask for the events of every client and receive on each only those that exist there.
  --
  local register = obj.RegisterEvent

  obj.RegisterEvent = function(self, event, ...)
    if (not K.EventExists(event)) then
      return
    end

    return register(self, event, ...)
  end
end

K:AceKore(K)

K.extensions = K.extensions or {}

-- Local aliases for global or Lua library functions
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tsort = table.sort
local tostring, tonumber = tostring, tonumber
local max, floor = math.max, math.floor
local ipairs = ipairs
local strfmt = string.format
local strsub = string.sub
local strfind = string.find
local strlower = string.lower
local strupper = string.upper
local strbyte = string.byte
local strchar = string.char
local gmatch = string.gmatch
local match = string.match
local gsub = string.gsub
local xpcall, pcall = xpcall, pcall
local pairs, type = pairs, type
local select, assert = select, assert
local band, rshift = bit.band, bit.rshift
local unpack, error = unpack, error

local k,v,i
local kore_ready = 0

--
-- Times are kept as seconds since the epoch, which is the same instant on every client whatever its time zone, and are
-- turned into a date only to be shown. The plain stamps below show UTC, which is what goes into anything exported, and the
-- Local ones show this client's own time. WHEN defaults to now in all of them.
--
function K.time()
  return time()
end

--
-- The decomposed local date of WHEN.
--
function K.date(when)
  return date("*t", when or time())
end

-- YYYY-MM-DD HH:MM:SS
function K.TimeStamp(when)
  return date("!%Y-%m-%d %H:%M:%S", when or time())
end

function K.LocalStamp(when)
  return date("%Y-%m-%d %H:%M:%S", when or time())
end

-- YYYY-MM-DD HH:MM
function K.TimeStampNS(when)
  return date("!%Y-%m-%d %H:%M", when or time())
end

function K.LocalStampNS(when)
  return date("%Y-%m-%d %H:%M", when or time())
end

-- YYYY-MM-DD
function K.YMDStamp(when)
  return date("!%Y-%m-%d", when or time())
end

function K.LocalYMD(when)
  return date("%Y-%m-%d", when or time())
end

-- HH:MM
function K.HMStamp(when)
  return date("!%H:%M", when or time())
end

function K.LocalHM(when)
  return date("%H:%M", when or time())
end

-- HH:MM:SS
function K.HMSStamp(when)
  return date("!%H:%M:%S", when or time())
end

function K.LocalHMS(when)
  return date("%H:%M:%S", when or time())
end

K.local_realm = K.local_realm or select(2, UnitFullName("player"))

--
-- Capitalise the first character in a users name. Many thanks to Arrowmaster in #wowuidev on irc.freenode.net for the pattern below.
--
function K.CapitaliseName(name)
  assert(name)
  return gsub(strlower(name), "^([\192-\255]?%a?[\128-\191]*)", strupper, 1)
end
K.CapitalizeName = K.CapitaliseName

--
-- A character's name the way Kore stores and compares it, which is always Name-Realm, a character on this realm included.
--
-- Every name that reaches Kore from the game or from a user comes through here or through K.FullUnitName, so a character
-- has one spelling everywhere: in KRP.players, in the guild roster, as the sender of a message, and in anything an addon
-- keys by name. It is also always a valid whisper target.
--
-- A bare name is on REALM, or on this realm when no REALM is given, which is what the game means when it hands one over
-- without a realm. The character part is capitalised the way the game capitalises it. The realm is written the way the game
-- writes it, spaces removed, and a realm typed in any case that is this realm's name is spelled the way this realm is, so
-- "bob-nightslayer" typed into a box and "Bob-Nightslayer" off a raid roster are the same key. Another realm typed in the
-- wrong case is not corrected, there being nothing on this client to say how it is spelled.
--
-- Nil when there is no name, when the character part cannot be a character's name, or when no realm is known yet, which is
-- only ever true very early in a login. A character's name is 2 to 12 letters, any alphabet's, and a trailing "-" with no
-- realm after it is a bare name. So a name typed into a box that could never be a character comes back nil, which is how a
-- caller knows to refuse it.
--
function K.CanonicalName(name, realm)
  if (not name or name == "") then
    return nil
  end

  local nm, rn = match(name, "^([^%-]*)%-(.*)$")

  if (not nm) then
    nm = name
    rn = realm
  end

  nm = gsub(nm, " ", "")

  -- Every byte of a letter outside ASCII is 128 or more, and only the first byte of each is outside 128 to 191.
  if (not match(nm, "^[%a\128-\255]+$")) then
    return nil
  end

  local nchars = #gsub(nm, "[\128-\191]", "")

  if (nchars < 2 or nchars > 12) then
    return nil
  end

  K.local_realm = K.local_realm or select(2, UnitFullName("player"))

  if (not rn or rn == "") then
    rn = K.local_realm
  end

  if (not rn or rn == "") then
    return nil
  end

  rn = gsub(rn, " ", "")

  if (K.local_realm and strlower(rn) == strlower(K.local_realm)) then
    rn = K.local_realm
  end

  return K.CapitaliseName(nm) .. "-" .. rn
end

--
-- The canonical name of UNIT, which is a unit token such as "raid3", or the name of someone in the group. Nil for a unit
-- that does not exist or whose name the client does not have yet.
--
function K.FullUnitName(unit)
  if (not unit or type(unit) ~= "string" or unit == "") then
    return nil
  end

  local unit_name, unit_realm = UnitFullName(unit)

  if (not unit_name or unit_name == "" or unit_name == "Unknown") then
    return nil
  end

  return K.CanonicalName(unit_name, unit_realm)
end

--
-- A canonical name without its realm, whichever realm that is. For text going somewhere space is short and the realm can be taken as read.
--
function K.ShortName(name)
  return Ambiguate(name, "short")
end

--
-- A canonical name the way the game shows one, Ambiguate's "none": the realm left off for a character on this realm and kept
-- for anyone from another. This is how a name is put on screen, unless the realm is wanted whatever it is (K.FullName) or
-- never (K.ShortName). Anything that keys, compares or sends by name uses the canonical form.
--
-- Not "all", which on Anniversary keeps the realm on a character from this realm outside the guild, whatever the wiki says.
--
function K.DisplayName(name)
  return Ambiguate(name, "none")
end

--
-- A name on screen with its realm, this realm's included, for where which realm somebody is from is the point. A canonical
-- name already carries it, so this is that name.
--
function K.FullName(name)
  return K.CanonicalName(name) or name
end

--
-- Some versions of the WoW client have problems with strfmt("%08x", val) for any val > 2^31. This simple functions avoids
-- that.
--
function K.hexstr(val)
  local lowerbits = band(val, 0xffff)
  local higherbits = band(rshift(val, 16), 0xffff)
  return strfmt("%04x%04x", higherbits, lowerbits)
end

K.GC_GCHAT_LISTEN       = 1
K.GC_GCHAT_SPEAK        = 2
K.GC_OCHAT_LISTEN       = 3
K.GC_OCHAT_SPEAK        = 4
K.GC_PROMOTE            = 5
K.GC_DEMOTE             = 6
K.GC_INVITE             = 7
K.GC_REMOVE             = 8
K.GC_SET_MODT           = 9
K.GC_EDIT_PUBLIC_NOTE   = 10
K.GC_VIEW_OFFICER_NOTE  = 11
K.GC_EDIT_OFFICER_NOTE  = 12
K.GC_MODIFY_GUILD_INFO  = 13

K.player = K.player or {}
K.guild = K.guild or {}
K.guild.ranks = K.guild.ranks or {}
K.guild.flags = K.guild.flags or {}
K.guild.roster = K.guild.roster or {}
K.guild.roster.id = K.guild.roster.id or {}
K.guild.roster.name = K.guild.roster.name or {}
K.guild.gmname = nil
K.raids = K.raids or { numraids = 0, info = {} }

--
-- The player's own character is always among the people (Kore.Users), the one person nobody has to ask for, and K.player.kuid
-- is their KUID. That needs both the people's database, which comes at login, and the player's name, which is not always
-- known by then, so this is tried as each arrives and done by whichever comes second.
--
local function add_player_user()
  if (K.Users and K.Users.users and K.player.name and not K.player.kuid) then
    K.player.kuid = K.Users:Add(K.player.name, K.player.class)
  end
end

local done_pi_once = false
local function get_static_player_info()
  if (done_pi_once) then
    return true
  end

  K.local_realm = select(2, UnitFullName("player"))
  if (not K.local_realm or K.local_realm == "") then
    K.local_realm = nil
    return false
  end

  K.player.name = K.FullUnitName("player")
  if (not K.player.name) then
    return false
  end

  K.player.faction = UnitFactionGroup("player")
  K.player.class = K.ClassIndex[select(2, UnitClass("player"))]
  K.player.race = select(3, UnitRace("player"))
  done_pi_once = true
  kore_ready = kore_ready + 1
  add_player_user()
  return true
end

local function update_player_and_guild(nofire)
  if (not get_static_player_info()) then
    return
  end

  local fireevt = false

  K.player.level = UnitLevel("player")
  if (IsInGuild()) then
    local gname, _, rankidx = GetGuildInfo("player")
    if (not gname or gname == "") then
      return
    end
    if (not K.player.is_guilded) then
      fireevt = true
    end
    K.player.is_guilded = true

    if (K.player.guild and K.player.guild ~= gname) then
      fireevt = true
    end
    K.player.guild = gname

    if (K.player.guildrankidx and K.player.guildrankidx ~= (rankidx + 1)) then
      fireevt = true
    end
    K.player.guildrankidx = rankidx + 1

    if (IsGuildLeader()) then
      if (not K.player.is_gm) then
        fireevt = true
      end
      K.player.is_gm = true
    else
      if (K.player.is_gm) then
        fireevt = true
      end
      K.player.is_gm = false
    end
  else
    if (K.player.is_guilded) then
      fireevt = true
    end
    K.player.is_guilded = false
    K.player.guild = nil
    K.player.guildrankidx = 0
    K.player.is_gm = false
  end

  if (K.player.is_guilded) then
    local i

    K.guild.numranks = GuildControlGetNumRanks()
    K.guild.ranks = {}
    K.guild.flags = {}
    K.guild.numroster = GetNumGuildMembers()
    K.guild.roster = {}
    K.guild.roster.id = {}
    K.guild.roster.name = {}
    -- Found again below, so a guild master who has handed the guild on is not still taken for one.
    K.guild.gmname = nil

    for i = 1, K.guild.numranks do
      local rname = GuildControlGetRankName(i)
      local flags = C_GuildInfo.GuildControlGetRankFlags(i)
      tinsert(K.guild.ranks, rname)
      tinsert(K.guild.flags, flags)
    end

    for i = 1, K.guild.numroster do
      local nm, _, ri, lvl, _, _, _, _, ol, _, cl = GetGuildRosterInfo(i)
      nm = nm and K.CanonicalName(nm)
      --
      -- GetNumGuildMembers() counts the whole guild but GetGuildRosterInfo()
      -- indexes the filtered roster, so with "show offline" off everything
      -- past the online count is nil.
      --
      if (not nm) then
        K.guild.numroster = i - 1
        break
      end
      local iv = { name = nm, rank = ri + 1, level = lvl, class = K.ClassIndex[cl], online = ol and true or false }
      tinsert(K.guild.roster.id, iv)
      K.guild.roster.name[nm] = i
      if (ri == 0) then
        K.guild.gmname = nm
      end
    end
  else
    K.guild = {}
    K.guild.numranks = 0
    K.guild.ranks = {}
    K.guild.flags = {}
    K.guild.numroster = 0
    K.guild.roster = {}
    K.guild.roster.id = {}
    K.guild.roster.name = {}
    K.guild.gmname = nil
  end

  if (not nofire) then
    K:SendMessage("GUILD_INFO_UPDATED")
  end

  if (fireevt and not nofire) then
    K:SendMessage("PLAYER_INFO_UPDATED")
  end
end

function K.UpdatePlayerAndGuild(nofire)
  update_player_and_guild(nofire)
end

--
-- Returns true if the user is thought to be an officer or the GM, false if we can't tell or can determine otherwise.
--
function K.UserIsRanked(name)
  if (not K.player.is_guilded or not K.guild) then
    return false
  end

  if (name == K.guild.gmname) then
    return true
  end

  local rosterid = K.guild.roster.name[name]
  if (not rosterid) then
    return false
  end

  -- If they can read officer chat we assume they are an officer of some sort.
  local flags = K.guild.flags[K.guild.roster.id[rosterid].rank]
  return flags[K.GC_OCHAT_LISTEN]
end

--
-- Simple debugging mechanism.
--
K.debugging = K.debugging or {}
K.debugframe = nil
K.maxlevel = GetMaxLevelForPlayerExpansion()

K.debugging["kore"] = 9 -- @debug-delete@

function K.debug(addon, lvl, ...)
  if (not K.debugging[addon]) then
    K.debugging[addon] = 0
    K.debugging[addon] = 9 -- @debug-delete@
  end

  if (K.debugging[addon] < lvl) then
    return
  end

  local text = ":[:" .. addon .. ":]: " .. strfmt(...)
  local frame = K.debugframe or DEFAULT_CHAT_FRAME
  frame:AddMessage(text, K.dcolor.r, K.dcolor.g, K.dcolor.b)
end

--
-- Whether any addon is debugging at LVL or above, for a caller about to build something costly to say that only a debugging
-- addon would ever see. Kore's own code serves every addon and cannot tell whose level applies, so it asks about all of them.
--
function K.DebugWanted(lvl)
  for _, l in pairs(K.debugging) do
    if (l >= lvl) then
      return true
    end
  end

  return false
end

--
-- Values as a debugging line shows them: strings quoted, tables as { ... } with their array part first and then their other
-- keys in order, and nothing deeper than DESCRIBE_DEPTH or longer than DESCRIBE_ITEMS entries a table, so that a whole config
-- going past does not bury the chat frame.
--
K.DESCRIBE_DEPTH = 3
K.DESCRIBE_ITEMS = 16

local describe

--
-- A string that cannot be read is nearly always values a mod packed with Kore's own two libraries, serialised by
-- LibSerialize and encoded for the addon channel by LibDeflate, as Konfer packs an event's arguments. It is shown as those
-- values, between angle brackets, and anything that will not come apart that way as the number of bytes it is.
--
local function describe_packed(s, depth)
  local LD = LibStub("LibDeflate", true)
  local LSER = LibStub("LibSerialize", true)
  local decoded = LD and LD:DecodeForWoWAddonChannel(s)

  if (decoded and LSER) then
    local got = { pcall(LSER.Deserialize, LSER, decoded) }

    if (got[1] and got[2]) then
      local parts = {}

      for i = 3, #got do
        tinsert(parts, describe(got[i], depth))
      end

      return "<" .. tconcat(parts, ", ") .. ">"
    end
  end

  return strfmt("<%d bytes>", #s)
end

describe = function(v, depth)
  local t = type(v)

  if (t == "string") then
    -- Control characters, which text never has. Bytes above 127 are UTF-8, a name with an accent in it, and read fine.
    if (strfind(v, "[%z\1-\31\127]")) then
      return describe_packed(v, depth)
    end

    return strfmt("%q", v)
  elseif (t ~= "table") then
    return tostring(v)
  elseif (depth <= 0) then
    return "{...}"
  end

  local parts = {}
  local n = #v
  local shown = 0

  for i = 1, n do
    shown = shown + 1
    if (shown > K.DESCRIBE_ITEMS) then
      break
    end
    tinsert(parts, describe(v[i], depth - 1))
  end

  local keys = {}

  for k in pairs(v) do
    if (type(k) ~= "number" or k < 1 or k > n or k ~= floor(k)) then
      tinsert(keys, k)
    end
  end

  tsort(keys, function(a, b) return tostring(a) < tostring(b) end)

  for _, k in ipairs(keys) do
    shown = shown + 1
    if (shown > K.DESCRIBE_ITEMS) then
      break
    end
    tinsert(parts, tostring(k) .. "=" .. describe(v[k], depth - 1))
  end

  if (shown > K.DESCRIBE_ITEMS) then
    tinsert(parts, "...")
  end

  return "{" .. tconcat(parts, ", ") .. "}"
end

function K.Describe(...)
  local parts = {}

  for i = 1, select("#", ...) do
    parts[i] = describe((select(i, ...)), K.DESCRIBE_DEPTH)
  end

  return tconcat(parts, ", ")
end

local function debug(lvl,...)
  K.debug("kore", lvl, ...)
end

--
-- Standard colors for usage messages, error messages, info messages and debug output
--
K.ucolor = { r = 1.0, g = 0.5, b = 0.0 }
K.ecolor = { r = 1.0, g = 0.0, b = 0.0 }
K.icolor = { r = 0.0, g = 1.0, b = 1.0 }
K.dcolor = { r = 0.75, g = 0.5, b = 1.0 }

K.white = function (str)
  return "|cffffffff" .. str .. "|r"
end

K.red = function (str)
  return "|cffff0000" .. str .. "|r"
end

K.green = function (str)
  return "|cff00ff00" .. str .. "|r"
end

K.yellow = function (str)
  return "|cffffff00" .. str .. "|r"
end

K.cyan = function (str)
  return "|cff00ffff" .. str .. "|r"
end

--
-- TEXT, or DATA when there is no TEXT, as a link carrying KIND and DATA, for a string label with an onlink handler to catch
-- (see KUI:CreateStringLabel). It is WoW's own link escape, the one item links use, with KIND:DATA as the part a click
-- hands back, so KIND may not contain a colon although DATA may. On a client whose frames cannot carry links it is plain
-- white text instead, so that nothing looks clickable that is not.
--
function K.Link(kind, data, text)
  local shown = text or data

  if (not UIParent.SetHyperlinksEnabled) then
    return K.white(shown)
  end

  return "|cff71d5ff|H" .. kind .. ":" .. data .. "|h" .. shown .. "|h|r"
end

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

  frame:AddMessage(strfmt(select(i, ...)), r, g, b, id)
end

--
-- Here we set up a bunch of constants that are used frequently throughout various modules. Some of them require actual
-- computation, and its pointless having multiple modules do the same computations, so we set up the list of such constants
-- here. Modules can then either reference these directly (K.constant) or do a local constant = K.constant.
--
--K.NaNstring = tostring(0/0)
K.Infstring = tostring(math.huge)
K.NInfstring = tostring(-math.huge)

--
-- What Kore itself says to the player, signed so that a line in the chat frame says where it came from. Anything Kore owns
-- belongs to no mod in particular, so it signs with KahLua alone. A mod signs with KahLua and its own name after it, which
-- is what konfer.err and konfer.info do, so the suite reads as one thing however many of its parts are installed.
--
--
-- The plate at the top of a window. **The brackets hold what owns the window's owner, and the word after them holds the
-- owner itself**, then a dash and what this particular window is:
--
--   <KahLua> - Users                      Kore's own. The suite owns Kore, and there is no mod in the middle.
--   <KahLua> Konfer - Lists               a mod's. The suite owns the mod.
--   <Konfer> Suicide Kings - Roll lists   a policy's. The mod owns the policy.
--
-- So OWNER goes in the brackets and NAME after them, one level apart, and neither is written down here: a policy's window
-- says Konfer in its brackets and never KahLua, because what owns a policy is the mod it is part of.
--
-- The dash separates whose window this is from what the window is, which without it run together into one phrase that reads
-- as neither. WHAT is nil for a window naming nothing but its owner, and then there is nothing to separate and no dash.
--
-- One function rather than the same concatenation in every file, because a plate is exactly the sort of thing that goes out
-- of step one window at a time.
--
function K.WindowTitle(owner, name, what)
  local title = "|cffff2222<" .. (owner or K.KAHLUA) .. ">|r"

  if (name and name ~= "") then
    title = title .. " " .. name
  end

  if (what and what ~= "") then
    title = title .. " - " .. what
  end

  return title
end

function K.err(msg, ...)
  K.printf(K.ecolor, "%s", K.KAHLUA .. " " .. L["error: "] .. strfmt(msg, ...))
end

function K.info(msg, ...)
  K.printf(K.icolor, "%s", K.KAHLUA .. ": " .. strfmt(msg, ...))
end

--
-- A name written in the tables below as an upper case key, "BEAST_MASTERY", as English words, "Beast Mastery". It is what a
-- name the game will not give is shown as, so that a list is never silently missing an entry.
--
local function english(key)
  local words = gsub(strlower(key), "_", " ")

  return (gsub(words, "(%a)(%a*)", function(first, rest)
    return strupper(first) .. rest
  end))
end

--
-- Roles. What kind of raider a character is: a tank, a healer, or one of three kinds of damage, which is what an item
-- restricted to a kind of raider and anybody planning a fight both want to know. A player says for themselves which two
-- they play, their main role and their off role (K.MyRoles), because the game cannot: the role somebody takes in a group
-- is only tank, healer or damage (KRP.ASSIGNED_), and a character's talents say only what it is playing right now. Which
-- roles each class can play is written down in the class table below.
--
K.ROLE_UNSET  = 0
K.ROLE_HEALER = 1
K.ROLE_MELEE  = 2
K.ROLE_RANGED = 3
K.ROLE_CASTER = 4
K.ROLE_TANK   = 5

-- The order roles are always listed in, wherever they are offered or shown.
K.ROLES = { K.ROLE_TANK, K.ROLE_HEALER, K.ROLE_MELEE, K.ROLE_RANGED, K.ROLE_CASTER }

--
-- What to call ROLE on screen, as K.RaceName does for a race.
--
local rolenames = {
  [K.ROLE_UNSET]  = K.NOTSET_STR,
  [K.ROLE_HEALER] = L["Healer"],
  [K.ROLE_MELEE]  = L["Melee DPS"],
  [K.ROLE_RANGED] = L["Ranged DPS"],
  [K.ROLE_CASTER] = L["Caster DPS"],
  [K.ROLE_TANK]   = L["Tank"],
}

function K.RoleName(role)
  return rolenames[role or K.ROLE_UNSET]
end

--
-- Classes. Storing a class by name is inefficient and the name is localised, so every class has a number of our own, the
-- plain number that a role, a profession and a race all are here. A class's number never changes: it is
-- stored in saved variables and sent over the wire, and its position in a class filter string is that number. A filter
-- string is indexed by it and never has one written into it, so there is nothing for a fixed width to buy; somewhere that
-- does want two characters, an export naming a class by number, asks for them with %02d where it writes them.
--
-- Which classes there are depends on the client. Death knights came with Wrath of the Lich King, monks with Mists of
-- Pandaria, demon hunters with Legion and evokers with Dragonflight, and a client from before one of those has no such
-- class. Everything about a class is asked of the game rather than written down here, so nothing below can disagree with the client it runs on:
--
--   C_CreatureInfo.GetClassInfo(classID) gives Blizzard's class token, such as "DEATHKNIGHT", which UnitClass and the guild
--     roster return and RAID_CLASS_COLORS is keyed by, and the class's localised name.
--   K.EXPANSION, at the top of this file, is which expansion this client plays, compared with the LE_EXPANSION_ constants the
--     way Blizzard's own class menu does. LE_EXPANSION_DRAGONFLIGHT falls back to its number for a client that does not define it.
--
-- All that is written by hand is the pairing of Blizzard's class ID, which is fixed, with ours, and the expansion a class
-- first appears in. From those this builds, for every class the client has:
--
--   K.CLASS_<token>      our number, so K.CLASS_WARRIOR is 1 and K.CLASS_DEATHKNIGHT is 10. It is not defined at all on a
--                        client without that class, which is how an addon asks: if (K.CLASS_DEATHKNIGHT) then ... end.
--   K.ClassIndex         Blizzard's class token to our number.
--   K.ClassIDIndex       Blizzard's numeric class ID, UnitClass's third return, to our number.
--   K.LClassIndex        the localised class name to our number, and K.LClassIndexNSP the same with spaces taken out.
--   K.IndexClass         our number to { u = token, c = localised name, l = lower-cased name with no spaces, w = widget name,
--                        id = Blizzard's class ID }. The widget name is the token in lower case, never localised.
--   K.ClassColorsRGBPerc our number to the class's colour, RAID_CLASS_COLORS[token].
--   K.NUM_CLASSES        the highest of our numbers the client has, which is how wide a class filter string is. Classes
--                        only ever arrive in order, so it is also how many there are.
--
-- K.EmptyClassFilter and K.classfilters are built further down, from these.
--
-- Roles. Each class lists the roles it can be played in, ROLES, and SINCE the roles it has gained later, by the expansion
-- it gained them in: hunters took up melee with Legion's Survival, and demon hunters casting with Midnight's Devourer. From
-- those, for every class the client has:
--
--   K.ClassRoles   our class number to the roles it can play on this client, in the order of K.ROLES.
--   K.ClassDamage  our class number to the kind of damage it is first thought of as dealing, the first of its ROLES that is
--                  one, melee before ranged before caster: melee for a druid or a shaman, ranged for a hunter. What a player
--                  is taken to be doing when all that is known of them is their class and that they are dealing damage.
--
local KORE_CLASSES = {
  { id =  1, classid = 1,  roles = { K.ROLE_TANK, K.ROLE_MELEE } },
  { id =  2, classid = 2,  roles = { K.ROLE_TANK, K.ROLE_HEALER, K.ROLE_MELEE } },
  { id =  3, classid = 3,  roles = { K.ROLE_RANGED }, since = { [LE_EXPANSION_LEGION] = { K.ROLE_MELEE } } },
  { id =  4, classid = 4,  roles = { K.ROLE_MELEE } },
  { id =  5, classid = 5,  roles = { K.ROLE_HEALER, K.ROLE_CASTER } },
  { id =  6, classid = 7,  roles = { K.ROLE_HEALER, K.ROLE_MELEE, K.ROLE_CASTER } },
  { id =  7, classid = 8,  roles = { K.ROLE_CASTER } },
  { id =  8, classid = 9,  roles = { K.ROLE_CASTER } },
  { id =  9, classid = 11, roles = { K.ROLE_TANK, K.ROLE_HEALER, K.ROLE_MELEE, K.ROLE_CASTER } },
  { id = 10, classid = 6,  from = LE_EXPANSION_WRATH_OF_THE_LICH_KING, roles = { K.ROLE_TANK, K.ROLE_MELEE } },
  { id = 11, classid = 10, from = LE_EXPANSION_MISTS_OF_PANDARIA, roles = { K.ROLE_TANK, K.ROLE_HEALER, K.ROLE_MELEE } },
  { id = 12, classid = 12, from = LE_EXPANSION_LEGION, roles = { K.ROLE_TANK, K.ROLE_MELEE },
    since = { [LE_EXPANSION_MIDNIGHT or 11] = { K.ROLE_CASTER } } },
  { id = 13, classid = 13, from = LE_EXPANSION_DRAGONFLIGHT or 9, roles = { K.ROLE_HEALER, K.ROLE_CASTER } },
}

K.ClassIndex = {}
K.ClassIDIndex = {}
K.LClassIndex = {}
K.LClassIndexNSP = {}
K.IndexClass = {}
K.ClassColorsRGBPerc = {}
K.NUM_CLASSES = 0
K.ClassRoles = {}
K.ClassDamage = {}

do
  local localised = LOCALIZED_CLASS_NAMES_MALE

  for _, kc in ipairs(KORE_CLASSES) do
    if (not kc.from or K.EXPANSION >= kc.from) then
      local info = C_CreatureInfo.GetClassInfo(kc.classid)

      assert(info and info.classFile, "Kore: the game has no class " .. kc.classid .. " for class " .. kc.id)

      local token = info.classFile
      local name = localised[token] or info.className
      local id = kc.id

      K["CLASS_" .. token] = id
      K.ClassIndex[token] = id
      K.ClassIDIndex[kc.classid] = id
      K.LClassIndex[name] = id
      K.LClassIndexNSP[gsub(name, " ", "")] = id

      --
      -- Where a language names a class differently for a woman, the game uses that name for her, in a guild roster and in an
      -- item's class restriction alike, so it finds the class as well as the name every other class is shown by.
      --
      local female = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[token]

      if (female and female ~= "") then
        K.LClassIndex[female] = id
        K.LClassIndexNSP[gsub(female, " ", "")] = id
      end

      K.IndexClass[id] = { u = token, c = name, l = gsub(strlower(name), " ", ""), w = strlower(token), id = kc.classid }
      K.ClassColorsRGBPerc[id] = RAID_CLASS_COLORS[token]
      K.NUM_CLASSES = max(K.NUM_CLASSES, id)

      -- The roles the class plays, and those it has gained by this client's expansion, in the order of K.ROLES.
      local plays = {}

      for _, role in ipairs(kc.roles) do
        plays[role] = true
      end

      for expansion, later in pairs(kc.since or {}) do
        if (K.EXPANSION >= expansion) then
          for _, role in ipairs(later) do
            plays[role] = true
          end
        end
      end

      K.ClassRoles[id] = {}

      for _, role in ipairs(K.ROLES) do
        if (plays[role]) then
          tinsert(K.ClassRoles[id], role)
        end
      end

      local made = {}

      for _, role in ipairs(kc.roles) do
        made[role] = true
      end

      for _, role in ipairs({ K.ROLE_MELEE, K.ROLE_RANGED, K.ROLE_CASTER }) do
        if (made[role]) then
          K.ClassDamage[id] = role
          break
        end
      end
    end
  end
end

--
-- Professions. The primary ones, the two a character chooses between, whether they make the things whose patterns, recipes
-- and plans drop in raids or gather what those things are made from. The secondary ones everybody may learn are nobody's
-- choice and are not here. Like a class, a profession has a number of our own, which never changes and is what is stored and
-- sent, and 0 is K.PROF_UNSET, a profession slot nobody has filled. Retail divides each profession into one skill line per
-- expansion, Khaz Algar Alchemy and the rest, but those are tiers of a single profession, so a character's profession is still one of these.
--
-- Every profession is of a kind, so that an addon wanting only some of them says which kind it means rather than keeping a
-- list of its own that goes stale the moment a profession is added here:
--
--   K.PROF_CRAFTING    makes things. This is the kind whose patterns, recipes and plans drop in raids.
--   K.PROF_GATHERING   gathers what those things are made from.
--
-- Which professions there are depends on the client. Jewelcrafting came with The Burning Crusade and inscription with Wrath
-- of the Lich King. All that is written by hand below is our number, the profession's kind, its Blizzard skill line, the
-- spell it is taught as, and the expansion it came with. From those this builds, for every profession the client has:
--
--   K.PROF_<key>      our number, K.PROF_ALCHEMY and the rest. Not defined on a client without the profession.
--   K.ProfIndex       "ALCHEMY" and the rest to our number.
--   K.IndexProf       our number to { u = key, c = localised name, skill = Blizzard's skill line, kind = one of the kinds
--                     above, id = our number }.
--   K.SkillLineProf   Blizzard's skill line to our number.
--   K.LProfIndex      the localised name to our number.
--
-- The name is asked of the game rather than translated again by every addon that wants it. The game publishes no list of
-- professions with names. What the client can name is a skill line, and failing that the spell a profession is taught as,
-- and failing both the name is the key in English. K.LProfIndex has the spell's name as well where the two differ, since that
-- is the name a classic client's skill list shows. Herbalism is the standing example, taught as a spell called Herb Gathering
-- on a classic client while the skill line it teaches is called Herbalism.
--
K.PROF_UNSET = 0

K.PROF_CRAFTING  = 1
K.PROF_GATHERING = 2

K.ProfIndex = {}
K.IndexProf = {}
K.SkillLineProf = {}
K.LProfIndex = {}

do
  local CRAFTING, GATHERING = K.PROF_CRAFTING, K.PROF_GATHERING

  local KORE_PROFESSIONS = {
    { id =  1, key = "ALCHEMY",        kind = CRAFTING,  skill = 171, spell =  2259 },
    { id =  2, key = "BLACKSMITHING",  kind = CRAFTING,  skill = 164, spell =  2018 },
    { id =  3, key = "ENCHANTING",     kind = CRAFTING,  skill = 333, spell =  7411 },
    { id =  4, key = "ENGINEERING",    kind = CRAFTING,  skill = 202, spell =  4036 },
    { id =  5, key = "INSCRIPTION",    kind = CRAFTING,  skill = 773, spell = 45357, from = LE_EXPANSION_WRATH_OF_THE_LICH_KING },
    { id =  6, key = "JEWELCRAFTING",  kind = CRAFTING,  skill = 755, spell = 25229, from = LE_EXPANSION_BURNING_CRUSADE },
    { id =  7, key = "LEATHERWORKING", kind = CRAFTING,  skill = 165, spell =  2108 },
    { id =  8, key = "TAILORING",      kind = CRAFTING,  skill = 197, spell =  3908 },
    { id =  9, key = "HERBALISM",      kind = GATHERING, skill = 182, spell =  2366 },
    { id = 10, key = "MINING",         kind = GATHERING, skill = 186, spell =  2575 },
    { id = 11, key = "SKINNING",       kind = GATHERING, skill = 393, spell =  8613 },
  }

  local skillname = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName

  for _, kp in ipairs(KORE_PROFESSIONS) do
    if (not kp.from or K.EXPANSION >= kp.from) then
      local spellname = K.SpellName(kp.spell)
      local name = skillname and skillname(kp.skill)

      if (not name or name == "") then
        name = spellname or english(kp.key)
      end

      K["PROF_" .. kp.key] = kp.id
      K.ProfIndex[kp.key] = kp.id
      K.IndexProf[kp.id] = { u = kp.key, c = name, skill = kp.skill, kind = kp.kind, id = kp.id }
      K.SkillLineProf[kp.skill] = kp.id
      K.LProfIndex[name] = kp.id

      if (spellname) then
        K.LProfIndex[spellname] = kp.id
      end
    end
  end
end

--
-- The skill list as this client keeps it: the old functions, or C_SkillInfo, which the Classic built on retail's client has
-- in their place and which answers a line as a table. How many lines; one line as its name, whether it is a heading and
-- whether that heading is open; and opening or closing a heading.
--
local function skill_count()
  if (GetNumSkillLines) then
    return GetNumSkillLines()
  end

  return C_SkillInfo.GetNumSkillLines()
end

local function skill_line(line)
  if (GetSkillLineInfo) then
    local name, header, expanded = GetSkillLineInfo(line)

    return name, header, expanded
  end

  local info = C_SkillInfo.GetSkillLineInfo(line)

  if (not info) then
    return nil, false, false
  end

  return info.name, info.isHeader, not info.isCollapsed
end

local function skill_heading(line, open)
  if (ExpandSkillHeader) then
    if (open) then
      ExpandSkillHeader(line)
    else
      CollapseSkillHeader(line)
    end
  elseif (open) then
    C_SkillInfo.ExpandSkillHeader(line)
  else
    C_SkillInfo.CollapseSkillHeader(line)
  end
end

--
-- The professions the player has, as our numbers, K.PROF_UNSET for a slot they have not filled. Only the professions above
-- count, so a herbalist tailor has two and a tailor who cooks has one. From Cataclysm the game says which two a character
-- has and their skill lines. Before it there is only the skill list, by name, and a heading the player has collapsed hides
-- what is under it, so any collapsed heading is opened while the list is read and closed again after. That list has the
-- secondary skills in it as well, and they are passed over because they are not in K.LProfIndex to be found.
--
function K.PlayerProfessions()
  local found = {}

  if (K.EXPANSION >= LE_EXPANSION_CATACLYSM) then
    local first, second = GetProfessions()

    for _, index in ipairs({ first or 0, second or 0 }) do
      local prof = index > 0 and K.SkillLineProf[select(7, GetProfessionInfo(index))]

      if (prof) then
        tinsert(found, prof)
      end
    end
  else
    local collapsed = {}
    local line = 1

    while (line <= skill_count()) do
      local name, header, expanded = skill_line(line)

      if (header and not expanded) then
        collapsed[name] = true
        skill_heading(line, true)
      elseif (not header and K.LProfIndex[name]) then
        tinsert(found, K.LProfIndex[name])
      end

      line = line + 1
    end

    for line = skill_count(), 1, -1 do
      local name, header = skill_line(line)

      if (header and collapsed[name]) then
        skill_heading(line, false)
      end
    end
  end

  return found[1] or K.PROF_UNSET, found[2] or K.PROF_UNSET
end

--
-- The name of race RACEID in the player's own language, or nil for a race this client does not have. Races are the one thing
-- here we do not number ourselves: the game's own ids are stable across every client and it will name one for us, so there is
-- nothing for Kore to add. UnitRace returns the id as its third value.
--
function K.RaceName(raceid)
  local info = raceid and C_CreatureInfo.GetRaceInfo(raceid)

  return info and info.raceName
end

--
-- Many mods need to know the different class colors. K.ClassColorsRGBPerc, built with the classes above, is percentage-based
-- RGB values, and from it we set up three more here: decimal, with all numbers between 0 and 255, hex, and text strings
-- suitable for messages, and a darker set of each. This also means that it is possible to change the class colors for all
-- KahLua mods by simply changing these values.
--

function K.RGBPercToDec(rgb)
  local ret = {}
  ret.r = rgb.r * 255
  ret.g = rgb.g * 255
  ret.b = rgb.b * 255
  return ret
end

function K.RGBDecToHex(rgb)
  return strfmt("%02x%02x%02x", rgb.r, rgb.g, rgb.b)
end

function K.RGBPercToHex(rgb)
  return strfmt("%02x%02x%02x", rgb.r*255, rgb.g*255, rgb.b*255)
end

function K.RGBPercToColorCode(rgb)
  local a = 1
  if (rgb.a) then
    a = rgb.a
  end
  return strfmt("|c%02x%02x%02x%02x", a*255, rgb.r*255, rgb.g*255, rgb.b*255)
end

function K.RGBDecToColorCode(rgb)
  local a = 255
  if (rgb.a) then
    a = rgb.a
  end
  return strfmt("|c%02x%02x%02x%02x", a, rgb.r, rgb.g, rgb.b)
end

K.ClassColorsRGB = {}
K.ClassColorsHex = {}
K.ClassColorsEsc = {}
K.ClassColorsRGBPerc2 = {}
K.ClassColorsRGB2 = {}
K.ClassColorsHex2 = {}
K.ClassColorsEsc2 = {}

for k,v in pairs(K.ClassIndex) do
  K.ClassColorsRGB[v] = K.RGBPercToDec(K.ClassColorsRGBPerc[v])
  K.ClassColorsHex[v] = K.RGBDecToHex(K.ClassColorsRGB[v])
  K.ClassColorsEsc[v] = K.RGBPercToColorCode(K.ClassColorsRGBPerc[v])

  local r, g, b, a
  r = K.ClassColorsRGBPerc[v].r / 1.75
  g = K.ClassColorsRGBPerc[v].g / 1.75
  b = K.ClassColorsRGBPerc[v].b / 1.75
  a = K.ClassColorsRGBPerc[v].a or 1
  K.ClassColorsRGBPerc2[v] = { r = r, g = g, b = b, a = a }
  K.ClassColorsRGB2[v] = K.RGBPercToDec(K.ClassColorsRGBPerc2[v])
  K.ClassColorsHex2[v] = K.RGBDecToHex(K.ClassColorsRGB2[v])
  K.ClassColorsEsc2[v] = K.RGBPercToColorCode(K.ClassColorsRGBPerc2[v])
end

local function errorhandler(err)
  return geterrorhandler()(err)
end

-- Call optional function
local function safecall(func, ...)
  if type(func) == "function" then
    return xpcall(func, errorhandler, ...)
  end
end

K.safecall = safecall

--
-- Utility function to copy one table to another. SEEN is internal: it maps a source table to its copy, so cycles terminate
-- and shared sub-tables stay shared in the result.
--
function K.CopyTable(src, dest, seen)
  if (type(dest) ~= "table") then
    dest = {}
  end

  if (type(src) == "table") then
    seen = seen or {}
    seen[src] = dest
    for k, v in pairs(src) do
      if (type(v) == "table") then
        v = seen[v] or K.CopyTable(v, dest[k], seen)
      end
      dest[k] = v
    end
  end
  return dest
end

--
-- Quite a few metatables want to prevent indexed access, so this function is used quite a bit. It simply always asserts
-- false which will raise an exception.
--
K.assert_false = function() assert(false) end

--
-- Two functions to always return true or false
--
K.always_true = function(self) return true end
K.always_false = function(self) return false end

-- We treat British the same as American English.
K.CurrentLocale = GetLocale()
if (K.CurrentLocale == "enGB") then
  K.CurrentLocale = "enUS"
end

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

local ctl = _G.ChatThrottleLib
assert(ctl, "KahLua Kore requires ChatThrottleLib")
assert(ctl.version >= 24, "KahLua Kore requires ChatThrottleLib >= 24")

--
-- Utility function: return a number of nil values, followed by any number of other values.
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
  spos = max(spos or 1, 1)

  local pos = spos
  pos = strfind(arg, "[^ ]", pos)
  if (not pos) then
    -- End of string before we got an argument
    return K.nilret(argc, 1e9)
  end

  if (argc < 1) then
    return pos
  end

  local delim_or_pipe
  local ch = strsub(arg, pos, pos)
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
    pos,_,ch = strfind(arg, delim_or_pipe, pos)

    if (not pos) then
      break
    end

    if (ch == "|") then
      -- Some kind of escape

      if (strsub(arg, pos, pos + 1) == "|H") then
        -- It's a |H....|hhyper link!|h
        pos = strfind(arg, "|h", pos + 2)       -- first |h
        if (not pos) then
          break
        end

        pos = strfind(arg, "|h", pos + 2)       -- second |h
        if (not pos) then
          break
        end
      elseif (strsub(arg,pos, pos + 1) == "|T") then
        -- It's a |T....|t  texture
        pos=strfind(arg, "|t", pos + 2)
        if (not pos) then
          break
        end
      end

      pos = pos + 2 -- Skip past this escape (last |h if it was a hyperlink)
    else
      -- Found delimiter, done with this arg
      return strsub(arg, spos, pos - 1), K.GetArgs(arg, argc - 1, pos + 1)
    end
  end

  -- Search aborted, we hit end of string. return it all as one argument.
  return strsub(arg, spos), K.nilret(argc - 1, 1e9)
end

--
-- Deal with KahLua Kore slash commands. Each KahLua module can have its commands accessed either by typing /kahlua NAME, or
-- any number of additional extra arguments. /kNAME is always created too. So for example, if you register a module called
-- "konfer", you can get to its main argument handling function via "/kahlua konfer" or "/kkonfer" by default. You can also
-- chose to register any number of additional entry points.
--
-- Each argument after the name and the primary function is either a string or a table. If its a string, it is a simple entry
-- into the main argument processing array. If it is a table, the table must have two members: name and func. name is the
-- name of the command and func is a reference to the function that will deal with that alias.
--

local function listall()
  local k,v
  for k,v in pairs(K.slashtable) do
    K.printf(K.ucolor, "    |cffffff00%s|r - %s [r%s]", k, v.desc, v.version)
  end
end

local function kahlua_usage()
  K.printf(K.ucolor, "|cffff2222<%s>|r %s - %s", K.KAHLUA,
    strfmt(L["KAHLUA_VER"], KORE_MINOR), L["KAHLUA_DESC"])
  K.printf(K.ucolor, L["Usage: %s/%s module [arg [arg...]]%s"],
    "|cffffffff", L["CMD_KAHLUA"], "|r")
  K.printf(K.ucolor, L["    Where module is one of the following modules:"])
  listall()
  K.printf(K.ucolor, L["For help with any module, type %s/%s module %s%s."], "|cffffffff", L["CMD_KAHLUA"], L["CMD_HELP"], "|r")
end

local function kahlua(input)
  if (not input or input == "" or input:lower() == "help") then
    kahlua_usage()
    return
  end


  if (input:lower() == L["CMD_VERSION"] or input:lower() == "version" or input:lower() == "ver") then
    K.printf(K.ucolor, "|cffff2222<%s>|r %s - %s", K.KAHLUA,
      strfmt(L["KAHLUA_VER"], KORE_MINOR), L["KAHLUA_DESC"])
    K.printf(K.ucolor, "(C) Copyright 2008-2026 Kean Johnston (Cruciformer). All rights reserved.")
    K.printf(K.ucolor, L["Kore extensions loaded:"])
    for k,v in pairs(K.extensions) do
      K.printf(K.ucolor, "    |cffffff00%s|r %s", k, strfmt(L["KAHLUA_VER"], v.version))
    end
    K.printf(K.ucolor, "This is open source software, distributed under the terms of the Apache license. For the latest"
      .. " version and other KahLua modules, visit |cffffffffhttps://www.curseforge.com/wow/addons/konfer|r.")
    return
  end

  if (input:lower() == L["CMD_LIST"]) then
    K.printf(K.ucolor,L["The following modules are available:"])
    listall()
    return
  end

  local cmd, pos = K.GetArgs(input)
  if (not cmd or cmd == "") then
    kahlua_usage()
    return
  end
  cmd = strlower(cmd)

  if (not K.slashtable[cmd]) then
    K.printf(K.ecolor, L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."],
      cmd, "|cffffffff", L["CMD_KAHLUA"], L["CMD_LIST"], "|r")
    return
  end

  local arg
  if (pos == 1e9) then
    arg = ""
  else
    arg = strsub(input, pos)
  end

  K.slashtable[cmd].fn(arg)
end

local function kcmdfunc(input)

  if (not input or input:lower() == L["CMD_HELP"] or input:lower() == "help" or input == "?" or input == "") then
    K.printf(K.ucolor,L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"], "|cffffffff", L["CMD_KORE"], "|r")
    K.printf(K.ucolor,L["%s/%s %s module level%s"], "|cffffffff", L["CMD_KORE"], L["CMD_DEBUG"], "|r")
    K.printf(K.ucolor,L["  Sets the debug level for a module. 0 disables."])
    K.printf(K.ucolor,L["  The higher the number the more verbose the output."])
    K.printf(K.ucolor,"%s/%s %s%s", "|cffffffff", L["CMD_KORE"], L["CMD_LIST"], "|r")
    K.printf(K.ucolor,L["  Lists all modules registered with KahLua."])
    return
  end

  if (input:lower() == L["CMD_LIST"] or input:lower() == "list") then
    K.printf(K.ucolor,L["The following modules are available:"])
    listall()
    return
  end

  local cmd, pos = K.GetArgs(input)
  if (not cmd or cmd == "") then
    kcmdfunc()
    return
  end
  cmd = strlower(cmd)

  if (cmd == L["CMD_DEBUG"] or cmd == "debug") then
    local md, lvl, npos = K.GetArgs(input, 2, pos)
    if (not md or not lvl or npos ~= 1e9 or not tonumber(lvl)) then
      kcmdfunc()
      return
    end
    md = strlower(md)
    lvl = tonumber(lvl)

    if (not K.slashtable[md]) then
      K.printf(K.ecolor, L["Cannot enable debugging for '%s' - no such module."],
        md)
      return
    end

    if (lvl < 0 or lvl > 10) then
      K.printf(K.ecolor, L["Debug level %d out of bounds - must be between 0 and 10."], lvl)
      return
    end

    K.debugging[md] = lvl
    return
  elseif (cmd == "ginit") then
    update_player_and_guild()
  elseif (cmd == "status") then
    local rs = strfmt("player=%s faction=%s class=%s level=%s guilded=%s", tostring(K.player.name),
      tostring(K.player.faction), tostring(K.player.class), tostring(K.player.level), tostring(K.player.is_guilded))
    if (K.player.is_guilded) then
      rs = rs .. strfmt(" guild=%q isgm=%s rankidx=%s numranks=%s", tostring(K.player.guild), tostring(K.player.is_gm),
        tostring(K.player.guildrankidx), tostring(K.guild.numranks))
    end

    K.printf("%s", rs);
    if (K.player.is_guilded) then
      local i
      for i = 1, K.guild.numranks do
        K.printf("Rank %d: name=%q", i, tostring(K.guild.ranks[i]))
      end
    end
  end
end

local function RegisterSlashCommand(name, func, desc, version, ...)
  if (not L) then
    error ("KahLua Kore: I18N initialization did not complete.", 2)
  end

  name = strlower(name)

  if (not K.slashtable) then
    K.slashtable = {}
    K.slashtable["kore"] = { fn = kcmdfunc,
      desc = strfmt(L["KORE_DESC"], K.KAHLUA),
      version = KORE_MINOR }
    K.slashtable["kore"].alts = {}
    K.slashtable["kore"].alts["kore"] = kcmdfunc
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
      error("Kore:NewAddon: invalid alternate name.", 2)
    end
  end

  --
  -- Register all of the slash command each time a new one is added. No real penalty to doing so, as it will just re-register
  -- the same old commands on additional calls to the function.
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
        local asn = sn .. "_" .. kk:upper()
        SlashCmdList[asn] = vv
        ds = "SLASH_" .. asn .. "1"
        _G[ds] = "/" .. kk
      end
    end
  end
end

--
-- Now for a few standard events that we capture and process so that all addons interested in them can simply register for
-- the message. We want to keep track of some of this stuff for our own internal purposes.
--
local function guild_update(evt, arg1)
  if (evt == "PLAYER_GUILD_UPDATE" or evt == "GUILD_RANKS_UPDATE") then
    update_player_and_guild()
    return
  end

  if (evt == "GUILD_ROSTER_UPDATE") then
    if (arg1) then
      C_GuildInfo.GuildRoster()
      return
    end

    update_player_and_guild()
    return
  end
end

local hasraidinfo

local function instance_update(evt, ...)
  if (not hasraidinfo) then
    hasraidinfo = 1
    return
  end
  K.raids = {}
  K.raids.numraids = GetNumSavedInstances()
  K.raids.info = {}
  if (K.raids.numraids > 0) then
    local i
    for i = 1, K.raids.numraids do
      local iname, iid, ireset, ilevel = GetSavedInstanceInfo(i)
      local ti = { zone = iname, raidid = iid, level = ilevel }
      tinsert(K.raids.info, ti)
    end
  end
  K:SendMessage("RAID_LIST_UPDATED")
end

K:RegisterEvent("PLAYER_GUILD_UPDATE", guild_update)
K:RegisterEvent("GUILD_ROSTER_UPDATE", guild_update)
K:RegisterEvent("GUILD_RANKS_UPDATE", guild_update)
K:RegisterEvent("UPDATE_INSTANCE_INFO", instance_update)

--
-- Deal with Kore addon initialisation. We maintain a table of all Kore
-- addons, each of which announces itself to Kore by calling Kore:NewAddon(),
-- defined below. Each addon calls this very early on in its life in order
-- to create the addon object. That call also embeds various Kore functions
-- into the returned object. It also sets up the slash command handler for
-- the modules and arranges to call the module's argument processing
-- function (addon.ProcessSlashCommand). We also arrange for the addon's
-- initialization functions to be called at the appropriate time. An addon
-- can have four initialisation functions: OnEarlyInit, which is called when
-- PLAYER_LOGIN fires, before any addon's OnLoginInit, OnLoginInit() which is
-- called straight after it when IsLoggedIn() returns true, OnEnteringWorld() which is called
-- when PLAYER_ENTERING_WORLD fires, which can happen more than once, and
-- OnLateInit(), which is called after all addons and FrameXML code has
-- loaded. Only OnEnteringWorld() is ever called more than once.
--
K.addons = K.addons or {}
K.earlyq = K.earlyq or {}
K.loginq = K.loginq or {}
K.pewq = K.pewq or {}
K.lateq = K.lateq or {}

local function addon_tostring(this)
  return this.kore_name
end

--
-- object  - existing object to embed Kore into or nil to create a new one
-- name    - the name of the addon, usually CamelCased
-- ver     - the version of the addon
-- desc    - brief description of the addon
-- cmdname - the primary command name for accessing the addon
-- ...     - additional alternate commands for accessing the addon
function K:NewAddon(obj, name, ver, desc, cmdname, ...)
  assert(obj == nil or type(obj) == "table", "Kore: first argument must be nil or an object table.")
  assert(name, "Kore: addon name must be provided.")
  assert(ver, "Kore: addon version must be provided.")
  assert(desc, "Kore: addon description must be provided.")

  if (self.addons[name]) then
    error(("Kore: addon %q already exists."):format(name), 2)
  end

  local obj = obj or {}
  obj.kore_name = name
  obj.kore_desc = desc
  obj.kore_ver = ver
  obj.kore_minor = KORE_MINOR

  local addonmeta = {}
  local oldmeta = getmetatable(obj)
  if (oldmeta) then
    for k,v in pairs(oldmeta) do
      addonmeta[k] = v
    end
  end
  addonmeta.__tostring = addon_tostring
  setmetatable(obj, addonmeta)

  self.addons[name] = obj

  --
  -- Each object gets a Kore-specific frame that we use for timers and other such things. Create that frame now.
  --
  obj.kore_frame = obj.kore_frame or CreateFrame("Frame", name .. "KoreFrame")
  obj.kore_frame:UnregisterAllEvents()

  K:AceKore(obj)

  --
  -- The game calls a slash command with the words typed and the chat edit box they were typed in. OnSlashCommand is handed
  -- the words alone, so that an addon is free to give it arguments of its own when it calls it from anywhere else.
  --
  RegisterSlashCommand(cmdname, function(input)
    safecall(obj.OnSlashCommand, obj, input)
  end, desc, ver, ...)

  tinsert(self.earlyq, obj)
  tinsert(self.pewq, obj)

  if (kore_ready == 2) then
    safecall(obj.OnLateInit, obj)
  else
    tinsert(self.lateq, obj)
  end

  return obj
end

function K:GetAddon(name, opt)
  if (not opt and not self.addons[name]) then
    error(("Kore:GetAddon: cannot find addon %q"):format(tostring(name)), 2)
  end
  return self.addons[name]
end

--
-- Kore's own saved data, inside KoreDB. Kore is an addon in its own right with a TOC of its own, so it owns this rather than
-- being handed a table by whichever mod happened to load it, and every KahLua mod on the client reads and writes the one
-- copy. That is the whole reason a character's facts live here and not in any one mod.
--
--   K.frdb      Per faction and realm. The people Kore knows about, which are facts about the game's own characters and the
--               same facts whichever mod asked after them.
--   K.chardb    This character alone. What the player has said about themselves where the game cannot simply be asked, their
--               chosen main and off spec and the professions they report, and what it owes others by trade (KLD.trades).
--   K.globaldb  The account. What has been put to the player once and need not be put to them again.
--
-- Built at PLAYER_LOGIN before any addon's OnEarlyInit runs, so that a mod may read it from its very first initialisation,
-- and only once however many times the event arrives.
--
local function kore_database()
  if (K.db) then
    return
  end

  K.db = DB:New("KoreDB", nil, "Default")
  K.frdb = K.db.factionrealm
  K.chardb = K.db.char
  K.globaldb = K.db.global

  --
  -- The people, and whose word about them is thrown away unread. Both are per faction and realm because a character on one
  -- is nobody on another. Kore.Users takes its alias here rather than reaching for K.frdb itself, so that everything it does
  -- can tell "before login" from "nobody is known yet" by whether it has a table at all.
  --
  if (not K.frdb.users) then
    K.frdb.users = {}
  end

  if (not K.frdb.blockedsenders) then
    K.frdb.blockedsenders = {}
  end

  --
  -- The user editor opens the way this character last left it, listing each main with their alts under them, and tethered
  -- for a character who has never opened it.
  --
  if (K.chardb.useredittether == nil) then
    K.chardb.useredittether = true
  end

  if (K.Users) then
    K.Users.users = K.frdb.users
    K.Users:Startup()
  end

  add_player_user()
end

local function addonOnEvent(this, event, arg1)
  if (event == "PLAYER_LOGIN") then
    kore_database()

    while (#K.earlyq > 0) do
      get_static_player_info()
      local addon = tremove(K.earlyq, 1)
      safecall(addon.OnEarlyInit, addon)
      tinsert(K.loginq, addon)
    end

    if (IsLoggedIn()) then
      get_static_player_info()
      while (#K.loginq> 0) do
        local addon = tremove(K.loginq, 1)
        safecall(addon.OnLoginInit, addon)
      end
    end
    return
  elseif (event == "PLAYER_ENTERING_WORLD") then
    get_static_player_info()
    for i = 1, #K.pewq do
      local addon = K.pewq[i]
      safecall(addon.OnEnteringWorld, addon)
    end
  end
end

--
-- Runs every frame until the player's name and realm are known, which is not always so on the first frame after loading, and
-- then no more. Stopping on the first frame regardless would leave OnLateInit never called when they were late.
--
local function addonOnUpdate(this, event)
  if (not get_static_player_info()) then
    return
  end

  this:SetScript("OnUpdate", nil)
  update_player_and_guild()

  if (kore_ready == 1) then
    kore_ready = 2
    -- For each extension or addon that is using us let them know that basic Kore functionality is ready. If a module joins
    -- late, after this code has been run, then the code that deals with adding the extension will send the event.
    for k, v in pairs(K.extensions) do
      safecall(v.library.OnLateInit, v.library)
    end
    while (#K.lateq > 0) do
      local addon = tremove(K.lateq, 1)
      safecall(addon.OnLateInit, addon)
    end
  end
end

K.addonframe = K.addonframe or CreateFrame("Frame", "KoreAddonFrame")
K.addonframe:UnregisterAllEvents()
K.addonframe:SetScript("OnEvent", addonOnEvent)
K.addonframe:SetScript("OnUpdate", addonOnUpdate)
K.addonframe:RegisterEvent("PLAYER_LOGIN")
K.addonframe:RegisterEvent("PLAYER_ENTERING_WORLD")

local addonembeds = {
  "DoCallbacks", "RegisterAddon", "SuspendAddon", "ResumeAddon",
  "ActivateAddon", "GetAddon", "AddonCallback", "GetPrivate",
  "ConfirmationDialog", "RenameDialog", "PopupSelectionList",
  "SingleStringInputDialog"
}

function K:DoCallbacks(name, ...)
  for k, v in pairs(self.addons) do
    if (type(v) == "table" and type(v.callbacks) == "table") then
      if (v.active) then
        -- All callbacks are called with the same first 3 arguments:
        -- 1. The name of the addon.
        -- 2. The name of the callback.
        -- 3. The addon private data table.
        -- Only active addons have their callbacks called.
        safecall(v.callbacks[name], k, name, v.private, ...)
      end
    end
  end
end

--
-- Every KahLua mod running on this client, keyed by the handle it registered with, each { handle, title, version }.
--
-- This is neither K.addons nor any extension's copy of it. Those say "this addon wants my callbacks", there is one per
-- extension, and a mod appears in as many of them as it uses. This one says only "this mod is here, and this is the copy of
-- it you have", which is what a character info check reports and what its "*" asks after. It is one table for the whole
-- client rather than one per extension, so RegisterMod is not in addonembeds and writes K.mods rather than self.mods.
--
-- A mod that is installed but switched off never loads, so it never registers and is simply absent. That is the answer
-- wanted: a mod that is not running is not there, whatever the addon list says about it.
--
K.mods = K.mods or {}

--
-- Function: K:RegisterMod(handle, title, version)
-- Purpose : Called once by each KahLua mod to say that it is here. HANDLE is its own short name, lower case, the same one it
--           uses everywhere else ("konfer", "kartographer"), and is how another client names it when asking after it. TITLE
--           is what to call it on screen, which travels because a client asking about a mod it does not itself have has no
--           way to know it. VERSION is the packaged revision.
--
--           **Zero means a development copy**, and that is the one test anything comparing versions has to make. A mod sets
--           its version from the packager's marker and puts a line straight after it forcing 0, which the packager deletes:
--
--             local MINOR = tonumber("@revision@")
--             local MINOR = 0 -- @debug-delete@
--
--           A development copy is never behind anything and is never something to update to, so it is neither nagged about
--           nor offered, and it is shown as K.DEV_STR rather than as the number 0.
-- Returns : true if the mod was added, false for a handle that is unusable or already taken.
--
function K:RegisterMod(handle, title, version)
  if (not handle or type(handle) ~= "string" or handle == "" or K.mods[handle]) then
    return false
  end

  K.mods[handle] = { handle = handle, title = title or handle, version = tonumber(version) or 0 }

  return true
end

--
-- Kore registers itself, being a KahLua mod like any other and the one every KahLua client has in common, which is why a
-- character info check reports its version whatever else was asked for.
--
K:RegisterMod("kore", "Kore", KORE_REVISION)

--
-- Function: K:RegisterAddon(name)
-- Purpose : Called by an addon to register with an ext. This creates both a private config space for the addon, as well a
--           place to store any callback functions.
-- Fires   : NEW_ADDON(name)
--           SUSPEND_ADDON(name)
-- Returns : true if the addon was added and the events fired, false if not.
--
function K:RegisterAddon(nm)
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

  safecall(self.OnNewAddon, self, nm)
  safecall(self.OnActivateAddon, self, nm, false)

  return true
end

--
-- Function: K:SuspendAddon(name)
-- Purpose : Called by an addon to suspend itself. When an addon is suspended none of its callback functions will be called
--           by Kore as it does its work. However, if the addon has registered any event handlers they will still be called.
-- Fires   : SUSPEND_ADDON(name)
-- Returns : true if the addon was suspended, false if it was either already suspended or the addon name is invalid.
--
function K:SuspendAddon(name)
  if (not name or type(name) ~= "string" or name == "" or not self.addons[name]
      or type(self.addons[name]) ~= "table") then
    return false
  end

  if (self.addons[name].active) then
    self.addons[name].active = false
    self.addons[name].private = {}
    safecall(self.OnActivateAddon, self, name, false)
    return true
  end

  return false
end

--
-- Function: K:ResumeAddon(name) K:ActivateAddon(name)
-- Purpose : Called by an addon to resume itself.
--
--           The private space is left as it is. Suspending empties it, an addon that is off being an addon that knows
--           nothing, but coming back is not a second forgetting, and an addon that stashed something before it was ever
--           activated would lose it on the way in.
-- Fires   : ACTIVATE_ADDON(name)
-- Returns : true if the addon was resumed, false if it was either already active or the addon name is invalid.
--
function K:ResumeAddon(name)
  if (not name or type(name) ~= "string" or name == "" or not self.addons[name]
      or type(self.addons[name]) ~= "table") then
    return false
  end

  if (not self.addons[name].active) then
    self.addons[name].active = true
    safecall(self.OnActivateAddon, self, name, true)
    return true
  end

  return false
end
K.ActivateAddon = K.ResumeAddon

--
-- Function: K:GetPrivate(name)
-- Purpose : Called by an addon to get its private config space.
-- Returns : The private config space for the named addon or nil if no such addon exists.
--
function K:GetPrivate(name)
  if (not name or type(name) ~= "string" or name == "" or not self.addons[name]
      or type(self.addons[name]) ~= "table" or not self.addons[name].private
      or type(self.addons[name].private) ~= "table") then
    return nil
  end

  return self.addons[name].private
end

--
-- Function: K:AddonCallback(name, callback, handler)
-- Purpose : Called by an addon with the specified name to register a new callback. The name of the callback must be a string
--           and only a defined set of callback names will ever be called by Kore. The callback arg can be nil to remove a
--           callback. Each addon can only register a single handler function for each given callback.
-- Returns : True if the callback was registered and valid, false otherwise.
--
function K:AddonCallback(name, callback, handler)
  if (not name or type(name) ~= "string" or name == ""
      or not self.addons[name] or type(self.addons[name]) ~= "table"
      or not self.addons[name].callbacks
      or type(self.addons[name].callbacks) ~= "table"
      or not callback or type(callback) ~= "string" or callback == ""
      or not self.valid_callbacks[callback]) then
    return false
  end

  if (handler and type(handler) ~= "function") then
    return false
  end

  self.addons[name].callbacks[callback] = handler

  return true
end

--
-- This is for extensions to Kore itself, such as KoreParty or KoreLoot.
-- Those extensions register with the Kore via this function. Addons that
-- use either the Kore or its extensions can register themselves with the
-- component(s) they need, which they do using the various Addon functions
-- above, each of which is added to the list of elements in the extension.
-- So for example, an addon that wants to use both KoreParty(KRP) and
-- KoreLoot(KLD) would call: KRP:RegisterAddon() and KLD:RegisterAddon.
--
function K:RegisterExtension(kext, major, minor)
  local ext = {}
  ext.version = minor
  ext.library = kext
  K.extensions[major] = ext
  kext.version = minor

  for k,v in pairs (evtembeds) do
    kext[v] = K[v]
  end

  for k,v in pairs (addonembeds) do
    kext[v] = K[v]
  end

  --
  -- The two tables those methods write, made here rather than left to the extension. Every one of them indexes one or the
  -- other, so an extension handed RegisterAddon with nowhere to put an addon has been handed half a thing. An extension
  -- that names the callbacks it answers replaces valid_callbacks with its own, that list being the one thing here nobody
  -- else can guess; KoreUI and KoreHash take neither and simply never have an addon registered with them.
  --
  kext.addons = kext.addons or {}
  kext.valid_callbacks = kext.valid_callbacks or {}

  if (kore_ready == 2) then
    safecall(kext.OnLateInit, kext)
  end
end

--
-- This isn't really useful to any mod that doesn't every have to deal with
-- items or loot, but it's a small table so this is now a part of Kore.
--
-- One of the things we need to know when looting items is the armor class of an item. This info is returned by GetItemInfo()
-- but the strings are localised. So we need to set up a translation table from that localised string to some constant that
-- has generic meaning to us (and is locale agnostic). Set up that table now. Please note that this relies heavily on the
-- fact that some of these functions return values in the same order for a given UI release. If this proves to be inacurate,
-- this whole strategy will need to be re-thought.
--
K.classfilters = {}

K.classfilters.weapon = Enum.ItemClass.Weapon
K.classfilters.armor  = Enum.ItemClass.Armor

--
-- The item subclasses we filter on. Every name here must have an entry in the filter tables below or we assert at load,
-- rather than handing out a nil mask at loot time.
--
-- Iterate these to walk the filter tables without touching Enum yourself:
--   K.classfilters.weapons[K.WeaponSubclass[name]]
K.WeaponSubclasses = {
  "Axe1H", "Axe2H", "Bows", "Guns", "Mace1H", "Mace2H", "Polearm",
  "Sword1H", "Sword2H", "Warglaive", "Staff", "Unarmed", "Generic",
  "Dagger", "Thrown", "Crossbow", "Wand", "Fishingpole",
}

K.ArmorSubclasses = {
  "Generic", "Cloth", "Leather", "Mail", "Plate", "Cosmetic",
  "Shield", "Libram", "Idol", "Totem", "Sigil", "Relic",
}

--
-- Name to numeric subclass value, and the reverse. Populated by build() below as it resolves each name, so a consumer never
-- has to reach into Enum to index the filter tables or to name a subclass for display.
--
K.WeaponSubclass = {}
K.ArmorSubclass = {}
K.WeaponSubclassName = {}
K.ArmorSubclassName = {}

--
-- Class filters are stored and transmitted as a string of "0" and "1", one character per class, indexed by the numeric part
-- of K.CLASS_xxx, and K.NUM_CLASSES wide. They are authored below as sets of classes and the strings built at load, so they
-- follow the classes the client has. A class the client does not have is nil here, and a set simply leaves it out.
--
local WARRIOR, PALADIN, HUNTER = K.CLASS_WARRIOR, K.CLASS_PALADIN, K.CLASS_HUNTER
local ROGUE,   PRIEST,  SHAMAN = K.CLASS_ROGUE,   K.CLASS_PRIEST,  K.CLASS_SHAMAN
local MAGE,    WARLOCK, DRUID  = K.CLASS_MAGE,    K.CLASS_WARLOCK, K.CLASS_DRUID
local DEATHKNIGHT, MONK, DEMONHUNTER = K.CLASS_DEATHKNIGHT, K.CLASS_MONK, K.CLASS_DEMONHUNTER
local EVOKER = K.CLASS_EVOKER

--
-- A set of classes, from any number of K.CLASS_xxx constants of which those the client does not have are nil and left out.
--
local function these(...)
  local set = {}

  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if (c) then
      set[#set + 1] = c
    end
  end

  return set
end

--
-- Turn a list of K.CLASS_xxx constants into a filter string.
--
local function mask(classes)
  local m = {}
  for i = 1, K.NUM_CLASSES do
    m[i] = "0"
  end
  for i = 1, #classes do
    local cp = classes[i]
    assert(cp and cp >= 1 and cp <= K.NUM_CLASSES,
      "Kore: bad class constant in a classfilters table")
    m[cp] = "1"
  end
  return tconcat(m, "")
end

--
-- Build a subclass-keyed table of filter strings from a name-keyed spec, asserting that every known subclass has been accounted for.
--
local function build(subclasses, ename, etbl, byname, byvalue, spec)
  local out = {}
  for i = 1, #subclasses do
    local name = subclasses[i]
    local v = etbl[name]
    assert(v, "Kore: Enum." .. ename .. "." .. name .. " is missing")
    local classes = spec[name]
    assert(classes, "Kore: no class filter defined for " .. ename .. "." .. name)
    byname[name] = v
    byvalue[v] = name
    out[v] = mask(classes)
  end
  return out
end

--
-- Every class the client has, in our order.
--
local ALL = {}
for i = 1, K.NUM_CLASSES do
  ALL[i] = i
end

K.classfilters.allclasses = mask(ALL)
K.EmptyClassFilter        = mask({})

--
-- Strict armour filtering: only classes that actually wear this armour type.
--
K.classfilters.strict = build(K.ArmorSubclasses, "ItemArmorSubclass",
  Enum.ItemArmorSubclass, K.ArmorSubclass, K.ArmorSubclassName, {
  Generic  = ALL,
  Cosmetic = ALL,
  Cloth    = these(PRIEST, MAGE, WARLOCK),
  Leather  = these(ROGUE, DRUID, MONK, DEMONHUNTER),
  Mail     = these(HUNTER, SHAMAN, EVOKER),
  Plate    = these(WARRIOR, PALADIN, DEATHKNIGHT),
  Shield   = these(WARRIOR, PALADIN, SHAMAN),
  Libram   = these(PALADIN),
  Idol     = these(DRUID),
  Totem    = these(SHAMAN),
  Sigil    = these(DEATHKNIGHT),
  Relic    = these(PALADIN, SHAMAN, DRUID, DEATHKNIGHT),
})

--
-- Relaxed armour filtering: classes that may legitimately want this armour type even if it isn't their top proficiency.
--
K.classfilters.relaxed = build(K.ArmorSubclasses, "ItemArmorSubclass",
  Enum.ItemArmorSubclass, K.ArmorSubclass, K.ArmorSubclassName, {
  Generic  = ALL,
  Cosmetic = ALL,
  Cloth    = ALL,
  Leather  = these(WARRIOR, PALADIN, HUNTER, ROGUE, SHAMAN, DRUID, DEATHKNIGHT, MONK, DEMONHUNTER, EVOKER),
  Mail     = these(WARRIOR, PALADIN, HUNTER, SHAMAN, DEATHKNIGHT, EVOKER),
  Plate    = these(WARRIOR, PALADIN, DEATHKNIGHT),
  Shield   = these(WARRIOR, PALADIN, SHAMAN),
  Libram   = these(PALADIN),
  Idol     = these(DRUID),
  Totem    = these(SHAMAN),
  Sigil    = these(DEATHKNIGHT),
  Relic    = these(PALADIN, SHAMAN, DRUID, DEATHKNIGHT),
})

K.classfilters.weapons = build(K.WeaponSubclasses, "ItemWeaponSubclass",
  Enum.ItemWeaponSubclass, K.WeaponSubclass, K.WeaponSubclassName, {
  Axe1H       = these(WARRIOR, PALADIN, HUNTER, ROGUE, SHAMAN, DEATHKNIGHT, MONK, DEMONHUNTER, EVOKER),
  Axe2H       = these(WARRIOR, PALADIN, HUNTER, SHAMAN, DEATHKNIGHT, EVOKER),
  Bows        = these(WARRIOR, HUNTER, ROGUE),
  Guns        = these(WARRIOR, HUNTER, ROGUE),
  Crossbow    = these(WARRIOR, HUNTER, ROGUE),
  Thrown      = these(WARRIOR, HUNTER, ROGUE),
  Mace1H      = these(WARRIOR, PALADIN, ROGUE, PRIEST, SHAMAN, DRUID, DEATHKNIGHT, MONK, EVOKER),
  Mace2H      = these(WARRIOR, PALADIN, SHAMAN, DRUID, DEATHKNIGHT, EVOKER),
  Polearm     = these(WARRIOR, PALADIN, HUNTER, DRUID, DEATHKNIGHT, MONK),
  Sword1H     = these(WARRIOR, PALADIN, HUNTER, ROGUE, MAGE, WARLOCK, DEATHKNIGHT, MONK, DEMONHUNTER, EVOKER),
  Sword2H     = these(WARRIOR, PALADIN, HUNTER, DEATHKNIGHT, EVOKER),
  Warglaive   = ALL,
  Staff       = these(WARRIOR, HUNTER, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID, MONK, EVOKER),
  Unarmed     = these(WARRIOR, HUNTER, ROGUE, SHAMAN, DRUID, MONK, DEMONHUNTER, EVOKER),
  Dagger      = these(WARRIOR, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID, EVOKER),
  Wand        = these(PRIEST, MAGE, WARLOCK),
  Generic     = ALL,
  Fishingpole = ALL,
})

--
-- Returns equip location, item class and item subclass for an item.
--
-- GetItemInfoInstant reads the client's own item data and so cannot miss, where GetItemInfo returns nil until the server has
-- answered for an item this client has not seen before. Both are C_Item's on every client, the globals of the same name
-- being deprecated shims that go when fallbacks are switched off.
--
function K.GetItemClassInfo(ilink)
  local _, _, _, slot, _, icls, isubcls = C_Item.GetItemInfoInstant(ilink)
  return slot, icls, isubcls
end

--
-- This function will take a given itemlink and examine its tooltip looking for class restrictions. It will return a class
-- filter mask suitable for use in a loot system. If no class restriction was found, return the all-inclusive mask.
--
-- Returns: filter, boe, cached
--
-- The tooltip can only be scanned once the client has the item data. Until then CACHED is false and the filter is
-- provisional, so the caller should ask again on GET_ITEM_INFO_RECEIVED rather than persisting it.
--
function K.GetItemClassFilter(ilink)
  local tnm, _, _, _, _, _, _, _, _, _, _, _, _, bindtype = C_Item.GetItemInfo(ilink)
  if (not tnm or tnm == "") then
    return K.classfilters.allclasses, nil, false
  end

  local tt = K.ScanTooltip(ilink)
  local ss = strfmt(ITEM_CLASSES_ALLOWED, "(.-)\n")
  local foo = match(tt, ss)

  --
  -- Whether it binds when picked up or when equipped is the item's bind type, 1 and 2, which every client gives, rather than
  -- the tooltip's words. Anything else is neither.
  --
  local boe = nil
  if (bindtype == 1) then
    boe = false
  elseif (bindtype == 2) then
    boe = true
  end

  if (foo) then
    foo = gsub(foo, " ", "")
    local clist = {}
    for i = 1, K.NUM_CLASSES do
      clist[i] = "0"
    end
    for k,v in pairs( { string.split(",", foo) } ) do
      local cp = K.LClassIndexNSP[v]
      if (not cp or cp < 1 or cp > K.NUM_CLASSES) then
        --
        -- Refuse to filter rather than guess. Too many candidates is a recoverable annoyance; hiding the only eligible one is not.
        --
        debug(1, "unknown class %q in class restriction for %s", tostring(v), tostring(ilink))
        return K.classfilters.allclasses, boe, true
      end
      clist[cp] = "1"
    end
    return tconcat(clist, ""), boe, true
  else
    return K.classfilters.allclasses, boe, true
  end
end

-- K.Deformat compliments of ChatGPT For example: local plr, roll, minr, maxr = K.Deformat(arg1, RANDOM_ROLL_RESULT)

local deformat_cache = {}

local function escape_pattern(c)
  return c:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

function K.Deformat(str, fmt)
  local compiled = deformat_cache[fmt]

  if not compiled then
    local pat = { "^" }
    local order, types = {}, {}
    local nextarg, maxarg = 1, 0
    local i = 1

    while i <= #fmt do
      local c = fmt:sub(i, i)

      if c ~= "%" then
        pat[#pat + 1] = escape_pattern(c)
        i = i + 1
      elseif fmt:sub(i + 1, i + 1) == "%" then
        pat[#pat + 1] = "%%"
        i = i + 2
      else
        local tail = fmt:sub(i)
        local pos, typ = tail:match("^%%(%d+)%$([sdiu])")
        local n

        if pos then
          n = tonumber(pos)
          i = i + #pos + 3
        else
          typ = tail:match("^%%([sdiu])")
          if not typ then
            return nil
          end
          n = nextarg
          nextarg = nextarg + 1
          i = i + 2
        end

        order[#order + 1] = n
        types[#types + 1] = typ
        maxarg = math.max(maxarg, n)

        if typ == "s" then
          pat[#pat + 1] = "(.-)"
        elseif typ == "u" then
          pat[#pat + 1] = "(%d+)"
        else
          pat[#pat + 1] = "([+-]?%d+)"
        end
      end
    end

    pat[#pat + 1] = "$"
    compiled = { table.concat(pat), order, types, maxarg }
    deformat_cache[fmt] = compiled
  end

  local cap = { str:match(compiled[1]) }
  if not cap[1] then
    return nil
  end

  local ret = {}
  for i, v in ipairs(cap) do
    local n = compiled[2][i]
    ret[n] = compiled[3][i] == "s" and v or tonumber(v)
  end

  return unpack(ret, 1, compiled[4])
end

--
-- This portion of this file (through to the end) was not written by me. It was a link given to me by Adys on
-- #wowuidev@irc.freenode.net. Many thanks for this code. It has been modified to suit Kore so any bugs are mine.
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

local korett = CreateFrame("GameTooltip", "KoreUTooltip", UIParent, "GameTooltipTemplate")
korett:SetOwner(UIParent, "ANCHOR_PRESERVE")
korett:SetPoint("CENTER", "UIParent")
korett:Hide()

local function SetTooltipHack(link)
  korett:SetOwner(UIParent, "ANCHOR_PRESERVE")
  korett:SetHyperlink("spell:1")
  korett:Show()
  korett:SetHyperlink(link)
end

local function UnsetTooltipHack()
  korett:SetOwner(UIParent, "ANCHOR_PRESERVE")
  korett:Hide()
end

function K.ScanTooltip(link)
  --
  -- The game's own tooltip data, where the client has it, rather than a hidden tooltip frame, which on retail may be given
  -- nothing to show. Each line reads as the frame's would, left and right joined by a tab, and a line whose text the client
  -- keeps secret is left out.
  --
  local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)

  if (data and data.lines) then
    local out = {}

    for _, line in ipairs(data.lines) do
      local left = K.CanAccess(line.leftText) and line.leftText or nil
      local right = K.CanAccess(line.rightText) and line.rightText or nil

      if (left and left ~= "") then
        out[#out + 1] = ((right and right ~= "") and (left .. "\t" .. right) or left) .. "\n"
      elseif (right and right ~= "") then
        out[#out + 1] = right .. "\n"
      end
    end

    return tconcat(out, "")
  end

  SetTooltipHack(link)

  local lines = korett:NumLines()
  local tooltiptxt = ""

  for i = 1, lines do
    local left = _G["KoreUTooltipTextLeft"..i]:GetText()
    local right = _G["KoreUTooltipTextRight"..i]:GetText()

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

  UnsetTooltipHack()
  return tooltiptxt
end

--[[ NOT CURRENTLY USED
function K.GetTooltipLine(link, line, side)
  side = side or "Left"
  SetTooltipHack(link)

  local lines = korett:NumLines()
  if (line > lines) then
    return UnsetTooltipHack()
  end

  local text = _G["KoreUTooltipText"..side..line]:GetText()
  UnsetTooltipHack()
  return text
end

function K.GetTooltipLines(link, ...)
  local lines = {}
  SetTooltipHack(link)

  for k,v in pairs({...}) do
    lines[#lines+1] = _G["KoreUTooltipTextLeft"..v]:GetText()
  end

  UnsetTooltipHack()
  return unpack(lines)
end
]]

