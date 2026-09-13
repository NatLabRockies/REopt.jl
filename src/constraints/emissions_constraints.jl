# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

function add_emissions_constraints(m,p)
	if !isnothing(p.s.site.bau_emissions_lb_CO2_per_year)
		if !isnothing(p.s.site.CO2_emissions_reduction_min_fraction)
			@constraint(m, MinEmissionsReductionCon, 
				m[:Lifecycle_Emissions_Lbs_CO2] <= 
				(1-p.s.site.CO2_emissions_reduction_min_fraction) * m[:Lifecycle_Emissions_Lbs_CO2_BAU]
			)
		end
		if !isnothing(p.s.site.CO2_emissions_reduction_max_fraction)
			@constraint(m, MaxEmissionsReductionCon, 
				m[:Lifecycle_Emissions_Lbs_CO2] >= 
				(1-p.s.site.CO2_emissions_reduction_max_fraction) * m[:Lifecycle_Emissions_Lbs_CO2_BAU]
			)
		end
	elseif !isnothing(p.s.site.CO2_emissions_reduction_min_fraction) || !isnothing(p.s.site.CO2_emissions_reduction_max_fraction)
		@warn "No emissions reduction constraints added, as BAU emissions have not been calculated."
	end
end


function add_yr1_emissions_calcs(m,p)
	# Components:
	m[:yr1_emissions_onsite_fuel_lbs_CO2], m[:yr1_emissions_onsite_fuel_lbs_NOx], 
	m[:yr1_emissions_onsite_fuel_lbs_SO2], m[:yr1_emissions_onsite_fuel_lbs_PM25] = 
		calc_yr1_emissions_from_onsite_fuel(m,p; tech_array=p.techs.fuel_burning)

	m[:yr1_emissions_from_elec_grid_lbs_CO2], m[:yr1_emissions_from_elec_grid_lbs_NOx], 
	m[:yr1_emissions_from_elec_grid_lbs_SO2], m[:yr1_emissions_from_elec_grid_lbs_PM25] = 
		calc_yr1_emissions_from_elec_grid_purchase(m, p)
	
	yr1_emissions_offset_from_elec_exports_lbs_CO2, 
	yr1_emissions_offset_from_elec_exports_lbs_NOx, 
	yr1_emissions_offset_from_elec_exports_lbs_SO2, 
	yr1_emissions_offset_from_elec_exports_lbs_PM25 = 
		calc_yr1_emissions_offset_from_elec_exports(m, p)
	
	m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_CO2] = (m[:yr1_emissions_from_elec_grid_lbs_CO2] - 
		yr1_emissions_offset_from_elec_exports_lbs_CO2)
	m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_NOx] = (m[:yr1_emissions_from_elec_grid_lbs_NOx] - 
		yr1_emissions_offset_from_elec_exports_lbs_NOx)
	m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_SO2] = (m[:yr1_emissions_from_elec_grid_lbs_SO2] - 
		yr1_emissions_offset_from_elec_exports_lbs_SO2)
	m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_PM25] = (m[:yr1_emissions_from_elec_grid_lbs_PM25] - 
		yr1_emissions_offset_from_elec_exports_lbs_PM25)

	m[:EmissionsYr1_Total_LbsCO2] = m[:yr1_emissions_onsite_fuel_lbs_CO2] + m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_CO2]
	m[:EmissionsYr1_Total_LbsNOx] = m[:yr1_emissions_onsite_fuel_lbs_NOx] + m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_NOx]
	m[:EmissionsYr1_Total_LbsSO2] = m[:yr1_emissions_onsite_fuel_lbs_SO2] + m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_SO2]
	m[:EmissionsYr1_Total_LbsPM25] = m[:yr1_emissions_onsite_fuel_lbs_PM25] + m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_PM25]
	nothing
end

