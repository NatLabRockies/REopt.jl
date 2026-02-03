# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
struct MPCScenario <: AbstractScenario
    settings::Settings
    site::MPCSite
    pvs::Array{MPCPV, 1}
    wind::MPCWind
    storage::Storage
    electric_tariff::MPCElectricTariff
    electric_load::MPCElectricLoad
    electric_utility::ElectricUtility
    financial::MPCFinancial
    generator::MPCGenerator
    cooling_load::MPCCoolingLoad
    dhw_load::MPCDomesticHotWaterLoad
    space_heating_load::MPCSpaceHeatingLoad
    process_heat_load::MPCProcessHeatLoad
    electric_heater::MPCElectricHeater
    electrolyzer::MPCElectrolyzer
    fuel_cell::MPCFuelCell
    hydrogen_load::MPCHydrogenLoad
    compressor::MPCCompressor
    flexible_hvac::Union{FlexibleHVAC, Nothing}
    limits::MPCLimits
    node::Int
end


"""
    MPCScenario(d::Dict)

Method for creating the MPCScenario struct:
```julia
    struct MPCScenario <: AbstractScenario
        settings::Settings
        site::MPCSite
        pvs::Array{MPCPV, 1}
        wind::MPCWind
        storage::Storage
        electric_tariff::MPCElectricTariff
        electric_load::MPCElectricLoad
        electric_utility::ElectricUtility
        financial::MPCFinancial
        generator::MPCGenerator
        cooling_load::MPCCoolingLoad
        dhw_load::MPCDomesticHotWaterLoad
        space_heating_load::MPCSpaceHeatingLoad
        process_heat_load::MPCProcessHeatLoad
        electric_heater::MPCElectricHeater
        electrolyzer::MPCElectrolyzer
        fuel_cell::MPCFuelCell
        hydrogen_load::MPCHydrogenLoad
        compressor::MPCCompressor
        flexible_hvac::Union{FlexibleHVAC, Nothing}
        limits::MPCLimits
        node::Int
    end
```

The Dict `d` must have at a minimum the keys:
    - "ElectricLoad"
    - "ElectricTariff"

Other options include:
    - "PV", which can contain a Dict or Dict[]
    - "Wind"
    - "ElectricStorage"
    - "Generator"
    - "ProcessHeatLoad"
    - "HighTempThermalStorage"
    - "ElectricHeater"
    - "Electrolyzer"
    - "HydrogenStorage"
    - "FuelCell"
    - "HydrogenLoad"
    - "Compressor"
    - "ElectricUtility"
    - "Settings"
    - "Financial"
    - "Limits"
    - "Site"
"""
function MPCScenario(d::Dict)
    if haskey(d, "Settings")
        settings = Settings(;dictkeys_tosymbols(d["Settings"])...)
    else
        settings = Settings()
    end

    if haskey(d, "Site")
        site = MPCSite(;dictkeys_tosymbols(d["Site"])...)
    else
        site = MPCSite()
    end
    
    pvs = MPCPV[]
    if haskey(d, "PV")
        if typeof(d["PV"]) <: AbstractArray
            for (i, pv) in enumerate(d["PV"])
                if !(haskey(pv, "name"))
                    pv["name"] = string("PV", i)
                end
                push!(pvs, MPCPV(;dictkeys_tosymbols(pv)...))
            end
        elseif typeof(d["PV"]) <: AbstractDict
            push!(pvs, MPCPV(;dictkeys_tosymbols(d["PV"])...))
        else
            throw(@error("PV input must be Dict or Dict[]."))
        end
    end

    if haskey(d, "Financial")
        financial = MPCFinancial(; dictkeys_tosymbols(d["Financial"])...)
    else
        financial = MPCFinancial()
    end

    if settings.off_grid_flag
        if !(haskey(d["ElectricLoad"], "critical_loads_kw"))
            @warn "ElectricLoad critical_loads_kw is overridden by loads_kw in off-grid scenarios. If you wish to alter the load profile or load met, adjust the loads_kw or min_load_met_annual_fraction."
            d["ElectricLoad"]["critical_loads_kw"] = d["ElectricLoad"]["loads_kw"]
        end
    end

    electric_load = MPCElectricLoad(; dictkeys_tosymbols(d["ElectricLoad"])...)

    if settings.off_grid_flag
        if haskey(d, "ElectricUtility")
            @warn "ElectricUtility inputs are not applicable when `off_grid_flag` is true and will be ignored."
        end
        electric_utility = ElectricUtility(; outage_start_time_step = 1, 
                                            outage_end_time_step = length(electric_load.loads_kw), 
                                            time_steps_per_hour=settings.time_steps_per_hour,
                                            off_grid_flag=settings.off_grid_flag,
                                            emissions_factor_series_lb_CO2_per_kwh = 0,
                                            emissions_factor_series_lb_NOx_per_kwh = 0,
                                            emissions_factor_series_lb_SO2_per_kwh = 0,
                                            emissions_factor_series_lb_PM25_per_kwh = 0,
                                            mpc_timesteps = length(d["ElectricLoad"]["loads_kw"])
                                        ) 
    else
        if haskey(d, "ElectricUtility")
            electric_utility = ElectricUtility(; dictkeys_tosymbols(d["ElectricUtility"])...,
                                                time_steps_per_hour=settings.time_steps_per_hour,
                                                off_grid_flag=settings.off_grid_flag,
                                                mpc_timesteps = length(d["ElectricLoad"]["loads_kw"]))
        else
            electric_utility = ElectricUtility(time_steps_per_hour=settings.time_steps_per_hour,
                                                off_grid_flag=settings.off_grid_flag,
                                                mpc_timesteps = length(d["ElectricLoad"]["loads_kw"]))
        end
    end

    storage_structs = Dict{String, AbstractStorage}()
    if haskey(d, "ElectricStorage")
        storage_dict = Dict(dictkeys_tosymbols(d["ElectricStorage"]))
    else
        storage_dict = Dict(:size_kw => 0.0, :size_kwh => 0.0)
    end
    storage_structs["ElectricStorage"] = MPCElectricStorage(; storage_dict...)

    if haskey(d, "HydrogenStorage")
        storage_structs["HydrogenStorage"] = MPCHydrogenStorage(; dictkeys_tosymbols(d["HydrogenStorage"])...)
    end

    if haskey(d, "HighTempThermalStorage")
       storage_structs["HighTempThermalStorage"] = MPCHighTempThermalStorage(; dictkeys_tosymbols(d["HighTempThermalStorage"])...)
    end

    storage = Storage(storage_structs)
   
    if !(settings.off_grid_flag)
        electric_tariff = MPCElectricTariff(d["ElectricTariff"])
    else
        tariff_dict = Dict([("energy_rates", zeros(length(electric_load.loads_kw)))])
        electric_tariff = MPCElectricTariff(tariff_dict)
    end

    if haskey(d, "Wind")
        wind = MPCWind(; dictkeys_tosymbols(d["Wind"])...)
    else
        wind = MPCWind(; size_kw=0)
    end

    if haskey(d, "Generator")
        generator = MPCGenerator(; dictkeys_tosymbols(d["Generator"])...)
    else
        generator = MPCGenerator(; size_kw=0)
    end

    if haskey(d, "ProcessHeatLoad")
        process_heat_load = MPCProcessHeatLoad(; dictkeys_tosymbols(d["ProcessHeatLoad"])...)
    else
        process_heat_load = MPCProcessHeatLoad()
    end

    if haskey(d, "ElectricHeater")
        electric_heater = MPCElectricHeater(; dictkeys_tosymbols(d["ElectricHeater"])...)
    else
        electric_heater = MPCElectricHeater(; size_mmbtu_per_hour=0)
    end

    if haskey(d, "Electrolyzer")
        electrolyzer = MPCElectrolyzer(; dictkeys_tosymbols(d["Electrolyzer"])...)
        if !electrolyzer.require_compression
            compressor = MPCCompressor(; size_kw = 0.0, 
                                      om_cost_per_kw = 0.0,
                                      om_cost_per_kwh = 0.0,
                                      efficiency_kwh_per_kg = 0.0
            )
        else
            if haskey(d, "Compressor")
                compressor = MPCCompressor(; dictkeys_tosymbols(d["Compressor"])...)
            else
                throw(@error("Must include Compressor size or set require_compression in Electrolyzer as true"))
            end
        end
    else
        electrolyzer = MPCElectrolyzer(; size_kw = 0)
        compressor = MPCCompressor(; size_kw = 0)
    end

    if haskey(d, "FuelCell")
        fuel_cell = MPCFuelCell(; dictkeys_tosymbols(d["FuelCell"])...)
    else
        fuel_cell = MPCFuelCell(; size_kw=0)
    end

    if haskey(d, "HydrogenLoad")
        hydrogen_load = MPCHydrogenLoad(; dictkeys_tosymbols(d["HydrogenLoad"])...)
    else
        hydrogen_load = MPCHydrogenLoad(; loads_kg = zeros(length(electric_load.loads_kw)))
    end

    # Placeholder/dummy cooling load set to zeros
    cooling_load = MPCCoolingLoad(; loads_kw_thermal = zeros(length(electric_load.loads_kw)), cop=1.0)
    dhw_load = MPCDomesticHotWaterLoad(; loads_kw_thermal = zeros(length(electric_load.loads_kw)))
    space_heating_load = MPCSpaceHeatingLoad(; loads_kw_thermal = zeros(length(electric_load.loads_kw)))
    flexible_hvac = nothing

    if haskey(d, "Limits")
        limits = MPCLimits(; dictkeys_tosymbols(d["Limits"])...)
    else
        limits = MPCLimits()
    end

    if haskey(d, "node")
        node = d["node"]
    else
        node = 1
    end

    return MPCScenario(
        settings,
        site,
        pvs, 
        wind,
        storage, 
        electric_tariff, 
        electric_load, 
        electric_utility, 
        financial,
        generator,
        cooling_load,
        dhw_load,
        space_heating_load,
        process_heat_load,
        electric_heater,
        electrolyzer,
        fuel_cell,
        hydrogen_load,
        compressor,
        flexible_hvac,
        limits,
        node
    )
end
