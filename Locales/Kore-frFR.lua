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

local L = LibStub("AceLocale-3.0"):NewLocale("Kore", "frFR")
if (not L) then
  return
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
L["OK_STR"] = "OK"
L["CANCEL_STR"] = "Annuler"
L["ACCEPT_STR"] = "Accepter"
L["CLOSE_STR"] = "Fermer"
L["OPEN_STR"] = "Ouvrir"
L["HELP_STR"] = "Aide"
L["YES_STR"] = "Oui"
L["NO_STR"] = "Non"
L["SAVEBAR_STR"] = "Enregistrer les modifications de cette page"
L["SAVEBAR_MSG"] = "Les modifications faites sur cette page ne seront permanentes qu'apr\195\168s avoir appuy\195\169 sur ce bouton. Fermer la fen\195\170tre sans enregistrer fera perdre toutes les modifications."
L["NONE_STR"] = "-Aucun-"
L["NOTSET_STR"] = "-Non d\195\169fini-"
L["NOBODY_STR"] = "-Personne-"
L["NOTRATED_STR"] = "-Non not\195\169-"
L["KAHLUA"] = "KahLua"
L["DEV_STR"] = "dev"
L["error: "] = "erreur : "

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KORE"] = "kore"
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
L["Debug level %d out of bounds - must be between 0 and 10."] = "Niveau de d\195\169boguage %d hors limites - doit \195\170tre compris entre 0 et 10."
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = "Module '%s' inexistant. Utilisez %s/%s %s%s pour une liste des modules disponibles."
L["Kore extensions loaded:"] = "Extensions Kore chargées :"
L["Chest"] = "Coffre"

L["Your version of %s is out of date. Please update it."] = "Votre version de %s n'est pas \195\160 jour. Veuillez la mettre \195\160 jour."
L["%s communication registration failed!"] = "%s \195\169chec de l'enregistrement des communications\194\160!"
L["%s: the game is refusing addon messages for now, so some were not sent."] = "%s : le jeu refuse les messages d'addon pour le moment, certains n'ont donc pas \195\169t\195\169 envoy\195\169s."
L["not sent: %s"] = "non envoy\195\169 : %s" -- @debug-delete@
L["%s: an addon message from %q was corrupt."] = "%s : un message d'addon de %q \195\169tait corrompu."
L["Shield"] = true



L["you must specify a character name."] = "Vous devez indiquer un nom de personnage."
L["%q is not a valid character name."] = "%q n'est pas un nom de personnage valide."
L["user %q already exists. Try again."] = "Le joueur %q existe d\195\169j\195\160. R\195\169essayez."
L["user %q does not exist. Try again."] = "Le joueur %q n'existe pas. R\195\169essayez."
L["USER_ALT_SELF"] = "%s ne peut pas \195\170tre son propre reroll."
L["USER_ALT_OF_ALT"] = "%s est un reroll de %s, et un reroll ne peut pas avoir ses propres rerolls."
L["USER_ALT_HAS_ALTS"] = "%s a ses propres rerolls et ne peut donc pas devenir un reroll."
L["USER_DELETE_IN_USE"] = "%s est encore utilis\195\169 dans : %s. Retirez-le d'abord de ceux-ci."

