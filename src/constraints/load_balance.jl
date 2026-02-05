# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

function add_elec_load_balance_constraints(m, p; _n="") 

	##Constraint (8a): Electrical Load Balancing with Grid
    if isempty(p.s.electric_tariff.export_bins)
        conrefs = @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps_with_grid],
            sum(p.production_factor_by_scenario[s][t][ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][s, t,ts] for t in p.techs.elec)  
            + sum(m[Symbol("dvDischargeFromStorage"*_n)][s, b,ts] for b in p.s.storage.types.elec) 
            + sum(m[Symbol("dvGridPurchase"*_n)][s, ts, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers)
            ==
            sum(sum(m[Symbol("dvProductionToStorage"*_n)][s, b, t, ts] for b in p.s.storage.types.elec) 
                + m[Symbol("dvCurtail"*_n)][s, t, ts] for t in p.techs.elec)
            + sum(m[Symbol("dvGridToStorage"*_n)][s, b, ts] for b in p.s.storage.types.elec)
            + sum(m[Symbol("dvCoolingProduction"*_n)][s, t, ts] / p.cooling_cop[t][ts] for t in setdiff(p.techs.cooling,p.techs.ghp))
            + sum(m[Symbol("dvHeatingProduction"*_n)][s, t, q, ts] / p.heating_cop[t][ts] for q in p.heating_loads, t in p.techs.electric_heater)
            + p.loads_kw_by_scenario[s][ts]
            - p.s.cooling_load.loads_kw_thermal[ts] / p.cooling_cop["ExistingChiller"][ts]
            + sum(p.ghp_electric_consumption_kw[g,ts] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options)
        )
        for (i, cr) in enumerate(conrefs)
            # Extract s and ts from the index - conrefs is now a 2D array
            idx = CartesianIndices(conrefs)[i]
            JuMP.set_name(cr, "con_load_balance"*_n*string("_s", idx[1], "_t", idx[2]))
        end
    else
        conrefs = @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps_with_grid],
            sum(p.production_factor_by_scenario[s][t][ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][s, t,ts] for t in p.techs.elec)
            + sum(m[Symbol("dvDischargeFromStorage"*_n)][s, b,ts] for b in p.s.storage.types.elec )
            + sum(m[Symbol("dvGridPurchase"*_n)][s, ts, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers)
            ==
            sum(sum(m[Symbol("dvProductionToStorage"*_n)][s, b, t, ts] for b in p.s.storage.types.elec) 
                + sum(m[Symbol("dvProductionToGrid"*_n)][s, t, u, ts] for u in p.export_bins_by_tech[t]) 
                + m[Symbol("dvCurtail"*_n)][s, t, ts] for t in p.techs.elec)
            + sum(m[Symbol("dvGridToStorage"*_n)][s, b, ts] for b in p.s.storage.types.elec)
            + sum(m[Symbol("dvCoolingProduction"*_n)][s, t, ts] / p.cooling_cop[t][ts] for t in setdiff(p.techs.cooling,p.techs.ghp))
            + sum(m[Symbol("dvHeatingProduction"*_n)][s, t, q, ts] / p.heating_cop[t][ts] for q in p.heating_loads, t in p.techs.electric_heater)
            + p.loads_kw_by_scenario[s][ts]
            - p.s.cooling_load.loads_kw_thermal[ts] / p.cooling_cop["ExistingChiller"][ts]
            + sum(p.ghp_electric_consumption_kw[g,ts] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options)
        )
        for (i, cr) in enumerate(conrefs)
            # Extract s and ts from the index - conrefs is now a 2D array
            idx = CartesianIndices(conrefs)[i]
            JuMP.set_name(cr, "con_load_balance"*_n*string("_s", idx[1], "_t", idx[2]))
        end
    end
	
	##Constraint (8b): Electrical Load Balancing without Grid
	if !p.s.settings.off_grid_flag # load balancing constraint for grid-connected runs
        @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps_without_grid],
            sum(p.production_factor_by_scenario[s][t][ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][s, t,ts] for t in p.techs.elec)  
            + sum(m[Symbol("dvDischargeFromStorage"*_n)][s, b,ts] for b in p.s.storage.types.elec)
            ==
            sum(sum(m[Symbol("dvProductionToStorage"*_n)][s, b, t, ts] for b in p.s.storage.types.elec) 
                + m[Symbol("dvCurtail"*_n)][s, t, ts] for t in p.techs.elec)
            + p.s.electric_load.critical_loads_kw[ts]
        )
    else # load balancing constraint for off-grid runs 
        @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps_without_grid],
            sum(p.production_factor_by_scenario[s][t][ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][s, t,ts] for t in p.techs.elec)
            + sum(m[Symbol("dvDischargeFromStorage"*_n)][s, b,ts] for b in p.s.storage.types.elec)
            ==
            sum(sum(m[Symbol("dvProductionToStorage"*_n)][s, b, t, ts] for b in p.s.storage.types.elec)
                + m[Symbol("dvCurtail"*_n)][s, t, ts] for t in p.techs.elec)
            + p.s.electric_load.critical_loads_kw[ts] * m[Symbol("dvOffgridLoadServedFraction"*_n)][ts]
        )
        ##Constraint : For off-grid scenarios, annual load served must be >= minimum percent specified
        @constraint(m, 
            sum(m[Symbol("dvOffgridLoadServedFraction"*_n)][ts] * p.s.electric_load.critical_loads_kw[ts] for ts in p.time_steps_without_grid)
            >=
			sum(p.s.electric_load.critical_loads_kw) * p.s.electric_load.min_load_met_annual_fraction 
		)
    end

