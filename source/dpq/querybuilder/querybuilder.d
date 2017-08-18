///
module dpq.querybuilder.querybuilder;

import dpq.attributes;
import dpq.column;
import dpq.connection;
import dpq.query;
import dpq.querybuilder.filterbuilder;
import dpq.value;

import std.stdio;
import std.algorithm : map;
import std.conv : to;
import std.string;
import std.typecons : Nullable;

enum Order : string
{
	none = "",
	asc = "ASC",
	desc = "DESC"
};

package enum QueryType
{
	select = "SELECT",
	update = "UPDATE",
	insert = "INSERT",
	delete_ = "DELETE"
}


/**
	Provides a nice way of writing queries in D, as well as some handy shortcuts
	to working with D structures in the DB.

	Most method names are synonimous with the same keyword in SQL, but their order
	does not matter.
	
	All of the methods can be chained.

	Examples:
	---------------------
	auto qb = QueryBuilder()
			.select("id")
			.from!User
			.where("posts > {posts}") // placeholders can be used 
			.order("posts", Order.desc)
			.limit(5);

	// Placeholders will be replaced ONLY if they are specified.
	// No need to escape anything, as it sent with execParams
	qb["posts"] = 50;
	---------------------
 */
struct QueryBuilder
{
	private
	{
		// Columns to select
		string[] _columns;

		// Table to select from
		string _table;

		// A list of filters, lowest-level representing AND, and OR between those
		FilterBuilder _filters;

		// List of ORDER BY columns and list of orders (ASC/DESC)
		string[] _orderBy;
		Order[] _orders;

		// Limit and offset values, using -1 is null value (not set)
		Nullable!(int, -1) _limit = -1;
		Nullable!(int, -1) _offset = -1;

		// Params to be used in the filters
		Value[string] _params;

		// Params to be be used as positional
		Value[] _indexParams;

		// Columns to list in RETURNING
		string[] _returning;

		// UPDATE's SET
		string[] _set;

		// Current index for positional params, needed because we allow mixing
		// placeholders and positional params
		int _paramIndex = 0;

		// Type of the query, (SELECT, UPDATE, ...)
		QueryType _type;

		Connection* _connection;
	}

	@property QueryBuilder dup()
	{
		// It's a struct, I'll copy anyway
		return this;
	}

	private string escapeIdentifier(string identifier)
	{
		if (_connection != null)
			return _connection.escapeIdentifier(identifier);

		// This could potentionally be dangerous, I don't like it.
		return `"%s"`.format(identifier);
	}

	/**
		Constructs a new QueryBuilder with the Connection, so we can directly
		run queries with it.
	 */
	this(ref Connection connection)
	{
		_connection = &connection;
	}

	/**
		Remembers the given key value pair, replacing the placeholders in the query
		before running it.

		If the same key is set multiple times, the last value will apply.
	 */
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

	/**
		Sets the builder's type to SELECT, a variadic array of column names to select
	 */
	ref QueryBuilder select(string[] cols...)
	{
		_columns = cols;
		_type = QueryType.select;
		return this;
	}

	/**
		Same as above, except it accepts a variadic array of Column type. Mostly
		used internally.
	 */
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

