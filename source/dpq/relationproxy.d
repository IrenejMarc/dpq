module dpq.relationproxy;

import dpq.attributes;
import dpq.connection;
import dpq.querybuilder;
import dpq.value : Value;
public import dpq.querybuilder : RowLock;

import std.algorithm : map, clamp, reverse;
import std.array;
import std.meta : Alias;
import std.typecons : Nullable;

/**
	 Verifies that the given type can be used a relation
 */
template IsValidRelation(T)
{
	import std.traits : hasUDA;

	// Class or struct, and has a RelationAttribute.
	enum IsValidRelation = (is(T == struct) || is(T == class)) &&
		hasUDA!(T, RelationAttribute);
}


/**
	A structure proxying to the actual Postgres table. 
	
	Allows short and readable querying, returning actual records or arrays of
	them. first, last, and all will be cached if appropriate, the rest will
	execute a query whenever a result is needed.
	Most functions return a reference to the same object, allowing you to
	chain them. Builder pattern, really.

	Can be implicitly converted to an array of the requested structure.

	Mostly meant to be used with RelationMixin, but can be used manually.

	Examples:
	---------------
	struct User
	{
		// provides where, find, findBy, etc on the User struct
		mixin RelationMixin;

		@PK @serial int id'
		string username;
	}

	auto user1 = User.where(["id": 1]).first;
	// Or better yet. Search directly by PK
	auto betterUser1 = User.find(1);
	// Delete some users
	long nDeleted = User.where("username LIKE 'somethi%'").removeAll();
	---------------
 */
