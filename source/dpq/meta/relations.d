/// Relation-related meta-programming like checking for valid relations ...
module dpq.meta.relations;

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

