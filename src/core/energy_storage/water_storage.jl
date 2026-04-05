# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.


"""
Upper reservoir water storage sytem

`UpperReservoirStorage` is an optional REopt input with the following keys and default values:

```julia
    tributary_water_inflow_cubic_meter_per_second::Array=[]
    minimum_volume_fraction_upper_reservoir::Float64 = 0.1
    maximum_volume_fraction_upper_reservoir::Float64 = 1.0
    initial_reservoir_volume_fraction_upper_reservoir::Float64 = 0.0
    minimum_capacity_cubic_meters_upper_reservoir::Float64 = 0.0
    maximum_capacity_cubic_meters_upper_reservoir::Float64 = 10000000.0
    cost_per_cubic_meter_upper_reservoir::Float64 = 25.0
    om_cost_per_cubic_meter::Float64 = 0.0 # Yearly fixed O&M cost dependent on storage energy size
    macrs_option_years::Int = 5 #Note: default may change if Site.sector is not "commercial/industrial"
    macrs_bonus_fraction::Float64 = 1.0 #Note: default may change if Site.sector is not "commercial/industrial"
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3 #Note: default may change if Site.sector is not "commercial/industrial"
    total_rebate_per_cubic_meter::Float64 = 0.0
```
"""
Base.@kwdef struct UpperReservoirStorageDefaults <: AbstractWaterStorageDefaults
    tributary_water_inflow_cubic_meter_per_second::Array=[]
    minimum_volume_fraction_upper_reservoir::Float64 = 0.1
    maximum_volume_fraction_upper_reservoir::Float64 = 1.0
    initial_reservoir_volume_fraction_upper_reservoir::Float64 = 0.0
    minimum_capacity_cubic_meters_upper_reservoir::Float64 = 0.0
    maximum_capacity_cubic_meters_upper_reservoir::Float64 = 10000000.0
    cost_per_cubic_meter_upper_reservoir::Float64 = 25.0
    om_cost_per_cubic_meter::Float64 = 0.0 
    macrs_option_years::Int = 5
    macrs_bonus_fraction::Float64 = 1.0 
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3 
    total_rebate_per_cubic_meter::Float64 = 0.0
end


"""
`DownstreamReservoirStorage` is an optional REopt input with the following keys and default values:

```julia    
    initial_reservoir_volume_fraction_downstream_reservoir::Float64 = 0.5
    minimum_volume_fraction_downstream_reservoir::Float64 = 0.2
    maximum_volume_fraction_downstream_reservoir::Float64 = 1.0
    minimum_capacity_cubic_meters_downstream_reservoir::Float64 = 0.0
    maximum_capacity_cubic_meters_downstream_reservoir::Float64 = 10000000.0
    cost_per_cubic_meter_downstream_reservoir::Float64 = 25.0
    minimum_outflow_from_downstream_reservoir_cubic_meter_per_second::Float64 = 0.0
    maximum_outflow_from_downstream_reservoir_cubic_meter_per_second::Float64 = 10000.0
    om_cost_per_cubic_meter::Float64 = 0.0
    tributary_water_inflow_cubic_meter_per_second::Array=[]
    macrs_option_years::Int = 5 #Note: default may change if Site.sector is not "commercial/industrial"
    macrs_bonus_fraction::Float64 = 1.0 #Note: default may change if Site.sector is not "commercial/industrial"
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3 #Note: default may change if Site.sector is not "commercial/industrial"
    total_rebate_per_cubic_meter::Float64 = 0.0
    
```
"""
Base.@kwdef struct DownstreamReservoirStorageDefaults <: AbstractWaterStorageDefaults   
    initial_reservoir_volume_fraction_downstream_reservoir::Float64 = 0.5
    minimum_volume_fraction_downstream_reservoir::Float64 = 0.2
    maximum_volume_fraction_downstream_reservoir::Float64 = 1.0
    minimum_capacity_cubic_meters_downstream_reservoir::Float64 = 0.0
    maximum_capacity_cubic_meters_downstream_reservoir::Float64 = 10000000.0
    cost_per_cubic_meter_downstream_reservoir::Float64 = 25.0
    minimum_outflow_from_downstream_reservoir_cubic_meter_per_second::Float64 = 0.0
    maximum_outflow_from_downstream_reservoir_cubic_meter_per_second::Float64 = 10000.0
    om_cost_per_cubic_meter::Float64 = 0.0
    tributary_water_inflow_cubic_meter_per_second::Array=[]
    macrs_option_years::Int = 5 
    macrs_bonus_fraction::Float64 = 1.0 
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3 
    total_rebate_per_cubic_meter::Float64 = 0.0
