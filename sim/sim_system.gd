class_name SimSystem
extends RefCounted
## Base class for a simulation system (production, growth, blight ...). Override the hooks you need and
## register with Settlement.add_system(). Hooks run in registration order.

func on_hour(_settlement: Settlement) -> void:
	pass


func on_day(_settlement: Settlement) -> void:
	pass


func on_season(_settlement: Settlement) -> void:
	pass
