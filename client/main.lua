local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = {}
local PlayerGang = {}
local PlayerJob = {}
local OutsideVehicles = {}
local CurrentGarage = nil
local GaragePoly = {}
local MenuItemId1 = nil
local MenuItemId2 = nil
local VehicleClassMap = {}
local GarageZones = {}

-- helper functions

local function TableContains(tab, val)
    if type(val) == "table" then -- checks if atleast one the values in val is contained in tab
        for _, value in ipairs(tab) do
            if TableContains(val, value) then
                return true
            end
        end
        return false
    else
        for _, value in ipairs(tab) do
            if value == val then
                return true
            end
        end
    end
    return false
end

function TrackVehicleByPlate(plate)
    QBCore.Functions.TriggerCallback('lightning-garages:server:GetVehicleLocation', function(coords)
        SetNewWaypoint(coords.x, coords.y)
    end, plate)
end
exports("TrackVehicleByPlate", TrackVehicleByPlate)

local function IsStringNilOrEmpty(s)
    return s == nil or s == ''
end

local function GetSuperCategoryFromCategories(categories)
    local superCategory = 'car'
    if TableContains(categories, {'car'}) then
        superCategory = 'car'
    elseif TableContains(categories, {'plane', 'helicopter'}) then
        superCategory = 'air'
    elseif TableContains(categories, 'boat') then
        superCategory = 'sea'
    end
    return superCategory
end

local function GetClosestLocation(locations, loc)
    local closestDistance = -1
    local closestIndex = -1
    local closestLocation = nil
    local plyCoords = loc or GetEntityCoords(PlayerPedId(), 0)
    for i, v in ipairs(locations) do
        local location = vector3(v.x, v.y, v.z)
        local distance = #(plyCoords - location)
        if (closestDistance == -1 or closestDistance > distance) then
            closestDistance = distance
            closestIndex = i
            closestLocation = v
        end
    end
    return closestIndex, closestDistance, closestLocation
end

