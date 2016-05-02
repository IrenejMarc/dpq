/// I was wrong, this the most useless module.
module dpq.exception;

class DPQException : Exception
{
	this(const string msg)
	{
		super(msg);
	}
}
