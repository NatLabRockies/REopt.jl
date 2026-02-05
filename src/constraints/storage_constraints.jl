# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_storage_size_constraints(m, p, b; _n="")
    # TODO add formal types for storage (i.e. "b")

	# Constraint (4b)-1: Lower bound on Storage Energy Capacity
	@constraint(m,
        m[Symbol("dvStorageEnergy"*_n)][b] >= p.s.storage.attr[b].min_kwh
    )

	# Constraint (4b)-2: Upper bound on Storage Energy Capacity
	@constraint(m,
        m[Symbol("dvStorageEnergy"*_n)][b] <= p.s.storage.attr[b].max_kwh
    )

	# Constraint (4c)-1: Lower bound on Storage Power Capacity
	@constraint(m,
        m[Symbol("dvStoragePower"*_n)][b] >= p.s.storage.attr[b].min_kw
    )

	# Constraint (4c)-2: Upper bound on Storage Power Capacity
	@constraint(m,
        m[Symbol("dvStoragePower"*_n)][b] <= p.s.storage.attr[b].max_kw
    )

	# Constraint (4c)-3: Limit on ElectricStorage Energy Capacity based on Duration Hours
    if p.s.storage.attr[b] isa ElectricStorage
        @constraint(m,
            m[Symbol("dvStorageEnergy"*_n)][b] <= m[Symbol("dvStoragePower"*_n)][b] * p.s.storage.attr[b].max_duration_hours
        )

        @constraint(m,
            m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvStoragePower"*_n)][b] * p.s.storage.attr[b].min_duration_hours
        )
    end    


end


function add_general_storage_dispatch_constraints(m, p, b; _n="")
    # Constraint (4a): initial and final state of charge
    if hasproperty(p.s.storage.attr[b], :optimize_soc_init_fraction) && p.s.storage.attr[b].optimize_soc_init_fraction
        @info "\nOptimizing "*b*" inital SOC and constraining initial SOC = final SOC. soc_init_fraction will not apply.\n"
        @constraint(m,
            m[Symbol("dvStoredEnergy"*_n)][b, 0] == m[:dvStoredEnergy][b, maximum(p.time_steps)]
        )
    else
        @constraint(m,
            m[Symbol("dvStoredEnergy"*_n)][b, 0] == p.s.storage.attr[b].soc_init_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
        )
        # TODO: constrain final soc to equal initial soc even when not optimized (ran into feasibility issues)
        # @constraint(m,
        #     m[Symbol("dvStoredEnergy"*_n)][b, maximum(p.time_steps)] == p.s.storage.attr[b].soc_init_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
        # )
    end

    #Constraint (4n): State of charge upper bound is storage system size
    @constraint(m, [ts in p.time_steps],
        m[Symbol("dvStoredEnergy"*_n)][b,ts] <= m[Symbol("dvStorageEnergy"*_n)][b]
    )

    # Constraint (4j): Minimum state of charge
	@constraint(m, [ts in p.time_steps],
        m[Symbol("dvStoredEnergy"*_n)][b, ts] >= p.s.storage.attr[b].soc_min_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
    )

    #Constraint (4j): Dispatch from storage is no greater than power capacity
	@constraint(m, [ts in p.time_steps],
        m[Symbol("dvStoragePower"*_n)][b] >= m[Symbol("dvDischargeFromStorage"*_n)][b, ts]
    )

end


