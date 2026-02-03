# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
"""
`HydrogenStorage` is an optional REopt input with the following keys and default values:

```julia
    min_kg::Real = 0.0, # Minimum hydrogen storage capacity in kg
    max_kg::Real = 1.0e6, # Maximum hydrogen storage capacity in kg
    soc_min_fraction::Float64 = 0.05, # Minimum state of charge fraction
    soc_init_fraction::Float64 = 0.5, # Initial state of charge fraction
    installed_cost_per_kg::Real = 500.0, # Total installed cost per kg of hydrogen storage
    replace_cost_per_kg::Real = 300.0, # Replacement cost per kg of hydrogen storage
    replacement_year::Int = 25, # Year of the analysis in which the storage tank is replaced
    macrs_option_years::Int = 7, # MACRS schedule for financial analysis (5 or 7 years). Set to zero to disable
    macrs_bonus_fraction::Float64 = 0.8, # Fraction of upfront project costs to depreciate in Year 1 in addition to scheduled depreciation
    macrs_itc_reduction::Float64 = 0.5, # Fraction of the ITC value by which the depreciable basis is reduced
    total_itc_fraction::Float64 = 0.3, # Total Investment Tax Credit (ITC) fraction
    minimum_avg_soc_fraction::Float64 = 0.0, # Minimum average state of charge fraction of the system over a typical year of operation
    soc_min_applies_during_outages::Bool = false, # If true, the minimum state of charge fraction applies during outages. Otherwise min SOC is set to 0 during outages.
    soc_self_discharge_rate_fraction::Float64 = 0.0 # Storage leakage per timestep, as a fraction of the kg of H2 stored in each timestep
    capacity_self_discharge_fraction::Float64 = 0.0 # Storage leakage per timestep, as a fraction of the rated kg capacity of the H2 storage tank
    require_start_and_end_charge_to_be_equal::Bool = true, # If true, the model will constrain final SOC = initial SOC
```
"""
Base.@kwdef struct HydrogenStorageDefaults
    min_kg::Real = 0.0
    max_kg::Real = 1.0e6
    soc_min_fraction::Float64 = 0.05
    soc_init_fraction::Float64 = 0.5
    installed_cost_per_kg::Real = 1524
    replace_cost_per_kg::Real = 300.0
    replacement_year::Int = 25
    macrs_option_years::Int = 7
    macrs_bonus_fraction::Float64 = 0.8
    macrs_itc_reduction::Float64 = 0.5
    total_itc_fraction::Float64 = 0.3
    total_rebate_per_kg::Real = 0.0
    minimum_avg_soc_fraction::Float64 = 0.0
    soc_min_applies_during_outages::Bool = false
    soc_self_discharge_rate_fraction::Float64 = 0.0 
    capacity_self_discharge_rate_fraction::Float64 = 0.0
    require_start_and_end_charge_to_be_equal::Bool = true
end


"""
    function HydrogenStorage(d::Dict, f::Financial, settings::Settings)

Construct HydrogenStorage struct from Dict with keys-val pairs from the 
REopt HydrogenStorage and Financial inputs.
"""
struct HydrogenStorage <: AbstractHydrogenStorage
    min_kg::Real
    max_kg::Real
    soc_min_fraction::Float64
    soc_init_fraction::Float64
    installed_cost_per_kg::Real
    replace_cost_per_kg::Real
    replacement_year::Int
    macrs_option_years::Int
    macrs_bonus_fraction::Float64
    macrs_itc_reduction::Float64
    total_itc_fraction::Float64
    total_rebate_per_kg::Real
    net_present_cost_per_kg::Real
    minimum_avg_soc_fraction::Float64
    soc_min_applies_during_outages::Bool
    soc_self_discharge_rate_fraction::Float64
    capacity_self_discharge_rate_fraction::Float64
    require_start_and_end_charge_to_be_equal::Bool

    function HydrogenStorage(d::Dict, f::Financial)  
        s = HydrogenStorageDefaults(;d...)

        if s.replacement_year >= f.analysis_years
            @warn "Hydrogen storage tank replacement costs (per_kg) will not be considered because replacement_year >= analysis_years."
        end

        net_present_cost_per_kg = effective_cost(;
            itc_basis = s.installed_cost_per_kg,
            replacement_cost = s.replacement_year >= f.analysis_years ? 0.0 : s.replace_cost_per_kg,
            replacement_year = s.replacement_year,
            discount_rate = f.owner_discount_rate_fraction,
            tax_rate = f.owner_tax_rate_fraction,
            itc = s.total_itc_fraction,
            macrs_schedule = s.macrs_option_years == 7 ? f.macrs_seven_year : f.macrs_five_year,
            macrs_bonus_fraction = s.macrs_bonus_fraction,
            macrs_itc_reduction = s.macrs_itc_reduction
        )

        net_present_cost_per_kg -= s.total_rebate_per_kg
    
        return new(
            s.min_kg,
            s.max_kg,
            s.soc_min_fraction,
            s.soc_init_fraction,
            s.installed_cost_per_kg,
            s.replace_cost_per_kg,
            s.replacement_year,
            s.macrs_option_years,
            s.macrs_bonus_fraction,
            s.macrs_itc_reduction,
            s.total_itc_fraction,
            s.total_rebate_per_kg,
            net_present_cost_per_kg,
            s.minimum_avg_soc_fraction,
            s.soc_min_applies_during_outages,
            s.soc_self_discharge_rate_fraction,
            s.capacity_self_discharge_rate_fraction,
            s.require_start_and_end_charge_to_be_equal
        )
    end
end
