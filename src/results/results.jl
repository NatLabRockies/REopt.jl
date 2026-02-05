# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    reopt_results(m::JuMP.AbstractModel, p::REoptInputs; _n="")

Create a dictionary of results with string keys for each Scenario structure modeled.
"""
function reopt_results(m::JuMP.AbstractModel, p::REoptInputs; _n="")
	tstart = time()
    d = Dict{String, Any}()
    # TODO determine whether other results specific to electrical or thermal storage
    # systems warrant separate functions
    for b in p.s.storage.types.elec
        if p.s.storage.attr[b].max_kwh > 0
            add_electric_storage_results(m, p, d, b; _n)
        end
    end

    for b in p.s.storage.types.hot
        if p.s.storage.attr[b].max_kwh > 0
            if b == "HighTempThermalStorage"
                add_high_temp_thermal_storage_results(m, p, d, b; _n)
            else
                add_hot_storage_results(m, p, d, b; _n)
            end
        end
    end

    for b in p.s.storage.types.cold
        if p.s.storage.attr[b].max_kwh > 0
            add_cold_storage_results(m, p, d, b; _n)
        end
    end

    add_electric_tariff_results(m, p, d; _n)
    add_electric_utility_results(m, p, d; _n)
    add_financial_results(m, p, d; _n)
    add_electric_load_results(m, p, d; _n)

	if !isempty(p.techs.pv)
        add_pv_results(m, p, d; _n)
	end

    if "Wind" in p.techs.all
        add_wind_results(m, p, d; _n)
    end
    
    if "CHP" in p.techs.all
        add_chp_results(m, p, d; _n)
    end
	
	time_elapsed = time() - tstart
	@debug "Base results processing took $(round(time_elapsed, digits=3)) seconds."
	
	if !isempty(p.techs.gen) && isempty(_n)  # generators not included in multinode model
        tstart = time()
		add_generator_results(m, p, d)
        time_elapsed = time() - tstart
        @debug "Generator results processing took $(round(time_elapsed, digits=3)) seconds."
	end
	
	if !isempty(p.s.electric_utility.outage_durations) && isempty(_n)  # outages not included in multinode model
        tstart = time()
		add_outage_results(m, p, d)
        time_elapsed = time() - tstart
        @debug "Outage results processing took $(round(time_elapsed, digits=3)) seconds."
	end

    if !isempty(p.techs.heating)
        add_heating_load_results(m, p, d)
    end

    if !isempty(p.techs.boiler)
        add_existing_boiler_results(m, p, d)
        if "Boiler" in p.techs.boiler
            add_boiler_results(m, p, d)
        end
    end

    if _n==""
        add_site_results(m, p, d)
    end

    if !isempty(p.techs.cooling)
        add_cooling_load_results(m, p, d)
    end

    if !isnothing(p.s.existing_chiller)
        add_existing_chiller_results(m, p, d)
    end

    if !isempty(p.techs.absorption_chiller)
        add_absorption_chiller_results(m, p, d)
    end

    if !isnothing(p.s.flexible_hvac)
        add_flexible_hvac_results(m, p, d)
    end

    if !isempty(p.ghp_options)
        add_ghp_results(m, p, d)
	end

    if "SteamTurbine" in p.techs.all
        add_steam_turbine_results(m, p, d; _n)
    end

    if "ElectricHeater" in p.techs.electric_heater
        add_electric_heater_results(m, p, d; _n)
    end

    if "CST" in p.techs.electric_heater
        add_concentrating_solar_results(m, p, d; _n)
    end

    if "ASHPSpaceHeater" in p.techs.ashp
        add_ashp_results(m, p, d; _n)
    end
    
    if "ASHPWaterHeater" in p.techs.ashp_wh
        add_ashp_wh_results(m, p, d; _n)
    end

    d["Financial"]["year_one_fuel_cost_before_tax"] = 0.0
    d["Financial"]["year_one_fuel_cost_after_tax"] = 0.0
    for tech in p.techs.fuel_burning
        if tech in keys(d)
            d["Financial"]["year_one_fuel_cost_before_tax"] += d[tech]["year_one_fuel_cost_before_tax"]
            d["Financial"]["year_one_fuel_cost_after_tax"] += d[tech]["year_one_fuel_cost_after_tax"]
        end
    end
    
    d["Financial"]["year_one_total_operating_cost_before_tax"] = d["ElectricTariff"]["year_one_bill_before_tax"] - d["ElectricTariff"]["year_one_export_benefit_before_tax"] + d["Financial"]["year_one_chp_standby_cost_before_tax"] + d["Financial"]["year_one_fuel_cost_before_tax"] + d["Financial"]["year_one_om_costs_before_tax"]
    d["Financial"]["year_one_total_operating_cost_after_tax"] = d["ElectricTariff"]["year_one_bill_after_tax"] - d["ElectricTariff"]["year_one_export_benefit_after_tax"] + d["Financial"]["year_one_chp_standby_cost_after_tax"] + d["Financial"]["year_one_fuel_cost_after_tax"] + d["Financial"]["year_one_om_costs_after_tax"]
    
    return d
end


"""
    combine_results(bau::Dict, opt::Dict)
    
