module dpq.exception;

class SQLException : Exception
{
	this(const string msg)
	{
		super(msg);
	}
}
