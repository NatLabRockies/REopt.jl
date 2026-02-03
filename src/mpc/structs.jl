

# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    MPCElectricLoad

"""
`MPCSite` is an optional REopt MPC input with the following keys and default values:

```julia
    include_exported_elec_emissions_in_total::Bool = true, # Accounts for the emissions offsets from electricity exported to the grid
```
"""
Base.@kwdef struct MPCSite
    include_exported_elec_emissions_in_total::Bool = true
end

"""
`MPCElectricLoad` is a required REopt MPC input with the following keys and default values:

```julia
    loads_kw::Array{Real,1}, # Electric loads in kW 
    critical_loads_kw::Union{Nothing, Array{Real,1}} = nothing, # Critical electric load that must be served during outages
    min_load_met_annual_fraction::Real = 1.0, # Minimum fraction of the annual electric load that must be met by the system #TODO - check functionality
```
"""
Base.@kwdef struct MPCElectricLoad
    loads_kw::Array{Real,1}
    critical_loads_kw::Union{Nothing, Array{Real,1}} = nothing
    min_load_met_annual_fraction::Real = 1.0
end


"""
`MPCFinancial` is an optional REopt MPC input with the following keys and default values:

```julia
    value_of_lost_load_per_kwh::Union{Array{R,1}, R} where R<:Real = 1.00, # Value of lost load in \$/kWh
    CO2_cost_per_tonne::Real = 51.0, # Cost of CO2 emissions in \$/tonne
```
"""
Base.@kwdef struct MPCFinancial
    value_of_lost_load_per_kwh::Union{Array{R,1}, R} where R<:Real = 1.00
    CO2_cost_per_tonne::Real = 51.0
end


"""
`MPCPV` is an optional REopt MPC input with the following keys and default values:

```julia
    name::String="PV", # Name of the PV system
    size_kw::Real = 0, # Size of the PV system in kW-DC
    production_factor_series::Union{Nothing, Array{Real,1}} = nothing, # Production factor series. Must be normalized to units of kW-AC/kW-DC nameplate and equal to the length of loads_kw
```
"""
Base.@kwdef struct MPCPV
    name::String="PV"
    size_kw::Real = 0
    production_factor_series::Union{Nothing, Array{Real,1}} = nothing
end


"""
`MPCWind` is an optional REopt MPC input with the following keys and default values:

```julia
    size_kw::Real = 0, # Size of the wind power system in kW
    production_factor_series::Union{Nothing, Array{Real,1}} = nothing, # Production factor series. Must be normalized to units of kW-AC/kW-DC nameplate and equal to the length of loads_kw
    om_cost_per_kw::Real = 0.0, # Fixed O&M cost based on power capacity (\$/kW-installed)
```
"""
Base.@kwdef struct MPCWind
    size_kw::Real = 0
    production_factor_series::Union{Nothing, Array{Real,1}} = nothing
    om_cost_per_kw::Real = 0.0
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

Function for parsing user inputs into:
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
    - must have length equal to `tou_demand_ratchet_time_steps`
    - default = []

  - `tou_demand_ratchet_time_steps`

    - an array of arrays for the integer time steps that apply to the `tou_demand_rates`
    - default = []

  - `tou_previous_peak_demands`

    - an array of the previous peak demands set in each time-of-use demand period
    - must have length equal to `tou_demand_ratchet_time_steps`
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
    tou_demand_ratchet_time_steps = get(d, "tou_demand_ratchet_time_steps", [])
    tou_previous_peak_demands = get(d, "tou_previous_peak_demands", Float64[])
    @assert length(tou_demand_rates) == length(tou_demand_ratchet_time_steps) == length(tou_previous_peak_demands)

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
        tou_demand_ratchet_time_steps,
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
`MPCElectricStorage` is an optional REopt MPC input with the following keys and default values:

```julia
    size_kw::Float64, # Size of the storage inverter in kW
    size_kwh::Float64, # Size of the storage system in kWh
    charge_efficiency::Float64 =  0.96 * 0.975^0.5, # Charge efficiency the storage system
    discharge_efficiency::Float64 =  0.96 * 0.975^0.5, # Discharge efficiency the storage system
    soc_min_fraction::Float64 = 0.2, # Minimum state of charge fraction
    soc_init_fraction::Float64 = 0.5, # Initial state of charge fraction
    can_grid_charge::Bool = true, # True/False for if storage can charge from the grid
    grid_charge_efficiency::Float64 = can_grid_charge ? charge_efficiency : 0.0, # Efficiency of charging the storage from the grid
    capacity_self_discharge_rate_fraction::Float64 = 0.0 # hydrogen self-discharge per timestep, as a fraction of the system's rated kWh capacity
    soc_self_discharge_rate_fraction::Float64 = 0.0 # hydrogen self-discharge per timestep, as a fraction of the kWh stored in each timestep
```
"""
Base.@kwdef struct MPCElectricStorage <: AbstractElectricStorage
    size_kw::Float64
    size_kwh::Float64
    charge_efficiency::Float64 = 0.96 * 0.975^0.5
    discharge_efficiency::Float64 = 0.96 * 0.975^0.5
    soc_min_fraction::Float64 = 0.2
    soc_init_fraction::Float64 = 0.5
    can_grid_charge::Bool = true
    grid_charge_efficiency::Float64 = can_grid_charge ? charge_efficiency : 0.0
    max_kw::Float64 = size_kw
    max_kwh::Float64 = size_kwh
    minimum_avg_soc_fraction::Float64 = 0.0
    capacity_self_discharge_rate_fraction::Float64 = 0.0
    soc_self_discharge_rate_fraction::Float64 = 0.0
    fixed_dispatch_series::Union{Nothing, Array{Real,1}} = nothing
end


"""
`MPCGenerator` is an optional REopt MPC input with the following keys and default values:

```julia
    size_kw::Real, # Size of the generator in kW
    fuel_cost_per_gallon::Real = 3.0, # Fuel cost (\$/gal)
    electric_efficiency_full_load::Real = 0.3233, # Electric efficiency of the generator at full load 
    electric_efficiency_half_load::Real = electric_efficiency_full_load, # Electric efficiency of the generator at half load
    fuel_avail_gal::Real = 1.0e9, # Fuel available (gallons)
    fuel_higher_heating_value_kwh_per_gal::Real = KWH_PER_GAL_DIESEL, # Higher heating value of the fuel in kWh per gallon (defaults to the HHV of diesel)
    min_turn_down_fraction::Real = 0.0, # Minimum generator loading in fraction of capacity (size_kw)
    only_runs_during_grid_outage::Bool = true, # True/False for if generator only runs during grid outages
    sells_energy_back_to_grid::Bool = false, # True/False for if generator can sell energy back to the grid
    om_cost_per_kwh::Real=0.0, # Variable O&M cost based on energy produced (\$/kWh of production)
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

#HYDROGEN TECHS
"""
`MPCElectrolyzer` is an optional REopt MPC input with the following keys and default values:

```julia
    size_kw::Float64, # Size of the electrolyzer in kW
    require_compression::Bool = true, # If true, a compressor is used to bring the hydrogen produced by the electrolyzer to higher pressures before storage
    efficiency_kwh_per_kg::Float64 =  55.8, # Efficiency of the electrolyzer in kWh of energy required per kg of hydrogen produced
    om_cost_per_kw::Float64 = 66.16, # Fixed O&M cost based on power capacity (\$/kW-installed)
    om_cost_per_kwh::Float64 = 0.0005, # Variable O&M cost based on production (\$/kWh of production)
```
"""
Base.@kwdef struct MPCElectrolyzer <: AbstractElectrolyzer
    size_kw::Float64
    require_compression::Bool = true
    efficiency_kwh_per_kg::Float64 =  55.8
    om_cost_per_kw::Float64 = 66.16
    om_cost_per_kwh::Float64 = 0.0005
end

"""
`MPCHydrogenStorage` is an optional REopt MPC input with the following keys and default values:

```julia
    size_kg::Float64, # Size of the hydrogen storage in kg
    soc_min_fraction::Float64 = 0.05, # Minimum state of charge fraction
    soc_init_fraction::Float64 = 0.5, # Initial state of charge fraction
    capacity_self_discharge_rate_fraction::Float64 = 0.0 # Storage leakage per timestep, as a fraction of the rated kg capacity of the H2 storage tank
    soc_self_discharge_rate_fraction::Float64 = 0.0 # Storage leakage per timestep, as a fraction of the kg of H2 stored in each timestep
    minimum_avg_soc_fraction::Float64 = 0.0, # Minimum average state of charge fraction of the system over a typical year of operation
