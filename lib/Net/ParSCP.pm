package Net::ParSCP;
use strict;
use warnings;

use Set::Scalar;
use IO::Select;
#use Sys::Hostname;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
  parpush
  exec_cssh
  help 
  version
  usage 
  $VERBOSE
);

our $VERSION = '0.07';
our $VERBOSE = 0;

# Create methods for each defined machine or cluster
sub create_machine_alias {
  my %cluster = @_;

  my %method; # keys: machine addresses. Values: the unique name of the associated method

  no strict 'refs';
  for my $m (keys(%cluster)) {
    my $name  = uniquename($m);
    *{__PACKAGE__.'::'.$name} = sub { 
      $cluster{$m} 
     };
    $method{$m} = $name;
  }

  return \%method;
}

sub read_configfile {
  my $configfile = $_[0];


  if (-r $configfile) {
    open(my $f, $configfile);
    my @desc = <$f>;
    chomp(@desc);
    return @desc;
  }

  # Configuration file not found. Try with ~/.csshrc of cssh
  $configfile = $_[0] = "$ENV{HOME}/.csshrc";
  if (-r $configfile) {
    open(my $f, $configfile);

    # We are interested in lines matching 'option = values'
    my @desc = grep { m{^\s*(\S+)\s*=\s*(.*)\s*} } <$f>;
    close($f);
    chomp(@desc);

    my %config = map { m{^\s*(\S+)\s*=\s*(.*)\s*} } @desc;

    # Get the clusters. It starts 'cluster = ... '
    my $regexp = $config{clusters};

    # create regexp (^beo\s*=)|(^be\s*=)
    $regexp =~ s/\s*(\S+)\s*/(^$1\\s*=)|/g;
    $regexp =~ s/[|]\s*$//;

    # Select the lines that correspond to clusters
    return grep { m{$regexp}x } @desc;
  }

  usage('Error. Configuration file not found!') unless -r $configfile;
}

