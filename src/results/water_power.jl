# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`WaterPower` results keys:
- `turbines_electric_to_storage_series_kw`
- `turbines_electric_curtailed_series_kw`
- `turbines_electric_to_grid_series_kw`
- `turbines_electric_to_load_series_kw`
- `spillway_water_outflow_series_cubic_meters_per_second`
- `annual_energy_produced_kwh`
- `pumps_lifecycle_fixed_om_cost_after_tax`
- `pumps_initial_capital_costs`
- `pumps_water_flow_series_cubic_meters_per_second`
- `pumps_power_rating`
- `pumps_power_input_kw`
- `turbine_or_pump_active`
- `number_of_pumps_active`
- `individual_pump_results` subdictionary with the following results for each pump: `pump_power_rating`, `water_flow_series_cubic_meters_per_second`, `power_input_series_kw`, `pump_on_or_off_series`
- `turbines_size_kw`
- `turbines_lifecycle_fixed_om_cost_after_tax`
- `turbines_initial_capital_costs`
- `turbines_water_outflow_series_cubic_meters_per_second`
- `turbines_power_output_series_kw`
- `individual_turbine_results` subdictionary with the following results for each turbine: `turbine_power_rating`, `water_outflow_series_cubic_meters_per_second`, `electric_curtailed_series_kw`, `power_output_series_kw`, `turbine_on_or_off_series`, `power_to_load_series_kw`, `power_to_battery_series_kw`, `power_to_grid_series_kw` 

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""

