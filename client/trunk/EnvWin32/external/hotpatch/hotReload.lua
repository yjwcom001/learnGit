require "lfs"
require "list"

module(..., package.seeall)

local pl = {}
pl.dir = require "pl.dir"
pl.path = require "pl.path"

local symol = "/" --not windows symol
local dirNames = {
    "Logic",
    "Module",
    "Stage",
    "UI",
}

local isReload = {}

local filesInfo = {}
local needReload = {}
local reloadInfo = {}
local moduleInfo = {}
local notNeedReload = {}

local printInfo = nil
local isInitFileInfo = false
local notInReloadAreaText = [[
    %s is not within the scope of reload area,
    please try again later!!!!!
]]
local successText = "Reload: Succeed!"

function initFileInfo()
    if isInitFileInfo then
        return
    end
    isInitFileInfo = true
    local osType = string.upper(os.getenv("OS") or "")
    local isWindows = string.find(osType, "WINDOWS", 1)
    symol = isWindows and "\\" or symol
    
    local filesPath = {}
    for _, dirName in ipairs(dirNames) do
        local dirPath = "script"..symol..dirName
        local dirFilesPath = pl.dir.getallfiles(dirPath, "*.lua")
        filesPath = list.concat(filesPath, dirFilesPath)
    end

    for _, filePath in ipairs(filesPath) do
        filesInfo[filePath] = pl.path.getmtime(filePath)
        local moduleLastName = pl.path.splitext(pl.path.basename(filePath))
        needReload[moduleLastName] = true
    end

    getReloadModule()
end

local checkModule = {}
function watch(moduleName)
    initFileInfo()
    moduleInfo[moduleName] = moduleInfo[moduleName] or findFilePath(moduleName, true)
    if checkModule[moduleName] == nil and moduleInfo[moduleName] ~= nil then
        scanAndRecordFile(moduleName)
    end
end

function findFilePath(moduleName, isWatch)
    local modulePath = string.gsub(moduleName, "%.", symol)..".lua"
    for key in pairs(filesInfo) do
        local matchresult = string.find(key, modulePath, 1)
        if matchresult ~= nil then
            return key
        end
    end
    if notNeedReload[moduleName] == nil and isWatch then
        notNeedReload[moduleName] = true
        printInfo(string.format(notInReloadAreaText, moduleName))
    end
end

function check(callback)
    getReloadModule()
    isReload = {}
    local isModified = false
    for moduleName in pairs(checkModule) do
        local msg = scanAndRecordFile(moduleName, true)
        if msg == true then
            isModified = true
        elseif msg == "remove" then
            reload(moduleName)
        end
    end
    if isModified then
        for moduleName in pairs(checkModule) do
            reload(moduleName)
        end
    end
    if table.size(isReload) > 0 then
        printInfo(successText)
        callback()
    end
end

local reloadMark = "%-%- reload %-%-"
local watchMark = 'require%([\"\']Reload[\"\']%)%.watch%(%.%.%.%)'
function scanAndRecordFile(moduleName, isCheck)
    local modulePath = moduleInfo[moduleName]
    local file = io.open(modulePath, "r")
    local count = 0
    if file then
        local content = file:read("*all")
        file:close()

        for _ in string.gmatch(content, reloadMark) do
            count = count + 1
        end
        if checkModule[moduleName] == nil then
            checkModule[moduleName] = count
        end
        if isCheck then
            local isWatch = string.find(content, watchMark, 1)
            if isWatch == nil then
                filesInfo[modulePath] = pl.path.getmtime(modulePath)
                checkModule[moduleName] = nil
                return "remove"
            end
        end

        if count ~= checkModule[moduleName] then
            filesInfo[modulePath] = pl.path.getmtime(modulePath)
            checkModule[moduleName] = count
            return true
        end
    end
    return false
end

function reloadModule(callback)
    getReloadModule()
    isReload = {}
    for key, value in pairs(moduleInfo) do
        if isModifyFile(value) then
            reload(key)
        end
    end
    local text = table.size(isReload) > 0 and successText or "Reload: No modification"
    printInfo(text)
    if table.size(isReload) > 0 then
        callback()
    end
end

function getReloadModule()
    local moduleNames = {}
    for key, value in pairs(package.loaded) do
        if isReloadFile(key) and type(value) == "table" then
            table.insert(moduleNames, key)
        end
    end
    
    markModuleName(moduleNames)
end

function isReloadFile(moduleName)
    local modulePath = string.gsub(moduleName, "%.", symol)
    local moduleLastName = pl.path.basename(modulePath)
    if needReload[moduleLastName] and moduleInfo[moduleName] == nil then
        return true
    end
    return false
end

function markModuleName(moduleNames)
    for _, moduleName in ipairs(moduleNames) do
        if moduleInfo[moduleName] == nil then
            moduleInfo[moduleName] = findFilePath(moduleName)
        end
    end
