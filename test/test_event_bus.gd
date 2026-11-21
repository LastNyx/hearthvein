extends GutTest
## Ticket 157: the in-memory event log is trimmed like the saved one.


func test_the_log_stays_within_twice_the_saved_limit_and_keeps_the_newest() -> void:
	var bus := EventBus.new()
	for i in 5000:
		bus.emit("walker_arrived", {"n": i})
		assert_lte(bus.log.size(), EventBus.SAVED_LOG_LIMIT * 2, "never above 2 x the limit")
	assert_gte(bus.log.size(), EventBus.SAVED_LOG_LIMIT, "the saved tail is whole")
	assert_eq(bus.log.back()["data"]["n"], 4999, "the newest entry is kept")
	assert_eq(bus.log[bus.log.size() - EventBus.SAVED_LOG_LIMIT]["data"]["n"], 4999 - EventBus.SAVED_LOG_LIMIT + 1)
