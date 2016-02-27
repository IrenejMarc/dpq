module dpq.connection;

import derelict.pq.pq;

import dpq.exception;
import dpq.result;
import dpq.value;
import dpq.attributes;
import dpq.querybuilder;
import dpq.meta;
import dpq.prepared;
import dpq.smartptr;

import std.string;
import derelict.pq.pq;
import std.conv : to;
import std.traits;
import std.typecons;


version(unittest)
{
	import std.stdio;
	Connection c;
}

/**
	Represents the PostgreSQL connection and allows executing queries on it.

	Examples:
	-------------
	auto conn = Connection("host=localhost dbname=testdb user=testuser");
	//conn.exec ...
	-------------
*/
struct Connection
{
	alias ConnectionPtr = SmartPointer!(PGconn*, PQfinish);

	private ConnectionPtr _connection;
	private PreparedStatement[string] _prepared;

	/**
		Connection constructor

		Params:
			connString = connection string

		See Also:
			http://www.postgresql.org/docs/9.3/static/libpq-connect.html#LIBPQ-CONNSTRING
	*/
	this(string connString)
	{
		char* err;
		auto opts = PQconninfoParse(cast(char*)connString.toStringz, &err);

		if (err != null)
			throw new DPQException(err.fromStringz.to!string);

		_connection = new ConnectionPtr(PQconnectdb(connString.toStringz));

		if (status != ConnStatusType.CONNECTION_OK)
			throw new DPQException(errorMessage);

		_dpqLastConnection = &this;
	}

	unittest
	{
		c = Connection("dbname=test user=test");
		writeln(" * Database connection with connection string");
		assert(c.status == ConnStatusType.CONNECTION_OK);
	}

	/** 
		Close the connection manually 
	*/
	void close()
	{
		_connection.clear();
	}

	@property const(ConnStatusType) status()
	{
		return PQstatus(_connection);
	}

	/** Returns the name of the database currently selected */
	@property const(string) db()
	{
		return PQdb(_connection).to!string;
	}

	/** Returns the name of the current user */
	@property const(string) user()
	{
		return PQuser(_connection).to!string;
	}

	/// ditto, but password
	@property const(string) password()
	{
		return PQpass(_connection).to!string;
	}

	/// ditto, but host
	@property const(string) host()
	{
		return PQhost(_connection).to!string;
	}

	/// ditto, but port
	@property const(ushort) port()
	{
		return PQport(_connection).fromStringz.to!ushort;
	}

	/** // FIXME: BROKEN ATM
		Executes the given string directly

		Throws on fatal query errors like bad syntax

		Examples:
		----------------
		Connection conn; // An established connection

		conn.exec("CREATE TABLE IF NOT EXISTS test_table");
		----------------
	*/
	Result exec(string command)
	{
		PGresult* res = PQexec(_connection, cast(const char*)command.toStringz);
		return Result(res);
	}

	/*
	unittest
	{
		auto res = c.exec("SELECT 1::INT4 AS int4, 2::INT8 AS some_long");
		writeln(" * exec for selecting INT4 and INT8");
		assert(res.rows == 1);
		assert(res.columns == 2);

		auto r = res[0];
		assert(r[0].as!int == 1);
		assert(r[0].as!long == 2);

		writeln(" * Row opIndex(int) and opIndex(string) equality ");
		assert(r[0] == r["int4"]);
		assert(r[1] == r["some_long"]);

	}
	*/

	/// ditto, async
	bool send(string command)
	{
		return PQsendQuery(_connection, cast(const char*)command.toStringz) == 1;
	}

	/**
		Executes the given string with given params

		Params should be given as $1, $2, ... $n in the actual command.
		All params are sent in a binary format and should not be escaped.
		If a param's type cannot be inferred, this method will throw an exception,
		in this case, either specify the type using the :: (cast) notation or
		make sure the type can be inferred by PostgreSQL in your query.

		Examples:
		----------------
		Connection conn; // An established connection

		conn.execParams("SELECT $1::string, $2::int, $3::double");
		----------------

		See also:
			http://www.postgresql.org/docs/9.3/static/libpq-exec.html
	*/
	Result execParams(T...)(string command, T params)
	{
		Value[] values;
		foreach(param; params)
			values ~= Value(param);

		return execParams(command, values);
	}


