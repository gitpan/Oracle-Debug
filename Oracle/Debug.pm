
# $Id: Debug.pm,v 1.20 2003/05/17 17:06:23 oradb Exp $

=head1 NAME

Oracle::Debug - A Perl (perldb-like) interface to the Oracle DBMS_DEBUG package for debugging PL/SQL programs.

=cut

package Oracle::Debug;

use 5.008;
use strict;
use warnings;
use Carp qw(carp croak);
use Data::Dumper;
use DBI;
use Term::ReadKey;

use vars qw($VERSION);
$VERSION = do { my @r = (q$Revision: 1.20 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

my $DEBUG = $ENV{Oracle_Debug} || 0;

=head1 SYNOPSIS

	./oradb

=head1 ABSTRACT

A perl-debugger-like interface to the Oracle DBMS_DEBUG package for
debugging PL/SQL programs.

The initial impetus for creating this was to get a command-line interface,
similar in instruction set and feel to the perl debugger.  For this
reason, it may be beneficial for a user of this module, or at least the
intended B<oradb> interface, to be familiar with the perl debugger first.

=head1 DESCRIPTION

There are really 2 parts to this exersize:

=over 4

=item DB

The current Oracle chunk is a package which can be used directly to debug
PL/SQL without involving perl at all, but which has similar commands to
the perl debugger.

Please see the I<packages/header.sql> file for credits for the original B<db> PL/SQL.

=item oradb

The Perl chunk implements a perl-debugger-like interface to the Oracle
debugger itself, partially via the B<DB> library referenced above.

=back

In both cases much more conveniently from the command line, than the
vanilla Oracle packages themselves.  In fairness DBMS_DEBUG is probably
designed to be used from a GUI of some sort, but this module focuses on 
it from a command line usage.

=head1 NOTES

Ignore any methods which are prefixed with an underscore (_)

We use a special table B<rfi_oracle_debug> for our own purposes.

Set B<Oracle_Debug>=1 for debugging information.

=head1 METHODS

=over 4

=item new

Create a new Oracle::Debug object

	my $o_debug = Oracle::Debug->new(\%dbconnectdata);

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) ? ref($proto) : $proto;
	my $self  = bless({
		'_config'  => do 'scripts/config', #$h_conf,
		'_connected' => 0,
		'_dbh'       => {},
		'_debugpid'  => '',
		'_name'      => '',
		'_primed'    => 0,
		'_sessionid' => '',
		'_targetpid' => '',
		'_type'      => '',
	}, $class);
	$self->_prime;
	# $self->log($self.' '.Dumper($self)) if $DEBUG;
	return $self; 
}

=item _prime

Prime the object and connect to the db

Also ensure we are able to talk to Probe

	$o_debug->_prime;

=cut

sub _prime {
	my $self  = shift;
	my $h_ref = $self->{_config};
	unless (ref($h_ref) eq 'HASH') {
		$self->fatal("invalid db priming data hash ref: ".Dumper($h_ref));
	} else {
		# $self->{_dbh} = $self->dbh;
		$self->{_dbh}->{$$} = $self->_connect($h_ref);
		$self->{_primed}++ if $self->{_dbh}->{$$};
		$self->dbh->func(20000, 'dbms_output_enable');
		$self->self_check();
	}
	return ref($self->{_dbh}->{$$}) ? $self : undef;
}

# =============================================================================
# dbh and sql methods
# =============================================================================

=item dbh

Return the database handle

	my $dbh = $o_debug->dbh;

=cut

sub dbh {
	my $self = shift;
	# my $type = $self->{_config}->{type}; # debug-target
	return ref($self->{_dbh}->{$$}) ? $self->{_dbh}->{$$} : $self->_connect($self->{_config});
}

=item _connect

Connect to the database

=cut

