# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    Degradation

Inputs used when `ElectricStorage.model_degradation` is `true`:
```julia
Base.@kwdef mutable struct Degradation
    calendar_fade_coefficient::Real = 1.16E-03
    cycle_fade_coefficient::Vector{<:Real} = [2.46E-05]
    cycle_fade_fraction::Vector{<:Real} = [1.0]
    time_exponent::Real = 0.428
    installed_cost_per_kwh_declination_rate::Real = 0.05
    maintenance_strategy::String = "augmentation"  # one of ["augmentation", "replacement"]
    maintenance_cost_per_kwh::Vector{<:Real} = Real[]
end
```

None of the above values are required. If `ElectricStorage.model_degradation` is `true` then the 
defaults above are used. If the `maintenance_cost_per_kwh` is not provided then it is determined 
using the `ElectricStorage.installed_cost_per_kwh` and the `installed_cost_per_kwh_declination_rate` 
along with a present worth factor ``f`` to account for the present cost of buying a battery in the 
future. The present worth factor for each day is:

``
f(day) = \\frac{ (1-r_g)^\\frac{day}{365} } { (1+r_d)^\\frac{day}{365} }
``

where ``r_g`` = `installed_cost_per_kwh_declination_rate` and ``r_d`` = `p.s.financial.owner_discount_rate_fraction`.

Note this day-specific calculation of the present-worth factor accumulates differently from the annually updated discount
rate for other net-present value calculations in REopt, and has a higher effective discount rate as a result.  The present 
worth factor is used in the same manner irrespective of the `maintenance_strategy`.

!!! warn
    When modeling degradation the following ElectricStorage inputs are not used:
    - `replace_cost_per_kwh`
    - `battery_replacement_year`
    - `replace_cost_constant`
    - `cost_constant_replacement_year`
    They are replaced by the `maintenance_cost_per_kwh` vector.
    Inverter replacement costs and inverter replacement year should still be used to model scheduled replacement of inverter.

!!! note
    When providing the `maintenance_cost_per_kwh` it must have a length equal to `Financial.analysis_years*365`-1.


# Battery State Of Health
The state of health [`SOH`] is a linear function of the daily average state of charge [`Eavg`] and
the daily equivalent full cycles [`EFC`]. The initial `SOH` is set to the optimal battery energy capacity 
(in kWh). The evolution of the `SOH` beyond the first day is:

``
SOH[d] = SOH[d-1] - h\\left(
    \\frac{1}{2} k_{cal} Eavg[d-1] / \\sqrt{d} + k_{cyc} EFC[d-1] \\quad \\forall d \\in \\{2\\dots D\\}
\\right)
``

where:
- ``k_{cal}`` is the `calendar_fade_coefficient`
- ``k_{cyc}`` is the `cycle_fade_coefficient`
- ``h`` is the hours per time step
- ``D`` is the total number of days, 365 * `analysis_years`

The `SOH` is used to determine the maintence cost of the storage system, which depends on the `maintenance_strategy`.

!!! note
    Battery degradation parameters are from based on laboratory aging data, and are expected to be reasonable only within 
    the range of conditions tested. Battery lifetime can vary widely from these estimates based on battery use and system design. 
    Battery cost estimates are based on domain expertise and published guidelines and are not to be taken as an indicator of real 
    system costs.

# Augmentation Maintenance Strategy
The augmentation maintenance strategy assumes that the battery energy capacity is maintained by replacing
degraded cells daily in terms of cost. Using the definition of the `SOH` above the maintenance cost is:

``
C_{\\text{aug}} = \\sum_{d \\in \\{2\\dots D\\}} C_{\\text{install}} f(day) \\left( SOH[d-1] - SOH[d] \\right)
``

where
- ``f(day)`` is the present worth factor of battery degradation costs as described above;
- ``C_{\\text{install}}`` is the `ElectricStorage.installed_cost_per_kwh`; and
- ``SOH[d-1] - SOH[d]`` is the incremental amount of battery capacity lost in a day.


