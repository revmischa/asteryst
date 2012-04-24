=head1 Asteryst::AGI::Jumpfile

A "jumpfile" is a file that starts n seconds into another file.  It's a way of
implementing fast-forward, pause, and rewind (at present, the only way we know).

=cut

package Asteryst::AGI::Jumpfile;

use Moose;

use Data::Dump 'pp';
use File::Temp 'tempfile';

has offset_in_seconds => (
    is  => 'rw',
);

has _offset_in_bytes => (
    is  => 'rw',
);

has input_path => (
    is  => 'rw',
);

has file_length => (
    is  => 'rw',
    isa => 'Int',
);

has output_path => (
    is  => 'rw',
    isa => 'Str',
);

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;

    print STDERR 'Jumpfile BUILDARGS \\@_:  ', pp(\@_), "\n" if 0;
    print STDERR 'Jumpfile BUILDARGS \\%args:  ', pp(\%args), "\n" if 0;

    # lame hack to find offset in bytes from seconds (sample rate = 8k samples/sec)
    my $byte_offset = 8000 * $args{offset_in_seconds};

    # don't seek before beginning of file
    if ($byte_offset < 0) { $byte_offset = 0 };

    $args{_offset_in_bytes} = $byte_offset;
    return $class->$orig(%args);
};

sub BUILD {
    my ($self) = @_;
    $self->write_file;
    return;
}

=head2

L<write_file()> - writes the file, to a path in /tmp that's guaranteed not to
conflict with an existing path.

RETURN VALUE:  the path to the output "jumpfile."

DIAGNOSTICS:  if there is a problem opening the output file, dies
with a string error (from Temp::File).  If there is any other I/O
problem, dies with an autodie::exception (from the autodie pragma).

=cut
sub write_file {
    my ($self) = @_;
    use autodie ':io';
    my $debug = 1;

    print STDERR 'Input path:  ',  $self->input_path, "\n" if $debug;
    print STDERR 'Byte offset:  ', $self->_offset_in_bytes, "\n" if $debug;
    open my $in_fh, '<', $self->input_path;
    seek $in_fh, $self->_offset_in_bytes, 0;
    my $content;
    {
	local $/ = undef; # slurp whole files
	$content = <$in_fh>;
    }
    close $in_fh;

    # TODO:  use the suffix of the original file; don't hard-code '.sln'.
    my ($out_fh, $output_path) = tempfile(SUFFIX => '.sln', UNLINK => 0);
    $self->output_path($output_path);
    print STDERR "Jumpfile output_path:  $output_path\n" if $debug;

    my $input_bytes = -l $self->input_path
                    ? (lstat $self->input_path)[7]
                    : (stat $self->input_path)[7];

    print STDERR 'Input file is ', $input_bytes, " bytes long\n" if $debug;
    if ($self->_offset_in_bytes > $input_bytes) {
        # The caller tried to skip past the end of the file.
	    # Write a zero-length jumpfile.
	    print STDERR "Writing zero-length jumpfile\n" if $debug;
	    $self->file_length(0);
    } elsif ($self->_offset_in_bytes <= 0 || ! length $content) {
	    # The caller tried to rewind past the beginning of the file.
        # Start from the beginning of the file.  Don't write a jumpfile;
        # just use the path of the original file.
	    $self->output_path($self->input_path);
	    print STDERR "Using input file as jumpfile\n" if $debug;
	    $self->file_length($input_bytes);
    } else {
        print $out_fh $content;
	    print STDERR "Wrote greater-than-zero-length file\n" if $debug;
	    $self->file_length(length $content);
    }

    close $out_fh;

    # make file world-readable
    chmod 0644, $self->output_path;

    return;
}

sub length {
    my ($self) = @_;
    my $bytes = -l $self->output_path
                 ? (lstat $self->output_path)[7]
                 : (stat $self->output_path)[7];
    return $bytes;
}

sub is_empty {
    my ($self) = @_;
    return $self->length == 0;
}

no Moose;
__PACKAGE__->meta->make_immutable;
