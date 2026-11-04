local _, ns = ...
local L = ns.L

-- Pinned recipes. A pin is one recipe for one character (the one who knows it), with how many items you
-- want. The reagents are read from the game when you pin it and kept, so your alts can see them too.

local P = {}
ns.Pins = P

local function professionOf(recipeID)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	if info and info.professionName and info.professionName ~= "" then
		return info.parentProfessionName or info.professionName
	end
	return L.OTHER
end

-- The reagents of a recipe: required slots only (optional ones are a choice, not a need).
function P.ReadRecipe(recipeID)
	local s = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	-- an unknown recipe comes back as an empty schematic, without a name
	if type(s) ~= "table" or not s.reagentSlotSchematics or not s.name or s.name == "" or issecretvalue(s.name) then
		return nil
	end
	local reagents = {}
	for _, slot in ipairs(s.reagentSlotSchematics) do
		local first = slot.reagents and slot.reagents[1]
		if slot.required ~= false and first and first.itemID and (slot.quantityRequired or 0) > 0 then
			reagents[#reagents + 1] = { item = first.itemID, n = slot.quantityRequired }
		end
	end
	return {
		name = s.name,
		output = s.outputItemID,
		per = math.max(1, s.quantityMin or 1),
		reagents = reagents,
		profession = professionOf(recipeID),
	}
end

function P.Find(recipeID, crafter)
	crafter = crafter or ns.CharKey()
	for i, p in ipairs(ns.db.pins) do
		if p.recipe == recipeID and p.crafter == crafter then
			return p, i
		end
	end
end

function P.Pin(recipeID, qty, quiet)
	local existing = P.Find(recipeID)
	if existing then
		if qty then
			P.SetQty(existing, qty)
		end
		return existing
	end
	local r = P.ReadRecipe(recipeID)
	if not r then
		if not quiet then
			ns.Print(L.NOT_A_RECIPE)
		end
		return nil
	end
	local pin = {
		recipe = recipeID,
		qty = math.max(1, math.floor(tonumber(qty) or r.per)),
		crafter = ns.CharKey(),
		profession = r.profession,
		name = r.name,
		output = r.output,
		per = r.per,
		reagents = r.reagents,
		at = time(),
	}
	table.insert(ns.db.pins, pin)
	if not quiet then
		ns.Print(L.PINNED:format(pin.name))
	end
	ns.Fire("pins")
	return pin
end

function P.Unpin(pin)
	local _, i = P.Find(pin.recipe, pin.crafter)
	if not i then
		return
	end
	table.remove(ns.db.pins, i)
	-- untick the game's own "track" too, when it is this character's recipe
	if pin.crafter == ns.CharKey() and C_TradeSkillUI.IsRecipeTracked(pin.recipe, false) then
		C_TradeSkillUI.SetRecipeTracked(pin.recipe, false, false)
	end
	ns.Fire("pins")
end

function P.SetQty(pin, qty)
	qty = math.floor(tonumber(qty) or 0)
	if qty <= 0 then
		P.Unpin(pin)
		return
	end
	pin.qty = math.min(qty, 9999)
	ns.Fire("pins")
end

-- How many times you have to craft it to get pin.qty items.
function P.Crafts(pin)
	return math.ceil(pin.qty / (pin.per or 1))
end

-- Each reagent of a pin: { item, need, have = Inventory.Count(item) }.
function P.Needs(pin)
	local out = {}
	local crafts = P.Crafts(pin)
	for _, r in ipairs(pin.reagents) do
		out[#out + 1] = { item = r.item, need = r.n * crafts, have = ns.Inventory.Count(r.item) }
	end
	return out
end

-- Every pin's reagents added up: the shopping list. Sorted with the most missing first.
function P.Shopping()
	local need = {}
	for _, pin in ipairs(ns.db.pins) do
		local crafts = P.Crafts(pin)
		for _, r in ipairs(pin.reagents) do
			need[r.item] = (need[r.item] or 0) + r.n * crafts
		end
	end
	local out = {}
	for item, n in pairs(need) do
		local have = ns.Inventory.Count(item)
		out[#out + 1] = { item = item, need = n, have = have, missing = math.max(0, n - have.total) }
	end
	table.sort(out, function(a, b)
		if a.missing ~= b.missing then
			return a.missing > b.missing
		end
		return a.item < b.item
	end)
	return out
end

-- Pins grouped by profession: { { profession, pins = { ... } } }, professions in alphabetical order.
function P.ByProfession()
	local groups, order = {}, {}
	for _, pin in ipairs(ns.db.pins) do
		local name = pin.profession or L.OTHER
		if not groups[name] then
			groups[name] = { profession = name, pins = {} }
			order[#order + 1] = name
		end
		table.insert(groups[name].pins, pin)
	end
	table.sort(order)
	local out = {}
	for _, name in ipairs(order) do
		out[#out + 1] = groups[name]
	end
	return out
end

-- A reagent that is also the product of another pin of yours: you can make it instead of buying it.
function P.MadeBy(itemID)
	for _, pin in ipairs(ns.db.pins) do
		if pin.output == itemID then
			return pin
		end
	end
end

-- You crafted something: count it against its pin (one cast = pin.per items).
function P.OnCrafted(recipeID)
	local pin = P.Find(recipeID)
	if not pin then
		return
	end
	pin.qty = pin.qty - (pin.per or 1)
	if pin.qty <= 0 then
		ns.Print(L.DONE:format(pin.name))
		P.Unpin(pin)
		PlaySound(SOUNDKIT.UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST)
	else
		ns.Fire("pins")
	end
end

-- The game's own "track" box: ticking it pins the recipe here, unticking it unpins it.
function P.OnTracked(recipeID, tracked)
	if tracked then
		P.Pin(recipeID, nil, false)
	else
		local pin = P.Find(recipeID)
		if pin then
			P.Unpin(pin)
			ns.Print(L.UNPINNED:format(pin.name))
		end
	end
end

-- At login: what the game tracks for this character is pinned here too.
function P.SyncTracked()
	local ids = C_TradeSkillUI.GetRecipesTracked(false) or {}
	for _, id in ipairs(ids) do
		if not P.Find(id) then
			P.Pin(id, nil, true)
		end
	end
end
