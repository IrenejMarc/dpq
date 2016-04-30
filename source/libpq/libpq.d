module libpq.libpq;

import core.stdc.stdio;

extern (C):
nothrow:
@nogc:

//pg_config_ext.h
alias PG_INT64_TYPE = long;

//postgres_ext.h
alias uint Oid;
alias long pg_int64;

enum OID_MAX = uint.max;
enum PG_DIAG_SEVERITY = 'S';
enum PG_DIAG_SQLSTATE = 'C';
enum PG_DIAG_MESSAGE_PRIMARY = 'M';
enum PG_DIAG_MESSAGE_DETAIL = 'D';
enum PG_DIAG_MESSAGE_HINT = 'H';
enum PG_DIAG_STATEMENT_POSITION = 'P';
enum PG_DIAG_INTERNAL_POSITION = 'p';
enum PG_DIAG_INTERNAL_QUERY = 'q';
enum PG_DIAG_CONTEXT = 'W';
enum PG_DIAG_SCHEMA_NAME = 's';
enum PG_DIAG_TABLE_NAME = 't';
enum PG_DIAG_COLUMN_NAME = 'c';
enum PG_DIAG_DATATYPE_NAME = 'd';
enum PG_DIAG_CONSTRAINT_NAME = 'n';
enum PG_DIAG_SOURCE_FILE = 'F';
enum PG_DIAG_SOURCE_LINE = 'L';
enum PG_DIAG_SOURCE_FUNCTION = 'R';
//libpq-fe.h
enum PG_COPYRES_ATTRS = 0x01;
enum PG_COPYRES_TUPLES = 0x02;
enum PG_COPYRES_EVENTS = 0x04;
enum PG_COPYRES_NOTICEHOOKS = 0x08;
enum PQnoPasswordSupplied = "fe_sendauth: no password supplied\n";

enum 
{
    CONNECTION_OK = 0,
    CONNECTION_BAD = 1,
    CONNECTION_STARTED = 2,
    CONNECTION_MADE = 3,
    CONNECTION_AWAITING_RESPONSE = 4,
    CONNECTION_AUTH_OK = 5,
    CONNECTION_SETENV = 6,
    CONNECTION_SSL_STARTUP = 7,
    CONNECTION_NEEDED = 8
}

// TODO: fix aliases to alias X = Y style
alias int ConnStatusType;

enum 
{
    PGRES_POLLING_FAILED = 0,
    PGRES_POLLING_READING = 1,
    PGRES_POLLING_WRITING = 2,
    PGRES_POLLING_OK = 3,
    PGRES_POLLING_ACTIVE = 4
}

alias int PostgresPollingStatusType;

enum 
{
    PGRES_EMPTY_QUERY = 0,
    PGRES_COMMAND_OK = 1,
    PGRES_TUPLES_OK = 2,
    PGRES_COPY_OUT = 3,
    PGRES_COPY_IN = 4,
    PGRES_BAD_RESPONSE = 5,
    PGRES_NONFATAL_ERROR = 6,
    PGRES_FATAL_ERROR = 7,
    PGRES_COPY_BOTH = 8,
    PGRES_SINGLE_TUPLE = 9
}

alias int ExecStatusType;

enum 
{
    PQTRANS_IDLE = 0,
    PQTRANS_ACTIVE = 1,
    PQTRANS_INTRANS = 2,
    PQTRANS_INERROR = 3,
    PQTRANS_UNKNOWN = 4
}

alias int PGTransactionStatusType;

enum 
{
    PQERRORS_TERSE = 0,
    PQERRORS_DEFAULT = 1,
    PQERRORS_VERBOSE = 2
}

alias int PGVerbosity;

enum 
{
    PQPING_OK = 0,
    PQPING_REJECT = 1,
    PQPING_NO_RESPONSE = 2,
    PQPING_NO_ATTEMPT = 3
}

alias int PGPing;

struct pg_conn;
struct pg_result;
struct pg_cancel;

alias pg_conn PGconn;
alias pg_result PGresult;
alias pg_cancel PGcancel;

struct pgNotify
{
    char* relname;
    int be_pid;
    char* extra;
    pgNotify* next;
}

alias pgNotify PGnotify;

alias void function (void*, const(pg_result)*) PQnoticeReceiver;
alias void function (void*, const(char)*) PQnoticeProcessor;

alias char pqbool;

struct _PQprintOpt
{
    pqbool header;
    pqbool align_;
    pqbool standard;
    pqbool html3;
    pqbool expanded;
    pqbool pager;
    char* fieldSep;
    char* tableOpt;
    char* caption;
    char** fieldName;
}

