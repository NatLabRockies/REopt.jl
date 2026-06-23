# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function run_outage_simulator(DataDictionaryForEachNode, REopt_dictionary, Multinode_Inputs, TimeStamp, LineInfo_PMD, line_upgrade_options_each_line, line_upgrade_results, REopt_inputs_combined)
    
    Outage_Results = Dict([])
    outage_simulator_time_start = now()
    outage_simulator_results_for_plotting = Dict([])
    outage_survival_results_dictionary = Dict([])
    outage_start_timesteps_dictionary = Dict([])
    m_outagesimulator_dictionary = Dict([])

    # TODO: Transfer any transformer upgrades from the main optimization model into the outage simulator
    #transformer_max_kva= "N/A"
    
    single_model_outage_simulator = "empty"
    for i in 1:length(Multinode_Inputs.length_of_simulated_outages_time_steps)
        OutageLength = Multinode_Inputs.length_of_simulated_outages_time_steps[i]
        pm, OutageLength_TimeSteps_Input, SuccessfullySolved, TimeStepsNotSolved, RunNumber, PercentOfOutagesSurvived, single_model_outage_simulator, outage_survival_results, outage_start_timesteps, dropped_load_results_summary, outage_data_for_plotting = Multinode_OutageSimulator(DataDictionaryForEachNode, 
                                                                                                                                                                                                    REopt_dictionary, 
                                                                                                                                                                                                    Multinode_Inputs, 
                                                                                                                                                                                                    TimeStamp,
                                                                                                                                                                                                    line_upgrade_options_each_line,
                                                                                                                                                                                                    line_upgrade_results, 
                                                                                                                                                                                                    REopt_inputs_combined;
                                                                                                                                                                                                    LineInfo_PMD = LineInfo_PMD,
                                                                                                                                                                                                    NumberOfOutagesToTest = Multinode_Inputs.number_of_outages_to_simulate, 
                                                                                                                                                                                                    OutageLength_TimeSteps_Input = OutageLength)
        Outage_Results["$(OutageLength_TimeSteps_Input)_timesteps_outage"] = Dict(["PercentSurvived" => PercentOfOutagesSurvived, 
                                                                             "NumberOfRuns" => RunNumber,
                                                                             "pm" => pm,
                                                                             "time_steps_not_solved" => TimeStepsNotSolved,  
                                                                             "NumberOfOutagesSurvived" => SuccessfullySolved, 
                                                                             "outage_survival_results_each_timestep" => outage_survival_results,
                                                                             "outage_start_timesteps" => outage_start_timesteps,
                                                                             "dropped_load_results" => dropped_load_results_summary ])
        
        if Multinode_Inputs.generate_dictionary_for_plotting
            
            additional_outage_results_for_plotting = Dict(["outage_survival_results" => outage_survival_results, 
                                                           "outage_start_timesteps_checked" => outage_start_timesteps, 
                                                           "TimeStamp"=>TimeStamp, 
                                                           "OutageLength_TimeSteps_Input"=>OutageLength_TimeSteps_Input])
            
            merge!(outage_data_for_plotting, additional_outage_results_for_plotting)
            outage_simulator_results_for_plotting[OutageLength_TimeSteps_Input] = outage_data_for_plotting
        end

        outage_survival_results_dictionary[OutageLength] = outage_survival_results
        outage_start_timesteps_dictionary[OutageLength] = outage_start_timesteps

    end
    outage_simulator_time_milliseconds, outage_simulator_time_minutes = CalculateComputationTime(outage_simulator_time_start)
    return Outage_Results, single_model_outage_simulator, outage_simulator_time_minutes, outage_simulator_results_for_plotting, outage_survival_results_dictionary, outage_start_timesteps_dictionary
end


