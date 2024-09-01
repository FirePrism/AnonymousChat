local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON");
frame:RegisterEvent("PLAYER_LOGIN");
frame:RegisterEvent("PLAYER_LOGOUT");
frame:RegisterEvent("GUILD_ROSTER_UPDATE");

C_ChatInfo.RegisterAddonMessagePrefix("ANON");
C_ChatInfo.RegisterAddonMessagePrefix("ANONANNOUNCE");
C_ChatInfo.RegisterAddonMessagePrefix("ANONACK");

local ANON_USERS = {}; -- list of online guild members that also use the addon
local ANON_ACKNOWLEDGEMENTS = {}; -- temporary nonces to detect offline or unresponsive users
local ANON_MESSAGES_COUNT = {}; -- how often have I seen this message? increase announce probability everytime I see it again to reduce communication overhead
local ANON_MY_MESSAGES = {}; -- which messages were sent by me? stored so that my messages are displayed in a different color
local ANON_THRESHOLD = 2; -- required other users (excluding the player).

local ANON_MESSAGE_HELLO = "HELLO";
local ANON_MESSAGE_GOODBYE = "GOODBYE";

local ANON_ANNOUNCE_PROBABILITY = 0.5; -- probability to announce a message (instead of forwarding the message).

if AnonymousChat == nil then
    AnonymousChat = {};
    AnonymousChat.threshold = ANON_THRESHOLD;
end

local ANON_LOCALIZATION = {};
ANON_LOCALIZATION["PREFIX"] = "|cffffff00AnonymousChat:|r";
ANON_LOCALIZATION["OPTIONS_HELP_ENABLED"] = "anonymous chatting possible (threshold: " .. AnonymousChat.threshold .. " other users). Usage: /anon MESSAGE.";
ANON_LOCALIZATION["OPTIONS_HELP_DISABLED"] = "anonymous chatting threshold currently not met (threshold: " .. AnonymousChat.threshold .. " other users). Usage: /anon MESSAGE.";
ANON_LOCALIZATION["MESSAGE_NOT_SENT"] = "message not sent because there are not enough other users to guarantee anonymity (threshold: " .. AnonymousChat.threshold .. ").";
ANON_LOCALIZATION["OPTIONS_HELP_SET_THRESHOLD"] = "set threshold using |cffffff00/anonymouschat THRESHOLD|r.";
ANON_LOCALIZATION["OPTIONS_HELP_SET_THRESHOLD_EXAMPLE"] = "example |cffffff00/anonymouschat 5:|r only send messages if there are at least 5 other users.";
ANON_LOCALIZATION["OPTIONS_CURRENT_THRESHOLD"] = "current threshold is " .. AnonymousChat.threshold .. " other users.";
ANON_LOCALIZATION["OPTIONS_THRESHOLD_SET"] = "set threshold to " .. AnonymousChat.threshold .. " other users.";
ANON_LOCALIZATION["OPTIONS_SET_THRESHOLD_ERROR"] = "please enter a whole number (greater 1) for the threshold.";

if (GetLocale() == "deDE") then
	ANON_LOCALIZATION["OPTIONS_HELP_ENABLED"] = "anonymes Chatten möglich (Schwellwert: " .. AnonymousChat.threshold .. " andere Nutzer). Nutzung: /anon NACHRICHT.";
	ANON_LOCALIZATION["OPTIONS_HELP_DISABLED"] = "Schwellwert zum anonymen Chatten zurzeit nicht erreicht (Schwellwert: " .. AnonymousChat.threshold .. " andere Nutzer). Nutzung: /anon NACHRICHT.";
	ANON_LOCALIZATION["MESSAGE_NOT_SENT"] = "Nachricht nicht gesendet, da nicht genug andere Nutzer online sind um die Anonymität zu gewährleisten (Schwellwert: " .. AnonymousChat.threshold .. ").";
	ANON_LOCALIZATION["OPTIONS_HELP_SET_THRESHOLD"] = "Schwellwert mithilfe von |cffffff00/anonymouschat SCHWELLWERT|r setzen.";
	ANON_LOCALIZATION["OPTIONS_HELP_SET_THRESHOLD_EXAMPLE"] = "Beispiel |cffffff00/anonymouschat 5:|r Nachrichten nur senden, wenn mindestens 5 andere Nutzer online sind.";
	ANON_LOCALIZATION["OPTIONS_CURRENT_THRESHOLD"] = "Aktueller Schwellwert ist " .. AnonymousChat.threshold .. " andere Nutzer.";
	ANON_LOCALIZATION["OPTIONS_THRESHOLD_SET"] = "Schwellwert auf " .. AnonymousChat.threshold .. " andere Nutzer gesetzt.";
	ANON_LOCALIZATION["OPTIONS_SET_THRESHOLD_ERROR"] = "Bitte eine ganze Zahl (größer als 1) als Schwellwert angeben.";
