# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    REoptInputs

The data structure for all the inputs necessary to construct the JuMP model.
```julia
struct REoptInputs <: AbstractInputs
    s::ScenarioType
    techs::Techs
    min_sizes::Dict{String, <:Real}  # (techs)
    max_sizes::Dict{String, <:Real}  # (techs)
    existing_sizes::Dict{String, <:Real}  # (techs)
    cap_cost_slope::Dict{String, Any}  # (techs)
    om_cost_per_kw::Dict{String, <:Real}  # (techs)
    thermal_cop::Dict{String, <:Real}  # (techs.absorption_chiller)
    time_steps::UnitRange
    time_steps_with_grid::Array{Int, 1}
    time_steps_without_grid::Array{Int, 1}
    hours_per_time_step::Real
    months::UnitRange
    production_factor::DenseAxisArray{<:Real, 2}  # (techs, time_steps)
    levelization_factor::Dict{String, <:Real,}  # (techs)
    value_of_lost_load_per_kwh::Array{<:Real, 1}
    pwf_e::Real
    pwf_om::Real
    pwf_fuel::Dict{String, <:Real}
    pwf_emissions_cost::Dict{String, Float64} # Cost of emissions present worth factors for grid and onsite fuelburn emissions [unitless]
    pwf_grid_emissions::Dict{String, Float64} # Emissions [lbs] present worth factors for grid emissions [unitless]
    pwf_offtaker::Real 
    pwf_owner::Real
    third_party_factor::Real
    pvlocations::Array{Symbol, 1}
    maxsize_pv_locations::DenseAxisArray{<:Real, 1}  # indexed on pvlocations
    pv_to_location::Dict{String, Dict{Symbol, Int64}}  # (techs.pv, pvlocations)
    ratchets::UnitRange
    techs_by_exportbin::Dict{Symbol, AbstractArray}  # keys can include [:NEM, :WHL, :CUR]
    export_bins_by_tech::Dict
    n_segs_by_tech::Dict{String, Int}
    seg_min_size::Dict{String, Dict{Int, <:Real}}
    seg_max_size::Dict{String, Dict{Int, <:Real}}
    seg_yint::Dict{String, Dict{Int, <:Real}}
    pbi_pwf::Dict{String, Any}  # (pbi_techs)
    pbi_max_benefit::Dict{String, Any}  # (pbi_techs)
    pbi_max_kw::Dict{String, Any}  # (pbi_techs)
    pbi_benefit_per_kwh::Dict{String, Any}  # (pbi_techs)
    boiler_efficiency::Dict{String, <:Real}
    fuel_cost_per_kwh::Dict{String, AbstractArray}  # Fuel cost array for all time_steps
    ghp_options::UnitRange{Int64}  # Range of the number of GHP options
    require_ghp_purchase::Int64  # 0/1 binary if GHP purchase is forced/required
    ghp_heating_thermal_load_served_kw::Array{Float64,2}  # Array of heating load (thermal!) profiles served by GHP
    ghp_cooling_thermal_load_served_kw::Array{Float64,2}  # Array of cooling load profiles served by GHP
    space_heating_thermal_load_reduction_with_ghp_kw::Array{Float64,2}  # Array of heating load reduction (thermal!) profile from GHP retrofit
    cooling_thermal_load_reduction_with_ghp_kw::Array{Float64,2}  # Array of cooling load reduction (thermal!) profile from GHP retrofit
    ghp_electric_consumption_kw::Array{Float64,2}  # Array of electric load profiles consumed by GHP
    ghp_installed_cost::Array{Float64,1}  # Array of installed cost for GHP options
    ghp_om_cost_year_one::Array{Float64,1}  # Array of O&M cost for GHP options    
    tech_renewable_energy_fraction::Dict{String, <:Real} # union(techs.elec, techs.fuel_burning)
    tech_emissions_factors_CO2::Dict{String, <:Real} # (techs)
    tech_emissions_factors_NOx::Dict{String, <:Real} # (techs)
    tech_emissions_factors_SO2::Dict{String, <:Real} # (techs)
    tech_emissions_factors_PM25::Dict{String, <:Real} # (techs)
    techs_operating_reserve_req_fraction::Dict{String, <:Real} # (techs.all)
    heating_cop::Dict{String, Array{<:Real, 1}} # (techs.ashp)
    cooling_cop::Dict{String, Array{<:Real, 1}} # (techs.ashp)
    heating_cf::Dict{String, Array{<:Real, 1}} # (techs.ashp)
    cooling_cf::Dict{String, Array{<:Real, 1}} # (techs.ashp)
    heating_loads_kw::Dict{String, <:Real} # (heating_loads)
    unavailability::Dict{String, Array{Float64,1}}  # Dict by tech of unavailability profile
end
```
"""
struct REoptInputs{ScenarioType <: AbstractScenario} <: AbstractInputs
    s::ScenarioType
    techs::Techs
    min_sizes::Dict{String, <:Real}  # (techs)
    max_sizes::Dict{String, <:Real}  # (techs)
    existing_sizes::Dict{String, <:Real}  # (techs)
    cap_cost_slope::Dict{String, Any}  # (techs)
    om_cost_per_kw::Dict{String, <:Real}  # (techs)
    thermal_cop::Dict{String, <:Real}  # (techs.absorption_chiller)
    time_steps::UnitRange
    time_steps_with_grid::Array{Int, 1}
    time_steps_without_grid::Array{Int, 1}
    hours_per_time_step::Real
    months::UnitRange
    production_factor::DenseAxisArray{<:Real, 2}  # (techs, time_steps)
    levelization_factor::Dict{String, <:Real}  # (techs)
    value_of_lost_load_per_kwh::Array{<:Real, 1}
    pwf_e::Real
    pwf_om::Real
    pwf_fuel::Dict{String, <:Real}
    pwf_emissions_cost::Dict{String, Float64} # Cost of emissions present worth factors for grid and onsite fuelburn emissions [unitless]
    pwf_grid_emissions::Dict{String, Float64} # Emissions [lbs] present worth factors for grid emissions [unitless]
    pwf_offtaker::Real 
    pwf_owner::Real
    third_party_factor::Real
    pvlocations::Array{Symbol, 1}
    maxsize_pv_locations::DenseAxisArray{<:Real, 1}  # indexed on pvlocations
    pv_to_location::Dict{String, Dict{Symbol, Int64}}  # (techs.pv, pvlocations)
    ratchets::UnitRange
    techs_by_exportbin::Dict{Symbol, AbstractArray}  # keys can include [:NEM, :WHL, :CUR]
    export_bins_by_tech::Dict
    n_segs_by_tech::Dict{String, Int}
    seg_min_size::Dict{String, Dict{Int, Real}}
    seg_max_size::Dict{String, Dict{Int, Real}}
    seg_yint::Dict{String, Dict{Int, Real}}
    pbi_pwf::Dict{String, Any}  # (pbi_techs)
    pbi_max_benefit::Dict{String, Any}  # (pbi_techs)
    pbi_max_kw::Dict{String, Any}  # (pbi_techs)
    pbi_benefit_per_kwh::Dict{String, Any}  # (pbi_techs)
    boiler_efficiency::Dict{String, <:Real}
    fuel_cost_per_kwh::Dict{String, AbstractArray}  # Fuel cost array for all time_steps
    ghp_options::UnitRange{Int64}  # Range of the number of GHP options
    require_ghp_purchase::Int64  # 0/1 binary if GHP purchase is forced/required
    ghp_heating_thermal_load_served_kw::Array{Float64,2}  # Array of heating load (thermal!) profiles served by GHP
    ghp_cooling_thermal_load_served_kw::Array{Float64,2}  # Array of cooling load profiles served by GHP
    space_heating_thermal_load_reduction_with_ghp_kw::Array{Float64,2}  # Array of heating load reduction (thermal!) profile from GHP retrofit
    cooling_thermal_load_reduction_with_ghp_kw::Array{Float64,2}  # Array of cooling load reduction (thermal!) profile from GHP retrofit
    ghp_electric_consumption_kw::Array{Float64,2}  # Array of electric load profiles consumed by GHP
    ghp_installed_cost::Array{Float64,1}  # Array of installed cost for GHP options
    ghp_om_cost_year_one::Array{Float64,1}  # Array of O&M cost for GHP options
    avoided_capex_by_ghp_present_value::Array{Float64,1} # HVAC upgrade costs avoided (GHP)
    ghx_useful_life_years::Array{Float64,1} # GHX useful life years
    ghx_residual_value::Array{Float64,1} # Residual value of each GHX options
    tech_renewable_energy_fraction::Dict{String, <:Real} # union(techs.elec, techs.fuel_burning)
    tech_emissions_factors_CO2::Dict{String, <:Real} # (techs)
    tech_emissions_factors_NOx::Dict{String, <:Real} # (techs)
    tech_emissions_factors_SO2::Dict{String, <:Real} # (techs)
    tech_emissions_factors_PM25::Dict{String, <:Real} # (techs)
    techs_operating_reserve_req_fraction::Dict{String, <:Real} # (techs.all)
    heating_cop::Dict{String, Array{Float64,1}} # (techs.ashp, time_steps)
    cooling_cop::Dict{String, Array{Float64,1}}  # (techs.ashp, time_steps)
    heating_cf::Dict{String, Array{Float64,1}} # (techs.heating, time_steps)
    cooling_cf::Dict{String, Array{Float64,1}}  # (techs.cooling, time_steps)
    heating_loads::Vector{String} # list of heating loads
    heating_loads_kw::Dict{String, Array{Real,1}} # (heating_loads)
    heating_loads_served_by_tes::Dict{String, Array{String,1}} # ("HotThermalStorage" or empty)
    unavailability::Dict{String, Array{Float64,1}} # (techs.elec)
    absorption_chillers_using_heating_load::Dict{String,Array{String,1}} # ("AbsorptionChiller" or empty)
    avoided_capex_by_ashp_present_value::Dict{String, <:Real} # HVAC upgrade costs avoided (ASHP)
end


"""
    REoptInputs(fp::String)

