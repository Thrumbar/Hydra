--[[--------------------------------------------------------------------
	Hydra
	Multibox leveling helper.
	Copyright (c) 2010-2016 Phanx <addons@phanx.net>. All rights reserved.
	https://github.com/Phanx/Hydra
	https://mods.curse.com/addons/wow/hydra
	https://www.wowinterface.com/downloads/info17572-Hydra.html
------------------------------------------------------------------------
	Hydra Mount
	* Mount and dismount together.
----------------------------------------------------------------------]]

local _, Hydra = ...;
local L = Hydra.L;
local STATE_SOLO, STATE_INSECURE, STATE_SECURE, STATE_LEADER = Hydra.STATE_SOLO, Hydra.STATE_INSECURE, Hydra.STATE_SECURE, Hydra.STATE_LEADER;

local Mount = Hydra:NewModule("Mount");
Mount.defaults = {
	mount = true,
	dismount = true,
}

local ACTION_DISMOUNT, ACTION_MOUNT = "DISMOUNT", "MOUNT";
local MESSAGE_ERROR = "ERROR";

local isCasting, isMounted, responding;

local MountIDs;

------------------------------------------------------------------------

function Mount:ShouldEnable()
	return Hydra.state > STATE_SOLO and (self.db.mount or self.db.dismount)
end

function Mount:OnEnable()
	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	if not UnitAffectingCombat("player") then
		self:PLAYER_REGEN_ENABLED();
	end

	MountIDs = C_MountJournal.GetMountIDs();

	if IsMounted() then
		for i = 1, #MountIDs do
			local _, spellID, _, active = C_MountJournal.GetMountInfoByID(MountIDs[i]);
			if active then
				local name = GetSpellInfo(spellID);
				self:Debug("Already mounted:", name);
				isMounted = name;
				self:RegisterUnitEvent("UNIT_AURA", "player");
				break
			end
		end
	end
end

------------------------------------------------------------------------

local mountTypeString = {
	-- http://www.wowinterface.com/forums/showthread.php?p=294988#post294988
	[230] = "GROUND",
	[231] = "TURTLE",
	[232] = "VASHJIR", -- Abyssal / Vashj'ir Seahorse, 450% swim speed, zone limited
	[241] = "AQ40",
	[242] = "GHOST",
	[247] = "AIR", -- Red Flying Cloud
	[248] = "AIR",
	[254] = "WATER", -- Subdued Seahorse, 300% swim speed
	[269] = "WATER_WALKING", -- Azure/Crimson Water Strider
	[284] = "Chauffeured Mekgineer's Chopper" or "Chauffeured Mechano-Hog"
}

