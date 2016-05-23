///
module dpq.serialisers.bytea;

import libpq.libpq : Oid;
import dpq.value : Type;
import dpq.connection : Connection;

struct ByteaSerialiser
{
	static bool isSupportedType(T)()
	{
		return is(T == byte[]) || is(T == ubyte[]);
	}

	static void enforceSupportedType(T)()
	{
		static assert(
				isSupportedType!T,
				"'%s' is not supported by ByteaSerialiser".format(T.stringof));
	}

	static T deserialise(T)(const(ubyte)[] val)
	{
		enforceSupportedType!T;

		return val.dup;
	}

	static ubyte[] serialise(T)(T val)
	{
		enforceSupportedType!T;

		return cast(ubyte[]) val;
	}

	static Oid oidForType(T)()
	{
		enforceSupportedType!T;

		return Type.BYTEA;
	}

	static string nameForType(T)()
	{
		enforceSupportedType!T;

		return "BYTEA";
	}

	static void ensureExistence(T)(Connection conn)
	{
		return;
	}
}
