"""
    run_reopt_multi_solutions(fp::String, size_scale::Union{Vector{Any},Vector{Float64}}, ms::AbstractVector{T}; 
                                parallel::Bool=false, resilience=false, outage_start_hour::Int64=1, 
                                outage_duration_hours::Int64=0))  where T <: JuMP.AbstractModel

Run REopt to get optimal tech sizes, and then run REopt multiple times with scaling factor size_scale applied to 
    the optimal sizes to look at sensitivity of tech size on key results parameters

fp is the inputs .json file path
size_scale is the vector of scaling factors to apply to each optimal tech size
ms is a vector of identical JuMP model objects and the length has to be larger than the max possible REopt runs

if kwarg `parallel`==`true`
    Uses multi-threading for multiple-solutions, but set JULIA_NUM_THREADS="auto" or set to max on computer
    export JULIA_NUM_THREADS="auto"
    or
    export JULIA_NUM_THREADS=8
else
    Runs multiple solutions in series, but still uses 2 @threads for 2x parallel BAU and Optimal
    so still at least need JULIA_NUM_THREADS=2

"""
function run_reopt_multi_solutions(fp::String, size_scale::Union{Vector{Any},Vector{Float64}}, ms::AbstractVector{T}; 
                                    parallel=false, resilience=false, outage_start_hour=1, outage_duration_hours=0,
                                    state="") where T <: JuMP.AbstractModel
    # Load in input_data from .json to dictionary
    input_data = JSON.parsefile(fp)
    # Count number of JuMP models used
    ms_count = 1
    # Decide which state incentives to apply
    best_incentive_program_name = "None"
    incentive_type = "None"
    incentive_value = 0.0
    net_metering_from_dsire = "false"
    if !isempty(state) && haskey(input_data, "PV")
        tech = "PV"
        reopt_inputs_scenarios = REopt.get_incentives_scenarios(input_data; state_abbr=state, tech=tech)
        net_metering_from_dsire = pop!(reopt_inputs_scenarios, "net_metering_from_dsire")
        results_scenarios = Dict()
        best_incentives = ""
        for (i, scenario) in enumerate(keys(reopt_inputs_scenarios))
            incentive_name = pop!(reopt_inputs_scenarios[scenario], "incentive_program_name")
            incentive_type = pop!(reopt_inputs_scenarios[scenario], "type")
            incentive_value = pop!(reopt_inputs_scenarios[scenario], "value")
            delete!(get(reopt_inputs_scenarios[scenario], "PV", Dict()), "incentive_program_name")
            delete!(get(reopt_inputs_scenarios[scenario], "PV", Dict()), "type")
            delete!(get(reopt_inputs_scenarios[scenario], "PV", Dict()), "value")
            s = Scenario(reopt_inputs_scenarios[scenario])
            inputs = REoptInputs(s)
            m = ms[i]
            ms_count += 1
            results_scenarios[scenario] = run_reopt(m, inputs)
            if i == 1
                best_incentives = scenario
                best_incentive_program_name = incentive_name
            elseif results_scenarios[scenario]["Financial"]["lcc"] < results_scenarios[best_incentives]["Financial"]["lcc"]
                best_incentives = scenario
                best_incentive_program_name = incentive_name
            end
        end
        if !isempty(best_incentives)
            input_data = reopt_inputs_scenarios[best_incentives]
            delete!(input_data, "incentive_program_name")
        end
    end
    
    # Create optimal and BAU inputs structs for initial 2 runs
    s = Scenario(input_data)
    p = REoptInputs(s)
    bau_inputs = BAUInputs(p)
    # Note, ms[1] and rs[1] are for the BAU case which we'll need to combine with all other solutions too
    # and ms[2] and rs[2] are for the optimal case
    inputs = ((ms[ms_count], bau_inputs), (ms[ms_count+1], p))
    ms_count += 2
    rs = Any[0, 0]
    Threads.@threads for i = 1:2
        rs[i] = run_reopt(inputs[i])
    end

    # Combine results for BAU-Opt to get e.g. NPV
    # This may still error ungracefully if the scenario is infeasible, same as REopt.jl does
    results_dict = REopt.combine_results(p, rs[1], rs[2], bau_inputs.s)
    results_dict["Financial"] = merge(results_dict["Financial"], REopt.proforma_results(p, results_dict))

    # Check results to see which techs are sized, to inform number of solutions
    techs_possible = ["PV", "ElectricStorage", "Generator", "CHP"]  # Eaton's techs of interest, where CHP really for power-only fuel cell
    techs_considered = intersect(techs_possible, keys(input_data))
    techs_sized = String[]
    for tech in techs_considered
        if results_dict[tech]["size_kw"] > 0.0
            append!(techs_sized, [tech])
        end
    end
    techs_to_zero = setdiff(techs_considered, techs_sized)
    n_solutions = length(size_scale) * length(techs_sized)

    # Create the first entry for "optimal" solution in the results dictionary
    if resilience
        simresults = simulate_outages(results_dict, p)
    else
        simresults = Dict()
    end
    results_summary = Dict("optimal" => get_multi_solutions_results_summary(results_dict, p, ms[ms_count-1], techs_considered, simresults, outage_start_hour, outage_duration_hours))
    results_summary["incentive_used"] = Dict("best_incentive_program_name" => best_incentive_program_name,
                                            "net_metering_from_dsire" => net_metering_from_dsire,
                                            "state" => state,
                                            "type" => incentive_type,
                                            "value" => incentive_value)
    # Add custom resilience output to results_all, per Eaton's request
    results_dict["resilience"] = results_summary["optimal"]["resilience"]
    results_dict["incentive_used"] = results_summary["incentive_used"]
    results_all = Dict("optimal" => results_dict)

    # Now create number of inputs based on the # of techs sized in optimal case
    ps = []
    for i in eachindex(size_scale)
        for tech in techs_sized
            input_data_s = deepcopy(input_data)
            
            # Remove techs which were considered but not sized (size=0) in optimal case            
            for t in techs_to_zero
                # delete!(input_data_s, t)
                input_data_s[t]["max_kw"] = 0.0
            end

            # Force size based on size_scale factor for tech, and set other techs to optimal size
            for t in techs_sized
                size_scale_tech = 1.0
                if t == tech
                    size_scale_tech = size_scale[i]
                end
                input_data_s[t]["min_kw"] = results_all["optimal"][t]["size_kw"] * size_scale_tech
                input_data_s[t]["max_kw"] = results_all["optimal"][t]["size_kw"] * size_scale_tech
                if t == "ElectricStorage"
                    input_data_s[t]["min_kwh"] = results_all["optimal"][t]["size_kwh"] * size_scale_tech
                    input_data_s[t]["max_kwh"] = results_all["optimal"][t]["size_kwh"] * size_scale_tech
                end
            end
            
            # Create named entry for REoptInputs
            append!(ps, [(tech*"_size_scale_"*string(size_scale[i]), REoptInputs(Scenario(input_data_s)))])
        end
    end

    # Run extra n_solutions with multi-threading
    rs_solns = Vector{Any}(nothing, n_solutions)

    if parallel
        Threads.@threads for i in 1:n_solutions  # Threads doesn't like enumerate with for loop
            # JuMP model index starts at 3 because 1 and 2 were used by BAU and optimal sceanarios
            n = ms_count + (i - 1)
            rs_solns[i] = run_reopt((ms[n], ps[i][2]))
        end
    else
        for i in eachindex(rs_solns)
            n = ms_count + (i - 1)
            rs_solns[i] = run_reopt((ms[n], ps[i][2]))
        end
    end
    
    # Combine BAU with each extra solution and get results summary
    for (i, p) in enumerate(ps)
        n = ms_count + (i-1)
        # Combine with BAU to get e.g. NPV
        if typeof(rs_solns[i]) <: Dict
            local results_dict = REopt.combine_results(p[2], rs[1], rs_solns[i], bau_inputs.s)
            results_dict["Financial"] = merge(results_dict["Financial"], REopt.proforma_results(p[2], results_dict))
            if resilience
                simresults = simulate_outages(rs_solns[i], p[2])
            else
                simresults = Dict()
            end
            # Build results summary, a select number of outputs for Eaton
            results_summary[p[1]] = get_multi_solutions_results_summary(results_dict, p[2], ms[n], techs_considered, simresults, outage_start_hour, outage_duration_hours)
            results_dict["resilience"] = results_summary[p[1]]["resilience"]
            results_all[p[1]] = results_dict
        else
            @warn "REopt did not solve successully (infeasible) for extra run number $i"
            results_all[p[1]] = Dict("status"=>Dict("error" => "infeasible"))
            results_summary[p[1]] = Dict("status"=>Dict("error" => "infeasible"))
        end
    end

    return results_all, results_summary
