package ORAC::Frame;

=head1 NAME

ORAC::Frame - base class for dealing with observation frames in ORAC-DR

=head1 SYNOPSIS

  use ORAC::Frame;

  $Frm = new ORAC::Frame("filename");
  $Frm->file("prefix_flat");
  $num = $Frm->number;  


=head1 DESCRIPTION

This module provides the basic methods available to all B<ORAC::Frame>
objects. This class should be used when dealing with individual
observation files (frames).

=cut


use strict;
use Carp;
use vars qw/$VERSION/;

use ORAC::Print;
use ORAC::Constants;

'$Revision$ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);


# Setup the object structure

=head1 PUBLIC METHODS

The following methods are available in this class:

=head2 Constructors

The following constructors are available:

=over 4

=item B<new>

Create a new instance of a B<ORAC::Frame> object.  This method also
takes optional arguments: if 1 argument is supplied it is assumed to
be the name of the raw file associated with the observation. If 2
arguments are supplied they are assumed to be the raw file prefix and
observation number. In any case, all arguments are passed to the
configure() method which is run in addition to new() when arguments
are supplied.  The object identifier is returned.

   $Frm = new ORAC::Frame;
   $Frm = new ORAC::Frame("file_name");
   $Frm = new ORAC::Frame("UT", "number");

=cut


# NEW - create new instance of Frame

sub new {

  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $frame = {};  # Anon hash

  $frame->{RawName} = undef;
  $frame->{RawSuffix} = undef;
  $frame->{RawFixedPart} = undef; 
  $frame->{Header} = {};
  $frame->{Group} = undef;
  $frame->{Files} = [];
  $frame->{NoKeepArr} = [];
  $frame->{Nsubs} = undef;
  $frame->{Recipe} = undef;
  $frame->{UHeader} = {};
  $frame->{Format} = undef;
  $frame->{IsGood} = 1;
  $frame->{Intermediates} = [];

  bless($frame, $class);

  # If arguments are supplied then we can configure the object
  # Currently the argument will be the filename.
  # If there are two args this becomes a prefix and number
  # This could be extended to include a reference to a hash holding the
  # header info but this may well compromise the object since
  # the best way to generate the header (including extensions) is to use the
  # readhdr method.

  if (@_) { 
    $frame->configure(@_);
  }

  return $frame;

}

=back

=head2 Instance methods

The following methods are available for accessing the 
'instance' data.

=over 4

=cut

# Create some methods to access "instance" data
#
# With args they set the values
# Without args they only retrieve values

=item B<file>

This method can be used to retrieve or set the file names that are 
currently associated with the frame. Multiple file names can be stored
if required (for example the names associated with different 
SCUBA sub-instruments).

  $first_file = $Frm->file;     # First file name
  $first_file = $Frm->file(1);  # First file name
  $second_file= $Frm->file(2);  # Second file name
  $Frm->file(1, value);         # Set the first file name
  $Frm->file(value);            # Set the first filename
  $Frm->file(10, value);        # Set the tenth file name

Note that counting starts at 1 (and not 0 as is normal for Perl 
arrays) and that the filename can not be an integer (otherwise
it will be treated as an array index). Use files() to retrieve
all the values in an array context.

If a file has been marked as temporary (ie with the nokeep()
method) it is erased (running the erase() method) when the file
name is updated.

For example, the second file (file_2) is marked as temporary
with $Frm->nokeep(2,1). The next time the filename is updated
($Frm->file(2,'new_file')) the current file is erased before the
'new_file' name is stored. The temporary flag is then reset to
zero.

If a file number is requested that does not exist, the first
member is returned.

Every time the file name is updated, the new file is pushed onto
the intermediates() array. This is so that intermediate files
can be tidied up when required.

=cut

