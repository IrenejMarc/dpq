///
module dpq.serialisers.string;

import dpq.serialisation;
import dpq.connection : Connection;
import std.string : representation;
import std.traits;
import std.conv : to;
import std.typecons : Nullable;
import libpq.libpq : Oid;
import dpq.value : Type;

struct StringSerialiser
{
   static bool isSupportedType(T)()
   {
      return isSomeString!T;
   }

   static Nullable!(ubyte[]) serialise(T)(T val)
   {
      static assert(isSupportedType!T, "'%s' is not supported by StringSerialiser".format(T.stringof));

      alias RT = Nullable!(ubyte[]);

      if (isAnyNull(val))
         return RT.init;

      return RT(val.representation.dup);
   }

   static T deserialise(T)(const(ubyte)[] bytes)
   {
      static assert(isSupportedType!T, "'%s' is not supported by StringSerialiser".format(T.stringof));

      // Is casting good enough? Let's hope so
      return cast(T)bytes;
   }

   static Oid oidForType(T)()
   {
      return Type.TEXT;
   }

   static string nameForType(T)()
   {
      return "TEXT";
   }

   static void ensureExistence(T)(Connection c)
   {
      return;
   }
}

unittest
{
   import std.stdio;

   writeln(" * StringSerialiser");

   string str = "1234567890qwertyuiop[]asdfghjkl;'zxcvbnm,./ščžèéêëē";
   auto serialised = StringSerialiser.serialise(str);
   assert(str == StringSerialiser.deserialise!string(serialised.get));
}
