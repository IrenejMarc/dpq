///
module dpq.result;

import std.conv : to;
import libpq.libpq;

import dpq.serialisation;

import std.stdio;
import std.string;
import std.typecons;
import std.datetime;
import std.traits;

import dpq.value;
import dpq.exception;
import dpq.smartptr;

version(unittest)
{
	import std.stdio;
	import dpq.connection;
	Connection c;
}

struct Result
{
	alias ResultPtr = SmartPointer!(PGresult*, PQclear);
	private ResultPtr _result;
	private TickDuration _time;

	this(PGresult* res)
	{
		if (res == null)
		{
			_result = new ResultPtr(null);
			return;
		}

		ExecStatusType status = PQresultStatus(res);

		switch (status)
		{
			case PGRES_EMPTY_QUERY:
			case PGRES_BAD_RESPONSE:
			case PGRES_FATAL_ERROR:
			{
				string err = PQresultErrorMessage(res).fromStringz.to!string;
				throw new DPQException(status.to!string ~ " " ~ err);
			}
			default:
				break;
		}

		_result = new ResultPtr(res);
	}

	unittest
	{
		import std.exception;

		writeln(" * Result");
		writeln("\t * this(PGresult)");

		c = Connection("host=127.0.0.1 dbname=test user=test");

		auto r = c.execParams("SELECT $1, $2, $3", 1, "two", 123456);
		assertThrown!DPQException(c.exec("SELECT_BAD_SYNTAX 1, 2, 3"));
	}

	@property int rows()
	{
		int n = PQntuples(_result);

		auto str = PQcmdTuples(_result).fromStringz;
		if (n == 0 && str.length > 0)
			return str.to!int();

		return n;
	}

	@property int cmdTuples()
	{
		auto str = PQcmdTuples(_result).fromStringz;
		if (str.length > 0)
			return str.to!int;
		return 0;
	}

	@property int columns()
	{
		return PQnfields(_result);
	}

	unittest
	{
		import dpq.attributes;

		@relation("test_query")
		struct Test
		{
			@serial @PK int id;
			int n;
		}
		c.ensureSchema!Test;

		foreach(i; 0 .. 100)
			c.insert(Test(i, i));

		auto r = c.exec("SELECT 1 FROM test_query");
		writeln("\t * columns");
		assert(r.columns == 1);

		writeln("\t * rows & cmdTuples");
		assert(r.rows == 100, `r.rows == 100`);
		assert(r.cmdTuples == 100, `r.cmdTuples == 0: ` ~ r.cmdTuples.to!string);

		r = c.exec("UPDATE\"test_query\" SET n = n + 1 WHERE n < 50 RETURNING 1");
		assert(r.rows == 50, `r.rows == 50`);
		assert(r.cmdTuples == 50, `r.cmdTuples == 50`);

		c.exec("DROP TABLE test_query");
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
		if (_result is null)
			throw new DPQException("Called get() on a null Result");

		if (row >= rows())
			throw new DPQException("Row %d is out of range, Result has %d rows".format(row, rows()));

		if (col >= columns())
			throw new DPQException("Column %d is out of range, Result has %d columns".format(col, columns()));

		if (PQgetisnull(_result, row, col))
			return Value(null);

		const(ubyte)* data = cast(ubyte *) PQgetvalue(_result, row, col);
		int len = PQgetlength(_result, row, col);
		Oid oid = PQftype(_result, col);
		
		return Value(data, len, cast(Type) oid);
	}

	unittest
	{
		import std.exception;

		writeln("\t * get");
		Result r;
		assertThrown!DPQException(r.get(0, 0));

		int x = 123;
		string s = "some string";

		r = c.execParams("SELECT $1, $2", x, s);
		assert(r.get(0, 0) == Value(x));
		assert(r.get(0, 1) == Value(s));
	}

	int columnIndex(string col)
	{
		int index = PQfnumber(_result, cast(const char*)col.toStringz);
		if (index == -1)
			throw new DPQException("Column " ~ col ~ " was not found");

		return index;
	}

	string columnName(int col)
	{
		return PQfname(_result, col).fromStringz.to!string;
	}

