using TestItems
using TestItemRunner
@run_package_tests


@testitem "basic" begin
    using Dictionaries
    using FlexiMaps
    using StructArrays
    using DictArrays.UnionCollections

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
    dau = DictArray(coldict |> unioncollection)
    @test eltype(AbstractDictionary(da)) == AbstractVector
    @test eltype(AbstractDictionary(dau)) == Union{StepRangeLen{Int64, Int64, Int64, Int64}, Vector{Int64}, Vector{String}}

    @testset for da in (da, dau)
        @test AbstractDictionary(da) == coldict
        @test Dict(da)[:a1] === coldict[:a1]
        @test AbstractDictionary(DictArray(Dict(da)))[:a1] === coldict[:a1]

        @test length(da) == 100
        @test axes(da) == (Base.OneTo(100),)
        @test ndims(da) == 1
        @test IndexStyle(da) == IndexLinear()

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

        @test da[12] isa AbstractDictionary
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

    @test_broken (DictArray(); true)  # what should empty constructor do?
end

@testitem "nested" begin
    using StructArrays

    da = DictArray(a=1:3, b=collect(1.0:3.0), c=StructArray(d=1:3, e=collect(1.0:3.0)))
    @test da.c isa StructArray
    @test da.c.d === 1:3

    da = DictArray(a=1:3, b=collect(1.0:3.0), c=DictArray(d=1:3, e=collect(1.0:3.0)))
    @test da.c isa DictArray
    @test da.c.d === 1:3
end

@testitem "collection interface - 1d" begin
    using Dictionaries

    da = DictArray(a=1:3, b=collect(1.0:3.0))
    @test !isempty(da)
    @test length(da) == 3
    @test size(da) == (3,)
    @test valtype(typeof(da)) == valtype(da) == eltype(typeof(da)) == eltype(da) == AbstractDictionary{Symbol}
    @test keytype(da) == Int
    @test collect(da)::Vector{<:AbstractDictionary{Symbol}} == [Dictionary([:a, :b], [1, 1.0]), Dictionary([:a, :b], [2, 2.0]), Dictionary([:a, :b], [3, 3.0])]
    @test da[2] == Dictionary([:a, :b], [2, 2.0])
    @test first(da) == Dictionary([:a, :b], [1, 1.0])
    @test lastindex(da) == 3
    @test eachindex(da) == keys(da) == 1:3
    @test values(da) === da

    dai = da[1:2]
    @test dai isa DictArray
    @test dai.a === 1:2
    @test dai.b::Vector == [1.0, 2.0]
    @test length(dai) == 2

    dai = da[1:0]
    @test dai isa DictArray
    @test isempty(dai)
    @test collect(dai)::Vector{<:AbstractDictionary{Symbol}} == []

    dai = @view da[1:2]
    @test dai isa DictArray
    @test dai.a === 1:2
    @test dai.b::SubArray == [1.0, 2.0]
    @test length(dai) == 2

    @test only(@view da[1]) == da[1]

    @test (NamedTuple(da)::NamedTuple).a === da.a
    @test DictArray(NamedTuple(da)) == da
    @test DictArray(; NamedTuple(da)...) == da

    daf = filter(r -> r.a >= 2, da)
    @test daf == da[2:3]
end

@testitem "collection interface - nd" begin
    using Dictionaries

    da = DictArray(a=reshape(1:6, 2, 3), b=[1.0 3 5; 2 4 6])
    @test !isempty(da)
    @test length(da) == 6
    @test size(da) == (2, 3)
    @test valtype(da) == eltype(da) == AbstractDictionary{Symbol}
    @test keytype(da) == CartesianIndex{2}
    @test (collect(da)::Matrix{<:AbstractDictionary{Symbol}})[2, 3] == Dictionary([:a, :b], [6, 6.0])
    @test da[2] == Dictionary([:a, :b], [2, 2.0])
    @test first(da) == Dictionary([:a, :b], [1, 1.0])
    @test lastindex(da) == 6
    @test eachindex(da) === Base.OneTo(6)
    @test keys(da) === CartesianIndices((2, 3))
    @test_broken CartesianIndices(da) === keys(da)
    @test values(da) === da

    dai = da[1:2]
    @test dai isa DictArray
    @test dai.a == 1:2
    @test dai.b::Vector == [1.0, 2.0]
    @test length(dai) == 2

    dai = da[1:0]
    @test dai isa DictArray
    @test isempty(dai)
    @test collect(dai)::Vector{<:AbstractDictionary{Symbol}} == []

    dai = @view da[1:2]
    @test dai isa DictArray
    @test dai.a == 1:2
    @test dai.b::SubArray == [1.0, 2.0]
    @test length(dai) == 2

    @test (NamedTuple(da)::NamedTuple).a === da.a
    @test DictArray(NamedTuple(da)) == da
    @test DictArray(; NamedTuple(da)...) == da

    # daf = filter(r -> r.a >= 2, da)
    # @test daf == da[2:3]
