package ORAC::Msg::Control::AMS;


=head1 NAME

ORAC::Msg::Control::AMS - control and initialise ADAM messaging from ORAC

=head1 SYNOPSIS

  use ORAC::Msg::Control::AMS;

  $ams = new ORAC::Msg::Control::AMS(1);
  $ams->init;

  $ams->messages(0);
  $ams->errors(1);
  $ams->timeout(30);
  $ams->stderr(\*ERRHANDLE);
  $ams->stdout(\*MSGHANDLE);
  $ams->paramrep( sub { return "!" } );

=head1 DESCRIPTION

Methods to initialise the ADAM messaging system (AMS) and control the
behaviour.

=head1 METHODS

The following methods are available:

=head2 Constructor

=over 4

=cut


use strict;
use Carp;

use vars qw/$VERSION/;

'$Revision$ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);


# Need to do some tests before using this for real
# since some monoliths do not realise that the error
# generated by NOPROMPT is effectively a PAR__ABORT
#BEGIN {
#  $ENV{ADAM_NOPROMPT} = '1';
#}


# This needs to Starlink module
use Starlink::AMS::Init '1.00';

# Derive all methods from the Starlink module since this
# behaves in exactly the same way.

use base qw/Starlink::AMS::Init/;



=item B<new>

Create a new instance of Starlink::AMS::Init.
If a true argument is supplied the messaging system is also
initialised via the init() method.

=back

=head2 Accessor Methods

=over 4

=item B<messages>

Method to set whether standard messages returned from monoliths
are printed or not. If set to true the messages are printed
else they are ignored.

  $current = $ams->messages;
  $ams->messages(0);

Default is to print all messages.

=item B<errors>

Method to set whether error messages returned from monoliths
are printed or not. If set to true the errors are printed
else they are ignored.

  $current = $ams->errors;
  $ams->errors(0);

Default is to print all messages.

=item B<timeout>

Set or retrieve the timeout (in seconds) for some of the ADAM messages.
Default is 30 seconds.

  $ams->timeout(10);
  $current = $ams->timeout;

=item B<stderr>

Set and retrieve the current filehandle to be used for printing
error messages. Default is to use STDERR.

=item B<stdout>

Set and retrieve the current filehandle to be used for printing
normal ADAM messages. Default is to use STDOUT. This can be
a tied filehandle (eg one generated by ORAC::Print).

=item B<paramrep>

Set and retrieve the code reference that will be executed if
the parameter system needs to ask for a parameter.
Default behaviour is to call a routine that simply prompts
the user for the required value. The supplied subroutine
should accept three arguments (the parameter name, prompt string and
default value) and should return the required value.

  $self->paramrep(\&mysub);

A simple check is made to make sure that the supplied argument
is a code reference.

Warning: It is possible to get into an infinite loop if you try
to continually return an unacceptable answer.

=back

=head2 General Methods

=over 4

=item B<init>

Initialises the ADAM messaging system. This routine should always be
called before attempting to control I-tasks.

A relay task is spawned in order to test that the messaging system
is functioning correctly. The relay itself is not necessary for the
non-event loop implementation. If this command hangs then it is
likely that the messaging system is not running correctly (eg
because the system was shutdown uncleanly.

  $ams->init( $preserve );

For ORAC-DR the message system directories are set to
values that will allow multiple oracdr pipelines to run
without interfering with each other.

Scratch files are written to ORACDR_TMP directory if defined,
else ORAC_DATA_OUT is used. By default ADAM_USER is set
to be a directory in the scratch file directory. This can be
overridden by supplying an optional flag.

If C<$preserve> is true, ADAM_USER will be left untouched. This
enables the pipeline to talk to tasks created by other applications
but does mean that the users ADAM_USER may be filled with unwanted
temporary files. It also has the added problem that on shutdown
the ADAM_USER directory is removed by ORAC-DR, this should not happen
if C<$preserve> is true but is not currently guaranteed.


=cut

sub init {
  my $self = shift;

  # Read flag to control private invocation of message system
  my $preserve = 0;
  $preserve = shift if @_;

  # Set ADAM environment variables
  # process-specific adam dir

  # Use ORACDR_TMP, then ORAC_DATA_OUT else /tmp as ADAM_USER directory.
  # Unless we are instructed to preserve ADAM_USER
  my $dir = "adam_$$";

  unless ($preserve) {

    if (exists $ENV{ORACDR_TMP} && defined $ENV{ORACDR_TMP}
        && -d $ENV{ORACDR_TMP}) {

      $ENV{'ADAM_USER'} = $ENV{ORACDR_TMP}."/$dir";

    } elsif (exists $ENV{'ORAC_DATA_OUT'} && defined $ENV{ORAC_DATA_OUT}
             && -d $ENV{ORAC_DATA_OUT}) {

      $ENV{'ADAM_USER'} = $ENV{ORAC_DATA_OUT} . "/$dir";

    } else {
      $ENV{'ADAM_USER'} = "/tmp/$dir";
    }

  }

  # Set HDS_SCRATCH -- unless it is defined already
  # Do not need to set to ORAC_DATA_OUT since this is cwd.

  # Want to modify this variable so that we can fix some ndf2fits
  # feature (etc ?) -- I think the problem came up when trying to convert
  # files from one directory to another when the input directory is
  # read-only...

  unless (exists $ENV{HDS_SCRATCH}) {
    if (exists $ENV{ORACDR_TMP} && defined $ENV{ORACDR_TMP}
        && -d $ENV{ORACDR_TMP}) {
      $ENV{HDS_SCRATCH} = $ENV{ORACDR_TMP};
    }
  }

  # Start messaging by calling base class
  $self->SUPER::init;
}


=back

=head1 CLASS METHODS

=over 4

=item B<require_uniqid>

Returns true, indicating that the ADAM "engine" identifiers must
be unique in the client each time an engine is launched.

=cut

sub require_uniqid {
  return 1;
}

=back

=head1 REQUIREMENTS

This module requires the Starlink::AMS::Init module.

=head1 SEE ALSO

L<Starlink::AMS::Init>

=head1 REVISION

$Id$

=head1 AUTHORS

Tim Jenness (t.jenness@jach.hawaii.edu)
and Frossie Economou (frossie@jach.hawaii.edu)

=head1 COPYRIGHT

Copyright (C) 1998-2000 Particle Physics and Astronomy Research
Council. All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut


1;
