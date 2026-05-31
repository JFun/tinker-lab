extends Control
## Preloaded as `UIIcon` by callers (village.gd, workbench.gd):
##   const UIIcon := preload("res://scenes/ui_icon.gd")
## Not using class_name so headless tool runs don't need the global class cache.
## Vector UI icon drawn with primitives so it renders identically on every
## platform. Emoji / symbol glyphs (☀⚙✉🏘📖🔬🎯🚚💡🎉🏆) TOFU on iOS even
## though they render fine on desktop — never put them in a Label/Button.
## The project font only covers geometric glyphs (●○◆★∿✱…); everything else
## must be drawn here.

var kind := ""
var col := Color.WHITE

func _init(k: String = "", c: Color = Color.WHITE) -> void:
	kind = k
	col = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_color(c: Color) -> void:
	col = c
	queue_redraw()

func _pt(nx: float, ny: float) -> Vector2:
	var d: float = min(size.x, size.y)
	var o: Vector2 = (size - Vector2(d, d)) * 0.5
	return o + Vector2(nx * d, ny * d)

func _ln(a: Vector2, b: Vector2, w: float) -> void:
	draw_line(a, b, col, w, true)

func _draw() -> void:
	var d: float = min(size.x, size.y)
	if d <= 0: return
	var lw: float = max(2.0, d * 0.075)
	match kind:
		"lamp":  # street lamp: bulb + post + base
			draw_circle(_pt(0.5, 0.30), d * 0.16, col)
			_ln(_pt(0.40, 0.15), _pt(0.60, 0.15), lw)
			_ln(_pt(0.5, 0.46), _pt(0.5, 0.86), lw)
			_ln(_pt(0.34, 0.86), _pt(0.66, 0.86), lw)
		"clock":  # clock face + two hands
			draw_arc(_pt(0.5, 0.48), d * 0.34, 0, TAU, 40, col, lw, true)
			_ln(_pt(0.5, 0.48), _pt(0.5, 0.26), lw)
			_ln(_pt(0.5, 0.48), _pt(0.70, 0.55), lw)
		"star":  # 4-point sparkle
			var c := _pt(0.5, 0.5)
			var pts := PackedVector2Array()
			for i in 8:
				var ang := deg_to_rad(i * 45.0 - 90.0)
				var rad := (0.42 if i % 2 == 0 else 0.16) * d
				pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
			draw_colored_polygon(pts, col)
		"loaf":  # bread loaf: rounded body + score lines
			var top := _pt(0.18, 0.44)
			var bot := _pt(0.82, 0.70)
			draw_rect(Rect2(top, bot - top), col, true)
			draw_circle(Vector2(top.x, (top.y + bot.y) * 0.5), (bot.y - top.y) * 0.5, col)
			draw_circle(Vector2(bot.x, (top.y + bot.y) * 0.5), (bot.y - top.y) * 0.5, col)
			var dark := col.darkened(0.55)
			for sx in [0.34, 0.5, 0.66]:
				draw_line(_pt(sx - 0.05, 0.48), _pt(sx + 0.03, 0.66), dark, lw * 0.7, true)
		"envelope":  # rectangle + flap
			var a := _pt(0.18, 0.34)
			var b := _pt(0.82, 0.66)
			draw_rect(Rect2(a, b - a), col, false, lw)
			_ln(_pt(0.18, 0.34), _pt(0.5, 0.53), lw)
			_ln(_pt(0.82, 0.34), _pt(0.5, 0.53), lw)
		"house":  # roof triangle + body + door
			var roof := PackedVector2Array([_pt(0.5, 0.16), _pt(0.88, 0.48), _pt(0.12, 0.48)])
			draw_colored_polygon(roof, col)
			var ba := _pt(0.24, 0.48)
			var bb := _pt(0.76, 0.84)
			draw_rect(Rect2(ba, bb - ba), col, true)
			var da := _pt(0.44, 0.62)
			var db := _pt(0.56, 0.84)
			draw_rect(Rect2(da, db - da), col.darkened(0.5), true)
		"book":  # open book: outline + spine + text lines
			var a := _pt(0.18, 0.28)
			var b := _pt(0.82, 0.72)
			draw_rect(Rect2(a, b - a), col, false, lw)
			_ln(_pt(0.5, 0.28), _pt(0.5, 0.72), lw)
			for ly in [0.42, 0.55]:
				_ln(_pt(0.26, ly), _pt(0.44, ly), lw * 0.7)
				_ln(_pt(0.56, ly), _pt(0.74, ly), lw * 0.7)
		"dots":  # ••• more menu
			for dx in [0.30, 0.5, 0.70]:
				draw_circle(_pt(dx, 0.5), d * 0.07, col)
		"magnify":  # magnifying glass — discovery counter
			draw_arc(_pt(0.42, 0.42), d * 0.26, 0, TAU, 32, col, lw, true)
			_ln(_pt(0.61, 0.61), _pt(0.84, 0.84), lw * 1.3)
		"target":  # concentric rings + bullseye — goal banner
			draw_arc(_pt(0.5, 0.5), d * 0.38, 0, TAU, 40, col, lw, true)
			draw_arc(_pt(0.5, 0.5), d * 0.20, 0, TAU, 28, col, lw, true)
			draw_circle(_pt(0.5, 0.5), d * 0.07, col)
		"truck":  # delivery van — cargo box + cab + wheels
			var cg := _pt(0.08, 0.34)
			var cgb := _pt(0.56, 0.64)
			draw_rect(Rect2(cg, cgb - cg), col, true)
			var cab := PackedVector2Array([
				_pt(0.56, 0.44), _pt(0.74, 0.44), _pt(0.86, 0.56), _pt(0.86, 0.64), _pt(0.56, 0.64)])
			draw_colored_polygon(cab, col)
			var bg := col.darkened(0.6)
			draw_circle(_pt(0.24, 0.72), d * 0.09, col)
			draw_circle(_pt(0.24, 0.72), d * 0.04, bg)
			draw_circle(_pt(0.70, 0.72), d * 0.09, col)
			draw_circle(_pt(0.70, 0.72), d * 0.04, bg)
		"arrow_left":  # back chevron + shaft
			_ln(_pt(0.80, 0.5), _pt(0.30, 0.5), lw)
			_ln(_pt(0.30, 0.5), _pt(0.50, 0.32), lw)
			_ln(_pt(0.30, 0.5), _pt(0.50, 0.68), lw)
