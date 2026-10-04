--!nonstrict
--[[
	Paralib - Simplest parallelization library.
	Made by baj
	v 0.1.0
	License: MIT
]]
local RunService = game:GetService("RunService")
const Paralib = {}
const Pool = {}
Pool.__index = Pool

local signalplus = require(script.Packages.signalplus)

export type Pool = {
	Invoke: (self: Pool, Jobs: number, Fn: string, ...any) -> { any },
	Fire: (self: Pool, Jobs: number, Fn: string, ...any) -> (),
	Destroy: (self: Pool) -> (),
}
--export type Pool = typeof(Paralib.new())

const ActorFolder = Instance.new("Folder")
ActorFolder.Parent = script

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
	Creates a new thread pool.
	@param Threads How many threads the pool should contain
	@param Module ModuleScript that will be required in the threads
]]
function Paralib.new(Threads: number, Module: ModuleScript): Pool
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
	self._Idle = signalplus()
	self._Destroyed = false
	local Context = RunService:IsClient() and Enum.RunContext.Client or Enum.RunContext.Server
	if script.Bootstrap.RunContext ~= Context then
		script.Bootstrap.RunContext = Context
	end
	for i = 1, Threads do
		self._Actors[i] = self:_MakeActor(Module, i)
	end
	return self
end
--[[
	@private
	Creates and binds a worker actor
]]
function Pool._MakeActor(self: Pool, Module: ModuleScript, ActorId: number)
	local Actor = Instance.new("Actor")
	Actor.Parent = ActorFolder
	local Estabilished = signalplus()
	local Prior = false
	local con = Actor:BindToMessage("estabilished", function()
		Estabilished:Fire()
		Prior = true
	end)
	local Bootstrap = script.Bootstrap:Clone()
	Bootstrap.Parent = Actor
	if not Prior then
		Estabilished:Wait()
	end
	con:Disconnect()
	Estabilished:Destroy()
	Actor:SendMessage("init", self._Work, #self._Actors, Module, ActorId)
	return Actor
end

function Pool._Dispatch(self: Pool)
	if self._Destroyed then
		error("Cannot dispatch work on a destroyed thread pool", 3)
	end
	self._Pending += 1
end

function Pool._EndDispatch(self: Pool)
	self._Pending -= 1
	if self._Pending == 0 then
		self._Idle:Fire()
	end
end

--[[
	Dispatch jobs to actors
	@param Jobs Amount of jobs to dispatch. Positive finite integer.
	@param Fn Function name to use as job
	@return Table of results
	@yields
]]
function Pool.Invoke(self: Pool, Jobs: number, Fn: string, ...: any): { any }
	if Jobs <= 0 then
		return {}
	end
	self:_Dispatch()
	local Pointer = self._Pointer
	self._Pointer += Jobs
	local Results = SharedTable.new()
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
	self._Work:Fire(Completed, Results, Pointer, Jobs, Fn, ...)
	Finished:Wait()
	Connection:Disconnect()
	Completed:Destroy()
	Finished:Destroy()
	local Result = StToTbl(Results)
	return Result
end
--[[
	Dispatch jobs to actors without yielding for result
	@param Jobs Amount of jobs to dispatch. Positive finite integer.
	@param Fn Function name to use as job
]]
function Pool.Fire(self: Pool, Jobs: number, Fn: string, ...: any)
	if Jobs <= 0 then
		return
	end
	self:_Dispatch()
	local Pointer = self._Pointer
	self._Pointer += Jobs
	local Results = SharedTable.new()
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
		end
	end)
	self._Work:Fire(Completed, Results, Pointer, Jobs, Fn, ...)
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
