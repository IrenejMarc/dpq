module dpq.smartptr;

import dpq.exception;

version(unittest)
{
	int nFrees = 0;
	void fakeFree(T)(T* val)
	{
		++nFrees;
	}
}

class SmartPointer(T, alias _free)
{
	private T _ptr;

	alias get this;

	this()
	{
		_ptr = null;
	}

	this(T ptr)
	{
		_ptr = ptr;
	}

	~this()
	{
		clear();
	}

	@property T get()
	{
		if (_ptr == null)
			throw new DPQException("get called on a null SmartPointer!(" ~ T.stringof ~ ")");
		return _ptr;
	}

	@property bool isNull()
	{
		return _ptr == null;
	}

	void opAssign(typeof(null) n)
	{
		clear();
	}

	void opAssign(T ptr)
	{
		if (ptr == _ptr)
			return;

		clear();
		_ptr = ptr;
	}

	void clear()
	{
		if (_ptr == null)
			return;

		_free(_ptr);

		_ptr = null;
	}
}

unittest
{
	import std.stdio;

	writeln(" * SmartPointer");

	alias Ptr = SmartPointer!(ubyte*, fakeFree);

	ubyte* p = new ubyte;
	*p = 2;
	auto sp = new Ptr;

	assert(sp._ptr == null);

	sp = p;
	assert(sp._ptr == p);

	// assign the same ptr
	sp = p;
	assert(nFrees == 0);
	assert(!sp.isNull);
	assert(sp._ptr == p);

	ubyte* p2 = new ubyte;
	*p2 = 255;

	sp = p2;
	assert(nFrees == 1);
	assert(sp._ptr == p2);

	sp = new Ptr(p2);
	assert(sp._ptr == p2);

	sp.clear();
	assert(sp.isNull);
	assert(sp._ptr == null);
}

