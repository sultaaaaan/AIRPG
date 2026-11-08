extends SceneTree
## Validates every content resource and smoke-tests CharacterDraft.
##
##   godot --headless --path . --script res://tools/validate_data.gd
##
## Exit code 0 = everything consistent. Wire this into CI so a bad .tres or a
## regression in the rules arithmetic cannot slip into the game.

var _failures := 0


func _initialize() -> void:
	_validate_classes()
	_validate_backgrounds()
	_validate_species()
	_validate_subclasses()
	_smoke_fighter()
	_smoke_subclass()
	_smoke_wizard()
	_smoke_monk()
	_smoke_paladin()
	_smoke_option_proficiencies()
	_smoke_inventory()
	_smoke_payload()

	print("-".repeat(64))
	if _failures == 0:
		print("OK — all content and draft checks passed")
	else:
		printerr("%d problem(s) found" % _failures)
	quit(0 if _failures == 0 else 1)


func _fail(message: String) -> void:
	printerr("  ! %s" % message)
	_failures += 1


# --- content resources ------------------------------------------------------

func _validate_classes() -> void:
	var classes := ClassRepository.load_all()
	print("classes: %d" % classes.size())
	if classes.size() != 12:
		_fail("expected 12 classes, found %d" % classes.size())
	for class_data in classes:
		for problem in class_data.validate():
			_fail("[%s] %s" % [class_data.id, problem])


func _validate_backgrounds() -> void:
	var backgrounds := BackgroundRepository.load_all()
	print("backgrounds: %d" % backgrounds.size())
	if backgrounds.size() != 16:
		_fail("expected 16 backgrounds, found %d" % backgrounds.size())
	for background in backgrounds:
		for problem in background.validate():
			_fail("[%s] %s" % [background.id, problem])


func _validate_species() -> void:
	var species_list := SpeciesRepository.load_all()
	print("species: %d" % species_list.size())
	if species_list.size() != 10:
		_fail("expected 10 species, found %d" % species_list.size())
	for species in species_list:
		for problem in species.validate():
			_fail("[%s] %s" % [species.id, problem])


func _validate_subclasses() -> void:
	var subclasses := SubclassRepository.load_all()
	print("subclasses: %d" % subclasses.size())
	if subclasses.size() != 48:
		_fail("expected 48 subclasses, found %d" % subclasses.size())

	var classes := ClassRepository.load_all()
	if classes.size() != 12:
		return

	var per_class := {}
	for subclass in subclasses:
		per_class[subclass.class_id] = int(per_class.get(subclass.class_id, 0)) + 1

		for problem in subclass.validate():
			_fail("[%s] %s" % [subclass.id, problem])

		var class_data := ClassRepository.find(subclass.class_id)
		if class_data == null:
			_fail("[%s] unknown class %s" % [subclass.id, subclass.class_id])
			continue
		if subclass.unlock_level != class_data.subclass_unlock_level:
			_fail("[%s] unlock level %d, class says %d" % [
				subclass.id, subclass.unlock_level, class_data.subclass_unlock_level,
			])

	for class_data in classes:
		var count := int(per_class.get(class_data.id, 0))
		if count != 4:
			_fail("[%s] expected 4 subclasses, found %d" % [class_data.id, count])

	for group in subclasses:
		for choice in group.choices:
			if choice.options.is_empty():
				_fail("[%s] choice %s has no options" % [group.id, choice.id])


# --- draft smoke tests ------------------------------------------------------

