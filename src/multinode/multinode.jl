# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function Multinode_Model(Multinode_Settings::Dict{String, Any})
    # The main function to run all parts of the multinode model

    StartTime_EntireModel = now() # Record the start time for the computation
    TimeStamp = Dates.format(now(), "mm-dd-yyyy")*"_"*Dates.format(now(), "HH-MM")
    time_results = Dict()

    Multinode_Settings_for_BAU = deepcopy(Multinode_Settings)
    Multinode_Settings = deepcopy(Multinode_Settings)
   
    Multinode_Inputs = REopt.MultinodeInputs(; REopt.dictkeys_tosymbols(Multinode_Settings)...)

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
            Multinode_Settings_No_Techs = SetTechSizesForBAU(Multinode_Settings_for_BAU)
            Multinode_Inputs_No_Techs = REopt.MultinodeInputs(; REopt.dictkeys_tosymbols(Multinode_Settings_No_Techs)...)
            PrepareElectricLoads(Multinode_Inputs_No_Techs)
            REopt_inputs_combined_No_Techs = PrepareREoptInputs(Multinode_Inputs_No_Techs, Dict()) # The REopt inputs for the BAU case are generated from the inputs without the technologies
            
            Outage_Results_No_Techs = Dict(["NoOutagesTested" => Dict(["Not evaluated" => "Not evaluated"])])
            
            REopt_Results_BAU, PMD_Results_No_Techs, DataFrame_PMD_LineFlow_Summary_No_Techs, 
                PMD_Dictionary_LineFlow_Power_Series_No_Techs, DataDictionaryForEachNode_No_Techs, 
                LineInfo_PMD_No_Techs, REoptInputs_Combined_No_Techs, data_eng_No_Techs, 
                data_math_mn_No_Techs, pm_No_Techs, line_upgrade_options_each_line_NoTechs, 
                line_upgrade_results_NoTechs, load_phase_dictionary_NoTechs, gen_ind_e_to_REopt_node_noTechs, 
                REopt_gen_ind_e_noTechs, connections_noTechs, connections_upstream_noTechs, 
                connections_downstream_noTechs = build_run_and_process_results(Multinode_Inputs_No_Techs, REopt_inputs_combined_No_Techs, PMD_number_of_timesteps, TimeStamp, time_results; allow_upgrades=false, BAU_case=true)
            
            GC.gc()

            model_BAU = pm_No_Techs.model # The BAU model is used for the solve time and is returned with the results

            if REopt_Results_BAU == "N/A"
                @warn "The BAU case did not solve to optimality, so the net present value will not be calculated."
                system_results_BAU = "none"
            else
                ComputationTime_EntireModel = "N/A"
                system_results_BAU, _ = REopt.Results_Compilation(pm_No_Techs.model, REopt_Results_BAU, PMD_Results_No_Techs, Outage_Results_No_Techs, Multinode_Inputs_No_Techs, DataFrame_PMD_LineFlow_Summary_No_Techs, PMD_Dictionary_LineFlow_Power_Series_No_Techs, TimeStamp, ComputationTime_EntireModel; system_results_BAU = "", data_eng = data_eng_No_Techs)
                time_results["Step $(length(keys(time_results))+1): BAU_model_solve_time_minutes"] = round(JuMP.solve_time(model_BAU)/60, digits = 2)
            end
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
        system_results, DataFrames_of_Results = REopt.Results_Compilation(pm.model, REopt_Results, PMD_Results, Outage_Results, Multinode_Inputs, DataFrame_PMD_LineFlow_Summary, PMD_Dictionary_LineFlow_Power_Series, TimeStamp, StartTime_EntireModel; bau_model = model_BAU, system_results_BAU = system_results_BAU, outage_simulator_time = outage_simulator_time_minutes, all_line_powerflow_results = all_line_powerflow_results, simple_powerflow_model_results=simple_powerflow_model_results, data_eng = data_eng)
        if line_upgrade_results isa DataFrame
            DataFrames_of_Results["Results_Line_Upgrade_Summary"] = line_upgrade_results
        end

        ComputationTime_EntireModel_Milliseconds, ComputationTime_EntireModel_Minutes = CalculateComputationTime(StartTime_EntireModel)
        time_results["ComputationTime_EntireModel_Minutes"] = ComputationTime_EntireModel_Minutes
        
        # Compile output data into a dictionary to return from the dictionary
        CompiledResults = Dict([("System_Results", system_results),
                                ("System_Results_BAU", system_results_BAU),
                                ("DataFrames_of_Results", DataFrames_of_Results), # The dataframes of results (can be saved as csv files by the user in their analysis script)
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
    else
        throw(@error("The model_type input, $(Multinode_Inputs.model_type), is not valid. The only option currently available is \"PowerModelsDistribution\"."))
    end
       
    return CompiledResults, pm.model, model_BAU, data_dictionary_for_plots
end


function PrepareElectricLoads(Multinode_Inputs)
    # Prepare the electric loads
    REopt_inputs_all_nodes = Multinode_Inputs.REopt_inputs_list

    # Prepare loads for using with the outage simulator, if the fraction method is used for determining the critical load
    if  Multinode_Inputs.critical_load_method == "Fraction"
        load_profiles_for_outage_sim_if_using_the_fraction_method = Dict([])
        for REopt_inputs in REopt_inputs_all_nodes
            load_profiles_for_outage_sim_if_using_the_fraction_method[string(REopt_inputs["Site"]["node"])] = deepcopy( REopt_inputs["ElectricLoad"]["loads_kw"] ) # The outage simulator looks up the nodes as strings
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

                    # Check that the critical load inputs for the node are defined
                    if Multinode_Inputs.critical_load_method == "Fraction"
                        if !(string(node) in keys(Multinode_Inputs.critical_load_fraction))
                            throw(@error("Node $(node) is not listed in the critical_load_fraction dictionary"))
                        end
                    elseif Multinode_Inputs.critical_load_method == "TimeSeries"
                        if !(string(node) in keys(Multinode_Inputs.critical_load_timeseries))
                            throw(@error("Node $(node) is not listed in the critical_load_timeseries dictionary"))
                        end
                    elseif Multinode_Inputs.critical_load_method != "N/A" # With "N/A", the loads are not changed during the outages
                        throw(@error("Invalid method for generating a critical load was provided"))
                    end
                    
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
        
        OutageStart = Int(Multinode_Inputs.single_outage_start_time_step)
        OutageEnd = Int(Multinode_Inputs.single_outage_end_time_step)

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
                    if !(string(node) in keys(Multinode_Inputs.critical_load_timeseries))
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
    # Create a list lines that are upgradable (a line is upgradable if it is listed in the locations of any of the upgrade options)

    lines_for_upgrades = []
    for i in keys(Multinode_Inputs.line_upgrade_options)
        append!(lines_for_upgrades, Multinode_Inputs.line_upgrade_options[i]["locations"]) 
    end
    lines_for_upgrades = unique(lines_for_upgrades)

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
                                                                    ("cost_per_length", [Multinode_Inputs.line_upgrade_options[i]["cost_per_meter"]])
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
        line_to_neutral_voltage_kv = LineInfo[line]["line_to_neutral_voltage_kv"] # From the PMD model, so the user does not need to enter a voltage
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

        for PMD_time_step in 1:length(Multinode_Inputs.PMD_time_steps)
            p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
            p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
            
            # The vectors are indexed by position, and the power flow on every phase of the line is limited. The limit for each phase is the current rating multiplied by the line-to-neutral voltage from the PMD model
            for k in eachindex(p_fr)
                @constraint(pm.model, p_fr[k] <= pm.model[:line_max_amps][line] * line_to_neutral_voltage_kv)
                @constraint(pm.model, p_fr[k] >= -pm.model[:line_max_amps][line] * line_to_neutral_voltage_kv)
            end

            for k in eachindex(p_to)
                @constraint(pm.model, p_to[k] <= pm.model[:line_max_amps][line] * line_to_neutral_voltage_kv) 
                @constraint(pm.model, p_to[k] >= -pm.model[:line_max_amps][line] * line_to_neutral_voltage_kv) 
            end
        end
    end
    
    return pm, line_upgrade_options_each_line
end


function model_transformer_upgrades(pm, Multinode_Inputs)
    # TODO: add this capability

    return pm
end


function SetElectricStorageMinimumSOCFractionForEachNode(Multinode_Inputs)
    # This function was generated with the assistance of AI
    # The minimum battery state of charge is applied through battery_min_soc_fraction_during_non_outage_times and 
    # battery_min_soc_fraction_during_grid_outage_times. REopt's soc_min_fraction input applies to every time step (including grid outages), 
    # so it would override a lower grid outage minimum. Therefore, it is set to 0 unless the user provides a value.
    for i in 1:length(Multinode_Inputs.REopt_inputs_list)
        if "ElectricStorage" in keys(Multinode_Inputs.REopt_inputs_list[i])
            electric_storage_inputs = Multinode_Inputs.REopt_inputs_list[i]["ElectricStorage"]
            if !("soc_min_fraction" in keys(electric_storage_inputs))
                electric_storage_inputs["soc_min_fraction"] = 0.0
            elseif electric_storage_inputs["soc_min_fraction"] != 0.0
                @warn "The ElectricStorage soc_min_fraction for the REopt inputs at position $(i) of REopt_inputs_list is $(electric_storage_inputs["soc_min_fraction"]), which is nonzero. This minimum state of charge applies to all time steps, including grid outages, so it takes precedence over battery_min_soc_fraction_during_grid_outage_times and battery_min_soc_fraction_during_non_outage_times when it is larger. Consider setting soc_min_fraction to 0 and using the multinode battery_min_soc_fraction inputs instead."
            end
        end
    end
end


function PrepareREoptInputs(Multinode_Inputs, time_results)  
    # Generate the scenarios, REoptInputs, and list of REoptInputs

    SetElectricStorageMinimumSOCFractionForEachNode(Multinode_Inputs)
       
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


function LimitTechSizeToExisting!(tech_inputs)
    # Note this function was generated with the assistance of AI.
    existing_kw = get(tech_inputs, "existing_kw", 0.0)
    tech_inputs["min_kw"] = existing_kw
    tech_inputs["max_kw"] = existing_kw
    return tech_inputs
end


function SetTechSizesForBAU(Multinode_Settings)
    # PV and Generator are limited to their existing_kw (and are only included if existing_kw > 0) and ElectricStorage is removed.
    
    Multinode_Settings_No_Techs = deepcopy(Multinode_Settings)
    facilitymeter_node = string(Multinode_Settings["facilitymeter_node"])

    for node_inputs in Multinode_Settings_No_Techs["REopt_inputs_list"]
        is_facilitymeter_node = string(node_inputs["Site"]["node"]) == facilitymeter_node

        if haskey(node_inputs, "PV")
            # Note this if statement was generated with the assistance of AI.
            pv_inputs_is_list = node_inputs["PV"] isa AbstractVector
            pvs = pv_inputs_is_list ? node_inputs["PV"] : [node_inputs["PV"]]
            # The facility meter node always keeps its PV because the export through the facility meter is modeled using the PV export variables
            bau_pvs = [LimitTechSizeToExisting!(pv) for pv in pvs if is_facilitymeter_node || get(pv, "existing_kw", 0.0) > 0]
            if isempty(bau_pvs)
                delete!(node_inputs, "PV")
            else
                node_inputs["PV"] = pv_inputs_is_list ? bau_pvs : only(bau_pvs)
            end
        end

        if haskey(node_inputs, "ElectricStorage")
            delete!(node_inputs, "ElectricStorage")
        end

        if haskey(node_inputs, "Generator")
            # Note this if statement was generated with the assistance of AI.
            if get(node_inputs["Generator"], "existing_kw", 0.0) > 0
                LimitTechSizeToExisting!(node_inputs["Generator"])
            else
                delete!(node_inputs, "Generator")
            end
        end
    end
    
    Multinode_Settings_No_Techs["single_outage_start_time_step"] = 5
    Multinode_Settings_No_Techs["single_outage_end_time_step"] = 5 # set to same time as outage start time step so a single outage is not modeled
    Multinode_Settings_No_Techs["model_outages_with_outages_vector"] = false
    Multinode_Settings_No_Techs["outages_vector"] = []
    Multinode_Settings_No_Techs["run_outage_simulator"] = false
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


function CheckThatPMDLoadExists(data_eng, load_name, node)
    # This function was generated with the assistance of AI.
    # Each REopt node needs a load with the expected name in the PMD network
    if !haskey(data_eng["load"], load_name)
        throw(@error("The load \"$(load_name)\" for REopt node $(node) is not in the PMD network. The loads in the network are: $(sort(collect(keys(data_eng["load"]))))"))
    end
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
            CheckThatPMDLoadExists(data_eng, "load$(i)", i)
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
                    if Multinode_Inputs.display_information_during_modeling_run
                        print("\n Adding PMD load empty time series to REopt node $(node), phase $(phase)")
                    end
                    CheckThatPMDLoadExists(data_eng, "load$(node)_phase$(phase)", node)
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
        throw(@error("The number_of_phases, $(Multinode_Inputs.number_of_phases), is invalid"))
    end
end


function RemoveCurrentLimitsFromUpgradableLines!(data_eng, Multinode_Inputs)
    # Note: This function was generated with the assistance of AI.
    # The current limit (cm_ub) of the lines that can be upgraded is removed so that the original rating does not cap the power flow after an upgrade. 
    # The limit with the upgrade is applied through the line upgrade constraints.
    for line in create_list_of_upgradable_lines(Multinode_Inputs)
        if !haskey(get(data_eng, "line", Dict()), line)
            continue # The line name is checked in RunDataChecks
        end
        line_data = data_eng["line"][line]
        # The linecode is applied to the line first, and then removed from it, because PMD would otherwise copy the cm_ub from the linecode back to the line when creating the math model
        PowerModelsDistribution._apply_linecode!(line_data, data_eng)
        delete!(line_data, "linecode")
        delete!(line_data, "cm_ub")
    end
end


function Create_PMD_Model_For_REopt_Integration(Multinode_Inputs, PMD_number_of_timesteps, time_results; combined_REopt_inputs = "", outage_simulator = false, BAU_case = false)
    
    if typeof(Multinode_Inputs.PMD_network_input) == String 
        print("\n Parsing the network input file \n")
        data_eng = PowerModelsDistribution.parse_file(Multinode_Inputs.PMD_network_input) #, transformations=[PowerModelsDistribution.remove_all_bounds!])
        @info "Completed parsing the .dss file"
    elseif Multinode_Inputs.PMD_network_input isa AbstractDict
        print("\n Saving the already-parsed PMD network input as a variable")
        data_eng = deepcopy(Multinode_Inputs.PMD_network_input) # A copy is used because the data_eng dictionary is modified below, and this function is called multiple times (such as for each outage simulation)
        print("\n Completed saving the PMD network input as a variable")
    else
        throw(@error("The PMD_network_input input format is not valid"))
    end 

    PowerModelsDistribution.remove_all_bounds!(data_eng; exclude = ["cm_ub","sm_ub","energy_ub"]) # Note: voltage bounds are manually applied later
    RemoveCurrentLimitsFromUpgradableLines!(data_eng, Multinode_Inputs)

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


function TotalGridPurchaseAtNode(m, node, time_step)
    # This function was generated with the assistance of AI.
    # The total power purchased from the grid at a REopt node in a time step. The facility meter node is indexed by energy tier (and the total is the sum over the tiers), 
    # and the other nodes are not indexed by energy tier because tiered energy rates are only supported at the facility meter node
    grid_purchase = m[Symbol("dvGridPurchase_"*string(node))]
    if ndims(grid_purchase) == 1
        return grid_purchase[time_step]
    else
        return sum(grid_purchase[time_step, tier] for tier in axes(grid_purchase, 2))
    end
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
                + sum(m[Symbol("dvStorageToGrid"*_n)][b,u,ts] for b in p.s.storage.types.elec, u in p.export_bins_by_storage[b]; init=0.0) # This line includes battery export in the total export
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

    
function LinkREoptAndPMD(pm, m, data_math_mn, Multinode_Inputs, REopt_nodes, REopt_inputs_combined; gen_name2ind=nothing, load_phase_dictionary=nothing, gen_ind_e_to_REopt_node=nothing)
    # Link the PMD and REopt variables through constraints
    
    if gen_name2ind === nothing || load_phase_dictionary === nothing || gen_ind_e_to_REopt_node === nothing
        gen_name2ind, load_phase_dictionary, gen_ind_e_to_REopt_node = generate_PMD_information(Multinode_Inputs, REopt_nodes, REopt_inputs_combined, data_math_mn)
    end
    
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
        
        if Multinode_Inputs.display_information_during_modeling_run
            print("\n Gen name to index: ")
            print(gen_name2ind)
        end

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
                            PowerModelsDistribution.var(pm, k, :pg, e).data[1] .== round((1/number_of_phases_at_load), digits = 6) * (m[Symbol("TotalExport_"*string(gen_ind_e_to_REopt_node[e]))][PMDTimeSteps_InREoptTimes[k]] - TotalGridPurchaseAtNode(m, gen_ind_e_to_REopt_node[e], PMDTimeSteps_InREoptTimes[k]))   # negative power "generation" is a load
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

    transformers = collect(keys(get(data_eng, "transformer", Dict()))) # The network might not have any transformers
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

        # Remove the 4 connection (the neutral I think) for the purposes of this simple powerflow equation. Note: filter (not filter!) is used so that the transformer connections in data_eng are not modified
        transformer_phases = filter(x -> x != 4, data_eng["transformer"][transformer_name]["connections"][1])

        # Add the phases for the transformer line to dictionary:
        if !(transformer_line in collect(keys(phases_for_each_line)))  # use this conditional to avoid adding multiple lines for the same connection between two nodes (could occur if there are single phase transformers or voltage regulators connecting each of of two adjacent three-phase busses)
            phases_for_each_line[transformer_line] = transformer_phases
        else
            # Add the phase to the existing line between the two busses (which is from another transformer or voltage regulator, likely a single phase transformer connecting the same two busses)
            phases_for_each_line[transformer_line] = unique(vcat(phases_for_each_line[transformer_line], transformer_phases))
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

    #Start of code segment created by AI
    # --- Repair phantom-edge orientation -------------------------------------
    # The phase-agnostic BFS in DeterminePathToSourcebus can classify some real
    # tree edges as non-tree (because the union graph over all phases has
    # shortcuts that don't exist on any individual phase). Such lines end up in
    # both endpoints' downstream lists and zero upstream lists, which makes
    # their dvPline a free degree of freedom and breaks power balance on
    # simple-PF timesteps. Re-orient each such line so it appears in exactly
    # one bus's upstream list and one bus's downstream list (closer-to-source
    # bus becomes the "from" end).
    for ln in all_lines_including_transformers_converted_to_lines
        in_up = [b for (b, lns) in connections_upstream_lines   if ln in lns]
        in_dn = [b for (b, lns) in connections_downstream_lines if ln in lns]
        if length(in_up) == 0 && length(in_dn) == 2
            bus_a, bus_b = in_dn
            d_a = get(summed_lengths_to_sourcebus_dict, bus_a, Inf)
            d_b = get(summed_lengths_to_sourcebus_dict, bus_b, Inf)
            from_bus, to_bus = d_a <= d_b ? (bus_a, bus_b) : (bus_b, bus_a)
            filter!(x -> x != ln, connections_downstream_lines[to_bus])
            push!(get!(connections_upstream_lines, to_bus, []), ln)
            @info "Phantom-edge repair: line $ln re-oriented as $from_bus -> $to_bus"
        end
    end
    # --------------------------------------------------------------------------
    # End of code segment created by AI

    all_connections_lines_to_busses = merge(connections_downstream_lines, connections_upstream_lines) do a, b
                                            vcat(a, b)
                                        end

    return all_connections_lines_to_busses, 
           connections_upstream_lines, 
           connections_downstream_lines, 
           lines, 
           transformer_busses, 
           line_names_to_sourcebus_dict_including_transformers, 
           phases_for_each_line_and_transformer_line,
           paths,
           neighbors,
           connections_upstream_busses,
           connections_downstream_busses,
           bus_pair_to_line_conversion
end


function create_dictionary_of_phases_for_each_line(data_eng)
    data = Dict([])

    for line in keys(data_eng["line"])
        data[line] = filter(x -> x != 4, data_eng["line"][line]["t_connections"]) # remove the 4 (the neutral) to get the phase numbers, as is done for the busses and transformers. A new array is created so that data_eng is not modified
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


function BusNameMismatchMessage(node, bus_names)
    # This function was generated with the assistance of AI.
    # Generates an error message for a REopt node that is not a bus in the PMD network. Bus names are case sensitive, and are converted to lowercase when a .dss file is parsed
    case_insensitive_matches = filter(bus -> lowercase(bus) == lowercase(string(node)), string.(bus_names))
    message = "The REopt node $(node) is not a bus in the PMD network."
    if !isempty(case_insensitive_matches)
        message *= " A bus named $(case_insensitive_matches) was found, so the node needs to be entered with the same capitalization as the bus name. Note that bus names are converted to lowercase when a .dss file is parsed."
    else
        message *= " The busses in the PMD network are: $(sort(string.(bus_names)))"
    end
    return message
end


function CheckThatREoptNodesAreBusses(Multinode_Inputs, data_eng)
    # This function was generated with the assistance of AI.
    # Check that each REopt node (the facility meter node is not included) is a bus in the PMD network, with the same name
    bus_names = string.(collect(keys(data_eng["bus"])))
    for node in GenerateREoptNodesList(Multinode_Inputs)
        if !(string(node) in bus_names)
            throw(@error(BusNameMismatchMessage(node, bus_names)))
        end
    end
end


function BusPhasesForREoptNode(phases_for_each_bus, node)
    # This function was generated with the assistance of AI.
    # The phases of the bus that is associated with a REopt node
    if !haskey(phases_for_each_bus, string(node))
        throw(@error(BusNameMismatchMessage(node, collect(keys(phases_for_each_bus)))))
    end
    return phases_for_each_bus[string(node)]
end


function TransformerRatingPerPhaseKw(transformer)
    # Note: this function was generated by AI
    # The nominal power rating (sm_nom, in kVA) of the first winding of the transformer, divided evenly across the phases of the transformer (the neutral, terminal 4, is not a phase). 
    # Returns Inf if the transformer does not have a rating
    phases = filter(x -> x != 4, transformer["connections"][1])
    has_rating = haskey(transformer, "sm_nom") && !ismissing(transformer["sm_nom"]) && !isempty(transformer["sm_nom"])
    rating_kva = has_rating ? Float64(first(transformer["sm_nom"])) : Inf
    return rating_kva / length(phases), phases
end


function CreateTransformerPowerLimitsForEachPhase(data_eng)
    # Note: this function was generated by AI
    # Creates a dictionary of the power limit (in kW) of each phase for each transformer line (the lines that represent transformers in the simple powerflow model). 
    # The limit is based on the nominal power rating (sm_nom, in kVA) of the first winding of each transformer, divided evenly across the phases of the transformer. 
    # If multiple transformers are represented by the same line (such as single phase transformers), their limits are added for each phase. 
    # A transformer without a rating has no limit (Inf), which makes the limit infinite for the phases of that transformer.
    # Note that the real power limit is set equal to the apparent power rating (kVA), which assumes a power factor of one.
    limits = Dict{String, Dict{Int, Float64}}()
    for (transformer_name, transformer) in get(data_eng, "transformer", Dict())
        transformer_line = "xfmr_line_"*string(transformer["bus"][1])*"_"*string(transformer["bus"][2])
        rating_per_phase_kw, phases = TransformerRatingPerPhaseKw(transformer)
        limits_for_line = get!(limits, transformer_line, Dict{Int, Float64}())
        for phase in phases
            limits_for_line[phase] = get(limits_for_line, phase, 0.0) + rating_per_phase_kw
        end
    end
    return limits
end


function AddTransformerPowerLimitsToPMDTimesteps(pm, data_eng, data_math_mn)
    # Note: this function was generated by AI
    # Adds linear limits to the real power through each phase of the PMD transformers, which are the same limits that the simple power flow model uses (the nominal kVA rating divided by the number of phases). 
    # PMD only limits each phase of a transformer to the full rating of the transformer (sm_ub), which does not limit the transformer to the rating divided by the number of phases.
    # The ratings are from data_eng, and each transformer in the PMD model is matched to a transformer in data_eng by its name. A transformer in the PMD model is either 
    # named the same as the transformer in data_eng or, when the loss model is used, it is a "_virtual_transformer.<name>.<winding number>" for each winding
    rating_per_phase_kw = Dict{String, Float64}()
    for (transformer_name, transformer) in get(data_eng, "transformer", Dict())
        rating, _ = TransformerRatingPerPhaseKw(transformer)
        if rating < Inf
            rating_per_phase_kw[string(transformer_name)] = rating
            for winding in eachindex(transformer["bus"])
                rating_per_phase_kw["_virtual_transformer.$(transformer_name).$(winding)"] = rating
            end
        end
    end

    sbase = get(data_math_mn["nw"]["1"]["settings"], "sbase", 1.0) # The PMD power variables are in per unit, and the base power is in kW (as is used in CreateLineInfoDictionary)
    number_of_limits = 0

    for nw in PowerModelsDistribution.nw_ids(pm)
        pt = PowerModelsDistribution.var(pm, nw, :pt)
        connections = Dict((l,i,j) => conns for (bus, entry) in PowerModelsDistribution.ref(pm, nw, :bus_arcs_conns_transformer) for ((l,i,j), conns) in entry)

        for (l, transformer) in PowerModelsDistribution.ref(pm, nw, :transformer)
            name = string(get(transformer, "name", ""))
            if !haskey(rating_per_phase_kw, name)
                continue # No limit, because the transformer does not have a rating
            end
            limit = rating_per_phase_kw[name] / sbase

            for arc in [(l, transformer["f_bus"], transformer["t_bus"]), (l, transformer["t_bus"], transformer["f_bus"])]
                for c in connections[arc]
                    if c == 4
                        continue # the neutral
                    end
                    @constraint(pm.model, pt[arc][c] <= limit)
                    @constraint(pm.model, pt[arc][c] >= -limit)
                    number_of_limits += 2
                end
            end
        end
    end

    print("\n Added $(number_of_limits) transformer power limits to the PMD timesteps")
end


function AddSimplePowerFlowConstraintsToNonPMDTimesteps(Multinode_Inputs, REoptInputs_Combined, pm, m, REoptTimeSteps, LineInfo, REopt_nodes, data_eng; phases_for_each_line=nothing, phases_for_each_bus=nothing)
    print("\n Adding Simple Powerflow Constraints to Non-PMD Timesteps: This can take a few minutes for very large models")
    
    time_steps_without_PMD = setdiff(REoptTimeSteps, Multinode_Inputs.PMD_time_steps)
    indeces = collect(1:length(time_steps_without_PMD))
    print("\n Generated timesteps vector and indeces")

    connections, connections_upstream, connections_downstream, lines, transformer_busses, line_names_to_sourcebus_dict_including_transformers, phases_for_each_line_and_transformer_line, paths, neighbors, connections_upstream_busses, connections_downstream_busses, bus_pair_to_line_conversion = CreateDictionaryOfNodeConnections(Multinode_Inputs, data_eng)  # Note: the lines variable here includes lines that represent the transformer
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
    
    if phases_for_each_bus === nothing
        phases_for_each_bus = create_dictionary_of_phases_for_each_bus(data_eng)
    end
    all_busses = collect(keys(data_eng["bus"])) # This includes both the PMD and the REopt busses
    @variable(m, dvP[bus in all_busses, phase in phases, t in indeces; phase in phases_for_each_bus[bus]] >= -1000000 )
    #@variable(m, Q[REopt_nodes] >= -10000000)
    
    print("\n Generating dvP variable for lines (this may take a few minutes for large models using the simple powerflow constraints)")
    if phases_for_each_line === nothing
        phases_for_each_line = create_dictionary_of_phases_for_each_line(data_eng)
    end
    
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

    # The power limit for each phase of the lines that represent transformers, based on the transformer ratings. Phases of transformers without a rating are not limited (the 100000000 kW is a large number that represents no limit)
    transformer_power_limits = CreateTransformerPowerLimitsForEachPhase(data_eng)
    transformer_limit_kw(line, phase) = min(get(get(transformer_power_limits, line, Dict{Int,Float64}()), phase, Inf), 100000000.0)
    
    # Add constraints for maximum power through each line. The power flow variables are per phase, so the limit for each phase of a line is the current rating of the line multiplied by the line-to-neutral voltage (LineInfo[line]["maximum_power_kw"] is also the limit for each phase)
    if Multinode_Inputs.model_line_upgrades
        print("Adding simple powerflow constraints to allow for line upgrades")
        line_upgrade_options_each_line = CreateDictionaryOfLineUpgradeOptions(Multinode_Inputs)
        for line in lines

            if line in keys(line_upgrade_options_each_line)
              
                # Note: line amperage ratings are for each conductor in a multiphase system. The limit for each phase is the current rating multiplied by the line-to-neutral voltage from the PMD model
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], dvPline[line, phase, t] <= m[:line_max_amps][line] * LineInfo[line]["line_to_neutral_voltage_kv"])
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], dvPline[line, phase, t] >= -m[:line_max_amps][line] * LineInfo[line]["line_to_neutral_voltage_kv"])

            elseif line in keys(transformer_busses)
                # Note: the transformer power rating is divided evenly across the phases of the transformer
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] <= transformer_limit_kw(line, phase))
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] >= -transformer_limit_kw(line, phase))
            else
                if LineInfo[line]["maximum_power_kw"] == Inf
                    line_max_power = 1000000000 #LineInfo[line]["maximum_power_kw"]
                    if Multinode_Inputs.display_information_during_modeling_run
                        print("\n Line max power for line $(line) is infinite, setting the line_max_power for $(line) to $(line_max_power)")
                    end
                else
                    line_max_power = LineInfo[line]["maximum_power_kw"]
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
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] <= transformer_limit_kw(line, phase))
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] >= -transformer_limit_kw(line, phase))
            else
                if LineInfo[line]["maximum_power_kw"] == Inf
                    line_max_power = 1000000000 #LineInfo[line]["maximum_power_kw"]
                else
                    line_max_power = LineInfo[line]["maximum_power_kw"]
                end
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] <= line_max_power) # Defines the maximum real power flow through the line
                @constraint(m, [t in indeces, phase in phases_for_each_line[line]], m[:dvPline][line, phase, t] >= -line_max_power)
                #@constraint(m, m[:dvQline][line, t] <= )
                #@constraint(m, m[:dvQline][line, t] >= 0)
            end
        end
        print("\n]")
    end
    
    counter = 0

    # ----- Start of section of code that was generated with the assistance of AI
    # The phases that each REopt node uses. In a single phase model, the phase numbers are not used, so the node uses the phases of its bus. 
    # In a multi-phase model, the node's power is split across the phases defined for the node (as is done when the node is linked to PMD), and the other phases of the bus have no injection
    REopt_node_phases = Dict{String, Vector{Int}}()
    for p in REoptInputs_Combined
        node_name = string(p.s.site.node)
        if node_name in string.(REopt_nodes)
            bus_phases = BusPhasesForREoptNode(phases_for_each_bus, node_name)
            if Multinode_Inputs.number_of_phases == 1
                REopt_node_phases[node_name] = collect(bus_phases)
            else
                node_phases = collect(p.s.settings.phase_numbers)
                if !all(phase -> phase in bus_phases, node_phases)
                    throw(@error("REopt node $(node_name) has the phases $(node_phases), but the bus has the phases $(bus_phases). All of the phases of a REopt node must be phases of the bus."))
                end
                REopt_node_phases[node_name] = node_phases
            end
        end
    end
    # ----- End of section of code that was generated with the assistance of AI

    # Link this simple powerflow model to the REopt nodes
    Multinode_Inputs.display_information_during_modeling_run ? print("\n Information about connecting the REopt nodes to the simple powerflow model") : nothing
    for (index, t) in enumerate(time_steps_without_PMD)
        counter = counter + 1
        for node in REopt_nodes  # only link the REopt nodes to PMD busses
            if string(node) != Multinode_Inputs.substation_node
                if counter in [1,2] # print information only for the first two timesteps
                    Multinode_Inputs.display_information_during_modeling_run ? print("\n Connecting REopt node $(node) to the simple powerflow model") : nothing
                end
                node_phases = REopt_node_phases[string(node)]
                for phase in BusPhasesForREoptNode(phases_for_each_bus, node)
                    # This constraint assumes that multiphase nodes with loads (or generators) consume (or distribute) power evenly across each phase of the node. Phases of the bus that are not phases of the node have no power injection
                    phase_fraction = phase in node_phases ? 1/length(node_phases) : 0.0
                    @constraint(m, m[:dvP][string(node), phase, index] .== phase_fraction .* ((m[Symbol("TotalExport_"*string(node))][t]) .- TotalGridPurchaseAtNode(m, node, t)) ) # To do: double check that these variable names are correct
                    
                    if Multinode_Inputs.display_information_during_modeling_run 
                        if t in [1,2] # print out some information for the first couple timesteps
                            print("\n For node $(node), the phases_for_each_bus are: $(phases_for_each_bus[string(node)]), and the phases of the node are $(node_phases)")
                            print("\n    The index is $(index), and the t i $(t), and the phase is $(phase)")
                            print("\n    The fraction of the node's power on the phase is $(phase_fraction)")
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

    if Multinode_Inputs.display_information_during_modeling_run
        print("\n The phases for each bus are: $(phases_for_each_bus)")
        print("\n The REopt nodes are: $(REopt_nodes)")
    end
    REopt_node_names = string.(REopt_nodes) # The busses are strings, and the REopt nodes can be integers or strings
    # Conservation of energy for each bus
    for bus in collect(keys(connections)) # all_busses #
        bus_connections = connections[bus]
        
        if bus == Multinode_Inputs.substation_node
            # Start of section of code created by AI
            # KCL at the substation bus, with dvP[substation, phase] retained as
            # a free slack variable representing the source injection from the
            # grid. Same form as the REopt-bus KCL below, but no linkage to
            # GP/Export: dvP[sub, ph] + Σ upstream - Σ downstream = 0.
            # dvP[sub, ph] is otherwise unconstrained (declared in all_busses).
            Multinode_Inputs.display_information_during_modeling_run ? print("\n Adding KCL for substation bus $(bus)") : nothing
            for phase in phases_for_each_bus[bus]
                connections_upstream_of_same_phase = []
                for line in get(connections_upstream, string(bus), [])
                    if phase in phases_for_each_line[line]
                        push!(connections_upstream_of_same_phase, line)
                    end
                end
                connections_downstream_of_same_phase = []
                for line in get(connections_downstream, string(bus), [])
                    if phase in phases_for_each_line[line]
                        push!(connections_downstream_of_same_phase, line)
                    end
                end
                @constraint(m, [t in indeces], m[:dvP][bus, phase, t] + sum(m[:dvPline][line, phase, t] for line in connections_upstream_of_same_phase; init=0) - sum(m[:dvPline][line, phase, t] for line in connections_downstream_of_same_phase; init=0) == 0)
            end
            # End of code segment created by AI
            
        elseif bus in REopt_node_names # for buses that have an associated REopt node
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
    REopt.build_reopt!(m, REoptInputs_Combined, Multinode_Inputs) # Pass the PMD JuMP model (with the PowerModelsDistribution variables and constraints) as the JuMP model that REopt should build onto
    
    CreateREoptTotalExportVariables(m, REoptInputs_Combined)

    # Cache dictionaries that would otherwise be recomputed inside many helpers
    phases_for_each_line = create_dictionary_of_phases_for_each_line(data_eng)
    phases_for_each_bus = create_dictionary_of_phases_for_each_bus(data_eng)
    gen_name2ind, load_phase_dictionary, gen_ind_e_to_REopt_node = generate_PMD_information(Multinode_Inputs, REopt_nodes, REoptInputs_Combined, data_math_mn)

    REopt_gen_ind_e, load_phase_dictionary, gen_ind_e_to_REopt_node = LinkREoptAndPMD(pm, m, data_math_mn, Multinode_Inputs, REopt_nodes, REoptInputs_Combined; gen_name2ind=gen_name2ind, load_phase_dictionary=load_phase_dictionary, gen_ind_e_to_REopt_node=gen_ind_e_to_REopt_node)
    LineInfo = CreateLineInfoDictionary(Multinode_Inputs, pm, data_math_mn)
    AddTransformerPowerLimitsToPMDTimesteps(pm, data_eng, data_math_mn)
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
        connections, connections_upstream, connections_downstream = AddSimplePowerFlowConstraintsToNonPMDTimesteps(Multinode_Inputs, REoptInputs_Combined, pm, m, REoptTimeSteps, LineInfo, REopt_nodes, data_eng; phases_for_each_line=phases_for_each_line, phases_for_each_bus=phases_for_each_bus)
    else
        connections = "N/A"
        connections_upstream = "N/A" 
        connections_downstream = "N/A"
    end

    ApplyGridImportAndExportConstraints(Multinode_Inputs, REoptInputs_Combined, pm, m, REoptTimeSteps, LineInfo, OutageSimulator, OutageLength_Timesteps, data_eng; phases_for_each_line=phases_for_each_line)
    
    LinkFacilityMeterNodeToSubstationPower(m, pm, Multinode_Inputs, REoptInputs_Combined, LineInfo, REopt_gen_ind_e, REoptTimeSteps, REopt_nodes, data_math_mn, data_eng; phases_for_each_line=phases_for_each_line, gen_name2ind=gen_name2ind, load_phase_dictionary=load_phase_dictionary, gen_ind_e_to_REopt_node=gen_ind_e_to_REopt_node)
    
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

    @constraint(model, model[:dvBusVoltageViolationCost] == Multinode_Inputs.cost_per_voltage_violation_per_timestep * sum(model[:binBusVoltageViolation][bus_name, PMD_time_step] for bus_name in bus_names, PMD_time_step in PMD_time_steps))

