----------------------------------------------------------------
-------------------CHESS----------------------------------------
----------------------------------------------------------------
local _ = wesnoth.textdomain "wesnoth-ctl"
local utils = wesnoth.require "wml-utils"

function ctl_chess_get_piece_type(chess_id)
    local chess_piece = (wesnoth.units.find_on_map({id = chess_id})) [1]
    local ctl_chess_type
	if chess_piece.type == "Peasant" or chess_piece.type == "Walking Corpse" then
	    ctl_chess_type = ctl_chess_moveset_pawn
	elseif chess_piece.type == "Daeola_L1_Mage" or chess_piece.type == "Wesfolk Princess" then
	    ctl_chess_type = ctl_chess_moveset_queen
    elseif chess_piece.type == "Haralin_L2" or chess_piece.type == "Lenvan" then
	    ctl_chess_type = ctl_chess_moveset_king
    elseif chess_piece.type == "Highwayman_Peasant" or chess_piece.type == "Bone Skeleton" then
	    ctl_chess_type = ctl_chess_moveset_rook
    elseif chess_piece.type == "Knight" or chess_piece.type == "Wesfolk Chariot" then
	    ctl_chess_type = ctl_chess_moveset_knight
    elseif chess_piece.type == "Lieutenant" or chess_piece.type == "Death Squire" then
	    ctl_chess_type = ctl_chess_moveset_bishop	
    end	

    return ctl_chess_type
end

function ctl_chess_get_piece_moves(chess_id)
    local chess_piece = wesnoth.units.find_on_map{ id = chess_id }[1]
	local ctl_chess_all_moves = {}
        if chess_piece.id:sub(1, 5) == "Chess" then
			local ctl_chess_type = ctl_chess_get_piece_type(chess_piece.id)
			local moves = ctl_chess_type(chess_piece.id, false, false, true)

            if moves then
                table.insert(ctl_chess_all_moves, {
                    id = chess_piece.id,
                    moves = moves
                })
			end
        end

    return ctl_chess_all_moves
end

function ctl_chess_get_all_moves(chess_side) 
    local all_chess_pieces = wesnoth.units.find_on_map{ side = chess_side }
	local ctl_chess_all_moves = {}

    for _, chess_piece in ipairs(all_chess_pieces) do
        if chess_piece.id:sub(1, 5) == "Chess" then
            local ctl_chess_type = ctl_chess_get_piece_type(chess_piece.id)
			local moves = ctl_chess_type(chess_piece.id, false, false, true)

            if moves then
                table.insert(ctl_chess_all_moves, {
                    id = chess_piece.id,
                    moves = moves
                })
			end
        end
    end

    return ctl_chess_all_moves
end

