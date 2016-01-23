module dpq.attributes;

import std.traits;

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

template attributeName(alias R)
{
	static if (hasUDA!(R, AttributeAttribute))
		enum attributeName = getUDAs!(R, AttributeAttribute)[0].name;
	else
		enum attributeName = R.stringof;
}
