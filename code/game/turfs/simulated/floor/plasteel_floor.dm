/turf/simulated/floor/plasteel
	icon_state = "floor"
	floor_tile = /obj/item/stack/tile/plasteel

/turf/simulated/floor/plasteel/update_icon_state()
	if(!broken && !burnt)
		icon_state = icon_regular_floor

/turf/simulated/floor/plasteel/get_broken_states()
	return list("damaged1", "damaged2", "damaged3", "damaged4", "damaged5")

/turf/simulated/floor/plasteel/pressure_debug

/turf/simulated/floor/plasteel/pressure_debug/airless
	name = "airless floor"
	oxygen = 0
	nitrogen = 0
	temperature = TCMB

/turf/simulated/floor/plasteel/pressure_debug/Initialize(mapload)
	..()
	addtimer(CALLBACK(src, PROC_REF(update_color)), 1, TIMER_LOOP)

/turf/simulated/floor/plasteel/pressure_debug/proc/update_color()
	var/datum/gas_mixture/air = get_readonly_air()
	var/ratio = min(1, air.return_pressure() / ONE_ATMOSPHERE)
	color = rgb(255 * (1 - ratio), 0, 255 * ratio)

/turf/simulated/floor/plasteel/airless
	name = "airless floor"
	oxygen = 0
	nitrogen = 0
	temperature = TCMB
	smoothing_groups = list(SMOOTH_GROUP_TURF, SMOOTH_GROUP_LATTICE)

/turf/simulated/floor/plasteel/lavaland_air
	oxygen = LAVALAND_OXYGEN
	nitrogen = LAVALAND_NITROGEN
	temperature = LAVALAND_TEMPERATURE
	atmos_mode = ATMOS_MODE_EXPOSED_TO_ENVIRONMENT
	atmos_environment = ENVIRONMENT_LAVALAND

/turf/simulated/floor/plasteel/airless/Initialize(mapload)
	. = ..()
	name = "floor"

/// For bomb testing range
/turf/simulated/floor/plasteel/airless/indestructible

/turf/simulated/floor/plasteel/airless/indestructible/ex_act(severity)
	return

/turf/simulated/floor/plasteel/goonplaque
	name = "Commemorative Plaque"
	desc = "\"This is a plaque in honour of our comrades on the G4407 Stations. Hopefully TG4407 model can live up to your fame and fortune.\" Scratched in beneath that is a crude image of a meteor and a spaceman. The spaceman is laughing. The meteor is exploding."
	icon_state = "plaque"

/turf/simulated/floor/plasteel/goonplaque/memorial
	name = "Memorial Plaque"
	desc = "\"This is a plaque in honour of those who died in the great space lube airlock incident.\" Scratched in beneath that is a crude image of a clown and a spaceman. The spaceman is slipping. The clown is laughing."

/turf/simulated/floor/plasteel/goonplaque/commission
	name = "Commission Plaque"
	desc = "Epsilon Eridani Sector - 'Meta' Class Outpost - Commissioned 11/03/2557 - NSS Cerebron."

/turf/simulated/floor/plasteel/goonplaque/nosey
	name = "Nosey little bastard aren't you?"
	desc = "Nosey little bastard aren't you?"

/turf/simulated/floor/plasteel/goonplaque/violence
	name = "Violence Free Area"
	desc = "Violence Free Area."

/turf/simulated/floor/plasteel/goonplaque/cerestation
	name = "Farragus Commission Plaque"
	desc = "\"AMS Farragus, Commissioned on 13 April 2472 by the Althland Mining Company. Acquired and recommissioned as NSS Farragus by Nanotrasen on 3 January 2485.\"<br><br>\
	Scratched in beneath is a crude image of a mime and a security officer. The security officer is hitting an invisible wall with a baton. The mime is silently laughing."

//TODO: Make subtypes for all normal turf icons
/turf/simulated/floor/plasteel/white
	icon_state = "white"
/turf/simulated/floor/plasteel/white/side
	icon_state = "whitehall"
/turf/simulated/floor/plasteel/white/corner
	icon_state = "whitecorner"

/turf/simulated/floor/plasteel/dark
	icon_state = "darkfull"

/turf/simulated/floor/plasteel/dark/telecomms
	nitrogen = 100
	oxygen = 0
	temperature = 80

/turf/simulated/floor/plasteel/dark/nitrogen
	nitrogen = 100
	oxygen = 0

/turf/simulated/floor/plasteel/freezer
	icon_state = "freezerfloor"

/turf/simulated/floor/plasteel/stairs
	icon_state = "stairs"

/turf/simulated/floor/plasteel/stairs/left
	icon_state = "stairs-l"

/turf/simulated/floor/plasteel/stairs/medium
	icon_state = "stairs-m"

/turf/simulated/floor/plasteel/stairs/right
	icon_state = "stairs-r"

/turf/simulated/floor/plasteel/grimy
	icon_state = "grimy"
