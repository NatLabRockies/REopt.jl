# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ElectricLoad` is a required REopt input with the following keys and default values:
```julia
    loads_kw::Array{<:Real,1} = Real[],
    normalize_and_scale_load_profile_input::Bool = false,  # Takes loads_kw and normalizes and scales it to annual_kwh or monthly_totals_kwh
    path_to_csv::String = "", # for csv containing loads_kw
    doe_reference_name::String = "",
    blended_doe_reference_names::Array{String, 1} = String[],
    blended_doe_reference_percents::Array{<:Real,1} = Real[], # Values should be between 0-1 and sum to 1.0
    year::Union{Int, Nothing} = doe_reference_name ≠ "" || blended_doe_reference_names ≠ String[] ? 2017 : nothing, # used in ElectricTariff to align rate schedule with weekdays/weekends. DOE CRB profiles defaults to using 2017. If providing load data, specify year of data.
    city::String = "",
    annual_kwh::Union{Real, Nothing} = nothing,
    monthly_totals_kwh::Array{<:Real,1} = Real[],
    critical_loads_kw::Union{Nothing, Array{Real,1}} = nothing,
    loads_kw_is_net::Bool = true,
    critical_loads_kw_is_net::Bool = false,
    critical_load_fraction::Real = off_grid_flag ? 1.0 : 0.5, # if off grid must be 1.0, else 0.5
    operating_reserve_required_fraction::Real = off_grid_flag ? 0.1 : 0.0, # if off grid, 10%, else must be 0%. Applied to each time_step as a % of electric load.
    min_load_met_annual_fraction::Real = off_grid_flag ? 0.99999 : 1.0 # if off grid, 99.999%, else must be 100%. Applied to each time_step as a % of electric load.
```

!!! note "Required inputs"
    Must provide either `loads_kw` or `path_to_csv` or [`doe_reference_name` and `city`] or `doe_reference_name` or [`blended_doe_reference_names` and `blended_doe_reference_percents`]. 

    When only `doe_reference_name` is provided the `Site.latitude` and `Site.longitude` are used to look up the ASHRAE climate zone, which determines the appropriate DoE Commercial Reference Building profile.

    When using the [`doe_reference_name` and `city`] option, choose `city` from one of the cities used to represent the ASHRAE climate zones:
    - Albuquerque
    - Atlanta
    - Baltimore
    - Boulder
    - Chicago
    - Duluth
    - Fairbanks
    - Helena
    - Houston
    - LosAngeles
    - LasVegas
    - Miami
    - Minneapolis
    - Phoenix
    - SanFrancisco
    - Seattle
    and `doe_reference_name` from:
    - FastFoodRest
    - FullServiceRest
    - Hospital
    - LargeHotel
    - LargeOffice
    - MediumOffice
    - MidriseApartment
    - Outpatient
    - PrimarySchool
    - RetailStore
    - SecondarySchool
    - SmallHotel
    - SmallOffice
    - StripMall
    - Supermarket
    - Warehouse
    - FlatLoad # constant load year-round
    - FlatLoad_24_5 # constant load all hours of the weekdays
    - FlatLoad_16_7 # two 8-hour shifts for all days of the year; 6-10 a.m.
    - FlatLoad_16_5 # two 8-hour shifts for the weekdays; 6-10 a.m.
    - FlatLoad_8_7 # one 8-hour shift for all days of the year; 9 a.m.-5 p.m.
    - FlatLoad_8_5 # one 8-hour shift for the weekdays; 9 a.m.-5 p.m.

    Each `city` and `doe_reference_name` combination has a default `annual_kwh`, or you can provide your
    own `annual_kwh` or `monthly_totals_kwh` and the reference profile will be scaled appropriately.


!!! note "Year" 
    The ElectricLoad `year` is used in ElectricTariff to align rate schedules with weekdays/weekends. If providing your own `loads_kw`, ensure the `year` matches the year of your data.
    If utilizing `doe_reference_name` or `blended_doe_reference_names`, the default year of 2017 is used because these load profiles start on a Sunday.
