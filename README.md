# DictArrays.jl

Dictionary-based arrays, useful to represent wide heterogeneous tables and enjoy the familiar Julia collection interface.

# Motivation

Similar to `StructArrays`, but doesn't encode all column types in the table type. Compilation is fast even for tables with hundreds of columns.
```julia
# 1000 columns - almost instant
julia> da = @time DictArray(Dictionary(Symbol.(:a, 1:10^3), fill(1:1, 10^3)))
  0.001211 seconds (5.50 k allocations: 313.422 KiB)

# StructArrays struggle:
julia> @time StructArray(da);
  7.496190 seconds (626.85 k allocations: 37.730 MiB, 0.30% gc time, 99.52% compilation time)

# DictArray compilation doesn't depend on the number of columns
# even absurd hundreds of thousands of columns are fine:
julia> @time DictArray(Dictionary(Symbol.(:a, 1:10^5), [fill(1:1, 2*10^4); fill([1.], 2*10^4); fill([:a], 2*10^4); fill(["a"], 2*10^4); fill([false], 2*10^4)]))
  0.228542 seconds (878.81 k allocations: 39.484 MiB, 11.63% gc time, 52.54% compilation time)
```
Common Julia functions such as `map` and `filter` work, and are performant for long and wide tables despite the inherent type-instability:
```julia
julia> da = DictArray(a=1:10^6, b=collect(1.0:10^6), c=fill("hello", 10^6));

# DictArray
julia> @btime map(x -> x.a + x.b, $da)
  1.430 ms (300 allocations: 7.65 MiB)

# baseline: StructArray
# basically the same timings
julia> @btime map(x -> x.a + x.b, $(StructArray(da)))
  1.314 ms (2 allocations: 7.63 MiB)

# baseline: plain Vector of Dictionaries
# orders of magnitude slower, many allocations
julia> @btime map(x -> x.a + x.b, $(collect(da)))
  100.512 ms (1000022 allocations: 22.89 MiB)
```

# Usage

## Array-like

`DictArrays` follow array-like collection interfaces. They are not `AbstractArrays` though: this is a deliberate decision so that not to trigger generic `AbstractArray` fallbacks anywhere. Type instability is fundamental to the design, and requires explicit function barriers for performance.

Still, lots of common functionality works as you would expect for an array of `NamedTuple`s: `length(da)`, `da[5]`, `da[5].colname`, `keys(da)`, `map`, `filter`, and others. `StructArray`-like behavior is also available with the same semantics: most notably, `da.colname` to retrieve the whole column.

## Tables

`DictArray` is a `Tables.jl`-compatible table type. It can be constructed from a table, or passed anywhere a table is expected.
```julia
julia> da = CSV.read(IOBuffer("a,b,c\n1,2,3\n4,5,6\n7,8,9\n"), DictArray)
DictArray({:a = [1, 4, 7], :b = [2, 5, 8], :c = [3, 6, 9]})

julia> da.a
3-element Vector{Int64}:
 1
 4
 7

julia> Tables.rowtable(da)
3-element Vector{NamedTuple{(:a, :b, :c), Tuple{Int64, Int64, Int64}}}:
 (a = 1, b = 2, c = 3)
 (a = 4, b = 5, c = 6)
 (a = 7, b = 8, c = 9)
```

## More

Conversion:
- `Dictionary(da)` retrieves the underlying dictionary of columns
- `Dict(da)`, `NamedTuple(da)` convert to the corresponding type
- `StructArray(da)` converts to a `StructArray` of `NamedTuples` without copying columns

Modification: uses `Accessors`, same interface as `StructArray`.
- `@set da.colname = 1:length(da)` replace a column
- `@insert da.colname = ...` insert a new column
- `@delete da.colname` delete a column
- `Properties()` are supported. Eg, normalize all numeric columns:
```julia
@modify(da |> Properties() |> If(c -> eltype(c) <: Number)) do col
    col .- mean(col)
end
```
