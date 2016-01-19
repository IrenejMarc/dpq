module dpq.result;

import derelict.pq.pq;

import std.stdio;
import std.string;
import std.typecons;
import std.datetime;

import dpq.value;
import dpq.exception;

struct Result
{
	PGresult* _result;
	private TickDuration _time;

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
		const(ubyte)* data = PQgetvalue(_result, row, col);
		int len = PQgetlength(_result, row, col);
		
		return Value(data, len);
	}

	int columnIndex(string col)
	{
		return PQfnumber(_result, cast(const char*)col.toStringz);
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
		return Row(row, this);
	}
}

private struct Row
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

Nullable!T fromBytes(T)(ref const(ubyte)[] bytes)
{	
	import std.bitmanip : read;
	import std.conv : to;


	static if (is(T == string))
	{
		string str = fromStringz(cast(const char*)bytes).to!string;
		return Nullable!string(str);
	}
	else
		return Nullable!T(read!T(bytes));
}
