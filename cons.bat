@rem = '--*-PERL-*--';
@rem = '
@echo off
rem setlocal
set ARGS=
:loop
if .%1==. goto endloop
set ARGS=%ARGS% %1
shift
goto loop
:endloop
rem ***** This assumes PERL is in the PATH *****
rem $Id: //depot/proj/cons/src/cons.bat.proto#1$
perl.exe -S cons.bat %ARGS%
goto endofperl
@rem ';

#!/usr/bin/env perl

# Cons: A Software Construction Tool.
# Bob Sidebotham (rns@fore.com), FORE Systems, 1996.
# $Id: //depot/proj/cons/src/cons#7 $

$cons_history = q(
Modification History:

    Created by Bob Sidebotham <rns@fore.com>
    Cons Win32 Port by Chriss Stephens <chriss@fore.com>
    Win32 port bugfixes by Rajesh Vaidheeswarran <rv@fore.com>
    Win32 bugfixes by Jochen Schwarze <schwarze@isa.de>
    1.3 Merge for Win32 and UNIX by Rajesh Vaidheeswarran <rv@fore.com>
    Minimal Shared lib support by Gary Oberbrunner <garyo@genarts.com>
    1.4 Caching, signatures changes, QuickScan, cleanup <rns@fore.com>
    CPPPATH and open file handle fix for Win32 - <Anthony_Kolarik@pilotsw.com>
    PATHS as arrays <rns@fore.com>
    Default targets can be specified Steven Knight <knight@baldmt.com>
    Local Help Functionality (cons flag -h) - rv@fore.com
    Repository method, -R flag, and related methods - <knight@baldmt.com>

);

$ver_num = 1.5;
$ver_rev = "";
$version = "This is Cons $ver_num$ver_rev " .
            '($Id: //depot/proj/cons/src/cons#7 $)'. "\n";

# Copyright (c) 1996-1998 FORE Systems, Inc.	 All rights reserved.

# Permission to use, copy, modify and distribute this software and
# its documentation for any purpose and without fee is hereby granted,
# provided that the above copyright notice appear in all copies and
# that both that copyright notice and this permission notice appear
# in supporting documentation, and that the name of FORE Systems, Inc.
# ("FORE Systems") not be used in advertising or publicity pertaining to
# distribution of the software without specific, written prior permission.

# FORE SYSTEMS DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
# INCLUDING ANY WARRANTIES REGARDING INTELLECTUAL PROPERTY RIGHTS AND
# ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE.  IN NO EVENT SHALL FORE SYSTEMS BE LIABLE FOR ANY SPECIAL,
# INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING
# FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
# NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION
# WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

require 5.002;
use integer;
use File::Copy;

#------------------------------------------------------------------
# Determine if running on win32 platform - either Windows NT or 95
#------------------------------------------------------------------

BEGIN {
    $PATH_SEPARATOR = ':';
    $FLAG_CHARACTER = '-';
    $LIB_FLAG_PREFIX = '-L';
    eval("require Win32");
    if (!$@) {
	$_WIN32 = 1;
	$PATH_SEPARATOR = ';';
	$FLAG_CHARACTER = '/';
	$LIB_FLAG_PREFIX = '/LIBPATH:';
    }
}

# Flush stdout each time.
$| = 1;

# Seed random number generator.
srand(time . $$); # this works better than time ^ $$ in perlfunc manpage.

$usage = q(
Usage: cons <arguments>

Arguments can be any of the following, in any order:

  <targets>	Build the specified targets. If <target> is a directory
		recursively build everything within that directory.

  +<pattern>	Limit the cons scripts considered to just those that
		match <pattern>. Multiple + arguments are accepted.

  <name>=<val>	Sets <name> to value <val> in the ARG hash passed to the
		top-level Construct file.

  -cc           Show command that would have been executed, when
	        retrieving from cache. No indication that the file
	        has been retrieved is given; this is useful for 
	        generating build logs that can be compared with
	        real build logs.

  -cd           Disable all caching. Do not retrieve from cache nor
	        flush to cache.

  -cr           Build dependencies in random order. This is useful when
	        building multiple similar trees with caching enabled.

  -cs           Synchronize existing build targets that are found to be
	        up-to-date with cache. This is useful if caching has
	        been disabled with -cc or just recently enabled with
	        UseCache.

  -d            Enable dependency debugging.

  -f <file>	Use the specified file instead of "Construct" (but first
		change to containing directory of <file>). 

  -h            Show a help message local to the current build if 
                one such is defined,  and exit.

  -o <file>	Read override file <file>.
		
  -k		Keep going as far as possible after errors.

  -m            Show cons modification history and exit.

  -p		Show construction products in specified trees.
  -pa		Show construction products and associated actions.
  -pw		Show products and where they are defined.

  -wf <file>    Write all filenames considered into <file>.

  -r		Remove construction products associated with <targets>

  -R <repos>	Search for files in <repos>.  Multiple -R <repos>
		directories are searched in the order specified.

  -v		Show cons version and continue processing.
  -V            Show cons version and exit.
  -x		Show this message and exit.

   Please report any bugs/fixes/suggestions through the
   cons-discuss@eng.fore.com mailing list. To subscribe, send mail to
   cons-discuss-request@eng.fore.com with body 'subscribe'.

   The Official cons site is: http://www.dsmit.com/cons

);

# Simplify program name, if it is a path.
$0 =~ s#.*/##;

# Default parameters.
$param::topfile = 'Construct'; # Top-level construction file.
$param::install = 1;	       # Show installations
$param::build = 1;	       # Build targets
$param::show = 1;	       # Show building of targets.
$param::sigpro = 'md5';        # Signature protocol.
$param::depfile = '';          # Write all deps out to this file
$param::salt = undef;          # Salt derived file signatures with this.
$param::rep_sig_times_ok = 1;  # Repository .consign times are in sync w/files.

# Display a command while executing or otherwise. This
# should be called by command builder action methods.
sub showcom {
    print($indent . $_[0] . "\n");
}

# Default environment.
@param::defaults = (
     'CC'	    => 'cc',
     'CFLAGS'	    => '',
     'CCCOM'	    => '%CC %CFLAGS %_IFLAGS -c %< -o %>',
     'LINK'	    => '%CC',		    
     'LINKCOM'	    => '%LINK %LDFLAGS -o %> %< %_LDIRS %LIBS',
     'LINKMODULECOM'=> '%LD -r -o %> %<',		    
     'AR'	    => 'ar',
     'ARCOM'	    => "%AR %ARFLAGS %> %<\n%RANLIB %>",
     'ARFLAGS'	    => 'r', # rs?		    
     'RANLIB'	    => 'ranlib',		    
     'AS'	    => 'as',
     'ASFLAGS'	    => '',
     'ASCOM'	    => '%AS %ASFLAGS %< -o %>',
     'LD'	    => 'ld',	    
     'LDFLAGS'	    => '',
     'PREFLIB'      => 'lib',
     'SUFLIB'	    => '.a',
     'SUFLIBS'      => '.so:.a',
     'SUFMAP'       => {
	 '.c'  => 'build::command::cc',
	 '.C'  => 'build::command::cc',
	 '.s'  => 'build::command::cc',
	 '.S'  => 'build::command::cc',
	 '.cc' => 'build::command::cc',
	 '.cxx'=> 'build::command::cc',
	 '.cpp'=> 'build::command::cc',
     },
     'SUFOBJ'	    => '.o',
     'ENV'	    => { 'PATH' => '/bin:/usr/bin' },
);

if ($main::_WIN32) {
  # reset PREFLIB;
  $param::defaults->{'PREFLIB'} = '';
}

# Handle command line arguments.
while (@ARGV) {
    $_ = shift(@ARGV);
    &option, next			if s/^-//;
    push (@param::include, $_), next	if s/^\+//;
    &equate, next			if /=/;
    push (@targets, $_), next;
}

sub option {
    if ($_ eq 'm') {
	print($version, $cons_history), exit(0);
    } elsif ($_ eq 'v') {
	print($version);
    } elsif ($_ eq 'V') {
	print($version), exit(0);
    } elsif ($_ eq 'o') {
	$param::overfile = shift(@ARGV);
	die("$0: -o option requires a filename argument.\n") if !$param::overfile;
    } elsif ($_ eq 'f') {
	$param::topfile = shift(@ARGV);
	die("$0: -f option requires a filename argument.\n") if !$param::topfile;
    } elsif ($_ eq 'wf') {
       $param::depfile = shift(@ARGV);
       die("$0: -wf option requires a filename argument.\n") if !$param::depfile;
    } elsif ($_ eq 'k') {
	$param::kflag = 1;
    } elsif ($_ eq 'p') {
	$param::pflag = 1;
	$param::build = 0;
    } elsif ($_ eq 'pa') {
	$param::pflag = $param::aflag = 1;
	$param::build = 0;
	$indent = "... ";
    } elsif ($_ eq 'pw') {
	$param::pflag = $param::wflag = 1;
	$param::build = 0;
    } elsif ($_ eq 'r') {
	$param::rflag = 1;
	$param::build = 0;
    } elsif ($_ eq 'h') {
	$param::localhelp =1;
    } elsif ($_ eq 'x') {
	print($usage);
	exit 0;
    } elsif ($_ eq 'd') {
	$param::depends = 1;
    } elsif ($_ eq 'cc') {
	$param::cachecom = 1;
    } elsif ($_ eq 'cd') {
	$param::cachedisable = 1;
    } elsif ($_ eq 'cr') {
	$param::random = 1;
    } elsif ($_ eq 'cs') {
	$param::cachesync = 1;
    } elsif ($_ eq 'R') {
	my($repository) = shift(@ARGV);
        die("$0: -R option requires a repository argument.\n") if !$repository;
	script::Repository($repository);
    } else {
	die qq($0: unrecognized option "-$_". Use -x for a usage message.\n) if $_;
    }
}	

