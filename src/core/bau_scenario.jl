# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    OutageOutputs

Struct for storing `bau_critical_load_met` and `bau_critical_load_met_time_steps`.
This struct is attached to the BAUScenario s.t. the outputs can be passed back to the user.
It is mutable s.t. that it can be adjusted in BAUInputs.
"""
Base.@kwdef mutable struct OutageOutputs
    bau_critical_load_met::Bool = true
    bau_critical_load_met_time_steps::Int = 0
end


struct BAUScenario <: AbstractScenario
    settings::Settings
    site::Site
    pvs::Array{PV, 1}
    wind::Wind
    storage::Storage
    electric_tariff::ElectricTariff
    electric_load::ElectricLoad
    electric_utility::ElectricUtility
    financial::Financial
    generator::Generator
    dhw_load::DomesticHotWaterLoad
    space_heating_load::SpaceHeatingLoad
    process_heat_load::ProcessHeatLoad
    existing_boiler::Union{ExistingBoiler, Nothing}
    existing_chiller::Union{ExistingChiller, Nothing}
    outage_outputs::OutageOutputs
    flexible_hvac::Union{BAU_HVAC, Nothing}
    cooling_load::CoolingLoad
    ghp_option_list::Array{Union{GHP, Nothing}, 1}  # List of GHP objects (often just 1 element, but can be more)
    space_heating_thermal_load_reduction_with_ghp_kw::Union{Vector{Float64}, Nothing}
    cooling_thermal_load_reduction_with_ghp_kw::Union{Vector{Float64}, Nothing}    
end


function set_min_max_kw_to_existing(tech::AbstractTech, site::Site)
    techdict = Dict(fn => getfield(tech, fn) for fn in fieldnames(typeof(tech)))
    if nameof(typeof(tech)) in [:PV]
        techdict[:latitude] = site.latitude
    end
    techdict[:min_kw] = techdict[:existing_kw]
    techdict[:max_kw] = techdict[:existing_kw]
    eval(Meta.parse(string(typeof(tech)) * "(; $techdict...)"))
end


function bau_site(site::Site)
    Site(;
        latitude=site.latitude,
        longitude=site.longitude,
        land_acres=site.land_acres,
        roof_squarefeet=site.roof_squarefeet,
        min_resil_time_steps=0,
        mg_tech_sizes_equal_grid_sizes=site.mg_tech_sizes_equal_grid_sizes,
        include_exported_elec_emissions_in_total=site.include_exported_elec_emissions_in_total,
        include_exported_renewable_electricity_in_total=site.include_exported_renewable_electricity_in_total,
        node=site.node,
    )
end


"""
    BAUScenario(s::Scenario)

Constructs the BAUScenario (used to create the Business-as-usual inputs) based on the Scenario for the optimized case.

The following assumptions are made for the BAU scenario: 
- sets the `PV` and `Generator` min_kw and max_kw values to the existing_kw values
- sets wind and storage max_kw values to zero (existing wind and storage cannot be modeled)
"""
function BAUScenario(s::Scenario)

    # set all PV.max_kw to existing_kw
    pvs = PV[]
    for pv in s.pvs
        if pv.existing_kw > 0
            push!(pvs, set_min_max_kw_to_existing(pv, s.site))
        end
    end

    # set Generator.max_kw to existing_kw
    generator = set_min_max_kw_to_existing(s.generator, s.site)

    # no existing wind
    wind = Wind(; max_kw=0)

    # no existing storage
    storage = Storage()

    # no existing GHP
    ghp_option_list = []
    space_heating_thermal_load_reduction_with_ghp_kw = zeros(8760 * s.settings.time_steps_per_hour)
    cooling_thermal_load_reduction_with_ghp_kw = zeros(8760 * s.settings.time_steps_per_hour)

    # No min or max capital cost constraints 
    financial = deepcopy(s.financial)
    financial.min_initial_capital_costs_before_incentives = nothing
    financial.max_initial_capital_costs_before_incentives = nothing
    
    t0, tf = s.electric_utility.outage_start_time_step, s.electric_utility.outage_end_time_step
    #=
    When a deterministic grid outage is modeled we must adjust the BAU critical load profile to keep the problem 
    feasible and to get the same ElectricTariff costs in both the optimal and BAU scenarios
    (because the BAU scenario may not have enough existing capacity to meet the critical load and because during an
    outage no grid costs are incurred).
    In the simplest case we set the BAU critical_loads_kw to zero during the outage. 
    However, if the BAU scenario has existing Generator and/or PV we calculate how many time steps the critical load can 
    be met and make the critical load non-zero for those time steps in order to show the most realistic dispatch results.
    This calculation requires the PV production_factor_series and so it is done in BAUInputs.
    =#
    elec_load = deepcopy(s.electric_load)
    if tf > t0 && t0 > 0
        elec_load.critical_loads_kw[t0:tf] = zeros(tf-t0+1)  # set crit load to zero 
    end
    outage_outputs = OutageOutputs()

    flexible_hvac = nothing
    if !isnothing(s.flexible_hvac)
        flexible_hvac = s.flexible_hvac.bau_hvac
    end
    #=
    For random or uncertain outages there is no need to zero out the critical load but we do have to
    set the Site.min_resil_time_steps to zero s.t. the model is not forced to meet any critical load
    in the BAUScenario
    =#
    site = bau_site(s.site)

    return BAUScenario(
        s.settings,
        site, 
        pvs, 
        wind,
        storage, 
        s.electric_tariff, 
        elec_load, 
        s.electric_utility, 
        financial,
        generator,
        s.dhw_load,
        s.space_heating_load,
        s.process_heat_load,
        s.existing_boiler,
        s.existing_chiller,
        outage_outputs,
        flexible_hvac,
        s.cooling_load,
        ghp_option_list,
        space_heating_thermal_load_reduction_with_ghp_kw,
        cooling_thermal_load_reduction_with_ghp_kw
    )
end