-- Magic System Rework 2.0 by amakri, original Magic System by Dalas
local _ = wesnoth.textdomain "wesnoth-ctl"
local utils = wesnoth.require "wml-utils"
local spell_data = wesnoth.dofile('~add-ons/Chasing_the_Light/lua/skill_set.lua')

-- to make code shorter
local wml_actions = wesnoth.wml_actions

-- metatable for GUI tags
local T = wml.tag

function deep_copy(original)
    local copy = {}
    for g, v in pairs(original) do
        if type(v) == "table" then
            copy[g] = deep_copy(v)
        else
            copy[g] = v
        end
    end
    return copy
end

-------------------------
-- SKILL'S COST
-------------------------
function spellcasting_cost(Table)
    local caster_temp = ( wesnoth.units.find_on_map({ id=Table.id }) )[1]
    if (Table.xp_cost)  then caster_temp.experience  =caster_temp.experience  -Table.xp_cost  end
    if (Table.hp_cost)  then caster_temp.experience  =caster_temp.hitpoints  -Table.hp_cost  end
    if (Table.gold_cost)  then wesnoth.sides[caster_temp.side].gold =wesnoth.sides[caster_temp.side].gold  -Table.gold_cost  end
    if (Table.atk_cost) then caster_temp.attacks_left=caster_temp.attacks_left-Table.atk_cost end
end



