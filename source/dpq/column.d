module dpq.column;

struct Column
{
	string column;
	string _asName;

	@property string asName()
	{
		return _asName.length > 0 ? _asName : column;
	}

	@property void asName(string n)
	{
		_asName = n;
	}
	//alias column this;

	unittest
	{
		import std.stdio;
		writeln(" * Column");
		writeln("\t * asName");

		Column c = Column("col", "col2");
		assert(c.asName != c.column);

		c = Column("col");
		assert(c.asName == c.column);
	}
}
