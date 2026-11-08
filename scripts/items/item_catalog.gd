class_name ItemCatalog
extends RefCounted
## Static catalogue for the inventory prototype.
##
## Starting gear is authored as `EquipmentEntry` subresources inside class and
## background packs, keyed by stable item ids. This table adds the metadata the
## inventory UI needs (category, stacking, description) without migrating the
## whole content set to individual ItemData resources. Weapon numbers stay in
## WeaponTable so combat has a single source of truth.

enum Category {
	WEAPON,
	ARMOR,
	CLOTHING,
	SHIELD,
	AMMO,
	PACK,
	FOCUS,
	TOOL,
	CONSUMABLE,
	GEAR,
	TREASURE,
}

## Equipment slots a slot grid can equip into.
enum Slot {
	NONE,
	WEAPON,
	ARMOR,
	CLOTHING,
	SHIELD,
}

const SLOT_NAMES_RU := {
	Slot.WEAPON: "Оружие",
	Slot.ARMOR: "Доспех",
	Slot.CLOTHING: "Одежда",
	Slot.SHIELD: "Щит",
}

const CATEGORY_NAMES_RU := {
	Category.WEAPON: "Оружие",
	Category.ARMOR: "Доспехи",
	Category.CLOTHING: "Одежда",
	Category.SHIELD: "Щиты",
	Category.AMMO: "Боеприпасы",
	Category.PACK: "Наборы",
	Category.FOCUS: "Фокусы",
	Category.TOOL: "Инструменты",
	Category.CONSUMABLE: "Расходники",
	Category.GEAR: "Снаряжение",
	Category.TREASURE: "Ценности",
}

## Display order for grouped lists.
const CATEGORY_ORDER := [
	Category.WEAPON,
	Category.ARMOR,
	Category.CLOTHING,
	Category.SHIELD,
	Category.AMMO,
	Category.FOCUS,
	Category.TOOL,
	Category.CONSUMABLE,
	Category.PACK,
	Category.GEAR,
	Category.TREASURE,
]

const ARMOR_IDS := [
	&"leather_armor", &"studded_leather_armor", &"chain_shirt", &"chain_mail",
]
const CLOTHING_IDS := [
	&"travelers_clothes", &"fine_clothes", &"robe", &"costume",
]
const SHIELD_IDS := [&"shield"]
const AMMO_IDS := [&"arrow", &"crossbow_bolts"]
const FOCUS_IDS := [&"arcane_focus", &"druidic_focus", &"holy_symbol", &"musical_instrument"]
const TOOL_IDS := [
	&"artisan_tools", &"artisans_tools", &"calligraphers_supplies",
	&"carpenters_tools", &"cartographers_tools", &"forgery_kit",
	&"gaming_set", &"herbalism_kit", &"healers_kit", &"navigators_tools",
	&"thieves_tools", &"spellbook",
]

## Ids that stack in one slot. Everything else is one item per slot.
const STACK_OVERRIDES := {
	&"arrow": 999,
	&"crossbow_bolts": 999,
	&"javelin": 20,
	&"oil": 10,
	&"parchment": 50,
	&"perfume": 5,
	&"iron_pot": 5,
}


static func category(item_id: StringName) -> Category:
	if WeaponTable.has_weapon(item_id):
		return Category.WEAPON
	if item_id in ARMOR_IDS:
		return Category.ARMOR
	if item_id in CLOTHING_IDS:
		return Category.CLOTHING
	if item_id in SHIELD_IDS:
		return Category.SHIELD
	if item_id in AMMO_IDS:
		return Category.AMMO
	if item_id in FOCUS_IDS:
		return Category.FOCUS
	if item_id in TOOL_IDS:
		return Category.TOOL
	if String(item_id).ends_with("_pack"):
		return Category.PACK
	return Category.GEAR


static func category_name(item_id: StringName) -> String:
	return CATEGORY_NAMES_RU.get(category(item_id), "Снаряжение")


