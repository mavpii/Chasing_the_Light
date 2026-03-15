--
-- Naia boss utilities
--

local _ = wesnoth.textdomain "wesnoth-Naia"

local BOSS_TITLE_COLOR = { 210, 60, 60 }
local BOSS_TITLE_SIZE = 22
local BOSS_TITLE_OFFSET = 10

local BOSS_SUBTITLE_COLOR = { 215, 215, 215 }
local BOSS_SUBTITLE_SIZE = 14
local BOSS_SUBTITLE_OFFSET = BOSS_TITLE_OFFSET + 30

local BOSS_BAR_BG_COLOR = '#0a2233'
local BOSS_BAR_FADE_TIME = 1000
local BOSS_BAR_FADE_DELAY = 1500
local BOSS_BAR_SIZE = 10
local BOSS_BAR_OFFSET = BOSS_SUBTITLE_OFFSET + 22

local BOSS_ALERT_SIZE = 32
local BOSS_ALERT_OFFSET = -200
local BOSS_ALERT_DURATION = 3000
local BOSS_ALERT_FADE_TIME = 1000

local BOSS_UI_TABLE = "__naia_boss_ui"

local FULL_BLOCK = '█'
local EMPTY_BLOCK = FULL_BLOCK
local BAR_LENGTH = 60

----------------------------------------------------------------
-- ГРАДІЄНТ КОЛЬОРУ HP BAR
----------------------------------------------------------------
local function gradient_color(i, total)
	local t = i / total

	local r = math.floor(120 + (220 - 120) * t)
	local g = math.floor(20  + (40  - 20)  * t)
	local b = math.floor(20  + (40  - 20)  * t)

	return ("#%02x%02x%02x"):format(r, g, b)
end

----------------------------------------------------------------
-- BAR FACTORY
----------------------------------------------------------------
local function bar_factory(current, max)

	local bar = ""

	local cnt = math.ceil(BAR_LENGTH * math.max(0, current) / math.max(1, max))
	local rem = BAR_LENGTH - cnt

	if cnt > 0 then
		for i = 1, cnt do
			bar = bar .. ("<span color='%s' rise='2pt'>%s</span>"):format(
				gradient_color(i, BAR_LENGTH),
				FULL_BLOCK
			)
		end
	end

	if rem > 0 then
		bar = bar .. ("<span color='%s' rise='2pt'>%s</span>"):format(
			BOSS_BAR_BG_COLOR,
			string.rep(EMPTY_BLOCK, rem)
		)
	end

	return bar
end

----------------------------------------------------------------
-- GAMESTATE
----------------------------------------------------------------
local function verify_gamestate()
	if wml.variables[BOSS_UI_TABLE] == nil then
		wml.variables[BOSS_UI_TABLE] = {
			id = "none",
			title = nil,
			subtitle = nil,
			auto_manage = true,
		}
	end
end

local boss_state = {}

setmetatable(boss_state, {
	["__index"] = function(t, k)

		verify_gamestate()

		if k == "unit" then
			local boss_id = wml.variables[("%s.id"):format(BOSS_UI_TABLE)]

			if boss_id == nil or boss_id == "none" then
				return nil
			end

			return wesnoth.units.get(boss_id)
		end

		return wml.variables[("%s.%s"):format(BOSS_UI_TABLE, k)]
	end,

	["__newindex"] = function(t, k, v)

		verify_gamestate()

		if k == "unit" then
			local boss_id = "none"

			if v ~= nil then
				boss_id = v
			end

			k = "id"
		end

		wml.variables[("%s.%s"):format(BOSS_UI_TABLE, k)] = v
	end
})

----------------------------------------------------------------
-- UI ELEMENT CLASS
----------------------------------------------------------------
local BossUiElement = {}
BossUiElement.__index = BossUiElement

function BossUiElement:new(text, offset, options)

	local o = {}

	setmetatable(o, self)

	o.text = text
	o.offset = offset
	o.options = options
	o.obj_ = nil

	return o
end

function BossUiElement:update(self_destruct)

	self.options.duration = "unlimited"
	self.options.halign = "center"
	self.options.valign = "top"
	self.options.location = { 0, self.offset }

	if self_destruct then
		self.options.duration = BOSS_BAR_FADE_DELAY
		self.options.fade_time = BOSS_BAR_FADE_TIME
	end

	local text = self.text or ""

	if self.obj_ then
		self.obj_:remove(0)
	end

	self.obj_ = wesnoth.interface.add_overlay_text(text, self.options)

	if self_destruct then
		self.obj_ = nil
	end
