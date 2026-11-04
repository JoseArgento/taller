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
    return [ln.strip().replace("\\", "/") for ln in lines if ln.strip() and not ln.startswith("#")]


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


def test_plus_and_minus(me):
    me.pin(2963, 2)
    me.run("ns.UI.Toggle()")
    pin = me.pins()[0]
    me.ns.Pins.SetQty(pin, pin.qty + 1)
    assert me.pins()[0].qty == 3
    me.run("MOCK.shift = true")
    me.ns.Pins.SetQty(pin, pin.qty + 10)
    assert me.pins()[0].qty == 13


def test_empty_message(me):
    me.run("ns.UI.Toggle()")
    assert me.run("return ns.UI.frame.empty:IsShown()")


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
