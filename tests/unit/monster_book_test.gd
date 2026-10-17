extends TestCase
## MonsterBook: kills, cards up to a full set, completed pages, the book rank and the
## power bonus it gives the character, and the save format.

var fx: UnitHelpers
var book: MonsterBook

func before_each() -> void:
	fx = UnitHelpers.new()
	book = MonsterBook.new()

func after_each() -> void:
	fx.cleanup()

func _complete(m: MonsterDef) -> void:
	for i in CardDef.SET:
		book.add_card(m)

func test_unseen_monster_is_empty() -> void:
	var m := fx.monster()
	check(not book.seen(m), "not seen")
	check_eq(book.kills(m), 0, "kills")
	check_eq(book.cards(m), 0, "cards")
	check(not book.complete(m), "not complete")
	check_eq(book.rank(), 1, "book starts at rank 1")

func test_kills_count_per_monster() -> void:
	var a := fx.monster(&"t_a")
	var b := fx.monster(&"t_b")
	for i in 3:
		book.record_kill(a)
	book.record_kill(b)
	check(book.seen(a), "seen after a kill")
	check_eq(book.kills(a), 3, "a")
	check_eq(book.kills(b), 1, "b")
	check_eq(book.total_kills(), 4, "total")
	check_eq(book.cards(a), 0, "kills give no cards")

func test_cards_fill_to_a_set_then_refuse() -> void:
	var m := fx.monster()
	for i in CardDef.SET - 1:
		check(book.add_card(m), "card %d accepted" % i)
	check(not book.complete(m), "one short")
	check(book.add_card(m), "last card accepted")
	check(book.complete(m), "complete")
	check(not book.add_card(m), "extra card refused")
	check_eq(book.cards(m), CardDef.SET, "stays at a set")

func test_card_alone_marks_seen() -> void:
	var m := fx.monster()
	book.add_card(m)
	check(book.seen(m), "seen")
	check_eq(book.kills(m), 0, "no kills")

func test_book_rank_every_three_pages() -> void:
	var expect := [1, 1, 1, 2, 2, 2, 3]
	for n in expect.size():
		if n > 0:
			_complete(fx.monster(StringName("t_m%d" % n)))
		check_eq(book.completed(), n, "%d pages" % n)
		check_eq(book.rank(), expect[n], "rank with %d pages" % n)

func test_power_bonus_is_one_per_rank_past_first() -> void:
	check_eq(book.power_bonus(), 0, "rank 1 gives nothing")
	for n in 6:
		_complete(fx.monster(StringName("t_m%d" % n)))
	check_eq(book.power_bonus(), 2, "rank 3")

func test_total_cards_counts_unfinished_pages() -> void:
	book.add_card(fx.monster(&"t_a"))
	book.add_card(fx.monster(&"t_a"))
	_complete(fx.monster(&"t_b"))
	check_eq(book.total_cards(), 2 + CardDef.SET, "all cards")
	check_eq(book.completed(), 1, "one page")

func test_book_bonus_reaches_character_power() -> void:
	var c := fx.character()
	var before := c.power()
	for n in 3:
		var m := fx.monster(StringName("t_m%d" % n))
		for i in CardDef.SET:
			c.book.add_card(m)
	check_eq(c.power(), before + 1, "book rank 2 adds 1 power")
	check_eq(c.stats.nonzero().size(), 0, "and no stats")

func test_save_round_trip() -> void:
	var a := fx.monster(&"t_a")
	var b := fx.monster(&"t_b")
	book.record_kill(a)
	book.record_kill(a)
	_complete(b)
	var back := MonsterBook.new()
	back.load_dict(book.to_dict())
	check_eq(back.kills(a), 2, "kills")
	check(back.complete(b), "page")
	check_eq(back.total_cards(), CardDef.SET, "cards")

func test_to_dict_is_a_copy() -> void:
	var m := fx.monster()
	book.record_kill(m)
	var d := book.to_dict()
	d["t_mob"][0] = 99
	check_eq(book.kills(m), 1, "book unchanged")

func test_load_drops_unknown_and_clamps() -> void:
	var m := fx.monster()
	book.load_dict({
		"t_mob": [-5, 99],
		"t_not_a_monster": [3, 3],
		"t_bad": "x",
	})
	check_eq(book.kills(m), 0, "negative kills floored")
	check_eq(book.cards(m), CardDef.SET, "cards capped")
	check_eq(book.pages.size(), 1, "only the real monster")
	book.load_dict({"t_mob": [1]})
	check_eq(book.pages.size(), 0, "short entry dropped and old pages cleared")

func test_real_card_for_monster() -> void:
	var m: MonsterDef = Content.monsters.values()[0]
	var card := Content.card(m)
	check(card != null, "every monster has a card")
	check_eq(card.monster, m, "card knows its monster")
	check_eq(card.stack_size(), 1, "cards don't stack")
