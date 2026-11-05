"""Taller running in Lua 5.1 (the Lua of WoW) on a small stand-in for the client.

Several characters of the same account share one TallerDB, the way the client does: a test logs one out
(its SavedVariables are written) and the next one in.
"""

from __future__ import annotations

from pathlib import Path

import pytest

lupa = pytest.importorskip("lupa.lua51")

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "Taller"
TESTS = Path(__file__).resolve().parent


def toc_files():
    lines = (ADDON / "Taller.toc").read_text(encoding="utf-8").splitlines()
    return [ln.strip().replace("\\", "/") for ln in lines if ln.strip() and not ln.startswith("#") and ln.strip().endswith(".lua")]


class Client:
    def __init__(self, name="Josecito", locale="enUS", saved=None):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((TESTS / "wow_mock.lua").read_text(encoding="utf-8"))
        self.lua.execute((TESTS / "taller_mock.lua").read_text(encoding="utf-8"))
        self.m = self.lua.globals().MOCK
        self.m.player.name = name
        self.m.locale = locale
        if saved is not None:
            self.lua.execute(saved)
        self.ns = self.lua.table()
        loader = self.lua.eval("function(src, name) return assert(loadstring(src, '@' .. name)) end")
        for rel in toc_files():
            loader((ADDON / rel).read_text(encoding="utf-8"), f"Taller/{rel}")("Taller", self.ns)

    def login(self):
        self.fire("ADDON_LOADED", "Taller")
        self.fire("PLAYER_LOGIN")
        return self

    def run(self, code):
        return self.lua.eval("function(ns, MOCK) " + code + " end")(self.ns, self.m)

    def fire(self, event, *args):
        self.m.fire(event, *args)

    def put(self, bag, item, count):
        self.m.put(bag, item, count)

    def bags_changed(self):
        self.fire("BAG_UPDATE_DELAYED")
        self.m.runTimers()

    def pin(self, recipe, qty=None):
        return self.ns.Pins.Pin(recipe, qty)

    def pins(self):
        p = self.lua.globals().TallerDB.pins
        return [p[i] for i in range(1, len(p) + 1)]

    def shopping(self):
        s = self.ns.Pins.Shopping()
        return {s[i].item: (s[i].need, s[i].have.total, s[i].missing) for i in range(1, len(s) + 1)}

    def save(self):
        return self.m.savedVariables("TallerDB")

    def chat(self):
        c = self.m.chat
        return [c[i] for i in range(1, len(c) + 1)]

    def lua_rows(self, expr):
        r = self.run("return " + expr)
        return [r[i] for i in range(1, len(r) + 1)]

    def rows(self):
        r = self.ns.UI.Rows()
        out = []
        for i in range(1, len(r) + 1):
            d = self.ns.UI.Describe(r[i])
            out.append((r[i].kind, d.left, d.right))
        return out


@pytest.fixture
def me():
    return Client().login()


def test_pin_reads_the_reagents_and_skips_optional_ones(me):
    pin = me.pin(2386, 3)
    assert pin.name == "Brown Linen Shirt" and pin.qty == 3 and pin.profession == "Tailoring"
    assert [(pin.reagents[i].item, pin.reagents[i].n) for i in range(1, len(pin.reagents) + 1)] == [(2996, 1), (2320, 1)]
    assert pin.crafter == "Josecito-Forever"


def test_materials_count_bags_bank_and_the_reagent_bag(me):
    me.pin(2963, 10)  # 10 bolts = 20 linen
    me.put(0, 2589, 7)
    me.put(5, 2589, 3)  # reagent bag
    me.bags_changed()
    assert me.shopping() == {2589: (20, 10, 10)}
    me.put(6, 2589, 4)  # bank tab: only counts once the bank is opened
    me.bags_changed()
    assert me.shopping()[2589][1] == 10
    me.fire("BANKFRAME_OPENED")
    assert me.shopping()[2589] == (20, 14, 6)


def test_other_characters_count_too():
    a = Client("Ana").login()
    a.put(0, 2589, 12)
    a.put(15, 2589, 5)  # account bank
    a.bags_changed()
    a.fire("BANKFRAME_OPENED")
    b = Client("Josecito", saved=a.save()).login()
    b.put(0, 2589, 2)
    b.bags_changed()
    b.pin(2963, 10)
    have = b.ns.Inventory.Count(2589)
    assert have.total == 19 and have.here == 2
    places = [(have.places[i].who, have.places[i].where, have.places[i].n) for i in range(1, len(have.places) + 1)]
    assert places == [("Josecito-Forever", "bags", 2), ("Ana-Forever", "bags", 12), ("warband", "warband", 5)]


