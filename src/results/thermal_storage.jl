# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`HotThermalStorage` results keys:
- `size_gal` Optimal TES capacity, by volume [gal]
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over the first year [-]
- `storage_to_load_series_mmbtu_per_hour` Vector of power used to meet load over the first year [MMBTU/hr]

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""
function add_hot_storage_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict, b::String; _n="")
    # Adds the `HotThermalStorage` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    kwh_per_gal = get_kwh_per_gal(p.s.storage.attr[b].hot_water_temp_degF,
                                p.s.storage.attr[b].cool_water_temp_degF)
    
    r = Dict{String, Any}()
    size_kwh = round(value(m[Symbol("dvStorageEnergy"*_n)][b]), digits=3)
    r["size_kwh"] = size_kwh
    r["size_gal"] = round(size_kwh / kwh_per_gal, digits=0)

    if size_kwh != 0
    	soc = [sum(p.scenario_probabilities[s] * value(m[Symbol("dvStoredEnergy"*_n)][s, b, ts]) for s in 1:p.n_scenarios) for ts in p.time_steps]
        r["soc_series_fraction"] = round.(soc ./ size_kwh, digits=3)

        discharge = [sum(p.scenario_probabilities[s] * value(sum(m[Symbol("dvHeatFromStorage"*_n)][s,b,q,ts] for q in p.heating_loads)) for s in 1:p.n_scenarios) for ts in p.time_steps]
        
        if p.s.storage.attr[b].can_supply_steam_turbine && ("SteamTurbine" in p.techs.all)
            storage_to_turbine = [sum(p.scenario_probabilities[s] * value(sum(m[Symbol("dvHeatFromStorageToTurbine"*_n)][s,b,q,ts] for q in p.heating_loads)) for s in 1:p.n_scenarios) for ts in p.time_steps]
            r["storage_to_turbine_series_mmbtu_per_hour"] = round.(storage_to_turbine / KWH_PER_MMBTU, digits=7)
            r["storage_to_load_series_mmbtu_per_hour"] = round.((discharge .- storage_to_turbine) / KWH_PER_MMBTU, digits=7)
        else
            r["storage_to_load_series_mmbtu_per_hour"] = round.(discharge / KWH_PER_MMBTU, digits=7)
            r["storage_to_turbine_series_mmbtu_per_hour"] = zeros(length(p.time_steps))
        end

        if "SpaceHeating" in p.heating_loads && p.s.storage.attr[b].can_serve_space_heating
            @expression(m, HotTESToSpaceHeatingKW[ts in p.time_steps], 
                sum(p.scenario_probabilities[s] * m[Symbol("dvHeatFromStorage"*_n)][s,b,"SpaceHeating",ts] for s in 1:p.n_scenarios)
            )
        else
            @expression(m, HotTESToSpaceHeatingKW[ts in p.time_steps], 0.0)
        end
        r["storage_to_space_heating_load_series_mmbtu_per_hour"] = round.(value.(HotTESToSpaceHeatingKW) ./ KWH_PER_MMBTU, digits=5)

        if "DomesticHotWater" in p.heating_loads && p.s.storage.attr[b].can_serve_dhw
            @expression(m, HotTESToDHWKW[ts in p.time_steps], 
                sum(p.scenario_probabilities[s] * m[Symbol("dvHeatFromStorage"*_n)][s,b,"DomesticHotWater",ts] for s in 1:p.n_scenarios)
            )
        else
            @expression(m, HotTESToDHWKW[ts in p.time_steps], 0.0)
        end
        r["storage_to_dhw_load_series_mmbtu_per_hour"] = round.(value.(HotTESToDHWKW) ./ KWH_PER_MMBTU, digits=5)

        if "ProcessHeat" in p.heating_loads && p.s.storage.attr[b].can_serve_process_heat
            @expression(m, HotTESToProcessHeatKW[ts in p.time_steps], 
                sum(p.scenario_probabilities[s] * m[Symbol("dvHeatFromStorage"*_n)][s,b,"ProcessHeat",ts] for s in 1:p.n_scenarios)
            )
        else
            @expression(m, HotTESToProcessHeatKW[ts in p.time_steps], 0.0)
        end
        r["storage_to_process_heat_load_series_mmbtu_per_hour"] = round.(value.(HotTESToProcessHeatKW) ./ KWH_PER_MMBTU, digits=5)
    else
        r["soc_series_fraction"] = []
        r["storage_to_load_series_mmbtu_per_hour"] = []
        r["storage_to_turbine_series_mmbtu_per_hour"] = []
    end

    d[b] = r
    nothing
end

"""
MPC `HotThermalStorage` results keys:
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over the time horizon [-]
"""
function add_hot_storage_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict, b::String; _n="")
    #=
    Adds the Storage results to the dictionary passed back from `run_mpc` using the solved model `m` and the `MPCInputs` for node `_n`.
    Note: the node number is an empty string if evaluating a single `Site`.
    =#
    r = Dict{String, Any}()

    soc = (m[Symbol("dvStoredEnergy"*_n)][1, b, ts] for ts in p.time_steps)
    r["soc_series_fraction"] = round.(value.(soc) ./ p.s.storage.attr[b].size_kwh, digits=3)

    d[b] = r
    nothing
