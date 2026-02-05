# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
struct Scenario <: AbstractScenario
    settings::Settings
    site::Site
    pvs::Array{PV, 1}
    wind::Wind
    storage::Storage
    electric_tariff::ElectricTariff
    electric_load::ElectricLoad
    electric_utility::ElectricUtility
    financial::Financial
    generator::Generator
    dhw_load::DomesticHotWaterLoad
    space_heating_load::SpaceHeatingLoad
    process_heat_load::ProcessHeatLoad
    cooling_load::CoolingLoad
    existing_boiler::Union{ExistingBoiler, Nothing}
    boiler::Union{Boiler, Nothing}
    chp::Union{CHP, Nothing}  # use nothing for more items when they are not modeled?
    flexible_hvac::Union{FlexibleHVAC, Nothing}
    existing_chiller::Union{ExistingChiller, Nothing}
    absorption_chiller::Union{AbsorptionChiller, Nothing}
    ghp_option_list::Array{Union{GHP, Nothing}, 1}  # List of GHP objects (often just 1 element, but can be more)
    space_heating_thermal_load_reduction_with_ghp_kw::Union{Vector{Float64}, Nothing}
    cooling_thermal_load_reduction_with_ghp_kw::Union{Vector{Float64}, Nothing}
    steam_turbine::Union{SteamTurbine, Nothing}
    electric_heater::Union{ElectricHeater, Nothing}
    cst::Union{CST, Nothing}
    ashp::Union{ASHP, Nothing}
    ashp_wh::Union{ASHP, Nothing}
end

