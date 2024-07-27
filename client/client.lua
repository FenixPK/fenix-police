


--TODOs:
--
-- Allow adding attachments to Config.loadouts so they have flashlights for eg.
--
-- Remove player stolen police cars if they are abandoned for a long time and far away from players.
--
-- Send player to prison if killed by cops, while player is in lastStand/bleedout the cops can approach you and if they reach player they go to jail. If you die before they reach you
-- then you go to hospital. Idea: Lookup lastStand code, lookup sendToPrison code and get help leveraging the two features?
--
-- Add criminal database that will track crimes: 
-- a) Allow criminal record check, just for fun stats. Should track anything you were wanted for whether you escaped or not. And also any convictions where you end up in prison.
-- b) If player has evaded police add a warrant for them and any vehicle they were last in at the time of evasion. Re-sets when they go to prison.
-- c) If cop is near player with warrant: 
--     -If player is on foot the cops spot you from farther away and set shorter timer to trigger wanted level.
--     -If player is in vehicle and vehicle is not wanted then the cops can only spot you from close by and the timer is longer to trigger wanted level.
--     -If player is in vehicle and vehicle is wanted then same distance/timer as when on foot.
--
-- Track kill count and if player has caused enough destruction at wanted level 5 then switch spawnpool to military units.
-- Track if player got into a military vehicle at any wanted level and switch spawnpool to military units. 
-- Track if player has escaped x amount of times without going to prison and chance to spawn hitmen or PMC contractors randomly (without wanted stars) to try and kill player. 
-- Also perhaps FIB agents can follow you around if warrant + very high crime stat, keeping distance but watching you so they can pounce when you commit a crime. 
--
--
-- Add gang relation database that will track gang relationships:
-- a) Set relationships of the peds so gang members out in the world will attack the player if relations are poor.
-- b) Track if player has killed x amount of gang members, if so chance to spawn gang hit one time then re-set flag. 
-- c) Way to increase relations? Messing with members of one gang could make another happy. Bribes? Drugs? Weapons?
-- d) Have this affect prison experience when that is working. Rival gangs in prison will cause problems for the player.
--
-- Add Gangs, Territories, and takeovers. Gang wars! Players could hire their own peds etc. This might need to be a separate mod.

-- USER REQUESTS:
-- Add command to manually activate/de-activate AI police that police-job users can use.
-- Prevent Police Job users from being wanted by this script. 







-- ****BEGIN CODE**** --

-- Get the QBCore object so we can do notifications, check for nearest vehicle using their improved call, and handle isDying and isLastStand situations for the player. 
QBCore = exports['qb-core']:GetCoreObject()




-- TABLES --
-- Tables to keep track of spawned police units
local spawnedVehicles = {} -- Table to store {vehicle = vehicle, officers = {driver = officer1, passenger = officer2...}, officerTasks = {}}
local deadPeds = {} -- Table to store {officer = ped, timer = 0}
local farOfficers = {} -- Table to store {officer = ped, timer = 0}

local spawnedHeliUnits = {} -- Table to store {unit = unit, officers = {driver = officer1, passenger = officer2...}, officerTasks = {}}
local deadHeliPeds = {} -- Table to store {officer = ped, timer = 0}
local farHeliPeds = {} -- Table to store {officer = ped, timer = 0}

local spawnedAirUnits = {} -- Table to store {unit = unit, officers = {driver = officer1, passenger = officer2...}, officerTasks = {}}
local deadAirPeds = {} -- Table to store {officer = ped, timer = 0}
local farAirPeds = {} -- Table to store {officer = ped, timer = 0}

local stuckAttempts = {}  -- Table to keep track of the number of attempts to unstick vehicle for each vehicle
local stolenVehicles = {} -- Table to store vehicles by netID that the player stole and were not cleaned up, to delete later when the player has abandoned them

local isSpawning = false -- Variable to prevent spawning more units when spawning is already in progress.

local disableAIPolice = nil -- Toggle to turn AI police response on and off if players are online or not if that config option is used. 




-- EXPORTS --
function ApplyWantedLevel(level)
    Citizen.CreateThread(function()
        if Config.PoliceWantedProtection and isPlayerPoliceOfficer then
            -- If wanted protection is enabled and the player is a cop we skip doing anything
        else
            -- Apply wanted
            local wantedLevel = GetPlayerWantedLevel(PlayerId())
            local newWanted = wantedLevel + level
            if newWanted > 5 then
                newWanted = 5
            end
            ClearPlayerWantedLevel(PlayerId())
            SetPlayerWantedLevelNow(PlayerId(),false)
            Citizen.Wait(10)
            SetPlayerWantedLevel(PlayerId(),newWanted,false)
            SetPlayerWantedLevelNow(PlayerId(),false)
            local playerVehicle = GetVehiclePedIsIn(PlayerPedId(), true)
            if playerVehicle ~= 0 then
                SetVehicleIsWanted(playerVehicle, true)
            end
        end
        
    end)
end
exports('ApplyWantedLevel', ApplyWantedLevel)
-- Use this in other scripts by calling the function like below. 
-- This allows you to set a wanted level from a script action that the normal GTA V code would not consider.
-- For eg. a robery script, chop-shop script, car theft mission etc. might call this to set a wanted level.
--  exports['fenix-police']:ApplyWantedLevel(wantedLevelHere)

function SetWantedLevel(level)
    Citizen.CreateThread(function()
        if Config.PoliceWantedProtection and isPlayerPoliceOfficer then
            -- If wanted protection is enabled and the player is a cop we skip doing anything
        else
            -- Apply wanted
            local wantedLevel = GetPlayerWantedLevel(PlayerId())
            local newWanted = level
            if level < wantedLevel then
                newWanted = wantedLevel
            else
                newWanted = level
            end
            ClearPlayerWantedLevel(PlayerId())
            SetPlayerWantedLevelNow(PlayerId(),false)
            Citizen.Wait(10)
            SetPlayerWantedLevel(PlayerId(),newWanted,false)
            SetPlayerWantedLevelNow(PlayerId(),false)
            local playerVehicle = GetVehiclePedIsIn(PlayerPedId(), true)
            if playerVehicle ~= 0 then
                SetVehicleIsWanted(playerVehicle, true)
            end
        end
    end)
end
exports('SetWantedLevel', SetWantedLevel)
-- Use this in other scripts by calling the function like below. 
-- This allows you to set a wanted level from a script action that the normal GTA V code would not consider.
-- For eg. a robery script, chop-shop script, car theft mission etc. might call this to set a wanted level.
--  exports['fenix-police']:SetWantedLevel(wantedLevelHere)




-- **HELPER FUNCTIONS** --



-- SPAWNING --

-- Get player zone for determining spawn tables
local function getPlayerZoneCode()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    -- Get the zone name from the player's coordinates
    local zoneName = GetNameOfZone(playerCoords.x, playerCoords.y, playerCoords.z)
    
    return zoneName
end




-- Function to get the formatted zone key
local function getZoneKey(zoneName)
    return Config.ZoneEnum[zoneName] or zoneName  -- Return the mapped key or the original zoneName if not found
end




-- Function to get a safe spawn point on a road near the player
local function getSafeSpawnPoint(playerCoords, minDistance, maxDistance)
    local found = false
    local roadCoords, roadHeading

    while not found do
        local offsetX = math.random(minDistance, maxDistance)
        local offsetY = math.random(minDistance, maxDistance)
        if math.random(0, 1) == 0 then offsetX = -offsetX end
        if math.random(0, 1) == 0 then offsetY = -offsetY end

        local spawnCoords = vector3(playerCoords.x + offsetX, playerCoords.y + offsetY, playerCoords.z)
        -- Try major roads first nodeType = 0
        local roadFound, tempRoadCoords, tempRoadHeading = GetClosestVehicleNodeWithHeading(spawnCoords.x, spawnCoords.y, spawnCoords.z, 0, 3.0, 0)
        
        if not roadFound then
            -- Try any path next nodeType = 1, this approach should prevent cops spawning in fields/racetracks etc. when main roads are available. 
            -- But still allow for dirt roads, fields, racetracks, parks etc. as a fallback option. 
            local roadFound, tempRoadCoords, tempRoadHeading = GetClosestVehicleNodeWithHeading(spawnCoords.x, spawnCoords.y, spawnCoords.z, 1, 3.0, 0)
        end

        if roadFound then
            roadCoords = tempRoadCoords
            roadHeading = tempRoadHeading
            found = true
        end
    end

    if found then
        return roadCoords, roadHeading
    end

    return nil
end




-- Get air unit spawn point within range
local function getRandomPointInRange(playerCoords, minDistance, maxDistance, minHeight, maxHeight)
    local minDist = minDistance -- or 300 -- can uncomment this to default, but I want a debug message for now. "somevar = anothervar or defaultvalue" syntax will default if first is nil
    local maxDist = maxDistance -- or 500
    
    if not minDistance then
        if Config.isDebug then print('GetRandomPointInRange: minDistance was nil, using default') end
        minDist = 300 -- Some fallback defaults
    end
    if not maxDistance then
        if Config.isDebug then print('GetRandomPointInRange: maxDistance was nil, using default') end
        maxDist = 500 -- Some fallback defaults
    end

    local offsetX = math.random(minDist, maxDist)
    local offsetY = math.random(minDist, maxDist)
    if math.random(0, 1) == 0 then offsetX = -offsetX end
    if math.random(0, 1) == 0 then offsetY = -offsetY end

    local x = playerCoords.x + offsetX
    local y = playerCoords.y + offsetY
    local z = playerCoords.z + math.random(minHeight, maxHeight) 
    return vector3(x, y, z)
end




-- VEHICLE FUNCTIONS --

-- Function to check if a vehicle contains any ped
local function isVehicleOccupied(vehicle)
    if DoesEntityExist(vehicle) then
        for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) do
            local ped = GetPedInVehicleSeat(vehicle, seat)
            if ped and ped ~= 0 then
                return true -- There is a ped in the vehicle
            end
        end
    end
    return false -- No ped found in the vehicle
end




-- Check if the vehicle seems stuck
function IsVehicleStuck(vehicle)
    if not DoesEntityExist(vehicle) or not IsPedInAnyVehicle(GetPedInVehicleSeat(vehicle, -1), false) then
        return false
    end

    local vehicleSpeed = GetEntitySpeed(vehicle)
    local isStuck = false

    if vehicleSpeed < 0.2 then
        local stuckTime = 0
        while vehicleSpeed < 0.2 and stuckTime < 8000 do -- Check if the vehicle is stuck for 8 seconds
            Citizen.Wait(1000)
            vehicleSpeed = GetEntitySpeed(vehicle)
            stuckTime = stuckTime + 1000
        end

        -- If stuck for 8 seconds continuously set isStuck = true. 
        if stuckTime >= 8000 then
            isStuck = true
        end
    end

    return isStuck
end