function add_elec_storage_dispatch_constraints(m, p, b; _n="")
				
	# Constraint (4g)-1: state-of-charge for electrical storage - with grid
	@constraint(m, [ts in p.time_steps_with_grid],
        m[Symbol("dvStoredEnergy"*_n)][b, ts] == m[Symbol("dvStoredEnergy"*_n)][b, ts-1] + p.hours_per_time_step * (  
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.elec) 
            + p.s.storage.attr[b].grid_charge_efficiency * m[Symbol("dvGridToStorage"*_n)][b, ts] 
            - m[Symbol("dvDischargeFromStorage"*_n)][b,ts] / p.s.storage.attr[b].discharge_efficiency
        )
	)
	# Constraint (4g)-2: state-of-charge for electrical storage - no grid
	@constraint(m, [ts in p.time_steps_without_grid],
        m[Symbol("dvStoredEnergy"*_n)][b, ts] == m[Symbol("dvStoredEnergy"*_n)][b, ts-1] + p.hours_per_time_step * (  
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.elec) 
            - m[Symbol("dvDischargeFromStorage"*_n)][b, ts] / p.s.storage.attr[b].discharge_efficiency
        )
    )	

	# Constraint (4h): prevent simultaneous charge and discharge by limitting charging alone to not make the SOC exceed 100%
    # (4h)-1: with grid
	@constraint(m, [ts in p.time_steps_with_grid],
        m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvStoredEnergy"*_n)][b, ts-1] + p.hours_per_time_step * (  
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.elec) 
            + p.s.storage.attr[b].grid_charge_efficiency * m[Symbol("dvGridToStorage"*_n)][b, ts] 
        )
	)
	# (4h)-2: no grid
	@constraint(m, [ts in p.time_steps_without_grid],
        m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvStoredEnergy"*_n)][b, ts-1] + p.hours_per_time_step * (  
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.elec) 
        )
    )

	# Constraint (4i)-1: Dispatch to electrical storage is no greater than power capacity
	@constraint(m, [ts in p.time_steps],
        m[Symbol("dvStoragePower"*_n)][b] >= 
            sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.elec) + m[Symbol("dvGridToStorage"*_n)][b, ts]
    )
	
	#Constraint (4k)-alt: Dispatch to and from electrical storage is no greater than power capacity
	@constraint(m, [ts in p.time_steps_with_grid],
        m[Symbol("dvStoragePower"*_n)][b] >= m[Symbol("dvDischargeFromStorage"*_n)][b, ts] + 
            sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.elec) + m[Symbol("dvGridToStorage"*_n)][b, ts]
    )

	#Constraint (4l)-alt: Dispatch from electrical storage is no greater than power capacity (no grid connection)
	@constraint(m, [ts in p.time_steps_without_grid],
        m[Symbol("dvStoragePower"*_n)][b] >= m[Symbol("dvDischargeFromStorage"*_n)][b,ts] + 
            sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.elec)
    )
    	
    # Remove grid-to-storage as an option if option to grid charge is turned off
    if !(p.s.storage.attr[b].can_grid_charge)
        for ts in p.time_steps_with_grid
            fix(m[Symbol("dvGridToStorage"*_n)][b, ts], 0.0, force=true)
        end
	end

    if p.s.storage.attr[b].minimum_avg_soc_fraction > 0
        avg_soc = sum(m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps) /
                   (8760. / p.hours_per_time_step)
        @constraint(m, avg_soc >= p.s.storage.attr[b].minimum_avg_soc_fraction * 
            sum(m[Symbol("dvStorageEnergy"*_n)][b])
        )
    end
end

function add_elec_storage_cost_constant_constraints(m, p, b; _n="")
    # If there is a battery, then the binIncludeStorageCostConstant binary must be 1
    @constraint(m, m[Symbol("dvStorageEnergy"*_n)][b] <= p.s.storage.attr[b].max_kwh * m[Symbol("binIncludeStorageCostConstant"*_n)][b])		
end 

