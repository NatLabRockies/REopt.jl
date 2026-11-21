# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
 
"""
`multinode` is an optional input with the following keys and default values:

    folder_location::String="",
    bus_coordinates::String="",  # Location of the csv document with the bus coordinates
    PMD_network_input::Any,
    multinode_type::String="BehindTheMeter",  # Options: "BehindTheMeter", "CommunityDistrict", or "Offgrid"
    model_type::String="PowerModelsDistribution",  #Options: "PowerModelsDistribution",
    model_subtype::String="LPUBFDiagPowerModel", # Options: "LPUBFDiagPowerModel", "ACPUPowerModel"
    run_BAU_case::Bool=true,
    optimizer::Any, # Such as HiGHS.Optimizer
    optimizer_tolerance::Float64=0.001, # Only works for Xpress, HiGHS, and Gurobi
    log_solver_output_to_console::Bool=true, # Log the output from the solver to the console
    PMD_time_steps::Any=collect(1:24), # By default, apply the PMD model to the first 24 timesteps of the model
    apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD::Bool=true,
    REopt_inputs_list::Array=[],
    
    number_of_phases::Real=1,
    bus_phase_voltage_lower_bound_per_unit::Float64=0.95,
    bus_phase_voltage_upper_bound_per_unit::Float64=1.05,
    bus_neutral_voltage_upper_bound_per_unit::Float64=0.1, 
    facilitymeter_node::String="",
    substation_node::String="",
    substation_line::String="",
    allow_export_beyond_substation::Bool=false,
    substation_export_limit::Real=0,
    substation_import_limit::Real=Inf, # The maximum total power imported through the substation line (kW). The default of Inf means that there is no limit
    external_reactive_power_support_per_phase_maximum_kvar::Real=1000000, # Because multi-node does not model reactive power, but reactive power may be needed for the power systems modeling, this value enables reactive power to flow from the substation to all parts of the network, regardless of if there is a grid outage or a switch is open

    model_switches::Bool=false,
    model_line_upgrades::Bool=false,
    line_upgrade_options::Dict=Dict(), # Each option is a dictionary with the keys "locations" (the names of the lines that can be upgraded), "max_amps" (the current rating of each conductor), and "cost_per_meter".
    model_transformer_upgrades::Bool=false,
    transformer_upgrade_options::Dict=Dict(),
    switch_open_timesteps::Dict=Dict(),
    
    single_outage_start_time_step::Real=0,
    single_outage_end_time_step::Real=0,
    model_outages_with_outages_vector::Bool=false,
    outages_vector::Array=[],
    run_outage_simulator::Bool=false,
    allow_dropped_load::Bool=false,
    outage_simulator_generator_gallons_per_kwh::Real=0.02457,
    length_of_simulated_outages_time_steps::Array=[],
    critical_load_method::String="Fraction",
    critical_load_fraction::Dict=Dict(), # Keys are the node numbers (as strings), values are the critical load fractions
    critical_load_timeseries::Dict=Dict(), # Keys are the node numbers (as strings), values are the critical load time series
    number_of_outages_to_simulate::Real=0,
    
    time_steps_per_hour::Real=0,
    generator_fuel_gallon_available::Dict=Dict(),
    generators_only_run_during_grid_outage::Bool=false,
    battery_min_soc_fraction_during_non_outage_times::Real=0.2,
    battery_min_soc_fraction_during_grid_outage_times::Real=0.0,
    generate_dictionary_for_plotting::Bool=false,
    number_of_plots_from_outage_simulator::Real=0,
  
    generate_same_pv_production_profile_for_each_node::Bool=false,
    pv_inputs_for_standardized_pv_production_profile::Dict=Dict(), 
    
    display_information_during_modeling_run::Bool=false, # This can be helpful for debugging a model
    include_additional_outputs_into_the_combined_results_dictionary::Bool=false,
    
    fault_analysis::Dict=Dict(),
    allow_bus_voltage_violations::Bool=false,
    bus_per_unit_voltage_target_upper_bound::Real=1.05,
    bus_per_unit_voltage_target_lower_bound::Real=0.95,
    cost_per_voltage_violation_per_timestep::Real=1000,
    allow_dropped_load_in_main_optimization::Bool=false,
    cost_per_kwh_dropped_load::Real=100,
    run_Xpress_model_presolve::Bool=true,  
    run_IIS_on_nonoptimal_models::Bool=false,
    load_profiles_for_outage_sim_if_using_the_fraction_method::Array=[]

The `grid_available_timesteps` and `grid_outage_timesteps` fields of the struct are not inputs. They are derived from 
`single_outage_start_time_step`, `single_outage_end_time_step`, `model_outages_with_outages_vector`, and `outages_vector`.
"""

