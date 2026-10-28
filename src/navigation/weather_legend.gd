class_name WeatherLegend
extends Control
## The weather overlay's legend in the chart's Weather tab: each kind's glyph,
## outline style and name, drawn with the same WeatherStyle as the map.

const ROW := 30.0
const KINDS := [WeatherEvent.KIND_GALE, WeatherEvent.KIND_THUNDER_RISK, WeatherEvent.KIND_THUNDERSTORM, WeatherEvent.KIND_CYCLONE]
const NAMES := ["Strong winds / gale area (inner ring: core)", "Thunderstorm risk (storms may form)",
	"Thunderstorm with squalls and gusts", "Tropical cyclone (not in European waters)"]

var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()
	custom_minimum_size = Vector2(0, ROW * KINDS.size() + 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.palette_changed.connect(queue_redraw)


func _draw() -> void:
	var font_size := 16
	for i in KINDS.size():
		var kind: StringName = KINDS[i]
		var style := WeatherStyle.style(kind)
		var y := i * ROW + ROW / 2.0
		var box := PackedVector2Array([Vector2(4, y - 10), Vector2(44, y - 10), Vector2(44, y + 10), Vector2(4, y + 10)])
		draw_colored_polygon(box, Color(style.color, maxf(float(style.fill), 0.08)))
		WeatherStyle.draw_outline(self, box, style.outline, Color(style.color, 0.95), 1.5)
		WeatherStyle.draw_glyph(self, kind, Vector2(24, y), 16.0, style.color)
		draw_string(_font, Vector2(56, y + font_size * 0.35), Loc.t(NAMES[i]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 60.0, font_size,
			UiTheme.color(&"ink"))
