extends KinematicBody2D

signal on_bounce(velocity)
signal on_hit_wall(velocity)
signal on_land(velocity)
signal on_jump(velocity)
signal sprinting_changed(new_value)
signal facing_changed(facing_right)

#exported variables
export(float, 0, 10000) var run_speed := 200.0
export(float, 0, 10000) var sprint_multiplier := 2.0

#uses_acceleration switches between logic for motion. 
#if it is set to true friction and gradual acceleration will be applied 
#if false the bodies velocity will be set whatever the user's input is instantly. 
export(bool) var uses_acceleration := true 

#accelerations
export(float, 0, 10000) var ground_acceleration := 1500.0
export(float, 0, 10000) var air_acceleration := 700.0
#deceleration
export(float, 0, 10000) var air_deceleration := 700.0
export(float, 0, 10000) var ground_deceleration  := 5000.0
#gravity
export(float, 0, 10000) var gravity := 1000.0
export(float, 0, 1) var jumping_gravity_multiplier := 0.6
#jump
export(float, 0, 10000) var ground_jump_power := 350.0
export(float, 0, 10000) var air_jump_power := 350.0
export(int, 0, 100) var air_jumps = 1
export(float, 0, 1) var coyote_time := 0.05

export(float, 0, 1) var elasticity := 0.0
export(float, 0, 1000) var min_bounce := 0.0
export(bool) var bounce_on_walls = false
export(bool) var reset_jumps_on_bounce = false
export(bool) var allow_jump_on_bounce = false

#public veriables
#this is used to shut down the basic phsyics on this controller.
#Maybe there is a smarter way of doing this, but I use it for if an
#class extending this one wants to do something like, freeze you mid air or
#give the character diffrent phsyics after like... say grabbing a glider or 
#something.
var run_basic_phsyics = true
#makes the character stop listening to the users input.
var listen_to_input = true

var sprinting := false setget sprinting_set, sprinting_get
func sprinting_set(new_value : bool):
	if(sprinting == new_value):
		return
	sprinting = new_value
	emit_signal("sprinting_changed", sprinting)
func sprinting_get():
	return sprinting 
var velocity := Vector2(0,0)

#private veriables
var _snap_distance = 32
var _facing_right := true
#jump info
var _ground_jump := true
var _jumpped := false
var _jump_uses_current_velocity := false
var _jumps_left := 0
var _jump_qued := false
var _holding_jump := false
var _air_time := 0.01
var _movement_input := Vector2()
#event flags
var _just_jumpped := false
var _just_landed := false
var _last_land_speed = velocity
var _just_turned := false
var _on_floor := false
var _last_floor_speed
var _falling = false

func _process(delta):
	get_input()
	if(_just_landed):
		_just_landed = false
		emit_signal("on_land", _last_land_speed)
	if(_just_jumpped):
		_just_jumpped = false
		emit_signal("on_jump", velocity)
	if(_just_turned):
		emit_signal("facing_changed", _facing_right)

func get_input():
	_movement_input = Vector2()
	#Get the player's movement vector.
	if listen_to_input:
		_movement_input.x -= Input.get_action_strength("move_left")
		_movement_input.x += Input.get_action_strength("move_right")
		if(!_jump_qued):
			_jump_qued = Input.is_action_just_pressed("jump")
		_holding_jump = Input.is_action_pressed("jump")
		self.sprinting = Input.is_action_pressed("sprint")

func _physics_process(delta):
	if run_basic_phsyics:
		do_charactor_physics(delta)

func do_charactor_physics(delta):
	_handle_walls_and_floor(delta)
	_apply_gravity(delta)
	if(uses_acceleration):
		_handle_acceleration(delta)
	else:
		velocity.x = _movement_input.x * max_run_speed()
	_handle_jumping()
	var snap = Vector2.DOWN * _snap_distance
	if _jumpped || _falling:
		snap = Vector2(0,0)
	move_and_slide_with_snap(velocity, snap, Vector2.UP, false, 4, 0.8)
	_handle_facing()

