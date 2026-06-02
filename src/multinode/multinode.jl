# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function Multinode_Model(Multinode_Settings::Dict{String, Any})
    # The main function to run all parts of the multinode model

    StartTime_EntireModel = now() # Record the start time for the computation
    TimeStamp = Dates.format(now(), "mm-dd-yyyy")*"_"*Dates.format(now(), "HH-MM")
    time_results = Dict()
   
    Multinode_Inputs = REopt.MultinodeInputs(; REopt.dictkeys_tosymbols(Multinode_Settings)...)
    
    if Multinode_Inputs.generate_CSV_of_outputs
        cd(Multinode_Inputs.folder_location)
        CreateOutputsFolder(Multinode_Inputs, TimeStamp)
    end

    print("\n Preparing the electric loads")
    Start_time_prepare_electric_loads = now()
    PrepareElectricLoads(Multinode_Inputs)
    milliseconds, prepare_electric_loads_time_minutes = CalculateComputationTime(Start_time_prepare_electric_loads)
    time_results["Step $(length(keys(time_results))+1): prepare_electric_loads_time_minutes"] = prepare_electric_loads_time_minutes   

    print("\n Preparing the REopt inputs")
    REopt_inputs_combined = PrepareREoptInputs(Multinode_Inputs, time_results)
    print("\n Completed preparing the REopt inputs")

    m_outagesimulator = "empty"
    #model = "empty"
    model_BAU = "empty"
    model_diagnostics_bus_voltage_violations = "empty"
    
    if Multinode_Inputs.model_type == "PowerModelsDistribution"
        print("\n Running data checks \n")        
        RunDataChecks(Multinode_Inputs, REopt_inputs_combined)
        
        PMD_number_of_timesteps = length(Multinode_Inputs.PMD_time_steps)

        REopt_Results, PMD_Results, DataFrame_PMD_LineFlow_Summary, 
            PMD_Dictionary_LineFlow_Power_Series, DataDictionaryForEachNode, 
            LineInfo_PMD, REoptInputs_Combined, data_eng, data_math_mn, pm, 
            line_upgrade_options_each_line, line_upgrade_results, load_phase_dictionary, 
            gen_ind_e_to_REopt_node, REopt_gen_ind_e, connections, connections_upstream, 
            connections_downstream = 
            build_run_and_process_results(Multinode_Inputs, REopt_inputs_combined, PMD_number_of_timesteps, TimeStamp, time_results; allow_upgrades = true)

        time_results["Step $(length(keys(time_results))+1): model_solve_time_minutes"] = round(JuMP.solve_time(pm.model)/60, digits = 2)  
        GC.gc()
        print("\n Completed running the build_run_and_process_results function")

        if REopt_Results == "N/A"
            @warn "The optimization did not return an optimal solution. Returning the failed model with all other outputs set to \"N/A\"."
            ComputationTime_EntireModel_Milliseconds, ComputationTime_EntireModel_Minutes = CalculateComputationTime(StartTime_EntireModel)
            time_results["ComputationTime_EntireModel_Minutes"] = ComputationTime_EntireModel_Minutes
            return "N/A", pm.model, "N/A", "N/A"
        end

        if Multinode_Inputs.run_outage_simulator
            Outage_Results, single_model_outage_simulator, outage_simulator_time_minutes, outage_simulator_results_for_plotting, outage_survival_results_dictionary, outage_start_timesteps_dictionary = run_outage_simulator(DataDictionaryForEachNode, REopt_inputs_combined, Multinode_Inputs, TimeStamp, LineInfo_PMD, line_upgrade_options_each_line, line_upgrade_results, REoptInputs_Combined)
            time_results["Step $(length(keys(time_results))+1): outage_simulator_time_minutes"] = outage_simulator_time_minutes
        else
            Outage_Results = Dict(["NoOutagesTested" => Dict(["Not evaluated" => "Not evaluated"])])
            single_model_outage_simulator = "N/A"
            outage_simulator_time_minutes = "N/A"
            outage_simulator_results_for_plotting = "N/A"
            outage_survival_results_dictionary = "N/A"
            outage_start_timesteps_dictionary = "N/A"
        end 

        if Multinode_Inputs.run_BAU_case
            print("\n Running the BAU case")
            Multinode_Settings_No_Techs = SetTechSizesToZero(Multinode_Settings)
            Multinode_Inputs_No_Techs = REopt.MultinodeInputs(; REopt.dictkeys_tosymbols(Multinode_Settings_No_Techs)...)
            PrepareElectricLoads(Multinode_Inputs_No_Techs)
            
            Outage_Results_No_Techs = Dict(["NoOutagesTested" => Dict(["Not evaluated" => "Not evaluated"])])
            
            REopt_Results_BAU, PMD_Results_No_Techs, DataFrame_PMD_LineFlow_Summary_No_Techs, 
                PMD_Dictionary_LineFlow_Power_Series_No_Techs, DataDictionaryForEachNode_No_Techs, 
                LineInfo_PMD_No_Techs, REoptInputs_Combined_No_Techs, data_eng_No_Techs, 
                data_math_mn_No_Techs, pm_No_Techs, line_upgrade_options_each_line_NoTechs, 
                line_upgrade_results_NoTechs, load_phase_dictionary_NoTechs, gen_ind_e_to_REopt_node_noTechs, 
                REopt_gen_ind_e_noTechs, connections_noTechs, connections_upstream_noTechs, 
                connections_downstream_noTechs = build_run_and_process_results(Multinode_Inputs_No_Techs, REopt_inputs_combined, PMD_number_of_timesteps, TimeStamp, time_results; allow_upgrades=false, BAU_case=true)
            
            GC.gc()

            ComputationTime_EntireModel = "N/A"
            system_results_BAU = REopt.Results_Compilation(pm_No_Techs.model, REopt_Results_BAU, PMD_Results, Outage_Results_No_Techs, Multinode_Inputs_No_Techs, DataFrame_PMD_LineFlow_Summary_No_Techs, PMD_Dictionary_LineFlow_Power_Series_No_Techs, TimeStamp, ComputationTime_EntireModel; system_results_BAU = "")
            time_results["Step $(length(keys(time_results))+1): BAU_model_solve_time_minutes"] = round(JuMP.solve_time(model_BAU)/60, digits = 2)
            print("\n Completed running the BAU case")
        else
            system_results_BAU = "none"
            REopt_Results_BAU = "none"
            model_BAU = "none"
        end

        if Multinode_Inputs.allow_bus_voltage_violations  # || Multinode_Inputs.allow_dropped_load_in_main_optimization
            print("\n Processing the model diagnostics for bus voltage violation")
            model_diagnostics_bus_voltage_violations = process_model_diagnostics_bus_voltage_violations(Multinode_Inputs, pm)
            print("\n Completed processing the model diagnostics for bus voltage violation")
        else
            model_diagnostics_bus_voltage_violations = "N/A"
        end
     
        if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
            GC.gc()
            print("\n Processing the simple powerflow results")
            simple_powerflow_model_results = process_simple_powerflow_results(Multinode_Inputs, pm.model, data_eng, connections, connections_upstream, connections_downstream)
            all_line_powerflow_results = combine_PMD_and_simple_powerflow_results(Multinode_Inputs, pm.model, data_eng, PMD_Dictionary_LineFlow_Power_Series, simple_powerflow_model_results)
            print("\n Completed processing the simple powerflow results")
        else
            simple_powerflow_model_results = "The simple powerflow model was not used"
            all_line_powerflow_results = combine_PMD_and_simple_powerflow_results(Multinode_Inputs, pm.model, data_eng, PMD_Dictionary_LineFlow_Power_Series, simple_powerflow_model_results)
        end
        print("\n Compiling all the results")
        system_results = REopt.Results_Compilation(pm.model, REopt_Results, PMD_Results, Outage_Results, Multinode_Inputs, DataFrame_PMD_LineFlow_Summary, PMD_Dictionary_LineFlow_Power_Series, TimeStamp, StartTime_EntireModel; bau_model = model_BAU, system_results_BAU = system_results_BAU, outage_simulator_time = outage_simulator_time_minutes, all_line_powerflow_results = all_line_powerflow_results, simple_powerflow_model_results=simple_powerflow_model_results)

        ComputationTime_EntireModel_Milliseconds, ComputationTime_EntireModel_Minutes = CalculateComputationTime(StartTime_EntireModel)
        time_results["ComputationTime_EntireModel_Minutes"] = ComputationTime_EntireModel_Minutes
        
        # Compile output data into a dictionary to return from the dictionary
        CompiledResults = Dict([("System_Results", system_results),
                                ("System_Results_BAU", system_results_BAU),
                                ("DataDictionaryForEachNode", DataDictionaryForEachNode),
                                ("Multinode_Inputs", Multinode_Inputs), 
                                ("Dictionary_LineFlow_Power_Series", all_line_powerflow_results), 
                                ("PMD_results", PMD_Results),
                                ("PMD_line_power_flow_results", PMD_Dictionary_LineFlow_Power_Series),
                                ("simple_powerflow_model_line_power_flow_results", simple_powerflow_model_results),
                                ("PMD_data_eng", data_eng),
                                ("REopt_results", REopt_Results),
                                ("REopt_results_BAU", REopt_Results_BAU),
                                ("Outage_Results", Outage_Results),
                                ("DataFrame_LineFlow_Summary", DataFrame_PMD_LineFlow_Summary),
                                ("Computation_Time_Data", time_results),
                                ("Line_Info_PMD", LineInfo_PMD),
                                ("pm", pm), # This can be a very large variable and it can be slow to load
                                ("line_upgrade_options", line_upgrade_options_each_line),
                                ("line_upgrade_results", line_upgrade_results),
                                ("single_outage_simulator_model", single_model_outage_simulator),
                                ("data_math_mn", data_math_mn),
                                ("model_diagnostics_bus_voltage_violations", model_diagnostics_bus_voltage_violations),
                                ("load_phase_dictionary", load_phase_dictionary),
                                ("gen_ind_e_to_REopt_node", gen_ind_e_to_REopt_node),
                                ("REopt_gen_ind_e", REopt_gen_ind_e),
                                #("transformer_upgrade_options", transformer_upgrade_options_output),
                                #("transformer_upgrade_results", transformer_upgrade_results_output)
                                #("FromREopt_Dictionary_Node_Data_Series", Dictionary_Node_Data_Series) 
                                ])
        
        if Multinode_Inputs.generate_dictionary_for_plotting
            data_dictionary_for_plots = Dict([
                            ("voltage_plot_time_step", 1), # The default is 1, but the user can update this value after this dictionary is returned from the Multinode_Model function
                            ("Multinode_Inputs", Multinode_Inputs),
                            ("outage_survival_results", outage_survival_results_dictionary),
                            ("outage_start_timesteps_checked", outage_start_timesteps_dictionary),
                            ("TimeStamp", TimeStamp),
                            #("OutageLength_TimeSteps_Input", OutageLength_TimeSteps_Input),
                            #("m_outagesimulator_dictionary", m_outagesimulator_dictionary),
                            ("DataDictionaryForEachNode", DataDictionaryForEachNode),
                            ("CompiledResults", CompiledResults),
                            ("REoptInputs_Combined", REoptInputs_Combined),
                            ("substation_power_flow", value.(pm.model[Symbol("dvSubstationPowerFlow")]).data),
                            ("outage_simulator_results_for_plotting", outage_simulator_results_for_plotting)
                        ])
        else
            data_dictionary_for_plots = "N/A"
        end
        print("\n Completed compiling all the results")
    end
       
    # Optional code for saving the outputs from the SOCNLPUBFPowerModel model
    #if (Multinode_Inputs.model_subtype == "SOCNLPUBFPowerModel") && (Multinode_Inputs.generate_CSV_of_outputs == true)
    #    FilePathAndName = Multinode_Inputs.folder_location*"/Results.json"
    #    open(FilePathAndName,"w") do x
    #        JSON.print(x, PMD_Results)
    #    end
    #end

    return CompiledResults, pm.model, model_BAU, data_dictionary_for_plots
end


