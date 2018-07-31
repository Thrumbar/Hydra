--[[--------------------------------------------------------------------
	Hydra
	Multibox leveling helper.
	Copyright (c) 2010-2016 Phanx <addons@phanx.net>. All rights reserved.
	https://github.com/Phanx/Hydra
	https://mods.curse.com/addons/wow/hydra
	https://www.wowinterface.com/downloads/info17572-Hydra.html
------------------------------------------------------------------------
	Hydra Chat
	* Forwards whispers to characters without app focus to party chat
	* Relays responses to forwarded whispers in party chat back to the
		original sender as a whisper from the forwarding character
	* Respond to a whisper forwarded by a character other than the last
		forwarder by typing "@name message" in party chat, where "name" is
		the character that forwarded the whipser
	* Respond to a whisper forwarded by a character that has since
		forwarded another whisper, or send an arbitrary whipser from a
		character, by whispering the character with "@name message", where
		"name" is the target of the message
----------------------------------------------------------------------]]

local _, Hydra = ...
local L = Hydra.L
local STATE_SOLO, STATE_INSECURE, STATE_SECURE, STATE_LEADER = Hydra.STATE_SOLO, Hydra.STATE_INSECURE, Hydra.STATE_SECURE, Hydra.STATE_LEADER
local PLAYER, REALM, PLAYERREALM = Hydra.PLAYER_NAME, Hydra.PLAYER_REALM, Hydra.PLAYER_FULLNAME

local Chat = Hydra:NewModule("Chat")
Chat:SetScript("OnUpdate", function() frameTime = GetTime() end)
Chat:Hide()

Chat.defaults = {
	enable = true,
	mode = "LEADER", -- APPFOCUS | LEADER
	timeout = 300,
}

local groupForwardTime, groupForwardFrom, hasActiveConversation = 0
local whisperForwardTime, whisperForwardTo, whisperForwardMessage = 0
local frameTime, hasFocus = 0

L.WhisperFromGM = "\124TInterface\\ChatFrame\\UI-ChatIcon-Blizz.blp:0:2:0:-3\124t" .. L.WhisperFromGM

------------------------------------------------------------------------

function Chat:ShouldEnable()
	-- #TEMP: fix old lowercase entry
	self.db.mode = strupper(self.db.mode)

	return self.db.enable and Hydra.state >= STATE_SECURE
end

function Chat:OnEnable()
	self:RegisterEvent("CHAT_MSG_PARTY")
	self:RegisterEvent("CHAT_MSG_PARTY_LEADER")
	self:RegisterEvent("CHAT_MSG_RAID")
	self:RegisterEvent("CHAT_MSG_RAID_LEADER")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("CHAT_MSG_WHISPER")
	self:RegisterEvent("CHAT_MSG_BN_WHISPER")

	self:SetShown(self.db.mode == "APPFOCUS")
end

function Chat:OnDisable()
	self:Hide()
end

------------------------------------------------------------------------

local playerToken = "@" .. PLAYER .. "%-?%S*" -- allow but don't require a realm

function Chat:CHAT_MSG_PARTY(message, sender) -- #TODO: check if player is "name" or "name-realm"
	if sender == PLAYER or sender == PLAYERREALM or strmatch(message, "^!") then return end -- command or error response

	self:Debug("CHAT_MSG_PARTY", sender, message)

	if strmatch(message, "^>> .-: .+$") then
		if not strmatch(message, "POSSIBLE SPAM") then
			-- someone else forwarded a whisper, our conversation is no longer the active one
			self:Debug("Someone else forwarded a whisper.")
			hasActiveConversation = nil
		end

	elseif hasActiveConversation and not message:match("^@") then
		-- someone responding to our last forwarded whisper
		self:Debug("hasActiveConversation")
		if GetTime() - groupForwardTime > self.db.timeout then
			-- it's been a while
			hasActiveConversation = nil
			self:SendChatMessage("!ERROR: " .. L.GroupTimeoutError)
		else
			-- forwarding response to whisper sender
			self:SendChatMessage(message, groupForwardFrom)
			groupForwardTime = GetTime()
		end

	elseif groupForwardFrom then
		-- we forwarded something earlier
		local _, messageStart = strfind(message, playerToken)
		local text = messageStart and strtrim(strsub(message, messageStart + 1))
		if text and strlen(text) > 0 then
			-- someone responding to our last forward
			self:Debug("Detected response to old forward:", text)
			self:SendChatMessage(text, groupForwardFrom)
		end
	end
end

Chat.CHAT_MSG_PARTY_LEADER = Chat.CHAT_MSG_PARTY
Chat.CHAT_MSG_INSTANCE_CHAT = Chat.CHAT_MSG_PARTY
Chat.CHAT_MSG_RAID = Chat.CHAT_MSG_PARTY
Chat.CHAT_MSG_RAID_LEADER = Chat.CHAT_MSG_PARTY

