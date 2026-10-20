extends Node3D # 继承三维节点，作为所有可见模型部件和动画变换的父节点。

const KNIGHT_SCENE: PackedScene = preload("res://assets/kaykit/Knight.glb")

var _head: Node3D # 缓存头部支点，用于动画时轻微调整头部俯仰。
var _torso: Node3D # 缓存躯干支点，用于制作呼吸和跑步起伏。
var _left_arm: Node3D # 缓存左上臂支点，用于摆臂和跳跃姿势。
var _right_arm: Node3D # 缓存右上臂支点，用于摆臂和跳跃姿势。
var _left_leg: Node3D # 缓存左腿支点，用于行走、奔跑和跳跃动作。
var _right_leg: Node3D # 缓存右腿支点，用于与左腿交替摆动。
var _left_forearm: Node3D # 缓存左前臂支点，跳跃时调整其弯曲角度。
var _right_forearm: Node3D # 缓存右前臂支点，跳跃时调整其弯曲角度。
var _phase: float = 0.0 # 步态循环相位，随时间增长并驱动四肢往复摆动。
var _move_weight: float = 0.0 # 当前移动动作权重，0 为站立，1 为完整移动。
var _run_weight: float = 0.0 # 行走到奔跑之间的平滑混合权重。
var _air_weight: float = 0.0 # 地面动作到跳跃动作之间的平滑混合权重。
var _climb_weight: float = 0.0 # 普通姿势到攀爬姿势之间的平滑混合权重。
var _move_target: float = 0.0 # 移动权重的目标值，由 update_animation 根据玩家输入设置。
var _run_target: float = 0.0 # 奔跑权重目标值，冲刺时为 1，否则为 0。
var _air_target: float = 0.0 # 空中权重目标值，离地时为 1，落地时为 0。
var _climb_target: float = 0.0 # 攀爬权重目标值，攀爬时为 1，否则为 0。
var _vertical_speed: float = 0.0 # 玩家当前垂直速度，用来区分跳起和下落阶段。
var _grounded: bool = true # 保存玩家是否接触地面的状态。
var _animation_player: AnimationPlayer
var _last_animation: StringName = &""


func _ready() -> void:
	set_process(false)
	var knight := KNIGHT_SCENE.instantiate() as Node3D
	knight.name = "KnightModel"
	add_child(knight)
	_animation_player = knight.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		push_warning("Knight model has no AnimationPlayer; check the imported GLB.")
		return
	_play_animation(&"Idle")


func update_animation( # 由 player.gd 每个物理帧调用，更新动画平滑过渡所需的目标状态。
	_delta: float, # 调用方传来的帧时间；当前平滑在 _process 中进行，因此此参数暂未使用。
	move_amount: float, # 当前移动输入强度，通常在 0 到 1 之间。
	sprinting: bool, # 玩家当前是否按住冲刺键。
	grounded: bool, # 玩家当前是否站在地面上。
	vertical_speed: float, # 玩家当前的垂直速度，用于判断上升或下落。
	climbing: bool = false # 玩家当前是否正在树干上攀爬。
) -> void: # 只更新目标状态，不直接瞬间改变角色姿势。
	var animation_name: StringName = &"Idle"
	if climbing:
		animation_name = &"Idle"
	elif not grounded:
		animation_name = &"Jump_Start" if _grounded and vertical_speed > 0.0 else &"Jump_Idle"
	elif not _grounded:
		animation_name = &"Jump_Land"
	elif move_amount > 0.05:
		animation_name = &"Running_A" if sprinting else &"Walking_A"
	var playing_transition := _animation_player.is_playing() and (
		_animation_player.current_animation == &"Jump_Start" and not grounded
		or _animation_player.current_animation == &"Jump_Land" and grounded
	)
	if playing_transition:
		_grounded = grounded
		_vertical_speed = vertical_speed
		return
	_play_animation(animation_name)
	_grounded = grounded
	_vertical_speed = vertical_speed


