# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`WaterPower` is an optional REopt input with the following keys and default values:
```julia
    
    # Define turbine information
    number_of_turbines::Real=0, 
    turbine_cost_per_kw::Real=5000.0,
    max_kw_turbine::Real=10000000,
    min_kw_turbine::Real=0,
    existing_kw_per_turbine::Real=nothing,
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
    minimum_water_output_cubic_meter_per_second_total_of_all_turbines::Real=0,
    minimum_water_output_cubic_meter_per_second_per_turbine::Real=0.0,
    maximum_water_output_cubic_meter_per_second_per_turbine::Real=0.0,
    minimum_operating_time_steps_individual_turbine::Real=0.0, # the minimum time (in time steps) that an invidual turbine must run for (can avoid turning a turbine on for just 15 minute, for instance)
    minimum_operating_time_steps_at_local_maximum_turbine_output::Real=0.0,
    minimum_turbine_off_time_steps::Real=0.0,

    # Define the pump information
    number_of_pumps::Real=0,
    max_kw_pump::Real=10000000,
    min_kw_pump::Real=0,
    pump_cost_per_kw::Real=5000.0,
    water_pump_average_cubic_meters_per_second_per_kw::Real=0,
    existing_kw_per_pump::Real=0,
    are_pumps_reversible::Bool=false,  # If set to true, then establishes a fixed ratio of maximum power to pumps and turbines
    pump_kw_to_turbine_kw_ratio_for_reversible_pumps::Real=1.0, # Define the maximum power ratio of the pumps to the turbines, if reversible pumps are being modeled
    minimum_water_flow_cubic_meter_per_second_per_pump::Real=0,
    maximum_water_flow_cubic_meter_per_second_per_pump::Real=1000000,

    # Inputs for the upper reservoir
    water_inflow_cubic_meter_per_second::Array=[], # tributary water flowing into the dam's pond
    cubic_meter_maximum::Real=0, #maximum capacity of the dam
    cubic_meter_minimum::Real=0, #minimum water level of the dam
    initial_reservoir_volume::Real=0.0,  # The initial volume of water in the reservoir
    
    # Inputs for a downstream reservoir
    model_downstream_reservoir::Bool=false,
    initial_downstream_reservoir_water_volume::Real=0.0,
    minimum_outflow_from_downstream_reservoir_cubic_meter_per_second::Real=0,
    maximum_outflow_from_downstream_reservoir_cubic_meter_per_second::Real=1000000,
    minimum_downstream_reservoir_volume_cubic_meters::Real=0,
    maximum_downstream_reservoir_volume_cubic_meters::Real=1000000,
    
    # Additional inputs
    spillway_maximum_cubic_meter_per_second::Real=nothing # maximum water flow that can flow out of the spillway (structure that enables water overflowing from the reservoir to pass over/through the dam)
    hydro_production_factor_series::Union{Nothing, Array{<:Real,1}} = nothing, # Optional user-defined production factors. Must be normalized to units of kW-AC/kW-DC nameplate. The series must be one year (January through December) of hourly, 30-minute, or 15-minute generation data.
    can_net_meter::Bool = off_grid_flag ? false : true,
    can_wholesale::Bool = off_grid_flag ? false : true,
    can_export_beyond_nem_limit::Bool = off_grid_flag ? false : true,
    can_curtail::Bool = true,

    om_cost_per_kw_turbine::Real=0,
    om_cost_per_kw_pump::Real=0

```
"""

mutable struct WaterPower <: AbstractTech
    number_of_turbines
    turbine_cost_per_kw
    max_kw_turbine
    min_kw_turbine
    existing_kw_per_turbine
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
    minimum_water_output_cubic_meter_per_second_total_of_all_turbines
    minimum_water_output_cubic_meter_per_second_per_turbine
    maximum_water_output_cubic_meter_per_second_per_turbine
    minimum_operating_time_steps_individual_turbine
    minimum_operating_time_steps_at_local_maximum_turbine_output
    minimum_turbine_off_time_steps
    number_of_pumps
    max_kw_pump
    min_kw_pump
    pump_cost_per_kw
    water_pump_average_cubic_meters_per_second_per_kw
    existing_kw_per_pump
    are_pumps_reversible
    pump_kw_to_turbine_kw_ratio_for_reversible_pumps
    minimum_water_flow_cubic_meter_per_second_per_pump
    maximum_water_flow_cubic_meter_per_second_per_pump
    water_inflow_cubic_meter_per_second
    cubic_meter_maximum  
    cubic_meter_minimum 
    initial_reservoir_volume 
    model_downstream_reservoir
    initial_downstream_reservoir_water_volume
    minimum_outflow_from_downstream_reservoir_cubic_meter_per_second
    maximum_outflow_from_downstream_reservoir_cubic_meter_per_second
    minimum_downstream_reservoir_volume_cubic_meters
    maximum_downstream_reservoir_volume_cubic_meters
    spillway_maximum_cubic_meter_per_second
    hydro_production_factor_series 
    can_net_meter  
    can_wholesale  
    can_export_beyond_nem_limit 
    can_curtail
    om_cost_per_kw_turbine
    om_cost_per_kw_pump

    function WaterPower(;
        number_of_turbines::Real=0, 
        turbine_cost_per_kw::Real=5000.0,
        max_kw_turbine::Real=10000000,
        min_kw_turbine::Real=0,
        existing_kw_per_turbine::Real=nothing,
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
        minimum_water_output_cubic_meter_per_second_total_of_all_turbines::Real=0,
        minimum_water_output_cubic_meter_per_second_per_turbine::Real=0.0,
        maximum_water_output_cubic_meter_per_second_per_turbine::Real=0.0,
        minimum_operating_time_steps_individual_turbine::Real=0.0, # the minimum time (in time steps) that an invidual turbine must run for (can avoid turning a turbine on for just 15 minute, for instance)
        minimum_operating_time_steps_at_local_maximum_turbine_output::Real=0.0,
        minimum_turbine_off_time_steps::Real=0.0,
        number_of_pumps::Real=0,
        max_kw_pump::Real=10000000,
        min_kw_pump::Real=0,
        pump_cost_per_kw::Real=5000.0,
        water_pump_average_cubic_meters_per_second_per_kw::Real=0,
        existing_kw_per_pump::Real=0,
        are_pumps_reversible::Bool=false,  # If set to true, then establishes a fixed ratio of maximum power to pumps and turbines
        pump_kw_to_turbine_kw_ratio_for_reversible_pumps::Real=1.0, # Define the maximum power ratio of the pumps to the turbines, if reversible pumps are being modeled
        minimum_water_flow_cubic_meter_per_second_per_pump::Real=0,
        maximum_water_flow_cubic_meter_per_second_per_pump::Real=1000000,
        water_inflow_cubic_meter_per_second::Array=[], # tributary water flowing into the dam's pond
        cubic_meter_maximum::Real=0, #maximum capacity of the dam
        cubic_meter_minimum::Real=0, #minimum water level of the dam
        initial_reservoir_volume::Real=0.0,  # The initial volume of water in the reservoir
        model_downstream_reservoir::Bool=false,
        initial_downstream_reservoir_water_volume::Real=0.0,
        minimum_outflow_from_downstream_reservoir_cubic_meter_per_second::Real=0,
        maximum_outflow_from_downstream_reservoir_cubic_meter_per_second::Real=1000000,
        minimum_downstream_reservoir_volume_cubic_meters::Real=0,
        maximum_downstream_reservoir_volume_cubic_meters::Real=1000000,
        spillway_maximum_cubic_meter_per_second::Real=nothing, # maximum water flow that can flow out of the spillway (structure that enables water overflowing from the reservoir to pass over/through the dam)
        hydro_production_factor_series::Union{Nothing, Array{<:Real,1}} = nothing, # Optional user-defined production factors. Must be normalized to units of kW-AC/kW-DC nameplate. The series must be one year (January through December) of hourly, 30-minute, or 15-minute generation data.
        can_net_meter::Bool = off_grid_flag ? false : true,
        can_wholesale::Bool = off_grid_flag ? false : true,
        can_export_beyond_nem_limit::Bool = off_grid_flag ? false : true,
        can_curtail::Bool = true,
        om_cost_per_kw_turbine::Real=0,
        om_cost_per_kw_pump::Real=0
        )
        
        #=
        # TODO: implement off_grid capability for water_power
        if off_grid_flag && (can_net_meter || can_wholesale || can_export_beyond_nem_limit)
            @warn "Setting Existing WaterPower can_net_meter, can_wholesale, and can_export_beyond_nem_limit to False because `off_grid_flag` is true."
            can_net_meter = false
            can_wholesale = false
            can_export_beyond_nem_limit = false
        end
        =#

        # Check the inputs for errors:
        if fixed_turbine_efficiency > 1.0
            throw(@error("The 'fixed_turbine_efficiency' must be less than or equal to 1.0"))
        end
        if minimum_operating_time_steps_individual_turbine < 1
            throw(@error("The 'minimum_operating_time_steps_individual_turbine' must be greater than or equal to 1"))
        end
        if are_pumps_reversible && (number_of_pumps != number_of_turbines)
            throw(@error("If the pumps are reversible, then the number_of_pumps must be equal to the number_of_turbines"))
        end
        if are_pumps_reversible 
            if (existing_kw_per_turbine != nothing) && (existing_kw_per_pump == nothing)
                throw(@error("If the pumps are reversible, then existing_kw_per_pump and existing_kw_per_turbine should both be nothing or both be defined"))
            elseif (existing_kw_per_turbine != nothing) && (existing_kw_per_pump == nothing)
                throw(@error("If the pumps are reversible, then existing_kw_per_pump and existing_kw_per_turbine should both be nothing or both be defined"))
            end
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
            number_of_turbines,
            turbine_cost_per_kw,
            max_kw_turbine,
            min_kw_turbine,
            existing_kw_per_turbine,
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
            
            minimum_water_output_cubic_meter_per_second_total_of_all_turbines,
            minimum_water_output_cubic_meter_per_second_per_turbine,
            maximum_water_output_cubic_meter_per_second_per_turbine,
            minimum_operating_time_steps_individual_turbine,
            minimum_operating_time_steps_at_local_maximum_turbine_output,
            minimum_turbine_off_time_steps,

            number_of_pumps,
            max_kw_pump,
            min_kw_pump,
            pump_cost_per_kw,
            water_pump_average_cubic_meters_per_second_per_kw,
            existing_kw_per_pump,
            are_pumps_reversible,
            pump_kw_to_turbine_kw_ratio_for_reversible_pumps,
            minimum_water_flow_cubic_meter_per_second_per_pump,
            maximum_water_flow_cubic_meter_per_second_per_pump,

            water_inflow_cubic_meter_per_second,
            cubic_meter_maximum,
            cubic_meter_minimum,
            initial_reservoir_volume,

            model_downstream_reservoir,
            initial_downstream_reservoir_water_volume,
            minimum_outflow_from_downstream_reservoir_cubic_meter_per_second,
            maximum_outflow_from_downstream_reservoir_cubic_meter_per_second,
            minimum_downstream_reservoir_volume_cubic_meters,
            maximum_downstream_reservoir_volume_cubic_meters,

            spillway_maximum_cubic_meter_per_second,
            hydro_production_factor_series,
            can_net_meter,
            can_wholesale,
            can_export_beyond_nem_limit,
            can_curtail,
            om_cost_per_kw_turbine,
            om_cost_per_kw_pump
        )
    end
end

