-- Copyright (C) 2011-2012, Aleksey Lim
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local datamanager = require "util.datamanager";
local jid_bare = require "util.jid".bare;
local st = require "util.stanza"
local jid_split = require "util.jid".split;

local bare_sessions = bare_sessions;

local group_name = "online";
local sugar_roster = {};

-- Populate newly appeared budy's metadata among the sugar roster.
-- This function seems to be a workaround, clients can (and already do,
-- but not in all cases) request this information within the regular
-- client side behavior.
local function publish_card(username, host, card)
    local appeared_jid = username.."@"..host;
    local appeared_buddy = sugar_roster[appeared_jid];

    if not appeared_buddy or appeared_buddy.published then
        return;
    end

    module:log('info', 'Publish %s card', appeared_jid);

    appeared_buddy.published = true;

    -- Notify roster about metadata of newly appeared buddy
    for roster_jid, buddy in pairs(sugar_roster) do
        if roster_jid ~= appeared_jid and bare_sessions[roster_jid] then
            local notification = st.message({from=appeared_jid, to=roster_jid, type='headline'})
                :tag('event', {xmlns='http://jabber.org/protocol/pubsub#event'})
                    :tag('items', {node="http://laptop.org/xmpp/buddy-properties"})
                        :tag('item')
                            :tag('properties', {xmlns="http://laptop.org/xmpp/buddy-properties"})
                                :tag('property', {type='bytes', name='key'})
                                    :text(card['key'])
                                :up()
                                :tag('property', {type='str', name='nick'})
                                    :text(card['nick'])
                                :up()
                                :tag('property', {type='str', name='color'})
                                    :text(card['color'])
                                :up()
                            :up()
                        :up()
                    :up()
                :up();
            for _, session in pairs(bare_sessions[appeared_jid].sessions) do
                core_post_stanza(session, notification);
            end
        end
    end
end

-- Trigger publish_card() on buddy appearing.
local function publish_card_on_appearing(event)
    local session, stanza = event.origin, event.stanza;

    if not stanza.attr.to and not stanza.attr.type and not session.presence then
        local card = st.deserialize(datamanager.load(session.username, session.host, 'sugar_card'));
        if card then
            publish_card(session.username, session.host, card);
        else
            -- card is not yet registered, that might happen right after
            -- user registration, will hook that user in set_cards
        end
    end
end

local function inject_sugar_roster(username, host, roster)
	local jid = username.."@"..host;

    if not bare_sessions[jid] then
        module:log("debug", "Do not add offline %s to sugar roster", jid);
        return;
    end

    local appeared_buddy = {};
    appeared_buddy.subscription = "both";
    appeared_buddy.groups = {};
    appeared_buddy.published = false;
    --appeared_buddy.groups = { [group_name] = true };

    for roster_jid, buddy in pairs(sugar_roster) do
        if not bare_sessions[roster_jid] then
            -- XXX Workaround to avoid #2963
            module:log("info", "Kick offline %s from sugar roster", roster_jid);
            sugar_roster[roster_jid] = nil;
        elseif roster_jid ~= jid then
            roster[roster_jid] = buddy;
            if bare_sessions[roster_jid] then
                bare_sessions[roster_jid].roster[jid] = appeared_buddy;
            end
        end
    end

	if roster[false] then
		roster[false].version = true;
	end

    module:log("info", "Add %s to sugar roster", jid);
    sugar_roster[jid] = appeared_buddy;
end

local function set_cards(event)
	local session, stanza = event.origin, event.stanza;
	local payload = stanza.tags[1];

	if stanza.attr.type ~= 'set' or stanza.attr.to or
            not payload:get_child('publish') or
            not payload:get_child('publish'):get_child('item') then
        return;
    end

    node = payload:get_child('publish').attr.node
    payload = payload:get_child('publish'):get_child('item')
    local new_card = {};

    if node == 'http://jabber.org/protocol/nick' then
        payload = payload.tags[1]
        new_card['nick'] = payload:get_text();
    elseif node == 'http://laptop.org/xmpp/buddy-properties' then
        payload = payload.tags[1]
        for _, prop in pairs(payload.tags) do
            if prop.attr.name == 'nick' or prop.attr.name == 'color' or
                    prop.attr.name == 'key' then
                new_card[prop.attr.name] = prop:get_text();
            end
        end
    else
        return;
    end

    local card = st.deserialize(datamanager.load(
            session.username, session.host, 'sugar_card'));
    if not card then
        card = { name = 'sugar_card', attr = {} };
    end
    for prop, value in pairs(new_card) do
        module:log('info', 'Populate card for %s@%s with %s=%s',
                session.username, session.host, prop, value);
        card[prop] = value;
    end
    datamanager.store(session.username, session.host, 'sugar_card', card);

    -- Try to take into account not yet registered user
    publish_card(session.username, session.host, card);
end

local function get_cards(event)
	local session, stanza = event.origin, event.stanza;
	local payload = stanza.tags[1];

	if stanza.attr.type ~= 'get' or not stanza.attr.to or
            not payload:get_child('items') then
        return;
    end

	local username, host = jid_split(stanza.attr.to);
    local card = st.deserialize(datamanager.load(username, host, 'sugar_card'));
    if not card then
        module:log('info', 'Not %s in sugar roster', username)
        return
    end

    node = payload:get_child('items').attr.node
    if node == 'http://jabber.org/protocol/nick' then
        local stanza = st.reply(stanza)
            :tag('pubsub', {xmlns='http://jabber.org/protocol/pubsub'})
                :tag('items', {node=node})
                    :tag('item')
                        :tag('nick', {xmlns="http://jabber.org/protocol/nick"})
                            :text(card['nick'])
                        :up()
                    :up()
                :up()
            :up();
        session.send(stanza);
        return true;
    elseif node == 'http://laptop.org/xmpp/buddy-properties' then
        local stanza = st.reply(stanza)
            :tag('pubsub', {xmlns='http://jabber.org/protocol/pubsub'})
                :tag('items', {node=node})
                    :tag('item')
                        :tag('properties', {xmlns="http://laptop.org/xmpp/buddy-properties"})
                            :tag('property', {type='bytes', name='key'})
                                :text(card['key'])
                            :up()
                            :tag('property', {type='str', name='nick'})
                                :text(card['nick'])
                            :up()
                            :tag('property', {type='str', name='color'})
                                :text(card['color'])
                            :up()
                        :up()
                    :up()
                :up()
            :up();
        session.send(stanza);
        return true;
    end
end

local function datastore_callback(username, host, datastore, data)
    if datastore == "roster" then
        -- No need in saving roster in sugar mode, it is temporal
        return username, host, datastore, {};
    else
        return username, host, datastore, data;
    end
end

function module.load()
    module:hook("presence/bare", publish_card_on_appearing, 1000);
    module:hook("iq/bare/http://jabber.org/protocol/pubsub:pubsub", set_cards, 1000);
    module:hook("iq/bare/http://jabber.org/protocol/pubsub:pubsub", get_cards, 1000);
    module:hook("roster-load", inject_sugar_roster);
    datamanager.add_callback(datastore_callback);
end

function module.unload()
    datamanager.remove_callback(datastore_callback);
end