function ctl_chess_get_excluded_moves(chess_id)
    local chess_piece = wesnoth.units.find_on_map{ id = chess_id} [1]
    local all_moves_side
	local king_side = chess_piece.side
	
	if chess_piece.side == 1 then
	    all_moves_side = 2
	else
	    all_moves_side = 1
	end
	 
    local king = wesnoth.units.find_on_map{
        side = king_side,
        type = {"Haralin_L2", "Lenvan"}
    } [1]
	
	if king then
	
	    local excluded_moves = {}
		
		--перевірка усіх ходів чи викликають вони шах
		--отримуємо всі можливі кроки фігури
		local chess_piece_moves = ctl_chess_get_piece_moves(chess_id)
		
		local initial_chess_piece_x = chess_piece.x
		local initial_chess_piece_y = chess_piece.y
		
		for _, friendly_data in ipairs(chess_piece_moves) do
		    local friendly_moves = friendly_data.moves
			
			if friendly_moves and #friendly_moves > 0 then
			    for _, friendly_move in ipairs(friendly_moves) do
				
				    local has_unit = wesnoth.units.find_on_map({x = friendly_move.x, y = friendly_move.y}) [1]
					
					local initial_enemy_x, initial_enemy_y
					
					if has_unit and has_unit.id ~= chess_piece.id then
					    initial_enemy_x = has_unit.x
					    initial_enemy_y = has_unit.y
						has_unit.x = 1
						has_unit.y = 1
					end

					wml.fire("modify_unit", {
                        wml.tag.filter {
                            id = chess_piece.id
                        },
						x = friendly_move.x,
						y = friendly_move.y
                    })

		            local all_enemy_moves =  ctl_chess_get_all_moves(all_moves_side)
	                
	                for _, enemy_data in ipairs(all_enemy_moves) do
                        local enemy_id = enemy_data.id
                        local enemy_moves = enemy_data.moves
	                
                        if enemy_moves and #enemy_moves > 0 then
                            for _, enemy_move in ipairs(enemy_moves) do
                                -- перевірка, чи координати ходу збігаються з позицією короля
                                if enemy_move.x == king.x and enemy_move.y == king.y then
									
									table.insert(excluded_moves, {
                                        id = chess_piece.id,
                                        moves = friendly_move
                                    })
                                end
                            end
                        end
                    end
					
					wml.fire("modify_unit", {
                        wml.tag.filter {
                            id = chess_piece.id
                        },
						x = initial_chess_piece_x,
						y = initial_chess_piece_y
                    })
					
					if has_unit and has_unit.x == 1 and has_unit.y == 1 and has_unit.id ~= chess_piece.id then
					    has_unit.x = initial_enemy_x
					    has_unit.y = initial_enemy_y
					end
					
				end
		    end
		end
		
		wml.fire("modify_unit", {
            wml.tag.filter {
                id = chess_piece.id
            },
			x = initial_chess_piece_x,
			y = initial_chess_piece_y
        })
		
		return excluded_moves
		
	end
end

function ctl_chess_exclude_moves(move_table, exclude_table, image_move, image_attack)
    local selected_target_hexes = move_table
	local excluded_target_hexes = exclude_table
    for i = #selected_target_hexes, 1, -1 do
        local sel = selected_target_hexes[i]
        for _, excl in ipairs(excluded_target_hexes) do
            -- якщо координати збігаються
            if sel.x == excl.moves.x and sel.y == excl.moves.y then
			    wesnoth.wml_actions.remove_item({
                    image = image_move,
					x = sel.x,
					y = sel.y
                })
				wesnoth.wml_actions.remove_item({
                    image = image_attack,
					x = sel.x,
					y = sel.y
                })
                table.remove(selected_target_hexes, i)
                break
            end
        end
    end
	
	return selected_target_hexes
end

--як показала практика, треба перевіряти усіх унітів, а не лише того, який ходив
function ctl_chess_check(chess_id)
    local chess_piece = wesnoth.units.find_on_map{ id = chess_id} [1]
	local king_side
	
	if chess_piece.side == 1 then
	    king_side = 2
	else
	    king_side = 1
	end
	 
    local king = wesnoth.units.find_on_map{
        side = king_side,
        type = {"Haralin_L2", "Lenvan"}
    } [1]
	
	if king then

		--перевірка усіх ходів чи викликають вони шах
		--отримуємо всі можливі кроки фігури
		
		local check
		local chess_piece_moves = ctl_chess_get_all_moves(chess_piece.side)
		
		for _, friendly_data in ipairs(chess_piece_moves) do
            local friendly_moves = friendly_data.moves
	    
            if friendly_moves and #friendly_moves > 0 then
                for _, friendly_move in ipairs(friendly_moves) do
                    -- перевірка, чи координати ходу збігаються з позицією короля
                    if friendly_move.x == king.x and friendly_move.y == king.y then
	   			        wesnoth.interface.add_chat_message("Info", ("Шах! | Check!"))
				        ctl_chess_place_image(king.x, king.y, "misc/summon.png")
	   			        check = true
					    break
				    end
                end
            end
        end
		
		--перевірка на мат
		    local all_enemy_chess_pieces = wesnoth.units.find_on_map{ side = king_side }
		    local checkmate = true
		    
		    for _, enemy_chess_piece in ipairs(all_enemy_chess_pieces) do
                if enemy_chess_piece.id:sub(1, 5) == "Chess" then
				    local ctl_chess_type = ctl_chess_get_piece_type(enemy_chess_piece.id)
		            local selected_target_hexes = ctl_chess_type(enemy_chess_piece.id, "misc/buff.png", "misc/attack.png", true)
	                local excluded_target_hexes = ctl_chess_get_excluded_moves(enemy_chess_piece.id)
	                selected_target_hexes = ctl_chess_exclude_moves(selected_target_hexes, excluded_target_hexes, "misc/buff.png", "misc/attack.png")
		    		
		    		if #selected_target_hexes > 0 then
                        checkmate = false
                        break
                    end
		        end
		    end
		    
		    if checkmate and check then
                wesnoth.interface.add_chat_message("Info", ("МАТ! | CHECKMATE!"))
		    	return checkmate
            end
			
			if checkmate and not check then
                wesnoth.interface.add_chat_message("Info", ("ПАТ! | STALEMATE!"))
		    	return checkmate
            end
		
	end