func _smoke_fighter() -> void:
	var draft := _draft(&"fighter", &"soldier", &"dwarf", "Дурган Камнещит")
	if draft == null:
		return

	var scores := {
		&"strength": 15, &"dexterity": 12, &"constitution": 14,
		&"intelligence": 8, &"wisdom": 10, &"charisma": 13,
	}
	if not draft.apply_standard_array(scores).is_empty():
		_fail("fighter: standard array rejected")

	var targets: Array[StringName] = [&"strength", &"dexterity", &"constitution"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"athletics", &"perception"]
	draft.skill_choices = skills
	draft.select_option(&"fighting_style", &"dueling")

	_expect(draft.ability_score(&"strength"), 17, "fighter STR 15+2")
	_expect(draft.ability_score(&"dexterity"), 13, "fighter DEX 12+1")
	_expect(draft.max_hit_points(), 13, "fighter HP 10+2+1(dwarf)")
	_expect(draft.armor_class(), 16, "fighter AC chain mail")
	_expect(draft.proficiency_bonus(), 2, "fighter PB")
	_expect(draft.initiative(), 1, "fighter initiative")
	_expect(draft.passive_perception(), 12, "fighter passive perception 10+0+2")
	_expect(draft.spell_save_dc(), 0, "fighter has no spell DC")
	_expect(draft.skill_proficiencies().size(), 3, "fighter skill union size")
	_expect(draft.starting_gold(), 0, "fighter took the pack")

	var problems := draft.validate()
	for problem in problems:
		_fail("fighter draft: %s" % problem)

	print(draft.summary())


## Subclasses are inert at level 1 and required from the unlock level on.
func _smoke_subclass() -> void:
	var draft := _draft(&"fighter", &"soldier", &"dwarf", "Подкласс")
	if draft == null:
		return

	var scores := {
		&"strength": 15, &"dexterity": 12, &"constitution": 14,
		&"intelligence": 8, &"wisdom": 10, &"charisma": 13,
	}
	draft.apply_standard_array(scores)
	var targets: Array[StringName] = [&"strength", &"dexterity", &"constitution"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"athletics", &"perception"]
	draft.skill_choices = skills
	draft.select_option(&"fighting_style", &"dueling")

	if not draft.validate().is_empty():
		_fail("subclass: level-1 draft should be valid without a subclass")

	draft.level = 3
	if draft.validate().is_empty():
		_fail("subclass: level 3 must require a subclass")

	var champion := SubclassRepository.find(&"champion")
	if champion == null:
		_fail("subclass: champion not found")
		return
	if champion.class_id != &"fighter":
		_fail("subclass: champion belongs to %s" % champion.class_id)
	draft.subclass = champion
	for problem in draft.validate():
		_fail("subclass draft: %s" % problem)

	var wrong := SubclassRepository.for_class(&"wizard")
	if wrong.is_empty():
		_fail("subclass: wizard has no subclasses")
		return
	draft.subclass = wrong[0]
	if draft.validate().is_empty():
		_fail("subclass: a wizard subclass must be rejected for a fighter")


func _smoke_wizard() -> void:
	var draft := _draft(&"wizard", &"sage", &"human", "Мира Тихоня")
	if draft == null:
		return

	var scores := {
		&"strength": 8, &"dexterity": 14, &"constitution": 13,
		&"intelligence": 15, &"wisdom": 12, &"charisma": 10,
	}
	draft.apply_standard_array(scores)

	var targets: Array[StringName] = [&"intelligence", &"constitution", &"wisdom"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"investigation", &"arcana"]
	draft.skill_choices = skills
	draft.chosen_size = &"medium"
	var languages: Array[StringName] = [&"elvish"]
	draft.chosen_languages = languages

	_expect(draft.ability_score(&"intelligence"), 17, "wizard INT 15+2")
	_expect(draft.spell_save_dc(), 13, "wizard DC 8+2+3")
	_expect(draft.spell_attack_bonus(), 5, "wizard spell attack +5")
	_expect(draft.max_hit_points(), 8, "wizard HP 6+2")
	_expect(draft.armor_class(), 12, "wizard AC 10+2")
	_expect(draft.proficiency_bonus(), 2, "wizard PB")
	draft.equipment_mode = CharacterDraft.EquipmentMode.GOLD
	_expect(draft.starting_gold(), 105, "wizard gold 55+50")

	for problem in draft.validate():
		_fail("wizard draft: %s" % problem)