sub file {
  my $self = shift;
 
  # Set it to point to first member by default
  my $index = 0;

  # Check the arguments
  if (@_) {

    my $firstarg = shift;

    # If this is an integer then proceed
    # Check for int and non-zero (since strings eval as 0)
    # Cant use int() since this extracts integers from the start of a 
    # string! Match a string containing only digits
    if ($firstarg =~ /^\d+$/ && $firstarg != 0) {

      # Decrement value so that we can use it as a perl array index
      $index = $firstarg - 1;

      # If we have more arguments we are setting a value
      # else wait until we return the specified value
      if (@_) {
	# First check that the old file should not be 
	# removed before we update the object
	# [Note that the erase method calls this method...]
	$self->erase($firstarg) if $self->nokeep($firstarg);

	# Now update the filename
	$self->files->[$index] = $self->stripfname(shift);         

	# Make sure the nokeep flag is unset
	$self->nokeep($firstarg,0);

	# Push onto file history array
	push(@{$self->intermediates}, $self->files->[$index]);

      } 
    } else {
      # Since we are updating, Erase the existing file if required
      $self->erase(1) if $self->nokeep(1);

      # Just set the first value
      $self->files->[0] = $self->stripfname($firstarg);

      # Make sure the nokeep flag is unset
      $self->nokeep(1,0);

      # Push onto file history array
      push(@{$self->intermediates}, $self->files->[0]);

    }
  }

  # If index is greater than number of files stored in the
  # array return the first one
  $index = 0 if ($index > $self->nfiles - 1);

  # Nothing else of interest so return specified member
  return ${$self->files}[$index];

}

=item B<files>

Set or retrieve the array containing the current file names
associated with the frame object.

    $Frm->files(@files);
    @files = $Frm->files;

    $array_ref = $Frm->files;

In a scalar context the array reference is returned.
In an array context, the array contents are returned.

The file() method can be used to set or retrieve individual
filenames.

Note: It is possible to set and retrieve the array members using
the array reference rather than the file() method:

  $first = $Frm->files->[0];

In this approach, the file numbering starts at 0. The file() method
is the recommended way of addressing individual members of this
array since the file() method could do extra processing of the
string (especially when setting the value, for example the automatic
deletion of temporary files).

=cut
 
sub files {
  my $self = shift;
  if (@_) { @{ $self->{Files} } = @_;}

  if (wantarray) {

    # In an array context, return the array itself
    return @{ $self->{Files} } if wantarray();
 
  } else {
    # In a scalar context, return the reference to the array
    return $self->{Files};
  }
}

=item B<format>

Data format associated with the current file().
Usually one of 'NDF' or 'FITS'.

=cut

sub format {
  my $self = shift;
  if (@_) { $self->{Format} = shift; }
  return $self->{Format};
}

=item B<group>

This method returns the group name associated with the observation.

  $group_name = $Frm->group;
  $Frm->group("group");

This can be configured initially using the findgroup() method.
Alternatively, findgroup() is run automatically by the configure()
method.

=cut


sub group {
  my $self = shift;
  if (@_) { $self->{Group} = shift;}
  return $self->{Group};
}

=item B<hdr>

This method allows specific entries in the header to be accessed.  In
general, this header is related to the actual header information
stored in the Frame file. The input argument should correspond to the
keyword in the header hash.

  $tel = $Frm->hdr("TELESCOP");
  $instrument = $Frm->hdr("INSTRUME");

Can also be used to set values in the header.
A hash can be used to set multiple values (but does not overwrite
other keys).

  $Frm->hdr("INSTRUME" => "IRCAM");
  $Frm->hdr("INSTRUME" => "SCUBA", 
            "TELESCOP" => 'JCMT');

If no arguments are provided, the reference to the header hash
is returned.

  $Frm->hdr->{INSTRUME} = 'SCUBA';

The header can be populated from the file by using the readhdr()
method.

=cut

sub hdr {
  my $self = shift;

  # If we have one argument we should read it and return the associated
  # value. If we have more than one argument will assume a hash has
  # been supplied and append it to the existing values.
  if (@_) {
    if (scalar(@_) == 1) {
      my $key = shift;
      return $self->{Header}->{$key};
    } else {

      # Assume we are setting keys, append to the existing
      # hash. Can either do this by merging the two hashes
      # (inefficient since we have to take an entire copy
      # of the existing hash) or by looping through the supplied
      # keys and changing them one by one. The former is more 
      # efficient for large lists, the latter when only supplying
      # a few arguments. For programming simplicity will take
      # the former approach

      %{ $self->{Header} } = ( %{ $self->{Header} }, @_ );
    }
  } else {
    # No arguments, return the header hash reference
    return $self->{Header};
  }
}

