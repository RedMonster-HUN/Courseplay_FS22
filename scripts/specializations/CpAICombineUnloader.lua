--- Specialization for unloading a combine on the field.
local modName = CpAICombineUnloader and CpAICombineUnloader.MOD_NAME -- for reload

---@class CpAICombineUnloader
CpAICombineUnloader = {}

CpAICombineUnloader.startText = g_i18n:getText("CP_jobParameters_startAt_unload")

CpAICombineUnloader.MOD_NAME = g_currentModName or modName
CpAICombineUnloader.NAME = ".cpAICombineUnloader"
CpAICombineUnloader.SPEC_NAME = CpAICombineUnloader.MOD_NAME .. CpAICombineUnloader.NAME
CpAICombineUnloader.KEY = "."..CpAICombineUnloader.MOD_NAME..CpAICombineUnloader.NAME

function CpAICombineUnloader.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAICombineUnloader.KEY
    CpJobParameters.registerXmlSchema(schema, key..".cpJob")
    CpJobParameters.registerXmlSchema(schema, key..".cpJobStartAtLastWp")
end

function CpAICombineUnloader.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpAICombineUnloader.register(typeManager,typeName,specializations)
	if CpAICombineUnloader.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAICombineUnloader.SPEC_NAME)
	end
end

function CpAICombineUnloader.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAICombineUnloader)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAICombineUnloader)
end

function CpAICombineUnloader.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "startCpCombineUnloader", CpAICombineUnloader.startCpCombineUnloader)
    SpecializationUtil.registerFunction(vehicleType, "startCpCombineUnloaderUnloading", CpAICombineUnloader.startCpCombineUnloaderUnloading)

    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpCombineUnloader", CpAICombineUnloader.getCanStartCpCombineUnloader)
    SpecializationUtil.registerFunction(vehicleType, "getCpCombineUnloaderJobParameters", CpAICombineUnloader.getCpCombineUnloaderJobParameters)

    SpecializationUtil.registerFunction(vehicleType, "applyCpCombineUnloaderJobParameters", CpAICombineUnloader.applyCpCombineUnloaderJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpCombineUnloaderJob", CpAICombineUnloader.getCpCombineUnloaderJob)
end

function CpAICombineUnloader.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAICombineUnloader.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob', CpAICombineUnloader.getCpStartableJob)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartText', CpAICombineUnloader.getCpStartText)

    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtFirstWp', CpAICombineUnloader.startCpAtFirstWp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtLastWp', CpAICombineUnloader.startCpAtLastWp)
end
------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAICombineUnloader:onLoad(savegame)
	--- Register the spec: spec_cpAICombineUnloader
    self.spec_cpAICombineUnloader = self["spec_" .. CpAICombineUnloader.SPEC_NAME]
    local spec = self.spec_cpAICombineUnloader
    --- This job is for starting the driving with a key bind or the mini gui.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.COMBINE_UNLOADER_CP)
    spec.cpJob:setVehicle(self)
    spec.cpJobStartAtLastWp = g_currentMission.aiJobTypeManager:createJob(AIJobType.COMBINE_UNLOADER_CP)
end

function CpAICombineUnloader:onLoadFinished(savegame)
    local spec = self.spec_cpAICombineUnloader
    if savegame ~= nil then 
        spec.cpJob:loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAICombineUnloader.KEY..".cpJob")
        spec.cpJobStartAtLastWp:getCpJobParameters():loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIFieldWorker.KEY..".cpJobStartAtLastWp")
    end
end

function CpAICombineUnloader:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAICombineUnloader
    spec.cpJob:saveToXMLFile(xmlFile, baseKey.. ".cpJob")
    spec.cpJobStartAtLastWp:getCpJobParameters():saveToXMLFile(xmlFile, baseKey.. ".cpJobStartAtLastWp")
end

function CpAICombineUnloader:getCpCombineUnloaderJobParameters()
    local spec = self.spec_cpAICombineUnloader
    return spec.cpJob:getCpJobParameters() 
end

function CpAICombineUnloader:getCpDriveStrategy(superFunc)
    return superFunc(self) or self.spec_cpAICombineUnloader.driveStrategy
end

--- If we have a trailer which can be emptied, we can unload a combine
function CpAICombineUnloader:getCanStartCpCombineUnloader()
	return not self:getCanStartCpFieldWork() and AIUtil.getNumberOfChildVehiclesWithSpecialization(self, Trailer) == 1
