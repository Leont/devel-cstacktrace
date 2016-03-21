use strict;
use warnings;
use Module::Build;

my @extra_linker_flags = $^O =~ m/ ^ (?! gnuk) .* bsd $ /xmsi ? qw/-lexecinfo/ : ();

my $builder = Module::Build->new(
  module_name         => 'Devel::cst',
  ##{ $plugin->get_prereqs(1) ##}
  ##{ $plugin->get_default('share_dir') ##}
  extra_linker_flags  => \@extra_linker_flags,
);

$builder->create_build_script();
