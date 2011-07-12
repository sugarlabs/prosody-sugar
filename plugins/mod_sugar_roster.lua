-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local lfs = require "lfs";
local datamanager = require "util.datamanager";
local st = require "util.stanza"
local hosts = hosts;

local group_name = "online";

local function inject_sugar_roster(username, host, roster)
	local bare_jid = username.."@"..host;
	local path = string.sub(datamanager.getpath(nil, host, "accounts", ""), 0, -2);

    local mode = lfs.attributes(path, "mode");
    if not mode then
        module:log("debug", "Assuming empty "..path);
        return;
    elseif mode ~= "directory" then
        module:log("error", "The "..path.." is not a directory");
        return;
    end

    for username in lfs.dir(path) do
        if username ~= "." and username ~= ".." then
            username = string.sub(username, 0, -5);
            local jid = username.."@"..host;

            if not roster[jid] and jid ~= bare_jid then
                roster[jid] = {};
                roster[jid].subscription = "both";
                roster[jid].groups = { [group_name] = true };
                roster[jid].groups[group_name] = true;
            end
        end
    end
end

local function remove_sugar_roster(username, host, datastore, data)
    if datastore == "roster" then
        -- No need in saving roster in sugar mode, it is temporal
        return username, host, datastore, {};
    else
        return username, host, datastore, data;
    end
end

function module.load()
	module:hook("roster-load", inject_sugar_roster);
	datamanager.add_callback(remove_sugar_roster);
end

function module.unload()
	datamanager.remove_callback(remove_sugar_roster);
end
