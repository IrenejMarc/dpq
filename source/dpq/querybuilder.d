module dpq.querybuilder;

import dpq.value;
import dpq.query;
import dpq.connection;
import dpq.attributes;
import dpq.column;

import std.typecons;
import std.string;

version (unittest) import std.stdio;


enum Order : string
{
	asc = "ASC",
	desc = "DESC"
};

private enum QueryType
{
	select = "SELECT",
	update = "UPDATE",
	insert = "INSERT",
	delete_ = "DELETE"
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

		string[] _returning;

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

	unittest
	{
		writeln(" * QueryBuilder");
		writeln("\t * opIndexAssign");

		QueryBuilder qb;
		qb["foo"] = 123;
		qb["bar"] = "456";

		assert(qb._params["foo"] == Value(123));
		assert(qb._params["bar"] == Value("456"));
	}

	// SELECT methods
	ref QueryBuilder select(string[] cols...)
	{
		_columns = cols;
		_type = QueryType.select;
		return this;
	}


	ref QueryBuilder select(Column[] cols...)
	{
		_type = QueryType.select;
		_columns = [];
		foreach(col; cols)
		{
			if (col.column != col.asName)
				_columns ~= "%s AS %s".format(col.column, col.asName);
			else
				_columns ~= col.column;
		}

		return this;
	}

	unittest
	{
		writeln("\t * select");

		QueryBuilder qb;
		qb.select("foo", "bar", "baz");
		assert(qb._columns == ["foo", "bar", "baz"]);

		Column[] cs = [Column("foo", "foo_test"), Column("bar")];
		qb.select(cs);
		assert(qb._columns == ["foo AS foo_test", "bar"]);
	}

	ref QueryBuilder from(string from)
	{
		assert(
				_type == QueryType.select || _type == QueryType.delete_,
				"QueryBuilder.from() can only be used for SELECT or DELETE queries.");

		_table = from;
		return this;
	}

	ref QueryBuilder from(T)()
	{
		return from(relationName!T);
	}

	unittest
	{
		writeln("\t\t * from");
		QueryBuilder qb;
		
		qb.from("sometable");
		assert(qb._table == "sometable");

		struct Test {}
		qb.from!Test;
		assert(qb._table == "test");
	}

	ref QueryBuilder where(string filter)
	{
		_filter = filter;
		return this;
	}

	ref QueryBuilder where(T)(string col, T val)
	{
		_params["__where_filt"] = Value(val);
		_filter = "%s = {__where_filt}".format(col);

		return this;
	}

	unittest
	{
		writeln("\t\t * where");

		string str = "a = $1 AND b = $2";
		QueryBuilder qb;
		qb.where(str);
		assert(qb._filter == str);

		qb.where("some_field", 1);
		assert(qb._filter == "some_field = {__where_filt}");
		assert(qb._params["__where_filt"] == Value(1));
	}

	ref QueryBuilder order(string col, Order order)
	{
		assert(_type == QueryType.select, "QueryBuilder.order() can only be used for SELECT queries.");
		_orderBy ~= col;
		_orders ~= order;
		return this;
	}

	unittest
	{
		writeln("\t\t * order");

		QueryBuilder qb;

		qb.order("some_col", Order.asc);

		assert(qb._orderBy[0] == "some_col");
		assert(qb._orders[0] == Order.asc);

		qb.order("some_other_col", Order.desc);

		assert(qb._orderBy[1] == "some_other_col");
		assert(qb._orders[1] == Order.desc);
	}
	
	ref QueryBuilder limit(int limit)
	{
		assert(_type == QueryType.select, "QueryBuilder.limit() can only be used for SELECT queries.");

		_limit = limit;
		return this;
	}

	unittest
	{
		writeln("\t\t * limit");

		QueryBuilder qb;
		qb.limit(1);
		assert(qb._limit == 1);
	}

	ref QueryBuilder offset(int offset)
	{
		assert(_type == QueryType.select, "QueryBuilder.offset() can only be used for SELECT queries.");
		_offset = offset;
		return this;
	}

	unittest
	{
		writeln("\t\t * offset");

		QueryBuilder qb;
		qb.offset(1);
		assert(qb._offset == 1);
	}

