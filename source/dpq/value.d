module dpq.value;

import dpq.result;

import derelict.pq.pq;

import std.algorithm : map;
import std.variant;
import std.array;
import std.conv : to;
import std.typecons : Nullable;

private enum Type : Oid
{
	INFER = 0,
	BOOL = 16,
	BYTEA = 17,
	CHAR = 18,
	NAME = 19,
	INT8 = 20,
	INT2 = 21,
	INT2VECTOR = 22,
	INT4 = 23,
	REGPROC = 24,
	TEXT = 25,
	OID = 26,
	TID = 27,
	XID = 28,
	CID = 29,
	OIDVECTOR = 30,
	JSON = 114,
	XML = 142,
	PGNODETREE = 194,
	POINT = 600,
	LSEG = 601,
	PATH = 602,
	BOX = 603,
	POLYGON = 604,
	LINE = 628,
	FLOAT4 = 700,
	FLOAT8 = 701,
	ABSTIME = 702,
	RELTIME = 703,
	TINTERVAL = 704,
	UNKNOWN = 705,
	CIRCLE = 718,
	CASH = 790,
	MACADDR = 829,
	INET = 869,
	CIDR = 650,
	INT2ARRAY = 1005,
	INT4ARRAY = 1007,
	TEXTARRAY = 1009,
	OIDARRAY = 1028,
	FLOAT4ARRAY = 1021,
	ACLITEM = 1033,
	CSTRINGARRAY = 1263,
	BPCHAR = 1042,
	VARCHAR = 1043,
	DATE = 1082,
	TIME = 1083,
	TIMESTAMP = 1114,
	TIMESTAMPTZ = 1184,
	INTERVAL = 1186,
	TIMETZ = 1266,
	BIT = 1560,
	VARBIT = 1562,
	NUMERIC = 1700,
	REFCURSOR = 1790,
	REGPROCEDURE = 2202,
	REGOPER = 2203,
	REGOPERATOR = 2204,
	REGCLASS = 2205,
	REGTYPE = 2206,
	REGTYPEARRAY = 2211,
	UUID = 2950,
	LSN = 3220,
	TSVECTOR = 3614,
	GTSVECTOR = 3642,
	TSQUERY = 3615,
	REGCONFIG = 3734,
	REGDICTIONARY = 3769,
	JSONB = 3802,
	INT4RANGE = 3904,
	RECORD = 2249,
	RECORDARRAY = 2287,
	CSTRING = 2275,
	ANY = 2276,
	ANYARRAY = 2277,
	VOID = 2278,
	TRIGGER = 2279,
	EVTTRIGGER = 3838,
	LANGUAGE_HANDLER = 2280,
	INTERNAL = 2281,
	OPAQUE = 2282,
	ANYELEMENT = 2283,
	ANYNONARRAY = 2776,
	ANYENUM = 3500,
	FDW_HANDLER = 3115,
	ANYRANGE = 3831,
}

struct Value
{
	private
	{
		ubyte[] _valueBytes;
		int _size;
		Type _type;
	}

	this(T)(T val)
	{
		opAssign(val);
	}

	this(T)(T* val, int len, Type type = Type.INFER)
	{
		_size = len;
		_type = type;

		for (int i = 0; i < len; ++i)
			_valueBytes ~= val[i];
	}

	this(Value val)
	{
		opAssign(val);
	}

	void opAssign(T)(T val)
	{
		import std.bitmanip;

		_size = val.sizeof;

		_valueBytes = new ubyte[_size];
		write(_valueBytes, val, 0);


		alias TU = std.typecons.Unqual!T;

		static if (is(TU == int))
			_type = Type.INT4;
		else static if (is(TU == int[]))
			_type = Type.INT4ARRAY;
		else static if (is(TU == long))
			_type = Type.INT8;
		//else static if (is(TU == long[]))
		//	_type = Type.INT8ARRAY; // Does not exist?
		else static if (is(TU == bool))
			_type = Type.BOOL;
		//else static if (is(TU == bool[]))
		//	_type = Type.;
		else static if (is(TU == byte))
			_type = Type.INT2;
		else static if (is(TU == byte[]))
			_type = Type.INT2ARRAY;
		else static if (is(TU == char))
			_type = Type.CHAR;
		else static if (is(TU == char[]))
			_type = Type.TEXT;
		else static if (is(TU == short))
			_type = Type.INT2;
		else static if (is(TU == short[]))
			_type = Type.INT2ARRAY;
		else static if (is(TU == float))
			_type = Type.FLOAT4;
		else static if (is(TU == float[]))
			_type = Type.FLOAT4ARRAY;
		else static if (is(TU == double))
			_type = Type.FLOAT8;
		//else static if (is(TU == double[]))
		//	type = Type.;
		else
			// Try to infer
			_type = Type.INFER;
	}

	void opAssign(string val)
	{
		_valueBytes = cast(ubyte[])val.dup;
		_size = _valueBytes.length.to!int;
		_type = Type.TEXT;
	}
	
	void opAssign(Value val)
	{
		_valueBytes = val._valueBytes;
		_size = val._size;
		_type = val._type;
	}

	@property int size()
	{
		return _size;
	}

	@property Oid type()
	{
		return _type;
	}
	
	@property const(ubyte)* valuePointer()
	{
		return _valueBytes.ptr;
	}

	Nullable!T as(T)()
	{
		import std.bitmanip;
		const(ubyte)[] data = _valueBytes[0 .. _size];

		return fromBytes!T(data);
	}
}

Oid[] paramTypes(Value[] values)
{
	return array(values.map!(v => v.type));
}

int[] paramLengths(Value[] values)
{
	return array(values.map!(v => v.size));
}

int[] paramFormats(Value[] values)
{
	return array(values.map!(v => 1));
}

const(ubyte)*[] paramValues(Value[] values)
{
	return array(values.map!(v => v.valuePointer));
}
