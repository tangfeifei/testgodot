extends Node3D

# 预载遗物场景；生成遗物时实例化这个资源，不必在运行时再查找文件。
const RelicScene: PackedScene = preload("res://scenes/relic.tscn")
const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage_wind.gdshader")
const MIRROR_SHADER: Shader = preload("res://shaders/planar_mirror.gdshader")
const WATER_SHADER: Shader = preload("res://shaders/pond_water.gdshader")
const TERRAIN_CACHE_PATH: String = "user://generated_terrain.scn"
const TERRAIN_CACHE_VERSION: int = 1

# 地形块边长；地表按需生成，因此地图可向任意方向延伸。
const TERRAIN_CHUNK_SIZE: float = 128.0
# 保持玩家周围 9×9 个地形块可见，超出范围后卸载旧块。
const STREAM_CHUNK_RADIUS: int = 4
# 碰撞仅保留在玩家周围，远处地形只负责视觉呈现。
const COLLISION_CHUNK_RADIUS: int = 2
# 远景地形覆盖玩家周围 16 个地块半径，显示低模山脉天际线。
const HORIZON_CHUNK_RADIUS: int = 32
const HORIZON_CELLS_PER_CHUNK: int = 2

# 场景中遗物的总数，用于 HUD 显示收集进度。
var _relic_count: int = 0
# 已收集遗物数量，每次拾取后递增。
var _collected_relics: int = 0
var _wind_field: WindField
var _world_camera: Camera3D
var _tree_material_cache: Dictionary = {}
var _terrain_material: StandardMaterial3D
var _terrain_chunks: Dictionary = {}
var _terrain_root: Node3D
var _distant_terrain: MeshInstance3D
var _last_stream_center: Vector2i = Vector2i(2147483647, 2147483647)

# 直接取得场景中的 HUD 节点，供初始化和遗物拾取回调使用。
@onready var hud: ExplorationHUD = $HUD


# 场景进入运行状态时建立整个游戏世界，并初始化 HUD 的遗物计数。
func _ready() -> void:
	# 先建立环境和地形，确保后续物件可以依照地形高度放置。
	_create_environment()
	_create_terrain()
	_world_camera = $Player/CameraPivot/SpringArm3D/Camera3D
	# 将玩家放到出生点地面上方两米，避免刚开始时陷入地形。
	$Player.position.y = terrain_height($Player.position.x, $Player.position.z) + 2.0
	_wind_field = WindField.new()
	_wind_field.name = "WindField"
	add_child(_wind_field)
	_load_terrain_cache()
	# 建立核心地标、镜面、水塘和可收集的遗物；远离中心的地表由分块系统生成。
	_create_landmark()
	_create_mirrors()
	_create_ponds()
	_create_relics()
	# 所有遗物建立完成后，把初始收集进度显示到 HUD。
	hud.set_relic_count(_collected_relics, _relic_count)
	var player := $Player as Node3D
	_update_terrain_stream(Vector2i(
		floori(player.position.x / TERRAIN_CHUNK_SIZE),
		floori(player.position.z / TERRAIN_CHUNK_SIZE)
	))


func _exit_tree() -> void:
	_save_terrain_cache()


func _process(_delta: float) -> void:
	var player := get_node_or_null("Player") as Node3D
	if player == null:
		return
	var current_chunk := Vector2i(
		floori(player.global_position.x / TERRAIN_CHUNK_SIZE),
		floori(player.global_position.z / TERRAIN_CHUNK_SIZE)
	)
	if current_chunk != _last_stream_center:
		_update_terrain_stream(current_chunk)


# 根据世界坐标计算程序化地形的高度。
# 多组不同频率和振幅的正弦、余弦波叠加，形成起伏而非平面的地面。
func terrain_height(x: float, z: float) -> float:
	var base_height := (
		# X 方向的长波起伏。
		sin(x * 0.045) * 1.7
		# Z 方向的起伏，与 X 方向波形错开。
		+ cos(z * 0.038) * 1.2
		# 沿 X+Z 斜向叠加一组较缓的山丘。
		+ sin((x + z) * 0.025) * 2.0
		# 沿 X-Z 方向再叠加一组波形，减少规则条纹感。
		+ cos((x - z) * 0.018) * 1.1
	)
	var first_pond_distance := Vector2((x - 28.0) / 8.7, (z + 16.0) / 6.2).length()
	var second_pond_distance := Vector2((x + 43.0) / 6.8, (z - 39.0) / 5.0).length()
	var first_basin := 1.8 * (1.0 - smoothstep(0.78, 1.35, first_pond_distance))
	var second_basin := 1.8 * (1.0 - smoothstep(0.78, 1.35, second_pond_distance))
	return base_height - maxf(first_basin, second_basin) + _mountain_height(x, z)