	void sendParams(T...)(string command, T params)
	{
		Value[] values;
		foreach(param; params)
			values ~= Value(param);

		execParams(command, values, true);
	}

	unittest
	{
		auto res = c.execParams("SELECT 1::INT4 AS int4, 2::INT8 AS some_long", []);
		writeln("\t * execParams");
		writeln("\t\t * Rows and cols");

		assert(res.rows == 1);
		assert(res.columns == 2);

		writeln("\t\t * Static values");
		auto r = res[0];
		assert(r[0].as!int == 1);
		assert(r[1].as!long == 2);

		writeln("\t\t * opIndex(int) and opIndex(string) equality");
		assert(r[0] == r["int4"]);
		assert(r[1] == r["some_long"]);

		int int4 = 1;
		long int8 = 2;
		string str = "foo bar baz";
		float float4 = 3.14;
		double float8 = 3.1415;

		writeln("\t\t * Passed values");
		res = c.execParams(
				"SELECT $1::INT4, $2::INT8, $3::TEXT, $4::FLOAT4, $5::FLOAT8",
				int4,
				int8,
				str,
				float4,
				float8);

		assert(res.rows == 1);
		r = res[0];

		assert(r[0].as!int == int4);
		assert(r[1].as!long == int8);
		assert(r[2].as!string == str);
		assert(r[3].as!float == float4);
		assert(r[4].as!double == float8);
	}

	/// ditto, but taking an array of params, instead of variadic template
	Result execParams(string command, Value[] params, bool async = false)
	{
		const char* cStr = cast(const char*) command.toStringz;

		auto pTypes = params.paramTypes;
		auto pValues = params.paramValues;
		auto pLengths = params.paramLengths;
		auto pFormats = params.paramFormats;

		if (async)
		{
			PQsendQueryParams(
				_connection,
				cStr,
				params.length.to!int,
				pTypes.ptr,
				pValues.ptr,
				pLengths.ptr,
				pFormats.ptr,
				1);

			return Result(null);
		}
		else
			return Result(PQexecParams(
					_connection, 
					cStr, 
					params.length.to!int,
					pTypes.ptr, 
					pValues.ptr,
					pLengths.ptr,
					pFormats.ptr,
					1));
	}

	/// ditto, async
	void sendParams(string command, Value[] params)
	{
		execParams(command, params, true);
	}

	/**
		Returns the last error message

		Examples:
		--------------------
		Connection conn; // An established connection

		writeln(conn.errorMessage);
		--------------------
		
	 */
	@property string errorMessage()
	{
		return PQerrorMessage(_connection).to!string;
	}

	unittest
	{
		writeln("\t * errorMessage");
		try
		{
			c.execParams("SELECT_BADSYNTAX $1::INT4", 1);
		}
		catch {}

		assert(c.errorMessage.length != 0);

	}