############################################################
sub parse_configfile {
  my $configfile = $_[0];
  my %cluster;

  my @desc = read_configfile($_[0]);

  for (@desc) {
    next if /^\s*(#.*)?$/;

    my ($cluster, $members) = split /\s*=\s*/;
    die "Error in configuration file $configfile invalid cluster name $cluster" unless $cluster =~ /^[\w.]+$/;

    my @members = split /\s+/, $members;

    for my $m (@members) {
      die "Error in configuration file $configfile invalid name $m" unless $m =~ /^[\@\w.]+$/;
      $cluster{$m} = Set::Scalar->new($m) unless exists $cluster{$m};
    }
    $cluster{$cluster} = Set::Scalar->new(@members);
  }

  # keys: machine and cluster names; values: name of the associated method 
  my $method = create_machine_alias(%cluster); 

  return (\%cluster, $method);
}

############################################################
sub version {
  my $errmsg = shift;

  print "$VERSION\n";
  exit(0);
}


############################################################
sub usage {
  my $errmsg = shift;

  warn "$errmsg\n";
  help();
}

sub help {
  warn << "HELPMSG";
Usage:
  $0 [ options ] sourcefile clusterexp1:/path1 clusterexp2:/path2 ...

Cluster expressions like:

  $0 file 'cluster1-machine2:/tmp'
  $0 file 'cluster1-machine2:/tmp/file_@=.txt'
  $0 -s '-v' dir/  cluster1+cluster2:/tmp cluster3:/scratch/

are accepted. The macro C<@=> inside a path expands to the name of the machine.
To transfer several files, protect them with quotes:

  $0 'file1 machine3:file2' cluster1%cluster2:  

it transfer file1 in the local machine and file2 in machine3 
to the machines in the symmetric difference of clusters cluster1 
and cluster2.

Valid options:

 --configfile file : Configuration file

 --scpoptions      : A string with the options for scp.
                     The default is no options and '-r' if 
                     sourcefile is adirectory

 --program         : A string with the name of the program to use for secure copy
                     by default is 'scp'

 --processes       : Maximum number of concurrent processes

 --verbose

 --xterm           : runs cssh to the target machines

 --help            : this help

 --Version

HELPMSG
  exit(1);
}

############################################################
{
  my $pc = 0;

  sub uniquename {
    my $m = shift;

    $m =~ s/\W/_/g;
    $pc++;
    return "_$pc"."_$m";
  }
}

sub exec_cssh {
  my @machines = @_;

  my $csshcommand  = 'cssh ';
  $csshcommand .= "$_ " for @machines;
  warn "Executing system command:\n\t$csshcommand\n" if $VERBOSE;
  my $pid;
  exec("$csshcommand &");
  die "Can't execute cssh\n";
}

sub warnundefined {
  my ($configfile, @errors) = @_;

  local $" = ", ";
  my $prefix = (@errors > 1) ?
      "Machine identifiers (@errors) do"
    : "Machine identifier (@errors) does";
  warn "$prefix not correspond to any cluster or machine defined in ".
       " cluster description file '$configfile'.\n";
}

sub non_declared_machines {
  my $configfile = shift;
  my $clusterexp = shift;
  my %cluster = @_;

  my @unknown;
  my @clusterexp = $clusterexp =~ m{([a-zA-Z_][\w.\@]*)}g;
  if (@unknown = grep { !exists($cluster{$_}) } @clusterexp) {
    warnundefined($configfile, @unknown) if $VERBOSE;
  }
  return @unknown;
}

sub wait_for_answers {
  my $readset = shift;
  my %proc = %{shift()};

  my $np = keys %proc; # number of processes
  my %output;
  my @ready;

  my %result;
  for (my $count = 0; $count < $np; ) {
    push @ready, $readset->can_read unless @ready;
    my $handle = shift @ready;

    my $name = $proc{0+$handle};

    unless (defined($name) && $name) {
      warn "Error. Received message from unknown handle\n";
      $name = 'unknown';
    }

    my $partial = '';
    my $numBytesRead;
    $numBytesRead = sysread($handle,  $partial, 65535, length($partial));

    $output{$name} .= $partial;

    if (defined($numBytesRead) && !$numBytesRead) {
      # eof
      if ($VERBOSE) {
        print "$name output:\n";
        $output{$name} =~ s/^/$name:/gm if length($output{$name});
        print "$output{$name}\n";
      }
      $readset->remove($handle);
      $count ++;
      if (close($handle)) {
        $result{$name} = 1;
      }
      else {
        warn $! ? "Error closing scp to $name $!\n" 
                : "Exit status $? from scp to $name\n";
        print "$output{$name}\n" unless $VERBOSE;
        $result{$name} = 0;
      }
    }
  } 
  return \%result;
}

sub spawn_secure_copies {
  my %arg = @_;
  my $readset = $arg{readset};
  my $configfile = $arg{configfile};
  my $destination = $arg{destination};
  my @destination = ref($destination)? @$destination : $destination;
  my %cluster = %{$arg{cluster}};
  my %method = %{$arg{method}};
  my $scp = $arg{scp} || 'scp';
  my $scpoptions = $arg{scpoptions} || '';
  my $sourcefile = $arg{sourcefile};

  # hash source: keys: source machines. values: lists of source paths for that machine
  my (%pid, %proc, %source);

  # @# stands for the source machine: decompose the transfer, one per source machine
  if ("@destination" =~ /@#/) { 
    # find out what source machines are involved 
    my $nowhitenocolons = '(?:[^\s:]|\\\s)+'; # escaped spaces are allowed
    my @externalmachines = $sourcefile =~ /($nowhitenocolons):($nowhitenocolons)/g;
    my @localpaths = $sourcefile =~ /(?:^|\s) # begin or space
                                     ($nowhitenocolons)
                                     (?:\s|$) # end or space
                                    /xg;
    
    @{$source{''}} = [ @localpaths ] if @localpaths; # '' is the local machine
    while (my ($machine, $path) = splice(@externalmachines, 0, 2)) {
      if (exists $source{$machine} ) {
        push @{$source{$machine}}, $path;
      }
      else {
        $source{$machine} = [ $path ]
      }
    }
  }

  for (@destination) {

    my ($clusterexp, $path);
    unless (/^([^:]*):([^:]*)$/) {
      warn "Error. Destination '$_' must have no more than one colon (:). Skipping transfer.\n";
      next;
    }

    if ($1) {  # There is a target machine
      ($clusterexp, $path) = split /\s*:\s*/;
    }
    else { # No target cluster: destiny is the local machine
      ($clusterexp, $path) = ('', $2);
      $scpoptions .= '-r';

      # TODO: decompose if @#
      $pid{localhost} = open(my $p, "$scp $scpoptions $sourcefile $path 2>&1 |");
      next;
    }

    # Autodeclare unknown machine identifiers
    my @unknown = non_declared_machines($configfile, $clusterexp, %cluster);
    my %unknown = map { $_ => Set::Scalar->new($_)} @unknown;
    %cluster = (%cluster, %unknown); # union
    %method = (%method, %{create_machine_alias(%unknown)});

    $clusterexp =~ s/(\w[\w.\@]*)/$method{$1}()/g;
    my $set = eval $clusterexp;

    unless (defined($set) && ref($set) && $set->isa('Set::Scalar')) {
      $clusterexp =~ s/_\d+_//g;
      $clusterexp =~ s/[()]//g;
      warn "Error. Expression '$clusterexp' has errors. Skipping.\n";
      next;
    }

    for my $m ($set->members) {
      # @= is a macro and means "the name of the destiny machine"
      my $cp = $path;
      $cp =~ s/@=/$m/g;

      if ($cp =~ /@#/ && %source) {
        # @# stands for source machine: decompose transfer
        for my $sm (keys %source) {
          my $sf = $sm? "$sm:@{$source{$sm}}" : "@{$source{$sm}}"; # $sm: source machine
          my $fp = $cp;                   # $fp: path customized for this source machine
          $fp =~ s/@#/$sm/g;
          warn "Executing system command:\n\t$scp $scpoptions $sf $m:$fp\n" if $VERBOSE;
          my $pid;
          $pid{$m} = $pid = open(my $p, "$scp $scpoptions $sf $m:$fp 2>&1 |");
          warn "Can't execute scp $scpoptions $sourcefile $m:$fp", next unless defined($pid);

          $proc{0+$p} = $m;
          $readset->add($p);
        }
      }
      else {
        warn "Executing system command:\n\t$scp $scpoptions $sourcefile $m:$cp\n" if $VERBOSE;

        my $pid;
        $pid{$m} = $pid = open(my $p, "$scp $scpoptions $sourcefile $m:$cp 2>&1 |");
        warn "Can't execute scp $scpoptions $sourcefile $m:$cp", next unless defined($pid);

        $proc{0+$p} = $m;
        $readset->add($p);
      }
    }
  }

  return (\%pid, \%proc);
}

sub parpush {
  my %arg = @_;

  my ($cluster, $method) = parse_configfile($arg{configfile});

  my $readset = IO::Select->new();

  # $proc is a hash ref. keys: memory address of some IO stream. 
  # Values the name of the assoc. machine. 
  # $pid is a hash ref
  # keys: machine names. Values: process Ids
  my ($pid, $proc) = spawn_secure_copies(
    readset => $readset, 
    cluster => $cluster,
    method => $method,
    %arg,
  );

  my $okh = wait_for_answers($readset, $proc);

  return wantarray? ($okh, $pid) : $okh;
}

1;

__END__