--
-- The user editor and the offers window, which came from Konfer with them.
--
L["Old name"] = "Ancien nom"
L["New name"] = "Nouveau nom"
L["Users"] = "Joueurs"
L["Create"] = "Cr\195\169er"
L["Delete"] = "Supprimer"
L["Rename"] = "Renommer"
L["Update"] = "M\195\160J"
L["User is an alt of"] = "Le joueur est un reroll de"
L["Guild import"] = "Import de guilde"
L["user %q created."] = "joueur %q cr\195\169\195\169."
L["user %q deleted."] = "joueur %q supprim\195\169."
L["Delete user"] = "Supprimer joueur"
L["User: %s"] = "Joueur : %s"
L["Rename user"] = "Renommer joueur"
L["added %d user(s)."] = "%d joueur(s) ajout\195\169(s)."
L["USEREDIT_TITLE"] = "Joueurs"
L["USEREDIT_SEARCH"] = "Rechercher"
L["USEREDIT_TETHER"] = "Rerolls rattach\195\169s"
L["TIP_USEREDIT_TETHER"] = "Affiche chaque main avec ses rerolls en dessous, au lieu de chacun s\195\169par\195\169ment. La recherche trouve alors un main et tous ses rerolls d\195\168s que l'un d'eux correspond."
L["TIP_USEREDIT_SEARCH"] = "Saisissez une partie d'un nom, d'un royaume, d'une classe ou d'un m\195\169tier pour r\195\169duire la liste. Chaque mot saisi doit correspondre, donc \"mage tailleur\" trouve les mages qui sont tailleurs. Le nom d'un main trouve aussi ses rerolls."
L["USEREDIT_COUNT"] = "%d joueurs"
L["USEREDIT_COUNT_ONE"] = "%d joueur"
L["USEREDIT_COL_NAME"] = "Nom"
L["USEREDIT_COL_CLASS"] = "Classe"
L["USEREDIT_COL_MSSPEC"] = "Sp\195\169 principale"
L["USEREDIT_COL_OSSPEC"] = "Sp\195\169 secondaire"
L["USEREDIT_COL_PROF1"] = "M\195\169tier 1"
L["USEREDIT_COL_PROF2"] = "M\195\169tier 2"
L["USEREDIT_COL_MAIN"] = "Reroll de"
L["USEREDIT_ALTS"] = "Rerolls : %s"
L["USEREDIT_NOALTS"] = "Aucun reroll"
L["USER_SHARED_INFO"] = "Infos partag\195\169es"
L["USEREDIT_NOTES"] = "Notes priv\195\169es / \195\169valuations"
L["USEREDIT_RATING"] = "\195\137valuation"
L["USEREDIT_NOTE"] = "Vos notes"
L["TIP_USEREDIT_NOTE"] = "Tout ce que vous voulez retenir sur ce personnage, dans vos propres mots. Vos notes n'appartiennent qu'\195\160 vous. Elles ne sont jamais envoy\195\169es \195\160 personne et sont enregistr\195\169es au fur et \195\160 mesure que vous \195\169crivez."
L["USEREDIT_FILTER"] = "Filtrer"
L["USEREDIT_FILTER_TITLE"] = "Filtrer les joueurs"
L["USEREDIT_FILTER_TEXT"] = "Filtrer la liste pour n'afficher que les joueurs ayant au moins les \195\169valuations suivantes."
L["USEREDIT_CLEAR"] = "Effacer"
L["USEREDIT_FILTER_UNRATED"] = "Inclure %s"
L["TIP_USEREDIT_FILTER_UNRATED"] = "Affiche aussi les joueurs que vous n'avez pas du tout \195\169valu\195\169s dans un domaine que le filtre demande, comme s'ils y r\195\169pondaient."
L["TIP_USEREDIT_FILTER"] = "N'affiche que les joueurs que vous avez \195\169valu\195\169s au moins aussi haut que vous le choisissez. Tant qu'un filtre est actif, le compte en haut de la liste indique combien sont affich\195\169s sur combien il y en a."
L["TIP_USEREDIT_FILTER_RATING"] = "N'afficher que les joueurs que vous avez \195\169valu\195\169s au moins aussi haut dans ce domaine, ou %s pour ne pas en tenir compte."
L["TIP_USEREDIT_GUILDIMPORT"] = "Ajoute des membres de votre guilde comme joueurs. Ils ne sont ajout\195\169s \195\160 aucune configuration."
L["TIP_USEREDIT_RATING"] ="Ce que vous pensez de ce personnage dans ce domaine, ou %s. Vos \195\169valuations n'appartiennent qu'\195\160 vous. Elles ne sont jamais envoy\195\169es \195\160 personne et sont enregistr\195\169es d\195\168s que vous en choisissez une."
L["TIP_USEREDIT_UPDATE"] = "Enregistre les modifications de ce personnage. Elles s'appliquent dans toutes les configurations o\195\185 il figure."
L["TIP_USEREDIT_CREATE"] = "Ajoute un personnage que Konfer ne conna\195\174t pas encore. Il n'est ajout\195\169 \195\160 aucune configuration."
L["TIP_USEREDIT_RENAME"] = "Donne au personnage s\195\169lectionn\195\169 son nouveau nom apr\195\168s un changement de nom payant. Toutes les configurations o\195\185 il figure suivent."
L["TIP_USEREDIT_DELETE"] = "Oublie enti\195\168rement le personnage s\195\169lectionn\195\169. Ce n'est possible qu'une fois qu'aucune configuration ne l'a comme joueur."
L["USEREDIT_DELMSG"] = "Oublier tout ce que Konfer sait de ce personnage ? Sa classe, ses sp\195\169cialisations, ses m\195\169tiers et ses liens de reroll seront perdus, ainsi que vos propres notes et \195\169valuations. Aucune configuration ne l'utilise, donc aucune liste ne change."
L["USEROFFER_TITLE"] = "Modifications de vos fiches"
L["USEROFFER_FROM"] = "Diffusion de %s"
L["USEROFFER_BLURB"] = "Ce joueur a diffus\195\169 des informations qui modifient des faits enregistr\195\169s sur des personnages. Si vous faites confiance \195\160 la source, vous pouvez accepter la diffusion ou en exclure certaines entr\195\169es."
L["USEROFFER_ALL"] = "Tout le monde"
L["TIP_USEROFFER_ALL"] = "Cocher ou d\195\169cocher tous les personnages de la liste."
L["USEROFFER_COL_WHO"] = "Personnage"
L["USEROFFER_COL_WHAT"] = "Quoi"
L["USEROFFER_COL_NOW"] = "Vous avez"
L["USEROFFER_COL_OFFERED"] = "Envoy\195\169"
L["USEROFFER_BLOCK"] = "Bloquer l'exp\195\169diteur"
L["TIP_USEROFFER_BLOCK"] = "Jeter ceci et ignorer d\195\169sormais tout ce que ce joueur diffuse. Les joueurs bloqu\195\169s figurent dans l'\195\169diteur d'utilisateurs, o\195\185 vous pouvez les r\195\169admettre."
L["USEREDIT_BLOCKED"] = "Bloqu\195\169s"
L["TIP_USEREDIT_BLOCKED"] = "Les joueurs dont vous ignorez les diffusions."
L["USEREDIT_BLOCKED_TITLE"] = "Exp\195\169diteurs bloqu\195\169s"
L["USEREDIT_BLOCK"] = "Bloquer"
L["TIP_USEREDIT_BLOCK"] = "Ignorer tout ce que ce joueur diffuse."
L["TIP_USEREDIT_BLOCKED_NAME"] = "Le nom du joueur \195\160 ignorer. Un nom sans royaume d\195\169signe quelqu'un de votre propre royaume."
L["USEREDIT_UNBLOCK"] = "D\195\169bloquer"
L["TIP_USEREDIT_UNBLOCK"] = "Accepter de nouveau les diffusions de ce joueur."
L["USEREDIT_LEVEL"] = "Niveau %s"

