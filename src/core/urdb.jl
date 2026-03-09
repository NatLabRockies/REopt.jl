# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
# https://discourse.julialang.org/t/vector-of-matrices-vs-multidimensional-arrays/9602/5
# 5d2360465457a3f77ddc131e has TOU demand
# 59bc22705457a3372642da67 has monthly tiered demand (no TOU demand)

const urdb_api_key = get(ENV, "URDB_API_KEY", "2qt5uihpKXdywTj3uMIhBewxY9K4eNjpRje1JUPL")

"""
    Base.@kwdef struct URDBrate

Contains some of the data for ElectricTariff
"""
struct URDBrate
    energy_rates::Array{Float64,2}  # time X tier
    energy_tier_limits::Array{Float64,2} # month X tier
    n_energy_tiers::Int

    n_monthly_demand_tiers::Int
    monthly_demand_tier_limits::Array{Float64,2} # month X tier
    monthly_demand_rates::Array{Float64,2}  # month X tier

    n_tou_demand_tiers::Int
    tou_demand_tier_limits::Array{Float64,2} # ratchet X tier
    tou_demand_rates::Array{Float64,2}  # ratchet X tier
    tou_demand_ratchet_time_steps::Array{Array{Int64,1},1}  # length = n_tou_demand_ratchets

    demand_lookback_months::AbstractArray{Int,1}  # Array of 12 binary values, indicating months in which lookbackPercent applies. If any of these is true, lookbackRange should be zero.
    demand_lookback_percent::Float64  # Lookback percentage. Applies to either lookbackMonths with value=1, or a lookbackRange.
    demand_lookback_range::Int  # Number of months for which lookbackPercent applies. If not 0, lookbackMonths values should all be 0.

    fixed_monthly_charge::Float64
    annual_min_charge::Float64
    min_monthly_charge::Float64

    sell_rates::Array{Float64,2}  # time X tier

    # add new fields here
    label::String
    rate_name::String
    utility::String
    rate_effective_date::String
    voltage_level::String
    rate_description::String
    peak_kw_capacity_min::Float64
    peak_kw_capacity_max::Float64
    rate_additional_info::String
    energy_comments::String
    demand_comments::String
    url_link::String   # why type would a url be?

end


"""
    URDBrate(urdb_label::String, year::Int; time_steps_per_hour=1)

download URDB dict, parse into reopt inputs, return URDBrate struct.
    year is required to align weekday/weekend schedules.
"""
function URDBrate(urdb_label::String, year::Int; time_steps_per_hour=1)
    urdb_response = download_urdb(urdb_label)
    URDBrate(urdb_response, year; time_steps_per_hour=time_steps_per_hour)
end


"""
    URDBrate(util_name::String, rate_name::String, year::Int; time_steps_per_hour=1)

download URDB dict, parse into reopt inputs, return URDBrate struct.
    year is required to align weekday/weekend schedules.
"""
function URDBrate(util_name::String, rate_name::String, year::Int; time_steps_per_hour=1)
    urdb_response = download_urdb(util_name, rate_name)
    URDBrate(urdb_response, year; time_steps_per_hour=time_steps_per_hour)
end