end


function ApplyGridImportAndExportConstraints(Multinode_Inputs, REoptInputs_Combined, pm, m, REoptTimeSteps, LineInfo, OutageSimulator, OutageLength_Timesteps, data_eng; phases_for_each_line=nothing)
    # Apply a variety of grid import and/or export constraints:
    
    # Restrict power flow from the substation if the multinode type is offgrid
    if Multinode_Inputs.multinode_type == "Offgrid" 
        RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, REoptTimeSteps, LineInfo, data_eng; Off_Grid=true, phases_for_each_line=phases_for_each_line)
    end
    
    # Define limits on grid import and export
    if Multinode_Inputs.allow_export_beyond_substation == false # Prevent power from being exported to the grid beyond the facility meter:
        print("\n Prohibiting power export at the substation")
        #RestrictLinePowerFlow(Multinode_Inputs, pm, m, Multinode_Inputs.substation_line, REoptTimeSteps, LineInfo; Prevent_Export=true) # This constraint is handled by other constraints below
    elseif Multinode_Inputs.substation_export_limit != ""
        print("\n Applying a limit to the power export at the substation")
        RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, REoptTimeSteps, LineInfo, data_eng; Substation_Export_Limit = Multinode_Inputs.substation_export_limit, phases_for_each_line=phases_for_each_line)
    end 
    
    if isfinite(Multinode_Inputs.substation_import_limit) # An infinite import limit means that there is no limit
        print("\n Applying a limit to the power import from the substation")
        RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, REoptTimeSteps, LineInfo, data_eng; Substation_Import_Limit = Multinode_Inputs.substation_import_limit, phases_for_each_line=phases_for_each_line)
    end 
    
    # Apply a grid outage to the model
    if Multinode_Inputs.model_outages_with_outages_vector
        if Multinode_Inputs.outages_vector != []
            print("\n Applying a grid outages on the following timesteps: ")
            print(Multinode_Inputs.model_outages_with_outages_vector)
            RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, Multinode_Inputs.outages_vector, LineInfo, data_eng; Grid_Outage=true, OutageSimulator = OutageSimulator, OutageLength_Timesteps = OutageLength_Timesteps, phases_for_each_line=phases_for_each_line)
        end    
    elseif Multinode_Inputs.single_outage_end_time_step - Multinode_Inputs.single_outage_start_time_step > 0
        print("\n Applying a grid outage from time step $(Multinode_Inputs.single_outage_start_time_step) to $(Multinode_Inputs.single_outage_end_time_step) ")
        RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, Multinode_Inputs.substation_line, collect(Multinode_Inputs.single_outage_start_time_step:Multinode_Inputs.single_outage_end_time_step), LineInfo, data_eng; Grid_Outage=true, OutageSimulator = OutageSimulator, OutageLength_Timesteps = OutageLength_Timesteps, phases_for_each_line=phases_for_each_line)
    end
    
    # Open switches if defined by the user
        # Note: the switch capability in PMD is not used currently in this model, but the switch openings are modeling with these constraints
    if (Multinode_Inputs.switch_open_timesteps != "") && (Multinode_Inputs.model_switches == true)
        print("\n Switches are included in the model")
        for i in keys(Multinode_Inputs.switch_open_timesteps)
            #print("\n   Opening the switch on line $(i) from timesteps $(minimum(Multinode_Inputs.switch_open_timesteps[i])) to $(maximum(Multinode_Inputs.switch_open_timesteps[i])) \n")
            RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, i, Multinode_Inputs.switch_open_timesteps[i], LineInfo, data_eng; Switches_Open=true, phases_for_each_line=phases_for_each_line)
        end
    end
    
