# Changelog

## 0.2.0 (unreleased)

- Reads **Syndicator** (or **Baganator**) when installed: other characters, guild bank, account bank and mail come from its data, labelled "via Syndicator" in the tooltip; your own bags and bank stay live. Reads **Auctionator** prices: each missing material in the shopping list shows its cost and the list shows a total, also in "Copy list". Both optional, every call guarded; their API names are unverified ⏳ (`Taller/Partners.lua`).
- Shared helper for place names (characters, account bank, guild banks).

## 0.1.0 (unreleased)

First version, for WoW Forever 1.60.1.

- Pin recipes with the game's own track box and set how many items you want (crafts are worked out from the recipe's yield).
- Materials counted in bags, reagent bag, bank, account bank and your other characters, by profession; where each one is, on hover.
- Shopping list of everything added up, copyable as one line; tooltip lines on materials; the count goes down as you craft.
- Camping blueprints tab: all 21, who learned each, which you carry unlearned, which are missing, and the boss that drops each (beta data).