function Multinode_OutageSimulator(DataDictionaryForEachNode, REopt_dictionary, Multinode_Inputs, TimeStamp, line_upgrade_options_each_line, line_upgrade_results, REopt_inputs_combined;
                                   NumberOfOutagesToTest = 15, OutageLength_TimeSteps_Input = 1, LineInfo_PMD="")
    # This function runs the outage simulator for a particular outage length
    
    # Initialize variables prior to running the simulator:
    NodeList = string.(GenerateREoptNodesList(Multinode_Inputs))
    #NodesWithPV = DetermineNodesWithPV(DataDictionaryForEachNode, NodeList)
    m_outagesimulator = ""
    RunNumber = 0
    OutageSimulator_LineFromSubstationToFacilityMeter, RunNumber, outage_start_timesteps_checked = PrepareInputsForOutageSimulator(Multinode_Inputs, OutageLength_TimeSteps_Input, NumberOfOutagesToTest)
    RunsTested = 0
    outage_survival_results = -1 * ones(RunNumber)
    SuccessfullySolved = 0
    TimeStepsNotSolved = []
    outage_data_for_plotting = Dict([])
    pm = ""
    data_math_mn = ""

    if Multinode_Inputs.allow_dropped_load
        dropped_load_results = Array{Any}(undef, RunNumber)
        dropped_load_results_summary = ""
    else
        dropped_load_results_summary = "N/A"
    end

    # Cache PMD information across outage iterations (because the network, REopt node generator mapping, and phase mapping are the same for all of the outages)
    cached_pmd_info = nothing

    for x in 1:RunNumber
        print("\n Outage Simulation Run # "*string(x)*"  of  "*string(RunNumber)*" runs")
        RunsTested = RunsTested + 1
        i = outage_start_timesteps_checked[x]
        TotalTimeSteps = 8760*Multinode_Inputs.time_steps_per_hour   
        time_results = Dict()
        if Multinode_Inputs.model_type == "PowerModelsDistribution"
            m_outagesimulator = "" # empty the m_outagesimulator variable
            pm, data_math_mn, data_eng = Create_PMD_Model_For_REopt_Integration(Multinode_Inputs, OutageLength_TimeSteps_Input, time_results; combined_REopt_inputs = REopt_inputs_combined, outage_simulator = true)
            m_outagesimulator = pm.model # TODO: Confirm that when make changes to pm.model again in the function, that that version of pm.model has the additional constraints defined below for m_outagesimulator
        #elseif
            # Add other options if additional model_types are added
        else
            throw(@error("And invalid model_type was provided."))
        end
        
        for n in NodeList
            TimeSteps = OutageLength_TimeSteps_Input
            AddVariablesOutageSimulator(Multinode_Inputs, pm.model, TimeSteps, DataDictionaryForEachNode, n)           
            AddConstraintsOutageSimulator(Multinode_Inputs, pm.model, TimeSteps, DataDictionaryForEachNode, OutageLength_TimeSteps_Input, n, i)
        end 
                
        if Multinode_Inputs.model_type == "PowerModelsDistribution"
            if cached_pmd_info === nothing
                REopt_nodes_for_cache = REopt.GenerateREoptNodesList(Multinode_Inputs)
                cached_pmd_info = generate_PMD_information(Multinode_Inputs, REopt_nodes_for_cache, REopt_inputs_combined, data_math_mn)
            end
            Connect_To_PMD_Model(pm, Multinode_Inputs, data_math_mn, OutageLength_TimeSteps_Input, LineInfo_PMD, REopt_inputs_combined; cached_pmd_info=cached_pmd_info)
        end

        if Multinode_Inputs.model_line_upgrades
            AddConstraintsFromLineUpgrades(pm, OutageLength_TimeSteps_Input, LineInfo_PMD, line_upgrade_options_each_line, line_upgrade_results)
        end

        if Multinode_Inputs.model_transformer_upgrades
            AddConstraintsFromTransformerUpgrades() # TODO: finish this function once transformer upgrades are implemented in the code
        end

        if !(Multinode_Inputs.allow_dropped_load)
            @objective(pm.model, FEASIBILITY_SENSE, 0)
        elseif Multinode_Inputs.allow_dropped_load
            @objective(pm.model, Max, (sum(sum(pm.model[Symbol("dvLoadMetMultiplier_"*n)] for n in NodeList)))) # If allowing dropped load, the objective is to maximize the non-dropped load
        else
            throw(@error("The input for allow_dropped_load is invalid. It must be true or false."))
        end

        PrepareOptimizer(pm, Multinode_Inputs)
        results = PowerModelsDistribution.optimize_model!(pm) 
        TerminationStatus = string(results["termination_status"])
                
        outage_survival_results[x], SuccessfullySolved, TimeStepsNotSolved = InterpretResult(TimeStepsNotSolved, TerminationStatus, SuccessfullySolved, Multinode_Inputs, x, i, pm.model, DataDictionaryForEachNode, OutageLength_TimeSteps_Input, TimeStamp, TotalTimeSteps, NodeList)
        print("\n The result from run #"*string(RunsTested)*" is: "*TerminationStatus*". Outages survived so far: "*string(SuccessfullySolved)*", Outages tested so far: "*string(RunsTested))
               
        if Multinode_Inputs.generate_dictionary_for_plotting && (SuccessfullySolved <= Multinode_Inputs.number_of_plots_from_outage_simulator)
            temp_dict = Dict([])
            temp_dict["model"] = pm.model
            temp_dict["x"] = x
            temp_dict["i"] = i
            temp_dict["TotalTimeSteps"] = TotalTimeSteps
            temp_dict["NodeList"] = NodeList
            outage_data_for_plotting[SuccessfullySolved] = deepcopy(temp_dict)
        end

        if Multinode_Inputs.allow_dropped_load && (TerminationStatus == "OPTIMAL")
            dropped_load_results[x] = ProcessDroppedLoadResults(Multinode_Inputs, pm.model, i, DataDictionaryForEachNode, OutageLength_TimeSteps_Input, NodeList, RunsTested)
        elseif Multinode_Inputs.allow_dropped_load && (TerminationStatus != "OPTIMAL")
            dropped_load_results[x] = Dict(["load_met_fraction" => 0.0, "Solved"=> "no"])
        end
    
    end

    PercentOfOutagesSurvived = DisplayResultsSummary(SuccessfullySolved, RunNumber, OutageLength_TimeSteps_Input)
    
    if Multinode_Inputs.allow_dropped_load
        dropped_load_results_summary = SummarizeDroppedLoadResults(Multinode_Inputs, dropped_load_results)
    end
        
    return pm, OutageLength_TimeSteps_Input, SuccessfullySolved, TimeStepsNotSolved, RunNumber, PercentOfOutagesSurvived, m_outagesimulator, outage_survival_results, outage_start_timesteps_checked, dropped_load_results_summary, outage_data_for_plotting
end 


