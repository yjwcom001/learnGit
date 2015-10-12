require 'logger'

--[[----------------------------------------------------------------------------

	1、支持DEBUG、INFO、WARN、ERROR、FATAL五种类型，等级从低到高

	2、Category('misc', 'DEBUG')，创建log4misc，并定义最低显示等级，默认为WARN
	
	3、用法：log4misc:debug('xxx')、log4misc:info('%s-%s', 'xx', 'yy')
	
--]]----------------------------------------------------------------------------

logger.Category('develop',	'DEBUG')
logger.Category('cocos2d',	'WARN')
logger.Category('login',	'WARN')
logger.Category('msg',		'WARN')
logger.Category('system',	'WARN')
logger.Category('drama',	'WARN')
logger.Category('misc',		'WARN')
logger.Category('battle',	'WARN')
logger.Category('men',		'WARN')
logger.Category('temp',		'DEBUG')
logger.Category('t',		'WARN')	--as temp
logger.Category('ui',		'WARN')
logger.Category('sql',		'WARN')
logger.Category('net',		'ERROR')
logger.Category('guide',	'WARN')
logger.Category('recepit',	'WARN')