	/**
		Generates and runs the DDL from the given structures

		Attributes from dpq.attributes should be used to define
		primary keys, indexes, and relationships.

		A custom type can be specified with the @type attribute.

		Examples:
		-----------------------
		Connection conn; // An established connection
		struct User 
		{
			@serial8 @PKey long id;
			string username;
			byte[] passwordHash;
		};

		struct Article { ... };

		conn.ensureSchema!(User, Article);
		-----------------------
	*/
	void ensureSchema(T...)(bool createType = false)
	{
		import std.stdio;
		string[] additional;

		foreach (type; T)
		{
			enum name = relationName!(type);
			string str;
			if (createType)
				str = "CREATE TYPE \"" ~ name ~ "\" AS (%s)";
			else
				str = "CREATE TABLE IF NOT EXISTS \"" ~ name ~ "\" (%s)";

			string cols;
			foreach(m; serialisableMembers!type)
			{
				string colName = attributeName!(mixin("type." ~ m));
				cols ~= "\"" ~ colName ~ "\"";

				// HACK: typeof a @property seems to be failing hard
				static if (is(FunctionTypeOf!(mixin("type." ~ m)) == function))
					alias t = typeof(mixin("type()." ~ m));
				else
					alias t = typeof(mixin("type." ~ m));

				cols ~= " ";

				// Basic data types
				static if (hasUDA!(mixin("type." ~ m), PGTypeAttribute))
					cols ~= getUDAs!(mixin("type." ~ m), PGTypeAttribute)[0].type;
				else
				{
					alias tu = Unqual!t;
					static if (ShouldRecurse!(mixin("type." ~ m)))
					{
						ensureSchema!tu(true);
						cols ~= '"' ~ relationName!tu ~ '"';
					}
					else
						cols ~= SQLType!tu;
				}
				
				// Primary key
				static if (hasUDA!(mixin("type." ~ m), PrimaryKeyAttribute))
				{
					if (!createType)
						cols ~= " PRIMARY KEY";
				}
				// Index
				else static if (hasUDA!(mixin("type." ~ m), IndexAttribute))
				{
					enum uda = getUDAs!(mixin("type." ~ m), IndexAttribute)[0];
					additional ~= "CREATE%sINDEX \"%s\" ON \"%s\" (\"%s\")".format(
							uda.unique ? " UNIQUE " : " ",
							"%s_%s_index".format(name, colName),
							name,
							colName);

					// DEBUG
				}
				// Foreign key
				else static if (hasUDA!(mixin("type." ~ m), ForeignKeyAttribute))
				{
					enum uda = getUDAs!(mixin("type." ~ m), ForeignKeyAttribute)[0];
					additional ~= 
						"ALTER TABLE \"%s\" ADD CONSTRAINT \"%s\" FOREIGN KEY (\"%s\") REFERENCES \"%s\" (\"%s\")".format(
								name,
								"%s_%s_fk_%s".format(name, colName, uda.relation),
								colName,
								uda.relation,
								uda.pkey);

					// Create an index on the FK too
					additional ~= "CREATE INDEX \"%s\" ON \"%s\" (\"%s\")".format(
							"%s_%s_fk_index".format(name, colName),
							name,
							colName);

				}

				cols ~= ", ";
			}

			cols = cols[0 .. $ - 2];
			str = str.format(cols);
			if (createType)
			{
				try
				{
					exec(str);
				}
				catch {} // Do nothing, type already exists
			}
			else
				exec(str);
		}
		foreach (cmd; additional)
		{
			try
			{
				exec(cmd);
			}
			catch {} // This just means the constraint/index already exists
		}
	}

	unittest
	{
		// Probably needs more thorough testing, let's assume right now
		// everything is correct if the creating was successful.

		writeln("\t * ensureSchema");
		struct Inner
		{
			string innerStr;
			int innerInt;
		}

		struct TestTable1
		{
			@serial8 @PK long id;
			string str;
			int n;
			@embed Inner inner;
		}

		c.ensureSchema!TestTable1;
		
		auto res = c.execParams(
				"SELECT COUNT(*) FROM pg_catalog.pg_tables WHERE tablename = $1",
				relationName!TestTable1);

		assert(res.rows == 1);
		assert(res[0][0].as!long == 1);

		c.exec("DROP TABLE " ~ relationName!TestTable1);
		c.exec("DROP TYPE \"" ~ relationName!Inner ~ "\" CASCADE");
	}

	/**
		Returns the requested structure or a Nullable null value if no rows are returned

		This method queries for the given structure by its primary key. If no
		primary key can be found, a compile-time error will be generated.

		Examples:
		----------------------
		Connection conn; // An established connection
		struct User
		{
			@serial @PKey int id;
			...
		};

		auto user = conn.findOne!User(1); // will search by the id attribute
		----------------------
	*/
	Nullable!T findOne(T, U)(U id)
	{
		return findOneBy!T(primaryKeyName!T, id);
	}

