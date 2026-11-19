extends GutTest
## Ticket 90: moving water and chimney smoke.

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func test_water_layers_carry_a_time_driven_shader() -> void:
	var s := Settlement.new_game(42, reg)
	var v := MapView.new()
	add_child_autofree(v)
	v.setup(s.map)
	for name in ["Base", "Shore"]:
		var layer := v.get_node(name) as TileMapLayer
		var m := layer.material as ShaderMaterial
		assert_not_null(m, "%s has a shader material" % name)
		assert_true(m.shader.code.contains("TIME"), "%s shader reads TIME" % name)
	assert_null(v.bridges.material, "bridge decks are not tinted by the water shader")
	assert_null(v.roads.material)


func test_smoke_sprite_uses_the_smoke_shader_and_glows_stay_static() -> void:
	var smoky := 0
	var glow_only := 0
	for id in ArtLibrary.manifest()["buildings"]:
		var e: Dictionary = ArtLibrary.building_entry(id)
		var sm := ArtLibrary.smoke_sprite(e)
		if sm != null:
			smoky += 1
			assert_true((sm.material as ShaderMaterial).shader.code.contains("TIME"), id)
			assert_true(FileAccess.file_exists("res://assets/" + str(e["smoke"]["file"])), id)
			sm.free()
		var f := ArtLibrary.fx_sprite(e)
		if f != null:
			assert_null(f.material, "%s glow has no shader" % id)
			f.free()
			if sm == null:
				glow_only += 1
	assert_gt(smoky, 10, "chimney buildings have smoke")
	assert_gt(glow_only, 0, "some buildings are glow only")


func test_smoke_is_shown_only_while_the_building_works() -> void:
	var s := Settlement.new_game(42, reg)
	var v := MapView.new()
	add_child_autofree(v)
	v.setup(s.map)
	var pv := PlacementView.new()
	add_child_autofree(pv)
	pv.setup(s, v)
	var h := s.hearth
	assert_true(pv._smoke.has(h.id), "the Hearth has a chimney")
	pv.refresh_smoke()
	assert_true((pv._smoke[h.id] as Sprite2D).visible, "the Hearth burns")
	h.paused = true
	pv.refresh_smoke()
	assert_false((pv._smoke[h.id] as Sprite2D).visible, "a paused building has no smoke")
	h.paused = false
	# A workshop-type building: smoke only while a worker is at work.
	var b := Building.new()
	b.def = reg.get_building("sawmill")
	b.id = 9999
	assert_gt(b.def.worker_slots, 0)
	assert_false(pv.smoke_active(b, {}, {}), "nobody at work, no smoke")
	assert_true(pv.smoke_active(b, {9999: 1}, {}), "a worker at work lights it")
	b.site = true
	assert_false(pv.smoke_active(b, {9999: 1}, {}), "a construction site never smokes")