Use `fp` to load in JSON scenario:
```
function REoptInputs(fp::String)
    s = Scenario(JSON.parsefile(fp))
    REoptInputs(s)
end
```
Useful if you want to manually modify REoptInputs before solving the model.
"""
function REoptInputs(fp::String)
    s = Scenario(JSON.parsefile(fp))
    REoptInputs(s)
end


"""
    REoptInputs(s::AbstractScenario)

Constructor for REoptInputs. Translates the `Scenario` into all the data necessary for building the JuMP model.
"""
function REoptInputs(s::AbstractScenario)

    time_steps = 1:length(s.electric_load.loads_kw)
    hours_per_time_step = 1 / s.settings.time_steps_per_hour
    techs, pv_to_location, maxsize_pv_locations, pvlocations, 
        production_factor, max_sizes, min_sizes, existing_sizes, cap_cost_slope, om_cost_per_kw, n_segs_by_tech, 
        seg_min_size, seg_max_size, seg_yint, techs_by_exportbin, export_bins_by_tech, boiler_efficiency,
        tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, 
        tech_emissions_factors_PM25, techs_operating_reserve_req_fraction, thermal_cop, fuel_cost_per_kwh, 
        heating_cop, cooling_cop, heating_cf, cooling_cf, avoided_capex_by_ashp_present_value, 
        pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh = setup_tech_inputs(s,time_steps)

    months = 1:12

    levelization_factor, pwf_e, pwf_om, pwf_fuel, pwf_emissions_cost, pwf_grid_emissions, third_party_factor, pwf_offtaker, pwf_owner = setup_present_worth_factors(s, techs)
    # the following hardcoded values for levelization_factor matches the public REopt API value
    # and makes the test values match.
    # the REopt code herein uses the Desktop method for levelization_factor, which is more accurate
    # (Desktop has non-linear degradation vs. linear degradation in API)
    # levelization_factor = Dict("PV" => 0.9539)
    # levelization_factor = Dict("ground" => 0.942238, "roof_east" => 0.942238, "roof_west" => 0.942238)
    # levelization_factor["PV"] = 0.9539
    # levelization_factor["Generator"] = 1.0
    time_steps_with_grid, time_steps_without_grid, = setup_electric_utility_inputs(s)
    
    ghp_options, require_ghp_purchase, ghp_heating_thermal_load_served_kw, 
        ghp_cooling_thermal_load_served_kw, space_heating_thermal_load_reduction_with_ghp_kw, 
        cooling_thermal_load_reduction_with_ghp_kw, ghp_electric_consumption_kw, 
        ghp_installed_cost, ghp_om_cost_year_one, avoided_capex_by_ghp_present_value,
        ghx_useful_life_years, ghx_residual_value = setup_ghp_inputs(s, time_steps, time_steps_without_grid)

    if any(pv.existing_kw > 0 for pv in s.pvs)
        adjust_load_profile(s, production_factor)
    end

    heating_loads = Vector{String}()
    heating_loads_kw = Dict{String, Array{Real,1}}()
    absorption_chillers_using_heating_load = Dict{String,Array{String,1}}()
    if !isnothing(s.dhw_load)
        push!(heating_loads, "DomesticHotWater")
        heating_loads_kw["DomesticHotWater"] = s.dhw_load.loads_kw
        if !isnothing(s.absorption_chiller) && s.absorption_chiller.heating_load_input == "DomesticHotWater"
            absorption_chillers_using_heating_load["DomesticHotWater"] = ["AbsorptionChiller"]
        else
            absorption_chillers_using_heating_load["DomesticHotWater"] = Vector{String}()
        end
    end
    if !isnothing(s.space_heating_load)
        push!(heating_loads, "SpaceHeating")
        heating_loads_kw["SpaceHeating"] = s.space_heating_load.loads_kw
        if !isnothing(s.absorption_chiller) && s.absorption_chiller.heating_load_input == "SpaceHeating"
            absorption_chillers_using_heating_load["SpaceHeating"] = ["AbsorptionChiller"]
        else
            absorption_chillers_using_heating_load["SpaceHeating"] = Vector{String}()
        end
    elseif !isnothing(s.flexible_hvac) && !isnothing(s.existing_boiler)
        push!(heating_loads, "SpaceHeating")  #add blank space heating load to add dvHeatingProduction for existing boiler
    end
    if !isnothing(s.process_heat_load)
        push!(heating_loads, "ProcessHeat")
        heating_loads_kw["ProcessHeat"] = s.process_heat_load.loads_kw
        if !isnothing(s.absorption_chiller) && s.absorption_chiller.heating_load_input == "ProcessHeat"
            absorption_chillers_using_heating_load["ProcessHeat"] = ["AbsorptionChiller"]
        else
            absorption_chillers_using_heating_load["ProcessHeat"] = Vector{String}()
        end
    end

    if sum(heating_loads_kw["SpaceHeating"]) > 0.0 && isempty(techs.can_serve_space_heating) 
        throw(@error("SpaceHeating load is nonzero and no techs can serve the load."))
    end
    if sum(heating_loads_kw["DomesticHotWater"]) > 0.0 && isempty(techs.can_serve_dhw) 
        throw(@error("DomesticHotWater load is nonzero and no techs can serve the load."))
    end
    if sum(heating_loads_kw["ProcessHeat"]) > 0.0 && isempty(techs.can_serve_process_heat) 
        throw(@error("ProcessHeat load is nonzero and no techs can serve the load."))
    end
    
    heating_loads_served_by_tes = Dict{String,Array{String,1}}()
    if !isempty(s.storage.types.hot)
        for b in s.storage.types.hot
            heating_loads_served_by_tes[b] = String[]
            if s.storage.attr[b].can_serve_dhw && ("DomesticHotWater" in heating_loads) && sum(heating_loads_kw["DomesticHotWater"]) > 0.0
                push!(heating_loads_served_by_tes[b],"DomesticHotWater")
            end
            if s.storage.attr[b].can_serve_space_heating && ("SpaceHeating" in heating_loads) && sum(heating_loads_kw["SpaceHeating"]) > 0.0
                push!(heating_loads_served_by_tes[b],"SpaceHeating")
            end
            if s.storage.attr[b].can_serve_process_heat && ("ProcessHeat" in heating_loads) && sum(heating_loads_kw["ProcessHeat"]) > 0.0
                push!(heating_loads_served_by_tes[b],"ProcessHeat")
            end
        end
    end
    unavailability = get_unavailability_by_tech(s, techs, time_steps)

    REoptInputs(
        s,
        techs,
        min_sizes,
        max_sizes,
        existing_sizes,
        cap_cost_slope,
        om_cost_per_kw,
        thermal_cop,
        time_steps,
        time_steps_with_grid,
        time_steps_without_grid,
        hours_per_time_step,
        months,
        production_factor,
        levelization_factor,
        typeof(s.financial.value_of_lost_load_per_kwh) <: Array{<:Real, 1} ? s.financial.value_of_lost_load_per_kwh : fill(s.financial.value_of_lost_load_per_kwh, length(time_steps)),
        pwf_e,
        pwf_om,
        pwf_fuel,
        pwf_emissions_cost,
        pwf_grid_emissions,
        pwf_offtaker, 
        pwf_owner,
        third_party_factor,
        pvlocations,
        maxsize_pv_locations,
        pv_to_location,
        1:length(s.electric_tariff.tou_demand_ratchet_time_steps),  # ratchets
        techs_by_exportbin,
        export_bins_by_tech,
        n_segs_by_tech,
        seg_min_size,
        seg_max_size,
        seg_yint,
        pbi_pwf, 
        pbi_max_benefit, 
        pbi_max_kw, 
        pbi_benefit_per_kwh,
        boiler_efficiency,
        fuel_cost_per_kwh,
        ghp_options,
        require_ghp_purchase,
        ghp_heating_thermal_load_served_kw,
        ghp_cooling_thermal_load_served_kw,
        space_heating_thermal_load_reduction_with_ghp_kw,
        cooling_thermal_load_reduction_with_ghp_kw,
        ghp_electric_consumption_kw,
        ghp_installed_cost,
        ghp_om_cost_year_one,
        avoided_capex_by_ghp_present_value,
        ghx_useful_life_years,
        ghx_residual_value,
        tech_renewable_energy_fraction, 
        tech_emissions_factors_CO2, 
        tech_emissions_factors_NOx, 
        tech_emissions_factors_SO2, 
        tech_emissions_factors_PM25,
        techs_operating_reserve_req_fraction,
        heating_cop,
        cooling_cop,
        heating_cf,
        cooling_cf,
        heating_loads,
        heating_loads_kw,
        heating_loads_served_by_tes,
        unavailability,
        absorption_chillers_using_heating_load,
        avoided_capex_by_ashp_present_value
    )
end


"""
    function setup_tech_inputs(s::AbstractScenario)

