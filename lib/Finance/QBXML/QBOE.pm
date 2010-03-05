#---------------------------------------------------------------------
package Finance::QBXML::QBOE;
#
# Copyright 2010 Christopher J. Madsen
#
# Author: Christopher J. Madsen <perl@cjmweb.net>
# Created: February 2, 2010
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either the
# GNU General Public License or the Artistic License for more details.
#
# ABSTRACT: Interface to QuickBooks Online Edition
#---------------------------------------------------------------------

use 5.008;
use Moose;
use MooseX::Types::Moose qw(ArrayRef Bool CodeRef HashRef Int Num Object Str);

extends 'Finance::QBXML';

use Carp qw(croak);
use List::Util qw(min);
use LWP::UserAgent;
use Scalar::Util 'reftype';
#use Smart::Comments '###';

=head1 DEPENDENCIES

Finance::QBXML::QBOE requires L<Finance::QBXML>, L<File::ShareDir>,
L<LWP::UserAgent>, and L<Net::SSL>.  These are all available from
CPAN.

=cut

#=====================================================================
# Package Global Variables:

our $VERSION = '0.01';

# Times (in seconds) after which a session ticket expires:
our $session_expire_after_issue = 24 * 60 * 60 - 10;
our $session_expire_after_use   =  1 * 60 * 60 - 10;

#=====================================================================
# Package Finance::QBXML::QBOE:
#---------------------------------------------------------------------
# Inherited attributes:

=attr-in version

Finance::QBXML::QBOE changes the default value for Finance::QBXML's
C<version> attribute to C<6.0>, because that's the higest version
currently supported by QuickBooks Online Edition.

=cut

has '+version' => (
  default => '6.0',             # Maximum currently supported by QBOE
);

#---------------------------------------------------------------------
# HTTPS attributes:

=attr-http url

