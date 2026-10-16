class_name UnitHelpers
extends RefCounted
## Small Defs built in code for unit tests, so tests don't break when content is rebalanced.
## Anything registered in Content (`register`) is removed again by `cleanup()`; call it in
## after_each. Every id made here starts with "t_" so it can't clash with real content.

## [table name, id, what was there before or null]
var _registered: Array = []

## Puts `res` in one of Content's tables ("items", "skills", "jobs", "monsters", "quests"...)
## until cleanup().
func register(table: String, res: Resource) -> Resource:
	var d: Dictionary = Content.get(table)
	_registered.append([table, res.get("id"), d.get(res.get("id"))])
	d[res.get("id")] = res
	return res

## Undoes every register(), newest first.
func cleanup() -> void:
	for i in range(_registered.size() - 1, -1, -1):
		var r: Array = _registered[i]
		var d: Dictionary = Content.get(r[0])
		if r[2] == null:
			d.erase(r[1])
		else:
			d[r[1]] = r[2]
	_registered.clear()

static func stats(values := {}) -> StatBlock:
	var s := StatBlock.new()
	for k in values:
		s.set(StringName(k), values[k])
	return s

## A job with round numbers: HP 50 + 10 and MP 20 + 5 per CharacterStats.GROWTH_POINTS stat
## points bought, STR main and DEX second, mastery 0.5.
func job(id := &"t_job", family := &"t_family", advances_from := &"") -> JobDef:
	var j := JobDef.new()
	j.id = id
	j.display_name = String(id).capitalize()
	j.family = family
	j.primary_stat = "strength"
	j.mastery = 0.5
	j.base_hp = 50
	j.hp_growth = 10
	j.base_mp = 20
	j.mp_growth = 5
	j.advances_from = advances_from
	register("jobs", j)
	return j

## A character of `j` (a fresh test job if null) with `base_values` as base stats, full HP and MP.
func character(j: JobDef = null, base_values := {}) -> Character:
	var c := Character.new()
	c.name = "Tester"
	c.job = j if j else job()
	c.base = stats(base_values)
	c.recalc()
	c.refill()
	return c

func etc(id := &"t_etc", max_stack := 100) -> ItemDef:
	var it := ItemDef.new()
	it.id = id
	it.display_name = String(id).capitalize()
	it.max_stack = max_stack
	register("items", it)
	return it

func use(id := &"t_use", max_stack := 100) -> UseDef:
	var it := UseDef.new()
	it.id = id
	it.display_name = String(id).capitalize()
	it.max_stack = max_stack
	register("items", it)
	return it


func equip(id := &"t_sword", slot := EquipDef.Slot.WEAPON, values := {}, variance := 0) -> EquipDef:
	var e := EquipDef.new()
	e.id = id
	e.display_name = String(id).capitalize()
	e.slot = slot
	e.stats = stats(values)
	e.variance = variance
	e.upgrade_slots = 7
	register("items", e)
	return e

func scroll(id := &"t_scroll", slots: Array[int] = [EquipDef.Slot.WEAPON], chance := 0.6, values := {"attack": 2}) -> ScrollDef:
	var s := ScrollDef.new()
	s.id = id
	s.display_name = String(id).capitalize()
	s.slots = slots
	s.chance = chance
	s.stats = stats(values)
	s.max_stack = 100
	register("items", s)
	return s

func skill(id := &"t_skill", kind := SkillDef.Kind.ATTACK, job_id := &"t_job") -> SkillDef:
	var s := SkillDef.new()
	s.id = id
	s.display_name = String(id).capitalize()
	s.kind = kind
	s.job = job_id
	s.max_level = 10
	register("skills", s)
	return s

func monster(id := &"t_mob", level := 1, max_hp := 100, essence := 10) -> MonsterDef:
	var m := MonsterDef.new()
	m.id = id
	m.display_name = String(id).capitalize()
	m.level = level
	m.max_hp = max_hp
	m.attack = 20
	m.essence = essence
	register("monsters", m)
	return m

func objective(kind: QuestObjective.Kind, count := 1) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = kind
	o.count = count
	return o

func quest(id := &"t_quest", objectives: Array[QuestObjective] = []) -> QuestDef:
	var q := QuestDef.new()
	q.id = id
	q.title = String(id).capitalize()
	q.objectives = objectives
	register("quests", q)
	return q

static func drop(item: ItemDef, amount := 1, chance := 1.0) -> DropEntry:
	var d := DropEntry.new()
	d.item = item
	d.chance = chance
	d.min_amount = amount
	d.max_amount = amount
	return d