------------------------------------------------------------------------

local ignorewords = {
	PLAYER, -- spammers seem to think addressing you by your character's name adds a personal touch...
	"account",
	"battle", "bonus", "buy", "blizz",
	"cheap", "complain", "contest", "coupon", "customer",
	"dear", "deliver", "detect", "discount",
	"extra",
	"fast track", "free",
	"gift", "gold",
	"honorablemention",
	"illegal", "in",
	"lowest", "lucky",
	"mrpopularity",
	"order",
	"powerle?ve?l", "price", "promoti[on][gn]",
	"recruiting", "reduced",
	"safe", "secure", "server", "service", "scan", "stock", "suspecte?d?", "suspend",
	"validat[ei]", "verif[iy]", "violat[ei]", "visit",
	"welcome", "www",
	"%d+%.?%d*eur", "%d+%.?%d*dollars",
	"[\226\130\172$\194\163]%d+",
}

local lastForwardedTo, lastForwardedMessage

function Chat:CHAT_MSG_WHISPER(message, sender, _, _, _, flag, _, _, _, _, _, guid)
	self:Debug("CHAT_MSG_WHISPER", flag, sender, message)
	local senderNameOnly = Ambiguate(sender, "none")

	if UnitInRaid(senderNameOnly) or UnitInParty(senderNameOnly) then
		self:Debug("Sender in group.")

		-- a group member whispered me "@Someone Hello!"
		local target, text = strmatch(message, "^@(.-) (.+)$")

		if target and text then
			-- sender wants us to whisper target with text
			self:Debug("Forwarding message to", target, ":", text)
			whisperForwardTo, whisperForwardTime = target, GetTime()
			self:SendChatMessage(text, target)

		elseif whisperForwardTo then
			-- we've forwarded to whisper recently
			self:Debug("Previously forwarded a whisper...")
			if GetTime() - whisperForwardTime > self.db.timeout then
				-- it's been a while since our last forward to whisper
				self:Debug("...but the timeout has been reached.")
				whisperForwardTo = nil
				self:SendChatMessage("!ERROR: " .. L.WhisperTimeoutError, sender)

			elseif message ~= whisperForwardMessage then
				-- whisper last forward target
				self:Debug("...forwarding :OnValueChanged( whisper to the same target.")
				whisperForwardTime = GetTime()
				self:SendChatMessage(message, whisperForwardTo)

			else
				-- message was echoed, avoid a loop
				self:Debug("Loop averted!")
			end
		end
	else
		local active
		if self.db.mode == "APPFOCUS" then
			active = GetTime() - frameTime < 0.1
		else
			active = UnitIsGroupLeader("player")
		end
		self:Debug("active", active)
		if not active then -- someone outside the group whispered me
			if flag == "GM" then
				self:SendAddonMessage(format("GM |cff00ccff%s|r %s", sender, message))
				self:SendChatMessage(format(">> GM %s: %s", sender, message))

			else
				local spamwords = 0
				local searchstring = gsub(strlower(message), "%W", "")
				for i = 1, #ignorewords do
					if strfind(searchstring, ignorewords[i]) then
						spamwords = spamwords + 1
					end
				end
				if spamwords > 3 then
					message = "POSSIBLE SPAM"
					hasActiveConversation, groupForwardFrom, groupForwardTime = true, sender, GetTime()
				end

				local color
				if guid and guid ~= "" then
					local _, class = GetPlayerInfoByGUID(guid)
					if class then
						color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
					end
				end
				self:SendAddonMessage(format("W %s %s", (color and format("\124cff%02x%02x%02x%s\124r", color.r * 255, color.g * 255, color.b * 255, sender) or sender), message))
				self:SendChatMessage(format(">> %s: %s", sender, message))
			end
		end
	end
end

------------------------------------------------------------------------

function Chat:CHAT_MSG_BN_WHISPER(message, sender, _, _, _, _, _, _, _, _, _, _, pID)
	self:Debug("CHAT_MSG_BN_WHISPER", sender, pID, message)
	local _, _, battleTag = BNGetFriendInfoByID(pID)
	self:SendAddonMessage(strjoin("§", "BW", battleTag, message))
end

function Chat:CHAT_MSG_BN_CONVERSATION(message, sender, _, channel, _, _, _, channelNumber, _, _, _, _, pID)
	self:Debug("CHAT_MSG_BN_CONVERSATION", sender, message)
	self:SendAddonMessage(strjoin("§", "BC", battleTag, message, channel, channelNumber))
end

------------------------------------------------------------------------