func _mountain_height(x: float, z: float) -> float:
	var mountain := 0.0
	var grid_x := floori(x / 1700.0)
	var grid_z := floori(z / 1700.0)
	for offset_z in range(-1, 2):
		for offset_x in range(-1, 2):
			var cell_x := grid_x + offset_x
			var cell_z := grid_z + offset_z
			var cell_hash := sin(float(cell_x) * 127.1 + float(cell_z) * 311.7) * 43758.5453
			var cell_hash_b := sin(float(cell_x) * 269.5 + float(cell_z) * 183.3) * 24634.6345
			var summit_x := float(cell_x) * 1700.0 + fposmod(cell_hash, 1.0) * 620.0 - 310.0
			var summit_z := float(cell_z) * 1700.0 + fposmod(cell_hash_b, 1.0) * 620.0 - 310.0
			if Vector2(summit_x, summit_z).length() < 1150.0:
				continue
			var distance := Vector2((x - summit_x) / 760.0, (z - summit_z) / 640.0).length()
			if distance < 1.35:
				var peak_height := 190.0 + fposmod(absf(cell_hash_b), 1.0) * 110.0
				var massif := peak_height * pow(1.0 - distance / 1.35, 1.55)
				var ridge := maxf(0.0, sin((x + summit_x) * 0.012) * cos((z - summit_z) * 0.015)) * 18.0
				mountain = maxf(mountain, massif + ridge)
	return mountain


# 创建天空和环境光；这部分只负责场景照明与背景，不创建实体碰撞。
func _create_environment() -> void:
	# 建立环境资源，并指定背景使用天空而不是纯色。
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	# 使用程序化天空材质，通过颜色渐变模拟天空和地平线。
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.15, 0.34, 0.54)
	sky_material.sky_horizon_color = Color(0.68, 0.78, 0.79)
	sky_material.ground_bottom_color = Color(0.12, 0.19, 0.15)
	sky_material.ground_horizon_color = Color(0.52, 0.63, 0.51)
	sky.sky_material = sky_material
	environment.sky = sky
	# 为没有被直射光照到的区域添加柔和的环境补光。
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.72, 0.75)
	environment.ambient_light_energy = 0.65
	# 把环境设置挂入场景树，使渲染器能够应用天空和环境光。
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


# 使用网格三角形生成起伏地面，并为相同网格创建静态碰撞体。
func _create_terrain() -> void:
	_terrain_root = Node3D.new()
	_terrain_root.name = "TerrainChunks"
	add_child(_terrain_root)
	_terrain_material = StandardMaterial3D.new()
	_terrain_material.albedo_color = Color(0.22, 0.38, 0.20)
	_terrain_material.roughness = 1.0
	_terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_distant_terrain = MeshInstance3D.new()
	_distant_terrain.name = "DistantMountainTerrain"
	_distant_terrain.material_override = _terrain_material
	_distant_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_distant_terrain)


func _load_terrain_cache() -> void:
	if not FileAccess.file_exists(TERRAIN_CACHE_PATH):
		return
	var packed_scene := ResourceLoader.load(TERRAIN_CACHE_PATH) as PackedScene
	if packed_scene == null:
		push_warning("Terrain cache could not be loaded; generating terrain instead.")
		return
	var cached_root := packed_scene.instantiate() as Node3D
	if cached_root == null or int(cached_root.get_meta("cache_version", -1)) != TERRAIN_CACHE_VERSION:
		if cached_root != null:
			cached_root.free()
		return
	var saved_player_position: Variant = cached_root.get_meta("player_position", null)
	if saved_player_position is Vector3:
		($Player as Node3D).position = saved_player_position
	remove_child(_terrain_root)
	_terrain_root.queue_free()
	_terrain_root = cached_root
	add_child(_terrain_root)
	for chunk_node in _terrain_root.get_children():
		var chunk_root := chunk_node as Node3D
		if chunk_root == null or not chunk_root.has_meta("chunk_x") or not chunk_root.has_meta("chunk_z"):
			continue
		var chunk_key := Vector2i(int(chunk_root.get_meta("chunk_x")), int(chunk_root.get_meta("chunk_z")))
		_terrain_chunks[chunk_key] = {
			"node": chunk_root,
			"subdivisions": int(chunk_root.get_meta("subdivisions", 8)),
			"with_collision": bool(chunk_root.get_meta("with_collision", false)),
		}
		var terrain_surface := chunk_root.get_node_or_null("TerrainSurface") as MeshInstance3D
		if terrain_surface != null and terrain_surface.material_override is StandardMaterial3D:
			_terrain_material = terrain_surface.material_override as StandardMaterial3D
			_distant_terrain.material_override = _terrain_material
	_register_cached_wind_materials(_terrain_root)


