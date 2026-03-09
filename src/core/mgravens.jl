# These packages are only needed to be loaded if using isolated from REopt
# using JSON
# using Dates

"""     
    convert_mgravens_inputs_to_reopt_inputs(mgravens::Dict)

- Load in the starting-point REopt inputs .json file (not a MG-Ravens user input) which has default values for:
    1. Non-required but possible Ravens-input fields
    2. REopt inputs which are not exposed in Ravens (yet), customized to be for utility-scale MG's, different than standard REopt (C&I-scale)
- Build out REopt inputs by overwritting defaults or adding MG-Ravens inputs to REopt inputs
- Return the REopt inputs Dictionary for using with run_reopt() function
"""

# Notes for REopt
# Expecting a specific name for DesignAlgorithmProperties called DesignAlgorithmProperties_1 to get Financial.analysis_years
# Only looking at the first ProposedAssetOption that is indexed for ProposedSiteLocation
# Summing up the load profiles of the list of LoadGroup.EnergyConsumers to get the total load profile
# Only using value1 for real power entries in the EnergyConsumerSchedule.RegularTimePoints list of dictionaries for load profile

# TODO ask David/Juan: the Location.670a_residential2_Loc has it's own Lat/Long and in this case it's different from the ProposedSiteLocation, even though I'm not using the Location key/dict for anything

"""
    build_timeseries_array(list_of_dict, y_value_name, timestep_sec=3600)

- Create array depending on interval and length of timeseries data
- If less than year-long data, build a year by repeating the partial load data
- Return the populated loads_kw array
"""
function build_timeseries_array(list_of_dict, y_value_name, timestep_sec)
    # Validate timestep_sec options
    if !(timestep_sec in [900, 3600])
        throw(@error("Valid EnergyConsumerSchedule.timeStep for BasicIntervalSchedule LoadForecast is 900 and 3600, input of $timestep_sec"))
    end
    # Adjust scale_factor for repeating data to fill a year-long array
    if timestep_sec == 3600
        scale_factor = 8760 / length(list_of_dict)
    elseif timestep_sec == 900
        scale_factor = 8760 * 4 / length(list_of_dict)
    else
        throw(@error("Invalid timestep_sec: $timestep_sec"))
    end
    # Build timeseries array
    reopt_array = []
    repeated_loads = [data[y_value_name] for data in list_of_dict]
    for _ in 1:convert(Int, ceil(scale_factor))
        append!(reopt_array, repeated_loads)
        extra_ts = length(reopt_array) - (timestep_sec == 3600 ? 8760 : 8760 * 4)
        if extra_ts > 0
            reopt_array = reopt_array[1:end-extra_ts]
            break
        end
    end
    return reopt_array
end

function get_value_in_kw(object)
    value = NaN
    power_conversion = 1000.0  # Assume Watts ("W") or Watt-Hours ("Wh") to divide W or Wh by 1000 to get kW or kWh
    if typeof(object) <: Dict
        if object["multiplier"] == "UnitMultiplier.k"
            power_conversion = 1.0  # Preserve kW
        end
        value = object["value"] / power_conversion
    else
        value = object / power_conversion
    end
    return value
end

"""
    write_timeseries_to_csv(timeseries_data::Vector, filename::String, timestep_sec::Int, year::Int=2024)

Write a timeseries array to a CSV file with a datetime index.

# Arguments
- `timeseries_data::Vector`: The timeseries data to write (e.g., loads_kw)
- `filename::String`: Name of the output CSV file
- `timestep_sec::Int`: Time step in seconds (900 for 15-min, 3600 for hourly)
- `year::Int`: Calendar year for the datetime index (default: 2024)

# Returns
- Writes CSV file to the current working directory with columns: datetime, value
"""
function write_timeseries_to_csv(timeseries_data::Vector, filename::String, timestep_sec::Int, year::Int=2024)
    # Calculate time steps per hour
    time_steps_per_hour = convert(Int64, 3600 / timestep_sec)
    
    # Create datetime index starting from January 1 of the given year
    start_datetime = DateTime(year, 1, 1, 0, 0, 0)
    
    # Generate datetime stamps for each timestep
    datetime_index = [start_datetime + Dates.Minute((i-1) * (60 / time_steps_per_hour)) for i in 1:length(timeseries_data)]
    
    # Open file and write header
    open(filename, "w") do io
        println(io, "datetime,value")
        
        # Write each row
        for (dt, val) in zip(datetime_index, timeseries_data)
            println(io, "$(Dates.format(dt, "yyyy-mm-dd HH:MM:SS")),$val")
        end
    end
    
    @info "Timeseries data written to $filename"
end


