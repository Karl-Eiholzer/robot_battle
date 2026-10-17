extends Node2D
class_name HexMap

# Renders the hex grid, hex objects, robots, and planned robot paths.
# Emits hex input signals (click, hover, drag, right-click) for game_view.
# Manages fog of war by dimming/hiding hexes and enemies.

signal hex_clicked(hex: Vector2i)
signal hex_hovered(hex: Vector2i)
# Left button held while the mouse enters a new hex (path painting).
signal hex_drag_entered(hex: Vector2i)
# Right press+release without dragging (dragging pans the camera).
signal hex_right_clicked(hex: Vector2i, screen_pos: Vector2)

# ==================== Constants ====================

const HEX_SIZE: float = 48.0
const TERRAIN_COLORS: Dictionary = {
	"plains":   Color(0.55, 0.76, 0.29),
	"forest":   Color(0.18, 0.49, 0.18),
	"mountain": Color(0.55, 0.47, 0.35),
	"water":    Color(0.20, 0.45, 0.80),
	"obstacle": Color(0.35, 0.30, 0.25),
	"spawn":    Color(0.70, 0.70, 0.50),
	"default":  Color(0.50, 0.65, 0.40),
}
const HEX_OBJECT_COLORS: Dictionary = {
	"emp":         Color(0.6, 0.1, 0.8),   # Purple
	"firewall":    Color(0.9, 0.5, 0.1),   # Orange
	"supply_drop": Color(0.1, 0.8, 0.2),   # Green
	"obstacle":    Color(0.4, 0.35, 0.3),  # Brown
}

# ==================== State ====================

# hex_coords: Dictionary  Vector2i -> bool (all known hexes)
var _hex_coords: Dictionary = {}
# hex_terrain: Dictionary  Vector2i -> String
var _hex_terrain: Dictionary = {}
# visible_hexes: set of Vector2i (for fog of war)
var _visible_hexes: Dictionary = {}
# highlight_hexes: Dictionary  Vector2i -> Color  (deploy targeting)
var _highlight_hexes: Dictionary = {}
# adjacent_highlight_hexes: Dictionary  Vector2i -> Color  (valid moves for selected robot)
var _adjacent_highlight_hexes: Dictionary = {}
# Planned paths for the player's robots, rebuilt by update_plan_display():
# Array of {points: PackedVector2Array, color: Color, selected: bool,
#           tip: Vector2, labels: Dictionary Vector2i -> Array[String],
#           issues: Array[Vector2i], deploys: Array[{hex, label}]}
var _plan_paths: Array = []
# Hover preview route from the selected robot's cursor: Array of Vector2 points.
var _hover_points: PackedVector2Array = PackedVector2Array()
var _hover_valid: bool = true

# Mouse tracking for hover/drag/right-click detection
var _last_hover_hex: Vector2i = Vector2i(-9999, -9999)
var _right_press_pos: Vector2 = Vector2.ZERO

# Robot sprite nodes: robot_id -> RobotSprite node
var _robot_sprites: Dictionary = {}

# Currently selected robot id (for highlight)
var _selected_robot_id: String = ""

# Hex object indicators: position key String "q,r,type" -> Label/node
var _hex_object_nodes: Dictionary = {}

# ==================== Init ====================

func _ready() -> void:
	set_process_input(true)

# ==================== Map Population ====================

func populate_from_game_state() -> void:
	_clear_all()
	_build_hex_grid()
	_rebuild_visible_hexes()
	_place_robots()
	_place_hex_objects()
	queue_redraw()

func _build_hex_grid() -> void:
	var map = GameState.map_data
	var hexes = map.get("hexes", [])
	for hex_data in hexes:
		var q = int(hex_data.get("q", 0))
		var r = int(hex_data.get("r", 0))
		var coord = Vector2i(q, r)
		_hex_coords[coord] = true
		_hex_terrain[coord] = hex_data.get("terrain", "default")

# Returns true if hex exists in the map grid.
func has_hex(hex: Vector2i) -> bool:
	return hex in _hex_coords

# Returns the average world position of the player's robots (for camera centering).
func get_player_robots_centroid() -> Vector2:
	if GameState.player_robots.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for robot in GameState.player_robots:
		var pos = robot.get("position", [0, 0])
		sum += HexMath.axial_to_pixel(Vector2i(int(pos[0]), int(pos[1])), HEX_SIZE)
	return sum / float(GameState.player_robots.size())