function PrepareElectricLoads(Multinode_Inputs)
    # Prepare the electric loads
    REopt_inputs_all_nodes = Multinode_Inputs.REopt_inputs_list

    # Prepare loads for using with the outage simulator, if the fraction method is used for determining the critical load
    if  Multinode_Inputs.critical_load_method == "Fraction"
        load_profiles_for_outage_sim_if_using_the_fraction_method = Dict([])
        for REopt_inputs in REopt_inputs_all_nodes
            load_profiles_for_outage_sim_if_using_the_fraction_method[REopt_inputs["Site"]["node"]] = deepcopy( REopt_inputs["ElectricLoad"]["loads_kw"] )
        end
        Multinode_Inputs.load_profiles_for_outage_sim_if_using_the_fraction_method = load_profiles_for_outage_sim_if_using_the_fraction_method
    else
        Multinode_Inputs.load_profiles_for_outage_sim_if_using_the_fraction_method = ""
    end
    
    # If outages are defined in the optimization, set the loads to the critical loads during the outages
    if Multinode_Inputs.model_outages_with_outages_vector
        if Multinode_Inputs.outages_vector != []

            for i in 1:length(Multinode_Inputs.REopt_inputs_list)
                if sum(Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"]) > 0 # only apply the critical load fraction if there is a load on the node

                    node = Multinode_Inputs.REopt_inputs_list[i]["Site"]["node"]
                    
                    load_segment_initial = deepcopy(Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"])
                    for outage_timestep in Multinode_Inputs.outages_vector
                        if Multinode_Inputs.critical_load_method == "Fraction"
                            Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"][outage_timestep] = Multinode_Inputs.critical_load_fraction[string(node)] * load_segment_initial[outage_timestep]
                        elseif Multinode_Inputs.critical_load_method == "TimeSeries"
                            Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"][outage_timestep] = Multinode_Inputs.critical_load_timeseries[string(node)][outage_timestep]
                        end
                    end
                end
            end
        end
    elseif Multinode_Inputs.single_outage_end_time_step - Multinode_Inputs.single_outage_start_time_step > 0
        
        OutageStart = Multinode_Inputs.single_outage_start_time_step
        OutageEnd = Multinode_Inputs.single_outage_end_time_step

        for i in 1:length(Multinode_Inputs.REopt_inputs_list)
            
            node = Multinode_Inputs.REopt_inputs_list[i]["Site"]["node"]

            if Multinode_Inputs.critical_load_method == "Fraction"
                if sum(Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"]) > 0 # only apply the critical load fraction if there is a load on the node
                    load_segment_initial = deepcopy(Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"])
                    load_segment_modified = deepcopy(load_segment_initial)
                    if !(string(node) in keys(Multinode_Inputs.critical_load_fraction))
                        throw(@error("Node $(node) is not listed in the critical_load_fraction dictionary"))
                    end
                    load_segment_modified[OutageStart:OutageEnd] = Multinode_Inputs.critical_load_fraction[string(node)] * load_segment_initial[OutageStart:OutageEnd]                    
                    delete!(Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"],"loads_kw")
                    Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"] = load_segment_modified
                end 
            elseif Multinode_Inputs.critical_load_method == "TimeSeries"
                if sum(Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"]) > 0 
                    load_segment_initial = deepcopy(Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"])
                    load_segment_modified = deepcopy(load_segment_initial)
                    if !(string(node) in keys(critical_load_timeseries))
                        throw(@error("Node $(node) is not listed in the critical_load_timeseries dictionary"))
                    end
                    load_segment_modified[OutageStart:OutageEnd] = Multinode_Inputs.critical_load_timeseries[string(node)][OutageStart:OutageEnd]                    
                    delete!(Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"],"loads_kw")
                    Multinode_Inputs.REopt_inputs_list[i]["ElectricLoad"]["loads_kw"] = load_segment_modified
                end
            end
        end
    end     
end


function build_run_and_process_results(Multinode_Inputs, REopt_inputs_combined, PMD_number_of_timesteps, timestamp, time_results; allow_upgrades=false, BAU_case=false)
    # Function to build the model, run the model, and process results

    # Empty these variables from any previous contents
    pm = nothing
    data_math_mn = nothing
    data_eng = nothing

    combined_REopt_inputs = REopt_inputs_combined
    
    pm, data_math_mn, data_eng = Create_PMD_Model_For_REopt_Integration(Multinode_Inputs, PMD_number_of_timesteps, time_results; combined_REopt_inputs = combined_REopt_inputs, BAU_case = BAU_case)
        
    LineInfo_PMD, data_math_mn, REoptInputs_Combined, 
        pm, load_phase_dictionary, gen_ind_e_to_REopt_node, 
        REopt_gen_ind_e, line_upgrade_options_each_line, 
        connections, connections_upstream, connections_downstream = Build_REopt_and_Link_To_PMD(pm, Multinode_Inputs, REopt_inputs_combined, data_math_mn, data_eng; allow_upgrades=allow_upgrades)
    
    GC.gc()

    add_objective(pm, Multinode_Inputs, REoptInputs_Combined)

    results, TerminationStatus = Run_REopt_PMD_Model(pm, Multinode_Inputs, timestamp)
    
    GC.gc()

    if TerminationStatus != "OPTIMAL"
        @warn "Optimization did not solve to optimality (status: $(TerminationStatus)). Skipping results processing and returning the failed model."
        return "N/A", "N/A", "N/A", "N/A", "N/A", "N/A", REoptInputs_Combined, data_eng, "Value not saved", pm, "N/A", "N/A", "N/A", "N/A", "N/A", "N/A", "N/A", "N/A"
    end

    REopt_Results, PMD_Results, DataDictionaryForEachNode, Dictionary_LineFlow_Power_Series, DataFrame_LineFlow_Summary, line_upgrade_results = Results_Processing_REopt_PMD_Model(pm.model, results, data_math_mn, REoptInputs_Combined, Multinode_Inputs, timestamp, time_results; allow_upgrades=allow_upgrades, line_upgrade_options_each_line = line_upgrade_options_each_line, BAU_case=BAU_case)
    
    print("\n Completed the build_run_and_process_results step")

    if !(Multinode_Inputs.include_additional_outputs_into_the_combined_results_dictionary)
        data_math_mn = "Value not saved"
    end

    return REopt_Results, PMD_Results, DataFrame_LineFlow_Summary, Dictionary_LineFlow_Power_Series, DataDictionaryForEachNode, LineInfo_PMD, REoptInputs_Combined, data_eng, data_math_mn, pm, line_upgrade_options_each_line, line_upgrade_results, load_phase_dictionary, gen_ind_e_to_REopt_node, REopt_gen_ind_e, connections, connections_upstream, connections_downstream
end


function create_list_of_upgradable_lines(Multinode_Inputs)
    # Create a list lines that are upgradable

    lines_for_upgrades_temp = []
    for i in keys(Multinode_Inputs.line_upgrade_options)
        push!(lines_for_upgrades_temp, Multinode_Inputs.line_upgrade_options[i]["locations"]) 
    end
    lines_for_upgrades = unique!(lines_for_upgrades_temp)[1]

    return lines_for_upgrades
end


function CreateDictionaryOfLineUpgradeOptions(Multinode_Inputs)
    # Generate a dictionary for the options, organized so that the keys are the lines and the values are options for each line
    
    lines_for_upgrades = create_list_of_upgradable_lines(Multinode_Inputs)
    
    line_upgrade_options_each_line = Dict([])

    for line in lines_for_upgrades
        for i in keys(Multinode_Inputs.line_upgrade_options), j in Multinode_Inputs.line_upgrade_options[i]["locations"]
            if line == j

                if line ∉ keys(line_upgrade_options_each_line) # create a new entry for that line if it is not in the line_upgrade_options_each_line dictionary

                    line_upgrade_options_each_line[line] = Dict([("max_amperage", [Multinode_Inputs.line_upgrade_options[i]["max_amps"]]),
                                                                    ("cost_per_length", [Multinode_Inputs.line_upgrade_options[i]["cost_per_meter"]]),
                                                                    ("voltage_kv", Multinode_Inputs.line_upgrade_options[i]["voltage_kv"]) # all upgrade options for a given line should have the same voltage
                                                                    #("rvalues", [Multinode_Inputs.line_upgrade_options[i]["rvalues"]]),
                                                                    #("xvalues", [Multinode_Inputs.line_upgrade_options[i]["xvalues"]])
                                                                            ])            
                else
                    push!(line_upgrade_options_each_line[line]["max_amperage"], Multinode_Inputs.line_upgrade_options[i]["max_amps"])
                    push!(line_upgrade_options_each_line[line]["cost_per_length"], Multinode_Inputs.line_upgrade_options[i]["cost_per_meter"])
                    #push!(line_upgrade_options_each_line[line_name]["rvalues"], Multinode_Inputs.line_upgrade_options[i]["rvalues"])
                    #push!(line_upgrade_options_each_line[line_name]["xvalues"], Multinode_Inputs.line_upgrade_options[i]["xvalues"])
                end
            end
        end
    end

    return line_upgrade_options_each_line
end


function model_line_upgrades(pm, Multinode_Inputs, LineInfo, data_eng)
    # Function for modeling line upgrades

    lines_for_upgrades = create_list_of_upgradable_lines(Multinode_Inputs)

    print("\n The lines for upgrades are: $(lines_for_upgrades) ")

    # Define variables for the line cost and line max amps
    @variable(pm.model, line_cost[lines_for_upgrades] >= 0 )
    @variable(pm.model, line_max_amps[lines_for_upgrades] >= 0)
    
    line_upgrade_options_each_line = CreateDictionaryOfLineUpgradeOptions(Multinode_Inputs)
    
    for line in lines_for_upgrades

        number_of_entries = length(line_upgrade_options_each_line[line]["max_amperage"])
        dv = "Bin"*line
        pm.model[Symbol(dv)] = @variable(pm.model, [1:number_of_entries], base_name=dv, Bin)
        line_length = data_eng["line"][line]["length"] 

        @constraint(pm.model, pm.model[:line_max_amps][line] == sum(pm.model[Symbol(dv)][i]*line_upgrade_options_each_line[line]["max_amperage"][i] for i in 1:number_of_entries))
        @constraint(pm.model, pm.model[:line_cost][line] == line_length * sum(pm.model[Symbol(dv)][i]*line_upgrade_options_each_line[line]["cost_per_length"][i] for i in 1:number_of_entries))
        @constraint(pm.model, sum(pm.model[Symbol(dv)][i] for i in 1:number_of_entries) == 1)

        # Constraint for limiting the power flow through line xxxx to the line_max_amps variable constrained
        i = LineInfo[line]["index"]
        
        # Based off of code in line 470 of PMD's src>core>constraint_template
        timestep = 1 # collect the network configuration information from timestep 1, which assumes that the network is not changing (fair to assume with the REopt integration)
        branch = PowerModelsDistribution.ref(pm, timestep, :branch, i)
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        f_connections = branch["f_connections"]
        t_connections = branch["t_connections"]
        f_idx = (i, f_bus, t_bus)
        t_idx = (i, t_bus, f_bus)
        
        if Multinode_Inputs.display_information_during_modeling_run
            print("\n The f_idx for line $(line) is $(f_idx)")
            print("\n The t_idx for line $(line) is $(t_idx)")
        end

        for timestep in Multinode_Inputs.PMD_time_steps
            PMD_time_step = findall(x -> x==timestep, Multinode_Inputs.PMD_time_steps)[1] #use the [1] to convert the 1-element vector into an integer
            
            p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
            p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
            
            @constraint(pm.model, p_fr[1] <= pm.model[:line_max_amps][line] * line_upgrade_options_each_line[line]["voltage_kv"])
            @constraint(pm.model, p_fr[1] >= -pm.model[:line_max_amps][line] * line_upgrade_options_each_line[line]["voltage_kv"])

            @constraint(pm.model, p_to[1] <= pm.model[:line_max_amps][line] * line_upgrade_options_each_line[line]["voltage_kv"]) 
            @constraint(pm.model, p_to[1] >= -pm.model[:line_max_amps][line] * line_upgrade_options_each_line[line]["voltage_kv"]) 
            
        end
    end
    
    return pm, line_upgrade_options_each_line
end


function model_transformer_upgrades(pm, Multinode_Inputs)
    # TODO: add this capability

    return pm
end


function PrepareREoptInputs(Multinode_Inputs, time_results)  
    # Generate the scenarios, REoptInputs, and list of REoptInputs
       
    print("\n    Creating the REopt scenarios")
    scenarios = Dict([])
    Start_time_prepare_REopt_scenarios = now()
    for i in 1:length(Multinode_Inputs.REopt_inputs_list)
        scenarios[i] = Scenario(Multinode_Inputs.REopt_inputs_list[i])
    end
    milliseconds, time_results["Step $(length(keys(time_results))+1): prepare_REopt_scenarios_time_minutes"] = CalculateComputationTime(Start_time_prepare_REopt_scenarios)
        

    print("\n    Converting the REopt scenarios into the REoptInputs format")
    REoptInputs_dictionary = Dict([])
    Start_time_prepare_REoptInputs = now()
    for i in 1:length(Multinode_Inputs.REopt_inputs_list)
        REoptInputs_dictionary[i] = REoptInputs(scenarios[i])
    end
    milliseconds, time_results["Step $(length(keys(time_results))+1): prepare_REoptInputs_time_minutes"] = CalculateComputationTime(Start_time_prepare_REoptInputs)
      

    print("\n    Compiling the REoptInputs into the same dictionary")
    Start_time_compile_REoptInputs_Into_Same_Dictionary = now()
    REopt_dictionary = [REoptInputs_dictionary[1]]
    for i in 2:length(Multinode_Inputs.REopt_inputs_list)
        push!(REopt_dictionary, REoptInputs_dictionary[i])
    end
    milliseconds, time_results["Step $(length(keys(time_results))+1): compile_REoptInputs_Into_Same_Dictionary"] = CalculateComputationTime(Start_time_compile_REoptInputs_Into_Same_Dictionary)
    
    return REopt_dictionary
end


function SetTechSizesToZero(Multinode_Settings)
    
    Multinode_Settings_No_Techs = deepcopy(Multinode_Settings)

    for i in 1:length(Multinode_Settings_No_Techs["REopt_inputs_list"])
        if ("PV" in keys(Multinode_Settings_No_Techs["REopt_inputs_list"][i])) && (string(Multinode_Settings_No_Techs["REopt_inputs_list"][i]["Site"]["node"]) != Multinode_Settings["facilitymeter_node"])
            delete!(Multinode_Settings_No_Techs["REopt_inputs_list"][i], "PV")
        end
        if "ElectricStorage" in keys(Multinode_Settings_No_Techs["REopt_inputs_list"][i])
            delete!(Multinode_Settings_No_Techs["REopt_inputs_list"][i], "ElectricStorage")
        end
        if "Generator" in keys(Multinode_Settings_No_Techs["REopt_inputs_list"][i])
            delete!(Multinode_Settings_No_Techs["REopt_inputs_list"][i], "Generator")
        end
        if string(Multinode_Settings_No_Techs["REopt_inputs_list"][i]["Site"]["node"]) != Multinode_Settings["facilitymeter_node"]
            Multinode_Settings_No_Techs["REopt_inputs_list"][i]["ElectricUtility"]["net_metering_limit_kw"] = 0
            Multinode_Settings_No_Techs["REopt_inputs_list"][i]["ElectricUtility"]["interconnection_limit_kw"] = 0
            Multinode_Settings_No_Techs["REopt_inputs_list"][i]["PV"]["can_net_meter"] = false
        end
    end
    
    Multinode_Settings_No_Techs["single_outage_start_time_step"] = 5
    Multinode_Settings_No_Techs["single_outage_end_time_step"] = 5 # set to same time as outage start time step so a single outage is not modeled
    Multinode_Settings_No_Techs["outages_vector"] = []
    Multinode_Settings_No_Techs["run_outage_simulator"] = false
    Multinode_Settings_No_Techs["generate_CSV_of_outputs"] = false
    Multinode_Settings_No_Techs["model_line_upgrades"] = false
    Multinode_Settings_No_Techs["model_transformer_upgrades"] = false
    Multinode_Settings_No_Techs["allow_export_beyond_substation"] = false

    return Multinode_Settings_No_Techs
end

# This function is a slight modification to the calc_voltage_bases function in PMD
function calc_voltage_bases(data_model::Dict{String,<:Any}, vbase_sources::Dict{String, <:Any})::Tuple{Dict,Dict}
    return ismath(data_model) ? calc_math_voltage_bases(data_model, vbase_sources) : calc_eng_voltage_bases(data_model, vbase_sources)
end


function ApplyDataEngSettings(data_eng, Multinode_Inputs)
    # Apply several miscellaneous settings to the data_eng dictionary

    data_eng["settings"]["sbase_default"] = 1.0*1E3/data_eng["settings"]["power_scale_factor"] # Set the power base (sbase) equal to 1 kW
    data_eng["voltage_source"]["source"]["bus"] = Multinode_Inputs.substation_node # "sourcebus"
    data_eng["settings"]["name"] = "OptimizationModel" 
    
    PowerModelsDistribution.add_bus_absolute_vbounds!(
        data_eng,
        phase_lb_pu = Multinode_Inputs.bus_phase_voltage_lower_bound_per_unit,
        phase_ub_pu = Multinode_Inputs.bus_phase_voltage_upper_bound_per_unit, 
        neutral_ub_pu = Multinode_Inputs.bus_neutral_voltage_upper_bound_per_unit
    )

end


function ApplyLoadProfileToPMDModel(Multinode_Inputs, data_eng, PMD_number_of_timesteps, REopt_nodes; combined_REopt_inputs = "")
    # Apply a timeseries load profile to the PMD model
    
    data_eng["time_series"] = Dict{String,Any}()
    data_eng["time_series"]["normalized_load_profile"] = Dict{String,Any}("replace" => false,
                                                                          "time" => 1:PMD_number_of_timesteps,
                                                                          "values" => zeros(PMD_number_of_timesteps)
                                                                          )

    if Multinode_Inputs.number_of_phases == 1
        for i in REopt_nodes
            data_eng["load"]["load$(i)"]["time_series"] = Dict(
                    "pd_nom"=>"normalized_load_profile",
                    "qd_nom"=> "normalized_load_profile"
            )
        end
    elseif Multinode_Inputs.number_of_phases in [2,3]        
        for p in combined_REopt_inputs
            node = p.s.site.node
            if node in REopt_nodes           
                for phase in p.s.settings.phase_numbers
                    print("\n Adding PMD load empty time series to REopt node $(node), phase $(phase)")
                    data_eng["load"]["load$(node)_phase$(phase)"]["time_series"] = Dict(
                            "pd_nom"=>"normalized_load_profile",
                            "qd_nom"=> "normalized_load_profile"
                    )
                end
            end
        end
        print("\n ")
    else
        throw(@error("The number_of_phases in the multinode inputs dictionary $(Multinode_Inputs.number_of_phases) is invalid"))
    end
end


function CreatePMDGenerators(Multinode_Inputs, data_eng, REopt_nodes; combined_REopt_inputs = "")
    # Add a generic PMD generator for each REopt node to the model, in order to be able to connect the REopt and PMD models
    
    data_eng["generator"] = Dict{String, Any}()
    if Multinode_Inputs.number_of_phases == 1
        for e in REopt_nodes
            data_eng["generator"]["REopt_gen_$(e)"] = Dict{String,Any}(
                        "status" => PowerModelsDistribution.ENABLED,
                        "bus" => data_eng["load"]["load$(e)"]["bus"],   
                        "connections" => [data_eng["load"]["load$(e)"]["connections"][1], 4], # Note: From PMD tutorial: "create a generator with the same connection setting."
                        "configuration" => PowerModelsDistribution.WYE,
            )
        end
    elseif Multinode_Inputs.number_of_phases in [2,3]
        for p in combined_REopt_inputs
            e = p.s.site.node

            if e in REopt_nodes
                for phase in p.s.settings.phase_numbers 
                    #print("\n The connections are: ")
                    #print(data_eng["load"]["load$(e)_phase$(phase)"]["connections"])
                    #print("\n")          
                    data_eng["generator"]["REopt_gen_node$(e)_phase$(phase)"] = Dict{String,Any}(
                            "status" => PowerModelsDistribution.ENABLED,
                            "bus" => data_eng["load"]["load$(e)_phase$(phase)"]["bus"],   
                            "connections" => [data_eng["load"]["load$(e)_phase$(phase)"]["connections"][1], 4],  # data_eng["load"]["load$(e)_phase$(phase)"]["connections"][1] will show the phase connection for that load. Does this only work with single phase loads? Note: From PMD tutorial: "create a generator with the same connection setting."
                            "configuration" => PowerModelsDistribution.WYE,
                    )
                end
            end
        end
    else
        throw(@error("The number_of_phases for node $(i) is invalid"))
    end
end


function Create_PMD_Model_For_REopt_Integration(Multinode_Inputs, PMD_number_of_timesteps, time_results; combined_REopt_inputs = "", outage_simulator = false, BAU_case = false)
    
    if typeof(Multinode_Inputs.PMD_network_input) == String 
        print("\n Parsing the network input file \n")
        data_eng = PowerModelsDistribution.parse_file(Multinode_Inputs.PMD_network_input, transformations=[PowerModelsDistribution.remove_all_bounds!])
        @info "Completed parsing the .dss file"
    elseif typeof(Multinode_Inputs.PMD_network_input) == Dict{String, Any}
        print("\n Saving the PMD network input as a variable")
        data_eng = Multinode_Inputs.PMD_network_input
        print("\n Completed the PMD network input as a variable")
    else
        throw(@error("The PMD_network_input input format is not valid"))
    end 
    
    data_eng_keys = keys(data_eng)
    print("\n The data_eng keys are $(data_eng_keys)")
    #print("\n The data_eng bus keys are $(keys(data_eng["bus"]))")
    #print("\n The data_eng load keys are $(keys(data_eng["load"]))")

    Start_generate_REopt_nodes_list = now()
    REopt_nodes = REopt.GenerateREoptNodesList(Multinode_Inputs) # Generate a list of the REopt nodes
    
    Start_apply_data_eng_settings = now()
    ApplyDataEngSettings(data_eng, Multinode_Inputs)
    
    Start_apply_load_profile_to_PMD_model = now()
    ApplyLoadProfileToPMDModel(Multinode_Inputs, data_eng, PMD_number_of_timesteps, REopt_nodes; combined_REopt_inputs = combined_REopt_inputs)
    
    Start_create_PMD_generators = now()
    CreatePMDGenerators(Multinode_Inputs, data_eng, REopt_nodes; combined_REopt_inputs = combined_REopt_inputs)

    # Beginning of code provided by AI
        # Kron reduction requires f_connections == t_connections for every line and switch.
        # Some DSS lines include the neutral conductor (4) in connections but reference a
        # 3×3 linecode (so rs is not inlined), or have asymmetric Bus1/Bus2 conductor lists.
        # This function makes both connection vectors consistent before transform_data_model.
        function fix_line_connections_for_kron!(data_eng)
            n_fixed = 0
            for comp_type in ("line", "switch")
                for (name, comp) in get(data_eng, comp_type, Dict())
                    f_conns = get(comp, "f_connections", Int[])
                    t_conns = get(comp, "t_connections", Int[])

                    # Step 1: if an inline rs matrix is smaller than the connection count,
                    # strip conductor 4 (neutral) from both sides.
                    rs = get(comp, "rs", nothing)
                    if rs !== nothing
                        n_matrix = size(rs, 1)
                        if n_matrix < max(length(f_conns), length(t_conns))
                            f_conns = filter(c -> c != 4, f_conns)
                            t_conns = filter(c -> c != 4, t_conns)
                            comp["f_connections"] = f_conns
                            comp["t_connections"] = t_conns
                            n_fixed += 1
                        end
                    end

                    # Step 2: Kron reduction asserts f_connections == t_connections.
                    # If they still differ (e.g. neutral on one end only, or different
                    # ordering from the DSS Bus1/Bus2 specs), force t to match f.
                    if f_conns != t_conns
                        comp["t_connections"] = copy(f_conns)
                        n_fixed += 1
                    end
                end
            end
            println("fix_line_connections_for_kron!: corrected $n_fixed line/switch connection vector(s)")
        end
        fix_line_connections_for_kron!(data_eng)
    # End of code provided by AI

    kron_reduce_indicator=true
    Start_transform_to_math_model = now()
    data_math_mn = PowerModelsDistribution.transform_data_model(data_eng, kron_reduce=kron_reduce_indicator, multinetwork=true) # Transforming the engineering model to a mathematical model in PMD 
    
    # Initialize voltage variable values:
    @info "running add_start_vrvi (this may take a few minutes for large models)\n"
    Start_vrvi = now()
    if Multinode_Inputs.number_of_phases == 1
        PowerModelsDistribution.add_start_vrvi!(data_math_mn)
    else
        @warn "Not using the add_start_vrvi function from PMD because the system is multiphase and the add_start_vrvi function appears not to work with multi-phase systems in this code"
    end

    milliseconds, PMD_vrvi_time_minutes = CalculateComputationTime(Start_vrvi)
    print("\n The PMD_vrvi_time was: $(PMD_vrvi_time_minutes) minutes \n")

    print("\n Instantiating the PMD model (this may take a few minutes for large models)\n")
    Start_instantiate = now()

    if Multinode_Inputs.model_subtype == "LPUBFDiagPowerModel"
        pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.LPUBFDiagPowerModel, PowerModelsDistribution.build_mn_mc_opf) # Note: instantiate_mc_model automatically converts the "engineering" model into a "mathematical" model
    elseif Multinode_Inputs.model_subtype == "NFAUPowerModel"
        pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.NFAUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif Multinode_Inputs.model_subtype == "ACPUPowerModel"
        pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.ACPUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif Multinode_Inputs.model_subtype == "ACRUPowerModel"
        pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.ACRUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif Multinode_Inputs.model_subtype == "IVRUPowerModel"
        pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.IVRUPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif Multinode_Inputs.model_subtype == "SOCNLPUBFPowerModel"                                      
        pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.SOCNLPUBFPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    elseif Multinode_Inputs.model_subtype == "SOCConicUBFPowerModel"
        pm = PowerModelsDistribution.instantiate_mc_model(data_math_mn, PowerModelsDistribution.SOCConicUBFPowerModel, PowerModelsDistribution.build_mn_mc_opf)
    else
        throw(@error("The PMD subtype is not valid"))
    end
    
    milliseconds, PMD_instantiate_time_minutes = CalculateComputationTime(Start_instantiate)
    print("\n The PMD_instantiate_time was: $(PMD_instantiate_time_minutes) minutes \n")
    
    # Record additional computation times for non-outage-simulator models
    if outage_simulator == false 
        if BAU_case == true
            BAU_indicator = "BAU_model_"
        else
            BAU_indicator = ""
        end

        time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"PMD_instantiate_time_minutes"] = PMD_instantiate_time_minutes

        time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"PMD_vrvi_time_minutes"] = PMD_vrvi_time_minutes

        milliseconds, PMD_transform_to_math_model_time_minutes = CalculateComputationTime(Start_transform_to_math_model)
        time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"PMD_transform_to_math_model_minutes"] = PMD_transform_to_math_model_time_minutes

        milliseconds, generate_REopt_nodes_list_minutes = CalculateComputationTime(Start_generate_REopt_nodes_list)
        time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"generate_REopt_nodes_list_minutes"] = generate_REopt_nodes_list_minutes

        milliseconds, apply_data_eng_settings_minutes = CalculateComputationTime(Start_apply_data_eng_settings)
        time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"apply_data_eng_settings_minutes"] = apply_data_eng_settings_minutes

        milliseconds, apply_load_profile_to_PMD_model_minutes = CalculateComputationTime(Start_apply_load_profile_to_PMD_model)
        time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"apply_load_profile_to_PMD_model_minutes"] = apply_load_profile_to_PMD_model_minutes

        milliseconds, create_PMD_generators_minutes = CalculateComputationTime(Start_create_PMD_generators)
        time_results["Step $(length(keys(time_results))+1): "*BAU_indicator*"create_PMD_generators_minutes"] = create_PMD_generators_minutes
    end

    return pm, data_math_mn, data_eng
end


function CreateREoptTotalExportVariables(m, REoptInputs_Combined)
    # Create Total Export variables for each REopt node, except for the facility meter node

    for p in REoptInputs_Combined
        _n = string("_", p.s.site.node)
        if string(p.s.site.node) != p.s.settings.facilitymeter_node
            m[Symbol("TotalExport"*_n)] = @expression(m, [ts in p.time_steps],
                sum(
                    m[Symbol("dvProductionToGrid"*_n)][t,u,ts] 
                    for t in p.techs.elec, u in p.export_bins_by_tech[t]
                )
                + sum(m[Symbol("dvStorageToGrid"*_n)][b,ts] for b in p.s.storage.types.all ) # This line includes battery export in the total export
            )
        else
            print("\n Not creating a total export variable for node $(p.s.site.node) because this node is the facility meter node.")
        end
    end

end


function create_load_phase_dictionary(Multinode_Inputs, REopt_nodes, REopt_inputs_combined)
    # Create a dictionary that lists the phases that are associated with each load
    load_phase_dictionary = Dict()

    for p in REopt_inputs_combined
        if p.s.site.node in REopt_nodes
            load_phase_dictionary[p.s.site.node] = p.s.settings.phase_numbers
        end
    end
    return load_phase_dictionary
end


function create_dictionary_for_gen_ind_e_to_REopt_node(Multinode_Inputs, REopt_nodes, load_phase_dictionary, gen_name2ind)

    if Multinode_Inputs.number_of_phases == 1
        gen_ind_e_to_REopt_node = Dict()
        for e in REopt_nodes
            gen_ind_e_temp = gen_name2ind["REopt_gen_$(e)"]
            gen_ind_e_to_REopt_node[gen_ind_e_temp] = e
        end

    elseif Multinode_Inputs.number_of_phases in [2,3]
        gen_ind_e_to_REopt_node = Dict()
        for e in REopt_nodes
            for phase in load_phase_dictionary[e]
                gen_ind_e_temp = gen_name2ind["REopt_gen_node$(e)_phase$(phase)"]
                gen_ind_e_to_REopt_node[gen_ind_e_temp] = e
            end
        end
        
    else
        throw(@error("The number of phases input is not valid"))
    end

    return gen_ind_e_to_REopt_node
end


function generate_PMD_information(Multinode_Inputs, REopt_nodes, REopt_inputs_combined, data_math_mn)
    
    gen_name2ind = Dict(gen["name"] => gen["index"] for (_,gen) in data_math_mn["nw"]["1"]["gen"])

    load_phase_dictionary = create_load_phase_dictionary(Multinode_Inputs, REopt_nodes, REopt_inputs_combined)
    
    gen_ind_e_to_REopt_node = create_dictionary_for_gen_ind_e_to_REopt_node(Multinode_Inputs, REopt_nodes, load_phase_dictionary, gen_name2ind)

    return gen_name2ind, load_phase_dictionary, gen_ind_e_to_REopt_node
end

    
function LinkREoptAndPMD(pm, m, data_math_mn, Multinode_Inputs, REopt_nodes, REopt_inputs_combined)
    # Link the PMD and REopt variables through constraints
    
    gen_name2ind, load_phase_dictionary, gen_ind_e_to_REopt_node = generate_PMD_information(Multinode_Inputs, REopt_nodes, REopt_inputs_combined, data_math_mn)
    
    if Multinode_Inputs.display_information_during_modeling_run
        print("\n gen_ind_e_to_REopt_node")
        print(gen_ind_e_to_REopt_node)
        print("\n")
    end

    REopt_gen_ind_e = ""

    if Multinode_Inputs.number_of_phases == 1
        REopt_gen_ind_e = [gen_name2ind["REopt_gen_$(e)"] for e in REopt_nodes];

    elseif (Multinode_Inputs.number_of_phases == 2) || (Multinode_Inputs.number_of_phases == 3)

        REopt_gen_ind_e = []
        
        print("\n Gen name to index: ")
        print(gen_name2ind)

        for e in REopt_nodes
            for phase in load_phase_dictionary[e]
                # Add the gen index to the REopt_gen_ind_e list
                gen_ind_e_temp = gen_name2ind["REopt_gen_node$(e)_phase$(phase)"]
                push!(REopt_gen_ind_e, gen_ind_e_temp)

            end
        end
    else
        throw(@error("Error in the number of phases"))
    end
    
    PMDTimeSteps_InREoptTimes = Multinode_Inputs.PMD_time_steps
    PMDTimeSteps_Indeces = collect(1:length(PMDTimeSteps_InREoptTimes))
         
    # Get the gen indeces this way: gen_name2ind = Dict(gen["name"] => gen["index"] for (_,gen) in data_math_mn["nw"]["1"]["gen"])

    #=
    dv = "dvFreeReactivePower"
    m[Symbol(dv)] = @variable(m, [REopt_gen_ind_e, PMDTimeSteps_Indeces], base_name=dv)

    @constraint(m, [k in PMDTimeSteps_Indeces, e in REopt_gen_ind_e], m[:dvFreeReactivePower][e,k] .<= 0), #500 )
    @constraint(m, [k in PMDTimeSteps_Indeces, e in REopt_gen_ind_e], m[:dvFreeReactivePower][e,k] .>= 0), #-500 )                                                 
    =#                                                    

    for e in REopt_gen_ind_e  #Note: the REopt_gen_ind_e does not contain the facility meter
       
        number_of_phases_at_load = ""
        number_of_phases_at_load = length(load_phase_dictionary[gen_ind_e_to_REopt_node[e]])
        
        # Note: evenly split the total export and import across each phase associated with that load (aka REopt node, aka PMD generator)
        JuMP.@constraint(m, [k in PMDTimeSteps_Indeces],  
                            PowerModelsDistribution.var(pm, k, :pg, e).data[1] .== round((1/number_of_phases_at_load), digits = 3) * (m[Symbol("TotalExport_"*string(gen_ind_e_to_REopt_node[e]))][PMDTimeSteps_InREoptTimes[k]] - m[Symbol("dvGridPurchase_"*string(gen_ind_e_to_REopt_node[e]))][PMDTimeSteps_InREoptTimes[k]])   # negative power "generation" is a load
        )
        
        # TODO: add reactive power to the REopt nodes
        if Multinode_Inputs.model_subtype != "NFAUPowerModel"
            JuMP.@constraint(m, [k in PMDTimeSteps_Indeces],
                                PowerModelsDistribution.var(pm, k, :qg, e).data[1] .== 0.0 # m[:dvFreeReactivePower][e,k]  # (1/number_of_phases_at_load) * m[Symbol("TotalExport_"*string(buses[e]))][PMDTimeSteps_InREoptTimes[k]] - m[Symbol("dvGridPurchase_"*string(buses[e]))][PMDTimeSteps_InREoptTimes[k]] 
            )
        end
    end

    return REopt_gen_ind_e, load_phase_dictionary, gen_ind_e_to_REopt_node

end


function add_transformer_lines_to_the_dictionary(data_eng, lines, phases_for_each_line)
    # Represent transformers as lines because voltage is not modeled in the simple powerflow representation without PMD

    transformers = collect(keys(data_eng["transformer"]))
    transformer_busses = Dict()
    for transformer_name in transformers
        transformer_bus1 = data_eng["transformer"][transformer_name]["bus"][1]
        transformer_bus2 = data_eng["transformer"][transformer_name]["bus"][2]
        transformer_line = "xfmr_line_"*string(transformer_bus1)*"_"*string(transformer_bus2) 
        transformer_busses[transformer_line] = [transformer_bus1, transformer_bus2]
        if !(transformer_line in lines)     
            push!(lines, transformer_line)
        else
            print("\n Not adding $(transformer_line) to the lines vector because it already exists. This is likely due to a multiple single phase transformers (or voltage regulators) connecting the same busses. The total power rating for these may need to be added together in the model inputs.")
        end

        # Add the phases for the transformer line to dictionary:
        if !(transformer_line in collect(keys(phases_for_each_line)))  # use this conditional to avoid adding multiple lines for the same connection between two nodes (could occur if there are single phase transformers or voltage regulators connecting each of of two adjacent three-phase busses)
            phases_for_each_line[transformer_line] = filter!(x -> x != 4, data_eng["transformer"][transformer_name]["connections"][1]) # Remove the 4 connection (the neutral I think) for the purposes of this simple powerflow equation
        else
            # Add the phase to the existing line between the two busses (which is from another transformer or voltage regulator, likely a single phase transformer connecting the same two busses)
            append!(phases_for_each_line[transformer_line], filter!(x -> x != 4, data_eng["transformer"][transformer_name]["connections"][1])) 
        end
    end

    return phases_for_each_line, lines, transformer_busses
end


function CreateDictionaryOfNodeConnections(Multinode_Inputs, data_eng)
   # Create dictionary with information about which lines are connected to each bus

    summed_lengths_to_sourcebus_dict, lengths_to_sourcebus_dict, line_names_to_sourcebus_dict, paths, neighbors = REopt.DetermineDistanceFromSourcebus(Multinode_Inputs, data_eng)
    print("\n Finished determining the distance from the sourcebus")

    # Create a new dictionary based on the paths (which will include the transformer path)
    line_names_to_sourcebus_dict_including_transformers = "This variable is not used anymore" # Dict()

    # Initial the lines vector based on data in PMD (which doesn't represent the transformers as lines)
    lines = collect(keys(data_eng["line"]))

    # Initiate this dictionary with just the phases for each line; 
    phases_for_each_line =  create_dictionary_of_phases_for_each_line(data_eng) 
    
    # Then add the line IDs and phases for each transformer, representing the transformers as lines
    phases_for_each_line_and_transformer_line, lines, transformer_busses = add_transformer_lines_to_the_dictionary(data_eng, lines, phases_for_each_line)

    connections_upstream_busses = Dict()
    connections_downstream_busses = Dict()
    all_lines_including_transformers_converted_to_lines = collect(keys(phases_for_each_line_and_transformer_line))

    all_busses = keys(neighbors)
    for bus in all_busses
        upstream_path = paths[bus]
        neighboring_busses = neighbors[bus]

        overlap = intersect(neighboring_busses, upstream_path)
        if length(overlap) > 1 # This should be correected if want to model mesh networks
            throw(@error("There are multiple upstream busses to bus $(bus)"))
        end

        if length(overlap) == 1
            #print("\n Overlap length is 1")
            upstream_bus = overlap[1]
        else
            print("\n Overlap length is not 1 or greater than 1 for bus $(bus), which should be the source bus")
            print("\n")
            upstream_bus = "N/A"
        end

        downstream_busses = setdiff(neighboring_busses, upstream_path) # Finds the busses that are neighbors that are not part of the upstream path
        connections_upstream_busses[bus] = upstream_bus
        connections_downstream_busses[bus] = downstream_busses
    end
   
    bus_pair_to_line_conversion = Dict()

    for line in all_lines_including_transformers_converted_to_lines
        if line in keys(data_eng["line"])
            node1 = data_eng["line"][line]["f_bus"]
            node2 = data_eng["line"][line]["t_bus"]
            bus_pair_to_line_conversion[(node1, node2)] = line
        elseif line in keys(transformer_busses)
            node1 = transformer_busses[line][1]
            node2 = transformer_busses[line][2]
            bus_pair_to_line_conversion[(node1, node2)] = line
        else
            throw(@error("Error converting the bus-pair to line for line $(line) "))
        end
    end

    connections_upstream_lines = Dict()
    connections_downstream_lines = Dict()

    # Loop through all downstream connections_busses and identify the corresponding line using the bus_pair_to_line_conversion
    for bus in collect(keys(connections_downstream_busses))
        downstream_lines_temp = []       
        downstream_buses = connections_downstream_busses[bus]
        for downstream_bus in downstream_buses
            if (bus, downstream_bus) in keys(bus_pair_to_line_conversion)
                push!(downstream_lines_temp, bus_pair_to_line_conversion[(bus, downstream_bus)])
            elseif (downstream_bus, bus) in keys(bus_pair_to_line_conversion)
                push!(downstream_lines_temp, bus_pair_to_line_conversion[(downstream_bus, bus)])
            else
                throw(@error("No line found for the downstream neighboring bus pair $(bus) and $(downstream_bus)"))
            end
        end
        connections_downstream_lines[bus] = downstream_lines_temp
    end

    # Loop through all upstream connections_busses and identify the corresponding line using the bus_pair_to_line_conversion
    for bus in collect(keys(connections_upstream_busses))
        upstream_lines_temp = []       
        upstream_bus = connections_upstream_busses[bus]
        #for upstream_bus in upstream_buses # use something like this for mesh networks probably
        if (bus, upstream_bus) in keys(bus_pair_to_line_conversion)
            push!(upstream_lines_temp, bus_pair_to_line_conversion[(bus, upstream_bus)])
        elseif (upstream_bus, bus) in keys(bus_pair_to_line_conversion)
            push!(upstream_lines_temp, bus_pair_to_line_conversion[(upstream_bus, bus)])
        elseif bus == Multinode_Inputs.substation_node
            print("\n The bus $(bus) is the substation node, so no upstream lines are being added to the connections_upstream_lines dictionary for that bus")
        else
            throw(@error("No line found for the upstream neighboring bus pair $(bus) and $(upstream_bus)"))
        end
        #end
        connections_upstream_lines[bus] = upstream_lines_temp
    end

    all_connections_lines_to_busses = merge(connections_downstream_lines, connections_upstream_lines) do a, b
                                            vcat(a, b)
                                        end

    if Multinode_Inputs.display_information_during_modeling_run
       # Save some text files showing connectivity from the simple powerflow model
        open(Multinode_Inputs.folder_location*"/paths.txt","w") do input
            for (key, val) in paths
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/neighbors.txt","w") do input
            for (key, val) in neighbors
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/all_connections_lines_to_busses.txt","w") do input
            for (key, val) in all_connections_lines_to_busses
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/connections_upstream_busses.txt","w") do input
            for (key, val) in connections_upstream_busses
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/connections_downstream_busses.txt","w") do input
            for (key, val) in connections_downstream_busses
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/bus_pair_to_line_conversion.txt","w") do input
            for (key, val) in bus_pair_to_line_conversion
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/connections_downstream_lines.txt","w") do input
            for (key, val) in connections_downstream_lines
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/connections_upstream_lines.txt","w") do input
            for (key, val) in connections_upstream_lines
                println(input, "$key => $val" ) 
            end
        end
    end

    return all_connections_lines_to_busses, connections_upstream_lines, connections_downstream_lines, lines, transformer_busses, line_names_to_sourcebus_dict_including_transformers, phases_for_each_line_and_transformer_line
end


function create_dictionary_of_phases_for_each_line(data_eng)
    data = Dict([])

    for line in keys(data_eng["line"])
        data[line] = data_eng["line"][line]["t_connections"]
    end
    
    return data
end


function create_dictionary_of_phases_for_each_bus(data_eng)
    data = Dict([])

    for bus in keys(data_eng["bus"])
        data[bus] = filter(x -> x != 4, data_eng["bus"][bus]["terminals"])  # remove the 4 from the list of terminals to get the phase numbers
    end

    return data
end


function AddSimplePowerFlowConstraintsToNonPMDTimesteps(Multinode_Inputs, REoptInputs_Combined, pm, m, REoptTimeSteps, LineInfo, REopt_nodes, data_eng)
    print("\n Adding Simple Powerflow Constraints to Non-PMD Timesteps: This can take a few minutes for very large models")
    
    time_steps_without_PMD = setdiff(REoptTimeSteps, Multinode_Inputs.PMD_time_steps)
    indeces = collect(1:length(time_steps_without_PMD))
    print("\n Generated timesteps vector and indeces")

    connections, connections_upstream, connections_downstream, lines, transformer_busses, line_names_to_sourcebus_dict_including_transformers, phases_for_each_line_and_transformer_line = CreateDictionaryOfNodeConnections(Multinode_Inputs, data_eng)  # Note: the lines variable here includes lines that represent the transformer
    print("\n Finished creating a dictionary of node connections")

    if Multinode_Inputs.display_information_during_modeling_run
        print("\n")
        print("\n Connectivity information used in the simple power flow model:")
        print("\n The connections are: ")
        print(connections)
        print("\n\n The upstream connections are: ")
        print(connections_upstream)  
        print("\n\n The downstream connections are: ")
        print(connections_downstream)
        print("\n")
        print("\n")
    end

    if Multinode_Inputs.number_of_phases == 3
        phases = [1,2,3]
    elseif Multinode_Inputs.number_of_phases == 2
        phases = [1,2]
    elseif Multinode_Inputs.number_of_phases == 1
        phases = [1]
    else
        throw(@error("The input for the number of phases is invalid"))
    end
    
    # Create a dictionary such that, for instance, phases_for_each_line["line_name"] = [1,2,3] for three phase, or [3] for single phase on phase #3, or [2,3] for two phase
    print("\n Generating dvP variable for busses (this may take a few minutes for large models using the simple powerflow constraints)")
    
    phases_for_each_bus = create_dictionary_of_phases_for_each_bus(data_eng) 
    all_busses = collect(keys(data_eng["bus"])) # This includes both the PMD and the REopt busses
    @variable(m, dvP[bus in all_busses, phase in phases, t in indeces; phase in phases_for_each_bus[bus]] >= -1000000 )
    #@variable(m, Q[REopt_nodes] >= -10000000)
    
    print("\n Generating dvP variable for lines (this may take a few minutes for large models using the simple powerflow constraints)")
    phases_for_each_line =  create_dictionary_of_phases_for_each_line(data_eng) 
    
    if Multinode_Inputs.display_information_during_modeling_run
        print("\n The lines are: $(lines)")
        print("\n")
        #print("\n The phases for each line are: $(phases_for_each_line)")
        #print("\n")
        print("\n The phases for each line are: $(phases_for_each_line_and_transformer_line)")
        print("\n")
    end
    
    @variable(m, dvPline[line in lines, phase in phases, t in indeces; phase in phases_for_each_line_and_transformer_line[line]] >= -1000000)
    #@variable(m, dvQline[lines, indeces])
    print("\n Completed dvP variable generation")
       
    phases_for_each_line = phases_for_each_line_and_transformer_line
    
    # Add constraints for maximum power through each line
    if Multinode_Inputs.model_line_upgrades
        print("Adding simple powerflow constraints to allow for line upgrades")
        line_upgrade_options_each_line = CreateDictionaryOfLineUpgradeOptions(Multinode_Inputs)
        for line in lines
            
            if line in collect(keys(phases_for_each_line)) # prevent looking for a line if it is a virtual line part of a transformer
                if length(phases_for_each_line[line]) == 3 
                    multiphase_multiplier = sqrt(3) # Use the sqrt(3) factor for three-phase lines
                else
                    # Don't use the sqrt(3) factor for single phase or two phase lines. This assumes that a two-phase system is a 4-wire two phase system where each phase has its own nuetral (instead of a 3-wire two phase system)
                    multiphase_multiplier = 1
                end
            else
                multiphase_multiplier = 1
            end

            if line in keys(line_upgrade_options_each_line)
              
                # Note: line amperage ratings are for each conductor in a multiphase system
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], dvPline[line, phase, t] <= m[:line_max_amps][line] * line_upgrade_options_each_line[line]["voltage_kv"] * multiphase_multiplier)
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], dvPline[line, phase, t] >= -m[:line_max_amps][line] * line_upgrade_options_each_line[line]["voltage_kv"] * multiphase_multiplier)

            elseif line in keys(transformer_busses)
                # Note: transformer power ratings are for power going through all phases combined, but for simplicity
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] .<= 100000000 / 1) # TODO: replace the 10000000 with the transformer power rating add maximum transformer power
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] .>= -100000000 / 1)
            else
                if LineInfo[line]["maximum_power_kw"] == Inf
                    line_max_power = 1000000000 #LineInfo[line]["maximum_power_kw"]
                    if Multinode_Inputs.display_information_during_modeling_run
                        print("\n Line max power for line $(line) is infinite, setting the line_max_power for $(line) to $(line_max_power)")
                    end
                else
                    line_max_power = LineInfo[line]["maximum_power_kw"] * multiphase_multiplier
                end
                
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] <= line_max_power) # Defines the maximum real power flow through the line
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] >= -line_max_power)
            end
        end
    else
        print("\n Line and phase information, shown if display_information_during_modeling_run is set to true in the inputs dictionary: [")
        for line in lines
            Multinode_Inputs.display_information_during_modeling_run ? print("The line is: $(line) which has phases: $(phases_for_each_line[line]), ") : nothing

            if line in keys(transformer_busses)
                if Multinode_Inputs.display_information_during_modeling_run
                    print("  this is a line that was derived from a transformer")
                end
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] <= 100000000 / 1) # TODO: replace the 10000000 with the transformer power rating add maximum transformer power
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] >= -100000000 / 1)
            else
                if LineInfo[line]["maximum_power_kw"] == Inf
                    line_max_power = 1000000000 #LineInfo[line]["maximum_power_kw"]
                else
                    line_max_power = LineInfo[line]["maximum_power_kw"] * multiphase_multiplier
                end
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] <= line_max_power) # LineInfo[line]["maximum_power_kw"] * multiphase_multiplier) # Defines the maximum real power flow through the line
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] >= -line_max_power) # LineInfo[line]["maximum_power_kw"] * multiphase_multiplier)
                #@constraint(m, m[:dvQline][line, t] <= )
                #@constraint(m, m[:dvQline][line, t] >= 0)
            end
        end
        print("\n]")
    end
    
    counter = 0

    # Link this simple powerflow model to the REopt nodes
    Multinode_Inputs.display_information_during_modeling_run ? print("\n Information about connecting the REopt nodes to the simple powerflow model") : nothing
    for t in REoptTimeSteps
        if t in time_steps_without_PMD
            index = findall(x->x==t, time_steps_without_PMD)[1]
            counter = counter + 1
            for node in REopt_nodes  # only link the REopt nodes to PMD busses
                if string(node) != Multinode_Inputs.substation_node
                    if counter in [1,2] # print information only for the first two timesteps
                        Multinode_Inputs.display_information_during_modeling_run ? print("\n Connecting REopt node $(node) to the simple powerflow model") : nothing
                    end
                    for phase in phases_for_each_bus[string(node)]
                        # This constraint assumes that multiphase nodes with loads (or generators) consume (or distribute) power evenly across each phase
                        @constraint(m, m[:dvP][string(node), phase, index] .== (1/length(phases_for_each_bus[string(node)])) .* ((m[Symbol("TotalExport_"*string(node))][t]) .- (m[Symbol("dvGridPurchase_"*string(node))][t])) ) # To do: double check that these variable names are correct
                        
                        if Multinode_Inputs.display_information_during_modeling_run 
                            if t in [1,2] # print out some information for the first couple timesteps
                                print("\n For node $(node), the phases_for_each_bus are: $(phases_for_each_bus[string(node)]), with a length of $(length(phases_for_each_bus[string(node)]))")
                                print("\n    The index is $(index), and the t i $(t), and the phase is $(phase)")
                                print("\n    (1/length(phases_for_each_bus[string(node)])) is $((1/length(phases_for_each_bus[string(node)])))")
                            end
                        end
                    
                    end
                else
                    # I don't think this is necessary because the substation node isn't part of REopt nodes
                    #if counter < 3
                    #    print("\n ****** Not connecting simple powerflow model to REopt for node $(node), which is the substation node")
                    #end
                end
            end
        end
    end

    if Multinode_Inputs.display_information_during_modeling_run
        # Save some text files showing connectivity from the simple powerflow model
        open(Multinode_Inputs.folder_location*"/connections_upstream.txt","w") do input
            for (key, val) in connections_upstream
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/connections_downstream.txt","w") do input
            for (key, val) in connections_downstream
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/connections.txt","w") do input
            for (key, val) in connections
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/phases_for_each_line.txt","w") do input
            for (key, val) in phases_for_each_line
                println(input, "$key => $val" ) 
            end
        end
        open(Multinode_Inputs.folder_location*"/phases_for_each_line_and_transformer_line.txt","w") do input
            for (key, val) in phases_for_each_line_and_transformer_line
                println(input, "$key => $val" ) 
            end
        end
    end
  print("\n The phases for each bus are: $(phases_for_each_bus)")
  print("\n The REopt nodes are: $(REopt_nodes)")
    # Conservation of energy for each bus
    for bus in collect(keys(connections)) # all_busses #
        bus_connections = connections[bus]
        
        if bus == Multinode_Inputs.substation_node
            #print("\n Adding constraint for substation bus $(bus)")
            # TODO: does this constraint need to exist?
            #@constraint(m, [t in indeces], m[:dvP][bus, t] - sum(m[:dvPline][line, t] for line in connections_downstream[string(bus)]) == 0)

        elseif bus in REopt_nodes # parse(Int, bus) in REopt_nodes  # for buses that have an associated REopt node
            Multinode_Inputs.display_information_during_modeling_run ? print("\n Adding constraint for REopt bus $(bus):") : nothing
            if length(connections_downstream[bus]) > 0
                Multinode_Inputs.display_information_during_modeling_run ? print(" mid-branch") : nothing
                # For nodes that have upstream and downstream lines
                    # This code assumes that the network has been defined correctly such that the phases on the lines are connected correctly to the phases on each bus
                for phase in phases_for_each_bus[bus]

                    connections_upstream_of_same_phase = []
                    for line in connections_upstream[string(bus)]
                        if phase in phases_for_each_line[line]
                            push!(connections_upstream_of_same_phase, line)
                        end
                    end

                    connections_downstream_of_same_phase = []
                    for line in connections_downstream[string(bus)]
                        if phase in phases_for_each_line[line]
                            push!(connections_downstream_of_same_phase, line)
                        end
                    end

                    @constraint(m, [t in indeces], m[:dvP][bus, phase, t] + sum(m[:dvPline][line, phase, t] for line in connections_upstream_of_same_phase) - sum(m[:dvPline][line, phase, t] for line in connections_downstream_of_same_phase) == 0)
                end
            else # This else might not be used because all busses should be in the keys of the connections_downstream
                Multinode_Inputs.display_information_during_modeling_run ? print(" at the end of a branch") : nothing
                # For nodes that are at the end of branch
                    # This code assumes that the network has been defined correctly such that the phases on the lines are connected correctly to the phases on each bus
            
                for phase in phases_for_each_bus[bus]
                    connections_upstream_of_same_phase = []
                    for line in connections_upstream[string(bus)]
                        if phase in phases_for_each_line[line]
                            push!(connections_upstream_of_same_phase, line)
                        end
                    end
                    @constraint(m, [t in indeces], m[:dvP][bus, phase, t] + sum(m[:dvPline][line, phase, t] for line in connections_upstream_of_same_phase) == 0)
                end
            end
            
        else # for buses in the model without a REopt node
            Multinode_Inputs.display_information_during_modeling_run ? print("\n Adding constraint for non-REopt bus $(bus):") : nothing
            if length(connections_downstream[bus]) > 0
                Multinode_Inputs.display_information_during_modeling_run ? print(" mid-branch") : nothing

                for phase in phases_for_each_bus[bus]
                    connections_upstream_of_same_phase = []
                    for line in connections_upstream[string(bus)]
                        if phase in phases_for_each_line[line]
                            push!(connections_upstream_of_same_phase, line)
                        end
                    end

                    connections_downstream_of_same_phase = []
                    for line in connections_downstream[string(bus)]
                        if phase in phases_for_each_line[line]
                            push!(connections_downstream_of_same_phase, line)
                        end
                    end
                    @constraint(m, [t in indeces], sum(m[:dvPline][line, phase, t] for line in connections_upstream_of_same_phase) - sum(m[:dvPline][line, phase, t] for line in connections_downstream_of_same_phase) == 0)
                end
            else
                Multinode_Inputs.display_information_during_modeling_run ? print(" at the end of a branch") : nothing
                
                for phase in phases_for_each_bus[bus]
                    connections_upstream_of_same_phase = []
                    for line in connections_upstream[string(bus)]
                        if phase in phases_for_each_line[line]
                            push!(connections_upstream_of_same_phase, line)
                        end
                    end
                    @constraint(m, [t in indeces], sum(m[:dvPline][line, phase, t] for line in connections_upstream_of_same_phase) == 0)
                end
            end
        end
    end

    return connections, connections_upstream, connections_downstream
