--[[
	Returns a range of jobs the actor has to take over
	@param Pointer Amount of jobs completed prior to this batch
	@param Jobs Amount of jobs assigned to the current batch
	@param ActorId Our actor id
	@param ActorCount Total number of actors in the pool
]]
local function GetRange(Pointer: number, Jobs: number, ActorId: number, ActorCount: number): (number, number)
	local JobsPerActor = math.floor(Jobs / ActorCount)
	local Remainder = Jobs % ActorCount
	local Offset = Pointer % ActorCount
	local ActorIndex = ActorId - 1

	local ActorRelativeIndex = (ActorIndex - Offset + ActorCount) % ActorCount
	local ActorJobs = JobsPerActor + if ActorRelativeIndex < Remainder then 1 else 0

	local ExtraJobsBeforeActor
	local RemainderEnd = Offset + Remainder

	if RemainderEnd <= ActorCount then
		ExtraJobsBeforeActor = math.max(0, math.min(ActorIndex, RemainderEnd) - Offset)
	else
		local WrappedEnd = RemainderEnd - ActorCount
		ExtraJobsBeforeActor = math.max(0, ActorIndex - Offset) + math.min(ActorIndex, WrappedEnd)
	end

	local JobsBeforeActor = ActorIndex * JobsPerActor + ExtraJobsBeforeActor
	local Start = Pointer + JobsBeforeActor + 1

	return Start, Start + ActorJobs - 1
end
return function(Bindable: BindableEvent, n: number, Module: ModuleScript, ActorId: number, InitErrs: SharedTable)
	local loaded, m = pcall(require, Module)
	if not loaded then
		InitErrs[ActorId] = tostring(m)
	end
	Bindable.Event:ConnectParallel(
		function(
			Completed: BindableEvent?,
			Results: SharedTable,
			Errors: SharedTable?,
			DispatchId: number,
			Pointer: number,
			Jobs: number,
			Fn: string,
			...
		)
			local function Stop()
				if Completed then
					Completed:Fire()
				end
			end
			if n <= 0 then
				Stop()
				return
			end
			local iStart, iEnd = GetRange(Pointer, Jobs, ActorId, n)
			if iStart > iEnd then
				Stop()
				return
			end
			local function Error(message: string)
				if Errors then
					Errors[ActorId] =
						`failed: {message}\ndispatch={DispatchId} actor={ActorId} function={Fn} range={iStart}-{iEnd}`
				end
			end
			if not m or typeof(Fn) ~= "string" or not m[Fn] then
				Error("Invalid worker function")
				Stop()
				return
			end
			local args = table.pack(...)
			local function RunWorker()
				m[Fn](iStart, iEnd, Results, table.unpack(args, 1, args.n))
			end
			local success, err = xpcall(RunWorker, function(message)
				return debug.traceback(tostring(message), 2)
			end)
			task.synchronize()
			if not success then
				Error(err)
			end
			Stop()
		end
	)
end
