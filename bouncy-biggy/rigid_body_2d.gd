extends RigidBody2D

var power = 600.0
var rotation_speed = 2.0

@onready var aiming_arrow = $Sprite2D # Yön oku

#func _process(delta: float) -> void:
#	# 1. Okun açısını tuşlarla değiştir
#	if Input.is_action_pressed("sol"):
#		rotation -= rotation_speed * delta
#	elif Input.is_action_pressed("sag"):
#		rotation += rotation_speed * delta

	# 2. Boşluk tuşuna basınca topu fırlat
#	if Input.is_action_just_pressed("zipla"): # veya "ates_et"
#		fire()

func fire() -> void:
	# Bakış açısına göre bir vektör hesaplayıp kuvveti verme
	var launch_direction = Vector2.RIGHT.rotated(rotation)
	apply_central_impulse(launch_direction * power)
	