=item B<intermediates>

An array containing all the intermediate file names used
during processing. Filenames are pushed onto this array
whenever the file() method is used to update the current
file information.

  $Frm->intermediates(@files);
  @files = $Frm->intermediates;
  push(@{$Frm->intermediates}, $file);
  $first = $Frm->intermediates->[0];

As for the files() method, returns an array reference when
called in a scalar context and an array of file names when
called from an array context.

The array does not store information relating to the position
of the file in the files() array [ie was it stored as
$Frm->file(1) or $Frm->file(2)]. The order simply reflects the
order the files were given to the file() method.

=cut
 
sub intermediates {
  my $self = shift;
  if (@_) { @{ $self->{Intermediates} } = @_;}

  if (wantarray) {

    # In an array context, return the array itself
    return @{ $self->{Intermediates} } if wantarray();
 
  } else {
    # In a scalar context, return the reference to the array
    return $self->{Intermediates};
  }
}


=item B<isgood>

Flag to determine the current state of the frame. If isgood()
is true the Frame is valid. If it returns false the frame
object may have a problem (eg the recipe responsible for 
processing the frame failed to complete).

This flag is used by the B<ORAC::Group> class to determine
membership.

=cut

sub isgood {
  my $self = shift;
  if (@_) { $self->{IsGood} = shift;  }
  $self->{IsGood} = 1 unless defined $self->{IsGood};
  return $self->{IsGood};
}

=item B<nokeep>

Flag used to determine whether the current filename should be
erased when the file() method is next used to update the current
filename.

  $Frm->erase($i) if $Frm->nokeep($i);

  $Frm->nokeep($i, 1);  # make ith file temporary
  $Frm->nokeep($i, 0);  # Make ith file permanent

  $nokeep = $Frm->nokeep($i);

The mandatory first argument specifies the file number associated with
this flag (same scheme as used by the file() method). An optional
second argument can be used to set the flag. 'True' indicates that the
file should not be kept, 'false' indicates that the file is permanent.

=cut

sub nokeep {
  my $self = shift;

  croak 'Usage: $Frm->nokeep(file_number,[value]);'
    unless @_;

  my $num = shift;

  # Convert this number to an array index
  my $index = $num - 1;

  # If we have another argument we are setting the value
  if (@_) {
    $self->nokeepArr->[$index] = shift;
  }

  return $self->nokeepArr->[$index];

}

=item B<nokeepArr>

Array of flags. Used internally by nokeep() method.  Set or retrieve
the array containing the flags used by the nokeep() method to
determine whether the current filename should be erased when the
file() method is next used to update the current filename.

    $Frm->nokeepArr(@flags);
    @flags = $Frm->nokeepArr;

    $array_ref = $Frm->nokeepArr;

In a scalar context the array reference is returned.
In an array context, the array contents are returned.

The nokeep() method can be used to set or retrieve individual
flags (the numbering scheme is different).

Note: It is possible to set and retrieve the array members using
the array reference rather than the nokeep() method:

  $first = $Frm->nokeepArr->[0];

In this approach, the numbering starts at 0. The nokeep() method
is the recommended way of addressing individual members of this
array since it could do extra processing of the
string.

=cut
 
sub nokeepArr {
  my $self = shift;
  if (@_) { @{ $self->{NoKeepArr} } = @_;}

  if (wantarray) {

    # In an array context, return the array itself
    return @{ $self->{NoKeepArr} } if wantarray();
 
  } else {
    # In a scalar context, return the reference to the array
    return $self->{NoKeepArr};
  }
}

=item B<nsubs>

Return the number of sub-frames associated with this frame.
If the object has a value of undef (ie a new object) the findnsubs()
method is automatically invoked to determine the number of sub-frames.

nfiles() should be used to return the current number of sub-frames
associated with the frame (nsubs usually only reports the number given
in the header and may or may not be the same as the number of sub-frames
currently stored)

Usually this value is set as part of the configure() method from
the header (using findnsubs()).

=cut

