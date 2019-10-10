-- 
-- KahLua Kore - Basic support functions used by all KahLua modules.
--

--
-- KKoreDB is the KahLua'ed version of AceDB-3.0, a library that allows you to
-- create profiles and smart default values for an addon's SavedVariables.
--
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

local KKOREDB_MAJOR = "KKoreDB"
local KKOREDB_MINOR = 3
local KDB, oldminor = LibStub:NewLibrary(KKOREDB_MAJOR, KKOREDB_MINOR)

if (not KDB) then
  return
end

-- Local aliases for global or Lua library functions
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local getmetatable = getmetatable
local rawset, rawget = rawset, rawget
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
local pairs, next, type, error = pairs, next, type, error
local select, assert, loadstring = select, assert, loadstring
local _G = _G

local K, KM = LibStub:GetLibrary("KKore")
assert (K, "KKoreDB requires KKore")
assert (tonumber(KM) >= 3, "KKoreDB requires KKore r3 or later")
K:RegisterExtension (KDB, KKOREDB_MAJOR, KKOREDB_MINOR)

KDB.db_registry = KDB.db_registry or {}
KDB.frame = KDB.frame or CreateFrame("Frame", "KKoreDBFrame")

local dbobjectlib = {}
local copytable = K.CopyTable

--
-- Called to add defaults to a section of the database.
--
-- When a ["*"] default section is indexed with a new key, a table is
-- returned and set in the host table. These tables must be cleaned up
-- by removeDefaults in order to ensure we don't write empty default tables.
--
local function copydefaults(src,dest)
  for k,v in pairs(src) do
    if ((k == "*") or (k == "**")) then
      if (type(v) == "table") then
        local mt = {
          __index = function(t,k)
            if (k == nil) then
              return nil
            end
            local tbl = {}
            copydefaults(v, tbl)
            rawset(t, k, tbl)
            return tbl
          end
        }
        setmetatable(dest, mt)
        -- Handle already existing tables in the SV
        for dk,dv in pairs(dest) do
          if (not rawget(src, dk) and type(dv) == "table") then
            copydefaults(v, dv)
          end
        end
      else
        -- Values are not tables, so this is just a simple return.
        local mt = {
          __index = function(t,k)
            return k ~= nil and v or nil
          end
        }
        setmetatable(dest, mt)
      end
    elseif (type(v) == "table") then
      if (not rawget(dest, k)) then
        rawset(dest, k, {})
      end
      if (type(dest[k]) == "table") then
        copydefaults(v, dest[k])
        if (src == "**") then
          copydefaults(src["**"], dest[k])
        end
      end
    else
      if (rawget(dest, k) == nil) then
        rawset(dest, k, v)
      end
    end
  end
end

--
-- Called to remove all defaults in the default table from the database
--
local function removedefaults(db, defaults, blocker)
  setmetatable(db, nil)
  for k,v in pairs(defaults) do
    if ((k == "*") or (k == "**")) then
      if (type(v) == "table") then
        -- Loop through all the actual k,v pairs and remove
        for key,val in pairs(db) do
          if (type(val) == "table") then
            -- If the key was not explicitly specified in the defaults table,
            -- just strip everything from * and ** tables.
            if ((defaults[key] == nil) and (not blocker or blocker[key]==nil)) then
              removedefaults(val, v)
              -- If the table is empty afterwards, remove it.
              if (next(val) == nil) then
                db[key] = nil
              end
            elseif (k == "**") then
              -- If it was specified, only strip ** content, but block values
              -- which were set in the key table.
              removedefaults(val, v, defaults[key])
            end
          end
        end
      elseif (k == "*") then
        -- Check for non-table default
        for key,val in pairs(db) do
          if (defaults[key] == nil and v == val) then
            db[key] = nil
          end
        end
      end
    elseif (type(v) == "table" and type(db[k]) == "table") then
      -- If a blocker was set, dive into it, to allow multi-level defaults
      removedefaults(db[k], v, blocker and blocker[k])
      if (next(db[k]) == nil) then
        db[k] = nil
      end
    else
      -- Check if the current value matches the default, and that it is not
      -- blocked by another defaults table.
      if (db[k] == defaults[k] and (not blocker or blocker[k] == nil)) then
        db[k] = nil
      end
    end
  end
end

--
-- This is called when a table section is first accessed to set up the defaults
--
local function initsection(db, section, svstore, key, defaults)
  local sv = rawget(db, "sv")

  local tablecreated
  if (not sv[svstore]) then
    sv[svstore] = {}
  end
  if (not sv[svstore][key]) then
    sv[svstore][key] = {}
    tablecreated = true
  end

  local tbl = sv[svstore][key]

  if (defaults) then
    copydefaults(defaults, tbl)
  end
  rawset(db, section, tbl)

  return tablecreated, tbl
