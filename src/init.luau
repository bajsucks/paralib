--!nonstrict
--[[
	Paralib - Simplest parallelization library.
	Made by baj
	v 0.1.3
	License: MIT
]]
local RunService = game:GetService("RunService")
const Paralib = {}
const Pool = {}
Pool.__index = Pool

local signalplus = require(script.Parent.signalplus)

local BootModule = script.Boot

export type Pool = {
	Invoke: (self: Pool, Jobs: number, Fn: string, ...any) -> { any },
	Fire: (self: Pool, Jobs: number, Fn: string, ...any) -> (),
	Destroy: (self: Pool) -> (),
}
--export type Pool = typeof(Paralib.new())

const ActorFolder = Instance.new("Folder")
ActorFolder.Name = "ParalibActors"
ActorFolder.Parent = RunService:IsClient() and script or game:GetService("ServerScriptService")

local ID = 0

local function StToTbl(st): any
	local tbl = {}
	for key, value in st do
		if typeof(value) == "SharedTable" then
			tbl[key] = StToTbl(value)
		else
			tbl[key] = value
		end
	end
	return tbl
end

local function Event(): BindableEvent
	return Instance.new("BindableEvent")
end
--[[
	Creates a new thread pool. This will yield a bit depending on thread count.
	@param Threads How many threads the pool should contain
	@param Module ModuleScript that will be required in the threads
	@param Debug Extended error handling; May degrade performance
	@yields
]]
function Paralib.new(Threads: number, Module: ModuleScript, Debug: boolean?): Pool
	local self = setmetatable({}, Pool)
	if not Threads or Threads <= 0 or math.floor(Threads) ~= Threads then
		error(`Tried to create a thread pool with {Threads} threads!`, 2)
	end
	ID += 1
	self._ID = tostring(ID) :: string
	self._Actors = table.create(Threads, 0) :: { Actor }
	self._Work = Event()
	self._Work.Parent = ActorFolder
	self._Pointer = 0
	self._Pending = 0
	self._DispatchId = 0
	self._Debug = Debug == true
	self._Idle = signalplus()
	self._Destroyed = false
	self._InitErrs = SharedTable.new()
	local Bootstrap = RunService:IsClient() and script.ClientBootstrap or script.ServerBootstrap
	for i = 1, Threads do
		self._Actors[i] = self:_MakeActor(Module, i, Bootstrap)
	end
	local InitErrs = {}
	for ActorId, message in self._InitErrs do
		table.insert(InitErrs, `actor={ActorId}: {message}`)
	end
	self._InitErrs = nil
	if #InitErrs > 0 then
		for _, Actor in self._Actors do
			Actor:Destroy()
		end
		self._Work:Destroy()
		self._Idle:Destroy()
		error(`Failed to initialize worker module:\n{table.concat(InitErrs, "\n")}`, 2)
	end
	return self
end
--[[
	@private
	Creates and binds a worker actor
]]
function Pool._MakeActor(self: Pool, Module: ModuleScript, ActorId: number, Bootstrap: Script)
	local Actor = Instance.new("Actor")
	Actor.Parent = ActorFolder
	local Estabilished = Event()
	Estabilished.Parent = Actor
	Bootstrap = Bootstrap:Clone()
	Bootstrap.Parent = Actor
	Estabilished.Event:Wait()
	Actor:SendMessage("init", BootModule, self._Work, #self._Actors, Module, ActorId, self._InitErrs)
	Estabilished.Event:Wait()
	Estabilished:Destroy()
	return Actor
end

function Pool._Dispatch(self: Pool, Jobs: number, Fn: string): (number, number)
	if typeof(Jobs) ~= "number" or Jobs <= 0 or Jobs ~= math.floor(Jobs) or Jobs == math.huge then
		error(`Jobs must be a positive finite integer; got {Jobs}`, 3)
	end
	if typeof(Fn) ~= "string" or Fn == "" then
		error("Fn must be a non-empty string", 3)
	end
	if self._Destroyed then
		error("Cannot dispatch work on a destroyed thread pool", 3)
	end
	self._Pending += 1
	self._DispatchId += 1
	local Pointer = self._Pointer
	self._Pointer += Jobs
	return self._DispatchId, Pointer
end

function Pool._EndDispatch(self: Pool)
	self._Pending -= 1
	if self._Pending == 0 then
		self._Idle:Fire()
	end
end

function Pool._Report(Errors: SharedTable, DispatchId: number, Fn: string): string?
	local ErrorCount = 0
	local FirstActor
	local FirstMessage
	for ActorId, message in Errors do
		ErrorCount += 1
		if not FirstActor or ActorId < FirstActor then
			FirstActor = ActorId
			FirstMessage = message
		end
	end
	if ErrorCount == 0 then
		return nil
	end
	return `[Paralib] dispatch={DispatchId} function={Fn} completed with {ErrorCount} worker error(s). First error:\n{FirstMessage}`
end

--[[
	Dispatch jobs to actors
	@param Jobs Amount of jobs to dispatch. Positive finite integer.
	@param Fn Function name to use as job
	@return Table of results
	@yields
]]
function Pool.Invoke(self: Pool, Jobs: number, Fn: string, ...: any): { any }
	local DispatchId, Pointer = self:_Dispatch(Jobs, Fn)
	local Results = SharedTable.new()
	local Errors = self._Debug and SharedTable.new()
	local Completed = Event()
	Completed.Parent = ActorFolder
	local Returned = 0
	local Finished = signalplus()
	local Connection
	Connection = Completed.Event:Connect(function()
		Returned += 1
		if Returned >= #self._Actors then
			self:_EndDispatch()
			Finished:Fire()
		end
	end)
	self._Work:Fire(Completed, Results, Errors, DispatchId, Pointer, Jobs, Fn, ...)
	Finished:Wait()
	Connection:Disconnect()
	Completed:Destroy()
	Finished:Destroy()
	if self._Debug then
		local ErrorMessage = Pool._Report(Errors, DispatchId, Fn)
		Errors = nil
		if ErrorMessage then
			warn(ErrorMessage)
			error(`Paralib dispatch {DispatchId} failed`, 2)
		end
	end
	local Result = StToTbl(Results)
	return Result
end
--[[
	Dispatch jobs to actors without yielding for result
	@param Jobs Amount of jobs to dispatch. Positive finite integer.
	@param Fn Function name to use as job
]]
function Pool.Fire(self: Pool, Jobs: number, Fn: string, ...: any)
	local DispatchId, Pointer = self:_Dispatch(Jobs, Fn)
	local Results = SharedTable.new()
	local Errors = self._Debug and SharedTable.new()
	local Completed = Event()
	Completed.Parent = ActorFolder
	local Returned = 0
	local Connection
	Connection = Completed.Event:Connect(function()
		Returned += 1
		if Returned >= #self._Actors then
			Connection:Disconnect()
			Completed:Destroy()
			self:_EndDispatch()
			if self._Debug then
				local ErrorMessage = Pool._Report(Errors, DispatchId, Fn)
				if ErrorMessage then
					warn(ErrorMessage)
				end
			end
		end
	end)
	self._Work:Fire(Completed, Results, Errors, DispatchId, Pointer, Jobs, Fn, ...)
end

function Pool.Destroy(self: Pool)
	if self._Destroyed then
		return
	end
	self._Destroyed = true
	if self._Pending > 0 then
		self._Idle:Wait()
	end
	for _, Actor in self._Actors do
		Actor:Destroy()
	end
	self._Work:Destroy()
	self._Idle:Destroy()
	return
end

return Paralib
