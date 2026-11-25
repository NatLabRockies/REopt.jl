# Really only meaningful incentives for PV for relevant techs; none for battery, couple for fuel cells
# The program description sometimes describes that the parameters do not fully define the program constraints, 
# e.g. the DC production incentive of $0.5/kWh has a tiered value after 2023, and only applies to 10 kW or less, but
# the parameter_set_id does not have a parameter of source=System, qualifier=max, and units=kW
# Assuming the incentives are state based, as opposed to utility-based - may have tax implications

# ONLY TX has a somewhat competitive capacity-based vs production-based Value
# Most states only have one or the other, and if they do have both, the production is typically the best by far
# Some states have different sizing classes for incentives, but I think that can be done with multiply REopt runs

# Some states have a 100% of cost incentive, which is not realistic so need to look into those

# Net metering - this assigns net metering, but only if it's available state-wide, and
# assigns an arbitrary high net metering limit (kW) because there is no parameter_set for net metering

# TODO these data from DSIRE are not directly used in REopt, but need to be post-processed
#   with the incentives to modify the REopt inputs, e.g. convert 
# max_percent_of_cost  # Convert to state_ibi_max (dollars) (how???)
# size_limit_basis_ac_or_dc   # If AC, convert to incentive per kW-DC based on AC/DC ratio


all_state_abbrev = ["AK", "AL", "AR", "AZ", "CA", "CO", "CT", 
                    "DC", "DE", "FL", "GA", "GU", "HI", "IA", "ID", "IL", "IN", 
                    "KS", "KY", "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MP", 
                    "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM", "NV", "NY", 
                    "OH", "OK", "OR", "PA", "PR", "RI", "SC", "SD", "TN", "TX", 
                    "UT", "VA", "VI", "VT", "WA", "WI", "WV", "WY"]

inputs_map = Dict("capacity_based" => Dict("capacity_based_incentive_per_kw" => "state_rebate_per_kw",
                                      "max_incentive_amount_dollar" => "state_rebate_max"),
                    "production_based" => Dict("production_based_incentive_per_kwh" => "production_incentive_per_kwh",
                                                "production_incentive_years" => "production_incentive_years",
                                                "max_kw" => "production_incentive_max_kw"),
                    "percent_based" => Dict("percent_cost_based_incentive" => "state_ibi_fraction",
                                            "max_incentive_amount_dollar" => "state_ibi_max"))

# TODO loop across all techs
function get_incentives_scenarios(reopt_inputs::Dict; state_abbr::String="", tech::String="", inputs_map::Dict=inputs_map)
    db = SQLite.DB(joinpath(dirname(@__FILE__), "..", "..", "data", "incentives", "DSIRE.db"))
    reopt_inputs_to_assign = Dict()
    can_net_meter = false
    possible_techs = ["PV", "ElectricStorage", "FuelCellsNonRenewable", "FuelCellsRenewable", "Wind"]
    # try
    state_incentive_program_data = get_incentive_data(db; state_abbr=state_abbr, tech=tech)
    if state_incentive_program_data["can_net_meter"]
        can_net_meter = true
    end
    for program in setdiff(keys(state_incentive_program_data), ["can_net_meter"])
        basis = ""
        count = 0
        # Find the basis of the program
        for key in keys(state_incentive_program_data[program])
            if occursin("capacity", key)
                basis = "capacity"
                count += 1
            elseif occursin("production", key)
                basis = "production"
                count += 1
            elseif occursin("percent", key)
                basis = "percent"
                count += 1
            end
        end
        # TODO find the highest value program if multiple of the same type
        # if count > 1
        #     # Multiple programs of the same type, find the max value
        #     best_program = program
        #     for key in keys(state_incentive_program_data[program])
        reopt_inputs_to_assign[basis] = Dict()
        if !isempty(basis)
            # Assign REopt inputs from DSIRE.db data for that program
            program_data = inputs_map[basis*"_based"]
            reopt_inputs_to_assign[basis]["incentive_program_name"] = state_incentive_program_data[program]["name"] 
            for key in keys(program_data)
                if key in setdiff(keys(state_incentive_program_data[program]), ["name"])
                    # Skipping unused keys for now
                    reopt_inputs_to_assign[basis][program_data[key]] = state_incentive_program_data[program][key]
                    if occursin("based_incentive", key)
                        reopt_inputs_to_assign[basis]["type"] = key
                        reopt_inputs_to_assign[basis]["value"] = state_incentive_program_data[program][key]
                    end
                end
            end
        end
    end
    # catch e
    #     println("Errored on state = ", state_abbr)
    #     println(showerror(stdout, e))
    #     # or 
    #     # println(e.msg)
    # end

    reopt_inputs_scenarios = Dict() 
    for basis in keys(reopt_inputs_to_assign)
        reopt_inputs_scenarios[basis] = deepcopy(reopt_inputs)
        reopt_inputs_scenarios[basis]["incentive_program_name"] = reopt_inputs_to_assign[basis]["incentive_program_name"]
        reopt_inputs_scenarios[basis]["type"] = reopt_inputs_to_assign[basis]["type"]
        reopt_inputs_scenarios[basis]["value"] = reopt_inputs_to_assign[basis]["value"]
        for input in keys(reopt_inputs_to_assign[basis])
            reopt_inputs_scenarios[basis][tech][input] = reopt_inputs_to_assign[basis][input]
        end
        # By default, even if a tech "can_net_meter", the net_metering_limit_kw is zero, so need to increase that if can_net_meter
        if can_net_meter
            reopt_inputs_scenarios[basis][tech]["can_net_meter"] = can_net_meter  # Just to make sure it's true even though some techs default to true
            if haskey(reopt_inputs_scenarios[basis], "ElectricUtility")
                # TODO replace big number 1.0E9 with a practical limit like 5 MW which is the max for all states - however, this makes it harder to solve sometimes
                reopt_inputs_scenarios[basis]["ElectricUtility"]["net_metering_limit_kw"] = 1.0E9
            else
                reopt_inputs_scenarios[basis]["ElectricUtility"] = Dict("net_metering_limit_kw" => 1.0E9)
            end
        end
    end

    # Report if net metering was enabled from DSIRE, for knowledge
    reopt_inputs_scenarios["net_metering_from_dsire"] = can_net_meter ? "true" : "false"

    return reopt_inputs_scenarios
