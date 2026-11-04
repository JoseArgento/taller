local _, ns = ...

-- English is the fallback; Spanish for esES and esMX.
local L = {
	TITLE = "Taller",
	SHOPPING = "Shopping list",
	BY_PROFESSION = "By profession",
	EMPTY = "Nothing pinned yet. Open a profession, pick a recipe and tick \"Track\": it shows up here.",
	CRAFTER = "made by %s",
	NEED = "%d needed",
	HAVE = "%d / %d",
	MISSING = "%d missing",
	READY = "ready",
	ALL_READY = "You have everything for this one.",
	BAGS = "bags",
	BANK = "bank",
	WARBAND = "account bank",
	CRAFTABLE = "you can craft it (%s)",
	TIMES = "x%d",
	PER_CRAFT = "%d per craft",
	BANK_OLD = "Bank last seen %s ago.",
	BANK_NEVER = "Visit your bank once so its items count.",
	TOOLTIP_LINE = "Taller: %d needed, %d here",
	TOOLTIP_ELSEWHERE = "Taller: %d needed, %d here, %d on %s",
	DONE = "Done: %s.",
	PINNED = "Pinned: %s.",
	UNPINNED = "Unpinned: %s.",
	NOT_A_RECIPE = "Could not read that recipe. Open its profession once and try again.",
	REMOVE = "Unpin",
	HELP = "/taller opens the list. /taller compras shows the shopping list. Pin recipes with the profession window's \"Track\" box.",
	COMPARTMENT = "Click to open your crafting list.",
	OTHER = "Other",
	UNKNOWN_ITEM = "item %d",
}

local es = {
	TITLE = "Taller",
	SHOPPING = "Lista de compras",
	BY_PROFESSION = "Por profesión",
	EMPTY = "Todavía no pineaste nada. Abrí una profesión, elegí una receta y tildá la casilla para seguirla: aparece acá.",
	CRAFTER = "la hace %s",
	NEED = "faltan %d",
	HAVE = "%d / %d",
	MISSING = "faltan %d",
	READY = "listo",
	ALL_READY = "Tenés todo para esta.",
	BAGS = "bolsas",
	BANK = "banco",
	WARBAND = "banco de cuenta",
	CRAFTABLE = "la podés craftear (%s)",
	TIMES = "x%d",
	PER_CRAFT = "%d por crafteo",
	BANK_OLD = "El banco lo viste hace %s.",
	BANK_NEVER = "Pasá una vez por el banco para que cuente lo que hay.",
	TOOLTIP_LINE = "Taller: necesitás %d, tenés %d acá",
	TOOLTIP_ELSEWHERE = "Taller: necesitás %d, tenés %d acá y %d en %s",
	DONE = "Listo: %s.",
	PINNED = "Pineada: %s.",
	UNPINNED = "Despineada: %s.",
	NOT_A_RECIPE = "No pude leer esa receta. Abrí su profesión una vez y probá de nuevo.",
	REMOVE = "Despinear",
	HELP = "/taller abre la lista. /taller compras muestra la lista de compras. Las recetas se pinean con la casilla para seguir la receta, en la ventana de profesiones.",
	COMPARTMENT = "Clic para abrir tu lista de crafteos.",
	OTHER = "Otras",
	UNKNOWN_ITEM = "objeto %d",
}

local locale = GetLocale()
if locale == "esES" or locale == "esMX" then
	for k, v in pairs(es) do
		L[k] = v
	end
end
ns.L = L