func _rebuild_visible_hexes() -> void:
	_visible_hexes.clear()
	for robot in GameState.player_robots:
		var pos = robot.get("position", [0, 0])
		var center = Vector2i(int(pos[0]), int(pos[1]))
		var robot_type = robot.get("type", "captain")
		var sight = TurnInput.ROBOT_STATS.get(robot_type, {}).get("sight_range", 5)
		for hex in HexMath.hexes_in_radius(center, sight):
			_visible_hexes[hex] = true

# ==================== Robot Management ====================

func _place_robots() -> void:
	for robot in GameState.player_robots:
		_add_or_update_robot(robot, true)
	for robot in GameState.visible_enemies:
		_add_or_update_robot(robot, false)

func _add_or_update_robot(robot: Dictionary, is_mine: bool) -> void:
	var robot_id = robot.get("robot_id", "")
	var pos = robot.get("position", [0, 0])
	var hex = Vector2i(int(pos[0]), int(pos[1]))
	var pixel = HexMath.axial_to_pixel(hex, HEX_SIZE)

	if robot_id in _robot_sprites:
		var existing := _robot_sprites[robot_id] as RobotSprite
		existing.position = pixel
		existing.axial_pos = hex
		existing.set_stunned(robot.get("state", "active") == "stunned")
		return

	var sprite := RobotSprite.new()
	add_child(sprite)
	sprite.setup(robot_id,
		robot.get("team", 0),
		robot.get("type", "captain"),
		hex, is_mine)
	sprite.position = pixel
	sprite.set_stunned(robot.get("state", "active") == "stunned")
	_robot_sprites[robot_id] = sprite

func update_robot_position(robot_id: String, hex: Vector2i) -> void:
	if robot_id in _robot_sprites:
		var sprite = _robot_sprites[robot_id]
		sprite.axial_pos = hex
		sprite.position = HexMath.axial_to_pixel(hex, HEX_SIZE)

func remove_robot(robot_id: String) -> void:
	if robot_id in _robot_sprites:
		_robot_sprites[robot_id].queue_free()
		_robot_sprites.erase(robot_id)

func get_robot_sprite(robot_id: String) -> Node2D:
	return _robot_sprites.get(robot_id, null)

# Reset map visuals to the state at the start of a turn for replay rewatching.
func reset_for_replay(replay_data: Dictionary) -> void:
	var rounds = replay_data.get("rounds", [])
	if not rounds.is_empty():
		for robot_replay in rounds[0]:
			var robot_id = robot_replay.get("robot_id", "")
			var before = robot_replay.get("before_position", [0, 0])
			var hex = Vector2i(int(before[0]), int(before[1]))
			if robot_id in _robot_sprites:
				_robot_sprites[robot_id].position = HexMath.axial_to_pixel(hex, HEX_SIZE)

	for obj in replay_data.get("hex_objects_created", []):
		var pos = obj.get("position", [0, 0])
		remove_hex_object(int(pos[0]), int(pos[1]), obj.get("type", ""))
	for obj in replay_data.get("hex_objects_destroyed", []):
		_add_hex_object_node(obj)

	queue_redraw()

func set_selected_robot(robot_id: String) -> void:
	if _selected_robot_id != "" and _selected_robot_id in _robot_sprites:
		_robot_sprites[_selected_robot_id].set_selected(false)
	_selected_robot_id = robot_id
	if robot_id != "" and robot_id in _robot_sprites:
		_robot_sprites[robot_id].set_selected(true)

# ==================== Plan Display ====================

