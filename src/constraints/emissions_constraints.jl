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
	yr1_emissions_onsite_fuel_lbs_CO2 = @expression(m,p.hours_per_time_step*
		sum(m[:dvFuelUsage][t,ts]*p.tech_emissions_factors_CO2[t] for t in tech_array, ts in p.time_steps))

	yr1_emissions_onsite_fuel_lbs_NOx = @expression(m,p.hours_per_time_step*
		sum(m[:dvFuelUsage][t,ts]*p.tech_emissions_factors_NOx[t] for t in tech_array, ts in p.time_steps))

	yr1_emissions_onsite_fuel_lbs_SO2 = @expression(m,p.hours_per_time_step*
		sum(m[:dvFuelUsage][t,ts]*p.tech_emissions_factors_SO2[t] for t in tech_array, ts in p.time_steps))

	yr1_emissions_onsite_fuel_lbs_PM25 = @expression(m,p.hours_per_time_step*
		sum(m[:dvFuelUsage][t,ts]*p.tech_emissions_factors_PM25[t] for t in tech_array, ts in p.time_steps))

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
		sum(m[:dvProductionToGrid][t,u,ts] * (p.s.electric_utility.emissions_factor_series_lb_CO2_per_kwh[ts])
		for t in p.techs.elec, ts in p.time_steps, u in p.export_bins_by_tech[t])
	)
		# if battery ends up being able to discharge to grid, need to incorporate here- might require complex tracking of what's charging battery

	yr1_emissions_offset_from_elec_exports_lbs_NOx = @expression(m, p.hours_per_time_step *
		sum(m[:dvProductionToGrid][t,u,ts] * (p.s.electric_utility.emissions_factor_series_lb_NOx_per_kwh[ts])
		for t in p.techs.elec, ts in p.time_steps, u in p.export_bins_by_tech[t])
	)

	yr1_emissions_offset_from_elec_exports_lbs_SO2 = @expression(m, p.hours_per_time_step *
		sum(m[:dvProductionToGrid][t,u,ts] * (p.s.electric_utility.emissions_factor_series_lb_SO2_per_kwh[ts])
		for t in p.techs.elec, ts in p.time_steps, u in p.export_bins_by_tech[t])
	)

	yr1_emissions_offset_from_elec_exports_lbs_PM25 = @expression(m, p.hours_per_time_step *
		sum(m[:dvProductionToGrid][t,u,ts] * (p.s.electric_utility.emissions_factor_series_lb_PM25_per_kwh[ts])
		for t in p.techs.elec, ts in p.time_steps, u in p.export_bins_by_tech[t])
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

	nothing
end