## Equipment slot this item occupies, or NONE for non-equipment.
static func equip_slot(item_id: StringName) -> Slot:
	match category(item_id):
		Category.WEAPON:
			return Slot.WEAPON
		Category.ARMOR:
			return Slot.ARMOR
		Category.CLOTHING:
			return Slot.CLOTHING
		Category.SHIELD:
			return Slot.SHIELD
		_:
			return Slot.NONE


## [base AC, max DEX bonus] where -1 means uncapped.
const ARMOR_STATS := {
	&"leather_armor": [11, -1],
	&"studded_leather_armor": [12, -1],
	&"chain_shirt": [13, 2],
	&"chain_mail": [16, 0],
}
const SHIELD_BONUS := 2


## Shared AC arithmetic for the character builder and the runtime equipment.
## `unarmored_modifier` is 0 when the class has no Unarmored Defense.
static func armor_class(
	dex_modifier: int,
	armor_id: StringName,
	has_shield: bool,
	unarmored_modifier: int,
	allows_shield: bool
) -> int:
	if ARMOR_STATS.has(armor_id):
		var row: Array = ARMOR_STATS[armor_id]
		var dex_part := dex_modifier if int(row[1]) < 0 else mini(dex_modifier, int(row[1]))
		return int(row[0]) + dex_part + (SHIELD_BONUS if has_shield else 0)

	var base := 10 + dex_modifier
	if allows_shield or not has_shield:
		base += unarmored_modifier
	if has_shield:
		base += SHIELD_BONUS
	return base


static func stack_size(item_id: StringName) -> int:
	return int(STACK_OVERRIDES.get(item_id, 1))


static func is_weapon(item_id: StringName) -> bool:
	return WeaponTable.has_weapon(item_id)


## Short stat line shown under an inventory row.
static func describe(item_id: StringName) -> String:
	if item_id == &"unarmed":
		return "1к1 · рукопашная · СИЛ"
	if WeaponTable.has_weapon(item_id):
		var weapon := WeaponTable.get_weapon(item_id)
		var parts := PackedStringArray()
		parts.append("%dк%d" % [int(weapon.get("count", 1)), int(weapon.get("faces", 1))])
		if bool(weapon.get("ranged", false)):
			parts.append("дистанция %d фт" % int(float(weapon.get("range", 0.0)) / 0.2))
		else:
			parts.append("рукопашная")
		parts.append(_weapon_ability_label(weapon))
		if bool(weapon.get("finesse", false)):
			parts.append("фехтовальное")
		if bool(weapon.get("light", false)):
			parts.append("лёгкое")
		return " · ".join(parts)

	var cat := category(item_id)
	match cat:
		Category.ARMOR:
			return _armor_description(item_id)
		Category.CLOTHING:
			return "Одежда · не влияет на КД"
		Category.SHIELD:
			return "+2 к КД, пока щит экипирован"
		Category.AMMO:
			return "Боеприпасы для дальнобойного оружия"
		Category.PACK:
			return "Готовый набор снаряжения"
		Category.FOCUS:
			return "Заклинательный фокус"
		Category.TOOL:
			return "Инструменты / набор"
		_:
			return "Снаряжение"


static func _weapon_ability_label(weapon: Dictionary) -> String:
	if bool(weapon.get("ranged", false)):
		return "ЛОВ"
	if bool(weapon.get("finesse", false)):
		return "СИЛ/ЛОВ"
	return "СИЛ" if str(weapon.get("ability", "strength")) == "strength" else "ЛОВ"


static func _armor_description(item_id: StringName) -> String:
	match item_id:
		&"leather_armor":
			return "Лёгкий доспех · КД 11 + ЛОВ"
		&"studded_leather_armor":
			return "Лёгкий доспех · КД 12 + ЛОВ"
		&"chain_shirt":
			return "Средний доспех · КД 13 + ЛОВ (макс. 2)"
		&"chain_mail":
			return "Тяжёлый доспех · КД 16"
		_:
			return "Доспех"
