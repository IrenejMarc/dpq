import std.stdio;
import std.typecons;

import dpq.connection;
import dpq.querybuilder;
import dpq.query;
import dpq.attributes;

@relation("users")
struct User
{
	@serial @PrimaryKey int id;
	@attr("user") string username;
}

@relation("articles")
struct Article
{
	@PrimaryKey int id;
	string title;
}

void main()
{
	writeln("Connecting");
	auto conn = Connection("host=10.2.0.2 dbname=testdb user=testuser password='VerySecureTestPassword'");
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

	writefln("result.get(0, 0) is: %d", res.get(0, 0).as!int);
	writefln("result.get(0, 2) is: %s", res.get(0, 1).as!string);

	int id = 1;

	QueryBuilder b;
	b.from("users")
		.where("id = {id}")
		.order("id", Order.desc)
		.order("asd", Order.asc)
		.limit(1)
		.offset(5);

	b.param!id;

	writeln(b.command);

	auto q = Query("SELECT 1, 'asd', $1::int, $2::text");
	q << 123 << "asd";
	q.command = "SELECT 0.000000000000001::float, $1::int, $2::text";

	writeln("Command: ", q.command);
	auto r = q.run();

	auto val = r[0][0];
	writeln("Result: ", val.as!double);

	Query("CREATE TABLE IF NOT EXISTS test (id SERIAL, txt TEXT)").run();

	q = Query("SELECT id, txt FROM test WHERE id = $1 OR id = $2");
	r = q.run(4, 1);
	foreach (row; r)
		writeln("row['txt'] is: ", row["txt"].as!string);

	writeln("usecs taken for query: ", r.time.usecs);

	writeln(relationName!User);

	conn.ensureSchema!(User);
}
