require "Logic"

local Manager       = require "CTB.Manager"
local ManagerManual = require "CTB.Manager.Manual"
local ManagerAuto   = require "CTB.Manager.Auto"
local ManagerEdit   = require "CTB.Manager.Edit"

----------------------------------------------
local FIGHTER_TYPE = TypeDef("com.eyu.ahxy.module.fight.service.config.FighterType")

local VALUES = TypeDef("com.eyu.ahxy.module.fight.model.UnitValue")
local VALUES_CODE = Enum(VALUES)

local DEGREES = TypeDef("com.eyu.ahxy.module.fight.model.UnitDegree")
local DEGREES_CODE = Enum(DEGREES)

local RATES = TypeDef("com.eyu.ahxy.module.fight.model.UnitRate")
local RATES_CODE = Enum(RATES)

local RESULTS = TypeDef("com.eyu.ahxy.module.fight.model.BattleResult")
local BATTLE_RESULTS = Enum(RESULTS)

----------------------------------------------

module(..., package.seeall)

EVT = Enum
{
	"START", --战斗开始
	"END_WAVE",
	"NEXT_WAVE",
	"NEXT_RELEIF", --援军进场
	"FINISH", -- 战斗结束

	"UPDATE_SKILL", --技能改变
	"INIT_SKILL", --技能初始化
	"LOCK_SKILL",--战斗中
	"ALTER_MP",--改变MP
	"ALTER_HP",
	"ALTER_ROUND",--回合结束
	"ALTER_BOSS",
	"ALTER_DROP",
	"SHOW_TOOLBAR",
	"USE_SKILL",--触发技能

	"ALTER_QTE",--qte状态改变
	"ENABLE_QTE",
	"RESULT_QTE",--完成qte
	"UI_ENTER", -- mNodeUpper     
}

class = Logic.class:subclass()

function class:initialize()
	super.initialize(self)

    -- todo fight test @lhx
    MsgFight:On("LOG_REPORT", self:Event("OnLogReport"))
end

---- todo fight test @lhx
function class:setLogReport(logReport)
    self.logReport = logReport
end

function class:sendReport()
    local params = {
        clientReport = json.encode(self.logReport.clientReport),
        num = self.logReport.num,
        seed = self.logReport.seed,
        skill = json.encode(self.logReport.skill),
    }
    MsgFight:Post("LOG_REPORT", params)
end

function class:OnLogReport(code)
    self.logReport = nil
end

--------- end --------------

local OPEN_DEBUG = false
local EDIT_MODE = false
-----------------------------------------------------
-- public
function class:enterEdit(skillId, mSkillId, model, conductData)
	local battleInfo = require "CTB.BattleInfoForEdit"

	self.battleInfo = json.decode(battleInfo)
	self:setBattleType("Edit")
	self:setMoveType("Non")

	local params = 
	{
		skillId = skillId, 
		mSkillId = mSkillId,
		data = conductData, 
		model = model,
	}
	self:enter("Edit", params)
end

function class:enterView(btlType, battleInfo, drops)
	-- test
	if (OPEN_DEBUG or EDIT_MODE) then
		-- local battleInfo = require "CTB.BattleInfoForEdit"
		-- self.battleInfo = json.decode(battleInfo)
		local battleInfo = json.decode(Manager.ReadReport("battleInfo.txt"))
		self:setBattleInfo(battleInfo, true)
	else
		self:setBattleInfo(battleInfo)
	end

	self:setBattleType(btlType)
	self:setDrops(drops)
	
	self:enter("Manual")
end

