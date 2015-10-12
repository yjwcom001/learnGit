local HotReload = require "hotReload"

module(..., package.seeall)

watch = HotReload.watch

callback = function()
end

local light = 255
local dark  = 128
local text = [[
    hot reload please click OK button, 
    cold reload please click cancel button, 
    cancel please click the area out of Popup Window,
    thank you for your cooperation!!
]]

prototype = WindowPrompt.prototype:extend()

function prototype:enter()
    self.btnReload:registerControlEventHandler(bind(self.touchDown, self), cc.CONTROL_EVENTTYPE_TOUCH_DOWN)
    self.btnReload:registerControlEventHandler(bind(self.dragEnter, self), cc.CONTROL_EVENTTYPE_DRAG_ENTER)
    self.btnReload:registerControlEventHandler(bind(self.dragExit, self), cc.CONTROL_EVENTTYPE_DRAG_EXIT)
    self.btnReload:registerControlEventHandler(bind(self.upInside, self), cc.CONTROL_EVENTTYPE_TOUCH_UP_INSIDE)
    self.btnReload:registerControlEventHandler(bind(self.upOutside, self), cc.CONTROL_EVENTTYPE_TOUCH_UP_OUTSIDE)

    self.isStartInButton = false
    self.isInButton = false
    self.isMove = false

    local screenSize = self:getContentSize()
    local width = screenSize.width
    local height = screenSize.height

    local listener = function(event, x, y)
        if event == "began" then
            return true
        end
        if event == "moved" then
            if self.isStartInButton and not self.isInButton then
                self.isMove = true
                local pos = self.nodeReload:getParent():convertToNodeSpace(cc.p(x, y))
                pos.x = pos.x > width and width or pos.x
                pos.x = pos.x < 0 and 0 or pos.x
                pos.y = pos.y > height and height or pos.y
                pos.y = pos.y < 0 and 0 or pos.y
                self.nodeReload:setPosition(pos)
            end
        end
    end

    self.layReload:setTouchEnabled(true)
    self.layReload:registerScriptTouchHandler(listener)
    self.layReload:setSwallowsTouches(false)

    self.hotReload = HotReload.getHotReloadObject()
    Singleton(Timer):Repeat(200, self:Event("reload", function()
        self.hotReload:check(callback)  
    end))
end

function prototype:touchDown()
    self.isStartInButton = true
    self.isInButton = true
    self:setOpacity(true)
end

function prototype:setOpacity(isLight)
    local opacity = isLight and light or dark
    self.sprReload:setOpacity(opacity)
    self.labReload:setOpacity(opacity)
end

function prototype:dragEnter()
    if not self.isMove then
        self.isInButton = true
        self:setOpacity(true)
    end
end

function prototype:dragExit()
    self.isInButton = false
    self:setOpacity(false)
end

function prototype:upInside()
    local isMoved = self.isMove
    self:upOutside()
    self:setOpacity(false)
    -- 目前只有script文件夹下的Logic、Module、Stage、UI可以重载
    -- 修改local变量后重载不生效
    if not isMoved then
        self.hotReload:reloadModule(callback)

        --  local OK = function()
        --      self.hotReload:reloadModule(callback)
        --  end

        --  local CANCEL = function()
        --      cc.Director:getInstance():replaceScene(CCScene:create())
        --      CEnvRoot:GetSingleton():SetReloadAll()
        --  end

        --  Prompt:Confirm(text, nil, OK, CANCEL)
    end
end

function prototype:upOutside()
    self.isInButton = false
    self.isStartInButton = false
    self.isMove = false
end
