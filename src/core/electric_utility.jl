# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
`ElectricUtility` is an optional REopt input with the following keys and default values:
```julia
    net_metering_limit_kw::Real = 0, # Upper limit on the total capacity of technologies that can participate in net metering agreement.
    interconnection_limit_kw::Real = 1.0e9, # Limit on total electric system capacity size that can be interconnected to the grid 
    allow_simultaneous_export_import::Bool = true,  # if true the site has two meters (in effect). Set to false if the export rate is greater than the cost of energy (otherwise, REopt will export before meeting site load).
    
    # Single Outage Modeling Inputs (Outage Modeling Option 1):
    outage_start_time_step::Int=0,  # for modeling a single outage, with critical load spliced into the baseline load ...
    outage_end_time_step::Int=0,  # ... utility production_factor = 0 during the outage
        
    # Multiple Outage Modeling Inputs (Outage Modeling Option 2): 
    # minimax the expected outage cost, with max taken over outage start time, expectation taken over outage duration
    outage_start_time_steps::Array{Int,1}=Int[],  # we minimize the maximum outage cost over outage start times
    outage_durations::Array{Int,1}=Int[],  # One-to-one with outage_probabilities. Outage_durations can be a random variable, and should be in timesteps aligning with time_steps_per_hour (e.g., duration of 4 equates to 1 hour if time_steps_per_hour is 4)
    outage_probabilities::Array{R,1} where R<:Real = [1.0],
    
    ### Cambium Emissions and Clean Energy Inputs ###
    cambium_scenario::String = "Mid-case", # Cambium Scenario for evolution of electricity sector (see Cambium documentation for descriptions).
        ## Options: ["Mid-case", "Low renewable energy cost",   "High renewable energy cost", "High demand growth",  "Low natural gas prices", "High natural gas prices", "Mid-case with 95% decarbonization by 2050",  "Mid-case with 100% decarbonization by 2035"]
    cambium_location_type::String =  "GEA Regions 2023", # Geographic boundary at which emissions and clean energy fraction are calculated. Options: ["Nations", "GEA Regions 2023"] 
    cambium_start_year::Int = 2025, # First year of operation of system. Emissions and clean energy fraction will be levelized starting in this year for the duration of cambium_levelization_years. # Options: any year 2025 through 2050.
    cambium_levelization_years::Int = analysis_years, # Expected lifetime or analysis period of the intervention being studied. Emissions and clean energy fraction will be averaged over this period.
    cambium_grid_level::String = "enduse", # Options: ["enduse", "busbar"]. Busbar refers to point where bulk generating stations connect to grid; enduse refers to point of consumption (includes distribution loss rate). 

    ### Grid Climate Emissions Inputs ### 
    # Climate Option 1 (Default): Use levelized emissions data from NLR's Cambium database by specifying the following fields:
    cambium_co2_metric::String = "lrmer_co2e", # Emissions metric used. Default: "lrmer_co2e" - Long-run marginal emissions rate for CO2-equivalant, combined combustion and pre-combustion emissions rates. Options: See metric definitions and names in the Cambium documentation

    # Climate Option 2: Use CO2 emissions data from the EPA's AVERT based on the AVERT emissions region and specify annual percent decrease
    co2_from_avert::Bool = false, # Default is to use Cambium data for CO2 grid emissions. Set to `true` to instead use data from the EPA's AVERT database. 

    # Climate Option 3: Provide your own custom emissions factors for CO2 and specify annual percent decrease  
    emissions_factor_series_lb_CO2_per_kwh::Union{Real,Array{<:Real,1}} = Float64[], # Custom CO2 emissions profile. Can be scalar or timeseries (aligned with time_steps_per_hour). Ensure emissions year aligns with load year.

    # Used with Climate Options 2 or 3: Annual percent decrease in CO2 emissions factors
    emissions_factor_CO2_decrease_fraction::Union{Nothing, Real} = co2_from_avert || length(emissions_factor_series_lb_CO2_per_kwh) > 0  ? EMISSIONS_DECREASE_DEFAULTS["CO2e"] : nothing , # Annual percent decrease in the total annual CO2 emissions rate of the grid. A negative value indicates an annual increase.

    ### Grid Health Emissions Inputs ###
    # Health Option 1 (Default): Use health emissions data from the EPA's AVERT based on the AVERT emissions region and specify annual percent decrease
    avert_emissions_region::String = "", # AVERT emissions region. Default is based on location, or can be overriden by providing region here.

    # Health Option 2: Provide your own custom emissions factors for health emissions and specify annual percent decrease:
    emissions_factor_series_lb_NOx_per_kwh::Union{Real,Array{<:Real,1}} = Float64[], # Custom NOx emissions profile. Can be scalar or timeseries (aligned with time_steps_per_hour). Ensure emissions year aligns with load year.
    emissions_factor_series_lb_SO2_per_kwh::Union{Real,Array{<:Real,1}} = Float64[], # Custom SO2 emissions profile. Can be scalar or timeseries (aligned with time_steps_per_hour). Ensure emissions year aligns with load year.
    emissions_factor_series_lb_PM25_per_kwh::Union{Real,Array{<:Real,1}} = Float64[], # Custom PM2.5 emissions profile. Can be scalar or timeseries (aligned with time_steps_per_hour). Ensure emissions year aligns with load year.

    # Used with Health Options 1 or 2: Annual percent decrease in health emissions factors: 
    emissions_factor_NOx_decrease_fraction::Real = EMISSIONS_DECREASE_DEFAULTS["NOx"], 
    emissions_factor_SO2_decrease_fraction::Real = EMISSIONS_DECREASE_DEFAULTS["SO2"],
    emissions_factor_PM25_decrease_fraction::Real = EMISSIONS_DECREASE_DEFAULTS["PM25"]

    ### Grid Clean Energy Fraction Inputs ###
    cambium_cef_metric::String = "cef_load", # Options = ["cef_load", "cef_gen"] # cef_load is the fraction of generation that is clean, for the generation that is allocated to a region’s end-use load; cef_gen is the fraction of generation that is clean within a region
    renewable_energy_fraction_series::Union{Real,Array{<:Real,1}} = Float64[], # Fraction of energy supplied by the grid that is renewable. Can be scalar or timeseries (aligned with time_steps_per_hour)
```

