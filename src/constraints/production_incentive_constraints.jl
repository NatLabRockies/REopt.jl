# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    add_prod_incent_vars_and_constraints(m, p)

When techs.pbi is not empty this function is called to add the variables and constraints for modeling production based
incentives.
"""
function add_prod_incent_vars_and_constraints(m, p)

    @variable(m, dvProdIncent[p.techs.pbi] >= 0)
    @variable(m, binProdIncent[p.techs.pbi], Bin)

	##Constraint (6a)-1: Production Incentive Upper Bound
	@constraint(m, ProdIncentUBCon[t in p.techs.pbi],
		m[:dvProdIncent][t] <= m[:binProdIncent][t] * p.pbi_max_benefit[t] * p.pbi_pwf[t] * p.third_party_factor)

	##Constraint (6a)-2: Production Incentive According to Production
	@constraint(m, IncentByProductionCon[t in p.techs.pbi],
		m[:dvProdIncent][t] <= p.hours_per_time_step * p.pbi_benefit_per_kwh[t] * p.pbi_pwf[t] * p.third_party_factor *
			sum(p.production_factor[t, ts] * m[:dvRatedProduction][t,ts] for ts in p.time_steps)
	)
	##Constraint (6b): System size max to achieve production incentive
	@constraint(m, IncentBySystemSizeCon[t in p.techs.pbi],
		m[:dvSize][t]  <= p.pbi_max_kw[t] + p.max_sizes[t] * (1 - m[:binProdIncent][t])
    )

	m[:TotalProductionIncentive] = @expression(m, sum(m[:dvProdIncent][t] for t in p.techs.pbi))
end
