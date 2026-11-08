extends SceneTree
## Adds the level 2..5 class features to res://data/classes/*.tres.
##
##   godot --headless --path . --script res://tools/generate_level_features.gd
##
## Re-runnable: existing features above level 1 are replaced, level-1 features
## are kept. This keeps the levelling tables in one readable place instead of
## hand-editing twelve binary-ish resources.

const CLASS_DIR := "res://data/classes"

## class id -> Array of [level, feature id, name, description].
const TABLE := {
	&"barbarian": [
		[2, &"danger_sense", "Чутьё опасности", "Вы получаете преимущество на спасброски Ловкости от эффектов, которые видите."],
		[2, &"reckless_attack", "Безрассудная атака", "В свой ход вы можете атаковать с преимуществом, но враги получают преимущество против вас до вашего следующего хода."],
		[3, &"primal_knowledge", "Первобытные знания", "Вы получаете владение ещё одним навыком из списка варвара."],
		[5, &"fast_movement", "Быстрое перемещение", "Скорость увеличивается на 10 футов, пока вы не носите тяжёлый доспех."],
	],
	&"bard": [
		[2, &"jack_of_all_trades", "Мастер на все руки", "Добавляйте половину бонуса мастерства к проверкам характеристик без владения."],
		[3, &"expertise", "Компетентность", "Выберите два навыка с владением: удвойте бонус мастерства для них."],
		[5, &"font_of_inspiration", "Источник вдохновения", "Вы восстанавливаете вдохновение барда на коротком отдыхе."],
	],
	&"cleric": [
		[2, &"channel_divinity", "Божественный канал", "Вы получаете способность направлять божественную силу: «Божественная искра» и «Изгнание нежити»."],
		[5, &"sear_undead", "Выжигание нежити", "Изгнанная нежить получает урон излучением, пока изгнана."],
	],
	&"druid": [
		[2, &"wild_shape", "Дикий облик", "Бонусным действием вы превращаетесь в зверя, которого видели."],
		[2, &"wild_companion", "Дикий спутник", "Вы призываете духа-зверя, помогающего вам."],
		[5, &"wild_resurgence", "Возрождение природы", "Вы можете потратить ячейку заклинания, чтобы восстановить использование Дикого облика, или наоборот."],
	],
	&"fighter": [
		[2, &"action_surge", "Всплеск действий", "Один раз между отдыхами вы совершаете дополнительное действие в свой ход."],
		[2, &"tactical_mind", "Тактический ум", "Потратив Второе дыхание, вы можете улучшить проверку характеристики или бросок урона."],
		[5, &"extra_attack", "Дополнительная атака", "При действии «Атака» вы атакуете дважды."],
		[5, &"tactical_shift", "Тактический сдвиг", "Используя Второе дыхание, вы можете переместиться, не провоцируя атак."],
	],
	&"monk": [
		[2, &"monks_focus", "Сосредоточение монаха", "Вы получаете очки ци и можете направлять их в удары и защиту."],
		[2, &"unarmored_movement", "Движение без доспехов", "Ваша скорость растёт, пока вы не носите доспех и не используете щит."],
		[2, &"uncanny_metabolism", "Невероятный метаболизм", "Один раз между отдыхами вы восстанавливаете ци и хиты."],
		[3, &"deflect_attacks", "Отражение атак", "Реакцией вы уменьшаете урон от атаки, а при удачном отражении можете вернуть его."],
		[4, &"slow_fall", "Медленное падение", "Реакцией вы снижаете урон от падения."],
		[5, &"extra_attack", "Дополнительная атака", "При действии «Атака» вы атакуете дважды."],
		[5, &"stunning_strike", "Ошеломляющий удар", "Тратя ци, вы можете оглушить цель ударом."],
	],
	&"paladin": [
		[2, &"fighting_style", "Боевой стиль", "Вы получаете черту боевого стиля."],
		[2, &"paladins_smite", "Кара паладина", "Вы всегда готовите «Божественную кару» и можете наложить её без подготовки."],
		[3, &"channel_divinity", "Божественный канал", "Вы получаете «Божественное чувство» и «Изгнание нежити»."],
		[5, &"extra_attack", "Дополнительная атака", "При действии «Атака» вы атакуете дважды."],
		[5, &"faithful_steed", "Верный скакун", "Вы призываете скакуна, связанного с вашей клятвой."],
	],
	&"ranger": [
		[1, &"spellcasting", "Заклинания", "Вы можете накладывать заклинания следопыта, используя Мудрость."],
		[2, &"deft_explorer", "Ловкий исследователь", "Вы получаете экспертизу в одном навыке и знание ещё одного языка."],
		[2, &"fighting_style", "Боевой стиль", "Вы получаете черту боевого стиля."],
		[3, &"primal_knowledge", "Первобытные знания", "Вы получаете владение ещё одним навыком из списка следопыта."],
		[5, &"extra_attack", "Дополнительная атака", "При действии «Атака» вы атакуете дважды."],
	],
	&"rogue": [
		[1, &"expertise", "Компетентность", "Выберите два навыка с владением: удвойте бонус мастерства для них."],
		[2, &"cunning_action", "Хитрое действие", "Бонусным действием вы совершаете Рывок, Отход или Засаду."],
		[3, &"steady_aim", "Верный прицел", "Бонусным действием вы получаете преимущество на следующую атаку."],
		[5, &"cunning_strike", "Хитрый удар", "Вы можете пожертвовать частью скрытой атаки ради эффекта."],
		[5, &"uncanny_dodge", "Невероятное уклонение", "Реакцией вы уменьшаете вдвое урон от одной атаки."],
	],
	&"sorcerer": [
		[2, &"font_of_magic", "Источник магии", "Вы получаете очки чародейства и можете превращать их в ячейки и обратно."],
		[2, &"metamagic", "Метамагия", "Вы выбираете два способа изменять заклинания за очки чародейства."],
		[5, &"sorcerous_restoration", "Восстановление чародейства", "На коротком отдыхе вы восстанавливаете часть очков чародейства."],
	],
	&"warlock": [
		[2, &"magical_cunning", "Магическая хитрость", "Один раз между отдыхами вы восстанавливаете ячейки договора."],
		[5, &"eldritch_invocation", "Дополнительное воззвание", "Вы изучаете ещё одно воззвание."],
	],
	&"wizard": [
		[1, &"ritual_adept", "Ритуальное мастерство", "Вы можете накладывать заклинания с ритуалом без подготовки, если они есть в книге."],
		[2, &"scholar", "Эрудит", "Вы получаете экспертизу в одном навыке из списка волшебника."],
		[5, &"memorize_spell", "Запоминание заклинания", "Вы можете подготовить заклинание из книги за 1 минуту."],
	],
}

