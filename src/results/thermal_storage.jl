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
    	soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
        r["soc_series_fraction"] = round.(value.(soc) ./ size_kwh, digits=3)

        discharge = (sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) for ts in p.time_steps)
        
        if p.s.storage.attr[b].can_supply_steam_turbine && ("SteamTurbine" in p.techs.all)
            storage_to_turbine = (sum(m[Symbol("dvHeatFromStorageToTurbine"*_n)][b,q,ts] for q in p.heating_loads) for ts in p.time_steps)
            r["storage_to_turbine_series_mmbtu_per_hour"] = round.(value.(storage_to_turbine) / KWH_PER_MMBTU, digits=7)
            r["storage_to_load_series_mmbtu_per_hour"] = round.(value.(discharge .- storage_to_turbine) / KWH_PER_MMBTU, digits=7)
        else
            r["storage_to_load_series_mmbtu_per_hour"] = round.(value.(discharge) / KWH_PER_MMBTU, digits=7)
            r["storage_to_turbine_series_mmbtu_per_hour"] = zeros(length(p.time_steps))
        end

        if "SpaceHeating" in p.heating_loads && p.s.storage.attr[b].can_serve_space_heating
            @expression(m, HotTESToSpaceHeatingKW[ts in p.time_steps], 
                m[Symbol("dvHeatFromStorage"*_n)][b,"SpaceHeating",ts]
            )
        else
            @expression(m, HotTESToSpaceHeatingKW[ts in p.time_steps], 0.0)
        end
        r["storage_to_space_heating_load_series_mmbtu_per_hour"] = round.(value.(HotTESToSpaceHeatingKW) ./ KWH_PER_MMBTU, digits=5)

        if "DomesticHotWater" in p.heating_loads && p.s.storage.attr[b].can_serve_dhw
            @expression(m, HotTESToDHWKW[ts in p.time_steps], 
                m[Symbol("dvHeatFromStorage"*_n)][b,"DomesticHotWater",ts]
            )
        else
            @expression(m, HotTESToDHWKW[ts in p.time_steps], 0.0)
        end
        r["storage_to_dhw_load_series_mmbtu_per_hour"] = round.(value.(HotTESToDHWKW) ./ KWH_PER_MMBTU, digits=5)

        if "ProcessHeat" in p.heating_loads && p.s.storage.attr[b].can_serve_process_heat
            @expression(m, HotTESToProcessHeatKW[ts in p.time_steps], 
                m[Symbol("dvHeatFromStorage"*_n)][b,"ProcessHeat",ts]
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
- `storage_to_load_series_mmbtu_per_hour` Vector of hot thermal storage dispatch to heating load
"""
function add_hot_storage_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict, b::String; _n="")
    #=
    Adds the Storage results to the dictionary passed back from `run_mpc` using the solved model `m` and the `MPCInputs` for node `_n`.
    Note: the node number is an empty string if evaluating a single `Site`.
    =#
    r = Dict{String, Any}()

    soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
    r["soc_series_fraction"] = round.(value.(soc) ./ p.s.storage.attr[b].size_kwh, digits=3)

    discharge = (sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for b in p.s.storage.types.hot, q in p.heating_loads) for ts in p.time_steps)
    r["storage_to_load_series_mmbtu_per_hour"] = round.(value.(discharge) / KWH_PER_MMBTU, digits=7)
    
    # if p.s.storage.attr[b].include_discharge_pump_losses
    #     discharge_pumping_power_series_kw = (m[Symbol("dvDischargePumpPower"*_n)][b, ts] for ts in p.time_steps)
    #     r["discharge_pumping_power_series_kw"] = round.(value.(discharge_pumping_power_series_kw), digits=3)
    # end
    
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
    	soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
        r["soc_series_fraction"] = round.(value.(soc) ./ size_kwh, digits=3)

        discharge = (m[Symbol("dvDischargeFromStorage"*_n)][b, ts] for ts in p.time_steps)
        r["storage_to_load_series_ton"] = round.(value.(discharge) / KWH_THERMAL_PER_TONHOUR, digits=7)
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

    soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
    r["soc_series_fraction"] = round.(value.(soc) ./ p.s.storage.attr[b].size_kwh, digits=3)

    d[b] = r
    nothing
end

"""
`HighTempThermalStorage` results keys:
- `size_kwh` Optimal high temperature thermal storage capacity (kWh-thermal)
- `size_kw_charge` Optimal charge mechanism size (kW)
- `size_kw_discharge` Optimal discharge mechanism size (kW)
- `soc_series_fraction` Vector of normalized (0-1) state of charge values
- `storage_to_load_series_mmbtu_per_hour` Total thermal power production to serve heating loads [MMBtu/hr]
- `storage_to_space_heating_load_series_mmbtu_per_hour` Thermal power production to serve the space heating load series [MMBtu/hr]
- `storage_to_dhw_load_series_mmbtu_per_hour` Thermal power production to serve the domestic hot water heating load series [MMBtu/hr]
- `storage_to_process_heat_load_series_mmbtu_per_hour` Thermal power production to serve the process heating load series [MMBtu/hr]
- `discharge_pumping_power_series_kw` Vector of power consumed by the auxiliary pump during thermal storage discharge [kW-electrical]

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpreted as energy outputs averaged over the analysis period. 

"""
function add_high_temp_storage_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict, b::String; _n="")
    # Adds the `HighTempThermalStorage` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()
    size_kwh = round(value(m[Symbol("dvStorageEnergy"*_n)][b]), digits=3)
    r["size_kwh"] = size_kwh
    
    r["size_kw_charge"] = round(value(m[Symbol("dvStorageChargePower"*_n)][b]), digits=3)
    r["size_kw_discharge"] = round(value(m[Symbol("dvStorageDischargePower"*_n)][b]), digits=3)

    if size_kwh != 0
    	soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
        r["soc_series_fraction"] = round.(value.(soc) ./ size_kwh, digits=3)

        discharge = (sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) for ts in p.time_steps)
        r["storage_to_load_series_mmbtu_per_hour"] = round.(value.(discharge) ./ KWH_PER_MMBTU, digits=7)

        if "SpaceHeating" in p.heating_loads && p.s.storage.attr[b].can_serve_space_heating
            @expression(m, HighTempTESToSpaceHeatingKW[ts in p.time_steps], 
                m[Symbol("dvHeatFromStorage"*_n)][b,"SpaceHeating",ts]
            )
        else
            @expression(m, HighTempTESToSpaceHeatingKW[ts in p.time_steps], 0.0)
        end
        r["storage_to_space_heating_load_series_mmbtu_per_hour"] = collect(round.(value.(HighTempTESToSpaceHeatingKW) ./ KWH_PER_MMBTU, digits=5))

        if "DomesticHotWater" in p.heating_loads && p.s.storage.attr[b].can_serve_dhw
            @expression(m, HighTempTESToDHWKW[ts in p.time_steps], 
                m[Symbol("dvHeatFromStorage"*_n)][b,"DomesticHotWater",ts]
            )
        else
            @expression(m, HighTempTESToDHWKW[ts in p.time_steps], 0.0)
        end
        r["storage_to_dhw_load_series_mmbtu_per_hour"] = collect(round.(value.(HighTempTESToDHWKW) ./ KWH_PER_MMBTU, digits=5))

        if "ProcessHeat" in p.heating_loads && p.s.storage.attr[b].can_serve_process_heat
            @expression(m, HighTempTESToProcessHeatKW[ts in p.time_steps], 
                m[Symbol("dvHeatFromStorage"*_n)][b,"ProcessHeat",ts]
            )
        else
            @expression(m, HighTempTESToProcessHeatKW[ts in p.time_steps], 0.0)
        end
        r["storage_to_process_heat_load_series_mmbtu_per_hour"] = collect(round.(value.(HighTempTESToProcessHeatKW) ./ KWH_PER_MMBTU, digits=5))

    	# if p.s.storage.attr[b].include_discharge_pump_losses
        #     discharge_pumping_power_series_kw = (m[Symbol("dvDischargePumpPower"*_n)][b, ts] for ts in p.time_steps)
        #     r["discharge_pumping_power_series_kw"] = round.(value.(discharge_pumping_power_series_kw), digits=3)
        # end
    else
        r["soc_series_fraction"] = []
        r["storage_to_load_series_mmbtu_per_hour"] = []
        r["storage_to_turbine_series_mmbtu_per_hour"] = []
    end

    d[b] = r
    nothing
end


"""
MPC `HighTempThermalStorage` results keys:
- `soc_series_fraction` Vector of normalized (0-1) state of charge values
- `storage_to_load_series_mmbtu_per_hour` Total thermal power production to serve heating loads [MMBtu/hr]
- `storage_to_space_heating_load_series_mmbtu_per_hour` Thermal power production to serve the space heating load series [MMBtu/hr]
- `storage_to_dhw_load_series_mmbtu_per_hour` Thermal power production to serve the domestic hot water heating load series [MMBtu/hr]
- `storage_to_process_heat_load_series_mmbtu_per_hour` Thermal power production to serve the process heating load series [MMBtu/hr]
- `discharge_pumping_power_series_kw` Vector of power consumed by the auxiliary pump during thermal storage discharge [kW-electrical]
"""
function add_high_temp_storage_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict, b::String; _n="")
    # Adds the ColdThermalStorage results to the dictionary passed back from `run_mpc` using the solved model `m` and the `MPCInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()

    soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
    r["soc_series_fraction"] = round.(value.(soc) ./ p.s.storage.attr[b].size_kwh, digits=3)

    discharge = (sum(m[Symbol("dvHeatFromStorage"*_n)][b,q,ts] for q in p.heating_loads) for ts in p.time_steps)
    r["storage_to_load_series_mmbtu_per_hour"] = round.(value.(discharge) ./ KWH_PER_MMBTU, digits=7)

    if "SpaceHeating" in p.heating_loads && p.s.storage.attr[b].can_serve_space_heating
        @expression(m, HighTempTESToSpaceHeatingKW[ts in p.time_steps], 
            m[Symbol("dvHeatFromStorage"*_n)][b,"SpaceHeating",ts]
        )
    else
        @expression(m, HighTempTESToSpaceHeatingKW[ts in p.time_steps], 0.0)
    end
    r["storage_to_space_heating_load_series_mmbtu_per_hour"] = collect(round.(value.(HighTempTESToSpaceHeatingKW) ./ KWH_PER_MMBTU, digits=5))

    if "DomesticHotWater" in p.heating_loads && p.s.storage.attr[b].can_serve_dhw
        @expression(m, HighTempTESToDHWKW[ts in p.time_steps], 
            m[Symbol("dvHeatFromStorage"*_n)][b,"DomesticHotWater",ts]
        )
    else
        @expression(m, HighTempTESToDHWKW[ts in p.time_steps], 0.0)
    end
    r["storage_to_dhw_load_series_mmbtu_per_hour"] = collect(round.(value.(HighTempTESToDHWKW) ./ KWH_PER_MMBTU, digits=5))

    if "ProcessHeat" in p.heating_loads && p.s.storage.attr[b].can_serve_process_heat
        @expression(m, HighTempTESToProcessHeatKW[ts in p.time_steps], 
            m[Symbol("dvHeatFromStorage"*_n)][b,"ProcessHeat",ts]
        )
    else
        @expression(m, HighTempTESToProcessHeatKW[ts in p.time_steps], 0.0)
    end
    r["storage_to_process_heat_load_series_mmbtu_per_hour"] = collect(round.(value.(HighTempTESToProcessHeatKW) ./ KWH_PER_MMBTU, digits=5))

    if p.s.storage.attr[b].include_discharge_pump_losses
        discharge_pumping_power_series_kw = (m[Symbol("dvDischargePumpPower"*_n)][b, ts] for ts in p.time_steps)
        r["discharge_pumping_power_series_kw"] = round.(value.(discharge_pumping_power_series_kw), digits=3)
    end

    d[b] = r
    nothing
end