function ProcessDroppedLoadResults(Multinode_Inputs, model, i, DataDictionaryForEachNode, OutageLength_TimeSteps_Input, NodeList, RunsTested)

    dropped_load_dictionary = Dict([])

    load_met_multiplier_results = Dict([])
    for n in NodeList
        load_met_multiplier_results[n] = value.(model[Symbol("dvLoadMetMultiplier_"*n)])
    end

    total_load = zeros(OutageLength_TimeSteps_Input)
    load_met = zeros(OutageLength_TimeSteps_Input)

    for ts in collect(1:OutageLength_TimeSteps_Input)
        total_load[ts] = sum((DataDictionaryForEachNode[n]["loads_kw"][i:(i+OutageLength_TimeSteps_Input-1)])[ts] for n in NodeList)
        load_met[ts] = sum( (value.(model[Symbol("dvLoadMetMultiplier_"*n)][ts]) * (DataDictionaryForEachNode[n]["loads_kw"][i:(i+OutageLength_TimeSteps_Input-1)])[ts]) for n in NodeList)
    end

    total_load_summed = sum(total_load)
    load_met_summed = sum(load_met)
    load_met_fraction = round((load_met_summed/total_load_summed), digits=4) 

    dropped_load_dictionary = Dict(["RunNumber" => RunsTested,
                                    "solved" => "yes", 
                                    "total_load_summed"=> total_load_summed, 
                                    "load_met_summed"=>load_met_summed, 
                                    "load_met_fraction"=> load_met_fraction, 
                                    "load_met_multiplier_results"=>load_met_multiplier_results])

    return dropped_load_dictionary
end


function SummarizeDroppedLoadResults(Multinode_Inputs, dropped_load_results)

    load_met_fraction_list = []
    minimum_value = "N/A"
    average_value = "N/A"
    maximum_value = "N/A"
    
    for i in collect(1:length(dropped_load_results))
        push!(load_met_fraction_list, dropped_load_results[i]["load_met_fraction"])
    end
    if Multinode_Inputs.display_information_during_modeling_run
        print("\n The load met fraction list is: ")
        print(load_met_fraction_list)
    end

    minimum_value = minimum(load_met_fraction_list)
    average_value = mean(load_met_fraction_list)
    maximum_value = maximum(load_met_fraction_list)

    summary = Dict(["minimum_load_met_fraction" => minimum_value, 
                    "average_load_met_fraction" => average_value,
                    "maximum_load_met_fraction" => maximum_value, 
                    "results_by_outage_simulation" => dropped_load_results])

    return summary
end


function AddVariablesOutageSimulator(Multinode_Inputs, m_outagesimulator, TimeSteps, DataDictionaryForEachNode, n)

    Batterykw = DataDictionaryForEachNode[n]["Battery_kw"]
    
    dv = "dvPVToLoad_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0.0)
    dv = "dvBatToLoad_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0.0)
    dv = "dvBatToLoadWithEfficiency_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0.0)
    dv = "dvGenToLoad_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0.0)

    dv = "dvPVToBat_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0.0, upper_bound = Batterykw)

    dv = "dvGridToBat_"*n 
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0, upper_bound = Batterykw)
    dv = "dvGridToLoad_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0)
    dv = "dvGridPurchase_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0)    
    
    dv = "FuelUsage_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0)
    dv = "TotalFuelUsage_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, base_name = dv, lower_bound = 0)
    
    dv = "BatteryCharge_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv) 
    dv = "SumOfBatFlows_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv)

    # Binary used to prevent battery from charging and discharging at the same time
    dv = "Binary_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, Bin)

    dv = "TotalExport_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name=dv) 
    
    dv = "dvPVToGrid_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0)
    dv = "dvBatToGrid_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0)
    dv = "dvBatToGridWithEfficiency_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0) 
    dv = "dvGenToGrid_"*n
    m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv, lower_bound = 0)

    if Multinode_Inputs.allow_dropped_load
        dv = "dvLoadMetMultiplier_"*n
        m_outagesimulator[Symbol(dv)] = @variable(m_outagesimulator, [1:TimeSteps], base_name = dv) #, lower_bound = 0, upper_bound = 1)
    end

end


