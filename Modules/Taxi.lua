--[[--------------------------------------------------------------------
	Hydra
	Multibox leveling helper.
	Written by Phanx <addons@phanx.net>
	Copyright © 2010–2012 Phanx. Some rights reserved. See LICENSE.txt for details.
	http://www.wowinterface.com/downloads/info17572-Hydra.html
	http://www.curse.com/addons/wow/hydra
------------------------------------------------------------------------
	Hydra Taxi
	* Autoselect the last taxi node selected by anyone in the party
----------------------------------------------------------------------]]

local _, core = ...

local L = core.L

local SOLO, PARTY, TRUSTED, LEADER = 0, 1, 2, 3
local playerName = UnitName("player")

local taxiTime, taxiNode, taxiNodeName = 0

local module = core:RegisterModule("Taxi", CreateFrame("Frame"))
module:SetScript("OnEvent", function(f, e, ...) return f[e] and f[e](f, ...) end)

module.defaults = { enable = true, timeout = 60 }

------------------------------------------------------------------------

function module:CheckState()
	if core.state == SOLO or not self.db.enable then
		self:Debug("Disable module: Taxi")
		self:UnregisterAllEvents()
	else
		self:Debug("Enable module: Taxi")
		self:RegisterEvent("CHAT_MSG_ADDON")
		self:RegisterEvent("TAXIMAP_OPENED")
		if not IsAddonMessagePrefixRegistered( "HydraTaxi" ) then
			RegisterAddonMessagePrefix( "HydraTaxi" )
		end
	end
	taxiNode, taxiNodeName, taxiTime = nil, nil, 0
end

------------------------------------------------------------------------

function module:CHAT_MSG_ADDON(prefix, message, channel, sender)
	if prefix ~= "HydraTaxi" or channel ~= "PARTY" or sender == playerName or not core:IsTrusted(sender) then return end
	self:Debug("Comm received from", sender, "->", message)

	if message == "TIMEOUT" then
		return core:Print( L["ERROR: %s: Taxi timeout reached."], sender )
	elseif message == "MISMATCH" then
		return core:Print( L["ERROR: %s: Taxi node mismatch."], sender )
	end

	local node, nodeName = message:trim():match("^(%d+) (.+)$")
	if node and nodeName then
		core:Print( L["%1$s set the party taxi to %2$s."], sender, nodeName )
		taxiNode, taxiNodeName, taxiTime = node, nodeName, GetTime()
	end
end

function module:TAXIMAP_OPENED()
	if not taxiNode then return end -- we're picking the taxi
	if IsShiftKeyDown() then return end -- we're doing something else

	if GetTime() - taxiTime > self.db.timeout then
		taxiNode, taxiNodeName, taxiTime = nil, nil, 0
		return SendAddonMessage("HydraTaxi", "TIMEOUT", "PARTY")
	end

	if TaxiNodeName(taxiNode) ~= taxiNodeName then
		local found
		for i = 1, NumTaxiNodes() do
			if TaxiNodeName(i) == taxiNodeName then
				taxiNode = i
				found = true
			end
		end
		if not found then
			taxiNode, taxiNodeName, taxiTime = nil, nil, 0
			return SendAddonMessage("HydraTaxi", "MISMATCH", "PARTY")
		end
	end

	if IsMounted() then Dismount() end -- #TODO: druids unshift?
	TakeTaxiNode(taxiNode)
	taxiNode, taxiNodeName, taxiTime = nil, nil, 0
end

------------------------------------------------------------------------

hooksecurefunc("TakeTaxiNode", function(i)
	if taxiNode then return end -- we're following someone
	if IsShiftKeyDown() then return end -- we're doing something else
	local name = TaxiNodeName(i)
	module:Debug("Broadcasting taxi node", i, name)
	SendAddonMessage("HydraTaxi", i .. " " .. name, "PARTY")
end)

------------------------------------------------------------------------

SLASH_HYDRA_CLEARTAXI1 = "/cleartaxi"
do
	local slash = rawget( core.L, "SLASH_HYDRA_CLEARTAXI2" )
	if slash and slash ~= SLASH_HYDRA_CLEARTAXI1 then
		SLASH_HYDRACLEARTAXI2 = slash
	end
end

function SlashCmdList.HYDRA_CLEARTAXI()
	if taxiNode then
		taxiTime, taxiNode, taxiNodeName = 0, nil, nil
		module:Print("Party taxi cleared.")
	end
end

------------------------------------------------------------------------