def test_quantity_counts_items_not_crafts(me):
    me.pin(2660, 12)  # sharpening stones come 5 per craft: 3 crafts
    assert me.ns.Pins.Crafts(me.pins()[0]) == 3
    assert me.shopping() == {2835: (3, 0, 3)}


def test_shopping_list_adds_up_shared_materials(me):
    me.pin(2963, 4)  # 8 linen
    me.pin(2386, 4)  # 4 bolts, 4 thread
    s = me.shopping()
    assert s[2589] == (8, 0, 8) and s[2996] == (4, 0, 4) and s[2320] == (4, 0, 4)
    order = list(s.keys())
    assert order[0] == 2589  # the most missing first


def test_grouped_by_profession_alphabetically(me):
    me.pin(2963, 1)
    me.pin(2657, 1)
    me.pin(2660, 5)
    headers = [left for kind, left, _ in me.rows() if kind == "header"]
    assert headers == ["Blacksmithing", "Mining", "Tailoring"]


def test_a_reagent_you_also_make_says_so(me):
    me.pin(2963, 4)  # makes Bolt of Linen Cloth
    me.pin(2386, 4)  # needs Bolt of Linen Cloth
    bolt = next(left for kind, left, _ in me.rows() if kind == "reagent" and "Bolt of Linen Cloth" in left)
    assert "you can craft it (Bolt of Linen Cloth)" in bolt


def test_the_games_track_box_pins_and_unpins(me):
    me.run("C_TradeSkillUI.SetRecipeTracked(2963, true, false)")
    assert [p.recipe for p in me.pins()] == [2963]
    me.run("C_TradeSkillUI.SetRecipeTracked(2963, false, false)")
    assert me.pins() == []


def test_unpinning_here_unticks_the_game_too(me):
    me.run("C_TradeSkillUI.SetRecipeTracked(2963, true, false)")
    me.ns.Pins.Unpin(me.pins()[0])
    assert me.pins() == []
    assert not me.run("return C_TradeSkillUI.IsRecipeTracked(2963, false)")


def test_tracked_recipes_are_pinned_at_login():
    c = Client()
    c.run("MOCK.tracked[2657] = true")
    c.login()
    assert [p.recipe for p in c.pins()] == [2657]


def test_crafting_counts_down_and_finishes(me):
    me.pin(2660, 10)  # 2 crafts of 5
    me.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 2660)
    assert me.pins()[0].qty == 5
    me.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-2", 2660)  # someone else's cast
    assert me.pins()[0].qty == 5
    me.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 2660)
    assert me.pins() == []
    assert any("Done: Rough Sharpening Stone" in line for line in me.chat())


def test_an_alts_pin_is_not_counted_by_your_casts():
    a = Client("Ana").login()
    a.pin(2657, 5)
    b = Client("Josecito", saved=a.save()).login()
    b.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2657)
    assert b.pins()[0].qty == 5 and b.pins()[0].crafter == "Ana-Forever"
    pin_row = next(left for kind, left, _ in b.rows() if kind == "pin")
    assert "made by Ana" in pin_row


def test_secret_spell_ids_are_left_alone(me):
    me.pin(2657, 5)
    me.run("MOCK.secret[2657] = true")
    me.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2657)
    assert me.pins()[0].qty == 5


def test_setting_zero_unpins(me):
    pin = me.pin(2657, 5)
    me.ns.Pins.SetQty(pin, 0)
    assert me.pins() == []


def test_unknown_recipe_is_not_pinned(me):
    assert me.pin(999999) is None
    assert me.pins() == []
    assert any("Could not read that recipe" in line for line in me.chat())


def test_unknown_item_names_are_asked_for(me):
    me.run("MOCK.recipes[1] = { name = 'Odd', output = 1, per = 1, profession = 'Tailoring', reagents = { { 424242, 1 } } }")
    me.pin(1, 1)
    left = next(left for kind, left, _ in me.rows() if kind == "reagent")
    assert "item 424242" in left
    assert 424242 in list(me.m.loadRequests.values())


