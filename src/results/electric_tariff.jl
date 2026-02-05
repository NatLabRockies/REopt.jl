# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ElectricTariff` results keys:
- `lifecycle_energy_cost_after_tax` lifecycle cost of energy from the grid in present value, after tax
- `year_one_energy_cost_before_tax` cost of energy from the grid over the first year, before considering tax benefits
- `lifecycle_demand_cost_after_tax` lifecycle cost of power from the grid in present value, after tax
- `year_one_demand_cost_before_tax` cost of power from the grid over the first year, before considering tax benefits
- `lifecycle_fixed_cost_after_tax` lifecycle fixed cost in present value, after tax
- `year_one_fixed_cost_before_tax` fixed cost over the first year, before considering tax benefits
- `lifecycle_min_charge_adder_after_tax` lifecycle minimum charge in present value, after tax
- `year_one_min_charge_adder_before_tax` minimum charge over the first year, before considering tax benefits
- `year_one_bill_before_tax` sum of `year_one_energy_cost_before_tax`, `year_one_demand_cost_before_tax`, `year_one_fixed_cost_before_tax`, `year_one_min_charge_adder_before_tax`, and `year_one_coincident_peak_cost_before_tax`
- `lifecycle_export_benefit_after_tax` lifecycle export credits in present value, after tax
- `year_one_export_benefit_before_tax` export credits over the first year, before considering tax benefits. A positive value indicates a benefit. 
- `lifecycle_coincident_peak_cost_after_tax` lifecycle coincident peak charge in present value, after tax
- `year_one_coincident_peak_cost_before_tax` coincident peak charge over the first year

Outputs related to electric tariff (year-one rates and costs not escalated):
- `monthly_fixed_cost_series_before_tax` the fixed monthly cost of electricity for modeled meter per chosen electric tariff in \\\$/month
- `energy_rate_series` dictionary for cost of electricity, each key corresponds to a tier with value being \\\$/kWh timeseries
- `energy_rate_tier_limits` dictionary for energy rate tier limits, each key corresponds to a tier with value being kWh limit
- `energy_rate_average_series` average energy rate across all tiers as \\\$/kWh timeseries
- `facility_demand_monthly_rate_series` facility demand charge in \\\$/kW/month (keys = tiers, values = demand charge for each month)
- `facility_demand_monthly_rate_tier_limits` facility demand charge limits in kW (keys = tiers, values = demand limit for each month)
- `tou_demand_rate_series` is a dictionary with TOU demand charges in \\\$/kW as timeseries for each timestep
- `demand_rate_average_series` average TOU demand rate across all tiers as \\\$/kW timeseries
- `tou_demand_rate_tier_limits` TOU demand charge limits in kW

