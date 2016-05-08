module dpq.value;

import dpq.result;
import dpq.exception;
import dpq.meta;
import dpq.attributes;
import dpq.connection;
import dpq.serialisation;

//import derelict.pq.pq;
import libpq.libpq;

import std.algorithm : map;
import std.array;
import std.conv : to;
import std.typecons : Nullable, TypedefType;
import std.bitmanip;
import std.traits;
import std.datetime : SysTime, DateTime;

version(unittest) import std.stdio;


package enum Type : Oid
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
	INT8ARRAY = 1016,
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

package Oid[string] customTypes;

struct Value
{
	private
	{
		ubyte[] _valueBytes;
		int _size;
		Type _type;
		bool _isNull;
	}

	this(typeof(null) n)
	{
		_isNull = true;
	}

	this(T)(T val)
	{
		opAssign(val);
	}

	this(T)(T* val, int len, Type type = Type.INFER)
	{
		_size = len;
		_type = type;

		_valueBytes = val[0 .. len].dup;
	}

	void opAssign(T)(T val)
	{
		if (isAnyNull(val))
		{
			_size = 0;
			_valueBytes = null;
			_isNull = true;

			return;
		}

		_valueBytes = toBytes(val);
		_size = _valueBytes.length.to!int;
		_type = cast(Type) oidFor!T;
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

	auto as(T)()
	{
		if (_isNull)
			return Nullable!(NoNullable!T).init;

		ubyte[] data = _valueBytes[0 .. _size];
		return fromBytes!T(data, _size);
	}

	unittest
	{
		import std.typecons : Typedef;

		writeln("\t * as");

		Value v = "123";
		assert(v.as!string == "123");

		v = 123;
		assert(v.as!int == 123);
		assert(v.as!(Nullable!int) == 123);

		v = [[1, 2], [3, 4]];
		assert(v.as!(int[][]) == [[1, 2], [3, 4]]);

		int[2] arr = [1, 2];
		v = arr;

		assert(v.as!(int[2]) == [1, 2]);


		alias MyInt = Typedef!int;
		MyInt x = 2;
		v = Value(x);
		assert(v.as!MyInt == x, v.as!(MyInt).to!string ~ " and " ~ x.to!string ~ " are not equal");
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
