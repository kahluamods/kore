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
-- The Kore wire protocol version. This versions the message envelope only:
-- the framing, the checksum and the serialisation. It is shared by every
-- Kore-based addon and is entirely separate from any addon's own protocol
-- number, which versions that addon's events and their arguments.
--
--   1 - initial version. The CRC32 covers the header (protocol, command and
--       config) as well as the payload.
--
-- There is only one envelope version, so there is nothing to fall back to on
-- receipt: a message either checksums as version 1 or it is rejected. When a
-- second version is added, comm_received() below is where the receiver has to
-- learn how to recognise the older one.
--
KC.WIRE_VERSION = 1

--
-- The channels a caller's config can talk on. This is the only field
-- KoreComms interprets in a config table, and it has just two meaningful
-- values: the guild addon channel, or the group the player is currently in.
-- Anything absent or unrecognised is treated as CHANNEL_OTHER, so a caller
-- that knows nothing about channels still gets sensible group-local delivery.
--
KC.CHANNEL_GUILD = 1
KC.CHANNEL_OTHER = 2

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
local gmatch = string.gmatch
local bor = bit.bor
local band = bit.band
local bxor = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift
local MakeFrame= KUI.MakeFrame

--
-- Every Konfer-family *addon* that has registered with Kore, keyed by its
-- addon handle. RegisterComms() records the addon here, and uses it to
-- recognise a repeat registration.
--
-- Do not confuse this with the loot distribution policies -- Suicide Kings,
-- EP/GP, DKP, PUG. Those are not addons and they do not appear here: they
-- register with the Konfer addon itself, through its konfer:RegisterPolicy(),
-- because Konfer is the system that knows about distribution policy. Kore
-- deliberately does not, so that the looting mechanics it provides stay
-- policy-agnostic.
--
-- Kept on KC rather than in _G so that the name "Konfer" in the global
-- namespace belongs to the Konfer addon alone. LibStub hands back the same
-- KC table across a library upgrade, so this survives one just as a global
-- would.
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

function KC.CreateNewID(strtohash)
  local _, y, mo, d, h, m = KC.TimeStamp()
  local ts = strfmt("%02d%02d%02d", y-2000, mo, d)
  local crc = H:CRC32(ts, nil, false)
  crc = H:CRC32(tostring(h), crc, false)
  crc = H:CRC32(tostring(m), crc, false)
  crc = H:CRC32(strtohash, crc, true)
  ts = ts .. K.hexstr(crc)
  return ts
end

function KC:OldProtoDialog()
  if (self.old_proto) then
    return
  end

  self.old_proto = true

  local arg = {
    name = self.comms.handle .. "OldProtoDialog",
    x = "CENTER", y = "MIDDLE", border = true, blackbg = true,
    okbutton = { text = K.OK_STR }, canmove = false, canresize = false,
    escclose = false, width = 450, height = 100, title = self.comms.title,
  }
  local dlg = KUI:CreateDialogFrame(arg)
  dlg.OnAccept = function(this)
    this:Hide()
  end
  dlg.OnCancel = function(this)
    this:Hide()
  end

  arg = {
    x = 8, y = -10, width = 410, height = 64, autosize = false,
    color = { r = 1, g = 0, b = 0, a = 1},
    text = self.comms.title .. ": " .. strfmt(L["your version of %s is out of date. Please update it."], self.comms.title),
    font = "GameFontNormal", justifyv = "TOP",
  }
  dlg.str1 = KUI:CreateStringLabel(arg, dlg)

  if (self.mainwin and self.mainwin:IsShown()) then
    self.mainwin:Hide()
  end
  dlg:Show()
end

