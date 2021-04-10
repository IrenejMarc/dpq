///
module dpq.serialisers.systime;

import dpq.connection : Connection;
import dpq.serialisation;
import dpq.value : Type;

import libpq.libpq : Oid;

import std.bitmanip : nativeToBigEndian;
import std.datetime : SysTime, DateTime;
import std.typecons : Nullable;

enum POSTGRES_EPOCH = DateTime(2000, 1, 1);

struct SysTimeSerialiser
{
   static bool isSupportedType(T)()
   {
      return is(T == SysTime);
   }

   static Nullable!(ubyte[]) serialise(T)(T val)
   {
      import std.datetime.timezone : UTC;

      static assert(isSupportedType!T, "'%s' is not supported by SysTimeSerialiser".format(T.stringof));

      alias RT = Nullable!(ubyte[]);

      if (isAnyNull(val))
      {
         return RT.init;
      }
      // stdTime is in hnsecs, psql wants microsecs
      long diff = val.stdTime - SysTime(POSTGRES_EPOCH, UTC()).stdTime;
      return RT(nativeToBigEndian(diff / 10).dup);
   }

   static T deserialise(T)(const(ubyte)[] bytes)
   {
      static assert(isSupportedType!T, "'%s' is not supported by SysTimeSerialiser".format(T.stringof));

      import std.datetime.timezone : UTC;

      return SysTime(fromBytes!long(bytes, long.sizeof).get * 10 + SysTime(POSTGRES_EPOCH, UTC()).stdTime);
   }

   static Oid oidForType(T)()
   {
      return Type.TIMESTAMP;
   }

   static string nameForType(T)()
   {
      return "TIMESTAMP";
   }

   static void ensureExistence(T)(Connection c)
   {
      return;
   }
}

unittest
{
   import std.stdio;
   import std.datetime;

   writeln(" * SysTimeSerialiser");

   // In reality, we should probably only check up to msec accuracy,
   // and I'm not sure how much SysTimes == checks.
   SysTime time = Clock.currTime;
   auto serialised = SysTimeSerialiser.serialise(time);

   assert(SysTimeSerialiser.deserialise!SysTime(serialised.get).toUnixTime == time.toUnixTime);
}
