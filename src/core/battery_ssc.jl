# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    run_ssc_battery(;
        batt_kw, batt_kwh, dispatch_strategy, soc_init_fraction, soc_min_fraction, 
        inverter_efficiency_fraction, rectifier_efficiency_fraction, internal_efficiency_fraction,
        can_grid_charge, loads_kw, pvs, time_steps_per_hour, pv_levelization_factor, soc_max_fraction=1.0
    )

Run the SAM SSC "battery" module
"""
function run_ssc_battery(;
    batt_kw::Real,
    batt_kwh::Real,
    dispatch_strategy::String,
    soc_init_fraction::Real,
    soc_min_fraction::Real,
    inverter_efficiency_fraction::Real,
    rectifier_efficiency_fraction::Real,
    internal_efficiency_fraction::Real,
    can_grid_charge::Bool,
    loads_kw::Array{<:Real,1},
    pvs::Vector{PV} = PV[],
    time_steps_per_hour::Int,
    can_net_meter::Bool,
    can_wholesale::Bool,
    pv_levelization_factor::Dict{String,<:Real},
    soc_max_fraction::Real=1.0
)
    R = Dict{String, Any}()

    n_timesteps = length(loads_kw)

    # Map REopt dispatch_strategy to SAM battery dispatch controls.
    # batt_dispatch_choice: 0 = PeakShaving, 5 = SelfConsumption
    # forecast_choice: 0 = look-ahead, 1 = look-behind
    dispatch_settings_map = Dict(
        "peak_shaving_look_ahead"  => (0, 0),
        "peak_shaving_look_behind" => (0, 1),
        "self_consumption"         => (5, 0)
    )
    batt_dispatch_choice, forecast_choice = dispatch_settings_map[dispatch_strategy]
    # Get the PV generation profile
    #TODO: Can the user enter a prod factor series that's not the same length as loads_kw in REopt in general?
    generation_series_kw = zeros(Float64, n_timesteps)
    if !isempty(pvs)
        for pv in pvs
            if !isnothing(pv.production_factor_series) && !isempty(pv.production_factor_series)
                pf = pv.production_factor_series
                # Calculate total PV size as existing capacity + fixed new capacity (min_kw == max_kw)
                pv_size_kw = Float64(pv.existing_kw)
                if pv.min_kw == pv.max_kw
                    pv_size_kw += Float64(pv.max_kw)
                end
                generation_series_kw .+= pv_size_kw .* pf .* pv_levelization_factor[pv.name]
            end
        end
    end 
    # Setup SSC 
    # TODO: Update the MacOS and Linux files
    if Sys.isapple()
        libfile = "ssc_battery.dylib"
    elseif Sys.islinux()
        libfile = "ssc_battery.so"
    elseif Sys.iswindows()
        libfile = "ssc_battery.dll"
    end

    global hdl = joinpath(@__DIR__, "..", "sam", libfile)
    chmod(hdl, filemode(hdl) | 0o755)
    ssc_module = @ccall hdl.ssc_module_create("battery"::Cstring)::Ptr{Cvoid}
    if ssc_module == C_NULL
        R["error"] = "Unable to create SAM SSC 'battery' module from src/sam/$libfile."
        R["soc_series_fraction"] = nothing
        return R
    end
    data = @ccall hdl.ssc_data_create()::Ptr{Cvoid}
    @ccall hdl.ssc_module_exec_set_print(0::Cint)::Cvoid

    # Load default battery parameters for SAM that do not change by REopt scenario
    defaults_file = joinpath(@__DIR__, "..", "sam", "defaults", "defaults_battery.json")
    defaults = JSON.parsefile(defaults_file)
    set_ssc_data_from_dict(defaults, "battery", data)

    # REopt-specific inputs for SAM SSC
    reopt_overrides = Dict{String, Any}(
        "batt_ac_or_dc" => 1,                                   # 0 = DC_Connected, 1 = AC_Connected

        # TODO: Set up inputs below when DC-coupled batteries are enabled in REopt.
        "batt_dispatch_auto_can_clipcharge" => 0,               # Set to 1 for DC-coupled batteries
        "batt_dc_dc_efficiency" => 1.0 * 100.0,                 # DC-DC efficiency for DC-coupled batteries (not used for AC-coupled but still a required input)

        # Simulation Group 
        "timestep_minutes" => Int(60 / time_steps_per_hour),    

        # BatterySystem Group
        "batt_ac_dc_efficiency" => rectifier_efficiency_fraction * 100.0,
        "batt_dc_ac_efficiency" => inverter_efficiency_fraction * 100.0,

        # BatteryCell Group
        "batt_initial_SOC" => soc_init_fraction * 100.0,
        "batt_maximum_SOC" => soc_max_fraction * 100.0,
        "batt_minimum_SOC" => soc_min_fraction * 100.0,
        
        # BatteryDispatch Group
        "batt_dispatch_auto_btm_can_discharge_to_grid" => Int(can_net_meter || can_wholesale),
        "batt_dispatch_auto_can_gridcharge" => Int(can_grid_charge),
        "batt_dispatch_choice" => batt_dispatch_choice,
        "batt_dispatch_load_forecast_choice" => forecast_choice,
        "batt_dispatch_wf_forecast_choice" => forecast_choice
    )
    set_ssc_data_from_dict(reopt_overrides, "battery", data)

    # Calculated batt_computed_bank_capacity, required for the Size_battery function
    batt_computed_bank_capacity = defaults["batt_Qfull"] * defaults["batt_Vnom_default"] *
        defaults["batt_computed_series"] * defaults["batt_computed_strings"] / 1000.0
    @ccall hdl.ssc_data_set_number(data::Ptr{Cvoid}, "batt_computed_bank_capacity"::Cstring, batt_computed_bank_capacity::Cdouble)::Cvoid

    # SAM defaults to 500 V for commercial-scale and 240 V for residential scale. A larger voltage for smaller systems may cause a convergence issue.
    desired_voltage = batt_kw <= 20 ? 240.0 : 500.0
    @ccall hdl.ssc_data_set_number(data::Ptr{Cvoid}, "desired_power"::Cstring, Float64(batt_kw)::Cdouble)::Cvoid
    @ccall hdl.ssc_data_set_number(data::Ptr{Cvoid}, "desired_capacity"::Cstring, Float64(batt_kwh)::Cdouble)::Cvoid
    @ccall hdl.ssc_data_set_number(data::Ptr{Cvoid}, "desired_voltage"::Cstring, desired_voltage::Cdouble)::Cvoid

    # Call the SSC Size_battery function to set SSC variables that depend up REopt size inputs
    size_success = @ccall hdl.Size_battery(data::Ptr{Cvoid})::Cuchar

    # Outputs from Size_battery:
        # batt_computed_series	            Number of cells in series, ceil(desired_voltage / batt_Vnom_default)
        # batt_computed_strings	            Number of parallel strings, ceil(desired_capacity·1000 / (batt_Qfull·batt_Vnom_default·num_series))
        # batt_computed_bank_capacity	    Sized bank capacity, batt_Qfull * computed_voltage * num_strings * 0.001
        # batt_power_discharge_max_kwdc	    DC discharge power limit
        # batt_power_discharge_max_kwac	    AC discharge power limit
        # batt_power_charge_max_kwdc	    DC charge power limit
        # batt_power_charge_max_kwac	    AC charge power limit
        # batt_current_charge_max	        batt_bank_power_charge_dc / computed_voltage · 1000
        # batt_current_discharge_max	    batt_bank_power_discharge_dc / computed_voltage · 1000
        # original_capacity	                Reference capacity
        # batt_mass	                        (via Calculate_thermal_params) scaled by desired_capacity/original_capacity
        # batt_surface_area	                (via Calculate_thermal_params) scaled by desired_capacity/original_capacity 

    if size_success == 0x00
        err_ptr = @ccall hdl.ssc_data_get_string(data::Ptr{Cvoid}, "error"::Cstring)::Cstring
        size_error_detail = err_ptr == C_NULL ? "No error message returned by Size_battery." : unsafe_string(err_ptr)
        @ccall hdl.ssc_module_free(ssc_module::Ptr{Cvoid})::Cvoid
        @ccall hdl.ssc_data_free(data::Ptr{Cvoid})::Cvoid
        R["error"] = "SAM Size_battery failed for batt_kw=$batt_kw, batt_kwh=$batt_kwh, desired_voltage=$desired_voltage V. Detail: $size_error_detail"
        R["soc_series_fraction"] = nothing
        return R
    end

    # Set onsite generation and load profiles in kW
    gen_array = convert(Vector{Float64}, generation_series_kw)
    @ccall hdl.ssc_data_set_array(data::Ptr{Cvoid}, "gen"::Cstring, gen_array::Ptr{Cdouble}, Cint(n_timesteps)::Cint)::Cvoid

    load_array = convert(Vector{Float64}, loads_kw)
    @ccall hdl.ssc_data_set_array(data::Ptr{Cvoid}, "load"::Cstring, load_array::Ptr{Cdouble}, Cint(n_timesteps)::Cint)::Cvoid

    # Run SAM SSC simulation
    success = @ccall hdl.ssc_module_exec(ssc_module::Ptr{Cvoid}, data::Ptr{Cvoid})::Cint

    if success != 1
        # Retrieve SSC log messages for diagnostics
        idx = Ref(Cint(0))
        log_messages = String[]
        while true
            msg_type = Ref(Cint(0))
            msg_time = Ref(Cfloat(0))
            msg_ptr = @ccall hdl.ssc_module_log(ssc_module::Ptr{Cvoid}, idx[]::Cint, msg_type::Ptr{Cint}, msg_time::Ptr{Cfloat})::Cstring
            if msg_ptr == C_NULL
                break
            end
            push!(log_messages, unsafe_string(msg_ptr))
            idx[] += Cint(1)
        end
        ssc_error_detail = isempty(log_messages) ? "No SSC log messages available." : join(log_messages, "\n")

        @ccall hdl.ssc_module_free(ssc_module::Ptr{Cvoid})::Cvoid
        @ccall hdl.ssc_data_free(data::Ptr{Cvoid})::Cvoid
        R["error"] = "SAM battery module execution failed for dispatch_strategy='$dispatch_strategy'. SSC log:\n$ssc_error_detail"
        R["soc_series_fraction"] = nothing
        return R
    end

    len_ref = Ref(Cint(0))

    # Extract battery state of charge profile [%]
    batt_soc_ptr = @ccall hdl.ssc_data_get_array(data::Ptr{Cvoid}, "batt_SOC"::Cstring, len_ref::Ptr{Cint})::Ptr{Float64}
    nout_soc = Int(len_ref[])

    if batt_soc_ptr == C_NULL || nout_soc == 0
        @ccall hdl.ssc_module_free(ssc_module::Ptr{Cvoid})::Cvoid
        @ccall hdl.ssc_data_free(data::Ptr{Cvoid})::Cvoid
        R["error"] = "SAM battery module ran but did not return a batt_SOC array."
        R["soc_series_fraction"] = nothing
        return R
    end

    soc_series_pct = Vector{Float64}(undef, nout_soc)
    for i in 1:nout_soc
        soc_series_pct[i] = unsafe_load(batt_soc_ptr, i)
    end

    # Obtain SAM-calculated DC-DC RTE by reading the AC-AC RTE and dividing it by the rectifier and inverter efficiencies
    conv_eff_ref = Ref(convert(Cdouble, 0.0))
    @ccall hdl.ssc_data_get_number(data::Ptr{Cvoid}, "average_battery_conversion_efficiency"::Cstring, conv_eff_ref::Ptr{Cdouble})::Cvoid
    ac_ac_rte_fraction = Float64(conv_eff_ref[]) /100.0

    dc_dc_rte_fraction = ac_ac_rte_fraction / (inverter_efficiency_fraction * rectifier_efficiency_fraction)
    if dc_dc_rte_fraction < 0.0 || dc_dc_rte_fraction > 1.0
        @warn "SAM-derived DC-DC round-trip efficiency ($(round(dc_dc_rte_fraction, digits=4))) is outside [0, 1]; clamping to bounds."
    end
    internal_efficiency_fraction = clamp(dc_dc_rte_fraction, 0.0, 1.0)

    # Free SSC
    @ccall hdl.ssc_module_free(ssc_module::Ptr{Cvoid})::Cvoid
    @ccall hdl.ssc_data_free(data::Ptr{Cvoid})::Cvoid

    # Convert battery SOC from % to fraction 
    soc_series_fraction = soc_series_pct ./ 100.0
    clamp!(soc_series_fraction, 0.0, 1.0)

    R["soc_series_fraction"] = soc_series_fraction
    R["internal_efficiency_fraction"] = internal_efficiency_fraction
    R["error"] = ""
    return R
end
