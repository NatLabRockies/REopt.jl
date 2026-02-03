# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
slope(x1, y1, x2, y2) = (y2 - y1) / (x2 - x1)


intercept(x1, y1, x2, y2) = y2 - slope(x1, y1, x2, y2) * x2

function insert_u_bp(xp_array_incent, yp_array_incent, region, u_xbp, u_ybp, p, u_cap)
    push!(xp_array_incent[region], u_xbp)
    push!(yp_array_incent[region], u_ybp - u_ybp * p + u_cap)
    return xp_array_incent, yp_array_incent
end


function insert_p_bp(xp_array_incent, yp_array_incent, region, p_xbp, p_ybp, u, p_cap)
    push!(xp_array_incent[region], p_xbp)
    push!(yp_array_incent[region], p_ybp - (p_cap + p_xbp * u))
    return xp_array_incent, yp_array_incent
end


function insert_u_after_p_bp(xp_array_incent, yp_array_incent, region, u_xbp, u_ybp, p, p_cap, u_cap)
    push!(xp_array_incent[region], u_xbp)
    if p_cap == 0
        push!(yp_array_incent[region], u_ybp - (p * u_ybp + u_cap))
    else
        push!(yp_array_incent[region], u_ybp - (p_cap + u_cap))
    end
    return xp_array_incent, yp_array_incent
end


function insert_p_after_u_bp(xp_array_incent, yp_array_incent, region, p_xbp, p_ybp, u, u_cap, p_cap)
    push!(xp_array_incent[region], p_xbp)
    if u_cap == 0
        push!(yp_array_incent[region], p_ybp - (p_cap + u * p_xbp))
    else
        push!(yp_array_incent[region], p_ybp - (p_cap + u_cap))
    end
    return xp_array_incent, yp_array_incent
end