end


function Build_REopt_and_Link_To_PMD(pm, Multinode_Inputs, REopt_inputs_combined, data_math_mn, data_eng; OutageSimulator=false, OutageLength_Timesteps=0, allow_upgrades=false)
    
    m = pm.model   
    REopt_nodes = REopt.GenerateREoptNodesList(Multinode_Inputs)
    REoptInputs_Combined = REopt_inputs_combined 
    Multinode_Inputs.display_information_during_modeling_run ? print("\n The REopt nodes are: $(REopt_nodes)") : nothing
    print("\n Building the REopt model\n")
    REopt.build_reopt!(m, REoptInputs_Combined) # Pass the PMD JuMP model (with the PowerModelsDistribution variables and constraints) as the JuMP model that REopt should build onto
    
    CreateREoptTotalExportVariables(m, REoptInputs_Combined)
    REopt_gen_ind_e, load_phase_dictionary, gen_ind_e_to_REopt_node = LinkREoptAndPMD(pm, m, data_math_mn, Multinode_Inputs, REopt_nodes, REoptInputs_Combined)
    LineInfo = CreateLineInfoDictionary(Multinode_Inputs, pm, data_math_mn)
    REoptTimeSteps = collect(1:(Multinode_Inputs.time_steps_per_hour * 8760))
    
    line_upgrade_options_each_line = "N/A"
    
    # Only allow for upgrades and add simple power flow constraints if not running the outage simulator

    if allow_upgrades == true
        if Multinode_Inputs.model_line_upgrades == true
            pm, line_upgrade_options_each_line = model_line_upgrades(pm, Multinode_Inputs, LineInfo, data_eng)          
        end

        if Multinode_Inputs.model_transformer_upgrades == true
            #pm = model_transformer_upgrades(pm, Multinode_Inputs) # TODO: add transformer upgrades
        end
    end
        
    if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD && (OutageSimulator == false)
        # Don't apply these constraints if the outage simulator is being used because the outage simulator applies PMD constraints to all time steps
        connections, connections_upstream, connections_downstream = AddSimplePowerFlowConstraintsToNonPMDTimesteps(Multinode_Inputs, REoptInputs_Combined, pm, m, REoptTimeSteps, LineInfo, REopt_nodes, data_eng)
    else
        connections = "N/A"
        connections_upstream = "N/A" 
        connections_downstream = "N/A"
    end

    ApplyGridImportAndExportConstraints(Multinode_Inputs, REoptInputs_Combined, pm, m, REoptTimeSteps, LineInfo, OutageSimulator, OutageLength_Timesteps, data_eng)
    
    LinkFacilityMeterNodeToSubstationPower(m, pm, Multinode_Inputs, REoptInputs_Combined, LineInfo, REopt_gen_ind_e, REoptTimeSteps, REopt_nodes, data_math_mn, data_eng)
    
    if Multinode_Inputs.generators_only_run_during_grid_outage == true
        LimitGeneratorOperatingTimes(m, Multinode_Inputs, REoptInputs_Combined)
    end

    return LineInfo, data_math_mn, REoptInputs_Combined, pm, load_phase_dictionary, gen_ind_e_to_REopt_node, REopt_gen_ind_e, line_upgrade_options_each_line, connections, connections_upstream, connections_downstream