end


"""
function UpperReservoirStorage(d::Dict, f::Financial, s::Site, time_steps_per_hour::Int)

Construct UpperReservoirStorage struct from Dict with keys-val pairs from the 
REopt UpperReservoirStorage and Financial inputs. 
"""
struct UpperReservoirStorage <: AbstractWaterStorage
    tributary_water_inflow_cubic_meter_per_second::Array
    minimum_volume_fraction_upper_reservoir::Float64
    maximum_volume_fraction_upper_reservoir::Float64
    initial_reservoir_volume_fraction_upper_reservoir::Float64
    minimum_capacity_cubic_meters_upper_reservoir::Float64
    maximum_capacity_cubic_meters_upper_reservoir::Float64
    cost_per_cubic_meter_upper_reservoir::Float64
    om_cost_per_cubic_meter::Float64
    macrs_option_years::Int
    macrs_bonus_fraction::Float64
    macrs_itc_reduction::Float64
    total_itc_fraction::Float64
    total_rebate_per_cubic_meter::Float64
    net_present_cost_per_cubic_meter::Float64

    function UpperReservoirStorage(d::Dict, f::Financial, s::Site, time_steps_per_hour::Int)
        set_sector_defaults!(d; struct_name="Storage", sector=s.sector, federal_procurement_type=s.federal_procurement_type)
        stor = UpperReservoirStorageDefaults(; d...)

        macrs_schedule = [0.0]
        if stor.macrs_option_years == 5 || stor.macrs_option_years == 7
            macrs_schedule = stor.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year
        elseif !(stor.macrs_option_years == 0)
            throw(@error("UpperReservoirStorage macrs_option_years must be 0, 5, or 7."))
        end
      
        net_present_cost_per_cubic_meter = effective_cost(;
            itc_basis = stor.cost_per_cubic_meter_upper_reservoir,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = stor.total_itc_fraction,
            macrs_schedule = macrs_schedule,
            macrs_bonus_fraction = stor.macrs_bonus_fraction,
            macrs_itc_reduction = stor.macrs_itc_reduction
        ) - stor.total_rebate_per_cubic_meter
        
        stor.tributary_water_inflow_cubic_meter_per_second = convert_tributary_flow_to_correct_time_steps_per_hour(stor.tributary_water_inflow_cubic_meter_per_second, time_steps_per_hour)

        if stor.maximum_volume_fraction_upper_reservoir < stor.minimum_volume_fraction_upper_reservoir
            throw(@error("The 'maximum_volume_fraction_upper_reservoir' must be greater than or equal to the 'minimum_volume_fraction_upper_reservoir"))
        end
        if (stor.initial_reservoir_volume_fraction_upper_reservoir < stor.minimum_volume_fraction_upper_reservoir) || (stor.initial_reservoir_volume_fraction_upper_reservoir > stor.maximum_volume_fraction_upper_reservoir)
            throw(@error("The 'initial_reservoir_volume_fraction_upper_reservoir' must be between the 'minimum_volume_fraction_upper_reservoir' and 'maximum_volume_fraction_upper_reservoir' "))
        end

        return new(
            stor.tributary_water_inflow_cubic_meter_per_second,
            stor.minimum_volume_fraction_upper_reservoir,
            stor.maximum_volume_fraction_upper_reservoir,
            stor.initial_reservoir_volume_fraction_upper_reservoir,
            stor.minimum_capacity_cubic_meters_upper_reservoir,
            stor.maximum_capacity_cubic_meters_upper_reservoir,
            stor.cost_per_cubic_meter_upper_reservoir,
            stor.om_cost_per_cubic_meter,
            stor.macrs_option_years,
            stor.macrs_bonus_fraction,
            stor.macrs_itc_reduction,
            stor.total_itc_fraction,
            stor.total_rebate_per_cubic_meter,
            net_present_cost_per_cubic_meter
        )
    end
end