--
-- This is the function that is responsible for creating all internal addon
-- messages we send. It implements all and any "protocol" we want to use to
-- communicate between different instances of the addon. It has a reciprocal
-- function comm_received below that should be used to decode all messages
-- received by the addon. Thus, as long as these two functions can deal with
-- changes between each other, pretty much any protocol can be used. For right
-- now the basic protocol is that each message is always a string that begins
-- with two lower case hexadecimal numbers, followed by a colon, followed
-- immediately by the payload, which extends from this point to the end of the
-- message.
--
-- The payload protocol is always a colon separated list in the form:
--   command:cfgid:crc32:data
--
-- Each handler is called with the command, config ID, protocol version and
-- then any other data.
--
-- Two independent things are versioned here, and they must not be confused:
--
--   KC.WIRE_VERSION (above) versions this envelope -- the framing, the
--   checksum and the serialisation. It belongs to Kore, is the same for every
--   addon built on it, and changes only when this file or KoreHash changes.
--
--   self.protocol is the *addon's* protocol: the set of events it sends and
--   understands, and their arguments. It says nothing about the wire format.
--
-- A change to one must never require a bump of the other.
--
local function send_addon_msg(self, cfg, cmd, prio, dist, target, ...)
  local proto = self.protocol
  local rcmd

  if (type(cmd) == "table") then
    proto = cmd.proto
    rcmd = cmd.cmd
  else
    rcmd = cmd
  end

  local serialised = LS:Serialize(...)
  if (not serialised) then
    self.debug(4, "failed to serialise data for %q", rcmd)
    return
  end

  local compressed = ZL:CompressDeflate(serialised, { level = 5 })
  if (not compressed) then
    self.debug(4, "failed to compress data for %q", rcmd)
    return
  end

  local encoded = ZL:EncodeForWoWAddonChannel(compressed)
  if (not encoded) then
    self.debug(4, "encode failed for %q", rcmd)
    return nil
  end

  local cfg = cfg or self.currentid or "0"
  local prio = prio or "ALERT"
  local fs = strfmt("%02x:%s:%s:", proto, rcmd, cfg)
  local crc = H:CRC32(fs, nil, false)
  crc = H:CRC32(encoded, crc, true)
  fs = fs .. K.hexstr(crc) .. ":" .. encoded

  self.debug(9, "send: dist=%s msg=%q", dist, strsub(fs, 1, 48))

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

  self.debug(9, "recv: dist=%s snd=%s msg=%q", tostring(dist), tostring(snd), strsub(tostring(msg), 1, 48))

  if (dist == "UNKNOWN" and (sender ~= nil and sender ~= "")) then
    return
  end

  -- Create the itterator for splitting on a :
  local iter = gmatch(msg, "([^:]+)()")

  -- Get the protocol (should be 2 hex digits)
  local ps = iter()
  if (not ps) then
    self.debug(4, "bad msg received from %q", sender)
    return
  end

  local proto = tonumber(ps, 16)

  if (not proto) then
    self.debug(4, "unparseable protocol from %q", sender)
    return
  end

  if (proto > self.protocol) then
    KC.OldProtoDialog(self)
    return
  end

  -- Now get the command
  local cmd = iter()
  if (not cmd) then
    self.debug(4, "malformed cmd msg received from %q", sender)
    return
  end

  -- And the config this message is for
  local cfg = iter()
  if (not cfg) then
    self.debug(4, "malformed cfg msg received from %q", sender)
    return
  end

  -- Get the message checksum
  local msum, pos = iter()
  if (not msum) then
    self.debug(4, "malformed msum msg received from %q", sender)
    return
  end

  -- The rest of the message is the payload
  local data = strsub(msg, pos+1)
  if (not data) then
    self.debug(4, "malformed data msg received from %q", sender)
    return
  end

  --
  -- The envelope carries no version field of its own: the span the CRC32
  -- covers is what identifies it. At wire version 1 that span is the header
  -- (protocol, command and config) followed by the payload, exactly as
  -- send_addon_msg() below computes it.
  --
  local crc = H:CRC32(strfmt("%02x:%s:%s:", proto, cmd, cfg), nil, false)
  crc = H:CRC32(data, crc, true)
  local mf = K.hexstr(crc)

  if (mf ~= msum) then
    self.debug(1, "mismatch: cmd=%q mysum=%q theirsum=%q", tostring(cmd), tostring(mf), tostring(msum))
    warn_once(sender, "WARNING: addon message from %q was truncated!", tostring(sender))
    return
  end

  local decoded = ZL:DecodeForWoWAddonChannel(data)
  if (not decoded) then
    self.debug(4, "recv: decode failed for %q from %q", cmd, sender)
    return
  end


  local inflated = ZL:DecompressDeflate(decoded)
  if (not inflated) then
    self.debug(4, "recv: deflate failed for %q from %q", cmd, sender)
    return
  end

  dispatcher(self, sender, proto, cmd, cfg, LS:Deserialize(inflated))
end

--
-- Send to whichever channel the config named by CFG asks for. Which of RAID
-- or PARTY CHANNEL_OTHER resolves to comes from KoreParty, and is further
-- constrained by the raid and party flags in the caller's descriptor.
--
local function send_to_raid_or_party_am_c(self, cfg, cmd, prio, ...)
  local cfg = cfg or self.currentid
  local channel = KC.CHANNEL_OTHER

  if (cfg and self.configs and self.configs[cfg]) then
    channel = self.configs[cfg].channel or KC.CHANNEL_OTHER
  end

  local dist = nil

  if (channel == KC.CHANNEL_GUILD and K.player.is_guilded) then
    dist = "GUILD"
  else
    if (KRP.in_party and self.comms.party) then
      dist = "PARTY"
    end

    if (KRP.in_raid and self.comms.raid) then
      dist = "RAID"
    end
  end

  if (not dist) then
    return
  end

  send_addon_msg(self, cfg, cmd, prio, dist, nil, ...)
end