alias _PQprintOpt PQprintOpt;

struct _PQconninfoOption
{
    char* keyword;
    char* envvar;
    char* compiled;
    char* val;
    char* label;
    char* dispchar;
    int dispsize;
}

alias _PQconninfoOption PQconninfoOption;

struct _PQArgBlock
{
    int len;
    int isint;

    union
    {
        int* ptr;
        int integer;
    }
}

alias _PQArgBlock PQArgBlock;

struct pgresAttDesc
{
    char* name;
    Oid tableid;
    int columnid;
    int format;
    Oid typid;
    int typlen;
    int atttypmod;
}

alias pgresAttDesc PGresAttDesc;
/* ----------------
 * Exported functions of libpq
 * ----------------
 */

/* ===	in fe-connect.c === */

/* make a new client connection to the backend */
/* Asynchronous (non-blocking) */
PGconn* PQconnectStart (const(char)* conninfo);
PGconn* PQconnectStartParams (const(char*)* keywords, const(char*)* values, int expand_dbname);
PostgresPollingStatusType PQconnectPoll (PGconn* conn);
PGconn* PQconnectdb (const(char)* conninfo);
PGconn* PQconnectdbParams (const(char*)* keywords, const(char*)* values, int expand_dbname);

PGconn* PQsetdbLogin (const(char)* pghost, const(char)* pgport, const(char)* pgoptions, const(char)* pgtty, const(char)* dbName, const(char)* login, const(char)* pwd);
//#define PQsetdb(M_PGHOST,M_PGPORT,M_PGOPT,M_PGTTY,M_DBNAME)  \
//	PQsetdbLogin(M_PGHOST, M_PGPORT, M_PGOPT, M_PGTTY, M_DBNAME, NULL, NULL)
PGconn* PQsetdb(const(char)* pghost, const(char)* pgport, const(char)* pgoptions, const(char)* pgtty, const(char)* dbName){
    return PQsetdbLogin(pghost,pgport,pgoptions, pgtty,dbName,null,null);
}

void PQfinish (PGconn* conn);
PQconninfoOption* PQconndefaults ();
PQconninfoOption* PQconninfoParse (const(char)* conninfo, char** errmsg);
PQconninfoOption* PQconninfo (PGconn* conn);
void PQconninfoFree (PQconninfoOption* connOptions);

/*
 * close the current connection and restablish a new one with the same
 * parameters
 */