end


function add_objective(pm, Multinode_Inputs, REoptInputs_Combined)

    @expression(pm.model, Costs, sum(pm.model[Symbol(string("Costs_", p.s.site.node))] for p in REoptInputs_Combined) )
    
    if Multinode_Inputs.model_line_upgrades
        @info "Including the line upgrade costs in the Costs expression"
        lines_for_upgrades = create_list_of_upgradable_lines(Multinode_Inputs)

        @variable(pm.model, total_line_upgrade_cost >= 0)
        @constraint(pm.model, pm.model[:total_line_upgrade_cost] == sum(pm.model[:line_cost][line] for line in lines_for_upgrades))

        add_to_expression!(Costs, pm.model[:total_line_upgrade_cost])
    end
    
    if Multinode_Inputs.allow_bus_voltage_violations
        @info "Allowing bus voltage violations"
        add_bus_voltage_violation_to_the_model(pm, Multinode_Inputs)
        add_to_expression!(Costs, pm.model[:dvBusVoltageViolationCost])
    end
    
    @objective(pm.model, Min, pm.model[:Costs]) # Define the optimization objective

end


function create_bus_info_dictionary(pm)
      # Creates a dictionary with the bus names and corresponding indeces for the :w decision variable (which is the voltage squared decision variable)
      BusInfo = Dict([])
      NumberOfBusses = length(PowerModelsDistribution.ref(pm,1,:bus))
      for i in 1:NumberOfBusses
          BusData = PowerModelsDistribution.ref(pm, 1, :bus, i)
          BusInfo[BusData["name"]] = Dict(["index"=>BusData["index"], "terminals"=>BusData["terminals"], "bus_i"=>BusData["bus_i"], "vbase"=>BusData["vbase"]]) 
      end
      return BusInfo
