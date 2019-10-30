///
module dpq.serialisation;

// TODO: merge all serialisers' imports
import dpq.serialisers.composite;
import dpq.serialisers.array;
import dpq.serialisers.scalar;
import dpq.serialisers.systime;
import dpq.serialisers.string;
import dpq.serialisers.bytea;

import dpq.meta;
import dpq.attributes;
import dpq.value : Type;

import std.datetime : SysTime, DateTime;
import std.typecons : Nullable, TypedefType;
import std.traits;
import std.bitmanip;
import std.string : format;
import std.meta;

import libpq.libpq;


/**
	Converts the given type to an ubyte[], as PostgreSQL expects it. Ignores
	any Nullable specifiers and Typedefs.
 */
package Nullable!(ubyte[]) toBytes(T)(T val)
{
	alias AT = RealType!T;

	if (isAnyNull(val))
		return Nullable!(ubyte[]).init;

	alias serialiser = SerialiserFor!AT;
auto x  = serialiser.serialise(cast(AT) val);
	return Nullable!(ubyte[])(x.get);
}

/*****************************************************************************/

struct SerialiserAttribute(alias T)
{
	alias serialiser = T;
}

SerialiserAttribute!T serialiser(alias T)()
{
	return SerialiserAttribute!T();
}

template SerialiserFor(T)
	if (isBuiltinType!T)
{
	static if (isSomeString!T)
		alias SerialiserFor = StringSerialiser;
	else static if (is(T == ubyte[]))
		alias SerialiserFor = ByteaSerialiser;
	else static if (isArray!T)
		alias SerialiserFor = ArraySerialiser;
	else static if (isScalarType!T)
		alias SerialiserFor = ScalarSerialiser;
}

template SerialiserFor(alias T)
	if (!isBuiltinType!T)
{
	import std.meta;

	alias UDAs = getUDAs!(T, SerialiserAttribute);

	// First see if a custom serialiser is specified for the type
	static if (UDAs.length > 0)
		alias SerialiserFor = UDAs[0].serialiser;
	else
	{
		alias RT = RealType!T;

		static if (isBuiltinType!RT)
			alias SerialiserFor = SerialiserFor!RT;
		// Otherwise, pick one from the bunch of pre-set ones.
		else static if (isArray!RT)
			alias SerialiserFor = ArraySerialiser;
		// Support for SysTime
		else static if (is(RT == SysTime))
			alias SerialiserFor = SysTimeSerialiser;
		else static if (is(RT == class) || is(RT == struct))
			alias SerialiserFor = CompositeTypeSerialiser;
		else
			static assert(false, "Cannot find serialiser for " ~ T.stringof);
	}
}

unittest
{
	import std.stdio;

	writeln(" * SerialiserFor");

	struct Test1 {}

	static assert(is(SerialiserFor!int == ScalarSerialiser));
	static assert(is(SerialiserFor!Test1 == CompositeTypeSerialiser));
	static assert(is(SerialiserFor!(int[][]) == ArraySerialiser));
	static assert(is(SerialiserFor!(Test1[][]) == ArraySerialiser));

	@serialiser!Test1() struct Test2 {}

	static assert(is(SerialiserFor!Test2 == Test1));
}

package T fromBytes(T)(const(ubyte)[] bytes, size_t len = 0)
		if (isInstanceOf!(Nullable, T))
{
	alias AT = RealType!T;

	return T(fromBytes!AT(bytes, len));
}

package Nullable!T fromBytes(T)(const(ubyte)[] bytes, size_t len = 0)
		if (!isInstanceOf!(Nullable, T))
{
	if (len == -1)
		return Nullable!T.init;

	alias AT = RealType!T;

	return Nullable!T(cast(T) fromBytesImpl!AT(bytes, len));
}

package T fromBytesImpl(T)(const(ubyte)[] bytes, size_t len)
{
	alias serialiser = SerialiserFor!T;
	return Nullable!T(serialiser.deserialise!T(bytes[0 .. len])).get;
}

unittest
{
	import std.bitmanip;
	import std.string;
	import std.stdio;

	writeln(" * fromBytes");

	int x = 123;

	const (ubyte)[] bs = nativeToBigEndian(x);
	assert(fromBytes!int(bs, x.sizeof) == x);

	x = -555;
	bs = nativeToBigEndian(x);
	assert(fromBytes!int(bs, x.sizeof) == x);

	x = int.min;
	bs = nativeToBigEndian(x);
	assert(fromBytes!int(bs, x.sizeof) == x);

	x = int.max;
	bs = nativeToBigEndian(x);
	assert(fromBytes!int(bs, x.sizeof) == x);

	string s = "some random string";
	assert(fromBytes!string(s.representation, s.representation.length) == s);

	s = "";
	assert(fromBytes!string(s.representation, s.representation.length) == s);
}

