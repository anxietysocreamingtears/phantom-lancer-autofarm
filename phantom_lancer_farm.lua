-- Umbrella Lua: Phantom Lancer jungle farm
local script = {}
local g = Menu.Create("Scripts", "Scripts", "PL Farm")
    :Create("Settings"):Create("Автофарм", Enum.GroupSide.Left)
local enable = g:Switch("Включить", false)
local bind = g:Bind("Автофарм", Enum.ButtonCode.KEY_NONE)
bind:Properties("Автофарм ПЛ", nil, true)
local useIllusions = g:Switch("Управлять иллюзиями", true)
local useLance = g:Switch("Spirit Lance: только для плотной цели", false)
local minHP = g:Slider("Отход при HP, %", 10, 70, 35)
local dangerRadius = g:Slider("Радиус опасности", 600, 2500, 1400)
local routeRadius = g:Slider("Радиус от точки запуска", 1500, 10000, 5000)
local ancients = g:Switch("Древние", false)
local autoRegen = g:Switch("Покупать и использовать Flask / Clarity", true)
local s
local function reset()
    s = {next = 0, blocked = {}, orders = {}, castUntil = 0, buy = {}, use = {}}
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
-- Consumables use inventory slots 0..5, backpack 6..8, stash 9..14.
local supplies = {
    {name="item_flask", id=39, cost=110, modifier="modifier_flask_healing"},
    {name="item_clarity", id=38, cost=50, modifier="modifier_clarity_potion"}
}
local function itemAt(h, slot) return NPC.GetItemByIndex(h, slot) end
local function findItem(h, name)
    for slot=0,14 do
        local item=itemAt(h,slot)
        if item and Ability.GetName(item)==name then return item,slot end
    end
end
local function itemIndex(item) return item and Entity.GetIndex(item) or -1 end
local function moveItem(h, item, slot)
    return Engine.RunScript(string.format(
        "Game.PrepareUnitOrders({OrderType:dotaunitorder_t.DOTA_UNIT_ORDER_MOVE_ITEM,TargetIndex:%d,AbilityIndex:%d,UnitIndex:%d,OrderIssuer:PlayerOrderIssuer_t.DOTA_ORDER_ISSUER_HERO_ONLY,Queue:false});",
        slot,Entity.GetIndex(item),Entity.GetIndex(h)))
end
local function restore(h, now)
    local t=s.swap
    if not t then return true end
    local original=itemAt(h,t.back)
    local active=itemAt(h,t.front)
    -- Restore only the exact displaced item, never overwrite manual changes.
    if t.original == -1 then s.swap=nil; return true end
    if itemIndex(active)==t.original then s.swap=nil; return true end
    if itemIndex(original)~=t.original
        or (active and itemIndex(active)~=t.consumable) then
        s.swap=nil
        return true
    end
    if now >= (t.nextRestore or 0) then
        moveItem(h,original,t.front)
        t.nextRestore=now+1
    end
    return false
