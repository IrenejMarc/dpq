module dpq.result;

import derelict.pq.pq;

import std.stdio;
import std.string;
import std.typecons;
import std.datetime;
import std.traits;

import dpq.value;
import dpq.exception;
import dpq.pgarray;

struct Result
{
	PGresult* _result;
	private TickDuration _time;

	@disable this(this);

	this(PGresult* res)
	{
		ExecStatusType status = PQresultStatus(res);

		switch (status)
		{
			case ExecStatusType.PGRES_EMPTY_QUERY:
			case ExecStatusType.PGRES_BAD_RESPONSE:
			case ExecStatusType.PGRES_FATAL_ERROR:
			{
				string err = PQresultErrorMessage(res).fromStringz.to!string;
				throw new DPQException(status.to!string ~ " " ~ err);
			}
			default:
				break;
		}

		_result = res;
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

	@property TickDuration time()
	{
		return _time;
	}

	@property package void time(TickDuration time)
	{
		_time = time;
	}

	Value get(int row, int col)
	{
		if (PQgetisnull(_result, row, col))
			return Value(null);

		const(ubyte)* data = PQgetvalue(_result, row, col);
		int len = PQgetlength(_result, row, col);
		
		return Value(data, len);
	}

	int columnIndex(string col)
	{
		int index = PQfnumber(_result, cast(const char*)col.toStringz);
		if (index == -1)
			throw new DPQException("Column " ~ col ~ " was not found");

		return index;
	}

	int opApply(int delegate(ref Row) dg)
	{
		int result = 0;

		for (int i = 0; i < this.rows; ++i)
		{
			auto row = Row(i, this);
			result = dg(row);
			if (result)
				break;
		}
		return result;
	}

	Row opIndex(int row)
	{
		if (row >= rows())
			throw new DPQException("Row %d out of range. Result has %d rows.".format(row, rows()));
		return Row(row, this);
	}
}

package struct Row
{
	private int _row;
	private Result* _parent;
	
	this(int row, ref Result res)
	{
		_row = row;
		_parent = &res;
	}

	Value opIndex(int col)
	{
		return _parent.get(_row, col);
	}

	Value opIndex(string col)
	{
		int c = _parent.columnIndex(col);
		return opIndex(c);
	}
}

Nullable!T fromBytes(T)(ref const(ubyte)[] bytes, int len = 0)
{	
	import std.bitmanip;
	import std.conv : to;

	alias TU = Unqual!T;

	static if (is(TU == string))
	{
		string str = cast(string)bytes[0 .. len];
		return Nullable!string(str);
	}
	else static if (is(TU == ubyte[]))
		return Nullable!T(bytes.dup);
	else static if (isArray!T)
	{
		auto arr = PGArray(bytes);
		return Nullable!T(cast(T)arr);
	}
	else
		return Nullable!T(bigEndianToNative!(T, T.sizeof)(bytes.to!(ubyte[T.sizeof])));
		//return Nullable!T(read!T(bytes));
}
