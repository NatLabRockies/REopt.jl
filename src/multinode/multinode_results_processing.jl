# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function CalculateComputationTime(StartTime)
    # Function to calculate the elapsed time between a time (input into the function) and the current time
    EndTime = now()
    ComputationTime_milliseconds = EndTime - StartTime
    #print("The computation time in milliseconds is: $(ComputationTime_milliseconds)")

    if Dates.value(ComputationTime_milliseconds) > 1000
        ComputationTime_minutes = round(Dates.value(ComputationTime_milliseconds)/60000, digits=2)
    else
        ComputationTime_minutes = round(Dates.value(ComputationTime_milliseconds)/60000, digits=4)
    end

    return ComputationTime_milliseconds, ComputationTime_minutes
end


function Results_Processing_REopt_PMD_Model(m, results, data_math_mn, REoptInputs_Combined, Multinode_Inputs, timestamp, time_results; allow_upgrades=false, line_upgrade_options_each_line ="", BAU_case=false)
    
    if BAU_case == true
        BAU_indicator = "BAU_model_"
    else
        BAU_indicator = ""
    end
    
    # Extract the PMD results
    print("\n Reading the PMD results")
    Start_reading_PMD_results = now()
    sol_math = results["solution"]
    # The PMD results are saved to the sol_eng variable
    sol_eng = PowerModelsDistribution.transform_solution(sol_math, data_math_mn)
    milliseconds, time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"reading_PMD_results_minutes"] = CalculateComputationTime(Start_reading_PMD_results)

    # Extract the REopt results
    print("\n Reading the REopt results \n")
    Start_reading_REopt_results = now()
    REopt_results = reopt_results(m, REoptInputs_Combined)
    print("\n Completed reading the REopt results \n")

    # Process the line upgrade results
    if allow_upgrades == true && Multinode_Inputs.model_line_upgrades == true
        line_upgrades = Process_Line_Upgrades(m, line_upgrade_options_each_line, Multinode_Inputs, timestamp)
    else
        line_upgrades = "N/A"
    end

    # Generate inputs that will be used for the multinode outage simulator
    if Multinode_Inputs.run_outage_simulator
        print("\n Generating inputs for the outage simulator \n")
        DataDictionaryForEachNodeForOutageSimulator = REopt.GenerateInputsForOutageSimulator(Multinode_Inputs, REopt_results, REoptInputs_Combined)
        print("\n Completed generating inputs for the outage simulator \n")
    else
        DataDictionaryForEachNodeForOutageSimulator = "N/A"
    end

    if Multinode_Inputs.model_subtype == "SOCNLPUBFPowerModel" 
        pf_name = "Pf"
        qf_name = "Qf"
    else # if Multinode_Inputs.model_subtype == "LPUBFDiagPowerModel" 
        pf_name = "pf"
        qf_name = "qf"
    end

    # Compute values for each line and store line power flows in a dataframe and dictionary 
    line_names = collect(keys(sol_eng["nw"]["1"]["line"]))
    n_lines = length(line_names)
    n_timesteps = length(sol_eng["nw"])
    is_nfa = Multinode_Inputs.model_subtype == "NFAUPowerModel"

    # Preallocate the per-line summary columns; one row per line
    col_Line = Vector{String}(undef, n_lines)
    col_min_active  = Vector{Any}(undef, n_lines)
    col_max_active  = Vector{Any}(undef, n_lines)
    col_avg_active  = Vector{Any}(undef, n_lines)
    col_min_react   = Vector{Any}(undef, n_lines)
    col_max_react   = Vector{Any}(undef, n_lines)
    col_avg_react   = Vector{Any}(undef, n_lines)

    PMD_Dictionary_LineFlow_Power_Series = Dict{String, Dict{String, Any}}()
    print("\n Storing the line flow data in PMD")
    for (line_idx, line) in enumerate(line_names)
        # Preallocate per-timestep vectors for this line
        ActivePowerFlow_line_temp   = Vector{Float64}(undef, n_timesteps)
        ReactivePowerFlow_line_temp = is_nfa ? Vector{Any}(fill("N/A", n_timesteps)) : Vector{Float64}(undef, n_timesteps)

        ActivePowerFlow_line_Phase1_temp   = Float64[]
        ActivePowerFlow_line_Phase2_temp   = Float64[]
        ActivePowerFlow_line_Phase3_temp   = Float64[]
        ReactivePowerFlow_line_Phase1_temp = is_nfa ? Any[] : Float64[]
        ReactivePowerFlow_line_Phase2_temp = is_nfa ? Any[] : Float64[]
        ReactivePowerFlow_line_Phase3_temp = is_nfa ? Any[] : Float64[]

        for i in 1:n_timesteps
            line_pf = sol_eng["nw"][string(i)]["line"][line][pf_name]
            ActivePowerFlow_line_temp[i] = sum(line_pf[Phase] for Phase in keys(line_pf))
            if !is_nfa
                line_qf = sol_eng["nw"][string(i)]["line"][line][qf_name]
                ReactivePowerFlow_line_temp[i] = sum(line_qf[Phase] for Phase in keys(line_qf))
            end
        end

        # Pull data from the first time step
        first_step_phases = keys(sol_eng["nw"]["1"]["line"][line][pf_name])
        # Preallocate the per-phase vectors (based on the phases that actually exist)
        if 1 in first_step_phases
            resize!(ActivePowerFlow_line_Phase1_temp, n_timesteps)
            is_nfa || resize!(ReactivePowerFlow_line_Phase1_temp, n_timesteps)
        end
        if 2 in first_step_phases
            resize!(ActivePowerFlow_line_Phase2_temp, n_timesteps)
            is_nfa || resize!(ReactivePowerFlow_line_Phase2_temp, n_timesteps)
        end
        if 3 in first_step_phases
            resize!(ActivePowerFlow_line_Phase3_temp, n_timesteps)
            is_nfa || resize!(ReactivePowerFlow_line_Phase3_temp, n_timesteps)
        end
        for phase in first_step_phases
            if phase == 1
                for i in 1:n_timesteps
                    ActivePowerFlow_line_Phase1_temp[i] = sol_eng["nw"][string(i)]["line"][line][pf_name][phase]
                    if !is_nfa
                        ReactivePowerFlow_line_Phase1_temp[i] = sol_eng["nw"][string(i)]["line"][line][qf_name][phase]
                    end
                end
            elseif phase == 2
                for i in 1:n_timesteps
                    ActivePowerFlow_line_Phase2_temp[i] = sol_eng["nw"][string(i)]["line"][line][pf_name][phase]
                    if !is_nfa
                        ReactivePowerFlow_line_Phase2_temp[i] = sol_eng["nw"][string(i)]["line"][line][qf_name][phase]
                    end
                end
            elseif phase == 3
                for i in 1:n_timesteps
                    ActivePowerFlow_line_Phase3_temp[i] = sol_eng["nw"][string(i)]["line"][line][pf_name][phase]
                    if !is_nfa
                        ReactivePowerFlow_line_Phase3_temp[i] = sol_eng["nw"][string(i)]["line"][line][qf_name][phase]
                    end
                end
            else
                throw(@error("The phase number, $(phase), is invalid"))
            end
        end

        col_Line[line_idx]       = "Line "*string(line)
        col_min_active[line_idx] = round(minimum(ActivePowerFlow_line_temp), digits = 5)
        col_max_active[line_idx] = round(maximum(ActivePowerFlow_line_temp), digits = 5)
        col_avg_active[line_idx] = round(mean(ActivePowerFlow_line_temp),    digits = 5)

        if !is_nfa
            col_min_react[line_idx] = round(minimum(ReactivePowerFlow_line_temp), digits = 5)
            col_max_react[line_idx] = round(maximum(ReactivePowerFlow_line_temp), digits = 5)
            col_avg_react[line_idx] = round(mean(ReactivePowerFlow_line_temp),    digits = 5)
        else
            col_min_react[line_idx] = "N/A"
            col_max_react[line_idx] = "N/A"
            col_avg_react[line_idx] = "N/A"
        end

        PMD_Dictionary_LineFlow_Power_Series[line] = Dict{String, Any}(
            "ActiveLineFlow"           => ActivePowerFlow_line_temp,
            "ReactiveLineFlow"         => ReactivePowerFlow_line_temp,
            "Phase1_ActiveLineFlow"    => ActivePowerFlow_line_Phase1_temp,
            "Phase2_ActiveLineFlow"    => ActivePowerFlow_line_Phase2_temp,
            "Phase3_ActiveLineFlow"    => ActivePowerFlow_line_Phase3_temp,
            "Phase1_ReactiveLineFlow"  => ReactivePowerFlow_line_Phase1_temp,
            "Phase2_ReactiveLineFlow"  => ReactivePowerFlow_line_Phase2_temp,
            "Phase3_ReactiveLineFlow"  => ReactivePowerFlow_line_Phase3_temp,
        )
    end

    DataFrame_LineFlow = DataFrame(
        Line                          = col_Line,
        Minimum_LineFlow_ActivekW     = col_min_active,
        Maximum_LineFlow_ActivekW     = col_max_active,
        Average_LineFlow_ActivekW     = col_avg_active,
        Minimum_LineFlow_ReactivekVAR = col_min_react,
        Maximum_LineFlow_ReactivekVAR = col_max_react,
        Average_LineFlow_ReactivekVAR = col_avg_react,
    )

    print("\n Completed storing the line flow data in PMD")

    # Record the time for post-processing
    milliseconds, time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"reading_REopt_results_minutes"] = CalculateComputationTime(Start_reading_REopt_results)

    return REopt_results, sol_eng, DataDictionaryForEachNodeForOutageSimulator, PMD_Dictionary_LineFlow_Power_Series, DataFrame_LineFlow, line_upgrades
