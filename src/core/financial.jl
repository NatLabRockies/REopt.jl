# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`Financial` is an optional REopt input with the following keys and default values:
```julia
    om_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "om_cost_escalation_rate_fraction", 0.025),
    elec_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "elec_cost_escalation_rate_fraction", 0.0166),
    existing_boiler_fuel_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "existing_boiler_fuel_cost_escalation_rate_fraction", 0.0348),
    boiler_fuel_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "boiler_fuel_cost_escalation_rate_fraction", 0.0348),
    chp_fuel_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "chp_fuel_cost_escalation_rate_fraction", 0.0348),
    generator_fuel_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "generator_fuel_cost_escalation_rate_fraction", 0.0197),
    offtaker_tax_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "offtaker_tax_rate_fraction", 0.26),
    offtaker_discount_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "offtaker_discount_rate_fraction", 0.0624),
    third_party_ownership::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "third_party_ownership", false),
    owner_tax_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "owner_tax_rate_fraction", 0.26),
    owner_discount_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "owner_discount_rate_fraction", 0.0624),
    analysis_years::Int = 25,
    value_of_lost_load_per_kwh::Union{Array{R,1}, R} where R<:Real = 1.00, #only applies to multiple outage modeling
    microgrid_upgrade_cost_fraction::Real = 0.0
    macrs_five_year::Array{Float64,1} = [0.2, 0.32, 0.192, 0.1152, 0.1152, 0.0576],  # IRS pub 946
    macrs_seven_year::Array{Float64,1} = [0.1429, 0.2449, 0.1749, 0.1249, 0.0893, 0.0892, 0.0893, 0.0446],
    offgrid_other_capital_costs::Real = 0.0, # only applicable when `off_grid_flag` is true. Straight-line depreciation is applied to this capex cost, reducing taxable income.
    offgrid_other_annual_costs::Real = 0.0 # only applicable when `off_grid_flag` is true. Considered tax deductible for owner. Costs are per year.
    min_initial_capital_costs_before_incentives::Union{Nothing,Real} = nothing # minimum up-front capital cost for all technologies, excluding replacement costs and incentives.
    max_initial_capital_costs_before_incentives::Union{Nothing,Real} = nothing # maximum up-front capital cost for all technologies, excluding replacement costs and incentives.
    # Emissions cost inputs
    CO2_cost_per_tonne::Real = 51.0,
    CO2_cost_escalation_rate_fraction::Real = 0.042173,
    NOx_grid_cost_per_tonne::Union{Nothing,Real} = nothing,
    SO2_grid_cost_per_tonne::Union{Nothing,Real} = nothing,
    PM25_grid_cost_per_tonne::Union{Nothing,Real} = nothing,
    NOx_onsite_fuelburn_cost_per_tonne::Union{Nothing,Real} = nothing, # Default data from EASIUR based on location
    SO2_onsite_fuelburn_cost_per_tonne::Union{Nothing,Real} = nothing, # Default data from EASIUR based on location
    PM25_onsite_fuelburn_cost_per_tonne::Union{Nothing,Real} = nothing, # Default data from EASIUR based on location
    NOx_cost_escalation_rate_fraction::Union{Nothing,Real} = nothing, # Default data from EASIUR based on location
    SO2_cost_escalation_rate_fraction::Union{Nothing,Real} = nothing, # Default data from EASIUR based on location
    PM25_cost_escalation_rate_fraction::Union{Nothing,Real} = nothing # Default data from EASIUR based on location
```

!!! note "Third party financing"
    When `third_party_ownership` is `false` the offtaker's discount and tax percentages are used throughout the model:
    ```julia
        if !third_party_ownership
            owner_tax_rate_fraction = offtaker_tax_rate_fraction
            owner_discount_rate_fraction = offtaker_discount_rate_fraction
        end
    ```