func _play_animation(animation_name: StringName) -> void:
	if not is_instance_valid(_animation_player) or _last_animation == animation_name:
		return
	if not _animation_player.has_animation(animation_name):
		push_warning("Knight model is missing animation: %s" % animation_name)
		return
	_last_animation = animation_name
	_animation_player.play(animation_name, 0.18)


func _process(delta: float) -> void: # 每个渲染帧平滑状态，并更新身体部件的旋转与位置。
	_move_weight = _smooth_to(_move_weight, _move_target, 10.0, delta) # 平滑启动或停止移动步态。
	_run_weight = _smooth_to(_run_weight, _run_target, 8.0, delta) # 平滑过渡行走和奔跑的动作幅度。
	_air_weight = _smooth_to(_air_weight, _air_target, 7.0, delta) # 平滑过渡地面动作和空中动作。
	_climb_weight = _smooth_to(_climb_weight, _climb_target, 9.0, delta) # 平滑进入或退出攀爬姿势。

	var stride_rate := lerpf(5.8, 9.5, _run_weight) # 按奔跑权重插值计算步态循环频率。
	_phase += delta * stride_rate # 按帧时间推进步态相位，保证动画速度不依赖帧率。
	var stride := sin(_phase) * _move_weight # 用正弦波生成摆动，并乘以移动权重控制淡入淡出。
	var swing := lerpf(0.42, 0.78, _run_weight) # 奔跑权重越高，四肢摆动幅度越大。
	var jump_pose := 0.35 if _vertical_speed > 0.0 else -0.2 # 上升时收腿，下降时使用略微不同的腿部角度。
	var climb_stride := sin(_phase * 2.0) * 0.34 # 用更快的交替节奏模拟攀爬时手脚寻找支点。

	var left_leg_pose := lerpf(stride * swing, jump_pose, _air_weight) # 混合左腿的地面步态和空中姿势。
	var right_leg_pose := lerpf(-stride * swing, jump_pose, _air_weight) # 混合右腿的地面步态和空中姿势。
	_left_leg.rotation.x = lerpf(left_leg_pose, climb_stride, _climb_weight) # 左腿在普通动作与攀爬屈伸之间平滑切换。
	_right_leg.rotation.x = lerpf(right_leg_pose, -climb_stride, _climb_weight) # 右腿与左腿反相屈伸，形成交替踩踏动作。
	var left_arm_pose := lerpf(-stride * swing * 0.8, 1.0, _air_weight) # 混合左臂的摆动和跳跃抬手姿势。
	var right_arm_pose := lerpf(stride * swing * 0.8, 1.0, _air_weight) # 混合右臂的摆动和跳跃抬手姿势。
	_left_arm.rotation.x = lerpf(left_arm_pose, -1.0 + climb_stride, _climb_weight) # 左臂攀爬时交替向上伸手抓枝条。
	_right_arm.rotation.x = lerpf(right_arm_pose, -1.0 - climb_stride, _climb_weight) # 右臂与左臂错相伸展，模拟轮流抓握。
	_left_forearm.rotation.x = lerpf(lerpf(-0.12, -0.45, _air_weight), -0.65, _climb_weight) # 攀爬时弯曲左肘，空中时保持原有屈臂姿势。
	_right_forearm.rotation.x = lerpf(lerpf(-0.12, -0.45, _air_weight), -0.65, _climb_weight) # 攀爬时弯曲右肘，动作与左臂保持协调。

	var idle_bob := sin(_phase * 0.5) * 0.012 * (1.0 - _move_weight) # 站立时加入极轻微起伏，减少完全静止的僵硬感。
	var run_bob := absf(stride) * 0.045 * _move_weight # 按步态强度计算移动时躯干的上下运动。
	_torso.position.y = 1.17 + idle_bob + run_bob - _air_weight * 0.035 + absf(climb_stride) * 0.035 * _climb_weight # 加入攀爬时的躯干起伏。
	_head.rotation.x = lerpf(0.0, -0.08 if _vertical_speed > 0.0 else 0.06, _air_weight) # 起跳和下落时轻微调整头部俯仰。