"""
    URDBrate(urdb_response::Dict, year::Int)

process URDB response dict, parse into reopt inputs, return URDBrate struct.
    year is required to align weekday/weekend schedules.
"""
function URDBrate(urdb_response::Dict, year::Int; time_steps_per_hour=1)

    label = get(urdb_response, "label", "")
    rate_name = get(urdb_response, "name", "")
    utility = get(urdb_response, "utility", "")
    latest_update_unix = get(urdb_response, "startdate", 0.0)
    voltage_level = get(urdb_response, "voltagecategory", "")
    rate_description = get(urdb_response, "description", "")
    peak_kw_capacity_min = get(urdb_response, "peakkwcapacitymin", 0.0)  
    peak_kw_capacity_max = get(urdb_response, "peakkwcapacitymax", 0.0)  
    rate_additional_info = get(urdb_response, "basicinformationcomments", "")
    energy_comments = get(urdb_response, "energycomments", "")
    demand_comments = get(urdb_response, "demandcomments", "")
    url_link = get(urdb_response, "uri", "")

    # Convert Unix timestamp to date string
    rate_effective_date = ""
    if latest_update_unix > 0
        rate_effective_date = string(Date(Dates.unix2datetime(latest_update_unix)))
    end

    # Convert matrix to array if needed
    possible_matrix = ["demandratestructure", "flatdemandstructure", "demandweekdayschedule", 
        "demandweekendschedule", "energyratestructure", "energyweekdayschedule", "energyweekendschedule"]
    for param in possible_matrix
        if typeof(get(urdb_response, param, nothing)) <: AbstractMatrix
            urdb_response[param] = convert_matrix_to_array(urdb_response[param])
        end
    end

    n_monthly_demand_tiers, monthly_demand_tier_limits, monthly_demand_rates,
      n_tou_demand_tiers, tou_demand_tier_limits, tou_demand_rates, tou_demand_ratchet_time_steps =
      parse_demand_rates(urdb_response, year, time_steps_per_hour=time_steps_per_hour)
    
    energy_rates, energy_tier_limits, n_energy_tiers, sell_rates = 
        parse_urdb_energy_costs(urdb_response, year; time_steps_per_hour=time_steps_per_hour)

    fixed_monthly_charge, annual_min_charge, min_monthly_charge = parse_urdb_fixed_charges(urdb_response)

    demand_lookback_months, demand_lookback_percent, demand_lookback_range = parse_urdb_lookback_charges(urdb_response)

    URDBrate(
        energy_rates,
        energy_tier_limits,
        n_energy_tiers,

        n_monthly_demand_tiers,
        monthly_demand_tier_limits,
        monthly_demand_rates,

        n_tou_demand_tiers,
        tou_demand_tier_limits,
        tou_demand_rates,
        tou_demand_ratchet_time_steps,

        demand_lookback_months,
        demand_lookback_percent,
        demand_lookback_range,

        fixed_monthly_charge,
        annual_min_charge,
        min_monthly_charge,

        sell_rates,

        label,
        rate_name,
        utility,
        rate_effective_date,
        voltage_level,
        rate_description,
        peak_kw_capacity_min,
        peak_kw_capacity_max,
        rate_additional_info,
        energy_comments,
        demand_comments,
        url_link
    )
end

#TODO: refactor two download_urdb to reduce duplicated code
function download_urdb(urdb_label::String; version::Int=8)
    url = string("https://api.openei.org/utility_rates", "?api_key=", urdb_api_key,
                "&version=", version , "&format=json", "&detail=full",
                "&getpage=", urdb_label
    )
    response = nothing
    try
        @info "Checking URDB for " urdb_label
        r = HTTP.get(url, require_ssl_verification=false)  # cannot verify on NLR VPN
        response = JSON.parse(String(r.body))
        if r.status != 200
            throw(@error("Bad response from URDB: $(response["errors"])"))  # TODO URDB has "errors"?
        end
    catch e
        throw(@error("Error occurred :$(e)"))
    end

    rates = response["items"]  # response['items'] contains a vector of dicts
    if length(rates) == 0
        throw(@error("Could not find $(urdb_label) in URDB."))
    end
    if rates[1]["label"] == urdb_label
        return rates[1]
    else
        throw(@error("Could not find $(urdb_label) in URDB."))
    end
end


function download_urdb(util_name::String, rate_name::String; version::Int=8)
    url = string("https://api.openei.org/utility_rates", "?api_key=", urdb_api_key,
                "&version=", version , "&format=json", "&detail=full",
                "&ratesforutility=", replace(util_name, "&" => "%26")
    )
    response = nothing
    try
        @info "Checking URDB for " rate_name
        r = HTTP.get(url, require_ssl_verification=false)  # cannot verify on NLR VPN
        response = JSON.parse(String(r.body))
        if r.status != 200
            throw(@error("Bad response from URDB: $(response["errors"])"))  # TODO URDB has "errors"?
        end
    catch e
        throw(@error("Error occurred :$(e)"))
    end

    rates = response["items"]  # response['items'] contains a vector of dicts
    if length(rates) == 0
        throw(@error("Could not find $(rate_name) in URDB."))
    end

    matched_rates = []
    start_dates = []

    for rate in rates
        if contains(rate_name, rate["name"])
            push!(matched_rates, rate)  # urdb can contain multiple rates of same name
            if "startdate" in keys(rate)
                push!(start_dates, rate["startdate"])
            end
        end
    end

    # find the newest rate of those that match the rate_name
    newest_index = 1  # covers the case where one rate is returned without a "startdate"
    if length(start_dates) > 1 && length(start_dates) == length(matched_rates)
        _, newest_index = findmax(start_dates)
    end
    
    if length(matched_rates) == 0
        throw(@error("Could not find $(rate_name) in URDB."))
    end

    return matched_rates[newest_index]
end


