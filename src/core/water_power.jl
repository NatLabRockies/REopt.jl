# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`WaterPower` is an optional REopt input with the following keys and default values:
```julia
    
    # Define turbine information
    number_of_turbines::Real=0, 
    turbine_cost_per_kw::Real=5000.0,
    max_kw_turbine::Real=10000000,
    min_kw_turbine::Real=0,
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
   
    are_pumps_reversible::Bool=false,  # If set to true, then establishes a fixed ratio of maximum power to pumps and turbines
    pump_kw_to_turbine_kw_ratio_for_reversible_pumps::Real=1.0, # Define the maximum power ratio of the pumps to the turbines, if reversible pumps are being modeled
    minimum_water_flow_cubic_meter_per_second_per_pump::Real=0,
    maximum_water_flow_cubic_meter_per_second_per_pump::Real=1000000,
    minimum_operating_time_steps_individual_pump::Real=1,
 
    # Additional inputs
    spillway_maximum_cubic_meter_per_second::Real=nothing, # maximum water flow that can flow out of the spillway (structure that enables water overflowing from the reservoir to pass over/through the dam)
    hydro_production_factor_series::Union{Nothing, Array{<:Real,1}} = nothing, # Optional user-defined production factors. Must be normalized to units of kW-AC/kW-DC nameplate. The series must be one year (January through December) of hourly, 30-minute, or 15-minute generation data.
    can_net_meter::Bool = off_grid_flag ? false : true,
    can_wholesale::Bool = off_grid_flag ? false : true,
    can_export_beyond_nem_limit::Bool = off_grid_flag ? false : true,
    can_curtail::Bool = true,

    om_cost_per_kw_turbine::Real=0,
    om_cost_per_kw_pump::Real=0,
    total_rebate_per_kw_pump::Real=0,
    total_rebate_per_kw_turbine::Real=0,
    macrs_option_years::Real=0,
    macrs_bonus_fraction::Real=0,
    macrs_itc_reduction::Real=0,
    total_itc_fraction::Real=0

```
"""

Base.@kwdef struct WaterPowerDefaults <: AbstractWaterPowerDefaults
   # Define turbine information
    number_of_turbines::Real=0
    turbine_cost_per_kw::Real=5000.0
    max_kw_turbine::Real=10000000
    min_kw_turbine::Real=0
    
    computation_type::String="average_power_conversion"
    average_cubic_meters_per_second_per_kw::Real=0
    coefficient_a_efficiency::Real=0.0
    coefficient_b_efficiency::Real=0.0
    coefficient_c_efficiency::Real=0.0
    coefficient_d_reservoir_head::Real=0.0
    coefficient_e_reservoir_head::Real=0.0
    coefficient_f_reservoir_head::Real=0.0
    number_of_efficiency_bins::Real=3
    fixed_turbine_efficiency::Real=0.9
    minimum_water_output_cubic_meter_per_second_total_of_all_turbines::Real=0
    minimum_water_output_cubic_meter_per_second_per_turbine::Real=0.0
    maximum_water_output_cubic_meter_per_second_per_turbine::Real=0.0
    minimum_operating_time_steps_individual_turbine::Real=0.0
    minimum_operating_time_steps_at_local_maximum_turbine_output::Real=0.0
    minimum_turbine_off_time_steps::Real=0.0

    # Define the pump information
    number_of_pumps::Real=0
    max_kw_pump::Real=10000000
    min_kw_pump::Real=0
    pump_cost_per_kw::Real=5000.0
    water_pump_average_cubic_meters_per_second_per_kw::Real=0
    
    are_pumps_reversible::Bool=false
    pump_kw_to_turbine_kw_ratio_for_reversible_pumps::Real=1.0
    minimum_water_flow_cubic_meter_per_second_per_pump::Real=0
    maximum_water_flow_cubic_meter_per_second_per_pump::Real=1000000
    minimum_operating_time_steps_individual_pump::Real=1

    # Additional inputs
    spillway_maximum_cubic_meter_per_second::Real=nothing
    hydro_production_factor_series::Union{Nothing, Array{<:Real,1}} = nothing
    can_net_meter::Bool = off_grid_flag ? false : true
    can_wholesale::Bool = off_grid_flag ? false : true
    can_export_beyond_nem_limit::Bool = off_grid_flag ? false : true
    can_curtail::Bool = true

    om_cost_per_kw_turbine::Real=0
    om_cost_per_kw_pump::Real=0
    total_rebate_per_kw_pump::Real=0
    total_rebate_per_kw_turbine::Real=0
    macrs_option_years::Real=0
    macrs_bonus_fraction::Real=0
    macrs_itc_reduction::Real=0
    total_itc_fraction::Real=0
    
end

"""
function WaterPower(d::Dict, f::Financial, s::Site, time_steps_per_hour::Int)

