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

has '+version' => (
  default => '6.0',             # Maximum currently supported by QBOE
);

#---------------------------------------------------------------------
# HTTPS attributes:

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

sub valid_session
{
  my $self = shift;

  $self->session_ticket and time() <= $self->session_expiration;
} # end valid_session
#---------------------------------------------------------------------

sub acquire_sesion
{
  my $self = shift;

  my $xmlOut = $self->format_XML({SignonMsgsRq => {SignonAppCertRq => {
    ClientDateTime   => $self->time2iso,
    ApplicationLogin => $self->application_login,
    ConnectionTicket => $self->connection_ticket,
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