"""
mutable struct Financial
    om_cost_escalation_rate_fraction::Float64
    elec_cost_escalation_rate_fraction::Float64
    existing_boiler_fuel_cost_escalation_rate_fraction::Float64
    boiler_fuel_cost_escalation_rate_fraction::Float64
    chp_fuel_cost_escalation_rate_fraction::Float64
    generator_fuel_cost_escalation_rate_fraction::Float64
    offtaker_tax_rate_fraction::Float64
    offtaker_discount_rate_fraction::Float64
    third_party_ownership::Bool
    owner_tax_rate_fraction::Float64
    owner_discount_rate_fraction::Float64
    analysis_years::Int
    value_of_lost_load_per_kwh::Union{Array{<:Real,1}, Real}
    microgrid_upgrade_cost_fraction::Float64
    macrs_five_year::Array{Float64,1}
    macrs_seven_year::Array{Float64,1}
    offgrid_other_capital_costs::Float64
    offgrid_other_annual_costs::Float64
    min_initial_capital_costs_before_incentives::Union{Nothing,Real}
    max_initial_capital_costs_before_incentives::Union{Nothing,Real}
    CO2_cost_per_tonne::Float64
    CO2_cost_escalation_rate_fraction::Float64
    NOx_grid_cost_per_tonne::Float64
    SO2_grid_cost_per_tonne::Float64
    PM25_grid_cost_per_tonne::Float64
    NOx_onsite_fuelburn_cost_per_tonne::Float64
    SO2_onsite_fuelburn_cost_per_tonne::Float64
    PM25_onsite_fuelburn_cost_per_tonne::Float64
    NOx_cost_escalation_rate_fraction::Float64
    SO2_cost_escalation_rate_fraction::Float64
    PM25_cost_escalation_rate_fraction::Float64

    function Financial(;
        off_grid_flag::Bool = false,
        sector::String = "commercial/industrial",
        federal_procurement_type::String = "",
        federal_sector_state::String = "",
        om_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "om_cost_escalation_rate_fraction", 0.025),
        elec_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "elec_cost_escalation_rate_fraction", 0.0166),
        existing_boiler_fuel_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "existing_boiler_fuel_cost_escalation_rate_fraction", 0.0348),
        boiler_fuel_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "boiler_fuel_cost_escalation_rate_fraction", 0.0348),
        chp_fuel_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "chp_fuel_cost_escalation_rate_fraction", 0.0348),
        generator_fuel_cost_escalation_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "generator_fuel_cost_escalation_rate_fraction", 0.0197),
        offtaker_tax_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "offtaker_tax_rate_fraction", 0.26),
        offtaker_discount_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "offtaker_discount_rate_fraction", 0.0624),
        third_party_ownership::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "third_party_ownership", false),
        owner_tax_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "owner_tax_rate_fraction", 0.26),
        owner_discount_rate_fraction::Real = get(get_sector_defaults(; sector=sector, federal_procurement_type=federal_procurement_type, federal_sector_state=federal_sector_state, struct_name="Financial"), "owner_discount_rate_fraction", 0.0624),
        analysis_years::Int = 25,
        value_of_lost_load_per_kwh::Union{Array{<:Real,1}, Real} = 1.00, #only applies to multiple outage modeling
        microgrid_upgrade_cost_fraction::Real = 0.0,
        macrs_five_year::Array{<:Real,1} = [0.2, 0.32, 0.192, 0.1152, 0.1152, 0.0576],  # IRS pub 946
        macrs_seven_year::Array{<:Real,1} = [0.1429, 0.2449, 0.1749, 0.1249, 0.0893, 0.0892, 0.0893, 0.0446],
        offgrid_other_capital_costs::Real = 0.0, # only applicable when `off_grid_flag` is true. Straight-line depreciation is applied to this capex cost, reducing taxable income.
        offgrid_other_annual_costs::Real = 0.0, # only applicable when `off_grid_flag` is true. Considered tax deductible for owner.
        min_initial_capital_costs_before_incentives::Union{Nothing,Real} = nothing,
        max_initial_capital_costs_before_incentives::Union{Nothing,Real} = nothing,
        # Emissions cost inputs
        CO2_cost_per_tonne::Real = 51.0,
        CO2_cost_escalation_rate_fraction::Real = 0.042173,
        NOx_grid_cost_per_tonne::Union{Nothing,Real} = nothing,
        SO2_grid_cost_per_tonne::Union{Nothing,Real} = nothing,
        PM25_grid_cost_per_tonne::Union{Nothing,Real} = nothing,
        NOx_onsite_fuelburn_cost_per_tonne::Union{Nothing,Real} = nothing,
        SO2_onsite_fuelburn_cost_per_tonne::Union{Nothing,Real} = nothing,
        PM25_onsite_fuelburn_cost_per_tonne::Union{Nothing,Real} = nothing,
        NOx_cost_escalation_rate_fraction::Union{Nothing,Real} = nothing,
        SO2_cost_escalation_rate_fraction::Union{Nothing,Real} = nothing,
        PM25_cost_escalation_rate_fraction::Union{Nothing,Real} = nothing,
        # fields from other models needed for validation
        latitude::Real, # Passed from Site
        longitude::Real, # Passed from Site
        include_health_in_objective::Bool = false # Passed from Settings
    )
        
        if off_grid_flag && !(microgrid_upgrade_cost_fraction == 0.0)
            @warn "microgrid_upgrade_cost_fraction is not applied when `off_grid_flag` is true. Setting microgrid_upgrade_cost_fraction to 0.0."
            microgrid_upgrade_cost_fraction = 0.0
        end

        if !off_grid_flag && (offgrid_other_capital_costs != 0.0 || offgrid_other_annual_costs != 0.0)
            @warn "offgrid_other_capital_costs and offgrid_other_annual_costs are only applied when `off_grid_flag` is true. Setting these inputs to 0.0 for this grid-connected analysis."
            offgrid_other_capital_costs = 0.0
            offgrid_other_annual_costs = 0.0
        end

        if !third_party_ownership
            owner_tax_rate_fraction = offtaker_tax_rate_fraction
            owner_discount_rate_fraction = offtaker_discount_rate_fraction
        end

        grid_costs = off_grid_flag ? nothing : easiur_costs(latitude, longitude, "grid")
        onsite_costs = easiur_costs(latitude, longitude, "onsite")
        escalation_rates = easiur_escalation_rates(latitude, longitude, om_cost_escalation_rate_fraction)

        missing_health_inputs = false
        # use EASIUR data for missing grid costs
        missing_health_inputs = isnothing(grid_costs) && !off_grid_flag ? true : missing_health_inputs
        if isnothing(NOx_grid_cost_per_tonne)
            NOx_grid_cost_per_tonne = isnothing(grid_costs) ? 0.0 : grid_costs["NOx"]
        end
        if isnothing(SO2_grid_cost_per_tonne)
            SO2_grid_cost_per_tonne = isnothing(grid_costs) ? 0.0 : grid_costs["SO2"]
        end
        if isnothing(PM25_grid_cost_per_tonne)
            PM25_grid_cost_per_tonne = isnothing(grid_costs) ? 0.0 : grid_costs["PM25"]
        end
        # use EASIUR data for missing fuelburn costs
        missing_health_inputs = isnothing(onsite_costs) ? true : missing_health_inputs
        if isnothing(NOx_onsite_fuelburn_cost_per_tonne)
            NOx_onsite_fuelburn_cost_per_tonne = isnothing(onsite_costs) ? 0.0 : onsite_costs["NOx"]
        end
        if isnothing(SO2_onsite_fuelburn_cost_per_tonne)
            SO2_onsite_fuelburn_cost_per_tonne = isnothing(onsite_costs) ? 0.0 : onsite_costs["SO2"]
        end
        if isnothing(PM25_onsite_fuelburn_cost_per_tonne)
            PM25_onsite_fuelburn_cost_per_tonne = isnothing(onsite_costs) ? 0.0 : onsite_costs["PM25"]
        end
        # use EASIUR data for missing escalation rates
        missing_health_inputs = isnothing(escalation_rates) ? true : missing_health_inputs
        if isnothing(NOx_cost_escalation_rate_fraction)
            NOx_cost_escalation_rate_fraction = isnothing(escalation_rates) ? 0.0 : escalation_rates["NOx"]
        end
        if isnothing(SO2_cost_escalation_rate_fraction)
            SO2_cost_escalation_rate_fraction = isnothing(escalation_rates) ? 0.0 : escalation_rates["SO2"]
        end
        if isnothing(PM25_cost_escalation_rate_fraction)
            PM25_cost_escalation_rate_fraction = isnothing(escalation_rates) ? 0.0 : escalation_rates["PM25"]
        end

        if missing_health_inputs && include_health_in_objective
            throw(@error("To include health costs in the objective function, you must either enter custom emissions costs and escalation rates or a site location within the CAMx grid."))
        end
    

        return new(    
            om_cost_escalation_rate_fraction,
            elec_cost_escalation_rate_fraction,
            existing_boiler_fuel_cost_escalation_rate_fraction,
            boiler_fuel_cost_escalation_rate_fraction,
            chp_fuel_cost_escalation_rate_fraction,
            generator_fuel_cost_escalation_rate_fraction,
            offtaker_tax_rate_fraction,
            offtaker_discount_rate_fraction,
            third_party_ownership,
            owner_tax_rate_fraction,
            owner_discount_rate_fraction,
            analysis_years,
            value_of_lost_load_per_kwh,
            microgrid_upgrade_cost_fraction,
            macrs_five_year,
            macrs_seven_year,
            offgrid_other_capital_costs,
            offgrid_other_annual_costs,
            min_initial_capital_costs_before_incentives,
            max_initial_capital_costs_before_incentives,
            CO2_cost_per_tonne,
            CO2_cost_escalation_rate_fraction,
            NOx_grid_cost_per_tonne,
            SO2_grid_cost_per_tonne,
            PM25_grid_cost_per_tonne,
            NOx_onsite_fuelburn_cost_per_tonne,
            SO2_onsite_fuelburn_cost_per_tonne,
            PM25_onsite_fuelburn_cost_per_tonne,
            NOx_cost_escalation_rate_fraction,
            SO2_cost_escalation_rate_fraction,
            PM25_cost_escalation_rate_fraction
        )
    end
end

function easiur_costs(latitude::Real, longitude::Real, grid_or_onsite::String)
    # Assumption: grid emissions occur at site at 150m above ground
    # and on-site fuelburn emissions occur at site at 0m above ground
    if grid_or_onsite=="grid"
        type = "p150"
    elseif grid_or_onsite=="onsite"
        type = "area"
    else
        @warn "Error in easiur_costs: grid_or_onsite must equal either 'grid' or 'onsite'"
        return nothing
    end
    EASIUR_data = nothing
    try
        EASIUR_data = get_EASIUR2005(type, pop_year=2024, income_year=2024, dollar_year=2010)
    catch e
        @warn "Could not look up EASIUR health costs from point ($latitude,$longitude). {$e}"
        return nothing
    end

    # convert lon, lat to CAMx grid (x, y), specify datum. default is NAD83
    # Note: x, y returned from g2l follows the CAMx grid convention.
    # x and y start from 1, not zero. (x) ranges (1, ..., 148) and (y) ranges (1, ..., 112)
    coords = g2l(longitude, latitude, datum="NAD83")
    x = Int(round(coords[1]))
    y = Int(round(coords[2]))
    # Convert from 2010$ to 2024$ (source: https://www.in2013dollars.com/us/inflation/2010?amount=100)
    USD_2010_to_2024 = 1.432
    try
        costs_per_tonne = Dict(
            "NOx" => EASIUR_data["NOX_Annual"][x, y] .* USD_2010_to_2024,
            "SO2" => EASIUR_data["SO2_Annual"][x, y] .* USD_2010_to_2024,
            "PM25" => EASIUR_data["PEC_Annual"][x, y] .* USD_2010_to_2024
        )
        return costs_per_tonne
    catch
        @warn "Could not look up EASIUR health costs from point ($latitude,$longitude). Location is likely invalid or outside the CAMx grid."
        return nothing
    end
end

function easiur_escalation_rates(latitude::Real, longitude::Real, inflation::Real)
    # Calculate escalation rate as nominal compound annual growth rate in marginal emissions costs between 2020 and 2024 for this location.
    EASIUR_150m_yr2020 = nothing
    EASIUR_150m_yr2024 = nothing
    try
        EASIUR_150m_yr2020 = get_EASIUR2005("p150", pop_year=2020, income_year=2020, dollar_year=2010) 
        EASIUR_150m_yr2024 = get_EASIUR2005("p150", pop_year=2024, income_year=2024, dollar_year=2010) 
    catch e
        @warn "Could not look up EASIUR health cost escalation rates from point ($latitude,$longitude). {$e}"
        return nothing
    end
    # convert lon, lat to CAMx grid (x, y), specify datum. default is NAD83
    coords = g2l(longitude, latitude, datum="NAD83")
    x = Int(round(coords[1]))
    y = Int(round(coords[2]))

    try
        # nominal compound annual growth rate (real + inflation)
        escalation_rates = Dict(
            "NOx" => ((EASIUR_150m_yr2024["NOX_Annual"][x - 1, y - 1]/EASIUR_150m_yr2020["NOX_Annual"][x - 1, y - 1])^(1/4)-1) + inflation,
            "SO2" => ((EASIUR_150m_yr2024["SO2_Annual"][x - 1, y - 1]/EASIUR_150m_yr2020["SO2_Annual"][x - 1, y - 1])^(1/4)-1) + inflation,
            "PM25" => ((EASIUR_150m_yr2024["PEC_Annual"][x - 1, y - 1]/EASIUR_150m_yr2020["PEC_Annual"][x - 1, y - 1])^(1/4)-1) + inflation
        )
        return escalation_rates
    catch
        @warn "Could not look up EASIUR health cost escalation rates from point ($latitude,$longitude). Location is likely invalid or outside the CAMx grid"
        return nothing
    end
end


"""
Adapted to Julia from example Python code for EASIUR found at https://barney.ce.cmu.edu/~jinhyok/apsca/#getting
"""

"""
    get_EASIUR2005(
        stack::String, # area, p150, or p300
        pop_year::Int64=2005, # population year (2000 to 2050)
        income_year::Int64=2005, # income level (1990 to 2024)
        dollar_year::Int64=2010 # dollar year (1980 to 2010)
    )