"""
	calc_yr1_emissions_from_onsite_fuel(m,p; tech_array=p.techs.fuel_burning)

Function to calculate annual emissions from onsite fuel consumption.

!!! note
    When a single outage is modeled (using outage_start_time_step), emissions calculations 
    account for operations during this outage (e.g., the critical load is used during 
    time_steps_without_grid). On the contrary, when multiple outages are modeled (using 
    outage_start_time_steps), emissions calculations reflect normal operations, and do not 
	account for expected operations during modeled outages (time_steps_without_grid is empty)
"""
function calc_yr1_emissions_from_onsite_fuel(m,p; tech_array=p.techs.fuel_burning) # also run this with p.techs.boiler
	# Capacity-limited dual-fuel CHPs blend fuel 1 and fuel 2 within year 1 itself (dvFuelUsageFuel1 +
	# dvFuelUsageFuel2), so they need their own emissions-factor-weighted terms rather than the single
	# tech_emissions_factors_* factor used for every other fuel-burning tech.
	dual_fuel_chps = intersect(tech_array, chp_names_with_capacity_limited_dual_fuel(p))
	single_factor_tech_array = setdiff(tech_array, dual_fuel_chps)

	yr1_emissions_onsite_fuel_lbs_CO2 = @expression(m,p.hours_per_time_step*
		sum(m[:dvFuelUsage][t,ts]*p.tech_emissions_factors_CO2[t] for t in single_factor_tech_array, ts in p.time_steps))

	yr1_emissions_onsite_fuel_lbs_NOx = @expression(m,p.hours_per_time_step*
		sum(m[:dvFuelUsage][t,ts]*p.tech_emissions_factors_NOx[t] for t in single_factor_tech_array, ts in p.time_steps))

	yr1_emissions_onsite_fuel_lbs_SO2 = @expression(m,p.hours_per_time_step*
		sum(m[:dvFuelUsage][t,ts]*p.tech_emissions_factors_SO2[t] for t in single_factor_tech_array, ts in p.time_steps))

	yr1_emissions_onsite_fuel_lbs_PM25 = @expression(m,p.hours_per_time_step*
		sum(m[:dvFuelUsage][t,ts]*p.tech_emissions_factors_PM25[t] for t in single_factor_tech_array, ts in p.time_steps))

	for t in dual_fuel_chps
		chp = get_chp_by_name(t, p.s.chps)
		fuel2_factor_CO2 = chp.fuel2_emissions_factor_lb_CO2_per_mmbtu / KWH_PER_MMBTU
		fuel2_factor_NOx = chp.fuel2_emissions_factor_lb_NOx_per_mmbtu / KWH_PER_MMBTU
		fuel2_factor_SO2 = chp.fuel2_emissions_factor_lb_SO2_per_mmbtu / KWH_PER_MMBTU
		fuel2_factor_PM25 = chp.fuel2_emissions_factor_lb_PM25_per_mmbtu / KWH_PER_MMBTU

		yr1_emissions_onsite_fuel_lbs_CO2 += @expression(m, p.hours_per_time_step*sum(
			m[:dvFuelUsageFuel1][t,ts]*p.tech_emissions_factors_CO2[t] + m[:dvFuelUsageFuel2][t,ts]*fuel2_factor_CO2
			for ts in p.time_steps))
		yr1_emissions_onsite_fuel_lbs_NOx += @expression(m, p.hours_per_time_step*sum(
			m[:dvFuelUsageFuel1][t,ts]*p.tech_emissions_factors_NOx[t] + m[:dvFuelUsageFuel2][t,ts]*fuel2_factor_NOx
			for ts in p.time_steps))
		yr1_emissions_onsite_fuel_lbs_SO2 += @expression(m, p.hours_per_time_step*sum(
			m[:dvFuelUsageFuel1][t,ts]*p.tech_emissions_factors_SO2[t] + m[:dvFuelUsageFuel2][t,ts]*fuel2_factor_SO2
			for ts in p.time_steps))
		yr1_emissions_onsite_fuel_lbs_PM25 += @expression(m, p.hours_per_time_step*sum(
			m[:dvFuelUsageFuel1][t,ts]*p.tech_emissions_factors_PM25[t] + m[:dvFuelUsageFuel2][t,ts]*fuel2_factor_PM25
			for ts in p.time_steps))
	end

	return yr1_emissions_onsite_fuel_lbs_CO2,
		   yr1_emissions_onsite_fuel_lbs_NOx,
		   yr1_emissions_onsite_fuel_lbs_SO2,
		   yr1_emissions_onsite_fuel_lbs_PM25
end