The ``C_{\\text{aug}}`` is added to the objective function to be minimized with all other costs.

# Replacement Maintenance Strategy
Modeling the replacement maintenance strategy is more complex than the augmentation strategy.
Effectively the replacement strategy says that the battery has to be replaced once the `SOH` drops below 80%
of the optimal, purchased capacity. It is possible that multiple replacements (at same replacement frequency) could be required under
this strategy.

!!! warn
    The "replacement" maintenance strategy requires integer decision variables.
    Some solvers are slow with integer decision variables.

The replacement strategy cost is:

``
C_{\\text{repl}} = B_{\\text{kWh}} N_{\\text{repl}} f(d_{80}) C_{\\text{install}}
``

where:
- ``B_{\\text{kWh}}`` is the optimal battery capacity (`ElectricStorage.size_kwh` in the results dictionary);
- ``N_{\\text{repl}}`` is the number of battery replacments required (a function of the month in which the `SOH` falls below 80% of original capacity);
- ``f(d_{80})`` is the present worth factor at approximately the 15th day of the month in which the `SOH` falls below 80% of original capacity;
- ``C_{\\text{install}}`` is the `ElectricStorage.installed_cost_per_kwh`.
The ``C_{\\text{repl}}`` is added to the objective function to be minimized with all other costs.

## Battery residual value
Since the battery can be replaced one-to-many times under this strategy, battery residual value captures the \$ value of remaining battery life at end of analysis period.
For example if replacement happens in month 145, then assuming 25 year analysis period there will be 2 replacements (months 145 and 290). 
The last battery which was placed in service during month 290 only serves for 10 months (i.e. 6.89% of its expected life assuming 145 month replacement frequecy).
In this case, the battery has 93.1% of residual life remaining as useful life left after analysis period ends.
A residual value cost vector is created to hold this value for all months. Residual value is calculated as:

``
C_{\\text{residual}} = R f(d_{\\text{last}}) C_{\\text{install}}
``
where:
- ``R`` is the `residual_factor` which determines portion of battery life remaining at the end of the analysis period;
- ``f(d_{\\text{last}})`` is the present worth factor at approximately the 15th day of the last month in the analysis period;
- ``C_{\\text{install}}`` is the `ElectricStorage.installed_cost_per_kwh`.

The ``C_{\\text{residual}}`` is added to the objective function to be minimized with all other costs.

# Example of inputs
The following shows how one would use the degradation model in REopt via the [Scenario](@ref) inputs:
```javascript
{
    ...
    "ElectricStorage": {
        "installed_cost_per_kwh": 390,
        ...
        "model_degradation": true,
        "degradation": {
            "calendar_fade_coefficient": 1.16E-03,
            "cycle_fade_coefficient": [2.46E-05],
            "cycle_fade_fraction": [1.0],
            "time_exponent": 0.428
            "installed_cost_per_kwh_declination_rate": 0.05,
            "maintenance_strategy": "replacement",
            ...
        }
    },
    ...
}
```
Note that not all of the above inputs are necessary. When not providing `calendar_fade_coefficient` for example the default value will be used.

"""
Base.@kwdef mutable struct Degradation
    calendar_fade_coefficient::Real = 1.16E-03
    cycle_fade_coefficient::Vector{<:Real} = [2.46E-05]
    cycle_fade_fraction::Vector{<:Real} = [1.0]
    time_exponent::Real = 0.428
    installed_cost_per_kwh_declination_rate::Real = 0.05
    maintenance_strategy::String = "augmentation"  # one of ["augmentation", "replacement"]
    maintenance_cost_per_kwh::Vector{<:Real} = Real[]
end


"""
`ElectricStorage` is an optional optional REopt input with the following keys and default values:

```julia
    min_kw::Real = 0.0
    max_kw::Real = 1.0e4
    min_kwh::Real = 0.0
    max_kwh::Real = 1.0e6
    internal_efficiency_fraction::Float64 = 0.975
    inverter_efficiency_fraction::Float64 = 0.96
    rectifier_efficiency_fraction::Float64 = 0.96
    soc_min_fraction::Float64 = 0.2
    soc_min_applies_during_outages::Bool = false
    soc_init_fraction::Float64 = off_grid_flag ? 1.0 : 0.5
    can_grid_charge::Bool = off_grid_flag ? false : true
    installed_cost_per_kw::Real = 968.0 # Cost of power components (e.g., inverter and BOS) 
    installed_cost_per_kwh::Real = 253.0 # Cost of energy components (e.g., battery pack)
    installed_cost_constant::Real = 222115.0 # "+c" constant cost that is added to total ElectricStorage installed costs if a battery is included. Accounts for costs not expected to scale with power or energy capacity.
    replace_cost_per_kw::Real = 0.0
    replace_cost_per_kwh::Real = 0.0
    replace_cost_constant::Real = 0.0
    inverter_replacement_year::Int = 10
    battery_replacement_year::Int = 10
    cost_constant_replacement_year::Int = 10
    om_cost_fraction_of_installed_cost::Float64 = 0.025 # Annual O&M cost as a fraction of installed cost
    macrs_option_years::Int = 5 #Note: default may change if Site.sector is not "commercial/industrial"
    macrs_bonus_fraction::Float64 = 1.0 #Note: default may change if Site.sector is not "commercial/industrial"
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3 #Note: default may change if Site.sector is not "commercial/industrial"
    total_rebate_per_kw::Real = 0.0
    total_rebate_per_kwh::Real = 0.0
    charge_efficiency::Float64 = rectifier_efficiency_fraction * internal_efficiency_fraction^0.5
    discharge_efficiency::Float64 = inverter_efficiency_fraction * internal_efficiency_fraction^0.5
    grid_charge_efficiency::Float64 = can_grid_charge ? charge_efficiency : 0.0
    model_degradation::Bool = false
    degradation::Dict = Dict()
    minimum_avg_soc_fraction::Float64 = 0.0
    optimize_soc_init_fraction::Bool = false # If true, soc_init_fraction will not apply. Model will optimize initial SOC and constrain initial SOC = final SOC. 
    min_duration_hours::Real = 0.0 # Minimum amount of time storage can discharge at its rated power capacity
    max_duration_hours::Real = 100000.0 # Maximum amount of time storage can discharge at its rated power capacity (ratio of ElectricStorage size_kwh to size_kw)
```
"""
Base.@kwdef struct ElectricStorageDefaults
    off_grid_flag::Bool = false
    min_kw::Real = 0.0
    max_kw::Real = 1.0e4
    min_kwh::Real = 0.0
    max_kwh::Real = 1.0e6
    internal_efficiency_fraction::Float64 = 0.975
    inverter_efficiency_fraction::Float64 = 0.96
    rectifier_efficiency_fraction::Float64 = 0.96
    soc_min_fraction::Float64 = 0.2
    soc_min_applies_during_outages::Bool = false
    soc_init_fraction::Float64 = off_grid_flag ? 1.0 : 0.5
    can_grid_charge::Bool = off_grid_flag ? false : true
    installed_cost_per_kw::Real = 968.0
    installed_cost_per_kwh::Real = 253.0
    installed_cost_constant::Real = 222115.0
    replace_cost_per_kw::Real = 0.0
    replace_cost_per_kwh::Real = 0.0
    replace_cost_constant::Real = 0.0
    inverter_replacement_year::Int = 10
    battery_replacement_year::Int = 10
    cost_constant_replacement_year::Int = 10
    om_cost_fraction_of_installed_cost::Float64 = 0.025
    macrs_option_years::Int = 5
    macrs_bonus_fraction::Float64 = 1.0
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3
    total_rebate_per_kw::Real = 0.0
    total_rebate_per_kwh::Real = 0.0
    charge_efficiency::Float64 = rectifier_efficiency_fraction * internal_efficiency_fraction^0.5
    discharge_efficiency::Float64 = inverter_efficiency_fraction * internal_efficiency_fraction^0.5
    grid_charge_efficiency::Float64 = can_grid_charge ? charge_efficiency : 0.0
    model_degradation::Bool = false
    degradation::Dict = Dict()
    minimum_avg_soc_fraction::Float64 = 0.0
    optimize_soc_init_fraction::Bool = false
    min_duration_hours::Real = 0.0
    max_duration_hours::Real = 100000.0
end


"""
    function ElectricStorage(d::Dict, f::Financial, s::Site)

