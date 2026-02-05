# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

function add_boiler_tech_constraints(m, p; _n="")
    
    m[:TotalBoilerFuelCosts] = @expression(m, sum(p.scenario_probabilities[s] * p.pwf_fuel[t] *
        sum(m[:dvFuelUsage][s, t, ts] * p.fuel_cost_per_kwh[t][ts] for ts in p.time_steps)
        for s in 1:p.n_scenarios, t in p.techs.boiler)
    )

    # Constraint (1e): Total Fuel burn for Boiler
    @constraint(m, BoilerFuelTrackingCon[s in 1:p.n_scenarios, t in p.techs.boiler, ts in p.time_steps],
        m[:dvFuelUsage][s, t,ts] == p.hours_per_time_step * (
            sum(m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts] for q in p.heating_loads) / p.boiler_efficiency[t]
        )
    )
    if "Boiler" in p.techs.boiler  # ExistingBoiler does not have om_cost_per_kwh
        m[:TotalBoilerPerUnitProdOMCosts] = @expression(m, p.third_party_factor * p.pwf_om *
            sum(p.scenario_probabilities[s] * p.s.boiler.om_cost_per_kwh * p.hours_per_time_step *
            m[Symbol("dvHeatingProduction"*_n)][s,"Boiler",q,ts] for s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps)
        )
    else
        m[:TotalBoilerPerUnitProdOMCosts] = 0.0
    end
end

