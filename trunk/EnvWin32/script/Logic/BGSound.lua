module(..., package.seeall)

class = Logic.class:subclass()

function class:initialize()
	super.initialize(self)
	
	self.music = 
	{ 
--		BG		= "audio/sound/bgm/city.mp3", 
--		BATTLE 	= "audio/sound/bgm/battle_001.mp3", 
--		LOGIN	= "audio/sound/bgm/loading.mp3", 
--		WORLD	= "audio/sound/bgm/world.mp3", 
	}
end

function class:dispose()
	super.dispose(self)
end

------------------------------------------------------------------
-- public: music control
function class:playMusic(name)
	if self.music[name] == nil then 
		return
	end

	self:switchMusic(self.music[name])
end

function class:stopMusic(name)
	if name == nil then
		AudioEngine.stopMusic()
		return
	end

	local file = self.music[name]

	if "" == file then return end
	file = Singleton(ComLogic):GetFullPath(file)
	if file ~= self.curFile then
		return
	end

	self.curFile = ""
	AudioEngine.stopMusic()
end

function class:pauseMusic(name)
	local file = self.music[name]

	if nil == file or "" == file then return end
	file = Singleton(ComLogic):GetFullPath(file)
	if file ~= self.curFile then
		return
	end

	AudioEngine.pauseMusic()
end

function class:resumeMusic(name)
	local file = self.music[name]

	if nil == file or "" == file then return end
	file = Singleton(ComLogic):GetFullPath(file)
	if file ~= self.curFile then
		return
	end

	AudioEngine.resumeMusic()
end

function class:resetMusic(name, isClose)
	if isClose then
		self:stopMusic(self.curFile)
	else
		self:playMusic(name)
	end
end

function class:getMusicVolume()
	return AudioEngine.getMusicVolume()
end

function class:setMusicVolume(volume)
	AudioEngine.setMusicVolume(volume)
end
------------------------------------------------------------------
-- public: effect control
function class:PlayEffect(file)
	self:playEffect(file)
end

function class:playEffect(file)
	local isClose = (1 == Singleton(ComLogic):GetSysVar( "CLOSE_SOUND" ))
	if isClose then return end

	if nil == file or "" == file then return end
	file = string.gsub(file, "\\", "/")

	file = Singleton(ComLogic):GetFullPath(file)
	AudioEngine.playEffect(file)
end

function class:pauseEffect()
	AudioEngine.pauseAllEffects()
end

function class:resumeEffect()
	AudioEngine.resumeAllEffects()
end

function class:getEffectsVolume()
	return AudioEngine.getEffectsVolume()
end

function class:getEffectsVolume(volume)
	AudioEngine.setEffectsVolume(volume)
end

function class:stopAllEffect()
	AudioEngine.stopAllEffects()
end

------------------------------------------------------------------
-- private: music fading control
function class:switchMusic(file, loop)
	loop = nil == loop and true or loop
	local isClose = (1 == Singleton(ComLogic):GetSysVar( "CLOSE_MUSIC" ))
	if isClose then return end

	if nil == file or "" == file then return end
	file = Singleton(ComLogic):GetFullPath(file)

	if self.curFile ~= nil and self.curFile ~= "" and self.curFile ~= file then
		if not self:EventTracer():Exist("FADE_CLOSE") then		
			Singleton(Timer):Repeat(50, self:Event("FADE_CLOSE", "onFadeClose"))
		end
		self.nextFile = {["file"] = file, ["loop"] = loop} 

		return
	end
	
	if self.curFile == file then return end

	if not pl.path.exists(file) then return end

	AudioEngine.playMusic(file, loop)
	self.curFile = file
end

function class:onFadeClose()
	local volume = AudioEngine.getMusicVolume() * 100
	volume = volume - 3
	volume = math.max(volume, 0)
	AudioEngine.setMusicVolume(volume / 100)

	if volume == 0 then
		self:onFadeCloseFinish()
	end
end

function class:onFadeCloseFinish()
	self:EventTracer():Cancel("FADE_CLOSE")
    
	AudioEngine.stopMusic()

	if nil ~= self.nextFile and nil ~= self.nextFile.file then		
		AudioEngine.playMusic(self.nextFile.file, self.nextFile.loop)
		if not self:EventTracer():Exist("FADE_OPEN") then
			Singleton(Timer):Repeat(50, self:Event("FADE_OPEN", "onFadeOpen"))
		end
		
		self.curFile = self.nextFile.file
		self.nextFile = nil
	end
end 

function class:onFadeOpen()
	local volume = AudioEngine.getMusicVolume() * 100
	volume = volume + 2
	volume = math.min(volume, 100)
	AudioEngine.setMusicVolume(volume / 100)

	if volume == 100 then
		self:EventTracer():Cancel("FADE_OPEN")
	end
end