sub nsubs {
  my $self = shift;
  if (@_) { $self->{Nsubs} = shift; };

  unless (defined $self->{Nsubs}) {
    $self->findnsubs;
  }

  return $self->{Nsubs};
}

# Method to return/set the filename of the raw data
# Initially this is the same as {File}


=item B<raw>

This method returns (or sets) the name of the raw data file
associated with this object.

  $Frm->raw("raw_data");
  $filename = $Frm->raw;

=cut

sub raw {
  my $self = shift;
  if (@_) { $self->{RawName} = shift; }
  return $self->{RawName};
}


=item B<rawfixedpart>

Return (or set) the constant part of the raw filename associated
with the raw data file. (ie the bit that stays fixed for every 
observation)

  $fixed = $self->rawfixedpart;

=cut

sub rawfixedpart {
  my $self = shift;
  if (@_) { $self->{RawFixedPart} = shift; }
  return $self->{RawFixedPart};
}

=item B<rawsuffix>

Return (or set) the file name suffix associated with
the raw data file.

  $suffix = $self->rawsuffix;

=cut

sub rawsuffix {
  my $self = shift;
  if (@_) { $self->{RawSuffix} = shift; }
  return $self->{RawSuffix};
}

# Method to return the recipe name
# If an argument is supplied the recipe is set to that value
# If the recipe is undef then the findrecipe method is invoked to set it


=item B<recipe>

This method returns the recipe name associated with the observation.
The recipe name can be set explicitly but in general should be
set by the findrecipe() method.

  $recipe_name = $Frm->recipe;
  $Frm->recipe("recipe");

This can be configured initially using the findrecipe() method.
Alternatively, findrecipe() is run automatically by the configure()
method.

=cut


sub recipe {
  my $self = shift;
  if (@_) { $self->{Recipe} = shift;}
  return $self->{Recipe};
}



=item B<uhdr>

This method allows specific entries in the user-defined header to be 
accessed. The input argument should correspond to the keyword in the header
hash.

  $tel = $Frm->uhdr("Telescope");
  $instrument = $Frm->uhdr("Instrument");

Can also be used to set values in the header.
A hash can be used to set multiple values (but does not overwrite
other keys).

  $Frm->uhdr("Instrument" => "IRCAM");
  $Frm->uhdr("Instrument" => "SCUBA", 
             "Telescope" => 'JCMT');

If no arguments are provided, the reference to the header hash
is returned.

  $Frm->uhdr->{Instrument} = 'SCUBA';

=cut



sub uhdr {
  my $self = shift;

  # If we have one argument we should read it and return the associated
  # value. If we have more than one argument will assume a hash has
  # been supplied and append it to the existing values.
  if (@_) {
    if (scalar(@_) == 1) {
      my $key = shift;
      return $self->{UHeader}->{$key};
    } else {

      # Assume we are setting keys, append to the existing
      # hash. Can either do this by merging the two hashes
      # (inefficient since we have to take an entire copy
      # of the existing hash) or by looping through the supplied
      # keys and changing them one by one. The former is more 
      # efficient for large lists, the latter when only supplying
      # a few arguments. For programming simplicity will take
      # the former approach

      %{ $self->{UHeader} } = ( %{ $self->{UHeader} }, @_ );
    }
  } else {
    # No arguments, return the header hash reference
    return $self->{UHeader};
  }
}


=back

=head2 General Methods

The following methods are provided for manipulating
B<ORAC::Frame> objects:

=over 4

=item B<calc_orac_headers>

This method calculates header values that are required by the
pipeline by using values stored in the header.

Required ORAC extensions are:

ORACTIME: should be set to a decimal time that can be used for
comparing the relative start times of frames. For IRCAM this
number is decimal hours, for SCUBA this number is decimal
UT days.

ORACUT: This is the UT day of the frame in YYYYMMDD format.

This method should be run after a header is set. Currently the header()
method calls this whenever it is updated.

This method updates the frame header.
Returns a hash containing the new keywords.

=cut