Combine two results dictionaries into one using BAU and optimal scenario results.
New fields added to the Financial output/results:
- `npv`: Net Present Value of the optimal scenario
- `year_one_total_operating_cost_savings_before_tax`: Total operating cost savings in year 1 before tax
- `year_one_total_operating_cost_savings_after_tax`: Total operating cost savings in year 1 after tax
- `breakeven_cost_of_emissions_reduction_per_tonne_CO2`: Breakeven cost of CO2 (usd per tonne) that would yield an npv of 0, holding all other inputs constant
- `lifecycle_emissions_reduction_CO2_fraction`: Fraction of CO2 emissions reduced in the optimal scenario compared to the BAU scenario
"""
function combine_results(p::REoptInputs, bau::Dict, opt::Dict, bau_scenario::BAUScenario)
    bau_outputs = (
        ("Financial", "lcc"),
        ("Financial", "lifecycle_emissions_cost_climate"),
        ("Financial", "lifecycle_emissions_cost_health"),
        ("Financial", "lifecycle_om_costs_before_tax"),
        ("Financial", "lifecycle_om_costs_after_tax"),
        ("Financial", "year_one_om_costs_before_tax"),
        ("Financial", "year_one_om_costs_after_tax"),
        ("Financial", "year_one_fuel_cost_before_tax"),
        ("Financial", "year_one_fuel_cost_after_tax"),
        ("Financial", "year_one_total_operating_cost_before_tax"),
        ("Financial", "year_one_total_operating_cost_after_tax"),
        ("Financial", "lifecycle_fuel_costs_after_tax"),
        ("Financial", "lifecycle_chp_standby_cost_after_tax"),
        ("Financial", "lifecycle_elecbill_after_tax"),
        ("Financial", "lifecycle_production_incentive_after_tax"),
        ("Financial", "lifecycle_outage_cost"),
        ("Financial", "lifecycle_MG_upgrade_and_fuel_cost"),
        ("Financial", "initial_capital_costs_after_incentives"),
        ("Financial", "lifecycle_capital_costs"),
        ("ElectricTariff", "year_one_energy_cost_before_tax"),
        ("ElectricTariff", "year_one_demand_cost_before_tax"),
        ("ElectricTariff", "year_one_fixed_cost_before_tax"),
        ("ElectricTariff", "year_one_min_charge_adder_before_tax"),
        ("ElectricTariff", "lifecycle_energy_cost_after_tax"),
        ("ElectricTariff", "lifecycle_demand_cost_after_tax"),
        ("ElectricTariff", "lifecycle_fixed_cost_after_tax"),
        ("ElectricTariff", "lifecycle_min_charge_adder_after_tax"),
        ("ElectricTariff", "lifecycle_export_benefit_after_tax"),
        ("ElectricTariff", "year_one_bill_before_tax"),
        ("ElectricTariff", "year_one_bill_after_tax"),
        ("ElectricTariff", "year_one_export_benefit_before_tax"),
        ("ElectricTariff", "year_one_export_benefit_after_tax"),
        ("ElectricTariff", "year_one_coincident_peak_cost_before_tax"),
        ("ElectricTariff", "lifecycle_coincident_peak_cost_after_tax"),
        ("ElectricTariff", "monthly_fixed_cost_series_before_tax"),
        ("ElectricTariff", "energy_cost_series_before_tax"),
        ("ElectricTariff", "monthly_energy_cost_series_before_tax"),
        ("ElectricTariff", "monthly_facility_demand_cost_series_before_tax"),
        ("ElectricTariff", "monthly_tou_demand_cost_series_before_tax"),
        ("ElectricTariff", "monthly_demand_cost_series_before_tax"),
        ("ElectricUtility", "electric_to_load_series_kw"),
        ("ElectricUtility", "annual_energy_supplied_kwh"),
        ("ElectricUtility","annual_renewable_electricity_supplied_kwh"),
        ("ElectricUtility", "annual_emissions_tonnes_CO2"),
        ("ElectricUtility", "annual_emissions_tonnes_NOx"),
        ("ElectricUtility", "annual_emissions_tonnes_SO2"),
        ("ElectricUtility", "annual_emissions_tonnes_PM25"),
        ("ElectricUtility", "lifecycle_emissions_tonnes_CO2"),
        ("ElectricUtility", "lifecycle_emissions_tonnes_NOx"),
        ("ElectricUtility", "lifecycle_emissions_tonnes_SO2"),
        ("ElectricUtility", "lifecycle_emissions_tonnes_PM25"),
        ("PV", "annual_energy_produced_kwh"),
        ("PV", "year_one_energy_produced_kwh"),
        ("PV", "lifecycle_om_cost_after_tax"),
        ("Generator", "annual_fuel_consumption_gal"),
        ("Generator", "lifecycle_fixed_om_cost_after_tax"),
        ("Generator", "lifecycle_variable_om_cost_after_tax"),
        ("Generator", "lifecycle_fuel_cost_after_tax"),
        ("Generator", "year_one_fuel_cost_before_tax"),
        ("Generator", "year_one_fuel_cost_after_tax"),
        ("Generator", "year_one_variable_om_cost_before_tax"),
        ("Generator", "year_one_fixed_om_cost_before_tax"),
        ("FlexibleHVAC", "temperatures_degC_node_by_time"),
        ("ExistingBoiler", "lifecycle_fuel_cost_after_tax"),
        ("ExistingBoiler", "year_one_fuel_cost_before_tax"),
        ("ExistingBoiler", "year_one_fuel_cost_after_tax"),
        ("ExistingBoiler", "annual_thermal_production_mmbtu"),
        ("ExistingBoiler", "annual_fuel_consumption_mmbtu"),
        ("ExistingBoiler", "size_mmbtu_per_hour"),
        ("ExistingChiller", "annual_thermal_production_tonhour"),
        ("ExistingChiller", "annual_electric_consumption_kwh"),
        ("ExistingChiller", "size_ton"),
        ("Site", "annual_onsite_renewable_electricity_kwh"),
        ("Site", "onsite_renewable_electricity_fraction_of_elec_load"),
        ("Site", "onsite_renewable_energy_fraction_of_total_load"),
        ("Site", "onsite_and_grid_renewable_electricity_fraction_of_elec_load"),
        ("Site", "onsite_and_grid_renewable_energy_fraction_of_total_load"),
        ("Site", "annual_emissions_tonnes_CO2"),
        ("Site", "annual_emissions_tonnes_NOx"),
        ("Site", "annual_emissions_tonnes_SO2"),
        ("Site", "annual_emissions_tonnes_PM25"),
        ("Site", "annual_emissions_from_fuelburn_tonnes_CO2"),
        ("Site", "annual_emissions_from_fuelburn_tonnes_NOx"),
        ("Site", "annual_emissions_from_fuelburn_tonnes_SO2"),
        ("Site", "annual_emissions_from_fuelburn_tonnes_PM25"),
        ("Site", "year_one_emissions_from_elec_grid_tonnes_CO2"),
        ("Site", "year_one_emissions_from_elec_grid_tonnes_NOx"),
        ("Site", "year_one_emissions_from_elec_grid_tonnes_SO2"),
        ("Site", "year_one_emissions_from_elec_grid_tonnes_PM25"),
        ("Site", "lifecycle_emissions_tonnes_CO2"),
        ("Site", "lifecycle_emissions_tonnes_NOx"),
        ("Site", "lifecycle_emissions_tonnes_SO2"),
        ("Site", "lifecycle_emissions_tonnes_PM25"),
        ("Site", "lifecycle_emissions_from_fuelburn_tonnes_CO2"),
        ("Site", "lifecycle_emissions_from_fuelburn_tonnes_NOx"),
        ("Site", "lifecycle_emissions_from_fuelburn_tonnes_SO2"),
        ("Site", "lifecycle_emissions_from_fuelburn_tonnes_PM25")
    )

    for t in bau_outputs
        if t[1] in keys(opt) && t[1] in keys(bau)
            if t[2] in keys(bau[t[1]])
                opt[t[1]][t[2] * "_bau"] = bau[t[1]][t[2]]
            end
        elseif t[1] == "PV" && !isempty(p.techs.pv)
            for pvname in p.techs.pv
                if pvname in keys(opt) && pvname in keys(bau)
                    if t[2] in keys(bau[pvname])
                        opt[pvname][t[2] * "_bau"] = bau[pvname][t[2]]
                    end
                end
            end
        end
    end
    opt["Financial"]["npv"] = round(opt["Financial"]["lcc_bau"] - opt["Financial"]["lcc"], digits=2)

    opt["ElectricLoad"]["bau_critical_load_met"] = bau_scenario.outage_outputs.bau_critical_load_met
    opt["ElectricLoad"]["bau_critical_load_met_time_steps"] = bau_scenario.outage_outputs.bau_critical_load_met_time_steps

    # emissions reductions
    opt["Site"]["lifecycle_emissions_reduction_CO2_fraction"] = (
        bau["Site"]["lifecycle_emissions_tonnes_CO2"] - opt["Site"]["lifecycle_emissions_tonnes_CO2"]
    ) / bau["Site"]["lifecycle_emissions_tonnes_CO2"]

    # breakeven cost of CO2 (to make NPV = 0)
    # first, remove climate costs from the output NPV, if they were previously included in LCC/NPV calcs:
    npv_without_modeled_climate_costs = opt["Financial"]["npv"]
    if p.s.settings.include_climate_in_objective == true
        npv_without_modeled_climate_costs -= (bau["Financial"]["lifecycle_emissions_cost_climate"] - opt["Financial"]["lifecycle_emissions_cost_climate"])
    end
    # we want to calculate the breakeven year 1 cost of CO2 (usd per tonne) that would yield an npv of 0, holding all other inputs constant
    # (back-calculating using the equation for m[:Lifecycle_Emissions_Cost_CO2] in "add_lifecycle_emissions_calcs" in emissions_constraints.jl)
    if npv_without_modeled_climate_costs < 0 # if the system is not cost effective (NPV < 0) without considering any cost of CO2
        breakeven_cost_denominator = p.pwf_emissions_cost["CO2_grid"] * (
            bau["ElectricUtility"]["annual_emissions_tonnes_CO2"] - opt["ElectricUtility"]["annual_emissions_tonnes_CO2"]
        ) + p.pwf_emissions_cost["CO2_onsite"] * (
            bau["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] - opt["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] 
        )
        if breakeven_cost_denominator != 0.0
            opt["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"] = -1 * npv_without_modeled_climate_costs / breakeven_cost_denominator
        end
    end
        
    opt["Financial"]["year_one_total_operating_cost_savings_before_tax"] = bau["Financial"]["year_one_total_operating_cost_before_tax"] - opt["Financial"]["year_one_total_operating_cost_before_tax"]
    opt["Financial"]["year_one_total_operating_cost_savings_after_tax"] = bau["Financial"]["year_one_total_operating_cost_after_tax"] - opt["Financial"]["year_one_total_operating_cost_after_tax"]
    
    # TODO add FlexibleHVAC opex savings

    return opt
end
