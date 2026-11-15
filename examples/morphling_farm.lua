--[[
     ~ qLocalization
     ~ automatic localization wrapper for Lua menu interfaces

     ~ author: qfun (qfun_g9s)
]]

local qLocalization = (function()
	local lib = {}

	local a = function(...)
		return ...
	end

	local state = {
		lang = Menu.Find("SettingsHidden", "", "", "", "Main", "Language"),
		instances = {},
	}

	local setters = {
		ToolTip = "tooltip",
	}

	local helpers
	do
		helpers = {
			resolve = a(function(root, path)
				for key in path:gmatch("[^.]+") do
					if type(root) ~= "table" then
						return
					end

					root = root[key]
				end

				return root
			end),

			is_object = a(function(value)
				return type(value) == "table" or type(value) == "userdata"
			end),

			has_method = a(function(object, name)
				return helpers.is_object(object) and type(object[name]) == "function"
			end),

			is_menu_object = a(function(value)
				return helpers.has_method(value, "Name") and helpers.has_method(value, "Type")
			end),

			is_list = a(function(value)
				if type(value) ~= "table" or #value == 0 then
					return false
				end

				for i = 1, #value do
					if type(value[i]) ~= "string" then
						return false
					end
				end

				return true
			end),

			is_indexed_list = a(function(object)
				return helpers.has_method(object, "List") and not helpers.has_method(object, "ListEnabled")
			end),
		}
	end

	function lib.new(translations)
		local languages = {}

		for i, name in ipairs(state.lang and state.lang:List() or {}) do
			local code = name:match("%a+")

			if code and translations[code] then
				languages[i - 1] = code
			end
		end

		local localization = {
			translations = translations,
			languages = languages,
			objects = {},
		}

		local methods
		do
			methods = {
				get_language = a(function(language_index)
					if language_index == nil and state.lang then
						language_index = state.lang:Get()
					end

					return localization.languages[language_index] or "en"
				end),

				localize = a(function(path, language_index)
					if type(path) ~= "string" then
						return path
					end

					local language = methods.get_language(language_index)

					return helpers.resolve(localization.translations[language], path)
						or helpers.resolve(localization.translations.en, path)
						or path
				end),

				has = a(function(path)
					if type(path) ~= "string" then
						return false
					end

					return helpers.resolve(localization.translations.en, path) ~= nil
						or helpers.resolve(localization.translations[methods.get_language()], path) ~= nil
				end),

				localize_items = a(function(items, language_index)
					local result, localized = {}, false

					for i = 1, #items do
						local value = items[i]

						if methods.has(value) then
							result[i] = methods.localize(value, language_index)
							localized = true
						else
							result[i] = value
						end
					end

					return result, localized
				end),

				apply = a(function(object, kind, path, language_index)
					if kind == "label" then
						object:ForceLocalization(methods.localize(path, language_index))
					elseif kind == "tooltip" then
						object:ToolTip(methods.localize(path, language_index))
					elseif kind == "items" then
						local value = object:Get()

						object:Update((methods.localize_items(path, language_index)))
						object:Set(value)
					end
				end),

				track = a(function(object, kind, path, apply_now)
					local record = localization.objects[object]

					if record == nil then
						record = {}
						localization.objects[object] = record
					end

					record[kind] = path

					if apply_now then
						methods.apply(object, kind, path)
					end
				end),

				register = a(function(object, path)
					if not methods.has(path) or not helpers.has_method(object, "ForceLocalization") then
						return
					end

					methods.track(object, "label", path, true)
				end),

				update = a(function(language_index)
					for object, record in pairs(localization.objects) do
						for kind, path in pairs(record) do
							methods.apply(object, kind, path, language_index)
						end
					end
				end),

				wrap = a(function(target, bind_self)
					if not helpers.is_object(target) then
						return target
					end

					local proxy

					proxy = setmetatable({}, {
						__index = function(_, key)
							local member = target[key]

							if type(member) ~= "function" then
								return member
							end

							return function(...)
								local args = table.pack(...)

								if bind_self and args[1] == proxy then
									table.remove(args, 1)
									args.n = args.n - 1
								end

								if key == "Switch" and args.n < 2 then
									args[2] = false
									args.n = 2
								end

								local name_path, item_paths

								if setters[key] then
									if methods.has(args[1]) then
										methods.track(target, setters[key], args[1], false)

										args[1] = methods.localize(args[1])
									end
								else
									local name_index = bind_self and 1 or args.n

									if methods.has(args[name_index]) then
										name_path = args[name_index]
									end

									local items_index

									if key == "Combo" then
										items_index = 2
									elseif key == "Update" and helpers.is_indexed_list(target) then
										items_index = 1
									end

									if items_index ~= nil and helpers.is_list(args[items_index]) then
										local items, localized = methods.localize_items(args[items_index])

										if localized then
											item_paths = args[items_index]
											args[items_index] = items
										end
									end
								end

								local results

								if bind_self then
									results = table.pack(member(target, table.unpack(args, 1, args.n)))
								else
									results = table.pack(member(table.unpack(args, 1, args.n)))
								end

								for i = 1, results.n do
									local result = results[i]

									if helpers.is_menu_object(result) then
										if name_path then
											methods.register(result, name_path)
										end

										if item_paths then
											methods.track(result, "items", item_paths, false)
											item_paths = nil
										end

										results[i] = methods.wrap(result, true)
									end
								end

								if item_paths then
									methods.track(target, "items", item_paths, false)
								end

								return table.unpack(results, 1, results.n)
							end
						end,

						__newindex = function(_, key, value)
							target[key] = value
						end,
					})

					return proxy
				end),
			}
		end

		state.instances[methods] = true

		return {
			GetLanguage = methods.get_language,

			Get = methods.localize,
			Localize = methods.localize,

			Update = methods.update,
			Register = methods.register,

			Wrap = methods.wrap,

			WrapLibrary = function(library)
				return methods.wrap(library, false)
			end,
		}
	end

	if state.lang then
		state.lang:SetCallback(function(this)
			local language_index = this:Get()

			for methods in pairs(state.instances) do
				methods.update(language_index)
			end
		end, true)
	else
		Log.Write("[qLocalization] Language widget not found, using English fallback")
	end

	return lib
end)()