func _handle_walls_and_floor(delta):
	if(is_on_wall()):
		emit_signal("on_hit_wall", velocity)
		if(bounce_on_walls):
			velocity.x = -velocity.x * elasticity
			emit_signal("on_bounce", velocity)
		else:
			velocity.x = 0
		
	if(is_on_ceiling()):
		if(bounce_on_walls):
			velocity.y = -velocity.y * elasticity
		else:
			velocity.y = 0
	
	#before updating our on floor status we want to launch the player 
	if _on_floor && !is_on_floor():
		velocity += _last_floor_speed
		_last_floor_speed = Vector2(0,0)
	_on_floor = is_on_floor()

	if(_on_floor):
		_last_land_speed = velocity
		_falling = false
		_last_floor_speed = get_floor_velocity()
		#if bouncing is enabled and were going fast enough to bounce
		if (elasticity && velocity.y > min_bounce):
			velocity = velocity.bounce(get_floor_normal()) * elasticity
			emit_signal("on_bounce", velocity)
			_falling = true
			_just_landed = true
			if reset_jumps_on_bounce:
				_reset_jumps()
			if !allow_jump_on_bounce:
				_on_floor = false
		else:
			#if going down
			if(velocity.y >= 0):
				velocity.y = 0
			_reset_jumps()
	else:
		if _air_time > 0.1:
			_falling = true
		_air_time += delta

func _apply_gravity(delta):
	var gravity_rate = gravity * delta
	if(_holding_jump):
		velocity.y += gravity_rate * jumping_gravity_multiplier
	else:
		velocity.y += gravity_rate

func _handle_acceleration(delta : float):
	var target_x_velocity = _movement_input.x * max_run_speed()
	#calculate deceleration_rate
	var deceleration_rate = 0
	var acceleration_rate = 0
	#use friction if no input.
	if (!target_x_velocity):
		if(_on_floor):
			deceleration_rate = ground_deceleration * delta
		else:
			deceleration_rate = air_deceleration * delta
	#use the acceleration rate as deceleration rate if 
	#you're pushing in that direction harder then friction.
	else:
		if(_on_floor):
			acceleration_rate = ground_acceleration * delta
			deceleration_rate = max(ground_deceleration, ground_acceleration) * delta
		else:
			acceleration_rate = air_acceleration * delta
			deceleration_rate = max(air_deceleration, air_acceleration) * delta
	
	#if going too fast clamp the speed to the target speed, 
	#unless its too fast for the deceleration rate to stop.
	#then just slow it down.
	if(velocity.x < target_x_velocity):
		if velocity.x < (target_x_velocity - deceleration_rate):
			if velocity.x >= 0:
				velocity.x += acceleration_rate
			else:
				velocity.x += deceleration_rate
		else:
			velocity.x = target_x_velocity
	elif(velocity.x > target_x_velocity):
		if velocity.x > (target_x_velocity + deceleration_rate):
			if velocity.x <= 0:
				velocity.x -= acceleration_rate
			else:
				velocity.x -= deceleration_rate
		else:
			velocity.x = target_x_velocity

func _handle_facing():
	if (velocity.x > 0 && !_facing_right):
		_just_turned = true
		_facing_right = true
	elif (velocity.x < 0 && _facing_right):
		_just_turned = true
		_facing_right = false

func _handle_jumping():
	#Ground jump logic, it also works if in air for coyote
	if(_ground_jump && !_jumpped && _jump_qued && (_on_floor || _air_time < coyote_time)):
		_jumpped = true
		_just_jumpped = true
		if(_jump_uses_current_velocity):
			velocity.y -= ground_jump_power
		else:
			velocity.y = -ground_jump_power
	#Air jump logic
	elif(_jump_qued && _jumps_left > 0):
		_just_jumpped = true
		if(_jump_uses_current_velocity):
			velocity.y -= air_jump_power
		elif(velocity.y > -air_jump_power):
			velocity.y = -air_jump_power
		_jumps_left -= 1
	
	_jump_qued = false

func _reset_jumps():
	if _air_time > 0.1:
		_jumps_left = air_jumps
		_jumpped = false
		_air_time = 0
		_just_landed = true

func max_run_speed() -> float:
	var max_run_speed : float
	if(sprinting):
		max_run_speed = run_speed * sprint_multiplier
	else:
		max_run_speed = run_speed
	return max_run_speed