sub calc_orac_headers {
  my $self = shift;

  my %new = ();  # Hash containing the derived headers

  # ORACTIME
  # For IRCAM the keyword is simply RUTSTART
  # Just return it (zero if not available)
  my $time = $self->hdr('RUTSTART');
  $time = 0 unless (defined $time);
  $self->hdr('ORACTIME', $time);

  $new{'ORACTIME'} = $time;

  # ORACUT
  # For IRCAM this is simply the IDATE header value
  my $ut = $self->hdr('IDATE');
  $ut = 0 unless defined $ut;
  $self->hdr('ORACUT', $ut);

  return %new;
}

=item B<configure>

This method is used to configure the object. It is invoked
automatically if the new() method is invoked with an argument. The
file(), raw(), readhdr(), findgroup(), findrecipe and findnsubs()
methods are invoked by this command. Arguments are required.  If there
is one argument it is assumed that this is the raw filename. If there
are two arguments the filename is constructed assuming that argument 1
is the prefix and argument 2 is the observation number.

  $Frm->configure("fname");
  $Frm->configure("UT","num");

=cut

sub configure {
  my $self = shift;

  # If two arguments (prefix and number) 
  # have to find the raw filename first
  # else assume we are being given the raw filename
  my $fname;
  if (scalar(@_) == 1) {
    $fname = shift;
  } elsif (scalar(@_) == 2) {
    $fname = $self->file_from_bits(@_);
  } else {
    croak 'Wrong number of arguments to configure: 1 or 2 args only';
  }

  # Set the filename
  $self->file($fname);

  # Set the raw data file name
  $self->raw($fname);

  # Populate the header
  $self->readhdr;

  # Find the group name and set it
  $self->findgroup;

  # Find the recipe name
  $self->findrecipe;

  # Find nsubs
  $self->findnsubs;

  # Return something
  return 1;
}


=item B<erase>

Erase the current file from disk.

  $Frm->erase($i);

The optional argument specified the file number to be erased.
The argument is identical to that given to the file() method.
Returns ORAC__OK if successful, ORAC__ERROR otherwise.

Note that the file() method is not modified to reflect the
fact the the file associated with it has been removed from disk.

This method is usually called automatically when the file()
method is used to update the current filename and the nokeep()
flag is set to true. In this way, temporary files can be removed
without explicit use of the erase() method. (Just need to
use the nokeep() method after the file() method has been used
to update the current filename).

=cut

sub erase {
  my $self = shift;

  # Retrieve the necessary frame name
  my $file = $self->file(@_);

  my $status = unlink $file;

  return ORAC__ERROR if $status == 0;
  return ORAC__OK;
}


# 


=item B<file_from_bits>

Determine the raw data filename given the variable component
parts. A prefix (usually UT) and observation number should
be supplied.

  $fname = $Frm->file_from_bits($prefix, $obsnum);

=cut

sub file_from_bits {
  my $self = shift;

  my $prefix = shift;
  my $obsnum = shift;

  # In this case (since this is generic) simply return
  # a combination. Use the IRCAM model by default
  # since this is a UKIRT designed system (<duck> - timj)
  return $self->rawfixedpart . $prefix . '_' . $obsnum . $self->rawsuffix;

}


=item B<findgroup>

Method to determine the group to which the observation belongs.
The default method is to look for a "GRPNUM" entry in the header.

  $group = $Frm->findgroup;

The object is automatically updated via the group() method.

=cut

sub findgroup {
  my $self = shift;

  # Simplistic routine that simply returns the GRPNUM
  # entry in the header
  my $group = $self->hdr->{GRPNUM};
  $self->group($group);
  return $group;

}

=item B<findnsubs>

Find the number of sub-frames associated with the frame by looking in
the header. Usually run by configure().

In the base class this method looks for a header keyword of 'NSUBS'.

  $nsubs = $Frm->findnsubs;

The state of the object is updated automatically.

=cut

sub findnsubs {
  my $self = shift;
  my $nsubs = $self->hdr->{N_SUBS};
  $self->nsubs($nsubs);
  return $nsubs
}

=item B<findrecipe>

Method to determine the recipe name that should be used to reduce
the observation.
The default method is to look for a "RECIPE" entry in the header.

  $recipe = $Frm->findrecipe;

The object is automatically updated to reflect this recipe.

=cut


sub findrecipe {
  my $self = shift;

  # Simplistic routine that simply returns the RECIPE
  # entry in the header
  my $recipe = $self->hdr->{RECIPE};
  $self->recipe($recipe);
  return $recipe;
}