func _smooth_to(value: float, target: float, rate: float, delta: float) -> float: # 使用指数插值，以平滑方式逼近目标动画权重。
	return lerpf(value, target, 1.0 - exp(-rate * delta)) # rate 越大过渡越快，delta 让平滑速度适应帧时间。


func _build_character() -> void: # 用基础几何体组合角色外观，并保存动画需要控制的关节节点。
	var tunic := _material(Color(0.16, 0.34, 0.29)) # 创建深绿色外衣材质。
	var tunic_light := _material(Color(0.25, 0.47, 0.37)) # 创建浅绿色材质，作为肩部披片颜色。
	var leather := _material(Color(0.28, 0.16, 0.09)) # 创建深棕皮革材质，用于背包、腰带和护臂。
	var leather_light := _material(Color(0.48, 0.29, 0.14)) # 创建浅棕皮革材质，用于装饰和边缘。
	var skin := _material(Color(0.78, 0.56, 0.38)) # 创建肤色材质，用于脸和手。
	var hair := _material(Color(0.13, 0.09, 0.07)) # 创建深色头发材质。
	var metal := _material(Color(0.63, 0.68, 0.58)) # 创建灰绿色金属材质，用于腰带扣。
	var eye := _material(Color(0.08, 0.07, 0.06)) # 创建深色眼睛材质。
	var cloth := _material(Color(0.76, 0.68, 0.47)) # 创建浅色布料材质，用于围巾。

	_torso = _pivot("Torso", Vector3(0.0, 1.17, 0.0), self) # 创建躯干支点并将其放置在角色身体中心。
	_capsule(_torso, "Tunic", 0.25, 0.7, tunic, Vector3.ZERO) # 用胶囊网格制作躯干主体和外衣。
	_sphere(_torso, "ShoulderMantle", Vector3(0.0, 0.22, 0.0), Vector3(0.34, 0.12, 0.25), tunic_light) # 在肩部添加浅绿色披片。
	_box(_torso, "Backpack", Vector3(0.39, 0.42, 0.18), leather, Vector3(0.0, 0.02, 0.29)) # 在躯干后方放置棕色背包。
	_box(_torso, "PackFlap", Vector3(0.29, 0.14, 0.035), leather_light, Vector3(0.0, 0.14, 0.19)) # 给背包添加浅色翻盖。
	_cylinder(_torso, "Belt", 0.27, 0.09, leather, Vector3(0.0, -0.28, 0.0)) # 在躯干下部添加圆柱形腰带。
	_box(_torso, "Buckle", Vector3(0.09, 0.07, 0.035), metal, Vector3(0.0, -0.28, -0.26)) # 在腰带前侧添加金属扣。
	_box(_torso, "Scarf", Vector3(0.31, 0.09, 0.28), cloth, Vector3(0.0, 0.32, 0.0)) # 在颈部添加浅色围巾。

	_head = _pivot("Head", Vector3(0.0, 1.64, 0.0), self) # 创建可单独旋转的头部支点，并设置头部高度。
	_sphere(_head, "Face", Vector3(0.0, 0.0, 0.0), Vector3(0.19, 0.23, 0.18), skin) # 创建椭圆形脸部。
	_sphere(_head, "HairCap", Vector3(0.0, 0.14, 0.015), Vector3(0.205, 0.12, 0.19), hair) # 在头顶覆盖一层深色头发。
	_sphere(_head, "LeftEye", Vector3(-0.07, 0.025, -0.165), Vector3(0.025, 0.028, 0.018), eye) # 在脸部左侧放置眼睛。
	_sphere(_head, "RightEye", Vector3(0.07, 0.025, -0.165), Vector3(0.025, 0.028, 0.018), eye) # 在脸部右侧放置眼睛。
	_sphere(_head, "Nose", Vector3(0.0, -0.025, -0.185), Vector3(0.035, 0.045, 0.035), skin) # 在双眼下方添加鼻部几何体。

	_left_arm = _pivot("LeftArm", Vector3(-0.34, 1.38, 0.0), self) # 在身体左侧建立肩部旋转支点。
	_right_arm = _pivot("RightArm", Vector3(0.34, 1.38, 0.0), self) # 在身体右侧建立肩部旋转支点。
	_build_arm(_left_arm, tunic, leather, leather_light, skin, -1.0) # 在左肩下组装左上臂、前臂和手。
	_build_arm(_right_arm, tunic, leather, leather_light, skin, 1.0) # 在右肩下组装右上臂、前臂和手。

	_left_leg = _pivot("LeftLeg", Vector3(-0.15, 0.88, 0.0), self) # 建立左腿根部支点，供步态动画旋转。
	_right_leg = _pivot("RightLeg", Vector3(0.15, 0.88, 0.0), self) # 建立右腿根部支点，供步态动画旋转。
	_build_leg(_left_leg, tunic, leather, leather_light) # 在左腿支点下添加裤腿和靴子。
	_build_leg(_right_leg, tunic, leather, leather_light) # 在右腿支点下添加裤腿和靴子。


