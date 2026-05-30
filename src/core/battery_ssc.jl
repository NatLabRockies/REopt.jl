# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    run_ssc_battery(;
        batt_kw, batt_kwh, dispatch_strategy, soc_init_fraction, soc_min_fraction, 
        inverter_efficiency_fraction, rectifier_efficiency_fraction, internal_efficiency_fraction,
        can_grid_charge, loads_kw, pvs, time_steps_per_hour, soc_max_fraction=1.0
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
    soc_max_fraction::Real=1.0
)
    R = Dict{String, Any}()

    n_timesteps = length(loads_kw)

    # Map REopt dispatch_strategy to SAM battery dispatch controls.
    # batt_dispatch_choice: 0 = PeakShaving, 5 = SelfConsumption
    # batt_dispatch_load_forecast_choice: 0 = look-ahead, 1 = look-behind
    dispatch_settings_map = Dict(
        "peak_shaving_look_ahead"  => (0, 0),
        "peak_shaving_look_behind" => (0, 1),
        "self_consumption"         => (5, 0)
    )
    batt_dispatch_choice, batt_dispatch_load_forecast_choice = dispatch_settings_map[dispatch_strategy]

    # ----- Load profile -----
    loads_kw_native = Vector{Float64}(loads_kw)

    # ----- Generation profile (PV) -----
    en_standalone_batt = 0
    gen_kw_native = zeros(Float64, n_timesteps)
    if !isempty(pvs)
        for pv in pvs
            if !isnothing(pv.production_factor_series) && !isempty(pv.production_factor_series)
                pf = pv.production_factor_series
                # Calculate total PV size as existing capacity + fixed new capacity (min_kw == max_kw)
                pv_size_kw = Float64(pv.existing_kw)
                if pv.min_kw == pv.max_kw
                    pv_size_kw += Float64(pv.max_kw)
                end
                if length(pf) == n_timesteps
                    pf_native = Vector{Float64}(pf)
                elseif length(pf) == 8760
                    pf_native = repeat(Vector{Float64}(pf); inner=time_steps_per_hour)
                else
                    R["error"] = "PV '$(pv.name)' production_factor_series length ($(length(pf))) must be either 8760 or match loads_kw length ($(n_timesteps))."
                    R["soc_series_fraction"] = nothing
                    R["dispatch_series_kw"]  = nothing
                    return R
                end
                gen_kw_native .+= pv_size_kw .* pf_native
            end
        end
    end 

    if sum(gen_kw_native) > 0.0
        en_standalone_batt = 1
    end

    # ===== Setup SSC =====
    global hdl = nothing
    ssc_module = C_NULL

    libfiles = if Sys.isapple()
        ["libssc.dylib"]
    elseif Sys.islinux()
        ["ssc.so", "libssc.so"]
    elseif Sys.iswindows()
        ["ssc_new.dll", "ssc.dll"]
    else
        String[]
    end

    for libfile in libfiles
        try
            hdl_candidate = joinpath(@__DIR__, "..", "sam", libfile)
            if !isfile(hdl_candidate)
                continue
            end
            chmod(hdl_candidate, filemode(hdl_candidate) | 0o755)
            global hdl = hdl_candidate
            mod = @ccall hdl.ssc_module_create("battery"::Cstring)::Ptr{Cvoid}
            if mod != C_NULL
                ssc_module = mod
                break
            end
        catch
            # Try next candidate library.
        end
    end

    if ssc_module == C_NULL || isnothing(hdl)
        R["error"] = "Unable to create SAM SSC 'battery' module from available SSC binaries under src/sam."
        R["soc_series_fraction"] = nothing
        R["dispatch_series_kw"]  = nothing
        return R
    end

    data = @ccall hdl.ssc_data_create()::Ptr{Cvoid}
    @ccall hdl.ssc_module_exec_set_print(0::Cint)::Cvoid

    # Load baseline SAM battery defaults from JSON, then override with REopt-specific values.
    defaults_file = joinpath(@__DIR__, "..", "sam", "defaults", "defaults_battery.json")
    defaults = JSON.parsefile(defaults_file)
    set_ssc_data_from_dict(defaults, "battery", data)

    # ----- Override with REopt-specific inputs -----
    reopt_overrides = Dict{String, Any}(

        # Simulation Group 
        "timestep_minutes" => Int(60 / time_steps_per_hour),    # The number of minutes in each timestep

        # Lifetime Group
        "system_use_lifetime_output" => 0,                      # 0 = SingleYearRepeated, 1 = RunEveryYear
        "analysis_period" => 1,                                 # Only required if system_use_lifetime_output = 1
        
        # BatterySystem Group
        "batt_ac_dc_efficiency" => rectifier_efficiency_fraction * 100.0,
        "batt_ac_or_dc" => 1,                                   # 0 = DC_Connected, 1 = AC_Connected
        "batt_computed_bank_capacity" => batt_kwh,              # Depends on batt_Qfull, batt_Vnom_default, batt_ac_dc_efficiency, batt_ac_or_dc, batt_chem, batt_current_choice, batt_dc_ac_efficiency, batt_dc_dc_efficiency
        "batt_dc_ac_efficiency" => inverter_efficiency_fraction * 100.0,
        
        "batt_dc_dc_efficiency" => internal_efficiency_fraction * 100.0, # PV coupled with PV, ignored if not DC connected

        "batt_meter_position" => 0,                             # 0 = BehindTheMeter, 1 = FrontOfMeter
        "batt_power_charge_max_kwac" => batt_kw,
        "batt_power_charge_max_kwdc" => batt_kw,                # Should these be the same??
        "batt_power_discharge_max_kwac" => batt_kw,
        "batt_power_discharge_max_kwdc" => batt_kw,             # Should these be the same??
        "en_batt" => 1,                                         # Enable battery storage model [0/1]
        "en_standalone_batt" => en_standalone_batt,             # Enable standalone battery storage model [0/1]

        # BatteryCell Group (many values in this category are in the defaults JSON)
        "batt_chem" => 1,                                       # 0 = LeadAcid, 1 = Li-ion
        "batt_life_model" => 1,                                 # Options: 0 = calendar/cycle, 1 = NMC, 2 = LMO/LTO
        "batt_initial_SOC" => soc_init_fraction * 100.0,
        "batt_maximum_SOC" => soc_max_fraction * 100.0,
        "batt_minimum_SOC" => soc_min_fraction * 100.0,
        
        # BatteryDispatch Group
        "batt_dispatch_auto_btm_can_discharge_to_grid" => 0,    # TO-DO: update if battery export is enabled? - Behind the meter battery can discharge to grid? [0/1]
        "batt_dispatch_auto_can_charge" => 1,                   # System charging allowed for automated dispatch? [0/1] - What does this mean?
        "batt_dispatch_auto_can_clipcharge" => 1,               # Battery can charge from clipped power? [0/1] - What does this mean?
        "batt_dispatch_auto_can_curtailcharge" => 1,            # Battery can charge from grid-limited system power? [0/1] - What does this mean?
        "batt_dispatch_auto_can_gridcharge" => Int(can_grid_charge),
        "batt_dispatch_charge_only_system_exceeds_load" => 1,   # Battery can charge from system only when system output exceeds load [0/1]
        "batt_dispatch_choice" => batt_dispatch_choice,
        "batt_dispatch_discharge_only_load_exceeds_system" => 1,# Battery can discharge only when load exceeds system output [0/1]
        "batt_dispatch_load_forecast_choice" => batt_dispatch_load_forecast_choice,
        "batt_dispatch_update_frequency_hours" => 1,            # Frequency to update the look-ahead dispatch [hours]
        "batt_look_ahead_hours" => 24,                          # Hours to look ahead in automated dispatch [hours]

        # Need to specify anything under SystemCosts, PriceSignal, Revenue, ElectricityRates, etc.?

    )
    set_ssc_data_from_dict(reopt_overrides, "battery", data)

    # Generation and load profiles in kW
    gen_array = convert(Vector{Float64}, gen_kw_native)
    @ccall hdl.ssc_data_set_array(data::Ptr{Cvoid}, "gen"::Cstring, gen_array::Ptr{Cdouble}, Cint(n_timesteps)::Cint)::Cvoid

    load_array = convert(Vector{Float64}, loads_kw_native)
    @ccall hdl.ssc_data_set_array(data::Ptr{Cvoid}, "load"::Cstring, load_array::Ptr{Cdouble}, Cint(n_timesteps)::Cint)::Cvoid

    # ===== Execute =====
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
        R["dispatch_series_kw"]  = nothing
        return R
    end

    # ===== Extract results =====
    len_ref = Ref(Cint(0))

    # batt_power — Electricity to/from battery AC [kW]
    batt_power_ptr = @ccall hdl.ssc_data_get_array(data::Ptr{Cvoid}, "batt_power"::Cstring, len_ref::Ptr{Cint})::Ptr{Float64}
    nout = Int(len_ref[])

    # batt_SOC — Battery state of charge [%]
    len_ref[] = Cint(0)
    batt_soc_ptr = @ccall hdl.ssc_data_get_array(data::Ptr{Cvoid}, "batt_SOC"::Cstring, len_ref::Ptr{Cint})::Ptr{Float64}
    nout_soc = Int(len_ref[])

    if batt_power_ptr == C_NULL || batt_soc_ptr == C_NULL || nout == 0 || nout_soc == 0
        @ccall hdl.ssc_module_free(ssc_module::Ptr{Cvoid})::Cvoid
        @ccall hdl.ssc_data_free(data::Ptr{Cvoid})::Cvoid
        R["error"] = "SAM battery module ran but did not return batt_power/batt_SOC arrays."
        R["soc_series_fraction"] = nothing
        R["dispatch_series_kw"]  = nothing
        return R
    end

    nout_use = min(nout, nout_soc)

    dispatch_series_kw = Vector{Float64}(undef, nout_use)
    soc_series_pct     = Vector{Float64}(undef, nout_use)

    for i in 1:nout_use
        dispatch_series_kw[i] = unsafe_load(batt_power_ptr, i)
        soc_series_pct[i]     = unsafe_load(batt_soc_ptr, i)
    end

    # ===== Free SSC =====
    @ccall hdl.ssc_module_free(ssc_module::Ptr{Cvoid})::Cvoid
    @ccall hdl.ssc_data_free(data::Ptr{Cvoid})::Cvoid

    # ===== Convert SOC from % to fraction (0-1) =====
    soc_series_fraction = soc_series_pct ./ 100.0
    # Clamp to valid range
    clamp!(soc_series_fraction, 0.0, 1.0)

    R["soc_series_fraction"] = soc_series_fraction
    R["dispatch_series_kw"]  = dispatch_series_kw
    R["error"] = ""
    return R
end
