# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
# `HeatingLoad` is a base function for the types of heating load inputs with the following keys and default values:
```julia
    load_type::String = "",  # Valid options are space_heating for SpaceHeatingLoad, domestic_hot_water for DomesticHotWaterLoad, and process_heat for ProcessHeatLoad
    doe_reference_name::String = "",  # For SpaceHeatingLoad and DomesticHotWaterLoad
    blended_doe_reference_names::Array{String, 1} = String[],  # For SpaceHeatingLoad and DomesticHotWaterLoad
    blended_doe_reference_percents::Array{<:Real,1} = Real[],  # For SpaceHeatingLoad and DomesticHotWaterLoad
    industrial_reference_name::String = "",  # For ProcessHeatLoad
    blended_industrial_reference_names::Array{String, 1} = String[],  # For ProcessHeatLoad
    blended_industrial_reference_percents::Array{<:Real,1} = Real[],  # For ProcessHeatLoad
    city::String = "",
    year::Union{Int, Nothing} = doe_reference_name ≠ "" || blended_doe_reference_names ≠ String[] || industrial_reference_name ≠ "" || blended_industrial_reference_names ≠ String[] ? 2017 : nothing, # CRB profiles are 2017 by default. If providing load profile, specify year of data.
    annual_mmbtu::Union{Real, Nothing} = nothing,
    monthly_mmbtu::Array{<:Real,1} = Real[],
    addressable_load_fraction::Any = 1.0,  # Fraction of input fuel load which is addressable by heating technologies. Can be a scalar or vector with length aligned with use of monthly_mmbtu or fuel_loads_mmbtu_per_hour.
    fuel_loads_mmbtu_per_hour::Array{<:Real,1} = Real[], # Vector of space heating fuel loads [mmbtu/hr]. Length must equal 8760 * `Settings.time_steps_per_hour`
    normalize_and_scale_load_profile_input::Bool = false,  # Takes fuel_loads_mmbtu_per_hour and normalizes and scales it to annual_mmbtu or monthly_mmbtu 
    existing_boiler_efficiency::Real = NaN
```

There are different ways to define a heating load:
1. A time-series via the `fuel_loads_mmbtu_per_hour`,
2. Scaling a DOE Commercial Reference Building (CRB) or industrial reference profile or a blend of profiles to either the `annual_mmbtu` or `monthly_mmbtu` values;
3. Using the same `doe_reference_name` or `blended_doe_reference_names` from the `ElectricLoad`.
4. A time-series via the `fuel_loads_mmbtu_per_hour` along with `annual_mmbtu` or `monthly_mmbtu` with `normalize_and_scale_load_profile_input`=true

When using an `ElectricLoad` defined from a `doe_reference_name` or `blended_doe_reference_names` 
one only needs to provide an empty Dict in the scenario JSON to add a `SpaceHeatingLoad` to a 
`Scenario`, i.e.:
```json
...
"ElectricLoad": {"doe_reference_name": "MidriseApartment"},
"SpaceHeatingLoad" : {},
...
```
In this case the values provided for `doe_reference_name`, or  `blended_doe_reference_names` and 
`blended_doe_reference_percents` are copied from the `ElectricLoad` to the the particular `HeatingLoad` type.

!!! note for all heating loads
    Hot water, space heating, and process heat "load" inputs are in terms of energy input required (boiler fuel), 
    not the actual end use thermal energy demand. The fuel energy is multiplied by the existing_boiler_efficiency to get the actual energy 
    demand.
