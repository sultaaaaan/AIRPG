class_name Progression
extends RefCounted
## Level-up rules for the 2024 ruleset, content levels 1..5.
##
## Everything here is pure static data and arithmetic: the character builder
## and the UI read it, nothing mutates. Higher levels are intentionally absent
## until the class features for them are authored — see MAX_LEVEL.

## Highest level the shipped content supports. Raised when class feature
## tables cover more levels; the arithmetic below already generalises.
const MAX_LEVEL: int = 5

## Experience needed to *reach* each level. Index 0 is level 1.
const XP_THRESHOLDS: Array[int] = [0, 300, 900, 2700, 6500]

## Levels at which an Ability Score Improvement is granted.
const ASI_LEVELS: Array[int] = [4, 8, 12, 16, 19]

## Spell slots by character level for full casters (bard, cleric, druid,
## sorcerer, wizard). Each entry is the slots per spell level 1..n.
const FULL_CASTER_SLOTS: Array = [
	[2], [3], [4, 2], [4, 3], [4, 3, 2],
]

## Rangers get spellcasting at level 1 in 2024; paladins are still modelled
## without a SpellcastingData, so only ranger uses this table for now.
const HALF_CASTER_SLOTS: Array = [
	[2], [2], [3], [3], [4, 2],
]

## Pact Magic: [number of slots, slot level] by character level.
const PACT_SLOTS: Array = [
	[1, 1], [2, 1], [2, 2], [2, 2], [2, 3],
]


## Clamp any requested level into the supported range.
static func clamp_level(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL)


## True when the character may gain another level.
static func can_level_up(level: int) -> bool:
	return level < MAX_LEVEL


## XP required to reach `level`. Clamped, so level 99 does not crash.
static func xp_for_level(level: int) -> int:
	return XP_THRESHOLDS[clampi(level, 1, MAX_LEVEL) - 1]


## XP still needed for the next level, or 0 at the cap.
static func xp_to_next(level: int, xp: int) -> int:
	if not can_level_up(level):
		return 0
	return maxi(0, xp_for_level(level + 1) - xp)


## Highest level unlocked by the given XP total.
static func level_for_xp(xp: int) -> int:
	var reached := 1
	for index in XP_THRESHOLDS.size():
		if xp >= XP_THRESHOLDS[index]:
			reached = index + 1
	return reached


## Fixed hit points gained per level after the first: the die's average
## rounded up, before the Constitution modifier.
static func hit_points_per_level(hit_die: int) -> int:
	return hit_die / 2 + 1


## True when this level grants an Ability Score Improvement.
static func is_asi_level(level: int) -> bool:
	return level in ASI_LEVELS


## ASI levels the character has already reached, oldest first.
static func asi_levels_through(level: int) -> Array[int]:
	var out: Array[int] = []
	for asi_level in ASI_LEVELS:
		if asi_level <= level:
			out.append(asi_level)
	return out


static func full_slots(level: int) -> Array[int]:
	return _slots(FULL_CASTER_SLOTS, level)


static func half_slots(level: int) -> Array[int]:
	return _slots(HALF_CASTER_SLOTS, level)


## [slot count, slot level] for Pact Magic.
static func pact_slots(level: int) -> Array[int]:
	var row: Array = PACT_SLOTS[clampi(level, 1, MAX_LEVEL) - 1]
	var out: Array[int] = []
	for value in row:
		out.append(int(value))
	return out


static func _slots(table: Array, level: int) -> Array[int]:
	var row: Array = table[clampi(level, 1, MAX_LEVEL) - 1]
	var out: Array[int] = []
	for value in row:
		out.append(int(value))
	return out