function class:enterShow(parent, modelId, skillId, battleType, extra)
	self:closeView()
	self.bInBattleState = true

	local battleInfo = require "CTB.BattleInfoForShow"
	self.battleInfo = battleInfo(battleType or 'ATTACK_ONE', extra or {}) -- json.decode(battleInfo[7])
	self:setBattleType("Show")

	local params = 
	{
		skillId = skillId, 
		modelId = modelId,
	}

	self:setBattleBg("images/public/clarity80.png")
	self:setMoveType("Non")
	local scence = Tw.BaseAni:load("CTBShow", parent)

	local manager = require ("CTB.Manager.Show")
	self.battle = manager.class:new(self, scence.mStage, scence.rootNode, params)
	self:getBattle():getSkill():setTimeout(0.5)
	self.battle:start()

	scence:setName("_CTBManagerShowView_")
	self.battleShowViewParent = parent

	scence:registerScriptHandler(function(event)
		if event == "cleanup" then
			self.battleShowViewParent = nil
			self:quit()
		end
	end)
end

function class:closeView()
	self.bInBattleState = false
	if self.battle == nil then
		return
	end

	if self.battle:getIsInShowMode() and self.battleShowViewParent then
		self.battleShowViewParent:removeChildByName("_CTBManagerShowView_")
		self.battleShowViewParent = nil
	else 
		SceneHelper:close("CTB")
		self:showMain()
		local isMusicClose = (1 ~= Singleton(ComLogic):GetSysVar("CLOSE_MUSIC"))
		if isMusicClose then
			Logic:Get("BGSound"):PlayBGMusic()
		end
	end

	self:quit()
end

-- json格式的战报无需进行类型转换
function class:enterViewAuto(btlType, report, drops, jsonFormat)
	self:setBattleType(btlType)
	self:setBattleInfo(report.battleInfo, jsonFormat)
	self:setRounds(report.rounds, jsonFormat)
	self:setInitAction(report.inits)
	self:setDrops(drops)
	
	self:enter("Auto")
end

function class:enter(type, params)
	Logic:Get("Performance"):clearAllPerformance()
	local auto = ("Auto" == type)
	local manager = require ("CTB.Manager." .. type)

	local scence = SceneHelper:open("CTB")
	scence:setAnimatCallback(function()
		if auto then scence:setAutoMode() end
		self:start()
	end, "Out")

	scence:setAnimatCallback(function()
		scence:runAnimations("Out")
		self:hideMain()
		scence.mBtnAuto:setEnabled(not auto)
		self.battle = manager.class:new(self, self:getStageNode(), self:getRootNode(), params)
		if not (OPEN_DEBUG or EDIT_MODE) and IsDevDevice() then
			json.encode_sparse_array(true)
			Manager.SaveReport(json.encode(self.battleInfo), "battleInfo.txt")
		end
        scence:onBtnSpeed()
	end, "Deep")
	scence:runAnimations("Deep")

	local isMusicClose = (1 ~= Singleton(ComLogic):GetSysVar("CLOSE_MUSIC"))
	if isMusicClose then
		Logic:Get("BGSound"):PlayBattleMusic()
	end

	self.bInBattleState = true
	return scence
end

function class:setMainUI(data)
	self.mainUI = {}

	for k, v in pairs(data or {}) do
		table.insert(self.mainUI, {layer = v})
	end
end

function class:hideMain()
	for k, v in pairs(self.mainUI or {}) do
		v.orgiVisible = v.layer:isVisible() 
		v.layer:setVisible(false)
	end
end

function class:showMain()
	for _, v in pairs(self.mainUI or {}) do
		v.layer:setVisible(v.orgiVisible ~= false)
	end
end

function class:isEditMode()
	return EDIT_MODE
end

function class:isDebugMode()
	return OPEN_DEBUG
end

function class:isTest()
	return EDIT_MODE or OPEN_DEBUG
end

function class:gotoNextWave(battleInfo, drops)
	log4battle:debug("[CTB] Next Wave")

	-- json.encode_sparse_array(true)
	if battleInfo == nil then
		return
	end

	self:setBattleInfo(battleInfo)
	self:setDrops(drops)

	self:FireEvent(EVT.NEXT_WAVE)
	self.battle:gotoNextWave()
end

