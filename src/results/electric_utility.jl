# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ElectricUtility` results keys:
- `annual_energy_supplied_kwh` # Total energy supplied from the grid in an average year.
- `electric_to_load_series_kw` # Vector of power drawn from the grid to serve load.
- `electric_to_storage_series_kw` # Vector of power drawn from the grid to charge the battery.
- `annual_renewable_electricity_supplied_kwh` # Total renewable electricity supplied from the grid in an average year.
- `annual_emissions_tonnes_CO2` # Average annual total tons of CO2 emissions associated with the site's grid-purchased electricity. If include_exported_elec_emissions_in_total is False, this value only reflects grid purchases. Otherwise, it accounts for emissions offset from any export to the grid.
- `annual_emissions_tonnes_NOx` # Average annual total tons of NOx emissions associated with the site's grid-purchased electricity. If include_exported_elec_emissions_in_total is False, this value only reflects grid purchases. Otherwise, it accounts for emissions offset from any export to the grid.
- `annual_emissions_tonnes_SO2` # Average annual total tons of SO2 emissions associated with the site's grid-purchased electricity. If include_exported_elec_emissions_in_total is False, this value only reflects grid purchases. Otherwise, it accounts for emissions offset from any export to the grid.
- `annual_emissions_tonnes_PM25` # Average annual total tons of PM25 emissions associated with the site's grid-purchased electricity. If include_exported_elec_emissions_in_total is False, this value only reflects grid purchsaes. Otherwise, it accounts for emissions offset from any export to the grid.
- `lifecycle_emissions_tonnes_CO2` # Total tons of CO2 emissions associated with the site's grid-purchased electricity over the analysis period. If include_exported_elec_emissions_in_total is False, this value only reflects grid purchaes. Otherwise, it accounts for emissions offset from any export to the grid.
- `lifecycle_emissions_tonnes_NOx` # Total tons of NOx emissions associated with the site's grid-purchased electricity over the analysis period. If include_exported_elec_emissions_in_total is False, this value only reflects grid purchaes. Otherwise, it accounts for emissions offset from any export to the grid.
- `lifecycle_emissions_tonnes_SO2` # Total tons of SO2 emissions associated with the site's grid-purchased electricity over the analysis period. If include_exported_elec_emissions_in_total is False, this value only reflects grid purchaes. Otherwise, it accounts for emissions offset from any export to the grid.
- `lifecycle_emissions_tonnes_PM25` # Total tons of PM2.5 emissions associated with the site's grid-purchased electricity over the analysis period. If include_exported_elec_emissions_in_total is False, this value only reflects grid purchaes. Otherwise, it accounts for emissions offset from any export to the grid.
- `avert_emissions_region` # EPA AVERT region of the site. Used for health-related emissions from grid electricity (populated if default emissions values are used) and climate emissions if "co2_from_avert" is set to true. 
- `distance_to_avert_emissions_region_meters` # Distance in meters from the site to the nearest AVERT emissions region.
- `cambium_region` # NLR Cambium region of the site. Used for climate-related emissions from grid electricity (populated only if default (Cambium) climate emissions values are used)

!!! note "'Series' and 'Annual' energy and emissions outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy and emissions outputs averaged over the analysis period. 

!!! note "Emissions outputs" 
    By default, REopt uses marginal emissions rates for grid-purchased electricity. Marginal emissions rates are most appropriate for reporting a change in emissions (avoided or increased) rather than emissions totals.
    It is therefore recommended that emissions results from REopt (using default marginal emissions rates) be reported as the difference in emissions between the optimized and BAU case.
    Note also that the annual_emissions metrics are average annual emissions over the analysis period, accounting for expected changes in future grid emissions. 

