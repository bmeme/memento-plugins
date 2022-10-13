#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";

package Memento::Tool::plugins;

use feature 'say';
our @ISA = qw(Memento::Command);
use strict; use warnings;
use version;

# List installed plugins
sub list {
  my $class = shift;
  my $arguments = shift;
  my $params = shift;
  
  my %plugins_list = _get_plugins_data();

  say "Plugin list:";
  foreach my $plugin_key (keys %plugins_list) {
    say "  " . $plugins_list{$plugin_key}{'name'} . " (". $plugins_list{$plugin_key}{'version'} . ")";
  }
}

# Add a new plugin, given its repository URL and the target directory name.
sub add {
  my $class = shift;
  my $plugin_url = shift;
  my $plugin_dir_name = shift;

  if (!$plugin_url) {
      $plugin_url = Daemon::prompt("Plugin repository URL");
  }

  if (!$plugin_dir_name) {
      $plugin_dir_name = Daemon::prompt("Plugin directory");
  }

  my $custom_plugins_directory = _get_custom_plugins_directory();
  my $plugin_dir = "${custom_plugins_directory}/${plugin_dir_name}";
  
  system("git clone --quiet ${plugin_url} ${plugin_dir}");

  my $file = "${plugin_dir}/.memento";
  my %plugin_data = _read_memento_plugin_config_file($file);
  
  say "Installed version " . $plugin_data{'version'} . " of plugin " . $plugin_data{'name'};
}

# List outdated plugins
sub outdated {

  my %plugins_outdated = _get_plugins_outdated(1);

  say "";

  my $size = keys %plugins_outdated;
  if ( $size > 0 ) {
    foreach my $plugin_key (keys %plugins_outdated) {
      say "A new version (" . $plugins_outdated{$plugin_key}{'new_version'} . ") is available for plugin " . $plugins_outdated{$plugin_key}{'name'} . " (" . $plugins_outdated{$plugin_key}{'version'} . ")";
    }
  } else {
    say "All plugins are up to date!";
  }

}

# Upgrade a plugin
sub upgrade {
  my $class = shift;
  my $plugin = shift;

  my %plugins_outdated = _get_plugins_outdated();
  my @plugins = keys %plugins_outdated;
  my $size = keys %plugins_outdated;

  if ( $size > 0 ) {
    if (!$plugin || !Daemon::in_array([@plugins], $plugin)) {
        $plugin = Daemon::prompt("Choose a plugin to update", '', [@plugins]);
    }

    my $plugin_dir = $plugins_outdated{$plugin}{'dir'};
    my $plugin_url = $plugins_outdated{$plugin}{'url'};
    system("rm -rf ${plugin_dir}");
    system("git clone --quiet ${plugin_url} ${plugin_dir}");

    say "Plugin " . $plugins_outdated{$plugin}{'name'} . " updated to version " . $plugins_outdated{$plugin}{'new_version'};
  } else {
    say "All plugins are up to date!";
  }
}


# OVERRIDDEN METHODS ###########################################################



# PRIVATE METHODS ##############################################################

# Return the absolute path of Memento custom plugins directory
sub _get_custom_plugins_directory {

  my $root = Memento::Tool->root();
  my $custom_commands_dir = "Memento/Tool/custom";

  return "$root/$custom_commands_dir";
}

# Read data from a memento plugin config file
#
# Expected file format:
# NAME=plugin-name
# VERSION=plugin-version
# URL=plugin-url
#
# Return a hash variable with the following keys: name, version, url.
sub _read_memento_plugin_config_file {

  my $file = shift;

  if ( -e $file) {
    open(FH, '<', $file) or die "Can't read file ${file}: $!";
    my $name; 
    my $version;
    my $url;
    while(<FH>) {
      if ( $_ =~ /^NAME=\s*(\S+)\s*$/ ) { $name = $1; };
      if ( $_ =~ /^VERSION=\s*(\S+)\s*$/ ) { $version = $1; };
      if ( $_ =~ /^URL=\s*(\S+)\s*$/ ) { $url = $1; };
    }
    close(FH);
    my %plugin_data = (
      name => $name, 
      version => $version,
      url => $url 
    );

    return %plugin_data;
  } else {
    die "File ${file} not found!";
  }

}

# Retrieve data of installed plugins
#
# Scans custom plugins directory: if a subdirectory contains 
# a file named .memento, it is evaluated as a memento plugin
#
# Return a hash variable where the keys are plugin names.
# Every value of this hash is a hash that contains plugin data,
# with the following keys: name, version, url, dir, dir_name.
sub _get_plugins_data {

  my %plugins_list;
  my $custom_plugins_directory = _get_custom_plugins_directory();

  my @custom_commands_dirs = `cd $custom_plugins_directory; ls -d */`;
  foreach my $custom_dir (@custom_commands_dirs) {
      chomp $custom_dir;
      $custom_dir =~ s/\/?$//;
      my $plugin_dir = "$custom_plugins_directory/${custom_dir}";
      my $file = "${plugin_dir}/.memento";
      if ( -e $file ) {
        my %plugin_data = _read_memento_plugin_config_file($file);
        $plugin_data{'dir_name'} = $custom_dir;
        $plugin_data{'dir'} = $plugin_dir;
        $plugins_list{$plugin_data{'name'}} = { %plugin_data };
      }
  }

  return %plugins_list
}

# Retrieve data of outdated plugins
#
# Use _get_plugins_data to retrieve the plugin list.
# For every plugin found, the repository is cloned in a temp directory
# and the downloaded version is compared against the installed one.
#
# Return a hash variable that contains the list of outdated plugins.
# The hash format is the same of _get_plugins_data, but with plugin data
# augmented with a key named new_version. 
sub _get_plugins_outdated {

  my $verbose = shift;
  
  my %plugins_list = _get_plugins_data();
  my %plugins_outdated;
  
  foreach my $plugin_key (keys %plugins_list) {
    $verbose && say "Checking plugin ${plugin_key} for updates...";
    my $dir_name = $plugins_list{$plugin_key}{'dir_name'};
    my $url = $plugins_list{$plugin_key}{'url'};
    my $tmp_dir = "/tmp/memento_plugin_${dir_name}";
    system("rm -rf ${tmp_dir} && mkdir ${tmp_dir}");
    system("git clone --quiet ${url} ${tmp_dir} 2>&1 > /dev/null");

    my $file = "${tmp_dir}/.memento";
    if ( -e $file ) {
      my $version;
      open(FH, '<', $file) or die "Can't read file ${file}: $!";
      while(<FH>) {
        if ( $_ =~ /^VERSION=\s*(\S+)\s*$/ ) { $version = $1; };
      }
      close(FH);

      if ( version->parse($version) > version->parse($plugins_list{$plugin_key}{'version'}) ) {
        $plugins_outdated{$plugin_key} = {
          name => $plugins_list{$plugin_key}{'name'},
          version => $plugins_list{$plugin_key}{'version'},
          new_version => $version,
          dir => $plugins_list{$plugin_key}{'dir'},
          dir_name => $plugins_list{$plugin_key}{'dir_name'},
          url => $plugins_list{$plugin_key}{'url'}
        };
      }
    }
  }

  return %plugins_outdated;
}

1;
