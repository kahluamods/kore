--[[
   KahLua Kore - the character info check.
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

local K, KM = LibStub:GetLibrary("Kore")
assert(K, "Kore CharInfo requires Kore")
assert(tonumber(KM) >= 1, "Kore CharInfo requires Kore r1 or later")

local tonumber = tonumber
local ipairs = ipairs

--
-- WHAT THIS CHARACTER REPORTS ABOUT ITSELF
--
-- A character's class, race and level are the game's to say and nobody asks the player about them. Its roles and its
-- professions are not so simple. The game cannot say which roles a player raids in, the talents saying only what they are
-- playing right now, and it will say which trade skills are known but not which a player wants a raid to count on. So those
-- are the player's own and are kept per character in Kore's database. Roles have no answer until the player gives one, and
-- professions stand at the game's answer until the player says otherwise.
--
-- They live here, in Kore, rather than with the mod that asks, because they are facts about the player's own character and
-- every KahLua mod on the client reads the same answer out of the same database. The dialog that asks the player is the
-- mod's (Konfer's RaidInfo.lua), and so is the check that asks everybody else (Konfer's CharInfo.lua). Neither is Kore's.
--
--
-- Whether ROLE is one the player's own class can play, K.ROLE_UNSET counting as one. A number stored for a class this
-- character is not, or one this client's class cannot play, is not ours to report.
--
local function my_role(role)
  if (role == K.ROLE_UNSET) then
    return true
  end

  for _, r in ipairs(K.ClassRoles[K.player.class] or {}) do
    if (r == role) then
      return true
    end
  end

  return false
end

--
-- The main role and off role this character reports: what the player chose, or none until they have, except that a class
-- that plays one role alone plays it as its main whether the player has said so or not.
--
function K.MyRoles()
  local chardb = K.chardb

  if (chardb and chardb.msrole ~= nil and my_role(chardb.msrole) and my_role(chardb.osrole or K.ROLE_UNSET)) then
    return chardb.msrole, chardb.osrole or K.ROLE_UNSET
  end

  local roles = K.ClassRoles[K.player.class] or {}

  return (#roles == 1) and roles[1] or K.ROLE_UNSET, K.ROLE_UNSET
end

--
-- A profession this client has, or none. A number stored by a client that had a profession this one does not, an inscriber
-- on a database later opened on a vanilla character, is not one we can report and falls back to what the game says.
--
local function my_prof(prof)
  return prof == K.PROF_UNSET or (prof ~= nil and K.IndexProf[prof] ~= nil)
end

--
-- The two professions this character reports: what the player chose, or the game's until they have chosen. The game knows
-- a character's professions for certain, so this only ever differs where the player has said otherwise, which is theirs to
-- do.
--
function K.MyProfessions()
  local chardb = K.chardb

  if (chardb and chardb.pprof ~= nil and my_prof(chardb.pprof) and my_prof(chardb.sprof)) then
    return chardb.pprof, chardb.sprof or K.PROF_UNSET
  end

  return K.PlayerProfessions()
end

--
-- What the player chose, written down. These are what a mod's own roles dialog calls when the player presses Ok on it, and
-- nothing else writes them. Passing nil for the roles leaves them unset, and for the professions puts the character back
-- on whatever the game says.
--
function K.SetMyRoles(msrole, osrole)
  if (not K.chardb) then
    return
  end

  K.chardb.msrole = msrole
  K.chardb.osrole = osrole
end

function K.SetMyProfessions(pprof, sprof)
  if (not K.chardb) then
    return
  end

  K.chardb.pprof = pprof
  K.chardb.sprof = sprof
end

--
-- Everything this character reports about itself, in one call, for a mod that wants the facts without asking anybody. The
-- caller writes them wherever it keeps such things; this only reads.
--
function K.MyFacts()
  local msrole, osrole = K.MyRoles()
  local pprof, sprof = K.MyProfessions()

  return K.player.class, K.player.race, K.player.level, msrole, osrole, pprof, sprof
end
