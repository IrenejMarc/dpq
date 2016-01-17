# dpq - A D PostgreSQL library

dpq wraps the libpq library and aims to provide a simple and modern way to access PostgreSQL in the D programming language.

Very incomplete for now.

## Current features:
 - Opening a connection using a connection string
 - Queries
 - Fetching the results of queries in binary format
  
 ## Planned features
 - Object-relational mapping
 - Automatic schema creating from objects
 - Connection pooling
 - a Query object of some kind to simplify querying
 - foreach looping through results
 - Errors messages and exceptions :)
 
 ## Documentation
There is no docs yet, in the future, they should be written into the source code itself.
 
## Some notes:
 - If a wrong type is specified while fetching a column, the results are undefined. Most likely just garbage
 - Errors on connecting throw an exception, other errors don't (yet)
 - Fetching result data is only possible via indexes for now (using `Connection.get(int row, int col)`)

## Licence
MIT, read LICENSE.txt

## Very simple example code

```d
import std.stdio;

import dpq.connection;

import std.stdio;

void main()
{
	writeln("Connecting");
	auto conn = SQLConnection("host=10.2.0.2 dbname=testdb user=testuser password='VerySecureTestPassword'");
	writefln("Error message from connection: \"%s\"", conn.errorMessage);
	writeln("Connected");
	writefln("Database name is: %s.", conn.db);
	writefln("Current user is: %s.", conn.user);

	writeln("Sending a query");
	auto res = conn.execParams("SELECT $1::int, $2::text", 1, "asd");
	writeln("Sent a query");
	writefln("Error message from connection: \"%s\"", conn.errorMessage);

	writefln("Query result rows: %d.", res.rows);
	writefln("Query result columns: %d.", res.columns);

	writefln("result.get(0, 0) is: %d", res.get!int(0, 0));
	writefln("result.get(0, 2) is: %s", res.get!string(0, 1));
}

```