func _register_cached_wind_materials(node: Node) -> void:
	if node is GeometryInstance3D:
		var material := (node as GeometryInstance3D).material_override as ShaderMaterial
		if material != null:
			_wind_field.register_material(material)
	for child in node.get_children():
		_register_cached_wind_materials(child)


func _save_terrain_cache() -> void:
	if not is_instance_valid(_terrain_root) or _terrain_root.get_child_count() == 0:
		return
	for chunk_node in _terrain_root.get_children():
		if chunk_node.is_queued_for_deletion():
			_terrain_root.remove_child(chunk_node)
	_terrain_root.set_meta("cache_version", TERRAIN_CACHE_VERSION)
	var player := get_node_or_null("Player") as Node3D
	if player != null:
		_terrain_root.set_meta("player_position", player.position)
	_set_scene_owner_recursive(_terrain_root, _terrain_root)
	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(_terrain_root)
	if pack_error != OK:
		push_warning("Terrain cache could not be packed: %s" % error_string(pack_error))
		return
	var save_error := ResourceSaver.save(packed_scene, TERRAIN_CACHE_PATH)
	if save_error != OK:
		push_warning("Terrain cache could not be saved: %s" % error_string(save_error))


func _set_scene_owner_recursive(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_scene_owner_recursive(child, scene_root)


func _update_terrain_stream(center: Vector2i) -> void:
	_last_stream_center = center
	for chunk_key in _terrain_chunks.keys():
		var offset := Vector2i(chunk_key) - center
		if absi(offset.x) > STREAM_CHUNK_RADIUS or absi(offset.y) > STREAM_CHUNK_RADIUS:
			(_terrain_chunks[chunk_key]["node"] as Node3D).queue_free()
			_terrain_chunks.erase(chunk_key)

	for z_offset in range(-STREAM_CHUNK_RADIUS, STREAM_CHUNK_RADIUS + 1):
		for x_offset in range(-STREAM_CHUNK_RADIUS, STREAM_CHUNK_RADIUS + 1):
			var chunk_key := center + Vector2i(x_offset, z_offset)
			var lod_ring := maxi(absi(x_offset), absi(z_offset))
			var subdivisions := 32 if lod_ring <= 1 else (16 if lod_ring <= 2 else 8)
			if _terrain_chunks.has(chunk_key):
				if _terrain_chunks[chunk_key]["subdivisions"] == subdivisions and _terrain_chunks[chunk_key]["with_collision"] == (lod_ring <= COLLISION_CHUNK_RADIUS):
					continue
				(_terrain_chunks[chunk_key]["node"] as Node3D).queue_free()
				_terrain_chunks.erase(chunk_key)
			_create_terrain_chunk(chunk_key, subdivisions, lod_ring <= COLLISION_CHUNK_RADIUS)

	_update_distant_terrain(center)


func _create_terrain_chunk(chunk_key: Vector2i, subdivisions: int, with_collision: bool) -> void:
	var chunk_root := Node3D.new()
	chunk_root.name = "TerrainChunk_%d_%d" % [chunk_key.x, chunk_key.y]
	chunk_root.set_meta("chunk_x", chunk_key.x)
	chunk_root.set_meta("chunk_z", chunk_key.y)
	chunk_root.set_meta("subdivisions", subdivisions)
	chunk_root.set_meta("with_collision", with_collision)
	chunk_root.position = Vector3(float(chunk_key.x) * TERRAIN_CHUNK_SIZE, 0.0, float(chunk_key.y) * TERRAIN_CHUNK_SIZE)
	var terrain_mesh := _build_terrain_mesh(chunk_key, 1, subdivisions)
	var terrain_instance := MeshInstance3D.new()
	terrain_instance.name = "TerrainSurface"
	terrain_instance.mesh = terrain_mesh
	terrain_instance.material_override = _terrain_material
	chunk_root.add_child(terrain_instance)
	if with_collision:
		var terrain_body := StaticBody3D.new()
		terrain_body.name = "TerrainCollision"
		terrain_body.collision_layer = 1
		var collision := CollisionShape3D.new()
		var terrain_shape := terrain_mesh.create_trimesh_shape()
		terrain_shape.backface_collision = true
		collision.shape = terrain_shape
		terrain_body.add_child(collision)
		chunk_root.add_child(terrain_body)
	_terrain_root.add_child(chunk_root)
	_create_forest(chunk_key, chunk_root, with_collision)
	_terrain_chunks[chunk_key] = {
		"node": chunk_root,
		"subdivisions": subdivisions,
		"with_collision": with_collision,
	}


func _update_distant_terrain(center: Vector2i) -> void:
	var start_chunk := center - Vector2i(HORIZON_CHUNK_RADIUS, HORIZON_CHUNK_RADIUS)
	var chunks_per_side := HORIZON_CHUNK_RADIUS * 2 + 1
	_distant_terrain.mesh = _build_terrain_mesh(
		start_chunk,
		chunks_per_side,
		HORIZON_CELLS_PER_CHUNK,
		true,
		center
	)
	_distant_terrain.position = Vector3(
		float(start_chunk.x) * TERRAIN_CHUNK_SIZE,
		0.0,
		float(start_chunk.y) * TERRAIN_CHUNK_SIZE
	)


func _build_terrain_mesh(start_chunk: Vector2i, chunks_per_side: int, cells_per_chunk: int, omit_streamed_area: bool = false, center_chunk: Vector2i = Vector2i.ZERO) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell_size := TERRAIN_CHUNK_SIZE / float(cells_per_chunk)
	for chunk_z in range(chunks_per_side):
		for chunk_x in range(chunks_per_side):
			var chunk_key := start_chunk + Vector2i(chunk_x, chunk_z)
			if omit_streamed_area:
				var offset := chunk_key - center_chunk
				if absi(offset.x) <= STREAM_CHUNK_RADIUS and absi(offset.y) <= STREAM_CHUNK_RADIUS:
					continue
			var chunk_local_x := float(chunk_x) * TERRAIN_CHUNK_SIZE
			var chunk_local_z := float(chunk_z) * TERRAIN_CHUNK_SIZE
			for z_index in range(cells_per_chunk):
				for x_index in range(cells_per_chunk):
					var x0 := chunk_local_x + float(x_index) * cell_size
					var z0 := chunk_local_z + float(z_index) * cell_size
					var x1 := x0 + cell_size
					var z1 := z0 + cell_size
					var world_x0 := float(start_chunk.x) * TERRAIN_CHUNK_SIZE + x0
					var world_z0 := float(start_chunk.y) * TERRAIN_CHUNK_SIZE + z0
					var world_x1 := world_x0 + cell_size
					var world_z1 := world_z0 + cell_size
					surface.add_vertex(Vector3(x0, terrain_height(world_x0, world_z0), z0))
					surface.add_vertex(Vector3(x0, terrain_height(world_x0, world_z1), z1))
					surface.add_vertex(Vector3(x1, terrain_height(world_x1, world_z0), z0))
					surface.add_vertex(Vector3(x1, terrain_height(world_x1, world_z0), z0))
					surface.add_vertex(Vector3(x0, terrain_height(world_x0, world_z1), z1))
					surface.add_vertex(Vector3(x1, terrain_height(world_x1, world_z1), z1))
	surface.generate_normals()
	return surface.commit()


# 每个地形块使用固定种子生成植被，卸载与重载后布局保持一致。
func _create_forest(chunk_key: Vector2i, parent: Node3D, with_collision: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 824_613 + chunk_key.x * 73_856_093 + chunk_key.y * 19_349_663
	var chunk_origin := Vector3(float(chunk_key.x) * TERRAIN_CHUNK_SIZE, 0.0, float(chunk_key.y) * TERRAIN_CHUNK_SIZE)
	for index in range(24):
		var tree_x := rng.randf_range(8.0, TERRAIN_CHUNK_SIZE - 8.0)
		var tree_z := rng.randf_range(8.0, TERRAIN_CHUNK_SIZE - 8.0)
		var world_x := chunk_origin.x + tree_x
		var world_z := chunk_origin.z + tree_z
		if _near_landmark(world_x, world_z) or _near_pond(world_x, world_z):
			continue
		_add_tree(parent, Vector3(tree_x, terrain_height(world_x, world_z), tree_z), rng.randf_range(0.8, 1.35), rng, with_collision)
	for index in range(3):
		var rock_x := rng.randf_range(5.0, TERRAIN_CHUNK_SIZE - 5.0)
		var rock_z := rng.randf_range(5.0, TERRAIN_CHUNK_SIZE - 5.0)
		var world_x := chunk_origin.x + rock_x
		var world_z := chunk_origin.z + rock_z
		if _near_pond(world_x, world_z):
			continue
		var rock := MeshInstance3D.new()
		rock.mesh = SphereMesh.new()
		rock.scale = Vector3(rng.randf_range(0.6, 1.8), rng.randf_range(0.35, 0.9), rng.randf_range(0.6, 1.4))
		rock.position = Vector3(rock_x, terrain_height(world_x, world_z) + 0.25, rock_z)
		var stone_material := StandardMaterial3D.new()
		stone_material.albedo_color = Color(0.34, 0.37, 0.35)
		stone_material.roughness = 1.0
		rock.material_override = stone_material
		parent.add_child(rock)
		if with_collision:
			var rock_body := StaticBody3D.new()
			rock_body.name = "RockCollision"
			rock_body.position = rock.position
			var rock_collision := CollisionShape3D.new()
			var rock_shape := rock.mesh.create_convex_shape()
			var rock_points := rock_shape.points
			for point_index in range(rock_points.size()):
				rock_points[point_index] *= rock.scale
			rock_shape.points = rock_points
			rock_collision.shape = rock_shape
			rock_body.add_child(rock_collision)
			parent.add_child(rock_body)
	_create_vegetation(rng, chunk_origin, parent)


# 创建一棵树：树干有圆柱碰撞，树干和树冠网格负责视觉显示。
func _add_tree(parent: Node3D, origin: Vector3, size: float, rng: RandomNumberGenerator, with_collision: bool) -> void:
	# 树木有独立视觉根节点，方便把网格局部坐标统一相对于树根计算。
	var tree_visual := Node3D.new()
	tree_visual.name = "TreeVisual"
	tree_visual.position = origin
	parent.add_child(tree_visual)
	# 树干静态碰撞阻挡角色；树枝碰撞会在不同高度形成可跳跃攀爬的平台。
	if with_collision:
		var tree_body := StaticBody3D.new()
		tree_body.name = "TreeCollision"
		tree_body.position = tree_visual.position
		tree_body.set_meta("climb_height", 5.1 * size)
		var trunk_collision := CollisionShape3D.new()
		var trunk_shape := CylinderShape3D.new()
		trunk_shape.radius = 0.3 * size
		trunk_shape.height = 5.1 * size
		trunk_collision.shape = trunk_shape
		trunk_collision.position.y = 2.55 * size
		tree_body.add_child(trunk_collision)
		parent.add_child(tree_body)
		_add_tree_branch(tree_visual, parent, size, 2.2 * size, 0.0, 1.8 * size)
		_add_tree_branch(tree_visual, parent, size, 3.35 * size, PI * 0.5, 1.9 * size)
		_add_tree_branch(tree_visual, parent, size, 4.5 * size, PI, 2.0 * size)

	# 创建树干外观；尺寸与上方圆柱碰撞大致一致。
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18 * size
	trunk_mesh.bottom_radius = 0.3 * size
	trunk_mesh.height = 2.5 * size
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.25 * size
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.28, 0.17, 0.10)
	bark.roughness = 1.0
	trunk.material_override = bark
	tree_visual.add_child(trunk)

	# 用不同剪影和颜色的交叉看板代替单一球形树冠，远看更像树叶层次。
	var species := rng.randi_range(0, 2)
	var foliage_material := _tree_foliage_material(species)
	for card_index in range(3):
		var crown_card := MeshInstance3D.new()
		crown_card.name = "CrownCard%d" % card_index
		var card_mesh := QuadMesh.new()
		card_mesh.size = Vector2(2.9 * size, 3.5 * size)
		crown_card.mesh = card_mesh
		crown_card.material_override = foliage_material
		crown_card.position.y = 4.0 * size
		crown_card.rotation.y = float(card_index) * PI / 3.0
		tree_visual.add_child(crown_card)


func _add_tree_branch(visual: Node3D, parent: Node3D, size: float, height: float, angle: float, length: float) -> void:
	# 用树枝外观盒和略厚的盒形碰撞共同构成可踩踏的平台。
	var offset := Vector3(cos(angle), 0.0, -sin(angle)) * length * 0.5
	var branch_mesh := BoxMesh.new()
	branch_mesh.size = Vector3(length, 0.16 * size, 0.2 * size)
	var branch_visual := MeshInstance3D.new()
	branch_visual.name = "ClimbableBranch"
	branch_visual.mesh = branch_mesh
	branch_visual.position = offset + Vector3(0.0, height, 0.0)
	branch_visual.rotation.y = angle
	var branch_bark := StandardMaterial3D.new()
	branch_bark.albedo_color = Color(0.34, 0.21, 0.12)
	branch_bark.roughness = 1.0
	branch_visual.material_override = branch_bark
	visual.add_child(branch_visual)
	var branch_body := StaticBody3D.new()
	branch_body.name = "ClimbableBranchCollision"
	branch_body.position = visual.position
	branch_body.collision_layer = 2
	var branch_collision := CollisionShape3D.new()
	var branch_shape := BoxShape3D.new()
	branch_shape.size = Vector3(length, 0.22 * size, 0.26 * size)
	branch_collision.shape = branch_shape
	branch_collision.position = offset + Vector3(0.0, height, 0.0)
	branch_collision.rotation.y = angle
	branch_body.add_child(branch_collision)
	parent.add_child(branch_body)


func _tree_foliage_material(species: int) -> ShaderMaterial:
	if _tree_material_cache.has(species):
		return _tree_material_cache[species]
	var material := ShaderMaterial.new()
	material.shader = FOLIAGE_SHADER
	material.set_shader_parameter("billboard", false)
	material.set_shader_parameter("foliage_style", species)
	var tint := Color(0.21, 0.43, 0.23)
	if species == 1:
		tint = Color(0.16, 0.34, 0.27)
	elif species == 2:
		tint = Color(0.39, 0.48, 0.20)
	material.set_shader_parameter("foliage_tint", tint)
	_tree_material_cache[species] = material
	if is_instance_valid(_wind_field):
		_wind_field.register_material(material)
	return material


func _create_vegetation(rng: RandomNumberGenerator, chunk_origin: Vector3, parent: Node3D) -> void:
	for patch_index in range(3):
		var meadow_center := Vector3(rng.randf_range(16.0, 112.0), 0.0, rng.randf_range(16.0, 112.0))
		_spawn_foliage_patch(rng, parent, chunk_origin, meadow_center, 35.0, 950, Color(0.31, 0.66, 0.27), 3)
		if patch_index < 2:
			var flower_center := Vector3(rng.randf_range(16.0, 112.0), 0.0, rng.randf_range(16.0, 112.0))
			_spawn_foliage_patch(rng, parent, chunk_origin, flower_center, 24.0, 120, Color(0.90, 0.72, 0.38), 4, 0.58)


func _spawn_foliage_patch(rng: RandomNumberGenerator, parent: Node3D, chunk_origin: Vector3, center: Vector3, radius: float, count: int, tint: Color, style: int, scale_factor: float = 1.0) -> void:
	# MultiMesh 将一片同材质草叶/花朵合并绘制，大幅降低大量植被的绘制开销。
	var foliage_mesh := QuadMesh.new()
	foliage_mesh.size = Vector2(0.22, 0.75)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = foliage_mesh
	multimesh.instance_count = count
	for instance_index in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * radius
		var x := center.x + cos(angle) * distance
		var z := center.z + sin(angle) * distance
		var world_x := chunk_origin.x + x
		var world_z := chunk_origin.z + z
		if _near_landmark(world_x, world_z) or _near_pond(world_x, world_z):
			multimesh.set_instance_transform(instance_index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0)))
			continue
		var height := rng.randf_range(0.42, 0.92) * scale_factor
		var width := rng.randf_range(0.72, 1.35) * scale_factor
		var yaw := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(width, height, 1.0))
		var position := Vector3(x, terrain_height(world_x, world_z), z)
		multimesh.set_instance_transform(instance_index, Transform3D(basis, position))
		multimesh.set_instance_color(instance_index, tint * Color(rng.randf_range(0.82, 1.16), rng.randf_range(0.82, 1.16), rng.randf_range(0.82, 1.16)))
		multimesh.set_instance_custom_data(instance_index, Color(rng.randf(), 0.0, 0.0, 1.0))
	var foliage_material := ShaderMaterial.new()
	foliage_material.shader = FOLIAGE_SHADER
	foliage_material.set_shader_parameter("billboard", true)
	foliage_material.set_shader_parameter("foliage_style", style)
	foliage_material.set_shader_parameter("foliage_tint", Color.WHITE)
	if is_instance_valid(_wind_field):
		_wind_field.register_material(foliage_material)
	var foliage_instance := MultiMeshInstance3D.new()
	foliage_instance.multimesh = multimesh
	foliage_instance.material_override = foliage_material
	foliage_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(foliage_instance)