end

local function ANON_getShortName(name) -- Remove the realm name from the character name
	if (name == nil or name == "" or name == '') then
		return "";
	else
		local charname, _ = strsplit("-", name, 2)
		return charname;
	end
end

local function ANON_sendHello()
	if (GetGuildInfo("player")) then
		C_ChatInfo.SendAddonMessage("ANON", ANON_MESSAGE_HELLO, "GUILD")
	end
end

local function ANON_sendGoodbye()
	if (GetGuildInfo("player")) then
		C_ChatInfo.SendAddonMessage("ANON", ANON_MESSAGE_GOODBYE, "GUILD")
	end
end

local function ANON_addUser(user)
	for i=1, #ANON_USERS do
		if (ANON_USERS[i] == user) then
			return;
		end
	end
	ANON_USERS[#ANON_USERS+1] = user;
end

local function ANON_removeUser(user)
	for i=1, #ANON_USERS do
		if (ANON_USERS[i] == user) then
			table.remove(ANON_USERS, i)
			return;
		end
	end
end

local function ANON_announce(msg)
	if (GetGuildInfo("player")) then
		C_ChatInfo.SendAddonMessage("ANONANNOUNCE", msg, "GUILD")
	end
end

local function ANON_sendAcknowledgement(toUser)
	C_ChatInfo.SendAddonMessage("ANONACK", "ACK", "WHISPER", toUser)
end

local function ANON_announceOrRedirectMessage(msg, parent)
	local msgNonce, msgText = strsplit(" ", msg, 2)
	if (msgNonce == nil or msgText == nil) then
		return
	end
	if (ANON_MESSAGES_COUNT[msgNonce] == nil) then
		ANON_MESSAGES_COUNT[msgNonce] = 1;
	end
	ANON_MESSAGES_COUNT[msgNonce] = ANON_MESSAGES_COUNT[msgNonce] + 1; -- increase announce probability for messages circulating a long time.

	local announce_roll = math.random();
	local currentAnnounceProbability = 1 - ((1 - ANON_ANNOUNCE_PROBABILITY) ^ ANON_MESSAGES_COUNT[msgNonce]);
	if (announce_roll < currentAnnounceProbability) then
		ANON_announce(msg)
		return;
	end

	if (#ANON_USERS > 0) then
		local newRandomUserIndex = math.random(#ANON_USERS);
		local newRandomUser = ANON_USERS[newRandomUserIndex];
		local nonce = tostring(math.random(1,99999));
		ANON_ACKNOWLEDGEMENTS[newRandomUser] = nonce;
		C_ChatInfo.SendAddonMessage("ANON", msg, "WHISPER", newRandomUser)
		ANON_checkAcknowledgement(newRandomUser, nonce, msg)

		C_Timer.After(3, function() 
			if (ANON_ACKNOWLEDGEMENTS[newRandomUser] == nonce) then
				ANON_removeUser(newRandomUser);
				ANON_announceOrRedirectMessage(msg);
			end
		end)
	end
end

function frame:OnEvent(event, ...)
	if (event == "CHAT_MSG_ADDON") then
		local prefix, message, channel, sender = select(1, ...)
		if (prefix == "ANON") then
			if (channel == "WHISPER") then
				C_GuildInfo.GuildRoster();
				if (#ANON_USERS > 0) then
					ANON_sendAcknowledgement(sender);
					ANON_announceOrRedirectMessage(message, sender)
				end
			elseif (channel == "GUILD" and message == ANON_MESSAGE_HELLO) then
				if (ANON_getShortName(UnitName("player")) ~= ANON_getShortName(sender)) then
					ANON_addUser(sender)
					ANON_sendAcknowledgement(sender);
				end
			elseif (channel == "GUILD" and message == ANON_MESSAGE_GOODBYE) then
				if (ANON_getShortName(UnitName("player")) ~= ANON_getShortName(sender)) then
					ANON_removeUser(sender)
				end
			end
		elseif (prefix == "ANONANNOUNCE") then
			local msgNonce, msgText = strsplit(" ", message, 2)
			if (msgNonce == nil or msgText == nil) then
				return
			end
			ANON_MESSAGES_COUNT[msgNonce] = nil
			if (ANON_MY_MESSAGES[msgNonce] == true) then
				print(ANON_LOCALIZATION["PREFIX"] .. " |cffffff00" .. msgText .. "|r");
				ANON_MY_MESSAGES[msgNonce] = nil;
			else
				print(ANON_LOCALIZATION["PREFIX"] .. " |cffff00ff" .. msgText .. "|r");
			end
		elseif (prefix == "ANONACK") then
			ANON_addUser(sender)
			ANON_ACKNOWLEDGEMENTS[sender] = 0;
		end
	elseif (event == "PLAYER_LOGIN") then
		C_Timer.After(3, function() 
			ANON_sendHello();
		end)
	elseif (event == "PLAYER_LOGOUT") then
		ANON_sendGoodbye();
	elseif (event == "GUILD_ROSTER_UPDATE") then
		for i=1,GetNumGuildMembers() do
			local n,_,_,_,_,_,_,_,o,_,_,_,_,_,_,_ = GetGuildRosterInfo(i);
			if (not o) then
				ANON_removeUser(n)
			end
		end
	end
end

frame:SetScript("OnEvent", frame.OnEvent)

SLASH_ANON1 = '/anon';
function SlashCmdList.ANON(msg, editbox)
	if(msg == "") then
		if (#ANON_USERS >= AnonymousChat.threshold) then
			print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["OPTIONS_HELP_ENABLED"]);
		else
			print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["OPTIONS_HELP_DISABLED"]);
			
		end
		print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["OPTIONS_HELP_SET_THRESHOLD"]);
	else
		if (#ANON_USERS >= AnonymousChat.threshold) then
			local nonce = tostring(math.random(1,99999));
			local newRandomUser = ANON_USERS[math.random(#ANON_USERS)]
			ANON_MY_MESSAGES[nonce] = true;
			C_ChatInfo.SendAddonMessage("ANON", nonce .. " " .. msg, "WHISPER", newRandomUser)
		else
			print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["MESSAGE_NOT_SENT"]);
		end
	end
end

SLASH_ANONYMOUSCHAT1 = '/anonymouschat';
function SlashCmdList.ANONYMOUSCHAT(msg, editbox)
	local value = strsplit(" ", msg, 1)
	if(msg == "" or value == nil) then
		print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["OPTIONS_CURRENT_THRESHOLD"]);
		print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["OPTIONS_HELP_SET_THRESHOLD"]);
		print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["OPTIONS_HELP_SET_THRESHOLD_EXAMPLE"]);
	else
		if (string.match(value, "^%d+$") and tonumber(value) > 1) then
			AnonymousChat.threshold = tonumber(value);
			print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["OPTIONS_THRESHOLD_SET"]);
		else
			print(ANON_LOCALIZATION["PREFIX"] .. " " .. ANON_LOCALIZATION["OPTIONS_SET_THRESHOLD_ERROR"]);
		end
	end
end
