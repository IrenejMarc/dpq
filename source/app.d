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
