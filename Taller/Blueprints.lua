local _, ns = ...
local L = ns.L

-- Camping blueprints: which ones each of your characters learned or carries, which are missing, and who drops
-- them. Forever does not track them (LFCarry's professions guide: "no tracking feature").
-- Data, checked 16 November 2026: item IDs from mmonster.co and foreverdiff.com (the client's own tables);
-- drop sources from wow-professions.com and mmonster.co (the level 60 dungeons were not in the beta, so the
-- tier 3 sources are from launch); skills follow the hotfixes (6 Nov: Tanning Rack 140 → 125; 10 Nov:
-- Journeyman Campfire Kit 140 → 90). ⏳ nil sources are not known yet; all of it may change.

local B = {}
ns.Blueprints = B

-- { profession, name, item = blueprint item, builds = camp object item, tier, skill, boss, where, also }
B.LIST = {
	{ "Alchemy", "Fermenter", 273085, 279970, 2, 140, "Rath'mael", "Ruins of Lordaeron" },
	{ "Alchemy", "Alchemy Laboratory", 273112, 279990, 3, 300, "Ras Frostwhisper", "Scholomance" },
	{ "Blacksmithing", "Anvil", 273086, 279988, 2, 140, "Gilnid", "The Deadmines" },
	{ "Blacksmithing", "Master Forge", 273113, 279955, 3, 300, "Golem Lord Argelmach", "Blackrock Depths" },
	{ "Cooking", "Journeyman Campfire", 273087, 279961, 2, 90, "Lord Serpentis", "Wailing Caverns" },
	{ "Cooking", "Cookie's Feast", 273102, 279957, 2, 140, "Cookie", "The Deadmines" },
	{ "Cooking", "Expert Campfire", 273101, 279974, 3, 220, "Slavecrusher Grox", "Krol'dok Stronghold" },
	{ "Cooking", "Iron Oven", 273115, 279982, 3, 300, "Quartermaster Zigris", "Lower Blackrock Spire" },
	{ "Enchanting", "Arcane Salvager", 273103, 279985, 2, 140, "Shade of the Archmage", "Dalaran", "Charlga Razorflank, Razorfen Kraul" },
	{ "Enchanting", "Arcane Forge", 273116, 279987, 3, 300, "Nanaya", "Kalimdor" },
	{ "Engineering", "Repair Bot", 273092, 279949, 2, 140, "Sneed", "The Deadmines" },
	{ "Engineering", "Anarchist's Workbench", 273117, 279989, 3, 300, "Ezra Grimm", "Stratholme" },
	{ "Herbalism", "Greenhouse", 273106, 279964, 2, 140, "Shadetooth", "Excavation Site: Wetlands" },
	{ "Herbalism", "Seed Hybridizer", 273120, 279947, 3, 300 },
	{ "Leatherworking", "Tanning Rack", 273096, 279941, 2, 125, "Razorclaw the Butcher", "Shadowfang Keep" },
	{ "Leatherworking", "Sewing Machine", 273121, 279945, 3, 300, "Vectus", "Scholomance" },
	{ "Mining", "Rock Garden", 273097, 279948, 2, 140, "Relic Guardian", "Excavation Site: Wetlands" },
	{ "Mining", "Molten Foundry", 273122, 279952, 3, 300, "Ambassador Flamelash", "Blackrock Depths" },
	{ "Skinning", "Field Guide", 273098, 279969, 2, 140, "Lady Anacondra", "Wailing Caverns" },
	{ "Skinning", "Trapper's Workbench", 273109, 279938, 3, 300, "The Beast", "Upper Blackrock Spire", "Houndmaster Loksey, Scarlet Monastery" },
	{ "Tailoring", "Spinning Wheel", 273099, 279943, 2, 140, "Unstable Sentinel", "Dalaran" },
	{ "Tailoring", "Loom", 273124, 279959, 3, 300, "Baroness Anastari", "Stratholme" },
	{ "First Aid", "Toxin Study", 273105, 279940, 2, 140, "Commander Springvale", "Shadowfang Keep" },
	{ "First Aid", "Plague Doctor's Laboratory", 273118, 279951, 3, 300, "Doctor Theolen Krastinov", "Scholomance" },
	{ "Fishing", "Fishing Rack", 273141, 279965, 2, 140, "Gelihast", "Blackfathom Deeps" },
	{ "Fishing", "Fishing Hut", 273119, 279966, 3, 300, "Jammal'an the Prophet", "Sunken Temple" },
}

B.BY_ITEM, B.BY_BUILD = {}, {}
for _, b in ipairs(B.LIST) do
	local e = { profession = b[1], name = b[2], item = b[3], builds = b[4], tier = b[5], skill = b[6], boss = b[7], where = b[8], also = b[9] }
	B.BY_ITEM[e.item] = e
	B.BY_BUILD[e.builds] = e
end

-- "Gilnid, The Deadmines", with the second known source after it when there is one.
function B.Source(e)
	if not e.boss then
		return L.BP_SOURCE_UNKNOWN
	end
	local source = L.BP_SOURCE:format(e.boss, e.where)
	if e.also then
		source = source .. L.BP_ALSO:format(e.also)
	end
	return source
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

-- Whether any character of the account opened a profession with Taller running (so learned ones count).
function B.AnyScanned()
	for _, c in pairs(ns.db.chars) do
		if c.blueprints then
			return true
		end
	end
	return false
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

-- Rows for the tab, grouped by profession: { header, profession, learned, count } and { e, state, status, source }.
function B.Rows()
	local rows, current, group = {}, nil, nil
	local missing, total = 0, 0
	for _, b in ipairs(B.LIST) do
		local e = B.BY_ITEM[b[3]]
		if e.profession ~= current then
			current = e.profession
			group = { header = L["PROF_" .. e.profession:gsub("[^%a]", ""):upper()] or e.profession, profession = e.profession, learned = 0, count = 0 }
			rows[#rows + 1] = group
		end
		group.count = group.count + 1
		local st = B.State(e)
		local status, state
		if #st.learned > 0 then
			state = "learned"
			group.learned = group.learned + 1
			local names = {}
			for i, k in ipairs(st.learned) do
				names[i] = ns.Short(k)
			end
			status = "|cff40c040" .. L.BP_LEARNED:format(table.concat(names, ", ")) .. "|r"
		elseif st.carried.total > 0 then
			state = "carried"
			local p = st.carried.places[1]
			status = "|cffffd100" .. L.BP_CARRIED:format(p.who == "warband" and L.WARBAND or ns.Short(p.who)) .. "|r"
		else
			state = "missing"
			status = "|cff9d9d9d" .. L.BP_MISSING .. "|r"
			missing = missing + 1
		end
		total = total + 1
		local source = B.Source(e)
		rows[#rows + 1] = {
			e = e,
			left = L.BP_NAME:format(e.name, e.tier, e.skill),
			short = L.BP_SHORT:format(e.name, e.tier),
			status = status,
			state = state,
			source = source,
		}
	end
	rows.missing, rows.total = missing, total
	return rows
end