mutable struct MultinodeInputs <: AbstractMultinode
    folder_location
    bus_coordinates
    PMD_network_input
    multinode_type
    model_type
    model_subtype
    run_BAU_case
    optimizer
    optimizer_tolerance
    log_solver_output_to_console
    PMD_time_steps
    apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD
    REopt_inputs_list
    number_of_phases
    bus_phase_voltage_lower_bound_per_unit
    bus_phase_voltage_upper_bound_per_unit
    bus_neutral_voltage_upper_bound_per_unit
    facilitymeter_node
    substation_node
    substation_line
    allow_export_beyond_substation
    substation_export_limit
    substation_import_limit
    external_reactive_power_support_per_phase_maximum_kvar
    model_switches
    model_line_upgrades
    line_upgrade_options 
    model_transformer_upgrades
    transformer_upgrade_options
    switch_open_timesteps
    single_outage_start_time_step
    single_outage_end_time_step
    model_outages_with_outages_vector
    outages_vector
    run_outage_simulator
    allow_dropped_load
    outage_simulator_generator_gallons_per_kwh
    length_of_simulated_outages_time_steps
    critical_load_method
    critical_load_fraction
    critical_load_timeseries
    number_of_outages_to_simulate
    time_steps_per_hour
    generator_fuel_gallon_available
    generators_only_run_during_grid_outage
    battery_min_soc_fraction_during_non_outage_times
    battery_min_soc_fraction_during_grid_outage_times
    generate_dictionary_for_plotting
    number_of_plots_from_outage_simulator
    generate_same_pv_production_profile_for_each_node
    pv_inputs_for_standardized_pv_production_profile 
    display_information_during_modeling_run
    include_additional_outputs_into_the_combined_results_dictionary
    fault_analysis
    allow_bus_voltage_violations
    bus_per_unit_voltage_target_upper_bound
    bus_per_unit_voltage_target_lower_bound
    cost_per_voltage_violation_per_timestep
    allow_dropped_load_in_main_optimization
    cost_per_kwh_dropped_load
    run_Xpress_model_presolve  
    run_IIS_on_nonoptimal_models
    load_profiles_for_outage_sim_if_using_the_fraction_method
    grid_available_timesteps
    grid_outage_timesteps
   
    function MultinodeInputs(;
        folder_location::String="",
        bus_coordinates::String="",  
        PMD_network_input::Any,
        multinode_type::String="BehindTheMeter", 
        model_type::String="PowerModelsDistribution",
        model_subtype::String="LPUBFDiagPowerModel",
        run_BAU_case::Bool=true, 
        optimizer::Any, 
        optimizer_tolerance::Float64=0.001,
        log_solver_output_to_console::Bool=true,
        PMD_time_steps::Any=collect(1:24),
        apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD::Bool=true,
        REopt_inputs_list::Array=[],
        number_of_phases::Real=1,
        bus_phase_voltage_lower_bound_per_unit::Float64=0.95,
        bus_phase_voltage_upper_bound_per_unit::Float64=1.05,
        bus_neutral_voltage_upper_bound_per_unit::Float64=0.1,
        facilitymeter_node::String="",
        substation_node::String="",
        substation_line::String="",
        allow_export_beyond_substation::Bool=false,
        substation_export_limit::Real=0,
        substation_import_limit::Real=Inf,
        external_reactive_power_support_per_phase_maximum_kvar::Real=1000000,
        model_switches::Bool=false,
        model_line_upgrades::Bool=false,
        line_upgrade_options::Dict=Dict(), 
        model_transformer_upgrades::Bool=false,
        transformer_upgrade_options::Dict=Dict(),
        switch_open_timesteps::Dict=Dict(),
        single_outage_start_time_step::Real=0,
        single_outage_end_time_step::Real=0,
        model_outages_with_outages_vector::Bool=false,
        outages_vector::Array=[],
        run_outage_simulator::Bool=false,
        allow_dropped_load::Bool=false,
        outage_simulator_generator_gallons_per_kwh::Real=0.02457,
        length_of_simulated_outages_time_steps::Array=[],
        critical_load_method::String="Fraction",
        critical_load_fraction::Dict=Dict(),
        critical_load_timeseries::Dict=Dict(),
        number_of_outages_to_simulate::Real=0,
        time_steps_per_hour::Real=0,
        generator_fuel_gallon_available::Dict=Dict(),
        generators_only_run_during_grid_outage::Bool=false,
        battery_min_soc_fraction_during_non_outage_times::Real=0.2,
        battery_min_soc_fraction_during_grid_outage_times::Real=0.0,
        generate_dictionary_for_plotting::Bool=false,
        number_of_plots_from_outage_simulator::Real=0,
        generate_same_pv_production_profile_for_each_node::Bool=false,
        pv_inputs_for_standardized_pv_production_profile::Dict=Dict(), 
        display_information_during_modeling_run::Bool=false,
        include_additional_outputs_into_the_combined_results_dictionary::Bool=false,
        fault_analysis::Dict=Dict(),
        allow_bus_voltage_violations::Bool=false,
        bus_per_unit_voltage_target_upper_bound::Real=1.05,
        bus_per_unit_voltage_target_lower_bound::Real=0.95,
        cost_per_voltage_violation_per_timestep::Real=1000,
        allow_dropped_load_in_main_optimization::Bool=false,
        cost_per_kwh_dropped_load::Real=100,
        run_Xpress_model_presolve::Bool=true,  
        run_IIS_on_nonoptimal_models::Bool=false,
        load_profiles_for_outage_sim_if_using_the_fraction_method::Array=[],
        )
    
    if generate_same_pv_production_profile_for_each_node

        pv_power_production_factor_series, ambient_temp_celcius = REopt.call_pvwatts_api(pv_inputs_for_standardized_pv_production_profile["latitude"], 
                                                                                        pv_inputs_for_standardized_pv_production_profile["longitude"]; 
                                                                                        tilt= pv_inputs_for_standardized_pv_production_profile["tilt"], 
                                                                                        azimuth= pv_inputs_for_standardized_pv_production_profile["azimuth"], 
                                                                                        module_type= pv_inputs_for_standardized_pv_production_profile["module_type"], 
                                                                                        array_type= pv_inputs_for_standardized_pv_production_profile["array_type"], 
                                                                                        losses= pv_inputs_for_standardized_pv_production_profile["losses"], 
                                                                                        dc_ac_ratio= pv_inputs_for_standardized_pv_production_profile["dc_ac_ratio"],
                                                                                        gcr= pv_inputs_for_standardized_pv_production_profile["gcr"], 
                                                                                        inv_eff= 100 * pv_inputs_for_standardized_pv_production_profile["inv_eff_fraction"], 
                                                                                        timeframe="hourly", 
                                                                                        radius=0, 
                                                                                        time_steps_per_hour=time_steps_per_hour)

        for node in collect(1:length(REopt_inputs_list))
            if "PV" in keys(REopt_inputs_list[node])
                if "production_factor_series" in keys(REopt_inputs_list[node]["PV"])
                    # do nothing because the power_factor_series is already defined
                else
                    REopt_inputs_list[node]["PV"]["production_factor_series"] = pv_power_production_factor_series
                end
            end
        end
    end
    
    if allow_bus_voltage_violations
        @warn "Setting the per unit phase voltage upper bound, phase voltage lower bound, and neutral voltage upper bound to 10, 0, and 10, respectively, for the PMD inputs because allow_bus_voltage_violations is set to true"
        bus_phase_voltage_upper_bound_per_unit = 10.0
        bus_phase_voltage_lower_bound_per_unit = 0.0
        bus_neutral_voltage_upper_bound_per_unit = 10.0
    end

    if battery_min_soc_fraction_during_grid_outage_times > battery_min_soc_fraction_during_non_outage_times
        throw(@error("The code is currently not compatible with the battery_min_soc_fraction_during_grid_outage_times being higher than battery_min_soc_fraction_during_non_outage_times."))
    end

    for (node_index, node_inputs) in enumerate(REopt_inputs_list)
        for thermal_storage_name in ["HotThermalStorage", "ColdThermalStorage", "HighTempThermalStorage"]
            if thermal_storage_name in keys(node_inputs)
                throw(@error("The REopt inputs at position $(node_index) of REopt_inputs_list include $(thermal_storage_name), but thermal storage is not supported in the multinode model. Please remove it from the REopt inputs."))
            end
        end
    end

    all_timesteps = collect(1:Int(8760 * time_steps_per_hour))
    
    if model_outages_with_outages_vector
        grid_outage_timesteps = sort(unique(intersect(all_timesteps, outages_vector)))
    elseif single_outage_end_time_step - single_outage_start_time_step > 0
        grid_outage_timesteps = intersect(all_timesteps, Int(single_outage_start_time_step):Int(single_outage_end_time_step))
    else
        grid_outage_timesteps = Int[]
    end

    grid_available_timesteps = setdiff(all_timesteps, grid_outage_timesteps)

    new(
        folder_location,
        bus_coordinates,
        PMD_network_input,
        multinode_type,
        model_type,
        model_subtype,
        run_BAU_case,
        optimizer,
        optimizer_tolerance,
        log_solver_output_to_console,
        PMD_time_steps,
        apply_simple_powerflow_model_to_timesteps_that_do_not_use_PMD,
        REopt_inputs_list,
        number_of_phases,
        bus_phase_voltage_lower_bound_per_unit,
        bus_phase_voltage_upper_bound_per_unit,
        bus_neutral_voltage_upper_bound_per_unit,
        facilitymeter_node,
        substation_node,
        substation_line,
        allow_export_beyond_substation,
        substation_export_limit,
        substation_import_limit,
        external_reactive_power_support_per_phase_maximum_kvar,
        model_switches,
        model_line_upgrades,
        line_upgrade_options, 
        model_transformer_upgrades,
        transformer_upgrade_options,
        switch_open_timesteps,
        single_outage_start_time_step,
        single_outage_end_time_step,
        model_outages_with_outages_vector,
        outages_vector,
        run_outage_simulator,
        allow_dropped_load,
        outage_simulator_generator_gallons_per_kwh,
        length_of_simulated_outages_time_steps,
        critical_load_method,
        critical_load_fraction,
        critical_load_timeseries,
        number_of_outages_to_simulate,
        time_steps_per_hour,
        generator_fuel_gallon_available,
        generators_only_run_during_grid_outage,
        battery_min_soc_fraction_during_non_outage_times,
        battery_min_soc_fraction_during_grid_outage_times,
        generate_dictionary_for_plotting,
        number_of_plots_from_outage_simulator,
        generate_same_pv_production_profile_for_each_node,
        pv_inputs_for_standardized_pv_production_profile, 
        display_information_during_modeling_run,
        include_additional_outputs_into_the_combined_results_dictionary,
        fault_analysis,
        allow_bus_voltage_violations,
        bus_per_unit_voltage_target_upper_bound,
        bus_per_unit_voltage_target_lower_bound,
        cost_per_voltage_violation_per_timestep,
        allow_dropped_load_in_main_optimization,
        cost_per_kwh_dropped_load,
        run_Xpress_model_presolve,  
        run_IIS_on_nonoptimal_models,
        load_profiles_for_outage_sim_if_using_the_fraction_method,
        grid_available_timesteps,
        grid_outage_timesteps
    )
   
    end
end