	// UPDATE methods
	ref QueryBuilder update(string table)
	{
		_table = table;
		_type = QueryType.update;
		return this;
	}
	
	ref QueryBuilder update(T)()
	{
		return update(relationName!T);
	}

	unittest
	{
		QueryBuilder qb;
		qb.update("sometable");

		assert(qb._table == "sometable");
		assert(qb._type == QueryType.update);

		struct Test {}

		qb.update!Test;
		assert(qb._type == QueryType.update);
		assert(qb._table == relationName!Test);
	}

	ref QueryBuilder set(Value[string] params)
	{
		foreach (col, val; params)
			set(col, val);

		return this;
	}

	ref QueryBuilder set(T)(string col, T val)
	{
		assert(_type == QueryType.update, "QueryBuilder.set() can only be used on UPDATE queries");

		_params[col] = val;
		_set ~= "\"%s\" = {%s}".format(col, col);

		return this;
	}

	ref QueryBuilder set(string set)
	{
		_set ~= set;

		return this;
	}

	unittest
	{
		writeln("\t * set");

		QueryBuilder qb;
		qb.update("foo")
			.set("some_col", 1);

		assert(qb._params["some_col"] == Value(1));
		assert(qb._set.length == 1);
		assert(qb._set[0] == "\"some_col\" = {some_col}");

		qb.set([
				"col1": Value(1),
				"col2": Value(2)]);

		assert(qb._params.length == 3);
		assert(qb._set.length == 3);
		assert(qb._set[1] == "\"col1\" = {col1}");
		assert(qb._set[2] == "\"col2\" = {col2}");

		string str = "asd = $1";
		qb.set(str);
		assert(qb._params.length == 3);
		assert(qb._set.length == 4);
		assert(qb._set[3] == str);
	}
	
	// INSERT methods
	ref QueryBuilder insert(string table, string[] cols...)
	{
		_table = table;
		_columns = cols;
		_type = QueryType.insert;
		return this;
	}


	ref QueryBuilder insert(string table, Column[] cols...)
	{
		import std.array;
		return insert(table, array(cols.map!(c => c.column)));
	}

