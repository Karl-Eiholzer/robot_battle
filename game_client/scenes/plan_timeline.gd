extends PanelContainer
class_name PlanTimeline

# Bottom dock showing every robot's plan as a robots x rounds grid.
# Click a row name to select a robot, click a cell to aim the next map click
# at that round, drag one cell onto another in the same row to swap their
# timing, right-click a cell for the step menu. Column headers scrub the
# board to that round. All edits go through TurnInput.
# The dock sizes itself to its contents and sits at the bottom-left corner,
# so it covers as little of the map as possible; it can be collapsed (T).

# Right-click on a cell; game_view owns the context menu.
signal cell_context_requested(robot_id: String, round_num: int, screen_pos: Vector2)

# Compass names for HexMath.AXIAL_DIRECTIONS on the flat-top layout.
const DIR_NAMES: Array = ["SE", "NE", "N", "NW", "SW", "S"]

const CELL_SIZE := Vector2(48, 26)
const COLOR_ISSUE := Color(0.75, 0.15, 0.15)
const COLOR_MOVE := Color(0.22, 0.32, 0.45)
const COLOR_WAIT := Color(0.2, 0.2, 0.22)
const COLOR_EMPTY := Color(0.14, 0.14, 0.16)
const COLOR_CURSOR := Color(1.0, 0.85, 0.2)
const COLOR_VIEW_COL := Color(0.35, 0.35, 0.15)

var _grid: GridContainer
var _hint_label: Label
var _toggle_btn: Button
var _rebuild_queued: bool = false
var collapsed: bool = false

# ==================== Cell ====================

# One round of one robot. Supports drag-and-drop within its own row.
class TimelineCell extends Button:
	var robot_id: String
	var round_num: int
	var timeline: PlanTimeline

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if TurnInput.current_phase != TurnInput.Phase.INPUT:
			return null
		var preview = Label.new()
		preview.text = "R%d %s" % [round_num + 1, text]
		set_drag_preview(preview)
		return {"timeline_cell": true, "robot_id": robot_id, "round_num": round_num}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("timeline_cell", false) \
			and data.get("robot_id", "") == robot_id

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		TurnInput.swap_steps(robot_id, data["round_num"], round_num)
		TurnInput.select_robot(robot_id)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			timeline.cell_context_requested.emit(robot_id, round_num, event.global_position)
			accept_event()

# ==================== Build ====================

func _ready() -> void:
	var vbox = VBoxContainer.new()
	add_child(vbox)

	var title_row = HBoxContainer.new()
	vbox.add_child(title_row)

	_toggle_btn = _make_button("")
	_toggle_btn.custom_minimum_size = Vector2(0, 22)
	_toggle_btn.tooltip_text = "Hide or show the plan grid (T)"
	_toggle_btn.pressed.connect(toggle_collapsed)
	title_row.add_child(_toggle_btn)

	_hint_label = Label.new()
	_hint_label.text = "click a cell to aim at a round · drag cells to retime · right-click for options"
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	title_row.add_child(_hint_label)

	_grid = GridContainer.new()
	_grid.columns = 1 + TurnInput.ROUNDS_PER_TURN + 2
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	vbox.add_child(_grid)

	TurnInput.action_plan_changed.connect(queue_rebuild)
	TurnInput.robot_selected.connect(func(_id): queue_rebuild())
	TurnInput.view_round_changed.connect(func(_r): queue_rebuild())
	TurnInput.phase_changed.connect(func(_p): queue_rebuild())
	GameState.robots_updated.connect(queue_rebuild)
	get_viewport().size_changed.connect(fit_to_content)
	_apply_collapsed()
	_rebuild()

func toggle_collapsed() -> void:
	collapsed = not collapsed
	_apply_collapsed()

func _apply_collapsed() -> void:
	_grid.visible = not collapsed
	_hint_label.visible = not collapsed
	_toggle_btn.text = "Show plan" if collapsed else "Hide plan"
	fit_to_content.call_deferred()

# Shrink to the grid's natural size, pinned to the bottom-left corner.
func fit_to_content() -> void:
	size = get_combined_minimum_size()
	position = Vector2(0, get_viewport_rect().size.y - size.y)

# Rebuilds are deferred so a cell is never freed inside its own press handler,
# and several plan changes in one frame cost one rebuild.
func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_queued = false
	if _grid == null:
		return
	fit_to_content.call_deferred()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	var editable = TurnInput.current_phase == TurnInput.Phase.INPUT

	# Header row
	_grid.add_child(_make_label(""))
	for r in range(TurnInput.ROUNDS_PER_TURN):
		var col_btn = _make_button("R%d" % (r + 1))
		col_btn.toggle_mode = true
		col_btn.button_pressed = TurnInput.view_round == r
		col_btn.tooltip_text = "Show the board at the start of round %d (click again for full paths)" % (r + 1)
		col_btn.disabled = not editable
		col_btn.pressed.connect(_on_column_pressed.bind(r))
		_grid.add_child(col_btn)
	_grid.add_child(_make_label("Moves"))
	_grid.add_child(_make_label("Energy"))

	var type_counts: Dictionary = {}
	for robot_id in TurnInput.get_my_robot_ids():
		var robot = GameState.robot_lookup.get(robot_id, {})
		var rtype = robot.get("type", "robot")
		type_counts[rtype] = type_counts.get(rtype, 0) + 1
		_add_robot_row(robot_id, robot, "%s %d" % [rtype.capitalize(), type_counts[rtype]], editable)