-- Function to continuously check if a vehicle is stuck
function MonitorVehicle(vehNetID)
    Citizen.CreateThread(function()
        local playerPed = PlayerPedId()

        while GetPlayerWantedLevel(PlayerId()) > 0 and stuckAttempts[vehNetID] ~= 999 do
            local vehicle = NetToVeh(vehNetID) 
            
            -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
            local waitCount = 0
            while (not vehicle or vehicle == 0) and waitCount < Config.controlWaitCount do
                vehicle = NetToVeh(vehNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end

            if (not vehicle or vehicle == 0) then
                if Config.isDebug then print('MonitorVehicle vehicle ID ' .. vehNetID .. ' NetToVeh still nil or 0, gave up ') end
            else
                if IsVehicleStuck(vehicle) then
                    GetVehicleUnstuck(vehicle, math.random(0, 1) == 0, vehNetID)
                else
                    stuckAttempts[vehNetID] = 0 -- Re-set counter if unstuck, so we can start fresh if it gets stuck
                end
            end
            Citizen.Wait(5000) -- Check every 5 seconds
        end

    end)
end




-- If stuck try reversing and then driving forward left or forward right before going back to task.
-- Usually police ram into things head first and get stuck on walls so reversing and then going left or right might help them get around it.
function GetVehicleUnstuck(vehicle, isLeft, vehNetID)
    local driver = GetPedInVehicleSeat(vehicle, -1) 
    local maxUnstuckAttempts

    if DoesEntityExist(driver) then
        local vehicleId = vehicle

        local playerCoords = GetEntityCoords(playerPed)
        local officerCoords = GetEntityCoords(driver)
        local distance = Vdist(playerCoords.x, playerCoords.y, playerCoords.z, officerCoords.x, officerCoords.y, officerCoords.z)

        if distance > 200 then 
            
            maxUnstuckAttempts = Config.maxFarUnstuckAttempts 

            -- Let's not do anything special if far away, I tried teleportation but it doesn't work well
            if stuckAttempts[vehNetID] == maxUnstuckAttempts then

                -- +1 so it stops trying but not permanently if it somehow gets unstuck again. 
                stuckAttempts[vehNetID] = stuckAttempts[vehNetID] + 1

                -- -- Teleport the vehicle to the nearest road node
                -- local vehCoords = GetEntityCoords(vehicle)
                -- local found, outPosition = GetClosestVehicleNode(vehCoords.x, vehCoords.y, vehCoords.z, 0, 3.0, 0)
                -- if found then
                --     SetEntityCoords(vehicle, outPosition.x, outPosition.y, outPosition.z, false, false, false, true)
                --     SetVehicleOnGroundProperly(vehicle)
                --     stuckAttempts[vehicleId] =  stuckAttempts[vehicleId] + 1 
                --     if Config.isDebug then print('Teleported far stuck vehicle') end
                -- end

    
                -- return  -- Exit the function after teleporting the vehicle

            elseif stuckAttempts[vehNetID] < maxUnstuckAttempts then

                -- Create a task sequence to unstick the vehicle
                local taskSequence = OpenSequenceTask(0)
                
                TaskVehicleTempAction(0, vehicle, 28, 4000) -- Strong brake + reverse
                if isLeft then
                    if Config.isDebug then print('Vehicle ' .. vehNetID .. ' seems stuck, trying to free it left') end
                    TaskVehicleTempAction(0, vehicle, 7, 2000)  -- Turn left + accelerate
                else
                    if Config.isDebug then print('Vehicle ' .. vehNetID .. ' seems stuck, trying to free it right') end
                    TaskVehicleTempAction(0, vehicle, 8, 2000)  -- Turn right + accelerate
                end
                
                TaskVehicleTempAction(0, vehicle, 27, 2000) -- Brake until car stop or until time ends
                CloseSequenceTask(taskSequence)

                -- Clear current tasks and perform the unstick sequence
                ClearPedTasks(driver)
                TaskPerformSequence(driver, taskSequence)
                ClearSequenceTask(taskSequence)
                Wait(10000) -- Wait for 10 seconds so the sequence can execute fully!
                --TaskVehicleDriveToCoord(driver, vehicle, playerCoords.x, playerCoords.y, playerCoords.z, 30.0, 1, GetEntityModel(vehicle), 787004, 5.0, true)
                TaskVehicleChase(driver, playerPed)
                stuckAttempts[vehNetID] =  stuckAttempts[vehNetID] + 1 
            else
                -- Do nothing if we exceeded attempts. 
            end
            

        else 
            maxUnstuckAttempts = Config.maxCloseUnstuckAttempts 

            -- If exactly == max we abandon vehicle once, then set 999 so it never tries again and saves CPU cycles. 
            if stuckAttempts[vehNetID] == maxUnstuckAttempts then
                -- If we the vehicle is close to the player just get out.
                GetPedsOutOfVehicle(vehicle)
                if Config.isDebug then print('Abandoned nearby stuck vehicle') end
                stuckAttempts[vehNetID] = 999 -- Set special value to prevent checking further, vehicle has been abandoned! 

                return
            elseif stuckAttempts[vehNetID] < maxUnstuckAttempts then

                -- Create a task sequence to unstick the vehicle
                local taskSequence = OpenSequenceTask(0)
                
                TaskVehicleTempAction(0, vehicle, 28, 4000) -- Strong brake + reverse
                if isLeft then
                    if Config.isDebug then print('Vehicle ' .. vehNetID .. ' seems stuck, trying to free it left') end
                    TaskVehicleTempAction(0, vehicle, 7, 2000)  -- Turn left + accelerate
                else
                    if Config.isDebug then print('Vehicle ' .. vehNetID .. ' seems stuck, trying to free it right') end
                    TaskVehicleTempAction(0, vehicle, 8, 2000)  -- Turn right + accelerate
                end
                
                TaskVehicleTempAction(0, vehicle, 27, 2000) -- Brake until car stop or until time ends
                CloseSequenceTask(taskSequence)

                -- Clear current tasks and perform the unstick sequence
                ClearPedTasks(driver)
                TaskPerformSequence(driver, taskSequence)
                ClearSequenceTask(taskSequence)
                Wait(10000) -- Wait for 10 seconds so the sequence can execute fully!
                --TaskVehicleDriveToCoord(driver, vehicle, playerCoords.x, playerCoords.y, playerCoords.z, 30.0, 1, GetEntityModel(vehicle), 787004, 5.0, true)
                TaskVehicleChase(driver, playerPed)
                stuckAttempts[vehNetID] =  stuckAttempts[vehNetID] + 1 
            else
                -- Do nothing if we exceeded attempts. 
            end

        end
    end
end




-- Abandon a vehicle, usually due to being stuck on roof. 
function GetPedsOutOfVehicle(vehicle)
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    for i = -1, seats - 2 do
        local ped = GetPedInVehicleSeat(vehicle, i)
        if DoesEntityExist(ped) then
            TaskLeaveVehicle(ped, vehicle, 0)
        end
    end
end




-- Function to handle if the server tried to delete a vehicle and someone was in driver seat still. 
RegisterNetEvent('deleteSpawnedVehicleResponseStolen')
AddEventHandler('deleteSpawnedVehicleResponseStolen', function(vehNetID)
    -- Add to stolen vehicle list to delete later. 
    stolenVehicles[vehNetID] = vehNetID
    if Config.isDebug then print('Added vehicle/heli/air ID ' .. vehNetID .. ' to stolenVehicles table ') end
end)




-- MAIN LOGIC --


-- AIR UNITS --

-- This function will tell the server to spawn a police unit, and the server will pass back the Network ID of the vehicle + officers spawned so the client can handle them. 
local function spawnHeliUnitNet(wantedLevel, spawnTable)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)   

    -- Get a safe spawn point
    local spawnCoords = getRandomPointInRange(playerCoords, Config.minHeliSpawnDistance, Config.maxHeliSpawnDistance, Config.minHeliSpawnHeight, Config.maxHeliSpawnHeight)

    if not spawnCoords then
        if Config.isDebug then print('No safe spawn point found') end
        return
    end

    TriggerServerEvent('spawnPoliceHeliNet', wantedLevel, playerCoords, spawnCoords, spawnTable)

end




-- This handles the response from the server after a vehicle and officers are spawned, so they can be tasked and otherwise handled by the client. 
RegisterNetEvent('spawnPoliceHeliNetResponse')
AddEventHandler('spawnPoliceHeliNetResponse', function(vehNetID, officers)

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)   


    if vehNetID and officers then
        local vehicle = NetToVeh(vehNetID) -- Try to set the local vehicle entity from the network ID returned by the server

        -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or = 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not vehicle or vehicle == 0) and waitCount < Config.spawnWaitCount do
            if Config.isDebug then print('HeliSpawn waiting for vehicle = NetToVeh to not be nil or 0') end
            vehicle = NetToVeh(vehNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end
        --if Config.isDebug then print('CLIENT NetToVeh for netID ' ..vehNetID .. ' returned entityID ' .. vehicle)  end
        --if Config.isDebug then print('CLIENT VehToNet for entityID ' ..vehicle.. ' returned NetID = ' .. VehToNet(vehicle))  end

        NetworkSetNetworkIdDynamic(vehNetID, false)  -- Allow the networked vehicle to be controlled dynamically.
        SetNetworkIdCanMigrate(vehNetID, false) -- Allow the network ID to be migrated to other clients.
        SetNetworkIdExistsOnAllMachines(vehNetID, true)
        SetEntityAsMissionEntity(vehicle, true, true) -- Prevent despawning by game garbage collection

        spawnedHeliUnits[vehNetID] = {vehicle = vehicle, officers = {}, officerTasks = {} }

        for i, pedNetID in ipairs(officers) do 
            local officer = NetToPed(pedNetID)

            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.spawnWaitCount do
                if Config.isDebug then print('HeliSpawn waiting for officer = NetToPed to not be nil') end
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end

            SetHeliBladesFullSpeed(vehicle)
            SetVehicleEngineOn(vehicle, true, true, false)

            NetworkSetNetworkIdDynamic(pedNetID, false) -- Allow the networked ped to be controlled dynamically.
            SetNetworkIdCanMigrate(pedNetID, false) -- Allow the network ID to be migrated to other clients.
            SetNetworkIdExistsOnAllMachines(pedNetID, true)
            SetEntityAsMissionEntity(officer, true, true) -- Prevent despawning by game garbage collection

            SetPedAsCop(officer, true)

            if i <= 2 then
                -- Process pilot and co-pilot. 
                SetPedCombatAttributes(officer, 52, enabled) -- Can vehicle attack? only works on driver
                SetPedCombatAttributes(officer, 53, enabled) -- Can use mounted vehicle weapons? only works on driver
                SetPedCombatAttributes(officer, 85, enabled) -- Prefer air targets to targets on ground       
                SetPedAccuracy(officer, math.random(20, 30))     
            else
                -- Process officers
                SetPedCombatAttributes(officer, 2, true) -- Allow drive-by shooting.
                SetPedAccuracy(officer, math.random(10, 20))
                SetPedFiringPattern(officer, 0x5D60E4E0) -- Set firing pattern to single shot. 
            end

            -- Set the pilot to pursue the player
            if i == 1 then
                TaskVehicleDriveToCoord(officer, unit, playerCoords.x, playerCoords.y, playerCoords.z, 60.0, 1, GetEntityModel(unit), 16777248, 70.0, true)
                SetDriverAbility(officer, 1.0) -- Set driver ability to max.
                spawnedHeliUnits[vehNetID].officerTasks[pedNetID] = 'DriveToCoord'
            else
                spawnedHeliUnits[vehNetID].officerTasks[pedNetID] = 'None'
            end

            -- Adds the spawned ped "officer" to the .officers table by key pedNetID so it can be retrieved by key pedNetID later. 
            spawnedHeliUnits[vehNetID].officers[pedNetID] = officer
        end

    end

    isSpawning = false

end)




-- This function will tell the server to spawn a police unit, and the server will pass back the Network ID of the vehicle + officers spawned so the client can handle them. 
local function spawnAirUnitNet(wantedLevel, spawnTable)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)   


    -- Get a safe spawn point
    local spawnCoords = getRandomPointInRange(playerCoords, Config.minAirSpawnDistance, Config.maxAirSpawnDistance, Config.minAirSpawnHeight, Config.maxAirSpawnHeight)

    if not spawnCoords then
        if Config.isDebug then print('No safe spawn point found') end
        return
    end

    TriggerServerEvent('spawnPoliceAirNet', wantedLevel, playerCoords, spawnCoords, spawnTable)

end




