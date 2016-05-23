///
module dpq.query;

import dpq.connection;
import dpq.value;
import dpq.exception;
import dpq.result;

version(unittest)
{
	import std.stdio;
	private Connection c;
}

/**
	A nice wrapper around various DB querying functions,
	to fill even everyday PostgreSQL querying with joy.

	Examples:
	-------------------
	Connection c; // an established connection

	Query q; // Will not have the connection set (!!!)
	q.connection = c; // We can set it manually

	q = Query(c); // Or simply use the constructor
	-------------------
 */
struct Query
{
	private string _command;
	private Value[] _params;
	private Connection* _connection;

	/**
		Constructs a new Query object, reusing the last opened connection.
		Will fail if no connection has been established.

		A command string msut be provided, optionally, values can be provided too,
		but will usually be added later on.

		The query internally keeps a list of params that it will be executed with.

		Please note that using the Query's empty constructor will NOT set the Query's 
		connection, and the Query will therefore be quite unusable unless you set the
		connection later.

		Examples:
		---------------
		auto q = Query("SELECT 1::INT");

		auto q = Query("SELECT $1::INT", 1);
		---------------
	 */
	this(string command, Value[] params = [])
	{
		if (_dpqLastConnection == null)
			throw new DPQException("Query: No established connection was found and none was provided.");

		_connection = _dpqLastConnection;
		_command = command;
		_params = params;
	}

	/**
		Like the above constructor, except it also accepts a Connection as the first
		param. A copy of the Connection is not made.

		Examples:
		---------------
		Connection conn; // an established connection
		auto q = Query(conn, "SELECT 1::INT");

		Connection conn; // an established connection
		auto q = Query(conn, "SELECT $1::INT", 1);
		---------------
	 */
	this(ref Connection conn, string command = "", Value[] params = [])
	{
		_connection = &conn;
		_command = command;
		_params = params;
	}

	unittest
	{
		writeln(" * Query");

		c = Connection("host=127.0.0.1 dbname=test user=test");

		writeln("\t * this()");
		Query q;
		// Empty constructor uses init values
		assert(q._connection == null);

		writeln("\t * this(command, params[])");
		string cmd = "some command";
		q = Query(cmd);
		assert(q._connection != null, `not null 2`);
		assert(q._command == cmd, `cmd`);
		assert(q._params == [], `empty arr`);

		Connection c2 = Connection("host=127.0.0.1 dbname=test user=test");
		writeln("\t * this(Connection, command, params[])");
		q = Query(c2);
		assert(q._connection == &c2);

		q = Query(cmd);
		assert(q._connection == &c2);
	}

	/**
		A setter for the connection.

		THe connection MUST be set before executing the query, but it is a lot more
		handy to simply use the constructor that takes the Connection instead of 
		using this.
	 */
	@property void connection(ref Connection conn)
	{
		_connection = &conn;
	}

	/**
		A getter/setter pair for the command that will be executed.
	 */
	@property string command()
	{
		return _command;
	}
	
	/// ditto
	@property void command(string c)
	{
		_command = c;
	}

	/**
		Add a param to the list of params that will be sent with the query.
		It's probably a better idea to just use run function with all the values,
		but in some cases, adding params one by one can result in a more readable code.
	 */
	void addParam(T)(T val)
	{
		_params ~= Value(val);
	}

	unittest
	{
		Query q;
		assert(q._params.length == 0);

		q.addParam(1);

		assert(q._params.length == 1);
		assert(q._params[0] == Value(1));
	}

	/**
		In reality just an alias to addParam, but can be chained to add multiple
		params.

		Examples:
		-----------------
		auto q = Query("SELECT $1, $2, $3");
		q << "something" << 123 << 'c';
		-----------------
	 */
	ref Query opBinary(string op, T)(T val)
			if (op == "<<")
	{
		addParam(val);
		return this;
	}

	/**
		Sets the query's command and resets the params. Connection is not affected
		Useful if you want to reuse the same query object.
	 */
	void opAssign(string str)
	{
		command = str;
		_params = [];
	}

	/**
		Runs the Query, returning a Result object.
		Optionally accepts a list of params for the query to be ran with. The params
		are added to the query, and if the query is re-ran for the second time, do
		not need to be added again.
		
		Examples:
		----------------
		Connection c;
		auto q = Query(c);
		q = "SELECT $1";
		q.run(123);
		----------------
	 */
	Result run()
	{
		import std.datetime;

		StopWatch sw;
		sw.start();

		Result r = _connection.execParams(_command, _params);
		sw.stop();

		r.time = sw.peek();
		return r;
	}

	/// ditto
	Result run(T...)(T params)
	{
		foreach (p; params)
			addParam(p);

		return run();
	}

	/// ditto, async
	bool runAsync(T...)(T params)
	{
		foreach (p; params)
			addParam(p);

		return runAsync();
	}

	// ditto
	bool runAsync()
	{
		_connection.sendParams(_command, _params);
		return true; // FIXME: must return the actual result from PQsendQueryParams
	}

	unittest
	{
		writeln("\t * run");

		auto c = Connection("host=127.0.0.1 dbname=test user=test");
		
		auto q = Query("SELECT 1::INT");

		auto r = q.run();
		assert(r.rows == 1);
		assert(r.columns == 1);
		assert(r[0][0].as!int == 1);

		writeln("\t\t * async");
		q.runAsync();

		r = c.lastResult();
		assert(r.rows == 1);
		assert(r.columns == 1);
		assert(r[0][0].as!int == 1);

		writeln("\t * run(params...)");

		q = "SELECT $1";
		q.run(1);
		assert(r.rows == 1);
		assert(r.columns == 1);
		assert(r[0][0].as!int == 1);

		writeln("\t\t * async");

		q.runAsync(1);
		r = c.lastResult();
		assert(r.rows == 1);
		assert(r.columns == 1);
		assert(r[0][0].as!int == 1);
	}
}
