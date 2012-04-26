use 5.010;
use strict;
use warnings;

package Geo::Shapefile::Writer;
# ABSTRACT: simple pureperl shapefile writer

# $Id$

use utf8;
use autodie;
use Carp;

use XBase;
use List::Util qw/ min max /;



my %shape_type = (
    # extend
    NULL        => 0,
    POINT       => 1,
    POLYLINE    => 3,
    POLYGON     => 5,
);


=method new
    
    my $shp_writer = Geo::Shapefile::Writer->new( $name, $type, @dbf_fields );

Constructor.
Creates object and 3 associated files

=cut

sub new {
    my $class = shift;
    my ($name, $type, @dbf_fields) = @_;

    my $shape_type = $shape_type{ uc($type || q{}) };
    croak "Invalid shape type: $type"  if !defined $shape_type;

    my $self = bless {
        NAME     => $name,
        TYPE     => $shape_type,
        RCOUNT   => 0,
        SHP_SIZE => 50,
        SHX_SIZE => 50,
    }, $class;

    my $header_data = $self->_get_header('SHP');

    open $self->{SHP}, '>:raw', "$name.shp";
    print {$self->{SHP}} $header_data; 

    open $self->{SHX}, '>:raw', "$name.shx";
    print {$self->{SHX}} $header_data; 

    unlink "$name.dbf"  if -f "$name.dbf";
    $self->{DBF} = XBase->create( name => "$name.dbf",
        field_names     => [ map { $_->{name} } @dbf_fields ],
        field_types     => [ map { $_->{type} } @dbf_fields ],
        field_lengths   => [ map { $_->{length} } @dbf_fields ],
        field_decimals  => [ map { $_->{decimals} } @dbf_fields ],
    );

    return $self;
}


{
my $header_size = 100;
# position, pack_type, object_field, default
my @header_fields = (
    [ 0,  'N', undef,   9994 ], # magic
    [ 24, 'N', _SIZE => $header_size / 2 ], # file size in 16-bit words
    [ 28, 'L', undef,   1000 ], # version
    [ 32, 'L', 'TYPE' ],
    [ 36, 'd', 'XMIN' ],
    [ 40, 'd', 'YMIN' ],
    [ 44, 'd', 'XMAX' ],
    [ 48, 'd', 'YMAX' ],
);

sub _get_header {
    my ($self, $file_type) = @_;

    my @use_fields =
        grep { defined $_->[2] }
        map {[ $_->[0], $_->[1], $_->[2] && ($self->{$_->[2]} // $self->{"$file_type$_->[2]"}) // $_->[3] ]}
        @header_fields;

    my $pack_string = join q{ }, map { sprintf '@%d%s', @$_ } (@use_fields, [$header_size, q{}]);
    return pack $pack_string, map { $_->[2] } @use_fields;
}
}


=method add_shape

    $shp_writer->add_shape( $object, @attributes );

=cut

sub add_shape {
    my ($self, $data, @attributes) = @_;

    my ($xmin, $ymin, $xmax, $ymax);

    my $rdata;
    given ( $self->{TYPE} ) {
        when ( $shape_type{NULL} ) {
            $rdata = pack( 'L', $self->{TYPE} );
        }

        when ( $shape_type{POINT} ) {
            $rdata = pack( 'Ldd', $self->{TYPE}, @$data );
            ($xmin, $ymin, $xmax, $ymax) = ( @$data, @$data );
        }

        when ( [ @shape_type{'POLYLINE','POLYGON'} ] ) {
            my $rpart = q{};
            my $rpoint = q{};
            my $ipoint = 0;

            for my $line ( @$data ) {
                $rpart .= pack 'L', $ipoint;
                for my $point ( @$line ) {
                    my ($x, $y) = @$point;
                    $rpoint .= pack 'dd', $x, $y;
                    $ipoint ++;
                }
            }

            $xmin = min map {$_->[0]} map {@$_} @$data;
            $ymin = min map {$_->[1]} map {@$_} @$data;
            $xmax = max map {$_->[0]} map {@$_} @$data;
            $ymax = max map {$_->[1]} map {@$_} @$data;

            $rdata = pack 'LddddLL', $self->{TYPE}, $xmin, $ymin, $xmax, $ymax, scalar @$data, $ipoint;
            $rdata .= $rpart . $rpoint;
        }
    }

    $self->{DBF}->set_record( $self->{RCOUNT}, @attributes );
    $self->{RCOUNT} ++;

    print {$self->{SHX}} pack 'NN', $self->{SHP_SIZE}, length($rdata)/2;
    $self->{SHX_SIZE} += 4;

    print {$self->{SHP}} pack 'NN', $self->{RCOUNT}, length($rdata)/2;
    print {$self->{SHP}} $rdata;
    $self->{SHP_SIZE} += 4+length($rdata)/2;

    $self->{XMIN} = min grep {defined} ($xmin, $self->{XMIN});
    $self->{YMIN} = min grep {defined} ($ymin, $self->{YMIN});
    $self->{XMAX} = max grep {defined} ($xmax, $self->{XMAX});
    $self->{YMAX} = max grep {defined} ($ymax, $self->{YMAX});

    return $self;
}


=merhod finalize

    $shp_writer->finalize();

Update global fields, close files

=cut

sub finalize {
    my $self = shift;

    my $shp = $self->{SHP};
    seek $shp, 0, 0;
    print {$shp} $self->_get_header('SHP');
    close $shp;

    my $shx = $self->{SHX};
    seek $shx, 0, 0;
    print {$shx} $self->_get_header('SHX');
    close $shx;

    $self->{DBF}->close();

    return;
}

1;