	unittest
	{
		writeln("\t * findOne(T)(U id), findOneBy, findOne");
		struct Testy
		{
			@serial @PK int id;
			string foo;
			int bar;
			long baz;
			int[] intArr;
			//string[] stringArr; // TODO: string[]
		}

		c.ensureSchema!Testy;

		writeln("\t\t * Null result");
		auto shouldBeNull = c.findOne!Testy(0);
		assert(shouldBeNull.isNull);

		c.exec("INSERT INTO " ~ relationName!Testy ~ " (id, foo, bar, baz, " ~ attributeName!(Testy.intArr) ~ ") "~
				"VALUES (1, 'somestr', 2, 3, '{1,2,3}')");

		writeln("\t\t * Valid result");
		Testy t = c.findOne!Testy(1);
		assert(t.id == 1, `t.id == 1` );
		assert(t.foo == "somestr", `t.foo == "somestr"`);
		assert(t.bar == 2, `t.bar == 2`);
		assert(t.baz == 3, `t.baz == 3`);
		assert(t.intArr == [1,2,3], `t.intArr == [1,2,3]`);
		//assert(t.stringArr == ["asd", "qwe"]);

		writeln("\t\t * findOne with custom filter");
		Testy t2 = c.findOne!Testy("id = $1", 1);
		assert(t == t2);

		c.exec("DROP TABLE " ~ relationName!Testy);
	}

	/**
		Returns the requestes structure, searches by the given column name
		with the given value
		If not rows are returned, a Nullable null value is returned

		Examples:
		----------------------
		Connection conn; // An established connection
		struct User
		{
			@serial @PKey int id;
			...
		};

		auto user = conn.findOneBy!User("id", 1); // will search by "id"
		----------------------
	*/
	Nullable!T findOneBy(T, U)(string col, U val)
	{
		import std.stdio;

		auto members = AttributeList!T;

		QueryBuilder qb;
		qb.select(members)
			.from(relationName!T)
			.where( col ~ " = {col_" ~ col ~ "}")
			.limit(1);

		qb["col_" ~ col] = val;

		auto q = qb.query(this);

		auto r = q.run();
		if (r.rows == 0)
			return Nullable!T.init;

		//return T();
		
		auto res = deserialise!T(r[0]);
		return Nullable!T(res);
	}
	
	/**
		Returns the requested structure, searches by the specified filter
		with given params

		The filter is not further escaped, so programmer needs to make sure
		not to properly escape or enclose reserved keywords (like user -> "user")
		so PostgreSQL can understand them.

		If not rows are returned, a Nullable null value is returned

		Examples:
		----------------------
		Connection conn; // An established connection
		struct User
		{
			@serial @PKey int id;
			string username;
			int posts;
		};

		auto user = conn.findOne!User("username = $1 OR posts > $2", "foo", 42);
		if (!user.isNull)
		{
			... // do something
		}
		----------------------
	*/
	Nullable!T findOne(T, U...)(string filter, U vals)
	{
		QueryBuilder qb;
		qb.select(AttributeList!T)
			.from(relationName!T)
			.where(filter)
			.limit(1);

		auto q = qb.query(this);
		auto r = q.run(vals);

		if (r.rows == 0)
			return Nullable!T.init;

		auto res = deserialise!T(r[0]);
		return Nullable!T(res);
	}

	/**
		Returns an array of the specified type, filtered with the given filter and
		params

		If no rows are returned by PostgreSQL, an empty array is returned.

		Examples:
		----------------------
		Connection conn; // An established connection
		struct User
		{
			@serial @PKey int id;
			string username;
			int posts;
		};

		auto users = conn.find!User("username = $1 OR posts > $2", "foo", 42);
		foreach (u; users)
		{
			... // do something
		}
		----------------------
	*/
	T[] find(T, U...)(string filter = "", U vals = U.init)
	{
		QueryBuilder qb;
		qb.select(AttributeList!T)
			.from(relationName!T)
			.where(filter);

		auto q = qb.query(this);

		T[] res;
		foreach (r; q.run(vals))
			res ~= deserialise!T(r);

		return res;
	}

