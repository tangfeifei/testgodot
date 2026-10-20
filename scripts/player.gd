extends CharacterBody3D # 继承可移动物理角色节点，获得速度、重力碰撞和 move_and_slide 等能力。

@export var walk_speed: float = 6.0 # 普通移动时的水平速度，单位为米/秒，可在检查器中调整。
@export var sprint_speed: float = 10.0 # 按住 Shift 冲刺时的水平速度，单位为米/秒。
@export var jump_velocity: float = 5.5 # 起跳瞬间赋给角色的向上速度，数值越大跳得越高。
@export var mouse_sensitivity: float = 0.0025 # 鼠标移动转换为摄像机旋转的灵敏度。
@export var climb_speed: float = 3.6 # 玩家贴在树干上攀爬时的竖直速度。

@onready var camera_pivot: Node3D = $CameraPivot # 缓存摄像机旋转支点，后续用它控制观察方向和移动方向。
@onready var character_visual: Node3D = $CharacterVisual # 缓存纯视觉模型节点，旋转它不会改变玩家碰撞体方向。

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") # 从项目设置读取默认重力加速度。
var _is_climbing: bool = false # 标记玩家当前是否处于抓树攀爬状态。
var _climb_anchor: Vector3 = Vector3.ZERO # 保存玩家攀爬时贴近树干的水平位置。
var _climb_min_height: float = 0.0 # 当前树根所在的世界高度，作为攀爬下限。
var _climb_height: float = 0.0 # 当前树木允许攀爬到的最大高度。


func _ready() -> void: # 节点加入场景树时运行一次，用于设置游戏初始输入状态。
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # 捕获鼠标并隐藏光标，以便鼠标移动控制第三人称视角。
	set_collision_mask_value(2, true) # 启用树枝平台所在的第 2 层，离开攀爬时才能踩在枝条上。


func _unhandled_input(event: InputEvent) -> void: # 处理未被 UI 消耗的输入事件，例如鼠标转视角和 Escape。
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: # 只有鼠标已捕获时才允许旋转视角。
		camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity # 水平鼠标位移控制摄像机绕 Y 轴转向。
		camera_pivot.rotation.x = clampf( # 竖直鼠标位移控制俯仰，并限制最大仰角和俯角。
			camera_pivot.rotation.x - event.relative.y * mouse_sensitivity, # 根据本帧鼠标 Y 位移更新俯仰角。
			deg_to_rad(-50.0), # 允许的最小俯仰角，转换成弧度供 rotation 使用。
			deg_to_rad(25.0) # 允许的最大俯仰角，避免摄像机翻转或看得过高。
		) # 结束对俯仰角的范围限制。
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: # 按下 Escape 时切换鼠标捕获状态。
		Input.mouse_mode = ( # 根据当前状态选择显示光标或重新捕获光标。
			Input.MOUSE_MODE_VISIBLE # 如果鼠标已捕获，则显示系统光标。
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED # 判断鼠标当前是否处于捕获状态。
			else Input.MOUSE_MODE_CAPTURED # 如果鼠标可见，则重新捕获以恢复视角控制。
		) # 结束鼠标模式的条件表达式。


func _physics_process(delta: float) -> void: # 按固定物理帧更新重力、移动、碰撞和动画状态。
	var input_vector := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_head")).limit_length() # 读取摄像机相对移动输入，并限制斜向输入长度。
	if _is_climbing: # 已抓住树干时使用专门的攀爬物理逻辑。
		if not Input.is_action_pressed("climb"): # 松开 E 后结束攀爬并恢复枝条平台碰撞。
			_stop_climbing() # 清理攀爬状态，使角色可以站到枝条上或自然落下。
		else: # 持续按住 E 时保持贴树攀爬。
			_process_climbing(input_vector, delta) # 根据 W/S 输入调整攀爬高度并保持水平贴近树干。
			character_visual.update_animation(delta, 0.0, false, false, velocity.y, true) # 通知视觉脚本播放攀爬动作。
			return # 跳过普通重力和地面移动，避免攀爬时角色被拉下树干。
	if Input.is_action_pressed("climb"): # 按住 E 时持续尝试抓树，地面或空中都可以开始攀爬。
		_try_start_climbing() # 用射线判断前方是否为可攀爬树木。
		if _is_climbing: # 若射线成功抓住树干，本帧立即切换到攀爬处理。
			_process_climbing(input_vector, delta) # 开始沿树干向上或向下移动。
			character_visual.update_animation(delta, 0.0, false, false, velocity.y, true) # 进入带平滑过渡的攀爬姿势。
			return # 不再执行普通移动分支。
	if not is_on_floor(): # 角色未接触地面时才继续施加重力。
		velocity.y -= _gravity * delta # 按重力和帧间隔降低垂直速度，使角色下落。

	if Input.is_action_just_pressed("jump") and is_on_floor(): # 只有刚按下跳跃且脚下有地面时才允许起跳。
		velocity.y = jump_velocity # 赋予向上初速度，后续帧由重力逐渐抵消。

	var forward := -camera_pivot.global_basis.z # 取摄像机面对的反 Z 方向，作为角色前进方向。
	var right := camera_pivot.global_basis.x # 取摄像机右侧的 X 方向，作为角色横向移动方向。
	forward.y = 0.0 # 去掉前进方向的垂直分量，避免摄像机俯仰影响地面移动速度。
	right.y = 0.0 # 去掉右侧方向的垂直分量，使移动保持在水平面上。
	var move_direction := right.normalized() * input_vector.x + forward.normalized() * input_vector.y # 将输入轴转换为基于摄像机朝向的世界移动方向。
	var current_speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed # 按住 Shift 时使用冲刺速度，否则使用普通速度。

	velocity.x = move_direction.x * current_speed # 将移动方向的 X 分量转换为物理水平速度。
	velocity.z = move_direction.z * current_speed # 将移动方向的 Z 分量转换为物理水平速度。

	move_and_slide() # 根据 velocity 移动角色，并自动处理地形、树木、石头等物理碰撞。
	if move_direction.length_squared() > 0.01: # 仅在确实有移动输入时改变模型朝向，避免站立时抖动。
		var target_yaw := atan2(-move_direction.x, -move_direction.z) # 根据水平移动方向计算模型应朝向的 Y 轴角度。
		character_visual.rotation.y = lerp_angle( # 使用角度插值平滑转身，避免模型瞬间转向。
			character_visual.rotation.y, # 插值起点：模型当前朝向。
			target_yaw, # 插值终点：本次移动对应的目标朝向。
			1.0 - exp(-12.0 * delta) # 依据帧时间计算平滑系数，使转向速度不依赖帧率。
		) # 结束模型朝向的平滑插值。
	character_visual.update_animation( # 将玩家运动状态传给视觉脚本，由它混合行走、奔跑和跳跃姿势。
		delta, # 传递物理帧时间，供动画脚本计算平滑过渡。
		input_vector.length(), # 传递输入强度，用于判断移动程度并控制步幅。
		Input.is_key_pressed(KEY_SHIFT), # 传递 Shift 状态，区分行走和奔跑动作。
		is_on_floor(), # 传递是否接触地面的状态，用于切换空中姿势。
		velocity.y, # 传递垂直速度，用于区分跳起和下落姿势。
		false # 普通移动状态下关闭攀爬姿势。
	) # 结束动画状态更新调用。