end

function isModifyFile(path)
    local newMTime = pl.path.getmtime(path)
    if newMTime == filesInfo[path] then
        return false
    end
    filesInfo[path] = newMTime
    return true
end

function reload(moduleName)
    if isReload[moduleName] then
        return
    end
    isReload[moduleName] = moduleName

    local G, index = getG(moduleName)
    local oldModule = rawget(G, index)
    local tostring = _G._tostring

    if oldModule == nil then
        return
    end

    local name = rawget(oldModule, "_NAME")
    local superclass = rawget(oldModule, "superclass")
    local __prototype__ = rawget(oldModule, "__prototype__")
    if name == nil or superclass ~= nil or __prototype__ ~= nil then
        -- 1.require C++库
        -- 2.底层代码
        -- 3.服务器接口代码
        return
    end

    local myPrototype = getPrototype(oldModule)
    if myPrototype == nil then
        return
    end

    package.loaded[moduleName] = nil
    local mPackage = oldModule._PACKAGE
    if mPackage ~= nil and mPackage ~= "" then
        mPackage = string.sub(mPackage, 1, -2)
        if moduleInfo[mPackage] then
            reload(mPackage)
        end
    end

    rawset(G, index, nil)
    local result, newModule = pcall(require, moduleName)
    if not result then
        package.loaded[moduleName] = oldModule
        rawset(G, index, oldModule)
        return
    end

    reloadPrototype(oldModule, newModule, myPrototype)
    updateContent(oldModule, newModule, myPrototype)
    
    rawset(G, index, oldModule)
    G[index]._M = G[index]
    package.loaded[moduleName] = G[index]

    reloadSubclass(oldModule)
end

function getG(moduleName)
    local tempG = _G
    local result = string.split(moduleName, ".")
    if #result == 1 then
        return tempG, moduleName
    end
    
    for idx, keyWord in ipairs(result) do
        if idx == #result then
            return tempG, keyWord
        end
        tempG = rawget(tempG, keyWord)
    end
end

function getPrototype(oldModule)
    local tempClass = rawget(oldModule, "class")
    local tempPrototype = rawget(oldModule, "prototype")
    if tempClass ~= nil then
        return "class"
    elseif tempPrototype ~= nil then
        return "prototype"
    end
    return nil
end

function reloadPrototype(oldModule, newModule, myPrototype)
    local oldPrototype = oldModule[myPrototype]
    local newPrototype = newModule[myPrototype]

    if not oldPrototype.__prototype__ or not newPrototype.__prototype__ then
        return
    end

    for key in pairs(oldPrototype.__prototype__) do
        if key ~= "__index" and key ~= "__metatable" then
            local newValue = rawget(newPrototype.__prototype__, key)
            rawset(oldPrototype.__prototype__, key, newValue)
        end
    end

    for key in pairs(newPrototype.__prototype__) do
        if key ~= "__index" and key ~= "__metatable" then
            local newValue = rawget(newPrototype.__prototype__, key)
            rawset(oldPrototype.__prototype__, key, newValue)
        end
    end
end

function updateContent(oldModule, newModule, myPrototype)
    local moduleName = oldModule._NAME

    for key, value in pairs(oldModule) do
        local keyWord = moduleName.."."..key
        if key ~= myPrototype and not isNeedRequire(keyWord) and key ~= "_M" then
            if type(value) == "table" then
                reloadTable(oldModule[key], newModule[key])
            elseif oldModule[key] ~= newModule[key] then
                if moduleName ~= "Reload" or type(value) ~= "function" then
                    oldModule[key] = newModule[key]
                end
            end
        end
    end

    for key, value in pairs(newModule) do
        local keyWord = moduleName.."."..key
        if key ~= myPrototype and not isNeedRequire(keyWord) and key ~= "_M" then
            if type(value) == "table" then
                reloadTable(oldModule[key], newModule[key])
            elseif oldModule[key] ~= newModule[key] then
                oldModule[key] = newModule[key]
            end
        end
    end
end

function isNeedRequire(keyWord)
    for key in pairs(moduleInfo) do
        local s = string.find(key, keyWord, 1)
        if s ~= nil then
            return true
        end
    end
    return false
end

function reloadTable(oldTable, newTable)
    for key in pairs(oldTable) do
        if oldTable[key] ~= newTable[key] then
            oldTable[key] = newTable[key]
        end
    end

    for key in pairs(newTable) do
        if oldTable[key] ~= newTable[key] then
            oldTable[key] = newTable[key]
        end
    end
end

function reloadSubclass(oldModule)
    local moduleName = oldModule._NAME
    for key in pairs(oldModule) do
        local keyWord = moduleName.."."..key
        if moduleInfo[keyWord] then
            reload(keyWord)
        end
    end
end

function setPrintInfoFunc(func)
    printInfo = func
end