Returns EASIUR for a given `stack` height in a dict, or nothing if arguments are invalid.
"""
function get_EASIUR2005(stack::String; pop_year::Int64=2005, income_year::Int64=2005, dollar_year::Int64=2010)
    EASIUR_data_lib = joinpath(@__DIR__,"..","..","data","emissions","EASIUR_Data")
    # Income Growth Adjustment factors from BenMAP
    MorIncomeGrowthAdj = Dict(
        1990 => 1.000000,
        1991 => 0.992025,
        1992 => 0.998182,
        1993 => 1.003087,
        1994 => 1.012843,
        1995 => 1.016989,
        1996 => 1.024362,
        1997 => 1.034171,
        1998 => 1.038842,
        1999 => 1.042804,
        2000 => 1.038542,
        2001 => 1.043834,
        2002 => 1.049992,
        2003 => 1.056232,
        2004 => 1.062572,
        2005 => 1.068587,
        2006 => 1.074681,
        2007 => 1.080843,
        2008 => 1.087068,
        2009 => 1.093349,
        2010 => 1.099688,
        2011 => 1.111515,
        2012 => 1.122895,
        2013 => 1.133857,
        2014 => 1.144425,
        2015 => 1.154627,
        2016 => 1.164482,
        2017 => 1.174010,
        2018 => 1.183233,
        2019 => 1.192168,
        2020 => 1.200834,
        2021 => 1.209226,
        2022 => 1.217341,
        2023 => 1.225191,
        2024 => 1.232790,
    )
    # GDP deflator from BenMAP
    GDP_deflator = Dict(
        1980 => 0.478513,
        1981 => 0.527875,
        1982 => 0.560395,
        1983 => 0.578397,
        1984 => 0.603368,
        1985 => 0.624855,
        1986 => 0.636469,
        1987 => 0.659698,
        1988 => 0.686992,
        1989 => 0.720093,
        1990 => 0.759001,
        1991 => 0.790941,
        1992 => 0.814750,
        1993 => 0.839141,
        1994 => 0.860627,
        1995 => 0.885017,
        1996 => 0.911150,
        1997 => 0.932056,
        1998 => 0.946574,
        1999 => 0.967480,
        2000 => 1.000000,
        2001 => 1.028455,
        2002 => 1.044715,
        2003 => 1.068525,
        2004 => 1.096980,
        2005 => 1.134146,
        2006 => 1.170732,
        2007 => 1.204077,
        2008 => 1.250308,
        2009 => 1.245860,
        2010 => 1.266295,
    )

    if !(stack in ["area", "p150", "p300"])
        throw(@error("stack should be one of 'area', 'p150', 'p300'"))
        return nothing
    end

    fn_2005 = joinpath(EASIUR_data_lib,"sc_8.6MVSL_$(stack)_pop2005.hdf5")
    ret_map = JLD.load(fn_2005) 

    if pop_year != 2005
        fn_growth = joinpath(EASIUR_data_lib,"sc_growth_rate_pop2005_pop2040_$(stack).hdf5")
        map_rate = JLD.load(fn_growth) 
        for (k,v) in map_rate
            setindex!(ret_map, ret_map[k] .* (v.^(pop_year - 2005)), k)
        end
    end
    if income_year != 2005
        try
            adj = get(MorIncomeGrowthAdj, income_year, nothing) / get(MorIncomeGrowthAdj, 2005, nothing)
            for (k, v) in ret_map
                setindex!(ret_map, v .* adj, k)
            end
        catch
            throw(@error("EASIUR income year is $(income_year) but must be between 1990 to 2024"))
            return nothing
        end
    end
    if dollar_year != 2010
        try
            adj = get(GDP_deflator, dollar_year, nothing) / get(GDP_deflator, 2010, nothing)
            for (k, v) in ret_map
                setindex!(ret_map, v .* adj, k)
            end
        catch e
            throw(@error("EASIUR dollar year must be between 1980 to 2010"))
            return nothing
        end
    end

    return ret_map
end

"""
    l2g(x::Real, y::Real, inverse::Bool=false, datum::String="NAD83")