## Level-1 features the first generation missed, kept for completeness.
const LEVEL_ONE_ADDITIONS := {
	&"paladin": [
		[1, &"spellcasting", "Заклинания", "Вы можете накладывать заклинания паладина, используя Харизму."],
	],
}


func _initialize() -> void:
	var saved := 0
	for class_id in TABLE.keys():
		var path := "%s/%s.tres" % [CLASS_DIR, class_id]
		var class_data: ClassData = load(path)
		if class_data == null:
			printerr("cannot load %s" % path)
			continue

		_apply(class_data, TABLE[class_id])
		if LEVEL_ONE_ADDITIONS.has(class_id):
			_apply(class_data, LEVEL_ONE_ADDITIONS[class_id])

		var error := ResourceSaver.save(class_data, path)
		if error != OK:
			printerr("failed to save %s: %s" % [path, error_string(error)])
		else:
			print("saved %s (%d features)" % [path, class_data.features.size()])
			saved += 1

	print("done: %d classes" % saved)
	quit(0 if saved == TABLE.size() else 1)


func _apply(class_data: ClassData, rows: Array) -> void:
	for row in rows:
		var feature_id: StringName = row[1]
		_remove_feature(class_data, feature_id)
		var feature := FeatureData.new()
		feature.id = feature_id
		feature.display_name = row[2]
		feature.description = row[3]
		feature.level = int(row[0])
		class_data.features.append(feature)


## Re-runnable: drop a previous copy before appending the new one.
func _remove_feature(class_data: ClassData, feature_id: StringName) -> void:
	var kept: Array[FeatureData] = []
	for feature in class_data.features:
		if feature != null and feature.id == feature_id:
			continue
		kept.append(feature)
	class_data.features = kept