func _near_pond(x: float, z: float) -> bool:
	return Vector2(x - 28.0, z + 16.0).length() < 7.5 or Vector2(x + 43.0, z - 39.0).length() < 6.0


# 建立古迹的底座、立柱和顶盖，并为三部分分别创建盒形碰撞体。
func _create_landmark() -> void:
	# 以地标所在位置的地表高度作为局部坐标原点。
	var landmark_origin := Vector3(0, terrain_height(0, -45), -45)
	# 底座的显示网格，中心位于地面上方 0.4 米。
	var base := _make_box(Vector3(4.0, 0.8, 4.0), Color(0.40, 0.39, 0.32))
	base.position = landmark_origin + Vector3(0, 0.4, 0)
	add_child(base)
	# 立柱的显示网格，中心高度为 5.2 米。
	var pillar := _make_box(Vector3(1.4, 9.0, 1.4), Color(0.55, 0.52, 0.41))
	pillar.position = landmark_origin + Vector3(0, 5.2, 0)
	add_child(pillar)
	# 顶盖的显示网格，位于立柱上方。
	var cap := _make_box(Vector3(2.4, 0.8, 2.4), Color(0.59, 0.54, 0.39))
	cap.position = landmark_origin + Vector3(0, 9.8, 0)
	add_child(cap)
	# 三个盒形碰撞分别贴合底座、立柱和顶盖，阻挡玩家进入地标内部。
	var landmark_body := StaticBody3D.new()
	landmark_body.name = "LandmarkCollision"
	landmark_body.position = landmark_origin
	_add_box_collision(landmark_body, Vector3(4.0, 0.8, 4.0), Vector3(0, 0.4, 0))
	_add_box_collision(landmark_body, Vector3(1.4, 9.0, 1.4), Vector3(0, 5.2, 0))
	_add_box_collision(landmark_body, Vector3(2.4, 0.8, 2.4), Vector3(0, 9.8, 0))
	add_child(landmark_body)
	# 信标只提供光照效果，不参与物理碰撞。
	var beacon := OmniLight3D.new()
	beacon.position = Vector3(0, terrain_height(0, -45) + 11.0, -45)
	beacon.light_color = Color(0.45, 0.82, 1.0)
	beacon.light_energy = 2.0
	beacon.omni_range = 18.0
	add_child(beacon)


