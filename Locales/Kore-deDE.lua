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

local L = LibStub("AceLocale-3.0"):NewLocale("Kore", "deDE")
if (not L) then
  return
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
L["OK_STR"] = "Ok"
L["CANCEL_STR"] = "Abbrechen"
L["ACCEPT_STR"] = "Akzeptieren"
L["CLOSE_STR"] = "Schließen"
L["OPEN_STR"] = "\195\150ffnen"
L["HELP_STR"] = "Hilfe"
L["YES_STR"] = "Ja"
L["NO_STR"] = "Nein"
L["SAVEBAR_STR"] = "\195\132nderungen auf dieser Seite speichern"
L["SAVEBAR_MSG"] = "\195\132nderungen auf dieser Seite werden erst dauerhaft, wenn du diesen Knopf dr\195\188ckst. Wird das Fenster ohne Speichern geschlossen, gehen alle \195\132nderungen verloren."
L["NONE_STR"] = "-Keine-"
L["NOTSET_STR"] = "-Nicht festgelegt-"
L["NOBODY_STR"] = "-Niemand-"
L["NOTRATED_STR"] = "-Nicht bewertet-"
L["KAHLUA"] = "KahLua"
L["DEV_STR"] = "dev"
L["error: "] = "Fehler: "

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KORE"] = "kore"
L["CMD_HELP"] = "hilfe"
L["CMD_LIST"] = "list"
L["CMD_DEBUG"] = "debug"
L["CMD_VERSION"] = "version"

L["KAHLUA_VER"] = "(Version %d)"
L["KAHLUA_DESC"] = "eine Sammlung von User Interface Verbesserungen."
L["KORE_DESC"] = "Core %s Funktionalit\195\164t, wie z. B. Debugging und Profiling."
L["Usage: %s/%s module [arg [arg...]]%s"] = "Benutzung: %s/%s Modul [arg [arg...]]%s"
L["    Where module is one of the following modules:"] = "    Wo das Modul eines der folgenden ist:"
L["For help with any module, type %s/%s module %s%s."] = "Für Hilfe mit einem der Module, tippe %s/%s Modul %s%s."
L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"] = "KahLua Kore Benutzung: %s/%s Kommando [arg [arg...]]%s."
L["%s/%s %s module level%s"] = "%s/%s %s Modul level%s"
L["  Sets the debug level for a module. 0 disables."] = "  Setzt das Debug Level für ein Modul. 0 Deaktiviert es."
L["  The higher the number the more verbose the output."] = "  Je höher die Zahl, desto ausführlicher ist die Ausgabe."
L["  Lists all modules registered with KahLua."] = "  Listet alle Module die mit KahLua registriert sind auf."
L["The following modules are available:"] = "Die folgenden Module sind verfügbar:"
L["Cannot enable debugging for '%s' - no such module."] = "Kann das debuggen für '%s' nicht aktivieren - dieses Modul existiert nicht."
L["Debug level %d out of bounds - must be between 0 and 10."] = "Debug Level %d ist außerhalb des Rahmens - es muss zwischen 0 und 10 liegen."
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = "Modul '%s' existiert nicht. Benutze %s/%s %s%s für eine Liste aller verfügbarer Module."
L["Kore extensions loaded:"] = "Kore Erweiterungen geladen:"
L["Chest"] = true

L["Your version of %s is out of date. Please update it."] = "Deine Version von %s ist nicht aktuell. Bitte aktualisiere sie."
L["%s communication registration failed!"] = "%s Kommunikationsregistrierung fehlgeschlagen!"
L["%s: the game is refusing addon messages for now, so some were not sent."] = "%s: Das Spiel lehnt Addon-Nachrichten im Moment ab, daher wurden einige nicht gesendet."
L["not sent: %s"] = "nicht gesendet: %s" -- @debug-delete@
L["%s: an addon message from %q was corrupt."] = "%s: Eine Addon-Nachricht von %q war besch\195\164digt."
L["Shield"] = true