"""
function DownstreamReservoirStorage(d::Dict, f::Financial, s::Site, time_steps_per_hour::Int)

Construct DownstreamReservoirStorage struct from Dict with keys-val pairs from the 
REopt DownstreamReservoirStorage and Financial inputs. 
"""
struct DownstreamReservoirStorage <: AbstractWaterStorage
    initial_reservoir_volume_fraction_downstream_reservoir::Float64
    minimum_volume_fraction_downstream_reservoir::Float64
    maximum_volume_fraction_downstream_reservoir::Float64
    minimum_capacity_cubic_meters_downstream_reservoir::Float64
    maximum_capacity_cubic_meters_downstream_reservoir::Float64
    cost_per_cubic_meter_downstream_reservoir::Float64
    minimum_outflow_from_downstream_reservoir_cubic_meter_per_second::Float64
    maximum_outflow_from_downstream_reservoir_cubic_meter_per_second::Float64
    om_cost_per_cubic_meter::Float64
    tributary_water_inflow_cubic_meter_per_second::Array=[]
    macrs_option_years::Int
    macrs_bonus_fraction::Float64
    macrs_itc_reduction::Float64
    total_itc_fraction::Float64
    total_rebate_per_cubic_meter::Float64
    net_present_cost_per_cubic_meter::Float64

    function DownstreamReservoirStorage(d::Dict, f::Financial, s::Site, time_steps_per_hour::Int)
        set_sector_defaults!(d; struct_name="Storage", sector=s.sector, federal_procurement_type=s.federal_procurement_type)
        stor = DownstreamReservoirStorageDefaults(; d...)

        macrs_schedule = [0.0]
        if stor.macrs_option_years == 5 || stor.macrs_option_years == 7
            macrs_schedule = stor.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year
        elseif !(stor.macrs_option_years == 0)
            throw(@error("DownstreamReservoirStorage macrs_option_years must be 0, 5, or 7."))
        end        
      
        net_present_cost_per_cubic_meter = effective_cost(;
            itc_basis = stor.cost_per_cubic_meter_downstream_reservoir,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = stor.total_itc_fraction,
            macrs_schedule = macrs_schedule,
            macrs_bonus_fraction = stor.macrs_bonus_fraction,
            macrs_itc_reduction = stor.macrs_itc_reduction
        ) - stor.total_rebate_per_cubic_meter
        
        stor.tributary_water_inflow_cubic_meter_per_second = convert_tributary_flow_to_correct_time_steps_per_hour(stor.tributary_water_inflow_cubic_meter_per_second, time_steps_per_hour)

        return new(
            stor.initial_reservoir_volume_fraction_downstream_reservoir,
            stor.minimum_volume_fraction_downstream_reservoir,
            stor.maximum_volume_fraction_downstream_reservoir,
            stor.minimum_capacity_cubic_meters_downstream_reservoir,
            stor.maximum_capacity_cubic_meters_downstream_reservoir,
            stor.cost_per_cubic_meter_downstream_reservoir,
            stor.minimum_outflow_from_downstream_reservoir_cubic_meter_per_second,
            stor.maximum_outflow_from_downstream_reservoir_cubic_meter_per_second,
            stor.om_cost_per_cubic_meter,
            stor.tributary_water_inflow_cubic_meter_per_second,
            stor.macrs_option_years,
            stor.macrs_bonus_fraction,
            stor.macrs_itc_reduction,
            stor.total_itc_fraction,
            stor.total_rebate_per_cubic_meter,
            net_present_cost_per_cubic_meter
        )
    end
end


function convert_tributary_flow_to_correct_time_steps_per_hour(tribuary_flow, time_steps_per_hour)
    
    tributary_flow_length = length(tributary_flow)

    if (tributary_flow_length != 8760) && (tributary_flow_length != 17520) && (tributary_flow_length != 35040)
        throw(@error("Invalid length of the tributary flow vector"))
    elseif (time_steps_per_hour == 2) && (tributary_flow_length == 8760)
        @warn("Upscaling the tributary flow rate to match the time steps per hour")
        tribuary_flow = repeat(tribuary_flow, inner=time_steps_per_hour)
    elseif (time_steps_per_hour == 4) && (tributary_flow_length == 8760)
        @warn("Upscaling the tributary flow rate to match the time steps per hour")
        tribuary_flow = repeat(tribuary_flow, inner=time_steps_per_hour)
    #elseif
        # TODO: add more options for setting the tributary_flow variable to the correct length
    else
        print("\n No changes made to the tributary flow input vector \n")
    end

    return tribuary_flow

end

   