"""
    parse_urdb_energy_costs(d::Dict, year::Int; time_steps_per_hour=1, bigM = 1.0e10)

use URDB dict to return rates, energy_cost_vector, energy_tier_limits_kwh where:
    - rates is vector summary of rates within URDB (used for average rates when necessary)
    - energy_cost_vector is a vector of vectors with inner vectors for each energy rate tier,
        inner vectors are costs in each time step
    - energy_tier_limits_kwh is a matrix of upper kWh limits for each energy tier, for each month
"""
function parse_urdb_energy_costs(d::Dict, year::Int; time_steps_per_hour=1, bigM = 1.0e10)
    if length(d["energyratestructure"]) == 0
        throw(@error("No energyratestructure in URDB response."))
    end
    n_energy_tiers = scrub_urdb_tiers!(d["energyratestructure"])
    energy_cost_vector = Float64[]
    sell_vector = Float64[]
    energy_tier_limits_kwh = Array{Float64}(undef, 12, n_energy_tiers)

    for tier in range(1, stop=n_energy_tiers)

        for month in range(1, stop=12)
            # NOTE: periods are zero indexed in URDB
            period = Int(d["energyweekdayschedule"][month][1] + 1)
            for tier in range(1, stop=n_energy_tiers)
                # tiered energy schedules are assumed to be consistent for each month (i.e., the first hour can represent all 24 hours of the schedule).
                tier_limit = get(d["energyratestructure"][period][tier], "max", bigM)
                energy_tier_limits_kwh[month, tier] = round(tier_limit, digits=3)
            end

            n_days = daysinmonth(Date(string(year) * "-" * string(month)))
            if month == 12 && isleapyear(year)
                n_days -= 1
            end

            for day in range(1, stop=n_days)
                for hour in range(1, stop=24)
                    # NOTE: periods are zero indexed in URDB
                    if dayofweek(Date(year, month, day)) < 6  # Monday == 1
                        period = Int(d["energyweekdayschedule"][month][hour] + 1)
                    else
                        period = Int(d["energyweekendschedule"][month][hour] + 1)
                    end
                    # workaround for cases where there are different numbers of tiers in periods
                    n_tiers_in_period = length(d["energyratestructure"][period])
                    if n_tiers_in_period == 1
                        tier_use = 1
                    elseif tier > n_tiers_in_period
                        tier_use = n_tiers_in_period
                    else
                        tier_use = tier
                    end
                    if "unit" in keys(d["energyratestructure"][period][tier_use]) && string(d["energyratestructure"][period][tier_use]["unit"]) != "kWh"
                        throw(@error("URDB energy tiers have non-standard units of " * d["energyratestructure"][period][tier_use]["unit"]))
                    end
                    total_rate = (get(d["energyratestructure"][period][tier_use], "rate", 0) + 
                                get(d["energyratestructure"][period][tier_use], "adj", 0)) 
                    sell = get(d["energyratestructure"][period][tier_use], "sell", 0)

                    for step in range(1, stop=time_steps_per_hour)  # repeat hourly rates intrahour
                        append!(energy_cost_vector, round(total_rate, digits=6))
                        append!(sell_vector, round(-sell, digits=6))
                    end
                end
            end
        end
    end
    energy_rates = reshape(energy_cost_vector, (:, n_energy_tiers))
    sell_rates = reshape(sell_vector, (:, n_energy_tiers))
    return energy_rates, energy_tier_limits_kwh, n_energy_tiers, sell_rates
end

"""
    convert_matrix_to_array(M::AbstractMatrix)

Convert an unexpected type::Matrix from URDB into an Array
    - Observed while using REopt.jl with PyJulia/PyCall
"""
function convert_matrix_to_array(M::AbstractMatrix)
    return [M[r,:] for r in axes(M, 1)]
end

"""
    parse_demand_rates(d::Dict, year::Int; bigM=1.0e8, time_steps_per_hour::Int)

Parse monthly ("flat") and TOU demand rates
"""
function parse_demand_rates(d::Dict, year::Int; bigM=1.0e8, time_steps_per_hour::Int)
    if haskey(d, "flatdemandstructure")
        n_monthly_demand_tiers = scrub_urdb_tiers!(d["flatdemandstructure"])
        monthly_demand_rates, monthly_demand_tier_limits = parse_urdb_monthly_demand(d, n_monthly_demand_tiers; bigM)
    else
        monthly_demand_tier_limits = Array{Float64,2}(undef, 0, 0)
        n_monthly_demand_tiers = 1
        monthly_demand_rates = Array{Float64,2}(undef, 0, 0)
    end

    if haskey(d, "demandratestructure")
        n_tou_demand_tiers = scrub_urdb_tiers!(d["demandratestructure"])
        ratchet_time_steps, tou_demand_rates, tou_demand_tier_limits = parse_urdb_tou_demand(d, year=year, n_tiers=n_tou_demand_tiers, time_steps_per_hour=time_steps_per_hour)
    else
        tou_demand_tier_limits = Array{Float64,2}(undef, 0, 0)
        n_tou_demand_tiers = 0
        ratchet_time_steps = []
        tou_demand_rates = Array{Float64,2}(undef, 0, 0)
    end

    return n_monthly_demand_tiers, monthly_demand_tier_limits, monthly_demand_rates,
           n_tou_demand_tiers, tou_demand_tier_limits, tou_demand_rates, ratchet_time_steps

