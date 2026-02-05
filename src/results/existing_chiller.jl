# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ExistingChiller` results keys:
- `thermal_to_storage_series_ton` # Thermal production to ColdThermalStorage
- `thermal_to_load_series_ton` # Thermal production to cooling load
- `electric_consumption_series_kw`
- `annual_electric_consumption_kwh`
- `annual_thermal_production_tonhour`

"""
function add_existing_chiller_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    r = Dict{String, Any}()

	r["size_ton"] = round(value(m[Symbol("dvSize"*_n)]["ExistingChiller"]) * p.s.existing_chiller.max_thermal_factor_on_peak_load / KWH_THERMAL_PER_TONHOUR, digits=3)

	@expression(m, ELECCHLtoTES[ts in p.time_steps],
		sum(p.scenario_probabilities[s] * m[:dvProductionToStorage][s,b,"ExistingChiller",ts] for s in 1:p.n_scenarios, b in p.s.storage.types.cold)
    )
	r["thermal_to_storage_series_ton"] = round.(value.(ELECCHLtoTES / KWH_THERMAL_PER_TONHOUR), digits=3)   

	@expression(m, ELECCHLtoLoad[ts in p.time_steps],
		sum(p.scenario_probabilities[s] * m[:dvCoolingProduction][s,"ExistingChiller", ts] for s in 1:p.n_scenarios)
			- ELECCHLtoTES[ts]
    )
	r["thermal_to_load_series_ton"] = round.(value.(ELECCHLtoLoad / KWH_THERMAL_PER_TONHOUR).data, digits=3)

	@expression(m, ELECCHLElecConsumptionSeries[ts in p.time_steps],
		sum(p.scenario_probabilities[s] * m[:dvCoolingProduction][s,"ExistingChiller", ts] / p.cooling_cop["ExistingChiller"][ts] for s in 1:p.n_scenarios)
    )
	r["electric_consumption_series_kw"] = round.(value.(ELECCHLElecConsumptionSeries).data, digits=3)

	@expression(m, Year1ELECCHLElecConsumption,
		p.hours_per_time_step * sum(p.scenario_probabilities[s] * m[:dvCoolingProduction][s,"ExistingChiller", ts] / p.cooling_cop["ExistingChiller"][ts]
			for s in 1:p.n_scenarios, ts in p.time_steps)
    )
	r["annual_electric_consumption_kwh"] = round(value(Year1ELECCHLElecConsumption), digits=3)

	@expression(m, Year1ELECCHLThermalProd,
		p.hours_per_time_step * sum(p.scenario_probabilities[s] * m[:dvCoolingProduction][s,"ExistingChiller", ts]
			for s in 1:p.n_scenarios, ts in p.time_steps)
    )
	r["annual_thermal_production_tonhour"] = round(value(Year1ELECCHLThermalProd / KWH_THERMAL_PER_TONHOUR), digits=3)

    d["ExistingChiller"] = r
	nothing
end