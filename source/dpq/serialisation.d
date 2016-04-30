module dpq.serialisation;

// TODO: merge all serialisers' imports
import dpq.serialisers.composite;
import dpq.serialisers.array;
import dpq.serialisers.scalar;
import dpq.serialisers.systime;
import dpq.serialisers.string;

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
	return serialiser.serialise(cast(AT) val);
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
		// Otherwise, pick one from the bunch of pre-set ones.
		static if (isArray!T)
			alias SerialiserFor = ArraySerialiser;
		// Support for SysTime
		else static if (is(T == SysTime))
			alias SerialiserFor = SysTimeSerialiser;
		else static if (is(T == class) || is(T == struct))
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
	return Nullable!T(serialiser.deserialise!T(bytes[0 .. len]));
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

// TODO: this for arrays
Type oidForType(T)()
		if (!isArray!T)
{
	import dpq.connection : _dpqCustomOIDs;
	enum oid = typeOid!T;

	static if (oid == Type.INFER)
	{
		Oid* p;
		if ((p = relationName!T in _dpqCustomOIDs) != null)
			return cast(Type) *p;
	}

	return oid;
}

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
