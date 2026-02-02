# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`ExistingHydropower` results keys:
- `size_kw` the turbine input into the model capacity
- `electric_to_storage_series_kw` Vector of power sent to battery in an average year
- `electric_to_grid_series_kw` Vector of power sent to grid in an average year
- `electric_to_load_series_kw` Vector of power sent to load in an average year
- `annual_energy_produced_kwh` Average annual energy produced over analysis period

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""

function add_existing_hydropower_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	# Adds the `ExistingHydropower` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
	# Note: the node number is an empty string if evaluating a single `Site`.
	# TODO: add _n to the hydropower code

    r = Dict{String, Any}()

	r["fixed_size_kw_per_turbine"] = p.s.existing_hydropower.existing_kw_per_turbine # round(value(sum(m[:dvSize][t] for t in p.techs.existing_hydropower)), digits=2)

	# TODO: add these financial results when financial parameters are added to the water power model
	#GenPerUnitSizeOMCosts = @expression(m, p.third_party_factor * p.pwf_om * sum(m[:dvSize][t] * p.om_cost_per_kw[t] for t in p.techs.gen))
	#GenPerUnitProdOMCosts = @expression(m, p.third_party_factor * p.pwf_om * p.hours_per_time_step *
 	#	sum(m[:dvRatedProduction][t, ts] * p.production_factor[t, ts] * p.s.generator.om_cost_per_kwh
 	#	for t in p.techs.gen, ts in p.time_steps)
 	#	)
	#r["lifecycle_fixed_om_cost_after_tax"] = round(value(GenPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
	#r["lifecycle_variable_om_cost_after_tax"] = round(value(m[:TotalPerUnitProdOMCosts]) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
	#r["lifecycle_fuel_cost_after_tax"] = round(value(m[:TotalGenFuelCosts]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
	#r["year_one_fuel_cost_before_tax"] = round(value(m[:TotalGenFuelCosts]) / p.pwf_fuel["Generator"], digits=2)
	#r["year_one_variable_om_cost_before_tax"] = round(value(GenPerUnitProdOMCosts) / (p.pwf_om * p.third_party_factor), digits=0)
	#r["year_one_fixed_om_cost_before_tax"] = round(value(GenPerUnitSizeOMCosts) / (p.pwf_om * p.third_party_factor), digits=0)

	# sum these power flows from all of the turbines
	if !isempty(p.s.storage.types.elec)
		hydropowerToBatt_raw_data = @expression(m, [ts in p.time_steps],
			sum(m[:dvProductionToStorage][b, t, ts] for b in p.s.storage.types.elec, t in p.techs.existing_hydropower))
		hydropowerToBatt = round.(value.(hydropowerToBatt_raw_data).data, digits=3)
	else
		hydropowerToBatt = zeros(length(p.time_steps))
	end
	r["electric_to_storage_series_kw_all_turbines_combined"] = hydropowerToBatt
	# Compute the curtailed power
	HydroCurtailment = @expression(m, [ts in p.time_steps],
		sum(m[Symbol("dvCurtail")][t, ts] for t in p.techs.existing_hydropower))
	
	r["electric_curtailed_series_kw_all_turbines_combined"] = round.(value.(HydroCurtailment).data, digits=3)

	# Hydropower to grid
	hydropowerToGrid = @expression(m, [ts in p.time_steps],
		sum(m[:dvProductionToGrid][t, u, ts] for t in p.techs.existing_hydropower, u in p.export_bins_by_tech[t])
	)
	r["electric_to_grid_series_kw_all_turbines_combined"] = round.(value.(hydropowerToGrid).data, digits=3)

	# Hydropower to load
	hydropowerToLoad = @expression(m, [ts in p.time_steps],
		sum(m[:dvRatedProduction][t, ts] * p.production_factor[t, ts] * p.levelization_factor[t]
			for t in p.techs.existing_hydropower) -
			hydropowerToBatt[ts] - hydropowerToGrid[ts] - HydroCurtailment[ts]
	)
	r["electric_to_load_series_kw_all_turbines_combined"] = round.(value.(hydropowerToLoad).data, digits=3)
	# Total hydropower power output
	TotalHydropowerPowerOutput = @expression(m, [ts in p.time_steps],
		sum(m[:dvRatedProduction][t, ts] * p.production_factor[t, ts] * p.levelization_factor[t]
			for t in p.techs.existing_hydropower) - HydroCurtailment[ts]
	)
	r["total_power_output_series_kw_all_turbines_combined"] = round.(value.(TotalHydropowerPowerOutput).data, digits=3)
	
	# Upstream reservoir volume
	upstream_reservoir_volume = @expression(m, [ts in p.time_steps], m[:dvWaterVolume][ts])
	r["upstream_reservoir_water_volume_cubic_meters"] = round.(value.(upstream_reservoir_volume).data, digits=3) 
	# Water flow into upstream reservoir (input into the model)
	r["input_to_model_tributary_water_flow"] = p.s.existing_hydropower.water_inflow_cubic_meter_per_second
	# Water outflow from the turbines
	water_outflow_total = @expression(m, [ts in p.time_steps],
		sum(m[:dvWaterOutFlow][t, ts] for t in p.techs.existing_hydropower) 
		)
	r["water_outflow_for_all_turbines_combined"] = round.(value.(water_outflow_total).data, digits=3) 

	# Spillway water flow
	spillway_water_flow = @expression(m, [ts in p.time_steps], m[:dvSpillwayWaterFlow][ts])
	r["spillway_water_outflow_cubic_meters_per_second"] = round.(value.(spillway_water_flow).data, digits = 3)

	# Water flow out of downstream reservoir
	if p.s.existing_hydropower.model_downstream_reservoir
		downstream_reservoir_water_outflow = @expression(m, [ts in p.time_steps], m[:dvDownstreamReservoirWaterOutflow][ts])
		r["downstream_reservoir_water_outflow_cubic_meters_per_second"] = round.(value.(downstream_reservoir_water_outflow).data, digits = 3)
	end
	# Annual power production
	AnnualExistingHydropowerProd = @expression(m,
		p.hours_per_time_step * sum(m[:dvRatedProduction][t,ts] * p.production_factor[t, ts] *
		p.levelization_factor[t]
			for t in p.techs.existing_hydropower, ts in p.time_steps)
	)
	r["annual_energy_produced_kwh"] = round(value(AnnualExistingHydropowerProd), digits=0) # includes curtailment
    
	
	if p.s.existing_hydropower.model_downstream_reservoir
		# Downstream reservoir volume
		downstream_reservoir_volume = @expression(m, [ts in p.time_steps], m[:dvDownstreamReservoirWaterVolume][ts])
		r["downstream_reservoir_water_volume_cubic_meters"] = round.(value.(downstream_reservoir_volume).data, digits=3) 
		
	end
	# Compile results for the pumps
	if (p.s.existing_hydropower.model_downstream_reservoir == true) && (p.s.existing_hydropower.number_of_pumps > 0)
		# Save combined results for all of the pumps
		totalPumpedWaterFlow = @expression(m, [ts in p.time_steps],
		sum(m[:dvPumpedWaterFlow][t, ts] for t in p.techs.existing_hydropower))
		r["pump_water_flow_all_pumps_combined"] = round.(value.(totalPumpedWaterFlow).data, digits=3)
		
		totalPumpPowerInput = @expression(m, [ts in p.time_steps],
		sum(m[:dvPumpPowerInput][t, ts] for t in p.techs.existing_hydropower))
		r["pump_power_input_kw_all_pumps_combined"] = round.(value.(totalPumpPowerInput).data, digits=3)
		
		TurbineOrPump = @expression(m, [ts in p.time_steps], m[:binTurbineOrPump][ts])
		r["turbine_or_pump_active"] = round.(value.(TurbineOrPump).data, digits=3)
		NumberOfPumpsActive = @expression(m, [ts in p.time_steps],
		sum(m[:binPumpingWaterActive][t, ts] for t in p.techs.existing_hydropower))
		r["number_of_pumps_active"] = round.(value.(NumberOfPumpsActive).data, digits=3)
		
		r["individual_pump_results"] = Dict([])
		for i in p.techs.existing_hydropower
			print("\n Debug 11")
			print("\n Saving results for pump "*string(i))
			
			r["individual_pump_results"][string(i)*"_results"] = Dict([])
			
			IndividualPumpedWaterFlow = @expression(m, [ts in p.time_steps], m[:dvPumpedWaterFlow][i, ts])
			r["individual_pump_results"][string(i)*"_results"]["pump_water_flow"] = round.(value.(IndividualPumpedWaterFlow).data, digits=3)
			
			IndividualPumpPowerInput = @expression(m, [ts in p.time_steps], m[:dvPumpPowerInput][i, ts])
			r["individual_pump_results"][string(i)*"_results"]["pump_power_input_kw"] = round.(value.(IndividualPumpPowerInput).data, digits=3)
			r["individual_pump_results"][string(i)*"_results"]["pump_on_or_off"] = value.(m[:binPumpingWaterActive][i,:]).data
			
		end
	end
	# Save results for the individual turbines
	r["individual_turbine_results"] = Dict([])

	for i in p.techs.existing_hydropower
		print("\n Saving results for turbine "*string(i))
	    
		r["individual_turbine_results"][string(i)*"_results"] = Dict([])
		
		water_outflow_individual = @expression(m, [ts in p.time_steps], m[:dvWaterOutFlow][i, ts])
		r["individual_turbine_results"][string(i)*"_results"]["water_outflow"] = round.(value.(water_outflow_individual).data, digits=3)
		individual_turbine_power_curtailment = @expression(m, [ts in p.time_steps], m[Symbol("dvCurtail")][i, ts])
		r["individual_turbine_results"][string(i)*"_results"]["electric_curtailed_series_kw"] = round.(value.(individual_turbine_power_curtailment), digits=3)

		individual_turbine_power_output = @expression(m, [ts in p.time_steps], (m[:dvRatedProduction][i, ts] * p.production_factor[i, ts] * p.levelization_factor[i]) - individual_turbine_power_curtailment[ts])
		r["individual_turbine_results"][string(i)*"_results"]["power_output_kw"] = round.(value.(individual_turbine_power_output).data, digits=3)
		r["individual_turbine_results"][string(i)*"_results"]["turbine_on_or_off"] = value.(m[:binTurbineActive][i,:]).data

		individual_turbine_power_to_grid = @expression(m, [ts in p.time_steps], sum(m[:dvProductionToGrid][i, u, ts] for u in p.export_bins_by_tech[i]))

		if !isempty(p.s.storage.types.elec)
			individual_turbine_power_to_batt_raw_data = @expression(m, [ts in p.time_steps],
				sum(m[:dvProductionToStorage][b, i, ts] for b in p.s.storage.types.elec))
			individual_turbine_power_to_batt = value.(individual_turbine_power_to_batt_raw_data).data
		else
			individual_turbine_power_to_batt = zeros(length(p.time_steps))
		end
		individual_turbine_power_to_load = @expression(m, [ts in p.time_steps], 
		(m[:dvRatedProduction][i, ts] * p.production_factor[i, ts] * p.levelization_factor[i]) - individual_turbine_power_to_batt[ts] - individual_turbine_power_to_grid[ts] - individual_turbine_power_curtailment[ts])

		r["individual_turbine_results"][string(i)*"_results"]["power_to_load_kw"] = round.(value.(individual_turbine_power_to_load).data, digits=3)
		r["individual_turbine_results"][string(i)*"_results"]["power_to_battery_kw"] = round.(individual_turbine_power_to_batt, digits=3)
		r["individual_turbine_results"][string(i)*"_results"]["power_to_grid_kw"] = round.(value.(individual_turbine_power_to_grid).data, digits=3)
	end
	d["ExistingHydropower"] = r
    nothing
end

# TODO: add results for hydropower MPC