-- The roles a player raids in (K.RoleName).
L["Healer"] = "Heal"
L["Melee DPS"] = "DPS CaC"
L["Ranged DPS"] = "DPS distant"
L["Caster DPS"] = "DPS magique"
L["Tank"] = "Tank"

--
-- The widgets a person is picked and edited with (UserUI.lua).
--
L["User role"] = "R\195\180le du joueur"
L["TIP071"] = "S\195\169lectionne le r\195\180le que joue le joueur dans le raid  la guilde. Ceci est utilis\195\169 pour d\195\169finir des filtres pour restreindre les ench\195\169risseurs aux joueurs qui remplissent un certain r\195\180le, dans le cas o\195\185 un objet pourrait \195\170tre davatange utile \195\160 un type de joueurs. Par exemple, vous pourrez d\195\169cider que cet objet est pour heal, m\195\170me si les DPS magique peuvent le convoiter."
L["Off spec"] = "Sp\195\169 secondaire"
L["Main spec"] = "Sp\195\169 principale"
L["Main / off spec"] = "Principale / secondaire"
L["TIP109"] = "La sp\195\169 secondaire de ce joueur. Un objet r\195\169serv\195\169 \195\160 un r\195\180le n'accepte un rand en sp\195\169 secondaire que des joueurs dont la sp\195\169 secondaire tient ce r\195\180le. Laissez %s s'il n'a pas de sp\195\169 secondaire."
L["TIP108"] = "La sp\195\169 principale de ce joueur. Un objet r\195\169serv\195\169 \195\160 un r\195\180le n'accepte une ench\195\168re ou un rand en sp\195\169 principale que des joueurs dont la sp\195\169 principale tient ce r\195\180le."
L["User class"] = "Classe du joueur"
L["Class"] = "Classe"
L["Race"] = "Race"
L["Level"] = "Niveau"
L["TIP073"] = "S\195\169lectionnez la classe du joueur. Vous devez d\195\169finir une classe pr\195\169cise car ceci affectera le filtre des classes."
L["Second profession"] = "Second m\195\169tier"
L["Profession"] = "M\195\169tier"
L["First profession"] = "Premier m\195\169tier"
L["Professions"] = "M\195\169tiers"
L["TIP105"] = "Le second des deux m\195\169tiers d'artisanat de ce joueur. Laissez %s s'il n'en a appris qu'un seul."
L["TIP104"] = "Le premier des deux m\195\169tiers d'artisanat de ce joueur. Cette information est conserv\195\169e pour savoir qui, dans le raid, peut fabriquer quoi. Elle est ind\195\169pendante du r\195\169glage Enchanteur du raid ci-dessus, qui d\195\169signe qui re\195\167oit les objets \195\160 d\195\169senchanter."
L["TIP_USEREDIT_MAIN"] = "Le personnage dont celui-ci est un reroll, ou %s s'il est un main. Seuls les personnages qui ne sont pas eux-m\195\170mes des rerolls sont propos\195\169s, et un personnage qui a ses propres rerolls ne peut pas en devenir un."
L["Create user"] = "Cr\195\169er joueur"
L["Name"] = "Nom"
L["TIP072"] = "Entrez le nom exact du joueur."
L["you must set a user class."] = "Vous devez d\195\169finir une classe."
L["Import guild users"] = "Importer les joueurs depuis la guilde"
L["Minimum level"] = "Niveau minimum"
L["TIP074"] = "S\195\169lectionnez le niveau minumu pour accepter les joueurs. Les membres de guilde en-dessous de ce niveau ne seront pas import\195\169s."

--
-- The Skill Rating grid, whose keys are built from RATE_ROWS and RATINGS (see UserEditor.lua).
--
L["USEREDIT_RATE_HEALER"] = "En tant que soigneur"
L["USEREDIT_RATE_TANK"] = "En tant que tank"
L["USEREDIT_RATE_MELEE"] = "En m\195\170l\195\169e"
L["USEREDIT_RATE_RANGED"] = "\195\128 distance"
L["USEREDIT_RATE_ETIQUETTE"] = "Savoir-vivre en groupe"
L["USEREDIT_RATE_KNOWLEDGE"] = "Connaissances"
L["USEREDIT_RATE_HELPFUL"] = "Serviabilit\195\169"
L["USEREDIT_RATING_TERRIBLE"] = "Terrible - \195\160 \195\169viter"
L["USEREDIT_RATING_BIND"] = "En dernier recours"
L["USEREDIT_RATING_ORDINARY"] = "Rien de sp\195\169cial"
L["USEREDIT_RATING_ABOVE"] = "Meilleur que la moyenne"
L["USEREDIT_RATING_GOOD"] = "Bon"
L["USEREDIT_RATING_EXCELLENT"] = "Excellent"