function add_heating_tech_constraints(m, p; _n="")
    # Constraint (7_heating_flow): Flows to Steam turbine, waste, and turbine must be less than or equal to total production
    if !isempty(p.techs.steam_turbine)
        if !isempty(p.s.storage.types.hot)
            @constraint(m, [s in 1:p.n_scenarios, t in p.techs.can_supply_steam_turbine, q in p.heating_loads, ts in p.time_steps],
                sum(m[Symbol("dvHeatToStorage"*_n)][s,b,t,q,ts] for b in p.s.storage.types.hot) + m[Symbol("dvThermalToSteamTurbine"*_n)][s,t,q,ts] + m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts]  <=
                m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts]
            )
            if !isempty(setdiff(union(p.techs.heating, p.techs.chp),p.techs.can_supply_steam_turbine))
                @constraint(m, [s in 1:p.n_scenarios, t in setdiff(union(p.techs.heating,p.techs.chp),p.techs.can_supply_steam_turbine), q in p.heating_loads, ts in p.time_steps],
                    sum(m[Symbol("dvHeatToStorage"*_n)][s,b,t,q,ts] for b in p.s.storage.types.hot) + m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts]  <=  
                    m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts]
                )
            end
        else
            @constraint(m, [s in 1:p.n_scenarios, t in p.techs.can_supply_steam_turbine, q in p.heating_loads, ts in p.time_steps],
                m[Symbol("dvThermalToSteamTurbine"*_n)][s,t,q,ts] + m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts]  <=
                m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts]
            )
            if !isempty(setdiff(union(p.techs.heating, p.techs.chp),p.techs.can_supply_steam_turbine))
                @constraint(m, [s in 1:p.n_scenarios, t in setdiff(union(p.techs.heating,p.techs.chp),p.techs.can_supply_steam_turbine), q in p.heating_loads, ts in p.time_steps],
                    m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts]  <=  m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts]
                )
            end
        end
    else
        if !isempty(p.s.storage.types.hot)
            @constraint(m, [s in 1:p.n_scenarios, t in union(p.techs.heating, p.techs.chp), q in p.heating_loads, ts in p.time_steps],
                sum(m[Symbol("dvHeatToStorage"*_n)][s,b,t,q,ts] for b in p.s.storage.types.hot) + m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts]  <=
                m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts]
            )
        else
            @constraint(m, [s in 1:p.n_scenarios, t in union(p.techs.heating, p.techs.chp), q in p.heating_loads, ts in p.time_steps],
                m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts]  <=  m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts]
            )
        end
    end
    
    # Constraint (7_heating_prod_size): Production limit based on size for non-electricity-producing heating techs
    if !isempty(setdiff(p.techs.heating, union(p.techs.elec, p.techs.ghp)))
        @constraint(m, [s in 1:p.n_scenarios, t in setdiff(p.techs.heating, union(p.techs.elec, p.techs.ghp)), ts in p.time_steps],
            sum(m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts] for q in p.heating_loads)  <= p.heating_cf[t][ts] * m[Symbol("dvSize"*_n)][t]
        )
    end
    # Constraint (7_heating_load_compatability): Set production variables for incompatible heat loads to zero
    for t in setdiff(union(p.techs.heating, p.techs.chp), p.techs.ghp)
        if !(t in p.techs.can_serve_space_heating)
            for s in 1:p.n_scenarios, ts in p.time_steps
                fix(m[Symbol("dvHeatingProduction"*_n)][s,t,"SpaceHeating",ts], 0.0, force=true)
                fix(m[Symbol("dvProductionToWaste"*_n)][s,t,"SpaceHeating",ts], 0.0, force=true)
            end
        end
        if !(t in p.techs.can_serve_dhw)
            for s in 1:p.n_scenarios, ts in p.time_steps
                fix(m[Symbol("dvHeatingProduction"*_n)][s,t,"DomesticHotWater",ts], 0.0, force=true)
                fix(m[Symbol("dvProductionToWaste"*_n)][s,t,"DomesticHotWater",ts], 0.0, force=true)
            end
        end
        if !(t in p.techs.can_serve_process_heat)
            for s in 1:p.n_scenarios, ts in p.time_steps
                fix(m[Symbol("dvHeatingProduction"*_n)][s,t,"ProcessHeat",ts], 0.0, force=true)
                fix(m[Symbol("dvProductionToWaste"*_n)][s,t,"ProcessHeat",ts], 0.0, force=true)
            end
        end
    end

    # If the electric heater can only provide heat to the storage system (as in PTES), then production to storage must equal total production
    if "ElectricHeater" in p.techs.electric_heater
        if p.s.electric_heater.charge_storage_only
            #assume sensible TES first, and hot water otherwise.
            if "HighTempThermalStorage" in p.s.storage.types.hot
                @constraint(m, ElectricHeaterToStorageOnly[s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps],
                    m[Symbol("dvHeatingProduction"*_n)][s,"ElectricHeater",q,ts] == m[Symbol("dvHeatToStorage"*_n)][s,"HighTempThermalStorage","ElectricHeater",q,ts]
                )
            elseif "HotThermalStorage" in p.s.storage.types.hot
                @constraint(m, ElectricHeaterToStorageOnly[s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps],
                    m[Symbol("dvHeatingProduction"*_n)][s,"ElectricHeater",q,ts] == m[Symbol("dvHeatToStorage"*_n)][s,"HotThermalStorage","ElectricHeater",q,ts]
                )
            else
                @warn "ElectricHeater.charge_storage_only is set to True, but no hot storage technologies exist."
            end
        end
    end

    if "CST" in p.techs.electric_heater
        @constraint(m, CSTHeatProduction[s in 1:p.n_scenarios, ts in p.time_steps],
            sum(m[Symbol("dvHeatingProduction"*_n)][s,"CST",q,ts] for q in p.heating_loads) == p.heating_cf["CST"][ts] * m[Symbol("dvSize"*_n)]["CST"]
        )
        if p.s.cst.charge_storage_only
            #assume sensible TES first, and hot water otherwise.
            if "HighTempThermalStorage" in p.s.storage.types.hot
                @constraint(m, CSTToStorageOnly[s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps],
                    m[Symbol("dvHeatingProduction"*_n)][s,"CST",q,ts] == m[Symbol("dvProductionToWaste"*_n)][s,"CST",q,ts] + m[Symbol("dvHeatToStorage"*_n)][s,"HighTempThermalStorage","CST",q,ts]
                )
            elseif "HotThermalStorage" in p.s.storage.types.hot
                @constraint(m, CSTToStorageOnly[s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps],
                    m[Symbol("dvHeatingProduction"*_n)][s,"CST",q,ts] == m[Symbol("dvProductionToWaste"*_n)][s,"CST",q,ts] + m[Symbol("dvHeatToStorage"*_n)][s,"HotThermalStorage","CST",q,ts]
                )
            else
                @warn "CST.charge_storage_only is set to True, but no hot storage technologies exist."
            end
        end
        if !p.s.cst.can_waste_heat
            for s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps
                fix(m[Symbol("dvProductionToWaste"*_n)][s,"CST",q,ts], 0.0, force=true)
            end
        end
    end

    
    # Enforce no waste heat for any technology that isn't both electricity- and heat-producing
    for t in setdiff(p.techs.heating, union(p.techs.elec, p.techs.ghp, ["CST"]))
        for s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps
            fix(m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts], 0.0, force=true)
        end
    end
end