struct RelationProxy(T)
	if (IsValidRelation!T)
{
	private 
	{
		/**
			The actual content, if any at all.
		 */
		T[] _content;

		Connection _connection;

		/**
			QueryBuilder used to generate the required queries for content.
			
			Sensible defaults.
		 */
		QueryBuilder _queryBuilder = QueryBuilder().select(AttributeList!T).from!T;

		/**
			Signifies whether the content is fresh. The content is not considered 
			fresh once any filters change or new ones are applied. 
		 */
		bool _contentFresh = false;

		/**
			Tracks which column is the content sorted by. Empty string means that
			the content is not guaranteed to be sorted.
		 */
		string _sortedBy = "";

		/**
			Update the content, does not check for freshness
		 */
		void _updateContent()
		{
			auto result = _queryBuilder.query(_connection).run();

			_content = result.map!(deserialise!T).array;
			_markFresh();
		}

		/**
			Mark the content stale, meaning it will be reloaded when next needed.
		 */
		void _markStale()
		{
			_contentFresh = false;
		}

		/**
			Mark the content fresh, it should not be reloaded unless filters change.
		 */
		void _markFresh()
		{
			_contentFresh = true;
		}
	}

	/**
		Basic constructor. RelationProxy requires a connection to operate on.
	 */
	this(ref Connection connection)
	{
		_connection = connection;
	}


	/**
		Makes a copy of just the filters, not any content;
	 */
	@property RelationProxy!T dup()
	{
		auto copy = RelationProxy!T(_connection);
		copy._queryBuilder = _queryBuilder;

		return copy;
	}

	/**
		Reloads the content with existing filters.
	 */
	ref auto reload()
	{
		_updateContent();
		return this;
	}

	/**
		 Returns the actual content, executing the query if data has not yet been
		 fetched from the database.
	 */
	@property T[] all()
	{
		// Update the content if it's not currently fresh or has not been fetched yet
		if (!_contentFresh)
		{
			_updateContent();
			_sortedBy = "";
		}

		return _content;
	}

	alias all this;

	/**
		Returns the actual content, executing the query if data has not yet been
		fetched from the database limited by limit rows.

		Params:
			limit = number of rows to return. If set to any negative value, then
			all rows will be returned. That is the default behavior.

		Note:
			In its current implementation this function will fetch all rows
			satisfying filters and cache them. Limit parameter affects how
			many rows will actually be returned from cache.

			Does not guarantee order of returned rows.
	 */
	@property T[] fetch(int limit = -1)
	{
		if (!_contentFresh)
		{
			_updateContent();
			_sortedBy = "";
		}

		if (limit <= -1)
			return _content;
		if (limit >= 1)
			return _content[0 .. limit.clamp(1, _content.length)];

		return T[].init;
	}

	/**
		Specifies filters according to the given AA. 
		Filters will be joined with AND.
	 */
	ref auto where(U)(U[string] filters)
	{
		_markStale();
		_queryBuilder.where(filters);
		return this;
	}

	/**
		Same as above, but allowing you to specify a completely custom filter.
		The supplied string will be wrapped in (), can be called multiple times
		to specify multiple filters.
	 */
	ref auto where(U...)(string filter, U params)
	{
		_markStale();
		_queryBuilder.where(filter, params);
		return this;
	}

	/**
		Convenience alias, allows us to do proxy.where(..).and(...)
	 */
	alias and = where;

	/**
		Inserts an OR seperator between the filters.

		Examples:
		------------------
		proxy.where("something").and("something2").or("something3");
		// will produce "WHERE ((something) AND (something2)) OR (something3)"
		------------------
	 */
	@property ref auto or()
	{
		_queryBuilder.or();
		return this;
	}

	/**
		Fetches the first record matching the filters.

		Will return a Nullable null value if no matches.

		If data is already cached, not marked stale/unfresh and ordered by PK,
		it will reuse it, meaning that calling this after calling all
		will not generate an additional query, even if called multiple times.
		Will not cache its own result, only reuse existing data.

		Example:
		-----------------
		auto p = RelationProxy!User();
		auto user = p.where(["something": 123]).first;
		-----------------
	 */
	@property Nullable!T first()
	{
		alias RT = Nullable!T;

		// If the content is fresh, we do not have to fetch anything
		if (_contentFresh && _sortedBy == primaryKeyAttributeName!T)
		{
			if (_content.length == 0)
				return RT.init;
			return RT(_content[0]);
		}

		// Make a copy of the builder, as to not ruin the query in case of reuse
		auto qb = _queryBuilder;
		qb.limit(1).order(primaryKeyAttributeName!T, Order.asc);

		auto result = qb.query(_connection).run();

		if (result.rows == 0)
			return RT.init;
		
		return RT(result[0].deserialise!T);
	}

	/**
		Fetches first limit records matching the filters.

		Will return an empty array if no matches.

		If data is already cached, not marked stale/unfresh and ordered by specified
		column, it will reuse it, meaning that calling this after calling all
		will not generate an additional query, even if called multiple times.
		Will not cache its own result, only reuse existing data.

		Params:
			by = specifies the column to order by, defaults to PK name.
			limit = specifies how many rows to return, defaults to 1.
			If set to negative value, all matching rows will be returned.

		Example:
		-----------------
		auto p = RelationProxy!User();
		auto users = p.where(["something": 123]).first(5);
		auto users = p.first("RegistrationDate");
		auto users = p.first("RegistrationDate", 10);
		-----------------
	 */
	@property T[] first(string by, int limit = 1)
	{
		if (limit == 0)
			return T[].init;

		if (!_contentFresh || _sortedBy != by)
		{
			auto qb = _queryBuilder;
			qb.order(by, Order.asc);
			auto result = qb.query(_connection).run();
			_content = result.map!(deserialise!T).array;
			_markFresh();
			_sortedBy = by;
		}

		if (limit <= -1)
			return _content;

		return _content[0 .. limit.clamp(1, _content.length)];
	}

	/// ditto
	@property T[] first(int limit, string by = primaryKeyAttributeName!T)
	{
		return first(by, limit);
	}

	/**
		Same as first, but defaults to desceding order, giving you the last match.

		Caching acts the same as with first.
	 */
	@property Nullable!T last()
	{
		alias RT = Nullable!T;

		// If the content is fresh, we do not have to fetch anything
		if (_contentFresh && _sortedBy == primaryKeyAttributeName!T)
		{
			if (_content.length == 0)
				return RT.init;
			return RT(_content[$ - 1]);
		}

		// Make a copy of the builder, as to not ruin the query in case of reuse
		auto qb = _queryBuilder;
		qb.limit(1).order(primaryKeyAttributeName!T, Order.desc);

		auto result = qb.query(_connection).run();

		if (result.rows == 0)
			return RT.init;
		
		return RT(result[result.rows - 1].deserialise!T);
	}

	/**
		Same as first(by, limit), but defaults to desceding order, giving you the last match.

		Caching acts the same as with first.

		Note:
			Actually this function uses ascending order internally and simply reverses it.
			This behavior is intentional and used to prevent additinal query to a database
			to change the order.
	 */
	@property T[] last(string by, int limit = 1)
	{
		if (limit == 0)
			return T[].init;

		if (!_contentFresh || _sortedBy != by)
		{
			auto qb = _queryBuilder;
			qb.order(by, Order.asc); // Yes, ASC. We will reverse it later
			auto result = qb.query(_connection).run();
			_content = result.map!(deserialise!T).array;
			_markFresh();
			_sortedBy = by;
		}

		if (limit <= -1)
		{
			auto result = _content.dup;
			reverse(result);
			return result;
		}

		auto result = _content[_content.length - limit.clamp(1, _content.length) .. $].dup;
		reverse(result);
		return result;
	}

	/// ditto
	@property T[] last(int limit, string by = primaryKeyAttributeName!T)
	{
		return last(by, limit);
	}

	/**
		Sets explicit row-level lock on returned rows.
	 */
	@property ref auto for_(RowLock lock)
	{
		_markStale();
		_queryBuilder.for_(lock);
		return this;
	}

	/**
		Finds a single record matching the filters. Equivalent to where(...).first.

		Does not change the filters for the RelationProxy it was called on.
	 */
	Nullable!T findBy(U)(U[string] filters)
	{
		// Make a copy so we do not destroy our filters in the case of reuse.
		return this.dup.where(filters).first;
	}

	/**
		Same as above, but always searches by the primary key
	 */
	Nullable!T find(U)(U param)
	{
		return findBy([primaryKeyAttributeName!T: param]);
	}


	/**
		Update all the records matching filters to new values from the AA.

		Does not use IDs of any existing cached data, simply uses the specified
		filter in an UPDATE query.

		Examples:
		----------------
		auto p = RelationProxy!User(db);
		p.where("posts > 500").updateAll(["rank": "Frequent Poster]);
		----------------
	 */
	auto updateAll(U)(U[string] updates)
	{
		_markStale();

		auto result = _queryBuilder.dup
			.update!T
			.set(updates)
			.query(_connection).run();

		return result.rows;
	}

	auto update(U, Tpk)(Tpk id, U[string] values)
	{
		_markStale();

		auto qb = QueryBuilder()
			.update!T
			.set(values)
			.where([primaryKeyAttributeName!T: Value(id)]);

		return qb.query(_connection).run().rows;
	}

	/**
		Simply deletes all the records matching the filters.

		Even if any data is already cached, does not filter by IDs, but simply
		uses the specified filters in a DELETE query.
	 */
	auto removeAll()
	{
		_markStale();

		auto result = _queryBuilder.dup
			.remove()
			.query(_connection).run();

		return result.rows;
	}

	/**
		Removes a single record, filtering it by the primary key's value.
	 */
	auto remove(Tpk)(Tpk id)
	{
		_markStale();

		auto qb = QueryBuilder()
			.remove()
			.from!T
			.where([primaryKeyAttributeName!T: Value(id)]);


		return qb.query(_connection).run().rows;
	}

	/**
		Inserts a new record, takes the record as a reference in order to update
		its PK value. Does not update any other values.

		Does not check if the record is already in the database, simply creates
		an insert without the PK and can therefore be used to insert the same 
		record multiple times.
	 */
	ref T insert(ref T record)
	{
		_markStale();

		enum pk = primaryKeyName!T;
		enum pkAttr = primaryKeyAttributeName!T;

		auto qb = QueryBuilder()
				.insert(relationName!T, AttributeList!(T, true, true))
				.returning(pkAttr)
				.addValues!T(record);

		alias pkMem = Alias!(__traits(getMember, record, pk));
		auto result = qb.query(_connection).run();
		__traits(getMember, record, pk) = result[0][pkAttr].as!(typeof(pkMem));

		return record;
	}

	/**
		Updates the given record in the DB with all the current values.

		Updates by ID. Assumes the record is already in the DB. Does not insert
		under any circumstance.

		Examples:
		-----------------
		User user = User.first;
		user.posts = posts - 2;
		user.save();
		-----------------
	 */
	bool save(T record)
	{
		_markStale();

		enum pkName = primaryKeyName!T;

		auto qb = QueryBuilder()
			.update(relationName!T)
			.where([pkName: __traits(getMember, record, pkName)]);

		foreach (member; serialisableMembers!T)
			qb.set(
					attributeName!(__traits(getMember, record, member)),
					__traits(getMember, record, member));

		return qb.query(_connection).run().rows > 0;
	}

	/**
		Selects the count of records with current filters.
		Default is *, but any column can be specified as a parameter. The column
		name is not further escaped.

		Does not cache the result or use existing data's length. Call .length to 
		get local data's length.
	 */
	long count(string col = "*")
	{
		import std.string : format;

		auto qb = _queryBuilder.dup
			.select("count(%s)".format(col));

		auto result = qb.query(_connection).run();
		return result[0][0].as!long;
	}

	/**
		A basic toString implementation, mostly here to prevent querying when
		the object is implicitly converted to a string.
	 */
	@property string toString()
	{
		return "<RelationProxy!" ~ T.stringof ~ "::`" ~ _queryBuilder.command ~ "`>";
	}
}


