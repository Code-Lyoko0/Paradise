/*	Note from Carnie:
		The way datum/mind stuff works has been changed a lot.
		Minds now represent IC characters rather than following a client around constantly.
	Guidelines for using minds properly:
	-	Never mind.transfer_to(ghost). The var/current and var/original of a mind must always be of type mob/living!
		ghost.mind is however used as a reference to the ghost's corpse
	-	When creating a new mob for an existing IC character (e.g. cloning a dead guy or borging a brain of a human)
		the existing mind of the old mob should be transfered to the new mob like so:
			mind.transfer_to(new_mob)
	-	You must not assign key= or ckey= after transfer_to() since the transfer_to transfers the client for you.
		By setting key or ckey explicitly after transfering the mind with transfer_to you will cause bugs like DCing
		the player.
	-	IMPORTANT NOTE 2, if you want a player to become a ghost, use mob.ghostize() It does all the hard work for you.
	-	When creating a new mob which will be a new IC character (e.g. putting a shade in a construct or randomly selecting
		a ghost to become a xeno during an event). Simply assign the key or ckey like you've always done.
			new_mob.key = key
		The Login proc will handle making a new mob for that mobtype (including setting up stuff like mind.name). Simple!
		However if you want that mind to have any special properties like being a traitor etc you will have to do that
		yourself.
*/

/datum/mind
	var/key
	var/name				//replaces mob/var/original_name
	var/mob/living/current
	/// The original mob's UID. Used for example to see if a silicon with antag status is actually malf. Or just an antag put in a borg
	var/original_mob_UID
	/// The original mob's name. Used in Dchat messages
	var/original_mob_name
	var/active = FALSE

	var/memory

	var/assigned_role //assigned role is what job you're assigned to when you join the station.
	var/playtime_role //if set, overrides your assigned_role for the purpose of playtime awards. Set by IDcomputer when your ID is changed.
	var/special_role //special roles are typically reserved for antags or roles like ERT. If you want to avoid a character being automatically announced by the AI, on arrival (becuase they're an off station character or something); ensure that special_role and assigned_role are equal.
	var/offstation_role = FALSE //set to true for ERT, deathsquad, abductors, etc, that can go from and to CC at will and shouldn't be antag targets
	var/list/restricted_roles = list()

	var/list/spell_list = list() // Wizard mode & "Give Spell" badmin button.
	var/datum/martial_art/martial_art
	var/list/known_martial_arts = list()

	var/role_alt_title

	var/datum/objective_holder/objective_holder
	///a list of objectives that a player with this job could complete for space credit rewards
	var/list/job_objectives = list()
	var/list/datum/objective/special_verbs = list()
	var/list/targets = list()

	/// Tracks if this mind has been a rev or not
	var/has_been_rev = FALSE

	var/miming = 0 // Mime's vow of silence
	/// A list of all the antagonist datums that the player is (does not include undatumized antags)
	var/list/antag_datums
	/// A lazy list of all teams the player is part of but doesnt have an antag role for, (i.e. a custom admin team)
	var/list/teams

	var/antag_hud_icon_state = null //this mind's ANTAG_HUD should have this icon_state
	var/datum/atom_hud/antag/antag_hud = null //this mind's antag HUD
	var/datum/mindslaves/som //stands for slave or master...hush..

	var/isblessed = FALSE // is this person blessed by a chaplain?
	var/num_blessed = 0 // for prayers

	var/suicided = FALSE

	//put this here for easier tracking ingame
	var/datum/money_account/initial_account

	//zealot_master is a reference to the mob that converted them into a zealot (for ease of investigation and such)
	var/mob/living/carbon/human/zealot_master = null

	var/list/learned_recipes //List of learned recipe TYPES.

	/// List of people who we've received kudos from.
	var/list/kudos_received_from = list()

/datum/mind/New(new_key)
	key = new_key
	objective_holder = new(src)

/datum/mind/Destroy()
	SSticker.minds -= src
	remove_all_antag_datums()
	qdel(objective_holder)
	current = null
	kudos_received_from.Cut()
	return ..()

/datum/mind/proc/set_original_mob(mob/original)
	original_mob_name = original.real_name
	original_mob_UID = original.UID()

/datum/mind/proc/is_original_mob(mob/M)
	return original_mob_UID == M.UID()

// Do not use for admin related things as this can hide the mob's ckey
/datum/mind/proc/get_display_key()
	// Lets try find a client so we can check their prefs
	var/client/C = null

	var/cannonical_key = ckey(key)

	if(current?.client)
		// Active client
		C = current.client
	else if(cannonical_key in GLOB.directory)
		// Do a directory lookup on the last ckey this mind had
		// If theyre online we can grab them still and check prefs
		C = GLOB.directory[cannonical_key]

	// Ok we found a client, be it their active or their last
	// Now we see if we need to respect their privacy
	var/out_ckey
	if(C)
		if(C.prefs.toggles2 & PREFTOGGLE_2_ANON)
			out_ckey = "(Anon)"
		else
			out_ckey = C.ckey
	else
		// No client. Just mark as DC'd.
		out_ckey = "(Disconnected)"

	return out_ckey

/datum/mind/proc/transfer_to(mob/living/new_character)
	var/datum/atom_hud/antag/hud_to_transfer = antag_hud //we need this because leave_hud() will clear this list
	var/mob/living/old_current = current
	if(!istype(new_character))
		stack_trace("transfer_to(): Some idiot has tried to transfer_to() a non mob/living mob.")
	if(current)					//remove ourself from our old body's mind variable
		current.mind = null
		if(isliving(current))
			current.med_hud_set_status()
		leave_all_huds() //leave all the huds in the old body, so it won't get huds if somebody else enters it

		SStgui.on_transfer(current, new_character)

		new_character.job = current.job //transfer our job over to the new body

	if(new_character.mind)		//remove any mind currently in our new body's mind variable
		new_character.mind.current = null

	current = new_character		//link ourself to our new body
	new_character.mind = src	//and link our new body to ourself
	for(var/a in antag_datums)	//Makes sure all antag datums effects are applied in the new body
		var/datum/antagonist/A = a
		A.on_body_transfer(old_current, current)
	transfer_antag_huds(hud_to_transfer)				//inherit the antag HUD
	transfer_actions(new_character)
	if(martial_art)
		for(var/datum/martial_art/MA in known_martial_arts)
			MA.reset_combos(old_current) // Clear combos on old body
			if(MA.temporary)
				MA.remove(current)
			else
				MA.remove(current)
				MA.teach(current)
	if(active)
		new_character.key = key		//now transfer the key to link the client to our new body
	SEND_SIGNAL(src, COMSIG_MIND_TRANSER_TO, new_character)
	SEND_SIGNAL(new_character, COMSIG_BODY_TRANSFER_TO)
	if(ishuman(new_character))
		var/mob/living/carbon/human/H = new_character
		if(H.mind in SSticker.mode.syndicates)
			SSticker.mode.update_synd_icons_added(H.mind)

/datum/mind/proc/store_memory(new_text)
	memory += "[new_text]<br>"

/datum/mind/proc/wipe_memory()
	memory = null

/datum/mind/proc/show_memory(mob/recipient, window = 1)
	if(!recipient)
		recipient = current
	var/list/output = list()
	output.Add("<!DOCTYPE html><meta charset='UTF-8'><b>[current.real_name]'s Memories:</b><hr>")
	output.Add(memory)

	for(var/datum/antagonist/A in antag_datums)
		output.Add(A.antag_memory)

	if(has_objectives())
		output.Add("<HR><B>Objectives:</B>")
		output.Add(gen_objective_text())

	if(LAZYLEN(job_objectives))
		output.Add("<HR><B>Job Objectives:</B><UL>")

		var/obj_count = 1
		for(var/datum/job_objective/objective in job_objectives)
			output.Add("<LI><B>Task #[obj_count]</B>: [objective.description]</LI>")
			obj_count++
		output.Add("</UL>")

	output = output.Join("<br>")
	if(window)
		recipient << browse(output, "window=memory")
	else
		to_chat(recipient, "<i>[output]</i>")

/datum/mind/proc/gen_objective_text(admin = FALSE)
	if(!has_objectives())
		return "<b>No Objectives.</b><br>"

	var/list/text = list()
	var/obj_count = 1
	// If they don't have any objectives, "" will be returned.
	for(var/datum/objective/objective in get_all_objectives())
		text.Add("<b>Objective #[obj_count++]</b>: [objective.explanation_text][admin ? get_admin_objective_edit(objective) : ""]")

	return text.Join("<br>")

/datum/mind/proc/get_admin_objective_edit(datum/objective/objective)
	return " <a href='byond://?src=[UID()];obj_edit=\ref[objective]'>Edit</a> \
			<a href='byond://?src=[UID()];obj_delete=\ref[objective]'>Delete</a> \
			<a href='byond://?src=[UID()];obj_completed=\ref[objective]'>\
			<font color=[objective.completed ? "green" : "red"]>Toggle Completion</font></a>"

/**
 * A quicker version of get_all_objectives() but only for seeing if they have any objectives at all
 */
/datum/mind/proc/has_objectives(include_team = TRUE)
	if(objective_holder.has_objectives())
		return TRUE
	for(var/datum/antagonist/A as anything in antag_datums)
		if(A.has_antag_objectives(include_team)) // this checks teams also
			return TRUE
	// For custom non-antag role teams
	if(include_team && LAZYLEN(teams))
		for(var/datum/team/team as anything in teams)
			if(team.objective_holder.has_objectives())
				return TRUE
	return FALSE

/**
 * Gets every objective this mind owns, including all of those from any antag datums and teams they have, and returns them as a list.
 */
/datum/mind/proc/get_all_objectives(include_team = TRUE)
	var/list/all_objectives = list()

	all_objectives += objective_holder.get_objectives() // Get their personal objectives

	for(var/datum/antagonist/A as anything in antag_datums)
		all_objectives += A.get_antag_objectives(include_team) // Add all antag datum objectives, and possibly antag team objectives

	// For custom non-antag role teams
	if(include_team && LAZYLEN(teams))
		for(var/datum/team/team as anything in teams)
			all_objectives += team.objective_holder.get_objectives()

	return all_objectives

/**
 * Add an objective to the mind
 */
/datum/mind/proc/add_mind_objective(datum/objective/O, _explanation_text, mob/target_override)
	if(ispath(O))
		O = new O()
	if(O.owner)
		stack_trace("[O], [O.type] was assigned as an objective to [src] (mind), but already had an owner: [O.owner] (mind). Overriding.")
	O.owner = src
	return objective_holder.add_objective(O, _explanation_text, target_override)

/**
 * Completely remove the given objective from the mind, and include antagdatums/teams if remove_from_everything is true
 */
/datum/mind/proc/remove_mind_objective(datum/objective/O, remove_from_everything)
	. = objective_holder.remove_objective(O)

	if(!remove_from_everything)
		return
	for(var/datum/antagonist/A as anything in antag_datums)
		A.remove_antag_objective(O)
		var/datum/team/team = A.get_team()
		team?.objective_holder.remove_objective(O)

/datum/mind/proc/_memory_edit_header(gamemode, list/alt)
	. = gamemode
	if(SSticker.mode.config_tag == gamemode || (LAZYLEN(alt) && (SSticker.mode.config_tag in alt)))
		. = uppertext(.)
	. = "<i><b>[.]</b></i>: "