local localization = qLocalization.new({
	en = {
		mf_group_main = "Farm",
		mf_group_extra = "Safety",
		mf_enable = "Enable",
		mf_enable_tip = "Enables automatic neutral farming for Morphling",
		mf_gear_extra = "Advanced",
		mf_debug = "Debug log",
		mf_debug_tip = "Writes state changes to debug.log",
		mf_key = "Farm toggle",
		mf_key_tip = "Press once to start farming\nand again to stop",
		mf_bind_name = "Morphling: toggle farm",
		mf_panel_key = "Camp selection panel",
		mf_panel_key_tip = "Opens a map where you can enable\nor disable individual neutral camps",
		mf_panel_bind_name = "Morphling: camp selection",
		mf_farm_wave = "Waveform to farm",
		mf_farm_wave_tip = "Uses Waveform on groups of neutral creeps",
		mf_farm_adaptive = "Adaptive Strike to farm",
		mf_farm_adaptive_tip = "Uses Adaptive Strike on the healthiest neutral creep",
		mf_farm_mana = "Minimum mana for farming",
		mf_clarity = "Buy Clarity every minute",
		mf_clarity_tip = "Buys one Clarity each game minute\nand uses it between neutral fights",
		mf_avoid = "Avoid enemy heroes",
		mf_avoid_tip = "Skips dangerous camps and retreats\nfrom visible enemy heroes",
		mf_avoid_radius = "Enemy detection radius",
		mf_escape_hp = "Retreat below health",
		mf_escape_hp_tip = "Returns to the allied fountain below this health",
		mf_escape_wave = "Waveform escape",
		mf_escape_wave_tip = "Uses Waveform toward safety when an enemy is close",
		mf_escape_morph = "Morph Strength on danger",
		mf_escape_morph_tip = "Starts Morph Strength when threatened\nat low health",
		mf_safe_items = "Escape items",
		mf_safe_items_tip = "Power Treads switch to Strength, Manta dispels,\nand a dominated creep attacks the pursuer",
		mf_safe_hp = "Use escape items below",
		mf_panel_title = "Morphling Farm Settings",
		mf_panel_radiant = "RADIANT",
		mf_panel_dire = "DIRE",
		mf_panel_hint = "Click camps to allow or block them",
		mf_status_farm = "FARM",
		mf_status_heal = "HEAL",
	},
	ru = {
		mf_group_main = "Фарм",
		mf_group_extra = "Безопасность",
		mf_enable = "Включить",
		mf_enable_tip = "Включает автоматический фарм нейтралов для Morphling",
		mf_gear_extra = "Расширенные настройки",
		mf_debug = "Отладка в лог",
		mf_debug_tip = "Пишет смену состояний в debug.log",
		mf_key = "Переключатель фарма",
		mf_key_tip = "Одно нажатие запускает фарм,\nповторное останавливает",
		mf_bind_name = "Morphling: переключить фарм",
		mf_panel_key = "Панель выбора кемпов",
		mf_panel_key_tip = "Открывает карту, на которой можно включать\nи выключать отдельные нейтральные кемпы",
		mf_panel_bind_name = "Morphling: выбор кемпов",
		mf_farm_wave = "Waveform для фарма",
		mf_farm_wave_tip = "Использует Waveform по группе нейтральных крипов",
		mf_farm_adaptive = "Adaptive Strike для фарма",
		mf_farm_adaptive_tip = "Использует Adaptive Strike по самому здоровому нейтралу",
		mf_farm_mana = "Минимум маны для фарма",
		mf_clarity = "Покупать Clarity каждую минуту",
		mf_clarity_tip = "Покупает одну Clarity каждую игровую минуту\nи использует её между боями с нейтралами",
		mf_avoid = "Избегать вражеских героев",
		mf_avoid_tip = "Пропускает опасные кемпы и отступает\nот видимых вражеских героев",
		mf_avoid_radius = "Радиус обнаружения врага",
		mf_escape_hp = "Отход при здоровье ниже",
		mf_escape_hp_tip = "Возвращается к своему фонтану ниже этого здоровья",
		mf_escape_wave = "Побег через Waveform",
		mf_escape_wave_tip = "Использует Waveform в безопасную сторону, если враг рядом",
		mf_escape_morph = "Morph Strength при угрозе",
		mf_escape_morph_tip = "Включает Morph Strength при угрозе\nи низком здоровье",
		mf_safe_items = "Предметы для побега",
		mf_safe_items_tip = "Power Treads переключаются в силу, Manta снимает эффекты,\nа подконтрольный крип атакует преследователя",
		mf_safe_hp = "Использовать предметы ниже",
		mf_panel_title = "Настройки фарма Morphling",
		mf_panel_radiant = "RADIANT",
		mf_panel_dire = "DIRE",
		mf_panel_hint = "Нажимай на кемпы, чтобы разрешить или запретить их",
		mf_status_farm = "FARM",
		mf_status_heal = "HEAL",
	},
})

local UI = localization.WrapLibrary(Menu)
local L = localization.Get

local ui = {}