function add_heating_cooling_constraints(m, p; _n="")
    @constraint(m, [s in 1:p.n_scenarios, t in setdiff(intersect(p.techs.cooling, p.techs.heating), p.techs.ghp), ts in p.time_steps],
        sum(m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts] for q in p.heating_loads) / p.heating_cf[t][ts] + m[Symbol("dvCoolingProduction"*_n)][s,t,ts] / p.cooling_cf[t][ts] <= m[Symbol("dvSize"*_n)][t]
    )
end
    

function add_ashp_force_in_constraints(m, p; _n="")
    if "ASHPSpaceHeater" in p.techs.ashp 
        if p.s.ashp.force_into_system
            for t in setdiff(p.techs.can_serve_space_heating, ["ASHPSpaceHeater"])
                for s in 1:p.n_scenarios, ts in p.time_steps
                    fix(m[Symbol("dvHeatingProduction"*_n)][s,t,"SpaceHeating",ts], 0.0, force=true)
                    fix(m[Symbol("dvProductionToWaste"*_n)][s,t,"SpaceHeating",ts], 0.0, force=true)
                end
            end
        elseif p.s.ashp.force_dispatch
            dv = "binASHPSHSizeExceedsThermalLoad"*_n
            m[Symbol(dv)] = @variable(m, [p.time_steps], binary=true, base_name=dv)
            dv = "dvASHPSHSizeTimesExcess"*_n
            m[Symbol(dv)] = @variable(m, [p.time_steps], lower_bound=0, base_name=dv)
            if p.s.ashp.can_serve_cooling
                max_sh_size_bigM = 2*max(p.max_sizes["ASHPSpaceHeater"], maximum(p.heating_loads_kw["SpaceHeating"] ./ p.heating_cf["ASHPSpaceHeater"])+maximum(p.s.cooling_load.loads_kw_thermal ./ p.cooling_cf["ASHPSpaceHeater"]))
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts] >= (
                        m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"]
                        - (p.heating_loads_kw["SpaceHeating"][ts] / p.heating_cf["ASHPSpaceHeater"][ts]) 
                        - (p.s.cooling_load.loads_kw_thermal[ts] / p.cooling_cf["ASHPSpaceHeater"][ts])  
                        ) / max_sh_size_bigM
                )
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts] <= 1 - (
                        (p.heating_loads_kw["SpaceHeating"][ts] / p.heating_cf["ASHPSpaceHeater"][ts]) 
                        + (p.s.cooling_load.loads_kw_thermal[ts] / p.cooling_cf["ASHPSpaceHeater"][ts]) 
                        - m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"]
                        ) / max_sh_size_bigM
                )
                # set dvASHPSHSizeTimesExcess = binASHPSHSizeExceedsThermalLoad * dvSize
                # big-M is min CF times heat load
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("dvASHPSHSizeTimesExcess"*_n)][ts] >= m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"] - max_sh_size_bigM * (1-m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts])  
                )
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("dvASHPSHSizeTimesExcess"*_n)][ts] <= m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"]
                )
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("dvASHPSHSizeTimesExcess"*_n)][ts] <= max_sh_size_bigM * m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts]
                )
                #Enforce dispatch: output = system size - (overage)
                @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
                    m[Symbol("dvHeatingProduction"*_n)][s,"ASHPSpaceHeater","SpaceHeating",ts] / p.heating_cf["ASHPSpaceHeater"][ts] + m[Symbol("dvCoolingProduction"*_n)][s,"ASHPSpaceHeater",ts] / p.cooling_cf["ASHPSpaceHeater"][ts] >= m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"] - m[Symbol("dvASHPSHSizeTimesExcess"*_n)][ts] + (p.heating_loads_kw["SpaceHeating"][ts] / p.heating_cf["ASHPSpaceHeater"][ts] + p.s.cooling_load.loads_kw_thermal[ts] / p.cooling_cf["ASHPSpaceHeater"][ts] ) * m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts]
                )
            else
                # binary variable enforcement for size >= load
                max_sh_size_bigM = 2*max(p.max_sizes["ASHPSpaceHeater"], maximum(p.heating_loads_kw["SpaceHeating"] ./ p.heating_cf["ASHPSpaceHeater"]))
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts] >= (m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"] - p.heating_loads_kw["SpaceHeating"][ts] / p.heating_cf["ASHPSpaceHeater"][ts]) / max_sh_size_bigM
                )
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts] <= 1 - (p.heating_loads_kw["SpaceHeating"][ts] / p.heating_cf["ASHPSpaceHeater"][ts] - m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"]) / max_sh_size_bigM
                )
                # set dvASHPSHSizeTimesExcess = binASHPSHSizeExceedsThermalLoad * dvSize
                # big-M is min CF times heat load
                
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("dvASHPSHSizeTimesExcess"*_n)][ts] >= p.heating_cf["ASHPSpaceHeater"][ts]*m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"] - max_sh_size_bigM * (1-m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts])  
                )
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("dvASHPSHSizeTimesExcess"*_n)][ts] <= p.heating_cf["ASHPSpaceHeater"][ts]*m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"]
                )
                @constraint(m, [ts in p.time_steps],
                    m[Symbol("dvASHPSHSizeTimesExcess"*_n)][ts] <= max_sh_size_bigM * m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts]
                )
                #Enforce dispatch: output = system size - (overage)
                @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
                    m[Symbol("dvHeatingProduction"*_n)][s,"ASHPSpaceHeater","SpaceHeating",ts] >= p.heating_cf["ASHPSpaceHeater"][ts]*m[Symbol("dvSize"*_n)]["ASHPSpaceHeater"] - m[Symbol("dvASHPSHSizeTimesExcess"*_n)][ts] + p.heating_loads_kw["SpaceHeating"][ts] * m[Symbol("binASHPSHSizeExceedsThermalLoad"*_n)][ts]
                )
            end
        end
    end

    if "ASHPSpaceHeater" in p.techs.cooling && p.s.ashp.force_into_system
        for t in setdiff(p.techs.cooling, ["ASHPSpaceHeater"])
            for s in 1:p.n_scenarios, ts in p.time_steps
                fix(m[Symbol("dvCoolingProduction"*_n)][s,t,ts], 0.0, force=true)
            end
        end
    end

    if "ASHPWaterHeater" in p.techs.ashp 
        if p.s.ashp_wh.force_into_system
            for t in setdiff(p.techs.can_serve_dhw, ["ASHPWaterHeater"])
                for s in 1:p.n_scenarios, ts in p.time_steps
                    fix(m[Symbol("dvHeatingProduction"*_n)][s,t,"DomesticHotWater",ts], 0.0, force=true)
                    fix(m[Symbol("dvProductionToWaste"*_n)][s,t,"DomesticHotWater",ts], 0.0, force=true)
                end
            end
        elseif p.s.ashp_wh.force_dispatch
            dv = "binASHPWHSizeExceedsThermalLoad"*_n
            m[Symbol(dv)] = @variable(m, [p.time_steps], binary=true, base_name=dv)
            dv = "dvASHPWHSizeTimesExcess"*_n
            m[Symbol(dv)] = @variable(m, [p.time_steps], lower_bound=0, base_name=dv)
            # binary variable enforcement for size >= load
            max_wh_size_bigM = 2*max(p.max_sizes["ASHPWaterHeater"], maximum(p.heating_loads_kw["DomesticHotWater"] ./ p.heating_cf["ASHPWaterHeater"]))
            @constraint(m, [ts in p.time_steps],
                m[Symbol("binASHPWHSizeExceedsThermalLoad"*_n)][ts] >= (m[Symbol("dvSize"*_n)]["ASHPWaterHeater"] - p.heating_loads_kw["DomesticHotWater"][ts] / p.heating_cf["ASHPWaterHeater"][ts]) / max_wh_size_bigM
            )
            @constraint(m, [ts in p.time_steps],
                m[Symbol("binASHPWHSizeExceedsThermalLoad"*_n)][ts] <= 1 - (p.heating_loads_kw["DomesticHotWater"][ts] / p.heating_cf["ASHPWaterHeater"][ts] - m[Symbol("dvSize"*_n)]["ASHPWaterHeater"]) / max_wh_size_bigM
            )
            # set dvASHPWHSizeTimesExcess = binASHPWHSizeExceedsThermalLoad * dvSize
            # big-M is min CF times heat load
            
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvASHPWHSizeTimesExcess"*_n)][ts] >= p.heating_cf["ASHPWaterHeater"][ts]*m[Symbol("dvSize"*_n)]["ASHPWaterHeater"] - max_wh_size_bigM * (1-m[Symbol("binASHPWHSizeExceedsThermalLoad"*_n)][ts])  
            )
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvASHPWHSizeTimesExcess"*_n)][ts] <= p.heating_cf["ASHPWaterHeater"][ts]*m[Symbol("dvSize"*_n)]["ASHPWaterHeater"]
            )
            @constraint(m, [ts in p.time_steps],
                m[Symbol("dvASHPWHSizeTimesExcess"*_n)][ts] <= max_wh_size_bigM * m[Symbol("binASHPWHSizeExceedsThermalLoad"*_n)][ts]
            )
            #Enforce dispatch: output = system size - (overage)
            @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
                m[Symbol("dvHeatingProduction"*_n)][s,"ASHPWaterHeater","DomesticHotWater",ts] >= p.heating_cf["ASHPWaterHeater"][ts]*m[Symbol("dvSize"*_n)]["ASHPWaterHeater"] - m[Symbol("dvASHPWHSizeTimesExcess"*_n)][ts] + p.heating_loads_kw["DomesticHotWater"][ts] * m[Symbol("binASHPWHSizeExceedsThermalLoad"*_n)][ts]
            )
        end 
    end