func _build_arm(pivot: Node3D, tunic: StandardMaterial3D, leather: StandardMaterial3D, leather_light: StandardMaterial3D, skin: StandardMaterial3D, side: float) -> void: # 在给定肩部支点下组装一条手臂并保存其前臂支点。
	_capsule(pivot, "UpperSleeve", 0.105, 0.43, tunic, Vector3(0.0, -0.22, 0.0)) # 用胶囊网格制作从肩部向下延伸的上臂袖子。
	_sphere(pivot, "Shoulder", Vector3(0.0, -0.04, 0.0), Vector3(0.13, 0.13, 0.13), tunic) # 用球体让肩膀和袖子的连接处更圆润。
	var forearm := _pivot("Forearm", Vector3(0.0, -0.43, 0.0), pivot) # 创建肘部以下的前臂支点。
	_capsule(forearm, "Bracer", 0.085, 0.34, leather, Vector3(0.0, -0.16, 0.0)) # 添加深色皮革护臂。
	_sphere(forearm, "Hand", Vector3(0.0, -0.37, 0.0), Vector3(0.085, 0.09, 0.08), skin) # 在手臂末端添加肤色手部。
	_cylinder(forearm, "BracerRim", 0.09, 0.055, leather_light, Vector3(0.0, -0.29, 0.0)) # 给护臂添加浅色圆柱装饰边。
	if side < 0.0: # 根据 side 的正负值判断当前生成的是左手还是右手。
		_left_forearm = forearm # 保存左前臂节点，动画更新时可直接访问。
	else: # side 为正数时处理角色右侧。
		_right_forearm = forearm # 保存右前臂节点，动画更新时可直接访问。


func _build_leg(pivot: Node3D, tunic: StandardMaterial3D, leather: StandardMaterial3D, leather_light: StandardMaterial3D) -> void: # 在指定腿部支点下组装裤腿和靴子。
	_capsule(pivot, "Trousers", 0.12, 0.46, tunic, Vector3(0.0, -0.23, 0.0)) # 用绿色胶囊网格表现裤腿主体。
	_capsule(pivot, "Boot", 0.12, 0.28, leather, Vector3(0.0, -0.55, -0.015)) # 在裤腿下方添加棕色靴筒。
	_box(pivot, "BootToe", Vector3(0.19, 0.11, 0.24), leather_light, Vector3(0.0, -0.75, -0.055)) # 添加向角色前方延伸的靴尖。


