# DBInterface compatibility layer for Oracle.jl
# Following the proven wrapper struct pattern from LibPQ.jl

import DBInterface

struct ProcedureResult
    cursors::Vector{ResultSet}
end

Base.length(result::ProcedureResult) = length(result.cursors)
Base.getindex(result::ProcedureResult, index::Integer) = result.cursors[index]
Base.iterate(result::ProcedureResult, state...) = iterate(result.cursors, state...)

"""
    DBConnection <: DBInterface.Connection

Wrapper around Oracle.Connection that implements the DBInterface standard.
This follows the pattern used by LibPQ.jl for database abstraction.
"""
struct DBConnection <: DBInterface.Connection
    conn::Connection
end

"""
    DBInterface.connect(::Type{Connection}, args...; kwargs...) -> DBConnection

Connect to Oracle database via DBInterface.
"""
function DBInterface.connect(::Type{Connection}, args...; kwargs...)
    return DBConnection(Connection(args...; kwargs...))
end

"""
    DBInterface.prepare(conn::DBConnection, sql::AbstractString) -> Statement

Prepare an SQL statement for execution.
"""
function DBInterface.prepare(conn::DBConnection, sql::AbstractString)
    return Stmt(conn.conn, sql)
end

function execute_procedure(conn::DBConnection, sql::AbstractString;
                           params=NamedTuple(), out_cursors=())
    stmt = Stmt(conn.conn, sql)
    variables = Variable[]
    try
        for (name, value) in pairs(params)
            stmt[name] = value
        end
        for name in out_cursors
            variable = Variable(conn.conn, Any, ORA_ORACLE_TYPE_STMT, ORA_NATIVE_TYPE_STMT)
            stmt[name] = variable
            push!(variables, variable)
        end

        execute(stmt)
        results = ResultSet[]
        for variable in variables
            cursor_stmt = get_returned_statement(variable)
            try
                push!(results, fetch_all!(cursor_stmt))
            finally
                destroy!(cursor_stmt)
            end
        end
        return ProcedureResult(results)
    finally
        destroy!(stmt)
        for variable in variables
            destroy!(variable)
        end
    end
end

execute_procedure(conn::Connection, sql::AbstractString; kwargs...) =
    execute_procedure(DBConnection(conn), sql; kwargs...)

"""
    DBInterface.execute(conn::DBConnection, sql::AbstractString; kwargs...) -> ResultSet

Execute SQL statement directly via connection.
"""
function DBInterface.execute(conn::DBConnection, sql::AbstractString; kwargs...)
    stmt = Stmt(conn.conn, sql)
    try
        return execute_and_fetch_all!(stmt)
    finally
        close(stmt)
        destroy!(stmt)
    end
end

bind_param!(stmt::Stmt, position::Integer, value) = stmt[position] = value

# A positional NULL carries no type, so bind it as a NULL string and let Oracle convert.
bind_param!(stmt::Stmt, position::Integer, ::Missing) =
    stmt[position, ORA_ORACLE_TYPE_VARCHAR, ORA_NATIVE_TYPE_BYTES] = missing

"""
    DBInterface.execute(conn::DBConnection, sql::AbstractString, params; kwargs...) -> ResultSet

Execute SQL statement with parameters.
"""
function DBInterface.execute(conn::DBConnection, sql::AbstractString, params; kwargs...)
    stmt = Stmt(conn.conn, sql)
    try
        for (i, param) in enumerate(params)
            bind_param!(stmt, i, param)
        end
        return execute_and_fetch_all!(stmt)
    finally
        close(stmt)
        destroy!(stmt)
    end
end

"""
    DBInterface.execute(stmt::Stmt; kwargs...) -> ResultSet

Execute a prepared statement.
"""
function DBInterface.execute(stmt::Stmt; kwargs...)
    return execute_and_fetch_all!(stmt)
end

"""
    DBInterface.execute(stmt::Stmt, params; kwargs...) -> ResultSet

Execute prepared statement with parameters.
"""
function DBInterface.execute(stmt::Stmt, params; kwargs...)
    for (i, param) in enumerate(params)
        bind_param!(stmt, i, param)
    end
    return execute_and_fetch_all!(stmt)
end

"""
    DBInterface.close!(conn::DBConnection)

Close connection.
"""
DBInterface.close!(conn::DBConnection) = close(conn.conn)

"""
    DBInterface.close!(stmt::Stmt)

Close statement.
"""
function DBInterface.close!(stmt::Stmt)
    close(stmt)
    destroy!(stmt)
end

# Compatibility layer: also support methods on native Oracle.Connection
# to allow FunSQL to work with both DBConnection and raw Connection objects

"""
    DBInterface.prepare(conn::Connection, sql::AbstractString) -> Stmt

Prepare an SQL statement on native Oracle.Connection.
"""
function DBInterface.prepare(conn::Connection, sql::AbstractString)
    return Stmt(conn, sql)
end

"""
    DBInterface.execute(conn::Connection, sql::AbstractString; kwargs...) -> ResultSet

Execute SQL directly on native Oracle.Connection.
"""
function DBInterface.execute(conn::Connection, sql::AbstractString; kwargs...)
    stmt = Stmt(conn, sql)
    try
        return execute_and_fetch_all!(stmt)
    finally
        close(stmt)
        destroy!(stmt)
    end
end
