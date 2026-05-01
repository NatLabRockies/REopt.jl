# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
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

function add_hydrogen_storage_size_constraints(m, p, b; _n="")
    # TODO add formal types for storage (i.e. "b")

	# Constraint (4b)-1: Lower bound on Storage Energy Capacity
	@constraint(m,
        m[Symbol("dvStorageEnergy"*_n)][b] >= p.s.storage.attr[b].min_kg
    )

	# Constraint (4b)-2: Upper bound on Storage Energy Capacity
	@constraint(m,
        m[Symbol("dvStorageEnergy"*_n)][b] <= p.s.storage.attr[b].max_kg
    )
end

function add_general_storage_dispatch_constraints(m, p, b; _n="")
    # Constraint (4a): initial and final state of charge
    if !hasproperty(p.s.storage.attr[b], :fixed_dispatch_series) || isnothing(p.s.storage.attr[b].fixed_dispatch_series)
        if (hasproperty(p.s.storage.attr[b], :optimize_soc_init_fraction) && p.s.storage.attr[b].optimize_soc_init_fraction) || p.s.storage.attr[b].require_start_and_end_charge_to_be_equal
            @info "\nOptimizing "*b*" inital SOC and constraining initial SOC = final SOC. soc_init_fraction will not apply.\n"
            @constraint(m,
                m[Symbol("dvStoredEnergy"*_n)][b, 0] == m[:dvStoredEnergy][b, maximum(p.time_steps)]
            )
            # TODO: always constrain final soc to equal initial soc even when not optimized (ran into feasibility issues)
            # @constraint(m,
            #     m[Symbol("dvStoredEnergy"*_n)][b, maximum(p.time_steps)] == p.s.storage.attr[b].soc_init_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
            # )
        end
        if !(hasproperty(p.s.storage.attr[b], :optimize_soc_init_fraction) && p.s.storage.attr[b].optimize_soc_init_fraction)
            @constraint(m,
                m[Symbol("dvStoredEnergy"*_n)][b, 0] == p.s.storage.attr[b].soc_init_fraction * m[Symbol("dvStorageEnergy"*_n)][b]
            )
        end
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

    # #Constraint (4j): Dispatch from storage is no greater than hydrogen capacity
	# @constraint(m, [ts in p.time_steps],
    #     m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvDischargeFromStorage"*_n)][b, ts]
    # )

end


function add_elec_storage_dispatch_constraints(m, p, b; _n="")
				
	# Constraint (4g)-1: state-of-charge for electrical storage - with grid
	@constraint(m, [ts in p.time_steps_with_grid],
        m[Symbol("dvStoredEnergy"*_n)][b, ts] == 
        m[Symbol("dvStoredEnergy"*_n)][b, ts-1] 
        + p.hours_per_time_step * (  
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.elec) 
            + p.s.storage.attr[b].grid_charge_efficiency * m[Symbol("dvGridToStorage"*_n)][b, ts] 
            - m[Symbol("dvDischargeFromStorage"*_n)][b,ts] / p.s.storage.attr[b].discharge_efficiency
        )
        - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
        - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
	)
	# Constraint (4g)-2: state-of-charge for electrical storage - no grid
	@constraint(m, [ts in p.time_steps_without_grid],
        m[Symbol("dvStoredEnergy"*_n)][b, ts] ==
        m[Symbol("dvStoredEnergy"*_n)][b, ts-1] 
        + p.hours_per_time_step * (  
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.elec) 
            - m[Symbol("dvDischargeFromStorage"*_n)][b, ts] / p.s.storage.attr[b].discharge_efficiency
        )
        - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
        - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
    )	

	# Constraint (4h): prevent simultaneous charge and discharge by limitting charging alone to not make the SOC exceed 100%
    # (4h)-1: with grid
	@constraint(m, [ts in p.time_steps_with_grid],
        m[Symbol("dvStorageEnergy"*_n)][b] >= 
        m[Symbol("dvStoredEnergy"*_n)][b, ts-1] 
        + p.hours_per_time_step * (  
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.elec) 
            + p.s.storage.attr[b].grid_charge_efficiency * m[Symbol("dvGridToStorage"*_n)][b, ts] 
        )
        - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
        - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
	)
	# (4h)-2: no grid
	@constraint(m, [ts in p.time_steps_without_grid],
        m[Symbol("dvStorageEnergy"*_n)][b] >= 
        m[Symbol("dvStoredEnergy"*_n)][b, ts-1] 
        + p.hours_per_time_step * (  
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.elec) 
        )
        - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
        - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
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

    #Constraint: Discharge from electric storage
    @constraint(m, [b in p.s.storage.types.elec, ts in p.time_steps],
        m[Symbol("dvDischargeFromStorage"*_n)][b,ts] >= m[Symbol("dvStorageToElectrolyzer"*_n)][b, ts]
            + m[Symbol("dvStorageToCompressor"*_n)][b, ts]
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

    # Constrain to fixed_dispatch_series
    if hasproperty(p.s.storage.attr[b], :fixed_dispatch_series) && !isnothing(p.s.storage.attr[b].fixed_dispatch_series)      
        @constraint(m, [ts in p.time_steps],
        # Allow for a 1 pct point buffer on user-provided fixed_dispatch_series
            m[Symbol("dvStoredEnergy"*_n)][b, ts] <= (0.01 + p.s.storage.attr[b].fixed_dispatch_series[ts]) * m[Symbol("dvStorageEnergy"*_n)][b]
        )
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStoredEnergy"*_n)][b, ts] >= (-0.01 + p.s.storage.attr[b].fixed_dispatch_series[ts]) * m[Symbol("dvStorageEnergy"*_n)][b]
        )
    end
