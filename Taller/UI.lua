local ADDON, ns = ...
local L = ns.L

-- how a blueprint's state is coloured on the left page
local TAG_KIND = { learned = "zone", carried = "pinned", missing = "muted" }
local P = Pergamino

-- The window is an open book (Pergamino): three bookmarks. Recetas: the pinned recipes by profession on
-- the left page, the chosen one with its materials on the right. Compras: everything missing added up as a
-- ledger on the left, the same as text to copy on the right. Planos: the camping blueprints by profession,
-- folded, on the left; the chosen blueprint on the right. Built the first time it opens.

local UI = {}
ns.UI = UI
UI.mode = "profession" -- "shopping" or "blueprints"
UI.MODES = { "profession", "shopping", "blueprints" }
UI.open = {} -- blueprint professions unfolded this session: [profession] = true

local ROW = 24
local GREEN, RED, GREY = "|cff2a7a1a", "|cffa0281c", "|cff6c4e31"

local function whereText(have)
	local parts = {}
	for _, p in ipairs(have.places) do
		local who = ns.PlaceName(p.who)
		local where = (p.where == "warband" or p.where == "guildbank") and "" or (" (" .. L[p.where:upper()] .. ")")
		parts[#parts + 1] = p.n .. " " .. who .. where
	end
	local text = table.concat(parts, ", ")
	if have.via then
		text = text .. "  " .. GREY .. L.VIA:format(have.via) .. "|r"
	end
	return text
end
UI.WhereText = whereText

-- data ---------------------------------------------------------------------------------------------------

-- Every row of the current mode, as plain data (the tests read this; the pages draw parts of it).
function UI.Rows()
	local rows = {}
	if UI.mode == "blueprints" then
		local bp = ns.Blueprints.Rows()
		rows[#rows + 1] = { kind = "note", text = L.BP_COUNT:format(bp.missing, bp.total) }
		for _, r in ipairs(bp) do
			if r.header then
				rows[#rows + 1] = { kind = "header", text = r.header, profession = r.profession, learned = r.learned, count = r.count }
			else
				rows[#rows + 1] = { kind = "bp", bp = r }
			end
		end
		return rows
	end
	if UI.mode == "shopping" then
		local list = ns.Pins.Shopping()
		for _, s in ipairs(list) do
			rows[#rows + 1] = { kind = "reagent", item = s.item, need = s.need, have = s.have, price = s.price, cost = s.cost }
		end
		local total = ns.Pins.ShoppingTotal(list)
		if total then
			rows[#rows + 1] = { kind = "note", text = L.TOTAL:format(ns.Partners.Money(total)) }
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

-- What a row says, as plain data.
function UI.Describe(row)
	if row.kind == "header" then
		if row.count then
			return { left = row.text, right = GREY .. L.BP_OF:format(row.learned, row.count) .. "|r" }
		end
		return { left = row.text }
	elseif row.kind == "note" then
		return { left = row.text }
	elseif row.kind == "bp" then
		-- short on the left page (name and tier); skill, who and the drop live on the right page
		return { left = "    " .. row.bp.short, tag = row.bp.state }
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
		if row.cost then
			right = right .. "  " .. GREY .. L.PRICE:format(ns.Partners.Money(row.cost)) .. "|r"
		end
	end
	local left = (row.indent and "    " or "") .. ns.ItemName(row.item)
	if made then
		left = left .. "  " .. GREY .. L.CRAFTABLE:format(made.name) .. "|r"
	end
	return { left = left, right = right, missing = missing }
end

-- Rows of the left page: the pins (no reagents) or the ledger, or the folded blueprint professions.
function UI.LeftRows()
	local rows = UI.Rows()
	local out = {}
	if UI.mode == "profession" then
		for _, r in ipairs(rows) do
			if r.kind ~= "reagent" then
				out[#out + 1] = r
			end
		end
	elseif UI.mode == "blueprints" then
		local scanned = ns.Blueprints.AnyScanned()
		for _, r in ipairs(rows) do
			if r.kind == "note" then
				if not scanned then
					out[#out + 1] = { kind = "note", text = L.BP_OPEN_ONCE }
				end
			elseif r.kind == "header" then
				r.open = UI.open[r.profession] and true or false
				out[#out + 1] = r
			elseif UI.open[r.bp.e.profession] then
				out[#out + 1] = r
			end
		end
	else
		out = rows
	end
	return out
end

-- Whether a pin or a blueprint is missing enough to matter: how many of its materials are short.
local function pinShort(pin)
	local short = 0
	for _, n in ipairs(ns.Pins.Needs(pin)) do
		if n.have.total < n.need then
			short = short + 1
		end
	end
	return short
end

-- The shopping list as text, to paste in a whisper or for a guildmate who gathers: "20x Linen Cloth (10 missing)".
function UI.ShoppingText()
	local lines = {}
	local list = ns.Pins.Shopping()
	for _, item in ipairs(list) do
		if item.missing > 0 then
			local line = L.COPY_LINE:format(item.missing, ns.ItemName(item.item))
			if item.cost then
				line = line .. " " .. L.PRICE:format(ns.Partners.Money(item.cost))
			end
			lines[#lines + 1] = line
		end
	end
	if #lines == 0 then
		return L.COPY_NOTHING
	end
	local text = table.concat(lines, ", ")
	local total = ns.Pins.ShoppingTotal(list)
	if total then
		text = text .. ". " .. L.TOTAL:format(ns.Partners.Money(total))
	end
	return text
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

-- pieces -------------------------------------------------------------------------------------------------

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

local FONT_OF = { header = "heading", pin = "strong", reagent = "body", bp = "body", note = "muted" }

-- A row of a list: left text, right text, the ink of its kind, and the selection when it is the chosen one.
local function initRow(row, item)
	if not row.left then
		row.left = P.Label(row, "", "body")
		row.left:SetPoint("LEFT", 6, 0)
		row.left:SetPoint("RIGHT", -8, 0)
		row.left:SetWordWrap(false)
		row.right = P.Label(row, "", "small", "RIGHT")
		row.right:SetPoint("RIGHT", -8, 0)
		row.fold = P.Label(row, "", "subheading")
		row.fold:SetPoint("LEFT", 0, 0)
		row:SetScript("OnEnter", rowTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
	end
	local d = UI.Describe(item)
	row.left:SetFontObject(P.fonts[FONT_OF[item.kind] or "body"])
	local isFold = item.kind == "header" and item.count ~= nil
	row.fold:SetText(isFold and (item.open and "v" or ">") or "")
	row.left:SetPoint("LEFT", isFold and 16 or 6, 0)
	row.left:SetText(d.left)
	row.right:SetText(d.right or "")
	row.right:SetShown((d.right or "") ~= "")
	if d.tag then
		-- a blueprint's state as a small seal on the right (learned / carried / missing)
		if not row.tag then
			row.tag = P.Tag(row, "", "note")
			row.tag:SetPoint("RIGHT", -8, 0)
		end
		row.tag:Set(L["BP_STATE_" .. d.tag:upper()], TAG_KIND[d.tag])
		row.tag:Show()
	elseif row.tag then
		row.tag:Hide()
	end
	row.left:SetPoint("RIGHT", ((d.right or "") ~= "" or d.tag) and -110 or -8, 0)
	local chosen = (item.kind == "pin" and item.pin == UI.pin) or (item.kind == "bp" and item.bp.e == UI.blueprint)
	row.selected:SetShown(chosen)
end

-- Clicking a row chooses a pin or a blueprint, or folds a profession.
local function onRowClick(item)
	if item.kind == "pin" then
		UI.pin = item.pin
		UI.Refresh()
	elseif item.kind == "bp" then
		UI.blueprint = item.bp.e
		UI.Refresh()
	elseif item.kind == "header" and item.count ~= nil then
		UI.open[item.profession] = not UI.open[item.profession]
		UI.Refresh()
	end
end

-- The right page of Recetas: the chosen pin with its materials, how many you want, and the unpin.
local function buildRecipePage(page)
	local r = {}
	r.title = P.Label(page, "", "heading")
	r.title:SetPoint("TOPLEFT")
	r.title:SetPoint("TOPRIGHT")
	r.sub = P.Label(page, "", "muted")
	r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
	r.sub:SetPoint("RIGHT")
	r.qtyLabel = P.Label(page, L.QTY, "body")
	r.qtyLabel:SetPoint("TOPLEFT", r.sub, "BOTTOMLEFT", 0, -12)
	-- What is typed applies on Enter or when the field loses focus, never while typing; the buttons drop the
	-- focus first, and the refresh always writes the real quantity back (the game once showed "41" for 4).
	local function applyTyped(self)
		if UI.pin then
			ns.Pins.SetQty(UI.pin, tonumber(self:GetText()) or UI.pin.qty)
			if r.qty then
				r.qty:SetText(tostring(UI.pin.qty))
			end
		end
	end
	r.qty = P.Edit(page, 60, { onEnter = applyTyped })
	r.qty:SetPoint("LEFT", r.qtyLabel, "RIGHT", 8, 0)
	r.qty:SetNumeric(true)
	r.qty:HookScript("OnEditFocusLost", applyTyped)
	local function step(sign)
		return function()
			r.qty:ClearFocus()
			if UI.pin then
				ns.Pins.SetQty(UI.pin, UI.pin.qty + sign * (IsShiftKeyDown() and 10 or (UI.pin.per or 1)))
			end
		end
	end
	r.minus = P.Button(page, "-", 36, step(-1))
	r.minus:SetPoint("LEFT", r.qty, "RIGHT", 8, 0)
	r.minus:SetHeight(36)
	r.minus:SetNormalFontObject(P.fonts.title)
	r.minus:SetHighlightFontObject(P.fonts.title)
	r.plus = P.Button(page, "+", 36, step(1))
	r.plus:SetPoint("LEFT", r.minus, "RIGHT", 4, 0)
	r.plus:SetHeight(36)
	r.plus:SetNormalFontObject(P.fonts.title)
	r.plus:SetHighlightFontObject(P.fonts.title)
	r.plus:SetPoint("LEFT", r.minus, "RIGHT", 4, 0)
	r.remove = P.Button(page, L.REMOVE, 100, function()
		if UI.pin then
			ns.Pins.Unpin(UI.pin)
		end
	end)
	r.remove:SetPoint("BOTTOMRIGHT")
	r.rule = P.Rule(page)
	r.rule:SetPoint("TOPLEFT", r.qtyLabel, "BOTTOMLEFT", 0, -10)
	r.rule:SetPoint("RIGHT")
	r.matsTitle = P.Label(page, L.MATERIALS, "subheading")
	r.matsTitle:SetPoint("TOPLEFT", r.rule, "BOTTOMLEFT", 0, -8)
	r.list = P.List(page, 34, function(row, item)
		if not row.name then
			row.name = P.Label(row, "", "body")
			row.name:SetPoint("TOPLEFT", 4, -2)
			row.name:SetPoint("RIGHT", -100, 0)
			row.name:SetWordWrap(false)
			row.have = P.Label(row, "", "strong", "RIGHT")
			row.have:SetPoint("TOPRIGHT", -4, -2)
			row.where = P.Label(row, "", "small")
			row.where:SetPoint("BOTTOMLEFT", 4, 2)
			row.where:SetPoint("RIGHT", -4, 0)
			row.where:SetWordWrap(false)
			row:SetScript("OnEnter", rowTooltip)
			row:SetScript("OnLeave", GameTooltip_Hide)
		end
		local d = UI.Describe(item)
		row.name:SetText(d.left)
		row.have:SetText(d.right or "")
		local where = whereText(item.have)
		row.where:SetText(where ~= "" and where or GREY .. L.NONE_YET .. "|r")
	end)
	r.list.box:SetPoint("TOPLEFT", r.matsTitle, "BOTTOMLEFT", 0, -4)
	r.list.box:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -14, 34)
	r.empty = P.Label(page, L.PICK_RECIPE, "muted")
	r.empty:SetPoint("TOPLEFT", 0, -6)
	r.empty:SetPoint("RIGHT")
	r.empty:SetWordWrap(true)
	function r.Refresh()
		local pin = UI.pin
		local has = pin ~= nil
		for _, w in ipairs({ r.title, r.sub, r.qtyLabel, r.qty, r.minus, r.plus, r.remove, r.rule, r.matsTitle, r.list.box, r.list.bar }) do
			w:SetShown(has)
		end
		r.empty:SetShown(not has)
		if not has then
			return
		end
		r.title:SetText(pin.name)
		local crafts = ns.Pins.Crafts(pin)
		local bits = { (crafts == 1 and L.CRAFT_ONE or L.CRAFTS):format(crafts) }
		if (pin.per or 1) > 1 then
			bits[#bits + 1] = L.PER_CRAFT:format(pin.per)
		end
		if pin.crafter ~= ns.CharKey() then
			bits[#bits + 1] = L.CRAFTER:format(ns.Short(pin.crafter))
		end
		local short = pinShort(pin)
		bits[#bits + 1] = short == 0 and L.ALL_READY or L.SHORT:format(short)
		r.sub:SetText(table.concat(bits, " · "))
		r.qty:SetText(tostring(pin.qty))
		local items = {}
		for _, n in ipairs(ns.Pins.Needs(pin)) do
			items[#items + 1] = { kind = "reagent", item = n.item, need = n.need, have = n.have }
		end
		r.list:SetData(items, true)
	end
	return r
end

-- The right page of Compras: the list as text, ready to copy.
local function buildCopyPage(page)
	local r = {}
	r.title = P.Label(page, L.COPY_TITLE, "heading")
	r.title:SetPoint("TOPLEFT")
	r.hint = P.Label(page, L.COPY_HINT, "muted")
	r.hint:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
	r.hint:SetPoint("RIGHT")
	r.hint:SetWordWrap(true)
	r.area = P.TextArea(page)
	r.area:SetPoint("TOPLEFT", r.hint, "BOTTOMLEFT", -4, -10)
	r.area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 36)
	r.select = P.Button(page, L.COPY, 130, function()
		local edit = r.area.box:GetEditBox()
		if edit then
			edit:SetFocus()
			edit:HighlightText()
		end
	end)
	r.select:SetPoint("BOTTOMRIGHT")
	function r.Refresh()
		local edit = r.area.box:GetEditBox()
		local text = UI.ShoppingText()
		if edit and not edit:HasFocus() then
			edit:SetText(text)
		end
		r.text = text
	end
	return r
end

-- The right page of Planos: the chosen blueprint.
local function buildBlueprintPage(page)
	local r = {}
	r.title = P.Label(page, "", "heading")
	r.title:SetPoint("TOPLEFT")
	r.title:SetPoint("TOPRIGHT")
	r.sub = P.Label(page, "", "muted")
	r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
	r.sub:SetPoint("RIGHT")
	r.rule = P.Rule(page)
	r.rule:SetPoint("TOPLEFT", r.sub, "BOTTOMLEFT", 0, -10)
	r.rule:SetPoint("RIGHT")
	r.lines = {}
	local prev = r.rule
	for i = 1, 4 do
		local head = P.Label(page, "", "subheading")
		head:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12)
		local body = P.Label(page, "", "body")
		body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
		body:SetPoint("RIGHT")
		body:SetWordWrap(true)
		r.lines[i] = { head = head, body = body }
		prev = body
	end
	r.note = P.Label(page, L.BP_BETA, "muted")
	r.note:SetPoint("BOTTOMLEFT")
	r.note:SetPoint("RIGHT")
	r.note:SetWordWrap(true)
	r.empty = P.Label(page, L.PICK_BLUEPRINT, "muted")
	r.empty:SetPoint("TOPLEFT", 0, -6)
	r.empty:SetPoint("RIGHT")
	r.empty:SetWordWrap(true)
	function r.Refresh()
		local e = UI.blueprint
		local has = e ~= nil
		for _, w in ipairs({ r.title, r.sub, r.rule, r.note }) do
			w:SetShown(has)
		end
		for _, l in ipairs(r.lines) do
			l.head:SetShown(has)
			l.body:SetShown(has)
		end
		r.empty:SetShown(not has)
		if not has then
			return
		end
		local st = ns.Blueprints.State(e)
		r.title:SetText(e.name)
		r.sub:SetText(L.BP_SUB:format(L["PROF_" .. e.profession:gsub("[^%a]", ""):upper()] or e.profession, e.tier, e.skill))
		local who
		if #st.learned > 0 then
			local names = {}
			for i, k in ipairs(st.learned) do
				names[i] = ns.Short(k)
			end
			who = GREEN .. L.BP_LEARNED:format(table.concat(names, ", ")) .. "|r"
		else
			who = L.BP_NOBODY
		end
		local carried = st.carried.total > 0 and whereText(st.carried) or L.BP_NOT_CARRIED
		local source = e.boss and L.BP_SOURCE:format(e.boss, e.where) or L.BP_SOURCE_UNKNOWN
		local texts = {
			{ L.BP_WHO, who },
			{ L.BP_WHERE, carried },
			{ L.BP_DROP, source },
			{ L.BP_BUILDS, ns.ItemName(e.builds) },
		}
		for i, t in ipairs(texts) do
			r.lines[i].head:SetText(t[1])
			r.lines[i].body:SetText(t[2])
		end
	end
	return r
end

-- the book -----------------------------------------------------------------------------------------------

local TIP_OF = { profession = "TIP_RECIPES", shopping = "TIP_SHOPPING", blueprints = "TIP_BLUEPRINTS" }
local TAB_OF = { profession = "TAB_PROFESSION", shopping = "TAB_SHOPPING", blueprints = "TAB_BLUEPRINTS" }
local HEAD_OF = { profession = "BY_PROFESSION", shopping = "SHOPPING", blueprints = "BLUEPRINTS" }

local function build()
	local FRAME = ADDON .. "Frame"
	local f = P.Book(FRAME, { title = L.TITLE })
	UI.frame = f
	f.TitleText = f.title
	f.OnMoved = function(point, _, relPoint, x, y)
		ns.db.settings.point = { point, relPoint, x, y }
	end
	f.OnTab = function(key)
		if UI.mode ~= key then
			UI.mode = key
			UI.Refresh()
		end
	end

	f.pages = f.pages or {}
	UI.views = {}
	for _, mode in ipairs(UI.MODES) do
		local tab = f:AddTab(mode, L[TAB_OF[mode]])
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(L[TAB_OF[mode]])
			GameTooltip:AddLine(L[TIP_OF[mode]], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", GameTooltip_Hide)
		local page = f:AddPage(mode)
		local v = { page = page }
		v.heading = P.Label(page.left, L[HEAD_OF[mode]], "heading")
		v.heading:SetPoint("TOPLEFT")
		v.count = P.Label(page.left, "", "muted", "RIGHT")
		v.count:SetPoint("TOPRIGHT")
		v.rule = P.Rule(page.left)
		v.rule:SetPoint("TOPLEFT", v.heading, "BOTTOMLEFT", 0, -6)
		v.rule:SetPoint("RIGHT")
		v.list = P.List(page.left, ROW, initRow, onRowClick)
		v.list.box:SetPoint("TOPLEFT", v.rule, "BOTTOMLEFT", 0, -6)
		v.list.box:SetPoint("BOTTOMRIGHT", page.left, "BOTTOMRIGHT", -14, 0)
		v.empty = P.Label(page.left, "", "muted")
		v.empty:SetPoint("TOPLEFT", v.rule, "BOTTOMLEFT", 0, -10)
		v.empty:SetPoint("RIGHT")
		v.empty:SetWordWrap(true)
		if mode == "profession" then
			v.right = buildRecipePage(page.right)
		elseif mode == "shopping" then
			v.right = buildCopyPage(page.right)
		else
			v.right = buildBlueprintPage(page.right)
		end
		UI.views[mode] = v
	end
	UI.Relabel()

	local p = ns.db.settings.point
	if p then
		f:ClearAllPoints()
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	end
	f:HookScript("OnShow", UI.Refresh)
	return f
end

-- Static texts, in the current language (also after /taller idioma).
function UI.Relabel()
	local f = UI.frame
	if not f then
		return
	end
	f:SetTitle(L.TITLE)
	for _, mode in ipairs(UI.MODES) do
		f.tabs[mode]:SetText(L[TAB_OF[mode]])
		local v = UI.views[mode]
		v.heading:SetText(L[HEAD_OF[mode]])
		local r = v.right
		if mode == "profession" then
			r.qtyLabel:SetText(L.QTY)
			r.remove:SetText(L.REMOVE)
			r.matsTitle:SetText(L.MATERIALS)
			r.empty:SetText(L.PICK_RECIPE)
		elseif mode == "shopping" then
			r.title:SetText(L.COPY_TITLE)
			r.hint:SetText(L.COPY_HINT)
			r.select:SetText(L.COPY)
		else
			r.note:SetText(L.BP_BETA)
			r.empty:SetText(L.PICK_BLUEPRINT)
		end
	end
end

function UI.Refresh()
	local f = UI.frame
	if not f or not f:IsShown() then
		return
	end
	if f.selected ~= UI.mode then
		f:SelectTab(UI.mode)
	end
	UI.rows = UI.Rows()
	-- a pin that is gone is no longer chosen; with none chosen, the first one is
	if UI.pin and not ns.Pins.Find(UI.pin.recipe, UI.pin.crafter) then
		UI.pin = nil
	end
	if not UI.pin then
		UI.pin = ns.db.pins[1]
	end
	local v = UI.views[UI.mode]
	local left = UI.LeftRows()
	UI.left = left
	v.list:SetData(left, true)
	local emptyText
	if UI.mode == "profession" and #ns.db.pins == 0 then
		emptyText = L.EMPTY
	elseif UI.mode == "shopping" and #ns.db.pins == 0 then
		emptyText = L.EMPTY_SHOPPING
	end
	v.empty:SetText(emptyText or "")
	v.empty:SetShown(emptyText ~= nil)
	v.list.box:SetShown(emptyText == nil)
	v.list.bar:SetShown(emptyText == nil)
	if UI.mode == "profession" then
		v.count:SetText(#ns.db.pins > 0 and L.PINNED_COUNT:format(#ns.db.pins) or "")
	elseif UI.mode == "shopping" then
		local missing = 0
		for _, r in ipairs(UI.rows) do
			if r.kind == "reagent" and r.need > r.have.total then
				missing = missing + 1
			end
		end
		v.count:SetText(#ns.db.pins > 0 and L.MISSING_COUNT:format(missing) or "")
	else
		local bp = ns.Blueprints.Rows()
		v.count:SetText(L.BP_OF:format(bp.total - bp.missing, bp.total))
	end
	v.right.Refresh()
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
ns.On("language", function()
	UI.Relabel()
	UI.Refresh()
end)