func _pivot(node_name: String, local_position: Vector3, parent: Node3D) -> Node3D: # 新建空的三维节点，作为模型部件的可旋转支点。
	var pivot := Node3D.new() # 创建不显示几何、不参与碰撞的普通三维节点。
	pivot.name = node_name # 设置节点名称，方便在场景树中辨认。
	pivot.position = local_position # 设置相对于父节点的局部坐标。
	parent.add_child(pivot) # 将支点加入父节点，使其进入场景树。
	return pivot # 返回创建好的支点供调用方保存和继续组装。


func _capsule(parent: Node3D, node_name: String, radius: float, height: float, material: StandardMaterial3D, local_position: Vector3) -> MeshInstance3D: # 创建指定半径、高度和材质的胶囊形网格部件。
	var mesh := CapsuleMesh.new() # 新建 Godot 内置的胶囊网格资源。
	mesh.radius = radius # 设置胶囊半径，控制部件粗细。
	mesh.height = height # 设置胶囊高度，控制部件长度。
	return _mesh_part(parent, node_name, mesh, material, local_position) # 调用通用函数创建节点并返回。


func _sphere(parent: Node3D, node_name: String, local_position: Vector3, scale: Vector3, material: StandardMaterial3D) -> MeshInstance3D: # 创建球形网格，并允许沿三个坐标轴分别缩放。
	var mesh := SphereMesh.new() # 新建 Godot 内置球体网格资源。
	var part := _mesh_part(parent, node_name, mesh, material, local_position) # 创建并放置球体节点。
	part.scale = scale # 设置球体 X、Y、Z 方向缩放以形成椭圆或其他比例。
	return part # 返回球体节点供调用方继续设置。


func _box(parent: Node3D, node_name: String, size: Vector3, material: StandardMaterial3D, local_position: Vector3) -> MeshInstance3D: # 创建指定三轴尺寸的盒形网格部件。
	var mesh := BoxMesh.new() # 新建 Godot 内置盒形网格资源。
	mesh.size = size # 设置盒子宽度、高度和深度。
	return _mesh_part(parent, node_name, mesh, material, local_position) # 创建网格实例节点并返回。


func _cylinder(parent: Node3D, node_name: String, radius: float, height: float, material: StandardMaterial3D, local_position: Vector3) -> MeshInstance3D: # 创建上下半径相等的圆柱形网格部件。
	var mesh := CylinderMesh.new() # 新建 Godot 内置圆柱网格资源。
	mesh.top_radius = radius # 设置圆柱上端半径。
	mesh.bottom_radius = radius # 设置圆柱下端半径，使圆柱两端等宽。
	mesh.height = height # 设置圆柱沿 Y 轴的高度。
	return _mesh_part(parent, node_name, mesh, material, local_position) # 创建网格实例节点并返回。


func _mesh_part(parent: Node3D, node_name: String, mesh: Mesh, material: StandardMaterial3D, local_position: Vector3) -> MeshInstance3D: # 通用网格实例工厂，统一设置名称、网格、材质和位置。
	var part := MeshInstance3D.new() # 创建一个负责绘制三维网格的节点。
	part.name = node_name # 设置节点名称，便于场景树调试。
	part.mesh = mesh # 指定该节点要绘制的几何网格资源。
	part.material_override = material # 指定覆盖材质，确保部件使用预期外观。
	part.position = local_position # 设置部件相对于父节点的局部位置。
	parent.add_child(part) # 将部件添加到指定父节点下。
	return part # 返回网格实例，供调用方进一步修改或保存。


func _material(color: Color) -> StandardMaterial3D: # 创建表面偏哑光的标准材质并设置其基础颜色。
	var material := StandardMaterial3D.new() # 新建 Godot 标准三维材质资源。
	material.albedo_color = color # 设置材质的基础漫反射颜色。
	material.roughness = 0.82 # 使用较高粗糙度降低镜面高光，使材质看起来不那么光滑。
	return material # 返回材质供角色各个模型部件使用。
