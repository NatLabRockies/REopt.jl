# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`Wind` is an optional REopt input with the following keys and default values:
```julia
    min_kw = 0.0,
    max_kw = 1.0e9,
    installed_cost_per_kw = nothing,
    om_cost_per_kw = 42.0,
    production_factor_series = nothing, # Optional user-defined production factors. Must be normalized to units of kW-AC/kW-DC nameplate. The series must be one year (January through December) of hourly, 30-minute, or 15-minute generation data.
    size_class = "",
    use_turbine_model_names = false, # Optional boolean to indicate whether to use specific turbine model names for size_class. If true, size_class must be one of the following turbine model names: ["Bergey Excel 15", "Northern Power Systems 100", "Vestas V-47", "GE 1.5 MW", "Bespoke 6 MW 170", "Bespoke 6 MW 196"]. If false, size_class is determined based on average electric load.
    wind_meters_per_sec = [],
    wind_direction_degrees = [],
    temperature_celsius = [],
    pressure_atmospheres = [],
    acres_per_kw = 0.0126, # assuming a power density for the Bespoke 6 MW 170. No size constraint applied to turbines below 1.5 MW capacity.. (not exposed in API)
    macrs_option_years = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, struct_name="Wind"), "macrs_option_years", 5),
    macrs_bonus_fraction = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, struct_name="Wind"), "macrs_bonus_fraction", 1.0),
    macrs_itc_reduction = 0.5,
    federal_itc_fraction = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, struct_name="Wind"), "federal_itc_fraction", 0.3),
    federal_rebate_per_kw = 0.0,
    state_ibi_fraction = 0.0,
    state_ibi_max = 1.0e10,
    state_rebate_per_kw = 0.0,
    state_rebate_max = 1.0e10,
    utility_ibi_fraction = 0.0,
    utility_ibi_max = 1.0e10,
    utility_rebate_per_kw = 0.0,
    utility_rebate_max = 1.0e10,
    production_incentive_per_kwh::Float64 = 0.0 # revenue from production incentive per kWh electricity produced, including curtailment
    production_incentive_max_benefit::Float64 = 1.0e9 # maximum allowable annual revenue from production incentives
    production_incentive_years::Int = 1 # number of year in which production incentives are paid
    production_incentive_max_kw::Float64 = 1.0e9 # maximum allowable system size to receive production incentives
    can_net_meter = true,
    can_wholesale = true,
    can_export_beyond_nem_limit = true,
    can_curtail = true, 
    operating_reserve_required_fraction::Real = off_grid_flag ? 0.50 : 0.0, # Only applicable when `off_grid_flag` is true. Applied to each time_step as a % of wind generation serving load.
```
!!! note "Default assumptions" 
    `size_class` must be one of ["Bergey Excel 15", "Northern Power Systems 100", "Vestas V-47", "GE 1.5 MW", "Bespoke 6 MW 170", "Bespoke 6 MW 196"]. If `size_class` is not provided then it is determined based on the average electric load.

    If no `installed_cost_per_kw` is provided then it is determined from:
    ```julia
    size_class_to_installed_cost = Dict(
        "Bergey Excel 15" => 5000,
        "Northern Power Systems 100" => 4400,
        "Vestas V-47" => 3137.0,
        "GE 1.5 MW" => 3000,
        "Bespoke 6 MW 170" => 2386.0,
        "Bespoke 6 MW 196" => 2000,
    )
    ```
    If the `production_factor_series` is not provided then NREL's System Advisor Model (SAM) is used to get the wind turbine 
    production factor.

!!! note "Wind resource value inputs"
    Wind resource values are optional (i.e., `wind_meters_per_sec`, `wind_direction_degrees`, `temperature_celsius`, and `pressure_atmospheres`).
    If not provided then the resource values are downloaded from NREL's Wind Toolkit.
    These values are passed to SAM to get the turbine production factor.
    
