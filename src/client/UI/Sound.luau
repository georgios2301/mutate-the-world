-- Local UI/feedback sounds (respects the SFX setting).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Sound = {}

local enabled = true
local cache: { [string]: Sound } = {}

function Sound.setEnabled(on: boolean)
	enabled = on
end

function Sound.play(name: string, speedMultiplier: number?)
	if not enabled then
		return
	end
	local def = Sounds[name]
	if not def then
		return
	end
	local sound = cache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "UI_" .. name
		sound.SoundId = def.id
		sound.Volume = def.volume or 0.5
		sound.Parent = SoundService
		cache[name] = sound
	end
	sound.PlaybackSpeed = (def.speed or 1) * (speedMultiplier or 1)
	SoundService:PlayLocalSound(sound)
end

return Sound