/datum/mind/proc/_memory_edit_role_enabled(role)
	. = "|Disabled in Prefs"
	if(current && current.client && (role in current.client.prefs.be_special))
		. = "|Enabled in Prefs"

/datum/mind/proc/memory_edit_implant(mob/living/carbon/human/H)
	if(ismindshielded(H))
		. = "Mindshield Bio-chip:<a href='byond://?src=[UID()];implant=remove'>Remove</a>|<b><font color='green'>Implanted</font></b></br>"
	else
		. = "Mindshield Bio-chip:<b>No Bio-chip</b>|<a href='byond://?src=[UID()];implant=add'>Bio-chip [H.p_them()]!</a></br>"


/datum/mind/proc/memory_edit_revolution(mob/living/carbon/human/H)
	. = _memory_edit_header("revolution")
	var/datum/antagonist/rev = has_antag_datum(/datum/antagonist/rev)
	if(ismindshielded(H))
		. += "<b>NO</b>|headrev|rev"
	else if(istype(rev, /datum/antagonist/rev/head))
		. += "<a href='byond://?src=[UID()];revolution=clear'>no</a>|<b><font color='red'>HEADREV</font></b>|<a href='byond://?src=[UID()];revolution=rev'>rev</a>"
		. += "<br>Flash: <a href='byond://?src=[UID()];revolution=flash'>give</a>"

		var/list/L = current.get_contents()
		var/obj/item/flash/flash = locate() in L
		if(flash)
			if(!flash.broken)
				. += "|<a href='byond://?src=[UID()];revolution=takeflash'>take</a>."
			else
				. += "|<a href='byond://?src=[UID()];revolution=takeflash'>take</a>|<a href='byond://?src=[UID()];revolution=repairflash'>repair</a>."
		else
			. += "."

		. += " <a href='byond://?src=[UID()];revolution=reequip'>Reequip</a> (gives flash/cham sec hud)."
		if(!rev.has_antag_objectives()) // if theres anything missing here, we want it to runtime. There should never be a rev without a rev team
			. += "<br>Objectives are empty! Unless theres no command, this is likely a bug, please report it! <a href='byond://?src=[UID()];revolution=autoobjectives'>Set to kill all heads</a>."
	else if(rev)
		. += "<a href='byond://?src=[UID()];revolution=clear'>no</a>|<a href='byond://?src=[UID()];revolution=headrev'>headrev</a>|<b><font color='red'>REV</font></b>"
	else
		. += "<b>NO</b>|<a href='byond://?src=[UID()];revolution=headrev'>headrev</a>|<a href='byond://?src=[UID()];revolution=rev'>rev</a>"

	. += _memory_edit_role_enabled(ROLE_REV)

/datum/mind/proc/memory_edit_cult(mob/living/carbon/human/H)
	. = _memory_edit_header("cult")
	if(has_antag_datum(/datum/antagonist/cultist))
		. += "<a href='byond://?src=[UID()];cult=clear'>no</a>|<b><font color='red'>CULTIST</font></b>"
		. += "<br>Give <a href='byond://?src=[UID()];cult=dagger'>dagger</a>|<a href='byond://?src=[UID()];cult=runedmetal'>runedmetal</a>."
	else
		. += "<b>NO</b>|<a href='byond://?src=[UID()];cult=cultist'>cultist</a>"

	. += _memory_edit_role_enabled(ROLE_CULTIST)

/datum/mind/proc/memory_edit_wizard(mob/living/carbon/human/H)
	. = _memory_edit_header("wizard")
	if(has_antag_datum(/datum/antagonist/wizard))
		. += "<b><font color='red'>WIZARD</font></b>|<a href='byond://?src=[UID()];wizard=clear'>no</a>"
		. += "<br><a href='byond://?src=[UID()];wizard=lair'>To lair</a>, <a href='byond://?src=[UID()];common=undress'>undress</a>, <a href='byond://?src=[UID()];wizard=dressup'>dress up</a>, <a href='byond://?src=[UID()];wizard=name'>let choose name</a>."
	else
		. += "<a href='byond://?src=[UID()];wizard=wizard'>wizard</a>|<b>NO</b>"

	. += _memory_edit_role_enabled(ROLE_WIZARD)

/datum/mind/proc/memory_edit_changeling(mob/living/carbon/human/H)
	. = _memory_edit_header("changeling", list("traitorchan"))
	var/datum/antagonist/changeling/cling = has_antag_datum(/datum/antagonist/changeling)
	if(cling)
		. += "<b><font color='red'>CHANGELING</font></b>|<a href='byond://?src=[UID()];changeling=clear'>no</a>"
		if(!cling.has_antag_objectives())
			. += "<br>Objectives are empty! <a href='byond://?src=[UID()];changeling=autoobjectives'>Randomize!</a>"
		if(length(cling.absorbed_dna))
			var/datum/dna/DNA = cling.absorbed_dna[1]
			if(current.real_name != DNA.real_name)
				. += "<br><a href='byond://?src=[UID()];changeling=initialdna'>Transform to initial appearance.</a>"
	else
		. += "<a href='byond://?src=[UID()];changeling=changeling'>changeling</a>|<b>NO</b>"

	. += _memory_edit_role_enabled(ROLE_CHANGELING)

/datum/mind/proc/memory_edit_vampire(mob/living/carbon/human/H)
	. = _memory_edit_header("vampire", list("traitorvamp"))
	var/datum/antagonist/vampire/vamp = has_antag_datum(/datum/antagonist/vampire)
	if(vamp)
		. += "<b><font color='red'>VAMPIRE</font></b>|<a href='byond://?src=[UID()];vampire=clear'>no</a>"
		. += "<br>Usable blood: <a href='byond://?src=[UID()];vampire=edit_usable_blood'>[vamp.bloodusable]</a>"
		. += " | Total blood: <a href='byond://?src=[UID()];vampire=edit_total_blood'>[vamp.bloodtotal]</a>"
		var/has_subclass = !QDELETED(vamp.subclass)
		. += "<br>Subclass: <a href='byond://?src=[UID()];vampire=change_subclass'>[has_subclass ? capitalize(vamp.subclass.name) : "None"]</a>"
		if(has_subclass)
			. += " | Force full power: <a href='byond://?src=[UID()];vampire=full_power_override'>[vamp.subclass.full_power_override ? "Yes" : "No"]</a>"
		if(!vamp.has_antag_objectives())
			. += "<br>Objectives are empty! <a href='byond://?src=[UID()];vampire=autoobjectives'>Randomize!</a>"
	else
		. += "<a href='byond://?src=[UID()];vampire=vampire'>vampire</a>|<b>NO</b>"

	. += _memory_edit_role_enabled(ROLE_VAMPIRE)
	/** Enthralled ***/
	. += "<br><b><i>enthralled</i></b>: "
	if(has_antag_datum(/datum/antagonist/mindslave/thrall))
		. += "<b><font color='red'>THRALL</font></b>|<a href='byond://?src=[UID()];vampthrall=clear'>no</a>"
	else
		. += "thrall|<b>NO</b>"

/datum/mind/proc/memory_edit_mind_flayer(mob/living/carbon/human/H)
	. = _memory_edit_header("mind_flayer")
	var/datum/antagonist/mindflayer/flayer = has_antag_datum(/datum/antagonist/mindflayer)
	if(flayer)
		. += "<b><font color='red'>MINDFLAYER</font></b>|<a href='byond://?src=[UID()];mind_flayer=clear'>no</a>"
		. += " | Usable swarms: <a href='byond://?src=[UID()];mind_flayer=edit_total_swarms'>[flayer.usable_swarms]</a>"
		. += " | Total swarms gathered: [flayer.total_swarms_gathered]"
		. += " | List of purchased powers: [json_encode(flayer.powers)]"
		if(!flayer.has_antag_objectives())
			. += "<br>Objectives are empty! <a href='byond://?src=[UID()];mind_flayer=autoobjectives'>Randomize!</a>"
	else
		. += "<a href='byond://?src=[UID()];mind_flayer=mind_flayer'>mind_flayer</a>|<b>NO</b>"

	. += _memory_edit_role_enabled(ROLE_MIND_FLAYER)

/datum/mind/proc/memory_edit_nuclear(mob/living/carbon/human/H)
	. = _memory_edit_header("nuclear")
	if(src in SSticker.mode.syndicates)
		. += "<b><font color='red'>OPERATIVE</b></font>|<a href='byond://?src=[UID()];nuclear=clear'>no</a>"
		. += "<br><a href='byond://?src=[UID()];nuclear=lair'>To shuttle</a>, <a href='byond://?src=[UID()];common=undress'>undress</a>, <a href='byond://?src=[UID()];nuclear=dressup'>dress up</a>."
		var/code
		for(var/obj/machinery/nuclearbomb/bombue in SSmachines.get_by_type(/obj/machinery/nuclearbomb))
			if(length(bombue.r_code) <= 5 && bombue.r_code != "LOLNO" && bombue.r_code != "ADMIN")
				code = bombue.r_code
				break
		if(code)
			. += " Code is [code]. <a href='byond://?src=[UID()];nuclear=tellcode'>tell the code.</a>"
	else
		. += "<a href='byond://?src=[UID()];nuclear=nuclear'>operative</a>|<b>NO</b>"

	. += _memory_edit_role_enabled(ROLE_OPERATIVE)

/datum/mind/proc/memory_edit_abductor(mob/living/carbon/human/H)
	. = _memory_edit_header("abductor")
	if(has_antag_datum(/datum/antagonist/abductor))
		. += "<b><font color='red'>ABDUCTOR</font></b>|<a href='byond://?src=[UID()];abductor=clear'>no</a>"
	else
		. += "<a href='byond://?src=[UID()];abductor=abductor'>abductor</a>|<b>NO</b>"

	. += _memory_edit_role_enabled(ROLE_ABDUCTOR)

/datum/mind/proc/memory_edit_zombie(mob/living/H)
	. = _memory_edit_header("zombie", list())
	if(has_antag_datum(/datum/antagonist/zombie))
		. += "<a href='byond://?src=[UID()];zombie=clear'>no</a>|<b><font color='red'>ZOMBIE</font></b>"
		return
	if(current.HasDisease(/datum/disease/zombie))
		. += "<b>NO</b>|<a href='byond://?src=[UID()];zombie=zombie'>zombie</a>|<a href='byond://?src=[UID()];zombie=zombievirusno'><font color='red'>dis-infect</font></a>"
	else
		. += "<b>NO</b>|<a href='byond://?src=[UID()];zombie=zombie'>zombie</a>|<a href='byond://?src=[UID()];zombie=zombievirus'>infect</a>"

/datum/mind/proc/memory_edit_eventmisc(mob/living/H)
	. = _memory_edit_header("event", list())
	if(has_antag_datum(/datum/antagonist/eventmisc))
		. += "<b>YES</b>|<a href='byond://?src=[UID()];eventmisc=clear'>no</a>"
	else
		. += "<a href='byond://?src=[UID()];eventmisc=eventmisc'>Event Role</a>|<b>NO</b>"

