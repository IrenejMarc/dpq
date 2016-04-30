module dpq.serialisers.systime;

import std.datetime : SysTime, DateTime;
import std.typecons : Nullable;
import std.bitmanip;
import core.time;
import dpq.meta;
import dpq.serialisation;

enum POSTGRES_EPOCH = DateTime(2000, 1, 1);

struct SysTimeSerialiser
{
	static bool isSupportedType(T)()
	{
		return is(T == SysTime);
	}

	static Nullable!(ubyte[]) serialise(T)(T val)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by SysTimeSerialiser".format(T.stringof));

		alias RT = Nullable!(ubyte[]);

		if (isAnyNull(val))
			return RT.init;

		// stdTime is in hnsecs, psql wants microsecs
		long diff = val.stdTime - SysTime(POSTGRES_EPOCH).stdTime;
		return RT(nativeToBigEndian(diff / 10).dup);
	}

	static T deserialise(T)(const (ubyte)[] bytes)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by SysTimeSerialiser".format(T.stringof));

		return SysTime(fromBytes!long(bytes) * 10 + SysTime(POSTGRES_EPOCH).stdTime);
	}
}