do
	local hero_tab = UI.Find("Heroes", "Hero List", "Morphling")
	local page = hero_tab and hero_tab:Find("Main Settings")
	if not page then
		local tab = UI.Create("Scripts", "Scripts", "Morphling Farm")
		tab:Icon("\u{f4d7}")
		page = tab:Create("Settings")
	end

	local g_main = page:Create("mf_group_main", Enum.GroupSide.Left)
	local g_extra = page:Create("mf_group_extra", Enum.GroupSide.Right)
	ui.hero_enable = Menu.Find("Heroes", "Hero List", "Morphling", "Main Settings", "Hero Settings", "Enable")

	ui.enable = g_main:Switch("mf_enable", false, "\u{f011}")
	ui.enable:ToolTip("mf_enable_tip")
	local g_gear = ui.enable:Gear("mf_gear_extra")
	ui.debug = g_gear:Switch("mf_debug", false, "\u{f188}")
	ui.debug:ToolTip("mf_debug_tip")
	ui.farm_wave = g_gear:Switch("mf_farm_wave", true, "\u{f043}")
	ui.farm_wave:ToolTip("mf_farm_wave_tip")
	ui.farm_adaptive = g_gear:Switch("mf_farm_adaptive", true, "\u{f05b}")
	ui.farm_adaptive:ToolTip("mf_farm_adaptive_tip")
	ui.farm_mana = g_gear:Slider("mf_farm_mana", 25, 90, 55, "%d%%")
	ui.farm_mana:Icon("\u{f1de}")
	ui.clarity = g_gear:Switch("mf_clarity", true, "\u{f0c3}")
	ui.clarity:ToolTip("mf_clarity_tip")

	ui.key = g_main:Bind("mf_key", Enum.ButtonCode.KEY_NONE, "\u{f11c}")
	ui.key:ToolTip("mf_key_tip")
	ui.key:Properties(L("mf_bind_name"), nil, true)
	ui.panel_key = g_main:Bind("mf_panel_key", Enum.ButtonCode.KEY_NONE, "\u{f3c5}")
	ui.panel_key:ToolTip("mf_panel_key_tip")
	ui.panel_key:Properties(L("mf_panel_bind_name"), nil, true)

	ui.avoid = g_extra:Switch("mf_avoid", true, "\u{f70c}")
	ui.avoid:ToolTip("mf_avoid_tip")
	ui.avoid_radius = g_extra:Slider("mf_avoid_radius", 700, 2200, 1300, "%d")
	ui.avoid_radius:Icon("\u{f1ce}")
	ui.escape_hp = g_extra:Slider("mf_escape_hp", 15, 70, 38, "%d%%")
	ui.escape_hp:Icon("\u{f004}")
	ui.escape_hp:ToolTip("mf_escape_hp_tip")
	ui.escape_wave = g_extra:Switch("mf_escape_wave", true, "\u{f4d7}")
	ui.escape_wave:ToolTip("mf_escape_wave_tip")
	ui.escape_morph = g_extra:Switch("mf_escape_morph", true, "\u{f337}")
	ui.escape_morph:ToolTip("mf_escape_morph_tip")
	ui.safe_items = g_extra:MultiSelect("mf_safe_items", {
		{ "Blade of Alacrity", "panorama/images/items/blade_of_alacrity_png.vtex_c", true },
		{ "Power Treads", "panorama/images/items/power_treads_png.vtex_c", true },
		{ "Helm of the Dominator", "panorama/images/items/helm_of_the_dominator_png.vtex_c", true },
		{ "Manta Style", "panorama/images/items/manta_png.vtex_c", true },
	}, true)
	ui.safe_items:Icon("\u{f132}")
	ui.safe_items:ToolTip("mf_safe_items_tip")
	ui.safe_hp = g_extra:Slider("mf_safe_hp", 15, 80, 55, "%d%%")
	ui.safe_hp:Icon("\u{f004}")
end

local function refresh_disabled()
	local on = ui.enable:Get()
	ui.key:Disabled(not on)
	ui.panel_key:Disabled(not on)
	ui.avoid:Disabled(not on)
	ui.avoid_radius:Disabled(not on or not ui.avoid:Get())
	ui.escape_hp:Disabled(not on)
	ui.escape_wave:Disabled(not on or not ui.avoid:Get())
	ui.escape_morph:Disabled(not on or not ui.avoid:Get())
	ui.safe_items:Disabled(not on)
	ui.safe_hp:Disabled(not on)
	ui.farm_wave:Disabled(not on)
	ui.farm_adaptive:Disabled(not on)
	ui.farm_mana:Disabled(not on or (not ui.farm_wave:Get() and not ui.farm_adaptive:Get()))
	ui.clarity:Disabled(not on)
	ui.debug:Disabled(not on)
end

ui.enable:SetCallback(refresh_disabled, true)
ui.avoid:SetCallback(refresh_disabled)
ui.farm_wave:SetCallback(refresh_disabled)
ui.farm_adaptive:SetCallback(refresh_disabled)

local function log(text)
	if ui.debug:Get() then
		Log.Write("[Morphling Farm] " .. text)
	end
end

local state = {
	camp = nil,
	blocked = {},
	next_think = 0,
	next_order = 0,
	retreating = false,
	last_mode = "",
	morph_owned = false,
	own_fountain = nil,
	enemy_fountain = nil,
	next_fountain_scan = 0,
	radiant_fountain = nil,
	dire_fountain = nil,
	selected_camps = {},
	custom_selection = Config.ReadInt("morphling_farm_v2", "custom_selection", 0) == 1,
	map_team = nil,
	treads_owned = false,
	treads_original = nil,
	next_treads = 0,
	next_manta = 0,
	next_guard = 0,
	attack_committed = false,
	attack_release = 0,
	next_attack = 0,
	attack_target = nil,
	last_clarity_buy_minute = -1,
	last_clarity_use_minute = -1,
	clarity_pending_until = 0,
}

