class_name MilestonePanelModel
extends RefCounted
## Rows for the Milestones panel on the pause screen (ticket 46c). No scene tree. Every milestone in data order for two
## sections: "run" (earned this run, with the in-game date; an old save may lack the date) and "lifetime" (the
## user://milestones.json entries). Row: {id, name, done, date, bonus}. Counts leave the bonus out of "x / y".


## {"run": section, "lifetime": section}; section = {rows, done, total, bonus_done, header}.
static func build(reg: DataRegistry, ms: MilestoneSystem, lifetime: Dictionary) -> Dictionary:
	var run_rows: Array[Dictionary] = []
	var life_rows: Array[Dictionary] = []
	for m in reg.milestones_in_order():
		var run_done := ms != null and ms.has(m.id)
		run_rows.append({"id": m.id, "name": m.display_name, "done": run_done,
				"date": ms.date_of(m.id) if run_done else "", "bonus": m.bonus})
		var entry: Variant = lifetime.get(m.id)
		var life_done := entry is Dictionary
		life_rows.append({"id": m.id, "name": m.display_name, "done": life_done,
				"date": str((entry as Dictionary).get("date", "")) if life_done else "", "bonus": m.bonus})
	return {"run": _section("This run", run_rows), "lifetime": _section("Lifetime", life_rows)}


static func _section(title: String, rows: Array[Dictionary]) -> Dictionary:
	var done := 0
	var total := 0
	var bonus_done := false
	var has_bonus := false
	for r in rows:
		if r["bonus"]:
			has_bonus = true
			bonus_done = bonus_done or r["done"]
		else:
			total += 1
			if r["done"]:
				done += 1
	var header := "%s %d / %d" % [title, done, total]
	if has_bonus:
		header += " (+bonus)" if bonus_done else " (+bonus locked)"
	return {"rows": rows, "done": done, "total": total, "bonus_done": bonus_done, "header": header}


## Row text: "Name" and the right-hand "Year 2, Spring, Day 3" / "locked".
static func status_text(r: Dictionary) -> String:
	if not r["done"]:
		return "locked"
	return r["date"] if r["date"] != "" else "done"
