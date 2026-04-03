# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
	add_site_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict)

Adds the Site results to the dictionary passed back from `run_reopt` using the solved model `m` and the `REoptInputs`.

Site results:
- `annual_onsite_renewable_electricity_kwh` # renewable electricity from on-site renewable electricity-generating technologies (including fuel-burning technologies)
- `onsite_renewable_electricity_fraction_of_elec_load` # Portion of electricity consumption (incl. electric heating/cooling loads) that is derived from on-site renewable resource generation
- `onsite_and_grid_renewable_electricity_fraction_of_elec_load` # "Calculation is the same as onsite_renewable_electricity_fraction_of_elec_load, but additionally includes the renewable energy content of grid-purchased electricity, accounting for any battery efficiency losses
- `onsite_renewable_energy_fraction_of_total_load` # Portion of total annual energy consumption (including non-electric heating/cooling loads) that is derived from on-site renewable resource generation
- `onsite_and_grid_renewable_energy_fraction_of_total_load` # Calculation is the same as onsite_renewable_energy_fraction_of_total_load, but additionally includes the renewable energy content of grid-purchased electricity, accounting for any battery efficiency losses
- `annual_emissions_tonnes_CO2` # Average annual total tons of emissions associated with the site's grid-purchased electricity and on-site fuel consumption.
- `annual_emissions_tonnes_NOx` # Average annual total tons of emissions associated with the site's grid-purchased electricity and on-site fuel consumption.
- `annual_emissions_tonnes_SO2` # Average annual total tons of emissions associated with the site's grid-purchased electricity and on-site fuel consumption.
- `annual_emissions_tonnes_PM25` # Average annual total tons of emissions associated with the site's grid-purchased electricity and on-site fuel consumption.
- `annual_emissions_from_fuelburn_tonnes_CO2` # Average annual total tons of emissions associated with the site's on-site fuel consumption.
- `annual_emissions_from_fuelburn_tonnes_NOx`
- `annual_emissions_from_fuelburn_tonnes_SO2`
- `annual_emissions_from_fuelburn_tonnes_PM25`
- `lifecycle_emissions_tonnes_CO2` # Total tons of emissions associated with the site's grid-purchased electricity and on-site fuel consumption over the analysis horizon.
- `lifecycle_emissions_tonnes_NOx`
- `lifecycle_emissions_tonnes_SO2`
- `lifecycle_emissions_tonnes_PM25`
- `lifecycle_emissions_from_fuelburn_tonnes_CO2` # Total tons of emissions associated with the site's on-site fuel consumption over the analysis horizon.
- `lifecycle_emissions_from_fuelburn_tonnes_NOx`
- `lifecycle_emissions_from_fuelburn_tonnes_SO2`
- `lifecycle_emissions_from_fuelburn_tonnes_PM25`

calculated in combine_results function if BAU scenario is run:
- `lifecycle_emissions_reduction_CO2_fraction`

!!! note "'Series' and 'Annual' energy and emissions outputs are average annual"
	REopt performs load balances using average annual production values for technologies that include degradation. 
	Therefore, all timeseries (`_series`) and `annual_` results should be interpretted as energy and emissions outputs averaged over the analysis period. 

!!! note "Emissions outputs" 
    By default, REopt uses marginal emissions rates for grid-purchased electricity. Marginal emissions rates are most appropriate for reporting a change in emissions (avoided or increased) rather than emissions totals.
    It is therefore recommended that emissions results from REopt (using default marginal emissions rates) be reported as the difference in emissions between the optimized and BAU case.