end

function ctl_chess_advance(chess_type, chess_x, chess_y)
    --верхні та нижні границі карти. Вони не є прямими, тому доводиться робити набори координат
	if chess_y == 4 or chess_y == 10 or (chess_x == 11 and chess_y == 5) or (chess_x == 10 and chess_y == 9) or (chess_x == 11 and chess_y == 9) or (chess_x == 12 and chess_y == 9) then
		wml.fire("modify_unit", {
            experience = 30,
            wml.tag.filter {
                x = chess_x,
                y = chess_y
            }
        })
		
		wml.fire("modify_unit", {
            experience = 0,
            wml.tag.filter {
                x = chess_x,
                y = chess_y
            }
        })
	end
end

function ctl_chess_move(chess_id, chess_type, chess_x, chess_y)
    wml.fire.kill({
        x = chess_x,
		y = chess_y,
		force_scroll = false
    })
	
	ctl_chess_remove_image("misc/highlight-hex.png")
	
    wml.fire.move_unit({
        id = chess_id,
		to_x = chess_x,
		to_y = chess_y,
		force_scroll = false
    })
	
	wesnoth.interface.end_turn()
	
	wml.variables["ctl_chess_active"] = true
end

function ctl_chess_select_cancel(image_move, image_attack, chess_debug)
    if not chess_debug then
        ctl_chess_remove_image(image_move)
	    ctl_chess_remove_image(image_attack)
	    ctl_chess_remove_image("misc/highlight-hex.png")
        wml.fire("redraw")
	end
	
    wesnoth.game_events.on_mouse_button = nil

    wesnoth.units.select()
	
	wml.variables["ctl_chess_active"] = true
end

function ctl_chess_place_image(x, y, image)
    wesnoth.wml_actions.item({
        x = x,
        y = y,
        image = image
    })
end

function ctl_chess_remove_image(image)
    wesnoth.wml_actions.remove_item({
        image = image
    })
end

function ctl_chess_calculate_next_coors(x, y, direction)
    local new_x, new_y = x, y

    if direction == "ne" then
        if y % 2 == 1 and x % 2 == 0 then
            -- y непарний, x парний
            new_y = y
    		new_x = x + 1
        elseif y % 2 == 1 and x % 2 == 1 then
            -- y непарний, x непарний
            new_y = y - 1
            new_x = x + 1
        elseif y % 2 == 0 and x % 2 == 0 then
            -- y парний, x парний
            new_y = y
            new_x = x + 1
        elseif y % 2 == 0 and x % 2 == 1 then
            -- y парний, x непарний
            new_y = y - 1
    		new_x = x + 1
        end
    elseif direction == "nw" then
        if y % 2 == 1 and x % 2 == 0 then
            -- y непарний, x парний
            new_y = y
    		new_x = x - 1
        elseif y % 2 == 1 and x % 2 == 1 then
            -- y непарний, x непарний
            new_y = y - 1
            new_x = x - 1
        elseif y % 2 == 0 and x % 2 == 0 then
            -- y парний, x парний
            new_y = y
            new_x = x - 1
        elseif y % 2 == 0 and x % 2 == 1 then
            -- y парний, x непарний
            new_y = y - 1
    		new_x = x - 1
        end
    elseif direction == "n" then
            new_y = y - 1
    		new_x = x
    elseif direction == "s" then
            new_y = y + 1
    		new_x = x
    elseif direction == "sw" then
        if y % 2 == 1 and x % 2 == 0 then
            -- y непарний, x парний
            new_y = y + 1
    		new_x = x - 1
        elseif y % 2 == 1 and x % 2 == 1 then
            -- y непарний, x непарний
            new_y = y
            new_x = x - 1
        elseif y % 2 == 0 and x % 2 == 0 then
            -- y парний, x парний
            new_y = y + 1
            new_x = x - 1
        elseif y % 2 == 0 and x % 2 == 1 then
            -- y парний, x непарний
            new_y = y
    		new_x = x - 1
        end
    elseif direction == "se" then
        if y % 2 == 1 and x % 2 == 0 then
            -- y непарний, x парний
            new_y = y + 1
    		new_x = x + 1
        elseif y % 2 == 1 and x % 2 == 1 then
            -- y непарний, x непарний
            new_y = y
            new_x = x + 1
        elseif y % 2 == 0 and x % 2 == 0 then
            -- y парний, x парний
            new_y = y + 1
            new_x = x + 1
        elseif y % 2 == 0 and x % 2 == 1 then
            -- y парний, x непарний
            new_y = y
    		new_x = x + 1
        end
    end
    
        return new_x, new_y
