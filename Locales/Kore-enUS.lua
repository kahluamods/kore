--[[
   KahLua Kore - core library functions for KahLua addons.
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

local L = LibStub("AceLocale-3.0"):NewLocale("Kore", "enUS", true)
if (not L) then
  return
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
L["OK_STR"] = "Ok"
L["CANCEL_STR"] = "Cancel"
L["ACCEPT_STR"] = "Accept"
L["CLOSE_STR"] = "Close"
L["OPEN_STR"] = "Open"
L["HELP_STR"] = "Help"
L["YES_STR"] = "Yes"
L["NO_STR"] = "No"

--
-- The save bar at the foot of a tabbed dialog, shown while a page has changes that are not saved yet.
--
L["SAVEBAR_STR"] = "Save changes on this page"
L["SAVEBAR_MSG"] = "Changes made on this page will not be permanent until you press this button. Closing the window without saving will lose all the changes."

--
-- What a choice shows when it stands for no value at all: no item, no profession, no main, no opinion. Set off with dashes so
-- that it can never be taken for a real value of the same name, a character called Nobody for one.
--
L["NONE_STR"] = "-None-"
L["NOTSET_STR"] = "-Not set-"
L["NOBODY_STR"] = "-Nobody-"
L["NOTRATED_STR"] = "-Not rated-"

L["KAHLUA"] = "KahLua"
L["DEV_STR"] = "dev"
L["error: "] = true

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KORE"] = "kore"
L["CMD_HELP"] = "help"
L["CMD_LIST"] = "list"
L["CMD_DEBUG"] = "debug"
L["CMD_VERSION"] = "version"

L["KAHLUA_VER"] = "(version %d)"
L["KAHLUA_DESC"] = "a suite of user interface enhancements."
L["KORE_DESC"] = "core %s functionality, such as debugging and profiling."
L["Usage: %s/%s module [arg [arg...]]%s"] = true
L["    Where module is one of the following modules:"] = true
L["For help with any module, type %s/%s module %s%s."] = true
L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"] = true
L["%s/%s %s module level%s"] = true
L["  Sets the debug level for a module. 0 disables."] = true
L["  The higher the number the more verbose the output."] = true
L["  Lists all modules registered with KahLua."] = true
L["The following modules are available:"] = true
L["Cannot enable debugging for '%s' - no such module."] = true
L["Debug level %d out of bounds - must be between 0 and 10."] = true
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = true
L["Kore extensions loaded:"] = true
L["Chest"] = true

-- Comms and version-check related stuff
L["Your version of %s is out of date. Please update it."] = true
L["%s communication registration failed!"] = true
L["%s: the game is refusing addon messages for now, so some were not sent."] = true
L["not sent: %s"] = true -- @debug-delete@
L["%s: an addon message from %q was corrupt."] = true
L["Shield"] = true



--
-- The people, and what is true of each of them (UserDB.lua, UserEditor.lua, UserOffers.lua).
--
L["you must specify a character name."] = true
L["%q is not a valid character name."] = true
L["user %q already exists. Try again."] = true
L["user %q does not exist. Try again."] = true
L["USER_ALT_SELF"] = "%s cannot be an alt of themselves."
L["USER_ALT_OF_ALT"] = "%s is an alt of %s, and an alt cannot have alts of their own."
L["USER_ALT_HAS_ALTS"] = "%s has alts of their own, so cannot become an alt."
L["USER_DELETE_IN_USE"] = "%s is still in use in: %s. Remove them from those first."

--
-- The user editor and the offers window, which came from Konfer with them.
--
L["Old name"] = true
L["New name"] = true
L["Users"] = true
L["Create"] = true
L["Delete"] = true
L["Rename"] = true
L["Update"] = true
L["User is an alt of"] = true
L["Guild import"] = true
L["user %q created."] = true
L["user %q deleted."] = true
L["Delete user"] = true
L["User: %s"] = true
L["Rename user"] = true
L["added %d user(s)."] = true
L["USEREDIT_TITLE"] = "Users"
L["USEREDIT_SEARCH"] = "Search"
L["USEREDIT_TETHER"] = "Tethered alts"
L["TIP_USEREDIT_TETHER"] = "List each main with their alts under them, instead of everybody on their own. Searching then finds a main and all of their alts whenever any one of them matches."
L["TIP_USEREDIT_SEARCH"] = "Type any part of a name, realm, class or profession to narrow the list. Every word you type has to match, so \"mage tailor\" finds mages who are tailors. A main's name finds their alts as well."
L["USEREDIT_COUNT"] = "%d users"
L["USEREDIT_COUNT_ONE"] = "%d user"
L["USEREDIT_COL_NAME"] = "Name"
L["USEREDIT_COL_CLASS"] = "Class"
L["USEREDIT_COL_MSSPEC"] = "Main spec"
L["USEREDIT_COL_OSSPEC"] = "Off spec"
L["USEREDIT_COL_PROF1"] = "Profession 1"
L["USEREDIT_COL_PROF2"] = "Profession 2"
L["USEREDIT_COL_MAIN"] = "Alt of"
L["USEREDIT_ALTS"] = "Alts: %s"
L["USEREDIT_NOALTS"] = "No alts"
L["USER_SHARED_INFO"] = "Shared Info"
L["USEREDIT_NOTES"] = "Private notes / ratings"
L["USEREDIT_RATING"] = "Skill Rating"
L["USEREDIT_NOTE"] = "Your notes"
L["TIP_USEREDIT_NOTE"] = "Anything you want to remember about this character, in your own words. Your notes are yours alone. They are never sent to anybody, and are saved as you type."
L["USEREDIT_FILTER"] = "Filter"
L["USEREDIT_FILTER_TITLE"] = "Filter Users"
L["USEREDIT_FILTER_TEXT"] = "Filter the user list to display only users with the following ratings or higher."
L["USEREDIT_CLEAR"] = "Clear"
L["USEREDIT_FILTER_UNRATED"] = "Include %s"
L["TIP_USEREDIT_FILTER_UNRATED"] = "Also list users you have not rated at all at something the filter asks for, as if they met it."
L["TIP_USEREDIT_FILTER"] = "Show only the users you have rated at least as highly as you choose. While a filter is on, the count at the top of the list shows how many are shown of how many there are."
L["TIP_USEREDIT_FILTER_RATING"] = "List only users you have rated at least this highly for this, or %s to leave it out of the filter."
L["TIP_USEREDIT_GUILDIMPORT"] = "Add members of your guild as users. They are not added to any configuration."
L["TIP_USEREDIT_RATING"] ="How good you think this character is at this, or %s. Your ratings are yours alone. They are never sent to anybody, and are saved as soon as you choose one."
L["TIP_USEREDIT_UPDATE"] = "Save the changes to this character. They apply in every configuration the character is in."
L["TIP_USEREDIT_CREATE"] = "Add a character Konfer does not know yet. They are not added to any configuration."
L["TIP_USEREDIT_RENAME"] = "Give the selected character their new name after a paid name change. Every configuration they are in follows."
L["TIP_USEREDIT_DELETE"] = "Forget the selected character entirely. This is only possible once no configuration has them as a user."
L["USEREDIT_DELMSG"] = "Forget everything Konfer knows about this character? Their class, specs, professions and alt links will be lost, and so will your own notes and ratings of them. No configuration uses them, so no roll list changes."
L["USEROFFER_TITLE"] = "Changes to your records"
L["USEROFFER_FROM"] = "Broadcast from %s"
L["USEROFFER_BLURB"] = "This user broadcast information that changes stored facts about users. If you trust the source you can accept the broadcast or you can exclude specific entries."
L["USEROFFER_ALL"] = "Everybody"
L["TIP_USEROFFER_ALL"] = "Tick or untick every character in the list."
L["USEROFFER_COL_WHO"] = "Character"
L["USEROFFER_COL_WHAT"] = "What"
L["USEROFFER_COL_NOW"] = "You have"
L["USEROFFER_COL_OFFERED"] = "Sent"
L["USEROFFER_BLOCK"] = "Block sender"
L["TIP_USEROFFER_BLOCK"] = "Throw this away and ignore everything this player broadcasts from now on. Blocked players are listed in the user editor, where you can let them back in."
L["USEREDIT_BLOCKED"] = "Blocked"
L["TIP_USEREDIT_BLOCKED"] = "The players whose broadcasts you ignore."
L["USEREDIT_BLOCKED_TITLE"] = "Blocked senders"
L["USEREDIT_BLOCK"] = "Block"
L["TIP_USEREDIT_BLOCK"] = "Ignore everything this player broadcasts."
L["TIP_USEREDIT_BLOCKED_NAME"] = "The name of the player to ignore. A name with no realm in it is somebody on your own realm."
L["USEREDIT_UNBLOCK"] = "Unblock"
L["TIP_USEREDIT_UNBLOCK"] = "Listen to this player's broadcasts again."
L["USEREDIT_LEVEL"] = "Level %s"

-- The roles a player raids in (K.RoleName).
L["Healer"] = true
L["Melee DPS"] = true
L["Ranged DPS"] = true
L["Caster DPS"] = true
L["Tank"] = true

--
-- The widgets a person is picked and edited with (UserUI.lua).
--
L["User role"] = true
L["TIP071"] = "Select the role the user plays in the raid / guild. This is used to set filters to restrict bidders to users who fulfill a certain role, in the case where an item may be useful to more than one type of player. For example you may decide that an item is better for healers, even though caster DPS may want it too."
L["Off spec"] = true
L["Main spec"] = true
L["Main / off spec"] = true
L["TIP109"] = "This user's off spec. An item restricted to a role only takes an off spec roll from users whose off spec plays that role. Leave this as %s if they have no off spec."
L["TIP108"] = "This user's main spec. An item restricted to a role only takes a main spec bid or roll from users whose main spec plays that role."
L["User class"] = true
L["Class"] = true
L["Race"] = true
L["Level"] = true
L["TIP073"] = "Select the user's class. You must assign their class and it must be accurate, as it affects the class filters."
L["Second profession"] = true
L["Profession"] = true
L["First profession"] = true
L["Professions"] = true
L["TIP105"] = "The second of this user's two crafting professions. Leave this as %s if they have only learned one."
L["TIP104"] = "The first of this user's two crafting professions. This is recorded so that you know who in the raid can make what, and it is separate from the raid enchanter setting above, which says who receives items to be disenchanted."
L["TIP_USEREDIT_MAIN"] = "The character this one is an alt of, or %s if they are a main. Only characters who are not alts themselves are offered, and a character with alts of their own cannot become one."
L["Create user"] = true
L["Name"] = true
L["TIP072"] = "Enter the user's name. This must be an exact match for their character name."
L["you must set a user class."] = true
L["Import guild users"] = true
L["Minimum level"] = true
L["TIP074"] = "Select the minimum level to accept for users. Any guild members below this level will not be imported."

--
-- The Skill Rating grid, whose keys are built from RATE_ROWS and RATINGS (see UserEditor.lua).
--
L["USEREDIT_RATE_HEALER"] = "As a healer"
L["USEREDIT_RATE_TANK"] = "As a tank"
L["USEREDIT_RATE_MELEE"] = "As melee"
L["USEREDIT_RATE_RANGED"] = "As ranged"
L["USEREDIT_RATE_ETIQUETTE"] = "Group etiquette"
L["USEREDIT_RATE_KNOWLEDGE"] = "Knowledge"
L["USEREDIT_RATE_HELPFUL"] = "Helpfulness"
L["USEREDIT_RATING_TERRIBLE"] = "Terrible - avoid"
L["USEREDIT_RATING_BIND"] = "Only in a bind"
L["USEREDIT_RATING_ORDINARY"] = "Nothing special"
L["USEREDIT_RATING_ABOVE"] = "Better than average"
L["USEREDIT_RATING_GOOD"] = "Good"
L["USEREDIT_RATING_EXCELLENT"] = "Excellent"