function add_hot_thermal_storage_dispatch_constraints(m, p, b; _n="")

    # Constraint (4f)-1b: SteamTurbineTechs
	if !isempty(p.techs.steam_turbine)
		@constraint(m, [t in p.techs.steam_turbine, q in p.heating_loads, ts in p.time_steps],
			m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] <=  m[Symbol("dvHeatingProduction"*_n)][t,q,ts]
			)
        @constraint(m, [q in p.heating_loads, ts in p.time_steps],
            m[Symbol("dvHeatFromStorageToTurbine"*_n)][b,q,ts] <= m[Symbol("dvHeatFromStorage"*_n)][b,q,ts]
        )
        if !p.s.storage.attr[b].can_supply_steam_turbine
            for q in p.heating_loads
                for ts in p.time_steps
                    fix(m[Symbol("dvHeatFromStorageToTurbine"*_n)][b,q,ts], 0.0, force=true)
                end
            end
        elseif p.s.storage.attr[b].supply_turbine_only
            @constraint(m, [q in p.heating_loads, ts in p.time_steps],
                m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] ==  m[Symbol("dvHeatFromStorageToTurbine"*_n)][b,q,ts]
                )
            for t in p.techs.steam_turbine
                for ts in p.time_steps, q in p.heating_loads
                    fix(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts], 0.0, force=true)
                end
            end
        end
	end

    # Constraint (4j)-1: Reconcile state-of-charge for (hot) thermal storage
    if b != "HighTempThermalStorage"
        @constraint(m, [b in setdiff(p.s.storage.types.hot, ["HighTempThermalStorage"]), ts in p.time_steps],
            m[Symbol("dvStoredEnergy"*_n)][b,ts] == m[Symbol("dvStoredEnergy"*_n)][b,ts-1] + p.hours_per_time_step * (
                p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads) -
                sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) / p.s.storage.attr[b].discharge_efficiency -
                p.s.storage.attr[b].thermal_decay_rate_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
            )
        )
    else
        @constraint(m, [ts in p.time_steps],
        m[Symbol("dvStoredEnergy"*_n)][b,ts] == m[Symbol("dvStoredEnergy"*_n)][b,ts-1] + (1/p.s.settings.time_steps_per_hour) * (
            p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads) -
            sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) / p.s.storage.attr[b].discharge_efficiency -
            p.s.storage.attr[b].thermal_decay_rate_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1]
            )
        )
    end
    
    # Prevent simultaneous charge and discharge by limitting charging alone to not make the SOC exceed 100%
	@constraint(m, [ts in p.time_steps],
        m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvStoredEnergy"*_n)][b,ts-1] + p.hours_per_time_step * (  
            p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads)
            - p.s.storage.attr[b].thermal_decay_rate_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
        )
    )

    #Constraint (4n)-1: Dispatch to and from thermal storage is no greater than power capacity
	@constraint(m, [ts in p.time_steps],
        m[Symbol("dvStoragePower"*_n)][b] >= 
        sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] + 
        sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp))
        for q in p.heating_loads)
    )

    if b == "HighTempThermalStorage"
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStorageEnergy"*_n)][b] / p.s.storage.attr[b].num_charge_hours >= 
            sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads)
        )
        @constraint(m, [ts in p.time_steps],
        m[Symbol("dvStorageEnergy"*_n)]["HighTempThermalStorage"] / p.s.storage.attr["HighTempThermalStorage"].num_discharge_hours  >= 
            sum(m[Symbol("dvHeatFromStorage"*_n)]["HighTempThermalStorage",q,ts] 
            for q in p.heating_loads)
        )
    end
    # TODO missing thermal storage constraints from API ???

    # Constraint (4o): Discharge from storage is equal to sum of heat from storage for all qualities
    @constraint(m, [ts in p.time_steps],
        m[Symbol("dvDischargeFromStorage"*_n)][b,ts] == 
        sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads)
    )

    #Do not allow GHP to charge storage
    if !isempty(p.techs.ghp)
        for t in p.techs.ghp, q in p.heating_loads, ts in p.time_steps
            fix(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts], 0.0, force=true)
        end
    end

    if b =="HighTempThermalStorage" && p.s.storage.attr[b].one_direction_flow
        dv = "binStorageCharge"*_n
        m[Symbol(dv)] = @variable(m, [["HighTempThermalStorage"], p.time_steps], base_name=dv, binary=true)
        dv = "binStorageDischarge"*_n
        m[Symbol(dv)] = @variable(m, [["HighTempThermalStorage"], p.time_steps], base_name=dv, binary=true)
        
        max_storage_power = min(p.s.storage.attr[b].max_kw, 
            100 * maximum(sum(p.heating_loads_kw[q][ts] for q in p.heating_loads) for ts in p.time_steps)    
        )
        
        @constraint(m, HighTempStorageChargeMax[ts in p.time_steps],
            sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads) <=
            max_storage_power * m[Symbol("binStorageCharge"*_n)][b,ts]
        )
        @constraint(m, HighTempStorageDischargeMax[ts in p.time_steps],
            sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) <=
            max_storage_power * m[Symbol("binStorageDischarge"*_n)][b,ts]
        )
        @constraint(m, HighTempStorageFlowDirection[ts in p.time_steps],
            m[Symbol("binStorageDischarge"*_n)][b,ts] + m[Symbol("binStorageCharge"*_n)][b,ts] <= 1
        )
    end

end

function add_cold_thermal_storage_dispatch_constraints(m, p, b; _n="")

    # Constraint (4f)-2: (Cold) Thermal production sent to storage or grid must be less than technology's rated production
	if !isempty(p.techs.cooling)
		@constraint(m, CoolingTechProductionFlowCon[t in p.techs.cooling, ts in p.time_steps],
    	        m[Symbol("dvProductionToStorage"*_n)][b,t,ts]  <=
				m[Symbol("dvCoolingProduction"*_n)][t,ts]
				)
	end

    # Constraint (4j)-2: Reconcile state-of-charge for (cold) thermal storage
	@constraint(m, ColdTESInventoryCon[ts in p.time_steps],
        m[Symbol("dvStoredEnergy"*_n)][b,ts] == m[Symbol("dvStoredEnergy"*_n)][b,ts-1] + p.hours_per_time_step * (
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.cooling) -
            m[Symbol("dvDischargeFromStorage"*_n)][b,ts]/p.s.storage.attr[b].discharge_efficiency -
            p.s.storage.attr[b].thermal_decay_rate_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
        )
    )

    # Prevent simultaneous charge and discharge by limitting charging alone to not make the SOC exceed 100%
	@constraint(m, [ts in p.time_steps],
        m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvStoredEnergy"*_n)][b,ts-1] + p.hours_per_time_step * (  
            p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.cooling)
            - p.s.storage.attr[b].thermal_decay_rate_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
        )
    )

    #Constraint (4n)-2: Dispatch to and from thermal storage is no greater than power capacity
    @constraint(m, [ts in p.time_steps],
        m[Symbol("dvStoragePower"*_n)][b] >= m[Symbol("dvDischargeFromStorage"*_n)][b,ts] + 
        sum(m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.cooling)
    )

    #Do not allow GHP to charge storage
    if !isempty(p.techs.ghp)
        for t in p.techs.ghp, ts in p.time_steps
                    fix(m[Symbol("dvProductionToStorage"*_n)][b,t,ts], 0.0, force=true)
        end
    end
