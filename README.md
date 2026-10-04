# paralib
Simplest parallelization library.

## Installation
add `paralib = bajsucks/paralib@*` to your wally.toml to install

## Usage
`paralib.new(n, Module)` - Create a pool of `n` actors with the module as content

`Pool:Invoke(n, FnStr, ...)` - Run `n` jobs of the function `Module[FnStr]`. Yields until the jobs finish and returns their results as a normal table.

`Pool:Fire(n, FnStr, ...)` - Run `n` jobs of the function `Module[FnStr]` without yielding. All results are discarded.

`Pool:Destroy()` - Locks the pool, waits for all jobs to finish and kills it.

## Parallel function Module[FnStr]
`(iStart, iEnd, Results, ...) -> ()`

where

`iStart, iEnd` - job range.

`Results` - SharedTable that will be sent to the caller after all jobs finish. Note that the caller will receive a converted normal table `{}`, not a `SharedTable`.

`...` - Any custom arguments. Note that they must be serializable.


## Example usage

```luau
-- Worker module
local Worker = {}

function Worker.SumSquares(iStart, iEnd, Results, values)
	for i = iStart, iEnd do
		local value = values[i]
		Results[i] = value * value
	end
end

return Worker
```

```luau
-- Module where you want to call the worker
local Paralib = require(game.ReplicatedStorage.Paralib)
local WorkerModule = script.Parent.WorkerModule -- path to the worker module

local pool = Paralib.new(4, WorkerModule)
local values = { 1, 2, 3, 4, 5, 6, 7, 8 }

local results = pool:Invoke(#values, "SumSquares", values)

for i, value in results do
	print(i, value)
end

pool:Destroy()
```

This creates a pool of 4 actors, runs `WorkerModule.SumSquares` for each item in the array, and returns the results as a normal Luau table.

If you do not need the result, you can fire-and-forget work:

```luau
local pool = Paralib.new(2, script.Parent.WorkerModule)
pool:Fire(100, "SumSquares", values)
pool:Destroy()
```
