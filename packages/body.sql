/*

# $Id: body.sql,v 1.2 2003/05/16 13:10:20 oradb Exp $

The body for the DB package we use in both Oracle and Perl environments.

*/

create or replace package body db as

  procedure q is
    runinfo dbms_debug.runtime_info;
    ret     binary_integer;
  begin
    ret := dbms_debug.continue(
      runinfo,
      dbms_debug.abort_execution ,
      0);
  end; --q

  procedure t is
    pkgs dbms_debug.backtrace_table;
    i    number;
  begin
    dbms_debug.print_backtrace(pkgs);
    i := pkgs.first();
    dbms_output.put_line('backtrace');
    while i is not null loop
      dbms_output.put_line('  ' || i || ': ' || pkgs(i).name || ' (' || pkgs(i).line# ||')');
      i := pkgs.next(i);
    end loop;
   exception
    when others then
     dbms_output.put_line('  backtrace exception: ' || sqlcode);
     dbms_output.put_line('                       ' || sqlerrm(sqlcode));
  end; -- t 
  
  procedure L is
    brkpts dbms_debug.breakpoint_table;
    i      number;

  begin
    dbms_debug.show_breakpoints(brkpts); 
    i := brkpts.first();
    dbms_output.put_line('breakpoints');
    while i is not null loop
      dbms_output.put_line('  ' || i || ': ' || brkpts(i).name || ' (' || brkpts(i).line# ||')');
      i := brkpts.next(i);
    end loop;
  end; -- L

  procedure continue_(break_flags in number) is
    runinfo dbms_debug.runtime_info;
    ret     binary_integer;
  begin
    ret := dbms_debug.continue(
      runinfo,
        break_flags,
    --   dbms_debug.break_next_line     +  -- Break at next source line (step over calls). 
    --   dbms_debug.break_any_call      +  -- Break at next source line (step into calls). 
    --   dbms_debug.break_any_return    +
    --   dbms_debug.break_return        +
    --   dbms_debug.break_exception     +
    --   dbms_debug.break_handler       +
    --   dbms_debug.q     +
       0             +
       dbms_debug.info_getlineinfo   +
       dbms_debug.info_getbreakpoint +
       dbms_debug.info_getstackdepth +
       0);
  
     if ret = dbms_debug.success then
      -- dbms_output.put_line('  continue: success');
       -- print_runtime_info(runinfo);
       print_runtime_info_with_source(runinfo,p_cont_lines_before, p_cont_lines_after,p_cont_lines_width);
     elsif ret = dbms_debug.error_timeout then 
       dbms_output.put_line('  continue: error_timeout');
     elsif ret = dbms_debug.error_communication then
       dbms_output.put_line('  continue: error_communication');
     else
       dbms_output.put_line('  continue: unknown error, ret = ' || ret);
     end if;
  end; -- continue_

  procedure c is
  begin
    continue_(0);
  end;  -- c

  procedure B(breakpoint in binary_integer) is
    ret binary_integer;
  begin
    ret := dbms_debug.delete_breakpoint(breakpoint);

    if ret = dbms_debug.success then
      dbms_output.put_line('  breakpoint deleted');
    elsif ret = dbms_debug.error_no_such_breakpt then
      dbms_output.put_line('  No such breakpoint exists');
    elsif ret = dbms_debug.error_idle_breakpt then
      dbms_output.put_line('  Cannot delete an unused breakpoint');
    elsif ret = dbms_debug.error_stale_breakpt then
      dbms_output.put_line('  The program unit was redefined since the breakpoint was set');
    else
      dbms_output.put_line('  Unknown error');
    end if;
  end; -- B

  procedure p(name in varchar2) is
    ret   binary_integer;
    val   varchar2(4000);
    frame number;
  begin
    frame := 0;
    ret := dbms_debug.get_value(
      name,
      frame,
      val,
      null);

    if ret = dbms_debug.success then
      dbms_output.put_line('  ' || name || ' = ' || val);
    elsif ret = dbms_debug.error_bogus_frame then
      dbms_output.put_line('  print_var: frame does not exist');
    elsif ret = dbms_debug.error_no_debug_info then
      dbms_output.put_line('  print_var: Entrypoint has no debug info');
    elsif ret = dbms_debug.error_no_such_object then
      dbms_output.put_line('  print_var: variable ' || name || ' does not exist in in frame ' || frame);
    elsif ret = dbms_debug.error_unknown_type then
      dbms_output.put_line('  print_var: The type information in the debug information is illegible');
    elsif ret = dbms_debug.error_nullvalue then
      dbms_output.put_line('  ' || name || ' = NULL');
    elsif ret = dbms_debug.error_indexed_table then
      dbms_output.put_line('  print_var: The object is a table, but no index was provided.');
    else
      dbms_output.put_line('  print_var: unknown error');
    end if;
  end; -- p

  procedure debug(debug_session_id in varchar2) is
  begin
    dbms_debug.attach_session(debug_session_id);
    p_cont_lines_before :=   5;
    p_cont_lines_after  :=   5;
    p_cont_lines_width  := 100;
    dbms_output.put_line('  debug session started?');
  end; -- debug

  function target return varchar2 as
    debug_session_id varchar2(20); 
  begin
    select dbms_debug.initialize into debug_session_id from dual;
		--
    dbms_debug.debug_on(TRUE, FALSE);
    return debug_session_id;
  end;  -- target
  
  procedure print_proginfo(prginfo dbms_debug.program_info) as
  begin
    dbms_output.put_line('  Namespace:  ' || str_for_namespace(prginfo.namespace));
    dbms_output.put_line('  Name:       ' || prginfo.name);
    dbms_output.put_line('  owner:      ' || prginfo.owner);
    dbms_output.put_line('  dblink:     ' || prginfo.dblink);
    dbms_output.put_line('  Line#:      ' || prginfo.Line#);
    dbms_output.put_line('  lib unit:   ' || prginfo.libunittype);
    dbms_output.put_line('  entrypoint: ' || prginfo.entrypointname);
  end;  -- program_info

  procedure print_runtime_info(runinfo dbms_debug.runtime_info) as
    rsnt varchar2(40);
  begin

    rsnt := str_for_reason_in_runtime_info(runinfo.reason);
    --rsn := runinfo.reason;
    dbms_output.put_line('');
    dbms_output.put_line('Runtime Info');
    dbms_output.put_line('Line:          ' || runinfo.line#);
    dbms_output.put_line('Terminated:    ' || runinfo.terminated);
    dbms_output.put_line('Breakpoint:    ' || runinfo.breakpoint);
    dbms_output.put_line('Stackdepth     ' || runinfo.stackdepth);
    dbms_output.put_line('Reason         ' || rsnt);
    
    print_proginfo(runinfo.program);
  end; -- print_runtime_info

  procedure print_runtime_info_with_source(
    runinfo dbms_debug.runtime_info, 
    v_lines_before in number, 
    v_lines_after  in number,
    v_lines_width  in number) is
    prefix char(3);
    suffix varchar2(4000);
    line_printed char(1):='N';   
  begin
    for r in (select line, text
              from all_source 
              where 
                name  =  runinfo.program.name           and
                owner =  runinfo.program.owner          and
								type != 'PACKAGE' and
                line  >= runinfo.line# - 5 and --v_lines_before and
                line  <= runinfo.line# + 5 --v_lines_after  
              order by 
                line) loop
      if r.line = runinfo.line# then 
        prefix := ' * ';
      else
        prefix := '   ';
      end if;

      if length(r.text) > v_lines_width then
        suffix := substr(r.text,1,v_lines_width);
      else
        suffix := r.text;
      end if;

      suffix := translate(suffix,chr(10),' ');
      suffix := translate(suffix,chr(13),' ');
      
      dbms_output.put_line(prefix || suffix);

      line_printed := 'Y';
      end loop;

      if line_printed = 'N' then
        print_runtime_info(runinfo);
      end if;
  end;

  procedure self_check as
    ret binary_integer;
  begin
    dbms_debug.self_check(5);
  exception
    when dbms_debug.pipe_creation_failure     then
      dbms_output.put_line('  self_check: pipe_creation_failure');
    when dbms_debug.pipe_send_failure      then
      dbms_output.put_line('  self_check: pipe_send_failure');
    when dbms_debug.pipe_receive_failure   then
      dbms_output.put_line('  self_check: pipe_receive_failure');
    when dbms_debug.pipe_datatype_mismatch then
      dbms_output.put_line('  self_check: pipe_datatype_mismatch');
    when dbms_debug.pipe_data_error        then
      dbms_output.put_line('  self_check: pipe_data_error');
    when others then
      dbms_output.put_line('  self_check: unknown error');
  end; -- self_check

  procedure b (
    name in varchar2, line in number, owner in varchar2 default null) 
  as
    proginfo dbms_debug.program_info;
    ret      binary_integer;
    bp       binary_integer;
    v_owner  varchar2(30);
  begin
    if owner is null then
      v_owner := user;
    else
      v_owner := owner;
    end if;
  
    proginfo.namespace      := dbms_debug.namespace_pkgspec_or_toplevel;
    proginfo.name   := UPPER(name);
    proginfo.owner  := v_owner;
    proginfo.dblink         := null;
    proginfo.line#  := line;
    proginfo.entrypointname := null;
  
    ret := dbms_debug.set_breakpoint(
      proginfo,
      proginfo.line#,
      bp);
  
    if ret = dbms_debug.success then 
      dbms_output.put_line('  set_breakpoint: success');
    elsif ret = dbms_debug.error_illegal_line then
      dbms_output.put_line('  set_breakpoint: error_illegal_line');
    elsif ret = dbms_debug.error_bad_handle then
      dbms_output.put_line('  set_breakpoint: error_bad_handle');
    else
      dbms_output.put_line('  set_breakpoint: unknown error');
    end if;
  
    dbms_output.put_line('  breakpoint: ' || bp);
  end;  -- b 

  procedure n is
  begin
    continue_(dbms_debug.break_next_line);
  end; -- n
 
  procedure s is
  begin
    continue_(dbms_debug.break_any_call);
  end; -- s

  procedure r is
  begin
    continue_(dbms_debug.break_any_return);
  end; -- r

  function str_for_namespace(nsp in binary_integer) return varchar2 is
    nsps   varchar2(40);
  begin
    if nsp = dbms_debug.Namespace_cursor then
      nsps := 'Cursor (anonymous block)';
    elsif nsp = dbms_debug.Namespace_pkgspec_or_toplevel then
      nsps := 'package, proc, func or obj type';
    elsif nsp = dbms_debug.Namespace_pkg_body then
      nsps := 'package body or type body';
    elsif nsp = dbms_debug.Namespace_trigger then
      nsps := 'Triggers';
    else
      nsps := 'Unknown namespace';
    end if;

    return nsps;
  end; -- str_for_namespace

  function  str_for_reason_in_runtime_info(rsn in binary_integer) return varchar2 is
    rsnt varchar2(40);
  begin
    if rsn = dbms_debug.reason_none then
      rsnt := 'none';
    elsif rsn = dbms_debug.reason_interpreter_starting then
      rsnt := 'Interpreter is starting.';
    elsif rsn = dbms_debug.reason_breakpoint then
      rsnt := 'Hit a breakpoint';
    elsif rsn = dbms_debug.reason_enter then
      rsnt := 'Procedure entry';
    elsif rsn = dbms_debug.reason_return then
      rsnt := 'Procedure is about to return';
    elsif rsn = dbms_debug.reason_finish then
      rsnt := 'Procedure is finished';
    elsif rsn = dbms_debug.reason_line then
      rsnt := 'Reached a new line';
    elsif rsn = dbms_debug.reason_interrupt then
      rsnt := 'An interrupt occurred';
    elsif rsn = dbms_debug.reason_exception then
      rsnt := 'An exception was raised';
    elsif rsn = dbms_debug.reason_exit then
      rsnt := 'Interpreter is exiting (old form)';
    elsif rsn = dbms_debug.reason_knl_exit then
      rsnt := 'Kernel is exiting';
    elsif rsn = dbms_debug.reason_handler then
      rsnt := 'Start exception-handler';
    elsif rsn = dbms_debug.reason_timeout then
      rsnt := 'A timeout occurred';
    elsif rsn = dbms_debug.reason_instantiate then
      rsnt := 'Instantiation block';
    elsif rsn = dbms_debug.reason_abort then
      rsnt := 'Interpreter is aborting';
    else
      rsnt := 'Unknown reason';
    end if;
    return rsnt;
  end;  -- str_for_reason_in_runtime_info

  procedure sync as
    runinfo dbms_debug.runtime_info;
    ret     binary_integer;
  begin
    ret:=dbms_debug.synchronize(
      runinfo,
      0 +
      dbms_debug.info_getstackdepth +
      dbms_debug.info_getbreakpoint +
      dbms_debug.info_getlineinfo   +
      0
    );
    print_runtime_info(runinfo); -- anyway rjsf
    if ret = dbms_debug.success then 
      --dbms_output.put_line('  synchronize: success');
      print_runtime_info(runinfo);
    elsif ret = dbms_debug.error_timeout then
      dbms_output.put_line('  synchronize: error_timeout');
    elsif ret = dbms_debug.error_communication then
      dbms_output.put_line('  synchronize: error_communication');
    else
      dbms_output.put_line('  synchronize: unknown error');
    end if;
  end;  -- synchronize

  procedure target_running is
  begin
    if dbms_debug.target_program_running then
      dbms_output.put_line('  target is running');
    else
      dbms_output.put_line('  target is not running');
    end if;
  end; -- target_running

  procedure version as
    major binary_integer;
    minor binary_integer;
  begin
    dbms_debug.probe_version(major,minor);
    dbms_output.put_line('  probe version is: ' || major || '.' || minor);
  end; -- version

end;

