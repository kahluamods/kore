--[[
   KahLua Kore - useful simple dialogs
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
assert(K, "Kore Dialogs requires Kore")
assert(tonumber(KM) >= 1, "Kore Dialogs requires Kore r1 or later")

local KUI, KM = LibStub:GetLibrary("KoreUI")
assert(KUI, "Kore Dialogs requires KoreUI")
assert(tonumber(KM) >= 1, "Kore Dialogs requires KoreUI r1 or later")

local L = LibStub("AceLocale-3.0"):GetLocale("Kore")

-- Local aliases for global or LUA library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tsort = table.sort
local tostring = tostring
local GetTime = GetTime
local min = math.min
local max = math.max
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local xpcall, pcall = xpcall, pcall
local pairs, next, type = pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local printf = K.printf
local MakeFrame= KUI.MakeFrame

local ucolor = K.ucolor
local ecolor = K.ecolor
local icolor = K.icolor

--
-- The plate for one of these, which every one of them wears so that no caller can forget it.
--
-- TTXT is what the dialog is about. A string is plated as KMOD's own window would be. A table is { text, owner }, and the
-- owner is whoever the dialog really belongs to where that is not KMOD itself: a mod acting on one of its policy's things
-- says so, and gets that policy's plate rather than its own.
--
-- The owner travels with the title rather than as an argument of its own, because it is a fact about the title. KMOD stays
-- what it always was, the table the dialog is kept on and the one handed back to the caller's function, and those are
-- emphatically not the same question -- a policy has none of the methods such a function calls.
--
local function dialog_plate(kmod, ttxt)
  if (type(ttxt) == "table") then
    return (ttxt.owner or kmod):WindowTitle(ttxt.text)
  end

  return kmod:WindowTitle(ttxt)
end

--
-- What a confirmation or rename dialog is about, a line of words centred at its top. VAL is the thing itself, shown in
-- white, or { fmt, thing } to set it in words of the caller's, "Current list: %s", with the thing in white and the words in
-- the font's own colour.
--
local function subject_text(val)
  if (type(val) == "table") then
    return strfmt(val[1], K.white(val[2]))
  end

  return K.white(val or "")
end

--
-- WIN, here and in K.RenameDialog, is the window the dialog stands in for: hidden while the dialog is up and shown again
-- when it closes. Nil leaves every window as it is. A mod may have many windows, so which one is the caller's to say.
--
function K.ConfirmationDialog(kmod, ttxt, msg, val, func, farg, win, height, option, xtras)
  local height = height or 240
  local confirmdlg = kmod.confirmdialog

  if (not confirmdlg) then
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KoreConfirmDialog",
      title = "",
      border = true,
      width = 450,
      height = height,
      canmove = true,
      canresize = false,
      --
      -- Escape cancels. A confirmation always has a safe answer, which is the one that does nothing, and Escape is the key
      -- every other window in the game gives up on. A dialog that cannot be dismissed that way reads as stuck.
      --
      escclose = true,
      blackbg = true,
      okbutton = true,
      cancelbutton = true,
    }
    if (xtras and type(xtras) == "table") then
      for k,v in pairs(xtras) do
        arg[k] = v
      end
    end

    local ret = KUI:CreateDialogFrame(arg)

    arg = { x = "CENTER", y = -4, font = "GameFontNormal", text = "" }
    ret.str1 = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = 8, y = -35, width = 410, height = height - 95 - (option and 24 or 0),
      autosize = false,
      color = {r = 1, g = 0, b = 0, a = 1 }, text = "",
      font = "GameFontNormal", justifyv = "TOP",
    }
    ret.str2 = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = "CENTER", y = -height + 85, label = { text = ""},
    }
    ret.opt = KUI:CreateCheckBox(arg, ret)
    ret.optval = false
    ret.opt:Catch("OnValueChanged", function(this, evt, val)
      ret.optval = val
    end)

    ret.OnAccept = function(this)
      local tcd = this.kmod.confirmdialog

      tcd:Hide()
      tcd.runfunction(this.kmod, tcd.arg, tcd.optval)
    end

    --
    -- The window stood in for comes back however the dialog is closed. Escape hides a dialog without throwing OnCancel, and
    -- hiding one throws OnHide whatever did it.
    --
    ret:Catch("OnHide", function(this, evt)
      local win = this.win

      this.win = nil
      if (win) then
        win:Show()
      end
    end)

    ret.kmod = kmod
    kmod.confirmdialog = ret
    confirmdlg = kmod.confirmdialog
  end

  confirmdlg:SetHeight(height)
  confirmdlg.str2:SetHeight(height - 95 - (option and 24 or 0))
  confirmdlg.opt:SetPoint("TOP", confirmdlg, "BOTTOM", 0, 56)
  if (option) then
    confirmdlg.opt:SetText(option)
    confirmdlg.opt:Show()
    confirmdlg.optval = false
    confirmdlg.opt:SetChecked(false)
  else
    confirmdlg.opt:Hide()
  end
  -- The plate names whoever the dialog belongs to, mod or policy, so a caller passes only what it is about. See dialog_plate.
  confirmdlg:SetTitleText(dialog_plate(kmod, ttxt))
  confirmdlg.str1:SetText(subject_text(val))
  confirmdlg.str2:SetText(msg)
  confirmdlg.runfunction = func
  confirmdlg.arg = farg
  confirmdlg.win = win

  if (win) then
    win:Hide()
  end
  confirmdlg:Show()
