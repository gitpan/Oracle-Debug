/*

Create a dummy package and procedure to debug

*/

CREATE OR REPLACE PROCEDURE xproc (	
	xarg IN  VARCHAR2 DEFAULT 'default_x_value'
) IS
	xret VARCHAR2(64) DEFAULT xarg;
BEGIN -- $$
	SELECT sysdate INTO xret FROM dual;
	oradb_package.proc(xarg);
END xproc;
/

CREATE OR REPLACE FUNCTION xfunc (	
	xarg IN  VARCHAR2 DEFAULT 'default_x_value'
) RETURN VARCHAR2 IS
	xret VARCHAR2(64) DEFAULT xarg;
BEGIN -- $$
	SELECT sysdate INTO xret FROM dual;
	oradb_package.proc(xarg);
	RETURN xret;
END xfunc;
/

CREATE OR REPLACE PACKAGE oradb_package IS
	PROCEDURE proc (
		xarg IN  VARCHAR2 DEFAULT 'default_proc_value'
	);
	FUNCTION func (
		xarg IN  VARCHAR2 DEFAULT 'default_func_value'
	) RETURN VARCHAR2;
END oradb_package;
/
CREATE OR REPLACE PACKAGE BODY oradb_package IS

	PROCEDURE proc (
		xarg IN  VARCHAR2 DEFAULT 'default_proc_value'
	) IS
		xret VARCHAR2(64) DEFAULT xarg;
	BEGIN -- proc
		SELECT sysdate INTO xret FROM dual;
	END proc;

	FUNCTION func (
		xarg IN  VARCHAR2 DEFAULT 'default_func_value'
	) RETURN VARCHAR2 IS
		xret VARCHAR2(64) DEFAULT xarg;
	BEGIN -- func
		SELECT sysdate INTO xret FROM dual;
		RETURN xret;
	END func;

END oradb_package;
/