end


function Process_Line_Upgrades(m, line_upgrade_options_each_line, Multinode_Inputs, TimeStamp)

    line_keys = collect(keys(line_upgrade_options_each_line))
    n = length(line_keys)
    col_Line             = Vector{Any}(undef, n)
    col_Upgraded         = Vector{String}(undef, n)
    col_MaximumRatedAmps = Vector{Any}(undef, n)
    col_UpgradeCost      = Vector{Any}(undef, n)

    for (idx, line) in enumerate(line_keys)
        number_of_entries = length(line_upgrade_options_each_line[line]["max_amperage"])
        dv = "Bin"*line
        maximum_amps = sum(value.(m[Symbol(dv)][i])*line_upgrade_options_each_line[line]["max_amperage"][i] for i in 1:number_of_entries)
        upgraded_cost = round(value.(m[Symbol("line_cost")][line]), digits = 0)

        upgraded = Int(round(value.(m[Symbol(dv)][1]), digits=0)) != 1 ? "Yes" : "No"

        col_Line[idx]             = line
        col_Upgraded[idx]         = upgraded
        col_MaximumRatedAmps[idx] = maximum_amps
        col_UpgradeCost[idx]      = upgraded_cost
    end

    line_upgrade_results = DataFrame(
        Line             = col_Line,
        Upgraded         = col_Upgraded,
        MaximumRatedAmps = col_MaximumRatedAmps,
        UpgradeCost      = col_UpgradeCost,
    )

    return line_upgrade_results
end
 

