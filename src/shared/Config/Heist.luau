-- Heist, defense and anti-griefing tuning. All times are seconds.
local Heist = {}

-- Stealing a creature
Heist.StartDistance = 11 -- attacker must be this close to the creature to begin
Heist.MaxDistance = 16 -- moving further away cancels the attempt
Heist.ChannelTime = 8 -- base time to finish stealing
Heist.ChannelPerSecurityLevel = 2 -- extra seconds per defender security level above 1
Heist.BaseSuccess = 0.8 -- chance the theft succeeds once the channel completes
Heist.SuccessPerSecurityLevel = -0.1 -- per security level above 1
Heist.MinSuccess = 0.45

-- Consequences
Heist.FailFinePercent = 0.05 -- attacker loses this share of coins on a failed attempt...
Heist.FailFineMax = 500 -- ...capped here (coins are destroyed, not transferred)
Heist.StunTime = 3

-- Cooldowns
Heist.AttackerCooldownFail = 60
Heist.AttackerCooldownSuccess = 180
Heist.SameVictimCooldown = 900 -- same attacker vs same victim

-- Protection / anti-griefing
Heist.NewCreatureProtection = 600 -- newly acquired creatures cannot be stolen for 10 min
Heist.VictimProtectionAfterTheft = 600 -- island immune for 10 min after losing a creature
Heist.NewPlayerProtectionSeconds = 20 * 60 -- players with < 20 min playtime ...
Heist.NewPlayerRequiresTutorial = true -- ... or an unfinished tutorial are immune
Heist.MinCreaturesKept = 3 -- a victim must own more than this many creatures
Heist.MaxLevelGap = 15 -- attacker cannot target players far below their level

-- Defenses (index = security level 1..4)
Heist.Shield = {
	duration = { 60, 90, 120, 180 },
	cooldown = { 300, 270, 240, 180 },
}
Heist.Trap = { cooldown = 45, stun = 4, minSecurity = 1 }
Heist.DoorBreachTime = { 5, 8, 11, 14 } -- hold duration to breach a locked door
Heist.DoorOpenAfterBreach = 25
Heist.AlarmMinSecurity = 2 -- intruder detection inside the vault
Heist.SlimeFloorMinSecurity = 3 -- intruders inside the vault are slowed
Heist.SlimeFloorWalkSpeed = 9
Heist.AlarmThrottle = 15

return Heist
