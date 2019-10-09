--[[
   KahLua Kore - loot distribution handling.
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
]]

local KKORELOOT_MAJOR = "KKoreLoot"
local KKORELOOT_MINOR = 2
local KLD, oldminor = LibStub:NewLibrary(KKORELOOT_MAJOR, KKORELOOT_MINOR)

if (not KLD) then
  return
end

local K, KM = LibStub:GetLibrary("KKore")
assert (K, "KKoreLoot requires KKore")
assert (tonumber(KM) >= 2, "KKoreLoot requires KKore r2 or later")
K:RegisterExtension (KLD, KKORELOOT_MAJOR, KKORELOOT_MINOR)

local KRP, KM = LibStub:GetLibrary("KKoreParty")
assert (KRP, "KKoreLoot requires KKoreParty")
assert (tonumber(KM) >= 2, "KKoreLoot requires KKoreParty r2 or later")

local L = K:GetI18NTable("KKore", false)

local printf = K.printf
local tinsert = table.insert

local LOOT_METHOD_UNKNOWN     = KRP.LOOT_METHOD_UNKNWON
local LOOT_METHOD_FREEFORALL  = KRP.LOOT_METHOD_FREEFORALL
local LOOT_METHOD_ROUNDROBIN  = KRP.LOOT_METHOD_ROUNDROBIN
local LOOT_METHOD_MASTER      = KRP.LOOT_METHOD_MASTER
local LOOT_METHOD_GROUP       = KRP.LOOT_METHOD_GROUP
local LOOT_METHOD_NEEDB4GREED = KRP.LOOT_METHOD_NEEDB4GREED
local LOOT_METHOD_PERSONAL    = KRP.LOOT_METHOD_PERSONAL

KLD.addons = {}

KLD.valid_callbacks = {
  ["ml_candidate"] = true,
  ["loot_item"] = true,
  ["start_loot_info"] = true,
  ["end_loot_info"] = true,
}

KLD.initialised = false

-- Set to true if loot method is master loot, false otherwise.
KLD.master_loot = false

-- Name of the unit being looted or nil if none.
KLD.unit_name = nil

-- GUID of the unit being looted or nil if none.
KLD.unit_guid = nil

-- Whether or not KLD.unit_guid is a real GUID (if set at all).
KLD.unit_realguid = false

-- Name of the chest or item being opened or nil if none
KLD.chest_name = nil

-- Number of loot items on the current corpse / chest or 0 if there is no
-- such current corpse or there are no items that match the threshold.
KLD.num_items = 0

-- State variable to indicate if we should skip populating loot this time.
KLD.skip_loot = false

-- Table of items on the current corpse or nil if there is no current corpse.
-- Each element in this table is a table with the following members:
--   name - name of the item
--   ilink - the full item link
--   itemid - the item ID
--   lootslot - the loot slot number
--   quantity - how many of the item
--   quality - the item quality
--   locked - whether or not the item is locked
--   candidates - list of possible candidates if we are master looting
KLD.items = nil

local disenchant_name = GetSpellInfo (13262)
local herbalism_name = GetSpellInfo (11993)
local mining_name = GetSpellInfo (32606)
-- local skinning_name = GetSpellInfo (75644)

--
-- Function: get_ml_candidates (slot)
-- Purpose : Returns the list of valid candidates for the provided
--           loot slot item, or nil if there is no current loot slot or
--           we are not using master looting.
-- Callback: Calls ml_candidate for each candidate.
--
local function get_ml_candidates (slot)
  if (not KLD.initialised) then
    return nil
  end

  if (not KLD.master_loot) then
    return nil
  end

  local candidates = {}
  local count = 0
  for i = 1, MAX_RAID_MEMBERS do
    local name = GetMasterLootCandidate (slot, i)
    if (name) then
      name = K.CanonicalName (name, nil)
      if (not name) then
        return nil
      end

      local cinfo = {}
      cinfo["index"] = i
      cinfo["lootslot"] = slot
      candidates[name] = cinfo
      KLD:DoCallbacks ("ml_candidate", candidates[name])
      count = count + 1
    end
  end

  if (count > 0) then
    return candidates
  else
    return nil
  end
end

local function reset_items ()
  KLD.items = nil
  KLD.num_items = 0
end

-- Actually retrieve all of the loot slot item info.
local function populate_items ()
  local nitems = GetNumLootItems ()
  local items = {}
  local count = 0

  KLD:DoCallbacks ("start_loot_info")

  for i = 1, nitems do
    if (LootSlotHasItem (i)) then
      local icon, name, quant, _, qual, locked  = GetLootSlotInfo (i)
      local ilink = GetLootSlotLink (i)
      local itemid = nil
      local item = {}

      if (icon and qual >= KRP.loot_threshold) then
        item["name"] = name
        if (ilink and ilink ~= "") then
          item["ilink"] = ilink
          itemid = tonumber (string.match (ilink, "item:(%d+)") or "0")
        end

        item["itemid"] = itemid
        item["lootslot"] = i
        item["quantity"] = quant
        item["quality"] = qual
        item["locked"] = locked or false
        item["candidates"] = get_ml_candidates (i)

        items[i] = item
        KLD:DoCallbacks ("loot_item", items[i])
        count = count + 1
      end
    end
  end

  KLD.num_items = count
  if (KLD.num_items > 0) then
    KLD.items = items
  else
    KLD.items = nil
  end

  KLD:DoCallbacks ("end_loot_info")
  KLD:SendIPC ("ITEMS_UPDATED")
