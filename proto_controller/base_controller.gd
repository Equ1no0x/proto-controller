extends CharacterBody3D

## Can we move around?
@export var can_move : bool = true
## Are we affected by gravity?
@export var has_gravity : bool = true
## Can we press to jump?
@export var can_jump : bool = true
## Can we hold to run?
@export var can_sprint : bool = true
## Can we press to enter noclip mode (noclip)?
@export var can_noclip : bool = false

@export_group("Camera")
## Mouse look sensitivity multiplier (0.5 = half speed, 2.0 = double speed).
@export var mouse_sensitivity : float = 1.0
## Look around rotation speed (base value, scaled by mouse_sensitivity).
@export var look_speed : float = 0.002
## Smooth the look in render frames (independent of physics).
@export var use_look_smoothing : bool = false
## Higher = snappier camera, lower = floatier.
@export var look_smoothing : float = 12.0

@export_group("Speeds")
## How fast do we walk?
@export var walk_speed : float = 6.0
## How fast do we sprint?
@export var sprint_speed : float = 8.0
## How far do we jump (vertical velocity)?
@export var jump_velocity : float = 4.5
## How fast do we noclip?
@export var noclip_speed : float = 25.0

@export_group("Air Control")
## Amount of lateral movement control while falling (0.0 = no control, 1.0 = full control at walk_speed).
@export_range(0.0, 1.0) var air_control : float = 0.2
## Multiplier applied to air_control when lateral velocity is below air_control_boost_threshold.
## Allows tighter control at low speeds (e.g., stationary jumps), looser at high speeds.
@export var air_control_boost_multiplier : float = 2.0
## When horizontal speed is below this threshold (m/s), apply air_control_boost_multiplier.
## Set to 0.0 to disable boosting. Typical: 2.0-4.0 m/s.
@export var air_control_boost_threshold : float = 3.0
## Friction applied to lateral air movement when falling (opposes horizontal velocity).
## Higher = more air drag, lower = momentum preservation. 0.0 = no friction.
@export var falling_lateral_friction : float = 0.0
## Deceleration applied when no input is given while falling (m/s²).
## Helps slow down horizontal movement when player releases input mid-air.
@export var braking_deceleration_falling : float = 0.0
## Maximum angle (degrees) you can deviate from initial jump direction when airborne.
## Only applies if you had horizontal velocity when jumping. 180.0 = no clamping.
@export_range(0.0, 180.0) var max_air_turn_angle : float = 90.0

@export_subgroup("Stationary Jump Air Control")
## Acceleration curve exponent for stationary jumps (1.0 = linear, >1.0 = faster start/slower end, <1.0 = slower start/faster end).
## Higher values (2.0-3.0) give snappier initial control that fades. Lower (0.5-0.8) builds momentum gradually.
@export_range(0.1, 5.0) var stationary_jump_curve : float = 2.5
## How long (seconds) stationary jump air control lasts at full strength before fading.
## After this time, control strength decays based on curve.
@export var stationary_jump_duration : float = 1
## Falloff rate after stationary_jump_duration expires (higher = faster decay).
@export var stationary_jump_falloff : float = 2.0

@export_subgroup("Moving Jump Air Control")
## How long (seconds) to preserve momentum after jumping while moving.
## During this time, you maintain horizontal acceleration even without input.
@export var momentum_preserve_time : float = 1.0
## Speed at which you descend faster when releasing input mid-air (multiplier to gravity).
## 1.0 = normal gravity, 2.0 = double gravity when no input. Set to 1.0 to disable.
@export var no_input_gravity_multiplier : float = 1.5
## How much momentum can be redirected toward camera forward direction while airborne.
## 0.0 = keep jump direction momentum, 1.0 = fully redirect to camera look, values between blend both.
## Only applies during momentum preservation window after jumping while moving.
@export_range(0.0, 1.0) var momentum_redirect_to_camera : float = 0.5


@export_group("Landing")
## Decelerate horizontal movement briefly after landing from a jump.
@export var landing_deceleration : bool = true
## Duration (seconds) of landing deceleration effect.
@export var landing_decel_time : float = 0.15
## Percentage of speed maintained during landing (0.0 = full stop, 1.0 = no decel).
@export var landing_speed_retain : float = 0.7