"""
function add_electric_utility_results(m::JuMP.AbstractModel, p::AbstractInputs, d::Dict; _n="")
    # Adds the `ElectricUtility` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()

    # add a warning if the WHL benefit is the max benefit
    if :WHL in p.s.electric_tariff.export_bins
        if abs(sum(value.(m[Symbol("WHL_benefit"*_n)])) - 10*sum([ld*rate for (ld,rate) in zip(p.s.electric_load.loads_kw, p.s.electric_tariff.export_rates[:WHL])]) / value(m[Symbol("WHL_benefit"*_n)]))  <= 1e-3
            @warn """Wholesale benefit is at the maximum allowable by the model; the problem is likely unbounded without this 
            limit in place. Check the inputs to ensure that there are practical limits for max system sizes and that 
            the wholesale and retail electricity rates are accurate."""
        end
    end

    Year1UtilityEnergy = p.hours_per_time_step * sum(p.scenario_probabilities[s] * sum(value(m[Symbol("dvGridPurchase"*_n)][s, ts, tier]) 
        for ts in p.time_steps, tier in 1:p.s.electric_tariff.n_energy_tiers) for s in 1:p.n_scenarios)
    r["annual_energy_supplied_kwh"] = round(Year1UtilityEnergy, digits=2)

    if !isempty(p.s.storage.types.elec)
        GridToLoad = [sum(p.scenario_probabilities[s] * (sum(value(m[Symbol("dvGridPurchase"*_n)][s, ts, tier]) for tier in 1:p.s.electric_tariff.n_energy_tiers) - sum(value(m[Symbol("dvGridToStorage"*_n)][s, b, ts]) for b in p.s.storage.types.elec)) for s in 1:p.n_scenarios) for ts in p.time_steps]
        GridToBatt = [sum(p.scenario_probabilities[s] * sum(value(m[Symbol("dvGridToStorage"*_n)][s, b, ts]) for b in p.s.storage.types.elec) for s in 1:p.n_scenarios) for ts in p.time_steps]
    else
        GridToLoad = [sum(p.scenario_probabilities[s] * sum(value(m[Symbol("dvGridPurchase"*_n)][s, ts, tier]) for tier in 1:p.s.electric_tariff.n_energy_tiers) for s in 1:p.n_scenarios) for ts in p.time_steps]
        GridToBatt = zeros(length(p.time_steps))
    end
    
    r["electric_to_load_series_kw"] = round.(GridToLoad, digits=3)
    r["electric_to_storage_series_kw"] = round.(GridToBatt, digits=3)

    if _n=="" #only output emissions and RE results if not a multinode model
        r["lifecycle_emissions_tonnes_CO2"] = round(value(m[:Lifecycle_Emissions_Lbs_CO2_grid_net_if_selected]*TONNE_PER_LB), digits=2)
        r["lifecycle_emissions_tonnes_NOx"] = round(value(m[:Lifecycle_Emissions_Lbs_NOx_grid_net_if_selected]*TONNE_PER_LB), digits=2)
        r["lifecycle_emissions_tonnes_SO2"] = round(value(m[:Lifecycle_Emissions_Lbs_SO2_grid_net_if_selected]*TONNE_PER_LB), digits=2)
        r["lifecycle_emissions_tonnes_PM25"] = round(value(m[:Lifecycle_Emissions_Lbs_PM25_grid_net_if_selected]*TONNE_PER_LB), digits=2)
        r["annual_emissions_tonnes_CO2"] = r["lifecycle_emissions_tonnes_CO2"] / p.s.financial.analysis_years
        r["annual_emissions_tonnes_NOx"] = r["lifecycle_emissions_tonnes_NOx"] / p.s.financial.analysis_years
        r["annual_emissions_tonnes_SO2"] = r["lifecycle_emissions_tonnes_SO2"] / p.s.financial.analysis_years
        r["annual_emissions_tonnes_PM25"] = r["lifecycle_emissions_tonnes_PM25"] / p.s.financial.analysis_years

        r["avert_emissions_region"] = p.s.electric_utility.avert_emissions_region
        r["distance_to_avert_emissions_region_meters"] = p.s.electric_utility.distance_to_avert_emissions_region_meters
        r["cambium_region"] = p.s.electric_utility.cambium_region

        r["annual_renewable_electricity_supplied_kwh"] = round(value(m[:AnnualGridREEleckWh]), digits=3)
    end

    d["ElectricUtility"] = r

    nothing
end

"""
MPC `ElectricUtility` results keys:
- `energy_supplied_kwh` 
- `to_battery_series_kw`
- `to_load_series_kw`
"""
function add_electric_utility_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict; _n="")
    r = Dict{String, Any}()

    Year1UtilityEnergy = p.hours_per_time_step * 
        sum(m[Symbol("dvGridPurchase"*_n)][s, ts, tier] for s in 1:p.n_scenarios, ts in p.time_steps, 
                                                         tier in 1:p.s.electric_tariff.n_energy_tiers)
    r["energy_supplied_kwh"] = round(value(Year1UtilityEnergy), digits=2)

    if p.s.storage.attr["ElectricStorage"].size_kwh > 0
        GridToBatt = @expression(m, [ts in p.time_steps], 
            sum(m[Symbol("dvGridToStorage"*_n)][1, b, ts] for b in p.s.storage.types.elec) 
		)
        r["to_battery_series_kw"] = round.(value.(GridToBatt), digits=3).data
    else
        GridToBatt = zeros(length(p.time_steps))
    end
    GridToLoad = @expression(m, [ts in p.time_steps], 
        sum(m[Symbol("dvGridPurchase"*_n)][1, ts, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) - 
        GridToBatt[ts]
    )
    r["to_load_series_kw"] = round.(value.(GridToLoad), digits=3).data

    d["ElectricUtility"] = r
    nothing
end