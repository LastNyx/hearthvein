class_name UpkeepSystem
extends SimSystem
## Lumen upkeep (design.md sections 8 and 14; section 16 Town: "Lumen upkeep starts"). From the Town era on, every
## finished, unpaused building with BuildingDef.upkeep_lumen > 0 needs that much Lumen per day.
##
## Hauling brings the Lumen in like any other consumer good: HaulingSystem.input_need adds upkeep_lumen x
## LogisticsDef.input_buffer_days of "lumen" (two days of need), so the building gets an input buffer and haulers keep
## it filled. This system spends one day's upkeep at the day start, before production and the Market's gold hook read
## the flag.
##
## A building whose day's upkeep could not be met in full runs the day at LogisticsDef.unpaid_upkeep_factor (x0.5,
## design.md sections 8 and 14). ProductionSystem reads it through output_modifier; a building whose output is not a
## recipe (Market gold) applies the same modifier itself. A building placed since the last day check counts as paid,
## so it never starts at half output before its first payment.
##
## No Camp or Village row has an upkeep (design.md section 16, all "-"), and data/buildings/ has none, so nothing
## needs Lumen before Town. The Town gate is checked here rather than on the def's era so a debug-placed Town
## building still waits for the real era.

const SAVE_KEY := "upkeep"
## The era whose row starts Lumen upkeep (design.md section 16).
const TOWN_ERA := "town"

## building id -> whether the last day's upkeep was paid. Saved, so a load resumes with the same half-output days.
var _paid: Dictionary = {}


func save_state() -> Dictionary:
	return {"paid": SaveGame.pairs(_paid)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_paid = SaveGame.unpairs(d["paid"])


## True from the Town era on.
static func is_on(s: Settlement) -> bool:
	var cur := s.registry.get_era(s.era_id())
	var town := s.registry.get_era(TOWN_ERA)
	return cur != null and town != null and cur.order >= town.order


## Whether this building paid its last day's upkeep (true before its first check).
func is_paid(building_id: int) -> bool:
	return bool(_paid.get(building_id, true))


func on_day(s: Settlement) -> void:
	if not is_on(s):
		return
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.paused or b.def.upkeep_lumen <= 0.0:
			continue
		_paid[bid] = _pay(b)


## Takes one day's upkeep from the input buffer. Returns true when the full amount was there.
func _pay(b: Building) -> bool:
	var need := b.def.upkeep_lumen
	if need <= 0.0:
		return true
	var got := b.input_buffer.remove("lumen", need) if b.input_buffer != null else 0.0
	return got >= need - Inventory.EPS


## Factor for a building's output: 1.0 normally, LogisticsDef.unpaid_upkeep_factor (x0.5) while the last day's
## upkeep was not paid, and 1.0 before Town or with no upkeep. ProductionSystem.modifier and MarketSystem's gold
## hook both use it; the first line keeps every other building free of any lookup.
static func output_modifier(s: Settlement, b: Building) -> float:
	if b.def.upkeep_lumen <= 0.0 or not is_on(s):
		return 1.0
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	if us == null or us.is_paid(b.id):
		return 1.0
	var lg := s.registry.logistics
	return lg.unpaid_upkeep_factor if lg != null else 1.0
