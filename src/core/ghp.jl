# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.


"""
GHP evaluations typically require the `GhpGhx.jl` package to be loaded unless the `GhpGhx.jl` package 
was already used externally to create `inputs_dict["GHP"]["ghpghx_responses"]`. See the Home page under 
"Additional package loading for GHP" for instructions. This `GHP` struct uses the response from `GhpGhx.jl`
to process input parameters for REopt including additional cost parameters for `GHP`.

    GHP

struct with outer constructor:
```julia
    require_ghp_purchase::Union{Bool, Int64} = false  # 0 = false, 1 = true
    installed_cost_heatpump_per_ton::Float64 = 1075.0
    installed_cost_wwhp_heating_pump_per_ton::Float64 = 700.0
    installed_cost_wwhp_cooling_pump_per_ton::Float64 = 700.0
    heatpump_capacity_sizing_factor_on_peak_load::Float64 = 1.1
    installed_cost_ghx_per_ft::Float64 = 14.0
    installed_cost_building_hydronic_loop_per_sqft = 1.70
    om_cost_per_sqft_year::Float64 = -0.51
    building_sqft::Float64                                  # Required input
    space_heating_efficiency_thermal_factor::Float64 = NaN  # Default depends on building and location
    cooling_efficiency_thermal_factor::Float64 = NaN        # Default depends on building and location
    ghpghx_response::Dict = Dict()
    can_serve_dhw::Bool = false
    max_ton::Real                                           # Maximum heat pump capacity size. Default at a big number
    max_number_of_boreholes::Real                           # Maximum GHX size
    load_served_by_ghp::String                              # "scaled" or "nonpeak"

    macrs_option_years::Int = 0
    macrs_bonus_fraction::Float64 = 0.0
    macrs_itc_reduction::Float64 = 0.5
    federal_itc_fraction::Float64 = 0.3 #Note: default may change if Site.sector is not "commercial/industrial"
    federal_rebate_per_ton::Float64 = 0.0
    federal_rebate_per_kw::Float64 = 0.0
    state_ibi_fraction::Float64 = 0.0
    state_ibi_max::Float64 = 1.0e10
    state_rebate_per_ton::Float64 = 0.0
    state_rebate_per_kw::Float64 = 0.0
    state_rebate_max::Float64 = 1.0e10
    utility_ibi_fraction::Float64 = 0.0
    utility_ibi_max::Float64 = 1.0e10
    utility_rebate_per_ton::Float64 = 0.0
    utility_rebate_per_kw::Float64 = 0.0
    utility_rebate_max::Float64 = 1.0e10

    # Processed data from inputs and results of GhpGhx.jl
    heating_thermal_kw::Vector{Float64} = []
    cooling_thermal_kw::Vector{Float64} = []
    yearly_electric_consumption_kw::Vector{Float64} = []
    peak_combined_heatpump_thermal_ton::Float64 = NaN

    # Intermediate parameters for cost processing
    tech_sizes_for_cost_curve::Union{Float64, AbstractVector{Float64}} = NaN
    installed_cost_per_kw::Union{Float64, AbstractVector{Float64}} = NaN
    heatpump_capacity_ton::Float64 = NaN

    # Process and populate these parameters needed more directly by the model
    installed_cost::Float64 = NaN
    om_cost_year_one::Float64 = NaN
```
"""
Base.@kwdef mutable struct GHP <: AbstractGHP
    require_ghp_purchase::Union{Bool, Int64} = false  # 0 = false, 1 = true
    installed_cost_heatpump_per_ton::Float64 = 1075.0
    installed_cost_wwhp_heating_pump_per_ton::Float64 = 700.0
    installed_cost_wwhp_cooling_pump_per_ton::Float64 = 700.0
    heatpump_capacity_sizing_factor_on_peak_load::Float64 = 1.1
    installed_cost_ghx_per_ft::Float64 = 14.0
    ghx_useful_life_years::Int = 50
    ghx_only_capital_cost::Union{Float64, Nothing} = nothing # overwritten afterwards
    installed_cost_building_hydronic_loop_per_sqft = 1.70
    om_cost_per_sqft_year::Float64 = -0.51
    building_sqft::Float64 # Required input
    space_heating_efficiency_thermal_factor::Float64 = NaN  # Default depends on building and location
    cooling_efficiency_thermal_factor::Float64 = NaN # Default depends on building and location
    ghpghx_response::Dict = Dict()
    can_serve_dhw::Bool = false  # If this default changes, must change conditional in scenario.jl for sending loads to GhpGhx.jl
    can_serve_space_heating::Bool = true
    can_serve_process_heat::Bool = false
    can_supply_steam_turbine::Bool = false
    max_ton::Real = BIG_NUMBER
    max_number_of_boreholes::Real = BIG_NUMBER
    load_served_by_ghp::String = "nonpeak"

    aux_heater_type::String = "electric"
    is_ghx_hybrid::Bool = false
    aux_heater_installed_cost_per_mmbtu_per_hr::Float64 = 26000.00
    aux_cooler_installed_cost_per_ton::Float64 = 400.00
    aux_unit_capacity_sizing_factor_on_peak_load::Float64 = 1.2

    macrs_option_years::Int = 0
    macrs_bonus_fraction::Float64 = 0.0
    macrs_itc_reduction::Float64 = 0.5
    federal_itc_fraction::Float64 = 0.3
    federal_rebate_per_ton::Float64 = 0.0
    federal_rebate_per_kw::Float64 = 0.0
    state_ibi_fraction::Float64 = 0.0
    state_ibi_max::Float64 = 1.0e10
    state_rebate_per_ton::Float64 = 0.0
    state_rebate_per_kw::Float64 = 0.0
    state_rebate_max::Float64 = 1.0e10
    utility_ibi_fraction::Float64 = 0.0
    utility_ibi_max::Float64 = 1.0e10
    utility_rebate_per_ton::Float64 = 0.0
    utility_rebate_per_kw::Float64 = 0.0
    utility_rebate_max::Float64 = 1.0e10

    # Processed data from inputs and results of GhpGhx.jl
    heating_thermal_kw::Vector{Float64} = []
    cooling_thermal_kw::Vector{Float64} = []
    yearly_electric_consumption_kw::Vector{Float64} = []
    peak_combined_heatpump_thermal_ton::Float64 = NaN
    heat_pump_configuration::String = ""

    # Intermediate parameters for cost processing
    tech_sizes_for_cost_curve::Union{Float64, AbstractVector{Float64}} = NaN
    installed_cost_per_kw::Union{Float64, AbstractVector{Float64}} = NaN
    wwhp_heating_pump_installed_cost_curve::Union{Float64, AbstractVector{Float64}} = NaN
    wwhp_cooling_pump_installed_cost_curve::Union{Float64, AbstractVector{Float64}} = NaN
    heatpump_capacity_ton::Float64 = 0
    wwhp_heating_pump_capacity_ton::Float64 = 0
    wwhp_cooling_pump_capacity_ton::Float64 = 0

    # Process and populate these parameters needed more directly by the model
    om_cost_year_one::Float64 = NaN
    hybrid_solution_type::String = "" # automatic_guess_correct, flipped_guess, nonhybrid_solution
    number_of_boreholes_auto_guess::Float64 = -1.0
    number_of_boreholes_flipped_guess::Float64 = -1.0
    number_of_boreholes_nonhybrid::Float64 = -1.0

    iterations_auto_guess::Float64 = -1.0
    iterations_flipped_guess::Float64 = -1.0
    iterations_nonhybrid::Float64 = -1.0

    solve_time_min::Float64 = -1.0

    # Account for expenses avoided by addition of GHP.
    avoided_capex_by_ghp_present_value::Float64 = 0.0
