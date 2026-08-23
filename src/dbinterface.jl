# DBInterface compatibility layer for Oracle.jl
# Following the proven wrapper struct pattern from LibPQ.jl

import DBInterface

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

"""
    DBInterface.execute(conn::DBConnection, sql::AbstractString, params; kwargs...) -> ResultSet

Execute SQL statement with parameters.
"""
function DBInterface.execute(conn::DBConnection, sql::AbstractString, params; kwargs...)
    stmt = Stmt(conn.conn, sql)
    try
        if !isempty(params)
            for (i, param) in enumerate(params)
                bind(stmt, i, param)
            end
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
    if !isempty(params)
        for (i, param) in enumerate(params)
            bind(stmt, i, param)
        end
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
