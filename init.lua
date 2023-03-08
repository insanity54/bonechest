-- bonechest/init.lua

-- Load support for MT game translation.
local S = minetest.get_translator("bonechest")

local function on_mods_loaded()
	-- Disable the bones mod callbacks
	if minetest.get_modpath("bones") then
		minetest.log("warning", "[bonechest] bones mod detected. Disabling its callbacks.")
		for i = #core.registered_on_dieplayers, 1, -1 do
		  local callback = core.registered_on_dieplayers[i]
		  local origin = core.callback_origins[callback]
		  if origin and origin.mod == "bones" then
		    table.remove(core.registered_on_dieplayers, i)
		  end
		end
	end
end
minetest.register_on_mods_loaded(on_mods_loaded)

local function get_date ()
	return math.floor(os.time())
end

local function get_record_key (player_name, world_time_of_death)
	-- "d" is short for death
	return "d:"..player_name..":"..world_time_of_death
end

local player_inventory_lists = { "main", "craft" }
bonechest = {}
bonechest.storage = minetest.get_mod_storage()
bonechest.player_inventory_lists = player_inventory_lists
bonechest.get_record_key = get_record_key
	

local function get_inventory_table(inv)
	local inventory_table = {}
	for _, list_name in ipairs(player_inventory_lists) do
		inventory_table[list_name] = {}
		for i = 1, inv:get_size(list_name) do
			local stack = inv:get_stack(list_name, i)
			inventory_table[list_name][i] = stack:to_table()
		end
	end
	return inventory_table
end

-- local function get_inventory_data(inv)
--   local inv_data = {}
--   local inv_lists = inv:get_lists()

--   for list_name, list in pairs(inv_lists) do
--     local list_data = {}
--     for i, stack in ipairs(list) do
--         list_data[i] = stack:to_table()
--     end
--     inv_data[list_name] = list_data
--   end

--   return InvRef:new(inv_data)
-- end


local function read_inventory_from_storage(key)
  local data_str = bonechest.storage:get_string(key)
  if not data_str or data_str == "" then
      return nil
  end
  local data = minetest.parse_json(data_str)
  if not data or type(data) ~= "table" then
      return nil
  end
  return data.inventory_data
end


local function write_death_data_to_storage(player_name, pos, world_time_of_death, date_of_death, inventory_data)
	local data = {
		player_name = player_name,
		pos = pos,
		world_time_of_death = world_time_of_death,
		date_of_death = date_of_death,
		inventory_data = inventory_data
	}
	local data_str = minetest.write_json(data)
	bonechest.storage:set_string(get_record_key(player_name, world_time_of_death), data_str)
end

local function read_death_data_from_storage(key)
    local data_str = bonechest.storage:get_string(key)
    local data = minetest.parse_json(data_str)
    return data
end


local function is_owner(pos, name)
	local owner = minetest.get_meta(pos):get_string("owner")
	if owner == "" or owner == name or minetest.check_player_privs(name, "protection_bypass") then
		return true
	end
	return false
end

local bonechest_formspec =
	"size[8,9]" ..
	"list[current_name;main;0,0.3;8,4;]" ..
	"list[current_player;main;0,4.85;8,1;]" ..
	"list[current_player;main;0,6.08;8,3;8]" ..
	"listring[current_name;main]" ..
	"listring[current_player;main]" ..
	default.get_hotbar_bg(0,4.85)

local bonechest_destroy_time = tonumber(minetest.settings:get("bonechest_destroy_time")) or 604800 -- default of 7 days

