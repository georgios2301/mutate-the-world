-- Sound effects. These point at sounds that ship inside the Roblox engine (rbxasset://),
-- so no uploads or third-party asset IDs are required. For a production release, upload
-- your own audio and replace these with "rbxassetid://<id>" strings.
return {
	Click = { id = "rbxasset://sounds/clickfast.wav", volume = 0.4 },
	Open = { id = "rbxasset://sounds/swoosh.wav", volume = 0.25, speed = 1.3 },
	Collect = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, speed = 1.2 },
	Notify = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.35 },
	Error = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.35, speed = 0.6 },
	Travel = { id = "rbxasset://sounds/swoosh.wav", volume = 0.5, speed = 0.8 },
	Discovery = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, speed = 1.5 },
	Alarm = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, speed = 0.45 },
	Mutate = { id = "rbxasset://sounds/swoosh.wav", volume = 0.4, speed = 0.6 },
}
