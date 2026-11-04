local _, ns = ...
local L = ns.L

-- Camping blueprints: which ones each of your characters learned or carries, which are missing, and who drops
-- them. Forever does not track them (LFCarry's professions guide: "no tracking feature").
-- Data: mmonster.co (blueprint and object item IDs) and wow-professions.com (drop sources), both from the
-- beta. ⏳ "?" sources were not known yet; the rest may change.

local B = {}
ns.Blueprints = B

-- { profession, name, item = blueprint item, builds = camp object item, tier, skill, boss, where }
B.LIST = {
	{ "Alchemy", "Fermenter", 273085, 279970, 2, 140, "Rath'mael", "Ruins of Lordaeron" },
	{ "Alchemy", "Alchemy Laboratory", 273112, 279990, 3, 300 },
	{ "Blacksmithing", "Anvil", 273086, 279988, 2, 140, "Gilnid", "The Deadmines" },
	{ "Blacksmithing", "Master Forge", 273113, 279955, 3, 300 },
	{ "Enchanting", "Arcane Salvager", 273103, 279985, 2, 140, "Shade of the Archmage", "Dalaran" },
	{ "Enchanting", "Arcane Forge", 273116, 279987, 3, 300 },
	{ "Engineering", "Repair Bot", 273092, 279949, 2, 140, "Sneed", "The Deadmines" },
	{ "Engineering", "Anarchist's Workbench", 273117, 279989, 3, 300 },
	{ "Herbalism", "Greenhouse", 273106, 279964, 2, 140, "Shadetooth", "Excavation Site: Wetlands" },
	{ "Herbalism", "Seed Hybridizer", 273120, 279947, 3, 300 },
	{ "Leatherworking", "Tanning Rack", 273096, 279941, 2, 140, "Razorclaw the Butcher", "Shadowfang Keep" },
	{ "Leatherworking", "Sewing Machine", 273121, 279945, 3, 300 },
	{ "Mining", "Rock Garden", 273097, 279948, 2, 140, "Relic Guardian", "Excavation Site: Wetlands" },
	{ "Mining", "Molten Foundry", 273122, 279952, 3, 300 },
	{ "Skinning", "Field Guide", 273098, 279969, 2, 140, "Lady Anacondra", "Wailing Caverns" },
	{ "Skinning", "Trapper's Workbench", 273109, 279938, 3, 300 },
	{ "Tailoring", "Spinning Wheel", 273099, 279943, 2, 140, "Unstable Sentinel", "Dalaran" },
	{ "Tailoring", "Loom", 273124, 279959, 3, 300 },
	{ "First Aid", "Toxin Study", 273105, 279940, 2, 140, "Commander Springvale", "Shadowfang Keep" },
	{ "First Aid", "Plague Doctor's Laboratory", 273118, 279951, 3, 300 },
	{ "Fishing", "Fishing Rack", 273141, 279965, 2, 140, "Gelihast", "Blackfathom Deeps" },
}

B.BY_ITEM, B.BY_BUILD = {}, {}
for _, b in ipairs(B.LIST) do
	local e = { profession = b[1], name = b[2], item = b[3], builds = b[4], tier = b[5], skill = b[6], boss = b[7], where = b[8] }
	B.BY_ITEM[e.item] = e
	B.BY_BUILD[e.builds] = e
end

-- With a profession window open: which camp objects this character knows how to build.
-- Unknown recipes and secret values are skipped; it only ever adds (a recipe is never unlearned).
function B.ScanRecipes()
	local ids = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs() or {}
	local c = ns.Char()
	c.blueprints = c.blueprints or {}
	local found = false
	for _, id in ipairs(ids) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and info.learned == true then
			local s = C_TradeSkillUI.GetRecipeSchematic(id, false)
			local out = s and s.outputItemID
			if out and not issecretvalue(out) and B.BY_BUILD[out] and not c.blueprints[out] then
				c.blueprints[out] = true
				found = true
			end
		end
	end
	if found then
		ns.Fire("blueprints")
	end
end

-- The state of one blueprint across your characters: { learned = { "Ana-Forever" }, carried = Inventory.Count }.
function B.State(e)
	local learned = {}
	for key, c in pairs(ns.db.chars) do
		if c.blueprints and c.blueprints[e.builds] then
			learned[#learned + 1] = key
		end
	end
	table.sort(learned)
	return { learned = learned, carried = ns.Inventory.Count(e.item) }
end

-- Rows for the tab, grouped by profession: { header } and { e, state, status, source }.
function B.Rows()
	local rows, current = {}, nil
	local missing, total = 0, 0
	for _, b in ipairs(B.LIST) do
		local e = B.BY_ITEM[b[3]]
		if e.profession ~= current then
			current = e.profession
			rows[#rows + 1] = { header = L["PROF_" .. e.profession:gsub("[^%a]", ""):upper()] or e.profession }
		end
		local st = B.State(e)
		local status
		if #st.learned > 0 then
			local names = {}
			for i, k in ipairs(st.learned) do
				names[i] = ns.Short(k)
			end
			status = "|cff40c040" .. L.BP_LEARNED:format(table.concat(names, ", ")) .. "|r"
		elseif st.carried.total > 0 then
			local p = st.carried.places[1]
			status = "|cffffd100" .. L.BP_CARRIED:format(p.who == "warband" and L.WARBAND or ns.Short(p.who)) .. "|r"
		else
			status = "|cff9d9d9d" .. L.BP_MISSING .. "|r"
			missing = missing + 1
		end
		total = total + 1
		local source = e.boss and L.BP_SOURCE:format(e.boss, e.where) or L.BP_SOURCE_UNKNOWN
		rows[#rows + 1] = {
			e = e,
			left = L.BP_NAME:format(e.name, e.tier, e.skill),
			status = status,
			source = source,
		}
	end
	rows.missing, rows.total = missing, total
	return rows
end
