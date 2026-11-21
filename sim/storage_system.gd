class_name StorageSystem
extends SimSystem
## Daily raw-Lumen leak (design.md section 7). Lumen cells do not leak.

const LEAK_GOOD := "lumen"
## Share of the raw Lumen stock lost a day (3%, ticket 159; was 1%).
const LEAK_PER_DAY := 0.03
## The leak only counts the first LEAK_CAP raw Lumen of the whole settlement's stock (ticket 169): a big reserve for the
## Dimming no longer drains away, and a small stock leaks 3% as before. Shared over the storages by their share.
const LEAK_CAP := 500.0
const CELL_GOOD := "lumen_cells"


func on_day(settlement: Settlement) -> void:
	var total := 0.0
	for id in settlement.buildings:
		var b: Building = settlement.buildings[id]
		if b.inventory != null:
			total += b.inventory.amount_of(LEAK_GOOD)
	var rate := LEAK_PER_DAY * minf(1.0, LEAK_CAP / total) if total > 0.0 else 0.0
	for id in settlement.buildings:
		var b: Building = settlement.buildings[id]
		if b.inventory == null:
			continue
		var have := b.inventory.amount_of(LEAK_GOOD)
		if have > 0.0:
			b.inventory.remove(LEAK_GOOD, have * rate)


## Auto-spend of Lumen cells (design.md section 7: "when raw Lumen runs out, buildings and light draw on cells
## automatically, 1 cell = 5 Lumen"). Breaks whole cells into raw Lumen in the storage that holds them until
## `amount` Lumen has been made; what a broken cell leaves over stays there as raw Lumen. Storages filtered against
## Lumen or without room for a whole cell's Lumen are skipped (a full storehouse would lose most of the cell).
## UpkeepSystem pays a day's upkeep with this; the Dimming's light draw does the same itself (DimmingSystem).
## Returns the raw Lumen made.
static func draw_cells_as_lumen(s: Settlement, amount: float) -> float:
	var pd := s.registry.planet
	if amount <= Inventory.EPS or pd == null or pd.lumen_per_cell <= 0.0:
		return 0.0
	var per := pd.lumen_per_cell
	var made := 0.0
	var ids: Array = s.buildings.keys()
	ids.sort()
	for id in ids:
		if made >= amount - Inventory.EPS:
			break
		var inv: Inventory = (s.buildings[id] as Building).inventory
		if inv == null or not inv.accepts(LEAK_GOOD):
			continue
		while made < amount - Inventory.EPS and inv.amount_of(CELL_GOOD) >= 1.0 - Inventory.EPS:
			# A total-cap store frees one unit when the cell leaves; a per-good store keeps its Lumen slot open.
			var room := inv.free_for(LEAK_GOOD) + (1.0 if inv.mode == "total" else 0.0)
			if room + Inventory.EPS < per:
				break
			inv.remove(CELL_GOOD, 1.0)
			var put := inv.add(LEAK_GOOD, per)
			if put <= Inventory.EPS:
				inv.add(CELL_GOOD, 1.0)  # nowhere to put the Lumen: put the cell back
				break
			made += put
	return made
