# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`ExistingHydropower` is an optional REopt input with the following keys and default values:
```julia
    existing_kw_per_turbine::Real=0,
    number_of_turbines::Real=0, 
    computation_type::String="average_power_conversion", # "average_power_conversion", "quadratic_partially_discretized", "fixed_efficiency_linearized_reservoir_head", or "quadratic_unsimplified"
    average_cubic_meters_per_second_per_kw::Real=0, # only applied when the computation_type = "average_power_conversion"
    coefficient_a_efficiency::Real=0.0, 
    coefficient_b_efficiency::Real=0.0,
    coefficient_c_efficiency::Real=0.0,
    coefficient_d_reservoir_head::Real=0.0, # coefficient for a quadratic term for the reservoir head equation, which is only applied when the computation_type = "quadratic_unsimplified"
    coefficient_e_reservoir_head::Real=0.0,
    coefficient_f_reservoir_head::Real=0.0, 
    number_of_efficiency_bins::Real=3, # only applied when the computation_type = "quadratic_partially_discretized"
    fixed_turbine_efficiency::Real=0.9, # only applied when the computation_type = "fixed_efficiency_linearized_reservoir_head"
    water_inflow_cubic_meter_per_second::Array=[], # tributary water flowing into the dam's pond
    cubic_meter_maximum::Real=0, #maximum capacity of the dam
    cubic_meter_minimum::Real=0, #minimum water level of the dam
    initial_reservoir_volume::Real=0.0  # The initial volume of water in the reservoir
    minimum_water_output_cubic_meter_per_second_total_of_all_turbines::Real=0,
    minimum_water_output_cubic_meter_per_second_per_turbine::Real=0.0,
    maximum_water_output_cubic_meter_per_second_per_turbine::Real=0.0,
    minimum_operating_time_steps_individual_turbine::Real=0.0, # the minimum time (in time steps) that an invidual turbine must run for (can avoid turning a turbine on for just 15 minute, for instance)
    minimum_operating_time_steps_at_local_maximum_turbine_output::Real=0.0,
    minimum_turbine_off_time_steps::Real=0.0,
    spillway_maximum_cubic_meter_per_second::Real=nothing # maximum water flow that can flow out of the spillway (structure that enables water overflowing from the reservoir to pass over/through the dam)
    hydro_production_factor_series::Union{Nothing, Array{<:Real,1}} = nothing, # Optional user-defined production factors. Must be normalized to units of kW-AC/kW-DC nameplate. The series must be one year (January through December) of hourly, 30-minute, or 15-minute generation data.
    can_net_meter::Bool = off_grid_flag ? false : true,
    can_wholesale::Bool = off_grid_flag ? false : true,
    can_export_beyond_nem_limit::Bool = off_grid_flag ? false : true,
    can_curtail::Bool = true,
    
    # Model a downstream reservoir
    model_downstream_reservoir::Bool=false,
    initial_downstream_reservoir_water_volume::Real=0.0,
    minimum_outflow_from_downstream_reservoir_cubic_meter_per_second::Real=0,
    maximum_outflow_from_downstream_reservoir_cubic_meter_per_second::Real=1000000,
    minimum_downstream_reservoir_volume_cubic_meters::Real=0,
    maximum_downstream_reservoir_volume_cubic_meters::Real=1000000,
    number_of_pumps::Real=0,
    water_pump_average_cubic_meters_per_second_per_kw::Real=0,
    existing_kw_per_pump::Real=0
```
"""

mutable struct ExistingHydropower <: AbstractTech

    existing_kw_per_turbine
    number_of_turbines
    computation_type
    average_cubic_meters_per_second_per_kw
    coefficient_a_efficiency 
    coefficient_b_efficiency
    coefficient_c_efficiency
    coefficient_d_reservoir_head
    coefficient_e_reservoir_head
    coefficient_f_reservoir_head
    number_of_efficiency_bins
    fixed_turbine_efficiency
    water_inflow_cubic_meter_per_second
    cubic_meter_maximum  
    cubic_meter_minimum 
    initial_reservoir_volume 
    minimum_water_output_cubic_meter_per_second_total_of_all_turbines
    minimum_water_output_cubic_meter_per_second_per_turbine
    maximum_water_output_cubic_meter_per_second_per_turbine
    minimum_operating_time_steps_individual_turbine
    minimum_operating_time_steps_at_local_maximum_turbine_output
    minimum_turbine_off_time_steps
    spillway_maximum_cubic_meter_per_second
    hydro_production_factor_series 
    can_net_meter  
    can_wholesale  
    can_export_beyond_nem_limit 
    can_curtail
    model_downstream_reservoir
    initial_downstream_reservoir_water_volume
    minimum_outflow_from_downstream_reservoir_cubic_meter_per_second
    maximum_outflow_from_downstream_reservoir_cubic_meter_per_second
    minimum_downstream_reservoir_volume_cubic_meters
    maximum_downstream_reservoir_volume_cubic_meters
    number_of_pumps
    water_pump_average_cubic_meters_per_second_per_kw
    existing_kw_per_pump

    function ExistingHydropower(;
        existing_kw_per_turbine::Real=0.0,
        number_of_turbines::Real=0,
        computation_type::String="average_power_conversion",
        average_cubic_meters_per_second_per_kw::Real=0.0,
        coefficient_a_efficiency::Real=0.0,
        coefficient_b_efficiency::Real=0.0,
        coefficient_c_efficiency::Real=0.0,
        coefficient_d_reservoir_head::Real=0.0,
        coefficient_e_reservoir_head::Real=0.0,
        coefficient_f_reservoir_head::Real=0.0,
        number_of_efficiency_bins::Real=3,
        fixed_turbine_efficiency::Real=0.9,
        water_inflow_cubic_meter_per_second::Union{Nothing, Array{<:Real,1}} = nothing, # water flowing into the dam's pond
        cubic_meter_maximum::Real=1000000, #maximum capacity of the reservoir
        cubic_meter_minimum::Real=0.0, #minimum water level of the reservoir
        initial_reservoir_volume::Real=500000, # the initial volume of the reservoir
        minimum_water_output_cubic_meter_per_second_total_of_all_turbines::Real=0.0,
        minimum_water_output_cubic_meter_per_second_per_turbine::Real=0.0,
        maximum_water_output_cubic_meter_per_second_per_turbine::Real=0.0,
        minimum_operating_time_steps_individual_turbine::Real=1.0,
        minimum_operating_time_steps_at_local_maximum_turbine_output::Real=0.0, 
        minimum_turbine_off_time_steps::Real=0.0,
        spillway_maximum_cubic_meter_per_second::Real=nothing, 
        hydro_production_factor_series::Union{Nothing, Array{<:Real,1}} = nothing,
        can_net_meter::Bool = false,
        can_wholesale::Bool = false,
        can_export_beyond_nem_limit::Bool = false,
        can_curtail::Bool = true,
        model_downstream_reservoir::Bool=false,
        initial_downstream_reservoir_water_volume::Real=500000,
        minimum_outflow_from_downstream_reservoir_cubic_meter_per_second::Real=0,
        maximum_outflow_from_downstream_reservoir_cubic_meter_per_second::Real=1000000,
        minimum_downstream_reservoir_volume_cubic_meters::Real=0,
        maximum_downstream_reservoir_volume_cubic_meters::Real=1000000,
        number_of_pumps::Real=0,
        water_pump_average_cubic_meters_per_second_per_kw::Real=0,
        existing_kw_per_pump::Real=0
        )
        
        #=
        # TODO: implement off_grid capability for hydropower
        if off_grid_flag && (can_net_meter || can_wholesale || can_export_beyond_nem_limit)
            @warn "Setting Existing Hydropower can_net_meter, can_wholesale, and can_export_beyond_nem_limit to False because `off_grid_flag` is true."
            can_net_meter = false
            can_wholesale = false
            can_export_beyond_nem_limit = false
        end
        =#

        if fixed_turbine_efficiency > 1.0
            throw(@error("The 'fixed_turbine_efficiency' must be less than or equal to 1.0"))
        end
        if minimum_operating_time_steps_individual_turbine < 1
            throw(@error("The 'minimum_operating_time_steps_individual_turbine' must be greater than or equal to 1"))
        end
        if number_of_efficiency_bins > 10
            @warn("Setting the 'number_of_efficiency_bins' to a high value can increase complexity of the optimization problem and reduce solve times")
        end
        if number_of_turbines > 8
            @warn("Setting the 'number_of_turbines' to a high value can increase complexity of the optimization problem and reduce solve times")
        end
        if cubic_meter_maximum < cubic_meter_minimum
            throw(@error("The 'cubic_meter_maximum' must be greater than or equal to the 'cubic_meter_minimum"))
        end
        if initial_reservoir_volume < cubic_meter_minimum || initial_reservoir_volume > cubic_meter_maximum
            throw(@error("The 'initial_reservoir_volume' must be between the 'cubic_meter_minimum' and 'cubic_meter_maximum' "))
        end

        new(
            existing_kw_per_turbine,
            number_of_turbines,
            computation_type,
            average_cubic_meters_per_second_per_kw,
            coefficient_a_efficiency,
            coefficient_b_efficiency,
            coefficient_c_efficiency,
            coefficient_d_reservoir_head,
            coefficient_e_reservoir_head,
            coefficient_f_reservoir_head,
            number_of_efficiency_bins,
            fixed_turbine_efficiency,
            water_inflow_cubic_meter_per_second,
            cubic_meter_maximum,
            cubic_meter_minimum,
            initial_reservoir_volume,
            minimum_water_output_cubic_meter_per_second_total_of_all_turbines,
            minimum_water_output_cubic_meter_per_second_per_turbine,
            maximum_water_output_cubic_meter_per_second_per_turbine,
            minimum_operating_time_steps_individual_turbine,
            minimum_operating_time_steps_at_local_maximum_turbine_output,
            minimum_turbine_off_time_steps,
            spillway_maximum_cubic_meter_per_second,
            hydro_production_factor_series,
            can_net_meter,
            can_wholesale,
            can_export_beyond_nem_limit,
            can_curtail,

            model_downstream_reservoir,
            initial_downstream_reservoir_water_volume,
            minimum_outflow_from_downstream_reservoir_cubic_meter_per_second,
            maximum_outflow_from_downstream_reservoir_cubic_meter_per_second,
            minimum_downstream_reservoir_volume_cubic_meters,
            maximum_downstream_reservoir_volume_cubic_meters,
            number_of_pumps,
            water_pump_average_cubic_meters_per_second_per_kw,
            existing_kw_per_pump
        )
    end
end