function Mount:OnAddonMessage(message, channel, sender)
	local target = Ambiguate(sender, "none")
	if not Hydra:IsTrusted(sender) or not (UnitInParty(target) or UnitInRaid(target)) then return end
	self:Debug("OnAddonMessage", message, channel, sender)

	local action, remoteID, remoteName = strsplit(" ", message, 3)

	if action == MESSAGE_ERROR then
		self:Print("ERROR: " .. L.MountMissing, sender)
		return
	elseif action == ACTION_DISMOUNT then
		self:Debug(sender, "dismounted")
		if self.db.dismount then
			responding = true
			Dismount();
			responding = nil
		end
		return
	end

	if action ~= ACTION_MOUNT or not remoteID or not remoteName or not self.db.mount then return end

	remoteID = tonumber(remoteID)
	self:Debug(sender, "mounted on", remoteID, remoteName)

	if IsMounted() then return self:Debug("Already mounted.") end
	if not UnitIsVisible(target) then return self:Debug("Not mounting because", sender, "is out of range.") end

	responding = true

	-- 1. Look for same mount
	if not self.db.mountRandom then
		local name, spellID = C_MountJournal.GetMountInfoByID(remoteID)
		if name then
			self:Debug("Found same mount", name)
			C_MountJournal.SummonByID(remoteID)
			responding = nil
			return
		end
	end

	-- 2. Look for equivalent mount
	local mountType, equivalent
	local _, _, _, _, mountTypeID = C_MountJournal.GetMountInfoExtraByID(remoteID)
	if mountTypeID then
		mountType = mountTypeString[mountTypeID]
	else
		return self:Debug("Mount type not recognized")
	end
	for i = 1, #MountIDs do
		local mountID = MountIDs[i]
		local _, _, _, _, isUsable = C_MountJournal.GetMountInfoByID(mountID)
		if isUsable then
			local _, _, _, _, mountTypeID = C_MountJournal.GetMountInfoExtraByID(mountID)
			if mountTypeString[mountTypeID] == mountType then
				self:Debug("Found equivalent mount", name)
				if not equivalent then
					equivalent = mountID
					if not self.db.mountRandom then
						break
					end
				elseif type(equivalent) == "table" then
					tinsert(equivalent, mountID)
				else
					equivalent = { equivalent, mountID }
				end
			end
		end
	end
	local mountID = type(equivalent) == "table" and equivalent[random(#equivalent)] or equivalent
	if mountID then
		local name = C_MountJournal.GetMountInfoByID(mountID)
		self:Debug("Using equivalent mount", name)
		C_MountJournal.SummonByID(mountID)
		responding = nil
		return
	end

	-- 3. Admit defeat
	self:SendAddonMessage(MESSAGE_ERROR)
	responding = nil
end

------------------------------------------------------------------------

function Mount:PLAYER_REGEN_DISABLED()
	--self:Debug("PLAYER_REGEN_DISABLED", UnitAffectingCombat("player"))
	self:UnregisterEvent("UNIT_SPELLCAST_START")
end

function Mount:PLAYER_REGEN_ENABLED()
	--self:Debug("PLAYER_REGEN_ENABLED", UnitAffectingCombat("player"))
	self:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
end

function Mount:UNIT_SPELLCAST_START(unit, castID, spellID)
	--self:Debug("UNIT_SPELLCAST_START", spellName)
	for i = 1, #MountIDs do
		local mountID = MountIDs[i]
		local mountName, mountSpellID = C_MountJournal.GetMountInfoByID(mountID)
		if mountSpellID == spellID then
			if not responding then
				self:Debug("Summoning mount", mountName, mountID, mountSpellID)
				self:SendAddonMessage(ACTION_MOUNT .. " " .. mountID .. " " .. mountName)
				isCasting = spellName
			end
			self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
			self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
		end
	end
end

function Mount:UNIT_SPELLCAST_SUCCEEDED(unit, castID, spellID)
	--self:Debug("UNIT_SPELLCAST_SUCCEEDED", spellName)
	if spellID == isCasting then
		isMounted = spellID
		self:Debug("Mounted!")
		self:RegisterUnitEvent("UNIT_AURA", "player")
	end
end

function Mount:UNIT_SPELLCAST_STOP(unit, castID, spellID)
	--self:Debug("UNIT_SPELLCAST_STOP", spellName)
	self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:UnregisterEvent("UNIT_SPELLCAST_STOP")
end

function Mount:UNIT_AURA(unit)
	if not UnitBuff(unit, _, isMounted) then
		if not responding then
			self:Debug("Dismounted");
			self:SendAddonMessage(ACTION_DISMOUNT);
		end
		self:UnregisterEvent("UNIT_AURA");
		isMounted = nil
	end
end

------------------------------------------------------------------------

Mount.displayName = L.Mount
function Mount:SetupOptions(panel)
	local title, notes = panel:CreateHeader(L.Mount, L.Mount_Info)

	local mount = panel:CreateCheckbox(L.MountTogether, L.MountTogether_Info)
	mount:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -12)
	function mount:OnValueChanged(value)
		Mount.db.mount = value
		Mount:IsEnabled()
	end

	local mountRandom = panel:CreateCheckbox(L.MountRandom, L.MountRandom)
	mountRandom:SetPoint("TOPLEFT", mount, "BOTTOMLEFT", 0, -8)
	function mountRandom:OnValueChanged(value)
		Mount.db.mountRandom = value
		Mount:IsEnabled()
	end

	local dismount = panel:CreateCheckbox(L.Dismount, L.Dismount_Info)
	dismount:SetPoint("TOPLEFT", mountRandom, "BOTTOMLEFT", 0, -8)
	function dismount:OnValueChanged(value)
		Mount.db.dismount = value
		Mount:IsEnabled()
	end

	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	help:SetPoint("BOTTOMLEFT", 16, 16)
	help:SetPoint("BOTTOMRIGHT", -16, 16)
	help:SetHeight(112)
	help:SetJustifyH("LEFT")
	help:SetJustifyV("BOTTOM")
	help:SetText(L.MountHelpText)

	panel.refresh = function()
		mount:SetChecked(Mount.db.mount)
		mountRandom:SetChecked(Mount.db.mountRandom)
		dismount:SetChecked(Mount.db.dismount)
	end
end

------------------------------------------------------------------------
--[[ NOT CURRENTLY USED

local mountPassengers = {
	[61467]  = 2, -- Grand Black War Mammoth (horde)
	[61465]  = 2, -- Grand Black War Mammoth (alliance)
	[122708] = 2, -- Grand Expedition Yak
	[61469]  = 2, -- Grand Ice Mammoth (horde)
	[61470]  = 2, -- Grand Ice Mammoth (alliance)
	[55531]  = 1, -- Mechano-hog
	[60424]  = 1, -- Mekgineer's Chopper
	[121820] = 1, -- Obsidian Nightwing
	[93326]  = 1, -- Sandstone Drake
	[61447]  = 2, -- Traveler's Tundra Mammoth (horde)
	[61425]  = 2, -- Traveler's Tundra Mammoth (alliance)
	[75973]  = 1, -- X-53 Touring Rocket
}

function Mount:GetMountPassengers(id)
	return self.mountSpecial.passengers[id]
end
]]
