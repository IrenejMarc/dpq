module dpq.value;

import dpq.result;

import derelict.pq.pq;

import std.algorithm : map;
import std.variant;
import std.array;
import std.conv : to;
import std.typecons : Nullable;

struct Value
{
	ubyte[] _valueBytes;
	private int _size;

	this(T)(T val)
	{
		this.opAssign(val);
	}

	this(T)(T* val, int len)
	{
		_size = len;
		for (int i = 0; i < len; ++i)
			_valueBytes ~= val[i];
	}

	void opAssign(T)(T val)
	{
		import std.bitmanip;

		_size = val.sizeof;

		_valueBytes = new ubyte[_size];
		write(_valueBytes, val, 0);
	}

	void opAssign(string val)
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
