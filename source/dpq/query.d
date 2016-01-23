module dpq.query;

import dpq.connection;
import dpq.value;
import dpq.exception;
import dpq.value;
import dpq.result;

struct Query
{
	private string _command;
	private Value[] _params;
	private Connection* _connection;

	this(ref Connection connection, string command)
	{
		_connection = &connection;
		_command = command;
	}

	this(string command)
	{
		if (_dpqLastConnection == null)
			throw new DPQException("Query: No established connection was found and none was provided.");

		_connection = _dpqLastConnection;
		_command = command;
	}

	this(ref Connection conn, string command, Value[] params)
	{
		this(conn, command);
		_params = params;
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
		auto r = _connection.execParams(_command, _params);
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
}