/datum/mind/proc/memory_edit_traitor()
	. = _memory_edit_header("traitor", list("traitorchan", "traitorvamp"))
	if(has_antag_datum(/datum/antagonist/traitor))
		. += "<b><font color='red'>TRAITOR</font></b>|<a href='byond://?src=[UID()];traitor=clear'>no</a>"
		var/datum/antagonist/traitor/T = has_antag_datum(/datum/antagonist/traitor)
		if(!T.has_antag_objectives())
			. += "<br>Objectives are empty! <a href='byond://?src=[UID()];traitor=autoobjectives'>Randomize!</a>"
	else
		. += "<a href='byond://?src=[UID()];traitor=traitor'>traitor</a>|<b>NO</b>"

	. += _memory_edit_role_enabled(ROLE_TRAITOR)
	// Contractor
	. += "<br><b><i>contractor</i></b>: "
	var/datum/contractor_hub/H = LAZYACCESS(GLOB.contractors, src)
	if(H)
		. += "<b><font color='red'>CONTRACTOR</font></b>"
		// List all their contracts
		. += "<br><b>Contracts:</b>"
		if(H.contracts)
			var/count = 1
			for(var/co in H.contracts)
				var/datum/syndicate_contract/CO = co
				. += "<br><B>Contract #[count++]</B>: "
				. += "<a href='byond://?src=[UID()];cuid=[CO.UID()];contractor=target'><b>[CO.contract.target?.name || "Invalid target!"]</b></a>|"
				. += "<a href='byond://?src=[UID()];cuid=[CO.UID()];contractor=locations'>locations</a>|"
				. += "<a href='byond://?src=[UID()];cuid=[CO.UID()];contractor=other'>more</a>|"
				switch(CO.status)
					if(CONTRACT_STATUS_INVALID)
						. += "<b>INVALID</b>"
					if(CONTRACT_STATUS_INACTIVE)
						. += "inactive"
					if(CONTRACT_STATUS_ACTIVE)
						. += "<b><font color='orange'>ACTIVE</font></b>|"
						. += "<a href='byond://?src=[UID()];cuid=[CO.UID()];contractor=interrupt'>interrupt</a>|"
						. += "<a href='byond://?src=[UID()];cuid=[CO.UID()];contractor=fail'>fail</a>"
					if(CONTRACT_STATUS_COMPLETED)
						. += "<font color='green'>COMPLETED</font>"
					if(CONTRACT_STATUS_FAILED)
						. += "<font color='red'>FAILED</font>"
			. += "<br>"
			. += "<a href='byond://?src=[UID()];contractor=add'>Add Contract</a><br>"
			. += "Claimable TC: <a href='byond://?src=[UID()];contractor=tc'>[H.reward_tc_available]</a><br>"
			. += "Available Rep: <a href='byond://?src=[UID()];contractor=rep'>[H.rep]</a><br>"
		else
			. += "<br>"
			. += "<i>Has not logged in to contractor uplink</i>"
	else
		. += "<b>NO</b>"
	// Mindslave
	. += "<br><b><i>mindslaved</i></b>: "
	if(has_antag_datum(/datum/antagonist/mindslave, FALSE))
		. += "<b><font color='red'>MINDSLAVE</font></b>|<a href='byond://?src=[UID()];mindslave=clear'>no</a>"
	else
		. += "mindslave|<b>NO</b>"

/datum/mind/proc/memory_edit_silicon()
	. = "<i><b>Silicon</b></i>: "
	var/mob/living/silicon/robot/robot = current
	if(istype(robot) && robot.emagged)
		. += "<br>Cyborg: <b><font color='red'>Is emagged!</font></b> <a href='byond://?src=[UID()];silicon=unemag'>Unemag!</a><br>0th law: [robot.laws.zeroth_law]"
	var/mob/living/silicon/ai/ai = current
	if(istype(ai) && length(ai.connected_robots))
		var/n_e_robots = 0
		for(var/mob/living/silicon/robot/R in ai.connected_robots)
			if(R.emagged)
				n_e_robots++
		. += "<br>[n_e_robots] of [length(ai.connected_robots)] slaved cyborgs are emagged. <a href='byond://?src=[UID()];silicon=unemagcyborgs'>Unemag</a>"

/datum/mind/proc/memory_edit_uplink()
	. = ""
	if(ishuman(current) && ((has_antag_datum(/datum/antagonist/traitor)) || \
		(src in SSticker.mode.syndicates)))
		. = "Uplink: <a href='byond://?src=[UID()];common=uplink'>give</a>"
		var/obj/item/uplink/hidden/suplink = find_syndicate_uplink()
		var/crystals
		if(suplink)
			crystals = suplink.uses
		if(suplink)
			. += "|<a href='byond://?src=[UID()];common=takeuplink'>take</a>"
			if(usr.client.holder.rights & (R_SERVER|R_EVENT))
				. += ", <a href='byond://?src=[UID()];common=crystals'>[crystals]</a> crystals"
			else
				. += ", [crystals] crystals"
		. += "." //hiel grammar
		//         ^ whoever left this comment is literally a grammar nazi. stalin better. in russia grammar correct you.

/datum/mind/proc/edit_memory()
	if(SSticker.current_state < GAME_STATE_PLAYING)
		alert("Not before round-start!", "Alert")
		return

	var/list/out = list("<html><meta charset='UTF-8'><head><title>[name]</title></head><body><b>[name]</b>[(current && (current.real_name != name))?" (as [current.real_name])" : ""]")
	out.Add("Mind currently owned by key: [key] [active ? "(synced)" : "(not synced)"]")
	out.Add("Assigned role: [assigned_role]. <a href='byond://?src=[UID()];role_edit=1'>Edit</a>")
	out.Add("Factions and special roles:")

	var/list/sections = list(
		"implant",
		"revolution",
		"cult",
		"wizard",
		"changeling",
		"vampire", // "traitorvamp",
		"mind_flayer",
		"nuclear",
		"traitor", // "traitorchan",
	)
	var/mob/living/carbon/human/H = current
	if(ishuman(current))
		/** Impanted**/
		sections["implant"] = memory_edit_implant(H)
		/** REVOLUTION ***/
		sections["revolution"] = memory_edit_revolution(H)
		/** WIZARD ***/
		sections["wizard"] = memory_edit_wizard(H)
		/** CHANGELING ***/
		sections["changeling"] = memory_edit_changeling(H)
		/** VAMPIRE ***/
		sections["vampire"] = memory_edit_vampire(H)
		/** MINDFLAYER ***/
		sections["mind_flayer"] = memory_edit_mind_flayer(H)
		/** NUCLEAR ***/
		sections["nuclear"] = memory_edit_nuclear(H)
		/** Abductors **/
		sections["abductor"] = memory_edit_abductor(H)
		/** Zombies **/
		sections["zombie"] = memory_edit_zombie(H)
	sections["eventmisc"] = memory_edit_eventmisc(H)
	/** TRAITOR ***/
	sections["traitor"] = memory_edit_traitor()
	if(!issilicon(current))
		/** CULT ***/
		sections["cult"] = memory_edit_cult(H)
	/** SILICON ***/
	if(issilicon(current))
		sections["silicon"] = memory_edit_silicon()
	/*
		This prioritizes antags relevant to the current round to make them appear at the top of the panel.
		Traitorchan and traitorvamp are snowflaked in because they have multiple sections.
	*/
	if(SSticker.mode.config_tag == "traitorchan")
		if(sections["traitor"])
			out.Add(sections["traitor"])
		if(sections["changeling"])
			out.Add(sections["changeling"])
		sections -= "traitor"
		sections -= "changeling"
	// Elif technically unnecessary but it makes the following else look better
	else if(SSticker.mode.config_tag == "traitorvamp")
		if(sections["traitor"])
			out.Add(sections["traitor"])
		if(sections["vampire"])
			out.Add(sections["vampire"])
		sections -= "traitor"
		sections -= "vampire"
	else
		if(sections[SSticker.mode.config_tag])
			out.Add(sections[SSticker.mode.config_tag])
		sections -= SSticker.mode.config_tag

	for(var/i in sections)
		if(sections[i])
			out.Add(sections[i])

	out.Add("<b>Organization:</b> ")
	for(var/datum/antagonist/D in antag_datums)
		if(D.organization)
			out.Add("[D.organization.name]")
	out.Add(memory_edit_uplink())
	out.Add("<b>Memory:</b>")
	out.Add(memory)
	out.Add("<a href='byond://?src=[UID()];memory_edit=1'>Edit memory</a><br>")
	out.Add("Objectives:")
	out.Add(gen_objective_text(admin = TRUE))
	out.Add("<a href='byond://?src=[UID()];obj_add=1'>Add objective</a><br>")
	out.Add("<a href='byond://?src=[UID()];obj_announce=1'>Announce objectives</a><br>")
	out.Add("</body></html>")
	usr << browse(out.Join("<br>"), "window=edit_memory[src];size=500x500")