/**************************************************/
/* Methods meant to be used on records themselves */
/**************************************************/

/**
	Reloads the record from the DB, overwrites it. Returns a reference to the 
	same object.

	Examples:
	---------------------
	User user = User.first;
	writeln("My user is: ", user);
	user.update(["username": "Oopdated Ooser"]);
	writeln("My user is: ", user);
	writeln("My user from DB is: ", User.find(user.id));
	writeln("Reloaded user ", user.reload); // will be same as above
	---------------------
 */
ref T reload(T)(ref T record)
	if (IsValidRelation!T)
{
	enum pkName = primaryKeyName!T;
	record = T.find(__traits(getMember, record, pkName));

	return record;
}

/**
	Updates a single record with the new values, does not set them on the record
	itself.

	Examples:
	--------------------
	User user = User.first;
	user.update(["username": "Some new name"]); // will run an UPDATE query
	user.reload(); // Can be reloaded after to fetch new data from DB if needed
	--------------------

 */
auto update(T, U)(T record, U[string] values)
	if (IsValidRelation!T)
{
	enum pkName = primaryKeyName!T;

	return T.updateOne(__traits(getMember, record, pkName), values);
}

/**
	Removes a record from the DB, filtering by the primary key.
 */
auto remove(T)(T record)
	if (IsValidRelation!T)
{
	enum pkName = primaryKeyName!T;

	return T.removeOne(__traits(getMember, record, pkName));
}