func _create_mirrors() -> void:
	_add_mirror(Vector3(-7.5, terrain_height(-7.5, -43.0) + 2.2, -43.0), 0.0)
	_add_mirror(Vector3(8.0, terrain_height(8.0, -42.0) + 2.2, -42.0), PI)
	_add_mirror(Vector3(34.0, terrain_height(34.0, 12.0) + 2.0, 12.0), -PI * 0.5)


func _add_mirror(position: Vector3, yaw: float) -> void:
	# 竖直平面镜使用独立反射视口，材质根据相机镜像矩阵采样对应方向。
	var mirror_root := Node3D.new()
	mirror_root.name = "PlanarMirror"
	mirror_root.position = position
	mirror_root.rotation = Vector3(PI * 0.5, yaw, 0.0)
	add_child(mirror_root)
	var mirror_mesh := MeshInstance3D.new()
	mirror_mesh.name = "MirrorSurface"
	mirror_mesh.layers = 2
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 3.8)
	mirror_mesh.mesh = plane
	var mirror_material := ShaderMaterial.new()
	mirror_material.shader = MIRROR_SHADER
	mirror_mesh.material_override = mirror_material
	mirror_root.add_child(mirror_mesh)
	var reflector := PlanarReflector.new()
	reflector.name = "ReflectionController"
	mirror_root.add_child(reflector)
	reflector.setup(_world_camera, mirror_mesh, Vector2i(320, 512), Vector3.UP)
	_add_mirror_frame(mirror_root, Vector2(2.4, 3.8))
	var body := StaticBody3D.new()
	body.name = "MirrorCollision"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 0.18, 4.0)
	collision.shape = shape
	body.add_child(collision)
	mirror_root.add_child(body)