end


function add_bus_voltage_violation_to_the_model(pm, Multinode_Inputs)
    model = pm.model
    
    BusInfo = create_bus_info_dictionary(pm)

    bus_names = collect(keys(BusInfo))

    PMD_time_steps = collect(1:length(Multinode_Inputs.PMD_time_steps))
     
    # Create the voltage violation binary variables
    @variable(pm.model, binBusVoltageViolation[bus_names, PMD_time_steps], Bin)

    # Add contraints
    for PMD_time_step in PMD_time_steps
        for bus_name in bus_names
            index = BusInfo[bus_name]["index"]
            voltage_squared = [PowerModelsDistribution.var(pm, PMD_time_step, :w, index)[terminal] for terminal in BusInfo[bus_name]["terminals"]]
            
            if Multinode_Inputs.display_information_during_modeling_run 
                # print out information to understand the approach in the code:
                #print("\n For bus $(bus_name) the terminals are: ")
                #print(BusInfo[bus_name]["terminals"])
                #print("\n For bus $(bus_name) the voltage_squared variable is: ")
                #print(voltage_squared)
                #index_temp = findall(x -> x== BusInfo[bus_name]["terminals"][1], BusInfo[bus_name]["terminals"])[1]
                #print("The index in voltage_squared for terminal $(BusInfo[bus_name]["terminals"][1]) is $(index_temp) ")
            end

            for terminal in BusInfo[bus_name]["terminals"]
                terminal_index = findall(x -> x== terminal, BusInfo[bus_name]["terminals"])[1]
                @constraint(model, voltage_squared[terminal_index] <= (Multinode_Inputs.bus_per_unit_voltage_target_upper_bound^2) + model[:binBusVoltageViolation][bus_name, PMD_time_step] * 100) # multiply by 100 to make the possible voltage very large
                @constraint(model, voltage_squared[terminal_index] >= (Multinode_Inputs.bus_per_unit_voltage_target_lower_bound^2) * (1 - model[:binBusVoltageViolation][bus_name, PMD_time_step])) # If the binary is one, then the voltage squared can go to zero
            end

        end
    end

    # Calculate the total cost of the bus voltage violations
    @variable(model, dvBusVoltageViolationCost, lower_bound = 0)

    @constraint(model, model[:dvBusVoltageViolationCost] == sum(model[:binBusVoltageViolation][bus_name, PMD_time_step] for bus_name in bus_names, PMD_time_step in PMD_time_steps))

