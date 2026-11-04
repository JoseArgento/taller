-- What Taller needs on top of wow_mock.lua: recipes, containers and item names.

MOCK.itemNames = {
	[2589] = "Linen Cloth",
	[2996] = "Bolt of Linen Cloth",
	[2320] = "Coarse Thread",
	[2580] = "Brown Linen Shirt",
	[2840] = "Copper Bar",
	[2770] = "Copper Ore",
	[2862] = "Rough Sharpening Stone",
	[2835] = "Rough Stone",
	[2318] = "Light Leather",
}
-- recipeID -> recipe. reagents: { item, n, required = false for optional slots }
MOCK.recipes = {
	[2963] = { name = "Bolt of Linen Cloth", output = 2996, per = 1, profession = "Tailoring", reagents = { { 2589, 2 } } },
	[2386] = {
		name = "Brown Linen Shirt",
		output = 2580,
		per = 1,
		profession = "Tailoring",
		reagents = { { 2996, 1 }, { 2320, 1 }, { 2318, 1, required = false } },
	},
	[2657] = { name = "Smelt Copper", output = 2840, per = 1, profession = "Mining", reagents = { { 2770, 1 } } },
	[2660] = { name = "Rough Sharpening Stone", output = 2862, per = 5, profession = "Blacksmithing", reagents = { { 2835, 1 } } },
}
MOCK.tracked = {}
MOCK.bags = {} -- [bagID] = { { itemID, count }, ... } one entry per slot
MOCK.loadRequests = {}
MOCK.shift = false

Enum.BagIndex = {
	Accountbanktab = -3,
	Characterbanktab = -2,
	Keyring = -1,
	Backpack = 0,
	Bag_1 = 1,
	Bag_2 = 2,
	Bag_3 = 3,
	Bag_4 = 4,
	ReagentBag = 5,
	CharacterBankTab_1 = 6,
	CharacterBankTab_2 = 7,
	AccountBankTab_1 = 15,
	AccountBankTab_2 = 16,
}

function GetNormalizedRealmName()
	return MOCK.player.realm
end
function IsShiftKeyDown()
	return MOCK.shift
end
function GameTooltip_Hide()
	GameTooltip:Hide()
end
SOUNDKIT.UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST = 1
SOUNDKIT.IG_CHARACTER_INFO_TAB = SOUNDKIT.IG_CHARACTER_INFO_TAB or 841

C_Item.GetItemNameByID = function(id)
	return MOCK.itemNames[id]
end
C_Item.RequestLoadItemDataByID = function(id)
	table.insert(MOCK.loadRequests, id)
end

C_Container = {
	GetContainerNumSlots = function(bag)
		return MOCK.bags[bag] and #MOCK.bags[bag] or 0
	end,
	GetContainerItemInfo = function(bag, slot)
		local s = MOCK.bags[bag] and MOCK.bags[bag][slot]
		if s and s[1] then
			return { itemID = s[1], stackCount = s[2], hyperlink = "|Hitem:" .. s[1] .. "|h" }
		end
	end,
}

C_TradeSkillUI = {
	GetRecipeSchematic = function(id, isRecraft)
		assert(isRecraft == false, "GetRecipeSchematic(recipeID, isRecraft)")
		local r = MOCK.recipes[id]
		if not r then
			-- the real one hands back an empty schematic for an unknown recipe
			return { recipeID = id, name = "", quantityMin = 0, quantityMax = 0, reagentSlotSchematics = {} }
		end
		local slots = {}
		for i, x in ipairs(r.reagents) do
			slots[i] = {
				reagents = { { itemID = x[1] } },
				quantityRequired = x[2],
				required = x.required ~= false,
				slotIndex = i,
				dataSlotIndex = i,
			}
		end
		return { recipeID = id, name = r.name, outputItemID = r.output, quantityMin = r.per, quantityMax = r.per, reagentSlotSchematics = slots }
	end,
	GetProfessionInfoByRecipeID = function(id)
		local r = MOCK.recipes[id]
		return { professionID = 0, professionName = r and r.profession or "", skillLevel = 0, maxSkillLevel = 0 }
	end,
	IsRecipeTracked = function(id, isRecraft)
		assert(type(isRecraft) == "boolean", "IsRecipeTracked(recipeID, isRecraft)")
		return MOCK.tracked[id] == true
	end,
	SetRecipeTracked = function(id, tracked, isRecraft)
		assert(type(isRecraft) == "boolean", "SetRecipeTracked(recipeID, tracked, isRecraft)")
		MOCK.tracked[id] = tracked or nil
		MOCK.fire("TRACKED_RECIPE_UPDATE", id, tracked)
	end,
	GetAllRecipeIDs = function()
		local out = {}
		for id in pairs(MOCK.recipes) do
			out[#out + 1] = id
		end
		table.sort(out)
		return out
	end,
	GetRecipeInfo = function(id)
		local r = MOCK.recipes[id]
		if r then
			return { recipeID = id, name = r.name, learned = r.learned ~= false, categoryID = 0 }
		end
	end,
	GetRecipesTracked = function(isRecraft)
		assert(isRecraft == false, "GetRecipesTracked(isRecraft)")
		local out = {}
		for id in pairs(MOCK.tracked) do
			out[#out + 1] = id
		end
		table.sort(out)
		return out
	end,
}

function GameTooltip:SetItemByID(id)
	self.itemID = id
end

-- Put items in a bag: MOCK.put(0, 2589, 10) adds a slot with 10 Linen Cloth to the backpack.
function MOCK.put(bag, itemID, count)
	MOCK.bags[bag] = MOCK.bags[bag] or {}
	table.insert(MOCK.bags[bag], { itemID, count })
end
