# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`WaterPower` is an optional REopt input with the following keys and default values:
```julia
    
    # Define turbine information
    number_of_turbines::Real=0, 
    turbine_cost_per_kw::Real=5000.0,
    turbine_max_kw::Real=10000000,
    turbine_min_kw::Real=0,
    turbine_head_meters::Real=500,
    turbine_head_loss_meters::Real=20
    water_power_mathematical_representation::String="average_efficiency", # This input defines which mathematical representation is used for the water power system. The options are: "average_efficiency" (which assumes a fixed conversion factor between the water flow and the electric power)
    turbine_average_efficiency_fraction::Real=0.9, # only applied when the water_power_mathematical_representation = "average_efficiency"   
    minimum_water_flow_total_of_all_turbines_and_spillway_cubic_meters_per_second::Real=0,
    minimum_water_flow_per_turbine_cubic_meters_per_second::Real=0.0,
    maximum_water_flow_per_turbine_cubic_meters_per_second::Real=50.0,
    minimum_operating_time_steps_during_each_on_cycle_individual_turbine::Real=1.0, # the minimum time (in time steps) that an invidual turbine must run for (can avoid turning a turbine on for just 15 minute, for instance)
    minimum_operating_time_steps_during_each_on_cycle_peak_individual_turbine_output::Real=0.0,
    minimum_turbine_off_time_steps_during_each_off_cycle_individual_turbine::Real=0.0,
    turbine_om_cost_per_kw::Real=0,
    turbine_total_rebate_per_kw::Real=0,

    # Define the pump information
    number_of_pumps::Real=0,
    pump_max_kw::Real=10000000,
    pump_min_kw::Real=0,
    pump_cost_per_kw::Real=5000.0,
    pump_head_meters::Real=500,
    pump_head_loss_meters::Real=20,
    pump_average_efficiency_fraction::Real=0.9, # only applied when the water_power_mathematical_representation = "average_efficiency"   
    pump_om_cost_per_kw::Real=0,
    are_pumps_reversible::Bool=false,  # If set to true, then establishes a fixed ratio of maximum power to pumps and turbines
    pump_kw_to_turbine_kw_ratio_for_reversible_pumps::Real=1.0, # Define the maximum power ratio of the pumps to the turbines, if reversible pumps are being modeled
    minimum_water_flow_cubic_meters_per_second_per_pump::Real=0,
    maximum_water_flow_cubic_meters_per_second_per_pump::Real=1000000,
    minimum_operating_time_steps_during_each_on_cycle_individual_pump::Real=1,
    pump_total_rebate_per_kw::Real=0,
    
    # Additional inputs
    spillway_maximum_flow_cubic_meters_per_second::Union{Nothing,Real}=nothing, # maximum water flow that can flow out of the spillway (structure that enables water overflowing from the reservoir to pass over/through the dam)
    can_net_meter::Bool = off_grid_flag ? false : true,
    can_wholesale::Bool = off_grid_flag ? false : true,
    can_export_beyond_nem_limit::Bool = off_grid_flag ? false : true,
    can_curtail::Bool = true,
    macrs_option_years::Real=0,
    macrs_bonus_fraction::Real=0,
    macrs_itc_reduction::Real=0,
    total_itc_fraction::Real=0,

```
"""

Base.@kwdef struct WaterPowerDefaults <: AbstractWaterPowerDefaults
   # Define turbine information
    number_of_turbines::Real=0
    turbine_cost_per_kw::Real=5000.0
    turbine_max_kw::Real=10000000
    turbine_min_kw::Real=0
    turbine_head_meters::Real=500
    turbine_head_loss_meters::Real=20
    water_power_mathematical_representation::String="average_efficiency"
    turbine_average_efficiency_fraction::Real=0.9
    minimum_water_flow_total_of_all_turbines_and_spillway_cubic_meters_per_second::Real=0
    minimum_water_flow_per_turbine_cubic_meters_per_second::Real=0.0
    maximum_water_flow_per_turbine_cubic_meters_per_second::Real=50.0
    minimum_operating_time_steps_during_each_on_cycle_individual_turbine::Real=1.0
    minimum_operating_time_steps_during_each_on_cycle_peak_individual_turbine_output::Real=0.0
    minimum_turbine_off_time_steps_during_each_off_cycle_individual_turbine::Real=0.0
    turbine_om_cost_per_kw::Real=0
    turbine_total_rebate_per_kw::Real=0

    # Define the pump information
    number_of_pumps::Real=0
    pump_max_kw::Real=10000000
    pump_min_kw::Real=0
    pump_cost_per_kw::Real=5000.0
    pump_head_meters::Real=500
    pump_head_loss_meters::Real=20
    pump_average_efficiency_fraction::Real=0.9
    pump_om_cost_per_kw::Real=0
    are_pumps_reversible::Bool=false
    pump_kw_to_turbine_kw_ratio_for_reversible_pumps::Real=1.0
    minimum_water_flow_cubic_meters_per_second_per_pump::Real=0
    maximum_water_flow_cubic_meters_per_second_per_pump::Real=1000000
    minimum_operating_time_steps_during_each_on_cycle_individual_pump::Real=1
    pump_total_rebate_per_kw::Real=0

    # Additional inputs
    spillway_maximum_flow_cubic_meters_per_second::Union{Nothing,Real}=nothing
    can_net_meter::Bool = off_grid_flag ? false : true
    can_wholesale::Bool = off_grid_flag ? false : true
    can_export_beyond_nem_limit::Bool = off_grid_flag ? false : true
    can_curtail::Bool = true
    macrs_option_years::Real=0
    macrs_bonus_fraction::Real=0
    macrs_itc_reduction::Real=0
    total_itc_fraction::Real=0

end

"""
function WaterPower(d::Dict, f::Financial, s::Site, settings::Settings)