Construct ElectricStorage struct from Dict with keys-val pairs from the 
REopt ElectricStorage and Financial inputs.
"""
struct ElectricStorage <: AbstractElectricStorage
    min_kw::Real
    max_kw::Real
    min_kwh::Real
    max_kwh::Real
    internal_efficiency_fraction::Float64
    inverter_efficiency_fraction::Float64
    rectifier_efficiency_fraction::Float64
    soc_min_fraction::Float64
    soc_min_applies_during_outages::Bool
    soc_init_fraction::Float64
    can_grid_charge::Bool
    installed_cost_per_kw::Real
    installed_cost_per_kwh::Real
    installed_cost_constant::Real
    replace_cost_per_kw::Real
    replace_cost_per_kwh::Real
    replace_cost_constant::Real
    inverter_replacement_year::Int
    battery_replacement_year::Int
    cost_constant_replacement_year::Int
    om_cost_fraction_of_installed_cost::Float64
    macrs_option_years::Int
    macrs_bonus_fraction::Float64
    macrs_itc_reduction::Float64
    total_itc_fraction::Float64
    total_rebate_per_kw::Real
    total_rebate_per_kwh::Real
    charge_efficiency::Float64
    discharge_efficiency::Float64
    grid_charge_efficiency::Float64
    net_present_cost_per_kw::Real
    net_present_cost_per_kwh::Real
    net_present_cost_cost_constant::Real
    model_degradation::Bool
    degradation::Degradation
    minimum_avg_soc_fraction::Float64
    optimize_soc_init_fraction::Bool
    min_duration_hours::Real
    max_duration_hours::Real

    function ElectricStorage(d::Dict, f::Financial, s::Site)  
        set_sector_defaults!(d; struct_name="Storage", sector=s.sector, federal_procurement_type=s.federal_procurement_type)
        s = ElectricStorageDefaults(;d...)

        if s.inverter_replacement_year >= f.analysis_years
            @warn "Battery inverter replacement costs (per_kw) will not be considered because inverter_replacement_year is greater than or equal to analysis_years."
        end

        if s.battery_replacement_year >= f.analysis_years
            @warn "Battery replacement costs (per_kwh) will not be considered because battery_replacement_year is greater than or equal to analysis_years."
        end

        if s.min_duration_hours > s.max_duration_hours
            throw(@error("ElectricStorage min_duration_hours must be less than max_duration_hours."))
        end

        macrs_schedule = [0.0]
        if s.macrs_option_years == 5 || s.macrs_option_years == 7
            macrs_schedule = s.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year
        elseif !(s.macrs_option_years == 0)
            throw(@error("ElectricStorage macrs_option_years must be 0, 5, or 7."))
        end

        net_present_cost_per_kw = effective_cost(;
            itc_basis = s.installed_cost_per_kw,
            replacement_cost = s.inverter_replacement_year >= f.analysis_years ? 0.0 : s.replace_cost_per_kw,
            replacement_year = s.inverter_replacement_year,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = s.total_itc_fraction,
            macrs_schedule = macrs_schedule,
            macrs_bonus_fraction = s.macrs_bonus_fraction,
            macrs_itc_reduction = s.macrs_itc_reduction,
            rebate_per_kw = s.total_rebate_per_kw
        )
        net_present_cost_per_kwh = effective_cost(;
            itc_basis = s.installed_cost_per_kwh,
            replacement_cost = s.battery_replacement_year >= f.analysis_years ? 0.0 : s.replace_cost_per_kwh,
            replacement_year = s.battery_replacement_year,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = s.total_itc_fraction,
            macrs_schedule = macrs_schedule,
            macrs_bonus_fraction = s.macrs_bonus_fraction,
            macrs_itc_reduction = s.macrs_itc_reduction
        )

        net_present_cost_per_kwh -= s.total_rebate_per_kwh

	    if (s.installed_cost_constant != 0) || (s.replace_cost_constant != 0)

            net_present_cost_cost_constant = effective_cost(;
                itc_basis = s.installed_cost_constant,
                replacement_cost = s.cost_constant_replacement_year >= f.analysis_years ? 0.0 : s.replace_cost_constant,
                replacement_year = s.cost_constant_replacement_year,
                discount_rate = f.owner_discount_rate_fraction,
                tax_rate = f.owner_tax_rate_fraction,
                itc = s.total_itc_fraction,
                macrs_schedule = macrs_schedule,
                macrs_bonus_fraction = s.macrs_bonus_fraction,
                macrs_itc_reduction = s.macrs_itc_reduction

            )
        else
            net_present_cost_cost_constant = 0
        end

        if haskey(d, :degradation)
            degr = Degradation(;dictkeys_tosymbols(d[:degradation])...)
            if length(degr.cycle_fade_coefficient) != length(degr.cycle_fade_fraction)
                throw(@error("The fields cycle_fade_coefficient and cycle_fade_fraction in ElectricStorage Degradation inputs must have equal length."))
            end
            if length(degr.cycle_fade_coefficient) > 1
                @info "Modeling segmented cycle fade battery degradation costing"
            end
        else
            degr = Degradation()
        end

        # Handle replacement costs for degradation model.
        replace_cost_per_kw = s.replace_cost_per_kw 
        replace_cost_per_kwh = s.replace_cost_per_kwh
        replace_cost_constant = s.replace_cost_constant
        if s.model_degradation
            if haskey(d, :replace_cost_per_kw) && d[:replace_cost_per_kw] != 0.0 || 
                haskey(d, :replace_cost_per_kwh) && d[:replace_cost_per_kwh] != 0.0 ||
                haskey(d, :replace_cost_constant) && d[:replace_cost_constant] != 0.0
                @warn "Setting ElectricStorage replacement costs to zero. Using degradation.maintenance_cost_per_kwh instead."
            end
            replace_cost_per_kw = 0.0
            replace_cost_per_kwh = 0.0
            replace_cost_constant = 0.0
        end
    
        return new(
            s.min_kw,
            s.max_kw,
            s.min_kwh,
            s.max_kwh,
            s.internal_efficiency_fraction,
            s.inverter_efficiency_fraction,
            s.rectifier_efficiency_fraction,
            s.soc_min_fraction,
            s.soc_min_applies_during_outages,
            s.soc_init_fraction,
            s.can_grid_charge,
            s.installed_cost_per_kw,
            s.installed_cost_per_kwh,
            s.installed_cost_constant,
            replace_cost_per_kw,
            replace_cost_per_kwh,
            replace_cost_constant,
            s.inverter_replacement_year,
            s.battery_replacement_year,
            s.cost_constant_replacement_year,
            s.om_cost_fraction_of_installed_cost,
            s.macrs_option_years,
            s.macrs_bonus_fraction,
            s.macrs_itc_reduction,
            s.total_itc_fraction,
            s.total_rebate_per_kw,
            s.total_rebate_per_kwh,
            s.charge_efficiency,
            s.discharge_efficiency,
            s.grid_charge_efficiency,
            net_present_cost_per_kw,
            net_present_cost_per_kwh,
            net_present_cost_cost_constant,
            s.model_degradation,
            degr,
            s.minimum_avg_soc_fraction,
            s.optimize_soc_init_fraction,
            s.min_duration_hours,
            s.max_duration_hours
        )
    end
end
