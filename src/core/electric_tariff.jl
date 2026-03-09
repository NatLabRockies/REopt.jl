# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    struct ElectricTariff

- data for electric tariff in reopt model
- can be defined using custom rates or URDB rate
- very similar to the URDB struct but includes export rates and bins
"""
struct ElectricTariff
    energy_rates::AbstractArray{Float64, 2} # gets a second dim with tiers
    energy_tier_limits::AbstractArray{Float64,2} # month X tier
    n_energy_tiers::Int

    monthly_demand_rates::AbstractArray{Float64, 2} # gets a second dim with tiers
    time_steps_monthly::AbstractArray{AbstractArray{Int64,1},1}  # length = 0 or 12
    monthly_demand_tier_limits::AbstractArray{Float64,2} # month X tier
    n_monthly_demand_tiers::Int

    tou_demand_rates::AbstractArray{Float64, 2} # gets a second dim with tiers
    tou_demand_ratchet_time_steps::AbstractArray{AbstractArray{Int64,1},1}  # length = n_tou_demand_ratchets
    tou_demand_tier_limits::AbstractArray{Float64,2} # ratchet X tier
    n_tou_demand_tiers::Int

    demand_lookback_months::AbstractArray{Int,1}
    demand_lookback_percent::Float64
    demand_lookback_range::Int

    fixed_monthly_charge::Float64
    annual_min_charge::Float64
    min_monthly_charge::Float64

    export_rates::Dict{Symbol, AbstractArray}
    export_bins::AbstractArray{Symbol,1}

    coincident_peak_load_active_time_steps::AbstractVector{AbstractVector{Int64}}
    coincident_peak_load_charge_per_kw::AbstractVector{Float64}
    coincpeak_periods::AbstractVector{Int64}

    urdb_metadata::Dict{Symbol, Any}

end


"""
`ElectricTariff` is a required REopt input for on-grid scenarios only (it cannot be supplied when `Settings.off_grid_flag` is true) with the following keys and default values:
```julia
    urdb_label::String="",
    urdb_response::Dict=Dict(), # Response JSON for URDB rates. Note: if creating your own urdb_response, ensure periods are zero-indexed.
    urdb_utility_name::String="",
    urdb_rate_name::String="",
    urdb_metadata::Dict=Dict(), # Meta data about the URDB rate, from the URDB API response
    wholesale_rate::T1=nothing, # Price of electricity sold back to the grid in absence of net metering. Can be a scalar value, which applies for all-time, or an array with time-sensitive values. If an array is input then it must have a length of 8760, 17520, or 35040. The inputed array values are up/down-sampled using mean values to match the Settings.time_steps_per_hour.
    export_rate_beyond_net_metering_limit::T2=nothing, # Price of electricity sold back to the grid beyond total annual grid purchases, regardless of net metering. Can be a scalar value, which applies for all-time, or an array with time-sensitive values. If an array is input then it must have a length of 8760, 17520, or 35040. The inputed array values are up/down-sampled using mean values to match the Settings.time_steps_per_hour
    monthly_energy_rates::Array=[], # Array (length of 12) of blended energy rates in dollars per kWh
    monthly_demand_rates::Array=[], # Array (length of 12) of blended demand charges in dollars per kW
    blended_annual_energy_rate::S=nothing, # Annual blended energy rate [\$ per kWh] (total annual energy in kWh divided by annual cost in dollars)
    blended_annual_demand_rate::R=nothing, # Average monthly demand charge [\$ per kW per month]. Rate will be applied to monthly peak demand.
    add_monthly_rates_to_urdb_rate::Bool=false, # Set to 'true' to add the monthly blended energy rates and demand charges to the URDB rate schedule. Otherwise, blended rates will only be considered if a URDB rate is not provided.
    tou_energy_rates_per_kwh::Array=[], # Time-of-use energy rates, provided by user. Must be an array with length equal to number of timesteps per year.
    add_tou_energy_rates_to_urdb_rate::Bool=false, # Set to 'true' to add the tou  energy rates to the URDB rate schedule. Otherwise, tou energy rates will only be considered if a URDB rate is not provided.
    remove_tiers::Bool=false,
    demand_lookback_months::AbstractArray{Int64, 1}=Int64[], # Array of 12 binary values, indicating months in which `demand_lookback_percent` applies. If any of these is true, `demand_lookback_range` should be zero.
    demand_lookback_percent::Real=0.0, # Lookback percentage. Applies to either `demand_lookback_months` with value=1, or months in `demand_lookback_range`.
    demand_lookback_range::Int=0, # Number of months for which `demand_lookback_percent` applies. If not 0, `demand_lookback_months` should not be supplied.
    coincident_peak_load_active_time_steps::Vector{Vector{Int64}}=[Int64[]], # The optional coincident_peak_load_charge_per_kw will apply at the max grid-purchased power during these timesteps. Note timesteps are indexed to a base of 1 not 0.
    coincident_peak_load_charge_per_kw::AbstractVector{<:Real}=Real[] # Optional coincident peak demand charge that is applied to the max load during the timesteps specified in coincident_peak_load_active_time_steps.
    ) where {
        T1 <: Union{Nothing, Real, Array{<:Real}}, 
        T2 <: Union{Nothing, Real, Array{<:Real}}, 
        S <: Union{Nothing, Real}, 
        R <: Union{Nothing, Real}
    }
```
!!! note "Export Rates" 
    There are three Export tiers and their associated export rates (negative cost values):
    1. NEM (Net Energy Metering) - set to the energy rate (or tier with the lowest energy rate, if tiered) 
    2. WHL (Wholesale) - set to wholesale_rate
    3. EXC (Excess, beyond NEM) - set to export_rate_beyond_net_metering_limit

    Only one of NEM and Wholesale can be exported into due to the binary constraints.
    Excess can be exported into in the same time step as NEM.

    Excess is meant to be combined with NEM: NEM export is limited to the total grid purchased energy in a year and some
    utilities offer a compensation mechanism for export beyond the site load.
    The Excess tier is not available with the Wholesale tier.