=item B<flag_from_bits>

Determine the name of the flag file given the variable
component parts. A prefix (usually UT) and observation number
should be supplied

  $flag = $Frm->flag_from_bits($prefix, $obsnum);

This particular method returns back the flag file associated with
UFTI.

=cut

# Note - I don't agree that the base class should consist
# of a mishmash of code related to many different instruments
# depending on which sub came first. The file_from_bits
# base method returns back the IRCAM specification and the flag_from_bits
# base method returns a value in the UFTI style!!! (TimJ)
# They only work together if the sub-classing is taken into account!

sub flag_from_bits {
  my $self = shift;

  my $prefix = shift;
  my $obsnum = shift;
  
  # It is almost possible to derive the flag name from the 
  # file name but not quite. In the UFTI case the flag name
  # is  .UT_obsnum.fits.ok but the filename is fUT_obsnum.fits

  # Retrieve the data file name
  my $raw = $self->file_from_bits($prefix, $obsnum);

  # Replace the 'f' with a '.' and append '.fits'
  substr($raw,0,1) = '.';
  $raw .= '.ok';
}


=item B<gui_id>

Returns the identification string that is used to compare the
current frame with the frames selected for display in the
display definition file.

Arguments:

 number - the file number (as accepted by the file() method)
          Starts counting at 0. If no argument is supplied
          a 1 is assumed.

To return the ID associated with the second frame:

 $id = $Frm->gui_id(2);

If nfiles() equals 1, this method returns everything after the last
suffix (using an underscore) from the filename stored in file(1). If
nfiles > 1, this method returns the everything after the last 
underscore, prepended with 's$number'. ie if file(2) is test_dk,
the ID would be 's2dk'; if file() is test_dk (and nfiles = 1) the
ID would be 'dk'.

=cut

sub gui_id {
  my $self = shift;

  # Read the number
  my $num = 1;
  if (@_) { $num = shift; }

  # Retrieve the Nth file name (start counting at 1)
  my $fname = $self->file($num);

  # Split on underscore
  my (@split) = split(/_/,$fname);

  my $id = $split[-1];

  # Find out how many files we have 
  my $nfiles = $self->nfiles;

  # Prepend wtih s$num if nfiles > 1
  # This is to make it simple for instruments that only ever
  # sotre one frame (eg UFTI)
  $id = "s$num" . $id if $nfiles > 1;

  return $id;

}


=item B<inout>

Method to return the current input filename and the new output
filename given a suffix.  For the base class the input filename is
chopped at the last underscore and the suffix appended when the name
contains at least 2 underscores. The suffix is simply appended if
there is only one underscore. This prevents numbers being chopped when
the name is of the form ut_num.

Note that this method does not set the new output name in this
object. This must still be done by the user.

Returns $in and $out in an array context:

   ($in, $out) = $Frm->inout($suffix);

Returns $out in a scalar context:

   $out = $Frm->inout($suffix);

Therefore if in=file_db and suffix=_ff then out would
become file_db_ff but if in=file_db_ff and suffix=dk then
out would be file_db_dk.

An optional second argument can be used to specify the
file number to be used. Default is for this method to process
the contents of file(1).

  ($in, $out) = $Frm->inout($suffix, 2);

will return the second file name and the name of the new output
file derived from this.

=cut

