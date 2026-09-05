--[[
   KahLua Kore - static global reference checker.

   Finds every global read and write in a set of Lua files, so that accidental
   globals (a missing "local", a typo, a function used above the line that
   defines it) show up before they reach a raid. Unlike a runtime _G metatable
   guard this sees code that never executes, which is where most such bugs
   hide -- error paths, tie-break rolls, truncated message handlers.

   Requires luajit; it reads compiled bytecode rather than parsing source.

     luajit kore/tools/findglobals.lua konfer/*.lua kore/*.lua

   Anything printed is either a real WoW or Lua global (fine) or a bug. Add
   known-good names to the KNOWN table below to quieten the output.
]]

local jutil = require("jit.util")
local bcnames = require("jit.vmdef").bcnames

--
-- Globals we expect to see: the Lua standard library plus the WoW API surface
-- this codebase actually uses. Anything not in here gets reported.
--
local KNOWN = {}

for w in ([[
_G assert bit collectgarbage date difftime error format getmetatable geterrorhandler
ipairs loadstring math max min next pairs pcall print rawget rawset select
setmetatable string table time tonumber tostring type unpack xpcall
gmatch gsub strbyte strchar strfind strformat strjoin strlen strlower strmatch
strrep strsplit strsub strtrim strupper tinsert tremove wipe floor ceil abs
LibStub CreateFrame UIParent GameTooltip GameTooltip_SetDefaultAnchor
DEFAULT_CHAT_FRAME SlashCmdList UISpecialFrames hooksecurefunc securecall
InCombatLockdown GetTime GetLocale GetScreenWidth GetScreenHeight
GetExpansionLevel MAX_PLAYER_LEVEL_TABLE MAX_RAID_MEMBERS NUM_RAID_GROUPS
UnitName UnitFullName UnitGUID UnitClass UnitLevel UnitExists UnitIsConnected
UnitIsDeadOrGhost UnitIsAFK UnitIsInMyGuild UnitFactionGroup UnitHealthMax
UnitPowerMax UnitPowerType UnitInRange UnitInBattleground UnitIsGroupLeader
UnitIsGroupAssistant CheckInteractDistance IsInGroup IsInRaid IsInGuild
IsInInstance IsLoggedIn IsGuildLeader IsShiftKeyDown IsModifiedClick
GetNumGroupMembers GetNumSubgroupMembers GetNumRaidMembers GetNumPartyMembers
GetRaidRosterInfo GetPartyAssignment GetGuildInfo GetGuildRosterInfo
GetNumGuildMembers GuildControlGetNumRanks GuildControlGetRankName
GetNumSavedInstances GetSavedInstanceInfo RequestRaidInfo GetGameTime
C_GuildInfo C_PartyInfo C_Item C_Container C_Timer C_ChatInfo Enum
GetItemInfo GetItemInfoInstant GetLootMethod GetLootThreshold GetNumLootItems
GetLootSlotInfo GetLootSlotLink LootSlotHasItem GiveMasterLoot
GetMasterLootCandidate GetSpellInfo SendChatMessage RandomRoll
RANDOM_ROLL_RESULT OPENING WEAPON ITEM_CLASSES_ALLOWED ITEM_BIND_ON_PICKUP
ITEM_BIND_ON_EQUIP ITEM_QUALITY_COLORS RAID_CLASS_COLORS NORMAL_FONT_COLOR
HIGHLIGHT_FONT_COLOR FillLocalizedClassList Ambiguate SetDesaturation
ChatEdit_InsertLink ChatFrame_AddMessageEventFilter
ChatFrame_RemoveMessageEventFilter PanelTemplates_SetTab
PanelTemplates_SelectTab PanelTemplates_SetNumTabs PanelTemplates_TabResize
BackdropTemplateMixin
]]):gmatch("%S+") do
  KNOWN[w] = true
end

-- Prefix matches, for the large families of Blizzard constants.
local KNOWN_PREFIX = { "INVTYPE_", "ITEM_QUALITY", "SLASH_", "Kore" }

local function known(name)
  if (KNOWN[name]) then
    return true
  end
  for _, p in ipairs(KNOWN_PREFIX) do
    if (name:sub(1, #p) == p) then
      return true
    end
  end
  return false
end

local function opname(ins)
  local op = bit.band(ins, 0xff)
  return (bcnames:sub(op * 6 + 1, op * 6 + 6):gsub("%s+$", ""))
end

local function scan(f, seen, out)
  if (seen[f]) then
    return
  end
  seen[f] = true

  local i = 1
  while true do
    local ins = jutil.funcbc(f, i)
    if (not ins) then
      break
    end
    local o = opname(ins)
    if (o == "GGET" or o == "GSET") then
      local d = bit.band(bit.rshift(ins, 16), 0xffff)
      local name = jutil.funck(f, -(d + 1))
      if (type(name) == "string" and not known(name)) then
        out[#out + 1] = {
          name = name, op = o, line = jutil.funcinfo(f, i).currentline,
        }
      end
    end
    i = i + 1
  end

  local k = -1
  while true do
    local ok, c = pcall(jutil.funck, f, k)
    if (not ok or c == nil) then
      break
    end
    if (type(c) == "proto") then
      scan(c, seen, out)
    end
    k = k - 1
  end
end

local nbad, nfiles = 0, 0

for _, path in ipairs({ ... }) do
  local chunk, err = loadfile(path)
  if (not chunk) then
    print(("%s: PARSE ERROR: %s"):format(path, tostring(err)))
    nbad = nbad + 1
  else
    nfiles = nfiles + 1
    local out = {}
    scan(chunk, {}, out)
    table.sort(out, function(a, b) return a.line < b.line end)
    for _, r in ipairs(out) do
      print(("%s:%d: %s global %q"):format(path, r.line,
        r.op == "GSET" and "writes" or "reads", r.name))
      nbad = nbad + 1
    end
  end
end

print(("-- %d file(s) checked, %d suspect global reference(s)"):format(nfiles, nbad))
os.exit(nbad > 0 and 1 or 0)
