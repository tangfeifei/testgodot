class_name WindField
extends Node

@export var direction_change_min: float = 5.0
@export var direction_change_max: float = 11.0
@export var breeze_strength: float = 0.045
@export var gust_strength: float = 0.11
@export var smoothing_rate: float = 0.24

var _random := RandomNumberGenerator.new()
var _materials: Array[ShaderMaterial] = []
var _direction := Vector2(1.0, 0.0)
var _target_direction := Vector2(1.0, 0.0)
var _direction_timer: float = 0.0
var _gust_phase: float = 0.0
var _gust_target: float = 0.0
var _gust: float = 0.0


func _ready() -> void:
	_random.seed = 603_119
	_choose_next_direction()


func register_material(material: ShaderMaterial) -> void:
	if material != null and not _materials.has(material):
		_materials.append(material)
		_apply_wind(material)


func _process(delta: float) -> void:
	_direction_timer -= delta
	if _direction_timer <= 0.0:
		_choose_next_direction()
	_direction = _direction.slerp(_target_direction, 1.0 - exp(-smoothing_rate * delta)).normalized()
	_gust_phase += delta
	var gust_cycle := maxf(0.0, sin(_gust_phase * 0.42 - 1.2))
	_gust = lerpf(_gust, maxf(_gust_target, gust_cycle), 1.0 - exp(-0.8 * delta))
	if gust_cycle < 0.08 and _random.randf() < delta * 0.06:
		_gust_target = _random.randf_range(0.25, 1.0)
	elif gust_cycle > 0.92:
		_gust_target = 0.0
	for material in _materials:
		if is_instance_valid(material):
			_apply_wind(material)


func _choose_next_direction() -> void:
	var angle := _random.randf_range(-PI, PI)
	_target_direction = Vector2(cos(angle), sin(angle))
	_direction_timer = _random.randf_range(direction_change_min, direction_change_max)
	_gust_target = _random.randf_range(0.0, 0.75)


func _apply_wind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("wind_direction", _direction)
	material.set_shader_parameter("wind_strength", breeze_strength + _gust * gust_strength)
	material.set_shader_parameter("gust_factor", 0.65 + _gust * 0.75)
	material.set_shader_parameter("wind_speed", 0.8 + _gust * 0.5)