function SetAsMissionEntity(vehicle)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleIsStolen(vehicle, false)
    SetVehicleIsWanted(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')
    local id = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(id, true)
end

function GetVehicleByPlate(plate)
    local vehicles = QBCore.Functions.GetVehicles()
    for _, v in pairs(vehicles) do
        if QBCore.Functions.GetPlate(v) == plate then
            return v
        end
    end
    return nil
end


-- Menus
local function PublicGarage(garageName, type)
    local garage = Config.Garages[garageName]
    local categories = garage.vehicleCategories
    local superCategory = GetSuperCategoryFromCategories(categories)

    TriggerEvent("lightning-garages:client:GarageMenu", {
        garageId = garageName,
        garage = garage,
        categories = categories,
        header = Lang:t("menu.header." .. garage.type .. "_" .. superCategory, {
            value = garage.label
        }),
        superCategory = superCategory,
        type = type
    })
end



local function ClearMenu()
    TriggerEvent("qb-menu:closeMenu")
end

local function ApplyVehicleDamage(currentVehicle, veh)
    local engine = veh.engine + 0.0
    local body = veh.body + 0.0
    local damage = veh.damage
    if damage then
        if damage.tyres then
            for k, tyre in pairs(damage.tyres) do
                if tyre.onRim then
                    SetVehicleTyreBurst(currentVehicle, tonumber(k), tyre.onRim, 1000.0)
                elseif tyre.burst then
                    SetVehicleTyreBurst(currentVehicle, tonumber(k), tyre.onRim, 990.0)
                end
            end
        end
        if damage.windows then
            for k, window in pairs(damage.windows) do
                if window.smashed then
                    SmashVehicleWindow(currentVehicle, tonumber(k))
                end
            end
        end

        if damage.doors then
            for k, door in pairs(damage.doors) do
                if door.damaged then
                    SetVehicleDoorBroken(currentVehicle, tonumber(k), true)
                end
            end
        end
    end

    SetVehicleEngineHealth(currentVehicle, engine)
    SetVehicleBodyHealth(currentVehicle, body)
end

local function GetCarDamage(vehicle)
    local damage = {
        windows = {},
        tyres = {},
        doors = {}
    }
    local tyreIndexes = {0, 1, 2, 3, 4, 5, 45, 47}

    for _, i in pairs(tyreIndexes) do
        damage.tyres[i] = {
            burst = IsVehicleTyreBurst(vehicle, i, false) == 1,
            onRim = IsVehicleTyreBurst(vehicle, i, true) == 1,
            health = GetTyreHealth(vehicle, i)
        }
    end
    for i = 0, 7 do
        damage.windows[i] = {
            smashed = not IsVehicleWindowIntact(vehicle, i)
        }
    end
    for i = 0, 5 do
        damage.doors[i] = {
            damaged = IsVehicleDoorDamaged(vehicle, i)
        }
    end
    return damage
end

local function Round(num, numDecimalPlaces)
    return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end

local function ExitAndDeleteVehicle(vehicle)
    local garage = Config.Garages[CurrentGarage]
    local exitLocation = nil
    if garage and garage.ExitWarpLocations and next(garage.ExitWarpLocations) then
        _, _, exitLocation = GetClosestLocation(garage.ExitWarpLocations)
    end
    for i = -1, 5, 1 do
        local ped = GetPedInVehicleSeat(vehicle, i)
        if ped then
            TaskLeaveVehicle(ped, vehicle, 0)
            if exitLocation then
                SetEntityCoords(ped, exitLocation.x, exitLocation.y, exitLocation.z)
            end
        end
    end
    SetVehicleDoorsLocked(vehicle)
    local plate = GetVehicleNumberPlateText(vehicle)
    Wait(1500)
    QBCore.Functions.DeleteVehicle(vehicle)
    Wait(1000)
    TriggerServerEvent('lightning-garages:server:parkVehicle', plate)
end

local function GetVehicleCategoriesFromClass(class)
    return VehicleClassMap[class]
end

local function IsAuthorizedToAccessGarage(garageName)
    local garage = Config.Garages[garageName]
    if not garage then
        return false
    end
    if garage.type == 'job' then
        if type(garage.job) == "string" and not IsStringNilOrEmpty(garage.job) then
            return PlayerJob.name == garage.job
        elseif type(garage.job) == "table" then
            return TableContains(garage.job, PlayerJob.name)
        else
            QBCore.Functions.Notify('job not defined on garage', 'error', 7500)
            return false
        end
    elseif garage.type == 'gang' then
        if type(garage.gang) == "string" and not IsStringNilOrEmpty(garage.gang) then
            return garage.gang == PlayerGang.name
        elseif type(garage.gang) == "table" then
            return TableContains(garage.gang, PlayerGang.name)
        else
            QBCore.Functions.Notify('gang not defined on garage', 'error', 7500)
            return false
        end
    end
    return true
end

local function CanParkVehicle(veh, garageName, vehLocation)
    local garage = garageName and Config.Garages[garageName] or
                       (CurrentGarage and Config.Garages[CurrentGarage])
    if not garage then
        return false
    end
    local parkingDistance = garage.ParkingDistance and garage.ParkingDistance or Config.ParkingDistance
    local vehClass = GetVehicleClass(veh)
    local vehCategories = GetVehicleCategoriesFromClass(vehClass)

    if garage and garage.vehicleCategories and not TableContains(garage.vehicleCategories, vehCategories) then
        QBCore.Functions.Notify(Lang:t("error.not_correct_type"), "error", 4500)
        return false
    end

    local parkingSpots = garage.ParkingSpots and garage.ParkingSpots or {}
    if next(parkingSpots) then
        local _, closestDistance, closestLocation = GetClosestLocation(parkingSpots, vehLocation)
        if closestDistance >= parkingDistance then
            QBCore.Functions.Notify(Lang:t("error.too_far_away"), "error", 4500)
            return false
        else
            return true, closestLocation
        end
    else
        return true
    end
end

local function ParkOwnedVehicle(veh, garageName, vehLocation, plate)
    local bodyDamage = math.ceil(GetVehicleBodyHealth(veh))
    local engineDamage = math.ceil(GetVehicleEngineHealth(veh))

    local totalFuel = 0

    if Config.FuelScript then
        totalFuel = exports[Config.FuelScript]:GetFuel(veh)
    else
        totalFuel = exports['LegacyFuel']:GetFuel(veh) -- Don't change this. Change it in the  Defaults to legacy fuel if not set in the config
    end

    local canPark, closestLocation = CanParkVehicle(veh, garageName, vehLocation)
    local closestVec3 = closestLocation and vector3(closestLocation.x, closestLocation.y, closestLocation.z) or nil
    local garage = Config.Garages[garageName]
    if not canPark and not garage.useVehicleSpawner then
        return
    end

    local properties = QBCore.Functions.GetVehicleProperties(veh)
    if not properties then
        return
    end

    TriggerServerEvent('lightning-garage:server:updateVehicle', 1, totalFuel, engineDamage, bodyDamage, properties, plate,
        garageName, false and closestVec3 or nil)
    ExitAndDeleteVehicle(veh)
    if plate then
        OutsideVehicles[plate] = nil
        TriggerServerEvent('lightning-garages:server:UpdateOutsideVehicles', OutsideVehicles)
    end
    QBCore.Functions.Notify(Lang:t("success.vehicle_parked"), "success", 4500)
end

function ParkVehicleSpawnerVehicle(veh, garageName, vehLocation, plate)
    QBCore.Functions.TriggerCallback("lightning-garage:server:CheckSpawnedVehicle", function(result)
        local canPark, _ = CanParkVehicle(veh, garageName, vehLocation)
        if result and canPark then
            TriggerServerEvent("lightning-garage:server:UpdateSpawnedVehicle", plate, nil)
            ExitAndDeleteVehicle(veh)
        elseif not result then
            QBCore.Functions.Notify(Lang:t("error.not_owned"), "error", 3500)
        end
    end, plate)
end

local function ParkVehicle(veh, garageName, vehLocation)
    local plate = QBCore.Functions.GetPlate(veh)
    local garageName = garageName or (CurrentGarage)
    local garage = Config.Garages[garageName]
    local type = garage and garage.type
    local gang = PlayerGang.name;
    local job = PlayerJob.name;
    QBCore.Functions.TriggerCallback('lightning-garage:server:checkOwnership', function(owned)
        if owned then
            ParkOwnedVehicle(veh, garageName, vehLocation, plate)
        elseif garage and garage.useVehicleSpawner and IsAuthorizedToAccessGarage(garageName) then
            ParkVehicleSpawnerVehicle(veh, vehLocation, vehLocation, plate)
        else
            QBCore.Functions.Notify(Lang:t("error.not_owned"), "error", 3500)
        end
    end, plate, type, garageName, gang)
end


local function CreateGarageZone()
    local combo = ComboZone:Create(GarageZones, {
        name = 'garages',
        debugPoly = false
    })
    combo:onPlayerInOut(function(isPointInside, l, zone)
        if isPointInside and IsAuthorizedToAccessGarage(zone.name) then
            CurrentGarage = zone.name
            exports["lightning-interaction"]:showInteraction('E', Config.Garages[CurrentGarage]['drawText'])
            
        else
            CurrentGarage = nil
            exports["lightning-interaction"]:hideInteraction()

        end
    end)
end

local function CreateGaragePolyZone(garage)
    local zone = PolyZone:Create(Config.Garages[garage].Zone.Shape, {
        name = garage,
        minZ = Config.Garages[garage].Zone.minZ,
        maxZ = Config.Garages[garage].Zone.maxZ,
        debugPoly = Config.Garages[garage].debug
    })
    GarageZones[#GarageZones + 1] = zone
    -- CreateGarageZone(zone, garage)
end




function GetFreeParkingSpots(parkingSpots)
    local freeParkingSpots = {}
    for _, parkingSpot in ipairs(parkingSpots) do
        local veh, distance = QBCore.Functions.GetClosestVehicle(vector3(parkingSpot.x, parkingSpot.y, parkingSpot.z))
        if veh == -1 or distance >= 1.5 then
            freeParkingSpots[#freeParkingSpots + 1] = parkingSpot
        end
    end
    return freeParkingSpots
end

function GetFreeSingleParkingSpot(freeParkingSpots, vehicle)
    local checkAt = nil
    if vehicle and vehicle.parkingspot then
        checkAt = vector3(vehicle.parkingspot.x, vehicle.parkingspot.y, vehicle.parkingspot.z) or nil
    end
    local _, _, location = GetClosestLocation(freeParkingSpots, checkAt)
    return location
end

function GetSpawnLocationAndHeading(garage, garageType, parkingSpots, vehicle, spawnDistance)
    local location
    local heading
    local closestDistance = -1

    if garageType == "house" then
        location = garage.takeVehicle
        heading = garage.takeVehicle.w 
    else
        if next(parkingSpots) then
            local freeParkingSpots = GetFreeParkingSpots(parkingSpots)
            if Config.AllowSpawningFromAnywhere then
                location = GetFreeSingleParkingSpot(freeParkingSpots, vehicle)
                if location == nil then
                    QBCore.Functions.Notify(Lang:t("error.all_occupied"), "error", 4500)
                    return
                end
                heading = location.w
            else
                _, closestDistance, location = GetClosestLocation(
                    Config.ParkingSpotSystem and freeParkingSpots or parkingSpots)
                local plyCoords = GetEntityCoords(PlayerPedId(), 0)
                local spot = vector3(location.x, location.y, location.z)
                if vehicle and vehicle.parkingspot then
                    spot = vehicle.parkingspot
                end
                local dist = #(plyCoords - vector3(spot.x, spot.y, spot.z))
                if  dist >= spawnDistance then
                    QBCore.Functions.Notify(Lang:t("error.too_far_away"), "error", 4500)
                    return
                elseif closestDistance >= spawnDistance then
                    QBCore.Functions.Notify(Lang:t("error.too_far_away"), "error", 4500)
                    return
                else
                    local veh, distance = QBCore.Functions
                                              .GetClosestVehicle(vector3(location.x, location.y, location.z))
                    if veh ~= -1 and distance <= 1.5 then
                        QBCore.Functions.Notify(Lang:t("error.occupied"), "error", 4500)
                        return
                    end
                    heading = location.w
                end
            end
        else
            local ped = GetEntityCoords(PlayerPedId())
            local pedheadin = GetEntityHeading(PlayerPedId())
            local forward = GetEntityForwardVector(PlayerPedId())
            local x, y, z = table.unpack(ped + forward * 3)
            location = vector3(x, y, z)
            heading = pedheadin + 90
        end
    end
    return location, heading
end

local function UpdateVehicleSpawnerSpawnedVehicle(veh, garage, heading, vehicleConf, cb)
    local plate = QBCore.Functions.GetPlate(veh)
    if Config.FuelScript then
        exports[Config.FuelScript]:SetFuel(veh, 100)
    else
        exports['LegacyFuel']:SetFuel(veh, 100) -- Don't change this. Change it in the  Defaults to legacy fuel if not set in the config
    end
    TriggerEvent("vehiclekeys:client:SetOwner", plate)
    TriggerServerEvent("lightning-garage:server:UpdateSpawnedVehicle", plate, true)

    ClearMenu()
    SetEntityHeading(veh, heading)

    if vehicleConf then
        if vehicleConf.extras then
            QBCore.Shared.SetDefaultVehicleExtras(veh, vehicleConf.extras)
        end
        if vehicleConf.livery then
            SetVehicleLivery(veh, vehicleConf.livery)
        end
    end

    if garage.WarpPlayerIntoVehicle or Config.WarpPlayerIntoVehicle and garage.WarpPlayerIntoVehicle == nil then
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end

    SetAsMissionEntity(veh)
    SetVehicleEngineOn(veh, true, true)

    if cb then
        cb(veh)
    end
end

local function SpawnVehicleSpawnerVehicle(vehicleModel, vehicleConfig, location, heading, cb)
    local garage = Config.Garages[CurrentGarage]
    local jobGrade = QBCore.Functions.GetPlayerData().job.grade.level

    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        UpdateVehicleSpawnerSpawnedVehicle(veh, garage, heading, vehicleConfig, cb)
    end, vehicleModel, location, garage.WarpPlayerIntoVehicle or Config.WarpPlayerIntoVehicle and
        garage.WarpPlayerIntoVehicle == nil)
end

function UpdateSpawnedVehicle(spawnedVehicle, vehicleInfo, heading, garage, properties)
    local plate = vehicleInfo.plate or QBCore.Functions.GetPlate(spawnedVehicle)

    if garage.useVehicleSpawner then
        ClearMenu()
        if plate then
            OutsideVehicles[plate] = spawnedVehicle
            TriggerServerEvent('lightning-garages:server:UpdateOutsideVehicles', OutsideVehicles)
        end
        if Config.FuelScript then
            exports[Config.FuelScript]:SetFuel(spawnedVehicle, 100)
        else
            exports['LegacyFuel']:SetFuel(spawnedVehicle, 100) -- Don't change this. Change it in the  Defaults to legacy fuel if not set in the config
        end
        TriggerEvent("vehiclekeys:client:SetOwner", plate)
        TriggerServerEvent("lightning-garage:server:UpdateSpawnedVehicle", plate, true)
    else
        if plate then
            OutsideVehicles[plate] = spawnedVehicle
            TriggerServerEvent('lightning-garages:server:UpdateOutsideVehicles', OutsideVehicles)
        end
        if Config.FuelScript then
            exports[Config.FuelScript]:SetFuel(spawnedVehicle, vehicleInfo.fuel)
        else
            exports['LegacyFuel']:SetFuel(spawnedVehicle, vehicleInfo.fuel) -- Don't change this. Change it in the  Defaults to legacy fuel if not set in the config
        end

        NetworkRequestControlOfEntity(spawnedVehicle)
        ApplyVehicleDamage(spawnedVehicle, vehicleInfo)
        SetAsMissionEntity(spawnedVehicle)

        while (NetworkGetEntityOwner(spawnedVehicle) ~= NetworkPlayerIdToInt()) do
            Wait(0)
        end

        TriggerServerEvent('lightning-garage:server:updateVehicleState', 0, vehicleInfo.plate, vehicleInfo.garage)
        TriggerEvent("vehiclekeys:client:SetOwner", vehicleInfo.plate)

        QBCore.Functions.SetVehicleProperties(spawnedVehicle, properties or {})

    end
    SetEntityHeading(spawnedVehicle, heading)
    SetAsMissionEntity(spawnedVehicle)
    if SpawnWithEngineRunning then
        SetVehicleEngineOn(veh, true, true)
    end
end

-- Events

RegisterNetEvent("lightning-garages:client:GarageMenu", function(data)
    local type = data.type
    local garageId = data.garageId
    local garage = data.garage
    local categories = data.categories and data.categories or {'car'}
    local header = data.header
    local superCategory = data.superCategory
    local leave

    leave = Lang:t("menu.leave." .. superCategory)

    local vehiclesTable = {} 

    QBCore.Functions.TriggerCallback("lightning-garage:server:GetGarageVehicles", function(result)
        if result == nil then
            QBCore.Functions.Notify(Lang:t("error.no_vehicles"), "error", 5000)
        else
            result = result and result or {}
            for k, v in pairs(result) do
                local enginePercent = Round(v.engine / 10, 0)
                local bodyPercent = Round(v.body / 10, 0)
                local currentFuel = v.fuel
                local vehData = QBCore.Shared.Vehicles[v.vehicle]
                local vname = 'Vehicle does not exist'
                if vehData then
                    local vehCategories = GetVehicleCategoriesFromClass(GetVehicleClassFromName(v.vehicle))
                    if garage and garage.vehicleCategories and
                        not TableContains(garage.vehicleCategories, vehCategories) then
                        goto skipVehicle
                    end
                    vname = vehData.name
                end

                if v.state == 0 then
                    v.state = Lang:t("status.out")
                elseif v.state == 1 then
                    v.state = Lang:t("status.garaged")
                elseif v.state == 2 then
                    v.state = Lang:t("status.impound")
                end

                vehiclesTable[#vehiclesTable + 1] = {
                    name = vname,
                    plate = v.plate,
                    state = v.state,
                    fuel = currentFuel,
                    enginePercent = enginePercent,
                    bodyPercent = bodyPercent,
                    vehicleModel = v.vehicle,
                    garageData = json.encode(garage),
                    superCategoryData = json.encode(superCategory),
                    type = type,
                    vehicle = v,
                    
                }

                ::skipVehicle::
            end

            SendNUIMessage({
                action = "garaj",
                garajIsmi = garage.label, 
                araclar = vehiclesTable
            })
            SetNuiFocus(true, true)
        end
    end, garageId, type, superCategory)
end)

RegisterNUICallback('AracCikart', function(data, cb)
    local aracData = data.aracData

    if type(aracData) == "string" then
        aracData = json.decode(aracData)
    end

    if aracData then
        TriggerEvent('lightning-garages:client:TakeOutGarage', aracData)
    else
        print("[LightningDev] Garage Error - AracCikart/838")
    end
    cb('ok')
end)

RegisterNetEvent('lightning-garages:client:TakeOutGarage', function(data, cb)
    local garageType = data.type
    local vehicleModel = data.vehicleModel
    local vehicleConfig = data.vehicleConfig
    local vehicle = data.vehicle
    local garage = data.garage
    local spawnDistance = 20.0
    local parkingSpots = garage.ParkingSpots or {}

    local location, heading = GetSpawnLocationAndHeading(garage, garageType, parkingSpots, vehicle, spawnDistance)
    if garage.useVehicleSpawner then
        SpawnVehicleSpawnerVehicle(vehicleModel, vehicleConfig, location, heading, cb)
    else
        QBCore.Functions.TriggerCallback('lightning-garage:server:spawnvehicle', function(netId, properties)
            while not NetworkDoesNetworkIdExist(netId) do Wait(10) end
            local veh = NetworkGetEntityFromNetworkId(netId)
            UpdateSpawnedVehicle(veh, vehicle, heading, garage, properties)
            if cb then
                cb(veh)
            end
        end, vehicle, location, heading, garage.WarpPlayerIntoVehicle or Config.WarpPlayerIntoVehicle and
            garage.WarpPlayerIntoVehicle == nil)
    end
end)

function CheckPlate(vehicle, plateToSet)
    local vehiclePlate = promise.new()
    CreateThread(function()
        while true do
            Wait(500)
            if GetVehicleNumberPlateText(vehicle) == plateToSet then
                vehiclePlate:resolve(true)
                return
            else
                SetVehicleNumberPlateText(vehicle, plateToSet)
            end
        end
    end)
    return vehiclePlate
end

-- Credits to esx_core and txAdmin for the list.
local mismatchedTypes = {
    [`airtug`] = "automobile", -- trailer
    [`avisa`] = "submarine", -- boat
    [`blimp`] = "heli", -- plane
    [`blimp2`] = "heli", -- plane
    [`blimp3`] = "heli", -- plane
    [`caddy`] = "automobile", -- trailer
    [`caddy2`] = "automobile", -- trailer
    [`caddy3`] = "automobile", -- trailer
    [`chimera`] = "automobile", -- bike
    [`docktug`] = "automobile", -- trailer
    [`forklift`] = "automobile", -- trailer
    [`kosatka`] = "submarine", -- boat
    [`mower`] = "automobile", -- trailer
    [`policeb`] = "bike", -- automobile
    [`ripley`] = "automobile", -- trailer
    [`rrocket`] = "automobile", -- bike
    [`sadler`] = "automobile", -- trailer
    [`sadler2`] = "automobile", -- trailer
    [`scrap`] = "automobile", -- trailer
    [`slamtruck`] = "automobile", -- trailer
    [`Stryder`] = "automobile", -- bike
    [`submersible`] = "submarine", -- boat
    [`submersible2`] = "submarine", -- boat
    [`thruster`] = "heli", -- automobile
    [`towtruck`] = "automobile", -- trailer
    [`towtruck2`] = "automobile", -- trailer
    [`tractor`] = "automobile", -- trailer
    [`tractor2`] = "automobile", -- trailer
    [`tractor3`] = "automobile", -- trailer
    [`trailersmall2`] = "trailer", -- automobile
    [`utillitruck`] = "automobile", -- trailer
    [`utillitruck2`] = "automobile", -- trailer
    [`utillitruck3`] = "automobile", -- trailer
}

function GetVehicleTypeFromModelOrHash(model)
    model = type(model) == "string" and joaat(model) or model
    if not IsModelInCdimage(model) then
        return
    end
    if mismatchedTypes[model] then
        return mismatchedTypes[model]
    end

    local vehicleType = GetVehicleClassFromName(model)
    local types = {
        [8] = "bike",
        [11] = "trailer",
        [13] = "bike",
        [14] = "boat",
        [15] = "heli",
        [16] = "plane",
        [21] = "train",
    }

    return types[vehicleType] or "automobile"
end

QBCore.Functions.CreateClientCallback('lightning-garages:client:GetVehicleType', function(cb, model)
    cb(GetVehicleTypeFromModelOrHash(model));
end)



RegisterNetEvent('lightning-garages:client:OpenMenu', function()
    local garage = Config.Garages[CurrentGarage]
    local garageType = garage.type
    PublicGarage(CurrentGarage, garageType)
end)

RegisterNetEvent('lightning-garages:client:ParkVehicle', function()
    local ped = PlayerPedId()
    local canPark = true
    local curVeh = GetVehiclePedIsIn(ped)

    local closestVeh, dist = QBCore.Functions.GetClosestVehicle()
    if dist <= 20.0 then
        curVeh = closestVeh
    end

    Wait(200)

    if not curVeh or not DoesEntityExist(curVeh) then
        return
    end

    if curVeh ~= 0 and canPark then
        ParkVehicle(curVeh)
    end
end)

RegisterNetEvent('lightning-garages:client:ParkLastVehicle', function(parkingName)
    local ped = PlayerPedId()
    local curVeh = GetLastDrivenVehicle(ped)
    if curVeh then
        local coords = GetEntityCoords(curVeh)
        ParkVehicle(curVeh, parkingName or CurrentGarage, coords)
    else
        QBCore.Functions.Notify(Lang:t('error.no_vehicle'), "error", 4500)
    end
end)

RegisterNetEvent('lightning-garages:client:TakeOutDepot', function(data)
    local vehicle = data.vehicle
    -- check whether the vehicle is already spawned
    local vehExists = false
    if not vehExists then
        local PlayerData = QBCore.Functions.GetPlayerData()
        if PlayerData.money['cash'] >= vehicle.depotprice or PlayerData.money['bank'] >= vehicle.depotprice then
            TriggerEvent("lightning-garages:client:TakeOutGarage", data, function(veh)
                if veh then
                    TriggerServerEvent("lightning-garage:server:PayDepotPrice", data)
                end
            end)
        else
            QBCore.Functions.Notify(Lang:t('error.not_enough'), "error", 5000)
        end
    else
        QBCore.Functions.Notify(Lang:t('error.not_impound'), "error", 5000)
    end
end)




AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData then
        return
    end
    PlayerGang = PlayerData.gang
    PlayerJob = PlayerData.job
    QBCore.Functions.TriggerCallback('lightning-garage:server:GetOutsideVehicles', function(outsideVehicles)
        OutsideVehicles = outsideVehicles
    end)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() and QBCore.Functions.GetPlayerData() ~= {} then
        PlayerData = QBCore.Functions.GetPlayerData()
        if not PlayerData then
            return
        end
        PlayerGang = PlayerData.gang
        PlayerJob = PlayerData.job
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, v in pairs(GarageZones) do
            exports['qb-target']:RemoveZone(v.name)
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    PlayerGang = gang
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerJob = job
end)

-- Threads

CreateThread(function()
    for _, garage in pairs(Config.Garages) do
        if garage.showBlip then
            CreateBlipForGarage(garage)
        end
    end
end)

function CreateBlipForClosestGarage(closestCoords)
    local blip = AddBlipForCoord(closestCoords)
    SetBlipSprite(blip, 357)
    SetBlipScale(blip, 0.6)
    SetBlipColour(blip, 3)
    SetBlipDisplay(blip, 4)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(closestName)
    EndTextCommandSetBlipName(blip)
    return blip
end

function CreateBlipForGarage(garage)
	local blip = AddBlipForCoord(garage.blipcoords.x, garage.blipcoords.y, garage.blipcoords.z)
    local blipColor = garage.blipColor ~= nil and garage.blipColor or 3
    SetBlipSprite(blip, garage.blipNumber)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.60)
    SetBlipAsShortRange(blip, true)
    SetBlipColour(blip, blipColor)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(garage.label)
    EndTextCommandSetBlipName(blip)
	return blip
