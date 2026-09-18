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
    techs_by_exportbin::Dict{Symbol, AbstractArray}  # keys can include [:NEM, :WHL]
    export_bins_by_tech::Dict{String, Array{Symbol, 1}}
    storage_by_exportbin::Dict{Symbol, AbstractArray}  # keys can include [:NEM, :WHL]
    export_bins_by_storage::Dict{String, Array{Symbol, 1}} 
    cooling_cop::Dict{String, Array{Float64,1}}  # (techs.cooling, time_steps)
    thermal_cop::Dict{String, Float64}  # (techs.absorption_chiller)
    ghp_options::UnitRange{Int64}  # Range of the number of GHP options
    fuel_cost_per_kwh::Dict{String, AbstractArray}  # Fuel cost array for all time_steps
    heating_loads::Vector{String} # list of heating loads
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

    # export related inputs (mirrors src/core `setup_tech_inputs`)
    # The bins a tech/storage can access are determined by its `can_net_meter`, `can_wholesale`,
    # and `can_export_beyond_nem_limit` attributes. MPC does not model the :EXC bin.
    techs_by_exportbin = Dict{Symbol, AbstractArray}(k => [] for k in s.electric_tariff.export_bins)
    export_bins_by_tech = Dict{String, Array{Symbol, 1}}()
    storage_by_exportbin = Dict{Symbol, AbstractArray}(k => [] for k in s.electric_tariff.export_bins)
    export_bins_by_storage = Dict{String, Array{Symbol, 1}}()

    for pv in s.pvs
        fillin_techs_by_exportbin(techs_by_exportbin, pv, pv.name)
    end
    if "Generator" in techs.all
        fillin_techs_by_exportbin(techs_by_exportbin, s.generator, "Generator")
    end
    # filling export_bins_by_tech MUST be done after techs_by_exportbin has been filled in
    for t in techs.elec
        export_bins_by_tech[t] = [bin for (bin, ts) in techs_by_exportbin if t in ts]
    end

    for b in s.storage.types.elec
        fillin_storage_by_exportbin(s, storage_by_exportbin, b)
    end
    for b in s.storage.types.elec
        export_bins_by_storage[b] = [bin for (bin, ts) in storage_by_exportbin if b in ts]
    end
 
    levelization_factor = Dict(t => 1.0 for t in techs.all) # production not levelized in MPC
    pwf_e = 1.0
    pwf_om = 1.0
    pwf_fuel = Dict{String, Float64}()
    pwf_fuel["Generator"] = 1.0 
    third_party_factor = 1.0

    time_steps_with_grid, time_steps_without_grid, = setup_electric_utility_inputs(s)

    #Placeholder COP because the REopt model expects it
    cooling_cop = Dict("ExistingChiller" => ones(length(s.electric_load.loads_kw)) .* s.cooling_load.cop)
    thermal_cop = Dict{String, Float64}()
    ghp_options = 1:0
    heating_loads = Vector{String}()

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
        storage_by_exportbin,
        export_bins_by_storage,
        cooling_cop,
        thermal_cop,
        ghp_options,
        # s.site.min_resil_time_steps,
        # s.site.mg_tech_sizes_equal_grid_sizes,
        # s.site.node,
        fuel_cost_per_kwh,
        heating_loads
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
