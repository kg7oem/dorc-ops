use strict;
use warnings;
use v5.10;

use Module::Build;

my $build = Module::Build->new(
    module_name => "DORC::Ops",
    dist_abstract => "D.O.R.C. Ops Libraries and Tools",
    requires => {
        "Dancer2" => 0,
        "Data::Section" => 0,
        "Net::DBus" => 0,
        "Plack" => 0,
        "Template" => 0,
    },
);

$build->create_build_script;
