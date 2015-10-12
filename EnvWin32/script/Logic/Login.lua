module(..., package.seeall)

EVT = Enum
{
	'LOGIN_COMPLETE',  		-- 登录完成
	'SHOW_ROLE',  		-- 查看本账号战队
	'BIND_SUC',  		-- 登录完成
}

local MSG_RET = TypeDef(MsgAccount.prefix .. '.account.facade.AccountResult')
local Armature = require "Tw.Armature"
class = Logic.class:subclass()

function class:initialize()
	super.initialize(self)
	self.isCreateRole = false
	self.patchPassEvent = self:Event('OnPatchPass')
	
	MsgSystem:On('REQUEST_DESCRIPTION', self:Event('OnDescription'))
	MsgSystem:On('MD5_DESCRIPTION', self:Event('OnMd5Description'))
	-- MsgSystem:On('RESOURCE_MD5', self:Event('OnResourceMd5'))

	MsgAccount:On('CHECK_ACCOUNT', self:Event('OnCheckAccount'))
	MsgAccount:On('CREATE', self:Event('OnCreateRole'), false)
	MsgAccount:On('LOGIN', self:Event('OnLogin'))
	MsgAccount:On('LOGIN_INFO', self:Event('OnLoginInfo'))

	--Logic:Get('Formation'):On(Logic.Formation.EVT.EMBATTLE, self:Event('OnLoadArmature'))
end

--@login step1
function class:Login()
	log4login:info({a_step = 'check autopatch'})
	NetMgr:getSingleton():SetSessionID(nil)

	Singleton(AutoPatch):On(AutoPatch.EVT.CHECK_PASS, self.patchPassEvent)
	Singleton(AutoPatch):Check()
end

function class:OnPatchPass()
	Singleton(AutoPatch):Off(AutoPatch.EVT.CHECK_PASS, self.patchPassEvent)
	
	local server = Singleton(Server):GetServer()
	log4login:info({a_step = 'connect server', server = server})
	NetMgr:getSingleton():Disconnect()
	NetMgr:getSingleton():Connect(server.addr, server.port, true)
	
	self:CheckDescrition()
end

function class:CheckDescrition()
	local server = Singleton(Server):GetServer()
	if server.queryDescribe then
		log4login:info({a_step = 'request describe'})
		MsgSystem:Post('REQUEST_DESCRIPTION')
	else
		log4login:info({a_step = 'check describe'})
		MsgSystem:Post('MD5_DESCRIPTION')
	end
end

function class:OnMd5Description(code, data)
	if nil == code or 0 ~= code or nil == data then
		self:OnPromptConfirmRetry('获取消息描述协议MD5码失败')
		return
	end

	local md5 = CMd5('db/describe.dat', true):GetResult()
	if string.upper(md5) ~= string.upper(data) then
		self:OnPromptConfirmRetry('消息描述协议MD5码不正确')
		return
	end

	self:OnDescription(0)
end

function class:GetAccountStr()
	--useId.运营商id_服id
	return string.format('%s.%s_%s', Singleton(Account):Get('userId'), 
						 			 Singleton(Account):Get('operatorId'), 
									 Singleton(Server):GetSelect() ) 
end

--@login step2
function class:OnDescription(code, data)
    do return self:CheckAccount() end

	log4login:info({a_step = 'check Resource md5'})
	MsgSystem:Post("RESOURCE_MD5")
end

function class:OnResourceMd5(code, data)
	local serverMd5 = data
	local file = "db/MD5KEY.dat"
	local keyStr = CTwFilePack.Open("db/MD5KEY.dat")
	if nil == keyStr or #keyStr == 0 then
		self:OnPromptConfirmRetry('MD5文件读取错误！')
		return
	end

	local keyTb = json.decode(keyStr)
	if nil == keyTb then
		self:OnPromptConfirmRetry("MD5文件读取错误！")
		return
	end

	for k, v in pairs(serverMd5) do
	    local mKey = string.gsub(k, "/", "\\")
	    if not keyTb[mKey] 
            or not (keyTb[mKey] == v 
            or keyTb[mKey] == string.lower(v)) then
	        Prompt:Confirm("战斗数值与服务端不匹配, 是否继续进入, <font color='#FF0000' size='36'>后果自负!!!</font>\n"..mKey, 
	            nil, bind(self.CheckAccount, self))
	        return
	    end
	end

    self:CheckAccount()	
end

--@login step3
function class:CheckAccount()
	local accountStr = self:GetAccountStr()
	log4login:info({a_step = 'check account', account = accountStr})
	MsgAccount:Post('CHECK_ACCOUNT', { account	= accountStr })
end

function class:OnCheckAccount(code, data)
	if data == false then  --创建角色
		SceneHelper:open("CreateRole")
		return 
	end

	self:PostLogin()
end

function class:GetServerDeviceType()
	local device = TypeDef(MsgAccount.prefix .. '.account.model.DeviceType')
	local PT_NAME = {
		[CTwUtil.E_TP_MAC]		= 'IOS',
		[CTwUtil.E_TP_ANDROID]	= 'ANDROID',
		[CTwUtil.E_TP_WIN32]	= 'WIN',
	}

	local ptName = PT_NAME[CTwUtil:GetPlatform()] or 'WIN'
	return device[ptName]