/datum/mind/Topic(href, href_list)
	if(!check_rights(R_ADMIN))
		return

	if(href_list["role_edit"])
		var/new_role = input("Select new role", "Assigned role", assigned_role) as null|anything in GLOB.joblist
		if(!new_role)
			return
		assigned_role = new_role
		log_admin("[key_name(usr)] has changed [key_name(current)]'s assigned role to [assigned_role]")
		message_admins("[key_name_admin(usr)] has changed [key_name_admin(current)]'s assigned role to [assigned_role]")

	else if(href_list["memory_edit"])
		var/messageinput = input("Write new memory", "Memory", memory) as null|message
		if(isnull(messageinput))
			return
		var/new_memo = copytext(messageinput, 1,MAX_MESSAGE_LEN)
		var/confirmed = alert(usr, "Are you sure you want to edit their memory? It will wipe out their original memory!", "Edit Memory", "Yes", "No")
		if(confirmed == "Yes") // Because it is too easy to accidentally wipe someone's memory
			memory = new_memo
			log_admin("[key_name(usr)] has edited [key_name(current)]'s memory")
			message_admins("[key_name_admin(usr)] has edited [key_name_admin(current)]'s memory")

	else if(href_list["obj_edit"] || href_list["obj_add"])
		var/datum/objective/objective
		var/def_value

		if(href_list["obj_edit"])
			objective = locate(href_list["obj_edit"])
			if(!objective)
				return

			//Text strings are easy to manipulate. Revised for simplicity.
			var/temp_obj_type = "[objective.type]"//Convert path into a text string.
			def_value = copytext(temp_obj_type, 18)//Convert last part of path into an objective keyword.
			if(!def_value)//If it's a custom objective, it will be an empty string.
				def_value = "custom"

		var/new_obj_type = input("Select objective type:", "Objective type", def_value) as null|anything in	list(
			"assassinate", "assassinateonce", "blood", "debrain", "protect", "prevent", "hijack", "escape", "survive", "steal",
			"nuclear", "absorb", "destroy", "maroon", "identity theft", "custom")
		if(!new_obj_type)
			return

		var/datum/objective/new_objective = null

		switch(new_obj_type)
			if("assassinate", "assassinateonce", "protect","debrain", "maroon")
				var/list/possible_targets = list()
				var/list/possible_targets_random = list()
				for(var/datum/mind/possible_target in SSticker.minds)
					if((possible_target != src) && ishuman(possible_target.current))
						possible_targets += possible_target.current // Allows for admins to pick off station roles
						if(!is_invalid_target(possible_target))
							possible_targets_random += possible_target.current // For random picking, only valid targets

				var/mob/def_target = null
				var/objective_list[] = list(/datum/objective/assassinate, /datum/objective/assassinateonce, /datum/objective/protect, /datum/objective/debrain)
				if(objective&&(objective.type in objective_list) && objective:target)
					def_target = objective.target.current
				possible_targets = sortAtom(possible_targets)

				var/new_target
				if(length(possible_targets))
					if(alert(usr, "Do you want to pick the objective yourself? No will randomise it", "Pick objective", "Yes", "No") == "Yes")
						possible_targets += "Free objective"
						new_target = input("Select target:", "Objective target", def_target) as null|anything in possible_targets
					else
						if(!length(possible_targets_random))
							to_chat(usr, "<span class='warning'>No random target found. Pick one manually.</span>")
							return
						new_target = pick(possible_targets_random)

					if(!new_target)
						return
				else
					to_chat(usr, "<span class='warning'>No possible target found. Defaulting to a Free objective.</span>")
					new_target = "Free objective"

				var/objective_path = text2path("/datum/objective/[new_obj_type]")
				if(new_target == "Free objective")
					new_objective = new objective_path
					new_objective:target = null
					new_objective.update_explanation_text()
				else
					new_objective = new objective_path
					new_objective:target = new_target:mind
					new_objective.update_explanation_text()

			if("destroy")
				var/list/possible_targets = active_ais(1)
				if(length(possible_targets))
					var/mob/new_target = input("Select target:", "Objective target") as null|anything in possible_targets
					new_objective = new /datum/objective/destroy
					new_objective.target = new_target.mind
					new_objective.update_explanation_text()
				else
					to_chat(usr, "No active AIs with minds")

			if("prevent")
				new_objective = /datum/objective/block // we can place paths here because they will be created as needed in the objective holder

			if("hijack")
				new_objective = /datum/objective/hijack

			if("escape")
				new_objective = /datum/objective/escape

			if("survive")
				new_objective = /datum/objective/survive

			if("nuclear")
				new_objective = /datum/objective/nuclear

			if("steal")
				if(!istype(objective, /datum/objective/steal))
					new_objective = new /datum/objective/steal
				else
					new_objective = objective
				var/datum/objective/steal/steal = new_objective
				if(!steal.select_target())
					return

			if("absorb", "blood")
				var/def_num
				if(objective&&objective.type==text2path("/datum/objective/[new_obj_type]"))
					def_num = objective.target_amount

				var/target_number = input("Input target number:", "Objective", def_num) as num|null
				if(isnull(target_number))//Ordinarily, you wouldn't need isnull. In this case, the value may already exist.
					return

				switch(new_obj_type)
					if("absorb")
						new_objective = new /datum/objective/absorb
					if("blood")
						new_objective = new /datum/objective/blood
				new_objective.target_amount = target_number
				new_objective.update_explanation_text()

			if("identity theft")
				var/list/possible_targets = list()
				for(var/datum/mind/possible_target in SSticker.minds)
					if((possible_target != src) && ishuman(possible_target.current))
						possible_targets += possible_target
				possible_targets = sortAtom(possible_targets)
				possible_targets += "Free objective"
				var/new_target = input("Select target:", "Objective target") as null|anything in possible_targets
				if(!new_target)
					return
				var/datum/mind/targ = new_target
				if(!istype(targ))
					CRASH("Invalid target for identity theft objective, cancelling")
				new_objective = new /datum/objective/escape/escape_with_identity
				new_objective.target = new_target
				new_objective.update_explanation_text()
				var/datum/objective/escape/escape_with_identity/O = new_objective
				O.target_real_name = new_objective.target.current.real_name
			if("custom")
				var/expl = sanitize(copytext_char(input("Custom objective:", "Objective", objective ? objective.explanation_text : "") as text|null, 1, MAX_MESSAGE_LEN))
				if(!expl)
					return
				new_objective = new /datum/objective
				new_objective.explanation_text = expl
				new_objective.needs_target = FALSE

		if(!new_objective)
			return

		if(objective)
			objective.holder.replace_objective(objective, new_objective) // replace it in its old holder
		else
			add_mind_objective(new_objective)

		log_admin("[key_name(usr)] has updated [key_name(current)]'s objectives: [new_objective]")
		message_admins("[key_name_admin(usr)] has updated [key_name_admin(current)]'s objectives: [new_objective]")

	else if(href_list["obj_delete"])
		var/datum/objective/objective = locate(href_list["obj_delete"])
		if(!istype(objective))
			return

		log_admin("[key_name(usr)] has removed one of [key_name(current)]'s objectives: [objective]")
		message_admins("[key_name_admin(usr)] has removed one of [key_name_admin(current)]'s objectives: [objective]")
		remove_mind_objective(objective, TRUE)

	else if(href_list["obj_completed"])
		var/datum/objective/objective = locate(href_list["obj_completed"])
		if(!istype(objective))
			return
		objective.completed = !objective.completed

		log_admin("[key_name(usr)] has toggled the completion of one of [key_name(current)]'s objectives")
		message_admins("[key_name_admin(usr)] has toggled the completion of one of [key_name_admin(current)]'s objectives")

	else if(href_list["implant"])
		var/mob/living/carbon/human/H = current

		switch(href_list["implant"])
			if("remove")
				for(var/obj/item/bio_chip/mindshield/I in H.contents)
					if(I && I.implanted)
						qdel(I)
				to_chat(H, "<span class='notice'><font size='3'><b>Your mindshield bio-chip has been deactivated.</b></font></span>")
				log_admin("[key_name(usr)] has deactivated [key_name(current)]'s mindshield bio-chip")
				message_admins("[key_name_admin(usr)] has deactivated [key_name_admin(current)]'s mindshield bio-chip")
			if("add")
				var/obj/item/bio_chip/mindshield/L = new/obj/item/bio_chip/mindshield(H)
				L.implant(H)

				log_admin("[key_name(usr)] has given [key_name(current)] a mindshield bio-chip")
				message_admins("[key_name_admin(usr)] has given [key_name_admin(current)] a mindshield bio-chip")

				to_chat(H, "<span class='userdanger'>You somehow have become the recipient of a mindshield transplant, and it just activated!</span>")
				var/datum/antagonist/rev/has_rev = has_antag_datum(/datum/antagonist/rev)
				if(has_rev)
					remove_antag_datum(/datum/antagonist/rev, silent_removal = TRUE) // we have some custom text, lets make the removal silent
					to_chat(H, "<span class='userdanger'>The nanobots in the mindshield implant remove all thoughts about being a revolutionary. Get back to work!</span>")

	else if(href_list["revolution"])

		switch(href_list["revolution"])
			if("clear")
				var/datum/antagonist/rev/has_rev = has_antag_datum(/datum/antagonist/rev)
				if(has_rev)
					remove_antag_datum(/datum/antagonist/rev)
					log_admin("[key_name(usr)] has de-rev'd [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-rev'd [key_name_admin(current)]")

			if("rev")
				var/datum/antagonist/rev/head/is_headrev = has_antag_datum(/datum/antagonist/rev/head)
				if(is_headrev)
					is_headrev.demote()
					log_admin("[key_name(usr)] has demoted [key_name(current)] from headrev to rev")
					message_admins("[key_name(usr)] has demoted [key_name(current)] from headrev to rev")
					edit_memory() // so it updates...
					return
				if(has_antag_datum(/datum/antagonist/rev))
					return
				add_antag_datum(/datum/antagonist/rev)
				log_admin("[key_name(usr)] has rev'd [key_name(current)]")
				message_admins("[key_name_admin(usr)] has rev'd [key_name_admin(current)]")
				current.create_log(MISC_LOG, "[current] was made into a revolutionary by [key_name_admin(usr)]")

			if("headrev")
				if(has_antag_datum(/datum/antagonist/rev/head))
					return
				var/datum/antagonist/rev/has_rev = has_antag_datum(/datum/antagonist/rev)
				if(has_rev)
					has_rev.promote()
					log_admin("[key_name(usr)] has promoted [key_name(current)] from rev to headrev (auto-equipped flash/hud)")
					message_admins("[key_name(usr)] has promoted [key_name(current)] from rev to headrev (auto-equipped flash/hud)")
					edit_memory() // so it updates...
					return

				var/datum/antagonist/rev/head/head_rev = new()
				head_rev.should_equip = FALSE
				add_antag_datum(head_rev)
				log_admin("[key_name(usr)] has head-rev'd [key_name(current)]")
				message_admins("[key_name_admin(usr)] has head-rev'd [key_name_admin(current)]")

			if("autoobjectives")
				var/datum/team/revolution/the_rev_team = SSticker.mode.get_rev_team()
				the_rev_team.update_team_objectives()
				log_admin("[key_name(usr)] has updated revolutionary objectives for [key_name(current)]")
				message_admins("[key_name_admin(usr)] has updated revolutionary objectives for [key_name_admin(current)]")

			if("flash")
				var/datum/antagonist/rev/head/headrev = has_antag_datum(/datum/antagonist/rev/head)
				if(!headrev.equip_revolutionary(TRUE, FALSE))
					to_chat(usr, "<span class='warning'>Spawning flash failed!</span>")
				log_admin("[key_name(usr)] has given [key_name(current)] a flash")
				message_admins("[key_name_admin(usr)] has given [key_name_admin(current)] a flash")

			if("takeflash")
				var/list/L = current.get_contents()
				var/obj/item/flash/flash = locate() in L
				if(!flash)
					to_chat(usr, "<span class='warning'>Deleting flash failed!</span>")
				qdel(flash)
				log_admin("[key_name(usr)] has taken [key_name(current)]'s flash")
				message_admins("[key_name_admin(usr)] has taken [key_name_admin(current)]'s flash")

			if("repairflash")
				var/list/L = current.get_contents()
				var/obj/item/flash/flash = locate() in L
				if(!flash)
					to_chat(usr, "<span class='warning'>Repairing flash failed!</span>")
				else
					flash.broken = FALSE
					log_admin("[key_name(usr)] has repaired [key_name(current)]'s flash")
					message_admins("[key_name_admin(usr)] has repaired [key_name_admin(current)]'s flash")

			if("reequip")
				var/list/L = current.get_contents()
				var/obj/item/flash/flash = locate() in L
				qdel(flash)
				take_uplink()
				var/datum/antagonist/rev/head/headrev = has_antag_datum(/datum/antagonist/rev/head)
				if(!headrev.equip_revolutionary())
					to_chat(usr, "<span class='warning'>Reequipping revolutionary went wrong!</span>")
					return
				log_admin("[key_name(usr)] has equipped [key_name(current)] as a revolutionary")
				message_admins("[key_name_admin(usr)] has equipped [key_name_admin(current)] as a revolutionary")

	else if(href_list["cult"])
		switch(href_list["cult"])
			if("clear")
				if(has_antag_datum(/datum/antagonist/cultist))
					remove_antag_datum(/datum/antagonist/cultist)
					log_admin("[key_name(usr)] has de-culted [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-culted [key_name_admin(current)]")
			if("cultist")
				if(!has_antag_datum(/datum/antagonist/cultist))
					add_antag_datum(/datum/antagonist/cultist)
					to_chat(current, "<span class='cultitalic'>Assist your new compatriots in their dark dealings. Their goal is yours, and yours is theirs. You serve [GET_CULT_DATA(entity_title2, "your god")] above all else. Bring It back.</span>")
					log_and_message_admins("has culted [key_name(current)]")
			if("dagger")
				var/datum/antagonist/cultist/cultist = has_antag_datum(/datum/antagonist/cultist)
				if(!cultist.cult_give_item(/obj/item/melee/cultblade/dagger))
					to_chat(usr, "<span class='warning'>Spawning dagger failed!</span>")
				log_and_message_admins("has equipped [key_name(current)] with a cult dagger")
			if("runedmetal")
				var/datum/antagonist/cultist/cultist = has_antag_datum(/datum/antagonist/cultist)
				if(!cultist.cult_give_item(/obj/item/stack/sheet/runed_metal/ten))
					to_chat(usr, "<span class='warning'>Spawning runed metal failed!</span>")
				log_and_message_admins("has equipped [key_name(current)] with 10 runed metal sheets")

	else if(href_list["wizard"])

		switch(href_list["wizard"])
			if("clear")
				if(has_antag_datum(/datum/antagonist/wizard))
					remove_antag_datum(/datum/antagonist/wizard)

					log_admin("[key_name(usr)] has de-wizarded [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-wizarded [key_name_admin(current)]")
			if("wizard")
				if(!has_antag_datum(/datum/antagonist/wizard))
					var/datum/antagonist/wizard/wizard = new /datum/antagonist/wizard()
					wizard.should_equip_wizard = FALSE
					wizard.should_name_pick = FALSE
					add_antag_datum(wizard)

					log_admin("[key_name(usr)] has wizarded [key_name(current)]")
					message_admins("[key_name_admin(usr)] has wizarded [key_name_admin(current)]")
					current.create_log(MISC_LOG, "[current] was made into a wizard by [key_name_admin(usr)]")
			if("lair")
				current.forceMove(pick(GLOB.wizardstart))
				log_admin("[key_name(usr)] has moved [key_name(current)] to the wizard's lair")
				message_admins("[key_name_admin(usr)] has moved [key_name_admin(current)] to the wizard's lair")
			if("dressup")
				var/datum/antagonist/wizard/wizard = has_antag_datum(/datum/antagonist/wizard)
				var/list/text_result = wizard.equip_wizard()
				to_chat(current, chat_box_red(text_result.Join("<br>")))
				log_admin("[key_name(usr)] has equipped [key_name(current)] as a wizard")
				message_admins("[key_name_admin(usr)] has equipped [key_name_admin(current)] as a wizard")
			if("name")
				var/datum/antagonist/wizard/wizard = has_antag_datum(/datum/antagonist/wizard)
				if(!istype(wizard))
					return
				wizard.name_wizard()
				log_admin("[key_name(usr)] has allowed wizard [key_name(current)] to name themselves")
				message_admins("[key_name_admin(usr)] has allowed wizard [key_name_admin(current)] to name themselves")


	else if(href_list["changeling"])
		switch(href_list["changeling"])
			if("clear")
				if(IS_CHANGELING(current))
					remove_antag_datum(/datum/antagonist/changeling)
					log_admin("[key_name(usr)] has de-changelinged [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-changelinged [key_name_admin(current)]")
			if("changeling")
				if(!IS_CHANGELING(current))
					add_antag_datum(/datum/antagonist/changeling)
					to_chat(current, "<span class='biggerdanger'>Your powers have awoken. A flash of memory returns to us... We are a changeling!</span>")
					log_admin("[key_name(usr)] has changelinged [key_name(current)]")
					message_admins("[key_name_admin(usr)] has changelinged [key_name_admin(current)]")

			if("autoobjectives")
				var/datum/antagonist/changeling/cling = has_antag_datum(/datum/antagonist/changeling)
				cling.give_objectives()
				to_chat(usr, "<span class='notice'>The objectives for changeling [key] have been generated. You can edit them and announce manually.</span>")
				log_admin("[key_name(usr)] has automatically forged objectives for [key_name(current)]")
				message_admins("[key_name_admin(usr)] has automatically forged objectives for [key_name_admin(current)]")

			if("initialdna")
				var/datum/antagonist/changeling/cling = has_antag_datum(/datum/antagonist/changeling)
				if(!cling || !length(cling.absorbed_dna))
					to_chat(usr, "<span class='warning'>Resetting DNA failed!</span>")
				else
					current.dna = cling.absorbed_dna[1]
					current.real_name = current.dna.real_name
					current.UpdateAppearance()
					domutcheck(current)
					log_admin("[key_name(usr)] has reset [key_name(current)]'s DNA")
					message_admins("[key_name_admin(usr)] has reset [key_name_admin(current)]'s DNA")

	else if(href_list["vampire"])
		switch(href_list["vampire"])
			if("clear")
				if(has_antag_datum(/datum/antagonist/vampire))
					remove_antag_datum(/datum/antagonist/vampire)
					to_chat(current, "<FONT color='red' size = 3><B>You grow weak and lose your powers! You are no longer a vampire and are stuck in your current form!</B></FONT>")
					log_admin("[key_name(usr)] has de-vampired [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-vampired [key_name_admin(current)]")
			if("vampire")
				if(!has_antag_datum(/datum/antagonist/vampire))
					add_antag_datum(/datum/antagonist/vampire)
					to_chat(current, "<B><font color='red'>Your powers have awoken. Your lust for blood grows... You are a Vampire!</font></B>")
					log_admin("[key_name(usr)] has vampired [key_name(current)]")
					message_admins("[key_name_admin(usr)] has vampired [key_name_admin(current)]")

			if("edit_usable_blood")
				var/new_usable = input(usr, "Select a new value:", "Modify usable blood") as null|num
				if(isnull(new_usable) || new_usable < 0)
					return
				var/datum/antagonist/vampire/vamp = has_antag_datum(/datum/antagonist/vampire)
				vamp.bloodusable = new_usable
				current.update_action_buttons_icon()
				log_admin("[key_name(usr)] has set [key_name(current)]'s usable blood to [new_usable].")
				message_admins("[key_name_admin(usr)] has set [key_name_admin(current)]'s usable blood to [new_usable].")

			if("edit_total_blood")
				var/new_total = input(usr, "Select a new value:", "Modify total blood") as null|num
				if(isnull(new_total) || new_total < 0)
					return

				var/datum/antagonist/vampire/vamp = has_antag_datum(/datum/antagonist/vampire)
				if(new_total < vamp.bloodtotal)
					if(alert(usr, "Note that reducing the vampire's total blood may remove some active powers. Continue?", "Confirm New Total", "Yes", "No") == "No")
						return
					vamp.remove_all_powers()

				vamp.bloodtotal = new_total
				vamp.check_vampire_upgrade()
				log_admin("[key_name(usr)] has set [key_name(current)]'s total blood to [new_total].")
				message_admins("[key_name_admin(usr)] has set [key_name_admin(current)]'s total blood to [new_total].")

			if("change_subclass")
				var/list/subclass_selection = list()
				for(var/subtype in subtypesof(/datum/vampire_subclass))
					var/datum/vampire_subclass/subclass = subtype
					subclass_selection[capitalize(initial(subclass.name))] = subtype
				subclass_selection["Let them choose (remove current subclass)"] = NONE

				var/new_subclass_name = input(usr, "Choose a new subclass:", "Change Vampire Subclass") as null|anything in subclass_selection
				if(!new_subclass_name)
					return

				var/datum/antagonist/vampire/vamp = has_antag_datum(/datum/antagonist/vampire)
				var/subclass_type = subclass_selection[new_subclass_name]

				if(subclass_type == NONE)
					vamp.clear_subclass()
					log_admin("[key_name(usr)] has removed [key_name(current)]'s vampire subclass.")
					message_admins("[key_name_admin(usr)] has removed [key_name_admin(current)]'s vampire subclass.")
				else
					vamp.upgrade_tiers -= /datum/spell/vampire/self/specialize
					vamp.change_subclass(subclass_type)
					log_admin("[key_name(usr)] has removed [key_name(current)]'s vampire subclass.")
					message_admins("[key_name_admin(usr)] has removed [key_name_admin(current)]'s vampire subclass.")

			if("full_power_override")
				var/datum/antagonist/vampire/vamp = has_antag_datum(/datum/antagonist/vampire)
				if(vamp.subclass.full_power_override)
					vamp.subclass.full_power_override = FALSE
					for(var/power in vamp.powers)
						if(!is_type_in_list(power, vamp.subclass.fully_powered_abilities))
							continue
						vamp.remove_ability(power)
				else
					vamp.subclass.full_power_override = TRUE

				vamp.check_full_power_upgrade()
				log_admin("[key_name(usr)] set [key_name(current)]'s vampire 'full_power_overide' to [vamp.subclass.full_power_override].")
				message_admins("[key_name_admin(usr)] set [key_name_admin(current)]'s vampire 'full_power_overide' to [vamp.subclass.full_power_override].")

			if("autoobjectives")
				var/datum/antagonist/vampire/V = has_antag_datum(/datum/antagonist/vampire)
				V.give_objectives()
				to_chat(usr, "<span class='notice'>The objectives for vampire [key] have been generated. You can edit them and announce manually.</span>")
				log_admin("[key_name(usr)] has automatically forged objectives for [key_name(current)]")
				message_admins("[key_name_admin(usr)] has automatically forged objectives for [key_name_admin(current)]")

	else if(href_list["vampthrall"])
		switch(href_list["vampthrall"])
			if("clear")
				if(has_antag_datum(/datum/antagonist/mindslave/thrall))
					remove_antag_datum(/datum/antagonist/mindslave/thrall)
					log_admin("[key_name(usr)] has de-vampthralled [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-vampthralled [key_name_admin(current)]")

	else if(href_list["mind_flayer"])
		switch(href_list["mind_flayer"])
			if("clear")
				if(has_antag_datum(/datum/antagonist/mindflayer))
					remove_antag_datum(/datum/antagonist/mindflayer)
					log_admin("[key_name(usr)] has de-flayer'd [key_name(current)].")
					message_admins("[key_name(usr)] has de-flayer'd [key_name(current)].")
			if("mind_flayer")
				make_mind_flayer()
				log_admin("[key_name(usr)] has flayer'd [key_name(current)].")
				to_chat(current, "<b><font color='red'>You feel an entity stirring inside your chassis... You are a Mindflayer!</font></b>")
				message_admins("[key_name(usr)] has flayer'd [key_name(current)].")
			if("edit_total_swarms")
				var/new_swarms = input(usr, "Select a new value:", "Modify swarms") as null|num
				if(isnull(new_swarms) || new_swarms < 0)
					return
				var/datum/antagonist/mindflayer/MF = has_antag_datum(/datum/antagonist/mindflayer)
				MF.set_swarms(new_swarms)
				log_admin("[key_name(usr)] has set [key_name(current)]'s current swarms to [new_swarms].")
				message_admins("[key_name_admin(usr)] has set [key_name_admin(current)]'s current swarms to [new_swarms].")

	else if(href_list["nuclear"])
		var/mob/living/carbon/human/H = current

		switch(href_list["nuclear"])
			if("clear")
				if(src in SSticker.mode.syndicates)
					SSticker.mode.syndicates -= src
					SSticker.mode.update_synd_icons_removed(src)
					special_role = null
					objective_holder.clear(/datum/objective/nuclear)
					to_chat(current, "<span class='warning'><font size='3'><b>You have been brainwashed! You are no longer a Syndicate operative!</b></font></span>")
					log_admin("[key_name(usr)] has de-nuke op'd [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-nuke op'd [key_name_admin(current)]")
			if("nuclear")
				if(!(src in SSticker.mode.syndicates))
					SSticker.mode.syndicates += src
					SSticker.mode.update_synd_icons_added(src)
					if(length(SSticker.mode.syndicates) == 1)
						SSticker.mode.prepare_syndicate_leader(src)
					else
						current.real_name = "[syndicate_name()] Operative #[length(SSticker.mode.syndicates) - 1]"
					special_role = SPECIAL_ROLE_NUKEOPS
					to_chat(current, "<span class='notice'>You are a [syndicate_name()] agent!</span>")
					SSticker.mode.forge_syndicate_objectives(src)
					SSticker.mode.greet_syndicate(src, FALSE) // False to fix the agent message appearing twice
					log_admin("[key_name(usr)] has nuke op'd [key_name(current)]")
					message_admins("[key_name_admin(usr)] has nuke op'd [key_name_admin(current)]")
			if("lair")
				current.forceMove(get_turf(locate("landmark*Syndicate-Spawn")))
				log_admin("[key_name(usr)] has moved [key_name(current)] to the nuclear operative spawn")
				message_admins("[key_name_admin(usr)] has moved [key_name_admin(current)] to the nuclear operative spawn")
			if("dressup")
				qdel(H.belt)
				qdel(H.back)
				qdel(H.l_ear)
				qdel(H.r_ear)
				qdel(H.gloves)
				qdel(H.head)
				qdel(H.shoes)
				qdel(H.wear_id)
				qdel(H.wear_pda)
				qdel(H.wear_suit)
				qdel(H.w_uniform)

				if(!SSticker.mode.equip_syndicate(current))
					to_chat(usr, "<span class='warning'>Equipping a Syndicate failed!</span>")
					return
				SSticker.mode.update_syndicate_id(current.mind, length(SSticker.mode.syndicates) == 1)
				log_admin("[key_name(usr)] has equipped [key_name(current)] as a nuclear operative")
				message_admins("[key_name_admin(usr)] has equipped [key_name_admin(current)] as a nuclear operative")

			if("tellcode")
				var/code
				for(var/obj/machinery/nuclearbomb/bombue in SSmachines.get_by_type(/obj/machinery/nuclearbomb))
					if(length(bombue.r_code) <= 5 && bombue.r_code != "LOLNO" && bombue.r_code != "ADMIN")
						code = bombue.r_code
						break
				if(code)
					store_memory("<B>Syndicate Nuclear Bomb Code</B>: [code]", 0, 0)
					to_chat(current, "The nuclear authorization code is: <B>[code]</B>")
					log_admin("[key_name(usr)] has given [key_name(current)] the nuclear authorization code")
					message_admins("[key_name_admin(usr)] has given [key_name_admin(current)] the nuclear authorization code")
				else
					to_chat(usr, "<span class='warning'>No valid nuke found!</span>")

	else if(href_list["eventmisc"])
		switch(href_list["eventmisc"])
			if("clear")
				if(!has_antag_datum(/datum/antagonist/eventmisc))
					return
				remove_antag_datum(/datum/antagonist/eventmisc)
				message_admins("[key_name_admin(usr)] has de-eventantag'ed [current].")
				log_admin("[key_name(usr)] has de-eventantag'ed [current].")
			if("eventmisc")
				if(has_antag_datum(/datum/antagonist/eventmisc))
					to_chat(usr, "[current] is already an event antag!")
					return
				add_antag_datum(/datum/antagonist/eventmisc)
				message_admins("[key_name_admin(usr)] has eventantag'ed [current].")
				log_admin("[key_name(usr)] has eventantag'ed [current].")
				current.create_log(MISC_LOG, "[current] was made into an event antagonist by [key_name_admin(usr)]")

	else if(href_list["zombie"])
		switch(href_list["zombie"])
			if("clear")
				if(!has_antag_datum(/datum/antagonist/zombie))
					return
				remove_antag_datum(/datum/antagonist/zombie)
				for(var/datum/disease/zombie/D in current.viruses)
					D.cure()
				if(ishuman(current))
					var/mob/living/carbon/human/human_current = current
					for(var/obj/item/organ/limb as anything in human_current.bodyparts)
						if(limb.status & ORGAN_DEAD && !limb.is_robotic())
							limb.status &= ~ORGAN_DEAD
					human_current.update_body()
				message_admins("[key_name_admin(usr)] has de-zombied'ed [key_name(current)].")
				log_admin("[key_name(usr)] has de-zombied'ed [key_name(current)].")
			if("zombie")
				if(has_antag_datum(/datum/antagonist/zombie))
					return
				add_antag_datum(/datum/antagonist/zombie)
				message_admins("[key_name_admin(usr)] has zombie'ed [key_name(current)].")
				log_admin("[key_name(usr)] has zombie'ed [key_name(current)].")
				current.create_log(MISC_LOG, "[key_name(current)] was made into an zombie by [key_name_admin(usr)]")
			if("zombievirus")
				if(has_antag_datum(/datum/antagonist/zombie) || !ishuman(current))
					return
				current.AddDisease(new /datum/disease/zombie)
				message_admins("[key_name_admin(usr)] has given a zombie virus to [key_name(current)].")
				log_admin("[key_name(usr)] has given a zombie virus to [key_name(current)].")
				current.create_log(MISC_LOG, "[key_name(current)] was admin-infected with a zombie virus by [key_name_admin(usr)]")
			if("zombievirusno")
				if(has_antag_datum(/datum/antagonist/zombie))
					return
				for(var/datum/disease/zombie/D in current.viruses)
					D.cure()
				message_admins("[key_name_admin(usr)] has removed the zombie virus from [key_name(current)].")
				log_admin("[key_name(usr)] has removed the zombie virus from [key_name(current)].")
				current.create_log(MISC_LOG, "[key_name(current)] had their zombie virus admin-removed by [key_name_admin(usr)]")

	else if(href_list["traitor"])
		switch(href_list["traitor"])
			if("clear")
				if(has_antag_datum(/datum/antagonist/traitor))
					remove_antag_datum(/datum/antagonist/traitor)
					log_admin("[key_name(usr)] has de-traitored [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-traitored [key_name_admin(current)]")

			if("traitor")
				if(!(has_antag_datum(/datum/antagonist/traitor)))
					add_antag_datum(/datum/antagonist/traitor)
					log_admin("[key_name(usr)] has traitored [key_name(current)]")
					message_admins("[key_name_admin(usr)] has traitored [key_name_admin(current)]")

			if("autoobjectives")
				var/datum/antagonist/traitor/T = has_antag_datum(/datum/antagonist/traitor)
				T.give_objectives()
				to_chat(usr, "<span class='notice'>The objectives for traitor [key] have been generated. You can edit them and announce manually.</span>")
				log_admin("[key_name(usr)] has automatically forged objectives for [key_name(current)]")
				message_admins("[key_name_admin(usr)] has automatically forged objectives for [key_name_admin(current)]")

	else if(href_list["contractor"])
		var/datum/contractor_hub/H = LAZYACCESS(GLOB.contractors, src)
		switch(href_list["contractor"])
			if("add")
				if(!H)
					return
				var/list/possible_targets = list()
				for(var/foo in SSticker.minds)
					var/datum/mind/possible_target = foo
					if(src == possible_target || !possible_target.current || !possible_target.key)
						continue
					possible_targets[possible_target.name] = possible_target

				var/choice = input(usr, "Select the contract target:", "Add Contract") as null|anything in possible_targets
				var/datum/mind/target = possible_targets[choice]
				if(!target || !target.current || !target.key)
					return
				var/datum/syndicate_contract/new_contract = new(H, src, list(), target)
				new_contract.reward_tc = list(0, 0, 0)
				H.contracts += new_contract
				for(var/difficulty in EXTRACTION_DIFFICULTY_EASY to EXTRACTION_DIFFICULTY_HARD)
					var/amount_tc = H.calculate_tc_reward(length(H.contracts), difficulty)
					new_contract.reward_tc[difficulty] = amount_tc
				SStgui.update_uis(H)
				log_admin("[key_name(usr)] has given a new contract to [key_name(current)] with [target.current] as the target")
				message_admins("[key_name_admin(usr)] has given a new contract to [key_name_admin(current)] with [target.current] as the target")

			if("tc")
				if(!H)
					return
				var/new_tc = input(usr, "Enter the new amount of TC:", "Set Claimable TC", H.reward_tc_available) as num|null
				new_tc = text2num(new_tc)
				if(isnull(new_tc) || new_tc < 0)
					return
				H.reward_tc_available = new_tc
				SStgui.update_uis(H)
				log_admin("[key_name(usr)] has set [key_name(current)]'s claimable TC to [new_tc]")
				message_admins("[key_name_admin(usr)] has set [key_name_admin(current)]'s claimable TC to [new_tc]")

			if("rep")
				if(!H)
					return
				var/new_rep = input(usr, "Enter the new amount of Rep:", "Set Available Rep", H.rep) as num|null
				new_rep = text2num(new_rep)
				if(isnull(new_rep) || new_rep < 0)
					return
				H.rep = new_rep
				SStgui.update_uis(H)
				log_admin("[key_name(usr)] has set [key_name(current)]'s contractor Rep to [new_rep]")
				message_admins("[key_name_admin(usr)] has set [key_name_admin(current)]'s contractor Rep to [new_rep]")

			// Contract specific actions
			if("target")
				if(!H)
					return
				var/datum/syndicate_contract/CO = locateUID(href_list["cuid"])
				if(!istype(CO))
					return

				var/list/possible_targets = list()
				for(var/foo in SSticker.minds)
					var/datum/mind/possible_target = foo
					if(src == possible_target || !possible_target.current || !possible_target.key)
						continue
					possible_targets[possible_target.name] = possible_target

				var/choice = input(usr, "Select the new contract target:", "Set Contract Target") as null|anything in possible_targets
				var/datum/mind/target = possible_targets[choice]
				if(!target || !target.current || !target.key)
					return
				// Update
				var/datum/data/record/R = find_record("name", target.name, GLOB.data_core.general)
				var/name = R?.fields["name"] || target.name || "Unknown"
				var/rank = R?.fields["rank"] || target.assigned_role || "Unknown"
				CO.contract.target = target
				CO.target_name = "[name], the [rank]"
				if(R?.fields["photo"])
					var/icon/temp = new('icons/turf/floors.dmi', pick("floor", "wood", "darkfull", "stairs"))
					temp.Blend(R.fields["photo"], ICON_OVERLAY)
					CO.target_photo = temp
				// Notify
				SStgui.update_uis(H)
				log_admin("[key_name(usr)] has set [key_name(current)]'s contract target to [target.current]")
				message_admins("[key_name_admin(usr)] has set [key_name_admin(current)]'s contract target to [target.current]")

			if("locations")
				if(!H)
					return
				var/datum/syndicate_contract/CO = locateUID(href_list["cuid"])
				if(!istype(CO))
					return

				var/list/difficulty_choices = list()
				for(var/diff in EXTRACTION_DIFFICULTY_EASY to EXTRACTION_DIFFICULTY_HARD)
					var/area/A = CO.contract.candidate_zones[diff]
					difficulty_choices["[A.name] ([CO.reward_tc[diff]] TC)"] = diff

				var/choice_diff = input(usr, "Select the location to change:", "Set Contract Location") as null|anything in difficulty_choices
				var/difficulty = difficulty_choices[choice_diff]
				if(!difficulty)
					return

				var/list/area_choices = list()
				for(var/a in return_sorted_areas())
					var/area/A = a
					if(A.outdoors || !is_station_level(A.z))
						continue
					area_choices += A

				var/new_area = input(usr, "Select the new location:", "Set Contract Location", CO.contract.candidate_zones[difficulty]) in area_choices
				if(!new_area)
					return

				var/new_reward = input(usr, "Enter the new amount of rewarded TC:", "Set Contract Location", CO.reward_tc[difficulty]) as num|null
				new_reward = text2num(new_reward)
				if(isnull(new_reward) || new_reward < 0)
					return
				CO.contract.candidate_zones[difficulty] = new_area
				CO.reward_tc[difficulty] = new_reward
				SStgui.update_uis(H)
				log_admin("[key_name(usr)] has set [key_name(current)]'s contract location to [new_area] with [new_reward] TC as reward")
				message_admins("[key_name_admin(usr)] has set [key_name_admin(current)]'s contract location to [new_area] with [new_reward] TC as reward")

			if("other")
				if(!H)
					return
				var/datum/syndicate_contract/CO = locateUID(href_list["cuid"])
				if(!istype(CO))
					return

				var/choice = input(usr, "Select an action to take:", "Other Contract Actions") in list("Edit Fluff Message", "Edit Prison Time", "Edit Credits Reward", "Delete Contract", "Cancel")
				if(!choice)
					return

				switch(choice)
					if("Edit Fluff Message")
						var/new_message = input(usr, "Enter the new fluff message:", "Edit Fluff Message", CO.fluff_message) as message|null
						if(!new_message)
							return
						CO.fluff_message = new_message
						log_admin("[key_name(usr)] has edited [key_name(current)]'s contract fluff message")
						message_admins("[key_name_admin(usr)] has edited [key_name_admin(current)]'s contract fluff message")
					if("Edit Prison Time")
						var/new_time = input(usr, "Enter the new prison time in seconds:", "Edit Prison Time", CO.prison_time / 10) as num|null
						if(!new_time || new_time < 0)
							return
						CO.prison_time = new_time SECONDS
						log_admin("[key_name(usr)] has edited [key_name(current)]'s contract prison time to [new_time] seconds")
						message_admins("[key_name_admin(usr)] has edited [key_name_admin(current)]'s contract prison time to [new_time] seconds")
					if("Edit Credits Reward")
						var/new_creds = input(usr, "Enter the new credits reward:", "Edit Credits Reward", CO.reward_credits) as num|null
						if(!new_creds || new_creds < 0)
							return
						CO.reward_credits = new_creds
						log_admin("[key_name(usr)] has edited [key_name(current)]'s contract reward credits to [new_creds]")
						message_admins("[key_name_admin(usr)] has edited [key_name_admin(current)]'s contract reward credits to [new_creds]")
					if("Delete Contract")
						if(CO.status == CONTRACT_STATUS_ACTIVE)
							CO.fail("Contract interrupted forcibly.")
						H.contracts -= CO
						log_admin("[key_name(usr)] has deleted [key_name(current)]'s contract")
						message_admins("[key_name_admin(usr)] has deleted [key_name_admin(current)]'s contract")
					else
						return
				SStgui.update_uis(H)

			if("interrupt")
				if(!H)
					return
				var/datum/syndicate_contract/CO = locateUID(href_list["cuid"])
				if(!istype(CO) || CO.status != CONTRACT_STATUS_ACTIVE)
					return
				H.current_contract = null
				CO.contract.extraction_zone = null
				CO.status = CONTRACT_STATUS_INACTIVE
				CO.clean_up()
				log_admin("[key_name(usr)] has interrupted [key_name(current)]'s contract")
				message_admins("[key_name_admin(usr)] has interrupted [key_name_admin(current)]'s contract")

			if("fail")
				if(!H)
					return
				var/datum/syndicate_contract/CO = locateUID(href_list["cuid"])
				if(!istype(CO) || CO.status != CONTRACT_STATUS_ACTIVE)
					return
				var/fail_reason = sanitize(input(usr, "Enter the fail reason:", "Fail Contract") as text|null)
				if(!fail_reason || CO.status != CONTRACT_STATUS_ACTIVE)
					return
				CO.fail(fail_reason)
				SStgui.update_uis(H)
				log_admin("[key_name(usr)] has failed [key_name(current)]'s contract with reason: [fail_reason]")
				message_admins("[key_name_admin(usr)] has failed [key_name_admin(current)]'s contract with reason: [fail_reason]")

	else if(href_list["mindslave"])
		switch(href_list["mindslave"])
			if("clear")
				if(has_antag_datum(/datum/antagonist/mindslave, FALSE))
					var/mob/living/carbon/human/H = current
					for(var/i in H.contents)
						if(istype(i, /obj/item/bio_chip/traitor))
							qdel(i)
							break
					remove_antag_datum(/datum/antagonist/mindslave)
					log_admin("[key_name(usr)] has de-mindslaved [key_name(current)]")
					message_admins("[key_name_admin(usr)] has de-mindslaved [key_name_admin(current)]")

	else if(href_list["abductor"])
		switch(href_list["abductor"])
			if("clear")
				to_chat(usr, "<span class='userdanger'>This will probably never be implemented. Sorry!</span>")
			if("abductor")
				if(!ishuman(current))
					to_chat(usr, "<span class='warning'>This only works on humans!</span>")
					return
				make_Abductor()
				log_admin("[key_name(usr)] turned [current] into an abductor.")
				message_admins("[key_name_admin(usr)] turned [key_name_admin(current)] into an abductor.")
				current.create_log(MISC_LOG, "[current] was made into an abductor by [key_name_admin(usr)]")

	else if(href_list["silicon"])
		switch(href_list["silicon"])
			if("unemag")
				var/mob/living/silicon/robot/R = current
				if(!istype(R))
					return
				R.unemag()
				log_admin("[key_name(usr)] has un-emagged [key_name(current)]")
				message_admins("[key_name_admin(usr)] has un-emagged [key_name_admin(current)]")

			if("unemagcyborgs")
				if(!is_ai(current))
					return
				var/mob/living/silicon/ai/ai = current
				for(var/mob/living/silicon/robot/R in ai.connected_robots)
					R.unemag(R)
				log_admin("[key_name(usr)] has unemagged [key_name(ai)]'s cyborgs")
				message_admins("[key_name_admin(usr)] has unemagged [key_name_admin(ai)]'s cyborgs")

	else if(href_list["common"])
		switch(href_list["common"])
			if("undress")
				for(var/obj/item/I in current)
					current.drop_item_to_ground(I, force = TRUE)
				log_admin("[key_name(usr)] has unequipped [key_name(current)]")
				message_admins("[key_name_admin(usr)] has unequipped [key_name_admin(current)]")
			if("takeuplink")
				take_uplink()
				var/datum/antagonist/traitor/T = has_antag_datum(/datum/antagonist/traitor)
				T.antag_memory = "" //Remove any antag memory they may have had (uplink codes, code phrases)
				log_admin("[key_name(usr)] has taken [key_name(current)]'s uplink")
				message_admins("[key_name_admin(usr)] has taken [key_name_admin(current)]'s uplink")
			if("crystals")
				if(usr.client.holder.rights & (R_SERVER|R_EVENT))
					var/obj/item/uplink/hidden/suplink = find_syndicate_uplink()
					var/crystals
					if(suplink)
						crystals = suplink.uses
					crystals = input("Amount of telecrystals for [key]","Syndicate uplink", crystals) as null|num
					if(!isnull(crystals))
						if(suplink)
							suplink.uses = crystals
							log_admin("[key_name(usr)] has set [key_name(current)]'s telecrystals to [crystals]")
							message_admins("[key_name_admin(usr)] has set [key_name_admin(current)]'s telecrystals to [crystals]")
			if("uplink")
				if(has_antag_datum(/datum/antagonist/traitor))
					var/datum/antagonist/traitor/T = has_antag_datum(/datum/antagonist/traitor)
					if(!T.give_uplink())
						to_chat(usr, "<span class='warning'>Equipping a Syndicate failed!</span>")
						return
				log_admin("[key_name(usr)] has given [key_name(current)] an uplink")
				message_admins("[key_name_admin(usr)] has given [key_name_admin(current)] an uplink")

	else if(href_list["obj_announce"])
		var/list/messages = prepare_announce_objectives()
		to_chat(current, chat_box_red(messages.Join("<br>")))
		SEND_SOUND(current, sound('sound/ambience/alarm4.ogg'))
		log_admin("[key_name(usr)] has announced [key_name(current)]'s objectives")
		message_admins("[key_name_admin(usr)] has announced [key_name_admin(current)]'s objectives")

	edit_memory()

