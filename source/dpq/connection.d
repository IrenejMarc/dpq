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
		_dpqLastConnection = &this;
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

		return execParams(command, values);
	}

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

	@property string errorMessage()
	{
		return PQerrorMessage(_connection).to!string;
	}

	//PQoptions
	//PQstatus
	//PQtransactionStatus
}

package Connection* _dpqLastConnection;

shared static this()
{
	DerelictPQ.load();
}