function add_water_power_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	# Adds the `WaterPower` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
	# Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()

	# sum these power flows from all of the turbines
	if !isempty(p.s.storage.types.elec)
		water_powerToBatt_raw_data = @expression(m, [ts in p.time_steps],
			sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for b in p.s.storage.types.elec, t in p.techs.water_power))
		water_powerToBatt = round.(value.(water_powerToBatt_raw_data).data, digits=3)
	else
		water_powerToBatt = zeros(length(p.time_steps))
	end
	r["turbines_electric_to_storage_series_kw"] = water_powerToBatt
	
	# Compute the curtailed power
	HydroCurtailment = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvCurtail"*_n)][t, ts] for t in p.techs.water_power))
	r["turbines_electric_curtailed_series_kw"] = round.(value.(HydroCurtailment).data, digits=3)

	# WaterPower to grid
	water_powerToGrid = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvProductionToGrid"*_n)][t, u, ts] for t in p.techs.water_power, u in p.export_bins_by_tech[t]))
	r["turbines_electric_to_grid_series_kw"] = round.(value.(water_powerToGrid).data, digits=3)

	# WaterPower to load
	water_powerToLoad = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvRatedProduction"*_n)][t, ts] * p.production_factor[t, ts] * p.levelization_factor[t]
			for t in p.techs.water_power) -
			water_powerToBatt[ts] - water_powerToGrid[ts] - HydroCurtailment[ts]
	)
	r["turbines_electric_to_load_series_kw"] = round.(value.(water_powerToLoad).data, digits=3)
	
	# Total water_power power output
	TotalWaterPowerPowerOutput = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvRatedProduction"*_n)][t, ts] * p.production_factor[t, ts] * p.levelization_factor[t]
			for t in p.techs.water_power) - HydroCurtailment[ts])
		
	# Spillway water flow
	spillway_water_flow = @expression(m, [ts in p.time_steps], m[Symbol("dvSpillwayWaterFlow"*_n)][ts])
	r["spillway_water_outflow_series_cubic_meters_per_second"] = round.(value.(spillway_water_flow).data, digits = 3)

	# Annual power production
	AnnualWaterPowerProd = @expression(m,
		p.hours_per_time_step * sum(m[Symbol("dvRatedProduction"*_n)][t,ts] * p.production_factor[t, ts] *
		p.levelization_factor[t]
			for t in p.techs.water_power, ts in p.time_steps)
	)
	r["annual_energy_produced_kwh"] = round(value(AnnualWaterPowerProd), digits=0) # includes curtailment
    	
	# Compile results for the pumps
	if ("downstream_reservoir" in p.s.water_storage) && (p.s.water_power.number_of_pumps > 0)
		
		PumpsPerUnitSizeOMCosts = @expression(m, p.third_party_factor * p.pwf_om * sum( p.om_cost_per_kw[t] * m[Symbol("dvSize"*_n)][t] for t in p.techs.water_power_pumps))
		r["pumps_lifecycle_fixed_om_cost_after_tax"] = round(value(PumpsPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
		r["pumps_initial_capital_costs"] = p.s.upstream_reservoir.cost_per_cubic_meter_upstream_reservoir * sum(m[Symbol("dvSize"*_n)][t] for t in p.techs.water_power_turbines)
	
		totalPumpedWaterFlow = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvPumpedWaterFlow"*_n)][t, ts] for t in p.techs.water_power_pumps))
		r["pumps_water_flow_series_cubic_meters_per_second"] = round.(value.(totalPumpedWaterFlow).data, digits=3)
		
		r["pumps_power_rating"] = round(sum(value.(m[Symbol("pump_power_rating"*_n)][i]) for i in p.techs.water_power_pumps), digits=3)  

		totalPumpPowerInput = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvPumpPowerInput"*_n)][t, ts] for t in p.techs.water_power_pumps))
		r["pumps_power_input_kw"] = round.(value.(totalPumpPowerInput).data, digits=3)
		
		TurbineOrPump = @expression(m, [ts in p.time_steps], m[Symbol("binTurbineOrPump"*_n)][ts])
		r["turbine_or_pump_active"] = round.(value.(TurbineOrPump).data, digits=3)
		NumberOfPumpsActive = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("binPumpingWaterActive"*_n)][t, ts] for t in p.techs.water_power_pumps))
		r["number_of_pumps_active"] = round.(value.(NumberOfPumpsActive).data, digits=3)

		r["individual_pump_results"] = Dict([])

		for i in p.techs.water_power_pumps		
			r["individual_pump_results"][string(i)*"_results"] = Dict([])
			
			r["individual_pump_results"][string(i)*"_results"]["pump_power_rating"] = round(value.(m[Symbol("pump_power_rating"*_n)][i]), digits=3)

			IndividualPumpedWaterFlow = @expression(m, [ts in p.time_steps], m[Symbol("dvPumpedWaterFlow"*_n)][i, ts])
			r["individual_pump_results"][string(i)*"_results"]["water_flow_series_cubic_meters_per_second"] = round.(value.(IndividualPumpedWaterFlow).data, digits=3)
			
			IndividualPumpPowerInput = @expression(m, [ts in p.time_steps], m[Symbol("dvPumpPowerInput"*_n)][i, ts])
			r["individual_pump_results"][string(i)*"_results"]["power_input_series_kw"] = round.(value.(IndividualPumpPowerInput).data, digits=3)
			r["individual_pump_results"][string(i)*"_results"]["pump_on_or_off_series"] = value.(m[Symbol("binPumpingWaterActive"*_n)][i,:]).data
			
		end
	end

	# Save results for the turbines
	r["turbines_size_kw"] = round(sum(value.(m[Symbol("dvSize"*_n)][i]) for i in p.techs.water_power_turbines), digits=3)  

	if r["turbines_size_kw"] > 0
		TurbinesPerUnitSizeOMCosts = @expression(m, p.third_party_factor * p.pwf_om * sum( p.om_cost_per_kw[t] * m[Symbol("dvSize"*_n)][t] for t in p.techs.water_power_turbines))
		r["turbines_lifecycle_fixed_om_cost_after_tax"] = round(value(TurbinesPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
		
		r["turbines_initial_capital_costs"] = p.s.water_power.turbine_cost_per_kw * sum(m[Symbol("dvSize"*_n)][t] for t in p.techs.water_power_turbines)
		
		# Water outflow from the turbines
		water_outflow_total = @expression(m, [ts in p.time_steps],
			sum(m[Symbol("dvWaterOutFlow"*_n)][t, ts] for t in p.techs.water_power_turbines) 
			)
		r["turbines_water_outflow_series_cubic_meters_per_second"] = round.(value.(water_outflow_total).data, digits=3) 

		r["turbines_power_output_series_kw"] = round.(value.(TotalWaterPowerPowerOutput).data, digits=3)
	
		r["individual_turbine_results"] = Dict([])

		for i in p.techs.water_power_turbines
					
			r["individual_turbine_results"][string(i)*"_results"] = Dict([])
			
			r["individual_turbine_results"][string(i)*"_results"]["turbine_power_rating"] = round(value.(m[Symbol("turbine_power_rating"*_n)][i]), digits=3)

			water_outflow_individual = @expression(m, [ts in p.time_steps], m[Symbol("dvWaterOutFlow"*_n)][i, ts])
			r["individual_turbine_results"][string(i)*"_results"]["water_outflow_series_cubic_meters_per_second"] = round.(value.(water_outflow_individual).data, digits=3)
			individual_turbine_power_curtailment = @expression(m, [ts in p.time_steps], m[Symbol("dvCurtail")][i, ts])
			r["individual_turbine_results"][string(i)*"_results"]["electric_curtailed_series_kw"] = round.(value.(individual_turbine_power_curtailment), digits=3)

			individual_turbine_power_output = @expression(m, [ts in p.time_steps], (m[Symbol("dvRatedProduction"*_n)][i, ts] * p.production_factor[i, ts] * p.levelization_factor[i]) - individual_turbine_power_curtailment[ts])
			r["individual_turbine_results"][string(i)*"_results"]["power_output_series_kw"] = round.(value.(individual_turbine_power_output).data, digits=3)
			r["individual_turbine_results"][string(i)*"_results"]["turbine_on_or_off_series"] = value.(m[Symbol("binTurbineActive"*_n)][i,:]).data

			individual_turbine_power_to_grid = @expression(m, [ts in p.time_steps], sum(m[Symbol("dvProductionToGrid"*_n)][i, u, ts] for u in p.export_bins_by_tech[i]))

			if !isempty(p.s.storage.types.elec)
				individual_turbine_power_to_batt_raw_data = @expression(m, [ts in p.time_steps],
					sum(m[Symbol("dvProductionToStorage"*_n)][b, i, ts] for b in p.s.storage.types.elec))
				individual_turbine_power_to_batt = value.(individual_turbine_power_to_batt_raw_data).data
			else
				individual_turbine_power_to_batt = zeros(length(p.time_steps))
			end
			individual_turbine_power_to_load = @expression(m, [ts in p.time_steps], 
			(m[Symbol("dvRatedProduction"*_n)][i, ts] * p.production_factor[i, ts] * p.levelization_factor[i]) - individual_turbine_power_to_batt[ts] - individual_turbine_power_to_grid[ts] - individual_turbine_power_curtailment[ts])

			r["individual_turbine_results"][string(i)*"_results"]["power_to_load_series_kw"] = round.(value.(individual_turbine_power_to_load).data, digits=3)
			r["individual_turbine_results"][string(i)*"_results"]["power_to_battery_series_kw"] = round.(individual_turbine_power_to_batt, digits=3)
			r["individual_turbine_results"][string(i)*"_results"]["power_to_grid_series_kw"] = round.(value.(individual_turbine_power_to_grid).data, digits=3)
		end

	end

	d["WaterPower"] = r
    nothing
end