function AddConstraintsOutageSimulator(Multinode_Inputs, m_outagesimulator, TimeSteps, DataDictionaryForEachNode, OutageLength_TimeSteps_Input, n, i)

    time_steps_per_hour = Multinode_Inputs.time_steps_per_hour

    GenPowerRating = DataDictionaryForEachNode[n]["GeneratorSize"]  
    GalPerkwh = Multinode_Inputs.outage_simulator_generator_gallons_per_kwh 
    
    BatteryChargeStart = DataDictionaryForEachNode[n]["Battery_charge_kwh"][i]
    Batterykw = DataDictionaryForEachNode[n]["Battery_kw"]
    Batterykwh = DataDictionaryForEachNode[n]["Battery_kwh"]
    BatteryRoundTripEfficiencyFraction = DataDictionaryForEachNode[n]["battery_roundtrip_efficiency"]

    PVProductionProfile = DataDictionaryForEachNode[n]["PVproductionprofile"]

    # Total power export:    
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], (m_outagesimulator[Symbol("TotalExport_"*n)] .== m_outagesimulator[Symbol("dvPVToGrid_"*n)][ts] + 
                                                                                            m_outagesimulator[Symbol("dvBatToGridWithEfficiency_"*n)][ts] + 
                                                                                            m_outagesimulator[Symbol("dvGenToGrid_"*n)][ts]))

    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("dvBatToLoadWithEfficiency_"*n)][ts] .== m_outagesimulator[Symbol("dvBatToLoad_"*n)][ts] * BatteryRoundTripEfficiencyFraction)
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("dvBatToGridWithEfficiency_"*n)][ts] .== m_outagesimulator[Symbol("dvBatToGrid_"*n)][ts] * BatteryRoundTripEfficiencyFraction)

    # Total PV power constraint:
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("dvPVToGrid_"*n)][ts] + 
                                                        m_outagesimulator[Symbol("dvPVToBat_"*n)][ts] + 
                                                        m_outagesimulator[Symbol("dvPVToLoad_"*n)][ts] .<= PVProductionProfile[i .+ ts .- 1] )
        
    # Grid power import to each node:           
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("dvGridPurchase_"*n)] .== 
                                                        m_outagesimulator[Symbol("dvGridToLoad_"*n)][ts] + m_outagesimulator[Symbol("dvGridToBat_"*n)][ts] )
    
    # Generator constraints:            
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("dvGenToGrid_"*n)][ts] + 
                                                        m_outagesimulator[Symbol("dvGenToLoad_"*n)][ts] .<= 
                                                        GenPowerRating ) 
    @constraint(m_outagesimulator, m_outagesimulator[Symbol("TotalFuelUsage_"*n)] .== sum(m_outagesimulator[Symbol("FuelUsage_"*n)]) )
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("FuelUsage_"*n)][ts] .== (m_outagesimulator[Symbol("dvGenToGrid_"*n)][ts] + m_outagesimulator[Symbol("dvGenToLoad_"*n)][ts])*(1/time_steps_per_hour)*GalPerkwh)
    @constraint(m_outagesimulator, sum(m_outagesimulator[Symbol("FuelUsage_"*n)]) .<= DataDictionaryForEachNode[n]["Fuel_tank_capacity_gal"] )
      
    # Battery constraints:
    @constraint(m_outagesimulator, m_outagesimulator[Symbol("BatteryCharge_"*n)][1] == BatteryChargeStart)
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]],  m_outagesimulator[Symbol("SumOfBatFlows_"*n)][ts] .== 
                                                        m_outagesimulator[Symbol("dvBatToLoad_"*n)][ts] + 
                                                        m_outagesimulator[Symbol("dvBatToGrid_"*n)][ts]  - 
                                                        m_outagesimulator[Symbol("dvPVToBat_"*n)][ts] - 
                                                        m_outagesimulator[Symbol("dvGridToBat_"*n)][ts])
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("SumOfBatFlows_"*n)][ts] .<= Batterykw)
    
    for t in 1:(TimeSteps-1)
        @constraint(m_outagesimulator, m_outagesimulator[Symbol("BatteryCharge_"*n)][t+1] ==  m_outagesimulator[Symbol("BatteryCharge_"*n)][t] - 
                                                                                                (((m_outagesimulator[Symbol("SumOfBatFlows_"*n)][t]))/time_steps_per_hour) )
    end 

    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("BatteryCharge_"*n)][ts] .<= Batterykwh )
    @constraint(m_outagesimulator, [ts in [1:TimeSteps]], m_outagesimulator[Symbol("BatteryCharge_"*n)][ts] .>= 0)
    
    
    if (string(Multinode_Inputs.optimizer) == "Xpress.Optimizer") || (string(Multinode_Inputs.optimizer) == "Gurobi.Optimizer") # only apply the indicator constraints if using a solver that is compatible with indicator constraints
        # Use a binary to prohibit charging and discharging at the same time.
                
        binary_var      = m_outagesimulator[Symbol("Binary_"*n)]
        grid_to_bat_var = m_outagesimulator[Symbol("dvGridToBat_"*n)]
        pv_to_bat_var   = m_outagesimulator[Symbol("dvPVToBat_"*n)]
        bat_to_load_var = m_outagesimulator[Symbol("dvBatToLoad_"*n)]
        bat_to_grid_var = m_outagesimulator[Symbol("dvBatToGrid_"*n)]
        @constraint(m_outagesimulator, [ts=1:TimeSteps],  binary_var[ts] => {grid_to_bat_var[ts] == 0.0})
        @constraint(m_outagesimulator, [ts=1:TimeSteps],  binary_var[ts] => {pv_to_bat_var[ts]   == 0.0})
        @constraint(m_outagesimulator, [ts=1:TimeSteps], !binary_var[ts] => {bat_to_load_var[ts] == 0.0})
        @constraint(m_outagesimulator, [ts=1:TimeSteps], !binary_var[ts] => {bat_to_grid_var[ts] == 0.0})
    else
        @warn "The battery may charge and discharge at the same time in the outage simulator because the solver is not compatible with indicator constraints."
    end
    #print("\n OutageLength_TimeSteps_Input are: $(OutageLength_TimeSteps_Input)")
    #print("\n Timesteps are: $(TimeSteps)")
    # Constraints for meeting the electric load at each node
    if !(Multinode_Inputs.allow_dropped_load)
        #print("\n Adding constraints for not allowing dropped load")
        @constraint(m_outagesimulator, [ts in [1:OutageLength_TimeSteps_Input]], m_outagesimulator[Symbol("dvPVToLoad_"*n)][ts] + 
                                    m_outagesimulator[Symbol("dvGridToLoad_"*n)][ts] +
                                    m_outagesimulator[Symbol("dvBatToLoadWithEfficiency_"*n)][ts] + 
                                    m_outagesimulator[Symbol("dvGenToLoad_"*n)][ts] .== (DataDictionaryForEachNode[n]["loads_kw"][i:(i+OutageLength_TimeSteps_Input-1)])[ts])

    elseif Multinode_Inputs.allow_dropped_load
        @info("Allowing dropped load in the outage simulator")
        @constraint(m_outagesimulator, [ts in [1:OutageLength_TimeSteps_Input]], m_outagesimulator[Symbol("dvLoadMetMultiplier_"*n)][ts] .>= 0.0) 
        @constraint(m_outagesimulator, [ts in [1:OutageLength_TimeSteps_Input]], m_outagesimulator[Symbol("dvLoadMetMultiplier_"*n)][ts] .<= 1.0) 
        @constraint(m_outagesimulator, [ts in [1:OutageLength_TimeSteps_Input]], m_outagesimulator[Symbol("dvPVToLoad_"*n)][ts] + 
                                    m_outagesimulator[Symbol("dvGridToLoad_"*n)][ts] +
                                    m_outagesimulator[Symbol("dvBatToLoadWithEfficiency_"*n)][ts] + 
                                    m_outagesimulator[Symbol("dvGenToLoad_"*n)][ts] .== (DataDictionaryForEachNode[n]["loads_kw"][i:(i+OutageLength_TimeSteps_Input-1)][ts]) .* m_outagesimulator[Symbol("dvLoadMetMultiplier_"*n)][ts] )

    end                                                
