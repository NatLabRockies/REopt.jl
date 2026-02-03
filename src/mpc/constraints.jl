# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_previous_monthly_peak_constraint(m::JuMP.AbstractModel, p::MPCInputs; _n="")
	## Constraint (11d): Monthly peak demand is >= demand at each time step in the month
	@constraint(m, [mth in p.months, ts in p.s.electric_tariff.time_steps_monthly[mth]],
    m[Symbol("dvPeakDemandMonth"*_n)][mth, 1] >= p.s.electric_tariff.monthly_previous_peak_demands[mth]
    )
end


function add_previous_tou_peak_constraint(m::JuMP.AbstractModel, p::MPCInputs; _n="")
    ## Constraint (12d): TOU peak demand is >= demand at each time step in the period` 
    @constraint(m, [r in p.ratchets],
        m[Symbol("dvPeakDemandTOU"*_n)][r, 1] >= p.s.electric_tariff.tou_previous_peak_demands[r]
    )
end


function add_grid_draw_limits(m::JuMP.AbstractModel, p::MPCInputs; _n="")
    @constraint(m, [ts in p.time_steps],
        sum(
            m[Symbol("dvGridPurchase"*_n)][ts, tier] 
            for tier in 1:p.s.electric_tariff.n_energy_tiers
        ) <= p.s.limits.grid_draw_limit_kw_by_time_step[ts]
    )
end


function add_export_limits(m::JuMP.AbstractModel, p::MPCInputs; _n="")
    @constraint(m, [ts in p.time_steps],
        sum(
            sum(m[Symbol("dvProductionToGrid"*_n)][t, u, ts] for u in p.export_bins_by_tech[t])
            for t in p.techs.elec
        ) <= p.s.limits.export_limit_kw_by_time_step[ts]
    )
end
