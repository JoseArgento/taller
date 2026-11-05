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

local onSlash -- the /taller handler, defined below; guarded once the saved variables are in
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			ns.InitDB()
			frame:UnregisterEvent("ADDON_LOADED")
			-- from here on a Lua error in a handler is kept, not thrown (see /taller errores)
			SlashCmdList.TALLER = ns.guard.Install(frame, onSlash)
		end
	elseif event == "PLAYER_LOGIN" then
		ns.Char()
		ns.MinimapButton()
		ns.Partners.Init()
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
onSlash = function(msg)
	msg = strtrim((msg or ""):lower())
	if msg == "compras" or msg == "shopping" then
		ns.UI.Toggle("shopping")
	elseif msg == "copiar" or msg == "copy" then
		ns.UI.Copy()
	elseif msg == "planos" or msg == "blueprints" then
		ns.UI.Toggle("blueprints")
	elseif msg:match("^idioma") or msg:match("^language") or msg:match("^lang") then
		local code = msg:match("%s+(%a+)$")
		if code == "es" or code == "en" or code == "auto" then
			ns.db.settings.lang = code
			ns.ApplyLanguage(code)
			ns.Print(L.LANG_SET:format(L.LANG_NAMES[code]))
		else
			ns.Print(L.LANG_USAGE)
		end
	elseif msg:match("^minimap") then
		local what = msg:match("%s+(%a+)$")
		if what == "on" or what == "off" then
			ns.db.settings.minimap = what == "on"
			ns.MinimapButton()
			ns.Print(ns.db.settings.minimap and L.MINIMAP_ON or L.MINIMAP_OFF)
		else
			ns.Print(L.MINIMAP_USAGE)
		end
	elseif msg == "errores" or msg == "errors" then
		ns.UI.Toggle("errors")
	elseif msg == "help" or msg == "ayuda" then
		ns.Print(L.HELP)
	else
		ns.UI.Toggle()
	end
end
SlashCmdList.TALLER = onSlash

-- The round button on the minimap's edge (Pergamino): left click opens the book, right click the blueprints.
-- Made once; the setting shows or hides it.
function ns.MinimapButton()
	if not ns.minimapButton then
		ns.minimapButton = Pergamino.MinimapButton("TallerMinimapButton", {
			icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon",
			angle = ns.db.settings.minimapAngle,
			onMove = function(angle)
				ns.db.settings.minimapAngle = angle
			end,
			onClick = function(button)
				ns.UI.Toggle(button == "RightButton" and "blueprints" or nil)
			end,
			tooltip = function(tip)
				tip:SetText(L.TITLE)
				tip:AddLine(L.MINIMAP_TIP, 1, 1, 1, true)
			end,
		})
	end
	ns.minimapButton:SetShown(ns.db.settings.minimap ~= false)
	return ns.minimapButton
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

-- Key binding (Bindings.xml) and its names in the key bindings panel.
_G["Taller_Toggle"] = function()
	ns.UI.Toggle()
end
_G["BINDING_HEADER_TALLER"] = "Taller"
_G["BINDING_NAME_TALLER_TOGGLE"] = L.BINDING_TOGGLE
