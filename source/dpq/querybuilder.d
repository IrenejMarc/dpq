module dpq.querybuilder;

import dpq.value;
import dpq.query;
import dpq.connection;

import std.typecons;
import std.string;


enum Order : string
{
	asc = "ASC",
	desc = "DESC"
};

private enum QueryType
{
	select = "SELECT",
	update = "UPDATE",
	insert = "INSERT"
}

struct QueryBuilder
{
	private
	{
		string[] _columns;
		string _table;
		string _filter;

		string[] _orderBy;
		Order[] _orders;

		int _limit = -1;

		Nullable!int _offset;
		Value[string] _params;
		Value[] _indexParams;

		// UPDATE's SET
		string[] _set;

		int _paramIndex = 0;
		QueryType _type;
		Connection* _connection;

	}

	this(ref Connection connection)
	{
		_connection = &connection;
	}

	void opIndexAssign(T)(T val, string key)
	{
		_params[key] = val;
	}

	// SELECT methods
	ref QueryBuilder select(string[] cols...)
	{
		_columns = cols;
		_type = QueryType.select;
		return this;
	}

	ref QueryBuilder from(string from)
	{
		assert(_type == QueryType.select, "QueryBuilder.from() can only be used for SELECT queries.");
		_table = from;
		return this;
	}

	ref QueryBuilder where(string filter)
	{
		_filter = filter;
		return this;
	}

	ref QueryBuilder where(T)(string col, T val)
	{
		addParam(val);
		_filter = "\"%s\" = $%d".format(col, _paramIndex);

		return this;
	}

	ref QueryBuilder order(string col, Order order)
	{
		assert(_type == QueryType.select, "QueryBuilder.order() can only be used for SELECT queries.");
		_orderBy ~= col;
		_orders ~= order;
		return this;
	}
	
	ref QueryBuilder limit(int limit)
	{
		assert(_type == QueryType.select, "QueryBuilder.limit() can only be used for SELECT queries.");

		_limit = limit;
		return this;
	}

	ref QueryBuilder offset(int offset)
	{
		assert(_type == QueryType.select, "QueryBuilder.offset() can only be used for SELECT queries.");
		_offset = offset;
		return this;
	}

	// UPDATE methods
	ref QueryBuilder update(string table)
	{
		_table = table;
		_type = QueryType.update;
		return this;
	}

	ref QueryBuilder set(Value[string] params)
	{
		foreach (col, val; params)
			set(col, val);

		return this;
	}

	ref QueryBuilder set(T)(string col, T val)
	{
		_params[col] = val;
		_set ~= "\"%s\" = {%s}".format(col, col);

		return this;
	}

	ref QueryBuilder set(string set)
	{
		_set ~= set;

		return this;
	}
	
	// INSERT methods
	ref QueryBuilder insert(string table, string[] cols...)
	{
		_table = table;
		_columns = cols;
		_type = QueryType.insert;
		return this;
	}

	ref QueryBuilder values(T...)(T vals)
	{
		assert(_type == QueryType.insert, "QueryBuilder.values() can only be used on INSERT queries");

		foreach (val; vals)
			addValue(val);

		return this;
	}

	ref QueryBuilder values(Value[] vals)
	{
		assert(_type == QueryType.insert, "QueryBuilder.values() can only be used on INSERT queries");

		foreach (val; vals)
			addValue(val);

		return this;
	}

	ref QueryBuilder addValue(T)(T val)
	{
		_indexParams ~= Value(val);
		return this;
	}

	// Other stuff

	private string replaceParams(string str)
	{
		int index = _paramIndex;

		foreach (param, val; _params)
			str = str.replace("{" ~ param ~ "}", "$%d".format(++index));

		return str;
	}

	private string selectCommand()
	{
		string cols;
		if (_columns.length == 0)
			cols = "*";
		else
			cols = "\"" ~ _columns.join("\", \"") ~ "\"";

		string str = "SELECT %s FROM \"%s\"".format(cols, _table);

		if (_filter.length > 0)
			str ~= " WHERE " ~ _filter;

		if (_orderBy.length > 0)
		{
			str ~= " ORDER BY ";
			for (int i = 0; i < _orderBy.length; ++i)
				str ~= "\"" ~ _orderBy[i] ~ "\" " ~ _orders[i] ~ ", ";
			str = str[0 .. $ - 2];
		}

		if (_limit != -1)
			str ~= " LIMIT %d".format(_limit);

		if (!_offset.isNull)
			str ~= " OFFSET %d".format(_offset);

		return replaceParams(str);
	}

	private string insertCommand()
	{
		int index = 0;
		string str = "INSERT INTO \"%s\" (\"%s\") VALUES (%s)".format(
				_table,
				_columns.join("\",\""),
				_indexParams.map!(v => "$%d".format(++index)).join(", ")
				);

		return str;
	}

	private string updateCommand()
	{

		string str = "UPDATE \"%s\" SET %s".format(
				_table,
				_set.join("\", \""));

		if (_filter.length > 0)
			str ~= " WHERE " ~ _filter;

		return replaceParams(str);
	}

	@property string command()
	{
		final switch (_type)
		{
			case QueryType.select:
				return selectCommand();
			case QueryType.update:
				return updateCommand();
			case QueryType.insert:
				return insertCommand();
		}
	}

	@property private Value[] paramsArr()
	{
		Value[] res = _indexParams;
		//foreach (param; _indexParams)
		//	res ~= param;

		foreach (param, val; _params)
			res ~= val;

		return res;
	}

	void addParam(T)(T val)
	{
		_indexParams ~= Value(val);
		++_paramIndex;
	}

	ref QueryBuilder addParams(T...)(T vals)
	{
		foreach (val; vals)
			addParam(val);

		return this;
	}

	ref QueryBuilder opBinary(string op, T)(T val)
			if (op == "<<")
	{
		addParam(val);

		return this;
	}


	Query query()
	{
		if (_connection != null)
			return Query(*_connection, command, paramsArr);

		return Query(command, paramsArr);
	}

	Query query(ref Connection conn)
	{
		return Query(conn, command, paramsArr);
	}
	
}

void param(alias P)(QueryBuilder b)
{
	b[P.stringof] = P;
}