"""
    cost_curve(tech::AbstractTech, financial::Financial)

Determine the cost curve segments (x and y points) accounting for:
    1. tax incentives
    2. rebates
    3. (size, cost) samples

Assumes that `tech` has the following attributes:
- installed_cost_per_kw
- federal_itc_fraction
- federal_rebate_per_kw
- state_ibi_fraction
- state_ibi_max
- state_rebate_per_kw
- state_rebate_max
- utility_ibi_fraction
- utility_ibi_max
- utility_rebate_per_kw
- utility_rebate_max
- macrs_option_years
- macrs_bonus_fraction
- macrs_itc_reduction

Optional attributes of `tech` are:
- existing_kw
- tech_sizes_for_cost_curve
"""
function cost_curve(tech::AbstractTech, financial::Financial)
    big_number = 1.0e10
    T = typeof(tech)

    regions = ["utility", "state", "federal", "combined"]
    cap_cost_slope = Real[]
    cost_curve_bp_x = [0.0]
    cost_curve_bp_y = [0.0]
    cap_cost_yint = Real[]
    n_segments = 1

    existing_kw = 0.0
    if :existing_kw in fieldnames(T)
        existing_kw = tech.existing_kw
    end

    tech_incentives = Dict(
        "federal" => Dict(),
        "state" => Dict(),
        "utility" => Dict(),
    )
    if nameof(T) in [:Generator, :Absorpchl]  # for generator and absorption chiller, there are no incentives
        for region in keys(tech_incentives)
            tech_incentives[region]["%"] = 0.0
            tech_incentives[region]["%_max"] = 0.0
            tech_incentives[region]["rebate"] = 0.0
            tech_incentives[region]["rebate_max"] = 0.0
        end
    else
        # NOTE REopt incentive calculation works best if "unlimited" incentives are entered as 0
        tech_incentives["federal"]["%"] = tech.federal_itc_fraction
        tech_incentives["federal"]["%_max"] = 0
        tech_incentives["state"]["%"] = tech.state_ibi_fraction
        tech_incentives["state"]["%_max"] = tech.state_ibi_max ==  big_number ? 0 : tech.state_ibi_max
        tech_incentives["utility"]["%"] = tech.utility_ibi_fraction
        tech_incentives["utility"]["%_max"] = tech.utility_ibi_max == big_number ? 0 : tech.utility_ibi_max

        tech_incentives["federal"]["rebate"] = tech.federal_rebate_per_kw
        tech_incentives["federal"]["rebate_max"] = 0
        tech_incentives["state"]["rebate"] = tech.state_rebate_per_kw
        tech_incentives["state"]["rebate_max"] = tech.state_rebate_max ==  big_number ? 0 : tech.state_rebate_max
        tech_incentives["utility"]["rebate"] = tech.utility_rebate_per_kw
        tech_incentives["utility"]["rebate_max"] = tech.utility_rebate_max  ==  big_number ? 0 : tech.utility_rebate_max
    end

    # Intermediate Cost curve
    xp_array_incent = Dict("utility" => [0.0, big_number])
    yp_array_incent = Dict("utility" => [0.0, big_number * tech.installed_cost_per_kw])  # [$]

    # New input of tech_sizes_for_cost_curve to be associated with tech.installed_cost_per_kw with same type and length
    if :tech_sizes_for_cost_curve in fieldnames(T)
        if !isempty(tech.tech_sizes_for_cost_curve)
            if length(tech.tech_sizes_for_cost_curve) == 1
                yp_array_incent["utility"] = [0.0, big_number * tech.installed_cost_per_kw[1]]  # [$]
            else  # length(tech.tech_sizes_for_cost_curve) > 1
                xp_array_incent["utility"] = []
                if tech.tech_sizes_for_cost_curve[1] != 0 # Append a 0 to the front of the list if not included (we"ll assume that it has a 0 y-intercept below)
                    push!(xp_array_incent["utility"], 0)
                end
                push!(xp_array_incent["utility"], tech.tech_sizes_for_cost_curve...)  # [$]  # Append list of sizes for cost curve [kW]
                if tech.tech_sizes_for_cost_curve[end] <= (big_number - 1.0)  # Avoid redundant append of a big number if the last size is basically big_number
                    push!(xp_array_incent["utility"], big_number)  # Append big number size to assume same cost as last input point
                end

                if tech.tech_sizes_for_cost_curve[1] == 0
                    yp_array_incent["utility"] = [tech.installed_cost_per_kw[1], tech.tech_sizes_for_cost_curve[2:end] .* tech.installed_cost_per_kw[2:end]...]  # [$]
                    # tech.installed_cost_per_kw[1] is assumed to be in units of $, if there is tech.tech_sizes_for_cost_curve[1]=0 point
                else
                    yp_array_incent["utility"] = [0, tech.tech_sizes_for_cost_curve .* tech.installed_cost_per_kw...]
                end
                append!(yp_array_incent["utility"], big_number * tech.installed_cost_per_kw[end])  # Last cost assumed for big_number size
                cost_curve_bp_y = [yp_array_incent["utility"][1]]
            end
        end
    end

    for r in range(1, stop=length(regions)-1)  # apply incentives

        region = regions[r]  # regions = ["utility", "state", "federal", "combined"]
        next_region = regions[r + 1]

        # Apply incentives, initialize first value
        xp_array_incent[next_region] = [0.0]
        yp_array_incent[next_region] = [0.0]

        # percentage based incentives
        p = tech_incentives[region]["%"]
        p_cap = tech_incentives[region]["%_max"]

        # rebates, for some reason called "u" in REopt
        u = tech_incentives[region]["rebate"]
        u_cap = tech_incentives[region]["rebate_max"]

        # reset switches and break point counter
        switch_percentage = (p == 0 || p_cap == 0) ? true : false
        switch_rebate = (u == 0 || u_cap == 0) ? true : false

        # start at second point, first is always zero
        for point in range(2, stop=length(xp_array_incent[region]))

            # previous points
            xp_prev = xp_array_incent[region][point - 1]
            yp_prev = yp_array_incent[region][point - 1]

            # current, unadjusted points
            xp = xp_array_incent[region][point]
            yp = yp_array_incent[region][point]

            # initialize the adjusted points on cost curve
            xa = xp
            ya = yp

            # initialize break points
            u_xbp = 0.0
            u_ybp = 0.0
            p_xbp = 0.0
            p_ybp = 0.0

            if  !switch_rebate
                u_xbp = u_cap / u
                u_ybp = slope(xp_prev, yp_prev, xp, yp) * u_xbp + intercept(xp_prev, yp_prev, xp, yp)
            end

            if !switch_percentage
                p_xbp = (p_cap / p - intercept(xp_prev, yp_prev, xp, yp)) / slope(xp_prev, yp_prev, xp, yp)
                p_ybp = p_cap / p
            end

            if ((p * yp) < p_cap || p_cap == 0) && ((u * xp) < u_cap || u_cap == 0)
                ya = yp - (p * yp + u * xp)
            elseif (p * yp) < p_cap && (u * xp) >= u_cap
                if !switch_rebate
                    if u * xp != u_cap
                        xp_array_incent, yp_array_incent = 
                            insert_u_bp(xp_array_incent, yp_array_incent, next_region, u_xbp, u_ybp, p, u_cap)
                    end
                    switch_rebate = true
                end
                ya = yp - (p * yp + u_cap)
            elseif (p * yp) >= p_cap && (u * xp) < u_cap
                if !switch_percentage
                    if p * yp != p_cap
                        xp_array_incent, yp_array_incent = 
                            insert_p_bp(xp_array_incent, yp_array_incent, next_region, p_xbp, p_ybp, u, p_cap)
                    end
                    switch_percentage = true
                end
                ya = yp - (p_cap + xp * u)
            elseif p * yp >= p_cap && u * xp >= u_cap
                if !switch_rebate && !switch_percentage
                    if p_xbp == u_xbp
                        xp_array_incent, yp_array_incent = 
                            insert_u_bp(xp_array_incent, yp_array_incent, next_region, u_xbp, u_ybp, p, u_cap)
                        switch_percentage = true
                        switch_rebate = true
                    elseif p_xbp < u_xbp
                        if p * yp != p_cap
                            xp_array_incent, yp_array_incent = 
                                insert_p_bp(xp_array_incent, yp_array_incent, next_region, p_xbp, p_ybp, u,
                                            p_cap)
                        end
                        switch_percentage = true
                        if u * xp != u_cap
                            xp_array_incent, yp_array_incent = 
                                insert_u_after_p_bp(xp_array_incent, yp_array_incent, next_region, u_xbp, u_ybp,
                                                    p, p_cap, u_cap)
                        end
                        switch_rebate = true
                    else
                        if u * xp != u_cap
                            xp_array_incent, yp_array_incent = 
                                insert_u_bp(xp_array_incent, yp_array_incent, next_region, u_xbp, u_ybp, p, u_cap)
                        end
                        switch_rebate = true
                        if p * yp != p_cap
                            xp_array_incent, yp_array_incent = 
                                insert_p_after_u_bp(xp_array_incent, yp_array_incent, next_region, p_xbp, p_ybp,
                                                    u, u_cap, p_cap)
                        end
                        switch_percentage = true
                    end
                elseif switch_rebate && !switch_percentage
                    if p * yp != p_cap
                        xp_array_incent, yp_array_incent = 
                            insert_p_after_u_bp(xp_array_incent, yp_array_incent, next_region, p_xbp, p_ybp, u,
                                                u_cap, p_cap)
                    end
                    switch_percentage = true
                elseif !switch_rebate && switch_percentage
                    if u * xp != u_cap
                        xp_array_incent, yp_array_incent = 
                            insert_u_after_p_bp(xp_array_incent, yp_array_incent, next_region, u_xbp, u_ybp, p,
                                                p_cap, u_cap)
                    end
                    switch_rebate = true
                end

                # Finally compute adjusted values
                if p_cap == 0
                    ya = yp - (p * yp + u_cap)
                elseif u_cap == 0
                    ya = yp - (p_cap + u * xp)
                else
                    ya = yp - (p_cap + u_cap)
                end
            end

            push!(xp_array_incent[next_region], xa)
            push!(yp_array_incent[next_region], ya)

            # compute cost curve, funky logic in REopt ignores everything except xa, ya
            if region == "federal"
                push!(cost_curve_bp_x, xa)
                push!(cost_curve_bp_y, ya)
            end
        end
    end

    for seg in range(2, stop=length(cost_curve_bp_x))
        tmp_slope = round((cost_curve_bp_y[seg] - cost_curve_bp_y[seg - 1]) /
                        (cost_curve_bp_x[seg] - cost_curve_bp_x[seg - 1]), digits=0)
        tmp_y_int = round(cost_curve_bp_y[seg] - tmp_slope * cost_curve_bp_x[seg], digits=0)

        push!(cap_cost_slope, tmp_slope)
        push!(cap_cost_yint, tmp_y_int)
    end

    n_segments = length(cap_cost_slope)

    # Following logic modifies the cap cost segments to account for the tax benefits of the ITC and MACRs
    updated_cap_cost_slope = Real[]
    updated_y_intercept = Real[]

    for s in range(1, stop=n_segments)
        if cost_curve_bp_x[s + 1] <= 0
            # Not sure how else to handle this case, perhaps there is a better way to handle it?
            throw(@error("Invalid cost curve for {$nameof(T)}. Value at index {$s} ({$cost_curve_bp_x[s + 1]}) cannot be less than or equal to 0."))
        end

        # Remove federal incentives for ITC basis and tax benefit calculations
        itc = tech.federal_itc_fraction
        rebate_federal = tech.federal_rebate_per_kw
        if itc == 1
            itc_unit_basis = 0
        else
            itc_unit_basis = (cap_cost_slope[s] + rebate_federal) / (1 - itc)
        end

        macrs_schedule = [0.0]
        macrs_bonus_fraction = 0.0
        macrs_itc_reduction = 0.0

        if tech.macrs_option_years != 0
            macrs_bonus_fraction = tech.macrs_bonus_fraction
            macrs_itc_reduction = tech.macrs_itc_reduction
        end
        if tech.macrs_option_years == 5
            macrs_schedule = financial.macrs_five_year
        end
        if tech.macrs_option_years == 7
            macrs_schedule = financial.macrs_seven_year
        end

        replacement_cost = 0.0
        replacement_year = financial.analysis_years
        if nameof(T) in [:Generator]  # Generator is currently only Tech with replacement year and cost
            if tech.replacement_year >= financial.analysis_years # assume no replacement in final year of project
                replacement_cost = 0.0
            else
                replacement_cost = tech.replace_cost_per_kw
            end
            replacement_year = tech.replacement_year
        end
        updated_slope = effective_cost(;
            itc_basis = itc_unit_basis,  # input tech cost with incentives, but no ITC
            replacement_cost = replacement_cost,
            replacement_year = replacement_year,
            discount_rate = financial.owner_discount_rate_fraction,
            tax_rate = financial.owner_tax_rate_fraction,
            itc = itc,
            macrs_schedule = macrs_schedule,
            macrs_bonus_fraction = macrs_bonus_fraction,
            macrs_itc_reduction = macrs_itc_reduction,
            rebate_per_kw = rebate_federal
        )
        # The way REopt incentives currently work, the federal rebate is the only incentive that doesn't reduce ITC basis
        push!(updated_cap_cost_slope, updated_slope)
    end

    for p in range(2, stop=n_segments + 1)
        cost_curve_bp_y[p] = cost_curve_bp_y[p - 1] + updated_cap_cost_slope[p - 1] * 
                                (cost_curve_bp_x[p] - cost_curve_bp_x[p - 1])
        push!(updated_y_intercept, cost_curve_bp_y[p] - updated_cap_cost_slope[p - 1] * cost_curve_bp_x[p])
    end
    cap_cost_slope = updated_cap_cost_slope
    cap_cost_yint = updated_y_intercept

    return cap_cost_slope, cost_curve_bp_x, cap_cost_yint, n_segments
end