def test_tooltip_line(me):
    me.pin(2963, 10)
    me.put(0, 2589, 3)
    me.bags_changed()
    me.run(
        "GameTooltip.lines = {}; for _, fn in ipairs(MOCK.tooltipCalls[Enum.TooltipDataType.Item]) do fn(GameTooltip, { id = 2589 }) end"
    )
    assert me.run("return GameTooltip.lines[1]") == "Taller: 20 needed, 3 here"


def test_saved_and_loaded():
    a = Client("Ana").login()
    a.pin(2386, 2)
    a.put(0, 2320, 1)
    a.bags_changed()
    b = Client("Josecito", saved=a.save()).login()
    assert [p.recipe for p in b.pins()] == [2386]
    assert b.shopping()[2320] == (2, 1, 1)  # Ana's thread, read from the saved data


def test_your_bags_are_read_again_at_login():
    a = Client().login()
    a.put(0, 2320, 5)
    a.bags_changed()
    b = Client(saved=a.save())  # same character, the thread was sold meanwhile
    b.login()
    assert b.ns.Inventory.Count(2320).total == 0


def test_the_window(me):
    me.pin(2963, 2)
    me.lua.globals().SlashCmdList.TALLER("")
    ui = me.ns.UI
    assert ui.frame.IsShown(ui.frame)
    assert "TallerFrame" in list(me.lua.globals().UISpecialFrames.values())
    kinds = [k for k, _, _ in me.rows()]
    assert kinds == ["header", "pin", "reagent"]
    me.lua.globals().SlashCmdList.TALLER("compras")
    assert ui.mode == "shopping"
    assert [k for k, _, _ in me.rows()] == ["reagent"]


def test_the_book_its_pages_and_bookmarks(me):
    me.pin(2963, 2)
    me.run("ns.UI.Toggle()")
    f = me.ns.UI.frame
    # a Pergamino book: leather, two pages, spine, title banner, wax seal, three bookmarks
    assert f.leather and f.pageL and f.pageR and f.spine and f.banner and f.close
    assert str(f.leather.texture).endswith("Taller\\Libs\\Pergamino\\Media\\leather")
    assert sorted(
        me.run("local t = {}; for k in pairs(ns.UI.frame.tabs) do t[#t + 1] = k end; return table.concat(t, ',')").split(",")
    ) == [
        "blueprints",
        "profession",
        "shopping",
    ]
    assert me.run("return ns.UI.frame.title:GetText()") == "Taller"
    assert me.run("return ns.UI.frame.tabs.shopping:GetText()") == "Shopping"
    # the page that is open is the one of the mode
    assert me.run("return ns.UI.frame.selected") == "profession"
    assert me.run("return ns.UI.frame.pages.profession.left:IsShown()") and not me.run("return ns.UI.frame.pages.shopping.left:IsShown()")
    # a bookmark click turns the page and changes the mode
    me.run("ns.UI.frame.tabs.shopping:GetScript('OnClick')(ns.UI.frame.tabs.shopping)")
    assert me.ns.UI.mode == "shopping" and me.run("return ns.UI.frame.pages.shopping.left:IsShown()")
    # the bookmark tooltip says what is inside
    me.run("GameTooltip.lines = {}; ns.UI.frame.tabs.shopping:GetScript('OnEnter')(ns.UI.frame.tabs.shopping)")
    assert "added up and priced" in me.run("return table.concat(GameTooltip.lines, '\\n')")
    # the wax seal closes it
    me.run("ns.UI.frame.close:GetScript('OnClick')()")
    assert not f.IsShown(f)