/*****************************************************************************/

bool isAnyNull(T)(T val)
{
	static if (is(T == class))
		return val is null;
	else static if (isInstanceOf!(Nullable, T))
		return val.isNull;
	else
		return false;
}

/**
	Shortuct to the type's serialiser's oidForType
 */
Oid oidFor(T)()
{
	alias RT = RealType!T;
	return SerialiserFor!RT.oidForType!RT;
}

deprecated("Use Serialisers and their oidForType instead")
template typeOid(T)
{
		alias TU = std.typecons.Unqual!T;
		static if (isArray!T && !isSomeString!T)
		{
			alias BT = BaseType!T;
			static if (is(BT == int))
				enum typeOid = Type.INT4ARRAY;
			else static if (is(BT == long))
				enum typeOid = Type.INT8ARRAY;
			else static if (is(BT == short))
				enum typeOid = Type.INT2ARRAY;
			else static if (is(BT == float))
				enum typeOid = Type.FLOAT4ARRAY;
			else static if (is(BT == string))
				enum typeOid = Type.TEXTARRAY;
			else static if (is(BT == byte) || is (BT == ubyte))
				enum typeOid = Type.BYTEA;
			else
				static assert(false, "Cannot map array type " ~ T.stringof ~ " to Oid");
		}
		else
		{
			static if (is(TU == int))
				enum typeOid = Type.INT4;
			else static if (is(TU == long))
				enum typeOid = Type.INT8;
			else static if (is(TU == bool))
				enum typeOid = Type.BOOL;
			else static if (is(TU == byte))
				enum typeOid = Type.CHAR;
			else static if (is(TU == char))
				enum typeOid = Type.CHAR;
			else static if (isSomeString!TU)
				enum typeOid = Type.TEXT;
			else static if (is(TU == short))
				enum typeOid = Type.INT2;
			else static if (is(TU == float))
				enum typeOid = Type.FLOAT4;
			else static if (is(TU == double))
				enum typeOid = Type.FLOAT8;
			else static if (is(TU == SysTime))
				enum typeOid = Type.TIMESTAMP;

			/**
				Since unsigned types are not supported by PostgreSQL, we use signed
				types for them. Transfer and representation in D will still work correctly,
				but SELECTing them in the psql console, or as a string might result in
				a negative number.

				It is recommended not to use unsigned types in structures, that will
				be used in the DB directly.
			*/
			else static if (is(TU == ulong))
				enum typeOid = Type.INT8;
			else static if (is(TU == uint))
				enum typeOid = Type.INT4;
			else static if (is(TU == ushort) || is(TU == char))
				enum typeOid = Type.INT2;
			else static if (is(TU == ubyte))
				enum typeOid = Type.CHAR;
			else
				// Try to infer
				enum typeOid = Type.INFER;
		}
}

unittest
{
	import std.stdio;
	writeln("\t * typeOid");

	static assert(typeOid!int == Type.INT4, "int");
	static assert(typeOid!string == Type.TEXT, "string");
	static assert(typeOid!(int[]) == Type.INT4ARRAY, "int[]");
	static assert(typeOid!(int[][]) == Type.INT4ARRAY, "int[][]");
	static assert(typeOid!(ubyte[]) == Type.BYTEA, "ubyte[]");
}

/**
	Custom serialisers - Serialiser is a struct providing all the required data
	that dpq needs to serialise/deserialise the custom type, ensure it exists in
	the schema, and in some cases, receive the type's OID.

	All serialisers must support the following static methods:

	 - static bool isSupportedType(T)();
	Must return true iff all the other functions in serialiser know how to handle this type

	 - static T deserialise(T)(ubyte[]);
	Must return T, when given postgresql-compatible representation of the type

	 - static ubyte[] serialise(T)(T val);
	Must return postgresql-compatible binary representation of the type

	 - static Oid oidForType(T)();
	Must return the given type's OID, as recognised by PostgreSQL

	 - static string nameForType(T)();
	Must return a valid, unescaped name for the type, as recognised by PostgreSQL

	 - static void ensureExistence(T)(Connection conn);
	Must ensure the type exists and can be used in the DB, can simply return
	if no work is needed.
	Must not throw or otherwise fail unless type creation failed, in case the type
	does not yet exist, it should be silently created.

	Example:
		-----------------------
		struct MyTypeSerialiser
		{
			static bool isSupportedType(T)()
			{
				// magic
			}

			static T deserialise(T)(ubyte[])
			{
				// magic
			}

			static ubyte[] serialise(T)(T val)
			{
				// magic
			}

			static Oid oidForType(T)()
			{
				// magic
			}

			static string nameForType(T)()
			{
				// magic
			}

			static void ensureExistence(T)(Connection conn)
			{
				// magic
			}
		}
		-----------------------
 */