-- This handles the response from the server after a vehicle and officers are spawned, so they can be tasked and otherwise handled by the client. 
RegisterNetEvent('spawnPoliceAirNetResponse')
AddEventHandler('spawnPoliceAirNetResponse', function(vehNetID, officers)

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)   


    if vehNetID and officers then
        local vehicle = NetToVeh(vehNetID) -- Try to set the local vehicle entity from the network ID returned by the server

        -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or = 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not vehicle or vehicle == 0) and waitCount < Config.spawnWaitCount do
            if Config.isDebug then print('AirSpawn waiting for vehicle = NetToVeh to not be nil or 0') end
            vehicle = NetToVeh(vehNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end
        --if Config.isDebug then print('CLIENT NetToVeh for netID ' ..vehNetID .. ' returned entityID ' .. vehicle)  end
        --if Config.isDebug then print('CLIENT VehToNet for entityID ' ..vehicle.. ' returned NetID = ' .. VehToNet(vehicle))  end

        SetHeliBladesFullSpeed(vehicle)
        SetVehicleEngineOn(vehicle, true, true, false)

        NetworkSetNetworkIdDynamic(vehNetID, false)  -- Allow the networked vehicle to be controlled dynamically.
        SetNetworkIdCanMigrate(vehNetID, false) -- Allow the network ID to be migrated to other clients.
        SetNetworkIdExistsOnAllMachines(vehNetID, true)
        SetEntityAsMissionEntity(vehicle, true, true) -- Prevent despawning by game garbage collection

        spawnedAirUnits[vehNetID] = {vehicle = vehicle, officers = {}, officerTasks = {} }

        for i, pedNetID in ipairs(officers) do 
            local officer = NetToPed(pedNetID)

            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.spawnWaitCount do
                if Config.isDebug then print('AirSpawn waiting for officer = NetToPed to not be nil') end
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end

            NetworkSetNetworkIdDynamic(pedNetID, false) -- Allow the networked ped to be controlled dynamically.
            SetNetworkIdCanMigrate(pedNetID, false) -- Allow the network ID to be migrated to other clients.
            SetNetworkIdExistsOnAllMachines(pedNetID, true)
            SetEntityAsMissionEntity(officer, true, true) -- Prevent despawning by game garbage collection

            SetPedAsCop(officer, true)

            SetPedCombatAttributes(officer, 52, enabled) -- Can vehicle attack? only works on driver
            SetPedCombatAttributes(officer, 53, enabled) -- Can use mounted vehicle weapons? only works on driver
            SetPedCombatAttributes(officer, 85, enabled) -- Prefer air targets to targets on ground
            SetPedCombatAttributes(officer, 86, enabled) -- Allow dogfighting         
            SetPedAccuracy(officer, math.random(20, 30))

             -- Give the plane weapons
            GiveWeaponToPed(officer, `VEHICLE_WEAPON_SPACE_ROCKET`, 50, false, true)

            -- Set the plane to fire weapons at the player vehicle
            SetCurrentPedVehicleWeapon(officer, `VEHICLE_WEAPON_SPACE_ROCKET`)

            ControlLandingGear(vehicle, 3) -- Retract the gear
            

            -- Set the pilot to pursue the player
            if i == 1 then
                --TaskVehicleDriveToCoord(officer, unit, playerCoords.x, playerCoords.y, playerCoords.z, 100.0, 1, GetEntityModel(unit), 16777248, 70.0, true)
                TaskPlaneChase(officer, playerPed, 20, 20, 150)
                SetDriverAbility(officer, 1.0) -- Set driver ability to max.
                spawnedAirUnits[vehNetID].officerTasks[pedNetID] = 'DriveToCoord'
            else
                spawnedAirUnits[vehNetID].officerTasks[pedNetID] = 'None'
            end

            -- Adds the spawned ped "officer" to the .officers table by key pedNetID so it can be retrieved by key pedNetID later. 
            spawnedAirUnits[vehNetID].officers[pedNetID] = officer
        end

    end

    isSpawning = false

end)




-- GROUND UNITS --

-- This function will tell the server to spawn a police unit, and the server will pass back the Network ID of the vehicle + officers spawned so the client can handle them. 
local function spawnPoliceUnitNet(wantedLevel)
    --if Config.isDebug then print('Spawning Net Unit') end
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local zoneCode = getPlayerZoneCode() -- Zone for determining spawnlists
    local zone = Config.zones[zoneCode]
    local regionCode = nil
    if zone then 
        regionCode = getZoneKey(zone.location)
    else
        if Config.isDebug then print('ERROR: region enum not found for zoneCode = '.. zoneCode) end
        regionCode = 'losSantos'
    end
    

    -- Get a safe spawn point
    local spawnPoint, spawnHeading = getSafeSpawnPoint(playerCoords, Config.minPoliceSpawnDistance, Config.maxPoliceSpawnDistance) 
    if not spawnPoint then
        if Config.isDebug then print('No safe spawn point found') end
        return
    end

    TriggerServerEvent('spawnPoliceUnitNet', wantedLevel, playerCoords, regionCode, spawnPoint, spawnHeading)

end




-- This handles the response from the server after a vehicle and officers are spawned, so they can be tasked and otherwise handled by the client. 
RegisterNetEvent('spawnPoliceUnitNetResponse')
AddEventHandler('spawnPoliceUnitNetResponse', function(vehNetID, officers)

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)   


    if vehNetID and officers then
        local vehicle = NetToVeh(vehNetID) -- Try to set the local vehicle entity from the network ID returned by the server

        -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or = 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not vehicle or vehicle == 0) and waitCount < Config.spawnWaitCount do
            if Config.isDebug then print('UnitSpawn waiting for vehicle = NetToVeh to not be nil or 0') end
            vehicle = NetToVeh(vehNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end
        --if Config.isDebug then print('CLIENT NetToVeh for netID ' ..vehNetID .. ' returned entityID ' .. vehicle)  end
        --if Config.isDebug then print('CLIENT VehToNet for entityID ' ..vehicle.. ' returned NetID = ' .. VehToNet(vehicle))  end

        NetworkSetNetworkIdDynamic(vehNetID, false)  -- Allow the networked vehicle to be controlled dynamically.
        SetNetworkIdCanMigrate(vehNetID, false) -- Allow the network ID to be migrated to other clients.
        SetNetworkIdExistsOnAllMachines(vehNetID, true)
        SetEntityAsMissionEntity(vehicle, true, true) -- Prevent despawning by game garbage collection

        spawnedVehicles[vehNetID] = {vehicle = vehicle, officers = {}, officerTasks = {} }

        for i, pedNetID in ipairs(officers) do
            local officer = NetToPed(pedNetID)

            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.spawnWaitCount do
                if Config.isDebug then print('UnitSpawn waiting for officer = NetToPed to not be nil') end
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end

            NetworkSetNetworkIdDynamic(pedNetID, false) -- Allow the networked ped to be controlled dynamically.
            SetNetworkIdCanMigrate(pedNetID, false) -- Allow the network ID to be migrated to other clients.
            SetNetworkIdExistsOnAllMachines(pedNetID, true)
            SetEntityAsMissionEntity(officer, true, true) -- Prevent despawning by game garbage collection

            SetPedAsCop(officer, true)
            SetPedCombatAttributes(officer, 2, true) -- Able to driveby
            SetPedCombatAttributes(officer, 22, true) -- Drag injured peds to safety
            SetPedAccuracy(officer, math.random(10, 30))
            SetPedFiringPattern(officer, 0xD6FF6D61) -- Set firing pattern to a more controlled burst. 
            SetPedGetOutUpsideDownVehicle(officer, true) 

            -- Set the driver to pursue the player
            if i == 1 then
                TaskVehicleDriveToCoord(officer, vehicle, playerCoords.x, playerCoords.y, playerCoords.z, 30.0, 1, GetEntityModel(vehicle), 787004, 5.0, true)
                spawnedVehicles[vehNetID].officerTasks[pedNetID] = 'DriveToCoord'
                SetDriverAbility(officer, 100.0) -- Set driver ability to max.
                SetDriverAggressiveness(officer, 0.5)
                SetSirenKeepOn(vehicle, true)
            else
                spawnedVehicles[vehNetID].officerTasks[pedNetID] = 'None'
            end
            
            -- Adds the spawned ped "officer" to the .officers table by key pedNetID so it can be retrieved by key pedNetID later. 
            spawnedVehicles[vehNetID].officers[pedNetID] = officer
        end

        -- Will check if vehicle is stuck and try to free it. 
        MonitorVehicle(vehNetID) 

    end

    

    isSpawning = false

end)





-- Function to maintain the desired number of police units
local function maintainPoliceUnits(wantedLevel)
    local playerPed = PlayerPedId()
    local playerVeh = GetVehiclePedIsIn(playerPed, false)

    local maxUnits = Config.maxUnitsPerLevel[wantedLevel] or 0
    local currentUnits = 0

    local maxHeliUnits = Config.maxHeliUnitsPerLevel[wantedLevel] or 0
    local currentHeliUnits = 0

    local maxAirUnits = Config.maxAirUnitsPerLevel[wantedLevel] or 0
    local currentAirUnits = 0


    -- Do Ground Units --
    local spawnGroundUnits = false
    if playerVeh ~= 0 then
        if IsThisModelAPlane(GetEntityModel(playerVeh)) then
            -- Player is in a plane
            spawnGroundUnits = Config.spawnGroundUnitsInPlane
        elseif IsThisModelAHeli(GetEntityModel(playerVeh)) then
            -- Player is in a helicopter
            spawnGroundUnits = Config.spawnGroundUnitsInHeli
        else
            -- Player is in a car
            spawnGroundUnits = true
        end
    else
        -- Player is on foot
        spawnGroundUnits = true
    end

    if spawnGroundUnits then
        
        for _, vehicleData in pairs(spawnedVehicles) do
            currentUnits = currentUnits + 1
        end

        --if Config.isDebug then print('currentUnits = ' ..currentUnits.. ' and maxUnits = ' ..maxUnits .. ' and isSpawning = ' .. tostring(isSpawning)) end

        -- Spawn additional units if needed
        while currentUnits < maxUnits and isSpawning == false do
            -- Set isSpawning = true so we don't keep requesting the server to spawn units while still waiting for a response from the last request!
            isSpawning = true
            spawnPoliceUnitNet(wantedLevel)
            currentUnits = currentUnits + 1
        end
    end
    

    -- Do Heli Units --
    local heliSpawnTable = nil

    if playerVeh ~= 0 then
        if IsThisModelAPlane(GetEntityModel(playerVeh)) then
            -- Player is in a plane
            -- We don't spawn helis anymore if player is in a plane.
        elseif IsThisModelAHeli(GetEntityModel(playerVeh)) then
            -- Player is in a helicopter
            heliSpawnTable = Config.milHelis
        else
            -- Player is in a car
            heliSpawnTable = Config.polHelis
        end
    else
        -- Player is on foot
        heliSpawnTable = Config.polHelis 
    end

    if heliSpawnTable then
        for _, vehicleData in pairs(spawnedHeliUnits) do
            currentHeliUnits = currentHeliUnits + 1
        end

        --if Config.isDebug then print('currentHeliUnits = ' ..currentHeliUnits.. ' and maxHeliUnits = ' ..maxHeliUnits .. ' and isSpawning = ' .. tostring(isSpawning)) end
        -- Spawn additional units if needed
        while currentHeliUnits < maxHeliUnits and isSpawning == false do
            -- Set isSpawning = true so we don't keep requesting the server to spawn units while still waiting for a response from the last request!
            isSpawning = true
            spawnHeliUnitNet(wantedLevel, heliSpawnTable)
            currentHeliUnits = currentHeliUnits + 1
        end
    end
    


    -- Do Air Units --
    local airSpawnTable = nil

    if playerVeh ~= 0 then
        if IsThisModelAPlane(GetEntityModel(playerVeh)) then
            -- Player is in a plane
            airSpawnTable = Config.milPlanes
        elseif IsThisModelAHeli(GetEntityModel(playerVeh)) then
            -- Player is in a helicopter
            airSpawnTable = Config.milPlanes
        else
            -- Player is in a car
            -- We don't spawn planes anymore if player is in a car
        end
    else
        -- Player is on foot
        -- We don't spawn planes anymore if player is on foot
    end


    if airSpawnTable then
        for _, vehicleData in pairs(spawnedAirUnits) do
            currentAirUnits = currentAirUnits + 1
        end

        --if Config.isDebug then print('currentAirUnits = ' ..currentAirUnits.. ' and maxAirUnits = ' ..maxAirUnits .. ' and isSpawning = ' .. tostring(isSpawning)) end
        -- Spawn additional units if needed
        while currentAirUnits < maxAirUnits and isSpawning == false do
            -- Set isSpawning = true so we don't keep requesting the server to spawn units while still waiting for a response from the last request!
            isSpawning = true
            spawnAirUnitNet(wantedLevel, airSpawnTable)
            currentAirUnits = currentAirUnits + 1
        end
    end
    



