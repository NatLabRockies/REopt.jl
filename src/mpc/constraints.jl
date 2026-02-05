# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_previous_monthly_peak_constraint(m::JuMP.AbstractModel, p::MPCInputs; _n="")
	## Constraint (11d): Monthly peak demand is >= previous peak demand for each month
	@constraint(m, [s in 1:p.n_scenarios, mth in p.months, tier in 1:p.s.electric_tariff.n_monthly_demand_tiers],
    m[Symbol("dvPeakDemandMonth"*_n)][s, mth, tier] >= p.s.electric_tariff.monthly_previous_peak_demands[mth]
    )
end


function add_previous_tou_peak_constraint(m::JuMP.AbstractModel, p::MPCInputs; _n="")
    ## Constraint (12d): TOU peak demand is >= previous peak demand for each ratchet
    @constraint(m, [s in 1:p.n_scenarios, r in p.ratchets, tier in 1:p.s.electric_tariff.n_tou_demand_tiers],
        m[Symbol("dvPeakDemandTOU"*_n)][s, r, tier] >= p.s.electric_tariff.tou_previous_peak_demands[r]
    )
end


function add_grid_draw_limits(m::JuMP.AbstractModel, p::MPCInputs; _n="")
    @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
        sum(
            m[Symbol("dvGridPurchase"*_n)][s, ts, tier] 
            for tier in 1:p.s.electric_tariff.n_energy_tiers
        ) <= p.s.limits.grid_draw_limit_kw_by_time_step[ts]
    )
end


function add_export_limits(m::JuMP.AbstractModel, p::MPCInputs; _n="")
    @constraint(m, [s in 1:p.n_scenarios, ts in p.time_steps],
        sum(
            sum(m[Symbol("dvProductionToGrid"*_n)][s, t, u, ts] for u in p.export_bins_by_tech[t])
            for t in p.techs.elec
        ) <= p.s.limits.export_limit_kw_by_time_step[ts]
    )
end
