--[[
   KahLua Kore - loot distribution handling.
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

local KORELOOT_MAJOR = "KoreLoot"
local KORELOOT_MINOR = 1
local KLD, oldminor = LibStub:NewLibrary(KORELOOT_MAJOR, KORELOOT_MINOR)

if (not KLD) then
  return
end

KLD.debug_id = KORELOOT_MAJOR

local K, KM = LibStub:GetLibrary("Kore")
assert (K, "KoreLoot requires Kore")
assert (tonumber(KM) >= 1, "KoreLoot requires Kore r1 or later")
K:RegisterExtension (KLD, KORELOOT_MAJOR, KORELOOT_MINOR)

local KRP, KM = LibStub:GetLibrary("KoreParty")
assert (KRP, "KoreLoot requires KoreParty")
assert (tonumber(KM) >= 1, "KoreLoot requires KoreParty r1 or later")

local L = LibStub("AceLocale-3.0"):GetLocale("Kore")

--
-- Constants for easy representation of the various armor and weapon types that a character can equip. This uses the Blizzard
-- localised strings as much as possible.
--
K.INV_HEAD              = 1
K.INV_NECK              = 2
K.INV_SHOULDER          = 3
K.INV_BODY              = 4
K.INV_CHEST             = 5
K.INV_WAIST             = 6
K.INV_LEGS              = 7
K.INV_FEET              = 8
K.INV_WRIST             = 9
K.INV_HANDS             = 10
K.INV_FINGER            = 11
K.INV_TRINKET           = 12
K.INV_1HWEAPON          = 13
K.INV_SHIELD            = 14
K.INV_RANGED            = 15
K.INV_BACK              = 16
K.INV_2HWEAPON          = 17
K.INV_BAG               = 18
K.INV_TABARD            = 19
K.INV_ROBE              = 20
K.INV_MHWEAPON          = 21
K.INV_OHWEAPON          = 22
K.INV_HOLDABLE          = 23
K.INV_AMMO              = 24
K.INV_THROWN            = 25
K.INV_RANGEDRIGHT       = 26
K.INV_QUIVER            = 27
K.INV_RELIC             = 28

K.InvSlotNames = {
  [K.INV_HEAD]          = INVTYPE_HEAD,
  [K.INV_NECK]          = INVTYPE_NECK,
  [K.INV_SHOULDER]      = INVTYPE_SHOULDER,
  [K.INV_BODY]          = INVTYPE_BODY,
  [K.INV_CHEST]         = INVTYPE_CHEST,
  [K.INV_WAIST]         = INVTYPE_WAIST,
  [K.INV_LEGS]          = INVTYPE_LEGS,
  [K.INV_FEET]          = INVTYPE_FEET,
  [K.INV_WRIST]         = INVTYPE_WRIST,
  [K.INV_HANDS]         = INVTYPE_HAND,
  [K.INV_FINGER]        = INVTYPE_FINGER,
  [K.INV_TRINKET]       = INVTYPE_TRINKET,
  [K.INV_1HWEAPON]      = INVTYPE_WEAPON .. " " .. WEAPON,
  [K.INV_SHIELD]        = L["Shield"],
  [K.INV_RANGED]        = INVTYPE_RANGED .. " " .. WEAPON,
  [K.INV_BACK]          = INVTYPE_CLOAK,
  [K.INV_2HWEAPON]      = INVTYPE_2HWEAPON .. " " .. WEAPON,
  [K.INV_BAG]           = INVTYPE_BAG,
  [K.INV_TABARD]        = INVTYPE_TABARD,
  [K.INV_ROBE]          = INVTYPE_ROBE,
  [K.INV_MHWEAPON]      = INVTYPE_WEAPONMAINHAND .. " " .. WEAPON,
  [K.INV_OHWEAPON]      = INVTYPE_WEAPONOFFHAND .. " " .. WEAPON,
  [K.INV_HOLDABLE]      = INVTYPE_HOLDABLE,
  [K.INV_AMMO]          = INVTYPE_AMMO,
  [K.INV_THROWN]        = INVTYPE_THROWN .. " " .. WEAPON,
  [K.INV_RANGEDRIGHT]   = INVTYPE_RANGEDRIGHT,
  [K.INV_QUIVER]        = INVTYPE_QUIVER,
  [K.INV_RELIC]         = INVTYPE_RELIC,
}

local strmatch = string.match
local printf = K.printf
local tinsert = table.insert
local tconcat = table.concat
local pairs, ipairs = pairs, ipairs

local function debug(lvl,...)
  K.debug("kore", lvl, ...)
end

KLD.addons = {}

KLD.valid_callbacks = {
  ["ml_candidate"] = true,
  ["loot_item"] = true,
  ["start_loot_info"] = true,
  ["end_loot_info"] = true,
  ["looting_ready"] = true,
  ["looting_ended"] = true,
  ["loot_assigned"] = true,
  ["loot_not_assigned"] = true,
  ["candidates_updated"] = true,
  ["encounter_ended"] = true,
  ["group_loot_rolled"] = true,
  ["group_loot_won"] = true,
  ["trade_delivered"] = true,
}

KLD.initialised = false

-- Name of the unit being looted or nil if none.
KLD.unit_name = nil

-- GUID of the unit being looted or nil if none.
KLD.unit_guid = nil

-- Whether or not KLD.unit_guid is a real GUID (if set at all). A chest's is "chest:" and the ids of what is in it.
KLD.unit_realguid = false

-- Number of loot items on the current corpse / chest or 0 if there is no such current corpse or there are no items that match the threshold.
KLD.num_items = 0

-- Whether the loot about to open is a gather this addon has nothing to say about, a disenchant or a herb or an ore vein.
KLD.skip_loot = false

-- Table of items on the current corpse or nil if there is no current corpse.
-- Each element in this table is a table with the following members:
--   name       - name of the item
--   ilink      - the full item link
--   itemid     - the item ID
--   lootslot   - the loot slot number
--   quantity   - how many of the item
--   quality    - the item quality
--   locked     - whether or not the item is locked
--   candidates - list of possible candidates if we are master looting
--   assigning  - who KLD.GiveMasterLoot has asked the game to give it to, until the slot clears
KLD.items = nil

--
-- Every rank of a gathering spell has the one name, so any rank will do to learn it, as long as the client has that rank.
-- These are the ranks the first client had.
--
local disenchant_name = K.SpellName(13262)
local herbalism_name = K.SpellName(11993)
local mining_name = K.SpellName(2575)
-- local skinning_name = K.SpellName(75644)

--
-- Function: get_ml_candidates(slot)
--
-- Purpose : Returns the list of valid candidates for the provided loot slot item, or nil if there is no current loot slot or
--           we are not using master looting.
--
-- Callback: Calls ml_candidate for each candidate.
--
local function get_ml_candidates(slot)
  if (not KLD.initialised) then
    return nil
  end

  if (not K.HAS_MASTER_LOOT or not KRP.master_looter) then
    return nil
  end

  local candidates = {}
  local count = 0
  for i = 1, MAX_RAID_MEMBERS do
    local name = GetMasterLootCandidate(slot, i)
    if (name) then
      name = K.CanonicalName(name, nil)
      if (not name) then
        return nil
      end

      local cinfo = {}
      cinfo["index"] = i
      cinfo["lootslot"] = slot
      candidates[name] = cinfo
      KLD:DoCallbacks("ml_candidate", candidates[name])
      count = count + 1
    end
  end

  if (count > 0) then
    return candidates
  else
    return nil
  end
end

local function reset_items()
  KLD.items = nil
  KLD.num_items = 0
end

--
-- Actually retrieve all of the loot slot item info.
--
-- KLD.items is keyed by loot slot and is sparse, a slot holding nothing or holding something under the threshold being
-- skipped, so the slots that were filled are kept in order beside it. A consumer building a list of its own from the
-- loot_item callback then gets the items in the order the loot window shows them, which is the order its user is looking
-- at. Walking the table with pairs handed them out in hash order, and ipairs would stop at the first gap.
--
local function populate_items()
  local nitems = GetNumLootItems()
  local items = {}
  local slots = {}
  local count = 0

  KLD:DoCallbacks("start_loot_info")

  for i = 1, nitems do
    if (LootSlotHasItem(i)) then
      local icon, name, quant, _, qual, locked  = GetLootSlotInfo(i)
      local ilink = GetLootSlotLink(i)
      local itemid = nil
      local item = {}

      if (icon and qual >= KRP.loot_threshold) then
        item["name"] = name
        if (ilink and ilink ~= "") then
          item["ilink"] = ilink
          itemid = strmatch(ilink, "item:(%d+)")
        end

        item["itemid"] = itemid
        item["lootslot"] = i
        item["quantity"] = quant
        item["quality"] = qual
        item["locked"] = locked or false
        item["candidates"] = get_ml_candidates(i) or {}

        items[i] = item
        tinsert(slots, i)
        count = count + 1
      end
    end
  end

  KLD.num_items = count
  if (KLD.num_items > 0) then
    KLD.items = items
    -- Only do callbacks once all items are in the list, and in loot slot order.
    for k, slot in ipairs(slots) do
      KLD:DoCallbacks("loot_item", items[slot])
    end
  else
    KLD.items = nil
  end

  KLD:DoCallbacks("end_loot_info")
end

local function reset_loot_target()
  KLD.unit_name = nil
  KLD.unit_guid = nil
  KLD.unit_realguid = false
end

--
-- When the player last finished opening something, and whether the loot on display is a chest's. Loot that opens within
-- CHEST_WINDOW seconds of opening something is taken to be that thing's, and stays a chest's until the window closes.
--
local CHEST_WINDOW = 5
local opened_at = nil
local chest_open = false

-- Whether a loot window is open at all, whatever is in it.
local loot_open = false

local function populate_loot_target()
  if (opened_at and (GetTime() - opened_at) < CHEST_WINDOW) then
    chest_open = true
  end

  opened_at = nil

  --
  -- A chest cannot be targeted, so whatever is targeted says nothing about it. One chest is told from another by what is in
  -- it, which also makes opening the same chest twice the same chest.
  --
  if (chest_open) then
    local ids = {}

    for i = 1, GetNumLootItems() do
      local link = GetLootSlotLink(i)
      tinsert(ids, link and strmatch(link, "item:(%d+)") or "")
    end

    KLD.unit_name = L["Chest"]
    KLD.unit_guid = "chest:" .. tconcat(ids, ",")
    KLD.unit_realguid = false
    return
  end

  local uname = UnitName("target")
  local uguid = UnitGUID("target")
  local realguid = true

  --
  -- Retail keeps the name and GUID of a unit outside the group secret in dungeons and raids, and a boss corpse is exactly such
  -- a unit. A secret one is treated as no target at all, which names the loot as a chest's.
  --
  if (not K.CanAccess(uname)) then
    uname = nil
  end

  if (not K.CanAccess(uguid)) then
    uguid = nil
  end

  if (not uname or uname == "") then
    uname = L["Chest"]
  end

  if (not uguid or uguid == "") then
    uguid = 0
    realguid = false
  end

  KLD.unit_name = uname
  KLD.unit_guid = uguid
  KLD.unit_realguid = realguid
end

--
-- Function: KLD.RefreshLoot()
--
-- Purpose : Refresh the internal view of the loot items on the current corpse. This should only ever be called when we know that
--           we have a valid corpse and that loot is not being skipped.
--
-- Fires   : ITEMS_UPDATED
--
function KLD.RefreshLoot()
  if (not KLD.initialised) then
    return
  end

  reset_loot_target()
  reset_items()

  populate_loot_target()
  populate_items()
end

--
-- Function: KLD.RefreshCandidates()
--
-- Purpose : Re-read the master loot candidate list for every item we already know about, in place. The item list has not
--           changed, only who is eligible to receive it.
--
--           Deliberately does NOT fire start_loot_info / loot_item / end_loot_info: those tell a consumer to rebuild its
--           loot list, which cancels any bid or roll in progress. UPDATE_MASTER_LOOT_LIST can fire repeatedly while bidding
--           is open. It says instead that the candidates changed, which matters because the game can open a loot window
--           before it knows who may have what is in it.
--
-- Callback: Calls ml_candidate for each candidate, then candidates_updated.
--
function KLD.RefreshCandidates()
  if (not KLD.initialised or not KLD.items) then
    return
  end

  for slot, item in pairs(KLD.items) do
    item.candidates = get_ml_candidates(slot) or {}
  end

  KLD:DoCallbacks("candidates_updated")
end

--
-- Function: KLD.GiveMasterLoot(slot, target)
--
-- Purpose : Ask the game to give the loot in KLD.items[slot] to the specified target. If master looting is not active, or
--           the slot is invalid, returns 1. If the slot and the target are valid but the target is not in the list of valid
--           recipients for the item, returns 2. Otherwise the game has been asked and it returns 0.
--
--           Asked is not given. The game answers nothing, and a target with full bags or out of range simply never receives
--           it. An item has gone when its loot slot clears, which is when loot_assigned fires, and one still waiting when
--           the loot window closes fires loot_not_assigned instead. Both may fire from inside this call.
--
-- Fires   : loot_assigned(slot, target), loot_not_assigned(slot, target)
--
function KLD.GiveMasterLoot(slot, target)
  if (not KLD.initialised or not K.HAS_MASTER_LOOT or not KRP.is_ml or not slot or slot < 1
      or not target or target == "" or not KLD.items
      or KLD.num_items < 1 or not KLD.items[slot]) then
    return 1
  end

  local cand = KLD.items[slot].candidates

  if (not cand or not cand[target]) then
    return 2
  end

  KLD.items[slot].assigning = target
  GiveMasterLoot(slot, cand[target].index)

  return 0
end

local function loot_slot_cleared_evt(evt, slot)
  local item = KLD.initialised and KLD.items and KLD.items[slot]

  if (not item or not item.assigning) then
    return
  end

  local target = item.assigning

  item.assigning = nil
  KLD:DoCallbacks("loot_assigned", slot, target)
end

local function loot_ready_evt()
  if (not KLD.initialised) then
    return
  end

  if (KLD.skip_loot) then
    KLD.skip_loot = false
    return
  end

  reset_items()
  reset_loot_target()

  loot_open = true
  populate_loot_target()
  populate_items()

  KLD:DoCallbacks("looting_ready")
end

local function loot_closed_evt()
  if (not KLD.initialised) then
    return
  end

  for slot, item in pairs(KLD.items or {}) do
    if (item.assigning) then
      KLD:DoCallbacks("loot_not_assigned", slot, item.assigning)
    end
  end

  reset_items()
  reset_loot_target()

  loot_open = false
  chest_open = false

  KLD:DoCallbacks("looting_ended")
end

local function unit_spellcast_succeeded(evt, unitid, castguid, spellid)
  if (not K.CanAccess(unitid) or not K.CanAccess(spellid) or unitid ~= "player" or not spellid) then
    return
  end

  local sname = K.SpellName(spellid)
  if (not sname) then
    return
  end

  if (sname == OPENING) then
    opened_at = GetTime()
    return
  end

  if ((sname == disenchant_name) or (sname == herbalism_name) or
      (sname == mining_name)) then
    KLD.skip_loot = true
  end
end

--
-- A boss fight ended, won or lost. Every client in the fight hears it from the game itself, so it goes no further than the
-- addons on this one.
--
-- Fires   : encounter_ended(enc), ENC being { id, name, difficulty, size, killed, when }: the game's encounterID, the fight's
--           name in this client's language, its difficultyID, the size of the group, whether the boss died, and when, in
--           UTC seconds (K.time). A fight has the one id on every client and in every locale, so id and when together name
--           one attempt at it. A fight the game will not show this client is not passed on at all.
--
local function encounter_end_evt(evt, encid, encname, difficulty, size, success)
  if (not K.CanAccess(encid) or not K.CanAccess(success)) then
    return
  end

  KLD:DoCallbacks("encounter_ended", {
    id = encid,
    name = K.CanAccess(encname) and encname or nil,
    difficulty = K.CanAccess(difficulty) and difficulty or nil,
    size = K.CanAccess(size) and size or nil,
    killed = (success == 1),
    when = K.time(),
  })
end

--
-- GROUP LOOT
--
-- Without a master looter the game rolls for each item, and an addon may answer the roll for its player. KLD.SetGroupLoot
-- says how: "pass" passes on everything, "need" asks for it, Need where the item allows it, then Transmog, then Greed, and
-- nil leaves the rolls to the player. Which a client does is its addon's to decide; this only does it. An item that cannot
-- be traded once won is never answered (UNTRADEABLE), nor is anything legendary, the player keeping those decisions for
-- themselves. The game's own roll window for a roll answered here is put away, there being nothing left in it to press.
--
-- Fires   : group_loot_rolled(ilink, rollid, roll), roll 0 for a pass, 1 Need, 2 Greed and 4 Transmog
--
KLD.grouploot = nil

--
-- Items that are bound to whoever wins them and so could never be handed on: hearthstones and toys that become unwinnable
-- once learned. RCLootCouncil's list, kept as theirs is.
--
local UNTRADEABLE = {
  [209035] = true, -- Hearthstone of the Flame, Larodar, Amirdrassil
  [236687] = true, -- Explosive Hearthstone, Liberation of Undermine
  [246565] = true, -- Cosmic Hearthstone, Manaforge Omega
  [250104] = true, -- Soulbinder's Nethermantle
  [264672] = true, -- Cosmic Ritual Stone, Voidspire
  [264313] = true, -- Madcap Redcap
  [264367] = true, -- Mycomancer's Hearthspore
  [268280] = true, -- Sporelord's Shroom Cap
}

local LEGENDARY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Legendary) or 5

-- The game's roll windows, one a roll, as many as it shows at once.
local NUM_ROLL_FRAMES = 4

function KLD.SetGroupLoot(how)
  KLD.grouploot = (how == "pass" or how == "need") and how or nil
end

local function hide_roll_frame(rollid)
  if (not GroupLootContainer or not GroupLootContainer_RemoveFrame) then
    return
  end

  for i = 1, NUM_ROLL_FRAMES do
    local frame = _G["GroupLootFrame" .. i]

    if (frame and frame:IsShown() and frame.rollID == rollid) then
      GroupLootContainer_RemoveFrame(GroupLootContainer, frame)
    end
  end
end

local function start_loot_roll_evt(evt, rollid)
  local how = KLD.grouploot

  if (not KLD.initialised or not how or not K.CanAccess(rollid)) then
    return
  end

  local ilink = GetLootRollItemLink(rollid)

  if (not K.CanAccess(ilink) or not ilink) then
    return
  end

  local _, _, _, quality, _, canneed, _, _, _, _, _, _, canmog = GetLootRollItemInfo(rollid)
  local itemid = tonumber(strmatch(ilink, "item:(%d+)"))

  if (not itemid or UNTRADEABLE[itemid] or (K.CanAccess(quality) and quality and quality >= LEGENDARY)) then
    return
  end

  local roll = 0

  if (how == "need") then
    roll = (canneed and 1) or (canmog and 4) or 2
  end

  -- A moment later, for another addon that changes the roll window to have finished with it first.
  C_Timer.After(0.05, function()
    RollOnLoot(rollid, roll)
    hide_roll_frame(rollid)
  end)

  KLD:DoCallbacks("group_loot_rolled", ilink, rollid, roll)
end

--
-- This character won ILINK in a roll. The item is in their bags from here, and whoever is collecting a group's loot puts it
-- on offer from here.
--
-- Fires   : group_loot_won(ilink)
--
local function loot_roll_won_evt(evt, ilink)
  if (KLD.initialised and K.CanAccess(ilink) and ilink) then
    KLD:DoCallbacks("group_loot_won", ilink)
  end
end

--
-- TRADING
--
-- An item held in this character's bags that is owed to somebody else is handed over by trading it to them. KLD.OweTrade
-- notes what is owed and to whom, and when a trade window opens with somebody owed something, what they are owed is put in
-- it, as many as the window takes, for the player to accept. The trade going through is the delivery. A trade that is
-- closed without completing delivers nothing, and what was owed stays owed.
--
-- KLD.trades is what is owed, each { id, ilink, to, at }, TO the canonical name and AT when it was noted, UTC seconds. It is
-- this character's saved data (K.chardb.trades), the items staying in its bags across a reload or a logout and so still owed.
-- Nothing here forgets an item that can no longer be traded; KLD.ForgetTrade is the caller's, and every item a raid wins
-- can be traded for two hours from when it was looted (TRADE_HOURS).
--
-- Fires   : trade_delivered(id, ilink, to)
--
KLD.trades = {}
KLD.TRADE_HOURS = 2

local trade_seq = 0
local trading = nil

function KLD.OweTrade(ilink, to)
  if (not ilink or not to or to == "") then
    return nil
  end

  trade_seq = trade_seq + 1
  tinsert(KLD.trades, { id = trade_seq, ilink = ilink, to = to, at = K.time() })

  return trade_seq
end

function KLD.ForgetTrade(id)
  for i, t in ipairs(KLD.trades) do
    if (t.id == id) then
      table.remove(KLD.trades, i)
      return true
    end
  end

  return false
end

-- Open a trade with NAME, somebody in the group. Answers whether the game could be asked.
function KLD.OpenTrade(name)
  local p = name and KRP.players and KRP.players[name]

  if (not p or not p.unitid) then
    return false
  end

  InitiateTrade(p.unitid)
  return true
end

-- Where in the bags an item whose link is ILINK is, passing over the places in USED.
local function find_in_bags(ilink, used)
  local want = strmatch(ilink, "item:(%d+)")

  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      local key = bag .. ":" .. slot

      if (link and not used[key] and (link == ilink or strmatch(link, "item:(%d+)") == want)) then
        used[key] = true
        return bag, slot
      end
    end
  end

  return nil
end

local function trade_show_evt()
  if (not KLD.initialised) then
    return
  end

  local who = UnitName("NPC")
  local partner = K.CanAccess(who) and who and K.CanonicalName(who, select(2, UnitName("NPC"))) or nil

  trading = { partner = partner }

  if (not partner) then
    return
  end

  local used = {}
  local n = 0
  local last = (MAX_TRADE_ITEMS or 7) - 1

  for _, t in ipairs(KLD.trades) do
    if (t.to == partner and n < last) then
      local bag, slot = find_in_bags(t.ilink, used)

      if (bag) then
        n = n + 1

        local button = n

        C_Timer.After(0.1 * n, function()
          if (trading and trading.partner == partner) then
            ClearCursor()
            C_Container.PickupContainerItem(bag, slot)
            ClickTradeButton(button)
          end
        end)
      end
    end
  end
end

--
-- Either side accepting is what is in the window being settled, the player having had every chance to change it by hand, so
-- what it holds then is what a completed trade delivered. The last of the window's places is the one whose item is not
-- traded, and is passed over.
--
local function trade_accept_evt(evt, player, target)
  if (not trading or not K.CanAccess(player) or not K.CanAccess(target) or (player ~= 1 and target ~= 1)) then
    return
  end

  trading.links = {}

  for i = 1, (MAX_TRADE_ITEMS or 7) - 1 do
    local link = GetTradePlayerItemLink(i)

    if (K.CanAccess(link) and link) then
      tinsert(trading.links, link)
    end
  end
end

-- The trade went through, so whatever owed to the partner went with it has been delivered, matched by the item it is.
local function trade_complete()
  local t = trading

  trading = nil

  if (not t or not t.partner) then
    return
  end

  for _, link in ipairs(t.links or {}) do
    local want = strmatch(link, "item:(%d+)")

    for i, owed in ipairs(KLD.trades) do
      if (owed.to == t.partner and (owed.ilink == link or strmatch(owed.ilink, "item:(%d+)") == want)) then
        table.remove(KLD.trades, i)
        KLD:DoCallbacks("trade_delivered", owed.id, owed.ilink, owed.to)
        break
      end
    end
  end
end

local function ui_info_evt(evt, msgtype)
  if (trading and K.CanAccess(msgtype) and LE_GAME_ERR_TRADE_COMPLETE and msgtype == LE_GAME_ERR_TRADE_COMPLETE) then
    trade_complete()
  end
end

local function trade_closed_evt()
  -- The completion message comes before the window closes, so a trade still noted here did not go through.
  C_Timer.After(0, function()
    trading = nil
  end)
end

local function kld_do_refresh(evt, ...)
  if (not KLD.initialised) then
    return
  end
  KLD.RefreshLoot()
  KLD:DoCallbacks("looting_ready")
end

--
-- An addon that is resumed while a loot window is open is handed that loot, as it would have been had it been running when
-- the window opened. With no window open there is nothing to hand it, and a suspended addon hears nothing either way.
--
function KLD:OnActivateAddon(name, onoff)
  if (onoff and loot_open) then
    kld_do_refresh()
  end
end

-- Whether a loot window is open at all, a corpse's or a chest's, whatever is in it.
function KLD:IsLootOpen()
  return loot_open
end

function KLD:OnLateInit()
  if (KLD.initialised) then
    return
  end

  KLD:RegisterEvent("LOOT_READY", loot_ready_evt)
  KLD:RegisterEvent("LOOT_SLOT_CLEARED", loot_slot_cleared_evt)
  KLD:RegisterEvent("LOOT_CLOSED", loot_closed_evt)

  if (K.HAS_MASTER_LOOT) then
    KLD:RegisterEvent("UPDATE_MASTER_LOOT_LIST", function()
      KLD.RefreshCandidates()
    end)
  end

  KLD:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", unit_spellcast_succeeded)
  KLD:RegisterEvent("ENCOUNTER_END", encounter_end_evt)

  K.chardb.trades = K.chardb.trades or {}
  KLD.trades = K.chardb.trades

  for _, t in ipairs(KLD.trades) do
    trade_seq = math.max(trade_seq, t.id or 0)
  end

  KLD:RegisterEvent("START_LOOT_ROLL", start_loot_roll_evt)
  KLD:RegisterEvent("LOOT_ITEM_ROLL_WON", loot_roll_won_evt)
  KLD:RegisterEvent("TRADE_SHOW", trade_show_evt)
  KLD:RegisterEvent("TRADE_ACCEPT_UPDATE", trade_accept_evt)
  KLD:RegisterEvent("UI_INFO_MESSAGE", ui_info_evt)
  KLD:RegisterEvent("TRADE_CLOSED", trade_closed_evt)

  KLD.initialised = true
end
