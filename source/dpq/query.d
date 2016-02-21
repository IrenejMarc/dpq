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

struct Query
{
	private string _command;
	private Value[] _params;
	private Connection* _connection;

	this(string command, Value[] params = [])
	{
		if (_dpqLastConnection == null)
			throw new DPQException("Query: No established connection was found and none was provided.");

		_connection = _dpqLastConnection;
		_command = command;
		_params = params;
	}

	this(ref Connection conn, string command = "", Value[] params = [])
	{
		_connection = &conn;
		_command = command;
		_params = params;
	}


	unittest
	{
		writeln(" * Query");

		c = Connection("dbname=test user=test");

		writeln("\t * this()");
		Query q;
		assert(q._connection == null);

		writeln("\t * this(command, params[])");
		string cmd = "some command";
		q = Query(cmd);
		assert(q._connection != null, `not null 2`);
		assert(q._command == cmd, `cmd`);
		assert(q._params == [], `empty arr`);

		Connection c2 = Connection("dbname=test user=test");
		writeln("\t * this(Connection, command, params[])");
		q = Query(c2);
		assert(q._connection == &c2);

		q = Query(cmd);
		assert(q._connection == &c2);
	}

	@property void connection(ref Connection conn)
	{
		_connection = &conn;
	}

	@property string command()
	{
		return _command;
	}
	
	@property void command(string c)
	{
		_command = c;
	}

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

	ref Query opBinary(string op, T)(T val)
			if (op == "<<")
	{
		addParam(val);
		return this;
	}

	void opAssign(string str)
	{
		command = str;
	}

	@property Result run()
	{
		import std.datetime;

		StopWatch sw;
		sw.start();

		Result r = _connection.execParams(_command, _params);
		sw.stop();

		r.time = sw.peek();
		return r;
	}

	Result run(T...)(T params)
	{
		foreach (p; params)
			addParam(p);

		return run();
	}

	unittest
	{
		writeln("\t * run");

		auto c = Connection("dbname=test user=test");
		
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

	bool runAsync(T...)(T params)
	{
		foreach (p; params)
			addParam(p);

		return runAsync();
	}

	bool runAsync()
	{
		_connection.sendParams(_command, _params);
		return true; // FIXME: must return the actual result from PQsendQueryParams
	}
}
