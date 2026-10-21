extends Control

# ==================== Node References ====================

@onready var player_name_input: LineEdit = $CenterContainer/VBox/PlayerNameInput
@onready var team_size_option: OptionButton = $CenterContainer/VBox/TeamSizeOption
@onready var create_game_btn: Button = $CenterContainer/VBox/CreateGameBtn
@onready var invite_code_input: LineEdit = $CenterContainer/VBox/InviteCodeInput
@onready var join_game_btn: Button = $CenterContainer/VBox/JoinGameBtn
@onready var status_label: Label = $CenterContainer/VBox/StatusLabel
@onready var error_label: Label = $CenterContainer/VBox/ErrorLabel
@onready var team_0_code_label: Label = $CenterContainer/VBox/Team0CodeLabel
@onready var team_0_code_display: Label = $CenterContainer/VBox/Team0CodeDisplay
@onready var team_0_copy_row: HBoxContainer = $CenterContainer/VBox/Team0CopyRow
@onready var copy_team_0_code_btn: Button = $CenterContainer/VBox/Team0CopyRow/CopyTeam0CodeBtn
@onready var copy_team_0_link_btn: Button = $CenterContainer/VBox/Team0CopyRow/CopyTeam0LinkBtn
@onready var team_1_code_label: Label = $CenterContainer/VBox/Team1CodeLabel
@onready var team_1_code_display: Label = $CenterContainer/VBox/Team1CodeDisplay
@onready var team_1_copy_row: HBoxContainer = $CenterContainer/VBox/Team1CopyRow
@onready var copy_team_1_code_btn: Button = $CenterContainer/VBox/Team1CopyRow/CopyTeam1CodeBtn
@onready var copy_team_1_link_btn: Button = $CenterContainer/VBox/Team1CopyRow/CopyTeam1LinkBtn
@onready var player_guide_btn: Button = $CenterContainer/VBox/PlayerGuideBtn
@onready var poll_timer: Timer = $PollTimer

# Share links from non-web builds point at the hosted web client
const WEB_CLIENT_URL: String = "https://zonal-recreation-robotbattle.up.railway.app/"

# ==================== State ====================

var _is_waiting: bool = false
# Web build: JS calls this back once the browser confirms a copy
var _copy_done_cb: JavaScriptObject = null
var _copy_done_msg: String = ""

# ==================== Ready ====================

func _ready() -> void:
	# Populate team size dropdown
	team_size_option.clear()
	team_size_option.add_item("1v1 (1 per team)", 1)
	team_size_option.add_item("2v2 (2 per team)", 2)
	team_size_option.add_item("3v3 (3 per team)", 3)
	team_size_option.select(team_size_option.get_item_index(2))

	# Pre-fill from saved state if available
	if GameState.player_name != "":
		player_name_input.text = GameState.player_name

	# Connect buttons
	create_game_btn.pressed.connect(_on_create_pressed)
	join_game_btn.pressed.connect(_on_join_pressed)
	copy_team_0_code_btn.pressed.connect(_copy_invite.bind(0, false))
	copy_team_0_link_btn.pressed.connect(_copy_invite.bind(0, true))
	copy_team_1_code_btn.pressed.connect(_copy_invite.bind(1, false))
	copy_team_1_link_btn.pressed.connect(_copy_invite.bind(1, true))
	player_guide_btn.pressed.connect(_on_player_guide_pressed)
	poll_timer.timeout.connect(_on_poll_timer)

	# Connect API signals
	APIClient.game_created.connect(_on_game_created)
	APIClient.game_joined.connect(_on_game_joined)
	APIClient.game_status_received.connect(_on_status_received)
	APIClient.request_failed.connect(_on_request_failed)

	# Web build: a link like https://host/?code=golden-dragon prefills the code
	var url_code = _invite_code_from_url()
	if url_code != "":
		invite_code_input.text = url_code
		player_name_input.grab_focus()
		_show_status("Enter your name and press Join to enter the game.")

# ==================== Button Handlers ====================

