class_name WorldRelic # 注册全局脚本类名，让其他脚本可以用 WorldRelic 类型声明遗物实例。
extends Area3D # 继承区域节点，以检测物理物体进入遗物范围而不阻挡它们移动。

signal collected # 玩家拾取遗物时发出此信号，世界脚本收到后更新收集计数。

var _elapsed: float = 0.0 # 累积遗物存在时间，用来驱动上下浮动和灯光变化。
@onready var orb: MeshInstance3D = $Orb # 缓存场景中的球形网格节点，后续更新材质、位置和旋转。
@onready var light: OmniLight3D = $Light # 缓存场景中的点光源节点，后续改变光照强度。


func _ready() -> void: # 遗物加入场景树时初始化发光外观，并连接区域进入事件。
	var material := StandardMaterial3D.new() # 新建标准材质，专门控制遗物球体的外观。
	material.albedo_color = Color(0.25, 0.85, 1.0) # 设置球体为明亮的青蓝色。
	material.emission_enabled = true # 打开发光通道，让球体自身看起来像在发光。
	material.emission = Color(0.1, 0.65, 1.0) # 设置发光颜色为蓝青色。
	material.emission_energy_multiplier = 1.4 # 提高发光能量，使遗物在环境中更醒目。
	orb.material_override = material # 将刚创建的发光材质应用到球形网格。
	body_entered.connect(_on_body_entered) # 有物理身体进入 Area3D 时调用拾取处理函数。


func _process(delta: float) -> void: # 每个渲染帧更新遗物的浮动、转动和脉动光照。
	_elapsed += delta # 累加帧时间，得到连续递增的动画计时值。
	orb.position.y = sin(_elapsed * 2.0) * 0.18 # 用正弦曲线让球体围绕初始位置上下浮动。
	orb.rotation.y += delta * 1.2 # 按帧时间旋转球体，使旋转速度不受帧率影响。
	light.light_energy = 1.2 + sin(_elapsed * 3.0) * 0.4 # 用不同频率的正弦波让点光源亮度周期性变化。


func _on_body_entered(body: Node3D) -> void: # Area3D 检测到物理物体进入时执行，参数是进入区域的节点。
	if body.is_in_group("player"): # 只处理属于 player 组的角色，忽略其他物理物体。
		collected.emit() # 发出拾取信号，让世界逻辑增加已收集数量并更新 HUD。
		queue_free() # 将遗物安排在本帧结束时删除，避免重复拾取。
