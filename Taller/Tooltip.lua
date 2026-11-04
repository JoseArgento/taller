local _, ns = ...
local L = ns.L

-- On an item's tooltip: how many your pins need and how many you have, here and on your other characters.

local function onItem(tooltip, data)
	if not ns.db or not ns.db.settings.tooltip or tooltip ~= GameTooltip then
		return
	end
	local itemID = data and data.id
	if not itemID or issecretvalue(itemID) then
		return
	end
	local bp = ns.Blueprints.BY_ITEM[itemID]
	if bp then
		local st = ns.Blueprints.State(bp)
		if #st.learned > 0 then
			local names = {}
			for i, k in ipairs(st.learned) do
				names[i] = ns.Short(k)
			end
			tooltip:AddLine(L.BP_TIP_LEARNED:format(table.concat(names, ", ")), 0.25, 0.75, 0.25)
		else
			tooltip:AddLine(L.BP_TIP_NONE, 1, 0.82, 0)
		end
		if bp.boss then
			tooltip:AddLine(L.BP_TIP_SOURCE:format(bp.boss, bp.where), 0.7, 0.7, 0.7)
		end
	end
	local need = 0
	for _, s in ipairs(ns.Pins.Shopping()) do
		if s.item == itemID then
			need = s.need
			break
		end
	end
	if need == 0 then
		return
	end
	local have = ns.Inventory.Count(itemID)
	local elsewhere = have.total - have.here
	if elsewhere > 0 then
		local who
		for _, p in ipairs(have.places) do
			if p.who ~= ns.CharKey() then
				who = p.who == "warband" and L.WARBAND or ns.Short(p.who)
				break
			end
		end
		tooltip:AddLine(L.TOOLTIP_ELSEWHERE:format(need, have.here, elsewhere, who), 1, 0.82, 0)
	else
		tooltip:AddLine(L.TOOLTIP_LINE:format(need, have.here), 1, 0.82, 0)
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