end

--king
function ctl_chess_moveset_king(chess_id, image_move, image_attack, chess_debug)
    local selected_target_hexes = {}

    local chess_piece = (wesnoth.units.find_on_map({id = chess_id})) [1]

    for xx = chess_piece.x - 1, chess_piece.x + 1 do
        for yy = chess_piece.y - 1, chess_piece.y + 1 do
            if wesnoth.map.distance_between(chess_piece.x, chess_piece.y, xx, yy) <= 1 then
                local target_units = (wesnoth.units.find_on_map({ x = xx, y = yy }))
                local has_unit = #target_units > 0
                local void_terrain = wesnoth.map.find({x = xx, y= yy, terrain = "_off^_usr"})
                local has_void_terrain = #void_terrain > 0

                if (not has_void_terrain and not has_unit) and (xx ~= chess_piece.x or yy ~= chess_piece.y) then
                    if not chess_debug then ctl_chess_place_image(xx, yy, image_move) end
                    table.insert(selected_target_hexes, { x = xx, y = yy })
				elseif (not has_void_terrain and has_unit and wesnoth.sides[chess_piece.side].side ~= wesnoth.sides[target_units[1].side].side) then
				    if not chess_debug then ctl_chess_place_image(xx, yy, image_attack) end
                    table.insert(selected_target_hexes, { x = xx, y = yy })
				end
            end
        end
    end
	
	if chess_debug then
	    ctl_chess_select_cancel(image_move, image_attack, true)
    end
	
	return selected_target_hexes
end

--queen
function ctl_chess_moveset_queen(chess_id, image_move, image_attack, chess_debug)
    local selected_target_hexes = {}
	
    local chess_piece = wesnoth.units.find_on_map({id = chess_id})[1]

    local directions = {"n","s","ne","nw","sw","se"}

    for _, dir in ipairs(directions) do
        local target_x = chess_piece.x
        local target_y = chess_piece.y

        for step = 1, 10 do
            target_x, target_y = ctl_chess_calculate_next_coors(target_x, target_y, dir)

            local target_units = wesnoth.units.find_on_map({x = target_x, y = target_y})
            local has_unit = #target_units > 0
            local void_terrain = wesnoth.map.find({x = target_x, y= target_y, terrain = "_off^_usr"})
            local has_void_terrain = #void_terrain > 0

            if (not has_void_terrain and not has_unit) then
                if not chess_debug then ctl_chess_place_image(target_x, target_y, image_move) end
                table.insert(selected_target_hexes, {x = target_x, y = target_y, id = step, direction = dir})
			elseif (not has_void_terrain and has_unit and wesnoth.sides[chess_piece.side].side ~= wesnoth.sides[target_units[1].side].side) then
			    if not chess_debug then ctl_chess_place_image(target_x, target_y, image_attack) end
                table.insert(selected_target_hexes, {x = target_x, y = target_y, id = step, direction = dir})
				break
            else break end
        end
    end
	
	if chess_debug then
	    ctl_chess_select_cancel(image_move, image_attack, true)
    end
	
	return selected_target_hexes