	unittest
	{
		writeln("\t * find");

		@relation("find_test")
		struct Test
		{
			@serial @PK int id;
			@attr("my_n") int n;
		}

		c.ensureSchema!Test;

		Test t;
		t.n = 1;

		c.insert(t);
		c.insert(t);
		++t.n;
		c.insert(t);
		c.insert(t);
		c.insert(t);

		Test[] ts = c.find!Test("my_n = $1", 1);
		assert(ts.length == 2);
		ts = c.find!Test("my_n > 0");
		assert(ts.length == 5);
		ts = c.find!Test("false");
		assert(ts.length == 0);

		c.exec("DROP TABLE find_test");
	}

	int update(T, U...)(string filter, string update, U vals)
	{
		QueryBuilder qb;
		qb.update(relationName!T)
			.set(update)
			.where(filter);

		auto r = qb.query(this).run(vals);
		return r.rows;
	}

	unittest
	{
		writeln("\t * update");

		@relation("update_test")
		struct Test
		{
			@serial @PK int id;
			int n;
		}

		c.ensureSchema!Test;

		Test t;
		t.n = 5;
		c.insert(t);

		int nUpdates = c.update!Test("n = $1", "n = $2", 5, 123);
		assert(nUpdates == 1, `nUpdates == 1`);

		t = c.findOneBy!Test("n", 123);
		assert(t.n == 123, `t.n == 123`);

		writeln("\t\t * async");
		c.updateAsync!Test("n = $1", "n = $2", 123, 6);
		auto r = c.nextResult();

		assert(r.rows == 1);
		assert(!c.findOneBy!Test("n", 6).isNull);

		c.exec("DROP TABLE update_test");
	}

	void updateAsync(T, U...)(string filter, string update, U vals)
	{
		QueryBuilder qb;
		qb.update(relationName!T)
			.set(update)
			.where(filter);

		qb.query(this).runAsync(vals);
	}

	int update(T, U)(U id, Value[string] updates, bool async = false)
	{
		QueryBuilder qb;

		qb.update(relationName!T)
			.set(updates)
			.where(primaryKeyName!T, id);

		auto q = qb.query(this);

		if (async)
		{
			q.runAsync();
			return -1;
		}

		auto r = q.run();
		return r.rows;
	}

	unittest
	{
		writeln("\t * update with AA updates");

		@relation("update_aa_test")
		struct Test
		{
			@serial @PK int id;
			int n;
		}
		c.ensureSchema!Test;

		Test t;
		t.n = 1;
		c.insert(t);

		int rows = c.update!Test(1, ["n": Value(2)]);
		assert(rows == 1, `r.rows == 1`);

		c.exec("DROP TABLE update_aa_test");
	}

	void updateAsync(T, U)(U id, Value[string] updates)
	{
		update!T(id, updates, true);
	}

	int update(T, U)(U id, T updates, bool async = false)
	{
		import dpq.attributes;

		QueryBuilder qb;

		qb.update(relationName!T)
			.where(primaryKeyName!T, id);

		foreach (m; serialisableMembers!T)
			qb.set(attributeName!(mixin("T." ~ m)), __traits(getMember, updates, m));

		auto q = qb.query(this);
		if (async)
		{
			qb.query(this).runAsync();
			return -1;
		}

		auto r = q.run();
		return r.rows;
	}

	unittest
	{
		writeln("\t * update with object");
		
		@relation("update_object_test")
		struct Test
		{
			@serial @PK int id;
			int n;
		}
		c.ensureSchema!Test;

		Test t;
		t.n = 1;
		t.id = 1; // assumptions <3

		c.insert(t);

		t.n = 2;
		c.update!Test(1, t);
		
		t = c.findOne!Test(1);
		assert(t.n == 2);

		t.n = 3;
		c.updateAsync!Test(1, t);
		auto r = c.nextResult();

		writeln("\t\t * async");
		assert(r.rows == 1);

		c.exec("DROP TABLE update_object_test");
	}

	void updateAsync(T, U)(U id, T updates)
	{
		update!T(id, updates, true);
	}