end


function Connect_To_PMD_Model(pm, Multinode_Inputs, data_math_mn, OutageLength_TimeSteps_Input, LineInfo_PMD, REopt_inputs_combined;
                              cached_pmd_info=nothing)
    # Link the power export decision variables to the PMD model
    outage_timesteps = collect(1:OutageLength_TimeSteps_Input)

    REopt_nodes = REopt.GenerateREoptNodesList(Multinode_Inputs)

    # Reuse cached generate_PMD_information results if available
    if cached_pmd_info === nothing
        gen_name2ind, load_phase_dictionary, gen_ind_e_to_REopt_node = generate_PMD_information(Multinode_Inputs, REopt_nodes, REopt_inputs_combined, data_math_mn)
    else
        gen_name2ind, load_phase_dictionary, gen_ind_e_to_REopt_node = cached_pmd_info
    end


    #gen_name2ind = Dict(gen["name"] => gen["index"] for (_,gen) in data_math_mn["nw"]["1"]["gen"])
    
    if Multinode_Inputs.number_of_phases == 1
        REopt_gen_ind_e = [gen_name2ind["REopt_gen_$e"] for e in REopt_nodes]
    
    elseif Multinode_Inputs.number_of_phases in [2,3]

        REopt_gen_ind_e = []
        if Multinode_Inputs.display_information_during_modeling_run 
            print("\n Gen name to index, outage simulator: ")
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
                           
    for e in REopt_gen_ind_e  #Note: the REopt_gen_ind_e does not contain the facility meter
        
        number_of_phases_at_load = ""
        number_of_phases_at_load = length(load_phase_dictionary[gen_ind_e_to_REopt_node[e]])

        JuMP.@constraint(pm.model, [k in outage_timesteps],  
                            PowerModelsDistribution.var(pm, k, :pg, e).data[1] == (1/number_of_phases_at_load) * (pm.model[Symbol("TotalExport_"*string(gen_ind_e_to_REopt_node[e]))][k] - pm.model[Symbol("dvGridPurchase_"*string(gen_ind_e_to_REopt_node[e]))][k])   # negative power "generation" is a load
        )
        # TODO: add reactive power to the REopt nodes
        if Multinode_Inputs.model_subtype != "NFAUPowerModel"
            JuMP.@constraint(pm.model, [k in outage_timesteps],
                                PowerModelsDistribution.var(pm, k, :qg, e).data[1]  == 0.0 #(1/number_of_phases_at_load) * (m[Symbol("TotalExport_"*string(gen_ind_e_to_REopt_node[e]))][k] - m[Symbol("dvGridPurchase_"*string(gen_ind_e_to_REopt_node[e]))][k]) 
            )
        end
    end
    
    # Prevent power from entering the multinode to simulate a power outage.
    substation_line_index = LineInfo_PMD[lowercase(Multinode_Inputs.substation_line)]["index"]
    timestep_for_network_data = 1 # collect the network configuration information from timestep 1, which assumes that the network is not changing (fair to assume with the REopt integration)
    branch_sub = PowerModelsDistribution.ref(pm, timestep_for_network_data, :branch, substation_line_index)
    f_bus = branch_sub["f_bus"]
    t_bus = branch_sub["t_bus"]
    f_connections = branch_sub["f_connections"]
    t_connections = branch_sub["t_connections"]
    f_idx = (substation_line_index, f_bus, t_bus)
    t_idx = (substation_line_index, t_bus, f_bus)

    for PMD_time_step in outage_timesteps
        p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
        p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]

        if Multinode_Inputs.model_subtype != "NFAUPowerModel"
            q_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :q, f_idx)[c] for c in f_connections]
            q_to = [PowerModelsDistribution.var(pm, PMD_time_step, :q, t_idx)[c] for c in t_connections]
        end

        JuMP.@constraint(pm.model, [phase in f_connections], p_fr[phase] .== 0)  # The _fr and _to variables are just indicating power flow in either direction on the line. In PMD, there is a constraint that requires  p_to = -p_fr 
        JuMP.@constraint(pm.model, [phase in t_connections], p_to[phase] .== 0)  # TODO test removing the "fr" constraints here in order to reduce the # of constraints in the model
        if Multinode_Inputs.model_subtype != "NFAUPowerModel"
            if Multinode_Inputs.number_of_phases == 1        
                JuMP.@constraint(pm.model, [phase in f_connections], q_fr[phase] .== 0)
                JuMP.@constraint(pm.model, [phase in t_connections], q_to[phase] .== 0)
            else
                JuMP.@constraint(pm.model, [phase in f_connections], -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar .<= q_fr[phase] .<= Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar)
                JuMP.@constraint(pm.model, [phase in t_connections], -Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar .<= q_to[phase] .<= Multinode_Inputs.external_reactive_power_support_per_phase_maximum_kvar)    
            end
        end
    end
