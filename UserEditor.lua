--[[
   KahLua Kore - the user editor, where the people are looked at and put right.
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

local KUI, KM = LibStub:GetLibrary("KoreUI")
assert(KUI, "Kore UserEditor requires KoreUI")
assert(tonumber(KM) >= 1, "Kore UserEditor requires KoreUI r1 or later")

local L = LibStub("AceLocale-3.0"):GetLocale("Kore")

local KU = K.Users
local MakeFrame = KUI.MakeFrame

local _G = _G
local tinsert = table.insert
local tconcat = table.concat
local tsort = table.sort
local strfmt = string.format
local strlower = string.lower
local strfind = string.find
local gmatch = string.gmatch
local pairs, ipairs, next, select = pairs, ipairs, next, select
local tonumber = tonumber
local max = math.max
local floor = math.floor
local ceil = math.ceil
local SlashCmdList = SlashCmdList

-- Signed with KahLua alone, the people belonging to no mod in particular. See K.err.
local err, info = K.err, K.info

local USER_KUID = KU.USER_KUID
local USER_CLASS = KU.USER_CLASS
local USER_PPROF = KU.USER_PPROF
local USER_SPROF = KU.USER_SPROF
local USER_ALTOF = KU.USER_ALTOF
local USER_ALTS  = KU.USER_ALTS
local USER_MSROLE = KU.USER_MSROLE
local USER_OSROLE = KU.USER_OSROLE
local USER_RACE = KU.USER_RACE
local USER_LEVEL = KU.USER_LEVEL

--
-- The user editor: every character the mod knows on this faction and realm, and what is true of each of them, their class,
-- their race, their level, their main and off specs and their professions. It is the mod's rather than any policy's, and it
-- has no config in hand. What a config or a policy thinks of somebody is that config's business and is edited in that
-- policy's own window. Nothing here shows it or could, since the mod never looks inside a policy's configs.
--
-- Whose alt somebody is is the one exception, and it is here because it is a fact about the human rather than an opinion of
-- any config's. Every config of every mod reads this one link, so a main set here is their main everywhere, and a policy's
-- Users page edits the same field from the context where it matters.
--
-- It is reached from the Users button in the foyer, "/konfer users" and "/kuser", and like the settings window it takes the
-- foyer's place on screen when opened from there.
--

local WIN_HEIGHT    = 560
local WIN_MINHEIGHT = 420
local WIN_MAXHEIGHT = 1536

local BUTTON_H    = 22
local BUTTON_W    = 90

local SEARCH_W = 180
local NAME_H   = 20

--
-- The columns of the user list. Every one is a fixed width, so the list does not change shape with the window.
--
local COL_NAME_W  = 140
local COL_CLASS_W = 100
local COL_SPEC_W  = 100
local COL_PROF_W  = 110
local COL_MAIN_W  = 140

--
-- The window is a fixed width, its columns being fixed widths, and may only be dragged taller or shorter, which shows more or
-- fewer users. The two spec columns and their gaps are on top of the width the rest of the window was laid out at.
--
local WIN_WIDTH = 980 + COL_SPEC_W + KUI.COLUMN_GAP + COL_SPEC_W + KUI.COLUMN_GAP

local RATE_ROWS = KU.RATE_ROWS

KU.usereditwin = KUI:CreateDialogFrame({
  x = "CENTER", y = "MIDDLE",
  name = "KoreUserEditWin",
  title = KU:WindowTitle(L["USEREDIT_TITLE"]),
  canmove = true,
  canresize = "HEIGHT",
  escclose = true,
  xbutton = true,
  blackbg = true,
  width = WIN_WIDTH,
  height = WIN_HEIGHT,
  minwidth = WIN_WIDTH,
  minheight = WIN_MINHEIGHT,
  maxwidth = WIN_WIDTH,
  maxheight = WIN_MAXHEIGHT,
})

local qf = {}

--
-- Every user as a row, built from KU.users each time the list is drawn, and the rows the search leaves. A row carries the
-- user's KUID, their full Name for the search, the KUID of their main as MAINKUID, and everything else as the words the list
-- shows and sorts by.
--
local allrows = {}
local rows = {}

--
-- The selected user, by KUID rather than by place in the list, because the list is rebuilt underneath it whenever the search
-- changes, a column is sorted or anything about the users changes, and a rename does not change who they are.
--
local selkuid = nil

local searchtext = ""

--
-- The rating filter: the least rating a user must have at each thing it names, as a table from a RATE_ constant to a RATING_
-- one, empty when nothing is filtered. A user not rated at something the filter names is left out, unless FILTERUNRATED says
-- that a user with no rating there passes.
--
local filter = {}
local filterunrated = false

--
-- Whether the list shows each main with their alts under them, rather than everybody on their own.
--
local tethered = false

--
-- What the details panel has been changed to and not yet saved, or nil with nobody selected.
--
local einfo = nil

-- What the details panel was loaded with, so that what has been changed since can be told from what has not.
local ebase = nil

--
-- Set while the window is standing aside for a dialog of its own rather than being closed, so that its closing does not put
-- anybody's window back. STOOD_ASIDE is the mods that took a window off the screen for this one, keyed by handle, each to be
-- told when it closes (see KU:RegisterConsumer).
--
local dialog_open = false
local stood_aside = {}

--
-- How short the window may be dragged: WIN_MINHEIGHT, or taller when the right hand column needs more (see fit_detail_panel).
--
local minheight = WIN_MINHEIGHT

local function class_name(cid)
  local ic = cid and K.IndexClass[cid]

  return ic and ic.c or ""
end

local function prof_name(pid)
  local ip = pid and K.IndexProf[pid]

  return ip and ip.c or ""
end

-- A spec, which is the role a player raids in, in words, or nothing for one not set.
local function spec_name(role)
  return (role and role ~= K.ROLE_UNSET) and K.RoleName(role) or ""
end

local function build_rows()
  allrows = {}

  for name, rec in pairs(KU.users or {}) do
    local mainname = rec[USER_ALTOF] and KU.kuids[rec[USER_ALTOF]]

    tinsert(allrows, {
      kuid = rec[USER_KUID], fullname = name, name = K.DisplayName(name), cid = rec[USER_CLASS],
      class = class_name(rec[USER_CLASS]), msspec = spec_name(rec[USER_MSROLE]), osspec = spec_name(rec[USER_OSROLE]),
      p1 = prof_name(rec[USER_PPROF]), p2 = prof_name(rec[USER_SPROF]),
      main = mainname and K.DisplayName(mainname) or "", mainkuid = rec[USER_ALTOF],
    })
  end
end

--
-- Whether ROW answers every word of the search. Each word has to turn up somewhere in the row: in the name with its realm, the
-- class, either spec, either profession, or the name of whoever they are an alt of. So "mage tailor" is every mage who is a
-- tailor, a realm name is everybody from that realm, and a main's name finds the main and all of their alts together.
--
local function matches(row, words)
  local hay = strlower(tconcat({ row.fullname, row.class, row.msspec, row.osspec, row.p1, row.p2, row.main }, " "))

  for k, w in ipairs(words) do
    if (not strfind(hay, w, 1, true)) then
      return false
    end
  end

  --
  -- And has at least every rating the filter asks for.
  --
  for which, least in pairs(filter) do
    local rating = KU:Rating(row.kuid, which)

    if (rating) then
      if (rating < least) then
        return false
      end
    elseif (not filterunrated) then
      return false
    end
  end

  return true
end

--
-- The rows the search leaves, in the order the list is sorted in.
--
-- With alts tethered to mains, a main and their alts are one group: the mains are sorted, and each is followed by their alts,
-- sorted the same way and drawn as the main's branches. A group is shown whole when any one of it answers the search, so an alt is never shown
-- without the main it belongs under, and finding a main finds everybody who is them.
--
local function filter_rows()
  local words = {}

  for w in gmatch(strlower(searchtext), "%S+") do
    tinsert(words, w)
  end

  rows = {}

  if (not tethered) then
    for k, v in ipairs(allrows) do
      v.tree = nil
      if (matches(v, words)) then
        tinsert(rows, v)
      end
    end

    qf.list:Sort(rows)
    return
  end

  local alts = {}
  local mains = {}

  for k, v in ipairs(allrows) do
    if (v.mainkuid) then
      alts[v.mainkuid] = alts[v.mainkuid] or {}
      tinsert(alts[v.mainkuid], v)
    end
  end

  for k, v in ipairs(allrows) do
    if (not v.mainkuid) then
      local found = matches(v, words)

      for kk, alt in ipairs(alts[v.kuid] or {}) do
        found = found or matches(alt, words)
      end

      if (found) then
        tinsert(mains, v)
      end
    end
  end

  qf.list:Sort(mains)

  for k, v in ipairs(mains) do
    v.tree = nil
    tinsert(rows, v)

    local group = alts[v.kuid] or {}

    qf.list:Sort(group)
    for kk, alt in ipairs(group) do
      alt.tree = (kk == #group) and "end" or "branch"
      tinsert(rows, alt)
    end
  end
end


--
-- The details panel and the buttons that act on a user can only be used with somebody selected, and read as such.
--
local function sync_detail_panel()
  local has = einfo ~= nil

  qf.detailpanel:SetEnabled(has)
  qf.shared:SetEnabled(has)
  qf.notespanel:SetEnabled(has)
  qf.notes:SetEnabled(has)
  qf.renamebutton:SetEnabled(has)
  qf.deletebutton:SetEnabled(has)

  if (not has) then
    qf.updatebutton:SetEnabled(false)
  end
end

--
-- The window can be dragged no shorter than MINHEIGHT, and is never wider or narrower than the list's columns make it (see
-- apply_tether). A window already shorter than that is made tall enough.
--
local function set_window_bounds()
  local win = KU.usereditwin
  local width = WIN_WIDTH - (tethered and (COL_MAIN_W + KUI.COLUMN_GAP) or 0)

  win:SetResizeBounds(width, minheight, width, WIN_MAXHEIGHT)
  win:SetWidth(width)

  if (win:GetHeight() < minheight) then
    win:SetHeight(minheight)
  end
end

--
-- The details panel is exactly as tall as what is in it. The alts box wraps its words and is ALTS_LINES lines tall, or taller
-- when they need more, the Update button hangs the usual gap under it, and the panel ends at the foot of the button.
--
-- The personal notes panel under it is already as tall as its contents, so the right hand column is the two together, and the
-- window has to be tall enough for that and the row of buttons along its foot.
--
local ALTS_LINES = 2

local function fit_detail_panel()
  local panel = qf.detailpanel
  local box = qf.altslabel
  local alts = max(box.label:GetStringHeight(), qf.lineheight * ALTS_LINES) + box.xtraheight
  local win = KU.usereditwin

  box:SetHeight(alts)
  panel:SetHeight(qf.altstop + alts + KUI.WIDGET_GAP + qf.updatebutton:GetHeight() + panel.rings.top + panel.rings.bottom)

  local column = panel:GetHeight() + qf.notesmin

  minheight = max(WIN_MINHEIGHT, win.rings.top + column + BUTTON_H + win.rings.bottom)
  set_window_bounds()
end

--
-- Put the selected user into the details panel, or empty it.
--
local function show_user()
  local rec = KU:Record(selkuid)

  einfo = nil
  qf.notes:SetUser(rec and selkuid or nil)

  if (not rec) then
    qf.namelabel:SetText("")
    qf.altslabel:SetText("")
    qf.shared:SetUser(nil)
    sync_detail_panel()
    return
  end

  einfo = {
    msspec = rec[USER_MSROLE] or K.ROLE_UNSET,
    osspec = rec[USER_OSROLE] or K.ROLE_UNSET,
    pprof = rec[USER_PPROF] or K.PROF_UNSET,
    sprof = rec[USER_SPROF] or K.PROF_UNSET,
    main = rec[USER_ALTOF] or "",
  }

  ebase = {}
  for k, v in pairs(einfo) do
    ebase[k] = v
  end

  --
  -- The name in class colour, and after it what the game itself says about the character: what level they had reached when we
  -- last heard, and what race they are. Neither is edited, both being the game's own word, and both arrive with a raid info
  -- check rather than from anybody's typing.
  --
  local about = {}

  if (rec[USER_LEVEL]) then
    tinsert(about, strfmt(L["USEREDIT_LEVEL"], rec[USER_LEVEL]))
  end

  if (K.RaceName(rec[USER_RACE])) then
    tinsert(about, K.RaceName(rec[USER_RACE]))
  end

  qf.namelabel:SetText(KU:String(selkuid) .. (next(about) and ("   " .. tconcat(about, " ")) or ""))
  qf.shared:SetUser(selkuid)

  -- Their alts in name order, the record holding them in no order of its own.
  local altkuids = {}
  local alts = {}

  for k, v in ipairs(rec[USER_ALTS] or {}) do
    tinsert(altkuids, v)
  end

  tsort(altkuids, function(a, b)
    return (KU.kuids[a] or "") < (KU.kuids[b] or "")
  end)

  for k, v in ipairs(altkuids) do
    tinsert(alts, KU:String(v))
  end

  qf.altslabel:SetText(next(alts) and strfmt(L["USEREDIT_ALTS"], tconcat(alts, ", ")) or L["USEREDIT_NOALTS"])
  qf.updatebutton:SetEnabled(false)
  sync_detail_panel()
end

local function changed()
  qf.updatebutton:SetEnabled(einfo ~= nil)
end

--
-- The fields of the details panel the user has changed and not yet saved, or nil for none. The list is rebuilt whenever
-- anything about the users changes, or the search or sort does, and reselecting the user reloads the panel from what is
-- stored, so these are put back over it. Only what was changed is put back, so that a fact changed elsewhere meanwhile that
-- this user did not touch is not written back as it was.
--
local function pending_edits()
  if (not einfo or not ebase or not qf.updatebutton:IsEnabled()) then
    return nil
  end

  local edits = nil

  for k, v in pairs(einfo) do
    if (v ~= ebase[k]) then
      edits = edits or {}
      edits[k] = v
    end
  end

  return edits
end

--
-- Save the details panel to the selected user. The alt link is the one edit that can be refused, which can still happen when
-- the users changed after the menu was built, and when it is the rest are still saved and the reason is given.
--
local function update_user()
  if (not einfo or not KU:Record(selkuid)) then
    return
  end

  -- Saved, so nothing is left to put back when what saving it refreshes reloads the panel.
  qf.updatebutton:SetEnabled(false)

  KU:SetRoles(selkuid, einfo.msspec, einfo.osspec)
  KU:SetProfessions(selkuid, einfo.pprof, einfo.sprof)

  local moved = einfo.main ~= (KU:Main(selkuid) or "")
  local ok, msg = KU:SetMain(selkuid, einfo.main, true)

  if (not ok) then
    err("%s", msg)
  end

  --
  -- Every window that shows this user shows their class and professions too, whether or not the alt link moved. Where it did
  -- move, and stuck, the mods are told which character it was, the link being one every configuration of theirs reads.
  --
  if (ok and moved) then
    KU:UserMainSet(selkuid)
  else
    KU:UserLinksChanged()
  end
end

local function list_selectitem(cl, idx, slot, row, onoff)
  if (onoff) then
    selkuid = rows[idx] and rows[idx].kuid or nil
    show_user()
  elseif (onoff == nil) then
    selkuid = nil
    show_user()
  end
end

local function list_setitem(cl, idx, slot, row)
  local r = rows[idx]

  row:SetTree(r.tree, KU.TREE_LEAD)
  row:SetCell("name", KU:String(r.kuid))
  row:SetCell("class", r.class)
  row:SetCell("msspec", r.msspec)
  row:SetCell("osspec", r.osspec)
  row:SetCell("p1", r.p1)
  row:SetCell("p2", r.p2)
  row:SetCell("main", r.mainkuid and KU:String(r.mainkuid) or "")
  row:Show()
end

function KU:RefreshUserEditor()
  if (not qf.list or not self.usereditwin:IsShown()) then
    return
  end

  --
  -- UpdateList deselects, and a deselection clears the selection, so what was selected is held on to across it.
  --
  local want = selkuid
  local edits = pending_edits()

  build_rows()
  filter_rows()

  qf.list:UpdateList(#rows)

  --
  -- With a filter on, the count is how many are shown of how many there are, so that a short list reads as filtered.
  --
  if (next(filter)) then
    qf.count:SetText(strfmt("%d/%d", #rows, #allrows))
  else
    qf.count:SetText(strfmt(#rows == 1 and L["USEREDIT_COUNT_ONE"] or L["USEREDIT_COUNT"], #rows))
  end

  qf.guildbutton:SetEnabled(K.player.is_guilded and true or false)

  local idx = nil

  for k, v in ipairs(rows) do
    if (v.kuid == want) then
      idx = k
      break
    end
  end

  if (idx) then
    qf.list:SetSelected(idx, true, true)

    if (edits and einfo and selkuid == want) then
      for field, value in pairs(edits) do
        einfo[field] = value
      end

      qf.shared:SetValues(einfo)
      changed()
    end
  else
    selkuid = nil
    qf.list:SetSelected(nil)
    show_user()
  end
end

--
-- The window stands aside for each of its dialogs rather than sitting behind, and comes back when the dialog goes, however it
-- goes: OK, Cancel or Escape.
--
local function stand_aside(dlg)
  dialog_open = true
  KU.usereditwin:Hide()
  dlg:Show()
end

local function come_back()
  dialog_open = false
  KU.usereditwin:Show()
end

--
-- A dialog's own OK and Cancel handlers are replaced rather than caught, because the dialog's default hides it before anything
-- caught is called, and a name that is refused has to leave it open to be corrected.
--
local function make_dialog(name, title, width, height)
  local ret = KUI:CreateDialogFrame({
    x = "CENTER", y = "MIDDLE", name = name, title = KU:WindowTitle(title), border = true, width = width, height = height,
    canmove = true, canresize = false, escclose = true, blackbg = true,
    okbutton = true, cancelbutton = true,
  })

  ret:Catch("OnHide", function(this, evt)
    come_back()
  end)

  return ret
end

local createdlg = nil

--
-- The shared create user dialog, with nothing added to the standard fields, every one of which is what is true of the
-- character and so the editor's to keep. Only the player's own alt link can be refused, and a refusal still leaves the user made.
--
local function create_user()
  if (not createdlg) then
    createdlg = KU:CreateUserDialog({
      name = "KoreUserEditCreateDlg",
      err = err,
      accept = function(dlg, uinfo)
        local kuid, rec, isnew = KU:Add(uinfo.name, uinfo.class)

        if (not kuid) then
          err(L["you must specify a character name."])
          return true
        end

        if (not isnew) then
          err(L["user %q already exists. Try again."], KU:String(kuid))
          return true
        end

        KU:SetRoles(kuid, uinfo.msspec, uinfo.osspec)
        KU:SetProfessions(kuid, uinfo.pprof, uinfo.sprof)

        if (uinfo.main ~= "") then
          local ok, msg = KU:SetMain(kuid, uinfo.main, true)

          if (not ok) then
            err("%s", msg)
          end
        end

        --
        -- The new user is selected, and the search cleared so that they are in the list to be selected.
        --
        selkuid = kuid
        searchtext = ""
        qf.search:SetText("")
        info(L["user %q created."], KU:String(kuid))
        KU:UserLinksChanged()
      end,
    })

    createdlg:Catch("OnHide", function(this, evt)
      come_back()
    end)
  end

  dialog_open = true
  KU.usereditwin:Hide()
  createdlg:Open()
end

local renamedlg = nil

local function rename_user()
  if (not selkuid) then
    return
  end

  if (not renamedlg) then
    local lw = KUI:WidestString({ L["Old name"], L["New name"] })
    local ret = make_dialog("KoreUserEditRenameDlg", L["Rename user"], 370, 145)
    local ypos = 0

    ret.oldname = KUI:CreateStringLabel({
      x = 5, y = ypos, width = 330, height = NAME_H, autosize = false, font = "GameFontNormal", text = "",
    }, ret)

    ypos = ypos - NAME_H - KUI.WIDGET_GAP

    ret.newname = KUI:CreateEditBox({
      x = 5, y = ypos, len = 48, label = { text = L["New name"], pos = "LEFT", width = lw },
      tooltip = { title = "$$", text = L["TIP_USEREDIT_RENAME"] },
    }, ret)

    ret.OnAccept = function(this)
      local newname = this.newname:GetText()
      local ok, msg = KU:Rename(this.kuid, newname)

      if (not ok) then
        err("%s", msg)
        this.newname:SetFocus()
        return true
      end

      -- Still selected, a rename not changing who they are.
      this:Hide()
    end

    renamedlg = ret
  end

  renamedlg.kuid = selkuid
  renamedlg.oldname:SetText(L["Old name"] .. "  " .. KU:String(selkuid))
  renamedlg.newname:SetText("")
  stand_aside(renamedlg)
  renamedlg.newname:SetFocus()
end

local deletedlg = nil

local function delete_user()
  if (not selkuid) then
    return
  end

  --
  -- Refused before asking rather than after, since there is no point asking whether to do something that cannot be done.
  --
  local used = KU:Usage(selkuid)

  if (next(used)) then
    err(L["USER_DELETE_IN_USE"], KU:String(selkuid), KU:UsageText(used))
    return
  end

  if (not deletedlg) then
    local ret = make_dialog("KoreUserEditDeleteDlg", L["Delete user"], 400, 200)

    -- Who is to go, in a line at the top as every confirmation names what it is about (K.ConfirmationDialog).
    ret.username = KUI:CreateStringLabel({ x = "CENTER", y = -4, font = "GameFontNormal", text = "" }, ret)

    ret.msg = KUI:CreateStringLabel({
      x = 5, y = -36, width = 370, height = 72, autosize = false, justifyv = "TOP", font = "GameFontNormal",
      text = L["USEREDIT_DELMSG"],
    }, ret)

    ret.OnAccept = function(this)
      -- Named before they go, while their class still colours the name, and said once they have, as a new user is.
      local who = KU:String(this.kuid)
      local ok, msg = KU:Remove(this.kuid)

      if (not ok) then
        err("%s", msg)
      else
        selkuid = nil
        info(L["user %q deleted."], who)
      end

      this:Hide()
    end

    deletedlg = ret
  end

  deletedlg.kuid = selkuid
  deletedlg.username:SetText(strfmt(L["User: %s"], KU:String(selkuid)))
  stand_aside(deletedlg)
end

--
-- Import the guild into the mod's users, and nowhere else, the editor having no config to add them to. Each member new to the
-- mod is named as they are added, the way a policy's import names each user it creates.
--
local function guild_import()
  local function onadd(kuid, class, isnew)
    if (isnew) then
      info(L["user %q created."], KU:String(kuid))
    end
    return isnew
  end

  -- Stood aside once the dialog is up, as OpenGuildImport asks, in case it was already up for somebody else.
  KU:OpenGuildImport(onadd, function(count)
    come_back()
    if (count) then
      info(L["added %d user(s)."], count)
    end
  end)
  dialog_open = true
  KU.usereditwin:Hide()
end

--
-- The filter dialog: a line in gold saying what it does, FILTER_TEXT_GAP above what follows it, then whether users not rated
-- at something pass the filter for it, and under that the same rating grid the Skill Rating draws, at the same width,
-- each rating being the least a user must have to be listed. It opens holding the filter in use. Clear sets every rating
-- back to -Not set- and the checkbox off and leaves the dialog open, OK puts what it holds into use, and closing it any other way changes nothing.
--
-- The window is FILTER_BUTTON_GAP taller than what is in it, so that the grid stands that much further clear of the OK and
-- Clear buttons than the usual gap the dialog leaves above them, matching the gap under the words.
--
local FILTER_TEXT_GAP = KUI.WIDGET_GAP * 2
local FILTER_BUTTON_GAP = FILTER_TEXT_GAP - KUI.WIDGET_GAP

local filterdlg = nil

local function filter_users()
  if (not filterdlg) then
    local width = qf.ratingwidth
    local ret = KUI:CreateDialogFrame({
      x = "CENTER", y = "MIDDLE", name = "KoreUserEditFilterDlg", title = KU:WindowTitle(L["USEREDIT_FILTER_TITLE"]), border = true,
      width = 300, height = 300, canmove = true, canresize = false, escclose = true, blackbg = true, padding = 5,
      okbutton = true, cancelbutton = { text = L["USEREDIT_CLEAR"] },
    })

    local ypos = 0

    ret.blurb = KUI:CreateStringLabel({
      x = 0, y = ypos, width = width, autosize = false, justifyv = "TOP", font = "GameFontNormal",
      text = L["USEREDIT_FILTER_TEXT"],
    }, ret)
    ret.blurb.label:SetWordWrap(true)

    local th = ceil(ret.blurb.label:GetStringHeight()) + ret.blurb.xtraheight

    ret.blurb:SetHeight(th)
    ypos = ypos - th - FILTER_TEXT_GAP

    ret.unrated = KUI:CreateCheckBox({
      x = 0, y = ypos, label = { text = strfmt(L["USEREDIT_FILTER_UNRATED"], K.NOTSET_STR) },
      tooltip = { title = "$$", text = L["TIP_USEREDIT_FILTER_UNRATED"] },
    }, ret)
    ypos = ypos - ret.unrated:GetHeight() - KUI.WIDGET_GAP

    ret.grid = KU:CreateRatingGrid({
      prefix = "KoreUserEditFilter", x = 0, y = ypos, width = width, empty = K.NOTSET_STR,
      tooltip = L["TIP_USEREDIT_FILTER_RATING"],
      changed = function(which, rating)
        -- What the dialog holds is only put into use by OK.
      end,
    }, ret)
    ypos = ypos - ret.grid.height - FILTER_BUTTON_GAP

    ret:SetSize(width + ret.rings.left + ret.rings.right, ret.rings.top - ypos + ret.rings.bottom)

    ret.OnCancel = function(this)
      for _, r in ipairs(RATE_ROWS) do
        this.grid:Set(r.which, nil)
      end
      this.unrated:SetChecked(false, true)
    end

    ret.OnAccept = function(this)
      filter = {}

      for _, r in ipairs(RATE_ROWS) do
        filter[r.which] = this.grid:Get(r.which)
      end

      filterunrated = this.unrated:GetChecked() and true or false
      this:Hide()
    end

    ret:Catch("OnHide", function(this, evt)
      come_back()
    end)

    filterdlg = ret
  end

  for _, r in ipairs(RATE_ROWS) do
    filterdlg.grid:Set(r.which, filter[r.which])
  end

  filterdlg.unrated:SetChecked(filterunrated, true)
  stand_aside(filterdlg)
end

--
-- The people the player has stopped listening to altogether. Refusing what a broadcast offers is never remembered, so the
-- same broadcast asks again, which is right for somebody who simply has better information than we do and wrong for somebody
-- pushing nonsense at a whole guild. Blocking them is the answer to the second, and it throws away everything they broadcast
-- rather than any part of it.
--
-- Anybody can be blocked, whether or not the mod knows them as a user, because the point of blocking somebody is usually that
-- they are nobody we have anything to do with.
--
local blockeddlg = nil
local blockedrows = {}
local blockedsel = nil

local BLOCKED_W = 320
local BLOCKED_H = 380

local function refresh_blocked()
  if (not blockeddlg) then
    return
  end

  blockedrows = KU:BlockedSenders()

  if (blockedsel and blockedsel > #blockedrows) then
    blockedsel = nil
  end

  blockeddlg.list:SetSelected(blockedsel)
  blockeddlg.list:UpdateList(#blockedrows)
  blockeddlg.unblock:SetEnabled(blockedsel and true or false)
end

local function block_sender()
  local key = KU:SetSenderBlocked(blockeddlg.name:GetText(), true)

  if (not key) then
    err(L["%q is not a valid character name."], blockeddlg.name:GetText() or "")
    return
  end

  blockeddlg.name:SetText("")
  refresh_blocked()
end

local function blocked_senders()
  if (not blockeddlg) then
    local ret = KUI:CreateDialogFrame({
      x = "CENTER", y = "MIDDLE", name = "KoreUserEditBlockedDlg", title = KU:WindowTitle(L["USEREDIT_BLOCKED_TITLE"]), border = true,
      width = BLOCKED_W, height = BLOCKED_H, canmove = true, canresize = false, escclose = true, blackbg = true, padding = 5,
      okbutton = { text = K.CLOSE_STR },
    })

    local ypos = 0

    ret.name = KUI:CreateEditBox({
      x = 0, y = ypos, width = BLOCKED_W - BUTTON_W - KUI.WIDGET_GAP - ret.rings.left - ret.rings.right, len = 48,
      tooltip = { title = "$$", text = L["TIP_USEREDIT_BLOCKED_NAME"] },
    }, ret)
    ret.name:Catch("OnEnterPressed", function(this, evt)
      block_sender()
    end)

    ret.add = KUI:CreateButton({
      x = BLOCKED_W - BUTTON_W - ret.rings.left - ret.rings.right, y = ypos, width = BUTTON_W, height = BUTTON_H,
      text = L["USEREDIT_BLOCK"], tooltip = { title = "$$", text = L["TIP_USEREDIT_BLOCK"] },
    }, ret)
    ret.add:Catch("OnClick", function(this, evt)
      block_sender()
    end)
    ypos = ypos - max(ret.name:GetHeight(), BUTTON_H) - KUI.WIDGET_GAP

    ret.unblock = KUI:CreateButton({
      x = BLOCKED_W - BUTTON_W - ret.rings.left - ret.rings.right, y = 0, width = BUTTON_W, height = BUTTON_H,
      text = L["USEREDIT_UNBLOCK"], enabled = false, tooltip = { title = "$$", text = L["TIP_USEREDIT_UNBLOCK"] },
    }, ret)
    ret.unblock:ClearAllPoints()
    ret.unblock:SetPoint("BOTTOMRIGHT", ret.content, "BOTTOMRIGHT", 0, 0)
    ret.unblock:Catch("OnClick", function(this, evt)
      if (blockedsel) then
        KU:SetSenderBlocked(blockedrows[blockedsel], false)
        blockedsel = nil
        refresh_blocked()
      end
    end)

    --
    -- The list stops the usual gap above the Unblock button. The offset is positive because it lifts the panel's bottom edge
    -- clear of the button's top, where a negative one would push it down over the button instead.
    --
    local panel = KUI:CreateInset({}, ret)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", ret.content, "TOPLEFT", 0, ypos)
    panel:SetPoint("BOTTOMRIGHT", ret.unblock, "TOPRIGHT", 0, KUI.WIDGET_GAP)

    ret.list = KUI:CreateColumnList({
      name = "KoreUserEditBlockedList",
      columns = {
        { key = "who", text = L["USEROFFER_COL_WHO"], width = "fill" },
      },
      setitem = function(objp, idx, slot, row)
        -- A blocked sender need be nobody the mod knows, and is named in class colour only when they are.
        local kuid = KU:Find(blockedrows[idx])

        row:SetCell("who", kuid and KU:String(kuid) or K.DisplayName(blockedrows[idx]))
      end,
      selectitem = function(objp, idx, slot, row, onoff)
        blockedsel = onoff and idx or nil
        ret.unblock:SetEnabled(blockedsel and true or false)
      end,
    }, panel.content)

    ret:Catch("OnHide", function(this, evt)
      come_back()
    end)

    blockeddlg = ret
  end

  blockedsel = nil
  blockeddlg.name:SetText("")
  refresh_blocked()
  stand_aside(blockeddlg)
end

--
-- Tether alts to their mains, or stop. With alts tethered, whose alt somebody is shows in where they sit, so the Alt of
-- column goes, and a list sorted on it goes back to being sorted by name. The window gives up exactly the room the column
-- and its gap took, the list's panel narrowing with it, and takes it back when the column returns, the window's width being fixed either way.
--
local function apply_tether(onoff)
  tethered = onoff
  qf.list:SetColumnShown("main", not onoff)

  if (onoff and qf.list:GetSort() == "main") then
    qf.list:SetSort("name", true, false)
  end

  set_window_bounds()
end

function KU:InitialiseUserEditorUI()
  local cf = self.usereditwin.content

  --
  -- The buttons along the bottom sit on the foot of the content, which a dialog already stands the usual gap clear of the
  -- inner line of its rim, and the list's panel comes down to meet them.
  --
  local btns = MakeFrame("Frame", nil, cf)
  btns:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, 0)
  btns:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
  btns:SetHeight(BUTTON_H)

  --
  -- The details panel is as wide as its widest row, a label and a control beside it, which the shared block measures, and as
  -- tall as what is in it (see fit_detail_panel), the list taking everything else. Its size is set once it is built.
  --
  local right = KUI:CreateInset({ title = L["USER_SHARED_INFO"] }, cf)
  right:ClearAllPoints()
  right:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 0, 0)
  qf.detailpanel = right

  local left = KUI:CreateInset({ title = L["Users"] }, cf)
  left:ClearAllPoints()
  left:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", btns, "TOPLEFT", 0, 0)
  left:SetPoint("RIGHT", right, "LEFT", 0, 0)

  --
  -- The search sits in a row of its own over the list, with how many users it has left showing against the right hand edge.
  --
  local lc = left.content
  local srow = MakeFrame("Frame", nil, lc)
  srow:SetPoint("TOPLEFT", lc, "TOPLEFT", 0, 0)
  srow:SetPoint("TOPRIGHT", lc, "TOPRIGHT", 0, 0)

  qf.search = KUI:CreateEditBox({
    x = 0, y = 0, width = SEARCH_W, len = 64,
    label = { text = L["USEREDIT_SEARCH"], pos = "LEFT" },
    tooltip = { title = "$$", text = L["TIP_USEREDIT_SEARCH"] },
  }, srow)
  srow:SetHeight(qf.search:GetHeight())
  qf.search:Catch("OnValueChanged", function(this, evt, newv, user)
    if (user) then
      searchtext = newv or ""
      self:RefreshUserEditor()
    end
  end)
  qf.search:Catch("OnEscapePressed", function(this, evt)
    this:SetText("")
    searchtext = ""
    self:RefreshUserEditor()
  end)

  qf.tether = KUI:CreateCheckBox({
    label = { text = L["USEREDIT_TETHER"] },
    tooltip = { title = "$$", text = L["TIP_USEREDIT_TETHER"] },
  }, srow)
  qf.tether:ClearAllPoints()
  qf.tether:SetPoint("LEFT", qf.search, "RIGHT", KUI.WIDGET_GAP, 0)
  qf.tether:Catch("OnValueChanged", function(this, evt, onoff)
    K.chardb.useredittether = onoff and true or false
    apply_tether(onoff and true or false)
    self:RefreshUserEditor()
  end)

  qf.count = KUI:CreateStringLabel({ text = "", font = "GameFontNormalSmall", justifyh = "RIGHT" }, srow)
  qf.count:ClearAllPoints()
  qf.count:SetPoint("RIGHT", srow, "RIGHT", 0, 0)

  local lframe = MakeFrame("Frame", nil, lc)
  lframe:SetPoint("TOPLEFT", srow, "BOTTOMLEFT", 0, 0 - KUI.WIDGET_GAP)
  lframe:SetPoint("BOTTOMRIGHT", lc, "BOTTOMRIGHT", 0, 0)

  qf.list = KUI:CreateColumnList({
    name = "KoreUserEditList",
    sortkey = "name",
    columns = {
      { key = "name", text = L["USEREDIT_COL_NAME"], width = COL_NAME_W, sort = true },
      { key = "class", text = L["USEREDIT_COL_CLASS"], width = COL_CLASS_W, sort = true },
      { key = "main", text = L["USEREDIT_COL_MAIN"], width = COL_MAIN_W, sort = true },
      { key = "msspec", text = L["USEREDIT_COL_MSSPEC"], width = COL_SPEC_W, sort = true },
      { key = "osspec", text = L["USEREDIT_COL_OSSPEC"], width = COL_SPEC_W, sort = true },
      { key = "p1", text = L["USEREDIT_COL_PROF1"], width = COL_PROF_W, sort = true },
      { key = "p2", text = L["USEREDIT_COL_PROF2"], width = COL_PROF_W, sort = true },
    },
    setitem = list_setitem,
    selectitem = list_selectitem,
  }, lframe)
  qf.list:Catch("OnSort", function()
    self:RefreshUserEditor()
  end)

  --
  -- The details of the selected user, one control to a row down the panel. Everything here is what is true of the character,
  -- so apart from the name at the top and the alts under it, it is the shared block every policy's Users page shows too.
  --
  local rc = right.content
  local ypos = 0

  qf.namelabel = KUI:CreateStringLabel({
    x = 0, y = ypos, height = NAME_H, autosize = false, font = "GameFontHighlight", text = "",
  }, rc)
  ypos = ypos - NAME_H - KUI.WIDGET_GAP

  qf.shared = self:CreateSharedUserInfo({
    prefix = "UserEdit", x = 0, y = ypos,
    changed = function(field, value)
      if (einfo) then
        einfo[field] = value
        changed()
      end
    end,
  }, rc)
  ypos = qf.shared.ypos

  --
  -- Under the details, this player's own notes on the user (KU:CreateUserNotes), in a panel of their own because none of it is
  -- fact. The panel runs down to the foot of the window beside the list rather than ending at the last rating, the note taking
  -- whatever the ratings leave, so the window is never shorter than the ratings and a couple of lines to write on.
  --
  local notes = KUI:CreateInset({ title = KU.NOTES_TITLE }, cf)
  notes:ClearAllPoints()
  notes:SetPoint("TOPRIGHT", right, "BOTTOMRIGHT", 0, 0)
  notes:SetPoint("BOTTOMRIGHT", btns, "TOPRIGHT", 0, 0)
  qf.notespanel = notes

  --
  -- The ratings are the grid the filter dialog draws too. The column only widens for them when they would not fit in it.
  --
  qf.lineheight = select(2, KUI:MeasureStrWidth("Wy", "GameFontNormalSmall"))

  local rowwidth = max(qf.shared.width, self:RatingGridWidth())

  right:SetWidth(rowwidth + right.rings.left + right.rings.right)
  notes:SetWidth(rowwidth + notes.rings.left + notes.rings.right)
  qf.namelabel:SetWidth(rowwidth)
  qf.ratingwidth = rowwidth

  qf.notes = self:CreateUserNotes({ prefix = "KoreUserEdit", width = rowwidth }, notes.content)
  qf.notesmin = qf.notes.minheight + notes.rings.top + notes.rings.bottom

  qf.altstop = 0 - ypos

  qf.altslabel = KUI:CreateStringLabel({
    name = "KoreUserEditAlts", x = 0, y = ypos, width = rowwidth, height = qf.lineheight * ALTS_LINES, autosize = false,
    justifyv = "TOP", font = "GameFontNormalSmall", text = "",
  }, rc)
  qf.altslabel.label:SetWordWrap(true)

  --
  -- Whatever sets the words, the box and the panel are fitted to them, so nothing has to remember to.
  --
  local settext = qf.altslabel.SetText

  qf.altslabel.SetText = function(this, text)
    settext(this, text)
    fit_detail_panel()
  end

  qf.updatebutton = KUI:CreateButton({
    text = L["Update"], enabled = false,
    tooltip = { title = "$$", text = L["TIP_USEREDIT_UPDATE"] },
  }, rc)
  qf.updatebutton:ClearAllPoints()
  qf.updatebutton:SetPoint("TOP", qf.altslabel, "BOTTOM", 0, 0 - KUI.WIDGET_GAP)
  qf.updatebutton:Catch("OnClick", function(this, evt)
    update_user()
  end)

  --
  -- The buttons that act on the users, along the foot of the window, standing the usual gap in from its left hand edge as the
  -- panel above them does, and the usual gap between them. They are all one width, BUTTON_W or wider where the words of one of
  -- them need it.
  --
  local buttons = {
    { key = "createbutton", text = L["Create"], tip = L["TIP_USEREDIT_CREATE"], click = create_user },
    { key = "renamebutton", text = L["Rename"], tip = L["TIP_USEREDIT_RENAME"], click = rename_user, off = true },
    { key = "deletebutton", text = L["Delete"], tip = L["TIP_USEREDIT_DELETE"], click = delete_user, off = true },
    { key = "guildbutton", text = L["Guild import"], tip = L["TIP_USEREDIT_GUILDIMPORT"], click = guild_import, off = true },
    { key = "filterbutton", text = L["USEREDIT_FILTER"], tip = L["TIP_USEREDIT_FILTER"], click = filter_users },
    { key = "blockedbutton", text = L["USEREDIT_BLOCKED"], tip = L["TIP_USEREDIT_BLOCKED"], click = blocked_senders },
  }

  local words = {}

  for _, b in ipairs(buttons) do
    tinsert(words, b.text)
  end

  local bw = max(BUTTON_W, KUI:WidestString(words) + 24)
  local row = MakeFrame("Frame", nil, btns)

  row:SetSize(bw * #buttons + KUI.WIDGET_GAP * (#buttons - 1), BUTTON_H)
  row:SetPoint("BOTTOMLEFT", btns, "BOTTOMLEFT", KUI.WIDGET_GAP, 0)

  local x = 0

  for _, b in ipairs(buttons) do
    local click = b.click

    qf[b.key] = KUI:CreateButton({
      x = x, y = 0, width = bw, height = BUTTON_H, text = b.text, enabled = not b.off,
      tooltip = { title = "$$", text = b.tip },
    }, row)
    qf[b.key]:Catch("OnClick", function(this, evt)
      click()
    end)
    x = x + bw + KUI.WIDGET_GAP
  end

  self.usereditwin:Catch("OnShow", function(this, evt)
    self:RefreshUserEditor()
  end)

  --
  -- However it was closed, every mod that moved out of its way is told once. Standing aside for a dialog of its own is not closing it.
  --
  KU.usereditwin:Catch("OnHide", function(this, evt)
    if (dialog_open) then
      return
    end

    for handle in pairs(stood_aside) do
      local tbl = KU.consumers[handle]

      if (tbl and tbl.ComeBack) then
        tbl:ComeBack("editor")
      end
    end

    stood_aside = {}
  end)

  --
  -- The window opens tethered or not as this character last left it. Set without throwing, the stored choice being put back rather than made again.
  --
  local tether = K.chardb.useredittether and true or false

  qf.tether:SetChecked(tether, true)
  apply_tether(tether)

  fit_detail_panel()
  sync_detail_panel()
end

--
-- Open the editor. Every registered mod is asked to stand aside first, and the ones that say they did are told to come back
-- when it closes, so this window can take a mod's own off the screen without Kore knowing that mod has windows at all. It
-- happens however the editor was reached, a mod's own button or "/kuser" typed at the chat bar, because a foyer left sitting
-- behind this window is wrong either way.
--
-- Nothing here asks whether any mod is suspended. Looking at the people is not a mod's to withhold, and a caller with a
-- reason to refuse simply does not call.
--
function KU:OpenUserEditor()
  if (not KU.usereditwin or KU.usereditwin:IsShown()) then
    return
  end

  stood_aside = {}

  for handle, tbl in pairs(KU.consumers) do
    if (tbl.StandAside and tbl:StandAside("editor")) then
      stood_aside[handle] = true
    end
  end

  KU.usereditwin:Show()
end

--
-- A command of its own, as well as whatever way each mod offers to reach it. The people belong to no mod in particular, so
-- getting at them should not mean going through one.
--
SlashCmdList["KORE_USERS"] = function(input)
  KU:OpenUserEditor()
end

_G["SLASH_KORE_USERS1"] = "/kuser"
_G["SLASH_KORE_USERS2"] = "/kusers"
_G["SLASH_KORE_USERS3"] = "/ku"
