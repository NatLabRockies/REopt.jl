# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`Wind` results keys:
- `size_kw` Optimal Wind capacity [kW]
- `lifecycle_om_cost_after_tax` Lifecycle operations and maintenance cost in present value, after tax
- `year_one_om_cost_before_tax` Operations and maintenance cost in the first year, before tax benefits
- `electric_to_storage_series_kw` Vector of power used to charge the battery over an average year
- `electric_to_grid_series_kw` Vector of power exported to the grid over an average year
- `annual_energy_exported_kwh` Average annual energy exported to the grid
- `electric_to_load_series_kw` Vector of power used to meet load over an average year
- `annual_energy_produced_kwh` Average annual energy produced, accounting for degradation. Includes curtailed energy.
- `lcoe_per_kwh` Levelized Cost of Energy produced by the PV system
- `electric_curtailed_series_kw` Vector of power curtailed over an average year
- `production_factor_series` Wind production factor in each time step, either provided by user or obtained from SAM

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 
"""
function add_wind_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	# Adds the `Wind` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
	# Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()
    t = "Wind"
	r["production_factor_series"] = Vector(p.production_factor[t, :])
	per_unit_size_om = @expression(m, p.third_party_factor * p.pwf_om * m[:dvSize][t] * p.om_cost_per_kw[t])

	r["size_kw"] = round(value(m[:dvSize][t]), digits=2)
	r["lifecycle_om_cost_after_tax"] = round(value(per_unit_size_om) * (1 - p.s.financial.owner_tax_rate_fraction), digits=0)
	r["year_one_om_cost_before_tax"] = round(value(per_unit_size_om) / (p.pwf_om * p.third_party_factor), digits=0)

	if !isempty(p.s.storage.types.elec)
		WindToStorage = (sum(m[:dvProductionToStorage][b, t, ts] for b in p.s.storage.types.elec) for ts in p.time_steps)
	else
		WindToStorage = zeros(length(p.time_steps))
	end
	r["electric_to_storage_series_kw"] = round.(value.(WindToStorage), digits=3)

    r["annual_energy_exported_kwh"] = 0.0
    if !isempty(p.s.electric_tariff.export_bins)
        WindToGrid = (sum(m[:dvProductionToGrid][t, u, ts] for u in p.export_bins_by_tech[t]) for ts in p.time_steps)
        r["electric_to_grid_series_kw"] = round.(value.(WindToGrid), digits=3)
        r["annual_energy_exported_kwh"] = round(
            sum(r["electric_to_grid_series_kw"]) * p.hours_per_time_step, digits=0)
	else
		WindToGrid = zeros(length(p.time_steps))
	end
	r["electric_to_grid_series_kw"] = round.(value.(WindToGrid), digits=3)
	
	WindToCUR = (m[Symbol("dvCurtail"*_n)][t, ts] for ts in p.time_steps)
    r["electric_curtailed_series_kw"] = round.(value.(WindToCUR), digits=3)
	
	TotalHourlyWindProd = value.(m[Symbol("dvRatedProduction"*_n)][t,ts] * p.production_factor[t, ts] for ts in p.time_steps)

	WindToLoad =(TotalHourlyWindProd[ts] 
			- r["electric_to_storage_series_kw"][ts] 
			- r["electric_to_grid_series_kw"][ts] 
			- r["electric_curtailed_series_kw"][ts] for ts in p.time_steps
	)
	r["electric_to_load_series_kw"] = round.(value.(WindToLoad), digits=3)

	AvgWindProd = (sum(TotalHourlyWindProd) * p.hours_per_time_step) * p.levelization_factor[t]
	r["annual_energy_produced_kwh"] = round(value(AvgWindProd), digits=0)

    r["lcoe_per_kwh"] = calculate_lcoe(p, r, p.s.wind)
	d[t] = r
    nothing
end
