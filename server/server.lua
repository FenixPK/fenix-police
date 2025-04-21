-- POLICE JOB CHECKING LOGIC --
QBCore = exports['qb-core']:GetCoreObject()

CreateThread(function()
    while true do
        local polCount = 0
        local players = QBCore.Functions.GetQBPlayers()
        for _, Player in pairs(players) do
            for _, job in ipairs(Config.PoliceJobsToCheck) do
                if Player.PlayerData.job.name == job.jobName then

                    -- Check if configured to only count on-duty players?
                    if job.onDutyOnly then
                        if Player.PlayerData.job.onduty then
                            polCount = polCount + 1
                        end
                    else
                        polCount = polCount + 1
                    end
                end
            end
        end

        Wait(5000) -- Ensure clients are loaded first

        -- -1 source tells ALL clients connected to update their cops online count and do logic pertaining to it.
        TriggerClientEvent('fenix-police:updateCopsOnline', -1, polCount)

        -- Check every minute if new police online
        Wait(55000)
    end
end)




-- CLEANUP LOGIC -- 

-- Server event to delete a vehicle or officer entity from the network ID.
RegisterServerEvent('deleteSpawnedEntity')
AddEventHandler('deleteSpawnedEntity', function(entityNetID)
    local entity = NetworkGetEntityFromNetworkId(entityNetID)
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end)




-- Server event to delete a ped by network ID
RegisterServerEvent('deleteSpawnedPed')
AddEventHandler('deleteSpawnedPed', function(pedNetID)
    local entity = NetworkGetEntityFromNetworkId(pedNetID)
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end)




-- Server event to delete a vehicle by network ID, this will check if anyone is in the vehicle first.
-- If a ped is in the vehicle we can assume it is a player, because this will not have been called until all officers assigned
-- to the vehicle were already deleted. 
RegisterServerEvent('deleteSpawnedVehicle')
AddEventHandler('deleteSpawnedVehicle', function(vehNetID)
    local src = source
    local entity = NetworkGetEntityFromNetworkId(vehNetID)
    if DoesEntityExist(entity) then

        local vehicleHasPlayer = false

        for _, playerId in ipairs(GetPlayers()) do
            local ped = GetPlayerPed(playerId)
            if GetVehiclePedIsIn(ped, false) == entity then
                vehicleHasPlayer = true
                break
            end
        end
        -- Only prevent deletion if the vehicle is occupied by a PLAYER. 
        if vehicleHasPlayer then
            TriggerClientEvent('deleteSpawnedVehicleResponseStolen', src, vehNetID)
        else
            DeleteEntity(entity)
        end 
    end   
end)




-- HELI / AIR UNIT FUNCTIONS --

