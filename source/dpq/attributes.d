module dpq.attributes;

import std.traits;
import std.typetuple;
import std.typecons;

import dpq.column;
import dpq.meta;

version(unittest)
{
	import std.stdio;
}

RelationAttribute relation(string name)
{
	return RelationAttribute(name);
}

struct RelationAttribute
{
	string name;
}

enum EmbedAttribute;
alias embed = EmbedAttribute;

AttributeAttribute attribute(string name)
{
	return AttributeAttribute(name);
}
alias attr = attribute;

struct AttributeAttribute
{
	string name;
}

@property PrimaryKeyAttribute PrimaryKey()
{
	return PrimaryKeyAttribute();
}

alias PKey = PrimaryKey;
alias PK = PrimaryKey;

struct PrimaryKeyAttribute
{
}


PGTypeAttribute type(string type)
{
	return PGTypeAttribute(type);
}

@property PGTypeAttribute serial()
{
	return PGTypeAttribute("SERIAL");
}

@property PGTypeAttribute serial4()
{
	return PGTypeAttribute("SERIAL4");
}

@property PGTypeAttribute serial8()
{
	return PGTypeAttribute("SERIAL8");
}


struct PGTypeAttribute
{
	string type;
}

enum IgnoreAttribute;
alias ignore = IgnoreAttribute;

struct IndexAttribute
{
	bool unique = false;
}

@property IndexAttribute index()
{
	return IndexAttribute();
}

@property IndexAttribute uniqueIndex()
{
	return IndexAttribute(true);
}

struct ForeignKeyAttribute
{
	string relation;
	string pkey;
}

@property ForeignKeyAttribute foreignKey(T)()
{
	return ForeignKeyAttribute(relationName!T, primaryKeyName!T);
}
alias FK = foreignKey;
alias FKey = foreignKey;

template SnakeCase(string str)
{
	import std.string : toLower;

	template IsLower(char c)
	{
		enum IsLower = (c >= 'a' && c <= 'z');
	}
	template IsUpper(char c)
	{
		enum IsUpper = (c >= 'A' && c <= 'Z');
	}

	// Ssss, sss.
	template Snake(string str)
	{
		static if (str.length < 2)
			enum Snake = str;
		else static if (IsLower!(str[0]) && IsUpper!(str[1]))
			enum Snake = str[0] ~ "_" ~ str[1] ~ SnakeCase!(str[2 .. $]);
		else
			enum Snake = str[0] ~ SnakeCase!(str[1 .. $]);
	}

	enum SnakeCase = Snake!str.toLower;
}

unittest
{
	writeln(" * Attributes");
	writeln("\t * SnakeCase");

	static assert(SnakeCase!"something" == "something");
	static assert(SnakeCase!"UPPERCASE" == "uppercase");
	static assert(SnakeCase!"camelCase" == "camel_case");
	static assert(SnakeCase!"UpperCamelCase" == "upper_camel_case");
	static assert(SnakeCase!"someTHING" == "some_thing");
	static assert(SnakeCase!"some_thing" == "some_thing");
}

template relationName(alias R)
{
	static if (hasUDA!(R, RelationAttribute))
	{
		enum rName = getUDAs!(R, RelationAttribute)[0].name;
		static if (rName.length == 0)
			enum relationName = SnakeCase!(R.stringof);
		else
			enum relationName = rName;
	}
	else
		enum relationName = SnakeCase!(R.stringof);
}

unittest
{
	writeln("\t * relationName");

	struct Test {}
	struct someThing {}
	@relation("some_random_name") struct Test2 {}

	static assert(relationName!Test == "test");
	static assert(relationName!someThing == "some_thing");
	static assert(relationName!Test2 == "some_random_name");
}


template attributeName(alias R)
{
	static if (hasUDA!(R, AttributeAttribute))
		enum attributeName = getUDAs!(R, AttributeAttribute)[0].name;
	else
		enum attributeName = SnakeCase!(__traits(identifier, R));
}

unittest
{
	writeln("\t * attributeName");
	struct Test
	{
		string id;
		string someName;
		@attr("someRandomName") string a;
	}

	static assert(attributeName!(Test.id) == "id");
	static assert(attributeName!(Test.someName) == "some_name");
	static assert(attributeName!(Test.a) == "someRandomName");
}


