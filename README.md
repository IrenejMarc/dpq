# dpq - A D PostgreSQL library

dpq wraps the libpq library and aims to provide a simple and modern way to access PostgreSQL in the D programming language.

## Current features:
 - Opening a connection using a connection string
 - Queries
 - Fetching the results of queries in binary format
 - Looping through the said results
 - Exceptions on query errors
 - 
  
## Planned features
 - Object-relational mapping
 - Automatic schema creating from objects
 - Connection pooling
 
## Documentation
There is no docs yet, in the future, they should be written into the source code itself.
 
## Some notes:
 - If a wrong type is specified while fetching a column, the results are undefined. Most likely just garbage

## Licence
MIT, read LICENSE.txt

## Very simple example code

```d
import std.stdio;
import dpq.connection;
import dpq.query;
import dpq.attributes;
import dpq.result;

struct UserData
{
	string firstName;
	string lastName;
}

// A relation's name can be specified with the @relation attribute
@relation("users")
struct User
{
	// serial is 4B in size, use serial8 with longs (@serial == @type("SERIAL"))
	@serial @PK int id;
	
	// @uniqueIndex will create an unique index, @index non-unique
	/*@uniqueIndex*/ string username;
	@index int posts;

	// Struct inside structs can be used, they will be created as a type
	UserData userData;

	// ubyte[] will get store as BYTEA
	// Attribute/column names can be specified using the @attribute UDA (@attr is an alias for it)
	@attr("passwordHash") ubyte[] password;

	// Private properties will be ignored, same for @ignore
	private int _secret;
	// A getter-setter pair will get (de-)serialised too.

	/*
	@property int secret()
	{
		return _secret;
	}

	@property void secret(int newSecret)
	{
		_secret = newSecret;
	}
	*/
}

struct Post
{
	@serial @PK int id;
	// @FK will automatically find the referenced table's PK
	@FK!User int userId;
	string title;
	string content;
}

void main()
{
	// Establish a connection, will throw if connecting fails or connection string cannot be parsed
	auto conn = Connection("host=anubis.ad.nuclei.co dbname=testdb user=testuser password='VerySecureTestPassword'");
	
	// One-line query execution, the same could be done with Connection.exec(string command)
	Query("CREATE TABLE IF NOT EXISTS test (id SERIAL, txt TEXT)").run();

	auto q = Query("INSERT INTO test (txt) VALUES ('Some text')");

	// A query can be run twice, if you wish to do so, inserting two rows in this case
	q.run();
	q.run();
	
	// Last connection will be used if none is specified as the first param to Query()
	q = Query("SELECT id, txt FROM test WHERE id = $1 OR id = $2");
	// Params could also be added with the << operator
	// r << 4 << 1;
	Result r = q.run(4, 1);

	writefln("Our query returned %d rows, each with %d columns", r.rows, r.columns);
	writefln("Additionaly, the query took %d ms to complete.", r.time.msecs);

	// Looping with foreach works as expected
	foreach (row; r)
		// Make sure you don't specify the incorrect type to as(),
		// the results are undefined, but mosty likely
		// you will either get garbage or a RangeError
		writeln("row[\"txt\"] is: ", row["txt"].as!string);

	// This will create a schema out of the two specified types
	// Indexes, primary keys, and foreign keys will also be created
	// as specified by the UDAs on struct/class members
	conn.ensureSchema!(User, Post);
	
	User newUser;
	newUser.username = "foobar123999";
	newUser.userData.firstName = "Foo";
	newUser.userData.lastName = "Bar";

	// This will insert an the given user.
	conn.insert(newUser);

	// This will return a Nullable!User, searched for by the User's primary key
	// if no rows are returned, a Nullable null value will be returned
	auto user = conn.findOne!User(1);
	writeln("User: ", user);

	// Similar to above, but we specify what attribute we are filtering by
	auto user2 = conn.findOneBy!User("username", "foobar123");
	writeln("User 2:", user2);

	// The most powerful version of findOne -- allows you to specify a custom filter
	// Parameters can be given as with normal queries, beginning with $1.
	auto user3 = conn.findOne!User("id > $1 AND username LIKE 'a%'", 1);
	writeln("User 3: ", user3);

	// This will return an array of users with more than 100 posts,
	// if no rows are returned by the query, the array will have a length of 0
	User[] users = conn.find!User("posts > $1", 100);
	writeln("Users: ", users);
	

  // Connection does not have to be closed, the destructor will take care of that,
	// but it can still manually be closed using conn.close()
}

```