@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_left : String = "ui_left"
## Name of Input Action to move Right.
@export var input_right : String = "ui_right"
## Name of Input Action to move Forward.
@export var input_forward : String = "ui_up"
## Name of Input Action to move Backward.
@export var input_back : String = "ui_down"
## Name of Input Action to Jump.
@export var input_jump : String = "ui_accept"
## Name of Input Action to Sprint.
@export var input_sprint : String = "sprint"
## Name of Input Action to toggle noclip mode.
@export var input_noclip : String = "noclip"

var mouse_captured : bool = false
## Target look rotation (x=pitch, y=yaw). Applied with smoothing in _process.
var look_rotation : Vector2
var move_speed : float = 0.0
var nocliping : bool = false

## Tracking for air control logic
var jump_start_horizontal_velocity : Vector3 = Vector3.ZERO  # Stored at jump to prevent speed boosting
var time_since_jump : float = 0.0  # Tracks time in air for stationary jump curve
var was_stationary_jump : bool = false  # Did we jump from standstill?
var momentum_preserve_timer : float = 0.0  # Timer for momentum preservation after moving jump

## Tracking for landing deceleration
var landing_decel_timer : float = 0.0
var is_landing_decel : bool = false

## IMPORTANT REFERENCES
@onready var cameraController: Node3D = $cameraController
@onready var collider: CollisionShape3D = $collider

func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = cameraController.rotation.x

func _unhandled_input(event: InputEvent) -> void:
	# Mouse capturing
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()

	# Look around: update target rotation based on mouse motion.
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)

	# Toggle noclip mode
	if can_noclip and Input.is_action_just_pressed(input_noclip):
		if not nocliping:
			enable_noclip()
		else:
			disable_noclip()

## Render-tick interpolation for camera look.
## Keeps movement in physics while smoothing yaw/pitch here for buttery feel.
func _process(delta: float) -> void:
	var target_yaw := look_rotation.y
	var target_pitch := look_rotation.x
	if use_look_smoothing:
		var t := clamp(look_smoothing * delta, 0.0, 1.0)
		var new_yaw := lerp_angle(rotation.y, target_yaw, t)
		var new_pitch := lerp(cameraController.rotation.x, target_pitch, t)
		transform.basis = Basis()
		rotate_y(new_yaw)
		cameraController.transform.basis = Basis()
		cameraController.rotate_x(new_pitch)
	else:
		transform.basis = Basis()
		rotate_y(target_yaw)
		cameraController.transform.basis = Basis()
		cameraController.rotate_x(target_pitch)

