-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local datamanager = require "util.datamanager";
local jid_bare = require "util.jid".bare;
local st = require "util.stanza"

local bare_sessions = bare_sessions;

local group_name = "online";
local sugar_roster = {};

local function populate_sugar_roster(event)
	local session, stanza = event.origin, event.stanza;
    local appeared_jid = session.username.."@"..session.host;

    if stanza.attr.to or stanza.attr.type or session.presence then
        return;
    end

    if sugar_roster[appeared_jid] then
        return;
    end

    local appeared_buddy = {};
    appeared_buddy.subscription = "both";
    appeared_buddy.name = appeared_jid;
    appeared_buddy.groups = {};
    --appeared_buddy.groups = { [group_name] = true };

    -- Add new buddy to all sugar users' rosters
    for i, buddy in pairs(sugar_roster) do
        if bare_sessions[i] then
            for _, session in pairs(bare_sessions[i].sessions) do
                session.roster[appeared_jid] = appeared_buddy;
                session.send(st.presence({type="subscribe", from=appeared_jid, subscription="both"}));
            end
        end
    end

    module:log("debug", "Add %s to sugar roster", appeared_jid);
    sugar_roster[appeared_jid] = appeared_buddy;
end

local function inject_sugar_roster(username, host, roster)
	local jid = username.."@"..host;

    if not bare_sessions[jid] then
        -- Sugar roster only for online users
        return;
    end

    for i, buddy in pairs(sugar_roster) do
        if i ~= jid then
            roster[i] = buddy;
        end
    end

	if roster[false] then
		roster[false].version = true;
	end
end

local function remove_sugar_roster(username, host, datastore, data)
    if datastore ~= "roster" then
        return username, host, datastore, data;
    end

    -- No need in saving roster in sugar mode, it is temporal
    return username, host, datastore, {};
end

function module.load()
    module:hook("presence/bare", populate_sugar_roster, 1000);
	module:hook("roster-load", inject_sugar_roster);
	datamanager.add_callback(remove_sugar_roster);
end

function module.unload()
	datamanager.remove_callback(remove_sugar_roster);
end