function Results_Compilation(model, results, PMD_Results, Outage_Results, Multinode_Inputs, DataFrame_LineFlow_Summary, PMD_Dictionary_LineFlow_Power_Series, TimeStamp, start_time_entire_model; all_line_powerflow_results="", simple_powerflow_model_results="", bau_model = "", system_results_BAU = "", line_upgrade_results = "", transformer_upgrade_results = "", outage_simulator_time = "", data_eng = "")
      
    @info "Compiling the results"

    InputsList = Multinode_Inputs.REopt_inputs_list

    # Compute system-level outputs
    system_results = Dict{String, Any}() # Float64}()
    dataframes = Dict{String, Any}() # The dataframes of results (which can be saved to csv files by the user), which are returned from this function
    
    # Initialize the results variables
    total_lifecycle_capital_cost = 0 # includes replacements and incentives
    total_initial_capital_costs = 0
    total_initial_capital_costs_after_incentives = 0
    total_lifecycle_storage_capital_costs = 0
    line_upgrade_costs = 0
    total_PV_size_kw = 0
    total_PV_energy_produced_minus_curtailment_first_year = 0
    total_electric_storage_size_kw = 0
    total_electric_storage_size_kwh = 0
    total_generator_size_kw = 0

    for n in InputsList 
        node_temp = n["Site"]["node"]

        total_lifecycle_capital_cost = total_lifecycle_capital_cost + results[node_temp]["Financial"]["lifecycle_capital_costs"]
        total_initial_capital_costs = total_initial_capital_costs + results[node_temp]["Financial"]["initial_capital_costs"]
        total_initial_capital_costs_after_incentives = total_initial_capital_costs_after_incentives + results[node_temp]["Financial"]["initial_capital_costs_after_incentives"] 
        total_lifecycle_storage_capital_costs = total_lifecycle_storage_capital_costs + results[node_temp]["Financial"]["lifecycle_storage_capital_costs"]

        if "PV" in keys(results[node_temp])
            total_PV_size_kw = total_PV_size_kw + results[node_temp]["PV"]["size_kw"]
            total_PV_energy_produced_minus_curtailment_first_year = total_PV_energy_produced_minus_curtailment_first_year + 
                                                                    (results[node_temp]["PV"]["year_one_energy_produced_kwh"] - sum(results[node_temp]["PV"]["electric_curtailed_series_kw"]/Multinode_Inputs.time_steps_per_hour))
        end
        if "ElectricStorage" in keys(results[node_temp])
            total_electric_storage_size_kw = total_electric_storage_size_kw + results[node_temp]["ElectricStorage"]["size_kw"]
            total_electric_storage_size_kwh = total_electric_storage_size_kwh + results[node_temp]["ElectricStorage"]["size_kwh"]
        end
        if "Generator" in keys(results[node_temp])
            total_generator_size_kw = total_generator_size_kw + results[node_temp]["Generator"]["size_kw"]
        end
    end

    if Multinode_Inputs.model_line_upgrades
        line_upgrade_costs = value.(model[:total_line_upgrade_cost])
    else
        line_upgrade_costs = 0
    end

    system_results["total_lifecycle_cost"] = value.(model[Symbol("Costs")])
    system_results["total_lifecycle_capital_cost"] = total_lifecycle_capital_cost + line_upgrade_costs
    system_results["total_initial_capital_costs"] = total_initial_capital_costs + line_upgrade_costs
    system_results["total_initial_capital_costs_after_incentives"] =  total_initial_capital_costs_after_incentives + line_upgrade_costs # no incentives are modeled for line upgrades
    system_results["total_lifecycle_storage_capital_cost"] = total_lifecycle_storage_capital_costs
    system_results["total_line_upgrade_cost"] = line_upgrade_costs
    system_results["total_PV_size_kw"] = total_PV_size_kw
    system_results["total_PV_energy_produced_minus_curtailment_first_year"] = total_PV_energy_produced_minus_curtailment_first_year
    system_results["total_electric_storage_size_kw"] = total_electric_storage_size_kw
    system_results["total_electric_storage_size_kwh"] = total_electric_storage_size_kwh
    system_results["total_generator_size_kw"] = total_generator_size_kw
    
    if isa(system_results_BAU, AbstractDict) # The BAU results are a string ("" or "none") if the BAU case was not run or is the BAU case itself
        system_results["net_present_value"] = system_results_BAU["total_lifecycle_cost"] - value.(model[Symbol("Costs")])
    else
        system_results["net_present_value"] = "Not calculated"
    end

    if Multinode_Inputs.model_subtype != "NFAUPowerModel"
        if Multinode_Inputs.number_of_phases == 1
            DataFrame_BusVoltages_Summary, per_unit_voltages, minimum_voltage, average_voltage, maximum_voltage = VoltageResultsSummary(PMD_Results)
        else
            DataFrame_BusVoltages_Summary, voltage_summary_by_phase, minimum_voltage, average_voltage, maximum_voltage = VoltageResultsSummaryMultiphase(PMD_Results, data_eng)
        end
    end

    # Generate the dataframes of results (these are not saved to csv files by REopt; they are returned so that the user can save them)
    if system_results_BAU != ""
        try
            @info "Generating the dataframes of results"
            DataLabels = []
            Data = []
            
            LineFromSubstationToFacilityMeter = Multinode_Inputs.substation_line # "line"*Multinode_Inputs.substation_node * "_" * Multinode_Inputs.facilitymeter_node
            
            if Multinode_Inputs.model_type == "PowerModelsDistribution"

                PMD_MaximumPowerOnsubstation_line_ActivePower = (round(maximum(PMD_Dictionary_LineFlow_Power_Series[lowercase(LineFromSubstationToFacilityMeter)]["ActiveLineFlow"]), digits = 1))
                PMD_MinimumPowerOnsubstation_line_ActivePower = (round(minimum(PMD_Dictionary_LineFlow_Power_Series[lowercase(LineFromSubstationToFacilityMeter)]["ActiveLineFlow"]), digits = 1))
                PMD_AveragePowerOnsubstation_line_ActivePower = (round(mean(PMD_Dictionary_LineFlow_Power_Series[lowercase(LineFromSubstationToFacilityMeter)]["ActiveLineFlow"]), digits = 1))

                warning_PMD_MaximumPowerOnsubstation_line_ReactivePower = ""
                warning_PMD_MinimumPowerOnsubstation_line_ReactivePower = ""
           
                if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                    PMD_MaximumPowerOnsubstation_line_ReactivePower = (round(maximum(PMD_Dictionary_LineFlow_Power_Series[lowercase(LineFromSubstationToFacilityMeter)]["ReactiveLineFlow"]), digits = 6))
                    PMD_MinimumPowerOnsubstation_line_ReactivePower = (round(minimum(PMD_Dictionary_LineFlow_Power_Series[lowercase(LineFromSubstationToFacilityMeter)]["ReactiveLineFlow"]), digits = 6))
                    PMD_AveragePowerOnsubstation_line_ReactivePower = (round(mean(PMD_Dictionary_LineFlow_Power_Series[lowercase(LineFromSubstationToFacilityMeter)]["ReactiveLineFlow"]), digits = 6))
                    
                    # Generate warnings if the reactive power support from the substation is larger than 1 kW or smaller than -1 kW, because this is power that is not generated by REopt nodes (which is more relevant if the system is off-grid or the reactive power support occurs during a grid outage)
                    if PMD_MaximumPowerOnsubstation_line_ReactivePower >= 1
                        warning_PMD_MaximumPowerOnsubstation_line_ReactivePower = "Warning: greater than 1kW (multi-node does not model meeting reactive power demand)"
                        @warn("The maximum reactive power support from the substation is greater than 1 kW")
                    end
                    
                    if PMD_MinimumPowerOnsubstation_line_ReactivePower <= -1
                        warning_PMD_MinimumPowerOnsubstation_line_ReactivePower = "Warning: less than -1kW (multi-node does not model meeting reactive power demand)"
                        @warn("The minimum reactive power support from the substation is less than -1 kW")
                    end   
                else
                    PMD_MaximumPowerOnsubstation_line_ReactivePower = "N/A" 
                    PMD_MinimumPowerOnsubstation_line_ReactivePower = "N/A" 
                    PMD_AveragePowerOnsubstation_line_ReactivePower = "N/A"
                end
            end

            # Add system-level results
            ComputationTime_EntireModel_Milliseconds, ComputationTime_EntireModel_Minutes = CalculateComputationTime(start_time_entire_model)
      
            push!(DataLabels, "----Optimization Parameters----")
            push!(Data,"")
            push!(DataLabels, "  Number of Variables")
            push!(Data, length(all_variables(model)))
            push!(DataLabels, "  Computation time, including the BAU model and the outage simulator if used (minutes)")
            push!(Data, round(ComputationTime_EntireModel_Minutes, digits=2))
            push!(DataLabels, "  Model solve time (minutes)" )
            push!(Data, round(JuMP.solve_time(model)/60, digits = 2))
            
            if Multinode_Inputs.run_BAU_case 
                push!(DataLabels, "  BAU model solve time (minutes)" )
                push!(Data, round(JuMP.solve_time(bau_model)/60, digits = 2))
            end
            if Multinode_Inputs.run_outage_simulator
                push!(DataLabels, "  Total outage simulation time (minutes)")
                push!(Data, outage_simulator_time)
            end

            push!(DataLabels, "----Model Information----")
            push!(Data,"")
            push!(DataLabels,"  Number of Phases (input)")
            push!(Data, Multinode_Inputs.number_of_phases)
            push!(DataLabels,"  Multinode Type (input)")
            push!(Data, Multinode_Inputs.multinode_type)
            push!(DataLabels,"  Model Type (input)")
            push!(Data, Multinode_Inputs.model_type)
            push!(DataLabels,"  Model Subtype (input)")
            push!(Data, Multinode_Inputs.model_subtype)
            
            push!(DataLabels, "----Model Diagnostics----")
            push!(Data,"")
            if Multinode_Inputs.allow_bus_voltage_violations
                push!(DataLabels,"  Number of Bus Voltage Violations")
                push!(Data, sum(round.(Int, value.(model[Symbol("binBusVoltageViolation")]).data)))
            else
                push!(DataLabels,"  No diagnostics were run")
                push!(Data, "")
            end
            
            push!(DataLabels, "----System Results----")
            push!(Data,"")
            push!(DataLabels,"  Total Lifecycle Cost (LCC)")
            push!(Data, round(system_results["total_lifecycle_cost"], digits=0))
            push!(DataLabels,"  Total Lifecycle Capital Cost (LCCC)")
            push!(Data, round(system_results["total_lifecycle_capital_cost"], digits=0))

            if Multinode_Inputs.run_BAU_case 
                push!(DataLabels,"  Net Present Value (NPV)")
                push!(Data, isa(system_results["net_present_value"], Number) ? round(system_results["net_present_value"], digits=0) : system_results["net_present_value"])
            end

            push!(DataLabels,"  Total initial capital costs")
            push!(Data, round(system_results["total_initial_capital_costs"],digits=0))
            push!(DataLabels,"  Total initial capital costs after incentives")
            push!(Data, round(system_results["total_initial_capital_costs_after_incentives"],digits=0))

            push!(DataLabels,"  Total lifecycle storage capital cost")
            push!(Data, round(system_results["total_lifecycle_storage_capital_cost"],digits=0))
            push!(DataLabels,"  Total line upgrade costs")
            push!(Data, round(system_results["total_line_upgrade_cost"],digits=0))
            
            push!(DataLabels,"  Total PV size kw")
            push!(Data, round(system_results["total_PV_size_kw"],digits=0))

            push!(DataLabels,"  Total PV energy produced minus curtailment first year")
            push!(Data,  round(system_results["total_PV_energy_produced_minus_curtailment_first_year"],digits=0))
            push!(DataLabels,"  Total electric storage size kw")
            push!(Data, round(system_results["total_electric_storage_size_kw"],digits=0))
            
            push!(DataLabels,"  Total electric storage size kwh")
            push!(Data, round(system_results["total_electric_storage_size_kwh"],digits=0))
            push!(DataLabels,"  Total generator size kw")
            push!(Data, round(system_results["total_generator_size_kw"],digits=0))
            
            push!(DataLabels, "----Power Flow Model Results----")
            push!(Data, "")
            
            push!(DataLabels,"  Total Number of PMD timesteps, based on the user input")
            push!(Data, length(PMD_Results["nw"]) )

            if (Multinode_Inputs.number_of_phases == 1) && (Multinode_Inputs.model_subtype != "NFAUPowerModel")
                push!(DataLabels,"  Minimum per unit bus voltage")
                push!(Data, minimum_voltage)
                push!(DataLabels,"  Average per unit bus voltage")
                push!(Data, average_voltage)
                push!(DataLabels,"  Maximum per unit bus voltage")
                push!(Data, maximum_voltage)
            elseif Multinode_Inputs.model_subtype == "NFAUPowerModel"
                push!(DataLabels,"  Voltages are not modeled in the NFAUPowerModel")
                push!(Data, "")
            else
                push!(DataLabels,"  Minimum per unit bus voltage, all phases")
                push!(Data, minimum_voltage)
                push!(DataLabels,"  Average per unit bus voltage, all phases")
                push!(Data, average_voltage)
                push!(DataLabels,"  Maximum per unit bus voltage, all phases")
                push!(Data, maximum_voltage)
                for phase in sort(collect(keys(voltage_summary_by_phase)))
                    push!(DataLabels,"  Minimum per unit bus voltage, phase $(phase)")
                    push!(Data, voltage_summary_by_phase[phase]["minimum"])
                    push!(DataLabels,"  Average per unit bus voltage, phase $(phase)")
                    push!(Data, voltage_summary_by_phase[phase]["average"])
                    push!(DataLabels,"  Maximum per unit bus voltage, phase $(phase)")
                    push!(Data, voltage_summary_by_phase[phase]["maximum"])
                end
            end

            push!(DataLabels,"  From PMD: Maximum power flow on substation line, Active Power kW")
            push!(Data, PMD_MaximumPowerOnsubstation_line_ActivePower)
            push!(DataLabels,"  From PMD: Minimum power flow on substation line, Active Power kW")
            push!(Data, PMD_MinimumPowerOnsubstation_line_ActivePower)
            push!(DataLabels,"  From PMD: Average power flow on substation line, Active Power kW")
            push!(Data, PMD_AveragePowerOnsubstation_line_ActivePower)

            push!(DataLabels,"  From PMD: Maximum power flow on substation line, Reactive Power kVAR")
            push!(Data, string(PMD_MaximumPowerOnsubstation_line_ReactivePower) * warning_PMD_MaximumPowerOnsubstation_line_ReactivePower)
            push!(DataLabels,"  From PMD: Minimum power flow on substation line, Reactive Power kVAR")
            push!(Data, string(PMD_MinimumPowerOnsubstation_line_ReactivePower) * warning_PMD_MinimumPowerOnsubstation_line_ReactivePower)
            push!(DataLabels,"  From PMD: Average power flow on substation line, Reactive Power kVAR")
            push!(Data, PMD_AveragePowerOnsubstation_line_ReactivePower)
            
            if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                push!(DataLabels,"  From Simple Powerflow Model: Maximum power flow on substation line, Active Power kW")
                push!(Data, round(maximum(simple_powerflow_model_results["lines"][lowercase(LineFromSubstationToFacilityMeter)]["line_power_flow_series"]),digits=0) )
                push!(DataLabels,"  From Simple Powerflow Model: Minimum power flow on substation line, Active Power kW")
                push!(Data, round(minimum(simple_powerflow_model_results["lines"][lowercase(LineFromSubstationToFacilityMeter)]["line_power_flow_series"]),digits=0))
                push!(DataLabels,"  From Simple Powerflow Model: Average power flow on substation line, Active Power kW")
                push!(Data, round(mean(simple_powerflow_model_results["lines"][lowercase(LineFromSubstationToFacilityMeter)]["line_power_flow_series"]),digits=0))
            end

            # Add the multinode outage results to the dataframe
            push!(DataLabels, "----Multinode Outage Simulator Results----")
            push!(Data, "")
            if Multinode_Inputs.run_outage_simulator == true
                push!(DataLabels, "  Allowed dropped load?")
                push!(Data, Multinode_Inputs.allow_dropped_load)
                for i in 1:length(Multinode_Inputs.length_of_simulated_outages_time_steps)
                    OutageLength = Multinode_Inputs.length_of_simulated_outages_time_steps[i]
                    push!(DataLabels, " --Outage Length: $(OutageLength) time steps--")
                    push!(Data, "")
                    push!(DataLabels, "  Percent of Outages Survived")
                    push!(Data, string(Outage_Results["$(OutageLength)_timesteps_outage"]["PercentSurvived"])*" %")
                    push!(DataLabels, "  Total Number of Outages Tested")
                    push!(Data, Outage_Results["$(OutageLength)_timesteps_outage"]["NumberOfRuns"])
                    push!(DataLabels, "  Total Number of Outages Survived")
                    push!(Data, Outage_Results["$(OutageLength)_timesteps_outage"]["NumberOfOutagesSurvived"])
                    if Multinode_Inputs.allow_dropped_load
                        push!(DataLabels, "  Average Load Met Fraction")
                        push!(Data, round(Outage_Results["$(OutageLength)_timesteps_outage"]["dropped_load_results"]["average_load_met_fraction"], digits=5))
                    end
                end 
            else 
                push!(DataLabels,"Outage modeling was not run")
                push!(Data,"")
            end

            # Add results for each REopt node
            push!(DataLabels, "----REopt Results for Each Node----")
            push!(Data, "")
            
            for n in InputsList 
                NodeNumberTempB = n["Site"]["node"]
                InputsDictionary = Dict[] # reset the inputs dictionary to an empty dictionary before redefining
                InputsDictionary = n
                push!(DataLabels, "----Node $(NodeNumberTempB)----")
                push!(Data, "")

                if "PV" in keys(results[NodeNumberTempB])
                    push!(DataLabels, "  PV Size (kw)")
                    push!(Data, results[NodeNumberTempB]["PV"]["size_kw"])
                    push!(DataLabels, "  Min and Max PV sizing input, kW")
                    push!(Data, string(get(InputsDictionary["PV"], "min_kw", "not specified"))*" and "*string(get(InputsDictionary["PV"], "max_kw", "not specified")))

                    push!(DataLabels, "  Max PV Power Curtailed: ") 
                    push!(Data, round(maximum(results[NodeNumberTempB]["PV"]["electric_curtailed_series_kw"]), digits =2))
                    push!(DataLabels, "  Max PV Power Exported to Grid from node: ") 
                    push!(Data,round(maximum(results[NodeNumberTempB]["PV"]["electric_to_grid_series_kw"]), digits =2))
                else
                    push!(DataLabels, "  PV")
                    push!(Data, " None")
                end 
            
                if "Generator" in keys(results[NodeNumberTempB])
                    push!(DataLabels, "  Generator (kw)")
                    push!(Data, round(results[NodeNumberTempB]["Generator"]["size_kw"], digits =2))
                    
                    push!(DataLabels, "  Maximum generator power to load (kW): ")
                    push!(Data, round(maximum(results[NodeNumberTempB]["Generator"]["electric_to_load_series_kw"].data), digits =2))
                    push!(DataLabels, "  Average generator power to load (kW): ")
                    push!(Data, round(mean(results[NodeNumberTempB]["Generator"]["electric_to_load_series_kw"].data), digits =2))
                    
                    push!(DataLabels, "  Maximum generator power to grid (kW): ")
                    push!(Data, round(maximum(results[NodeNumberTempB]["Generator"]["electric_to_grid_series_kw"].data), digits =2))
                    push!(DataLabels, "  Minimum generator power to grid (kW): ")
                    push!(Data, round(minimum(results[NodeNumberTempB]["Generator"]["electric_to_grid_series_kw"].data), digits =2))
                    
                    push!(DataLabels, "  Average generator power to grid (kW): ")
                    push!(Data, round(mean(results[NodeNumberTempB]["Generator"]["electric_to_grid_series_kw"].data), digits =2))
                else 
                    push!(DataLabels, "  Generator")
                    push!(Data, " None")   
                end 
                if "ElectricStorage" in keys(results[NodeNumberTempB])
                    if results[NodeNumberTempB]["ElectricStorage"]["size_kw"] > 0 
                        push!(DataLabels, "  Battery Power (kW)")
                        push!(Data, round(results[NodeNumberTempB]["ElectricStorage"]["size_kw"], digits =2)) 
                        push!(DataLabels, "  Battery Capacity (kWh)")
                        push!(Data, round(results[NodeNumberTempB]["ElectricStorage"]["size_kwh"], digits =2))
                        
                        push!(DataLabels, "  Average Battery SOC (fraction): ")
                        push!(Data, round(mean(results[NodeNumberTempB]["ElectricStorage"]["soc_series_fraction"]), digits =2))
                        push!(DataLabels, "  Minimum Battery SOC (fraction): ")
                        push!(Data, round(minimum(results[NodeNumberTempB]["ElectricStorage"]["soc_series_fraction"]), digits =2))
                        
                        push!(DataLabels, "  Average battery to load (kW): ")
                        push!(Data, round(mean(results[NodeNumberTempB]["ElectricStorage"]["storage_to_load_series_kw"]), digits =2))
                        push!(DataLabels, "  Maximum battery to load (kW): ")
                        push!(Data, round(maximum(results[NodeNumberTempB]["ElectricStorage"]["storage_to_load_series_kw"]), digits =2))
                        
                        push!(DataLabels, "  Average battery to grid (kW): ")
                        push!(Data, round(mean(results[NodeNumberTempB]["ElectricStorage"]["storage_to_grid_series_kw"]), digits =2))
                        push!(DataLabels, "  Maximum battery to grid (kW): ")
                        push!(Data, round(maximum(results[NodeNumberTempB]["ElectricStorage"]["storage_to_grid_series_kw"]), digits =2))
                    else
                        push!(DataLabels, "  Battery")
                        push!(Data, " None")   
                    end
                else
                    push!(DataLabels, "  Battery")
                    push!(Data, " None")   
                end 
            end
            
            # Store the results summary dataframe
            dataframes["Results_Summary"] = DataFrame(Labels = DataLabels, Data = Data)
            
            # Store the Line Flow summary
            dataframes["PMD_Results_Line_Powerflow_Summary"] = DataFrame_LineFlow_Summary
            
            # Store the bus voltage summary
            if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                dataframes["PMD_Results_Bus_Voltages_Summary"] = DataFrame_BusVoltages_Summary
            end

            # Generate a dataframe summarizing the line power flow for each line
            line_powerflow_data = DataFrame()
            
            line_powerflow_data[!,"REopt_time_steps"] = Multinode_Inputs.PMD_time_steps  # Note: The PMD_time_steps input is expressed in REopt time steps
            line_powerflow_data[!,"PMD_time_steps"] = collect(1:length(Multinode_Inputs.PMD_time_steps))
                                                
            for line_data in keys(PMD_Dictionary_LineFlow_Power_Series)
                for data_subtype in keys(PMD_Dictionary_LineFlow_Power_Series[line_data])
                    if (data_subtype == "ActiveLineFlow") || (data_subtype == "ReactiveLineFlow")
                        OptionalNameAddition = "CombinedPhases_"
                    else
                        OptionalNameAddition = ""
                    end
                    line_phase_name = line_data*"_"*OptionalNameAddition*data_subtype
                    
                    if length(PMD_Dictionary_LineFlow_Power_Series[line_data][data_subtype]) > 0
                        line_powerflow_data[!,line_phase_name] = PMD_Dictionary_LineFlow_Power_Series[line_data][data_subtype]
                    else
                        line_powerflow_data[!,line_phase_name] = zeros(length(Multinode_Inputs.PMD_time_steps))
                    end
                    
                end
            end
            
            line_powerflow_data = line_powerflow_data[:,sortperm(names(line_powerflow_data))] # Sort the dataframe by the header title

            dataframes["PMD_Results_Line_Powerflow_Data"] = line_powerflow_data
            
        catch dataframe_error
            @warn "The dataframes of results could not be completely generated: $(sprint(showerror, dataframe_error))"
        end 

    end
    return system_results, dataframes
