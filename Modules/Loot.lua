--[[--------------------------------------------------------------------
	Hydra
	Multibox leveling helper.
	Copyright (c) 2010-2016 Phanx <addons@phanx.net>. All rights reserved.
	https://github.com/Phanx/Hydra
	https://mods.curse.com/addons/wow/hydra
	https://www.wowinterface.com/downloads/info17572-Hydra.html
------------------------------------------------------------------------
	Hydra Loot
	Automatically sets the loot method to Free For All in trusted groups,
	and back to Group Loot if a non-trusted player joins the group.
----------------------------------------------------------------------]]

local _, Hydra = ...
local L = Hydra.L
local STATE_SOLO, STATE_INSECURE, STATE_SECURE, STATE_LEADER = Hydra.STATE_SOLO, Hydra.STATE_INSECURE, Hydra.STATE_SECURE, Hydra.STATE_LEADER

local Loot = Hydra:NewModule("Loot")
Loot.defaults = { enable = true }

------------------------------------------------------------------------

function Loot:ShouldEnable()
	return self.db.enable
end

function Loot:OnEnable()
--	self:RegisterEvent("GROUP_ROSTER_CHANGED")
	self:OnStateChange(Hydra.state)
end

function Loot:OnStateChange(newstate)
	if UnitIsGroupLeader("player") then
		local loot = GetLootMethod()
		if newstate >= STATE_SECURE then
			if loot ~= "freeforall" then
				self:Debug("Setting loot method to FFA.")
				SetLootMethod("freeforall")
			end
		elseif newstate > STATE_SOLO then
			if loot == "freeforall" then
				self:Debug("Setting loot method to Group.")
				SetLootMethod("group")
			end
		end
	end
end

------------------------------------------------------------------------

Loot.displayName = L["Loot"]
function Loot:SetupOptions(panel)
	local title, notes = panel:CreateHeader(L.Loot, L.Loot_Info)

	local enable = panel:CreateCheckbox(L.Enable, L.Enable_Info)
	enable:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -12)
	function enable:OnValueChanged(value)
		Loot.db.enable = value
		Loot:Refresh()
	end
--[[
	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	help:SetPoint("BOTTOMLEFT", 16, 16)
	help:SetPoint("BOTTOMRIGHT", -16, 16)
	help:SetHeight(112)
	help:SetJustifyH("LEFT")
	help:SetJustifyV("BOTTOM")
	help:SetText(L.LootHelpText)
]]
	panel.refresh = function()
		enable:SetChecked(Loot.db.enable)
	end
end
