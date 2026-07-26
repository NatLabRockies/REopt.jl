"""
This scratch space can be used for development of new tests. Delete tests that are not longer needed.
    Run these tests with: 
    using Pkg
    Pkg.test("REopt"; test_args=["Dev"])
"""

# @testset verbose=true "Battery Can Export" begin

#     # case where whl rate is between off peak and on peak retail rates?
#     # or whl rate > retail rate and allow_simultaneous_export_import = false (copy existing test) 

#     # Case 1: energy rate is lower during PV production
#     # so expect battery to do energy arbitrage and NEM export during higher rate
#     d = JSON.parsefile("./scenarios/bess_export.json")
#     d["ElectricTariff"]["tou_energy_rates_per_kwh"] = repeat([0.5, 0.1, 0.5], inner=8, outer=365)
#     # d["ElectricStorage"]["can_net_meter"] = true
#     # d["ElectricStorage"]["can_wholesale"] = true
#     # d["PV"]["can_net_meter"] = false
#     # d["PV"]["can_wholesale"] = false
#     p = REoptInputs(d)
#     for exbin in [:WHL, :NEM]
#         @test exbin in p.export_bins_by_storage["ElectricStorage"]
#     end
#     @test !(:EXC in p.export_bins_by_storage["ElectricStorage"])
#     m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
#     results = run_reopt(m, p)
#     open("debug_results.json","w") do f
#         JSON.print(f, results, 4)
#     end
#     # @test results["PV"]["electric_to_grid_series_kw"]
#     @test sum(results["ElectricStorage"]["storage_to_grid_series_kw"]) > 0
#     @test all(x == 0.0 for (i,x) in enumerate(results["ElectricStorage"]["storage_to_grid_series_kw"]) if 8 < i % 24 < 17)
#     @test value(m[:NEM_benefit]) <= 0
#     @test value(m[:WHL_benefit]) ≈ 0.0 atol=1e-5
#     @test value(m[:EXC_benefit]) ≈ 0.0 atol=1e-5
#     @test results["ElectricTariff"]["year_one_export_benefit_before_tax"] >= 0
#     finalize(backend(m))
#     empty!(m)
#     GC.gc() 

#     # Case 2: whl rate > retail rate and allow_simultaneous_export_import = false
#     # so expect battery to wholesale once load is met
#     #TODO: have to limit PV size to get expected result?
#     d["ElectricStorage"]["can_net_meter"] = false
#     d["PV"]["can_net_meter"] = false
#     d["ElectricTariff"]["tou_energy_rates_per_kwh"] = repeat([0.1], 8760)
#     d["ElectricTariff"]["wholesale_rate"] = append!(repeat([5], 31*24), repeat([0], 8760 - 31*24))
#     d["ElectricUtility"]["allow_simultaneous_export_import"] = false
#     m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
#     results = run_reopt(m, d)
#     open("debug_results2.json","w") do f
#         JSON.print(f, results, 4)
#     end
#     @test all(x == 0.0 for (i,x) in enumerate(results["ElectricUtility"]["electric_to_load_series_kw"]) 
#                     if results["ElectricStorage"]["storage_to_grid_series_kw"][i] > 0)
#     @test sum(results["ElectricStorage"]["storage_to_grid_series_kw"]) > 0
#     @test value(m[:NEM_benefit]) == 0
#     @test value(m[:EXC_benefit]) == 0
#     @test results["ElectricTariff"]["year_one_export_benefit_before_tax"] >= 0
#     finalize(backend(m))
#     empty!(m)
#     GC.gc() 

#     # More testing of storage export inputs
#     # d["ElectricStorage"]["can_net_meter"] = true
#     # d["ElectricStorage"]["can_wholesale"] = true
#     d["ElectricStorage"]["can_export_beyond_nem_limit"] = true
#     p = REoptInputs(d)
#     println(p.export_bins_by_storage["ElectricStorage"])
#     for exbin in [:EXC, :WHL, :NEM]
#         @test exbin in p.export_bins_by_storage["ElectricStorage"]
#     end
#     d["ElectricStorage"]["can_net_meter"] = false
#     d["ElectricStorage"]["can_wholesale"] = false
#     d["ElectricStorage"]["can_export_beyond_nem_limit"] = false
#     p = REoptInputs(d)
#     @test isempty(p.export_bins_by_storage["ElectricStorage"])   
# end
