# dpq - A D PostgreSQL library
[![Build Status](https://travis-ci.org/IrenejMarc/dpq.svg?branch=master)](https://travis-ci.org/IrenejMarc/dpq)

dpq wraps the libpq library and aims to provide a simple and modern way to access PostgreSQL in the D programming language.

## Feature highlights:
 - Manual querying using `Query` or `Connection`'s `exec` and `execParams`
 - Automatic schema generation from D structures (including PKs, indexes, ... check example below)
 - ORM functions `findOne`, `findBy`, `insert`, `update`, `count`, ... on `Connection`
 - Full support for `Nullable` and `Typedef` types.
 - `foreach` looping through `Result` and `Row`
 - Data is sent *fully* in binary, including structures and arrays (and arrays of structures)
 - Ability to specify a custom serialiser for any custom type
 - Pre-existing serialisers cover most needs, and `SysTime`
 - (Basic) async query support (will be improved in the future)
 - (Basic) prepared statement support (will be improved in the future)

 
## Documentation
Documentation is in the code itself, though pretty lacking currently.

Unit tests might provide some useful usage examples too.
 
## Some notes:
 - If a wrong type is specified to `Value`'s `as`, the results are undefined, but most likely a `RangeError` or garbage.
 - Using QueryBuilder, when specifying columns, make sure they are not reserverd SQL keywords, they will not be escaped automatically (wrap keywords in `" "`)
 - Be careful with using `Connection`'s `exec` function, since it only returns textual values, that are not currently supported by dpq's `Value`. (execParams can be used even without params and will return binary data)

## Licence
MIT, read LICENSE.txt

## Example

```d
import std.stdio;
import std.typecons : Nullable;

import std.datetime : SysTime;

import dpq.connection;
import dpq.value;
import dpq.attributes;
import dpq.query;
import dpq.result;

void main()
{
	/*
		 Establish a new connection. Accepts a PostgreSQL connection string.
		 Will throw if the connection could not be established or if parsing
		 the connection string failed.

		 More: http://www.postgresql.org/docs/9.3/static/libpq-connect.html
	 */
	auto db = Connection("host=127.0.0.1 dbname=test user=test");

	/*
		 Basic querying can be done via the Query object which allows you
		 two write manual queries.

		 The basic constructor accepts a Connection object, an optional SQL command.

		 Params are positional and begin with $1, any number of params can be sent.
	 */
	Query q = Query(db, "SELECT $1, $2, $3");

	/*
		 Parameters to the query can be added with the addParam method, or
		 the `<<` operator, which can also be chained.
	 */
	q.addParam(1);
	q << 2.0 << "three";

	/*
		 Running the query is done with the querys' run() function, which
		 also accepts any number of params to be sent with the query.

		 You can run the same query multiple times if you wish.
	 */
	Result r = q.run();

	/*
		 Params can also be added to the query later, or when when running it.
	 */
	q = Query(db, "SELECT $1, $2 AS second_param, 'a literal string'");
	r = q.run("this is a string param", 777);

	/*
		 Accessing the results if done via Result's index operator which will
		 return a Row object.

		 Alternatively, you can also loop through all the Result's rows with a
		 foreach loop.

		 Row, is however not publicly-visible, so use the auto declarator.
	 */
	auto firstRow = r[0];

	foreach (row; r)
	{
		/*
			 You can access the actual column's values by using Row's opIndex.
			 The opIndex will accept either a textual index, looking up the column
			 by its name, or the column's numerical index, starting with a zero.

			 A Value object will be returned by this. 
			 This value, can hold a NULL value, or the actual data. Checking for NULL
			 can be done with its isNull property.
		 */
		Value strVal = row[0];

		/*
			 The value stores PostgreSQL compatible data and can be passed back
			 to most dpq's functions directly.

			 To obtain a value usable in D, you must call the Value's as method, which
			 accepts one template param, indicating the type to return. The returned 
			 type will ALWAYS be an instance of Nullable, meaning you must check for 
			 the NULL value unless you're sure it cannot happen.
		 */
		string stringParam = strVal.as!string;

		/*
			 In actual code, you will probably want to shorten this and use
			 textual indexes for columns.
		 */
		int secondParam = row["second_param"].as!int; // fancy stuff

		/*
			 Using a line like above, will implicitly convert the Nullable!int
			 returned by .as!int to just an int, causing an AssertError if
			 the value was null.

			 Because of that, is is usually recommended to do stuff this way.
		 */
		auto literalString = row[2].as!string;

		/* 
			 And now the returned value can be checked for null with Nullable's
			 isNull method.
		 */
		if (literalString.isNull)
			continue;
	}

	/*
		 Since @relation is not specified here, user_profile_data will be used.
	 */
	struct UserProfileData
	{
		string fullName;
		/*
			 Nullable values are supported at any level of nesting and work as expected.
		 */
		Nullable!string favouriteQuote;
	}

		/*
		 That's it as far as the basic Querying goes, but that's not where the
		 real power of dpq comes from.

		 dpq allows you to generate DB schema from existing D structures, even
		 allowing you to create primary keys, foreign keys, indexes and more.

		 Once generated, you can easily fetch whole objects from the database,
		 update existing records and insert or remove new ones.
	 */

	
	/* 
		 Specifying the relation name can be done with the @relation attribute.
		 If no name is specified, though you generally probably should do that,
		 the structure's name will be lower_snake_cased and used.

		 Both structs and classes are supported.
	 */
	@relation("users")
	struct User
	{
		/*
			 The column/attribute's special properties can be specified with the
			 UDAs from dpq.attributes.

			 In this case, @serial sets the type to SERIAL, and @PK will ensure
			 that the id column will be a Primary key in the column.

			 In reality, @PK is an alias for @PrimaryKey, another available alias
			 is @PKey. Use whichever one you prefer and deem more understandable.
		 */
		@serial @PK int id;
		
		/*
			 Setting an index on the column is as simple as specifying @index for 
			 the member. @uniqueIndex is also provided, creating a, you guessed it, 
			 unique index.
		 */
		@index int posts;
		@uniqueIndex string username;
		

		/*
			 Arrays are supported, and are sent as PostgreSQL arrays.
			 ubyte[] and byte[] are a special case of arrays, and will be created
			 and sent as BYTEA.
		 */
		ubyte[] passwordHash;

		/*
			 Since D prefers camelCased variable names, but it seems to be the standard
			 in database design to use lower_snake_cased names, dpq takes care of that
			 automatically. All variable names will be converted to lower_snake_case,
			 making, for example, the passwordHash above into password_hash.

			 You can, however, specify a custom name for any column using the
			 @attribute("column_name") property, or its alias @attr.
			 Names specifies with the @attr UDA, will not be lower_snake_cased and will
			 be used exactly as entered.
		 */
		@attr("password_salt") ubyte[] salt;

		/*
			 Other structures can be embedded into any relation or type.
			 These structures will either be created as a custom type in the database,
			 or if applicable, relations.
		 */

		UserProfileData profileData;

		/*
			 Both arrays of built-in types and custom structures are supported, but
			 sadly, I am running out of ideas for user fields.

			 Arrays can only have up to 6 dimensions, which is a limitation of 
			 PostgreSQL, and can-not be jagged. Arrays of Nullable values
			 are supported, but not, however, arrays of Nullable arrays. This is
			 again, a limitation of PostgreSQL, not dpq.
		 */
		string[] favouriteFoods;

		/*
			 Another thing supported by dpq out-of-the-box is SysTime, which will
			 get stored in the DB as TIMESTAMP in UTC.
			 Keep in mind, that PostgreSQL only supportes up to millisecond 
			 accuracy, while D supports it up to hnsecs.
		 */
		SysTime registrationTime;

	}


	@relation("posts")
	struct Post
	{
		/*
			 When wanting to work with BIGINT serial values, use @serial8, and 
			 make sure to use long as the member's type.
		 */
		@serial8 @PK long id;

		/*
			 To specify a foreign key, use the @ForeignKey attribute or one of its
			 alises (@FK, @FKey).

			 This attribute will find the referenced table's primary key automaticaly
			 and use that.

			 Additionally, alongside the FK constraint on a FK column, an index
			 will also be created for it, since that's generally good practice.
		 */
		@FK!User int userId;
	}

	/*
		 Creating the schema is as simple as calling the Connection's ensureSchema
		 method. This method must be called every time, even if the schema already
		 exists, to ensure dpq is aware of the created relations and type's OIDs.
		 Without that, they cannot be properly serialised and sent to the DB.

		 ensureSchema must be given all the structures that should be created as
		 relations. If any of them have embedded structures inside them, those
		 will automatically be created as types.

		 Foreign keys will be created after all the relations, so the order
		 you specify the structures is does not matter.
	 */

		db.ensureSchema!(User, Post);

		/*
			 After ensureSchema is called, we can finally get to real work.

			 Fetching a single object from the database is done by calling the
			 Connection's findOne method.
			 The method accepts a single template parameter, indicating the structure
			 to fetch, and a normal parameter, indicating the value of the FK to filter
			 by.
			 
			 findOne will return a Nullable instance of the requested type. A NULL 
			 value in this case means no rows were selected by the query.

			 Once again, in case you forgot by now, compound PKs are, unfortunately,
			 not supported.
		 */

		auto user = db.findOne!User(1);
		if (!user.isNull)
			writeln("We have a user."); // whatever logic

		/*
			 There's also a special version of findOne, allowing you to specify a
			 custom filter for the query.
			 It accepts a string as the first parameter, and any number of values
			 to be used in the query.
			 The result it limited to 1 row and NULL will be returned in the same
			 case as above.

		 */
		auto otherUser = db.findOne!User("username = $1", "Person9720");

		/*
			 In cases such as above, findOneBy could also be used.
			 findOneBy accepts a parameter for the column name, and the value for it
			 to filter by.

			 The query below will be the same as above.
		 */
		otherUser = db.findOneBy!User("username", "Person9720");

		/*
			 Fetching more than one object from the DB can be done with the
			 Connection's find method, accepting a filter string, and any number
			 of values that are to be used.

			 This method will return an array, which will be empty if no records
			 matching the filter were found.
		 */
		User[] manyUsers = db.find!User("posts > $1", 250);

		/*
			 Inserting records is just as simple, using the Connection's insert method.

			 When records are being inserted, the primary key will not be sent alongside
			 them, allowing you to use PostgreSQL's SERIAL type's default values.
		 */
		User newUser;
		user.username = "Person8164";
		db.insert(newUser);

		/*
			 Records can be deleted using the Connection's remove method, again
			 providing both a filter-string version and a find-by-PK version.
		 */
		db.remove!User(1);
		db.remove!User("posts <= $1", 25);

		/*
			 Last, but definitely not least, there's updating records.

			 There are three versions of the Connection's update method,
			 the first, accepting the value of the PK to filter by, and a
			 structure of the same type you're updating and updates ALL the values
			 of the matched record.
			 A template parameter is not needed, since it can be inferred from
			 the second parameter, but you can provide it if you wish to be
			 explicit.

			 All update methods return the number of updated records
		 */
		newUser.posts = 2;
		int nUpdated = db.update(1, newUser);

		/*
			 The second version accepts the value of the PK to filter by, and
			 an associative array of strings mapping to Value objects.
			 It sets the columns of the provided to the values they map to.
			 
			 Keep in mind that there is no way to set values relatively to their
			 current value using this way, which might cause data races in concurrent
			 applications.
		 */
		nUpdated = db.update!User(1, [
				"posts": Value(3),
				"username": Value("New Person 9720")
		]);

		/*
			 The last version of update, takes a filter string, and an update string,
			 as well as any number of values to be sent with the query.
			 This version gives you the most freedom and allows you to set the values
			 relatively.
		 */
		nUpdated = db.update!User(
				"posts > $1", // filter
				"posts = 0, username = $2", //update
				250, "Spammer batch #927"); // values

		/*
			 dpq also provides async versions for most of the methods mentioned above,
			 for which the results can be obtained by using Connection's
			 lastResult, allResults and nextResult method.
			 
			 More info is available in the Connection's and Query's files inline docs.
		 */
		db.removeAsync!User(1);
}
```

## A word from the author
I believe this above example covers most use cases for dpq.

If you have any questions, I can be contacted on Twitter with the handle
@IrenejMarc. I'll always be glad to help out.

If you have any ideas how dpq could be improved, or find a missing feature
or a bug, don't be scared to create an issue, I love feedback.