"""
    Scenario(d::Dict; flex_hvac_from_json=false)

A Scenario struct can contain the following keys:
- [Site](@ref) (required)
- [Financial](@ref) (optional)
- [ElectricTariff](@ref) (required when `off_grid_flag=false`)
- [ElectricLoad](@ref) (required)
- [PV](@ref) (optional, can be Array)
- [Wind](@ref) (optional)
- [ElectricStorage](@ref) (optional)
- [HotThermalStorage](@ref) (optional)
- [HighTempThermalStorage](@ref) (optional)
- [ColdThermalStorage](@ref) (optional)
- [ElectricStorage](@ref) (optional)
- [ElectricUtility](@ref) (optional)
- [Generator](@ref) (optional)
- [HeatingLoad](@ref) (optional)
- [CoolingLoad](@ref) (optional)
- [ExistingBoiler](@ref) (optional)
- [Boiler](@ref) (optional)
- [CHP](@ref) (optional)
- [FlexibleHVAC](@ref) (optional)
- [ExistingChiller](@ref) (optional)
- [AbsorptionChiller](@ref) (optional)
- [GHP](@ref) (optional, can be Array)
- [SteamTurbine](@ref) (optional)
- [ElectricHeater](@ref) (optional)
- [CST](@ref) (optional)
- [ASHPSpaceHeater](@ref) (optional)
- [ASHPWaterHeater](@ref) (optional)

All values of `d` are expected to be `Dicts` except for `PV` and `GHP`, which can be either a `Dict` or `Dict[]` (for multiple PV arrays or GHP options).

!!! note 
    Set `flex_hvac_from_json=true` if `FlexibleHVAC` values were loaded in from JSON (necessary to 
    handle conversion of Vector of Vectors from JSON to a Matrix in Julia).
"""
function Scenario(d::Dict; flex_hvac_from_json=false)

    instantiate_logger()

    d = deepcopy(d)
    if haskey(d, "Settings")
        settings = Settings(;dictkeys_tosymbols(d["Settings"])...)
    else
        settings = Settings()
    end
    
    site = Site(;dictkeys_tosymbols(d["Site"])...)

    # Check that only PV, electric storage, and generator are modeled for off-grid
    if settings.off_grid_flag
        offgrid_allowed_keys = ["PV", "Wind", "ElectricStorage", "Generator", "CHP", "Settings", "Site", "Financial", "ElectricLoad", "ElectricTariff", "ElectricUtility"]
        unallowed_keys = setdiff(keys(d), offgrid_allowed_keys) 
        if !isempty(unallowed_keys)
            throw(@error("The following key(s) are not permitted when `off_grid_flag` is true: $unallowed_keys."))
        end
    end

    # json parsing may make monthly_peaks_kw and monthly_totals_kwh type Vector{Any} instead of Vector{<:Real}
    if haskey(d["ElectricLoad"], "monthly_peaks_kw")
        d["ElectricLoad"]["monthly_peaks_kw"] = convert(Vector{Float64}, d["ElectricLoad"]["monthly_peaks_kw"])
    end
    if haskey(d["ElectricLoad"], "monthly_totals_kwh")
        d["ElectricLoad"]["monthly_totals_kwh"] = convert(Vector{Float64}, d["ElectricLoad"]["monthly_totals_kwh"])
    end

    electric_load = ElectricLoad(; dictkeys_tosymbols(d["ElectricLoad"])...,
    latitude=site.latitude, longitude=site.longitude, 
    time_steps_per_hour=settings.time_steps_per_hour,
    off_grid_flag = settings.off_grid_flag
    )
    
    pvs = PV[]
    electric_load_annual_kwh = sum(electric_load.loads_kw) / settings.time_steps_per_hour
    if haskey(d, "PV")
        if typeof(d["PV"]) <: AbstractArray
            for (i, pv) in enumerate(d["PV"])
                if !(haskey(pv, "name"))
                    pv["name"] = string("PV", i)
                end
                push!(pvs, PV(
                    ; dictkeys_tosymbols(pv)...,
                    off_grid_flag = settings.off_grid_flag, 
                    sector = site.sector,
                    federal_procurement_type = site.federal_procurement_type,
                    latitude = site.latitude,
                    electric_load_annual_kwh = electric_load_annual_kwh,
                    site_land_acres = site.land_acres,
                    site_roof_squarefeet = site.roof_squarefeet
                ))
            end
        elseif typeof(d["PV"]) <: AbstractDict
            push!(pvs, PV(
                ; dictkeys_tosymbols(d["PV"])..., 
                off_grid_flag = settings.off_grid_flag, 
                sector = site.sector,
                federal_procurement_type = site.federal_procurement_type,
                latitude = site.latitude,
                electric_load_annual_kwh = electric_load_annual_kwh,
                site_land_acres = site.land_acres,
                site_roof_squarefeet = site.roof_squarefeet
            ))
        else
            throw(@error("PV input must be Dict or Dict[]."))
        end
    end

    if haskey(d, "Financial")
        financial = Financial(; dictkeys_tosymbols(d["Financial"])...,
                                latitude=site.latitude, longitude=site.longitude, 
                                off_grid_flag = settings.off_grid_flag,
                                include_health_in_objective = settings.include_health_in_objective,
                                sector = site.sector,
                                federal_procurement_type = site.federal_procurement_type,
                                federal_sector_state = site.federal_sector_state
                            )
    else
        financial = Financial(; latitude=site.latitude, longitude=site.longitude,
                                off_grid_flag = settings.off_grid_flag,
                                include_health_in_objective = settings.include_health_in_objective,
                                sector = site.sector,
                                federal_procurement_type = site.federal_procurement_type,
                                federal_sector_state = site.federal_sector_state
                            )
    end



    if haskey(d, "ElectricUtility") && !(settings.off_grid_flag)
        electric_utility = ElectricUtility(; dictkeys_tosymbols(d["ElectricUtility"])...,
                                            latitude=site.latitude, longitude=site.longitude, 
                                            CO2_emissions_reduction_min_fraction=site.CO2_emissions_reduction_min_fraction,
                                            CO2_emissions_reduction_max_fraction=site.CO2_emissions_reduction_max_fraction,
                                            min_resil_time_steps=site.min_resil_time_steps,
                                            include_climate_in_objective=settings.include_climate_in_objective,
                                            include_health_in_objective=settings.include_health_in_objective,
                                            off_grid_flag=settings.off_grid_flag,
                                            time_steps_per_hour=settings.time_steps_per_hour,
                                            analysis_years=financial.analysis_years,
                                            load_year=electric_load.year
                                        )
    elseif !(settings.off_grid_flag)
        electric_utility = ElectricUtility(; latitude=site.latitude, longitude=site.longitude, 
                                            CO2_emissions_reduction_min_fraction=site.CO2_emissions_reduction_min_fraction,
                                            CO2_emissions_reduction_max_fraction=site.CO2_emissions_reduction_max_fraction,
                                            include_climate_in_objective=settings.include_climate_in_objective,
                                            include_health_in_objective=settings.include_health_in_objective,
                                            off_grid_flag=settings.off_grid_flag,
                                            time_steps_per_hour=settings.time_steps_per_hour,
                                            analysis_years=financial.analysis_years,
                                            load_year=electric_load.year
                                        )
    elseif settings.off_grid_flag 
        if haskey(d, "ElectricUtility")
            @warn "ElectricUtility inputs are not applicable when `off_grid_flag` is true and will be ignored. For off-grid scenarios, a year-long outage will always be modeled."
        end
        electric_utility = ElectricUtility(; outage_start_time_step = 1, 
                                            outage_end_time_step = settings.time_steps_per_hour * 8760, 
                                            latitude=site.latitude, longitude=site.longitude, 
                                            time_steps_per_hour=settings.time_steps_per_hour,
                                            off_grid_flag=settings.off_grid_flag,
                                            emissions_factor_series_lb_CO2_per_kwh = 0,
                                            emissions_factor_series_lb_NOx_per_kwh = 0,
                                            emissions_factor_series_lb_SO2_per_kwh = 0,
                                            emissions_factor_series_lb_PM25_per_kwh = 0,
                                            renewable_energy_fraction_series = 0
                                        ) 
    end
        
    storage_structs = Dict{String, AbstractStorage}()
    if haskey(d,  "ElectricStorage")
        storage_dict = dictkeys_tosymbols(d["ElectricStorage"])
        storage_dict[:off_grid_flag] = settings.off_grid_flag
    else
        storage_dict = Dict(:max_kw => 0.0)
    end
    storage_structs["ElectricStorage"] = ElectricStorage(storage_dict, financial, site)
    # TODO stop building ElectricStorage when it is not modeled by user 
    #       (requires significant changes to constraints, variables)
    if haskey(d, "HotThermalStorage")
        storage_structs["HotThermalStorage"] = HotThermalStorage(
                                                    dictkeys_tosymbols(d["HotThermalStorage"]), 
                                                    financial, site, settings.time_steps_per_hour
                                                )
    end
    if haskey(d, "HighTempThermalStorage")
        storage_structs["HighTempThermalStorage"] = HighTempThermalStorage(
                                                        dictkeys_tosymbols(d["HighTempThermalStorage"]), 
                                                        financial, site, settings.time_steps_per_hour
                                                    )
    end
    if haskey(d, "ColdThermalStorage")
        storage_structs["ColdThermalStorage"] = ColdThermalStorage(
                                                    dictkeys_tosymbols(d["ColdThermalStorage"]), 
                                                    financial, site, settings.time_steps_per_hour
                                                )
    end
    storage = Storage(storage_structs)

    if haskey(d, "Wind")
        wind = Wind(; dictkeys_tosymbols(d["Wind"])..., off_grid_flag=settings.off_grid_flag,
                    sector = site.sector, federal_procurement_type = site.federal_procurement_type,
                    average_elec_load=sum(electric_load.loads_kw) / length(electric_load.loads_kw))
    else
        wind = Wind(; max_kw=0)
    end

    if haskey(d, "Generator")
        generator = Generator(; dictkeys_tosymbols(d["Generator"])..., off_grid_flag=settings.off_grid_flag, analysis_years=financial.analysis_years)
    else
        generator = Generator(; max_kw=0)
    end

    total_heating_load_series_kw = zeros(8760 * settings.time_steps_per_hour)

    if haskey(d, "DomesticHotWaterLoad") && !haskey(d, "FlexibleHVAC")
        add_doe_reference_names_from_elec_to_thermal_loads(d["ElectricLoad"], d["DomesticHotWaterLoad"])
        existing_boiler_efficiency = get_existing_boiler_efficiency(d)
        year = get!(d["DomesticHotWaterLoad"], "year", electric_load.year)
        validate_load_year_consistency(electric_load.year, year, "DomesticHotWaterLoad")
        dhw_load = HeatingLoad(; dictkeys_tosymbols(d["DomesticHotWaterLoad"])...,
                                        load_type = "domestic_hot_water",
                                        latitude=site.latitude, longitude=site.longitude, 
                                        time_steps_per_hour=settings.time_steps_per_hour,
                                        existing_boiler_efficiency = existing_boiler_efficiency
                                        )
        total_heating_load_series_kw .+= dhw_load.loads_kw
    else
        dhw_load = HeatingLoad(;
            load_type = "domestic_hot_water", 
            fuel_loads_mmbtu_per_hour=zeros(8760*settings.time_steps_per_hour),
            time_steps_per_hour=settings.time_steps_per_hour,
            existing_boiler_efficiency = EXISTING_BOILER_EFFICIENCY,
            year=electric_load.year
        )
    end

    if haskey(d, "SpaceHeatingLoad") && !haskey(d, "FlexibleHVAC")
        add_doe_reference_names_from_elec_to_thermal_loads(d["ElectricLoad"], d["SpaceHeatingLoad"])
        existing_boiler_efficiency = get_existing_boiler_efficiency(d)
        year = get!(d["SpaceHeatingLoad"], "year", electric_load.year)
        validate_load_year_consistency(electric_load.year, year, "SpaceHeatingLoad")
        space_heating_load = HeatingLoad(; dictkeys_tosymbols(d["SpaceHeatingLoad"])...,
                                            load_type = "space_heating",
                                            latitude=site.latitude, longitude=site.longitude, 
                                            time_steps_per_hour=settings.time_steps_per_hour,
                                            existing_boiler_efficiency = existing_boiler_efficiency
                                            )
        total_heating_load_series_kw .+= space_heating_load.loads_kw
    else
        space_heating_load = HeatingLoad(; 
            load_type = "space_heating",        
            fuel_loads_mmbtu_per_hour=zeros(8760*settings.time_steps_per_hour),
            time_steps_per_hour=settings.time_steps_per_hour,
            existing_boiler_efficiency = EXISTING_BOILER_EFFICIENCY,
            year=electric_load.year
        )
    end

    if haskey(d, "ProcessHeatLoad") && !haskey(d, "FlexibleHVAC")
        existing_boiler_efficiency = get_existing_boiler_efficiency(d)
        year = get!(d["ProcessHeatLoad"], "year", electric_load.year)
        validate_load_year_consistency(electric_load.year, year, "ProcessHeatLoad")
        process_heat_load = HeatingLoad(; dictkeys_tosymbols(d["ProcessHeatLoad"])...,
                                            load_type = "process_heat",
                                            latitude = site.latitude, longitude = site.longitude, 
                                            time_steps_per_hour = settings.time_steps_per_hour,
                                            existing_boiler_efficiency = existing_boiler_efficiency                                           
                                            )
                                    
        total_heating_load_series_kw .+= process_heat_load.loads_kw
    else
        process_heat_load = HeatingLoad(;
                load_type = "process_heat",                
                fuel_loads_mmbtu_per_hour=zeros(8760*settings.time_steps_per_hour),
                time_steps_per_hour=settings.time_steps_per_hour,
                existing_boiler_efficiency = EXISTING_BOILER_EFFICIENCY,
                year=electric_load.year
        )
    end

    flexible_hvac = nothing
    existing_boiler = nothing
    boiler = nothing
    existing_chiller = nothing

    if haskey(d, "FlexibleHVAC")
        # TODO how to handle Matrix from JSON (to Dict) ?
        if flex_hvac_from_json
            flexible_hvac = FlexibleHVAC(d["FlexibleHVAC"])
        else
            flexible_hvac = FlexibleHVAC(; dictkeys_tosymbols(d["FlexibleHVAC"])...)
        end

        if sum(flexible_hvac.bau_hvac.existing_boiler_kw_thermal) ≈ 0.0 && 
            sum(flexible_hvac.bau_hvac.existing_chiller_kw_thermal) ≈ 0.0
            @warn "The FlexibleHVAC inputs indicate that no heating nor cooling is required. Not creating FlexibleHVAC model."
            flexible_hvac = nothing
        else
            # ExistingChiller and/or ExistingBoiler are added based on BAU_HVAC energy required to keep temperature within bounds
            if sum(flexible_hvac.bau_hvac.existing_boiler_kw_thermal) > 0
                boiler_inputs = Dict{Symbol, Any}()
                boiler_inputs[:max_heat_demand_kw] = maximum(flexible_hvac.bau_hvac.existing_boiler_kw_thermal)
                boiler_inputs[:time_steps_per_hour] = settings.time_steps_per_hour
                if haskey(d, "ExistingBoiler")
                    boiler_inputs = merge(boiler_inputs, dictkeys_tosymbols(d["ExistingBoiler"]))
                end
                existing_boiler = ExistingBoiler(; boiler_inputs...)

                if haskey(d, "Boiler")
                    boiler = Boiler(; dictkeys_tosymbols(d["Boiler"])...)
                end
                # TODO increase max_thermal_factor_on_peak_load to allow more heating flexibility?
            elseif haskey(d, "Boiler")
                @warn("Not creating Boiler because there is no heating load.") 
            end

            if sum(flexible_hvac.bau_hvac.existing_chiller_kw_thermal) > 0
                chiller_inputs = Dict{Symbol, Any}()
                chiller_inputs[:loads_kw_thermal] = flexible_hvac.bau_hvac.existing_chiller_kw_thermal                                 
                if haskey(d, "ExistingChiller")
                    if !haskey(d["ExistingChiller"], "cop")
                        d["ExistingChiller"]["cop"] = get_existing_chiller_default_cop(; existing_chiller_max_thermal_factor_on_peak_load=1.25, 
                                                                                max_load_kw=nothing, 
                                                                                max_load_kw_thermal=maximum(chiller_inputs[:loads_kw_thermal]))
                    end 
                    chiller_inputs = merge(chiller_inputs, dictkeys_tosymbols(d["ExistingChiller"]))
                else
                    chiller_inputs[:cop] = get_existing_chiller_default_cop(; existing_chiller_max_thermal_factor_on_peak_load=1.25, 
                                                                                max_load_kw=nothing, 
                                                                                max_load_kw_thermal=maximum(chiller_inputs[:loads_kw_thermal]))
                end              
                existing_chiller = ExistingChiller(; chiller_inputs...)
            end

            if haskey(d, "SpaceHeatingLoad")
                @warn "Not using SpaceHeatingLoad because FlexibleHVAC was provided."
            end

            if haskey(d, "DomesticHotWaterLoad")
                @warn "Not using DomesticHotWaterLoad because FlexibleHVAC was provided."
            end

            if haskey(d, "ProcessHeatLoad")
                @warn "Not using ProcessHeatLoad because FlexibleHVAC was provided."
            end

            if haskey(d, "CoolingLoad")
                @warn "Not using CoolingLoad because FlexibleHVAC was provided."
            end
        end
    end

    max_heat_demand_kw = maximum(total_heating_load_series_kw)
    if max_heat_demand_kw > 0 && !haskey(d, "FlexibleHVAC")  # create ExistingBoiler
        boiler_inputs = Dict{Symbol, Any}()
        boiler_inputs[:max_heat_demand_kw] = max_heat_demand_kw
        boiler_inputs[:time_steps_per_hour] = settings.time_steps_per_hour
        if haskey(d, "ExistingBoiler")
            boiler_inputs = merge(boiler_inputs, dictkeys_tosymbols(d["ExistingBoiler"]))
        else
            throw(@error("Must include ExistingBoiler input with at least fuel_cost_per_mmbtu if modeling heating load"))
        end
        existing_boiler = ExistingBoiler(; boiler_inputs...)
    end

    if haskey(d, "Boiler")
        if max_heat_demand_kw > 0 && !haskey(d, "FlexibleHVAC")
            boiler = Boiler(; dictkeys_tosymbols(d["Boiler"])...)
        end
        if !(max_heat_demand_kw > 0) && !haskey(d, "FlexibleHVAC")
            @warn("Not creating Boiler because there is no heating load.")
        end
    end


    chp = nothing
    chp_prime_mover = nothing
    if haskey(d, "CHP")
        electric_only = get(d["CHP"], "is_electric_only", false) || get(d["CHP"], "thermal_efficiency_full_load", 0.5) == 0.0
        if !isnothing(existing_boiler) && !electric_only
            total_fuel_heating_load_mmbtu_per_hour = (space_heating_load.loads_kw + dhw_load.loads_kw + process_heat_load.loads_kw) / existing_boiler.efficiency / KWH_PER_MMBTU
            avg_boiler_fuel_load_mmbtu_per_hour = sum(total_fuel_heating_load_mmbtu_per_hour) / length(total_fuel_heating_load_mmbtu_per_hour)
            chp = CHP(d["CHP"]; 
                    avg_boiler_fuel_load_mmbtu_per_hour = avg_boiler_fuel_load_mmbtu_per_hour,
                    existing_boiler = existing_boiler,
                    electric_load_series_kw = electric_load.loads_kw,
                    year = electric_load.year,
                    sector = site.sector,
                    federal_procurement_type = site.federal_procurement_type,
                    off_grid_flag = settings.off_grid_flag)
        else # Only if modeling CHP without heating_load and existing_boiler (for prime generator, electric-only)
            chp = CHP(d["CHP"];
                    electric_load_series_kw = electric_load.loads_kw,
                    year = electric_load.year,
                    sector = site.sector,
                    federal_procurement_type = site.federal_procurement_type,
                    off_grid_flag = settings.off_grid_flag)
        end
        chp_prime_mover = chp.prime_mover
    end

    max_cooling_demand_kw = 0
    if haskey(d, "CoolingLoad") && !haskey(d, "FlexibleHVAC")
        d["CoolingLoad"] = convert(Dict{String, Any}, d["CoolingLoad"])
        # Note, if thermal_loads_ton or one of the "...fraction(s)_of_electric_load" inputs is used for CoolingLoad, doe_reference_name is ignored 
        add_doe_reference_names_from_elec_to_thermal_loads(d["ElectricLoad"], d["CoolingLoad"])
        d["CoolingLoad"]["site_electric_load_profile"] = electric_load.loads_kw
        # Pass ExistingChiller inputs which are used in CoolingLoad processing, if they exist
        ec_empty = ExistingChiller(; loads_kw_thermal=zeros(8760*settings.time_steps_per_hour))
        if !haskey(d, "ExistingChiller")
            d["CoolingLoad"]["existing_chiller_max_thermal_factor_on_peak_load"] = ec_empty.max_thermal_factor_on_peak_load
        else
            if haskey(d["ExistingChiller"], "cop")
                d["CoolingLoad"]["existing_chiller_cop"] = d["ExistingChiller"]["cop"]
            end
            if haskey(d["ExistingChiller"], "max_thermal_factor_on_peak_load")
                d["CoolingLoad"]["existing_chiller_max_thermal_factor_on_peak_load"] = d["ExistingChiller"]["max_thermal_factor_on_peak_load"]
            else
                d["CoolingLoad"]["existing_chiller_max_thermal_factor_on_peak_load"] = ec_empty.max_thermal_factor_on_peak_load
            end
        end
        year = get!(d["CoolingLoad"], "year", electric_load.year)
        validate_load_year_consistency(electric_load.year, year, "CoolingLoad")
        # If array inputs are coming from Julia JSON.parsefile (reader), they have type Vector{Any}; convert to expected type here
        cooling_type_convert = ["monthly_fractions_of_electric_load", "per_time_step_fractions_of_electric_load", 
                                "blended_doe_reference_percents", "monthly_tonhour", "thermal_loads_ton"]
        for (k,v) in d["CoolingLoad"]
            if typeof(v) <: AbstractVector{Any} && k in cooling_type_convert
                d["CoolingLoad"][k] = convert(Vector{Float64}, v)
            end
        end
        cooling_load = CoolingLoad(; dictkeys_tosymbols(d["CoolingLoad"])...,
                                    latitude=site.latitude, longitude=site.longitude, 
                                    time_steps_per_hour=settings.time_steps_per_hour
                                    )
        max_cooling_demand_kw = maximum(cooling_load.loads_kw_thermal)
    
        # Check if cooling electric load is greater than total electric load in any hour, and throw error if true with the violating time time_steps
        cooling_elec = cooling_load.loads_kw_thermal / cooling_load.existing_chiller_cop
        cooling_elec_too_high_timesteps = findall(cooling_elec .> electric_load.loads_kw)
        if length(cooling_elec_too_high_timesteps) > 0
            cooling_elec_too_high_kw = cooling_elec[cooling_elec_too_high_timesteps]
            total_elec_when_cooling_elec_too_high = electric_load.loads_kw[cooling_elec_too_high_timesteps]
            throw(@error("Cooling electric consumption cannot be more than the total electric load at any time step. At time steps 
                $cooling_elec_too_high_timesteps the cooling electric consumption is $cooling_elec_too_high_kw (kW) and
                the total electric load is $total_elec_when_cooling_elec_too_high (kW). Note you may consider adjusting 
                cooling load input versus the total electric load if you provided inputs in units of cooling tons, or 
                check the electric chiller COP input value."))
        end
    else
        cooling_load = CoolingLoad(; 
            thermal_loads_ton=zeros(8760*settings.time_steps_per_hour),
            time_steps_per_hour=settings.time_steps_per_hour,
            year=electric_load.year
        )
    end

    absorption_chiller = nothing
    if max_cooling_demand_kw > 0 && !haskey(d, "FlexibleHVAC")  # create ExistingChiller
        chiller_inputs = Dict{Symbol, Any}()
        chiller_inputs[:loads_kw_thermal] = cooling_load.loads_kw_thermal
        if haskey(d, "ExistingChiller")
            if !haskey(d["ExistingChiller"], "cop")
                d["ExistingChiller"]["cop"] = cooling_load.existing_chiller_cop
            end
            chiller_inputs = merge(chiller_inputs, dictkeys_tosymbols(d["ExistingChiller"]))
        else
            chiller_inputs[:cop] = cooling_load.existing_chiller_cop
        end
        existing_chiller = ExistingChiller(; chiller_inputs...)

        if haskey(d, "AbsorptionChiller")
            absorption_chiller = AbsorptionChiller(d["AbsorptionChiller"]; 
                                                    existing_boiler = existing_boiler,
                                                    chp_prime_mover = chp_prime_mover,
                                                    cooling_load = cooling_load)
        end
    end

    # GHP
    ambient_temp_celsius = nothing
    ghp_option_list = []
    space_heating_thermal_load_reduction_with_ghp_kw = zeros(8760 * settings.time_steps_per_hour)
    cooling_thermal_load_reduction_with_ghp_kw = zeros(8760 * settings.time_steps_per_hour)
    eval_ghp = false
    get_ghpghx_from_input = false
    if haskey(d, "GHP") && haskey(d["GHP"],"building_sqft")
        eval_ghp = true
        if haskey(d["GHP"], "ghpghx_responses") && !isempty(d["GHP"]["ghpghx_responses"])
            get_ghpghx_from_input = true
        end        
    elseif haskey(d, "GHP") && !haskey(d["GHP"],"building_sqft")
        throw(@error("If evaluating GHP you must enter a building_sqft."))
    end
    # Modify Heating and Cooling loads for GHP retrofit to account for HVAC VAV efficiency gains
    if eval_ghp
        # Assign efficiency_thermal_factors if not specified (and if applicable to building type and climate zone)
        for factor in [("space_heating_efficiency_thermal_factor", "space_heating"), ("cooling_efficiency_thermal_factor", "cooling")]
            if !(haskey(d["GHP"], factor[1]))
                nearest_city, climate_zone = assign_thermal_factor!(d, factor[2])
            end
        end
        space_heating_thermal_load_reduction_with_ghp_kw = space_heating_load.loads_kw * (1.0 - d["GHP"]["space_heating_efficiency_thermal_factor"])
        cooling_thermal_load_reduction_with_ghp_kw = cooling_load.loads_kw_thermal * (1.0 - d["GHP"]["cooling_efficiency_thermal_factor"])
    end
    # Call GhpGhx.jl module if only ghpghx_inputs is given, otherwise use ghpghx_responses
    if eval_ghp && !(get_ghpghx_from_input)
        if get(d["GHP"], "ghpghx_inputs", nothing) in [nothing, []]
            number_of_ghpghx = 1
            d["GHP"]["ghpghx_inputs"] = [Dict()]
        else
            number_of_ghpghx = length(d["GHP"]["ghpghx_inputs"])
        end
        # Call PVWatts for hourly dry-bulb outdoor air temperature
        ambient_temp_degF = []
        if (!haskey(d["GHP"]["ghpghx_inputs"][1], "ambient_temperature_f") || isempty(d["GHP"]["ghpghx_inputs"][1]["ambient_temperature_f"])) &&
            isnothing(site.outdoor_air_temperature_degF)
            # If PV is evaluated and we need to call PVWatts for ambient temperature, assign PV production factor here too with the same call
            # By assigning pv.production_factor_series here, it will skip the PVWatts call in get_production_factor(PV) call from reopt_input.jl
            if !isempty(pvs)
                for pv in pvs
                    pv.production_factor_series, ambient_temp_celsius = call_pvwatts_api(site.latitude, site.longitude; tilt=pv.tilt, azimuth=pv.azimuth, module_type=pv.module_type, 
                        array_type=pv.array_type, losses=round(pv.losses*100, digits=3), dc_ac_ratio=pv.dc_ac_ratio,
                        gcr=pv.gcr, inv_eff=pv.inv_eff*100, timeframe="hourly", radius=pv.radius, time_steps_per_hour=settings.time_steps_per_hour)
                end
            else
                pv_prodfactor, ambient_temp_celsius = call_pvwatts_api(site.latitude, site.longitude; time_steps_per_hour=settings.time_steps_per_hour)    
            end
            site.outdoor_air_temperature_degF = ambient_temp_celsius * 1.8 .+ 32.0
        elseif isnothing(site.outdoor_air_temperature_degF)
            site.outdoor_air_temperature_degF = d["GHP"]["ghpghx_inputs"][1]["ambient_temperature_f"]
        end
        
        for i in 1:number_of_ghpghx
            ghpghx_inputs = d["GHP"]["ghpghx_inputs"][i]
            d["GHP"]["ghpghx_inputs"][i]["ambient_temperature_f"] = site.outdoor_air_temperature_degF
            # Only SpaceHeating portion of Heating Load gets served by GHP, unless allowed by can_serve_dhw
            if get(ghpghx_inputs, "heating_thermal_load_mmbtu_per_hr", []) in [nothing, []]
                if get(d["GHP"], "can_serve_dhw", false)  # This is assuming the default stays false
                    ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"] = (space_heating_load.loads_kw + dhw_load.loads_kw - space_heating_thermal_load_reduction_with_ghp_kw)  / KWH_PER_MMBTU
                else
                    ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"] = (space_heating_load.loads_kw - space_heating_thermal_load_reduction_with_ghp_kw) / KWH_PER_MMBTU
                end
            end
            if get(ghpghx_inputs, "cooling_thermal_load_ton", []) in [nothing, []]
                ghpghx_inputs["cooling_thermal_load_ton"] = (cooling_load.loads_kw_thermal - cooling_thermal_load_reduction_with_ghp_kw)  / KWH_THERMAL_PER_TONHOUR
            end

            # Update ground thermal conductivity based on climate zone if not user-input
            if isnothing(get(ghpghx_inputs, "ground_thermal_conductivity_btu_per_hr_ft_f", nothing))
                k_by_zone = deepcopy(GhpGhx.ground_k_by_climate_zone)
                nearest_city, climate_zone = find_ashrae_zone_city(d["Site"]["latitude"], d["Site"]["longitude"]; get_zone=true)
                ghpghx_inputs["ground_thermal_conductivity_btu_per_hr_ft_f"] = k_by_zone[climate_zone]
            end

            aux_heater_type = get(d["GHP"], "aux_heater_type", nothing)
            
            start_time = now()

            ## Deal with hybrid
            hybrid_ghx_sizing_method = get(ghpghx_inputs, "hybrid_ghx_sizing_method", nothing)

            is_ghx_hybrid = false
            hybrid_sizing_flag = nothing
            is_heating_electric = nothing

            if hybrid_ghx_sizing_method == "Automatic"

                # Call GhpGhx.jl to size GHP and GHX in non-hybrid mode
                nonhybrid_results_resp_dict = Dict()
                try
                    ghpghx_inputs["hybrid_auto_ghx_sizing_flag"] = false
                    ghpghx_inputs["hybrid_sizing_flag"] = 1.0
                    # Call GhpGhx.jl to size GHP and GHX
                    @info "Starting GhpGhx.jl for non-hybrid GHX sizing"
                    # Call GhpGhx.jl to size GHP and GHX
                    results_nonhybrid, inputs_params_nonhybrid = GhpGhx.ghp_model(ghpghx_inputs)
                    # Create a dictionary of the results data needed for REopt
                    nonhybrid_results_resp_dict = GhpGhx.get_results_for_reopt(results_nonhybrid, inputs_params_nonhybrid)
                    @info "Non-hybrid GHX sizing complete using GhpGhx.jl"
                catch e
                    @info e
                    throw(@error("The GhpGhx package was not added (add https://github.com/NatLabRockies/GhpGhx.jl) or 
                        loaded (using GhpGhx) to the active Julia environment"))
                end
                d["GHP"]["number_of_boreholes_nonhybrid"] = nonhybrid_results_resp_dict["number_of_boreholes"]
                d["GHP"]["iterations_nonhybrid"] = nonhybrid_results_resp_dict["ghx_soln_number_of_iterations"]

                # ORIGINAL GUESS
                temp_diff = nonhybrid_results_resp_dict["end_of_year_ghx_lft_f"][length(nonhybrid_results_resp_dict["end_of_year_ghx_lft_f"])] - 
                            nonhybrid_results_resp_dict["end_of_year_ghx_lft_f"][1]

                hybrid_sizing_flag = 1.0 # non hybrid
                hybrid_sizing_flag_opposite_guess = 1.0 # non hybrid
                if temp_diff > 0
                    hybrid_sizing_flag = -2.0 #heating
                    hybrid_sizing_flag_opposite_guess = -1.0 #cooling
                    is_ghx_hybrid = true
                elseif temp_diff < 0
                    hybrid_sizing_flag = -1.0 #cooling
                    hybrid_sizing_flag_opposite_guess = -2.0 #heating
                    is_ghx_hybrid = true
                else
                    # non hybrid if exactly 0.
                    hybrid_sizing_flag = 1.0
                end
                ghpghx_inputs["hybrid_auto_ghx_sizing_flag"] = false

            elseif hybrid_ghx_sizing_method == "Fractional"
                is_ghx_hybrid = true
                hybrid_sizing_flag = get(ghpghx_inputs, "hybrid_ghx_sizing_fraction", 0.6)
            elseif hybrid_ghx_sizing_method !== nothing
                @warn "Unknown hybrid GHX sizing model provided"
            end

            if !isnothing(aux_heater_type)
                if aux_heater_type == "electric"
                    is_heating_electric = true
                else
                    @warn "Unknown auxillary heater type provided"
                    is_heating_electric = false
                end
            end

            d["GHP"]["is_ghx_hybrid"] = is_ghx_hybrid
            if !isnothing(hybrid_sizing_flag)
                ghpghx_inputs["hybrid_sizing_flag"] = hybrid_sizing_flag
            end
            if !isnothing(is_heating_electric)
                ghpghx_inputs["is_heating_electric"] = is_heating_electric
            end

            ghpghx_results = Dict()
            max_ghx_sizing_interations = 0

            # Hybrid GHP results 
            if is_ghx_hybrid

                # Run hybrid results using the initial guess of whether an auxiliary heater or cooler is required
                try
                    # Call GhpGhx.jl to size GHP and GHX
                    @info "Starting GhpGhx.jl for initial hybrid GHX sizing"
                    results, inputs_params = GhpGhx.ghp_model(ghpghx_inputs)
                    max_ghx_sizing_interations = inputs_params.max_sizing_iterations
    
                    # Create a dictionary of the results data needed for REopt
                    ghpghx_results = GhpGhx.get_results_for_reopt(results, inputs_params)
                    @info "GhpGhx.jl model solved" #with status $(results["status"])."
                catch e
                    @info e
                    throw(@error("The GhpGhx package was not added (add https://github.com/NatLabRockies/GhpGhx.jl) or 
                        loaded (using GhpGhx) to the active Julia environment, or an error occurred during the call 
                        to the GhpGhx.jl package."))
                end

                d["GHP"]["number_of_boreholes_auto_guess"] = ghpghx_results["number_of_boreholes"]
                d["GHP"]["iterations_auto_guess"] = ghpghx_results["ghx_soln_number_of_iterations"]
                
                # Invalid hybrid results
                if (ghpghx_results["number_of_boreholes"] >= nonhybrid_results_resp_dict["number_of_boreholes"]) || (ghpghx_results["ghx_soln_number_of_iterations"] == max_ghx_sizing_interations)
                    new_hybrid_ghpghx_results = Dict()
                    max_ghx_sizing_interations = 0
                    try
                        ghpghx_inputs["hybrid_sizing_flag"] = hybrid_sizing_flag_opposite_guess

                        # Call GhpGhx.jl to size GHP and GHX
                        @info "Initial guess for the hybrid GHP auxiliary unit was incorrect. Starting GhpGhx.jl for new hybrid GHX sizing"
                        # Call GhpGhx.jl to size GHP and GHX
                        results_new_hybrid, inputs_params_new_hybrid = GhpGhx.ghp_model(ghpghx_inputs)
                        max_ghx_sizing_interations = inputs_params_new_hybrid.max_sizing_iterations
                        # Create a dictionary of the results data needed for REopt
                        new_hybrid_ghpghx_results = GhpGhx.get_results_for_reopt(results_new_hybrid, inputs_params_new_hybrid)
                        @info "New hybrid GHX sizing complete using GhpGhx.jl"
                    catch e
                        @info e
                        throw(@error("The GhpGhx package was not added (add https://github.com/NatLabRockies/GhpGhx.jl) or 
                            loaded (using GhpGhx) to the active Julia environment, or an error occurred during the call 
                            to the GhpGhx.jl package."))
                    end
                    d["GHP"]["number_of_boreholes_flipped_guess"] = new_hybrid_ghpghx_results["number_of_boreholes"]
                    d["GHP"]["iterations_flipped_guess"] = new_hybrid_ghpghx_results["ghx_soln_number_of_iterations"]

                    if (new_hybrid_ghpghx_results["number_of_boreholes"] >= nonhybrid_results_resp_dict["number_of_boreholes"]) || (new_hybrid_ghpghx_results["ghx_soln_number_of_iterations"] == max_ghx_sizing_interations)
                        @info "Hybrid GHX results are unavailable for this scenario. Returning non-hybrid results"
                        is_ghx_hybrid = false
                        ghpghx_results = nonhybrid_results_resp_dict
                        d["GHP"]["hybrid_solution_type"] = "nonhybrid_solution"
                    else
                        ghpghx_results = new_hybrid_ghpghx_results
                        d["GHP"]["hybrid_solution_type"] = "flipped_guess"
                    end
                else
                    d["GHP"]["hybrid_solution_type"] = "automatic_guess_correct"
                end

                if haskey(d["GHP"],"max_ton") || haskey(d["GHP"],"max_number_of_boreholes")
                    @warn "User specified GHP/GHX size limits are not considered when hybrid sizing is selected. Inputs such as max_ton and max_number_of_boreholes will be ignored."
                end
            else
                try
                    # If user provides undersized GHP, calculate load to send to GhpGhx.jl, and load to send to REopt for backup
                    thermal_load_ton = ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"] .* 1/TONNE_PER_MMBTU_HOUR
                    if haskey(ghpghx_inputs,"cooling_thermal_load_ton")
                        cooling_load_ton = ghpghx_inputs["cooling_thermal_load_ton"]
                        thermal_load_ton .+= cooling_load_ton
                    end
                    peak_thermal_load_ton = maximum(thermal_load_ton)
                    if haskey(d["GHP"],"max_ton") && peak_thermal_load_ton > d["GHP"]["max_ton"]
                        @info "User entered undersized GHP. Calculating load that can be served by user specified undersized GHP"
                        # When user specifies undersized GHP, calculate the load to be served by GHP and send the rest to REopt
                        if !haskey(d["GHP"], "load_served_by_ghp")
                            d["GHP"]["load_served_by_ghp"] = "nonpeak"
                        end
                        # If user choose to scale down total load (load_served_by_ghp="scaled"), calculate the ratio of the udersized GHP size and peak load
                        if d["GHP"]["load_served_by_ghp"] == "scaled"
                            @info "GHP served scaled down of total thermal load"
                            peak_ratio = d["GHP"]["max_ton"] / peak_thermal_load_ton
                            # Scale the total load profile down by the peak_ratio and use this scaled down load to rerun GhpGhx.jl
                            heating_load_mmbtu = ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"]
                            heating_load_mmbtu = heating_load_mmbtu .* peak_ratio
                            ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"] = heating_load_mmbtu
                            if haskey(ghpghx_inputs,"cooling_thermal_load_ton")
                                ghpghx_inputs["cooling_thermal_load_ton"] = cooling_load_ton .* peak_ratio
                            end
                        elseif d["GHP"]["load_served_by_ghp"] == "nonpeak"
                            @info "GHP serves all thermal load below peak"
                            heating_load_mmbtu = ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"]
                            # if cooling load is included, cut down total thermal load and send as much heating load to GhpGhx.jl as possible
                            if haskey(ghpghx_inputs,"cooling_thermal_load_ton")
                                # If total thermal load (heating + cooling) is more than user-defined GHP size, 
                                # first reduce heating load as much as possible while keeping cooling load the same
                                if peak_thermal_load_ton > d["GHP"]["max_ton"]
                                    thermal_load_ton[thermal_load_ton .>= d["GHP"]["max_ton"]] .= d["GHP"]["max_ton"]
                                    heating_load_ton = thermal_load_ton .- cooling_load_ton
                                    # Make sure that the reduced heating load is not negative
                                    heating_load_ton[heating_load_ton .< 0] .= 0
                                    # If the updated peak thermal load is still more than user-defined GHP size, 
                                    # reduce cooling load as well
                                    updated_thermal_load_ton = heating_load_ton .+ cooling_load_ton
                                    updated_peak_thermal_load_ton = maximum(updated_thermal_load_ton)
                                    if updated_peak_thermal_load_ton > d["GHP"]["max_ton"]
                                        updated_thermal_load_ton[updated_thermal_load_ton .>= d["GHP"]["max_ton"]] .= d["GHP"]["max_ton"]
                                        cooling_load_ton = updated_thermal_load_ton .- heating_load_ton
                                        ghpghx_inputs["cooling_thermal_load_ton"] = cooling_load_ton
                                    end
                                    heating_load_mmbtu = heating_load_ton .* TONNE_PER_MMBTU_HOUR
                                    ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"] = heating_load_mmbtu
                                end
                            # if cooling load is not included, cut down heating load only and send to GhpGhx.jl
                            else
                                heating_load_mmbtu[heating_load_mmbtu .>= d["GHP"]["max_ton"] * TONNE_PER_MMBTU_HOUR] .= d["GHP"]["max_ton"] * TONNE_PER_MMBTU_HOUR
                                ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"] = heating_load_mmbtu
                            end                         
                        end
                    end
                    # Call GhpGhx.jl to size GHP and GHX
                    @info "Starting GhpGhx.jl"
                    results, inputs_params = GhpGhx.ghp_model(ghpghx_inputs)

                    # If max_number_of_boreholes is specified, check if number of boreholes sized by GhpGhx.jl greater than user-specified max_number_of_boreholes,
                    # and if max_number_of_boreholes is less, reduce thermal load served by GHP until max_number_of_boreholes = number of boreholses sized by GhpGhx.jl                
                    if haskey(d["GHP"],"max_number_of_boreholes")
                        optimal_number_of_boreholes = GhpGhx.get_results_for_reopt(results, inputs_params)["number_of_boreholes"]
                        if optimal_number_of_boreholes > d["GHP"]["max_number_of_boreholes"]
                            @info "Max number of boreholes specified is less than number of boreholes sized in GhpGhx.jl, reducing thermal load served by GHP further"
                            max_iter = 10
                            for iter = 1:max_iter
                                borehole_ratio = d["GHP"]["max_number_of_boreholes"] / optimal_number_of_boreholes
                                heating_load_mmbtu .*= borehole_ratio
                                if haskey(ghpghx_inputs,"cooling_thermal_load_ton")
                                    cooling_load_ton .*= borehole_ratio
                                # if cooling load is not included, cut down heating load only and send to GhpGhx.jl
                                end
                                ghpghx_inputs["heating_thermal_load_mmbtu_per_hr"] = heating_load_mmbtu                              
                                ghpghx_inputs["cooling_thermal_load_ton"] = cooling_load_ton   
                                
                                # Rerun GhpGhx.jl
                                results, inputs_params = GhpGhx.ghp_model(ghpghx_inputs)
                                optimal_number_of_boreholes = GhpGhx.get_results_for_reopt(results, inputs_params)["number_of_boreholes"]
                                # Solution is found if the new optimal number of boreholes sized by GhpGhx.jl = user-specified max number of boreholes,
                                # Otherwise, continue solving until reaching max iteration
                                if -0.5 < optimal_number_of_boreholes - d["GHP"]["max_number_of_boreholes"] < 0.5
                                    break
                                else
                                    iter += 1
                                end
                            end
                        end
                    end

                    # Create a dictionary of the results data needed for REopt
                    ghpghx_results = GhpGhx.get_results_for_reopt(results, inputs_params)
                    # Return results from GhpGhx.jl without load scaling if user does not provide GHP size or if user entered GHP size is greater than GHP size output
                    @info "GhpGhx.jl model solved" #with status $(results["status"])."
                catch e
                    @info e
                    throw(@error("The GhpGhx package was not added (add https://github.com/NatLabRockies/GhpGhx.jl) or 
                        loaded (using GhpGhx) to the active Julia environment, or an error occurred during the call 
                        to the GhpGhx.jl package."))
                end
            end

            end_time = now()
            d["GHP"]["solve_time_min"] = (end_time - start_time).value/1000/60

            ghpghx_response = Dict([("inputs", ghpghx_inputs), ("outputs", ghpghx_results)])
            ghp_inputs_removed_ghpghx_params = deepcopy(d["GHP"])
            for param in ["ghpghx_inputs", "ghpghx_responses", "ghpghx_response_uuids"]
                if haskey(d["GHP"], param)    
                    pop!(ghp_inputs_removed_ghpghx_params, param)
                end
            end                    
            append!(
                ghp_option_list, 
                [GHP(
                    ghpghx_response, 
                    ghp_inputs_removed_ghpghx_params;
                    sector = site.sector,
                    federal_procurement_type = site.federal_procurement_type
                )]
            )
            # Print out ghpghx_response for loading into a future run without running GhpGhx.jl again
            # open("scenarios/ghpghx_response.json","w") do f             
        end
    # If ghpghx_responses is included in inputs, do NOT run GhpGhx.jl model and use already-run ghpghx result as input to REopt
    elseif eval_ghp && get_ghpghx_from_input
        ghp_inputs_removed_ghpghx_responses = deepcopy(d["GHP"])
        pop!(ghp_inputs_removed_ghpghx_responses, "ghpghx_responses")
        if haskey(d["GHP"], "ghpghx_inputs")    
            pop!(ghp_inputs_removed_ghpghx_responses, "ghpghx_inputs")
        end
        for ghpghx_response in get(d["GHP"], "ghpghx_responses", [])
            if haskey(ghpghx_response, "inputs")
                if get(ghpghx_response["inputs"], "hybrid_ghx_sizing_method", nothing) in ["Automatic", "Fractional"]
                    ghp_inputs_removed_ghpghx_responses["is_ghx_hybrid"] = true
                end
            end
            append!(
                ghp_option_list, 
                [GHP(
                    ghpghx_response, 
                    ghp_inputs_removed_ghpghx_responses;
                    sector = site.sector,
                    federal_procurement_type = site.federal_procurement_type
                )]
            )
        end
    end

    steam_turbine = nothing
    if haskey(d, "SteamTurbine")
        if !isnothing(existing_boiler)
            total_fuel_heating_load_mmbtu_per_hour = (space_heating_load.loads_kw + dhw_load.loads_kw + process_heat_load.loads_kw) / existing_boiler.efficiency / KWH_PER_MMBTU
            avg_boiler_fuel_load_mmbtu_per_hour = sum(total_fuel_heating_load_mmbtu_per_hour) / length(total_fuel_heating_load_mmbtu_per_hour)
            steam_turbine = SteamTurbine(d["SteamTurbine"];  
                                        avg_boiler_fuel_load_mmbtu_per_hour = avg_boiler_fuel_load_mmbtu_per_hour,
                                        sector = site.sector, 
                                        federal_procurement_type = site.federal_procurement_type)
        else
            steam_turbine = SteamTurbine(d["SteamTurbine"]; 
                                        sector = site.sector, 
                                        federal_procurement_type = site.federal_procurement_type)
        end
    end

    # Electric Heater
    electric_heater = nothing
    if haskey(d, "ElectricHeater") && (!haskey(d["ElectricHeater"], "max_mmbtu_per_hour") || d["ElectricHeater"]["max_mmbtu_per_hour"] > 0.0)
        electric_heater = ElectricHeater(;dictkeys_tosymbols(d["ElectricHeater"])...)
    end
    
    if !(settings.off_grid_flag) # ElectricTariff only required for on-grid                            
        electric_tariff = ElectricTariff(; dictkeys_tosymbols(d["ElectricTariff"])..., 
                                        year=electric_load.year,
                                        NEM=electric_utility.net_metering_limit_kw > 0, 
                                        time_steps_per_hour=settings.time_steps_per_hour
                                        )
    else # if ElectricTariff inputs supplied for off-grid, will not be applied. 
        if haskey(d, "ElectricTariff")
            @warn "ElectricTariff inputs are not applicable when `off_grid_flag` is true, and will be ignored."
        end
        electric_tariff = ElectricTariff(;  blended_annual_energy_rate = 0.0, 
                                            blended_annual_demand_rate = 0.0,
                                            year=electric_load.year,
                                            time_steps_per_hour=settings.time_steps_per_hour
                                        )
    end

    # CST                                    
    cst = nothing
    if haskey(d, "CST") && (!haskey(d["CST"], "max_kw") || d["CST"]["max_kw"] > 0.0)
        if !haskey(d,"Site") || !haskey(d["Site"], "land_acres")
            throw(@error("Site.land_acres not provided as an input, which is required when CST is included as a technology."))
        end
        cst_ssc_response = run_ssc(d)
        d["CST"]["production_factor"] = cst_ssc_response["thermal_production_series"]
        d["CST"]["elec_consumption_factor_series"] = cst_ssc_response["electric_consumption_series"]
        if haskey(d["CST"], "SSC_Inputs")
            pop!(d["CST"],"SSC_Inputs")
        end
        cst = CST(;dictkeys_tosymbols(d["CST"])...)
    end

    # ASHP
    ashp = nothing
    if haskey(d, "ASHPSpaceHeater")
        if !haskey(d["ASHPSpaceHeater"], "max_ton")
            max_ton = get_ashp_defaults("SpaceHeating")["max_ton"]
        else
            max_ton = d["ASHPSpaceHeater"]["max_ton"]
        end

        if max_ton > 0
            # ASHP Space Heater's temp back_up_temp_threshold_degF
            if !haskey(d["ASHPSpaceHeater"], "back_up_temp_threshold_degF")
                ambient_temp_thres_fahrenheit = get_ashp_defaults("SpaceHeating")["back_up_temp_threshold_degF"]
            else
                ambient_temp_thres_fahrenheit = d["ASHPSpaceHeater"]["back_up_temp_threshold_degF"]
            end
            
            # If PV is evaluated, get ambient temperature series from PVWatts and assign PV production factor
            if isnothing(site.outdoor_air_temperature_degF)
                if !isempty(pvs)
                    for pv in pvs
                        pv.production_factor_series, ambient_temp_celsius = call_pvwatts_api(site.latitude, site.longitude; tilt=pv.tilt, azimuth=pv.azimuth, module_type=pv.module_type, 
                            array_type=pv.array_type, losses=round(pv.losses*100, digits=3), dc_ac_ratio=pv.dc_ac_ratio,
                            gcr=pv.gcr, inv_eff=pv.inv_eff*100, timeframe="hourly", radius=pv.radius, time_steps_per_hour=settings.time_steps_per_hour)
                    end
                else
                    # if PV is not evaluated, call PVWatts to get ambient temperature series
                    pv_prodfactor, ambient_temp_celsius = call_pvwatts_api(site.latitude, site.longitude; time_steps_per_hour=settings.time_steps_per_hour)    
                end
                site.outdoor_air_temperature_degF = (9/5 .* ambient_temp_celsius) .+ 32
            end

            d["ASHPSpaceHeater"]["ambient_temp_degF"] = site.outdoor_air_temperature_degF
            d["ASHPSpaceHeater"]["heating_load"] = space_heating_load.loads_kw
            d["ASHPSpaceHeater"]["cooling_load"] = cooling_load.loads_kw_thermal

            ashp = ASHPSpaceHeater(;dictkeys_tosymbols(d["ASHPSpaceHeater"])...)
        end    
    end

    # ASHP Water Heater:
    ashp_wh = nothing

    if haskey(d, "ASHPWaterHeater")
        if !haskey(d["ASHPWaterHeater"], "max_ton")
            max_ton = get_ashp_defaults("DomesticHotWater")["max_ton"]
        else
            max_ton = d["ASHPWaterHeater"]["max_ton"]
        end

        if max_ton > 0.0
            # ASHP Space Heater's temp back_up_temp_threshold_degF
            if !haskey(d["ASHPWaterHeater"], "back_up_temp_threshold_degF")
                ambient_temp_thres_fahrenheit = get_ashp_defaults("DomesticHotWater")["back_up_temp_threshold_degF"]
            else
                ambient_temp_thres_fahrenheit = d["ASHPWaterHeater"]["back_up_temp_threshold_degF"]
            end
            
            # If PV is evaluated, get ambient temperature series from PVWatts and assign PV production factor
            if isnothing(site.outdoor_air_temperature_degF)
                if !isempty(pvs)
                    for pv in pvs
                        pv.production_factor_series, ambient_temp_celsius = call_pvwatts_api(site.latitude, site.longitude; tilt=pv.tilt, azimuth=pv.azimuth, module_type=pv.module_type, 
                            array_type=pv.array_type, losses=round(pv.losses*100, digits=3), dc_ac_ratio=pv.dc_ac_ratio,
                            gcr=pv.gcr, inv_eff=pv.inv_eff*100, timeframe="hourly", radius=pv.radius, time_steps_per_hour=settings.time_steps_per_hour)
                    end
                else
                    # if PV is not evaluated, call PVWatts to get ambient temperature series
                    pv_prodfactor, ambient_temp_celsius = call_pvwatts_api(site.latitude, site.longitude; time_steps_per_hour=settings.time_steps_per_hour)    
                end
                site.outdoor_air_temperature_degF = (9/5 .* ambient_temp_celsius) .+ 32
            end

            d["ASHPWaterHeater"]["ambient_temp_degF"] = site.outdoor_air_temperature_degF
            d["ASHPWaterHeater"]["heating_load"] = dhw_load.loads_kw

            ashp_wh = ASHPWaterHeater(;dictkeys_tosymbols(d["ASHPWaterHeater"])...)
        end
    end

    return Scenario(
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
        dhw_load,
        space_heating_load,
        process_heat_load,
        cooling_load,
        existing_boiler,
        boiler,
        chp,
        flexible_hvac,
        existing_chiller,
        absorption_chiller,
        ghp_option_list,
        space_heating_thermal_load_reduction_with_ghp_kw,
        cooling_thermal_load_reduction_with_ghp_kw,
        steam_turbine,
        electric_heater,
        cst,
        ashp,
        ashp_wh
    )
end


"""
    Scenario(fp::String)

Consruct Scenario from filepath `fp` to JSON with keys aligned with the `Scenario(d::Dict)` method.
"""
function Scenario(fp::String)
    Scenario(JSON.parsefile(fp); flex_hvac_from_json=true)
end


function add_doe_reference_names_from_elec_to_thermal_loads(elec::Dict, thermal::Dict)
    string_keys = [
        "doe_reference_name",
        "blended_doe_reference_names",
        "blended_doe_reference_percents",
    ]
    for k in string_keys
        if k in keys(elec) 
            if !(k in keys(thermal)) || isempty(thermal[k])
                thermal[k] = elec[k]
            end
        end
    end
end

function get_existing_boiler_efficiency(d)
    existing_boiler_temp = ExistingBoiler(;fuel_cost_per_mmbtu=1.0)
    default_production_type = existing_boiler_temp.production_type
    if haskey(d, "ExistingBoiler")
        existing_boiler_production_type = get(d["ExistingBoiler"], "production_type", default_production_type)
        existing_boiler_efficiency = get(d["ExistingBoiler"], "efficiency", existing_boiler_efficiency_defaults[existing_boiler_production_type])
    else
        existing_boiler_efficiency = existing_boiler_efficiency_defaults[default_production_type]
    end  

    return existing_boiler_efficiency
end

function validate_load_year_consistency(electric_load_year, year, load_type)
    if electric_load_year != year
        throw(@error("Inconsistent load years: ElectricLoad year ($electric_load_year) does not match the provided year ($year) for $load_type."))
    end
end