"""
function HeatingLoad(;
    load_type::String = "",
    doe_reference_name::String = "",
    blended_doe_reference_names::Array{String, 1} = String[],
    blended_doe_reference_percents::Array{<:Real,1} = Real[],
    industrial_reference_name::String = "",
    blended_industrial_reference_names::Array{String, 1} = String[],
    blended_industrial_reference_percents::Array{<:Real,1} = Real[],    
    city::String = "",
    year::Union{Int, Nothing} = doe_reference_name ≠ "" || blended_doe_reference_names ≠ String[] || industrial_reference_name ≠ "" || blended_industrial_reference_names ≠ String[] ? 2017 : nothing, # CRB profiles are 2017 by default. If providing load profile, specify year of data.
    annual_mmbtu::Union{Real, Nothing} = nothing,
    monthly_mmbtu::Array{<:Real,1} = Real[],
    addressable_load_fraction::Any = 1.0,
    fuel_loads_mmbtu_per_hour::Array{<:Real,1} = Real[],
    normalize_and_scale_load_profile_input::Bool = false,
    time_steps_per_hour::Int = 1, # corresponding to `fuel_loads_mmbtu_per_hour`
    latitude::Real = 0.0,
    longitude::Real = 0.0,
    existing_boiler_efficiency::Real = NaN
    )

    # Determine which type of heating load to build
    if load_type == "space_heating"
        load = :SpaceHeatingLoad
        struct_type = SpaceHeatingLoad
    elseif load_type == "domestic_hot_water"
        load = :DomesticHotWaterLoad
        struct_type = DomesticHotWaterLoad
    elseif load_type == "process_heat"
        load = :ProcessHeatLoad
        struct_type = ProcessHeatLoad
        city = "Industrial"
        doe_reference_name = industrial_reference_name
        blended_doe_reference_names = blended_industrial_reference_names
        blended_doe_reference_percents = blended_industrial_reference_percents     
    else
        throw(@error("load_type must be 'space_heating', 'domestic_hot_water', or 'process_heat'"))
    end

    if isnothing(year)
        throw(@error("Must provide the year when using fuel_loads_mmbtu_per_hour input."))
    end
    if !isnothing(annual_mmbtu) && !isempty(monthly_mmbtu)
        throw(@error("Cannot provide both annual_mmbtu and monthly_mmbtu to scale the $load profile."))
    elseif length(monthly_mmbtu) > 0 && length(monthly_mmbtu) != 12
        throw(@error("monthly_mmbtu must be length 12 if provided."))
    end

    fuel_loads_mmbtu_per_hour = check_and_adjust_load_length(fuel_loads_mmbtu_per_hour, time_steps_per_hour, "$load")

    if length(addressable_load_fraction) > 1
        if normalize_and_scale_load_profile_input && length(addressable_load_fraction) == length(fuel_loads_mmbtu_per_hour)
            throw(@error("Cannot use timeseries `addressable_load_fraction` with `fuel_loads_mmbtu_per_hour` when scaling fuel loads."))
        end
        if !isempty(fuel_loads_mmbtu_per_hour) && !normalize_and_scale_load_profile_input
            n_fuel = length(fuel_loads_mmbtu_per_hour)
            n_addr = length(addressable_load_fraction)
            
            if n_addr != n_fuel && n_addr != 12
                if n_fuel % n_addr == 0
                    addressable_load_fraction = repeat(addressable_load_fraction, inner=Int(n_fuel / n_addr))
                else
                    throw(@error("`addressable_load_fraction` must be a scalar or an array of length 12 if `monthly_mmbtu` is input or of length `fuel_loads_mmbtu_per_hour`"))
                end
            end
        elseif !isempty(monthly_mmbtu) && length(addressable_load_fraction) != 12
            throw(@error("`addressable_load_fraction` must be a scalar or an array of length 12 if `monthly_mmbtu` is input or of length `fuel_loads_mmbtu_per_hour`"))
        end
        addressable_load_fraction = convert(Vector{Real}, addressable_load_fraction) # Can be monthly or per timestep
    elseif typeof(addressable_load_fraction) <: Vector{}
        addressable_load_fraction = convert(Real, addressable_load_fraction[1])  
    else
        addressable_load_fraction = convert(Real, addressable_load_fraction)            
    end

    if length(fuel_loads_mmbtu_per_hour) > 0 && ( !isempty(doe_reference_name) || length(blended_doe_reference_names) > 0 )
        @warn "$load fuel_loads_mmbtu_per_hour was provided, so doe_reference_name and/or blended_doe_reference_names will be ignored."
    end

    if length(fuel_loads_mmbtu_per_hour) > 0 && !normalize_and_scale_load_profile_input

        loads_kw = fuel_loads_mmbtu_per_hour .* (KWH_PER_MMBTU * existing_boiler_efficiency) .* addressable_load_fraction
        unaddressable_annual_fuel_mmbtu = sum(fuel_loads_mmbtu_per_hour .* (1 .- addressable_load_fraction))  / time_steps_per_hour

    elseif length(fuel_loads_mmbtu_per_hour) > 0 && ( !isnothing(annual_mmbtu) || !isempty(monthly_mmbtu) ) && !normalize_and_scale_load_profile_input
            throw(@error("If providing $load fuel_loads_mmbtu_per_hour and annual_mmbtu or monthly_mmbtu, must set normalize_and_scale_load_profile_input=true."))
    elseif length(fuel_loads_mmbtu_per_hour) > 0 && normalize_and_scale_load_profile_input

        if isnothing(annual_mmbtu) && isempty(monthly_mmbtu)
            throw(@error("Provided $load fuel_loads_mmbtu_per_hour with normalize_and_scale_load_profile_input=true, but no annual_mmbtu or monthly_mmbtu was provided"))
        end

        # Using dummy values for all unneeded location and building type arguments for normalizing and scaling load profile input
        normalized_profile = fuel_loads_mmbtu_per_hour ./ sum(fuel_loads_mmbtu_per_hour)
        loads_kw = BuiltInHeatingLoad(load_type, "Chicago", "FlatLoad", 41.8333, -88.0616, year, addressable_load_fraction, annual_mmbtu, monthly_mmbtu, existing_boiler_efficiency, normalized_profile; time_steps_per_hour = time_steps_per_hour)               
        unaddressable_annual_fuel_mmbtu = get_unaddressable_fuel(addressable_load_fraction, annual_mmbtu, monthly_mmbtu, loads_kw, existing_boiler_efficiency)
    elseif !isempty(doe_reference_name)
        loads_kw = BuiltInHeatingLoad(load_type, city, doe_reference_name, latitude, longitude, year, addressable_load_fraction, annual_mmbtu, monthly_mmbtu, existing_boiler_efficiency)
        if length(blended_doe_reference_names) > 0
            @warn "SpaceHeatingLoad doe_reference_name was provided, so blended_doe_reference_names will be ignored."
        end
        unaddressable_annual_fuel_mmbtu = get_unaddressable_fuel(addressable_load_fraction, annual_mmbtu, monthly_mmbtu, loads_kw, existing_boiler_efficiency)           
    elseif length(blended_doe_reference_names) > 0 && 
        length(blended_doe_reference_names) == length(blended_doe_reference_percents)
        loads_kw = blend_and_scale_doe_profiles(BuiltInHeatingLoad, latitude, longitude, year, 
                                                blended_doe_reference_names, blended_doe_reference_percents, city, 
                                                annual_mmbtu, monthly_mmbtu, addressable_load_fraction,
                                                existing_boiler_efficiency, load_type)
        unaddressable_annual_fuel_mmbtu = get_unaddressable_fuel(addressable_load_fraction, annual_mmbtu, monthly_mmbtu, loads_kw, existing_boiler_efficiency)                                                   
    else
        throw(@error("Cannot construct $load. You must provide either [fuel_loads_mmbtu_per_hour], 
            [doe_reference_name, latitude, longitude], or [blended_doe_reference_names, blended_doe_reference_percents, latitude, longitude]."))
    end

    # Adjust load length for CRBs, which are always 8760, if needed (after energy scaling and blending)
    if length(loads_kw) < 8760*time_steps_per_hour
        loads_kw = repeat(loads_kw, inner=Int(time_steps_per_hour / (length(loads_kw)/8760)))
        @warn "Repeating $load in each hour to match the time_steps_per_hour."
    end

    struct_type(
        loads_kw,
        (sum(loads_kw)/time_steps_per_hour)/KWH_PER_MMBTU,
        unaddressable_annual_fuel_mmbtu
    )
end

struct DomesticHotWaterLoad
    loads_kw::Array{Real, 1}
    annual_mmbtu::Real
    unaddressable_annual_fuel_mmbtu::Real
end

struct SpaceHeatingLoad
    loads_kw::Array{Real, 1}
    annual_mmbtu::Real
    unaddressable_annual_fuel_mmbtu::Real
end

struct ProcessHeatLoad
    loads_kw::Array{Real, 1}
    annual_mmbtu::Real
    unaddressable_annual_fuel_mmbtu::Real
end

function BuiltInHeatingLoad(
    load_type::String,
    city::String,
    buildingtype::String,
    latitude::Real,
    longitude::Real,
    year::Int,
    addressable_load_fraction::Union{<:Real, AbstractVector{<:Real}},
    annual_mmbtu::Union{Real, Nothing}=nothing,
    monthly_mmbtu::Vector{<:Real}=Real[],
    existing_boiler_efficiency::Union{Real, Nothing}=nothing,
    normalized_profile::Union{Vector{Float64}, Vector{<:Real}}=Real[]; # for user-provided load profile
    time_steps_per_hour::Int = 1 # only used with normalized_profile
    )

    # Load the appropriate default annual energy data based on load_type
    if load_type == "space_heating"
        default_annual_mmbtu = JSON.parsefile(joinpath(@__DIR__, "..", "..", "data", "load_profiles", "space_heating_annual_mmbtu.json"))
    elseif load_type == "domestic_hot_water"
        default_annual_mmbtu = JSON.parsefile(joinpath(@__DIR__, "..", "..", "data", "load_profiles", "domestic_hot_water_annual_mmbtu.json"))
    elseif load_type == "process_heat"
        default_annual_mmbtu = Dict(
            "Industrial" => Dict(
                "Chemical" => 15000.0,  # mid-sized chemical processes
                "FlatLoad" => 10000,  #  continuous operations throughout the year
                "Warehouse" => 7000
            )
        )
        city = "Industrial"
    else
        throw(@error("For BuiltInHeatingLoad, load_type must be 'space_heating', 'domestic_hot_water', or 'process_heat'"))
    end

    if isempty(city)
        city = find_ashrae_zone_city(latitude, longitude)
    end
    if (load_type in ["space_heating", "domestic_hot_water"]) && !(buildingtype in DEFAULT_BUILDINGS)
        throw(@error("buildingtype $(buildingtype) not in $(DEFAULT_BUILDINGS)."))
    end
    if (load_type == "process_heat") && !(buildingtype in DEFAULT_PROCESS_TYPES)
        throw(@error("buildingtype $(buildingtype) not in $(DEFAULT_PROCESS_TYPES)."))
    end

    if isnothing(annual_mmbtu)
        # Use FlatLoad annual_mmbtu from data for all types of FlatLoads because we don't have separate data for e.g. FlatLoad_16_7
        if occursin("FlatLoad", buildingtype)
            annual_mmbtu = default_annual_mmbtu[city]["FlatLoad"]
        else
            annual_mmbtu = default_annual_mmbtu[city][buildingtype]
        end
    else # cannot use addressable_load_fraction with default CRB loads
        # if user provides normalized_profile and monthly values, monthly will be used instead of this annual value
        annual_mmbtu *= addressable_load_fraction 
    end

    if length(monthly_mmbtu) == 12
        monthly_mmbtu = monthly_mmbtu .* addressable_load_fraction
    end

    built_in_load(load_type, city, buildingtype, year, annual_mmbtu, monthly_mmbtu, 
                    existing_boiler_efficiency, normalized_profile; time_steps_per_hour=time_steps_per_hour)
end

"""
    get_unaddressable_fuel(addressable_load_fraction, annual_mmbtu, monthly_mmbtu, loads_kw, existing_boiler_efficiency)
    
