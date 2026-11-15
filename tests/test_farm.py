import sys,re,pathlib
from lupa import LuaRuntime
lua=LuaRuntime()
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'phantom_lancer_farm.lua').read_text()
lua.execute('''
widgets={}; calls={}; now=100
local w={}
function w:Create() return self end
function w:Switch(n,d) local v={value=d}; function v:Get() return self.value end; widgets[n]=v; return v end
function w:Slider(n,a,b,d) return self:Switch(n,d) end
function w:Bind(n) local v=self:Switch(n,false); function v:IsToggled() return self.value end; function v:Properties() end; return v end
Menu={Create=function() return w end}
Enum={GroupSide={Left=0},ButtonCode={KEY_NONE=0}}
function Vector(x,y,z) return {x=x,y=y,z=z} end
h={name='npc_dota_hero_phantom_lancer',team=2,id=1,hp=100,point=Vector(0,0,0)}
n={name='neutral',team=4,id=2,hp=100,point=Vector(100,0,0),neutral=true}
f={name='fountain',team=2,id=3,hp=100,point=Vector(-1000,0,0)}
e={name='enemy',team=3,id=4,hp=100,point=Vector(200,0,0)}
heroList={h}; npcList={h,n,f}
Heroes={GetLocal=function() return h end,GetAll=function() return heroList end}
NPCs={GetAll=function()return npcList end}
Players={GetLocal=function() return {} end}
Entity={GetAbsOrigin=function(u)return u.point end,GetIndex=function(u)return u.id end,
IsAlive=function(u)return u.hp>0 end,IsDormant=function()return false end,
GetTeamNum=function(u)return u.team end,GetHealth=function(u)return u.hp end,GetMaxHealth=function()return 100 end}
NPC={GetUnitName=function(u)return u.name end,IsStunned=function()return false end,
IsChannellingAbility=function()return false end,IsVisible=function()return true end,
IsIllusion=function()return false end,IsNeutral=function(u)return u.neutral end,
IsWaitingToSpawn=function()return false end,IsAncient=function()return false end,
IsAttacking=function()return false end,GetAbility=function()return nil end,
MoveTo=function(u,point) calls[#calls+1]={kind='move',point=point} end}
Player={GetPlayerID=function()return 0 end,AttackTarget=function(player,u,target)calls[#calls+1]={kind='attack',target=target.id} end,HoldPosition=function()calls[#calls+1]={kind='hold'}end}
GameRules={IsPaused=function()return false end,GetGameTime=function()return now end,GetDOTATime=function()return now end}
Camps={GetAll=function()return {1}end}
Camp={GetCampBox=function()return {min=Vector(50,-50,0),max=Vector(150,50,0)}end}
''')
lua.execute("""
NPC.GetMana=function()return 100 end
NPC.GetMaxMana=function()return 100 end
NPC.GetItemByIndex=function(u,slot)return u.items and u.items[slot] end
NPC.GetItem=function()return nil end
NPC.HasModifier=function(u,name)return u.mods and u.mods[name] or false end
Couriers={GetLocal=function()return nil end}
Player.GetTotalGold=function()return 0 end
GameRules.GetStockCount=function()return 5 end
Engine={RunScript=function(js) calls[#calls+1]={kind='js',js=js}; return true end}
Ability={GetName=function(i)return i.name end,IsReady=function()return true end,
IsCastable=function()return true end,CastTarget=function(i,u)
 calls[#calls+1]={kind='cast',item=i.name}; u.mods=u.mods or {}; u.mods[i.mod]=true end}
Item={IsItemEnabled=function()return true end,GetCost=function(i)return i.cost or 100 end}
""")
lua.execute("Log={Write=function()end}")
script=lua.execute(source)
lua.execute("widgets['Проверять лагеря без обзора'].value=false")
script.OnUpdate();assert len(lua.globals().calls)==0
lua.execute("widgets['Включить'].value=true; widgets['Автофарм'].value=true")
script.OnUpdate();assert lua.globals().calls[1]['kind']=='attack'
lua.execute('now=101; h.hp=20')
script.OnUpdate();assert lua.globals().calls[2]['kind']=='move'
assert lua.globals().calls[2]['point']['x']==-1000
lua.execute('now=117; h.hp=95')
script.OnUpdate();assert lua.globals().calls[3]['kind']=='attack'
lua.execute('now=118; heroList={h,e}')
script.OnUpdate();assert lua.globals().calls[4]['kind']=='move'
script.OnGameEnd()
import zipfile
with zipfile.ZipFile(root/'references/umbrella-lua.zip') as z:
    api='\n'.join(z.read(n).decode() for n in z.namelist() if n.endswith('.md'))
missing=[x for x in set(re.findall(r'\b(?:NPC|Entity|Heroes|Players|Player|Camp|Camps|GameRules|Ability)\.\w+',source)) if x+'(' not in api]
assert not missing,missing
print('PASS: Lua syntax, API names, disabled mode, farming, low HP retreat, recovery, enemy retreat, reset')

