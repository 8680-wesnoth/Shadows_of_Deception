--#textdomain wesnoth-Shadows_of_Deception

local dialogs = nxrequire "gui/dialogs/inv"
local buttons = dialogs.buttons
local valid_attacks = {axe = 1, ["battle axe"] = 1, bow = 1, broadsword = 1, dagger = 1, crossbow = 1, hammer = 1, javelin = 1, lance = 1, spear = 1, staff = 1}; 

-- This brings up the custom inventory control window
function wml_actions.show_inventory(cfg)
	local unit = wesnoth.get_units({x = wesnoth.current.event_context.x1, y = wesnoth.current.event_context.y1})[1].__cfg
	local recipients = wesnoth.get_variable("adjacent_recipients") or nil
	local selected_recipient = 1
	local selected_row = 1
	local page_count = 0
	local var, inv_list_data, button, continue
	local command_list = {}

	-- Syncs weapon data with the table and sorts it
	local function sync_weapons_to_items()
		for i, attack in pairs(lp8.get_children(unit, 'attack')) do
			if valid_attacks[attack.name] and not helper.get_child(var, "item", attack.name) then
				local descrip = string.format("%s - %s %s", attack.damage, attack.number, attack.type)

				table.insert(var, {"item", {
					id = attack.name,
					name = attack.description, -- [attack] doesn't have dedicated id keys, and the description is more like a name anyway
					image = attack.icon or string.format("attacks/%s.png", attack.name),
					description = descrip,
					effect_type = "continuous",
					active = true,
					{ "command", { { "object", { silent = true, duration = "forever",
						{'effect', lp8.copyTable(attack, {apply_to = 'new_attack'})}
						} }
					} },
					{ "removal_command", { { "object", { silent = true, duration = "forever",
						{ "effect", { apply_to = "remove_attacks", range = attack.range, name = attack.name } } } }
					} }
				} })
			end
		end

		wesnoth.put_unit(unit)
	end

	-- Prints item list
	local function print_item_list()
		for i, item in ipairs(inv_list_data) do
			if item.active then
				wesnoth.set_dialog_value(item.image .. "~BLIT(misc/active_item_indicator.png)", "inventory_list", i, "list_image")
			else
				wesnoth.set_dialog_value(item.image, "inventory_list", i, "list_image")
			end

			wesnoth.set_dialog_value("<span size='large'>" .. item.name .. "</span>", "inventory_list", i, "list_name")
			wesnoth.set_dialog_markup(true,                                           "inventory_list", i, "list_name")

			wesnoth.set_dialog_value(item.name, "details_pages", i, "details_name")
			wesnoth.set_dialog_value(item.quantity or 1, "inventory_list", i, "list_quantity")
			wesnoth.set_dialog_value(item.description, "details_pages", i, "details_description")

			page_count = i
		end
	end

	-- Refreshes use button value
	local function refresh_use_button_text(index)
		local item = inv_list_data[index]

		if item.active and item.effect_type == "continuous" then
			wesnoth.set_dialog_value(_"Unequip", "use_button")
		elseif not item.active and item.effect_type == "continuous" then
			wesnoth.set_dialog_value(_"Equip", "use_button")
		else
			wesnoth.set_dialog_value(_"Use", "use_button")
		end

		wesnoth.set_dialog_active(
			wesnoth.eval_conditional(
				helper.get_child(item, "usable_if") or {}),
			"use_button")
	end

	-- Sets values for the details panel widgets
	local function select_from_inventory()
		local i = wesnoth.get_dialog_value("inventory_list")

		if i > page_count or page_count == 0 then
			wesnoth.fire("wml_message", {
				logger = "error",
				message = "[SoD] BUG: invalid inventory_list row number"
			})

			return
		end

		selected_row = i
		refresh_use_button_text(i)
		wesnoth.set_dialog_value(i, "details_pages")
	end

	local function keepGoing()
		return button == buttons.use or
				button == buttons.give or (
					continue and not (
						button == buttons.exit or
						button <= 0
					)
				)
	end

	-- Handles using an item
	local function use_item()
		local i = wesnoth.get_dialog_value("inventory_list")
		local list_item = inv_list_data[i]
		local function item_filter(tag)
			return tag[1] == 'item' and tag[2].id == list_item.id
		end
		local item_var = lp8.get_child(var, item_filter)

		button = buttons.use
		continue = true

		-- If item is not active...
		if not list_item.active then
			-- ... and if it's single-use, decrease quantity by 1
			if list_item.effect_type == "single" then
				item_var.quantity = (list_item.quantity or 1) - 1

				wesnoth.set_dialog_value(
					list_item.quantity, "inventory_list", i, "list_quantity")

				-- Delete item if you now have none of it
				if list_item.quantity == 0 then
					lp8.remove_subtag(var, item_filter)

					if selected_row == page_count then
						selected_row = selected_row - 1
					end
				end
			end

			-- ... and if it's continuous-use, activate it
			if list_item.effect_type == "continuous" then
				wesnoth.set_dialog_value(
					list_item.image
						.. "~BLIT(misc/active_item_indicator.png)",
					"inventory_list", i, "list_image")
				item_var.active = true
			end

			table.insert(command_list,(helper.get_child(list_item, "command")))

		-- But if it was already active, therefore it was a continuous-use item
		-- So just deactivate it
		else
			wesnoth.set_dialog_value(
				list_item.image, "inventory_list", i, "list_image")

			item_var.active = false

			table.insert(command_list,(helper.get_child(list_item, "removal_command")))
		end

		refresh_use_button_text(i)
	end

	local function give_item()
	end

	local function inventory_preshow()
		wesnoth.set_dialog_value("Inventory — " .. unit.name, "title")
		wesnoth.set_dialog_value(unit.image .. "~RC(magenta>red)", "unit_image")

		wesnoth.set_dialog_callback(select_from_inventory, "inventory_list")
		wesnoth.set_dialog_callback(use_item, "use_button")
		wesnoth.set_dialog_callback(give_item, "give_button")

		-- Sets initial values of stuff
		print_item_list()

		wesnoth.set_dialog_value(selected_row, "inventory_list")
		select_from_inventory()

		-- Disable Give button if there're no recipients
		if not recipients then
			wesnoth.set_dialog_active(false, "give_button")
		end
	end

	repeat
		-- Keep all tables and main variables up to date
		var = helper.get_child(unit, "variables")

		sync_weapons_to_items() -- Adds weapons to inv_list_data and sorts it alphabetically

		inv_list_data = lp8.get_children(var, "item")
		table.sort(inv_list_data, function(a,b) return tostring(a.name) < tostring(b.name) end)

		button = next(inv_list_data)
			and wesnoth.show_dialog(dialogs.normal, inventory_preshow)
			or wesnoth.show_dialog(dialogs.empty)
	until not keepGoing()

	-- Resyncs the local lua tables with the actual unit
	wesnoth.put_unit(unit)

	for i = 1, #command_list do
		wml_actions.command(command_list[i])
	end
end
