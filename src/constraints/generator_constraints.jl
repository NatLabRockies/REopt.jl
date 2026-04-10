# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_fuel_burn_constraints(m,p)
	fuel_slope_gal_per_kwhe, fuel_intercept_gal_per_hr = fuel_slope_and_intercept(
		electric_efficiency_full_load=p.s.generator.electric_efficiency_full_load, 
		electric_efficiency_half_load=p.s.generator.electric_efficiency_half_load,
		fuel_higher_heating_value_kwh_per_unit=p.s.generator.fuel_higher_heating_value_kwh_per_gal
	)
  	@constraint(m, [t in p.techs.gen, ts in p.time_steps],
		m[:dvFuelUsage][t, ts] == (fuel_slope_gal_per_kwhe * p.s.generator.fuel_higher_heating_value_kwh_per_gal *
		p.production_factor[t, ts] * p.hours_per_time_step * m[:dvRatedProduction][t, ts]) +
		(fuel_intercept_gal_per_hr * p.s.generator.fuel_higher_heating_value_kwh_per_gal * p.hours_per_time_step * m[:binGenIsOnInTS][t, ts])
	)
	@constraint(m,
		sum(m[:dvFuelUsage][t, ts] for t in p.techs.gen, ts in p.time_steps) <=
		p.s.generator.fuel_avail_gal * p.s.generator.fuel_higher_heating_value_kwh_per_gal
	)
end


function add_binGenIsOnInTS_constraints(m,p)
	# Generator must be on for nonnegative output
	@constraint(m, [t in p.techs.gen, ts in p.time_steps],
		m[:dvRatedProduction][t, ts] <= p.max_sizes[t] * m[:binGenIsOnInTS][t, ts]
	)
	# Note: min_turn_down_fraction is only enforced when `off_grid_flag` is true and in p.time_steps_with_grid, but not for grid outages for on-grid analyses
	if p.s.settings.off_grid_flag 
		@constraint(m, [t in p.techs.gen, ts in p.time_steps_without_grid],
			p.s.generator.min_turn_down_fraction * m[:dvSize][t] - m[:dvRatedProduction][t, ts] <=
			p.max_sizes[t] * (1 - m[:binGenIsOnInTS][t, ts])
		)
	else 
		@constraint(m, [t in p.techs.gen, ts in p.time_steps_with_grid],
			p.s.generator.min_turn_down_fraction * m[:dvSize][t] - m[:dvRatedProduction][t, ts] <=
			p.max_sizes[t] * (1 - m[:binGenIsOnInTS][t, ts])
		)
	end 
end

function add_gen_can_run_constraints(m,p)
	if p.s.generator.only_runs_during_grid_outage
		for ts in p.time_steps_with_grid, t in p.techs.gen
			fix(m[:dvRatedProduction][t, ts], 0.0, force=true)
		end
	end

	if !(p.s.generator.sells_energy_back_to_grid)
		for t in p.techs.gen, u in p.export_bins_by_tech[t], ts in p.time_steps
			fix(m[:dvProductionToGrid][t, u, ts], 0.0, force=true)
		end
	end
end


function add_gen_rated_prod_constraint(m, p)
	@constraint(m, [t in p.techs.gen, ts in p.time_steps],
		m[:dvSize][t] >= m[:dvRatedProduction][t, ts]
	)
end

"""
    add_generator_hourly_om_charges(m, p)

- add decision variable "dvOMByHourBySizeGen" for the hourly Generator operations and maintenance costs
- add the cost to TotalPerUnitHourOMCosts
"""
function add_generator_hourly_om_charges(m, p)
    dv = "dvOMByHourBySizeGen"
    m[Symbol(dv)] = @variable(m, [p.techs.gen, p.time_steps], base_name=dv, lower_bound=0)

	println(p.s.generator.max_kw)

    #Constraint Generator-hourly-om-a: om per hour, per time step >= per_unit_size_cost * size for when on, >= zero when off
	@constraint(m, GeneratorHourlyOMBySizeA[t in p.techs.gen, ts in p.time_steps],
        p.s.generator.om_cost_per_hr_per_kw_rated * m[Symbol("dvSize")][t] -
        (p.s.generator.existing_kw + p.s.generator.max_kw) * p.s.generator.om_cost_per_hr_per_kw_rated * (1-m[Symbol("binGenIsOnInTS")][t,ts])
            <= m[Symbol("dvOMByHourBySizeGen")][t, ts]
    )
	#Constraint Generator-hourly-om-b: om per hour, per time step <= per_unit_size_cost * size for each hour
	@constraint(m, GeneratorHourlyOMBySizeB[t in p.techs.gen, ts in p.time_steps],
        p.s.generator.om_cost_per_hr_per_kw_rated * m[Symbol("dvSize")][t]
            >= m[Symbol("dvOMByHourBySizeGen")][t, ts]
    )
	#Constraint Generator-hourly-om-c: om per hour, per time step <= zero when off, <= per_unit_size_cost*max_size
	@constraint(m, GeneratorHourlyOMBySizeC[t in p.techs.gen, ts in p.time_steps],
        (p.s.generator.existing_kw + p.s.generator.max_kw) * p.s.generator.om_cost_per_hr_per_kw_rated * m[Symbol("binGenIsOnInTS")][t,ts]
            >= m[Symbol("dvOMByHourBySizeGen")][t, ts]
    )
    
    m[:TotalHourlyGenOMCosts] = @expression(m, p.third_party_factor * p.pwf_om * 
    	sum(m[Symbol(dv)][t, ts] * p.hours_per_time_step for t in p.techs.gen, ts in p.time_steps))
    nothing
end


"""
    add_gen_constraints(m, p)

Add Generator operational constraints and cost expressions.
"""
function add_gen_constraints(m, p)
    add_fuel_burn_constraints(m,p)
    add_binGenIsOnInTS_constraints(m,p)
    add_gen_can_run_constraints(m,p)
    add_gen_rated_prod_constraint(m,p)

	m[:TotalHourlyGenOMCosts] = 0
	if p.s.generator.om_cost_per_hr_per_kw_rated > 1.0E-7
        add_generator_hourly_om_charges(m, p)
    end

    m[:TotalGenPerUnitProdOMCosts] = @expression(m, p.third_party_factor * p.pwf_om *
        sum(p.s.generator.om_cost_per_kwh * p.hours_per_time_step *
        m[:dvRatedProduction][t, ts] for t in p.techs.gen, ts in p.time_steps)
    )
    m[:TotalGenFuelCosts] = @expression(m,
        sum(p.pwf_fuel[t] * m[:dvFuelUsage][t,ts] * p.fuel_cost_per_kwh[t][ts] for t in p.techs.gen, ts in p.time_steps)
    )
end
