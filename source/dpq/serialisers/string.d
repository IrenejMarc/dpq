module dpq.serialisers.string;

import dpq.serialisation;
import std.string : representation;
import std.traits;
import std.conv : to;
import std.typecons : Nullable;

struct StringSerialiser
{
	static bool isSupportedType(T)()
	{
		return isSomeString!T;
	}

	static Nullable!(ubyte[]) serialise(T)(T val)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by StringSerialiser".format(T.stringof));

		alias RT = Nullable!(ubyte[]);

		if (isAnyNull(val))
			return RT.init;

		return RT(val.representation.dup);
	}

	static T deserialise(T)(const (ubyte)[] bytes)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by StringSerialiser".format(T.stringof));

		return cast(T) bytes;
	}
}

unittest
{
	import std.stdio;

	writeln(" * StringSerialiser");

	string str = "Aa b";
	auto serialised = StringSerialiser.serialise(str);
	assert(!serialised.isNull);
	writefln("Serialised string %s", serialised);
	assert(str == StringSerialiser.deserialise!string(serialised));
}
