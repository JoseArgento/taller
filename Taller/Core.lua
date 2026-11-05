local ADDON, ns = ...
local L = ns.L

-- Saved data (TallerDB), shared by every character of the account:
--   chars[Name-Realm] = { bags = { [itemID] = n }, bank = { [itemID] = n }, bankSeen = time }
--   warband = { items = { [itemID] = n }, seen = time }       the account bank, the same for everyone
--   pins = { { recipe, qty, crafter, profession, name, output, per, reagents = { { item, n } }, at } }
--   settings = { tooltip = true, lang = "auto" | "es" | "en", point = where the book was left,
--                minimap = true (show the minimap button), minimapAngle = where it sits around the minimap }

local listeners = {}
function ns.On(topic, fn)
	listeners[topic] = listeners[topic] or {}
	table.insert(listeners[topic], fn)
end
function ns.Fire(topic, ...)
	for _, fn in ipairs(listeners[topic] or {}) do
		fn(...)
	end
end

function ns.InitDB()
	if type(TallerDB) ~= "table" then
		TallerDB = {}
	end
	local db = TallerDB
	db.version = 1
	db.chars = type(db.chars) == "table" and db.chars or {}
	db.warband = type(db.warband) == "table" and db.warband or { items = {} }
	db.warband.items = db.warband.items or {}
	db.pins = type(db.pins) == "table" and db.pins or {}
	db.settings = type(db.settings) == "table" and db.settings or {}
	if db.settings.tooltip == nil then
		db.settings.tooltip = true
	end
	if db.settings.lang ~= "es" and db.settings.lang ~= "en" then
		db.settings.lang = "auto"
	end
	if db.settings.minimap == nil then
		db.settings.minimap = true
	end
	ns.db = db
	ns.ApplyLanguage(db.settings.lang)
end

function ns.CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName() or GetRealmName() or "?")
end

function ns.Char(key)
	key = key or ns.CharKey()
	local c = ns.db.chars[key]
	if not c then
		c = { bags = {}, bank = {} }
		ns.db.chars[key] = c
	end
	return c
end

-- "Ana-Forever" -> "Ana" for characters of this realm.
function ns.Short(key)
	local name, realm = key:match("^(.-)%-(.+)$")
	if name and realm == (GetNormalizedRealmName() or GetRealmName()) then
		return name
	end
	return key
end

-- The name of a place from Inventory.Count: a character, "account bank", or a guild bank.
function ns.PlaceName(who)
	if who == "warband" then
		return L.WARBAND
	end
	return who:match("^guild:(.+)$") or ns.Short(who)
end

function ns.ItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if not name or issecretvalue(name) then
		C_Item.RequestLoadItemDataByID(itemID) -- GET_ITEM_INFO_RECEIVED refreshes the window
		return L.UNKNOWN_ITEM:format(itemID)
	end
	return name
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. L.TITLE .. ":|r " .. msg)
end

function ns.Ago(seconds)
	if seconds < 3600 then
		return math.max(1, math.floor(seconds / 60)) .. " min"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. " h"
	end
	return math.floor(seconds / 86400) .. " d"
end

ns.ADDON = ADDON

-- A small public API for other addons (Trueque uses it): the shopping list as plain data, nothing else.
-- Each entry: { item = itemID, name = item name, need = total wanted, have = owned, missing = still to get }.
Taller_API = {
	VERSION = 1,
	ShoppingList = function()
		local out = {}
		if not ns.db or not ns.Pins then
			return out
		end
		for _, s in ipairs(ns.Pins.Shopping()) do
			out[#out + 1] = { item = s.item, name = ns.ItemName(s.item), need = s.need, have = s.have.total, missing = s.missing }
		end
		return out
	end,
}