end


function ApplyGridImportAndExportConstraints(Multinode_Inputs, REoptInputs_Combined, pm, m, REoptTimeSteps, LineInfo, OutageSimulator, OutageLength_Timesteps, data_eng)
    # Apply a variety of grid import and/or export constraints:
    
    # Restrict power flow from the substation if the multinode type is offgrid
    if Multinode_Inputs.multinode_type == "Offgrid" 
        RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, REoptTimeSteps, LineInfo, data_eng; Off_Grid=true)
    end
    
    # Define limits on grid import and export
    if Multinode_Inputs.allow_export_beyond_substation == false # Prevent power from being exported to the grid beyond the facility meter:
        print("\n Prohibiting power export at the substation")
        #RestrictLinePowerFlow(Multinode_Inputs, pm, m, Multinode_Inputs.substation_line, REoptTimeSteps, LineInfo; Prevent_Export=true) # This constraint is handled by other constraints below
    elseif Multinode_Inputs.substation_export_limit != ""
        print("\n Applying a limit to the power export at the substation")
        RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, REoptTimeSteps, LineInfo, data_eng; Substation_Export_Limit = Multinode_Inputs.substation_export_limit)
    end 
    
    if Multinode_Inputs.substation_import_limit != ""
        print("\n Applying a limit to the power import from the substation")
        RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, REoptTimeSteps, LineInfo, data_eng; Substation_Import_Limit = Multinode_Inputs.substation_import_limit)
    end 
    
    # Apply a grid outage to the model
    if Multinode_Inputs.model_outages_with_outages_vector
        if Multinode_Inputs.outages_vector != []
            print("\n Applying a grid outages on the following timesteps: ")
            print(Multinode_Inputs.model_outages_with_outages_vector)
            RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, Multinode_Inputs.outages_vector, LineInfo, data_eng; Grid_Outage=true, OutageSimulator = OutageSimulator, OutageLength_Timesteps = OutageLength_Timesteps)
        end    
    elseif Multinode_Inputs.single_outage_end_time_step - Multinode_Inputs.single_outage_start_time_step > 0
        print("\n Applying a grid outage from time step $(Multinode_Inputs.single_outage_start_time_step) to $(Multinode_Inputs.single_outage_end_time_step) ")
        RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, collect(Multinode_Inputs.single_outage_start_time_step:Multinode_Inputs.single_outage_end_time_step), LineInfo, data_eng; Grid_Outage=true, OutageSimulator = OutageSimulator, OutageLength_Timesteps = OutageLength_Timesteps)
    end
    
    # Open switches if defined by the user
        # Note: the switch capability in PMD is not used currently in this model, but the switch openings are modeling with these constraints
    if (Multinode_Inputs.switch_open_timesteps != "") && (Multinode_Inputs.model_switches == true)
        print("\n Switches are included in the model")
        for i in keys(Multinode_Inputs.switch_open_timesteps)
            #print("\n   Opening the switch on line $(i) from timesteps $(minimum(Multinode_Inputs.switch_open_timesteps[i])) to $(maximum(Multinode_Inputs.switch_open_timesteps[i])) \n")
            RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, i, Multinode_Inputs.switch_open_timesteps[i], LineInfo, data_eng; Switches_Open=true)
        end
    end
    
end


function LinkFacilityMeterNodeToSubstationPower(m, pm, Multinode_Inputs, REoptInputs_Combined, LineInfo, REopt_gen_ind_e, REoptTimeSteps, REopt_nodes, data_math_mn, data_eng)
    # Link export through the substation to the utility tariff on the facility meter node
    
    PMDTimeSteps_InREoptTimes = Multinode_Inputs.PMD_time_steps
    buses = REopt_nodes

    gen_name2ind, load_phase_dictionary, gen_ind_e_to_REopt_node = generate_PMD_information(Multinode_Inputs, REopt_nodes, REoptInputs_Combined, data_math_mn)

    if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
        time_steps_without_PMD = setdiff(REoptTimeSteps, Multinode_Inputs.PMD_time_steps)
    else
        time_steps_without_PMD = 0
    end

    phases_for_each_line =  create_dictionary_of_phases_for_each_line(data_eng)

    for p in REoptInputs_Combined
        if string(p.s.site.node) == p.s.settings.facilitymeter_node

            Multinode_Inputs.display_information_during_modeling_run ? print("\n The export bins for the facility meter node are: $(p.export_bins_by_tech["PV"]) \n") : nothing
            
            i = LineInfo[lowercase(Multinode_Inputs.substation_line)]["index"]
                # Based off of code in line 470 of PMD's src>core>constraint_template
                timestep = 1 # collect the network configuration information from timestep 1, which assumes that the network is not changing (fair to assume with the REopt integration)
                branch = PowerModelsDistribution.ref(pm, timestep, :branch, i)
                f_bus = branch["f_bus"]
                t_bus = branch["t_bus"]
                f_connections = branch["f_connections"]
                t_connections = branch["t_connections"]
                f_idx = (i, f_bus, t_bus)
                t_idx = (i, t_bus, f_bus)
    
            @variable(m, binSubstationPositivePowerFlow[ts in REoptTimeSteps], Bin)
            @variable(m, dvSubstationPowerFlow[ts in REoptTimeSteps])
                        
            for timestep in REoptTimeSteps
                
                @constraint(m, m[:dvSubstationPowerFlow][timestep] <= m[:binSubstationPositivePowerFlow][timestep] * 1000000 )
                @constraint(m, m[:dvSubstationPowerFlow][timestep] >=  (1 - m[:binSubstationPositivePowerFlow][timestep]) * -1000000 )

                if Multinode_Inputs.allow_export_beyond_substation == true
                    # Set the power flowing through the line from the substation to be the grid purchase minus the dvProductionToGrid for node 15
                    #TODO: make this compatible with three phase power- I believe p_fr[1] only refers to the first phase: might be able to say:  p_fr .>= 0   with the period
                    
                    if timestep in PMDTimeSteps_InREoptTimes
                        
                        PMD_time_step = findall(x -> x==timestep, PMDTimeSteps_InREoptTimes)[1] #use the [1] to convert the 1-element vector into an integer

                        p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
                        p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
                        
                        if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                            q_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :q, f_idx)[c] for c in f_connections]
                            q_to = [PowerModelsDistribution.var(pm, PMD_time_step, :q, t_idx)[c] for c in t_connections]
                        end

                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == sum(p_fr[phase] for phase in f_connections))
                    
                    elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD      
                        simple_powerflow_timestep = findall(x -> x==timestep, time_steps_without_PMD)[1]
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == sum(m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, simple_powerflow_timestep] for phase in phases_for_each_line[lowercase(Multinode_Inputs.substation_line)]))
                        
                    else
                        # Instead of using the line flow from PMD or the simple powerflow model, consider the total system inflow/outflow to be based on a lumped-element model, which sums all power inflows and outflows for each node
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] ==
                            (-sum(m[Symbol("TotalExport_"*string(gen_ind_e_to_REopt_node[e]))][timestep] for e in REopt_gen_ind_e) + 
                            sum(m[Symbol("dvGridPurchase_"*string(gen_ind_e_to_REopt_node[e]))][timestep] for e in REopt_gen_ind_e)))
                    end

                    @constraint(m, m[:dvSubstationPowerFlow][timestep] == (sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) - 
                                                                                sum(m[Symbol("dvProductionToGrid_"*p.s.settings.facilitymeter_node)]["PV", u, timestep] for u in p.export_bins_by_tech["PV"]))) 
            
                    @constraint(m, sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) <= Multinode_Inputs.substation_import_limit * m[:binSubstationPositivePowerFlow][timestep])
                    
                    @constraint(m, sum(m[Symbol("dvProductionToGrid_"*p.s.settings.facilitymeter_node)]["PV", u, timestep] for u in p.export_bins_by_tech["PV"]) <= Multinode_Inputs.substation_export_limit * (1 - m[:binSubstationPositivePowerFlow][timestep]))
                    
                    @constraint(m, sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) >= 0)
                    
                    @constraint(m, sum(m[Symbol("dvProductionToGrid_"*p.s.settings.facilitymeter_node)]["PV", u, timestep] for u in p.export_bins_by_tech["PV"]) >= 0)
                                    
                else                  
                    @constraint(m, sum(m[Symbol("dvProductionToGrid_"*p.s.settings.facilitymeter_node)]["PV", u, timestep] for u in p.export_bins_by_tech["PV"]) == 0)

                    if timestep in PMDTimeSteps_InREoptTimes
                        PMD_time_step = findall(x -> x==timestep, PMDTimeSteps_InREoptTimes)[1] #use the [1] to convert the 1-element vector into an integer

                        p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
                        p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
                        
                        if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                            q_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :q, f_idx)[c] for c in f_connections]
                            q_to = [PowerModelsDistribution.var(pm, PMD_time_step, :q, t_idx)[c] for c in t_connections]
                        end

                        @constraint(m, sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) == sum(p_fr[phase] for phase in f_connections))
                        
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == sum(p_fr[phase] for phase in f_connections)) 
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] >= 0) 
                    
                    elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                        simple_powerflow_timestep = findall(x -> x==timestep, time_steps_without_PMD)[1]
                        
                        @constraint(m, sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) == sum(m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, simple_powerflow_timestep] for phase in phases_for_each_line[lowercase(Multinode_Inputs.substation_line)]))
                        
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == m[:dvPline][lowercase(Multinode_Inputs.substation_line), simple_powerflow_timestep])
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] >= 0) 
                        
                    else
                        # Instead of using the line flow from PMD or simple powerflow model, consider the total system inflow/outflow to be based on a lumped-element model, which sums all power inflows and outflows for each node
                        @constraint(m,
                            (sum(m[Symbol("TotalExport_"*string(buses[e]))][timestep] for e in REopt_gen_ind_e)  - 
                            sum(m[Symbol("dvGridPurchase_"*string(buses[e]))][timestep] for e in REopt_gen_ind_e)) == 
                            (sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers)))
                    
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == (sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers))) 
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] >= 0)
                        
                    end
                end
            end
        end
    end
