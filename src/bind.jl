
@inline function check_bind_bounds(stmt::Stmt, pos::Integer)
    @assert pos > 0 && pos <= stmt.bind_count "Bind position $pos out of bounds."
end

@inline function check_bind_bounds(stmt::Stmt, name::AbstractString)
    name_upper = uppercase(name)
    @assert haskey(stmt.bind_names_index, name_upper) "Bind name $name_upper not found in statement."
end

@inline check_bind_bounds(stmt::Stmt, name::Symbol) = check_bind_bounds(stmt, string(name))

const NameOrPositionTypes = Union{Integer, String, Symbol}

#
# Bind Variable to Stmt
#

@inline function Base.setindex!(stmt::Stmt, value::Variable, name_or_position::NameOrPositionTypes)
    bind!(stmt, value, name_or_position)
end

@generated function bind!(stmt::Stmt, variable::Variable, name_or_position::K) where {K<:NameOrPositionTypes}

    if name_or_position <: Integer
        name_or_position_exp = :(UInt32(name_or_position))
        bind_function_name = :dpiStmt_bindByPos
    elseif name_or_position <: Symbol
        name_or_position_exp = :(string(name_or_position))
        bind_function_name = :dpiStmt_bindByName
    elseif name_or_position <: String
        name_or_position_exp = :name_or_position
        bind_function_name = :dpiStmt_bindByName
    else
        error("Unsupported type for argument `name_or_position`: $name_or_position.")
    end

    return quote
        key = $name_or_position_exp
        check_bind_bounds(stmt, key)
        result = $(bind_function_name)(stmt.handle, key, variable.handle)
        error_check(context(stmt), result)
        nothing
    end
end

#
# Bind Value to Stmt
#

@generated function bind!(stmt::Stmt, value::JuliaOracleValue{O,N}, name_or_position::K) where {K<:NameOrPositionTypes,O,N}

    # https://github.com/oracle/odpi/issues/99
    if O == ORA_ORACLE_TYPE_TIMESTAMP_TZ || O == ORA_ORACLE_TYPE_TIMESTAMP_LTZ
        error("Can't bind Timestamp with TimeZone directly to Statement. Use a Variable instead.")
    end

    if O == ORA_ORACLE_TYPE_RAW || O == ORA_ORACLE_TYPE_LONG_RAW
        error("Can't bind RAW data type directly to Statement. Use a Variable instead.")
    end

    if name_or_position <: Integer
        name_or_position_exp = :(UInt32(name_or_position))
        bind_function_name = :dpiStmt_bindValueByPos
    elseif name_or_position <: Symbol
        name_or_position_exp = :(string(name_or_position))
        bind_function_name = :dpiStmt_bindValueByName
    elseif name_or_position <: String
        name_or_position_exp = :name_or_position
        bind_function_name = :dpiStmt_bindValueByName
    else
        error("Unsupported type for argument `name_or_position`: $name_or_position.")
    end

    return quote
        key = $name_or_position_exp
        check_bind_bounds(stmt, key)
        data_ref = Ref{OraData}()
        set_oracle_value_at!(value, value[], data_ref)
        result = $(bind_function_name)(stmt.handle, key, N, data_ref)
        error_check(context(stmt), result)
        nothing
    end
end

@inline function Base.setindex!(stmt::Stmt, value::JuliaOracleValue, name_or_position::N) where {N<:NameOrPositionTypes}
    bind!(stmt, value, name_or_position)
end

@inline function Base.setindex!(stmt::Stmt, value::T, name_or_position::N) where {T, N<:NameOrPositionTypes}
    bind!(stmt, JuliaOracleValue(value), name_or_position)
end

#
# Bind Value through an implicitly created Variable
#
# ODPI-C refuses to bind RAW, LOB and TIMESTAMP WITH TIME ZONE values directly
# to a statement (see https://github.com/oracle/odpi/issues/99), so those go
# through a `Variable` that the statement keeps alive until it is released.
#

function bind_through_variable!(stmt::Stmt, value, name_or_position::NameOrPositionTypes,
                                ::Type{T}, oracle_type::OraOracleTypeNum,
                                native_type::OraNativeTypeNum;
                                max_byte_string_size::Integer=4000) where {T}
    variable = Variable(stmt.connection, T, oracle_type, native_type,
                        buffer_capacity=1, max_byte_string_size=max_byte_string_size)
    variable[1] = value
    bind!(stmt, variable, name_or_position)
    push!(stmt.bound_resources, variable)
    nothing
