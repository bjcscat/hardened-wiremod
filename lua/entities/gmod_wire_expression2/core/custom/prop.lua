/******************************************************************************\
Restricted Prop Core by brined
\******************************************************************************/

E2Lib.RegisterExtension("propcore", false, "Allows E2 chips to create and manipulate props", "Can be used to teleport props to arbitrary locations, including other player's faces")
PropCore = {}
local sbox_E2_maxProps = CreateConVar( "sbox_E2_maxProps", "-1", FCVAR_ARCHIVE )
local sbox_E2_maxPropsPerSecond = CreateConVar( "sbox_E2_maxPropsPerSecond", "4", FCVAR_ARCHIVE )
local sbox_E2_PropCore = CreateConVar( "sbox_E2_PropCore", "2", FCVAR_ARCHIVE ) -- 2: Players can affect their own props, 1: Only admins, 0: Disabled
local sbox_E2_PropDiff = CreateConVar( "sbox_E2_PropCoreMaxDiff", "300", FCVAR_ARCHIVE )

local E2totalspawnedprops = 0
local E2tempSpawnedProps = 0
local TimeStamp = 0
local playerMeta = FindMetaTable("Player")

local function TempReset()
 if (CurTime()>= TimeStamp) then
	E2tempSpawnedProps = 0
	TimeStamp = CurTime()+1
 end
end
hook.Add("Think","TempReset",TempReset)

function PropCore.WithinPropcoreLimits()
	return (sbox_E2_maxProps:GetInt() <= 0 or E2totalspawnedprops<sbox_E2_maxProps:GetInt()) and E2tempSpawnedProps < sbox_E2_maxPropsPerSecond:GetInt()
end

function PropCore.ValidSpawn(ply, model, isVehicle)
	return false
end

local canHaveInvalidPhysics = {
	delete=true, parent=true, deparent=true, solid=true,
	shadow=true, draw=true, use=true, pos=true, ang=true,
	manipulate=true
}
function PropCore.ValidAction(self, entity, cmd)
	if(cmd=="spawn" or cmd=="Tdelete") then return true end
	if(!IsValid(entity)) then return false end
	if(!canHaveInvalidPhysics[cmd] and !validPhysics(entity)) then return false end
	if(!isOwner(self, entity)) then return false end
	if entity:IsPlayer() then return false end

	-- make sure we can only perform the same action on this prop once per tick
	-- to prevent spam abuse
	if not entity.e2_propcore_last_action then
		entity.e2_propcore_last_action = {}
	end
	if 	entity.e2_propcore_last_action[cmd] and
		entity.e2_propcore_last_action[cmd] == CurTime() then return false end
	entity.e2_propcore_last_action[cmd] = CurTime()

	local ply = self.player
	return sbox_E2_PropCore:GetInt()==2 or (sbox_E2_PropCore:GetInt()==1 and ply:IsAdmin())
end

local function MakePropNoEffect(...)
	local backup = DoPropSpawnedEffect
	DoPropSpawnedEffect = function() end
	local ret = MakeProp(...)
	DoPropSpawnedEffect = backup
	return ret
end

function PropCore.CanManipulateProp(self,prop)
	local tracedLine = util.QuickTrace(self.entity:GetPos(),prop:GetPos()-self.entity:GetPos(),self.entity)
	if tracedLine.Entity == prop:GetEntity() then
		return true
	end
	return false
end

function PropCore.PhysManipulate(self, this, pos, rot, freeze, gravity, notsolid)
	local phys = this:GetPhysicsObject()
	local physOrThis = IsValid(phys) and phys or this
	if not PropCore.CanManipulateProp(self,physOrThis) then return end
	if pos ~= nil then 
		local currentPos = self.entity:GetPos() -- get current chip pos
		local distMagnitude = math.abs(pos[1]-currentPos[1]+pos[2]-currentPos[2]+pos[3]-currentPos[3]) -- get distance
		if distMagnitude <= sbox_E2_PropDiff:GetInt() then -- check distance
			WireLib.setPos( physOrThis, Vector( pos[1],pos[2],pos[3] ) )
		end 
	end
	if rot ~= nil then 
		WireLib.setAng( physOrThis, Angle( rot[1],rot[2],rot[3] ) ) 
	end

	if IsValid( phys ) then
		if freeze ~= nil and this:GetUnFreezable() ~= true then phys:EnableMotion( freeze == 0 ) end
		if gravity ~= nil then phys:EnableGravity( gravity ~= 0 ) end
		if notsolid ~= nil then this:SetSolid( notsolid ~= 0 and SOLID_NONE or SOLID_VPHYSICS ) end
		phys:Wake()
	end
