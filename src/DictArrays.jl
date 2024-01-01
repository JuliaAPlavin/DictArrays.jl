module DictArrays

using Dictionaries
using Indexing: getindices
using StructArrays
using DataAPI: Cols
using ConstructionBase
using Accessors
using DataPipes
using Tables
using FlexiMaps

export DictArray, Cols


struct VectorParted{T,PS<:Tuple} <: AbstractVector{T}
    parts::PS
    ix_to_partix::Vector{Tuple{Int,Int}}
end
VectorParted(parts, ix_to_partix) = VectorParted{Union{eltype.(parts)...}}(parts, ix_to_partix)
VectorParted{T}(parts, ix_to_partix) where {T} = VectorParted{T,typeof(parts)}(parts, ix_to_partix)

function _fromcontent(vals)
    types = unique(map(typeof, vals)) |> Tuple
    parts = map(T -> T[], types)
    ix_to_partix = map(vals) do v
        partix = findfirst(==(typeof(v)), types)
        push!(parts[partix], v)
        (partix, lastindex(parts[partix]))
    end |> collect
    return VectorParted(parts, ix_to_partix)
end

Base.@propagate_inbounds function Base.getindex(v::VectorParted, I::Int...)
    partix, ix_in_part = v.ix_to_partix[I...]
    return v.parts[partix][ix_in_part]
end

Base.size(v::VectorParted) = size(v.ix_to_partix)
Base.map(f, v::VectorParted) = @modify(v.parts) do ps
    map(p -> map(f, p), ps)
end

FlexiMaps.mapview(f, v::VectorParted) = @modify(v.parts) do ps
    map(p -> mapview(f, p), ps)
end

_any_element(v::VectorParted) = first(first(v.parts))


struct DictionaryParted{I,T,VT<:VectorParted{T}} <: AbstractDictionary{I,T}
    indices::Indices{I}
    values::VT
end

DictionaryParted(indices, values) = DictionaryParted(Indices(indices), _fromcontent(values))
DictionaryParted(dict::AbstractDictionary) = DictionaryParted(keys(dict), values(dict))

Base.keys(dict::DictionaryParted) = getfield(dict, :indices)
_values(dict::DictionaryParted) = getfield(dict, :values)
Accessors.set(dict::DictionaryParted, ::typeof(_values), values) = DictionaryParted(keys(dict), values)
Dictionaries.tokenized(dict::DictionaryParted) = _values(dict)
Dictionaries.istokenassigned(dict::DictionaryParted, (_slot, index)) = isassigned(_values(dict), index)
Dictionaries.istokenassigned(dict::DictionaryParted, index::Int) = isassigned(_values(dict), index)
Dictionaries.gettokenvalue(dict::DictionaryParted, (_slot, index)) = _values(dict)[index]
Dictionaries.gettokenvalue(dict::DictionaryParted, index::Int) = _values(dict)[index]

Base.map(f, d::DictionaryParted) = @modify(vs -> map(f, vs), _values(d))
FlexiMaps.mapview(f, d::DictionaryParted) = @modify(vs -> mapview(f, vs), _values(d))

_any_element(d::DictionaryParted) = _any_element(_values(d))


# https://github.com/andyferris/Dictionaries.jl/pull/43
Base.propertynames(d::AbstractDictionary) = keys(d)
Base.@propagate_inbounds Base.getproperty(d::D, s::Symbol) where {D<:AbstractDictionary} = hasfield(D, s) ? getfield(d, s) : d[s]
Base.@propagate_inbounds function Base.setproperty!(d::D, s::Symbol, x) where {D<:AbstractDictionary}
    hasfield(D, s) && return setfield!(d, s, x)
    d[s] = x
    return x
end
ConstructionBase.setproperties(obj::AbstractDictionary, patch::NamedTuple) = merge(obj, Dictionary(keys(patch), values(patch)))


struct DictArray{T,VT}
    dct::DictionaryParted{Symbol,T,VT}

    # so that we don't have DictArray(::Any) that gets overriden below
    function DictArray(dct::DictionaryParted{Symbol,T,VT}) where {T,VT}
        @assert all(isequal(axes(_any_element(dct))) ∘ axes, dct)
        new{T,VT}(dct)
    end
end

DictArray(d::AbstractDictionary) = @p let
    d
    map(convert(AbstractArray, _))
    @aside @assert __ isa AbstractDictionary{Symbol}
    DictionaryParted()
    DictArray()