sub _connect {
	my $self   = shift;
	my $h_conf = $self->{_config};

	my $dbh = DBI->connect(
		$h_conf->{datasrc},	$h_conf->{user}, $h_conf->{pass}, $h_conf->{params} 
	) || $self->fatal("Can't connect to database: $DBI::errstr");

	$self->{_connected}++;
	$self->log("connected: $dbh") if $DEBUG;

	return $dbh; #$id eq 'Debug' ? $dbh : 1;
}

=item getarow

Get a row

	my ($res) = $o_debug->getarow($sql);

=cut

sub getarow {
	my $self  = shift;
	my $sql   = shift;

	my @res = $self->dbh->selectrow_array($sql);
	
	if ($DEBUG) {
		$self->log("failed to getarow: $sql $DBI::errstr") unless @res >= 1;
	}

	return @res;
}

# =============================================================================
# parse and control
# =============================================================================

my %HISTORY = ();
my $COMMANDS= 'rc|src|test|perl|sql|shell';
my %GROUPS  = (
	+0	=> [qw(rc src)],
	+2	=> [qw(b c n r s)],
	+4	=> [qw(l p)],
	+6	=> [qw(h H ! q)],
	+8	=> [qw(test perl sql shell)],
);
my %COMMAND = (
	'b'		=> {
		'handle'	=> 'break',
		'syntax'	=> 'b [lineno]',
		'simple'	=> 'set breakpoint', 
		'detail'	=> 'set breakpoint on given line of code identified by name',
	},
	'c'	  => {
		'handle'	=> 'continue',
		'syntax'	=> 'c',
		'simple'	=> 'continue to next interesting event',
		'detail'	=> 'breakpoint or similar',
	},
	'h'	  => {
		'handle'	=> 'help',
		'syntax'	=> 'h [cmd|h|syntax]',
		'simple'	=> 'help listing - h h for more',
		'detail'	=> 'you can also give a command as an argument (eg: h b)',
	},
	'H'	  => {
		'handle'	=> 'history',
		'syntax'	=> 'H',
		'simple'	=> 'command history',
		'detail'	=> 'history listing not including single character commands',
	},
	'l'	  => {
		'handle'	=> 'list_breakpoints',
		'syntax'	=> 'l',
		'simple'	=> 'list breakpoints',
		'detail'	=> 'on which line breakpoints exist',
	},
	'n'	  => {
		'handle'	=> 'next',
		'syntax'	=> 'n',
		'simple'	=> 'next line',
		'detail'	=> 'continue until the next line',
	},
	'p'	  => {
		'handle'	=> 'get_val',
		'syntax'	=> 'p',
		'simple'	=> 'print',
		'detail'	=> 'print the value of a variable',
	},
	'perl'=> {
		'handle'	=> 'perl',
		'syntax'	=> 'perl <valid perl command>',
		'simple'	=> 'perl command',
		'detail'	=> 'execute a perl command',
	},
	'q'   => {
		'handle'	=> 'quit',
		'syntax'	=> 'q(uit)',
		'simple'	=> 'exit',
		'detail'	=> 'quit the oradb',
	},
	'r'	  => {
		'handle'	=> 'return',
		'syntax'	=> 'r',
		'simple'	=> 'return',
		'detail'	=> 'return from the current block',
	},
	'rc'  => {
		'handle'	=> 'recompile',
		'syntax'	=> 'rc name [<PROC>(EDURE)|PACK(AGE)]',
		'simple'	=> 'recompile + sync',
		'detail'	=> 'recompile the program and synchronize with the target, '.
                 '(note that this session _should_ hang until the procedure is executed in the target session)'
	},
	's'	  => {
		'handle'	=> 'step',
		'syntax'	=> 's',
		'simple'	=> 'step into',
		'detail'	=> 'step into the next function or method call',
	},
	'shell'	=> {
		'handle'	=> 'shell',
		'syntax'	=> 'shell <valid shell command>',
		'simple'	=> 'shell command',
		'detail'	=> 'execute a shell command',
	},
	'sql' => {
		'handle'	=> 'sql',
		'syntax'	=> 'sql <valid SQL>',
		'simple'	=> 'SQL select',
		'detail'	=> 'execute a SQL SELECT statement',
	},
	'src' => {
		'handle'	=> 'list_source',
		'syntax'	=> 'sql name [<PROC>(EDURE)|PACK(AGE)]',
		'simple'	=> 'list source code',
		'detail'	=> 'list source for given code (name)',
	},
	'test'=> {
		'handle'	=> 'is_running',
		'syntax'	=> 'test',
		'simple'	=> 'target is running',
		'detail'	=> 'test whether target session is currently running and responding',
	},
	'!'   => {
		'handle'	=> 'rerun',
		'syntax'	=> '! (!|historyno)',
		'simple'	=> 'run history command',
		'detail'	=> 'run a command from the history list',
	},
);

