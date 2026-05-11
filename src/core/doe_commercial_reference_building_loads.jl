# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
const DEFAULT_BUILDINGS = [
    "FastFoodRest",
    "FullServiceRest",
    "Hospital",
    "LargeHotel",
    "LargeOffice",
    "MediumOffice",
    "MidriseApartment",
    "Outpatient",
    "PrimarySchool",
    "RetailStore",
    "SecondarySchool",
    "SmallHotel",
    "SmallOffice",
    "StripMall",
    "Supermarket",
    "Warehouse",
    "FlatLoad",
    "FlatLoad_24_5",
    "FlatLoad_16_7",
    "FlatLoad_16_5",
    "FlatLoad_8_7",
    "FlatLoad_8_5"    
]

const DEFAULT_PROCESS_TYPES = [
    "Chemical", 
    "Warehouse",
    "FlatLoad", 
    "FlatLoad_24_5", 
    "FlatLoad_16_7", 
    "FlatLoad_16_5",
    "FlatLoad_8_7",
    "FlatLoad_8_5"
]

function find_ashrae_zone_city(lat, lon; get_zone=false)
    file_path = joinpath(@__DIR__, "..", "..", "data", "climate_cities.shp")
    shpfile = ArchGDAL.read(file_path)
	cities_layer = ArchGDAL.getlayer(shpfile, 0)

	# From https://yeesian.com/ArchGDAL.jl/latest/projections/#:~:text=transform%0A%20%20%20%20point%20%3D%20ArchGDAL.-,fromWKT,-(%22POINT%20(1120351.57%20741921.42
    # From https://en.wikipedia.org/wiki/Well-known_text_representation_of_geometry
	point = ArchGDAL.fromWKT(string("POINT (",lon," ",lat,")"))
	
	# No transformation needed
	archgdal_city = nothing
	for i in 1:ArchGDAL.nfeature(cities_layer)
		ArchGDAL.getfeature(cities_layer,i-1) do feature # 0 indexed
			if ArchGDAL.contains(ArchGDAL.getgeom(feature), point)
				archgdal_city = ArchGDAL.getfield(feature,"city")
			end
		end
	end
    if isnothing(archgdal_city)
        @warn "Could not find latitude/longitude in U.S. Using geometrically nearest city."
    elseif !get_zone && !(archgdal_city == "LosAngeles")
        return archgdal_city
    end
    cities = [
        (city="Miami", lat=25.761680, lon=-80.191790, zone="1A"),
        (city="Houston", lat=29.760427, lon=-95.369803, zone="2A"),
        (city="Phoenix", lat=33.448377, lon=-112.074037, zone="2B"),
        (city="Atlanta", lat=33.748995, lon=-84.387982, zone="3A"),
        (city="LasVegas", lat=36.1699, lon=-115.1398, zone="3B"),
        (city="LosAngeles", lat=34.052234, lon=-118.243685, zone="3B"),
        (city="SanFrancisco", lat=37.3382, lon=-121.8863, zone="3C"),
        (city="Baltimore", lat=39.290385, lon=-76.612189, zone="4A"),
        (city="Albuquerque", lat=35.085334, lon=-106.605553, zone="4B"),
        (city="Seattle", lat=47.606209, lon=-122.332071, zone="4C"),
        (city="Chicago", lat=41.878114, lon=-87.629798, zone="5A"),
        (city="Boulder", lat=40.014986, lon=-105.270546, zone="5B"),
        (city="Minneapolis", lat=44.977753, lon=-93.265011, zone="6A"),
        (city="Helena", lat=46.588371, lon=-112.024505, zone="6B"),
        (city="Duluth", lat=46.786672, lon=-92.100485, zone="7"),
        (city="Fairbanks", lat=59.0397, lon=-158.4575, zone="8"),
    ]
    min_distance = 0.0
    nearest_city = ""
    ashrae_zone = ""    
    for (i, c) in enumerate(cities)
        distance = sqrt((lat - c.lat)^2 + (lon - c.lon)^2)
        if i == 1
            min_distance = distance
            nearest_city = c.city
            ashrae_zone = c.zone
        elseif distance < min_distance
            min_distance = distance
            nearest_city = c.city
            ashrae_zone = c.zone
        end
    end
    
    # Optionally return both city and zone
    if get_zone
        if !isnothing(archgdal_city)
            nearest_city = archgdal_city
        end
        return nearest_city, ashrae_zone
    else
        return nearest_city
    end
end


"""
    built_in_load(
        type::String, 
        city::String, 
        buildingtype::String, 
        year::Int, 
        annual_energy::Real, 
        monthly_energies::AbstractArray{<:Real,1},
        boiler_efficiency_input::Union{Real,Nothing}=nothing,
        normalized_profile::Union{Vector{Float64}, Vector{<:Real}}=Real[];
        time_steps_per_hour::Int = 1 # only used with normalized_profile      
    )
Scale a normalized Commercial Reference Building according to inputs provided and return the 8760.
"""

