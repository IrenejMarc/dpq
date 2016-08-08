///
module dpq.mixins;

import dpq.relationproxy;
import std.typecons : Nullable;

mixin template RelationMixin()
{
	alias Type = typeof(this);
	alias ProxyT = RelationProxy!Type;

	import dpq.connection : _dpqLastConnection;
	import std.typecons : Nullable;

	@property static relationProxy()
	{
		return ProxyT(*_dpqLastConnection);
	}

	static ProxyT where(U)(U[string] filters)
	{
		return relationProxy.where(filters);
	}

	static ProxyT where(U...)(string filter, U params)
	{
		return relationProxy.where(filter, params);
	}

	static Type find(U)(U param)
	{
		return relationProxy.find(param);
	}

	static Type findBy(U)(U[string] filters)
	{
		return relationProxy.findBy(filters);
	}

	static ref Type insert(ref Type record)
	{
		return relationProxy.insert(record);	
	}

	@property static Nullable!Type first()
	{
		return relationProxy.first;
	}

	@property static Nullable!Type last()
	{
		return relationProxy.last;
	}

	@property static Type[] all()
	{
		return RelationProxy!Type(*_dpqLastConnection).all;
	}
}