end


function combine_PMD_and_simple_powerflow_results(Multinode_Inputs, m, data_eng, PMD_Dictionary_LineFlow_Power_Series, simple_powerflow_model_results)
    # This function combines the powerflow results from the PMD model and the simple powerflow model
    phases_for_each_line =  create_dictionary_of_phases_for_each_line(data_eng) 
    simplified_powerflow_model_timesteps, REoptTimeSteps, time_steps_without_PMD, time_steps_with_PMD = determine_timestep_information(Multinode_Inputs, m, data_eng, phases_for_each_line)

    lines = collect(keys(data_eng["line"]))
    n_timesteps_total = Int(Multinode_Inputs.time_steps_per_hour * 8760)
    use_simple_pf = Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD

    pmd_index_of = Dict(t => i for (i, t) in enumerate(time_steps_with_PMD))
    simple_pf_index_of = use_simple_pf ?
        Dict(t => i for (i, t) in enumerate(time_steps_without_PMD)) :
        Dict{Int,Int}()

    all_line_powerflows = Dict{String, Dict{String, Any}}()

    for line in lines

        # Preallocate per-timestep vectors (mixed Float/String values, so Any)
        ActivePowerFlow_line_temp          = Vector{Any}(undef, n_timesteps_total)
        ReactivePowerFlow_line_temp        = Vector{Any}(undef, n_timesteps_total)
        ActivePowerFlow_line_Phase1_temp   = Vector{Any}(undef, n_timesteps_total)
        ActivePowerFlow_line_Phase2_temp   = Vector{Any}(undef, n_timesteps_total)
        ActivePowerFlow_line_Phase3_temp   = Vector{Any}(undef, n_timesteps_total)
        ReactivePowerFlow_line_Phase1_temp = Vector{Any}(undef, n_timesteps_total)
        ReactivePowerFlow_line_Phase2_temp = Vector{Any}(undef, n_timesteps_total)
        ReactivePowerFlow_line_Phase3_temp = Vector{Any}(undef, n_timesteps_total)
        power_flow_model_at_timesteps      = Vector{String}(undef, n_timesteps_total)

        # Cache per-line dicts once to avoid repeated lookups inside the inner loop
        line_pmd = PMD_Dictionary_LineFlow_Power_Series[line]
        has_p1 = length(line_pmd["Phase1_ActiveLineFlow"])   > 0
        has_p2 = length(line_pmd["Phase2_ActiveLineFlow"])   > 0
        has_p3 = length(line_pmd["Phase3_ActiveLineFlow"])   > 0
        has_q1 = length(line_pmd["Phase1_ReactiveLineFlow"]) > 0
        has_q2 = length(line_pmd["Phase2_ReactiveLineFlow"]) > 0
        has_q3 = length(line_pmd["Phase3_ReactiveLineFlow"]) > 0
        simple_line = use_simple_pf ? simple_powerflow_model_results["lines"][line]["line_power_flow_series"] : nothing

        for timestep in 1:n_timesteps_total

            if haskey(pmd_index_of, timestep)
                k = pmd_index_of[timestep]

                ActivePowerFlow_line_temp[timestep]   = line_pmd["ActiveLineFlow"][k]
                ReactivePowerFlow_line_temp[timestep] = line_pmd["ReactiveLineFlow"][k]

                ActivePowerFlow_line_Phase1_temp[timestep]   = has_p1 ? line_pmd["Phase1_ActiveLineFlow"][k]   : "N/A"
                ActivePowerFlow_line_Phase2_temp[timestep]   = has_p2 ? line_pmd["Phase2_ActiveLineFlow"][k]   : "N/A"
                ActivePowerFlow_line_Phase3_temp[timestep]   = has_p3 ? line_pmd["Phase3_ActiveLineFlow"][k]   : "N/A"
                ReactivePowerFlow_line_Phase1_temp[timestep] = has_q1 ? line_pmd["Phase1_ReactiveLineFlow"][k] : "N/A"
                ReactivePowerFlow_line_Phase2_temp[timestep] = has_q2 ? line_pmd["Phase2_ReactiveLineFlow"][k] : "N/A"
                ReactivePowerFlow_line_Phase3_temp[timestep] = has_q3 ? line_pmd["Phase3_ReactiveLineFlow"][k] : "N/A"

                power_flow_model_at_timesteps[timestep] = "PMD"

            elseif haskey(simple_pf_index_of, timestep)
                k = simple_pf_index_of[timestep]
                ActivePowerFlow_line_temp[timestep]   = simple_line[k]
                ReactivePowerFlow_line_temp[timestep] = "No reactive power in the simple powerflow model"

                ActivePowerFlow_line_Phase1_temp[timestep]   = "To do: add individual phase reporting for the simple powerflow model"
                ActivePowerFlow_line_Phase2_temp[timestep]   = "To do: add individual phase reporting for the simple powerflow model"
                ActivePowerFlow_line_Phase3_temp[timestep]   = "To do: add individual phase reporting for the simple powerflow model"
                ReactivePowerFlow_line_Phase1_temp[timestep] = "No reactive power in the simple powerflow model"
                ReactivePowerFlow_line_Phase2_temp[timestep] = "No reactive power in the simple powerflow model"
                ReactivePowerFlow_line_Phase3_temp[timestep] = "No reactive power in the simple powerflow model"

                power_flow_model_at_timesteps[timestep] = "simplified_powerflow_model"
            else
                ActivePowerFlow_line_temp[timestep]   = "No powerflow model at this time step"
                ReactivePowerFlow_line_temp[timestep] = "No powerflow model at this time step"

                ActivePowerFlow_line_Phase1_temp[timestep]   = "No powerflow model at this time step"
                ActivePowerFlow_line_Phase2_temp[timestep]   = "No powerflow model at this time step"
                ActivePowerFlow_line_Phase3_temp[timestep]   = "No powerflow model at this time step"
                ReactivePowerFlow_line_Phase1_temp[timestep] = "No powerflow model at this time step"
                ReactivePowerFlow_line_Phase2_temp[timestep] = "No powerflow model at this time step"
                ReactivePowerFlow_line_Phase3_temp[timestep] = "No powerflow model at this time step"

                power_flow_model_at_timesteps[timestep] = "no powerflow model"
            end
        end

        # Direct assignment is O(1); per-line merge! over a single-entry Dict was O(N) per line
        all_line_powerflows[line] = Dict{String, Any}(
            "ActiveLineFlow"                => ActivePowerFlow_line_temp,
            "ReactiveLineFlow"              => ReactivePowerFlow_line_temp,
            "Phase1_ActiveLineFlow"         => ActivePowerFlow_line_Phase1_temp,
            "Phase2_ActiveLineFlow"         => ActivePowerFlow_line_Phase2_temp,
            "Phase3_ActiveLineFlow"         => ActivePowerFlow_line_Phase3_temp,
            "Phase1_ReactiveLineFlow"       => ReactivePowerFlow_line_Phase1_temp,
            "Phase2_ReactiveLineFlow"       => ReactivePowerFlow_line_Phase2_temp,
            "Phase3_ReactiveLineFlow"       => ReactivePowerFlow_line_Phase3_temp,
            "power_flow_model_at_timesteps" => power_flow_model_at_timesteps,
        )
    end

    return all_line_powerflows
