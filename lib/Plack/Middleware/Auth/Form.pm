use strict;
use warnings;
package Plack::Middleware::Auth::Form;
BEGIN {
  $Plack::Middleware::Auth::Form::VERSION = '0.001';
}

use feature ':5.10';

use parent qw/Plack::Middleware/;
use Plack::Util::Accessor qw( secure authenticator no_login_page after_logout );
use Plack::Request;
use Scalar::Util;

sub prepare_app {
    my $self = shift;

    my $auth = $self->authenticator or die 'authenticator is not set';
    if (Scalar::Util::blessed($auth) && $auth->can('authenticate')) {
        $self->authenticator(sub { $auth->authenticate(@_[0,1]) }); # because Authen::Simple barfs on 3 params
    } elsif (ref $auth ne 'CODE') {
        die 'authenticator should be a code reference or an object that responds to authenticate()';
    }
}

sub call {
    my($self, $env) = @_;
    my $path = $env->{PATH_INFO};

    if( $env->{'psgix.session'}{remember} ){
        if( $path ne '/logout' ){
            $env->{'psgix.session.options'}{expires} = time + 60 * 60 * 24 * 30;
        }
        delete $env->{'psgix.session'}{remember};
    }

    if( $path eq '/login' ){
        return $self->_login( $env );
    }
    elsif( $path eq '/logout' ){
        return $self->_logout( $env );
    }
    return $self->app->( $env );
}

sub _login {
    my($self, $env) = @_;
    my $login_error;
    if( $self->secure && $env->{'psgi.url_scheme'} ne 'https' ){
        my $server = $env->{X_FORWARDED_FOR} // $env->{X_HTTP_HOST} // $env->{SERVER_NAME};
        my $secure_url = "https://$server" . $env->{PATH_INFO};
        return [ 
            301, 
            { Location => $secure_url }, 
            [ "<html><body><a href=\"$secure_url\">Need a secure connection</a></body></html>" ]
        ];
    }
    my $params = Plack::Request->new( $env )->parameters;
    if( defined $env->{user} ){
        return 'Already logged in';
    }
    elsif( $env->{REQUEST_METHOD} eq 'POST' ){
        my $user_id;
        my $auth_result = $self->authenticator->( $params->get( 'username' ), $params->get( 'password' ), $env );
        if( ref $auth_result ){
            $login_error = $auth_result->{error};
            $user_id = $auth_result->{user_id};
        }
        else{
            $login_error = 'Wrong username or password' if !$auth_result;
            $user_id = $params->get( 'username' );
        }
        if( !$login_error ){
            $env->{'psgix.session'}{user_id} = $user_id;
            $env->{'psgix.session'}{remember} = 1 if $params->get( 'remember' );
            my $redir_to = delete $env->{'psgix.session'}{redir_to};
            $redir_to = '/' if 
                URI->new( $redir_to )->path eq $env->{PATH_INFO};
            return [ 
                302, 
                { Location => $redir_to }, 
                [ "<html><body><a href=\"$redir_to\">Back</a></body></html>" ]
            ];
        }
    }
    $env->{'psgix.session'}{redir_to} ||= $env->{HTTP_REFERER} || '/';
    my $form = $self->_render_form( 
        username => $params->get( 'username' ), 
        login_error => $login_error,
        redir_to => $env->{'psgix.session'}{redir_to},
    );
    if( $self->no_login_page ){
        $env->{SimpleLoginForm} = $form;
        return $self->app->( $env );
    }
    else{
         return [ 
            200, 
            { 'Content-Type' => 'text/html', },
            [ "<html><body>$form\nAfter login: $env->{'psgix.session'}{redir_to}</body></html>" ]
        ];
    }
}

sub _render_form {
    my $self = shift;
    my ( %params ) = @_;
    my $out = '';
    if( $params{login_error} ){
        $out .= qq{<div class="error">$params{login_error}</div>};
    }
    my $username = $params{username} // '';
    $out .= <<END;
<form id="login_form" method="post" > 
  <fieldset class="main_fieldset"> 
    <div><label class="label" for="username">Username: </label><input type="text" name="username" id="username" value="$username" /></div> 
    <div><label class="label" for="password">Password: </label><input type="password" name="password" id="password" value="" /></div> 
    <div><label class="label" for="remember">Remember: </label><input type="checkbox" name="remember" id="remember" value="1" /></div> 
    <div><input type="submit" name="submit" id="submit" value="Login" /></div> 
  </fieldset> 
</form>
END
    return $out;
}

sub _logout {
    my($self, $env) = @_;
    if( $env->{REQUEST_METHOD} eq 'POST' ){
        delete $env->{'psgix.session'}{user_id};
    }
    return [ 
        303, 
        { Location => $self->after_logout || '/' }, 
        [ "<html><body><a href=\"/\">Home</a></body></html>" ]
    ];
}

1;



=pod

=head1 NAME

Plack::Middleware::Auth::Form - Form Based Authentication for Plack (think CatalystX::Simple)

=head1 VERSION

version 0.001

=head1 SYNOPSIS

    builder {
        enable 'Session';
        enable 'Auth::Form', authenticator => \&check_pass;
        \&my_app
    }

=head1 DESCRIPTION

/login - a page with a login form
/logout - logouts the user (only on a POST) and redirects him to C<after_logout> or C</>.

After a succesful login the user is redirected back to url identified by 
the C<redir_to> session parameter.  It also sets that session parameter from
$env->{HTTP_REFERER} if it is not set or to C</> if even that is not available.
The username (or id) is saved to C<user_id> session parameter, if you want
to save an id different from the username - then you need to return
a hashref from the C<authenticator> callback described below.

If the login page looks too simplistic - the application can take over
displaying it by setting the C<no_login_page> attribute.  Then 
the the login form will be saved to C<<$env->{SimpleLoginForm}>>.

=head1 CONFIGURATION

=over 4

=item authenticator

A callback function that takes username and password supplied and
returns whether the authentication succeeds. Required.

Authenticator can also be an object that responds to C<authenticate>
method that takes username and password and returns boolean, so
backends for L<Authen::Simple> is perfect to use:

  use Authen::Simple::LDAP;
  enable "Auth::Form", authenticator => Authen::Simple::LDAP->new(...);

The callback can also return a hashref with two optional fields
C<error> - the reason for the failure and C<user_id> - the user id
to be saved in the session instead of the username.

=item no_login_page

Save the login form on C<<$env->{SimpleLoginForm}>> and let the 
application display the login page (for a GET request).

=item after_logout

Where to go after logout, by default '/'.

=back

=head1 SEE ALSO

L<Plack>

=head1 ACKNOWLEDGEMENTS

The C<authenticator> code and documentation copied from 
L<Plack::Middleware::Auth::Basic>.

=head1 AUTHOR

Zbigniew Lukasiak <zby@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2011 by Zbigniew Lukasiak <zby@cpan.org>.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut


__END__

# ABSTRACT: Form Based Authentication for Plack (think CatalystX::Simple)