function class:finish(win)
	self:showMain()
	self:EventTracer():Cancel("TIMER_FINFISH")

	Logic:Get("BGSound"):StopBattleMusic()
	if win then 
		 Logic:Get("BGSound"):PlayEffect('audio/sound/other/battle_win.mp3')
	else
		 Logic:Get("BGSound"):PlayEffect('audio/sound/other/battle_fail.mp3')
	end

	Singleton(Timer):After(1000, self:Event("TIMER_FINFISH", function()
		if self.battle ~= nil then
			self.battle:setFinishState(true)
		end
		log4battle:debug("[CTB] FINFISH BATTLE: result: " .. tostring(win))
		self:FireEvent(EVT.FINISH, win)

	end))
end

function class:setBattleBg(strImg)
	self.battleBg = strImg
end

function class:getBattleBg()
	return self.battleBg
end

function class:getBattle()
	return self.battle
end

-- identification of the battle type
function class:getBattleType()
	return self.battleType
end

function class:getCurrentBattleId()
	return self.currentBattleId
end

function class:setCurrentBattleId(id)
	self.currentBattleId = id
end

-- inner type in battleInfo
function class:getCurrentBattleType()
	return self.currentBattleType
end
------------------------------------------------------
-- private
function class:start()
	Logic:Get("Guide"):SetFightData("state","start")
	Logic:Get("Guide"):SetFightData("round",1)
	self:FireEvent(EVT.START)
	self:setupSkillTimer()
	self.battle:start()
end

function class:pause()
	self.battle:pause()
end

function class:resume()
	self.battle:resume()
end

function class:quit()
	if self.battle ~= nil then
		self.battle:dispose()
	end
	
	self.battleInfo      = nil
	self.battleRounds    = nil
	self.initAction      = nil
	self.battleMoveType  = nil
	self.battleBg        = nil
	self.battle          = nil
	self.qteInfo         = nil
	self.waveEndCallBack = nil
    self.deadNum         = nil
	self.syncCallback    = nil
	self.damageCCB       = nil
	self.timeoutCCB		 = nil
	self.battleTimeout   = nil
	self.newSkillId      = nil
	self.infoCallback    = nil
	self.damage          = nil
	self.popupMsg        = nil
    self.currEnemyNum    = nil
    self.instanceType    = nil
    self.maxRound        = nil

    self.showAttackerEquipState = nil
    self.showDefenderEquipState = nil
end

function class:setSpeed(speed)
	self.battle:setSpeed(speed)
end

function class:setStageNode(node)
	self.stageNode = node
end

function class:getStageNode()
	assert(self.stageNode ~= nil)
	return self.stageNode
end

function class:setRootNode(node)
	self.rootNode = node
end

function class:getRootNode()
	assert(self.rootNode ~= nil)
	return self.rootNode
end

function class:setWaveEndCallBack(func)
    self.waveEndCallBack = func
end

function class:getWaveEndCallBack()
    return self.waveEndCallBack
end

function class:setMaxRound(maxRound)
    self.maxRound = maxRound
end

function class:getMaxRound()
    return self.maxRound
end

function class:setDeadNum(deadNum)
    deadNum = deadNum ~= 0 and deadNum or nil
    self.deadNum = deadNum
end

function class:getDeadNum()
    return self.deadNum
end

function class:setSyncCallBack(func)
    self.syncCallback = func
end

function class:getSyncCallBack()
    return self.syncCallback
end

function class:setDamageCCB(damageCCB)
    self.damageCCB = damageCCB
end

function class:statisticsDamage(value)
    if self.damageCCB == nil or value > 0 then
        return
    end

    local initValue = self.damage or 0
    local toValue =  initValue + math.abs(value)

    self.damageCCB:stopAllActions()
    local seq = AniHelper:valueTimeAction(initValue, toValue, 0.5, function(num)
    	self.damageCCB:setString(num)
    end)
    self.damageCCB:runAction(seq)
    
    self.damageCCB:runAction(AniHelper:createSequence
    {
    	cc.EaseOut:create(cc.ScaleTo:create(0.1, 2), 3),
    	cc.DelayTime:create(1),
    	cc.ScaleTo:create(0.1, 1),
    })

    self.damage = toValue
