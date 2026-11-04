local ADDON, ns = ...
local L = ns.L

-- The window: pinned recipes by profession, each with its materials, or everything added up as a
-- shopping list. Built the first time it opens.

local UI = {}
ns.UI = UI
UI.mode = "profession" -- or "shopping"

local ROW = 22
local GREEN, RED, GREY = "|cff40c040", "|cffff5050", "|cff9d9d9d"

local function whereText(have)
	local parts = {}
	for _, p in ipairs(have.places) do
		local who = p.who == "warband" and L.WARBAND or ns.Short(p.who)
		local where = p.where == "warband" and "" or (" (" .. L[p.where:upper()] .. ")")
		parts[#parts + 1] = p.n .. " " .. who .. where
	end
	return table.concat(parts, ", ")
end

-- Rows for the list, from the pins.
function UI.Rows()
	local rows = {}
	if UI.mode == "blueprints" then
		local bp = ns.Blueprints.Rows()
		rows[#rows + 1] = { kind = "note", text = L.BP_COUNT:format(bp.missing, bp.total) }
		for _, r in ipairs(bp) do
			if r.header then
				rows[#rows + 1] = { kind = "header", text = r.header }
			else
				rows[#rows + 1] = { kind = "bp", bp = r }
			end
		end
		return rows
	end
	if UI.mode == "shopping" then
		for _, s in ipairs(ns.Pins.Shopping()) do
			rows[#rows + 1] = { kind = "reagent", item = s.item, need = s.need, have = s.have }
		end
		return rows
	end
	for _, group in ipairs(ns.Pins.ByProfession()) do
		rows[#rows + 1] = { kind = "header", text = group.profession }
		for _, pin in ipairs(group.pins) do
			rows[#rows + 1] = { kind = "pin", pin = pin }
			for _, n in ipairs(ns.Pins.Needs(pin)) do
				rows[#rows + 1] = { kind = "reagent", item = n.item, need = n.need, have = n.have, indent = true }
			end
		end
	end
	return rows
end

-- What a row says, as plain data (the tests read this; the window draws it).
function UI.Describe(row)
	if row.kind == "header" or row.kind == "note" then
		return { left = row.text }
	elseif row.kind == "bp" then
		return { left = "    " .. row.bp.left .. "  " .. GREY .. row.bp.source .. "|r", right = row.bp.status }
	elseif row.kind == "pin" then
		local p = row.pin
		local who = p.crafter ~= ns.CharKey() and ("  " .. GREY .. L.CRAFTER:format(ns.Short(p.crafter)) .. "|r") or ""
		local per = (p.per or 1) > 1 and ("  " .. GREY .. L.PER_CRAFT:format(p.per) .. "|r") or ""
		return { left = p.name .. "  " .. L.TIMES:format(p.qty) .. per .. who }
	end
	local have = row.have.total
	local missing = math.max(0, row.need - have)
	local made = missing > 0 and ns.Pins.MadeBy(row.item)
	local right = (missing == 0 and GREEN or RED) .. L.HAVE:format(math.min(have, row.need), row.need) .. "|r"
	if missing > 0 then
		right = right .. "  " .. L.MISSING:format(missing)
	end
	local left = (row.indent and "    " or "") .. ns.ItemName(row.item)
	if made then
		left = left .. "  " .. GREY .. L.CRAFTABLE:format(made.name) .. "|r"
	end
	return { left = left, right = right, missing = missing }
end

local function rowTooltip(row)
	local item = row.item
	if item and item.kind == "bp" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(item.bp.e.item)
		GameTooltip:Show()
		return
	end
	if not item or not item.item then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(item.item)
	local places = whereText(item.have)
	if places ~= "" then
		GameTooltip:AddLine(places, 1, 1, 1, true)
	end
	local c = ns.Char()
	if not c.bankSeen then
		GameTooltip:AddLine(L.BANK_NEVER, 0.7, 0.7, 0.7, true)
	elseif time() - c.bankSeen > 86400 then
		GameTooltip:AddLine(L.BANK_OLD:format(ns.Ago(time() - c.bankSeen)), 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end

local function initRow(row, item)
	if not row.left then
		row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.left:SetPoint("LEFT", 6, 0)
		row.left:SetPoint("RIGHT", -150, 0)
		row.left:SetJustifyH("LEFT")
		row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.right:SetPoint("RIGHT", -8, 0)
		row.right:SetJustifyH("RIGHT")
		row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.minus:SetSize(22, 18)
		row.minus:SetText("-")
		row.minus:SetPoint("RIGHT", -60, 0)
		row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.plus:SetSize(22, 18)
		row.plus:SetText("+")
		row.plus:SetPoint("LEFT", row.minus, "RIGHT", 2, 0)
		row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
		row.remove:SetSize(20, 20)
		row.remove:SetPoint("LEFT", row.plus, "RIGHT", 4, 0)
		local function step(sign)
			return function(self)
				local pin = self:GetParent().item.pin
				local by = IsShiftKeyDown() and 10 or (pin.per or 1)
				ns.Pins.SetQty(pin, pin.qty + sign * by)
			end
		end
		row.minus:SetScript("OnClick", step(-1))
		row.plus:SetScript("OnClick", step(1))
		row.remove:SetScript("OnClick", function(self)
			ns.Pins.Unpin(self:GetParent().item.pin)
		end)
		row:SetScript("OnEnter", rowTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
	end
	local d = UI.Describe(item)
	row.left:SetFontObject((item.kind == "reagent" or item.kind == "bp") and "GameFontHighlightSmall" or item.kind == "note" and "GameFontDisableSmall" or "GameFontNormal")
	row.left:SetText(d.left)
	row.right:SetText(d.right or "")
	local isPin = item.kind == "pin"
	row.minus:SetShown(isPin)
	row.plus:SetShown(isPin)
	row.remove:SetShown(isPin)
	row.right:SetShown(not isPin)
end

-- The shopping list as text, to paste in a whisper or for a guildmate who gathers: "20x Linen Cloth (10 missing)".
function UI.ShoppingText()
	local lines = {}
	for _, item in ipairs(ns.Pins.Shopping()) do
		if item.missing > 0 then
			lines[#lines + 1] = L.COPY_LINE:format(item.missing, ns.ItemName(item.item))
		end
	end
	return #lines > 0 and table.concat(lines, ", ") or L.COPY_NOTHING
end

StaticPopupDialogs.TALLER_COPY = {
	text = "%s",
	button1 = OKAY,
	hasEditBox = 1,
	editBoxWidth = 350,
	OnShow = function(dialog, data)
		local edit = dialog:GetEditBox()
		edit:SetText(data or "")
		edit:HighlightText()
		edit:SetFocus()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function UI.Copy()
	StaticPopup_Show("TALLER_COPY", L.COPY_PROMPT, nil, UI.ShoppingText())
end

local function build()
	local FRAME = ADDON .. "Frame"
	local f = CreateFrame("Frame", FRAME, UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(520, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	f.TitleText:SetText(L.TITLE)
	tinsert(UISpecialFrames, FRAME)
	UI.frame = f

	f.tabs = {}
	UI.MODES = { "profession", "shopping", "blueprints" }
	local TAB_TEXT = { profession = L.BY_PROFESSION, shopping = L.SHOPPING, blueprints = L.BLUEPRINTS }
	for i, mode in ipairs(UI.MODES) do
		local tab = CreateFrame("Button", FRAME .. "Tab" .. i, f, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(TAB_TEXT[mode])
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 8, 2)
		else
			tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 3, 0)
		end
		tab:SetScript("OnClick", function()
			UI.SetMode(mode)
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		end)
		f.tabs[i] = tab
	end
	PanelTemplates_SetNumTabs(f, #UI.MODES)

	local box = CreateFrame("Frame", nil, f, "WowScrollBoxList")
	box:SetPoint("TOPLEFT", 12, -32)
	box:SetPoint("BOTTOMRIGHT", -30, 12)
	local bar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW)
	view:SetElementInitializer("Button", function(row, item)
		row.item = item
		initRow(row, item)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	UI.box = box

	f.copy = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.copy:SetSize(120, 20)
	f.copy:SetPoint("TOPRIGHT", -30, -1)
	f.copy:SetText(L.COPY)
	f.copy:SetScript("OnClick", UI.Copy)

	f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.empty:SetPoint("TOPLEFT", 24, -48)
	f.empty:SetPoint("TOPRIGHT", -24, -48)
	f.empty:SetJustifyH("LEFT")
	f.empty:SetWordWrap(true)
	f.empty:SetText(L.EMPTY)

	f:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		UI.Refresh()
	end)
	f:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
	end)
	return f
end

function UI.Refresh()
	local f = UI.frame
	if not f or not f:IsShown() then
		return
	end
	for i, mode in ipairs(UI.MODES) do
		if mode == UI.mode then
			PanelTemplates_SetTab(f, i)
		end
	end
	UI.rows = UI.Rows()
	f.empty:SetShown(#ns.db.pins == 0 and UI.mode ~= "blueprints")
	f.copy:SetShown(UI.mode == "shopping" and #ns.db.pins > 0)
	UI.box:SetDataProvider(CreateDataProvider(UI.rows), ScrollBoxConstants.RetainScrollPosition)
end

function UI.SetMode(mode)
	UI.mode = mode
	UI.Refresh()
end

function UI.Toggle(mode)
	local f = UI.frame or build()
	if mode then
		UI.mode = mode
		f:Show()
		UI.Refresh()
		return
	end
	f:SetShown(not f:IsShown())
end

ns.On("pins", UI.Refresh)
ns.On("inventory", UI.Refresh)
ns.On("blueprints", UI.Refresh)