end
local function regen(h,player,now,hp,mana,safeToUse)
    local courier=Couriers.GetLocal()
    local function owned(name)
        return findItem(h,name)
            or (courier and NPC.GetItem(courier,name,false))
    end
    local needs={hp<50,mana<50}
    local delivery=false
    for i,def in ipairs(supplies) do
        local item,slot=findItem(h,def.name)
        local buff=NPC.HasModifier(h,def.modifier)
        if needs[i] and not buff then
            if not owned(def.name) and now >= (s.buy[def.name] or 0)
                and Player.GetTotalGold(player)>=def.cost
                and GameRules.GetStockCount(def.id,Entity.GetTeamNum(h))>0 then
                -- One outstanding purchase; allow time for inventory replication/delivery.
                Engine.RunScript(string.format(
                    "Game.PrepareUnitOrders({OrderType:dotaunitorder_t.DOTA_UNIT_ORDER_PURCHASE_ITEM,TargetIndex:0,Position:[0,0,0],AbilityIndex:%d,OrderIssuer:PlayerOrderIssuer_t.DOTA_ORDER_ISSUER_HERO_ONLY,UnitIndex:%d,Queue:false});",
                    def.id,Entity.GetIndex(h)))
                s.buy[def.name]=now+30
                return true
            end
            if (item and slot>=9) or (courier and NPC.GetItem(courier,def.name,false)) then
                delivery=true
            end
        end
    end
    if delivery and courier and Entity.IsAlive(courier) and now>=(s.delivery or 0) then
        local transfer=NPC.GetAbility(courier,"courier_transfer_items")
        if transfer and Ability.IsReady(transfer) then Ability.CastNoTarget(transfer) end
        s.delivery=now+10
    end
    local t=s.swap
    if t then
        if t.used and now<s.castUntil then return true end
        if t.used or now>t.deadline or not safeToUse then
            restore(h,now)
            return true
        end
        local item=itemAt(h,t.front)
        if itemIndex(item)==t.consumable and now>=t.readyAt
            and Item.IsItemEnabled(item) and Ability.IsReady(item)
            and Ability.IsCastable(item,NPC.GetMana(h)) and act(h) then
            Ability.CastTarget(item,h)
            t.used=true
            s.castUntil=now+0.6
        end
        return true
    end
    if not safeToUse or not act(h) or now<s.castUntil then return false end
    for i,def in ipairs(supplies) do
        if needs[i] and not NPC.HasModifier(h,def.modifier)
            and now>=(s.use[def.name] or 0) then
            local item,slot=findItem(h,def.name)
            if item and slot<9 then
                if slot>=6 then
                    local front
                    for j=0,5 do if not itemAt(h,j) then front=j; break end end
                    -- Prefer the cheapest unequipped item when all slots are occupied.
                    if not front then
                        local cost=math.huge
                        for j=0,5 do
                            local other=itemAt(h,j)
                            local name=Ability.GetName(other)
                            if name~="item_flask" and name~="item_clarity"
                                and Item.GetCost(other)<cost then
                                front,cost=j,Item.GetCost(other)
                            end
                        end
                    end
                    if front then
                        s.swap={front=front,back=slot,original=itemIndex(itemAt(h,front)),
                            consumable=itemIndex(item),readyAt=now+6.2,deadline=now+12}
                        moveItem(h,item,front)
                        s.use[def.name]=now+10
                        return true
                    end
                elseif Item.IsItemEnabled(item) and Ability.IsReady(item)
                    and Ability.IsCastable(item,NPC.GetMana(h)) then
                    Ability.CastTarget(item,h)
                    s.use[def.name]=now+3
                    s.castUntil=now+0.6
                    return true
                end
            end
        end
    end
    return false
end