func _add_mirror_frame(parent: Node3D, size: Vector2) -> void:
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.19, 0.25, 0.22)
	frame_material.metallic = 0.78
	frame_material.roughness = 0.22
	for edge in range(4):
		var frame_bar := MeshInstance3D.new()
		var frame_mesh := BoxMesh.new()
		if edge < 2:
			frame_mesh.size = Vector3(0.12, 0.14, size.y + 0.2)
			frame_bar.position.x = -size.x * 0.5 if edge == 0 else size.x * 0.5
		else:
			frame_mesh.size = Vector3(size.x + 0.2, 0.14, 0.12)
			frame_bar.position.z = -size.y * 0.5 if edge == 2 else size.y * 0.5
		frame_bar.mesh = frame_mesh
		frame_bar.material_override = frame_material
		parent.add_child(frame_bar)


func _create_ponds() -> void:
	_add_pond(Vector3(28.0, terrain_height(28.0, -16.0) + 0.16, -16.0), Vector2(7.6, 5.2), Color(0.19, 0.49, 0.50))
	_add_pond(Vector3(-43.0, terrain_height(-43.0, 39.0) + 0.14, 39.0), Vector2(5.8, 4.2), Color(0.23, 0.47, 0.51))


func _add_pond(center: Vector3, extent: Vector2, tint: Color) -> void:
	# 椭圆 PlaneMesh 由着色器裁成池塘轮廓；波纹由多组不同频率的正弦环叠加。
	var water_surface := MeshInstance3D.new()
	water_surface.name = "ReflectivePond"
	water_surface.layers = 2
	var water_mesh := PlaneMesh.new()
	water_mesh.size = extent * 2.0
	water_surface.mesh = water_mesh
	water_surface.position = Vector3.ZERO
	var water_material := ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	water_material.set_shader_parameter("pond_center", center)
	water_material.set_shader_parameter("pond_extent", extent)
	water_material.set_shader_parameter("water_tint", tint)
	water_material.set_shader_parameter("wave_scale", 1.0 + extent.x / 10.0)
	water_material.set_shader_parameter("transparency", 0.84)
	water_surface.material_override = water_material
	var pond_root := Node3D.new()
	pond_root.name = "PondReflection"
	pond_root.position = center
	add_child(pond_root)
	water_surface.position = Vector3.ZERO
	pond_root.add_child(water_surface)
	var reflector := PlanarReflector.new()
	reflector.name = "WaterReflectionController"
	pond_root.add_child(reflector)
	reflector.setup(_world_camera, water_surface, Vector2i(384, 256), Vector3.UP)
	# 岸边石块提供池塘边界的视觉过渡，避开水面中心。
	var bank_rng := RandomNumberGenerator.new()
	bank_rng.seed = int(absf(center.x * 913.0 + center.z * 617.0))
	for rock_index in range(22):
		var angle := TAU * float(rock_index) / 22.0 + bank_rng.randf_range(-0.1, 0.1)
		var shore_offset := Vector3(cos(angle) * extent.x, 0.0, sin(angle) * extent.y)
		var shore_position := center + shore_offset
		var stone := MeshInstance3D.new()
		stone.name = "PondBankStone"
		stone.mesh = SphereMesh.new()
		stone.scale = Vector3(bank_rng.randf_range(0.25, 0.58), bank_rng.randf_range(0.18, 0.35), bank_rng.randf_range(0.24, 0.48))
		stone.position = Vector3(shore_position.x, terrain_height(shore_position.x, shore_position.z) + 0.12, shore_position.z)
		var stone_material := StandardMaterial3D.new()
		stone_material.albedo_color = Color(0.34, 0.39, 0.34)
		stone_material.roughness = 0.96
		stone.material_override = stone_material
		add_child(stone)
		var stone_body := StaticBody3D.new()
		stone_body.position = stone.position
		var stone_collision := CollisionShape3D.new()
		var bank_points := stone.mesh.create_convex_shape().points
		for point_index in range(bank_points.size()):
			bank_points[point_index] *= stone.scale
		var bank_shape := ConvexPolygonShape3D.new()
		bank_shape.points = bank_points
		stone_collision.shape = bank_shape
		stone_body.add_child(stone_collision)
		add_child(stone_body)


