"""
This scratch space can be used for development of new tests. Delete tests that are not longer needed.
    Run these tests by spinning up the Julia REPL from the test folder environment, and then:
    push!(ARGS, "Dev")
    include("runtests.jl")

    or this (but this often fails with "cannot merge projects" due to dependency compatibility issues)
    using Pkg
    Pkg.test("REopt"; test_args=["Dev"])
"""