end


function determine_timestep_information(Multinode_Inputs, m, data_eng, phases_for_each_line)
    
    if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
        line_to_use_to_collect_timesteps = collect(keys(data_eng["line"]))[1]
        phase_to_use_to_collect_timesteps = phases_for_each_line[line_to_use_to_collect_timesteps][1]
        simplified_powerflow_model_timesteps = collect(1:length(value.(m[:dvPline][line_to_use_to_collect_timesteps, phase_to_use_to_collect_timesteps, :]))) # the phase 1 might not always work # pull the total number of timesteps from the first line in the simplified powerflow model
    else
        simplified_powerflow_model_timesteps = "the simplified powerflow model was not used"
    end

    REoptTimeSteps = collect(1:Int(8760* Multinode_Inputs.time_steps_per_hour))
    time_steps_without_PMD = setdiff(REoptTimeSteps, Multinode_Inputs.PMD_time_steps)
    time_steps_with_PMD = Multinode_Inputs.PMD_time_steps

    return simplified_powerflow_model_timesteps, REoptTimeSteps, time_steps_without_PMD, time_steps_with_PMD
end


function process_simple_powerflow_results(Multinode_Inputs, m, data_eng, connections, connections_upstream, connections_downstream)
   # Process the results from the simple powerflow model, which is applied to the time steps that the PMD model isn't applied to

    phases_for_each_line =  create_dictionary_of_phases_for_each_line(data_eng) 
    phases_for_each_bus = create_dictionary_of_phases_for_each_bus(data_eng) 

    simplified_powerflow_model_timesteps, REoptTimeSteps, time_steps_without_PMD, time_steps_with_PMD = determine_timestep_information(Multinode_Inputs, m, data_eng, phases_for_each_line)

    if length(time_steps_without_PMD) != length(simplified_powerflow_model_timesteps)
        throw(@error("The lengths of the time step arrays should be the same. This indicates that there is an issue with how the simple powerflow model and/or PMD model was formulated."))
    end
    
    timesteps = collect(1:length(time_steps_without_PMD)) # axes(m[:dvPline],3)

    simple_powerflow_line_results = Dict()
    lines = collect(keys(data_eng["line"]))   
    for line in lines
        #line_power_flow_series = sum(value.(m[:dvPline][line,phase,:].data) for phase in phases_for_each_line[line])
        
        line_power_flow_series = zeros(length(time_steps_without_PMD))
        
        for phase in phases_for_each_line[line]
            values = value.(m[:dvPline][line, phase, :])
            line_power_flow_series += [values[i] for i in timesteps]
        end
        
        simple_powerflow_line_results[line] = Dict("line_power_flow_series" => line_power_flow_series,
                                                   "line_maximum_power_flow" => maximum(line_power_flow_series),
                                                   "line_average_power_flow" => mean(line_power_flow_series),
                                                   "line_minimum_power_flow" => minimum(line_power_flow_series),
                                                   "associated_REopt_timesteps" => time_steps_without_PMD,
                                                   "simplified_powerflow_model_timesteps" => simplified_powerflow_model_timesteps
                                                    )
        # Add power flow results for individual phases
        individual_phase_results=Dict([])
        for phase in phases_for_each_line[line]
            individual_phase_results["phase_$(phase)"] = value.(m[:dvPline][line,phase,:]) 
        end
        simple_powerflow_line_results[line]["individual_phase_results"] = individual_phase_results
    end

    simple_powerflow_bus_results = Dict()
    #busses = axes(m[:dvP][:,:,1])[1]  # sounds like this line will error

    busses = unique(first.(collect(keys(m[:dvP][:,:,1].data)))) # something to extract all of the indeces in the first index of dvP

    # Adjust the phases associated with the sourcebus because in the PMD model the sourcebus will have three phases, even if the rest of the components on the system are single phase
    if Multinode_Inputs.number_of_phases == 3
        # Do nothing because the phases_for_each_bus["sourcebus"] should already be [1,2,3] by default
    elseif Multinode_Inputs.number_of_phases == 2
        phases_for_each_bus["sourcebus"] = [1,2]
    elseif Multinode_Inputs.number_of_phases == 1
        phases_for_each_bus["sourcebus"] = [1]
    else
        throw(@error("The input for the number_of_phases is invalid."))
    end

    #dvP_values = value.(m[:dvP][bus,:,:])
    print("\n")
    for bus in busses
        if Multinode_Inputs.display_information_during_modeling_run
            print(" For bus $(bus) the phases are:")
            print(phases_for_each_bus[string(bus)])
        end

        dvP_values = value.(m[:dvP][bus,:,:]).data

        #bus_power_series = sum(value.(m[:dvP][bus, phase, :].data) for phase in phases_for_each_bus[string(bus)])
        bus_power_series = zeros(Float64, length(time_steps_without_PMD))
        
        for ((_,j), val) in dvP_values
            bus_power_series[j] += val
        end

        #sum(dvP_values[phase, :] for phase in phases_for_each_bus[bus])
        simple_powerflow_bus_results[bus] = Dict("bus_power_series" => bus_power_series,
                                                   "bus_maximum_power" => maximum(bus_power_series),
                                                   "bus_average_power" => mean(bus_power_series),
                                                   "bus_minimum_power" => minimum(bus_power_series),
                                                   "associated_REopt_timesteps" => time_steps_without_PMD,
                                                   "simplified_powerflow_model_timesteps" => simplified_powerflow_model_timesteps
                                                    )
    end
    print("\n")
    
    simple_powerflow_results = Dict("lines" => simple_powerflow_line_results,
                                    "busses" => simple_powerflow_bus_results,
                                    "all_bus_line_connections" => connections,
                                    "downstream_bus_line_connections" => connections_downstream,
                                    "upstream_bus_line_connections" => connections_upstream)
                                        
    return simple_powerflow_results
