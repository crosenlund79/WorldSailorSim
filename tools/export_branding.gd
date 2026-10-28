extends SceneTree
## Rasterises the branding SVGs to transparent PNGs using Godot's own SVG
## renderer. The game itself uses the SVGs; the PNGs are convenience exports
## for documentation, store pages and anything that cannot consume SVG.
##
## Usage: godot --headless --path . -s res://tools/export_branding.gd

const SOURCE_DIR := "res://assets/branding/"
const OUTPUT_DIR := "res://assets/branding/png/"

## file name (without extension) -> list of output heights in pixels
## (The old next_harbor_* PNGs are kept unchanged for history.)
const EXPORTS := {
	"little_captains_hat_logo": [240, 480, 960],  # 240: the boot splash (I022)
	"little_captains_hat_logo_on_light": [480],
	"little_captains_hat_symbol": [64, 256, 512],
	"little_captains_hat_icon": [32, 64, 256, 512],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failures := 0
	for base_name: String in EXPORTS:
		var svg_text := FileAccess.get_file_as_string(SOURCE_DIR + base_name + ".svg")
		if svg_text.is_empty():
			push_error("Missing SVG: %s" % base_name)
			failures += 1
			continue
		var native := Image.new()
		native.load_svg_from_string(svg_text, 1.0)
		for height: int in EXPORTS[base_name]:
			var image := Image.new()
			var err := image.load_svg_from_string(svg_text, float(height) / native.get_height())
			if err != OK:
				push_error("Could not render %s" % base_name)
				failures += 1
				continue
			var out_path := OUTPUT_DIR + "%s_%d.png" % [base_name, height]
			image.save_png(out_path)
			print("Exported ", out_path, " (", image.get_width(), "x", image.get_height(), ")")
	quit(1 if failures > 0 else 0)