L["you must specify a character name."] = "Du musst einen Charakternamen festlegen."
L["%q is not a valid character name."] = "%q ist kein g\195\188ltiger Charaktername."
L["user %q already exists. Try again."] = "Nutzer %q existiert bereits. Versuche es nochmal."
L["user %q does not exist. Try again."] = "Nutzer %q existiert nicht. Versuche es nochmal."
L["USER_ALT_SELF"] = "%s kann nicht sein eigener Twink sein."
L["USER_ALT_OF_ALT"] = "%s ist ein Twink von %s, und ein Twink kann keine eigenen Twinks haben."
L["USER_ALT_HAS_ALTS"] = "%s hat eigene Twinks und kann daher kein Twink werden."
L["USER_DELETE_IN_USE"] = "%s wird noch verwendet in: %s. Entferne ihn zuerst dort."

--
-- The user editor and the offers window, which came from Konfer with them.
--
L["Old name"] = "Alter Name"
L["New name"] = "Neuer Name"
L["Users"] = "Nutzer"
L["Create"] = "Erstellen"
L["Delete"] = "Löschen"
L["Rename"] = "Umbenennen"
L["Update"] = "Updaten"
L["User is an alt of"] = "Nutzer ist ein Twink von"
L["Guild import"] = "Gilden-Import"
L["user %q created."] = "User %q wurde erstellt."
L["user %q deleted."] = "Nutzer %q wurde gel\195\182scht."
L["Delete user"] = "Lösche Nutzer"
L["User: %s"] = "Nutzer: %s"
L["Rename user"] = "Nutzer umbenennen"
L["added %d user(s)."] = "%d Nutzer hinzugefügt."
L["USEREDIT_TITLE"] = "Nutzer"
L["USEREDIT_SEARCH"] = "Suche"
L["USEREDIT_TETHER"] = "Verbundene Twinks"
L["TIP_USEREDIT_TETHER"] = "Zeigt jeden Main mit seinen Twinks darunter, statt alle einzeln. Die Suche findet dann einen Main mit allen seinen Twinks, sobald einer von ihnen passt."
L["TIP_USEREDIT_SEARCH"] = "Gib einen Teil eines Namens, Realms, einer Klasse oder eines Berufs ein, um die Liste einzugrenzen. Jedes eingegebene Wort muss passen, \"magier schneider\" findet also Magier, die Schneider sind. Der Name eines Mains findet auch seine Twinks."
L["USEREDIT_COUNT"] = "%d Nutzer"
L["USEREDIT_COUNT_ONE"] = "%d Nutzer"
L["USEREDIT_COL_NAME"] = "Name"
L["USEREDIT_COL_CLASS"] = "Klasse"
L["USEREDIT_COL_MSSPEC"] = "Mainspec"
L["USEREDIT_COL_OSSPEC"] = "Offspec"
L["USEREDIT_COL_PROF1"] = "Beruf 1"
L["USEREDIT_COL_PROF2"] = "Beruf 2"
L["USEREDIT_COL_MAIN"] = "Twink von"
L["USEREDIT_ALTS"] = "Twinks: %s"
L["USEREDIT_NOALTS"] = "Keine Twinks"
L["USER_SHARED_INFO"] = "Gemeinsame Infos"
L["USEREDIT_NOTES"] = "Private Notizen / Bewertungen"
L["USEREDIT_RATING"] = "Bewertung"
L["USEREDIT_NOTE"] = "Deine Notizen"
L["TIP_USEREDIT_NOTE"] = "Alles, was du dir \195\188ber diesen Charakter merken willst, in deinen eigenen Worten. Deine Notizen geh\195\182ren nur dir. Sie werden nie an andere gesendet und beim Tippen gespeichert."
L["USEREDIT_FILTER"] = "Filter"
L["USEREDIT_FILTER_TITLE"] = "Nutzer filtern"
L["USEREDIT_FILTER_TEXT"] = "Die Nutzerliste auf Nutzer mit mindestens den folgenden Bewertungen beschr\195\164nken."
L["USEREDIT_CLEAR"] = "Leeren"
L["USEREDIT_FILTER_UNRATED"] = "%s einschlie\195\159en"
L["TIP_USEREDIT_FILTER_UNRATED"] = "Zeigt auch Nutzer, die du in etwas, wonach der Filter fragt, gar nicht bewertet hast, als ob sie es erf\195\188llten."
L["TIP_USEREDIT_FILTER"] = "Zeigt nur die Nutzer, die du mindestens so hoch bewertet hast wie gew\195\164hlt. Solange ein Filter aktiv ist, zeigt die Anzahl oben an der Liste, wie viele von wie vielen angezeigt werden."
L["TIP_USEREDIT_FILTER_RATING"] = "Nur Nutzer anzeigen, die du hierin mindestens so hoch bewertet hast, oder %s, um dies nicht zu filtern."
L["TIP_USEREDIT_GUILDIMPORT"] = "F\195\188gt Mitglieder deiner Gilde als Nutzer hinzu. Sie werden keiner Konfiguration hinzugef\195\188gt."
L["TIP_USEREDIT_RATING"] ="Wie gut du diesen Charakter darin findest, oder %s. Deine Bewertungen geh\195\182ren nur dir. Sie werden nie an andere gesendet und sofort gespeichert, wenn du eine w\195\164hlst."
L["TIP_USEREDIT_UPDATE"] = "Speichert die \195\132nderungen an diesem Charakter. Sie gelten in jeder Konfiguration, in der er vorkommt."
L["TIP_USEREDIT_CREATE"] = "F\195\188gt einen Charakter hinzu, den Konfer noch nicht kennt. Er wird keiner Konfiguration hinzugef\195\188gt."
L["TIP_USEREDIT_RENAME"] = "Gibt dem ausgew\195\164hlten Charakter nach einer kostenpflichtigen Namens\195\164nderung seinen neuen Namen. Jede Konfiguration, in der er vorkommt, folgt."
L["TIP_USEREDIT_DELETE"] = "Vergisst den ausgew\195\164hlten Charakter vollst\195\164ndig. Das geht erst, wenn ihn keine Konfiguration mehr als Nutzer f\195\188hrt."
L["USEREDIT_DELMSG"] = "Alles vergessen, was Konfer \195\188ber diesen Charakter wei\195\159? Klasse, Spezialisierungen, Berufe und Twink-Verkn\195\188pfungen gehen verloren, ebenso deine eigenen Notizen und Bewertungen. Keine Konfiguration verwendet ihn, daher \195\164ndert sich keine Wurf-Liste."
L["USEROFFER_TITLE"] = "\195\132nderungen an deinen Aufzeichnungen"
L["USEROFFER_FROM"] = "\195\156bertragung von %s"
L["USEROFFER_BLURB"] = "Dieser Spieler hat Informationen \195\188bertragen, die gespeicherte Fakten \195\188ber Charaktere \195\164ndern. Wenn du der Quelle vertraust, kannst du die \195\156bertragung annehmen, oder einzelne Eintr\195\164ge davon ausschlie\195\159en."
L["USEROFFER_ALL"] = "Alle"
L["TIP_USEROFFER_ALL"] = "Alle Charaktere in der Liste an- oder abw\195\164hlen."
L["USEROFFER_COL_WHO"] = "Charakter"
L["USEROFFER_COL_WHAT"] = "Was"
L["USEROFFER_COL_NOW"] = "Du hast"
L["USEROFFER_COL_OFFERED"] = "Gesendet"
L["USEROFFER_BLOCK"] = "Absender sperren"
L["TIP_USEROFFER_BLOCK"] = "Dies verwerfen und ab sofort alles ignorieren, was dieser Spieler \195\188bertr\195\164gt. Gesperrte Spieler stehen im Benutzereditor, wo du sie wieder zulassen kannst."
L["USEREDIT_BLOCKED"] = "Gesperrt"
L["TIP_USEREDIT_BLOCKED"] = "Die Spieler, deren \195\156bertragungen du ignorierst."
L["USEREDIT_BLOCKED_TITLE"] = "Gesperrte Absender"
L["USEREDIT_BLOCK"] = "Sperren"
L["TIP_USEREDIT_BLOCK"] = "Alles ignorieren, was dieser Spieler \195\188bertr\195\164gt."
L["TIP_USEREDIT_BLOCKED_NAME"] = "Der Name des zu ignorierenden Spielers. Ein Name ohne Realm ist jemand auf deinem eigenen Realm."
L["USEREDIT_UNBLOCK"] = "Entsperren"
L["TIP_USEREDIT_UNBLOCK"] = "Die \195\156bertragungen dieses Spielers wieder annehmen."
L["USEREDIT_LEVEL"] = "Stufe %s"

