extends Node2D

# Exists for exactly one reason: a different texture filter than Main's.
#
# Main draws with TEXTURE_FILTER_NEAREST, which is what the gate rings,
# character and background art want. The top HUD art does not: those four
# PNGs are high-resolution painted frames (439x148 and friends) drawn at
# roughly 40% size, and nearest-neighbour minification point-samples away
# more than half the pixels — the thin frame outlines, chain links and
# bubble highlights come out broken and jagged. Linear filtering with
# mipmaps resolves them cleanly instead.
#
# Texture filtering is a per-CanvasItem property with no per-draw override,
# so the only way to give the HUD its own is to hand it its own CanvasItem.
# That is all this node is. The drawing logic still lives in Main (see
# draw_hud_into) — this just supplies the canvas it happens on, and Main
# drives the redraws.
#
# Draw order note: a Node2D child renders after everything its parent draws,
# so putting the HUD here also lifts it above Main's effects layer. The one
# effect that actually overlapped the HUD was the combo glow (its top band
# covers the score box), so that is drawn here too, after the HUD, keeping
# the original glow-over-HUD look.

var main: Node = null


func _draw() -> void:
	if main == null:
		return
	main.draw_hud_into(self, get_viewport_rect().size)
