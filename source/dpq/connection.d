module dpq.connection;

import derelict.pq.pq;

import dpq.exception;
import dpq.result;
import dpq.value;
import dpq.attributes;
import dpq.querybuilder;

import std.string;
import derelict.pq.pq;
import std.conv : to;
import std.traits;
import std.typecons;

/**
	Represents the PostgreSQL connection and allows executing queries on it.

	Examples:
	-------------
	auto conn = Connection("host=localhost dbname=testdb user=testuer");
	//conn.exec ...
	-------------
*/
struct Connection
{
	private PGconn* _connection;

	/**
		Connection constructor

		Params:
			- connString - connection string

		See also:
			http://www.postgresql.org/docs/9.3/static/libpq-connect.html#LIBPQ-CONNSTRING
	*/
	this(string connString)
	{
		char* err;
		auto opts = PQconninfoParse(cast(char*)connString.toStringz, &err);

		if (err != null)
		{
			throw new DPQException(err.fromStringz.to!string);
		}

		_connection = PQconnectdb(connString.toStringz);
		_dpqLastConnection = &this;
	}

	/** Copy constructor is disabled to avoid double-freeing the PGConn pointer */
	@disable this(this);

	/** The destructor will automatically close the connection and free resources */
	~this()
	{
		PQfinish(_connection);
	}

	/** 
		Close the connection manually 
	*/
	void close()
	{
		PQfinish(_connection);
		_connection = null;
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
	@property const(string) port()
	{
		return PQport(_connection).to!string;
	}

	/**
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

	/// ditto, but taking an array of params, instead of variadic template
	Result execParams(string command, Value[] params)
	{
		const char* cStr = cast(const char*) command.toStringz;

		auto pTypes = params.paramTypes;
		auto pValues = params.paramValues;
		auto pLengths = params.paramLengths;
		auto pFormats = params.paramFormats;

		auto res = PQexecParams(
				_connection, 
				cStr, 
				params.length.to!int, 
				pTypes.ptr, 
				pValues.ptr,
				pLengths.ptr,
				pFormats.ptr,
				1);

		return Result(res);
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

	/**
		Generates and runs the DDL from the givent structures

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
			ubyte[] passwordHash;
		};

		struct Article { ... };

		conn.ensureSchema!(User, Article);
		-----------------------
	*/
	void ensureSchema(T...)()
	{
		import std.stdio;
		string[] additional;

		foreach (type; T)
		{
			enum name = relationName!(type);
			string str = "CREATE TABLE IF NOT EXISTS \"" ~ name ~ "\" (%s)";

			string cols;
			foreach(m; serialisableMembers!type)
			{
				string colName = attributeName!(mixin("type." ~ m));
				cols ~= "\"" ~ colName ~ "\"";

				alias t = typeof(mixin("type." ~ m));

				cols ~= " ";

				// TODO: More types, embedded structs, Date types

				// Basic data types
				static if (hasUDA!(mixin("type." ~ m), PGTypeAttribute))
					cols ~= getUDAs!(mixin("type." ~ m), PGTypeAttribute)[0].type;
				else
				{
					alias tu = Unqual!(typeof(mixin("type." ~ m)));

					static if (is(tu == int))
						cols ~= "INT";
					else static if (is(tu == long))
						cols ~= "BIGINT";
					else static if (is(tu == float))
						cols ~= "FLOAT4";
					else static if (is(tu == double))
						cols ~= "FLOAT8";
					else static if (is(tu == char[]) || is(tu == string))
						cols ~= "TEXT";
					else static if (is(tu == bool))
						cols ~= "BOOL";
					else static if (is(tu == char))
						cols ~= "CHAR(1)";
					else static if(is(tu == ubyte[]) || is(tu == byte[]))
						cols ~= "BYTEA";
					// Default to bytea because we fetch and send everything in binary anyway
					else
						static assert(false, "Cannot map type \"" ~ t.stringof ~ "\" of field " ~ m ~ " to any PG type, please specify it manually using @type.");
				}
				
				writeln("All attrs: ", __traits(getAttributes, mixin("type." ~ m)));
				writeln("Has FK UDA: ", hasUDA!(mixin("type." ~ m), ForeignKeyAttribute));
				writeln("FK UDAs: ", getUDAs!(mixin("type." ~ m), ForeignKeyAttribute));
				writeln("Has index UDA: ", hasUDA!(mixin("type." ~ m), IndexAttribute));
				writeln("index UDAs: ", getUDAs!(mixin("type." ~ m), IndexAttribute));
								
				// Primary key
				static if (hasUDA!(mixin("type." ~ m), PrimaryKeyAttribute))
					cols ~= " PRIMARY KEY";
				// Index
				else static if (hasUDA!(mixin("type." ~ m), IndexAttribute))
				{
					writeln("Got Index!");
					enum uda = getUDAs!(mixin("type." ~ m), IndexAttribute)[0];
					additional ~= "CREATE%sINDEX \"%s\" ON \"%s\" (\"%s\")".format(
							uda.unique ? " UNIQUE " : " ",
							"%s_%s_index".format(name, colName),
							name,
							colName);

					// DEBUG
					writeln(additional[$ - 1]);
				}
				// Foreign key
				else static if (hasUDA!(mixin("type." ~ m), ForeignKeyAttribute))
				{
					writeln("Got FK");
//ALTER TABLE distributors ADD CONSTRAINT distfk FOREIGN KEY (address) REFERENCES addresses (address) MATCH FULL;
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

					// DEBUG
					writeln(additional[$ - 2 .. $]);
				}

				cols ~= ", ";
			}

			cols = cols[0 .. $ - 2];
			str = str.format(cols);

			exec(str);
		}
		foreach (cmd; additional)
			exec(cmd);
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

		auto members = sqlMembers!T;

		QueryBuilder qb;
		qb.select(members)
			.from(relationName!T)
			.where("\"" ~ col ~ "\"" ~ " = {col_" ~ col ~ "}")
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
		qb.select(sqlMembers!T)
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
		qb.select(sqlMembers!T)
			.from(relationName!T)
			.where(filter);

		auto q = qb.query(this);

		T[] res;
		foreach (r; q.run(vals))
			res ~= deserialise!T(r);

		return res;
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

	int update(T, U)(U id, Value[string] updates)
	{
		QueryBuilder qb;

		qb.update(relationName!T)
			.set(updates)
			.where(primaryKeyName!T, id);

		auto r = qb.query(this).run();
		return r.rows;
}

/**
	Returns an array of all the members that can be (de-)serialised, with their
	preferred names.
*/
private string[] sqlMembers(T)()
{
	string[] members;
	foreach (m; serialisableMembers!T)
		members ~= attributeName!(mixin("T." ~ m));

	return members;
}

/**
	Deserialises the given Row to the requested type

	Params:
		- T (template) - type to deserialise into
		- r - Row to deserialise
*/
T deserialise(T)(Row r)
{
	T res;
	foreach (m; serialisableMembers!T)
	{
		enum n = attributeName!(mixin("T." ~ m));
		try
		{
			mixin("res." ~ m) = r[n].as!(typeof(mixin("res." ~ m)));
		}
		catch {}
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
