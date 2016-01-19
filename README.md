# dpq - A D PostgreSQL library

dpq wraps the libpq library and aims to provide a simple and modern way to access PostgreSQL in the D programming language.

## Current features:
 - Opening a connection using a connection string
 - Queries
 - Fetching the results of queries in binary format
 - Looping through the said results
 - Exceptions on query errors
 - 
  
 ## Planned features
 - Object-relational mapping
 - Automatic schema creating from objects
 - Connection pooling
 
 ## Documentation
There is no docs yet, in the future, they should be written into the source code itself.
 
## Some notes:
 - If a wrong type is specified while fetching a column, the results are undefined. Most likely just garbage

## Licence
MIT, read LICENSE.txt

## Very simple example code

```d
import std.stdio;
import dpq.connection;
import dpq.query;

void main()
{
	auto conn = Connection("host=somehost dbname=testdb user=testuser password='VerySecureTestPassword'");
	// One-line query execution, the same could be done with Connection.exec(string command)
	Query("CREATE TABLE IF NOT EXISTS test (id SERIAL, txt TEXT)").run();
	
	// Last connection will be used if none is specified as the first param to Query()
	q = Query("SELECT id, txt FROM test WHERE id = $1 OR id = $2");
	// Params could also be added with the << operator
	// r << 4 << 1;
	r = q.run(4, 1);
	foreach (row; r)
		writeln("row['txt'] is: ", row["txt"].as!string);

    // Connection does not have to be closed, the destructor will take care of that.
}

```

