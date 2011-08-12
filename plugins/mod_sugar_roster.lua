-- Copyright (C) 2011, Aleksey Lim
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

local function set_nick(username, host, nick)
    local appeared_jid = username.."@"..host;
    local appeared_user = bare_sessions[appeared_jid];
    local appeared_buddy = sugar_roster[appeared_jid];

    if appeared_buddy.published then
        return;
    end

    module:log("debug", "Set nick %s for %s", nick, appeared_jid);

    appeared_buddy.published = true;
    appeared_buddy.name = nick;

    -- Notify roster about changed nick of newly appeared buddy
    for i, buddy in pairs(sugar_roster) do
        if i ~= appeared_jid and bare_sessions[i] then
            local stanza = st.message({from=appeared_jid, to=i, type='headline'})
                :tag('event', {xmlns='http://jabber.org/protocol/pubsub#event'})
                    :tag('items', {node="http://laptop.org/xmpp/buddy-properties"})
                        :tag('item')
                            :tag('properties', {xmlns="http://laptop.org/xmpp/buddy-properties"})
                                :tag('property', {type="str", name="nick"})
                                    :text(nick)
                                :up()
                            :up()
                        :up()
                    :up()
                :up();
            for _, session in pairs(appeared_user.sessions) do
                core_post_stanza(session, stanza);
            end
        end
    end
end

local function set_nick_on_appearing(event)
    local session, stanza = event.origin, event.stanza;

    if not stanza.attr.to and not stanza.attr.type and not session.presence then
        local vcard = st.deserialize(datamanager.load(session.username, session.host, "vcard"));
        if vcard then
            set_nick(session.username, session.host, vcard[1][1]);
        else
            -- vcard is not yet registered, that might happen right after
            -- user registration, will hook that user in datastore_callback
        end
    end
end

local function inject_sugar_roster(username, host, roster)
	local jid = username.."@"..host;

    if not bare_sessions[jid] then
        -- Sugar roster only for online users
        return;
    end

    local appeared_buddy = {};
    appeared_buddy.subscription = "both";
    appeared_buddy.name = jid;
    appeared_buddy.groups = {};
    appeared_buddy.published = false;
    --appeared_buddy.groups = { [group_name] = true };

    for i, buddy in pairs(sugar_roster) do
        if not bare_sessions[i] then
            -- Workaround to avoid #2963
            sugar_roster[i] = nil;
        elseif i ~= jid then
            roster[i] = buddy;
            if bare_sessions[i] then
                bare_sessions[i].roster[jid] = appeared_buddy;
            end
        end
    end

	if roster[false] then
		roster[false].version = true;
	end

    module:log("debug", "Add %s to sugar roster", jid);
    sugar_roster[jid] = appeared_buddy;
end

local function datastore_callback(username, host, datastore, data)
    if datastore == "roster" then
        -- No need in saving roster in sugar mode, it is temporal
        return username, host, datastore, {};
    elseif datastore == "vcard" then
        -- Try to take into account not yet registered user
        set_nick(username, host, data[1] and data[1][1] or username.."@"..host);
    end

    return username, host, datastore, data;
end

function module.load()
    module:hook("presence/bare", set_nick_on_appearing, 1000);
	module:hook("roster-load", inject_sugar_roster);
	datamanager.add_callback(datastore_callback);
end

function module.unload()
	datamanager.remove_callback(datastore_callback);
end