end

function get_incentive_data(db::SQLite.DB; state_abbr::String="", tech::String="")
    # Filter incentives database by technology and state, only keeping state-wide and non-expired incentives
    tech_map = Dict("PV" => 7, "ElectricStorage" => 207, "FuelCellsNonRenewable" => 15, "FuelCellsRenewable" => 124, "Wind" => 8)
    tech_number = tech_map[tech]
    state = DBInterface.execute(db, "SELECT * FROM state WHERE abbreviation='$state_abbr'") |> DataFrame
    state_id = state[1,1]
    todays_date = Dates.today()
    todays_date_str = Dates.format(todays_date, "yyyymmdd")
    state_programs = DBInterface.execute(db, "SELECT * FROM program WHERE (state_id=$state_id) 
        AND (is_entire_state=1)
        AND ((end_date > $todays_date_str) OR (end_date IS NULL))") |> DataFrame
    net_metering = "Net Metering" in state_programs[!, "name"]
    # TODO CA, AZ, and UT, as well as recently AL, TN, and SD have net billing instead of net metering, so 
    #   ideally we'd assign a wholesale_rate equal to the avoided electricity cost credit those states would receive
    if ismissing(net_metering)
        net_metering = true
    end
    tech_programs = DBInterface.execute(db, "SELECT * FROM program_technology WHERE technology_id=$tech_number") |> DataFrame
    tech_state_program_ids = intersect(state_programs[!,"id"],tech_programs[!,"program_id"])
    tech_state_program_ids_tuple = tuple(tech_state_program_ids...)
    parameter_set = sql_select_helper_variable_length(db; table_name="parameter_set", column_name="program_id", data_tuple=tech_state_program_ids_tuple)
    parameter_set_technology = DBInterface.execute(db, "SELECT * FROM parameter_set_technology WHERE technology_id=$tech_number") |> DataFrame
    tech_state_parameter_set = intersect(parameter_set[!,"id"], parameter_set_technology[!,"set_id"])
    parameter_set_ids_tuple = tuple(tech_state_parameter_set...)
    parameters = sql_select_helper_variable_length(db; table_name="parameter", column_name="parameter_set_id", data_tuple=parameter_set_ids_tuple)

    data = Dict()
    data["can_net_meter"] = net_metering
    for set_id in unique(parameters[!, "parameter_set_id"])
        program_id = parameter_set[parameter_set[!, "id"].==set_id, "program_id"][1]
        data[program_id] = Dict()
        data[program_id]["name"] = state_programs[state_programs[!, "id"].==program_id, "name"][1]
        param_sub = parameters[parameters.parameter_set_id.==set_id, :]
        for param in eachrow(param_sub)
            if !ismissing(param["units"]) && !ismissing(param["source"])
                if occursin("kWh", param["units"]) || occursin("MWh", param["units"])
                    # Production based incentive
                    divide_by = 1.0
                    if occursin("MWh", param["units"])
                        divide_by = 1000.0
                    end
                    data[program_id]["production_based_incentive_per_kwh"] = param["amount"] / divide_by
                    if occursin("year", param["units"])
                        # Limited number of years of production incentive
                        for i in 1:30
                            if occursin("i", param["units"])
                                data[program_id]["production_incentive_years"] = i
                                break
                            end
                        end
                    end
                elseif occursin(r"\$/W", param["units"]) || occursin(r"\$/kW", param["units"])
                    # Capacity-based incentive ($/kW), could be AC or DC basis
                    if occursin(r"\$/W", param["units"])
                        incentive_per_kw = param["amount"] * 1000.0
                    else
                        incentive_per_kw = param["amount"]
                    end
                    data[program_id]["capacity_based_incentive_per_kw"] = incentive_per_kw
                    if occursin("AC", param["units"])
                        data[program_id]["capacity_based_incentive_basis_ac_or_dc"] = "AC"
                    else
                        data[program_id]["capacity_based_incentive_basis_ac_or_dc"] = "DC"
                    end
                elseif ismissing(param["qualifier"]) && occursin(r"\%", param["units"])
                    # %-based incentives
                    data[program_id]["percent_cost_based_incentive"] = param["amount"] / 100.0  # Fraction
                elseif param["source"] == "System"
                    # Size limits (min/max kW), could be AC or DC basis
                    divide_by = 1000.0  # For W (Watts)
                    if occursin("kW", param["units"])
                        divide_by = 1.0
                    elseif occursin("MW", param["units"])
                        divide_by = 0.001
                    end
                    if param["qualifier"] == "max"
                        data[program_id]["max_kw"]= param["amount"] / divide_by
                    elseif param["qualifier"] == "min"
                        data[program_id]["min_kw"] = param["amount"] / divide_by
                    end
                    if occursin("AC", param["units"])
                        data[program_id]["size_limit_basis_ac_or_dc"] = "AC"
                    else
                        data[program_id]["size_limit_basis_ac_or_dc"] = "DC"
                    end
                elseif !ismissing(param["qualifier"])
                    if param["source"] == "Incentive" && param["units"] == "\$"
                        # Max incentive value in $; some have NULL for qualifier but we can't know if it's max or min, so ignoring those
                        if param["qualifier"] == "max" 
                            data[program_id]["max_incentive_amount_dollar"] = param["amount"]
                        elseif param["qualifier"] == "min"
                            data[program_id]["min_incentive_amount_dollar"] = param["amount"]
                        end
                    elseif param["qualifier"] == "max" && occursin(r"\%", param["units"])
                        # Max incentive as a percentage of cost
                        data[program_id]["max_percent_of_cost"] = param["amount"]
                    end                        
                end
            end
        end
    end

    for program_id in keys(data)
        useful_data = ["capacity_based_incentive_per_kw", "production_based_incentive_per_kwh", "percent_cost_based_incentive"]
        has_useful_data = length(intersect(useful_data, keys(data[program_id]))) >= 1
        if !(program_id == "can_net_meter")
            if isempty(data[program_id])
                delete!(data, program_id)
            elseif !has_useful_data
                delete!(data, program_id)
            elseif haskey(data[program_id], "percent_cost_based_incentive")
                if data[program_id]["percent_cost_based_incentive"] > 0.75
                    # Likely a tax exemption and not a percent of cost rebate
                    delete!(data, program_id)
                end
            end
        end
    end

    return data
end


function sql_select_helper_variable_length(db::SQLite.DB; table_name::String="", column_name::String="", data_tuple::Tuple=())
    if length(data_tuple) >= 2
        data_df = DBInterface.execute(db, "SELECT * FROM $table_name WHERE $column_name IN $data_tuple") |> DataFrame
    elseif length(data_tuple) == 1
        data_df = DBInterface.execute(db, "SELECT * FROM $table_name WHERE $column_name=$(data_tuple[1])") |> DataFrame
    else
        data_df = DBInterface.execute(db, "SELECT * FROM $table_name WHERE $column_name=1") |> DataFrame
        delete!(data_df, :)
    end
    return data_df
end