# Purchase once below threshold; neither resource at exactly 50%.
script.OnGameEnd()
lua.execute("heroList={h}; h.hp=50; NPC.GetMana=function()return 50 end; calls={}; now=200; Player.GetTotalGold=function()return 500 end")
script.OnUpdate(); assert not any(lua.globals().calls[i]['kind']=='js' for i in range(1,len(lua.globals().calls)+1))
lua.execute('h.hp=49; NPC.GetMana=function()return 49 end; now=201')
script.OnUpdate(); assert 'AbilityIndex:39' in lua.globals().calls[len(lua.globals().calls)]['js']
lua.execute('now=202')
script.OnUpdate(); assert 'AbilityIndex:38' in lua.globals().calls[len(lua.globals().calls)]['js']
# Ready consumable self cast; active modifier prevents a second cast.
script.OnGameEnd()
lua.execute("now=300; Player.GetTotalGold=function()return 0 end; calls={}; h.point=Vector(-1500,0,0); h.items={[0]={name='item_flask',id=10,mod='modifier_flask_healing'}}; h.mods={}")
script.OnUpdate(); assert lua.globals().calls[len(lua.globals().calls)]['kind']=='cast'
lua.execute('now=301')
script.OnUpdate(); assert sum(lua.globals().calls[i]['kind']=='cast' for i in range(1,len(lua.globals().calls)+1))==1
# Backpack swap waits six seconds and restores exact original item after cast.
script.OnGameEnd()
lua.execute("""
now=400; calls={}; h.mods={}; h.items={}
for i=0,5 do h.items[i]={name='item_branch',id=20+i,cost=50+i} end
h.items[6]={name='item_flask',id=10,mod='modifier_flask_healing'}
Engine.RunScript=function(js)
 calls[#calls+1]={kind='js',js=js}
 local slot=tonumber(js:match('TargetIndex:(%d+)'))
 local id=tonumber(js:match('AbilityIndex:(%d+)'))
 if js:find('MOVE_ITEM') then
  for i=0,14 do if h.items[i] and h.items[i].id==id then
   h.items[i],h.items[slot]=h.items[slot],h.items[i]; break end end
 end
 return true
end
""")
script.OnUpdate(); assert lua.globals().h['items'][0]['id']==10
lua.execute('now=405')
script.OnUpdate(); assert not lua.globals().h['mods']['modifier_flask_healing']
lua.execute('now=407')
script.OnUpdate(); assert lua.globals().h['mods']['modifier_flask_healing']
lua.execute('now=408')
script.OnUpdate(); assert lua.globals().h['items'][0]['id']==20
print('PASS: 50% threshold, independent purchases, modifier guard, backpack delay, self-cast and restore')

script.OnGameEnd()
lua.execute("""
now=500; calls={}; h.hp=100; h.mods={}; h.items={}; h.point=Vector(0,0,0)
NPC.GetMana=function()return 100 end
n.hp=100; n.point=Vector(100,0,0)
n2={name='neutral',team=4,id=5,hp=100,point=Vector(700,0,0),neutral=true}
npcList={h,n,n2,f}; heroList={h}
Camps.GetAll=function()return {1,2}end
Camp.GetCampBox=function(c)
 local x=c==1 and 100 or 700
 return {min=Vector(x-20,-20,0),max=Vector(x+20,20,0)}
end
""")
script.OnUpdate(); assert lua.globals().calls[1]['target']==2
lua.execute('now=502; n.hp=0')
script.OnUpdate(); assert lua.globals().calls[len(lua.globals().calls)]['target']==5
lua.execute('now=504; n2.hp=0')
script.OnUpdate(); assert lua.globals().calls[len(lua.globals().calls)]['kind']=='hold'
count=len(lua.globals().calls)
lua.execute('now=506')
script.OnUpdate(); assert len(lua.globals().calls)==count
lua.execute('now=541; n.hp=100')
script.OnUpdate(); assert lua.globals().calls[len(lua.globals().calls)]['target']==2
script.OnGameEnd()
lua.execute("now=550; calls={}; n2.hp=100; NPC.IsVisible=function(u)return u~=n end")
script.OnUpdate(); assert lua.globals().calls[1]['target']==5
print('PASS: unique camp assignment, dead/empty pack rejection, next camp, idle without packs, respawn and fog')
script.OnGameEnd()
lua.execute('now=560; calls={}; n.hp=0; n2.hp=0; h.point=Vector(100,0,0)')
script.OnUpdate()
assert lua.globals().calls[1]['kind']=='move'
point=lua.globals().calls[1]['point']
assert not (16<=point['x']<=184 and -84<=point['y']<=84)
print('PASS: leaves spawn box while waiting')

script.OnGameEnd()
lua.execute("""
widgets['Проверять лагеря без обзора'].value=true
now=600; calls={}; h.point=Vector(-500,0,0); n.hp=0; n2.hp=0
""")
script.OnUpdate(); assert lua.globals().calls[1]['kind']=='move'
assert lua.globals().calls[1]['point']['x']==100
lua.execute('now=602; h.point=Vector(100,0,0)')
script.OnUpdate()
lua.execute('now=604')
script.OnUpdate()
lua.execute('now=605')
script.OnUpdate(); assert lua.globals().calls[len(lua.globals().calls)]['point']['x']==700
lua.execute('now=607; n2.hp=100; NPC.IsVisible=function()return true end')
script.OnUpdate(); assert lua.globals().calls[len(lua.globals().calls)]['target']==5
print('PASS: scouts without vision, skips confirmed empty camp, attacks newly revealed pack')