Create data arrays associated with techs necessary to build the JuMP model.
"""
function setup_tech_inputs(s::AbstractScenario, time_steps)
    #TODO: create om_cost_per_kwh in here as well as om_cost_per_kw? (Generator, CHP, SteamTurbine, and Boiler have this)
    
    techs = Techs(s)

    boiler_efficiency = Dict{String, Float64}()
    fuel_cost_per_kwh = Dict{String, AbstractArray}()

    # REoptInputs indexed on techs:
    max_sizes = Dict(t => 0.0 for t in techs.all)
    min_sizes = Dict(t => 0.0 for t in techs.all)
    existing_sizes = Dict(t => 0.0 for t in techs.all)
    cap_cost_slope = Dict{String, Any}()
    om_cost_per_kw = Dict(t => 0.0 for t in techs.all)
    production_factor = DenseAxisArray{Float64}(undef, techs.all, 1:length(s.electric_load.loads_kw))
    tech_renewable_energy_fraction = Dict{String, Float64}()
    # !!! note: tech_emissions_factors are in lb / kWh of fuel burned (gets multiplied by kWh of fuel burned, not kWh electricity consumption, ergo the use of the HHV instead of fuel slope)
    tech_emissions_factors_CO2 = Dict(t => 0.0 for t in techs.all)
    tech_emissions_factors_NOx = Dict(t => 0.0 for t in techs.all)
    tech_emissions_factors_SO2 = Dict(t => 0.0 for t in techs.all)
    tech_emissions_factors_PM25 = Dict(t => 0.0 for t in techs.all)
    techs_operating_reserve_req_fraction = Dict(t => 0.0 for t in techs.all)
    thermal_cop = Dict(t => 0.0 for t in techs.absorption_chiller)
    heating_cop = Dict(t => zeros(length(time_steps)) for t in union(techs.heating, techs.chp))
    heating_cf = Dict(t => zeros(length(time_steps)) for t in union(techs.heating, techs.chp))
    cooling_cf = Dict(t => zeros(length(time_steps)) for t in techs.cooling)
    cooling_cop = Dict(t => zeros(length(time_steps)) for t in techs.cooling)
    avoided_capex_by_ashp_present_value = Dict(t => 0.0 for t in techs.all)

    pbi_pwf = Dict{String, Any}()
    pbi_max_benefit = Dict{String, Any}()
    pbi_max_kw = Dict{String, Any}()
    pbi_benefit_per_kwh = Dict{String, Any}()

    # export related inputs
    techs_by_exportbin = Dict{Symbol, AbstractArray}(k => [] for k in s.electric_tariff.export_bins)
    export_bins_by_tech = Dict{String, Array{Symbol, 1}}()

    # REoptInputs indexed on techs.segmented
    n_segs_by_tech = Dict{String, Int}()
    seg_min_size = Dict{String, Dict{Int, Real}}()
    seg_max_size = Dict{String, Dict{Int, Real}}()
    seg_yint = Dict{String, Dict{Int, Real}}()

    pvlocations = [:roof, :ground, :both]
    d = Dict(loc => 0 for loc in pvlocations)
    pv_to_location = Dict(t => copy(d) for t in techs.pv)
    maxsize_pv_locations = DenseAxisArray([1.0e9, 1.0e9, 1.0e9], pvlocations)
    # default to large max size per location. Max size by roof, ground, both
    if !isempty(techs.pv)
        setup_pv_inputs(s, max_sizes, min_sizes, existing_sizes, cap_cost_slope, om_cost_per_kw, production_factor,
            pvlocations, pv_to_location, maxsize_pv_locations, techs.segmented, n_segs_by_tech, 
            seg_min_size, seg_max_size, seg_yint, techs_by_exportbin, techs, 
            pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh, tech_renewable_energy_fraction)
    end

    if "Wind" in techs.all
        setup_wind_inputs(s, max_sizes, min_sizes, existing_sizes, cap_cost_slope, om_cost_per_kw, production_factor, 
            techs_by_exportbin, techs.segmented, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, 
            techs, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh, tech_renewable_energy_fraction)
    end

    if "Generator" in techs.all
        setup_gen_inputs(s, max_sizes, min_sizes, existing_sizes, cap_cost_slope, om_cost_per_kw, production_factor, 
            techs_by_exportbin, techs.segmented, n_segs_by_tech, seg_min_size, seg_max_size, 
            seg_yint, techs, tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, 
            fuel_cost_per_kwh, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh)
    end

    if "ExistingBoiler" in techs.all
        setup_existing_boiler_inputs(s, max_sizes, min_sizes, existing_sizes, cap_cost_slope, boiler_efficiency,
            tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
            heating_cf)
    end

    if "Boiler" in techs.all
        setup_boiler_inputs(s, max_sizes, min_sizes, existing_sizes, cap_cost_slope, boiler_efficiency,
            tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25,
            om_cost_per_kw, production_factor, fuel_cost_per_kwh, heating_cf)
    end

    if "CHP" in techs.all
        setup_chp_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, 
            production_factor, techs_by_exportbin, techs.segmented, n_segs_by_tech, seg_min_size, seg_max_size, 
            seg_yint, techs, tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, 
            tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
            heating_cf, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh)
    end

    if "ExistingChiller" in techs.all
        setup_existing_chiller_inputs(s, max_sizes, min_sizes, existing_sizes, cap_cost_slope, cooling_cop, cooling_cf)
    else
        cooling_cop["ExistingChiller"] = ones(length(time_steps))
        cooling_cf["ExistingChiller"] = zeros(length(time_steps))
    end

    if "AbsorptionChiller" in techs.all
        setup_absorption_chiller_inputs(s, max_sizes, min_sizes, cap_cost_slope, cooling_cop, thermal_cop, om_cost_per_kw, cooling_cf)
    else
        cooling_cop["AbsorptionChiller"] = ones(length(time_steps))
        thermal_cop["AbsorptionChiller"] = 1.0
        cooling_cf["AbsorptionChiller"] = zeros(length(time_steps))
    end

    if "SteamTurbine" in techs.all
        setup_steam_turbine_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, production_factor, techs_by_exportbin, techs, heating_cf,
            pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh)
    end    

    if "ElectricHeater" in techs.all
        setup_electric_heater_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, heating_cop, heating_cf)
    else
        heating_cop["ElectricHeater"] = ones(length(time_steps))
        heating_cf["ElectricHeater"] = zeros(length(time_steps))
    end

    if "ASHPSpaceHeater" in techs.all
        setup_ASHPSpaceHeater_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, heating_cop, cooling_cop, heating_cf, cooling_cf,
            techs.segmented, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, avoided_capex_by_ashp_present_value)
    else
        heating_cop["ASHPSpaceHeater"] = ones(length(time_steps))
        cooling_cop["ASHPSpaceHeater"] = ones(length(time_steps))
        heating_cf["ASHPSpaceHeater"] = zeros(length(time_steps))
        cooling_cf["ASHPSpaceHeater"] = zeros(length(time_steps))
    end

    if "ASHPWaterHeater" in techs.all
        setup_ASHPWaterHeater_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, heating_cop, heating_cf,
            techs.segmented, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, avoided_capex_by_ashp_present_value)
    else
        heating_cop["ASHPWaterHeater"] = ones(length(time_steps))
        heating_cf["ASHPWaterHeater"] = zeros(length(time_steps))
    end

    if !isempty(techs.ghp)
        cooling_cop["GHP"] = ones(length(time_steps))
        heating_cop["GHP"] = ones(length(time_steps))
        heating_cf["GHP"] = ones(length(time_steps))
        cooling_cf["GHP"] = ones(length(time_steps))
    end

    if "CST" in techs.all
        setup_cst_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, heating_cop, heating_cf)
    end

    # filling export_bins_by_tech MUST be done after techs_by_exportbin has been filled in
    for t in techs.elec
        export_bins_by_tech[t] = [bin for (bin, ts) in techs_by_exportbin if t in ts]
    end

    if s.settings.off_grid_flag
        setup_operating_reserve_fraction(s, techs_operating_reserve_req_fraction)
    end

    return techs, pv_to_location, maxsize_pv_locations, pvlocations, 
    production_factor, max_sizes, min_sizes, existing_sizes, cap_cost_slope, om_cost_per_kw, n_segs_by_tech, 
    seg_min_size, seg_max_size, seg_yint, techs_by_exportbin, export_bins_by_tech, boiler_efficiency,
    tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, 
    tech_emissions_factors_PM25, techs_operating_reserve_req_fraction, thermal_cop, fuel_cost_per_kwh, 
    heating_cop, cooling_cop, heating_cf, cooling_cf, avoided_capex_by_ashp_present_value,
    pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh
end


"""
    setup_pbi_inputs!(techs::Techs, tech::AbstractTech, tech_name::String, financial::Financial,
        pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh
    )

Modifies dictionaries for production based incentives: pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh. 
All dicts can be empty if no techs have production_incentive_per_kwh > 0.
"""
function setup_pbi_inputs!(techs::Techs, tech::AbstractTech, tech_name::String, financial::Financial,
    pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh
    )
    if :production_incentive_per_kwh in fieldnames(typeof(tech)) && tech.production_incentive_per_kwh > 0
        push!(techs.pbi, tech_name)
        pbi_pwf[tech_name], pbi_max_benefit[tech_name], pbi_max_kw[tech_name], pbi_benefit_per_kwh[tech_name] = 
            production_incentives(tech, financial)
    end
    return nothing
end


"""
    update_cost_curve!(tech::AbstractTech, tech_name::String, financial::Financial,
        cap_cost_slope, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint
    )

