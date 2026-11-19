# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_fuel_burn_constraints(m,p; _n="")
	fuel_slope_gal_per_kwhe, fuel_intercept_gal_per_hr = fuel_slope_and_intercept(
		electric_efficiency_full_load=p.s.generator.electric_efficiency_full_load, 
		electric_efficiency_half_load=p.s.generator.electric_efficiency_half_load,
		fuel_higher_heating_value_kwh_per_unit=p.s.generator.fuel_higher_heating_value_kwh_per_gal
	)
  	@constraint(m, [t in p.techs.gen, ts in p.time_steps],
		m[Symbol("dvFuelUsage"*_n)][t, ts] == (fuel_slope_gal_per_kwhe * p.s.generator.fuel_higher_heating_value_kwh_per_gal *
		p.production_factor[t, ts] * p.hours_per_time_step * m[Symbol("dvRatedProduction"*_n)][t, ts]) +
		(fuel_intercept_gal_per_hr * p.s.generator.fuel_higher_heating_value_kwh_per_gal * p.hours_per_time_step * m[Symbol("binGenIsOnInTS"*_n)][t, ts])
	)
	@constraint(m,
		sum(m[Symbol("dvFuelUsage"*_n)][t, ts] for t in p.techs.gen, ts in p.time_steps) <=
		p.s.generator.fuel_avail_gal * p.s.generator.fuel_higher_heating_value_kwh_per_gal
	)
end


function add_binGenIsOnInTS_constraints(m,p; _n="")
	# Generator must be on for nonnegative output
	@constraint(m, [t in p.techs.gen, ts in p.time_steps],
		m[Symbol("dvRatedProduction"*_n)][t, ts] <= p.max_sizes[t] * m[Symbol("binGenIsOnInTS"*_n)][t, ts]
	)
	# Note: min_turn_down_fraction is only enforced when `off_grid_flag` is true and in p.time_steps_with_grid, but not for grid outages for on-grid analyses
	if p.s.settings.off_grid_flag 
		@constraint(m, [t in p.techs.gen, ts in p.time_steps_without_grid],
			p.s.generator.min_turn_down_fraction * m[Symbol("dvSize"*_n)][t] - m[Symbol("dvRatedProduction"*_n)][t, ts] <=
			p.max_sizes[t] * (1 - m[Symbol("binGenIsOnInTS"*_n)][t, ts])
		)
	else 
		@constraint(m, [t in p.techs.gen, ts in p.time_steps_with_grid],
			p.s.generator.min_turn_down_fraction * m[Symbol("dvSize"*_n)][t] - m[Symbol("dvRatedProduction"*_n)][t, ts] <=
			p.max_sizes[t] * (1 - m[Symbol("binGenIsOnInTS"*_n)][t, ts])
		)
	end 
end

function add_gen_can_run_constraints(m,p; _n="")
	if p.s.generator.only_runs_during_grid_outage
		for ts in p.time_steps_with_grid, t in p.techs.gen
			fix(m[Symbol("dvRatedProduction"*_n)][t, ts], 0.0, force=true)
		end
	end

	if !(p.s.generator.sells_energy_back_to_grid)
		for t in p.techs.gen, u in p.export_bins_by_tech[t], ts in p.time_steps
			fix(m[Symbol("dvProductionToGrid"*_n)][t, u, ts], 0.0, force=true)
		end
	end
end


function add_gen_rated_prod_constraint(m, p; _n="")
	@constraint(m, [t in p.techs.gen, ts in p.time_steps],
		m[Symbol("dvSize"*_n)][t] >= m[Symbol("dvRatedProduction"*_n)][t, ts]
	)
end

"""
    add_generator_hourly_om_charges(m, p; _n="")

- add decision variable "dvOMByHourBySizeGen" for the hourly Generator operations and maintenance costs
- add the cost expression "TotalHourlyGenOMCosts"
"""
function add_generator_hourly_om_charges(m, p; _n="")
    dv = "dvOMByHourBySizeGen"*_n
    m[Symbol(dv)] = @variable(m, [p.techs.gen, p.time_steps], base_name=dv, lower_bound=0)

    # Anonymous constraints are used so that each multinode node can add its own set without name conflicts
    #Constraint Generator-hourly-om-a: om per hour, per time step >= per_unit_size_cost * size for when on, >= zero when off
	@constraint(m, GeneratorHourlyOMBySizeA[t in p.techs.gen, ts in p.time_steps],
        p.s.generator.om_cost_per_hr_per_kw_rated * m[Symbol("dvSize"*_n)][t] -
        (p.s.generator.existing_kw + p.s.generator.max_kw) * p.s.generator.om_cost_per_hr_per_kw_rated * (1-m[Symbol("binGenIsOnInTS"*_n)][t,ts])
            <= m[Symbol(dv)][t, ts]
    )
	#Constraint Generator-hourly-om-b: om per hour, per time step <= per_unit_size_cost * size for each hour
	@constraint(m, GeneratorHourlyOMBySizeB[t in p.techs.gen, ts in p.time_steps],
        p.s.generator.om_cost_per_hr_per_kw_rated * m[Symbol("dvSize"*_n)][t]
            >= m[Symbol(dv)][t, ts]
    )
	#Constraint Generator-hourly-om-c: om per hour, per time step <= zero when off, <= per_unit_size_cost*max_size
	@constraint(m, GeneratorHourlyOMBySizeC[t in p.techs.gen, ts in p.time_steps],
        (p.s.generator.existing_kw + p.s.generator.max_kw) * p.s.generator.om_cost_per_hr_per_kw_rated * m[Symbol("binGenIsOnInTS"*_n)][t,ts]
            >= m[Symbol(dv)][t, ts]
    )
    
    m[Symbol("TotalHourlyGenOMCosts"*_n)] = @expression(m, p.third_party_factor * p.pwf_om * 
    	sum(m[Symbol(dv)][t, ts] * p.hours_per_time_step for t in p.techs.gen, ts in p.time_steps))
    nothing
end


"""
    add_gen_constraints(m, p; _n="")

Add Generator operational constraints and cost expressions.
"""
function add_gen_constraints(m, p; _n="")
    add_fuel_burn_constraints(m,p, _n=_n)
    add_binGenIsOnInTS_constraints(m,p, _n=_n)
    add_gen_can_run_constraints(m,p, _n=_n)
    add_gen_rated_prod_constraint(m,p, _n=_n)

	m[Symbol("TotalHourlyGenOMCosts"*_n)] = 0
	if p.s.generator.om_cost_per_hr_per_kw_rated > 1.0E-7
        add_generator_hourly_om_charges(m, p; _n=_n)
    end

    m[Symbol("TotalGenPerUnitProdOMCosts"*_n)] = @expression(m, p.third_party_factor * p.pwf_om *
        sum(p.s.generator.om_cost_per_kwh * p.hours_per_time_step *
        m[Symbol("dvRatedProduction"*_n)][t, ts] for t in p.techs.gen, ts in p.time_steps)
    )
    m[Symbol("TotalGenFuelCosts"*_n)] = @expression(m, 
		sum(p.pwf_fuel[t] * m[Symbol("dvFuelUsage"*_n)][t,ts] * p.fuel_cost_per_kwh[t][ts] for t in p.techs.gen, ts in p.time_steps) 
	)
end
