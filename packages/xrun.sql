/*

# $Id: xrun.sql,v 1.3 2003/07/14 10:00:17 oradb Exp $

*/

CREATE OR REPLACE PROCEDURE xrun (	
	xarg IN  VARCHAR2 DEFAULT 'default_x_value'
) IS
	xret VARCHAR2(64) DEFAULT xarg;
BEGIN -- $$
	SELECT sysdate INTO xret FROM dual;
	xpack.proc(xarg, xret);
	SELECT 'end-of-xrun' INTO xret FROM dual;
END xrun;
/
