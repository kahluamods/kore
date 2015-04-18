--[[
   KahLua Kore - core library functions for KahLua addons.
     WWW: http://kahluamod.com/kore
     SVN: http://kahluamod.com/svn/kore
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com
   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2009 James Kean Johnston. All rights reserved.

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

if (K.CurrentLocale ~= "frFR") then
  return
end

local L = K:RegisterI18NTable(KKORE_MAJOR, "deDE")
if (not L) then
  error ("KahLua Kore: impossible d'initialiser I18N.")
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
K.OK_STR = "OK"
K.CANCEL_STR = "Annuler"
K.ACCEPT_STR = "Accepter"
K.CLOSE_STR = "Fermer"
K.OPEN_STR = "Ouvrir"
K.HELP_STR = "Aide"
K.YES_STR = "Oui"
K.NO_STR = "Non"
K.KAHLUA = "KahLua"

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KKORE"] = "kkore"
L["CMD_HELP"] = "aide"
L["CMD_LIST"] = "liste"
L["CMD_DEBUG"] = "debug"
L["CMD_VERSION"] = "version"

L["KAHLUA_VER"] = "(Version %d)"
L["KAHLUA_DESC"] = "un ensemble d'améliorations de l'interface utilisateur."
L["KORE_DESC"] = "Fonctionnaliés %s du coeur, telles que le debug ou les profils."
L["Usage: %s/%s module [arg [arg...]]%s"] = "Utilisation : %s/%s module [arg [arg...]]%s"
L["    Where module is one of the following modules:"] = "    module étant l'in des modules suivants :"
L["For help with any module, type %s/%s module %s%s."] = "Pour une aide sur l'un des modules, tapez %s/%s module %s%s."
L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"] = "Utilisation de KahLua Kore : %s/%s commande [arg [arg...]]%s."
L["%s/%s %s module level%s"] = "%s/%s %s module level%s"
L["  Sets the debug level for a module. 0 disables."] = "  Définit le niveau de déboguage pour un module. 0 désactive."
L["  The higher the number the more verbose the output."] = "  Plus le nombre est grand, plus la sortie est détaillée."
L["  Lists all modules registered with KahLua."] = "  Liste tous les modules enregistrés avec KahLua."
L["The following modules are available:"] = "Les modules suivants sont disponibles :"
L["Cannot enable debugging for '%s' - no such module."] = "Impossible d'activer le déboguage pour '%s' - module inexistant."
L["Debug level %d out of bounds - must be between 0 and 10."] = "Niveau de déboguage %s hors limites - doit être compris entre 0 et 10."
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = "Module '%s' inexistant. Utilisez %s/%s %s%s pour une liste des modules disponibles."
L["KKore extensions loaded:"] = "Extensions KKore chargées :"