--###########################################################################################################################################################
--                                                                  SKILL DIALOG
--###########################################################################################################################################################
function display_skills_dialog(selecting)
    if wesnoth.current.user_is_replaying then return end -- якщо це реплей, то не спавнити діалог. схоже, не працює
    local caster = ( wesnoth.units.find_on_map({ id=wml.variables['current_caster'] }) )[1]
	local caster_side = wesnoth.get_sides({ side = caster.side })
    if not (caster_side[1].controller == "human" and caster_side[1].is_local and wml.variables["side_number"] == caster_side[1].side) then return end --якщо зараз не хід гравця

    local result_table = {} -- table used to return selected skills
	
	--###############################
	-- CREATE DIALOG
	--###############################
	local dialog = {
	    definition="menu",
		T.helptip{ id="tooltip_large" }, -- mandatory field
		T.tooltip{ id="tooltip_large" }, -- mandatory field
		T.grid{} }
	local grid = dialog[3]

    --список усіх доступних заклять
	local skills_copy = {}
    for i = 1, 10 do
	    if wml.variables["caster_" .. caster.id .. ".spell_group_" .. i] then
            skills_copy[i] = {}
		    for spell in wml.variables["caster_" .. caster.id .. ".spell_group_" .. i]:gmatch("[^,]+") do
                table.insert(skills_copy[i], spell)
            end
		end
    end

	local skills_actual_copy = deep_copy(spell_data.skill_set)
	
	-------------------------
	-- HEADER
	-------------------------
	table.insert( grid[2], T.row{ T.column{ border="bottom", border_size=15, T.image{  label="icons/banner1.png"  }}} )
	local title_text = selecting and wml.variables["caster_" .. caster.id .. ".u_title_select"]  or wml.variables["caster_" .. caster.id .. ".u_title_cast"]
	table.insert( grid[2], T.row{ T.column{ T.label{
        definition="title",
        horizontal_alignment="center",
        label = title_text,
    }}} )
	local                help_text = "<span size='small'><i>" .. wml.variables["caster_" .. caster.id .. ".u_description"] .. "</i></span>"
	table.insert( grid[2], T.row{ T.column{ border="top", border_size=15, T.label{ use_markup=true, label=help_text }}} )
	table.insert( grid[2], T.row{ T.column{ border="top", border_size=15, T.image{  label="icons/banner2.png"  }}} )
	
	-------------------------
	-- SKILL GROUPS
	-------------------------
	-- each button/image/label id ends with the index of the skill group it corresponds to
	-- put all these in 1 big grid, so they can have their own table-layout
	
	local skill_grid = T.grid{}
	
	--список розблокованих заклять
	local already_unlocked_list = {}
	for spell in wml.variables["caster_" .. caster.id .. ".spell_unlocked"]:gmatch("[^,]+") do
        table.insert(already_unlocked_list, spell)
    end
	
	for _, spell_list in pairs(skills_copy) do
        for i, skill_id in ipairs(spell_list) do
            for _, skill in ipairs(skills_actual_copy) do
	    	    if skill_id == skill.id then
	    			for _, unlocked_skill in ipairs(already_unlocked_list) do
	    		        if not (unlocked_skill == skill.id) then
                            spell_list[i] = spell_data.locked
                        else
                            spell_list[i] = skill
	    					break
                        end
                    end
	    			break
	    		end
            end
        end
	end
	
	--не показувати групи, які недоступні або заблоковані
	for i = #skills_copy, 1, -1 do
        local all_locked = true
        
        for j = #skills_copy[i], 1, -1 do
            if not skills_copy[i][j].id then
                skills_copy[i][j] = nil
            else
                if skills_copy[i][j] ~= spell_data.locked then
                    all_locked = false
                end
            end
        end
    
        if all_locked then
            table.remove(skills_copy, i)
        end
    end
	
    --spell_equiped
	local skills_equipped = {}
	if wml.variables["caster_" .. caster.id .. ".spell_equipped"] then
	    for spell in wml.variables["caster_" .. caster.id .. ".spell_equipped"]:gmatch("[^,]+") do
	    	table.insert(skills_equipped, spell) --список, що є аналогом wml.variables[spell]
        end
	end

	for i=1,#skills_copy,1 do
		local button
		local subskill_row
		if (selecting) then
			-- menu button for selecting skills
			button = T.menu_button{  id="button"..i, use_markup=true  }
			for j=1,#skills_copy[i],1 do
				table.insert( button[2], T.option{label=skills_copy[i][j].label} )
			end
		else -- button for casting spells, or label for displaying skills
			for j=1,#skills_copy[i],1 do
				local skill = skills_copy[i][j]
				for o, equipped_skill in ipairs(skills_equipped) do
				    if (equipped_skill == skill.id) then
				    	if (not (skill.xp_cost or skill.gold_cost or skill.hp_cost)) then button=T.label{  id="button"..i, use_markup=true, label=skill.label }
				    	else                        button=T.button{ id="button"..i, use_markup=true, label=skill.label } end
				    	-- handle one skill with multiple buttons
				    	if (skill.subskills) then
				    		subskill_row = T.row{}
				    		for k=1,#skill.subskills,1 do
				    			local subskill = skill.subskills[k]
				    			local subskill_is_unlocked
				    			for p, unlocked_skill in ipairs(already_unlocked_list) do
				    			    if (unlocked_skill == skill.subskills[k].id) then
				    			        table.insert( subskill_row[2], T.column{T.button{id=subskill.id,use_markup=true,label=subskill.label}} );
				    					subskill_is_unlocked = true
				    					break
				    			    end
				    			end
				    			if not subskill_is_unlocked then
				    				table.insert( subskill_row[2], T.column{T.button{id=subskill.id,use_markup=true,enabled=false,label=_"<span>Locked</span>"}} );
				    			end
				    			subskill_is_unlocked = nil
				    		end
				    	end
						break
				    end
				end
			end
			if (not button) then button=T.label{id="button"..i} end -- dummy button
		end
		
		-- skill row
		table.insert( skill_grid[2], T.row{ 
			T.column{ border="left",  border_size=15, button},
            T.column{                                 T.label{label="  "}},  T.column{  horizontal_alignment="left", T.image{id="image"..i                }  },
            T.column{ border="right", border_size=15, T.label{label="  "}},  T.column{  horizontal_alignment="left", T.label{id="label"..i,use_markup=true}  },
		} )
		
		-- subskill row
		if (subskill_row) then table.insert( skill_grid[2], T.row{ 
			T.column{T.label{}}, T.column{T.label{}},
			T.column{T.label{}}, T.column{T.label{}},
			T.column{T.grid{subskill_row}},
		} ) end
		
		-- spacer row
		table.insert( skill_grid[2], T.row{ 
			T.column{T.label{label="  "}},
			T.column{T.label{}}, T.column{T.label{}},
			T.column{T.label{}}, T.column{T.label{}}
		} )
    end
	table.insert( grid[2], T.row{T.column{ horizontal_alignment="left", skill_grid }} )
	
	-------------------------
	-- CONFIRM BUTTON
	-------------------------
	table.insert( grid[2], T.row{ T.column{T.image{  label="icons/banner2.png"  }}} )
	if (selecting) then
        table.insert( grid[2], T.row{ T.column{ T.grid{ T.row{ T.column{
            border="top,right", border_size=10,
            T.button{  id="confirm_button", use_markup=true, return_value=1, label=_"Confirm Spells <small><i>(can be changed every scenario)</i></small>"  }
        }, T.column{
            border="top,left",  border_size=10,
            T.button{  id="wait_button",    use_markup=true, return_value=2, label=_"Choose Later"  }
        }}}}})
    else
        table.insert( grid[2], T.row{ T.column{
            border="top", border_size=10,
            T.button{  id="confirm_button", use_markup=true, return_value=1, label="Cancel"  }
        }})
    end
	
	table.insert( grid[2], T.row{ T.column{ border="top", border_size=15,  T.image{  label="icons/banner4.png"  }}} )
	
	
	
	--###############################
	-- POPULATE DIALOG
	--###############################
	-------------------------
	-- PRESHOW
	-------------------------
	local function preshow(dialog)
		-- for the button corresponding to each skill group
		
		for i,group in pairs(skills_copy) do
			button = dialog["button"..i]
			
			-- menu callbacks for selecting skills
			if (selecting) then
				-- default to whatever skill we had selected last time
				if skills_equipped then
				    for j,skill in pairs(skills_copy[i]) do
				        for _, equipped_skill in ipairs(skills_equipped) do
				            if (equipped_skill == skill.id) then
				    		    button.selected_index=j
				    			break
				    		end
				    	end
				    end
				end
				
				-- whenever we refresh the menu, update the image and label
				refresh = function(button)
					if (not skills_copy[i][1]) then return end
					dialog["image"..i].label = skills_copy[i][button.selected_index].image
					dialog["label"..i].label = skills_copy[i][button.selected_index].description
					
					-- also update variables
					for j, skill in pairs(skills_copy[i]) do
                        result_table[skill.id] = (j == button.selected_index) and "yes" or "no"
                        if skill.id == "skill_locked" then 
                            result_table[skill.id] = "no"
                        end
                    end
				end
				
				-- refresh immediately, and after any change
				refresh(button)
				button.on_modified = refresh
			
			-- fixed labels for casting/displaying skills/spells
			else dialog["button"..i].visible = false
				for j,skill in pairs(skills_copy[i]) do
				    for _, equipped_skill in ipairs(skills_equipped) do
					    if equipped_skill == skill.id then
						    goto continue_equipped
						end
					end
					
					goto continue_unequipped
					
					::continue_equipped::
					
					-- if we know this skill, reveal and initialize the UI
					dialog["button"..i].visible = true
					dialog["image" ..i].label = skill.image
					dialog["label" ..i].label = skill.description
					
					-- if the button is clickable (i.e. a castable spell), set on_button_click
					local function initialize_button( buttonid, skill, small )

						if (dialog[buttonid].type=="button") then
						    --check if locked
							local skill_is_unlocked
							for _, unlocked_skill in ipairs(already_unlocked_list) do
							    if (unlocked_skill == skill.id) then
									skill_is_unlocked = true
								    break
								end
							end

							-- cancel spell
							local function caster_has_object(object_id) return wesnoth.units.find_on_map{ id=caster.id, T.filter_wml{T.modifications{T.object{id=object_id}}} }[1] end
							if (caster_has_object(skill.id)) then
								dialog[buttonid].label = small and "<span size='small'>Cancel</span>" or label('Cancel')
								dialog[buttonid].on_button_click = function()
								    wml.variables["caster_" .. caster.id .. ".spell_to_cast"] = skill.id.."_cancel"
									gui.widget.close(dialog)
								end
							-- errors (extra spaces are to center the text)
							elseif (not skill_is_unlocked) then
								dialog[buttonid].enabled = false
								skill_is_unlocked = nil
							elseif (wml.variables["caster_" .. caster.id .. ".spellcasted_this_turn"]) then
								dialog[buttonid].label = small and _"<span size='small'>1 spell/turn</span>" or _"<span> Can only cast\n1 spell per turn</span>"
								dialog[buttonid].enabled = false
							elseif (wml.variables["caster_" .. caster.id .. ".polymorphed"]) then
								dialog[buttonid].label = small and _"<span size='small'>Polymorphed</span>" or _"<span>  Blocked by\n  Polymorph</span>"
								dialog[buttonid].enabled = false
							elseif (wesnoth.units.find_on_map{ id=caster.id, T.filter_location{radius=3, T.filter{id='Haralin_mirror3'}} }[1]) then   -- mirror Haralin counterspell. Переробити, щоб працювало з усіма
								dialog[buttonid].label = small and _"<span size='small'>Counterspelled</span>" or _"<span>  Blocked by\n Counterspell</span>"
								dialog[buttonid].enabled = false
							elseif (wml.variables['counterspell_active']) then -- counterspell
								dialog[buttonid].label = small and _"<span size='small'>Counterspelled</span>" or _"<span>  Blocked by\n Counterspell</span>"
								dialog[buttonid].enabled = false
							elseif (skill.xp_cost and skill.xp_cost>caster.experience) then
								dialog[buttonid].label = small and _"<span size='small'>No XP</span>" or label('Insufficient XP')
								dialog[buttonid].enabled = false
							elseif (skill.hp_cost and skill.hp_cost>=caster.hitpoints) then
								dialog[buttonid].label = small and _"<span size='small'>No HP</span>" or label('Insufficient HP')
								dialog[buttonid].enabled = false
					     	elseif (skill.gold_cost and skill.gold_cost>wesnoth.sides[caster.side].gold) then
								dialog[buttonid].label = small and _"<span size='small'>No Gold</span>" or label('Insufficient Gold')
								dialog[buttonid].enabled = false
							elseif (skill.atk_cost and skill.atk_cost>caster.attacks_left) then
								dialog[buttonid].label = small and _"<span size='small'>No Attack</span>" or label('No Attack')
								dialog[buttonid].enabled = false
							
							-- cast spell
							else
								dialog[buttonid].on_button_click = function()
								    wesnoth.sync.invoke_command("spellcasting_cost", {id=caster.id, xp_cost = skill.xp_cost, hp_cost = skill.hp_cost, gold_cost = skill.gold_cost, atk_cost = skill.atk_cost})
									wml.variables["caster_" .. caster.id .. ".spell_to_cast"] = skill.id
									wml.variables["caster_" .. caster.id .. ".spellcasted_this_turn"] = skill.id
									gui.widget.close(dialog)
								end
							end
						end
					end
					initialize_button("button"..i, skill);
					
					-- if this skill has subskills, initialize each button
					if (skill.subskills) then
						for k,subskill in pairs(skill.subskills) do
							initialize_button(subskill.id, subskill, true);
						end
					end
					::continue_unequipped::
				end
			end
		end
    end
	
	
	-------------------------
	-- SHOW DIALOG
	-------------------------
	wesnoth.interface.game_display.selected_unit = nil
	wesnoth.interface.delay(300)
	
    wesnoth.units.select()
	wesnoth.interface.deselect_hex()
    wml.fire("redraw") -- deselect caster
	
	-- select spell, synced
	if (selecting) then
		dialog_result = wesnoth.sync.evaluate_single(function()
            retval = gui.show_dialog( dialog, preshow )
            wml.variables["caster_" .. caster.id .. ".wait_to_select_spells"] = retval==2 and 'yes' or 'no' --not nil, or else the key appears blank
            return result_table
        end)
		
		skills_equipped = {}
		for skill_id,skill_value in pairs(dialog_result) do
		    if skill_value == true then
			    table.insert(skills_equipped, skill_id)
			end
		end
		
		wml.variables["caster_" .. caster.id .. ".spell_equipped"] = table.concat(skills_equipped, ",")
	
	-- cast spells, synced
	else
		dialog_result = wesnoth.sync.evaluate_single(function()
			gui.show_dialog( dialog, preshow )
			if (wml.variables["caster_" .. wml.variables["current_caster"] .. ".spell_to_cast"]) then
			    wml.fire.do_command({
                    wml.tag.fire_event {
                        raise = wml.variables["caster_" .. wml.variables["current_caster"] .. ".spell_to_cast"]
                    }
                })
			    wml.variables["caster_" .. wml.variables["current_caster"] .. ".spell_to_cast"] = nil
			end
		end)
	end

    already_unlocked_list = nil
	skills_equipped = nil
    return