end

function add_storage_sum_grid_constraints(m, p; _n="")

	##Constraint (8c): Grid-to-storage no greater than grid purchases 
	@constraint(m, [ts in p.time_steps_with_grid],
      sum(m[Symbol("dvGridPurchase"*_n)][ts, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) >= 
      sum(m[Symbol("dvGridToStorage"*_n)][b, ts] for b in p.s.storage.types.elec)
    )
end

"""
	add_hot_tes_flow_restrictions!(m, p, b)

Add flow restrictions from individual heating technologies to charge via dvHeatToStorage and 
discharge via dvHeatFromStorage depending on the compatible loads served.
"""
function add_hot_tes_flow_restrictions!(m, p, b)
    # If there are incompatible heating techs for the storage (i.e., TES fills load the tech cannot), all charge to storage from that tech is zero
    for t in union(p.techs.heating, p.techs.chp)
        incompatible_loads_served = []
        if ("DomesticHotWater" in p.heating_loads_served_by_tes[b] && !(t in p.techs.can_serve_dhw)) 
            push!(incompatible_loads_served, "DomesticHotWater")
        end
        if ("SpaceHeating" in p.heating_loads_served_by_tes[b] && !(t in p.techs.can_serve_space_heating))
            push!(incompatible_loads_served, "SpaceHeating")
        end
        if ("ProcessHeat" in p.heating_loads_served_by_tes[b] && !(t in p.techs.can_serve_process_heat)) 
            push!(incompatible_loads_served, "ProcessHeat")
        end
        if !isempty(incompatible_loads_served)
            @warn "Technology "*t*" is ineligible to serve storage system "*b*" due to the following incompatible loads served "*string(incompatible_loads_served) 
            for q in p.heating_loads_served_by_tes[b]
                for ts in p.time_steps
                    fix(m[:dvHeatToStorage][b,t,q,ts], 0.0, force=true)
                end
            end
        end
    end

    #If load isn't served by storage, all charge or discharge flows of that quality heat are zero 
    if !isempty(setdiff(p.heating_loads, p.heating_loads_served_by_tes[b]))
        @constraint(m, [t in union(p.techs.heating, p.techs.chp), 
            q in setdiff(p.heating_loads, p.heating_loads_served_by_tes[b]), 
            ts in p.time_steps], 
             m[:dvHeatToStorage][b,t,q,ts] == 0
        )
        @constraint(m, [q in setdiff(p.heating_loads, p.heating_loads_served_by_tes[b]), 
            ts in p.time_steps], m[:dvHeatFromStorage][b,q,ts] == 0
        )
    end

    # If a heating load is served by a storage vehicle, only allow charge from compatible techs. otherwise, allow no charge for that heat quality.
    if "DomesticHotWater" in p.heating_loads_served_by_tes[b] && !isempty(setdiff(union(p.techs.heating, p.techs.chp), p.techs.can_serve_dhw))
        @constraint(m, [t in setdiff(union(p.techs.heating, p.techs.chp), p.techs.can_serve_dhw), ts in p.time_steps], 
            m[:dvHeatToStorage][b,t,"DomesticHotWater",ts] == 0
        )
    end
    if "SpaceHeating" in p.heating_loads_served_by_tes[b] && !isempty(setdiff(union(p.techs.heating, p.techs.chp), p.techs.can_serve_space_heating))
        @constraint(m, [t in setdiff(union(p.techs.heating, p.techs.chp), p.techs.can_serve_space_heating), ts in p.time_steps], 
            m[:dvHeatToStorage][b,t,"SpaceHeating",ts] == 0
        )
    end
    if "ProcessHeat" in p.heating_loads_served_by_tes[b] && !isempty(setdiff(union(p.techs.heating, p.techs.chp), p.techs.can_serve_process_heat))
        @constraint(m, [t in setdiff(union(p.techs.heating, p.techs.chp), p.techs.can_serve_process_heat), ts in p.time_steps], 
            m[:dvHeatToStorage][b,t,"ProcessHeat",ts] == 0
        )
    end
end