# Process an equate argument (var=val).
sub equate {
    my($var, $val) = /([^=]*)=(.*)/;
    $script::ARG{$var} = $val;
}

# Define file signature protocol.
sig->select($param::sigpro);

# Cleanup after an interrupt.
$SIG{HUP} = $SIG{INT} = $SIG{QUIT} = $SIG{TERM} = sub { 
    $SIG{PIPE} = $SIG{HUP} = $SIG{INT} = $SIG{QUIT} = $SIG{TERM} = 'IGNORE';
    warn("\n$0: killed\n");
    # Call this first, to make sure that this processing
    # occurs even if a child process does not die (and we
    # hang on the wait).
    sig::hash::END();
    wait();
    exit(1);
};

# Cleanup after a broken pipe (someone piped our stdout?)
$SIG{PIPE} = sub { 
    $SIG{PIPE} = $SIG{HUP} = $SIG{INT} = $SIG{QUIT} = $SIG{TERM} = 'IGNORE';
    warn("\n$0: broken pipe\n");
    sig::hash::END();
    wait();
    exit(1);
};

if ($param::depfile) {
  open (main::DEPFILE, ">".$param::depfile) ||
    die ("$0: couldn't open $param::depfile ($!)\n");
}

# If the supplied top-level Conscript file is not in the
# current directory, then change to that directory.
if ($param::topfile =~ s#(.*)/##) {
    chdir($1) || die("$0: couldn't change to directory $1 ($!)\n");
}

