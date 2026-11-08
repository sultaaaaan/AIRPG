class_name WeaponTable
extends RefCounted
## Minimal weapon catalogue for the arena combat prototype.
##
## Item ids match `EquipmentEntry.item_id` in the class/background packs. A
## proper item catalogue will replace this table; until then, stats use the
## 2024 PHB values for the weapons that actually appear in starting gear.
##
## `range` is in world units (1 ft = 0.2 units): melee reach is 2.2, bows 12.

const UNARMED := {
	"name": "Без оружия",
	"count": 1,
	"faces": 1,
	"ability": "strength",
	"category": "simple",
	"finesse": false,
	"light": false,
	"ranged": false,
	"range": 1.8,
}

const WEAPONS := {
	&"dagger": {"name": "Кинжал", "count": 1, "faces": 4, "ability": "strength", "category": "simple", "finesse": true, "light": true, "ranged": false, "range": 2.0},
	&"flail": {"name": "Цеп", "count": 1, "faces": 8, "ability": "strength", "category": "martial", "finesse": false, "light": false, "ranged": false, "range": 2.2},
	&"greataxe": {"name": "Секира", "count": 1, "faces": 12, "ability": "strength", "category": "martial", "finesse": false, "light": false, "ranged": false, "range": 2.2},
	&"greatsword": {"name": "Двуручный меч", "count": 2, "faces": 6, "ability": "strength", "category": "martial", "finesse": false, "light": false, "ranged": false, "range": 2.2},
	&"handaxe": {"name": "Боевой топор", "count": 1, "faces": 6, "ability": "strength", "category": "simple", "finesse": false, "light": true, "ranged": false, "range": 2.0},
	&"javelin": {"name": "Метательное копьё", "count": 1, "faces": 6, "ability": "strength", "category": "simple", "finesse": false, "light": false, "ranged": false, "range": 2.2},
	&"light_crossbow": {"name": "Лёгкий арбалет", "count": 1, "faces": 8, "ability": "dexterity", "category": "simple", "finesse": false, "light": false, "ranged": true, "range": 12.0},
	&"longbow": {"name": "Длинный лук", "count": 1, "faces": 8, "ability": "dexterity", "category": "martial", "finesse": false, "light": false, "ranged": true, "range": 12.0},
	&"longsword": {"name": "Длинный меч", "count": 1, "faces": 8, "ability": "strength", "category": "martial", "finesse": false, "light": false, "ranged": false, "range": 2.2},
	&"mace": {"name": "Булава", "count": 1, "faces": 6, "ability": "strength", "category": "simple", "finesse": false, "light": false, "ranged": false, "range": 2.2},
	&"quarterstaff": {"name": "Боевой посох", "count": 1, "faces": 6, "ability": "strength", "category": "simple", "finesse": false, "light": false, "ranged": false, "range": 2.2},
	&"scimitar": {"name": "Ятаган", "count": 1, "faces": 6, "ability": "strength", "category": "martial", "finesse": true, "light": true, "ranged": false, "range": 2.2},
	&"shortbow": {"name": "Короткий лук", "count": 1, "faces": 6, "ability": "dexterity", "category": "simple", "finesse": false, "light": false, "ranged": true, "range": 10.0},
	&"shortsword": {"name": "Короткий меч", "count": 1, "faces": 6, "ability": "strength", "category": "martial", "finesse": true, "light": true, "ranged": false, "range": 2.2},
	&"sickle": {"name": "Серп", "count": 1, "faces": 4, "ability": "strength", "category": "simple", "finesse": false, "light": true, "ranged": false, "range": 2.0},
	&"spear": {"name": "Копьё", "count": 1, "faces": 6, "ability": "strength", "category": "simple", "finesse": false, "light": false, "ranged": false, "range": 2.2},
}


static func has_weapon(item_id: StringName) -> bool:
	return WEAPONS.has(item_id)


## Stats for `item_id`, or an unarmed strike for anything unknown.
static func get_weapon(item_id: StringName) -> Dictionary:
	if WEAPONS.has(item_id):
		var weapon: Dictionary = WEAPONS[item_id].duplicate()
		weapon["id"] = String(item_id)
		return weapon
	return UNARMED.duplicate()


## True when a class/option training list covers this weapon's category.
static func is_proficient(weapon: Dictionary, training: Array) -> bool:
	var category := str(weapon.get("category", "simple"))
	if category in training:
		return true
	# Rogue-style "martial_light" training covers martial weapons with Light.
	if category == "martial" and bool(weapon.get("light", false)) and "martial_light" in training:
		return true
	return false