Modifies cap_cost_slope, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint based on tech attributes.
In the simplest case (zero incentives, no existing_kw) the cap_cost_slope is updated with:
```julia
    cap_cost_slope[tech_name] = tech.installed_cost_per_kw
```
However, if there are non-zero incentives or `existing_kw` then there will be more than one cost curve segment typically
and all of the other arguments will be updated as well.
"""
function update_cost_curve!(tech::AbstractTech, tech_name::String, financial::Financial,
    cap_cost_slope, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint
    )    
    cost_slope, cost_curve_bp_x, cost_yint, n_segments = cost_curve(tech, financial)
    cap_cost_slope[tech_name] = first(cost_slope)
    
    min_allowable_kw = isdefined(tech, :min_allowable_kw) ? tech.min_allowable_kw : 0.0
    
    if n_segments > 1 || (typeof(tech)==CHP && min_allowable_kw > 0.0)
        cap_cost_slope[tech_name] = cost_slope
        push!(segmented_techs, tech_name)
        seg_max_size[tech_name] = Dict{Int,Float64}()
        seg_min_size[tech_name] = Dict{Int,Float64}()
        n_segs_by_tech[tech_name] = n_segments
        seg_yint[tech_name] = Dict{Int,Float64}()
        
        for s in 1:n_segments
            seg_min_size[tech_name][s] = typeof(tech)==CHP ? max(cost_curve_bp_x[s], min_allowable_kw) : cost_curve_bp_x[s]
            seg_max_size[tech_name][s] = cost_curve_bp_x[s+1]
            seg_yint[tech_name][s] = cost_yint[s]
        end
    end

    nothing
end

function setup_pv_inputs(s::AbstractScenario, max_sizes, min_sizes,
    existing_sizes, cap_cost_slope, om_cost_per_kw, production_factor,
    pvlocations, pv_to_location, maxsize_pv_locations, segmented_techs, 
    n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, techs_by_exportbin, 
    techs, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh, tech_renewable_energy_fraction)

    pv_roof_limited, pv_ground_limited, pv_space_limited = false, false, false
    roof_existing_pv_kw, ground_existing_pv_kw, both_existing_pv_kw = 0.0, 0.0, 0.0
    roof_max_kw, land_max_kw = 1.0e5, 1.0e5

    for pv in s.pvs        
        production_factor[pv.name, :] = get_production_factor(pv, s.site.latitude, s.site.longitude; 
            time_steps_per_hour=s.settings.time_steps_per_hour)
        for location in pvlocations
            if pv.location == String(location) # Must convert symbol to string
                pv_to_location[pv.name][location] = 1
            else
                pv_to_location[pv.name][location] = 0
            end
        end
        tech_renewable_energy_fraction[pv.name] = 1.0

        beyond_existing_kw = pv.max_kw
        if pv.location == "both"
            both_existing_pv_kw += pv.existing_kw
            if !(s.site.roof_squarefeet === nothing) && !(s.site.land_acres === nothing)
                # don"t restrict unless both land_area and roof_area specified,
                # otherwise one of them is "unlimited"
                roof_max_kw = s.site.roof_squarefeet * pv.kw_per_square_foot
                land_max_kw = s.site.land_acres / pv.acres_per_kw
                beyond_existing_kw = min(roof_max_kw + land_max_kw, beyond_existing_kw)
                pv_space_limited = true
            end
        elseif pv.location == "roof"
            roof_existing_pv_kw += pv.existing_kw
            if !(s.site.roof_squarefeet === nothing)
                roof_max_kw = s.site.roof_squarefeet * pv.kw_per_square_foot
                beyond_existing_kw = min(roof_max_kw, beyond_existing_kw)
                pv_roof_limited = true
            end
        elseif pv.location == "ground"
            ground_existing_pv_kw += pv.existing_kw
            if !(s.site.land_acres === nothing)
                land_max_kw = s.site.land_acres / pv.acres_per_kw
                beyond_existing_kw = min(land_max_kw, beyond_existing_kw)
                pv_ground_limited = true
            end
        end

        existing_sizes[pv.name] = pv.existing_kw
        min_sizes[pv.name] = pv.existing_kw + pv.min_kw
        max_sizes[pv.name] = pv.existing_kw + beyond_existing_kw

        update_cost_curve!(pv, pv.name, s.financial,
            cap_cost_slope, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint
        )

        om_cost_per_kw[pv.name] = pv.om_cost_per_kw
        fillin_techs_by_exportbin(techs_by_exportbin, pv, pv.name)

        if !pv.can_curtail
            push!(techs.no_curtail, pv.name)
        end
        setup_pbi_inputs!(techs, pv, pv.name, s.financial, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh)
    end

    if pv_roof_limited
        maxsize_pv_locations[:roof] = float(roof_existing_pv_kw + roof_max_kw)
    end
    if pv_ground_limited
        maxsize_pv_locations[:ground] = float(ground_existing_pv_kw + land_max_kw)
    end
    if pv_space_limited
        maxsize_pv_locations[:both] = float(both_existing_pv_kw + roof_max_kw + land_max_kw)
    end

    return nothing
end

"""
    function setup_chp_inputs(s::AbstractScenario, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw,  
        production_factor, techs_by_exportbin, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, techs,
        tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
        heating_cf
        )

Update tech-indexed data arrays necessary to build the JuMP model with the values for CHP.
"""
function setup_chp_inputs(s::AbstractScenario, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw,  
    production_factor, techs_by_exportbin, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, techs,
    tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
    heating_cf
    )
    max_sizes["CHP"] = s.chp.max_kw
    min_sizes["CHP"] = s.chp.min_kw
    update_cost_curve!(s.chp, "CHP", s.financial,
        cap_cost_slope, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint
    )
    om_cost_per_kw["CHP"] = s.chp.om_cost_per_kw
    production_factor["CHP", :] = get_production_factor(s.chp, s.electric_load.year, s.electric_utility.outage_start_time_step, 
        s.electric_utility.outage_end_time_step, s.settings.time_steps_per_hour)
    fillin_techs_by_exportbin(techs_by_exportbin, s.chp, "CHP")
    if !s.chp.can_curtail
        push!(techs.no_curtail, "CHP")
    end  
    tech_renewable_energy_fraction["CHP"] = s.chp.fuel_renewable_energy_fraction
    tech_emissions_factors_CO2["CHP"] = s.chp.emissions_factor_lb_CO2_per_mmbtu / KWH_PER_MMBTU  # lb/mmtbu * mmtbu/kWh
    tech_emissions_factors_NOx["CHP"] = s.chp.emissions_factor_lb_NOx_per_mmbtu / KWH_PER_MMBTU
    tech_emissions_factors_SO2["CHP"] = s.chp.emissions_factor_lb_SO2_per_mmbtu / KWH_PER_MMBTU
    tech_emissions_factors_PM25["CHP"] = s.chp.emissions_factor_lb_PM25_per_mmbtu / KWH_PER_MMBTU
    chp_fuel_cost_per_kwh = s.chp.fuel_cost_per_mmbtu ./ KWH_PER_MMBTU
    fuel_cost_per_kwh["CHP"] = per_hour_value_to_time_series(chp_fuel_cost_per_kwh, s.settings.time_steps_per_hour, "CHP")   
    heating_cf["CHP"] = ones(8760*s.settings.time_steps_per_hour)
    return nothing
end


function setup_wind_inputs(s::AbstractScenario, max_sizes, min_sizes, existing_sizes,
    cap_cost_slope, om_cost_per_kw, production_factor, techs_by_exportbin,
    segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, 
    techs, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh, tech_renewable_energy_fraction
    )
    max_sizes["Wind"] = s.wind.max_kw
    min_sizes["Wind"] = s.wind.min_kw
    existing_sizes["Wind"] = 0.0
    tech_renewable_energy_fraction["Wind"] = 1.0
    
    if !(s.site.land_acres === nothing) # Limit based on available land 
        land_max_kw = s.site.land_acres / s.wind.acres_per_kw
        if land_max_kw < 1500 # turbines less than 1.5 MW aren't subject to the acres/kW limit
            land_max_kw = 1500
        end
        if max_sizes["Wind"] > land_max_kw # if user-provided max is greater than land max, update max (otherwise use user-provided max)
            @warn "User-provided maximum wind kW is greater than the calculated land-constrained kW (site.land_acres/wind.acres_per_kw). Wind max kW has been updated to land-constrained max of $(land_max_kw) kW."
            max_sizes["Wind"] = land_max_kw
        end
        if min_sizes["Wind"] > max_sizes["Wind"] # If user-provided min is greater than max (updated to land max as above), send error
            throw(@error("User-provided minimum wind kW is greater than either wind.max_kw or calculated land-constrained kW (site.land_acres/wind.acres_per_kw). Update wind.min_kw or site.land_acres"))
        end 
    end
    
    update_cost_curve!(s.wind, "Wind", s.financial,
        cap_cost_slope, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint
    )
    om_cost_per_kw["Wind"] = s.wind.om_cost_per_kw
    production_factor["Wind", :] = get_production_factor(s.wind, s.site.latitude, s.site.longitude, s.settings.time_steps_per_hour)
    fillin_techs_by_exportbin(techs_by_exportbin, s.wind, "Wind")
    if !s.wind.can_curtail
        push!(techs.no_curtail, "Wind")
    end

    setup_pbi_inputs!(techs, s.wind, "Wind", s.financial, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh)

    return nothing
end


function setup_gen_inputs(s::AbstractScenario, max_sizes, min_sizes, existing_sizes,
    cap_cost_slope, om_cost_per_kw, production_factor, techs_by_exportbin,
    segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, techs,
    tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, 
    tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
    pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh
    )
    max_sizes["Generator"] = s.generator.existing_kw + s.generator.max_kw
    min_sizes["Generator"] = s.generator.existing_kw + s.generator.min_kw
    existing_sizes["Generator"] = s.generator.existing_kw
    update_cost_curve!(s.generator, "Generator", s.financial,
        cap_cost_slope, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint
    )
    om_cost_per_kw["Generator"] = s.generator.om_cost_per_kw
    production_factor["Generator", :] = get_production_factor(s.generator; s.settings.time_steps_per_hour)
    fillin_techs_by_exportbin(techs_by_exportbin, s.generator, "Generator")
    if !s.generator.can_curtail
        push!(techs.no_curtail, "Generator")
    end
    tech_renewable_energy_fraction["Generator"] = s.generator.fuel_renewable_energy_fraction
    hhv_kwh_per_gal = s.generator.fuel_higher_heating_value_kwh_per_gal
    tech_emissions_factors_CO2["Generator"] = s.generator.emissions_factor_lb_CO2_per_gal / hhv_kwh_per_gal  # lb/gal * gal/kWh
    tech_emissions_factors_NOx["Generator"] = s.generator.emissions_factor_lb_NOx_per_gal / hhv_kwh_per_gal
    tech_emissions_factors_SO2["Generator"] = s.generator.emissions_factor_lb_SO2_per_gal / hhv_kwh_per_gal
    tech_emissions_factors_PM25["Generator"] = s.generator.emissions_factor_lb_PM25_per_gal / hhv_kwh_per_gal
    generator_fuel_cost_per_kwh = s.generator.fuel_cost_per_gallon / hhv_kwh_per_gal
    fuel_cost_per_kwh["Generator"] = per_hour_value_to_time_series(generator_fuel_cost_per_kwh, s.settings.time_steps_per_hour, "Generator")
    setup_pbi_inputs!(techs, s.generator, "Generator", s.financial, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh)
    return nothing
end

"""
    function setup_existing_boiler_inputs(s::AbstractScenario, max_sizes, min_sizes, existing_sizes, cap_cost_slope, boiler_efficiency,
        tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
        heating_cf)