end

function class:setBattleTimeout(t)
	if (t == nil) or (t <= 0) then
		return
	end

	local time = Singleton(ComLogic):DiffTime(t / 1000)
	if time > 0 then
		self.battleTimeout = time
	end
end

function class:getBattleTimeout(t)
	return self.battleTimeout
end

function class:setTimeoutCCB(timeoutCCB)
    self.timeoutCCB = timeoutCCB
end

function class:statisticsTimeout(value)
	if self.timeoutCCB == nil or value < 0 then
		return
	end

	value = math.modf(value)
	if value <= 60 then
		self.timeoutCCB:setTextColor(cc.c4b(255,0,0,255))
	else
		self.timeoutCCB:setTextColor(cc.c4b(187,255,0,255))
	end

	local time = Singleton(ComLogic):SecToDay(value)
	local str = string.format("%02d:%02d", time.min, time.sec)
	self.timeoutCCB:setString(str)
end

function class:setPopupMsg(info)
	self.popupMsg = info
end

function class:getPopupMsg()
	return self.popupMsg
end

function class:showEquipState(showAttacker, showDefender)
	self.showAttackerEquipState = showAttacker
	self.showDefenderEquipState = showDefender
end

function class:isShowAttackerEquipState()
	return self.showAttackerEquipState or false
end

function class:isShowDefenderEquipState()
	return self.showDefenderEquipState or false
end
----------------------------------------
-- event
function class:updateSkill(info)
	if self:getBattle() then 
		Logic:Get("Guide"):SetFightData("isFighting",self:getBattle():isFighting())
	end
	
	local skillSelect = {}
	local skillresult = {}
	for i = 1,#info do 
		skillSelect[info[i].active.fdb.id] = info[i].select
		skillresult[info[i].active.fdb.id] = info[i].result

		if info[i].select then 
			self.skillTipSeleId = info[i].active.fdb.id
		end
	end

	Logic:Get("Guide"):SetFightData("skillSelect",skillSelect)
	Logic:Get("Guide"):SetFightData("skillresult",skillresult)

	--Logic:Get("Guide"):GuideResume()
	Logic:Get("Guide"):check()

	self:FireEvent(EVT.UPDATE_SKILL, info)
end

function class:initSkill(info)
	Logic:Get("Guide"):SetFightData("STA_SKILL","INIT_SKILL")
	self:FireEvent(EVT.INIT_SKILL, info)
end

function class:lockSkillControl(st)
	-- Logic:Get("Guide"):SetFightData("lockSkill",st)
	if not self:isTest() then
		-- Logic:Get("Guide"):check()
	end
	self:FireEvent(EVT.LOCK_SKILL, st)
end

function class:alterMp(mp, maxMp, bInit)
	self:FireEvent(EVT.ALTER_MP, mp, maxMp, bInit)
end

function class:alterHp(hp, maxHp, isAlive)
	self:FireEvent(EVT.ALTER_HP, hp, maxHp, isAlive)
end

function class:alterRound(round, deadCount)
	Logic:Get("Guide"):SetFightData("round",round)
	Logic:Get("Guide"):check()

	if self.skillTipSeleId then 
		Logic:Get("Guide"):isSkillTip(self.skillTipSeleId)
	end

	self.skillTipSeleId = nil
	self:FireEvent(EVT.ALTER_ROUND, round, deadCount)
end

function class:alterRelief(...)
	self:FireEvent(EVT.NEXT_RELEIF, ...)
end

function class:alterBoss(model, hp, hpMax, first)
	self:FireEvent(EVT.ALTER_BOSS, model, hp, hpMax, first)
end

function class:alterQTE(msg)
	if msg.enable then 
		SceneHelper:close('SkillTip')
		Logic:Get("Guide"):SetFightData("alterQTE",msg.enable)
		Logic:Get("Guide"):check()
	end

	self:FireEvent(EVT.ALTER_QTE, msg)