end

"""
`ColdThermalStorage` results:
- `size_gal` Optimal TES capacity, by volume [gal]
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over the first year [-]
- `storage_to_load_series_ton` Vector of power used to meet load over the first year [ton]
"""
function add_cold_storage_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict, b::String; _n="")
    #=
    Adds the `ColdThermalStorage` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    Note: the node number is an empty string if evaluating a single `Site`.
    =#

    kwh_per_gal = get_kwh_per_gal(p.s.storage.attr["ColdThermalStorage"].hot_water_temp_degF,
                                    p.s.storage.attr["ColdThermalStorage"].cool_water_temp_degF)
    
    r = Dict{String, Any}()
    size_kwh = round(value(m[Symbol("dvStorageEnergy"*_n)][b]), digits=3)
    r["size_gal"] = round(size_kwh / kwh_per_gal, digits=0)

    if size_kwh != 0
    	soc = [sum(p.scenario_probabilities[s] * value(m[Symbol("dvStoredEnergy"*_n)][s, b, ts]) for s in 1:p.n_scenarios) for ts in p.time_steps]
        r["soc_series_fraction"] = round.(soc ./ size_kwh, digits=3)

        discharge = [sum(p.scenario_probabilities[s] * value(m[Symbol("dvDischargeFromStorage"*_n)][s, b, ts]) for s in 1:p.n_scenarios) for ts in p.time_steps]
        r["storage_to_load_series_ton"] = round.(discharge / KWH_THERMAL_PER_TONHOUR, digits=7)
    else
        r["soc_series_fraction"] = []
        r["storage_to_load_series_ton"] = []
    end

    d[b] = r
    nothing
end

"""
MPC `ColdThermalStorage` results keys:
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over the time horizon [-]
"""
function add_cold_storage_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict, b::String; _n="")
    #= 
    Adds the ColdThermalStorage results to the dictionary passed back from `run_mpc` using the solved model `m` and the `MPCInputs` for node `_n`.
    Note: the node number is an empty string if evaluating a single `Site`.
    =#
    r = Dict{String, Any}()

    soc = (m[Symbol("dvStoredEnergy"*_n)][1, b, ts] for ts in p.time_steps)
    r["soc_series_fraction"] = round.(value.(soc) ./ p.s.storage.attr[b].size_kwh, digits=3)

    d[b] = r
    nothing
end

"""
`HighTempThermalStorage` results keys:
- `size_kwh` Optimal TES capacity, by energy capacity [kWh]
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over the first year [-]
- `storage_to_load_series_mmbtu_per_hour` Vector of power used to meet load over the first year [MMBTU/hr]

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""
function add_high_temp_thermal_storage_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict, b::String; _n="")
    # Adds the `HighTempThermalStorage` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.
    
    r = Dict{String, Any}()
    size_kwh = round(value(m[Symbol("dvStorageEnergy"*_n)][b]), digits=3)
    r["size_kwh"] = size_kwh  

    if size_kwh != 0
    	soc = [sum(p.scenario_probabilities[s] * value(m[Symbol("dvStoredEnergy"*_n)][s, b, ts]) for s in 1:p.n_scenarios) for ts in p.time_steps]
        r["soc_series_fraction"] = round.(soc ./ size_kwh, digits=3)

        discharge = [sum(p.scenario_probabilities[s] * value(sum(m[Symbol("dvHeatFromStorage"*_n)][s,b,q,ts] for b in p.s.storage.types.hot, q in p.heating_loads)) for s in 1:p.n_scenarios) for ts in p.time_steps]

        # TODO: add something to track heat to steam turbine?
        # discharge = (sum(m[Symbol("dvThermalToSteamTurbine"*_n)][b,q,ts] for b in p.s.storage.types.hot, q in p.heating_loads) for ts in p.time_steps)
        # r["storage_to_load_series_mmbtu_per_hour"] = round.(value.(discharge) / KWH_PER_MMBTU, digits=7)
        if p.s.storage.attr[b].can_supply_steam_turbine && ("SteamTurbine" in p.techs.all)
            storage_to_turbine = [sum(p.scenario_probabilities[s] * value(sum(m[Symbol("dvHeatFromStorageToTurbine"*_n)][s,b,q,ts] for q in p.heating_loads)) for s in 1:p.n_scenarios) for ts in p.time_steps]
            r["storage_to_turbine_series_mmbtu_per_hour"] = round.(storage_to_turbine / KWH_PER_MMBTU, digits=7)
            r["storage_to_load_series_mmbtu_per_hour"] = round.((discharge .- storage_to_turbine) / KWH_PER_MMBTU, digits=7)
        else
            r["storage_to_load_series_mmbtu_per_hour"] = round.(discharge / KWH_PER_MMBTU, digits=7)
            r["storage_to_turbine_series_mmbtu_per_hour"] = zeros(length(p.time_steps))
        end
    else
        r["soc_series_fraction"] = []
        r["storage_to_load_series_mmbtu_per_hour"] = []
        r["storage_to_turbine_series_mmbtu_per_hour"] = []
    end

    d[b] = r
    nothing
end
