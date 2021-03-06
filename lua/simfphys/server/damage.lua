util.AddNetworkString( "simfphys_spritedamage" )
util.AddNetworkString( "simfphys_lightsfixall" )
util.AddNetworkString( "simfphys_backfire" )

local function Spark( pos , normal , snd )
	local effectdata = EffectData()
	effectdata:SetOrigin( pos - normal )
	effectdata:SetNormal( -normal )
	util.Effect( "stunstickimpact", effectdata, true, true )
	
	if snd then
		sound.Play(Sound( snd ), pos, 75)
	end
end

local function BloodEffect( pos )
	local effectdata = EffectData()
	effectdata:SetOrigin( pos )
	util.Effect( "BloodImpact", effectdata, true, true )
end

local function DestroyVehicle( ent )
	if not IsValid( ent ) then return end
	if ent.destroyed then return end
	
	ent.destroyed = true
	
	local ply = ent.EntityOwner
	
	local bprop = ents.Create( "gmod_sent_vehicle_fphysics_gib" )
	bprop:SetModel( ent:GetModel() )			
	bprop:SetPos( ent:GetPos() )
	bprop:SetAngles( ent:GetAngles() )
	bprop:Spawn()
	bprop:Activate()
	bprop:GetPhysicsObject():SetVelocity( ent:GetVelocity() + Vector(math.random(-5,5),math.random(-5,5),math.random(150,250)) ) 
	bprop:GetPhysicsObject():SetMass( ent.Mass * 0.75 )
	bprop.DoNotDuplicate = true
	bprop.MakeSound = true
	simfphys.SetOwner( ply , bprop )
	
	if IsValid( ply ) then
		undo.Create( "Gib" )
		undo.SetPlayer( ply )
		undo.AddEntity( bprop )
		undo.SetCustomUndoText( "Undone Gib" )
		undo.Finish( "Gib" )
		ply:AddCleanup( "Gibs", bprop )
	end
	
	if ent.CustomWheels == true then
		for i = 1, table.Count( ent.GhostWheels ) do
			local Wheel = ent.GhostWheels[i]
			if IsValid(Wheel) then
				local prop = ents.Create( "gmod_sent_vehicle_fphysics_gib" )
				prop:SetModel( Wheel:GetModel() )			
				prop:SetPos( Wheel:LocalToWorld( Vector(0,0,0) ) )
				prop:SetAngles( Wheel:LocalToWorldAngles( Angle(0,0,0) ) )
				prop:SetOwner( bprop )
				prop:Spawn()
				prop:Activate()
				prop:GetPhysicsObject():SetVelocity( ent:GetVelocity() + Vector(math.random(-5,5),math.random(-5,5),math.random(0,25)) )
				prop:GetPhysicsObject():SetMass( 20 )
				prop.DoNotDuplicate = true
				bprop:DeleteOnRemove( prop )
				
				simfphys.SetOwner( ply , prop )
			end
		end
	end
	
	local Driver = ent:GetDriver()
	if IsValid( Driver ) then
		if ent.RemoteDriver ~= Driver then
			Driver:Kill()
		end
	end
	
	if ent.PassengerSeats then
		for i = 1, table.Count( ent.PassengerSeats ) do
			local Passenger = ent.pSeat[i]:GetDriver()
			if IsValid( Passenger ) then
				Passenger:Kill()
			end
		end
	end
	
	ent:Extinguish() 
	ent:Remove()
end

local function DamageVehicle( ent , damage )
	if not simfphys.DamageEnabled then return end
	
	local MaxHealth = ent:GetMaxHealth()
	local CurHealth = ent:GetCurHealth()
	if CurHealth <= 0 then return end
	
	local NewHealth = math.max( math.Round(CurHealth - damage,0) , 0 )
	
	if NewHealth <= (MaxHealth * 0.6) then
		if NewHealth <= (MaxHealth * 0.3) then
			ent:SetOnFire( true )
			ent:SetOnSmoke( false )
		else
			ent:SetOnSmoke( true )
		end
	end
	
	if NewHealth <= 0 then DestroyVehicle( ent ) return end
	
	ent:SetCurHealth( NewHealth )
end