end

--
-- Metatable to handle the dynamic creation of sections and copying of sections.
--
local dbmt = {
  __index = function(t, section)
    local keys=rawget(t, "keys")
    local key = keys[section]
    if (key) then
      local defaulttbl = rawget(t, "defaults")
      local defaults = defaulttbl and defaulttbl[section]

      if (section == "profile") then
        local new = initsection(t, section, "profiles", key, defaults)
        if (new) then
          t.callbacks:Fire("OnNewProfile", t, key)
        end
      elseif (section == "profiles") then
        local sv = rawget(t, "sv")
        if (not sv.profiles) then
          sv.profiles = {}
        end
        rawset(t, "profiles", sv.profiles)
      elseif (section == "global") then
        local sv = rawget(t, sv)
        if (not sv.global) then
          sv.global = {}
        end
        if (defaults) then
          copydefaults(defaults, sv.global)
        end
        rawset(t, section, sv.global)
      else
        initsection(t, section, section, key, defaults)
      end
    end

    return rawget(t, section)
  end
}

local function validatedefaults(defaults,keytbl, offset)
  if (not defaults) then
    return
  end
  offset = offset or 0
  for k in pairs(defaults) do
    if (not keytbl[k] or k == "profiles") then
      error(("KKoreDB:RegisterDefaults: %s is not a valid datatype."):format(k), 3 + offset)
    end
  end
end

local preserve_keys = {
  ["callbacks"] = true,
  ["RegisterCallback"] = true,
  ["UnregisterCallback"] = true,
  ["UnregisterAllCallbacks"] = true,
  ["children"] = true
}

local realm = GetRealmName()
local toon = UnitName("player") .. "-" .. realm
local _, class = UnitClass("player")
local _,race = UnitRace("player")
local faction = UnitFactionGroup("player")
local factionrealm = faction .. "-" .. realm
local locale = GetLocale():lower()

local regiontable = { "US", "KR", "EU", "TW", "CN" }
local region = _G["GetCurrentRegion"] and regiontable[GetCurrentRegion()] or string.sub(GetCVar("realmList"), 1, 2):upper()
local factionrealmregion = factionrealm .. " - " .. region

-- Actual database initialization function
local function initdb(sv, defaults, defaultprofile, olddb, parent)
  -- Generate the database keys for each section

  -- map "true" to our "Default" profile
  if (defaultprofile == true) then
    defaultprofile = "Default"
  end

  local profileKey
  if (not parent) then
    -- Make a container for profile keys
    if (not sv.profileKeys) then
      sv.profileKeys = {}
    end

    -- Try to get the profile selected from the char db
    profileKey = sv.profileKeys[toon] or defaultprofile or toon

    -- save the selected profile for later
    sv.profileKeys[toon] = profileKey
  else
    -- Use the profile of the parents DB
    profileKey = parent.keys.profile or defaultprofile or toon

    -- clear the profileKeys in the DB, namespaces don't need to store them
    sv.profileKeys = nil
  end

  -- This table contains keys that enable the dynamic creation of each
  -- section of the table. The 'global' and 'profiles' have a key value of
  -- true, since they are handled in a special case.
  local keytbl = {
    ["char"] = toon,
    ["realm"] = realm,
    ["class"] = class,
    ["race"] = race,
    ["faction"] = faction,
    ["factionrealm"] = factionrealm,
    ["factionrealmregion"] = factionrealmregion,
    ["profile"] = profileKey,
    ["locale"] = locale,
    ["global"] = true,
    ["profiles"] = true
  }

  validatedefaults(defaults, keytbl, 1)

  -- This allows us to use this function to reset an entire database.
  -- Clear out the old database.
  if (olddb) then
    for k,v in pairs(olddb) do
      if (not preserve_keys[k]) then
        olddb[k] = nil
      end
    end
  end

  local db = setmetatable(olddb or {}, dbmt)

  if (not rawget(db, "callbacks")) then
    db.callbacks = K:NewCB(db)
  end

  -- Copy methods locally into teh database object, to avoid hitting the
  -- metatable when calling methods.
  if (not parent) then
    for n,f in pairs(dbobjectlib) do
      db[n] = f
    end
  else
    db.RegisterDefaults = dbobjectlib.RegisterDefaults
    db.ResetProfile = dbobjectlib.ResetProfile
  end

  -- Set some properties in the database object
  db.profiles = sv.profiles
  db.keys = keytbl
  db.sv = sv
  db.defaults = defaults
  db.parent = parent

  -- Store the database in the registry
  KDB.db_registry[db] = true

  return db
end