end

--------------------------------------------------------------------------------

__e2setcost(10)
e2function void entity:propDelete()
	if not PropCore.ValidAction(self, this, "delete") then return end
	this:Remove()
end

e2function void entity:use()
	if not PropCore.ValidAction(self, this, "use") then return end
	
	local ply = self.player

	if not isOwner(self,this) then return end

	if not IsValid(ply) then return end -- if the owner isn't connected to the server, do nothing

	if not hook.Run( "PlayerUse", ply, this ) then return end
	if this.Use then
		this:Use(ply,ply,USE_ON,0)
	else
		this:Fire("use","1",0)
	end
end

__e2setcost(30)
local function removeAllIn( self, tbl )
	local count = 0
	for k,v in pairs( tbl ) do
		if (IsValid(v) and isOwner(self,v) and !v:IsPlayer()) then
			count = count + 1
			v:Remove()
		end
	end
	return count
end

e2function number table:propDelete()
	if not PropCore.ValidAction(self, nil, "Tdelete") then return 0 end

	local count = removeAllIn( self, this.s )
	count = count + removeAllIn( self, this.n )

	self.prf = self.prf + count

	return count
end

e2function number array:propDelete()
	if not PropCore.ValidAction(self, nil, "Tdelete") then return 0 end

	local count = removeAllIn( self, this )

	self.prf = self.prf + count

	return count
end

__e2setcost(10)

--------------------------------------------------------------------------------
e2function void entity:propManipulate(vector pos, angle rot, number freeze, number gravity, number notsolid)
	if not PropCore.ValidAction(self, this, "manipulate") then return end
	PropCore.PhysManipulate(self,this, pos, rot, freeze, gravity, notsolid)
end

e2function void entity:propFreeze(number freeze)
	if not PropCore.ValidAction(self, this, "freeze") then return end
	PropCore.PhysManipulate(self,this, nil, nil, freeze, nil, nil)
end

e2function void entity:propNotSolid(number notsolid)
	if not PropCore.ValidAction(self, this, "solid") then return end
	PropCore.PhysManipulate(self,this, nil, nil, nil, nil, notsolid)
end

--- Makes <this> not render at all
e2function void entity:propDraw(number drawEnable)
	if not PropCore.ValidAction(self, this, "draw") then return end
	this:SetNoDraw( drawEnable == 0 )
end

--- Makes <this>'s shadow not render at all
e2function void entity:propShadow(number shadowEnable)
	if not PropCore.ValidAction(self, this, "shadow") then return end
	this:DrawShadow( shadowEnable ~= 0 )
end

e2function void entity:propGravity(number gravity)
	if not PropCore.ValidAction(self, this, "gravity") then return end
	local physCount = this:GetPhysicsObjectCount()
	if physCount > 1 then
		for physID = 0, physCount - 1 do
			local phys = this:GetPhysicsObjectNum(physID)
			if IsValid(phys) then phys:EnableGravity( gravity ~= 0 ) end
		end
	else
		PropCore.PhysManipulate(self,this, nil, nil, nil, gravity, nil)
	end
end

e2function void entity:propDrag( number drag )
	if not PropCore.ValidAction(self, this, "drag") then return end
	local phys = this:GetPhysicsObject()
	if IsValid( phys ) then
		phys:EnableDrag( drag ~= 0 )
	end
end

e2function void entity:propInertia( vector inertia )
	if not PropCore.ValidAction(self, this, "inertia") then return end
	if Vector( inertia[1], inertia[2], inertia[3] ):IsZero() then return end
	local phys = this:GetPhysicsObject()
	if IsValid( phys ) then
		phys:SetInertia(Vector(inertia[1], inertia[2], inertia[3]))
	end
end

e2function void entity:propSetBuoyancy(number buoyancy)
	if not PropCore.ValidAction(self, this, "buoyancy") then return end
	local phys = this:GetPhysicsObject()
	if IsValid( phys ) then
		phys:SetBuoyancyRatio( math.Clamp(buoyancy, 0, 1) )
	end
end

e2function void entity:propSetFriction(number friction)
	if not PropCore.ValidAction(self, this, "friction") then return end
	this:SetFriction( math.Clamp(friction, -1000, 1000) )
