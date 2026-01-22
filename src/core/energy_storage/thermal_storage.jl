# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.


"""
Cold thermal energy storage sytem; specifically, a chilled water system used to meet thermal cooling loads.

`ColdThermalStorage` is an optional REopt input with the following keys and default values:

```julia
    min_gal::Float64 = 0.0
    max_gal::Float64 = 0.0
    hot_water_temp_degF::Float64 = 56.0 # Warmed-side return water temperature from the cooling load to the ColdTES (top of tank)
    cool_water_temp_degF::Float64 = 44.0 # Chilled-side supply water temperature from ColdTES (bottom of tank) to the cooling load
    internal_efficiency_fraction::Float64 = 0.999999 # Efficiency due to mixing losses from thermal power entering or leaving tank
    soc_min_fraction::Float64 = 0.1 # Minimum allowable TES thermal state of charge
    soc_init_fraction::Float64 = 0.5 # TES thermal state of charge at first hour of optimization
    installed_cost_per_gal::Float64 = 1.50 # Thermal energy capacity based cost of TES
    soc_based_per_ts_self_discharge_fraction::Float64 = 0.0 # Thermal loss (gain) per timestep, as a fraction of the energy stored in each timestep
    capacity_based_per_ts_self_discharge_fraction::Float64 = 0.0004 # Thermal loss (gain) per timestep, as a fraction of the rated storage capacity per timestep; the provided default is for an hourly thermal loss/gain
    om_cost_per_gal::Float64 = 0.0 # Yearly fixed O&M cost dependent on storage energy capacity
    macrs_option_years::Int = 7
    macrs_bonus_fraction::Float64 = 0.6
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3
    total_rebate_per_kwh::Float64 = 0.0
```
"""
Base.@kwdef struct ColdThermalStorageDefaults <: AbstractThermalStorageDefaults
    min_gal::Float64 = 0.0
    max_gal::Float64 = 0.0
    hot_water_temp_degF::Float64 = 56.0
    cool_water_temp_degF::Float64 = 44.0
    internal_efficiency_fraction::Float64 = 0.999999
    soc_min_fraction::Float64 = 0.1
    soc_init_fraction::Float64 = 0.5
    installed_cost_per_gal::Float64 = 1.50
    soc_based_per_ts_self_discharge_fraction::Float64 = 0.0
    capacity_based_per_ts_self_discharge_fraction::Float64 = 0.0004
    om_cost_per_gal::Float64 = 0.0
    macrs_option_years::Int = 7
    macrs_bonus_fraction::Float64 = 0.6
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3
    total_rebate_per_kwh::Float64 = 0.0
end


"""
`HotThermalStorage` is an optional REopt input with the following keys and default values:

```julia
    min_gal::Float64 = 0.0
    max_gal::Float64 = 0.0
    hot_water_temp_degF::Float64 = 180.0
    cool_water_temp_degF::Float64 = 160.0
    internal_efficiency_fraction::Float64 = 0.999999 # Efficiency due to mixing losses from thermal power entering or leaving tank
    soc_min_fraction::Float64 = 0.1 # Minimum allowable TES thermal state of charge
    soc_init_fraction::Float64 = 0.5 # TES thermal state of charge at first hour of optimization
    installed_cost_per_gal::Float64 = 1.50 # Thermal energy capacity based cost of TES
    soc_based_per_ts_self_discharge_fraction::Float64 = 0.0 # Energy loss per timestep, as a fraction of the energy stored in each timestep
    capacity_based_per_ts_self_discharge_fraction::Float64 = 0.0004 # Energy loss per timestep, as a fraction of the rated storage capacity per timestep; the provided default is for an hourly thermal loss/gain
    om_cost_per_gal::Float64 = 0.0 # Yearly fixed O&M cost dependent on storage energy capacity
    macrs_option_years::Int = 7
    macrs_bonus_fraction::Float64 = 0.6
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3
    total_rebate_per_kwh::Float64 = 0.0
    can_serve_dhw::Bool = true
    can_serve_space_heating:Bool = true
    can_serve_process_heat::Bool = false
```
"""
Base.@kwdef struct HotThermalStorageDefaults <: AbstractThermalStorageDefaults
    min_gal::Float64 = 0.0
    max_gal::Float64 = 0.0
    hot_water_temp_degF::Float64 = 180.0
    cool_water_temp_degF::Float64 = 160.0
    internal_efficiency_fraction::Float64 = 0.999999
    soc_min_fraction::Float64 = 0.1
    soc_init_fraction::Float64 = 0.5
    installed_cost_per_gal::Float64 = 1.50
    soc_based_per_ts_self_discharge_fraction::Float64 = 0.0
    capacity_based_per_ts_self_discharge_fraction::Float64 = 0.0004
    om_cost_per_gal::Float64 = 0.0
    macrs_option_years::Int = 7
    macrs_bonus_fraction::Float64 = 0.6
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3
    total_rebate_per_kwh::Float64 = 0.0
    can_serve_dhw::Bool = true
    can_serve_space_heating::Bool = true
    can_serve_process_heat::Bool = false