Update tech-indexed data arrays necessary to build the JuMP model with the values for existing boiler.
This version of this function, used in BAUInputs(), doesn't update renewable energy and emissions arrays.
"""

function setup_existing_boiler_inputs(s::AbstractScenario, max_sizes, min_sizes, existing_sizes, cap_cost_slope, boiler_efficiency,
    tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
    heating_cf)
    max_sizes["ExistingBoiler"] = s.existing_boiler.max_kw
    min_sizes["ExistingBoiler"] = 0.0
    existing_sizes["ExistingBoiler"] = 0.0
    cap_cost_slope["ExistingBoiler"] = s.existing_boiler.installed_cost_per_kw
    boiler_efficiency["ExistingBoiler"] = s.existing_boiler.efficiency
    # om_cost_per_kw["ExistingBoiler"] = 0.0
    tech_renewable_energy_fraction["ExistingBoiler"] = s.existing_boiler.fuel_renewable_energy_fraction
    tech_emissions_factors_CO2["ExistingBoiler"] = s.existing_boiler.emissions_factor_lb_CO2_per_mmbtu / KWH_PER_MMBTU  # lb/mmtbu * mmtbu/kWh
    tech_emissions_factors_NOx["ExistingBoiler"] = s.existing_boiler.emissions_factor_lb_NOx_per_mmbtu / KWH_PER_MMBTU
    tech_emissions_factors_SO2["ExistingBoiler"] = s.existing_boiler.emissions_factor_lb_SO2_per_mmbtu / KWH_PER_MMBTU
    tech_emissions_factors_PM25["ExistingBoiler"] = s.existing_boiler.emissions_factor_lb_PM25_per_mmbtu / KWH_PER_MMBTU 
    existing_boiler_fuel_cost_per_kwh = s.existing_boiler.fuel_cost_per_mmbtu ./ KWH_PER_MMBTU
    fuel_cost_per_kwh["ExistingBoiler"] = per_hour_value_to_time_series(existing_boiler_fuel_cost_per_kwh, s.settings.time_steps_per_hour, "ExistingBoiler")   
    heating_cf["ExistingBoiler"] = ones(8760*s.settings.time_steps_per_hour)   
    return nothing
end

"""
    function setup_boiler_inputs(s::AbstractScenario, max_sizes, min_sizes, existing_sizes, cap_cost_slope, boiler_efficiency,
        tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, 
        om_cost_per_kw, production_factor, fuel_cost_per_kwh, heating_cf)

Update tech-indexed data arrays necessary to build the JuMP model with the values for (new) boiler.
This version of this function, used in BAUInputs(), doesn't update renewable energy and emissions arrays.
"""
function setup_boiler_inputs(s::AbstractScenario, max_sizes, min_sizes, existing_sizes, cap_cost_slope, boiler_efficiency,
        tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25,
        om_cost_per_kw, production_factor, fuel_cost_per_kwh, heating_cf)
    max_sizes["Boiler"] = s.boiler.max_kw
    min_sizes["Boiler"] = s.boiler.min_kw
    existing_sizes["Boiler"] = 0.0
    boiler_efficiency["Boiler"] = s.boiler.efficiency
    tech_renewable_energy_fraction["Boiler"] = s.boiler.fuel_renewable_energy_fraction
    tech_emissions_factors_CO2["Boiler"] = s.boiler.emissions_factor_lb_CO2_per_mmbtu / KWH_PER_MMBTU  # lb/mmtbu * mmtbu/kWh
    tech_emissions_factors_NOx["Boiler"] = s.boiler.emissions_factor_lb_NOx_per_mmbtu / KWH_PER_MMBTU
    tech_emissions_factors_SO2["Boiler"] = s.boiler.emissions_factor_lb_SO2_per_mmbtu / KWH_PER_MMBTU
    tech_emissions_factors_PM25["Boiler"] = s.boiler.emissions_factor_lb_PM25_per_mmbtu / KWH_PER_MMBTU 
    
    # The Boiler only has a MACRS benefit, no ITC etc.
    if s.boiler.macrs_option_years in [5, 7]

        cap_cost_slope["Boiler"] = effective_cost(;
            itc_basis = s.boiler.installed_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = s.financial.analysis_years,
            discount_rate = s.financial.owner_discount_rate_fraction,
            tax_rate = s.financial.owner_tax_rate_fraction,
            itc = 0.0,
            macrs_schedule = s.boiler.macrs_option_years == 5 ? s.financial.macrs_five_year : s.financial.macrs_seven_year,
            macrs_bonus_fraction = s.boiler.macrs_bonus_fraction,
            macrs_itc_reduction = 0.0,
            rebate_per_kw = 0.0
        )

    else
        cap_cost_slope["Boiler"] = s.boiler.installed_cost_per_kw
    end

    om_cost_per_kw["Boiler"] = s.boiler.om_cost_per_kw
    boiler_fuel_cost_per_kwh = s.boiler.fuel_cost_per_mmbtu ./ KWH_PER_MMBTU
    fuel_cost_per_kwh["Boiler"] = per_hour_value_to_time_series(boiler_fuel_cost_per_kwh, s.settings.time_steps_per_hour, "Boiler")
    heating_cf["Boiler"]  = ones(8760*s.settings.time_steps_per_hour)
    return nothing
end


"""
    function setup_existing_chiller_inputs(s::AbstractScenario, max_sizes, min_sizes, existing_sizes, cap_cost_slope, cooling_cop, cooling_cf)

Update tech-indexed data arrays necessary to build the JuMP model with the values for existing chiller.
"""
function setup_existing_chiller_inputs(s::AbstractScenario, max_sizes, min_sizes, existing_sizes, cap_cost_slope, cooling_cop, cooling_cf)
    max_sizes["ExistingChiller"] = s.existing_chiller.max_kw
    min_sizes["ExistingChiller"] = 0.0
    existing_sizes["ExistingChiller"] = 0.0
    cap_cost_slope["ExistingChiller"] = s.existing_chiller.installed_cost_per_kw
    cooling_cop["ExistingChiller"] .= s.existing_chiller.cop
    cooling_cf["ExistingChiller"]  = ones(8760*s.settings.time_steps_per_hour)
    # om_cost_per_kw["ExistingChiller"] = 0.0
    return nothing
end


function setup_absorption_chiller_inputs(s::AbstractScenario, max_sizes, min_sizes, cap_cost_slope, 
    cooling_cop, thermal_cop, om_cost_per_kw, cooling_cf
    )
    max_sizes["AbsorptionChiller"] = s.absorption_chiller.max_kw
    min_sizes["AbsorptionChiller"] = s.absorption_chiller.min_kw
    
    # The AbsorptionChiller only has a MACRS benefit, no ITC etc.
    if s.absorption_chiller.macrs_option_years in [5, 7]

        cap_cost_slope["AbsorptionChiller"] = effective_cost(;
            itc_basis = s.absorption_chiller.installed_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = s.financial.analysis_years,
            discount_rate = s.financial.owner_discount_rate_fraction,
            tax_rate = s.financial.owner_tax_rate_fraction,
            itc = 0.0,
            macrs_schedule = s.absorption_chiller.macrs_option_years == 5 ? s.financial.macrs_five_year : s.financial.macrs_seven_year,
            macrs_bonus_fraction = s.absorption_chiller.macrs_bonus_fraction,
            macrs_itc_reduction = 0.0,
            rebate_per_kw = 0.0
        )

    else
        cap_cost_slope["AbsorptionChiller"] = s.absorption_chiller.installed_cost_per_kw
    end

    cooling_cop["AbsorptionChiller"] .= s.absorption_chiller.cop_electric
    cooling_cf["AbsorptionChiller"] .= 1.0
    if isnothing(s.chp)
        thermal_factor = 1.0
    elseif s.chp.cooling_thermal_factor == 0.0
        throw(@error("The CHP cooling_thermal_factor is 0.0 which implies that CHP cannot serve AbsorptionChiller. If you
            want to model CHP and AbsorptionChiller, you must specify a cooling_thermal_factor greater than 0.0"))
    else
        thermal_factor = s.chp.cooling_thermal_factor
    end    
    thermal_cop["AbsorptionChiller"] = s.absorption_chiller.cop_thermal * thermal_factor
    om_cost_per_kw["AbsorptionChiller"] = s.absorption_chiller.om_cost_per_kw
    return nothing
end

"""
    function setup_chp_inputs(s::AbstractScenario, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw,  
        production_factor, techs_by_exportbin, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, techs,
        tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
        heating_cf, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh
        )