end

--
-- SUBJECT is what is being renamed, in the same form a confirmation's VAL takes, NEWLBL the words beside the box the new
-- name is typed into.
--
function K.RenameDialog(kmod, ttxt, subject, newlbl, len, func, farg, win, xtras)
  local renamedlg = kmod.renamedialog

  if (not renamedlg) then
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KoreRenameDialog",
      title = "",
      border = true,
      width = 450,
      height = 125,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = true,
      cancelbutton = true,
    }
    if (xtras and type(xtras) == "table") then
      for k,v in pairs(xtras) do
        arg[k] = v
      end
    end

    local ret = KUI:CreateDialogFrame(arg)

    arg = { x = "CENTER", y = 0, font = "GameFontNormal", text = "" }
    ret.str1 = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = 0, y = -30, width = 150, height = 24, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal", text = "",
    }
    ret.str3 = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = 0, y = -30, width = 200, height = 20,
    }
    ret.input = KUI:CreateEditBox(arg, ret)
    ret.input:SetFocus()

    ret.input:ClearAllPoints()
    ret.input:SetPoint("TOPLEFT", ret.str3, "TOPRIGHT", 12, 0)

    ret.OnAccept = function(this)
      local trd = this.kmod.renamedialog
      local rv = trd.runfunction(trd.input:GetText(), trd.arg, true)
      if (rv) then
        trd:Show()
        trd.input:SetFocus()
      else
        trd:Hide()
      end
    end

    -- As for K.ConfirmationDialog, the window comes back however the dialog is closed, Escape included.
    ret:Catch("OnHide", function(this, evt)
      local win = this.win

      this.win = nil
      if (win) then
        win:Show()
      end
    end)
    ret.input.OnEnterPressed = function(this)
      local tp = this:GetParent():GetParent()
      tp.OnAccept(tp)
    end

    ret.kmod = kmod
    kmod.renamedialog = ret
    renamedlg = kmod.renamedialog
  end

  -- As the confirmation dialog's above.
  renamedlg:SetTitleText(dialog_plate(kmod, ttxt))
  renamedlg.str1:SetText(subject_text(subject))
  renamedlg.str3:SetText(newlbl)
  renamedlg.input:SetMaxLetters(len)
  renamedlg.runfunction = func
  renamedlg.arg = farg
  renamedlg.win = win

  if (win) then
    win:Hide()
  end
  renamedlg:Show()
  renamedlg.input:SetText("")
  renamedlg.input:SetFocus()
end

function K.PopupSelectionList(kmod, name, list, title, width, height, parent, itemheight, func, topspace, botspace, xtras)
  if (kmod.popupwindow) then
    kmod.popupwindow:Hide()
    kmod.popupwindow = nil
  end

  assert(name)

  local arg = {
    name = name,
    itemheight = itemheight,
    width = width,
    height = height,
    header = topspace,
    footer = botspace,
    -- No title, no plaque. An empty one reads as something missing, and a dialog without one is dragged by its top edge.
    title = title and { text = title, width = width - 50 } or nil,
    canmove = true,
    canresize = "HEIGHT",
    escclose = true,
    blackbg = true,
    xbutton = false,
    level = 32,
    border = "THICK",
    x = "CENTER",
    y = "MIDDLE",
    func = function(lst, idx, arg)
      func(lst[idx].value)
    end,
    timeout = 3,
  }
  if (xtras and type(xtras) == "table") then
    for k,v in pairs(xtras) do
      arg[k] = v
    end
  end

  local rv = KUI:CreatePopupList(arg, parent)
  assert(rv)
  rv.kmod = kmod

  rv:UpdateList(list)
  rv:Show()

  return rv
end

function K.SingleStringInputDialog(kmod, name, title, text, width, height, xtras)
  local arg = {
    x = "CENTER", y = "MIDDLE",
    name = name,
    -- The plate names whoever raised this, as the confirmation and rename dialogs above do. See K.WindowTitle.
    title = dialog_plate(kmod, title),
    border = "THICK",
    width = width,
    height = height,
    canmove = true,
    canresize = false,
    escclose = true,
    xbutton = false,
    blackbg = true,
    okbutton = true,
    cancelbutton = true,
  }
  if (xtras and type(xtras) == "table") then
    for k,v in pairs(xtras) do
      arg[k] = v
    end
  end

  local ret = KUI:CreateDialogFrame(arg)
  assert(ret)
  ret.kmod = kmod

  arg = {
    x = 8, y = 0, width = width - 40, height = height - 90, autosize = false,
    font = "GameFontNormal", text = text, }
  ret.str1 = KUI:CreateStringLabel(arg, ret)

  arg = { x = "CENTER", y = -(height - 85), len = 32 }
  ret.ebox = KUI:CreateEditBox(arg, ret)

  ret.ebox:SetFocus()

  return ret, ret.ebox
end