end


"""
`HighTempThermalStorage` models a generic thermal storage medium for storing thermal energy at high temperatures to serve process heat loads.
The storage charging mechanism is decoupled from the discharge mechanism, allowing the components to be independently sized and costed. 
The user has the option to constrain charge and discharge power to be less than a specified fraction of the energy stored in the system, 
as well as optionally account for auxiliary pump power consumption based on the rate of energy discharge. 

`HighTempThermalStorage` is an optional REopt input with the following keys and default values:
```julia
    min_kw_charge::Float64 = 0.0, # Minimum charge mechanism size in kW (may be decoupled from the discharge mechanism)
    max_kw_charge::Float64 = 0.0, # Maximum charge mechanism size in kW (may be decoupled from the discharge mechanism)
    min_kw_discharge::Float64 = 0.0, # Minimum discharge mechanism size in kW (may be decoupled from the charge mechanism)
    max_kw_discharge::Float64 = 0.0, # Maximum discharge mechanism size in kW (may be decoupled from the charge mechanism)
    min_kwh::Float64 = 0.0, # Minimum storage size in kWh
    max_kwh::Float64 = 0.0, # Maximum storage size in kWh
    constrain_dispatch_to_stored_kwh::Bool = false, # True/False for if maximum charge and discharge power in timestep t is constrained to be less than a fraction of the energy stored in the system in timestep t-1
    charge_limit_as_fraction_of_stored_kwh::Float64 = 1.0, # If constrain_dispatch_to_stored_kwh is true, limit charging power to this fraction of the energy stored in the system in the previous timestep 
    discharge_limit_as_fraction_of_stored_kwh::Float64 = 1.0, # If constrain_dispatch_to_stored_kwh is true, limit discharging power to this fraction of the energy stored in the system in the previous timestep 
    include_discharge_pump_losses::Bool = false, # True/False for if auxiliary pump losses based on discharge power are modeled
    pump_loss_as_fraction_of_discharge_kw::Float64 = 0.01, # Fraction of discharge power that is consumed as electricity by the auxiliary pump. This electric power must be supplied by another source.
    charge_efficiency::Float64 = 0.98, # Efficiency of the charge mechanism
    discharge_efficiency::Float64 = 0.903, # Efficiency of the discharge mechanism
    soc_min_fraction::Float64 = 0.1, # Minimum state of charge fraction
    soc_init_fraction::Float64 = 0.5, # Initial state of charge fraction
    installed_cost_per_kwh::Float64 = 5.0, # Total installed cost per kWh of thermal storage
    installed_cost_per_kw_charge::Float64 = 7.3, # Total installed cost of the charge mechanism (\$/kW)
    installed_cost_per_kw_discharge::Float64 = 7.3, # Total installed cost of the discharge mechanism (\$/kW)
    om_cost_per_kwh::Float64 = 0.0, # Fixed O&M based on installed storage capacity (\$/kWh)
    min_kw::Float64 = min(min_kw_charge, min_kw_discharge), # Minimum charge/discharge power in kW
    max_kw::Float64 = max(max_kw_charge, max_kw_discharge), # Maximum charge/discharge power in kW 
    minimum_avg_soc_fraction::Float64 = 0.0, # Minimum average state of charge fraction of the system over a typical year of operation
    soc_based_per_ts_self_discharge_fraction::Float64 = 0.0 # Energy loss per timestep, as a fraction of the energy stored in each timestep
    capacity_based_per_ts_self_discharge_fraction::Float64 = 0.0004 # Energy loss per timestep, as a fraction of the rated storage capacity per timestep; the provided default is for an hourly thermal loss/gain
    macrs_option_years::Int = 7, # MACRS schedule for financial analysis (5 or 7 years). Set to zero to disable
    macrs_bonus_fraction::Float64 = 0.6, # Fraction of upfront project costs to depreciate in Year 1 in addition to scheduled depreciation
    macrs_itc_reduction::Float64 = 0.5, # Fraction of the ITC value by which the depreciable basis is reduced
    total_itc_fraction::Float64 = 0.3, # Total Investment Tax Credit (ITC) fraction
    total_rebate_per_kwh::Float64 = 0.0, # Total rebate based on installed storage capacity (\$/kWh)
    can_supply_steam_turbine::Bool = true, # True/False for if technology can supply steam to the steam turbine for electric production
    can_serve_dhw::Bool = false, # True/False for if technology can supply heat to the domestic hot water loads
    can_serve_space_heating::Bool = false, # True/False for if technology can supply heat to the space heating loads
    can_serve_process_heat::Bool = true, # True/False for if technology can supply heat to the process heat loads
```
"""
Base.@kwdef struct HighTempThermalStorageDefaults <: AbstractThermalStorageDefaults
    min_kw_charge::Float64 = 0.0
    max_kw_charge::Float64 = 0.0
    min_kw_discharge::Float64 = 0.0
    max_kw_discharge::Float64 = 0.0
    min_kwh::Float64 = 0.0
    max_kwh::Float64 = 0.0
    constrain_dispatch_to_stored_kwh::Bool = false
    charge_limit_as_fraction_of_stored_kwh::Float64 = 1.0
    discharge_limit_as_fraction_of_stored_kwh::Float64 = 1.0
    include_discharge_pump_losses::Bool = false
    pump_loss_as_fraction_of_discharge_kw::Float64 = 0.01
    charge_efficiency::Float64 = 0.98
    discharge_efficiency::Float64 = 0.903
    soc_min_fraction::Float64 = 0.1
    soc_init_fraction::Float64 = 0.5
    installed_cost_per_kwh::Float64 = 5.0
    installed_cost_per_kw_charge::Float64 = 7.3
    installed_cost_per_kw_discharge::Float64 = 7.3
    om_cost_per_kwh::Float64 = 0.0
    min_kw::Float64 = min(min_kw_charge, min_kw_discharge)
    max_kw::Float64 = max(max_kw_charge, max_kw_discharge)
    minimum_avg_soc_fraction::Float64 = 0.0
    thermal_decay_rate_fraction::Float64 = 0.0004
    macrs_option_years::Int = 7
    macrs_bonus_fraction::Float64 = 0.6
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3
    total_rebate_per_kwh::Real = 0.0
    total_rebate_per_kw_charge::Real = 0.0
    total_rebate_per_kw_discharge::Real = 0.0
    can_supply_steam_turbine::Bool = true
    can_serve_dhw::Bool = false
    can_serve_space_heating::Bool = false
    can_serve_process_heat::Bool = true