"""
function add_site_results(m::JuMP.AbstractModel, p::REoptInputs, d::Dict; _n="")
	r = Dict{String, Any}()

	# renewable elec
	r["annual_onsite_renewable_electricity_kwh"] = round(value(m[:AnnualOnsiteREEleckWh]), digits=2)
	r["onsite_renewable_electricity_fraction_of_elec_load"] = round(value(m[:AnnualOnsiteREEleckWh])/value(m[:AnnualEleckWh]), digits=4)
	r["onsite_and_grid_renewable_electricity_fraction_of_elec_load"] = round((value(m[:AnnualOnsiteREEleckWh]) + value(m[:AnnualGridREEleckWh])) /value(m[:AnnualEleckWh]), digits=4)
	
	# total renewable energy
	add_re_tot_calcs(m,p)
	r["onsite_renewable_energy_fraction_of_total_load"] = round(value(m[:AnnualOnsiteRETotkWh])/value(m[:AnnualTotkWh]), digits=4)
	r["onsite_and_grid_renewable_energy_fraction_of_total_load"] = round((value(m[:AnnualOnsiteRETotkWh]) + value(m[:AnnualGridREEleckWh]))/value(m[:AnnualTotkWh]), digits=4)

	# Lifecycle emissions results at Site level
	if !isnothing(p.s.site.bau_emissions_lb_CO2_per_year)
		r["lifecycle_emissions_reduction_CO2_fraction"] = round(value(1-m[:Lifecycle_Emissions_Lbs_CO2]/m[:Lifecycle_Emissions_Lbs_CO2_BAU]), digits=6)
	end
	r["lifecycle_emissions_tonnes_CO2"] = round(value(m[:Lifecycle_Emissions_Lbs_CO2]*TONNE_PER_LB), digits=2)
	r["lifecycle_emissions_tonnes_NOx"] = round(value(m[:Lifecycle_Emissions_Lbs_NOx]*TONNE_PER_LB), digits=2)
	r["lifecycle_emissions_tonnes_SO2"] = round(value(m[:Lifecycle_Emissions_Lbs_SO2]*TONNE_PER_LB), digits=2)
	r["lifecycle_emissions_tonnes_PM25"] = round(value(m[:Lifecycle_Emissions_Lbs_PM25]*TONNE_PER_LB), digits=2)

	r["lifecycle_emissions_from_fuelburn_tonnes_CO2"] = round(value(m[:Lifecycle_Emissions_Lbs_CO2_fuelburn]*TONNE_PER_LB), digits=2)
	r["lifecycle_emissions_from_fuelburn_tonnes_NOx"] = round(value(m[:Lifecycle_Emissions_Lbs_NOx_fuelburn]*TONNE_PER_LB), digits=2)
	r["lifecycle_emissions_from_fuelburn_tonnes_SO2"] = round(value(m[:Lifecycle_Emissions_Lbs_SO2_fuelburn]*TONNE_PER_LB), digits=2)
	r["lifecycle_emissions_from_fuelburn_tonnes_PM25"] = round(value(m[:Lifecycle_Emissions_Lbs_PM25_fuelburn]*TONNE_PER_LB), digits=2)

	# Simple Average Annual Emissions results at Site level (total divided by analysis period)
	for em in ["CO2", "NOx", "SO2", "PM25"]
		r["annual_emissions_tonnes_$(em)"] = r["lifecycle_emissions_tonnes_$(em)"] / p.s.financial.analysis_years
		r["annual_emissions_from_fuelburn_tonnes_$(em)"] = r["lifecycle_emissions_from_fuelburn_tonnes_$(em)"] / p.s.financial.analysis_years
	end
	
	d["Site"] = r
end

"""
	add_re_tot_calcs(m::JuMP.AbstractModel, p::REoptInputs)

Function to calculate annual energy (electricity plus heat) demand and annual energy demand derived from renewable energy.

!!! note
    When a single outage is modeled (using outage_start(/end)_time_step), renewable electricity calculations account for operations during this outage (e.g., the critical load is used during time_steps_without_grid)
	On the contrary, when multiple outages are modeled (using outage_start_time_steps, etc.), renewable electricity calculations reflect normal operations, and do not account for expected operations during modeled outages (time_steps_without_grid is empty)