end

function class:showToolBar(visible, callback)
	self:FireEvent(EVT.SHOW_TOOLBAR, visible, callback)
end

function class:useSkill(id)
	Logic:Get("Guide"):SetSkillId(id,true)
	Logic:Get("Guide"):GuideResume()
	Logic:Get("Guide"):check()
	
	self:FireEvent(EVT.USE_SKILL, id)
end

function class:enableQTE(b)
	self:FireEvent(EVT.ENABLE_QTE, b)
end

function class:notifyQTEResult(b)
	Logic:Get("Guide"):SetFightData("RESULT_QTE",b)
	self:FireEvent(EVT.RESULT_QTE, b)
end

function class:alterDrop(itemInfo)
	self:FireEvent(EVT.ALTER_DROP, itemInfo)
end

function class:notifyUIEnter(ctb)
	self:FireEvent(EVT.UI_ENTER, ctb)
end

function class:setupSkillTimer()
	local battleType = self:getCurrentBattleType()
	if battleType == nil then
		return
	end

	local roundTimeOut = 20
	local info = KFDBGetRecord("BattleSetting", battleType)
	if info ~= nil then
		roundTimeOut = info.roundTimeOut or 20
	end
	
	self:getBattle():getSkill():setTimeout(roundTimeOut)
end
----------------------------------------

function class:setDrops(drop)
	log4battle:debug("[CTB] setDrops")
	self.drops = drop or {}
end

function class:getDrops()
	return self.drops
end

function class:getDropPos()
	return self.dropsPos
end

function class:setDropPos(pos)
	self.dropsPos = pos
end

function class:setBattleType(type)
	self.battleType = type
end

function class:endWave(win, controlList, result, isTimeout)
	log4battle:debug("[CTB] endWave battleType: %s", self.battleType)
	log4battle:debug(function()
		return "{" .. table.concat(controlList, ",") .. "}"
	end)
	
	self.bInBattleState = false

	self:EventTracer():Cancel("TIMER_ENDWAVE")
	Singleton(Timer):After(1000, self:Event("TIMER_ENDWAVE", function()
		self:FireEvent(EVT.END_WAVE, win, controlList, RESULTS[result], isTimeout)
		if OPEN_DEBUG then
			self.battle:gotoNextWave()
		end
	end))
end

function class:setLastWave(st)
	self.lastWave = st
end

function class:isLastWave()
	return self.lastWave
end

function class:setBattleInfo(battleInfo, jsonFormat)
	if not jsonFormat then
		self:formatReport(battleInfo)
	end

	self.battleInfo = battleInfo
	self.currentBattleType = battleInfo.type
	self:setBattleTimeout(battleInfo.timeout)
end

function class:getBattleInfo()
	return self.battleInfo
end

-- "Attack, Defend, Tie, Non"
function class:setMoveType(strType)
	self.battleMoveType = strType
end

function class:getMoveType()
	return self.battleMoveType or "Defend"
end

function class:setRounds(rounds, jsonFormat)
	self.battleRounds = rounds
	self.jsonFormat = jsonFormat
end

function class:setInitAction(actions)
	self.initAction = actions
end

function class:getInitAction()
	return self.initAction
end

function class:getRounds()
	return self.battleRounds, self.jsonFormat
end

function class:setQteInfo(qteInfo)
    self.qteInfo = json.decode(qteInfo)
end

function class:getQteInfo()
    if OPEN_DEBUG or EDIT_MODE then
        return self.qteInfo or {count = 10, time = 100, skill = "bigSkill:Test004", qtepower = 60}
    end
    return self.qteInfo
end

function class:setInstanceType(type)
    self.instanceType = type
end

function class:isShowEnemyNum()
    local enemyNum = #self.battleInfo.defender.allUnit - 1
    return enemyNum > 0
end

local CTBValues = require"CTB.Simulator.Unit.CTBValues"
local UnitType = CTBValues.UnitType

