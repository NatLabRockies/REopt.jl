# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`WaterPower` results keys:
- `size_kw` the turbine input into the model capacity
- `electric_to_storage_series_kw` Vector of power sent to battery in an average year
- `electric_to_grid_series_kw` Vector of power sent to grid in an average year
- `electric_to_load_series_kw` Vector of power sent to load in an average year
- `annual_energy_produced_kwh` Average annual energy produced over analysis period

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
	r["electric_to_storage_series_kw_all_turbines_combined"] = water_powerToBatt
	
	# Compute the curtailed power
	HydroCurtailment = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvCurtail"*_n)][t, ts] for t in p.techs.water_power))
	r["electric_curtailed_series_kw_all_turbines_combined"] = round.(value.(HydroCurtailment).data, digits=3)

	# WaterPower to grid
	water_powerToGrid = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvProductionToGrid"*_n)][t, u, ts] for t in p.techs.water_power, u in p.export_bins_by_tech[t]))
	r["electric_to_grid_series_kw_all_turbines_combined"] = round.(value.(water_powerToGrid).data, digits=3)

	# WaterPower to load
	water_powerToLoad = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvRatedProduction"*_n)][t, ts] * p.production_factor[t, ts] * p.levelization_factor[t]
			for t in p.techs.water_power) -
			water_powerToBatt[ts] - water_powerToGrid[ts] - HydroCurtailment[ts]
	)
	r["electric_to_load_series_kw_all_turbines_combined"] = round.(value.(water_powerToLoad).data, digits=3)
	
	r["combined_upstream_and_downstream_resevoir_costs"] = m[Symbol("WaterStorageCapCosts"*_n)]
	
	# Total water_power power output
	TotalWaterPowerPowerOutput = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvRatedProduction"*_n)][t, ts] * p.production_factor[t, ts] * p.levelization_factor[t]
			for t in p.techs.water_power) - HydroCurtailment[ts])
	
	# Upstream reservoir volume
	r["upstream_reservoir_water_capacity_cubic_meters"] = round.(value.(m[Symbol("dvUpperReservoirCapacity"*_n)]), digits=3)
	
	if r["upstream_reservoir_water_capacity_cubic_meters"] > 0
		upstream_reservoir_volume = @expression(m, [ts in p.time_steps], m[Symbol("dvWaterVolume"*_n)][ts])
		r["upstream_reservoir_water_volume_cubic_meters"] = round.(value.(upstream_reservoir_volume).data, digits=3) 

		# Water flow into upstream reservoir (input into the model)
		r["input_to_model_tributary_water_flow"] = p.s.upper_reservoir.water_inflow_cubic_meter_per_second
		
		UpstreamReservoirPerUnitSizeOMCosts = @expression(m, p.third_party_factor * p.pwf_om * p.s.upstream_reservoir.om_cost_per_cubic_meter * m[upstream_reservoir_capacity])
		r["upstream_reservoir_lifecycle_fixed_om_cost_after_tax"]	= round(value(UpstreamReservoirPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
		r["upper_reservior_initial_capital_costs"] = p.s.upper_reservoir.cost_per_cubic_meter_upper_reservoir * m[Symbol("dvUpperReservoirCapacity"*_n)]
	end

	
	# Spillway water flow
	spillway_water_flow = @expression(m, [ts in p.time_steps], m[Symbol("dvSpillwayWaterFlow"*_n)][ts])
	r["spillway_water_outflow_cubic_meters_per_second"] = round.(value.(spillway_water_flow).data, digits = 3)

	# Annual power production
	AnnualWaterPowerProd = @expression(m,
		p.hours_per_time_step * sum(m[Symbol("dvRatedProduction"*_n)][t,ts] * p.production_factor[t, ts] *
		p.levelization_factor[t]
			for t in p.techs.water_power, ts in p.time_steps)
	)
	r["annual_energy_produced_kwh"] = round(value(AnnualWaterPowerProd), digits=0) # includes curtailment
    	
	if "downstream_reservoir" in p.s.water_storage
		# Downstream reservoir volume
		downstream_reservoir_volume = @expression(m, [ts in p.time_steps], m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][ts])
		r["downstream_reservoir_water_volume_cubic_meters"] = round.(value.(downstream_reservoir_volume).data, digits=3) 
		r["downstream_reservoir_water_capacity_cubic_meters"] = round.(value.(m[Symbol("dvDownstreamReservoirCapacity"*_n)]), digits=3)
		
		# Water flow out of downstream reservoir
		downstream_reservoir_water_outflow = @expression(m, [ts in p.time_steps], m[Symbol("dvDownstreamReservoirWaterOutflow"*_n)][ts])
		r["downstream_reservoir_water_outflow_cubic_meters_per_second"] = round.(value.(downstream_reservoir_water_outflow).data, digits = 3)
		
		DownstreamReservoirPerUnitSizeOMCosts = @expression(m,p.third_party_factor * p.pwf_om * p.s.downstream_reservoir.om_cost_per_cubic_meter * m[downstream_reservoir_capacity])
		r["downstream_reservoir_lifecycle_fixed_om_cost_after_tax"]	= round(value(DownstreamReservoirPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
		r["downstream_reservior_initial_capital_costs"] = p.s.downstream_reservoir.cost_per_cubic_meter_downstream_reservoir * m[Symbol("dvDownstreamReservoirCapacity"*_n)]
		
	end

	# Compile results for the pumps
	if ("downstream_reservoir" in p.s.water_storage) && (p.s.water_power.number_of_pumps > 0)
		
		PumpsPerUnitSizeOMCosts = @expression(m, p.third_party_factor * p.pwf_om * sum( p.om_cost_per_kw[t] * m[Symbol("dvSize"*_n)][t] for t in p.techs.pumps))
		r["lifecycle_fixed_om_cost_after_tax_pumps"] = round(value(PumpsPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
		r["combined_pumps_initial_capital_costs"] = p.s.upper_reservoir.cost_per_cubic_meter_upper_reservoir * sum(m[Symbol("dvSize"*_n)][t] for t in p.techs.turbines)
	
		totalPumpedWaterFlow = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvPumpedWaterFlow"*_n)][t, ts] for t in p.techs.water_power_pumps))
		r["pump_water_flow_all_pumps_combined"] = round.(value.(totalPumpedWaterFlow).data, digits=3)
		
		r["combined_pump_power_rating"] = round(sum(value.(m[Symbol("pump_power_rating"*_n)][i]) for i in p.techs.water_power_pumps), digits=3)  

		totalPumpPowerInput = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvPumpPowerInput"*_n)][t, ts] for t in p.techs.water_power_pumps))
		r["pump_power_input_kw_all_pumps_combined"] = round.(value.(totalPumpPowerInput).data, digits=3)
		
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
			r["individual_pump_results"][string(i)*"_results"]["pump_water_flow"] = round.(value.(IndividualPumpedWaterFlow).data, digits=3)
			
			IndividualPumpPowerInput = @expression(m, [ts in p.time_steps], m[Symbol("dvPumpPowerInput"*_n)][i, ts])
			r["individual_pump_results"][string(i)*"_results"]["pump_power_input_kw"] = round.(value.(IndividualPumpPowerInput).data, digits=3)
			r["individual_pump_results"][string(i)*"_results"]["pump_on_or_off"] = value.(m[Symbol("binPumpingWaterActive"*_n)][i,:]).data
			
		end
	end

	# Save results for the turbines
	r["combined_turbine_size_kw"] = round(sum(value.(m[Symbol("dvSize"*_n)][i]) for i in p.techs.water_power_turbines), digits=3)  

	if r["combined_turbine_size_kw"] > 0

		if p.s.water_power.existing_kw_per_turbine > 0
			r["fixed_size_kw_per_turbine"] = p.s.water_power.existing_kw_per_turbine 
		else
			r["fixed_size_kw_per_turbine"] = "N/A"
		end


		TurbinesPerUnitSizeOMCosts = @expression(m, p.third_party_factor * p.pwf_om * sum( p.om_cost_per_kw[t] * m[Symbol("dvSize"*_n)][t] for t in p.techs.turbines))
		r["lifecycle_fixed_om_cost_after_tax_turbines"] = round(value(TurbinesPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
		
		r["combined_turbines_initial_capital_costs"] = p.s.upper_reservoir.cost_per_cubic_meter_upper_reservoir * sum(m[Symbol("dvSize"*_n)][t] for t in p.techs.pumps)
		
		r["individual_turbine_results"] = Dict([])

		# Water outflow from the turbines
		water_outflow_total = @expression(m, [ts in p.time_steps],
			sum(m[Symbol("dvWaterOutFlow"*_n)][t, ts] for t in p.techs.water_power_turbines) 
			)
		r["water_outflow_for_all_turbines_combined"] = round.(value.(water_outflow_total).data, digits=3) 

		r["total_power_output_series_kw_all_turbines_combined"] = round.(value.(TotalWaterPowerPowerOutput).data, digits=3)
	


		for i in p.techs.water_power_turbines
					
			r["individual_turbine_results"][string(i)*"_results"] = Dict([])
			
			r["individual_turbine_results"][string(i)*"_results"]["turbine_power_rating"] = round(value.(m[Symbol("turbine_power_rating"*_n)][i]), digits=3)

			water_outflow_individual = @expression(m, [ts in p.time_steps], m[Symbol("dvWaterOutFlow"*_n)][i, ts])
			r["individual_turbine_results"][string(i)*"_results"]["water_outflow"] = round.(value.(water_outflow_individual).data, digits=3)
			individual_turbine_power_curtailment = @expression(m, [ts in p.time_steps], m[Symbol("dvCurtail")][i, ts])
			r["individual_turbine_results"][string(i)*"_results"]["electric_curtailed_series_kw"] = round.(value.(individual_turbine_power_curtailment), digits=3)

			individual_turbine_power_output = @expression(m, [ts in p.time_steps], (m[Symbol("dvRatedProduction"*_n)][i, ts] * p.production_factor[i, ts] * p.levelization_factor[i]) - individual_turbine_power_curtailment[ts])
			r["individual_turbine_results"][string(i)*"_results"]["power_output_kw"] = round.(value.(individual_turbine_power_output).data, digits=3)
			r["individual_turbine_results"][string(i)*"_results"]["turbine_on_or_off"] = value.(m[Symbol("binTurbineActive"*_n)][i,:]).data

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

			r["individual_turbine_results"][string(i)*"_results"]["power_to_load_kw"] = round.(value.(individual_turbine_power_to_load).data, digits=3)
			r["individual_turbine_results"][string(i)*"_results"]["power_to_battery_kw"] = round.(individual_turbine_power_to_batt, digits=3)
			r["individual_turbine_results"][string(i)*"_results"]["power_to_grid_kw"] = round.(value.(individual_turbine_power_to_grid).data, digits=3)
		end

	end

	d["WaterPower"] = r
    nothing
end
