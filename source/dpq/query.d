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

	bool runAsync(T...)(T params)
	{
		foreach (p; params)
			addParam(p);

		return runAsync();
	}

	bool runAsync()
	{
		if (_params.length > 0)
		{
			_connection.sendParams(_command, _params);
			return true; // FIXME: must return actual sendQueryParams status
		}

		return _connection.send(_command);
	}
}
