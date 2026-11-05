local _, ns = ...

-- Other addons Taller reads when they are installed. Nothing here is required: without them Taller
-- counts what it scanned itself and shows no prices.
--
--   Syndicator (also bundled inside Baganator): what every character, guild bank and the account bank
--   holds, even characters Taller never saw.
--   Auctionator: an estimated price per material and a total for the shopping list.
--
-- ⏳ The API names below are from memory (their sources could not be fetched when this was written):
--   Syndicator.API.GetInventoryInfoByItemID(itemID, sameConnectedRealm, sameFaction)
--     -> { characters = { { character, realm, bags, bank, mail, equipped, void, auctions } },
--          guilds = { { guild, realm, bank } }, warband = { { bank } } }
--   Syndicator.CallbackRegistry:RegisterCallback("BagCacheUpdate" | "BankCacheUpdate" |
--     "GuildCacheUpdate" | "WarbandBankCacheUpdate", fn)
--   Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID) -> copper or nil
--   Auctionator.API.v1.RegisterForDBUpdate(callerID, fn)
-- Every call goes through pcall and every result is type-checked: if a name or a shape differs, the
-- feature stays hidden instead of breaking the window.

local Partners = {}
ns.Partners = Partners

local CALLER = "Taller"

local function loaded(name)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) == true
end

-- The other addon's global, through _G so the API checker does not take it for a typo of ours.
local function global(name)
	local v = rawget(_G, name)
	return type(v) == "table" and v or nil
end

local function num(v)
	return type(v) == "number" and not issecretvalue(v) and v > 0 and math.floor(v) or nil
end

local function str(v)
	return type(v) == "string" and not issecretvalue(v) and v ~= "" and v or nil
end

-- Syndicator ----------------------------------------------------------------------------------------

function Partners.SyndicatorAPI()
	if not (loaded("Syndicator") or loaded("Baganator")) then
		return nil
	end
	local S = global("Syndicator")
	local api = S and type(S.API) == "table" and S.API
	if api and type(api.GetInventoryInfoByItemID) == "function" then
		return api
	end
	return nil
end

function Partners.HasSyndicator()
	return Partners.SyndicatorAPI() ~= nil
end

-- Where Syndicator says an item is: { { who = "Ana-Forever" | "guild:Name" | "warband", where, n } }, or nil.
function Partners.SyndicatorPlaces(itemID)
	local api = Partners.SyndicatorAPI()
	if not api then
		return nil
	end
	local ok, info = pcall(api.GetInventoryInfoByItemID, itemID, false, false)
	if not ok or type(info) ~= "table" then
		return nil
	end
	local out = {}
	local function add(who, where, n)
		n = num(n)
		if n then
			out[#out + 1] = { who = who, where = where, n = n, via = "Syndicator" }
		end
	end
	if type(info.characters) == "table" then
		for _, c in ipairs(info.characters) do
			local name, realm = type(c) == "table" and str(c.character), type(c) == "table" and str(c.realm)
			if name then
				local who = name .. "-" .. (realm or "?")
				add(who, "bags", (tonumber(c.bags) or 0) + (tonumber(c.equipped) or 0))
				add(who, "bank", c.bank)
				add(who, "mail", c.mail)
			end
		end
	end
	if type(info.guilds) == "table" then
		for _, g in ipairs(info.guilds) do
			local name = type(g) == "table" and str(g.guild)
			if name then
				add("guild:" .. name, "guildbank", g.bank)
			end
		end
	end
	if type(info.warband) == "table" then
		local total = 0
		for _, w in ipairs(info.warband) do
			total = total + (type(w) == "table" and tonumber(w.bank) or 0)
		end
		add("warband", "warband", total)
	end
	return out
end

-- Auctionator ---------------------------------------------------------------------------------------

function Partners.AuctionatorAPI()
	if not loaded("Auctionator") then
		return nil
	end
	local A = global("Auctionator")
	local api = A and type(A.API) == "table" and type(A.API.v1) == "table" and A.API.v1
	if api and type(api.GetAuctionPriceByItemID) == "function" then
		return api
	end
	return nil
end

function Partners.HasPrices()
	return Partners.AuctionatorAPI() ~= nil
end

-- Auctionator's price of one item, in copper, or nil when it has none (or the API is not there).
function Partners.Price(itemID)
	local api = Partners.AuctionatorAPI()
	if not api then
		return nil
	end
	local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
	return ok and num(price) or nil
end

-- "12g 30s 5c" for a price, like the game's own money text.
function Partners.Money(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then
		parts[#parts + 1] = g .. "g"
	end
	if s > 0 or g > 0 then
		parts[#parts + 1] = s .. "s"
	end
	parts[#parts + 1] = c .. "c"
	return table.concat(parts, " ")
end

-- Listen for their updates so the window redraws; each registration may fail quietly.
function Partners.Init()
	local S = Partners.HasSyndicator() and global("Syndicator")
	local reg = S and type(S.CallbackRegistry) == "table" and S.CallbackRegistry
	if reg and type(reg.RegisterCallback) == "function" then
		for _, event in ipairs({ "BagCacheUpdate", "BankCacheUpdate", "GuildCacheUpdate", "WarbandBankCacheUpdate" }) do
			pcall(reg.RegisterCallback, reg, event, function()
				ns.Fire("inventory")
			end)
		end
	end
	local api = Partners.AuctionatorAPI()
	if api and type(api.RegisterForDBUpdate) == "function" then
		pcall(api.RegisterForDBUpdate, CALLER, function()
			ns.Fire("inventory")
		end)
	end
end
