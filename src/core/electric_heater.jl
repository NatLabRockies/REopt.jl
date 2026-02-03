# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

struct ElectricHeater <: AbstractThermalTech
    min_kw::Real
    max_kw::Real
    installed_cost_per_kw::Real
    om_cost_per_kw::Real
    macrs_option_years::Int
    macrs_bonus_fraction::Real
    can_supply_steam_turbine::Bool
    cop::Real
    can_serve_dhw::Bool
    can_serve_space_heating::Bool
    can_serve_process_heat::Bool
    charge_storage_only::Bool
end


"""
ElectricHeater

If a user provides the `ElectricHeater` key then the optimal scenario has the option to purchase 
this new `ElectricHeater` to meet the heating load in addition to using the `ExistingBoiler`
 to meet the heating load. 

```julia
function ElectricHeater(;
    min_mmbtu_per_hour::Real = 0.0, # Minimum thermal power size
    max_mmbtu_per_hour::Real = BIG_NUMBER, # Maximum thermal power size
    installed_cost_per_mmbtu_per_hour::Union{Real, nothing} = nothing, # Thermal power-based cost
    om_cost_per_mmbtu_per_hour::Union{Real, nothing} = nothing, # Thermal power-based fixed O&M cost
    macrs_option_years::Int = 0, # MACRS schedule for financial analysis. Set to zero to disable
    macrs_bonus_fraction::Real = 0.0, # Fraction of upfront project costs to depreciate under MACRS
    can_supply_steam_turbine::Union{Bool, nothing} = nothing # If the boiler can supply steam to the steam turbine for electric production
    cop::Union{Real, nothing} = nothing # COP of the heating (i.e., thermal produced / electricity consumed)
    can_serve_dhw::Bool = true # If electric heater can supply heat to the domestic hot water load
    can_serve_space_heating::Bool = true # If electric heater can supply heat to the space heating load
    can_serve_process_heat::Bool = true # If electric heater can supply heat to the process heating load
)
```
"""
function ElectricHeater(;
        min_mmbtu_per_hour::Real = 0.0,
        max_mmbtu_per_hour::Real = BIG_NUMBER,
        installed_cost_per_mmbtu_per_hour::Union{Real, Nothing} = nothing,
        om_cost_per_mmbtu_per_hour::Union{Real, Nothing} = nothing,
        macrs_option_years::Int = 0,
        macrs_bonus_fraction::Real = 0.0,
        can_supply_steam_turbine::Union{Bool, Nothing} = nothing,
        cop::Union{Real, Nothing} = nothing,
        can_serve_dhw::Bool = true,
        can_serve_space_heating::Bool = true,
        can_serve_process_heat::Bool = true,
        charge_storage_only::Bool = false
    )

    defaults = get_electric_heater_defaults()

    # populate defaults as needed
    if isnothing(installed_cost_per_mmbtu_per_hour)
        installed_cost_per_mmbtu_per_hour = defaults["installed_cost_per_mmbtu_per_hour"]
    end
    if isnothing(om_cost_per_mmbtu_per_hour)
        om_cost_per_mmbtu_per_hour = defaults["om_cost_per_mmbtu_per_hour"]
    end
    if isnothing(can_supply_steam_turbine)
        can_supply_steam_turbine = defaults["can_supply_steam_turbine"]
    end
    if isnothing(cop)
        cop = defaults["cop"]
    end

    # Convert max sizes, cost factors from mmbtu_per_hour to kw
    min_kw = min_mmbtu_per_hour * KWH_PER_MMBTU
    max_kw = max_mmbtu_per_hour * KWH_PER_MMBTU

    
    installed_cost_per_kw = installed_cost_per_mmbtu_per_hour / KWH_PER_MMBTU
    om_cost_per_kw = om_cost_per_mmbtu_per_hour / KWH_PER_MMBTU

    
    ElectricHeater(
        min_kw,
        max_kw,
        installed_cost_per_kw,
        om_cost_per_kw,
        macrs_option_years,
        macrs_bonus_fraction,
        can_supply_steam_turbine,
        cop,
        can_serve_dhw,
        can_serve_space_heating,
        can_serve_process_heat,
        charge_storage_only
    )
end



"""
function get_electric_heater_defaults()

Obtains defaults for the electric heater from a JSON data file. 

inputs
None

returns
eh_defaults::Dict -- Dictionary containing defaults for electric heater
"""
function get_electric_heater_defaults()
    eh_defaults = JSON.parsefile(joinpath(dirname(@__FILE__), "..", "..", "data", "electric_heater", "electric_heater_defaults.json"))
    return eh_defaults
end