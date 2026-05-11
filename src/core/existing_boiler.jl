# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
const existing_boiler_efficiency_defaults = Dict(
                                                "hot_water" => EXISTING_BOILER_EFFICIENCY,
                                                "steam" => 0.75
                                            )

struct ExistingBoiler <: AbstractThermalTech  # useful to create AbstractHeatingTech or AbstractThermalTech?
    max_kw::Real
    production_type::String
    max_thermal_factor_on_peak_load::Real    
    installed_cost_per_kw::Real
    installed_cost_dollars::Real 
    efficiency::Real
    fuel_cost_per_mmbtu::Union{<:Real, AbstractVector{<:Real}}
    fuel_type::String
    can_supply_steam_turbine::Bool
    retire_in_optimal::Bool
    fuel_renewable_energy_fraction::Real
    emissions_factor_lb_CO2_per_mmbtu::Real
    emissions_factor_lb_NOx_per_mmbtu::Real
    emissions_factor_lb_SO2_per_mmbtu::Real
    emissions_factor_lb_PM25_per_mmbtu::Real
    can_serve_dhw::Bool
    can_serve_space_heating::Bool
    can_serve_process_heat::Bool
end


"""
`ExistingBoiler` is an optional REopt input with the following keys and default values:
```julia
    max_heat_demand_kw::Real=0, # Auto-populated based on SpaceHeatingLoad and DomesticHotWaterLoad inputs
    production_type::String = "hot_water", # Can be "steam" or "hot_water"
    max_thermal_factor_on_peak_load::Real = 1.25,
    installed_cost_per_mmbtu_per_hour::Real = 0.0  # Represents needed CapEx in BAU, assuming net present value basis; cost is scaled to the size of boiler needed
    installed_cost_dollars::Real = 0.0  # Represents needed CapEx in BAU, assuming net present cost basis; also incurred in Optimal case if still using at all
    efficiency::Real = NaN, # Existing boiler system efficiency - conversion of fuel to usable heating thermal energy. See note below.
    fuel_cost_per_mmbtu::Union{<:Real, AbstractVector{<:Real}} = [], # REQUIRED. Can be a scalar, a list of 12 monthly values, or a time series of values for every time step
    fuel_type::String = "natural_gas", # "restrict_to": ["natural_gas", "landfill_bio_gas", "propane", "diesel_oil"]
    can_supply_steam_turbine::Bool = false,
    retire_in_optimal::Bool = false,  # Do NOT use in the optimal case (still used in BAU)
    fuel_renewable_energy_fraction::Real = get(FUEL_DEFAULTS["fuel_renewable_energy_fraction"],fuel_type,0),
    emissions_factor_lb_CO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_CO2_per_mmbtu"],fuel_type,0),
    emissions_factor_lb_NOx_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_NOx_per_mmbtu"],fuel_type,0),
    emissions_factor_lb_SO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_SO2_per_mmbtu"],fuel_type,0),
    emissions_factor_lb_PM25_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_PM25_per_mmbtu"],fuel_type,0)
    can_serve_dhw::Bool = true # If ExistingBoiler can supply heat to the domestic hot water load
    can_serve_space_heating::Bool = true # If ExistingBoiler can supply heat to the space heating load
    can_serve_process_heat::Bool = true # If ExistingBoiler can supply heat to the process heating load
```

!!! note "Max ExistingBoiler size" 
    The maximum size [kW] of the `ExistingBoiler` will be set based on the peak heat demand as follows:
    ```julia 
    max_kw = max_heat_demand_kw * max_thermal_factor_on_peak_load
    ```

!!! note "ExistingBoiler operating costs" 
    The `ExistingBoiler`'s `fuel_cost_per_mmbtu` field is a required input. The `fuel_cost_per_mmbtu` can be a scalar, a list of 12 monthly values, or a time series of values for every time step.

!!! note "Determining `efficiency`" 
    Must supply either: `efficiency` or `production_type`.
    
    If `efficiency` is not supplied, the `efficiency` will be determined based on the `production_type`. 
    If `production_type` is not supplied, it defaults to `hot_water`.
    The following defaults are used:
    ```julia
    existing_boiler_efficiency_defaults = Dict(
        "hot_water" => 0.8,
        "steam" => 0.75
    )
    ```

"""
function ExistingBoiler(;
    max_heat_demand_kw::Real=0,
    production_type::String = "hot_water",
    max_thermal_factor_on_peak_load::Real = 1.25,
    installed_cost_per_mmbtu_per_hour::Real = 0.0,
    installed_cost_dollars::Real = 0.0,
    efficiency::Real = NaN,
    fuel_cost_per_mmbtu::Union{<:Real, AbstractVector{<:Real}} = [], # REQUIRED. Can be a scalar, a list of 12 monthly values, or a time series of values for every time step
    fuel_type::String = "natural_gas", # "restrict_to": ["natural_gas", "landfill_bio_gas", "propane", "diesel_oil"]
    can_supply_steam_turbine::Bool = false,
    retire_in_optimal::Bool = false,
    fuel_renewable_energy_fraction::Real = get(FUEL_DEFAULTS["fuel_renewable_energy_fraction"],fuel_type,0),
    emissions_factor_lb_CO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_CO2_per_mmbtu"],fuel_type,0),
    emissions_factor_lb_NOx_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_NOx_per_mmbtu"],fuel_type,0),
    emissions_factor_lb_SO2_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_SO2_per_mmbtu"],fuel_type,0),
    emissions_factor_lb_PM25_per_mmbtu::Real = get(FUEL_DEFAULTS["emissions_factor_lb_PM25_per_mmbtu"],fuel_type,0),
    time_steps_per_hour::Int = 1,
    can_serve_dhw::Bool = true,
    can_serve_space_heating::Bool = true,
    can_serve_process_heat::Bool = true
)
    @assert fuel_type in FUEL_TYPES
    @assert production_type in ["steam", "hot_water"]

    if isempty(fuel_cost_per_mmbtu)
        throw(@error("The ExistingBoiler.fuel_cost_per_mmbtu is a required input when modeling a heating load which is served by the Existing Boiler in the BAU case"))
    end

    if isnan(efficiency)
        efficiency = existing_boiler_efficiency_defaults[production_type]
    end

    max_kw = max_heat_demand_kw * max_thermal_factor_on_peak_load  # This is really the **actual** size in BAU

    installed_cost_per_kw = 0.0
    if !(installed_cost_per_mmbtu_per_hour == 0.0) && (installed_cost_dollars == 0.0)
        installed_cost_per_kw = installed_cost_per_mmbtu_per_hour / KWH_PER_MMBTU * max_thermal_factor_on_peak_load
    elseif !(installed_cost_per_mmbtu_per_hour == 0.0) && !(installed_cost_dollars == 0.0)
        throw(@error("A non-zero value for both installed_cost_per_mmbtu_per_hour and installed_cost_dollars was input for ExistingBoiler; only provide one or the other"))
    end

    ExistingBoiler(
        max_kw,
        production_type,
        max_thermal_factor_on_peak_load,
        installed_cost_per_kw,
        installed_cost_dollars,
        efficiency,
        fuel_cost_per_mmbtu,
        fuel_type,
        can_supply_steam_turbine,
        retire_in_optimal,
        fuel_renewable_energy_fraction,
        emissions_factor_lb_CO2_per_mmbtu,
        emissions_factor_lb_NOx_per_mmbtu,
        emissions_factor_lb_SO2_per_mmbtu,
        emissions_factor_lb_PM25_per_mmbtu,
        can_serve_dhw,
        can_serve_space_heating,
        can_serve_process_heat
    )
end