!!! note "Outage modeling"
    # Indexing
    Outage indexing begins at 1 (not 0) and the outage is inclusive of the outage end time step. 
    For instance, to model a 3-hour outage from 12AM to 3AM on Jan 1, outage_start_time_step = 1 and outage_end_time_step = 3.
    To model a 1-hour outage from 6AM to 7AM on Jan 1, outage_start_time_step = 7 and outage_end_time_step = 7.

    # Can use either singular or multiple outage modeling inputs, not both
    Cannot supply singular outage_start(or end)_time_step and multiple outage_start_time_steps. Must use one or the other.

    # Using min_resil_time_steps to ensure critical load is met
    With multiple outage modeling, the model will choose to meet the critical loads only as cost-optimal. This trade-off depends on cost of not meeting load (see `Financial | value_of_lost_load_per_kwh`) 
    and the costs of meeting load, such as microgrid upgrade cost (see `Financial | microgrid_upgrade_cost_fraction`), fuel costs, and additional DER capacity. To ensure that REopt recommends a system that can meet 
    critical loads during a defined outage period, specify this duration using `Site | min_resil_time_steps`.

    # Outage costs will be included in NPV and LCC
    Note that when using multiple outage modeling, the expected outage cost will be included in the net present value and lifecycle cost calculations (for both the BAU and optimized case). 
    You can set `Financial | value_of_lost_load_per_kwh` to 0 to ignore these costs. However, doing so will remove incentive for the model to meet critical loads during outages, 
    and you should therefore consider also specifying `Site | min_resil_time_steps`. You can alternatively post-process results to remove `lifecycle_outage_cost` from the NPV and LCCs.

!!! note "Outages, Emissions, and Renewable Energy Calculations"
    If a single deterministic outage is modeled using outage_start_time_step and outage_end_time_step,
    emissions and renewable energy percentage calculations and constraints will factor in this outage.
    If stochastic outages are modeled using outage_start_time_steps, outage_durations, and outage_probabilities,
    emissions and renewable energy percentage calculations and constraints will not consider outages.
    
!!! note "MPC vs. Non-MPC"
    This constructor is intended to be used with latitude/longitude arguments provided for
    the non-MPC case and without latitude/longitude arguments provided for the MPC case.