def test_recipes_page_lists_pins_on_the_left_and_the_chosen_one_on_the_right(me):
    me.pin(2963, 2)
    me.pin(2386, 1)
    me.put(0, 2589, 10)
    me.bags_changed()
    me.run("ns.UI.Toggle()")
    left = [(r.kind, r.pin and r.pin.name or r.text) for r in me.lua_rows("ns.UI.left")]
    assert left == [("header", "Tailoring"), ("pin", "Bolt of Linen Cloth"), ("pin", "Brown Linen Shirt")]
    # the first pin is chosen by default; its materials fill the right page
    assert me.run("return ns.UI.pin.name") == "Bolt of Linen Cloth"
    right = me.ns.UI.views.profession.right
    assert me.run("return ns.UI.views.profession.right.title:GetText()") == "Bolt of Linen Cloth"
    assert "2 crafts" in me.run("return ns.UI.views.profession.right.sub:GetText()")
    mats = me.lua_rows("ns.UI.views.profession.right.list.box.data")
    assert [m.item for m in mats] == [2589]
    assert me.run("return ns.UI.views.profession.right.qty:GetText()") == "2"
    # clicking the other pin on the left shows it on the right
    me.run("ns.UI.views.profession.list.box.rows[3]:GetScript('OnClick')(ns.UI.views.profession.list.box.rows[3], 'LeftButton')")
    assert me.run("return ns.UI.pin.name") == "Brown Linen Shirt"
    assert me.run("return ns.UI.views.profession.right.title:GetText()") == "Brown Linen Shirt"
    assert [m.item for m in me.lua_rows("ns.UI.views.profession.right.list.box.data")] == [2996, 2320]
    # + and - and the unpin act on the chosen one
    me.run("ns.UI.views.profession.right.plus:GetScript('OnClick')()")
    assert me.ns.Pins.Find(2386)[0].qty == 2
    me.run("ns.UI.views.profession.right.remove:GetScript('OnClick')()")
    assert me.ns.Pins.Find(2386) is None and me.run("return ns.UI.pin.name") == "Bolt of Linen Cloth"
    assert right is not None


def test_the_quantity_field_always_shows_the_real_quantity(me):
    # In the game the field once read "41" while the pin was at 4: the refresh skipped the focused field and
    # what was typed stayed. Now + and - drop the focus and the refresh always writes the quantity back.
    me.pin(2386, 1)
    me.run("ns.UI.Toggle()")
    qty = "ns.UI.views.profession.right.qty"
    me.run(qty + ":SetFocus()")
    for _ in range(3):
        me.run("ns.UI.views.profession.right.plus:GetScript('OnClick')()")
    assert me.ns.Pins.Find(2386)[0].qty == 4
    assert me.run("return " + qty + ":GetText()") == "4"
    assert not me.run("return " + qty + ":HasFocus()")
    # typing applies on Enter...
    me.run(qty + ":SetFocus(); " + qty + ":SetText('12')")
    assert me.ns.Pins.Find(2386)[0].qty == 4
    me.run(qty + ":GetScript('OnEnterPressed')(" + qty + ")")
    assert me.ns.Pins.Find(2386)[0].qty == 12 and me.run("return " + qty + ":GetText()") == "12"
    # ...or when the field loses focus; garbage leaves the quantity alone and the field shows it again
    me.run(qty + ":SetFocus(); " + qty + ":SetText('')")
    me.run(qty + ":ClearFocus()")
    assert me.ns.Pins.Find(2386)[0].qty == 12 and me.run("return " + qty + ":GetText()") == "12"
    assert "12 crafts" in me.run("return ns.UI.views.profession.right.sub:GetText()")
    me.run("ns.Pins.SetQty(ns.UI.pin, 1)")
    assert "1 craft " in me.run("return ns.UI.views.profession.right.sub:GetText()") + " "


def test_shopping_page_is_a_ledger_with_the_text_to_copy(me):
    me.pin(2963, 2)
    me.run("ns.UI.Toggle('shopping')")
    assert [r.kind for r in me.lua_rows("ns.UI.left")] == ["reagent"]
    assert me.run("return ns.UI.views.shopping.count:GetText()") == "1 missing"
    assert me.run("return ns.UI.views.shopping.right.text") == "4x Linen Cloth"
    assert me.run("return ns.UI.views.shopping.right.area.box:GetEditBox():GetText()") == "4x Linen Cloth"


def test_empty_pages_invite(me):
    me.run("ns.UI.Toggle()")
    assert me.run("return ns.UI.views.profession.empty:IsShown()")
    assert "Nothing pinned yet" in me.run("return ns.UI.views.profession.empty:GetText()")
    assert not me.run("return ns.UI.views.profession.list.box:IsShown()")
    assert "Pick a recipe" in me.run("return ns.UI.views.profession.right.empty:GetText()")
    me.run("ns.UI.Toggle('shopping')")
    assert "Nothing to buy" in me.run("return ns.UI.views.shopping.empty:GetText()")
    me.pin(2963, 2)
    assert not me.run("return ns.UI.views.shopping.empty:IsShown()") and me.run("return ns.UI.views.shopping.list.box:IsShown()")


