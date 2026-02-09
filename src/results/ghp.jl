# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    add_ghp_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")

Adds the `GHP` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
Note: the node number is an empty string if evaluating a single `Site`.

GHP results:
- `ghp_option_chosen` Integer option # chosen by model, possible 0 for no GHP
- `ghpghx_chosen_outputs` Dict of all outputs from GhpGhx.jl results of the chosen GhpGhx system
- `size_heat_pump_ton` Total heat pump capacity [ton]
- `avoided_capex_by_ghp_present_value` Present value of avoided capital cost by choosing GHP
- `space_heating_thermal_load_reduction_with_ghp_mmbtu_per_hour`
- `cooling_thermal_load_reduction_with_ghp_ton`
- `thermal_to_space_heating_load_series_mmbtu_per_hour`
- `thermal_to_dhw_load_series_mmbtu_per_hour`
- `thermal_to_load_series_ton`
- `annual_thermal_production_mmbtu`  # GHP's heating thermal power production in a year [MMBtu]
- `annual_thermal_production_tonhour`  # GHP's cooling thermal power production in a year [ton]

"""

function add_ghp_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	r = Dict{String, Any}()
    @expression(m, GHPOptionChosen, sum(g * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options))
	ghp_option_chosen = round(Int64, value(GHPOptionChosen)) # Use integer rounding to avoid precision issues
    r["ghp_option_chosen"] = ghp_option_chosen
    # r["size_heat_pump_ton"] = 0.0
    # r["size_wwhp_heating_pump_ton"] = 0.0
    # r["size_wwhp_cooling_pump_ton"] = 0.0

    if ghp_option_chosen >= 1
        
        r["hybrid_solution_type"] = p.s.ghp_option_list[ghp_option_chosen].hybrid_solution_type
        r["solve_time_min"] = p.s.ghp_option_list[ghp_option_chosen].solve_time_min
        r["number_of_boreholes_nonhybrid"] = p.s.ghp_option_list[ghp_option_chosen].number_of_boreholes_nonhybrid
        r["number_of_boreholes_auto_guess"] = p.s.ghp_option_list[ghp_option_chosen].number_of_boreholes_auto_guess
        r["number_of_boreholes_flipped_guess"] = p.s.ghp_option_list[ghp_option_chosen].number_of_boreholes_flipped_guess

        r["iterations_nonhybrid"] = p.s.ghp_option_list[ghp_option_chosen].iterations_nonhybrid
        r["iterations_auto_guess"] = p.s.ghp_option_list[ghp_option_chosen].iterations_auto_guess
        r["iterations_flipped_guess"] = p.s.ghp_option_list[ghp_option_chosen].iterations_flipped_guess

        r["ghpghx_chosen_outputs"] = p.s.ghp_option_list[ghp_option_chosen].ghpghx_response["outputs"]

        if r["ghpghx_chosen_outputs"]["heat_pump_configuration"] == "WSHP"
            r["size_heat_pump_ton"] = r["ghpghx_chosen_outputs"]["peak_combined_heatpump_thermal_ton"] * 
                p.s.ghp_option_list[ghp_option_chosen].heatpump_capacity_sizing_factor_on_peak_load
        elseif r["ghpghx_chosen_outputs"]["heat_pump_configuration"] == "WWHP"
            r["size_wwhp_heating_pump_ton"] = r["ghpghx_chosen_outputs"]["peak_heating_heatpump_thermal_ton"] * 
                p.s.ghp_option_list[ghp_option_chosen].heatpump_capacity_sizing_factor_on_peak_load
            r["size_wwhp_cooling_pump_ton"] = r["ghpghx_chosen_outputs"]["peak_cooling_heatpump_thermal_ton"] * 
                p.s.ghp_option_list[ghp_option_chosen].heatpump_capacity_sizing_factor_on_peak_load
        end
        @expression(m, HeatingThermalReductionWithGHP[ts in p.time_steps],
		    sum(p.space_heating_thermal_load_reduction_with_ghp_kw[g,ts] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options))
        r["space_heating_thermal_load_reduction_with_ghp_mmbtu_per_hour"] = round.(value.(HeatingThermalReductionWithGHP) ./ KWH_PER_MMBTU, digits=3)
        @expression(m, CoolingThermalReductionWithGHP[ts in p.time_steps],
		    sum(p.cooling_thermal_load_reduction_with_ghp_kw[g,ts] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options))
        
        @expression(m, HeatingThermalLoadServedWithGHP[ts in p.time_steps],
		    sum(p.ghp_heating_thermal_load_served_kw[g,ts] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options))    
        @expression(m, CoolingThermalLoadServedWithGHP[ts in p.time_steps],
		    sum(p.ghp_cooling_thermal_load_served_kw[g,ts] * m[Symbol("binGHP"*_n)][g] for g in p.ghp_options)) 

        r["cooling_thermal_load_reduction_with_ghp_ton"] = round.(value.(CoolingThermalReductionWithGHP) ./ KWH_THERMAL_PER_TONHOUR, digits=3)
        r["ghx_residual_value_present_value"] = value(m[:ResidualGHXCapCost])
        r["avoided_capex_by_ghp_present_value"] = value(m[:AvoidedCapexByGHP])
        r["thermal_to_space_heating_load_series_mmbtu_per_hour"] = round.(value.(HeatingThermalLoadServedWithGHP) ./ KWH_PER_MMBTU, digits=3)
        r["thermal_to_load_series_ton"] = round.(value.(CoolingThermalLoadServedWithGHP) ./ KWH_THERMAL_PER_TONHOUR, digits=3)
        r["annual_thermal_production_mmbtu"] = sum(r["thermal_to_space_heating_load_series_mmbtu_per_hour"])
        r["annual_thermal_production_tonhour"] = sum(r["thermal_to_load_series_ton"])
        if p.s.ghp_option_list[ghp_option_chosen].can_serve_dhw
            r["thermal_to_dhw_load_series_mmbtu_per_hour"] = d["HeatingLoad"]["dhw_thermal_load_series_mmbtu_per_hour"]
            r["annual_thermal_production_mmbtu"] = r["annual_thermal_production_mmbtu"] + sum(r["thermal_to_dhw_load_series_mmbtu_per_hour"])
        else
            r["thermal_to_dhw_load_series_mmbtu_per_hour"] = zeros(length(p.time_steps))
        end
    else
        r["ghpghx_chosen_outputs"] = Dict()
        r["space_heating_thermal_load_reduction_with_ghp_mmbtu_per_hour"] = zeros(length(p.time_steps))
        r["cooling_thermal_load_reduction_with_ghp_ton"] = zeros(length(p.time_steps))
        r["ghx_residual_value_present_value"] = 0.0
        r["thermal_to_space_heating_load_series_mmbtu_per_hour"] = zeros(length(p.time_steps))
        r["thermal_to_load_series_ton"] = zeros(length(p.time_steps))
        r["thermal_to_dhw_load_series_mmbtu_per_hour"] = zeros(length(p.time_steps))
        r["annual_thermal_production_mmbtu"] = 0.0
        r["annual_thermal_production_tonhour"] = 0.0
    end
    d["GHP"] = r
    nothing
end