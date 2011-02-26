
use strict;
use warnings;



use ExtUtils::MakeMaker 6.31;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'Form Based Authentication for Plack (think CatalystX::Simple)',
  'AUTHOR' => 'Zbigniew Lukasiak <zby@cpan.org>',
  'BUILD_REQUIRES' => {
    'Data::Dumper' => '0',
    'Test::More' => '0',
    'Test::WWW::Mechanize::PSGI' => '0'
  },
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.31'
  },
  'DISTNAME' => 'Plack-Middleware-Login',
  'EXE_FILES' => [],
  'LICENSE' => 'artistic_2',
  'NAME' => 'Plack::Middleware::Login',
  'PREREQ_PM' => {
    'Plack::Middleware' => '0',
    'Plack::Request' => '0',
    'Plack::Util::Accessor' => '0',
    'Scalar::Util' => '0',
    'parent' => '0'
  },
  'VERSION' => '0.001',
  'test' => {
    'TESTS' => 't/*.t'
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