sub inout {

  my $self = shift;
 
  my $suffix = shift;

  # Read the number
  my $num = 1; 
  if (@_) { $num = shift; }
  
  my $infile = $self->file($num);

  # Chop off at last underscore
  # Must be able to do this with a clever pattern match
  # Want to use s/_.*$// but that turns a_b_c to a and not a_b

  # instead split on underscore and recombine using underscore
  # but ignoring the last member of the split array
  my (@junk) = split(/_/,$infile);

  # We only want to drop the SECOND underscore. If we only have
  # two components we simply append. If we have more we drop the last
  # This prevents us from dropping the observation number in 
  # ro970815_28

  my $outfile;
  if ($#junk > 1) {
    $outfile = join("_", @junk[0..$#junk-1]);
  } else {
    $outfile = $infile;
  }

  # Now append the suffix to the outfile
  $outfile .= $suffix;

  # Generate a warning if output file equals input file
  orac_warn("inout - output filename equals input filename ($outfile)\n")
    if ($outfile eq $infile);

  return ($infile, $outfile) if wantarray();  # Array context
  return $outfile;                            # Scalar context
}


=item B<nfiles>

Number of files associated with the current state of the object and
stored in file(). This method lets the caller know whether an
observation has generated multiple output files for a single input.

=cut

sub nfiles {
  my $self = shift;
  my $num = $#{$self->files} + 1;
  return $num;
}

# Supply a method to return the number associated with the observation

=item B<number>

Method to return the number of the observation. The number is
determined by looking for a number at the end of the raw data
filename.  For example a number can be extracted from strings of the
form textNNNN.sdf or textNNNN, where NNNN is a number (leading zeroes
are stripped) but not textNNNNtext (number must be followed by a decimal
point or nothing at all).

  $number = $Frm->number;

The return value is -1 if no number can be determined.

As an aside, an alternative approach for this method (especially
in a sub-class) would be to read the number from the header.

=cut


sub number {

  my $self = shift;

  my ($number);

  # Get the number from the raw data
  # Assume there is a number at the end of the string
  # (since the extension has already been removed)
  # Leading zeroes are dropped

  if ($self->raw =~ /(\d+)(\.\w+)?$/) {
    # Drop leading 00
    $number = $1 * 1;
  } else {
    # No match so set to -1
    $number = -1;
  }

  return $number;

}


# Method to read header information from the file directly
# Put it separately so that we do not need to specify how we read
# header or whether we include NDF extensions
# Returns reference to hash
# No input arguments - only assumes that the object knows the name of the
# file associated with it

=item B<readhdr>

A method that is used to read header information from the current
file and store that information in the object. For the base class,
this method does nothing since the base class does not know 
the format of the file associated with the object. There are
no return arguments.

  $Frm->readhdr;

The calc_orac_headers() method is called automatically.

=cut

sub readhdr {
  my $self = shift;
  $self->calc_orac_headers;
  return;
}


=item B<template>

Method to change the current filename of the frame (file())
so that it matches a template. e.g.:

  $Frm->template("something_number_flat");

Would change the first file to match "something_number_flat".
Essentially this simply means that the number in the template
is changed to the number of the current frame object.

  $Frm->template("something_number_dark", 2);

would change the second filename to match "something_number_dark".
The base method assumes that the filename matches the form:
prefix_number_suffix. This must be modified by the derived
classes since in general the filenaming convention is telescope
and instrument specific.

The Nth filename is modified (ie file(N)).
There are no return arguments.

=cut

sub template {
  my $self = shift;
  my $template = shift;

  my $fnum = 1;
  if (@_) { $fnum = shift; };

  my $num = $self->number;
  # Change the first number
  $template =~ s/_\d+_/_${num}_/;

  # Update the filename
  $self->file($template, $fnum);

}


# Private method for removing file extensions from the filename strings

=back

=head1 PRIVATE METHODS

The following methods are intended for use inside the module.
They are included here so that authors of derived classes are 
aware of them.

=cut

# Private method for removing file extensions from the filename strings
# In the base class this does nothing. It is up to the derived classes
# To do something special with this.

=over 4

=item stripfname

Method to strip file extensions from the filename string. This method
is called by the file() method. For the base class this method
does nothing. It is intended for derived classes (e.g. so that ".sdf"
can be removed). 

=cut


sub stripfname {

  my $self = shift;

  my $name = shift;

  return $name;

}

# Deprecated

sub header {
  my $self = shift;
  carp 'The Frame header() method is no longer supported - use hdr() instead';
  return $self->{Header};
}

sub userheader {
  my $self = shift;
   carp 'The Frame userheader() method is no longer supported - use uhdr() instead';
  return $self->{UHeader};
}


=back

=head1 SEE ALSO

L<ORAC::Group>

=head1 REVISION

$Id$

=head1 AUTHORS

Tim Jenness (t.jenness@jach.hawaii.edu)
Frossie Economou (frossie@jach.hawaii.edu)    

=cut

1;