=cut

=item help

Print the help listings where I<levl> is one of: 

	h    (simple)

	h h  (detail)
	
	h b  (help for break command etc.)

	$o_oradb->help($levl);

=cut

sub help {
	my $self = shift;
	my $levl = shift || '';

	my $help = '';
	if (grep(/^$levl$/, keys %COMMAND)) {
			$help .= "\tsyntax: $COMMAND{$levl}{syntax}\n\t$COMMAND{$levl}{detail}\n";
	} else {
		$levl = 'simple' unless $levl =~ /^(simple|detail|syntax|handle)$/io;
		$help = "oradb help:\n";
		foreach my $grp (sort { $a <=> $b } keys %GROUPS) {
			foreach my $char (@{$GROUPS{$grp}}) {
				$help .= "\t".($levl ne 'syntax' ? "$char\t" : '')."$COMMAND{$char}{$levl}\n";
			}
			$help .= "\n";
		}
	}

	return $help;
}

=item parse

Parse the input command to the appropriate method

	$o_oradb->parse($cmd, $input);

=cut 

sub parse {
	my $self = shift;
	my $cmd  = shift;
	my $input= shift;

	unless ($self->can($COMMAND{$cmd}{handle})) {
		$self->error("command ($cmd) not understood");
		print $self->help;
	} else {
		$DB::single=2;
		my $handler = $COMMAND{$cmd}{handle} || 'help';
		# print "xxx ->$handler<- xxx\n";
		my @res = $self->$handler($input);
		# print "xxx ->@res<- xxx\n";
		$self->log("cmd($cmd) input($input) handler($handler) returned(@res)") if $DEBUG;
		print @res;
	}
}

# =============================================================================
# run and exec methods
# =============================================================================

=item do

Wrapper for oradb->dbh->do() - internally we still use prepare and execute.

	$o_oradb->do($sql);

=cut

sub do {
	my $self = shift;
	my $exec = shift;

	my $csr  = $self->dbh->prepare($exec);
	$self->fatal("Failed to prepare $exec - $DBI::errstr\n") unless $csr;

	my $i_res;
	eval {
		$i_res = $csr->execute; # returning 0E0 is true/ok/good
	};

	if ($@) {
		$self->fatal("Failure: $@ while evaling $exec - $DBI::errstr\n");
	}

	unless ($i_res) {
		$self->fatal("Failed to execute $exec - $DBI::errstr\n");
	}

	$self->log("do($exec)->res($i_res)") if $DEBUG;
	
	return $self;
}

=item recompile

Recompile this procedure|function|package for debugging

	my $i_res = $oradb->recompile('PROCEDURE x');

=cut