func _on_create_pressed() -> void:
	var pname = player_name_input.text.strip_edges()
	if pname == "":
		_show_error("Please enter your name.")
		return

	GameState.player_name = pname
	var team_size = team_size_option.get_item_id(team_size_option.selected)
	_set_waiting(true, "Creating game...")
	APIClient.create_game(pname, team_size)

func _on_join_pressed() -> void:
	var pname = player_name_input.text.strip_edges()
	var code = invite_code_input.text.strip_edges()
	if pname == "":
		_show_error("Please enter your name.")
		return
	if code == "":
		_show_error("Please enter an invite code.")
		return

	GameState.player_name = pname
	_set_waiting(true, "Joining game...")
	APIClient.join_game_by_code(code, pname)

func _copy_invite(team: int, as_link: bool) -> void:
	var code = (team_0_code_display if team == 0 else team_1_code_display).text
	if code == "":
		return
	var text = _share_link(code) if as_link else code
	var who = "your teammates" if team == 0 else "your opponents"
	_copy_to_clipboard(text, "Team %d %s copied! Send it to %s." % [team, "link" if as_link else "code", who])

func _on_player_guide_pressed() -> void:
	if OS.has_feature("web"):
		# Same tab, so the guide's "Return to Main Menu" lands back here; carry any invite code along
		var code = invite_code_input.text.strip_edges()
		var query = "?code=" + code.uri_encode() if code != "" else ""
		JavaScriptBridge.eval("window.location.href = 'player_guide.html%s'" % query, true)
	else:
		OS.shell_open(ProjectSettings.globalize_path("res://player_guide.html"))

# ==================== API Response Handlers ====================

func _on_game_created(data: Dictionary) -> void:
	GameState.initialize_from_create_response(data)

	# Show both invite codes
	var team_0_code = data.get("team_0_invite_code", "")
	var team_1_code = data.get("team_1_invite_code", "")

	team_0_code_display.text = team_0_code
	team_1_code_display.text = team_1_code

	# In 1v1 the creator already fills Team 0, so only the opponent code is useful
	var solo = team_size_option.get_item_id(team_size_option.selected) == 1
	team_0_code_label.visible = not solo
	team_0_code_display.visible = not solo
	team_0_copy_row.visible = not solo
	team_1_code_label.visible = true
	team_1_code_display.visible = true
	team_1_copy_row.visible = true

	if solo:
		_show_status("Game created! Share this code with your opponent:")
	else:
		_show_status("Game created! Share codes with players:")
	_set_waiting(true, "Waiting for players to join...")
	poll_timer.start()

func _on_game_joined(data: Dictionary) -> void:
	GameState.initialize_from_join_response(data)
	var state = data.get("state", "")
	_show_status("Joined game as Team %d" % GameState.player_team)

	if state == "in_progress":
		_transition_forward()
	else:
		_set_waiting(true, "Waiting for players to join...")
		poll_timer.start()

func _on_status_received(data: Dictionary) -> void:
	var state = data.get("state", "")

	match state:
		"waiting_for_players":
			_show_status("Waiting for players to join...")
		"in_progress", "processing_turn":
			_transition_forward()
		"complete":
			_show_error("Game already complete.")
		_:
			_show_status("Game state: " + state)

func _on_request_failed(_endpoint: String, status_code: int, body: String) -> void:
	_set_waiting(false, "")
	poll_timer.stop()
	_show_error("Error (%d): %s" % [status_code, body])

# ==================== Polling ====================

func _on_poll_timer() -> void:
	if GameState.game_id != "":
		APIClient.get_status(GameState.game_id)

# ==================== Scene Transitions ====================

func _transition_forward() -> void:
	poll_timer.stop()
	# Check if we need role assignment or can go straight to game view
	# We go to role_assignment scene; it will redirect if robots already spawned
	get_tree().change_scene_to_file("res://scenes/role_assignment.tscn")

# ==================== Share Links (web build) ====================

func _invite_code_from_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var code = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get('code') || ''", true)
	return str(code).strip_edges() if code != null else ""