	/**
		Selects all the given relation's properties

		Examples:
		-----------------
		struct User { @PK @serial int id; }
		auto qb = QueryBuilder()
				.select!User
				.from!User
				.where( ... );
		-----------------

	 */
	ref QueryBuilder select(T)()
	{
		return select(AttributeList!T);
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

	/**
		Sets the builder's FROM value to the given string.
	 */
	ref QueryBuilder from(string from)
	{
		assert(
				_type == QueryType.select || _type == QueryType.delete_,
				"QueryBuilder.from() can only be used for SELECT or DELETE queries.");

		_table = from;
		return this;
	}

	/**
		Same as above, but instead of accepting a string parameter, it instead
		accepts a type as a template parameter, then sets the value to that
		type's relation name. Preferred over the above version.
	 */
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

	/**
		Generates a placeholder that should be unique every time.

		This is required because we might filter by the same column twice (e.g. 
		where(["id": 1])).or.where(["id": 2]), in which case the second value for
		ID would overwrite the first one.
	 */
	private string safePlaceholder(string key)
	{
		/*
			Because we only really need to be unique within this specific QB, just
			a simple static counter is good enough. It could be put on the QB
			instance instead, but this works just as well no need to complicate for
			now.
		 */
		static int count = 0;
		return "%s_%d".format(key, ++count);
	}

	/**
		Adds new filter(s). Param placeholders are used, with the same names as
		the AA keys. Calling this multiple times will AND the filters.

		Internally, a value placeholder will be used for each of the values, with
		the same name as the column itself. Be careful not to overwrite these
		before running the query.
	 */
	ref QueryBuilder where(T)(T[string] filters)
	{
		foreach (key, value; filters)
		{
			auto placeholder = safePlaceholder(key);
			_filters.and("%s = {%s}".format(escapeIdentifier(key), placeholder));
			_params[placeholder] = value;
		}

		return this;
	}

	/**
		Adds a new custom filter.

		Useful for filters that are not simple equality comparisons, or usage psql
		functions. Nothing is escaped, make sure you properly escape the reserved
		keywords if they are used as identifier names.

		Placeholders can be used with this, and even
		positional params, since the order is predictable. Read addParam for
		more information about that.
	 */
	ref QueryBuilder where(T...)(string filter, T params)
	{
		_filters.and("%s".format(filter));

		foreach (param; params)
			addParam(param);

		return this;
	}

	/// Alias and to where, to allow stuff like User.where( ... ).and( ... )
	alias and = where;

	/**
		Once called, all additional parameters will be placed into their own group,
		OR placed between each group of ANDs

		Examples:
		--------------------
		auto qb = QueryBuilder()
			.select!User
			.from!User
			.where(["id	": 1])
			.or
			.where(["id": 2]);

			// Which will produce a filter like "... WHERE (id = $1) OR (id = $2)"
		--------------------
	 */
	@property ref QueryBuilder or()
	{
		_filters.or();

		return this;
	}

	unittest
	{
		writeln("\t\t * where");

		auto qb = QueryBuilder();

		qb.where(["something": "asd"]);
		assert(qb._filters.length == 1);

		qb.where(["two": 2, "three": 3]);
		assert(qb._filters.length == 3);
	}

	/**
		Sets the ORDER part of the query. Accepts a column name and an Order value.
	 */
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
	
	/**
		Sets the LIMIT in the query. Only for SELECT queries, obviously.
	 */
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

	/// OFFSET for queries
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

	ref QueryBuilder set(T)(T[string] params)
	{
		foreach (col, val; params)
			set(col, val);

		return this;
	}

	ref QueryBuilder set(T)(string col, T val)
	{
		assert(_type == QueryType.update, "QueryBuilder.set() can only be used on UPDATE queries");

		_params[col] = val;
		_set ~= "%s = {%s}".format(escapeIdentifier(col), col);

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

	ref QueryBuilder addValues(T, U)(U val)
	{
		import std.traits;
		import dpq.meta;
		import dpq.serialisation;

		if (isAnyNull(val))
			addValue(null);
		else
		{
			foreach (m; serialisableMembers!(NoNullable!T))
			{
				static if (isPK!(T, m) || hasUDA!(mixin("T." ~ m), IgnoreAttribute))
					continue;
				else
					addValue(__traits(getMember, val, m));
			}
		}

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
			cols = _columns
				//.map!(c => escapeIdentifier(c))
				.join(", ");

		string table = escapeIdentifier(_table);
		string str = "SELECT %s FROM %s".format(cols, table);

		if (_filters.length > 0)
			str ~= " WHERE " ~ _filters.to!string;

		if (_orderBy.length > 0)
		{
			str ~= " ORDER BY ";
			for (int i = 0; i < _orderBy.length; ++i)
			{
				if (_orders[i] == Order.none)
					continue;

				str ~= "\"" ~ _orderBy[i] ~ "\" " ~ _orders[i] ~ ", ";
			}
			str = str[0 .. $ - 2];
		}

		if (!_limit.isNull)
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
			.where(["id": 1])
			.limit(1)
			.offset(1);

		string str = qb.command();
		assert(str == `SELECT col FROM "table" WHERE ("id" = $1) LIMIT 1 OFFSET 1`, str);
	}

	private string insertCommand()
	{
		int index = 0;
		
		string params = "(";
		foreach (i, v; _indexParams)
		{
			params ~= "$%d".format(i + 1);
			if ((i + 1) % _columns.length)
				params ~= ", ";
			else if ( (i + 1) < _indexParams.length)
				params ~= "),(";
		}
		params ~= ")";
		
		string str = "INSERT INTO \"%s\" (%s) VALUES %s".format(
				_table,
				_columns.join(","),
				params
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
			.values(1, 2)
			.returning("id");

		string str = qb.command();
		assert(str == `INSERT INTO "table" (col) VALUES ($1),($2) RETURNING id`);
	}

	private string updateCommand()
	{
		string str = "UPDATE \"%s\" SET %s".format(
				_table,
				_set.join(", "));

		if (_filters.length > 0)
			str ~= " WHERE " ~ _filters.to!string;

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
			.where(["foo": 2])
			.returning("id");

		string str = qb.command();
		assert(
				str == `UPDATE "table" SET "col" = $1 WHERE ("foo" = $2) RETURNING id` ||
				str == `UPDATE "table" SET "col" = $2 WHERE ("foo" = $1) RETURNING id`);
	}

	private string deleteCommand()
	{
		string str = "DELETE FROM \"%s\"".format(_table);

		if (_filters.length > 0)
			str ~= " WHERE " ~ _filters.to!string;

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
			.where(["id": 1])
			.returning("id");

		string str = qb.command();
		assert(str == `DELETE FROM "table" WHERE ("id" = $1) RETURNING id`, str);
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
