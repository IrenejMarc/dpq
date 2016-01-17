module dpq.result;

import derelict.pq.pq;

import std.stdio;
import std.string;
import std.typecons;

struct SQLResult
{
	PGresult* _result;

	this(PGresult* res)
	{
		auto status = PQresultStatus(res);
		writeln("Status is: ", PQresStatus(status).fromStringz);


		_result = res;

		// TODO: result work
	}

	~this()
	{
		PQclear(_result);
	}

	@property int rows()
	{
		return PQntuples(_result);
	}

	@property int columns()
	{
		return PQnfields(_result);
	}

	Nullable!T get(T)(int row, int col)
	{
		import std.bitmanip;
		import std.conv : to;

		if (PQgetisnull(_result, row, col) == 1)
			return Nullable!T();

		const(ubyte)* data = PQgetvalue(_result, row, col);
		int len = PQgetlength(_result, row, col);

		ubyte[] dataArr = new ubyte[len];
		for (int i = 0; i < len; ++i)
			dataArr[i] = data[i];

		static if (is(T == string))
		{
			string str = fromStringz(cast(const char*)data).to!string;
			return Nullable!string(str);
		}
		else
			return Nullable!T(read!T(dataArr));
	}
}
