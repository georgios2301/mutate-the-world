-- 3D creature preview in a ViewportFrame (slowly spinning while visible).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CreatureModels = require(ReplicatedStorage.Shared.CreatureModels)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)

local CreatureView = {}
CreatureView.__index = CreatureView

function CreatureView.new(parent: Instance, size: UDim2)
	local vp = Kit.new("ViewportFrame", {
		Name = "CreatureView",
		Size = size,
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		Ambient = Color3.fromRGB(170, 160, 210),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1.5, 1),
		Parent = parent,
	}) :: ViewportFrame
	Kit.corner(vp, 14)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = vp
	vp.CurrentCamera = camera
	local self = setmetatable({ frame = vp, camera = camera, model = nil, key = nil, angle = 0 }, CreatureView)
	self.conn = RunService.RenderStepped:Connect(function(dt)
		local model = self.model
		if model and Kit.isShown(vp) then
			self.angle += dt * 0.8
			model:PivotTo(CFrame.Angles(0, self.angle, 0))
		end
	end)
	return self
end

-- data = { species, mutation, level, seed } or nil to clear
function CreatureView:set(data)
	local key = data and table.concat({ data.species, data.mutation or "none", data.level or 1, data.seed or 1 }, "|")
	if key == self.key then
		return
	end
	self.key = key
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
	if not data then
		return
	end
	local model = CreatureModels.build(data, { effects = false })
	model:PivotTo(CFrame.new())
	model.Parent = self.frame
	self.model = model
	local h = math.max(3, CreatureModels.height(model))
	local target = Vector3.new(0, h * 0.45, 0)
	self.camera.CFrame = CFrame.lookAt(Vector3.new(h * 0.5, h * 0.8, -h * 2.6), target)
end

function CreatureView:destroy()
	if self.conn then
		self.conn:Disconnect()
	end
	self.frame:Destroy()
end

return CreatureView
