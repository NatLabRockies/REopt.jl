# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ElectricStorage` results keys:
- `size_kw` Optimal inverter capacity
- `size_kwh` Optimal storage capacity
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over the first year
- `storage_to_load_series_kw` Vector of power used to meet load over the first year
- `storage_to_electrolyzer_series_kw` Vector of power used by electrolyzer over the first year
- `storage_to_compressor_series_kw` Vector of power used by compressor over the first year
- `initial_capital_cost` Upfront capital cost for storage and inverter
# The following results are reported if storage degradation is modeled:
- `state_of_health`
- `maintenance_cost`
- `replacement_month`

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
        r["soc_series_fraction"] = round.(value.(soc) ./ r["size_kwh"], digits=6)

        r["initial_capital_cost"] = r["size_kwh"] * p.s.storage.attr[b].installed_cost_per_kwh +
            r["size_kw"] * p.s.storage.attr[b].installed_cost_per_kw

        if p.s.storage.attr[b].model_degradation
            r["state_of_health"] = value.(m[:SOH]).data / value.(m[:dvStorageEnergy])["ElectricStorage"];
            r["maintenance_cost"] = value(m[:degr_cost])
            if p.s.storage.attr[b].degradation.maintenance_strategy == "replacement"
                r["replacement_month"] = round(Int, value(
                    sum(mth * m[:binSOHIndicatorChange][mth] for mth in 1:p.s.financial.analysis_years*12)
                ))
            end
            r["residual_value"] = value(m[:residual_value])
         end

        if !isempty(p.techs.electrolyzer)
            BattToElectrolyzer = (m[Symbol("dvStorageToElectrolyzer"*_n)][b, ts] for ts in p.time_steps)
            r["storage_to_electrolyzer_series_kw"] = round.(value.(BattToElectrolyzer), digits=3)
        end

        if !isempty(p.techs.compressor)
            BattToCompressor = (m[Symbol("dvStorageToCompressor"*_n)][b, ts] for ts in p.time_steps)
            r["storage_to_compressor_series_kw"] = round.(value.(BattToCompressor), digits=3)
        end

        BattToLoad = (m[Symbol("dvDischargeFromStorage"*_n)][b, ts] 
                        - m[Symbol("dvStorageToElectrolyzer"*_n)][b, ts] 
                        - m[Symbol("dvStorageToCompressor"*_n)][b, ts] for ts in p.time_steps)
        r["storage_to_load_series_kw"] = round.(value.(BattToLoad), digits=3)

    else
        r["soc_series_fraction"] = []
        r["storage_to_load_series_kw"] = []
        r["storage_to_electrolyzer_series_kw"] = []
        r["storage_to_compressor_series_kw"] = []
    end

    d[b] = r
    nothing
end

"""
MPC `ElectricStorage` results keys:
- `soc_series_fraction` Vector of normalized (0-1) state of charge values over time horizon
- `storage_to_load_series_kw` Vector of power used to meet load
- `storage_to_electrolyzer_series_kw` Vector of power used by electrolyzer
- `storage_to_compressor_series_kw` Vector of power used by compressor
"""
function add_electric_storage_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict, b::String; _n="")
    r = Dict{String, Any}()

    soc = (m[Symbol("dvStoredEnergy"*_n)][b, ts] for ts in p.time_steps)
    r["soc_series_fraction"] = round.(value.(soc) ./ p.s.storage.attr[b].size_kwh, digits=5)

    if !isempty(p.techs.electrolyzer)
        BattToElectrolyzer = (m[Symbol("dvStorageToElectrolyzer"*_n)][b, ts] for ts in p.time_steps)
        r["storage_to_electrolyzer_series_kw"] = round.(value.(BattToElectrolyzer), digits=3)
    end

    if !isempty(p.techs.compressor)
        BattToCompressor = (m[Symbol("dvStorageToCompressor"*_n)][b, ts] for ts in p.time_steps)
        r["storage_to_compressor_series_kw"] = round.(value.(BattToCompressor), digits=3)
    end

    BattToLoad = (m[Symbol("dvDischargeFromStorage"*_n)][b, ts] 
                    - m[Symbol("dvStorageToElectrolyzer"*_n)][b, ts] 
                    - m[Symbol("dvStorageToCompressor"*_n)][b, ts] for ts in p.time_steps)
    r["storage_to_load_series_kw"] = round.(value.(BattToLoad), digits=3)

    d[b] = r
    nothing
end