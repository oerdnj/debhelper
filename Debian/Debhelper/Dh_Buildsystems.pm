# A module for loading and managing debhelper buildsystem plugins.
# This module is intended to be used by all dh_auto_* helper commands.
#
# Copyright: © 2009 Modestas Vainius
# License: GPL-2+

package Debian::Debhelper::Dh_Buildsystems;

use strict;
use warnings;
use Debian::Debhelper::Dh_Lib;

use base 'Exporter';
our @EXPORT=qw(&buildsystems_init &buildsystems_do &load_buildsystem);

# Historical order must be kept for backwards compatibility. New
# buildsystems MUST be added to the END of the list.
our @BUILDSYSTEMS = (
    "autoconf",
    "perl_makemaker",
    "makefile",
    "python_distutils",
    "perl_build",
    "cmake",
);

my $opt_buildsys;
my $opt_builddir;
my $opt_list;

sub create_buildsystem_instance {
	my $system=shift;
	my %bsopts=@_;
	my $module = "Debian::Debhelper::Buildsystem::$system";

	eval "use $module";
	if ($@) {
		error("unable to load buildsystem class '$system': $@");
	}

	if (!exists $bsopts{builddir} && defined $opt_builddir) {
		$bsopts{builddir} = ($opt_builddir eq "") ? undef : $opt_builddir;
	}
	return $module->new(%bsopts);
}

sub load_buildsystem {
	my ($action, $system)=@_;
	if (defined $system) {
		my $inst = create_buildsystem_instance($system);
		return $inst;
	}
	else {
		# Try to determine build system automatically
		for $system (@BUILDSYSTEMS) {
			my $inst = create_buildsystem_instance($system, build_action=>$action);
			if ($inst->is_buildable()) {
				return $inst;
			}
		}
	}
	return;
}

sub buildsystems_init {
	my %args=@_;

	# TODO: Not documented in the manual pages yet.
	# Initialize options from environment variables
	if (exists $ENV{DH_AUTO_BUILDDIRECTORY}) {
		$opt_builddir = $ENV{DH_AUTO_BUILDDIRECTORY};
	}
	if (exists $ENV{DH_AUTO_BUILDSYSTEM}) {
		$opt_buildsys = $ENV{DH_AUTO_BUILDSYSTEM};
	}

	# Available command line options
	my %options = (
	    "b:s" => \$opt_builddir,
	    "builddirectory:s" => \$opt_builddir,

	    "m=s" => \$opt_buildsys,
	    "buildsystem=s" => \$opt_buildsys,

	    "l" => \$opt_list,
	    "--list" => \$opt_list,
	);
	map { $args{options}{$_} = $options{$_} } keys(%options);
	Debian::Debhelper::Dh_Lib::init(%args);
}

sub buildsystems_list {
	my $action=shift;

	# List buildsystems (including auto and specified status)
	my ($auto, $specified);
	for my $system (@BUILDSYSTEMS) {
		my $inst = create_buildsystem_instance($system, build_action => undef);
		my $is_specified = defined $opt_buildsys && $opt_buildsys eq $inst->NAME();
		if (! defined $specified && defined $opt_buildsys && $opt_buildsys eq $inst->NAME()) {
			$specified = $inst->NAME();
		}
		elsif (! defined $auto && $inst->check_auto_buildable($action)) {
			$auto = $inst->NAME();
		}
		printf("%s - %s\n", $inst->NAME(), $inst->DESCRIPTION());
	}
	# List a specified 3rd party buildsystem too.
	if (! defined $specified && defined $opt_buildsys) {
		my $inst = create_buildsystem_instance($opt_buildsys, build_action => undef);
		printf("%s - %s.\n", $inst->NAME(), $inst->DESCRIPTION());
		$specified = $inst->NAME();
	}
	print "\n";
	print "Auto-selected: $auto\n" if defined $auto;
	print "Specified: $specified\n" if defined $specified;
	print "No system auto-selected or specified\n"
		if ! defined $auto && ! defined $specified;
}

sub buildsystems_do {
	my $action=shift;

	if (!defined $action) {
		$action = basename($0);
		$action =~ s/^dh_auto_//;
	}

	if (grep(/^\Q$action\E$/, qw{configure build test install clean}) == 0) {
		error("unrecognized build action: " . $action);
	}

	if ($opt_list) {
		buildsystems_list($action);
		exit 0;
	}

	my $buildsystem = load_buildsystem($action, $opt_buildsys);
	if (defined $buildsystem) {
		$buildsystem->pre_action($action);
		$buildsystem->$action(@_, @{$dh{U_PARAMS}});
		$buildsystem->post_action($action);
	}
	return 0;
}

1;