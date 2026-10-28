-- Access to the RemoteEvents/RemoteFunctions defined in default.project.json
-- (ReplicatedStorage.Remotes). See docs/REMOTES.md for each remote's purpose.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder = ReplicatedStorage:WaitForChild("Remotes")

function Remotes.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
