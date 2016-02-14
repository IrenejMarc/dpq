module dpq.connection;

import derelict.pq.pq;

import dpq.exception;
import dpq.result;
import dpq.value;
import dpq.attributes;
import dpq.querybuilder;
import dpq.meta;

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

		_connection = PQconnectdb(connString.toStringz);

		if (status != ConnStatusType.CONNECTION_OK)
			throw new DPQException(errorMessage);

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
	Result execParams(T...)(string command, T params, bool async = false)
	{
		Value[] values;
		foreach(param; params)
			values ~= Value(param);

		return execParams(command, values);
	}

	void sendParams(T...)(string command, T params)
	{
		execParams(command, params, true);
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
					static if (is(tu == class) || is(tu == struct))
					{
						ensureSchema!tu(true);
						cols ~= '"' ~ relationName!tu ~ '"';
					}
					else						cols ~= SQLType!tu;
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

		foreach (m; AttributeList!(T, true))
			qb.set(attributeName!(mixin("T." ~ m), __traits(getMember, updates, m)));

		auto q = qb.query(this);
		if (async)
		{
			qb.query(this).runAsync();
			return -1;
		}

		auto r = q.run();
		return r.rows;
	}

	void updateAsync(T, U)(U id, T updates)
	{
		update(id, T, true);
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
				else static if (is(typeof(mixin("T." ~ m)) == class) || is(typeof(mixin("T." ~ m)) == struct))
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

	void insertAsync(T)(T val)
	{
		insert(val, true);
	}

	bool isBusy()
	{
		return PQisBusy(_connection) == 1;
	}


	/**
		 Blocks until a result is read, then returns it

		 If no more results remain, a null result will be returned
	*/
	Result nextResult()
	{
		import core.thread;

		do
		{
			PQconsumeInput(_connection);
			Thread.sleep(dur!"msecs"(1)); // What's a reasonable amount of time to wait?
		}
		while (isBusy());

		PGresult* res = PQgetResult(_connection);
		return Result(res);
	}

	Result prepare(T...)(string name, string command, T paramTypes)
	{
		Oid[] oids;
		foreach (pType; paramTypes)
			oids ~= pType;

		char* cName = cast(char*) name.toStringz;
		char* cComm = cast(char*) command.toStringz;

		return Result(PQprepare(
					_connection,
					cName,
					cComm,
					oids.length.to!int,
					oids.ptr));
	}

	Result execPrepared(T...)(string name, T params)
	{
		Value[] vals;
		foreach (p; params)
			vals ~= Value(p);

		char* cStr = cast(char*) name.toStringz;

		return Result(PQexecPrepared(
					_connection,
					cStr,
					vals.length.to!int,
					cast(char**) vals.paramValues.ptr,
					vals.paramLengths.ptr,
					vals.paramFormats.ptr,
					1));
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

		static if (is(mType == class) || is(mType == struct))
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
