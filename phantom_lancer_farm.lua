-- Umbrella Lua: Phantom Lancer jungle farm
local script = {}
local g = Menu.Create("Scripts", "Scripts", "PL Farm")
    :Create("Settings"):Create("Автофарм", Enum.GroupSide.Left)
local enable = g:Switch("Включить", false)
local bind = g:Bind("Автофарм", Enum.ButtonCode.KEY_NONE)
bind:Properties("Автофарм ПЛ", nil, true)
local useIllusions = g:Switch("Управлять иллюзиями", true)
local useLance = g:Switch("Spirit Lance", true)
local minMana = g:Slider("Минимум маны, %", 0, 90, 40)
local minHP = g:Slider("Отход при HP, %", 10, 70, 35)
local dangerRadius = g:Slider("Радиус опасности", 600, 2500, 1400)
local routeRadius = g:Slider("Радиус от точки запуска", 1500, 10000, 5000)
local ancients = g:Switch("Древние", false)
local s
local function reset()
    s = {next = 0, blocked = {}, orders = {}, castUntil = 0}
end
reset()
local function p(u) return Entity.GetAbsOrigin(u) end
local function dist(a,b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2)
end
local function live(u)
    return Entity.IsAlive(u) and not Entity.IsDormant(u)
end
local function center(c)
    local b = Camp.GetCampBox(c)
    if not b or not b.min or not b.max then return end
    return Vector((b.min.x+b.max.x)/2,(b.min.y+b.max.y)/2,(b.min.z+b.max.z)/2)
end
local function act(u)
    return not NPC.IsStunned(u) and not NPC.IsChannellingAbility(u)
end
local function move(u, point, now)
    if not act(u) then return end
    local id = Entity.GetIndex(u)
    local old = s.orders[id]
    if old and old.point and dist(old.point,point)<100 and now-old.time<1.2 then return end
    NPC.MoveTo(u, point, false, false, false, false, "pl_farm")
    s.orders[id] = {point=point,time=now}
end
local function attack(player,u,target,now)
    if not act(u) then return end
    local id, tid = Entity.GetIndex(u), Entity.GetIndex(target)
    local old = s.orders[id]
    if old and old.target==tid and (NPC.IsAttacking(u) or now-old.time<1.2) then return end
    Player.AttackTarget(player,u,target,false,false,false,"pl_farm")
    s.orders[id] = {target=tid,time=now}
end
function script.OnUpdate()
    local h, player = Heroes.GetLocal(), Players.GetLocal()
    if not h or not player or NPC.GetUnitName(h)~="npc_dota_hero_phantom_lancer"
        or not enable:Get() or not bind:IsToggled() or not Entity.IsAlive(h) then
        reset()
        return
    end
    if GameRules.IsPaused() then return end
    local now = GameRules.GetGameTime()
    if now<0 or now<s.next then return end
    s.next = now+0.25
    s.anchor = s.anchor or p(h)
    local foes, neutrals, units = {}, {}, {h}
    for _,e in ipairs(Heroes.GetAll() or {}) do
        if live(e) and NPC.IsVisible(e) and not NPC.IsIllusion(e)
            and Entity.GetTeamNum(e)~=Entity.GetTeamNum(h) then foes[#foes+1]=e end
    end
    local function safe(point)
        for _,e in ipairs(foes) do
            if dist(point,p(e))<dangerRadius:Get() then return false end
        end
        return true
    end
    local ids = {[Entity.GetIndex(h)]=true}
    for _,u in ipairs(NPCs.GetAll() or {}) do
        if Entity.GetTeamNum(u)==Entity.GetTeamNum(h)
            and (NPC.GetUnitName(u) or ""):find("fountain",1,true) then s.home=p(u) end
        if live(u) then
            if NPC.IsNeutral(u) and NPC.IsVisible(u) and not NPC.IsWaitingToSpawn(u)
                and Entity.GetTeamNum(u)~=Entity.GetTeamNum(h) then neutrals[#neutrals+1]=u
            elseif useIllusions:Get() and u~=h and NPC.IsIllusion(u)
                and NPC.GetUnitName(u)==NPC.GetUnitName(h) and NPC.GetOwnerNPC(u)==h
                and NPC.IsControllableByPlayer(u,Player.GetPlayerID(player)) then
                units[#units+1]=u
                ids[Entity.GetIndex(u)]=true
            end
        end
    end
    for id in pairs(s.orders) do if not ids[id] then s.orders[id]=nil end end
    local hp = Entity.GetHealth(h)*100/math.max(1,Entity.GetMaxHealth(h))
    if hp<=minHP:Get() then s.retreat=true end
    if hp>=90 then s.retreat=false end
    if s.retreat or not safe(p(h)) then
        if s.camp then s.blocked[s.camp.key]=now+15 end
        s.camp=nil
        if s.home then for _,u in ipairs(units) do move(u,s.home,now) end end
        return
    end
    if not act(h) or now<s.castUntil then return end
    local function at(point)
        local list={}
        for _,u in ipairs(neutrals) do
            if dist(p(u),point)<800 then list[#list+1]=u end
        end
        return list
    end
    local nextSpawn=(math.floor(now/60)+1)*60+1
    if s.camp and not safe(s.camp.point) then
        s.blocked[s.camp.key]=now+15
        s.camp=nil
    end
    if not s.camp then
        local bestScore=math.huge
        for _,c in ipairs(Camps.GetAll() or {}) do
            local point=center(c)
            if point and dist(point,s.anchor)<=routeRadius:Get() and safe(point) then
                local k=string.format("%.0f:%.0f",point.x,point.y)
                if (s.blocked[k] or 0)<=now then
                    local list, allowed=at(point),true
                    for _,u in ipairs(list) do
                        if NPC.IsAncient(u) and not ancients:Get() then allowed=false end
                    end
                    if not allowed then s.blocked[k]=nextSpawn
                    else
                        local score=dist(p(h),point)+(#list==0 and 1000 or 0)
                        if score<bestScore then
                            s.camp={point=point,key=k}
                            bestScore=score
                        end
                    end
                end
            end
        end
    end
    local c=s.camp
    if not c then return end
    local list=at(c.point)
    for _,u in ipairs(list) do
        if NPC.IsAncient(u) and not ancients:Get() then
            s.blocked[c.key]=nextSpawn
            s.camp=nil
            return
        end
    end
    if #list==0 then
        if dist(p(h),c.point)<250 then
            c.arrived=c.arrived or now
            if now-c.arrived>=1 then s.blocked[c.key]=nextSpawn; s.camp=nil; return end
        else c.arrived=nil end
        for _,u in ipairs(units) do move(u,c.point,now) end
        return
    end
    c.arrived=nil
    table.sort(list,function(a,b) return dist(p(h),p(a))<dist(p(h),p(b)) end)
    local target=list[1]
    for i=2,#units do attack(player,units[i],target,now) end
    local q=NPC.GetAbility(h,"phantom_lancer_spirit_lance")
    if useLance:Get() and q and Ability.GetLevel(q)>0 and Ability.IsReady(q)
        and not NPC.IsSilenced(h) and Ability.IsCastable(q,NPC.GetMana(h))
        and NPC.GetMana(h)*100/math.max(1,NPC.GetMaxMana(h))>=minMana:Get()
        and dist(p(h),p(target))<=Ability.GetCastRange(q) then
        Ability.CastTarget(q,target)
        s.castUntil=now+math.max(0.6,Ability.GetCastPoint(q)+0.25)
        s.orders[Entity.GetIndex(h)]=nil
        return
    end
    attack(player,h,target,now)
end
function script.OnGameEnd() reset() end
return script
