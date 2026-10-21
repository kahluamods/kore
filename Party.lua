--[[
   KahLua Kore - party and raid monitoring.
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

local KOREPARTY_MAJOR = "KoreParty"
local KOREPARTY_MINOR = 1
local KRP, oldminor = LibStub:NewLibrary(KOREPARTY_MAJOR, KOREPARTY_MINOR)

if (not KRP) then
  return
end

local assert = assert
local GetNumRaidMembers = GetNumGroupMembers or GetNumRaidMembers
local GetNumPartyMembers = GetNumSubgroupMembers or GetNumPartyMembers

KRP.debug_id = KOREPARTY_MAJOR

local K, KM = LibStub:GetLibrary("Kore")
assert(K, "KoreParty requires Kore")
assert(tonumber(KM) >= 1, "KoreParty requires Kore r1 or later")
K:RegisterExtension(KRP, KOREPARTY_MAJOR, KOREPARTY_MINOR)

local printf = K.printf
local tinsert = table.insert
local tsort = table.sort
local tconcat = table.concat
local strfmt = string.format
local max, min = math.max, math.min
local unpack = unpack

local function debug(lvl,...)
  K.debug("kore", lvl, ...)
end

KRP.initialised = false

--
-- Whenever a user is in a raid they are automatically in a party too, which is their raid group. It may be useful to know
-- who the current group members are so we will maintain both lists.
--
-- KRP.in_party therefore doubles as what we used to call KRP.in_either because it is also set when a user in in a raid. Thus
-- KRP.in_party is true when a user is in a party, raid or BG, if they are in a raid, and in_bg if they are in a battleground.
--

-- Is the player in a party
KRP.in_party = false

-- Is the player in a raid
KRP.in_raid = false

-- Is the player in a battleground
KRP.in_bg = false

-- The number of other players in the party, not counting ourselves, as the game's GetNumSubgroupMembers counts them.
KRP.num_party = 0
KRP.num_raid = 0

-- The raid sub-group the player is in, or 0 if not in a raid.
KRP.subgroup = 0

-- The raid ID for the player. This is the X in unit name "raidX". 0 if not in a raid.
KRP.raidid = 0

-- Is the player both in a party and the party leader
KRP.is_pl = false

-- Is the player both in a raid and the raid leader
KRP.is_rl = false

-- Is the player both in a raid and the raid leader OR an assistant
KRP.is_aorl = false

-- Is the player both in a party / raid and the master looter
KRP.is_ml = false

-- Which party member (0 for player) is the master looter, or nil if none.
KRP.party_mlid = nil

-- Which raid member is the master looter, or nil if none.
KRP.raid_mlid = nil

-- Full name of the current master looter or nil if none.
KRP.master_looter = nil

-- Full name of the current party or raid leader or nil if none.
KRP.leader = nil

-- The list of players in the party or raid, or nil if not in one.
-- Each element in the table is indexed by the full player name, and is itself
-- a table with the following members:
--   .name - same as the index - the full player name
--   .level - the player level
--   .class - the player's class (K.ClassIndex)
--   .faction - players faction
--   .is_guilded - true if the player is in our guild
--   .guildrankidx - guild rank index if in our guild
--   .is_gm - true if the player is our guild GM
--   .unitid - the unit ID (party3, raid17, player etc)
--   .subgroup - the raid subgroup or 0 if we're in a party not a raid
--   .raidid - the X in raidX if we are in a raid
--   .partyid - the X in partyX, 0 for ourselves
--   .is_pl - true if player is the party leader, false otherwise
--   .is_rl - true if the player is the raid leader, false otherwise
--   .is_aorl - true if player is raid leader OR assist, false otherwise
--   .is_ml - true if the player is the master looter
--   .group_role - GROUP_ROLE_NONE for party members, or NONE, TANK or ASSIST
--   .assigned - the role they have taken in the group, an ASSIGNED_ constant (see THE ROLES TAKEN)
--   .assignedrole - the same as one of Kore's K.ROLE_, damage told apart as melee, ranged or caster, or nil
--   .online - true if the player is online otherwise false
--   .dead - true if the player is dead false otherwise
--   .afk - true if teh player is AFK false otherwise
--   .guid - unit GUID
--   .maxhp - player's max HP
--   .powertype - player's power type (MANA, RAGE, ENERGY etc)
--   .maxpower - players maximum power
--   .cantrade - true if they are within trading distance otherwise false
--   .inrange - true if unit is in range
KRP.players = nil

-- The list of player names in the players party. Includes us.
KRP.party = nil

-- The list of players in the raid or nil if not in a raid.
KRP.raid = nil

-- The list of players in the various raid groups or nil if not in a raid. This is an array of 8 tables when it is non-nil.
KRP.raidgroups = nil

-- @debug-start@
--
-- A pretend group, for trying out what a mod does in a raid with nobody else there. While this holds a roster, the group is
-- that roster rather than what the game says: a raid, led by the player, who is also its master looter, with everybody in
-- it online and in range. Nothing is ever sent to it, there being nobody there, and group chat is shown to the player
-- instead (Comms.lua). Nil when the group is the game's. Set with KRP:PretendGroup. A development copy's alone: a packaged
-- one has none of it, and everything that asks after KRP.pretend finds it nil.
--
-- An array of { name, class, level }, name being the canonical Name-Realm and class the Kore class number. The player need
-- not be in it and is put at its head. What the group is asked to change about somebody (see ASKING THE GAME TO CHANGE THE
-- GROUP) is kept on their entry, as assistant, role ("MAINTANK" or "MAINASSIST") and mark, and the player's own in
-- KRP.pretendself. Who leads and who master loots stay the player.
--
KRP.pretend = nil
KRP.pretendself = {}
-- @debug-end@

KRP.LOOT_METHOD_FREEFORALL  = Enum.LootMethod.Freeforall
KRP.LOOT_METHOD_ROUNDROBIN  = Enum.LootMethod.Roundrobin
KRP.LOOT_METHOD_MASTER      = Enum.LootMethod.Masterlooter
KRP.LOOT_METHOD_GROUP       = Enum.LootMethod.Group
KRP.LOOT_METHOD_NEEDB4GREED = Enum.LootMethod.Needbeforegreed
KRP.LOOT_METHOD_PERSONAL    = Enum.LootMethod.Personal

local LOOT_METHOD_FREEFORALL  = KRP.LOOT_METHOD_FREEFORALL
local LOOT_METHOD_MASTER      = KRP.LOOT_METHOD_MASTER

-- Party or raid loot method
KRP.loot_method = LOOT_METHOD_FREEFORALL

-- Loot threshold
KRP.loot_threshold = 0

KRP.GROUP_ROLE_NONE   = 0
KRP.GROUP_ROLE_TANK   = 1
KRP.GROUP_ROLE_ASSIST = 2

local GROUP_ROLE_NONE   = KRP.GROUP_ROLE_NONE
local GROUP_ROLE_TANK   = KRP.GROUP_ROLE_TANK
local GROUP_ROLE_ASSIST = KRP.GROUP_ROLE_ASSIST

local group_role_to_number = {
  ["NONE"]       = GROUP_ROLE_NONE,
  ["MAINTANK"]   = GROUP_ROLE_TANK,
  ["MAINASSIST"] = GROUP_ROLE_ASSIST,
}

KRP.RC_NOCHECK  = 0
KRP.RC_READY    = 1
KRP.RC_NOTREADY = 2
KRP.RC_WAITING  = 3
KRP.RC_AWAY     = 4

local RC_NOCHECK  = KRP.RC_NOCHECK
local RC_READY    = KRP.RC_READY
local RC_NOTREADY = KRP.RC_NOTREADY
local RC_WAITING  = KRP.RC_WAITING
local RC_AWAY     = KRP.RC_AWAY

local rc_to_number = {
  ["none"]     = RC_NOCHECK,
  ["ready"]    = RC_READY,
  ["notready"] = RC_NOTREADY,
  ["waiting"]  = RC_WAITING,
  ["away"]     = RC_AWAY,
}

KRP.ready_checking = false

-- When the last ready check ended, as GetTime gives it, or nil while one runs or none has. Its answers stay in KRP.ready.
KRP.ready_ended = nil

--
-- What somebody in the group can hold that the raid frames mark: master looter, the group's leader (a raid's or a party's),
-- one of a raid's assistants, its main tank and its main assist. KRP.statuses is who held which at the last look, by name,
-- each a set of these, and status_changed (name, status, onoff) is fired for every one gained or lost since, so a listener
-- hears of each change to anybody whatever brought it about.
--
KRP.STATUS_ML = "ml"
KRP.STATUS_RL = "rl"
KRP.STATUS_RA = "ra"
KRP.STATUS_MT = "mt"
KRP.STATUS_MA = "ma"

KRP.statuses = {}

--
-- The marks somebody can be given as a raid target, by the game's own numbers. Each player's is .mark, nil for none, read as
-- the group is scanned and again whenever a mark moves (RAID_TARGET_UPDATE). Retail tells an addon that a mark is worn but
-- not which, the number coming back secret, and such a mark is the one this client noted putting on them, or 0 where it put
-- none (marknotes): KRP:DrawMark still shows the real one, the texture being handed the secret as it is. KRP.marks is
-- everybody's at the last look, by name, and mark_changed (name, mark, old) is fired for everybody whose mark is not what it
-- was, nil being none, and at every look for one that could not be read, which may have moved unseen.
--
KRP.MARK_STAR     = 1
KRP.MARK_CIRCLE   = 2
KRP.MARK_DIAMOND  = 3
KRP.MARK_TRIANGLE = 4
KRP.MARK_MOON     = 5
KRP.MARK_SQUARE   = 6
KRP.MARK_CROSS    = 7
KRP.MARK_SKULL    = 8

KRP.marks = {}

--
-- How each mark is shown, as the game's own menus show it: its name in the game's words (RAID_TARGET_1 and on), its colour,
-- and its square of KRP.MARK_TEXTURE, the game's sheet of them, four to a row.
--
KRP.MARK_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local MARK_COLOURS = {
  { 1, 0.92, 0 }, { 0.98, 0.57, 0 }, { 0.83, 0.22, 0.9 }, { 0.04, 0.95, 0 },
  { 0.7, 0.82, 0.875 }, { 0, 0.71, 1 }, { 1, 0.24, 0.168 }, { 0.98, 0.98, 0.98 },
}

-- The name of MARK, its colour as { r, g, b } and its square of KRP.MARK_TEXTURE as { left, right, top, bottom }, or nil.
function KRP.MarkInfo(mark)
  local c = MARK_COLOURS[mark]

  if (not c) then
    return nil
  end

  local col, row = (mark - 1) % 4, math.floor((mark - 1) / 4)

  return _G["RAID_TARGET_" .. mark], { r = c[1], g = c[2], b = c[3] },
    { left = col / 4, right = (col + 1) / 4, top = row / 4, bottom = (row + 1) / 4 }
end

--
-- Show the mark NAME wears on the texture TEX, as the raid frames do, or hide it for none, answering which. The mark is read
-- afresh and handed straight to the texture, whose SetSpriteSheetCell takes one that retail keeps secret, so that a mark
-- this cannot read (.mark 0) is still drawn.
--
function KRP:DrawMark(tex, name)
  local p = KRP.players and KRP.players[name]
  local mark = p and p.unitid and GetRaidTargetIndex(p.unitid)

  -- @debug-start@
  if (p and KRP.pretend) then
    mark = p.pretendmark
  end
  -- @debug-end@

  if (mark == nil) then
    tex:Hide()
    return false
  end

  tex:SetTexture(KRP.MARK_TEXTURE)
  tex:SetSpriteSheetCell(mark, 4, 4)
  tex:Show()

  return true
end

--
-- THE ROLES TAKEN
--
-- The role somebody has taken in the group, tank, healer or damage, as they pick it when the game asks (its role check) or
-- from its menus, and as the raid frames show it. It is what they have said they are doing in this group, never what Kore
-- knows a character can play (K.ROLE_), and it has nothing to do with the main tank or main assist (.group_role). Each
-- player's is .assigned, ASSIGNED_NONE where they have taken none, read as the group is scanned and again whenever the game
-- says roles have moved (PLAYER_ROLES_ASSIGNED). KRP.assigned is everybody's at the last look, by name, and
-- assigned_changed (name, role, old) is fired for everybody whose role is not what it was, ASSIGNED_NONE for somebody not
-- there. KRP:AssignedTo says who has taken one.
--
-- The game knows only the three, and Kore tells damage apart as melee, ranged and caster. So .assignedrole is the role
-- taken as one of Kore's own (K.ROLE_): a tank's and a healer's straight from the game, and damage the kind picked for them
-- through KRP:SetAssigned, kept by name in KRP.picked for as long as they are in the group and never saved, or failing that
-- the kind of damage they are recorded as playing, main spec first (KU:Roles), or failing that the kind their class is first
-- thought of as dealing (K.ClassDamage), a guess the user can put right. Nil where they have taken no role. It is the
-- raid's, and never written into anybody's record. assigned_changed is fired when it moves as well, ROLE and OLD then being
-- the same. KRP:IsTank and its fellows ask it of one player.
--
KRP.ASSIGNED_NONE   = 0
KRP.ASSIGNED_TANK   = 1
KRP.ASSIGNED_HEALER = 2
KRP.ASSIGNED_DAMAGE = 3

local ASSIGNED_NONE = KRP.ASSIGNED_NONE

local assigned_to_number = {
  ["TANK"]    = KRP.ASSIGNED_TANK,
  ["HEALER"]  = KRP.ASSIGNED_HEALER,
  ["DAMAGER"] = KRP.ASSIGNED_DAMAGE,
}

-- What the game is told for each of Kore's roles, every kind of damage being the one to it.
local role_to_game = {
  [K.ROLE_TANK]   = "TANK",
  [K.ROLE_HEALER] = "HEALER",
  [K.ROLE_MELEE]  = "DAMAGER",
  [K.ROLE_RANGED] = "DAMAGER",
  [K.ROLE_CASTER] = "DAMAGER",
}

KRP.assigned = {}
KRP.assignedroles = {}
KRP.picked = {}

-------------------------------------------------------------------------------

KRP.addons = {}
KRP.valid_callbacks = {
  ["new_player"] = true,
  ["update_group_start"] = true,
  ["update_group_end"] = true,
  ["in_group_changed"] = true,
  ["loot_method"] = true,
  ["leader_changed"] = true,
  ["role_changed"] = true,
  ["status_changed"] = true,
  ["mark_changed"] = true,
  ["assigned_changed"] = true,
  ["group_id_changed"] = true,
  ["in_party_changed"] = true,
  ["in_raid_changed"] = true,
  ["in_bg_changed"] = true,
  ["readycheck_start"] = true,
  ["readycheck_reply"] = true,
  ["readycheck_end"] = true,
}

--
-- Who in the group holds what now, as KRP.statuses keeps it. The master looter is the one KRP.master_looter names, a player's
-- own flag being left as it was when the loot method stops being master loot.
--
local function current_statuses()
  local out = {}

  for name, p in pairs(KRP.players or {}) do
    local s = {}
    local leads = p.is_rl or (not KRP.in_raid and p.is_pl)

    s[KRP.STATUS_ML] = (name == KRP.master_looter) or nil
    s[KRP.STATUS_RL] = leads or nil
    s[KRP.STATUS_RA] = (KRP.in_raid and p.is_aorl and not leads) or nil
    s[KRP.STATUS_MT] = (p.group_role == GROUP_ROLE_TANK) or nil
    s[KRP.STATUS_MA] = (p.group_role == GROUP_ROLE_ASSIST) or nil
    out[name] = s
  end

  return out
end

--
-- Fire status_changed for everything somebody has lost and then everything somebody has gained since the last look, and keep
-- what is held now for the next. Called after anything that may have moved one, and quiet where nothing has.
--
local function fire_status_changes()
  local was, now = KRP.statuses or {}, current_statuses()

  KRP.statuses = now

  for name, held in pairs(was) do
    for status in pairs(held) do
      if (not (now[name] and now[name][status])) then
        KRP:DoCallbacks("status_changed", name, status, false)
      end
    end
  end

  for name, held in pairs(now) do
    for status in pairs(held) do
      if (not (was[name] and was[name][status])) then
        KRP:DoCallbacks("status_changed", name, status, true)
      end
    end
  end
end

--
-- The marks this client has put on people itself, by name, which is how retail's secret marks are known by their number
-- after all. Every mark this client sets goes through the game's SetRaidTarget, from Kore's secure buttons (KRP:MarkAction),
-- the game's own menus or /tm, and the call is watched, its arguments being plain. A mark is one target's at a time, so one
-- noted on anybody, or put on anything else, goes from whoever had it. A note goes when its wearer is found wearing none.
-- Somebody else changing the mark on a raider who stays marked is not seen, and that note is wrong until this client next
-- marks them.
--
local marknotes = {}

-- Who in the group the unit token UNIT is, by name: the token itself, or the game's word that it is the same unit, which may
-- be secret and is then nobody.
local function unit_member(unit)
  for name, p in pairs(KRP.players or {}) do
    if (p.unitid == unit) then
      return name
    end
  end

  for name, p in pairs(KRP.players or {}) do
    local same = p.unitid and UnitIsUnit(unit, p.unitid)

    if (K.CanAccess(same) and same) then
      return name
    end
  end

  return nil
end

if (type(SetRaidTarget) == "function") then
  hooksecurefunc("SetRaidTarget", function(unit, index)
    if (not K.CanAccess(unit) or not K.CanAccess(index) or type(unit) ~= "string") then
      return
    end

    index = tonumber(index) or 0

    if (index > 0) then
      for name, m in pairs(marknotes) do
        if (m == index) then
          marknotes[name] = nil
        end
      end
    end

    local name = unit_member(unit)

    if (name) then
      marknotes[name] = (index > 0) and index or nil
    end
  end)
end

--
-- The mark the player NAME, P, wears as a raid target, or nil, and whether the game let it be read. Retail hands it back
-- secret, and only comparing it with nil is allowed of one, which is all that is asked of it here: a secret mark is what
-- this client noted putting on them, or 0. A pretend group's marks are its own, there being no unit to ask.
--
local function player_mark(name, p)
  -- @debug-start@
  if (KRP.pretend) then
    return p.pretendmark, true
  end
  -- @debug-end@

  local mark = p.unitid and GetRaidTargetIndex(p.unitid)

  if (mark == nil) then
    marknotes[name] = nil
    return nil, true
  end

  if (K.CanAccess(mark)) then
    return mark, true
  end

  return marknotes[name] or 0, false
end

--
-- Read everybody's mark afresh, fire mark_changed for everybody whose mark has moved since the last look, and keep what is
-- worn now for the next. A mark that could not be read may have moved unseen, so it is told of at every look.
--
local unread = {}

local function fire_mark_changes()
  local was, now = KRP.marks or {}, {}
  local wasunread = unread

  unread = {}

  for name, p in pairs(KRP.players or {}) do
    local seen

    p.mark, seen = player_mark(name, p)
    now[name] = p.mark
    unread[name] = (not seen) or nil
  end

  KRP.marks = now

  for name, old in pairs(was) do
    if (now[name] ~= old or unread[name] or wasunread[name]) then
      KRP:DoCallbacks("mark_changed", name, now[name], old)
    end
  end

  for name, mark in pairs(now) do
    if (was[name] == nil) then
      KRP:DoCallbacks("mark_changed", name, mark, nil)
    end
  end
end

--
-- The role the player P has taken, an ASSIGNED_ constant. Retail may hand it back secret inside an instance, and a role that
-- cannot be read is taken as none. A pretend group's roles are its own, there being no unit to ask.
--
local function player_assigned(p)
  -- @debug-start@
  if (KRP.pretend) then
    return p.pretendassigned or ASSIGNED_NONE
  end
  -- @debug-end@

  local role = p.unitid and UnitGroupRolesAssigned(p.unitid)

  if (role == nil or not K.CanAccess(role)) then
    return ASSIGNED_NONE
  end

  return assigned_to_number[role] or ASSIGNED_NONE
end

local function is_damage(role)
  return role_to_game[role] == "DAMAGER"
end

--
-- The role P plays as one of Kore's, from ASSIGNED, what they have taken in the game: the kind of damage picked for them, or
-- failing that the one they are recorded as playing, main spec first, or failing that the one their class is first thought
-- of as dealing.
--
local function player_assigned_role(p, assigned)
  if (assigned == KRP.ASSIGNED_TANK) then
    return K.ROLE_TANK
  elseif (assigned == KRP.ASSIGNED_HEALER) then
    return K.ROLE_HEALER
  elseif (assigned ~= KRP.ASSIGNED_DAMAGE) then
    return nil
  end

  if (KRP.picked[p.name]) then
    return KRP.picked[p.name]
  end

  local KU = K.Users
  local kuid = KU and KU:Find(p.name)

  if (kuid) then
    local ms, os = KU:Roles(kuid)

    if (is_damage(ms)) then
      return ms
    elseif (is_damage(os)) then
      return os
    end
  end

  return p.class and K.ClassDamage[p.class] or nil
end

--
-- Read everybody's role afresh, fire assigned_changed for everybody whose role has moved since the last look, and keep what
-- is held now for the next. A pick goes with somebody who has left the group.
--
local function fire_assigned_changes()
  local was, wasrole = KRP.assigned or {}, KRP.assignedroles or {}
  local now, nowrole = {}, {}

  for name, p in pairs(KRP.players or {}) do
    p.assigned = player_assigned(p)
    p.assignedrole = player_assigned_role(p, p.assigned)
    now[name] = p.assigned
    nowrole[name] = p.assignedrole
  end

  for name in pairs(KRP.picked) do
    if (not now[name]) then
      KRP.picked[name] = nil
    end
  end

  KRP.assigned = now
  KRP.assignedroles = nowrole

  for name, old in pairs(was) do
    local role = now[name] or ASSIGNED_NONE

    if (role ~= old or nowrole[name] ~= wasrole[name]) then
      KRP:DoCallbacks("assigned_changed", name, role, old)
    end
  end

  for name, role in pairs(now) do
    if (was[name] == nil and (role ~= ASSIGNED_NONE or nowrole[name] ~= nil)) then
      KRP:DoCallbacks("assigned_changed", name, role, ASSIGNED_NONE)
    end
  end
end

--
-- Everybody in the group who has taken ROLE, an ASSIGNED_ constant, by name and sorted, and an empty table where nobody has
-- or there is no group. The healers are KRP:AssignedTo(KRP.ASSIGNED_HEALER).
--
function KRP:AssignedTo(role)
  local out = {}

  for name, p in pairs(self.players or {}) do
    if (p.assigned == role) then
      tinsert(out, name)
    end
  end

  tsort(out)

  return out
end

--
-- Whether NAME, in the group, plays a role: the role they have taken as one of Kore's (.assignedrole). IsDPS is any kind of
-- damage, and so somebody who has taken damage of no kind Kore knows as well.
--
local function plays(name, role)
  local p = KRP.players and KRP.players[name]

  return (p and p.assignedrole == role) and true or false
end

function KRP:IsTank(name)
  return plays(name, K.ROLE_TANK)
end

function KRP:IsHealer(name)
  return plays(name, K.ROLE_HEALER)
end

function KRP:IsMelee(name)
  return plays(name, K.ROLE_MELEE)
end

function KRP:IsRanged(name)
  return plays(name, K.ROLE_RANGED)
end

function KRP:IsCaster(name)
  return plays(name, K.ROLE_CASTER)
end

function KRP:IsDPS(name)
  local p = KRP.players and KRP.players[name]

  return (p and p.assigned == KRP.ASSIGNED_DAMAGE) and true or false
end

--
-- INVITING
--
-- A party holds five, so the invitations KRP:Invite cannot send wait in PENDING_INVITES while the party is made a raid,
-- which a party can be once somebody besides its leader is in it. That is done as soon as one is, and the rest are asked
-- when it is a raid, both as the group comes in. They are forgotten after INVITE_WAIT seconds, as the game forgets an
-- invitation nobody answers.
--
local INVITE_WAIT = 60
local MAX_PARTY = 5
local pending_invites = nil
local pending_until = 0

local function send_pending_invites()
  if (not pending_invites) then
    return
  end

  if (GetTime() > pending_until) then
    pending_invites = nil
    return
  end

  if (KRP.in_raid) then
    local names = pending_invites

    pending_invites = nil

    for _, name in ipairs(names) do
      if (not KRP.players[name]) then
        C_PartyInfo.InviteUnit(K.DisplayName(name))
      end
    end
  elseif (KRP.in_party and KRP.is_pl) then
    C_PartyInfo.ConvertToRaid()
  end
end

--
-- Reset ready check related variables
--
local function reset_ready()
  KRP.ready_checking = false
  KRP.ready = nil
  KRP.ready_timeout = nil
  KRP.ready_start = nil
  KRP.ready_ended = nil
end

--
-- THE GROUP'S OWN ID
--
-- The GUID the game gives the player's own group, as against a battleground's or the dungeon finder's, which are groups of
-- their own with ids of their own: KRP.group_id, nil when there is no group or the game has not said which. The game says
-- it as the group is formed or joined (GROUP_FORMED, GROUP_JOINED) and left (GROUP_LEFT) and at no other time, so it is kept
-- in K.chardb.groupid, where a reload, which says nothing, finds it again. What the game says always replaces what was
-- kept, and a look at the group that finds the player in none forgets it, which is how a login after the group broke up
-- while the player was away finds out. group_id_changed (id, old) is fired whenever it moves. A pretend group has an id of
-- its own, kept nowhere.
--
local HOME_GROUP = LE_PARTY_CATEGORY_HOME or 1

KRP.group_id = nil

local function set_group_id(id, unkept)
  local old = KRP.group_id

  KRP.group_id = id

  if (not unkept) then
    K.chardb.groupid = id
  end

  if (id ~= old) then
    KRP:DoCallbacks("group_id_changed", id, old)
  end
end

--
-- Utility function to reset loot method related variables.
--
local function reset_loot_method()
  KRP.is_ml = false
  KRP.master_looter = nil
  KRP.party_mlid = nil
  KRP.raid_mlid = nil
  KRP.loot_method = nil
  KRP.loot_threshold = 0
end

--
-- Utility function to reset leader related variables.
--
local function reset_group_leader()
  KRP.is_pl = false
  KRP.is_rl = false
  KRP.is_aorl = false
  KRP.leader = nil
end

--
-- Utility function to reset role related variables.
--
local function reset_role()
  KRP.group_role = GROUP_ROLE_NONE
end

--
-- Utility function to reset group related variables.
--
--
-- KEEPREADY is for a roster that has merely been walked again. A ready check in progress is about the group, which is still
-- there, and is not forgotten because somebody joined or moved.
--
local function reset_group(keepready)
  reset_group_leader()
  reset_loot_method()
  reset_role()
  if (not keepready) then
    reset_ready()
  end
  KRP.in_party = false
  KRP.in_raid = false
  KRP.in_bg = false
  KRP.num_party = 0
  KRP.num_raid = 0
  KRP.subgroup = 0
  KRP.raidid = 0
  KRP.raid = nil
  KRP.party = nil
  KRP.players = nil
  KRP.raidgroups = nil
end

local function update_loot_method_internal()
  reset_loot_method()

  if ((not KRP.in_party) or KRP.in_bg) then
    return
  end

  -- @debug-start@
  -- A pretend raid is the player's, and master looted by them.
  if (KRP.pretend) then
    KRP.loot_method = LOOT_METHOD_MASTER
    KRP.is_ml = true
    KRP.master_looter = K.player.name
    KRP.raid_mlid = KRP.raidid
    KRP.loot_threshold = GetLootThreshold()
    return
  end
  -- @debug-end@

  local lm, pmlid, rmlid = C_PartyInfo.GetLootMethod()
  local mlname = nil

  KRP.party_mlid = pmlid
  KRP.raid_mlid = rmlid
  KRP.loot_method = lm or LOOT_METHOD_FREEFORALL

  if (KRP.loot_method == LOOT_METHOD_MASTER) then
    if (pmlid ~= nil) then
      if (pmlid == 0) then
        mlname = K.player.name
      else
        mlname = K.FullUnitName("party" .. pmlid)
      end
    end
    if (rmlid ~= nil) then
      mlname = K.FullUnitName("raid" .. rmlid)
    end

    if (mlname and KRP.players) then
      for k, v in pairs(KRP.players) do
        if (v.is_ml) then
          if (k ~= mlname) then
            v.is_ml = false
          end
        end
        if (k == mlname) then
          v.is_ml = true
        end
      end
    end
  end

  if (mlname and mlname == K.player.name) then
    KRP.is_ml = true
  else
    KRP.is_ml = false
  end
  KRP.master_looter = mlname
  KRP.loot_threshold = GetLootThreshold()
end

--
-- Function: KRP.UpdateLootMethod()
-- Purpose : Updates the various loot method related settings, namely: loot_method, party_mlid, raid_mlid, master_looter, is_ml
-- Fires   : LOOT_METHOD_UPDATED(new_method_id)
--
function KRP.UpdateLootMethod(evtonly)
  if (not KRP.initialised) then
    return false
  end

  if (not evtonly) then
    update_loot_method_internal()
  end

  fire_status_changes()
  KRP:DoCallbacks("loot_method", KRP.loot_method)
end

local function update_leader_internal()
  local old_leader = KRP.leader
  local prn

  reset_group_leader()

  if (not KRP.in_party and not KRP.in_bg) then
    return
  end

  -- @debug-start@
  if (KRP.pretend) then
    KRP.is_rl = true
    KRP.is_aorl = true
    KRP.leader = K.player.name
    return
  end
  -- @debug-end@

  if (UnitIsGroupAssistant("player")) then
    KRP.is_aorl = true
  end

  if (UnitIsGroupLeader("player")) then
    if (KRP.in_party) then
      KRP.is_pl = true
    end
    if (KRP.in_raid) then
      KRP.is_pl = false
      KRP.is_rl = true
      KRP.is_aorl = true
    end
    if (KRP.is_pl or KRP.is_rl) then
      KRP.leader = K.player.name
    end
  else
    if (KRP.in_party and not KRP.in_raid and not KRP.in_bg) then
      local npm = GetNumPartyMembers()
      for i = 1, npm do
        prn = "party" .. i
        if (UnitExists(prn)) then
          if (UnitIsGroupLeader(prn)) then
            KRP.leader = K.FullUnitName(prn)
          end
        end
      end
    end

    if (KRP.in_raid) then
      local num_raiders = KRP.num_raid
      for i = 1, num_raiders do
        prn = "raid" .. i
        if (UnitExists(prn)) then
          if (UnitIsGroupLeader(prn)) then
            KRP.leader = K.FullUnitName(prn)
          end
        end
      end
    end
  end

  if (KRP.players) then
    if (old_leader and KRP.players[old_leader]) then
      KRP.players[old_leader].is_rl = false
      KRP.players[old_leader].is_pl = false
      KRP.players[old_leader].is_aorl = false
      if (KRP.in_raid) then
        prn = "raid" .. KRP.players[old_leader].raidid
        if (UnitIsGroupAssistant(prn)) then
          KRP.players[old_leader].is_aorl = true
        end
      end
    end

    prn = KRP.leader
    if (KRP.players[prn]) then
      KRP.players[prn].is_pl = true
      KRP.players[prn].is_rl = false
      KRP.players[prn].is_aorl = false
      if (KRP.in_raid) then
        KRP.players[prn].is_pl = false
        KRP.players[prn].is_rl = true
        KRP.players[prn].is_aorl = true
      end
    end
  end
end

--
-- Function: KRP.UpdateLeader()
-- Purpose : Updates the various group leader related settings, namely: is_pl, is_rl, is_aorl, leader.
-- Fires   : LEADER_CHANGED()
--
function KRP.UpdateLeader(evtonly)
  if (not KRP.initialised) then
    return false
  end

  local old_leader = KRP.leader

  if (not evtonly) then
    update_leader_internal()
  end

  fire_status_changes()

  if (old_leader ~= KRP.leader) then
    KRP:DoCallbacks("leader_changed")
  end
end

local function update_role_internal()
  reset_role()

  if (not KRP.in_party and not KRP.in_bg) then
    return
  end

  -- @debug-start@
  -- A pretend group's assignments are its own, the game having none to give.
  if (KRP.pretend) then
    KRP.group_role = group_role_to_number[KRP.pretendself.role or "NONE"] or GROUP_ROLE_NONE

    if (KRP.players and KRP.players[K.player.name]) then
      KRP.players[K.player.name].group_role = KRP.group_role
    end

    return
  end
  -- @debug-end@

  if (GetPartyAssignment("MAINTANK", "player")) then
    KRP.group_role = GROUP_ROLE_TANK
  elseif (GetPartyAssignment("MAINASSIST", "player")) then
    KRP.group_role = GROUP_ROLE_ASSIST
  else
    KRP.group_role = GROUP_ROLE_NONE
  end

  if (KRP.players and KRP.players[K.player.name]) then
    KRP.players[K.player.name].group_role = KRP.group_role
  end
end

--
-- Function: KRP.UpdateRole()
-- Purpose : Updates the group role variable: group_role.
-- Fires   : ROLE_CHANGED(role)
--
function KRP.UpdateRole(evtonly)
  if (not KRP.initialised) then
    return false
  end

  local old_role = KRP.group_role

  if (not evtonly) then
    update_role_internal()
  end

  fire_status_changes()

  if (KRP.group_role ~= old_role) then
    KRP:DoCallbacks("role_changed")
  end
end

local krp_flag_events = false

--
-- This function updates various unit flags. Some small amount of code from
-- UpdateLeader() is duplicated here. This function is called from two places
-- with very different data access requirements, hence the long argument list.
-- First, it is called from the populate_unit() closure, during which time none
-- of the group variables are valid yet. Secondly it is called from an event
-- handler for UNIT_FLAGS, when the group variables ARE in place.
--
local function update_unit_flags(unm, pt, in_party, in_raid, players)
  local urn

  local inparty = in_party or KRP.in_party
  local inraid = in_raid or KRP.in_raid
  local plist = players or KRP.players

  if (pt) then
    urn = pt.name
  else
    urn = K.FullUnitName(unm)
  end

  if (not urn or urn == "" or urn == "Unknown") then
    return
  end

  if (not pt) then
    if (not plist or not plist[urn]) then
      return
    end
  end

  local ptbl = pt or plist[urn]
  if (not ptbl) then
    return
  end

  if (UnitExists(unm)) then
    if (UnitIsConnected(unm)) then
      ptbl.online = true
    else
      ptbl.online = false
    end
    if (UnitIsDeadOrGhost(unm)) then
      ptbl.dead = true
    else
      ptbl.dead = false
    end
    --
    -- Retail keeps whether someone is away secret inside dungeons and raids, and its range check secret everywhere. A value
    -- that cannot be read counts as present and in range, which is also what an unchecked range means below.
    --
    local afk = UnitIsAFK(unm)
    if (K.CanAccess(afk) and afk) then
      ptbl.afk = true
    else
      ptbl.afk = false
    end
    ptbl.guid = UnitGUID(unm)
    ptbl.maxhp = UnitHealthMax(unm) or 0
    local _, powertype = UnitPowerType(unm)
    ptbl.powertype = powertype or "MANA" -- Fall back to mana as a default
    ptbl.maxpower = UnitPowerMax(unm) or 0
    if InCombatLockdown() then
      ptbl.cantrade = false
    else
      ptbl.cantrade = CheckInteractDistance(unm, 2) or false
    end
    local irange, rced = UnitInRange(unm)
    if (K.CanAccess(irange) and K.CanAccess(rced) and rced and not irange) then
      ptbl.inrange = false
    else
      ptbl.inrange = true
    end
    ptbl.is_aorl = false
    ptbl.is_pl = false
    ptbl.is_rl = false
    if (UnitIsGroupLeader(unm)) then
      if (inparty) then
        ptbl.is_pl = true
      end
      if (inraid) then
        ptbl.is_pl = false
        ptbl.is_rl = true
        ptbl.is_aorl = true
      end
    end

    -- An assistant is not the leader, so is asked about in their own right.
    if (inraid and UnitIsGroupAssistant(unm)) then
      ptbl.is_aorl = true
    end
  end
end

-- @debug-start@
--
-- The group as KRP.pretend has it, built the way the game's is and handed to listeners the same way, so that nothing
-- listening can tell. The player heads it, in group one, and the rest follow five to a group in the order the roster gives.
-- Whatever the game could say about a unit is taken to be what a raid most wants: online, alive, here and in range.
--
local function pretend_group(fire_party, fire_raid, fire_bg)
  local old_inparty, old_inraid, old_inbg = KRP.in_party, KRP.in_raid, KRP.in_bg
  local players, raid, raidgroups = {}, {}, {}
  local myself = KRP.pretendself
  local roster = {
    { name = K.player.name, class = K.player.class, level = K.player.level, role = myself.role, mark = myself.mark },
  }

  for _, m in ipairs(KRP.pretend) do
    if (m.name ~= K.player.name and #roster < NUM_RAID_GROUPS * 5) then
      tinsert(roster, m)
    end
  end

  KRP:DoCallbacks("update_group_start", old_inparty, old_inraid, old_inbg)

  for i = 1, NUM_RAID_GROUPS do
    raidgroups[i] = {}
  end

  for i, m in ipairs(roster) do
    local me = (i == 1)
    local kgi = K.player.is_guilded and K.guild.roster.name[m.name]
    local rank = kgi and K.guild.roster.id[kgi] and K.guild.roster.id[kgi].rank or 0
    local p = {
      name = m.name, level = m.level or K.player.level, class = m.class, faction = K.player.faction,
      is_guilded = kgi and true or false, guildrankidx = rank, is_gm = (rank == 1),
      unitid = me and "player" or ("raid" .. i), subgroup = math.floor((i - 1) / 5) + 1, raidid = i, partyid = 0,
      is_pl = false, is_rl = me, is_aorl = me or (m.assistant and true or false), is_ml = me,
      group_role = group_role_to_number[m.role or "NONE"] or GROUP_ROLE_NONE, pretendmark = m.mark,
      pretendassigned = m.assigned,
      online = true, dead = false, afk = false, inrange = true, cantrade = false, maxhp = 0, powertype = "MANA", maxpower = 0,
    }

    players[p.name] = p
    raid[i] = p.name
    tinsert(raidgroups[p.subgroup], p.name)
    KRP:DoCallbacks("new_player", p)
  end

  reset_group(true)

  KRP.players = players
  KRP.party = nil
  KRP.raid = raid
  KRP.raidgroups = raidgroups
  KRP.num_raid = #roster
  KRP.num_party = 0
  KRP.in_party = true
  KRP.in_raid = true
  KRP.in_bg = false
  KRP.subgroup = 1
  KRP.raidid = 1

  update_loot_method_internal()
  update_leader_internal()
  update_role_internal()

  if (fire_party or not old_inparty) then
    KRP:DoCallbacks("in_party_changed", true)
  end

  if (fire_raid or not old_inraid) then
    KRP:DoCallbacks("in_raid_changed", true)
  end

  if (fire_bg or old_inbg) then
    KRP:DoCallbacks("in_bg_changed", false)
  end

  fire_status_changes()
  fire_mark_changes()
  fire_assigned_changes()
  KRP:DoCallbacks("in_group_changed", true, true, false)
  KRP:DoCallbacks("update_group_end", true, true, false)

  return true
end
-- @debug-end@

local function update_group_internal(fire_party, fire_raid, fire_bg)
  if (not KRP.initialised) then
    return false
  end

  -- @debug-start@
  if (KRP.pretend and K.local_realm and K.local_realm ~= "") then
    return pretend_group(fire_party, fire_raid, fire_bg)
  end
  -- @debug-end@

  local old_inparty = KRP.in_party
  local old_inraid = KRP.in_raid
  local old_inbg = KRP.in_bg
  local in_party, in_raid, in_bg = false, false, false
  local changed = false
  local players, party, raid, raidgroups
  local nrm = GetNumRaidMembers()
  local npm = GetNumPartyMembers()
  local _, itype = IsInInstance()
  local prn

  if (not K.local_realm or K.local_realm == "") then
    return false
  end

  KRP:DoCallbacks("update_group_start", old_inparty, old_inraid, old_inbg)

  -- Every exit path from here owes listeners the matching update_group_end.
  local function bail()
    KRP:DoCallbacks("update_group_end", KRP.in_party, KRP.in_raid, KRP.in_bg)
    return false
  end

  if (IsInGroup()) then
    in_party = true
  end

  if (IsInRaid()) then
    in_raid = true
    in_party = true
  end

  if ((itype == "pvp") or (itype == "arena") or UnitInBattleground("player")) then
    in_bg = true
  end

  if (not in_bg and not in_party) then
    if (krp_flag_events) then
      KRP:UnregisterEvent("PLAYER_FLAGS_CHANGED")
      krp_flag_events = false
    end
    reset_group()
    set_group_id(nil)
    KRP:DoCallbacks("in_group_changed", in_party, in_raid, in_bg)
    fire_status_changes()
    fire_mark_changes()
    fire_assigned_changes()
    KRP:DoCallbacks("update_group_end", in_party, in_raid, in_bg)
    return true
  end

  players = {}

  --
  -- When we are in either a party or a raid, we build up a list of players that are in that party or raid. We retrieve
  -- certain useful values for those players such as their class, level and a bunch of other things. We also give all
  -- registered addons a chance to add extra information to each player entry via the "new_player" callback. The callback is
  -- passed the player table we are adding and if it needs to add any members to the table the member names should begin with
  -- an addon-specific prefix. For example, Konfer may add a variable "konfer_userid" to the player.
  --
  -- After all this had been done the players table will contain the full list of players in the party or raid. Other tables
  -- such as the party or raid table will simply contain player references into this players table indexed by the player full name (Name-realm).
  --
  -- Also note that our own name always appears in the players list if we are in either a raid or party.
  --
  -- To a large degree this table can simply be thought of as a cache for the info returned by GetRaidRosterInfo() or an
  -- amalgmation of other calls getting the same info if we are just in a party.
  --

  local player = {}

  local function populate_unit(ptbl, unm)
    ptbl.name = K.FullUnitName(unm)
    if (not ptbl.name or ptbl.name == "Unknown" or ptbl.name == "") then
      ptbl.name = nil
      return
    end

    ptbl.level = UnitLevel(unm)
    ptbl.class = K.ClassIndex[select(2, UnitClass(unm))]
    ptbl.faction = UnitFactionGroup(unm)
    if (K.player.is_guilded and UnitIsInMyGuild(unm)) then
      ptbl.is_guilded = true
      local kgi = K.guild.roster.name[ptbl.name]
      if (kgi) then
        local kri = K.guild.roster.id[kgi]
        ptbl.guildrankidx = kri.rank
        if (ptbl.guildrankidx == 1) then
          ptbl.is_gm = true
        else
          ptbl.is_gm = false
        end
      else
        ptbl.guildrankidx = 0
        ptbl.is_gm = false
      end
    else
      ptbl.is_guilded = false
      ptbl.guildrankidx = 0
      ptbl.is_gm = false
    end
  end

  -- Always add ourselves to the players list
  populate_unit(player, "player")
  if (not player.name) then
    return bail()
  end
  player.unitid = "player"
  player.is_ml = KRP.is_ml
  player.subgroup = 0
  player.raidid = 0
  player.partyid = 0
  player.group_role = GROUP_ROLE_NONE

  players[player.name] = player
  update_unit_flags("player", player, in_party, in_raid, players)
  players[player.name] = player
  KRP:DoCallbacks("new_player", players[player.name])

  if (in_party) then
    party = {}
    party[0] = player.name

    for i = 1, npm do
      prn = "party" .. i
      if (UnitExists(prn)) then
        player = {}
        player.partyid = i
        player.unitid = prn
        player.is_ml = false
        -- If we're in raid then dont do this check else each raid party will erroneous get this party member number marked as master looter.
        if (not in_raid) then
          if (KRP.party_mlid and KRP.party_mlid == i) then
            player.is_ml = true
          end
        end
        player.subgroup = 0
        player.raidid = 0
        player.group_role = GROUP_ROLE_NONE
        populate_unit(player, prn)
        if (player.name) then
          players[player.name] = player
          update_unit_flags(prn, player, in_party, in_raid, players)
          players[player.name] = player
          KRP:DoCallbacks("new_player", players[player.name])
          party[i] = player.name
        else
          return bail()
        end
      end
    end
  end

  --
  -- It is possible, even probable that we may end up calculating player info for a player that was already processed during
  -- party processing above. That's OK but addons need to be aware of this and never use any form of index other than the name into tables.
  --
  if (in_raid) then
    raid = {}
    raidgroups = {}
    for i = 1, NUM_RAID_GROUPS do
      raidgroups[i] = {}
    end

    for i = 1, nrm do
      prn = "raid" .. i
      if (UnitExists(prn)) then
        local nm, rank, subgrp, _, _, _, _, _, _, role, ml = GetRaidRosterInfo(i)
        if (nm) then
          player = {}
          player.unitid = prn
          player.subgroup = subgrp
          player.raidid = i
          player.group_role = group_role_to_number[role or "NONE"] or GROUP_ROLE_NONE
          populate_unit(player, prn)
          if (player.name) then
            players[player.name] = player
            update_unit_flags(prn, player, in_party, in_raid, players)
            -- Overwrite is_rl and is_aorl computed during update_unit_flags().
            if (rank == 2) then
              player.is_rl = true
            else
              player.is_rl = false
            end
            if (rank > 0) then
              player.is_aorl = true
            else
              player.is_aorl = false
            end
            if (ml) then
              player.is_ml = true
            else
              player.is_ml = false
            end
            players[player.name] = player
            KRP:DoCallbacks("new_player", players[player.name])
            raid[i] = player.name
            tinsert(raidgroups[subgrp], player.name)
          else
            return bail()
          end
        end
      end
    end
  end

  -- Update all of the table members, setting the in_party or in_raid stuff last so that the party and raid tables can be in
  -- place before we change those settings.
  reset_group(true)

  KRP.players = players
  KRP.party = party
  KRP.raid = raid
  KRP.raidgroups = raidgroups
  KRP.num_raid = nrm
  KRP.num_party = npm

  KRP.in_party = in_party
  KRP.in_raid = in_raid
  KRP.in_bg = in_bg

  player = players[K.player.name]

  KRP.subgroup = player.subgroup
  KRP.raidid = player.raidid

  update_loot_method_internal()
  update_leader_internal()
  update_role_internal()

  -- Send out all of the change events
  if (fire_party or old_inparty ~= KRP.in_party) then
    KRP:DoCallbacks("in_party_changed", in_party)
    changed = true
  end

  if (fire_raid or old_inraid ~= KRP.in_raid) then
    KRP:DoCallbacks("in_raid_changed", in_raid)
    changed = true
  end

  if (fire_bg or old_inbg ~= KRP.in_bg) then
    KRP:DoCallbacks("in_bg_changed", in_bg)
    changed = true
  end

  if (changed) then
    KRP:DoCallbacks("in_group_changed", in_party, in_raid, in_bg)
  end

  --
  -- We need to register for certain events if we haven't already.
  --
  if (not krp_flag_events) then
    KRP:RegisterEvent("PLAYER_FLAGS_CHANGED", function(evt, unitid)
      update_unit_flags(unitid, nil, nil, nil, nil)
    end)
    krp_flag_events = true
  end

  fire_status_changes()
  fire_mark_changes()
  fire_assigned_changes()
  send_pending_invites()
  KRP:DoCallbacks("update_group_end", in_party, in_raid, in_bg)

  return true
end

--
-- A roster walk fails when the game has not yet got a name for somebody in the group, which is common straight after a login
-- or a reload, and what listeners were handed on the way is only part of the group. So it is tried again every second until
-- it goes through, for up to GROUP_RETRIES seconds, and only one such retry is ever waiting.
--
local GROUP_RETRIES = 30
local group_retry_pending = false

local function retry_update_group(fire_party, fire_raid, fire_bg, tries)
  local tries = tries or GROUP_RETRIES

  if (group_retry_pending) then
    return
  end

  group_retry_pending = true

  K:ScheduleTimer(function()
    group_retry_pending = false

    if (not update_group_internal(fire_party, fire_raid, fire_bg) and tries > 1) then
      retry_update_group(fire_party, fire_raid, fire_bg, tries - 1)
    end
  end, 1.0)
end

--
-- Function: KRP.UpdateGroup(fire_party, fire_raid, fire_bg) fire_XXX - fire the specified change event even if the state
--           hasn't changed. This is most commonly done when you want to refresh the raid data and have all of the various
--           callbacks run after information that the callbacks may use has changed.
-- Purpose : Updates the various group related settings, namely: in_party, in_raid, in_bg, subgroup, num_party, num_raid, raid, party, players
-- Fires   : IN_RAID_CHANGED(is_in_raid)
--           IN_PARTY_CHANGED(is_in_party)
--           IN_BATTLEGROUND_CHANGED(is_in_bg)
--           Callback in_group_changed(in_party, in_raid, in_bg)
--
function KRP.UpdateGroup(fire_party, fire_raid, fire_bg)
  if (fire_party == nil) then
    fire_party = true
  end
  if (fire_raid == nil) then
    fire_raid = true
  end
  if (fire_bg == nil) then
    fire_bg = true
  end

  if (not KRP.initialised) then
    return false
  end

  if (not update_group_internal(fire_party, fire_raid, fire_bg)) then
    retry_update_group(fire_party, fire_raid, fire_bg)
    return false
  end
  return true
end

-- @debug-start@
--
-- Function: KRP:PretendGroup(roster)
-- Purpose : Pretend the group is ROSTER, the player's own raid with the player master looting it, or with nil go back to the
--           game's group. See KRP.pretend. It is refused while the player is in a real group, which would be two groups at
--           once. Answers whether the group is now pretend.
--
function KRP:PretendGroup(roster)
  if (roster and IsInGroup() and not KRP.pretend) then
    return false
  end

  KRP.pretend = roster

  if (not roster) then
    KRP.pretendself = {}
  else
    set_group_id("Party-0-00000000000000000000PRETEND", true)
  end

  KRP.UpdateGroup(true, true, true)

  return KRP.pretend ~= nil
end

-- The pretend group's entry for NAME, the player's own being KRP.pretendself, or nil for somebody not in it.
local function pretend_entry(name)
  if (name == K.player.name) then
    return KRP.pretendself
  end

  for _, m in ipairs(KRP.pretend or {}) do
    if (m.name == name) then
      return m
    end
  end
end
-- @debug-end@

--
-- ASKING THE GAME TO CHANGE THE GROUP
--
-- Who leads it, who assists, who is its main tank or main assist, who master loots, which mark somebody wears as a raid
-- target, which role they have taken, and who is in it at all. Each asks the game, which says who may: the leader any of it,
-- an assistant the main tank and main assist, the marks, the roles and taking out anybody holding no rank. Nothing here
-- changes what KRP holds; the game's own events bring the group in again, and status_changed, mark_changed and
-- assigned_changed with it. NAME is somebody in the group, by the
-- canonical Name-Realm. A pretend group is changed instead, all but who leads it and who master loots, which it keeps as
-- the player. The main tank and main assist are the game's alone to set, and KRP:GroupRoleAction says how to ask it.
--
local ROLE_ACTIONS = { [GROUP_ROLE_TANK] = "maintank", [GROUP_ROLE_ASSIST] = "mainassist" }

function KRP:PromoteToLeader(name)
  -- @debug-start@
  if (KRP.pretend) then
    return
  end
  -- @debug-end@

  C_PartyInfo.PromoteToLeader(K.DisplayName(name))
end

function KRP:SetAssistant(name, onoff)
  -- @debug-start@
  if (KRP.pretend) then
    local m = pretend_entry(name)

    if (m and m ~= KRP.pretendself) then
      m.assistant = onoff or nil
      KRP.UpdateGroup(false, false, false)
    end

    return
  end
  -- @debug-end@

  if (onoff) then
    C_PartyInfo.PromoteToAssistant(K.DisplayName(name))
  else
    C_PartyInfo.DemoteAssistant(K.DisplayName(name))
  end
end

function KRP:PromoteToAssistant(name)
  self:SetAssistant(name, true)
end

function KRP:DemoteAssistant(name)
  self:SetAssistant(name, false)
end

--
-- Making somebody the main tank or main assist is protected, and the game refuses it to an addon outright. Only a secure
-- action button the player clicks does it, so this answers what such a button is set to, the attributes of a
-- SecureActionButtonTemplate (a KUI menu item's secure) that make NAME the group's main tank, ROLE being GROUP_ROLE_TANK, or
-- its main assist, GROUP_ROLE_ASSIST, or with ONOFF false not. Nil for somebody not in the group, and in a pretend group,
-- which no secure button can reach and KRP:PretendGroupRole changes instead.
--
function KRP:GroupRoleAction(name, role, onoff)
  local kind = ROLE_ACTIONS[role]
  local p = KRP.players and KRP.players[name]

  if (not kind or not p or not p.unitid) then
    return nil
  end

  -- @debug-start@
  if (KRP.pretend) then
    return nil
  end
  -- @debug-end@

  return { type = kind, action = onoff and "set" or "clear", unit = p.unitid }
end

-- @debug-start@
function KRP:PretendGroupRole(name, role, onoff)
  local kind = ROLE_ACTIONS[role]
  local m = KRP.pretend and kind and pretend_entry(name)

  if (m) then
    m.role = onoff and kind:upper() or nil
    KRP.UpdateGroup(false, false, false)
  end
end
-- @debug-end@

function KRP:SetMasterLooter(name)
  -- @debug-start@
  if (KRP.pretend) then
    return
  end
  -- @debug-end@

  C_PartyInfo.SetLootMethod(LOOT_METHOD_MASTER, K.DisplayName(name))
end

--
-- Putting a raid target mark on somebody is restricted, as making them the main tank is, so this answers the attributes of a
-- secure button that puts MARK, one of the MARK_ numbers, on NAME, or with nil or 0 takes theirs off. A mark is one
-- target's at a time, and the game moves it. Nil for somebody not in the group, and in a pretend group, which
-- KRP:PretendMark changes instead.
--
function KRP:MarkAction(name, mark)
  local p = KRP.players and KRP.players[name]

  if (not p or not p.unitid) then
    return nil
  end

  -- @debug-start@
  if (KRP.pretend) then
    return nil
  end
  -- @debug-end@

  if (mark and mark > 0) then
    return { type = "raidtarget", action = "set", marker = mark, unit = p.unitid }
  end

  return { type = "raidtarget", action = "clear", unit = p.unitid }
end

-- @debug-start@
function KRP:PretendMark(name, mark)
  local m = KRP.pretend and pretend_entry(name)

  if (not m) then
    return
  end

  for _, other in ipairs(KRP.pretend) do
    if (mark and mark > 0 and other.mark == mark) then
      other.mark = nil
    end
  end

  if (mark and mark > 0 and KRP.pretendself.mark == mark) then
    KRP.pretendself.mark = nil
  end

  m.mark = (mark and mark > 0) and mark or nil
  KRP.UpdateGroup(false, false, false)
end
-- @debug-end@

--
-- Whether this character may say which role NAME has taken (THE ROLES TAKEN): anybody's as the leader or an assistant, and
-- their own as anybody, where the game offers roles at all. KRP:SetAssigned asks for it, ROLE one of Kore's K.ROLE_, the
-- game being told damage for every kind of it and the kind kept in KRP.picked, and with K.ROLE_UNSET or nil takes theirs
-- away. A pick of another kind of damage is Kore's alone, the game holding damage either way, so it is told now.
--
function KRP:CanAssign(name)
  local p = KRP.players and KRP.players[name]

  if (not p) then
    return false
  end

  -- @debug-start@
  if (KRP.pretend) then
    return true
  end
  -- @debug-end@

  if (not CanShowSetRoleButton()) then
    return false
  end

  return (KRP.is_pl or KRP.is_aorl or name == K.player.name) and true or false
end

function KRP:SetAssigned(name, role)
  local p = KRP.players and KRP.players[name]

  if (not p) then
    return
  end

  local game = role_to_game[role]

  KRP.picked[name] = is_damage(role) and role or nil

  -- @debug-start@
  if (KRP.pretend) then
    local m = pretend_entry(name)

    if (m) then
      m.assigned = assigned_to_number[game]
      KRP.UpdateGroup(false, false, false)
    end

    return
  end
  -- @debug-end@

  fire_assigned_changes()

  if ((assigned_to_number[game] or ASSIGNED_NONE) ~= p.assigned) then
    UnitSetRole(p.unitid, game)
  end
end

--
-- What a secure click is set to that makes every one of NAMES the group's main tank, ROLE being GROUP_ROLE_TANK, or its
-- main assist, GROUP_ROLE_ASSIST, or with ONOFF false not, as KRP:GroupRoleAction is for one. The game's action does one
-- unit a click, so for several it is the game's own slash command for it, a line each, run as a macro. Nil where any of
-- them is not in the group, and in a pretend group.
--
local ROLE_COMMANDS = {
  [GROUP_ROLE_TANK]   = { on = "SLASH_MAINTANKON1", off = "SLASH_MAINTANKOFF1" },
  [GROUP_ROLE_ASSIST] = { on = "SLASH_MAINASSISTON1", off = "SLASH_MAINASSISTOFF1" },
}

function KRP:GroupRolesAction(names, role, onoff)
  if (#names == 1) then
    return self:GroupRoleAction(names[1], role, onoff)
  end

  local cmds = ROLE_COMMANDS[role]
  local cmd = cmds and _G[onoff and cmds.on or cmds.off]

  if (not cmd or #names == 0) then
    return nil
  end

  -- @debug-start@
  if (KRP.pretend) then
    return nil
  end
  -- @debug-end@

  local lines = {}

  for _, name in ipairs(names) do
    if (not (KRP.players and KRP.players[name])) then
      return nil
    end

    tinsert(lines, cmd .. " " .. K.DisplayName(name))
  end

  return { type = "macro", macrotext = tconcat(lines, "\n") }
end

--
-- What a secure click is set to that takes off the mark every one of NAMES wears, as KRP:MarkAction does for one. For
-- several it is the game's own /tm aimed at each by name with 0, a line each, run as a macro. Nil where any of them is not
-- in the group, and in a pretend group.
--
function KRP:ClearMarksAction(names)
  if (#names == 0) then
    return nil
  end

  if (#names == 1) then
    return self:MarkAction(names[1], 0)
  end

  local cmd = _G.SLASH_TARGET_MARKER1

  if (not cmd) then
    return nil
  end

  -- @debug-start@
  if (KRP.pretend) then
    return nil
  end
  -- @debug-end@

  local lines = {}

  for _, name in ipairs(names) do
    if (not (KRP.players and KRP.players[name])) then
      return nil
    end

    tinsert(lines, cmd .. " [@" .. K.DisplayName(name) .. "] 0")
  end

  return { type = "macro", macrotext = tconcat(lines, "\n") }
end

--
-- The same for the main tank and the main assist by name, NAMES one name or a list of them. There is no setting either from
-- an addon's own code, the game refusing it, so these say what the secure click a player makes is to be set to.
--
function KRP:MainTankAction(names, onoff)
  return self:GroupRolesAction(type(names) == "table" and names or { names }, GROUP_ROLE_TANK, onoff)
end

function KRP:MainAssistAction(names, onoff)
  return self:GroupRolesAction(type(names) == "table" and names or { names }, GROUP_ROLE_ASSIST, onoff)
end

--
-- Whether this character may invite anybody into the group: anybody alone, the leader of a party, and the leader or an
-- assistant of a raid. KRP:Invite asks the game to invite every one of NAMES not in the group already, and what will not
-- fit in a party waits while it is made a raid (INVITING).
--
function KRP:CanInvite()
  -- @debug-start@
  if (KRP.pretend) then
    return false
  end
  -- @debug-end@

  if (KRP.in_raid) then
    return KRP.is_aorl and true or false
  elseif (KRP.in_party) then
    return KRP.is_pl and true or false
  end

  return true
end

function KRP:Invite(names)
  if (not self:CanInvite()) then
    return
  end

  local out = {}
  local have = 0

  for _ in pairs(KRP.players or {}) do
    have = have + 1
  end

  for _, name in ipairs(names) do
    if (not (KRP.players and KRP.players[name]) and name ~= K.player.name) then
      tinsert(out, name)
    end
  end

  local room = KRP.in_raid and #out or (MAX_PARTY - max(have, 1))

  for i = 1, min(room, #out) do
    C_PartyInfo.InviteUnit(K.DisplayName(out[i]))
  end

  if (#out > room) then
    pending_invites = { unpack(out, room + 1) }
    pending_until = GetTime() + INVITE_WAIT
    send_pending_invites()
  end
end

function KRP:RemoveFromGroup(name)
  -- @debug-start@
  if (KRP.pretend) then
    local roster = {}

    for _, m in ipairs(KRP.pretend) do
      if (m.name ~= name) then
        tinsert(roster, m)
      end
    end

    KRP:PretendGroup(roster)
    return
  end
  -- @debug-end@

  C_PartyInfo.UninviteUnit(K.DisplayName(name))
end

-- Leave the group this character is in, as the game's own Leave Group does.
function KRP:LeaveGroup()
  if (C_PartyInfo and C_PartyInfo.LeaveParty) then
    C_PartyInfo.LeaveParty()
  else
    LeaveParty()
  end
end

--
-- Ask the group whether it is ready, which only its leader or an assistant may. The answers arrive as readycheck_reply and the
-- check ends with readycheck_end, KRP.ready holding each member's answer, RC_AWAY for those who gave none.
--
function KRP:StartReadyCheck()
  -- @debug-start@
  --
  -- Nobody is there to answer a made-up group's check, so it answers itself at once: ready, but for every third member not
  -- ready and every fourth away, so that every answer is seen in a raid of only a few. Those away say nothing and are left
  -- waiting until the check runs out, a few seconds later, as a real one runs out after its timeout.
  --
  if (KRP.pretend) then
    local check = {}

    for k in pairs(KRP.players or {}) do
      check[k] = RC_WAITING
    end

    check[K.player.name] = RC_READY
    KRP.ready = check
    KRP.ready_ended = nil
    KRP.ready_checking = true
    KRP:DoCallbacks("readycheck_start")

    for i, m in ipairs(KRP.pretend) do
      if (m.name ~= K.player.name and i % 4 ~= 0) then
        check[m.name] = (i % 3 == 0) and RC_NOTREADY or RC_READY
        KRP:DoCallbacks("readycheck_reply", m.name, check[m.name])
      end
    end

    K:ScheduleTimer(function()
      if (KRP.ready ~= check or not KRP.ready_checking) then
        return
      end

      KRP.ready_checking = false
      KRP.ready_ended = GetTime()

      for k, v in pairs(check) do
        if (v == RC_WAITING) then
          check[k] = RC_AWAY
        end
      end

      KRP:DoCallbacks("readycheck_end")
    end, 5)

    return
  end
  -- @debug-end@

  C_PartyInfo.DoReadyCheck()
end

-- Function to deal with the start of a readycheck. This will mark all users
-- in the raid as unknown, except for the person who initiated the readycheck.
local function ready_check_start(evt, started_by, timeout, ...)
  if (not KRP.initialised) then
    return
  end

  --
  -- Retail keeps who started a ready check secret inside dungeons and raids, and a check whose starter cannot be read is not followed.
  --
  local nm = K.CanAccess(started_by) and K.FullUnitName(started_by)

  if (not nm or not KRP.in_party or not KRP.players or not KRP.players[nm]) then
    reset_ready()
    return
  end

  KRP.ready_start = time()
  KRP.ready_timeout = tonumber(timeout)
  KRP.ready_ended = nil
  KRP.ready_checking = true
  KRP.ready = {}
  for k, v in pairs(KRP.players) do
    KRP.ready[k] = RC_WAITING
  end
  KRP.ready[nm] = RC_READY

  KRP:DoCallbacks("readycheck_start")
end

-- Function to deal with a reply to a ready check
local function ready_check_confirm(evt, unit, status, ...)
  if (not KRP.initialised or not KRP.ready_checking or not KRP.ready) then
    return
  end

  local nm = K.FullUnitName(unit)

  if (not nm or nm == "" or not KRP.ready or not KRP.ready[nm]) then
    return
  end

  if (status) then
    KRP.ready[nm] = RC_READY
  else
    KRP.ready[nm] = RC_NOTREADY
  end
  KRP:DoCallbacks("readycheck_reply", nm, KRP.ready[nm])
end

-- And finally a function to deal with the end of a ready check
local function ready_check_ended(evt, ...)
  if (not KRP.initialised or not KRP.ready_checking or not KRP.ready) then
    return
  end

  KRP.ready_checking = false
  KRP.ready_timeout = nil
  KRP.ready_start = nil
  KRP.ready_ended = GetTime()

  for k, v in pairs(KRP.ready) do
    if (v == RC_WAITING) then
      KRP.ready[k] = RC_AWAY
    end
  end

  KRP:DoCallbacks("readycheck_end")
end

--
-- Walking the roster brings the leader, the role and the loot method up to date along with everything else, so what changed
-- is measured against what was there before the walk rather than after it.
--
local function krp_refresh(fire_party, fire_raid, fire_bg)
  if (not KRP.initialised) then
    return
  end

  local old_leader, old_role = KRP.leader, KRP.group_role

  if (KRP.UpdateGroup(fire_party, fire_raid, fire_bg)) then
    KRP.UpdateLootMethod(true)

    if (KRP.leader ~= old_leader) then
      KRP:DoCallbacks("leader_changed")
    end

    if (KRP.group_role ~= old_role) then
      KRP:DoCallbacks("role_changed")
    end
  end
end

function KRP:OnLateInit()
  if (KRP.initialised) then
    return
  end

  K:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", function(evt)
    KRP.UpdateLootMethod(false)
  end)
  K:RegisterEvent("PARTY_LEADER_CHANGED", function(evt)
    KRP.UpdateLeader(false)
  end)
  K:RegisterEvent("PLAYER_ROLES_ASSIGNED", function(evt)
    KRP.UpdateRole(false)
    fire_assigned_changes()
  end)
  K:RegisterEvent("GROUP_ROSTER_UPDATE", function(evt)
    KRP.UpdateGroup(false, false, false)
  end)
  -- Somebody in the group going offline or coming back, which the game tells of that unit alone and not as a roster change.
  K:RegisterEvent("UNIT_CONNECTION", function(evt, unit)
    local nm = KRP.initialised and KRP.players and K.FullUnitName(unit)

    if (nm and KRP.players[nm]) then
      KRP.UpdateGroup(false, false, false)
    end
  end)
  -- A mark put on or taken off anybody, which needs no new look at the group, only at who wears what.
  K:RegisterEvent("RAID_TARGET_UPDATE", function(evt)
    if (KRP.initialised) then
      fire_mark_changes()
    end
  end)
  K:RegisterEvent("READY_CHECK", ready_check_start)
  K:RegisterEvent("READY_CHECK_CONFIRM", ready_check_confirm)
  K:RegisterEvent("READY_CHECK_FINISHED", ready_check_ended)

  -- The group's own id as last kept, which the first look at the group below forgets if there is no group (THE GROUP'S OWN ID).
  KRP.group_id = K.chardb.groupid

  local function group_said(evt, category, guid)
    if ((category or HOME_GROUP) == HOME_GROUP and guid) then
      set_group_id(guid)
    end
  end

  K:RegisterEvent("GROUP_FORMED", group_said)
  K:RegisterEvent("GROUP_JOINED", group_said)
  K:RegisterEvent("GROUP_LEFT", function(evt, category, guid)
    if ((category or HOME_GROUP) == HOME_GROUP) then
      set_group_id(nil)
    end
  end)

  KRP.initialised = true

  krp_refresh()
end

K:RegisterMessage("PLAYER_INFO_UPDATED", function(evt, ...)
  krp_refresh(true, true, true)
end)

--
-- When an addon is suspended or resumed, we need to do a refresh because the addon may have callbacks that have either been
-- populated and now need to be removed (addon suspended) or needs to add new data via the callbacks (addon resumed). So we
-- trap these two events and use them to schedule a refresh.
--
function KRP:OnActivateAddon(name, onoff)
  krp_refresh(true, true, true)
end

--
-- Utility functions that more than one mod will likely need.
--
-- A name in colour for its class. STR is a canonical name with CLASS its Kore class number, or a table carrying both as
-- .name and .class. The two plain forms grey out someone who is not in the group while we are in one, and the Always forms
-- never do. The long forms show the name the way the game does, without the realm for a character on this realm, and the
-- short forms leave the realm off for a guildmate as well. A class that is not known yet is drawn white.
--
local function class_colour(class)
  return K.ClassColorsEsc[class] or "|cffffffff"
end

local function class_string(str, class, context, always)
  local sn = str

  if (type(str) == "table") then
    sn = str.name
    class = str.class
  end

  -- This realm's names lose theirs through K.DisplayName, and only a guildmate from another realm is left to Ambiguate.
  local shown = K.DisplayName(sn)

  if (shown == sn and context == "guild") then
    shown = Ambiguate(sn, context)
  end

  if (not always and KRP.in_party and KRP.players and not KRP.players[sn]) then
    return "|cff808080" .. shown .. "|r"
  end

  return class_colour(class) .. shown .. "|r"
end

function KRP.ClassString(str, class)
  return class_string(str, class, "none", false)
end

function KRP.ShortClassString(str, class)
  return class_string(str, class, "guild", false)
end

function KRP.AlwaysClassString(str, class)
  return class_string(str, class, "none", true)
end

function KRP.ShortAlwaysClassString(str, class)
  return class_string(str, class, "guild", true)
end