Update tech-indexed data arrays necessary to build the JuMP model with the values for CHP.
"""
function setup_chp_inputs(s::AbstractScenario, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw,  
    production_factor, techs_by_exportbin, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, techs,
    tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
    heating_cf, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh
    )
    max_sizes["CHP"] = s.chp.max_kw
    min_sizes["CHP"] = s.chp.min_kw
    update_cost_curve!(s.chp, "CHP", s.financial,
        cap_cost_slope, segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint
    )
    om_cost_per_kw["CHP"] = s.chp.om_cost_per_kw
    production_factor["CHP", :] = get_production_factor(s.chp, s.electric_load.year, s.electric_utility.outage_start_time_step, 
        s.electric_utility.outage_end_time_step, s.settings.time_steps_per_hour)
    fillin_techs_by_exportbin(techs_by_exportbin, s.chp, "CHP")
    if !s.chp.can_curtail
        push!(techs.no_curtail, "CHP")
    end  
    tech_renewable_energy_fraction["CHP"] = s.chp.fuel_renewable_energy_fraction
    tech_emissions_factors_CO2["CHP"] = s.chp.emissions_factor_lb_CO2_per_mmbtu / KWH_PER_MMBTU  # lb/mmtbu * mmtbu/kWh
    tech_emissions_factors_NOx["CHP"] = s.chp.emissions_factor_lb_NOx_per_mmbtu / KWH_PER_MMBTU
    tech_emissions_factors_SO2["CHP"] = s.chp.emissions_factor_lb_SO2_per_mmbtu / KWH_PER_MMBTU
    tech_emissions_factors_PM25["CHP"] = s.chp.emissions_factor_lb_PM25_per_mmbtu / KWH_PER_MMBTU
    chp_fuel_cost_per_kwh = s.chp.fuel_cost_per_mmbtu ./ KWH_PER_MMBTU
    fuel_cost_per_kwh["CHP"] = per_hour_value_to_time_series(chp_fuel_cost_per_kwh, s.settings.time_steps_per_hour, "CHP")   
    heating_cf["CHP"] = ones(8760*s.settings.time_steps_per_hour)
    setup_pbi_inputs!(techs, s.chp, "CHP", s.financial, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh)
    return nothing
end

function setup_steam_turbine_inputs(s::AbstractScenario, max_sizes, min_sizes, cap_cost_slope, 
    om_cost_per_kw, production_factor, techs_by_exportbin, techs, heating_cf,
    pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh
    )

    max_sizes["SteamTurbine"] = s.steam_turbine.max_kw
    min_sizes["SteamTurbine"] = s.steam_turbine.min_kw
    
    # The AbsorptionChiller only has a MACRS benefit, no ITC etc.
    if s.steam_turbine.macrs_option_years in [5, 7]
        cap_cost_slope["SteamTurbine"] = effective_cost(;
            itc_basis = s.steam_turbine.installed_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = s.financial.analysis_years,
            discount_rate = s.financial.owner_discount_rate_fraction,
            tax_rate = s.financial.owner_tax_rate_fraction,
            itc = 0.0,
            macrs_schedule = s.steam_turbine.macrs_option_years == 5 ? s.financial.macrs_five_year : s.financial.macrs_seven_year,
            macrs_bonus_fraction = s.steam_turbine.macrs_bonus_fraction,
            macrs_itc_reduction = 0.0,
            rebate_per_kw = 0.0
        )
    else
        cap_cost_slope["SteamTurbine"] = s.steam_turbine.installed_cost_per_kw
    end

    om_cost_per_kw["SteamTurbine"] = s.steam_turbine.om_cost_per_kw
    
    production_factor["SteamTurbine", :] = get_production_factor(s.steam_turbine; s.settings.time_steps_per_hour)
    
    fillin_techs_by_exportbin(techs_by_exportbin, s.steam_turbine, "SteamTurbine")
    
    if !s.steam_turbine.can_curtail
        push!(techs.no_curtail, "SteamTurbine")
    end

    heating_cf["SteamTurbine"] = ones(8760*s.settings.time_steps_per_hour)
    setup_pbi_inputs!(techs, s.steam_turbine, "SteamTurbine", s.financial, pbi_pwf, pbi_max_benefit, pbi_max_kw, pbi_benefit_per_kwh)
    return nothing
end

function setup_electric_heater_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, heating_cop, heating_cf)
    max_sizes["ElectricHeater"] = s.electric_heater.max_kw
    min_sizes["ElectricHeater"] = s.electric_heater.min_kw
    om_cost_per_kw["ElectricHeater"] = s.electric_heater.om_cost_per_kw
    heating_cop["ElectricHeater"] .= s.electric_heater.cop
    heating_cf["ElectricHeater"] = ones(8760*s.settings.time_steps_per_hour)  #TODO: add timem series input for Electric Heater if using as AShP DHW heater? or use ASHP object?

    if s.electric_heater.macrs_option_years in [5, 7]
        cap_cost_slope["ElectricHeater"] = effective_cost(;
            itc_basis = s.electric_heater.installed_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = s.financial.analysis_years,
            discount_rate = s.financial.owner_discount_rate_fraction,
            tax_rate = s.financial.owner_tax_rate_fraction,
            itc = 0.0,
            macrs_schedule = s.electric_heater.macrs_option_years == 5 ? s.financial.macrs_five_year : s.financial.macrs_seven_year,
            macrs_bonus_fraction = s.electric_heater.macrs_bonus_fraction,
            macrs_itc_reduction = 0.0,
            rebate_per_kw = 0.0
        )
    else
        cap_cost_slope["ElectricHeater"] = s.electric_heater.installed_cost_per_kw
    end

end

function setup_cst_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, heating_cop, heating_cf)
    max_sizes["CST"] = s.cst.max_kw
    min_sizes["CST"] = s.cst.min_kw
    om_cost_per_kw["CST"] = s.cst.om_cost_per_kw
    heating_cop["CST"] = 1000*ones(s.settings.time_steps_per_hour*8760)  # TODO: merge ASHP developments to make heating_cop a time series, and import the electrical consumption from SAM.
    heating_cf["CST"] = s.cst.production_factor

    if s.cst.macrs_option_years in [5, 7]
        cap_cost_slope["CST"] = effective_cost(;
            itc_basis = s.cst.installed_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = s.financial.analysis_years,
            discount_rate = s.financial.owner_discount_rate_fraction,
            tax_rate = s.financial.owner_tax_rate_fraction,
            itc = 0.0,
            macrs_schedule = s.cst.macrs_option_years == 5 ? s.financial.macrs_five_year : s.financial.macrs_seven_year,
            macrs_bonus_fraction = s.cst.macrs_bonus_fraction,
            macrs_itc_reduction = 0.0,
            rebate_per_kw = 0.0
        )
    else
        cap_cost_slope["CST"] = s.cst.installed_cost_per_kw
    end

end

function setup_ASHPSpaceHeater_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, heating_cop, cooling_cop, heating_cf, cooling_cf,
        segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, avoided_capex_by_ashp_present_value)
    max_sizes["ASHPSpaceHeater"] = s.ashp.max_kw
    min_sizes["ASHPSpaceHeater"] = s.ashp.min_kw
    om_cost_per_kw["ASHPSpaceHeater"] = s.ashp.om_cost_per_kw
    heating_cop["ASHPSpaceHeater"] = s.ashp.heating_cop
    cooling_cop["ASHPSpaceHeater"] = s.ashp.cooling_cop
    heating_cf["ASHPSpaceHeater"] = s.ashp.heating_cf
    cooling_cf["ASHPSpaceHeater"] = s.ashp.cooling_cf

    if s.ashp.min_allowable_kw > 0.0
        cap_cost_slope["ASHPSpaceHeater"] = s.ashp.installed_cost_per_kw
        push!(segmented_techs, "ASHPSpaceHeater")
        seg_max_size["ASHPSpaceHeater"] = Dict{Int,Float64}(1 => min(s.ashp.max_kw))
        seg_min_size["ASHPSpaceHeater"] = Dict{Int,Float64}(1 => s.ashp.min_allowable_kw)
        n_segs_by_tech["ASHPSpaceHeater"] = 1
        seg_yint["ASHPSpaceHeater"] = Dict{Int,Float64}(1 => 0.0)
    end

    if s.ashp.macrs_option_years in [5, 7]
        cap_cost_slope["ASHPSpaceHeater"] = effective_cost(;
            itc_basis = s.ashp.installed_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = s.financial.analysis_years,
            discount_rate = s.financial.owner_discount_rate_fraction,
            tax_rate = s.financial.owner_tax_rate_fraction,
            itc = 0.0,
            macrs_schedule = s.ashp.macrs_option_years == 5 ? s.financial.macrs_five_year : s.financial.macrs_seven_year,
            macrs_bonus_fraction = s.ashp.macrs_bonus_fraction,
            macrs_itc_reduction = 0.0,
            rebate_per_kw = 0.0
        )
    else
        cap_cost_slope["ASHPSpaceHeater"] = s.ashp.installed_cost_per_kw
    end
    
    avoided_capex_by_ashp_present_value["ASHPSpaceHeater"] = s.ashp.avoided_capex_by_ashp_present_value
end

function setup_ASHPWaterHeater_inputs(s, max_sizes, min_sizes, cap_cost_slope, om_cost_per_kw, heating_cop, heating_cf,
        segmented_techs, n_segs_by_tech, seg_min_size, seg_max_size, seg_yint, avoided_capex_by_ashp_present_value)
    max_sizes["ASHPWaterHeater"] = s.ashp_wh.max_kw
    min_sizes["ASHPWaterHeater"] = s.ashp_wh.min_kw
    om_cost_per_kw["ASHPWaterHeater"] = s.ashp_wh.om_cost_per_kw
    heating_cop["ASHPWaterHeater"] = s.ashp_wh.heating_cop
    heating_cf["ASHPWaterHeater"] = s.ashp_wh.heating_cf

    if s.ashp_wh.min_allowable_kw > 0.0
        cap_cost_slope["ASHPWaterHeater"] = s.ashp_wh.installed_cost_per_kw
        push!(segmented_techs, "ASHPWaterHeater")
        seg_max_size["ASHPWaterHeater"] = Dict{Int,Float64}(1 => s.ashp_wh.max_kw)
        seg_min_size["ASHPWaterHeater"] = Dict{Int,Float64}(1 => s.ashp_wh.min_allowable_kw)
        n_segs_by_tech["ASHPWaterHeater"] = 1
        seg_yint["ASHPWaterHeater"] = Dict{Int,Float64}(1 => 0.0)
    end

    if s.ashp_wh.macrs_option_years in [5, 7]
        cap_cost_slope["ASHPWaterHeater"] = effective_cost(;
            itc_basis = s.ashp_wh.installed_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = s.financial.analysis_years,
            discount_rate = s.financial.owner_discount_rate_fraction,
            tax_rate = s.financial.owner_tax_rate_fraction,
            itc = 0.0,
            macrs_schedule = s.ashp_wh.macrs_option_years == 5 ? s.financial.macrs_five_year : s.financial.macrs_seven_year,
            macrs_bonus_fraction = s.ashp_wh.macrs_bonus_fraction,
            macrs_itc_reduction = 0.0,
            rebate_per_kw = 0.0
        )
    else
        cap_cost_slope["ASHPWaterHeater"] = s.ashp_wh.installed_cost_per_kw
    end
    avoided_capex_by_ashp_present_value["ASHPWaterHeater"] = s.ashp_wh.avoided_capex_by_ashp_present_value
end


function setup_present_worth_factors(s::AbstractScenario, techs::Techs)

    lvl_factor = Dict(t => 1.0 for t in techs.all)  # default levelization_factor of 1.0
    for (i, tech) in enumerate(techs.pv)  # replace 1.0 with actual PV levelization_factor (only tech with degradation)
        lvl_factor[tech] = levelization_factor(
            s.financial.analysis_years,
            s.financial.elec_cost_escalation_rate_fraction,
            s.financial.offtaker_discount_rate_fraction,
            s.pvs[i].degradation_fraction  # TODO generalize for any tech (not just pvs)
        )
    end

    pwf_e = annuity(
        s.financial.analysis_years,
        s.financial.elec_cost_escalation_rate_fraction,
        s.financial.offtaker_discount_rate_fraction
    )

    pwf_om = annuity(
        s.financial.analysis_years,
        s.financial.om_cost_escalation_rate_fraction,
        s.financial.owner_discount_rate_fraction
    )
    pwf_fuel = Dict{String, Float64}()
    for t in techs.fuel_burning
        if t == "ExistingBoiler"
            pwf_fuel["ExistingBoiler"] = annuity(
                s.financial.analysis_years,
                s.financial.existing_boiler_fuel_cost_escalation_rate_fraction,
                s.financial.offtaker_discount_rate_fraction
            )
        end
        if t == "Boiler"
            pwf_fuel["Boiler"] = annuity(
                s.financial.analysis_years,
                s.financial.boiler_fuel_cost_escalation_rate_fraction,
                s.financial.offtaker_discount_rate_fraction
            )
        end
        if t == "CHP"
            pwf_fuel["CHP"] = annuity(
                s.financial.analysis_years,
                s.financial.chp_fuel_cost_escalation_rate_fraction,
                s.financial.offtaker_discount_rate_fraction
            )
        end
        if t == "Generator" 
            pwf_fuel["Generator"] = annuity(
                s.financial.analysis_years,
                s.financial.generator_fuel_cost_escalation_rate_fraction,
                s.financial.offtaker_discount_rate_fraction
            )
        end     
    end

    # Emissions pwfs
    pwf_emissions_cost = Dict{String, Float64}()
    pwf_grid_emissions = Dict{String, Float64}() # used to calculate total grid CO2, NOx, SO2, and PM2.5 lbs
    for emissions_type in ["CO2", "NOx", "SO2", "PM25"]
        merge!(pwf_emissions_cost, 
                Dict(emissions_type*"_grid"=>annuity_two_escalation_rates(
                            s.financial.analysis_years, 
                            getproperty(s.financial, Symbol("$(emissions_type)_cost_escalation_rate_fraction")),  
                            -1.0 * getproperty(s.electric_utility, Symbol("emissions_factor_$(emissions_type)_decrease_fraction")),
                            s.financial.offtaker_discount_rate_fraction)
                )
        )
        merge!(pwf_emissions_cost, 
                Dict(emissions_type*"_onsite"=>annuity(
                            s.financial.analysis_years, 
                            getproperty(s.financial, Symbol("$(emissions_type)_cost_escalation_rate_fraction")), 
                            s.financial.offtaker_discount_rate_fraction)
                )
        )
        merge!(pwf_grid_emissions, 
                Dict(emissions_type=>annuity(
                            s.financial.analysis_years, 
                            -1.0 * getproperty(s.electric_utility, Symbol("emissions_factor_$(emissions_type)_decrease_fraction")),
                            0.0)
                )
        )
    end

    pwf_offtaker = annuity(s.financial.analysis_years, 0.0, s.financial.offtaker_discount_rate_fraction)
    pwf_owner = annuity(s.financial.analysis_years, 0.0, s.financial.owner_discount_rate_fraction)
    if s.financial.third_party_ownership
        third_party_factor = (pwf_offtaker * (1 - s.financial.offtaker_tax_rate_fraction)) /
                           (pwf_owner * (1 - s.financial.owner_tax_rate_fraction))
    else
        third_party_factor = 1.0
    end

    return lvl_factor, pwf_e, pwf_om, pwf_fuel, pwf_emissions_cost, pwf_grid_emissions, third_party_factor, pwf_offtaker, pwf_owner
end


"""
    setup_electric_utility_inputs(s::AbstractScenario)

