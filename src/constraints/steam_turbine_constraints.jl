# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

function steam_turbine_thermal_input(m, p; _n="")

    # This constraint is already included in storage_constraints.jl if HotThermalStorage and SteamTurbine are considered that also includes dvProductionToStorage["HotThermalStorage"] in LHS
    if isempty(p.s.storage.types.hot)
        @constraint(m, SupplySteamTurbineProductionLimit[t in p.techs.can_supply_steam_turbine, q in p.heating_loads, ts in p.time_steps],
                    m[Symbol("dvThermalToSteamTurbine"*_n)][t,q,ts] + m[Symbol("dvProductionToWaste"*_n)][t,q,ts] <=
                    m[Symbol("dvHeatingProduction"*_n)][t,q,ts]
        )
    else
        @constraint(m, SupplySteamTurbineProductionLimit[t in p.techs.can_supply_steam_turbine, q in p.heating_loads, ts in p.time_steps],
                    m[Symbol("dvThermalToSteamTurbine"*_n)][t,q,ts] + sum(m[Symbol("dvHeatToStorage"*_n)][b,t,q,ts] for b in p.s.storage.types.hot) + m[Symbol("dvProductionToWaste"*_n)][t,q,ts] <=
                    m[Symbol("dvHeatingProduction"*_n)][t,q,ts]
        )
    end
end

function steam_turbine_production_constraints(m, p; _n="")
    # Constraint Steam Turbine Thermal Production
    @constraint(m, SteamTurbineThermalProductionCon[t in p.techs.steam_turbine, ts in p.time_steps],
                sum(m[Symbol("dvHeatingProduction"*_n)][t,q,ts] + m[Symbol("dvProductionToWaste"*_n)][t,q,ts] for q in p.heating_loads) == p.s.steam_turbine.thermal_produced_to_thermal_consumed_ratio * (
                    sum(m[Symbol("dvThermalToSteamTurbine"*_n)][tst,q,ts] for tst in p.techs.can_supply_steam_turbine, q in p.heating_loads) + 
                    sum(m[Symbol("dvHeatFromStorageToTurbine"*_n)][b,q,ts] for b in p.s.storage.types.hot, q in p.heating_loads)
                    )
                )
    # Constraint Steam Turbine Electric Production
    @constraint(m, SteamTurbineElectricProductionCon[t in p.techs.steam_turbine, ts in p.time_steps],
                m[Symbol("dvRatedProduction"*_n)][t,ts] == p.s.steam_turbine.electric_produced_to_thermal_consumed_ratio * (
                    sum(m[Symbol("dvThermalToSteamTurbine"*_n)][tst,q,ts] for tst in p.techs.can_supply_steam_turbine, q in p.heating_loads) +
                    sum(m[Symbol("dvHeatFromStorageToTurbine"*_n)][b,q,ts] for b in p.s.storage.types.hot, q in p.heating_loads)
                    )
                )
    if p.s.steam_turbine.charge_storage_only  #assume hot water TES first, hot sensible TES otherwise.
        if "HotThermalStorage" in p.s.storage.types.hot
            @constraint(m, TurbineToStorageOnly[t in p.techs.steam_turbine, q in p.heating_loads, ts in p.time_steps],
                m[Symbol("dvHeatingProduction"*_n)][t,q,ts] == m[Symbol("dvHeatToStorage"*_n)]["HotThermalStorage",t,q,ts]
            )
        elseif "HighTempThermalStorage" in p.s.storage.types.hot
            @constraint(m, TurbineToStorageOnly[t in p.techs.steam_turbine, q in p.heating_loads, ts in p.time_steps],
                m[Symbol("dvHeatingProduction"*_n)][t,q,ts] == m[Symbol("dvHeatToStorage"*_n)]["HighTempThermalStorage",t,q,ts]
            )
        else
            @warn "SteamTurbine.charge_storage_only is set to True, but no hot storage technologies exist."
        end
    end
    
    if !p.s.steam_turbine.can_waste_heat
        for t in p.techs.steam_turbine
            for q in p.heating_loads
                for ts in p.time_steps
                    fix(m[Symbol("dvProductionToWaste"*_n)][t,q,ts] , 0.0, force=true)
                end
            end
        end
    end
    
end

function add_steam_turbine_constraints(m, p; _n="")
    steam_turbine_production_constraints(m, p; _n)
    steam_turbine_thermal_input(m, p; _n)

    m[:TotalSteamTurbinePerUnitProdOMCosts] = @expression(m, p.third_party_factor * p.pwf_om *
        sum(p.s.steam_turbine.om_cost_per_kwh * p.hours_per_time_step *
        m[:dvRatedProduction][t, ts] for t in p.techs.steam_turbine, ts in p.time_steps)
    )
end