end

function class:PostLogin(  )
	local uniqueId = Singleton(ComLogic):GetUniqueId() or ''
	if Singleton(ComLogic):IsOperator('appstore') then
		local uniqueData = { 
			idfa = Singleton(ComLogic):GetIdfa() or '', 
			uuid = Singleton(ComLogic):GetUniqueId() or '',
			mac = Singleton(ComLogic):GetMacAddr() or '',
			account = Singleton(AcctEy):Get('userName') or ''
		}
		uniqueId = json.encode(uniqueData)
	end

	local key, timestamp = Singleton(Feedback):GetLoginKey()
	if nil == key or nil == timestamp then
		log4misc:warn('get key or timestamp error')
		return
	end

	local server = Singleton(Server):GetServer()
	if server.localGameSign then
		local saltFile = Singleton(ComLogic):GetSaltFilePath()
		--local account = Singleton(Account):Get('userId')
		local account = self:GetAccountStr()
		local keyInfo = CTwUtil:GetSingleton():MakeSaltKey(account, 
													   	   server.server, 
														   saltFile)
		key, timestamp = keyInfo.strKey, keyInfo.dwTime
	end

	local loginInfo = 
	{
		account		= self:GetAccountStr(), 
		adult 		= false, 
		gm			= false,
		timestamp	= tonumber(timestamp), 
		key 		= key,
		-- device 		= self:GetServerDeviceType(),
		token 		= Singleton(ComLogic):GetDeviceToken(), 
		appId 		= Singleton(ComLogic):GetSysVariable(GV_PKG_IDENTIFIER),
--		idfa 		= uniqueId,
--		channel 	= Singleton(ComLogic):GetChannelId()
	}

	log4login:info({ a_step = 'login', loginInfo = loginInfo })
	MsgAccount:Post('LOGIN', loginInfo)
end

--@login step3-2
function class:CreateRole(name,country,sex)
	CUMengAgent:OnEvent("CreateHero", Singleton(ComLogic):GetUniqueId())

	local device = Singleton(ComLogic):GetUniqueId()
	if Singleton(ComLogic):IsOperator('appstore') then
		local deviceData =
		{ 
			idfa	= Singleton(ComLogic):GetIdfa() or '',
			uuid 	= Singleton(ComLogic):GetUniqueId() or '',
			mac 	= Singleton(ComLogic):GetMacAddr() or ''
		}
		device = json.encode(deviceData)
	end

	local roleInfo = { account 	= self:GetAccountStr(),
					   channel 	= Singleton(ComLogic):GetChannelId(),
					   country 	= country,
					   name 	= name, 
					   sex	 	= sex,
					 }
	
	log4login:info({a_step = 'create role', roleInfo = roleInfo})
	MsgAccount:Post('CREATE', roleInfo)
end

function class:OnCreateRole( code, data )
	if code ~= 0 then 
		self.BackToAutoPatch()
		Singleton(NetAssist):OnMsgResult('MsgAccount', code)
		return
	end

	self.isCreateRole = true
    self:Login()

	--Logic:Get("Guide"):setup(self.isCreateRole)
end

--@login step4
function class:OnLogin(code, data)
	log4login:info({a_step = 'loginInfo'})
	MsgAccount:Post('LOGIN_INFO')
end

--@login step5
function class:OnLoginInfo(code, data)
    --[[
	--系统时间
	Singleton(ComLogic):SetSystemTime(data[MsgSystem.mod].systemTime)

	-- 保存登陆时获得的信息
	Logic:Get('Player'):Set('player', data[MsgPlayer.mod])
	Logic:Get('Player'):Set('account', data[MsgAccount.mod])
	
	--保存体力信息
	Logic:Get('Player'):Set('actionPoint', data[MsgPoint.mod].actionPointVo.points[0])

	data[MsgCurrency.mod].copper = Singleton(ComLogic):LongToString(data[MsgCurrency.mod].copper)
	Logic:Get('Player'):Set('walletVo', data[MsgCurrency.mod])

	--保存背包信息
	Logic:Get('Pack'):SetItems(data[MsgPack.mod], 
							   data[MsgEquip.mod])

	--保存竞技场勋章
	Logic:Get('Arena'):setMedal(data[MsgArena.mod])
	
	--保存副本信息
	Logic:Get('Copy'):SetInfoVo(data[MsgInstance.mod])

	--保存任务信息
	Logic:Get('Task'):OnCurrents(0,data[MsgTask.mod])
	
	-- 保存武将信息
	Logic:Get("Hero"):SaveHeroData(data[MsgHero.mod])

	-- 保存邮件信息
	Logic:Get("Mail"):SaveMails(data[MsgEmail.mod])
	
	-- 保存VIP信息
	Logic:Get("Vip"):setVip(data[MsgVip.mod])
	
	-- 保存首充信息
	Logic:Get("Recharge"):setVipCharge(data[MsgVip.mod])

	-- 保存公会信息
	Logic:Get("Corps"):setLoginInfo(data[MsgSociety.mod])
	
	--保存成就信息
	Logic:Get("Achievement"):setAchvInfo(data[MsgAchieve.mod])

	--保存礼包信息
	Logic:Get("Vip"):setGiftInfo(data[MsgGift.mod])

	--保存炼金信息
	Logic:Get("AlchemyLab"):setAlchemyInfo(data[MsgAlchemy.mod])
	
	--保存抽奖信息
	Logic:Get("Lottery"):setLotteryInfo(data[MsgLottery.mod])
	--保存积分信息
	Logic:Get("Lottery"):setScoreInfo(data[MsgScoremall.mod])

	--保存抽奖信息
	Logic:Get("Dice"):setDiceInfo(data[MsgDice.mod])
	
	--保存竞技场战报回放http
	if data[MsgCommon.mod] and data[MsgCommon.mod].reportsHttpUrl then
		Logic:Get("Arena"):Set("reportsHttpUrl",data[MsgCommon.mod].reportsHttpUrl)
	end

	-- 冷却时间
	Logic:Get("CoolTimes"):SetCoolTimesData(data[MsgCooltime.mod])
	
    -- 引导创角色清库
	Logic:Get("Guide"):setup(self.isCreateRole)

    -- 剧情创角色清库
	Logic:Get("DramaTalk"):cleanUpDrama(self.isCreateRole)
    --]]

	--登录完成
	self:LoginComplete()