func _smoke_monk() -> void:
	var draft := _draft(&"monk", &"wayfarer", &"halfling", "Пип Удача")
	if draft == null:
		return

	var scores := {
		&"strength": 10, &"dexterity": 15, &"constitution": 13,
		&"intelligence": 8, &"wisdom": 14, &"charisma": 12,
	}
	draft.apply_standard_array(scores)

	var targets: Array[StringName] = [&"dexterity", &"wisdom", &"charisma"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"acrobatics", &"stealth"]
	draft.skill_choices = skills

	_expect(draft.ability_score(&"dexterity"), 17, "monk DEX 15+2")
	_expect(draft.ability_score(&"wisdom"), 15, "monk WIS 14+1")
	_expect(draft.armor_class(), 15, "monk AC 10+3+2")
	_expect(draft.max_hit_points(), 9, "monk HP 8+1")
	_expect(draft.resolved_size(), &"small", "monk halfling size")
	_expect(draft.has_species_trait(&"luck"), true, "monk halfling luck trait")

	for problem in draft.validate():
		_fail("monk draft: %s" % problem)


func _smoke_paladin() -> void:
	var draft := _draft(&"paladin", &"noble", &"orc", "Грак Клятва")
	if draft == null:
		return

	var scores := {
		&"strength": 15, &"dexterity": 10, &"constitution": 14,
		&"intelligence": 8, &"wisdom": 12, &"charisma": 13,
	}
	draft.apply_standard_array(scores)

	var targets: Array[StringName] = [&"strength", &"charisma", &"intelligence"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"athletics", &"persuasion"]
	draft.skill_choices = skills

	_expect(draft.spell_save_dc(), 12, "paladin spell DC 8+2+2")
	_expect(draft.spell_slots_text(), "1 ур.: 2", "paladin level-1 slots")
	_expect(draft.max_hit_points(), 12, "paladin HP 10+2")

	for problem in draft.validate():
		_fail("paladin draft: %s" % problem)


## The network payload must survive a round-trip and stay valid; a tampered
## class id must not validate. `derived` numbers are recomputed, not trusted.
func _smoke_payload() -> void:
	var draft := _draft(&"fighter", &"soldier", &"dwarf", "Пейлоад")
	if draft == null:
		return

	var scores := {
		&"strength": 15, &"dexterity": 12, &"constitution": 14,
		&"intelligence": 8, &"wisdom": 10, &"charisma": 13,
	}
	draft.apply_standard_array(scores)
	var targets: Array[StringName] = [&"strength", &"dexterity", &"constitution"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"athletics", &"perception"]
	draft.skill_choices = skills
	draft.select_option(&"fighting_style", &"dueling")

	var payload := draft.to_payload()
	var rebuilt := CharacterDraft.from_payload(payload)
	if rebuilt == null:
		_fail("payload: from_payload returned null")
		return
	for problem in rebuilt.validate():
		_fail("payload round-trip: %s" % problem)
	_expect(rebuilt.max_hit_points(), draft.max_hit_points(), "payload HP")
	_expect(rebuilt.armor_class(), draft.armor_class(), "payload AC")
	_expect(rebuilt.character_name, "Пейлоад", "payload name")
	_expect(rebuilt.skill_proficiencies(), draft.skill_proficiencies(), "payload skills")

	var broken := payload.duplicate(true)
	broken["class"] = &"nonsense"
	var invalid := CharacterDraft.from_payload(broken)
	if invalid == null or invalid.validate().is_empty():
		_fail("payload: an unknown class must not validate")
	_expect("martial" in rebuilt.weapon_training(), true, "payload weapon training")
	_expect("heavy" in rebuilt.armor_training(), true, "payload armour training")