-- Function to select a random air unit and its peds based on wanted level and spawn chance
local function getRandomAirUnit(spawnTable, currentWantedLevel)
    local candidates = {}

    -- Loop through each unit in the table returned by region.
    for _, unit in ipairs(spawnTable) do

        -- Check if the unit is applicable at the current wanted level and skip it if not.
        if currentWantedLevel >= unit.wantedLevel then
            -- If applicable create a table of candidates to select from randomly later. This is how the spawnChance variable
            -- is used. If picking a random value from a table that has 10 entries, and 9 of those entries are for the same car model
            -- then we have a 9 in 10 chance to spawn that model. 
            for _ = 1, unit.spawnChance do
                table.insert(candidates, unit)
            end
        end
    end

    if #candidates > 0 then

        -- Use a randomIndex to pick one item from the candidates table.
        local randomIndex = math.random(1, #candidates)
        local selectedUnit = candidates[randomIndex]
        local selectedPilots = {}
        local selectedPeds = {}

        -- Use the numPilots variable to spawn that number of pilots to go with the unit
        for _ = 1, selectedUnit.numPilots do
            -- Use a randomPedIndex to pick a ped from the table of possibilities.
            local randomPedIndex = math.random(1, #selectedUnit.pilots)
            table.insert(selectedPilots, selectedUnit.pilots[randomPedIndex])
        end
        
        -- Use the numPeds variable to spawn that number of peds to go with the unit
        for _ = 1, selectedUnit.numPeds do
            -- Use a randomPedIndex to pick a ped from the table of possibilities.
            local randomPedIndex = math.random(1, #selectedUnit.peds)
            table.insert(selectedPeds, selectedUnit.peds[randomPedIndex])
        end

        -- Return values in table format so you can call .unit or .pilots or .peds to access the selectedVehicle or the peds table later.
        return { unit = selectedUnit, pilots = selectedPilots, peds = selectedPeds }
    else
        return nil
    end
end




-- GROUND UNIT FUNCTIONS --

-- Function to select a random vehicle and its peds based on wanted level and spawn chance
local function getRandomVehicle(region, currentWantedLevel)
    local candidates = {}

    -- Loop through each vehicle in the table returned by region.
    for _, vehicle in ipairs(Config.vehiclesByRegion[region]) do
        -- Check if the vehicle is applicable at the current wanted level and skip it if not.
        if currentWantedLevel >= vehicle.wantedLevel then
            -- If applicable create a table of candidates to select from randomly later. This is how the spawnChance variable
            -- is used. If picking a random value from a table that has 10 entries, and 9 of those entries are for the same car model
            -- then we have a 9 in 10 chance to spawn that model. 
            for _ = 1, vehicle.spawnChance do
                table.insert(candidates, vehicle)
            end
        end
    end

    if #candidates > 0 then
        -- Use a randomIndex to pick one item from the candidates table.
        local randomIndex = math.random(1, #candidates)
        local selectedVehicle = candidates[randomIndex]
        local selectedPeds = {}
        
        -- Use the numPeds variable to spawn that number of peds to go with the car
        for _ = 1, selectedVehicle.numPeds do
            -- Use a randomPedIndex to pick a ped from the table of possibilities.
            local randomPedIndex = math.random(1, #selectedVehicle.peds)
            table.insert(selectedPeds, selectedVehicle.peds[randomPedIndex])
        end

        -- Return values in table format so you can call .vehicle or .peds to access the selectedVehicle or the peds table later.
        return { vehicle = selectedVehicle, peds = selectedPeds }
    else
        return nil
    end
end




-- LOADOUT AND COMBAT FUNCTIONS --

-- Function to select a weighted random item from a list
local function selectWeightedRandom(items)
    local totalWeight = 0
    for _, item in ipairs(items) do
        totalWeight = totalWeight + item.weight
    end

    local randomWeight = math.random() * totalWeight
    local currentWeight = 0

    for _, item in ipairs(items) do
        currentWeight = currentWeight + item.weight
        if randomWeight <= currentWeight then
            return item.name
        end
    end
end




-- Function to give a loadout to a ped
local function givePedLoadout(ped, loadout)
    -- Select a weighted random primary weapon
    local primaryWeapon = selectWeightedRandom(loadout.primaryWeapons)

    local waitCount = 0
    local currentWeapon = GetCurrentPedWeapon(ped) 
    
    while currentWeapon ~= GetHashKey(primaryWeapon) and waitCount < Config.spawnWaitCount do
        if #loadout.secondaryWeapons > 0 then
            GiveWeaponToPed(ped, GetHashKey(primaryWeapon), 999, false, false)
        else
            GiveWeaponToPed(ped, GetHashKey(primaryWeapon), 999, false, true) -- force in hand if only weapon
        end
        Wait(100)
        currentWeapon = GetCurrentPedWeapon(ped) 
        waitCount = waitCount + 1
    end

    -- Randomly select a secondary weapon based on secondaryChance
    if math.random() < loadout.secondaryChance and #loadout.secondaryWeapons > 0 then
        local secondaryWeapon = selectWeightedRandom(loadout.secondaryWeapons)

        waitCount = 0
        currentWeapon = GetCurrentPedWeapon(ped) 
        
        while currentWeapon ~= GetHashKey(secondaryWeapon) and waitCount < Config.spawnWaitCount do
            GiveWeaponToPed(ped, GetHashKey(secondaryWeapon), 999, false, true)  
            Wait(100)
            currentWeapon = GetCurrentPedWeapon(ped) 
            waitCount = waitCount + 1
        end

    else
        
        
    end

    -- Add body armor based on armorChance
    if math.random() < loadout.armorChance then
        SetPedArmour(ped, loadout.armorValue)
    end

    -- Add helmet based on helmetChance
    if math.random() < loadout.helmetChance then
        SetPedPropIndex(ped, 0, loadout.helmetModel, 0, true)
    end
end




-- Function to add a weapon with attachments to a ped
local function giveWeaponWithAttachments(ped, weaponHash, attachments)
    -- Give the weapon to the ped
    GiveWeaponToPed(ped, GetHashKey(weaponHash), 999, false, true)

    -- Add each attachment to the weapon
    for _, attachment in ipairs(attachments) do
        GiveWeaponComponentToPed(ped, GetHashKey(weaponHash), GetHashKey(attachment))
    end
end




-- SPAWNING FUNCTIONS --




-- Function to generate a random float between min and max
local function randomFloat(min, max)
    return min + math.random() * (max - min)
end



-- GROUND UNITS --
RegisterNetEvent('spawnPoliceUnitNet')
AddEventHandler('spawnPoliceUnitNet', function(wantedLevel, playerCoords, regionCode, spawnPoint, spawnHeading)
    local src = source
    local seatIndex = -1

    -- Variable will be set true as soon as a vehicle has a driver. I'm less worried about a crew member not warping in properly.
    local vehicleCrewed = false
    local hasDriverCount = 0
    local vehNetID = nil
    local officers = {}

    while (not vehicleCrewed) and hasDriverCount < Config.hasDriverWaitCount do


        vehNetID = nil

        -- Pick the vehicle to choose to spawn for this region, vehicle determines which peds spawn with it, and the peds determine combat behavior and weapons. 
        local selectedEntry = getRandomVehicle(regionCode, wantedLevel)
        if not selectedEntry then
            if Config.isDebug then print('No suitable vehicle found for the given wanted level.') end
            return
        end
        local vehicleHash = GetHashKey(selectedEntry.vehicle.model)


        local vehicle = CreateVehicleServerSetter(vehicleHash, 'automobile', spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnHeading)
        local waitCount = 0 
        while not DoesEntityExist(vehicle) and waitCount < Config.spawnWaitCount do
            Wait(10)
            waitCount = waitCount + 1
        end
        if not DoesEntityExist(vehicle) then
            if Config.isDebug then print('Spawning '..selectedEntry.vehicle.model.. ' failed.') end
            return
        end
        --NetworkRegisterEntityAsNetworked(vehicle)
        vehNetID = NetworkGetNetworkIdFromEntity(vehicle)

        if Config.isDebug then print('NET vehicle ' .. selectedEntry.vehicle.model.. ' spawned with vehNetID = ' ..vehNetID) end

        SetEntityDistanceCullingRadius(vehicle, 10000.0)
        

        officers = {}

        for _, pedModel in ipairs(selectedEntry.peds) do


            local pedHash = GetHashKey(pedModel)

            -- Create officers
            --local officer = CreatePedInsideVehicle(vehicle, 4, pedHash, seatIndex, true, true) -- This did NOT work, it fails far too often and gets stuck spawning empty vehicles. 

            local warpCount = 0
            
            local pedInSeat = nil
            while (not pedInSeat or pedInSeat == 0) and warpCount < Config.warpWaitCount do

                local officer = CreatePed(4, pedHash, spawnPoint.x+20, spawnPoint.y+20, spawnPoint.z, spawnHeading, true, true)
                local waitCount = 0
                while not DoesEntityExist(officer) and waitCount < Config.spawnWaitCount do
                    if Config.isDebug then print('Waiting to spawn officer...') end
                    officer = CreatePed(4, pedHash, spawnPoint.x+20, spawnPoint.y+20, spawnPoint.z, spawnHeading, true, true)
                    Wait(10)
                    waitCount = waitCount + 1
                end
                if not DoesEntityExist(officer) then
                    if Config.isDebug then print('Spawning '..pedModel.. ' failed.') end
                    return
                end
                SetEntityDistanceCullingRadius(officer, 10000.0)
                Wait(50)
                TaskWarpPedIntoVehicle(officer, vehicle, seatIndex)
                Wait(50)
                pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
                local waitCount = 0
                while (not pedInSeat or pedInSeat == 0) and waitCount < Config.spawnWaitCount do
                    -- Try warping them again
                    if Config.isDebug then print('Officer failed to warp into ' .. selectedEntry.vehicle.model .. ' vehNetID = ' .. vehNetID .. ' seat = ' .. seatIndex .. ' trying again ' .. waitCount) end
                    TaskWarpPedIntoVehicle(officer, vehicle, seatIndex)
                    Wait(20)
                    pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
                    waitCount = waitCount + 1
                end

                if (not pedInSeat or pedInSeat == 0) then
                    -- Delete the officer and start over with a fresh one until they warp into the vehicle properly.
                    if Config.isDebug then print('Officer failed to warp into ' .. selectedEntry.vehicle.model .. ' vehNetID = ' .. vehNetID .. ' too many times, deleting entity and starting over ') end
                    DeleteEntity(officer)
                    Wait(100)
                    warpCount = warpCount + 1
                else
                    -- Put this here so if a ped fails to be warped in it will still fill the driver seat first.
                    seatIndex = seatIndex + 1 -- Increase seat index so each seat is filled from driver, to passenger, to rear passengers etc.

                    -- Network setup for officer
                    local pedNetID = NetworkGetNetworkIdFromEntity(officer)
                    if Config.isDebug then print('NET ped ' ..pedModel .. ' spawned with pedNetID = ' ..pedNetID .. ' for vehNetID = ' .. vehNetID) end

                    -- Give officer loadout
                    givePedLoadout(officer, Config.loadouts[selectedEntry.vehicle.loadout])

                    -- Add officer to table to return
                    table.insert(officers, pedNetID)

                    -- We spawned a ped into the vehicle, ensure vehicleCrewed is true.
                    vehicleCrewed = true
                end
            end

            if not vehicleCrewed then
                -- Should break the ped loop and move straight to deleting the vehicle. In my experience if the first one fails to warp they all will. 
                break 
            end


        end

        if not vehicleCrewed then
            if Config.isDebug then print('Vehicle ' .. selectedEntry.vehicle.model .. ' failed to be crewed, deleting vehNetID = ' .. vehNetID .. ' and starting over ') end
            DeleteEntity(vehicle)
            vehNetID = nil
            Wait(100)

            -- Add 1 and try again
            hasDriverCount = hasDriverCount + 1   
        end

        

    end

    
    -- Return the netIDs to the client
    TriggerClientEvent('spawnPoliceUnitNetResponse', src, vehNetID, officers)
    
end)




-- HELI UNITS --
RegisterNetEvent('spawnPoliceHeliNet')
AddEventHandler('spawnPoliceHeliNet', function(wantedLevel, playerCoords, spawnPoint, spawnTable)
    local src = source
    local seatIndex = -1
    
    -- Variable will be set true as soon as a vehicle has a driver. I'm less worried about a crew member not warping in properly.
    local vehicleCrewed = false
    local hasDriverCount = 0
    local vehNetID = nil
    local officers = {}
    

    while (not vehicleCrewed) and hasDriverCount < Config.hasDriverWaitCount do

        vehNetID = nil

        -- Pick the vehicle to choose to spawn for this region, vehicle determines which peds spawn with it, and the peds determine combat behavior and weapons. 
        local selectedEntry = getRandomAirUnit(spawnTable, wantedLevel)
        if not selectedEntry then
            if Config.isDebug then print('No suitable heli found for the given wanted level.') end
            return
        end
        local vehicleHash = GetHashKey(selectedEntry.unit.model)

        local vehicle = CreateVehicleServerSetter(vehicleHash, 'heli', spawnPoint.x, spawnPoint.y, spawnPoint.z, 0.0)
        local waitCount = 0 
        while not DoesEntityExist(vehicle) and waitCount < Config.spawnWaitCount do
            Wait(10)
            waitCount = waitCount + 1
        end
        if not DoesEntityExist(vehicle) then
            if Config.isDebug then print('Spawning '..selectedEntry.unit.model.. ' failed.') end
            return
        end
        vehNetID = NetworkGetNetworkIdFromEntity(vehicle)

        SetEntityDistanceCullingRadius(vehicle, 10000.0)

        

        officers = {}

        local pedInSeat = nil

        for _, pedModel in ipairs(selectedEntry.pilots) do


            local pedHash = GetHashKey(pedModel)


            -- Create pilot
            local warpCount = 0
            pedInSeat = nil
            while (not pedInSeat or pedInSeat == 0) and warpCount < Config.warpWaitCount do

                local officer = CreatePed(4, pedHash, spawnPoint.x+20, spawnPoint.y+20, spawnPoint.z, spawnHeading, true, true)
                local waitCount = 0
                while not DoesEntityExist(officer) and waitCount < Config.spawnWaitCount do
                    if Config.isDebug then print('Waiting to spawn officer...') end
                    officer = CreatePed(4, pedHash, spawnPoint.x+20, spawnPoint.y+20, spawnPoint.z, spawnHeading, true, true)
                    Wait(10)
                    waitCount = waitCount + 1
                end
                if not DoesEntityExist(officer) then
                    if Config.isDebug then print('Spawning '..pedModel.. ' failed.') end
                    return
                end
                SetEntityDistanceCullingRadius(officer, 10000.0)
                Wait(50)
                TaskWarpPedIntoVehicle(officer, vehicle, seatIndex)
                Wait(50)
                pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
                local waitCount = 0
                while (not pedInSeat or pedInSeat == 0) and waitCount < Config.spawnWaitCount do
                    -- Try warping them again
                    if Config.isDebug then print('Officer failed to warp into ' .. selectedEntry.unit.model .. ' vehNetID = ' .. vehNetID .. ' seat = ' .. seatIndex .. ' trying again ' .. waitCount) end
                    TaskWarpPedIntoVehicle(officer, vehicle, seatIndex)
                    Wait(20)
                    pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
                    waitCount = waitCount + 1
                end

                if (not pedInSeat or pedInSeat == 0) then
                    -- Delete the officer and start over with a fresh one until they warp into the vehicle properly.
                    if Config.isDebug then print('Officer failed to warp into ' .. selectedEntry.unit.model .. ' vehNetID = ' .. vehNetID .. ' too many times, deleting entity and starting over ') end
                    DeleteEntity(officer)
                    Wait(100)
                    warpCount = warpCount + 1
                else
                    -- Put this here so if a ped fails to be warped in it will still fill the driver seat first.
                    seatIndex = seatIndex + 1 -- Increase seat index so each seat is filled from driver, to passenger, to rear passengers etc.

                    -- Network setup for pilot
                    local pedNetID = NetworkGetNetworkIdFromEntity(officer)
                    if Config.isDebug then print('NET ped ' ..pedModel .. ' spawned with pedNetID = ' ..pedNetID .. ' for vehNetID = ' .. vehNetID) end

                    -- Give pilot loadout
                    GiveWeaponToPed(pilot, GetHashKey('weapon_combatpistol'), 999, false, false)

                    -- Add pilot to table to return
                    table.insert(officers, pedNetID)

                    -- We spawned a ped into the vehicle, ensure vehicleCrewed is true.
                    vehicleCrewed = true
                end

            end

            if not vehicleCrewed then
                -- Should break the ped loop and move straight to deleting the vehicle. In my experience if the first one fails to warp they all will. 
                break 
            end


            

            --seatIndex = seatIndex + 1 -- Increase seat index so each seat is filled from driver, to passenger, to rear passengers etc.
        end

        if vehicleCrewed then 

            for _, pedModel in ipairs(selectedEntry.peds) do


                local pedHash = GetHashKey(pedModel)


                warpCount = 0
                pedInSeat = nil
                while (not pedInSeat or pedInSeat == 0) and warpCount < Config.warpWaitCount do

                    local officer = CreatePed(4, pedHash, spawnPoint.x+20, spawnPoint.y+20, spawnPoint.z, spawnHeading, true, true)
                    local waitCount = 0
                    while not DoesEntityExist(officer) and waitCount < Config.spawnWaitCount do
                        if Config.isDebug then print('Waiting to spawn officer...') end
                        officer = CreatePed(4, pedHash, spawnPoint.x+20, spawnPoint.y+20, spawnPoint.z, spawnHeading, true, true)
                        Wait(10)
                        waitCount = waitCount + 1
                    end
                    if not DoesEntityExist(officer) then
                        if Config.isDebug then print('Spawning '..pedModel.. ' failed.') end
                        return
                    end
                    SetEntityDistanceCullingRadius(officer, 10000.0)
                    Wait(50)
                    TaskWarpPedIntoVehicle(officer, vehicle, seatIndex)
                    Wait(50)
                    pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
                    local waitCount = 0
                    while (not pedInSeat or pedInSeat == 0) and waitCount < Config.spawnWaitCount do
                        -- Try warping them again
                        if Config.isDebug then print('Officer failed to warp into ' .. selectedEntry.unit.model .. ' vehNetID = ' .. vehNetID .. ' seat = ' .. seatIndex .. ' trying again ' .. waitCount) end
                        TaskWarpPedIntoVehicle(officer, vehicle, seatIndex)
                        Wait(20)
                        pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
                        waitCount = waitCount + 1
                    end

                    if (not pedInSeat or pedInSeat == 0) then
                        -- Delete the officer and start over with a fresh one until they warp into the vehicle properly.
                        if Config.isDebug then print('Officer failed to warp into ' .. selectedEntry.unit.model .. ' vehNetID = ' .. vehNetID .. ' too many times, deleting entity and starting over ') end
                        DeleteEntity(officer)
                        Wait(100)
                        warpCount = warpCount + 1
                    else
                        -- Put this here so if a ped fails to be warped in it will still fill the driver seat first.
                        seatIndex = seatIndex + 1 -- Increase seat index so each seat is filled from driver, to passenger, to rear passengers etc.

                        -- Network setup for officer
                        local pedNetID = NetworkGetNetworkIdFromEntity(officer)
                        if Config.isDebug then print('NET ped ' ..pedModel .. ' spawned with pedNetID = ' ..pedNetID .. ' for vehNetID = ' .. vehNetID) end

                        -- Give officer loadout
                        givePedLoadout(officer, Config.loadouts[selectedEntry.unit.loadout])

                        -- Add officer to table to return
                        table.insert(officers, pedNetID)

                        -- We spawned a ped into the vehicle, ensure vehicleCrewed is true.
                        vehicleCrewed = true

                    end

                end

                
                
                --seatIndex = seatIndex + 1 -- Increase seat index so each seat is filled from driver, to passenger, to rear passengers etc.
            end
        end

        if not vehicleCrewed then
            if Config.isDebug then print('Vehicle ' .. selectedEntry.unit.model .. ' failed to be crewed, deleting vehNetID = ' .. vehNetID .. ' and starting over ') end
            DeleteEntity(vehicle)
            vehNetID = nil
            Wait(100)
            -- Add 1 and try again
            hasDriverCount = hasDriverCount + 1   
        end
    end

    -- Return the netIDs to the client
    TriggerClientEvent('spawnPoliceHeliNetResponse', src, vehNetID, officers)
end)




-- AIR UNITS --
RegisterNetEvent('spawnPoliceAirNet')
AddEventHandler('spawnPoliceAirNet', function(wantedLevel, playerCoords, spawnPoint, spawnTable)
    local src = source
    local seatIndex = -1

    -- Variable will be set true as soon as a vehicle has a driver. I'm less worried about a crew member not warping in properly.
    local vehicleCrewed = false
    local hasDriverCount = 0
    local vehNetID = nil
    local officers = {}
    

    while (not vehicleCrewed) and hasDriverCount < Config.hasDriverWaitCount do

        vehNetID = nil

        -- Pick the vehicle to choose to spawn for this region, vehicle determines which peds spawn with it, and the peds determine combat behavior and weapons. 
        local selectedEntry = getRandomAirUnit(spawnTable, wantedLevel)
        if not selectedEntry then
            if Config.isDebug then print('No suitable air unit found for the given wanted level.') end
            return
        end
        local vehicleHash = GetHashKey(selectedEntry.unit.model)

        local vehicle = CreateVehicleServerSetter(vehicleHash, 'plane', spawnPoint.x, spawnPoint.y, spawnPoint.z, 0.0)
        local waitCount = 0 
        while not DoesEntityExist(vehicle) and waitCount < Config.spawnWaitCount do
            Wait(10)
            waitCount = waitCount + 1
        end
        if not DoesEntityExist(vehicle) then
            if Config.isDebug then print('Spawning '..selectedEntry.unit.model.. ' failed.') end
            return
        end
        vehNetID = NetworkGetNetworkIdFromEntity(vehicle)

        SetEntityDistanceCullingRadius(vehicle, 10000.0)
        

        officers = {}

        for _, pedModel in ipairs(selectedEntry.pilots) do


            local pedHash = GetHashKey(pedModel)


            local warpCount = 0
            local pedInSeat = nil
            while (not pedInSeat or pedInSeat == 0) and warpCount < Config.warpWaitCount do

                local officer = CreatePed(4, pedHash, spawnPoint.x+20, spawnPoint.y+20, spawnPoint.z, spawnHeading, true, true)
                local waitCount = 0
                while not DoesEntityExist(officer) and waitCount < Config.spawnWaitCount do
                    if Config.isDebug then print('Waiting to spawn officer...') end
                    officer = CreatePed(4, pedHash, spawnPoint.x+20, spawnPoint.y+20, spawnPoint.z, spawnHeading, true, true)
                    Wait(10)
                    waitCount = waitCount + 1
                end
                if not DoesEntityExist(officer) then
                    if Config.isDebug then print('Spawning '..pedModel.. ' failed.') end
                    return
                end
                SetEntityDistanceCullingRadius(officer, 10000.0)
                Wait(50)
                TaskWarpPedIntoVehicle(officer, vehicle, seatIndex)
                Wait(50)
                pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
                local waitCount = 0
                while (not pedInSeat or pedInSeat == 0) and waitCount < Config.spawnWaitCount do
                    -- Try warping them again
                    if Config.isDebug then print('Officer failed to warp into ' .. selectedEntry.unit.model .. ' vehNetID = ' .. vehNetID .. ' seat = ' .. seatIndex .. ' trying again ' .. waitCount) end
                    TaskWarpPedIntoVehicle(officer, vehicle, seatIndex)
                    Wait(20)
                    pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
                    waitCount = waitCount + 1
                end

                if (not pedInSeat or pedInSeat == 0) then
                    -- Delete the officer and start over with a fresh one until they warp into the vehicle properly.
                    if Config.isDebug then print('Officer failed to warp into ' .. selectedEntry.unit.model .. ' vehNetID = ' .. vehNetID .. ' too many times, deleting entity and starting over ') end
                    DeleteEntity(officer)
                    Wait(100)
                    warpCount = warpCount + 1
                else
                    -- Put this here so if a ped fails to be warped in it will still fill the driver seat first.
                    seatIndex = seatIndex + 1 -- Increase seat index so each seat is filled from driver, to passenger, to rear passengers etc.

                    -- Network setup for pilot
                    local pedNetID = NetworkGetNetworkIdFromEntity(officer)
                    if Config.isDebug then print('NET ped ' ..pedModel .. ' spawned with pedNetID = ' ..pedNetID .. ' for vehNetID = ' .. vehNetID) end

                    -- Give pilot loadout
                    GiveWeaponToPed(pilot, GetHashKey('weapon_combatpistol'), 999, false, false)

                    -- Add pilot to table to return
                    table.insert(officers, pedNetID)

                    -- We spawned a ped into the vehicle, ensure vehicleCrewed is true.
                    vehicleCrewed = true
                end

            end


            --seatIndex = seatIndex + 1 -- Increase seat index so each seat is filled from driver, to passenger, to rear passengers etc.

            
            

            if not vehicleCrewed then
                -- Should break the ped loop and move straight to deleting the vehicle. In my experience if the first one fails to warp they all will. 
                break 
            end

        end

        if not vehicleCrewed then
            if Config.isDebug then print('Vehicle ' .. selectedEntry.unit.model .. ' failed to be crewed, deleting vehNetID = ' .. vehNetID .. ' and starting over ') end
            DeleteEntity(vehicle)
            vehNetID = nil
            Wait(100)
            -- Add 1 and try again
            hasDriverCount = hasDriverCount + 1   
        end

    end

    -- Return the netIDs to the client
    TriggerClientEvent('spawnPoliceAirNetResponse', src, vehNetID, officers)
end)


--Added wanted levels for basic QB robbery etc

--used to get the players near an alert
function GetPlayersInRadius(centerCoords, radius)
    local playersInRadius = {}

    for _, playerId in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(playerId)
        local playerCoords = GetEntityCoords(ped)

        local dist = #(vector3(centerCoords.x, centerCoords.y, centerCoords.z) - playerCoords)
        if dist <= radius then
            table.insert(playersInRadius, playerId)
        end
    end

    return playersInRadius
end

--Used to round the location
function round(val, decimal)
    local power = 10 ^ (decimal or 0)
    return math.floor(val * power + 0.5) / power
end
--This function gets the wanted level from the coordinates in the config file - this way you can set a different wanted level based on the crime being commited
function GetWantedLevelFromCoords(alertCoords)
    local coords = vector3(
        round(alertCoords.x, 2),
        round(alertCoords.y, 2),
        round(alertCoords.z, 2)
    )   

    print("Corrodinates " .. coords)
    for index, location in pairs(Config.locations) do
        local locCoords = location[1]  -- correctly getting the vector3
    print("loccoords ".. locCoords)
        if locCoords then
            local distance = #(coords - locCoords)
            print(string.format("Checking location %d: distance = %.2f", index, distance))

            if distance < 20 then -- adjust this threshold as needed
                return location.wanted
            end
        else
            print("Warning: No coords found for location index " .. tostring(index))
        end
    end

    return nil
end

--Uesed to receive alerts from qbpolice trigger fuction
--Needs to be added to QB-Police police:server:policeAlert
RegisterNetEvent('fenix:server:trigger')
AddEventHandler('fenix:server:trigger', function(pdata,alertData)
    
    if alertData.coords then
        local wantedlevel = GetWantedLevelFromCoords({x = alertData.coords.x, y = alertData.coords.y, z = alertData.coords.z })
    
        if wantedlevel then
            print("Wanted Level for this location is " .. wantedlevel)
        else
            print("No wanted level for this locaiton found.. setting to 1")
            wantedlevel = 0
        end 

        print("getting nearbyplayers")
        local nearbyPlayers = GetPlayersInRadius({ x = alertData.coords.x, y = alertData.coords.y, z = alertData.coords.z }, 10.0)
        print("Nearby players: " .. json.encode(nearbyPlayers))   

        for _, playerId in ipairs(nearbyPlayers) do
            print("Player nearby: " .. tostring(playerId))
        
            -- You can get more info about the player
            local ped = GetPlayerPed(playerId)
            print("Player " .. playerId .. " triggered police, applying wanted level: " .. wantedlevel)
            TriggerClientEvent('fenix-police:client:SetWantedLevel', playerId, wantedlevel)
        end
    end  
end)