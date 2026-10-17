class_name MonsterBook
extends RefCounted
## The Monster Book, like MapleStory's: a page for every monster with how many you've
## beaten and how many of its cards you've found. Completed pages raise the book's rank,
## and each rank past the first adds a point to every main stat.

## Completed pages per book rank.
const PAGES_PER_RANK := 3

## monster id -> [kills, cards]
var pages := {}

func kills(m: MonsterDef) -> int:
	return pages.get(m.id, [0, 0])[0]

func cards(m: MonsterDef) -> int:
	return pages.get(m.id, [0, 0])[1]

func seen(m: MonsterDef) -> bool:
	return pages.has(m.id)

func complete(m: MonsterDef) -> bool:
	return cards(m) >= CardDef.SET

func record_kill(m: MonsterDef) -> void:
	var page: Array = pages.get(m.id, [0, 0])
	page[0] += 1
	pages[m.id] = page

## Puts a card in the book. False when its page is already complete.
func add_card(m: MonsterDef) -> bool:
	var page: Array = pages.get(m.id, [0, 0])
	if page[1] >= CardDef.SET:
		return false
	page[1] += 1
	pages[m.id] = page
	return true

func total_kills() -> int:
	var n := 0
	for page in pages.values():
		n += page[0]
	return n

func total_cards() -> int:
	var n := 0
	for page in pages.values():
		n += page[1]
	return n

func completed() -> int:
	var n := 0
	for page in pages.values():
		if page[1] >= CardDef.SET:
			n += 1
	return n

func rank() -> int:
	return 1 + completed() / PAGES_PER_RANK

## What the book adds to the character's power (Character.power): one a rank past the first.
func power_bonus() -> int:
	return rank() - 1

func to_dict() -> Dictionary:
	var out := {}
	for k in pages:
		out[String(k)] = pages[k].duplicate()
	return out

func load_dict(data: Dictionary) -> void:
	pages.clear()
	for k in data:
		var page: Variant = data[k]
		if Content.monsters.has(StringName(k)) and page is Array and page.size() == 2:
			pages[StringName(k)] = [maxi(0, int(page[0])), clampi(int(page[1]), 0, CardDef.SET)]
