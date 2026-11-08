class_name FeatureData
extends Resource
## One named class feature.
##
## Pure data: no behaviour lives here. Rules logic belongs in the character
## builder / rules service that reads these resources.

## Stable machine id, e.g. &"rage". Never localise this.
@export var id: StringName = &""
## Localised name shown in the UI.
@export var display_name: String = ""
## Localised rules text.
@export_multiline var description: String = ""
## Character level at which the feature is gained.
@export_range(1, 20, 1) var level: int = 1