end

function bind_temp_lob!(stmt::Stmt, data, name_or_position::NameOrPositionTypes,
                        lob_type::OraOracleTypeNum)
    lob = Lob(stmt.connection, lob_type)
    write(lob, data)
    push!(stmt.bound_resources, lob)
    bind_through_variable!(stmt, lob, name_or_position, Lob, lob_type, ORA_NATIVE_TYPE_LOB)
end

# `RAW` holds at most 2000 bytes; anything longer is sent as a temporary `BLOB`.
const MAX_RAW_SIZE = 2000

function Base.setindex!(stmt::Stmt, value::Vector{UInt8}, name_or_position::NameOrPositionTypes)
    if length(value) <= MAX_RAW_SIZE
        bind_through_variable!(stmt, value, name_or_position, Vector{UInt8},
                               ORA_ORACLE_TYPE_RAW, ORA_NATIVE_TYPE_BYTES,
                               max_byte_string_size=max(length(value), 1))
    else
        bind_temp_lob!(stmt, value, name_or_position, ORA_ORACLE_TYPE_BLOB)
    end
end

# EXPERIMENTAL: bound as `RAW(16)` in big-endian (RFC 4122) byte order.
function Base.setindex!(stmt::Stmt, value::UUID, name_or_position::NameOrPositionTypes)
    bind_through_variable!(stmt, uuid_bytes(value), name_or_position, Vector{UInt8},
                           ORA_ORACLE_TYPE_RAW, ORA_NATIVE_TYPE_BYTES,
                           max_byte_string_size=16)
end

# `VARCHAR2` bind buffers hold at most 4000 bytes; longer strings are sent as a temporary `CLOB`.
const MAX_VARCHAR_SIZE = 4000

function Base.setindex!(stmt::Stmt, value::String, name_or_position::NameOrPositionTypes)
    if sizeof(value) <= MAX_VARCHAR_SIZE
        bind!(stmt, JuliaOracleValue(value), name_or_position)
    else
        bind_temp_lob!(stmt, value, name_or_position, ORA_ORACLE_TYPE_CLOB)
    end
end

function Base.setindex!(stmt::Stmt, value::TimestampTZ{L}, name_or_position::NameOrPositionTypes) where {L}
    oracle_type = L ? ORA_ORACLE_TYPE_TIMESTAMP_LTZ : ORA_ORACLE_TYPE_TIMESTAMP_TZ
    bind_through_variable!(stmt, value, name_or_position, TimestampTZ{L},
                           oracle_type, ORA_NATIVE_TYPE_TIMESTAMP)
end

function Base.setindex!(stmt::Stmt, value::Lob{O}, name_or_position::NameOrPositionTypes) where {O}
    bind_through_variable!(stmt, value, name_or_position, Lob, O, ORA_NATIVE_TYPE_LOB)
end

# Oracle has a single numeric type, so narrower Julia numbers are widened before binding.
@inline Base.setindex!(stmt::Stmt, value::Union{Int8, Int16, Int32, UInt8, UInt16, UInt32}, name_or_position::NameOrPositionTypes) =
    bind!(stmt, JuliaOracleValue(Int64(value)), name_or_position)

@inline Base.setindex!(stmt::Stmt, value::Union{Float16, Float32}, name_or_position::NameOrPositionTypes) =
    bind!(stmt, JuliaOracleValue(Float64(value)), name_or_position)

@inline function Base.setindex!(stmt::Stmt, ::Missing, name_or_position::N) where {N<:NameOrPositionTypes}
    error("Cannot bind missing value to statement without type information. Use `stmt[pos, julia_type] = value` or `stmt[pos, oracle_type, native_type] = value`.")
end

@inline function Base.setindex!(stmt::Stmt, ::Missing, name_or_position::N, oracle_type::OraOracleTypeNum, native_type::OraNativeTypeNum) where {N<:NameOrPositionTypes}
    val = JuliaOracleValue(oracle_type, native_type, Missing)
    val[] = missing
    bind!(stmt, val, name_or_position)
end

@inline function Base.setindex!(stmt::Stmt, m::Missing, name_or_position::N, ::Type{T}) where {T,N<:NameOrPositionTypes}
    ott = infer_oracle_type_tuple(T)
    setindex!(stmt, m, name_or_position, ott.oracle_type, ott.native_type)
end