/* Asynchronous (non-blocking) */
int PQresetStart (PGconn* conn);
PostgresPollingStatusType PQresetPoll (PGconn* conn);
void PQreset (PGconn* conn);
PGcancel* PQgetCancel (PGconn* conn);
void PQfreeCancel (PGcancel* cancel);
int PQcancel (PGcancel* cancel, char* errbuf, int errbufsize);
int PQrequestCancel (PGconn* conn);
char* PQdb (const(PGconn)* conn);
char* PQuser (const(PGconn)* conn);
char* PQpass (const(PGconn)* conn);
char* PQhost (const(PGconn)* conn);
char* PQport (const(PGconn)* conn);
char* PQtty (const(PGconn)* conn);
char* PQoptions (const(PGconn)* conn);
ConnStatusType PQstatus (const(PGconn)* conn);
PGTransactionStatusType PQtransactionStatus (const(PGconn)* conn);
const(char)* PQparameterStatus (const(PGconn)* conn, const(char)* paramName);
int PQprotocolVersion (const(PGconn)* conn);
int PQserverVersion (const(PGconn)* conn);
char* PQerrorMessage (const(PGconn)* conn);
int PQsocket (const(PGconn)* conn);
int PQbackendPID (const(PGconn)* conn);
int PQconnectionNeedsPassword (const(PGconn)* conn);
int PQconnectionUsedPassword (const(PGconn)* conn);
int PQclientEncoding (const(PGconn)* conn);
int PQsetClientEncoding (PGconn* conn, const(char)* encoding);
void* PQgetssl (PGconn* conn);
void PQinitSSL (int do_init);
void PQinitOpenSSL (int do_ssl, int do_crypto);
PGVerbosity PQsetErrorVerbosity (PGconn* conn, PGVerbosity verbosity);
void PQtrace (PGconn* conn, FILE* debug_port);
void PQuntrace (PGconn* conn);
PQnoticeReceiver PQsetNoticeReceiver (PGconn* conn, PQnoticeReceiver proc, void* arg);
PQnoticeProcessor PQsetNoticeProcessor (PGconn* conn, PQnoticeProcessor proc, void* arg);
alias void function (int) pgthreadlock_t;
pgthreadlock_t PQregisterThreadLock (pgthreadlock_t newhandler);
PGresult* PQexec (PGconn* conn, const(char)* query);
PGresult* PQexecParams (PGconn* conn, const(char)* command, int nParams, const(Oid)* paramTypes, const(char*)* paramValues, const(int)* paramLengths, const(int)* paramFormats, int resultFormat);
PGresult* PQprepare (PGconn* conn, const(char)* stmtName, const(char)* query, int nParams, const(Oid)* paramTypes);
PGresult* PQexecPrepared (PGconn* conn, const(char)* stmtName, int nParams, const(char*)* paramValues, const(int)* paramLengths, const(int)* paramFormats, int resultFormat);
int PQsendQuery (PGconn* conn, const(char)* query);
int PQsendQueryParams (PGconn* conn, const(char)* command, int nParams, const(Oid)* paramTypes, const(char*)* paramValues, const(int)* paramLengths, const(int)* paramFormats, int resultFormat);
int PQsendPrepare (PGconn* conn, const(char)* stmtName, const(char)* query, int nParams, const(Oid)* paramTypes);
int PQsendQueryPrepared (PGconn* conn, const(char)* stmtName, int nParams, const(char*)* paramValues, const(int)* paramLengths, const(int)* paramFormats, int resultFormat);
int PQsetSingleRowMode (PGconn* conn);
PGresult* PQgetResult (PGconn* conn);
int PQisBusy (PGconn* conn);
int PQconsumeInput (PGconn* conn);
PGnotify* PQnotifies (PGconn* conn);
int PQputCopyData (PGconn* conn, const(char)* buffer, int nbytes);
int PQputCopyEnd (PGconn* conn, const(char)* errormsg);
int PQgetCopyData (PGconn* conn, char** buffer, int async);
int PQgetline (PGconn* conn, char* string, int length);
int PQputline (PGconn* conn, const(char)* string);
int PQgetlineAsync (PGconn* conn, char* buffer, int bufsize);
int PQputnbytes (PGconn* conn, const(char)* buffer, int nbytes);
int PQendcopy (PGconn* conn);
int PQsetnonblocking (PGconn* conn, int arg);
int PQisnonblocking (const(PGconn)* conn);
int PQisthreadsafe ();
PGPing PQping (const(char)* conninfo);
PGPing PQpingParams (const(char*)* keywords, const(char*)* values, int expand_dbname);
int PQflush (PGconn* conn);
PGresult* PQfn (PGconn* conn, int fnid, int* result_buf, int* result_len, int result_is_int, const(PQArgBlock)* args, int nargs);
ExecStatusType PQresultStatus (const(PGresult)* res);
char* PQresStatus (ExecStatusType status);
char* PQresultErrorMessage (const(PGresult)* res);
char* PQresultErrorField (const(PGresult)* res, int fieldcode);
int PQntuples (const(PGresult)* res);
int PQnfields (const(PGresult)* res);
int PQbinaryTuples (const(PGresult)* res);
char* PQfname (const(PGresult)* res, int field_num);
int PQfnumber (const(PGresult)* res, const(char)* field_name);
Oid PQftable (const(PGresult)* res, int field_num);
int PQftablecol (const(PGresult)* res, int field_num);
int PQfformat (const(PGresult)* res, int field_num);
Oid PQftype (const(PGresult)* res, int field_num);
int PQfsize (const(PGresult)* res, int field_num);
int PQfmod (const(PGresult)* res, int field_num);
char* PQcmdStatus (PGresult* res);
char* PQoidStatus (const(PGresult)* res);
Oid PQoidValue (const(PGresult)* res);
char* PQcmdTuples (PGresult* res);
char* PQgetvalue (const(PGresult)* res, int tup_num, int field_num);
int PQgetlength (const(PGresult)* res, int tup_num, int field_num);
int PQgetisnull (const(PGresult)* res, int tup_num, int field_num);
int PQnparams (const(PGresult)* res);
Oid PQparamtype (const(PGresult)* res, int param_num);
PGresult* PQdescribePrepared (PGconn* conn, const(char)* stmt);
PGresult* PQdescribePortal (PGconn* conn, const(char)* portal);
int PQsendDescribePrepared (PGconn* conn, const(char)* stmt);
int PQsendDescribePortal (PGconn* conn, const(char)* portal);
void PQclear (PGresult* res);
void PQfreemem (void* ptr);

alias PQfreeNotify = PQfreemem;