The URL of the QBOE gateway
(default L<https://webapps.quickbooks.com/j/AppGateway>).

=attr-http cert_file

The path of the file containing the client certificate.  Required.

=attr-http key_file

The path of the file containing the client's private key.  Required.

=attr-http ca_file

The path of the file containing the certificate authority's signing
certificate (defaults to the copy of F<VeriSignClass3SecureServerCA.pem>
included with this module).

=attr-http ua

The L<LWP::UserAgent> to use for the connection.  The default is to
create a new UserAgent and set it to perform certificate validation.
You shouldn't override the default unless you know what you're doing.

=cut

has url => (
  is      => 'ro',
  isa     => Str,
  default => 'https://webapps.quickbooks.com/j/AppGateway',
);

has cert_file => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

has key_file => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

has ca_file => (
  is       => 'ro',
  isa      => Str,
  builder  => '_build_ca_file',
);

sub _build_ca_file
{
  require File::ShareDir;

  File::ShareDir::dist_file('Finance-QBXML-QBOE',
                            'VeriSignClass3SecureServerCA.pem');
} # end _build_ca_file

has ua => (
  is      => 'ro',
  isa     => Object,            # Normally, LWP::UserAgent
  lazy    => 1,
  builder => '_build_ua',
);

sub _build_ua
{
  my $self = shift;

  my $ua = LWP::UserAgent->new;

  require Net::HTTPS;
  croak "You must use Net::SSL with LWP in order to validate certificates"
      unless $Net::HTTPS::SSL_SOCKET_CLASS eq 'Net::SSL';

=diag C<< You must use Net::SSL with LWP in order to validate certificates >>

LWP can normally use either Net::SSL or IO::Socket::SSL to handle
HTTPS connections, but Finance::QBXML::QBOE requires you to use
Net::SSL in order to properly validate the server's certificate and
provide the client certificate required by QBOE.

=diag C<< No hostname in URL: %s >>

You specified an invalid URL for the L</url> attribute.

=cut

  $self->url =~ m!^https://([^/:]+)/!
      or confess "No hostname in URL: " . $self->url;

  my $hostname = $1;

  $ua->default_header(
    'If-SSL-Cert-Subject' =>
    qr!^/C=US/ST=[^/=]*/L=[^/=]*/O=Intuit/OU=[^/=]*/CN=\Q$hostname\E$!
  );

  return $ua;
} # end _build_ua

#---------------------------------------------------------------------
# Session attributes:

=attr-sess session_ticket

The current session ticket, if any.  You can clear this with the
L</clear_session> method, or set it with the L</set_session> method.

=method clear_session

  $qb->clear_session

Clears out any existing session information.  The next request will
open a new session.

=attr-sess connection_ticket

The current connection ticket, if any.  This attribute is read/write,
and setting it automatically clears any existing session.

=attr-sess session_issue_expiration

The time at which the session should be considered expired based on
the time it was originally issued.

=attr-sess session_use_expiration

The time at which the session should be considered expired based on
the last time it was used.

=method session_expiration

  $time = $qb->session_expiration

This returns the smaller of L</session_issue_expiration> and
L</session_use_expiration>.

=cut

has session_ticket => (
  is       => 'ro',
  isa      => Str,
  writer   => '_set_session_ticket',
  clearer  => 'clear_session',
);

has connection_ticket => (
  is       => 'rw',
  isa      => Str,
  trigger  => \&clear_session,
);

has session_issue_expiration => (
  is       => 'ro',
  isa      => Int,
  writer   => '_set_session_issue_expiration',
);

has session_use_expiration => (
  is       => 'ro',
  isa      => Int,
  writer   => '_set_session_use_expiration',
);

sub session_expiration
{
  my $self = shift;

  min($self->session_issue_expiration,
      $self->session_use_expiration);
} # end session_expiration

#---------------------------------------------------------------------
# Application attributes:

=attr-app application_login

This is your C<ApplicationLogin> for QBOE.  Required.

=attr-app app_id

This is your C<AppID> for QBOE.  Required.

=attr-app app_ver

This is your C<AppVer> for QBOE (default 1).

=attr-app language

This is your C<Language> for QBOE (default C<English>).

=cut

has application_login => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

has app_id => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

has app_ver => (
  is       => 'ro',
  isa      => Str,
  default  => '1',
);

has language => (
  is       => 'ro',
  isa      => Str,
  default  => 'English',
);
#---------------------------------------------------------------------

=method set_session

  $qb->set_session($session_ticket, $issue_exp, $use_exp)

You can use this method to provide a session ticket for QBOE.  If
either C<$issue_exp> or C<$use_exp> is omitted or C<undef>, the value
will be calculated based on the current time.

C<$session_ticket> is assigned to the L</session_ticket> attribute,
C<$issue_exp> to L</session_issue_expiration>, and C<$use_exp> to
L</session_use_expiration>.

You don't normally need to use this method, as the automatic session
management will call it for you.  But if you want to save a session
ticket for later, just store those 3 attributes and return them to
C<set_session> later.

A session ticket normally expires 1 hour after its last use, or
24 hours after it was first issued, whichever comes first.

=diag C<< Invalid session ticket >>

You tried to pass an empty session ticket to L</set_session>.

=cut

sub set_session
{
  my ($self, $ticket, $issue, $use) = @_;

  croak 'Invalid session ticket' unless defined $ticket and length $ticket;

  $issue ||= time() + $session_expire_after_issue;
  $use   ||= time() + $session_expire_after_use;

  $self->_set_session_issue_expiration($issue);
  $self->_set_session_use_expiration($use);
  $self->_set_session_ticket($ticket);
} # end set_session
#---------------------------------------------------------------------

=method valid_session

  $is_valid = $qb->valid_session

Returns true if the L</session_ticket> is set and has not yet expired,
false otherwise.

=cut

sub valid_session
{
  my $self = shift;

  $self->session_ticket and time() <= $self->session_expiration;
} # end valid_session
#---------------------------------------------------------------------

=method acquire_sesion

  $qb->acquire_sesion

This method is normally called automatically when needed.  It sends
the L</connection_ticket> to QBOE and requests a session ticket.

It throws an exception if it is unable to acquire a sesion ticket for
any reason.

=diag C<< The connection_ticket has not been set >>

You called L</make_request> (or L</acquire_sesion>) before setting
the L</connection_ticket>.

=diag C<< Unable to get session ticket: %s >>

An error occured while trying to acquire a session ticket.

=cut

sub acquire_sesion
{
  my $self = shift;

  my $xmlOut = $self->format_XML({SignonMsgsRq => {SignonAppCertRq => {
    ClientDateTime   => $self->time2iso,
    ApplicationLogin => $self->application_login,
    ConnectionTicket => $self->connection_ticket
      || croak "The connection_ticket has not been set",
    Language         => $self->language,
    AppID            => $self->app_id,
    AppVer           => $self->app_ver,
  }}});

  my $rsp = $self->post_request($xmlOut);

  croak "Unable to get session ticket: " . $rsp->status_line
      unless $rsp->is_success;

  my $data = $self->get_parser->parse_string($rsp->content);

  $self->set_session(
    $data->{SignonMsgsRs}{SignonAppCertRs}{SessionTicket}
  );
} # end acquire_sesion
#---------------------------------------------------------------------

=method post_request

  $rsp = $qb->post_request($xml)

This is the low-level function that posts a qbXML message to the QBOE
server and returns a L<HTTP::Response>.  You wouldn't normally call it
directly.

=cut

sub post_request
{
  my ($self, $req) = @_;

  ### Request: $req

  local $ENV{HTTPS_CERT_FILE} = $self->cert_file;
  local $ENV{HTTPS_KEY_FILE}  = $self->key_file;
  local $ENV{HTTPS_CA_FILE}   = $self->ca_file;

  my $rsp = $self->ua->post($self->url, 'Content-Type' => 'application/x-qbxml',
                            Content => $req);

  ### Response: $rsp->as_string

  $rsp;
} # end post_request
#---------------------------------------------------------------------

=method make_request

  $response = $qb->make_request($request)

This is the primary method provided by Finance::QBXML::QBOE.  It takes
a data structure representing a qbXML request (something that would be
accepted by L<Finance::QBXML/format_XML>), converts it to XML, sends
that to QBOE, and parses the response, returning a hashref
representing the qbXML response.  It also updates the
L</session_use_expiration> attribute.

If C<$request> does not contain a C<SignonMsgsRq> element, one is
automatically added using the current session information.  (If there
is no current session, it calls L</acquire_sesion> first.)

As a shortcut, passing an arrayref as C<$request> is equivalent to passing
C<< { QBXMLMsgsRq => $request } >>.

=diag C<< Request failed: %s >>

An error occured while trying to read the response from the server.

=cut

sub make_request
{
  my ($self, $req) = @_;

  if (reftype($req) eq 'ARRAY') {
    $req = { QBXMLMsgsRq => $req };
  }

  unless ($req->{SignonMsgsRq}) {
    $self->acquire_sesion unless $self->valid_session;

    $req->{SignonMsgsRq}{SignonTicketRq} = {
      ClientDateTime   => $self->time2iso,
      SessionTicket    => $self->session_ticket,
      Language         => $self->language,
      AppID            => $self->app_id,
      AppVer           => $self->app_ver,
    };
  }

  my $xmlOut = $self->format_XML($req);

  my $rsp = $self->post_request($xmlOut);

  croak "Request failed: " . $rsp->status_line
      unless $rsp->is_success;

  $self->_set_session_use_expiration(time() + $session_expire_after_use);

  return $self->get_parser->parse_string($rsp->content);
} # end make_request

#=====================================================================
# Package Return Value:

no Moose;
__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 SYNOPSIS

    use Finance::QBXML::QBOE;

    my $qb = Finance::QBXML->new(
      application_login => 'abc', app_id => 1234,
      cert_file => 'client.crt', key_file => 'client.key',
      connection_ticket => 'xyz',
    );

    my $rsp = $qb->make_request([{ _tag => 'CompanyQueryRq' }]);


=head1 DESCRIPTION

Finance::QBXML::QBOE extends L<Finance::QBXML> with methods to
interface with QuickBooks Online Edition
(L<http://quickbooksonline.intuit.com>), including automatic session
management.

You just construct a Finance::QBXML::QBOE object, giving it the
connection ticket, and call the L</make_request> method.  The object
will acquire a sesion ticket as necessary, and convert to and from
qbXML automatically.

=for Pod::Loom-sort_method
new

=method new

  $qb = Finance::QBXML::QBOE->new(
    application_login => 'abc', app_id => 1234,
    cert_file => 'client.crt', key_file => 'client.key', ...
  );

This is the standard L<Moose|Moose::Object> constructor.

=begin Pod::Loom-group_attr in

=head2 Inherited Attributes

=begin Pod::Loom-group_attr app

=head2 Application Attributes

=begin Pod::Loom-group_attr http

=head2 HTTPS Attributes

=begin Pod::Loom-group_attr sess

=head2 Session Management Attributes