end


function process_model_diagnostics_bus_voltage_violations(Multinode_Inputs, pm)
    model = pm.model

    bus_voltage_violation_results = Dict()

    BusInfo = create_bus_info_dictionary(pm)
    bus_names = collect(keys(BusInfo))
    PMD_time_steps = collect(1:length(Multinode_Inputs.PMD_time_steps))
    
    for bus_name in bus_names
        for PMD_time_step in PMD_time_steps
            bin_value = value.(model[Symbol("binBusVoltageViolation")][bus_name, PMD_time_step])
            if bin_value > 0.5 # The binary variable value can be slightly off of 1 due to solver tolerances
                REoptTimeStep = Multinode_Inputs.PMD_time_steps[PMD_time_step]
                
                if string("node_"*bus_name) in keys(bus_voltage_violation_results)
                    entry_to_add_temp = Dict(REoptTimeStep => Dict("associated_PMD_time_step" => PMD_time_step, "per_unit_voltage" => "To add")) # Note: Multinode_Inputs.PMD_time_steps[PMD_time_step] converts the timestep from the PMD timestep (expressed in PMD timesteps) to the PMD timestep (expressed in REopt timesteps)
                    bus_voltage_violation_results[string("node_"*bus_name)] = merge!(bus_voltage_violation_results[string("node_"*bus_name)], entry_to_add_temp)
                else
                    bus_voltage_violation_results[string("node_"*bus_name)] = Dict(REoptTimeStep => Dict("associated_PMD_time_step" => PMD_time_step, "per_unit_voltage" => "To add"))
                end

                if "REopt_timesteps_with_bus_voltage_violations" in keys(bus_voltage_violation_results)
                    if REoptTimeStep in bus_voltage_violation_results["REopt_timesteps_with_bus_voltage_violations"]
                        # Do nothing because the time step is already listed in the array
                    else
                        push!(bus_voltage_violation_results["REopt_timesteps_with_bus_voltage_violations"], REoptTimeStep) 
                    end
                else
                    bus_voltage_violation_results["REopt_timesteps_with_bus_voltage_violations"] = [REoptTimeStep] 
                end

            end
        end
    end

    return bus_voltage_violation_results
end


