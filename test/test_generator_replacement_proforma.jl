# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
using HiGHS
using JuMP
using REopt
using Test

@testset "Generator replacement in proforma" begin
    inputs = Dict(
        "Site" => Dict("latitude" => 39.74, "longitude" => -105.17),
        "ElectricLoad" => Dict("loads_kw" => fill(5.0, 8760), "year" => 2017),
        "ElectricTariff" => Dict("blended_annual_energy_rate" => 0.10),
        "ElectricUtility" => Dict(
            "emissions_factor_series_lb_CO2_per_kwh" => 0.0,
            "emissions_factor_series_lb_NOx_per_kwh" => 0.0,
            "emissions_factor_series_lb_SO2_per_kwh" => 0.0,
            "emissions_factor_series_lb_PM25_per_kwh" => 0.0,
            "renewable_energy_fraction_series" => [0.0],
        ),
        "ElectricStorage" => Dict("max_kw" => 0.0, "max_kwh" => 0.0),
        "Generator" => Dict(
            "existing_kw" => 2.0,
            "min_kw" => 3.0,
            "max_kw" => 3.0,
            "installed_cost_per_kw" => 2000.0,
            "replacement_year" => 2,
            "replace_cost_per_kw" => 1000.0,
            "fuel_cost_per_gallon" => 0.0,
            "fuel_avail_gal" => 100000.0,
            "om_cost_per_kw" => 0.0,
            "om_cost_per_kwh" => 0.0,
            "only_runs_during_grid_outage" => false,
        ),
        "Financial" => Dict(
            "analysis_years" => 5,
            "offtaker_discount_rate_fraction" => 0.10,
            "offtaker_tax_rate_fraction" => 0.20,
            "elec_cost_escalation_rate_fraction" => 0.0,
        ),
    )

    models = [Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false)) for _ in 1:2]
    results = run_reopt(models, inputs)
    @test results["status"] == "optimal"
    @test results["Generator"]["size_kw"] ≈ 5.0

    financial = Dict{Int, Dict}(2 => results["Financial"])
    # Installed and purchased capacities are fixed. Reuse the solved design for the boundary years.
    for replacement_year in (0, 5)
        inputs["Generator"]["replacement_year"] = replacement_year
        p = REoptInputs(Scenario(inputs))
        replacement_cost = REopt.generator_replacement_cost(models[2], p)
        financial[replacement_year] =
            REopt.proforma_results(p, results; generator_replacement_cost=replacement_cost)
    end

    upfront_replacement = financial[0]
    replacement = financial[2]
    terminal_year = financial[5]
    # Only the 3 kW of new capacity is replaced. The year-2 outlay is tax deductible.
    after_tax_outlay = 3.0 * 1000.0 * (1 - 0.20)
    @test replacement["offtaker_annual_free_cashflows"] - terminal_year["offtaker_annual_free_cashflows"] ≈
        [0.0, 0.0, -after_tax_outlay, 0.0, 0.0, 0.0]
    @test replacement["offtaker_annual_free_cashflows_bau"] ≈ terminal_year["offtaker_annual_free_cashflows_bau"]
    @test replacement["capital_costs_after_non_discounted_incentives_without_macrs"] -
        terminal_year["capital_costs_after_non_discounted_incentives_without_macrs"] ≈ after_tax_outlay / 1.10^2
    @test upfront_replacement["offtaker_annual_free_cashflows"] - terminal_year["offtaker_annual_free_cashflows"] ≈
        [-after_tax_outlay, 0.0, 0.0, 0.0, 0.0, 0.0]
    @test upfront_replacement["capital_costs_after_non_discounted_incentives_without_macrs"] -
        terminal_year["capital_costs_after_non_discounted_incentives_without_macrs"] ≈ after_tax_outlay
    @test replacement["simple_payback_years"] > terminal_year["simple_payback_years"] > 0
    for m in models
        finalize(backend(m))
        empty!(m)
    end
    GC.gc()
end
