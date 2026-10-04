local Actor = script:GetActor()
if not Actor then
	return
end
local Estabilished = script.Parent:FindFirstChildWhichIsA("BindableEvent")
Actor:BindToMessage("init", function(BootModule, ...)
	local Boot = require(BootModule)
	Boot(...)
	Estabilished:Fire()
end)
if Estabilished then
	Estabilished:Fire()
end