func _try_start_climbing() -> void: # 从胸口向玩家面对方向发射射线，尝试捕捉树干。
	var ray_origin := global_position + Vector3.UP * 0.95 # 将射线起点放在玩家胸口高度。
	var forward := -camera_pivot.global_basis.z # 使用摄像机朝向决定玩家尝试抓树的方向。
	forward.y = 0.0 # 忽略摄像机俯仰，保证抓取方向保持水平。
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + forward.normalized() * 1.25, 1) # 只检测默认物理层上的树干和其他实体。
	query.exclude = [get_rid()] # 排除玩家自身，避免射线命中自己的碰撞体。
	var result := get_world_3d().direct_space_state.intersect_ray(query) # 查询射线是否与物理物体相交。
	if result.is_empty(): # 没有命中任何物体时不能开始攀爬。
		return # 结束尝试并继续正常空中移动。
	var collider := result.get("collider") as StaticBody3D # 将命中的节点转换为静态物体类型。
	if collider == null or not collider.has_meta("climb_height"): # 只接受带 climb_height 标记的树干。
		return # 命中地形、石头或建筑时不进入攀爬。
	var surface_normal: Vector3 = result.get("normal") # 读取碰撞表面法线，以便角色停在树干外侧。
	_climb_anchor = result.get("position") + surface_normal * 0.48 # 将角色锚点放到树干表面外，避免胶囊体陷入树干。
	_climb_anchor.y = global_position.y # 保留当前垂直高度，抓附时不突然抬升或下沉。
	_climb_min_height = collider.global_position.y + 0.1 # 从树干世界坐标计算攀爬下限，兼容高低不平的地形。
	_climb_height = collider.global_position.y + (collider.get_meta("climb_height") as float) # 结合树根高度计算攀爬上限。
	_is_climbing = true # 切换到攀爬状态。
	velocity = Vector3.ZERO # 抓住树干时清除原有跳跃/下落速度。
	set_collision_mask_value(2, false) # 临时忽略第 2 物理层的树枝平台，使角色能沿树干上攀。


func _process_climbing(input_vector: Vector2, delta: float) -> void: # 沿树干移动并将玩家保持在树干表面外侧。
	var climb_input := input_vector.y # W/S 的纵向输入控制攀爬方向。
	global_position.y = clampf(global_position.y + climb_input * climb_speed * delta, _climb_min_height, _climb_height - 0.65) # 限制移动高度，避免穿过地面或越过树顶。
	var horizontal_position := Vector3(_climb_anchor.x, global_position.y, _climb_anchor.z) # 使用锚点锁定 X/Z，只允许沿树干竖直移动。
	global_position = global_position.lerp(horizontal_position, 1.0 - exp(-10.0 * delta)) # 平滑贴向树干，减少抓附时的位移突变。
	velocity = Vector3.ZERO # 攀爬期间不叠加重力或水平惯性。
	move_and_slide() # 仍运行物理移动，让玩家与树干和场景保持碰撞检测。


func _stop_climbing() -> void: # 退出攀爬并恢复枝条碰撞和正常垂直运动。
	_is_climbing = false # 清除攀爬状态标记。
	set_collision_mask_value(2, true) # 恢复对枝条平台物理层的检测，使玩家可以站在枝条上。
	velocity = Vector3.ZERO # 清除抓树期间的速度，之后由普通移动/重力重新计算。
