module dpq.attributes;

import std.traits;
import std.typetuple;
import std.typecons;

import dpq.column;

RelationAttribute relation(string name)
{
	return RelationAttribute(name);
}

struct RelationAttribute
{
	string name;
}

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

struct IgnoreAttribute
{
}

@property IgnoreAttribute ignore()
{
	return IgnoreAttribute();
}

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

template relationName(alias R)
{
	string relName()
	{
		static if (hasUDA!(R, RelationAttribute))
			return getUDAs!(R, RelationAttribute)[0].name;
		else
			return R.stringof;
	}

	enum relationName = relName();
}


string snakeCase(string str)
{
	import std.regex;
	import std.string;

	static auto r = regex(r"([a-z][A-Z])", "g");
	return str.replaceAll(r, r"\1_\2").toLower;
}

template attributeName(alias R)
{
	static if (hasUDA!(R, AttributeAttribute))
		enum attributeName = getUDAs!(R, AttributeAttribute)[0].name;
	else
		enum attributeName = __traits(identifier, R);
		//enum attributeName = R.stringof;
}


// Workaround for getSymbolsByUDA not working on structs/classes with private members
template getMembersByUDA(T, alias attribute)
{
	import std.meta : Filter;

	enum hasSpecificUDA(string name) = mixin("hasUDA!(T." ~ name ~ ", attribute)");
	alias getMembersByUDA = Filter!(hasSpecificUDA, __traits(allMembers, T));
}

template primaryKeyName(T)
{
	alias fields = getMembersByUDA!(T, PrimaryKeyAttribute);
	static assert(fields.length < 2, "Multiple or composite primary key found for " ~ T.stringof ~ ", this is not currently supported");
	static assert(fields.length == 1, "No primary key found for " ~ T.stringof);

	enum primaryKeyName = fields[0].stringof;
}

template isPK(alias T, string m)
{
	enum isPK = hasUDA!(mixin("T." ~ m), PrimaryKeyAttribute);
}

string embeddedPrefix(T)()
{
	return "_" ~ relationName!T ~ "_";
}

Column[] attributeList(T)(bool ignorePK = false, bool insert = false)
{
	alias TU = Unqual!T;
	Column[] res;

	void addMems(T)(string prefix = "", string asPrefix = "")
	{
		import std.string : format;
		foreach(m; serialisableMembers!T)
		{
			alias mType = typeof(mixin("T." ~ m));
			alias attrName = attributeName!(mixin("T." ~ m));
			static if (is(mType == class) || is(mType == struct))
			{
				if (insert)
					addMems!mType("\"%s\".%s".format(attrName, prefix));
				else
					addMems!mType("(\"%s\").%s".format(attrName, prefix), embeddedPrefix!mType);
			}
			else
			{
				if (ignorePK && isPK!(T, m))
					continue;

				res ~= Column("%s\"%s\"".format(prefix, attributeName!(mixin("T." ~ m))),
						asPrefix ~ attrName);
			}
		}
	}
	addMems!TU;

	return res;
}
alias sqlMembers = attributeList;

template serialisableMembers(T)
{
	alias serialisableMembers = filterSerialisableMembers!(T, __traits(allMembers, T));
}

template filterSerialisableMembers(T, FIELDS...)
{
	static if (FIELDS.length > 1) {
		alias filterSerialisableMembers = TypeTuple!(
			filterSerialisableMembers!(T, FIELDS[0 .. $/2]),
			filterSerialisableMembers!(T, FIELDS[$/2 .. $]));
	} else static if (FIELDS.length == 1) {
		//alias T = T;
		enum mname = FIELDS[0];
		static if (isRWPlainField!(T, mname) || isRWField!(T, mname)) 
		{
			alias tup = TypeTuple!(__traits(getMember, T, FIELDS[0]));
			static if (tup.length != 1) 
			{
				alias filterSerialisableMembers = TypeTuple!(mname);
			}
			else 
			{
				static if (!hasUDA!(IgnoreAttribute, __traits(getMember, T, mname)))
					alias filterSerialisableMembers = TypeTuple!(mname);
				else
					alias filterSerialisableMembers = TypeTuple!();
			}
		} 
		else 
			alias filterSerialisableMembers = TypeTuple!();
	} 
	else 
		alias filterSerialisableMembers = TypeTuple!();
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

	static if (!__traits(compiles, TypeTuple!(__traits(getMember, T, M)))) enum isPublicMember = false;
	else {
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

