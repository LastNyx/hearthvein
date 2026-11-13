class_name StorageSystem
extends SimSystem
## Daily raw-Lumen leak (design.md section 7). Lumen cells do not leak.

const LEAK_GOOD := "lumen"
const LEAK_PER_DAY := 0.01


func on_day(settlement: Settlement) -> void:
	for id in settlement.buildings:
		var b: Building = settlement.buildings[id]
		if b.inventory == null:
			continue
		var have := b.inventory.amount_of(LEAK_GOOD)
		if have > 0.0:
			b.inventory.remove(LEAK_GOOD, have * LEAK_PER_DAY)
