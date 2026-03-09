# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    MPCElectricLoad

    Base.@kwdef struct MPCElectricLoad
        loads_kw::Array{Real,1}
        critical_loads_kw::Union{Nothing, Array{Real,1}} = nothing
    end
"""
Base.@kwdef struct MPCElectricLoad
    loads_kw::Array{Real,1}
    critical_loads_kw::Union{Nothing, Array{Real,1}} = nothing
end


"""
    MPCFinancial

    Base.@kwdef struct MPCFinancial
        value_of_lost_load_per_kwh::Union{Array{R,1}, R} where R<:Real = 1.00
    end
"""
Base.@kwdef struct MPCFinancial
    value_of_lost_load_per_kwh::Union{Array{R,1}, R} where R<:Real = 1.00
end


"""
    MPCPV
```julia
Base.@kwdef struct MPCPV
    name::String="PV"
    size_kw::Real = 0
    production_factor_series::Union{Nothing, Array{Real,1}} = nothing
end
```
"""
Base.@kwdef struct MPCPV
    name::String="PV"
    size_kw::Real = 0
    production_factor_series::Union{Nothing, Array{Real,1}} = nothing
end


struct MPCElectricTariff
    energy_rates::AbstractVector{Float64}
    n_energy_tiers::Int

    monthly_demand_rates::AbstractVector{Float64}
    time_steps_monthly::Array{Array{Int64,1},1}  # length = 0 or 12
    monthly_previous_peak_demands::AbstractVector{Float64}
    n_monthly_demand_tiers::Int

    tou_demand_rates::AbstractVector{Float64}
    tou_demand_ratchet_time_steps::Array{Array{Int64,1},1}  # length = n_tou_demand_ratchets
    tou_previous_peak_demands::AbstractVector{Float64}
    n_tou_demand_tiers::Int

    fixed_monthly_charge::Float64
    annual_min_charge::Float64
    min_monthly_charge::Float64

    export_rates::DenseAxisArray{Array{Float64,1}}
    export_bins::Array{Symbol,1}

    # coincident_peak not used in MPC but must implement it for model building
    coincident_peak_load_active_time_steps::AbstractVector{AbstractVector{Int64}}
    coincident_peak_load_charge_per_kw::AbstractVector{Float64}
    coincpeak_periods::AbstractVector{Int64}
end


"""
    MPCElectricTariff(d::Dict)

function for parsing user inputs into 
```julia
    struct MPCElectricTariff
        monthly_previous_peak_demands::Array{Float64,1}
        energy_rates::Array{Float64,1} 

        monthly_demand_rates::Array{Float64,1}
        time_steps_monthly::Array{Array{Int64,1},1}  # length = 0 or 12

        tou_demand_rates::Array{Float64,1}
        tou_demand_ratchet_time_steps::Array{Array{Int64,1},1}  # length = n_tou_demand_ratchets
        tou_previous_peak_demands::Array{Float64,1}

        fixed_monthly_charge::Float64
        annual_min_charge::Float64
        min_monthly_charge::Float64

        export_rates::DenseAxisArray{Array{Float64,1}}
        export_bins::Array{Symbol,1}
    end
```

Keys for `d` include:

  - `energy_rates`

    - REQUIRED
    - must have length equal to `ElectricLoad.loads_kw`

  - `monthly_demand_rates`

    - default = [0]

  - `time_steps_monthly`

    - array of arrays for integer time steps that the `monthly_demand_rates` apply to
    - default = [collect(1:length(energy_rates))]

  - `monthly_previous_peak_demands`

    - default = [0]

  - `tou_demand_rates`

    - an array of time-of-use demand rates
    - must have length equal to `tou_demand_time_steps`
    - default = []

  - `tou_demand_time_steps`

    - an array of arrays for the integer time steps that apply to the `tou_demand_rates`
    - default = []

  - `tou_previous_peak_demands`

    - an array of the previous peak demands set in each time-of-use demand period
    - must have length equal to `tou_demand_time_steps`
    - default = []

  - `net_metering`

    - boolean, if `true` then customer DER export is compensated at the `energy_rates`

  - `export_rates`

    - can be a <:Real or Array{<:Real, 1}, or not provided
    - if provided, customer DER export is compensated at the `export_rates`

NOTE: if both `net_metering=true` and `export_rates` are provided then the model can choose from either option.
"""
function MPCElectricTariff(d::Dict)

    energy_rates = d["energy_rates"]

    monthly_demand_rates = get(d, "monthly_demand_rates", [0.0])
    time_steps_monthly = get(d, "time_steps_monthly", [collect(eachindex(energy_rates))])
    monthly_previous_peak_demands = get(d, "monthly_previous_peak_demands", [0.0])

    tou_demand_rates = get(d, "tou_demand_rates", Float64[])
    tou_demand_time_steps = get(d, "tou_demand_time_steps", [])
    tou_previous_peak_demands = get(d, "tou_previous_peak_demands", Float64[])
    @assert length(tou_demand_rates) == length(tou_demand_time_steps) == length(tou_previous_peak_demands)

    # TODO can remove these inputs?
    fixed_monthly_charge = 0.0
    annual_min_charge = 0.0
    min_monthly_charge = 0.0

    # TODO handle tiered rates
    export_bins = [:NEM, :WHL]
    nem_rate = []
    NEM = get(d, "net_metering", false)
    if NEM
        nem_rate = [-0.999 * x for x in energy_rates]
    end
    # export_rates can be a <:Real or Array{<:Real, 1}, or not provided
    export_rates = get(d, "export_rates", nothing)
    if !isnothing(export_rates)
        export_rates = convert(Vector{Real}, export_rates)
    end
    whl_rate = create_export_rate(export_rates, length(energy_rates[:,1]), 1)

    if !NEM & (sum(whl_rate) >= 0)
        export_rates = DenseAxisArray{Array{Float64,1}}(undef, [])
        export_bins = Symbol[]
    elseif !NEM
        export_bins = [:WHL]
        export_rates = DenseAxisArray([whl_rate], export_bins)
    elseif (sum(whl_rate) >= 0)
        export_bins = [:NEM]
        export_rates = DenseAxisArray([nem_rate], export_bins)
    else
        export_bins = [:NEM, :WHL]  # NOTE: not modeling EXC bin b/c MPC does not track annaul energy exported
        export_rates = DenseAxisArray([nem_rate, whl_rate], export_bins)
    end
    
    MPCElectricTariff(
        energy_rates,
        1,
        monthly_demand_rates,
        time_steps_monthly,
        monthly_previous_peak_demands,
        1,
        tou_demand_rates,
        tou_demand_time_steps,
        tou_previous_peak_demands,
        1,
        fixed_monthly_charge,
        annual_min_charge,
        min_monthly_charge,
        export_rates,
        export_bins,

        # empty values for coincident_peak
        [Int64[]],
        Float64[],
        Int64[],
    )
end


"""
    MPCElectricStorage