end


function add_production_constraints(m, p; _n="")
	# Constraint (4d): Electrical production sent to storage or export must be less than technology's rated production
    if isempty(p.s.electric_tariff.export_bins)
        @constraint(m, [s in 1:p.n_scenarios, t in p.techs.elec, ts in p.time_steps_with_grid],
            sum(m[Symbol("dvProductionToStorage"*_n)][s, b, t, ts] for b in p.s.storage.types.elec)  
            + m[Symbol("dvCurtail"*_n)][s, t, ts]
            <= 
            p.production_factor_by_scenario[s][t][ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][s, t, ts]
        )
    else
        @constraint(m, [s in 1:p.n_scenarios, t in p.techs.elec, ts in p.time_steps_with_grid],
            sum(m[Symbol("dvProductionToStorage"*_n)][s, b, t, ts] for b in p.s.storage.types.elec)  
            + m[Symbol("dvCurtail"*_n)][s, t, ts]
            + sum(m[Symbol("dvProductionToGrid"*_n)][s, t, u, ts] for u in p.export_bins_by_tech[t])
            <= 
            p.production_factor_by_scenario[s][t][ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][s, t, ts]
        )
    end

	# Constraint (4e): Electrical production sent to storage or curtailed must be less than technology's rated production - no grid
    @constraint(m, [s in 1:p.n_scenarios, t in p.techs.elec, ts in p.time_steps_without_grid],
        sum(m[Symbol("dvProductionToStorage"*_n)][s, b, t, ts] for b in p.s.storage.types.elec)  
        + m[Symbol("dvCurtail"*_n)][s, t, ts]
        <= 
        p.production_factor_by_scenario[s][t][ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][s, t, ts]
    )

end


function add_thermal_load_constraints(m, p; _n="")

    m[Symbol("binFlexHVAC"*_n)] = 0
    m[Symbol("dvTemperature"*_n)] = 0
    m[Symbol("dvComfortLimitViolationCost"*_n)] = 0

    if !isnothing(p.s.flexible_hvac)
        #= FlexibleHVAC does not require equality constraints for thermal loads. The thermal loads
        are instead a function of the energy required to keep the space temperature within the 
        comfort limits.
        =#
        add_flexible_hvac_constraints(m, p, _n=_n) 

	##Constraint (5b): Hot thermal loads
    else    
        if !isempty(p.techs.heating)
            
            if !isempty(p.techs.steam_turbine)
                @constraint(m, HeatLoadBalanceCon[s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps_with_grid],
                    sum(m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts] for t in union(p.techs.heating, p.techs.chp))
                    + sum(m[Symbol("dvHeatFromStorage"*_n)][s,b,q,ts] for b in p.s.storage.types.hot)
                    ==
                    p.heating_loads_kw[q][ts]
                    + sum(m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts] for t in union(p.techs.heating, p.techs.chp))
                    + sum(m[Symbol("dvHeatToStorage"*_n)][s,b,t,q,ts] for b in p.s.storage.types.hot, t in union(p.techs.heating, p.techs.chp))
                    + sum(m[Symbol("dvCoolingProduction"*_n)][s,t,ts] / p.thermal_cop[t] for t in p.absorption_chillers_using_heating_load[q])
                    + sum(m[Symbol("dvThermalToSteamTurbine"*_n)][s,t,q,ts] for t in p.techs.can_supply_steam_turbine)
                    + sum(m[Symbol("dvHeatFromStorageToTurbine"*_n)][s,b,q,ts] for b in p.s.storage.types.hot)
                )
            else
                @constraint(m, HeatLoadBalanceCon[s in 1:p.n_scenarios, q in p.heating_loads, ts in p.time_steps_with_grid],
                    sum(m[Symbol("dvHeatingProduction"*_n)][s,t,q,ts] for t in union(p.techs.heating, p.techs.chp))
                    + sum(m[Symbol("dvHeatFromStorage"*_n)][s,b,q,ts] for b in p.s.storage.types.hot)
                    ==
                    p.heating_loads_kw[q][ts]
                    + sum(m[Symbol("dvProductionToWaste"*_n)][s,t,q,ts] for t in union(p.techs.heating, p.techs.chp))
                    + sum(m[Symbol("dvHeatToStorage"*_n)][s,b,t,q,ts] for b in p.s.storage.types.hot, t in union(p.techs.heating, p.techs.chp))
                    + sum(m[Symbol("dvCoolingProduction"*_n)][s,t,ts] / p.thermal_cop[t] for t in p.absorption_chillers_using_heating_load[q])
                )
            end

        end

        if !isempty(p.techs.cooling)
            
            ##Constraint (5a): Cold thermal loads
            @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps_with_grid],
                sum(m[Symbol("dvCoolingProduction"*_n)][s,t,ts] for t in p.techs.cooling)
                + sum(m[Symbol("dvDischargeFromStorage"*_n)][s,b,ts] for b in p.s.storage.types.cold)
                ==
                p.s.cooling_load.loads_kw_thermal[ts]
                + sum(m[Symbol("dvProductionToStorage"*_n)][s,b,t,ts] for b in p.s.storage.types.cold, t in p.techs.cooling)
            )
        end
    end
end