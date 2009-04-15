use warnings;
use strict;
use Test::More tests => 22;
BEGIN { use_ok('Net::ParSCP') };

#########################

SKIP: {
  skip("Developer test", 21) unless ($ENV{DEVELOPER} && -x "script/parpush" && ($^O =~ /nux$/));

     my $output = `script/parpush -v 'orion:.bashrc beowulf:.bashrc' europa:/tmp/bashrc.@# 2>&1`;
     like($output, qr{scp\s+beowulf:.bashrc\s+europa:.tmp.bashrc.beowulf}, 'using macro for source machine: remote target');
     like($output, qr{scp\s+orion:.bashrc europa:/tmp/bashrc.orion}, 'using macro for source machine: remote target');
     ok(!$?, 'macro for source machine: status 0');

     $output = `script/parpush -l =europa -v MANIFEST  beo-europa:/tmp/@# 2>&1`;
     ok(!$?, 'macro from local to remote: status 0');
     like($output, qr{scp  MANIFEST beowulf:/tmp/europa}, 'using -l =europa and macro from local machine: remote target');
     like($output, qr{scp  MANIFEST orion:/tmp/europa}, 'using -l  =europa and macro from local machine: remote target');

     $output = `script/parpush -v MANIFEST  beo-europa:/tmp/@# 2>&1`;
     ok(!$?, 'macro from local to remote: status 0');
     like($output, qr{scp  MANIFEST beowulf:/tmp/localhost}, 'using macro from local machine: remote target');
     like($output, qr{scp  MANIFEST orion:/tmp/localhost}, 'using macro from local machine: remote target');

     $output = `script/parpush -l localhost=orionbashrc -v orion:.bashrc :/tmp/@= 2>&1`;
     ok(!$?, 'macro target from remote to local: status 0');
     like($output, qr{scp -r orion:.bashrc /tmp/orionbashrc}, 'using -l localhost=orionbashrc with target macro to local machine');

     $output = `script/parpush -l orion=orionbashrc -v orion:.bashrc :/tmp/@# 2>&1`;
     ok(!$?, 'macro source with -l from remote to local: status 0');
     like($output, qr{Executing system command:\s+scp -r orion:.bashrc /tmp/orionbashrc}, 'using -l orion=orionbashrc with source macro to local machine');

     $output = `script/parpush -l orion=ORION -l beowulf=BEO -v 'orion:.bashrc beowulf:.bashrc' europa:/tmp/bashrc.@# 2>&1`;
     ok(!$?, 'macro for source with 2 -l options: status 0');
     like($output, qr{scp  beowulf:.bashrc europa:/tmp/bashrc.BEO}, 'macro for source with 2 -l options: correct command 1');
     like($output, qr{scp  orion:.bashrc europa:/tmp/bashrc.ORION}, 'macro for source with 2 -l options: correct command 2');
     #ok(-e '/tmp/.bashrc', 'remote file transferred');
     #ok(-x '/tmp/tutu', 'remote dir transferred');

     $output = `script/parpush -h`;
     ok(!$?, 'help: status 0');
     like($output, qr{Name:\s+parpush - Secure transfer of files via SSH},'help:Name');
     like($output, qr{Usage:\s+parpush}, 'help: Usage');
     like($output, qr{Options:\s+--configfile file :}, 'help:Options');
     like($output, qr{--xterm}, 'help: xterm option');
}



