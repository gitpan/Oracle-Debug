/*

Create a dummy package and procedure to debug

*/

CREATE OR REPLACE PROCEDURE X (	
	xarg IN  VARCHAR2 DEFAULT 'default_x_value'
) IS
	xret VARCHAR2(64) DEFAULT xarg;
BEGIN -- $$
	xret := 'this-n-that';
	SELECT sysdate INTO xret FROM dual;
	oradb_package.oradb_proc(xarg);
END X;
/

CREATE OR REPLACE PACKAGE oradb_package IS
	PROCEDURE oradb_proc (
		xarg IN  VARCHAR2 DEFAULT 'default_proc_value'
	);
	FUNCTION oradb_func (
		xarg IN  VARCHAR2 DEFAULT 'default_func_value'
	) RETURN VARCHAR2;
END oradb_package;
/
CREATE OR REPLACE PACKAGE BODY oradb_package IS

	PROCEDURE oradb_proc (
		xarg IN  VARCHAR2 DEFAULT 'default_proc_value'
	) IS
		xret VARCHAR2(64) DEFAULT xarg;
	BEGIN -- oradb_proc
		SELECT sysdate INTO xret FROM dual;
	END oradb_proc;

	FUNCTION oradb_func (
		xarg IN  VARCHAR2 DEFAULT 'default_func_value'
	) RETURN VARCHAR2 IS
		xret VARCHAR2(64) DEFAULT xarg;
	BEGIN -- oradb_func
		SELECT sysdate INTO xret FROM dual;
		RETURN xret;
	END oradb_func;

END oradb_package;
/
