/**
   Kinda hacked-together and not really complete prepared-statement thing.
   Needs a lot of work, as well as tests.

   Accepting donations in tests.
 */
module dpq.prepared;

import libpq.libpq;
import dpq.connection;
import dpq.result;

struct PreparedStatement
{
   private
   {
      Connection* _connection;
      string _name;
      string _command;
      Oid[] _paramTypes;
   }

   this(ref Connection conn, string name, string command, Oid[] paramTypes...)
   {
      _connection = &conn;
      _name = name;
      _command = command;
      _paramTypes = paramTypes;
   }

   @property string name()
   {
      return _name;
   }

   @property string command()
   {
      return _command;
   }


   Result run(T...)(T params)
   {
      return _connection.execPrepared(_name, params);
   }

   bool runAsync(T...)(T params)
   {
      return _connection.sendPrepared(_name, params);
   }
}