end


function AddConstraintsFromLineUpgrades(pm, OutageLength_TimeSteps_Input, LineInfo, line_upgrade_options_each_line, line_upgrade_results)
    
    outage_timesteps = collect(1:OutageLength_TimeSteps_Input)

    max_amps_by_line = Dict(line_upgrade_results.Line[r] => line_upgrade_results[r, :MaximumRatedAmps]
                            for r in 1:nrow(line_upgrade_results))

    for line in keys(line_upgrade_options_each_line)

        max_amps_line = max_amps_by_line[line]
        voltage_kv    = line_upgrade_options_each_line[line]["voltage_kv"]
        power_limit   = max_amps_line * voltage_kv 

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

        for PMD_time_step in outage_timesteps            
            p_fr = [PowerModelsDistribution.var(pm, PMD_time_step, :p, f_idx)[c] for c in f_connections]
            p_to = [PowerModelsDistribution.var(pm, PMD_time_step, :p, t_idx)[c] for c in t_connections]
            
            for phase in f_connections
                @constraint(pm.model, p_fr[phase] <=  power_limit)
                @constraint(pm.model, p_fr[phase] >= -power_limit)
            end

            for phase in t_connections
                @constraint(pm.model, p_to[phase] <=  power_limit) 
                @constraint(pm.model, p_to[phase] >= -power_limit) 
            end
        end
    end
end


function AddConstraintsFromTransformerUpgrades()
    # TODO: finish this function

end


