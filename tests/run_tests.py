#!/usr/bin/env python3
"""Runs the pure-logic Luau test suite outside Roblox.

Bundles every ModuleScript from the Rojo tree into one Luau file with a tiny fake
Instance hierarchy (script.Parent, game:GetService, require) plus minimal Roblox
datatype mocks, appends tests/spec.luau and executes it with the `luau` CLI.

Usage: python3 tests/run_tests.py [spec.luau]   (default: tests/spec.luau)
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD_DIR = os.path.join(ROOT, "build")


def collect_modules(project):
    """Returns [(instance_path_list, file_path)] for every ModuleScript in the tree."""
    modules = []

    def walk_tree(node, path):
        for key, child in node.items():
            if key.startswith("$") or not isinstance(child, dict):
                continue
            child_path = path + [key]
            if "$path" in child:
                walk_fs(os.path.join(ROOT, child["$path"]), child_path)
            walk_tree(child, child_path)

    def walk_fs(fs_path, inst_path):
        for name in sorted(os.listdir(fs_path)):
            full = os.path.join(fs_path, name)
            if os.path.isdir(full):
                walk_fs(full, inst_path + [name])
            elif name.endswith(".luau") or name.endswith(".lua"):
                if ".server." in name or ".client." in name:
                    continue
                base = name.rsplit(".", 1)[0]
                if base == "init":
                    modules.append((inst_path, full))
                else:
                    modules.append((inst_path + [base], full))

    walk_tree(project["tree"], [])
    return modules


PRELUDE = r'''
-- ===== Fake Roblox environment =====
local __nodes = {}
local __modules = {}
local __cache = {}
local __loading = {}

local NodeMethods = {}
local function nodeIndex(t, k)
	local m = NodeMethods[k]
	if m then return m end
	local child = rawget(t, "__children")[k]
	if child then return child end
	error("Fake instance '" .. rawget(t, "__path") .. "' has no child '" .. tostring(k) .. "'", 2)
end
local function makeNode(path, name, parent)
	local node = setmetatable({ Name = name, Parent = parent, __path = path, __children = {} }, { __index = nodeIndex })
	__nodes[path] = node
	if parent then rawget(parent, "__children")[name] = node end
	return node
end
function NodeMethods.WaitForChild(self, name) return nodeIndex(self, name) end
function NodeMethods.FindFirstChild(self, name) return rawget(self, "__children")[name] end
function NodeMethods.GetChildren(self) local out = {} for _, c in pairs(rawget(self, "__children")) do table.insert(out, c) end return out end
function NodeMethods.GetFullName(self) return rawget(self, "__path") end

local game = makeNode("game", "game", nil)
function NodeMethods.GetService(self, name)
	local svc = rawget(self, "__children")[name]
	if not svc then svc = makeNode("game/" .. name, name, self) end
	return svc
end
local function ensurePath(parts)
	local node = game
	local path = "game"
	for _, part in ipairs(parts) do
		path = path .. "/" .. part
		node = __nodes[path] or makeNode(path, part, node)
	end
	return node
end

local function typeof(v)
	if type(v) == "table" and rawget(v, "__type") then return rawget(v, "__type") end
	if type(v) == "table" and rawget(v, "__path") then return "Instance" end
	return type(v)
end

local function require(target)
	local path = type(target) == "table" and rawget(target, "__path")
	if not path then error("require() expects a fake ModuleScript, got " .. typeof(target), 2) end
	if __cache[path] ~= nil then return __cache[path] end
	local fn = __modules[path]
	if not fn then error("No module at " .. path, 2) end
	if __loading[path] then error("Cyclic require: " .. path, 2) end
	__loading[path] = true
	local result = fn(target, require)
	__loading[path] = nil
	__cache[path] = result
	return result
end

local function warn(...) print("[warn]", ...) end

local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0, __type = "Color3" }, Color3) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHSV(h, s, v) return Color3.new(v, v, v) end
function Color3:Lerp(other, a) return Color3.new(self.R + (other.R - self.R) * a, self.G + (other.G - self.G) * a, self.B + (other.B - self.B) * a) end
function Color3:ToHSV() return 0, 0, self.R end

local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __type = "Vector3" }, Vector3) end
Vector3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end

local CFrame = {}
function CFrame.new(...) return { __type = "CFrame" } end
function CFrame.lookAt(...) return { __type = "CFrame" } end

local Random = {}
Random.__index = Random
function Random.new(seed) return setmetatable({}, Random) end
function Random:NextNumber(a, b) a = a or 0 b = b or 1 return a + math.random() * (b - a) end
function Random:NextInteger(a, b) return math.random(a, b) end


local Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, k2) return k .. "." .. k2 end }) end })
local task = { wait = function() return 0 end, spawn = function(f, ...) f(...) end, defer = function(f, ...) f(...) end, delay = function() end }
local workspace = { GetServerTimeNow = function() return os.time() end }

-- ===== Modules =====
'''


def bundle(spec_path):
    with open(os.path.join(ROOT, "default.project.json")) as f:
        project = json.load(f)
    modules = collect_modules(project)
    out = [PRELUDE]
    for inst_path, file_path in modules:
        with open(file_path) as f:
            source = f.read()
        # `export type` is only legal at a module's top level; inside the wrapper it isn't.
        source = "\n".join(
            line[len("export "):] if line.startswith("export type") else line for line in source.split("\n")
        )
        key = "game/" + "/".join(inst_path)
        rel = os.path.relpath(file_path, ROOT)
        out.append('ensurePath({' + ', '.join(json.dumps(x) for x in inst_path) + '})\n')
        out.append(f'__modules[{json.dumps(key)}] = function(script, require) -- {rel}\n{source}\nend\n')
    with open(spec_path) as f:
        out.append("-- ===== Spec =====\n")
        out.append("do\n" + f.read() + "\nend\n")
    os.makedirs(BUILD_DIR, exist_ok=True)
    path = os.path.join(BUILD_DIR, "test_bundle.luau")
    with open(path, "w") as f:
        f.write("".join(out))
    return path, len(modules)


def main():
    spec = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "tests", "spec.luau")
    path, count = bundle(spec)
    print(f"Bundled {count} modules -> {os.path.relpath(path, ROOT)}")
    result = subprocess.run(["luau", path], cwd=ROOT)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
