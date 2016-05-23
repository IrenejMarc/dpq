///
module dpq.serialisers.array;

import std.typecons : Nullable;
import std.bitmanip;
import std.traits;
import std.conv : to;
import std.string : format;

import dpq.meta;
import dpq.serialisation;
import dpq.exception;
import dpq.value : Type;
import dpq.connection : Connection;

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
	------------------------------------

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
		// BYTEA uses its own serialiser
		// strings are arrays, but not handled by this serialiser
		return 
			isArray!T &&
			!isSomeString!T &&
			!is(T == ubyte[]) &&
			!is(T == byte[]);
	}

	static void enforceSupportedType(T)()
	{
		static assert (
				isSupportedType!T,
				"'%s' is not supported by ArraySerialiser".format(T.stringof));
	}

	static Nullable!(ubyte[]) serialise(T)(T val)
	{
		enforceSupportedType!T;

		alias RT = Nullable!(ubyte[]);
		ubyte[] result;
		import std.stdio;
	
		// ndim
		result ~= nativeToBigEndian(cast(int) ArrayDimensions!T);

		// data offset is 0, no NULL bitmap
		result ~= nativeToBigEndian(cast(int) 0);

		// OID of the array elements
		alias BT = BaseType!T;
		result ~= nativeToBigEndian(cast(int) SerialiserFor!BT.oidForType!BT);

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
			static if (isSupportedType!(RealType!(ForeachType!T)))
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
			static if (isSupportedType!(RealType!(ForeachType!T)))
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
		enforceSupportedType!T;

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
			static if (isSupportedType!FT)
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
				static if (isDynamicArray!TI)
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
				return cast(TI) inner;
			}
		}

		return assemble!T;
	}

	static Oid oidForType(T)()
	{
		enforceSupportedType!T;

		alias BT = RealType!(BaseType!T);

		Oid typeOid = SerialiserFor!BT.oidForType!BT;

		Oid* p = typeOid in arrayOIDs;
		assert(p != null, "Oid for type %s cannot be determined by ArraySerialiser".format(T.stringof));

		return *p;
	}

	static string nameForType(T)()
	{
		enforceSupportedType!T;

		alias FT = RealType!(ForeachType!T);
		alias serialiser = SerialiserFor!FT;
		return serialiser.nameForType!FT ~ "[]";
	}

	// Arrays are always created implicitly
	static void ensureExistence(T)(Connection c)
	{
		alias EType = BaseType!T;
		SerialiserFor!EType.ensureExistence!EType(c);
	}

	static void addCustomOid(Oid typeOid, Oid oid)
	{
		arrayOIDs[typeOid] = oid;
	}

	template ArrayDimensions(T)
	{
		static if (isSupportedType!T)
			enum ArrayDimensions = 1 + ArrayDimensions!(ForeachType!T);
		else 
			enum ArrayDimensions = 0;
	}
}

unittest
{
	import std.stdio;
	import dpq.serialisers.composite;

	writeln(" * ArraySerialiser");

	writeln("	* Array of scalar types");
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


	writeln("	* Empty array");

	int[] emptyScalarArr;
	serialised = ArraySerialiser.serialise(emptyScalarArr);
	assert(ArraySerialiser.deserialise!(int[])(serialised) == emptyScalarArr);


	writeln("	* Array of struct");
	struct Test
	{
		int a = 1;
	}

	// An oid needs to exist for struct serialisation
	CompositeTypeSerialiser.addCustomOid(
			CompositeTypeSerialiser.nameForType!Test,
			999999);

	Test[] testArr = [Test(1), Test(2)];
	serialised = ArraySerialiser.serialise(testArr);
	assert(ArraySerialiser.deserialise!(Test[])(serialised) == testArr);

	writeln("	* Array of arrays");
	int[][] twoDArray = [
		[1, 2, 3],
		[4, 5, 6],
		[7, 8, 9]
	];

	serialised = ArraySerialiser.serialise(twoDArray);
	assert(ArraySerialiser.deserialise!(int[][])(serialised) == twoDArray);

	import std.datetime;

	writeln("	* Array of SysTime");
	SysTime[] timeArr;
	timeArr ~= Clock.currTime;
	timeArr ~= Clock.currTime + 2.hours;
	timeArr ~= Clock.currTime + 24.hours;

	serialised = ArraySerialiser.serialise(timeArr);
	foreach (i, time; ArraySerialiser.deserialise!(SysTime[])(serialised))
	{
		// Serialiser only works with ms accuracy, so comparing them directly 
		// won't work in most cases.
		assert(time.toUnixTime == timeArr[i].toUnixTime);
	}

	writeln("	* Array of string");
	string[] stringArr = [
		"My first string.",
		"String numero dva",
		"Do I even need this many strings?",
		"Bye"
	];

	serialised = ArraySerialiser.serialise(stringArr);
	assert(ArraySerialiser.deserialise!(string[])(serialised) == stringArr);
}

// Element Oid => Array Oid map
private Oid[Oid] arrayOIDs;

static this()
{
	// Initialise arrayOIDs with the default values
	arrayOIDs[Type.INT4]   = Type.INT4ARRAY;
	arrayOIDs[Type.INT8]   = Type.INT8ARRAY;
	arrayOIDs[Type.INT2]   = Type.INT2ARRAY;
	arrayOIDs[Type.FLOAT4] = Type.FLOAT4ARRAY;
}