function GenerateInputsForOutageSimulator(Multinode_Inputs, REopt_results)
    results = REopt_results
                        
    TimeSteps = collect(1:(8760*Multinode_Inputs.time_steps_per_hour))
    NodeList = string.(GenerateREoptNodesList(Multinode_Inputs))
    
    # Define the critical loads
    critical_loads_kw = Dict([])
    if Multinode_Inputs.critical_load_method == "Fraction"
        for i in 1:length(NodeList)
            if results[NodeList[i]]["ElectricLoad"]["annual_calculated_kwh"] > 1
                critical_loads_kw[NodeList[i]] = Multinode_Inputs.critical_load_fraction[NodeList[i]] * Multinode_Inputs.load_profiles_for_outage_sim_if_using_the_fraction_method[NodeList[i]]
            else
                critical_loads_kw[NodeList[i]] = zeros(8760*Multinode_Inputs.time_steps_per_hour)
            end
        end
    elseif Multinode_Inputs.critical_load_method == "TimeSeries"
        for i in 1:length(NodeList)
            if results[NodeList[i]]["ElectricLoad"]["annual_calculated_kwh"] > 1
                critical_loads_kw[NodeList[i]] = Multinode_Inputs.critical_load_timeseries[NodeList[i]]
            else
                critical_loads_kw[NodeList[i]] = zeros(8760*Multinode_Inputs.time_steps_per_hour)
            end
        end
    else
        throw(@error("Invalid method for generating a critical load was provided"))
    end

    # Initiate the dictionary with data from the first node
    if "ElectricStorage" in keys(results[NodeList[1]])
        if length(results[NodeList[1]]["ElectricStorage"]["soc_series_fraction"]) > 0
            BatteryChargekwh = results[NodeList[1]]["ElectricStorage"]["soc_series_fraction"]*results[NodeList[1]]["ElectricStorage"]["size_kwh"]
            Batterykw = results[NodeList[1]]["ElectricStorage"]["size_kw"]
            Batterykwh = results[NodeList[1]]["ElectricStorage"]["size_kwh"]
        else
            BatteryChargekwh = 0*ones(length(TimeSteps))
            Batterykw = 0
            Batterykwh = 0
        end 
    else
        BatteryChargekwh = 0*ones(length(TimeSteps))
        Batterykw = 0
        Batterykwh = 0
    end 

    if "PV" in keys(results[NodeList[1]])
        if results[NodeList[1]]["PV"]["size_kw"] > 0
            PVProductionProfile_results = round.(((results[NodeList[1]]["PV"]["production_factor_series"])*results[NodeList[1]]["PV"]["size_kw"]), digits = 3)
        else
            PVProductionProfile_results = zeros(length(TimeSteps))
        end
    else
        PVProductionProfile_results = zeros(length(TimeSteps))
    end

    if "Generator" in keys(results[NodeList[1]])
        GeneratorSize_results = results[NodeList[1]]["Generator"]["size_kw"]
        if NodeList[1] in keys(Multinode_Inputs.generator_fuel_gallon_available)
            generator_fuel_gallon_available = Multinode_Inputs.generator_fuel_gallon_available[NodeList[1]]
        else
            generator_fuel_gallon_available = 0
        end
    else
        GeneratorSize_results = 0
        generator_fuel_gallon_available = 0
    end

    # Enter data into the dictionary
    DataDictionaryForEachNode = Dict([
        (NodeList[1],Dict([
            ("loads_kw", critical_loads_kw[NodeList[1]]), 
            ("PVproductionprofile",  PVProductionProfile_results ),
            ("GeneratorSize", GeneratorSize_results),
            ("Battery_charge_kwh",  BatteryChargekwh),
            ("Battery_kw", Batterykw),
            ("Battery_kwh", Batterykwh),
            ("Fuel_tank_capacity_gal", generator_fuel_gallon_available),
            ("battery_roundtrip_efficiency",0.95)
            ])),
        ])

    # Add additional dictionaries to the main dictionary for the additional nodes, depending on how many nodes there are
    for i in 2:length(NodeList)
        if "ElectricStorage" in keys(results[NodeList[i]]) 
            if length(results[NodeList[i]]["ElectricStorage"]["soc_series_fraction"]) > 0
                BatteryChargekwh_B = results[NodeList[i]]["ElectricStorage"]["soc_series_fraction"]*results[NodeList[i]]["ElectricStorage"]["size_kwh"]
                Batterykw_B = results[NodeList[i]]["ElectricStorage"]["size_kw"]
                Batterykwh_B = results[NodeList[i]]["ElectricStorage"]["size_kwh"]
            else
                BatteryChargekwh_B = 0*ones(length(TimeSteps))
                Batterykw_B = 0
                Batterykwh_B = 0  
            end      
        else 
            BatteryChargekwh_B = 0*ones(length(TimeSteps))
            Batterykw_B = 0
            Batterykwh_B = 0
        end
        if "PV" in keys(results[NodeList[i]])
            if results[NodeList[i]]["PV"]["size_kw"] > 0
                PVProductionProfile_results_B = round.(((results[NodeList[i]]["PV"]["production_factor_series"])*results[NodeList[i]]["PV"]["size_kw"]), digits = 3)
            else
                PVProductionProfile_results_B = zeros(length(TimeSteps))
            end
        else
            PVProductionProfile_results_B = zeros(length(TimeSteps))
        end
        
        if "Generator" in keys(results[NodeList[i]])
            GeneratorSize_results_B = results[NodeList[i]]["Generator"]["size_kw"]
            if NodeList[i] in keys(Multinode_Inputs.generator_fuel_gallon_available)
                generator_fuel_gallon_available = Multinode_Inputs.generator_fuel_gallon_available[NodeList[i]]
            else
                generator_fuel_gallon_available = 0
            end 
        else
            GeneratorSize_results_B = 0
            generator_fuel_gallon_available = 0
        end 
        DictionaryToAdd = Dict([
            (NodeList[i],Dict([
                ("loads_kw", critical_loads_kw[NodeList[i]]),
                ("PVproductionprofile", PVProductionProfile_results_B),
                ("GeneratorSize", GeneratorSize_results_B),
                ("Battery_charge_kwh", BatteryChargekwh_B),
                ("Battery_kw", Batterykw_B),
                ("Battery_kwh", Batterykwh_B),
                ("Fuel_tank_capacity_gal", generator_fuel_gallon_available),
                ("battery_roundtrip_efficiency",0.95)
                ])),
        ]) 
        merge!(DataDictionaryForEachNode, DictionaryToAdd)
    end 
return DataDictionaryForEachNode
end


function PrepareInputsForOutageSimulator(Multinode_Inputs, OutageLength_TimeSteps_Input, NumberOfOutagesToTest)
    randomly_ordered_timesteps = RandomlyOrderedTimesteps() 
    if Multinode_Inputs.time_steps_per_hour == 1
        outage_start_timesteps = randomly_ordered_timesteps["8760"]
    elseif Multinode_Inputs.time_steps_per_hour == 2
        outage_start_timesteps = randomly_ordered_timesteps["17540"]
    elseif Multinode_Inputs.time_steps_per_hour == 4
        outage_start_timesteps = randomly_ordered_timesteps["35040"]
    else
        throw(@error("The defined time steps per hour are currently not compatible with the outage simulator"))
    end
    
    NumberOfTimeSteps = Multinode_Inputs.time_steps_per_hour * 8760
    RunNumber_limit = NumberOfTimeSteps - (OutageLength_TimeSteps_Input+1) 
    outage_start_timesteps_filtered = outage_start_timesteps[outage_start_timesteps .< RunNumber_limit]

    if RunNumber_limit < NumberOfOutagesToTest
        @warn "The number of possible outages to test is less than the number of outages requested by the user. $(RunNumber) will be evaluated instead of $(NumberOfOutagesToTest)."
        RunNumber = RunNumber_limit
    else
        RunNumber = NumberOfOutagesToTest
    end

    outage_start_timesteps_checked = outage_start_timesteps_filtered[1:RunNumber]
 
    if Multinode_Inputs.model_type == "PowerModelsDistribution" 
        OutageSimulator_LineFromSubstationToFacilityMeter = lowercase(Multinode_Inputs.substation_line) #substation_node*"-"*Multinode_Inputs.facilitymeter_node
    end

    return OutageSimulator_LineFromSubstationToFacilityMeter, RunNumber, outage_start_timesteps_checked
end
  