/**
 * Create and/or add the `datum_type_or_instance` antag datum to the src mind.
 *
 * Arguments:
 * * antag_datum - an antag datum typepath or instance. If it's a typepath, it will create a new antag datum
 * * datum/team/team - the antag team that the src mind should join, if any
 */
/datum/mind/proc/add_antag_datum(datum_type_or_instance, datum/team/team)
	var/datum/antagonist/antag_datum
	if(!ispath(datum_type_or_instance))
		antag_datum = datum_type_or_instance
		if(!istype(antag_datum))
			return
	else
		antag_datum = new datum_type_or_instance()

	if(!antag_datum.can_be_owned(src))
		qdel(antag_datum)
		return
	antag_datum.owner = src
	LAZYADD(antag_datums, antag_datum)
	antag_datum.create_team(team)
	var/datum/team/antag_team = antag_datum.get_team()
	if(antag_team)
		antag_team.add_member(src)
	ASSERT(antag_datum.owner && antag_datum.owner.current)
	antag_datum.on_gain()
	return antag_datum

/**
 * Remove the specified `datum_type` antag datum from the src mind.
 *
 * Arguments:
 * * datum_type - an antag datum typepath
 */
/datum/mind/proc/remove_antag_datum(datum_type, check_subtypes = TRUE, silent_removal = FALSE)
	var/datum/antagonist/A = has_antag_datum(datum_type, check_subtypes)
	if(A)
		A.silent |= silent_removal
		qdel(A)