end

--pawn
function ctl_chess_moveset_pawn(chess_id, image_move, image_attack, chess_debug)
    local selected_target_hexes = {}

    local chess_piece = wesnoth.units.find_on_map({id = chess_id})[1]
	
	local directions

    if chess_piece.side == 1 then
        directions = {"n","ne","nw"}
	else 
	    directions = {"s","se","sw"}
	end

    for _, dir in ipairs(directions) do
        local target_x = chess_piece.x
        local target_y = chess_piece.y
		local radius
		
		--starting coords of pawns
		if ((target_x == 9 and target_y == 9) or (target_x == 10 and target_y == 8)
        or (target_x == 11 and target_y == 8) or (target_x == 12 and target_y == 8)
        or (target_x == 13 and target_y == 9)) and chess_piece.side == 1 then
            radius = 2
        elseif ((target_x == 9 and target_y == 5) or (target_x == 10 and target_y == 5)
            or (target_x == 11 and target_y == 6) or (target_x == 12 and target_y == 5)
            or (target_x == 13 and target_y == 5)) and chess_piece.side ~= 1 then
            radius = 2
        else
            radius = 1
        end

        for step = 1, radius do
            target_x, target_y = ctl_chess_calculate_next_coors(target_x, target_y, dir)

            local target_units = wesnoth.units.find_on_map({x = target_x, y = target_y})
            local has_unit = #target_units > 0
            local void_terrain = wesnoth.map.find({x = target_x, y= target_y, terrain = "_off^_usr"})
            local has_void_terrain = #void_terrain > 0

            if (not has_void_terrain and not has_unit) then
				if dir == "n" or dir == "s" then
				    if not chess_debug then ctl_chess_place_image(target_x, target_y, image_move) end
                    table.insert(selected_target_hexes, {x = target_x, y = target_y, id = step, direction = dir})
				end
			elseif (not has_void_terrain and has_unit and wesnoth.sides[chess_piece.side].side ~= wesnoth.sides[target_units[1].side].side) then
			    if step == 1 then
				    if dir ~= "n" and dir ~= "s" then
				        if not chess_debug then ctl_chess_place_image(target_x, target_y, image_attack) end
                        table.insert(selected_target_hexes, {x = target_x, y = target_y, id = step, direction = dir})
				    end
				    break
				end
            else break end
        end
    end
	
	if chess_debug then
	    ctl_chess_select_cancel(image_move, image_attack, true)
    end
	
	return selected_target_hexes
end
 
--rook
 function ctl_chess_moveset_rook(chess_id, image_move, image_attack, chess_debug)
    local selected_target_hexes = {}

    local chess_piece = wesnoth.units.find_on_map({id = chess_id})[1]

    local directions = {"n","s"}

    for _, dir in ipairs(directions) do
        local target_x = chess_piece.x
        local target_y = chess_piece.y

        for step = 1, 10 do
            target_x, target_y = ctl_chess_calculate_next_coors(target_x, target_y, dir)

            local target_units = wesnoth.units.find_on_map({x = target_x, y = target_y})
            local has_unit = #target_units > 0
			local void_terrain = wesnoth.map.find({x = target_x, y= target_y, terrain = "_off^_usr"})
            local has_void_terrain = #void_terrain > 0

            if (not has_void_terrain and not has_unit) then
                if not chess_debug then ctl_chess_place_image(target_x, target_y, image_move) end
                table.insert(selected_target_hexes, {x = target_x, y = target_y, id = step, direction = dir})
            elseif (not has_void_terrain and has_unit and wesnoth.sides[chess_piece.side].side ~= wesnoth.sides[target_units[1].side].side) then
                if not chess_debug then ctl_chess_place_image(target_x, target_y, image_attack) end
                table.insert(selected_target_hexes, {x = target_x, y = target_y, id = step, direction = dir})
				break
            else break end
        end
    end
	
	if chess_debug then
	    ctl_chess_select_cancel(image_move, image_attack, true)
    end
	
	return selected_target_hexes
 end