end

CreateThread(function()
    for garageName, garage in pairs(Config.Garages) do
        if (garage.type == 'public' or garage.type == 'depot' or garage.type == 'job' or garage.type == 'gang') then
            CreateGaragePolyZone(garageName)
        end
    end
    CreateGarageZone()
end)

CreateThread(function()
    local debug = false
    for _, garage in pairs(Config.Garages) do
        if garage.debug then
            debug = true
            break
        end
    end
    while debug do
        for _, garage in pairs(Config.Garages) do
            local parkingSpots = garage.ParkingSpots and garage.ParkingSpots or {}
            if next(parkingSpots) ~= nil and garage.debug then
                for _, location in pairs(parkingSpots) do
                    DrawMarker(2, location.x, location.y, location.z + 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4,
                        0.2, 255, 255, 255, 255, 0, 0, 0, 1, 0, 0, 0)
                end
            end
        end
        Wait(0)
    end
end)

function IsPointInPoly(point, poly)
    local intersections = 0
    for i = 1, #poly do
        local v1 = poly[i]
        local v2 = poly[i % #poly + 1]

        if ((v1.y > point.y) ~= (v2.y > point.y)) and
            (point.x < (v2.x - v1.x) * (point.y - v1.y) / (v2.y - v1.y) + v1.x) then
            intersections = intersections + 1
        end
    end
    return (intersections % 2) == 1
end

function IsPlayerInGarage()
    local playerCoords = GetEntityCoords(PlayerPedId())

    for garageName, garageData in pairs(Config.Garages) do
        local shape = garageData.Zone.Shape
        local minZ = garageData.Zone.minZ
        local maxZ = garageData.Zone.maxZ

        if IsPointInPoly(vector2(playerCoords.x, playerCoords.y), shape) and
            playerCoords.z >= minZ and playerCoords.z <= maxZ then
            return garageName, garageData.type -- Garaj ismi ve tipi döndürülüyor
        end
    end

    return nil, nil
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if IsControlJustReleased(0, 38) then
            local playerPed = PlayerPedId()
            local garageName, garageType = IsPlayerInGarage()

            if garageName then
                if IsPedInAnyVehicle(playerPed, false) then
                    TriggerEvent("lightning-garages:client:ParkVehicle")
                else
                    PublicGarage(garageName, garageType)
                end
            end
        end
    end
end)

CreateThread(function()
    for category, classes in pairs(Config.VehicleCategories) do
        for _, class in pairs(classes) do
            VehicleClassMap[class] = VehicleClassMap[class] or {}
            VehicleClassMap[class][#VehicleClassMap[class] + 1] = category
        end
    end
end)

RegisterNUICallback('menuKapat', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)