-- Handle PLAYER_LOGOUT. Strip all defaults from all databases.
local function logouthandler(frame,event)
  if (event == "PLAYER_LOGOUT") then
    for db in pairs(KDB.db_registry) do
      db.callbacks:Fire("OnDatabaseShutdown", db)
      db:RegisterDefaults (nil)
      local sv = rawget (db, "sv");
      for sect in pairs (db.keys) do
        if (rawget (sv, sect)) then
          if ((sect ~= "global") and ((sect ~= "profiles") or (rawget (db, "parent")))) then
            for key in pairs (sv[sect]) do
              if (not next (sv[sect][key])) then
                sv[sect][key] = nil
              end
            end
          end
          if (not next (sv[sect])) then
            sv[sect] = nil
          end
        end
      end
    end
  end
end

KDB.frame:RegisterEvent("PLAYER_LOGOUT")
KDB.frame:SetScript("OnEvent", logouthandler)

-- Object Methods
function dbobjectlib:RegisterDefaults(defaults)
  if (defaults and type(defaults) ~= "table") then
    error ("KKoreDB:RegisterDefaults: table or nil expected.", 2)
  end

  validatedefaults(defaults, self.keys)

  -- Remove any currently set defaults
  if (self.defaults) then
    for sect,key in pairs(self.keys) do
      if (self.defaults[sect] and rawgets(self, sect)) then
        removedefaults(self[sect], self.defaults[sect])
      end
    end
  end

  -- Set the dbobject.defaults table
  self.defaults = defaults

  -- Copy in any defaults, only touching those sections already created.
  if (defaults) then
    for sect,key in pairs(self.keys) do
      if (defaults[sect] and rawget(self, sect)) then
        copydefaults(defaults[sect], self[sect])
      end
    end
  end
end

-- Changes the profile of the database and all of its namespaces to the
-- supplied names profile.
function dbobjectlib:SetProfile(name)
  if (not name or type(name) ~= "string") then
    error ("KKoreDB:SetProfile: string expected as only argument.", 2)
  end

  -- Do nothing if changing to the same profile
  if (self.keys.profile == name) then
    return
  end

  local oldprof = self.profile
  local defaults = self.defaults and self.defaults.profile

  self.callbacks:Fire("OnProfileShutdown", self)

  if (oldprof and defaults) then
    -- Remove the defaults from the old profile
    removedefaults(oldprof, defaults)
  end

  self.profile = nil
  self.keys["profile"] = name

  -- if the storage exists, save the new profile
  -- this won't exist on namespaces.
  if (self.sv.profileKeys) then
    self.sv.profileKeys[toon] = name
  end

  -- Populate child namespces
  if (self.children) then
    for _,db in pairs(self.children) do
      dbobjectlib.SetProfile(db,name)
    end
  end

  self.callbacks:Fire("OnProfileChanged", self, name)
end

-- Returns a table with the names of the existing profiles in the database.
-- You can optionally supply a table to re-use for this purpose.
function dbobjectlib:GetProfiles(tbl)
  if (tbl and type(tbl) ~= "table") then
    error ("KKoreDB:GetProfiles: table or nil expected.", 2)
  end

  if (tbl) then
    for k,v in pairs(tbl) do
      tbl[k] = nil
    end
  else
    tbl = {}
  end

  local cuprofile = self.keys.profile
  local i = 0
  for pkey in pairs(self.profiles) do
    i = i + 1
    tbl[i] = pkey
    if (curprofile and pkey == curprofile) then
      curprofile = nil
    end
  end

  -- Add the current profile, if it hasn't been created yet
  if (curprofile) then
    i = i + 1
    tbl[i] = curprofile
  end

  return tbl,i
end

-- Returns the current profile name used by the database
function dbobjectlib:GetCurrentProfile()
  return self.keys.profile
end

-- Deletes a named profile. This profile must not be the active profile.
function dbobjectlib:DeleteProfile(name, silent)
  if (type(name) ~= "string") then
    error ("KKoreDB:DeleteProfile: string expected.", 2)
  end

  if (self.keys.profile == name) then
    error ("KKoreDB:DeleteProfile: cannot delete the active profile.", 2)
  end

  if (not rawget(self.profiles, name) and not silent) then
    error ("KKoreDB:DeleteProfile: cannot delete non-existing profile '" .. name .. "'.", 2)
  end

  self.profiles[name] = nil

  -- Delete child namespaces
  if (self.children) then
    for _,db in pairs(self.children) do
      dbobjectlib.DeleteProfile(db, name, true)
    end
  end

  if (self.sv.profileKeys) then
    for key, prof in pairs(self.sv.profileKeys) do
      if (prof == name) then
        self.sv.profileKeys[key] = nil
      end
    end
  end

  self.callbacks:Fire("OnProfileDeleted", self, name)