Get unaddressable fuel load, for reporting
    :addressable_load_fraction is the fraction of the input fuel load that is addressable to supply by energy technologies, like CHP. Can be array of 12 or scalar.
    :annual_mmbtu and :monthly_mmbtu is assumed to be fuel, not thermal, in this function
    :loads_kw is assumed to be thermal in this function, with units of kw_thermal, so needs to be converted to fuel mmbtu
"""
function get_unaddressable_fuel(addressable_load_fraction, annual_mmbtu, monthly_mmbtu, loads_kw, existing_boiler_efficiency)
    # Get unaddressable fuel load, for reporting
    if !isempty(monthly_mmbtu)
        unaddressable_annual_fuel_mmbtu = sum(monthly_mmbtu .* (1 .- addressable_load_fraction))
    elseif !isnothing(annual_mmbtu)
        unaddressable_annual_fuel_mmbtu = annual_mmbtu * (1 - addressable_load_fraction)
    else # using the default CRB annual_mmbtu, so rely on loads_kw (thermal) assuming single addressable_load_fraction
        unaddressable_annual_fuel_mmbtu = sum(loads_kw) / (KWH_PER_MMBTU * existing_boiler_efficiency)                
    end
    return unaddressable_annual_fuel_mmbtu
end


"""
`CoolingLoad` is an optional REopt input with the following keys and default values:
```julia
    doe_reference_name::String = "",
    blended_doe_reference_names::Array{String, 1} = String[],
    blended_doe_reference_percents::Array{<:Real,1} = Real[],
    city::String = "",
    year::Int = doe_reference_name ≠ "" || blended_doe_reference_names ≠ String[] ? 2017 : nothing, # CRB profiles are 2017 by default. If providing load profile, specify year of data.    
    annual_tonhour::Union{Real, Nothing} = nothing,
    monthly_tonhour::Array{<:Real,1} = Real[],
    thermal_loads_ton::Array{<:Real,1} = Real[], # Vector of cooling thermal loads [ton] = [short ton hours/hour]. Length must equal 8760 * `Settings.time_steps_per_hour`
    annual_fraction_of_electric_load::Union{Real, Nothing} = nothing, # Fraction of total electric load that is used for cooling 
    monthly_fractions_of_electric_load::Array{<:Real,1} = Real[],
    per_time_step_fractions_of_electric_load::Array{<:Real,1} = Real[]
```