!!! note "NEM input"
    The `NEM` boolean is determined by the `ElectricUtility.net_metering_limit_kw`. There is no need to pass in a `NEM`
    value.

!!! note "Demand Lookback Inputs" 
    Cannot use both `demand_lookback_months` and `demand_lookback_range` inputs, only one or the other.
    When using lookbacks, the peak demand in each month will be the greater of the peak kW in that month and the peak kW in the lookback months times the demand_lookback_percent. 
"""
function ElectricTariff(;
    urdb_label::String="",
    urdb_response::Dict=Dict(),
    urdb_utility_name::String="",
    urdb_rate_name::String="",
    urdb_metadata::Dict=Dict(),
    year::Union{Int, Nothing}=nothing,   # Passed from ElectricLoad
    time_steps_per_hour::Int=1,
    NEM::Bool=false,
    wholesale_rate::T1=nothing,
    export_rate_beyond_net_metering_limit::T2=nothing,
    monthly_energy_rates::Array=[],
    monthly_demand_rates::Array=[],
    blended_annual_energy_rate::S=nothing,
    blended_annual_demand_rate::R=nothing,
    add_monthly_rates_to_urdb_rate::Bool=false,
    tou_energy_rates_per_kwh::Array=[],
    add_tou_energy_rates_to_urdb_rate::Bool=false,
    remove_tiers::Bool=false,
    demand_lookback_months::AbstractArray{Int64, 1}=Int64[], # Array of 12 binary values, indicating months in which `demand_lookback_percent` applies. If any of these is true, demand_lookback_range should be zero.
    demand_lookback_percent::Real=0.0,
    demand_lookback_range::Int=0,
    coincident_peak_load_active_time_steps::Vector{Vector{Int64}}=[Int64[]],
    coincident_peak_load_charge_per_kw::AbstractVector{<:Real}=Real[]
    ) where {
        T1 <: Union{Nothing, Real, Array{<:Real}}, 
        T2 <: Union{Nothing, Real, Array{<:Real}}, 
        S <: Union{Nothing, Real}, 
        R <: Union{Nothing, Real}
    }
    # TODO remove_tiers for multinode models
    nem_rate = Float64[]

    energy_tier_limits = Array{Float64,2}(undef, 0, 0)
    n_energy_tiers = 1
    monthly_demand_tier_limits = Array{Float64,2}(undef, 0, 0)
    n_monthly_demand_tiers = 1
    tou_demand_tier_limits = Array{Float64,2}(undef, 0, 0)
    n_tou_demand_tiers = 1
    time_steps_monthly = get_monthly_time_steps(year, time_steps_per_hour=time_steps_per_hour)

    u = nothing
    if !isempty(urdb_response)

        u = URDBrate(urdb_response, year, time_steps_per_hour=time_steps_per_hour)

    elseif !isempty(urdb_label)

        u = URDBrate(urdb_label, year, time_steps_per_hour=time_steps_per_hour)

    elseif !isempty(urdb_utility_name) && !isempty(urdb_rate_name)

        u = URDBrate(urdb_utility_name, urdb_rate_name, year, time_steps_per_hour=time_steps_per_hour)

    elseif !isempty(tou_energy_rates_per_kwh) && length(tou_energy_rates_per_kwh) == 8760*time_steps_per_hour

        tou_demand_rates = Float64[]
        tou_demand_ratchet_time_steps = []
        energy_rates = tou_energy_rates_per_kwh
        monthly_demand_rates = convert(Array{Float64}, monthly_demand_rates)

        fixed_monthly_charge = 0.0
        annual_min_charge = 0.0
        min_monthly_charge = 0.0

        if NEM
            nem_rate = [-0.999 * x for x in energy_rates]
        end

    elseif !isempty(monthly_energy_rates)

        invalid_args = String[]
        if !(length(monthly_energy_rates) == 12)
            push!(invalid_args, "length(monthly_energy_rates) must equal 12, got length $(length(monthly_energy_rates))")
        end
        if !isempty(monthly_demand_rates) && !(length(monthly_demand_rates) == 12)
            push!(invalid_args, "length(monthly_demand_rates) must equal 12, got length $(length(monthly_demand_rates))")
        end
        if length(invalid_args) > 0
            throw(@error("Invalid ElectricTariff argument values: $(invalid_args)"))
        end

        if isempty(monthly_demand_rates)
            monthly_demand_rates = repeat([0.0], 12)
        end

        tou_demand_rates = Float64[]
        tou_demand_ratchet_time_steps = []
        energy_rates = Real[]
        for m in 1:12
            append!(energy_rates, [monthly_energy_rates[m] for ts in time_steps_monthly[m]])
        end

        fixed_monthly_charge = 0.0
        annual_min_charge = 0.0
        min_monthly_charge = 0.0

        if NEM
            nem_rate = [-0.999 * x for x in energy_rates]
        end

    elseif !isnothing(blended_annual_energy_rate)

        tou_demand_rates = Float64[]
        tou_demand_ratchet_time_steps = []
        energy_rates = repeat(Real[blended_annual_energy_rate], 8760 * time_steps_per_hour)
        if !isnothing(blended_annual_demand_rate)
            monthly_demand_rates = repeat(Real[blended_annual_demand_rate], 12)
        end
        if isempty(monthly_demand_rates)
            monthly_demand_rates = repeat([0.0], 12)
        end

        fixed_monthly_charge = 0.0
        annual_min_charge = 0.0
        min_monthly_charge = 0.0

        if NEM
            nem_rate = [-0.999 * x for x in energy_rates]
        end

    else
        throw(@error("Creating ElectricTariff requires at least urdb_label, urdb_response, monthly rates, annual rates, or tou_energy_rates_per_kwh."))
    end

    # Error checks and processing for user-defined demand_lookback_months
    if length(demand_lookback_months) != 0 && length(demand_lookback_months) != 12  # User provides value with incorrect length
        throw(@error("Length of demand_lookback_months array must be 12."))
    elseif demand_lookback_range != 0 && length(demand_lookback_months) != 0 # If user has provided demand_lookback_months of length 12, check that range is not used
        throw(@error("Cannot supply demand_lookback_months if demand_lookback_range != 0."))
    elseif demand_lookback_range == 0 && length(demand_lookback_months) == 12
        demand_lookback_months = collect(1:12)[demand_lookback_months .== 1]
    end

    if !isnothing(u)  # use URDBrate
        if NEM
            t = get_tier_with_lowest_energy_rate(u)
            nem_rate = [-0.999 * x for x in u.energy_rates[:,t]]
        end

        energy_rates = u.energy_rates
        energy_tier_limits = u.energy_tier_limits
        n_energy_tiers = u.n_energy_tiers
        users_monthly_demand_rates = copy(monthly_demand_rates)
        monthly_demand_rates = u.monthly_demand_rates
        monthly_demand_tier_limits = u.monthly_demand_tier_limits
        n_monthly_demand_tiers = u.n_monthly_demand_tiers
        tou_demand_rates = u.tou_demand_rates
        tou_demand_tier_limits = u.tou_demand_tier_limits
        n_tou_demand_tiers = u.n_tou_demand_tiers

        urdb_metadata = Dict{Symbol, Any}(
            :label => u.label,
            :rate_name => u.rate_name,
            :utility => u.utility,
            :rate_effective_date => u.rate_effective_date,
            :voltage_level => u.voltage_level,
            :rate_description => u.rate_description,
            :peak_kw_capacity_min => u.peak_kw_capacity_min,
            :peak_kw_capacity_max => u.peak_kw_capacity_max,
            :rate_additional_info => u.rate_additional_info,
            :energy_comments => u.energy_comments,
            :demand_comments => u.demand_comments,
            :url_link => u.url_link
        ) 

        if remove_tiers
            energy_rates, monthly_demand_rates, tou_demand_rates = remove_tiers_from_urdb_rate(u)
            energy_tier_limits, monthly_demand_tier_limits, tou_demand_tier_limits = 
                Array{Float64,2}(undef, 0, 0), Array{Float64,2}(undef, 0, 0), Array{Float64,2}(undef, 0, 0)
            n_energy_tiers, n_monthly_demand_tiers, n_tou_demand_tiers = 1, 1, 1
        end

        tou_demand_ratchet_time_steps = u.tou_demand_ratchet_time_steps
        demand_lookback_months = u.demand_lookback_months
        demand_lookback_percent = u.demand_lookback_percent
        demand_lookback_range = u.demand_lookback_range
        fixed_monthly_charge = u.fixed_monthly_charge
        annual_min_charge = u.annual_min_charge
        min_monthly_charge = u.min_monthly_charge

        if add_monthly_rates_to_urdb_rate 
            if length(monthly_energy_rates) == 12
                for tier in axes(energy_rates, 2), mth in 1:12, ts in time_steps_monthly[mth]
                    energy_rates[ts, tier] += monthly_energy_rates[mth]
                end
            end
            if length(users_monthly_demand_rates) == 12
                for tier in axes(monthly_demand_rates, 2), mth in 1:12
                    monthly_demand_rates[mth, tier] += users_monthly_demand_rates[mth]
                end
            end
        end

        if add_tou_energy_rates_to_urdb_rate && length(tou_energy_rates_per_kwh) == size(energy_rates, 1)
            for tier in axes(energy_rates, 2)
                energy_rates[:, tier] += tou_energy_rates_per_kwh
            end
        end
    else
        # need to reshape cost vectors to arrays (2nd dim is for tiers)
        energy_rates = reshape(energy_rates, :, 1)
        monthly_demand_rates = reshape(monthly_demand_rates, :, 1)
        tou_demand_rates = reshape(tou_demand_rates, :, 1)
    end

    #= export_rates
    There are three Export tiers and their associated export rates (negative values):
    1. NEM (Net Energy Metering)
    2. WHL (Wholesale)
    3. EXC (Excess, beyond NEM)

    Only one of NEM and Wholesale can be exported into due to the binary constraints.
    Excess can be exported into in the same time step as NEM.

    Excess is meant to be combined with NEM: NEM export is limited to the total grid purchased energy in a year and some
    utilities offer a compensation mechanism for export beyond the site load.
    The Excess tier is not available with the Wholesale tier.

    - if NEM then set ExportRate[:Nem, :] to energy_rate[tier_with_lowest_energy_rate, :]
    - user can provide either scalar wholesale rate or vector of time_steps, 
    =#
    whl_rate = create_export_rate(wholesale_rate, length(energy_rates[:,1]), time_steps_per_hour) 
    if !isnothing(u) && sum(u.sell_rates) < 0
        whl_rate += u.sell_rates
    end
    exc_rate = create_export_rate(export_rate_beyond_net_metering_limit, length(energy_rates[:,1]), time_steps_per_hour)
    
    if !NEM & (sum(whl_rate) >= 0) # no NEM or WHL 
        export_rates = Dict{Symbol, AbstractArray}()
        export_bins = Symbol[]
    elseif !NEM # no NEM, with WHL
        export_bins = [:WHL]
        export_rates = Dict(:WHL => whl_rate)
    elseif (sum(whl_rate) >= 0) # NEM, no WHL
        export_bins = [:NEM]
        export_rates = Dict(:NEM => nem_rate)
        if sum(exc_rate) < 0 # NEM with EXC rate
            push!(export_bins, :EXC)
            export_rates[:EXC] = exc_rate
        end
    else # NEM and WHL
        export_bins = [:NEM, :WHL]
        export_rates = Dict(:NEM => nem_rate, :WHL => whl_rate)
        if sum(exc_rate) < 0 # NEM and WHL with EXC rate
            push!(export_bins, :EXC)
            export_rates[:EXC] = exc_rate
        end
    end

    coincpeak_periods = Int64[]
    if !isempty(coincident_peak_load_charge_per_kw)
        coincpeak_periods = collect(eachindex(coincident_peak_load_charge_per_kw))
    end

    ElectricTariff(
        energy_rates,
        energy_tier_limits,
        n_energy_tiers,
        monthly_demand_rates,
        time_steps_monthly,
        monthly_demand_tier_limits,
        n_monthly_demand_tiers,
        tou_demand_rates,
        tou_demand_ratchet_time_steps,
        tou_demand_tier_limits,
        n_tou_demand_tiers,
        demand_lookback_months,
        demand_lookback_percent,
        demand_lookback_range,
        fixed_monthly_charge,
        annual_min_charge,
        min_monthly_charge,
        export_rates,
        export_bins,
        coincident_peak_load_active_time_steps,
        coincident_peak_load_charge_per_kw,
        coincpeak_periods,
        urdb_metadata
    )
end


function get_tier_with_lowest_energy_rate(u::URDBrate)
    """
    ExportRate should be lowest energy cost for tiered rates. 
    Otherwise, ExportRate can be > FuelRate, which leads REopt to export all PV energy produced.
    """
    #TODO: can eliminate if else if confirm that u.energy_rates is always 2D
    if length(u.energy_tier_limits) > 1
        return argmin(vec(sum(u.energy_rates, dims=1)))
    else
        return 1
    end
end


"""
    function create_export_rate(e::Nothing, N::Int, ts_per_hour::Int=1) 