	bool insert(T)(T val, bool async = false)
	{
		QueryBuilder qb;
		qb.insert(relationName!T, AttributeList!(T, true, true));

		void addVals(T, U)(U val)
		{
			foreach (m; serialisableMembers!T)
			{
				static if (isPK!(T, m))
					continue;
				else static if (ShouldRecurse!(mixin("T." ~ m)))
					addVals!(typeof(mixin("T." ~ m)))(__traits(getMember, val, m));
				else
					qb.addValue(__traits(getMember, val, m));
			}
		}

		addVals!T(val);

		if (async)
		{
			return qb.query(this).runAsync();
		}

		auto r = qb.query(this).run();
		return r.rows > 0;
	}

	unittest
	{
		writeln("\t * insert");

		@relation("insert_test_inner")
		struct Inner
		{
			int bar;
		}

		@relation("insert_test")
		struct Test
		{
			int n;
			@embed Inner foo;
		}
		c.ensureSchema!Test;

		Test t;
		t.n = 1;
		t.foo.bar = 2;
		
		auto r = c.insert(t);
		assert(r == true);

		Test t2 = c.findOneBy!Test("n", 1);
		assert(t2 == t);

		writeln("\t\t * async");
		t.n = 123;
		c.insertAsync(t);
		
		auto res = c.nextResult();
		assert(res.rows == 1);

		c.exec("DROP TABLE insert_test");
		c.exec("DROP TYPE \"%s\" CASCADE".format(relationName!Inner));
	}

	void insertAsync(T)(T val)
	{
		insert(val, true);
	}

	int remove(T, U)(U id)
	{
		QueryBuilder qb;
		qb.remove!T
			.where(primaryKeyName!T, id);

		return qb.query(this).run().rows;
	}

	bool removeAsync(T, U)(U id)
	{
		QueryBuilder qb;
		qb.remove!T
			.where(primaryKeyName!T, id);

		return qb.query(this).runAsync() == 1;
	}


	int remove(T, U...)(string filter, U vals)
	{
		QueryBuilder qb;
		qb.remove!T
			.where(filter);

		foreach (v; vals)
			qb.addValue(v);

		return qb.query(this).run().rows;
	}

	bool removeAsync(T, U...)(string filter, U vals)
	{
		QueryBuilder qb;
		qb.remove!T
			.where(filter);

		foreach (v; vals)
			qb.addValue(v);

		return qb.query(this).runAsync() == 1;
	}

	unittest
	{
		@relation("remove_test")
		struct Test
		{
			@serial @PK int id;
			int n;
		}
		c.ensureSchema!Test;

		foreach (i; 0 .. 10)
			c.insert(Test(0, i));

		writeln("\t * remove(id)");
		int n = c.remove!Test(1);
		assert(n == 1, `n == 1`);


		writeln("\t\t * async");
		c.removeAsync!Test(2);
		auto r = c.nextResult();
		assert(r.rows == 1, `r.rows == 1`);

		writeln("\t * remove(filter, vals...)");
		n = c.remove!Test("id IN($1,$2,$3,$4,$5)", 3, 4, 5, 6, 7);
		assert(n == 5);

		writeln("\t\t * async");
		c.removeAsync!Test("id >= $1", 7);
		r = c.nextResult();
		assert(r.rows == 3);

		c.exec("DROP TABLE remove_test");
	}


	bool isBusy()
	{
		return PQisBusy(_connection) == 1;
	}

	unittest
	{
		writeln("\t * isBusy");

		assert(c.isBusy() == false);

		c.send("SELECT 1::INT");

		assert(c.isBusy() == true);

		c.nextResult();
		assert(c.isBusy() == false);
	}


	/**
		 Blocks until a result is read, then returns it

		 If no more results remain, a null result will be returned

		 Make sure to call this until a null is returned.
	*/
	Result nextResult()
	{
		import core.thread;

		/*
		do
		{
			PQconsumeInput(_connection);
			//Thread.sleep(dur!"msecs"(1)); // What's a reasonable amount of time to wait?
		}
		while (isBusy());
		*/

		PGresult* res = PQgetResult(_connection);
		return Result(res);
	}

	Result[] allResults()
	{
		Result[] res;
		
		PGresult* r;
		while ((r = PQgetResult(_connection)) != null)
			res ~= Result(r);

		return res;
	}
	