end


"""
scrub_urdb_tiers!(A::Array)

validate energyratestructure, flatdemandstructure and demandratestructure have equal number of tiers across periods
"""
function scrub_urdb_tiers!(A::Array)
    if length(A) == 0
        return
    end
    len_tiers = Int[length(r) for r in A]
    len_tiers_set = Set(len_tiers)
    n_tiers = maximum(len_tiers_set)

    if length(len_tiers_set) > 1
        @warn "Rate structure has varying number of tiers in periods. Making the number of tiers the same across all periods by repeating the last tier in each period."
        for (i, rate) in enumerate(A)
            n_tiers_in_period = length(rate)
            if n_tiers_in_period != n_tiers
                rate_new = rate
                last_tier = rate[n_tiers_in_period]
                for j in range(1, stop=n_tiers - n_tiers_in_period)
                    append!(rate_new, [last_tier])
                end
                A[i] = rate_new
            end
        end
    end
    return n_tiers
end


"""
    parse_urdb_monthly_demand(d::Dict, n_tiers; bigM=1.0e8)

return monthly demand rates as array{month, tier}
"""
function parse_urdb_monthly_demand(d::Dict, n_tiers; bigM=1.0e8)
    if !haskey(d, "flatdemandmonths")
        return []
    end
    if length(d["flatdemandmonths"]) == 0
        return []
    end

    demand_rates = zeros(12, n_tiers)  # array(month, tier)
    demand_tier_limits = zeros(12, n_tiers)
    for month in range(1, stop=12)
        period = d["flatdemandmonths"][month] + 1  # URDB uses zero-indexing
        rates = d["flatdemandstructure"][period]  # vector of dicts

        for (t, tier) in enumerate(rates)
            demand_rates[month, t] = round(get(tier, "rate", 0.0) + get(tier, "adj", 0.0), digits=6)
            demand_tier_limits[month, t] = round(get(tier, "max", bigM), digits=6)
        end
    end
    return demand_rates, demand_tier_limits
end


"""
    parse_urdb_tou_demand(d::Dict; year::Int, n_tiers::Int)

return array of arrary for ratchet time steps, tou demand rates array{ratchet, tier}
"""
function parse_urdb_tou_demand(d::Dict; year::Int, n_tiers::Int, time_steps_per_hour::Int, bigM=1.0e8)
    if !haskey(d, "demandratestructure")
        return [], []
    end
    n_periods = length(d["demandratestructure"])
    ratchet_time_steps = Array[]
    rates_vec = Float64[]  # array(ratchet_num, tier), reshape later
    limits_vec = Float64[] # array(ratchet_num, tier), reshape later
    n_ratchets = 0  # counter

    for month in range(1, stop=12)
        for period in range(1, stop=n_periods)
            time_steps = get_tou_demand_steps(d, year=year, month=month, period=period-1, time_steps_per_hour=time_steps_per_hour)
            if length(time_steps) > 0  # can be zero! not every month contains same number of periods
                n_ratchets += 1
                append!(ratchet_time_steps, [time_steps])
                for (t, tier) in enumerate(d["demandratestructure"][period])
                    append!(rates_vec, round(get(tier, "rate", 0.0) + get(tier, "adj", 0.0), digits=6))
                    append!(limits_vec, round(get(tier, "max", bigM), digits=3))
                end
            end
        end
    end
    rates = reshape(rates_vec, (n_tiers, :))'  # Array{Float64,2}
    limits = reshape(limits_vec, (n_tiers, :))'  # Array{Float64,2}
    ratchet_time_steps = convert(Array{Array{Int64,1},1}, ratchet_time_steps)
    return ratchet_time_steps, rates, limits
end