function script.OnUpdate()
    local h, player = Heroes.GetLocal(), Players.GetLocal()
    if not h or not player or NPC.GetUnitName(h)~="npc_dota_hero_phantom_lancer"
        or not Entity.IsAlive(h) then
        reset()
        return
    end
    if GameRules.IsPaused() then return end
    local now = GameRules.GetGameTime()
    if now<0 or now<s.next then return end
    s.next = now+0.25
    if not enable:Get() or not bind:IsToggled() then
        if s.swap then restore(h,now) else reset() end
        return
    end
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
    local mana=NPC.GetMana(h)*100/math.max(1,NPC.GetMaxMana(h))
    local regenSafe=safe(p(h))
    for _,creep in ipairs(neutrals) do
        if dist(p(h),p(creep))<850 then regenSafe=false; break end
    end
    local busy=false
    if autoRegen:Get() then
        busy=regen(h,player,now,hp,mana,regenSafe)
    elseif s.swap then
        busy=not restore(h,now)
    end
    if hp<=minHP:Get() then s.retreat=true end
    if hp>=90 then s.retreat=false end
    if busy and safe(p(h)) then return end
    if s.retreat or not safe(p(h)) then
        if s.camp then s.blocked[s.camp.key]=now+15 end
        s.camp=nil
        if s.home then for _,u in ipairs(units) do move(u,s.home,now) end end
        return
    end
    if busy then return end
    if autoRegen:Get() and not regenSafe and safe(p(h))
        and ((hp<50 and findItem(h,"item_flask"))
            or (mana<50 and findItem(h,"item_clarity"))) then
        if s.home then move(h,s.home,now) end
        return
    end
    if NPC.HasModifier(h,"modifier_flask_healing")
        or NPC.HasModifier(h,"modifier_clarity_potion") then
        -- Let regeneration complete outside the camp; avoid spending mana meanwhile.
        if not regenSafe and s.home then move(h,s.home,now) end
        return
    end
    if not act(h) or now<s.castUntil then return end
    -- Assign each visible living neutral to exactly one camp. An 800-radius
    -- scan used to count the same pack for neighbouring camps.
    local camps={}
    for _,handle in ipairs(Camps.GetAll() or {}) do
        local point=center(handle)
        local box=Camp.GetCampBox(handle)
        if point and box and box.min and box.max then
            local k=string.format("%.0f:%.0f",point.x,point.y)
            camps[#camps+1]={point=point,key=k,box=box,creeps={}}
        end
    end
    for _,creep in ipairs(neutrals) do
        local cp=p(creep)
        local best,bestScore
        for _,camp in ipairs(camps) do
            local box=camp.box
            local dx=math.max(box.min.x-cp.x,0,cp.x-box.max.x)
            local dy=math.max(box.min.y-cp.y,0,cp.y-box.max.y)
            local score=dx*dx+dy*dy
            local tie=dist(cp,camp.point)
            if tie<1000 and (not bestScore or score<bestScore
                or (score==bestScore and tie<dist(cp,best.point))) then
                best,bestScore=camp,score
            end
        end
        if best then best.creeps[#best.creeps+1]=creep end
    end
    local dotaTime=GameRules.GetDOTATime()
    local nextSpawn=now+(60-dotaTime%60)+1
    local current
    if s.camp then
        for _,camp in ipairs(camps) do
            if camp.key==s.camp.key then current=camp; break end
        end
        if not current or #current.creeps==0 then
            -- A cleared pack cannot be selected again before the next spawn.
            -- Hidden packs are also skipped until they become visible again.
            s.blocked[s.camp.key]=nextSpawn
            current=nil
        elseif not safe(current.point) then
            s.blocked[current.key]=now+15
            current=nil
        end
    end
    local function allowed(camp)
        if #camp.creeps==0 or not safe(camp.point)
            or dist(camp.point,s.anchor)>routeRadius:Get()
            or (s.blocked[camp.key] or 0)>now then return false end
        for _,creep in ipairs(camp.creeps) do
            if NPC.IsAncient(creep) and not ancients:Get() then return false end
        end
        return true
    end
    if current and not allowed(current) then current=nil end
    if not current then
        local bestScore=math.huge
        for _,camp in ipairs(camps) do
            if allowed(camp) then
                local score=dist(p(h),camp.point)
                if score<bestScore then current,bestScore=camp,score end
            end
        end
    end
    s.camp=current
    if not current then
        -- Wait outside spawn boxes so the hero/illusions do not block respawns.
        local function outside(point)
            for _,camp in ipairs(camps) do
                local box=camp.box
                if point.x>=box.min.x-64 and point.x<=box.max.x+64
                    and point.y>=box.min.y-64 and point.y<=box.max.y+64 then
                    return false
                end
            end
            return true
        end
        local waitingPoint=p(h)
        if not outside(waitingPoint) then
            waitingPoint=nil
            for radius=400,1200,400 do
                for i=0,7 do
                    local angle=i*math.pi/4
                    local candidate=Vector(p(h).x+math.cos(angle)*radius,
                        p(h).y+math.sin(angle)*radius,p(h).z)
                    if outside(candidate) and safe(candidate) then
                        waitingPoint=candidate
                        break
                    end
                end
                if waitingPoint then break end
            end
        end
        for _,u in ipairs(units) do
            if waitingPoint and (not outside(p(u)) or dist(p(u),waitingPoint)>200) then
                move(u,waitingPoint,now)
            elseif not s.waiting and act(u) then
                Player.HoldPosition(player,u,false,false,false,"pl_farm")
                s.orders[Entity.GetIndex(u)]=nil
            end
        end
        s.waiting=true
        return
    end
    s.waiting=false
    local list=current.creeps
    table.sort(list,function(a,b) return dist(p(h),p(a))<dist(p(h),p(b)) end)
    local target=list[1]
    for i=2,#units do attack(player,units[i],target,now) end
    local q=NPC.GetAbility(h,"phantom_lancer_spirit_lance")
    if useLance:Get() and #units<3 and Entity.GetHealth(target)>=300
        and not NPC.IsAttacking(h) and q and Ability.GetLevel(q)>0 and Ability.IsReady(q)
        and not NPC.IsSilenced(h) and Ability.IsCastable(q,NPC.GetMana(h))
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