# Place the player's robot sprites for view_round (-1 = turn start) and
# rebuild the path overlay for every robot in TurnInput.plans.
func update_plan_display(selected_robot_id: String, view_round: int) -> void:
	_plan_paths.clear()

	for robot_id in TurnInput.plans.keys():
		var robot = GameState.robot_lookup.get(robot_id, {})
		if robot.is_empty():
			continue

		if robot_id in _robot_sprites:
			var shown_hex = TurnInput.get_projected_hex(robot_id, view_round - 1)
			_robot_sprites[robot_id].position = HexMath.axial_to_pixel(shown_hex, HEX_SIZE)
			_robot_sprites[robot_id].axial_pos = shown_hex

		var color = RobotSprite.TEAM_COLORS.get(robot.get("team", 0), {}).get(
			robot.get("type", "captain"), Color.WHITE)
		var is_selected = robot_id == selected_robot_id
		var issues = TurnInput.get_step_issues(robot_id)
		var steps = TurnInput.get_steps(robot_id)

		var hex = TurnInput.get_start_hex(robot_id)
		var points := PackedVector2Array([HexMath.axial_to_pixel(hex, HEX_SIZE)])
		var labels: Dictionary = {}
		var issue_hexes: Array = []
		var deploys: Array = []
		for i in range(steps.size()):
			if TurnInput.has_deploy(robot_id, i):
				deploys.append({
					"hex": TurnInput.get_deploy_target(robot_id, i),
					"label": "D%d" % (i + 1),
				})
			var label: String
			if steps[i].get("type", "wait") == "move":
				hex += HexMath.AXIAL_DIRECTIONS[steps[i]["dir"]]
				points.append(HexMath.axial_to_pixel(hex, HEX_SIZE))
				label = str(i + 1)
			else:
				label = "w%d" % (i + 1)
			if not labels.has(hex):
				labels[hex] = []
			labels[hex].append(label)
			if i in issues:
				issue_hexes.append(hex)
		# Deploys can be planned on implicit-wait rounds past the last step.
		for i in range(steps.size(), TurnInput.ROUNDS_PER_TURN):
			if TurnInput.has_deploy(robot_id, i):
				deploys.append({
					"hex": TurnInput.get_deploy_target(robot_id, i),
					"label": "D%d" % (i + 1),
				})
				if i in issues:
					issue_hexes.append(hex)

		_plan_paths.append({
			"points": points,
			"color": color,
			"selected": is_selected,
			"tip": points[points.size() - 1],
			"labels": labels,
			"issues": issue_hexes,
			"deploys": deploys,
		})

	queue_redraw()

# Dashed preview of the route the selected robot would take to the hovered hex.
func set_hover_route(hexes: Array, valid: bool) -> void:
	_hover_points = PackedVector2Array()
	for h in hexes:
		_hover_points.append(HexMath.axial_to_pixel(h, HEX_SIZE))
	_hover_valid = valid
	queue_redraw()

func clear_hover_route() -> void:
	if _hover_points.is_empty():
		return
	_hover_points = PackedVector2Array()
	queue_redraw()

# ==================== Hex Object Management ====================

func _place_hex_objects() -> void:
	for obj in GameState.hex_objects:
		_add_hex_object_node(obj)

func add_hex_object(obj: Dictionary) -> void:
	_add_hex_object_node(obj)
	queue_redraw()

func remove_hex_object(pos_q: int, pos_r: int, type: String) -> void:
	var key = "%d,%d,%s" % [pos_q, pos_r, type]
	if key in _hex_object_nodes:
		_hex_object_nodes[key].queue_free()
		_hex_object_nodes.erase(key)

func _add_hex_object_node(obj: Dictionary) -> void:
	var pos = obj.get("position", [0, 0])
	var type = obj.get("type", "")
	var key = "%d,%d,%s" % [pos[0], pos[1], type]
	if key in _hex_object_nodes:
		return

	var hex = Vector2i(int(pos[0]), int(pos[1]))
	var pixel = HexMath.axial_to_pixel(hex, HEX_SIZE)

	var label = Label.new()
	label.text = _obj_label(type)
	label.position = pixel + Vector2(-8, -8)
	label.add_theme_color_override("font_color", HEX_OBJECT_COLORS.get(type, Color.WHITE))
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)
	_hex_object_nodes[key] = label

func _obj_label(type: String) -> String:
	match type:
		"emp": return "⚡"
		"firewall": return "🔥"
		"supply_drop": return "📦"
		"obstacle": return "🪨"
	return "?"

# ==================== Highlights ====================

# Deploy targeting highlights (purple).
func highlight_hexes(hexes: Array, color: Color) -> void:
	_highlight_hexes.clear()
	for h in hexes:
		_highlight_hexes[h] = color
	queue_redraw()

func clear_highlights() -> void:
	_highlight_hexes.clear()
	queue_redraw()

