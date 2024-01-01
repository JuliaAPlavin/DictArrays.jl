module DictArrays

using Dictionaries
using Indexing: getindices
using StructArrays
using DataAPI: Cols

export DictArray, Cols


Base.@propagate_inbounds Base.getproperty(d::D, s::Symbol) where {D<:AbstractDictionary} = hasfield(D, s) ? getfield(d, s) : d[s]
Base.@propagate_inbounds function Base.setproperty!(d::D, s::Symbol, x) where {D<:AbstractDictionary}
    hasfield(D, s) && return setfield!(d, s, x)
    d[s] = x
    return x
end


struct DictArray
    dct::Dictionary{Symbol, <:AbstractVector}
end

Base.length(da::DictArray) = length(first(Dictionary(da)))
Base.getindex(da::DictArray, i) = map(a -> a[i], Dictionary(da))
Base.first(da::DictArray) = map(first, Dictionary(da))

Base.getproperty(da::DictArray, i::Symbol) = Dictionary(da)[i]
function Base.getindex(da::DictArray, i::Cols{<:Tuple{Vararg{Symbol}}})
    ckeys = i.cols
    cvals = getindices(Dictionary(da), ckeys)
    StructArray(NamedTuple{ckeys}(cvals))
end
Base.getindex(da::DictArray, i::Cols{<:Tuple{Tuple{Vararg{Symbol}}}}) = da[Cols(only(i.cols)...)]
Base.getindex(da::DictArray, i::Cols{<:Tuple{AbstractVector{Symbol}}}) = DictArray(getindices(Dictionary(da), Indices(only(i.cols))))
Base.getindex(da::DictArray, i::Cols) = error("Not supported")

Dictionary(da::DictArray) = getfield(da, :dct)
Base.collect(da::DictArray) = map(i -> da[i], 1:length(da))

function Base.map(f, da::DictArray)
    t = tracedkeys(first(da))
    fres = f(t)
    _map(f, da, Cols(_accessed(t)...))
end
    
function _map(f, da::DictArray, cols::Cols)
    try
        map(da[cols]) do r
            try
                f(r)
            catch e
                e isa ErrorException || rethrow()
                m = match(r"has no field (\w+)$", e.msg)
                isnothing(m) && rethrow()
                throw(_map(f, da, Cols(cols.cols..., Symbol(m.captures[1]))))
            end
        end
    catch e
        e isa Exception && rethrow()
        return e
    end
end


struct TracedKeys
    dct::Dictionary{Symbol, <:Any}
    accessed::Vector{Symbol}
end

tracedkeys(dct) = TracedKeys(dct, [])
_dct(t::TracedKeys) = getfield(t, :dct)
_accessed(t::TracedKeys) = getfield(t, :accessed)

Base.getproperty(t::TracedKeys, i::Symbol) = t[i]
Base.getindex(t::TracedKeys, i::Symbol) = (push!(_accessed(t), i); _dct(t)[i])
Base.getindex(t::TracedKeys, i::Tuple{Vararg{Symbol}}) = (append!(_accessed(t), i); getindices(_dct(t), i))

end