end

local function reset_loot_target ()
  KLD.unit_name = nil
  KLD.unit_guid = nil
  KLD.unit_realguid = false
end

local function populate_loot_target ()
  local uname = UnitName ("target")
  local uguid = UnitGUID ("target")
  local realguid = true

  if (not uname or uname == "") then
    if (KLD.chest_name and KLD.chest_name ~= "") then
      uname = KLD.chest_name
    else
      uname = L["Chest"]
    end
  end

  if (not uguid or uguid == "") then
    uguid = 0
    realguid = false
    if (KLD.chest_name and KLD.chest_name ~= "") then
      uguid = KLD.chest_name
    end
  end

  KLD.unit_name = uname
  KLD.unit_guid = uguid
  KLD.unit_realguid = realguid
end

--
-- Function: KLD.LootReady ()
-- Purpose : Retrieve all of the item info from the target. This event seems
--           to be fired when all of the loot information is ready from the
--           server. This should be the event that mods use to trigger the
--           actual looting process.
-- Fires   : LOOTING_READY
--
function KLD.LootReady ()
  if (not KLD.initialised) then
    return
  end

  if (KLD.skip_loot) then
    KLD.skip_loot = nil
    return
  end

  reset_items ()
  reset_loot_target ()

  populate_loot_target ()
  populate_items ()

  KLD:SendIPC ("LOOTING_READY")
end

--
-- Function: KLD.LootClosed ()
-- Purpose : End of the loot process. This resets the loot table and boss info
--           to nil.
-- Fires   : LOOTING_ENDED
--
function KLD.LootClosed ()
  if (not KLD.initialised) then
    return
  end

  reset_items ()
  reset_loot_target ()

  KLD.chest_name = nil

  KLD:SendIPC ("LOOTING_ENDED")
end

--
-- Function: KLD.RefreshLoot ()
-- Purpose : Refresh the internal view of the loot items on the current
--           corpse. This should only ever be called when we know that
--           we have a valid corpse and that loot is not being skipped.
-- Fires   : ITEMS_UPDATED
--
function KLD.RefreshLoot ()
  if (KLD.initialised) then
    return
  end

  reset_loot_target ()
  reset_items ()

  populate_loot_target ()
  populate_items ()
end

--
-- Function: KLD.GiveMasterLoot (slot, target)
-- Purpose : Give the loot in KLD.items[slot] to the specified target. If
--           master looting is not active, or the slot is invalid, returns
--           1. If the slot and the target are valid but the target is not
--           in the list of valid recipients for the item, returns 2. If
--           there was no error, return 0.
-- Fires   : LOOT_ASSIGNED (slot, target)
--
function KLD.GiveMasterLoot (slot, target)
  if (not KLD.initialised or not KLD.master_loot or not slot or slot < 1
      or not target or target == "" or not KLD.items
      or KLD.num_items < 1 or not KLD.items[slot]) then
    return 1
  end

  local cand = KLD.items[slot].candidates

  if (not cand or not cand[target]) then
    return 2
  end

  GiveMasterLoot (slot, cand[target].index)

  KLD:SendIPC ("LOOT_ASSIGNED", slot, target)
  return 0
end

local function krp_lm_updated (evt, new_method, ...)
  if (new_method == LOOT_METHOD_MASTER) then
    KLD.master_loot = true
  else
    KLD.master_loot = false
  end
end

local function unit_spellcast_succeeded (evt, caster, sname, rank, tgt)
  if (caster == "player") then
    if (sname == OPENING) then
      KLD.chest_name = tgt
      return
    end

    if ((sname == disenchant_name) or (sname == herbalism_name) or
        (sname == mining_name)) then
      KLD.skip_loot = true
    end
  end
end

local function kld_do_refresh (evt, ...)
  if (not KLD.initialised) then
    return
  end
  KLD.RefreshLoot ()
  KLD:SendIPC ("LOOTING_READY")
end

--
-- When an addon is suspended or resumed, we need to do a refresh because
-- the addon may have callbacks that have either been populated and now
-- need to be removed (addon suspended) or needs to add new data via the
-- callbacks (addon resumed). So we trap these two events and use them to
-- schedule a refresh.
--
local function kld_act_susp (evt, ...)
  KLD:SendIPC ("DO_REFRESH")
end

local function kld_initialised (evt, ...)
  if (KLD.initialised) then
    return
  end

  KLD:RegisterEvent ("LOOT_READY", function (evt)
    KLD.LootReady()
  end)
  KLD:RegisterEvent ("LOOT_CLOSED", function (evt)
    KLD.LootClosed()
  end)
  KLD:RegisterEvent ("UNIT_SPELLCAST_SUCCEEDED", unit_spellcast_succeeded)

  KLD:RegisterIPC ("ACTIVATE_ADDON", kld_act_susp)
  KLD:RegisterIPC ("SUSPEND_ADDON", kld_act_susp)
  KLD:RegisterIPC ("DO_REFRESH", kld_do_refresh)

  KRP:RegisterIPC ("LOOT_METHOD_UPDATED", krp_lm_updated)

  KLD.initialised = true
end

function KLD:OnLateInit ()
  KLD:RegisterIPC ("INITIALISED", kld_initialised)

  KLD:SendIPC ("INITIALISED")
end