end


"""
function ColdThermalStorage(d::Dict, f::Financial, time_steps_per_hour::Int)

Construct ColdThermalStorage struct from Dict with keys-val pairs from the 
REopt ColdThermalStorage and Financial inputs. 
"""
struct ColdThermalStorage <: AbstractThermalStorage
    min_gal::Float64
    max_gal::Float64
    hot_water_temp_degF::Float64
    cool_water_temp_degF::Float64
    internal_efficiency_fraction::Float64
    soc_min_fraction::Float64
    soc_init_fraction::Float64
    installed_cost_per_gal::Float64
    soc_based_per_ts_self_discharge_fraction::Float64
    capacity_based_per_ts_self_discharge_fraction::Float64
    om_cost_per_gal::Float64
    macrs_option_years::Int
    macrs_bonus_fraction::Float64
    total_rebate_per_kwh::Float64
    min_kw::Float64
    max_kw::Float64
    min_kwh::Float64
    max_kwh::Float64
    installed_cost_per_kwh::Float64
    charge_efficiency::Float64
    discharge_efficiency::Float64
    net_present_cost_per_kwh::Float64
    om_cost_per_kwh::Float64

    function ColdThermalStorage(s::AbstractThermalStorageDefaults, f::Financial, time_steps_per_hour::Int)
         
        kwh_per_gal = get_kwh_per_gal(s.hot_water_temp_degF, s.cool_water_temp_degF)
        min_kwh = s.min_gal * kwh_per_gal
        max_kwh = s.max_gal * kwh_per_gal
        min_kw = min_kwh * time_steps_per_hour
        max_kw = max_kwh * time_steps_per_hour
        om_cost_per_kwh = s.om_cost_per_gal / kwh_per_gal
    
        charge_efficiency = s.internal_efficiency_fraction^0.5
        discharge_efficiency = s.internal_efficiency_fraction^0.5
        installed_cost_per_kwh = s.installed_cost_per_gal / kwh_per_gal
      
        net_present_cost_per_kwh = effective_cost(;
            itc_basis = installed_cost_per_kwh,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = s.total_itc_fraction,
            macrs_schedule = s.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year,
            macrs_bonus_fraction = s.macrs_bonus_fraction,
            macrs_itc_reduction = s.macrs_itc_reduction
        ) - s.total_rebate_per_kwh
    
        return new(
            s.min_gal,
            s.max_gal,
            s.hot_water_temp_degF,
            s.cool_water_temp_degF,
            s.internal_efficiency_fraction,
            s.soc_min_fraction,
            s.soc_init_fraction,
            s.installed_cost_per_gal,
            s.soc_based_per_ts_self_discharge_fraction,
            s.capacity_based_per_ts_self_discharge_fraction,
            s.om_cost_per_gal,
            s.macrs_option_years,
            s.macrs_bonus_fraction,
            s.total_rebate_per_kwh,
            min_kw,
            max_kw,
            min_kwh,
            max_kwh,
            installed_cost_per_kwh,
            charge_efficiency,
            discharge_efficiency,
            net_present_cost_per_kwh,
            om_cost_per_kwh
        )
    end