def test_language_can_be_chosen_whatever_the_client_speaks(me):
    assert me.run("return ns.language") == "en"
    me.lua.globals().SlashCmdList.TALLER("idioma es")
    assert me.run("return ns.language") == "es" and me.run("return TallerDB.settings.lang") == "es"
    assert me.chat()[-1].endswith("Idioma: castellano. Recargá la interfaz (/reload) para que lo note el resto del juego.")
    me.pin(2963, 2)
    assert "faltan 4" in next(right for kind, _, right in me.rows() if kind == "reagent")
    me.run("ns.UI.Toggle()")
    assert me.run("return ns.UI.frame.tabs.shopping:GetText()") == "Compras"
    me.lua.globals().SlashCmdList.TALLER("idioma en")
    assert me.run("return ns.UI.frame.tabs.shopping:GetText()") == "Shopping"
    me.lua.globals().SlashCmdList.TALLER("idioma klingon")
    assert "es, en or auto" in me.chat()[-1]
    # the setting survives a login, and "auto" follows the client
    saved = me.save()
    c = Client(locale="esES", saved=saved).login()
    assert c.run("return ns.language") == "en"
    c.lua.globals().SlashCmdList.TALLER("idioma auto")
    assert c.run("return ns.language") == "es"


def test_spanish():
    c = Client(locale="esES").login()
    c.pin(2963, 2)
    reagent = next(left for kind, left, right in c.rows() if kind == "reagent")
    assert "Linen Cloth" in reagent
    right = next(right for kind, _, right in c.rows() if kind == "reagent")
    assert "faltan 4" in right


def test_compartment(me):
    g = me.lua.globals()
    g.Taller_OnAddonCompartmentClick()
    assert me.ns.UI.frame.IsShown(me.ns.UI.frame)
    g.Taller_OnAddonCompartmentEnter(None, me.ns.UI.frame)
    g.Taller_OnAddonCompartmentLeave()


# blueprints (#37) -------------------------------------------------------------------------------


def bp_rows(c):
    r = c.ns.Blueprints.Rows()
    return {r[i].e.name: r[i].status for i in range(1, len(r) + 1) if r[i].e}


def test_blueprints_start_missing(me):
    rows = bp_rows(me)
    assert len(rows) == 21
    assert all("missing" in s for s in rows.values())


def test_a_learned_camp_object_is_found_in_the_profession_window(me):
    # the Anvil blueprint teaches a recipe that makes the Anvil camp object (279988)
    me.run("MOCK.recipes[999001] = { name = 'Anvil', output = 279988, per = 1, profession = 'Blacksmithing', reagents = {} }")
    me.run(
        "MOCK.recipes[999002] = { name = 'Master Forge', output = 279955, per = 1, profession = 'Blacksmithing', reagents = {}, learned = false }"
    )
    me.fire("TRADE_SKILL_LIST_UPDATE")
    me.fire("TRADE_SKILL_LIST_UPDATE")  # in bursts: one scan
    me.m.runTimers()
    rows = bp_rows(me)
    assert "learned: Josecito" in rows["Anvil"]
    assert "missing" in rows["Master Forge"]  # listed but not learned


def test_a_blueprint_in_the_bags_of_an_alt():
    a = Client("Ana").login()
    a.put(0, 273099, 1)  # Spinning Wheel blueprint
    a.bags_changed()
    b = Client("Josecito", saved=a.save()).login()
    assert "Ana has it, not learned" in bp_rows(b)["Spinning Wheel"]


def test_learned_on_an_alt_shows_on_every_character():
    a = Client("Ana").login()
    a.run("MOCK.recipes[999001] = { name = 'Anvil', output = 279988, per = 1, profession = 'Blacksmithing', reagents = {} }")
    a.ns.Blueprints.ScanRecipes()
    b = Client("Josecito", saved=a.save()).login()
    assert "learned: Ana" in bp_rows(b)["Anvil"]