/**
 * Removes all antag datums from the src mind.
 *
 * Use this over doing `QDEL_LIST_CONTENTS(antag_datums)`.
 */
/datum/mind/proc/remove_all_antag_datums(handle_target_cryo = FALSE)
	// This is not `QDEL_LIST_CONTENTS(antag_datums)`because it's possible for the `antag_datums` list to be set to null during deletion of an antag datum.
	// Then `QDEL_LIST` would runtime because it would be doing `null.Cut()`.
	for(var/datum/antagonist/A as anything in antag_datums)
		if(handle_target_cryo)
			A.on_cryo()
		qdel(A)
	antag_datums?.Cut()
	antag_datums = null

/// This proc sets the hijack speed for a mob. If greater than zero, they can hijack. Outputs in seconds.
/datum/mind/proc/get_hijack_speed()
	var/hijack_speed = 0
	if(special_role)
		hijack_speed = 15 SECONDS
	if(locate(/datum/objective/hijack) in get_all_objectives())
		hijack_speed = 10 SECONDS
	return hijack_speed



/**
 * Returns an antag datum instance if the src mind has the specified `datum_type`. Returns `null` otherwise.
 *
 * Arguments:
 * * datum_type - an antag datum typepath
 * * check_subtypes - TRUE if this proc will consider subtypes of `datum_type` as valid. FALSE if only the exact same type should be considered.
 */