"""
	calc_yr1_emissions_from_elec_grid_purchase(m,p)

Function to calculate annual emissions from grid electricity consumption.

!!! note
    When a single outage is modeled (using outage_start_time_step), emissions calculations 
    account for operations during this outage (e.g., the critical load is used during 
    time_steps_without_grid). On the contrary, when multiple outages are modeled (using 
    outage_start_time_steps), emissions calculations reflect normal operations, and do not 
	account for expected operations during modeled outages (time_steps_without_grid is empty)
"""
function calc_yr1_emissions_from_elec_grid_purchase(m,p)
	yr1_emissions_from_elec_grid_lbs_CO2 = @expression(m,p.hours_per_time_step*
		sum(m[:dvGridPurchase][ts, tier]*p.s.electric_utility.emissions_factor_series_lb_CO2_per_kwh[ts] for ts in p.time_steps, tier in 1:p.s.electric_tariff.n_energy_tiers))
		 
	yr1_emissions_from_elec_grid_lbs_NOx = @expression(m,p.hours_per_time_step*
		sum(m[:dvGridPurchase][ts, tier]*p.s.electric_utility.emissions_factor_series_lb_NOx_per_kwh[ts] for ts in p.time_steps, tier in 1:p.s.electric_tariff.n_energy_tiers))

	yr1_emissions_from_elec_grid_lbs_SO2 = @expression(m,p.hours_per_time_step*
		sum(m[:dvGridPurchase][ts, tier]*p.s.electric_utility.emissions_factor_series_lb_SO2_per_kwh[ts] for ts in p.time_steps, tier in 1:p.s.electric_tariff.n_energy_tiers))

	yr1_emissions_from_elec_grid_lbs_PM25 = @expression(m,p.hours_per_time_step*
		sum(m[:dvGridPurchase][ts, tier]*p.s.electric_utility.emissions_factor_series_lb_PM25_per_kwh[ts] for ts in p.time_steps, tier in 1:p.s.electric_tariff.n_energy_tiers))

	return yr1_emissions_from_elec_grid_lbs_CO2, 
		   yr1_emissions_from_elec_grid_lbs_NOx, 
		   yr1_emissions_from_elec_grid_lbs_SO2, 
		   yr1_emissions_from_elec_grid_lbs_PM25
end


function calc_yr1_emissions_offset_from_elec_exports(m, p)
	if !(p.s.site.include_exported_elec_emissions_in_total)
		return 0.0, 0.0, 0.0, 0.0
	end
	yr1_emissions_offset_from_elec_exports_lbs_CO2 = @expression(m, p.hours_per_time_step *
		sum( p.s.electric_utility.emissions_factor_series_lb_CO2_per_kwh[ts] * (
			sum(m[:dvProductionToGrid][t,u,ts] for t in p.techs.elec, u in p.export_bins_by_tech[t])
			+ sum(m[:dvStorageToGrid][b, u, ts] for b in p.s.storage.types.elec, u in p.export_bins_by_storage[b])
			) for ts in p.time_steps
		)
	)

	yr1_emissions_offset_from_elec_exports_lbs_NOx = @expression(m, p.hours_per_time_step *
		sum( p.s.electric_utility.emissions_factor_series_lb_NOx_per_kwh[ts] * (
			sum(m[:dvProductionToGrid][t,u,ts] for t in p.techs.elec, u in p.export_bins_by_tech[t])
			+ sum(m[:dvStorageToGrid][b, u, ts] for b in p.s.storage.types.elec, u in p.export_bins_by_storage[b])
			) for ts in p.time_steps
		)
	)

	yr1_emissions_offset_from_elec_exports_lbs_SO2 = @expression(m, p.hours_per_time_step *
		sum( p.s.electric_utility.emissions_factor_series_lb_SO2_per_kwh[ts] * (
			sum(m[:dvProductionToGrid][t,u,ts] for t in p.techs.elec, u in p.export_bins_by_tech[t])
			+ sum(m[:dvStorageToGrid][b, u, ts] for b in p.s.storage.types.elec, u in p.export_bins_by_storage[b])
			) for ts in p.time_steps
		)
	)

	yr1_emissions_offset_from_elec_exports_lbs_PM25 = @expression(m, p.hours_per_time_step *
		sum( p.s.electric_utility.emissions_factor_series_lb_PM25_per_kwh[ts] * (
			sum(m[:dvProductionToGrid][t,u,ts] for t in p.techs.elec, u in p.export_bins_by_tech[t])
			+ sum(m[:dvStorageToGrid][b, u, ts] for b in p.s.storage.types.elec, u in p.export_bins_by_storage[b])
			) for ts in p.time_steps
		)
	)

	return yr1_emissions_offset_from_elec_exports_lbs_CO2, 
		   yr1_emissions_offset_from_elec_exports_lbs_NOx, 
		   yr1_emissions_offset_from_elec_exports_lbs_SO2, 
		   yr1_emissions_offset_from_elec_exports_lbs_PM25
end