# 在指定静态物体下添加一个盒形碰撞子节点。
# box_size 是盒子的三轴尺寸；local_position 是相对父 StaticBody3D 的偏移。
func _add_box_collision(parent: StaticBody3D, box_size: Vector3, local_position: Vector3) -> void:
	# BoxShape3D 是物理形状资源，CollisionShape3D 将它挂接到物理体。
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	collision.position = local_position
	parent.add_child(collision)


# 创建一个指定尺寸和颜色的盒子网格，返回节点供调用者设置位置或挂入场景。
func _make_box(box_size: Vector3, color: Color) -> MeshInstance3D:
	# 建立网格节点和盒形几何，并将传入尺寸应用到盒子表面。
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh_instance.mesh = box
	# 使用标准材质设置颜色和粗糙度，避免表面呈现过强的镜面反射。
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh_instance.material_override = material
	return mesh_instance


# 在预设坐标生成全部遗物，并连接每个遗物的拾取信号到统一计数回调。
func _create_relics() -> void:
	# 遗物位置用 X、Z 平面坐标描述；Y 高度稍后根据地形计算。
	var positions := [
		Vector2(25, -20),
		Vector2(-35, -42),
		Vector2(48, 35),
		Vector2(-52, 28),
		Vector2(12, 68),
	]
	# 记录总数，并逐个实例化遗物场景。
	_relic_count = positions.size()
	for point in positions:
		var relic: WorldRelic = RelicScene.instantiate()
		relic.position = Vector3(point.x, terrain_height(point.x, point.y) + 1.3, point.y)
		relic.collected.connect(_on_relic_collected)
		add_child(relic)


# 收到遗物的 collected 信号时递增收集数，并刷新 HUD 上的进度文字。
func _on_relic_collected() -> void:
	_collected_relics += 1
	hud.set_relic_count(_collected_relics, _relic_count)


# 判断候选树木是否位于地标周围的保留区域内；是则不在此处生成树。
func _near_landmark(x: float, z: float) -> bool:
	# 地标中心位于 (0, -45)，用二维距离与 9 米半径比较。
	return Vector2(x, z + 45.0).length() < 9.0