end




--###########################################################################################################################################################
--                                                                      "MAIN"
--###########################################################################################################################################################
-------------------------
-- DEFINE WML TAGS
-------------------------
wml_actions["refresh_skills"] = function(cfg)
    wml.variables ["current_caster"] = cfg.id
	wml.variables["caster_" .. cfg.id .. ".spellcasted_this_turn"] = nil
	wesnoth.game_events.fire(("refresh_skills"))
end

wml_actions["select_caster_skills"] = function(cfg)

    wesnoth.audio.play("miss-2.ogg")
	
	local filter = wml.get_child(cfg, "filter") or
    wml.error "[select_caster_skills] missing required [filter] tag"
	local units = wesnoth.units.find(filter)
	
	for i,u in ipairs(units) do
	    if (wml.variables['is_badly_timed']) then return end
	    wml.variables ["current_caster"] = u.id
		
		if not wml.variables["caster_" .. u.id .. ".utils_spellcasting_allowed"] then
            display_skills_dialog(true)
		    wml.fire("refresh_skills", ({id = u.id}))
		    
	        wml.variables["caster_" .. u.id .. ".spellcasted_this_turn"] = nil
		end
	end
end

wml_actions["show_caster_skills"] = function(cfg)

	wesnoth.audio.play("miss-2.ogg")

	local filter = wml.get_child(cfg, "filter") or
    wml.error "[select_caster_skills] missing required [filter] tag"
	local units = wesnoth.units.find(filter)
	
	for i,u in ipairs(units) do
	    if (wml.variables['is_badly_timed']) then return end
	    wml.variables ["current_caster"] = u.id
	    
        if not wml.variables["caster_" .. u.id .. ".utils_spellcasting_allowed"] then
	        if (wml.variables["caster_" .. u.id .. ".wait_to_select_spells"]) then
                display_skills_dialog(true)
	    		wml.fire("refresh_skills", ({id = u.id}))
	    		wml.variables["caster_" .. u.id .. ".spellcasted_this_turn"] = nil
            else
                display_skills_dialog()
            end
	    end
	end