local panel = {
	w = 323,
	h = 378,
	map_top = 68,
	map_size = 304,
	world_min = -8300,
	world_max = 8300,
	font = Render.LoadFont("Arial", Enum.FontCreate.FONTFLAG_ANTIALIAS, 500),
	title_font = Render.LoadFont("Arial", Enum.FontCreate.FONTFLAG_ANTIALIAS, 700),
	status_font = Render.LoadFont("Arial", Enum.FontCreate.FONTFLAG_ANTIALIAS, 700),
	map_image = Render.LoadImage("images/morphling_farm_map.png"),
}

local function set_mode(mode)
	if state.last_mode ~= mode then
		state.last_mode = mode
		log(mode)
	end
end

local function reset()
	state.camp = nil
	state.blocked = {}
	state.next_think = 0
	state.next_order = 0
	state.retreating = false
	state.last_mode = ""
	state.morph_owned = false
	state.own_fountain = nil
	state.enemy_fountain = nil
	state.next_fountain_scan = 0
	state.radiant_fountain = nil
	state.dire_fountain = nil
	state.selected_camps = {}
	state.custom_selection = Config.ReadInt("morphling_farm_v2", "custom_selection", 0) == 1
	state.treads_owned = false
	state.treads_original = nil
	state.next_treads = 0
	state.next_manta = 0
	state.next_guard = 0
	state.attack_committed = false
	state.attack_release = 0
	state.next_attack = 0
	state.attack_target = nil
	state.last_clarity_buy_minute = -1
	state.last_clarity_use_minute = -1
	state.clarity_pending_until = 0
end

local function active()
	return ui.enable:Get() and ui.key:IsToggled() and (not ui.hero_enable or ui.hero_enable:Get())
end

local function camp_center(camp)
	local box = Camp.GetCampBox(camp)
	if not box or not box.min or not box.max then return nil end
	return Vector(
		(box.min.x + box.max.x) * 0.5,
		(box.min.y + box.max.y) * 0.5,
		(box.min.z + box.max.z) * 0.5
	)
end

local function camp_key(camp)
	local center = camp_center(camp)
	if not center then return "invalid" end
	return string.format("%d_%d", math.floor(center.x / 50), math.floor(center.y / 50))
end

local function camp_selected(camp)
	local key = camp_key(camp)
	if state.selected_camps[key] == nil then
		state.selected_camps[key] = Config.ReadInt("morphling_farm_v2", "camp_" .. key, 1) == 1
	end
	return state.selected_camps[key]
end

local function set_camp_selected(camp, value)
	local key = camp_key(camp)
	state.selected_camps[key] = value
	state.custom_selection = true
	Config.WriteInt("morphling_farm_v2", "camp_" .. key, value and 1 or 0)
	Config.WriteInt("morphling_farm_v2", "custom_selection", 1)
	if state.camp == camp and not value then state.camp = nil end
end

local function camp_side(center)
	if state.radiant_fountain and state.dire_fountain then
		return center:DistanceSqr2D(state.radiant_fountain) <= center:DistanceSqr2D(state.dire_fountain) and 0 or 1
	end
	return center.x + center.y < 0 and 0 or 1
end

local function find_fountains(hero)
	local now = GameRules.GetGameTime()
	if state.own_fountain and now < state.next_fountain_scan then
		return state.own_fountain, state.enemy_fountain
	end
	local own, enemy = nil, nil
	local team = Entity.GetTeamNum(hero)
	for _, npc in ipairs(NPCs.GetAll() or {}) do
		local name = (Entity.GetUnitName(npc) or ""):lower()
		if name:find("fountain", 1, true) then
			local fountain_pos = Entity.GetAbsOrigin(npc)
			local fountain_team = Entity.GetTeamNum(npc)
			if fountain_team == Enum.TeamNum.TEAM_RADIANT then state.radiant_fountain = fountain_pos end
			if fountain_team == Enum.TeamNum.TEAM_DIRE then state.dire_fountain = fountain_pos end
			if fountain_team == team then own = fountain_pos else enemy = fountain_pos end
		end
	end
	state.own_fountain = own or state.own_fountain
	state.enemy_fountain = enemy or state.enemy_fountain
	state.next_fountain_scan = now + 8
	return state.own_fountain, state.enemy_fountain
end

local function neutrals()
	return NPCs.GetAll(function(npc)
		return NPC.IsNeutral(npc)
			and Entity.IsAlive(npc)
			and not Entity.IsDormant(npc)
			and not NPC.IsWaitingToSpawn(npc)
	end) or {}
end

