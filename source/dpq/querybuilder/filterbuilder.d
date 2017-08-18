///
module dpq.querybuilder.filterbuilder;

import dpq.attributes;
import dpq.column;
import dpq.connection;
import dpq.query;
import dpq.querybuilder.querybuilder;
import dpq.value;

import std.stdio;
import std.string;
import std.algorithm : map, sum;
import std.typecons : Nullable;

package struct FilterBuilder
{
	private string[][] _filters;

	ref FilterBuilder and(string filter)
	{
		if (_filters.length == 0)
			_filters.length++;

		_filters[$ - 1] ~= '(' ~ filter ~ ')';

		return this;
	}

	ref FilterBuilder or()
	{
		_filters ~= [];

		return this;
	}

	/// Returns the actual number of lowest-level filters
	long length()
	{
		return _filters.map!(f => f.length).sum;
	}


	string toString()
	{
		// Join inner filters by AND, outer by OR
		return _filters.map!(innerFilter =>
				innerFilter.join(" AND ")
				).join(" OR ");
	}
}
