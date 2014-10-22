# $Id: oradb.t,v 1.4 2003/05/16 13:29:36 oradb Exp $

use Data::Dumper;
use Test::More tests => 12;

# 1
BEGIN { use_ok('Oracle::Debug') };

# 2
my %conf = (
	'datasrc' => 'dbi:Oracle:sid=RFI;host=localhost;port=1521', 
	'user'		=> 'ubsw',
	'pass'		=> 'ubsw',
	'logfile'	=> './oradb.log',
	'comms'	  => './oradb.com',
	'params'  => { AutoCommit => 1 },
);
my $odb = Oracle::Debug->new(\%conf);
ok(ref($odb), 'new');

# 3
my $dbh = $odb->dbh;
ok($dbh->isa('DBI::db'), 'dbi') or diag('dbi: '.Dumper($dbh));

# 4
my ($err) = $odb->error('xxx');
ok($err eq 'Error: xxx', 'error') or diag("dodgy error: $err");

# 5
my ($res) = $odb->getarow('SELECT sysdate FROM dual');
ok($res =~ /^\d\d\-\w\w\w-\d\d$/o, 'getarow') or diag("failed to getarow(sysdate)");

# 6
my $checked = $odb->self_check;
ok($checked, 'self_check') or diag('self_check: '.Dumper($checked));

# 7
my $pv = $odb->probe_version;
ok($pv =~ /probe\s+version:\s+\d+\.\d+/, 'probe_version') or diag('probe: '.Dumper($pv));

# 8
# put_msg
my ($pmsg) = $odb->put_msg("rjsf_$$".'_oradb');
ok($pmsg eq 1, 'put_msg') or diag('put: '.Dumper($pmsg));

# 9
# get_msg
my ($gmsg) = $odb->get_msg;
ok($gmsg =~ /rjsf_$$_oradb/, 'get_msg') or diag('get: '.Dumper($gmsg));

# 10 
# is_running 
my ($irun) = $odb->is_running;
ok($irun =~ /running/, 'is_running') or diag('is_running: '.Dumper($irun));

# 11
# help 
my ($help) = $odb->help;
ok($help =~ /oradb\s*help/, 'help') or diag('help: '.Dumper($help));

# 12 
my $audit = $odb->audit;
ok($audit =~ /\w+\s+$$/, 'audit') or diag('audit: '.Dumper($audit));