end

--@login step6 end
function class:LoginComplete()
	local player = {}
	local areaInfo = Singleton(Server):GetServer()
	-- player.time = Singleton(ComLogic):GetTime()
	-- player.accountId = Singleton(Account):Get('userId')
	-- player.areaName = Logic:Get('Player'):GetPlayer('name')
	-- player.serverId = Singleton(Server):GetSelect()
	-- player.serverName = areaInfo.name or ''
	-- player.isFirstLogin = self.isCreateRole
	-- player.PlayerLevel = Logic:Get('Player'):GetPlayer('level')

	Singleton(EnvLogic):LoginComplete(player)
	self.isCreateRole = false

	self:RecordServer()
	Singleton(GameStage):ChgStage("Normal")
	
	log4login:info({a_step = 'loginComplete'})
	self:FireEvent(EVT.LOGIN_COMPLETE)
	-- Logic:Get('Lock'):initLockedPlays()
end

function class:RecordServer()
	Singleton(Server):RecordServer( {
		server		= Singleton(Server):GetSelect(),
		userId  	= Singleton(Account):Get('userId'), 
		roleName    =  "11",--Logic:Get('Player'):GetPlayer('name'), 
		level		=   1 ,--Logic:Get('Player'):GetPlayer('level'),
		-- vip 		= Logic:Get('Vip'):getVipLevel(),
	--	time		= Singleton(ComLogic):GetTime(),
		time		= os.time(),
	} )
end

function class:BackToAutoPatch()
	if Singleton(GameStage):IsStage('AutoPatch') then
		Singleton(AutoPatch):Check()	
	else	
		Singleton(GameStage):ChgStage('AutoPatch')
	end
end

function class:OnPromptConfirmRetry(strId)
	Prompt:Tip(strId, self,self.BackToAutoPatch)
end

function class:OnLoadArmature(data)
	if not data then return end
	local battleHeros = table.indices(data)
	local loadTable = {}
	local newSaveArmature = {}
	
	for i,v in pairs(battleHeros) do 
		if not Logic:Get("Hero"):IsLeaderById(v) then 
			local info = Logic:Get("Hero"):GetHeroDataById(v)
			local heroInfo = KFDBGetRecord('BaseHero',info.baseId)
			if heroInfo and heroInfo.model then
				local modelInfo = KFDBGetRecord('RoleSkin',heroInfo.model)
				table.insert(loadTable,modelInfo.model)
			end			
		end
	end
	--释放掉下阵武将
	for i,v in pairs(self.saveArmature) do
		local flag = true
		for ni,nv in pairs(loadTable) do 
			if nv == i then 
				flag = false
			end			
		end
		if flag then 
			v:release()
			self.saveArmature[i] = nil
		end
	end 
	--加载新的武将
	for i,v in pairs(loadTable) do 
		local flag = true
		for ni,nv in pairs(self.saveArmature) do 
			if v == ni then 
				flag = false
			end
		end
		if flag then
			table.insert(newSaveArmature,v)
		end
	end
	Armature:loadDataAsync(newSaveArmature, function(percent)
		if percent == 1 then 
			for i,v in pairs(newSaveArmature) do 
				local Armature = Armature:create(v, function() end)
				Armature:retain()
				self.saveArmature[v] = Armature
			end		
		end												
	end)
end
--预加载上阵武将
function class:loadArmature(data)
	--加载
	for i,v in pairs(data) do 
		if not Logic:Get("Hero"):IsLeaderById(i) and not self.saveArmature[i] then 
			v:retain()
			self.saveArmature[i] = v
		end
	end
	--释放之前
	for i,v in pairs(self.saveArmature) do
		if not data[i] then
			v:release()
			self.saveArmature[i] = nil
		end
	end
end
