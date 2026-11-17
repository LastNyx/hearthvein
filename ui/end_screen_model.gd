class_name EndScreenModel
extends RefCounted
## View-model of the end screens (ticket 45d, design.md sections 18 and 20): maps a campaign outcome ("won", "no_win",
## "lost", see CampaignSystem) and the settlement to {title, body, buttons}. Buttons are {id, text}; the ids are
## "continue", "save_quit", "load", "quit". Plain data, no nodes.

static func build(outcome: String, s: Settlement) -> Dictionary:
	var pop := s.citizens.size()
	var health := roundi(s.planet_health())
	var when := "Year %d, %s, day %d" % [s.clock.year(), s.clock.season_name().capitalize(), s.clock.day()]
	match outcome:
		"won":
			return {"title": "The Skyheart held",
					"body": "%s. The Great Dimming has passed. %d citizens live under the light, and the planet stands at %d%% health.\nThe world goes on, and so can you." % [when, pop, health],
					"buttons": [{"id": "continue", "text": "Continue"}, {"id": "save_quit", "text": "Save and quit"}]}
		"no_win":
			var need := roundi(s.registry.planet.win_health)
			return {"title": "The light held, the land did not",
					"body": "%d citizens survived the Great Dimming, but the planet health of %d%% is below %d%%. There is no victory this run.\nPlay goes on." % [pop, health, need],
					"buttons": [{"id": "continue", "text": "Continue"}]}
		"lost":
			return {"title": "The hearth went cold",
					"body": "No citizens remain. %s." % when,
					"buttons": [{"id": "load", "text": "Load a save"}, {"id": "quit", "text": "Quit"}]}
	return {}