def test_blueprint_tab_and_tooltip(me):
    me.lua.globals().SlashCmdList.TALLER("planos")
    assert me.ns.UI.mode == "blueprints"
    kinds = [k for k, _, _ in me.rows()]
    assert kinds[0] == "note" and kinds.count("header") == 11 and kinds.count("bp") == 21
    # the left page is short (name and tier, state as a tag); skill and the drop live on the right page
    first = next(left for kind, left, _ in me.rows() if kind == "bp")
    assert first.strip() == "Fermenter · tier 2"
    rows = me.lua_rows("ns.UI.Rows()")
    firstbp = next(r for r in rows if r.kind == "bp")
    assert firstbp.bp.state == "missing" and "Rath'mael, Ruins of Lordaeron" in firstbp.bp.source
    unknown = next(r for r in rows if r.kind == "bp" and r.bp.e.name == "Alchemy Laboratory")
    assert "drop not known yet" in unknown.bp.source
    me.run(
        "GameTooltip.lines = {}; for _, fn in ipairs(MOCK.tooltipCalls[Enum.TooltipDataType.Item]) do fn(GameTooltip, { id = 273086 }) end"
    )
    lines = me.run("return table.concat(GameTooltip.lines, '\\n')")
    assert "none of your characters learned it" in lines and "Gilnid (The Deadmines)" in lines


def test_blueprint_page_folds_professions_and_shows_the_chosen_one(me):
    me.run("ns.UI.Toggle('blueprints')")
    left = me.lua_rows("ns.UI.left")
    # nothing scanned yet: the hint, then the eleven professions folded (no blueprints visible)
    assert left[0].kind == "note" and "Open each profession once" in left[0].text
    assert [r.kind for r in left[1:]] == ["header"] * 11 and all(not r.open for r in left[1:])
    assert me.run("return ns.UI.views.blueprints.count:GetText()") == "0 of 21"
    assert "Pick a blueprint" in me.run("return ns.UI.views.blueprints.right.empty:GetText()") or "pick a blueprint" in me.run(
        "return ns.UI.views.blueprints.right.empty:GetText()"
    )
    # unfold Blacksmithing by clicking its row
    me.run("ns.UI.views.blueprints.list.box.rows[3]:GetScript('OnClick')(ns.UI.views.blueprints.list.box.rows[3], 'LeftButton')")
    left = me.lua_rows("ns.UI.left")
    assert left[2].kind == "header" and left[2].profession == "Blacksmithing" and left[2].open
    assert [r.kind for r in left[3:5]] == ["bp", "bp"] and left[5].kind == "header"
    # choose the Anvil: the right page tells who learned it, who carries it and who drops it
    me.run("ns.UI.views.blueprints.list.box.rows[4]:GetScript('OnClick')(ns.UI.views.blueprints.list.box.rows[4], 'LeftButton')")
    r = me.ns.UI.views.blueprints.right
    assert me.run("return ns.UI.views.blueprints.right.title:GetText()") == "Anvil"
    assert me.run("return ns.UI.views.blueprints.right.sub:GetText()") == "Blacksmithing · tier 2 · skill 140"
    bodies = [me.run(f"return ns.UI.views.blueprints.right.lines[{i}].body:GetText()") for i in range(1, 5)]
    assert bodies[0] == "none of your characters" and bodies[1] == "nobody" and bodies[2] == "Gilnid, The Deadmines"
    assert r is not None
    # once a profession was scanned, the hint goes away and the count follows
    me.run("MOCK.recipes[9999] = { name = 'Anvil', output = 279988, per = 1, profession = 'Blacksmithing', reagents = {} }")
    me.fire("TRADE_SKILL_LIST_UPDATE")
    me.m.runTimers()
    left = me.lua_rows("ns.UI.left")
    assert left[0].kind == "header"
    assert me.run("return ns.UI.views.blueprints.count:GetText()") == "1 of 21"
    assert me.run("return ns.UI.views.blueprints.right.lines[1].body:GetText()").endswith("learned: Josecito|r")


def test_blueprints_in_spanish():
    c = Client(locale="esES").login()
    c.run("ns.UI.Toggle('blueprints')")
    headers = [left for kind, left, _ in c.rows() if kind == "header"]
    assert headers[0] == "Alquimia" and "Primeros auxilios" in headers


def test_copy_the_shopping_list(me):
    me.pin(2963, 10)
    me.put(0, 2589, 5)
    me.bags_changed()
    assert me.ns.UI.ShoppingText() == "15x Linen Cloth"
    me.lua.globals().SlashCmdList.TALLER("copiar")
    me.put(0, 2589, 15)
    me.bags_changed()
    assert me.ns.UI.ShoppingText() == "Nothing missing."


# other addons: Syndicator / Baganator counts and Auctionator prices ------------------------------------