There are many ways to define a `CoolingLoad`:
1. a time-series via the `thermal_loads_ton`,
2. DoE Commercial Reference Building (CRB) profile or a blend of CRB profiles which uses the buildings' fraction of total electric for cooling profile applied to the `ElectricLoad`
3. scaling a DoE Commercial Reference Building (CRB) profile or a blend of CRB profiles using `annual_tonhour` or `monthly_tonhour`
4. the `annual_fraction_of_electric_load`, `monthly_fractions_of_electric_load`, or `per_time_step_fractions_of_electric_load` values, which get applied to the `ElectricLoad` to determine the cooling electric load;
5. or using the `doe_reference_name` or `blended_doe_reference_names` from the `ElectricLoad`.

The electric-based `loads_kw` of the `CoolingLoad` is a _subset_ of the total electric load `ElectricLoad`, so `CoolingLoad.loads_kw` for the BAU/conventional electric consumption of the `existing_chiller` is subtracted from the `ElectricLoad` for the non-cooling electric load balance constraint in the model. 

When using an `ElectricLoad` defined from a `doe_reference_name` or `blended_doe_reference_names` 
one only needs to provide an empty Dict in the scenario JSON to add a `CoolingLoad` to a 
`Scenario`, i.e.:
```json
...
"ElectricLoad": {"doe_reference_name": "MidriseApartment"},
"CoolingLoad" : {},
...
```
In this case the values provided for `doe_reference_name`, or  `blended_doe_reference_names` and 
`blended_doe_reference_percents` are copied from the `ElectricLoad` to the `CoolingLoad`.
"""
struct CoolingLoad
    loads_kw_thermal::Array{Real, 1}
    existing_chiller_cop::Real

    function CoolingLoad(;
        doe_reference_name::String = "",
        blended_doe_reference_names::Array{String, 1} = String[],
        blended_doe_reference_percents::Array{<:Real,1} = Real[],
        city::String = "",
        year::Union{Int, Nothing} = doe_reference_name ≠ "" || blended_doe_reference_names ≠ String[] ? 2017 : nothing, # CRB profiles are 2017 by default. If providing load profile, specify year of data.
        annual_tonhour::Union{Real, Nothing} = nothing,
        monthly_tonhour::Array{<:Real,1} = Real[],
        thermal_loads_ton::Array{<:Real,1} = Real[], # Vector of cooling thermal loads [ton] = [short ton hours/hour]. Length must equal 8760 * `Settings.time_steps_per_hour`
        annual_fraction_of_electric_load::Union{Real, Nothing} = nothing, # Fraction of total electric load that is used for cooling
        monthly_fractions_of_electric_load::Array{<:Real,1} = Real[],
        per_time_step_fractions_of_electric_load::Array{<:Real,1} = Real[],
        site_electric_load_profile = Real[],
        time_steps_per_hour::Int = 1,
        latitude::Float64=0.0,
        longitude::Float64=0.0,
        existing_chiller_cop::Union{Real, Nothing} = nothing, # Passed from ExistingChiller or set to a default
        existing_chiller_max_thermal_factor_on_peak_load::Union{Real, Nothing}= nothing # Passed from ExistingChiller or set to a default
    )

        if isnothing(year)
            throw(@error("Must provide the year when using inputs of thermal_loads_ton or per_time_step_fractions_of_electric_load."))
        end 

        # determine the timeseries of loads_kw_thermal
        loads_kw_thermal = nothing
        loads_kw = nothing
        if length(thermal_loads_ton) > 0
            if !(length(thermal_loads_ton) / time_steps_per_hour ≈ 8760)
                throw(@error("Provided cooling load does not match the time_steps_per_hour."))
            end
            loads_kw_thermal = thermal_loads_ton .* (KWH_THERMAL_PER_TONHOUR)
        
        elseif !isempty(per_time_step_fractions_of_electric_load) && (length(site_electric_load_profile) / time_steps_per_hour ≈ 8760)
            if !(length(per_time_step_fractions_of_electric_load) / time_steps_per_hour ≈ 8760)
                throw(@error("Provided cooling per_time_step_fractions_of_electric_load array does not match the time_steps_per_hour."))
            end
            loads_kw = per_time_step_fractions_of_electric_load .* site_electric_load_profile
        
        elseif !isempty(monthly_fractions_of_electric_load) && (length(site_electric_load_profile) / time_steps_per_hour ≈ 8760)
            if !(length(monthly_fractions_of_electric_load) ≈ 12)
                throw(@error("Provided cooling monthly_fractions_of_electric_load array does not have 12 values."))
            end
            timeseries = collect(DateTime(year,1,1) : Minute(60/time_steps_per_hour) : 
                                 DateTime(year,1,1) + Minute(8760*60 - 60/time_steps_per_hour))
            loads_kw = [monthly_fractions_of_electric_load[month(dt)] * site_electric_load_profile[ts] for (ts, dt) 
                        in enumerate(timeseries)]
        
        elseif !isnothing(annual_fraction_of_electric_load) && (length(site_electric_load_profile) / time_steps_per_hour ≈ 8760)
            loads_kw = annual_fraction_of_electric_load * site_electric_load_profile
        
        elseif !isempty(doe_reference_name)
            if isnothing(annual_tonhour) && isempty(monthly_tonhour)
                loads_kw = get_default_fraction_of_total_electric(city, doe_reference_name, 
                                            latitude, longitude, year) .* site_electric_load_profile
            else
                loads_kw = BuiltInCoolingLoad(city, doe_reference_name, latitude, longitude, year, 
                                          annual_tonhour, monthly_tonhour, existing_chiller_cop)
            end
        
        elseif length(blended_doe_reference_names) > 1 && 
            length(blended_doe_reference_names) == length(blended_doe_reference_percents)
            if isnothing(annual_tonhour) && isempty(monthly_tonhour)
                loads_kw = zeros(Int(8760*time_steps_per_hour))
                for (i, building) in enumerate(blended_doe_reference_names)
                    default_fraction = get_default_fraction_of_total_electric(city, building, latitude, longitude, year)
                    modified_fraction = default_fraction * blended_doe_reference_percents[i]
                    if length(site_electric_load_profile) > 8784
                        modified_fraction = repeat(modified_fraction, inner=time_steps_per_hour / (length(site_electric_load_profile)/8760))
                        @warn "Repeating cooling electric load in each hour to match the time_steps_per_hour."
                    end
                    loads_kw += site_electric_load_profile .* modified_fraction
                end
            else        
                loads_kw = blend_and_scale_doe_profiles(BuiltInCoolingLoad, latitude, longitude, year, 
                                                        blended_doe_reference_names, 
                                                        blended_doe_reference_percents, city, 
                                                        annual_tonhour, monthly_tonhour)
            end
        
        else
            throw(@error("Cannot construct BuiltInCoolingLoad. You must provide either [thermal_loads_ton], 
                [doe_reference_name, city], [blended_doe_reference_names, blended_doe_reference_percents, city],
                or the site_electric_load_profile along with one of [per_time_step_fractions_of_electric_load, monthly_fractions_of_electric_load, annual_fraction_of_electric_load]."))
        end

        if isnothing(loads_kw_thermal)  # have to convert electric loads_kw to thermal load
            if (!isnothing(annual_tonhour) || !isempty(monthly_tonhour)) && isnothing(existing_chiller_cop)
                # cop_unknown_thermal (4.55) was used to convert thermal to electric in BuiltInCoolingLoad, so need to use the same here to convert back
                #  in order to preserve the input tonhour amounts - however, the updated/actual existing_chiller_cop is still assigned based on user input or actual max ton load conditional defaults
                chiller_cop = get_existing_chiller_default_cop()
            elseif (!isempty(doe_reference_name) || !isempty(blended_doe_reference_names)) || isnothing(existing_chiller_cop)
                # Generated loads_kw (electric) above based on the building's default fraction of electric profile
                chiller_cop = get_existing_chiller_default_cop(;existing_chiller_max_thermal_factor_on_peak_load=existing_chiller_max_thermal_factor_on_peak_load, 
                                        max_load_kw=maximum(loads_kw))
            else
                chiller_cop = existing_chiller_cop
            end
            loads_kw_thermal = chiller_cop * loads_kw
        end

        # Now that cooling thermal loads_kw_thermal is known, update existing_chiller_cop if it was not input
        if isnothing(existing_chiller_cop)
            existing_chiller_cop = get_existing_chiller_default_cop(;existing_chiller_max_thermal_factor_on_peak_load=existing_chiller_max_thermal_factor_on_peak_load, 
                                        max_load_kw_thermal=maximum(loads_kw_thermal))
        end

        if length(loads_kw_thermal) < 8760*time_steps_per_hour && length(loads_kw_thermal) % 8760 == 0
            loads_kw_thermal = repeat(loads_kw_thermal, inner=Int(time_steps_per_hour / 
                               (length(loads_kw_thermal)/8760)))
            @warn "Repeating cooling loads in each hour to match the time_steps_per_hour."
        end

        new(
            loads_kw_thermal,
            existing_chiller_cop
        )
    end
end

function get_default_fraction_of_total_electric(city, doe_reference_name, latitude, longitude, year)
    crb_total_elec_loads_kw = BuiltInElectricLoad(city, doe_reference_name, latitude, longitude, year)

    crb_cooling_elec_loads_kw = BuiltInCoolingLoad(city, doe_reference_name, latitude, longitude, year, nothing, Real[], nothing)
    
    default_fraction_of_total_electric_profile = crb_cooling_elec_loads_kw ./
                                                    max.(crb_total_elec_loads_kw, repeat([1.0E-6], length(crb_total_elec_loads_kw)))
    return default_fraction_of_total_electric_profile
end

"""
function get_existing_chiller_default_cop(; existing_chiller_max_thermal_factor_on_peak_load=nothing, 
                                            max_load_kw=nothing, 
                                            max_load_kw_thermal=nothing)