// Workaround for getSymbolsByUDA not working on structs/classes with private members
template getMembersByUDA(T, alias attribute)
{
	import std.meta : Filter;

	enum hasSpecificUDA(string name) = mixin("hasUDA!(T." ~ name ~ ", attribute)");
	alias getMembersByUDA = Filter!(hasSpecificUDA, __traits(allMembers, T));
}

unittest
{
	writeln("\t * getMembersByUDA");

	struct Test
	{
		@PK int id;
		@FK!Test int id2;
		@FK!Test int id3;
	}

	static assert(getMembersByUDA!(Test, PrimaryKeyAttribute)[0] == "id");
	static assert(getMembersByUDA!(Test, ForeignKeyAttribute)[0] == "id2");
	static assert(getMembersByUDA!(Test, ForeignKeyAttribute)[1] == "id3");
}

template primaryKeyName(T)
{
	alias fields = getMembersByUDA!(T, PrimaryKeyAttribute);
	static assert(fields.length < 2,
			"Multiple or composite primary key found for " ~ T.stringof ~ ", this is not currently supported");
	static assert(fields.length == 1, "No primary key found for " ~ T.stringof);

	enum primaryKeyName = mixin(fields[0].stringof);
}

template primaryKeyAttributeName(T)
{
	enum primaryKeyAttributeName = attributeName!(mixin("T." ~ primaryKeyName!T));
}

unittest
{
	writeln("\t * primaryKeyName");
	struct Test
	{
		@PK int myPK;
		int id;
	}

	static assert(primaryKeyName!Test == "myPK");

	writeln("\t * primaryKeyAttributeName");

	static assert(primaryKeyAttributeName!Test == "my_pk");
}

template isPK(alias T, string m)
{
	enum isPK = hasUDA!(mixin("T." ~ m), PrimaryKeyAttribute);
}

unittest
{
	writeln("\t * isPK");
	struct Test
	{
		@PK int id;
		string a;
	}
	
	static assert(isPK!(Test, "id"));
	static assert(!isPK!(Test, "a"));
}

template embeddedPrefix(T, string name)
{
	import std.string : format;
	enum embeddedPrefix ="_%s_%s_".format(
			relationName!T,
			SnakeCase!name);
}

template AttributeList2(
		T,
		string prefix = "",
		string asPrefix = "",
		bool ignorePK = false,
		bool insert = false,
		fields...)
{
	static if (fields.length == 0)
		enum AttributeList2 = [];
	else
	{
		alias mt = typeof(mixin("T." ~ fields[0]));

		// Ignore the PK
		static if (ignorePK && isPK!(T, fields[0]) || hasUDA!(IgnoreAttribute, mixin("T." ~ fields[0])))
			enum AttributeList2 = AttributeList2!(T, prefix, asPrefix, ignorePK, insert, fields[1 .. $]);
		else
		{
			enum attrName = attributeName!(mixin("T." ~ fields[0]));
			enum AttributeList2 = 
					[Column(prefix ~ attrName, asPrefix ~ attrName)] ~ 
					AttributeList2!(
							T,
							prefix,
							asPrefix,
							ignorePK,
							insert,
							fields[1 .. $]);
		}
	}
}

unittest
{
	import std.typecons : Nullable;
	writeln("\t * AttributeList");
	struct Test2
	{
		string bar;
		string baz;
	}

	struct Test
	{
		@PK int id;
		@embed Test2 inner;
	}

	static assert(AttributeList!Test[0] == Column("id", "id"));
	static assert(AttributeList!Test[1] == Column("inner", "inner"));

	// ignorePK
	static assert(AttributeList!(Test, true)[0] == Column("inner", "inner"));

	// INSERT syntax, with ignorePK
	static assert(AttributeList!(Test, true, true)[0] == Column("inner", "inner"));


}

template AttributeList(T, bool ignorePK = false, bool insert = false)
{
	alias AttributeList = AttributeList2!(T, "", "", ignorePK, insert, serialisableMembers!(T));
	static assert(AttributeList.length > 0, "AttributeList found no fields, for " ~ T.stringof ~ " cannot continue");
}