end
DictArray(d::AbstractDict) = DictArray(DictionaryParted(keys(d), values(d)))
DictArray(d::NamedTuple) = DictArray(DictionaryParted(keys(d), values(d)))
DictArray(; kwargs...) = DictArray(values(kwargs))
DictArray(tbl) = @p let
    tbl
    Tables.dictcolumntable()
    DictionaryParted(Tables.columnnames(__), Tables.columns(__))
    DictArray()
end

for f in (:isempty, :length, :size, :firstindex, :lastindex, :eachindex, :keys, :keytype)
    @eval Base.$f(da::DictArray) = $f(_any_element(AbstractDictionary(da)))
end
Base.axes(da::DictArray, args...) = axes(_any_element(AbstractDictionary(da)), args...)
Base.valtype(::Type{<:DictArray}) = AbstractDictionary{Symbol}
Base.valtype(::DictArray) = AbstractDictionary{Symbol}
Base.eltype(::Type{<:DictArray}) = AbstractDictionary{Symbol}
Base.@propagate_inbounds function Base.getindex(da::DictArray, I::Union{Integer,CartesianIndex}...)
    @boundscheck checkbounds(Bool, da, I...)
    map(a -> @inbounds(a[I...]), AbstractDictionary(da))
end
Base.@propagate_inbounds function Base.getindex(da::DictArray, I::AbstractVector{<:Integer})
    @boundscheck checkbounds(Bool, da, I)
    @modify(dct -> map(a -> @inbounds(a[I]), dct), AbstractDictionary(da))
end
Base.@propagate_inbounds function Base.view(da::DictArray, I::Integer...)
    @boundscheck checkbounds(Bool, da, I...)
    map(a -> @inbounds(view(a, I...)), AbstractDictionary(da))
end
Base.@propagate_inbounds function Base.view(da::DictArray, I::AbstractVector{<:Integer})
    @boundscheck checkbounds(Bool, da, I)
    @modify(dct -> map(a -> @inbounds(view(a, I)), dct), AbstractDictionary(da))
end

Base.checkbounds(::Type{Bool}, da::DictArray, I...) = checkbounds(Bool, _any_element(AbstractDictionary(da)), I...)
Base.first(da::DictArray) = map(first, AbstractDictionary(da))
Base.last(da::DictArray) = map(last, AbstractDictionary(da))
Base.values(da::DictArray) = da

Base.similar(da::DictArray, ::Type{T}) where {T} = similar(Array{T}, axes(da))
Base.similar(da::DictArray, ::Type{<:Union{NamedTuple,AbstractDict,AbstractDictionary}}) = error("Reserved: what exactly this should mean?")
Base.copy(da::DictArray) = @modify(copy, AbstractDictionary(da) |> Elements())

function Base.append!(a::DictArray, b::DictArray)
    @assert propertynames(a) == propertynames(b)
    for k in propertynames(a)
        append!(AbstractDictionary(a)[k], AbstractDictionary(b)[k])
    end
    return a
end

Base.iterate(::DictArray) = error("Iteration deliberately not supported to avoid triggering fallbacks that perform poorly for type-unstable DictArrays.")

Base.propertynames(da::DictArray) = collect(keys(AbstractDictionary(da)))
Base.getproperty(da::DictArray, i::Symbol) = getproperty(AbstractDictionary(da), i)
function Base.getindex(da::DictArray, i::Cols{<:Tuple{Vararg{Symbol}}})
    cspec = NamedTuple{i.cols}(i.cols)
    cols = getindices(AbstractDictionary(da), cspec)::NamedTuple
    StructArray(cols)
end
Base.getindex(da::DictArray, i::Cols{<:Tuple{Tuple{Vararg{Symbol}}}}) = da[Cols(only(i.cols)...)]
Base.getindex(da::DictArray, i::Cols{<:Tuple{AbstractVector{Symbol}}}) = 
    @modify(AbstractDictionary(da)) do dct
        getindices(dct, Indices(only(i.cols)))
    end
Base.getindex(da::DictArray, i::Cols) = error("Not supported")

Dictionaries.AbstractDictionary(da::DictArray) = getfield(da, :dct)
Dictionaries.Dictionary(da::DictArray) = Dictionary(AbstractDictionary(da))  # remove?
Base.Dict(da::DictArray) = Dict(pairs(AbstractDictionary(da)))
Base.NamedTuple(da::DictArray) = (; pairs(AbstractDictionary(da))...)
StructArrays.StructArray(da::DictArray) = da[Cols(keys(AbstractDictionary(da))...)]
Base.collect(da::DictArray)::AbstractArray{AbstractDictionary{Symbol}} = map(i -> da[i], keys(da))

