module dpq.meta;

import std.traits;


deprecated("Use SQLType instead, not all array types are supported by sqlType")
string sqlType(T)()
{
	// TODO: More types, embedded structs, Date types

	static if (isArray!T)
		alias FT = ForeachType!T;
	else
		alias FT = T;


	static if (is(FT == int) || is(FT == ushort))
		enum type = "INT";
	else static if (is(FT == long) || is(FT == uint))
		enum type = "INT8";
	else static if (is(FT == short))
		enum type = "INT2";
	else static if (is(FT == long))
		enum type = "BIGINT";
	else static if (is(FT == float))
		enum type = "FLOAT4";
	else static if (is(FT == double))
		enum type = "FLOAT8";
	else static if (is(FT == char[]) || is(FT == string))
		enum type = "TEXT";
	else static if (is(FT == bool))
		enum type = "BOOL";
	else static if (is(FT == char))
		enum type = "CHAR(1)";
	else static if(is(FT == ubyte[]) || is(FT == byte[]))
		enum type = "BYTEA";
	else static if (is(FT == enum))
		enum type = sqlType!(OriginalType!FT);
	else
		static assert(false, "Cannot map type \"" ~ T.stringof ~ "\" to any PG type, please specify it manually using @type.");

	static if (isArray!T)
	{
		static if (isStaticArray!T)
			return type ~ "[%d]".format(T.length);
		else
			return type ~ "[]";
	}
	else
		return type;
}

/**
	Returns the array's base type

	Examples:
	---------------
	alias T = BaseType!(int[][]);
	alias T2 = BaseType!(int[]);
	alias T3 = BaseType!int;

	static assert(is(T == int));
	static assert(is(T2 == int));
	static assert(is(T3 == int));
	---------------
*/
template BaseType(T)
{
	static if (isArray!T)
		alias BaseType = BaseType!(ForeachType!T);
	else
		alias BaseType = T;
}

template SQLType(T)
{
	alias BT = BaseType!T;

	static if (isSomeString!T)
		enum type = "TEXT";
	else static if (is(BT == int))
		enum type = "INT";
	else static if (is(BT == long))
		enum type = "INT8";
	else static if (is(BT == short))
		enum type = "INT2";
	else static if (is(BT == long))
		enum type = "BIGINT";
	else static if (is(BT == float))
		enum type = "FLOAT4";
	else static if (is(BT == double))
		enum type = "FLOAT8";
	else static if (is(BT == bool))
		enum type = "BOOL";
	else static if (is(BT == char))
		enum type = "CHAR(1)";
	else static if(is(BT == ubyte[]) || is(BT == byte[]))
		enum type = "BYTEA";
	else static if (is(BT == enum))
		enum type = SQLType!(OriginalType!BT);
	else
		static assert(false, "Cannot map type \"" ~ T.stringof ~ "\" to any PG type, please specify it manually using @type.");

	static if (isArray!T && !isSomeString!T)
		enum SQLType = type ~ "[]";
	else 
		enum SQLType = type;
}

/**
	Returns the number of dimensions of the given array type

	Examples:
	-----------------
	auto dims = ArrayDimensions!(int[][]);
	static assert(dims == 2);
	-----------------
 */
template ArrayDimensions(T)
{
	static if (isArray!T)
		enum ArrayDimensions = 1 + ArrayDimensions!(ForeachType!T);
	else 
		enum ArrayDimensions = 0;
}