	Result lastResult()
	{
		Result res;

		PGresult* r;
		while ((r = PQgetResult(_connection)) != null)
			res = Result(r);

		return res;
	}

	unittest
	{
		writeln("\t * nextResult");
		auto x = c.nextResult();
		assert(x.isNull);

		int int1 = 1;
		int int2 = 2;

		c.sendParams("SELECT $1", int1);

		// In every way the same as lastResult
		Result r, t;
		while(!(t = c.nextResult()).isNull)
			r = t;

		assert(r.rows == 1);
		assert(r.columns == 1);
		assert(r[0][0].as!int == int1);

		writeln("\t * lastResult");
		c.sendParams("SELECT $1", int2);
		r = c.lastResult();

		assert(r.rows == 1);
		assert(r.columns == 1);
		assert(r[0][0].as!int == int2);
	}

	Result prepare(T...)(string name, string command, T paramTypes)
	{
		Oid[] oids;
		foreach (pType; paramTypes)
			oids ~= pType;

		char* cName = cast(char*) name.toStringz;
		char* cComm = cast(char*) command.toStringz;

		auto p = PreparedStatement(this, name, command, oids);
		_prepared[name] = p;

		return Result(PQprepare(
					_connection,
					cName,
					cComm,
					oids.length.to!int,
					oids.ptr));
	}

	Result execPrepared(string name, Value[] params...)
	{
		char* cStr = cast(char*) name.toStringz;

		return Result(PQexecPrepared(
					_connection,
					cStr,
					params.length.to!int,
					cast(char**) params.paramValues.ptr,
					params.paramLengths.ptr,
					params.paramFormats.ptr,
					1));
	}

	Result execPrepared(T...)(string name, T params)
	{
		Value[] vals;
		foreach (p; params)
			vals ~= Value(p);

		return execPrepared(name, vals);
	}

	bool sendPrepared(string name, Value[] params...)
	{
		char* cStr = cast(char*) name.toStringz;

		return PQsendQueryPrepared(
				_connection,
				cStr,
				params.length.to!int,
				cast(char**) params.paramValues.ptr,
				params.paramLengths.ptr,
				params.paramFormats.ptr,
				1) == 1;
	}

	bool sendPrepared(T...)(string name, T params)
	{
		Value[] vals;
		foreach (p; params)
			vals ~= Value(p);

		return sendPrepared(name, vals);
	}

	unittest
	{
		writeln("\t * prepare");
		// The result of this isn't really all that useful, but as long as it 
		// throws on errors, it kinda is
		c.prepare("prepare_test", "SELECT $1", Type.INT4);

		writeln("\t * execPrepared");
		auto r = c.execPrepared("prepare_test", 1);
		assert(r.rows == 1);
		assert(r[0][0].as!int == 1);

		writeln("\t\t * sendPrepared");
		bool s = c.sendPrepared("prepare_test", 1);
		assert(s);

		r = c.lastResult();
		assert(r.rows == 1);
		assert(r[0][0].as!int == 1);
	}
	
	ref PreparedStatement prepared(string name)
	{
		return _prepared[name];
	}

	ref PreparedStatement opIndex(string name)
	{
		return prepared(name);
	}
}


/**
	Deserialises the given Row to the requested type

	Params:
		T  = (template) type to deserialise into
		r  = Row to deserialise
*/
T deserialise(T)(Row r, string prefix = "")
{
	T res;
	foreach (m; serialisableMembers!T)
	{
		enum n = attributeName!(mixin("T." ~ m));
		alias mType = typeof(mixin("T." ~ m));

		static if (ShouldRecurse!(__traits(getMember, res, m)))
			__traits(getMember, res, m) = deserialise!mType(r, embeddedPrefix!mType ~ prefix);
		else
		{
			auto x = r[prefix ~ n].as!(typeof(mixin("res." ~ m)));
			if (!x.isNull)
				__traits(getMember, res, m) = x;
		}
	}
	return res;
}

/// Hold the last created connection, not to be used outside the library
package Connection* _dpqLastConnection;

/// Loads the derelict-pq library at runtime
shared static this()
{
	DerelictPQ.load();
}
