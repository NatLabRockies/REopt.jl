# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
abstract type AbstractTech end
abstract type AbstractStorage end
abstract type AbstractFuelBurningTech <: AbstractTech end
abstract type AbstractGenerator <: AbstractFuelBurningTech end
abstract type AbstractScenario end
abstract type AbstractInputs end
abstract type AbstractThermalTech <: AbstractGenerator end
abstract type AbstractCHP <: AbstractFuelBurningTech end
abstract type AbstractThermalStorage <: AbstractStorage end
abstract type AbstractElectricStorage <: AbstractStorage end
abstract type AbstractThermalStorageDefaults end
abstract type AbstractGHP <: AbstractTech end
abstract type AbstractSteamTurbine <: AbstractTech end


"""
    Techs

`Techs` contains the index sets that are used to define the model constraints and decision variables.

```julia
mutable struct Techs
    all::Vector{String}
    elec::Vector{String}
    pv::Vector{String}
    gen::Vector{String}
    pbi::Vector{String}
    no_curtail::Vector{String}
    no_turndown::Vector{String}
    segmented::Vector{String}
    heating::Vector{String}
    cooling::Vector{String}
    boiler::Vector{String}
    fuel_burning::Vector{String}
    thermal::Vector{String}
    chp::Vector{String}
    requiring_oper_res::Vector{String}
    providing_oper_res::Vector{String}
    electric_chiller::Vector{String}
    absorption_chiller::Vector{String}
    steam_turbine::Vector{String}
    can_supply_steam_turbine::Vector{String}
    electric_heater::Vector{String}    
    can_serve_space_heating::Vector{String}
    can_serve_dhw::Vector{String}
    can_serve_process_heat::Vector{String}
    ghp::Vector{String}
    ashp::Vector{String}
    ashp_wh::Vector{String}
end
```
"""
mutable struct Techs
    all::Vector{String}
    elec::Vector{String}
    pv::Vector{String}
    gen::Vector{String}
    pbi::Vector{String}
    no_curtail::Vector{String}
    no_turndown::Vector{String}
    segmented::Vector{String}
    heating::Vector{String}
    cooling::Vector{String}
    boiler::Vector{String}
    fuel_burning::Vector{String}
    thermal::Vector{String}
    chp::Vector{String}
    requiring_oper_res::Vector{String}
    providing_oper_res::Vector{String}
    electric_chiller::Vector{String}
    absorption_chiller::Vector{String}
    steam_turbine::Vector{String}
    can_supply_steam_turbine::Vector{String}
    electric_heater::Vector{String}
    can_serve_space_heating::Vector{String}
    can_serve_dhw::Vector{String}
    can_serve_process_heat::Vector{String}
    ghp::Vector{String}
    ashp::Vector{String}
    ashp_wh::Vector{String}
end