end

wml_actions["caster_set_menu"] = function(cfg)
    local units = wesnoth.units.find_on_map()
    
    for i,u in ipairs(units) do
        if  wml.variables["caster_" .. u.id] then
    	    wml.fire("clear_menu_item", {
                id = "spellcasting_object_" .. u.id
    		})
    		
			if wml.variables["side_number"] == u.side then
                wml.fire("set_menu_item", {
                    id = "spellcasting_object_" .. u.id,
                    description = _"Cast Spells",
                    synced = false,
                    wml.tag.filter_location {
                        wml.tag.filter { id = u.id, side = wml.variables["side_number"] }
                    },
                    wml.tag.command {
                        wml.tag.show_caster_skills {
                            wml.tag.filter { id = u.id }
                        }
                    },
    		    	wml.tag.show_if {
    		    	    wml.tag.variable {
    		    		    name = "caster_" .. u.id .. ".utils_spellcasting_allowed",
    		    			not_equals = "disabled"
    		    		}
    		    	}
                })
			end
        end
    end
    
    units = nil
end

wml_actions["assign_caster"] = function(cfg)
	local filter = wml.get_child(cfg, "filter") or
    wml.error "[assign_caster] missing required [filter] tag"
	local units = wesnoth.units.find(filter)
	local basic_description, spellcasting_allowed

    for i,u in ipairs(units) do
	
	local writer = utils.vwriter.init(cfg, ("caster_" .. u.id ))
	
	if u.gender == "male" then
	    basic_description = u.name .. " knows many useful spells, and will learn more as he levels-up automatically throughout the campaign. " .. u.name .. " does not use XP to level-up. Instead,\nhe uses XP to cast certain spells. If you select spells that cost XP, <b>double-click on " .. u.name .. " to cast them</b>. You can only cast 1 spell per turn."
	else
	    basic_description = u.name .. " knows many useful spells, and will learn more as she levels-up automatically throughout the campaign. " .. u.name .. " does not use XP to level-up. Instead,\nshe uses XP to cast certain spells. If you select spells that cost XP, <b>double-click on " .. u.name .. " to cast them</b>. You can only cast 1 spell per turn."
	end
	
	if cfg.spellcasting_allowed == false then
	    spellcasting_allowed = "disabled"
	else 
	    spellcasting_allowed = cfg.spellcasting_allowed
	end

    local caster_data_temp = {
        id = u.id,
        u_title_select = cfg.title_select or ("Select " .. u.name .. "’s Spells"),
        u_title_cast = cfg.title_cast or ("Cast " .. u.name .. "’s Spells"),
        u_description = cfg.description or basic_description,
		spell_unlocked = cfg.unlocked_spells or "",
		spell_equipped = cfg.equipped_spells or "",
        spell_group_1 = cfg.spell_group_1,
		spell_group_2 = cfg.spell_group_2,
		spell_group_3 = cfg.spell_group_3,
		spell_group_4 = cfg.spell_group_4,
		spell_group_5 = cfg.spell_group_5,
		spell_group_6 = cfg.spell_group_6,
		spell_group_7 = cfg.spell_group_7,
		spell_group_8 = cfg.spell_group_8,
		spell_group_9 = cfg.spell_group_9,
		spell_group_10 =cfg.spell_group_10,
		utils_spellcasted_this_turn = cfg.spellcasted_this_turn or nil,
		utils_spellcasting_allowed = spellcasting_allowed or nil,
    }
	
	utils.vwriter.write(writer, caster_data_temp)
		
	wml.fire("caster_set_menu")
	
	wml.fire("refresh_skills", ({id = u.id}))
	
	wml.fire.do_command({
        wml.tag.fire_event {
            raise = "magic_system_add_animations"
        }
    })
	
	caster_data_temp, writer = nil
	
	end