!!! note "Wind sizing and land constraint" 
    Wind size is constrained by Site.land_acres, assuming a power density of Wind.acres_per_kw for turbine sizes above 1.5 MW (default assumption of 30 acres per MW). 
    If the turbine size recommended is smaller than 1.5 MW, the input for land available will not constrain the system size. 
    If the the land available constrains the system size to less than 1.5 MW, the system will be capped at 1.5 MW (i.e., turbines < 1.5 MW are not subject to the acres/kW limit).  

"""
struct Wind <: AbstractTech
    min_kw::Real
    max_kw::Real
    installed_cost_per_kw::Union{Nothing, Real}
    om_cost_per_kw::Real
    production_factor_series::Union{Nothing, Array{Real,1}}
    size_class::String
    use_turbine_model_names::Bool
    hub_height::T where T <: Real
    wind_meters_per_sec::Any
    wind_direction_degrees::Any
    temperature_celsius::Any
    pressure_atmospheres::Any
    acres_per_kw::Real
    macrs_option_years::Int
    macrs_bonus_fraction::Real
    macrs_itc_reduction::Real
    federal_itc_fraction::Real
    federal_rebate_per_kw::Real
    state_ibi_fraction::Real
    state_ibi_max::Real
    state_rebate_per_kw::Real
    state_rebate_max::Real
    utility_ibi_fraction::Real
    utility_ibi_max::Real
    utility_rebate_per_kw::Real
    utility_rebate_max::Real
    production_incentive_per_kwh::Real
    production_incentive_max_benefit::Real
    production_incentive_years::Int
    production_incentive_max_kw::Real
    can_net_meter::Bool
    can_wholesale::Bool
    can_export_beyond_nem_limit::Bool
    can_curtail::Bool
    operating_reserve_required_fraction::Real
    """Still needs to undergo more work"""
    function Wind(;
        off_grid_flag::Bool = false,
        sector::String = "commercial/industrial",
        federal_procurement_type::String = "",
        min_kw = 0.0,
        max_kw = 1.0e9,
        installed_cost_per_kw = nothing,
        om_cost_per_kw = 42.0,
        production_factor_series = nothing,
        size_class::String = "",
        use_turbine_model_names::Bool = false, 
        wind_meters_per_sec = [],
        wind_direction_degrees = [],
        temperature_celsius = [],
        pressure_atmospheres = [],
        acres_per_kw = 0.0126, # assuming a power density for the Bespoke 6 MW 170. No size constraint applied to turbines below 1.5 MW capacity.
        macrs_option_years = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, struct_name="Wind"), "macrs_option_years", 5),
        macrs_bonus_fraction = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, struct_name="Wind"), "macrs_bonus_fraction", 1.0),
        macrs_itc_reduction = 0.5,
        federal_itc_fraction = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, struct_name="Wind"), "federal_itc_fraction", 0.3),
        federal_rebate_per_kw = 0.0,
        state_ibi_fraction = 0.0,
        state_ibi_max = 1.0e10,
        state_rebate_per_kw = 0.0,
        state_rebate_max = 1.0e10,
        utility_ibi_fraction = 0.0,
        utility_ibi_max = 1.0e10,
        utility_rebate_per_kw = 0.0,
        utility_rebate_max = 1.0e10,
        production_incentive_per_kwh = 0.0,
        production_incentive_max_benefit = 1.0e9,
        production_incentive_years = 1,
        production_incentive_max_kw = 1.0e9,
        can_net_meter = off_grid_flag ? false : true,
        can_wholesale = off_grid_flag ? false : true,
        can_export_beyond_nem_limit = off_grid_flag ? false : true,
        can_curtail = off_grid_flag ? false : true,
        average_elec_load = 0.0,
        operating_reserve_required_fraction::Real = off_grid_flag ? 0.50 : 0.0, # Only applicable when `off_grid_flag` is true. Applied to each time_step as a % of wind generation serving load.
        )
        if use_turbine_model_names
            @warn "Using specific turbine model names for `size_class`. Ensure that `size_class` is one of the following turbine model names: [\"Bergey Excel 15\", \"Northern Power Systems 100\", \"Vestas V-47\", \"GE 1.5 MW\", \"Bespoke 6 MW 170\", \"Bespoke 6 MW 196\"]"
            size_class_to_hub_height = Dict(
                "Bergey Excel 15" => 24, #supposed to be 24 but WINDToolkit has increments of 20 m
                "Northern Power Systems 100" => 37, #supposed to be 37 but WINDToolkit has increments of 20 m
                "Vestas V-47" => 60,
                "GE 1.5 MW" => 80,
                "Bespoke 6 MW 170" => 115, #supposed to be 115 but WINDToolkit has increments of 20 m
                "Bespoke 6 MW 196" => 140
            )
            size_class_to_installed_cost = Dict(
                "Bergey Excel 15" => 5000,
                "Northern Power Systems 100" => 4400,
                "Vestas V-47" => 3137.0,
                "GE 1.5 MW" => 3000,
                "Bespoke 6 MW 170" => 2386.0,
                "Bespoke 6 MW 196" => 2000
            )
        else
            size_class_to_hub_height = Dict(
                "residential"=> 20,
                "commercial"=> 40,
                "medium"=> 60,  # Owen Roberts provided 50m for medium size_class, but Wind Toolkit has increments of 20m
                "large"=> 80
            )
            size_class_to_installed_cost = Dict(
                "residential"=> 7692.0,
                "commercial"=> 5776.0,
                "medium"=> 3807.0,
                "large"=> 2896.0
            )
        end
            # Size class selection logic remains similar but references the appropriate dict
        if size_class == ""
            if use_turbine_model_names
                if average_elec_load <= 16
                    size_class = "Bergey Excel 15"
                elseif average_elec_load <= 100
                    size_class = "Northern Power Systems 100"
                elseif average_elec_load <= 660
                    size_class = "Vestas V-47"
                elseif average_elec_load <= 1500
                    size_class = "GE 1.5 MW"
                elseif average_elec_load <= 6000
                    size_class = "Bespoke 6 MW 170"
                else
                    size_class = "Bespoke 6 MW 196"
                end
            else
                if average_elec_load <= 100
                    size_class = "residential"
                elseif average_elec_load <= 660
                    size_class = "commercial"
                elseif average_elec_load <= 6000
                    size_class = "medium"
                else
                    size_class = "large"
                end
            end
        elseif !(size_class in keys(size_class_to_hub_height))
            throw(@error("Wind size_class must be one of $(keys(size_class_to_hub_height))"))
        end

        if isnothing(installed_cost_per_kw)
            installed_cost_per_kw = size_class_to_installed_cost[size_class]
        end

        hub_height = size_class_to_hub_height[size_class]

        if !(off_grid_flag) && !(operating_reserve_required_fraction == 0.0)
            @warn "Wind operating_reserve_required_fraction applies only when `off_grid_flag` is true. Setting operating_reserve_required_fraction to 0.0 for this on-grid analysis."
            operating_reserve_required_fraction = 0.0
        end

        if off_grid_flag && (can_net_meter || can_wholesale || can_export_beyond_nem_limit)
            @warn "Setting Wind can_net_meter, can_wholesale, and can_export_beyond_nem_limit to False because `off_grid_flag` is true."
            can_net_meter = false
            can_wholesale = false
            can_export_beyond_nem_limit = false
        end

        new(
            min_kw,
            max_kw,
            installed_cost_per_kw,
            om_cost_per_kw,
            production_factor_series,
            size_class,
            hub_height,
            wind_meters_per_sec,
            wind_direction_degrees,
            temperature_celsius,
            pressure_atmospheres,
            acres_per_kw,
            macrs_option_years,
            macrs_bonus_fraction,
            macrs_itc_reduction,
            federal_itc_fraction,
            federal_rebate_per_kw,
            state_ibi_fraction,
            state_ibi_max,
            state_rebate_per_kw,
            state_rebate_max,
            utility_ibi_fraction,
            utility_ibi_max,
            utility_rebate_per_kw,
            utility_rebate_max,
            production_incentive_per_kwh,
            production_incentive_max_benefit,
            production_incentive_years,
            production_incentive_max_kw,
            can_net_meter,
            can_wholesale,
            can_export_beyond_nem_limit,
            can_curtail,
            operating_reserve_required_fraction
        )
    end
end