class_name PlanarReflector
extends Node3D

@export var viewport_size: Vector2i = Vector2i(384, 256)

var _source_camera: Camera3D
var _reflection_camera: Camera3D
var _surface_material: ShaderMaterial
var _normal_axis: Vector3 = Vector3.BACK


func setup(source_camera: Camera3D, surface: MeshInstance3D, resolution: Vector2i = Vector2i(384, 256), normal_axis: Vector3 = Vector3.BACK) -> void:
	_source_camera = source_camera
	viewport_size = resolution
	_normal_axis = normal_axis
	_surface_material = surface.material_override as ShaderMaterial
	_create_reflection_viewport()
	if _surface_material != null:
		_surface_material.set_shader_parameter("reflection_texture", _reflection_camera.get_viewport().get_texture())


func _process(_delta: float) -> void:
	if not is_instance_valid(_source_camera) or not is_instance_valid(_reflection_camera):
		return

	var normal := (global_basis * _normal_axis).normalized()
	var camera_offset := _source_camera.global_position - global_position
	var reflected_position := _source_camera.global_position - 2.0 * normal * camera_offset.dot(normal)
	var source_forward := -_source_camera.global_basis.z
	var reflected_forward := source_forward - 2.0 * normal * source_forward.dot(normal)
	var source_up := _source_camera.global_basis.y
	var reflected_up := source_up - 2.0 * normal * source_up.dot(normal)
	_reflection_camera.global_position = reflected_position
	_reflection_camera.look_at(reflected_position + reflected_forward, reflected_up.normalized())
	if _surface_material != null:
		_surface_material.set_shader_parameter("reflection_view", _reflection_camera.get_camera_transform().affine_inverse())
		_surface_material.set_shader_parameter("reflection_projection", _reflection_camera.get_camera_projection())
		_surface_material.set_shader_parameter("camera_world_position", _source_camera.global_position)


func _create_reflection_viewport() -> void:
	var reflection_viewport := SubViewport.new()
	reflection_viewport.name = "ReflectionViewport"
	reflection_viewport.size = viewport_size
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reflection_viewport.world_3d = get_viewport().world_3d
	add_child(reflection_viewport)

	_reflection_camera = Camera3D.new()
	_reflection_camera.name = "ReflectionCamera"
	_reflection_camera.cull_mask = 1
	_reflection_camera.near = 0.05
	_reflection_camera.far = 220.0
	_reflection_camera.fov = _source_camera.fov
	reflection_viewport.add_child(_reflection_camera)
	_reflection_camera.make_current()


func set_surface_material(material: ShaderMaterial) -> void:
	_surface_material = material
	if is_instance_valid(_reflection_camera):
		_surface_material.set_shader_parameter("reflection_texture", _reflection_camera.get_viewport().get_texture())