This function returns the default value for ExistingChiller.cop based on:
    1. No information about load, returns average of lower and higher cop default values (`cop_unknown_thermal`)
    2. If the cooling electric `max_load_kw` is known, we first guess the thermal load profile using `cop_unknown_thermal`,
        and then we use the default logic to determine the `existing_chiller_cop` based on the peak thermal load with a thermal factor multiplier.
    3. If the cooling thermal `max_load_kw_thermal` is known, same as 2. but we don't have to guess the cop to convert electric to thermal load first.
"""
function get_existing_chiller_default_cop(; existing_chiller_max_thermal_factor_on_peak_load=nothing, max_load_kw=nothing, max_load_kw_thermal=nothing)
    cop_less_than_100_ton = 4.40
    cop_more_than_100_ton = 4.69
    cop_unknown_thermal = (cop_less_than_100_ton + cop_more_than_100_ton) / 2.0
    max_cooling_load_ton = nothing
    if !isnothing(max_load_kw_thermal)
        max_cooling_load_ton = max_load_kw_thermal / KWH_THERMAL_PER_TONHOUR
    elseif !isnothing(max_load_kw)
        max_cooling_load_ton = max_load_kw / KWH_THERMAL_PER_TONHOUR * cop_unknown_thermal
    end
    if isnothing(max_cooling_load_ton) || isnothing(existing_chiller_max_thermal_factor_on_peak_load)
        return cop_unknown_thermal
    elseif max_cooling_load_ton * existing_chiller_max_thermal_factor_on_peak_load < 100.0
        return cop_less_than_100_ton
    else
        return cop_more_than_100_ton
    end
end

function BuiltInCoolingLoad(
    city::String,
    buildingtype::String,
    latitude::Float64,
    longitude::Float64,
    year::Int,
    annual_tonhour::Union{Real, Nothing}=nothing,
    monthly_tonhour::Vector{<:Real}=Real[],
    existing_chiller_cop::Union{Real, Nothing}=nothing
    )

    cooling_electric_annual_kwh = JSON.parsefile(joinpath(@__DIR__, "..", "..", "data", "load_profiles", "cooling_electric_annual_kwh.json"))

    if isempty(city)
        city = find_ashrae_zone_city(latitude, longitude)
    end
    if !(buildingtype in DEFAULT_BUILDINGS)
        throw(@error("buildingtype $(buildingtype) not in $(DEFAULT_BUILDINGS)."))
    end
    # Set initial existing_chiller_cop to "cop_unknown_thermal" if not passed in; we will update existing_chiller_cop once the load profile is determined
    if isnothing(existing_chiller_cop)
        existing_chiller_cop = get_existing_chiller_default_cop()
    end
    if isnothing(annual_tonhour)
        # Use FlatLoad annual_kwh from data for all types of FlatLoads because we don't have separate data for e.g. FlatLoad_16_7
        if occursin("FlatLoad", buildingtype)
            annual_kwh = cooling_electric_annual_kwh[city]["FlatLoad"]
        else
            annual_kwh = cooling_electric_annual_kwh[city][buildingtype]
        end
    else
        annual_kwh = annual_tonhour * KWH_THERMAL_PER_TONHOUR / existing_chiller_cop
    end
    monthly_kwh = Real[]
    if length(monthly_tonhour) == 12
        monthly_kwh = monthly_tonhour * KWH_THERMAL_PER_TONHOUR / existing_chiller_cop
    end
    built_in_load("cooling", city, buildingtype, year, annual_kwh, monthly_kwh)
end