sub recompile {
	my $self = shift;
	my $args = shift;
	my @res  = ();

	my ($name, $type) = split(/\s+/, $args);
	$name = uc($name); $type = '' unless $type;
	$type = ($type =~ /^PROC/io ? 'PROCEDURE' : $type =~ /^FUNC/io ? 'FUNCTION' : $type =~ /^PACK/io ? 'PACKAGE' : 'PROCEDURE');
	unless ($name =~ /^\w+$/o && $type =~ /^\w+$/o) {
		$self->error("recompile requires a name($name) and type($type)");
	} else {
		$self->{_name} = $name;
		$self->{_type} = $name;
		my $exec = qq|ALTER $type $name COMPILE Debug|; 
		$exec .= ' BODY' if $type eq 'PACKAGE';
		@res = $self->do($exec)->get_msg;
		print "Synching - once this hangs, execute this in the target session\n"; 
		print "\t(if this does not hang, check the connection (with 'test'), and retry)\n";
		@res = $self->sync;
	}

	return @res;
}

=item perl 

Run a chunk of perl 

	$o_oradb->perl($perl);

=cut

sub perl {
		my $self = shift;
		my $perl = shift;
		
		eval $perl;
		if ($@) {
			$self->error("failed perl expression($perl) - $@");
		}
		return "\n";
}

=item shell 

Run a shell command 

	$o_oradb->shell($shellcommand);

=cut

sub shell {
		my $self  = shift;
		my $shell = shift;
		
		system($shell);
		if ($@) {
			$self->error("failed shell command($shell) - $@");
		}
		return "\n";
}

=item sql 

Run a chunk of SQL (select only)

	$o_oradb->sql($sql);

=cut

sub sql {
		my $self = shift;
		my $xsql = shift;
		my @res  = ();

		unless ($xsql =~ /^\s*SELECT\s+/o) {
			$self->error("SELECT statements only please: $xsql");
		} else {
			$xsql =~ s/\s*;\s*$//;
			@res = ($self->getarow($xsql), "\n");
		}

		return @res;
}

=item run

Run a chunk

	$o_oradb->run($sql);

=cut

sub run {
      my $self = shift;
      my $xsql = shift;

      my $exec = qq#
              BEGIN
                      $xsql;
              END;
      #;

      return $self->do($exec)->get_msg;
}


# =============================================================================
# start debug and target methods
# =============================================================================

=item target

Run the target session

	$o_oradb->target;

=cut

sub target {
	my $self = shift;

	my $dbid = $self->start_target('rfi_oradb_sessionid');
	
	ReadMode 0;
	print "orasql> enter a PL/SQL command to debug (debugger session must be running...)\n";
	while (1) {
		print "orasql>";
		chomp(my $input = ReadLine(0));
		$self->log("processing input($input)") if $DEBUG;
		if ($input =~ /^\s*(q\s*|quit\s*)$/io) {
			$self->quit;
		} else {
			$self->run($input);
		}
	}

	return $self;
}

=item start_target 

Get the target session id(given) and stick it in our table (by process_id)

	my $dbid = $oradb->start_target($dbid);

=cut

sub start_target {
	my $self = shift;
	my $dbid = shift;

	if ($self->{_debugid}) {
		$self->fatal("mix-n-matching debug and target processes is not allowed");
	}

	$self->{_targetpid} = $dbid;
	my $x_res = $self->do('DELETE FROM '.$self->{_config}{table}); # currently we only allow a single session at a time

	my $init = qq#
		DECLARE 
			xret VARCHAR2(32); 
		BEGIN 
			xret := dbms_debug.initialize('$dbid'); 
		END;
	#;
	$x_res = $self->do($init);

	my $ddid = qq#
		BEGIN 
			dbms_debug.debug_on(TRUE, FALSE); 
		END;
		#; # should hang (if 2nd true) unless debugger running
	$x_res = $self->do($ddid);

=rjsf
	# should be autonomous transaction
	my $insert = qq#INSERT INTO $self->{_config}{table} 
           (created, debugpid, targetpid, sessionid, data) 
		VALUES (sysdate, $$, $$, '$dbid', 'xxx'
	)#;
	$x_res = $self->do($insert);

	$x_res = $self->do('COMMIT');
=cut

	$self->log("target started: $dbid") if $DEBUG;

	return $dbid;
}