end

e2function number entity:propGetFriction()
	if not PropCore.ValidAction(self, this, "friction") then return 0 end
	return this:GetFriction()
end

e2function void entity:propSetElasticity(number elasticity)
	if not PropCore.ValidAction(self, this, "elasticity") then return end
	this:SetElasticity( math.Clamp(elasticity, -1000, 1000) )
end

e2function number entity:propGetElasticity()
	if not PropCore.ValidAction(self, this, "elasticity") then return 0 end
	return this:GetElasticity()
end

e2function void entity:propMakePersistent(number persistent)
	if not PropCore.ValidAction(self, this, "persist") then return end
	if GetConVarString("sbox_persist") == "0" then return end
	if not gamemode.Call("CanProperty", self.player, "persist", this) then return end
	this:SetPersistent(persistent ~= 0)
end

e2function void entity:propPhysicalMaterial(string physprop)
	if not PropCore.ValidAction(self, this, "physprop") then return end
	construct.SetPhysProp(self.player, this, 0, nil, {nil, Material = physprop})
end

e2function string entity:propPhysicalMaterial()
	if not PropCore.ValidAction(self, this, "physprop") then return "" end
	local phys = this:GetPhysicsObject()
	if IsValid(phys) then return phys:GetMaterial() or "" end
	return ""
end

e2function void entity:propSetVelocity(vector velocity)
	if not PropCore.ValidAction(self, this, "velocitynxt") then return end
	local phys = this:GetPhysicsObject()
	if IsValid( phys ) then
		phys:SetVelocity(Vector(velocity[1], velocity[2], velocity[3]))
	end
end

e2function void entity:propSetVelocityInstant(vector velocity)
	if not PropCore.ValidAction(self, this, "velocityins") then return end
	local phys = this:GetPhysicsObject()
	if IsValid( phys ) then
		phys:SetVelocityInstantaneous(Vector(velocity[1], velocity[2], velocity[3]))
	end
end

--------------------------------------------------------------------------------

__e2setcost(20)
e2function void entity:setPos(vector pos)
	if not PropCore.ValidAction(self, this, "pos") then return end
	PropCore.PhysManipulate(self,this, pos, nil, nil, nil, nil)
end

e2function void entity:setAng(angle rot)
	if not PropCore.ValidAction(self, this, "ang") then return end
	PropCore.PhysManipulate(self,this, nil, rot, nil, nil, nil)
end

e2function void entity:rerotate(angle rot) = e2function void entity:setAng(angle rot)

--------------------------------------------------------------------------------

local function getChildLength(curchild, count)
	local max = 0
	for _, v in pairs(curchild:GetChildren()) do
		max = math.max(max, getChildLength(v, count + 1))
	end
	return math.max(max, count)
end

-- Checks if there is recursive parenting, if so then returns false
-- Also checks if parent/child chain length is > 16, and if so, hard errors.
local function parent_check( self, child, parent )
	local parents = 0
	while parent:IsValid() do
		parents = parents + 1
		parent = parent:GetParent()
	end

	return ( parents + getChildLength(child, 1) ) <= 16
end

local function parent_antispam( child )
	if (child.E2_propcore_antispam or 0) > CurTime() then
		return false
	end

	child.E2_propcore_antispam = CurTime() + 0.06
	return true
end

e2function void entity:parentTo(entity target)
	if not PropCore.ValidAction(self, this, "parent") then return self:throw("You do not have permission to parent to this prop!", nil) end
	if not IsValid(target) then return self:throw("Target prop is invalid.", nil) end
	if not isOwner(self, target) then return self:throw("You do not own the target prop!", nil) end
	if not parent_antispam( this ) then return self:throw("You are parenting too fast!", nil) end
	if this == target then return self:throw("You cannot parent a prop to itself") end
	if not parent_check( self, this, target ) then return self:throw("Parenting chain of entities can't exceed 16 or crash may occur", nil) end

	this:SetParent(target)
end

__e2setcost(5)
e2function void entity:deparent()
	if not PropCore.ValidAction(self, this, "deparent") then return end
	if not IsValid(target) then return self:throw("Target prop is invalid.", nil) end
	if not isOwner(self, target) then return self:throw("You do not own the targeted prop!", nil) end
	this:SetParent( nil )
end
e2function void entity:parentTo() = e2function void entity:deparent()