	deprecated("Use columnName instead") 
		alias colName = columnName;

	unittest
	{
		writeln("\t * columnIndex");
		auto r = c.execParams("SELECT $1 col1, $2 col2, $3 col3", 999, 888, 777);

		assert(r.columnIndex("col1") == 0);
		assert(r.columnIndex("col2") == 1);
		assert(r.columnIndex("col3") == 2);

		writeln("\t * columnName");

		assert(r.columnName(0) == "col1");
		assert(r.columnName(1) == "col2");
		assert(r.columnName(2) == "col3");
	}

	/**
		Make result satisfy the IsInputRange constraints so we can use it
		with functions like map, each, ...

		Kinda hackish for now.
	 */
	int currentRangeIndex = 0;
	@property bool empty()
	{
		return currentRangeIndex >= this.rows;
	}

	void popFront()
	{
		++currentRangeIndex;
	}

	@property Row front()
	{
		return Row(currentRangeIndex, this);
	}

	/**
		Support foreach loops, the first version with just the row, and the
		second also providing the index of the row.

		Row is not sent as a reference.
	 */
	int opApply(int delegate(Row) dg)
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

	int opApply(int delegate(int, Row) dg)
	{
		int result = 0;

		for (int i = 0; i < this.rows; ++i)
		{
			auto row = Row(i, this);
			result = dg(i, row);
			if (result)
				break;
		}
		return result;
	}

	Row opIndex(int row)
	{
		return Row(row, this);
	}

	T opCast(T)()
			if (is(T == bool))
	{
		return !isNull();
	}

	@property bool isNull()
	{
		return _result.isNull();
	}
}

//package 
struct Row
{
	private int _row;
	private Result* _parent;
	
	this(int row, ref Result res)
	{
		if (row >= res.rows || row < 0)
			throw new DPQException("Row %d out of range. Result has %d rows.".format(row, res.rows));

		_row = row;
		_parent = &res;
	}

	unittest
	{
		import std.exception;

		writeln(" * Row");
		writeln("\t * this(row, result)");
		auto r = c.execParams("SELECT $1 UNION ALL SELECT $2 UNION ALL SELECT $3", 1, 2, 3);
		assert(r.rows == 3);

		assertThrown!DPQException(Row(3, r));
		assertThrown!DPQException(Row(999, r));
		assertThrown!DPQException(Row(-1, r));

		assertNotThrown!DPQException(Row(0, r));
		assertNotThrown!DPQException(Row(2, r));
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

	unittest
	{
		writeln("\t * opIndex");

		auto res = c.execParams("SELECT $1 c1, $2 c2, $3 c3", 1, 2, 3);
		auto r = Row(0, res);

		assert(r[0] == Value(1));
		assert(r[1] == Value(2));
		assert(r[2] == Value(3));
		assert(r["c1"] == r[0]);
		assert(r["c2"] == r[1]);
		assert(r["c3"] == r[2]);
	}

	int opApply(int delegate(Value) dg)
	{
		int result = 0;

		for (int i = 0; i < _parent.columns; ++i)
		{
			auto val = this[i];
			result = dg(val);
			if (result)
				break;
		}
		return result;
	}

	int opApply(int delegate(string, Value) dg)
	{
		int result = 0;

		for (int i = 0; i < _parent.columns; ++i)
		{
			auto val = this[i];
			string name = _parent.columnName(i);
			result = dg(name, val);
			if (result)
				break;
		}
		return result;
	}

	unittest
	{
		writeln("\t * opApply(Value)");

		auto vs = [1, 2, 3];
		auto cs = ["c1", "c2", "c3"];
		auto r = c.execParams("SELECT $1 c1, $2 c2, $3 c3", vs[0], vs[1], vs[2]);

		int n = 0;
		foreach (v; r[0])
			assert(v == Value(vs[n++]));
		assert(n == 3);

		writeln("\t * opApply(string, Value)");
		n = 0;
		foreach (c, v; r[0])
		{
			assert(c == cs[n]);
			assert(v == Value(vs[n]));
			n += 1;
		}
	}
}


