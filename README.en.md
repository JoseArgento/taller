# Taller

For crafters in **WoW Forever**. Pin recipes, say how many you want to make, and Taller tells you how many materials you need and how many you have: in your bags, your bank and your other characters. All split by profession. ("Taller" is Spanish for workshop.)

- **Pin:** in the game's profession window, tick the box to track the recipe. It shows up in Taller. Untick it and it's unpinned; unpin it in Taller and it's unticked.
- **Quantity:** `+` and `-` on each recipe (Shift for 10). It counts **items**: if a recipe makes 5 stones per craft and you want 12, that's 3 crafts.
- **Materials:** under each recipe, "have / need" and how many are missing. Hover to see where they are ("5 Josecito (bags), 12 Ana (bank), 3 account bank").
- **Shopping list:** everything your recipes need, added up, most missing first. If another recipe of yours makes a material, it says so.
- **When you craft** the quantity goes down by itself; at zero you get a message and it's unpinned.
- **Item tooltips:** "Taller: 20 needed, 3 here, 12 on Ana".
- **Camping blueprints:** a Blueprints tab lists all 21 by profession: which of your characters learned each, which you carry unlearned, which are missing, and who drops them (beta data; 10 sources not known yet). Blueprint tooltips say whether any of your characters learned it.
- `/taller` opens it, `/taller planos` (or `blueprints`) the blueprints, `/taller copiar` (or `copy`) gives what is missing as text, `/taller compras` (or `shopping`) goes to the shopping list.

**What it counts:** bags (and the reagent bag) always; your bank and the account bank as you last saw them; other characters as of your last login with them. Not the mailbox or the auction house.

**Why another one:** *Forever Profession Master* has a queue with quantities but only counts bags; *ItemWatch & Shopping List* counts bags and bank but not alts; *ForeverArtisan* counts alts with an extra bag addon. Taller does one thing: what you want to craft against everything you own, on every character, with nothing else needed.

**Tested**: every API checked against Forever 1.60.1 (`tools/check_api.py`); forever-lint and Addon Sentry report nothing; 31 tests in Lua 5.1 with several characters sharing the saved data. **Not tested in the game**: how the window looks, that Forever's track box fires `TRACKED_RECIPE_UPDATE`, that Forever uses the modern bank tabs and an account bank, and that `UNIT_SPELLCAST_SUCCEEDED` carries the recipe ID when crafting.

Not affiliated with Blizzard Entertainment. MIT license.