function VoltageResultsSummary(results)

    bus_names = collect(keys(results["nw"]["1"]["bus"]))
    n_buses = length(bus_names)
    timestep_keys = sort(collect(keys(results["nw"])), by = x -> parse(Int, string(x))) # sorted so the voltage series are in time order
    n_timesteps = length(timestep_keys)

    per_unit_voltages = Dict{String, Vector{Float64}}()
    col_Bus = Vector{String}(undef, n_buses)
    col_min = Vector{Float64}(undef, n_buses)
    col_avg = Vector{Float64}(undef, n_buses)
    col_max = Vector{Float64}(undef, n_buses)

    for (b_idx, bus) in enumerate(bus_names)
        bus_voltages = Vector{Float64}(undef, n_timesteps)
        for (t_idx, timestep) in enumerate(timestep_keys)
            bus_at_t = results["nw"][string(timestep)]["bus"][bus]
            if haskey(bus_at_t, "w")
                bus_voltages[t_idx] = sqrt(bus_at_t["w"][1])
            elseif haskey(bus_at_t, "Wr")
                bus_voltages[t_idx] = sqrt(bus_at_t["Wr"][1][1]) # TODO: figure out what "Wi" is in the results when using the SOCNLPUBFPowerModel model
            else
                throw(@error("Bus voltage results data is not available"))
            end
        end
        per_unit_voltages[bus] = bus_voltages

        col_Bus[b_idx] = "Bus "*string(bus)
        col_min[b_idx] = round(minimum(bus_voltages), digits = 6)
        col_avg[b_idx] = round(mean(bus_voltages),    digits = 6)
        col_max[b_idx] = round(maximum(bus_voltages), digits = 6)
    end

    DataFrame_BusVoltages = DataFrame(
        Bus                = col_Bus,
        minimum_pu_voltage = col_min,
        Average_pu_voltage = col_avg,
        maximum_pu_voltage = col_max,
    )

    minimum_voltage = round(minimum(col_min), digits=6)
    average_voltage = round(mean(col_avg),    digits=6)
    maximum_voltage = round(maximum(col_max), digits=6)

    return DataFrame_BusVoltages, per_unit_voltages, minimum_voltage, average_voltage, maximum_voltage
end


function MultiphaseBusVoltagesPerUnit(bus_result, terminals)
    # This function was written with the assistance of AI.
    # Returns a dictionary of the per unit voltage magnitude for each phase (1, 2, or 3) at a bus, for one PMD time step
    # This follows the same approach as the single phase VoltageResultsSummary, where the square root of "w" is the per unit voltage 
    apply_to_values(f, x) = x isa AbstractDict ? Dict(k => f(v) for (k, v) in x) : [f(v) for v in x]

    if haskey(bus_result, "w")
        magnitudes = apply_to_values(w -> sqrt(max(w, 0.0)), bus_result["w"])
    elseif haskey(bus_result, "Wr")
        Wr = bus_result["Wr"]
        n_entries = Wr isa AbstractMatrix ? size(Wr, 1) : length(Wr)
        magnitudes = [sqrt(max(Wr isa AbstractMatrix ? Wr[i, i] : Wr[i][i], 0.0)) for i in 1:n_entries]
    else
        throw(@error("Bus voltage results data is not available"))
    end

    phase_voltages = Dict{Int,Float64}()
    if magnitudes isa AbstractDict
        for (key, magnitude) in magnitudes
            phase = key isa Integer ? Int(key) : tryparse(Int, string(key))
            phase in 1:3 && (phase_voltages[phase] = Float64(magnitude))
        end
    else
        # The voltage entries follow the order of the bus terminals; the neutral terminal (4) might or might not be included in the results
        terminals = collect(terminals)
        if length(terminals) != length(magnitudes)
            terminals_without_neutral = filter(!=(4), terminals)
            terminals = length(terminals_without_neutral) == length(magnitudes) ? terminals_without_neutral : collect(1:length(magnitudes))
        end
        for (i, terminal) in enumerate(terminals)
            terminal in 1:3 && (phase_voltages[Int(terminal)] = Float64(magnitudes[i]))
        end
    end

    return phase_voltages
end


function VoltageResultsSummaryMultiphase(results, data_eng)
    # This function was generated with the assistance of AI.
    # Summarizes the per unit bus voltages for each phase of a multi-phase system
    # The data_eng input provides the terminals of each bus, which identify the phase of each voltage entry

    bus_names = sort(string.(collect(keys(results["nw"]["1"]["bus"]))))
    timestep_keys = sort(collect(keys(results["nw"])), by = x -> parse(Int, string(x)))

    all_voltages = Dict{Int, Vector{Float64}}() # all of the voltages (every bus and time step) for each phase
    bus_column = String[]
    phase_column = Int[]
    minimum_column = Float64[]
    average_column = Float64[]
    maximum_column = Float64[]

    for bus in bus_names
        terminals = (data_eng isa AbstractDict) && haskey(data_eng, "bus") && haskey(data_eng["bus"], bus) ? data_eng["bus"][bus]["terminals"] : Int[]
        voltages_at_bus = Dict{Int, Vector{Float64}}()
        for timestep in timestep_keys
            phase_voltages = MultiphaseBusVoltagesPerUnit(results["nw"][string(timestep)]["bus"][bus], terminals)
            for (phase, voltage) in phase_voltages
                push!(get!(voltages_at_bus, phase, Float64[]), voltage)
                push!(get!(all_voltages, phase, Float64[]), voltage)
            end
        end
        for phase in sort(collect(keys(voltages_at_bus)))
            push!(bus_column, "Bus "*bus)
            push!(phase_column, phase)
            push!(minimum_column, round(minimum(voltages_at_bus[phase]), digits = 6))
            push!(average_column, round(mean(voltages_at_bus[phase]),    digits = 6))
            push!(maximum_column, round(maximum(voltages_at_bus[phase]), digits = 6))
        end
    end

    if isempty(all_voltages)
        throw(@error("Bus voltage results data is not available for any phase"))
    end

    DataFrame_BusVoltages = DataFrame(
        Bus                = bus_column,
        Phase              = phase_column,
        minimum_pu_voltage = minimum_column,
        Average_pu_voltage = average_column,
        maximum_pu_voltage = maximum_column,
    )

    voltage_summary_by_phase = Dict{Int, Dict{String, Float64}}()
    for (phase, voltages) in all_voltages
        voltage_summary_by_phase[phase] = Dict("minimum" => round(minimum(voltages), digits = 6),
                                               "average" => round(mean(voltages),    digits = 6),
                                               "maximum" => round(maximum(voltages), digits = 6))
    end

    every_voltage = vcat(values(all_voltages)...)
    minimum_voltage = round(minimum(every_voltage), digits = 6)
    average_voltage = round(mean(every_voltage),    digits = 6)
    maximum_voltage = round(maximum(every_voltage), digits = 6)

    return DataFrame_BusVoltages, voltage_summary_by_phase, minimum_voltage, average_voltage, maximum_voltage
end


function CollectMapInformation(results, Multinode_Inputs, all_lines_including_transformers_as_lines, lines_in_PMD, data_eng_lines, busses_in_PMD)

    if Multinode_Inputs.model_type == "PowerModelsDistribution"
        lines = keys(results["Line_Info_PMD"])
    end

    # Extract the latitude and longitude for the busses
    bus_coordinates_filename = Multinode_Inputs.bus_coordinates
    data_input = CSV.read(bus_coordinates_filename, DataFrame, header =1)

    # Create a dictionary of the bus coordinates
    number_of_entries_in_lat_long_file = size(data_input, 1)
    busses_in_PMD_lowercase = lowercase.(busses_in_PMD)
    bus_cords = Dict([])
    busses=[]
    for row in collect(1:number_of_entries_in_lat_long_file)
        bus = lowercase(string(data_input[row,:Bus]))
        if bus in busses_in_PMD_lowercase
            push!(busses, bus)
            bus_cords[string(bus)] = [data_input[row,:Latitude], data_input[row,:Longitude]]
        end
    end

    # Create a dictionary of the line segment start and end coordinates
    substation_cords = "N/A"
    line_cords = Dict([])   

    # Convert all of the characters to lower case
    bus_cords = Dict(lowercase(String(key)) => value for (key,value) in bus_cords)

    # Every bus that is plotted needs coordinates in the bus coordinates file
    busses_without_coordinates = setdiff(busses_in_PMD_lowercase, collect(keys(bus_cords)))
    if !isempty(busses_without_coordinates)
        throw(@error("The following busses are in the PMD model, but are not listed in the bus coordinates file $(bus_coordinates_filename): $(busses_without_coordinates)"))
    end

    for line in all_lines_including_transformers_as_lines
        if line in lines_in_PMD # for lines that are lines in PMD
            line_cords[line] = [bus_cords[data_eng_lines[line]["f_bus"]], bus_cords[data_eng_lines[line]["t_bus"]]]
        else # assume that the line is part of a transformer line
            # transformer lines are represented with the syntax "xfmr_line_bus1_bus2"
            line_interpretation = match(r"_([^_]+)_([^_]+)$", line)
            bus1 = line_interpretation.captures[1]
            bus2 = line_interpretation.captures[2]

            line_cords[line] = [bus_cords[bus1],bus_cords[bus2]]
        end
    end

    substation_cords = bus_cords[lowercase(string(Multinode_Inputs.substation_node))]

    bus_key_values = collect(keys(bus_cords))
    line_key_values = collect(keys(line_cords))

