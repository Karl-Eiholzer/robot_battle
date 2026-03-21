extends Node2D
class_name RobotSprite

# Visual representation of a single robot on the hex map.
# Drawn as colored shapes (no art assets needed for prototype).

# ==================== Robot Data ====================

var robot_id: String = ""
var robot_team: int = 0
var robot_type: String = "captain"
var axial_pos: Vector2i = Vector2i.ZERO
var is_stunned: bool = false
var is_player_robot: bool = false
var is_selected: bool = false

# ==================== Colors ====================

# Team 0 = Blue family, Team 1 = Red family
const TEAM_COLORS: Dictionary = {
	0: {
		"captain":  Color(0.1, 0.3, 0.9),   # Strong blue
		"scout":    Color(0.3, 0.6, 1.0),   # Light blue
		"defender": Color(0.0, 0.1, 0.6),   # Dark blue
		"engineer": Color(0.2, 0.7, 0.9),   # Cyan-blue
	},
	1: {
		"captain":  Color(0.9, 0.1, 0.1),   # Strong red
		"scout":    Color(1.0, 0.4, 0.3),   # Light red/salmon
		"defender": Color(0.6, 0.0, 0.0),   # Dark red
		"engineer": Color(0.9, 0.5, 0.1),   # Orange-red
	}
}

# Type letter labels
const TYPE_LABELS: Dictionary = {
	"captain": "C",
	"scout": "S",
	"defender": "D",
	"engineer": "E",
}

const SHAPE_SIZE: float = 16.0

# ==================== Setup ====================

func setup(rid: String, team: int, rtype: String, pos: Vector2i, is_mine: bool) -> void:
	robot_id = rid
	robot_team = team
	robot_type = rtype
	axial_pos = pos
	is_player_robot = is_mine
	queue_redraw()

# ==================== Drawing ====================

func _draw() -> void:
	var color = TEAM_COLORS.get(robot_team, {}).get(robot_type, Color.WHITE)
	var outline_color = Color.WHITE if is_player_robot else Color(0.8, 0.8, 0.8, 0.5)

	match robot_type:
		"captain":
			# Large filled circle
			draw_circle(Vector2.ZERO, SHAPE_SIZE, color)
			draw_arc(Vector2.ZERO, SHAPE_SIZE, 0, TAU, 32, outline_color, 2.0)
		"scout":
			# Small circle
			draw_circle(Vector2.ZERO, SHAPE_SIZE * 0.7, color)
			draw_arc(Vector2.ZERO, SHAPE_SIZE * 0.7, 0, TAU, 32, outline_color, 2.0)
		"defender":
			# Square
			var half = SHAPE_SIZE * 0.85
			var rect = Rect2(-half, -half, half * 2, half * 2)
			draw_rect(rect, color)
			draw_rect(rect, outline_color, false, 2.0)
		"engineer":
			# Diamond (rotated square)
			var d = SHAPE_SIZE
			var points = PackedVector2Array([
				Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)
			])
			draw_colored_polygon(points, color)
			draw_polyline(PackedVector2Array([
				Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0), Vector2(0, -d)
			]), outline_color, 2.0)

	# Draw type letter
	# Note: draw_string requires a Font; use a simple placeholder
	# In Godot 4 we can use draw_string with default font from ThemeDB
	var font = ThemeDB.fallback_font
	if font:
		var label = TYPE_LABELS.get(robot_type, "?")
		var text_size = Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 14))
		draw_string(font, Vector2(-text_size.x / 2, text_size.y / 2 - 2), label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

	# Selection highlight: bright yellow ring drawn outside the shape
	if is_selected:
		draw_arc(Vector2.ZERO, SHAPE_SIZE + 7.0, 0, TAU, 36, Color(1.0, 0.9, 0.1, 1.0), 3.5)

	# Stunned indicator: red X
	if is_stunned:
		var s = SHAPE_SIZE * 0.6
		draw_line(Vector2(-s, -s), Vector2(s, s), Color.RED, 3.0)
		draw_line(Vector2(s, -s), Vector2(-s, s), Color.RED, 3.0)

# ==================== Animation ====================

func animate_move(from_pixel: Vector2, to_pixel: Vector2, duration: float = 0.4) -> void:
	position = from_pixel
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", to_pixel, duration)

func animate_bump(push_direction_pixel: Vector2, duration: float = 0.2) -> void:
	var start_pos = position
	var bump_pos = position + push_direction_pixel * 12.0
	var tween = create_tween()
	tween.tween_property(self, "position", bump_pos, duration * 0.4)
	tween.tween_property(self, "position", start_pos, duration * 0.6)

func show_stunned_flash() -> void:
	is_stunned = true
	queue_redraw()
	# Flash modulate
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 0.3, 0.3, 1), 0.15)
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	tween.set_loops(3)

func clear_stunned() -> void:
	is_stunned = false
	queue_redraw()

func set_stunned(stunned: bool) -> void:
	is_stunned = stunned
	queue_redraw()

func set_selected(selected: bool) -> void:
	is_selected = selected
	queue_redraw()
