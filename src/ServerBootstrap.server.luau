local Actor = script:GetActor()
if not Actor then
	return
end
Actor:BindToMessageParallel("init", function(BootModule, ...)
	local Boot = require(BootModule)
	Boot(...)
end)
Actor:SendMessage("estabilished")