/datum/mind/proc/has_antag_datum(datum_type, check_subtypes = TRUE)
	for(var/datum/antagonist/A as anything in antag_datums)
		if(check_subtypes && istype(A, datum_type))
			return A
		else if(A.type == datum_type)
			return A

/datum/mind/proc/prepare_announce_objectives(title = TRUE)
	if(!current)
		return
	var/list/text = list()
	if(title)
		text.Add("<span class='notice'>Your current objectives:</span>")
	text.Add(gen_objective_text())
	return text

/datum/mind/proc/find_syndicate_uplink()
	var/list/L = current.get_contents()
	for(var/obj/item/I in L)
		if(I.hidden_uplink)
			return I.hidden_uplink
	return null

/datum/mind/proc/take_uplink()
	var/obj/item/uplink/hidden/H = find_syndicate_uplink()
	if(H)
		qdel(H)

/datum/mind/proc/make_Traitor()
	if(!has_antag_datum(/datum/antagonist/traitor))
		add_antag_datum(/datum/antagonist/traitor)

/datum/mind/proc/make_Nuke()
	if(!(src in SSticker.mode.syndicates))
		SSticker.mode.syndicates += src
		SSticker.mode.update_synd_icons_added(src)
		if(length(SSticker.mode.syndicates) == 1)
			SSticker.mode.prepare_syndicate_leader(src)
		else
			current.real_name = "[syndicate_name()] Operative #[length(SSticker.mode.syndicates) - 1]"
		special_role = SPECIAL_ROLE_NUKEOPS
		assigned_role = SPECIAL_ROLE_NUKEOPS
		to_chat(current, "<span class='notice'>You are a [syndicate_name()] agent!</span>")
		SSticker.mode.forge_syndicate_objectives(src)
		SSticker.mode.greet_syndicate(src, FALSE) // False to fix the agent message appearing twice

		current.loc = get_turf(locate("landmark*Syndicate-Spawn"))

		var/mob/living/carbon/human/H = current
		qdel(H.belt)
		qdel(H.back)
		qdel(H.l_ear)
		qdel(H.r_ear)
		qdel(H.gloves)
		qdel(H.head)
		qdel(H.shoes)
		qdel(H.wear_id)
		qdel(H.wear_pda)
		qdel(H.wear_suit)
		qdel(H.w_uniform)

		SSticker.mode.equip_syndicate(current)

