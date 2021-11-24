-- JMRI-IR integration v0.1
-- Requires Aumation Mod and JMRI Server
-- https://pastebin.com/zwXhwFDZ

local component = require("component")
local internet = require("internet")
local serial = require("serialization")
local fs = require("filesystem")
local term = require ("term")
local keyboard = require("keyboard") 
local json = require("json")
local event = require("event")
local thread = require("thread")
local CONFIG_FILE = "/home/Msettings.cfg"
local SWITCH_TABLE = "/home/Mswitchtable.tbl"
local CONFIG = {ip = "localhost",port = "12080", wait = 1}
local DEFAULT_CONFIG = {ip = "localhost",port = "12080", wait = 1}
local getip = "http://"..CONFIG.ip..":"..CONFIG.port.."/json"
local world = component.world_link
local wait = 1
local chunkLoad = true
local RUNNING = true
local flagReset = false
local CurrSwitches = {}

-- GL Added, list types, seems unused
local stocktypes = {
    "immersiverailroading:locomotivediesel",
    "immersiverailroading:locomotivesteam"
    }

-- GL New - point check function
function checkRect(a1,b1,a2,b2,x,y)
    if a1 < a2 then
        x1 = a1
        x2 = a2
        else
        x1 = a2
        x2 = a1
        end
    if b1 < b2 then
        y1 = b1
        y2 = b2
        else
        y1 = b2
        y2 = b1
        end
    if (x >= x1 and x <= x2 and y >= y1 and y <= y2) then
        return true
        else
        return false
        end
    end

-- blocks 
blocks = {}
    blocks[1] = {1,1,10,10}
    blocks[2] = {20,20,100,100}

