# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`Generator` is an optional REopt input with the following keys and default values:
```julia
    only_runs_during_grid_outage::Bool = true,
    existing_kw::Real = 0,
    min_kw::Real = 0,
    max_kw::Real = 1.0e6,
    installed_cost_per_kw::Real = off_grid_flag ? 880 : only_runs_during_grid_outage ? 650.0 : 800.0,
    om_cost_per_kw::Real = off_grid_flag ? 10.0 : 20.0,
    om_cost_per_kwh::Real = 0.0,
    fuel_cost_per_gallon::Real = 2.25,
    electric_efficiency_full_load::Real = 0.322,
    electric_efficiency_half_load::Real = electric_efficiency_full_load,
    fuel_avail_gal::Real = 1.0e9,
    fuel_higher_heating_value_kwh_per_gal::Real = 40.7,
    min_turn_down_fraction::Real = off_grid_flag ? 0.15 : 0.0,
    sells_energy_back_to_grid::Bool = false,
    can_net_meter::Bool = false,
    can_wholesale::Bool = false,
    can_export_beyond_nem_limit = false,
    can_curtail::Bool = false,
    macrs_option_years::Int = 0,
    macrs_bonus_fraction::Real = 0.0,
    macrs_itc_reduction::Real = 0.0,
    federal_itc_fraction::Real = 0.0,
    federal_rebate_per_kw::Real = 0.0,
    state_ibi_fraction::Real = 0.0,
    state_ibi_max::Real = 1.0e10,
    state_rebate_per_kw::Real = 0.0,
    state_rebate_max::Real = 1.0e10,
    utility_ibi_fraction::Real = 0.0,
    utility_ibi_max::Real = 1.0e10,
    utility_rebate_per_kw::Real = 0.0,
    utility_rebate_max::Real = 1.0e10,
    production_incentive_per_kwh::Float64 = 0.0 # revenue from production incentive per kWh electricity produced, including curtailment
    production_incentive_max_benefit::Float64 = 1.0e9 # maximum allowable annual revenue from production incentives
    production_incentive_years::Int = 0 # number of year in which production incentives are paid
    production_incentive_max_kw::Float64 = 1.0e9 # maximum allowable system size to receive production incentives
    fuel_renewable_energy_fraction::Real = 0.0,
    emissions_factor_lb_CO2_per_gal::Real = 22.58, # CO2e
    emissions_factor_lb_NOx_per_gal::Real = 0.0775544,
    emissions_factor_lb_SO2_per_gal::Real = 0.040020476,
    emissions_factor_lb_PM25_per_gal::Real = 0.0,
    replacement_year::Int = off_grid_flag ? 10 : analysis_years, # Project year in which generator capacity will be replaced at a cost of replace_cost_per_kw.
    replace_cost_per_kw::Real = off_grid_flag ? installed_cost_per_kw : 0.0 # Per kW replacement cost for generator capacity. Replacement costs are considered tax deductible.
```

!!! note "Replacement costs" 
    Generator replacement costs will not be considered if `Generator.replacement_year` >= `Financial.analysis_years`.