No export rate provided by user: set to 0 dollars/kWh for all time
N = length(energy_rates[:,1]) and should already account for time_steps_per_hour
"""
function create_export_rate(e::Nothing, N::Int, ts_per_hour::Int=1)
    [0 for _ in range(1, stop=N)]
end


"""
    function create_export_rate(e::T, N::Int, ts_per_hour::Int=1) where T<:Real
Case for scaler export rate provided -> convert to array of time_steps
N = length(energy_rates[:,1]) and should already account for time_steps_per_hour
"""
function create_export_rate(e::T, N::Int, ts_per_hour::Int=1) where T<:Real
    repeat([float(-1*e)], N)
end


"""
    function create_export_rate(e::AbstractArray{<:Real, 1}, N::Int, ts_per_hour::Int=1)

Check length of e and upsample if length(e) != N
"""
function create_export_rate(e::AbstractArray{<:Real, 1}, N::Int, ts_per_hour::Int=1)
    Ne = length(e)
    if Ne != Int(N/ts_per_hour) && Ne != N
        throw(@error("Export rates do not have correct number of entries. Must be $(N) or $(Int(N/ts_per_hour))."))
    end
    if Ne != N  # upsample
        export_rates = [-1*x for x in e for ts in 1:ts_per_hour]
    else
        export_rates = -1*e
    end
    return export_rates
end


# TODO use this function only for URDBrate
function remove_tiers_from_urdb_rate(u::URDBrate)
    # tariff args: have to validate that there are no tiers
    if length(u.energy_tier_limits) > 1
        @warn "Energy rate contains tiers. Using the first tier!"
    end
    elec_rates = u.energy_rates[:,1]

    if u.n_monthly_demand_tiers > 1
        @warn "Monthly demand rate contains tiers. Using the last tier!"
    end
    if u.n_monthly_demand_tiers > 0
        demand_rates_monthly = u.monthly_demand_rates[:,u.n_monthly_demand_tiers]
    else
        demand_rates_monthly = u.monthly_demand_rates  # 0×0 Array{Float64,2}
    end

    if u.n_tou_demand_tiers > 1
        @warn "TOU demand rate contains tiers. Using the last tier!"
    end
    if u.n_tou_demand_tiers > 0
        demand_rates = u.tou_demand_rates[:,u.n_tou_demand_tiers]
    else
        demand_rates = u.tou_demand_rates
    end

    return elec_rates, demand_rates_monthly, demand_rates
end
