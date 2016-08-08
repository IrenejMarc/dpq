///
module dpq.attributes;

import std.traits;
import std.typetuple;
import std.typecons;

import dpq.column;
import dpq.meta;

version(unittest) import std.stdio;

/** 
	@relation attribute -- specifies the relation/type name to be used
	for Connection's ORM functions. If none is set, dpq will
	default to the structure's name in lower_snake_case.
 */
RelationAttribute relation(string name)
{
	return RelationAttribute(name);
}

package struct RelationAttribute
{
	string name;
}

enum EmbedAttribute;
deprecated("There is no need to use @embed anymore, Serialisers should take care of it")
	alias embed = EmbedAttribute;

/**
	@attribute / @attr -- specifies the name of the attribute to be used.

	Defaults to member's name in lower_snake_case if nothing is specified
 */
AttributeAttribute attribute(string name)
{
	return AttributeAttribute(name);
}
alias attr = attribute;

package struct AttributeAttribute
{
	string name;
}

/**
	@PK / @Pkey / @PrimaryKey attribute -- specifies that the member should be
	a PK. Coumpound PKs are not supported.
 */
package enum PrimaryKeyAttribute;

alias PrimaryKey = PrimaryKeyAttribute;
alias PKey = PrimaryKey;
alias PK = PrimaryKey;



/**
	Specifies the type for the member, overrides any serialiser-provided type
 */
PGTypeAttribute type(string type)
{
	return PGTypeAttribute(type);
}

/// Shortcut for @type("SERIAL")
@property PGTypeAttribute serial()
{
	return PGTypeAttribute("SERIAL");
}

/// SHORTCUT for @type("SERIAL4")
@property PGTypeAttribute serial4()
{
	return PGTypeAttribute("SERIAL4");
}

/// SHORTCUT for @type("SERIAL8")
@property PGTypeAttribute serial8()
{
	return PGTypeAttribute("SERIAL8");
}

package struct PGTypeAttribute
{
	string type;
}

/**
	Allows placing any text after the column definition when ensureSchema is ran.

	Useful for stuff like "NOT NULL", or "CHECK (x > y)", ...

	Do not use to create foreign keys, use @FK instead.

	Example:
	-------------
	@relation("testy")
	struct Test
	{
		@serial @PK int id;
		@suffix("NOT NULL") string username; // will produce "username TEXT NOT NULL"
	}
	-------------
 */
ColumnSuffixAttribute suffix(string suffix)
{
	return ColumnSuffixAttribute(suffix);
}

struct ColumnSuffixAttribute
{
	string suffix;
}

/**
	A shortcut to @suffix("NOT NULL")

	Does not perform any kind of a null check in D.
 */
enum notNull = suffix("NOT NULL");

/**
	Specifies that the member should be completely ignored as far as the DB is
	concerned.
 */
package enum IgnoreAttribute;
alias ignore = IgnoreAttribute;

/**
	Specifies that the member/column should have an index created on it.
	If unique is set, it well be a unique index. 
 */
package struct IndexAttribute
{
	bool unique = false;
}

/// @index
@property IndexAttribute index()
{
	return IndexAttribute();
}

/// @uniqueIndex
@property IndexAttribute uniqueIndex()
{
	return IndexAttribute(true);
}

/**
	Specifies that the member is a foriegn key, ensureSchema will create a FK 
	constraint as well as an index for it. Finds the referenced table's PK
	by itself.
 */
package struct ForeignKeyAttribute
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

/**
	Transforms the given string into lower_snake_case at compile-time.
	Used for attribute and relation names and probably not very useful
	outside the library itself.
 */
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

/**
	Relation/type name for the given type, can be set with @relation attribute.
	If @relation is not set, type's name will be lower_snake_cased.
 */
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

/**
	Attribute name for the given type, can be specified with @attribute.
	If @attribute is not specified, the member's name will just be 
	lower_snake_cased and returned.
 */
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