SYND_LINEN = """
MOCK.syndicator.items[2589] = {
  characters = {
    { character = "Josecito", realm = "Forever", bags = 99, bank = 99 },  -- ignored: this character is read live
    { character = "Ana", realm = "Forever", bags = 4, equipped = 0, bank = 6, mail = 2 },
    { character = "Beto", realm = "Forever", bags = 0, bank = 0 },
  },
  guilds = { { guild = "Los Pibes", realm = "Forever", bank = 30 } },
  warband = { { bank = 5 }, { bank = 7 } },
}
"""


def syndicator_client(addon="Syndicator"):
    c = Client()
    c.run(f"MOCK.loaded['{addon}'] = true")
    c.run(SYND_LINEN)
    return c.login()


def test_without_other_addons_nothing_changes(me):
    me.run(SYND_LINEN)  # the globals exist but the addons are not loaded
    me.run("MOCK.auctionator.prices[2589] = 500")
    me.pin(2963, 10)
    me.put(0, 2589, 5)
    me.bags_changed()
    assert me.shopping() == {2589: (20, 5, 15)}
    assert not me.ns.Partners.HasSyndicator() and not me.ns.Partners.HasPrices()
    assert me.ns.UI.ShoppingText() == "15x Linen Cloth"
    assert all("Auctionator" not in left for _, left, _ in me.rows())


def test_syndicator_counts_alts_guild_bank_and_warband():
    c = syndicator_client()
    c.pin(2963, 30)  # 60 linen
    c.put(0, 2589, 5)
    c.bags_changed()
    have = c.ns.Inventory.Count(2589)
    places = [(have.places[i].who, have.places[i].where, have.places[i].n) for i in range(1, len(have.places) + 1)]
    # mine live (5), then Ana's bags, bank and mail, the guild bank and both account-bank tabs added up
    assert places == [
        ("Josecito-Forever", "bags", 5),
        ("Ana-Forever", "bags", 4),
        ("Ana-Forever", "bank", 6),
        ("Ana-Forever", "mail", 2),
        ("guild:Los Pibes", "guildbank", 30),
        ("warband", "warband", 12),
    ]
    assert have.total == 59 and have.here == 5 and have.via == "Syndicator"
    assert c.shopping() == {2589: (60, 59, 1)}


def test_syndicator_wins_over_an_old_scan_of_the_same_alt():
    saved = 'TallerDB = { chars = { ["Ana-Forever"] = { bags = { [2589] = 40 }, bank = {} } }, warband = { items = { [2589] = 100 } } }'
    c = Client(saved=saved)
    c.run("MOCK.loaded.Baganator = true")  # Baganator bundles Syndicator
    c.run(SYND_LINEN)
    c.login()
    have = c.ns.Inventory.Count(2589)
    who = {(have.places[i].who, have.places[i].where): have.places[i].n for i in range(1, len(have.places) + 1)}
    assert who[("Ana-Forever", "bags")] == 4 and who[("warband", "warband")] == 12  # not 40 and 100
    assert have.total == 54


def test_syndicator_label_in_the_tooltip_and_a_throwing_api():
    c = syndicator_client()
    c.pin(2963, 10)
    c.run("ns.UI.Toggle('shopping')")
    rows = c.rows()
    assert rows and rows[0][0] == "reagent"
    assert c.ns.PlaceName("guild:Los Pibes") == "Los Pibes" and c.ns.PlaceName("warband") == "account bank"
    c.run("MOCK.syndicator.throws = true")
    have = c.ns.Inventory.Count(2589)
    assert have.total == 0 and have.via is None  # the error is swallowed; Taller's own data stays
    c.run("MOCK.syndicator.throws = false; MOCK.syndicator.items[2589] = { characters = 'garbage' }")
    assert c.ns.Inventory.Count(2589).total == 0  # an unexpected shape is ignored


def test_syndicator_updates_redraw():
    c = syndicator_client()
    assert sorted(
        c.run(
            "local out = {} for k in pairs(MOCK.syndicator.callbacks) do out[#out + 1] = k end table.sort(out) return table.concat(out, ',')"
        ).split(",")
    ) == [
        "BagCacheUpdate",
        "BankCacheUpdate",
        "GuildCacheUpdate",
        "WarbandBankCacheUpdate",
    ]
    c.run("ns.hits = 0; ns.On('inventory', function() ns.hits = ns.hits + 1 end)")
    c.run("MOCK.syndicator.callbacks.BagCacheUpdate()")
    assert c.run("return ns.hits") == 1