# Now handle override file.
package override;
if ($param::overfile) {
    my($ov) = $param::overfile;
    die qq($0: can't read override file "$ov" ($!)\n) if ! -f $ov; #'
    do $ov;
    if ($@) {
	chop($@);
	die qq($0: errors in override file "$ov" ($@)\n);
    }
}

# Provide this to user to setup override patterns.
sub Override {
    my($re, @env) = @_;
    return if $overrides{$re}; # if identical, first will win.
    $param::overrides = 1;
    $param::overrides{$re} = \@env;
    push(@param::overrides, $re);
}

package main;
# Check script inclusion regexps
for $re (@param::include) {
    if (! defined eval {"" =~ /$re/}) {
	my($err) = $@;
	$err =~ s/in regexp at .*$//;
	die("$0: error in regexp $err");
    }
}

# Read the top-level construct file and its included scripts.
doscripts($param::topfile);

# Status priorities. This let's us aggregate status for directories and print
# an appropriate message (at the top-level).
%priority =
    ('none' => 1, 'handled' => 2, 'built' => 3, 'unknown' => 4, 'errors' => 5);

# If no targets were specified, supply default targets (if any).
@targets = @param::default_targets if ! @targets;

# Build the supplied target patterns.
for $tgt (map($dir::top->lookup($_), @targets)) {
    my($status) = buildtarget($tgt);
    if ($status ne 'built') {
	my($path) = $tgt->path;
	if ($status eq "errors") {
	    print qq($0: "$path" not remade because of errors.\n);
	    $errors++;
	} elsif ($status eq "handled") {
	    print qq($0: "$path" is up-to-date.\n);
	} elsif ($status eq "unknown") {
	    # cons error already reported.
	    $errors++;
	} elsif ($status eq "none") {
	    #???
	} else {
	    print qq($0: don't know how to construct "$path".\n"); #'
	    $errors++;
	}
    }
}

exit 0 + ($errors != 0);

# Build the supplied target directory or files. Return aggregated status.
sub buildtarget {
    my($tgt) = @_;
    if (ref($tgt) eq "dir") {
	my($result) = "none";
	my($priority) = $priority{$result};
	if (exists $tgt->{member}) {
	    my($members) = $tgt->{member};
	    for $entry (sort keys %$members) {
		next if $entry =~ /^\./; # ignore hidden files
		my($tgt) = $members->{$entry};
		next if ref($tgt) eq "file" && !exists($tgt->{builder});
		my($stat) = buildtarget($members->{$entry});
		my($pri) = $priority{$stat};
		if ($pri > $priority) {
		    $priority = $pri;
		    $result = $stat;
		}
	    }
	}
	return $result;
    }	
    if ($param::build) {
	return build $tgt;
    } elsif ($param::depends) {
	my($path) = $tgt->path;
	if ($tgt->{builder}) {
	    my(@dep) = (@{$tgt->{dep}}, @{$tgt->{sources}});
	    my($dep) = join(' ',map($_->path, @dep));
	    print("$path: $dep\n");
	} else {
	    print("$path: not a derived file\n");
	}
    } elsif ($param::pflag || $param::wflag || $param::aflag) {
	if ($tgt->{builder}) {
	    if ($param::wflag) {
		print qq(${\$tgt->path}: $tgt->{script}\n);
	    } elsif ($param::pflag) {
		print qq(${\$tgt->path}:\n) if $param::aflag;
		print qq(${\$tgt->path}\n) if !$param::aflag;
	    }
	    if ($param::aflag) {
		$tgt->{builder}->action($tgt);
	    }
	}
    } elsif ($param::rflag && $tgt->{builder}) {
	my($path) = $tgt->path;
	if (-f $path) {
	    if (unlink($path)) {
		print("Removed $path\n");
	    } else {
		warn("$0: couldn't remove $path\n");
	    }
	}
    }

    return "none";
}

# Support for "building" scripts, importing and exporting variables.
# With the expection of the top-level routine here (invoked from the
# main package by cons), these are all invoked by user scripts.
package script;

# This is called from main to interpret/run the top-level Construct
# file, passed in as the single argument.
sub main::doscripts {
    my($script) = @_;
    Build($script);
    # Now set up the includes/excludes (after the Construct file is read).
    $param::include = join('|', @param::include);

    my(@scripts) = pop(@priv::scripts);
    while ($priv::self = shift(@scripts)) {
	my($path) = $priv::self->{script}->rsrcpath;
	$dir::cwd = $priv::self->{script}->{dir};
	if (-f $path) {
	    do $path;
	    if ($@) {
		chop($@);
		print qq($0: error in file "$path" ($@)\n);
		$run::errors++;
	    } else {
		# Only process subsidiary scripts if no errors in parent.
		unshift(@scripts, @priv::scripts);
	    }
	    undef @priv::scripts;
	} else {
	    warn qq(Ignoring missing script "$path".\n);
	}

# reset "a-zA-Z";# Reset here, to give Construct chance at globals (i.e. %ARG).
# RESET causes a memory corruption problem, with all sorts of bad side effects
# so we've replaced it with the following code.
	my($key,$val);
	while (($key,$val) = each %script::) {
	    local(*priv::script) = $val;
	    undef $priv::script;
	    undef @priv::script;
	    undef %priv::script;
	}
    }
    die("$0: script errors encountered: construction aborted\n") if $run::errors;
}

# Link a directory to another. This simply means set up the *source*
# for the directory to be the other directory.
sub Link {
    my(@paths) = @_;
    my($srcdir) = $dir::cwd->lookupdir(pop @paths)->srcdir;
    map($dir::cwd->lookupdir($_)->{srcdir} = $srcdir, @paths);
}

# Add directories to the repository search path for files.
# We're careful about stripping our current directory from
# the list, which we do by comparing the `pwd` results from
# the current directory and the specified directory.  This
# is cumbersome, but assures that the paths will be reported
# the same regardless of symbolic links.
sub Repository {
    my($my_dir) = $dir::cwd->path;
    if ($my_dir eq '.') {
    	chomp($my_dir = `pwd`);
    }
    foreach $dir (@_) {
	my($d) = `cd $dir 2>/dev/null && pwd`;
	next if ! $d;
	chop $d;
	push(@param::rpath, $dir::top->lookupdir($dir)) if -d $d && $d ne $my_dir;
    }
}

# Return the list of Repository directories specified.
sub Repository_List {
    map($_->path, @param::rpath);
}

# Specify whether the .consign signature times in repository files are,
# in fact, consistent with the times on the files themselves.
sub Repository_Sig_Times_OK {
    $param::rep_sig_times_ok = shift;
}

# Specify files/targets that must be present and built locally,
# even if they exist already-built in a Repository.
sub Local {
    my(@files) = map($dir::cwd->lookup($_), @_);
    map($_->local(1), @files);
}

# Export variables to any scripts invoked from this one.
sub Export {
    @{$priv::self->{exports}} = @_;
}

# Import variables from the export list of the caller
# of the current script.
sub Import {
    my($parent) = $priv::self->{parent};
    my($imports) = $priv::self->{imports};
    @{$priv::self->{exports}} = keys %$imports;
    my($var);
    while ($var = shift) {
	if (!exists $imports->{$var}) {
	    my($path) = $parent->{script}->path;
	    die qq($0: variable "$var" not exported by file "$path"\n);
	}
	if (!defined $imports->{$var}) {
	    my($path) = $parent->{script}->path;
	    die qq($0: variable "$var" exported but not defined by file "$path"\n);
	}
	${"script::$var"} = $imports->{$var};
    }
}

# Build an inferior script. That is, arrange to read and execute
# the specified script, passing to it any exported variables from
# the current script.
sub Build {
    my(@files) = map($dir::cwd->lookup($_), @_);
    my(%imports);
    map($imports{$_} = ${"script::$_"}, @{$priv::self->{exports}});
    for $file (@files) {
	next if $param::include && $file->path !~ /$param::include/o;
	my($self) = {'script' => $file,
		     'parent' => $priv::self,
		     'imports' => \%imports};
	bless $self;  # may want to bless into class of parent in future 
	push(@priv::scripts, $self);
    }
}

# Set up regexps dependencies to ignore. Should only be called once.
sub Ignore {
    die("Ignore called more than once\n") if $param::ignore;
    $param::ignore = join("|", map("($_)", @_)) if @_;
}

# Specification of default targets.  Should only be called once?
sub Default {
    die("Default called more than once\n") if $param::default_targets;
    @param::default_targets = @_ if @_;
}

# Local Help.  Should only be called once.
sub Help {
    if ($param::localhelp) {
	print "@_\n";
	exit 2;
    }
}

# Return the build name(s) of a file or file list.
sub FilePath {
    wantarray
	? map($dir::cwd->lookup($_)->path, @_)
	: $dir::cwd->lookup($_[0])->path;
}

# Return the build name(s) of a directory or directory list.
sub DirPath {
    wantarray
	? map($dir::cwd->lookupdir($_)->path, @_)
	: $dir::cwd->lookupdir($_[0])->path;
}

# Split the search path provided into components. Look each up
# relative to the current directory.
# The usual path separator problems abound; for now we'll use :
sub SplitPath {
    my($dirs) = @_;
    if (ref($dirs) ne ARRAY) {
	$dirs = [ split(/$main::PATH_SEPARATOR/o, $dirs) ];
    }
    map { DirPath(@_) } @$dirs;
}

# Return true if the supplied path is available as a source file
# or is buildable (by rules seen to-date in the build).
sub ConsPath {
    my($path) = @_;
    my($file) = $dir::cwd->lookup($path);
    return $file->accessible;
}

# Return the source path of the supplied path.
sub SourcePath {
    my($path) = @_;
    my($file) = $dir::cwd->lookup($path);
    return $file->srcpath;
}

# Search up the tree for the specified cache directory, starting with
# the current directory. Returns undef if not found, 1 otherwise.
# If the directory is found, then caching is enabled. The directory
# must be readable and writable. If the argument "mixtargets" is provided,
# then targets may be mixed in the cache (two targets may share the same
# cache file--not recommended).
sub UseCache($@) {
    my($dir, @args) = @_;
    # NOTE: it's important to process arguments here regardless of whether
    # the cache is disabled temporarily, since the mixtargets option affects
    # the salt for derived signatures.
    for (@args) {
	if ($_ eq "mixtargets") {
	    # When mixtargets is enabled, we salt the target signatures.
	    # This is done purely to avoid a scenario whereby if 
	    # mixtargets is turned on or off after doing builds, and
	    # if cache synchronization with -cs is used, then
	    # cache files may be shared in the cache itself (linked
	    # under more than one name in the cache). This is not bad,
	    # per se, but simply would mean that a cache cleaning algorithm
	    # that looked for a link count of 1 would never find those
	    # particular files; they would always appear to be in use.
	    $param::salt = 'M' . $param::salt;
            $param::mixtargets = 1;
        } else {
            die qq($0: UseCache unrecognized option "$_"\n");
        }
    }
    if ($param::cachedisable) {
	warn("Note: caching disabled by -cd flag\n");
	return 1;
    }
    my($depth) = 15;
    while ($depth-- && ! -d $dir) { $dir = "../$dir"; }
    if (-d $dir) {
	$param::cache = $dir;
	return 1;
    }
    return undef;
}

# Salt the signature generator. The salt (a number of string) is added
# into the signature of each derived file. Changing the salt will
# force recompilation of all derived files.
sub Salt($) {
    # We append the value, so that UseCache and Salt may be used
    # in either order without changing the signature calculation.
    $param::salt .= $_[0];
}


# These methods are callable from Conscript files, via a cons
# object. Procs beginning with _ are intended for internal use.
package cons;

# This is passed the name of the base environment to instantiate.
# Overrides to the base environment may also be passed in
# as key/value pairs. 
sub new {
    my($package) = shift;
    my ($env) = {@param::defaults, @_};
    @{$env->{_envcopy}} = %$env; # Note: we never change PATH
    $env->{_cwd} = $dir::cwd; # Save directory of environment for
    bless $env, $package;	# any deferred name interpretation.
}

# Clone an environment.
# Note that the working directory will be the initial directory
# of the original environment.
sub clone {
    my($env) = shift;
    my $clone = {@{$env->{_envcopy}}, @_};
    @{$clone->{_envcopy}} = %$clone; # Note: we never change PATH
    $clone->{_cwd} = $env->{_cwd};
    bless $clone, ref $env;
}

# Create a flattened hash representing the environment.
# It also contains a copy of the PATH, so that the path
# may be modified if it is converted back to a hash.
sub copy {
    my($env) = shift;
    (@{$env->{_envcopy}}, 'ENV' => {%{$env->{ENV}}}, @_)
}

# Resolve which environment to actually use for a given
# target. This is just used for simple overrides.
sub _resolve {
    return $_[0] if !$param::overrides;
    my($env, $tgt) = @_;
    my($path) = $tgt->path;
    for $re (@param::overrides) {
	next if $path !~ /$re/;
	# Found one. Return a combination of the original environment
	# and the override.
	my($ovr) = $param::overrides{$re};
	return $envcache{$env,$re} if $envcache{$env,$re};
	my($newenv) = {@{$env->{_envcopy}}, @$ovr};
	@{$newenv->{_envcopy}} = %$env;
	$newenv->{_cwd} = $env->{_cwd};
	return $envcache{$env,$re} = bless $newenv, ref $env;
    }
    return $env;
}

# Substitute construction environment variables into a string.
# Internal function/method.
sub _subst {
    my($env, $str) = @_;
    while ($str =~ s/\%([_a-zA-Z]\w*)/$env->{$1}/ge) {}
    $str;
}

sub Install {
    my($env) = shift;
    my($tgtdir) = $dir::cwd->lookupdir(shift);
    for $file (map($dir::cwd->lookup($_), @_)) {
	my($tgt) = $tgtdir->lookup($file->{entry});
	$tgt->bind(find build::install, $file);
    }
}

# Installation in a local build directory,
# copying from the repository if it's already built there.
# Functionally equivalent to:
#	Install $env $dir, $file;
#	Local "$dir/$file";
sub Install_Local {
    my($env) = shift;
    my($tgtdir) = $dir::cwd->lookupdir(shift);
    for $file (map($dir::cwd->lookup($_), @_)) {
	my($tgt) = $tgtdir->lookup($file->{entry});
	$tgt->bind(find build::install, $file);
	$tgt->local(1);
    }
}

sub Objects {
    my($env) = shift;
    map($_->{entry}, _Objects($env, map($dir::cwd->lookup($_), @_)))
}

# Called with multiple source file references (or object files).
# Returns corresponding object files references.
sub _Objects {
    my($env) = shift;
    my($suffix) = $env->{SUFOBJ};
    map(_Object($env, $_, $_->{dir}->lookup($_->base . $suffix)), @_);
}

# Called with an object and source reference.  If no object reference
# is supplied, then the object file is determined implicitly from the
# source file's extension. Sets up the appropriate rules for creating
# the object from the source.  Returns the object reference.
sub _Object {
    my($env, $src, $obj) = @_;
    return $obj if $src eq $obj; # don't need to build self from self.
    my($objenv) = $env->_resolve($obj);
    my($suffix) = $src->suffix;

    my($builder) = $env->{SUFMAP}{$suffix};

    if ($builder) {
	$obj->bind((find $builder($objenv)), $src);
    } else {
	die("don't know how to construct ${\$obj->path} from ${\$src->path}.\n");
    }
    $obj
}

sub Program {
    my($env) = shift;
    my($tgt) = $dir::cwd->lookup(shift);
    my($progenv) = $env->_resolve($tgt);
    $tgt->bind(find build::command::link($progenv, $progenv->{LINKCOM}),
	       $env->_Objects(map($dir::cwd->lookup($_), @_)));
}

sub Module {
    my($env) = shift;
    my($tgt) = $dir::cwd->lookup(shift);
    my($modenv) = $env->_resolve($tgt);
    my($com) = pop(@_);
    $tgt->bind(find build::command::link($modenv, $com),
	       $env->_Objects(map($dir::cwd->lookup($_), @_)));
}

sub LinkedModule {
    my($env) = shift;
    my($tgt) = $dir::cwd->lookup(shift);
    my($progenv) = $env->_resolve($tgt);
    $tgt->bind(find build::command::linkedmodule
	       ($progenv, $progenv->{LINKMODULECOM}),
	       $env->_Objects(map($dir::cwd->lookup($_), @_)));
}

sub Library {
    my($env) = shift;
    my($lib) = $dir::cwd->lookup(file::addsuffix(shift, $env->{SUFLIB}));
    my($libenv) = $env->_resolve($lib);
    $lib->bind(find build::command::library($libenv),
	       $env->_Objects(map($dir::cwd->lookup($_), @_)));
}

# Simple derivation: you provide target, source(s), command.
# Special variables substitute into the rule.
# Target may be a reference, in which case it is taken
# to be a multiple target (all targets built at once).
sub Command {
    my($env) = shift;
    my($tgt) = shift;
    my($com) = pop(@_);
    my(@sources) = map($dir::cwd->lookup($_), @_);
    if (ref($tgt)) {
	# A multi-target command.
	my(@tgts) = map($dir::cwd->lookup($_), @$tgt);
	die("empty target list in multi-target command\n") if !@tgts;
	$env = $env->_resolve($tgts[0]);
	my($builder) = find build::command::user($env, $com);
	my($multi) = build::multiple->new($builder, \@tgts);
	for $tgt (@tgts) {
	    $tgt->bind($multi, @sources);
	}
    } else {
	$tgt = $dir::cwd->lookup($tgt);
	$env = $env->_resolve($tgt);
	my($builder) = find build::command::user($env, $com);
	$tgt->bind($builder, @sources);
    }
}

sub Depends {
    my($env) = shift;
    my($tgt) = $dir::cwd->lookup(shift);
    push(@{$tgt->{dep}}, map($dir::cwd->lookup($_), @_));
}

# Setup a quick scanner for the specified input file, for the
# associated environment. Any use of the input file will cause the
# scanner to be invoked, once only. The scanner sees just one line at
# a time of the file, and is expected to return a list of
# dependencies.
sub QuickScan {
    my($env, $code, $file, $path) = @_;
    $dir::cwd->lookup($file)->{srcscan,$env} =
	find scan::quickscan($code, $env, $path);
}

# Generic builder module. Just a few default methods.  Every derivable
# file must have a builder object of some sort attached.  Usually
# builder objects are shared.
package build;

# Null signature for dynamic includes.
sub includes { () }

# Null signature for build script.
sub script { () }

# Not compatible with any other builder, by default.
sub compatible { 0 }


# Builder module for the Install command.
package build::install;
BEGIN {
    @ISA = qw(build);
    bless $installer = {}    # handle for this class.
} 

sub find {
    $installer
}

# Caching not supported for Install: generally install is trivial anyway,
# and we don't want to clutter the cache.
sub cachin { undef }
sub cachout { }

# Do the installation.
sub action {
    my($self, $tgt) = @_;
    my($src) = $tgt->{sources}[0];
    main::showcom("Install ${\$src->rpath} as ${\$tgt->path}") if $param::install;
    return unless $param::build;
    futil::install($src->rpath, $tgt);
    return 1;
}


# Builder module for generic UNIX commands.
package build::command;
BEGIN { @ISA = qw(build) }

sub find {
    my($class, $env, $com, $includes) = @_;
    $com = $env->_subst($com);
    $com{$env,$com,$includes} || do {
	# Remove unwanted bits from signature -- those bracketed by %( ... %)
	my($comsig) = $com;
	while ($comsig =~ s/%\(([^%]|%[^\(])*?%\)//g) { }
	my($self) = { env => $env, com => $com, includes => $includes,
		     comsig => $comsig };
	$com{$env,$com,$includes} = bless $self, $class;
    }
}

# Default cache in function.
sub cachin {
    my($self, $tgt, $sig) = @_;
    if (cache::in($tgt, $sig)) {
	if ($param::cachecom) {
	    map { main::showcom($_) } $self->getcoms($tgt);
	} else {
	    printf("Retrieved %s from cache\n", $tgt->path);
	}
	return 1;
    }
    return undef;
}

# Default cache out function.
sub cachout {
    my($self, $tgt, $sig) = @_;
    cache::out($tgt, $sig);
}

# For the signature of a basic command, we don't bother
# including the command itself. This is not strictly correct,
# and if we wanted to be rigorous, we might want to insist
# that the command was checked for all the basic commands
# like gcc, etc. For this reason we don't have an includes
# method.

# Call this to get the command line script: an array of
# fully substituted commands.
sub getcoms {
    my($self, $tgt) = @_;
    my(@coms);
    for $com (split(/\n/, $self->{com})) {
	my(@src) = (undef, @{$tgt->{sources}});
	my(@src1) = @src;

	next if $com =~ /^\s*$/;

	# NOTE: we used to have a more elegant s//.../e solution
	# for the items below, but this caused a bus error...

	# Remove %( and %) -- those are only used to bracket parts
	# of the command that we don't depend on.
	$com =~ s/%[()]//g;

	# Deal with %n, n=1,9 and variants.
	while ($com =~ /%([1-9])(:([fd]?))?/) {
	    my($match) = $&;
	    my($src) = $src1[$1];
	    my($subst) =
		!$src? '' :
		    $3 eq 'f' ? $src1[$1]->{entry} :
			$3 eq 'd'? $src1[$1]->rfile->{dir}->path :
			    $src1[$1]->rpath;
	    undef $src[$1];	    
	    $com =~ s/$match/$subst/;
	}

	# Deal with %0 aka %> and variants.
	while ($com =~ /%[0>](:([fd]?))?/) {
	    my($match) = $&;
	    my($subst) =
		$2 eq 'f' ? $tgt->{entry} :
		    $2 eq 'd'? $tgt->{dir}->path :
			$tgt->path;
	    $com =~ s/$match/$subst/;
	}

	# Deal with %< (all sources except %n's already used)
	while ($com =~ /%<(:([fd]?))?/) {
	    my($match) = $&;
	    my($subst) =
		join(' ',
		     $2 eq 'f' ? map($_ && $_->{entry} || (), @src) :
		     $2 eq 'd' ? map($_ && $_->rfile->{dir}->path || (), @src) :
		     map($_ && $_->rpath || (), @src));
	    $com =~ s/$match/$subst/;
	}
	
	# White space cleanup. XXX NO WAY FOR USER TO HAVE QUOTED SPACES
	$com = join(' ', split(' ', $com));
	next if $com =~ /^:/ && $com !~ /^:\S/;
	push(@coms, $com);
    }
    @coms
}

# Build the target using the previously specified commands.
sub action {
    my($self, $tgt) = @_;
    my($env) = $self->{env};

    if ($param::build) {
	futil::mkdir($tgt->{dir});
	unlink($tgt->path); # is this done already?
    }

    # Set environment.
    map(delete $ENV{$_}, keys %ENV);
    %ENV = %{$env->{ENV}};

    # Handle multi-line commands.
    for $com ($self->getcoms($tgt)) {
        main::showcom($com);
	if ($param::build) {

	  #---------------------
	  # Can't fork on Win32
	  #---------------------
	  
	  if ($main::_WIN32) {
	    system($com);
	  } else {
	    my($pid) = fork();
	    die("$0: unable to fork child process ($!)\n") if !defined $pid;
	    if (!$pid) {
	      # This is the child.
	      exec($com);
	      $com =~ s/\s.*//;
	      die qq($0: failed to execute "$com" ($!). )
		. qq(Is this an executable on path "$ENV{PATH}"?\n);
	    }
	    for (;;) {
	      do {} until wait() == $pid;
	      my($b0, $b1 ) = ($? & 0xFF, $? >> 8);
	      # Don't actually see 0177 on stopped process; is this necessary?
	      next if $b0 == 0177; # process stopped; we can wait.
	      if ($b0) {
		my($core, $sig) = ($b0 & 0200, $b0 & 0177);
		my($coremsg) = $core ? "; core dumped" : "";
		$com =~ s/\s.*//;
		my($path) = $tgt->path;
		warn qq($0: *** [$path] $com terminated by signal $sig$coremsg\n);
		return undef;
	      }
	      if ($b1) {
		my($path) = $tgt->path;
		warn qq($0: *** [$path] Error $b1\n); # trying to be like make.
		return undef;
	      }
	      last;
	    }
	  }
	}

	if ($main::_WIN32) {
	  my($err) = $?;
	  if ($err) {
	    my($path) = $tgt->path;
	    warn qq($0: *** [$path] Error $err\n); # trying to be like make.
	    return undef;
	  }
	}
      }

    # success.
    return 1;
}

# Return script signature.
sub script {
    $_[0]->{comsig}
}


# Create a linked module.
package build::command::link;
BEGIN { @ISA = qw(build::command) }

# Find an appropriate linker.
sub find {
    my($class, $env, $command) = @_;
    if (!exists $env->{_LDIRS}) {
	my($ldirs);
	my($wd) = $env->{_cwd};
	my($pdirs) = $env->{LIBPATH};
	if (ref($pdirs) ne 'ARRAY') {
	    $pdirs = [ split(/$main::PATH_SEPARATOR/o, $pdirs) ];
	}
	# On Win32, build library search path as /LIBPATH:A
	# <schwarze@isa.de> 1998-05-13
	# Move its invariant calculation outside the loop
	# <knight@baldmt.com> 1998-09-22
	my($flagprefix) = " ${main::LIB_FLAG_PREFIX}";
	for $dir (map($wd->lookupdir($_), @$pdirs)) {
	    my($dpath) = $dir->path;
	    $ldirs .= $flagprefix . $dpath;
	    next if $dpath =~ m#^$dir::MATCH_SEPARATOR#o;
	    if (@param::rpath) {
		my($suffix);
		if ($dpath ne '.' && $dpath !~ '^#') {
		    $suffix = $dir::SEPARATOR . $dpath;
		}
		my($d);
		foreach $d (@param::rpath) {
		    $ldirs .= $flagprefix . $d->path . $suffix;
		}
	    }
	}
	$env->{_LDIRS} = "%($ldirs%)";
    }

    # Introduce a new magic _LIBS symbol which allows to use the
    # Unix-style -lNAME syntax for Win32 only. -lNAME will be replaced
    # with %{PREFLIB}NAME%{UFLIB}. <schwarze@isa.de> 1998-06-18

    if ($main::_WIN32 && !exists $env->{_LIBS}) {
	my($libs);
	for $name (split(' ', $env->_subst($env->{LIBS}))) {
	    if ($name =~ /^-l(.*)/) {
		$name = "$env->{PREFLIB}$1$env->{SUFLIB}";
	    }
	    $libs .= ' ' . $name;
	}
	$env->{_LIBS} = "%($libs%)";
    }
    bless find build::command($env, $command);
}

# Called from file::build. Make sure any libraries needed by the
# environment are built, and return the collected signatures
# of the libraries in the path.
sub includes {
    return $_[0]->{sig} if exists $_[0]->{sig};
    my($self, $tgt) = @_;
    my($env) = $self->{env};
    my($ewd) = $env->{_cwd};
    my($ldirs) = $env->{LIBPATH};
    if (ref($ldirs) ne 'ARRAY') {
	$ldirs = [ split(/$main::PATH_SEPARATOR/o, $ldirs) ];
    }
    my(@lpath) = map($ewd->lookupdir($_), @$ldirs);
    my(@sigs);
    my(@names);

    if ($main::_WIN32) {
      # Pass %LIBS symbol through %-substituition
      # <schwarze@isa.de> 1998-06-18
      @names = split(' ', $env->_subst($env->{LIBS}));
    } else {
      @names = split(' ', $env->{LIBS});
    }
    for $name (@names) {
      my($lpath,@allnames);
	if ($name =~ /^-l(.*)/) {
            # -l style names are looked up on LIBPATH, using all
            # possible lib suffixes in the same search order the
            # linker uses (according to SUFLIBS).
	    # Recognize new PREFLIB symbol, which should be 'lib' on
	    # Unix, and empty on Win32. TODO: What about shared
	    # library suffixes?  <schwarze@isa.de> 1998-05-13
           @allnames = map("$env->{PREFLIB}$1$_",
                           split(/:/, $env->{SUFLIBS}));
	    $lpath = \@lpath;
	} else {
	    @allnames = ($name);
	    # On Win32, all library names are looked up in LIBPATH
	    # <schwarze@isa.de> 1998-05-13
	    if ($main::_WIN32) {
		$lpath = [$dir::top, @lpath];
	    }
	    else {
		$lpath = [$dir::top];
	    }
	}
        DIR: for $dir (@$lpath) {
            for $n (@allnames) {
                my($lib) = $dir->lookup($n);
                if ($lib->accessible) {
                    last DIR if $lib->ignore;
                    if ((build $lib) eq 'errors') {
                        $tgt->{status} = 'errors';
                        return undef;
                    }
                    push(@sigs, sig->signature($lib));
                    last DIR;
		}
	    }
	}
    }
    $self->{sig} = sig->collect(@sigs);
}    

# Always compatible with other such builders, so the user
# can define a single program or module from multiple places.
sub compatible {
    my($self, $other) = @_;
    ref($other) eq "build::command::link";
}

# Link a program.
package build::command::linkedmodule;

BEGIN { @ISA = qw(build::command) }

# Always compatible with other such builders, so the user
# can define a single linked module from multiple places.
sub compatible {
    my($self, $other) = @_;
    ref($other) eq "build::command::linkedmodule";
}

# Builder for a C module
package build::command::cc;

BEGIN { @ISA = qw(build::command) }

sub find {
    $_[1]->{_cc} || do {
	my($class, $env) = @_;
	my($cscanner) = find scan::cpp($env->{_cwd}, $env->{CPPPATH});
	$env->{_IFLAGS} = "%(" . $cscanner->iflags . "%)";
	my($self) = find build::command($env, $env->{CCCOM});
	$self->{scanner} = $cscanner;
	bless $env->{_cc} = $self;
    }
}

# Invoke the associated	 C scanner to get signature of included files.
sub includes {
    my($self, $tgt) = @_;
    $self->{scanner}->includes($tgt, $tgt->{sources}[0]);
}

# Builder for a user command (cons::Command).  We assume that a user
# command might be built and implement the appropriate dependencies on
# the command itself (actually, just on the first word of the command
# line).
package build::command::user;

BEGIN { @ISA = qw(build::command) }

# XXX Optimize this to not use ignored paths.
sub comsig {
    return $_[0]->{_comsig} if exists $_[0]->{_comsig};
    my($self, $tgt) = @_;
    my($env) = $self->{env};
  com:
    for $com (split(/[\n;]/, $self->script)) {
	# Isolate command word.
	$com =~ s/^\s*//;
	$com =~ s/\s.*//;
	next if !$com; # blank line
	my($pdirs) = $env->{ENV}->{PATH};
	if (ref($pdirs) ne 'ARRAY') {
	    $pdirs = [ split(/$main::PATH_SEPARATOR/o, $pdirs) ];
	}						     
	for $dir (map($dir::top->lookupdir($_), @$pdirs)) {
	    my($prog) = $dir->lookup($com);
	    if ($prog->accessible) { # XXX Not checking execute permission.
		if ((build $prog) eq 'errors') {
		    $tgt->{status} = 'errors';
		    return undef;
		}
		next com if $prog->ignore;
		$self->{_comsig} .= sig->signature($prog);
		next com;
	    }
	}
	# Not found: let shell give an error.
    }
    $self->{_comsig}
}

sub includes {
    my($self, $tgt) = @_;
    my($sig);

    # Check for any quick scanners attached to source files.
    for $dep (@{$tgt->{dep}}, @{$tgt->{sources}}) {
	my($scanner) = $dep->{srcscan,$self->{env}};
	if ($scanner) {
	    $sig .= $scanner->includes($tgt, $dep);
	}
    }

    # Add the command signature.
    return &comsig . $sig;
}


# Builder for a library module (archive).
# We assume that a user command might be built and implement the
# appropriate dependencies on the command itself.
package build::command::library;

BEGIN { @ISA = qw(build::command) }

sub find {
    my($class, $env) = @_;
    bless find build::command($env, $env->{ARCOM})
}

# Always compatible with other library builders, so the user
# can define a single library from multiple places.
sub compatible {
    my($self, $other) = @_;
    ref($other) eq "build::command::library";
}

# A multi-target builder.
# This allows multiple targets to be associated with a single build
# script, without forcing all the code to be aware of multiple targets.
package build::multiple;

sub new {
    my($class, $builder, $tgts) = @_;
    bless { 'builder' => $builder, 'tgts' => $tgts };
}

sub script {
    my($self, $tgt) = @_;
    $self->{builder}->script($tgt);
}

sub includes {
    my($self, $tgt) = @_;
    $self->{builder}->includes($tgt);
}

sub compatible {
    my($self, $tgt) = @_;
    $self->{builder}->compatible($tgt);
}

sub cachin {
    my($self, $tgt, $sig) = @_;
    $self->{builder}->cachin($tgt, $sig);
}

sub cachout {
    my($self, $tgt, $sig) = @_;
    $self->{builder}->cachout($tgt, $sig);
}

sub action {
    my($self, $invoked_tgt) = @_;
    return $self->{built} if exists $self->{built};

    # Make sure all targets in the group are unlinked before building any.
    my($tgts) = $self->{tgts};
    for $tgt (@$tgts) {
	futil::mkdir($tgt->{dir});
	unlink($tgt->path);
    }

    # Now do the action to build all the targets. For consistency
    # we always call the action on the first target, just so that
    # $> is deterministic.
    $self->{built} = $self->{builder}->action($tgts->[0]);

    # Now "build" all the other targets (except for the one
    # we were called with). This guarantees that the signature
    # of each target is updated appropriately. We force the
    # targets to be built even if they have been previously
    # considered and found to be OK; the only effect this
    # has is to make sure that signature files are updated
    # correctly.
    for $tgt (@$tgts) {
	if ($tgt ne $invoked_tgt) {
	    delete $tgt->{status};
	    sig->invalidate($tgt);
	    build $tgt;
	}
    }

    # Status of action.
    $self->{built};
}


# Generic scanning module.
package scan;

# Returns the signature of files included by the specified files on
# behalf of the associated target. Any errors in handling the included
# files are propagated to the target on whose behalf this processing
# is being done. Signatures are cached for each unique file/scanner
# pair.
sub includes {
    my($self, $tgt, @files) = @_;
    my(%files, $file);
    my($inc) = $self->{includes} || ($self->{includes} = {});
    while ($file = pop @files) {
	next if exists $files{$file};
	if ($inc->{$file}) {
	    push(@files, @{$inc->{$file}});
	    $files{$file} = sig->signature($file->rfile);
	} else {
	    if ((build $file) eq 'errors') {
		$tgt->{status} = 'errors'; # tgt inherits build status
		return ();
	    }
	    $files{$file} = sig->signature($file->rfile);
	    my(@includes) = $self->scan($file);
	    $inc->{$file} = \@includes;
	    push(@files, @includes);
	}
    }
    sig->collect(sort values %files)
}


# A simple scanner. This is used by the QuickScanfunction, to setup
# one-time target and environment-independent scanning for a source
# file. Only used for commands run by the Command method.
package scan::quickscan;

BEGIN { @ISA = qw(scan) }

sub find {
    my($class, $code, $env, $path) = @_;
    $scanner{$code,$env,$path} || do {
	my(@path) = map { $dir::cwd->lookupdir($_) } split(/:/, $path);
	my($self) = { code => $code, env => $env, path => \@path };
	$scanner{$code,$env,$path} = bless $self;
    }
}

# Scan the specified file for included file names.
sub scan {
    my($self, $file) = @_;
    my($code) = $self->{code};
    my(@includes);
    # File should have been built by now. If not, we'll ignore it.
    return () unless open(SCAN, $file->rpath);
    local($script::env) = $self->{env};
    while(<SCAN>) {
	push(@includes, &$code);
    }
    close(SCAN);
    my($wd) = $file->{dir};
    my(@files);
    for $name (@includes) {
	for $dir ($file->{dir}, @{$self->{path}}) {
	    my($include) = $dir->lookup($name);
	    if ($include->accessible) {
		push(@files, $include) unless $include->ignore;
		last;
	    }
	}
    }
    @files
}


# CPP (C preprocessor) scanning module
package scan::cpp;

BEGIN { @ISA = qw(scan) }

# For this constructor, provide the include path argument (colon
# separated). Each path is taken relative to the provided directory.

# Note: a particular scanning object is assumed to always return the
# same result for the same input. This is why the search path is a
# parameter to the constructor for a CPP scanning object. We go to
# some pains to make sure that we return the same scanner object
# for the same path: otherwise we will unecessarily scan files.
sub find {
    my($class, $dir, $pdirs) = @_;
    if (ref($pdirs) ne 'ARRAY') {
	$pdirs = [ split(/$main::PATH_SEPARATOR/o, $pdirs) ];
    }
    my(@path) = map($dir->lookupdir($_), @$pdirs);
    my($spath) = "@path";
    $scanner{$spath} || do {
	my($self) = {'path' => \@path};
	$scanner{$spath} = bless $self;
    }
}

# Scan the specified file for include lines.
sub scan {
    my($self, $file) = @_;
    my($angles, $quotes);

    if (exists $file->{angles}) {
	$angles = $file->{angles};
	$quotes = $file->{quotes};
    } else {
	my(@anglenames, @quotenames);
	return () unless open(SCAN, $file->rpath);
	while (<SCAN>) {
	    next unless /^\s*#/;
	    if (/^\s*#\s*include\s*([<"])(.*)[>"]/) {
		if ($1 eq "<") {
		    push(@anglenames, $2);
		} else {
		    push(@quotenames, $2);
		}
	    }
	}
	close(SCAN);
	$angles = $file->{angles} = \@anglenames;
	$quotes = $file->{quotes} = \@quotenames;
    }


    my(@shortpath) = @{$self->{path}};	  # path for <> style includes
    my(@longpath) = ($file->{dir}, @shortpath); # path for "" style includes

    my(@includes);

    for $name (@$angles) {
	for $dir (@shortpath) {
	    my($include) = $dir->lookup($name);
	    if ($include->accessible) {
		push(@includes, $include) unless $include->ignore;
		last;
	    }
	}
    }

    for $name (@$quotes) {
	for $dir(@longpath) {
	    my($include) = $dir->lookup($name);
	    if ($include->accessible) {
		push(@includes, $include) unless $include->ignore;
		last;
	    }
	}
    }	    

    return @includes
}

# Return the include flags that would be used for a C Compile.
sub iflags {
    my($self) = @_;
    my($iflags);
    my($dpath);
    # Recognize /I style include directive on Win32
    # <schwarze@isa.de> 1998-05-13
    # Move its invariant calculation outside the loop
    # <knight@baldmt.com> 1998-09-22
    my($flagprefix) = " ${main::FLAG_CHARACTER}I";
    for $dpath (map($_->path, @{$self->{path}})) {
	$iflags .= $flagprefix . $dpath;
	next if $dpath =~ m#^$dir::MATCH_SEPARATOR#o;
	if (@param::rpath) {
	    my($suffix);
	    if ($dpath ne '.' && $dpath !~ '^#') {
		$suffix = $dir::SEPARATOR . $dpath;
	    }
	    my($dir);
	    foreach $dir (@param::rpath) {
		$iflags .= $flagprefix . $dir->path . $suffix;
	    }
	}
    }
    $iflags
}

# Directory and file handling. Files/dirs are represented by objects.
# Other packages are welcome to add component-specific attributes.
package dir;

BEGIN {

    $SEPARATOR = "/";
    $MATCH_SEPARATOR = "/";
    if ($main::_WIN32) {
	$SEPARATOR = "\\";
	$MATCH_SEPARATOR = "\\\\";
    }

    $root = {path => $SEPARATOR, prefix => $SEPARATOR, 
             srcpath => $SEPARATOR, 'exists' => 1 };
    $root->{srcdir} = $root;
    bless $root;

    $top = {path => '.', prefix => '', srcpath => '.', exists => 1 };
    $top->{srcdir} = $top;
    $top->{member}->{'.'} = $top;
    bless $top;

    $cwd = $top;
}

# Look up a file (but not a directory) in a directory. 
# The file may be specified as relative, absolute (starts
# with /), or top-relative (starts with #).
sub lookup {
    my($dir, $entry) = @_;

    #--------------------------------------------------------------------
    # Convert entry to use SEPARATOR characters so it is correct on eith
    # win32 or Unix platforms.
    #--------------------------------------------------------------------

    $entry =~ s#/#$SEPARATOR#g;

    if ($entry !~ m#$MATCH_SEPARATOR#o) {
	# Fast path: simple entry name in a known directory.
	if ($entry =~ s/^#//) {
	    # Top-relative names begin with #.
	    $dir = $dir::top;
	}
    } else {
	# Path has a / in it somewhere. Separate into
	# stem and entry, and find the new directory
	# to look the entry up in.
	my($stem);
	if ($entry =~ s#^$MATCH_SEPARATOR##) {
	    # Absolute path
	    if ($entry =~ m#$MATCH_SEPARATOR#o) {
		($stem, $entry) = $entry =~ m#(.*)$MATCH_SEPARATOR(.*)#o;
		$dir = $root->lookupdir($stem)
	    } else {
		return $root if !$entry;
		$dir = $root;
	    }
	} else {
  	    ($stem, $entry) = $entry =~ m#(.*)$MATCH_SEPARATOR(.*)#o;
	    if ($entry =~ s/^#//) {
		# Top-relative names begin with #.
		$dir = $dir::top->lookupdir($stem)
	    } else {
		$dir = $dir->lookupdir($stem)
	    }
	}
    }

    $dir->{member}->{$entry} ||
	bless $dir->{member}->{$entry} =
	    {'entry' => $entry, 'dir' => $dir}, file
}

sub lookupdir {
    $dir::cache{$_[0],$_[1]} || do {
	my($dir) = $dir::cache{$_[0],$_[1]} = &dir::lookup;
	$dir->{member}->{'..'} = $dir->{dir};
	$dir->{member}->{'.'} = $dir;
	bless $dir;
    }	    
}

# Return the path of the directory (file paths implemented
# separately, below).
sub path {
    $_[0]->{path} ||
	($_[0]->{path} = $_[0]->{dir}->prefix . $_[0]->{entry});
}

# Return the pathname as a prefix to be concatenated with an entry.
sub prefix {
    return $_[0]->{prefix} if exists $_[0]->{prefix};
    $_[0]->{prefix} = $_[0]->path . $SEPARATOR;
}

# Return the related source path prefix.
sub srcprefix {
    return $_[0]->{srcprefix} if exists $_[0]->{srcprefix};
    my($srcdir) = $_[0]->srcdir;
    $srcdir->{srcprefix} = $srcdir eq $_[0] ? $srcdir->prefix : $srcdir->srcprefix;
}

# Return the related source directory.
sub srcdir {
    $_[0]->{srcdir} ||
	($_[0]->{srcdir} = $_[0]->{dir}->srcdir->lookupdir($_[0]->{entry}))
}

# Return if the directory is linked to a separate source directory.
sub is_linked {
    $_[0]->{is_linked} ||
	($_[0]->{is_linked} = $_[0]->path ne $_[0]->srcdir->path)
}

sub accessible {
    my($path) = $_[0]->path;
    die(qq($0: you have attempted to use path "$path" both as a file and as a directory!\n));
}


package file;

BEGIN { @ISA = qw(dir) }

# Return the pathname of the file.
# Define this separately from dir::path because we don't want to
# cache all file pathnames (just directory pathnames).
sub path {
    $_[0]->{dir}->prefix . $_[0]->{entry}
}

# Return the related source file path.
sub srcpath {
    $_[0]->{dir}->srcprefix . $_[0]->{entry}
}

# Return if the file is (should be) linked to a separate source file.
sub is_linked {
    $_[0]->{dir}->is_linked
}

# Repository file search.  If the local file exists, that wins.
# Otherwise, return the first existing same-named file under a
# Repository directory.  If there isn't anything with the same name
# under a Repository directory, return the local file name anyway
# so that some higher layer can try to construct it.
sub rfile {
    return $_[0]->{rfile} if exists $_[0]->{rfile};
    my($self) = @_;
    my($rfile) = $self;
    if (@param::rpath) {
	my($path) = $self->path;
	if ($path !~ m#^$dir::MATCH_SEPARATOR#o && ! -f $path) {
	    my($dir);
	    foreach $dir (@param::rpath) {
		my($t) = $dir->prefix . $path;
		if (-f $t) {
		    $rfile = $_[0]->lookup($t);
		    $rfile->{is_on_rpath} = 1;
		    last;
		}
	    }
	}
    }
    $self->{rfile} = $rfile;
}

# "Erase" reference to a Repository file,
# making this a completely local file object
# by pointing it back to itself.
sub no_rfile {
    $_[0]->{rfile} = $_[0];
}

# Return a path to the first existing file under a Repository directory,
# implicitly returning the current file's path if there isn't a
# same-named file under a Repository directory.
sub rpath {
    $_[0]->{rpath} ||
	($_[0]->{rpath} = $_[0]->rfile->path)
}

# Return a path to the first linked srcpath file under a Repositoy
# directory, implicitly returning the current file's srcpath if there
# isn't a same-named file under a Repository directory.
sub rsrcpath {
    return $_[0]->{rsrcpath} if exists $_[0]->{rsrcpath};
    my($self) = @_;
    my($path) = $self->{rsrcpath} = $self->srcpath;
    if (@param::rpath && $path !~ m#^$dir::MATCH_SEPARATOR#o && ! -f $path) {
	my($dir);
	foreach $dir (@param::rpath) {
	    my($t) = $dir->prefix . $path;
	    if (-f $t) {
		$self->{rsrcpath} = $t;
		last;
	    }
	}
    }
    $self->{rsrcpath};
}

# Return if a same-named file source file exists.
# This handles the interaction of Link and Repository logic.
# As a side effect, it will link a source file from its Linked
# directory (preferably local, but maybe in a repository)
# into a build directory from its proper Linked directory.
sub source_exists {
    return $_[0]->{source_exists} if defined $_[0]->{source_exists};
    my($self) = @_;
    my($path) = $self->path;
    my($time) = (stat($path))[9];
    if ($self->is_linked) {
	# Linked directory, local logic.
	my($srcpath) = $self->srcpath;
	my($srctime) = (stat($srcpath))[9];
	if ($srctime) {
	    if (! $time || $srctime != $time) {
		futil::install($srcpath, $self);
	    }
	    return $self->{source_exists} = 1;
	}
	# Linked directory, repository logic.
	if (@param::rpath) {
	    if ($self != $self->rfile) {
		return $self->{source_exists} = 1;
	    }
	    my($rsrcpath) = $self->rsrcpath;
	    if ($path ne $rsrcpath) {
		my($rsrctime) = (stat($rsrcpath))[9];
		if ($rsrctime) {
		    if (! $time || $rsrctime != $time) {
			futil::install($rsrcpath, $self);
		    }
		    return $self->{source_exists} = 1;
		}
	    }
	}
	# There was no source file in any Linked directory
	# under any Repository.  If there's one in the local
	# build directory, it no longer belongs there.
	if ($time) {
	    unlink($path) || die("$0: couldn't unlink $path ($!)\n");
	}
	return $self->{source_exists} = '';
    } else {
    	if ($time) {
    	    return $self->{source_exists} = 1;
	}
	if (@param::rpath && $self != $self->rfile) {
	    return $self->{source_exists} = 1;
	}
	return $self->{source_exists} = '';
    }
}

# Return if a same-named derived file exists under a Repository directory.
sub derived_exists {
    $_[0]->{derived_exists} ||
	($_[0]->{derived_exists} = ($_[0] != $_[0]->rfile));
}

# Return if this file is somewhere under a Repository directory.
sub is_on_rpath {
    $_[0]->{is_on_rpath};
}

sub local {
    my($self, $arg) = @_;
    if (defined $arg) {
	$self->{local} = $arg;
    }
    $self->{local};
}

# Return the entry name of the specified file
# without the suffix 
sub base {
    my($entry) = $_[0]->{entry};
    $entry =~ s/\.[^\.]*$//;
    $entry;
}

# Return the suffix of the file, for up to a 3 character
# suffix. Anything less returns nothing.
sub suffix {
  if (! $main::_WIN32) {
    $_[0]->{entry} =~ /\.[^\.\/]{0,3}$/;
    $&
  } else {
    @pieces = split(/\./, $_[0]->{entry});
    $suffix = pop(pieces);
    return ".$suffix";
  }
}

# Called as a simple function file::addsuffix(name, suffix)
sub addsuffix {
    my($name, $suffix) = @_;

    if ($suffix && substr($name, -length($suffix)) ne $suffix) {
	return $name .= $suffix;
    }
    $name;
}

# Return true if the file is (or will be) accessible.
# That is, if we can build it, or if it is already present.
sub accessible {
    (exists $_[0]->{builder}) || ($_[0]->source_exists);
}

# Return true if the file should be ignored for the purpose
# of computing dependency information (should not be considered
# as a dependency and, further, should not be scanned for 
# dependencies). 
sub ignore {
    return 0 if !$param::ignore;
    return $_[0]->{ignore} if exists $_[0]->{ignore};
    $_[0]->{ignore} = $_[0]->path =~ /$param::ignore/o;
}

# Build the file, if necessary.
sub build {
    $_[0]->{status} || &file::_build;
}

sub _build {
    my($self) = @_;
    print main::DEPFILE $self->path, "\n" if param::depfile;
    print((' ' x $level), $self->path, "\n") if $param::depends;
    if (!exists $self->{builder}) {
	# We don't know how to build the file. This is OK, if
	# the file is present as a source file, under either the
	# local tree or a Repository.
	if ($self->source_exists) {
	    return $self->{status} = 'handled';
	} else {
	    my($name) = $self->path;
	    print("$0: don't know how to construct \"$name\"\n");
	    exit(1) unless $param::kflag;
	    return $self->{status} = 'errors'; # xxx used to be 'unknown'
	}
    }

    # An associated build object exists, so we know how to build
    # the file. We first compute the signature of the file, based
    # on its dependendencies, then only rebuild the file if the
    # signature has changed.
    my($builder) = $self->{builder};
    $level += 2;

    my(@deps) = (@{$self->{dep}}, @{$self->{sources}});
    my($rdeps) = \@deps;

    if ($param::random) {
	# If requested, build in a random order, instead of the
	# order that the dependencies were listed.
	my(%rdeps);
	map { $rdeps{$_,'*' x int(rand(0,10))} = $_ } @deps;
	$rdeps = [values(%rdeps)];
    }

    for $dep (@$rdeps) {
	if ((build $dep) eq 'errors') {
	    # Propagate dependent errors to target.
	    # but try to build all dependents regardless of errors.
	    $self->{status} = 'errors';
	}
    }

    # If any dependents had errors, then we abort.
    if ($self->{status} eq 'errors') {
        $level -= 2;
	return 'errors';
    }

    # Compute the final signature of the file, based on
    # the static dependencies (in order), dynamic dependencies,
    # output path name, and (non-substituted) build script.
    my($sig) = sig->collect(map(sig->signature($_->rfile), @deps),
			    $builder->includes($self),
			    $builder->script);

    # May have gotten errors during computation of dynamic
    # dependency signature, above.
    $level -= 2;
    return 'errors' if $self->{status} eq 'errors';

    if (@param::rpath && $self->derived_exists) {
	# There is no local file of this name, but there is one
	# under a Repository directory.

	if (sig->current($self->rfile, $sig)) {
	    # The Repository copy is current (its signature matches
	    # our calculated signature).
	    if ($self->local) {
		# ...but they want a local copy, so provide it.
		main::showcom("Local copy of ${\$self->path} from ${\$self->rpath}");
		futil::install($self->rpath, $self);
	    	sig->set($self, $sig);
	    }
	    return $self->{status} = 'handled';
	}

	# The signatures don't match, implicitly because something
	# on which we depend exists locally.  Get rid of the reference
	# to the Repository file; we'll build this (and anything that
	# depends on it) locally.
	$self->no_rfile;
    }

    # Then check for currency.
    if (! sig->current($self, $sig)) {
	# We have to build/derive the file.
	# First check to see if the built file is cached.
	if ($builder->cachin($self, $sig)) {
	    sig->set($self, $sig);
	    return $self->{status} = 'built';
	} elsif ($builder->action($self)) {
	    $builder->cachout($self, $sig);
	    sig->set($self, $sig);
	    return $self->{status} = 'built';
	} else {
	    die("$0: errors constructing ${\$self->path}\n") unless $param::kflag;
	    return $self->{status} = 'errors';
	}
    } else {
	# Push this out to the cache if we've been asked to (-C option).
	# Don't normally do this because it slows us down.
	# In a fully built system, no accesses to the cache directory
	# are required to check any files. This is a win if cache is
	# heavily shared. Enabling this option puts the directory in the
	# loop. Useful only when you wish to recreate a cache from a build.
	if ($param::cachesync) {
	    $builder->cachout($self, $sig);
	    sig->set($self, $sig);
	}
	return $self->{status} = 'handled';
    }
}

# Bind an action to a file, with the specified sources. No return value.
sub bind {
    my($self, $builder, @sources) = @_;
    if ($self->{builder} && !$self->{builder}->compatible($builder)) {
	# Even if not "compatible", we can still check to see if the
	# derivation is identical. It should be identical if the builder is
	# the same and the sources are the same.
	if ("$self->{builder} @{$self->{sources}}" ne "$builder @sources") {
	    $main::errors++;
	    my($path) = $self->path;
	    die("$0: attempt to build ${\$self->path} twice, in different ways!\n");
	}
	return;
    }
    if ($param::wflag) {
	my($lev) = 1;
	my(@frame);
	do {@frame = caller ++$lev} while $frame[3] ne '(eval)';
	@frame = caller --$lev;
	$self->{script} .= "; " if $self->{script};
	$self->{script} .= qq($frame[3] in "$frame[1]", line $frame[2]);
    }
    $self->{builder} = $builder;
    push(@{$self->{sources}}, @sources);
}

# File utilities
package futil;

# Install one file as another.
# Links them if possible (hard link), otherwise copies.
# Don't ask why, but the source is a path, the tgt is a file obj.
sub install {
    my($sp, $tgt) = @_;
    my($tp) = $tgt->path;
    return 1 if $tp eq $sp;
    return 1 if eval { link($sp, $tp) };
    unlink($tp);
    futil::mkdir($tgt->{dir});
    return 1 if eval { link($sp, $tp) };
    futil::copy($sp, $tp);
}

# Copy one file to another. Arguments are actual file names.
# Returns undef on failure. Preserves mtime and mode.
sub copy {
    my ($sp, $tp) = @_;
    my($mode, $length, $atime, $mtime) = (stat($sp))[2,7,8,9];

# ****XXX Remember to remove before going FCS, if fix is ok ****

#     if (!open(SRC, $sp)) {
# 	die("$0: unable to read file $sp ($!)\n");
# 	return undef;
#     }
#     if (!open(TGT, ">$tp")) {
# 	die("$0: unable to write file $tp ($!)\n");
# 	close(SRC);
# 	return undef;
#     }

    # Use Perl standard library module for file copying, which handles
    # binary copies. <schwarze@isa.de> 1998-06-18
    File::Copy::copy($sp, $tp)
	|| die qq($0: can't copy file "$sp" to "$tp" ($!)\n);
    utime $atime, $mtime, $tp
	|| die qq($0: can't set modification time for file "$tp" ($!)\n); #'
    chmod $mode, $tp
	|| die qq($0: can't set mode on file "$tp" ($!)\n); #'
    return 1;
}

# Ensure that the specified directory exists.
# Aborts on failure.
sub mkdir {
    return if $_[0]->{exists};
    futil::mkdir($_[0]->{dir}); # Recursively make parent.
    my($path) = $_[0]->path;
    if (!-d $path && !mkdir($path, 0777)) {
	die("$0: can't create directory $path ($!).\n");
    }
    $dir->{exists} = 1;
}


# Signature package.
package sig::hash;

sub init {
    my($dir) = @_;
    my($consign) = $dir->prefix . ".consign";
    my($dhash) = $dir->{consign} = {};
    if (-f $consign) {
	open(CONSIGN, $consign) || die("$0: can't open $consign ($!)\n");
	while(<CONSIGN>) {
	    chop;
	    ($file,$sig) = split(/:/,$_);
	    $dhash->{$file} = $sig;
	}
	close(HASH);
    }
    $dhash
}

# Read the hash entry for a particular file.
sub in {
    my($dir) = $_[0]->{dir};
    ($dir->{consign} || init($dir))->{$_[0]->{entry}}
}

# Write the hash entry for a particular file.
sub out {
    my($file, $sig) = @_;
    my($dir) = $file->{dir};
    ($dir->{consign} || init($dir))->{$file->{entry}} = $sig;
    $sig::hash::dirty{$dir} = $dir;
}

# Flush hash entries. Called at end or via ^C interrupt.
sub END {
    return if $called++; # May be called twice.
    close(CONSIGN); # in case this came in via ^C.
    for $dir (values %sig::hash::dirty) {
	$consign = $dir->prefix . ".consign";
	unlink($consign);
	open(CONSIGN, ">$consign") || die("$0: can't create $consign ($!)\n");
	my($entry, $sig);
	while(($entry,$sig) = each %{$dir->{consign}}) {
	    print CONSIGN ("$entry:$sig\n");
	}
	close(CONSIGN);
    }
}


# Derived file caching.
package cache;

# Find a file in the cache. Return non-null if the file is in the cache.
sub in {
    return undef unless $param::cache;
    my($file, $sig) = @_;
    # Add the path to the signature, to make it unique.
    $sig = sig->collect($sig, $file->path) unless $param::mixtargets;
    my($dir) = substr($sig, 0, 1);
    my($cp) = "$param::cache/$dir/$sig";
    return -f $cp && futil::install($cp, $file);
}

# Try to flush a file to the cache, if not already there.
# If it doesn't make it out, due to an error, then that doesn't
# really matter.
sub out {
    return unless $param::cache;
    my($file, $sig) = @_;
    # Add the path to the signature, to make it unique.
    $sig = sig->collect($sig, $file->path) unless $param::mixtargets;
    my($dir) = substr($sig, 0, 1);
    my($sp) = $file->path;
    my($cp) = "$param::cache/$dir/$sig";
    if (-f $cp) {
	# Already cached: try to use that instead, to save space.
	# This can happen if the -cs option is used on a previously
	# uncached build, or if two builds occur simultaneously.
	my($lp) = ".$sig";
	unlink($lp);
	return if ! eval { link($cp, $lp) };
	rename($lp, $sp);
	return;
    }
	
    return if eval { link($sp, $cp) };
    return if ! -f $sp; # if nothing to cache.
    if (futil::copy($sp, "$cp.new")) {
	rename("$cp.new", $cp);
    }
}


# Generic signature handling
package sig;

sub select {
    my($package, $subclass) = @_;
    @ISA = ("sig::$subclass");
};


# MD5-based signature package.
package sig::md5;

use MD5 1.6;

BEGIN {
    $md5 = new MD5;
}

# Invalidate a cache entry.
sub invalidate {
    delete $_[1]->{sig}
}

# Determine the current signature of an already-existing or
# non-existant file.
sub signature {
    if (defined $_[1]->{sig}) {
	return $_[1]->{sig};
    }
    my ($self, $file) = @_;
    my($path) = $file->path;
    my($time) = (stat($path))[9];
    if ($time) {
	my($sigtime) = sig::hash::in($file);
	if ($file->is_on_rpath) {
	    if ($sigtime) {
		my($htime, $hsig) = split(' ',$sigtime);
		if (! $hsig) {
		    # There was no separate $htime recorded in
		    # the .consign file, which implies that this
		    # is a source file in the repository.
		    # (Source file .consign entries don't record
		    # $htime.)  Just return the signature that
		    # someone else conveniently calculated for us.
		    return $htime;	# actually the signature
		} else {
		    if (! $param::rep_sig_times_ok || $htime == $time) {
			return $file->{sig} = $hsig;
		    }
		}
	    }
	    return $file->{sig} = $file->path . $time;
	}
	if ($sigtime) {
	    my($htime, $hsig) = split(' ',$sigtime);
	    if ($htime == $time) {
		return $file->{sig} = $hsig;
	    }
	}
	if ($path !~ m#^/#) {
            # A file in the local build directory. Assume we can write
	    # a signature file for it, and compute the actual source
	    # signature. We compute the file based on the build path,
	    # not source path, only because there might be parallel
	    # builds going on... In principle, we could use the source
	    # path and only compute this once.
	    my($sig) = srcsig($path);
	    sig::hash::out($file, $sig);
	    return $file->{sig} = $sig;
	} else {
	    return $file->{sig} = $file->{entry} . $time;
	}
    }
    $file->{sig} = '';
}

# Is the provided signature equal to the signature of the current
# instantiation of the target (and does the target exist)?
sub current {
    my($self, $file, $sig) = @_;
    # Uncomment this to debug checks for signature currency. 
    # <knight@baldmt.com> 1998-10-29
#   my $fsig = $self->signature($file); print STDOUT "\$self->signature(${\$file->path}) '$fsig' eq \$sig '$sig'\n"; return $fsig eq $sig;
    $self->signature($file) eq $sig
}

# Store the signature for a file.
sub set {
    my($self, $file, $sig) = @_;
    my($time) = (stat($file->path))[9];
    sig::hash::out($file, "$time $sig");
    $file->{sig} = $sig
}

# Return an aggregate signature
sub collect {
    my($self, @sigs) = @_;
    # The following sequence is faster than calling the hex interface.
    $md5->reset();
    $md5->add(join('', $param::salt, @sigs));

    # Uncomment this to debug dependency signatures. 
    # <schwarze@isa.de> 1998-05-08
#   my $buf = join(', ', $param::salt, @sigs); print STDOUT "sigbuf=|$buf|\n"; 
    # Uncomment this to print the result of dependency signature calculation.
    # <knight@baldmt.com> 1998-10-13
#   $buf = unpack("H*", $md5->digest()); print STDOUT "\t=>|$buf|\n"; return $buf;

    unpack("H*", $md5->digest());
}

# Directly compute a file signature as the MD5 checksum of the
# bytes in the file.
sub srcsig {
    my($path) = @_;
    $md5->reset();
    open(FILE, $path) || die("$0: couldn't read $path ($!)\n");
    $md5->addfile(FILE);
    close(FILE);
    # Uncomment this to print the result of file signature calculation.
    # <knight@baldmt.com> 1998-10-13
#   my $buf = unpack("H*", $md5->digest()); print STDOUT "$path=|$buf|\n"; return $buf;
    unpack("H*", $md5->digest());
}


#:endofperl