end




-- Function to handle police foot chase and vehicle retrieval
local function handleChaseBehavior(vehicleData, playerPed, vehNetID)
    local playerCoords = GetEntityCoords(playerPed)
    local vehicle = NetToVeh(vehNetID) 
        
    -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
    local waitCount = 0
    while (not vehicle or vehicle == 0) and waitCount < Config.controlWaitCount do
        vehicle = NetToVeh(vehNetID)
        Wait(Config.netWaitTime)
        waitCount = waitCount + 1
    end

    if (not vehicle or vehicle == 0) then
        if Config.isDebug then print('HandleChase vehicle ID ' .. vehNetID .. ' NetToVeh still nil or 0, gave up ') end
    end

    for pedNetID, officerData in pairs(vehicleData.officers) do
        local officer = NetToPed(pedNetID) 

        -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
            officer = NetToPed(pedNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end

        if not DoesEntityExist(officer) or officer == 0 then
            if Config.isDebug then print('HandleChase ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
        else
            local officerCoords = GetEntityCoords(officer)
            local distance = Vdist(playerCoords.x, playerCoords.y, playerCoords.z, officerCoords.x, officerCoords.y, officerCoords.z)

            --Equivalent to checkDeadPeds but for farPeds, done here to leverage distance check
            if distance > Config.officerTooFarDistance then
                if farOfficers[pedNetID] then
                    farOfficers[pedNetID].timer = farOfficers[pedNetID].timer + 1
                else
                    farOfficers[pedNetID] = { officer = officer, timer = 0 }
                end
            else
                farOfficers[pedNetID] = nil
            end

            if IsPedInAnyVehicle(playerPed, false) then
                -- Player is in a vehicle
                if IsPedInAnyVehicle(officer, false) then
                    if GetPedInVehicleSeat(GetVehiclePedIsIn(officer), -1) == officer then 
                        local taskStatus = spawnedVehicles[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'VehicleChase' then  
                            TaskVehicleChase(officer, playerPed)
                            SetTaskVehicleChaseBehaviorFlag(officer, 8, true) -- Turn on boxing and PIT behavior
                            spawnedVehicles[vehNetID].officerTasks[pedNetID] = 'VehicleChase'
                        end
                    else
                        local taskStatus = spawnedVehicles[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'CombatPed' then  
                            TaskCombatPed(officer, playerPed, 0, 16)
                            spawnedVehicles[vehNetID].officerTasks[pedNetID] = 'CombatPed'
                        end    
                    end
                else
                    local nearbyVehicle = QBCore.Functions.GetClosestVehicle(vector3(officerCoords.x, officerCoords.y, officerCoords.z), 100, false)
                    if nearbyVehicle then
                        local taskStatus = spawnedVehicles[vehNetID].officerTasks[pedNetID] -- Only call task once to avoid interrupting peds repeatedly
                        if taskStatus ~= 'EnterVehicle' then  
                            TaskEnterVehicle(officer, nearbyVehicle, 20000, -1, 1.5, 8, 0)
                            spawnedVehicles[vehNetID].officerTasks[pedNetID] = 'EnterVehicle'
                        end
                    end
                end
            else
                -- Player is on foot
                if distance > Config.footChaseDistance then
                    if IsPedInAnyVehicle(officer, false) then
                        if GetPedInVehicleSeat(GetVehiclePedIsIn(officer), -1) == officer then 
                            local taskStatus = spawnedVehicles[vehNetID].officerTasks[pedNetID]
                            if taskStatus ~= 'VehicleChase' then  
                                TaskVehicleChase(officer, playerPed)
                                SetTaskVehicleChaseBehaviorFlag(officer, 8, true) -- Turn on boxing and PIT behavior
                                spawnedVehicles[vehNetID].officerTasks[pedNetID] = 'VehicleChase'
                            end
                        else
                            local taskStatus = spawnedVehicles[vehNetID].officerTasks[pedNetID]
                            if taskStatus ~= 'CombatPed' then  
                                TaskCombatPed(officer, playerPed, 0, 16)
                                spawnedVehicles[vehNetID].officerTasks[pedNetID] = 'CombatPed'
                            end    
                        end
                    end
                else
                    local taskStatus = spawnedVehicles[vehNetID].officerTasks[pedNetID]
                    if taskStatus ~= 'CombatPed' then  
                        TaskGoToEntity(officer, playerPed, -1, 5.0, 2.0, 1073741824, 0)
                        TaskCombatPed(officer, playerPed, 0, 16)
                        spawnedVehicles[vehNetID].officerTasks[pedNetID] = 'CombatPed'
                    end      
                end
            end
        end
    end
end




-- Function to handle heli chase
local function handleHeliChaseBehavior(vehicleData, playerPed, vehNetID)
    local playerCoords = GetEntityCoords(playerPed)
    local vehicle = NetToVeh(vehNetID) 
        
    -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
    local waitCount = 0
    while (not vehicle or vehicle == 0) and waitCount < Config.controlWaitCount do
        vehicle = NetToVeh(vehNetID)
        Wait(Config.netWaitTime)
        waitCount = waitCount + 1
    end

    if (not vehicle or vehicle == 0) then
        if Config.isDebug then print('HandleHeli vehicle ID ' .. vehNetID .. ' NetToVeh still nil or 0, gave up ') end
    end

    for pedNetID, officerData in pairs(vehicleData.officers) do
        local officer = NetToPed(pedNetID) 

        -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
            officer = NetToPed(pedNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end

        if not DoesEntityExist(officer) or officer == 0 then
            if Config.isDebug then print('HandleHeli ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
        else
            local officerCoords = GetEntityCoords(officer)
            local distance = Vdist(playerCoords.x, playerCoords.y, playerCoords.z, officerCoords.x, officerCoords.y, officerCoords.z)

            --Equivalent to checkDeadPeds but for farPeds, done here to leverage distance check
            if distance > Config.heliTooFarDistance then
                if farHeliPeds[pedNetID] then
                    farHeliPeds[pedNetID].timer = farHeliPeds[pedNetID].timer + 1
                else
                    farHeliPeds[pedNetID] = { officer = officer, timer = 0 }
                end
            else
                farHeliPeds[pedNetID] = nil
            end

            if IsPedInAnyVehicle(playerPed, false) then
                -- Player is in a vehicle
                if IsPedInAnyVehicle(officer, false) then
                    if GetPedInVehicleSeat(GetVehiclePedIsIn(officer), -1) == officer then 

                        local taskStatus = spawnedHeliUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'VehicleChase' then  
                            --TaskVehicleChase(officer, playerPed)
                            TaskHeliChase(officer, playerPed, 0, 0, 120)
                            spawnedHeliUnits[vehNetID].officerTasks[pedNetID] = 'VehicleChase'
                        end
                    else
                        local taskStatus = spawnedHeliUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'CombatPed' then  
                            TaskCombatPed(officer, playerPed, 0, 16)
                            spawnedHeliUnits[vehNetID].officerTasks[pedNetID] = 'CombatPed'
                        end    
                    end

                else
                    local nearbyVehicle = QBCore.Functions.GetClosestVehicle(vector3(officerCoords.x, officerCoords.y, officerCoords.z), 100, false)
                    if nearbyVehicle then
                        -- If pilots are somehow out of their helicopter alive and player is fleeing steal a car
                        local taskStatus = spawnedHeliUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'EnterVehicle' then
                            TaskEnterVehicle(officer, nearbyVehicle, 20000, -1, 1.5, 8, 0)
                            spawnedHeliUnits[vehNetID].officerTasks[pedNetID] = 'EnterVehicle'
                        end
                    end
                end
            else

                if IsPedInAnyVehicle(officer, false) then
                    if GetPedInVehicleSeat(GetVehiclePedIsIn(officer), -1) == officer then 
                        local taskStatus = spawnedHeliUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'VehicleChase' then  
                            --TaskVehicleChase(officer, playerPed)
                            TaskHeliChase(officer, playerPed, 0, 0, 120)
                            spawnedHeliUnits[vehNetID].officerTasks[pedNetID] = 'VehicleChase'
                        end
                    else
                        local taskStatus = spawnedHeliUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'CombatPed' then  
                            TaskCombatPed(officer, playerPed, 0, 16)
                            spawnedHeliUnits[vehNetID].officerTasks[pedNetID] = 'CombatPed'
                        end    
                    end
                end

            end

        end
    end
end




-- Function to handle air chase
local function handleAirChaseBehavior(vehicleData, playerPed, vehNetID)
    local playerCoords = GetEntityCoords(playerPed)
    local vehicle = NetToVeh(vehNetID) 
        
    -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
    local waitCount = 0
    while (not vehicle or vehicle == 0) and waitCount < Config.controlWaitCount do
        vehicle = NetToVeh(vehNetID)
        Wait(Config.netWaitTime)
        waitCount = waitCount + 1
    end

    if (not vehicle or vehicle == 0) then
        if Config.isDebug then print('HandleAir vehicle ID ' .. vehNetID .. ' NetToVeh still nil or 0, gave up ') end
    end

    for pedNetID, officerData in pairs(vehicleData.officers) do
        local officer = NetToPed(pedNetID) 

        -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
            officer = NetToPed(pedNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end

        if not DoesEntityExist(officer) or officer == 0 then
            if Config.isDebug then print('HandleAir ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
        else
            local officerCoords = GetEntityCoords(officer)
            local distance = Vdist(playerCoords.x, playerCoords.y, playerCoords.z, officerCoords.x, officerCoords.y, officerCoords.z)

            --Equivalent to checkDeadPeds but for farPeds, done here to leverage distance check
            if distance > Config.planeTooFarDistance then
                if farAirPeds[pedNetID] then
                    farAirPeds[pedNetID].timer = farAirPeds[pedNetID].timer + 1
                else
                    farAirPeds[pedNetID] = { officer = officer, timer = 0 }
                end
            else
                farAirPeds[pedNetID] = nil
            end

            if IsPedInAnyVehicle(playerPed, false) then
                local playerVeh = GetVehiclePedIsIn(playerPed, false)
                -- Player is in a vehicle
                if IsPedInAnyVehicle(officer, false) then
                    if GetPedInVehicleSeat(GetVehiclePedIsIn(officer), -1) == officer then 
                        local taskStatus = spawnedAirUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'VehicleChase' then  
                            --TaskVehicleChase(officer, playerPed)
                            --TaskPlaneChase(officer, playerPed, 0, 0, 80)
                            -- Assign the attack mission to the pilot
                            TaskVehicleMission(officer, vehicle, playerVeh, 6, 1000.0, 1073741824, 1, 0.0, true)

                            spawnedAirUnits[vehNetID].officerTasks[pedNetID] = 'VehicleChase'
                        end
                    else
                        local taskStatus = spawnedAirUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'CombatPed' then  
                            TaskCombatPed(officer, playerPed, 0, 16)
                            spawnedAirUnits[vehNetID].officerTasks[pedNetID] = 'CombatPed'
                        end   
                    end
                else
                    local nearbyVehicle = QBCore.Functions.GetClosestVehicle(vector3(officerCoords.x, officerCoords.y, officerCoords.z), 100, false)
                    if nearbyVehicle then
                        local taskStatus = spawnedAirUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'EnterVehicle' then
                            -- If pilots are somehow out of their helicopter and player is fleeing steal a car
                            TaskEnterVehicle(officer, nearbyVehicle, 20000, -1, 1.5, 8, 0)
                            spawnedAirUnits[vehNetID].officerTasks[pedNetID] = 'EnterVehicle'
                        end
                    end
                end
                
            else

                if IsPedInAnyVehicle(officer, false) then
                    if GetPedInVehicleSeat(GetVehiclePedIsIn(officer), -1) == officer then 
                        local taskStatus = spawnedAirUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'VehicleChase' then  
                            --TaskVehicleChase(officer, playerPed)
                            TaskPlaneChase(officer, playerPed, 20, 20, 150)
                            spawnedAirUnits[vehNetID].officerTasks[pedNetID] = 'VehicleChase'
                        end
                    else
                        local taskStatus = spawnedAirUnits[vehNetID].officerTasks[pedNetID]
                        if taskStatus ~= 'CombatPed' then  
                            TaskCombatPed(officer, playerPed, 0, 16)
                            spawnedAirUnits[vehNetID].officerTasks[pedNetID] = 'CombatPed'
                        end    
                    end
                end

            end
        end
    end
end




-- Function to check for dead peds and start the timer
local function checkDeadPeds()

    -- Ground Units --
    for vehNetID, vehicleData in pairs(spawnedVehicles) do
        for pedNetID, officerData in pairs(vehicleData.officers) do
            local officer = NetToPed(pedNetID) 

            -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            if not DoesEntityExist(officer) or officer == 0 then
                if Config.isDebug then print('CheckDeadUnit ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end


            if IsPedDeadOrDying(officer, true) then
                local deadPed = deadPeds[pedNetID]
                --If they are already added don't add them again
                if not deadPed then
                    deadPeds[pedNetID] = { officer = officer, timer = 0 }
                end   
            end
        end
    end

    -- Heli Units --
    for vehNetID, vehicleData in pairs(spawnedHeliUnits) do
        for pedNetID, officerData in pairs(vehicleData.officers) do
            local officer = NetToPed(pedNetID) 

            -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            if not DoesEntityExist(officer) or officer == 0 then
                if Config.isDebug then print('CheckDeadHeli ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end

            if IsPedDeadOrDying(officer, true) then
                local deadPed = deadHeliPeds[pedNetID]
                --If they are already added don't add them again
                if not deadPed then
                    deadHeliPeds[pedNetID] = { officer = officer, timer = 0 }
                end   
            end
        end
    end

    -- Air Units --
    for vehNetID, vehicleData in pairs(spawnedAirUnits) do
        for pedNetID, officerData in pairs(vehicleData.officers) do
            local officer = NetToPed(pedNetID) 

            -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            if not DoesEntityExist(officer) or officer == 0 then
                if Config.isDebug then print('CheckDeadAir ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end

            if IsPedDeadOrDying(officer, true) then
                local deadPed = deadAirPeds[pedNetID]
                --If they are already added don't add them again
                if not deadPed then
                    deadAirPeds[pedNetID] = { officer = officer, timer = 0 }
                end   
            end
        end
    end


end




-- Function to handle the deletion of dead peds after timer
local function handleDeadPeds()

    -- Ground Units --
    for pedNetID, deadPed in pairs(deadPeds) do

        deadPed.timer = deadPed.timer + 1

        if deadPed.timer >= (Config.deadOfficerCleanupTimer / Config.scriptFrequencyModulus) then

            -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
            if Config.isDebug then print('Removing DeadOfficer ID = ' .. pedNetID) end
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            deadPeds[pedNetID] = nil

            -- Loop through all stored vehicles and set officers[pedNetID] = nil
            -- If our officer exists for that vehicle, they are removed. Otherwise does nothing. 
            for vehNetID, vehicleData in pairs(spawnedVehicles) do

                if Config.isDebug then print('Checking vehNetID = '.. vehNetID .. ' for dead ped = ' ..pedNetID) end
                if vehicleData.officers[pedNetID] then
                    if Config.isDebug then print('Found ped in vehicleData.officers for pedNetID = ' .. pedNetID) end
                    vehicleData.officers[pedNetID] = nil

                    if not next(vehicleData.officers) then
                        -- If no officers left assigned tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
                        -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
                        if Config.isDebug then print('Removing DeadOfficerVehicle ID = ' .. vehNetID) end
                        TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
                        spawnedVehicles[vehNetID] = nil  
                    end
                    break
                end
            end

        end
    end


    -- Heli Units --
    for pedNetID, deadPed in pairs(deadHeliPeds) do

        deadPed.timer = deadPed.timer + 1

        if deadPed.timer >= (Config.deadHeliPilotCleanupTimer / Config.scriptFrequencyModulus) then

            -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
            if Config.isDebug then print('Removing HeliPilot ID = ' .. pedNetID) end
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            deadHeliPeds[pedNetID] = nil

            -- Loop through all stored vehicles and set officers[pedNetID] = nil
            -- If our officer exists for that vehicle, they are removed. Otherwise does nothing. 
            for vehNetID, vehicleData in pairs(spawnedHeliUnits) do
                if vehicleData.officers[pedNetID] then
                    vehicleData.officers[pedNetID] = nil

                    if not next(vehicleData.officers) then
                        -- If no officers left tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
                        -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
                        if Config.isDebug then print('Removing DeadOfficerHeli ID = ' .. vehNetID) end
                        TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
                        spawnedHeliUnits[vehNetID] = nil  
                    end
                    break
                end
            end

        end
    end


    -- Air Units --
    for pedNetID, deadPed in pairs(deadAirPeds) do

        deadPed.timer = deadPed.timer + 1

        if deadPed.timer >= (Config.deadAirPilotCleanupTimer / Config.scriptFrequencyModulus) then

            -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
            if Config.isDebug then print('Removing AirPilot ID = ' .. pedNetID) end
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            deadAirPeds[pedNetID] = nil

            -- Loop through all stored vehicles and set officers[pedNetID] = nil
            -- If our officer exists for that vehicle, they are removed. Otherwise does nothing. 
            for vehNetID, vehicleData in pairs(spawnedAirUnits) do
                if vehicleData.officers[pedNetID] then
                    vehicleData.officers[pedNetID] = nil

                    if not next(vehicleData.officers) then
                        -- If no officers left tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
                        -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
                        if Config.isDebug then print('Removing DeadOfficerHeli ID = ' .. vehNetID) end
                        TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
                        spawnedAirUnits[vehNetID] = nil    
                    end
                    break
                end
            end

        end
    end


end




-- Function to handle the deletion of far peds after timer
local function handleFarPeds()

    -- Ground Units --
    for pedNetID, farPed in pairs(farOfficers) do

        if farPed.timer >= (Config.farOfficerCleanupTimer / Config.scriptFrequencyModulus) then

            -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
            if Config.isDebug then print('Remove FarOfficer ID = ' .. pedNetID) end
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            farOfficers[pedNetID] = nil

            -- Loop through all stored vehicles and set officers[pedNetID] = nil
            -- If our officer exists for that vehicle, they are removed. Otherwise does nothing. 
            for vehNetID, vehicleData in pairs(spawnedVehicles) do
                if vehicleData.officers[pedNetID] then
                    vehicleData.officers[pedNetID] = nil

                    if not next(vehicleData.officers) then
                        -- If no officers left tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
                        -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
                        if Config.isDebug then print('Remove FarOfficerVehicle ID = ' .. vehNetID) end
                        TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
                        spawnedVehicles[vehNetID] = nil  
                    end
                    break
                end
            end

        end
    end

    -- Heli Units --
    for pedNetID, farPed in pairs(farHeliPeds) do

        if farPed.timer >= (Config.farHeliPilotCleanupTimer / Config.scriptFrequencyModulus) then

            -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
            if Config.isDebug then print('Remove FarHeliPilot ID = ' .. pedNetID) end
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            farHeliPeds[pedNetID] = nil

            -- Loop through all stored vehicles and set officers[pedNetID] = nil
            -- If our officer exists for that vehicle, they are removed. Otherwise does nothing. 
            for vehNetID, vehicleData in pairs(spawnedHeliUnits) do
                if vehicleData.officers[pedNetID] then
                    vehicleData.officers[pedNetID] = nil

                    if not next(vehicleData.officers) then
                        -- If no officers left tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
                        -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
                        if Config.isDebug then print('Remove FarOfficerHeli ID = ' .. vehNetID) end
                        TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
                        spawnedHeliUnits[vehNetID] = nil 
                    end
                    break
                end
            end

        end
    end

    -- Air Units --
    for pedNetID, farPed in pairs(farAirPeds) do

        if farPed.timer >= (Config.farAirPilotCleanupTimer / Config.scriptFrequencyModulus) then

             -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
             if Config.isDebug then print('Remove FarAirPilot ID = ' .. pedNetID) end
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            farAirPeds[pedNetID] = nil
 
             -- Loop through all stored vehicles and set officers[pedNetID] = nil
             -- If our officer exists for that vehicle, they are removed. Otherwise does nothing. 
             for vehNetID, vehicleData in pairs(spawnedAirUnits) do
                 if vehicleData.officers[pedNetID] then
                     vehicleData.officers[pedNetID] = nil
 
                     if not next(vehicleData.officers) then
                         -- If no officers left tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
                         -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
                         if Config.isDebug then print('Remove FarOfficerAir ID = ' .. vehNetID) end
                        TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
                        spawnedAirUnits[vehNetID] = nil
                     end
                     break
                 end
             end

        end
    end


end




-- This function handles re-tasking the police when you first lose your wanted level so they drive off and stop pursuing the player.
local function handleEndWantedTasks()


    for vehNetID, vehicleData in pairs(spawnedVehicles) do
        local vehicle = NetToVeh(vehNetID) -- vehicleData.vehicle -- NetToVeh(vehNetID)
        
        -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not vehicle or vehicle == 0) and waitCount < Config.controlWaitCount do
            vehicle = NetToVeh(vehNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end
        if (not vehicle or vehicle == 0) then
            if Config.isDebug then print('EndWantedUnit vehicle ID ' .. vehNetID .. ' NetToVeh still nil or 0, gave up ') end
        end
        --if Config.isDebug then print('CLIENT NetToVeh for netID ' ..vehNetID .. ' returned entityID ' .. vehicle)  end
        --if Config.isDebug then print('CLIENT VehToNet for entityID ' ..vehicle.. ' returned NetID = ' .. VehToNet(vehicle))  end

        for pedNetID, officerData in pairs(vehicleData.officers) do
            local officer = NetToPed(pedNetID) --officerData -- NetToPed(pedNetID)

            -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            if not DoesEntityExist(officer) or officer == 0 then
                if Config.isDebug then print('EndWantedUnit ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end

            if DoesEntityExist(officer) then
                if Config.isDebug then print('Terminating tasks and setting cruise') end 

                
                if IsPedInVehicle(officer, vehicle, false) then
                    ClearPedTasks(officer)
                    TaskVehicleDriveWander(officer, vehicle, 30.0, 262571) 
                    SetSirenKeepOn(vehicle, false) 
                else
                    ClearPedTasksImmediately(officer)
                    if DoesEntityExist(vehicle) then
                        -- Try to get back into own vehicle, not sure if tasks will be executed in order or if they will fail to drive off after?
                        TaskEnterVehicle(officer, vehicle, 20000, -1, 1.5, 8, 0)
                        TaskVehicleDriveWander(officer, vehicle, 30.0, 262571) 
                    else
                        TaskWanderStandard(officer, 10.0, 10)
                    end    
                end
            end
        end
    end

    for vehNetID, vehicleData in pairs(spawnedHeliUnits) do
        local vehicle = NetToVeh(vehNetID)
        
        -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not vehicle or vehicle == 0) and waitCount < Config.controlWaitCount do
            vehicle = NetToVeh(vehNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end
        if (not vehicle or vehicle == 0) then
            if Config.isDebug then print('EndWantedHeli vehicle ID ' .. vehNetID .. ' NetToVeh still nil or 0, gave up ') end
        end
        --if Config.isDebug then print('CLIENT NetToVeh for netID ' ..vehNetID .. ' returned entityID ' .. vehicle)  end
        --if Config.isDebug then print('CLIENT VehToNet for entityID ' ..vehicle.. ' returned NetID = ' .. VehToNet(vehicle))  end


        for pedNetID, officerData in pairs(vehicleData.officers) do
            local officer = NetToPed(pedNetID)

            -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            if not DoesEntityExist(officer) or officer == 0 then
                if Config.isDebug then print('EndWantedHeli ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end

            if DoesEntityExist(officer) then

                local driver = GetPedInVehicleSeat(vehicle, -1) 
                if driver == officer then
                    ClearPedTasks(officer)
                    -- Re-use this logic to get point near here to fly to
                    local flyPoint, spawnHeading = getRandomPointInRange(GetEntityCoords(officer), Config.minHeliSpawnDistance, Config.maxHeliSpawnDistance, Config.minHeliSpawnHeight, Config.maxHeliSpawnHeight) 
                    if flyPoint then
                        TaskVehicleDriveToCoord(officer, vehicle, flyPoint.x, flyPoint.y, flyPoint.z, 60.0, 1, GetEntityModel(vehicle), 16777248, 70.0, true)
                    end
                else
                    -- Prevent ped from leaving the vehicle
                    TaskSetBlockingOfNonTemporaryEvents(officer, true)
                    -- Clear specific combat-related tasks
                    ClearPedTasks(officer)
                    TaskSetBlockingOfNonTemporaryEvents(officer, false)
                end
            end
        end
    end

    for vehNetID, vehicleData in pairs(spawnedAirUnits) do
        local vehicle = NetToVeh(vehNetID)
        
        -- I've found that one call isn't enough, and it can take multiple NetToVeh calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
        local waitCount = 0
        while (not vehicle or vehicle == 0) and waitCount < Config.controlWaitCount do
            vehicle = NetToVeh(vehNetID)
            Wait(Config.netWaitTime)
            waitCount = waitCount + 1
        end
        if (not vehicle or vehicle == 0) then
            if Config.isDebug then print('EndWantedAir vehicle ID ' .. vehNetID .. ' NetToVeh still nil or 0, gave up ') end
        end
        --if Config.isDebug then print('CLIENT NetToVeh for netID ' ..vehNetID .. ' returned entityID ' .. vehicle)  end
        --if Config.isDebug then print('CLIENT VehToNet for entityID ' ..vehicle.. ' returned NetID = ' .. VehToNet(vehicle))  end


        for pedNetID, officerData in pairs(vehicleData.officers) do
            local officer = NetToPed(pedNetID)

            -- I've found that one call isn't enough, and it can take multiple NetToPed calls before it is not nil or == 0 regardless of the time that has passed since spawn. 
            local waitCount = 0
            while (not officer or officer == 0) and waitCount < Config.controlWaitCount do
                officer = NetToPed(pedNetID)
                Wait(Config.netWaitTime)
                waitCount = waitCount + 1
            end
            if not DoesEntityExist(officer) or officer == 0 then
                if Config.isDebug then print('EndWantedAir ped ID ' .. pedNetID .. ' NetToPed still nil or 0, gave up ') end
            end
            --if Config.isDebug then print('CLIENT NetToPed for netID ' ..pedNetID .. ' returned entityID ' .. officer)  end
            --if Config.isDebug then print('CLIENT PedToNet for entityID ' ..officer.. ' returned NetID = ' .. PedToNet(officer))  end

            if DoesEntityExist(officer) then
                if Config.isDebug then print('Terminating tasks and setting cruise') end

                local driver = GetPedInVehicleSeat(vehicle, -1) 
                if driver == officer then
                    ClearPedTasks(officer)
                    -- Re-use this logic to get point near here to fly to
                    local flyPoint, spawnHeading = getRandomPointInRange(GetEntityCoords(officer), Config.minAirSpawnDistance, Config.maxAirSpawnDistance, Config.minAirSpawnHeight, Config.maxAirSpawnHeight) 
                    if flyPoint then
                        TaskVehicleDriveToCoord(officer, vehicle, flyPoint.x, flyPoint.y, flyPoint.z, 60.0, 1, GetEntityModel(vehicle), 16777248, 70.0, true)
                    end
                else
                    -- Prevent ped from leaving the vehicle
                    TaskSetBlockingOfNonTemporaryEvents(officer, true)
                    -- Clear specific combat-related tasks
                    ClearPedTasks(officer)
                    TaskSetBlockingOfNonTemporaryEvents(officer, false)
                end
                
            end
        end
    end

end




-- This function handles deleting the police units when you have lost your wanted level and the timer has expired. 
-- The above function + this function attempts to have the police drive off, then when far enough away delete them. 
local function handleEndWantedDelete()

    -- If wanted level is 0, remove all police units
    -- Remove Ground Units
    for vehNetID, vehicleData in pairs(spawnedVehicles) do

        -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
        for pedNetID, officerData in pairs(vehicleData.officers) do
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            spawnedVehicles[vehNetID].officers[pedNetID] = nil
            if Config.isDebug then print('Cleaned up police officer ') end
        end

        -- Only remove the vehicle if all officers were removed this cycle!
        if not next(vehicleData.officers) then
            -- If no officers left tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
            -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
            TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
            if Config.isDebug then print('Cleaned up police vehicle ') end
            spawnedVehicles[vehNetID] = nil 
        end

    end


    -- Remove Helicopter Units
    for vehNetID, vehicleData in pairs(spawnedHeliUnits) do


        -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
        for pedNetID, officerData in pairs(vehicleData.officers) do
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            spawnedHeliUnits[vehNetID].officers[pedNetID] = nil
            if Config.isDebug then print('Cleaned up heli officer ') end
        end

        -- Only remove the vehicle if all officers were removed this cycle!
        if not next(vehicleData.officers) then
            -- If no officers left tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
            -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
            TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
            if Config.isDebug then print('Cleaned up heli unit ') end
            spawnedHeliUnits[vehNetID] = nil
        end

    end

    -- Remove Air Units
    for vehNetID, vehicleData in pairs(spawnedAirUnits) do

         -- We should be able to tell the server to delete the NetID whether it exists locally for us or not and trust that it will be removed and remove it from the table now
         for pedNetID, officerData in pairs(vehicleData.officers) do
            TriggerServerEvent('deleteSpawnedPed', pedNetID)
            if Config.isDebug then print('Cleaned up air officer ') end
            spawnedAirUnits[vehNetID].officers[pedNetID] = nil
        end

        -- Only remove the vehicle if all officers were removed this cycle!
        if not next(vehicleData.officers) then
            -- If no officers left tells server to delete vehicle. Server will check if there is a ped in the driver seat first.
            -- If they are, the server will not delete the vehicle but send back a response to the client to add to stolenVehicles table instead.
            TriggerServerEvent('deleteSpawnedVehicle', vehNetID)
            if Config.isDebug then print('Cleaned up air unit ') end
            spawnedAirUnits[vehNetID] = nil
        end

    end

    if Config.isDebug then print('All Units Cleaned Up') end
end




-- ENABLE DISPATCH FEATURES --

-- Server will tell clients whether to enable/disable disaptch services.
-- This could be based on whether players with police jobs are online or not if configured.
local function UpdateDispatchServices()

    Citizen.CreateThread(function()

        if disableAIPolice == true then

            QBCore.Functions.Notify('Fenix Police Response: Disabled')
            if Config.isDebug then print('Fenix Police Response: Disabled') end


            SetAudioFlag('PoliceScannerDisabled', true)
            SetCreateRandomCops(false)
            SetCreateRandomCopsNotOnScenarios(false)

            -- NOTE this can cause problems with some mods and will crash your game if set to false for some reason. Disabling a particular mod resolved it
            -- for me. Or you can leave it true if you use those mods.
            SetCreateRandomCopsOnScenarios(false) 
            
            DistantCopCarSirens(false)
        
            SetMaxWantedLevel(0) -- Disable wanted level

            -- This removes vehicles from generating at PDs when police are online. 
            if Config.RemoveVehicleGenerators == true then
                RemoveVehiclesFromGeneratorsInArea(335.2616 - 300.0, -1432.455 - 300.0, 46.51 - 300.0, 335.2616 + 300.0, -1432.455 + 300.0, 346.51)
                RemoveVehiclesFromGeneratorsInArea(441.8465 - 500.0, -987.99 - 500.0, 30.68 -500.0, 441.8465 + 500.0, -987.99 + 500.0, 30.68 + 500.0)
                RemoveVehiclesFromGeneratorsInArea(316.79 - 300.0, -592.36 - 300.0, 43.28 - 300.0, 316.79 + 300.0, -592.36 + 300.0, 43.28 + 300.0)
                RemoveVehiclesFromGeneratorsInArea(-2150.44 - 500.0, 3075.99 - 500.0, 32.8 - 500.0, -2150.44 + 500.0, -3075.99 + 500.0, 32.8 + 500.0)
                RemoveVehiclesFromGeneratorsInArea(-1108.35 - 300.0, 4920.64 - 300.0, 217.2 - 300.0, -1108.35 + 300.0, 4920.64 + 300.0, 217.2 + 300.0)
                RemoveVehiclesFromGeneratorsInArea(-458.24 - 300.0, 6019.81 - 300.0, 31.34 - 300.0, -458.24 + 300.0, 6019.81 + 300.0, 31.34 + 300.0)
                RemoveVehiclesFromGeneratorsInArea(1854.82 - 300.0, 3679.4 - 300.0, 33.82 - 300.0, 1854.82 + 300.0, 3679.4 + 300.0, 33.82 + 300.0)
                RemoveVehiclesFromGeneratorsInArea(-724.46 - 300.0, -1444.03 - 300.0, 5.0 - 300.0, -724.46 + 300.0, -1444.03 + 300.0, 5.0 + 300.0)
            end

        else

            QBCore.Functions.Notify('Fenix Police Response: Enabled')
            if Config.isDebug then print('Fenix Police Response: Enabled') end

            SetAudioFlag('PoliceScannerDisabled', false)
            SetCreateRandomCops(true)
            SetCreateRandomCopsNotOnScenarios(true)
            SetCreateRandomCopsOnScenarios(true)
            DistantCopCarSirens(false) --I keep this off for personal preference, I found sometimes they got stuck on and it was annoying.
        
            SetMaxWantedLevel(5) -- Uses max 5 star wanted level
        end

        -- Always enable the dispatch services, as they are only meant for non-police things like Ambulance/Fire as this mod handles police separately. 
        for i = 1, 15 do
            local toggle = Config.AIResponse.dispatchServices[i]
            EnableDispatchService(i, toggle)
        end


        -- Always update evasion times for when this mod handles police.
        for i, evasionTime in ipairs(Config.evasionTimes) do
            SetWantedLevelHiddenEvasionTime(PlayerId(), i, evasionTime)
        end
    
    end)

end



-- COPS ONLINE CHECKING --

RegisterNetEvent('fenix-police:updateCopsOnline', function(polCount)
    if polCount >= Config.numberOfPoliceRequired and Config.onlyWhenPlayerPoliceOffline == true then
        if disableAIPolice == true then
            -- Already disabled no need to do the same thing again.
        else
            disableAIPolice = true
            UpdateDispatchServices()
        end
    elseif (Config.onlyWhenPlayerPoliceOffline == false) or (polCount < Config.numberOfPoliceRequired and Config.onlyWhenPlayerPoliceOffline == true)  then
        if disableAIPolice == false then
            -- Already enabled no need to do the same thing again.
        else
            disableAIPolice = false
            UpdateDispatchServices()
        end
    end
end)

-- checks if a player is one of the police jobs configured and returns true if they are.
local function isPlayerPoliceOfficer()

    local playerData = QBCore.Functions.GetPlayerData()
    local isPolice = false

    
    for _, job in ipairs(Config.PoliceJobsToCheck) do
        if playerData.job.name == job.jobName then
            -- Check if configured to only count on-duty players?
            if Config.PlayerPoliceOnlyOnDuty then
                if playerData.job.onduty then
                    isPolice = true
                else
                    isPolice = false
                end
            else
                isPolice = true
            end
        end
    end

    return isPolice

end


    

-- MAIN THREAD --
-- Monitor the player's wanted level and maintain police units
Citizen.CreateThread(function()
    local wantedTimer = 0

    -- Create a thread that continuously loops
    while true do

        Citizen.Wait(Config.scriptFrequency)
        local playerPed = PlayerPedId()
        local wantedLevel = GetPlayerWantedLevel(PlayerId())
        
        if wantedLevel > 0 then

            -- If police are protected we should check if player is a cop and prevent being wanted
            if Config.PoliceWantedProtection then
                local playerIsOfficer = isPlayerPoliceOfficer()
                if playerIsOfficer == true then
                    wantedLevel = 0
                    ClearPlayerWantedLevel(PlayerId())
                end
            end

            

            if QBCore.Functions.GetPlayerData().metadata['isdead'] or QBCore.Functions.GetPlayerData().metadata['inlaststand'] then

                local vehicle = GetVehiclePedIsIn(playerPed, false)

                if vehicle and vehicle ~= 0 then 
                    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
                    local otherPeds = false

                    for seat = -1, seats - 2 do
                        local pedInSeat = GetPedInVehicleSeat(vehicle, seat)
                        if pedInSeat ~= 0 and pedInSeat ~= playerPed then
                            otherPeds = true
                            break
                        end
                    end

                    if otherPeds then
                        -- If there are other players in the vehicle we don't want to clear wanted level or it will affect all players in the vehicle!
                    else
                        ClearPlayerWantedLevel(PlayerId())
                    end
                else
                    ClearPlayerWantedLevel(PlayerId())
                end
                
                
            else

                wantedTimer = 0
                maintainPoliceUnits(wantedLevel) -- Checks if we need to spawn more units, or remove excess units.
                checkDeadPeds() -- Check for dead peds
                handleDeadPeds() -- Handle the deletion of dead peds.
                handleFarPeds() -- Handle the deletion of far peds. 

                for vehNetID, vehicleData in pairs(spawnedVehicles) do
                    handleChaseBehavior(vehicleData, playerPed, vehNetID) -- Handles starting foot pursuits, or getting back into vehicles
                end

                for vehNetID, vehicleData in pairs(spawnedHeliUnits) do
                    handleHeliChaseBehavior(vehicleData, playerPed, vehNetID) -- Handles starting foot pursuits, or getting back into vehicles
                end

                for vehNetID, vehicleData in pairs(spawnedAirUnits) do
                    handleAirChaseBehavior(vehicleData, playerPed, vehNetID) -- Handles starting foot pursuits, or getting back into vehicles
                end

            end
        else

            -- Player is no longer wanted we should set the officers to cruise and then delete them after a time
            if wantedTimer == 0 then
                -- Do this only once
                handleEndWantedTasks()
            end

            if wantedTimer == (Config.endWantedCleanupTimer / Config.scriptFrequencyModulus) then          
                handleEndWantedDelete()       
                wantedTimer = wantedTimer + 1    
            else
                wantedTimer = wantedTimer + 1
            end
        end
    end
end)




-- MONITOR POLICE VEHICLES AND ADD CAMERAMAN FOR LINE OF SIGHT --
-- Monitor police vehicles and spawn cameraman to allow for visibility and detection of player to work correctly. 




-- Function to check if the ped model is a cop
function IsCopPed(model)
    local copModels = {
        's_m_y_cop_01', -- LSPD
        -- 's_f_y_cop_01', -- Female LSPD
        -- 's_m_y_sheriff_01', -- Sheriff
        -- 's_f_y_sheriff_01', -- Female Sheriff
        -- 's_m_y_hwaycop_01', -- Highway Cop
        -- 's_m_y_swat_01', -- SWAT (NOOSE)
        -- 's_m_m_snowcop_01', -- Snow Cop
        -- 's_m_m_fibsec_01' -- FIB Security
    }

    for _, copModel in ipairs(copModels) do
        if model == GetHashKey(copModel) then
            return true
        end
    end
    return false
end




-- This thread creates a "cameraman" for police vehicles. Essentially spawning an invisible cop above the car for a 1/4 second, just long enough to spot players, before deleting the cameraman. 
-- These are created clientside only, and NOT networked so it should only create them on the client PC and not try to sync them to the server.
-- When these were synced/networked I ran into issues where hundreds of invisible police officers would be all over the place. In theory this is because the server is being told to create them 
-- and the lag time means all the other clients are being told to create these peds too, long after the initial client had already deleted them, and that delete was not being communicated for some reason.
-- Since the purpose of these peds is only to allow vehicles to actually spot a wanted player there is no reason other clients need to know they exist. 
CreateThread(function ()
    local cleanupCameras = false
    while true do
        if GetPlayerWantedLevel(PlayerId()) >= 1 then 

            cleanupCameras = true
            local allVehicles = QBCore.Functions.GetVehicles()

            -- Loop through all cars and look for emergency vehicles driven by police.
            -- This will add a cameraman, disabling their vision cone to prevent duplicates on minimap. This will allow cops to actually
            -- see the player instead of being able to easily drive right past them while actively wanted without them noticing you. 
            for _, vehicle in pairs(allVehicles) do 

                -- Check for emergency vehicles only
                if GetVehicleClass(vehicle) == 18 then 
                    CreateThread(function () 
                        local carPos = GetEntityCoords(vehicle)
                        local theDriver = GetPedInVehicleSeat(vehicle, -1)
                        if theDriver then
                            local carheading = GetEntityHeading(theDriver)
                            local pedHash = GetHashKey('s_m_y_cop_01')
                            local cameraman = CreatePed(0, pedHash, carPos.x, carPos.y, carPos.z+10, carheading, false, false)
                            SetPedAiBlipHasCone(cameraman, false)  
                            SetPedAsCop(cameraman)  
                            SetEntityInvincible(cameraman, true)
                            SetEntityVisible(cameraman, false, 0)
                            SetEntityCompletelyDisableCollision(cameraman, true, false)
                            
                            Wait(250) -- Wait for 1/4 second to allow the cameraman to observe players and allow the game to handle wanted logic
                            DeletePed(cameraman) -- Remove the cameraman when done. 
                        end
                    end)
                end
            end
            Wait(200) -- Wait 1/5th second when wanted
        else

            -- Only loop through all peds once and delete cameramen. 
            if cleanupCameras == true then
                local pedPool = GetGamePool('CPed') -- Get all peds in the game world

                for _, ped in ipairs(pedPool) do
                    if IsPedHuman(ped) and IsPedAPlayer(ped) == false then -- Check if the ped is a human and not a player
                        local pedModel = GetEntityModel(ped)
        
                        if IsPedInAnyPoliceVehicle(ped) or IsCopPed(pedModel) then -- Check if the ped is a cop or in a police vehicle
                            if not IsEntityVisible(ped) then -- Check if the ped is invisible
                                if Config.isDebug then print('Found invisible cameraman officer and deleted it') end
                                DeleteEntity(ped) -- Delete the invisible ped
                            end
                        end
                    end
                end
                cleanupCameras = false
            end
            Wait(1000) -- Wait 10 seconds when not wanted

            
        end
    end
end)




-- **HELPFUL NATIVE FUNCTION INFO** --

--void TASK_ENTER_VEHICLE(Ped ped, Vehicle vehicle, int timeout, int seat, float speed, int p5, Any p6) // 0xC20E50AA46D09CA8 0xB8689B4E
-- Example usage  
-- VEHICLE::GET_CLOSEST_VEHICLE(x, y, z, radius, hash, unknown leave at 70)   
-- x, y, z: Position to get closest vehicle to.  
-- radius: Max radius to get a vehicle.  
-- modelHash: Limit to vehicles with this model. 0 for any.  
-- flags: The bitwise flags altering the function's behaviour.  
-- Does not return police cars or helicopters.  
-- It seems to return police cars for me, does not seem to return helicopters, planes or boats for some reason  
-- Only returns non police cars and motorbikes with the flag set to 70 and modelHash to 0. ModelHash seems to always be 0 when not a modelHash in the scripts, as stated above.   
-- These flags were found in the b617d scripts: 0,2,4,6,7,23,127,260,2146,2175,12294,16384,16386,20503,32768,67590,67711,98309,100359.  
-- Converted to binary, each bit probably represents a flag as explained regarding another native here: gtaforums.com/topic/822314-guide-driving-styles  
-- Conversion of found flags to binary: pastebin.com/kghNFkRi  
-- At exactly 16384 which is 0100000000000000 in binary and 4000 in hexadecimal only planes are returned.   
-- It's probably more convenient to use worldGetAllVehicles(int *arr, int arrSize) and check the shortest distance yourself and sort if you want by checking the vehicle type with for example VEHICLE::IS_THIS_MODEL_A_BOAT  
-- -------------------------------------------------------------------------  
-- Conclusion: This native is not worth trying to use. Use something like this instead: pastebin.com/xiFdXa7h
-- Use flag 127 to return police cars

-- -- TASK_ARREST_PED
-- TaskArrestPed(
-- 	ped --[[ Ped ]], 
-- 	target --[[ Ped ]]
-- )


-- -- SET_PED_COMBAT_ATTRIBUTES
-- SetPedCombatAttributes(
-- 	ped --[[ Ped ]], 
-- 	attributeIndex --[[ integer ]], 
-- 	enabled --[[ boolean ]]
-- )
-- enum eCombatAttribute
-- {
--   CA_INVALID = -1,	
--   CA_USE_COVER = 0, // AI will only use cover if this is set
--   CA_USE_VEHICLE = 1, // AI will only use vehicles if this is set
--   CA_DO_DRIVEBYS = 2, // AI will only driveby from a vehicle if this is set
--   CA_LEAVE_VEHICLES = 3, // Will be forced to stay in a ny vehicel if this isn't set
--   CA_CAN_USE_DYNAMIC_STRAFE_DECISIONS	= 4, // This ped can make decisions on whether to strafe or not based on distance to destination, recent bullet events, etc.
--   CA_ALWAYS_FIGHT = 5, // Ped will always fight upon getting threat response task
--   CA_FLEE_WHILST_IN_VEHICLE = 6, // If in combat and in a vehicle, the ped will flee rather than attacking
--   CA_JUST_FOLLOW_VEHICLE = 7, // If in combat and chasing in a vehicle, the ped will keep a distance behind rather than ramming
--   CA_PLAY_REACTION_ANIMS = 8, // Deprecated
--   CA_WILL_SCAN_FOR_DEAD_PEDS = 9, // Peds will scan for and react to dead peds found
--   CA_IS_A_GUARD = 10, // Deprecated
--   CA_JUST_SEEK_COVER = 11, // The ped will seek cover only 
--   CA_BLIND_FIRE_IN_COVER = 12, // Ped will only blind fire when in cover
--   CA_AGGRESSIVE = 13, // Ped may advance
--   CA_CAN_INVESTIGATE = 14, // Ped can investigate events such as distant gunfire, footsteps, explosions etc
--   CA_CAN_USE_RADIO = 15, // Ped can use a radio to call for backup (happens after a reaction)
--   CA_CAN_CAPTURE_ENEMY_PEDS = 16, // Deprecated
--   CA_ALWAYS_FLEE = 17, // Ped will always flee upon getting threat response task
--   CA_CAN_TAUNT_IN_VEHICLE = 20, // Ped can do unarmed taunts in vehicle
--   CA_CAN_CHASE_TARGET_ON_FOOT = 21, // Ped will be able to chase their targets if both are on foot and the target is running away
--   CA_WILL_DRAG_INJURED_PEDS_TO_SAFETY = 22, // Ped can drag injured peds to safety
--   CA_REQUIRES_LOS_TO_SHOOT = 23, // Ped will require LOS to the target it is aiming at before shooting
--   CA_USE_PROXIMITY_FIRING_RATE = 24, // Ped is allowed to use proximity based fire rate (increasing fire rate at closer distances)
--   CA_DISABLE_SECONDARY_TARGET = 25, // Normally peds can switch briefly to a secondary target in combat, setting this will prevent that
--   CA_DISABLE_ENTRY_REACTIONS = 26, // This will disable the flinching combat entry reactions for peds, instead only playing the turn and aim anims
--   CA_PERFECT_ACCURACY = 27, // Force ped to be 100% accurate in all situations (added by Jay Reinebold)
--   CA_CAN_USE_FRUSTRATED_ADVANCE	= 28, // If we don't have cover and can't see our target it's possible we will advance, even if the target is in cover
--   CA_MOVE_TO_LOCATION_BEFORE_COVER_SEARCH = 29, // This will have the ped move to defensive areas and within attack windows before performing the cover search
--   CA_CAN_SHOOT_WITHOUT_LOS = 30, // Allow shooting of our weapon even if we don't have LOS (this isn't X-ray vision as it only affects weapon firing)
--   CA_MAINTAIN_MIN_DISTANCE_TO_TARGET = 31, // Ped will try to maintain a min distance to the target, even if using defensive areas (currently only for cover finding + usage) 
--   CA_CAN_USE_PEEKING_VARIATIONS	= 34, // Allows ped to use steamed variations of peeking anims
--   CA_DISABLE_PINNED_DOWN = 35, // Disables pinned down behaviors
--   CA_DISABLE_PIN_DOWN_OTHERS = 36, // Disables pinning down others
--   CA_OPEN_COMBAT_WHEN_DEFENSIVE_AREA_IS_REACHED = 37, // When defensive area is reached the area is cleared and the ped is set to use defensive combat movement
--   CA_DISABLE_BULLET_REACTIONS = 38, // Disables bullet reactions
--   CA_CAN_BUST = 39, // Allows ped to bust the player
--   CA_IGNORED_BY_OTHER_PEDS_WHEN_WANTED = 40, // This ped is ignored by other peds when wanted
--   CA_CAN_COMMANDEER_VEHICLES = 41, // Ped is allowed to 'jack' vehicles when needing to chase a target in combat
--   CA_CAN_FLANK = 42, // Ped is allowed to flank
--   CA_SWITCH_TO_ADVANCE_IF_CANT_FIND_COVER = 43,	// Ped will switch to advance if they can't find cover
--   CA_SWITCH_TO_DEFENSIVE_IF_IN_COVER = 44, // Ped will switch to defensive if they are in cover
--   CA_CLEAR_PRIMARY_DEFENSIVE_AREA_WHEN_REACHED = 45, // Ped will clear their primary defensive area when it is reached
--   CA_CAN_FIGHT_ARMED_PEDS_WHEN_NOT_ARMED = 46, // Ped is allowed to fight armed peds when not armed
--   CA_ENABLE_TACTICAL_POINTS_WHEN_DEFENSIVE = 47, // Ped is not allowed to use tactical points if set to use defensive movement (will only use cover)
--   CA_DISABLE_COVER_ARC_ADJUSTMENTS = 48, // Ped cannot adjust cover arcs when testing cover safety (atm done on corner cover points when  ped usingdefensive area + no LOS)
--   CA_USE_ENEMY_ACCURACY_SCALING	= 49, // Ped may use reduced accuracy with large number of enemies attacking the same local player target
--   CA_CAN_CHARGE = 50, // Ped is allowed to charge the enemy position
--   CA_REMOVE_AREA_SET_WILL_ADVANCE_WHEN_DEFENSIVE_AREA_REACHED = 51, // When defensive area is reached the area is cleared and the ped is set to use will advance movement
--   CA_USE_VEHICLE_ATTACK = 52, // Use the vehicle attack mission during combat (only works on driver)
--   CA_USE_VEHICLE_ATTACK_IF_VEHICLE_HAS_MOUNTED_GUNS = 53, // Use the vehicle attack mission during combat if the vehicle has mounted guns (only works on driver)
--   CA_ALWAYS_EQUIP_BEST_WEAPON = 54, // Always equip best weapon in combat
--   CA_CAN_SEE_UNDERWATER_PEDS = 55, // Ignores in water at depth visibility check
--   CA_DISABLE_AIM_AT_AI_TARGETS_IN_HELIS = 56, // Will prevent this ped from aiming at any AI targets that are in helicopters
--   CA_DISABLE_SEEK_DUE_TO_LINE_OF_SIGHT = 57, // Disables peds seeking due to no clear line of sight
--   CA_DISABLE_FLEE_FROM_COMBAT = 58, // To be used when releasing missions peds if we don't want them fleeing from combat (mission peds already prevent flee)
--   CA_DISABLE_TARGET_CHANGES_DURING_VEHICLE_PURSUIT = 59, // Disables target changes during vehicle pursuit
--   CA_CAN_THROW_SMOKE_GRENADE = 60, // Ped may throw a smoke grenade at player loitering in combat
--   CA_CLEAR_AREA_SET_DEFENSIVE_IF_DEFENSIVE_CANNOT_BE_REACHED = 62, // Will clear a set defensive area if that area cannot be reached
--   CA_DISABLE_BLOCK_FROM_PURSUE_DURING_VEHICLE_CHASE = 64, // Disable block from pursue during vehicle chases
--   CA_DISABLE_SPIN_OUT_DURING_VEHICLE_CHASE = 65, // Disable spin out during vehicle chases
--   CA_DISABLE_CRUISE_IN_FRONT_DURING_BLOCK_DURING_VEHICLE_CHASE = 66, // Disable cruise in front during block during vehicle chases
--   CA_CAN_IGNORE_BLOCKED_LOS_WEIGHTING = 67, // Makes it more likely that the ped will continue targeting a target with blocked los for a few seconds
--   CA_DISABLE_REACT_TO_BUDDY_SHOT = 68, // Disables the react to buddy shot behaviour.
--   CA_PREFER_NAVMESH_DURING_VEHICLE_CHASE = 69, // Prefer pathing using navmesh over road nodes
--   CA_ALLOWED_TO_AVOID_OFFROAD_DURING_VEHICLE_CHASE = 70, // Ignore road edges when avoiding
--   CA_PERMIT_CHARGE_BEYOND_DEFENSIVE_AREA = 71, // Permits ped to charge a target outside the assigned defensive area.
--   CA_USE_ROCKETS_AGAINST_VEHICLES_ONLY = 72, // This ped will switch to an RPG if target is in a vehicle, otherwise will use alternate weapon.
--   CA_DISABLE_TACTICAL_POINTS_WITHOUT_CLEAR_LOS = 73, // Disables peds moving to a tactical point without clear los
--   CA_DISABLE_PULL_ALONGSIDE_DURING_VEHICLE_CHASE = 74, // Disables pull alongside during vehicle chase
--   CA_DISABLE_ALL_RANDOMS_FLEE = 78,	// If set on a ped, they will not flee when all random peds flee is set to TRUE (they are still able to flee due to other reasons)
--   CA_WILL_GENERATE_DEAD_PED_SEEN_SCRIPT_EVENTS = 79, // This ped will send out a script DeadPedSeenEvent when they see a dead ped
--   CA_USE_MAX_SENSE_RANGE_WHEN_RECEIVING_EVENTS = 80, // This will use the receiving peds sense range rather than the range supplied to the communicate event
--   CA_RESTRICT_IN_VEHICLE_AIMING_TO_CURRENT_SIDE = 81, // When aiming from a vehicle the ped will only aim at targets on his side of the vehicle
--   CA_USE_DEFAULT_BLOCKED_LOS_POSITION_AND_DIRECTION = 82, // LOS to the target is blocked we return to our default position and direction until we have LOS (no aiming)
--   CA_REQUIRES_LOS_TO_AIM = 83, // LOS to the target is blocked we return to our default position and direction until we have LOS (no aiming)
--   CA_CAN_CRUISE_AND_BLOCK_IN_VEHICLE = 84, // Allow vehicles spawned infront of target facing away to enter cruise and wait to block approaching target
--   CA_PREFER_AIR_COMBAT_WHEN_IN_AIRCRAFT = 85, // Peds flying aircraft will prefer to target other aircraft over entities on the ground
--   CA_ALLOW_DOG_FIGHTING = 86, //Allow peds flying aircraft to use dog fighting behaviours
--   CA_PREFER_NON_AIRCRAFT_TARGETS = 87, // This will make the weight of targets who aircraft vehicles be reduced greatly compared to targets on foot or in ground based vehicles
--   CA_PREFER_KNOWN_TARGETS_WHEN_COMBAT_CLOSEST_TARGET = 88, //When peds are tasked to go to combat, they keep searching for a known target for a while before forcing an unknown one
--   CA_FORCE_CHECK_ATTACK_ANGLE_FOR_MOUNTED_GUNS = 89, // Only allow mounted weapons to fire if within the correct attack angle (default 25-degree cone). On a flag in order to keep exiting behaviour and only fix in specific cases.
--   CA_BLOCK_FIRE_FOR_VEHICLE_PASSENGER_MOUNTED_GUNS = 90 // Blocks the firing state for passenger-controlled mounted weapons. Existing flags CA_USE_VEHICLE_ATTACK and CA_USE_VEHICLE_ATTACK_IF_VEHICLE_HAS_MOUNTED_GUNS only work for drivers.
-- };


-- -- SET_PED_FIRING_PATTERN
-- SetPedFiringPattern(
-- 	ped --[[ Ped ]], 
-- 	patternHash --[[ Hash ]]
-- )

-- FIRING_PATTERN_BURST_FIRE = 0xD6FF6D61 ( 1073727030 )  
-- FIRING_PATTERN_BURST_FIRE_IN_COVER = 0x026321F1 ( 40051185 )  
-- FIRING_PATTERN_BURST_FIRE_DRIVEBY = 0xD31265F2 ( -753768974 )  
-- FIRING_PATTERN_FROM_GROUND = 0x2264E5D6 ( 577037782 )  
-- FIRING_PATTERN_DELAY_FIRE_BY_ONE_SEC = 0x7A845691 ( 2055493265 )  
-- FIRING_PATTERN_FULL_AUTO = 0xC6EE6B4C ( -957453492 )  
-- FIRING_PATTERN_SINGLE_SHOT = 0x5D60E4E0 ( 1566631136 )  
-- FIRING_PATTERN_BURST_FIRE_PISTOL = 0xA018DB8A ( -1608983670 )  
-- FIRING_PATTERN_BURST_FIRE_SMG = 0xD10DADEE ( 1863348768 )  
-- FIRING_PATTERN_BURST_FIRE_RIFLE = 0x9C74B406 ( -1670073338 )  
-- FIRING_PATTERN_BURST_FIRE_MG = 0xB573C5B4 ( -1250703948 )  
-- FIRING_PATTERN_BURST_FIRE_PUMPSHOTGUN = 0x00BAC39B ( 12239771 )  
-- FIRING_PATTERN_BURST_FIRE_HELI = 0x914E786F ( -1857128337 )  
-- FIRING_PATTERN_BURST_FIRE_MICRO = 0x42EF03FD ( 1122960381 )  
-- FIRING_PATTERN_SHORT_BURSTS = 0x1A92D7DF ( 445831135 )  
-- FIRING_PATTERN_SLOW_FIRE_TANK = 0xE2CA3A71 ( -490063247 )  
-- if anyone is interested firing pattern info: pastebin.com/Px036isB  




-- -- _SET_WANTED_LEVEL_HIDDEN_EVASION_TIME
-- SetWantedLevelHiddenEvasionTime(
-- 	player --[[ Player ]], 
-- 	wantedLevel --[[ integer ]], 
-- 	lossTime --[[ integer ]]
-- )


-- -- GIVE_WEAPON_TO_PED
-- GiveWeaponToPed(
-- 	ped --[[ Ped ]], 
-- 	weaponHash --[[ Hash ]], 
-- 	ammoCount --[[ integer ]], 
-- 	isHidden --[[ boolean ]], 
-- 	bForceInHand --[[ boolean ]]
-- )



