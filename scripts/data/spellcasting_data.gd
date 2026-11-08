class_name SpellcastingData
extends Resource
## Level-1 spellcasting numbers for a class.
##
## Spell *lists* are deliberately not stored here; they are a separate
## catalogue. This resource only answers "how many does this class get".
## Warlock is the reason `recovery` exists: Pact Magic returns on a short rest.

enum Recovery {
	LONG_REST,
	SHORT_REST,
}

## Spellcasting ability, e.g. &"wisdom".
@export var ability: StringName = &"intelligence"

@export_group("Level 1")
@export_range(0, 10, 1) var cantrips_known: int = 0
## Spells prepared / known at level 1. Wizard prepares from a spellbook.
@export_range(0, 20, 1) var spells_prepared: int = 0
## Wizard only: how many level-1 spells start in the spellbook.
@export_range(0, 20, 1) var spellbook_spells: int = 0
@export_range(0, 4, 1) var level_1_slots: int = 0
@export var recovery: Recovery = Recovery.LONG_REST

@export_group("Traits")
## Can cast spells with the Ritual tag without preparing them.
@export var ritual_caster: bool = false
## Knows a fixed secret language tied to spellcasting (Druidic).
@export var secret_language: StringName = &""