end

-- Copies a named profile into the current profile, overwriting any
-- conflicting settings.
function dbobjectlib:CopyProfile(name, silent)
  if (type(name) ~= "string") then
    error ("KKoreDB:CopyProfile: string expected.", 2)
  end

  if (self.keys.profile == name) then
    error ("KKoreDB:CopyProfile: cannot copy a profile onto itself.", 2)
  end

  if (not rawget(self.profiles, name) and not silent) then
    error ("KKoreDB:CopyProfile: cannot copy non-existing profile '" .. name .. "'.", 2)
  end

  -- Reset the profile before copying
  dbobjectlib.ResetProfile(self, nil, true)

  local profile = self.profile
  local src = self.profiles[name]

  copytable(src, profile)

  if (self.children) then
    for _,db in pairs(self.children) do
      dbobjectlib.CopyProfile(db, name, true)
    end
  end

  self.callbacks:Fire("OnProfileCopied", self, name)
end

-- Resets the current profile to the default values (if specified).
function dbobjectlib:ResetProfile(nochildren, nocallbacks)
  local profile = self.profile

  for k,v in pairs(profile) do
    profile[k] = nil
  end

  local defaults = self.defaults and self.defaults.profile
  if (defaults) then
    copydefaults(defaults, profile)
  end

  if (self.children and not nochildren) then
    for _,db in pairs(self.children) do
      dbobjectlib.ResetProfile(db, nil, nocallbacks)
    end
  end

  if (not nocallbacks) then
    self.callbacks:Fire("OnProfileReset", self)
  end
end

-- Resets the entire database, using the given profile as the new default.
function dbobjectlib:ResetDB(dprofile)
  if (dprofile and type(dprofile) ~= "string") then
    error ("KKoreDB:ResetDB: string expected.", 2)
  end

  local sv = self.sv
  for k,v in pairs(sv) do
    sv[k] = nil
  end

  local parent = self.parent
  initdb(sv, self.defaults, dprofile, self)

  if (self.children) then
    if (not sv.namespaces) then
      sv.namespaces = {}
    end
    for name,db in pairs(self.children) do
      if (not sv.namespaces[name]) then
        sv.namespace[name] = {}
      end
      initdb(sv.namespaces[name], db.defaults, self.keys.profile, db, self)
    end
  end

  self.callbacks:Fire("OnDatabaseReset", self)
  self.callbacks:Fire("OnProfileChanged", self, self.keys["profile"])

  return self
end

--
-- Create a new dattabase namespace, directly tied to the database. This
-- is a full scale database in its own rights other than the fact that
-- it cannot control its profile individually.
--
function dbobjectlib:RegisterNamespace(name, defaults)
  if (type(name) ~= "string") then
    error ("KKoreDB:RegisterNamespace: string expected.", 2)
  end

  if (defaults and type(defaults) ~= "table") then
    error ("KKoreDB:RegisterNamespace: table or nil expected.", 2)
  end

  if (self.children and self.children[name]) then
    error ("KKoreDB:RegisterNamespace: a namespace with that name already exists.", 2)
  end

  local sv = self.sv
  if (not sv.namespaces) then
    sv.namespaces = {}
  end
  if (not sv.namespaces[name]) then
    sv.namespaces[name] = {}
  end

  local newdb
  newdb = initdb(sv.namespaces[name], defaults, self.keys.profile, nil, self)
  if (not self.children) then
    self.children = {}
  end
  self.children[name] = newdb
  return newdb
end

function dbobjectlib:GetNamespace(name, silent)
  if (type(name) ~= "string") then
    error("KKoreDB:GetNamespace: string expected.", 2)
  end

  if (not silent and not (self.children and self.children[name])) then
    error ("KKoreDB:GetNamespace: namespace does not exist.", 2)
  end

  if (not self.children) then
    self.children = {}
  end

  return self.children[name]
end

--
-- KKoreDB exposed methods
--
function KDB:New(tbl, defaults, dprofile)
  if (type(tbl) == "string") then
    local name = tbl
    tbl = _G[name]
    if (not tbl) then
      tbl = {}
      _G[name] = tbl
    end
  end

  if (type(tbl) ~= "table") then
    error ("KKoreDB:New: 'tbl' - table expected.", 2)
  end

  if (defaults and type(defaults) ~= "table") then
    error ("KKoreDB:New: 'defaults' - table expected.", 2)
  end

  if (dprofile and type(dprofile) ~= "string") then
    error ("KKoreDB:New: 'dprofile' - string expected.", 2)
  end

  return initdb(tbl, defaults, dprofile)
end