=item debugger

Run the debugger

	$o_debug->debugger;

=cut

sub debugger {
	my $self = shift;

	my $dbid = $self->start_debug('rfi_oradb_sessionid');
	
	ReadMode 0;
	print "Welcome to the oradb (type h for help)\n";
	my $i_cnt = 0;
	while (1) {
		print "oradb> ";
		chomp(my $input = ReadLine(0));
		$self->log("processing command($input)") if $DEBUG;
		if ($input =~ /^\s*($COMMANDS|.)\s*(.*)\s*$/o) {
			my ($cmd, $args) = ($1, $2); $args =~ s/^\s+//o; $args =~ s/\s+$//o;
			$self->log("input($input) -> cmd($cmd) args($args)") if $DEBUG;
			$HISTORY{++$i_cnt} = $cmd.' '.$args unless $cmd =~ /^\s*(.|!.*)\s*$/o;
			$self->parse($cmd, $args); # + process
		} else {
			$self->error("oradb> command ($input) not understood");	
		}
	}

	return $self; 
}

=item start_debug

Start the debugger session

	my $i_res = $oradb->start_debug($db_session_id, $pid);

=cut

sub start_debug {
	my $self = shift;
	my $dbid = shift;
	my $pid  = shift;

	# my $x_res = $self->do('UPDATE '.$self->{_config}{table}." SET debugpid = $pid");
	if ($self->{_targetid}) {
		$self->fatal("mix-n-matching target and debug processes is not allowed");
	}
	$self->{_debugpid} = $dbid;

	# SET serveroutput ON;                  -- done via dbi
	my $x_res = $self->do(qq#ALTER session SET plsql_debug=TRUE#)->get_msg;
	# ALTER session SET plsql_debug = TRUE; -- done per proc.

	my $exec = qq#
		BEGIN 
			dbms_debug.attach_session('$dbid'); 
			dbms_output.put_line('attached');
		END;
	#;

	return $self->do($exec)->get_msg;
}

=item sync

Blocks debug session until we exec in target session

	my $i_res = $oradb->sync;

=cut

sub sync {
	my $self = shift;

=rjsf
	my ($tid) = $self->getarow('SELECT targetpid FROM '.$self->{_config}{table}." WHERE debugpid = '".$self->{_debugpid}."'");
	$self->{_targetpid} = $tid;
=cut

	my $exec = qq#
		DECLARE	
			xret binary_integer;
			runtime dbms_debug.runtime_info;
		BEGIN	
			xret := dbms_debug.synchronize(runtime);
			IF xret = dbms_debug.success THEN
				dbms_output.put_line('synched ' || runtime.program.name);
			ELSIF xret = dbms_debug.error_timeout THEN
				dbms_output.put_line('timed out');
			ELSIF xret = dbms_debug.error_communication THEN
				dbms_output.put_line('communication failure');
			ELSE
				dbms_output.put_line('unknown error:' || xret);
			END IF;
		END;
	#;

	return $self->do($exec)->get_msg;
}

# ============================================================================= 
# b c n s r exec
# =============================================================================

=item exec 

Runs the given statement against the target session

	my $i_res = $oradb->exec($call);

=cut

sub exec {
	my $self = shift;
	my $call = shift;
	my $trim = $call; $trim =~ s/^(\w+)?\(.*$/$1/o;

	$self->{_name} = $trim;
	my @res = ();

	# small loop
	# check target is running
	#
	# alter call compile debug
	# request target call this prog in 3 secs...
	# sync (hang) with timeout
	#
	# $self->do($exec)->get_msg;

	return @res; 
}

=item execute 

Runs the given statement against the target session

	my $i_res = $oradb->execute($xsql);

=cut

sub _execute {
	my $self = shift;
	my $xsql = shift;

	my $exec = qq#
		DECLARE 
			col1 sys.dbms_debug_vc2coll; errm VARCHAR2(100); 
		BEGIN 
			dbms_debug.execute($xsql, -1, 0, col1, errm); 
		END;
	#;

	return $self->do($exec)->get_msg;
}

=item break

Set a breakpoint

	my $i_res = $oradb->break("PROCNAME $i_line");

=cut

sub break {
	my $self = shift;
	my $args = shift;
	my @res  = ();

	unless ($args =~ /^\s*(\w+)\s+(\d+)\s*$/o) {
		$self->error("must supply the name($1) and line number($2) of a chunk of PL/SQL to set a breakpoint ($args)");
	} else {
		my ($name, $line, $owner) = (uc($1), $2, '');
		my $exec = qq|
			BEGIN 
				db.b('$name', $line); 
			END;
		|;

		@res = $self->do($exec)->get_msg;
	}

	return @res;
}

=item continue 

Continue execution until given breakpoints

	my $i_res = $oradb->continue;

=cut

sub continue {
	my $self = shift;

	my $exec = qq#
		BEGIN 
    	db.continue_(dbms_debug.break_next_line);
		END;
	#;

	return $self->do($exec)->get_msg;
}

=item next 

Step over the next line

	my $i_res = $oradb->next;

=cut

sub next {
	my $self = shift;

	my $exec = qq#
		BEGIN 
    	db.continue_(dbms_debug.break_next_line);
		END;
	#;

	return $self->do($exec)->get_msg;
}

=item step

Step into the next statement

	my $i_res = $oradb->step;

=cut

sub step {
	my $self = shift;

	my $exec = qq#
		BEGIN 
    	db.continue_(dbms_debug.break_any_call);
		END;
	#;

	return $self->do($exec)->get_msg;
}

=item return

Return from the current scope

	my $i_res = $oradb->return;

=cut

sub return {
	my $self = shift;

	my $exec = qq#
		BEGIN 
    	db.continue_(dbms_debug.break_any_return);
		END;
	#;

	return $self->do($exec)->get_msg;
}

# =============================================================================
# runtime_info and source listing methods
# =============================================================================

=item runtime

Print runtime_info via dbms_output

	$oradb->runtime;

=cut

sub runtime {
	my $self = shift;
	my $sep = '-' x 80;

	my $exec = qq/
		DECLARE 
			runinfo dbms_debug.runtime_info; 
			rsnt varchar2(40);
		BEGIN 
			-- rsnt := str_for_reason_in_runtime_info(runinfo.reason);
			dbms_output.put_line('');
			dbms_output.put_line('Runtime Info');
    	dbms_output.put_line('  Name:       ' || runinfo.program.name);
			dbms_output.put_line('  Line:          ' || runinfo.line#);
			dbms_output.put_line('  Line:          ' || runinfo.program.line#);
			dbms_output.put_line('  Terminated:    ' || runinfo.terminated);
			-- dbms_output.put_line('  Reason         ' || rsnt);
		END;
	/;

	my @msg = $self->do($exec)->get_msg;

	return @msg >= 1 ? "\n".join("\n", $sep, @msg, $sep)."\n" : '...';
}

=item backtrace 

Print backtrace from runtime info via dbms_output

	$oradb->backtrace();

=cut

sub backtrace {
	my $self = shift;

	my $exec = qq#
		DECLARE 
			runinfo dbms_debug.runtime_info; 
		BEGIN 
			db.print_backtrace(runinfo); 
		END;
	#;

	my @msg = $self->do($exec)->get_msg;

	return @msg >= 1 ? @msg : '...';
}

=item list_source 

Print source 

	$oradb->list_source();

=cut

sub list_source {
	my $self = shift;
	my $args = shift;
	my @res  = ();

	my ($name, $type) = split(/\s+/, $args);
	$name = uc($name); $type = '' unless $type;
	$type = ($type =~ /^PROC/io ? 'PROCEDURE' : $type =~ /^FUNC/io ? 'FUNCTION' : $type =~ /^PACK/io ? 'PACKAGE BODY' : 'PROCEDURE');
	unless ($name =~ /^\w+$/o && $type =~ /^\w+/o) {
		$self->error("list source requires a name($name) and type($type)");
	} else {
		my $exec = qq#
			DECLARE
				xsrc VARCHAR2(4000);
				CURSOR src IS
					SELECT line, text FROM all_source WHERE name = '$name' AND type = '$type' AND type != 'PACKAGE' ORDER BY name, line;
			BEGIN
				FOR rec IN src LOOP
					xsrc := rec.line || ': ' || rec.text;
					dbms_output.put_line(SUBSTR(xsrc, 1, LENGTH(xsrc) -1));
				END LOOP;
			END;
		#;
		@res = $self->do($exec)->get_msg;
	} 

	return @res;
}

=item list_breakpoints

Print breakpoint info

	$oradb->list_breakpoints;

=cut

sub list_breakpoints {
	my $self = shift;
	my $name = uc(shift) || $self->{_name};

	my $exec = qq/
		DECLARE
    	brkpts dbms_debug.breakpoint_table;
    	i      number;
  	BEGIN	
			dbms_debug.show_breakpoints(brkpts); 
			i := brkpts.first();
			dbms_output.put_line('breakpoints: ');
			while i is not null loop
				dbms_output.put_line('  ' || i || ': ' || brkpts(i).name || ' (' || brkpts(i).line# ||')');
				i := brkpts.next(i);
			end loop;
		END;
	/;

	return $self->do($exec)->get_msg;
}

=rjsf
		vanilla version
		DECLARE 
			runinfo dbms_debug.runtime_info; 
      i_before number := 1;
      i_after  number := 99;
      i_width  number := 80;
		BEGIN 
      db.print_runtime_info_with_source(runinfo, i_before, i_after, i_width);
		END;
=cut

=item history

Display the command history

	print $o_oradb->history;	

=cut

sub history {
	my $self = shift;

	my @hist = map { "$_: $HISTORY{$_}\n" } sort { $a <=> $b } grep(!/\!/, keys %HISTORY);

	return @hist;
}

=item rerun

Rerun a command from the history list

	$o_oradb->rerun($histno);

=cut

sub rerun {
	my $self = shift;
	my $hist = shift || 0;

	if ($hist =~ /!/o) {
		($hist) = reverse sort { $a <=> $b } keys %HISTORY;
	}
	unless ($HISTORY{$hist} =~ /^(\S+)\s(.*)$/o) {
		$self->error("invalid history key($hist) - try using 'H'");
	} else {
		my ($cmd, $args) = ($1, $2);
		$self->parse($cmd, $args); # + process
	}

	return ();
}

# =============================================================================
# check and ping methods
# =============================================================================

=item self_check 

Check the connections (fails otherwise)

	my $i_ok = $oradb->self_check();

=cut

sub self_check {
	my $self = shift;

	my $exec = qq#
		BEGIN 
			dbms_debug.self_check(10); 
		END;
	#;

	return $self->do($exec) ? 1 : 0;
}

=item probe_version 

Log the Probe version

	print $oradb->probe_version;

=cut

sub probe_version {
	my $self = shift;

	my $exec = qq#
		DECLARE 
			i_maj BINARY_INTEGER; 
			i_min BINARY_INTEGER; 
		BEGIN 
			dbms_debug.probe_version(i_maj, i_min); 
			dbms_output.put_line('probe version: ' || i_maj || '.' || i_min); 
		END;
		#;

	return $self->do($exec)->get_msg;
}

=item ping 

Ping the target process (gives an ORA-error if no target)

	my $i_ok = $oradb->ping; # 9.2

=cut

sub ping {
	my $self = shift;

	my $exec = qq#
		BEGIN 
			dbms_debug.ping;
			dbms_output.put_line('pinged');
		END;
		#;

	return $self->do($exec)->get_msg;
}

=item is_running 

Check the target is still running - ???

	my $i_ok = $oradb->is_running; # 9.2

=cut

sub is_running {
	my $self = shift;

	my $exec = qq#
		BEGIN 
			IF dbms_debug.target_program_running THEN
				dbms_output.put_line('target is currently running');
			ELSE 
				dbms_output.put_line('target is not currently running');
			END IF;
		END;
		#;

	return $self->do($exec)->get_msg;
}

# =============================================================================
# get and put msg methods
# =============================================================================

=item plsql_errstr

Get PL/SQL error string

	$o_debug->plsql_errstr;

=cut

sub plsql_errstr {
	my $self  = shift;

	return $self->dbh->func('plsql_errstr');
}

=item put_msg 

Put debug message info

	$o_debug->put_msg($msg);

=cut

sub put_msg {
	my $self  = shift;

	return $self->dbh->func(@_, 'dbms_output_put');
}

=item get_msg 

Get debug message info

	print $o_debug->get_msg;

=cut

sub get_msg {
	my $self  = shift;

	my @msg = (); {
		no warnings;
		@msg = grep(/./, $self->dbh->func('dbms_output_get'));
	}

	return (@msg >= 1 ? join("\n", @msg)."\n" : "\n"); 
}

=item get_val

Get the value of a variable

	my $val = $o_debug->get_val($varname);

=cut

sub get_val {
	my $self = shift;
	my $varn = shift;

	my $exec = qq#
		DECLARE
			buff   VARCHAR2(500);
			xret   BINARY_INTEGER;
		BEGIN
			xret := dbms_debug.get_value($varn, 0, buff, NULL);
			dbms_output.put_line('value: ' || buff);
		END;
	#;
	
	my @res = $self->do($exec)->get_msg;

	return @res;
}

=item audit 

Get auditing info

	my ($audsid) = $o_debug->audit;

=cut

sub audit {
	my $self  = shift;

	my $sql   = qq#
		SELECT audsid || '-' || sid || '-' || osuser || '-' || username FROM v\$session WHERE audsid = userenv('SESSIONID')
	#;

	my ($res) = $self->dbh->selectrow_array($sql);

	$self->error("failed to audit: $sql $DBI::errstr") unless $res;

	return $res." $$";
}

# =============================================================================
# error, log and cleanup methods
# =============================================================================

=item log 

Log handler (currently just prints to STDOUT)

	$o_debug->log("this");

=cut

sub log {
	my $self = shift;
	my $msgs = join(' ', @_);
	print STDOUT '          '."$msgs\n";
	return $msgs;
}

=item quit

Quit the debugger

	$o_oradb->quit;

=cut

sub quit {
	my $self = shift;
	print "oradb detaching\n";
	# $self->detach;
	exit;
}

=item error 

Error handler

=cut

sub error {
	my $self = shift;
	# $DB::errstr;
	my $errs = join(' ', 'Error:', @_).($DB::errstr || '')."\n";
	carp($errs);
	return $errs;
}

=item fatal

Fatal error handler

=cut

sub fatal {
	my $self = shift;
	croak(ref($self).' FATAL ERROR: ', @_);
}

=item detach

Tell the target session to detach itself

	$o_debug->detach;

=cut

sub detach {
	my $self = shift;

	my $exec = qq#
		BEGIN 
			dbms_debug.detach_session; 
		END;
	#;
	$self->do->($exec)->get_msg;

	# autonomous transaction
	# $self->do->('DELETE FROM '.$self->{_config}{table});
	# $self->do->('COMMIT');
}

sub DESTROY {
	my $self = shift;
	my $dbh  = $self->{_dbh}->{$$};
	if (ref($dbh)) {
		$dbh->disconnect;
	}
}

1;

=back

=head1 SEE ALSO

DBD::Oracle

perldebug

=head1 AUTHOR

Richard Foley, E<lt>Oracle_Debug@rfi.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Richard Foley

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