local function camp_creeps(camp, all_neutrals, hero)
	local result = {}
	local box = Camp.GetCampBox(camp)
	if not box then return result end
	local center = camp_center(camp)
	local hero_pos = hero and Entity.GetAbsOrigin(hero) or nil
	for _, npc in ipairs(all_neutrals) do
		local pos = Entity.GetAbsOrigin(npc)
		local in_box = pos.x >= box.min.x - 300 and pos.x <= box.max.x + 300
			and pos.y >= box.min.y - 300 and pos.y <= box.max.y + 300
		local fighting_nearby = hero_pos and center
			and (pos:IsInRange2D(center, 1100) or pos:IsInRange2D(hero_pos, 900))
		if in_box or fighting_nearby then
			result[#result + 1] = npc
		end
	end
	return result
end

local function camp_safe(hero, center)
	if not ui.avoid:Get() then return true end
	local enemies = Heroes.InRadius(
		center,
		ui.avoid_radius:Get(),
		Entity.GetTeamNum(hero),
		Enum.TeamType.TEAM_ENEMY,
		true,
		true
	)
	return #enemies == 0
end

local function select_camp(hero, all_neutrals, now)
	local hero_pos = Entity.GetAbsOrigin(hero)
	local occupied_best, occupied_dist = nil, math.huge
	local empty_best, empty_dist = nil, math.huge
	for _, camp in ipairs(Camps.GetAll() or {}) do
		local center = camp_center(camp)
		local key = camp_key(camp)
		if center and camp_selected(camp)
			and (not state.blocked[key] or state.blocked[key] <= now) and camp_safe(hero, center) then
			local creeps = camp_creeps(camp, all_neutrals)
			local distance = hero_pos:DistanceSqr2D(center)
			if #creeps > 0 and distance < occupied_dist then
				occupied_best, occupied_dist = camp, distance
			elseif #creeps == 0 and distance < empty_dist then
				empty_best, empty_dist = camp, distance
			end
		end
	end
	return occupied_best or empty_best
end

local function closest_enemy(hero)
	if not ui.avoid:Get() then return nil end
	local enemies = Entity.GetHeroesInRadius(hero, ui.avoid_radius:Get(), Enum.TeamType.TEAM_ENEMY, true, true)
	local hero_pos = Entity.GetAbsOrigin(hero)
	local closest, distance = nil, math.huge
	for _, enemy in ipairs(enemies) do
		local value = hero_pos:DistanceSqr2D(Entity.GetAbsOrigin(enemy))
		if value < distance then closest, distance = enemy, value end
	end
	return closest
end

local function stop_strength_morph(hero)
	if not state.morph_owned then return end
	local morph = NPC.GetAbility(hero, "morphling_morph_str")
	if morph and Ability.GetToggleState(morph) then Ability.Toggle(morph) end
	state.morph_owned = false
end

local function selected_item(name)
	return ui.safe_items:Get(name)
end

local function dominated_guard(hero)
	for _, npc in ipairs(NPCs.GetAll() or {}) do
		if Entity.IsAlive(npc) and not NPC.IsHero(npc) and not NPC.IsIllusion(npc)
			and NPC.GetOwnerNPC(npc) == hero then return npc end
	end
	return nil
end

local function restore_treads(hero, now)
	if not state.treads_owned or now < state.next_treads then return end
	local treads = NPC.GetItem(hero, "item_power_treads")
	if not treads or state.treads_original == nil then
		state.treads_owned = false
		state.treads_original = nil
		return
	end
	if PowerTreads.GetStats(treads) ~= state.treads_original then
		Ability.CastNoTarget(treads, false, false, false, "morphling_farm_treads_restore")
		state.next_treads = now + 0.2
	else
		state.treads_owned = false
		state.treads_original = nil
	end
end

local function use_escape_items(hero, enemy, hp_pct, now)
	if hp_pct > ui.safe_hp:Get() then return false end
	if selected_item("Power Treads") and now >= state.next_treads then
		local treads = NPC.GetItem(hero, "item_power_treads")
		if treads then
			local current = PowerTreads.GetStats(treads)
			if not state.treads_owned then
				state.treads_original = current
				state.treads_owned = true
			end
			if current ~= Enum.Attributes.DOTA_ATTRIBUTE_STRENGTH then
				Ability.CastNoTarget(treads, false, false, false, "morphling_farm_treads_strength")
				state.next_treads = now + 0.2
			end
		end
	end
	if enemy and selected_item("Helm of the Dominator") and now >= state.next_guard then
		local guard = dominated_guard(hero)
		local player = Players.GetLocal()
		if guard and player then Player.AttackTarget(player, guard, enemy, false, false, false, "morphling_farm_guard") end
		state.next_guard = now + 0.5
	end
	if enemy and selected_item("Manta Style") and now >= state.next_manta then
		local manta = NPC.GetItem(hero, "item_manta")
		if manta and Ability.IsCastable(manta, NPC.GetMana(hero)) then
			Ability.CastNoTarget(manta, false, false, false, "morphling_farm_manta")
			state.next_manta = now + 1
			state.next_order = now + 0.25
			return true
		end
	end
	return false
end

local function use_dominator(hero, creeps, now)
	if not selected_item("Helm of the Dominator") or dominated_guard(hero) then return false end
	local helm = NPC.GetItem(hero, "item_helm_of_the_dominator")
	if not helm or not Ability.IsCastable(helm, NPC.GetMana(hero)) then return false end
	local hero_pos = Entity.GetAbsOrigin(hero)
	local target = nil
	for _, creep in ipairs(creeps) do
		if not NPC.IsAncient(creep) and hero_pos:IsInRange2D(Entity.GetAbsOrigin(creep), Ability.GetCastRange(helm)) then
			target = creep
			break
		end
	end
	if not target then return false end
	Ability.CastTarget(helm, target, false, false, false, "morphling_farm_dominate")
	state.next_order = now + 0.25
	return true
end

local function game_minute()
	local dota_time = GameRules.GetDOTATime()
	if dota_time < 0 then return nil end
	return math.floor(dota_time / 60)
end

local function buy_clarity(hero, now)
	if not ui.clarity:Get() then return end
	local minute = game_minute()
	if minute == nil or state.last_clarity_buy_minute >= minute then return end
	if NPC.HasItem(hero, "item_clarity", false) or now < state.clarity_pending_until then return end
	local player = Players.GetLocal()
	if not player or Player.GetTotalGold(player) < 60 then return end
	if GameRules.GetStockCount(38, Entity.GetTeamNum(hero)) <= 0 then return end
	local hero_index = Entity.GetIndex(hero)
	local script_text = string.format(
		"Game.PrepareUnitOrders({OrderType:dotaunitorder_t.DOTA_UNIT_ORDER_PURCHASE_ITEM,TargetIndex:0,Position:[0,0,0],AbilityIndex:38,OrderIssuer:PlayerOrderIssuer_t.DOTA_ORDER_ISSUER_HERO_ONLY,UnitIndex:%d,Queue:false,ShowEffects:false});",
		hero_index
	)
	local sent = Engine.RunScript(script_text)
	state.last_clarity_buy_minute = minute
	state.clarity_pending_until = now + 5
	log(sent and "clarity purchase sent" or "clarity purchase order failed")
end

local function draw_status(hero)
	local world_pos = Entity.GetAbsOrigin(hero) + Vector(0, 0, NPC.GetHealthBarOffset(hero))
	local screen_pos, visible = Render.WorldToScreen(world_pos)
	if not visible then return end
	local healing = state.retreating
	local label = healing and L("mf_status_heal") or L("mf_status_farm")
	local color = healing and Color(92, 196, 235, 255) or Color(111, 214, 111, 255)
	local font_size, height = 11, 18
	local text_size = Render.TextSize(panel.status_font, font_size, label)
	local width = math.max(42, text_size.x + 14)
	local x = math.floor(screen_pos.x - width * 0.5)
	local y = math.floor(screen_pos.y - 60)
	Render.FilledRect(Vec2(x, y), Vec2(x + width, y + height), Color(14, 16, 18, 210), height * 0.5, Enum.DrawFlags.RoundCornersAll)
	Render.Text(panel.status_font, font_size, label, Vec2(x + (width - text_size.x) * 0.5, y + 2), color)
end

local function use_clarity(hero, all_neutrals, now)
	if not ui.clarity:Get() or state.attack_committed then return false end
	local minute = game_minute()
	if minute == nil or state.last_clarity_use_minute >= minute then return false end
	if NPC.GetMana(hero) >= NPC.GetMaxMana(hero) - 1 then return false end
	local hero_pos = Entity.GetAbsOrigin(hero)
	for _, creep in ipairs(all_neutrals) do
		if hero_pos:IsInRange2D(Entity.GetAbsOrigin(creep), 850) then return false end
	end
	local clarity = NPC.GetItem(hero, "item_clarity")
	if not clarity or not Ability.IsCastable(clarity, NPC.GetMana(hero)) then return false end
	Ability.CastTarget(clarity, hero, false, false, false, "morphling_farm_clarity")
	state.last_clarity_use_minute = minute
	state.clarity_pending_until = 0
	state.next_order = now + 0.2
	set_mode("using clarity")
	return true
end

local function retreat(hero, enemy, own_fountain, hp_pct, now)
	local hero_pos = Entity.GetAbsOrigin(hero)
	local destination = own_fountain
	if enemy and not destination then
		local enemy_pos = Entity.GetAbsOrigin(enemy)
		destination = hero_pos + enemy_pos:DirectionTo(hero_pos, 1200)
	end
	if not destination then return end
	if use_escape_items(hero, enemy, hp_pct, now) then return end

	if enemy and ui.escape_morph:Get() and hp_pct <= ui.escape_hp:Get() + 12 then
		local morph = NPC.GetAbility(hero, "morphling_morph_str")
		if morph and Ability.GetLevel(morph) > 0 and not Ability.GetToggleState(morph) then
			Ability.Toggle(morph)
			state.morph_owned = true
		end
	end

	if enemy and ui.escape_wave:Get() then
		local wave = NPC.GetAbility(hero, "morphling_waveform")
		if wave and Ability.IsCastable(wave, NPC.GetMana(hero)) then
			local cast_range = Ability.GetCastRange(wave)
			if cast_range < 100 then cast_range = 700 end
			local cast_pos = hero_pos:Extend2D(destination, math.max(100, cast_range - 35))
			Ability.CastPosition(wave, cast_pos, false, false, false, "morphling_farm_escape")
			state.next_order = now + 0.45
			return
		end
	end

	if now >= state.next_order then
		NPC.MoveTo(hero, destination, false, false, false, false, "morphling_farm_retreat")
		state.next_order = now + 0.35
	end
end

local function neutral_center(creeps)
	if #creeps == 0 then return nil end
	local x, y, z = 0, 0, 0
	for _, creep in ipairs(creeps) do
		local pos = Entity.GetAbsOrigin(creep)
		x, y, z = x + pos.x, y + pos.y, z + pos.z
	end
	return Vector(x / #creeps, y / #creeps, z / #creeps)
end

local function kite_destination(hero, creeps, distance)
	local hero_pos = Entity.GetAbsOrigin(hero)
	local center = neutral_center(creeps)
	local dx, dy = 1, 0
	if center and not center:IsInRange2D(hero_pos, 20) then
		dx, dy = hero_pos.x - center.x, hero_pos.y - center.y
	elseif state.own_fountain and not hero_pos:IsInRange2D(state.own_fountain, 20) then
		dx, dy = state.own_fountain.x - hero_pos.x, state.own_fountain.y - hero_pos.y
	end
	local length = math.sqrt(dx * dx + dy * dy)
	dx, dy = dx / math.max(1, length), dy / math.max(1, length)
	local best, best_score = nil, math.huge
	for _, angle in ipairs({ 0, 0.58, -0.58, 1.05, -1.05 }) do
		local cosine, sine = math.cos(angle), math.sin(angle)
		local rx, ry = dx * cosine - dy * sine, dx * sine + dy * cosine
		local candidate = Vector(hero_pos.x + rx * distance, hero_pos.y + ry * distance, hero_pos.z)
		local midpoint = Vector(hero_pos.x + rx * distance * 0.5, hero_pos.y + ry * distance * 0.5, hero_pos.z)
		local score = #Trees.InRadius(candidate, 150, true) * 3
			+ #TempTrees.InRadius(candidate, 150) * 3
			+ #Trees.InRadius(midpoint, 120, true)
			+ #TempTrees.InRadius(midpoint, 120)
		if score < best_score then best, best_score = candidate, score end
		if score == 0 then break end
	end
	if not best or best_score >= 6 then return hero_pos end
	return best
end

local function farm_attack(hero, target, creeps, now)
	if state.attack_committed then
		if now < state.attack_release then
			set_mode("releasing attack")
			return true
		end
		if now < state.next_attack then
			if now >= state.next_order then
				NPC.MoveTo(hero, kite_destination(hero, creeps, 240), false, false, false, false, "morphling_farm_kite")
				state.next_order = now + 0.16
			end
			set_mode("kiting neutrals")
			return true
		end
		state.attack_committed = false
		state.attack_target = nil
		return false
	end

	if not target or not Entity.IsAlive(target) then return false end
	local hero_pos = Entity.GetAbsOrigin(hero)
	local target_pos = Entity.GetAbsOrigin(target)
	local attack_range = NPC.GetAttackRange(hero) + NPC.GetAttackRangeBonus(hero)

	if not hero_pos:IsInRange2D(target_pos, math.max(100, attack_range - 25)) then
		if now >= state.next_order then
			local staging = target_pos:Extend2D(hero_pos, math.max(100, attack_range - 45))
			NPC.MoveTo(hero, staging, false, false, false, false, "morphling_farm_standoff")
			state.next_order = now + 0.18
		end
		set_mode("taking attack position")
		return true
	end

	local player = Players.GetLocal()
	if not player then return false end
	Player.AttackTarget(player, hero, target, false, false, false, "morphling_farm_attack")
	local attack_point = NPC.GetAttackAnimPoint(hero) or 0.5
	local face_time = NPC.GetTimeToFace(hero, target) or 0
	local attack_period = NPC.GetSecondsPerAttack(hero, false) or 1.5
	state.attack_committed = true
	state.attack_target = target
	state.attack_release = now + math.max(0.16, face_time + attack_point + 0.04)
	state.next_attack = now + math.max(0.5, attack_period)
	state.next_order = state.attack_release
	set_mode("attacking from range")
	return true
end

local function panel_origin()
	local screen = Render.ScreenSize()
	return Vec2(math.floor((screen.x - panel.w) * 0.5), math.floor((screen.y - panel.h) * 0.5))
end

local function map_point(origin, world)
	local span = panel.world_max - panel.world_min
	local x = origin.x + 9 + (world.x - panel.world_min) / span * panel.map_size
	local y = origin.y + panel.map_top + (panel.world_max - world.y) / span * panel.map_size
	return Vec2(x, y)
end

local function draw_panel(hero)
	local origin = panel_origin()
	local map_start = Vec2(origin.x + 9, origin.y + panel.map_top)
	local map_end = Vec2(map_start.x + panel.map_size, map_start.y + panel.map_size)
	local white = Color(235, 235, 235, 255)
	local dim = Color(160, 165, 174, 255)
	local bg = Color(16, 18, 22, 242)
	local border = Color(55, 59, 68, 255)
	local green = Color(45, 220, 95, 255)
	local red = Color(235, 65, 70, 255)
	local click = Input.IsKeyDownOnce(Enum.ButtonCode.KEY_MOUSE1)
	if state.map_team == nil then
		state.map_team = Entity.GetTeamNum(hero) == Enum.TeamNum.TEAM_DIRE and 1 or 0
	end

	Render.Shadow(origin, Vec2(origin.x + panel.w, origin.y + panel.h), Color(0, 0, 0, 190), 16, 5)
	Render.FilledRect(origin, Vec2(origin.x + panel.w, origin.y + panel.h), bg, 5)
	Render.Rect(origin, Vec2(origin.x + panel.w, origin.y + panel.h), border, 5, Enum.DrawFlags.None, 1)
	Render.Logo(Vec2(origin.x + 13, origin.y + 15), 7, -45, Color(255, 60, 90, 255), Color(255, 60, 90, 255))
	Render.Text(panel.title_font, 15, L("mf_panel_title"), Vec2(origin.x + 25, origin.y + 7), white)

	local tabs = {
		{ L("mf_panel_radiant"), 0, Color(45, 190, 92, 255) },
		{ L("mf_panel_dire"), 1, Color(205, 65, 70, 255) },
	}
	local tab_w = 147
	for index, tab in ipairs(tabs) do
		local x = origin.x + 9 + (index - 1) * (tab_w + 10)
		local selected = state.map_team == tab[2]
		local color = selected and tab[3] or Color(42, 42, 44, 255)
		Render.FilledRect(Vec2(x, origin.y + 35), Vec2(x + tab_w, origin.y + 56), color, 4)
		local label_size = Render.TextSize(panel.font, 12, tab[1])
		Render.Text(panel.font, 12, tab[1], Vec2(x + (tab_w - label_size.x) * 0.5, origin.y + 39), white)
		if click and Input.IsCursorInRect(x, origin.y + 35, tab_w, 21) then state.map_team = tab[2] end
	end

	Render.Image(panel.map_image, map_start, Vec2(panel.map_size, panel.map_size), Color(255, 255, 255, 255), 4)
	Render.Rect(map_start, map_end, border, 4, Enum.DrawFlags.None, 1)

	find_fountains(hero)
	for _, camp in ipairs(Camps.GetAll() or {}) do
		local center = camp_center(camp)
		if center then
			local point = map_point(origin, center)
			local enabled = camp_selected(camp)
			local side_color = camp_side(center) == 0 and green or red
			local color = enabled and side_color or Color(side_color.r, side_color.g, side_color.b, 95)
			local hovered = Input.IsCursorInRect(point.x - 9, point.y - 9, 18, 18)
			Render.FilledCircle(point, 7, Color(10, 14, 15, enabled and 235 or 170), 0, 1, 20)
			Render.Circle(point, hovered and 10 or 8, color, hovered and 3 or 2, 0, 1, false, 24)
			if enabled then Render.FilledCircle(point, 3, side_color, 0, 1, 16) end
			if click and hovered then set_camp_selected(camp, not enabled) end
		end
	end
end

local script = {}

function script.OnUpdate()
	local hero = Heroes.GetLocal()
	if not hero or NPC.GetUnitName(hero) ~= "npc_dota_hero_morphling" then reset() return end
	if not active() or not Entity.IsAlive(hero) or GameRules.IsPaused() then
		stop_strength_morph(hero)
		restore_treads(hero, GameRules.GetGameTime())
		state.attack_committed = false
		state.attack_target = nil
		state.camp = nil
		set_mode("idle")
		return
	end

	local now = GameRules.GetGameTime()
	if now < state.next_think then return end
	state.next_think = now + 0.18
	buy_clarity(hero, now)

	local health = Entity.GetHealth(hero)
	local max_health = math.max(1, Entity.GetMaxHealth(hero))
	local hp_pct = health * 100 / max_health
	local enemy = closest_enemy(hero)
	local own_fountain, enemy_fountain = find_fountains(hero)

	if enemy then
		state.attack_committed = false
		state.attack_target = nil
		state.retreating = true
		if state.camp then state.blocked[camp_key(state.camp)] = now + 10 end
		state.camp = nil
		set_mode("escaping enemy")
		retreat(hero, enemy, own_fountain, hp_pct, now)
		return
	end

	if hp_pct <= ui.escape_hp:Get() then state.retreating = true end
	if state.retreating then
		stop_strength_morph(hero)
		if hp_pct >= math.min(95, ui.escape_hp:Get() + 30) then
			state.retreating = false
		else
			state.attack_committed = false
			state.attack_target = nil
			state.camp = nil
			set_mode("recovering at fountain")
			retreat(hero, nil, own_fountain, hp_pct, now)
			return
		end
	end

	stop_strength_morph(hero)
	restore_treads(hero, now)
	local all_neutrals = neutrals()
	if use_clarity(hero, all_neutrals, now) then return end
	local current_center = state.camp and camp_center(state.camp) or nil
	if not state.camp or not current_center or not Camps.Contains(state.camp) or not camp_safe(hero, current_center) then
		state.camp = select_camp(hero, all_neutrals, now)
	end
	if not state.camp then
		state.attack_committed = false
		state.attack_target = nil
		set_mode("no safe camp")
		return
	end

	local center = camp_center(state.camp)
	local hero_pos = Entity.GetAbsOrigin(hero)
	local creeps = camp_creeps(state.camp, all_neutrals, hero)
	if #creeps == 0 then
		state.attack_committed = false
		state.attack_target = nil
		if hero_pos:IsInRange2D(center, 650) then
			local dota_time = GameRules.GetDOTATime()
			local wait = math.max(8, (math.floor(dota_time / 60) + 1) * 60 + 2 - dota_time)
			state.blocked[camp_key(state.camp)] = now + wait
			state.camp = nil
			set_mode("camp empty")
		elseif now >= state.next_order then
			NPC.MoveTo(hero, center, false, false, false, false, "morphling_farm_move")
			state.next_order = now + 0.45
			set_mode("moving to camp")
		end
		return
	end

	local target = hero_pos:ClosestToPoint(creeps)
	if not target then return end
	if state.attack_committed and farm_attack(hero, target, creeps, now) then return end
	if use_dominator(hero, creeps, now) then
		set_mode("dominating guard")
		return
	end
	local mana_pct = NPC.GetMana(hero) * 100 / math.max(1, NPC.GetMaxMana(hero))
	if ui.farm_wave:Get() and #creeps >= 2 then
		local wave = NPC.GetAbility(hero, "morphling_waveform")
		if wave and mana_pct >= ui.farm_mana:Get() and Ability.IsCastable(wave, NPC.GetMana(hero)) then
			local target_pos = Entity.GetAbsOrigin(target)
			local cast_range = Ability.GetCastRange(wave)
			local distance = hero_pos:Distance2D(target_pos)
			local center = neutral_center(creeps)
			local cast_pos = nil
			if center and hero_pos:IsInRange2D(center, 260) then
				local safe_pos = kite_destination(hero, creeps, math.max(300, cast_range - 35))
				if not safe_pos:IsInRange2D(hero_pos, 50) then cast_pos = safe_pos end
			elseif distance <= cast_range - 260 then
				cast_pos = hero_pos:Extend2D(target_pos, distance + 260)
			end
			if cast_pos then
				Ability.CastPosition(wave, cast_pos, false, false, false, "morphling_farm_wave")
				state.next_order = now + 0.4
				set_mode("waveform farm")
				return
			end
		end
	end
	if ui.farm_adaptive:Get() and mana_pct >= ui.farm_mana:Get() then
		local adaptive = NPC.GetAbility(hero, "morphling_adaptive_strike_agi")
		if adaptive and Ability.IsCastable(adaptive, NPC.GetMana(hero)) then
			local cast_range = Ability.GetCastRange(adaptive)
			local adaptive_target, adaptive_health = nil, -1
			for _, creep in ipairs(creeps) do
				local creep_pos = Entity.GetAbsOrigin(creep)
				local creep_health = Entity.GetHealth(creep)
				if hero_pos:IsInRange2D(creep_pos, cast_range) and creep_health > adaptive_health then
					adaptive_target, adaptive_health = creep, creep_health
				end
			end
			if adaptive_target then
				Ability.CastTarget(adaptive, adaptive_target, false, false, false, "morphling_farm_adaptive")
				state.next_order = now + 0.35
				set_mode("adaptive strike farm")
				return
			end
		end
	end

	farm_attack(hero, target, creeps, now)
end

function script.OnGameEnd()
	reset()
end

function script.OnDraw()
	if not ui.enable:Get() then return end
	local hero = Heroes.GetLocal()
	if not hero or NPC.GetUnitName(hero) ~= "npc_dota_hero_morphling" then return end
	if active() and Entity.IsAlive(hero) then draw_status(hero) end
	if ui.panel_key:IsToggled() then draw_panel(hero) end
end

return script
