"""Runtime tests for the direct adaptation of the supplied Morphling script."""
import pathlib, re, zipfile
from lupa import LuaRuntime
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'phantom_lancer_farm.lua').read_text()
lua=LuaRuntime()
lua.execute('''
logs={}; calls={}; widgets={}
Log={Write=function(text)logs[#logs+1]=text end}
local methods={}
function methods:Create()return self end
function methods:Icon()return self end
function methods:ToolTip()return self end
function methods:Properties()return self end
function methods:Disabled()return self end
function methods:Gear()return self end
function methods:SetCallback()return self end
function methods:Switch(name,default)
 local v=setmetatable({value=default},{__index=methods}); widgets[name]=v; return v
end
function methods:Slider(name,a,b,d)return self:Switch(name,d)end
function methods:Bind(name)return self:Switch(name,false)end
function methods:MultiSelect(name)return self:Switch(name,false)end
function methods:Get()return self.value end
function methods:IsToggled()return self.value end
local menu=setmetatable({},{__index=methods})
Menu={Find=function()return nil end,Create=function()return menu end}
Enum={GroupSide={Left=0,Right=1},ButtonCode={KEY_NONE=0},FontCreate={FONTFLAG_ANTIALIAS=0},TeamNum={TEAM_RADIANT=2,TEAM_DIRE=3},TeamType={TEAM_ENEMY=1}}
Render={LoadFont=function()return 1 end,LoadImage=function()return nil end}
Config={ReadInt=function(section,key,default)return default end}
local vm={}
function Vector(x,y,z)return setmetatable({x=x,y=y,z=z},{__index=vm})end
function vm:DistanceSqr2D(b)return (self.x-b.x)^2+(self.y-b.y)^2 end
function vm:Distance2D(b)return math.sqrt(self:DistanceSqr2D(b))end
function vm:IsInRange2D(b,r)return self:DistanceSqr2D(b)<=r*r end
function vm:ClosestToPoint(list)
 local best,d=nil,math.huge
 for _,u in ipairs(list)do local v=self:DistanceSqr2D(u.pos);if v<d then best,d=u,v end end
 return best
end
h={name='npc_dota_hero_phantom_lancer',team=2,pos=Vector(0,0,0),hp=100}
n={name='neutral',team=4,pos=Vector(150,0,0),hp=100,neutral=true}
i={name=h.name,team=2,pos=Vector(30,0,0),hp=100,illusion=true}
npcs={h,n,i}; camp={}
Entity={GetAbsOrigin=function(u)return u.pos end,GetUnitName=function(u)return u.name end,
GetTeamNum=function(u)return u.team end,IsAlive=function(u)return u.hp>0 end,
GetHeroesInRadius=function()return {} end,IsDormant=function()return false end,GetHealth=function(u)return u.hp end,GetMaxHealth=function()return 100 end}
NPC={GetUnitName=Entity.GetUnitName,IsNeutral=function(u)return u.neutral end,
IsWaitingToSpawn=function()return false end,IsIllusion=function(u)return u.illusion end,
IsControllableByPlayer=function()return true end,GetSecondsPerAttack=function()return 1 end,
GetMana=function()return 100 end,GetMaxMana=function()return 100 end,
GetAbility=function()return nil end,IsSilenced=function()return false end,IsStunned=function()return false end,
GetItem=function()return nil end,MoveTo=function(u,p)calls[#calls+1]={kind='move',unit=u}end}
NPCs={GetAll=function(filter)
 if not filter then return npcs end
 local out={}; for _,u in ipairs(npcs)do if filter(u)then out[#out+1]=u end end;return out end}
Player={GetPlayerID=function()return 0 end,AttackTarget=function(p,u,t)calls[#calls+1]={kind='attack',unit=u,target=t}end}
Players={GetLocal=function()return {} end}
Heroes={GetLocal=function()return h end,InRadius=function()return {} end}
Camps={GetAll=function()return {camp}end,Contains=function(c)return c==camp end}
Camp={GetCampBox=function()return {min=Vector(100,-50,0),max=Vector(200,50,0)}end}
GameRules={GetGameTime=function()return 100 end,GetDOTATime=function()return 100 end,IsPaused=function()return false end}
''')
# Expose internals in memory only; production continues to export callbacks alone.
script=lua.execute(source.rsplit('return script',1)[0]+'''script.test={state=state,ui=ui,farm=farm_attack,select=select_camp,retreat=retreat};return script''')
ui=script.test.ui
assert not ui.farm_lance.Get(ui.farm_lance)
assert not ui.escape_doppel.Get(ui.escape_doppel)
assert ui.farm_mana is None
ui.enable.value=True
ui.key.value=True
ui.clarity.value=False
script.OnUpdate()
assert len(lua.globals().calls)==2
assert all(lua.globals().calls[k]['kind']=='attack' for k in (1,2))
assert lua.eval('calls[1].unit==h and calls[2].unit==i')
# Continuous melee attack: no ranged kiting/move between attacks.
script.test.farm(lua.globals().h,lua.globals().n,lua.table_from([lua.globals().n]),100.2)
assert len(lua.globals().calls)==2
lua.execute('n.hp=0; calls={}; GameRules.GetGameTime=function()return 102 end')
script.OnUpdate()
assert script.test.state.camp is None
assert len(lua.globals().calls)==0
lua.execute('calls={}; h.name="npc_dota_hero_morphling"')
script.OnUpdate()
assert len(lua.globals().calls)==0
with zipfile.ZipFile(root/'references/umbrella-lua.zip') as z:
    api='\n'.join(z.read(n).decode() for n in z.namelist() if n.endswith('.md'))
missing=[x for x in set(re.findall(r'\b(?:NPC|NPCs|Entity|Heroes|Players|Player|Camp|Camps|GameRules|Ability|PowerTreads)\.\w+',source)) if x+'(' not in api]
assert not missing, missing
assert not re.search(r'"morphling_(?:waveform|adaptive_strike_agi|morph_str)"',source)
print('PASS: load, PL gate, original menu/camp loop, melee attacks, owned illusions, empty camp, no ranged kiting, no mana slider, API names')

# PL abilities use correct cast types and respect their explicit switches.
lua.execute("""
h.name='npc_dota_hero_phantom_lancer'; n.hp=100; calls={}
q={name='phantom_lancer_spirit_lance'}; w={name='phantom_lancer_doppelwalk'}
Ability={GetLevel=function()return 1 end,IsCastable=function()return true end,
GetCastRange=function()return 600 end,GetCastPoint=function()return 0.3 end,
CastTarget=function(a,t)calls[#calls+1]={kind='lance',target=t}end,
CastPosition=function(a,p)calls[#calls+1]={kind='doppel',point=p}end}
NPC.GetAbility=function(u,name)if name==q.name then return q elseif name==w.name then return w end end
GameRules.GetGameTime=function()return 105 end
""")
ui.farm_lance.value=True
script.OnUpdate()
assert lua.globals().calls[len(lua.globals().calls)]['kind']=='lance'
ui.escape_doppel.value=True
lua.execute("""
local mt=getmetatable(h.pos).__index
function mt:Extend2D(b,d)
 local length=self:Distance2D(b)
 return Vector(self.x+(b.x-self.x)*d/length,self.y+(b.y-self.y)*d/length,self.z)
end
""")
script.test.retreat(lua.globals().h,lua.globals().n,lua.eval('Vector(-1000,0,0)'),100,110)
assert lua.globals().calls[len(lua.globals().calls)]['kind']=='doppel'
print('PASS: optional Spirit Lance targets neutrals; optional Doppelganger casts toward safety')