Convert LCP (x, y) in CAMx 148x112 grid to Geodetic (lon, lat)
"""
function l2g(x::Real, y::Real; inverse::Bool=false, datum::String="NAD83")
    x = Float64(x)
    y = Float64(y)
    LCP_US = ArchGDAL.importPROJ4("+proj=lcc +no_defs +a=6370000.0 +b=6370000.0 +lon_0=97w +lat_0=40n +lat_1=33n +lat_2=45n +x_0=2736000.0 +y_0=2088000.0 +to_wgs=0,0,0 +units=m")
    if datum == "NAD83"
        datum = ArchGDAL.importEPSG(4269)
    elseif datum == "WGS84"
        datum = ArchGDAL.importEPSG(4326)
    end
    if inverse
        point = ArchGDAL.createpoint(y, x)
        ArchGDAL.createcoordtrans(datum, LCP_US) do transform
            ArchGDAL.transform!(point, transform)
        end
        point = ArchGDAL.createpoint(ArchGDAL.gety(point, 0) / 36000.0 + 1, ArchGDAL.getx(point, 0) / 36000.0 + 1)
    else
        point = ArchGDAL.createpoint((y-1)*36e3, (x-1)*36e3)
        ArchGDAL.createcoordtrans(LCP_US, datum) do transform
            ArchGDAL.transform!(point, transform)
        end
    end
    return [ArchGDAL.getx(point, 0) ArchGDAL.gety(point, 0)]
end

"""
    g2l(lon::Real, lat::Real, datum::String="NAD83")