end

function BossUiElement:remove()

	if not self.obj_ then
		return
	end

	self.obj_:remove(BOSS_BAR_FADE_TIME)
	self.obj_ = nil
end

----------------------------------------------------------------
-- UI STATE
----------------------------------------------------------------
local ui = {

	active = false,

	title = nil,
	subtitle = nil,
	bar = nil,
}

----------------------------------------------------------------
-- UI UPDATE
----------------------------------------------------------------
function ui.update()

	local unit = boss_state.unit

	if unit == nil then
		ui.remove()
		return
	end

	local name = boss_state.title
	local sub = ("– %s –"):format(boss_state.subtitle)

	local hp = unit.hitpoints
	local max_hp = unit.max_hitpoints

	local padding = string.rep(" ", #(("%d / %d"):format(hp, max_hp)))

	local bar = ("<b><span size='125%%'>%s</span>  %s  <span size='125%%' color='#d7d7d7'>%d / %d</span></b>")
		:format(padding, bar_factory(hp, max_hp), hp, max_hp)

	if not ui.title then

		ui.title = BossUiElement:new(name, BOSS_TITLE_OFFSET, {
			color = BOSS_TITLE_COLOR,
			size = BOSS_TITLE_SIZE
		})

	else
		ui.title.text = name
	end

	if not ui.subtitle then

		ui.subtitle = BossUiElement:new(sub, BOSS_SUBTITLE_OFFSET, {
			color = BOSS_SUBTITLE_COLOR,
			size = BOSS_SUBTITLE_SIZE
		})

	else
		ui.subtitle.text = sub
	end

	if not ui.bar then

		ui.bar = BossUiElement:new(bar, BOSS_BAR_OFFSET, {
			size = BOSS_BAR_SIZE
		})

	else
		ui.bar.text = bar
	end

	local temporary = unit.hitpoints < 1 and boss_state.auto_manage

	ui.title:update(temporary)
	ui.subtitle:update(temporary)
	ui.bar:update(temporary)

	if temporary then

		ui.title = nil
		ui.subtitle = nil
		ui.bar = nil

		boss_state.unit = "none"
	end
end

function ui.remove()

	if ui.title then
		ui.title:remove()
		ui.title = nil
	end

	if ui.subtitle then
		ui.subtitle:remove()
		ui.subtitle = nil
	end

	if ui.bar then
		ui.bar:remove()
		ui.bar = nil
	end
end

----------------------------------------------------------------
-- WML ACTIONS
----------------------------------------------------------------
function wesnoth.wml_actions.boss_ui(cfg)

	local unit_id = cfg.id

	if cfg.remove then
		unit_id = "none"
	end

	if unit_id == nil then
		wml.error("[boss_ui]: Must specify a boss unit id")
	end

	if cfg.auto_manage == nil then
		boss_state.auto_manage = true
	else
		boss_state.auto_manage = not not cfg.auto_manage
	end

	boss_state.title = cfg.name or _ "Chaos Warlord"
	boss_state.subtitle = cfg.subtitle or _ "The Fire of Uria"

	boss_state.unit = cfg.id

	ui.update()
end

function wesnoth.wml_actions.update_boss_ui()
	ui.update()
end

function wesnoth.wml_actions.boss_popup()

	local banner = _ "Enemy boss sighted!"

	wesnoth.interface.add_overlay_text(
		("<b>%s</b>"):format(banner),
		{
			color = BOSS_TITLE_COLOR,
			size = BOSS_ALERT_SIZE,
			location = { 0, BOSS_ALERT_OFFSET },
			duration = BOSS_ALERT_DURATION,
			fade_time = BOSS_ALERT_FADE_TIME
		}
	)
end

----------------------------------------------------------------
-- EVENTS
----------------------------------------------------------------
local HOOK_EVENTS = "preload,turn refresh,unit placed,last breath,die,attacker hits,defender hits,attack end"
local CLEANUP_EVENTS = "victory,defeat"

on_event(HOOK_EVENTS, ui.update)

on_event(CLEANUP_EVENTS, function()
	wml.variables[BOSS_UI_TABLE] = nil
end)