## Options such as the Cleric's Divine Order grant proficiencies that must be
## added on top of the class list.
func _smoke_option_proficiencies() -> void:
	var draft := _draft(&"cleric", &"sage", &"human", "Орден")
	if draft == null:
		return

	var scores := {
		&"strength": 10, &"dexterity": 12, &"constitution": 13,
		&"intelligence": 14, &"wisdom": 15, &"charisma": 8,
	}
	draft.apply_standard_array(scores)
	var targets: Array[StringName] = [&"wisdom", &"constitution", &"intelligence"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"insight", &"religion"]
	draft.skill_choices = skills
	draft.chosen_size = &"medium"
	var languages: Array[StringName] = [&"elvish"]
	draft.chosen_languages = languages
	draft.select_option(&"divine_order", &"protector")

	_expect("heavy" in draft.armor_training(), true, "cleric protector heavy armour")
	_expect("martial" in draft.weapon_training(), true, "cleric protector martial weapons")
	for problem in draft.validate():
		_fail("option proficiencies draft: %s" % problem)


## The starting kit must turn into a usable inventory: categories, quantities,
## stacking and the "leftover" contract of add_item.
func _smoke_inventory() -> void:
	var draft := _draft(&"fighter", &"soldier", &"dwarf", "Сумка")
	if draft == null:
		return

	var scores := {
		&"strength": 15, &"dexterity": 12, &"constitution": 14,
		&"intelligence": 8, &"wisdom": 10, &"charisma": 13,
	}
	draft.apply_standard_array(scores)
	var targets: Array[StringName] = [&"strength", &"dexterity", &"constitution"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"athletics", &"perception"]
	draft.skill_choices = skills
	draft.select_option(&"fighting_style", &"dueling")

	var derived: Dictionary = draft.to_payload()["derived"]
	var inventory := Inventory.new()
	inventory.setup(derived["equipment"], int(derived["gold"]))

	_expect(inventory.has_item(&"greatsword"), true, "inventory has greatsword")
	_expect(inventory.has_item(&"chain_mail"), true, "inventory has chain mail")
	_expect(inventory.get_item_count(&"javelin"), 8, "inventory javelin count")
	_expect(ItemCatalog.category(&"greatsword"), ItemCatalog.Category.WEAPON, "catalog weapon")
	_expect(ItemCatalog.category(&"chain_mail"), ItemCatalog.Category.ARMOR, "catalog armor")
	_expect(ItemCatalog.category(&"arrow"), ItemCatalog.Category.AMMO, "catalog ammo")
	_expect(ItemCatalog.stack_size(&"arrow"), 999, "catalog arrow stack")

	var leftover := inventory.add_item(&"arrow", "Стрела", 15)
	_expect(leftover, 0, "inventory arrow add leftover")
	_expect(inventory.get_item_count(&"arrow"), 35, "inventory arrow total")
	_expect(inventory.remove_item(&"arrow", 50), 35, "inventory arrow removed")
	_expect(inventory.has_item(&"arrow"), false, "inventory arrows fully removed")

	var restored := Inventory.new()
	restored.apply_payload(inventory.to_payload())
	_expect(restored.get_item_count(&"greatsword"), 1, "inventory payload greatsword")
	_expect(restored.get_item_count(&"chain_mail"), 1, "inventory payload chain mail")
	_expect(restored.gold, inventory.gold, "inventory payload gold")


# --- helpers ----------------------------------------------------------------

func _draft(class_id: StringName, background_id: StringName, species_id: StringName, named: String) -> CharacterDraft:
	var class_data := ClassRepository.find(class_id)
	var background := BackgroundRepository.find(background_id)
	var species := SpeciesRepository.find(species_id)
	if class_data == null or background == null or species == null:
		_fail("draft setup: missing %s / %s / %s" % [class_id, background_id, species_id])
		return null

	var draft := CharacterDraft.new()
	draft.character_name = named
	draft.class_data = class_data
	draft.background = background
	draft.species = species
	return draft


func _expect(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s: expected %s, got %s" % [label, expected, actual])
