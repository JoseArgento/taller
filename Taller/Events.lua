local ADDON, ns = ...
local L = ns.L

local Inv = ns.Inventory

-- Bags change in bursts (looting, sorting): read them once things settle.
local bagsPending = false
local function bagsSoon()
	if bagsPending then
		return
	end
	bagsPending = true
	C_Timer.After(0.5, function()
		bagsPending = false
		Inv.ScanBags()
		Inv.ScanBank()
	end)
end

-- A profession window lists its recipes in bursts: look for camp objects once it settles.
local scanPending = false
local function scanSoon()
	if scanPending then
		return
	end
	scanPending = true
	C_Timer.After(1, function()
		scanPending = false
		ns.Blueprints.ScanRecipes()
	end)
end

local handlers = {
	BAG_UPDATE_DELAYED = bagsSoon,
	PLAYERBANKSLOTS_CHANGED = bagsSoon,
	BANKFRAME_OPENED = function()
		Inv.bankOpen = true
		Inv.ScanBank()
	end,
	BANKFRAME_CLOSED = function()
		Inv.ScanBank() -- last look before it closes (it fires more than once in Forever: harmless here)
		Inv.bankOpen = false
	end,
	TRACKED_RECIPE_UPDATE = function(recipeID, tracked)
		if recipeID and not issecretvalue(recipeID) then
			ns.Pins.OnTracked(recipeID, tracked)
		end
	end,
	UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
		if unit == "player" and spellID and not issecretvalue(spellID) then
			ns.Pins.OnCrafted(spellID)
		end
	end,
	TRADE_SKILL_LIST_UPDATE = function()
		scanSoon()
	end,
	NEW_RECIPE_LEARNED = function()
		scanSoon()
	end,
	GET_ITEM_INFO_RECEIVED = function()
		ns.Fire("inventory") -- an item name arrived: redraw
	end,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			ns.InitDB()
			frame:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		ns.Char()
		Inv.ScanBags()
		ns.Pins.SyncTracked()
		for e in pairs(handlers) do
			frame:RegisterEvent(e)
		end
	elseif handlers[event] then
		handlers[event](...)
	end
end)

SLASH_TALLER1 = "/taller"
SlashCmdList.TALLER = function(msg)
	msg = strtrim((msg or ""):lower())
	if msg == "compras" or msg == "shopping" then
		ns.UI.Toggle("shopping")
	elseif msg == "copiar" or msg == "copy" then
		ns.UI.Copy()
	elseif msg == "planos" or msg == "blueprints" then
		ns.UI.Toggle("blueprints")
	elseif msg == "help" or msg == "ayuda" then
		ns.Print(L.HELP)
	else
		ns.UI.Toggle()
	end
end

function Taller_OnAddonCompartmentClick()
	ns.UI.Toggle()
end
function Taller_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(L.TITLE)
	GameTooltip:AddLine(L.COMPARTMENT, 1, 1, 1)
	GameTooltip:Show()
end
function Taller_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
