--[[
   KahLua Kore - core library functions for KahLua addons.
     WWW: http://kahluamod.com/kore
     Git: https://github.com/kahluamods/kore
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com
   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2018 James Kean Johnston. All rights reserved.

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

local KKORE_MAJOR = "KKore"
local K = LibStub:GetLibrary(KKORE_MAJOR)

if (not K) then
  return
end

if (K.CurrentLocale ~= "ruRU") then
  return
end

local L = K:RegisterI18NTable(KKORE_MAJOR, "ruRU")
if (not L) then
  error ("KahLua Kore: could not initialize I18N.")
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
K.OK_STR = "Ok"
K.CANCEL_STR = "Отмена"
K.ACCEPT_STR = "Принять"
K.CLOSE_STR = "Закрыть"
K.OPEN_STR = "Открыть"
K.HELP_STR = "Помощь"
K.YES_STR = "Да"
K.NO_STR = "Нет"
K.KAHLUA = "KahLua"

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KKORE"] = "kkore"
L["CMD_HELP"] = "help"
L["CMD_LIST"] = "list"
L["CMD_DEBUG"] = "debug"
L["CMD_VERSION"] = "version"

L["KAHLUA_VER"] = "(версия %d)"
L["KAHLUA_DESC"] = "комплекс усовершенствований UI."
L["KORE_DESC"] = "основные %s функции, такие как отладка и профили."
L["Usage: %s/%s module [arg [arg...]]%s"] = "Использование: %s/%s модуль [arg [arg...]]%s"
L["    Where module is one of the following modules:"] = "    Где модуль один из следующих:"
L["For help with any module, type %s/%s module %s%s."] = "Для помощи по любому из модулей наберите %s/%s модуль %s%s."
L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"] = "KahLua Kore использование: %s/%s команда [arg [arg...]]%s."
L["%s/%s %s module level%s"] = "%s/%s %s уровень модуля %s"
L["  Sets the debug level for a module. 0 disables."] = "  Задайте уровень отладки для модуля. 0 отключить."
L["  The higher the number the more verbose the output."] = "  Чем выше число, тем более подробный вывод."
L["  Lists all modules registered with KahLua."] = "  Список всех модулей, зерегистрированных в KahLua."
L["The following modules are available:"] = "Доступны следующие модули:"
L["Cannot enable debugging for '%s' - no such module."] = "Не могу включить отладку для '%s' - модуль не существует."
L["Debug level %d out of bounds - must be between 0 and 10."] = "Уровень отладки %d вне диапазона - должен быть от 0 до 10."
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = "Модуль '%s' не существует. Используйте %s/%s %s%s для отображения списка доступных модулей."
L["KKore extensions loaded:"] = "KKore расширения загружены:"
L["Chest"] = true