end

wml_actions["refresh_caster_animations"] = function(cfg)
	local filter = wml.get_child(cfg, "filter") or
    wml.error "[refresh_caster_animations] missing required [filter] tag"
	local units = wesnoth.units.find(filter)

    for i,u in ipairs(units) do
	
	    if wml.variables["caster_" .. u.id] then
		    wml.fire.remove_object({
                id = u.id,
				object_id = "magic_system_animations"
            })  
		    wml.variables["current_caster"] = u.id  
		    wml.fire.do_command({
                wml.tag.fire_event {
                    raise = "magic_system_add_animations"
                }
            })    
	    end
	end
end

wml_actions["modify_caster"] = function(cfg)
	local filter = wml.get_child(cfg, "filter") or
    wml.error "[modify_caster] missing required [filter] tag"
	local units = wesnoth.units.find(filter)
	local basic_description

    for i,u in ipairs(units) do
	    if wml.variables["caster_" .. u.id] then
	        wml.variables["caster_" .. u.id .. ".u_title_select"] = cfg.title_select or wml.variables["caster_" .. u.id .. ".u_title_select"]
	    	wml.variables["caster_" .. u.id .. ".u_title_cast"] = cfg.title_cast or wml.variables["caster_" .. u.id .. ".u_title_cast"]
	    	wml.variables["caster_" .. u.id .. ".u_description"] = cfg.description or wml.variables["caster_" .. u.id .. ".u_description"]
	    	wml.variables["caster_" .. u.id .. ".spell_unlocked"] = cfg.unlocked_spells or wml.variables["caster_" .. u.id .. ".spell_unlocked"]
	    	wml.variables["caster_" .. u.id .. ".spell_equipped"] = cfg.equipped_spells or wml.variables["caster_" .. u.id .. ".spell_equipped"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_1"] = cfg.spell_group_1 or wml.variables["caster_" .. u.id .. ".spell_group_1"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_2"] = cfg.spell_group_2 or wml.variables["caster_" .. u.id .. ".spell_group_2"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_3"] = cfg.spell_group_3 or wml.variables["caster_" .. u.id .. ".spell_group_3"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_4"] = cfg.spell_group_4 or wml.variables["caster_" .. u.id .. ".spell_group_4"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_5"] = cfg.spell_group_5 or wml.variables["caster_" .. u.id .. ".spell_group_5"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_6"] = cfg.spell_group_6 or wml.variables["caster_" .. u.id .. ".spell_group_6"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_7"] = cfg.spell_group_7 or wml.variables["caster_" .. u.id .. ".spell_group_7"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_8"] = cfg.spell_group_8 or wml.variables["caster_" .. u.id .. ".spell_group_8"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_9"] = cfg.spell_group_9 or wml.variables["caster_" .. u.id .. ".spell_group_9"]
	    	wml.variables["caster_" .. u.id .. ".spell_group_10"] = cfg.spell_group_10 or wml.variables["caster_" .. u.id .. ".spell_group_10"]
	    	wml.variables["caster_" .. u.id .. ".utils_spellcasted_this_turn"] = cfg.spellcasted_this_turn or wml.variables["caster_" .. u.id .. ".utils_spellcasted_this_turn"]
	    	wml.variables["caster_" .. u.id .. ".utils_spellcasting_allowed"] = cfg.spellcasting_allowed or wml.variables["caster_" .. u.id .. ".utils_spellcasting_allowed"]
	    	
	        wml.fire("refresh_skills", ({id = u.id}))
	    else
	        wml.fire("assign_caster", cfg)
	    end
	end
end

wml_actions["unlock_spell"] = function(cfg)
    if cfg.spell_id then
        local spell_to_modify = {}
	    local filter = wml.get_child(cfg, "filter") or
        wml.error "[unlocked_spell] missing required [filter] tag"
	    local units = wesnoth.units.find(filter)
        for spell in cfg.spell_id:gmatch("[^,]+") do
            table.insert(spell_to_modify, spell)
        end
	    
        for i,u in ipairs(units) do
	    
	        if wml.variables["caster_" .. u.id] then
	    	
	    	    local already_unlocked_list = {}
	    	    for spell in wml.variables["caster_" .. u.id .. ".spell_unlocked"]:gmatch("[^,]+") do
                    table.insert(already_unlocked_list, spell)
                end
	    				
	            for _, spell in ipairs(spell_to_modify) do
                    local already_unlocked = false
                    for _, unlocked_spell in ipairs(already_unlocked_list) do
                        if spell == unlocked_spell then
                            already_unlocked = true
                            break
                        end
                    end
                    if not already_unlocked then
	    				wml.variables["caster_" .. u.id .. ".spell_unlocked"] = wml.variables["caster_" .. u.id .. ".spell_unlocked"] .. "," .. spell
                    end
                end
	        end
	    end
	end
end

wml_actions["lock_spell"] = function(cfg)
    if cfg.spell_id then
        local spell_to_modify = {}
	    local filter = wml.get_child(cfg, "filter") or
        wml.error "[lock_spell] missing required [filter] tag"
	    local units = wesnoth.units.find(filter)
        for spell in cfg.spell_id:gmatch("[^,]+") do
            table.insert(spell_to_modify, spell)
        end
	    
        for i,u in ipairs(units) do
	        if wml.variables["caster_" .. u.id] then
	            local already_unlocked_list = {}
	            for spell in wml.variables["caster_" .. u.id .. ".spell_unlocked"]:gmatch("[^,]+") do
                    table.insert(already_unlocked_list, spell)
                end
	            
                for _, spell in ipairs(spell_to_modify) do
                for i = #already_unlocked_list, 1, -1 do
                    if already_unlocked_list[i] == spell then
                        table.remove(already_unlocked_list, i)
                        wesnoth.interface.add_chat_message("Locked spell", spell)
                    end
                end
            end
            
            wml.variables["caster_" .. u.id .. ".spell_unlocked"] = table.concat(already_unlocked_list, ",")
	        end
	    end
	end
end

wml_actions["caster_status"] = function(cfg)
	local filter = wml.get_child(cfg, "filter") or
    wml.error "[caster_status] missing required [filter] tag"
	local units = wesnoth.units.find(filter)

    for i,u in ipairs(units) do
	    if wml.variables["caster_" .. u.id] then
		    if cfg.spellcasting_allowed == true then
			    wml.variables["caster_" .. u.id .. ".utils_spellcasting_allowed"] = nil
			else
			    wml.variables["caster_" .. u.id .. ".utils_spellcasting_allowed"] = "disabled"
			end 
        end
	end
	
	units = nil
	
	wml.fire("caster_set_menu")
end

wml_actions["equip_spell"] = function(cfg)
    if not cfg.spell_id then return end
    
    local filter = wml.get_child(cfg, "filter") or wml.error "[equip_spell] missing required [filter] tag"
    local units = wesnoth.units.find(filter)
    local spell_to_modify = {}
    
    for spell in cfg.spell_id:gmatch("[^,]+") do
        table.insert(spell_to_modify, spell)
    end
    
    for _, u in ipairs(units) do
        local spell_to_equip = {}
        local equipped_var = wml.variables["caster_" .. u.id .. ".spell_equipped"] or ""
        
        for spell in equipped_var:gmatch("[^,]+") do
            table.insert(spell_to_equip, spell)
        end
        
        for i = 1, 10 do
            local group_var = wml.variables["caster_" .. u.id .. ".spell_group_" .. i]
            if group_var then
                local spell_to_compare = {}
                
                for spell in group_var:gmatch("[^,]+") do
                    table.insert(spell_to_compare, spell)
                end
                
                for _, spell in ipairs(spell_to_modify) do
                    local found = false
                    for _, s in ipairs(spell_to_compare) do
                        if s == spell then
                            found = true
                            break
                        end
                    end
                    if found then
                        for j = #spell_to_equip, 1, -1 do
                            local remove_spell = false
                            for _, s in ipairs(spell_to_compare) do
                                if s == spell_to_equip[j] then
                                    remove_spell = true
                                    break
                                end
                            end
                            if remove_spell then
                                table.remove(spell_to_equip, j)
                            end
                        end
                        table.insert(spell_to_equip, spell)
                    end
                end
            end
        end
        
        wml.variables["caster_" .. u.id .. ".spell_equipped"] = table.concat(spell_to_equip, ",")
        wml.fire("refresh_skills", { id = u.id })
    end
end

wml_actions["unequip_spell"] = function(cfg)
    if not cfg.spell_id then return end
	
    local filter = wml.get_child(cfg, "filter") or wml.error "[unequip_spell] missing required [filter] tag"
    local units = wesnoth.units.find(filter)
    local spell_to_remove = {}
	
    for spell in cfg.spell_id:gmatch("[^,]+") do
        table.insert(spell_to_remove, spell)
    end

    for _, u in ipairs(units) do
        local spell_to_equip = {}
        local equipped_var = wml.variables["caster_" .. u.id .. ".spell_equipped"] or ""

        for spell in equipped_var:gmatch("[^,]+") do
            table.insert(spell_to_equip, spell)
        end

        for _, spell in ipairs(spell_to_remove) do
            for i = #spell_to_equip, 1, -1 do
                if spell_to_equip[i] == spell then
                    table.remove(spell_to_equip, i)
                end
            end
        end
        wml.variables["caster_" .. u.id .. ".spell_equipped"] = table.concat(spell_to_equip, ",")
        wml.fire("refresh_skills", { id = u.id })
    end
end

wml_actions["find_equipped_spell"] = function(cfg)
    if not cfg.spell_id then
	wml.variables["equipped_spell_found"] = false
	return
	end
    
    local filter = wml.get_child(cfg, "filter") or wml.error "[find_equipped_spell] missing required [filter] tag"
    local units = wesnoth.units.find(filter)
    
    for _, u in ipairs(units) do
        local equipped_var = wml.variables["caster_" .. u.id .. ".spell_equipped"] or ""
        
        for spell in equipped_var:gmatch("[^,]+") do
            if spell == cfg.spell_id then
                wml.variables["equipped_spell_found"] = true
                return
            end
        end
    end
    
    wml.variables["equipped_spell_found"] = false
end

wml_actions["find_unlocked_spell"] = function(cfg)
    if not cfg.spell_id then
	wml.variables["equipped_unlocked_found"] = false
	return
	end
    
    local filter = wml.get_child(cfg, "filter") or wml.error "[find_unlocked_spell] missing required [filter] tag"
    local units = wesnoth.units.find(filter)
    
    for _, u in ipairs(units) do
        local unlocked_var = wml.variables["caster_" .. u.id .. ".spell_unlocked"] or ""
        
        for spell in unlocked_var:gmatch("[^,]+") do
            if spell == cfg.spell_id then
                wml.variables["equipped_unlocked_found"] = true
                return
            end
        end
    end
    
    wml.variables["equipped_unlocked_found"] = false
end

wml_actions["remove_caster"] = function(cfg)
	local filter = wml.get_child(cfg, "filter") or
    wml.error "[remove_caster] missing required [filter] tag"
	local units = wesnoth.units.find(filter)

    for i,u in ipairs(units) do
	    if wml.variables["caster_" .. u.id] then
		    wml.variables["caster_" .. u.id] = nil
			
			wml.fire.remove_object({
                id = u.id,
				object_id = "magic_system_animations"
            })  
			
			wml.fire("clear_menu_item", {
                id = "spellcasting_object_" .. u.id
    		})
        end
	end
end




-------------------------
-- DETECT DOUBLECLICKS
-------------------------
local last_click = os.clock()
wesnoth.game_events.on_mouse_action = function(x,y)
	local selected_unit = wesnoth.units.find_on_map{ x=x, y=y }
	
	if (not selected_unit[1]) then return end
	if wml.variables["caster_" .. selected_unit[1].id] then
	    if (wml.variables['is_badly_timed']) then return end
	    
		wml.variables['current_caster'] = selected_unit[1].id
	    
	    if (os.clock()-last_click<0.25) then
	    	wesnoth.audio.play("miss-2.ogg")
	    
	    	if not wml.variables["caster_" .. wml.variables['current_caster'] .. ".utils_spellcasting_allowed"] then
	    	    if (wml.variables["caster_" .. wml.variables['current_caster'] .. ".wait_to_select_spells"]) then
                    display_skills_dialog(true)
                else
                    display_skills_dialog()
                end
	    	end
	    	
	    	last_click = 0 -- prevent accidentally immediately re-opening the dialog
	    else
	    	last_click = os.clock()
	    end
	end
end

-------------------------
-- DETECT MOUSEMOVES
-------------------------
function wml_actions.listen_for_mousemove(cfg)
	wesnoth.game_events.on_mouse_move = function(x,y)
		wesnoth.game_events.fire('mousemove_synced', x, y)
		wesnoth.game_events.on_mouse_move = nil --only trigger once
	end
end