```julia
Base.@kwdef struct MPCElectricStorage < AbstractElectricStorage
    size_kw::Float64
    size_kwh::Float64
    charge_efficiency::Float64 =  0.96 * 0.975^2
    discharge_efficiency::Float64 =  0.96 * 0.975^2
    soc_min_fraction::Float64 = 0.2
    soc_init_fraction::Float64 = 0.5
    can_grid_charge::Bool = true
    grid_charge_efficiency::Float64 = 0.96 * 0.975^2
end
```
"""
Base.@kwdef struct MPCElectricStorage <: AbstractElectricStorage
    size_kw::Float64
    size_kwh::Float64
    charge_efficiency::Float64 = 0.96 * 0.975^2
    discharge_efficiency::Float64 = 0.96 * 0.975^2
    soc_min_fraction::Float64 = 0.2
    soc_init_fraction::Float64 = 0.5
    can_grid_charge::Bool = true
    grid_charge_efficiency::Float64 = 0.96 * 0.975^2
    max_kw::Float64 = size_kw
    max_kwh::Float64 = size_kwh
    minimum_avg_soc_fraction::Float64 = 0.0
end


"""
    MPCGenerator

struct with inner constructor:
```julia
function MPCGenerator(;
    size_kw::Real,
    fuel_cost_per_gallon::Real = 3.0,
    electric_efficiency_full_load::Real = 0.3233,
    electric_efficiency_half_load::Real = electric_efficiency_full_load,
    fuel_avail_gal::Real = 1.0e9,
    fuel_higher_heating_value_kwh_per_gal::Real = KWH_PER_GAL_DIESEL,
    min_turn_down_fraction::Real = 0.0,  # TODO change this to non-zero value
    only_runs_during_grid_outage::Bool = true,
    sells_energy_back_to_grid::Bool = false,
    om_cost_per_kwh::Real=0.0,
    )
```
"""
struct MPCGenerator <: AbstractGenerator
    size_kw
    max_kw
    fuel_cost_per_gallon
    electric_efficiency_full_load
    electric_efficiency_half_load
    fuel_avail_gal
    fuel_higher_heating_value_kwh_per_gal
    min_turn_down_fraction
    only_runs_during_grid_outage
    sells_energy_back_to_grid
    om_cost_per_kwh

    function MPCGenerator(;
        size_kw::Real,
        fuel_cost_per_gallon::Real = 3.0,
        electric_efficiency_full_load::Real = 0.3233,
        electric_efficiency_half_load::Real = electric_efficiency_full_load,
        fuel_avail_gal::Real = 1.0e9,
        fuel_higher_heating_value_kwh_per_gal::Real = KWH_PER_GAL_DIESEL,
        min_turn_down_fraction::Real = 0.0,  # TODO change this to non-zero value
        only_runs_during_grid_outage::Bool = true,
        sells_energy_back_to_grid::Bool = false,
        om_cost_per_kwh::Real=0.0,
        )

        max_kw = size_kw
        
        new(
            size_kw,
            max_kw,
            fuel_cost_per_gallon,
            electric_efficiency_full_load,
            electric_efficiency_half_load,
            fuel_avail_gal,
            fuel_higher_heating_value_kwh_per_gal,
            min_turn_down_fraction,
            only_runs_during_grid_outage,
            sells_energy_back_to_grid,
            om_cost_per_kwh,
        )
    end
end


"""
    MPCCoolingLoad

    Base.@kwdef struct MPCCoolingLoad
        loads_kw_thermal::Array{Real,1}
    end
"""
Base.@kwdef struct MPCCoolingLoad
    loads_kw_thermal::Array{Real,1}
    cop::Union{Real, Nothing}
end


"""
    MPCLimits

struct for MPC specific input parameters:
- `grid_draw_limit_kw_by_time_step::Vector{<:Real}` limits for grid power consumption in each time step; length must be same as `length(loads_kw)`.
- `export_limit_kw_by_time_step::Vector{<:Real}` limits for grid power export in each time step; length must be same as `length(loads_kw)`.

!!! warn 
    `grid_draw_limit_kw_by_time_step` and `export_limit_kw_by_time_step` values can lead to 
    infeasible problems. For example, there is a constraint that the electric load must be met in 
    each time step and by limiting the amount of power from the grid the load balance constraint 
    could be infeasible.
"""
Base.@kwdef struct MPCLimits
    grid_draw_limit_kw_by_time_step::Vector{<:Real} = Real[]
    export_limit_kw_by_time_step::Vector{<:Real} =  Real[]
end
