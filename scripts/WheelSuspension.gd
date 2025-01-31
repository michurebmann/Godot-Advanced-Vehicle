class_name RaycastSuspension
extends RayCast

############# Choose what tire formula to use #############
export var tire_model: Resource 

############# Suspension stuff #############
export (float) var spring_length = 0.2
export (float) var spring_stiffness = 20000.0
export (float) var bump = 5000.0
export (float) var rebound = 3000.0
export (float) var anti_roll = 0.0

############# Tire stuff #############

export (float) var wheel_mass = 15.0
export (float) var tire_radius = 0.3
export (float) var tire_width = 0.2
export (float) var ackermann = 0.15

var peak_sr: float = 0.10
var peak_sa: float = 0.10

var tire_wear: float = 0.0

var surface_mu = 1.0
var y_force: float = 0.0
#var braketorque: float = 0.0

var wheel_moment: float = 0.0
var spin: float = 0.0
var z_vel: float = 0.0
var local_vel

var rolling_resistance: float = 0.0 #Vector2 = Vector2.ZERO
var rol_res_surface_mul: float = 0.02

var force_vec = Vector3.ZERO
var slip_vec: Vector2 = Vector2.ZERO
var prev_pos: Vector3 = Vector3.ZERO

var prev_compress: float = 0.0
var spring_curr_length: float = spring_length


onready var car = $'..' #Get the parent node as car
onready var wheelmesh = $MeshInstance


func _ready() -> void:
#	var nominal_load = car.weight * 0.25
	wheel_moment = 0.5 * wheel_mass * pow(tire_radius, 2)
	set_cast_to(Vector3.DOWN * (spring_length + tire_radius))


#func _process(delta: float) -> void:
func _physics_process(delta: float) -> void:
	wheelmesh.translation.y = -spring_curr_length
	wheelmesh.rotate_x(wrapf(-spin * delta,0, TAU))
	if abs(z_vel) > 2.0:
		tire_wear = tire_model.update_tire_wear(delta, slip_vec, y_force, surface_mu)


func apply_forces(opposite_comp, delta):
	############# Local forward velocity #############
	
	local_vel = global_transform.basis.xform_inv((global_transform.origin - prev_pos) / delta)
	z_vel = -local_vel.z
	var planar_vect = Vector2(local_vel.x, local_vel.z).normalized()
	prev_pos = global_transform.origin
	
	var surface
	############# Suspension #################
	if is_colliding():
		if get_collider().get_groups().size() > 0:
			surface = get_collider().get_groups()[0]
		if surface:
			surface_mu = 1.0
			if surface == "Tarmac":
				surface_mu = 1.0 
				rol_res_surface_mul = 0.01
			elif surface == "Gravel":
				surface_mu = 0.6
				rol_res_surface_mul = 0.03
			elif surface == "Grass":
				surface_mu = 0.55  
				rol_res_surface_mul = 0.025
			elif surface == "Snow":
				surface_mu = 0.4
				rol_res_surface_mul = 0.035
		spring_curr_length = get_collision_point().distance_to(global_transform.origin) - tire_radius
	else:
		spring_curr_length = spring_length
		
	var compress = 1 - spring_curr_length / spring_length
	y_force = spring_stiffness * compress * spring_length

	if (compress - prev_compress) >= 0:
		y_force += (bump + wheel_mass) * (compress - prev_compress) * spring_length / delta
	else:
		y_force += rebound * (compress - prev_compress) * spring_length  / delta
	
	y_force = max(0, y_force)
	prev_compress = compress
	
	############### Slip #######################
	slip_vec.x = asin(clamp(-planar_vect.x, -1, 1)) # X slip is lateral slip
	slip_vec.y = 0.0 # Y slip is the longitudinal Z slip
	
#	if is_colliding() and z_vel != 0:
	if not is_zero_approx(z_vel):
		slip_vec.y = (z_vel - spin * tire_radius) / abs(z_vel)
	else:
#		if spin == 0:
		if is_zero_approx(spin):
			slip_vec.y = 0.0
		else:
			slip_vec.y = 0.0001 * spin # This is to avoid "getting stuck" if local z velocity is absolute 0
	
	############### Calculate and apply the forces #######################
#	var normalised_sr = slip_vec.y / peak_sr
#	var normalised_sa = slip_vec.x / peak_sa
#	var resultant_slip = sqrt(pow(normalised_sr, 2) + pow(normalised_sa, 2))
#
#	var sr_modified = resultant_slip * peak_sr
#	var sa_modified = resultant_slip * peak_sa
	
#	if resultant_slip != 0:
#		force_vec.x = force_vec.x * abs(normalised_sa / resultant_slip)
#		force_vec.y = force_vec.y * abs(normalised_sr / resultant_slip)
#	else:
#		force_vec.x = 0
#		force_vec.y = 0
	
	force_vec = tire_model.update_tire_forces(slip_vec, y_force, surface_mu)
	
	if is_colliding():
		var contact = get_collision_point() - car.global_transform.origin
		var normal = get_collision_normal()
		
#		prints("Z force =", force_vec.y)
		car.add_force(normal * y_force, contact)
		car.add_force(global_transform.basis.x * force_vec.x, contact)
		car.add_force(global_transform.basis.z * force_vec.y, contact)
		
		### Return suspension compress info for the car bodys antirollbar calculations
		if compress !=0:
			compress = 1 - (spring_curr_length / spring_length)
			y_force += anti_roll * (compress - opposite_comp)
		return compress
	else:
		spin -= sign(spin) * delta * 2 / wheel_moment # stop undriven wheels from spinning endlessly
		return 0.0


func apply_torque(drive, drive_inertia, brake_torque, delta):
	var prev_spin = spin
	var net_torque = force_vec.y * tire_radius
	net_torque += drive
	if spin < 5 and brake_torque > abs(net_torque):
#	if brake_torque > abs(net_torque):
		spin = 0
	else:
		net_torque -= (brake_torque + rolling_resistance) * sign(spin)
		spin += delta * net_torque / (wheel_moment + drive_inertia)

	if drive * delta == 0:
		return 0.5
	else:
		return (spin - prev_spin) * (wheel_moment + drive_inertia) / (drive * delta)


func applySolidAxleSpin(axlespin):
	spin = axlespin


func steer(input, max_steer):
	rotation.y = max_steer * (input + (1 - cos(input * 0.5 * PI)) * ackermann)
