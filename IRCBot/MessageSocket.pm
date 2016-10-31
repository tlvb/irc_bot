use warnings;
use strictures 2;

package IRCBot::MessageSocket;

use IO::Socket::SSL;
use IO::Socket::INET;
use IO::Select;
use Try::Tiny;

use IRCBot::DayLog;
use IRCBot::Message;

our $Socket_Error = '';

sub new { #{{{
	# pass everything but the class as creation arguments for the ssl socket
	my $class = shift;
	my %params = @_;
	my $use_ssl = $params{use_ssl} // 1;
	delete $params{use_ssl};

	my $socket = undef;
	if ($use_ssl) {
		$socket = IO::Socket::SSL->new(%params);
	}
	else {
		$socket = IO::Socket::INET->new(%params);
	}
	unless (defined $socket) {
		$Socket_Error = "Error in MessageSocket::new()\n    $!";
		if ($use_ssl) {
			$Socket_Error .= "\n    $SSL_ERROR";
		}
		return undef;
	}
	binmode $socket, ':encoding(UTF-8)';

	my $select = IO::Select->new($socket);

	my $self = {
		buffer=>'',
		socket=>$socket,
		select=>$select,
		ssl=>$use_ssl
	};

	bless $self, $class;
	return $self;
} #}}}
sub read_message { #{{{
	my $self = shift;
	my $timeout = shift;
	my ($ret, $ok) = $self->_read_line_timeout($timeout);
	return (IRCBot::Message->new($ret), $ok) if $ok and defined $ret;
	return ($ret, $ok);
} #}}}
sub write_message { #{{{
	my $self = shift;
	my $message = shift;
	$self->_write_line($message->deflate());
} #}}}
sub close { #{{{
	my $self = shift;
	try {
		$self->{socket}->close();
	}
} #}}}

sub _read_socket_to_buffer { #{{{
	my $self = shift;
	my $p = shift // 16384;

	# read into temp var, add temp var to buffer
	# this blocks until the socket has data, or
	# there is a connection error, in which case
	# we get no data
	my $r = $self->{socket}->sysread(my $tmp, $p);
	if (defined $r && $r > 0) {
		$self->{buffer} .= $tmp;
		return 1;
	}
	return undef;
} #}}}
sub _attempt_extract_line_from_buffer { #{{{
	# extract line from buffer if line is detected
	my $self = shift;
	if ($self->{buffer} =~ /\r\n/) {
		my $retval = undef;
		($retval, $self->{buffer}) = split "\r\n", $self->{buffer}, 2;
		return ($retval, 1);
	}
	return (undef, 0);
} #}}}
sub _read_line_timeout { #{{{
	my $self = shift;
	my $timeout = shift // 0;
	my $line = undef;
	my $ok = undef;

	($line, $ok) = $self->_attempt_extract_line_from_buffer();
	return ($line, $ok) if $ok;

	if ($self->{ssl}) {
		# check if we have data in the ssl buffer first
		# possibly return if a full \r\n delimited line
		# can be constructed
		my $p = $self->{socket}->pending();
		if ($p > 0) {
			my $ok = $self->_read_socket_to_buffer($p);
			if ($ok) {
				($line, $ok) = $self->_attempt_extract_line_from_buffer();
				return ($line, $ok) if $ok;
			}
			else {
				# no data from socket
				return ('no data from socket', undef);
			}
		}
	}

	# if we are still here, it means either that there were
	# no data pending in the ssl buffer, or that we read all
	# data there, but it was not enough to construct a full
	# line so we use select to wait for more data with a timeout
	if ($timeout >= 0) {
		my @cr = $self->{select}->can_read($timeout);
		if (0 == @cr) {
			return (undef, 1);
		}
	}
	$ok = $self->_read_socket_to_buffer();
	if ($ok) {
		($line, $ok) = $self->_attempt_extract_line_from_buffer();
		return ($line, $ok) if $ok;
		return (undef, 1);
	}
	else {
		return ('no data from socket', undef);
	}
} #}}}
sub _write_line { #{{{
	my $self = shift;
	my $line = shift;
	print {$self->{socket}} "$line\r\n";
} #}}}
1;