func _physics_process(delta: float) -> void:
	# If nocliping, handle noclip and nothing else
	if can_noclip and nocliping:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (cameraController.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		motion *= noclip_speed * delta
		move_and_collide(motion)
		return

	# Apply gravity to velocity
	if has_gravity:
		if not is_on_floor():
			velocity += get_gravity() * delta

	# Apply jumping
	if can_jump:
		if Input.is_action_just_pressed(input_jump) and is_on_floor():
			# Store horizontal velocity at jump start to prevent boosting beyond this speed
			# Air control can't exceed walk_speed or jump start speed
			jump_start_horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
			
			# Detect if this is a stationary jump (no horizontal movement)
			var jump_start_speed := jump_start_horizontal_velocity.length()
			if jump_start_speed < 0.1:
				was_stationary_jump = true
				time_since_jump = 0.0
			else:
				was_stationary_jump = false
				momentum_preserve_timer = momentum_preserve_time
			
			# Apply vertical jump impulse without modifying horizontal velocity
			velocity.y = jump_velocity

	# Update landing deceleration timer
	if is_landing_decel:
		landing_decel_timer -= delta
		if landing_decel_timer <= 0.0:
			is_landing_decel = false

	# Modify speed based on sprinting
	if can_sprint and Input.is_action_pressed(input_sprint):
			move_speed = sprint_speed
	else:
		move_speed = walk_speed

	# Apply desired movement to velocity
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if move_dir:
			if is_on_floor():
				# Ground: instant direction and speed.
				var target_vel_x := move_dir.x * move_speed
				var target_vel_z := move_dir.z * move_speed
				
				# Apply landing deceleration if active
				if landing_deceleration and is_landing_decel:
					target_vel_x *= landing_speed_retain
					target_vel_z *= landing_speed_retain
				
				velocity.x = target_vel_x
				velocity.z = target_vel_z
			else:
				# Air: Air control system
				var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
				var horizontal_speed := horizontal_vel.length()
				var jump_start_speed := jump_start_horizontal_velocity.length()
				
				var effective_air_control := air_control
				
				# STATIONARY JUMP: Apply acceleration curve for more natural feel
				if was_stationary_jump:
					time_since_jump += delta
					
					# Calculate curve factor based on time in air
					var curve_factor := 1.0
					if time_since_jump < stationary_jump_duration:
						# During active control window: apply acceleration curve
						# t goes from 0 to 1 over the duration
						var t: float = time_since_jump / stationary_jump_duration
						# Curve: higher exponent = snappier start, slower end
						# Linear (1.0): constant control
						# >1.0: front-loaded (quick start, fades)
						# <1.0: back-loaded (slow start, builds up)
						curve_factor = pow(1.0 - t, stationary_jump_curve)
					else:
						# After duration: exponential falloff
						var overtime: float = time_since_jump - stationary_jump_duration
						curve_factor = exp(-stationary_jump_falloff * overtime)
					
					effective_air_control *= curve_factor
					
				# MOVING JUMP: Preserve momentum for a duration
				else:
					# Tick down momentum preserve timer
					if momentum_preserve_timer > 0.0:
						momentum_preserve_timer -= delta
				
				# Boost air control when moving slowly (helps recover from low speeds)
				if air_control_boost_threshold > 0.0 and horizontal_speed < air_control_boost_threshold:
					effective_air_control = min(air_control * air_control_boost_multiplier, 1.0)
				
				if effective_air_control > 0.0:
					
					# Clamp turn angle if we had momentum when jumping
					if jump_start_speed > 0.1 and max_air_turn_angle < 180.0:
						var jump_dir := jump_start_horizontal_velocity.normalized()
						var angle_to_jump := rad_to_deg(acos(clamp(move_dir.dot(jump_dir), -1.0, 1.0)))
						var target_speed : float
						var max_air_speed : float
						if angle_to_jump > max_air_turn_angle:
							# Clamp input direction to max allowed angle from jump direction
							var max_angle_rad := deg_to_rad(max_air_turn_angle)
							var axis := jump_dir.cross(move_dir)
							if axis.length() > 0.01:
								move_dir = jump_dir.rotated(axis.normalized(), max_angle_rad).normalized()
					
					# Calculate target speed based on jump type
					var target_speed : float
					
					if was_stationary_jump:
						# Stationary: can accelerate up to walk_speed with air control
						target_speed = walk_speed * effective_air_control
					else:
						# Moving: preserve jump start speed during momentum window
						if momentum_preserve_timer > 0.0:
							# Preserve momentum: use jump start speed as target
							target_speed = jump_start_speed * effective_air_control
						else:
							# After momentum expires: fall back to walk_speed control
							target_speed = walk_speed * effective_air_control
					
					# Calculate max speed cap: can't exceed walk_speed OR jump start speed
					# This is the KEY to preventing velocity boosting (UE approach)
					var max_air_speed := max(walk_speed, jump_start_speed)
					
					# Determine acceleration direction based on jump type
					var accel_direction := move_dir
					
					# MOVING JUMP: Redirect momentum toward camera forward based on setting
					if not was_stationary_jump and momentum_preserve_timer > 0.0:
						if momentum_redirect_to_camera > 0.0:
							# Get current camera forward direction (updated every frame)
							var current_camera_forward := -cameraController.global_transform.basis.z
							var camera_forward_horizontal := Vector3(current_camera_forward.x, 0, current_camera_forward.z).normalized()
							
							if camera_forward_horizontal.length() > 0.01:
								# Blend between jump start direction and current camera forward direction
								var jump_dir := jump_start_horizontal_velocity.normalized()
								# Use slerp for smooth blending between directions
								accel_direction = jump_dir.slerp(camera_forward_horizontal, momentum_redirect_to_camera).normalized()
					
					# Apply lateral acceleration toward acceleration direction
					var current_speed_in_dir := velocity.dot(accel_direction)
					var add_speed := target_speed - current_speed_in_dir
					
					if add_speed > 0.0:
						# Use max acceleration scaled by air control as acceleration rate
						var accel_amount := walk_speed * 10.0 * effective_air_control * delta
						accel_amount = min(accel_amount, add_speed)
						
						var new_velocity: Vector3 = velocity + accel_direction * accel_amount
						var new_horizontal := Vector3(new_velocity.x, 0, new_velocity.z)
						
						# CRITICAL: Clamp total horizontal speed to max_air_speed
						# This prevents velocity boosting when jumping while moving
						if new_horizontal.length() <= max_air_speed:
							velocity = new_velocity
							
				# Apply falling lateral friction (velocity-dependent drag)
				if falling_lateral_friction > 0.0:
					var friction_amount := falling_lateral_friction * horizontal_speed * delta
					if horizontal_speed > 0.0:
						var friction_dir := horizontal_vel.normalized()
						var new_speed := max(horizontal_speed - friction_amount, 0.0)
						velocity.x = friction_dir.x * new_speed
						velocity.z = friction_dir.z * new_speed
		else:
			# No input: apply braking deceleration
			var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
			var horizontal_speed := horizontal_vel.length()
			
			if horizontal_speed > 0.0:
				if is_on_floor():
					# Ground: instant stop (snappy)
					velocity.x = 0.0
					velocity.z = 0.0
				else:
					# Air: apply braking deceleration (constant opposing force)
					if braking_deceleration_falling > 0.0:
						var decel_amount := braking_deceleration_falling * delta
						var new_speed := max(horizontal_speed - decel_amount, 0.0)
						var decel_dir := horizontal_vel.normalized()
						velocity.x = decel_dir.x * new_speed
						velocity.z = decel_dir.z * new_speed
						
					# MOVING JUMP: Apply faster descent when no input after momentum expires
					if not was_stationary_jump and momentum_preserve_timer <= 0.0:
						if no_input_gravity_multiplier > 1.0:
							# Apply additional gravity to make player fall faster
							var extra_gravity: Vector3 = get_gravity() * (no_input_gravity_multiplier - 1.0)
							velocity += extra_gravity * delta
			else:
				velocity.x = 0
				velocity.z = 0

	# Use velocity to actually move
	var was_in_air := not is_on_floor()
	move_and_slide()
	
	# Detect landing: if we were in air and now on floor, start deceleration
	if landing_deceleration and was_in_air and is_on_floor():
		is_landing_decel = true
		landing_decel_timer = landing_decel_time


## Rotate us to look around.
## Base of controller rotates around y (left/right). Head rotates around x (up/down).
## Modifies look_rotation (targets) based on rot_input; actual rotation is applied in _process for smoothing.
func rotate_look(rot_input : Vector2):
	look_rotation.x -= rot_input.y * look_speed * mouse_sensitivity
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed * mouse_sensitivity
	# Actual basis changes happen in _process to decouple camera feel from physics.

## Disable clipping movement vectors
func enable_noclip():
	collider.disabled = true
	nocliping = true
	velocity = Vector3.ZERO

## Enable clipping movement vectors
func disable_noclip():
	collider.disabled = false
	nocliping = false


func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


## Checks if some Input Actions haven't been created.
## Disables functionality accordingly.
func check_input_mappings():
	if can_move and not InputMap.has_action(input_left):
		push_error("Movement disabled. No InputAction found for input_left: " + input_left)
		can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Movement disabled. No InputAction found for input_right: " + input_right)
		can_move = false
	if can_move and not InputMap.has_action(input_forward):
		push_error("Movement disabled. No InputAction found for input_forward: " + input_forward)
		can_move = false
	if can_move and not InputMap.has_action(input_back):
		push_error("Movement disabled. No InputAction found for input_back: " + input_back)
		can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Jumping disabled. No InputAction found for input_jump: " + input_jump)
		can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Sprinting disabled. No InputAction found for input_sprint: " + input_sprint)
		can_sprint = false
	if can_noclip and not InputMap.has_action(input_noclip):
		push_error("noclip disabled. No InputAction found for input_noclip: " + input_noclip)
		can_noclip = false
