
# Oracle.jl

[![License][license-img]](LICENSE)
[![CI][ci-img]][ci-url]
[![dev][docs-dev-img]][docs-dev-url]
[![stable][docs-stable-img]][docs-stable-url]

[license-img]: http://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat-square
[ci-img]: https://github.com/felipenoris/Oracle.jl/workflows/CI/badge.svg
[ci-url]: https://github.com/felipenoris/Oracle.jl/actions?query=workflow%3ACI
[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg?style=flat-square
[docs-dev-url]: https://felipenoris.github.io/Oracle.jl/dev
[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg?style=flat-square
[docs-stable-url]: https://felipenoris.github.io/Oracle.jl/stable

This package provides a driver to access Oracle databases using the Julia language,
based on [ODPI-C](https://github.com/oracle/odpi) bindings.

## Requirements

* [Julia](https://julialang.org/) v1.6 or newer.

* Oracle's [Instant Client](https://www.oracle.com/technetwork/database/database-technologies/instant-client/overview/index.html).

* Linux or macOS.

* C compiler.

## Documentation

Package documentation is hosted at https://felipenoris.github.io/Oracle.jl/stable.

## Stored procedures with REF CURSOR outputs

Oracle procedures that return one or more `SYS_REFCURSOR` values can be
executed with `Oracle.execute_procedure`. Input parameters are supplied as a
named tuple and output cursor bind names are listed in order:

```julia
result = Oracle.execute_procedure(
	conn,
	"BEGIN fs_order_report(:p_customer_id, :p_orders, :p_items); END;";
	params = (p_customer_id = 1,),
	out_cursors = (:p_orders, :p_items))

orders = result[1]
items = result[2]
```

The returned `ProcedureResult` is iterable and indexable. Each element is a
normal `ResultSet` and can be consumed with Tables.jl.