end


function LinkFacilityMeterNodeToSubstationPower(m, pm, Multinode_Inputs, REoptInputs_Combined, LineInfo, REopt_gen_ind_e, REoptTimeSteps, REopt_nodes, data_math_mn, data_eng; phases_for_each_line=nothing, gen_name2ind=nothing, load_phase_dictionary=nothing, gen_ind_e_to_REopt_node=nothing)
    # Link export through the substation to the utility tariff on the facility meter node
    
    PMDTimeSteps_InREoptTimes = Multinode_Inputs.PMD_time_steps
    buses = REopt_nodes

    if gen_name2ind === nothing || load_phase_dictionary === nothing || gen_ind_e_to_REopt_node === nothing
        gen_name2ind, load_phase_dictionary, gen_ind_e_to_REopt_node = generate_PMD_information(Multinode_Inputs, REopt_nodes, REoptInputs_Combined, data_math_mn)
    end

    if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
        time_steps_without_PMD = setdiff(REoptTimeSteps, Multinode_Inputs.PMD_time_steps)
    else
        time_steps_without_PMD = 0
    end

    if phases_for_each_line === nothing
        phases_for_each_line = create_dictionary_of_phases_for_each_line(data_eng)
    end

    # Precompute O(1) lookups for PMD timestep index and simple-PF timestep index
    pmd_index_of = Dict(t => i for (i, t) in enumerate(PMDTimeSteps_InREoptTimes))
    simple_pf_index_of = isa(time_steps_without_PMD, AbstractVector) ?
        Dict(t => i for (i, t) in enumerate(time_steps_without_PMD)) :
        Dict{Int,Int}()

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
                    
                    if haskey(pmd_index_of, timestep)
                        
                        PMD_time_step = pmd_index_of[timestep]

                        p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
                        p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
                        
                        if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                            q_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :q, f_idx)[c] for c in f_connections]
                            q_to = [PowerModelsDistribution.var(pm, PMD_time_step, :q, t_idx)[c] for c in t_connections]
                        end

                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == sum(p_fr))
                    
                    elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD      
                        simple_powerflow_timestep = simple_pf_index_of[timestep]
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == sum(m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, simple_powerflow_timestep] for phase in phases_for_each_line[lowercase(Multinode_Inputs.substation_line)]))
                        
                    else
                        # Instead of using the line flow from PMD or the simple powerflow model, consider the total system inflow/outflow to be based on a lumped-element model, which sums all power inflows and outflows for each node
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] ==
                            (-sum(m[Symbol("TotalExport_"*string(node))][timestep] for node in REopt_nodes) + 
                            sum(TotalGridPurchaseAtNode(m, node, timestep) for node in REopt_nodes)))
                    end

                    @constraint(m, m[:dvSubstationPowerFlow][timestep] == (sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) - 
                                                                                sum(m[Symbol("dvProductionToGrid_"*p.s.settings.facilitymeter_node)]["PV", u, timestep] for u in p.export_bins_by_tech["PV"]))) 
            
                    # The import limit is used with the binary to prevent simultaneous import and export. An infinite limit (no limit) is replaced with the same large number used for dvSubstationPowerFlow (Inf * a variable cannot be used in a constraint)
                    @constraint(m, sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) <= min(Multinode_Inputs.substation_import_limit, 1000000) * m[:binSubstationPositivePowerFlow][timestep])
                    
                    @constraint(m, sum(m[Symbol("dvProductionToGrid_"*p.s.settings.facilitymeter_node)]["PV", u, timestep] for u in p.export_bins_by_tech["PV"]) <= Multinode_Inputs.substation_export_limit * (1 - m[:binSubstationPositivePowerFlow][timestep]))
                    
                    @constraint(m, sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) >= 0)
                    
                    @constraint(m, sum(m[Symbol("dvProductionToGrid_"*p.s.settings.facilitymeter_node)]["PV", u, timestep] for u in p.export_bins_by_tech["PV"]) >= 0)
                                    
                else                  
                    @constraint(m, sum(m[Symbol("dvProductionToGrid_"*p.s.settings.facilitymeter_node)]["PV", u, timestep] for u in p.export_bins_by_tech["PV"]) == 0)

                    if haskey(pmd_index_of, timestep)
                        PMD_time_step = pmd_index_of[timestep]

                        p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
                        p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
                        
                        if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                            q_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :q, f_idx)[c] for c in f_connections]
                            q_to = [PowerModelsDistribution.var(pm, PMD_time_step, :q, t_idx)[c] for c in t_connections]
                        end

                        @constraint(m, sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) == sum(p_fr))
                        
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == sum(p_fr)) 
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] >= 0) 
                    
                    elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                        simple_powerflow_timestep = simple_pf_index_of[timestep]
                        
                        @constraint(m, sum(m[Symbol("dvGridPurchase_"*p.s.settings.facilitymeter_node)][timestep, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) == sum(m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, simple_powerflow_timestep] for phase in phases_for_each_line[lowercase(Multinode_Inputs.substation_line)]))
                        
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] == sum(m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, simple_powerflow_timestep] for phase in phases_for_each_line[lowercase(Multinode_Inputs.substation_line)]))
                        @constraint(m, m[:dvSubstationPowerFlow][timestep] >= 0) 
                        
                    else
                        # Instead of using the line flow from PMD or simple powerflow model, consider the total system inflow/outflow to be based on a lumped-element model, which sums all power inflows and outflows for each node
                        @constraint(m,
                            (sum(m[Symbol("TotalExport_"*string(node))][timestep] for node in REopt_nodes)  - 
                            sum(TotalGridPurchaseAtNode(m, node, timestep) for node in REopt_nodes)) == 
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
    # Prevent the generators from generating power during times when grid power supply is available
    for p in REoptInputs_Combined
        _n = "_"*string(p.s.site.node)
        if "Generator" in p.techs.elec
            for ts in Multinode_Inputs.grid_available_timesteps
			    fix(m[Symbol("dvRatedProduction"*_n)]["Generator", ts], 0.0, force=true)
            end       
        end
    end
end


function CreateLineInfoDictionary(Multinode_Inputs, pm, data_math_mn)
    # Creates a dictionary with the line names and corresponding indeces for the :p decision variable
    LineInfo = Dict([])
    NumberOfBranches = length(PowerModelsDistribution.ref(pm,1,:branch))

    # The power base of the PMD model, which is 1 kW (see ApplyDataEngSettings), so a per unit power is equal to a power in kW
    sbase = get(data_math_mn["nw"]["1"]["settings"], "sbase", 1.0)
   
    for i in 1:NumberOfBranches
        LineData = PowerModelsDistribution.ref(pm, 1, :branch, i)
        
        branch_vbase = LineData["vbase"] # The line-to-neutral voltage base of the branch (kV)
        c_rating_a = minimum(LineData["c_rating_a"]) # The current rating of the line in per unit (the smallest rating if the phases have different ratings)

        # The maximum power for each phase of the line is the current rating multiplied by the line-to-neutral voltage. In per unit, the current rating is the 
        # current (in amps) multiplied by vbase/sbase, so the maximum power for each phase (in kW) is the per unit current rating multiplied by sbase. 
        
        maximum_power = round(c_rating_a * sbase, digits=3)
        
        line_name = LineData["name"]
        if Multinode_Inputs.display_information_during_modeling_run
            print("\n For line $(line_name), the data is max power for each phase: $(maximum_power), c_rating_a: $(c_rating_a), branch_vbase (line-to-neutral): $(branch_vbase)")
        end

        LineInfo[LineData["name"]] = Dict(["index"=>LineData["index"], 
                                           "t_bus"=>LineData["t_bus"], 
                                           "f_bus"=>LineData["f_bus"], 
                                           "c_rating_a"=>LineData["c_rating_a"], 
                                           "vbase"=>LineData["vbase"],
                                           "line_to_neutral_voltage_kv"=>branch_vbase,
                                           "maximum_power_kw"=>maximum_power # The maximum power for each phase of the line
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

        # Distinguish BAU vs main run logs. The log is saved in the current working directory (the full path is used so the message below shows where the file is)
        log_filename = isfile(timestamp*"_xpress_log.txt") ? timestamp*"_xpress_log_BAU.txt" : timestamp*"_xpress_log.txt"
        xpress_log_path = abspath(log_filename)

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
        
        if Multinode_Inputs.run_Xpress_model_presolve == false
            print("\n Removing the presolve step because Multinode_Inputs.run_Xpress_model_presolve was set to false")
            set_optimizer_attribute(m, "PRESOLVE", 0)
        end

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
        if Multinode_Inputs.run_IIS_on_nonoptimal_models
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
                        # The file is saved in the current working directory, with the same naming approach as the Xpress log
                        iis_filename = isfile(timestamp*"_iis_conflict.txt") ? timestamp*"_iis_conflict_BAU.txt" : timestamp*"_iis_conflict.txt"
                        iis_path = abspath(iis_filename)
                        println("Writing the IIS conflict file to $(iis_path)")
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
        end
        
        @warn("The termination status of the optimization was "*string(results["termination_status"])*". Returning the failed model without further processing.")
    end
        
    return results, TerminationStatus;
end


function RestrictLinePowerFlow(Multinode_Inputs, REoptInputs_Combined, pm, m, line, REoptTimeSteps, LineInfo, data_eng; Grid_Outage=false, Off_Grid=false, Switches_Open=false, Prevent_Export=false, Substation_Export_Limit=1E10, Substation_Import_Limit=1E10, OutageSimulator = false, OutageLength_Timesteps = 0, phases_for_each_line=nothing)
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

    if phases_for_each_line === nothing
        phases_for_each_line = create_dictionary_of_phases_for_each_line(data_eng)
    end
    
    if Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD    
        time_steps_without_PMD = setdiff(REoptTimeSteps, Multinode_Inputs.PMD_time_steps)
    else
        time_steps_without_PMD = 0
    end

    # Precompute O(1) lookups for PMD timestep index and simple-PF timestep index
    pmd_index_of = Dict(t => i for (i, t) in enumerate(PMDTimeSteps_InREoptTimes))
    simple_pf_index_of = isa(time_steps_without_PMD, AbstractVector) ?
        Dict(t => i for (i, t) in enumerate(time_steps_without_PMD)) :
        Dict{Int,Int}()

    for timestep in REoptTimeSteps
            
        if haskey(pmd_index_of, timestep)
            # Based off of code in line 274 of PMD's src>core>constraints
            PMD_time_step = pmd_index_of[timestep]
            
            p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
            p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
            
            if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                q_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :q, f_idx)[c] for c in f_connections]
                q_to = [PowerModelsDistribution.var(pm, PMD_time_step, :q, t_idx)[c] for c in t_connections]
            end
        elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
            # redefine the timestep variable to be correlated with the timestep variable in the simple powerflow model
            timestep_for_simple_powerflow_model = simple_pf_index_of[timestep]
        end

        if Prevent_Export == true
            # If the timesteps are part of the PMD model, then apply the constraints to the lines in PMD. The vectors are indexed by position
            if haskey(pmd_index_of, timestep)
                JuMP.@constraint(m, [k in eachindex(p_fr)], p_fr[k] >= 0)
                if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                    JuMP.@constraint(m, [k in eachindex(q_fr)], q_fr[k] >= -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar) # no restrictions on reactive power
                end
            elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                for phase in phases_for_each_line[line]
                    @constraint(m, m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, timestep_for_simple_powerflow_model] .>= 0)
                end
            else
                @constraint(m, sum(m[Symbol("dvProductionToGrid_"*Multinode_Inputs.facilitymeter_node)]["PV", u, timestep] for u in FacilityMeterNode_REoptInputs.export_bins_by_tech["PV"]) == 0)
            end
        end

        # The substation export and import limits apply to the total power flow through the line (the sum of the phases)
        if Substation_Export_Limit != ""
            if haskey(pmd_index_of, timestep)
                JuMP.@constraint(m, sum(p_fr) >= -Substation_Export_Limit) 
                if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                    JuMP.@constraint(m, [k in eachindex(q_fr)], q_fr[k] >= -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar)
                end
            elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                @constraint(m, sum(m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, timestep_for_simple_powerflow_model] for phase in phases_for_each_line[line]) >= -Substation_Export_Limit)
            else
                @constraint(m, sum(m[Symbol("dvProductionToGrid_"*Multinode_Inputs.facilitymeter_node)]["PV", u, timestep] for u in FacilityMeterNode_REoptInputs.export_bins_by_tech["PV"]) <= Substation_Export_Limit)
            end
        end

        if isfinite(Substation_Import_Limit)
            if haskey(pmd_index_of, timestep)
                JuMP.@constraint(m, sum(p_fr) <= Substation_Import_Limit)
                if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                    JuMP.@constraint(m, [k in eachindex(q_fr)], q_fr[k] <= Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar)
                end
            elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                @constraint(m, sum(m[:dvPline][lowercase(Multinode_Inputs.substation_line), phase, timestep_for_simple_powerflow_model] for phase in phases_for_each_line[line]) <= Substation_Import_Limit)
            else
                @constraint(m, sum(m[Symbol("dvGridPurchase_"*Multinode_Inputs.facilitymeter_node)][timestep, tier] for tier in 1:FacilityMeterNode_REoptInputs.s.electric_tariff.n_energy_tiers) <= Substation_Import_Limit)
            end
        end
 
        if Off_Grid == true || Grid_Outage == true || Switches_Open==true
            # Restrict all power flow
            if haskey(pmd_index_of, timestep)
                JuMP.@constraint(m, [k in eachindex(p_fr)], p_fr[k] == 0)  # The _fr and _to variables are just indicating power flow in either direction on the line. In PMD, there is a constraint that requires  p_to = -p_fr 
                JuMP.@constraint(m, [k in eachindex(p_to)], p_to[k] == 0)  # TODO test removing the "fr" constraints here in order to reduce the # of constraints in the model
                if Multinode_Inputs.model_subtype != "NFAUPowerModel"
                    if Multinode_Inputs.number_of_phases == 1                
                        JuMP.@constraint(m, [k in eachindex(q_fr)], q_fr[k] == 0.0)
                        JuMP.@constraint(m, [k in eachindex(q_to)], q_to[k] == 0.0)
                    else
                        # Add small amount of reactive power support for multi-phase systems
                        JuMP.@constraint(m, [k in eachindex(q_fr)], -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar <= q_fr[k] <= Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar) 
                        JuMP.@constraint(m, [k in eachindex(q_to)], -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar <= q_to[k] <= Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar) # no restrictions on reactive power
                    end
                end
            elseif Multinode_Inputs.apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
                for phase in phases_for_each_line[line]
                    @constraint(m, m[:dvPline][line, phase, timestep_for_simple_powerflow_model] .== 0)
                end               
            elseif Switches_Open==false
                @constraint(m, sum(m[Symbol("dvGridPurchase_"*Multinode_Inputs.facilitymeter_node)][timestep, tier] for tier in 1:FacilityMeterNode_REoptInputs.s.electric_tariff.n_energy_tiers) == 0)
                @constraint(m, sum(m[Symbol("dvProductionToGrid_"*Multinode_Inputs.facilitymeter_node)]["PV", u, timestep] for u in FacilityMeterNode_REoptInputs.export_bins_by_tech["PV"]) == 0)
            else # The switches are open (Switches_Open == true) during a time step that is not modeled with PMD or the simple powerflow model
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
        if Multinode_Inputs.run_outage_simulator || Multinode_Inputs.model_outages_with_outages_vector || ((Multinode_Inputs.single_outage_end_time_step - Multinode_Inputs.single_outage_start_time_step) > 0 )

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
        
        if Int(length(p.s.electric_load.loads_kw)) != Int(8760 * Multinode_Inputs.time_steps_per_hour)
            throw(@error("At REopt node $(node_temp), the length of the electric loads vector does not correlate with the time steps per hour defined in the Multinode_Inputs dictionary"))
        end
    end
    
    if Multinode_Inputs.number_of_phases ∉ [1,2,3]
        throw(@error("The number_of_phases input must be 1, 2, or 3"))
    end

    if Multinode_Inputs.multinode_type ∉ ["CommunityDistrict", "BehindTheMeter", "Offgrid"]
        throw(@error("An invalid multinode type was provided in the inputs. The options are \"BehindTheMeter\", \"CommunityDistrict\", and \"Offgrid\"."))
    end

    if (Multinode_Inputs.multinode_type == "Offgrid") && (Multinode_Inputs.run_BAU_case == true)
        throw(@error("The BAU case cannot be run for an off-grid model because an off-grid model cannot solve without on-site generation."))
    end
    
    if Multinode_Inputs.multinode_type == "CommunityDistrict"
        @warn("For the community district multinode type, the electricity tariff for the facility meter node should be 0")
    end

    # The facility meter node needs PV defined (it can have a size of zero) because the export through the facility meter is modeled using the PV export variables
    for p in ps
        if string(p.s.site.node) == Multinode_Inputs.facilitymeter_node
            if !("PV" in p.techs.all) || !haskey(p.export_bins_by_tech, "PV")
                throw(@error("The facility meter node, $(p.s.site.node), must have a PV defined in its REopt inputs (and a net metering or wholesale rate so that export bins exist), because the export through the facility meter is modeled using the PV export variables. The PV can have a maximum size of zero."))
            end
        end
    end

    # The outage simulator needs a critical load method to define the critical loads
    if Multinode_Inputs.run_outage_simulator && (Multinode_Inputs.critical_load_method == "N/A")
        throw(@error("The outage simulator requires the critical_load_method to be \"Fraction\" or \"TimeSeries\" (it cannot be \"N/A\")"))
    end

    if Multinode_Inputs.critical_load_method == "Fraction"
        for x in values(Multinode_Inputs.critical_load_fraction)
            if x < 0
                throw(@error("The critical_load_fraction values cannot be negative"))
            end
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
        throw(@error("When modeling a multi-phase system, allowing dropped load in the outage simulator is not allowed. Please set the allow_dropped_load input to false."))
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
    if Multinode_Inputs.PMD_network_input isa AbstractDict
        data_eng = deepcopy(Multinode_Inputs.PMD_network_input) # The network input can be a dictionary that was already parsed
    else
        data_eng = PowerModelsDistribution.parse_file(Multinode_Inputs.PMD_network_input, transformations=[PowerModelsDistribution.remove_all_bounds!])
    end

    PowerModelsDistribution.remove_all_bounds!(data_eng; exclude = ["cm_ub","sm_ub","energy_ub"]) # Note: voltage bounds are manually applied later

    # Check that each REopt node is a bus in the network (with the same capitalization)
    CheckThatREoptNodesAreBusses(Multinode_Inputs, data_eng)

    # The substation line is used to link the facility meter node to the network, so it must be a line in the network (the names of the lines are lowercase)
    if !(lowercase(Multinode_Inputs.substation_line) in lowercase.(string.(keys(data_eng["line"]))))
        throw(@error("The substation_line, \"$(Multinode_Inputs.substation_line)\", is not a line in the PMD network. The lines in the network are: $(sort(string.(collect(keys(data_eng["line"])))))"))
    end

    has_loops, loop_edges = REopt.detect_network_loops(data_eng)
    has_islands, islanded_buses, island_groups = REopt.detect_islanded_buses(data_eng, Multinode_Inputs.substation_node)

    if has_loops
        @warn("The distribution system has the following loops: $(loop_edges)")
    end
    if has_islands
        @warn("The following islands are present in the distribution system: $(island_groups)")
    end

    # ----- Beginning of additional data checks generated by AI
    if Multinode_Inputs.time_steps_per_hour <= 0
        throw(@error("The time_steps_per_hour input must be defined in the multinode settings, and it must be greater than zero"))
    end

    # The PMD_time_steps are REopt time steps, so they need to be unique integers within the length of the year
    number_of_time_steps_in_year = Int(8760 * Multinode_Inputs.time_steps_per_hour)
    if !all(t -> t isa Integer, Multinode_Inputs.PMD_time_steps)
        throw(@error("The PMD_time_steps input must be a vector of integers, for example collect(1:24) (and not [1:24], which is a vector that contains a range)"))
    end
    if !all(t -> 1 <= t <= number_of_time_steps_in_year, Multinode_Inputs.PMD_time_steps)
        throw(@error("The PMD_time_steps must be between 1 and the number of time steps in the year, which is $(number_of_time_steps_in_year)"))
    end
    if length(unique(Multinode_Inputs.PMD_time_steps)) != length(Multinode_Inputs.PMD_time_steps)
        throw(@error("The PMD_time_steps input can't list the same time step more than once"))
    end
    # ----- End of additional data checks generated by AI

end