local function HurtPlayers( ent, damage )
	if not simfphys.pDamageEnabled then return end
	
	local Driver = ent:GetDriver()
	
	if IsValid( Driver ) then
		Driver:TakeDamage(damage, Entity(0), ent )
	end
	
	if ent.PassengerSeats then
		for i = 1, table.Count( ent.PassengerSeats ) do
			local Passenger = ent.pSeat[i]:GetDriver()
			
			if IsValid(Passenger) then
				Passenger:TakeDamage(damage, Entity(0), ent )
			end
		end
	end
end

local function bcDamage( vehicle , position , cdamage )
	if not simfphys.DamageEnabled then return end
	
	cdamage = cdamage or false
	net.Start( "simfphys_spritedamage" )
		net.WriteEntity( vehicle )
		net.WriteVector( position ) 
		net.WriteBool( cdamage ) 
	net.Broadcast()
end

local function onCollide( ent, data )
	if ( data.Speed > 60 && data.DeltaTime > 0.2 ) then
		
		local pos = data.HitPos
		
		if (data.Speed > 1000) then
			Spark( pos , data.HitNormal , "MetalVehicle.ImpactHard" )
			
			HurtPlayers( ent , 5 )
			
			ent:TakeDamage( (data.Speed / 7) * simfphys.DamageMul, Entity(0), Entity(0) )
			
			bcDamage( ent , ent:WorldToLocal( pos ) , true )
		else
			Spark( pos , data.HitNormal , "MetalVehicle.ImpactSoft" )
			
			if data.Speed > 250 then
				local hitent = data.HitEntity:IsPlayer()
				if not hitent then
					bcDamage( ent , ent:WorldToLocal( pos ) , true )
					
					if simfphys.DamageMul > 1 then
						ent:TakeDamage( (data.Speed / 28) * simfphys.DamageMul, Entity(0), Entity(0) )
					end
				end
			end
			
			if data.Speed > 500 then
				HurtPlayers( ent , 2 )
				ent:TakeDamage( (data.Speed / 14) * simfphys.DamageMul, Entity(0), Entity(0) )
			end
		end
	end
end

local function OnDamage( ent, dmginfo )
	ent:TakePhysicsDamage( dmginfo )
	
	if not ent:IsInitialized() then return end
	
	local Damage = dmginfo:GetDamage() 
	local DamagePos = dmginfo:GetDamagePosition() 
	local Type = dmginfo:GetDamageType()
	local Driver = ent:GetDriver()
	
	bcDamage( ent , ent:WorldToLocal( DamagePos ) )
	
	local Mul = 1
	if Type == DMG_BLAST then
		Mul = 10
	end
	
	if Type == DMG_BULLET then
		Mul = 2
	end
	
	DamageVehicle( ent , Damage * Mul )
	
	if ent.IsArmored then return end
	
	if IsValid(Driver) then
		local Distance = (DamagePos - Driver:GetPos()):Length() 
		if (Distance < 70) then
			local Damage = (70 - Distance) / 22
			dmginfo:ScaleDamage( Damage )
			Driver:TakeDamageInfo( dmginfo )
			BloodEffect( DamagePos )
		end
	end
	
	if ent.PassengerSeats then
		for i = 1, table.Count( ent.PassengerSeats ) do
			local Passenger = ent.pSeat[i]:GetDriver()
			
			if IsValid(Passenger) then
				local Distance = (DamagePos - Passenger:GetPos()):Length()
				local Damage = (70 - Distance) / 22
				if (Distance < 70) then
					dmginfo:ScaleDamage( Damage )
					Passenger:TakeDamageInfo( dmginfo )
					BloodEffect( DamagePos )
				end
			end
		end
	end
end

hook.Add( "OnEntityCreated", "simfphys_damagestuff", function( ent )
	if simfphys.IsCar( ent ) then
		timer.Simple( 0.2, function()
			if not IsValid( ent ) then return end
			
			local Health = math.floor(ent.MaxHealth and ent.MaxHealth or (1000 + ent:GetPhysicsObject():GetMass() / 3))
			
			ent:SetMaxHealth( Health )
			ent:SetCurHealth( Health )
			
			ent.PhysicsCollide = onCollide
			ent.OnTakeDamage = OnDamage
		end)
	end
end)