!!! note "Climate and Health Emissions and Grid Clean Energy Modeling" 
    Climate and health-related emissions from grid electricity come from two different data sources and have different REopt inputs as described below. 

    **Climate Emissions**
    - For sites in the contiguous United States (CONUS): 
        - Default climate-related emissions factors come from NLR's Cambium database (Current version: 2022)
            - By default, REopt uses *levelized long-run marginal emission rates for CO2-equivalent (CO2e) emissions* for the region in which the site is located. 
                By default, the emissions rates are levelized over the analysis period (e.g., from 2025 through 2049 for a 25-year analysis)
            - The inputs to the Cambium API request can be modified by the user based on emissions accounting needs (e.g., can change "lifetime" to 1 to analyze a single year's emissions)
            - Note for analysis periods extending beyond 2050: Values beyond 2050 are estimated with the 2050 values. Analysts are advised to use caution when selecting values that place significant weight on 2050 (e.g., greater than 50%)
        - Users can alternatively choose to use emissions factors from the EPA's AVERT by setting `co2_from_avert` to `true`
    - For Alaska and HI: Grid CO2e emissions rates come from the eGRID database. These are single values repeated throughout the year. The default annual `emissions_factor_CO2_decrease_fraction` will be applied to this rate to account for future greening of the grid.   
    - For sites outside of the United States: REopt does not have default grid emissions rates for sites outside of the U.S. For these sites, users must supply custom emissions factor series (`emissions_factor_series_lb_CO2_per_kwh`) and projected emissions decreases (`emissions_factor_CO2_decrease_fraction`). 

    **Health Emissions**
    - For sites in CONUS: health-related emissions factors (PM2.5, SO2, and NOx) come from the EPA's AVERT database.
    - For Alaska and HI: Grid health emissions rates come from the eGRID database. These are single values repeated throughout the year. The default annual `emissions_factor_XXX_decrease_fraction` will be applied to this rate to account for future greening of the grid. 
    - The default `avert_emissions_region` input is determined by the site's latitude and longitude. 
    Alternatively, you may input the desired AVERT `avert_emissions_region`, which must be one of: 
    ["California", "Central", "Florida", "Mid-Atlantic", "Midwest", "Carolinas", "New England","Northwest", "New York", "Rocky Mountains", "Southeast", "Southwest", "Tennessee", "Texas", "Alaska", "Hawaii (except Oahu)", "Hawaii (Oahu)"]
    - For sites outside of the United States: REopt does not have default grid emissions rates for sites outside of the U.S. For these sites, users must supply custom emissions factor series (e.g., `emissions_factor_series_lb_NOx_per_kwh`) and projected emissions decreases (e.g., `emissions_factor_NOx_decrease_fraction`). 

    **Grid Clean Energy Fraction**
    - For sites in CONUS: 
        - Default clean energy fraction data comes from NLR's Cambium database (Current version: 2022)
            - By default, REopt uses *clean energy fraction* for the region in which the site is located.
    - For sites outside of CONUS: REopt does not have default grid clean energy fraction data. Users must supply a custom `renewable_energy_fraction_series`

"""
struct ElectricUtility
    avert_emissions_region::String # AVERT emissions region
    distance_to_avert_emissions_region_meters::Real
    cambium_region::String # Determined by location (lat long) and cambium_location_type
    emissions_factor_series_lb_CO2_per_kwh::Array{<:Real,1}
    emissions_factor_series_lb_NOx_per_kwh::Array{<:Real,1}
    emissions_factor_series_lb_SO2_per_kwh::Array{<:Real,1}
    emissions_factor_series_lb_PM25_per_kwh::Array{<:Real,1}
    emissions_factor_CO2_decrease_fraction::Real
    emissions_factor_NOx_decrease_fraction::Real
    emissions_factor_SO2_decrease_fraction::Real
    emissions_factor_PM25_decrease_fraction::Real
    renewable_energy_fraction_series::Array{<:Real,1} # fraction of grid electricity that is clean or renewable
    outage_start_time_step::Int  # for modeling a single outage, with critical load spliced into the baseline load ...
    outage_end_time_step::Int  # ... utility production_factor = 0 during the outage
    allow_simultaneous_export_import::Bool  # if true the site has two meters (in effect)
    # next 5 variables below used for minimax the expected outage cost,
    # with max taken over outage start time, expectation taken over outage duration
    outage_start_time_steps::Array{Int,1}  # we minimize the maximum outage cost over outage start times
    outage_durations::Array{Int,1}  # one-to-one with outage_probabilities, outage_durations can be a random variable
    outage_probabilities::Array{R,1} where R<:Real 
    outage_time_steps::Union{Nothing, UnitRange} 
    scenarios::Union{Nothing, UnitRange} 
    net_metering_limit_kw::Real 
    interconnection_limit_kw::Real 
    transmission_limit_kw::Real


    function ElectricUtility(;

        # Fields from other models
        latitude::Union{Nothing,Real} = nothing, # Passed from Site
        longitude::Union{Nothing,Real} = nothing, # Passed from Site
        off_grid_flag::Bool = false, # Passed from Settings
        analysis_years::Int = 25, # Passed from Financial
        time_steps_per_hour::Int = 1, # Passed from Settings
        CO2_emissions_reduction_min_fraction::Union{Real, Nothing} = nothing, # passed from Site
        CO2_emissions_reduction_max_fraction::Union{Real, Nothing} = nothing, # passed from Site
        min_resil_time_steps::Int=0, # passed from Site
        include_climate_in_objective::Bool = false, # passed from Settings
        include_health_in_objective::Bool = false, # passed from Settings
        load_year::Int = 2017, # Passed from ElectricLoad

        # Inputs for ElectricUtility
        net_metering_limit_kw::Real = 0, # Upper limit on the total capacity of technologies that can participate in net metering agreement.
        interconnection_limit_kw::Real = 1.0e9,
        transmission_limit_kw::Real = 1.0e9, #Upper limit on purchases from or exports to the grid
        allow_simultaneous_export_import::Bool=true,  # if true the site has two meters (in effect)

        outage_start_time_step::Int=0,  # for modeling a single outage, with critical load spliced into the baseline load ...
        outage_end_time_step::Int=0,  # ... utility production_factor = 0 during the outage
        
        # next 5 variables below used for minimax the expected outage cost,
        # with max taken over outage start time, expectation taken over outage duration
        outage_start_time_steps::Array{Int,1}=Int[],  # we include in the minimization the maximum outage cost over outage start times
        outage_durations::Array{Int,1}=Int[],  # one-to-one with outage_probabilities, outage_durations can be a random variable
        outage_probabilities::Array{<:Real,1} = isempty(outage_durations) ? Float64[] : [1/length(outage_durations) for p_i in 1:length(outage_durations)],
        outage_time_steps::Union{Nothing, UnitRange} = isempty(outage_durations) ? nothing : 1:maximum(outage_durations),
        scenarios::Union{Nothing, UnitRange} = isempty(outage_durations) ? nothing : 1:length(outage_durations),

        ### Cambium Emissions and Clean Energy Inputs ###
        cambium_scenario::String = "Mid-case", # Cambium Scenario for evolution of electricity sector (see Cambium documentation for descriptions).
        cambium_location_type::String =  "GEA Regions 2023", # Geographic boundary at which emissions and clean energy fraction are calculated.  
        cambium_start_year::Int = 2025, # First year of operation of system. Emissions and clean energy fraction will be levelized starting in this year for the duration of cambium_levelization_years. 
        cambium_levelization_years::Int = analysis_years, # Expected lifetime or analysis period of the intervention being studied. Emissions and clean energy fraction will be averaged over this period.
        cambium_grid_level::String = "enduse", # Options: ["enduse", "busbar"]. Busbar refers to point where bulk generating stations connect to grid; enduse refers to point of consumption (includes distribution loss rate). 

        ### Grid Climate Emissions Inputs ### 
        cambium_co2_metric::String = "lrmer_co2e", # Emissions metric used. Default: "lrmer_co2e" - Long-run marginal emissions rate for CO2-equivalant, combined combustion and pre-combustion emissions rates. Options: See metric definitions and names in the Cambium documentation
        co2_from_avert::Bool = false, # Default is to use Cambium data for CO2 grid emissions. Set to `true` to instead use data from the EPA's AVERT database. 
        emissions_factor_series_lb_CO2_per_kwh::Union{Real,Array{<:Real,1}} = Float64[], # Custom CO2 emissions profile. Can be scalar or timeseries (aligned with time_steps_per_hour). Ensure emissions year aligns with load year.
        emissions_factor_CO2_decrease_fraction::Union{Nothing, Real} = co2_from_avert || length(emissions_factor_series_lb_CO2_per_kwh) > 0  ? EMISSIONS_DECREASE_DEFAULTS["CO2e"] : nothing , # Annual percent decrease in the total annual CO2 emissions rate of the grid. A negative value indicates an annual increase.

        ### Grid Health Emissions Inputs ###
        avert_emissions_region::String = "", # AVERT emissions region. Default is based on location, or can be overriden by providing region here.
        emissions_factor_series_lb_NOx_per_kwh::Union{Real,Array{<:Real,1}} = Float64[], # Custom NOx emissions profile. Can be scalar or timeseries (aligned with time_steps_per_hour). Ensure emissions year aligns with load year.
        emissions_factor_series_lb_SO2_per_kwh::Union{Real,Array{<:Real,1}} = Float64[], # Custom SO2 emissions profile. Can be scalar or timeseries (aligned with time_steps_per_hour). Ensure emissions year aligns with load year.
        emissions_factor_series_lb_PM25_per_kwh::Union{Real,Array{<:Real,1}} = Float64[], # Custom PM2.5 emissions profile. Can be scalar or timeseries (aligned with time_steps_per_hour). Ensure emissions year aligns with load year.
        emissions_factor_NOx_decrease_fraction::Real = EMISSIONS_DECREASE_DEFAULTS["NOx"], 
        emissions_factor_SO2_decrease_fraction::Real = EMISSIONS_DECREASE_DEFAULTS["SO2"],
        emissions_factor_PM25_decrease_fraction::Real = EMISSIONS_DECREASE_DEFAULTS["PM25"],

        ### Grid Clean Energy Fraction Inputs ###
        cambium_cef_metric::String = "cef_load", # Options = ["cef_load", "cef_gen"] # cef_load is the fraction of generation that is clean, for the generation that is allocated to a region’s end-use load; cef_gen is the fraction of generation that is clean within a region
        renewable_energy_fraction_series::Union{Real,Array{<:Real,1}} = Float64[], # Fraction of energy supplied by the grid that is renewable. Can be scalar or timeseries (aligned with time_steps_per_hour)
        )

        is_MPC = isnothing(latitude) || isnothing(longitude)
        cambium_region = "NA - Cambium data not used" # will be overwritten if Cambium is used
        
        if !is_MPC
            # Check some inputs 
            error_if_series_vals_not_0_to_1(renewable_energy_fraction_series, "ElectricUtility", "renewable_energy_fraction_series")
            if cambium_start_year < 2025 || cambium_start_year > 2050
                cambium_start_year = 2025 # Must update annually 
                @warn("The cambium_start_year must be between 2025 and 2050. Setting cambium_start_year to $(cambium_start_year).")
            end

            # Get AVERT emissions region
            if avert_emissions_region == ""
                region_abbr, meters_to_region = avert_region_abbreviation(latitude, longitude)
                avert_emissions_region = region_abbr_to_name(region_abbr)
            else
                region_abbr = region_name_to_abbr(avert_emissions_region)
                meters_to_region = 0
            end
            # Warnings 
            if co2_from_avert && length(emissions_factor_series_lb_CO2_per_kwh) > 0
                @warn("You set co2_from_avert = true and provided values for emissions_factor_series_lb_CO2_per_kwh. REopt will use the provided values for emissions_factor_series_lb_CO2_per_kwh.")
            elseif !co2_from_avert && region_abbr ∈ ["AKGD","HIMS","HIOA"] && length(emissions_factor_series_lb_CO2_per_kwh) == 0
                co2_from_avert = true # Must use "avert" data (actually eGRID) because AK and HI are not in Cambium
                if isnothing(emissions_factor_CO2_decrease_fraction)
                    emissions_factor_CO2_decrease_fraction = EMISSIONS_DECREASE_DEFAULTS["CO2e"]
                    @warn("Using eGRID data for region $(region_abbr) for all grid emissions factors and setting emissions_factor_CO2_decrease_fraction = $(emissions_factor_CO2_decrease_fraction).")
                else
                    @warn("Using eGRID data for region $(region_abbr) for all grid emissions factors.")
                end
            elseif isnothing(emissions_factor_CO2_decrease_fraction) 
                emissions_factor_CO2_decrease_fraction = 0.0 # For Cambium data and if not user-provided
            end

            # Get all grid emissions series and clean energy fraction series
            emissions_and_cef_series_dict = Dict{String, Union{Nothing,Array{<:Real,1}}}()
            for (eseries, ekey) in [
                (emissions_factor_series_lb_CO2_per_kwh, "CO2"),
                (emissions_factor_series_lb_NOx_per_kwh, "NOx"),
                (emissions_factor_series_lb_SO2_per_kwh, "SO2"),
                (emissions_factor_series_lb_PM25_per_kwh, "PM25"),
                (renewable_energy_fraction_series, "renewable_energy_fraction_series")
            ]
                if off_grid_flag # no grid emissions for off-grid
                    emissions_and_cef_series_dict[ekey] = zeros(Float64, 8760*time_steps_per_hour)
                elseif typeof(eseries) <: Real  # user provided scalar value
                    emissions_and_cef_series_dict[ekey] = repeat([eseries], 8760*time_steps_per_hour)
                elseif length(eseries) == 1  # user provided array of one value
                    emissions_and_cef_series_dict[ekey] = repeat(eseries, 8760*time_steps_per_hour)
                elseif length(eseries) / time_steps_per_hour ≈ 8760  # user provided array with correct length
                    emissions_and_cef_series_dict[ekey] = eseries
                elseif length(eseries) > 1 && !(length(eseries) / time_steps_per_hour ≈ 8760)  # user provided array with incorrect length
                    if length(eseries) == 8760
                        emissions_and_cef_series_dict[ekey] = repeat(eseries,inner=time_steps_per_hour)
                        @warn("The ElectricUtility emissions or clean energy fraction series for $(ekey) has been adjusted to align with time_steps_per_hour of $(time_steps_per_hour).")
                    else
                        throw(@error("The provided ElectricUtility emissions or clean enery fraction series for $(ekey) does not match the time_steps_per_hour."))
                    end
                else # if not user-provided, get emissions or cef factors from Cambium and/or AVERT
                    if ekey == "CO2" && co2_from_avert == false || ekey == "renewable_energy_fraction_series" # Use Cambium for CO2 or clean energy factors
                        try
                            cambium_response_dict = cambium_profile( # Adjusted for day of week alignment with load and time_steps_per_hour
                                    scenario = cambium_scenario, 
                                    location_type = cambium_location_type, 
                                    latitude = latitude, 
                                    longitude = longitude,
                                    start_year = cambium_start_year,
                                    lifetime = cambium_levelization_years,
                                    metric_col = ekey == "CO2" ? cambium_co2_metric : cambium_cef_metric,
                                    time_steps_per_hour = time_steps_per_hour,
                                    load_year = load_year,
                                    profile_year = 2017, # because Cambium data always starts on a Sunday
                                    grid_level = cambium_grid_level
                            )
                            emissions_and_cef_series_dict[ekey] = cambium_response_dict["data_series"]
                            cambium_region = cambium_response_dict["location"]

                            # save clean_energy_series_dict["cef"] as csv
                            # clean_energy_df = DataFrame(cef = clean_energy_series_dict["cef"])
                            # CSV.write("renewable_energy_fraction_series.csv", clean_energy_df)
                        catch
                            @warn("Could not look up Cambium $(ekey) profile for location ($(latitude), $(longitude)).
                            Location is likely outside contiguous US or something went wrong with the Cambium API request. Setting ElectricUtility $(ekey) factors to zero.")
                            emissions_and_cef_series_dict[ekey] = zeros(Float64, 8760*time_steps_per_hour) 
                        end
                    else # otherwise use AVERT
                        if !isnothing(region_abbr)
                            avert_data_year = 2023 # Must update when AVERT data are updated
                            emissions_and_cef_series_dict[ekey] = avert_emissions_profiles(
                                                            avert_region_abbr = region_abbr,
                                                            latitude = latitude,
                                                            longitude = longitude,
                                                            time_steps_per_hour = time_steps_per_hour,
                                                            load_year = load_year,
                                                            avert_data_year = avert_data_year
                                                            )["emissions_factor_series_lb_"*ekey*"_per_kwh"]
                        else
                            emissions_and_cef_series_dict[ekey] = zeros(Float64, 8760*time_steps_per_hour) # Warnings will happen in avert_emissions_profiles
                        end
                    end
                    # Handle missing emissions inputs (due to failed lookup and not provided by user)
                    if isnothing(emissions_and_cef_series_dict[ekey])
                        @warn "Cannot find hourly ElectricUtility $(ekey) series for region $(region_abbr). Setting this input to zero."
                        if ekey == "CO2" && 
                                        (!isnothing(CO2_emissions_reduction_min_fraction) || 
                                        !isnothing(CO2_emissions_reduction_max_fraction) || 
                                        include_climate_in_objective)
                            throw(@error("To include CO2 costs in the objective function or enforce emissions reduction constraints, 
                                you must either enter custom CO2 grid emissions factors or a site location within the U.S."))
                        elseif ekey in ["NOx", "SO2", "PM25"] && include_health_in_objective
                            throw(@error("To include health costs in the objective function, you must either enter custom health 
                                grid emissions factors or a site location within the contiguous U.S."))
                        end
                        emissions_and_cef_series_dict[ekey] = zeros(8760*time_steps_per_hour)
                    end
                end
            end
        end
        
        if !isempty(outage_durations) && min_resil_time_steps > maximum(outage_durations)
            throw(@error("Site input min_resil_time_steps cannot be greater than the maximum value in ElectricUtility input outage_durations"))
        end
        if (!isempty(outage_start_time_steps) && isempty(outage_durations)) || (isempty(outage_start_time_steps) && !isempty(outage_durations))
            throw(@error("ElectricUtility inputs outage_start_time_steps and outage_durations must both be provided to model multiple outages"))
        end
        if (outage_start_time_step == 0 && outage_end_time_step != 0) || (outage_start_time_step != 0 && outage_end_time_step == 0)
            throw(@error("ElectricUtility inputs outage_start_time_step and outage_end_time_step must both be provided to model a single outage"))
        end
        if !isempty(outage_start_time_steps)
            if outage_start_time_step != 0 && outage_end_time_step !=0
                # Warn if outage_start/end_time_step is provided and outage_start_time_steps not empty
                throw(@error("Cannot supply both outage_start(/end)_time_step for deterministic outage modeling and 
                    multiple outage_start_time_steps for stochastic outage modeling. Please use one or the other."))
            else
                @warn "When using stochastic outage modeling (i.e. outage_start_time_steps, outage_durations, outage_probabilities), 
                    emissions and renewable energy percentage calculations and constraints do not consider outages."
            end
        end
        if length(outage_durations) != length(outage_probabilities)
            throw(@error("ElectricUtility inputs outage_durations and outage_probabilities must be the same length"))
        end
        if length(outage_probabilities) >= 1 && (sum(outage_probabilities) < 0.99999 || sum(outage_probabilities) > 1.00001)
            throw(@error("Sum of ElectricUtility inputs outage_probabilities must be equal to 1"))
        end

        new(
            is_MPC ? "" : avert_emissions_region,
            is_MPC || isnothing(meters_to_region) ? typemax(Int64) : meters_to_region,
            cambium_region,
            is_MPC ? Float64[] : emissions_and_cef_series_dict["CO2"],
            is_MPC ? Float64[] : emissions_and_cef_series_dict["NOx"],
            is_MPC ? Float64[] : emissions_and_cef_series_dict["SO2"],
            is_MPC ? Float64[] : emissions_and_cef_series_dict["PM25"],
            emissions_factor_CO2_decrease_fraction,
            emissions_factor_NOx_decrease_fraction,
            emissions_factor_SO2_decrease_fraction,
            emissions_factor_PM25_decrease_fraction,
            is_MPC ? Float64[] : emissions_and_cef_series_dict["renewable_energy_fraction_series"],
            outage_start_time_step,
            outage_end_time_step,
            allow_simultaneous_export_import,
            outage_start_time_steps,
            outage_durations,
            outage_probabilities,
            outage_time_steps,
            scenarios,
            net_metering_limit_kw,
            interconnection_limit_kw,
            transmission_limit_kw
        )
    end
end

"""
Determine the AVERT region abberviation for a given lat/lon pair.
    1. Checks to see if given point is in an AVERT region
    2. If 1 doesnt work, check to see if our point is near any AVERT regions.
        1. Transform point from NAD83 CRS to EPSG 102008 (NA focused conic projection)
        2. Get distance between point and AVERT zones, store in a vector
        3. If distance from a region < 5 miles, return that region along with distance.

Helpful links:
# https://yeesian.com/ArchGDAL.jl/latest/projections/#:~:text=transform%0A%20%20%20%20point%20%3D%20ArchGDAL.-,fromWKT,-(%22POINT%20(1120351.57%20741921.42
# https://en.wikipedia.org/wiki/Well-known_text_representation_of_geometry
# https://epsg.io/102008
"""
function avert_region_abbreviation(latitude, longitude)
    
    file_path = joinpath(@__DIR__, "..", "..", "data", "emissions", "AVERT_Data", "avert_4326.shp")

    abbr = nothing
    meters_to_region = nothing

    shpfile = ArchGDAL.read(file_path)
	avert_layer = ArchGDAL.getlayer(shpfile, 0)

	point = ArchGDAL.fromWKT(string("POINT (",longitude," ",latitude,")"))
    
	for i in 1:ArchGDAL.nfeature(avert_layer)
		ArchGDAL.getfeature(avert_layer,i-1) do feature # 0 indexed
			if ArchGDAL.contains(ArchGDAL.getgeom(feature), point)
				abbr = ArchGDAL.getfield(feature,"AVERT")
                meters_to_region = 0.0;
			end
		end
	end
    if isnothing(abbr)
        @warn "Could not find AVERT region containing site latitude/longitude. Checking site proximity to AVERT regions."
    else
        return abbr, meters_to_region
    end

    shpfile = ArchGDAL.read(joinpath(@__DIR__, "..", "..", "data", "emissions", "AVERT_Data", "avert_102008.shp"))
    avert_102008 = ArchGDAL.getlayer(shpfile, 0)

    pt = ArchGDAL.createpoint(latitude, longitude)

    try
        fromProj = ArchGDAL.importEPSG(4326)
        toProj = ArchGDAL.importPROJ4("+proj=aea +lat_1=20 +lat_2=60 +lat_0=40 +lon_0=-96 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs")
        ArchGDAL.createcoordtrans(fromProj, toProj) do transform
            ArchGDAL.transform!(pt, transform)
        end
    catch
        @warn "Could not look up AVERT emissions region closest to point ($(latitude), $(longitude)). Location is
        likely invalid or well outside continental US, AK and HI. Grid emissions assumed to be zero."
        return abbr, meters_to_region #nothing, nothing
    end

    distances = []
    for i in 1:ArchGDAL.nfeature(avert_102008)
        ArchGDAL.getfeature(avert_102008,i-1) do f # 0 indexed
            push!(distances, ArchGDAL.distance(ArchGDAL.getgeom(f), pt))
        end
    end
    
    ArchGDAL.getfeature(avert_102008,argmin(distances)-1) do feature	# 0 indexed
        meters_to_region = distances[argmin(distances)]

        if meters_to_region > 8046
            @warn "Your site location ($(latitude), $(longitude)) is more than 5 miles from the nearest AVERT region. Cannot calculate emissions."
            return abbr, meters_to_region #nothing, #
        else
            abbr = ArchGDAL.getfield(feature,"AVERT")
            abbr = abbr == "HI" ? "HIMS" : abbr
            return abbr, meters_to_region
        end
    end
end

function region_abbr_to_name(region_abbr)
    lookup = Dict(
        "CA" => "California",
        "CENT" => "Central",
        "FL" => "Florida",
        "MIDA" => "Mid-Atlantic",
        "MIDW" => "Midwest",
        "NCSC" => "Carolinas",
        "NE" => "New England",
        "NW" => "Northwest",
        "NY" => "New York",
        "RM" => "Rocky Mountains",
        "SE" => "Southeast",
        "SW" => "Southwest",
        "TN" => "Tennessee",
        "TE" => "Texas",
        "AKGD" => "Alaska",
        "HIMS" => "Hawaii (except Oahu)",
        "HIOA" => "Hawaii (Oahu)"
    )
    return get(lookup, region_abbr, "")
end

function region_name_to_abbr(region_name)
    lookup = Dict(
        "California" => "CA",
        "Central" => "CENT",
        "Florida" => "FL",
        "Mid-Atlantic" => "MIDA",
        "Midwest" => "MIDW",
        "Carolinas" => "NCSC",
        "New England" => "NE",
        "Northwest" => "NW",
        "New York" => "NY",
        "Rocky Mountains" => "RM",
        "Southeast" => "SE",
        "Southwest" => "SW",
        "Tennessee" => "TN",
        "Texas" => "TE",
        "Alaska" => "AKGD",
        "Hawaii (except Oahu)" => "HIMS",
        "Hawaii (Oahu)" => "HIOA"
    )
    return get(lookup, region_name, "")
end

"""
    avert_emissions_profiles(; avert_region_abbr::String="", latitude::Real, longitude::Real, time_steps_per_hour::Int=1, load_year::Int=2017, avert_data_year::Int=2023)

This function gets CO2, NOx, SO2, and PM2.5 grid emission rate profiles (1-year time series) from the AVERT dataset.
    If avert_region_abbr is supplied, this will overwrite the default region that would otherwise be selected using the lat, long.
Returned emissions profile is adjusted for day of week alignment with load_year.
    
This function is used for the /emissions_profile endpoint in the REopt API, in particular 
    for the webtool to display grid emissions defaults before running REopt, 
    but is also generally an external way to access AVERT data without running REopt.
"""
function avert_emissions_profiles(; avert_region_abbr::String="", latitude::Real, longitude::Real, time_steps_per_hour::Int=1, load_year::Int=2017, avert_data_year::Int=2023)
    if avert_region_abbr == "" # Region not supplied
        avert_region_abbr, avert_meters_to_region = avert_region_abbreviation(latitude, longitude)
    else
        avert_meters_to_region = 0.0
    end
    avert_emissions_region = region_abbr_to_name(avert_region_abbr)
    if isnothing(avert_region_abbr)
        return Dict{String, Any}(
                "error"=>
                "Could not look up AVERT emissions region within 5 miles from point ($(latitude), $(longitude)).
                Location is likely invalid or well outside continental US, AK, and HI."
            )
    end

    response_dict = Dict{String, Any}(
        "avert_region_abbr" => avert_region_abbr,
        "avert_region" => avert_emissions_region,
        "units" => "Pounds emissions per kWh",
        "description" => "Regional hourly grid emissions factors for applicable EPA AVERT region, adjusted to align days of week with load year $(load_year).",
        "avert_meters_to_region" => avert_meters_to_region
    )
    for ekey in ["CO2", "NOx", "SO2", "PM25"]
        # Columns 1 and 2 do not contain AVERT region information, so skip them.
        avert_df = readdlm(joinpath(@__DIR__, "..", "..", "data", "emissions", "AVERT_Data", "AVERT_$(avert_data_year)_$(ekey)_lb_per_kwh.csv"), ',')[:, 3:end]
        # Find col index for region. Row 1 does not contain AVERT data so skip that.
        emissions_profile_unadjusted = round.(avert_df[2:end,findfirst(x -> x == avert_region_abbr, avert_df[1,:])], digits=6)
        # Adjust for day of week alignment with load
        ef_profile_adjusted = align_profile_with_load_year(load_year=load_year, profile_year=avert_data_year, profile_data=emissions_profile_unadjusted) 
        # Adjust for non-hourly timesteps 
        if time_steps_per_hour > 1
            ef_profile_adjusted = repeat(ef_profile_adjusted,inner=time_steps_per_hour)
        end
        response_dict["emissions_factor_series_lb_"*ekey*"_per_kwh"] = ef_profile_adjusted
    end
    return response_dict
end

"""
    cambium_profile(; scenario::String, 
                                location_type::String, 
                                latitude::Real, 
                                longitude::Real,
                                start_year::Int,
                                lifetime::Int,
                                metric_col::String,
                                grid_level::String,
                                time_steps_per_hour::Int=1,
                                load_year::Int=2017,
                                profile_year::Int=2017,
                                )

This function constructs an API request to the Cambium database to retrieve either emissions data or clean energy fraction data depending on the `metric_col` provided.
The data will be averaged on an hourly basis over the "lifetime" provided.
The returned profiles are adjusted for day of week alignment with the provided "load_year" (Cambium profiles always start on a Sunday.)
    
This function is also used for the /cambium_profile endpoint in the REopt API, in particular for the webtool to display grid emissions data.

"""
function cambium_profile(; scenario::String, 
                        location_type::String, 
                        latitude::Real, 
                        longitude::Real,
                        start_year::Int,
                        lifetime::Int,
                        metric_col::String,
                        grid_level::String,
                        time_steps_per_hour::Int=1,
                        load_year::Int=2017,
                        profile_year::Int=2017
                        )

    url = "https://scenarioviewer.nrel.gov/api/get-levelized/" # Production 
    project_uuid = "0f92fe57-3365-428a-8fe8-0afc326b3b43" # Cambium 2023 
    

    payload=Dict(
            "project_uuid" => project_uuid,
            "scenario" => scenario,
            "location_type" => location_type,  
            "latitude" => string(round(latitude, digits=3)),
            "longitude" => string(round(longitude, digits=3)), 
            "start_year" => string(start_year), # data year covers nominal year and 4 years proceeding; e.g., 2040 values cover time range starting in 2036
            "lifetime" => string(lifetime), # Integer 1 or greater (Default 25 yrs)
            "discount_rate" => "0.0", # Zero = simple average (a pwf with discount rate gets applied to projected CO2 costs, but not quantity.)
            "time_type" => "hourly", # hourly or annual
            "metric_col" => metric_col, # lrmer_co2e
            "smoothing_method" => "rolling", # rolling or none (only applicable to hourly queries). "rolling" best with TMY data; "none" best if 2012 weather data used.
            "gwp" => "100yrAR6", # Global warming potential values. Default: "100yrAR6". Options: "100yrAR5", "20yrAR5", "100yrAR6", "20yrAR6" or a custom tuple [1,10.0,100] with GWP values for [CO2, CH4, N2O]
            "grid_level" => grid_level, # enduse or busbar 
            "ems_mass_units" => "lb" # lb or kg
    )

    try
        r = HTTP.get(url; query=payload) 
        response = JSON.parse(String(r.body)) # contains response["status"]
        output = response["message"]
        # Convert from [lb/MWh] to [lb/kWh] if the metric is emissions-related
        data_series = occursin("co2", metric_col) ? output["values"] ./ 1000 : convert(Array{Float64,1}, output["values"])
        # Align day of week of emissions or clean energy and load profiles (Cambium data starts on Sundays so assuming profile_year=2017)
        data_series = align_profile_with_load_year(load_year=load_year, profile_year=profile_year, profile_data=data_series)
        
        if time_steps_per_hour > 1
            data_series = repeat(data_series, inner=time_steps_per_hour)
        end
        
        response_dict = Dict{String, Any}(
            "description" => "Hourly CO2 (or CO2e) grid emissions factors or clean energy fraction for applicable Cambium location and location_type, adjusted to align with load year $(load_year).",
            "units" => occursin("co2", metric_col) ? "Pounds emissions per kWh" : "Fraction of clean energy",
            "location" => output["location"],
            "metric_col" => output["metric_col"], 
            "data_series" => data_series 
        )
        return response_dict
    catch
        return Dict{String, Any}(
            "error" => "Could not look up Cambium $(metric_col) profile from point ($(latitude), $(longitude)). 
             Location is likely outside contiguous US or something went wrong with the Cambium API request."
        )
    end
end

function align_profile_with_load_year(; load_year::Int, profile_year::Int, profile_data::Array{<:Real,1})
    
    ef_start_day = dayofweek(Date(profile_year,1,1)) # Monday = 1; Sunday = 7
    load_start_day = dayofweek(Date(load_year,1,1)) 
    
    if ef_start_day == load_start_day
        profile_data_adj = profile_data
    else
        # Example: Emissions year = 2017; ef_start_day = 7 (Sunday). Load year = 2021; load_start_day = 5 (Fri)
        cut_days = 7+(load_start_day-ef_start_day) # Ex: = 7+(5-7) = 5 --> cut Sun, Mon, Tues, Wed, Thurs
        wrap_ts = profile_data[25:24+24*cut_days] # Ex: = profile_data[25:144] wrap Mon-Fri to end
        profile_data_adj = append!(profile_data[24*cut_days+1:end],wrap_ts) # Ex: now starts on Fri and end Fri to align with 2021 cal
    end

    return profile_data_adj
end