end

function avoided_capex_by_ashp(m, p; _n="")
    m[:AvoidedCapexByASHP] = @expression(m,
    sum(p.avoided_capex_by_ashp_present_value[t] for t in p.techs.ashp)
    )
end

function no_existing_boiler_production(m, p; _n="")
    for s in 1:p.n_scenarios, ts in p.time_steps, q in p.heating_loads
        fix(m[Symbol("dvHeatingProduction"*_n)][s,"ExistingBoiler",q,ts], 0.0, force=true)
    end
    fix(m[Symbol("dvSize"*_n)]["ExistingBoiler"], 0.0, force=true)
end

function add_cooling_tech_constraints(m, p; _n="")
    # Constraint (7_cooling_prod_size): Production limit based on size for boiler
    @constraint(m, [s in 1:p.n_scenarios, t in setdiff(p.techs.cooling, p.techs.ghp), ts in p.time_steps_with_grid],
        m[Symbol("dvCoolingProduction"*_n)][s,t,ts] <= m[Symbol("dvSize"*_n)][t] * p.cooling_cf[t][ts]
    )
    # The load balance for cooling is only applied to time_steps_with_grid, so make sure we don't arbitrarily show cooling production for time_steps_without_grid
    for t in setdiff(p.techs.cooling, p.techs.ghp)
        for s in 1:p.n_scenarios, ts in p.time_steps_without_grid
            fix(m[Symbol("dvCoolingProduction"*_n)][s, t, ts], 0.0, force=true)
        end
    end