# Adjacent move highlights (green) — valid destinations for the selected robot.
func highlight_adjacent_hexes(hexes: Array) -> void:
	_adjacent_highlight_hexes.clear()
	for h in hexes:
		_adjacent_highlight_hexes[h] = Color(0.3, 0.9, 0.3, 0.45)
	queue_redraw()

func clear_adjacent_highlights() -> void:
	_adjacent_highlight_hexes.clear()
	queue_redraw()

# Clear planned path overlay (called when entering replay).
func clear_path_highlights() -> void:
	_plan_paths.clear()
	_hover_points = PackedVector2Array()
	queue_redraw()

# ==================== Fog of War ====================

func apply_fog_of_war(visible_hexes: Array) -> void:
	_visible_hexes.clear()
	for h in visible_hexes:
		_visible_hexes[h] = true
	queue_redraw()

func _is_visible(hex: Vector2i) -> bool:
	return _visible_hexes.is_empty() or hex in _visible_hexes

# ==================== Drawing ====================

func _draw() -> void:
	for coord in _hex_coords.keys():
		_draw_hex(coord)

	for obj in GameState.hex_objects:
		var pos = obj.get("position", [0, 0])
		var hex = Vector2i(int(pos[0]), int(pos[1]))
		var pixel = HexMath.axial_to_pixel(hex, HEX_SIZE)
		var color = HEX_OBJECT_COLORS.get(obj.get("type", ""), Color.MAGENTA)
		color.a = 0.35
		draw_circle(pixel, HEX_SIZE * 0.4, color)

	_draw_plan_paths()

# Planned paths: unselected robots faded, selected robot on top.
func _draw_plan_paths() -> void:
	var font = ThemeDB.fallback_font
	var ordered: Array = []
	for path in _plan_paths:
		if not path["selected"]:
			ordered.append(path)
	for path in _plan_paths:
		if path["selected"]:
			ordered.append(path)

	for path in ordered:
		var alpha = 1.0 if path["selected"] else 0.4
		var c: Color = path["color"]
		var line_color = Color(c.r, c.g, c.b, 0.9 * alpha)
		var points: PackedVector2Array = path["points"]
		if points.size() > 1:
			draw_polyline(points, line_color, 4.0 if path["selected"] else 2.5, true)
			# End-of-path ghost
			draw_arc(path["tip"], RobotSprite.SHAPE_SIZE, 0, TAU, 24, line_color, 2.0)

		for hex in path["issues"]:
			var center = HexMath.axial_to_pixel(hex, HEX_SIZE)
			draw_polyline(_close_polygon(_hex_corners(center)), Color(1, 0.15, 0.15, alpha), 3.0)

		for hex in path["labels"].keys():
			var center = HexMath.axial_to_pixel(hex, HEX_SIZE)
			var text = " ".join(path["labels"][hex])
			var pos = center + Vector2(-HEX_SIZE * 0.6, HEX_SIZE * 0.72)
			draw_rect(Rect2(pos + Vector2(-2, -13), Vector2(HEX_SIZE * 1.2, 17)), Color(0, 0, 0, 0.55 * alpha))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, HEX_SIZE * 1.2, 13,
				Color(1, 1, 1, alpha))

		for deploy in path["deploys"]:
			var center = HexMath.axial_to_pixel(deploy["hex"], HEX_SIZE)
			draw_circle(center, HEX_SIZE * 0.3, Color(0.8, 0.4, 1.0, 0.6 * alpha))
			draw_string(font, center + Vector2(-HEX_SIZE * 0.5, 5), deploy["label"],
				HORIZONTAL_ALIGNMENT_CENTER, HEX_SIZE, 13, Color(1, 1, 1, alpha))

	# Hover preview, dashed
	if _hover_points.size() > 1:
		var hc = Color(0.4, 1.0, 0.4, 0.9) if _hover_valid else Color(1.0, 0.3, 0.3, 0.9)
		for i in range(_hover_points.size() - 1):
			draw_dashed_line(_hover_points[i], _hover_points[i + 1], hc, 2.5, 8.0)
		draw_circle(_hover_points[_hover_points.size() - 1], 6.0, hc)