/**
	See: RelationProxy's save method
 */
bool save(T)(T record)
	if (IsValidRelation!T)
{
	return T.saveRecord(record);
}

// Have to move unittest out of the RelationProxy scope due to recursive expansion
unittest
{
	import std.stdio;

	writeln(" * RelationProxy");

	import std.algorithm : equal, all;

	@relation("test")
	struct Test
	{
		@serial @PK int id;
		int data;
	}

	c.ensureSchema!Test;

	Test[] t;
	t ~= Test();
	t[0].data = 789;
	t ~= Test();
	t[1].data = 123;
	t ~= Test();
	t[2].data = 456;

	c.insert(t);

	auto rp = RelationProxy!Test(c);

	writeln("\t * first");
	assert(rp.first.data               == 789);
	assert(rp.first(2)[1].data         == 123);
	assert(rp.first(2, "data")[0].data == 123);
	assert(rp.first(-1)[0].data        == 789);

	assert(equal(rp.first(2, "data"), rp.first("data", 2)));
	assert([
			rp.first(1)[0].data,
			rp.first("id")[0].data,
			rp.first(1, "id")[0].data
		]
		.all!(x => x == rp.first.data)
	);

	assert(rp.first(-2).length == 3);
	assert(rp.first( 0).length == 0);
	assert(rp.first( 2).length == 2);
	assert(rp.first( 5).length == 3);

	writeln("\t * last");
	assert(rp.last.data               == 456);
	assert(rp.last(2)[1].data         == 123);
	assert(rp.last(2, "data")[0].data == 789);
	assert(rp.last(-1)[0].data        == 456);

	assert(equal(rp.last(2, "data"), rp.last("data", 2)));
	assert([
			rp.last(1)[0].data,
			rp.last("id")[0].data,
			rp.last(1, "id")[0].data
		]
		.all!(x => x == rp.last.data)
	);

	assert(rp.last(-2).length == 3);
	assert(rp.last( 0).length == 0);
	assert(rp.last( 2).length == 2);
	assert(rp.last( 5).length == 3);

	writeln("\t * fetch");
	assert(rp.fetch(  ).length == 3);
	assert(rp.fetch(-1).length == 3);
	assert(rp.fetch( 0).length == 0);
	assert(rp.fetch( 2).length == 2);

	c.exec("DROP TABLE test;");
}
