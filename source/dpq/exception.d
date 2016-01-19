module dpq.exception;

class DPQException : Exception
{
	this(const string msg)
	{
		super(msg);
	}
}