```
"""
Base.@kwdef struct MPCHydrogenStorage <: AbstractHydrogenStorage
    size_kg::Float64
    soc_min_fraction::Float64 = 0.01
    soc_init_fraction::Float64 = 0.5
    capacity_self_discharge_rate_fraction::Float64 = 0.0
    soc_self_discharge_rate_fraction::Float64 = 0.0
    max_kg::Float64 = size_kg
    minimum_avg_soc_fraction::Float64 = 0.0
end

"""
`MPCFuelCell` is an optional REopt MPC input with the following keys and default values:

```julia
    size_kw::Float64, # Size of the fuel cell in kW
    efficiency_kwh_per_kg::Float64 =  15.98, # Efficiency of the fuel cell in kWh of electricity generated per kg of hydrogen consumed
    om_cost_per_kw::Float64 = 16, # Fixed O&M cost based on power capacity (\$/kW-installed)
    om_cost_per_kwh::Float64 = 0.0016, # Variable O&M cost based on production (\$/kWh of production)
```
"""
Base.@kwdef struct MPCFuelCell <: AbstractFuelCell
    size_kw::Float64
    efficiency_kwh_per_kg::Float64 =  15.98
    om_cost_per_kw::Float64 = 16
    om_cost_per_kwh::Float64 = 0.0016
end

"""
`MPCHydrogenLoad` is an optional REopt MPC input with the following keys and default values:

```julia
    loads_kg::Array{Real,1} = Real[], # Hydrogen loads in kg; must be equal to the length of loads_kw
```
"""
Base.@kwdef struct MPCHydrogenLoad
    loads_kg::Array{Real,1} = Real[]
end

"""
`MPCCompressor` is an optional REopt MPC input with the following keys and default values:

```julia
    size_kw::Float64, # Size of the compressor in kW
    efficiency_kwh_per_kg::Float64 = 3.3, # Efficiency of the compressor in kWh of energy required per kg of hydrogen compressed
    om_cost_per_kw::Float64 = 0, # Fixed O&M cost based on power capacity (\$/kW-installed)
    om_cost_per_kwh::Float64 = 0, # Variable O&M cost based on production (\$/kWh of production)
```
"""
Base.@kwdef struct MPCCompressor <: AbstractCompressor
    size_kw::Float64
    efficiency_kwh_per_kg::Float64 = 3.3
    om_cost_per_kwh::Float64 = 0
    om_cost_per_kw::Float64 = 0
end


# THERMAL TECHS
"""
`MPCProcessHeatLoad` is an optional REopt MPC input with the following keys and default values:

```julia
    heat_loads_mmbtu_per_hour::Array{<:Real,1} = Real[], # Process heat loads in MMBTU per hour; must be equal to the length of loads_kw
```
"""
struct MPCProcessHeatLoad
    loads_kw#::Union{Nothing, Array{Real,1}} = nothing
    # production_factor_series::Union{Nothing, Array{Real,1}} = nothing
    function MPCProcessHeatLoad(;
        heat_loads_mmbtu_per_hour::Array{<:Real,1} = Real[],
    )
        loads_kw = heat_loads_mmbtu_per_hour * KWH_PER_MMBTU 
        new(loads_kw)
    end
end

"""
`MPCElectricHeater` is an optional REopt MPC input with the following keys and default values:

```julia
    size_mmbtu_per_hour::Real, # Thermal power size in MMBTU per hour
    cop::Real = 1.0, # Coefficient of performance of the heating (i.e., thermal power produced / electricity consumed)
    can_serve_dhw::Bool = true, # True/False for if technology can supply heat to the domestic hot water loads
    can_serve_space_heating::Bool = true, # True/False for if technology can supply heat to the space heating loads
    can_serve_process_heat::Bool = true, # True/False for if technology can supply heat to the process heat loads
```
"""
struct MPCElectricHeater <: AbstractThermalTech
    size_kw#::Real
    cop#::Real
    can_serve_dhw#::Bool
    can_serve_space_heating#::Bool
    can_serve_process_heat#::Bool

    function MPCElectricHeater(;
        size_mmbtu_per_hour::Real,
        cop::Real = 1.0,
        can_serve_dhw::Bool = true,
        can_serve_space_heating::Bool = true,
        can_serve_process_heat::Bool = true
    )
        # Convert max sizes, cost factors from mmbtu_per_hour to kw
        size_kw = size_mmbtu_per_hour * KWH_PER_MMBTU
        
        new(
            size_kw,
            cop,
            can_serve_dhw,
            can_serve_space_heating,
            can_serve_process_heat
        )
    end
end

"""
    MPCCoolingLoad - Placeholder, not yet implemented in REopt MPC

```julia
Base.@kwdef struct MPCCoolingLoad
    loads_kw_thermal::Array{Real,1}