function add_lifecycle_emissions_calcs(m,p)

	# BAU Lifecycle lbs CO2
	if !isnothing(p.s.site.bau_grid_emissions_lb_CO2_per_year)
		m[:Lifecycle_Emissions_Lbs_CO2_BAU] = p.s.site.bau_grid_emissions_lb_CO2_per_year * p.pwf_grid_emissions["CO2"] + p.s.financial.analysis_years * (p.s.site.bau_emissions_lb_CO2_per_year - p.s.site.bau_grid_emissions_lb_CO2_per_year) # no annual decrease for on-site fuel burn
	end

	# Lifecycle lbs CO2
	m[:Lifecycle_Emissions_Lbs_CO2_grid_net_if_selected] = p.pwf_grid_emissions["CO2"] * m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_CO2]
	m[:Lifecycle_Emissions_Lbs_NOx_grid_net_if_selected] = p.pwf_grid_emissions["NOx"] * m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_NOx]
	m[:Lifecycle_Emissions_Lbs_SO2_grid_net_if_selected] = p.pwf_grid_emissions["SO2"] * m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_SO2]
	m[:Lifecycle_Emissions_Lbs_PM25_grid_net_if_selected] = p.pwf_grid_emissions["PM25"] * m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_PM25]

	m[:Lifecycle_Emissions_Lbs_CO2_fuelburn] = p.s.financial.analysis_years *  m[:yr1_emissions_onsite_fuel_lbs_CO2] # not assuming an annual decrease in on-site fuel burn emissions
	m[:Lifecycle_Emissions_Lbs_NOx_fuelburn] = p.s.financial.analysis_years *  m[:yr1_emissions_onsite_fuel_lbs_NOx] # not assuming an annual decrease in on-site fuel burn emissions
	m[:Lifecycle_Emissions_Lbs_SO2_fuelburn] = p.s.financial.analysis_years *  m[:yr1_emissions_onsite_fuel_lbs_SO2] # not assuming an annual decrease in on-site fuel burn emissions
	m[:Lifecycle_Emissions_Lbs_PM25_fuelburn] = p.s.financial.analysis_years *  m[:yr1_emissions_onsite_fuel_lbs_PM25] # not assuming an annual decrease in on-site fuel burn emissions

	m[:Lifecycle_Emissions_Lbs_CO2] = m[:Lifecycle_Emissions_Lbs_CO2_grid_net_if_selected] + m[:Lifecycle_Emissions_Lbs_CO2_fuelburn]
	m[:Lifecycle_Emissions_Lbs_NOx] = m[:Lifecycle_Emissions_Lbs_NOx_grid_net_if_selected] + m[:Lifecycle_Emissions_Lbs_NOx_fuelburn]
	m[:Lifecycle_Emissions_Lbs_SO2] = m[:Lifecycle_Emissions_Lbs_SO2_grid_net_if_selected] + m[:Lifecycle_Emissions_Lbs_SO2_fuelburn]
	m[:Lifecycle_Emissions_Lbs_PM25] = m[:Lifecycle_Emissions_Lbs_PM25_grid_net_if_selected] + m[:Lifecycle_Emissions_Lbs_PM25_fuelburn]

	# Emissions costs
	m[:Lifecycle_Emissions_Cost_CO2] = p.s.financial.CO2_cost_per_tonne * TONNE_PER_LB * ( 
		p.pwf_emissions_cost["CO2_grid"] * m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_CO2] + 
		p.pwf_emissions_cost["CO2_onsite"] * m[:yr1_emissions_onsite_fuel_lbs_CO2]
	)
	m[:Lifecycle_Emissions_Cost_NOx] = TONNE_PER_LB * (p.pwf_emissions_cost["NOx_grid"] * 
		p.s.financial.NOx_grid_cost_per_tonne * m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_NOx] + 
		p.pwf_emissions_cost["NOx_onsite"] * p.s.financial.NOx_onsite_fuelburn_cost_per_tonne * m[:yr1_emissions_onsite_fuel_lbs_NOx]
	) 
	m[:Lifecycle_Emissions_Cost_SO2] = TONNE_PER_LB * (p.pwf_emissions_cost["SO2_grid"] * 
		p.s.financial.SO2_grid_cost_per_tonne * m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_SO2] + 
		p.pwf_emissions_cost["SO2_onsite"] * p.s.financial.SO2_onsite_fuelburn_cost_per_tonne * m[:yr1_emissions_onsite_fuel_lbs_SO2]
	)
	m[:Lifecycle_Emissions_Cost_PM25] = TONNE_PER_LB * (p.pwf_emissions_cost["PM25_grid"] * 
		p.s.financial.PM25_grid_cost_per_tonne * m[:yr1_emissions_from_elec_grid_net_if_selected_lbs_PM25] + 
		p.pwf_emissions_cost["PM25_onsite"] * p.s.financial.PM25_onsite_fuelburn_cost_per_tonne * m[:yr1_emissions_onsite_fuel_lbs_PM25]
	)
	m[:Lifecycle_Emissions_Cost_Health] = m[:Lifecycle_Emissions_Cost_NOx] + m[:Lifecycle_Emissions_Cost_SO2] + m[:Lifecycle_Emissions_Cost_PM25]

	add_chp_fuel_switch_emissions_corrections(m, p)

	nothing