Construct WaterPower struct from Dict with keys-val pairs from the 
REopt WaterPower and Financial inputs. 
"""

mutable struct WaterPower <: AbstractWaterPower
    number_of_turbines
    turbine_cost_per_kw
    turbine_max_kw
    turbine_min_kw
    turbine_head_meters
    turbine_head_loss_meters
    water_power_mathematical_representation
    turbine_average_efficiency_fraction
    minimum_water_flow_total_of_all_turbines_and_spillway_cubic_meters_per_second
    minimum_water_flow_per_turbine_cubic_meters_per_second
    maximum_water_flow_per_turbine_cubic_meters_per_second
    minimum_operating_time_steps_during_each_on_cycle_individual_turbine
    minimum_operating_time_steps_during_each_on_cycle_peak_individual_turbine_output
    minimum_turbine_off_time_steps_during_each_off_cycle_individual_turbine
    turbine_om_cost_per_kw
    turbine_total_rebate_per_kw
    
    number_of_pumps
    pump_max_kw
    pump_min_kw
    pump_cost_per_kw
    pump_head_meters
    pump_head_loss_meters
    pump_average_efficiency_fraction
    pump_om_cost_per_kw
    are_pumps_reversible
    pump_kw_to_turbine_kw_ratio_for_reversible_pumps
    minimum_water_flow_cubic_meters_per_second_per_pump
    maximum_water_flow_cubic_meters_per_second_per_pump
    minimum_operating_time_steps_during_each_on_cycle_individual_pump
    pump_total_rebate_per_kw
    
    spillway_maximum_flow_cubic_meters_per_second
    can_net_meter  
    can_wholesale  
    can_export_beyond_nem_limit 
    can_curtail
    macrs_option_years
    macrs_bonus_fraction
    macrs_itc_reduction
    total_itc_fraction

    function WaterPower(d::Dict, f::Financial, s::Site, settings::Settings)
        # TODO: update the struct_name for the sector-specific defaults
        set_sector_defaults!(d; struct_name="WaterPower", sector=s.sector, federal_procurement_type=s.federal_procurement_type)
        water_power = WaterPowerDefaults(; d...)
        
        # Input validation
        macrs_schedule = [0.0]
        if water_power.macrs_option_years == 5 || water_power.macrs_option_years == 7
            macrs_schedule = water_power.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year
        elseif !(water_power.macrs_option_years == 0)
            throw(@error("WaterPower macrs_option_years must be 0, 5, or 7."))
        end

        if settings.off_grid_flag
            throw(@error("Water power cannot currently be modeled in off grid models."))
        end
        
        if water_power.minimum_operating_time_steps_during_each_on_cycle_individual_turbine < 1
            throw(@error("The 'minimum_operating_time_steps_during_each_on_cycle_individual_turbine' must be greater than or equal to 1"))
        end

        if water_power.are_pumps_reversible && (water_power.number_of_pumps != water_power.number_of_turbines)
            throw(@error("If the pumps are reversible, then the number_of_pumps must be equal to the number_of_turbines"))
        end
       
        if water_power.number_of_turbines > 8
            @warn("Setting the 'number_of_turbines' to a high value can increase complexity of the optimization problem and reduce solve times")
        end

        if !(water_power.water_power_mathematical_representation in ["average_efficiency"])
			error("An invalid water_power_mathematical_representation input was provided")
        end

        #=
        if off_grid_flag && (can_net_meter || can_wholesale || can_export_beyond_nem_limit)
            @warn "Setting Existing WaterPower can_net_meter, can_wholesale, and can_export_beyond_nem_limit to False because `off_grid_flag` is true."
            can_net_meter = false
            can_wholesale = false
            can_export_beyond_nem_limit = false
        end
        =#

        return new(
            water_power.number_of_turbines,
            water_power.turbine_cost_per_kw,
            water_power.turbine_max_kw,
            water_power.turbine_min_kw,
            water_power.turbine_head_meters,
            water_power.turbine_head_loss_meters,
            water_power.water_power_mathematical_representation,
            water_power.turbine_average_efficiency_fraction,
            water_power.minimum_water_flow_total_of_all_turbines_and_spillway_cubic_meters_per_second,
            water_power.minimum_water_flow_per_turbine_cubic_meters_per_second,
            water_power.maximum_water_flow_per_turbine_cubic_meters_per_second,
            water_power.minimum_operating_time_steps_during_each_on_cycle_individual_turbine,
            water_power.minimum_operating_time_steps_during_each_on_cycle_peak_individual_turbine_output,
            water_power.minimum_turbine_off_time_steps_during_each_off_cycle_individual_turbine,
            water_power.turbine_om_cost_per_kw,
            water_power.turbine_total_rebate_per_kw,

            water_power.number_of_pumps,
            water_power.pump_max_kw,
            water_power.pump_min_kw,
            water_power.pump_cost_per_kw,
            water_power.pump_head_meters,
            water_power.pump_head_loss_meters,
            water_power.pump_average_efficiency_fraction,
            water_power.pump_om_cost_per_kw,
            water_power.are_pumps_reversible,
            water_power.pump_kw_to_turbine_kw_ratio_for_reversible_pumps,
            water_power.minimum_water_flow_cubic_meters_per_second_per_pump,
            water_power.maximum_water_flow_cubic_meters_per_second_per_pump,
            water_power.minimum_operating_time_steps_during_each_on_cycle_individual_pump,
            water_power.pump_total_rebate_per_kw,
            
            water_power.spillway_maximum_flow_cubic_meters_per_second,
            water_power.can_net_meter,
            water_power.can_wholesale,
            water_power.can_export_beyond_nem_limit,
            water_power.can_curtail,            
            water_power.macrs_option_years,
            water_power.macrs_bonus_fraction,
            water_power.macrs_itc_reduction,
            water_power.total_itc_fraction
            
        )
    end
end