PGresult* PQmakeEmptyPGresult (PGconn* conn, ExecStatusType status);
PGresult* PQcopyResult (const(PGresult)* src, int flags);
int PQsetResultAttrs (PGresult* res, int numAttributes, PGresAttDesc* attDescs);
void* PQresultAlloc (PGresult* res, size_t nBytes);
int PQsetvalue (PGresult* res, int tup_num, int field_num, char* value, int len);
size_t PQescapeStringConn (PGconn* conn, char* to, const(char)* from, size_t length, int* error);
char* PQescapeLiteral (PGconn* conn, const(char)* str, size_t len);
char* PQescapeIdentifier (PGconn* conn, const(char)* str, size_t len);
ubyte* PQescapeByteaConn (PGconn* conn, const(ubyte)* from, size_t from_length, size_t* to_length);
ubyte* PQunescapeBytea (const(ubyte)* strtext, size_t* retbuflen);
size_t PQescapeString (char* to, const(char)* from, size_t length);
ubyte* PQescapeBytea (const(ubyte)* from, size_t from_length, size_t* to_length);
void PQprint (FILE* fout, const(PGresult)* res, const(PQprintOpt)* ps);
void PQdisplayTuples (const(PGresult)* res, FILE* fp, int fillAlign, const(char)* fieldSep, int printHeader, int quiet);
void PQprintTuples (const(PGresult)* res, FILE* fout, int printAttName, int terseOutput, int width);
int lo_open (PGconn* conn, Oid lobjId, int mode);
int lo_close (PGconn* conn, int fd);
int lo_read (PGconn* conn, int fd, char* buf, size_t len);
int lo_write (PGconn* conn, int fd, const(char)* buf, size_t len);
int lo_lseek (PGconn* conn, int fd, int offset, int whence);
pg_int64 lo_lseek64 (PGconn* conn, int fd, pg_int64 offset, int whence);
Oid lo_creat (PGconn* conn, int mode);
Oid lo_create (PGconn* conn, Oid lobjId);
int lo_tell (PGconn* conn, int fd);
pg_int64 lo_tell64 (PGconn* conn, int fd);
int lo_truncate (PGconn* conn, int fd, size_t len);
int lo_truncate64 (PGconn* conn, int fd, pg_int64 len);
int lo_unlink (PGconn* conn, Oid lobjId);
Oid lo_import (PGconn* conn, const(char)* filename);
Oid lo_import_with_oid (PGconn* conn, const(char)* filename, Oid lobjId);
int lo_export (PGconn* conn, Oid lobjId, const(char)* filename);
int PQlibVersion ();
int PQmblen (const(char)* s, int encoding);
int PQdsplen (const(char)* s, int encoding);
int PQenv2encoding ();
char* PQencryptPassword (const(char)* passwd, const(char)* user);
int pg_char_to_encoding (const(char)* name);
const(char)* pg_encoding_to_char (int encoding);
int pg_valid_server_encoding_id (int encoding);

//libpq-events.h

enum _Anonymous_0
{
    PGEVT_REGISTER = 0,
    PGEVT_CONNRESET = 1,
    PGEVT_CONNDESTROY = 2,
    PGEVT_RESULTCREATE = 3,
    PGEVT_RESULTCOPY = 4,
    PGEVT_RESULTDESTROY = 5
}

alias _Anonymous_0 PGEventId;

struct _Anonymous_1
{
    PGconn* conn;
}

alias _Anonymous_1 PGEventRegister;

struct _Anonymous_2
{
    PGconn* conn;
}

alias _Anonymous_2 PGEventConnReset;

struct _Anonymous_3
{
    PGconn* conn;
}

alias _Anonymous_3 PGEventConnDestroy;

struct _Anonymous_4
{
    PGconn* conn;
    PGresult* result;
}

alias _Anonymous_4 PGEventResultCreate;

struct _Anonymous_5
{
    const(PGresult)* src;
    PGresult* dest;
}

alias _Anonymous_5 PGEventResultCopy;

struct _Anonymous_6
{
    PGresult* result;
}

alias _Anonymous_6 PGEventResultDestroy;
alias int function (_Anonymous_0, void*, void*) PGEventProc;

int PQregisterEventProc (PGconn* conn, PGEventProc proc, const(char)* name, void* passThrough);
int PQsetInstanceData (PGconn* conn, PGEventProc proc, void* data);
void* PQinstanceData (const(PGconn)* conn, PGEventProc proc);
int PQresultSetInstanceData (PGresult* result, PGEventProc proc, void* data);
void* PQresultInstanceData (const(PGresult)* result, PGEventProc proc);
int PQfireResultCreateEvents (PGconn* conn, PGresult* res);