end


function LimitGeneratorOperatingTimes(m, Multinode_Inputs, REoptInputs_Combined)
    # Prevent the generators from generating power during times that aren't a grid outage
    NonOutageTimeSteps = []

    if Multinode_Inputs.model_outages_with_outages_vector == false
        NonOutageTimeSteps = vcat(collect(1:Multinode_Inputs.single_outage_start_time_step), collect(Multinode_Inputs.single_outage_end_time_step:(8760*Multinode_Inputs.time_steps_per_hour)))
    elseif Multinode_Inputs.model_outages_with_outages_vector == true
        for i in 1:(8760*Multinode_Inputs.time_steps_per_hour)
            if !(i in Multinode_Inputs.outages_vector) 
                push!(NonOutageTimeSteps, i)
            end
        end
    end

    for p in REoptInputs_Combined
        _n = "_"*string(p.s.site.node)
        if "Generator" in p.techs.elec
            for ts in NonOutageTimeSteps
			    fix(m[Symbol("dvRatedProduction"*_n)]["Generator", ts], 0.0, force=true)
            end       
        end
    end
end


function CreateLineInfoDictionary(Multinode_Inputs, pm, data_math_mn)
    # Creates a dictionary with the line names and corresponding indeces for the :p decision variable
    LineInfo = Dict([])
    NumberOfBranches = length(PowerModelsDistribution.ref(pm,1,:branch))

    if length(collect(values(data_math_mn["nw"]["1"]["settings"]["vbases_default"]))) != 1
        throw(@error("The length of vbases_default is not 1"))
    end

    vbases_default = collect(values(data_math_mn["nw"]["1"]["settings"]["vbases_default"]))[1]
   
    for i in 1:NumberOfBranches
        LineData = PowerModelsDistribution.ref(pm, 1, :branch, i)
        
        branch_vbase = LineData["vbase"]
        line_voltage = round(Multinode_Inputs.base_voltage_kv * (LineData["vbase"]/vbases_default), digits=3)
        maximum_power = round((LineData["c_rating_a"][1]/branch_vbase) * line_voltage, digits=3)
        
        c_rating_a = LineData["c_rating_a"][1]
        line_name = LineData["name"]
        if Multinode_Inputs.display_information_during_modeling_run
            print("\n For line $(line_name), the data is max power: $(maximum_power), line voltage: $(line_voltage), c_rating_a: $(c_rating_a), branch_vbase: $(branch_vbase)")
        end

        LineInfo[LineData["name"]] = Dict(["index"=>LineData["index"], 
                                           "t_bus"=>LineData["t_bus"], 
                                           "f_bus"=>LineData["f_bus"], 
                                           "c_rating_a"=>LineData["c_rating_a"], 
                                           "vbase"=>LineData["vbase"],
                                           "line_voltage_kv"=>line_voltage,
                                           "maximum_power_kw"=>maximum_power
                                           ])
    end
    return LineInfo
end


function Run_REopt_PMD_Model(pm, Multinode_Inputs, timestamp="")
    # This function runs the optimization
    
    m = pm.model

    set_optimizer(m, Multinode_Inputs.optimizer) 
    
    if string(Multinode_Inputs.optimizer) == "Xpress.Optimizer"
        @info "Setting attributes for the Xpress solver"
        set_optimizer_attribute(m, "MIPRELSTOP", Multinode_Inputs.optimizer_tolerance)
        set_optimizer_attribute(m, "OUTPUTLOG", Multinode_Inputs.log_solver_output_to_console ? 1 : 0)

        # Save the Xpress log into the per-run timestamped folder created by CreateOutputsFolder.
        # Use mkpath (idempotent) so this works even when generate_CSV_of_outputs/generate_results_plots
        # are false (in which case CreateOutputsFolder did not create the folder) and on repeated
        # solves within the same run (e.g. BAU case).
        log_folder = isempty(timestamp) ? Multinode_Inputs.folder_location :
                     joinpath(Multinode_Inputs.folder_location, "results_"*timestamp)
        mkpath(log_folder)
        # Distinguish BAU vs main run logs within the same timestamped folder
        log_filename = isfile(joinpath(log_folder, "xpress_log.txt")) ? "xpress_log_BAU.txt" : "xpress_log.txt"
        xpress_log_path = joinpath(log_folder, log_filename)

        # Xpress.jl does NOT expose "LOGFILE" as a MOI RawOptimizerAttribute, so set_optimizer_attribute
        # will throw MOI.UnsupportedAttribute. The log file has to be set via the Xpress C API on the
        # inner problem handle (Xpress.setlogfile). We force JuMP to instantiate the backend optimizer
        # first (so .inner exists), then call Xpress.setlogfile. If anything goes wrong, fall back
        # quietly to console-only logging.
        log_file_set = false
        try
            JuMP.MOI.Utilities.attach_optimizer(m)
            xpress_opt = JuMP.unsafe_backend(m)
            Xpress = Base.require(Main, :Xpress)
            Xpress.setlogfile(xpress_opt.inner, xpress_log_path)
            log_file_set = true
        catch err
            @warn "Could not configure Xpress LOGFILE via the C API; the log will only appear in the console if log_solver_output_to_console=true. Error: $(err)"
        end
        if log_file_set
            @info "Xpress log will be written to $(xpress_log_path)"
        end
        #print("\n ************************************************ removing the presolve; presolve should be reactivated")
        #set_optimizer_attribute(m, "PRESOLVE", 0)

    elseif string(Multinode_Inputs.optimizer) == "Gurobi.Optimizer"
        @info "Setting attributes for the Gurobi solver"
        set_optimizer_attribute(m, "MIPGap", Multinode_Inputs.optimizer_tolerance)
        set_optimizer_attribute(m, "OutputFlag", Multinode_Inputs.log_solver_output_to_console ? 1 : 0)  
        set_optimizer_attribute(m, "LogToConsole", Multinode_Inputs.log_solver_output_to_console ? 1 : 0)
    elseif string(Multinode_Inputs.optimizer) == "HiGHS.Optimizer"
        @info "Setting attributes for the HiGHS solver"
        set_optimizer_attribute(m, "mip_rel_gap", Multinode_Inputs.optimizer_tolerance)
        set_optimizer_attribute(m, "output_flag", Multinode_Inputs.log_solver_output_to_console)
        set_optimizer_attribute(m, "log_to_console", Multinode_Inputs.log_solver_output_to_console)
    else
        @info "The solver's default tolerance and log settings are being used for the optimization"
    end
    
    print("\n The optimization is starting")
    print("\n     The number of variables in the model is: ")
    print(length(all_variables(pm.model)))
    print("\n")
    # Note: the "optimize_model!" function is a wrapper from PMD and it includes some organization of the results
    results = PowerModelsDistribution.optimize_model!(pm) #  Option other fields: relax_intregrality=true, optimizer=HiGHS.Optimizer) # The default in PMD for relax_integrality is false
    print("\n The optimization is complete\n")
    
    TerminationStatus = string(results["termination_status"])
    if TerminationStatus != "OPTIMAL"
        
        model = pm.model

        solver_name_str = ""
        try
            solver_name_str = lowercase(JuMP.solver_name(model))
        catch
            solver_name_str = lowercase(string(Multinode_Inputs.optimizer))
        end
        iis_supported = occursin("xpress", solver_name_str) || occursin("gurobi", solver_name_str) || occursin("cplex", solver_name_str)

        infeasible_statuses = ("INFEASIBLE", "LOCALLY_INFEASIBLE", "INFEASIBLE_OR_UNBOUNDED")

        if !(TerminationStatus in infeasible_statuses)
            println("Termination status is $(TerminationStatus); skipping IIS computation (IIS is only meaningful for infeasible models).")
        elseif !iis_supported
            println("Skipping IIS computation: the active solver ($(solver_name_str)) does not support MOI.compute_conflict!. Supported solvers include Xpress, Gurobi, and CPLEX.")
        else
            println("Computing IIS via $(solver_name_str) (this may take a while)...")
            conflict_computed = true
            try
                MOI.compute_conflict!(JuMP.backend(model))
            catch err
                println("compute_conflict! failed: ", err)
                conflict_computed = false
            end

            if conflict_computed
                conflict_status = MOI.get(JuMP.backend(model), MOI.ConflictStatus())
                println("Conflict status: ", conflict_status)

                if conflict_status == MOI.CONFLICT_FOUND
                    iis_folder = isempty(timestamp) ? Multinode_Inputs.folder_location :
                                 joinpath(Multinode_Inputs.folder_location, "results_"*timestamp)
                    mkpath(iis_folder)
                    iis_filename = isfile(joinpath(iis_folder, "iis_conflict.txt")) ? "iis_conflict_BAU.txt" : "iis_conflict.txt"
                    iis_path = joinpath(iis_folder, iis_filename)
                    open(iis_path, "w") do io
                        # The typed all_constraints(model, F, S) overload already returns variable-in-set
                        # constraints (e.g. fix(...) or lower/upper bounds) when F is VariableRef, so no
                        # kwarg is needed here. The include_variable_in_set_constraints kwarg only applies
                        # to the untyped all_constraints(model) overload and will throw if passed here.
                        for (F, S) in JuMP.list_of_constraint_types(model)
                            for c in JuMP.all_constraints(model, F, S)
                                st = MOI.get(model, MOI.ConstraintConflictStatus(), c)
                                if st == MOI.IN_CONFLICT
                                    nm = JuMP.name(c)
                                    label = isempty(nm) ? "<unnamed>" : nm
                                    # Also write the constraint object so unnamed constraints remain interpretable
                                    println(io, label, " :: ", c)
                                end
                            end
                        end
                    end
                    println("IIS written to $(iis_path)")
                else
                    println("The solver did not return a conflict set.")
                end
            end
        end
        
        
        @error("The termination status of the optimization was "*string(results["termination_status"])*". Returning the failed model without further processing.")
    end
        
    return results, TerminationStatus;
end


function RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, line, REoptTimeSteps, LineInfo, data_eng; Grid_Outage=false, Off_Grid=false, Switches_Open=false, Prevent_Export=false, Substation_Export_Limit=1E10, Substation_Import_Limit=1E10, OutageSimulator = false, OutageLength_Timesteps = 0)
    # Function used for restricting power flow for grid outages, times when switches are opened, and substation import and export limits
    
    line = lowercase(line)

    # Save the REopt Inputs for the site not to a variable
    FacilityMeterNode_REoptInputs = ""
    for p in REoptInputs_Combined
        if string(p.s.site.node) == p.s.settings.facilitymeter_node
            FacilityMeterNode_REoptInputs = p        
        end
    end

    # Save to a variable the timesteps that the power models distribution model is applied to
    if OutageSimulator == false
        PMDTimeSteps_InREoptTimes = Multinode_Inputs.PMD_time_steps
        PMDTimeSteps_Indeces = collect(1:length(PMDTimeSteps_InREoptTimes))
    elseif OutageSimulator == true
        PMDTimeSteps_InREoptTimes = collect(1:OutageLength_Timesteps)
        PMDTimeSteps_Indeces = collect(1:OutageLength_Timesteps)
    end

    if Multinode_Inputs.display_information_during_modeling_run
        open(Multinode_Inputs.folder_location*"/LineInfo.txt","w") do input
            for (key, val) in LineInfo
                println(input, "$key => $val" ) 
            end
        end
    end

    i = LineInfo[line]["index"]
        # Based off of code in line 470 of PMD's src>core>constraint_template
        timestep = 1 # collect the network configuration information from timestep 1, which assumes that the network is not changing (fair to assume with the REopt integration)
        branch = PowerModelsDistribution.ref(pm, timestep, :branch, i)
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        f_connections = branch["f_connections"]
        t_connections = branch["t_connections"]
        f_idx = (i, f_bus, t_bus)
        t_idx = (i, t_bus, f_bus)

    phases_for_each_line = create_dictionary_of_phases_for_each_line(data_eng) 
    
    if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD    
        time_steps_without_PMD = setdiff(REoptTimeSteps, Multinode_Inputs.PMD_time_steps)
    else
        time_steps_without_PMD = 0
    end

    for timestep in REoptTimeSteps
            
        if timestep in PMDTimeSteps_InREoptTimes
            # Based off of code in line 274 of PMD's src>core>constraints
            PMD_time_step = findall(x -> x==timestep, PMDTimeSteps_InREoptTimes)[1] #use the [1] to convert the 1-element vector into an integer
            
            p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
            p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
            
            if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                q_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :q, f_idx)[c] for c in f_connections]
                q_to = [PowerModelsDistribution.var(pm, PMD_time_step, :q, t_idx)[c] for c in t_connections]
            end
        elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
            # redefine the timestep variable to be correlated with the timestep variable in the simple powerflow model
            timestep_for_simple_powerflow_model = findall(x -> x==timestep, time_steps_without_PMD)[1]
        end

        if Prevent_Export == true
            # If the timesteps are part of the PMD model, then apply the constraints to the lines in PMD
            if timestep in PMDTimeSteps_InREoptTimes
                JuMP.@constraint(m, [phase in f_connections], p_fr[phase] .>= 0)
                JuMP.@constraint(m, [phase in f_connections], q_fr[phase] .>= -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar) # no restrictions on reactive power
            elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                for phase in phases_for_each_line[line]
                    @constraint(m, m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, timestep_for_simple_powerflow_model] .>= 0)
                end
            else
                @constraint(m, sum(m[Symbol("dvProductionToGrid_"*Multinode_Inputs.facilitymeter_node)]["PV", u, timestep] for u in FacilityMeterNode_REoptInputs.export_bins_by_tech["PV"]) == 0)
            end
        end

        if Substation_Export_Limit != ""
            if timestep in PMDTimeSteps_InREoptTimes
                JuMP.@constraint(m, [phase in f_connections], p_fr[phase] .>= -Substation_Export_Limit) 
                if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                    JuMP.@constraint(m, [phase in f_connections], q_fr[phase] .>= -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar)
                end
            elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                for phase in phases_for_each_line[line]
                    @constraint(m, m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, timestep_for_simple_powerflow_model] .>= (1/length(phases_for_each_line[line])) * -Substation_Export_Limit) # Assume that the maximum export limit is evenly divided by each of the phases
                end
            else
                @constraint(m, sum(m[Symbol("dvProductionToGrid_"*Multinode_Inputs.facilitymeter_node)]["PV", u, timestep] for u in FacilityMeterNode_REoptInputs.export_bins_by_tech["PV"]) <= Substation_Export_Limit)
            end
        end

        if Substation_Import_Limit != ""
            if timestep in PMDTimeSteps_InREoptTimes
                JuMP.@constraint(m, [phase in f_connections], p_fr[phase] .<= Substation_Import_Limit)
                if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                    JuMP.@constraint(m, [phase in f_connections], q_fr[phase] .<= Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar)
                end
            elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                for phase in phases_for_each_line[line]
                    @constraint(m, sum(m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, timestep_for_simple_powerflow_model]) .<= (1/length(phases_for_each_line[line])) * Substation_Import_Limit) # Assume that the maximum import limit is evenly divided by each of the phases
                end
            else
                @constraint(m, sum(m[Symbol("dvGridPurchase_"*Multinode_Inputs.facilitymeter_node)][timestep, tier] for tier in 1:FacilityMeterNode_REoptInputs.s.electric_tariff.n_energy_tiers) <= Substation_Import_Limit)
            end
        end

        if Off_Grid == true || Grid_Outage == true || Switches_Open==true
            # Restrict all power flow
            if timestep in PMDTimeSteps_InREoptTimes
                JuMP.@constraint(m, [phase in f_connections], p_fr[phase] .== 0)  # The _fr and _to variables are just indicating power flow in either direction on the line. In PMD, there is a constraint that requires  p_to = -p_fr 
                JuMP.@constraint(m, [phase in t_connections], p_to[phase] .== 0)  # TODO test removing the "fr" constraints here in order to reduce the # of constraints in the model
                if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                    if Multinode_Inputs.number_of_phases == 1                
                        JuMP.@constraint(m, [phase in f_connections], q_fr[phase] .== 0.0)
                        JuMP.@constraint(m, [phase in t_connections], q_to[phase] .== 0.0)
                    else
                        # Add small amount of reactive power support for multi-phase systems
                        JuMP.@constraint(m, [phase in f_connections], -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar .<= q_fr[phase] .<= Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar) 
                        JuMP.@constraint(m, [phase in t_connections], -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar .<= q_to[phase] .<= Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar) # no restrictions on reactive power
                    end
                end
            elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                for phase in phases_for_each_line[line]
                    @constraint(m, m[:dvPline][line, phase, timestep_for_simple_powerflow_model] .== 0)
                end               
            elseif Switches_Open==false
                @constraint(m, sum(m[Symbol("dvGridPurchase_"*Multinode_Inputs.facilitymeter_node)][timestep, tier] for tier in 1:FacilityMeterNode_REoptInputs.s.electric_tariff.n_energy_tiers) == 0)
                @constraint(m, sum(m[Symbol("dvProductionToGrid_"*Multinode_Inputs.facilitymeter_node)]["PV", u, timestep] for u in FacilityMeterNode_REoptInputs.export_bins_by_tech["PV"]) == 0)
            else Switches_Open==true # Note: the first elseif statement covers the situation where switches_open == true and the simple powerflow model is being used
                @warn "The switches were defined as open during a time period when the PMD model and simple powerflow model are not applied"
            end
        end
    end
end


function GenerateREoptNodesList(Multinode_Inputs)
    REopt_nodes = []
    for i in Multinode_Inputs.REopt_inputs_list
        if string(i["Site"]["node"]) != Multinode_Inputs.facilitymeter_node
            push!(REopt_nodes, i["Site"]["node"])
        end
    end
    return REopt_nodes
end


# Function to check for errors in the data inputs for the model
function RunDataChecks(Multinode_Inputs,  REopt_dictionary)

    ps = REopt_dictionary

    for p in ps
        node_temp = p.s.site.node

        for phase in p.s.settings.phase_numbers
            if !(phase in [1,2,3])
                throw(@error("Phase $(phase) for node $(node_temp) is invalid"))
            end
            if length(findall(x -> x==phase, p.s.settings.phase_numbers)) > 1
                throw(@error("Phase $(phase) can't be listed more than once for node $(node_temp)"))
            end
        end

        if p.s.settings.facilitymeter_node != Multinode_Inputs.facilitymeter_node
            throw(@error("The facilitymeter_node input for each REopt node must equal the facilitymeter_node defined in the multinode settings, which is $(Multinode_Inputs.facilitymeter_node)"))
        end

        if p.s.settings.time_steps_per_hour != Multinode_Inputs.time_steps_per_hour
            throw(@error("The time steps per hour for each REopt node must match the time steps per hour defined in the multinode settings dictionary"))
        end

        possible_critical_load_method_entries = ["Fraction", "TimeSeries", "N/A"]
        if !(Multinode_Inputs.critical_load_method in possible_critical_load_method_entries)
            throw(@error("The input for critical_load_method is not valid"))
        end

        # Checking that critical loads are defined, if running a resilience model and/or the outage simulator
        if Multinode_Inputs.run_outage_simulator || Multinode_Inputs.model_outages_with_outages_vector || Multinode_Inputs.model_outages_with_outages_vector || ((Multinode_Inputs.single_outage_end_time_step - Multinode_Inputs.single_outage_start_time_step) > 0 )

            if Multinode_Inputs.critical_load_method == "Fraction"
                if string(p.s.site.node) ∉ keys(Multinode_Inputs.critical_load_fraction)
                    if sum(p.s.electric_load.loads_kw) > 0
                        throw(@error("The REopt node $(node_temp) does not have an assigned critical load fraction in the critical_load_fraction input dictionary"))
                    end
                end
            end

            if Multinode_Inputs.critical_load_method == "TimeSeries"
                if string(p.s.site.node) ∉ keys(Multinode_Inputs.critical_load_timeseries)
                    if sum(p.s.electric_load.loads_kw) > 0
                        throw(@error("The REopt node $(node_temp) does not have an assigned critical load timeseries profile in the critical_load_timeseries input dictionary"))
                    end
                end
            end

        end
        # TODO: add data check to ensure that if a critical load method is defined, then there must be either a critical load fraction or a critical load timeseries dictionary   
        
        if Int(length(p.s.electric_load.loads_kw)) != Int(8760 * Multinode_Inputs.time_steps_per_hour)
            throw(@error("At REopt node $(node_temp), the length of the electric loads vector does not correlate with the time steps per hour defined in the Multinode_Inputs dictionary"))
        end
    end
    
    if Multinode_Inputs.base_voltage_kv <= 0
        throw(@error("the base_voltage_kv must be greater than zero. The default value of the base_voltage_kv is zero to ensure that the user defines the correct base voltage. The base voltage entered for base_voltage_kv should be the base voltage defined at the top of the .dss inputs file."))
    end

    if Multinode_Inputs.number_of_phases ∉ [1,2,3]
        throw(@error("The number_of_phases input must be 1, 2, or 3"))
    end

    if Multinode_Inputs.multinode_type ∉ ["CommunityDistrict", "BehindTheMeter", "OffGrid"]
        throw(@error("An invalid multinode type was provided in the inputs"))
    end

    if (Multinode_Inputs.multinode_type == "Offgrid") && (Multinode_Inputs.run_BAU_case == true)
        throw(@error("The BAU case cannot be run for an off-grid model because an off-grid model cannot solve without on-site generation."))
    end
    
    if Multinode_Inputs.multinode_type != "CommunityDistrict"
        @warn("For the community district multinode type, the electricity tariff for the facility meter node should be 0")
    end

    if Multinode_Inputs.critical_load_method == "Fraction"
        for x in values(Multinode_Inputs.critical_load_fraction)
            if x >= 5.0
                throw(@error("The critical_load_fraction load fraction should be entered as a fraction, not a percent. The model currently limits the critical_load_fraction to 5.0 (or 500%) to reduce the possibility of user error. "))
            end
        end
    end

    if Multinode_Inputs.single_outage_start_time_step > Multinode_Inputs.single_outage_end_time_step
        throw(@error("In the Multinode_Inputs dictionary, the single outage start time must be a smaller value than the single outage stop time"))
    end

    if Multinode_Inputs.single_outage_end_time_step > (8760 * Multinode_Inputs.time_steps_per_hour)
        TotalNumberOfTimeSteps = Int(8760 * Multinode_Inputs.time_steps_per_hour)
        throw(@error("In the Multinode_Inputs dictionary, the defined outage stop time must be less than the total number of time steps, which is $(TotalNumberOfTimeSteps)"))
    end
    
    #if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD  &&  (Multinode_Inputs.number_of_phases > 1)
        #throw(@error("The simple powerflow model is currently not compatible with multiphase systems. Please set apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD to false to run the model only with PowerModelsDistribution."))
    #end

    if Multinode_Inputs.substation_export_limit < 0
        throw(@error("The substation_export_limit input cannot be negative."))
    end

    if Multinode_Inputs.substation_import_limit < 0
        throw(@error("The substation_import_limit input cannot be negative."))
    end

    if (Multinode_Inputs.allow_dropped_load) && (Multinode_Inputs.number_of_phases != 1)
        throw(@error("When modeling a three-phase system, allowing dropped load in the outage simulator is not allowed. Please set the allowed_dropped_load input to false."))
    end

    # Currently the simple powerflow model does not work with outages and multiphase systems, so an error is caused if the user runs a multi-phase model where the outages do not occur during PMD timesteps
    if Multinode_Inputs.number_of_phases != 1
        if Multinode_Inputs.single_outage_end_time_step - Multinode_Inputs.single_outage_start_time_step > 0
            for timestep in collect(Multinode_Inputs.single_outage_start_time_step:Multinode_Inputs.single_outage_end_time_step)
                if !(timestep in Multinode_Inputs.PMD_time_steps)
                    throw(@error("For multi-phase systems, the outages in the optimization must be modeled during timesteps that are modeled using PMD"))
                end
            end
        end 
        if Multinode_Inputs.model_outages_with_outages_vector == true
            for timestep in Multinode_Inputs.outages_vector
                if !(timestep in Multinode_Inputs.PMD_time_steps)
                    throw(@error("For multi-phase systems, all outages must be modeled during times steps modeled with PowerModelsDistribution (PMD)."))
                end
            end
        end
    end

    # Check for internal loops
    data_eng = PowerModelsDistribution.parse_file(Multinode_Inputs.PMD_network_input, transformations=[PowerModelsDistribution.remove_all_bounds!])
    has_loops, loop_edges = REopt.detect_network_loops(data_eng)
    has_islands, islanded_buses, island_groups = REopt.detect_islanded_buses(data_eng, Multinode_Inputs.substation_node)

    if has_loops
        @warn("The distribution system has the following loops: $(loop_edges)")
    end
    if has_islands
        @warn("The following islands are present in the distribution system: $(island_groups)")
    end

end


# Function to check for commons issues in the model if the model fails to optimize
function run_diagnostics(model, Multinode_Inputs,  REopt_dictionary)

    diagnostic_report = Dict([])

    # Evaluation 1: Check for single variable contradictions
    # AI was used to generate the evaluation 1 code
    bad = []
    for v in all_variables(model)
        lb = has_lower_bound(v) ? lower_bound(v) : -Inf
        ub = has_upper_bound(v) ? upper_bound(v) :  Inf
        fx = is_fixed(v) ? fix_value(v) : nothing
        if lb > ub + 1e-9
            push!(bad, (v, lb, ub, fx, :lb_gt_ub))
        elseif fx !== nothing && (fx < lb - 1e-9 || fx > ub + 1e-9)
            push!(bad, (v, lb, ub, fx, :fix_outside_bounds))
        end
    end
    length(bad), first(bad, 20)

    diagnostic_report["single_variable_contradictions"] = bad
    
    return diagnostic_report
end