/**
 Workaround for getSymbolsByUDA not working on structs/classes with private members.
 Returns all the structure's members that have the given UDA.
 */
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

	alias FKMembers = getMembersByUDA!(Test, ForeignKeyAttribute);
	alias PKMembers = getMembersByUDA!(Test, PrimaryKeyAttribute);

	static assert(PKMembers.length == 1);
	static assert(PKMembers[0] == "id");

	static assert(FKMembers.length == 2);
	static assert(FKMembers[0] == "id2");
	static assert(FKMembers[1] == "id3");

	static assert(getMembersByUDA!(Test, IgnoreAttribute).length == 0);
}

/**
	Returns a string containing the name of the type member that is marked with @PK
 */
template primaryKeyName(T)
{
	alias fields = getMembersByUDA!(T, PrimaryKeyAttribute);
	static assert(fields.length < 2,
			"Multiple or composite primary key found for " ~ T.stringof ~ ", this is not currently supported");
	static assert(fields.length == 1, "No primary key found for " ~ T.stringof);

	enum primaryKeyName = mixin(fields[0].stringof);
}

/**
	Returns the name of the PK attribute (SQL name)
 */
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

/**
	Returns true if the member m is a PK on T.
 */
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

deprecated template embeddedPrefix(T, string name)
{
	import std.string : format;
	enum embeddedPrefix ="_%s_%s_".format(
			relationName!T,
			SnakeCase!name);
}

/**
	Returns a list of Columns for all the given type's serialisable members,
	with their actual names as they're used in SQL.

	Params:
		prefix   = prefix to use, if any
		asPrefix = asPrefix, prefix to use for column's AS names
		ignorePK = whether to ignore the PK, useful for inserts and similar
 */
template AttributeList2(
		T,
		string prefix = "",
		string asPrefix = "",
		bool ignorePK = false,
		fields...)
{
	static if (fields.length == 0)
		enum AttributeList2 = [];
	else
	{
		alias mt = typeof(mixin("T." ~ fields[0]));

		// Ignore the PK
		static if (ignorePK && isPK!(T, fields[0]) || hasUDA!(IgnoreAttribute, mixin("T." ~ fields[0])))
			enum AttributeList2 = AttributeList2!(T, prefix, asPrefix, ignorePK, fields[1 .. $]);
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
							fields[1 .. $]);
		}
	}
}

template AttributeList(T, bool ignorePK = false, bool insert = false)
{
	alias AttributeList = AttributeList2!(T, "", "", ignorePK, serialisableMembers!(T));
	static assert(AttributeList.length > 0, "AttributeList found no fields, for " ~ T.stringof ~ " cannot continue");
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
		Test2 inner;
	}

	alias attrs = AttributeList!Test;
	static assert(attrs[0] == Column("id", "id"));
	static assert(attrs[1] == Column("inner", "inner"));

	// ignorePK
	static assert(AttributeList!(Test, true)[0] == Column("inner", "inner"));

	// INSERT syntax, with ignorePK
	static assert(AttributeList!(Test, true)[0] == Column("inner", "inner"));
}

/**
	Gives a list of all the structure's members that will be used in the DB.
	Ignores @ignore members, non-RW and non-public members.
 */
template serialisableMembers(T)
{
	alias RT = RealType!T;
	alias serialisableMembers = filterSerialisableMembers!(RT, __traits(allMembers, RT));
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

/// A filter implementation for serialisableMembers
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
				alias filterSerialisableMembers = TypeTuple!(
						TypeTuple!(m),
						filterSerialisableMembers!(T, fields[1 .. $]));
			else
				alias filterSerialisableMembers = filterSerialisableMembers!(T, fields[1 .. $]);
		}
		else 
			alias filterSerialisableMembers = filterSerialisableMembers!(T, fields[1 .. $]);
	} 
}


/*
	Functions/templates isRWPlainField, isRWField, isPublicMember and isNonStaticMember.

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

	static if (M.length == 0)
	{
	    enum isNonStaticMember = false;
	}
	else static if (anySatisfy!(isSomeFunction, MF))
	{
	    enum isNonStaticMember = !__traits(isStaticFunction, MF);
	}
	else
	{
		enum isNonStaticMember = !__traits(compiles, (){ auto x = __traits(getMember, T, M); }());
	}
}
