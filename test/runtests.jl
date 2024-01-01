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
    @test Dict(da)[:a1] === coldict[:a1]
    @test Dictionary(DictArray(Dict(da)))[:a1] === coldict[:a1]

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

    @test first(map(r -> r[:a1] * r[:c9] + r[:a1], da)::Vector{Int}) == 10
    
    sa = map(r -> r[(:a1, :b10, :c30)], da)
    @test sa isa StructArray
    @test isconcretetype(eltype(sa))
    @test sa[12] === (a1=12, b10="str_$(10*12)", c30=30*12)
    @test sa.a1 == da.a1
    
    sa = map(r -> (; a=r.a1, b=r.b10, c=r.c30), da)
    @test sa[12] === (a=12, b="str_$(10*12)", c=30*12)

    sa = map(r -> (; r[(:a1, :b10, :c30)]..., x=r.a3 + r.c5), da)
    @test sa isa StructArray
    @test isconcretetype(eltype(sa))
    @test sa[12] === (a1=12, b10="str_$(10*12)", c30=30*12, x=3*12+5*12)

    da1 = da[Cols([:a1, :b10, :c30])]::DictArray
    sa = map(r -> (; r..., x=r.a1 + r.c30), da1)
    @test sa isa StructArray
    @test isconcretetype(eltype(sa))
    @test sa[12] === (a1=12, b10="str_$(10*12)", c30=30*12, x=1*12+30*12)
end

@testitem "Tables" begin
    using Tables
    using CSV
    using StructArrays

    da = CSV.read(IOBuffer("a,b,c\n1,2,3\n4,5,6\n7,8,9\n"), DictArray)
    @test da isa DictArray
    @test da.a == [1, 4, 7]
    sa = StructArray(da)
    @test sa isa StructArray
    @test isconcretetype(eltype(sa))
    @test sa == [(a=1, b=2, c=3), (a=4, b=5, c=6), (a=7, b=8, c=9)]
    @test sa === da[Cols((:a, :b, :c))]
    das = DictArray(sa)
    @test das == da
    @test das.a === da.a

    @test Tables.rowtable(da)::Vector == [(a=1, b=2, c=3), (a=4, b=5, c=6), (a=7, b=8, c=9)]
    @test Tables.columntable(da) == (a=[1, 4, 7], b=[2, 5, 8], c=[3, 6, 9])
end


@testitem "_" begin
    import Aqua
    Aqua.test_all(DictArrays; ambiguities=false)
    Aqua.test_ambiguities(DictArrays)

    import CompatHelperLocal as CHL
    CHL.@check()
end