function built_in_load(
    type::String, 
    city::String, 
    buildingtype::String, 
    year::Int, 
    annual_energy::Real, 
    monthly_energies::AbstractArray{<:Real,1},
    boiler_efficiency_input::Union{Real,Nothing}=nothing,
    normalized_profile::Union{Vector{Float64}, Vector{<:Real}}=Real[]; # provided as function input for customer loads, not CRBs
    time_steps_per_hour::Int = 1 # only used with user-provided normalized_profile. CRB loads are always hourly when this function is called.
    )

    @assert type in ["electric", "domestic_hot_water", "space_heating", "cooling", "process_heat"]
    monthly_scalers = ones(12)
    lib_path = joinpath(@__DIR__, "..", "..", "data", "load_profiles", type)

    profile_path = joinpath(lib_path, string("crb8760_norm_" * city * "_" * buildingtype * ".dat"))
    input_normalized = false
    shift_possible = false
    monthly_timesteps = get_monthly_time_steps(year; time_steps_per_hour=time_steps_per_hour)

    if isempty(normalized_profile) # Not user-provided
        if occursin("FlatLoad", buildingtype)
            normalized_profile = custom_normalized_flatload(buildingtype, year)
        else 
            normalized_profile = vec(readdlm(profile_path, '\n', Float64, '\n'))
            shift_possible = true
        end
    else
        input_normalized = true
    end

    # The normalized_profile for CRBs (not FlatLoads, which use the year input) is based on year 2017 which starts on a Sunday. 
    # If the year is not 2017 and we're using a CRB, we shift the 2017 CRB profile to match the weekday/weekend profile of the input year.
    # We remove the CRB start day Sunday, and shift the CRB profile to the left until reaching the start day of the input year (e.g. Friday for 2021), and 
    #  the shifted days (but not Sunday) get wrapped around to the end of the year, and the year's start day gets duplicated at the end of the year to match the year's ending day of the week.
    # We then re-normalize the profile because we've removed the previously-normalized year's first day Sunday and duplicated the year's start day profile
    if !(year == 2017) && shift_possible
        crb_start_day = Dates.dayofweek(DateTime(2017,1,1))
        load_start_day = Dates.dayofweek(DateTime(year,1,1))
        cut_days = 7 - (crb_start_day - load_start_day) # Ex: = 7-(7-5) = 5 --> cut Sun, Mon, Tues, Wed, Thurs for 2021 load year
        wrap_ts = normalized_profile[25*time_steps_per_hour: (24+24*cut_days)*time_steps_per_hour] # Ex: = crb_profile[25:144] wrap Mon-Fri to end for 2021
        normalized_profile = append!(normalized_profile[(24*cut_days+1)*time_steps_per_hour:end], wrap_ts) # Ex: now starts on Fri and end Fri to align with 2021 cal
        normalized_profile = normalized_profile ./ sum(normalized_profile)
    end

    if length(monthly_energies) == 12
        annual_energy = 1.0  # do not scale based on annual_energy
        for month in 1:12
            start_idx = monthly_timesteps[month][1]
            end_idx = monthly_timesteps[month][end]
            month_total = sum(normalized_profile[start_idx:end_idx])
            if month_total == 0.0  # avoid division by zero
                monthly_scalers[month] = 0.0
            else
                monthly_scalers[month] = monthly_energies[month] / month_total
            end
        end
    end

    scaled_load = Float64[]
    used_kwh_per_mmbtu = 1.0  # do not convert electric loads
    if type in ["domestic_hot_water", "space_heating", "process_heat"]
        # CRB thermal "loads" are in terms of energy input required (boiler fuel), not the actual energy demand.
        # So we multiply the fuel energy by the boiler_efficiency to get the actual energy demand.
        boiler_efficiency = isnothing(boiler_efficiency_input) ? EXISTING_BOILER_EFFICIENCY : boiler_efficiency_input
        used_kwh_per_mmbtu = KWH_PER_MMBTU  # do convert thermal loads
    else
        boiler_efficiency = 1.0
    end

    for (month, timesteps) in enumerate(monthly_timesteps)
        for t in timesteps
            push!(scaled_load, normalized_profile[t] * annual_energy * monthly_scalers[month] * time_steps_per_hour * boiler_efficiency * used_kwh_per_mmbtu)
        end
    end

    return scaled_load
end


"""
    blend_and_scale_doe_profiles(
        constructor,
        latitude::Real,
        longitude::Real,
        year::Int,
        blended_doe_reference_names::Array{String, 1},
        blended_doe_reference_percents::Array{<:Real,1},
        city::String = "",
        annual_energy::Union{Real, Nothing} = nothing,
        monthly_energies::Array{<:Real,1} = Real[],
        boiler_efficiency_input::Union{Real,Nothing}=nothing
    )

Given `blended_doe_reference_names` and `blended_doe_reference_percents` use the `constructor` function to load in DoE 
    CRB profiles and create a single profile, where `constructor` is one of:
    - BuiltInElectricLoad
    - BuiltInHeatingLoad
    - BuiltInCoolingLoad
"""

