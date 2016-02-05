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
}
