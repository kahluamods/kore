--[[
   KahLua Kore - Konfer module registration and inter-mod communication.
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

local KORECOMMS_MAJOR = "KoreComms"
local KORECOMMS_MINOR = 1
local KC, oldminor = LibStub:NewLibrary(KORECOMMS_MAJOR, KORECOMMS_MINOR)

if (not KC) then
  return
end

KC.debug_id = KORECOMMS_MAJOR

--
-- The Kore wire protocol version. This versions the message envelope only: the framing, the checksum, the serialisation and
-- the compression. It is shared by every Kore-based addon and has nothing to do with any addon's own protocol number, which
-- versions that addon's events and their arguments and travels inside the payload where this library cannot see it.
--
--   1 - version letter and compression flag, checksum, payload.
--
-- The version is the first character of every message and always will be, because nothing else can be read until it has
-- been. Everything after it is version dependent.
--
-- It is written as a letter, "a" for version 1, so that its case can carry the one other thing the receiver must know
-- before it can do anything: lower case for a payload as it was serialised, upper case for one that was compressed as
-- well. That is a bit that would otherwise cost a whole character, and there is nowhere cheaper to put it.
--
-- Twenty six versions is a great many for something whose first version stood for twenty years, and the alphabet running
-- out is not a trap: a later version may declare "z" to mean the real version follows in a wider field, and every client
-- written before that refuses it unread, because a version it does not implement is a version it does not implement. That
-- is the invariant everything here rests on and it must never be weakened. Nothing ever parses past a version letter it
-- does not know, however tempting the rest of the message looks.
--
KC.WIRE_VERSION = 1

local K, KM = LibStub:GetLibrary("Kore")
assert(K, "KoreComms requires Kore")
assert(tonumber(KM) >= 1, "KoreComms requires Kore r1 or later")
K:RegisterExtension(KC, KORECOMMS_MAJOR, KORECOMMS_MINOR)

local KUI, KM = LibStub:GetLibrary("KoreUI")
assert(KUI, "KoreComms requires KoreUI")
assert(tonumber(KM) >= 1, "KoreComms requires KoreUI r1 or later")

local H, KM = LibStub:GetLibrary("KoreHash")
assert(H, "KoreComms requires KoreHash")
assert(tonumber(KM) >= 1, "KoreComms requires KoreHash r1 or later")

local KRP, KM = LibStub:GetLibrary("KoreParty")
assert(KRP, "KoreComms requires KoreParty")
assert(tonumber(KM) >= 1, "KoreComms requires KoreParty r1 or later")

local ZL = LibStub:GetLibrary("LibDeflate")
assert(ZL, "KoreComms requires LibDeflate")

local LS = LibStub:GetLibrary("LibSerialize")
assert(LS, "KoreComms requires LibSerialize")

local L = LibStub("AceLocale-3.0"):GetLocale("Kore")

KC.addons = {}
KC.valid_callbacks = {
}

local printf = K.printf
local tsort = table.sort
local tinsert = table.insert
local strfmt = string.format
local strlen = string.len
local strsub = string.sub
local strlower = string.lower
local strbyte = string.byte
local strchar = string.char
local gmatch = string.gmatch
local bor = bit.bor
local band = bit.band
local bxor = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift
local MakeFrame= KUI.MakeFrame

-- C_ChatInfo's on every client. The global of the same name is a deprecated shim that goes when fallbacks are switched off.
local SendChatMessage = C_ChatInfo.SendChatMessage

--
-- Every table that has registered to talk on the wire, keyed by the handle in its comms descriptor. RegisterComms() records
-- it here, and uses it to recognise a repeat registration.
--
-- What a registered table is, this library neither knows nor cares. An addon registers itself; an addon that is several
-- things at once may register each of them, and each is then a separate endpoint. Endpoints may take a prefix each, or share
-- one and say which of them a message came from in the command, which is theirs to fill. Either way a message reaches the
-- endpoint it was sent from on the other clients, and how is no business of this library's.
--
-- Kept on KC rather than in _G so that the name "Konfer" in the global namespace belongs to the Konfer addon alone. LibStub
-- hands back the same KC table across a library upgrade, so this survives one just as a global would.
--
KC.registry = KC.registry or {}

local registry = KC.registry

function KC:OnLateInit()
  if (self.initialised) then
    return
  end

  self.initialised = true
end

function KC.TimeStamp()
  local tDate = date("*t")
  local mo = tDate["month"]
  local dy = tDate["day"]
  local yr = tDate["year"]
  local hh, mm = GetGameTime()
  return strfmt("%04d%02d%02d%02d%02d", yr, mo, dy, hh, mm), yr, mo, dy, hh, mm
end

--
-- A fresh identifier, eight hexadecimal characters, for anything that has to be named on the wire: a config space, a roll list.
--
-- What a thing is *called* never goes into it, and that is the point. An id derived from a name collides whenever two people
-- name two different things the same way at about the same time, which on a raid night is an ordinary Tuesday rather than a
-- freak event. Two admins who both create "Main Raid" are creating two separate things and must get two ids.
--
-- Uniqueness rests on legs enough that none of them has to carry it alone: the clock to the second, a counter that separates
-- ids issued within the same second, and the player's own name, which is what keeps two people apart when their clocks
-- agree. None of it needs the random number generator to have been seeded, which is not something an addon can assume.
--
-- EXTRA is a fourth leg the caller may add: anything that classifies the thing being named and cannot change afterwards.
-- Kore does not care what it means, only that ids of two different kinds are then drawn from separate spaces even when the
-- clock, the counter and the player all agree.
--
local newid_seq = 0

function KC.CreateNewID(extra)
  local t = date("*t")

  newid_seq = newid_seq + 1

  local crc = H:CRC32(strfmt("%04d%02d%02d%02d%02d%02d", t.year, t.month,
    t.day, t.hour, t.min, t.sec), nil, false)
  crc = H:CRC32(tostring(newid_seq), crc, false)
  crc = H:CRC32((K.player and K.player.name) or "", crc, false)
  crc = H:CRC32(tostring(extra or ""), crc, true)

  return K.hexstr(crc)
end

--
-- Titles already told they are out of date. The dialog names the thing to update by its title, and an addon that is several
-- endpoints under one title is one thing to update, so it is told once however many of its endpoints hear from a newer peer.
--
local old_proto_shown = {}

function KC:OldProtoDialog()
  local title = self.comms.title

  if (old_proto_shown[title]) then
    return
  end

  old_proto_shown[title] = true

  local arg = {
    name = self.comms.handle .. "OldProtoDialog",
    x = "CENTER", y = "MIDDLE", border = true, blackbg = true,
    okbutton = true, canmove = true, canresize = false,
    escclose = false, width = 450, height = 100, title = self:WindowTitle(),
  }
  local dlg = KUI:CreateDialogFrame(arg)

  arg = {
    x = "CENTER", y = "MIDDLE", width = 410, height = 64, autosize = false,
    color = { r = 1, g = 0, b = 0, a = 1},
    text = strfmt(L["Your version of %s is out of date. Please update it."], self.comms.title),
    font = "GameFontNormal", justifyh = "CENTER", justifyv = "MIDDLE",
  }
  dlg.str1 = KUI:CreateStringLabel(arg, dlg)

  if (self.mainwin and self.mainwin:IsShown()) then
    self.mainwin:Hide()
  end
  dlg:Show()
end


--
-- Retail refuses addon messages, and chat, while certain restrictions are in force: during an encounter, a challenge mode
-- run or a PvP match, or whenever it restricts addon chat. A refused message is not an error anybody sees. ChatThrottleLib
-- quietly drops it, and a dropped chunk of a message sent in parts spoils the rest. So nothing is handed to the game while
-- one of those restrictions is in force.
--
-- What is sent then is either held or dropped, as the sender said when it sent it. A message that still means something
-- later, a config event, sync or a broadcast, is held and sent in order once the restriction lifts. One that means nothing
-- later, a bid or a roll's countdown, is dropped, and so is chat, the player being told once for each restriction that
-- something went unsent. Nothing here can tell which is which, the payload being the sender's, so the sender says. The game
-- says a restriction is coming before it is enforced, and gone after it has lifted. The other clients never see the event,
-- as they have no restriction to be in.
--
local LOCKED_TYPES = { [1] = true, [2] = true, [3] = true, [5] = true }  -- Encounter, ChallengeMode, PvPMatch, Chat

local locked = {}
local held = {}
local told_unsent = false

local function messages_locked()
  return next(locked) ~= nil
end

local function tell_unsent(title)
  if (not told_unsent) then
    told_unsent = true
    printf(K.ecolor, L["%s: the game is refusing addon messages for now, so some were not sent."],
      title and (K.KAHLUA .. " " .. title) or K.KAHLUA)
  end
end

local function restriction_changed(evt, rtype, state)
  if (not LOCKED_TYPES[rtype]) then
    return
  end

  -- Activating (1) is the moment before it is enforced, and Active (2) while it is.
  locked[rtype] = (state == 1 or state == 2) or nil

  if (messages_locked()) then
    return
  end

  told_unsent = false

  local q = held

  held = {}
  for _, m in ipairs(q) do
    K:SendCommMessage(m.prefix, m.text, m.dist, m.target, m.prio)
  end
end

K:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", restriction_changed)

--
-- Every message this library sends is built here and taken apart again by comm_received below, and those two functions are
-- the whole of the wire format. Nothing else on either side of it knows the shape of a message.
--
-- At wire version 1 a message is nine characters of header and then the payload, with no separators anywhere, every field
-- being of a width the version fixes:
--
--   VCCCCCCCCpayload...
--
--   V          The version letter, "a" for version 1, upper case if the payload was compressed. See KC.WIRE_VERSION.
--   CCCCCCCC   The CRC32 of everything else, as eight lower case hex digits.
--   payload    Whatever the caller passed, serialised, compressed if that made it smaller, and encoded for the channel.
--
-- The CRC covers the whole message with those eight characters taken out of it, which is the version letter followed by the
-- payload. So the version and the compression flag are checked along with the data, and a corrupted flag cannot turn a plain
-- message into a decompression failure that checksums perfectly well.
--
-- What is in the payload is the caller's business entirely and none of this library's. An addon's own protocol version, what
-- kind of message it is, which of its endpoints sent it and what it is about are all values it passes and gets back, and
-- this file neither knows nor cares that any of them exist.
--
-- Compression is decided by measuring rather than guessing. A small message deflates to something longer than it started,
-- and most raid traffic is small, so the compressed form is used only when it is actually shorter and the flag says which
-- was sent. The receiver does not have to care either way.
--
local function send_addon_msg(self, prio, hold, dist, target, ...)
  local serialised = LS:Serialize(...)

  if (not serialised) then
    self.debug(4, "failed to serialise data")
    return
  end

  local body = serialised
  local squished = false
  local compressed = ZL:CompressDeflate(serialised, { level = 5 })

  if (compressed and strlen(compressed) < strlen(serialised)) then
    body = compressed
    squished = true
  end

  local encoded = ZL:EncodeForWoWAddonChannel(body)

  if (not encoded) then
    self.debug(4, "encode failed")
    return nil
  end

  local sc

  if (squished) then
    sc = "A"
  else
    sc = "a"
  end

  local vc = strchar(strbyte(sc) + KC.WIRE_VERSION - 1)
  local prio = prio or "ALERT"
  local crc = H:CRC32(vc, nil, false)
  crc = H:CRC32(encoded, crc, true)
  local fs = vc .. K.hexstr(crc) .. encoded

  --
  -- What went out, as the caller handed it over: the wire form is a checksum and compressed bytes, which say nothing. Only
  -- built when somebody is debugging at the level that shows it.
  --
  if (K.DebugWanted(9)) then
    self.debug(9, "send: %s%s, %d bytes%s: %s", dist, target and (" to " .. target) or "", strlen(fs),
      squished and " compressed" or "", K.Describe(...))
  end

  --
  -- Held or dropped while the game is refusing addon messages. Whether a message still means anything once the restriction
  -- lifts is the sender's to say, in HOLD, because nothing in it is legible from here. See restriction_changed.
  --
  if (messages_locked()) then
    if (hold) then
      tinsert(held, { prefix = self.CHAT_MSG_PREFIX, text = fs, dist = dist, target = target, prio = prio })
    else
      tell_unsent(self.comms and self.comms.title)
    end
    return
  end

  K:SendCommMessage(self.CHAT_MSG_PREFIX, fs, dist, target, prio)
end

-- Complain about a given sender at most once every ten minutes.
local userwarn = {}

local function warn_once(sender, fmt, ...)
  local t = K.time()
  local n = userwarn[sender]

  if (n and (t - n) < 600) then
    return
  end

  userwarn[sender] = t
  printf(K.ecolor, fmt, ...)
end

-- Designed to process host addon's OnCommReceived with a dispatcher.
local function comm_received(self, prefix, msg, dist, snd, dispatcher)
  local sender = K.CanonicalName(snd)
  if (sender == K.player.name) then
    return -- Ignore our own messages
  end

  --
  -- Every message this library sends goes to the guild, to the group or to one player, and each of those arrives with the
  -- channel it came on and the name of whoever sent it. A message with either missing is not one of ours whatever prefix it
  -- turned up under, and there would be nobody to answer or to hold to an admin's rights even if it were.
  --
  if (dist == "UNKNOWN" or not sender or sender == "") then
    return
  end

  --
  -- Nine characters of header and at least one of payload. Nothing is separated, so a message shorter than that would be
  -- sliced into empty strings rather than failing of its own accord, and every field after the version is only where it is
  -- because the version says so.
  --
  if (strlen(msg) < 10) then
    self.debug(4, "runt message from %q", sender)
    return
  end

  --
  -- The version letter, and with it the only other thing that has to be known before anything can be done: whether the
  -- payload was compressed, which is the letter's case. The version compare is case insensitive and the compression read is
  -- case sensitive, on the one character, so neither may be done by comparing the raw byte.
  --
  local vc = strsub(msg, 1, 1)
  local squished = (vc ~= strlower(vc))
  local version = strbyte(strlower(vc)) - strbyte("a") + 1

  --
  -- A version this client does not implement is refused here, unread, and that is the hinge the whole format turns on. It is
  -- what lets a later version widen any field it likes, or redefine the last letter of the alphabet to mean the real version
  -- follows in a wider one, without a thought for anybody written before it. Never parse past this.
  --
  if (version ~= KC.WIRE_VERSION) then
    self.debug(4, "wire version %s from %q, we speak %d", tostring(vc), sender, KC.WIRE_VERSION)
    KC.OldProtoDialog(self)
    return
  end

  local msum = strsub(msg, 2, 9)
  local data = strsub(msg, 10)

  -- The whole message but for the eight characters of checksum, so the version and the compression flag are covered too.
  local crc = H:CRC32(vc, nil, false)
  crc = H:CRC32(data, crc, true)
  local mf = K.hexstr(crc)

  if (mf ~= msum) then
    self.debug(1, "mismatch: mysum=%q theirsum=%q", tostring(mf), tostring(msum))
    warn_once(sender, L["%s: an addon message from %q was corrupt."], K.KAHLUA, tostring(sender))
    return
  end

  local decoded = ZL:DecodeForWoWAddonChannel(data)
  if (not decoded) then
    self.debug(4, "recv: decode failed from %q", sender)
    return
  end

  local inflated = decoded

  if (squished) then
    inflated = ZL:DecompressDeflate(decoded)

    if (not inflated) then
      self.debug(4, "recv: deflate failed from %q", sender)
      return
    end
  end

  --
  -- The caller gets back exactly what the caller passed, with the first value saying whether it deserialised at all. What
  -- any of it means is theirs, and whether it travelled compressed is nobody's.
  --
  -- What arrived is said the way a send is, as the values the sender handed over, and only when somebody is debugging.
  --
  if (K.DebugWanted(9)) then
    local got = { n = 0 }

    local function keep(...)
      got.n = select("#", ...)

      for i = 1, got.n do
        got[i] = (select(i, ...))
      end
    end

    keep(LS:Deserialize(inflated))
    self.debug(9, "recv: %s from %s, %d bytes%s: %s", tostring(dist), sender, strlen(msg),
      squished and " compressed" or "", K.Describe(unpack(got, 2, got.n)))
    dispatcher(self, sender, dist, unpack(got, 1, got.n))
    return
  end

  dispatcher(self, sender, dist, LS:Deserialize(inflated))
end

--
-- The chat channel of the group the player is in, as KoreParty sees it: INSTANCE_CHAT in a battleground, whose group is the
-- instance's and refuses RAID, else RAID or PARTY. Nil with no group.
--
local function group_channel()
  if (KRP.in_bg) then
    return "INSTANCE_CHAT"
  end

  if (KRP.in_raid) then
    return "RAID"
  end

  if (KRP.in_party) then
    return "PARTY"
  end

  return nil
end

--
-- The three sends. Each takes the priority, then HOLD, saying whether this message is still worth sending once the game
-- stops refusing addon messages, and then whatever the caller wants carried.
--
-- Send to whatever group the player is in, which is the one thing about a destination this library is better placed to know
-- than its caller: a battleground's group refuses RAID and wants INSTANCE_CHAT, and KoreParty is where that is settled.
-- Whether a caller ought to be talking in the group it finds itself in is the caller's own business and is not asked here.
--
--
-- A message with nowhere to go is dropped, and for somebody debugging that is said, with what it would have carried, rather
-- than leaving them wondering why a change went by without a word.
--
local function said_nowhere(self, why, ...)
  if (K.DebugWanted(9)) then
    self.debug(9, "not sent, %s: %s", why, K.Describe(...))
  end
end

-- @debug-start@
--
-- A pretend group (KRP.pretend) has nobody in it to talk to. Its chat, and a whisper to anybody in it but the player, is
-- shown to the player instead, so that what would have been said can still be seen, and addon messages to it go nowhere.
-- The guild is real and is talked to as ever.
--
local function pretend_member(target)
  local name = KRP.pretend and target and K.CanonicalName(target)

  return name and name ~= K.player.name and KRP.players and KRP.players[name] ~= nil
end

local function pretend_chat(text)
  printf(K.dcolor, L["not sent: %s"], text)
end
-- @debug-end@

local function send_to_raid_or_party_am(self, prio, hold, ...)
  local dist = group_channel()

  -- @debug-start@
  if (KRP.pretend) then
    said_nowhere(self, "the group is pretend", ...)
    return
  end
  -- @debug-end@

  if (not dist) then
    said_nowhere(self, "not in a group", ...)
    return
  end

  send_addon_msg(self, prio, hold, dist, nil, ...)
end

local function send_to_guild_am(self, prio, hold, ...)
  if (K.player.is_guilded) then
    send_addon_msg(self, prio, hold, "GUILD", nil, ...)
  else
    said_nowhere(self, "not in a guild", ...)
  end
end

local function send_whisper_am(self, target, prio, hold, ...)
  -- @debug-start@
  if (pretend_member(target)) then
    said_nowhere(self, "the group is pretend", ...)
    return
  end
  -- @debug-end@

  send_addon_msg(self, prio, hold, "WHISPER", target, ...)
end

--
-- Chat is refused along with addon messages, and what it says is about now, so while the game is refusing it nothing is sent.
--
local function chat_locked(self)
  if (messages_locked()) then
    tell_unsent(self.comms and self.comms.title)
    return true
  end

  return false
end

local function send_plain_message(self, text)
  local dist = group_channel()

  -- @debug-start@
  if (KRP.pretend) then
    pretend_chat(text)
    return
  end
  -- @debug-end@

  if (not dist or chat_locked(self)) then
    return
  end

  SendChatMessage(text, dist)
end

local function send_guild_message(self, text)
  if (not K.player.is_guilded or chat_locked(self)) then
    return
  end
  SendChatMessage(text, "GUILD")
end

local function send_whisper_message(self, text, target)
  -- @debug-start@
  if (pretend_member(target)) then
    pretend_chat(text)
    return
  end
  -- @debug-end@

  if (chat_locked(self)) then
    return
  end
  SendChatMessage(text, "WHISPER", nil, target)
end

local function send_raid_warning(self, text)
  -- @debug-start@
  if (KRP.pretend) then
    pretend_chat(text)
    return
  end
  -- @debug-end@

  if (chat_locked(self)) then
    return
  end

  if (KRP.in_bg) then
    SendChatMessage("{skull}{skull} " .. text .. " {skull}{skull}", "INSTANCE_CHAT")
  elseif (KRP.in_raid) then
    if (KRP.is_aorl) then
      SendChatMessage(text, "RAID_WARNING")
    else
      SendChatMessage("{skull}{skull} " .. text .. " {skull}{skull}", "RAID")
    end
  elseif (KRP.in_party) then
    SendChatMessage("{skull}{skull} " .. text .. " {skull}{skull}", "PARTY")
  end
end

--
-- Register a table to talk on the wire. KMOD is the table and KMOD.comms describes it:
--
--   handle   Unique among everything registered. The registry is keyed by it, and it names the frames this library builds on
--            KMOD's behalf, so it must be usable as the start of a frame name.
--   title    What those frames call KMOD.
--
-- That is the whole of it, and it says nothing about what KMOD sends, where it may send it, or what it will answer. Whether
-- a message survives being held and whether a group is a fit place to be talking are both the caller's to decide, the first
-- at the call site and the second before it gets here, because neither is legible from this side.
--
-- Returns that descriptor, which is what the registry holds, and returns the one already registered if the handle is taken
-- rather than registering twice.
--
-- KMOD supplies CHAT_MSG_PREFIX and subscribes to it itself with KC.Listen once it is ready to hear anything. Everything it
-- sends goes out under that prefix and nothing else.
--
function KC.RegisterComms(kmod)
  local targ = kmod.comms
  if (not targ or type(targ) ~= "table") then
    error("Invalid call to RegisterComms.", 2)
  end

  local me = registry[targ.handle]
  if (me ~= nil) then
    return me
  end

  kmod.SendAM = send_to_raid_or_party_am
  kmod.SendGuildAM = send_to_guild_am
  kmod.SendWhisperAM = send_whisper_am
  kmod.SendText = send_plain_message
  kmod.SendGuildText = send_guild_message
  kmod.SendWhisper = send_whisper_message
  kmod.SendWarning = send_raid_warning
  kmod.KonferCommReceived = comm_received

  --
  -- What a window KMOD put up calls itself. Kept on KMOD rather than worked out by whoever draws the window, so that a
  -- dialog of Kore's raised on KMOD's behalf is plated as KMOD's own windows are without Kore knowing what KMOD is. An
  -- endpoint that is part of something larger, a policy inside a mod, sets its own before registering and keeps it.
  --
  kmod.WindowTitle = kmod.WindowTitle or function(self, what)
    return K.WindowTitle(nil, self.comms and self.comms.title, what)
  end

  registry[targ.handle] = targ

  return targ
end

--
-- Start KMOD hearing its CHAT_MSG_PREFIX, or stop it for ONOFF false. The game allows a client only so many prefixes across
-- every addon, and a prefix it refuses is one nothing ever arrives under, so that is said, once for each prefix, rather than
-- left to look like nobody is talking.
--
local prefix_refused = {}

function KC.Listen(kmod, onoff)
  local prefix = kmod.CHAT_MSG_PREFIX

  if (not onoff) then
    K.UnregisterComm(kmod, prefix)
    return
  end

  K.RegisterComm(kmod, prefix)

  if (not C_ChatInfo.IsAddonMessagePrefixRegistered(prefix) and not prefix_refused[prefix]) then
    prefix_refused[prefix] = true
    local who = (kmod.comms and kmod.comms.title) or prefix

    printf(K.ecolor, L["%s communication registration failed!"], K.KAHLUA .. " " .. who)
  end
end
