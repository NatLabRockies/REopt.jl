# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ElectricTariff` results keys:
- `lifecycle_energy_cost_after_tax` lifecycle cost of energy from the grid in present value, after tax
- `year_one_energy_cost_before_tax` cost of energy from the grid over the first year, before considering tax benefits
- `lifecycle_demand_cost_after_tax` lifecycle cost of power from the grid in present value, after tax
- `year_one_demand_cost_before_tax` cost of power from the grid over the first year, before considering tax benefits
- `lifecycle_fixed_cost_after_tax` lifecycle fixed cost in present value, after tax
- `year_one_fixed_cost_before_tax` fixed cost over the first year, before considering tax benefits
- `lifecycle_min_charge_adder_after_tax` lifecycle minimum charge in present value, after tax
- `year_one_min_charge_adder_before_tax` minimum charge over the first year, before considering tax benefits
- `year_one_bill_before_tax` sum of `year_one_energy_cost_before_tax`, `year_one_demand_cost_before_tax`, `year_one_fixed_cost_before_tax`, `year_one_min_charge_adder_before_tax`, and `year_one_coincident_peak_cost_before_tax`
- `lifecycle_export_benefit_after_tax` lifecycle export credits in present value, after tax
- `year_one_export_benefit_before_tax` export credits over the first year, before considering tax benefits. A positive value indicates a benefit. 
- `lifecycle_coincident_peak_cost_after_tax` lifecycle coincident peak charge in present value, after tax
- `year_one_coincident_peak_cost_before_tax` coincident peak charge over the first year
"""
function add_electric_tariff_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
    # Adds the `ElectricTariff` results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs` for node `_n`.
    # Note: the node number is an empty string if evaluating a single `Site`.

    r = Dict{String, Any}()
    m[Symbol("Year1UtilityEnergy"*_n)] = p.hours_per_time_step * 
        sum(m[Symbol("dvGridPurchase"*_n)][ts, tier] for ts in p.time_steps, tier in 1:p.s.electric_tariff.n_energy_tiers)

    r["lifecycle_energy_cost_after_tax"] = round(value(m[Symbol("TotalEnergyChargesUtil"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_energy_cost_before_tax"] = round(value(m[Symbol("TotalEnergyChargesUtil"*_n)]) / p.pwf_e, digits=2)

    r["lifecycle_demand_cost_after_tax"] = round(value(m[Symbol("TotalDemandCharges"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_demand_cost_before_tax"] = round(value(m[Symbol("TotalDemandCharges"*_n)]) / p.pwf_e, digits=2)
    
    r["lifecycle_fixed_cost_after_tax"] = round(m[Symbol("TotalFixedCharges"*_n)] * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_fixed_cost_before_tax"] = round(m[Symbol("TotalFixedCharges"*_n)] / p.pwf_e, digits=0)

    r["lifecycle_min_charge_adder_after_tax"] = round(value(m[Symbol("MinChargeAdder"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_min_charge_adder_before_tax"] = round(value(m[Symbol("MinChargeAdder"*_n)]) / p.pwf_e, digits=2)
                                
    r["lifecycle_export_benefit_after_tax"] = -1 * round(value(m[Symbol("TotalExportBenefit"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_export_benefit_before_tax"] = -1 * round(value(m[Symbol("TotalExportBenefit"*_n)]) / p.pwf_e, digits=0)
    r["year_one_export_benefit_after_tax"] = r["year_one_export_benefit_before_tax"] * (1 - p.s.financial.offtaker_tax_rate_fraction)

    r["lifecycle_coincident_peak_cost_after_tax"] = round(value(m[Symbol("TotalCPCharges"*_n)]) * (1 - p.s.financial.offtaker_tax_rate_fraction), digits=2)
    r["year_one_coincident_peak_cost_before_tax"] = round(value(m[Symbol("TotalCPCharges"*_n)]) / p.pwf_e, digits=2)
    
    r["year_one_bill_before_tax"] = r["year_one_energy_cost_before_tax"] + r["year_one_demand_cost_before_tax"] +
                                    r["year_one_fixed_cost_before_tax"]  + r["year_one_min_charge_adder_before_tax"] + r["year_one_coincident_peak_cost_before_tax"]
    
    r["year_one_bill_after_tax"] = r["year_one_bill_before_tax"] * (1 - p.s.financial.offtaker_tax_rate_fraction)

    d["ElectricTariff"] = r
    nothing
end

"""
MPC `ElectricTariff` results keys:
- `energy_cost` Cost of energy from the grid in \$/kWh
- `demand_cost` Cost of power from the grid in \$/kW
- `export_benefit` Export credits in \$/kWh
"""
function add_electric_tariff_results(m::JuMP.AbstractModel, p::MPCInputs, d::Dict; _n="")
    r = Dict{String, Any}()
    m[Symbol("energy_purchased"*_n)] = p.hours_per_time_step * 
        sum(m[Symbol("dvGridPurchase"*_n)][ts] for ts in p.time_steps)

    r["energy_cost"] = round(value(m[Symbol("TotalEnergyChargesUtil"*_n)]), digits=2)

    r["demand_cost"] = round(value(m[Symbol("TotalDemandCharges"*_n)]), digits=2)
                                
    r["export_benefit"] = -1 * round(value(m[Symbol("TotalExportBenefit"*_n)]), digits=0)
    
    d["ElectricTariff"] = r
    nothing
end