end

function add_hot_thermal_storage_dispatch_constraints(m, p, b; _n="")

    # Constraint (4j)-1: Reconcile state-of-charge for (hot) thermal storage
    # Thermal decay for HighTempThermalStorage is based on stored kWh, not rated capacity; value is entered as per ts (not hourly)
    if b != "HighTempThermalStorage"
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStoredEnergy"*_n)][b,ts] == 
            m[Symbol("dvStoredEnergy"*_n)][b,ts-1] 
            + p.hours_per_time_step * (
                p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads) -
                sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) / p.s.storage.attr[b].discharge_efficiency
            )
            - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
            - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
        )
    else
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStoredEnergy"*_n)][b,ts] == m[Symbol("dvStoredEnergy"*_n)][b,ts-1] + p.hours_per_time_step * (
                p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads) -
                sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) / p.s.storage.attr[b].discharge_efficiency) -
                p.s.storage.attr[b].thermal_decay_rate_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1]
        )
    end

    # Prevent simultaneous charge and discharge by limitting charging alone to not make the SOC exceed 100%
    # Thermal decay for HighTempThermalStorage is based on stored kWh, not rated capacity; value is entered as per ts (not hourly)
    if b != "HighTempThermalStorage"
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStorageEnergy"*_n)][b] >= 
            m[Symbol("dvStoredEnergy"*_n)][b,ts-1] + p.hours_per_time_step * (  
                p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads)
            )
            - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
            - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
        )
    else
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvStoredEnergy"*_n)][b,ts-1] + p.hours_per_time_step * (  
                p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads)) -
                p.s.storage.attr[b].thermal_decay_rate_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1]
        )
    end
    #Constraint (4n)-1: Dispatch to and from thermal storage is no greater than power capacity
	@constraint(m, [ts in p.time_steps],
        m[Symbol("dvStoragePower"*_n)][b] >= 
        sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] + 
        sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp))
        for q in p.heating_loads)
    )

    #Constraint (4n)-2: Dispatch to thermal storage is no greater than power capacity
	@constraint(m, [b in p.s.storage.types.hot, ts in p.time_steps],
        m[Symbol("dvStorageChargePower"*_n)][b] >= 
        sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads)
    )

    #Constraint (4n)-3: Dispatch from thermal storage is no greater than power capacity
	@constraint(m, [b in p.s.storage.types.hot, ts in p.time_steps],
        m[Symbol("dvStorageDischargePower"*_n)][b] >= sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads)
    )

    # TODO missing thermal storage constraints from API ???

    # Constraint (4o): Discharge from storage is equal to sum of heat from storage for all qualities
    @constraint(m, HeatDischargeReconciliation[ts in p.time_steps],
        m[Symbol("dvDischargeFromStorage"*_n)][b,ts] == 
        sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads)
    )

    #Do not allow GHP to charge storage
    if !isempty(p.techs.ghp)
        for t in p.techs.ghp, q in p.heating_loads, ts in p.time_steps
            fix(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts], 0.0, force=true)
        end
    end
    
    if b in p.s.storage.types.hightemp
        # Constraint (4p): HighTempThermalStorage - constrain charge and discharge to fraction of kWh stored
        if (hasproperty(p.s.storage.attr[b], :constrain_dispatch_to_stored_kwh) && p.s.storage.attr[b].constrain_dispatch_to_stored_kwh)
            @constraint(m, [ts in p.time_steps],
                sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for t in union(p.techs.heating, p.techs.chp), q in p.heating_loads) <= 
                p.hours_per_time_step * p.s.storage.attr[b].charge_limit_as_fraction_of_stored_kwh * m[Symbol("dvStoredEnergy"*_n)][b, ts-1]    
            )
            @constraint(m, [ts in p.time_steps],
                sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) <=
                p.hours_per_time_step * p.s.storage.attr[b].discharge_limit_as_fraction_of_stored_kwh * m[Symbol("dvStoredEnergy"*_n)][b, ts-1]
            )
        end

        # Constraint (4q): HighTempThermalStorage - include pumping power losses as a fraction of discharge power
        if (hasproperty(p.s.storage.attr[b], :pump_loss_as_fraction_of_discharge_kw) && p.s.storage.attr[b].include_discharge_pump_losses)
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvDischargePumpPower"*_n)][b,ts] ==  
                p.s.storage.attr[b].pump_loss_as_fraction_of_discharge_kw * sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads)
            )
        else
            @constraint(m, [ts in p.time_steps], m[Symbol("dvDischargePumpPower"*_n)][b,ts] == 0)
        end
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
        m[Symbol("dvStoredEnergy"*_n)][b,ts] == 
        m[Symbol("dvStoredEnergy"*_n)][b,ts-1] 
        + p.hours_per_time_step * (
            sum(p.s.storage.attr[b].charge_efficiency * m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.cooling) -
            m[Symbol("dvDischargeFromStorage"*_n)][b,ts]/p.s.storage.attr[b].discharge_efficiency
        )
        - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
        - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
    )

    # Prevent simultaneous charge and discharge by limitting charging alone to not make the SOC exceed 100%
	@constraint(m, [ts in p.time_steps],
        m[Symbol("dvStorageEnergy"*_n)][b] >= 
        m[Symbol("dvStoredEnergy"*_n)][b,ts-1] 
        + p.hours_per_time_step * (  
            p.s.storage.attr[b].charge_efficiency * sum(m[Symbol("dvProductionToStorage"*_n)][b,t,ts] for t in p.techs.cooling)
        )
        - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
        - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
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
      + m[Symbol("dvGridToElectrolyzer"*_n)][ts]
      + m[Symbol("dvGridToCompressor"*_n)][ts]
    )