end


function GHP(response::Dict, d::Dict; sector::String, federal_procurement_type::String)
    d = dictkeys_tosymbols(d)
    set_sector_defaults!(d; struct_name="GHP", sector=sector, federal_procurement_type=federal_procurement_type)

    ghp = GHP(; ghpghx_response = response, d...)
    
    if !(0 <= ghp.aux_cooler_installed_cost_per_ton <= 1.0e6)
        @error "out of bounds aux_cooler_installed_cost_per_ton"
    end

    if !(0 <= ghp.aux_heater_installed_cost_per_mmbtu_per_hr <= 1.0e6)
        @error "out of bounds aux_heater_installed_cost_per_mmbtu_per_hr"
    end

    if !(1.0 <= ghp.aux_unit_capacity_sizing_factor_on_peak_load <= 5.0)
        @error "out of bounds aux_unit_capacity_sizing_factor_on_peak_load"
    end

    # Inputs of GhpGhx.jl, which are still needed in REopt
    ghp.heating_thermal_kw = response["inputs"]["heating_thermal_load_mmbtu_per_hr"] * KWH_PER_MMBTU
    ghp.cooling_thermal_kw = response["inputs"]["cooling_thermal_load_ton"] * KWH_THERMAL_PER_TONHOUR
    # Outputs of GhpGhx.jl
    ghp.heat_pump_configuration = response["outputs"]["heat_pump_configuration"]
    ghp.yearly_electric_consumption_kw = response["outputs"]["yearly_total_electric_consumption_series_kw"]
    ghp.peak_combined_heatpump_thermal_ton = response["outputs"]["peak_combined_heatpump_thermal_ton"]

    # Change units basis from ton to kW to use existing cost_curve function
    for region in ["federal", "state", "utility"]
        setfield!(ghp, Symbol(region * "_rebate_per_kw"), getfield(ghp, Symbol(region * "_rebate_per_ton")))
    end
    # incentives = IncentivesNoProdBased(**d_mod)
    
    setup_installed_cost_curve!(d, ghp, response)

    setup_om_cost!(ghp)

    # Convert boolean input into an integer for the model
    if typeof(ghp.require_ghp_purchase) == Bool && ghp.require_ghp_purchase
        ghp.require_ghp_purchase = 1
    elseif typeof(ghp.require_ghp_purchase) == Bool && ghp.require_ghp_purchase == false
        ghp.require_ghp_purchase = 0
    end
    return ghp
