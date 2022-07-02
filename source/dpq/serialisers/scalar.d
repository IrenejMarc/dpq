///
module dpq.serialisers.scalar;

import dpq.serialisation;
import dpq.value : Type;
import dpq.connection : Connection;

import libpq.libpq;

import std.bitmanip : nativeToBigEndian, read;
import std.string : format;
import std.typecons : Nullable;

struct ScalarSerialiser
{
	static bool isSupportedType(T)()
	{
		return (T.stringof in _supportedTypes) != null;
	}

	static void enforceSupportedType(T)()
	{
		static assert(
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

		auto bytes = nativeToBigEndian(val);
		return RT(bytes.dup);
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
		"bool":   _Type(Type.BOOL,   "BOOL"),

		"byte":   _Type(Type.CHAR,   "CHAR"),
		"char":   _Type(Type.CHAR,   "CHAR"),

		"short":  _Type(Type.INT2,   "INT2"),
		"wchar":  _Type(Type.INT2,   "INT2"),

		"int":    _Type(Type.INT4,   "INT4"),
		"dchar":  _Type(Type.INT4,   "INT4"),

		"long":   _Type(Type.INT8,   "INT8"),

		"float":  _Type(Type.FLOAT4, "FLOAT4"),
		"double": _Type(Type.FLOAT8,   "FLOAT8")
	];
}

unittest
{
	import std.stdio;

	writeln(" * ScalarSerialiser");

	// Not much to test here, since it's just a wrapper around D's stdlib

	int a = 123;
	auto serialised = ScalarSerialiser.serialise(a);
	assert(ScalarSerialiser.deserialise!int(serialised.get) == a);
}
