module dpq.serialisers.array;

import std.typecons : Nullable;
import std.bitmanip;
import std.traits;
import std.conv : to;

import dpq.meta;
import dpq.serialisation;
import dpq.exception;

import libpq.libpq;



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
/**
	reverse-enigneering the source

	Name         | size in B       | notes
	------------------------------------
	ndim         | 4               | more than 0, less than MAXDIM
	data_offset  | 4               | data offset in bytes, if > 0, reads null bitmap
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

struct ArraySerialiser
{
	static bool isSupportedType(T)()
	{
		return isArray!T;
	}

	static Nullable!(ubyte[]) serialise(T)(T val)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by ArraySerialiser".format(T.stringof));

		alias RT = Nullable!(ubyte[]);
		ubyte[] result;
		import std.stdio;
	
		// ndim
		result ~= nativeToBigEndian(cast(int) ArrayDimensions!T);

		// data offset is 0, no NULL bitmap
		result ~= nativeToBigEndian(cast(int) 0);

		// OID of the array elements
		result ~= nativeToBigEndian(cast(int) oidForType!(RealType!(BaseType!(T))));

		// Dimension size for every dimension
		int[] dimSizes;
		void setDimensions(T)(T data, int dim = 0)
		{
			// Remember the dimension size, make sure array is not jagged
			if (dimSizes.length <= dim)
				dimSizes ~= data.length.to!int;
			else if (dimSizes[dim] != data.length)
				throw new DPQException("Multidimensional arrays must have sub-arrays with matching dimensions.");

			// Loop through array
			static if (isArray!(RealType!(ForeachType!T)))
			{
				foreach (v; data)
				{
					if (isAnyNull(v))
						throw new DPQException(
								"Multidimensional array can not have NULL sub-arrays");
					setDimensions(v, dim + 1);
				}
			}
		}
		setDimensions(val);

		foreach(dimSize; dimSizes)
		{
			// Dimension size
			result ~= nativeToBigEndian(cast(int) dimSize);
			// Lower bound
			result ~= nativeToBigEndian(cast(int) 1);
		}

		// Writes all the values, left-to-right to data
		void write(T)(T data)
		{
			static if (isArray!(RealType!(ForeachType!T)))
				foreach (v; data)
					write(v);
			else
			{
				foreach (v; data)
				{
					auto bs = toBytes(v);

					if (bs.isNull)
						result ~= nativeToBigEndian(cast(int) -1); // NULL element
					else
					{
						result ~= nativeToBigEndian(cast(int) bs.length);
						result ~= bs;
					}
				}
			}
		}
		write(val);

		return RT(result);
	}

	static T deserialise(T)(const(ubyte)[] bytes)
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by ArraySerialiser".format(T.stringof));

		// Basic array info
		int nDims = bytes.read!int;
		int offset = bytes.read!int;
		Oid oid = bytes.read!int;


		int[] dimSizes;
		int[] lowerBounds;
		dimSizes.length = nDims;
		lowerBounds.length = nDims;

		// Read dimension sizes and lower bounds
		foreach (i; 0 .. nDims)
		{
			dimSizes[i] = bytes.read!int;
			lowerBounds[i] = bytes.read!int;
		}
		
		// I don't know what to do with this.
		ubyte[] nullBitmap;
		foreach (i; 0 .. offset)
			nullBitmap ~= bytes.read!ubyte;

		// Offset used for reading the actual data later
		TI assemble(TI)(int dim = 0)
		{
			TI arr;
			alias FT = RealType!(ForeachType!TI);

			// Recurse into the next dimension
			static if (isArray!FT)
			{
				static if (isDynamicArray!TI)
					arr.length = dimSizes[dim];

				assert(
						dimSizes[dim] == arr.length, 
						"Array sizes do not match, you probably specified an incorrect static array size somewhere.");

				foreach (i; 0 .. dimSizes[dim])
					arr[i] = assemble!FT(dim + 1);

				return arr;
			}
			// last dimension
			else
			{
				TI inner;
				static if (isDynamicArray!T)
					inner.length = dimSizes[dim];

				// For each of the elements, read its size, then their actual value
				foreach (i; 0 .. dimSizes[dim])
				{
					int len = bytes.read!int;
					// We're using "global" offset here, because we're reading the array left-to-right
					inner[i] = fromBytes!FT(bytes[0 .. len], len);

					// "Consume" the array
					bytes = bytes[len .. $];
				}
				return inner;
			}
		}

		return assemble!T;
	}
}

unittest
{
	import std.stdio;
	writeln(" * ArraySerialiser");

	int[2][2] arr = [[1, 2], [3, 4]];
	ubyte[] expected = [
		0, 0, 0, 2, // dims
		0, 0, 0, 0, // offset
		0, 0, 0, 23, // oid

		0, 0, 0, 2, // dim 0 size
		0, 0, 0, 1, // dim 0 lBound
		0, 0, 0, 2, // dim 1 size
		0, 0, 0, 1, // dim 1 lBound


		0, 0, 0, 4, // element size
		0, 0, 0, 1, // element value

		0, 0, 0, 4, // element size
		0, 0, 0, 2, // element value

		0, 0, 0, 4, // element size
		0, 0, 0, 3, // element value

		0, 0, 0, 4, // element size
		0, 0, 0, 4, // element value
	];

	auto serialised = ArraySerialiser.serialise(arr);
	assert(serialised == expected);
	assert(ArraySerialiser.deserialise!(int[2][2])(serialised) == arr);
}
