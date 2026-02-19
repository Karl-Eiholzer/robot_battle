extends Control

@onready var winner_label: Label = $CenterContainer/VBox/WinnerLabel
@onready var turn_label: Label = $CenterContainer/VBox/TurnLabel
@onready var return_btn: Button = $CenterContainer/VBox/ReturnBtn

func _ready() -> void:
	# initiative_team was temporarily reused to store winner
	var winner_team = GameState.initiative_team
	var is_my_team_winner = (winner_team == GameState.player_team)

	winner_label.text = "Team %d Wins!" % winner_team
	if is_my_team_winner:
		winner_label.theme_override_colors.font_color = Color(0.2, 1.0, 0.2, 1)
	else:
		winner_label.theme_override_colors.font_color = Color(1.0, 0.2, 0.2, 1)

	turn_label.text = "Completed in %d turn(s)" % GameState.current_turn

	return_btn.pressed.connect(_on_return_pressed)

func _on_return_pressed() -> void:
	GameState.clear_saved_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
