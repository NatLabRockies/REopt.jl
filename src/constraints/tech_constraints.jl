# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
function add_tech_size_constraints(m, p; _n="")

    # PV techs can be constrained by space available based on location at site (roof, ground, both)
    @constraint(m, [loc in p.pvlocations],
        sum(m[Symbol("dvSize"*_n)][t] * p.pv_to_location[t][loc] for t in p.techs.pv) <= p.maxsize_pv_locations[loc]
    )

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
    @constraint(m, [t in p.techs.no_turndown, ts in p.time_steps],
        m[Symbol("dvRatedProduction"*_n)][t,ts] == m[Symbol("dvSize"*_n)][t]
    )

	##Constraint (7e): SteamTurbine is not in techs.no_turndown OR techs.segmented, so handle electric production to dvSize constraint
    if !isempty(p.techs.steam_turbine)
        @constraint(m, [t in p.techs.steam_turbine, ts in p.time_steps],
            m[Symbol("dvRatedProduction"*_n)][t,ts]  <= m[:dvSize][t]
        )
    end  

    if !isempty(p.techs.electrolyzer)
        @constraint(m, [t in p.techs.electrolyzer, ts in p.time_steps],
            m[Symbol("dvRatedProduction"*_n)][t,ts]  <= m[:dvSize][t]
        )
    end  

    if !isempty(p.techs.compressor)
        @constraint(m, [t in p.techs.compressor, ts in p.time_steps],
            m[Symbol("dvRatedProduction"*_n)][t,ts]  <= m[:dvSize][t]
        )
    end
    
    if !isempty(p.techs.fuel_cell)
        @constraint(m, [t in p.techs.fuel_cell, ts in p.time_steps],
            m[Symbol("dvRatedProduction"*_n)][t,ts]  <= m[:dvSize][t]
        )
    end
end


function add_no_curtail_constraints(m, p; _n="")
    for t in p.techs.no_curtail
        for ts in p.time_steps
            fix(m[Symbol("dvCurtail"*_n)][t, ts] , 0.0, force=true)
        end
    end
end