minetest.register_node("bonechest:bonechest", {
	description = S("bonechest"),
	tiles = {
		"bonechest_top.png^[transform2",
		"bonechest_bottom.png",
		"bonechest_side.png",
		"bonechest_side.png",
		"bonechest_rear.png",
		"bonechest_front.png"
	},
	paramtype2 = "facedir",
	groups = {dig_immediate = 2},
	sounds = default.node_sound_gravel_defaults(),

	can_dig = function(pos, player)
		local bonechest_inv = minetest.get_meta(pos):get_inventory()
		local name = ""
		if player then
			name = player:get_player_name()
		end
		return is_owner(pos, name) and bonechest_inv:is_empty("main")
	end,

	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		if is_owner(pos, player:get_player_name()) then
			return count
		end
		return 0
	end,

	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		return 0
	end,

	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		if is_owner(pos, player:get_player_name()) then
			return stack:get_count()
		end
		return 0
	end,

	-- player removes one or more items
	on_metadata_inventory_take = function(pos, listname, index, stack, player)


		local meta = minetest.get_meta(pos)
		local player_name = meta:get_string("owner")
		local world_time_of_death = meta:get_string("world_time_of_death")
		-- local bonechest_inv = meta:get_inventory()


		-- update the modstorage record
		local bonechest_inventory = meta:get_inventory()
		local inventory_table = get_inventory_table(bonechest_inventory)
		local updated_date = get_date()
		write_death_data_to_storage(
			player_name,
			pos,
			world_time_of_death,
			updated_date,
			inventory_table
		)

		if meta:get_inventory():is_empty("main") then
			-- remove modstorage record
			bonechest.storage:set_string(bonechest.get_record_key(player_name, world_time_of_death), "")

			-- delete chest if it's empty
			minetest.remove_node(pos)
		end
	end,

	on_punch = function(pos, node, player)
		local player_name = player:get_player_name()
		if not is_owner(pos, player_name) then
			return
		end

		if minetest.get_meta(pos):get_string("infotext") == "" then
			return
		end

		local world_time_of_death = minetest.get_meta(pos):get_int("world_time_of_death")
		if world_time_of_death == "" then
			return
		end

		local bonechest_inv = minetest.get_meta(pos):get_inventory()
		local player_inv = player:get_inventory()
		local has_space = true

		for i = 1, bonechest_inv:get_size("main") do
			local stk = bonechest_inv:get_stack("main", i)
			if player_inv:room_for_item("main", stk) then
				bonechest_inv:set_stack("main", i, nil)
				player_inv:add_item("main", stk)
			else
				has_space = false
				break
			end
		end

		-- remove modstorage record
		bonechest.storage:set_string('d:'..player_name..":"..world_time_of_death, "")

		minetest.remove_node(pos)
	end,

	-- destroy bonechest if it's time has expired
	on_timer = function(pos, elapsed)
		local meta = minetest.get_meta(pos)
		local time = meta:get_int("time") + elapsed
		local player_name = meta:get_string("owner")
		local world_time_of_death = meta:get_string("world_time_of_death")
		if time >= bonechest_destroy_time then
			minetest.log("action", "Bonechest at " .. minetest.pos_to_string(pos) .. " timer elapsed. Destroying.")
			minetest.remove_node(pos)
		else
			meta:set_int("time", time)
			return true
		end
	end,

	on_blast = function(pos)
	end,
})

local function may_replace(pos, player)
	local node_name = minetest.get_node(pos).name
	local node_definition = minetest.registered_nodes[node_name]

	-- if the node is unknown, we return false
	if not node_definition then
		return false
	end

	-- don't replace nodes inside protections
	if minetest.is_protected(pos, player:get_player_name()) then
		return false
	end

	-- allow replacing air
	if node_name == "air" then
		return true
	end

	-- allow replacing liquids
	if node_definition.liquidtype ~= "none" then
		return true
	end

	-- don't replace filled chests and other nodes that don't allow it
	local can_dig_func = node_definition.can_dig
	if can_dig_func and not can_dig_func(pos, player) then
		return false
	end

	-- default to each nodes buildable_to; if a placed block would replace it, why shouldn't bonechest?
	-- flowers being squished by bonechest are more realistical than a squished stone, too
	return node_definition.buildable_to
end

local drop = function(pos, itemstack)
	local obj = minetest.add_item(pos, itemstack:take_item(itemstack:get_count()))
	if obj then
		obj:set_velocity({
			x = math.random(-10, 10) / 9,
			y = 5,
			z = math.random(-10, 10) / 9,
		})
	end
