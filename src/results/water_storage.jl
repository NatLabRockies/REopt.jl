# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`UpperReservoir` results keys:
- `combined_upstream_and_downstream_resevoir_costs` the turbine input into the model capacity
- `upstream_reservoir_water_capacity_cubic_meters`
- `upstream_reservoir_water_volume_cubic_meters`
- `input_to_model_tributary_water_flow`
- `upstream_reservoir_lifecycle_fixed_om_cost_after_tax`
- `upper_reservior_initial_capital_costs`

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""

function add_upper_reservoir_water_storage_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	# Adds the `WaterPower` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
	# Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()

	r["combined_upstream_and_downstream_resevoir_costs"] = m[Symbol("WaterStorageCapCosts"*_n)]

	# Upstream reservoir volume
	r["upstream_reservoir_water_capacity_cubic_meters"] = round.(value.(m[Symbol("dvUpperReservoirCapacity"*_n)]), digits=3)
	
	if r["upstream_reservoir_water_capacity_cubic_meters"] > 0
		upstream_reservoir_volume = @expression(m, [ts in p.time_steps], m[Symbol("dvWaterVolume"*_n)][ts])
		r["upstream_reservoir_water_volume_cubic_meters"] = round.(value.(upstream_reservoir_volume).data, digits=3) 

		# Water flow into upstream reservoir (input into the model)
		r["input_to_model_tributary_water_flow"] = p.s.upper_reservoir.water_inflow_cubic_meter_per_second
		
		UpstreamReservoirPerUnitSizeOMCosts = @expression(m, p.third_party_factor * p.pwf_om * p.s.upper_reservoir.om_cost_per_cubic_meter * m[Symbol("dvUpperReservoirCapacity"*_n)])
		r["upstream_reservoir_lifecycle_fixed_om_cost_after_tax"]	= round(value(UpstreamReservoirPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
		r["upper_reservior_initial_capital_costs"] = p.s.upper_reservoir.cost_per_cubic_meter_upper_reservoir * m[Symbol("dvUpperReservoirCapacity"*_n)]
	end

	d["UpperReservoir"] = r
    nothing
end


"""
`DownstreamReservoir` results keys:
- `downstream_reservoir_water_volume_cubic_meters` the turbine input into the model capacity
- `downstream_reservoir_water_capacity_cubic_meters`
- `downstream_reservoir_water_outflow_cubic_meters_per_second`
- `downstream_reservoir_lifecycle_fixed_om_cost_after_tax`
- `downstream_reservior_initial_capital_costs`
- `combined_upstream_and_downstream_resevoir_costs`

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""

function add_downstream_reservoir_water_storage_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	# Adds the `WaterPower` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
	# Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()

	# Downstream reservoir volume
	downstream_reservoir_volume = @expression(m, [ts in p.time_steps], m[Symbol("dvDownstreamReservoirWaterVolume"*_n)][ts])
	r["downstream_reservoir_water_volume_cubic_meters"] = round.(value.(downstream_reservoir_volume).data, digits=3) 
	r["downstream_reservoir_water_capacity_cubic_meters"] = round.(value.(m[Symbol("dvDownstreamReservoirCapacity"*_n)]), digits=3)
	
	# Water flow out of downstream reservoir
	downstream_reservoir_water_outflow = @expression(m, [ts in p.time_steps], m[Symbol("dvDownstreamReservoirWaterOutflow"*_n)][ts])
	r["downstream_reservoir_water_outflow_cubic_meters_per_second"] = round.(value.(downstream_reservoir_water_outflow).data, digits = 3)
	
	# Downstream reservoir costs
	DownstreamReservoirPerUnitSizeOMCosts = @expression(m,p.third_party_factor * p.pwf_om * p.s.downstream_reservoir.om_cost_per_cubic_meter * m[Symbol("dvDownstreamReservoirCapacity"*_n)])
	r["downstream_reservoir_lifecycle_fixed_om_cost_after_tax"]	= round(value(DownstreamReservoirPerUnitSizeOMCosts) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
	r["downstream_reservior_initial_capital_costs"] = p.s.downstream_reservoir.cost_per_cubic_meter_downstream_reservoir * m[Symbol("dvDownstreamReservoirCapacity"*_n)]
	r["combined_upstream_and_downstream_resevoir_costs"] = m[Symbol("WaterStorageCapCosts"*_n)]
	
	d["DownstreamReservoir"] = r
    nothing
end


