

local E = getgenv()
local API = E.GrowbloxHub
assert(API and API.State and API.State.movement, "Jalankan Becks dulu")
local S = API.State
local RS = game:GetService("ReplicatedStorage")
local Net = require(RS.Shared.Net)
local DB = require(RS.Shared.ItemDB)

-- bersihkan instance lama patch ini
if E.BecksLavaBreaker then pcall(E.BecksLavaBreaker.Unload) end

local gameSource = "Players." .. game.Players.LocalPlayer.Name .. ".PlayerGui.GameGui.Game"
local world, hit, controls
for _, f in Net.tileChanged.getListeners() do
    if debug.info(f, "s") == gameSource then
        for _, v in debug.getupvalues(f) do
            if type(v) == "table" and v.fg and v.bg and v.w and v.h then world = v end
        end
    end
end
assert(world, "World tidak ditemukan")
for _, f in filtergc("function", {Name = "act"}, false) do
    if debug.info(f, "s") == gameSource then
        local same, cand = false, nil
        for _, v in debug.getupvalues(f) do
            if v == world then same = true end
            if type(v) == "function" and debug.info(v, "n") == "hit" then cand = v end
        end
        if same and cand then hit = cand; break end
    end
end
assert(hit, "Fungsi hit tidak ditemukan")
for _, v in debug.getupvalues(hit) do
    if type(v) == "table" and type(v.punchRange) == "function" then controls = v end
end
assert(controls, "controls tidak ditemukan")

local LB = {enabled = true, broken = 0, blocked = 0, busy = false, target = nil,
    error = nil, live = true, giveUpAt = {}}
E.BecksLavaBreaker = LB

local function position()
    local x, y = debug.getupvalue(world.goTo, 1), debug.getupvalue(world.goTo, 2)
    return x, y
end
local function tile(x, y)
    local row = world.fg[y]
    return row and row[x]
end
local function isHurt(x, y)
    local d = DB[tile(x, y) or 0]
    return d ~= nil and d.hurts == true
end

-- cek tile lava di depan avatar (setinggi kaki dan badan)
local function lavaAhead(dir)
    local px, py = position()
    local fy = math.floor(py - 0.05)
    local nx = math.floor(px + dir * 0.6)
    if nx < 0 or nx >= world.w then return nil end
    for _, y in {fy, fy - 1} do
        if isHurt(nx, y) then return nx, y end
    end
    return nil
end

-- proxy untuk S.movement.keys: tulis A/D ke arah lava ditolak
local real = S.movement.keys
local KA, KD = Enum.KeyCode.A, Enum.KeyCode.D
local proxy = setmetatable({}, {
    __index = function(_, k) return real[k] end,
    __newindex = function(_, k, v)
        if v == true and LB.enabled and (k == KA or k == KD) then
            local ok, lx, ly = pcall(lavaAhead, k == KD and 1 or -1)
            if ok and lx then
                LB.blocked += 1
                if not LB.busy and not LB.target then LB.target = {x = lx, y = ly} end
                real[KA], real[KD] = false, false
                return
            end
        end
        real[k] = v
    end,
    __iter = function() return next, real end,
})
S.movement.keys = proxy

-- worker: pecahkan lava yang ditandai
task.spawn(function()
    while LB.live and E.GrowbloxHub == API do
        local t = LB.target
        if t and not LB.busy then
            LB.busy = true
            local ok, err = pcall(function()
                local id = tile(t.x, t.y)
                local def = DB[id or 0]
                if not def or not def.hurts then return end
                if not def.hits or def.hits <= 0 then
                    error("Lava tidak bisa dihancurkan (hits=0)")
                end
                for _ = 1, def.hits * 3 + 3 do
                    if not LB.live or tile(t.x, t.y) ~= id then break end
                    local px, py = position()
                    local reach = math.min(controls.punchRange(), 2.5)
                    if math.abs(t.x + 0.5 - px) > reach or math.abs(t.y + 0.5 - py) > reach then
                        error("Lava di luar jangkauan pukul")
                    end
                    hit(t.x, t.y)
                    S.nativeCalls += 1
                    task.wait(math.max(0.24, S.config.interval, S.mining.effectiveInterval))
                end
                if tile(t.x, t.y) == 0 then LB.broken += 1
                elseif tile(t.x, t.y) == id then error("Lava masih ada setelah dipukul") end
            end)
            LB.target, LB.busy = nil, false
            if not ok then
                LB.error = tostring(err):match("^[^\r\n]+") or tostring(err)
                -- tidak bisa dipecah: hentikan bot supaya tidak menginjak lava
                task.defer(function()
                    if API.Stop then API.Stop("Lava: " .. LB.error) end
                end)
            end
        end
        task.wait(0.03)
    end
end)

function LB.Unload()
    LB.live = false
    if S.movement.keys == proxy then S.movement.keys = real end
    if E.BecksLavaBreaker == LB then E.BecksLavaBreaker = nil end
end

print("[Lava Breaker] aktif. Toggle: getgenv().BecksLavaBreaker.enabled = true/false")
return LB