Define the `time_steps_with_grid` and `time_steps_without_grid` (detministic outage).

NOTE: v1 of the API spliced the critical_loads_kw into the loads_kw during outages but this splicing is no longer needed
now that the constraints are properly applied over `time_steps_with_grid` and `time_steps_without_grid` using loads_kw
and critical_loads_kw respectively.
"""
function setup_electric_utility_inputs(s::AbstractScenario)
    if s.electric_utility.outage_end_time_step > 0 &&
            s.electric_utility.outage_end_time_step >= s.electric_utility.outage_start_time_step
        time_steps_without_grid = Int[i for i in range(s.electric_utility.outage_start_time_step,
                                                    stop=s.electric_utility.outage_end_time_step)]
        if s.electric_utility.outage_start_time_step > 1
            time_steps_with_grid = append!(
                Int[i for i in range(1, stop=s.electric_utility.outage_start_time_step - 1)],
                Int[i for i in range(s.electric_utility.outage_end_time_step + 1,
                                     stop=length(s.electric_load.loads_kw))]
            )
        else
            time_steps_with_grid = Int[i for i in range(s.electric_utility.outage_end_time_step + 1,
                                       stop=length(s.electric_load.loads_kw))]
        end
    else
        time_steps_without_grid = Int[]
        time_steps_with_grid = Int[i for i in range(1, stop=length(s.electric_load.loads_kw))]
    end
    return time_steps_with_grid, time_steps_without_grid
end


"""
    adjust_load_profile(s::AbstractScenario, production_factor::DenseAxisArray)

