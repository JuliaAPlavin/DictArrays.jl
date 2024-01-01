using TestItems
using TestItemRunner
@run_package_tests


@testitem "basic" begin
    using Dictionaries
    using FlexiMaps
    using StructArrays

    Nrow = 10^2
    Ncol = 10^3
    coldict = dictionary(flatmap(1:Ncol) do ci
        [
            Symbol(:a, ci) => ci .* (1:Nrow),
            Symbol(:b, ci) => ["str_$i" for i in ci .* (1:Nrow)],
            Symbol(:c, ci) => collect(ci .* (1:Nrow)),
        ]	
    end)
    da = DictArray(coldict)
    @test Dictionary(da) === coldict

    @test da.a1 === 1 .* (1:Nrow)
    
    da1 = da[Cols([:a1, :b10, :c30])]
    @test da1 isa DictArray
    @test da1[12] == dictionary([:a1=>12, :b10=>"str_$(10*12)", :c30=>30*12])
    @test da1.a1 === da.a1

    sa1 = da[Cols((:a1, :b10, :c30))]
    @test sa1 isa StructArray
    @test isconcretetype(eltype(sa1))
    @test sa1[12] === (a1=12, b10="str_$(10*12)", c30=30*12)
    @test sa1.a1 == da.a1

    @test da[12] isa Dictionary
    @test da[12].a10 == 10*12
    @test da[12].b40 == "str_$(40*12)"
    @test first(da).c20 == 20

    a = map(r -> r.a10, da)
    @test a isa Vector{Int}
    @test a[12] == 10*12
    a = map(r -> r.a10 > 10 ? r.b3 : r.b38, da)
    @test a isa Vector{String}
    @test a[12] == "str_$(3*12)"

    @test first(map(r -> r[:a1] * r[:c9], da)::Vector{Int}) == 9
    
    sa = map(r -> r[(:a1, :b10, :c30)], da)
    @test sa isa StructArray
    @test isconcretetype(eltype(sa))
    @test sa[12] === (a1=12, b10="str_$(10*12)", c30=30*12)
    @test sa.a1 == da.a1
    @test sa.a1 !== da.a1
end


@testitem "_" begin
    import Aqua
    Aqua.test_all(DictArrays; ambiguities=false)
    Aqua.test_ambiguities(DictArrays)

    import CompatHelperLocal as CHL
    CHL.@check()
end