end

local function is_all_empty(player_inv)
	for _, list_name in ipairs(player_inventory_lists) do
		if not player_inv:is_empty(list_name) then
			return false
		end
	end
	return true
end


minetest.register_on_dieplayer(function(player)


	local bonechest_mode = minetest.settings:get("bonechest_mode") or "bonechest"
	if bonechest_mode ~= "bonechest" and bonechest_mode ~= "destroy" and bonechest_mode ~= "keep" then
		bonechest_mode = "bonechest"
	end

	minetest.log("action", "the bonechest_mode is "..bonechest_mode)

	local bonechest_position_message = minetest.settings:get_bool("bonechest_position_message") == true
	local player_name = player:get_player_name()
	local pos = vector.round(player:get_pos())
	local pos_string = minetest.pos_to_string(pos)
	local world_time_of_death = minetest.get_gametime()

	-- return if keep inventory set or in creative mode
	if bonechest_mode == "keep" or minetest.is_creative_enabled(player_name) then
		minetest.log("action", player_name .. " dies at " .. pos_string ..
			". No bonechest placed")
		if bonechest_position_message then
			minetest.chat_send_player(player_name, S("@1 died at @2.", player_name, pos_string))
		end
		return
	end

	local player_inv = player:get_inventory()
	if is_all_empty(player_inv) then
		minetest.log("action", player_name .. " dies at " .. pos_string ..
			". No bonechest placed")
		if bonechest_position_message then
			minetest.chat_send_player(player_name, S("@1 died at @2.", player_name, pos_string))
		end
		return
	end


	-- A bonechest creates a record in mod storage
	minetest.log("action", "creating a bonechest record")
	local inventory_table = get_inventory_table(player_inv)
	local date_of_death = get_date()
	write_death_data_to_storage(
		player_name,
		pos,
		world_time_of_death,
		date_of_death,
		inventory_table
	)


	-- check if it's possible to place bonechest
	-- if not, destroy their items.
	if bonechest_mode == "bonechest" and not may_replace(pos, player) then
		local air = minetest.find_node_near(pos, 1, {"air"})
		if air and not minetest.is_protected(air, player_name) then
			pos = air
		else
			bonechest_mode = "destroy"
		end
	end

	if bonechest_mode == "destroy" then
		-- clear player's inv
		for _, list_name in ipairs(player_inventory_lists) do
			player_inv:set_list(list_name, {})
		end

		minetest.log("action", player_name .. " dies at protected area " .. pos_string .. " so their inventory was destroyed.")
		if bonechest_position_message then
			minetest.chat_send_player(player_name, S("@1 died at protected area @2, so their inventory was destroyed.", player_name, pos_string))
		end
		return
	end

	local param2 = minetest.dir_to_facedir(player:get_look_dir())
	minetest.set_node(pos, {name = "bonechest:bonechest", param2 = param2})

	minetest.log("action", player_name .. " dies at " .. pos_string ..
		". bonechest placed")
	if bonechest_position_message then
		minetest.chat_send_player(player_name, S("@1 died at @2, and bonechest were placed.", player_name, pos_string))
	end

	local meta = minetest.get_meta(pos)
	local bonechest_inv = meta:get_inventory()
	bonechest_inv:set_size("main", 8 * 4)

	for _, list_name in ipairs(player_inventory_lists) do
		for i = 1, player_inv:get_size(list_name) do
			local stack = player_inv:get_stack(list_name, i)
			if bonechest_inv:room_for_item("main", stack) then
				bonechest_inv:add_item("main", stack)
			else -- no space left
				drop(pos, stack)
			end
		end
		player_inv:set_list(list_name, {})
	end



	meta:set_string("formspec", bonechest_formspec)
	meta:set_string("owner", player_name)
	meta:set_string("infotext", S("@1's bonechest", player_name))
	meta:set_string("world_time_of_death", world_time_of_death)
	meta:set_int("time", 0)
	minetest.get_node_timer(pos):start(10)

end)