Outputs related to REopt calculated costs of electricity (year-one rates and costs not escalated):
- `energy_cost_series_before_tax` timeseries of cost of electricity purchases from the grid (grid to total net load) in \\\$
- `monthly_energy_cost_series_before_tax` Monthly energy costs, summed across all tiers in \\\$
- `monthly_facility_demand_cost_series_before_tax`  Monthly facility demand cost, dictionary by Tier number in \\\$/month
- `tou_demand_metrics` -> month: Month this TOU period applies to
- `tou_demand_metrics` -> tier: Tier of TOU period
- `tou_demand_metrics` -> demand_rate: \\\$/kW TOU demand charge
- `tou_demand_metrics` -> measured_tou_peak_demand: measured peak kW load in TOU period in kW
- `tou_demand_metrics` -> demand_charge_before_tax`: calculated demand charge in \\\$
- `monthly_tou_demand_cost_series_before_tax`  Monthly TOU demand costs, dictionary by Tier number in \\\$/month
- `monthly_demand_cost_series_before_tax` Monthly total facility plus TOU demand costs, summed across all tiers in \\\$/month

Prefix net_metering, wholesale, or net_metering_excess (export categories) for following outputs, all can be in results if relevant inputs are provided.
- `_export_rate_series` export rate timeseries for type of export category in \\\$/kWh
- `_electric_to_grid_series_kw` exported electricity timeseries for type of export category in kW
- `_monthly_export_series_kwh` monthly exported energy totals by export category in kWh
- `_monthly_export_cost_benefit_before_tax` monthly export benefit by export category in \\\$

!!! note "Handling of tiered rates"
	Energy and demand charges costs are returned as a dictionary with each key corresponding to a cost tier. 
    REopt assumes all TOU periods have the same tier limits

"""
function add_electric_tariff_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    # Adds the `ElectricTariff` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()
    m[Symbol("Year1UtilityEnergy"*_n)] = p.hours_per_time_step * 
        sum(p.scenario_probabilities[s] * m[Symbol("dvGridPurchase"*_n)][s, ts, tier] for s in 1:p.n_scenarios, ts in p.time_steps, tier in 1:p.s.electric_tariff.n_energy_tiers)

    r["lifecycle_energy_cost_after_tax"] = round(value(m[Symbol("TotalEnergyChargesUtil"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_energy_cost_before_tax"] = round(value(m[Symbol("TotalEnergyChargesUtil"*_n)]) / p.pwf_e, digits=2)

    r["lifecycle_demand_cost_after_tax"] = round(value(m[Symbol("TotalDemandCharges"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_demand_cost_before_tax"] = round(value(m[Symbol("TotalDemandCharges"*_n)]) / p.pwf_e, digits=2)
    
    r["lifecycle_fixed_cost_after_tax"] = round(m[Symbol("TotalFixedCharges"*_n)] * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_fixed_cost_before_tax"] = round(m[Symbol("TotalFixedCharges"*_n)] / p.pwf_e, digits=0)

    r["lifecycle_min_charge_adder_after_tax"] = round(value(m[Symbol("MinChargeAdder"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_min_charge_adder_before_tax"] = round(value(m[Symbol("MinChargeAdder"*_n)]) / p.pwf_e, digits=2)
                                
    r["lifecycle_export_benefit_after_tax"] = -1 * round(value(m[Symbol("TotalExportBenefit"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_export_benefit_before_tax"] = -1 * round(value(m[Symbol("TotalExportBenefit"*_n)]) / p.pwf_e, digits=0)
    r["year_one_export_benefit_after_tax"] = r["year_one_export_benefit_before_tax"] * (1 - p.s.financial.offtaker_tax_rate_fraction)

    r["lifecycle_coincident_peak_cost_after_tax"] = round(value(m[Symbol("TotalCPCharges"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_coincident_peak_cost_before_tax"] = round(value(m[Symbol("TotalCPCharges"*_n)]) / p.pwf_e, digits=2)
    
    r["year_one_bill_before_tax"] = r["year_one_energy_cost_before_tax"] + r["year_one_demand_cost_before_tax"] +
                                    r["year_one_fixed_cost_before_tax"]  + r["year_one_min_charge_adder_before_tax"] + r["year_one_coincident_peak_cost_before_tax"]
    
    r["year_one_bill_after_tax"] = r["year_one_bill_before_tax"] * (1 - p.s.financial.offtaker_tax_rate_fraction)


    r["monthly_fixed_cost_series_before_tax"] = repeat([p.s.electric_tariff.fixed_monthly_charge], 12)
    
    # energy cost dictionary and tier limits.
    r["energy_rate_series"] = Dict()
    for (idx,col) in enumerate(eachcol(p.s.electric_tariff.energy_rates))
       r["energy_rate_series"][string("Tier_", idx)] = col
    end
    r["energy_rate_tier_limits"] = Dict()
    for (idx,col) in enumerate(eachcol(p.s.electric_tariff.energy_tier_limits))
       r["energy_rate_tier_limits"][string("Tier_", idx)] = col
    end
    
    # Average energy rate across all tiers
    if !isempty(r["energy_rate_series"])
        tier_values = collect(values(r["energy_rate_series"]))
        # Calculate element-wise average across all tiers
        r["energy_rate_average_series"] = sum(tier_values) / length(tier_values)
    else
        r["energy_rate_average_series"] = Float64[]
    end

    # monthly facility demand charge and tier limits.
    r["facility_demand_monthly_rate_series"] = Dict()
    for (idx,col) in enumerate(eachcol(p.s.electric_tariff.monthly_demand_rates))
       r["facility_demand_monthly_rate_series"][string("Tier_", idx)] = col
    end
    r["facility_demand_monthly_rate_tier_limits"] = Dict()
    for (idx,col) in enumerate(eachcol(p.s.electric_tariff.monthly_demand_tier_limits))
       r["facility_demand_monthly_rate_tier_limits"][string("Tier_", idx)] = col
    end
    
    # demand charge timeseries (tou)
    r["tou_demand_rate_series"] = Dict()
    if !isempty(p.s.electric_tariff.tou_demand_rates)
        for (idx,col) in enumerate(eachcol(p.s.electric_tariff.tou_demand_rates))
            r["tou_demand_rate_series"][string("Tier_", idx)] = zeros(p.time_steps[end])
            for (ts, rate) in zip(p.s.electric_tariff.tou_demand_ratchet_time_steps, p.s.electric_tariff.tou_demand_rates[:,idx])
                r["tou_demand_rate_series"][string("Tier_", idx)][ts] .= rate
            end
        end
    end
    
    # Average TOU demand rate across all tiers
    if !isempty(r["tou_demand_rate_series"])
        tier_values = collect(values(r["tou_demand_rate_series"]))
        # Calculate element-wise average across all TOU tiers
        r["demand_rate_average_series"] = sum(tier_values) / length(tier_values)
    else
        r["demand_rate_average_series"] = Float64[]
    end

    # TOU tier limits
    r["tou_demand_rate_tier_limits"] = Dict()
    for (idx,col) in enumerate(eachcol(p.s.electric_tariff.tou_demand_tier_limits))
       r["tou_demand_rate_tier_limits"][string("Tier_", idx)] = col
    end

    # Grid to load - compute expected value across scenarios
    r["energy_cost_series_before_tax"] = Dict()
    for (idx,col) in enumerate(eachcol(p.s.electric_tariff.energy_rates))
       expected_grid_purchase = [sum(p.scenario_probabilities[s] * value(m[Symbol("dvGridPurchase"*_n)][s, ts, idx]) for s in 1:p.n_scenarios) for ts in p.time_steps]
       r["energy_cost_series_before_tax"][string("Tier_", idx)] = col .* expected_grid_purchase .* p.hours_per_time_step
    end
    
    if Dates.isleapyear(p.s.electric_load.year) # end dr on Dec 30th 11:59 pm.
        dr = DateTime(p.s.electric_load.year):Dates.Minute(Int(60*p.hours_per_time_step)):DateTime(p.s.electric_load.year,12,30,23,59)
    else
        dr = DateTime(p.s.electric_load.year):Dates.Minute(Int(60*p.hours_per_time_step)):DateTime(p.s.electric_load.year,12,31,23,59)
    end
    # Shift required to capture months identification in leap year.
    ts_shift = Int(24/p.hours_per_time_step)
    
    r["monthly_energy_cost_series_before_tax"] = []
    for mth in 1:12
        idx = findall(x -> Dates.month(x) == mth, dr)
        monthly_sum = 0.0
        for k in keys(r["energy_cost_series_before_tax"])
            monthly_sum += sum(r["energy_cost_series_before_tax"][k][idx])
        end
        push!(r["monthly_energy_cost_series_before_tax"], monthly_sum)
    end

    # monthly demand charges paid to utility - compute expected value across scenarios
    r["monthly_facility_demand_cost_series_before_tax"] = zeros(12)
    if !isempty(p.s.electric_tariff.monthly_demand_rates)
        for (idx,col) in enumerate(eachcol(p.s.electric_tariff.monthly_demand_rates))
            expected_peak_demand = [sum(p.scenario_probabilities[s] * value(m[Symbol("dvPeakDemandMonth"*_n)][s, mth, idx]) for s in 1:p.n_scenarios) for mth in 1:12]
            r["monthly_facility_demand_cost_series_before_tax"] .+= col .* expected_peak_demand
        end
    end

    # Create list, each row contains 
    r["tou_demand_metrics"] = Dict()
    r["tou_demand_metrics"]["month"] = []
    r["tou_demand_metrics"]["tier"] = []
    r["tou_demand_metrics"]["demand_rate"] = []
    r["tou_demand_metrics"]["measured_tou_peak_demand"] = []
    r["tou_demand_metrics"]["demand_charge_before_tax"] = []
    tou_demand_charges = Dict()
    for tier in 1:p.s.electric_tariff.n_tou_demand_tiers
        # Compute expected peak demand across scenarios for this tier
        expected_tou_peaks = [sum(p.scenario_probabilities[s] * value(m[Symbol("dvPeakDemandTOU"*_n)][s, r, tier]) for s in 1:p.n_scenarios) for r in 1:length(p.ratchets)]
        for (a,b,c) in zip(
                p.s.electric_tariff.tou_demand_ratchet_time_steps,
                p.s.electric_tariff.tou_demand_rates[:,tier],
                expected_tou_peaks)

            idx = a[1] + ts_shift # DateTime element to inspect for month determination. Shift ts by a day in case of leap year to capture December TOU ratchets.
            
            push!(r["tou_demand_metrics"]["month"], monthabbr(dr[idx]))
            push!(r["tou_demand_metrics"]["tier"], tier)
            push!(r["tou_demand_metrics"]["demand_rate"], b)
            push!(r["tou_demand_metrics"]["measured_tou_peak_demand"], c)
            push!(r["tou_demand_metrics"]["demand_charge_before_tax"], b*c)
            
            # initialize a dict to track each month's cumulative TOU demand charges.
            if !haskey(tou_demand_charges, month(dr[idx]))
                tou_demand_charges[month(dr[idx])] = 0.0
            end
            tou_demand_charges[month(dr[idx])] += b*c
        end
    end

    r["monthly_tou_demand_cost_series_before_tax"] = []
    if !isempty(tou_demand_charges)
        for mth in 1:12
            push!(r["monthly_tou_demand_cost_series_before_tax"], get(tou_demand_charges, mth, 0.0))
        end
    else
        for mth in 1:12
            push!(r["monthly_tou_demand_cost_series_before_tax"], 0.0)
        end
    end

    # Total monthly demand costs (facility + TOU)
    r["monthly_demand_cost_series_before_tax"] = r["monthly_facility_demand_cost_series_before_tax"] .+ r["monthly_tou_demand_cost_series_before_tax"]

    if p.s.settings.include_export_cost_series_in_results
        @info "Including electricity export compensation timeseries in ElectricTariff results."
        binmap = Dict()
        binmap[Symbol("WHL")] = "wholesale"
        binmap[Symbol("NEM")] = "net_metering"
        binmap[Symbol("EXC")] = "net_metering_excess"
        if !isempty(p.techs.elec)
            for bin in p.s.electric_tariff.export_bins
                rate_series = string(binmap[bin], "_export_rate_series")
                export_series = string(binmap[bin], "_electric_to_grid_series_kw")

                r[rate_series] = collect(p.s.electric_tariff.export_rates[bin])
                r[export_series] = collect(value.(sum(m[Symbol("dvProductionToGrid"*_n)][t, bin, :] for t in p.techs.elec)))

                r[string(binmap[bin], "_monthly_export_series_kwh")] = []
                r[string(binmap[bin], "_monthly_export_cost_benefit_before_tax")] = []
                for mth in 1:12
                    idx = findall(x -> Dates.month(x) == mth, dr)
                    push!(r[string(binmap[bin], "_monthly_export_series_kwh")], sum(r[export_series][idx]) / p.s.time_steps_per_hour)
                    push!(r[string(binmap[bin], "_monthly_export_cost_benefit_before_tax")], sum((r[rate_series].*r[export_series])[idx]) / p.s.time_steps_per_hour)
                end
            end
        end
    end

    d["ElectricTariff"] = r
    nothing
end

"""
MPC `ElectricTariff` results keys:
- `energy_cost`
- `demand_cost`
- `export_benefit`
"""
function add_electric_tariff_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict; _n="")
    r = Dict{String, Any}()
    m[Symbol("energy_purchased"*_n)] = p.hours_per_time_step * 
        sum(m[Symbol("dvGridPurchase"*_n)][s, ts, tier] for s in 1:p.n_scenarios, ts in p.time_steps, tier in 1:p.s.electric_tariff.n_energy_tiers)

    r["energy_cost"] = round(value(m[Symbol("TotalEnergyChargesUtil"*_n)]), digits=2)

    r["demand_cost"] = round(value(m[Symbol("TotalDemandCharges"*_n)]), digits=2)
                                
    r["export_benefit"] = -1 * round(value(m[Symbol("TotalExportBenefit"*_n)]), digits=0)
    
    d["ElectricTariff"] = r
    nothing
end