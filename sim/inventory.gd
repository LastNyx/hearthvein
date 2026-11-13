class_name Inventory
extends RefCounted
## Goods held by one building. Amounts are floats (Lumen leaks fractionally); UI rounds.
## Mode "per_good": cap applies to each good separately. Mode "total": cap is shared by any mix.
## An empty accept filter accepts every good.

const EPS := 0.000001

var mode: String = "total"
var cap: float = 0.0
## Accepted good ids (id -> true). Empty = accept all.
var accept: Dictionary = {}
var _amounts: Dictionary = {}  # good id -> float


func _init(p_mode: String = "total", p_cap: float = 0.0) -> void:
	mode = p_mode
	cap = p_cap


func accepts(good: String) -> bool:
	return accept.is_empty() or accept.has(good)


func set_filter(goods: Array) -> void:
	accept.clear()
	for g in goods:
		accept[str(g)] = true


func amount_of(good: String) -> float:
	return _amounts.get(good, 0.0)


func total() -> float:
	var sum := 0.0
	for g in _amounts:
		sum += _amounts[g]
	return sum


## Room left for this good (0 when filtered out).
func free_for(good: String) -> float:
	if not accepts(good):
		return 0.0
	var used := amount_of(good) if mode == "per_good" else total()
	return maxf(0.0, cap - used)


## Returns the amount actually stored.
func add(good: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var taken := minf(amount, free_for(good))
	if taken <= 0.0:
		return 0.0
	_amounts[good] = amount_of(good) + taken
	return taken


## Returns the amount actually removed.
func remove(good: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var have := amount_of(good)
	var taken := minf(amount, have)
	if taken <= 0.0:
		return 0.0
	if have - taken <= EPS:
		_amounts.erase(good)
	else:
		_amounts[good] = have - taken
	return taken


func goods() -> Array:
	return _amounts.keys()