end

function add_hydrogen_storage_dispatch_constraints(m, p, b; _n="")

    if p.s.electrolyzer.require_compression
        # Constraint: state-of-charge for hydrogen storage
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStoredEnergy"*_n)][b, ts] == 
            m[Symbol("dvStoredEnergy"*_n)][b, ts-1] 
            + p.hours_per_time_step * (  
                sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.compressor) 
                - m[Symbol("dvDischargeFromStorage"*_n)][b,ts]
            )
            - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
            - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
        )
        # Constraint: Dispatch to hydrogen storage is no greater than capacity
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStorageEnergy"*_n)][b] >= 
                sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.compressor)
        )
        #Constraint: Dispatch to and from hydrogen storage is no greater than capacity
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvDischargeFromStorage"*_n)][b, ts] + 
                sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.compressor)
        )
    else
        # Constraint: state-of-charge for hydrogen storage
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStoredEnergy"*_n)][b, ts] == 
            m[Symbol("dvStoredEnergy"*_n)][b, ts-1] 
            + p.hours_per_time_step * (  
                sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.electrolyzer) 
                - m[Symbol("dvDischargeFromStorage"*_n)][b,ts]
            )
            - (p.s.storage.attr[b].soc_based_per_ts_self_discharge_fraction * m[Symbol("dvStoredEnergy"*_n)][b, ts-1])
            - (p.s.storage.attr[b].capacity_based_per_ts_self_discharge_fraction * m[Symbol("dvStorageEnergy"*_n)][b])
        )
        # Constraint: Dispatch to hydrogen storage is no greater than capacity
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStorageEnergy"*_n)][b] >= 
                sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.electrolyzer)
        )
        #Constraint: Dispatch to and from hydrogen storage is no greater than capacity
        @constraint(m, [ts in p.time_steps],
            m[Symbol("dvStorageEnergy"*_n)][b] >= m[Symbol("dvDischargeFromStorage"*_n)][b, ts] + 
                sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for t in p.techs.electrolyzer)
        )
    end

    # Constraint: Hydrogen dispatch from storage
	@constraint(m, [b in p.s.storage.types.hydrogen, ts in p.time_steps],
        sum(m[Symbol("dvDischargeFromStorage"*_n)][b,ts]) == 
            p.s.hydrogen_load.loads_kg[ts]
            + sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] / p.s.fuel_cell.efficiency_kwh_per_kg for t in p.techs.fuel_cell)
    )
					
    if p.s.storage.attr[b].minimum_avg_soc_fraction > 0
        avg_soc = sum(m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps) /
                   (8760. / p.hours_per_time_step)
        @constraint(m, avg_soc >= p.s.storage.attr[b].minimum_avg_soc_fraction * 
            sum(m[Symbol("dvStorageEnergy"*_n)][b])
        )
    end

end