"""
    get_tou_demand_steps(d::Dict; year::Int, month::Int, period::Int, time_steps_per_hour=1)

return Array{Int, 1} for time_steps in ratchet (aka period)
"""
function get_tou_demand_steps(d::Dict; year::Int, month::Int, period::Int, time_steps_per_hour=1)
    if month > 1
        plus_days = 0
        if month == 12 && isleapyear(year)
            plus_days -= 1
        end
        for m in range(1, stop=month-1)
            plus_days += daysinmonth(Date(string(year) * "-" * string(m)))
        end
        start_hour = 1 + plus_days * 24
        start_step = 1 + plus_days * 24 * time_steps_per_hour
    else
        start_hour = 1
        start_step = 1
    end

    step_of_year = start_step
    step_array = Int[]

    for day in range(1, stop=daysinmonth(Date(string(year) * "-" * string(month))))
        for hour in range(1, stop=24)
            if (dayofweek(Date(year, month, day)) < 6 && 
                d["demandweekdayschedule"][month][hour] == period) ||
                (dayofweek(Date(year, month, day)) > 5 &&
                d["demandweekendschedule"][month][hour] == period)
                
                append!(step_array, collect(step_of_year:step_of_year+time_steps_per_hour-1))
            end
            step_of_year += time_steps_per_hour
        end
    end
    return step_array
end


"""
    parse_urdb_fixed_charges(d::Dict)

return fixed_monthly, annual_min, min_monthly :: Float64
"""
function parse_urdb_fixed_charges(d::Dict)
    fixed_monthly = 0.0
    annual_min = 0.0
    min_monthly = 0.0

    # first try $/month, then check if $/day exists, as of 1/28/2020 there were only $/day and $month entries in the URDB
    fixed_monthly = Float64(get(d, "fixedmonthlycharge", 0.0))
    if fixed_monthly == 0.0
        if get(d, "fixedchargeunits", "") == "\$/month" 
            fixed_monthly = Float64(get(d, "fixedchargefirstmeter", 0.0))
        elseif get(d, "fixedchargeunits", "") == "\$/day"
            fixed_monthly = Float64(get(d, "fixedchargefirstmeter", 0.0) * 30.4375)
            # scalar intended to approximate annual charges over 12 month period, derived from 365.25/12
        elseif get(d, "fixedchargeunits", "") == "\$/year"
            fixed_monthly = Float64(get(d, "fixedchargefirstmeter", 0.0) / 12)
        elseif !isnothing(get(d, "fixedchargefirstmeter",  nothing))
            @warn "A valid value for fixedchargeunits (\$/month, \$/day, or \$/year) was not provided in urdb_response so the value provided for fixedchargefirstmeter will be ignored."
        end
    end

    if get(d, "minchargeunits", "") == "\$/month"
        min_monthly = Float64(get(d, "mincharge", 0.0))
        # first try $/month, then check if $/day or $/year exists, as of 1/28/2020 these were the only unit types in the urdb
    elseif get(d, "minchargeunits", "") == "\$/day"
        min_monthly = Float64(get(d, "mincharge", 0.0) * 30.4375 )
        # scalar intended to approximate annual charges over 12 month period, derived from 365.25/12
    elseif get(d, "minchargeunits", "") == "\$/year"
        annual_min = Float64(get(d, "mincharge", 0.0))
    elseif !isnothing(get(d, "minchargeunits",  nothing))
        @warn "A valid value for minchargeunits (\$/month, \$/day, or \$/year) was not provided in urdb_response so the value provided for mincharge will be ignored."
    end
    
    return fixed_monthly, annual_min, min_monthly
end


"""
    parse_urdb_lookback_charges(d::Dict)

URDB lookback fields:
- lookbackMonths
    - Type: array
    - Array of 12 booleans, true or false, indicating months in which lookbackPercent applies.
        If any of these is true, lookbackRange should be zero.
- lookbackPercent
    - Type: decimal
    - Lookback percentage. Applies to either lookbackMonths with value=1, or a lookbackRange.
- lookbackRange
    - Type: integer
    - Number of previous months for which lookbackPercent applies each month. If not 0, lookbackMonths values should all be 0.
"""
function parse_urdb_lookback_charges(d::Dict)
    lookback_months = get(d, "lookbackmonths", Int[])
    lookback_percent = Float64(get(d, "lookbackpercent", 0.0))
    lookback_range = Int64(get(d, "lookbackrange", 0.0))

    if lookback_range == 0 && length(lookback_months) == 12
        lookback_months = collect(1:12)[lookback_months .== 1]
    elseif lookback_range !=0 && length(lookback_months) == 12
        throw(@warn("URDB rate contains both lookbackRange and lookbackMonths. Only lookbackRange will apply."))
    end

    return lookback_months, lookback_percent, lookback_range
end