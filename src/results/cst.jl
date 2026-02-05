# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

"""
`CST` results keys:
- `size_kw`  # Thermal production capacity size of the CST [kW]
- `size_mmbtu_per_hour`` Thermal production capacity size of the CST [MMBtu/hr]
- `electric_consumption_series_kw`  # Fuel consumption series [kW]
- `annual_electric_consumption_kwh`  # Fuel consumed in a year [kWh]
- `thermal_production_series_mmbtu_per_hour`  # Thermal energy production series [MMBtu/hr]
- `annual_thermal_production_mmbtu`  # Thermal energy produced in a year [MMBtu]
- `thermal_to_storage_series_mmbtu_per_hour`  # Thermal power production to TES (HotThermalStorage) series [MMBtu/hr]
- `thermal_to_high_temp_thermal_storage_series_mmbtu_per_hour`  # Thermal power production to TES (HotThermalStorage) series [MMBtu/hr]
- `thermal_to_steamturbine_series_mmbtu_per_hour`  # Thermal power production to SteamTurbine series [MMBtu/hr]
- `thermal_curtailed_series_mmbtu_per_hour` Thermal power wasted/unused/vented time-series array [MMBtu/hr]
- `thermal_to_load_series_mmbtu_per_hour`  # Thermal power production to serve the heating load series [MMBtu/hr]

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""

function add_concentrating_solar_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    r = Dict{String, Any}()
    r["size_kw"] = round(value(m[Symbol("dvSize"*_n)]["CST"]), digits=3)
    r["size_mmbtu_per_hour"] = round(value(m[Symbol("dvSize"*_n)]["CST"]) / KWH_PER_MMBTU, digits=3)
    @expression(m, CSTElectricConsumptionSeries[ts in p.time_steps],
        p.hours_per_time_step * sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s,"CST",q,ts] / p.heating_cop["CST"][ts] 
        for s in 1:p.n_scenarios, q in p.heating_loads))
    r["electric_consumption_series_kw"] = round.(value.(CSTElectricConsumptionSeries), digits=3)
    r["annual_electric_consumption_kwh"] = sum(r["electric_consumption_series_kw"])

    @expression(m, CSTThermalProductionSeries[ts in p.time_steps],
        sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s,"CST",q,ts] for s in 1:p.n_scenarios, q in p.heating_loads))
	r["thermal_production_series_mmbtu_per_hour"] = 
        round.(value.(CSTThermalProductionSeries) / KWH_PER_MMBTU, digits=5)
	r["annual_thermal_production_mmbtu"] = round(sum(r["thermal_production_series_mmbtu_per_hour"]), digits=3)

	if !isempty(p.s.storage.types.hot)
        @expression(m, CSTToHotTESKW[ts in p.time_steps],
		    sum(p.scenario_probabilities[s] * m[:dvHeatToStorage][s,b,"CST",q,ts] for s in 1:p.n_scenarios, b in p.s.storage.types.hot, q in p.heating_loads)
            )
        @expression(m, CSTToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 
            sum(p.scenario_probabilities[s] * m[:dvHeatToStorage][s,b,"CST",q,ts] for s in 1:p.n_scenarios, b in p.s.storage.types.hot)
            )
        if "HighTempThermalStorage" in p.s.storage.types.hot
            @expression(m, CSTToHotSensibleTESKW[ts in p.time_steps],
                sum(p.scenario_probabilities[s] * m[:dvHeatToStorage][s,"HighTempThermalStorage","CST",q,ts] for s in 1:p.n_scenarios, q in p.heating_loads)
                )
        else
            @expression(m, CSTToHotSensibleTESKW[ts in p.time_steps], 0.0)
        end
    else
        @expression(m, CSTToHotTESKW[ts in p.time_steps], 0.0)
        @expression(m, CSTToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 0.0)
        @expression(m, CSTToHotSensibleTESKW[ts in p.time_steps], 0.0)
    end
	r["thermal_to_storage_series_mmbtu_per_hour"] = round.(value.(CSTToHotTESKW) / KWH_PER_MMBTU, digits=3)
    r["thermal_to_high_temp_thermal_storage_series_mmbtu_per_hour"] = round.(value.(CSTToHotSensibleTESKW) / KWH_PER_MMBTU, digits=3)

    if !isempty(p.techs.steam_turbine) && p.s.cst.can_supply_steam_turbine
        @expression(m, CSTToSteamTurbine[ts in p.time_steps], sum(p.scenario_probabilities[s] * m[:dvThermalToSteamTurbine][s,"CST",q,ts] for s in 1:p.n_scenarios, q in p.heating_loads))
        @expression(m, CSTToSteamTurbineByQuality[q in p.heating_loads, ts in p.time_steps], sum(p.scenario_probabilities[s] * m[:dvThermalToSteamTurbine][s,"CST",q,ts] for s in 1:p.n_scenarios))
    else
        CSTToSteamTurbine = zeros(length(p.time_steps))
        @expression(m, CSTToSteamTurbineByQuality[q in p.heating_loads, ts in p.time_steps], 0.0)
    end
    r["thermal_to_steamturbine_series_mmbtu_per_hour"] = round.(value.(CSTToSteamTurbine) / KWH_PER_MMBTU, digits=3)

    @expression(m, CSTToWaste[ts in p.time_steps],
		sum(p.scenario_probabilities[s] * m[:dvProductionToWaste][s,"CST", q, ts] for s in 1:p.n_scenarios, q in p.heating_loads)
    )
    @expression(m, CSTToWasteByQualityKW[q in p.heating_loads, ts in p.time_steps],
		sum(p.scenario_probabilities[s] * m[:dvProductionToWaste][s,"CST", q, ts] for s in 1:p.n_scenarios)
    )
    r["thermal_curtailed_series_mmbtu_per_hour"] = round.(value.(CSTToWaste) / KWH_PER_MMBTU, digits=3)

	@expression(m, CSTToLoad[ts in p.time_steps],
		sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s,"CST", q, ts] for s in 1:p.n_scenarios, q in p.heating_loads) - CSTToHotTESKW[ts] - CSTToSteamTurbine[ts] - CSTToWaste[ts]
    )
	r["thermal_to_load_series_mmbtu_per_hour"] = round.(value.(CSTToLoad) / KWH_PER_MMBTU, digits=3)

    if "DomesticHotWater" in p.heating_loads && p.s.cst.can_serve_dhw
        @expression(m, CSTToDHWKW[ts in p.time_steps], 
            sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s,"CST","DomesticHotWater",ts] for s in 1:p.n_scenarios) - CSTToHotTESByQualityKW["DomesticHotWater",ts] - CSTToSteamTurbineByQuality["DomesticHotWater",ts] - CSTToWasteByQualityKW["DomesticHotWater",ts]
        )
    else
        @expression(m, CSTToDHWKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_dhw_load_series_mmbtu_per_hour"] = round.(value.(CSTToDHWKW ./ KWH_PER_MMBTU), digits=5)
    
    if "SpaceHeating" in p.heating_loads && p.s.cst.can_serve_space_heating
        @expression(m, CSTToSpaceHeatingKW[ts in p.time_steps], 
            sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s,"CST","SpaceHeating",ts] for s in 1:p.n_scenarios) - CSTToHotTESByQualityKW["SpaceHeating",ts] - CSTToSteamTurbineByQuality["SpaceHeating",ts] - CSTToWasteByQualityKW["SpaceHeating",ts]
        )
    else
        @expression(m, CSTToSpaceHeatingKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_space_heating_load_series_mmbtu_per_hour"] = round.(value.(CSTToSpaceHeatingKW ./ KWH_PER_MMBTU), digits=5)
    
    if "ProcessHeat" in p.heating_loads && p.s.cst.can_serve_process_heat
        @expression(m, CSTToProcessHeatKW[ts in p.time_steps], 
            sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s,"CST","ProcessHeat",ts] for s in 1:p.n_scenarios) - CSTToHotTESByQualityKW["ProcessHeat",ts] - CSTToSteamTurbineByQuality["ProcessHeat",ts] - CSTToWasteByQualityKW["ProcessHeat",ts]
        )
    else
        @expression(m, CSTToProcessHeatKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_process_heat_load_series_mmbtu_per_hour"] = round.(value.(CSTToProcessHeatKW ./ KWH_PER_MMBTU), digits=5)

    d["CST"] = r
	nothing
end