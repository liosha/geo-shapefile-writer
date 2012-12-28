#!/usr/bin/perl

use 5.010;
use strict;
use warnings;
use utf8;

use Test::More;
use File::Temp;

use Geo::Shapefile::Writer;

my $dir = File::Temp->newdir();
my $dirname = $dir->dirname();

my $name = 'summits';

my $s = Geo::Shapefile::Writer->new(
    "$dirname/$name", 'POINT',
    [ name => 'C', 100 ],
    [ elevation => 'N', 8, 0 ],
);

$s->add_shape( [86.925278, 27.988056], 'Everest', 8848 );
$s->add_shape( [42.436944, 43.353056], { name => 'Elbrus', elevation => 5642 } );
$s->finalize();

for my $ext ( qw/ shp shx dbf / ) {
    ok( (-s "$dirname/$name.$ext"), lc($ext) . " created" );
}

done_testing();