return bus_key_values, line_key_values, bus_cords, line_cords, busses, substation_cords

end

function CollectResultsByNode(results, busses)

    # REopt nodes can be integers or strings, and the busses are lowercase strings, so the REopt results are matched using lowercase strings
    REopt_results_by_bus_name = Dict(lowercase(string(node)) => node_results for (node, node_results) in results["REopt_results"])

    # Create a dictionary of the technology sizing at each node, which will be plotted on the map:
    results_by_node = Dict([])
    for bus in busses 
        if lowercase(string(bus)) in keys(REopt_results_by_bus_name)
            node_results = REopt_results_by_bus_name[lowercase(string(bus))]
            if "PV" in keys(node_results)
                if node_results["PV"]["size_kw"] > 0
                    PV = "PV: "*string(round(node_results["PV"]["size_kw"], digits=0))*"kW "
                else
                    PV = ""  
                end
            else            
                PV = ""
            end

            if "Generator" in keys(node_results)
                if node_results["Generator"]["size_kw"] > 0
                    Generator = "Gen: "*string(round(node_results["Generator"]["size_kw"], digits=0))*"kW "
                else
                    Generator = ""
                end
            else
                Generator = ""
            end

            if "ElectricStorage" in keys(node_results)
                if node_results["ElectricStorage"]["size_kw"] > 0
                    Battery =  "Bat: "*string(round(node_results["ElectricStorage"]["size_kw"],digits=1))*"kW"*","*string(round(node_results["ElectricStorage"]["size_kwh"],digits=1))*"kWh "
                else
                    Battery = ""
                end
            else
                Battery = ""
            end
            
            if PV != "" || Generator != "" || Battery != ""
                punctuation = ": "
            else
                punctuation = ""
            end
            
            results_by_node[lowercase(string(bus))] = punctuation*PV*Generator*Battery
        else
            results_by_node[lowercase(string(bus))] = ""
        end
    end

    return results_by_node
end


function DetermineOutageStartsAndEnds(Multinode_Inputs, outages_vector)
    # From the list of outage timesteps, construct an array for the outage start times and outage end times by identifying groups of values

    outages_vector = sort(unique(outages_vector))
    if isempty(outages_vector)
        return Float64[], Float64[]
    end

    outage_starts = [outages_vector[1]]
    outage_ends = []

    for i in collect(2:length(outages_vector))
        if (outages_vector[i] - outages_vector[i-1]) >= 2
            push!(outage_starts, outages_vector[i])
            push!(outage_ends, outages_vector[i-1])
        end
    end

    # Make sure that the last value in the outage vector is part of the outage_ends array (outage_ends is empty if there is only one outage):
    if isempty(outage_ends) || (outage_ends[end] != outages_vector[end])
        push!(outage_ends, outages_vector[end])
    end
    # Convert to days:
    outage_starts = outage_starts / (24 * Multinode_Inputs.time_steps_per_hour)
    outage_ends = outage_ends / (24 * Multinode_Inputs.time_steps_per_hour)
    return outage_starts, outage_ends
end


function DeterminePathToSourcebus(neighbors, Multinode_Inputs)
    # Acknowledgement: This function was built with the assistance of AI
    parent_dict = Dict()
    path_dict = Dict()
    substation_bus = Multinode_Inputs.substation_node #"sourcebus"
    queue = [substation_bus]
    visited = Dict()
    visited[substation_bus] = true

    while !isempty(queue)
        bus = popfirst!(queue)
        for i in neighbors[bus]
            if !haskey(visited, i)
                visited[i] = true
                parent_dict[i] = bus
                push!(queue, i)
            end
        end
    end

    for bus in keys(neighbors)
        if !haskey(visited, bus)
            throw(@error("Bus $(bus) is not connected to the substation node $(substation_bus), so a path from the bus to the substation cannot be determined"))
        end
        path = []
        current_bus = bus
        while current_bus != substation_bus
            push!(path, current_bus)
            current_bus = parent_dict[current_bus]
        end
        push!(path, substation_bus)
        path_dict[bus] = reverse(path)
    end

    return path_dict
end
 

function DetermineDistanceFromSourcebus(Multinode_Inputs, data_eng)
    neighbors = REopt.modified_calc_connected_components_eng(data_eng)
    paths = REopt.DeterminePathToSourcebus(neighbors, Multinode_Inputs)

    # remove duplicate values if a key has duplicates
    for (key, values) in neighbors
        neighbors[key] = unique(values)
    end

    #Multinode_Inputs = results["Multinode_Inputs"]

    line_names_to_sourcebus_dict = Dict()
    lengths_to_sourcebus_dict = Dict()

    for i in keys(paths)
        path = paths[i]
        line_names_temp = []
        line_lengths_temp = []

        for j in collect(1:(length(path)-1))
            firstnode = path[j]
            if path[j] == "sourcebus"
                firstnode = string(Multinode_Inputs.substation_node)
            end
            line_name = string("line"*firstnode*"_"*path[j+1])
            reverse_line_name = string("line"*path[j+1]*"_"*firstnode) # the line may be defined in the direction toward the sourcebus
            if !haskey(data_eng["line"], line_name) && haskey(data_eng["line"], reverse_line_name)
                line_name = reverse_line_name
            end
            if haskey(data_eng["line"], line_name)
                push!(line_names_temp, line_name)
                push!(line_lengths_temp, data_eng["line"][line_name]["length"])
            end
        end
        line_names_to_sourcebus_dict[i] = line_names_temp
        lengths_to_sourcebus_dict[i] = line_lengths_temp
    end
    
    summed_lengths_to_sourcebus_dict = Dict()
    for i in keys(lengths_to_sourcebus_dict)
        if lengths_to_sourcebus_dict[i] != Any[]
            summed_lengths_to_sourcebus_dict[i] = sum(lengths_to_sourcebus_dict[i])
        else
            summed_lengths_to_sourcebus_dict[i] = 0
        end
    end

    return summed_lengths_to_sourcebus_dict, lengths_to_sourcebus_dict, line_names_to_sourcebus_dict, paths, neighbors
end


function modified_calc_connected_components_eng(data; edges::Vector{<:String}=String["line", "switch", "transformer"], type::Union{Missing,String}=missing, check_enabled::Bool=true) #::Set{Set{String}}
    # Acknowledgement: This function is based on code from the julia package PowerModelsDistribution
    
    @assert get(data, "data_model", PowerModelsDistribution.MATHEMATICAL) == PowerModelsDistribution.ENGINEERING

    active_bus = Dict{String,Dict{String,Any}}(x for x in data["bus"] if x.second["status"] == PowerModelsDistribution.ENABLED || !check_enabled)
    active_bus_ids = Set{String}([i for (i,bus) in active_bus])

    neighbors = Dict{String,Vector{String}}(i => [] for i in active_bus_ids)
    for edge_type in edges
        for (id, edge_obj) in get(data, edge_type, Dict{Any,Dict{String,Any}}())
            if edge_obj["status"] == PowerModelsDistribution.ENABLED || !check_enabled
                if edge_type == "transformer" && haskey(edge_obj, "bus")
                    for f_bus in edge_obj["bus"]
                        for t_bus in edge_obj["bus"]
                            if f_bus != t_bus
                                push!(neighbors[f_bus], t_bus)
                                push!(neighbors[t_bus], f_bus)
                            end
                        end
                    end
                else
                    if edge_type == "switch" && !ismissing(type)
                        if type == "load_blocks"
                            if edge_obj["dispatchable"] == PowerModelsDistribution.NO && edge_obj["state"] == PowerModelsDistribution.CLOSED
                                push!(neighbors[edge_obj["f_bus"]], edge_obj["t_bus"])
                                push!(neighbors[edge_obj["t_bus"]], edge_obj["f_bus"])
                            end
                        elseif type == "blocks"
                            if edge_obj["state"] == PowerModelsDistribution.CLOSED
                                push!(neighbors[edge_obj["f_bus"]], edge_obj["t_bus"])
                                push!(neighbors[edge_obj["t_bus"]], edge_obj["f_bus"])
                            end
                        end
                    else
                        push!(neighbors[edge_obj["f_bus"]], edge_obj["t_bus"])
                        push!(neighbors[edge_obj["t_bus"]], edge_obj["f_bus"])
                    end
                end
            end
        end
    end

    neighbors_with_keys_as_strings = Dict(string(key)=> value for (key, value) in neighbors)

    return neighbors_with_keys_as_strings 
end

