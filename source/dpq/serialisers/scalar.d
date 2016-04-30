module dpq.serialisers.scalar;

import std.traits;
import std.bitmanip;
import std.typecons;
import std.string : format;

import dpq.serialisation;

struct ScalarSerialiser
{
	static bool isSupportedType(T)()
	{
		return isScalarType!T;
	}

	static Nullable!(ubyte[]) serialise(T)(T val)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by ScalarSerialiser".format(T.stringof));

		alias RT = Nullable!(ubyte[]);
		import std.stdio;

		if (isAnyNull(val))
			return RT.init;

		return RT(nativeToBigEndian(val).dup);
	}
	
	static T deserialise(T)(const(ubyte)[] bytes)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by ScalarSerialiser".format(T.stringof));

		return bytes.read!T;
	}
}