function class:getEnemyInfo()
    if self.instanceType == "ANABASIS" then
        return self:getWarEnemyInfo()
    end

    return self:getInstanceEnemyInfo()
end

local unitModel = {
    true,
    true,
}

function class:getWarEnemyInfo()
    local allUnit = self.battleInfo.defender.allUnit
    local enemyInfo = {}
    
    for _, grounp in ipairs(allUnit) do
        local hasMajor = false
        for _, units in ipairs(grounp) do
            for _, unit in ipairs(units) do
                local model = unit.model.model
                if unitModel[model] then
                    hasMajor = true
                    table.insert(enemyInfo, model)
                    break
                end
            end
            if hasMajor then
                break
            end
        end
        if not hasMajor then
            assert(false, "war battle not hasMajor")
        end
    end

    return enemyInfo
end

function class:getInstanceEnemyInfo()
    local allUnit = self.battleInfo.defender.allUnit
    local enemyInfo = {}
    for _, grounp in ipairs(allUnit) do
        local isBoss = false
        for _, units in ipairs(grounp) do
            for _, unit in pairs(units) do
                if unit.model.type == UnitType.BOSS then
                    isBoss = true
                    table.insert(enemyInfo, "boss")
                    break
                end
            end
            if isBoss then
                break
            end
        end
        if not isBoss then
            table.insert(enemyInfo, "normal")
        end
    end
    return enemyInfo
end

function class:getEnemyNum()
    return #self.battleInfo.defender.allUnit
end

function class:setCurEnemyNum(enemyNum)
    if self.currEnemyNum ~= nil and self.currEnemyNum > enemyNum then
        return
    end
    self.currEnemyNum = enemyNum
end

function class:getCurEnemyNum()
    return self.currEnemyNum
end

--{hp = 0, anger = 0}
function class:setRecoverInfo(info)
	self.recoverInfo = info
end

function class:getRecoverInfo()
	return self.recoverInfo
end

function class:setNewSkillId(id)
	self.newSkillId = id
end

function class:getNewSkillId()
	return self.newSkillId
end

function class:setInfoCallback(callback)
	self.infoCallback = callback
end

function class:getInfoCallback()
	return self.infoCallback
end

---------------------------------------------------------
--

function class:formatReport(battleInfo)
	self:formatTeam(battleInfo.attacker.allUnit)
	self:formatTeam(battleInfo.defender.allUnit)
	-- self:formatBattleType(battleInfo)
	battleInfo.inits = battleInfo.inits or {}
end

function class:formatTeam(team)
	for _, grounp in pairs(team) do
		for r, units in pairs(grounp) do
			for c, unit in pairs(units) do
				self:formatUnit(unit)
			end
		end
	end
end

function class:formatUnit(unit)
	if unit == json.null then
		return
	end

	self:formatValues(unit.rates, RATES_CODE)
	self:formatValues(unit.degrees, DEGREES_CODE)
	self:formatValues(unit.values, VALUES_CODE)
end

function class:formatValues(values, t)
	local tmp = table.clone(values)
	for k, v in pairs(tmp) do
		k = tonumber(k)
		values[k] = nil
		if v ~= json.null then
			assert(t[k], "Error: can not find the enum:" .. k)
			values[t[k]] = v
		end   
	end
end

function class:formatBattleType(info)
	info.type = BATTLE_CODES[info.type]
end

function class:formatBattleResult(round)
	local code = tonumber(round.battleResult)
	if code == nil then
		return
	end
	round.battleResult = BATTLE_RESULTS[code]
end

function class:formatRound(round)
	local formatCallUnit = nil
	formatCallUnit = function(t)
		for k, v in pairs(t) do 
			if k == "units" then
				for _, unit in pairs(v) do 
					self:formatUnit(unit)
				end
			elseif type(v) == "table" then
				formatCallUnit(v)
			end
		end
	end

	formatCallUnit(round)
	self:formatBattleResult(round)
end