end

"""
    setup_installed_cost_curve!(d::Dict, response::Dict, ghp::GHP)

"""
function setup_installed_cost_curve!(d::Dict, ghp::GHP, response::Dict)
    big_number = 1.0e10
    # GHX and GHP sizing metrics for cost calculations
    total_ghx_ft = response["outputs"]["number_of_boreholes"] * response["outputs"]["length_boreholes_ft"]
    
    if ghp.heat_pump_configuration == "WSHP"
        heatpump_peak_ton = response["outputs"]["peak_combined_heatpump_thermal_ton"]
    elseif ghp.heat_pump_configuration == "WWHP"
        wwhp_heating_pump_peak_ton = response["outputs"]["peak_heating_heatpump_thermal_ton"]
        wwhp_cooling_pump_peak_ton = response["outputs"]["peak_cooling_heatpump_thermal_ton"]
    end

    # Use initial cost curve to leverage existing incentives-based cost curve method in data_manager
    # The GHX and hydronic loop cost are the y-intercepts ([$]) of the cost for each design
    hydronic_loop_cost = ghp.building_sqft * ghp.installed_cost_building_hydronic_loop_per_sqft

    if isnothing(ghp.ghx_only_capital_cost)
        ghp.ghx_only_capital_cost = total_ghx_ft * ghp.installed_cost_ghx_per_ft
    else
        @info "Using user provided GHX costs, please validate that this is intentional"
    end

    aux_heater_cost = 0.0
    aux_cooler_cost = 0.0
    if ghp.is_ghx_hybrid
        aux_heater_cost = ghp.aux_heater_installed_cost_per_mmbtu_per_hr*
        response["outputs"]["peak_aux_heater_thermal_production_mmbtu_per_hour"]*
        ghp.aux_unit_capacity_sizing_factor_on_peak_load
        
        aux_cooler_cost = ghp.aux_cooler_installed_cost_per_ton*
        response["outputs"]["peak_aux_cooler_thermal_production_ton"]*
        ghp.aux_unit_capacity_sizing_factor_on_peak_load
    end

    # The DataManager._get_REopt_cost_curve method expects at least a two-point tech_sizes_for_cost_curve to
    #   to use the first value of installed_cost_per_kw as an absolute $ value and
    #   the initial slope is based on the heat pump size (e.g. $/ton) of the cost curve for
    #   building a rebate-based cost curve if there are less-than big_number maximum incentives
    ghp.tech_sizes_for_cost_curve = [0.0, big_number]

    if ghp.heat_pump_configuration == "WSHP"
        # Use this with the cost curve to determine absolute cost
        ghp.heatpump_capacity_ton = heatpump_peak_ton * ghp.heatpump_capacity_sizing_factor_on_peak_load
    elseif ghp.heat_pump_configuration == "WWHP"
        ghp.wwhp_heating_pump_capacity_ton = wwhp_heating_pump_peak_ton * ghp.heatpump_capacity_sizing_factor_on_peak_load
        ghp.wwhp_cooling_pump_capacity_ton = wwhp_cooling_pump_peak_ton * ghp.heatpump_capacity_sizing_factor_on_peak_load
    end

    # Using a separate call to _get_REopt_cost_curve in data_manager for "ghp" (not included in "available_techs")
    #    and then use the value above for heat pump capacity to calculate the final absolute cost for GHP

    if ghp.heat_pump_configuration == "WSHP"
        if !(ghp.heatpump_capacity_ton == 0)
            ghp.installed_cost_per_kw = [0, (ghp.ghx_only_capital_cost + hydronic_loop_cost + aux_cooler_cost + aux_heater_cost) / 
                                            ghp.heatpump_capacity_ton + ghp.installed_cost_heatpump_per_ton]
        else  # For just costing ground heat exchanger for URBANopt
            # Approximate investment-based incentive (ibi) stacking, ignores max incentive for state and utility
            base_cost = ghp.ghx_only_capital_cost + hydronic_loop_cost + aux_cooler_cost + aux_heater_cost
            ibi_net_fraction = (1 - ghp.federal_itc_fraction) * (1 - ghp.state_ibi_fraction) * (1 - ghp.utility_ibi_fraction)
            ghp.installed_cost_per_kw = [base_cost * ibi_net_fraction, 0.0]
        end
    elseif ghp.heat_pump_configuration == "WWHP"
        # Divide by two to avoid double counting non-heatpump costs
        ghp.wwhp_heating_pump_installed_cost_curve = [0, (ghp.ghx_only_capital_cost + aux_cooler_cost + aux_heater_cost) / 2 /
                                                          ghp.wwhp_heating_pump_capacity_ton + ghp.installed_cost_wwhp_heating_pump_per_ton]
        ghp.wwhp_cooling_pump_installed_cost_curve = [0, (ghp.ghx_only_capital_cost + aux_cooler_cost + aux_heater_cost) / 2 /
                                                          ghp.wwhp_cooling_pump_capacity_ton + ghp.installed_cost_wwhp_cooling_pump_per_ton]
    end

