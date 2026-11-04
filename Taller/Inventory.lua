local _, ns = ...

-- What each character holds. The bags are read whenever they change; the bank only while it is open,
-- so it is what you had the last time you visited. The account bank is one for every character.

local Inv = {}
ns.Inventory = Inv

local function bagIDs(pattern)
	local ids = {}
	for name, id in pairs(Enum.BagIndex or {}) do
		if name:match(pattern) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	return ids
end

-- Backpack, the 4 bags and the reagent bag.
function Inv.BagIDs()
	local ids = { 0 }
	local b = Enum.BagIndex or {}
	for _, k in ipairs({ "Bag_1", "Bag_2", "Bag_3", "Bag_4", "ReagentBag" }) do
		if b[k] then
			ids[#ids + 1] = b[k]
		end
	end
	return ids
end
function Inv.BankIDs()
	return bagIDs("^CharacterBankTab_%d+$")
end
function Inv.WarbandIDs()
	return bagIDs("^AccountBankTab_%d+$")
end

local function scan(ids)
	local items = {}
	for _, bag in ipairs(ids) do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not issecretvalue(info.itemID) and not issecretvalue(info.stackCount) then
				items[info.itemID] = (items[info.itemID] or 0) + (info.stackCount or 1)
			end
		end
	end
	return items
end

function Inv.ScanBags()
	ns.Char().bags = scan(Inv.BagIDs())
	ns.Fire("inventory")
end

Inv.bankOpen = false
function Inv.ScanBank()
	if not Inv.bankOpen then
		return
	end
	local c = ns.Char()
	c.bank = scan(Inv.BankIDs())
	c.bankSeen = time()
	local ids = Inv.WarbandIDs()
	if #ids > 0 then
		ns.db.warband.items = scan(ids)
		ns.db.warband.seen = time()
	end
	ns.Fire("inventory")
end

-- How many of an item you have, and where: { total, here = bags + bank of this character,
-- places = { { who = "Ana-Forever" | "warband", where = "bags" | "bank", n } } }.
function Inv.Count(itemID)
	local me = ns.CharKey()
	local out = { total = 0, here = 0, places = {} }
	local function add(who, where, n)
		if n and n > 0 then
			out.total = out.total + n
			if who == me then
				out.here = out.here + n
			end
			out.places[#out.places + 1] = { who = who, where = where, n = n }
		end
	end
	local keys = {}
	for key in pairs(ns.db.chars) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		if (a == me) ~= (b == me) then
			return a == me
		end
		return a < b
	end)
	for _, key in ipairs(keys) do
		local c = ns.db.chars[key]
		add(key, "bags", c.bags and c.bags[itemID])
		add(key, "bank", c.bank and c.bank[itemID])
	end
	add("warband", "warband", ns.db.warband.items[itemID])
	return out
end