end

"""
    add_chp_fuel_switch_emissions_corrections(m, p)

The lifecycle emissions lbs/cost roll-ups above assume fuel 1's emissions factor and cost-escalation
apply for the entire analysis period, which is correct except for CHPs using the long-term fuel-switch
dual-fuel mode (`fuel2_switch_start_year` set). For each such CHP, replace its share of the uniform
`analysis_years * yr1` roll-up with the correct N-years-fuel-1 / N-years-fuel-2 split, using the same
year-1-repeating dispatch (`dvFuelUsage`) both before and after, consistent with how
`add_chp_fuel_switch_costs` (chp_dual_fuel_constraints.jl) handles CHP fuel cost.
"""
function add_chp_fuel_switch_emissions_corrections(m, p)
	switch_chps = chp_names_with_fuel_switch(p)
	isempty(switch_chps) && return nothing

	discount_rate = p.s.financial.offtaker_discount_rate_fraction
	# (onsite $/tonne field name, cost-escalation-rate field name) per pollutant
	cost_fields = Dict(
		"CO2" => (:CO2_cost_per_tonne, :CO2_cost_escalation_rate_fraction),
		"NOx" => (:NOx_onsite_fuelburn_cost_per_tonne, :NOx_cost_escalation_rate_fraction),
		"SO2" => (:SO2_onsite_fuelburn_cost_per_tonne, :SO2_cost_escalation_rate_fraction),
		"PM25" => (:PM25_onsite_fuelburn_cost_per_tonne, :PM25_cost_escalation_rate_fraction),
	)

	for t in switch_chps
		chp = get_chp_by_name(t, p.s.chps)
		n_fuel1_years, n_fuel2_years = chp_fuel_switch_year_counts(p, chp)
		n_fuel2_years <= 0 && continue  # fuel 2 never reached within the analysis period; base formula already correct

		for pollutant in ["CO2", "NOx", "SO2", "PM25"]
			yr1_fuel1, yr1_fuel2 = chp_fuel_switch_yr1_emissions_contributions(m, p, t, pollutant)

			lbs_key = Symbol("Lifecycle_Emissions_Lbs_$(pollutant)_fuelburn")
			m[lbs_key] = @expression(m, m[lbs_key] + n_fuel2_years * (yr1_fuel2 - yr1_fuel1))

			cost_per_tonne_field, escalation_field = cost_fields[pollutant]
			cost_per_tonne = getproperty(p.s.financial, cost_per_tonne_field)
			escalation_rate = getproperty(p.s.financial, escalation_field)
			pwf1, pwf2 = annuity_split_periods(n_fuel1_years, n_fuel2_years, escalation_rate, escalation_rate, discount_rate)
			base_pwf_onsite = p.pwf_emissions_cost["$(pollutant)_onsite"]

			cost_key = Symbol("Lifecycle_Emissions_Cost_$(pollutant)")
			m[cost_key] = @expression(m, m[cost_key] +
				TONNE_PER_LB * cost_per_tonne * (pwf1 * yr1_fuel1 + pwf2 * yr1_fuel2 - base_pwf_onsite * yr1_fuel1)
			)
		end
	end

	m[:Lifecycle_Emissions_Lbs_CO2] = m[:Lifecycle_Emissions_Lbs_CO2_grid_net_if_selected] + m[:Lifecycle_Emissions_Lbs_CO2_fuelburn]
	m[:Lifecycle_Emissions_Lbs_NOx] = m[:Lifecycle_Emissions_Lbs_NOx_grid_net_if_selected] + m[:Lifecycle_Emissions_Lbs_NOx_fuelburn]
	m[:Lifecycle_Emissions_Lbs_SO2] = m[:Lifecycle_Emissions_Lbs_SO2_grid_net_if_selected] + m[:Lifecycle_Emissions_Lbs_SO2_fuelburn]
	m[:Lifecycle_Emissions_Lbs_PM25] = m[:Lifecycle_Emissions_Lbs_PM25_grid_net_if_selected] + m[:Lifecycle_Emissions_Lbs_PM25_fuelburn]
	m[:Lifecycle_Emissions_Cost_Health] = m[:Lifecycle_Emissions_Cost_NOx] + m[:Lifecycle_Emissions_Cost_SO2] + m[:Lifecycle_Emissions_Cost_PM25]

	nothing
end