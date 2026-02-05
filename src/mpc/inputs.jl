# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

struct MPCInputs <: AbstractInputs
    s::MPCScenario
    techs::Techs
    existing_sizes::Dict{String, <:Real}  # (techs.all)
    max_sizes::Dict{String, <:Real}  # (techs.all)  max_sizes is same as existing_sizes (added so that we can re-use generator_constraints)
    time_steps::UnitRange
    time_steps_with_grid::Array{Int, 1}
    time_steps_without_grid::Array{Int, 1}
    hours_per_time_step::Float64
    months::UnitRange
    production_factor::DenseAxisArray{Float64, 2}  # (techs.all, time_steps)
    levelization_factor::Dict{String, Float64}  # (techs.all)
    value_of_lost_load_per_kwh::Array{R, 1} where R<:Real #default set to 1 US dollar per kwh
    pwf_e::Float64
    pwf_om::Float64
    pwf_fuel::Dict{String, Float64}
    third_party_factor::Float64
    ratchets::UnitRange
    techs_by_exportbin::DenseAxisArray{Array{String,1}}  # indexed on [:NEM, :WHL]
    export_bins_by_tech::Dict{String, Array{Symbol, 1}}
    cooling_cop::Dict{String, Array{Float64,1}}  # (techs.cooling, time_steps)
    thermal_cop::Dict{String, Float64}  # (techs.absorption_chiller)
    ghp_options::UnitRange{Int64}  # Range of the number of GHP options
    fuel_cost_per_kwh::Dict{String, AbstractArray}  # Fuel cost array for all time_steps
    heating_loads::Vector{String} # list of heating loads
    # Uncertainty fields (MPC is deterministic, but fields needed for compatibility)
    n_scenarios::Int
    scenario_probabilities::Vector{Float64}
    loads_kw_by_scenario::Dict{Int, Vector{Float64}}
    production_factor_by_scenario::Dict{Int, Dict{String, Vector{Float64}}}
end


function MPCInputs(fp::String)
    s = MPCScenario(JSON.parsefile(fp))
    MPCInputs(s)
end


function MPCInputs(d::Dict)
    s = MPCScenario(d)
    MPCInputs(s)
end


function MPCInputs(s::MPCScenario)

    time_steps = 1:length(s.electric_load.loads_kw)
    hours_per_time_step = 1 / s.settings.time_steps_per_hour
    techs, production_factor, existing_sizes, fuel_cost_per_kwh = setup_tech_inputs(s)
    months = 1:length(s.electric_tariff.monthly_demand_rates)

    techs_by_exportbin = DenseAxisArray([ techs.all, techs.all, techs.all], s.electric_tariff.export_bins)
    # TODO account for which techs have access to export bins (when we add more techs than PV)

    levelization_factor = Dict(t => 1.0 for t in techs.all)
    pwf_e = 1.0
    pwf_om = 1.0
    pwf_fuel = Dict{String, Float64}()
    pwf_fuel["Generator"] = 1.0 
    third_party_factor = 1.0

    time_steps_with_grid, time_steps_without_grid, = setup_electric_utility_inputs(s)

    export_bins_by_tech = Dict{String, Array{Symbol, 1}}()
    for t in techs.elec
        export_bins_by_tech[t] = s.electric_tariff.export_bins
    end
    # TODO implement export bins by tech (rather than assuming that all techs share the export_bins)
 
    #Placeholder COP because the REopt model expects it
    cooling_cop = Dict("ExistingChiller" => ones(length(s.electric_load.loads_kw)) .* s.cooling_load.cop)
    thermal_cop = Dict{String, Float64}()
    ghp_options = 1:0
    heating_loads = Vector{String}()

    # MPC is deterministic - single scenario with probability 1.0
    # TODO could consider OUU for dispatch decisions in MPC, even with sizes being specified/fixed
    n_scenarios = 1
    scenario_probabilities = [1.0]
    loads_kw_by_scenario = Dict{Int, Vector{Float64}}(1 => Float64.(s.electric_load.loads_kw))
    production_factor_by_scenario = Dict{Int, Dict{String, Vector{Float64}}}(
        1 => Dict{String, Vector{Float64}}(
            t => Float64.([production_factor[t, ts] for ts in time_steps]) for t in techs.all
        )
    )

    MPCInputs(
        s,
        techs,
        existing_sizes,
        existing_sizes,
        time_steps,
        time_steps_with_grid,
        time_steps_without_grid,
        hours_per_time_step,
        months,
        production_factor,
        levelization_factor,  # TODO need this?
        typeof(s.financial.value_of_lost_load_per_kwh) <: Array{<:Real, 1} ? s.financial.value_of_lost_load_per_kwh : fill(s.financial.value_of_lost_load_per_kwh, length(time_steps)),
        pwf_e,
        pwf_om,
        pwf_fuel,
        third_party_factor,
        # maxsize_pv_locations,
        1:length(s.electric_tariff.tou_demand_ratchet_time_steps),  # ratchets
        techs_by_exportbin,
        export_bins_by_tech,
        cooling_cop,
        thermal_cop,
        ghp_options,
        # s.site.min_resil_time_steps,
        # s.site.mg_tech_sizes_equal_grid_sizes,
        # s.site.node,
        fuel_cost_per_kwh,
        heating_loads,
        n_scenarios,
        scenario_probabilities,
        loads_kw_by_scenario,
        production_factor_by_scenario
    )
end


function setup_tech_inputs(s::MPCScenario)

    techs = Techs(s)

    time_steps = 1:length(s.electric_load.loads_kw)

    # REoptInputs indexed on techs:
    existing_sizes = Dict(t => 0.0 for t in techs.all)
    production_factor = DenseAxisArray{Float64}(undef, techs.all, time_steps)
    fuel_cost_per_kwh = Dict{String, AbstractArray}()

    if !isempty(techs.pv)
        setup_pv_inputs(s, existing_sizes, production_factor)
    end

    if "Generator" in techs.all
        setup_gen_inputs(s, existing_sizes, production_factor, fuel_cost_per_kwh)
    end

    return techs, production_factor, existing_sizes, fuel_cost_per_kwh
end


function setup_pv_inputs(s::MPCScenario, existing_sizes, production_factor)
    for pv in s.pvs
        production_factor[pv.name, :] = pv.production_factor_series
        existing_sizes[pv.name] = pv.size_kw
    end
    return nothing
end


function setup_gen_inputs(s::MPCScenario, existing_sizes, production_factor, fuel_cost_per_kwh)
    existing_sizes["Generator"] = s.generator.size_kw
    production_factor["Generator", :] = ones(length(s.electric_load.loads_kw))
    generator_fuel_cost_per_kwh = s.generator.fuel_cost_per_gallon / s.generator.fuel_higher_heating_value_kwh_per_gal
    fuel_cost_per_kwh["Generator"] = per_hour_value_to_time_series(generator_fuel_cost_per_kwh, s.settings.time_steps_per_hour, "Generator")
    return nothing
end
