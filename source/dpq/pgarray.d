module dpq.pgarray;

import derelict.pq.pq : Oid;

import std.traits;
import std.bitmanip;
import std.conv;

import dpq.meta;
import dpq.exception;
import dpq.value;

version(unittest) import std.stdio;

/* reverse-enigneering the source

	Name         | size in B       | notes
	------------------------------------
	ndim         | 4               | more than 0, less than MAXDIM
	flags?       | 4               | only 0 or 1 (!!)
	element_type | sizeof Oid      | cannot be spec_element_type, whatever that is

  --- ndim times
	dim          | 4               | appends to array of dim -- if lbound + dim - 1 < lbound, fail (???)
	lBound       | 4               | appends to array of lBound
	---

	--- nitems (calculated) times
	itemlen      | 4               | if itemlen is < -1 or itemlen > more than buffer remainder
	                               | -1 means null (?)
	value        | itemlen         | element's receiveproc is called
	---

*/

/*-------------------------------------------------------------------------
 *
 * array.h
 *	  Declarations for Postgres arrays.
 *
 * A standard varlena array has the following internal structure:
 *	  <vl_len_>		- standard varlena header word
 *	  <ndim>		- number of dimensions of the array
 *	  <dataoffset>	- offset to stored data, or 0 if no nulls bitmap
 *	  <elemtype>	- element type OID
 *	  <dimensions>	- length of each array axis (C array of int)
 *	  <lower bnds>	- lower boundary of each dimension (C array of int)
 *	  <null bitmap> - bitmap showing locations of nulls (OPTIONAL)
 *	  <actual data> - whatever is the stored data
 *-------------------------------------------------------------------------
 */

struct PGArray
{
	// All have to be ints for psql.
	int nDimensions;
	int dataOffset;
	Oid elementOid;
	int[] dimSizes;
	int[] lowerBounds;
	ubyte[] nullBitmap;
	ubyte[] value;

	int elementSize;


	this(const(ubyte)[] val)
	{
		auto bytes = val.dup;

		nDimensions = read!int(bytes);
		dataOffset = read!int(bytes);
		elementOid = read!Oid(bytes);

		foreach (i; 0 .. nDimensions)
		{
			dimSizes ~= read!int(bytes);
			lowerBounds ~= read!int(bytes);
		}

		import std.stdio;

		if (dataOffset != 0)
		{
			foreach (i; 0 .. dataOffset)
				nullBitmap ~= read!ubyte(bytes);

			throw new DPQException("Sorry, null values in an array are not currently supported.");
		}

		// Read the remaining data (raw array data)
		while (bytes.length > 0)
		{
			int elemSize = read!int(bytes);
			
			if (elementSize == 0)
				elementSize = elemSize;
			else if (elemSize == -1)
				continue; // null value, ignore
			else if (elementSize != elemSize)
				assert("All elements of an array must be the same type/length");

			foreach (i; 0 .. elemSize)
				value ~= read!ubyte(bytes);
		}
	}

	unittest
	{
		writeln("* PGArray");
		writeln("\t * this(ubyte[])");

		int[] ints = [1, 2, 3];
		ubyte[] arr = [
				0, 0, 0, 1,  // nDims - 1
				0, 0, 0, 0,  // flags, ignored, always 0
				0, 0, 0, 23, // elementOid

				0, 0, 0, 3,  // dimension size
				0, 0, 0, 1,  // lower bound

				0, 0, 0, 4,  // elem length
				0, 0, 0, 1,  // elem value

				0, 0, 0, 4,  // elem length
				0, 0, 0, 2,  // elem value

				0, 0, 0, 4,  // elem length
				0, 0, 0, 3]; // elem value

		auto v = PGArray(arr);
		assert(v == PGArray(ints));
	}

	this(T)(T val)
			if (isArray!T)
	{
		import std.stdio;

		nDimensions = ArrayDimensions!T;
		elementOid = typeOid!(BaseType!T);
		elementSize = BaseType!T.sizeof;


		void arr(T)(T data, int dim = 0)
		{
			alias FT = ForeachType!T;

			if (dimSizes.length <= dim)
			{
				dimSizes ~= data.length.to!int;
				lowerBounds ~= 1; // I still don't know what lower bounds does
			}

			static if (isArray!FT)
			{
				// The first time in this dimension

				foreach (v; data)
					arr(v, dim + 1);
			}
			else
			{
				foreach (v; data)
				{
					value ~= nativeToBigEndian(v);
				}
			}
		}

		arr(val);
	}

	unittest
	{
		writeln("\t* this(T val)");

		int[] x = [1,2,3];
		auto a = PGArray(x);

		assert(a.value == [
				0, 0, 0, 1,
				0, 0, 0, 2,
				0, 0, 0, 3],
			a.value.to!string);
		assert(a.nDimensions == 1);
		assert(a.elementOid == Type.INT4);
		assert(a.dimSizes == [3]);
	}

	ubyte[] toBytes()
	{
		import std.stdio;
		ubyte[] res;
		// First int is number of dimensions
		res ~= nativeToBigEndian(nDimensions);

		// flags (hasNulls?), ignored by psql
		res ~= nativeToBigEndian(0);

		// The Oid of the elements
		res ~= nativeToBigEndian(elementOid);

		assert(dimSizes.length == lowerBounds.length);
		foreach (i; 0 .. dimSizes.length)
		{
			res ~= nativeToBigEndian(dimSizes[i]);
			res ~= nativeToBigEndian(lowerBounds[i]);
		}

		//TODO: Null bitmap, null elements
		//res ~= nativeToBigEndian(nullBitmap);

		// Actual data
		size_t offset = 0;
		while(offset < value.length)
		{
			res ~= nativeToBigEndian(elementSize);
			res ~= value[offset .. offset + elementSize];
			offset += elementSize;
		}

		return res;
	}

	T opCast(T)()
			if (isArray!T)
	{
		import std.stdio;

		int dims = ArrayDimensions!T;

		if (dims != nDimensions)
			throw new DPQException("Cannot convert array to " ~ T.stringof ~ " (dimensions do not match)");

		int offset = 0;
		T assemble(T)(int dim = 0)
		{
			alias FT = ForeachType!T; // must check if this is an array and then recurse more
			T res;

			static if (isArray!FT)
			{
				foreach (i; 0 .. dimSizes[dim])
					res ~= assemble!FT(dim + 1);
			}
			else
			{
				T inner;
				foreach (i; 0 .. dimSizes[dim])
				{
					// Do stuff with slices as to not consume the array
					// and also trigger a range error if something is wrong
					inner ~= bigEndianToNative!FT(value[offset .. offset + elementSize].to!(ubyte[FT.sizeof]));
					offset += elementSize;
				}
				res ~= inner;
			}
			return res;
		}

		return assemble!T();
	}
}


