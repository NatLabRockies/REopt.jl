# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ElectricStorage` results keys:
- `size_kw` Optimal inverter capacity
- `size_kwh` Optimal storage capacity
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over the first year
- `storage_to_load_series_kw` Vector of power used to meet load over the first year
- `initial_capital_cost` Upfront capital cost for storage and inverter
# The following results are reported if storage degradation is modeled:
- `state_of_health`
- `maintenance_cost`
- `replacement_month` # only applies is maintenance_strategy = "replacement"
- `residual_value`
- `total_residual_kwh` # only applies is maintenance_strategy = "replacement"

!!! note "'Series' and 'Annual' energy outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy outputs averaged over the analysis period. 

"""
function add_electric_storage_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict, b::String; _n="")
    # Adds the `Storage` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()
    r["size_kwh"] = round(value(m[Symbol("dvStorageEnergy"*_n)][b]), digits=2)
    r["size_kw"] = round(value(m[Symbol("dvStoragePower"*_n)][b]), digits=2)

    if r["size_kwh"] != 0
    	soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
        r["soc_series_fraction"] = round.(value.(soc) ./ r["size_kwh"], digits=3)

        discharge = (m[Symbol("dvDischargeFromStorage"*_n)][b, ts] for ts in p.time_steps)
        r["storage_to_load_series_kw"] = round.(value.(discharge), digits=3)

        r["initial_capital_cost"] = r["size_kwh"] * p.s.storage.attr[b].installed_cost_per_kwh +
            r["size_kw"] * p.s.storage.attr[b].installed_cost_per_kw +
            p.s.storage.attr[b].installed_cost_constant

        if p.s.storage.attr[b].model_degradation
            r["state_of_health"] = round.(value.(m[:SOH]).data / value.(m[:dvStorageEnergy])["ElectricStorage"], digits=3)
            r["maintenance_cost"] = value(m[:degr_cost])
            if p.s.storage.attr[b].degradation.maintenance_strategy == "replacement"
                r["replacement_month"] = round(Int, value(
                    sum(mth * m[:binSOHIndicatorChange][mth] for mth in 1:p.s.financial.analysis_years*12)
                ))
                # Calculate total healthy BESS capacity at end of analysis period.
                # Determine fraction of useful life left assuming same replacement frequency.
                # Multiply by 0.2 to scale residual useful life since entire BESS is replaced when SOH drops below 80%.
                # Total BESS capacity residual is (0.8 + residual useful fraction) * BESS capacity
                # If not replacements happen then useful capacity is SOH[end]*BESS capacity.
                if iszero(r["replacement_month"])
                    r["total_residual_kwh"] = r["state_of_health"][end]*r["size_kwh"]
                else
                    # SOH[end] can be negative, so alternate method to calculate residual healthy SOH.
                    total_replacements = (p.s.financial.analysis_years*12)/r["replacement_month"]
                    r["total_residual_kwh"] = r["size_kwh"]*(
                        0.2*(1 - (total_replacements - floor(total_replacements))) + 0.8
                    )
                end
            end
            r["residual_value"] = value(m[:residual_value])
        end
    else
        r["soc_series_fraction"] = []
        r["storage_to_load_series_kw"] = []
    end

    d[b] = r
    nothing
end

"""
MPC `ElectricStorage` results keys:
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over time horizon
"""
function add_electric_storage_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict, b::String; _n="")
    r = Dict{String, Any}()

    soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
    r["soc_series_fraction"] = round.(value.(soc) ./ p.s.storage.attr[b].size_kwh, digits=3)

    discharge = (m[Symbol("dvDischargeFromStorage"*_n)][b, ts] for ts in p.time_steps)
    r["to_load_series_kw"] = round.(value.(discharge), digits=3)

    d[b] = r
    nothing
end