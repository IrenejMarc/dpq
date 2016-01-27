module dpq.querybuilder;

import dpq.value;
import dpq.query;

import std.typecons;
import std.string;

import dpq.connection;

enum Order : string
{
	asc = "ASC",
	desc = "DESC"
};

struct QueryBuilder
{
	// SELECT 'a', 'b' FROM table_name WHERE id = 1 ORDER BY id DESC LIMIT 10 OFFSET 5 

	private
	{
		string[] _columns;
		string _from;
		string _where;
		string[] _orderBy;
		Order[] _orders;
		int _limit = -1;
		Nullable!int _offset;
		Value[string] _params;

		int _paramIndex = 1;
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

	ref QueryBuilder select(string[] cols...)
	{
		_columns = cols;
		return this;
	}

	ref QueryBuilder from(string from)
	{
		_from = from;
		return this;
	}

	ref QueryBuilder where()(string filter)
	{
		_where = filter;
		return this;
	}

	ref QueryBuilder order(string col, Order order)
	{
		_orderBy ~= col;
		_orders ~= order;
		return this;
	}
	
	ref QueryBuilder limit(int limit)
	{
		_limit = limit;
		return this;
	}

	ref QueryBuilder offset(int offset)
	{
		_offset = offset;
		return this;
	}

	@property string command()
	{
		string cols;
		if (_columns.length == 0)
			cols = "*";
		else
			cols = "\"" ~ _columns.join("\", \"") ~ "\"";

		string str = "SELECT %s FROM \"%s\"".format(cols, _from);

		if (_where.length > 0)
			str ~= " WHERE " ~ _where;

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

		foreach (param, val; _params)
			str = str.replace("{" ~ param ~ "}", "$%d".format(_paramIndex++));

		return str;
	}

	@property private Value[] paramsArr()
	{
		Value[] res;
		foreach (param, val; _params)
			res ~= val;

		std.stdio.writeln(res);
		return res;
	}

	Query query()
	{
		if (_connection != null)
			return Query(*_connection, command());

		return Query(command());
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
