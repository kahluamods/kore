--[[
   KahLua Kore - what another client would change about the people we know.
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
assert(KUI, "Kore UserOffers requires KoreUI")
assert(tonumber(KM) >= 1, "Kore UserOffers requires KoreUI r1 or later")

local L = LibStub("AceLocale-3.0"):GetLocale("Kore")

local KU = K.Users

local tinsert = table.insert
local tremove = table.remove
local strfmt = string.format
local ceil = math.ceil
local ipairs, next = ipairs, next

local USER_ALTOF = KU.USER_ALTOF
local USER_ALTS = KU.USER_ALTS

--
-- What somebody else would have us believe about the people we know. A broadcast is one admin's whole picture of a config and
-- of everybody in it, and what it says about a character is very often righter than what we hold, having been checked against
-- the characters themselves. It is still not ours to be told: a person's own record is each player's, so what a broadcast
-- would change is put to them here, user by user, and what they do not want simply does not happen.
--
-- A refusal is not remembered. The comparison is always against what is stored, so the next broadcast asks again, which is
-- what anybody who changed their mind would expect. Somebody who will not take no for an answer is blocked outright instead,
-- in K.frdb.blockedsenders, and then nothing they broadcast is even unpacked.
--
-- Each batch is one question with one source, so they queue rather than run together: whoever answers the one on screen is
-- shown the next. A user is a single tick covering every change to them, because "is this person's record right" is the
-- question being asked and picking one field out of it and not another answers nothing.
--
-- What is asked about is the facts the game itself can prove, those being the ones a sender can be honestly wrong about. An
-- alt link is never asked about. It is a fact about the human behind two characters, said by whoever administers the
-- configurations they are in, and one arriving is written straight through KU:SetMain.
--

local OFFERWIN_WIDTH = 600
local OFFERWIN_HEIGHT = 420
local OFFER_COL_W = 120

--
-- A row is its tick and the standard gap, so that the ticks down the column stand apart from one another the way any other
-- column of boxes does. The tick is then in the middle of a row taller than it is.
--
local OFFER_ROW_H = KUI.CHECKBOX_SIZE + KUI.WIDGET_GAP
local OFFER_TICK_Y = 0 - ceil((OFFER_ROW_H - KUI.CHECKBOX_SIZE) / 2)

local offerwin
local batches = {}
local rows = {}

--
-- The window interrupts whatever a mod has up rather than sitting over it, so every registered mod is asked to stand aside
-- as it opens (KU:RegisterConsumer, "offers"), and the ones that did are told to come back once the last batch has been
-- answered, accepted, refused or closed. Between one batch and the next nothing comes back.
--
local stood_aside = {}

-- Adding to whoever already stood aside, a batch arriving in the moment between two others being the window opening again.
local function stand_aside()
  for handle, tbl in pairs(KU.consumers) do
    if (tbl.StandAside and tbl:StandAside("offers")) then
      stood_aside[handle] = true
    end
  end
end

local function come_back()
  local was = stood_aside

  stood_aside = {}

  for handle in pairs(was) do
    local tbl = KU.consumers[handle]

    if (tbl and tbl.ComeBack) then
      tbl:ComeBack("offers")
    end
  end
end

--
-- The batch on screen, and the rows the list draws for it. A user is one row carrying every change to them and the tick that
-- decides whether they happen, and the changes after the first get a row each under it, with no tick of their own.
--
-- The first change shares the user's own row rather than starting a new one, because a name on a line by itself with the one
-- thing being said about it on the line below reads as two people, and very nearly every offer is a single change.
--
local function build_rows()
  local batch = batches[1]

  rows = {}

  if (not batch) then
    return
  end

  local bykuid = {}
  local order = {}

  for k, v in ipairs(batch.changes) do
    if (not bykuid[v.kuid]) then
      bykuid[v.kuid] = { kuid = v.kuid, who = KU:String(v.kuid), ticked = true, changes = {} }
      tinsert(order, bykuid[v.kuid])
    end

    tinsert(bykuid[v.kuid].changes, v)
  end

  for k, user in ipairs(order) do
    for i, change in ipairs(user.changes) do
      if (i == 1) then
        user.what = change.what
        user.now = change.now
        user.offered = change.offered
        tinsert(rows, user)
      else
        tinsert(rows, { user = user, what = change.what, now = change.now, offered = change.offered })
      end
    end
  end
end

local function refresh_rows()
  if (not offerwin) then
    return
  end

  offerwin.list:UpdateList(#rows)
end

--
-- The tick at the head of the column is only true while every user in the list is ticked, so it follows them as they are
-- ticked one at a time. Set without throwing, this being what the rows already say rather than anything the player clicked.
--
local function sync_header_tick()
  local all = true

  for k, row in ipairs(rows) do
    if (row.changes and not row.ticked) then
      all = false
      break
    end
  end

  offerwin.list:ColumnWidget("tick"):SetChecked(all, true)
end

--
-- Everything the player left ticked, applied. A change knows how to make itself where making it is more than writing a value,
-- which is what the personal alt link below wants, and otherwise the value is one KU:UserFactChanges already worked out
-- this client would store.
--
local function apply_batch()
  local any = false

  for k, row in ipairs(rows) do
    if (row.ticked) then
      for i, change in ipairs(row.changes) do
        if (change.apply) then
          change.apply()
        else
          -- By KUID, so that a rename while the offer waited still finds who it is about.
          local rec = KU:Record(change.kuid)

          if (rec) then
            rec[change.slot] = change.value
          end
        end

        any = true
      end
    end
  end

  if (any) then
    KU:UserLinksChanged()
  end
end

--
-- Draw the batch at the front of the queue.
--
local function show_batch()
  build_rows()
  local skuid = KU:Find(batches[1].sender)

  -- Whoever sent it, who need be nobody the mod knows, and is in class colour only when they are.
  offerwin.source:SetText(strfmt(L["USEROFFER_FROM"], skuid and KU:String(skuid) or K.DisplayName(batches[1].sender or "")))
  offerwin.blockbutton:SetShown(batches[1].sender and true or false)
  sync_header_tick()
  refresh_rows()
end

--
-- Show the next batch, or close, there being nothing left to ask.
--
local function next_batch()
  tremove(batches, 1)

  if (not next(batches)) then
    offerwin:Hide()
    return
  end

  show_batch()
end

local function create_offer_window()
  local win = KUI:CreateDialogFrame({
    x = "CENTER", y = "MIDDLE", name = "KoreUserOffersWin", title = KU:WindowTitle(L["USEROFFER_TITLE"]), border = true,
    width = OFFERWIN_WIDTH, height = OFFERWIN_HEIGHT, canmove = true, canresize = false, escclose = true, xbutton = true,
    padding = KUI.WIDGET_GAP, okbutton = true, cancelbutton = true,
  })

  local ypos = 0
  local cw = win.content:GetWidth()

  win.source = KUI:CreateStringLabel({ x = 0, y = ypos, width = cw, autosize = false, font = "GameFontNormal",
    text = "" }, win)
  ypos = ypos - win.source:GetHeight() - KUI.WIDGET_GAP

  win.blurb = KUI:CreateStringLabel({ x = 0, y = ypos, width = cw, autosize = false, justifyv = "TOP",
    text = L["USEROFFER_BLURB"] }, win)
  win.blurb.label:SetWordWrap(true)

  local bh = ceil(win.blurb.label:GetStringHeight()) + win.blurb.xtraheight

  win.blurb:SetHeight(bh)
  ypos = ypos - bh - KUI.WIDGET_GAP

  --
  -- No padding of its own: this panel is against the dialog's walls on three sides, and the dialog's own padding is already
  -- the gap. A panel keeps that ring so that it stands clear of a neighbour, and here the only neighbour is the blurb above.
  --
  local panel = KUI:CreateInset({ padding = 0 }, win)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, ypos)
  panel:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", 0, 0)

  --
  -- The tick has a column of its own so that the box never sits over anybody's name, and so that a change under a user, which
  -- has no tick, leaves the space its user's tick is drawn in. The one that answers for everybody is that column's heading,
  -- standing at the top of the ticks it sets rather than off to one side of them.
  --
  win.list = KUI:CreateColumnList({
    name = "KoreUserOffersList",
    itemheight = OFFER_ROW_H,
    columns = {
      { key = "tick", width = KUI.CHECKBOX_SIZE + KUI.WIDGET_GAP,
        header = { checked = true, tooltip = { title = L["USEROFFER_ALL"], text = L["TIP_USEROFFER_ALL"] },
          changed = function(list, onoff)
            for k, row in ipairs(rows) do
              if (row.changes) then
                row.ticked = onoff and true or false
              end
            end

            refresh_rows()
          end } },
      { key = "who", text = L["USEROFFER_COL_WHO"], width = "fill" },
      { key = "what", text = L["USEROFFER_COL_WHAT"], width = OFFER_COL_W },
      { key = "now", text = L["USEROFFER_COL_NOW"], width = OFFER_COL_W },
      { key = "offered", text = L["USEROFFER_COL_OFFERED"], width = OFFER_COL_W },
    },
    setitem = function(objp, idx, slot, row)
      local r = rows[idx]

      row:SetCell("tick", "")
      row:SetCell("who", r.who or "")
      row:SetCell("what", r.what or "")
      row:SetCell("now", r.now or "")
      row:SetCell("offered", r.offered or "")

      --
      -- The tick belongs to the user, so a change under one has none of its own. It is set without throwing, rows being
      -- reused as the list scrolls, and only a click of the player's writes anything back.
      --
      row.tick:SetShown(r.changes and true or false)
      row.tick.row = r
      row.tick:SetChecked(r.ticked and true or false, true)
    end,
    newrow = function(objp, row, num)
      row.tick = KUI:CreateCheckBox({ x = 0, y = OFFER_TICK_Y, checked = true }, row)
      row.tick:Catch("OnValueChanged", function(this, evt, onoff, user)
        if (user and this.row) then
          this.row.ticked = onoff and true or false
          sync_header_tick()
        end
      end)
    end,
  }, panel.content)

  --
  -- Blocking is the answer to somebody who will not stop, so it is offered where they are being a nuisance rather than only
  -- in the user editor. Everything of theirs still waiting goes with them, and nothing they sent is applied. It stands in
  -- the bottom left corner, as far in from it as Cancel stands from the bottom right, apart from the answers to the batch.
  --
  win.blockbutton = KUI:CreateButton({ width = 150, text = L["USEROFFER_BLOCK"],
    tooltip = { title = "$$", text = L["TIP_USEROFFER_BLOCK"] } }, win)

  local _, _, _, cx, cy = win.cancelbutton:GetPoint(1)

  win.blockbutton:ClearAllPoints()
  win.blockbutton:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0 - cx, cy)
  win.blockbutton:Catch("OnClick", function(this, evt)
    local sender = batches[1] and batches[1].sender

    if (not sender) then
      return
    end

    KU:SetSenderBlocked(sender, true)
    KU:RefreshUserEditor()

    for i = #batches, 1, -1 do
      if (batches[i].sender == sender) then
        tremove(batches, i)
      end
    end

    if (not next(batches)) then
      win:Hide()
      return
    end

    show_batch()
  end)

  win.OnAccept = function(this)
    apply_batch()
    next_batch()
  end

  win.OnCancel = function(this)
    next_batch()
  end

  --
  -- However the window is closed, and Escape and the corner button both close it without throwing OnCancel, the batch on
  -- screen has been answered and the next one takes its place. Closing it is a refusal like any other, and a refusal is not
  -- remembered, so the same broadcast asks again. Leaving the batch at the head of the queue instead meant the window came
  -- back on a question already dismissed, and the queue could only ever be drained with the two buttons.
  --
  -- The one left is put up on a timer rather than from in here, so that showing a window is not something that happens
  -- part way through hiding it. The two buttons take the ordinary path, the batch they answered having already gone by the
  -- time anything hides, and only hide the window once there is nothing left. However the last one went, whatever was put
  -- away for the window comes back.
  --
  win:Catch("OnHide", function(this, evt)
    if (next(batches)) then
      tremove(batches, 1)
    end

    if (not next(batches)) then
      come_back()
      return
    end

    K:ScheduleTimer(function()
      if (next(batches)) then
        show_batch()
        offerwin:Show()
      else
        come_back()
      end
    end, 0)
  end)

  return win
end

--
-- Put a batch of changes to the player. SENDER is the canonical name of whoever said so, which is who the window names and
-- who the Block button here blocks, and CHANGES is an array of
--   kuid      the KUID of the user it is about
--   what      the field, in words
--   now       what we hold, in words
--   offered   what the sender says, in words
--   slot      the USER_ slot to write, and VALUE what to write to it
--   apply     called instead, for a change that is more than writing a value
--
function KU:OfferUserChanges(sender, changes)
  if (not next(changes)) then
    return
  end

  offerwin = offerwin or create_offer_window()

  --
  -- Anything from the same person as the batch behind joins it rather than queueing behind it, which is what turns the forty
  -- events a character info check sets off into one question instead of forty. The batch on screen is left alone, being one
  -- the player is already answering.
  --
  local last = batches[#batches]
  local onscreen = offerwin:IsShown() and #batches == 1

  if (last and last.sender == sender and not onscreen) then
    for k, v in ipairs(changes) do
      tinsert(last.changes, v)
    end

    return
  end

  tinsert(batches, { sender = sender, changes = changes })

  if (offerwin:IsShown()) then
    return
  end

  stand_aside()
  show_batch()
  offerwin:Show()
end