Convert Geodetic (lon, lat) to LCP (x, y) in CAMx 148x112 grid
"""
function g2l(lon::Real, lat::Real; datum::String="NAD83")
    return l2g(lon, lat, inverse=true, datum=datum)
end

"""
    easiur_data(; latitude::Real, longitude::Real, inflation::Real)

This function gets NOx, SO2, and PM2.5 costs (for grid and on-site emissions) and cost escalation rates from the EASIUR dataset.
    
This function is used for the /easiur_costs endpoint in the REopt API, in particular 
    for the webtool to display health emissions cost/escalation defaults before running REopt, 
    but is also generally an external way to access EASIUR data without running REopt.
"""
function easiur_data(; latitude::Real, longitude::Real, inflation::Real)
        grid_costs = easiur_costs(latitude, longitude, "grid")
        if isnothing(grid_costs)
            return Dict{String, Any}(
                    "error"=>
                    "Could not look up EASIUR health cost data from point ($latitude,$longitude). 
                    Location is likely invalid or outside the CAMx grid."
                )
        end
        onsite_costs = easiur_costs(latitude, longitude, "onsite")
        escalation = easiur_escalation_rates(latitude, longitude, inflation)
        response_dict = Dict{String, Any}(
            "units_costs" => "US dollars per metric ton",
            "description_costs" => "Health costs of emissions from the grid and on-site fuel burn, as reported by the EASIUR model.",
            "units_escalation" => "nominal annual fraction",
            "description_escalation" => "Annual nominal escalation rate of public health costs of emissions.",
        )
        for ekey in ["NOx", "SO2", "PM25"]
            response_dict[ekey*"_grid_cost_per_tonne"] = grid_costs[ekey]
            response_dict[ekey*"_onsite_fuelburn_cost_per_tonne"] = onsite_costs[ekey]
            response_dict[ekey*"_cost_escalation_rate_fraction"] = escalation[ekey]
        end
        return response_dict
end