Base.merge(da::DictArray, args::AbstractDictionary...) = DictArray(merge(AbstractDictionary(da), args...))
Base.merge(da::DictArray, args...) = merge(da, map(Dictionary, args)...)

Base.:(==)(a::DictArray, b::DictArray) = AbstractDictionary(a) == AbstractDictionary(b)

Base.filter(f, da::DictArray) = da[map(f, da)]

function Base.map(f, da::DictArray)
    t = tracedkeys(first(da))
    fres = f(t)
    _map(f, da, Cols(_accessed(t)...))
end
    
function _map(f, da::DictArray, cols::Cols)
    try
        map(f, da[cols])
    catch e
        e isa ErrorException || rethrow()
        m = match(r"has no field (\w+)$", e.msg)
        isnothing(m) && rethrow()
        return _map(f, da, Cols(cols.cols..., Symbol(m.captures[1])))
    end
end


struct TracedKeys
    dct::AbstractDictionary{Symbol, <:Any}
    accessed::Vector{Symbol}
end

tracedkeys(dct) = TracedKeys(dct, [])
_dct(t::TracedKeys) = getfield(t, :dct)
_accessed(t::TracedKeys) = unique(__accessed(t))
__accessed(t::TracedKeys) = getfield(t, :accessed)

Base.getproperty(t::TracedKeys, i::Symbol) = t[i]
function Base.getindex(t::TracedKeys, i::Symbol)
    push!(__accessed(t), i)
    _dct(t)[i]
end
function Base.getindex(t::TracedKeys, i::Tuple{Vararg{Symbol}})
    append!(__accessed(t), i)
    NamedTuple{i}(getindices(_dct(t), i))
end
Base.merge(nt::NamedTuple, t::TracedKeys) = merge(nt, t[Tuple(keys(_dct(t)))])


ConstructionBase.setproperties(da::DictArray, patch::NamedTuple) = merge(da, patch)
Accessors.set(da::DictArray, ::Type{AbstractDictionary}, val::AbstractDictionary) = DictArray(val)
Accessors.delete(da::DictArray, ::PropertyLens{P}) where {P} = @delete AbstractDictionary(da)[P]
Accessors.insert(da::DictArray, ::PropertyLens{P}, val) where {P} = @insert AbstractDictionary(da)[P] = val
Accessors.mapproperties(f, da::DictArray) = @modify(f, AbstractDictionary(da) |> Elements())

function Accessors.setindex(da::DictArray, val::AbstractDictionary{Symbol}, I::Integer...)
    @assert keys(AbstractDictionary(da)) == keys(val)
    @modify(AbstractDictionary(da)) do cols
        map(cols, val) do col, v
            @set col[I...] = v
        end
    end
end


Tables.istable(::Type{<:DictArray}) = true
Tables.columnaccess(::Type{<:DictArray}) = true
Tables.columns(da::DictArray) = da
Tables.schema(da::DictArray) = Tables.Schema(collect(keys(AbstractDictionary(da))), collect(map(eltype, AbstractDictionary(da))))


## fast-path for map(), and support for mapview():

Base.map(f::PropertyLens, da::DictArray) = map(identity, f(da))
Base.map(f::IndexLens{Tuple{Symbol}}, da::DictArray) = map(identity, f(Dictionary(da)))
function Base.map(f::ComposedFunction, da::DictArray)
    fs = Accessors.decompose(f)
    map(Accessors.compose(Base.front(fs)...), mapview(last(fs), da))
end

FlexiMaps.mapview(f::PropertyLens, da::DictArray) = f(da)
FlexiMaps.mapview(f::IndexLens{Tuple{Symbol}}, da::DictArray) = f(Dictionary(da))
function FlexiMaps.mapview(f::ComposedFunction, da::DictArray)
    fs = Accessors.decompose(f)
    mapview(Accessors.compose(Base.front(fs)...), mapview(last(fs), da))
end

# disambiguation:
FlexiMaps.mapview(p::Union{Symbol,Int,String}, A::VectorParted) = mapview(PropertyLens(p), A)
FlexiMaps.mapview(p::Union{Symbol,Int,String}, A::DictionaryParted) = mapview(PropertyLens(p), A)

# for flatten() to work:
FlexiMaps._similar_with_content_sameeltype(da::DictArray) = copy(da)

end