end


"""
function HotThermalStorage(d::Dict, f::Financial, time_steps_per_hour::Int)

Construct HotThermalStorage struct from Dict with keys-val pairs from the 
REopt HotThermalStorage and Financial inputs. 
"""
struct HotThermalStorage <: AbstractThermalStorage
    min_gal::Float64
    max_gal::Float64
    hot_water_temp_degF::Float64
    cool_water_temp_degF::Float64
    internal_efficiency_fraction::Float64
    soc_min_fraction::Float64
    soc_init_fraction::Float64
    installed_cost_per_gal::Float64
    soc_based_per_ts_self_discharge_fraction::Float64
    capacity_based_per_ts_self_discharge_fraction::Float64
    om_cost_per_gal::Float64
    macrs_option_years::Int
    macrs_bonus_fraction::Float64
    total_rebate_per_kwh::Float64
    min_kw::Float64
    max_kw::Float64
    min_kwh::Float64
    max_kwh::Float64
    installed_cost_per_kwh::Float64
    charge_efficiency::Float64
    discharge_efficiency::Float64
    net_present_cost_per_kwh::Float64
    om_cost_per_kwh::Float64
    can_serve_dhw::Bool
    can_serve_space_heating::Bool
    can_serve_process_heat::Bool

    function HotThermalStorage(s::AbstractThermalStorageDefaults, f::Financial, time_steps_per_hour::Int)
         
        kwh_per_gal = get_kwh_per_gal(s.hot_water_temp_degF, s.cool_water_temp_degF)
        min_kwh = s.min_gal * kwh_per_gal
        max_kwh = s.max_gal * kwh_per_gal
        min_kw = min_kwh * time_steps_per_hour
        max_kw = max_kwh * time_steps_per_hour
        om_cost_per_kwh = s.om_cost_per_gal / kwh_per_gal
    
        charge_efficiency = s.internal_efficiency_fraction^0.5
        discharge_efficiency = s.internal_efficiency_fraction^0.5
        installed_cost_per_kwh = s.installed_cost_per_gal / kwh_per_gal
      
        net_present_cost_per_kwh = effective_cost(;
            itc_basis = installed_cost_per_kwh,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = s.total_itc_fraction,
            macrs_schedule = s.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year,
            macrs_bonus_fraction = s.macrs_bonus_fraction,
            macrs_itc_reduction = s.macrs_itc_reduction
        ) - s.total_rebate_per_kwh
    
        return new(
            s.min_gal,
            s.max_gal,
            s.hot_water_temp_degF,
            s.cool_water_temp_degF,
            s.internal_efficiency_fraction,
            s.soc_min_fraction,
            s.soc_init_fraction,
            s.installed_cost_per_gal,
            s.soc_based_per_ts_self_discharge_fraction,
            s.capacity_based_per_ts_self_discharge_fraction,
            s.om_cost_per_gal,
            s.macrs_option_years,
            s.macrs_bonus_fraction,
            s.total_rebate_per_kwh,
            min_kw,
            max_kw,
            min_kwh,
            max_kwh,
            installed_cost_per_kwh,
            charge_efficiency,
            discharge_efficiency,
            net_present_cost_per_kwh,
            om_cost_per_kwh,
            s.can_serve_dhw,
            s.can_serve_space_heating,
            s.can_serve_process_heat
        )
    end
end


