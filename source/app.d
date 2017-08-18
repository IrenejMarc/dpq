import std.stdio;
import std.typecons : Nullable;

import std.datetime : SysTime;

import dpq.connection;
import dpq.value;
import dpq.attributes;
import dpq.query;
import dpq.result;

void main()
{
	struct Test
	{
		@serial @PK int id;
		@notNull string name;
		string somethingElse;
	}

	auto db = Connection("dbname=test user=test");

	db.ensureSchema!Test;

	auto q = Query(db);
	q = "SELECT ARRAY[]::INT[]";

	auto v = q.run()[0][0];
	writeln(v.as!(int[]));
}