function Chat:CHAT_MSG_SYSTEM(message)
	if message == ERR_FRIEND_NOT_FOUND then
		-- the whisper couldn't be forwarded
	end
end

------------------------------------------------------------------------

function Chat:OnAddonMessage(message, channel, sender)
	if not Hydra:IsTrusted(sender) or not UnitInParty(sender) or not UnitInRaid(sender) then return end

	local fwdEvent, fwdSender, fwdMessage = strmatch(message, "^([^%s§]+)[%§]([^%s§]+)[%§]?(.*)$")
	self:Debug("HydraChat", sender, fwdEvent, fwdSender, fwdMessage)

	if fwdEvent == "GM" then
		local message = format(L.WhisperFromGM, sender)
		self:Debug(message)
		self:Alert(message, true)
		self:Print(message)

	elseif fwdEvent == "W" then
		self:Debug(L.WhisperFrom, sender, fwdSender)

	elseif fwdEvent == "BW" then
		local found
		for i = 1, BNGetNumFriends() do
			local id, name, tag, useTag, _, _, _, _, _, _, _, _, _, useName = BNGetFriendInfo(i)
			if tag == fwdSender then
				found = true
				for i = 1, 10 do
					local frame = _G["ChatFrame"..i]
					if frame and frame.tab:IsShown() then
						ChatFrame_MessageEventHandler(frame, "CHAT_MSG_BN_WHISPER", fwdMessage, useName and name or tag, "", "", "", "", 0, 0, "", 0, 0, "", id)
					end
				end
			end
			if not found then
				self:Print(L.WhisperFromBnet, sender, fwdSender, fwdMessage)
			end
		end

	elseif fwdEvent == "BC" then
		local fwdChannelNumber, fwdChannel, fwdMessage = strsplit("§", fwdMessage)
		local found
		for i = 1, BNGetNumFriends() do
			local id, name, tag, useTag, _, _, _, _, _, _, _, _, _, useName = BNGetFriendInfo(i)
			if tag == fwdSender then
				found = true
				for i = 1, 10 do
					local frame = _G["ChatFrame"..i]
					if frame and frame.tab:IsShown() then
						ChatFrame_MessageEventHandler(frame, "CHAT_MSG_BN_CONVERSATION", fwdMessage, useName and name or tag, "", fwdChannel or "", "", "", 0, tostring(fwdChannelNumber) or 0, "", 0, 0, "", id)
					end
				end
			end
			if not found then
				self:Print(L.WhisperFromConvo, sender, fwdSender, fwdMessage)
			end
		end
	end
end

------------------------------------------------------------------------

Chat.displayName = L.Chat
function Chat:SetupOptions(panel)
	local title, notes = panel:CreateHeader(L.Chat, L.Chat_Info)

	local enable = panel:CreateCheckbox(L.Enable, L.Enable_Info)
	enable:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -12)
	function enable:OnValueChanged(value)
		Chat.db.enable = value
		Chat:Refresh()
	end

	local modes = {
		APPFOCUS = L.ApplicationFocus,
		LEADER = L.PartyLeader,
	}

	local mode
	do
		local checked = function(self)
			return Chat.db.mode == self.value
		end
		local func = function(self)
			Chat.db.mode = self.value
			Chat:Refresh()
		end
		local menu = {
			{ text = L.AppFocus, value = "APPFOCUS", checked = checked, func = func },
			{ text = L.PartyLeader, value = "LEADER", checked = checked, func = func },
		}
		mode = panel:CreateDropdown(L.DetectionMethod, L.DetectionMethod_Info, menu)
		mode:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -16)
		mode:SetPoint("TOPRIGHT", notes, "BOTTOM", -8, -12 - enable:GetHeight() - 16)
	end

	local timeout = panel:CreateSlider(L.Timeout, L.GroupTimeout_Info, 30, 600, 30)
	timeout:SetPoint("TOPLEFT", mode, "BOTTOMLEFT", 0, -16)
	timeout:SetPoint("TOPRIGHT", mode, "BOTTOMRIGHT", 0, -16)
	function timeout:OnValueChanged(value)
		value = floor((value + 1) / 30) * 30
		Chat.db.timeout = value
		return value
	end

	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	help:SetPoint("BOTTOMLEFT", 16, 16)
	help:SetPoint("BOTTOMRIGHT", -16, 16)
	help:SetHeight(112)
	help:SetJustifyH("LEFT")
	help:SetJustifyV("BOTTOM")
	help:SetText(L.ChatHelpText)

	panel.refresh = function()
		enable:SetValue(Chat.db.enable)
		mode:SetValue(modes[Chat.db.mode])
		timeout:SetValue(Chat.db.timeout)
	end
end
