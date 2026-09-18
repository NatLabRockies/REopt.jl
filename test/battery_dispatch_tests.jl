# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

@testset verbose=true "SAM BESS dispatch strategies" begin
    # Tests for peak_shaving_look_ahead, peak_shaving_look_behind, and self_consumption
    # dispatch strategies (PR #607). All require fixed (min == max) non-zero sizing.
    # Requires the SAM ssc_battery DLL/SO to be present in src/sam/.

    # ---- Scenario parameters ----
    # Peak-shaving: MediumOffice has strong weekday/weekend contrast — near-zero weekend
    # loads vs. high weekday peaks — so day-to-day peak demand varies considerably.
    # This challenges look-behind (which uses yesterday's pattern as the forecast),
    # especially at week transitions where Sunday's low load under-predicts Monday's peak.
    ps_d = Dict(
        "Site"         => Dict("latitude" => 37.78, "longitude" => -122.45),
        "ElectricLoad" => Dict("doe_reference_name" => "MediumOffice", "annual_kwh" => 800000.0),
        "ElectricTariff" => Dict("blended_annual_energy_rate" => 0.12, "blended_annual_demand_rate" => 30.0)
    )
    ps_batt_kw  = 100.0
    ps_batt_kwh = 200.0
    ps_pv_kw    = 100.0

    # Self-consumption: 120 kW PV against a ~34 kW average retail load. Midday generation
    # routinely exceeds instantaneous demand, but annual PV (~200 MWh) stays below annual
    # load (300 MWh) so the NEM constraint (annual export ≤ annual import) does not bind.
    # The LP baseline exports midday surplus via NEM; SAM self_consumption stores it instead.
    sc_d = Dict(
        "Site"           => Dict("latitude" => 37.78, "longitude" => -122.45),
        "ElectricLoad"   => Dict("doe_reference_name" => "RetailStore", "annual_kwh" => 300000.0),
        "ElectricTariff" => Dict("blended_annual_energy_rate" => 0.12, "blended_annual_demand_rate" => 0.0),
        "ElectricUtility" => Dict("net_metering_limit_kw" => 500.0)
    )
    sc_batt_kw  = 50.0
    sc_batt_kwh = 100.0
    sc_pv_kw    = 120.0

    # ---- Cost-optimal baselines (LP with perfect annual foresight) ----
    # Baseline 1: battery-only peak shaving
    d_opt_no_pv = deepcopy(ps_d)
    d_opt_no_pv["ElectricStorage"] = Dict(
        "min_kw" => ps_batt_kw, "max_kw" => ps_batt_kw,
        "min_kwh" => ps_batt_kwh, "max_kwh" => ps_batt_kwh
    )
    m_opt = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
    r_opt_no_pv    = run_reopt(m_opt, REoptInputs(Scenario(d_opt_no_pv)))
    bill_opt_no_pv = r_opt_no_pv["ElectricTariff"]["year_one_bill_before_tax"]
    finalize(backend(m_opt)); empty!(m_opt); GC.gc()

    # Baseline 2: peak shaving with PV
    d_opt_ps_with_pv = deepcopy(ps_d)
    d_opt_ps_with_pv["PV"] = Dict("min_kw" => ps_pv_kw, "max_kw" => ps_pv_kw)
    d_opt_ps_with_pv["ElectricStorage"] = Dict(
        "min_kw" => ps_batt_kw, "max_kw" => ps_batt_kw,
        "min_kwh" => ps_batt_kwh, "max_kwh" => ps_batt_kwh
    )
    m_opt = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
    r_opt_ps_with_pv    = run_reopt(m_opt, REoptInputs(Scenario(d_opt_ps_with_pv)))
    bill_opt_ps_with_pv = r_opt_ps_with_pv["ElectricTariff"]["year_one_bill_before_tax"]
    finalize(backend(m_opt)); empty!(m_opt); GC.gc()

    # Baseline 3: self-consumption (NEM-enabled). internal_efficiency_fraction = 1.0 matches
    # the value SAM back-calculates for self_consumption, keeping battery RTE equal.
    d_opt_sc = deepcopy(sc_d)
    d_opt_sc["PV"] = Dict("min_kw" => sc_pv_kw, "max_kw" => sc_pv_kw)
    d_opt_sc["ElectricStorage"] = Dict(
        "min_kw" => sc_batt_kw, "max_kw" => sc_batt_kw,
        "min_kwh" => sc_batt_kwh, "max_kwh" => sc_batt_kwh,
        "internal_efficiency_fraction" => 1.0
    )
    m_opt    = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
    r_opt_sc = run_reopt(m_opt, REoptInputs(Scenario(d_opt_sc)))
    # Net cost = bill minus NEM export credit (export_benefit is stored as a positive credit)
    bill_opt_sc = r_opt_sc["ElectricTariff"]["year_one_bill_before_tax"] -
                  get(r_opt_sc["ElectricTariff"], "year_one_export_benefit_before_tax", 0.0)
    finalize(backend(m_opt)); empty!(m_opt); GC.gc()

    summary_data = Vector{Dict{String,Any}}()

    @testset "peak_shaving_look_ahead (no PV)" begin
        d = deepcopy(ps_d)
        d["ElectricStorage"] = Dict(
            "min_kw" => ps_batt_kw, "max_kw" => ps_batt_kw,
            "min_kwh" => ps_batt_kwh, "max_kwh" => ps_batt_kwh,
            "dispatch_strategy" => "peak_shaving_look_ahead"
        )
        s = Scenario(d)
        p = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        results = run_reopt(m, p)

        @test results["status"] == "optimal"
        @test results["ElectricStorage"]["size_kw"]  ≈ ps_batt_kw  atol=0.01
        @test results["ElectricStorage"]["size_kwh"] ≈ ps_batt_kwh atol=0.01

        # Optimizer SOC must track SAM-generated dispatch within the fixed_soc tolerance
        soc_series = results["ElectricStorage"]["soc_series_fraction"]
        fixed_soc  = p.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction
        tol        = p.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction_tolerance
        @test maximum(abs.(soc_series .- fixed_soc)) ≤ tol + 1e-3

        bill = results["ElectricTariff"]["year_one_bill_before_tax"]
        @test bill ≥ bill_opt_no_pv   # LP perfect-foresight is a lower bound on achievable bill

        push!(summary_data, Dict("strategy" => "peak_shaving_look_ahead (no PV)",
            "status" => results["status"], "opt" => bill_opt_no_pv, "sam" => bill))
        finalize(backend(m)); empty!(m); GC.gc()
    end

    @testset "peak_shaving_look_behind (no PV)" begin
        d = deepcopy(ps_d)
        d["ElectricStorage"] = Dict(
            "min_kw" => ps_batt_kw, "max_kw" => ps_batt_kw,
            "min_kwh" => ps_batt_kwh, "max_kwh" => ps_batt_kwh,
            "dispatch_strategy" => "peak_shaving_look_behind"
        )
        s = Scenario(d)
        p = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        results = run_reopt(m, p)

        @test results["status"] == "optimal"
        @test results["ElectricStorage"]["size_kw"]  ≈ ps_batt_kw  atol=0.01
        @test results["ElectricStorage"]["size_kwh"] ≈ ps_batt_kwh atol=0.01

        soc_series = results["ElectricStorage"]["soc_series_fraction"]
        fixed_soc  = p.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction
        tol        = p.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction_tolerance
        @test maximum(abs.(soc_series .- fixed_soc)) ≤ tol + 1e-3

        bill = results["ElectricTariff"]["year_one_bill_before_tax"]
        @test bill ≥ bill_opt_no_pv

        # Look-behind uses yesterday's data — its SAM SOC profile must differ from look-ahead
        d_la = deepcopy(ps_d)
        d_la["ElectricStorage"] = Dict(
            "min_kw" => ps_batt_kw, "max_kw" => ps_batt_kw,
            "min_kwh" => ps_batt_kwh, "max_kwh" => ps_batt_kwh,
            "dispatch_strategy" => "peak_shaving_look_ahead"
        )
        p_la         = REoptInputs(Scenario(d_la))
        fixed_soc_la = p_la.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction
        @test fixed_soc != fixed_soc_la

        push!(summary_data, Dict("strategy" => "peak_shaving_look_behind (no PV)",
            "status" => results["status"], "opt" => bill_opt_no_pv, "sam" => bill))
        finalize(backend(m)); empty!(m); GC.gc()
    end

    @testset "self_consumption (with PV)" begin
        d = deepcopy(sc_d)
        d["PV"] = Dict("min_kw" => sc_pv_kw, "max_kw" => sc_pv_kw)
        d["ElectricStorage"] = Dict(
            "min_kw" => sc_batt_kw, "max_kw" => sc_batt_kw,
            "min_kwh" => sc_batt_kwh, "max_kwh" => sc_batt_kwh,
            "dispatch_strategy" => "self_consumption"
        )
        s = Scenario(d)
        p = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        results = run_reopt(m, p)

        @test results["status"] == "optimal"
        @test results["PV"]["size_kw"]               ≈ sc_pv_kw   atol=0.01
        @test results["ElectricStorage"]["size_kw"]  ≈ sc_batt_kw  atol=0.01
        @test results["ElectricStorage"]["size_kwh"] ≈ sc_batt_kwh atol=0.01

        soc_series = results["ElectricStorage"]["soc_series_fraction"]
        fixed_soc  = p.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction
        tol        = p.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction_tolerance
        @test maximum(abs.(soc_series .- fixed_soc)) ≤ tol + 1e-3

        # Net cost (bill minus NEM export credit); LP is a lower bound on net electricity cost
        net_cost = results["ElectricTariff"]["year_one_bill_before_tax"] -
                   get(results["ElectricTariff"], "year_one_export_benefit_before_tax", 0.0)
        @test net_cost ≥ bill_opt_sc

        # self_consumption stores excess PV; LP baseline exports it — export should be less
        pv_export_opt = get(r_opt_sc["PV"], "annual_energy_exported_kwh", 0.0)
        pv_export_sc  = get(results["PV"], "annual_energy_exported_kwh", 0.0)
        @test pv_export_sc ≤ pv_export_opt

        push!(summary_data, Dict("strategy" => "self_consumption (with PV)",
            "status" => results["status"], "opt" => bill_opt_sc, "sam" => net_cost,
            "pv_export_opt" => pv_export_opt, "pv_export_sc" => pv_export_sc))
        finalize(backend(m)); empty!(m); GC.gc()
    end

    @testset "peak_shaving_look_behind (with PV)" begin
        d = deepcopy(ps_d)
        d["PV"] = Dict("min_kw" => ps_pv_kw, "max_kw" => ps_pv_kw)
        d["ElectricStorage"] = Dict(
            "min_kw" => ps_batt_kw, "max_kw" => ps_batt_kw,
            "min_kwh" => ps_batt_kwh, "max_kwh" => ps_batt_kwh,
            "dispatch_strategy" => "peak_shaving_look_behind"
        )
        s = Scenario(d)
        p = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        results = run_reopt(m, p)

        @test results["status"] == "optimal"
        @test results["PV"]["size_kw"]               ≈ ps_pv_kw   atol=0.01
        @test results["ElectricStorage"]["size_kw"]  ≈ ps_batt_kw  atol=0.01
        @test results["ElectricStorage"]["size_kwh"] ≈ ps_batt_kwh atol=0.01

        soc_series = results["ElectricStorage"]["soc_series_fraction"]
        fixed_soc  = p.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction
        tol        = p.s.storage.attr["ElectricStorage"].fixed_soc_series_fraction_tolerance
        @test maximum(abs.(soc_series .- fixed_soc)) ≤ tol + 1e-3

        bill = results["ElectricTariff"]["year_one_bill_before_tax"]
        @test bill ≥ bill_opt_ps_with_pv

        push!(summary_data, Dict("strategy" => "peak_shaving_look_behind (with PV)",
            "status" => results["status"], "opt" => bill_opt_ps_with_pv, "sam" => bill))
        finalize(backend(m)); empty!(m); GC.gc()
    end

    # ---- End-of-test summary (net electricity cost, $ year-one) ----
    w1, w2, w3, w4 = 40, 17, 17, 10
    sep = "="^(w1+w2+w3+w4)
    println("\n" * sep)
    println("  DISPATCH STRATEGY COMPARISON  (year-one net electricity cost, \$)")
    println(sep)
    println(rpad("Strategy", w1) * lpad("Optimized", w2) * lpad("SAM Dispatch", w3) * lpad("Δ% vs Opt", w4))
    println("-"^(w1+w2+w3+w4))
    for row in summary_data
        status = row["status"]
        tag    = status == "optimal" ? "" : " [$status]"
        pct    = row["opt"] != 0 ? round((row["sam"] - row["opt"]) / abs(row["opt"]) * 100, digits=1) : 0.0
        println(rpad(row["strategy"] * tag, w1) *
                lpad(string(round(Int, row["opt"])), w2) *
                lpad(string(round(Int, row["sam"])), w3) *
                lpad("+$(pct)%", w4))
    end
    println(sep)
    println("  self_consumption costs are net of NEM export credits")

    # PV export comparison for self_consumption scenario
    sc_idx = findfirst(r -> r["strategy"] == "self_consumption (with PV)", summary_data)
    if !isnothing(sc_idx)
        sc = summary_data[sc_idx]
        pv_opt = round(Int, sc["pv_export_opt"])
        pv_sc  = round(Int, sc["pv_export_sc"])
        pv_pct = pv_opt != 0 ? round((pv_sc - pv_opt) / pv_opt * 100, digits=1) : 0.0
        println()
        println("  Self-consumption PV export reduction (annual kWh exported via NEM):")
        println("-"^(w1+w2+w3+w4))
        println(rpad("Scenario", w1) * lpad("PV Export [kWh]", w2+w3) * lpad("Δ% vs Opt", w4))
        println("-"^(w1+w2+w3+w4))
        println(rpad("optimized (NEM baseline)", w1) * lpad(string(pv_opt), w2+w3) * lpad("—", w4))
        println(rpad("self_consumption", w1) * lpad(string(pv_sc), w2+w3) * lpad("$(pv_pct)%", w4))
        println("-"^(w1+w2+w3+w4))
    end
    println()
end