-- The roles a player raids in (K.RoleName).
L["Healer"] = "Healer"
L["Melee DPS"] = "Melee DPS"
L["Ranged DPS"] = "Ranged DPS"
L["Caster DPS"] = "Caster DPS"
L["Tank"] = "Tank"

--
-- The widgets a person is picked and edited with (UserUI.lua).
--
L["User role"] = "Nutzerrolle"
L["TIP071"] = "W\195\164hle aus, welche Rolle der Nutzer im Raid / in der Gilde spielt. Dies wird benutzt, um einen Filter zu setzten, um Nutzer beim Bieten zu beschr\195\164nken, wenn sie eine bestimmte Rolle haben. Dieser Fall tritt ein, wenn ein Item f\195\188r mehr als einen Spielertyp sinnvoll ist. Zum Beispiel kannst du entscheiden, dass ein Item besser f\195\188r Heiler ist, auch wenn es Caster DPS ebenfalls wollen."
L["Off spec"] = "Offspec"
L["Main spec"] = "Mainspec"
L["Main / off spec"] = "Main- / Offspec"
L["TIP109"] = "Die Offspec dieses Nutzers. Ein auf eine Rolle beschr\195\164nkter Gegenstand nimmt Offspec-W\195\188rfe nur von Nutzern an, deren Offspec diese Rolle spielt. Auf %s lassen, wenn keine Offspec gespielt wird."
L["TIP108"] = "Die Mainspec dieses Nutzers. Ein auf eine Rolle beschr\195\164nkter Gegenstand nimmt Mainspec-Gebote und -W\195\188rfe nur von Nutzern an, deren Mainspec diese Rolle spielt."
L["User class"] = "User-Klasse"
L["Class"] = "Klasse"
L["Race"] = "Volk"
L["Level"] = "Stufe"
L["TIP073"] = "Wähle die Klasse des Nutzers aus. Du musst die richtige Klasse zuweisen, damit die Klassenfilter richtig funktionieren."
L["Second profession"] = "Zweiter Beruf"
L["Profession"] = "Beruf"
L["First profession"] = "Erster Beruf"
L["Professions"] = "Berufe"
L["TIP105"] = "Der zweite der beiden herstellenden Berufe dieses Nutzers. Auf %s lassen, wenn nur ein Beruf erlernt wurde."
L["TIP104"] = "Der erste der beiden herstellenden Berufe dieses Nutzers. Dies wird festgehalten, damit bekannt ist, wer im Schlachtzug was herstellen kann. Es ist unabh\195\164ngig von der Einstellung Schlachtzugsverzauberer dar\195\188ber, die festlegt, wer Gegenst\195\164nde zum Entzaubern erh\195\164lt."
L["TIP_USEREDIT_MAIN"] = "Der Charakter, dessen Twink dieser ist, oder %s, wenn er ein Main ist. Angeboten werden nur Charaktere, die selbst keine Twinks sind, und ein Charakter mit eigenen Twinks kann keiner werden."
L["Create user"] = "Erstelle Nutzer"
L["Name"] = "Name"
L["TIP072"] = "Gib den Namen des Nutzers ein. Er muss genau mit seinem Charakternamen übereinstimmen."
L["you must set a user class."] = "Du musst eine Klasse festlegen."
L["Import guild users"] = "Importiere Gildenmitglieder"
L["Minimum level"] = "Minimum-Level"
L["TIP074"] = "Wähle das Mindest-Level, um einen Nutzer zu akzeptieren. Alle Gildenmitglieder unter diesem Level werden nicht importiert."

--
-- The Skill Rating grid, whose keys are built from RATE_ROWS and RATINGS (see UserEditor.lua).
--
L["USEREDIT_RATE_HEALER"] = "Als Heiler"
L["USEREDIT_RATE_TANK"] = "Als Tank"
L["USEREDIT_RATE_MELEE"] = "Als Nahk\195\164mpfer"
L["USEREDIT_RATE_RANGED"] = "Als Fernk\195\164mpfer"
L["USEREDIT_RATE_ETIQUETTE"] = "Gruppenverhalten"
L["USEREDIT_RATE_KNOWLEDGE"] = "Wissen"
L["USEREDIT_RATE_HELPFUL"] = "Hilfsbereitschaft"
L["USEREDIT_RATING_TERRIBLE"] = "Furchtbar - meiden"
L["USEREDIT_RATING_BIND"] = "Nur im Notfall"
L["USEREDIT_RATING_ORDINARY"] = "Nichts Besonderes"
L["USEREDIT_RATING_ABOVE"] = "\195\156berdurchschnittlich"
L["USEREDIT_RATING_GOOD"] = "Gut"
L["USEREDIT_RATING_EXCELLENT"] = "Hervorragend"