--bishop
function ctl_chess_moveset_bishop(chess_id, image_move, image_attack, chess_debug)
    local selected_target_hexes = {}

    local chess_piece = wesnoth.units.find_on_map({id = chess_id})[1]

    local directions = {"ne","nw","sw","se"}

    for _, dir in ipairs(directions) do
        local target_x = chess_piece.x
        local target_y = chess_piece.y

        for step = 1, 10 do
            target_x, target_y = ctl_chess_calculate_next_coors(target_x, target_y, dir)

            local target_units = wesnoth.units.find_on_map({x = target_x, y = target_y})
            local has_unit = #target_units > 0
            local void_terrain = wesnoth.map.find({x = target_x, y= target_y, terrain = "_off^_usr"})
            local has_void_terrain = #void_terrain > 0

            if (not has_void_terrain and not has_unit) then
                if not chess_debug then ctl_chess_place_image(target_x, target_y, image_move) end
                table.insert(selected_target_hexes, {x = target_x, y = target_y, id = step, direction = dir})
            elseif (not has_void_terrain and has_unit and wesnoth.sides[chess_piece.side].side ~= wesnoth.sides[target_units[1].side].side) then
			    if not chess_debug then ctl_chess_place_image(target_x, target_y, image_attack) end
                table.insert(selected_target_hexes, {x = target_x, y = target_y, id = step, direction = dir})
				break
			else break end
        end
    end
	
	if chess_debug then
	    ctl_chess_select_cancel(image_move, image_attack, true)
    end
	
	return selected_target_hexes
end

--knight
function ctl_chess_moveset_knight(chess_id, image_move, image_attack, chess_debug)
    local selected_target_hexes = {}

    local chess_piece = (wesnoth.units.find_on_map({id = chess_id})) [1]

    for xx = chess_piece.x - 3, chess_piece.x + 3 do
        for yy = chess_piece.y - 3, chess_piece.y + 3 do
            if wesnoth.map.distance_between(chess_piece.x, chess_piece.y, xx, yy) <= 3 then
                local target_units = (wesnoth.units.find_on_map({ x = xx, y = yy }))
                local has_unit = #target_units > 0
                local void_terrain = wesnoth.map.find({x = xx, y= yy, terrain = "_off^_usr"})
                local has_void_terrain = #void_terrain > 0
				local castle_terrain = wesnoth.map.find({x = xx, y= yy, terrain = "Kha"})
                local has_castle_terrain = #castle_terrain > 0
				
				if wesnoth.map.distance_between(chess_piece.x, chess_piece.y, xx, yy) == 3 then

                if (not has_void_terrain and not has_unit and not has_castle_terrain) and (xx ~= chess_piece.x or yy ~= chess_piece.y) then
                    if not chess_debug then ctl_chess_place_image(xx, yy, image_move) end
                    table.insert(selected_target_hexes, { x = xx, y = yy })
				elseif (not has_castle_terrain and not has_void_terrain and has_unit and wesnoth.sides[chess_piece.side].side ~= wesnoth.sides[target_units[1].side].side) then
				    if not chess_debug then ctl_chess_place_image(xx, yy, image_attack) end
                    table.insert(selected_target_hexes, { x = xx, y = yy })
				end
				
				end
            end
        end
    end
	
	local directions = {"n","s","ne","nw","sw","se"}

    for _, dir in ipairs(directions) do
        local target_x = chess_piece.x
        local target_y = chess_piece.y

        for step = 1, 3 do
            target_x, target_y = ctl_chess_calculate_next_coors(target_x, target_y, dir)
			if step == 3 then
			    if not chess_debug then
				    wesnoth.wml_actions.remove_item({
                        image = image_move,
				    	x = target_x,
				    	y = target_y
                    })
				    wesnoth.wml_actions.remove_item({
                        image = image_attack,
				    	x = target_x,
				    	y = target_y
                    })
				end
			    for i, hex in ipairs(selected_target_hexes) do
                    if hex.x == target_x and hex.y == target_y then
                        table.remove(selected_target_hexes, i)
                        break
                    end
                end
			end
        end
    end
	
	if chess_debug then
	    ctl_chess_select_cancel(image_move, image_attack, true)
    end
	
	return selected_target_hexes