Adjust the (critical_)loads_kw based off of (critical_)loads_kw_is_net
"""
function adjust_load_profile(s::AbstractScenario, production_factor::DenseAxisArray)
    if s.electric_load.loads_kw_is_net
        for pv in s.pvs if pv.existing_kw > 0
            s.electric_load.loads_kw .+= pv.existing_kw * production_factor[pv.name, :].data
        end end
    end
    
    if s.electric_load.critical_loads_kw_is_net
        for pv in s.pvs if pv.existing_kw > 0
            s.electric_load.critical_loads_kw .+= pv.existing_kw * production_factor[pv.name, :].data
        end end
    end
end


"""
    production_incentives(tech::AbstractTech, financial::Financial)

Intermediate function for building the PBI arrays in REoptInputs
"""
function production_incentives(tech::AbstractTech, financial::Financial)
    pwf_prod_incent = 0.0
    max_prod_incent = 0.0
    max_size_for_prod_incent = 0.0
    production_incentive_rate = 0.0
    T = typeof(tech)
    if :degradation_fraction in fieldnames(T)  # PV has degradation
        pwf_prod_incent = annuity_escalation(tech.production_incentive_years, -1*tech.degradation_fraction,
                                                financial.owner_discount_rate_fraction)
    else
        # prod incentives have zero escalation rate
        pwf_prod_incent = annuity(tech.production_incentive_years, 0, financial.owner_discount_rate_fraction)
    end
    max_prod_incent = tech.production_incentive_max_benefit
    max_size_for_prod_incent = tech.production_incentive_max_kw
    production_incentive_rate = tech.production_incentive_per_kwh

    return pwf_prod_incent, max_prod_incent, max_size_for_prod_incent, production_incentive_rate
end


function fillin_techs_by_exportbin(techs_by_exportbin::Dict, tech::AbstractTech, tech_name::String)
    if tech.can_net_meter && :NEM in keys(techs_by_exportbin)
        push!(techs_by_exportbin[:NEM], tech_name)
        if tech.can_export_beyond_nem_limit && :EXC in keys(techs_by_exportbin)
            push!(techs_by_exportbin[:EXC], tech_name)
        end
    end
    
    if tech.can_wholesale && :WHL in keys(techs_by_exportbin)
        push!(techs_by_exportbin[:WHL], tech_name)
    end
    return nothing
end

function setup_ghp_inputs(s::AbstractScenario, time_steps, time_steps_without_grid)
    # GHP parameters for REopt model
    num = length(s.ghp_option_list)
    ghp_options = 1:num
    require_ghp_purchase = 0
    ghp_installed_cost = Vector{Float64}(undef, num)
    ghp_om_cost_year_one = Vector{Float64}(undef, num)
    ghp_heating_thermal_load_served_kw = zeros(num, length(time_steps))
    ghp_cooling_thermal_load_served_kw = zeros(num, length(time_steps))
    space_heating_thermal_load_reduction_with_ghp_kw = zeros(num, length(time_steps))
    cooling_thermal_load_reduction_with_ghp_kw = zeros(num, length(time_steps))
    ghp_cooling_thermal_load_served_kw = zeros(num, length(time_steps))        
    ghp_electric_consumption_kw = zeros(num, length(time_steps))
    avoided_capex_by_ghp_present_value = Vector{Float64}(undef, num)
    ghx_useful_life_years = Vector{Float64}(undef, num)
    ghx_residual_value = Vector{Float64}(undef, num)
    if num > 0
        require_ghp_purchase = s.ghp_option_list[1].require_ghp_purchase  # This does not change with the number of options
       
        for (i, option) in enumerate(s.ghp_option_list)
            if option.heat_pump_configuration == "WSHP"
                fixed_cost, variable_cost = get_ghp_installed_cost(option, s.financial, option.heatpump_capacity_ton)
                ghp_installed_cost[i] = fixed_cost + variable_cost

            elseif option.heat_pump_configuration == "WWHP"
                temp = option.installed_cost_per_kw
                option.installed_cost_per_kw = option.wwhp_heating_pump_installed_cost_curve
                fixed_cost_heating, variable_cost_heating = get_ghp_installed_cost(option, s.financial, option.wwhp_heating_pump_capacity_ton)
                ghp_installed_cost_heating = 0.5 * fixed_cost_heating + variable_cost_heating
                
                option.installed_cost_per_kw = option.wwhp_cooling_pump_installed_cost_curve
                fixed_cost_cooling, variable_cost_cooling = get_ghp_installed_cost(option, s.financial, option.wwhp_cooling_pump_capacity_ton)
                option.installed_cost_per_kw = temp
                ghp_installed_cost_cooling = 0.5 * fixed_cost_cooling + variable_cost_cooling

                ghp_installed_cost[i] = ghp_installed_cost_heating + ghp_installed_cost_cooling
            end

            ghp_om_cost_year_one[i] = option.om_cost_year_one
            avoided_capex_by_ghp_present_value[i] = option.avoided_capex_by_ghp_present_value
            ghx_useful_life_years[i] = option.ghx_useful_life_years
            # ownership guided residual value determination
            discount_rate = (1 - 1*s.financial.third_party_ownership)*s.financial.offtaker_discount_rate_fraction + s.financial.third_party_ownership*s.financial.owner_discount_rate_fraction
            ghx_residual_value[i] = option.ghx_only_capital_cost*
            (
                (option.ghx_useful_life_years - s.financial.analysis_years)/option.ghx_useful_life_years
            )/(
                (1 + discount_rate)^s.financial.analysis_years
            )

            heating_thermal_load = s.space_heating_load.loads_kw + s.dhw_load.loads_kw + s.process_heat_load.loads_kw
            # Using minimum of thermal load and ghp-serving load to avoid small negative net loads
            for j in time_steps
                space_heating_thermal_load_reduction_with_ghp_kw[i,j] = min(s.space_heating_thermal_load_reduction_with_ghp_kw[j], heating_thermal_load[j])
                cooling_thermal_load_reduction_with_ghp_kw[i,j] = min(s.cooling_thermal_load_reduction_with_ghp_kw[j], s.cooling_load.loads_kw_thermal[j])
                ghp_heating_thermal_load_served_kw[i,j] = min(option.heating_thermal_kw[j], heating_thermal_load[j] - space_heating_thermal_load_reduction_with_ghp_kw[i,j])
                ghp_cooling_thermal_load_served_kw[i,j] = min(option.cooling_thermal_kw[j], s.cooling_load.loads_kw_thermal[j] - cooling_thermal_load_reduction_with_ghp_kw[i,j])
                ghp_electric_consumption_kw[i,j] = option.yearly_electric_consumption_kw[j]
            end

            # GHP electric consumption is omitted from the electric load balance during an outage
            # So here we also have to zero out heating and cooling thermal production from GHP during an outage
            if !isempty(time_steps_without_grid)
                for outage_time_step in time_steps_without_grid
                    space_heating_thermal_load_reduction_with_ghp_kw[i,outage_time_step] = 0.0
                    cooling_thermal_load_reduction_with_ghp_kw[i,outage_time_step] = 0.0
                    ghp_heating_thermal_load_served_kw[i,outage_time_step] = 0.0
                    ghp_cooling_thermal_load_served_kw[i,outage_time_step] = 0.0
                    ghp_electric_consumption_kw[i,outage_time_step] = 0.0
                end
            end
        end
    end

    return ghp_options, require_ghp_purchase, ghp_heating_thermal_load_served_kw, 
    ghp_cooling_thermal_load_served_kw, space_heating_thermal_load_reduction_with_ghp_kw, 
    cooling_thermal_load_reduction_with_ghp_kw, ghp_electric_consumption_kw, 
    ghp_installed_cost, ghp_om_cost_year_one, avoided_capex_by_ghp_present_value,
    ghx_useful_life_years, ghx_residual_value
end

function setup_operating_reserve_fraction(s::AbstractScenario, techs_operating_reserve_req_fraction)
    # Currently PV, Wind, and CHP can require or provide operating reserves in off-grid scenarios
    for pv in s.pvs 
        techs_operating_reserve_req_fraction[pv.name] = pv.operating_reserve_required_fraction
    end

    techs_operating_reserve_req_fraction["Wind"] = s.wind.operating_reserve_required_fraction

    if !isnothing(s.chp)
        techs_operating_reserve_req_fraction["CHP"] = s.chp.operating_reserve_required_fraction
    end

    return nothing
end

function get_ghp_installed_cost(option::AbstractTech, financial::Financial, ghp_size_ton::Float64)

    ghp_cap_cost_slope, ghp_cap_cost_x, ghp_cap_cost_yint, ghp_n_segments = cost_curve(option, financial)
    seg = 0
    if ghp_size_ton <= ghp_cap_cost_x[1]
        seg = 2
    elseif ghp_size_ton > ghp_cap_cost_x[end]
        seg = ghp_n_segments+1
    else
        for n in 2:(ghp_n_segments+1)
            if (ghp_size_ton > ghp_cap_cost_x[n-1]) && (ghp_size_ton <= ghp_cap_cost_x[n])
                seg = n
                break
            end
        end
    end
    fixed_cost = ghp_cap_cost_yint[seg-1] 
    variable_cost = ghp_size_ton * ghp_cap_cost_slope[seg-1]

    return fixed_cost, variable_cost
end

function get_unavailability_by_tech(s::AbstractScenario, techs::Techs, time_steps)
    if !isempty(techs.elec)
        unavailability = Dict(tech => zeros(length(time_steps)) for tech in techs.elec)
        if !isempty(techs.chp)
            unavailability["CHP"] = [s.chp.unavailability_hourly[i] for i in 1:8760 for _ in 1:s.settings.time_steps_per_hour]
        end
    else
        unavailability = Dict(""=>Float64[])
    end
    return unavailability
end