function convert_mgravens_inputs_to_reopt_inputs(mgravens::Dict)
    reopt_inputs = JSON.parsefile(joinpath(@__DIR__, "..", "..", "data", "mgravens_fields_defaults.json"))

    # Assume any key within ProposedAssetOption.ProposedEnergyProducerOption are unique and compatible DERs to evaluate in REopt (and have the same site location, etc)
    tech_names = keys(mgravens["ProposedAssetOption"]["ProposedEnergyProducerOption"])
    # TODO if there are duplicative DER types or incompatible DER types, throw an error

    # Analysis period
    algo_name = first(keys(mgravens["ApplicationSettings"]))
    lifetime_str = get(mgravens["ApplicationSettings"][algo_name], "DesignAlgorithmProperties.analysisPeriod", nothing)
    if !isnothing(lifetime_str)
        reopt_inputs["Financial"]["analysis_years"] = parse(Int64, split(split(lifetime_str, "P")[2], "Y")[1])
    end

    # Major assumptions: every ProposedEnergyProducerOption has the same SiteLocation
    # TODO add error checking in case above is not true
    # Make techs_to_include a set and push! append to avoid duplicates below
    techs_to_include = Set()
    # Specific names that were given to certain categories/classes of data
    site_name = ""  # Only one, assumed to be the site location of the first ProposedAssetOption
    load_group_names = []  # May be one or more than one, e.g. ["ResidentialGroup", "IndustrialGroup"]
    energy_consumer_names = []  # One set (1+) for each LoadGroup, e.g. ["670a_residential2", "670b_residential2"]
    load_profile_data = Dict()  # One-to-one with energy_consumer_names
    timestep_sec = 0    
    n_timesteps = 0
    subregion_name = ""
    economic_props_name = ""
    lmp_name = ""
    capacity_prices_name = ""
    updated_battery_cost_with_existing = false 
    for (i, name) in enumerate(tech_names)
        @info "Processing $name"
        tech_data = mgravens["ProposedAssetOption"]["ProposedEnergyProducerOption"][name]
        
        # Assign site, load, and energy prices attributes, using only the FIRST ProposedEnergyProducerOption because they **should** all be the same
        # TODO track all missing required inputs, and key optional inputs that rely on defaults
        if i == 1
            # Site data (lat, long, area) - lat/long is only needed if relying on PV or Wind APIs; default area is a Big Number
            site_name = replace(split(tech_data["ProposedAssetOption.ProposedLocations"][1], "::")[2], "'" => "")
            land_sq_meter = get(mgravens["ProposedSiteLocation"][site_name], "ProposedSiteLocation.availableArea", nothing)
            if !isnothing(land_sq_meter)
                reopt_inputs["Site"]["land_acres"] = land_sq_meter / 4046.86
            end
            position_points = mgravens["ProposedSiteLocation"][site_name]["Location.PositionPoints"][1]
            reopt_inputs["Site"]["latitude"] = parse(Float64, position_points["PositionPoint.yPosition"])
            reopt_inputs["Site"]["longitude"] = parse(Float64, position_points["PositionPoint.xPosition"])
            # Also from SiteLocation, get needed references for LoadGroup
            load_groups_lumped = mgravens["ProposedSiteLocation"][site_name]["ProposedSiteLocation.LoadGroups"]
            # Note, for lehigh_v8_corrected.json, Juan put Group.LoadGroup = {"None": {...}}, but I think we still need to look for the line above in ProposedSiteLocation.loadGroup
            if !isempty(load_groups_lumped)
                # Have to extract just the name we want from lumped string value, e.g. "SubGeographicalRegion::'County1'" (want just 'County1')
                # Need to assume only one/first EnergyConsumer which is tied to a LoadForecast
                for load_group_lumped in load_groups_lumped
                    load_group = replace(split(load_group_lumped, "::")[2], "'" => "")
                    append!(load_group_names, [load_group])
                    lumped_ec_list = mgravens["Group"]["LoadGroup"][load_group]["LoadGroup.EnergyConsumers"]
                    for lumped_ec in lumped_ec_list
                        append!(energy_consumer_names, [replace(split(lumped_ec, "::")[2], "'" => "")])
                    end
                end
            else
                # Assume ALL EnergyConsumers should be summed up
                energy_consumer_names = collect(keys(mgravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["EnergyConsumer"]))
            end
            
            # Check for defined microgrid list of energy consumers to aggregate for critical load, built up along side the total load profile below
            # TODO handle any unique name that has "Microgrid" in it instead of hard-coding this specific name
            #   done by looping through types in Group.ConnectivityNodeContainer keys and finding something like "cimObjectType==microgrid"
            microgrid_name_list = []
            mg_energy_consumers = []
            use_mg_energy_consumers_for_critical_load = false
            if haskey(mgravens["Group"], "ConnectivityNodeContainer") && haskey(mgravens["Group"]["ConnectivityNodeContainer"], "Microgrid.1")
                microgrid_name_list = mgravens["Group"]["ConnectivityNodeContainer"]["Microgrid.1"]["EquipmentContainer.Equipments"]
                for key in microgrid_name_list
                    if occursin("EnergyConsumer", key)
                        push!(mg_energy_consumers, replace(split(key, "::")[2], "'" => ""))
                        use_mg_energy_consumers_for_critical_load = true
                    end
                end
            end

            # Load profile data
            for energy_consumer_name in energy_consumer_names
                # We find out if the p (power) value is to be multiplied by a normalized load profile or ignored later
                load_profile_data[energy_consumer_name] = Dict()
                energy_consumer_data = mgravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["EnergyConsumer"][energy_consumer_name]
                load_profile_data[energy_consumer_name]["name"] = replace(split(energy_consumer_data["EnergyConsumer.LoadProfile"], "::")[2], "'" => "")
                if !isnothing(get(energy_consumer_data, "EnergyConsumer.p", nothing))
                    load_profile_data[energy_consumer_name]["p"] = energy_consumer_data["EnergyConsumer.p"]
                elseif !isnothing(get(energy_consumer_data, "EnergyConsumer.EnergyConsumerPhase", nothing))
                    load_profile_data[energy_consumer_name]["p"] = 0.0
                    # Average all phases for real power p
                    for phase in energy_consumer_data["EnergyConsumer.EnergyConsumerPhase"]
                        if !isnothing(get(phase, "EnergyConsumerPhase.pfixed", nothing))
                            load_profile_data[energy_consumer_name]["p"] += phase["EnergyConsumerPhase.pfixed"] / length(energy_consumer_data["EnergyConsumer.EnergyConsumerPhase"])
                        else
                            @warn "No EnergyConsumerPhase.pfixed found in EnergyConsumer.EnergyConsumerPhase for EnergyConsumer $energy_consumer_name"
                        end
                    end
                else
                    throw(@error("No EnergyConsumer.p or EnergyConsumer.EnergyConsumerPhase found for EnergyConsumer $energy_consumer_name"))
                end
                # Only using these two params below if the load profile does not have units
                load_profile_data[energy_consumer_name]["has_units"] = !isnothing(get(energy_consumer_data, "BasicIntervalSchedule.value1Unit", nothing)) ? true : false
                load_profile_data[energy_consumer_name]["units_multiplier"] = !isnothing(get(energy_consumer_data, "BasicIntervalSchedule.value1Multiplier", nothing)) ? 1.0 : 1000.0
            end
            
            # ElectricLoad.loads_kw electric load profile - aggregate any relevant EnergyConsumers, from LoadGroup or all
            # Assume timestep and year are consistent for all EnergyConsumer.LoadProfile
            timestep_sec = convert(Int64, mgravens["BasicIntervalSchedule"][first(load_profile_data)[2]["name"]]["EnergyConsumerSchedule.timeStep"])
            n_timesteps = length(mgravens["BasicIntervalSchedule"][first(load_profile_data)[2]["name"]]["EnergyConsumerSchedule.RegularTimePoints"])
            has_year = !isnothing(get(mgravens["BasicIntervalSchedule"][first(load_profile_data)[2]["name"]], "EnergyConsumerSchedule.startDate", nothing)) ? true : false
            if has_year
                year = Dates.year(DateTime(mgravens["BasicIntervalSchedule"][first(load_profile_data)[2]["name"]]["EnergyConsumerSchedule.startDate"], DateFormat("dd-mm-yyyy")))
            else
                year = 2024
            end
            reopt_inputs["ElectricLoad"]["year"] = year
            reopt_inputs["Settings"]["time_steps_per_hour"] = convert(Int64, 3600 / timestep_sec)

            # This is intended to handle both/combo absolute power load profiles or normalized profiles with their respective "p" load allocations
            all_interval_data = mgravens["BasicIntervalSchedule"]
            total_loads_kw = zeros(convert(Int64, 8760 * 3600 / timestep_sec))
            microgrid_loads_kw = zeros(convert(Int64, 8760 * 3600 / timestep_sec))
            for energy_consumer_name in energy_consumer_names
                load_name = load_profile_data[energy_consumer_name]["name"]
                interval_data = get(all_interval_data, load_name, nothing)
                if !isnothing(interval_data)
                    # Currently allowing 15-min and hourly intervals with length of N timesteps and scaling to 1-year if not the full year
                    # Note, we also do this with LMPs but we still require 12 months for capacity prices, and optional-input PV profiles
                    timestep_sec_i = interval_data["EnergyConsumerSchedule.timeStep"]
                    if !(timestep_sec_i == timestep_sec)
                        throw(@error("All EnergyConsumerSchedule.timeStep for BasicIntervalSchedule load profiles must be the same"))
                    end
                    if has_year
                        year_i = Dates.year(DateTime(interval_data["EnergyConsumerSchedule.startDate"], DateFormat("dd-mm-yyyy")))
                        if !(year_i == year)
                            throw(@error("All EnergyConsumerSchedule.startDate year for BasicIntervalSchedule load profiles must be the same"))
                        end
                    end
                    load_list_of_dict = interval_data["EnergyConsumerSchedule.RegularTimePoints"]
                    if !(length(load_list_of_dict) == n_timesteps)
                        throw(@error("All EnergyConsumerSchedule.RegularTimePoints for BasicIntervalSchedule load profiles must be the same length"))
                    end
                    # Assume Watts if it has units, and multiplier of 1000 for kW if it has a value1Multiplier
                    has_units = !isnothing(get(interval_data, "BasicIntervalSchedule.value1Unit", nothing)) ? true : false
                    units_multiplier = !isnothing(get(interval_data, "BasicIntervalSchedule.value1Multiplier", nothing)) ? 1.0 : 1000.0
                    # Convert from data from W to kW for REopt, and multiply by EnergyConsumer.p load allocation if normalized (no units)
                    if has_units
                        load_multiplier = 1.0 / units_multiplier
                    else
                        # Not units, but has a p value
                        load_multiplier = load_profile_data[energy_consumer_name]["p"] / load_profile_data[energy_consumer_name]["units_multiplier"]
                    end
                    # Allow for 15-minute (900 timestep_sec) or hourly (3600 timestep_sec) time intervals, and time windows of 1, 2, 7, and 365 days, and scale to year-long time window arrays (365 days)
                    total_loads_kw += load_multiplier * build_timeseries_array(load_list_of_dict, "RegularTimePoint.value1", timestep_sec_i)
                    if (energy_consumer_name in mg_energy_consumers) && use_mg_energy_consumers_for_critical_load
                        microgrid_loads_kw += load_multiplier * build_timeseries_array(load_list_of_dict, "RegularTimePoint.value1", timestep_sec_i)
                    end
                else
                    throw(@error("No $load_name load name found in BasicIntervalSchedule"))
                end
            end
            reopt_inputs["ElectricLoad"]["loads_kw"] = total_loads_kw
            # Write total_loads_kw to CSV file with datetime index
            write_timeseries_to_csv(total_loads_kw, "total_loads_kw.csv", timestep_sec, year)
            println("Min gross load (kW): ", round(minimum(total_loads_kw), digits=0))
            println("Max gross load (kW): ", round(maximum(total_loads_kw), digits=0))
            if sum(microgrid_loads_kw) > 0.0
                reopt_inputs["ElectricLoad"]["critical_loads_kw"] = microgrid_loads_kw
                # Write microgrid_loads_kw to CSV file with datetime index
                write_timeseries_to_csv(microgrid_loads_kw, "microgrid_loads_kw.csv", timestep_sec, year)
            end
            println("Min critical load (kW): ", round(minimum(microgrid_loads_kw), digits=0))
            println("Max critical load (kW): ", round(maximum(microgrid_loads_kw), digits=0))

            # A bunch of financial/prices stuff depends on the Region name, but this is all assumed to apply for all/aggregate loads
            subregion_name = replace(split(mgravens["ProposedSiteLocation"][site_name]["ProposedSiteLocation.Region"], "::")[2], "'" => "")
            # The *Sub*Region is the one that has the economic properties and index for EnergyPrices, e.g. "SubGeographicalRegion::'County1'"
            economic_props_name = replace(split(mgravens["Group"]["SubGeographicalRegion"][subregion_name]["SubGeographicalRegion.EconomicProperty"], "::")[2], "'" => "")
            
            # Financial inputs (optional)
            financial_map = [("discountRate", "offtaker_discount_rate_fraction"), 
                            ("inflationRate", "om_cost_escalation_rate_fraction"),
                            ("taxRate", "offtaker_tax_rate_fraction")]
            economic_props = mgravens["EconomicProperty"][economic_props_name]
            for param in financial_map
                if !isnothing(get(economic_props, "EconomicProperty."*param[1], nothing))
                    reopt_inputs["Financial"][param[2]] = round(economic_props["EconomicProperty."*param[1]] / 100.0, digits=4)  # Convert percent to decimal
                end
            end          

            # LMP - energy prices
            lmp_name = replace(split(mgravens["Group"]["SubGeographicalRegion"][subregion_name]["SubGeographicalRegion.LocationalMarginalPrices"], "::")[2], "'" => "")
            lmp_dict = get(mgravens["EnergyPrices"]["LocationalMarginalPrices"], lmp_name, nothing)
            if !isnothing(lmp_dict)
                # LMP - energy prices
                lmp_list_of_dict = lmp_dict["LocationalMarginalPrices.LMPCurve"]["PriceCurve.CurveDatas"]
                # Note, if 15-minute interval analysis, must supply LMPs in 15-minute interval, so they have one-to-one data
                if length(lmp_list_of_dict) == n_timesteps
                    reopt_inputs["ElectricTariff"]["tou_energy_rates_per_kwh"] = build_timeseries_array(lmp_list_of_dict, "CurveData.y1value", timestep_sec)
                    # reopt_inputs["ElectricTariff"]["wholesale_rate"] = build_timeseries_array(lmp_list_of_dict, "CurveData.y1value", timestep_sec) .- 0.001
                else
                    throw(@error("LMP PriceCurve.CurveDatas must match the interval and length of the Load Profile RegularIntervalSchedule.TimePoints array"))
                end
            else
                throw(@error("No LMP name $lmp_name found in EnergyPrices.LocationalMarginalPrices"))
            end

            # Capacity prices (monthly)
            capacity_prices_name = replace(split(mgravens["Group"]["SubGeographicalRegion"][subregion_name]["SubGeographicalRegion.CapacityPrices"], "::")[2], "'" => "")
            capacity_dict = get(mgravens["EnergyPrices"]["CapacityPrices"], capacity_prices_name, nothing)
            if !isnothing(capacity_dict)
                capacity_list_of_dict = capacity_dict["CapacityPrices.CapacityPriceCurve"]["PriceCurve.CurveDatas"]
                if length(capacity_list_of_dict) == 12
                    reopt_inputs["ElectricTariff"]["monthly_demand_rates"] = zeros(12)
                    for (ts, data) in enumerate(capacity_list_of_dict)
                        reopt_inputs["ElectricTariff"]["monthly_demand_rates"][ts] = data["CurveData.y1value"]
                    end
                else
                    throw(@error("Length of CapacityPrices PriceCurve.CurveDatas must be equal to 12 (monthly)"))
                end
            else
                throw(@error("No Capacity name $capacity_prices_name found in EnergyPrices.CapacityPrices"))
            end

            # Coincident peak prices, monthly (optional)
            # TODO allow multiple prices with different times for each; also consider more than one consecutive hour
            #  Currently, we can only have one active time step for each month because we can't distinguish from the Ravens schema
            #   Also, we must past an array of length 12 of the same prices for REopt to calculate monthly CP charges; otherwise it's more like "yearly" or "per unique price"
            if !isnothing(get(mgravens["EnergyPrices"], "CoincidentPeakPrices", nothing))
                coincident_peak_prices_name = replace(split(mgravens["Group"]["SubGeographicalRegion"][subregion_name]["SubGeographicalRegion.CoincidentPeakPrices"], "::")[2], "'" => "")
                coincident_peak_dict = get(mgravens["EnergyPrices"]["CoincidentPeakPrices"], coincident_peak_prices_name, nothing)
                if !isnothing(coincident_peak_dict)
                    coincident_peak_list_of_dict = coincident_peak_dict["CoincidentPeakPrices.CoincidentPeakPriceCurve"]["PriceCurve.CurveDatas"]
                    prices = [coincident_peak_list_of_dict[i]["CurveData.y1value"] for i in eachindex(coincident_peak_list_of_dict)]
                    ts_array = [[coincident_peak_list_of_dict[i]["CurveData.xvalue"]] for i in eachindex(coincident_peak_list_of_dict)]
                    reopt_inputs["ElectricTariff"]["coincident_peak_load_charge_per_kw"] = prices
                    reopt_inputs["ElectricTariff"]["coincident_peak_load_active_time_steps"] = ts_array
                else
                    throw(@error("No Coincident Peak name $coincident_peak_prices_name found in EnergyPrices.CoincidentPeakPrices"))
                end     
            end       

            # Printing for debugging
            # println("")
            # println("site_name = $site_name")
            # println("load_group_names = $load_group_names")
            # println("energy_consumer_names = $energy_consumer_names")
            # println("load_profile_data = $load_profile_data")
            # println("subregion_name = $subregion_name")
            # println("region_name = $region_name")
            # println("lmp_name = $lmp_name")
            # println("capacity_prices_name = $capacity_prices_name")

            # Outages: NOTE, REopt cannot consider different outage durations for differerent outage start times
            #   it can only consider the same set of outage durations with their specified probabilities (sum equals one) across ALL outage start times
            #   also can only specify ONE fraction of total load for critical load
            duration = []  # Only a list to take average at the end (assuming different)
            critical_load_fraction = []  # Only a list to take average at the end (assuming different)
            outage_start_time_steps = []
            if haskey(mgravens, "Document")
                for outage in keys(get(mgravens["Document"], "Outage", []))
                    duration_str = mgravens["Document"]["Outage"][outage]["OutageScenario.anticipatedDuration"]
                    append!(duration, [parse(Int64, split(split(duration_str, "P")[2], "H")[1])])
                    # This will be ignored if there is a critical_loads_kw input, as defined by the list of mg_energy_consumers
                    # Hand if OutageScenario.loadFractionCritical is not a key and avoid assigning reopt_inputs["ElectricLoad"]["critical_load_fraction"]
                    if haskey(mgravens["Document"]["Outage"][outage], "OutageScenario.loadFractionCritical")
                        append!(critical_load_fraction, [mgravens["Document"]["Outage"][outage]["OutageScenario.loadFractionCritical"] / 100.0])
                    end
                    start_date_str = get(mgravens["Document"]["Outage"][outage], "OutageScenario.anticipatedStartDay", nothing)
                    # Optional to input start date and hour, and otherwise REopt will use default 4 seasonal peak outages
                    if !isnothing(start_date_str)
                        monthly_time_steps = get_monthly_time_steps(reopt_inputs["ElectricLoad"]["year"]; time_steps_per_hour = convert(Int64, reopt_inputs["Settings"]["time_steps_per_hour"]))
                        start_month = parse(Int64, split(start_date_str, "-")[3])
                        start_day_of_month = parse(Int64, split(start_date_str, "-")[4])
                        start_hour_of_day = mgravens["Document"]["Outage"][outage]["OutageScenario.anticipatedStartHour"]
                        append!(outage_start_time_steps, [monthly_time_steps[start_month][(start_day_of_month - 1) * 24 + start_hour_of_day]])
                    end
                end
                if !isempty(duration) && sum(duration) > 0.0
                    duration_avg = convert(Int64, round(sum(duration) / length(duration), digits=0))
                    reopt_inputs["ElectricUtility"]["outage_durations"] = [duration_avg]
                    reopt_inputs["Site"]["min_resil_time_steps"] = duration_avg
                    if !isempty(outage_start_time_steps)
                        reopt_inputs["ElectricUtility"]["outage_start_time_steps"] = outage_start_time_steps
                    end
                end
                # If no critical load fraction, we rely on the list of EnergyConsumers in the microgrid for the critical load
                if !isempty(critical_load_fraction)
                    critical_load_fraction_avg = sum(critical_load_fraction) / length(critical_load_fraction)
                    reopt_inputs["ElectricLoad"]["critical_load_fraction"] = critical_load_fraction_avg
                end                
            end
            # Technology specific input parameters
            # Current approach: only include *microgrid* PV + Battery in "existing", 
            #   where existing battery will only be accounted for by min_kw and min_kwh = existing battery and zeroing out the first "min" amount of capacity cost, and
            #   the generation from existing PVs that are NOT in the microgrid are subtracted off of the total grid-tied load (above)
            # Check for existing assets such as PhotoVoltaicUnit and BatteryUnit, and "consider" them in REopt if those technologies are options
            # TODO we cannot currently model a different size PV or battery for the whole system vs the microgrid for the outage, but
            #   we can net out the non-MG PV from the loads_kw and then ONLY include the existing PV capacity which is on the microgrid
            # Defaults from electric_load.jl
            # loads_kw_is_net::Bool = true, --> we want to say this is FALSE because we are NOT modeling non-MG existing PV, and we are NOT subtracting MG PV from load
            # critical_loads_kw_is_net::Bool = false, --> keep as false because we are NOT netting out MG existing PV, but maybe we would sometimes if that's the load data we have?
            # TODO we cannot model an existing battery other than trick the cost to only estimate cost for new battery, but this won't have BAU value/dispatch for battery
            existing_assets = get(mgravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"], "PowerElectronicsConnection", Dict())
            existing_asset_types = Set{String}()
            existing_pv_data = Dict()
            existing_bess_data = Dict()            
            if !isempty(existing_assets)
                for (key, asset) in existing_assets
                    if haskey(asset, "PowerElectronicsConnection.PowerElectronicsUnit")
                        unit = asset["PowerElectronicsConnection.PowerElectronicsUnit"]
                        if haskey(unit, "Ravens.cimObjectType")
                            asset_type = unit["Ravens.cimObjectType"]
                            if asset_type == "PhotoVoltaicUnit"
                                existing_pv_data[key] = Dict()
                                existing_pv_data[key]["ac_rating_kw"] = get_value_in_kw(unit["PowerElectronicsUnit.maxP"])
                            elseif asset_type == "BatteryUnit"
                                existing_bess_data[key] = Dict()
                                existing_bess_data[key]["ac_rating_kw"] = get_value_in_kw(unit["PowerElectronicsUnit.maxP"])
                                existing_bess_data[key]["energy_rating_kwh"] = get_value_in_kw(unit["BatteryUnit.ratedE"])
                            end
                            # The "Set" data type only keeps unique values with push!, so we can use it to collect unique asset types
                            push!(existing_asset_types, asset_type)
                        else
                            @info "Warning: PowerElectronicsConnection.PowerElectronicsUnit does not have Ravens.cimObjectType for key: $key"
                        end
                    else
                        @info "Warning: PowerElectronicsConnection.PowerElectronicsUnit key not found for key: $key"
                    end
                end 
            end

            # Check for existing assets in the microgrid which may be a SUBset of the list above, or possibly the same set if the whole network is the microgrid
            # TODO handle any unique name that has "Microgrid" in it instead of hard-coding this specific name
            #   done by looping through types in Group.ConnectivityNodeContainer keys and finding something like "cimObjectType==microgrid"
            existing_mg_assets = []
            if haskey(mgravens["Group"], "ConnectivityNodeContainer") && haskey(mgravens["Group"]["ConnectivityNodeContainer"], "Microgrid.1")
                existing_mg_assets = mgravens["Group"]["ConnectivityNodeContainer"]["Microgrid.1"]["EquipmentContainer.Equipments"]
            end
            existing_mg_asset_types = Set{String}()
            existing_mg_pvs = []  # List of unique keys for existing PVs within the existing_assets object
            existing_mg_bess = []  # List of unique keys for existing BESS within the existing_assets object
            for key in existing_mg_assets
                update_asset_type = false
                if occursin("PhotoVoltaicUnit", key)
                    push!(existing_mg_pvs, replace(split(key, "::")[2], "'" => ""))
                    asset_type = "PhotoVoltaicUnit"
                    update_asset_type = true
                elseif occursin("BatteryUnit", key)
                    push!(existing_mg_bess, replace(split(key, "::")[2], "'" => ""))
                    asset_type = "BatteryUnit"
                    update_asset_type = true
                end
                # The "Set" data type only keeps unique values with push!, so we can use it to collect unique asset types
                if update_asset_type
                    push!(existing_mg_asset_types, asset_type)
                end
            end

            # Subtract non-MG (outside of MG) PV from the whole network load profile because we are not modeling that PV capacity in REopt
            if "PhotoVoltaicUnit" in existing_asset_types
                # We are conditionally subtracting out the non_mg_pvs generation from the load profile, but we are not including the non_mg_pvs in the existing_kw
                #   so even though we are making the load profile "partially net", we are not netting out at least some PV so need to specify _is_net = false
                reopt_inputs["ElectricLoad"]["loads_kw_is_net"] = false
                reopt_inputs["ElectricLoad"]["critical_loads_kw_is_net"] = false # this is also the default value, but being explicit here.
                push!(techs_to_include, "PV")
                @info "Found existing PhotoVoltaicUnit assets in whole network"
                if !(length(existing_mg_pvs) == length(keys(existing_pv_data)))
                    @info "Found more existing PhotoVoltaicUnit assets in whole network than microgrid, so netting out non-microgrid PV production from grid-tied load profile"
                    # Find unique existing PVs in existing_pvs that are NOT in existing_mg_pvs
                    non_mg_pvs = setdiff(keys(existing_pv_data), existing_mg_pvs)
                    # Subtract the generation from the grid-tied load profile
                    for pv in non_mg_pvs
                        pv_data = existing_assets[pv]["PowerElectronicsConnection.PowerElectronicsUnit"]
                        if !isnothing(pv_data["PhotoVoltaicUnit.GenerationProfile"])
                            pv_profile_name = replace(split(pv_data["PhotoVoltaicUnit.GenerationProfile"], "::")[2], "'" => "")
                            pv_curve_data = mgravens["Curve"][pv_profile_name]
                            # Assume Watts if it has units, and multiplier of 1000 for kW if it has a value1Multiplier
                            has_units = !isnothing(get(pv_curve_data, "Curve.y1Unit", nothing)) ? true : false
                            units_multiplier = !isnothing(get(pv_curve_data, "Curve.y1Multiplier", nothing)) ? 1.0 : 1000.0
                            # Convert from data from W to kW for REopt, and multiply by EnergyConsumer.p load allocation if normalized (no units)
                            if has_units
                                pv_multiplier = 1.0 / units_multiplier
                            else
                                # Not units, but has a p value
                                pv_multiplier = existing_pv_data[pv]["ac_rating_kw"]  # kW, possibly already converted from W above
                            end
                            # Note, the Curve profile must be normalized to DC-capacity; otherwise will throw a REopt error
                            pv_profile_list_of_dict = pv_curve_data["Curve.CurveDatas"]
                            if !(length(pv_profile_list_of_dict) == 8760 * convert(Int64, reopt_inputs["Settings"]["time_steps_per_hour"]))
                                throw(@error("PV profile $pv_profile_name Curve.CurveDatas must be the same length as the load profile"))
                            else
                                # Subtract the generation from the grid-tied load profile
                                reopt_inputs["ElectricLoad"]["loads_kw"] .-= pv_multiplier * build_timeseries_array(pv_profile_list_of_dict, "CurveData.y1value", timestep_sec)
                            end
                        end
                    end
                end

                # Ensure ensure that the load doesn't go negative, and if it does, make it zero
                reopt_inputs["ElectricLoad"]["loads_kw"] .*= (reopt_inputs["ElectricLoad"]["loads_kw"] .> 0)
                if haskey(reopt_inputs["ElectricLoad"], "critical_loads_kw")
                    reopt_inputs["ElectricLoad"]["critical_loads_kw"] .*= (reopt_inputs["ElectricLoad"]["critical_loads_kw"] .> 0)
                end

                # Aggregate the existing PV capacity, but just using MG PVs and the largest existing PV for the production factor below to avoid modeling multiple PVs
                reopt_inputs["PV"]["existing_kw"] = 0.0  # Initialize existing_kw for REopt inputs
                largest_pv = 0.0
                largest_pv_name = ""
                # TODO handle if no existing_mg_pvs which will error for "" largest_pv_name below for pv_data
                for pv in existing_mg_pvs
                    pv_data = existing_assets[pv]["PowerElectronicsConnection.PowerElectronicsUnit"]
                    if !isnothing(pv_data["PowerElectronicsUnit.maxP"])
                        reopt_inputs["PV"]["existing_kw"] += get_value_in_kw(pv_data["PowerElectronicsUnit.maxP"])
                        if get_value_in_kw(pv_data["PowerElectronicsUnit.maxP"]) > largest_pv
                            largest_pv = get_value_in_kw(pv_data["PowerElectronicsUnit.maxP"])
                            largest_pv_name = pv
                        end
                    end
                end

                # Assign the largest existing PV for production factor
                pv_data = existing_assets[largest_pv_name]["PowerElectronicsConnection.PowerElectronicsUnit"]
                if !isnothing(pv_data["PhotoVoltaicUnit.GenerationProfile"])
                    pv_profile_name = replace(split(pv_data["PhotoVoltaicUnit.GenerationProfile"], "::")[2], "'" => "")
                    pv_curve_data = mgravens["Curve"][pv_profile_name]
                    # Assume Watts if it has units, and multiplier of 1000 for kW if it has a value1Multiplier
                    has_units = !isnothing(get(pv_curve_data, "Curve.y1Unit", nothing)) ? true : false
                    units_multiplier = !isnothing(get(pv_curve_data, "Curve.y1Multiplier", nothing)) ? 1.0 : 1000.0
                    # Convert from data from W to kW for REopt, and multiply by EnergyConsumer.p load allocation if normalized (no units)
                    println("PV largest unit size kW = ", existing_pv_data[largest_pv_name]["ac_rating_kw"])
                    println("PV profile has_units = $has_units, units_multiplier = $units_multiplier")
                    if has_units
                        pv_multiplier = 1.0 / (existing_pv_data[largest_pv_name]["ac_rating_kw"] * units_multiplier)
                    else
                        # TODO confirm good: No units, so use this profile assuming it's AC_prod / DC_rated
                        pv_multiplier = 1.0
                    end
                    # Note, the Curve profile must be normalized to DC-capacity; otherwise will throw a REopt error
                    pv_profile_list_of_dict = pv_curve_data["Curve.CurveDatas"]
                    if !(length(pv_profile_list_of_dict) == 8760 * convert(Int64, reopt_inputs["Settings"]["time_steps_per_hour"]))
                        throw(@error("PV profile $pv_profile_name Curve.CurveDatas must be the same length as the load profile"))
                    else
                        # Subtract the generation from the grid-tied load profile
                        reopt_inputs["PV"]["production_factor_series"] = pv_multiplier * build_timeseries_array(pv_profile_list_of_dict, "CurveData.y1value", timestep_sec)
                    end
                else
                    @info "No PhotoVoltaicUnit.GenerationProfile found for existing PV $largest_pv_name, so REopt will call PVWatts for production_factor_series"
                end

                # Calculate total aggregated existing PV production profile for all PV systems (MG and non-MG)
                if haskey(reopt_inputs["PV"], "production_factor_series")
                    total_existing_pv_capacity_kw = sum([existing_pv_data[pv]["ac_rating_kw"] for pv in keys(existing_pv_data)])
                    total_existing_pv_production_kw = total_existing_pv_capacity_kw * reopt_inputs["PV"]["production_factor_series"]
                    write_timeseries_to_csv(total_existing_pv_production_kw, "total_existing_pv_production_kw.csv", timestep_sec, year)
                    println("Total existing PV capacity (kW): ", round(total_existing_pv_capacity_kw, digits=0))
                    println("Min existing PV production (kW): ", round(minimum(total_existing_pv_production_kw), digits=0))
                    println("Max existing PV production (kW): ", round(maximum(total_existing_pv_production_kw), digits=0))
                    # Create the same type of pv_production but just for the microgrid existing PVs
                    if !isempty(existing_mg_pvs)
                        total_mg_existing_pv_capacity_kw = sum([existing_pv_data[pv]["ac_rating_kw"] for pv in existing_mg_pvs])
                        total_mg_existing_pv_production_kw = total_mg_existing_pv_capacity_kw * reopt_inputs["PV"]["production_factor_series"]
                        write_timeseries_to_csv(total_mg_existing_pv_production_kw, "total_mg_existing_pv_production_kw.csv", timestep_sec, year)
                        println("Total MG existing PV capacity (kW): ", round(total_mg_existing_pv_capacity_kw, digits=0))
                        println("Min MG existing PV production (kW): ", round(minimum(total_mg_existing_pv_production_kw), digits=0))
                        println("Max MG existing PV production (kW): ", round(maximum(total_mg_existing_pv_production_kw), digits=0))
                    end
                end
            end

            if "BatteryUnit" in existing_asset_types && !("BatteryUnit" in existing_mg_asset_types)
                @info "Found existing BatteryUnit in whole system but not in microgrid, so ignoring existing BatteryUnit assets. Existing MG BatteryUnit will be modeled as a zero-cost first X capacity using a negative constant cost term"
            end

            existing_battery_kw = 0.0
            existing_battery_kwh = 0.0
            cost(kw, kwh) = kw * reopt_inputs["ElectricStorage"]["installed_cost_per_kw"] + kwh * reopt_inputs["ElectricStorage"]["installed_cost_per_kwh"]
            if "BatteryUnit" in existing_mg_asset_types
                updated_battery_cost_with_existing = true
                @info "Found existing BatteryUnit in microgrid, so including by zeroing out the cost for the first X amount of capacity"
                push!(techs_to_include, "ElectricStorage")
                # Update ElectricStorage.installed_cost_constant to make the existing BatteryUnit power and energy capacity zero-cost
                # TODO we currently cannot model economy of scale with the cost constant when we have an existing battery
                # Aggregate existing battery capacity
                for bess in keys(existing_bess_data)
                    existing_battery_kw += existing_bess_data[bess]["ac_rating_kw"]
                    existing_battery_kwh += existing_bess_data[bess]["energy_rating_kwh"]
                end
                reopt_inputs["ElectricStorage"]["min_kw"] = existing_battery_kw
                reopt_inputs["ElectricStorage"]["min_kwh"] = existing_battery_kwh
                # With existing battery, we lump the const constant into the per_kw and per_kwh costs because we can't model the cost constant for real
                lumped_const_power_fraction = 0.5
                lumped_const_ref_kw = 1800.0
                lumped_const_ref_kwh = 7200.0
                installed_cost_per_kw = copy(reopt_inputs["ElectricStorage"]["installed_cost_per_kw"])
                installed_cost_per_kwh = copy(reopt_inputs["ElectricStorage"]["installed_cost_per_kwh"])
                installed_cost_constant = copy(reopt_inputs["ElectricStorage"]["installed_cost_constant"])
                reopt_inputs["ElectricStorage"]["installed_cost_per_kw"] = (installed_cost_per_kw * lumped_const_ref_kw + lumped_const_power_fraction * installed_cost_constant) / lumped_const_ref_kw
                reopt_inputs["ElectricStorage"]["installed_cost_per_kwh"] = (installed_cost_per_kwh * lumped_const_ref_kwh + lumped_const_power_fraction * installed_cost_constant) / lumped_const_ref_kwh
                reopt_inputs["ElectricStorage"]["installed_cost_constant"] = -cost(existing_battery_kw, existing_battery_kwh)
            end
        end

        ####   Check these for each asset type, not just i == 1   ###
        # TODO are we sure that the cost inputs can be handled as "per/kW" vs "per/W"? what about units for land area, or other non power/energy/money unit?   
        if tech_data["Ravens.cimObjectType"] == "ProposedPhotoVoltaicUnitOption"
            # PV inputs
            push!(techs_to_include, "PV")
            # Optional inputs for PV; only update if included in MG-Ravens inputs, otherwise rely on MG-Ravens default or REopt default
            if !isnothing(get(tech_data, "ProposedEnergyProducerOption.powerCapacityFixed", nothing))
                reopt_inputs["PV"]["min_kw"] = get_value_in_kw(tech_data["ProposedEnergyProducerOption.powerCapacityFixed"])
                reopt_inputs["PV"]["max_kw"] = get_value_in_kw(tech_data["ProposedEnergyProducerOption.powerCapacityFixed"])
            else
                if !isnothing(get(tech_data, "ProposedEnergyProducerOption.powerCapacityMin", nothing))
                    reopt_inputs["PV"]["min_kw"] = get_value_in_kw(tech_data["ProposedEnergyProducerOption.powerCapacityMin"])
                end
                if !isnothing(get(tech_data, "ProposedEnergyProducerOption.powerCapacityMax", nothing))
                    reopt_inputs["PV"]["max_kw"] = get_value_in_kw(tech_data["ProposedEnergyProducerOption.powerCapacityMax"])
                end
            end
            if !isnothing(get(tech_data, "ProposedEnergyProducerOption.variablePrice", nothing))
                reopt_inputs["PV"]["installed_cost_per_kw"] = tech_data["ProposedEnergyProducerOption.variablePrice"]["value"]
            end
            if !isnothing(get(tech_data, "ProposedAssetOption.operationsAndMaintenanceRateFixed", nothing))
                reopt_inputs["PV"]["om_cost_per_kw"] = tech_data["ProposedAssetOption.operationsAndMaintenanceRateFixed"]["value"]
            end
            # If there is existing PV identified above, the PV.production_factor_series would currently be assigned to that Curve GenerationProfile
            if !isnothing(get(tech_data, "ProposedPhotoVoltaicUnitOption.GenerationProfile", nothing))
                pv_profile_name = replace(split(tech_data["ProposedPhotoVoltaicUnitOption.GenerationProfile"], "::")[2], "'" => "")
                # Note, the Curve profile for PV is assumed to be in units of AC or normalized
                pv_curve_data = mgravens["Curve"][pv_profile_name]
                has_units = !isnothing(get(pv_curve_data, "Curve.y1Unit", nothing)) ? true : false
                fixed_size = get(reopt_inputs["PV"], "min_kw", 0.0) == get(reopt_inputs["PV"], "max_kw", 1e9) && get(reopt_inputs["PV"], "max_kw", 0.0) > 0.0
                pv_profile_list_of_dict = pv_curve_data["Curve.CurveDatas"]
                if !(length(pv_profile_list_of_dict) == 8760 * convert(Int64, reopt_inputs["Settings"]["time_steps_per_hour"]))
                    throw(@error("PV profile $pv_profile_name Curve.CurveDatas must be the same length as the load profile"))
                elseif has_units && !fixed_size
                    # If the PV system size is not fixed, we cannot normalize the W/kW production profile because we don't know the size
                    throw(@error("PV profile $pv_profile_name Curve.CurveDatas must be normalized if the PV size is not fixed"))
                elseif has_units && fixed_size
                    # Assume Watts if it has units, and multiplier of 1000 for kW if it has a value1Multiplier
                    units_multiplier = !isnothing(get(pv_curve_data, "Curve.y1Multiplier", nothing)) ? 1.0 : 1000.0
                    reopt_inputs["PV"]["production_factor_series"] = build_timeseries_array(pv_profile_list_of_dict, "CurveData.y1value", timestep_sec) / reopt_inputs["PV"]["min_kw"] / units_multiplier
                else
                    # If existing PV, especially large PV, could instead just use that production profile that's already written to reopt_inputs["PV"]["production_factor_series"] above
                    @info "Using ProposedPhotoVoltaicUnitOption.GenerationProfile for PV production_factor_series (normalized), instead of possibly large existing PV generation profile"
                    reopt_inputs["PV"]["production_factor_series"] = build_timeseries_array(pv_profile_list_of_dict, "CurveData.y1value", timestep_sec)
                end
            end
        elseif tech_data["Ravens.cimObjectType"] == "ProposedBatteryUnitOption"
            push!(techs_to_include, "ElectricStorage")
            # Optional inputs for ElectricStorage; only update if included in MG-Ravens inputs, otherwise rely on MG-Ravens default or REopt default
            if !isnothing(get(tech_data, "ProposedBatteryUnitOption.energyCapacityFixed", nothing))
                reopt_inputs["ElectricStorage"]["min_kwh"] = get_value_in_kw(tech_data["ProposedBatteryUnitOption.energyCapacityFixed"])
                reopt_inputs["ElectricStorage"]["max_kwh"] = get_value_in_kw(tech_data["ProposedBatteryUnitOption.energyCapacityFixed"])
            else
                if !isnothing(get(tech_data, "ProposedBatteryUnitOption.energyCapacityMin", nothing))
                    reopt_inputs["ElectricStorage"]["min_kwh"] = get_value_in_kw(tech_data["ProposedBatteryUnitOption.energyCapacityMin"])
                end
                if !isnothing(get(tech_data, "ProposedBatteryUnitOption.energyCapacityMax", nothing))
                    reopt_inputs["ElectricStorage"]["max_kwh"] = get_value_in_kw(tech_data["ProposedBatteryUnitOption.energyCapacityMax"])
                end
            end
            if !isnothing(get(tech_data, "ProposedEnergyProducerOption.powerCapacityFixed", nothing))
                reopt_inputs["ElectricStorage"]["min_kw"] = get_value_in_kw(tech_data["ProposedEnergyProducerOption.powerCapacityFixed"])
                reopt_inputs["ElectricStorage"]["max_kw"] = get_value_in_kw(tech_data["ProposedEnergyProducerOption.powerCapacityFixed"])
            else
                if !isnothing(get(tech_data, "ProposedEnergyProducerOption.powerCapacityMin", nothing))
                    reopt_inputs["ElectricStorage"]["min_kw"] = get_value_in_kw(tech_data["ProposedEnergyProducerOption.powerCapacityMin"])
                end
                if !isnothing(get(tech_data, "ProposedEnergyProducerOption.powerCapacityMax", nothing))
                    reopt_inputs["ElectricStorage"]["max_kw"] = get_value_in_kw(tech_data["ProposedEnergyProducerOption.powerCapacityMax"])
                end
            end          
            if !isnothing(get(tech_data, "ProposedAssetOption.variablePrice", nothing))
                reopt_inputs["ElectricStorage"]["installed_cost_per_kw"] = tech_data["ProposedAssetOption.variablePrice"]["value"]
                # Assume replacement cost is 50% of first cost, and replacement happens at half way through the analysis period years
                # reopt_inputs["ElectricStorage"]["replace_cost_per_kw"] = 0.5 * reopt_inputs["ElectricStorage"]["installed_cost_per_kw"]
                # reopt_inputs["ElectricStorage"]["inverter_replacement_year"] = convert(Int64, floor(0.5 * reopt_inputs["Financial"]["analysis_years"], digits=0))
            end
            if !isnothing(get(tech_data, "ProposedBatteryUnitOption.variablePriceEnergy", nothing))
                reopt_inputs["ElectricStorage"]["installed_cost_per_kwh"] = tech_data["ProposedBatteryUnitOption.variablePriceEnergy"]["value"]
                # reopt_inputs["ElectricStorage"]["replace_cost_per_kwh"] = 0.5 * reopt_inputs["ElectricStorage"]["installed_cost_per_kwh"]
                # reopt_inputs["ElectricStorage"]["battery_replacement_year"] = convert(Int64, floor(0.5 * reopt_inputs["Financial"]["analysis_years"], digits=0))
            end
            if !isnothing(get(tech_data, "ProposedBatteryUnitOption.stateOfChargeMin", nothing))
                reopt_inputs["ElectricStorage"]["soc_min_fraction"] = tech_data["ProposedBatteryUnitOption.stateOfChargeMin"] / 100.0
            end
            if !isnothing(get(tech_data, "ProposedBatteryUnitOption.chargeEfficiency", nothing))
                reopt_inputs["ElectricStorage"]["rectifier_efficiency_fraction"] = tech_data["ProposedBatteryUnitOption.chargeEfficiency"] / 100.0
            end
            if !isnothing(get(tech_data, "ProposedBatteryUnitOption.dischargeEfficiency", nothing))
                reopt_inputs["ElectricStorage"]["inverter_efficiency_fraction"] = tech_data["ProposedBatteryUnitOption.dischargeEfficiency"] / 100.0
            end
            # Since REopt has rectifier, internal, and inverter efficiencies, assign charge to rectifier, discharge to inverter, and internal to 1.0
            if !isnothing(get(tech_data, "ProposedBatteryUnitOption.chargeEfficiency", nothing)) && !isnothing(get(tech_data, "ProposedBatteryUnitOption.dischargeEfficiency", nothing))
                reopt_inputs["ElectricStorage"]["internal_efficiency_fraction"] = 1.0     
            end
            # Update min capacities and costs in case the proposed minimum battery size is larger than the existing and cost inputs differ from default
            if "BatteryUnit" in existing_mg_asset_types
                reopt_inputs["ElectricStorage"]["min_kw"] = max(existing_battery_kw, get(reopt_inputs["ElectricStorage"], "min_kw", 0.0))
                reopt_inputs["ElectricStorage"]["min_kwh"] = max(existing_battery_kwh, get(reopt_inputs["ElectricStorage"], "min_kwh", 0.0))
                if !(updated_battery_cost_with_existing)
                    lumped_const_power_fraction = 0.5
                    lumped_const_ref_kw = 1800.0
                    lumped_const_ref_kwh = 7200.0                
                    installed_cost_per_kw = copy(reopt_inputs["ElectricStorage"]["installed_cost_per_kw"])
                    installed_cost_per_kwh = copy(reopt_inputs["ElectricStorage"]["installed_cost_per_kwh"])
                    # TODO this might already be negative from existing battery calc above, so we are actually reducing the per_kw and per_kwh costs here
                    installed_cost_constant = copy(reopt_inputs["ElectricStorage"]["installed_cost_constant"])
                    reopt_inputs["ElectricStorage"]["installed_cost_per_kw"] = (installed_cost_per_kw * lumped_const_ref_kw + lumped_const_power_fraction * installed_cost_constant) / lumped_const_ref_kw
                    reopt_inputs["ElectricStorage"]["installed_cost_per_kwh"] = (installed_cost_per_kwh * lumped_const_ref_kwh + lumped_const_power_fraction * installed_cost_constant) / lumped_const_ref_kwh                
                    cost_update(kw, kwh) = kw * reopt_inputs["ElectricStorage"]["installed_cost_per_kw"] + kwh * reopt_inputs["ElectricStorage"]["installed_cost_per_kwh"]
                    reopt_inputs["ElectricStorage"]["installed_cost_constant"] = -cost_update(existing_battery_kw, existing_battery_kwh)
                end
            end
        end
    end

    non_tech_keys = ["Site", "ElectricLoad", "ElectricTariff", "ElectricUtility", "Financial", "Settings"]

    # Remove technologies that are in the base mgravens_fields_defaults.json file that are not included in this analysis scenario
    println("Techs to include: $techs_to_include")
    for key in keys(reopt_inputs)
        if !(key in non_tech_keys) && !(key in techs_to_include)
            pop!(reopt_inputs, key)
        end
    end

    return reopt_inputs
end


"""
    update_mgravens_with_reopt_results!(reopt_results::Dict, mgravens::Dict, reopt_inputs::Dict)

Update the MG-Ravens data structure with results from REopt.

# Arguments
- `reopt_results::Dict`: Dictionary containing the results from REopt optimization.
- `mgravens::Dict`: Dictionary representing the MG-Ravens data structure to be updated.
- `inputs::REoptInputs`: The REopt inputs used for the optimization, which may contain additional information needed for the update.

# Description
This function updates the MG-Ravens data structure with REopt results by:
1. Adding warning and error messages to the "Message" section.
2. Creating or updating the "Group.ProposedAssetSet" and "Group.EstimatedCost" sections for both Business-As-Usual (BAU) and Optimal scenarios.
3. Populating technology-specific outputs for PV and ElectricStorage, including their capacities, costs, and dispatch curves.

# Notes
- The function assumes that the MG-Ravens data structure follows a specific schema.
- It handles both BAU and Optimal scenarios, ensuring that lifecycle costs and other financial metrics are correctly mapped.
- Technology-specific outputs are added only for technologies included in the REopt results.

# Returns
- The `mgravens` dictionary is updated in-place.
"""
function update_mgravens_with_reopt_results!(reopt_results::Dict, mgravens::Dict, reopt_inputs::Dict)
    # Convert from REopt --> MG-Ravens outputs and update or add fields to MG-Ravens data .json
    # We are NOT creating a separate mgravens.json - only adding or maybe updating values (but mostly adding)
    # Three main sections we are adding: 1) "Group.ProposedAssetSet.[BAU and Optimal]", 2) Group.EstimatedAssetCosts.[BAU and Optimal], and 
    #  3) ProposedAssets.[Each Technology]

    # Add any warning or error messages in the top-level "Message" list of dictionaries
    if isnothing(get(reopt_results, "Messages", nothing))
        reopt_results["Messages"] = Dict("warnings" => "", "errors" => "")
    end

    mgravens["Message"] =  [
        Dict(
          "IdentifiedObject.mRID" => string(uuid4()),
          "Ravens.cimObjectType" => "Warning",
          "Message.message" => string(reopt_results["Messages"]["warnings"]),
          "Message.Application" => "Application::'REopt'"
        ),
        Dict(
            "IdentifiedObject.mRID" => string(uuid4()),
            "Ravens.cimObjectType" => "Error",
            "Message.message" => string(isempty(reopt_results["Messages"]["errors"]) ? "" : reopt_results["Messages"]["errors"]),
            "Message.Application" => "Application::'REopt'"
          ),
    ]

    # Start by adding the output/results Dicts, if needed
    if !("EstimatedCost" in keys(mgravens))
        mgravens["EstimatedCost"] = Dict{String, Any}()
    end

    if !("ProposedAssetSet" in keys(mgravens["Group"]))
        mgravens["Group"]["ProposedAssetSet"] = Dict{String, Any}()
    end

    # Create Group.ProposedAssetSet and EstimatedCost for BAU and Optimal
    scenario_names = ["BusinessAsUsual", "Optimal"]

    # ProposedAssetSet will also get populated with the list of ProposedAssetSet.ProposedAssets depending on which technologies were included
    for scenario_name in scenario_names
        proposed_asset_set_uuid = string(uuid4())
        mgravens["Group"]["ProposedAssetSet"][scenario_name] = Dict{String, Any}(
            "IdentifiedObject.name"=> scenario_name,
            "IdentifiedObject.mRID"=> proposed_asset_set_uuid,
            "Ravens.cimObjectType"=> "ProposedAssetSet",
            "ProposedAssetSet.ProposedAssets"=> [],
            "ProposedAssetSet.Application" => "Application::'REopt'",
            "ProposedAssetSet.EstimatedCost" => "EstimatedCost::'$scenario_name'"
        )

        # Scenario total lifecycle costs
        bau_suffix = ""  # blank for optimal scenario
        npv = 0.0  # 0.0 for BAU
        lcc_capital_costs = 0.0  # 0.0 for BAU
        if scenario_name == "BusinessAsUsual"
            bau_suffix = "_bau"
        else
            npv = reopt_results["Financial"]["npv"]
            lcc_capital_costs = reopt_results["Financial"]["lifecycle_capital_costs"]
        end

        # Include demand charges and coincident peak charges in the capacity cost
        capacity_cost = (reopt_results["ElectricTariff"]["lifecycle_demand_cost_after_tax"*bau_suffix] + 
                        reopt_results["ElectricTariff"]["lifecycle_coincident_peak_cost_after_tax"*bau_suffix])
            
        estimated_asset_costs_uuid = string(uuid4())
        mgravens["EstimatedCost"][scenario_name] = Dict{String, Any}(
            "IdentifiedObject.name" => scenario_name,
            "IdentifiedObject.mRID" => estimated_asset_costs_uuid,
            "Ravens.cimObjectType" => "EstimatedCost",
            "EstimatedCost.lifecycleCapacityCost" => cost_template(capacity_cost),
            "EstimatedCost.lifecycleEnergyCost" => cost_template(reopt_results["ElectricTariff"]["lifecycle_energy_cost_after_tax"*bau_suffix]),
            "EstimatedCost.lifecycleCapitalCost" => cost_template(lcc_capital_costs),
            "EstimatedCost.lifecycleCost" => cost_template(reopt_results["Financial"]["lcc"*bau_suffix]),
            "EstimatedCost.netPresentValue" => cost_template(npv)
        )
    end


    # Technology-specific outputs; need to append possible_techs once more are added to the mg-ravens conversions
    possible_techs = [("PV", "REopt_PV"), ("ElectricStorage", "REopt_ESS")]
    tech_names = []
    for tech in possible_techs
        if tech[1] in keys(reopt_results)
            append!(tech_names, [tech[2]])
        end
    end

    # Find the unique tech names that associate with the different possible techs
    ravens_tech_names = keys(mgravens["ProposedAssetOption"]["ProposedEnergyProducerOption"])
    tech_name_map = Dict(map[1] => "" for map in possible_techs)
    for tech in ravens_tech_names
        tech_data = mgravens["ProposedAssetOption"]["ProposedEnergyProducerOption"][tech]
        if tech_data["Ravens.cimObjectType"] == "ProposedPhotoVoltaicUnitOption"
            tech_name_map["PV"] = tech
        elseif tech_data["Ravens.cimObjectType"] == "ProposedBatteryUnitOption"
            tech_name_map["ElectricStorage"] = tech
        end
    end

    # This loop is associating all technologies with the Optimal scenario only, as indicated by "ProposedAsset.EstimatedCost": "EstimatedCost::"*scenario_name[2]
    for (i, name) in enumerate(tech_names)

        if !("ProposedAsset" in keys(mgravens))
            mgravens["ProposedAsset"] = Dict{String, Any}()
        end
        
        # Filling in results for each technology
        proposed_asset_uuid = string(uuid4())
        proposed_asset_template = Dict{String, Any}(
            "IdentifiedObject.name" => name,
            "IdentifiedObject.mRID" => proposed_asset_uuid,
            "Ravens.cimObjectType" => "",  # To be filled in depending on which technology type
            "ProposedAsset.ProposedAssetOption" => "",
            "ProposedAsset.EstimatedCost" => "EstimatedCost::'"*scenario_names[2]*"'",
        )

        if occursin("PV", name)
            # Add PV stuff
            append!(mgravens["Group"]["ProposedAssetSet"][scenario_names[2]]["ProposedAssetSet.ProposedAssets"], ["ProposedEnergyProducerAsset::'$name'"])
            proposed_asset_template["ProposedEnergyProducerAsset.capacity"] = Dict(
                "value" => reopt_results["PV"]["size_kw"],
                "unit" => "UnitSymbol.W",
                "multiplier" => "UnitMultiplier.k"
            )
            proposed_asset_template["Ravens.cimObjectType"] = "ProposedEnergyProducerAsset"
            proposed_asset_template["ProposedAsset.ProposedAssetOption"] = "ProposedPhotoVoltaicUnitOption::'"*tech_name_map["PV"]*"'"

            if isnothing(get(mgravens["Curve"], "PVProfile_REopt", nothing))
                mgravens["Curve"]["PVProfile_REopt"] = Dict{String, Any}(
                    "IdentifiedObject.name" => "PVProfile_REopt",
                    "IdentifiedObject.mRID" => string(uuid4()),
                    "Ravens.cimObjectType" => "Curve",
                    "Curve.xUnit" => "UnitSymbol.h",
                    "Curve.CurveDatas" => []
                    )
                for ts in 1:(8760 * convert(Int64, reopt_inputs["Settings"]["time_steps_per_hour"]))
                    append!(mgravens["Curve"]["PVProfile_REopt"]["Curve.CurveDatas"], 
                        [Dict("CurveData.xvalue" => ts-1, "CurveData.y1value" => reopt_results["PV"]["production_factor_series"][ts])])
                end
            end
            # TODO add reference to Curve::PVProfile_REopt that was just created above
        elseif occursin("ESS", name)
            # Add Battery stuff
            append!(mgravens["Group"]["ProposedAssetSet"][scenario_names[2]]["ProposedAssetSet.ProposedAssets"], ["ProposedBatteryUnit::'$name'"])
            proposed_asset_template["Ravens.cimObjectType"] = "ProposedBatteryUnit"
            proposed_asset_template["ProposedAsset.ProposedAssetOption"] = "ProposedBatteryUnitOption::'"*tech_name_map["ElectricStorage"]*"'"
            proposed_asset_template["ProposedEnergyProducerAsset.capacity"] = Dict(
                "value" => reopt_results["ElectricStorage"]["size_kw"],
                "unit" => "UnitSymbol.W",
                "multiplier" => "UnitMultiplier.k"
            )
            proposed_asset_template["ProposedBatteryUnit.energyCapacity"] = Dict(
                "value" => reopt_results["ElectricStorage"]["size_kwh"],
                "unit" => "UnitSymbol.Wh",
                "multiplier" => "UnitMultiplier.k"
            )
        end

        mgravens["ProposedAsset"][name] = proposed_asset_template
    end   
end


function cost_template(value)
        return Dict([
          "unit" => "Currency.USD",
          "value" => value
        ])
end

# THIS FUNCTION WAS COPIED FROM REOPT.JL UTILS.JL
"""
    get_monthly_time_steps(year::Int; time_steps_per_hour=1)

return Array{Array{Int64,1},1}, size = (12,)
"""
function get_monthly_time_steps(year::Int; time_steps_per_hour=1)
    a = Array[]
    i = 1
    for m in range(1, stop=12)
        n_days = daysinmonth(Date(string(year) * "-" * string(m)))
        stop = n_days * 24 * time_steps_per_hour + i - 1
        if m == 12 && isleapyear(year)
            stop -= 24 * time_steps_per_hour
        end
        steps = [step for step in range(i, stop=stop)]
        append!(a, [steps])
        i = stop + 1
    end
    return a
end