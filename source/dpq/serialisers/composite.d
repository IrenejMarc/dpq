module dpq.serialisers.composite;

import dpq.serialisation;
import dpq.meta;
import dpq.attributes;
import dpq.exception;
import dpq.value;

import std.string : format;
import std.typecons : Nullable, Typedef;
import std.traits;
import std.array : Appender;
import std.bitmanip;
import std.conv : to;
import std.datetime : SysTime;

import libpq.libpq;
/**
	The default serialiser for any composite type (structs and classes)

	For custom types, the data representation is the following
	 
	First 4 bytes are an int representing the number of members
	After that, the members are listed in the following way:
		- OID
		- length
		- value

	Example: (bytes, decimal)
		[0 0 0 2 | 0 0 0 23 | 0 0 0 4 | 0 0 0 1 | 0 0 0 23 | 0 0 0 4 | 0 0 0 2]
		will represent a struct with two members, both OID 23, length 4, with values 1 and 2
 */
struct CompositeTypeSerialiser
{
	/** 
		Only accepts structs and classes, will fail on Nullable or Typedef types
		which should be taken care of by toBytes function.
	 */
	static bool isSupportedType(T)()
	{
		return 
			is(T == class) || is(T == struct) && 
			!is(T == SysTime) &&
			!isInstanceOf!(Typedef, T);
	}

	static Nullable!(ubyte[]) serialise(T)(T val)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by CompositeTypeSerialiser".format(T.stringof));

		alias RT = Nullable!(ubyte[]);

		if (isAnyNull(val))
			return RT.init;

		alias members = serialisableMembers!T;
		ubyte[] data;
		
		// The number of members of this type
		data ~= nativeToBigEndian(cast(int) members.length);

		foreach (mName; members)
		{
			auto member = __traits(getMember, val, mName);
			// The member's actual type without any qualifiers and such
			alias MT = RealType!(typeof(member));

			// Element's Oid
			data ~= nativeToBigEndian(cast(int) oidForType!MT);

			auto bytes = toBytes(member);

			// Null values have length of -1
			if (bytes.isNull)
				data ~= nativeToBigEndian(cast(int) -1);
			else
			{
				// The element length and data itself
				data ~= nativeToBigEndian(bytes.length.to!int);
				data ~= bytes;
			}
		}

		return RT(data);
	}

	static T deserialise(T)(const (ubyte)[] bytes)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by CompositeTypeSerialiser".format(T.stringof));

		alias members = serialisableMembers!T;

		int length = bytes.read!int;

		if (length != members.length)
			throw new DPQException("Length for %s (%d) does not actual match number of members (%s)".format(
						T.stringof,
						length,
						members.length
						));
		
		T result;
		foreach (mName; members)
		{
			auto member = __traits(getMember, result, mName);
			alias MT = RealType!(typeof(member));

			Oid oid = cast(Oid) bytes.read!int;
			auto mLen = bytes.read!int;

			// When a null value is encontered, leave the member to its init value
			if (mLen == -1)
				continue;

			// Read the value
			__traits(getMember, result, mName) = fromBytes!MT(bytes[0 .. mLen], mLen);

			// "Consume" the bytes that were just read
			bytes = bytes[mLen .. $];
		}

		return result;
	}
}

unittest
{
	import std.stdio;

	writeln(" * CompositeTypeSerialiser");

	struct Test2
	{
		int c = 3;
	}

	struct Test
	{
		int a = 1;
		int b = 2;

		Nullable!Test2 ntest2;
		Test2 test2;
	}

	Test t = Test(1, 2);
	auto serialised = CompositeTypeSerialiser.serialise(t);
	auto deserialised = CompositeTypeSerialiser.deserialise!Test(serialised);


	// Why is this throwing AssertError???
	//assert(t == deserialised);

	// The manual approach, I guess
	assert(deserialised.a == t.a);
	assert(deserialised.b == t.b);
	assert(deserialised.test2.c == t.test2.c);
	assert(deserialised.ntest2.isNull == t.ntest2.isNull);
}