local function send_to_raid_or_party_am(self, cmd, prio, ...)
  send_to_raid_or_party_am_c(self, nil, cmd, prio, ...)
end

local function send_to_guild_am_c(self, cfg, cmd, prio, ...)
  if (K.player.is_guilded) then
    send_addon_msg(self, cfg, cmd, prio, "GUILD", nil, ...)
  end
end

local function send_to_guild_am(self, cmd, prio, ...)
  if (K.player.is_guilded) then
    send_addon_msg(self, nil, cmd, prio, "GUILD", nil, ...)
  end
end

local function send_whisper_am_c(self, cfg, target, cmd, prio, ...)
  send_addon_msg(self, cfg, cmd, prio, "WHISPER", target, ...)
end

local function send_whisper_am(self, target, cmd, prio, ...)
  send_addon_msg(self, nil, cmd, prio, "WHISPER", target, ...)
end

local function send_plain_message(self, text)
  if (not KRP.in_party) then
    return
  end

  local dist = "PARTY"
  if (KRP.in_raid) then
    dist = "RAID"
  end

  SendChatMessage(text, dist)
end

local function send_guild_message(self, text)
  if (not K.player.is_guilded) then
    return
  end
  SendChatMessage(text, "GUILD")
end

local function send_whisper_message(self, text, target)
  SendChatMessage(text, "WHISPER", nil, target)
end

local function send_raid_warning(self, text)
  if (KRP.in_raid) then
    if (KRP.is_aorl) then
      SendChatMessage(text, "RAID_WARNING")
    else
      SendChatMessage("{skull}{skull} " .. text .. " {skull}{skull}", "RAID")
    end
  else
    SendChatMessage("{skull}{skull} " .. text .. " {skull}{skull}", "PARTY")
  end
end

--
-- Shared dialog for version checks.
--
local function vlist_newitem(objp, num)
  local kc = objp:GetParent():GetParent():GetParent().kcmod
  local bname = kc.comms.handle .. "KCVCheckListButton" .. tostring(num)
  local rf = MakeFrame("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local hfn = "GameFontHighlightSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth(325)
  rf:SetHeight(16)
  rf:SetHighlightTexture(htn, "ADD")

  local who = rf:CreateFontString(nil, "BORDER", nfn)
  who:ClearAllPoints()
  who:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, -2)
  who:SetPoint("BOTTOMLEFT", rf, "BOTTOMLEFT", 0, -2)
  who:SetWidth(168)
  who:SetJustifyH("LEFT")
  who:SetJustifyV("TOP")
  rf.who = who

  local version = rf:CreateFontString(nil, "BORDER", nfn)
  version:ClearAllPoints()
  version:SetPoint("TOPLEFT", who, "TOPRIGHT", 4, 0)
  version:SetPoint("BOTTOMLEFT", who, "BOTTOMRIGHT", 4, 0)
  version:SetWidth(95)
  version:SetJustifyH("LEFT")
  version:SetJustifyV("TOP")
  rf.version = version

  local raid = rf:CreateFontString(nil, "BORDER", nfn)
  raid:ClearAllPoints()
  raid:SetPoint("TOPLEFT", version, "TOPRIGHT", 4, 0)
  raid:SetPoint("BOTTOMLEFT", version, "BOTTOMRIGHT", 4, 0)
  raid:SetWidth(50)
  raid:SetJustifyH("LEFT")
  raid:SetJustifyV("TOP")
  rf.raid = raid

  rf.SetText = function(self, who, vers, raid)
    self.who:SetText(who)
    self.version:SetText(vers)
    if (raid) then
      self.raid:SetText(K.YES_STR)
    else
      self.raid:SetText(K.NO_STR)
    end
  end

  return rf
end

local function vlist_setitem(objp, idx, slot, btn)
  local kc = objp:GetParent():GetParent():GetParent().kcmod
  if (not kc or not kc.vcdlg or not kc.vcdlg.vcreplies) then
    return
  end

  local vcent = kc.vcdlg.vcreplies[idx]
  if (not vcent) then
    return
  end
  local name = kc.shortaclass(vcent)
  local vers = tonumber(vcent.version)
  local fn = kc.green
  if (vers < kc.version) then
    fn = kc.red
  end

  btn:SetText(name, fn(tostring(vers)), vcent.raid)
  btn:SetID(idx)
  btn:Show()
end

local function sort_vcreplies(self)
  tsort(self.vcdlg.vcreplies, function(a, b)
    if (a.raid and not b.raid) then
      return true
    end
    if (b.raid and not a.raid) then
      return false
    end
    if (a.version < b.version) then
      return true
    end
    if (b.version < a.version) then
      return false
    end
    return strlower(a.name) < strlower(b.name)
  end)
  self.vcdlg.slist.itemcount = #self.vcdlg.vcreplies
  self.vcdlg.slist:UpdateList()
end

