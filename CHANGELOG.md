# Changelog

## 0.2.0 (unreleased)

- **Minimap button like the game's** (Pergamino 7): gold bevelled ring, dark disc, shadow, a cream icon; `/taller minimapa juntar on|off` puts every addon of the family into one button with a menu. Errors in the minimap button and the addon compartment are kept too (`/taller errores`).
- **Its own errors, kept** (Pergamino 5): a Lua error in a handler no longer reaches the player as a popup; it is kept in `TallerDB.errors` (last 10), said once in the chat, and `/taller errores` opens a page to copy it into a GitHub issue. An "Errores" bookmark appears while there is something kept.
- **Minimap button** (Pergamino 2): left click opens the book, right click the blueprints, drag it around the minimap; `/taller minimapa on|off` shows or hides it (`TallerDB.settings.minimap`, angle in `minimapAngle`). Pergamino 2 also brings one-line bookmarks and scroll bars only when needed.
- Recipes: the quantity field always shows the real quantity (it could keep what you typed while + and - changed the pin); what you type applies on Enter or when you leave the field; bigger + and - buttons; "1 craft" in singular. Shorter bookmarks (Recipes, Shopping, Blueprints). Blueprint rows on the left page are short (name and tier) with a seal for learned / carried / missing; skill and drop stay on the right page.
- **The window is an open book** (the shared Pergamino skin, vendored in `Libs/Pergamino` with its own textures and OFL fonts): bookmarks for Recipes, Shopping list and Blueprints; list on the left page, the chosen recipe or blueprint on the right; blueprint professions folded with "learned / total"; empty pages that say what to do; bookmark tooltips.
- **Language setting**: `/taller idioma es|en|auto` picks Spanish or English whatever the client speaks (saved in `TallerDB.settings.lang`).
- Own icon in the addon compartment and a key binding to open the window (Key Bindings → AddOns).
- Reads **Syndicator** (or **Baganator**) when installed: other characters, guild bank, account bank and mail come from its data, labelled "via Syndicator" in the tooltip; your own bags and bank stay live. Reads **Auctionator** prices: each missing material in the shopping list shows its cost and the list shows a total, also in "Copy list". Both optional, every call guarded; their API names are unverified ⏳ (`Taller/Partners.lua`).
- Shared helper for place names (characters, account bank, guild banks).

## 0.1.0 (unreleased)

First version, for WoW Forever 1.60.1.

- Pin recipes with the game's own track box and set how many items you want (crafts are worked out from the recipe's yield).
- Materials counted in bags, reagent bag, bank, account bank and your other characters, by profession; where each one is, on hover.
- Shopping list of everything added up, copyable as one line; tooltip lines on materials; the count goes down as you craft.
- Camping blueprints tab: all 21, who learned each, which you carry unlearned, which are missing, and the boss that drops each (beta data).
