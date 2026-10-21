--[[
   KahLua Kore - the people, and what is true of each of them.
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

local KRP, KM = LibStub:GetLibrary("KoreParty")
assert(KRP, "Kore UserDB requires KoreParty")
assert(tonumber(KM) >= 1, "Kore UserDB requires KoreParty r1 or later")

local L = LibStub("AceLocale-3.0"):GetLocale("Kore")

local tinsert = table.insert
local tremove = table.remove
local tsort = table.sort
local tconcat = table.concat
local strfmt = string.format
local tonumber = tonumber
local pairs, ipairs, next = pairs, ipairs, next

local aclass = KRP.AlwaysClassString

--
-- KORE.USERS
--
-- The people themselves, and what is true of each of them. A consumer declares "local KU = Kore.Users" and everything here
-- is on that. It is Kore's rather than any one mod's because a character's class, race, level, roles and professions are
-- facts about the game's own characters and are the same facts whichever mod asked after them, so every KahLua mod on the
-- client reads and writes the one table rather than each keeping a copy that drifts from the others.
--
-- What a *mod* thinks of a person is emphatically not here. Konfer's opinion of a user inside one of its configs lives on
-- that config, keyed by a uid that means nothing outside it.
--
-- THREE NAMES FOR ONE PERSON
--
-- A character's Name, the canonical "Name-Realm", is the one thing every client agrees on, and is what travels whenever
-- people are spoken of between clients with nothing else in common. Each client also gives every character it knows a KUID
-- of its own, four lower-case hex digits issued here in turn and never reused, and everything kept about a person, here or
-- in a mod, points at them by it. A KUID never leaves this client: another client has its own for the same character, so a
-- KUID on the wire would name somebody else there, or nobody. A mod's config has a third, its uid, which every copy of that
-- config shares and which means nothing outside it; each copy maps it to that client's own KUID.
--
-- So a person is stored by KUID and spoken of by Name. KU:Find turns a Name into a KUID and KU.kuids turns one back, and every
-- function here that is about a person takes a KUID. The handful that take a Name are the doors a Name comes in by: KU:Add,
-- KU:Find, KU:Rename's new name and what arrives from another client.
--
local KU = {}
K.Users = KU

--
-- What is kept about a character is what is true of them, a matter of fact rather than anybody's opinion. One thing alone is
-- the exception and is this player's own, never sent to anybody, and that is their notes on the person.
--
-- Whose alt somebody is is a fact like the rest. A human has one main and every other character of theirs is an alt of it,
-- so a link is one level deep and is the same wherever that person appears. Nobody is an alt in one raid and a main in the
-- next. Who says so is whoever administers the configurations they are in rather than the character themselves, and it
-- travels, which is how every client in a raid resolves an alt the same way.
--
-- KU.users holds the people of this faction and realm by Name, each a positional array indexed by the USER_ constants:
--
--   USER_KUID    This client's own id for them, which never changes and is never given to anybody else.
--   USER_CLASS   The Kore class number, K.CLASS_DRUID and the rest.
--   USER_PPROF   The first profession, as Kore's profession number, K.PROF_ALCHEMY and the rest, or nil for none.
--   USER_SPROF   The second, the same way.
--   USER_ALTOF   The KUID of the person this one is an alt of, or nil. That person is in this table.
--   USER_ALTS    An array of the KUIDs of this person's alts, in no order, or nil when they have none.
--   USER_NOTES   What this player thinks of them, or nil. See NOTES_ below.
--   USER_MSROLE  Their main role, as a K.ROLE_ number, one their class can play, or nil for none.
--   USER_OSROLE  Their off role, the same way.
--   USER_RACE    The game's own race id, as K.RaceName takes, or nil for a race nobody has told us.
--   USER_LEVEL   What level the character had reached when we last heard, or nil.
--
-- KU.kuids is the other way round, KUID to Name. Every record carries its own KUID, so it is rebuilt from them at login and
-- never saved, and the two cannot disagree. A Name is a key and nothing else points at one, so a rename moves one record and
-- changes one entry there, and everything that points at the person by KUID is untouched.
--
-- A person is either an alt or has alts, never both, so there is only ever one level to an alt link and USER_ALTOF and
-- USER_ALTS are never both set. The two directions are kept together by KU:SetMain and nothing else writes them.
--
-- Nobody is ever added behind the user's back. Everything that creates a person is something the user asked for, and the
-- player's own character, who is added at login (KU:Startup).
--
KU.USER_KUID   = 1
KU.USER_CLASS  = 2
KU.USER_PPROF  = 3
KU.USER_SPROF  = 4
KU.USER_ALTOF  = 5
KU.USER_ALTS   = 6
KU.USER_NOTES  = 7
KU.USER_MSROLE = 8
KU.USER_OSROLE = 9
KU.USER_RACE   = 10
KU.USER_LEVEL  = 11

--
-- Notes are this player's own opinion, where everything else on a record is fact. They are never sent to anybody and
-- nothing that arrives from anybody touches them, so they are edited in the user editor alone and stored the moment they
-- change. A notes table is a positional array too, indexed by the NOTES_ constants, and is nil once empty:
--
--   NOTES_RATINGS  How good they are at each of the RATE_ things, as a table from a RATE_ constant to a RATING_ one, a
--                  thing not rated having no entry. Nil when nothing is rated.
--   NOTES_TEXT     Whatever else this player wants to remember about them, in their own words. Nil when they have written
--                  nothing.
--
-- The RATE_ constants are what can be rated and RATING_ what a rating can be, from RATING_TERRIBLE, somebody to avoid, to
-- RATING_EXCELLENT. KU:Rating and KU:SetRating read and write them.
--
KU.NOTES_RATINGS = 1
KU.NOTES_TEXT    = 2

KU.RATE_HEALER    = 1
KU.RATE_TANK      = 2
KU.RATE_MELEE     = 3
KU.RATE_RANGED    = 4
KU.RATE_ETIQUETTE = 5
KU.RATE_KNOWLEDGE = 6
KU.RATE_HELPFUL   = 7

KU.RATING_TERRIBLE  = 1
KU.RATING_BIND      = 2
KU.RATING_ORDINARY  = 3
KU.RATING_ABOVE     = 4
KU.RATING_GOOD      = 5
KU.RATING_EXCELLENT = 6

--
-- What one client tells another about a character, as a positional array indexed by the WUSER_ constants: the name and then
-- the facts, each of them missing where the sender has nothing to say about it. Every wire path that carries a person
-- carries this row, KU:WireRow packs one and KU:OfferUserFacts and KU:UserFactChanges take them. It names the person by Name,
-- a KUID meaning nothing to anybody else.
--
-- Nothing a mod keeps of its own is in it, and neither is anything that is somebody's opinion rather than a fact. Notes
-- never leave this client at all.
--
-- The alt link is not in it either, though it is a fact and it does travel. Everything in this row is something the game
-- itself can prove, so what a sender says about it is put to the player as an offer. Who is whose alt the game cannot prove
-- and the people running the raid can, so it rides beside this row and is taken as it stands.
--
KU.WUSER_NAME   = 1
KU.WUSER_CLASS  = 2
KU.WUSER_PPROF  = 3
KU.WUSER_SPROF  = 4
KU.WUSER_MSROLE = 5
KU.WUSER_OSROLE = 6
KU.WUSER_RACE   = 7
KU.WUSER_LEVEL  = 8

local USER_KUID = KU.USER_KUID
local USER_CLASS = KU.USER_CLASS
local USER_PPROF = KU.USER_PPROF
local USER_SPROF = KU.USER_SPROF
local USER_ALTOF = KU.USER_ALTOF
local USER_ALTS  = KU.USER_ALTS
local USER_NOTES = KU.USER_NOTES
local USER_MSROLE = KU.USER_MSROLE
local USER_OSROLE = KU.USER_OSROLE
local USER_RACE = KU.USER_RACE
local USER_LEVEL = KU.USER_LEVEL

local WUSER_NAME   = KU.WUSER_NAME
local WUSER_CLASS  = KU.WUSER_CLASS
local WUSER_PPROF  = KU.WUSER_PPROF
local WUSER_SPROF  = KU.WUSER_SPROF
local WUSER_MSROLE = KU.WUSER_MSROLE
local WUSER_OSROLE = KU.WUSER_OSROLE
local WUSER_RACE   = KU.WUSER_RACE
local WUSER_LEVEL  = KU.WUSER_LEVEL

local NOTES_RATINGS = KU.NOTES_RATINGS
local NOTES_TEXT = KU.NOTES_TEXT

--
-- How far a child row's words are set in from its parent's wherever people are drawn as a tree, an alt under their main most
-- of all. One number, so that every window showing the same relationship indents it the same way.
--
KU.TREE_LEAD = 8

--
-- What a window of Kore's own calls itself. It names no mod, the user editor and the offers window belonging to no mod in
-- particular, so the plate is the suite and then the window. See K.WindowTitle.
--
function KU:WindowTitle(what)
  return K.WindowTitle(nil, nil, what)
end

--
-- THE MODS THAT USE THIS
--
-- Kore knows nothing about configs, rosters or whatever else a mod keeps people in, so where a change here means a mod has
-- work to do, the mod is asked rather than reached into. A consumer registers once and may supply any of:
--
--   UserConfigs (kuid) -> array of { name = <what the mod calls this grouping>, owner = <what to call the mod> } for every
--                         place this mod still holds KUID. What stops a person being deleted while somebody is using them.
--   UsersChanged ()                 Who we know, or what is true of them, changed. Redraw anything showing a person. A
--                                   rename is one of these: whatever a mod keeps points at the person by KUID, so it has
--                                   nothing to put right and only has a name to draw differently.
--   UserMainChanged (kuid)          This player just set whose alt KUID is, in the user editor, where there is no config in
--                                   hand. The link is one fact that every config reads, so a mod carrying it between clients
--                                   tells the ones it administers. Only a link set here is announced. One that arrived is
--                                   already on its way round the raid and saying so again would put it round a second time.
--   StandAside (who) -> true if it put something away. One of Kore's own windows is about to open, WHO saying which:
--                       "editor", the user editor, or "offers", what another client would change about the people we know.
--                       A mod with a window of its own on screen that this one should not sit over puts it away and says
--                       so. What that is may differ by WHO, the editor standing in for one room and the offers interrupting
--                       whichever is up.
--   ComeBack (who)      That window has closed. Put back whatever StandAside took away for WHO. Only the mods that answered
--                       true are told.
--
-- StandAside and ComeBack are how Kore's windows can take a mod's window off the screen without knowing that mod has windows
-- at all. Kore has nothing of its own to move and no opinion about anybody else's.
--
KU.consumers = {}

function KU:RegisterConsumer(handle, tbl)
  if (not handle or type(handle) ~= "string" or handle == "") then
    return false
  end

  KU.consumers[handle] = tbl or {}

  return true
end

--
-- Call CB on every consumer that has one, with the consumer's own table as self.
--
local function consumers(cb, ...)
  for _, tbl in pairs(KU.consumers) do
    if (tbl[cb]) then
      tbl[cb](tbl, ...)
    end
  end
end

-- As high as a level is allowed to be before it is somebody's mistake rather than a character. The game's own ceiling moves
-- every expansion and is not worth chasing, since this is here to throw out nonsense, not to police the client.
local MAX_LEVEL = 255

--
-- The users of this faction and realm, as the mod knows them: what is true of each character whatever config they are in.
-- KU.users documents the record. Everything about a person takes their KUID, never a uid, because a uid belongs to one config
-- and nothing at this level has a config in hand.
--
-- A config's entry for a user is a policy's own opinion of them. What is kept here is fact, and it is edited in the mod's
-- own user editor, and from any policy's Users page, because a fact is the same whoever is looking at it.
--
-- Where something here changes what a config should look like, most of all an alt link moving a tethered list, each policy
-- is told about it through the methods RegisterPolicy gives it, and puts its own configs right. Nothing here reaches into a config itself.
--

--
-- At login, once the database is there (kore_database): the KUID-to-Name table, built from the records, and the counter
-- KUIDs are issued from, which starts at 1 and only ever goes up, so that a KUID once given is never anybody else's.
--
function KU:Startup()
  self.kuids = {}

  for name, rec in pairs(self.users) do
    self.kuids[rec[USER_KUID]] = name
  end

  if (not K.frdb.nextkuid) then
    K.frdb.nextkuid = 1
  end
end

--
-- The next KUID, four lower-case hex digits.
--
local function new_kuid()
  local n = K.frdb.nextkuid

  K.frdb.nextkuid = n + 1

  return strfmt("%04x", n)
end

--
-- The KUID of the character NAME, given in any form K.CanonicalName accepts, so that a bare name means a character on this
-- realm. Nil for somebody the mod does not know. This is how a Name from outside, off the wire, out of the roster or typed,
-- becomes the person it is.
--
function KU:Find(name)
  local key = name and K.CanonicalName(name)
  local rec = key and self.users and self.users[key]

  return rec and rec[USER_KUID] or nil
end

--
-- The record for KUID and their Name, or nil for a KUID the mod does not know.
--
function KU:Record(kuid)
  local name = kuid and self.kuids and self.kuids[kuid]

  if (not name) then
    return nil
  end

  return self.users[name], name
end

--
-- KUID's Name in colour for their class, the realm left off for this realm, or the KUID itself for nobody the mod knows.
--
function KU:String(kuid)
  local rec, name = self:Record(kuid)

  return rec and aclass(name, rec[USER_CLASS]) or tostring(kuid)
end

--
-- KUID's main role and off role, K.ROLE_ numbers, K.ROLE_UNSET for one that is not set, and for a user the mod does not know.
--
function KU:Roles(kuid)
  local rec = self:Record(kuid)

  if (not rec) then
    return K.ROLE_UNSET, K.ROLE_UNSET
  end

  return rec[USER_MSROLE] or K.ROLE_UNSET, rec[USER_OSROLE] or K.ROLE_UNSET
end

--
-- Add NAME as a user of class CLASS, issuing them a KUID. Returns their KUID and record, and whether they are new: a user the
-- mod already knows is handed back as they are, their class included, so this is safe to call for somebody who may already be
-- here. Nil for a name that cannot be made canonical.
--
function KU:Add(name, class)
  local key = name and K.CanonicalName(name)

  if (not key or not self.users) then
    return nil
  end

  local rec = self.users[key]

  if (rec) then
    return rec[USER_KUID], rec, false
  end

  local kuid = new_kuid()

  rec = { kuid, class }
  self.users[key] = rec
  self.kuids[kuid] = key

  return kuid, rec, true
end

--
-- Whether ROLE, a K.ROLE_ number, is one a character of class CLASS can play. K.ROLE_UNSET is no role at all.
--
local function class_role(class, role)
  for _, r in ipairs((class and K.ClassRoles[class]) or {}) do
    if (r == role) then
      return true
    end
  end

  return false
end

--
-- A user's class as the Kore class number, or nil for one nobody has told us and for a user the mod does not know.
--
function KU:Class(kuid)
  local rec = self:Record(kuid)

  return rec and rec[USER_CLASS] or nil
end

--
-- A role is only what a class can play, so a user whose class changes loses any role the new class cannot.
--
function KU:SetClass(kuid, class)
  local rec = self:Record(kuid)

  if (not rec or not class) then
    return false
  end

  rec[USER_CLASS] = class

  if (not class_role(class, rec[USER_MSROLE])) then
    rec[USER_MSROLE] = nil
  end

  if (not class_role(class, rec[USER_OSROLE])) then
    rec[USER_OSROLE] = nil
  end

  return true
end

--
-- A user's race, as the game's own race id, or nil for a race nobody has told us. K.RaceName puts it into words.
--
function KU:Race(kuid)
  local rec = self:Record(kuid)

  return rec and rec[USER_RACE] or nil
end

--
-- Set it, taking only a race this client can name, so that a number out of somebody else's client is dropped rather than
-- stored and shown as itself. Returns whether anything changed.
--
function KU:SetRace(kuid, race)
  local rec = self:Record(kuid)
  local race = tonumber(race)
  local race = (race and K.RaceName(race)) and race or nil

  if (not rec or rec[USER_RACE] == race) then
    return false
  end

  rec[USER_RACE] = race

  return true
end

--
-- What level a user had reached when we last heard, or nil for one nobody has told us. A level is worth keeping because a
-- raid leader wants to know who is ready for a raid, and is the one fact here that moves on its own, so it is only ever as
-- recent as the last raid info check.
--
function KU:Level(kuid)
  local rec = self:Record(kuid)

  return rec and rec[USER_LEVEL] or nil
end

function KU:SetLevel(kuid, level)
  local rec = self:Record(kuid)
  local level = tonumber(level)
  local level = (level and level > 0 and level <= MAX_LEVEL) and level or nil

  if (not rec or rec[USER_LEVEL] == level) then
    return false
  end

  rec[USER_LEVEL] = level

  return true
end

--
-- A user's two professions, K.PROF_UNSET for a slot they have not filled or for a user the mod does not know.
--
function KU:Professions(kuid)
  local rec = self:Record(kuid)

  if (not rec) then
    return K.PROF_UNSET, K.PROF_UNSET
  end

  return rec[USER_PPROF] or K.PROF_UNSET, rec[USER_SPROF] or K.PROF_UNSET
end

--
-- Set both professions at once, since one is only ever edited alongside the other. Returns whether anything changed.
--
function KU:SetProfessions(kuid, pprof, sprof)
  local rec = self:Record(kuid)

  if (not rec) then
    return false
  end

  local pprof = tonumber(pprof) or K.PROF_UNSET
  local sprof = tonumber(sprof) or K.PROF_UNSET

  if ((rec[USER_PPROF] or K.PROF_UNSET) == pprof and (rec[USER_SPROF] or K.PROF_UNSET) == sprof) then
    return false
  end

  rec[USER_PPROF] = (pprof ~= K.PROF_UNSET) and pprof or nil
  rec[USER_SPROF] = (sprof ~= K.PROF_UNSET) and sprof or nil

  return true
end

--
-- Set both roles at once, since one is only ever edited alongside the other. A role the user's class cannot play is no
-- role at all. Returns whether anything changed.
--
function KU:SetRoles(kuid, msrole, osrole)
  local rec = self:Record(kuid)

  if (not rec) then
    return false
  end

  local class = rec[USER_CLASS]
  local msrole = class_role(class, tonumber(msrole)) and tonumber(msrole) or nil
  local osrole = class_role(class, tonumber(osrole)) and tonumber(osrole) or nil

  if (rec[USER_MSROLE] == msrole and rec[USER_OSROLE] == osrole) then
    return false
  end

  rec[USER_MSROLE] = msrole
  rec[USER_OSROLE] = osrole

  return true
end

--
-- Whether the user KUID is a tank, and the same for every other role: two answers, the first whether it is their main role
-- and the second whether it is their off role, false for a role they have not set. Nil and nil for a user the mod does not
-- know, which is a different answer from a user who is known not to be one.
--
local function user_is(role)
  return function(self, kuid)
    if (not self:Record(kuid)) then
      return nil, nil
    end

    local msrole, osrole = self:Roles(kuid)

    return msrole == role, osrole == role
  end
end

KU.IsTank   = user_is(K.ROLE_TANK)
KU.IsHealer = user_is(K.ROLE_HEALER)
KU.IsMelee  = user_is(K.ROLE_MELEE)
KU.IsRanged = user_is(K.ROLE_RANGED)
KU.IsCaster = user_is(K.ROLE_CASTER)

--
-- How this player rates the user KUID at WHICH, one of the RATE_ constants, as a RATING_ constant, or nil when they have not
-- rated it or the mod does not know the user.
--
function KU:Rating(kuid, which)
  local rec = self:Record(kuid)
  local ratings = rec and rec[USER_NOTES] and rec[USER_NOTES][NOTES_RATINGS]

  return ratings and ratings[which] or nil
end

--
-- Rate the user KUID at WHICH as RATING, or take the rating away with nil. A ratings table left empty goes, and so does a
-- notes table, so a user nobody has an opinion of carries no notes at all. Returns whether the user is known.
--
function KU:SetRating(kuid, which, rating)
  local rec = self:Record(kuid)

  if (not rec) then
    return false
  end

  local notes = rec[USER_NOTES] or {}
  local ratings = notes[NOTES_RATINGS] or {}

  ratings[which] = rating
  notes[NOTES_RATINGS] = next(ratings) and ratings or nil
  rec[USER_NOTES] = next(notes) and notes or nil

  return true
end

--
-- What this player has written about the user KUID, or nil for nothing and for a user the mod does not know.
--
function KU:Note(kuid)
  local rec = self:Record(kuid)
  local notes = rec and rec[USER_NOTES]

  return notes and notes[NOTES_TEXT] or nil
end

--
-- Write TEXT about the user KUID, or take what was written away with nil or an empty string. An empty notes table goes, so a
-- user nobody has an opinion of carries no notes at all. Returns whether the user is known.
--
function KU:SetNote(kuid, text)
  local rec = self:Record(kuid)

  if (not rec) then
    return false
  end

  local notes = rec[USER_NOTES] or {}

  notes[NOTES_TEXT] = (text and text ~= "") and text or nil
  rec[USER_NOTES] = next(notes) and notes or nil

  return true
end

--
-- The KUID of the user KUID is an alt of, or nil for a main or a user the mod does not know.
--
function KU:Main(kuid)
  local rec = self:Record(kuid)

  return rec and rec[USER_ALTOF] or nil
end

--
-- The KUIDs of KUID's alts, in no particular order, or nil when they have none. The stored array itself, which a caller reads
-- and does not keep, KU:SetMain being the only thing that writes either direction of a link. Whoever shows them sorts them,
-- by name or however suits.
--
function KU:Alts(kuid)
  local rec = self:Record(kuid)

  return (rec and rec[USER_ALTS]) or nil
end

--
-- Take KUID out of their main's list of alts, dropping the list when it empties, and forget whose alt they were.
--
local function unlink_alt(this, kuid)
  local rec = this:Record(kuid)
  local mrec = this:Record(rec[USER_ALTOF])

  if (mrec and mrec[USER_ALTS]) then
    for k, v in ipairs(mrec[USER_ALTS]) do
      if (v == kuid) then
        tremove(mrec[USER_ALTS], k)
        break
      end
    end

    if (not next(mrec[USER_ALTS])) then
      mrec[USER_ALTS] = nil
    end
  end

  rec[USER_ALTOF] = nil
end

--
-- Make KUID an alt of MAINKUID, or a main of their own when MAINKUID is nil or empty. Both directions of the link are
-- written here, which is what keeps them in step.
--
-- This is the one alt link there is. Every mod's every configuration reads it, so a link set here is set everywhere that
-- person is, and a mod that carries links between clients writes what arrives through here as well.
--
-- A main cannot itself be an alt, and a user who has alts cannot become one, so a link is only ever one level deep. A human
-- has one main and every other character of theirs hangs off it, and anybody wanting two mains simply does not link them.
-- Returns true when the link is as asked, whether or not it had to change, or false and a message saying why it cannot be.
--
-- QUIET leaves the redraw to the caller, for one making a batch of these who calls UserLinksChanged once at the end.
--
function KU:SetMain(kuid, mainkuid, quiet)
  local rec = self:Record(kuid)

  if (not rec) then
    return false, strfmt(L["user %q does not exist. Try again."], tostring(kuid))
  end

  local mrec = nil

  if (mainkuid and mainkuid ~= "") then
    mrec = self:Record(mainkuid)

    if (not mrec) then
      return false, strfmt(L["user %q does not exist. Try again."], tostring(mainkuid))
    end

    if (mainkuid == kuid) then
      return false, strfmt(L["USER_ALT_SELF"], self:String(kuid))
    end

    if (mrec[USER_ALTOF]) then
      return false, strfmt(L["USER_ALT_OF_ALT"], self:String(mainkuid), self:String(mrec[USER_ALTOF]))
    end

    if (rec[USER_ALTS]) then
      return false, strfmt(L["USER_ALT_HAS_ALTS"], self:String(kuid))
    end
  else
    mainkuid = nil
  end

  if (rec[USER_ALTOF] == mainkuid) then
    return true
  end

  unlink_alt(self, kuid)

  if (mainkuid) then
    rec[USER_ALTOF] = mainkuid
    mrec[USER_ALTS] = mrec[USER_ALTS] or {}
    tinsert(mrec[USER_ALTS], kuid)
  end

  if (not quiet) then
    self:UserLinksChanged()
  end

  return true
end

--
-- Where KUID is a user, as an array of { policy, config } with one entry per config that has an entry for them, CONFIG being
-- that config's name. Each policy is asked for its own, being the only thing that looks inside its configs.
--
function KU:Usage(kuid)
  local used = {}

  if (not kuid) then
    return used
  end

  for _, tbl in pairs(KU.consumers) do
    if (tbl.UserConfigs) then
      for _, where in ipairs(tbl:UserConfigs(kuid) or {}) do
        tinsert(used, where)
      end
    end
  end

  return used
end

--
-- The configs in USED, from Usage, as one line of text for a message: each config's name and the policy it belongs to.
--
function KU:UsageText(used)
  local names = {}

  for k, v in ipairs(used) do
    tinsert(names, strfmt("%s (%s)", v.name, v.owner))
  end

  return tconcat(names, ", ")
end

--
-- Forget KUID entirely. Refused while any config still has an entry for them, since that entry would be left pointing at
-- nobody, and the message says which configs they are in. Their alts become mains, and if they were an alt they leave their
-- main's list. Their KUID goes with them and is never issued again. Returns true, or false and a message saying why not.
--
function KU:Remove(kuid)
  local rec, key = self:Record(kuid)

  if (not rec) then
    return false, strfmt(L["user %q does not exist. Try again."], tostring(kuid))
  end

  local used = self:Usage(kuid)

  if (next(used)) then
    return false, strfmt(L["USER_DELETE_IN_USE"], self:String(kuid), self:UsageText(used))
  end

  unlink_alt(self, kuid)

  for k, v in ipairs(rec[USER_ALTS] or {}) do
    local arec = self:Record(v)

    if (arec) then
      arec[USER_ALTOF] = nil
    end
  end

  self.users[key] = nil
  self.kuids[kuid] = nil

  self:UserLinksChanged()

  return true
end

--
-- Give the user KUID the name NEWNAME, which is what a paid name change is. The record moves to its new key and KU.kuids
-- follows it. Everything that points at the person does so by KUID, alt links and every config's entries alike, so nothing
-- else changes. Refused when NEWNAME is already somebody. Returns true, or false and a message saying why not.
--
function KU:Rename(kuid, newname)
  local rec, okey = self:Record(kuid)
  local nkey = newname and K.CanonicalName(newname)

  if (not rec) then
    return false, strfmt(L["user %q does not exist. Try again."], tostring(kuid))
  end

  if (not newname or newname == "") then
    return false, L["you must specify a character name."]
  end

  if (not nkey) then
    return false, strfmt(L["%q is not a valid character name."], newname)
  end

  if (nkey == okey) then
    return true
  end

  if (self.users[nkey]) then
    return false, strfmt(L["user %q already exists. Try again."], self:String(self:Find(nkey)))
  end

  self.users[nkey] = rec
  self.users[okey] = nil
  self.kuids[kuid] = nkey

  self:UserLinksChanged()

  return true
end

--
-- The wire row for KUID as we would send it, naming them by Name, or nil for a user we do not know. See the WUSER_ constants.
--
function KU:WireRow(kuid)
  local rec, key = self:Record(kuid)

  if (not rec) then
    return nil
  end

  return { key, rec[USER_CLASS], rec[USER_PPROF], rec[USER_SPROF], rec[USER_MSROLE], rec[USER_OSROLE], rec[USER_RACE],
    rec[USER_LEVEL] }
end

--
-- The facts a player is asked about before one of theirs is changed, in the order they are shown them, and what each is
-- called. Notes, whose alt the player holds somebody to be and everything a config keeps are all deliberately absent: none of
-- them is a fact and none of them travels. A level is a fact and travels, but is never asked about (see UserFactChanges).
--
local FACT_SLOTS = { USER_CLASS, USER_RACE, USER_PPROF, USER_SPROF, USER_MSROLE, USER_OSROLE }

--
-- These are locale keys rather than words. Five of them are the labels the shared facts block already puts on its own
-- controls, so a fact is called the same thing whether it is being edited or being asked about. The facts block offers no
-- control for a race or a level, so those two have words of their own.
--
local FACT_LABELS = {
  [USER_CLASS] = "User class", [USER_RACE] = "Race", [USER_LEVEL] = "Level",
  [USER_PPROF] = "First profession", [USER_SPROF] = "Second profession", [USER_MSROLE] = "Main spec",
  [USER_OSROLE] = "Off spec",
}

--
-- One of those facts in words, for a player being asked about it.
--
local function fact_string(slot, val, class)
  if (not val) then
    return K.NOTSET_STR
  end

  if (slot == USER_CLASS) then
    return K.IndexClass[val] and K.IndexClass[val].c or tostring(val)
  elseif (slot == USER_PPROF or slot == USER_SPROF) then
    return K.IndexProf[val] and K.IndexProf[val].c or tostring(val)
  elseif (slot == USER_MSROLE or slot == USER_OSROLE) then
    return K.RoleName(val) or tostring(val)
  elseif (slot == USER_RACE) then
    return K.RaceName(val) or tostring(val)
  end

  return tostring(val)
end

--
-- Write ROW's facts onto REC, as far as each is one this client can make sense of. ONLYBLANK fills in what we have no value
-- for at all and leaves everything else alone. Returns whether anything changed.
--
local function take_facts(this, rec, row, onlyblank)
  local changed = false

  local function take(slot, val)
    if (rec[slot] == val or (onlyblank and rec[slot])) then
      return
    end

    rec[slot] = val
    changed = true
  end

  if (K.IndexClass[tonumber(row[WUSER_CLASS]) or 0]) then
    take(USER_CLASS, tonumber(row[WUSER_CLASS]))
  end

  -- A role is only what a class can play, so one we hold that this class cannot is gone whatever the row says next.
  if (not class_role(rec[USER_CLASS], rec[USER_MSROLE])) then
    take(USER_MSROLE, nil)
  end

  if (not class_role(rec[USER_CLASS], rec[USER_OSROLE])) then
    take(USER_OSROLE, nil)
  end

  --
  -- A character's professions are a set of two, not an ordered pair. Which slot one sits in is the order they happened to
  -- learn them and means nothing to anybody: no caller treats the first as the important one, and the two are labelled first
  -- and second precisely because that is all they are.
  --
  -- So they are matched by value before anything is written. A sender naming the same two the other way round is saying what
  -- we already hold and changes nothing. Taken slot by slot it would read as two changes instead, the player would be asked
  -- to approve a swap that means nothing, and the next admin holding the original order would ask them to swap it back, for
  -- as long as both kept talking, a refusal not being remembered.
  --
  local p1, p2 = tonumber(row[WUSER_PPROF]), tonumber(row[WUSER_SPROF])
  local sent = {}

  if (K.IndexProf[p1 or 0]) then
    sent[#sent + 1] = p1
  end

  if (K.IndexProf[p2 or 0] and p2 ~= p1) then
    sent[#sent + 1] = p2
  end

  if (#sent > 0) then
    local spare = {}
    local fill = {}

    --
    -- A profession we hold that the sender also names stays exactly where it is. Every other slot of ours is free for
    -- whatever they name that we do not have.
    --
    for _, slot in ipairs({ USER_PPROF, USER_SPROF }) do
      local held = rec[slot]
      local matched = false

      for _, p in ipairs(sent) do
        if (held and held == p) then
          matched = true
          break
        end
      end

      if (not matched) then
        spare[#spare + 1] = slot
      end
    end

    for _, p in ipairs(sent) do
      if (p ~= rec[USER_PPROF] and p ~= rec[USER_SPROF]) then
        fill[#fill + 1] = p
      end
    end

    --
    -- Only as far as they have something to say. A sender who names one profession where we hold two knows less than we do
    -- rather than disagreeing with us, and nothing they leave out is a reason to forget what we have.
    --
    for i, slot in ipairs(spare) do
      if (fill[i]) then
        take(slot, fill[i])
      end
    end
  end

  local r1, r2 = tonumber(row[WUSER_MSROLE]), tonumber(row[WUSER_OSROLE])

  if (class_role(rec[USER_CLASS], r1)) then
    take(USER_MSROLE, r1)
  end

  if (class_role(rec[USER_CLASS], r2)) then
    take(USER_OSROLE, r2)
  end

  local race = tonumber(row[WUSER_RACE])

  if (race and K.RaceName(race)) then
    take(USER_RACE, race)
  end

  local level = tonumber(row[WUSER_LEVEL])

  if (level and level > 0 and level <= MAX_LEVEL) then
    take(USER_LEVEL, level)
  end

  return changed
end

--
-- What another admin says about a user, arriving with an event or a sync that has just given one of our configs an entry for
-- them. A user we do not know is added with everything said about them, since adding somebody is exactly what the config we
-- accepted asked for. A user we do know keeps every value we already have: what is true of a character is the player's own,
-- and only what we have nothing at all for is filled in.
--
-- Where a change to somebody we know is offered to the player rather than dropped is a broadcast, which is the whole picture
-- rather than one admin's remark in passing. See KU:UserFactChanges.
--
-- NAME is how the sender named them, the Name being all two clients share. Returns their KUID here.
--
function KU:OfferUserFacts(name, class, pprof, sprof, msrole, osrole, race, level)
  local kuid, rec = self:Add(name, class)

  if (not kuid) then
    return nil
  end

  take_facts(self, rec, { name, class, pprof, sprof, msrole, osrole, race, level }, true)

  return kuid
end

--
-- What another client has just told us about a number of people, put to the player as one question. SENDER is whoever said
-- it and USERS an array of wire rows, a whole config's worth from a broadcast or a sync, or the one person an event was
-- about. Anybody in it we have never heard of is simply added.
--
-- One question, however many messages it took to arrive: everything from one sender gathers into a single batch, so the
-- forty events a raid info check sets off are answered once (see KU:OfferUserChanges).
--
function KU:OfferPeople(sender, users)
  local changes = {}

  self:UserFactChanges(users, changes)
  self:OfferUserChanges(sender, changes)
end

--
-- What a broadcast says about its users, against what we hold, as the changes to put to the player. USERS is an array of wire
-- rows and INTO is the change list they are added to, as KU:OfferUserChanges takes it.
--
-- Somebody we have never heard of is added here and then, with everything the broadcast says about them, because accepting a
-- config is accepting the people in it and there is nothing yet to disagree with. For everybody else each fact the broadcast
-- has a value for is compared with ours, and every one that differs is a line the player will see, with what we hold now
-- beside what is being offered. Nothing is written until they accept it.
--
function KU:UserFactChanges(users, into)
  local added = false

  for k, row in ipairs(users) do
    local key = row[WUSER_NAME] and K.CanonicalName(row[WUSER_NAME])
    local rec = key and self.users[key]

    if (key and not rec) then
      self:OfferUserFacts(row[WUSER_NAME], row[WUSER_CLASS], row[WUSER_PPROF], row[WUSER_SPROF], row[WUSER_MSROLE],
        row[WUSER_OSROLE], row[WUSER_RACE], row[WUSER_LEVEL])
      added = true
    elseif (rec) then
      local was = {}

      for _, slot in ipairs(FACT_SLOTS) do
        was[slot] = rec[slot]
      end

      --
      -- Worked out by making the change and putting it straight back, so that what a player is offered is exactly what they
      -- would get, every rule about what this client will take included, and there is no second copy of those rules here.
      --
      -- What is put back is the facts a player could have an opinion about. A level is not one of them: nobody disagrees
      -- about what level somebody is, it moves on its own between one raid and the next, and being asked to confirm that
      -- another player dinged is not a question. It stays as taken.
      --
      if (take_facts(self, rec, row)) then
        for _, slot in ipairs(FACT_SLOTS) do
          if (rec[slot] ~= was[slot]) then
            tinsert(into, { kuid = rec[USER_KUID], slot = slot, what = L[FACT_LABELS[slot]], value = rec[slot],
              now = fact_string(slot, was[slot], was[USER_CLASS]), offered = fact_string(slot, rec[slot], rec[USER_CLASS]) })
          end

          rec[slot] = was[slot]
        end
      end
    end
  end

  if (added) then
    self:UserLinksChanged()
  end
end

--
-- Who the mod knows, or what is true of them, has changed, so every window that shows a user is redrawn and every mod is
-- told to redraw its own. Nothing is sent anywhere. What arrives from another client comes in through here as well.
--
function KU:UserLinksChanged()
  if (not KU.users) then
    return
  end

  self:RefreshUserEditor()

  consumers("UsersChanged")
end

--
-- This player has just set whose alt KUID is, here in the editor, where there is no config in hand. Everything is redrawn as
-- for any other change, and then the mods are told which character it was, so that the configurations they administer carry
-- it to the rest of the raid. See UserMainChanged in the consumer seam above for why only this one is announced.
--
function KU:UserMainSet(kuid)
  self:UserLinksChanged()

  consumers("UserMainChanged", kuid)
end

--
-- BLOCKED SENDERS
--
-- Everything another client says about a third party is an offer, and a refusal is never remembered, because the comparison
-- is always against what is stored and so the next message asks again. The answer to somebody who will not stop asking is to
-- stop reading them at all. Their messages are thrown away unread rather than answered, which is the only thing that actually ends it.
--

--
-- Block NAME, or unblock them for ONOFF false. Answers their canonical name, or nil for a name that is not one.
--
function KU:SetSenderBlocked(name, onoff)
  local key = name and K.CanonicalName(name)

  if (not key or not K.frdb) then
    return nil
  end

  K.frdb.blockedsenders[key] = onoff and true or nil

  return key
end

--
-- Whether NAME is somebody we have stopped reading.
--
function KU:SenderBlocked(name)
  local key = name and K.CanonicalName(name)

  return (key and K.frdb and K.frdb.blockedsenders[key]) and true or false
end

--
-- Everybody blocked, in name order.
--
function KU:BlockedSenders()
  local names = {}

  for k, v in pairs((K.frdb and K.frdb.blockedsenders) or {}) do
    tinsert(names, k)
  end

  tsort(names)

  return names
end