"""
#Renewable heat calculations and totalling heat/electric emissions
function add_re_tot_calcs(m::JuMP.AbstractModel, p::REoptInputs)
 
	if !isempty(intersect(p.techs.fuel_burning, union(p.techs.heating, p.techs.chp)))
		# TODO: When steam turbine implemented, uncomment code below, replacing p.TechCanSupplySteamTurbine, p.STElecOutToThermInRatio, p.STThermOutToThermInRatio with new names
		# # Steam turbine RE heat calculations
		# if isempty(p.steam)
		# 	AnnualSteamTurbineREThermOut = 0 
		# 	AnnualRESteamToSteamTurbine = 0
		# 	AnnualSteamToSteamTurbine = 0
		# else  
		# 	# Note: SteamTurbine's input p.tech_renewable_energy_fraction = 0 because it is actually a decision variable dependent on fraction of steam generated by RE fuel
		# 	# SteamTurbine RE battery losses, RE curtailment, and exported RE terms are based on an approximation of percent RE because the general equation is nonlinear
		# 	# Thus, SteamTurbine %RE is only accurate if all techs that can supply ST have equal %RE fuel or provide equal quantities of steam to the steam turbine
		# 	SteamTurbinePercentREEstimate = @expression(m,
		# 		sum(p.tech_renewable_energy_fraction[tst] for tst in p.TechCanSupplySteamTurbine) / length(p.TechCanSupplySteamTurbine)
		# 	)
		# 	AnnualSteamTurbineREThermOut = @expression(m,p.hours_per_time_step *
		# 		p.STThermOutToThermInRatio * sum(m[:dvThermalToSteamTurbine][tst,ts]*p.tech_renewable_energy_fraction[tst] for ts in p.time_steps, tst in p.TechCanSupplySteamTurbine) # plus steam turbine RE generation 
		# 		- sum(m[:dvProductionToStorage][b,t,ts] * SteamTurbinePercentREEstimate * (1-p.s.storage.attr[b].charge_efficiency*p.s.storage.attr[b].discharge_efficiency) for t in p.steam, b in p.s.storage.types.thermal, ts in p.time_steps) # minus battery storage losses from RE heat from steam turbine; note does not account for p.DecayRate
		# 	)
		# 	AnnualRESteamToSteamTurbine = @expression(m,p.hours_per_time_step *
		# 		sum(m[:dvThermalToSteamTurbine][tst,ts]*p.tech_renewable_energy_fraction[tst] for ts in p.time_steps, tst in p.TechCanSupplySteamTurbine) # steam to steam turbine from other techs- need to subtract this out from the total 	
		# 	)
		# 	AnnualSteamToSteamTurbine = @expression(m,p.hours_per_time_step *
		# 		sum(m[:dvThermalToSteamTurbine][tst,ts] for ts in p.time_steps, tst in p.TechCanSupplySteamTurbine) # steam to steam turbine from other techs- need to subtract this out from the total
		# 	)
		# end

		#To account for hot storage losses and the RE contributions from fuel-fired sources when calculating end-use load, these expressions are used.
		m[:AnnualHeatContributionToStorage] = @expression(m, sum(m[:dvProductionToStorage][b,t,ts] for t in union(p.techs.heating, p.techs.chp), b in p.s.storage.types.hot, ts in p.time_steps))
		m[:AnnualREFBToHotStoragekWh] = @expression(m, sum(m[:dvProductionToStorage][b,t,ts]*p.tech_renewable_energy_fraction[t] for t in intersect(p.techs.fuel_burning, union(p.techs.heating, p.techs.chp)), b in p.s.storage.types.hot, ts in p.time_steps))
		m[:AnnualFBToHotStoragekWh] = @expression(m, sum(m[:dvProductionToStorage][b,t,ts] for t in intersect(p.techs.fuel_burning, union(p.techs.heating, p.techs.chp)), b in p.s.storage.types.hot, ts in p.time_steps))
		if value(m[:AnnualFBToHotStoragekWh]) > 0.0
			m[:FBStorageDeliveryREFraction] = @expression(m, m[:AnnualREFBToHotStoragekWh] / m[:AnnualFBToHotStoragekWh])
		else
			m[:FBStorageDeliveryREFraction] = @expression(m, 0.0)
		end
		m[:AnnualHotStorageLosses] = @expression(m, m[:AnnualFBToHotStoragekWh] - sum(m[:dvDischargeFromStorage][b, ts]  for b in p.s.storage.types.hot, ts in p.time_steps))
		if value(m[:AnnualHeatContributionToStorage]) > 0.0
			m[:FBToHotStorageFraction] = @expression(m, m[:AnnualFBToHotStoragekWh] / m[:AnnualHeatContributionToStorage])
		else
			m[:FBToHotStorageFraction] = @expression(m, 0.0)
		end
		# End-use consumed heating load from renewable, fuel-fired sources (electrified heat is addressed in the renewable electricity calculation)
		m[:AnnualREHeatkWh] = @expression(m,p.hours_per_time_step*(
				sum(m[:dvHeatingProduction][t,q,ts] * p.tech_renewable_energy_fraction[t] for t in intersect(p.techs.fuel_burning, union(p.techs.heating, p.techs.chp)), q in p.heating_loads, ts in p.time_steps) #total RE end-use heat generation from fuel sources
				- sum(m[:dvProductionToWaste][t,q,ts]* p.tech_renewable_energy_fraction[t] for t in intersect(p.techs.fuel_burning, union(p.techs.heating, p.techs.chp)), q in p.heating_loads, ts in p.time_steps) #minus waste heat
				- m[:FBStorageDeliveryREFraction] * m[:FBToHotStorageFraction] * m[:AnnualHotStorageLosses] # RE weight times hot storage loss attributable to FB techs
			)
			# - AnnualRESteamToSteamTurbine # minus RE steam feeding steam turbine, adjusted by p.hours_per_time_step 
			# + AnnualSteamTurbineREThermOut #plus steam turbine RE generation, adjusted for storage losses, adjusted by p.hours_per_time_step (not included in first line because p.tech_renewable_energy_fraction for SteamTurbine is 0)
		)

		# End-use consumed heating load from fuel-fired sources (electrified heat is addressed in the renewable electricity calculation)
		m[:AnnualHeatkWh] = @expression(m,p.hours_per_time_step*(
				sum(m[:dvHeatingProduction][t,q,ts] for t in intersect(p.techs.fuel_burning, union(p.techs.heating, p.techs.chp)), q in p.heating_loads, ts in p.time_steps) #total end-use heat generation from fuel sources
				- sum(m[:dvProductionToWaste][t,q,ts] for t in intersect(p.techs.fuel_burning, union(p.techs.heating, p.techs.chp)), q in p.heating_loads, ts in p.time_steps) #minus waste heat
				- m[:FBToHotStorageFraction] * m[:AnnualHotStorageLosses] # hot storage loss attributable to FB techs
			)
			# - AnnualSteamToSteamTurbine # minus steam going to SteamTurbine; already adjusted by p.hours_per_time_step
		)
	else
		m[:AnnualREHeatkWh] = @expression(m, 0.0) 
		m[:AnnualHeatkWh] = @expression(m, 0.0) 
	end 
	m[:AnnualOnsiteRETotkWh] = @expression(m, m[:AnnualOnsiteREEleckWh] + m[:AnnualREHeatkWh])
	m[:AnnualTotkWh] = @expression(m, m[:AnnualEleckWh] + m[:AnnualHeatkWh]) 
	nothing
end