/datum/mind/proc/make_vampire()
	if(!has_antag_datum(/datum/antagonist/vampire))
		add_antag_datum(/datum/antagonist/vampire)

/datum/mind/proc/make_Overmind()
	if(!(src in SSticker.mode.blob_overminds))
		SSticker.mode.blob_overminds += src
		special_role = SPECIAL_ROLE_BLOB_OVERMIND

/datum/mind/proc/make_mind_flayer()
	if(!has_antag_datum(/datum/antagonist/mindflayer))
		add_antag_datum(/datum/antagonist/mindflayer)
		SSticker.mode.mindflayers |= src

/datum/mind/proc/make_Abductor()
	if(alert(usr, "Are you sure you want to turn this person into an abductor? This can't be undone!", "New Abductor?", "Yes", "No") != "Yes")
		return

	for(var/datum/team/abductor/team in SSticker.mode.actual_abductor_teams)
		if(length(team.members) < 2)
			team.add_member(src)
			team.create_agent()
			team.create_scientist()
			return
	var/role = alert("Abductor Role?", "Role", "Agent", "Scientist", "Cancel")
	if(!role || role == "Cancel")
		return
	var/datum/team/abductor/team = new /datum/team/abductor(list(src))
	if(role == "Agent")
		team.create_agent()
	else
		team.create_scientist()


/datum/mind/proc/AddSpell(datum/spell/S)
	spell_list += S
	S.action.Grant(current)

/datum/mind/proc/RemoveSpell(datum/spell/spell) //To remove a specific spell from a mind
	if(!spell)
		return
	for(var/datum/spell/S in spell_list)
		if(istype(S, spell))
			qdel(S)
			spell_list -= S

/datum/mind/proc/transfer_actions(mob/living/new_character)
	if(current && current.actions)
		for(var/datum/action/A in current.actions)
			A.Grant(new_character)
	transfer_mindbound_actions(new_character)

/datum/mind/proc/transfer_mindbound_actions(mob/living/new_character)
	for(var/X in spell_list)
		var/datum/spell/S = X
		if(!S.on_mind_transfer(new_character))
			current.RemoveSpell(S)
			continue
		S.action.Grant(new_character)

/datum/mind/proc/get_ghost(even_if_they_cant_reenter)
	for(var/mob/dead/observer/G in GLOB.dead_mob_list)
		if(G.mind == src && G.mind.key == G.key)
			if(G.can_reenter_corpse || even_if_they_cant_reenter)
				return G
			break

/datum/mind/proc/check_ghost_client()
	var/mob/dead/observer/G = get_ghost()
	if(G?.client)
		return TRUE

/datum/mind/proc/grab_ghost(force)
	var/mob/dead/observer/G = get_ghost(even_if_they_cant_reenter = force)
	. = G
	if(G)
		G.reenter_corpse()


/datum/mind/proc/make_zealot(mob/living/carbon/human/missionary, convert_duration = 10 MINUTES, team_color = "red")
	zealot_master = missionary

	// Give the new zealot their mindslave datum with a custom greeting.
	var/greeting = "You're now a loyal zealot of [missionary.name]!</B> You now must lay down your life to protect [missionary.p_them()] and assist in [missionary.p_their()] goals at any cost."
	add_antag_datum(new /datum/antagonist/mindslave(missionary.mind, greeting))

	var/obj/item/clothing/under/jumpsuit = null
	if(ishuman(current))		//only bother with the jumpsuit stuff if we are a human type, since we won't have the slot otherwise
		var/mob/living/carbon/human/H = current
		if(H.w_uniform)
			jumpsuit = H.w_uniform
			jumpsuit.color = team_color
			H.update_inv_w_uniform()

	add_attack_logs(missionary, current, "Converted to a zealot for [convert_duration/600] minutes")
	addtimer(CALLBACK(src, PROC_REF(remove_zealot), jumpsuit), convert_duration) //deconverts after the timer expires
	return TRUE

/datum/mind/proc/remove_zealot(obj/item/clothing/under/jumpsuit = null)
	if(!zealot_master)	//if they aren't a zealot, we can't remove their zealot status, obviously. don't bother with the rest so we don't confuse them with the messages
		return
	remove_antag_datum(/datum/antagonist/mindslave)
	add_attack_logs(zealot_master, current, "Lost control of zealot")
	zealot_master = null

	if(jumpsuit)
		jumpsuit.color = initial(jumpsuit.color)		//reset the jumpsuit no matter where our mind is
		if(ishuman(current))							//but only try updating us if we are still a human type since it is a human proc
			var/mob/living/carbon/human/H = current
			H.update_inv_w_uniform()

	to_chat(current, "<span class='warning'><b>You seem to have forgotten the events of the past 10 minutes or so, and your head aches a bit as if someone beat it savagely with a stick.</b></span>")
	to_chat(current, "<span class='warning'><b>This means you don't remember who you were working for or what you were doing.</b></span>")

/datum/mind/proc/has_normal_assigned_role()
	if(!assigned_role)
		return FALSE
	if(assigned_role == special_role) // nukie, ninjas, wizards, whatever
		return FALSE
	if(assigned_role == "Assistant") // because the default assigned role is assistant :P
		for(var/list/L in list(GLOB.data_core.general))
			for(var/datum/data/record/R in L)
				if(R.fields["name"] == name)
					return TRUE
		return FALSE
	return TRUE


/datum/mind/proc/get_assigned_role_asset() //Used in asset generation for Orbiting
	var/job_icons = GLOB.joblist
	var/centcom = get_all_centcom_jobs() + SPECIAL_ROLE_ERT + SPECIAL_ROLE_DEATHSQUAD
	var/solgov = get_all_solgov_jobs()
	var/soviet = get_all_soviet_jobs()

	if(assigned_role in centcom) //Return with the NT logo if it is a Centcom job
		return "centcom"

	if(assigned_role in solgov) //Return with the SolGov logo if it is a SolGov job
		return "solgov"

	if(assigned_role in soviet) //Return with the U.S.S.P logo if it is a Soviet job
		return "soviet"

	if(assigned_role in job_icons) //Check if the job has a hud icon
		return assigned_role
	return "unknown"

//Initialisation procs
/mob/proc/mind_initialize()
	SHOULD_CALL_PARENT(TRUE)
	if(mind)
		mind.key = key
	else
		mind = new /datum/mind(key)
		if(SSticker)
			SSticker.minds += mind
		else
			error("mind_initialize(): No ticker ready yet! Please inform Carn")
	if(!mind.name)
		mind.name = real_name
	mind.current = src
	SEND_SIGNAL(src, COMSIG_MIND_INITIALIZE)

//HUMAN
/mob/living/carbon/human/mind_initialize()
	..()
	if(!mind.assigned_role)
		mind.assigned_role = "Assistant"	//default

/mob/proc/sync_mind()
	mind_initialize()  //updates the mind (or creates and initializes one if one doesn't exist)
	mind.active = TRUE //indicates that the mind is currently synced with a client

//slime
/mob/living/simple_animal/slime/mind_initialize()
	..()
	mind.assigned_role = "slime"

//XENO
/mob/living/carbon/alien/mind_initialize()
	..()
	mind.assigned_role = "Alien"
	//XENO HUMANOID
/mob/living/carbon/alien/humanoid/queen/mind_initialize()
	..()
	mind.special_role = SPECIAL_ROLE_XENOMORPH_QUEEN

/mob/living/carbon/alien/humanoid/hunter/mind_initialize()
	..()
	mind.special_role = SPECIAL_ROLE_XENOMORPH_HUNTER

/mob/living/carbon/alien/humanoid/drone/mind_initialize()
	..()
	mind.special_role = SPECIAL_ROLE_XENOMORPH_DRONE

/mob/living/carbon/alien/humanoid/sentinel/mind_initialize()
	..()
	mind.special_role = SPECIAL_ROLE_XENOMORPH_SENTINEL
	//XENO LARVA
/mob/living/carbon/alien/larva/mind_initialize()
	..()
	mind.special_role = SPECIAL_ROLE_XENOMORPH_LARVA

//AI
/mob/living/silicon/ai/mind_initialize()
	..()
	mind.assigned_role = "AI"

//BORG
/mob/living/silicon/robot/mind_initialize()
	..()
	mind.assigned_role = "Cyborg"

//PAI
/mob/living/silicon/pai/mind_initialize()
	..()
	mind.assigned_role = "pAI"
	mind.special_role = null

//BLOB
/mob/camera/overmind/mind_initialize()
	..()
	mind.special_role = SPECIAL_ROLE_BLOB

//Animals
/mob/living/simple_animal/mind_initialize()
	..()
	mind.assigned_role = "Animal"

/mob/living/simple_animal/pet/dog/corgi/mind_initialize()
	..()
	mind.assigned_role = "Corgi"

/mob/living/simple_animal/shade/mind_initialize()
	..()
	mind.assigned_role = "Shade"

/mob/living/simple_animal/hostile/construct/builder/mind_initialize()
	..()
	mind.assigned_role = "Artificer"
	mind.special_role = SPECIAL_ROLE_CULTIST

/mob/living/simple_animal/hostile/construct/wraith/mind_initialize()
	..()
	mind.assigned_role = "Wraith"
	mind.special_role = SPECIAL_ROLE_CULTIST

/mob/living/simple_animal/hostile/construct/armoured/mind_initialize()
	..()
	mind.assigned_role = "Juggernaut"
	mind.special_role = SPECIAL_ROLE_CULTIST