func _share_link(code: String) -> String:
	var base = WEB_CLIENT_URL
	if OS.has_feature("web"):
		base = str(JavaScriptBridge.eval(
			"window.location.origin + window.location.pathname", true))
	return base + "?code=" + code.uri_encode()

# ==================== Clipboard ====================

# Godot's web clipboard_set runs after the click event has finished, which
# browsers (Safari especially) silently reject. On the web, try the browser
# clipboard directly; if it refuses, show an HTML popup whose own Copy button
# is a real click, with the text pre-selected for Cmd/Ctrl+C as a last resort.
const COPY_HELPER_JS := """
window.robotBattleCopy = function (text, done) {
	function popup() {
		var old = document.getElementById('rb-copy');
		if (old) old.remove();
		var box = document.createElement('div');
		box.id = 'rb-copy';
		box.style.cssText = 'position:fixed;inset:0;z-index:1000;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,0.6);font:16px system-ui,sans-serif';
		box.innerHTML = '<div style="background:#1d1d2b;color:#e4e4ec;padding:20px;border-radius:10px;width:min(92vw,520px);box-sizing:border-box">'
			+ '<div style="margin-bottom:8px">Your browser blocked automatic copying. Press Copy:</div>'
			+ '<input readonly style="width:100%;box-sizing:border-box;padding:8px;font:inherit;background:#14141f;color:#fff;border:1px solid #444;border-radius:6px">'
			+ '<div id="rb-copy-hint" style="margin-top:6px;color:#a3a3b5;font-size:14px"></div>'
			+ '<div style="margin-top:12px;display:flex;gap:8px;justify-content:flex-end">'
			+ '<button data-a="copy" style="padding:8px 16px;font:inherit;font-weight:700;background:#e6b31a;border:0;border-radius:6px;cursor:pointer">Copy</button>'
			+ '<button data-a="close" style="padding:8px 16px;font:inherit;background:#34344a;color:#fff;border:0;border-radius:6px;cursor:pointer">Close</button>'
			+ '</div></div>';
		document.body.appendChild(box);
		var input = box.querySelector('input');
		input.value = text;
		input.focus();
		input.select();
		box.addEventListener('click', function (e) {
			var action = e.target.getAttribute('data-a');
			if (action === 'copy') {
				input.select();
				var ok = false;
				try { ok = document.execCommand('copy'); } catch (err) {}
				if (ok) { box.remove(); done(true); return; }
				navigator.clipboard.writeText(text).then(function () { box.remove(); done(true); }, function () {
					input.select();
					box.querySelector('#rb-copy-hint').textContent = 'Still blocked. The text is selected: press Cmd+C (Mac) or Ctrl+C.';
				});
			} else if (action === 'close' || e.target === box) {
				box.remove();
			}
		});
	}
	if (navigator.clipboard && window.isSecureContext) {
		navigator.clipboard.writeText(text).then(function () { done(true); }, popup);
	} else {
		popup();
	}
};
"""

func _copy_to_clipboard(text: String, done_msg: String) -> void:
	if not OS.has_feature("web"):
		DisplayServer.clipboard_set(text)
		_show_status(done_msg)
		return
	if _copy_done_cb == null:
		JavaScriptBridge.eval(COPY_HELPER_JS, true)
		_copy_done_cb = JavaScriptBridge.create_callback(_on_web_copy_done)
	_copy_done_msg = done_msg
	JavaScriptBridge.get_interface("window").robotBattleCopy(text, _copy_done_cb)

func _on_web_copy_done(_args: Array) -> void:
	_show_status(_copy_done_msg)

# ==================== UI Helpers ====================

func _set_waiting(waiting: bool, msg: String) -> void:
	_is_waiting = waiting
	create_game_btn.disabled = waiting
	join_game_btn.disabled = waiting
	if msg != "":
		_show_status(msg)

func _show_status(msg: String) -> void:
	status_label.text = msg
	error_label.text = ""

func _show_error(msg: String) -> void:
	error_label.text = msg
	status_label.text = ""
	_set_waiting(false, "")