end

function no_existing_chiller_production(m, p; _n="")
    for s in 1:p.n_scenarios, ts in p.time_steps
        fix(m[Symbol("dvCoolingProduction"*_n)][s,"ExistingChiller",ts], 0.0, force=true)
    end
    fix(m[Symbol("dvSize"*_n)]["ExistingChiller"], 0.0, force=true)
end

function add_existing_boiler_capex_constraints(m, p; _n="")
    # @variable(m, binExistingBoiler, Int, lower_bound = 0, upper_bound = 1)  # This is same as below with Bin
    @variable(m, binExistingBoiler, Bin)
    # If still using ExistingBoiler in optimal case at all, incur costs (not scaled by size)
    # Force dvSize["ExistingBoiler] to zero if binExistingBoiler is zero:
    @constraint(m, ExistingBoilerCostCon, m[Symbol("dvSize"*_n)]["ExistingBoiler"] <= m[Symbol("binExistingBoiler"*_n)] * BIG_NUMBER)

    if p.s.existing_boiler.retire_in_optimal
        @constraint(m, ExistingBoilerSelect, m[Symbol("binExistingBoiler"*_n)] == 0)
    else
        @constraint(m, ExistingBoilerSelect, m[Symbol("binExistingBoiler"*_n)] <= 1)
    end

    m[:ExistingBoilerCost] = @expression(m, p.third_party_factor *
        sum(p.s.existing_boiler.installed_cost_dollars * m[Symbol("binExistingBoiler"*_n)])
    )
end

function add_existing_chiller_capex_constraints(m, p; _n="")
    # @variable(m, binExistingChiller, Int, lower_bound = 0, upper_bound = 1)  # This is same as below with Bin
    @variable(m, binExistingChiller, Bin)
    # If still using ExistingChiller in optimal case, incur costs (not scaled by size)
    # Force dvSize["ExistingChiller] to zero if binExistingChiller is zero:
    @constraint(m, ExistingChillerCostCon, m[Symbol("dvSize"*_n)]["ExistingChiller"] <= m[Symbol("binExistingChiller"*_n)] * BIG_NUMBER)

    @constraint(m, ExistingChillerSelect, m[Symbol("binExistingChiller"*_n)] <= 1)

    m[:ExistingChillerCost] = @expression(m, p.third_party_factor *
        sum(p.s.existing_chiller.installed_cost_dollars * m[Symbol("binExistingChiller"*_n)])
    )
end
