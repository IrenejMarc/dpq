/// RelationProxy-related methods that are called on records themselves through
/// UFCS.
module dpq.relationproxy.records;

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