for a,b in pairs(blocks) do
    x1 = b[1]
    y1 = b[2]
    x2 = b[3]
    y2 = b[4]
    answer = checkRect(x1,y1,x2,y2,5,5)
    print("Block", a,": ", answer)
    end


        -- GL Added, runs immediately, looks for all entity cards
        link_table = {}
        for i,v in pairs(component.list()) do
            if v == "entity_link" then
                table.insert(link_table, i)
                end
            end 
        print("Entity_link's found: ", #link_table)
    
function overArray()
    local b = {}
    count = 0
    for i, link in pairs(link_table) do
        local entity = component.proxy(link).getAPI("immersiverailroading:locomotivediesel")
        if entity ~= nil then
            rollingstock = entity
            local posit_array = {}
            local a = {}
            uuid = rollingstock.getUUID()
            position = rollingstock.getLocation()
            xpos = position.getX()
            ypos = position.getY()
            zpos = position.getZ()
            speed = rollingstock.getCurrentSpeed()
            if locotable[uuid] == nil then
                setspeed = 0
                method = "Manual"
            else
                setspeed = locotable[uuid].setspeed
                method = locotable[uuid].method
            end
            tag = "" -- add later
            c = {["x"] = xpos, ["y"] = ypos, ["z"] = zpos}
            a = {}
            a["uuid"] = uuid
            a["speed"] = speed
            a["setspeed"] = setspeed
            a["method"] = method
            a["posit_array"] = c
            a["name"] = rollingstock.getName()
            a["tag"] = "" --rollingstock.getTag()
            table.insert(b,1,a) 
            end
        end
        -- Don't need to send this data, use b 
        --data = json:encode(b)
        --if data ~= "" then
            --con:write("#01,"..data.."\r\n")
            --con:flush()
            --end
end



-- Decode
function decode(x)
    result = ""
    for chunk in x do result = result .. chunk end
    decoded = json:decode(result)
    return decoded
end

-- Uses finishConnect() to check connection, need to be run multiple times to work...
function httpTEST(x)
    local flagConnect = false
    for i = 1, 10 do
        if x.finishConnect() then
            flagConnect = true
            break
        end
    end
    return flagConnect
end

-- General HTTP GET
function httpGET(ip)
    local decoded = ""
    handle = internet.request(ip,"",{},"GET")
    if httpTEST(handle) then
        decoded = decode(handle)
        return decoded
    else
        return nil
    end
end

-- General HTTPS GET -- required for a list of objects (i.e all turnouts)
function httpsGET(ip)
    local decoded = ""
    handle = internet.request(ip)
    if httpTEST(handle) then
        decoded = decode(handle)
        return decoded
    else
        return nil
    end
end

-- General HTTP PUT
function httpPUT(ip, data)
    local encoded = json:encode(data)
    local header = {["Content-Type"] = "application/json;charset=utf-8"}
    local result = ""
    local handle = internet.request(ip, encoded, header, "PUT")
    if handle == nil then
        print("failed to connect")
    else
        holdtable = handle() -- required
    end
end

-- General HTTP POST
function httpPOST(ip, data)
    local encoded = json:encode(data)
    local header = {["Content-Type"] = "application/json;charset=utf-8"}
    local handle = internet.request(ip, encoded, header, "POST")
    if handle == nil then
        print("failed to connect")
    else
        holdtable = handle() -- required
    end
end
 
-- General save file
function saveFile(file, data)
    local f = io.open(file, "w")
    if f == nil then error("Couldn't open " .. file .. " to write config.") end
    f:write(serial.serialize(data, 100000))
    f:close()
end

-- General load file
function loadFile(file)
    local f = io.open(file, "r")
    if f == nil then 
      print("Could not open " .. CONFIG_FILE .. ".")
      return nil
      else
      local data = serial.unserialize(f:read("*a"))
      f:close()
      return data
      end
end

-- General loadconfig file, loads default if not found
function loadConfig(file)
    local f = io.open(file, "r")
    if f == nil then 
      print("Could not open " .. CONFIG_FILE .. ".")
      print("Loading default config")
      return DEFAULT_CONFIG
      else
      local data = serial.unserialize(f:read("*a"))
      f:close()
      return data
      end
end

-- Compares the Current switches against the JMRI turnouts, adds switch to JMRI if not found
function compareWeb(CurrSwitches, WebSwitches)
    if WebSwitches ~= nil then
        for name, data in pairs(CurrSwitches) do
            if WebSwitches[name] == nil then
                httpPUT(getip.."/turnout", buildTurnout(name,name:gsub("%,", " "), data.state))
            end
        end
    end
end

--Compares the states of the Current switches against the JMRI turnouts, if different, changes the state of that switch
function compareWebState(CurrSwitches, WebSwitches)
    if WebSwitches ~= nil then
        for name, data in pairs(CurrSwitches) do
            if WebSwitches[name] ~= nil then
                if WebSwitches[name] ~= data.state then
                    x = data.position.x
                    y = data.position.y
                    z = data.position.z
                    location = world.getLocationByCoordinates(x,y,z)
                    flagChunk = false
                    if chunkLoad then 
                        if location.isLoaded() == false then 
                            location.getChunk().forceLoad() 
                            print("Chunk loading..")
                            os.sleep(0.1)
                            flagChunk = true
                        end
                    end
                    a = location.getTileEntities().whereProperty("type", "automation:redstone_box").asList()
                    if a ~= nil then
                        b = a[1]
                        c = b.getAPI("automation:redstone_box")
                        out = 0
                        if WebSwitches[name] then out = 15 end
                        c.setPowerLevel(out)
                        if flagChunk then 
                            os.sleep(0.1)
                            location.getChunk().unforceLoad()
                        end
                        print("Set: ",x,y,z,"To: ",out)
                        CurrSwitches[name].state = WebSwitches[name]
                    else
                        print("Error locating rebox: ", name)
                    end
                end    
            end
        end
    end
end

-- Compares the current switches against the previously saved switches
function compareTables(compare)
    against = loadFile(SWITCH_TABLE)
    if against ~= nil then
        for name, data in pairs(compare) do
            if against[name] == nil then
                against[name] = data
            else
                against[name].state = data.state
            end            
        end
        saveFile(SWITCH_TABLE, against)
        return against
    else
        saveFile(SWITCH_TABLE, compare)
        return compare
    end   
end

-- Searches for all loaded Redstone_box, returns the list of found switches
function FindSwitches()
    data = {}
    count = 0
    Allredboxes = world.getLoadedTileEntities().whereProperty("type", "automation:redstone_box").asList()
    if Allredboxes then
        for i, redbox in pairs(Allredboxes) do
            position = redbox.getLocation()
            xpos = position.getX()
            ypos = position.getY()
            zpos = position.getZ() 
            c = {["x"] = xpos, ["y"] = ypos, ["z"] = zpos}
            output = redbox.getAPI("automation:redstone_box").getPowerLevel()
            a = {}
            a["position"] = c
            a["state"] = Rstate(output)
            name = tostring(xpos)..","..tostring(ypos)..","..tostring(zpos)
            data[name] = a
            count = count + 1
            os.sleep(0.1)
            end
        end
    if data == {} then
        data = nil
        end
    print("Redboxes found: ",count)
    return data
end

-- Turns JMRI Blocks into a readable table
function ParseBlocks(x)
    if x ~= nil then
        blockTable = {}
        for i,v in pairs(x) do
            print(i,v)
            print(v["data"]["name"])
            name = v["data"]["name"]
            name = string.sub( name, 3 )
            username = v["data"]["userName"]
            comment = v["data"]["comment"]
            length = v["data"]["length"]
            state = v["data"]["state"] -- 4 un	2 oc 0 unknown
            permissive = v["data"]["permissive"]
            curvature = v["data"]["curvature"]
            reporter = v["data"]["reporter"]
            speedLimit = v["data"]["speedLimit"]
            sensor = v["data"]["sensor"]
            speed = v["data"]["speed"]
            direction = v["data"]["direction"]
            
            v["data"]["comment"] = "TESTING123"
        end
    else
        return false
    end
end

-- Turns JMRI light to a readable table
function ParseLight(x)
    if x ~= nil then
        name = x["data"]["name"]
        state = x["data"]["state"]
        --print (name,state)
        return JLstate(state)
    else
        return false
    end
end

-- Turns JMRI turnout to a readable table
function ParseTurnout(x)
    if x ~= nil then
        xtable = {}
        for i,v in pairs(x) do
            name = v["data"]["name"]
            name = string.sub( name, 3 )
            username = v["data"]["userName"]
            comment = v["data"]["comment"]
            inverted = v["data"]["inverted"]
            state = JTstate(v["data"]["state"])
            if name ~= nil then
                xtable[name] = state
            end
        end
        return xtable
    else
        return nil
    end
end

-- Builds JMRI Turnout to send
function buildTurnout(name, comment, state)
    setstate = 2
    if state == true then setstate = 4 end
    out = {
        type="turnout",
        data= {name="IT"..name,comment=comment,state=0}
    }
    return out
end

-- Builds JMRI Light to send
function buildLight(name, state)
    setstate = 4
    if state == true then setstate = 2 end
    out = {
        type="light",
        data={name=name,state=setstate},
      }
    return out
end

-- JMRI Turnout state converts to true or false
function JTstate(x) 
    local out = false
    if x == 4 then
        out = true
    end
    return out
end

-- JMRI Light state converts to true or false, they are backwards...
function JLstate(x) 
    local out = false
    if x == 2 then
        out = true
    end
    return out
end

-- Redstone state convert to true or false
function Rstate(x) 
    local out = false
    if x == 15 then
        out = true
    end
    return out
end

-- Gets user config information
function getSettings()
    print("What is the IP address of the JMRI server?")
    local ip = nil
    repeat
      ip = io.read()
    until ip ~= nil

    print("What is the port number of the JMRI server?")
    local port = nil
    repeat
      port = tonumber(io.read())
      if port == nil or port <= 0 then
        print("Invalid port number. Please enter a positive number.")
      end
    until port ~= nil and port > 0
    
    print("How fast do you want the update rate in seconds (standard is 1) ?")
    local wait = nil
    repeat
        wait = tonumber(io.read())
        if wait == nil or wait <= 0 then
        print("Invalid number. Please enter a positive number.")
        end
    until wait ~= nil and wait > 0
    
    print("Entered information:")
    print("  JMRI IP: \""..ip.."\"")
    print("  JMRI port: \""..port.."\"")
    print("  Update rate (s): \""..wait.."\"")
    print("Is this information correct? [y/n]")
    local choice = io.read()
      
    if choice == "y" or choice == "yes" then
        CONFIG = {
            ip = ip,
            port = port,
            wait = wait
        }
        return CONFIG
    else
        return nil
    end
end

-- Checks for config file and loads, if not found, asks user for input
function startup()
    local CONFIG = nil
    local f = io.open(CONFIG_FILE, "r")
    if f == nil then 
        CONFIG = getSettings()
        if CONFIG == nil then
            CONFIG = loadConfig(CONFIG_FILE)
            saveFile(CONFIG_FILE,CONFIG)
        else
            print("Saving to "..CONFIG_FILE..".")
            saveFile(CONFIG_FILE,CONFIG)
        end
    else
        CONFIG = loadConfig(CONFIG_FILE)
    end
    return CONFIG
end

-- What to do when the user has typed some keys.
local function onKeyDown(code)
    local key = keyboard.keys[code]
    if (keyboard.isControlDown()) then
        if (key == "r") then
            flagReset = true
        elseif (key == "q") then
            print("Quitting.")
            RUNNING = false
        end
    end
end

-- General purpose event handler that delegates different events to their own functions.
function handleEvents()
    while RUNNING do
        local event_name, p1, p2, p3, p4, p5 = event.pull("key_down")
        if event_name == "key_down" then
            local key_code = p3
            onKeyDown(key_code)
        end
    end
end

-- INIT --

-- Setup of config and switch table
CONFIG = startup()
getip = "http://"..CONFIG.ip..":"..CONFIG.port.."/json"
CurrSwitches = loadFile(SWITCH_TABLE)
if CurrSwitches == nil then
    CurrSwitches = FindSwitches()
    saveFile(SWITCH_TABLE, CurrSwitches)
end
term.clear()

-- MAIN --

os.sleep(1)

-- Create event handle for user keyboard
thread.create(handleEvents):detach()

--read([n:number]):string
--Tries to read data from the response. Returns the read byte array.
--response():number, string, table
--Get response code, message and headers.
--finishConnect():boolean
--Ensures a response is available. Errors if the connection failed.


-- While running, checks in order; User reset, Build mode, Find switches, Update switches
while RUNNING do
    if flagReset then
        flagReset = false
        CONFIG = getSettings()
        if CONFIG == nil then
            CONFIG = loadConfig(CONFIG_FILE)
            saveFile(CONFIG_FILE,CONFIG)
        else
            print("Saving to "..CONFIG_FILE..".")
            saveFile(CONFIG_FILE,CONFIG)
        end
        term.clear()
        getip = "http://"..CONFIG.ip..":"..CONFIG.port.."/json"
    end
    print("JMRI IR")
    print(os.date(" %I:%M %p"))
    print("Reset: Cntl + r")
    print("Exit: Cntl + q")
    if httpGET(getip.."/railroad") ~= nil then
        testdata = ParseBlocks(httpsGET(getip.."/blocks"))
        httpPUT(getip.."/blocks", testdata) 
    else
        print("No connection")
    end
    os.sleep(CONFIG.wait)
    term.clear()
end
