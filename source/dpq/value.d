module dpq.value;

import derelict.pq.pq;

import std.algorithm : map;
import std.variant;
import std.array;
import std.conv : to;

struct SQLValue
{
	ubyte[] _valueBytes;
	private int _size;

	this(T)(T val)
	{
		import std.bitmanip;

		_size = val.sizeof;

		_valueBytes = new ubyte[_size];
		write(_valueBytes, val, 0);
		std.stdio.writeln("ByteArray: ", _valueBytes);
	}

	this(string val)
	{
		_valueBytes = cast(ubyte[])val.dup;
		_size = _valueBytes.length.to!int;
	}

	@property int size()
	{
		return _size;
	}

	@property Oid type()
	{
		// TODO: Find out the Oid of a type and return that
		return 0;
	}
	
	@property const(ubyte)* valuePointer()
	{
		return _valueBytes.ptr;
	}
}

Oid[] paramTypes(SQLValue[] values)
{
	return array(values.map!(v => v.type));
}

int[] paramLengths(SQLValue[] values)
{
	return array(values.map!(v => v.size));
}

int[] paramFormats(SQLValue[] values)
{
	return array(values.map!(v => 1));
}

const(ubyte)*[] paramValues(SQLValue[] values)
{
	return array(values.map!(v => v.valuePointer));
}