end

"""
    get_multi_solutions_results_summary(results::Dict, p::REoptInputs, m::JuMP.AbstractModel, techs_considered::Vector{String}, simresults::Dict,
                                        outage_start_hour::Int64, outage_duration_hours::Int64)

Get the results summary dictionary which is a selected number of outputs for Financial, Emissions, and 
the relevant techs

"""
function get_multi_solutions_results_summary(results::Dict, p::REoptInputs, m::JuMP.AbstractModel, techs_considered::Vector{String}, simresults::Dict,
                                                outage_start_hour::Int64, outage_duration_hours::Int64)
    # results_summary always has Financial and emissions, and then add techs as needed
    results_summary = Dict(
        "status" => results["status"],
        "Financial" =>
            Dict("Net Present Value" => results["Financial"]["npv"],
                "Simple payback period" => results["Financial"]["simple_payback_years"],
                "Net capital cost" => results["Financial"]["lifecycle_capital_costs"],
                "Internal Rate of Return %" => results["Financial"]["internal_rate_of_return"] * 100.0),
        "emissions" => 
            Dict("Site life cycle CO2 tonnes" => results["Site"]["lifecycle_emissions_tonnes_CO2"],
                "Site life cycle NOx tonnes" => results["Site"]["lifecycle_emissions_tonnes_NOx"],
                "Site life cycle SO2 tonnes" => results["Site"]["lifecycle_emissions_tonnes_SO2"],
                "Site life cycle PM25 tonnes" => results["Site"]["lifecycle_emissions_tonnes_PM25"])
    )

    if !isempty(simresults)
        # User specified outage_start_hour and outage_duration_hours ONLY for this post-processing for Eaton
        # Also VoLL only specified for this post-processing, NOT using it in the model
        # Must specify critical_load_fraction of 1.0 if you want to use the whole load (default 0.5) in REopt inputs 
        #   even though the model is NOT going to use that if no outage is input
        num_outage_time_steps = outage_duration_hours * p.s.settings.time_steps_per_hour
        
        # Get BAU and Optimal outage lost load and cost for every hour of the year to get average and max values
        last_time_step = 8760-outage_duration_hours  # Avoid wrapping around the year
        BAUOutageLostLoadKWH = Array{Float64}(undef, last_time_step * p.s.settings.time_steps_per_hour)
        BAUOutageCost = Array{Float64}(undef, last_time_step * p.s.settings.time_steps_per_hour)
        OptimalOutageLostLoadKWH = Array{Float64}(undef, last_time_step * p.s.settings.time_steps_per_hour)
        OptimalOutageCost = Array{Float64}(undef, last_time_step * p.s.settings.time_steps_per_hour)
        for tz in 1:(last_time_step * p.s.settings.time_steps_per_hour)
            BAUOutageLostLoadKWH[tz] = sum(p.s.electric_load.critical_loads_kw[tz+ts-1] / p.s.settings.time_steps_per_hour
                                        for ts in 1:num_outage_time_steps; init=0.0)
            BAUOutageCost[tz] = sum(p.value_of_lost_load_per_kwh[tz+ts-1] * p.s.electric_load.critical_loads_kw[tz+ts-1] / p.s.settings.time_steps_per_hour
                                    for ts in 1:num_outage_time_steps; init=0.0)
            resil_by_time_step = simresults["resilience_by_time_step"][tz] * p.s.settings.time_steps_per_hour
            OptimalOutageLostLoadKWH[tz] = sum(p.s.electric_load.critical_loads_kw[tz+ts-1] / p.s.settings.time_steps_per_hour
                                                for ts in (convert(Int, resil_by_time_step)+1):outage_duration_hours; init=0.0)
            OptimalOutageCost[tz] = sum(p.value_of_lost_load_per_kwh[tz+ts-1] * p.s.electric_load.critical_loads_kw[tz+ts-1] / p.s.settings.time_steps_per_hour
                                                for ts in (convert(Int, resil_by_time_step)+1):outage_duration_hours; init=0.0)                                                    
        end
        avg_lost_load_bau_kwh = sum(BAUOutageLostLoadKWH) / length(BAUOutageLostLoadKWH)
        avg_year_one_outage_cost_bau = sum(BAUOutageCost) / length(BAUOutageCost)
        avg_lost_load_optimal_kwh = sum(OptimalOutageLostLoadKWH) / length(OptimalOutageLostLoadKWH)
        avg_year_one_outage_cost_optimal = sum(OptimalOutageCost) / length(OptimalOutageCost)
        avg_outage_load_served = avg_lost_load_bau_kwh - avg_lost_load_optimal_kwh
        avg_outage_cost_savings = avg_year_one_outage_cost_bau - avg_year_one_outage_cost_optimal
        avg_outage_hours_served = sum(simresults["resilience_by_time_step"]) / length(simresults["resilience_by_time_step"])
        specific_outage_lost_load_bau_kwh = BAUOutageLostLoadKWH[outage_start_hour * p.s.settings.time_steps_per_hour]
        specific_outage_cost_bau = BAUOutageCost[outage_start_hour * p.s.settings.time_steps_per_hour]
        specific_outage_lost_load_optimal_kwh = OptimalOutageLostLoadKWH[outage_start_hour * p.s.settings.time_steps_per_hour]
        specific_outage_cost_optimal = OptimalOutageCost[outage_start_hour * p.s.settings.time_steps_per_hour]
        specific_outage_load_served_kwh = specific_outage_lost_load_bau_kwh - specific_outage_lost_load_optimal_kwh
        specific_outage_hours_served = simresults["resilience_by_time_step"][outage_start_hour]
        year_one_outage_cost_savings = specific_outage_cost_bau - specific_outage_cost_optimal
        # Outage cost as percentage of year one utility bill to put into perspective?
        year_one_utility_bill_bau = results["ElectricTariff"]["year_one_bill_before_tax"]
        year_one_outage_cost_savings_percent_of_utility_bill = year_one_outage_cost_savings / year_one_utility_bill_bau * 100.0

        results_summary["resilience"] = Dict("Input outage duration (hours)" => outage_duration_hours,
                                            "Average outage hours of load served (hours)" => round(avg_outage_hours_served, digits=0),
                                            "Average outage load served (kWh)" => round(avg_outage_load_served, sigdigits=3),
                                            "Average outage cost savings per year" => round(avg_outage_cost_savings, sigdigits=3),
                                            "Specified outage hours of load served" => round(specific_outage_hours_served, digits=0),
                                            "Specified outage load served with DERs (kWh)" => round(specific_outage_load_served_kwh, sigdigits=3),
                                            "Specified outage cost savings per year with DERs" => round(year_one_outage_cost_savings, sigdigits=3),
                                            "Specified outage cost savings as percent of annual utility bill" => round(year_one_outage_cost_savings_percent_of_utility_bill, sigdigits=3)
                                            )
    else
        results_summary["resilience"] = Dict("No resilience simulation was run" => 0.0)
    end

    # Add techs if they have been sized in the optimal case
    for key in techs_considered
        if key == "PV"
            # Note, capital cost is "net" of incentives, and Maintenance cost is year-one
            results_summary["PV"] = 
                Dict("Rated capacity" => results[key]["size_kw"],
                    "Average annual energy produced" => results[key]["year_one_energy_produced_kwh"],
                    "Capital cost" => p.cap_cost_slope[key] * results[key]["size_kw"],
                    "Annual maintenance cost" => p.s.pvs[1].om_cost_per_kw * results[key]["size_kw"])
        elseif key == "ElectricStorage"
            # Note, capital cost is "net" of incentives, and Maintenance cost is year-one
            # Estimate the installed upfront cost versus the replacement cost by scaling inputs
            # TODO this has become complicated and might be easier to just leverage effective_cost REopt function
            net_installed_plus_replace_cost = value(m[Symbol("TotalStorageCapCosts")])
            total_input_cost_per_kw = p.s.storage.attr[key].installed_cost_per_kw + p.s.storage.attr[key].replace_cost_per_kw
            total_input_cost_per_kwh = p.s.storage.attr[key].installed_cost_per_kwh + p.s.storage.attr[key].replace_cost_per_kwh
            replacement_fraction_per_kw = p.s.storage.attr[key].replace_cost_per_kw / total_input_cost_per_kw
            replacement_fraction_per_kwh = p.s.storage.attr[key].replace_cost_per_kwh / total_input_cost_per_kwh
            replacement_cost_fraction = (replacement_fraction_per_kw * results[key]["size_kw"] + 
                                        replacement_fraction_per_kwh * results[key]["size_kwh"]) /
                                        (results[key]["size_kw"] + results[key]["size_kwh"])
            net_replacement_cost = net_installed_plus_replace_cost * replacement_cost_fraction
            net_installed_cost = net_installed_plus_replace_cost - net_replacement_cost
            results_summary["Storage"] = 
                Dict("Rated energy capacity" => results[key]["size_kwh"],
                    "Rated inverter capacity" => results[key]["size_kw"],
                    "Capital cost" => net_installed_cost,
                    "Total replacement cost" => net_replacement_cost)
        elseif key == "Generator"
            results_summary["Generator"] = 
                Dict("Rated capacity" => results[key]["size_kw"],
                    "Capital cost" => p.cap_cost_slope[key] * results[key]["size_kw"],
                    "Annual maintenance cost" => p.s.generator.om_cost_per_kw * results[key]["size_kw"],
                    "Life cycle fuel cost after tax" => results[key]["lifecycle_fuel_cost_after_tax"],
                    "Annual fuel used gallons" => results[key]["annual_fuel_consumption_gal"],
                    "Annual energy produced" => results[key]["annual_energy_produced_kwh"])
        elseif key == "CHP"
            cap_cost = p.third_party_factor * (
                    sum(p.cap_cost_slope[key][s] * value(m[Symbol("dvSegmentSystemSize"*key)][s]) + 
                    p.seg_yint[key][s] * value(m[Symbol("binSegment"*key)][s]) for s in 1:p.n_segs_by_tech[key]))
            var_om_cost = (value(m[Symbol("TotalCHPPerUnitProdOMCosts")]) + value(m[Symbol("TotalHourlyCHPOMCosts")])) / 
                            p.third_party_factor * p.pwf_om
            fixed_om_cost = p.s.chp.om_cost_per_kw * results[key]["size_kw"]
            results_summary["Fuel Cell"] = 
                Dict("Rated capacity" => results[key]["size_kw"],
                    "Capital cost" => cap_cost,
                    "Annual maintenance cost" => var_om_cost + fixed_om_cost,
                    "Annual energy produced" => results[key]["annual_electric_production_kwh"],
                    "Life cycle fuel cost after tax" => results[key]["lifecycle_fuel_cost_after_tax"],
                    "Annual fuel used MMBtu" => results[key]["annual_fuel_consumption_mmbtu"],
                    "Life cycle standby cost after tax" => results[key]["lifecycle_standby_cost_after_tax"])
        end
    end
    return results_summary
end