Construct WaterPower struct from Dict with keys-val pairs from the 
REopt WaterPower and Financial inputs. 
"""

mutable struct WaterPower <: AbstractWaterPower
    number_of_turbines
    turbine_cost_per_kw
    max_kw_turbine
    min_kw_turbine
    
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
    
    are_pumps_reversible
    pump_kw_to_turbine_kw_ratio_for_reversible_pumps
    minimum_water_flow_cubic_meter_per_second_per_pump
    maximum_water_flow_cubic_meter_per_second_per_pump
    minimum_operating_time_steps_individual_pump
    spillway_maximum_cubic_meter_per_second
    hydro_production_factor_series 
    can_net_meter  
    can_wholesale  
    can_export_beyond_nem_limit 
    can_curtail
    om_cost_per_kw_turbine
    om_cost_per_kw_pump
    total_rebate_per_kw_pump
    total_rebate_per_kw_turbine
    macrs_option_years
    macrs_bonus_fraction
    macrs_itc_reduction
    total_itc_fraction
    net_present_cost_per_kw_turbine
    net_present_cost_per_kw_pump

    function WaterPower(d::Dict, f::Financial, s::Site, time_steps_per_hour::Int)
        # TODO: update the struct_name for the sector-specific defaults
        set_sector_defaults!(d; struct_name="Storage", sector=s.sector, federal_procurement_type=s.federal_procurement_type)
        stor = WaterPowerDefaults(; d...)
        
        macrs_schedule = [0.0]
        if stor.macrs_option_years == 5 || stor.macrs_option_years == 7
            macrs_schedule = stor.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year
        elseif !(stor.macrs_option_years == 0)
            throw(@error("ColdThermalStorage macrs_option_years must be 0, 5, or 7."))
        end

        # TODO: implement off_grid capability for water_power
        #=
        if off_grid_flag && (can_net_meter || can_wholesale || can_export_beyond_nem_limit)
            @warn "Setting Existing WaterPower can_net_meter, can_wholesale, and can_export_beyond_nem_limit to False because `off_grid_flag` is true."
            can_net_meter = false
            can_wholesale = false
            can_export_beyond_nem_limit = false
        end
        =#
        net_present_cost_per_kw_pump = effective_cost(;
            itc_basis = stor.pump_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = stor.total_itc_fraction,
            macrs_schedule = macrs_schedule,
            macrs_bonus_fraction = stor.macrs_bonus_fraction,
            macrs_itc_reduction = stor.macrs_itc_reduction
        ) - stor.total_rebate_per_kw_pump

        net_present_cost_per_kw_turbine = effective_cost(;
            itc_basis = stor.turbine_cost_per_kw,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = stor.total_itc_fraction,
            macrs_schedule = macrs_schedule,
            macrs_bonus_fraction = stor.macrs_bonus_fraction,
            macrs_itc_reduction = stor.macrs_itc_reduction
        ) - stor.total_rebate_per_kw_turbine

        # Check the inputs for errors:
        if stor.fixed_turbine_efficiency > 1.0
            throw(@error("The 'fixed_turbine_efficiency' must be less than or equal to 1.0"))
        end
        if stor.minimum_operating_time_steps_individual_turbine < 1
            throw(@error("The 'minimum_operating_time_steps_individual_turbine' must be greater than or equal to 1"))
        end
        if stor.are_pumps_reversible && (stor.number_of_pumps != stor.number_of_turbines)
            throw(@error("If the pumps are reversible, then the number_of_pumps must be equal to the number_of_turbines"))
        end
       
        if stor.number_of_efficiency_bins > 10
            @warn("Setting the 'number_of_efficiency_bins' to a high value can increase complexity of the optimization problem and reduce solve times")
        end
        if stor.number_of_turbines > 8
            @warn("Setting the 'number_of_turbines' to a high value can increase complexity of the optimization problem and reduce solve times")
        end

        return new(
            stor.number_of_turbines,
            stor.turbine_cost_per_kw,
            stor.max_kw_turbine,
            stor.min_kw_turbine,
            stor.computation_type,
            stor.average_cubic_meters_per_second_per_kw,
            stor.coefficient_a_efficiency,
            stor.coefficient_b_efficiency,
            stor.coefficient_c_efficiency,
            stor.coefficient_d_reservoir_head,
            stor.coefficient_e_reservoir_head,
            stor.coefficient_f_reservoir_head,
            stor.number_of_efficiency_bins,
            stor.fixed_turbine_efficiency,
            stor.minimum_water_output_cubic_meter_per_second_total_of_all_turbines,
            stor.minimum_water_output_cubic_meter_per_second_per_turbine,
            stor.maximum_water_output_cubic_meter_per_second_per_turbine,
            stor.minimum_operating_time_steps_individual_turbine,
            stor.minimum_operating_time_steps_at_local_maximum_turbine_output,
            stor.minimum_turbine_off_time_steps,
            stor.number_of_pumps,
            stor.max_kw_pump,
            stor.min_kw_pump,
            stor.pump_cost_per_kw,
            stor.water_pump_average_cubic_meters_per_second_per_kw,
            stor.are_pumps_reversible,
            stor.pump_kw_to_turbine_kw_ratio_for_reversible_pumps,
            stor.minimum_water_flow_cubic_meter_per_second_per_pump,
            stor.maximum_water_flow_cubic_meter_per_second_per_pump,
            stor.minimum_operating_time_steps_individual_pump,
            stor.spillway_maximum_cubic_meter_per_second,
            stor.hydro_production_factor_series,
            stor.can_net_meter,
            stor.can_wholesale,
            stor.can_export_beyond_nem_limit,
            stor.can_curtail,
            stor.om_cost_per_kw_turbine,
            stor.om_cost_per_kw_pump,
            stor.total_rebate_per_kw_pump,
            stor.total_rebate_per_kw_turbine,
            stor.macrs_option_years,
            stor.macrs_bonus_fraction,
            stor.macrs_itc_reduction,
            stor.total_itc_fraction,
            net_present_cost_per_kw_turbine,
            net_present_cost_per_kw_pump
        )
    end
end