"""
struct Generator <: AbstractGenerator
    existing_kw
    min_kw
    max_kw
    installed_cost_per_kw
    om_cost_per_kw
    om_cost_per_kwh
    fuel_cost_per_gallon
    electric_efficiency_full_load
    electric_efficiency_half_load
    fuel_avail_gal
    fuel_higher_heating_value_kwh_per_gal
    min_turn_down_fraction
    only_runs_during_grid_outage
    sells_energy_back_to_grid
    can_net_meter
    can_wholesale
    can_export_beyond_nem_limit
    can_curtail
    macrs_option_years
    macrs_bonus_fraction
    macrs_itc_reduction
    federal_itc_fraction
    federal_rebate_per_kw
    state_ibi_fraction
    state_ibi_max
    state_rebate_per_kw
    state_rebate_max
    utility_ibi_fraction
    utility_ibi_max
    utility_rebate_per_kw
    utility_rebate_max
    production_incentive_per_kwh
    production_incentive_max_benefit
    production_incentive_years
    production_incentive_max_kw
    fuel_renewable_energy_fraction
    emissions_factor_lb_CO2_per_gal
    emissions_factor_lb_NOx_per_gal
    emissions_factor_lb_SO2_per_gal
    emissions_factor_lb_PM25_per_gal
    replacement_year
    replace_cost_per_kw

    function Generator(;
        off_grid_flag::Bool = false,
        analysis_years::Int = 25, 
        only_runs_during_grid_outage::Bool = true,
        existing_kw::Real = 0,
        min_kw::Real = 0,
        max_kw::Real = 1.0e6,
        installed_cost_per_kw::Real = off_grid_flag ? 880 : only_runs_during_grid_outage ? 650.0 : 800.0,
        om_cost_per_kw::Real= off_grid_flag ? 10.0 : 20.0,
        om_cost_per_kwh::Real = 0.0,
        fuel_cost_per_gallon::Real = 2.25,
        electric_efficiency_full_load::Real = 0.322,
        electric_efficiency_half_load::Real = electric_efficiency_full_load,
        fuel_avail_gal::Real = 1.0e9,
        fuel_higher_heating_value_kwh_per_gal::Real = KWH_PER_GAL_DIESEL,
        min_turn_down_fraction::Real = off_grid_flag ? 0.15 : 0.0,
        sells_energy_back_to_grid::Bool = false,
        can_net_meter::Bool = false,
        can_wholesale::Bool = false,
        can_export_beyond_nem_limit = false,
        can_curtail::Bool = false,
        macrs_option_years::Int = 0,
        macrs_bonus_fraction::Real = 0.0,
        macrs_itc_reduction::Real = 0.0,
        federal_itc_fraction::Real = 0.0,
        federal_rebate_per_kw::Real = 0.0,
        state_ibi_fraction::Real = 0.0,
        state_ibi_max::Real = 1.0e10,
        state_rebate_per_kw::Real = 0.0,
        state_rebate_max::Real = 1.0e10,
        utility_ibi_fraction::Real = 0.0,
        utility_ibi_max::Real = 1.0e10,
        utility_rebate_per_kw::Real = 0.0,
        utility_rebate_max::Real = 1.0e10,
        production_incentive_per_kwh::Real = 0.0,
        production_incentive_max_benefit::Real = 1.0e9,
        production_incentive_years::Int = 0,
        production_incentive_max_kw::Real = 1.0e9,
        fuel_renewable_energy_fraction::Real = 0.0,
        emissions_factor_lb_CO2_per_gal::Real = 22.58, # CO2e
        emissions_factor_lb_NOx_per_gal::Real = 0.0775544,
        emissions_factor_lb_SO2_per_gal::Real = 0.040020476,
        emissions_factor_lb_PM25_per_gal::Real = 0.0,
        replacement_year::Int = off_grid_flag ? 10 : analysis_years, # Project year in which generator capacity will be replaced at a cost of replace_cost_per_kw.
        replace_cost_per_kw::Real = off_grid_flag ? installed_cost_per_kw : 0.0 # Per kW replacement cost for generator capacity. Replacement costs are considered tax deductible.
    )

        if (replacement_year >= analysis_years) && !(replace_cost_per_kw == 0.0)
            @warn "Generator replacement costs will not be considered because replacement_year >= analysis_years."
        end

        new(
            existing_kw,
            min_kw,
            max_kw,
            installed_cost_per_kw,
            om_cost_per_kw,
            om_cost_per_kwh,
            fuel_cost_per_gallon,
            electric_efficiency_full_load,
            electric_efficiency_half_load,
            fuel_avail_gal,
            fuel_higher_heating_value_kwh_per_gal,
            min_turn_down_fraction,
            only_runs_during_grid_outage,
            sells_energy_back_to_grid,
            can_net_meter,
            can_wholesale,
            can_export_beyond_nem_limit,
            can_curtail,
            macrs_option_years,
            macrs_bonus_fraction,
            macrs_itc_reduction,
            federal_itc_fraction,
            federal_rebate_per_kw,
            state_ibi_fraction,
            state_ibi_max,
            state_rebate_per_kw,
            state_rebate_max,
            utility_ibi_fraction,
            utility_ibi_max,
            utility_rebate_per_kw,
            utility_rebate_max,
            production_incentive_per_kwh,
            production_incentive_max_benefit,
            production_incentive_years,
            production_incentive_max_kw,
            fuel_renewable_energy_fraction,
            emissions_factor_lb_CO2_per_gal,
            emissions_factor_lb_NOx_per_gal,
            emissions_factor_lb_SO2_per_gal,
            emissions_factor_lb_PM25_per_gal,
            replacement_year,
            replace_cost_per_kw
        )
    end
end