end
```
"""
Base.@kwdef struct MPCCoolingLoad
    loads_kw_thermal::Array{Real,1}
    cop::Union{Real, Nothing}
end

"""
    MPCDomesticHotWaterLoad - Placeholder, not yet implemented in REopt MPC

```julia
Base.@kwdef struct MPCDomesticHotWaterLoad
    loads_kw_thermal::Array{Real,1}
end
```
"""
Base.@kwdef struct MPCDomesticHotWaterLoad
    loads_kw_thermal::Array{Real,1}
end

"""
    MPCSpaceHeatingLoad - Placeholder, not yet implemented in REopt MPC

```julia
Base.@kwdef struct MPCSpaceHeatingLoad
    loads_kw_thermal::Array{Real,1}
end
```
"""
Base.@kwdef struct MPCSpaceHeatingLoad
    loads_kw_thermal::Array{Real,1}
end


"""
`MPCHighTempThermalStorage` is an optional REopt MPC input with the following keys and default values:

```julia
    charge_kw::Float64, # Size of the charge mechanism in kW
    discharge_kw::Float64, # Size of the discharge mechanism in kW
    size_kwh::Float64, # Size of the thermal storage size in kWh
    charge_efficiency::Float64 = 1.0, # Efficiency of the charge mechanism
    discharge_efficiency::Float64 = 0.9, # Efficiency of the discharge mechanism
    constrain_dispatch_to_stored_kwh::Bool = false, # True/False for if maximum charge and discharge power in timestep t is constrained to be less than a fraction of the energy stored in the system in timestep t-1
    charge_limit_as_fraction_of_stored_kwh::Float64 = 1.0, # If constrain_dispatch_to_stored_kwh is true, limit charging power to this fraction of the energy stored in the system in the previous timestep 
    discharge_limit_as_fraction_of_stored_kwh::Float64 = 1.0, # If constrain_dispatch_to_stored_kwh is true, limit discharging power to this fraction of the energy stored in the system in the previous timestep 
    include_discharge_pump_losses::Bool = false, # True/False for if auxiliary pump losses based on discharge power are modeled
    pump_loss_as_fraction_of_discharge_kw::Float64 = 0.01, # Fraction of discharge power that is consumed as electricity by the auxiliary pump. This electric power must be supplied by another source.
    soc_min_fraction::Float64 = 0.2, # Minimum state of charge fraction
    soc_init_fraction::Float64 = 0.5, # Initial state of charge fraction
    minimum_avg_soc_fraction::Float64 = 0.0, # Minimum average state of charge fraction of the system over a typical year of operation
    thermal_decay_rate_fraction::Float64 = 0.0004, # Fraction of stored energy lost per timestep due to thermal decay
    can_serve_dhw::Bool = false, # True/False for if technology can supply heat to the domestic hot water loads
    can_serve_space_heating::Bool = false, # True/False for if technology can supply heat to the space heating loads
    can_serve_process_heat::Bool = true, # True/False for if technology can supply heat to the process heat loads
```
"""
Base.@kwdef struct MPCHighTempThermalStorage <: AbstractThermalStorage
    charge_kw::Float64
    discharge_kw::Float64
    size_kwh::Float64
    charge_efficiency::Float64 = 1.0
    discharge_efficiency::Float64 = 0.9
    constrain_dispatch_to_stored_kwh::Bool = false
    charge_limit_as_fraction_of_stored_kwh::Float64 = 1.0
    discharge_limit_as_fraction_of_stored_kwh::Float64 = 1.0
    include_discharge_pump_losses::Bool = false
    pump_loss_as_fraction_of_discharge_kw::Float64 = 0.01
    soc_min_fraction::Float64 = 0.2
    soc_init_fraction::Float64 = 0.5
    size_kw::Float64 = charge_kw + discharge_kw
    max_kw::Float64 = max(charge_kw, discharge_kw)
    max_kwh::Float64 = size_kwh
    minimum_avg_soc_fraction::Float64 = 0.0
    thermal_decay_rate_fraction::Float64 = 0.0004
    can_serve_dhw::Bool = false
    can_serve_space_heating::Bool = false
    can_serve_process_heat::Bool = true
end

"""
`MPCLimits` is an optional REopt MPC input with the following keys and default values:

```julia
    grid_draw_limit_kw_by_time_step::Vector{<:Real}, # Limits grid power consumption in each time step (length of input series must be same as loads_kw)
    export_limit_kw_by_time_step::Vector{<:Real}, # Limits grid power export in each time step (length of input series must be same as loads_kw)
```
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
