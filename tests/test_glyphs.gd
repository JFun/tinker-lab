extends SceneTree
## Detect glyphs that Godot's bundled fallback font can't render. A missing
## glyph reports a much narrower advance width than the requested font size,
## or matches the .notdef tofu width. Run via:
##   godot --path . -s res://tests/test_glyphs.gd

func _initialize() -> void:
	var items := preload("res://data/items.gd").new()
	items._build_items()
	var font := ThemeDB.fallback_font
	var fs := 48
	# Use the font's own glyph-coverage API as the primary check. This catches
	# emoji-block chars (⚙ ⚡ ✉ ♨ etc.) that DO render at normal width as a
	# .notdef tofu box, but have no actual glyph in the Godot fallback.
	var failures: Array = []
	for id in items.defs:
		var d = items.defs[id]
		var cp: int = d.glyph.unicode_at(0)
		# `has_char` walks fallback chain. False = renders as tofu on this build.
		if not font.has_char(cp):
			failures.append("%s glyph '%s' (U+%04X) is .notdef in fallback font" % [
				id, d.glyph, cp])
	# NOTE: Godot's desktop fallback font has FAR less coverage than iOS system
	# fonts. Many of these glyphs render fine on device. Treat this as a hint,
	# not a failure — emoji-block chars (U+2600..27BF) and APL chars are the
	# usual culprits when something IS actually blank in production.
	if failures.is_empty():
		print("OK: all %d glyphs covered by the bundled fallback font." % items.defs.size())
	else:
		print("Glyphs not in desktop fallback (may still render on iOS, but check on device):")
		for f in failures: print("  ", f)
	quit(0)