function blend_and_scale_doe_profiles(
    constructor,
    latitude::Real,
    longitude::Real,
    year::Int,
    blended_doe_reference_names::Array{String, 1},
    blended_doe_reference_percents::Array{<:Real,1},
    city::String = "",
    annual_energy::Union{Real, Nothing} = nothing,
    monthly_energies::Array{<:Real,1} = Real[],
    addressable_load_fraction::Union{<:Real, AbstractVector{<:Real}} = 1.0,
    boiler_efficiency_input::Union{Real,Nothing}=nothing,
    heating_load_type::String=""
    )

    @assert sum(blended_doe_reference_percents) ≈ 1 "The sum of the blended_doe_reference_percents must equal 1"
    
    if isempty(city)
        if heating_load_type === "process_heat"
            city = "Industrial"
        else
            city = find_ashrae_zone_city(latitude, longitude)
        end
    end

    profiles = Array[]  # collect the built in profiles
    if constructor == BuiltInHeatingLoad
        for name in blended_doe_reference_names
            push!(profiles, constructor(heating_load_type, city, name, latitude, longitude, year, addressable_load_fraction, annual_energy, monthly_energies, boiler_efficiency_input))
        end
    else
        for name in blended_doe_reference_names
            push!(profiles, constructor(city, name, latitude, longitude, year, annual_energy, monthly_energies))
        end
    end
    if isnothing(annual_energy) # then annual_energy should be the sum of all the profiles' annual kwhs
        # we have to rescale the built in profiles to the total_kwh by normalizing them with their
        # own annual kwh and multiplying by the total kwh
        annual_kwhs = [sum(profile) for profile in profiles]
        total_kwh = sum(annual_kwhs)
        monthly_scaler = 1
        if length(monthly_energies) == 12
            monthly_scaler = length(blended_doe_reference_names)
        end
        for idx in eachindex(profiles)
            if !(annual_kwhs[idx] == 0.0)
                profiles[idx] .*= total_kwh / annual_kwhs[idx] / monthly_scaler
            end
        end
    end
    for idx in eachindex(profiles)  # scale the profiles
        profiles[idx] .*= blended_doe_reference_percents[idx]
    end
    sum(profiles)
end


function custom_normalized_flatload(doe_reference_name, year)
    # built in profiles are assumed to be hourly
    periods = 8760
    # get datetimes of all hours 
    if Dates.isleapyear(year)
        end_year_datetime = DateTime(string(year)*"-12-30T23:00:00")
    else
        end_year_datetime = DateTime(string(year)*"-12-31T23:00:00")
    end
    dt_hourly = collect(DateTime(string(year)*"-01-01T00:00:00"):Hour(1):end_year_datetime)

    # create boolean masks for weekday and hour of day filters
    weekday_mask = convert(Vector{Int}, ones(periods))
    hour_mask = convert(Vector{Int}, ones(periods))
    weekends = [6,7]
    hour_range_16 = 6:21  # DateTime hours are 0-indexed, so this is 6am (7th hour of the day) to 10pm (end of 21st hour)
    hour_range_8 = 9:16  # This is 9am (10th hour of the day) to 5pm (end of 16th hour)
    if !(doe_reference_name == "FlatLoad")
        for (i,dt) in enumerate(dt_hourly)
            # Zero out no-weekend operation
            if doe_reference_name in ["FlatLoad_24_5","FlatLoad_16_5","FlatLoad_8_5"]
                if Dates.dayofweek(dt) in weekends
                    weekday_mask[i] = 0
                end
            end
            # Assign 1's for 16 or 8 hour shift profiles
            if doe_reference_name in ["FlatLoad_16_5","FlatLoad_16_7"]
                if !(Dates.hour(dt) in hour_range_16)
                    hour_mask[i] = 0
                end
            elseif doe_reference_name in ["FlatLoad_8_5","FlatLoad_8_7"]
                if !(Dates.hour(dt) in hour_range_8)
                    hour_mask[i] = 0
                end
            end
        end
    end
    # combine masks to a dt_hourly where 1 is on and 0 is off
    dt_hourly_binary = weekday_mask .* hour_mask
    # convert combined masks to a normalized profile
    sum_dt_hourly_binary = sum(dt_hourly_binary)
    normalized_profile = [i/sum_dt_hourly_binary for i in dt_hourly_binary]
    return normalized_profile
end

"""
    get_monthly_energy(power_profile::AbstractArray{<:Real,1};
                        year::Int64=2017)

Get monthly energy from an hourly load profile.
"""
function get_monthly_energy(power_profile::AbstractArray{<:Real,1}; 
                            year::Int64=2017)
    if length(power_profile) != 8760
        throw(@error("get_monthly_energy can only be used for hourly profiles"))
    end
    monthly_timesteps = get_monthly_time_steps(year)
    monthly_energy_total = zeros(12)
    for month in 1:12
        start_idx = monthly_timesteps[month][1]
        end_idx = monthly_timesteps[month][end]
        if !isempty(power_profile)
            monthly_energy_total[month] = sum(power_profile[start_idx:end_idx])
        else
            throw(@error("Must provide power_profile"))
        end
    end

    return monthly_energy_total
end