	unittest
	{
		writeln("\t * insert");

		QueryBuilder qb;
		qb.insert("table", "col1", "col2");

		assert(qb._type == QueryType.insert);
		assert(qb._table == "table");
		assert(qb._columns == ["col1", "col2"]);

		Column[] cs = [
			Column("some_col", "stupid_as_name"),
			Column("qwe")];

		qb.insert("table2", cs);
		assert(qb._table == "table2");
		assert(qb._columns.length == 2);
		assert(qb._columns == ["some_col", "qwe"]);
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

	unittest
	{
		writeln("\t * values");

		QueryBuilder qb;
		qb.insert("table", "col")
			.values(1, 2, 3);

		assert(qb._type == QueryType.insert);
		assert(qb._indexParams.length == 3);
		assert(qb._indexParams == [Value(1), Value(2), Value(3)]);

		qb.values([Value(4), Value(5)]);
		assert(qb._indexParams.length == 5);
		assert(qb._indexParams == [Value(1), Value(2), Value(3), Value(4), Value(5)]);
	}

	ref QueryBuilder remove()
	{
		_type = QueryType.delete_;
		return this;
	}

	ref QueryBuilder remove(string table)
	{
		from(table);
		return remove();
	}

	ref QueryBuilder remove(T)()
	{
		return remove(relationName!T);
	}

	ref QueryBuilder returning(string[] ret...)
	{
		foreach (r; ret)
			_returning ~= r;

		return this;
	}

	unittest
	{
		writeln("\t * remove");

		struct Test {}
		QueryBuilder qb;
		qb.remove!Test;

		assert(qb._type == QueryType.delete_);
		assert(qb._table == relationName!Test);
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

	unittest
	{
		writeln("\t * replaceParams");
		QueryBuilder qb;
		string str = "SELECT {foo} FROM table WHERE id = {bar} AND name = '{baz}'";
		qb["foo"] = "a";
		qb["bar"] = "b";

		str = qb.replaceParams(str);

		// No idea what the order might be
		assert(
				str == "SELECT $1 FROM table WHERE id = $2 AND name = '{baz}'" ||
				str == "SELECT $2 FROM table WHERE id = $1 AND name = '{baz}'");
	}

	private string selectCommand()
	{
		string cols;
		if (_columns.length == 0)
			cols = "*";
		else
			cols = _columns.join(", ");

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

	unittest
	{
		writeln("\t * selectCommand");

		QueryBuilder qb;
		qb.select("col")
			.from("table")
			.where("id", 1)
			.limit(1)
			.offset(1);

		string str = qb.command();
		assert(str == `SELECT col FROM "table" WHERE id = $1 LIMIT 1 OFFSET 1`, str);
	}

	private string insertCommand()
	{
		int index = 0;
		string str = "INSERT INTO \"%s\" (%s) VALUES (%s)".format(
				_table,
				_columns.join(","),
				_indexParams.map!(v => "$%d".format(++index)).join(", ")
				);

		if (_returning.length > 0)
		{
			str ~= " RETURNING ";
			str ~= _returning.join(", ");
		}

		return str;
	}

	unittest
	{
		writeln("\t * insertCommand");

		QueryBuilder qb;
		qb.insert("table", "col")
			.values(1)
			.returning("id");

		string str = qb.command();
		assert(str == `INSERT INTO "table" (col) VALUES ($1) RETURNING id`);
	}

	private string updateCommand()
	{
		string str = "UPDATE \"%s\" SET %s".format(
				_table,
				_set.join(", "));

		if (_filter.length > 0)
			str ~= " WHERE " ~ _filter;

		if (_returning.length > 0)
		{
			str ~= " RETURNING ";
			str ~= _returning.join(", ");
		}

		return replaceParams(str);
	}

	unittest
	{
		writeln("\t * updateCommand");

		QueryBuilder qb;
		qb.update("table")
			.set("col", 1)
			.where("foo", 2)
			.returning("id");

		string str = qb.command();
		assert(
				str == `UPDATE "table" SET "col" = $1 WHERE foo = $2 RETURNING id` ||
				str == `UPDATE "table" SET "col" = $2 WHERE foo = $1 RETURNING id`);
	}

	private string deleteCommand()
	{
		string str = "DELETE FROM \"%s\"".format(_table);

		if (_filter.length > 0)
			str ~= " WHERE " ~ _filter;

		if (_returning.length > 0)
		{
			str ~= " RETURNING ";
			str ~= _returning.join(", ");
		}

		return replaceParams(str);
	}

	unittest
	{
		writeln("\t * deleteCommand");

		QueryBuilder qb;
		qb.remove("table")
			.where("id", 1)
			.returning("id");

		string str = qb.command();
		assert(str == `DELETE FROM "table" WHERE id = $1 RETURNING id`, str);
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
			case QueryType.delete_:
				return deleteCommand();
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

	unittest
	{
		writeln("\t * paramsArr");

		QueryBuilder qb;
		qb.addParams("1", "2", "3");
		qb["foo"] = 1;
		qb["bar"] = 2;

		auto ps = qb.paramsArr();
		assert(
				ps == [Value("1"), Value("2"), Value("3"), Value(1), Value(2)] ||
				ps == [Value("1"), Value("2"), Value("3"), Value(2), Value(1)]);
	}

	void addParam(T)(T val)
	{
		_indexParams ~= Value(val);
		++_paramIndex;
	}

	unittest
	{
		writeln("\t * addParam");

		QueryBuilder qb;

		assert(qb._paramIndex == 0);

		qb.addParam(1);
		assert(qb._paramIndex == 1);
		assert(qb._indexParams.length == 1);
		assert(qb._indexParams[0] == Value(1));

		qb.addParam(2);
		assert(qb._paramIndex == 2);
		assert(qb._indexParams.length == 2);
		assert(qb._indexParams[1] == Value(2));
	}

	ref QueryBuilder addParams(T...)(T vals)
	{
		foreach (val; vals)
			addParam(val);

		return this;
	}
	
	unittest
	{
		writeln("\t * addParams");

		QueryBuilder qb;
		qb.addParams(1, 2, 3);

		assert(qb._indexParams.length == 3);
		assert(qb._paramIndex == 3);
	}

	ref QueryBuilder opBinary(string op, T)(T val)
			if (op == "<<")
	{
		return addParam(val);
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