"""
function HighTempThermalStorage(d::Dict, f::Financial, time_steps_per_hour::Int)

Construct HighTempThermalStorage struct from Dict with keys-val pairs from the 
REopt HighTempThermalStorage and Financial inputs. 
"""
struct HighTempThermalStorage <: AbstractThermalStorage
    min_kw_charge::Float64
    max_kw_charge::Float64
    min_kw_discharge::Float64
    max_kw_discharge::Float64
    min_kwh::Float64
    max_kwh::Float64
    constrain_dispatch_to_stored_kwh::Bool
    charge_limit_as_fraction_of_stored_kwh::Float64
    discharge_limit_as_fraction_of_stored_kwh::Float64
    include_discharge_pump_losses::Bool
    pump_loss_as_fraction_of_discharge_kw::Float64
    charge_efficiency::Float64
    discharge_efficiency::Float64
    soc_min_fraction::Float64
    soc_init_fraction::Float64
    installed_cost_per_kwh::Float64
    installed_cost_per_kw_charge::Float64
    installed_cost_per_kw_discharge::Float64
    net_present_cost_per_kwh::Float64
    net_present_cost_per_kw_charge::Float64
    net_present_cost_per_kw_discharge::Float64
    om_cost_per_kwh::Float64
    min_kw::Float64
    max_kw::Float64
    minimum_avg_soc_fraction::Float64
    thermal_decay_rate_fraction::Float64
    macrs_option_years::Int
    macrs_bonus_fraction::Float64
    macrs_itc_reduction::Float64
    total_itc_fraction::Float64
    total_rebate_per_kwh::Real
    total_rebate_per_kw_charge::Real
    total_rebate_per_kw_discharge::Real
    can_supply_steam_turbine::Bool
    can_serve_dhw::Bool
    can_serve_space_heating::Bool
    can_serve_process_heat::Bool

    function HighTempThermalStorage(s::AbstractThermalStorageDefaults, f::Financial, time_steps_per_hour::Int)

        net_present_cost_per_kwh = effective_cost(;
            itc_basis = s.installed_cost_per_kwh,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = s.total_itc_fraction,
            macrs_schedule = s.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year,
            macrs_bonus_fraction = s.macrs_bonus_fraction,
            macrs_itc_reduction = s.macrs_itc_reduction
        ) - s.total_rebate_per_kwh

        net_present_cost_per_kw_charge = effective_cost(;
            itc_basis = s.installed_cost_per_kw_charge,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = s.total_itc_fraction,
            macrs_schedule = s.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year,
            macrs_bonus_fraction = s.macrs_bonus_fraction,
            macrs_itc_reduction = s.macrs_itc_reduction,
            rebate_per_kw = s.total_rebate_per_kw_charge
        )

        net_present_cost_per_kw_discharge = effective_cost(;
            itc_basis = s.installed_cost_per_kw_discharge,
            replacement_cost = 0.0,
            replacement_year = 100,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = s.total_itc_fraction,
            macrs_schedule = s.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year,
            macrs_bonus_fraction = s.macrs_bonus_fraction,
            macrs_itc_reduction = s.macrs_itc_reduction,
            rebate_per_kw = s.total_rebate_per_kw_charge
        )

        return new(
            s.min_kw_charge,
            s.max_kw_charge,
            s.min_kw_discharge,
            s.max_kw_discharge,
            s.min_kwh,
            s.max_kwh,
            s.constrain_dispatch_to_stored_kwh,
            s.charge_limit_as_fraction_of_stored_kwh,
            s.discharge_limit_as_fraction_of_stored_kwh,
            s.include_discharge_pump_losses,
            s.pump_loss_as_fraction_of_discharge_kw,
            s.charge_efficiency,
            s.discharge_efficiency,
            s.soc_min_fraction,
            s.soc_init_fraction,
            s.installed_cost_per_kwh,
            s.installed_cost_per_kw_charge,
            s.installed_cost_per_kw_discharge,
            net_present_cost_per_kwh,
            net_present_cost_per_kw_charge,
            net_present_cost_per_kw_discharge,
            s.om_cost_per_kwh,
            s.min_kw,
            s.max_kw,
            s.minimum_avg_soc_fraction,
            s.thermal_decay_rate_fraction,
            s.macrs_option_years,
            s.macrs_bonus_fraction,
            s.macrs_itc_reduction,
            s.total_itc_fraction,
            s.total_rebate_per_kwh,
            s.total_rebate_per_kw_charge,
            s.total_rebate_per_kw_discharge,
            s.can_supply_steam_turbine,
            s.can_serve_dhw,
            s.can_serve_space_heating,
            s.can_serve_process_heat,
        )
    end
end