# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

struct Boiler <: AbstractThermalTech
    min_kw::Real
    max_kw::Real
    efficiency::Real
    fuel_cost_per_mmbtu::Union{<:Real, AbstractVector{<:Real}}
    installed_cost_per_kw::Real
    om_cost_per_kw::Real
    om_cost_per_kwh::Real
    macrs_option_years::Int
    macrs_bonus_fraction::Real
    fuel_type::String
    can_supply_steam_turbine::Bool
    can_serve_dhw::Bool
    can_serve_space_heating::Bool
    can_serve_process_heat::Bool
    fuel_renewable_energy_fraction::Real
    emissions_factor_lb_CO2_per_mmbtu::Real
    emissions_factor_lb_NOx_per_mmbtu::Real
    emissions_factor_lb_SO2_per_mmbtu::Real
    emissions_factor_lb_PM25_per_mmbtu::Real
end


"""
    Boiler

When modeling a heating load an `ExistingBoiler` model is created even if user does not provide the
`ExistingBoiler` key. The `Boiler` model is not created by default. If a user provides the `Boiler`
key then the optimal scenario has the option to purchase this new `Boiler` to meet the heating load
in addition to using the `ExistingBoiler` to meet the heating load. 

```julia
function Boiler(;
    min_mmbtu_per_hour::Real = 0.0, # Minimum thermal power size
    max_mmbtu_per_hour::Real = 0.0, # Maximum thermal power size
    efficiency::Real = 0.8, # boiler system efficiency - conversion of fuel to usable heating thermal energy
    fuel_cost_per_mmbtu::Union{<:Real, AbstractVector{<:Real}} = 0.0,
    macrs_option_years::Int = 0, # MACRS schedule for financial analysis. Set to zero to disable
    macrs_bonus_fraction::Real = 0.0, # Fraction of upfront project costs to depreciate under MACRS
    installed_cost_per_mmbtu_per_hour::Real = 293000.0, # Thermal power-based cost
    om_cost_per_mmbtu_per_hour::Real = 2930.0, # Thermal power-based fixed O&M cost
    om_cost_per_mmbtu::Real = 0.0, # Thermal energy-based variable O&M cost
    fuel_type::String = "natural_gas",  # "restrict_to": ["natural_gas", "landfill_bio_gas", "propane", "diesel_oil", "uranium"]
    can_supply_steam_turbine::Bool = true # If the boiler can supply steam to the steam turbine for electric production
    can_serve_dhw::Bool = true # If Boiler can supply heat to the domestic hot water load
    can_serve_space_heating::Bool = true # If Boiler can supply heat to the space heating load
    can_serve_process_heat::Bool = true # If Boiler can supply heat to the process heating load
    fuel_renewable_energy_fraction::Real = get(FUEL_DEFAULTS["fuel_renewable_energy_fraction"],fuel_type,0) # fraction of renewable-sourced fuel input to boiler
    emissions_factor_lb_CO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_CO2_per_mmbtu"],fuel_type,0)
    emissions_factor_lb_NOx_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_NOx_per_mmbtu"],fuel_type,0)
    emissions_factor_lb_SO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_SO2_per_mmbtu"],fuel_type,0)
    emissions_factor_lb_PM25_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_PM25_per_mmbtu"],fuel_type,0)
)
```
"""
function Boiler(;
        min_mmbtu_per_hour::Real = 0.0,
        max_mmbtu_per_hour::Real = 0.0,
        efficiency::Real = 0.8,
        fuel_cost_per_mmbtu::Union{<:Real, AbstractVector{<:Real}} = [], # REQUIRED. Can be a scalar, a list of 12 monthly values, or a time series of values for every time step
        time_steps_per_hour::Int = 1,  # passed from Settings
        macrs_option_years::Int = 0,
        macrs_bonus_fraction::Real = 0.0,
        installed_cost_per_mmbtu_per_hour::Real = 293000.0,
        om_cost_per_mmbtu_per_hour::Real = 2930.0,
        om_cost_per_mmbtu::Real = 0.0,
        fuel_type::String = "natural_gas",  # "restrict_to": ["natural_gas", "landfill_bio_gas", "propane", "diesel_oil", "uranium"]
        can_supply_steam_turbine::Bool = true,
        can_serve_dhw::Bool = true,
        can_serve_space_heating::Bool = true,
        can_serve_process_heat::Bool = true,
        fuel_renewable_energy_fraction::Real = get(FUEL_DEFAULTS["fuel_renewable_energy_fraction"],fuel_type,0),
        emissions_factor_lb_CO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_CO2_per_mmbtu"],fuel_type,0),
        emissions_factor_lb_NOx_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_NOx_per_mmbtu"],fuel_type,0),
        emissions_factor_lb_SO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_SO2_per_mmbtu"],fuel_type,0),
        emissions_factor_lb_PM25_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_PM25_per_mmbtu"],fuel_type,0),
    )

    if isempty(fuel_cost_per_mmbtu)
        throw(@error("The Boiler.fuel_cost_per_mmbtu is a required input when modeling a heating load which is served by the Boiler in the optimal case"))
    end

    min_kw = min_mmbtu_per_hour * KWH_PER_MMBTU
    max_kw = max_mmbtu_per_hour * KWH_PER_MMBTU

    # Convert cost basis of mmbtu/mmbtu_per_hour to kwh/kw
    installed_cost_per_kw = installed_cost_per_mmbtu_per_hour / KWH_PER_MMBTU
    om_cost_per_kw = om_cost_per_mmbtu_per_hour / KWH_PER_MMBTU
    om_cost_per_kwh = om_cost_per_mmbtu / KWH_PER_MMBTU

    Boiler(
        min_kw,
        max_kw,
        efficiency,
        fuel_cost_per_mmbtu,
        installed_cost_per_kw,
        om_cost_per_kw,
        om_cost_per_kwh,
        macrs_option_years,
        macrs_bonus_fraction,
        fuel_type,
        can_supply_steam_turbine,
        can_serve_dhw,
        can_serve_space_heating,
        can_serve_process_heat,
        fuel_renewable_energy_fraction,
        emissions_factor_lb_CO2_per_mmbtu,
        emissions_factor_lb_NOx_per_mmbtu,
        emissions_factor_lb_SO2_per_mmbtu,
        emissions_factor_lb_PM25_per_mmbtu
    )
end