def test_auctionator_prices_the_missing_materials():
    c = Client()
    c.run("MOCK.loaded.Auctionator = true; MOCK.auctionator.prices[2589] = 1234; MOCK.auctionator.prices[2320] = 10")
    c.login()
    c.pin(2963, 10)  # 20 linen
    c.pin(2386, 2)  # 2 bolts + 2 thread
    c.put(0, 2589, 5)
    c.bags_changed()
    s = c.ns.Pins.Shopping()
    by = {s[i].item: (s[i].missing, s[i].price, s[i].cost) for i in range(1, len(s) + 1)}
    assert by[2589] == (15, 1234, 15 * 1234) and by[2320] == (2, 10, 20) and by[2996][1] is None  # bolts: no price
    assert c.ns.Pins.ShoppingTotal() == 15 * 1234 + 20
    assert c.ns.Partners.Money(15 * 1234 + 20) == "1g 85s 30c" and c.ns.Partners.Money(7) == "7c"
    text = c.ns.UI.ShoppingText()
    assert "15x Linen Cloth ~1g 85s 10c" in text and "2x Coarse Thread ~20c" in text and text.endswith("about 1g 85s 30c, per Auctionator.")
    c.run("ns.UI.Toggle('shopping')")
    rows = c.rows()
    assert rows[-1][0] == "note" and "1g 85s 30c" in rows[-1][1]
    assert any("~1g 85s 10c" in (right or "") for _, _, right in rows)
    c.run("ns.hits = 0; ns.On('inventory', function() ns.hits = ns.hits + 1 end); MOCK.auctionator.callbacks[1]()")
    assert c.run("return ns.hits") == 1
    c.run("MOCK.auctionator.throws = true")
    assert c.ns.Pins.ShoppingTotal() is None and "~" not in c.ns.UI.ShoppingText()


def test_prices_in_spanish():
    c = Client(locale="esES")
    c.run("MOCK.loaded.Auctionator = true; MOCK.auctionator.prices[2589] = 100")
    c.login()
    c.pin(2963, 1)
    assert c.ns.UI.ShoppingText() == "2x Linen Cloth ~2s 0c. Lo que falta sale unos 2s 0c, según Auctionator."


def test_the_minimap_button_opens_the_book_and_can_be_hidden(me):
    b = me.run("return ns.minimapButton")
    assert b is not None and me.run("return ns.minimapButton:IsShown()")
    assert me.run("return TallerDB.settings.minimap") is True
    # left click opens the book, right click opens it on the blueprints
    me.run("ns.minimapButton:GetScript('OnClick')(ns.minimapButton, 'LeftButton')")
    assert me.run("return ns.UI.frame:IsShown()") and me.ns.UI.mode == "profession"
    me.run("ns.minimapButton:GetScript('OnClick')(ns.minimapButton, 'LeftButton')")
    assert not me.run("return ns.UI.frame:IsShown()")
    me.run("ns.minimapButton:GetScript('OnClick')(ns.minimapButton, 'RightButton')")
    assert me.run("return ns.UI.frame:IsShown()") and me.ns.UI.mode == "blueprints"
    # the angle is kept across sessions; the slash hides and shows it
    me.run("ns.minimapButton:SetAngle(45); ns.minimapButton:GetScript('OnDragStop')(ns.minimapButton)")
    assert me.run("return TallerDB.settings.minimapAngle") == 45
    me.lua.globals().SlashCmdList.TALLER("minimapa off")
    assert not me.run("return ns.minimapButton:IsShown()") and me.chat()[-1].endswith("/taller minimapa on brings it back.")
    other = Client("Josecito", saved=me.save()).login()
    assert not other.run("return ns.minimapButton:IsShown()")
    other.lua.globals().SlashCmdList.TALLER("minimapa on")
    assert other.run("return ns.minimapButton:IsShown()")
    assert other.run("return ns.minimapButton.angle") == 45


def test_one_material_short_is_singular(me):
    # in the game: "45 crafts · 1 materials short"
    me.pin(2963, 2)
    me.run("ns.UI.Toggle()")
    assert me.run("return ns.UI.views.profession.right.sub:GetText()").endswith("1 material short")
    me.pin(2386, 1)
    me.run("ns.UI.views.profession.list.box.rows[3]:GetScript('OnClick')(ns.UI.views.profession.list.box.rows[3], 'LeftButton')")
    assert me.run("return ns.UI.views.profession.right.sub:GetText()").endswith("2 materials short")
