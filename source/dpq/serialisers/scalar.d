module dpq.serialisers.scalar;

import std.traits;
import std.bitmanip;
import std.typecons;
import std.string : format;

import dpq.serialisation;
import dpq.value : Type;
import dpq.connection : Connection;

import libpq.libpq;

struct ScalarSerialiser
{
	static bool isSupportedType(T)()
	{
		return (T.stringof in _supportedTypes) != null;
	}

	static void enforceSupportedType(T)()
	{
		assert(
				isSupportedType!T,
				"'%s' is not supported by ScalarSerialiser".format(T.stringof));
	}

	static Nullable!(ubyte[]) serialise(T)(T val)
	{
		enforceSupportedType!T;

		alias RT = Nullable!(ubyte[]);
		import std.stdio;

		if (isAnyNull(val))
			return RT.init;

		return RT(nativeToBigEndian(val).dup);
	}
	
	static T deserialise(T)(const(ubyte)[] bytes)
	{
		enforceSupportedType!T;

		return bytes.read!T;
	}

	static Oid oidForType(T)()
	{	
		enforceSupportedType!T;

		return _supportedTypes[T.stringof].oid;
	}

	static string nameForType(T)()
	{
		enforceSupportedType!T;
		
		return _supportedTypes[T.stringof].name;
	}

	static void ensureExistence(T)(Connection c)
	{
		return;
	}

	private struct _Type
	{
		Oid oid;
		string name;
	}

	private static enum _Type[string] _supportedTypes = [
		"bool":   _Type(Type.INT4,   "BOOL"),

		"byte":   _Type(Type.CHAR,   "CHAR"),
		"char":   _Type(Type.CHAR,   "CHAR"),

		"short":  _Type(Type.INT2,   "INT2"),
		"wchar":  _Type(Type.INT2,   "INT2"),

		"int":    _Type(Type.INT4,   "INT4"),
		"dchar":  _Type(Type.INT4,   "INT4"),

		"long":   _Type(Type.INT8,   "INT8"),

		"float":  _Type(Type.FLOAT4, "FLOAT4"),
		"double": _Type(Type.INT4,   "FLOAT8")
	];
}

unittest
{
	import std.stdio;

	writeln(" * ScalarSerialiser");

	// Not much to test here, since it's just a wrapper around D's stdlib

	int a = 123;
	auto serialised = ScalarSerialiser.serialise(a);
	assert(ScalarSerialiser.deserialise!int(serialised) == a);
}