end

function CpAICombineUnloader:getCanStartCp(superFunc)
    return superFunc(self) or self:getCanStartCpCombineUnloader() and not self:getIsCpCourseRecorderActive()
end

function CpAICombineUnloader:getCpStartableJob(superFunc)
    local spec = self.spec_cpAICombineUnloader
    return superFunc(self) or self:getCanStartCpCombineUnloader() and spec.cpJob
end

function CpAICombineUnloader:getCpStartText(superFunc)
	local text = superFunc and superFunc(self)
	return text~="" and text or self:getCanStartCpCombineUnloader() and CpAICombineUnloader.startText
end


--- Starts the cp driver at the first waypoint.
function CpAICombineUnloader:startCpAtFirstWp(superFunc)
    if not superFunc(self) then 
        if self:getCanStartCpCombineUnloader() then
            local spec = self.spec_cpAICombineUnloader
            spec.cpJob:applyCurrentState(self, g_currentMission, g_currentMission.player.farmId, true)
            spec.cpJob:setValues()
            local success = spec.cpJob:validate(false)
            if success then
                g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJob, self:getOwnerFarmId()))
                return true
            end
        end
    else 
        return true
    end
end

--- Starts the cp driver at the last driven waypoint.
function CpAICombineUnloader:startCpAtLastWp(superFunc)
    if not superFunc(self) then 
        if self:getCanStartCpCombineUnloader() then
            local spec = self.spec_cpAICombineUnloader
            spec.cpJob:applyCurrentState(self, g_currentMission, g_currentMission.player.farmId, true)
            spec.cpJob:setValues()
            local success = spec.cpJob:validate(false)
            if success then
                g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJob, self:getOwnerFarmId()))
                return true
            end
        end
    else 
        return true
    end
end

--- Custom version of AIFieldWorker:startFieldWorker()
function CpAICombineUnloader:startCpCombineUnloader(fieldPolygon, jobParameters)
    --- Calls the giants startFieldWorker function.
    self:startFieldWorker()
    if self.isServer then 
        --- Replaces drive strategies.
        CpAICombineUnloader.replaceDriveStrategies(self, fieldPolygon, jobParameters)
    end
end

-- We replace the Giants AIDriveStrategyStraight with our AIDriveStrategyFieldWorkCourse to take care of
-- field work.
function CpAICombineUnloader:replaceDriveStrategies(fieldPolygon, jobParameters)
    CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'This is a CP combine unload job, start the CP AI driver, setting up drive strategies...')
    local spec = self.spec_aiFieldWorker
    if spec.driveStrategies ~= nil then
        for i = #spec.driveStrategies, 1, -1 do
            spec.driveStrategies[i]:delete()
            table.remove(spec.driveStrategies, i)
        end
        spec.driveStrategies = {}
    end
	CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Combine unload job, install CP drive strategy for it')
    local cpDriveStrategy = AIDriveStrategyUnloadCombine.new()
    cpDriveStrategy:setFieldPolygon(fieldPolygon)
    cpDriveStrategy:setJobParameterValues(jobParameters)
    CpUtil.try(cpDriveStrategy.setAIVehicle, cpDriveStrategy, self)
    self.spec_cpAIFieldWorker.driveStrategy = cpDriveStrategy
    --- TODO: Correctly implement this strategy.
	local driveStrategyCollision = AIDriveStrategyCollision.new(cpDriveStrategy)
    driveStrategyCollision:setAIVehicle(self)
    table.insert(spec.driveStrategies, driveStrategyCollision)
    --- Only the last driving strategy can stop the helper, while it is running.
    table.insert(spec.driveStrategies, cpDriveStrategy)
end

--- Forces the driver to unload now.
function CpAICombineUnloader:startCpCombineUnloaderUnloading()
    CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Drive unload now requested')
    local strategy = self:getCpDriveStrategy()
    if strategy then 
        strategy:requestDriveUnloadNow()
    end
end

function CpAICombineUnloader:applyCpCombineUnloaderJobParameters(job)
    local spec = self.spec_cpAICombineUnloader
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

function CpAICombineUnloader:getCpCombineUnloaderJob()
    local spec = self.spec_cpAICombineUnloader
    return spec.cpJob
end
