class_name ExplorationHUD
extends CanvasLayer

var _relic_label: Label
var _message_label: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(340, 104)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.075, 0.065, 0.82)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "WILDLANDS  |  古林遗迹"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.76, 0.91, 0.72))
	layout.add_child(title)
	_relic_label = Label.new()
	_relic_label.text = "收集灵晶：0 / 0"
	_relic_label.add_theme_font_size_override("font_size", 16)
	layout.add_child(_relic_label)
	_message_label = Label.new()
	_message_label.text = "WASD 移动/攀爬  ·  Shift 奔跑  ·  Space 跳跃  ·  E 抓树  ·  鼠标观察"
	_message_label.position = Vector2(22, 132)
	_message_label.add_theme_font_size_override("font_size", 15)
	_message_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	add_child(_message_label)


func set_relic_count(collected: int, total: int) -> void:
	if is_instance_valid(_relic_label):
		_relic_label.text = "收集灵晶：%d / %d" % [collected, total]
		if collected == total and total > 0:
			_message_label.text = "所有灵晶都已找到。古林记住了你的名字。"
