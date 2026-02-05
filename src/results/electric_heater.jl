# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

"""
`ElectricHeater` results keys:
- `size_mmbtu_per_hour`  # Thermal production capacity size of the ElectricHeater [MMBtu/hr]
- `electric_consumption_series_kw`  # Fuel consumption series [kW]
- `annual_electric_consumption_kwh`  # Fuel consumed in a year [kWh]
- `thermal_production_series_mmbtu_per_hour`  # Thermal energy production series [MMBtu/hr]
- `annual_thermal_production_mmbtu`  # Thermal energy produced in a year [MMBtu]
- `thermal_to_storage_series_mmbtu_per_hour`  # Thermal power production to TES (HotThermalStorage) series [MMBtu/hr]
- `thermal_to_steamturbine_series_mmbtu_per_hour`  # Thermal power production to SteamTurbine series [MMBtu/hr]
- `thermal_to_load_series_mmbtu_per_hour`  # Thermal power production to serve the heating load series [MMBtu/hr]

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""

function add_electric_heater_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    r = Dict{String, Any}()
    r["size_mmbtu_per_hour"] = round(value(m[Symbol("dvSize"*_n)]["ElectricHeater"]) / KWH_PER_MMBTU, digits=3)
    @expression(m, ElectricHeaterElectricConsumptionSeries[ts in p.time_steps],
        p.hours_per_time_step * sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s, t,q,ts] / p.heating_cop[t][ts] 
        for s in 1:p.n_scenarios, q in p.heating_loads, t in p.techs.electric_heater))
    r["electric_consumption_series_kw"] = round.(value.(ElectricHeaterElectricConsumptionSeries), digits=3)
    r["annual_electric_consumption_kwh"] = sum(r["electric_consumption_series_kw"])

    @expression(m, ElectricHeaterThermalProductionSeries[ts in p.time_steps],
        sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s, t,q,ts] for s in 1:p.n_scenarios, q in p.heating_loads, t in p.techs.electric_heater))
	r["thermal_production_series_mmbtu_per_hour"] = 
        round.(value.(ElectricHeaterThermalProductionSeries) / KWH_PER_MMBTU, digits=5)
	r["annual_thermal_production_mmbtu"] = round(sum(r["thermal_production_series_mmbtu_per_hour"]), digits=3)

	if !isempty(p.s.storage.types.hot)
        @expression(m, ElectricHeaterToHotTESKW[ts in p.time_steps],
		    sum(p.scenario_probabilities[s] * m[:dvHeatToStorage][s, b,"ElectricHeater",q,ts] for s in 1:p.n_scenarios, b in p.s.storage.types.hot, q in p.heating_loads)
            )
        @expression(m, ElectricHeaterToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 
            sum(p.scenario_probabilities[s] * m[:dvHeatToStorage][s, b,"ElectricHeater",q,ts] for s in 1:p.n_scenarios, b in p.s.storage.types.hot)
            )
        if "HighTempThermalStorage" in p.s.storage.types.hot
            @expression(m, ElectricHeaterToHotSensibleTESKW[ts in p.time_steps],
                sum(p.scenario_probabilities[s] * m[:dvHeatToStorage][s, "HighTempThermalStorage","ElectricHeater",q,ts] for s in 1:p.n_scenarios, q in p.heating_loads)
                )
        else
            @expression(m, ElectricHeaterToHotSensibleTESKW[ts in p.time_steps], 0.0)
        end
    else
        @expression(m, ElectricHeaterToHotTESKW[ts in p.time_steps], 0.0)
        @expression(m, ElectricHeaterToHotTESByQualityKW[q in p.heating_loads, ts in p.time_steps], 0.0)
        @expression(m, ElectricHeaterToHotSensibleTESKW[ts in p.time_steps], 0.0)
    end
	r["thermal_to_storage_series_mmbtu_per_hour"] = round.(value.(ElectricHeaterToHotTESKW) / KWH_PER_MMBTU, digits=3)
    r["thermal_to_high_temp_thermal_storage_series_mmbtu_per_hour"] = round.(value.(ElectricHeaterToHotSensibleTESKW) / KWH_PER_MMBTU, digits=3)

    if !isempty(p.techs.steam_turbine) && p.s.electric_heater.can_supply_steam_turbine
        @expression(m, ElectricHeaterToSteamTurbine[ts in p.time_steps], sum(p.scenario_probabilities[s] * m[:dvThermalToSteamTurbine][s, "ElectricHeater",q,ts] for s in 1:p.n_scenarios, q in p.heating_loads))
        @expression(m, ElectricHeaterToSteamTurbineByQuality[q in p.heating_loads, ts in p.time_steps], sum(p.scenario_probabilities[s] * m[:dvThermalToSteamTurbine][s, "ElectricHeater",q,ts] for s in 1:p.n_scenarios))
    else
        ElectricHeaterToSteamTurbine = zeros(length(p.time_steps))
        @expression(m, ElectricHeaterToSteamTurbineByQuality[q in p.heating_loads, ts in p.time_steps], 0.0)
    end
    r["thermal_to_steamturbine_series_mmbtu_per_hour"] = round.(value.(ElectricHeaterToSteamTurbine) / KWH_PER_MMBTU, digits=3)

    @expression(m, ElectricHeaterToWaste[ts in p.time_steps],
        sum(p.scenario_probabilities[s] * m[:dvProductionToWaste][s, "ElectricHeater", q, ts] for s in 1:p.n_scenarios, q in p.heating_loads) 
    )
    @expression(m, ElectricHeaterToWasteByQualityKW[q in p.heating_loads, ts in p.time_steps], 
        sum(p.scenario_probabilities[s] * m[:dvProductionToWaste][s, "ElectricHeater",q,ts] for s in 1:p.n_scenarios)
    )

	@expression(m, ElectricHeaterToLoad[ts in p.time_steps],
		sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s, "ElectricHeater", q, ts] for s in 1:p.n_scenarios, q in p.heating_loads) - ElectricHeaterToHotTESKW[ts] - ElectricHeaterToSteamTurbine[ts] - ElectricHeaterToWaste[ts]
    )
	r["thermal_to_load_series_mmbtu_per_hour"] = round.(value.(ElectricHeaterToLoad) / KWH_PER_MMBTU, digits=3)

    if "DomesticHotWater" in p.heating_loads && p.s.electric_heater.can_serve_dhw
        @expression(m, ElectricHeaterToDHWKW[ts in p.time_steps], 
            sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s, "ElectricHeater","DomesticHotWater",ts] for s in 1:p.n_scenarios) - ElectricHeaterToHotTESByQualityKW["DomesticHotWater",ts] - ElectricHeaterToSteamTurbineByQuality["DomesticHotWater",ts] - ElectricHeaterToWasteByQualityKW["DomesticHotWater",ts]
        )
    else
        @expression(m, ElectricHeaterToDHWKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_dhw_load_series_mmbtu_per_hour"] = round.(value.(ElectricHeaterToDHWKW ./ KWH_PER_MMBTU), digits=5)
    
    if "SpaceHeating" in p.heating_loads && p.s.electric_heater.can_serve_space_heating
        @expression(m, ElectricHeaterToSpaceHeatingKW[ts in p.time_steps], 
            sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s, "ElectricHeater","SpaceHeating",ts] for s in 1:p.n_scenarios) - ElectricHeaterToHotTESByQualityKW["SpaceHeating",ts] - ElectricHeaterToSteamTurbineByQuality["SpaceHeating",ts] - ElectricHeaterToWasteByQualityKW["SpaceHeating",ts]
        )
    else
        @expression(m, ElectricHeaterToSpaceHeatingKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_space_heating_load_series_mmbtu_per_hour"] = round.(value.(ElectricHeaterToSpaceHeatingKW ./ KWH_PER_MMBTU), digits=5)
    
    if "ProcessHeat" in p.heating_loads && p.s.electric_heater.can_serve_process_heat
        @expression(m, ElectricHeaterToProcessHeatKW[ts in p.time_steps], 
            sum(p.scenario_probabilities[s] * m[:dvHeatingProduction][s, "ElectricHeater","ProcessHeat",ts] for s in 1:p.n_scenarios) - ElectricHeaterToHotTESByQualityKW["ProcessHeat",ts] - ElectricHeaterToSteamTurbineByQuality["ProcessHeat",ts] - ElectricHeaterToWasteByQualityKW["ProcessHeat",ts]
        )
    else
        @expression(m, ElectricHeaterToProcessHeatKW[ts in p.time_steps], 0.0)
    end
    r["thermal_to_process_heat_load_series_mmbtu_per_hour"] = round.(value.(ElectricHeaterToProcessHeatKW ./ KWH_PER_MMBTU), digits=5)

    d["ElectricHeater"] = r
	nothing
end