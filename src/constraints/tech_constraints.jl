# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_tech_size_constraints(m, p; _n="")

    # PV techs can be constrained by space available based on location at site (roof, ground, both)
    @constraint(m, [loc in p.pvlocations],
        sum(m[Symbol("dvSize"*_n)][t] * p.pv_to_location[t][loc] for t in p.techs.pv) <= p.maxsize_pv_locations[loc]
    )
    
    # if !isempty(p.s.pvs)
    #     varname = "dvGroundUse"*_n
    #     m[Symbol(dv)] = @variable(m, [t in union(p.techs.pv, p.techs.cst)], base_name=dv)
    #     for pv in p.s.pvs
    #         if p.pv_to_location[t][:both]
    #             @constraint(m,  >=  - )
    #         elseif 
    #             @constraint(m, >= )
    #         end
    #     end
    # end


    #Site ground limit for PV and CSP combined; PV max size handled separately if this isn't present
    if "CST" in p.techs.all
        if !isempty(p.s.pvs)
            @constraint(m, LandConstraint,
                sum(pv.acres_per_kw * (p.pv_to_location[pv.name][:ground] + p.pv_to_location[pv.name][:both]) * m[Symbol("dvSize"*_n)][pv.name] for pv in p.s.pvs) 
                    + p.s.cst.acres_per_kw * m[Symbol("dvSize"*_n)]["CST"] <= p.s.site.land_acres
            )
        else
            @constraint(m, LandConstraint,
                p.s.cst.acres_per_kw * m[Symbol("dvSize"*_n)]["CST"] <= p.s.site.land_acres
            )
        end
    end

    # max size limit
    @constraint(m, [t in p.techs.all],
        m[Symbol("dvSize"*_n)][t] <= p.max_sizes[t]
    )

    ##Constraint (7c): Minimum size for each tech
    @constraint(m, [t in p.techs.all],
        m[Symbol("dvSize"*_n)][t] >= p.min_sizes[t]
    )

    @constraint(m, [t in p.techs.all],
        m[Symbol("dvPurchaseSize"*_n)][t] >= m[Symbol("dvSize"*_n)][t] - p.existing_sizes[t]
    )

    ## Constraint (7d): Non-turndown technologies are always at rated production
    @constraint(m, [s in 1:p.n_scenarios, t in p.techs.no_turndown, ts in p.time_steps],
        m[Symbol("dvRatedProduction"*_n)][s, t,ts] == m[Symbol("dvSize"*_n)][t]
    )

	##Constraint (7e): SteamTurbine is not in techs.no_turndown OR techs.segmented, so handle electric production to dvSize constraint
    if !isempty(p.techs.steam_turbine)
        @constraint(m, [s in 1:p.n_scenarios, t in p.techs.steam_turbine, ts in p.time_steps],
            m[Symbol("dvRatedProduction"*_n)][s, t,ts]  <= m[:dvSize][t]
        )
    end  
end


function add_no_curtail_constraints(m, p; _n="")
    for s in 1:p.n_scenarios, t in p.techs.no_curtail, ts in p.time_steps
        fix(m[Symbol("dvCurtail"*_n)][s, t, ts] , 0.0, force=true)
    end
end