end

@testitem "Flexi*" begin
    using FlexiMaps
    using FlexiMaps: MappedArray
    using FlexiGroups
    using FlexiJoins
    using StructArrays
    using Dictionaries
    using Accessors

    # non-resizeable arrays are broken now in eg flatten() - don't work
    # da = DictArray(a=1:3, b=collect(1.0:3.0))
    da = DictArray(a=[1, 2, 3], b=collect(1.0:3.0))

    dafm = filtermap(r -> r.a >= 2 ? (;r.a) : nothing, da)
    @test dafm == [(a=2,), (a=3,)]
    @test_broken dafm isa StructArray

    @testset "flatten" begin
        @test isempty(flatten([da][1:0]))
        @test flatten([da]) == da
        @test flatten([da, da]) == DictArray(a=[1, 2, 3, 1, 2, 3], b=[1.0, 2.0, 3.0, 1.0, 2.0, 3.0])
        @test_broken flatmap(r -> 1:r.a, da)
    end

    @testset "map, mapview" begin
        @test_broken mapview(r -> r.a, da) == [1, 2, 3]
        @test mapview(r -> r.a, da) |> collect == [1, 2, 3]
        @test mapview((@optic _.a), da) === da.a == [1, 2, 3]
        @test mapview((@optic _[:b]), da) === da.b == [1., 2, 3]
        @test mapview((@optic _.a ^ 2), da)::MappedArray{Int} == [1, 4, 9]

        # these are Base tests, not FlexiMaps - but putting here because similar to the above
        @test [1, 2, 3] == map((@optic _.a), da) !== da.a
        @test [1., 2, 3] == map((@optic _[:b]), da) !== da.b
        @test map((@optic _.a ^ 2), da)::Vector{Int} == [1, 4, 9]
    end

    @testset "group" begin
        # group() not supported yet

        G = groupview((@optic _.a), da)
        @test G isa Dictionary{Int, <:DictArray}
        @test G[1] == DictArray(a=[1], b=[1.0])

        G = groupview((@optic isodd(_.a)), da)
        @test G isa AbstractDictionary{Bool, <:DictArray}
        @test G[true] == DictArray(a=[1, 3], b=[1.0, 3.0])
        @test addmargins(G)[total] == DictArray(a=[1, 3, 2], b=[1.0, 3.0, 2.0])

        @test groupmap((@optic isodd(_.a)), length, da) == dictionary([true => 2, false => 1])
        @test groupmap((@optic isodd(_.a)), first, da) == dictionary([true => Dictionary([:a, :b], [1, 1.0]), false => Dictionary([:a, :b], [2, 2.0])])
    end

    @testset "join" begin
        @test_broken (innerjoin((da, da), by_key(:a)); true)
    end
end

@testitem "Accessors" begin
    using Accessors
    using AccessorsExtra  # for Dictionaries
    using DataPipes
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

    das = @p let
        da
        @set __.a2 = __.a1
        @set __.a3 = __.a1 .+ 0.5
        @delete __.b10
        @insert __.x = __.c5
        @insert __.y = map(Symbol ∘ string, __.c5)
    end
    @test das.a2 === das.a1 === da.a1
    @test !haskey(AbstractDictionary(das), :b10)
    @test das.x === das.c5

    das = @modify(c -> c .* 100, da |> Properties() |> If(c -> eltype(c) <: Number))
    @test das.a10 == 100 .* da.a10
    @test das.b5 === da.b5

    das = @set da[1].a10 = 100
    @test das[1].a10 == 100
    @test das[2].a10 == 20
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
    # Aqua.test_ambiguities(DictArrays)  # ambiguity with piracy from Indexing.jl

    import CompatHelperLocal as CHL
    CHL.@check()
end