template serialisableMembers(T)
{
	alias NT = NoNullable!T;
	alias serialisableMembers = filterSerialisableMembers!(NT, __traits(allMembers, NT));
}

unittest
{
	writeln("\t * serialisableMembers");
	struct Test
	{
		int a;
		private int _b;
		@property int b() {return _b;};
		@property void b(int x) {_b = x;};
		@property int c() {return _b;};
	}

	static assert(serialisableMembers!Test.length == 2);
	static assert(serialisableMembers!Test[0] == "a");
	static assert(serialisableMembers!Test[1] == "b");
}

template filterSerialisableMembers(T, fields...)
{
	static if (fields.length == 0)
		alias filterSerialisableMembers = TypeTuple!();
	else
	{
		enum m = fields[0];
		static if (isRWPlainField!(T, m) || isRWField!(T, m))
		{
			static if (!hasUDA!(mixin("T." ~ m), IgnoreAttribute))
				alias filterSerialisableMembers = TypeTuple!(TypeTuple!(m), filterSerialisableMembers!(T, fields[1 .. $]));
			else
				alias filterSerialisableMembers = filterSerialisableMembers!(T, fields[1 .. $]);
		}
		else 
			alias filterSerialisableMembers = filterSerialisableMembers!(T, fields[1 .. $]);
	} 
}


/*
	 Functions below

	Extensions to `std.traits` module of Phobos. Some may eventually make it into Phobos,
	some are dirty hacks that work only for vibe.d
	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/


/**
	Determins if a member is a public, non-static data field.
*/

template isRWPlainField(T, string M)
{
	static if (!isRWField!(T, M)) 
		enum isRWPlainField = false;
	else 
		enum isRWPlainField = __traits(compiles, *(&__traits(getMember, Tgen!T(), M)) = *(&__traits(getMember, Tgen!T(), M)));
}

/**
	Determines if a member is a public, non-static, de-facto data field.
	In addition to plain data fields, R/W properties are also accepted.
*/
template isRWField(T, string M)
{
	import std.traits;
	import std.typetuple;

	static void testAssign()() 
	{
		T t = void;
		__traits(getMember, t, M) = __traits(getMember, t, M);
	}

	// reject type aliases
	static if (is(TypeTuple!(__traits(getMember, T, M))))
		enum isRWField = false;
	// reject non-public members
	else static if (!isPublicMember!(T, M))
		enum isRWField = false;
	// reject static members
	else static if (!isNonStaticMember!(T, M))
		enum isRWField = false;
	// reject non-typed members
	else static if (!is(typeof(__traits(getMember, T, M))))
		enum isRWField = false;
	// reject void typed members (includes templates)
	else static if (is(typeof(__traits(getMember, T, M)) == void))
		enum isRWField = false;
	// reject non-assignable members
	else static if (!__traits(compiles, testAssign!()()))
		enum isRWField = false;
	else static if (anySatisfy!(isSomeFunction, __traits(getMember, T, M)))
	{
		// If M is a function, reject if not @property or returns by ref
		private enum FA = functionAttributes!(__traits(getMember, T, M));
		enum isRWField = (FA & FunctionAttribute.property) != 0;
	}
	else
	{
		enum isRWField = true;
	}
}

template isPublicMember(T, string M)
{
	import std.algorithm, std.typetuple : TypeTuple;

	static if (!__traits(compiles, TypeTuple!(__traits(getMember, T, M)))) 
		enum isPublicMember = false;
	else 
	{
		alias MEM = TypeTuple!(__traits(getMember, T, M));
		enum isPublicMember = __traits(getProtection, MEM).among("public", "export");
	}
}

template isNonStaticMember(T, string M)
{
	import std.typetuple;
	import std.traits;

	alias MF = TypeTuple!(__traits(getMember, T, M));
	static if (M.length == 0) {
		enum isNonStaticMember = false;
	} else static if (anySatisfy!(isSomeFunction, MF)) {
		enum isNonStaticMember = !__traits(isStaticFunction, MF);
	} else {
		enum isNonStaticMember = !__traits(compiles, (){ auto x = __traits(getMember, T, M); }());
	}
}

bool isAnyNull(T)(T val)
{
	static if (is(T == class))
		return val is null;
	else static if (isInstanceOf!(Nullable, T))
		return val.isNull;
	else
		return false;
}
