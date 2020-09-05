///
module dpq.meta;

import dpq.attributes;

import std.traits;
import std.typecons : Nullable;
import std.datetime : SysTime;

version(unittest) import std.stdio;

/**
   Returns the array's base type

   Returns the string type for any type that returns true
   for isSomeString!T

   Examples:
   ---------------
   alias T = BaseType!(int[][]);
   alias T2 = BaseType!(int[]);
   alias T3 = BaseType!int;
   alias T4 = BaseType!(string[])

   static assert(is(T == int));
   static assert(is(T2 == int));
   static assert(is(T3 == int));
   static assert(is(T4 == string));
   ---------------
*/
template BaseType(T)
{
   import std.typecons : TypedefType;
   static if (isArray!T && !isSomeString!T)
      alias BaseType = BaseType!(ForeachType!T);
   else
      alias BaseType = TypedefType!(Unqual!T);
}

unittest
{
   writeln(" * meta");
   writeln("\t * BaseType");

   static assert(is(BaseType!(int[][][]) == int));
   static assert(is(BaseType!(string[]) == string));
   static assert(is(BaseType!string == string));
   static assert(is(BaseType!dstring == dstring));
}

/**
   Returns the number of dimensions of the given array type

   Examples:
   -----------------
   auto dims = ArrayDimensions!(int[][]);
   static assert(dims == 2);
   -----------------
 */
deprecated("Use ArraySerialier's ArrayDimensions instead")
template ArrayDimensions(T)
{
   static if (isArray!T)
      enum ArrayDimensions = 1 + ArrayDimensions!(ForeachType!T);
   else
      enum ArrayDimensions = 0;
}


/// Removes any Nullable specifiers, even multiple levels
template NoNullable(T)
{
   static if (isInstanceOf!(Nullable, T))
      // Nullable nullable? Costs us nothing, so why not
      alias NoNullable = NoNullable!(Unqual!(ReturnType!(T.get)));
   else
      alias NoNullable = T;
}

/**
   Will strip off any Nullable, Typedefs and qualifiers from a given type.
   It's a bit paranoid and tries to remove any identifiers multiple times, until
   the removal attempt yields no changes, but it shouldn't be a problem since it's
   all just compile-time.

   Examples:
      static assert(RealType!(const Nullable!(immutable int) == int));
 */
template RealType(T)
{
   import std.typecons : TypedefType;
   // Ugly, but better than doing this every time we need it
   alias NT = OriginalType!(Unqual!(NoNullable!(TypedefType!T)));

   static if (is(T == NT))
      alias RealType = NT;
   else
      alias RealType = RealType!NT;
}