func _add_robot_row(robot_id: String, robot: Dictionary, row_name: String, editable: bool) -> void:
	var is_selected = robot_id == TurnInput.selected_robot_id
	var issues = TurnInput.get_step_issues(robot_id)
	var steps = TurnInput.get_steps(robot_id)
	var cursor = TurnInput.get_cursor(robot_id)

	var stunned = robot.get("state", "active") == "stunned"
	var name_btn = _make_button(row_name + (" (stunned)" if stunned else ""))
	name_btn.toggle_mode = true
	name_btn.button_pressed = is_selected
	name_btn.custom_minimum_size = Vector2(110, CELL_SIZE.y)
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.disabled = not editable
	name_btn.pressed.connect(_on_robot_pressed.bind(robot_id))
	_grid.add_child(name_btn)

	for r in range(TurnInput.ROUNDS_PER_TURN):
		var cell = TimelineCell.new()
		cell.robot_id = robot_id
		cell.round_num = r
		cell.timeline = self
		cell.focus_mode = Control.FOCUS_NONE
		cell.custom_minimum_size = CELL_SIZE
		cell.add_theme_font_size_override("font_size", 12)
		cell.disabled = not editable

		var bg: Color
		var text: String
		if r < steps.size() and steps[r].get("type", "wait") == "move":
			text = DIR_NAMES[steps[r]["dir"]]
			bg = COLOR_MOVE
		elif r < steps.size():
			text = "wait"
			bg = COLOR_WAIT
		else:
			text = "·"
			bg = COLOR_EMPTY
		if TurnInput.has_deploy(robot_id, r):
			text += " +D"
		if TurnInput.view_round == r and not r in issues:
			bg = bg.lerp(COLOR_VIEW_COL, 0.5)
		if r in issues:
			bg = COLOR_ISSUE
			cell.tooltip_text = issues[r]
		else:
			cell.tooltip_text = "Round %d" % (r + 1)
		cell.text = text

		var show_cursor = is_selected and r == cursor
		_style_cell(cell, bg, show_cursor, is_selected)
		cell.pressed.connect(_on_cell_pressed.bind(robot_id, r))
		_grid.add_child(cell)

	var moves_label = _make_label("%d/%d" % [
		TurnInput.count_moves_planned(robot_id), TurnInput.get_max_moves(robot_id)])
	_grid.add_child(moves_label)
	var max_energy = TurnInput.ROBOT_STATS.get(robot.get("type", ""), {}).get("max_energy", 0)
	var energy_label = _make_label("%d/%d" % [int(robot.get("energy", 0)), max_energy])
	_grid.add_child(energy_label)

func _style_cell(cell: Button, bg: Color, show_cursor: bool, row_selected: bool) -> void:
	var normal = _compact_style(bg if row_selected else bg.darkened(0.25))
	if show_cursor:
		normal.border_color = COLOR_CURSOR
		normal.set_border_width_all(2)
	var hover = normal.duplicate()
	hover.bg_color = normal.bg_color.lightened(0.15)
	cell.add_theme_stylebox_override("normal", normal)
	cell.add_theme_stylebox_override("hover", hover)
	cell.add_theme_stylebox_override("pressed", hover)
	cell.add_theme_stylebox_override("hover_pressed", hover)
	cell.add_theme_stylebox_override("disabled", normal)

# Flat box with small padding; the default theme's padding makes rows ~45% taller.
func _compact_style(bg: Color) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(3)
	box.set_content_margin_all(2)
	box.content_margin_left = 6
	box.content_margin_right = 6
	return box

func _make_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = CELL_SIZE
	btn.add_theme_font_size_override("font_size", 12)
	var normal = _compact_style(Color(0.25, 0.25, 0.28))
	var hover = _compact_style(Color(0.33, 0.33, 0.37))
	var pressed = _compact_style(Color(0.35, 0.42, 0.6))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("disabled", normal)
	return btn

func _make_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(44, CELL_SIZE.y)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	return label

# ==================== Handlers ====================

func _on_robot_pressed(robot_id: String) -> void:
	if TurnInput.selected_robot_id == robot_id:
		TurnInput.select_robot("")
	else:
		TurnInput.select_robot(robot_id)

func _on_cell_pressed(robot_id: String, round_num: int) -> void:
	if TurnInput.selected_robot_id != robot_id:
		TurnInput.select_robot(robot_id)
	TurnInput.set_cursor(robot_id, round_num)
	TurnInput.set_view_round(round_num)

func _on_column_pressed(round_num: int) -> void:
	TurnInput.set_view_round(-1 if TurnInput.view_round == round_num else round_num)
