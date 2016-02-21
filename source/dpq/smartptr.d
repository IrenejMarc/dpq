module dpq.smartptr;

import dpq.exception;

class SmartPointer(T, alias _free = null)
{
	private T _ptr;

	alias get this;

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
		clear();
		_ptr = ptr;
	}

	void clear()
	{
		if (_ptr == null)
			return;

		if (_free == null)
			delete _ptr;
		else
			_free(_ptr);

		_ptr = null;
	}
}