func _draw_hex(coord: Vector2i) -> void:
	var center = HexMath.axial_to_pixel(coord, HEX_SIZE)
	var terrain = _hex_terrain.get(coord, "default")
	var color = TERRAIN_COLORS.get(terrain, TERRAIN_COLORS["default"])

	var is_hex_visible = _is_visible(coord)
	if not is_hex_visible:
		color = color.darkened(0.55)
		color.a = 0.6

	var points = _hex_corners(center)
	draw_colored_polygon(points, color)

	# Adjacent move highlight (green) — drawn first, lowest priority overlay
	if coord in _adjacent_highlight_hexes:
		draw_colored_polygon(points, _adjacent_highlight_hexes[coord])

	# Deploy targeting highlight — highest priority, drawn on top
	if coord in _highlight_hexes:
		var hcolor = _highlight_hexes[coord]
		hcolor.a = 0.45
		draw_colored_polygon(points, hcolor)

	var border_color = Color(0, 0, 0, 0.25) if is_hex_visible else Color(0, 0, 0, 0.1)
	draw_polyline(_close_polygon(points), border_color, 1.0)

func _hex_corners(center: Vector2) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):
		var angle_deg = 60.0 * i
		var angle_rad = deg_to_rad(angle_deg)
		points.append(center + Vector2(cos(angle_rad), sin(angle_rad)) * HEX_SIZE)
	return points

func _close_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var closed = PackedVector2Array(points)
	if closed.size() > 0:
		closed.append(closed[0])
	return closed

# ==================== Input ====================

# Unhandled so clicks on UI panels never reach the map.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var hex = HexMath.pixel_to_axial(get_local_mouse_position(), HEX_SIZE)
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Only process the first click of a potential double-click to avoid
			# duplicate actions.
			if event.pressed and not event.double_click and hex in _hex_coords:
				_last_hover_hex = hex
				hex_clicked.emit(hex)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_press_pos = event.position
			elif event.position.distance_to(_right_press_pos) < 6.0 and hex in _hex_coords:
				hex_right_clicked.emit(hex, event.position)
	elif event is InputEventMouseMotion:
		var hex = HexMath.pixel_to_axial(get_local_mouse_position(), HEX_SIZE)
		if hex == _last_hover_hex or not hex in _hex_coords:
			return
		_last_hover_hex = hex
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			hex_drag_entered.emit(hex)
		else:
			hex_hovered.emit(hex)

# ==================== Cleanup ====================

func _clear_all() -> void:
	_hex_coords.clear()
	_hex_terrain.clear()
	_visible_hexes.clear()
	_highlight_hexes.clear()
	_adjacent_highlight_hexes.clear()
	_plan_paths.clear()
	_hover_points = PackedVector2Array()

	for sprite in _robot_sprites.values():
		sprite.queue_free()
	_robot_sprites.clear()

	for node in _hex_object_nodes.values():
		node.queue_free()
	_hex_object_nodes.clear()

# ==================== Replay Animation ====================

func animate_replay_round(round_replays: Array, hex_objects_created: Array,
		hex_objects_destroyed: Array) -> void:
	for robot_replay in round_replays:
		var robot_id = robot_replay.get("robot_id", "")
		var anim_type = robot_replay.get("animation_type", "Waiting")
		var before_pos = robot_replay.get("before_position", [0, 0])
		var after_pos = robot_replay.get("after_position", [0, 0])

		var sprite = get_robot_sprite(robot_id)
		if sprite == null:
			continue

		var from_hex = Vector2i(int(before_pos[0]), int(before_pos[1]))
		var to_hex = Vector2i(int(after_pos[0]), int(after_pos[1]))
		var from_pixel = HexMath.axial_to_pixel(from_hex, HEX_SIZE)
		var to_pixel = HexMath.axial_to_pixel(to_hex, HEX_SIZE)

		match anim_type:
			"Move", "PowerMove":
				sprite.animate_move(from_pixel, to_pixel, 0.4)
			"Bump":
				var dir_pixel = to_pixel - from_pixel
				sprite.animate_bump(dir_pixel.normalized(), 0.2)
			"Stunned":
				sprite.show_stunned_flash()
			"Waiting", "Puzzled":
				pass

	for obj in hex_objects_created:
		add_hex_object(obj)
	for obj in hex_objects_destroyed:
		var pos = obj.get("position", [0, 0])
		remove_hex_object(int(pos[0]), int(pos[1]), obj.get("type", ""))

	queue_redraw()