end

function setup_om_cost!(ghp::GHP)
    # O&M Cost
    ghp.om_cost_year_one = ghp.building_sqft * ghp.om_cost_per_sqft_year
end

function assign_thermal_factor!(d::Dict, heating_or_cooling::String)
    if heating_or_cooling == "space_heating"
        name = "space_heating_efficiency_thermal_factor"
        if haskey(d, "SpaceHeatingLoad")
            file_path = joinpath(@__DIR__, "..", "..", "data", "ghp", "ghp_space_heating_efficiency_thermal_factors.csv")
            factor_data_df = CSV.read(file_path, DataFrame)
            building_type = get(d["SpaceHeatingLoad"], "doe_reference_name", [])
        else
            building_type = "dummy"
        end
    elseif heating_or_cooling == "cooling"
        name = "cooling_efficiency_thermal_factor"
        if haskey(d, "CoolingLoad")
            file_path = joinpath(@__DIR__, "..", "..", "data", "ghp", "ghp_cooling_efficiency_thermal_factors.csv")
            factor_data_df = CSV.read(file_path, DataFrame)
            building_type = get(d["CoolingLoad"], "doe_reference_name", [])
        else
            building_type = "dummy"
        end
    else
        throw(@error("Specify `space_heating` or `cooling` for assign_thermal_factor! function"))
    end
    latitude = d["Site"]["latitude"]
    longitude = d["Site"]["longitude"]
    nearest_city, climate_zone = find_ashrae_zone_city(latitude, longitude; get_zone=true)
    # Default thermal factors are assigned for certain building types and not for campuses (multiple buildings)
    if !(building_type == "dummy") && building_type in factor_data_df[!, "BuildingType"]
        factor = filter("BuildingType" => ==(building_type), factor_data_df)[1, climate_zone]
    else
        factor = 1.0
    end
    
    # Mutate d to assign GHP efficiency_thermal_factors
    d["GHP"][name] = factor

    # Return this data for informational purposes
    return nearest_city, climate_zone
end
