extends Node2D
class_name HexMap

# Renders the hex grid, hex objects, and robots.
# Handles mouse click input and emits hex_clicked signal.
# Manages fog of war by dimming/hiding hexes and enemies.

signal hex_clicked(hex: Vector2i)

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
# path_highlight_hexes: Dictionary  Vector2i -> Color  (current-round move destinations)
var _path_highlight_hexes: Dictionary = {}
# adjacent_highlight_hexes: Dictionary  Vector2i -> Color  (valid moves for selected robot)
var _adjacent_highlight_hexes: Dictionary = {}
# move_arrows: Array of {from: Vector2, to: Vector2, color: Color} for current round
var _move_arrows: Array = []

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

# ==================== Projected Positions ====================

# Move robot sprites to their projected positions at the start of current_round,
# and draw move arrows for any planned move in current_round.
func update_projected_positions(action_plan: Dictionary, current_round: int,
		robot_lookup: Dictionary) -> void:
	_path_highlight_hexes.clear()
	_move_arrows.clear()

	for robot_id in action_plan.keys():
		var robot = robot_lookup.get(robot_id, {})
		if robot.is_empty():
			continue

		# Compute projected position entering this round (after rounds 0..current_round-1)
		var start_pos = robot.get("position", [0, 0])
		var proj_pos = start_pos.duplicate()
		var rounds = action_plan.get(robot_id, [])
		for i in range(current_round):
			if i < rounds.size() and rounds[i].get("action_type", "wait") == "move":
				proj_pos = rounds[i].get("after_position", proj_pos)

		var proj_hex = Vector2i(int(proj_pos[0]), int(proj_pos[1]))

		# Reposition sprite
		if robot_id in _robot_sprites:
			_robot_sprites[robot_id].position = HexMath.axial_to_pixel(proj_hex, HEX_SIZE)
			_robot_sprites[robot_id].axial_pos = proj_hex

		# Build move arrow if this robot has a move in current_round
		if current_round < rounds.size() and rounds[current_round].get("action_type", "wait") == "move":
			var dest_arr = rounds[current_round].get("after_position", proj_pos)
			var dest_hex = Vector2i(int(dest_arr[0]), int(dest_arr[1]))
			var from_px = HexMath.axial_to_pixel(proj_hex, HEX_SIZE)
			var to_px = HexMath.axial_to_pixel(dest_hex, HEX_SIZE)
			var team = robot.get("team", 0)
			var rtype = robot.get("type", "captain")
			var color = RobotSprite.TEAM_COLORS.get(team, {}).get(rtype, Color.WHITE)
			_move_arrows.append({"from": from_px, "to": to_px, "color": Color(color.r, color.g, color.b, 0.9)})
			_path_highlight_hexes[dest_hex] = Color(color.r, color.g, color.b, 0.35)

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

# Clear planned-move path highlights and arrows (called when entering replay).
func clear_path_highlights() -> void:
	_path_highlight_hexes.clear()
	_move_arrows.clear()
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

	# Draw move arrows on top of hex fills, under robot sprites
	for arrow in _move_arrows:
		var f: Vector2 = arrow["from"]
		var t: Vector2 = arrow["to"]
		var c: Color = arrow["color"]
		draw_line(f, t, c, 3.0)
		# Arrowhead
		var dir = (t - f).normalized()
		var perp = Vector2(-dir.y, dir.x)
		var tip = t - dir * 10.0
		draw_line(tip, tip + (-dir + perp) * 9.0, c, 2.5)
		draw_line(tip, tip + (-dir - perp) * 9.0, c, 2.5)

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

	# Planned move destination (robot color tint) for current round
	if coord in _path_highlight_hexes:
		draw_colored_polygon(points, _path_highlight_hexes[coord])

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

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Only process the first click of a potential double-click to avoid
		# duplicate actions (select then immediately clear).
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not event.double_click:
			var local_pos = get_local_mouse_position()
			var hex = HexMath.pixel_to_axial(local_pos, HEX_SIZE)
			if hex in _hex_coords:
				hex_clicked.emit(hex)

# ==================== Cleanup ====================

func _clear_all() -> void:
	_hex_coords.clear()
	_hex_terrain.clear()
	_visible_hexes.clear()
	_highlight_hexes.clear()
	_path_highlight_hexes.clear()
	_adjacent_highlight_hexes.clear()
	_move_arrows.clear()

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