end

--select chess piece
function ctl_chess_select(chess_type, chess_id, image_move, image_attack)
    
	local selected_target_hexes = chess_type(chess_id, image_move, image_attack, false)
	local excluded_target_hexes = ctl_chess_get_excluded_moves(chess_id)
	selected_target_hexes = ctl_chess_exclude_moves(selected_target_hexes, excluded_target_hexes, image_move, image_attack)
	
    wesnoth.game_events.on_mouse_button = function(screen_x, screen_y, button, pressed)
        if pressed and button == "left" then
			wesnoth.sync.invoke_command("ctl_chess", {type="_click", x=screen_x, y=screen_y, chess_id = chess_id, image_move = image_move, image_attack = image_attack})
        end
    end
end

--click on selected piece
function ctl_chess_click(Table)
    local chess_piece = (wesnoth.units.find_on_map({id = Table.chess_id})) [1]
	
	local ctl_chess_type = ctl_chess_get_piece_type(chess_piece.id)
	
	--використовуємо chess_debug, щоб не створювати дуплікати картинок
	local selected_target_hexes = ctl_chess_type(Table.chess_id, Table.image_move, Table.image_attack, true)
	local excluded_target_hexes = ctl_chess_get_excluded_moves(Table.chess_id)
	selected_target_hexes = ctl_chess_exclude_moves(selected_target_hexes, excluded_target_hexes, Table.image_move, Table.image_attack)

    for _, target_hex in ipairs(selected_target_hexes) do
        if Table.x == target_hex.x and Table.y == target_hex.y then
            ctl_chess_remove_image(Table.image_move)
			ctl_chess_remove_image(Table.image_attack)
			ctl_chess_remove_image("misc/summon.png")
            wml.fire("redraw")
            wesnoth.game_events.on_mouse_button = nil
		    
            ctl_chess_move(chess_piece.id, chess_piece.type, Table.x, Table.y)
			ctl_chess_advance(chess_piece.type, Table.x, Table.y)
			
			ctl_chess_checkmate = ctl_chess_check(chess_piece.id)
			if ctl_chess_checkmate then
			    wml.variables["ctl_chess_active"] = false
			    if chess_piece.side == 1 then
				    wml.fire.endlevel({
                        result = "victory",
                    	side = 1
                    })
				else
				    wml.fire.endlevel({
                        result = "victory",
                    	side = 2
                    }) 
				end
			end
		    
            wesnoth.units.select()
            return
        end
    end
    ctl_chess_select_cancel(Table.image_move, Table.image_attack)
end

register_mouse_handler(function(x, y)
	if wml.variables["ctl_chess_active"] ~= true then return end
	
	local selected_unit = wesnoth.units.find_on_map{ x=x, y=y } [1]
	
    if (not selected_unit) then return end
	if (wml.variables['is_badly_timed']) then return end
	
    if selected_unit.id:sub(1, 5) == "Chess" then
    	
		if wesnoth.current.user_is_replaying then return end -- якщо це реплей, то не спавнити діалог. схоже, не працює
	    local chess_side = wesnoth.get_sides({ side = selected_unit.side }) [1]
        if not (chess_side.controller == "human" and chess_side.is_local and wml.variables["side_number"] == chess_side.side) then return end
		
		ctl_chess_place_image(x, y, "misc/highlight-hex.png")
		
		wml.variables["ctl_chess_active"] = false
    	
    	wesnoth.audio.play("miss-2.ogg")
    	
		local ctl_chess_type = ctl_chess_get_piece_type(selected_unit.id)
		
		ctl_chess_select(ctl_chess_type, selected_unit.id, "misc/buff.png", "misc/attack.png")	
    
        wesnoth.interface.delay(500)
        wesnoth.units.select()
    	wesnoth.interface.deselect_hex()
        wml.fire("redraw")
    end
end)