function InterpretResult(TimeStepsNotSolved, TerminationStatus, SuccessfullySolved, Multinode_Inputs, x, i, m_outagesimulator, DataDictionaryForEachNode, OutageLength_TimeSteps_Input, TimeStamp, TotalTimeSteps, NodeList)
    if TerminationStatus == "OPTIMAL"
        SuccessfullySolved = SuccessfullySolved + 1
        outage_survival_result = 1 # a value of 1 indicates that the outage was survived
        
        # TODO: calculate the amount of generator fuel that remains, for example: RemainingFuel = value.(m_outagesimulator[Symbol("FuelLeft_3")]) + value.(m_outagesimulator[Symbol("FuelLeft_10")])
                
    else
        push!(TimeStepsNotSolved, i)
        outage_survival_result = 0 # a value of 0 indicates that the outage was not survived
    end 

    return outage_survival_result, SuccessfullySolved, TimeStepsNotSolved
end


function PrepareOptimizer(pm, Multinode_Inputs)
    set_optimizer(pm.model, Multinode_Inputs.optimizer) 
    
    if string(Multinode_Inputs.optimizer) == "Xpress.Optimizer"
        set_optimizer_attribute(pm.model, "MIPRELSTOP", Multinode_Inputs.optimizer_tolerance)
        set_optimizer_attribute(pm.model, "OUTPUTLOG", Multinode_Inputs.log_solver_output_to_console ? 1 : 0)
    elseif string(Multinode_Inputs.optimizer) == "Gurobi.Optimizer"
        set_optimizer_attribute(pm.model, "MIPGap", Multinode_Inputs.optimizer_tolerance)
        set_optimizer_attribute(pm.model, "OutputFlag", Multinode_Inputs.log_solver_output_to_console ? 1 : 0)  
        set_optimizer_attribute(pm.model, "LogToConsole", Multinode_Inputs.log_solver_output_to_console ? 1 : 0)
    elseif string(Multinode_Inputs.optimizer) == "HiGHS.Optimizer"
        set_optimizer_attribute(pm.model, "mip_rel_gap", Multinode_Inputs.optimizer_tolerance)
        set_optimizer_attribute(pm.model, "output_flag", false)
        set_optimizer_attribute(pm.model, "log_to_console", false)
    else
        @info "The solver's default tolerance and log settings are being used for the optimization"
    end

end


function DisplayResultsSummary(SuccessfullySolved, RunNumber, OutageLength_TimeSteps_Input)
    print("\n --- Summary of results ---")
    PercentOfOutagesSurvived = 100*(SuccessfullySolved/RunNumber)
    print("\n The length of outage tested is: "*string(OutageLength_TimeSteps_Input)*" time steps")
    print("\n The number of outages survived is: "*string(SuccessfullySolved)*"  of  "*string(RunNumber)*" runs")
    print("\n Percent of outages survived: "*string(round(PercentOfOutagesSurvived, digits = 2))*" % \n")
    return PercentOfOutagesSurvived
end


function DetermineNodesWithPV(DataDictionaryForEachNode, NodeList)
    # This function determines which nodes have PV
    NodesWithPV = []
    for p in NodeList 
        if maximum(DataDictionaryForEachNode[p]["PVproductionprofile"]) > 0
            push!(NodesWithPV, p)
        end
    end 
    return NodesWithPV
end


function RandomlyOrderedTimesteps() 
    path = joinpath(dirname(pathof(REopt)))
    path = replace(path, "\\" => "/")
    randomly_ordered_timesteps = JSON.parsefile(path*"/multinode/random_vectors_data.json")
    return randomly_ordered_timesteps
end


function CreateRandomVectorOrder(filepath, vector1, vector2, vector3)
    # This function saves a random ordering of vector data for the outage simulator
        #=
        # Use this code to create inputs into the function:
        vector_8760_ordered = collect(1:8760)
        vector_8760_randomly_unordered = Random.shuffle(vector_8760_ordered)
        
        vector_17540_ordered = collect(1:17540)
        vector_17540_randomly_unordered = Random.shuffle(vector_17540_ordered)
        
        vector_35040_ordered = collect(1:35040)
        vector_35040_randomly_unordered = Random.shuffle(vector_35040_ordered)

        CreateRandomVectorOrder(filepath, vector_8760_randomly_unordered, vector_17540_randomly_unordered, vector_35040_randomly_unordered
        =#

    vector_8760_randomly_unordered = vector1
    vector_17540_randomly_unordered = vector2
    vector_35040_randomly_unordered = vector3

    data = Dict(["8760" => vector_8760_randomly_unordered,
                 "17540" => vector_17540_randomly_unordered,
                 "35040" => vector_35040_randomly_unordered
                ])
    
    open(filepath*"/random_vectors_data.json", "w") do x
        JSON.print(x, data)
    end

    # Visualize some distributions of the data
    lengths = [100,250,500,1000]
    
    for length in lengths

        selected_values = vector_8760_randomly_unordered[1:length]
        time_of_day = zeros(length)
        day_of_year = zeros(length)
        for x in collect(1:length)
            time_of_day[x] = selected_values[x] % 24
            day_of_year[x] = ceil(selected_values[x] / 24)
        end
        Plots.histogram(time_of_day, bins=range(0,24, length=25))
        Plots.xlabel!("Hour of Day")
        Plots.ylabel!("Occurances")
        display(Plots.title!("Time of day distribution, $(length) tests"))
        Plots.histogram(day_of_year, bins=0:7:371)
        Plots.xlabel!("Day of Year")
        Plots.ylabel!("Occurances")
        display(Plots.title!("Day of year distribution, $(length) tests"))
    end
end