local function kk_version_check(self)
  local vcdlg = self.vcdlg
  if (not vcdlg) then
    local ks = "|cffff2222<" .. K.KAHLUA ..">|r"
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = self.comms.handle .. "KCVersionCheck",
      title = strfmt(L["VCTITLE"], ks, self.comms.title),
      canmove = true,
      canresize = false,
      escclose = true,
      xbutton = false,
      width = 400,
      height = 350,
      framelevel = 64,
      titlewidth = 270,
      border = true,
      blackbg = true,
      okbutton = { text = K.OK_STR },
    }
    vcdlg = KUI:CreateDialogFrame(arg)
    vcdlg.kcmod = self

    vcdlg.OnAccept = function(this)
      this:Hide()
      if (this.mainshown) then
        this.kcmod.mainwin:Show()
      end
      this.mainshown = nil
      this.vcreplies = nil
    end
    vcdlg.OnCancel = vcdlg.OnAccept

    arg = {
      x = 5, y = 0, text = L["Who"], font = "GameFontNormal",
    }
    vcdlg.str1 = KUI:CreateStringLabel(arg, vcdlg)

    arg.x = 175
    arg.text = L["Version"]
    vcdlg.str2 = KUI:CreateStringLabel(arg, vcdlg)

    arg.x = 275
    arg.text = L["In Raid"]
    vcdlg.str3 = KUI:CreateStringLabel(arg, vcdlg)

    vcdlg.sframe = MakeFrame("Frame", nil, vcdlg.content)
    vcdlg.sframe:ClearAllPoints()
    vcdlg.sframe:SetPoint("TOPLEFT", vcdlg.content, "TOPLEFT", 5, -18)
    vcdlg.sframe:SetPoint("BOTTOMRIGHT", vcdlg.content, "BOTTOMRIGHT", 0, 0)


    arg = {
      name = self.comms.handle .. "KCVersionScrollList",
      itemheight = 16, newitem = vlist_newitem, setitem = vlist_setitem,
      selectitem = function(objp, idx, slot, btn, onoff) return end,
      highlightitem = function(objp, idx, slot, btn, onoff)
        return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
      end,
    }
    vcdlg.slist = KUI:CreateScrollList(arg, vcdlg.sframe)

    self.vcdlg = vcdlg
  end

  --
  -- Populate the expected replies with all current raid members and if we
  -- are in a guild, with all currently online guild members. We set the
  -- version to 0 to indicate no reply yet. As replies come in we change the
  -- version number and re-sort and refresh the list.
  --

  vcdlg.vcreplies = {}

  if (KRP.players) then
    for k, v in pairs(KRP.players) do
      local vce = { name = k, class = v.class, version = 0, raid = true }
      if (k == K.player.name) then
        vce.version = self.version
      end
      tinsert(vcdlg.vcreplies, vce)
    end
  end

  if (K.player.is_guilded) then
    for k, v in pairs(K.guild.roster.id) do
      if ((not KRP.players or not KRP.players[v.name]) and v.online) then
        local vce = { name = v.name, class = v.class, version = 0, raid = false }
        if (v.name == K.player.name) then
          vce.version = self.version
        end
        tinsert(vcdlg.vcreplies, vce)
      end
    end
  end

  sort_vcreplies(self)

  vcdlg.mainshown = self.mainwin:IsShown()
  self.mainwin:Hide()
  vcdlg:Show()

  self:SendAM({cmd = "VCHEK"}, nil)
  if (K.player.is_guilded) then
    self:SendGuildAM({cmd = "VCHEK"}, nil)
  end
end

local function kk_version_check_reply(self, sender, version)
  if (not self.vcdlg or not self.vcdlg.vcreplies) then
    return
  end

  for k, v in pairs(self.vcdlg.vcreplies) do
    if (v.name == sender) then
      v.version = version
      sort_vcreplies(self)
      return
    end
  end
end

--
-- Register a new addon (like Konfer) with the base Konfer system. The single
-- argument to this function is a table with various parameters, as described
-- below. Returns a handle to the mod, which is a table.
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

  assert(kmod.protocol)

  kmod.comms = targ
  kmod.CSendAM = send_to_raid_or_party_am_c
  kmod.SendAM = send_to_raid_or_party_am
  kmod.CSendGuildAM = send_to_guild_am_c
  kmod.SendGuildAM = send_to_guild_am
  kmod.CSendWhisperAM = send_whisper_am_c
  kmod.SendWhisperAM = send_whisper_am
  kmod.SendText = send_plain_message
  kmod.SendGuildText = send_guild_message
  kmod.SendWhisper = send_whisper_message
  kmod.SendWarning = send_raid_warning
  kmod.VersionCheck = kk_version_check
  kmod.VersionCheckReply = kk_version_check_reply
  kmod.KonferCommReceived = comm_received

  registry[targ.handle] = targ
end
