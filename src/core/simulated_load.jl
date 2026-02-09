"""
    simulated_load(d::Dict)

This function gets DOE commercial reference building (CRB) load profile data
    which is the same way that loads are processed to create REoptInputs.s (Scenario struct).
    
This function is used for the /simulated_load endpoint in the REopt API, in particular 
    for the webtool/UI to display loads before running REopt, but is also generally
    an external way to access CRB load data without running REopt.

One particular aspect of this function specifically for the webtool/UI is the heating load 
    because there is just a single heating load instead of separated space heating and 
    domestic hot water loads.

"""
function simulated_load(d::Dict)
    # Latitude and longitude are required if not normalizing and scaling load profile input
    normalize_and_scale_load_profile_input = get(d, "normalize_and_scale_load_profile_input", false)
    year = get(d, "year", 2017)
    time_steps_per_hour = get(d, "time_steps_per_hour", 1)
    latitude = get(d, "latitude", 0.0)
    longitude = get(d, "longitude", 0.0)
    if (isnothing(latitude) || isnothing(longitude)) && !normalize_and_scale_load_profile_input
        throw(@error("latitude and longitude must be provided"))
    elseif !normalize_and_scale_load_profile_input
        if latitude > 90 || latitude < -90
            throw(@error("latitude $latitude is out of acceptable range (-90 <= latitude <= 90)"))
        end
        if longitude > 180 || longitude < -180
            throw(@error("longitude $longitude is out of acceptable range (-180 <= longitude <= 180)"))
        end
    end

    # Load type validation
    load_type = get(d, "load_type", "electric")
    if !(load_type in ["electric", "heating", "cooling", "space_heating", "domestic_hot_water", "process_heat"])
        throw(@error("load_type parameter must be one of the following: 'electric', 'heating', 'cooling', 'space_heating', 'domestic_hot_water', 'process_heat'. If load_type is not specified, 'electric' is assumed."))
    end

    # Check for valid reference building name
    if load_type == "process_heat"
        doe_reference_name_input = get(d, "industrial_reference_name", nothing)
        valid_names = DEFAULT_PROCESS_TYPES
    else
        doe_reference_name_input = get(d, "doe_reference_name", nothing)
        valid_names = DEFAULT_BUILDINGS
    end
    percent_share_input = get(d, "percent_share", Real[])

    # Input which then expects a custom load_profile along with annual or monthly energy values; this could be electric, heating, or cooling profiles
    load_profile = get(d, "load_profile", Real[])
    if normalize_and_scale_load_profile_input
        if isempty(load_profile)
            throw(@error("The load_profile must be provided to normalize_and_scale_load_profile_input"))
        end
    end
    
    # Validate consistency between reference name and optionally the percent_share for blended building types
    if !isnothing(doe_reference_name_input) && !(typeof(doe_reference_name_input) <: Vector{})
        doe_reference_name = [doe_reference_name_input]
    elseif !isnothing(doe_reference_name_input) && !isempty(percent_share_input)
        doe_reference_name = doe_reference_name_input
        if !(typeof(percent_share_input) <: Vector{})
            percent_share_list = [percent_share_input]
        else
            percent_share_list = percent_share_input
        end
        if !(length(percent_share_list) == length(doe_reference_name))
            throw(@error("The number of percent_share entries does not match that of the number of doe_reference_name entries"))
        end
    elseif !isnothing(doe_reference_name_input) && typeof(doe_reference_name_input) <: Vector{} && isempty(percent_share_input)  # Vector of doe_reference_name but no percent_share, as needed
        throw(@error("Must provide percent_share list if modeling a blended/hybrid set of buildings"))
    else
        doe_reference_name = doe_reference_name_input
    end

    # When wanting cooling profile based on building type(s) for cooling, need separate cooling building(s)
    cooling_doe_ref_name_input = get(d, "cooling_doe_ref_name", nothing)
    cooling_pct_share_input = get(d, "cooling_pct_share", Real[])
    if !isnothing(cooling_doe_ref_name_input) && !(typeof(cooling_doe_ref_name_input) <: Vector{})
        cooling_doe_ref_name = [cooling_doe_ref_name_input]
        cooling_pct_share_list = Real[]
    elseif !isnothing(cooling_doe_ref_name_input) && !isempty(cooling_pct_share_input)
        cooling_doe_ref_name = cooling_doe_ref_name_input
        if !(typeof(cooling_pct_share_input) <: Vector{})
            cooling_pct_share_list = [cooling_pct_share_input]
        else
            cooling_pct_share_list = cooling_pct_share_input
        end            
        if !(length(cooling_pct_share_list) == length(cooling_doe_ref_name))
            throw(@error("The number of cooling_pct_share entries does not match that of the number of cooling_doe_ref_name entries"))
        end
    elseif typeof(cooling_doe_ref_name_input) <: Vector{} && isempty(cooling_pct_share_input)  # Vector of cooling_doe_ref_name but no cooling_pct_share_input, as needed
        throw(@error("Must provide cooling_pct_share list if modeling a blended/hybrid set of buildings"))
    else
        cooling_doe_ref_name = nothing
        cooling_pct_share_list = Real[]
    end

    if isnothing(doe_reference_name) && !isnothing(cooling_doe_ref_name)
        doe_reference_name = cooling_doe_ref_name
        percent_share_list = cooling_pct_share_list
    end

    if !isnothing(doe_reference_name)
        for drn in doe_reference_name
            if !(drn in valid_names)
                throw(@error("Invalid doe_reference_name - $drn. Select from the following: $valid_names"))
            end
        end
    end

    # The following is possibly used in both load_type == "electric" and "cooling", so have to bring it out of those if-statements
    chiller_cop = get(d, "chiller_cop", nothing)

    if !isnothing(get(d, "max_thermal_factor_on_peak_load", nothing))
        max_thermal_factor_on_peak_load = d["max_thermal_factor_on_peak_load"]
    else
        max_thermal_factor_on_peak_load = 1.25
    end

    if load_type == "electric"
        for key in keys(d)
            if occursin("_mmbtu", key) || occursin("_ton", key) || occursin("_fraction", key)
                throw(@error("Invalid key $key for load_type=electric"))
            end
        end
        if isnothing(doe_reference_name) && !normalize_and_scale_load_profile_input
            throw(@error("Please supply a doe_reference_name and optionally scaling parameters (annual_kwh or monthly_totals_kwh)."))
        end
        # Annual loads (default is nothing)
        annual_kwh = get(d, "annual_kwh", nothing)
        # Monthly loads (default is empty list)
        monthly_totals_kwh = get(d, "monthly_totals_kwh", Real[])
        if !isempty(monthly_totals_kwh)
            if !(length(monthly_totals_kwh) == 12)
                throw(@error("monthly_totals_kwh must contain a value for each of the 12 months"))
            end
            bad_index = []
            for (i, kwh) in enumerate(monthly_totals_kwh)
                if isnothing(kwh)
                    append!(bad_index, i)
                end
            end
            if !isempty(bad_index)
                throw(@error("monthly_totals_kwh must contain a value for each month, and it is null for these months: $bad_index"))
            end
        end
        # Monthly peak loads (default is empty list)
        monthly_peaks_kw = get(d, "monthly_peaks_kw", Real[])
        if !isempty(monthly_peaks_kw)
            if !(length(monthly_peaks_kw) == 12)
                throw(@error("monthly_peaks_kw must contain a value for each of the 12 months"))
            end
            bad_index = []
            for (i, peak) in enumerate(monthly_peaks_kw)
                if isnothing(peak) || peak <= 0
                    append!(bad_index, i)
                end
            end
            if !isempty(bad_index)
                throw(@error("monthly_peaks_kw must contain a positive value for each month, and it is null or non-positive for these months: $bad_index"))
            end
        end

        # Build dependent inputs for electric load
        elec_load_inputs = Dict{Symbol, Any}()
        if !normalize_and_scale_load_profile_input
            if typeof(doe_reference_name) <: Vector{} && length(doe_reference_name) > 1
                elec_load_inputs[:blended_doe_reference_names] = doe_reference_name
                elec_load_inputs[:blended_doe_reference_percents] = percent_share_list
            else
                elec_load_inputs[:doe_reference_name] = doe_reference_name[1]
            end
        else
            elec_load_inputs[:normalize_and_scale_load_profile_input] = normalize_and_scale_load_profile_input
            elec_load_inputs[:loads_kw] = load_profile
            elec_load_inputs[:time_steps_per_hour] = time_steps_per_hour
        end
        elec_load_inputs[:year] = year

        electric_load = ElectricLoad(; elec_load_inputs...,
                                latitude=latitude,
                                longitude=longitude,
                                annual_kwh=annual_kwh,
                                monthly_totals_kwh=monthly_totals_kwh,
                                monthly_peaks_kw=monthly_peaks_kw
                            )

        # Get the default cooling portion of the total electric load (used when we want cooling load without annual_tonhour input)
        if !isnothing(cooling_doe_ref_name)
            # Build dependent inputs for cooling load
            cooling_load_inputs = Dict{Symbol, Any}()
            if typeof(cooling_doe_ref_name) <: Vector{} && length(cooling_doe_ref_name) > 1
                cooling_load_inputs[:blended_doe_reference_names] = cooling_doe_ref_name
                cooling_load_inputs[:blended_doe_reference_percents] = cooling_pct_share_list
            else
                cooling_load_inputs[:doe_reference_name] = cooling_doe_ref_name[1]
            end
            cooling_load_inputs[:year] = year

            cooling_load = CoolingLoad(; cooling_load_inputs...,
                                        city=electric_load.city,
                                        latitude=latitude,
                                        longitude=longitude,
                                        site_electric_load_profile=electric_load.loads_kw,
                                        existing_chiller_cop=chiller_cop,
                                        existing_chiller_max_thermal_factor_on_peak_load=max_thermal_factor_on_peak_load
                                )

            if length(cooling_doe_ref_name) > 1
                modified_fraction = []
                for (i, building) in enumerate(cooling_doe_ref_name)
                    default_fraction = get_default_fraction_of_total_electric(electric_load.city, building, latitude, longitude, electric_load.year)
                    modified_fraction = default_fraction * cooling_pct_share_list[i] / 100.0
                end
            else
                modified_fraction = get_default_fraction_of_total_electric(electric_load.city, cooling_doe_ref_name[1], latitude, longitude, electric_load.year)
            end

            cooling_load_thermal_ton = round.(cooling_load.loads_kw_thermal ./ KWH_THERMAL_PER_TONHOUR, digits=3)
            cooling_defaults_dict = Dict([
                                        ("loads_ton", cooling_load_thermal_ton),
                                        ("annual_tonhour", sum(cooling_load_thermal_ton)),
                                        ("chiller_cop", round(cooling_load.existing_chiller_cop, digits=3)),
                                        ("min_ton", minimum(cooling_load_thermal_ton)),
                                        ("mean_ton", sum(cooling_load_thermal_ton) / length(cooling_load_thermal_ton)),
                                        ("max_ton", maximum(cooling_load_thermal_ton)),
                                        ("fraction_of_total_electric_profile", round.(modified_fraction, digits=9))
                                        ])
        else
            cooling_defaults_dict = Dict()
        end

        electric_loads_kw = round.(electric_load.loads_kw, digits=3)

        # Calculate actual/scaled monthly energy and peaks which may not match inputs perfectly
        monthly_timesteps = REopt.get_monthly_time_steps(year; time_steps_per_hour=time_steps_per_hour)
        actual_energies = Float64[]
        actual_peaks = Float64[]
        for month in 1:12
            start_idx = monthly_timesteps[month][1]
            end_idx = monthly_timesteps[month][end]
            push!(actual_energies, sum(electric_loads_kw[start_idx:end_idx]) / time_steps_per_hour)
            push!(actual_peaks, maximum(electric_loads_kw[start_idx:end_idx]))
        end

        response = Dict([
                        ("loads_kw", electric_loads_kw),
                        ("annual_kwh", sum(electric_loads_kw) / time_steps_per_hour),
                        ("min_kw", minimum(electric_loads_kw)),
                        ("mean_kw", sum(electric_loads_kw) / length(electric_loads_kw)),
                        ("max_kw", maximum(electric_loads_kw)),
                        ("cooling_defaults", cooling_defaults_dict),
                        ("monthly_totals_kwh", actual_energies),
                        ("monthly_peaks_kw", actual_peaks)
                        ])

        return response
    end

    if load_type == "heating"
        error_list = []
        for key in keys(d)
            if occursin("_kw", key) || occursin("_ton", key)
                append!(error_list, [key])
            end
        end
        if !isempty(error_list)
            throw(@error("Invalid key(s) $error_list for load_type=heating"))
        end
        if isnothing(doe_reference_name) && !normalize_and_scale_load_profile_input
            throw(@error("Please supply a doe_reference_name and optional scaling parameters (annual_mmbtu or monthly_mmbtu)."))
        elseif normalize_and_scale_load_profile_input
            throw(@error("For normalizing and scaling a heating load profile, use one of load_type=['space_heating', 'domestic_hot_water', 'process_heat']"))
        end
        # Annual loads (default is nothing)
        annual_mmbtu = get(d, "annual_mmbtu", nothing)
        # Monthly loads (default is empty list)
        monthly_mmbtu = get(d, "monthly_mmbtu", Real[])
        if !isempty(monthly_mmbtu)
            if !(length(monthly_mmbtu) == 12)
                throw(@error("monthly_mmbtu must contain a value for each of the 12 months"))
            end                   
            bad_index = []
            for (i, mmbtu) in enumerate(monthly_mmbtu)
                if isnothing(mmbtu)
                    append!(bad_index, i)
                end
            end
            if !isempty(bad_index)
                throw(@error("monthly_mmbtu must contain a value for each month, and it is null for these months: $bad_index"))
            end
        end
        # Addressable heating load (default is 1.0)
        addressable_load_fraction = get(d, "addressable_load_fraction", 1.0)
        if typeof(addressable_load_fraction) <: Vector{}
            if !(length(addressable_load_fraction) == 12)
                throw(@error("addressable_load_fraction must contain a value for each of the 12 months"))
            end                
            bad_index = []
            for (i, frac) in enumerate(addressable_load_fraction)
                if isnothing(frac)
                    append!(bad_index, i)
                end
            end
            if length(bad_index) > 0
                throw(@error("addressable_load_fraction must contain a value for each month, and it is null for these months: $bad_index"))
            end
        elseif addressable_load_fraction < 0.0 ||addressable_load_fraction > 1.0
            throw(@error("addressable_load_fraction must be between 0.0 and 1.0"))
        end

        # Build dependent inputs for heating load
        heating_load_inputs = Dict{Symbol, Any}()
        if length(doe_reference_name) > 1
            heating_load_inputs[:blended_doe_reference_names] = doe_reference_name
            heating_load_inputs[:blended_doe_reference_percents] = percent_share_list
        else
            heating_load_inputs[:doe_reference_name] = doe_reference_name[1]
        end
        if addressable_load_fraction != 1.0
            heating_load_inputs[:addressable_load_fraction] = addressable_load_fraction
        end
        heating_load_inputs[:year] = year
    
        # Split up the single heating fuel input for space + dhw annual_mmbtu or monthly_mmbtu into CRB profile split
        boiler_efficiency = get(d, "boiler_efficiency", EXISTING_BOILER_EFFICIENCY)
        
        default_space_heating_load = HeatingLoad(; heating_load_inputs...,
                                                        load_type="space_heating",
                                                        latitude=latitude, 
                                                        longitude=longitude,
                                                        existing_boiler_efficiency=boiler_efficiency
                                                    )
        default_dhw_load = HeatingLoad(; heating_load_inputs...,
                                                    load_type="domestic_hot_water",
                                                    latitude=latitude, 
                                                    longitude=longitude,
                                                    existing_boiler_efficiency=boiler_efficiency
                                                )
    
        space_heating_annual_mmbtu = nothing
        dhw_annual_mmbtu = nothing

        space_heating_monthly_mmbtu = Vector{Real}()
        space_heating_monthly_fuel_mmbtu = Vector{Real}()

        dhw_monthly_mmbtu = Vector{Real}()
        dhw_monthly_fuel_mmbtu = Vector{Real}()
    
        if !isempty(monthly_mmbtu)    
            space_heating_monthly_energy =   get_monthly_energy(default_space_heating_load.loads_kw; year=year)
            dhw_monthly_energy           =   get_monthly_energy(default_dhw_load.loads_kw; year=year)
            
            total_monthly_energy        =   space_heating_monthly_energy + dhw_monthly_energy
            
            space_heating_fraction_monthly =   space_heating_monthly_energy ./ total_monthly_energy
            dhw_fraction_monthly           =   dhw_monthly_energy ./ total_monthly_energy
    
            space_heating_monthly_mmbtu      =   monthly_mmbtu .* space_heating_fraction_monthly
            space_heating_monthly_fuel_mmbtu =   space_heating_monthly_mmbtu .* addressable_load_fraction
            
            dhw_monthly_mmbtu      =   monthly_mmbtu .* dhw_fraction_monthly
            dhw_monthly_fuel_mmbtu =   dhw_monthly_mmbtu .* addressable_load_fraction
            
        elseif !isnothing(annual_mmbtu)
            total_heating_annual_mmbtu =   default_space_heating_load.annual_mmbtu + default_dhw_load.annual_mmbtu
            
            space_heating_fraction =   default_space_heating_load.annual_mmbtu / total_heating_annual_mmbtu
            dhw_fraction           =   default_dhw_load.annual_mmbtu / total_heating_annual_mmbtu
    
            space_heating_annual_mmbtu =   annual_mmbtu * space_heating_fraction
            dhw_annual_mmbtu           =   annual_mmbtu * dhw_fraction
        end
    
        space_heating_load = HeatingLoad(; heating_load_inputs...,
                                                load_type="space_heating",
                                                latitude=latitude, 
                                                longitude=longitude,
                                                annual_mmbtu=space_heating_annual_mmbtu,
                                                monthly_mmbtu=space_heating_monthly_mmbtu,
                                                existing_boiler_efficiency=boiler_efficiency
                                            )
        dhw_load = HeatingLoad(; heating_load_inputs...,
                                            load_type="domestic_hot_water",
                                            latitude=latitude, 
                                            longitude=longitude,
                                            annual_mmbtu=dhw_annual_mmbtu,
                                            monthly_mmbtu=dhw_monthly_mmbtu,
                                            existing_boiler_efficiency=boiler_efficiency
                                        )                                             
    
        space_load_series        =   space_heating_load.loads_kw ./ boiler_efficiency ./ KWH_PER_MMBTU
        dhw_load_series          =   dhw_load.loads_kw ./ boiler_efficiency ./ KWH_PER_MMBTU
        total_load_series        =   space_load_series + dhw_load_series
        
        total_heating_annual_mmbtu =   (space_heating_load.annual_mmbtu + dhw_load.annual_mmbtu) / boiler_efficiency
    
        response = Dict([
            ("loads_mmbtu_per_hour", round.(total_load_series, digits=3)),
            ("annual_mmbtu", round(total_heating_annual_mmbtu, digits=3)),
            ("min_mmbtu_per_hour", round(minimum(total_load_series), digits=3)),
            ("mean_mmbtu_per_hour", round(sum(total_load_series) / length(total_load_series), digits=3)),
            ("max_mmbtu_per_hour", round(maximum(total_load_series), digits=3)),
            ("space_loads_mmbtu_per_hour", round.(space_load_series, digits=3)),
            ("space_annual_mmbtu", round(space_heating_load.annual_mmbtu / boiler_efficiency, digits=3)),
            ("space_min_mmbtu_per_hour", round(minimum(space_load_series), digits=3)),
            ("space_mean_mmbtu_per_hour", round(sum(space_load_series) / length(space_load_series), digits=3)),
            ("space_max_mmbtu_per_hour", round(maximum(space_load_series), digits=3)),
            ("space_monthly_mmbtu", round.(space_heating_monthly_fuel_mmbtu, digits=3)),
            ("dhw_loads_mmbtu_per_hour", round.(dhw_load_series, digits=3)),
            ("dhw_annual_mmbtu", round(dhw_load.annual_mmbtu / boiler_efficiency, digits=3)),
            ("dhw_min_mmbtu_per_hour", round(minimum(dhw_load_series), digits=3)),
            ("dhw_mean_mmbtu_per_hour", round(sum(dhw_load_series) / length(dhw_load_series), digits=3)),
            ("dhw_max_mmbtu_per_hour", round(maximum(dhw_load_series), digits=3)),
            ("dhw_monthly_mmbtu", round.(dhw_monthly_fuel_mmbtu, digits=3)),
        ])
    
        return response
    end

    if load_type in ["space_heating", "domestic_hot_water", "process_heat"]
        error_list = []
        for key in keys(d)
            if occursin("_kw", key) || occursin("_ton", key)
                append!(error_list, [key])
            end
        end
        if !isempty(error_list)
            throw(@error("Invalid key(s) $error_list for load_type=[space_heating, domestic_hot_water, or process_heat"))
        end
        if isnothing(doe_reference_name) && !normalize_and_scale_load_profile_input
            throw(@error("Please supply a doe_reference_name or industrial_reference_name and optional scaling parameters (annual_mmbtu or monthly_mmbtu)."))
        end
        # Annual loads (default is nothing)
        annual_mmbtu = get(d, "annual_mmbtu", nothing)
        # Monthly loads (default is empty list)
        monthly_mmbtu = get(d, "monthly_mmbtu", Real[])
        if !isempty(monthly_mmbtu)
            if !(length(monthly_mmbtu) == 12)
                throw(@error("monthly_mmbtu must contain a value for each of the 12 months"))
            end
            bad_index = []
            for (i, mmbtu) in enumerate(monthly_mmbtu)
                if isnothing(mmbtu)
                    append!(bad_index, i)
                end
            end
            if !isempty(bad_index)
                throw(@error("monthly_mmbtu must contain a value for each month, and it is null for these months: $bad_index"))
            end
        end
        # Addressable heating load (default is 1.0)
        addressable_load_fraction = get(d, "addressable_load_fraction", 1.0)
        if typeof(addressable_load_fraction) <: Vector{}
            if !(length(addressable_load_fraction) == 12)
                throw(@error("addressable_load_fraction must contain a value for each of the 12 months"))
            end
            bad_index = []
            for (i, frac) in enumerate(addressable_load_fraction)
                if isnothing(frac)
                    append!(bad_index, i)
                end
            end
            if length(bad_index) > 0
                throw(@error("addressable_load_fraction must contain a value for each month, and it is null for these months: $bad_index"))
            end
        elseif addressable_load_fraction < 0.0 ||addressable_load_fraction > 1.0
            throw(@error("addressable_load_fraction must be between 0.0 and 1.0"))
        end

        boiler_efficiency = get(d, "boiler_efficiency", EXISTING_BOILER_EFFICIENCY)
        
        # Build dependent inputs for Heating load
        heating_load_inputs = Dict{Symbol, Any}()
        if !normalize_and_scale_load_profile_input
            if load_type == "process_heat"
                if length(doe_reference_name) > 1
                    heating_load_inputs[:blended_industrial_reference_names] = doe_reference_name
                    heating_load_inputs[:blended_industrial_reference_percents] = percent_share_list
                else
                    heating_load_inputs[:industrial_reference_name] = doe_reference_name[1]
                end
            else
                if length(doe_reference_name) > 1
                    heating_load_inputs[:blended_doe_reference_names] = doe_reference_name
                    heating_load_inputs[:blended_doe_reference_percents] = percent_share_list                        
                else
                    heating_load_inputs[:doe_reference_name] = doe_reference_name[1]
                end
            end
        else
            heating_load_inputs[:normalize_and_scale_load_profile_input] = normalize_and_scale_load_profile_input
            heating_load_inputs[:fuel_loads_mmbtu_per_hour] = load_profile
        end

        if addressable_load_fraction != 1.0
            heating_load_inputs[:addressable_load_fraction] = addressable_load_fraction
        end
        heating_load_inputs[:year] = year

        heating_load = HeatingLoad(; heating_load_inputs...,
                                    load_type = load_type,
                                    latitude=latitude, 
                                    longitude=longitude,
                                    annual_mmbtu=annual_mmbtu,
                                    monthly_mmbtu=monthly_mmbtu,
                                    existing_boiler_efficiency=boiler_efficiency
                                )

        load_series = heating_load.loads_kw ./ boiler_efficiency ./ KWH_PER_MMBTU  # [MMBtu/hr fuel]
        heating_monthly_energy = get_monthly_energy(load_series; year=year)
    
        response = Dict([
            ("load_type", load_type),
            ("loads_mmbtu_per_hour", round.(load_series, digits=3)),
            ("annual_mmbtu", round(sum(load_series), digits=3)),
            ("monthly_mmbtu", round.(heating_monthly_energy, digits=3)),
            ("min_mmbtu_per_hour", round(minimum(load_series), digits=3)),
            ("mean_mmbtu_per_hour", round(sum(load_series) / length(load_series), digits=3)),
            ("max_mmbtu_per_hour", round(maximum(load_series), digits=3))
        ])
    
        return response
    end    

    if load_type == "cooling"
        error_list = []
        for key in keys(d)
            if occursin("_kw", key) || occursin("_mmbtu", key)
                append!(error_list, [key])
            end
        end
        if !isempty(error_list)
            throw(@error("Invalid key(s) $error_list for load_type=cooling"))
        end          

        # First check if one of the "fraction" inputs were given, which supersedes doe_reference_name
        annual_fraction = get(d, "annual_fraction", nothing)
        if !isnothing(annual_fraction)
            cooling_fraction_series = ones(8760) * annual_fraction
            response = Dict([
                ("loads_fraction", round.(cooling_fraction_series, digits=3)),
                ("annual_fraction", round(sum(cooling_fraction_series) / length(cooling_fraction_series), digits=3)),  # should equal input annual_fraction
                ("min_fraction", round(minimum(cooling_fraction_series), digits=3)),
                ("mean_fraction", round(sum(cooling_fraction_series) / len(cooling_fraction_series), digits=3)),
                ("max_fraction", round(maximum(cooling_fraction_series), digits=3)),
                    ])
            return response
        end
        monthly_fraction = get(d, "monthly_fraction", Real[])
        if !isempty(monthly_fraction)
            if length(monthly_fraction) > 1
                if !(length(monthly_fraction) == 12)
                    throw(@error("monthly_fraction must contain a value for each of the 12 months"))
                end                     
                bad_index = []
                for (i, frac) in enumerate(monthly_fraction)
                    if isnothing(frac) || frac < 0.0 || frac > 1.0
                        append!(bad_index, i)
                    end
                end
                if length(bad_index) > 0
                    throw(@error("monthly_fraction must contain a value between 0-1 for each month, and it is not valid for these months: $bad_index"))
                end
            end
            days_in_month = [daysinmonth(Date(string(year) * "-" * string(month))) for month in 1:12]
            fraction_series = []
            for i in 1:12
                if month == 12 && isleapyear(year)
                    days_in_month[i] -= 1
                end
                append!(fraction_series, fill!(zeros(days_in_month[i] * 24), monthly_fraction[i]))
            end
            response = Dict([
                ("loads_fraction", round.(fraction_series, digits=3)),
                ("annual_fraction", round(sum(fraction_series) / length(fraction_series), digits=3)),
                ("min_fraction", round(minimum(fraction_series), digits=3)),
                ("mean_fraction", round(sum(fraction_series) / length(fraction_series), digits=3)),
                ("max_fraction", round(maximum(fraction_series), digits=3)),
                ])
            return response
        end

        # Check if doe_refernce_name along with annual or monthly tonhour was given, if not one of the fraction inputs
        if !isnothing(doe_reference_name)
            # Annual loads (default is nothing)
            annual_tonhour = get(d, "annual_tonhour", nothing)
            # Monthly loads (default is empty list)
            monthly_tonhour = get(d, "monthly_tonhour", Real[])
            if !isempty(monthly_tonhour)
                if !(length(monthly_tonhour) == 12)
                    throw(@error("monthly_tonhour must contain a value for each of the 12 months"))
                end                    
                bad_index = []
                for (i, mmbtu) in enumerate(monthly_tonhour)
                    if isnothing(mmbtu)
                        append!(bad_index, i)
                    end
                end
                if !isempty(bad_index)
                    throw(@error("monthly_tonhour must contain a value for each month, and it is null for these months: $bad_index"))
                end
            end

            if isnothing(annual_tonhour) && isempty(monthly_tonhour)
                throw(@error("Use load_type=electric to get cooling load for buildings with no annual_tonhour or monthly_tonhour input (response.cooling_defaults)"))
            end

            # Build dependent inputs for cooling load
            cooling_load_inputs = Dict{Symbol, Any}()
            if length(doe_reference_name) > 1
                cooling_load_inputs[:blended_doe_reference_names] = doe_reference_name
                cooling_load_inputs[:blended_doe_reference_percents] = percent_share_list
            else
                cooling_load_inputs[:doe_reference_name] = doe_reference_name[1]
            end
            cooling_load_inputs[:year] = year     

            cooling_load = CoolingLoad(; cooling_load_inputs...,
                                        latitude = latitude, 
                                        longitude = longitude,
                                        annual_tonhour = annual_tonhour,
                                        monthly_tonhour = monthly_tonhour
                                        )

            cooling_load_series = cooling_load.loads_kw_thermal ./ KWH_THERMAL_PER_TONHOUR

            response = Dict([
                ("loads_ton", round.(cooling_load_series, digits=3)),
                ("annual_tonhour", round(sum(cooling_load_series), digits=3)),
                ("chiller_cop", round(cooling_load.existing_chiller_cop, digits=3)),
                ("min_ton", round(minimum(cooling_load_series), digits=3)),
                ("mean_ton", round(sum(cooling_load_series) / length(cooling_load_series), digits=3)),
                ("max_ton", round(maximum(cooling_load_series), digits=3)),
                ])
            return response
        else
            throw(@error("Please supply a doe_reference_name and optional scaling parameters (annual_tonhour or monthly_tonhour), or annual_fraction, or monthly_fraction."))
        end
    end
end