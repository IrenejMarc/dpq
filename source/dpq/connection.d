module dpq.connection;

import derelict.pq.pq;

import dpq.exception;
import dpq.result;
import dpq.value;

import std.string;
import derelict.pq.pq;
import std.conv : to;

struct Connection
{
	private PGconn* _connection;

	this(string connString)
	{
		char* err;
		auto opts = PQconninfoParse(cast(char*)connString.toStringz, &err);

		if (err != null)
		{
			throw new DPQException(err.fromStringz.to!string);
		}

		_connection = PQconnectdb(connString.toStringz);
	}

	~this()
	{
		PQfinish(_connection);
	}

	void close()
	{
		PQfinish(_connection);
		_connection = null;
	}

	@property const(string) db()
	{
		return PQdb(_connection).to!string;
	}

	@property const(string) user()
	{
		return PQuser(_connection).to!string;
	}

	@property const(string) password()
	{
		return PQpass(_connection).to!string;
	}

	@property const(string) host()
	{
		return PQhost(_connection).to!string;
	}
	@property const(string) port()
	{
		return PQport(_connection).to!string;
	}

	Result exec(string command)
	{
		PGresult* res = PQexec(_connection, cast(const char*)command.toStringz);
		return Result(res);
	}

	Result execParams(T...)(string command, T params)
	{
		Value[] values;
		foreach(param; params)
			values ~= Value(param);

		const char* cStr = cast(const char*) command.toStringz;

		import std.stdio;
		writeln("nParams: ", values.length);
		auto pTypes = values.paramTypes;
		auto pValues = values.paramValues;
		auto pLengths = values.paramLengths;
		auto pFormats = values.paramFormats;

		writeln("paramTypes: ", pTypes);
		writeln("paramValues: ", pValues);
		writeln("paramLengths: ", pLengths);
		writeln("paramFormats: ", pFormats);

		auto res = PQexecParams(
				_connection, 
				cStr, 
				values.length.to!int, 
				pTypes.ptr, 
				pValues.ptr,
				pLengths.ptr,
				pFormats.ptr,
				1);

		return SQLResult(res);
	}

	@property string errorMessage()
	{
		return PQerrorMessage(_connection).to!string;
	}

	//PQoptions
	//PQstatus
	//PQtransactionStatus
}

shared static this()
{
	DerelictPQ.load();
}