"""
mutable struct ElectricLoad  # mutable to adjust (critical_)loads_kw based off of (critical_)loads_kw_is_net
    loads_kw::Array{Real,1}
    year::Int  # used in ElectricTariff to align rate schedule with weekdays/weekends
    critical_loads_kw::Array{Real,1}
    loads_kw_is_net::Bool
    critical_loads_kw_is_net::Bool
    city::String
    operating_reserve_required_fraction::Real
    min_load_met_annual_fraction::Real
    
    function ElectricLoad(;
        off_grid_flag::Bool = false,
        loads_kw::Array{<:Real,1} = Real[],
        normalize_and_scale_load_profile_input::Bool = false,
        path_to_csv::String = "",
        doe_reference_name::String = "",
        blended_doe_reference_names::Array{String, 1} = String[],
        blended_doe_reference_percents::Array{<:Real,1} = Real[],
        year::Union{Int, Nothing} = doe_reference_name ≠ "" || blended_doe_reference_names ≠ String[] ? 2017 : nothing, # used in ElectricTariff to align rate schedule with weekdays/weekends. DOE CRB profiles 2017 by default. If providing load data, specify year of data.
        city::String = "",
        annual_kwh::Union{Real, Nothing} = nothing,
        monthly_totals_kwh::Array{<:Real,1} = Real[],
        critical_loads_kw::Union{Nothing, Array{Real,1}} = nothing,
        loads_kw_is_net::Bool = true,
        critical_loads_kw_is_net::Bool = false,
        critical_load_fraction::Real = off_grid_flag ? 1.0 : 0.5, # if off grid, must be 1.0, else 0.5
        latitude::Real,
        longitude::Real,
        time_steps_per_hour::Int = 1,
        operating_reserve_required_fraction::Real = off_grid_flag ? 0.1 : 0.0, # if off grid, 10%, else must be 0%
        min_load_met_annual_fraction::Real = off_grid_flag ? 0.99999 : 1.0 # if off grid, 99.999%, else must be 100%. Applied to each time_step as a % of electric load.
        )
        
        if off_grid_flag
            if !isnothing(critical_loads_kw)
                @warn "ElectricLoad critical_loads_kw will be ignored because `off_grid_flag` is true. If you wish to alter the load profile or load met, adjust the loads_kw or min_load_met_annual_fraction."
                critical_loads_kw = nothing
            end
            if critical_load_fraction != 1.0
                @warn "ElectricLoad critical_load_fraction must be 1.0 (100%) for off-grid scenarios. Any other value will be overriden when `off_grid_flag` is true. If you wish to alter the load profile or load met, adjust the loads_kw or min_load_met_annual_fraction."
                critical_load_fraction = 1.0
            end
        end

        if !(off_grid_flag)
            if !(operating_reserve_required_fraction == 0.0)
                @warn "ElectricLoad operating_reserve_required_fraction must be 0 for on-grid scenarios. Operating reserve requirements apply to off-grid scenarios only."
                operating_reserve_required_fraction = 0.0
            elseif !(min_load_met_annual_fraction == 1.0)
                @warn "ElectricLoad min_load_met_annual_fraction must be 1.0 for on-grid scenarios. This input applies to off-grid scenarios only."
                min_load_met_annual_fraction = 1.0
            end
        end

        if isnothing(year)
            throw(@error("Must provide the year when using loads_kw input."))
        end 

        if length(loads_kw) > 0 && !normalize_and_scale_load_profile_input

            if !(length(loads_kw) / time_steps_per_hour ≈ 8760)
                throw(@error("Provided electric load does not match the time_steps_per_hour."))
            end
        
        elseif length(loads_kw) > 0 && normalize_and_scale_load_profile_input
            if !isempty(doe_reference_name)
                @warn "loads_kw provided with normalize_and_scale_load_profile_input = true, so ignoring location and building type inputs, and only using the year and annual or monthly energy inputs with the load profile"
            end
            if isnothing(annual_kwh) && isempty(monthly_totals_kwh)
                throw(@error("Provided loads_kw with normalize_and_scale_load_profile_input=true, but no annual_kwh or monthly_totals_kwh was provided"))
            end
            # Using dummy values for all unneeded location and building type arguments for normalizing and scaling load profile input
            normalized_profile = loads_kw ./ sum(loads_kw)
            loads_kw = BuiltInElectricLoad("Chicago", "LargeOffice", 41.8333, -88.0616, year, annual_kwh, monthly_totals_kwh, normalized_profile)            

        elseif !isempty(path_to_csv)
            try
                loads_kw = vec(readdlm(path_to_csv, ',', Float64, '\n'))
            catch e
                throw(@error("Unable to read in electric load profile from $path_to_csv. Please provide a valid path to a csv with no header."))
            end

            if !(length(loads_kw) / time_steps_per_hour ≈ 8760)
                throw(@error("Provided electric load does not match the time_steps_per_hour."))
            end
    
        elseif !isempty(doe_reference_name)
            loads_kw = BuiltInElectricLoad(city, doe_reference_name, latitude, longitude, year, annual_kwh, monthly_totals_kwh)

        elseif length(blended_doe_reference_names) > 1 && 
            length(blended_doe_reference_names) == length(blended_doe_reference_percents)
            loads_kw = blend_and_scale_doe_profiles(BuiltInElectricLoad, latitude, longitude, year, 
                                                    blended_doe_reference_names, blended_doe_reference_percents, city, 
                                                    annual_kwh, monthly_totals_kwh)
        else
            throw(@error("Cannot construct ElectricLoad. You must provide either [loads_kw], [doe_reference_name, city], 
                  [doe_reference_name, latitude, longitude], 
                  or [blended_doe_reference_names, blended_doe_reference_percents] with city or latitude and longitude."))
        end

        if length(loads_kw) < 8760*time_steps_per_hour
            loads_kw = repeat(loads_kw, inner=Int(time_steps_per_hour / (length(loads_kw)/8760)))
            @warn "Repeating electric loads in each hour to match the time_steps_per_hour."
        end

        if isnothing(critical_loads_kw)
            critical_loads_kw = critical_load_fraction * loads_kw
        end

        new(
            loads_kw,
            year,
            critical_loads_kw,
            loads_kw_is_net,
            critical_loads_kw_is_net,
            city,
            operating_reserve_required_fraction,
            min_load_met_annual_fraction
        )
    end
end


function BuiltInElectricLoad(
    city::String,
    buildingtype::String,
    latitude::Real,
    longitude::Real,
    year::Int,
    annual_kwh::Union{Real, Nothing}=nothing,
    monthly_totals_kwh::Vector{<:Real}=Real[],
    normalized_profile::Union{Vector{Float64}, Vector{<:Real}}=Real[]
    )
    
    electric_annual_kwh = JSON.parsefile(joinpath(@__DIR__, "..", "..", "data", "load_profiles", "total_electric_annual_kwh.json"))

    if !(buildingtype in DEFAULT_BUILDINGS)
        throw(@error("buildingtype $(buildingtype) not in $(DEFAULT_BUILDINGS)."))
    end

    if isempty(city)
        city = find_ashrae_zone_city(latitude, longitude)
    end

    if isnothing(annual_kwh)
        # Use FlatLoad annual_kwh from data for all types of FlatLoads because we don't have separate data for e.g. FlatLoad_16_7
        if occursin("FlatLoad", buildingtype)
            annual_kwh = electric_annual_kwh[city][lowercase("FlatLoad")]
        else
            annual_kwh = electric_annual_kwh[city][lowercase(buildingtype)]
        end
    end

    built_in_load("electric", city, buildingtype, year, annual_kwh, monthly_totals_kwh, nothing, normalized_profile)
end
